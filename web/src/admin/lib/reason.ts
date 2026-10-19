// Every change made from the admin panel needs a short explanation. It's sent with the request (the
// X-Admin-Reason header), saved in the audit log, and emailed to the person whose account changed.

type Asker = (action: string) => Promise<string | null>;
let asker: Asker | null = null;
let recent: { reason: string; at: number } | null = null;

/** Registered by <ReasonDialog/>. */
export function setReasonAsker(next: Asker | null) {
  asker = next;
}

/** Requests that don't change anyone's account. */
const EXEMPT = /\/rpc\/(admin_dashboard_stats|mark_support_ticket_read|send_support_message|set_support_ticket_status)\b|\/functions\/v1\/admin-send-email\b/;

function actionName(url: string): string {
  const name = url.match(/\/rpc\/([a-z_]+)/)?.[1] ?? url.match(/\/functions\/v1\/([a-z-]+)/)?.[1] ?? url.match(/\/rest\/v1\/([a-z_]+)/)?.[1] ?? "change";
  return name.replace(/^admin[_-]/, "").replace(/[_-]/g, " ");
}

const encode = (text: string) => btoa(String.fromCharCode(...new TextEncoder().encode(text)));

/** fetch for the admin Supabase client: asks for the explanation before any change. */
export const fetchWithReason: typeof fetch = async (input, init) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  const method = (init?.method ?? (input instanceof Request ? input.method : "GET")).toUpperCase();
  const writes = !["GET", "HEAD", "OPTIONS"].includes(method) && /\/(rest|functions)\/v1\//.test(url) && !EXEMPT.test(url);
  if (!writes) return fetch(input, init);
  // One explanation covers the few requests a single button makes.
  let reason = recent && Date.now() - recent.at < 8000 ? recent.reason : null;
  if (reason === null) {
    reason = asker ? await asker(actionName(url)) : "";
    if (reason === null) throw new Error("Cancelled – nothing was changed.");
    recent = { reason, at: Date.now() };
  }
  const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
  if (reason) headers.set("x-admin-reason", encode(reason));
  return fetch(input, { ...init, headers });
};
