/** Public keys (safe in the browser; data is protected by row-level security). */
export const config = {
  supabaseUrl: import.meta.env.VITE_SUPABASE_URL || __SHARED_CONFIG__.supabaseUrl || "https://gdebbieifsvspszmevwa.supabase.co",
  supabaseAnonKey: import.meta.env.VITE_SUPABASE_ANON_KEY || __SHARED_CONFIG__.supabaseAnonKey,
  stripePublishableKey: import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY || __SHARED_CONFIG__.stripePublishableKey,
  supportEmail: import.meta.env.VITE_SUPPORT_EMAIL || __SHARED_CONFIG__.supportEmail,
  /** Google OAuth web client (Google Cloud → Credentials). Its secret lives only in Supabase. */
  googleClientId: import.meta.env.VITE_GOOGLE_CLIENT_ID || "579827968857-6ageejk9t18cji1qgo5eooi35eu5di1i.apps.googleusercontent.com",
};

/** Public contact addresses (support also comes from the shared app config). */
export const CONTACT = {
  support: config.supportEmail || "support@easysesh.live",
  general: "easysesh@easysesh.live",
  instagram: "https://www.instagram.com/easysesh.live",
  instagramHandle: "@easysesh.live",
};

/** Platform-wide commercial settings, the same as the apps and supabase/functions/_shared/pricing.ts. */
export const PlatformConfig = {
  ARTIST_SERVICE_FEE_PERCENT: 0,
  PLATFORM_FEE_PERCENT: 10,
  PAYOUT_DELAY_DAYS: 2,
  MAX_SESSION_HOURS: 12,
  /**
   * Card payments and payouts (Stripe) aren't live yet. Until they are, studios can skip the payout
   * setup; set this to true at launch and every studio without payouts is asked to set them up.
   */
  PAYMENTS_LIVE: false,
  /** Sign in with Apple isn't set up in Supabase yet; set to true to show the button again. */
  APPLE_SIGN_IN: false,
};

/** Bump together with the apps when a legal document changes materially. */
export const TERMS_VERSION = "2026-09-26";
