// Emails written in the admin panel, sent from an @easysesh.live address through Resend.
// Support staff send from support@; admins also from easysesh@ and noreply@; owners from any address.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin } from "../_shared/supabase.ts";
import { audit, requireStaff } from "../_shared/staff.ts";
import { sendStaffEmail } from "../_shared/email.ts";

const DOMAIN = "easysesh.live";
const EMAIL = /^[^\s@<>,;"]+@[^\s@<>,;"]+\.[a-z]{2,}$/i;

Deno.serve(handler(async (req, body) => {
  const staff = await requireStaff(req, "support");
  const local = requireString(body, "from").toLowerCase().replace(/@.*$/, "");
  const allowed = staff.admin_rank === "owner" ? null : staff.admin_rank === "admin" ? ["support", "easysesh", "noreply"] : ["support"];
  if (!/^[a-z0-9][a-z0-9._-]{0,40}$/.test(local) || (allowed && !allowed.includes(local))) {
    throw new HttpError(403, `You can send from ${(allowed ?? ["any"]).map((a) => `${a}@${DOMAIN}`).join(", ")}.`);
  }
  const to = (Array.isArray(body.to) ? body.to : String(body.to ?? "").split(/[,;\s]+/)).map((a) => String(a).trim()).filter(Boolean);
  if (to.length === 0 || to.length > 20 || !to.every((a) => EMAIL.test(a))) throw new HttpError(400, "Enter 1–20 valid email addresses.");
  const subject = requireString(body, "subject").trim().slice(0, 200);
  const text = requireString(body, "body").trim().slice(0, 20000);

  const { count } = await admin.from("admin_emails").select("id", { count: "exact", head: true }).gte("created_at", new Date(Date.now() - 86_400_000).toISOString());
  if ((count ?? 0) >= 300) throw new HttpError(429, "300 emails a day have been sent from the admin panel. Try again tomorrow.");

  const from = `${local}@${DOMAIN}`;
  const resendId = await sendStaffEmail(from, to, subject, text);
  if (resendId === null) throw new HttpError(502, "The email couldn't be sent. Check the Resend key and domain.");
  await admin.from("admin_emails").insert({
    sent_by: staff.id, sender_email: staff.email, from_address: from, to_addresses: to, subject, body: text, resend_id: resendId || null,
  });
  await audit(staff, "send_email", { table: "admin_emails" }, null, { from, to, subject });
  return json({ sent: true });
}));
