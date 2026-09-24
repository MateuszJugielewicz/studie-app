// Artist or studio cancels an upcoming booking. Refund follows the studio's cancellation policy for
// artists; studio cancellations are always refunded in full.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { amountPaid, bookingRole, loadBooking, loadStudio, requireUser, updateBooking } from "../_shared/supabase.ts";
import { refundAmount } from "../_shared/pricing.ts";
import { refundBooking, releaseAuthorization } from "../_shared/refunds.ts";

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const booking = await loadBooking(requireString(body, "booking_id"));
  const role = await bookingRole(user, booking);
  const reason = String(body.reason ?? "").slice(0, 500);

  if (!["pending_approval", "confirmed"].includes(booking.status) || new Date(booking.starts_at) <= new Date()) {
    throw new HttpError(409, "This booking can no longer be cancelled.");
  }
  if (role === "studio_owner" && reason.trim().length === 0) {
    throw new HttpError(400, "Please tell the artist why you're cancelling.");
  }

  const cancelledBy = role === "artist" ? "artist" : "studio_owner";
  let refund = 0;
  let paymentStatus = booking.payment_status;

  if (booking.payment_method === "cash") {
    // Nothing was charged; the cancellation policy is shown to the artist but there is no money to move.
    paymentStatus = "unpaid";
  } else if (booking.payment_status === "authorized") {
    await releaseAuthorization(booking);
    refund = booking.price.due_now;
    paymentStatus = "refunded";
  } else {
    const studio = await loadStudio(booking.studio_id);
    const paid = await amountPaid(booking.id);
    refund = refundAmount(booking.price, paid, studio.booking_policy?.cancellation_policy ?? "moderate", new Date(booking.starts_at), cancelledBy);
    if (refund > 0) {
      await refundBooking(booking, refund, `Cancelled by ${cancelledBy}`);
      paymentStatus = refund >= paid ? "refunded" : "partially_refunded";
    }
  }

  const updated = await updateBooking(booking.id, {
    status: "cancelled",
    cancelled_by: cancelledBy,
    cancellation_reason: reason || null,
    refund_amount: booking.refund_amount + refund,
    payment_status: paymentStatus,
    changed_by: user.id,
  });
  return json(updated);
}));
