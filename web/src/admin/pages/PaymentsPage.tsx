import { useState } from "react";
import { ActionButton, Badge, PageState, Stat, Tabs } from "../components";
import type { FeeBalance } from "../lib/types";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label, money, moneyTotals, sumByCurrency } from "../lib/format";

type Tab = "transactions" | "fees" | "payouts" | "cash" | "invoices" | "refunds" | "failures";

export default function PaymentsPage() {
  const api = useApi();
  const transactions = useLoad(() => api.transactions());
  const payouts = useLoad(() => api.payouts());
  const studios = useLoad(() => api.studios());
  const balances = useLoad(() => api.feeBalances());
  const invoices = useLoad(() => api.feeInvoices());
  const [tab, setTab] = useState<Tab>("transactions");

  const tx = transactions.data ?? [];
  const po = payouts.data ?? [];
  const studioName = (id: string) => studios.data?.find((s) => s.id === id)?.name ?? id.slice(0, 8);
  const succeeded = tx.filter((t) => t.status === "succeeded");
  const charges = succeeded.filter((t) => t.kind !== "refund");
  const refunds = succeeded.filter((t) => t.kind === "refund");
  const failures = tx.filter((t) => t.status === "failed");

  return (
    <>
      <header className="page-header"><h1>Payments</h1></header>
      <section className="grid stats">
        <Stat title="Payment volume" value={moneyTotals(sumByCurrency(charges, (t) => t.currency, (t) => t.amount))} />
        <Stat title="Platform fees" value={moneyTotals(sumByCurrency(charges, (t) => t.currency, (t) => t.platform_fee))} />
        <Stat title="Paid to studios" value={moneyTotals(sumByCurrency(po.filter((p) => p.status === "paid"), (p) => p.currency, (p) => p.amount))} />
        <Stat title="Upcoming payouts" value={moneyTotals(sumByCurrency(po.filter((p) => p.status === "scheduled" || p.status === "in_transit"), (p) => p.currency, (p) => p.amount))} />
        <Stat title="Refunded" value={moneyTotals(sumByCurrency(refunds, (t) => t.currency, (t) => t.amount))} />
        <Stat title="Failed payments" value={failures.length} />
      </section>
      <Tabs<Tab>
        value={tab}
        onChange={setTab}
        tabs={[
          { id: "transactions", title: "Transactions", count: tx.length },
          { id: "fees", title: "Platform fees" },
          { id: "payouts", title: "Studio payouts", count: po.length },
          { id: "cash", title: "Cash & fees owed", count: (balances.data ?? []).filter((b) => b.balance > 0).length },
          { id: "invoices", title: "Fee invoices", count: (invoices.data ?? []).filter((i) => i.status === "open" || i.status === "collections").length },
          { id: "refunds", title: "Refunds", count: refunds.length },
          { id: "failures", title: "Payment failures", count: failures.length },
        ]}
      />
      <PageState loading={transactions.loading && !transactions.data} error={transactions.error ?? payouts.error}>
        <div className="card flush">
          {tab === "cash" ? (
            <>
              <p className="muted small" style={{ padding: "12px 16px 0" }}>
                For cash bookings the studio collects the money and owes EasySesh its platform fee (10%, or its special deal). Fees are deducted automatically from the studio's next payout. What's left is invoiced on the 1st of each month (due in 14 days); reminders go out automatically, and 14 days after the due date the studio is suspended and the debt goes to collection.
              </p>
              <table>
                <thead><tr><th>Studio</th><th>Owed</th><th>Last cash booking</th><th>Open invoices</th><th></th></tr></thead>
                <tbody>
                  {(balances.data ?? []).map((b) => (
                    <FeeRow
                      key={`${b.studio_id}-${b.currency}`}
                      balance={b}
                      openInvoices={(invoices.data ?? []).filter((i) => i.studio_id === b.studio_id && i.currency === b.currency && (i.status === "open" || i.status === "collections")).reduce((s, i) => s + i.amount, 0)}
                      onChanged={async () => { await balances.reload(); await invoices.reload(); }}
                    />
                  ))}
                </tbody>
              </table>
            </>
          ) : tab === "invoices" ? (
            <table>
              <thead><tr><th>Studio</th><th>Amount</th><th>Status</th><th>Created</th><th>Due</th><th>Paid</th><th></th></tr></thead>
              <tbody>
                {(invoices.data ?? []).map((i) => {
                  const overdue = i.status === "open" && i.due_at && new Date(i.due_at) < new Date();
                  return (
                    <tr key={i.id}>
                      <td>{studioName(i.studio_id)}</td>
                      <td className="strong">{money(i.amount, i.currency)}</td>
                      <td><Badge value={i.status === "collections" ? "failed" : overdue ? "disputed" : i.status} text={i.status === "collections" ? "Debt collection" : overdue ? "Overdue" : label(i.status)} /></td>
                      <td>{date(i.created_at)}</td>
                      <td>{date(i.due_at)}</td>
                      <td>{date(i.paid_at)}</td>
                      <td className="actions">
                        {i.hosted_invoice_url && <a href={i.hosted_invoice_url} target="_blank" rel="noreferrer">Invoice</a>}
                        {(i.status === "open" || i.status === "collections") && (
                          <ActionButton kind="secondary" confirm="Record that this invoice was paid (bank transfer etc.)?" onClick={async () => { await api.recordFeeSettlement(i.studio_id, i.amount, i.currency, "manual_payment", `Invoice ${i.id.slice(0, 8)} paid`); await invoices.reload(); await balances.reload(); }}>
                            Record payment
                          </ActionButton>
                        )}
                        {i.status === "collections" && (
                          <ActionButton kind="secondary" confirm="Reinstate the studio? Only once the debt is settled." onClick={async () => { await api.reinstateStudio(i.studio_id); await invoices.reload(); }}>Reinstate studio</ActionButton>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          ) : tab === "payouts" ? (
            <table>
              <thead><tr><th>Studio</th><th>Amount</th><th>Status</th><th>Scheduled</th><th>Paid</th><th>Bookings</th><th>Note</th></tr></thead>
              <tbody>
                {po.map((p) => (
                  <tr key={p.id}>
                    <td>{studioName(p.studio_id)}</td>
                    <td className="strong">{money(p.amount, p.currency)}</td>
                    <td><Badge value={p.status} /></td>
                    <td>{date(p.scheduled_for)}</td>
                    <td>{date(p.paid_at)}</td>
                    <td>{p.booking_ids.length}</td>
                    <td className="muted small">{p.failure_reason ?? ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : tab === "fees" ? (
            <table>
              <thead><tr><th>Date</th><th>Receipt</th><th>Studio</th><th>Charge</th><th>Service fee</th></tr></thead>
              <tbody>
                {charges.filter((t) => t.platform_fee > 0).map((t) => (
                  <tr key={t.id}>
                    <td>{date(t.created_at, true)}</td>
                    <td className="mono">{t.receipt_number}</td>
                    <td>{studioName(t.studio_id)}</td>
                    <td>{money(t.amount, t.currency)}</td>
                    <td className="strong">{money(t.platform_fee, t.currency)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <table>
              <thead><tr><th>Date</th><th>Receipt</th><th>Studio</th><th>Type</th><th>Method</th><th>Amount</th><th>Status</th><th>Details</th></tr></thead>
              <tbody>
                {(tab === "refunds" ? refunds : tab === "failures" ? failures : tx).map((t) => (
                  <tr key={t.id}>
                    <td>{date(t.created_at, true)}</td>
                    <td className="mono">{t.receipt_number}</td>
                    <td>{studioName(t.studio_id)}</td>
                    <td>{label(t.kind)}</td>
                    <td>{label(t.method)}</td>
                    <td className={t.kind === "refund" ? "refund" : "strong"}>{t.kind === "refund" ? "−" : ""}{money(t.amount, t.currency)}</td>
                    <td><Badge value={t.status} /></td>
                    <td className="muted small">{t.failure_reason ?? t.provider_reference ?? ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </PageState>
    </>
  );
}

function FeeRow({ balance, openInvoices, onChanged }: { balance: FeeBalance; openInvoices: number; onChanged: () => Promise<void> }) {
  const api = useApi();
  const [amount, setAmount] = useState("");
  const minor = Math.round(Number(amount.replace(",", ".")) * 100);
  return (
    <tr>
      <td className="strong">{balance.studio_name}</td>
      <td className={balance.balance > 0 ? "strong" : "muted"}>{money(balance.balance, balance.currency)}</td>
      <td>{date(balance.last_commission_at)}</td>
      <td>{openInvoices ? money(openInvoices, balance.currency) : "–"}</td>
      <td className="actions">
        {balance.balance > 0 && (
          <>
            <ActionButton kind="secondary" confirm="Send an invoice for the outstanding fees (due in 14 days)?" onClick={async () => { await api.sendFeeInvoice(balance.studio_id, balance.currency); await onChanged(); }}>
              Send invoice
            </ActionButton>
            <input style={{ width: 110 }} placeholder={`Amount ${balance.currency}`} value={amount} onChange={(e) => setAmount(e.target.value)} />
            <ActionButton kind="secondary" disabled={!(minor > 0)} onClick={async () => { await api.recordFeeSettlement(balance.studio_id, minor, balance.currency, "manual_payment", "Bank transfer received"); setAmount(""); await onChanged(); }}>
              Record payment
            </ActionButton>
            <ActionButton kind="danger" disabled={!(minor > 0)} confirm="Waive this amount?" onClick={async () => { await api.recordFeeSettlement(balance.studio_id, minor, balance.currency, "waiver", "Waived by admin"); setAmount(""); await onChanged(); }}>
              Waive
            </ActionButton>
          </>
        )}
      </td>
    </tr>
  );
}
