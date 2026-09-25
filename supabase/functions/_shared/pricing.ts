// Mirrors ios/EasySesh/Core/PricingEngine.swift. The server is the source of truth for what is charged.
import type { BookedAddOn, CancellationPolicy, PriceBreakdown, ServiceAddOn, SessionType, Studio, UserRole } from "./types.ts";

/** EasySesh takes 10% of every sale; artists pay the studio's price with no extra fee. */
export const ARTIST_SERVICE_FEE_PERCENT = 0;
export const PLATFORM_FEE_PERCENT = 10;
export const PAYOUT_DELAY_DAYS = 2;
export const MAX_SESSION_HOURS = 12;

/** Integer percentage with half-up rounding (same as Money.percent in Swift). */
export function percent(amount: number, pct: number): number {
  return Math.floor((amount * pct + 50) / 100);
}

export function addOnAmount(addOn: ServiceAddOn, quantity: number, hours: number): number {
  switch (addOn.unit) {
    case "per_hour":
      return addOn.price * hours;
    case "per_session":
      return addOn.price;
    case "per_track":
      return addOn.price * quantity;
  }
}

export function quote(
  studio: Studio,
  sessionType: SessionType,
  hoursInput: number,
  selected: Record<string, number> = {},
): PriceBreakdown {
  const hours = Math.max(1, Math.floor(hoursInput));
  const sessionAmount = sessionType.hourly_rate * hours;
  let addOnsAmount = 0;
  for (const addOn of studio.add_ons ?? []) {
    const quantity = selected[addOn.id] ?? 0;
    if (quantity > 0) addOnsAmount += addOnAmount(addOn, quantity, hours);
  }
  const subtotal = sessionAmount + addOnsAmount;
  const serviceFee = percent(subtotal, ARTIST_SERVICE_FEE_PERCENT);
  const total = subtotal + serviceFee;

  const depositPercent = Math.min(Math.max(studio.booking_policy?.deposit_percent ?? 0, 0), 100);
  const deposit = depositPercent > 0 && depositPercent < 100 ? percent(subtotal, depositPercent) : 0;
  const dueNow = deposit > 0 ? deposit + serviceFee : total;
  // Studios can have a special deal (their own platform fee), set by an admin.
  const commission = percent(subtotal, studio.platform_fee_percent ?? PLATFORM_FEE_PERCENT);

  return {
    currency: studio.currency,
    hourly_rate: sessionType.hourly_rate,
    hours,
    session_amount: sessionAmount,
    add_ons_amount: addOnsAmount,
    subtotal,
    service_fee: serviceFee,
    total,
    deposit_amount: deposit,
    due_now: dueNow,
    due_later: total - dueNow,
    studio_commission: commission,
    studio_payout: subtotal - commission,
  };
}

export function bookedAddOns(studio: Studio, selected: Record<string, number>, hours: number): BookedAddOn[] {
  return (studio.add_ons ?? [])
    .filter((a) => (selected[a.id] ?? 0) > 0)
    .map((a) => ({ id: a.id, name: a.name, quantity: selected[a.id], amount: addOnAmount(a, selected[a.id], hours) }));
}

export function refundPercent(policy: CancellationPolicy, hoursUntilStart: number): number {
  switch (policy) {
    case "flexible":
      return hoursUntilStart >= 24 ? 100 : 0;
    case "moderate":
      if (hoursUntilStart >= 72) return 100;
      if (hoursUntilStart >= 24) return 50;
      return 0;
    case "strict":
      return hoursUntilStart >= 24 * 7 ? 50 : 0;
  }
}

export function refundAmount(
  price: PriceBreakdown,
  amountPaid: number,
  policy: CancellationPolicy,
  startsAt: Date,
  cancelledBy: UserRole,
  now = new Date(),
): number {
  if (amountPaid <= 0) return 0;
  if (cancelledBy !== "artist") return amountPaid;
  const hours = (startsAt.getTime() - now.getTime()) / 3_600_000;
  const pct = refundPercent(policy, hours);
  if (pct === 100) return amountPaid;
  return percent(Math.max(amountPaid - price.service_fee, 0), pct);
}

/** Cash is offered when the studio allows it and no card deposit is required. */
export function acceptsCash(studio: Studio): boolean {
  return (studio.booking_policy?.accepts_cash ?? true) && (studio.booking_policy?.deposit_percent ?? 0) === 0;
}
