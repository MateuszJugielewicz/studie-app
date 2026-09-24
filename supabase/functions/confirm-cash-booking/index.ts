// Artist chooses to pay cash at the studio. No card is charged; EasySesh's 10% platform fee is
// booked to the studio's fee ledger when the session is completed.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { loadBooking, loadStudio, requireUser, updateBooking } from "../_shared/supabase.ts";
import { acceptsCash } from "../_shared/pricing.ts";

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const booking = await loadBooking(requireString(body, "booking_id"));
  if (booking.artist_id !== user.id) throw new HttpError(403, "forbidden");
  if (booking.status !== "awaiting_payment") throw new HttpError(409, "This booking is no longer awaiting payment.");

  const studio = await loadStudio(booking.studio_id);
  if (!acceptsCash(studio)) throw new HttpError(400, "This studio only accepts payment in the app.");
  const instant = studio.booking_policy?.instant_book ?? true;

  return json(await updateBooking(booking.id, {
    status: instant ? "confirmed" : "pending_approval",
    payment_method: "cash",
    payment_status: "pay_at_studio",
    changed_by: user.id,
  }));
}));
