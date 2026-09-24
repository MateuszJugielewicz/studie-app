// Studio payout setup with Stripe Connect Express. Bank details are entered on Stripe's hosted pages.
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin, loadStudio, requireUser } from "../_shared/supabase.ts";
import { stripe } from "../_shared/stripe.ts";

const COUNTRY_CODES: Record<string, string> = { greece: "GR", denmark: "DK", sweden: "SE", norway: "NO", germany: "DE", "united kingdom": "GB" };

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const studio = await loadStudio(requireString(body, "studio_id"));
  if (studio.owner_id !== user.id) throw new HttpError(403, "forbidden");

  const { data: existing } = await admin.from("studio_payout_accounts").select("*").eq("studio_id", studio.id).maybeSingle();
  let account = existing ?? { studio_id: studio.id, account_holder: "", iban_last4: "", stripe_account_id: null, payouts_enabled: false };

  if (typeof body.account_holder === "string") account.account_holder = body.account_holder.slice(0, 200);

  let onboardingUrl: string | null = null;
  if (body.action === "onboarding_link") {
    if (!account.stripe_account_id) {
      const { data: full } = await admin.from("studios").select("address, contact").eq("id", studio.id).single();
      const country = COUNTRY_CODES[String(full?.address?.country ?? "").toLowerCase()] ?? "GR";
      const connected = await stripe.accounts.create({
        type: "express",
        country,
        email: full?.contact?.email || user.email,
        business_profile: { name: studio.name, mcc: "7929", product_description: "Recording studio sessions booked via EasySesh" },
        capabilities: { transfers: { requested: true } },
        metadata: { studio_id: studio.id },
      });
      account.stripe_account_id = connected.id;
    }
    const link = await stripe.accountLinks.create({
      account: account.stripe_account_id!,
      type: "account_onboarding",
      refresh_url: `${Deno.env.get("PUBLIC_SITE_URL") ?? "https://sonora.app"}/payouts/refresh`,
      return_url: `${Deno.env.get("PUBLIC_SITE_URL") ?? "https://sonora.app"}/payouts/done`,
    });
    onboardingUrl = link.url;
  }

  const { data: saved, error } = await admin.from("studio_payout_accounts")
    .upsert({ ...account, updated_at: new Date().toISOString() }).select("*").single();
  if (error) throw new HttpError(400, error.message);
  return json({ account: saved, onboarding_url: onboardingUrl });
}));
