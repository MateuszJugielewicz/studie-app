// Creates (or reuses) the Stripe PaymentIntent for a booking's upfront amount.
// Instant-book studios capture immediately; request-to-book studios authorise now and capture on acceptance.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { loadBooking, loadStudio, requireUser, updateBooking } from "../_shared/supabase.ts";
import { ensureCustomer, stripe } from "../_shared/stripe.ts";

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const booking = await loadBooking(requireString(body, "booking_id"));
  if (booking.artist_id !== user.id) throw new HttpError(403, "forbidden");
  if (booking.status !== "awaiting_payment") throw new HttpError(409, "This booking is no longer awaiting payment.");

  const studio = await loadStudio(booking.studio_id);
  const instant = studio.booking_policy?.instant_book ?? true;
  const customer = await ensureCustomer(user);
  const amount = booking.price.due_now;
  const currency = booking.price.currency.toLowerCase();

  let intent = booking.payment_intent_id ? await stripe.paymentIntents.retrieve(booking.payment_intent_id) : null;
  if (!intent || intent.status === "canceled" || intent.amount !== amount) {
    intent = await stripe.paymentIntents.create({
      amount,
      currency,
      customer,
      capture_method: instant ? "automatic" : "manual",
      // Save the card when a balance will be charged after the session.
      setup_future_usage: booking.price.due_later > 0 ? "off_session" : undefined,
      automatic_payment_methods: { enabled: true },
      description: `EasySesh ${booking.reference} · ${booking.studio_name}`,
      statement_descriptor_suffix: "EASYSESH",
      transfer_group: booking.id,
      metadata: { booking_id: booking.id, kind: "charge", studio_id: booking.studio_id },
    }, { idempotencyKey: `booking-${booking.id}-${amount}` });
    await updateBooking(booking.id, { payment_intent_id: intent.id });
  }

  const ephemeralKey = await stripe.ephemeralKeys.create({ customer }, { apiVersion: "2025-02-24.acacia" });

  return json({
    client_secret: intent.client_secret,
    customer_id: customer,
    ephemeral_key: ephemeralKey.secret,
    amount,
    currency,
    capture_later: !instant,
  });
}));
