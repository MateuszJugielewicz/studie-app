// Creates a booking in `awaiting_payment` with a server-computed price.
// The slot is held for 30 minutes; the exclusion constraint on `bookings` prevents double booking.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin, loadStudio, requireUser } from "../_shared/supabase.ts";
import { bookedAddOns, MAX_SESSION_HOURS, quote } from "../_shared/pricing.ts";
import { paddedRange, validateTiming } from "../_shared/availability.ts";

function reference(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  return "SON-" + Array.from(bytes, (b) => alphabet[b % alphabet.length]).join("");
}

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  if (user.role !== "artist") throw new HttpError(403, "Only artist accounts can book sessions.");

  const studio = await loadStudio(requireString(body, "studio_id"));
  if (studio.status !== "approved" || !studio.is_active) throw new HttpError(404, "not_found");

  const sessionType = studio.session_types.find((t) => t.id === body.session_type_id);
  if (!sessionType) throw new HttpError(400, "Unknown session type.");

  const hours = Number(body.hours);
  if (!Number.isInteger(hours) || hours < sessionType.minimum_hours) {
    throw new HttpError(400, `Minimum ${sessionType.minimum_hours} hours for ${sessionType.name}.`);
  }
  if (hours > MAX_SESSION_HOURS) throw new HttpError(400, `Sessions can be at most ${MAX_SESSION_HOURS} hours.`);

  const start = new Date(requireString(body, "starts_at"));
  const timingProblem = validateTiming(studio, start, hours);
  if (timingProblem) throw new HttpError(409, timingProblem);

  // Buffer-aware clash check (the DB constraint covers exact overlaps).
  const range = paddedRange(studio, start, hours);
  const { data: busy } = await admin.rpc("studio_busy_intervals", { p_studio_ids: [studio.id], p_from: range.from, p_to: range.to });
  if ((busy ?? []).length > 0) throw new HttpError(409, "slot_unavailable");

  const selected: Record<string, number> = {};
  for (const item of (body.add_ons as { id: string; quantity: number }[] | undefined) ?? []) {
    const quantity = Math.min(Math.max(Math.floor(Number(item.quantity) || 0), 0), 50);
    if (quantity > 0 && studio.add_ons.some((a) => a.id === item.id)) selected[item.id] = quantity;
  }

  const { data: artist } = await admin.from("artist_profiles").select("artist_name").eq("id", user.id).maybeSingle();
  const price = quote(studio, sessionType, hours, selected);

  const { data, error } = await admin.from("bookings").insert({
    reference: reference(),
    artist_id: user.id,
    studio_id: studio.id,
    artist_name: artist?.artist_name || user.email,
    studio_name: studio.name,
    session_type_id: sessionType.id,
    session_type_name: sessionType.name,
    starts_at: start.toISOString(),
    ends_at: new Date(start.getTime() + hours * 3_600_000).toISOString(),
    hours,
    add_ons: bookedAddOns(studio, selected, hours),
    price,
    notes: String(body.notes ?? "").slice(0, 1000),
    changed_by: user.id,
  }).select("*").single();

  if (error) {
    if (error.code === "23P01") throw new HttpError(409, "slot_unavailable");
    throw new HttpError(400, error.message);
  }
  return json(data);
}));
