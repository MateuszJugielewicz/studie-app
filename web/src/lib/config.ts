/** Public keys (safe in the browser; data is protected by row-level security). */
export const config = {
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL || __SHARED_CONFIG__.supabaseUrl || "https://gdebbieifsvspszmevwa.supabase.co",
  supabaseAnonKey: import.meta.env.VITE_SUPABASE_ANON_KEY || __SHARED_CONFIG__.supabaseAnonKey,
  stripePublishableKey: import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY || __SHARED_CONFIG__.stripePublishableKey,
  supportEmail: import.meta.env.VITE_SUPPORT_EMAIL || __SHARED_CONFIG__.supportEmail,
};

/** Public contact addresses (support also comes from the shared app config). */
export const CONTACT = {
  support: config.supportEmail || "support@easysesh.live",
  general: "easysesh@easysesh.live",
};

/** Platform-wide commercial settings, the same as the apps and supabase/functions/_shared/pricing.ts. */
export const PlatformConfig = {
  ARTIST_SERVICE_FEE_PERCENT: 0,
  PLATFORM_FEE_PERCENT: 10,
  PAYOUT_DELAY_DAYS: 2,
  MAX_SESSION_HOURS: 12,
};

/** Bump together with the apps when a legal document changes materially. */
export const TERMS_VERSION = "2026-09-26";
