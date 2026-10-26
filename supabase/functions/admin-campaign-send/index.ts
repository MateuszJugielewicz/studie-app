// Owners only: sends an email campaign written in the admin panel. Each recipient gets their own
// email (never a shared To/CC), with {{name}}, {{city}} and {{website}} filled in.
//   { campaign_id, mode: "test" }            → one test email to the owner's own address
//   { campaign_id, mode: "batch", limit: n } → the next n pending recipients (max 50 per call)
// Addresses on email_suppressions are skipped. A daily cap protects the Resend quota, which the
// booking emails share (CAMPAIGN_DAILY_LIMIT, default 80 emails per 24 hours from the admin panel).
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin } from "../_shared/supabase.ts";
import { audit, requireStaff } from "../_shared/staff.ts";
import { sendCampaignEmail } from "../_shared/email.ts";

const DOMAIN = "easysesh.live";
const DAILY_LIMIT = Number(Deno.env.get("CAMPAIGN_DAILY_LIMIT") ?? 80);
const DEFAULT_FOOTER = "Sent by EasySesh – easysesh.live";

type Recipient = { id: string; email: string; name: string; city: string; website: string };

const fill = (template: string, r: Pick<Recipient, "name" | "city" | "website">) =>
  template.replace(/\{\{\s*(name|city|website)\s*\}\}/gi, (_, key: string) => r[key.toLowerCase() as "name" | "city" | "website"] ?? "");

Deno.serve(handler(async (req, body) => {
  const staff = await requireStaff(req, "owner");
  const campaignId = requireString(body, "campaign_id");
  const mode = body.mode === "test" ? "test" : body.mode === "batch" ? "batch" : null;
  if (!mode) throw new HttpError(400, "Unknown mode.");

  const { data: campaign } = await admin.from("email_campaigns").select("*").eq("id", campaignId).maybeSingle();
  if (!campaign) throw new HttpError(404, "Campaign not found.");
  if (!campaign.subject.trim() || !campaign.body.trim()) throw new HttpError(400, "Write a subject and a message first.");
  const from = `${campaign.from_local}@${DOMAIN}`;
  const footer = campaign.footer.trim() || DEFAULT_FOOTER;

  if (mode === "test") {
    const { data: first } = await admin.from("email_campaign_recipients").select("name, city, website")
      .eq("campaign_id", campaignId).order("created_at").limit(1).maybeSingle();
    const sample = first ?? { name: "Studio", city: "København", website: "" };
    const id = await sendCampaignEmail(from, staff.email!, `[Test] ${fill(campaign.subject, sample)}`, fill(campaign.body, sample), fill(footer, sample));
    if (id === null) throw new HttpError(502, "The test email couldn't be sent. Check the Resend key and domain.");
    return json({ sent: 1, to: staff.email });
  }

  // Daily cap across the admin panel (single emails and campaigns).
  const since = new Date(Date.now() - 86_400_000).toISOString();
  const { count } = await admin.from("admin_emails").select("id", { count: "exact", head: true }).gte("created_at", since);
  const room = DAILY_LIMIT - (count ?? 0);
  if (room <= 0) throw new HttpError(429, `${DAILY_LIMIT} emails have been sent from the admin panel in the last 24 hours. Try again tomorrow.`);
  const limit = Math.max(1, Math.min(50, Number(body.limit) || 20, room));

  const { data: recipients, error } = await admin.from("email_campaign_recipients").select("id, email, name, city, website")
    .eq("campaign_id", campaignId).eq("status", "pending").order("created_at").limit(limit);
  if (error) throw new HttpError(500, error.message);
  const list = (recipients ?? []) as Recipient[];

  const { data: suppressed } = await admin.from("email_suppressions").select("email").in("email", list.map((r) => r.email.toLowerCase()));
  const blocked = new Set((suppressed ?? []).map((s) => s.email));

  await admin.from("email_campaigns").update({ status: "sending" }).eq("id", campaignId);
  let sent = 0, failed = 0, skipped = 0;
  for (const r of list) {
    if (blocked.has(r.email.toLowerCase())) {
      await admin.from("email_campaign_recipients").update({ status: "skipped", error: "Asked not to be contacted" }).eq("id", r.id);
      skipped++;
      continue;
    }
    const subject = fill(campaign.subject, r).slice(0, 200);
    const text = fill(campaign.body, r);
    const id = await sendCampaignEmail(from, r.email, subject, text, fill(footer, r));
    if (id === null) {
      await admin.from("email_campaign_recipients").update({ status: "failed", error: "Resend refused the email" }).eq("id", r.id);
      failed++;
      continue;
    }
    sent++;
    await admin.from("email_campaign_recipients").update({ status: "sent", resend_id: id || null, sent_at: new Date().toISOString(), error: null }).eq("id", r.id);
    await admin.from("admin_emails").insert({
      sent_by: staff.id, sender_email: staff.email, from_address: from, to_addresses: [r.email], subject, body: text, resend_id: id || null,
    });
    // Resend allows a few requests per second.
    await new Promise((resolve) => setTimeout(resolve, 600));
  }

  const { count: left } = await admin.from("email_campaign_recipients").select("id", { count: "exact", head: true })
    .eq("campaign_id", campaignId).eq("status", "pending");
  if (!left) await admin.from("email_campaigns").update({ status: "done" }).eq("id", campaignId);
  await audit(staff, "send_campaign_batch", { table: "email_campaigns", id: campaignId }, null, { sent, failed, skipped, from });
  return json({ sent, failed, skipped, left: left ?? 0 });
}));
