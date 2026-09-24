// Admin-issued refund (disputes, goodwill). Amount is capped at what the artist has paid net of refunds.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { amountPaid, loadBooking, requireAdmin, updateBooking } from "../_shared/supabase.ts";
import { refundBooking } from "../_shared/refunds.ts";

Deno.serve(handler(async (req, body) => {
  await requireAdmin(req);
  const booking = await loadBooking(requireString(body, "booking_id"));
  const paid = await amountPaid(booking.id);
  const amount = body.amount === undefined ? paid : Math.floor(Number(body.amount));
  if (!Number.isFinite(amount) || amount <= 0) throw new HttpError(400, "Enter an amount to refund.");
  if (amount > paid) throw new HttpError(400, `At most ${paid} can be refunded.`);

  await refundBooking(booking, amount, String(body.reason ?? "Admin refund"));
  const updated = await updateBooking(booking.id, {
    refund_amount: booking.refund_amount + amount,
    payment_status: amount >= paid ? "refunded" : "partially_refunded",
  });
  return json(updated);
}));
