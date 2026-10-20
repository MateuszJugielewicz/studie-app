// Transactional emails (booking confirmations, studio approval, email verification) from noreply@easysesh.live via Resend
// (https://resend.com). The API key comes from the RESEND_API_KEY secret or, failing that, from
// Supabase Vault ('resend_api_key', via the service-role-only resend_api_key() function); without
// a key nothing is sent. Replies go to support.
import { admin } from "./supabase.ts";

const METHOD_TITLES: Record<string, string> = {
  card: "Card", apple_pay: "Apple Pay", google_pay: "Google Pay", link: "Link", paypal: "PayPal", klarna: "Klarna",
  mobilepay: "MobilePay", ideal: "iDEAL", bancontact: "Bancontact", blik: "BLIK", eps: "EPS", revolut_pay: "Revolut Pay",
};
const methodTitle = (method?: string | null) => METHOD_TITLES[method ?? ""] ?? "Online payment";

const FROM = Deno.env.get("EMAIL_FROM") ?? "EasySesh <noreply@easysesh.live>";
const REPLY_TO = Deno.env.get("EMAIL_REPLY_TO") ?? "support@easysesh.live";
const SITE = (Deno.env.get("SITE_URL") ?? "https://easysesh.live").replace(/\/+$/, "");

/** Notification kinds that also go out by email. */
export const EMAIL_KINDS = new Set([
  "booking_confirmed", "booking_requested", "booking_declined", "booking_cancelled", "booking_changed", "refund_issued",
  "studio_approved", "studio_rejected", "studio_changes_requested",
]);

const escape = (text: unknown) =>
  String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

function money(minor: number, currency: string) {
  return new Intl.NumberFormat("en-GB", { style: "currency", currency }).format((minor ?? 0) / 100);
}

function when(startsAt: string, endsAt: string, timeZone: string) {
  const day = new Intl.DateTimeFormat("en-GB", { timeZone, weekday: "long", day: "numeric", month: "long", year: "numeric" });
  const time = new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit" });
  return `${day.format(new Date(startsAt))}, ${time.format(new Date(startsAt))}–${time.format(new Date(endsAt))}`;
}

let cachedKey: string | null = null;

async function resendKey(): Promise<string | null> {
  if (cachedKey) return cachedKey;
  const fromEnv = Deno.env.get("RESEND_API_KEY");
  if (fromEnv) return (cachedKey = fromEnv);
  const { data, error } = await admin.rpc("resend_api_key");
  if (error) console.error("Resend key lookup failed", error.message);
  cachedKey = (data as string | null) || null;
  return cachedKey;
}

async function send(to: string | string[], subject: string, html: string, text: string, from = FROM, replyTo = REPLY_TO): Promise<boolean> {
  return (await sendWithId(to, subject, html, text, from, replyTo)) !== null;
}

/** Sends through Resend; returns Resend's email id, or null when it failed or no key is set. */
async function sendWithId(to: string | string[], subject: string, html: string, text: string, from = FROM, replyTo = REPLY_TO): Promise<string | null> {
  const key = await resendKey();
  if (!key) return null;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({ from, to: Array.isArray(to) ? to : [to], reply_to: replyTo, subject, html, text }),
  });
  if (!response.ok) {
    console.error("Email failed", response.status, await response.text());
    return null;
  }
  return ((await response.json()) as { id?: string }).id ?? "";
}

/** The EasySesh email layout: logo, a card with title, text, optional detail rows and a button. */
function render(o: { title: string; body: string; rows?: [string, string][]; button?: string; link?: string; footer: string; after?: string; replyTo?: string }) {
  const rows = o.rows ?? [];
  const table = rows.map(([k, v]) =>
    `<tr><td style="padding:6px 0;color:#6f6c66;width:110px;vertical-align:top">${escape(k)}</td><td style="padding:6px 0;color:#1c1b19">${escape(v)}</td></tr>`).join("");
  const html = `<!doctype html><html><body style="margin:0;background:#f5f5f4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
<div style="max-width:520px;margin:0 auto;padding:28px 16px">
  <table role="presentation" cellpadding="0" cellspacing="0" style="border-collapse:collapse"><tr>
    <td style="vertical-align:middle"><img src="${SITE}/email-logo.png" width="40" height="40" alt="EasySesh" style="display:block;border:0;border-radius:10px"></td>
    <td style="vertical-align:middle;padding-left:10px;font-weight:800;font-size:22px;letter-spacing:-0.03em;color:#1c1b19">easysesh<span style="color:#d9431e">.</span></td>
  </tr></table>
  <div style="background:#fff;border:1px solid #e4e3e0;border-radius:16px;padding:22px;margin-top:16px">
    <h1 style="font-size:20px;margin:0 0 8px;color:#1c1b19">${escape(o.title)}</h1>
    <p style="margin:0 0 16px;color:#3a3935;line-height:1.5;white-space:pre-line">${escape(o.body)}</p>
    ${table ? `<table style="width:100%;border-collapse:collapse;font-size:14px;border-top:1px solid #eee;margin-bottom:18px">${table}</table>` : ""}
    ${o.button && o.link ? `<a href="${escape(o.link)}" style="display:inline-block;background:#d9431e;color:#fff;text-decoration:none;font-weight:600;padding:11px 18px;border-radius:10px">${escape(o.button)}</a>` : ""}
    ${o.after ? `<p style="margin:16px 0 0;font-size:13px;color:#6f6c66;line-height:1.5;word-break:break-all">${escape(o.after)}</p>` : ""}
  </div>
  <p style="font-size:12px;color:#8a877f;line-height:1.5;margin:16px 4px 0">${escape(o.footer)} Questions? Reply to this email or write to ${escape(o.replyTo ?? REPLY_TO)}.</p>
</div></body></html>`;
  const text = [o.title, "", o.body, "", ...rows.map(([k, v]) => `${k}: ${v}`), ...(o.button && o.link ? ["", `${o.button}: ${o.link}`] : []), ...(o.after ? ["", o.after] : []), "", `Questions? ${o.replyTo ?? REPLY_TO}`].join("\n");
  return { html, text };
}

const STUDIO_KINDS = new Set(["studio_approved", "studio_rejected", "studio_changes_requested"]);

// deno-lint-ignore no-explicit-any
export async function sendNotificationEmail(note: any, email: string | null | undefined): Promise<boolean> {
  if (!EMAIL_KINDS.has(note.kind) || !email || email.endsWith(".invalid") || !(await resendKey())) return false;

  if (STUDIO_KINDS.has(note.kind)) {
    const approved = note.kind === "studio_approved";
    const { html, text } = render({
      title: note.title,
      body: approved ? `${note.body}\n\nArtists can now find your studio and book sessions on EasySesh.` : note.body,
      button: approved ? "Open your studio" : "Update your listing",
      link: approved ? `${SITE}/studio` : `${SITE}/studio/edit`,
      footer: "You're getting this email because you listed a studio on EasySesh.",
    });
    return send(email, `${note.title} – EasySesh`, html, text);
  }

  const rows: [string, string][] = [];
  let link = `${SITE}/sessions`;
  if (note.booking_id) {
    const { data: b } = await admin.from("bookings").select("*").eq("id", note.booking_id).maybeSingle();
    if (b) {
      const { data: studio } = await admin.from("studios").select("timezone, address").eq("id", b.studio_id).maybeSingle();
      const zone = studio?.timezone || "Europe/Athens";
      link = `${SITE}/sessions/${b.id}`;
      rows.push(
        ["Reference", b.reference],
        ["Studio", b.studio_name],
        ["Artist", b.artist_name],
        ["Session", `${b.session_type_name} · ${b.hours} h`],
        ["When", when(b.starts_at, b.ends_at, zone)],
        ["Total", money(b.price?.total, b.price?.currency ?? "EUR")],
        ["Payment", b.payment_method === "cash" ? "Cash at the studio"
          : b.payment_status === "authorized" ? `${methodTitle(b.payment_method)} (charged when the studio accepts)` : methodTitle(b.payment_method)],
      );
      const address = studio?.address;
      if (address?.street) rows.push(["Address", [address.street, address.postal_code, address.city].filter(Boolean).join(", ")]);
    }
  }

  const { html, text } = render({
    title: note.title, body: note.body, rows, button: "View booking", link,
    footer: "You're getting this email because of a booking on EasySesh.",
  });
  return send(email, `${note.title} – EasySesh`, html, text);
}

/** "Confirm your email" with a one-time link (valid 7 days) to easysesh.live/verify-email. */
export async function sendVerificationEmail(email: string, token: string, role: string, name: string): Promise<boolean> {
  if (!email || email.endsWith(".invalid") || !(await resendKey())) return false;
  const link = `${SITE}/verify-email?token=${encodeURIComponent(token)}`;
  const hello = name ? `Hi ${name},` : "Hi,";
  const what = role === "studio_owner"
    ? "Confirm your email address to send your studio for approval and talk to artists."
    : "Confirm your email address to book sessions and message studios.";
  const { html, text } = render({
    title: "Confirm your email",
    body: `${hello}\n\nWelcome to EasySesh! ${what}`,
    button: "Confirm email",
    link,
    after: `The link works for 7 days. If the button doesn't work, open this link: ${link}`,
    footer: "You're getting this email because someone signed up to EasySesh with this address. If it wasn't you, you can ignore it.",
  });
  return send(email, "Confirm your email – EasySesh", html, text);
}

/** "Changes to your account": what the EasySesh team changed, why, and how to object (reply to support@). */
export async function sendAccountChangeEmail(email: string, changes: string[], reason: string | null): Promise<boolean> {
  if (!email || email.endsWith(".invalid") || !(await resendKey())) return false;
  const list = changes.map((c) => `• ${c}`).join("\n");
  const { html, text } = render({
    title: "Changes to your account",
    body: `The EasySesh team made these changes to your account:\n\n${list}\n\nWhy: ${reason?.trim() || "No explanation was added."}\n\n` +
      "If you disagree, or you don't think this change should have been made, reply to this email and tell us why. A person from our support team will look at it.",
    button: "Open EasySesh",
    link: SITE,
    footer: "You're getting this email because your EasySesh account was changed by our team.",
  });
  return send(email, "Changes to your EasySesh account", html, text);
}

/** An email written in the admin panel, sent from an @easysesh.live address (replies come back to it). */
export async function sendStaffEmail(fromAddress: string, to: string[], subject: string, body: string): Promise<string | null> {
  const name = fromAddress.startsWith("support@") ? "EasySesh Support" : "EasySesh";
  const { html, text } = render({ title: subject, body, footer: "This email was sent by the EasySesh team.", replyTo: fromAddress });
  return sendWithId(to, subject, html, text, `${name} <${fromAddress}>`, fromAddress);
}
