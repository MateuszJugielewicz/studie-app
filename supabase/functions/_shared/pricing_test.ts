import { assertEquals } from "jsr:@std/assert@1";
import { acceptsCash, quote, refundAmount, refundPercent } from "./pricing.ts";
import { fitsOpeningHours, zonedParts } from "./availability.ts";
import type { Studio } from "./types.ts";

// Same fixtures as ios/SonoraTests — keeps client and server prices identical.
const studio: Studio = {
  id: "s1",
  owner_id: "o1",
  name: "Test",
  timezone: "Europe/Athens",
  currency: "EUR",
  session_types: [{ id: "rec", name: "Recording", details: "", hourly_rate: 2500, minimum_hours: 2, includes_engineer: false }],
  add_ons: [
    { id: "mixing", kind: "mixing", name: "Mixing", price: 7500, unit: "per_track" },
    { id: "producer", kind: "producer", name: "Producer", price: 2500, unit: "per_hour" },
  ],
  opening_hours: [
    { weekday: 2, is_closed: false, opens_at: 600, closes_at: 1320 }, // Monday 10–22
    { weekday: 6, is_closed: false, opens_at: 720, closes_at: 1560 }, // Friday 12–02
  ],
  booking_policy: { deposit_percent: 0 },
  status: "approved",
  is_active: true,
};

Deno.test("quote without add-ons", () => {
  const p = quote(studio, studio.session_types[0], 3);
  assertEquals(p.subtotal, 7500);
  assertEquals(p.service_fee, 0);
  assertEquals(p.total, 7500);
  assertEquals(p.due_now, 7500);
  assertEquals(p.studio_commission, 750); // 10% platform fee
  assertEquals(p.studio_payout, 6750);
});

Deno.test("quote with add-ons and deposit", () => {
  const p = quote({ ...studio, booking_policy: { deposit_percent: 30 } }, studio.session_types[0], 2, { mixing: 2, producer: 1 });
  assertEquals(p.session_amount, 5000);
  assertEquals(p.add_ons_amount, 15000 + 5000);
  assertEquals(p.subtotal, 25000);
  assertEquals(p.service_fee, 0);
  assertEquals(p.deposit_amount, 7500);
  assertEquals(p.due_now, 7500);
  assertEquals(p.due_later, 17500);
  assertEquals(p.studio_commission, 2500);
});

Deno.test("refund policies", () => {
  assertEquals(refundPercent("flexible", 25), 100);
  assertEquals(refundPercent("flexible", 23), 0);
  assertEquals(refundPercent("moderate", 80), 100);
  assertEquals(refundPercent("moderate", 30), 50);
  assertEquals(refundPercent("strict", 24 * 8), 50);
  assertEquals(refundPercent("strict", 24 * 6), 0);
  const p = quote(studio, studio.session_types[0], 3);
  const now = new Date("2026-10-01T10:00:00Z");
  const in30h = new Date(now.getTime() + 30 * 3_600_000);
  assertEquals(refundAmount(p, p.total, "moderate", in30h, "artist", now), 3750); // 50%
  assertEquals(refundAmount(p, p.total, "strict", in30h, "studio_owner", now), 7500); // studio cancels: full
});

Deno.test("opening hours in studio time zone incl. past midnight", () => {
  // 2026-10-05 is a Monday. 07:00Z = 10:00 in Athens (UTC+3).
  assertEquals(zonedParts(new Date("2026-10-05T07:00:00Z"), "Europe/Athens"), { weekday: 2, minuteOfDay: 600 });
  assertEquals(fitsOpeningHours(studio, new Date("2026-10-05T07:00:00Z"), 2), true);
  assertEquals(fitsOpeningHours(studio, new Date("2026-10-05T06:00:00Z"), 2), false); // 09:00 local
  assertEquals(fitsOpeningHours(studio, new Date("2026-10-05T18:00:00Z"), 2), false); // 21:00–23:00 > close
  // Friday 2026-10-09 23:00 local → Saturday 01:00 fits the Friday 12–02 window.
  assertEquals(fitsOpeningHours(studio, new Date("2026-10-09T20:00:00Z"), 3), true);
  assertEquals(fitsOpeningHours(studio, new Date("2026-10-09T22:00:00Z"), 1), true); // Sat 01:00–02:00
  assertEquals(fitsOpeningHours(studio, new Date("2026-10-09T22:00:00Z"), 2), false);
});

Deno.test("cash only without deposit", () => {
  assertEquals(acceptsCash(studio), true);
  assertEquals(acceptsCash({ ...studio, booking_policy: { accepts_cash: false } }), false);
  assertEquals(acceptsCash({ ...studio, booking_policy: { deposit_percent: 30 } }), false);
});
