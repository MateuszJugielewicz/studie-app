// Delivers a notification row as a push to the user's devices, honouring their settings: APNs for iOS,
// Firebase Cloud Messaging for Android. Booking notifications also go out by email (_shared/email.ts).
// Invoked by the `on_notification_insert` trigger.
// iOS env: APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (p8), APNS_BUNDLE_ID, APNS_PRODUCTION ("true" for App Store builds).
// Android env (Firebase service account): FCM_PROJECT_ID, FCM_CLIENT_EMAIL, FCM_PRIVATE_KEY.
import { handler, json, requireString } from "../_shared/http.ts";
import { admin, requireServiceRole } from "../_shared/supabase.ts";
import { sendNotificationEmail } from "../_shared/email.ts";

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

let cachedFcm: { token: string; expiresAt: number } | null = null;

/** OAuth access token for FCM, from the Firebase service account (signed RS256 JWT). */
async function fcmAccessToken(): Promise<string> {
  if (cachedFcm && Date.now() < cachedFcm.expiresAt - 5 * 60_000) return cachedFcm.token;
  const pem = Deno.env.get("FCM_PRIVATE_KEY")!.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: Deno.env.get("FCM_CLIENT_EMAIL"),
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${header}.${claims}.${base64url(signature)}` }),
  });
  if (!response.ok) throw new Error(`FCM auth failed: ${response.status}`);
  const result = await response.json();
  cachedFcm = { token: result.access_token, expiresAt: Date.now() + result.expires_in * 1000 };
  return cachedFcm.token;
}

// deno-lint-ignore no-explicit-any
async function sendAndroid(note: any): Promise<number> {
  if (!Deno.env.get("FCM_PRIVATE_KEY") || !Deno.env.get("FCM_PROJECT_ID")) return 0;
  const { data: tokens } = await admin.from("device_tokens").select("token").eq("user_id", note.user_id).eq("platform", "android");
  if (!tokens?.length) return 0;
  const accessToken = await fcmAccessToken();
  // FCM data values must be strings; the app opens the booking / chat / studio from these.
  const data: Record<string, string> = {};
  for (const key of ["booking_id", "conversation_id", "studio_id"]) if (note[key]) data[key] = String(note[key]);

  let sent = 0;
  for (const { token } of tokens) {
    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${Deno.env.get("FCM_PROJECT_ID")}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${accessToken}`, "content-type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: note.title, body: note.body },
          data,
          android: {
            priority: "high",
            notification: { channel_id: "easysesh", tag: note.conversation_id ?? note.booking_id ?? note.kind, default_sound: true },
          },
        },
      }),
    });
    if (response.ok) {
      sent++;
    } else if (response.status === 404 || response.status === 400) {
      // UNREGISTERED / invalid token → forget it.
      await admin.from("device_tokens").delete().eq("token", token);
    }
  }
  return sent;
}

Deno.serve(handler(async (req, body) => {
  await requireServiceRole(req);
  const { data: note } = await admin.from("notifications").select("*").eq("id", requireString(body, "notification_id")).single();
  if (!note) return json({ sent: 0 });

  const { data: profile } = await admin.from("profiles").select("status, settings, email").eq("id", note.user_id).single();
  const settings = (profile?.settings ?? {}) as Record<string, boolean>;
  // Booking emails are part of the booking itself, so they don't follow the push switches.
  const emailed = profile?.status === "active" ? await sendNotificationEmail(note, profile.email).catch((error) => { console.error(error); return false; }) : false;
  const category = CATEGORY[note.kind];
  if (profile?.status !== "active" || settings.push_enabled === false || (category && settings[category] === false)) {
    return json({ sent: 0, emailed, skipped: true });
  }
  const android = await sendAndroid(note).catch((error) => { console.error(error); return 0; });
  if (!Deno.env.get("APNS_PRIVATE_KEY")) return json({ sent: android, emailed, skipped: "apns_not_configured" });

  const { data: tokens } = await admin.from("device_tokens").select("token").eq("user_id", note.user_id).eq("platform", "ios");
  const { count: unread } = await admin.from("notifications").select("id", { count: "exact", head: true }).eq("user_id", note.user_id).eq("is_read", false);
  const host = Deno.env.get("APNS_PRODUCTION") === "true" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const jwt = await providerToken();

  let sent = android;
  for (const { token } of tokens ?? []) {
    const response = await fetch(`https://${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": Deno.env.get("APNS_BUNDLE_ID") ?? "com.easysesh.app",
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
  return json({ sent, emailed });
}));
