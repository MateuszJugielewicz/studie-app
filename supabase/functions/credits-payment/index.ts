// Card purchase of promotion credits (Stripe, on the website). 1 credit = €1.
//   { credits }                       → creates a purchase and a PaymentIntent for the payment form
//   { purchase_id, confirm: true }    → checks the payment and adds the credits (returns the new balance)
// complete_credit_purchase only adds the credits once, so confirming twice is harmless.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin, requireUser } from "../_shared/supabase.ts";
import { ensureCustomer, stripe } from "../_shared/stripe.ts";

const MIN_CREDITS = 5;
const MAX_CREDITS = 1000;

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);

  if (body.confirm === true) {
    const purchaseId = requireString(body, "purchase_id");
    const { data: purchase } = await admin.from("credit_purchases").select("*").eq("id", purchaseId).maybeSingle();
    if (!purchase || purchase.user_id !== user.id) throw new HttpError(404, "not_found");
    if (purchase.status !== "paid") {
      if (!purchase.payment_intent_id) throw new HttpError(409, "No payment found for this purchase.");
      const intent = await stripe.paymentIntents.retrieve(purchase.payment_intent_id);
      if (intent.status !== "succeeded") throw new HttpError(402, "The payment hasn't gone through yet.");
    }
    const { data: balance, error } = await admin.rpc("complete_credit_purchase", { p_purchase_id: purchase.id });
    if (error) throw new HttpError(400, error.message);
    return json({ status: "paid", balance });
  }

  const credits = Number(body.credits);
  if (!Number.isInteger(credits) || credits < MIN_CREDITS || credits > MAX_CREDITS) {
    throw new HttpError(400, `Buy between ${MIN_CREDITS} and ${MAX_CREDITS} credits.`);
  }
  const { data: profile } = await admin.from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (!profile || !["artist", "studio_owner"].includes(profile.role)) {
    throw new HttpError(403, "Credits are for artists and studio owners.");
  }

  const { data: purchase, error } = await admin.from("credit_purchases")
    .insert({ user_id: user.id, credits, amount: credits * 100, currency: "EUR" }).select().single();
  if (error || !purchase) throw new HttpError(400, error?.message ?? "Couldn't start the purchase.");

  const customer = await ensureCustomer(user);
  const intent = await stripe.paymentIntents.create({
    amount: purchase.amount,
    currency: "eur",
    customer,
    automatic_payment_methods: { enabled: true },
    description: `EasySesh promotion credits · ${credits}`,
    statement_descriptor_suffix: "EASYSESH",
    metadata: { kind: "credits", purchase_id: purchase.id, user_id: user.id, credits: String(credits) },
  }, { idempotencyKey: `credits-${purchase.id}` });
  await admin.from("credit_purchases").update({ payment_intent_id: intent.id }).eq("id", purchase.id);

  return json({
    purchase_id: purchase.id,
    client_secret: intent.client_secret,
    amount: purchase.amount,
    currency: "eur",
  });
}));
