import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { existsSync, readFileSync } from "node:fs";

// The public keys the apps ship with (ios/Config/App.xcconfig) are the defaults, so the website,
// iOS and Android always talk to the same backend. VITE_* variables override them.
function sharedConfig(): Record<string, string> {
  const file = new URL("../ios/Config/App.xcconfig", import.meta.url);
  if (!existsSync(file)) return {};
  const values: Record<string, string> = {};
  for (const raw of readFileSync(file, "utf8").split("\n")) {
    const line = raw.trim();
    if (line.startsWith("//") || !line.includes("=")) continue;
    values[line.slice(0, line.indexOf("=")).trim()] = line.slice(line.indexOf("=") + 1).trim().replace("$()", "");
  }
  return values;
}

const shared = sharedConfig();

export default defineConfig({
  plugins: [react()],
  define: {
    __SHARED_CONFIG__: JSON.stringify({
      supabaseUrl: shared.EASYSESH_SUPABASE_URL ?? "",
      supabaseAnonKey: shared.EASYSESH_SUPABASE_ANON_KEY ?? "",
      stripePublishableKey: shared.EASYSESH_STRIPE_PUBLISHABLE_KEY ?? "",
      supportEmail: shared.EASYSESH_SUPPORT_EMAIL ?? "",
    }),
  },
  // The legal texts live outside web/ (shared with the apps).
  server: { fs: { allow: [".."] } },
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          react: ["react", "react-dom", "react-router-dom"],
          supabase: ["@supabase/supabase-js"],
        },
      },
    },
  },
});
