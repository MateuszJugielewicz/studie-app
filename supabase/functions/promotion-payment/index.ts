// Card payment for a studio promotion (Stripe).
//   { promotion_id }                 → PaymentIntent for the payment sheet
//   { promotion_id, confirm: true }  → checks the payment and starts the promotion
// The promotion itself is ordered with the request_promotion RPC (price comes from the database).
// The stripe-webhook also starts it on payment_intent.succeeded, whichever arrives first.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin, requireUser } from "../_shared/supabase.ts";
import { ensureCustomer, stripe } from "../_shared/stripe.ts";

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const promotionId = requireString(body, "promotion_id");

  const { data: promotion } = await admin.from("studio_promotions").select("*, studios!inner(owner_id, name)").eq("id", promotionId).maybeSingle();
  if (!promotion || promotion.studios.owner_id !== user.id) throw new HttpError(404, "not_found");

  if (body.confirm === true) {
    if (promotion.status === "active") return json({ status: "active" });
    if (!promotion.payment_intent_id) throw new HttpError(409, "No payment found for this promotion.");
    const intent = await stripe.paymentIntents.retrieve(promotion.payment_intent_id);
    if (intent.status !== "succeeded") throw new HttpError(402, "The payment hasn't gone through yet.");
    const { error } = await admin.rpc("activate_promotion", { p_promotion_id: promotion.id });
    if (error) throw new HttpError(400, error.message);
    return json({ status: "active" });
  }

  if (promotion.status !== "pending") throw new HttpError(409, "This promotion is no longer awaiting payment.");
  const customer = await ensureCustomer(user);

  let intent = promotion.payment_intent_id ? await stripe.paymentIntents.retrieve(promotion.payment_intent_id) : null;
  if (!intent || intent.status === "canceled") {
    intent = await stripe.paymentIntents.create({
      amount: promotion.amount,
      currency: String(promotion.currency).toLowerCase(),
      customer,
      automatic_payment_methods: { enabled: true },
      description: `EasySesh promotion · ${promotion.studios.name} · ${promotion.days} days`,
      statement_descriptor_suffix: "EASYSESH",
      metadata: { kind: "promotion", promotion_id: promotion.id, studio_id: promotion.studio_id },
    }, { idempotencyKey: `promotion-${promotion.id}` });
    await admin.from("studio_promotions").update({ payment_intent_id: intent.id }).eq("id", promotion.id);
  }

  const ephemeralKey = await stripe.ephemeralKeys.create({ customer }, { apiVersion: "2025-02-24.acacia" });
  return json({
    client_secret: intent.client_secret,
    customer_id: customer,
    ephemeral_key: ephemeralKey.secret,
    amount: promotion.amount,
    currency: String(promotion.currency).toLowerCase(),
    capture_later: false,
  });
}));
