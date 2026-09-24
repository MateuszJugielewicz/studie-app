// Hourly job (pg_cron → call_edge_function). Service role only.
//  1. Releases card holds on requests that expired without an answer.
//  2. Charges the remaining balance for deposit bookings once the session is completed.
//  3. Schedules studio payouts for completed sessions and transfers them after the payout delay.
import { handler, json } from "../_shared/http.ts";
import { admin, requireServiceRole, updateBooking } from "../_shared/supabase.ts";
import { applyPaymentIntent, stripe, studioAccountId } from "../_shared/stripe.ts";
import { PAYOUT_DELAY_DAYS } from "../_shared/pricing.ts";
import type { Booking } from "../_shared/types.ts";

const DAY = 86_400_000;

async function releaseExpiredHolds(): Promise<number> {
  const { data } = await admin.from("bookings").select("*").eq("status", "expired").eq("payment_status", "refunded").not("payment_intent_id", "is", null).gte("starts_at", new Date(Date.now() - 8 * DAY).toISOString());
  let count = 0;
  for (const booking of (data ?? []) as Booking[]) {
    const intent = await stripe.paymentIntents.retrieve(booking.payment_intent_id!);
    if (intent.status === "requires_capture") {
      await stripe.paymentIntents.cancel(intent.id);
      count++;
    }
  }
  return count;
}

async function chargeBalances(): Promise<number> {
  const { data } = await admin.from("bookings").select("*").eq("status", "completed").eq("payment_status", "deposit_paid").is("balance_payment_intent_id", null);
  let count = 0;
  for (const booking of (data ?? []) as Booking[]) {
    if (!booking.payment_intent_id || booking.price.due_later <= 0) continue;
    const first = await stripe.paymentIntents.retrieve(booking.payment_intent_id);
    const paymentMethod = typeof first.payment_method === "string" ? first.payment_method : first.payment_method?.id;
    const customer = typeof first.customer === "string" ? first.customer : first.customer?.id;
    if (!paymentMethod || !customer) continue;
    try {
      const intent = await stripe.paymentIntents.create({
        amount: booking.price.due_later,
        currency: booking.price.currency.toLowerCase(),
        customer,
        payment_method: paymentMethod,
        off_session: true,
        confirm: true,
        description: `Sonora ${booking.reference} · remaining balance`,
        transfer_group: booking.id,
        metadata: { booking_id: booking.id, kind: "balance" },
      }, { idempotencyKey: `balance-${booking.id}` });
      await updateBooking(booking.id, { balance_payment_intent_id: intent.id });
      await applyPaymentIntent(intent);
      count++;
    } catch (error) {
      // Card declined / authentication required: record and notify, retry manually from the admin panel.
      const intent = (error as { raw?: { payment_intent?: { id: string } } }).raw?.payment_intent;
      if (intent) {
        await updateBooking(booking.id, { balance_payment_intent_id: intent.id });
        await applyPaymentIntent(await stripe.paymentIntents.retrieve(intent.id));
      }
      console.error("Balance charge failed", booking.id, error);
    }
  }
  return count;
}

async function schedulePayouts(): Promise<number> {
  const { data: completed } = await admin.from("bookings").select("*").eq("status", "completed").in("payment_status", ["paid", "partially_refunded"]);
  const { data: existing } = await admin.from("payouts").select("booking_ids");
  const paidOut = new Set((existing ?? []).flatMap((p) => p.booking_ids as string[]));
  const rows = ((completed ?? []) as Booking[])
    .filter((b) => !paidOut.has(b.id))
    .map((b) => ({
      studio_id: b.studio_id,
      amount: b.price.studio_payout,
      currency: b.price.currency,
      status: "scheduled",
      scheduled_for: new Date(new Date(b.ends_at).getTime() + PAYOUT_DELAY_DAYS * DAY).toISOString(),
      booking_ids: [b.id],
    }));
  if (rows.length) await admin.from("payouts").insert(rows);
  return rows.length;
}

async function sendDuePayouts(): Promise<number> {
  const { data } = await admin.from("payouts").select("*").in("status", ["scheduled", "failed"]).lte("scheduled_for", new Date().toISOString());
  let count = 0;
  for (const payout of data ?? []) {
    const destination = await studioAccountId(payout.studio_id);
    if (!destination) continue; // waits until the studio finishes payout onboarding
    try {
      const transfer = await stripe.transfers.create({
        amount: payout.amount,
        currency: payout.currency.toLowerCase(),
        destination,
        transfer_group: payout.booking_ids[0],
        metadata: { payout_id: payout.id },
      }, { idempotencyKey: `payout-${payout.id}` });
      await admin.from("payouts").update({ status: "paid", paid_at: new Date().toISOString(), provider_reference: transfer.id, failure_reason: null }).eq("id", payout.id);
      count++;
    } catch (error) {
      await admin.from("payouts").update({ status: "failed", failure_reason: (error as Error).message }).eq("id", payout.id);
    }
  }
  return count;
}

Deno.serve(handler(async (req) => {
  requireServiceRole(req);
  const released = await releaseExpiredHolds();
  const balances = await chargeBalances();
  const scheduled = await schedulePayouts();
  const sent = await sendDuePayouts();
  return json({ released, balances, scheduled, sent });
}));
