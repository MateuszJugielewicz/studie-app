// Transactional emails (booking confirmations etc.) from noreply@easysesh.live via Resend
// (https://resend.com). Needs the RESEND_API_KEY secret and the domain verified in Resend;
// without the key nothing is sent. Replies go to support.
import { admin } from "./supabase.ts";

const FROM = Deno.env.get("EMAIL_FROM") ?? "EasySesh <noreply@easysesh.live>";
const REPLY_TO = Deno.env.get("EMAIL_REPLY_TO") ?? "support@easysesh.live";
const SITE = (Deno.env.get("SITE_URL") ?? "https://easysesh.live").replace(/\/+$/, "");

/** Notification kinds that also go out by email. */
export const EMAIL_KINDS = new Set([
  "booking_confirmed", "booking_requested", "booking_declined", "booking_cancelled", "booking_changed", "refund_issued",
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

async function send(to: string, subject: string, html: string, text: string): Promise<boolean> {
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return false;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [to], reply_to: REPLY_TO, subject, html, text }),
  });
  if (!response.ok) console.error("Email failed", response.status, await response.text());
  return response.ok;
}

// deno-lint-ignore no-explicit-any
export async function sendNotificationEmail(note: any, email: string | null | undefined): Promise<boolean> {
  if (!EMAIL_KINDS.has(note.kind) || !email || email.endsWith(".invalid") || !Deno.env.get("RESEND_API_KEY")) return false;

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
        ["Payment", b.payment_method === "cash" ? "Cash at the studio" : b.payment_status === "authorized" ? "Card (charged when the studio accepts)" : "Card"],
      );
      const address = studio?.address;
      if (address?.street) rows.push(["Address", [address.street, address.postal_code, address.city].filter(Boolean).join(", ")]);
    }
  }

  const table = rows.map(([k, v]) =>
    `<tr><td style="padding:6px 0;color:#6f6c66;width:110px;vertical-align:top">${escape(k)}</td><td style="padding:6px 0;color:#1c1b19">${escape(v)}</td></tr>`).join("");
  const html = `<!doctype html><html><body style="margin:0;background:#f5f5f4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
<div style="max-width:520px;margin:0 auto;padding:28px 16px">
  <div style="font-weight:800;font-size:22px;letter-spacing:-0.03em;color:#1c1b19">easysesh<span style="color:#d9431e">.</span></div>
  <div style="background:#fff;border:1px solid #e4e3e0;border-radius:16px;padding:22px;margin-top:16px">
    <h1 style="font-size:20px;margin:0 0 8px;color:#1c1b19">${escape(note.title)}</h1>
    <p style="margin:0 0 16px;color:#3a3935;line-height:1.5">${escape(note.body)}</p>
    ${table ? `<table style="width:100%;border-collapse:collapse;font-size:14px;border-top:1px solid #eee;margin-bottom:18px">${table}</table>` : ""}
    <a href="${escape(link)}" style="display:inline-block;background:#d9431e;color:#fff;text-decoration:none;font-weight:600;padding:11px 18px;border-radius:10px">View booking</a>
  </div>
  <p style="font-size:12px;color:#8a877f;line-height:1.5;margin:16px 4px 0">You're getting this email because of a booking on EasySesh. Questions? Reply to this email or write to ${escape(REPLY_TO)}.</p>
</div></body></html>`;
  const text = [note.title, "", note.body, "", ...rows.map(([k, v]) => `${k}: ${v}`), "", `View booking: ${link}`, "", `Questions? ${REPLY_TO}`].join("\n");
  return send(email, `${note.title} – EasySesh`, html, text);
}
