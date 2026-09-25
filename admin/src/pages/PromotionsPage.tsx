import { useState } from "react";
import { ActionButton, Badge, PageState, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label, money } from "../lib/format";
import type { Promotion } from "../lib/types";

type Tab = "pending" | "active" | "all";

/** Studios' promotion orders. Without Stripe they arrive as "pending": invoice the studio,
 *  then activate the promotion here once it's paid. */
export default function PromotionsPage() {
  const api = useApi();
  const { data, loading, error, reload } = useLoad(() => api.promotions());
  const [tab, setTab] = useState<Tab>("pending");
  const all = data ?? [];
  const filters: Record<Tab, (p: Promotion) => boolean> = {
    pending: (p) => p.status === "pending",
    active: (p) => p.status === "active",
    all: () => true,
  };
  const rows = all.filter(filters[tab]);

  return (
    <>
      <header className="page-header"><h1>Promotions</h1></header>
      <p className="muted">Studios buy a period at the top of search with a "Promoted" tag. Paid in the app when Stripe is set up; otherwise send an invoice and activate the order when it's paid.</p>
      <Tabs<Tab>
        value={tab}
        onChange={setTab}
        tabs={[
          { id: "pending", title: "Waiting for payment", count: all.filter(filters.pending).length },
          { id: "active", title: "Active", count: all.filter(filters.active).length },
          { id: "all", title: "All" },
        ]}
      />
      <PageState loading={loading && !data} error={error} empty={rows.length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Studio</th><th>Package</th><th>Price</th><th>Status</th><th>Period</th><th>Ordered</th><th></th></tr></thead>
            <tbody>
              {rows.map((p) => (
                <tr key={p.id}>
                  <td className="strong">{p.studio_name}<div className="muted small">{p.source === "admin" ? "Given by admin" : "Purchase"}</div></td>
                  <td>{label(p.package)} · {p.days} days</td>
                  <td>{p.amount ? money(p.amount, p.currency) : "Free"}</td>
                  <td><Badge value={p.status} /></td>
                  <td>{p.starts_at ? `${date(p.starts_at)} – ${date(p.ends_at)}` : "–"}</td>
                  <td>{date(p.created_at, true)}</td>
                  <td className="actions">
                    {p.status === "pending" && (
                      <>
                        <ActionButton confirm="Mark as paid and start the promotion now?" onClick={async () => { await api.activatePromotion(p.id); await reload(); }}>Paid – activate</ActionButton>
                        <ActionButton kind="secondary" confirm="Cancel this order?" onClick={async () => { await api.cancelPromotion(p.id); await reload(); }}>Cancel</ActionButton>
                      </>
                    )}
                    {p.status === "active" && (
                      <ActionButton kind="danger" confirm="End this studio's promotion now?" onClick={async () => { await api.endPromotion(p.studio_id); await reload(); }}>End now</ActionButton>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
    </>
  );
}
