// Admin deletes an account ({ user_id }) or a studio ({ studio_id }). Needs the admin rank.
// Upcoming bookings are cancelled with full refunds, the person is emailed (from noreply@) with the
// reason, and it's written to the audit log.
//   Account: anonymised and soft-deleted when it has booking history (receipts stay valid),
//            removed completely otherwise. A studio owner's studio is taken offline too.
//   Studio:  removed completely when it never had bookings, otherwise taken offline and hidden.
import { handler, HttpError, json } from "../_shared/http.ts";
import { admin, amountPaid, updateBooking } from "../_shared/supabase.ts";
import { refundBooking, releaseAuthorization } from "../_shared/refunds.ts";
import { adminReason, audit, requireStaff } from "../_shared/staff.ts";
import { sendAccountChangeEmail } from "../_shared/email.ts";
import type { Booking } from "../_shared/types.ts";

/** Cancels bookings that haven't happened yet, refunding everything that was paid. */
async function cancelUpcoming(column: "artist_id" | "studio_id", id: string, reason: string, by: string): Promise<number> {
  const { data } = await admin.from("bookings").select("*").eq(column, id)
    .in("status", ["awaiting_payment", "pending_approval", "confirmed"]).gte("starts_at", new Date().toISOString());
  for (const booking of (data ?? []) as Booking[]) {
    let refund = 0;
    if (booking.payment_status === "authorized") {
      await releaseAuthorization(booking);
    } else {
      refund = await amountPaid(booking.id);
      await refundBooking(booking, refund, reason);
    }
    await updateBooking(booking.id, {
      status: "cancelled", cancelled_by: "admin", cancellation_reason: reason, refund_amount: (booking.refund_amount ?? 0) + refund,
      payment_status: refund > 0 ? "refunded" : booking.payment_status, changed_by: by,
    });
  }
  return (data ?? []).length;
}

Deno.serve(handler(async (req, body) => {
  const staff = await requireStaff(req, "admin");
  const reason = adminReason(req, body);
  if (!reason) throw new HttpError(400, "Add an explanation – it's emailed to the person.");
  const cancelReason = "Cancelled by EasySesh";

  if (typeof body.studio_id === "string") {
    const { data: studio } = await admin.from("studios").select("id, name, owner_id").eq("id", body.studio_id).maybeSingle();
    if (!studio) throw new HttpError(404, "Studio not found.");
    const cancelled = await cancelUpcoming("studio_id", studio.id, cancelReason, staff.id);
    const { count } = await admin.from("bookings").select("id", { count: "exact", head: true }).eq("studio_id", studio.id);
    const { data: owner } = await admin.from("profiles").select("email").eq("id", studio.owner_id).maybeSingle();
    let removed = false;
    if ((count ?? 0) === 0) {
      const { error } = await admin.from("studios").delete().eq("id", studio.id);
      removed = !error;
    }
    if (!removed) {
      await admin.from("studios").update({ is_active: false, status: "suspended", admin_note: `Removed by EasySesh: ${reason}`.slice(0, 500) }).eq("id", studio.id);
    }
    await sendAccountChangeEmail(owner?.email ?? "", [
      `Studio: ${studio.name} was removed from EasySesh`,
      ...(cancelled ? [`Bookings: ${cancelled} upcoming booking${cancelled === 1 ? "" : "s"} cancelled and refunded`] : []),
    ], reason).catch(() => false);
    await audit(staff, "delete_studio", { table: "studios", id: studio.id, user: studio.owner_id }, reason, { name: studio.name, removed, cancelled });
    return json({ deleted: true, removed, cancelled });
  }

  const userId = typeof body.user_id === "string" ? body.user_id : "";
  if (!userId) throw new HttpError(400, "Missing user_id or studio_id.");
  if (userId === staff.id) throw new HttpError(400, "You can't delete your own account here.");
  const { data: profile } = await admin.from("profiles").select("id, email, role").eq("id", userId).maybeSingle();
  if (!profile) throw new HttpError(404, "User not found.");
  if (profile.role === "admin") throw new HttpError(403, "Remove them from the team first (Team page).");

  let cancelled = await cancelUpcoming("artist_id", userId, cancelReason, staff.id);
  const { data: studio } = await admin.from("studios").select("id, name").eq("owner_id", userId).maybeSingle();
  if (studio) {
    cancelled += await cancelUpcoming("studio_id", studio.id, cancelReason, staff.id);
    await admin.from("studios").update({ is_active: false, status: "suspended", admin_note: `Owner account deleted by EasySesh: ${reason}`.slice(0, 500) }).eq("id", studio.id);
  }
  // Tell them before the email address is removed.
  await sendAccountChangeEmail(profile.email, [
    "Account: deleted by the EasySesh team",
    ...(studio ? [`Studio: ${studio.name} taken offline`] : []),
    ...(cancelled ? [`Bookings: ${cancelled} upcoming booking${cancelled === 1 ? "" : "s"} cancelled and refunded`] : []),
  ], reason).catch(() => false);

  const { count: history } = await admin.from("bookings").select("id", { count: "exact", head: true }).eq("artist_id", userId);
  await admin.from("device_tokens").delete().eq("user_id", userId);
  const soft = (history ?? 0) > 0 || !!studio;
  if (soft) {
    await admin.from("artist_profiles").update({ artist_name: "Deleted user", bio: "", avatar_url: null, links: [], city: "" }).eq("id", userId);
    await admin.from("reviews").update({ text: "", artist_name: "Deleted user" }).eq("artist_id", userId);
    await admin.from("messages").update({ body: "Message deleted" }).eq("sender_id", userId);
    await admin.from("profiles").update({ email: `deleted-${userId}@easysesh.invalid`, status: "banned", status_reason: `Account deleted by EasySesh: ${reason}`.slice(0, 500), settings: {} }).eq("id", userId);
  }
  const { error } = await admin.auth.admin.deleteUser(userId, soft);
  if (error) throw new HttpError(500, error.message);
  await audit(staff, "delete_user", { table: "profiles", id: userId, user: userId }, reason, { email: profile.email, role: profile.role, soft, cancelled, studio: studio?.name ?? null });
  return json({ deleted: true, soft, cancelled });
}));
