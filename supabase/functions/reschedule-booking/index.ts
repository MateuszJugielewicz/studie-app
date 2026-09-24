// Moves a confirmed booking to a new start time (same duration and price).
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin, bookingRole, loadBooking, loadStudio, requireUser, updateBooking } from "../_shared/supabase.ts";
import { paddedRange, validateTiming } from "../_shared/availability.ts";

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const booking = await loadBooking(requireString(body, "booking_id"));
  await bookingRole(user, booking);
  if (booking.status !== "confirmed" || new Date(booking.starts_at) <= new Date()) {
    throw new HttpError(409, "This booking can't be changed.");
  }

  const studio = await loadStudio(booking.studio_id);
  const start = new Date(requireString(body, "starts_at"));
  const problem = validateTiming(studio, start, booking.hours);
  if (problem) throw new HttpError(409, problem);

  const range = paddedRange(studio, start, booking.hours);
  const { data: busy } = await admin.rpc("studio_busy_intervals", { p_studio_ids: [studio.id], p_from: range.from, p_to: range.to });
  const clashes = (busy ?? []).filter((b: { starts_at: string; ends_at: string }) =>
    !(new Date(b.starts_at).getTime() === new Date(booking.starts_at).getTime() &&
      new Date(b.ends_at).getTime() === new Date(booking.ends_at).getTime()));
  if (clashes.length > 0) throw new HttpError(409, "slot_unavailable");

  try {
    return json(await updateBooking(booking.id, {
      starts_at: start.toISOString(),
      ends_at: new Date(start.getTime() + booking.hours * 3_600_000).toISOString(),
      changed_by: user.id,
    }));
  } catch (error) {
    if (error instanceof HttpError && /no_overlap|exclusion/i.test(error.message)) throw new HttpError(409, "slot_unavailable");
    throw error;
  }
}));
