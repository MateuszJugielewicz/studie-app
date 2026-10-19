// "View as user": opens a read-only session as an artist or studio owner, so the team can see exactly
// what they see. The session is registered in impersonation_sessions, which makes every write from it
// fail (database pre-request check, storage policies, edge functions). Logged in the audit log.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin } from "../_shared/supabase.ts";
import { adminReason, audit, requireStaff } from "../_shared/staff.ts";

Deno.serve(handler(async (req, body) => {
  const staff = await requireStaff(req, "support");
  const userId = requireString(body, "user_id");
  const { data: profile } = await admin.from("profiles").select("id, role, email").eq("id", userId).maybeSingle();
  if (!profile) throw new HttpError(404, "User not found.");
  if (profile.role === "admin") throw new HttpError(403, "You can't view the app as another admin.");

  const { data: authUser } = await admin.auth.admin.getUserById(userId);
  const email = authUser?.user?.email;
  if (!email) throw new HttpError(400, "This account has no email address, so it can't be opened.");

  const { data: link, error: linkError } = await admin.auth.admin.generateLink({ type: "magiclink", email });
  if (linkError || !link?.properties?.hashed_token) throw new HttpError(400, linkError?.message ?? "Couldn't open a session.");

  // Exchange the one-time token here, so the session is registered before anyone can use it.
  const anon = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { auth: { persistSession: false } });
  const { data: verified, error: verifyError } = await anon.auth.verifyOtp({ type: "magiclink", token_hash: link.properties.hashed_token });
  const session = verified?.session;
  if (verifyError || !session) throw new HttpError(400, verifyError?.message ?? "Couldn't open a session.");
  const sessionId = JSON.parse(atob(session.access_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).session_id as string;

  const { error } = await admin.from("impersonation_sessions").insert({ session_id: sessionId, admin_id: staff.id, user_id: userId });
  if (error) {
    await anon.auth.signOut().catch(() => undefined);
    throw new HttpError(500, "Couldn't make the session read-only, so it was closed.");
  }
  await audit(staff, "view_as", { table: "profiles", id: userId, user: userId }, adminReason(req, body), { session_id: sessionId });
  return json({ access_token: session.access_token, refresh_token: session.refresh_token, email, role: profile.role });
}));
