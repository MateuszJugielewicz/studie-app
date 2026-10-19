// "View as user" (admin panel): the website opens in its own tab with a read-only session for that
// person, kept in sessionStorage so the admin's own sign-in on this browser isn't touched. The server
// refuses every change from that session; this file also stops the website from trying.

const KEY = "easysesh.viewAs";

export interface ViewAs { email: string; role: string; access_token?: string; refresh_token?: string }

/** Called by boot.ts on /view-as#access_token=…: keeps the session for this tab only. */
export function captureViewAs(): boolean {
  if (window.location.pathname !== "/view-as") return false;
  const params = new URLSearchParams(window.location.hash.slice(1));
  const access_token = params.get("access_token");
  const refresh_token = params.get("refresh_token");
  if (access_token && refresh_token) {
    try {
      sessionStorage.setItem(KEY, JSON.stringify({ access_token, refresh_token, email: params.get("email") ?? "", role: params.get("role") ?? "" }));
    } catch { /* storage blocked: nothing to view */ }
  }
  window.history.replaceState(null, "", "/");
  return true;
}

export function viewAs(): ViewAs | null {
  try {
    const raw = sessionStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as ViewAs) : null;
  } catch {
    return null;
  }
}

/** The tokens, once: after they're turned into a session only the email and role stay. */
export function takeViewAsTokens(): { access_token: string; refresh_token: string } | null {
  const current = viewAs();
  if (!current?.access_token || !current.refresh_token) return null;
  sessionStorage.setItem(KEY, JSON.stringify({ email: current.email, role: current.role }));
  return { access_token: current.access_token, refresh_token: current.refresh_token };
}

export function endViewAs() {
  try { sessionStorage.removeItem(KEY); } catch { /* ignore */ }
}

/** Reads that go through POST. */
const READ_RPCS = /\/rpc\/(quote_booking|check_promo_code|studio_busy_intervals|current_terms_version|search_artists|conversation_block_state|my_blocked_users)\b/;

/** fetch for the website's Supabase client in view-as mode: changes are refused before they're sent. */
export const viewOnlyFetch: typeof fetch = async (input, init) => {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  const method = (init?.method ?? (input instanceof Request ? input.method : "GET")).toUpperCase();
  const write = !["GET", "HEAD", "OPTIONS"].includes(method);
  const allowed = !write || READ_RPCS.test(url) || /\/auth\/v1\/(token|logout)\b/.test(url);
  if (!allowed) throw new Error("View only: you're seeing EasySesh as this user, so nothing can be changed.");
  return fetch(input, init);
};
