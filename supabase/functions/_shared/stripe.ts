import Stripe from "stripe";
import { admin, loadBooking, loadStudio, updateBooking } from "./supabase.ts";
import type { Booking, Profile } from "./types.ts";

export const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2025-02-24.acacia",
  httpClient: Stripe.createFetchHttpClient(),
});

export const cryptoProvider = Stripe.createSubtleCryptoProvider();

export async function ensureCustomer(profile: Profile): Promise<string> {
  if (profile.stripe_customer_id) return profile.stripe_customer_id;
  const customer = await stripe.customers.create({ email: profile.email, metadata: { user_id: profile.id } });
  await admin.from("profiles").update({ stripe_customer_id: customer.id }).eq("id", profile.id);
  return customer.id;
}

type Method = "card" | "apple_pay" | "google_pay";

async function describeMethod(pi: Stripe.PaymentIntent): Promise<{ method: Method; brand: string | null; last4: string | null }> {
  const pmId = typeof pi.payment_method === "string" ? pi.payment_method : pi.payment_method?.id;
  if (!pmId) return { method: "card", brand: null, last4: null };
  const pm = await stripe.paymentMethods.retrieve(pmId);
  const wallet = pm.card?.wallet?.type;
  return {
    method: wallet === "apple_pay" ? "apple_pay" : wallet === "google_pay" ? "google_pay" : "card",
    brand: pm.card?.brand ?? null,
    last4: pm.card?.last4 ?? null,
  };
}

/**
 * Applies a PaymentIntent's state to its booking. Idempotent: used by both the webhook and
 * `confirm-payment` (called by the app right after the payment sheet closes).
 */
export async function applyPaymentIntent(pi: Stripe.PaymentIntent): Promise<Booking | null> {
  const bookingId = pi.metadata?.booking_id;
  if (!bookingId) return null;
  const booking = await loadBooking(bookingId);
  const isBalance = pi.metadata?.kind === "balance";
  const { method, brand, last4 } = await describeMethod(pi);

  const record = async (status: "succeeded" | "failed", failure?: string) => {
    await admin.from("transactions").upsert({
      booking_id: booking.id,
      studio_id: booking.studio_id,
      artist_id: booking.artist_id,
      kind: isBalance ? "balance" : "charge",
      method,
      status,
      amount: pi.amount_received || pi.amount,
      platform_fee: isBalance ? 0 : booking.price.service_fee,
      currency: booking.price.currency,
      card_brand: brand,
      card_last4: last4,
      failure_reason: failure ?? null,
      provider_reference: pi.id,
    }, { onConflict: "provider_reference,kind", ignoreDuplicates: status === "failed" });
  };

  if (pi.status === "succeeded") {
    await record("succeeded");
    if (isBalance) return updateBooking(booking.id, { payment_status: "paid" });
    if (booking.status === "awaiting_payment" || booking.status === "pending_approval" || booking.status === "expired") {
      if (booking.status === "expired") {
        // Paid after the hold expired and the slot may be gone: refund automatically.
        await stripe.refunds.create({ payment_intent: pi.id });
        return booking;
      }
      return updateBooking(booking.id, {
        status: "confirmed",
        payment_status: booking.price.deposit_amount > 0 ? "deposit_paid" : "paid",
        payment_method: method,
      });
    }
    return booking;
  }

  if (pi.status === "requires_capture") {
    if (booking.status === "awaiting_payment") {
      return updateBooking(booking.id, { status: "pending_approval", payment_status: "authorized", payment_method: method });
    }
    return booking;
  }

  if (pi.last_payment_error) {
    await record("failed", pi.last_payment_error.message ?? "Payment failed");
    if (!isBalance && booking.status === "awaiting_payment") {
      return updateBooking(booking.id, { payment_status: "failed" });
    }
    if (isBalance) {
      await admin.rpc("notify_payment_problem", { p_booking_id: booking.id });
    }
  }
  return booking;
}

export async function studioAccountId(studioId: string): Promise<string | null> {
  const { data } = await admin.from("studio_payout_accounts").select("stripe_account_id, payouts_enabled").eq("studio_id", studioId).maybeSingle();
  return data?.payouts_enabled ? data.stripe_account_id : null;
}

export { loadStudio };
