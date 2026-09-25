// Server-side validation of a requested slot (mirrors ios/EasySesh/Core/AvailabilityEngine.swift).
// Opening hours are wall-clock times in the studio's time zone.
import type { Studio } from "./types.ts";

const MINUTE = 60_000;

/** Wall-clock parts of an instant in a time zone. */
export function zonedParts(date: Date, timeZone: string) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      weekday: "short",
    }).formatToParts(date).map((p) => [p.type, p.value]),
  );
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  return {
    weekday: weekdays.indexOf(parts.weekday) + 1, // 1 = Sunday, like Calendar.weekday
    minuteOfDay: Number(parts.hour) * 60 + Number(parts.minute),
  };
}

/** Whether [start, start+hours) fits inside the studio's opening hours (same day or an overnight window). */
export function fitsOpeningHours(studio: Studio, start: Date, hours: number): boolean {
  const { weekday, minuteOfDay } = zonedParts(start, studio.timezone || "UTC");
  const duration = hours * 60;
  const windows = [
    { weekday, offset: 0 },
    { weekday: weekday === 1 ? 7 : weekday - 1, offset: 24 * 60 }, // previous day running past midnight
  ];
  return windows.some(({ weekday: day, offset }) => {
    const h = studio.opening_hours.find((o) => o.weekday === day);
    if (!h || h.is_closed) return false;
    const closes = h.closes_at <= h.opens_at ? h.closes_at + 24 * 60 : h.closes_at;
    const begin = minuteOfDay + offset;
    return begin >= h.opens_at && begin + duration <= closes;
  });
}

export function validateTiming(studio: Studio, start: Date, hours: number, now = new Date()): string | null {
  const policy = studio.booking_policy ?? {};
  if (Number.isNaN(start.getTime())) return "Invalid start time.";
  if (start.getTime() < now.getTime() + (policy.minimum_notice_hours ?? 0) * 60 * MINUTE) {
    return `This studio needs at least ${policy.minimum_notice_hours ?? 0} hours' notice.`;
  }
  if (start.getTime() > now.getTime() + ((policy.max_advance_days ?? 90) + 1) * 24 * 60 * MINUTE) {
    return `You can book at most ${policy.max_advance_days ?? 90} days ahead.`;
  }
  if (!fitsOpeningHours(studio, start, hours)) return "slot_unavailable";
  return null;
}

/** Buffer-padded range to test against existing bookings/blocks. */
export function paddedRange(studio: Studio, start: Date, hours: number) {
  const buffer = (studio.booking_policy?.buffer_minutes ?? 0) * MINUTE;
  return {
    from: new Date(start.getTime() - buffer).toISOString(),
    to: new Date(start.getTime() + hours * 60 * MINUTE + buffer).toISOString(),
  };
}
