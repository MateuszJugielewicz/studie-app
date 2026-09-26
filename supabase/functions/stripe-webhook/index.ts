// Stripe → EasySesh. Configure the endpoint in Stripe with these events:
// payment_intent.succeeded, payment_intent.amount_capturable_updated, payment_intent.payment_failed,
// charge.refunded, account.updated, invoice.paid
import Stripe from "npm:stripe@17.7.0";
import { admin } from "../_shared/supabase.ts";
import { applyPaymentIntent, cryptoProvider, stripe } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  const signature = req.headers.get("Stripe-Signature");
  const payload = await req.text();
  // Two endpoints can point here: "Your account" events and "Connected accounts" events
  // (studio payout onboarding). Each has its own signing secret.
  const secrets = [Deno.env.get("STRIPE_WEBHOOK_SECRET"), Deno.env.get("STRIPE_CONNECT_WEBHOOK_SECRET")].filter((s): s is string => !!s);
  let event: Stripe.Event | undefined;
  let lastError = "no webhook secret configured";
  for (const secret of secrets) {
    try {
      event = await stripe.webhooks.constructEventAsync(payload, signature!, secret, undefined, cryptoProvider);
      break;
    } catch (error) {
      lastError = (error as Error).message;
    }
  }
  if (!event) return new Response(`Invalid signature: ${lastError}`, { status: 400 });

  try {
    switch (event.type) {
      case "payment_intent.succeeded":
      case "payment_intent.amount_capturable_updated":
      case "payment_intent.payment_failed": {
        const intent = event.data.object;
        if (intent.metadata?.kind === "promotion") {
          // Studio promotion paid in the app → start it.
          if (event.type === "payment_intent.succeeded" && intent.metadata.promotion_id) {
            const { error } = await admin.rpc("activate_promotion", { p_promotion_id: intent.metadata.promotion_id });
            if (error) throw new Error(error.message);
          }
          break;
        }
        await applyPaymentIntent(intent);
        break;
      }

      case "account.updated": {
        const account = event.data.object;
        const bank = account.external_accounts?.data.find((a) => a.object === "bank_account") as Stripe.BankAccount | undefined;
        await admin.from("studio_payout_accounts").update({
          payouts_enabled: account.payouts_enabled ?? false,
          iban_last4: bank?.last4 ?? "",
          updated_at: new Date().toISOString(),
        }).eq("stripe_account_id", account.id);
        break;
      }

      case "invoice.paid": {
        // Studio paid its platform-fee invoice (cash bookings).
        const invoice = event.data.object;
        const { data: row } = await admin.from("studio_fee_invoices").select("*").eq("stripe_invoice_id", invoice.id).maybeSingle();
        if (!row || row.status === "paid") break;
        await admin.from("studio_fee_invoices").update({ status: "paid", paid_at: new Date().toISOString() }).eq("id", row.id);
        await admin.from("studio_fee_ledger").insert({
          studio_id: row.studio_id, invoice_id: row.id, kind: "invoice_payment", amount: -row.amount, currency: row.currency,
          note: `Invoice ${invoice.number ?? invoice.id} paid`,
        });
        break;
      }

      case "charge.refunded": {
        // Refunds made in the Stripe dashboard are mirrored as transactions.
        const charge = event.data.object;
        const bookingId = charge.metadata?.booking_id ?? (typeof charge.payment_intent === "string"
          ? (await stripe.paymentIntents.retrieve(charge.payment_intent)).metadata.booking_id
          : undefined);
        if (!bookingId) break;
        const { data: booking } = await admin.from("bookings").select("*").eq("id", bookingId).single();
        if (!booking) break;
        for (const refund of charge.refunds?.data ?? []) {
          await admin.from("transactions").upsert({
            booking_id: booking.id,
            studio_id: booking.studio_id,
            artist_id: booking.artist_id,
            kind: "refund",
            method: booking.payment_method ?? "card",
            status: refund.status === "succeeded" ? "succeeded" : "pending",
            amount: refund.amount,
            currency: booking.price.currency,
            provider_reference: refund.id,
          }, { onConflict: "provider_reference,kind", ignoreDuplicates: true });
        }
        break;
      }
    }
  } catch (error) {
    console.error(error);
    return new Response("Handler error", { status: 500 });
  }
  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
