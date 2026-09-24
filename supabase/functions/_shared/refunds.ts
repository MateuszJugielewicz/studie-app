import { admin, updateBooking } from "./supabase.ts";
import { stripe } from "./stripe.ts";
import type { Booking } from "./types.ts";

/** Refunds `amount` of the booking's upfront charge and records the transaction. */
export async function refundBooking(booking: Booking, amount: number, reason: string): Promise<void> {
  if (amount <= 0 || !booking.payment_intent_id) return;
  const refund = await stripe.refunds.create({
    payment_intent: booking.payment_intent_id,
    amount,
    metadata: { booking_id: booking.id, reason: reason.slice(0, 200) },
  }, { idempotencyKey: `refund-${booking.id}-${booking.refund_amount}-${amount}` });
  await admin.from("transactions").upsert({
    booking_id: booking.id,
    studio_id: booking.studio_id,
    artist_id: booking.artist_id,
    kind: "refund",
    method: booking.payment_method ?? "card",
    status: refund.status === "failed" ? "failed" : "succeeded",
    amount,
    currency: booking.price.currency,
    provider_reference: refund.id,
  }, { onConflict: "provider_reference,kind", ignoreDuplicates: true });
}

/** Releases an uncaptured authorisation. */
export async function releaseAuthorization(booking: Booking): Promise<void> {
  if (!booking.payment_intent_id) return;
  const intent = await stripe.paymentIntents.retrieve(booking.payment_intent_id);
  if (intent.status === "requires_capture") await stripe.paymentIntents.cancel(intent.id);
}

export { updateBooking };
