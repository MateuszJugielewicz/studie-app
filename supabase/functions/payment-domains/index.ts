// Registers the website's domains with Stripe so Apple Pay, Google Pay, Link and PayPal show up in the
// web checkout (Stripe verifies Apple Pay for us). Safe to run again, and needed again after
// switching to live Stripe keys, because test and live mode keep their own list.
//   {}  → registers SITE_DOMAINS (or easysesh.live + www.easysesh.live) and returns each one's status
import { handler, json } from "../_shared/http.ts";
import { stripe } from "../_shared/stripe.ts";
import { audit, requireStaff } from "../_shared/staff.ts";

const DOMAINS = (Deno.env.get("SITE_DOMAINS") ?? "easysesh.live,www.easysesh.live").split(",").map((d) => d.trim()).filter(Boolean);

Deno.serve(handler(async (req) => {
  const staff = await requireStaff(req, "owner");
  const existing = await stripe.paymentMethodDomains.list({ limit: 100 });
  const results = [];
  for (const domain of DOMAINS) {
    let entry = existing.data.find((d) => d.domain_name === domain);
    if (!entry) entry = await stripe.paymentMethodDomains.create({ domain_name: domain, enabled: true });
    else if (entry.apple_pay.status !== "active") entry = await stripe.paymentMethodDomains.validate(entry.id);
    results.push({
      domain,
      apple_pay: entry.apple_pay.status,
      google_pay: entry.google_pay.status,
      link: entry.link.status,
      paypal: entry.paypal.status,
      error: entry.apple_pay.status_details?.error_message ?? null,
    });
  }
  await audit(staff, "register_payment_domains", { table: "stripe" }, null, { domains: DOMAINS });
  return json({ live: (Deno.env.get("STRIPE_SECRET_KEY") ?? "").startsWith("sk_live"), domains: results });
}));
