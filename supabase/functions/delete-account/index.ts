// Deletes the caller's account (App Store requirement). Upcoming bookings are cancelled with refunds by
// the normal rules. Accounts with booking history are anonymised and soft-deleted so receipts stay valid.
import { handler, HttpError, json } from "../_shared/http.ts";
import { admin, amountPaid, requireUser, updateBooking } from "../_shared/supabase.ts";
import { refundAmount } from "../_shared/pricing.ts";
import { refundBooking, releaseAuthorization } from "../_shared/refunds.ts";
import type { Booking } from "../_shared/types.ts";

Deno.serve(handler(async (req) => {
  const user = await requireUser(req);
  if (user.role === "admin") throw new HttpError(400, "Admin accounts are removed by another admin.");

  if (user.role === "studio_owner") {
    const { data: studio } = await admin.from("studios").select("id").eq("owner_id", user.id).maybeSingle();
    if (studio) {
      const { data: fees } = await admin.from("studio_fee_ledger").select("amount").eq("studio_id", studio.id);
      if ((fees ?? []).reduce((sum, f) => sum + f.amount, 0) > 0) {
        throw new HttpError(409, "Please settle your outstanding platform fees before deleting your account.");
      }
      const { count } = await admin.from("bookings").select("id", { count: "exact", head: true })
        .eq("studio_id", studio.id).in("status", ["pending_approval", "confirmed"]).gte("starts_at", new Date().toISOString());
      if ((count ?? 0) > 0) throw new HttpError(409, "Cancel or complete your upcoming bookings before deleting your account.");
      await admin.from("studios").update({ is_active: false, status: "suspended", admin_note: "Owner deleted account" }).eq("id", studio.id);
    }
  }

  const { data: upcoming } = await admin.from("bookings").select("*").eq("artist_id", user.id).in("status", ["pending_approval", "confirmed"]).gte("starts_at", new Date().toISOString());
  for (const booking of (upcoming ?? []) as Booking[]) {
    let refund = 0;
    if (booking.payment_status === "authorized") {
      await releaseAuthorization(booking);
      refund = booking.price.due_now;
    } else {
      const { data: studio } = await admin.from("studios").select("booking_policy").eq("id", booking.studio_id).single();
      refund = refundAmount(booking.price, await amountPaid(booking.id), studio?.booking_policy?.cancellation_policy ?? "moderate", new Date(booking.starts_at), "artist");
      await refundBooking(booking, refund, "Account deleted");
    }
    await updateBooking(booking.id, { status: "cancelled", cancelled_by: "artist", cancellation_reason: "Account deleted", refund_amount: refund, payment_status: refund > 0 ? "refunded" : booking.payment_status, changed_by: user.id });
  }

  const { count: history } = await admin.from("bookings").select("id", { count: "exact", head: true }).or(`artist_id.eq.${user.id}`);
  await admin.from("device_tokens").delete().eq("user_id", user.id);
  if ((history ?? 0) > 0 || user.role === "studio_owner") {
    await admin.from("artist_profiles").update({ artist_name: "Deleted user", bio: "", avatar_url: null, links: [], city: "" }).eq("id", user.id);
    await admin.from("profiles").update({ email: `deleted-${user.id}@easysesh.invalid`, status: "banned", status_reason: "Account deleted by user", settings: {} }).eq("id", user.id);
    const { error } = await admin.auth.admin.deleteUser(user.id, true);
    if (error) throw new HttpError(500, error.message);
  } else {
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw new HttpError(500, error.message);
  }
  return json({ deleted: true });
}));
