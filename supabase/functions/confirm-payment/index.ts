// Called by the app after the payment sheet completes. Reads the PaymentIntent from Stripe and applies
// the same transition as the webhook, so the app gets the final booking state immediately.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { loadBooking, requireUser } from "../_shared/supabase.ts";
import { applyPaymentIntent, stripe } from "../_shared/stripe.ts";

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const booking = await loadBooking(requireString(body, "booking_id"));
  if (booking.artist_id !== user.id) throw new HttpError(403, "forbidden");
  if (!booking.payment_intent_id) throw new HttpError(409, "No payment was started for this booking.");

  const intent = await stripe.paymentIntents.retrieve(booking.payment_intent_id);
  const updated = await applyPaymentIntent(intent);
  if (intent.last_payment_error && updated?.status === "awaiting_payment") {
    throw new HttpError(402, intent.last_payment_error.message ?? "Payment failed.");
  }
  return json(updated ?? booking);
}));
