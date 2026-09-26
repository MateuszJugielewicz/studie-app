// Studio payout setup with Stripe Connect Express. Bank details are entered on Stripe's hosted pages.
import type Stripe from "npm:stripe@17.7.0";
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin, loadStudio, requireUser } from "../_shared/supabase.ts";
import { stripe } from "../_shared/stripe.ts";

const COUNTRY_CODES: Record<string, string> = {
  greece: "GR", denmark: "DK", danmark: "DK", sweden: "SE", sverige: "SE", norway: "NO", norge: "NO",
  germany: "DE", deutschland: "DE", "united kingdom": "GB", france: "FR", spain: "ES", italy: "IT",
  netherlands: "NL", poland: "PL", polska: "PL",
};

function countryCode(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (/^[A-Za-z]{2}$/.test(raw)) return raw.toUpperCase();
  return COUNTRY_CODES[raw.toLowerCase()] ?? "GR";
}

/** Stripe errors carry a readable message; show it instead of a generic failure. */
async function stripeCall<T>(work: () => Promise<T>): Promise<T> {
  try {
    return await work();
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const message = (error as { message?: string })?.message ?? "Stripe request failed.";
    throw new HttpError(400, `Stripe: ${message}`);
  }
}

function payoutState(account: Stripe.Account) {
  const bank = account.external_accounts?.data.find((a) => a.object === "bank_account") as Stripe.BankAccount | undefined;
  return { payouts_enabled: account.payouts_enabled ?? false, iban_last4: bank?.last4 ?? "" };
}

Deno.serve(handler(async (req, body) => {
  const user = await requireUser(req);
  const studio = await loadStudio(requireString(body, "studio_id"));
  if (studio.owner_id !== user.id) throw new HttpError(403, "forbidden");

  const { data: existing } = await admin.from("studio_payout_accounts").select("*").eq("studio_id", studio.id).maybeSingle();
  const account = existing ?? { studio_id: studio.id, account_holder: "", iban_last4: "", stripe_account_id: null, payouts_enabled: false };

  if (typeof body.account_holder === "string") account.account_holder = body.account_holder.slice(0, 200);

  // The connected account, if it still exists in this Stripe mode (test and live keys see different accounts).
  let connected: Stripe.Account | null = null;
  const needsStripe = body.action === "onboarding_link" || body.action === "sync" || body.action === "bank";
  if (account.stripe_account_id && needsStripe) {
    try {
      connected = await stripe.accounts.retrieve(account.stripe_account_id);
      if ((connected as { deleted?: boolean }).deleted) connected = null;
    } catch {
      connected = null;
    }
    if (connected) Object.assign(account, payoutState(connected));
    else if (body.action !== "sync") Object.assign(account, { stripe_account_id: null, payouts_enabled: false, iban_last4: "" });
  }

  let onboardingUrl: string | null = null;
  if ((body.action === "onboarding_link" || body.action === "bank") && !connected) {
    const { data: full } = await admin.from("studios").select("address, contact").eq("id", studio.id).single();
    connected = await stripeCall(() => stripe.accounts.create({
      type: "express",
      country: countryCode(full?.address?.country),
      email: full?.contact?.email || user.email,
      business_profile: { name: studio.name || undefined, mcc: "7929", product_description: "Recording studio sessions booked via EasySesh" },
      capabilities: { transfers: { requested: true } },
      metadata: { studio_id: studio.id },
    }));
    account.stripe_account_id = connected.id;
  }

  if (body.action === "bank") {
    // Bank details typed in the app. The app turns them into a Stripe token first, so the
    // number itself never reaches our servers.
    const token = requireString(body, "bank_token");
    const bank = await stripeCall(() => stripe.accounts.createExternalAccount(connected!.id, {
      external_account: token,
      default_for_currency: true,
    })) as Stripe.BankAccount;
    connected = await stripeCall(() => stripe.accounts.retrieve(connected!.id));
    Object.assign(account, payoutState(connected), { iban_last4: bank.last4 ?? account.iban_last4 });
  }

  if (body.action === "onboarding_link") {
    // Stripe's identity check (name, birth date, address, ID). The bank is added in the app, so
    // Stripe skips that step once a bank account is on file.
    const back = `${Deno.env.get("SUPABASE_URL")}/functions/v1/payout-return`;
    const link = await stripeCall(() => stripe.accountLinks.create({
      account: connected!.id,
      type: "account_onboarding",
      refresh_url: `${back}?to=refresh`,
      return_url: `${back}?to=done`,
    }));
    onboardingUrl = link.url;
  }

  const { data: saved, error } = await admin.from("studio_payout_accounts")
    .upsert({ ...account, updated_at: new Date().toISOString() }).select("*").single();
  if (error) throw new HttpError(400, error.message);
  return json({ account: saved, onboarding_url: onboardingUrl });
}));
