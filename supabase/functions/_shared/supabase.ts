import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { HttpError } from "./http.ts";
import type { Booking, Profile, Studio } from "./types.ts";

/** Service-role client: bypasses RLS, so every function checks permissions explicitly. */
export const admin: SupabaseClient = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

/** Resolves the calling user from the Authorization header and loads their profile. */
export async function requireUser(req: Request): Promise<Profile> {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) throw new HttpError(401, "Please sign in to continue.");
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) throw new HttpError(401, "Please sign in to continue.");
  const { data: profile } = await admin.from("profiles").select("*").eq("id", data.user.id).single();
  if (!profile) throw new HttpError(401, "Please sign in to continue.");
  if (profile.status !== "active") throw new HttpError(403, "account_suspended");
  return profile as Profile;
}

/** Assurance level from the (already verified) access token: "aal2" = signed in with a second factor. */
function tokenAal(req: Request): string {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  try {
    const payload = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload.aal ?? "aal1";
  } catch {
    return "aal1";
  }
}

/** Admins must be signed in with MFA. */
export async function requireAdmin(req: Request): Promise<Profile> {
  const user = await requireUser(req);
  if (user.role !== "admin") throw new HttpError(403, "forbidden");
  if (tokenAal(req) !== "aal2") throw new HttpError(403, "Admin actions require two-factor authentication.");
  return user;
}

/** Studio-side actions need an admin-approved studio owned by the caller. */
export function requireApprovedStudio(user: Profile, studio: Studio) {
  if (user.role !== "studio_owner" || studio.owner_id !== user.id || studio.status !== "approved") {
    throw new HttpError(403, "Your studio must be approved by EasySesh before you can do this.");
  }
}

/** Only the service role (cron / database triggers) may call internal functions. */
export function requireServiceRole(req: Request) {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (token !== Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")) throw new HttpError(401, "forbidden");
}

export async function loadBooking(id: string): Promise<Booking> {
  const { data } = await admin.from("bookings").select("*").eq("id", id).single();
  if (!data) throw new HttpError(404, "not_found");
  return data as Booking;
}

export async function loadStudio(id: string): Promise<Studio> {
  const { data } = await admin.from("studios").select("*").eq("id", id).single();
  if (!data) throw new HttpError(404, "not_found");
  return data as Studio;
}

export async function updateBooking(id: string, patch: Partial<Booking>): Promise<Booking> {
  const { data, error } = await admin.from("bookings").update(patch).eq("id", id).select("*").single();
  if (error) throw new HttpError(400, error.message);
  return data as Booking;
}

/** Artist, studio owner or admin – returns which side the caller is on. */
export async function bookingRole(user: Profile, booking: Booking): Promise<"artist" | "studio_owner" | "admin"> {
  if (booking.artist_id === user.id) return "artist";
  const studio = await loadStudio(booking.studio_id);
  if (studio.owner_id === user.id) {
    requireApprovedStudio(user, studio);
    return "studio_owner";
  }
  if (user.role === "admin") return "admin";
  throw new HttpError(403, "forbidden");
}

/** Sum of successful charges minus refunds. */
export async function amountPaid(bookingId: string): Promise<number> {
  const { data } = await admin.from("transactions").select("kind, amount, status").eq("booking_id", bookingId).eq("status", "succeeded");
  return (data ?? []).reduce((sum, t) => sum + (t.kind === "refund" ? -t.amount : t.amount), 0);
}
