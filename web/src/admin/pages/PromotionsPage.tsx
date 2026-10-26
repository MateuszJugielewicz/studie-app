import { useMemo, useState } from "react";
import { ActionButton, Badge, PageState, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label, money } from "../lib/format";
import type { AdminUser, Promotion } from "../lib/types";

type Tab = "pending" | "active" | "all" | "credits";

/** Studios' and artists' promotion orders. They're paid on the website (Stripe) and start by themselves;
 *  an order paid some other way can be activated here. */
export default function PromotionsPage() {
  const api = useApi();
  const { data, loading, error, reload } = useLoad(() => api.promotions());
  const [tab, setTab] = useState<Tab>("pending");
  const all = data ?? [];
  const filters: Record<Exclude<Tab, "credits">, (p: Promotion) => boolean> = {
    pending: (p) => p.status === "pending",
    active: (p) => p.status === "active",
    all: () => true,
  };
  const rows = tab === "credits" ? [] : all.filter(filters[tab]);

  return (
    <>
      <header className="page-header"><h1>Promotions</h1></header>
      <p className="muted">Studios buy a period at the top of search, and artists a place first in the studios' artist search, both with a "Promoted" tag. They pay on the website and the promotion starts by itself; an order paid some other way can be activated here.</p>
      <Tabs<Tab>
        value={tab}
        onChange={setTab}
        tabs={[
          { id: "pending", title: "Waiting for payment", count: all.filter(filters.pending).length },
          { id: "active", title: "Active", count: all.filter(filters.active).length },
          { id: "all", title: "All" },
          { id: "credits", title: "Credits" },
        ]}
      />
      {tab === "credits" ? <CreditsPanel /> : <PageState loading={loading && !data} error={error} empty={rows.length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Studio / artist</th><th>Package</th><th>Price</th><th>Status</th><th>Period</th><th>Ordered</th><th></th></tr></thead>
            <tbody>
              {rows.map((p) => (
                <tr key={p.id}>
                  <td className="strong">{p.studio_name}<div className="muted small">{p.source === "admin" ? "Given by admin" : "Purchase"}</div></td>
                  <td>{label(p.package)} · {p.days} days</td>
                  <td>{p.credits_used ? `${p.credits_used} credits` : p.amount ? money(p.amount, p.currency) : "Free"}</td>
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
                      <ActionButton kind="danger" confirm="End this promotion now?" onClick={async () => {
                        if (p.artist_id) await api.endArtistPromotion(p.artist_id); else if (p.studio_id) await api.endPromotion(p.studio_id);
                        await reload();
                      }}>End now</ActionButton>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>}
    </>
  );
}

/** Its own page in the menu, so it's easy to find. */
export function CreditsPage() {
  return (
    <>
      <header className="page-header"><h1>Credits</h1></header>
      <CreditsPanel />
    </>
  );
}

/** One person's credits, in their user details: balance plus add / remove. */
export function UserCredits({ userId }: { userId: string }) {
  const api = useApi();
  const balance = useLoad(() => api.creditBalance(userId), [userId]);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const credits = Number(amount);
  const validAmount = Number.isInteger(credits) && credits > 0 && credits <= 10000;
  async function adjust(sign: 1 | -1) {
    await api.adjustCredits(userId, sign * credits, note.trim());
    setAmount("");
    setNote("");
    await balance.reload();
  }
  return (
    <div className="card">
      <div className="row gap wrap">
        <strong>Promotion credits:</strong>
        <span>{balance.data ?? "…"} credits (€{balance.data ?? 0})</span>
        <span className="muted small">1 credit = €1 · 1 week = 19, 2 weeks = 35, 1 month = 59</span>
      </div>
      <div className="row gap wrap">
        <input inputMode="numeric" placeholder="Credits" style={{ width: 110 }} value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, ""))} />
        <input placeholder="Note (optional)" style={{ width: 220 }} value={note} onChange={(e) => setNote(e.target.value)} />
        <ActionButton disabled={!validAmount} onClick={() => adjust(1)}>{validAmount ? `Add ${credits} credits` : "Add credits"}</ActionButton>
        <ActionButton kind="danger" disabled={!validAmount} confirm="Remove these credits?" onClick={() => adjust(-1)}>Remove</ActionButton>
      </div>
    </div>
  );
}

/** Promotion credits: 1 credit = €1. Give credits to a studio owner or artist (they're notified), or remove them. */
function CreditsPanel() {
  const api = useApi();
  const balances = useLoad(() => api.creditBalances());
  const users = useLoad(() => api.users());
  const [query, setQuery] = useState("");
  const [picked, setPicked] = useState<AdminUser | null>(null);
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("");
  const [done, setDone] = useState<string | null>(null);

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (q.length < 2 || picked) return [];
    return (users.data ?? [])
      .filter((u) => u.role === "artist" || u.role === "studio_owner")
      .filter((u) => [u.email, u.artist_name, u.studio_name].some((v) => v?.toLowerCase().includes(q)))
      .slice(0, 8);
  }, [query, picked, users.data]);
  const credits = Number(amount);
  const validAmount = Number.isInteger(credits) && credits !== 0 && Math.abs(credits) <= 10000;
  const who = (u: AdminUser) => u.studio_name ?? (u.artist_name || u.email);

  async function adjust(sign: 1 | -1) {
    if (!picked) return;
    const balance = await api.adjustCredits(picked.id, sign * Math.abs(credits), note.trim());
    setDone(`${sign > 0 ? "Added" : "Removed"} ${Math.abs(credits)} credits ${sign > 0 ? "to" : "from"} ${who(picked)}. New balance: ${balance} credits.`);
    setAmount("");
    setNote("");
    await balances.reload();
  }

  return (
    <>
      <div className="card">
        <h2>Give promotion credits</h2>
        <p className="muted">1 credit = €1. Studios and artists use credits to pay for promotions (1 week = 19, 2 weeks = 35, 1 month = 59 credits) and can also buy them on the website. They get a notification when you add credits.</p>
        <div className="grid" style={{ gap: 10, maxWidth: 520 }}>
          {picked ? (
            <div className="row gap">
              <span className="strong">{who(picked)}</span>
              <span className="muted small">{picked.email} · {picked.role === "studio_owner" ? "Studio owner" : "Artist"}</span>
              <button className="ghost" onClick={() => { setPicked(null); setQuery(""); }}>Change</button>
            </div>
          ) : (
            <>
              <input placeholder="Search studio owner or artist by email or name" value={query} onChange={(e) => { setQuery(e.target.value); setDone(null); }} />
              {matches.map((u) => (
                <button key={u.id} className="secondary" style={{ textAlign: "left" }} onClick={() => setPicked(u)}>
                  {who(u)} <span className="muted small">· {u.email} · {u.role === "studio_owner" ? "Studio owner" : "Artist"}</span>
                </button>
              ))}
              {query.trim().length >= 2 && matches.length === 0 && !users.loading && <span className="muted small">No studio owner or artist found.</span>}
            </>
          )}
          <input inputMode="numeric" placeholder="Credits (1 credit = €1)" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9]/g, ""))} />
          <input placeholder="Note (optional, e.g. Early studio bonus)" value={note} onChange={(e) => setNote(e.target.value)} />
          <div className="row gap">
            <ActionButton disabled={!picked || !validAmount} onClick={() => adjust(1)}>{validAmount ? `Add ${credits} credits (€${credits})` : "Add credits"}</ActionButton>
            <ActionButton kind="danger" disabled={!picked || !validAmount} confirm="Remove these credits?" onClick={() => adjust(-1)}>Remove</ActionButton>
          </div>
          {done && <span className="small">{done}</span>}
        </div>
      </div>
      <PageState loading={balances.loading && !balances.data} error={balances.error} empty={(balances.data ?? []).length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Studio / artist</th><th>Balance</th><th>Given</th><th>Bought</th><th>Spent</th><th>Last activity</th></tr></thead>
            <tbody>
              {(balances.data ?? []).map((b) => (
                <tr key={b.user_id}>
                  <td className="strong">{b.name}<div className="muted small">{b.email} · {b.role === "studio_owner" ? "Studio owner" : "Artist"}</div></td>
                  <td className="strong">{b.balance} <span className="muted small">(€{b.balance})</span></td>
                  <td>{b.granted ?? 0}</td>
                  <td>{b.bought ?? 0}</td>
                  <td>{b.spent ?? 0}</td>
                  <td>{date(b.last_activity, true)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
    </>
  );
}
