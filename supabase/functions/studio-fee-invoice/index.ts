// Admin: invoice a studio for platform fees it owes from cash bookings (Stripe Invoicing, 14 days).
import { handler, HttpError, json, requireString } from "../_shared/http.ts";
import { admin, loadStudio, requireAdmin } from "../_shared/supabase.ts";
import { ensureCustomer, stripe } from "../_shared/stripe.ts";
import type { Profile } from "../_shared/types.ts";

Deno.serve(handler(async (req, body) => {
  await requireAdmin(req);
  const studio = await loadStudio(requireString(body, "studio_id"));
  const currency = requireString(body, "currency").toUpperCase();

  const { data: rows } = await admin.from("studio_fee_ledger").select("amount").eq("studio_id", studio.id).eq("currency", currency);
  const { data: open } = await admin.from("studio_fee_invoices").select("amount").eq("studio_id", studio.id).eq("currency", currency).eq("status", "open");
  const owed = (rows ?? []).reduce((s, r) => s + r.amount, 0) - (open ?? []).reduce((s, r) => s + r.amount, 0);
  if (owed <= 0) throw new HttpError(400, "Nothing to invoice – open invoices already cover the balance.");

  const { data: owner } = await admin.from("profiles").select("*").eq("id", studio.owner_id).single();
  const customer = await ensureCustomer(owner as Profile);

  const invoice = await stripe.invoices.create({
    customer,
    currency: currency.toLowerCase(),
    collection_method: "send_invoice",
    days_until_due: 14,
    description: `EasySesh platform fees (10%) for cash bookings – ${studio.name}`,
    metadata: { studio_id: studio.id, kind: "platform_fees" },
  });
  await stripe.invoiceItems.create({ customer, invoice: invoice.id, amount: owed, currency: currency.toLowerCase(), description: "Platform fees for cash bookings" });
  const finalized = await stripe.invoices.finalizeInvoice(invoice.id!);
  await stripe.invoices.sendInvoice(finalized.id!);

  const { data: saved, error } = await admin.from("studio_fee_invoices").insert({
    studio_id: studio.id, amount: owed, currency, stripe_invoice_id: finalized.id, hosted_invoice_url: finalized.hosted_invoice_url,
  }).select("*").single();
  if (error) throw new HttpError(400, error.message);
  return json(saved);
}));
