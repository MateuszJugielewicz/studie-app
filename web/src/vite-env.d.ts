/// <reference types="vite/client" />

declare const __SHARED_CONFIG__: { supabaseUrl: string; supabaseAnonKey: string; stripePublishableKey: string; supportEmail: string };

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
  readonly VITE_STRIPE_PUBLISHABLE_KEY?: string;
  readonly VITE_SUPPORT_EMAIL?: string;
  readonly VITE_GOOGLE_CLIENT_ID?: string;
}
