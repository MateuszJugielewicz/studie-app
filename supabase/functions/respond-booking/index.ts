// Studio accepts (captures the authorised payment) or declines (releases it) a booking request.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { loadBooking, loadStudio, requireApprovedStudio, requireUser, updateBooking } from "../_shared/supabase.ts";
import { applyPaymentIntent, stripe } from "../_shared/stripe.ts";
import { releaseAuthorization } from "../_shared/refunds.ts";

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const booking = await loadBooking(requireString(body, "booking_id"));
  const studio = await loadStudio(booking.studio_id);
  requireApprovedStudio(user, studio);
  if (booking.status !== "pending_approval") throw new HttpError(409, "This request has already been handled.");

  const isCash = booking.payment_method === "cash";

  if (body.accept === true && isCash) {
    return json(await updateBooking(booking.id, { status: "confirmed", changed_by: user.id }));
  }

  if (body.accept === true) {
    if (!booking.payment_intent_id) throw new HttpError(409, "No authorised payment found.");
    const intent = await stripe.paymentIntents.capture(booking.payment_intent_id, {}, { idempotencyKey: `capture-${booking.id}` });
    const updated = await applyPaymentIntent(intent);
    if (!updated || updated.status !== "confirmed") {
      throw new HttpError(402, "We couldn't charge the artist's card. The request stays open.");
    }
    return json(await updateBooking(booking.id, { changed_by: user.id }));
  }

  if (!isCash) await releaseAuthorization(booking);
  const message = typeof body.message === "string" && body.message.trim() ? body.message.trim().slice(0, 500) : null;
  return json(await updateBooking(booking.id, {
    status: "declined",
    payment_status: isCash ? "unpaid" : "refunded",
    refund_amount: isCash ? 0 : booking.price.due_now,
    cancellation_reason: message,
    changed_by: user.id,
  }));
}));
