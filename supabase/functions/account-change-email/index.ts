// Emails a person when the EasySesh team changed their account (account_change_notices, written by
// the staff audit trigger): what changed and why, from noreply@, with replies going to support@.
// Also adds an in-app notification. Invoked by the database (service key).
import { handler, json, requireString } from "../_shared/http.ts";
import { admin, requireServiceRole } from "../_shared/supabase.ts";
import { sendAccountChangeEmail } from "../_shared/email.ts";

Deno.serve(handler(async (req, body) => {
  await requireServiceRole(req);
  const { data: notice } = await admin.from("account_change_notices").select("*").eq("id", requireString(body, "notice_id")).maybeSingle();
  if (!notice || notice.emailed_at) return json({ sent: false });
  const { data: profile } = await admin.from("profiles").select("email").eq("id", notice.user_id).maybeSingle();
  const changes = (notice.changes ?? []) as string[];

  await admin.from("notifications").insert({
    user_id: notice.user_id, kind: "system", title: "Your account was updated",
    body: `${changes.slice(0, 3).join("\n")}${changes.length > 3 ? "\n…" : ""}${notice.reason ? `\nWhy: ${notice.reason}` : ""}`.slice(0, 1000),
  });
  const sent = await sendAccountChangeEmail(profile?.email ?? "", changes, notice.reason);
  await admin.from("account_change_notices").update({ emailed_at: new Date().toISOString() }).eq("id", notice.id);
  return json({ sent });
}));
