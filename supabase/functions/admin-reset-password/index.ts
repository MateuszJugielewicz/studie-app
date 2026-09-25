// Admin resets an artist's or studio owner's password.
//   mode "email":     sends the user a password-reset email (recommended).
//   mode "temporary": sets a random temporary password and returns it once, so the admin can
//                     pass it on (e.g. by phone). The user should change it in Settings.
// Requires an admin with two-factor authentication. Admin accounts can't be reset here.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin, requireAdmin } from "../_shared/supabase.ts";
import { temporaryPassword } from "../_shared/passwords.ts";

const APP_REDIRECT = "easysesh://auth-callback";

Deno.serve(handler(async (req, body) => {
  const caller = await requireAdmin(req);
  const userId = requireString(body, "user_id");
  const mode = body.mode === "temporary" ? "temporary" : "email";
  if (userId === caller.id) throw new HttpError(400, "Change your own password from the Supabase dashboard.");

  const { data: profile } = await admin.from("profiles").select("id, email, role").eq("id", userId).maybeSingle();
  if (!profile) throw new HttpError(404, "User not found.");
  if (profile.role === "admin") throw new HttpError(403, "Admin passwords can't be reset here.");

  const { data: authUser, error: lookupError } = await admin.auth.admin.getUserById(userId);
  if (lookupError || !authUser.user?.email) throw new HttpError(400, "This account has no email address (e.g. Apple sign-in with a hidden email).");
  const email = authUser.user.email;

  if (mode === "email") {
    const { error } = await admin.auth.resetPasswordForEmail(email, { redirectTo: APP_REDIRECT });
    if (error) throw new HttpError(400, error.message);
    return json({ mode, email });
  }

  const password = temporaryPassword();
  const { error } = await admin.auth.admin.updateUserById(userId, { password });
  if (error) throw new HttpError(400, error.message);
  await admin.from("notifications").insert({
    user_id: userId,
    kind: "system",
    title: "Your password was reset",
    body: "EasySesh support set a temporary password for your account. Please choose a new one in Settings → Change password.",
  });
  return json({ mode, email, password });
}));
