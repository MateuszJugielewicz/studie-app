// Sends the "Confirm your email" email from noreply@easysesh.live. Invoked by the database (service
// key) when an email/password account is created and when the user taps "Resend email"
// (resend_email_verification). The token is created and rate limited by issue_email_verification;
// the link is checked by verify_email.
import { handler, json, requireString } from "../_shared/http.ts";
import { admin, requireServiceRole } from "../_shared/supabase.ts";
import { sendVerificationEmail } from "../_shared/email.ts";

Deno.serve(handler(async (req, body) => {
  await requireServiceRole(req);
  const { data, error } = await admin.rpc("issue_email_verification", { p_user_id: requireString(body, "user_id") });
  if (error) throw error;
  if (!data) return json({ sent: false, reason: "verified_or_rate_limited" });
  const sent = await sendVerificationEmail(data.email, data.token, data.role, data.name);
  return json({ sent });
}));
