// GDPR art. 15/20: returns everything EasySesh stores about the caller as JSON.
import { handler, json } from "../_shared/http.ts";
import { admin, requireUser } from "../_shared/supabase.ts";

Deno.serve(handler(async (req) => {
  const user = await requireUser(req);
  const id = user.id;

  const [profile, artist, studios, bookings, reviews, reports, notifications, devices] = await Promise.all([
    admin.from("profiles").select("id, email, role, status, is_verified, settings, accepted_terms_version, accepted_terms_at, created_at").eq("id", id).single(),
    admin.from("artist_profiles").select("*").eq("id", id).maybeSingle(),
    admin.from("studios").select("*").eq("owner_id", id),
    admin.from("bookings").select("*").eq("artist_id", id),
    admin.from("reviews").select("*").eq("artist_id", id),
    admin.from("reports").select("*").eq("reporter_id", id),
    admin.from("notifications").select("*").eq("user_id", id),
    admin.from("device_tokens").select("platform, created_at").eq("user_id", id),
  ]);

  const studioIds = (studios.data ?? []).map((s) => s.id);
  const studioBookings = studioIds.length ? await admin.from("bookings").select("*").in("studio_id", studioIds) : { data: [] };
  const allBookingIds = [...(bookings.data ?? []), ...(studioBookings.data ?? [])].map((b) => b.id);
  const transactions = allBookingIds.length
    ? await admin.from("transactions").select("booking_id, kind, method, status, amount, currency, receipt_number, card_brand, card_last4, created_at").in("booking_id", allBookingIds)
    : { data: [] };
  const conversations = await admin.from("conversations").select("*").or(
    studioIds.length ? `artist_id.eq.${id},studio_id.in.(${studioIds.join(",")})` : `artist_id.eq.${id}`,
  );
  const messages = await admin.from("messages").select("conversation_id, kind, body, created_at").eq("sender_id", id);
  const payouts = studioIds.length ? await admin.from("payouts").select("*").in("studio_id", studioIds) : { data: [] };
  const support = await admin.from("support_tickets").select("*, support_messages(from_admin, body, created_at)").eq("user_id", id);
  const fees = studioIds.length ? await admin.from("studio_fee_ledger").select("*").in("studio_id", studioIds) : { data: [] };

  return json({
    exported_at: new Date().toISOString(),
    notice: "This file contains the personal data EasySesh holds about you (GDPR art. 15 and 20). Card numbers are held by Stripe and never stored by EasySesh.",
    account: profile.data,
    artist_profile: artist.data,
    studios: studios.data,
    bookings_as_artist: bookings.data,
    bookings_at_my_studio: studioBookings.data,
    payments: transactions.data,
    payouts: payouts.data,
    platform_fees: fees.data,
    conversations: conversations.data,
    messages_sent: messages.data,
    support_requests: support.data,
    reviews_written: reviews.data,
    reports_made: reports.data,
    notifications: notifications.data,
    devices: devices.data,
  });
}));
