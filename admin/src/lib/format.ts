export function money(minor: number | null | undefined, currency: string): string {
  const value = (minor ?? 0) / 100;
  return new Intl.NumberFormat("en-GB", { style: "currency", currency, maximumFractionDigits: value % 1 === 0 ? 0 : 2 }).format(value);
}

export function date(value: string | null | undefined, withTime = false): string {
  if (!value) return "–";
  return new Date(value).toLocaleString("en-GB", withTime
    ? { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }
    : { day: "numeric", month: "short", year: "numeric" });
}

export function label(value: string): string {
  return value.replace(/_/g, " ").replace(/^\w/, (c) => c.toUpperCase());
}

/** Sums amounts per currency, e.g. { EUR: 12000, DKK: 45000 }. */
export function sumByCurrency<T>(items: T[], currency: (t: T) => string, amount: (t: T) => number): Record<string, number> {
  const result: Record<string, number> = {};
  for (const item of items) result[currency(item)] = (result[currency(item)] ?? 0) + amount(item);
  return result;
}

export function moneyTotals(totals: Record<string, number>): string {
  const entries = Object.entries(totals);
  return entries.length ? entries.map(([c, v]) => money(v, c)).join(" · ") : "–";
}
