// Delivers a notification row as an APNs push to the user's iOS devices, honouring their settings.
// Invoked by the `on_notification_insert` trigger. Env: APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (p8),
// APNS_BUNDLE_ID, APNS_PRODUCTION ("true" for App Store builds).
import { handler, json, requireString } from "../_shared/http.ts";
import { admin, requireServiceRole } from "../_shared/supabase.ts";

const CATEGORY: Record<string, string | null> = {
  booking_confirmed: "booking_updates", booking_changed: "booking_updates", booking_cancelled: "booking_updates",
  booking_declined: "booking_updates", booking_requested: "booking_updates", refund_issued: null, payout_sent: null,
  session_reminder: "reminders", review_reminder: "review_prompts", new_review: "booking_updates",
  new_message: "messages", studio_approved: null, studio_rejected: null, studio_changes_requested: null, system: null,
};

let cachedJwt: { token: string; issuedAt: number } | null = null;

function base64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function providerToken(): Promise<string> {
  // APNs accepts a token for up to an hour; refresh every 50 minutes.
  if (cachedJwt && Date.now() - cachedJwt.issuedAt < 50 * 60_000) return cachedJwt.token;
  const pem = Deno.env.get("APNS_PRIVATE_KEY")!.replace(/\\n/g, "").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: Deno.env.get("APNS_KEY_ID") }));
  const claims = base64url(JSON.stringify({ iss: Deno.env.get("APNS_TEAM_ID"), iat: Math.floor(Date.now() / 1000) }));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  cachedJwt = { token: `${header}.${claims}.${base64url(signature)}`, issuedAt: Date.now() };
  return cachedJwt.token;
}

Deno.serve(handler(async (req, body) => {
  requireServiceRole(req);
  const { data: note } = await admin.from("notifications").select("*").eq("id", requireString(body, "notification_id")).single();
  if (!note) return json({ sent: 0 });

  const { data: profile } = await admin.from("profiles").select("status, settings").eq("id", note.user_id).single();
  const settings = (profile?.settings ?? {}) as Record<string, boolean>;
  const category = CATEGORY[note.kind];
  if (profile?.status !== "active" || settings.push_enabled === false || (category && settings[category] === false)) {
    return json({ sent: 0, skipped: true });
  }
  if (!Deno.env.get("APNS_PRIVATE_KEY")) return json({ sent: 0, skipped: "apns_not_configured" });

  const { data: tokens } = await admin.from("device_tokens").select("token").eq("user_id", note.user_id).eq("platform", "ios");
  const { count: unread } = await admin.from("notifications").select("id", { count: "exact", head: true }).eq("user_id", note.user_id).eq("is_read", false);
  const host = Deno.env.get("APNS_PRODUCTION") === "true" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const jwt = await providerToken();

  let sent = 0;
  for (const { token } of tokens ?? []) {
    const response = await fetch(`https://${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": Deno.env.get("APNS_BUNDLE_ID") ?? "com.sonora.app",
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify({
        aps: { alert: { title: note.title, body: note.body }, sound: "default", badge: unread ?? 1, "thread-id": note.conversation_id ?? note.booking_id ?? note.kind },
        booking_id: note.booking_id,
        conversation_id: note.conversation_id,
        studio_id: note.studio_id,
      }),
    });
    if (response.ok) {
      sent++;
    } else if (response.status === 410 || response.status === 400) {
      // Unregistered / bad token → forget it.
      await admin.from("device_tokens").delete().eq("token", token);
    }
  }
  return json({ sent });
}));
