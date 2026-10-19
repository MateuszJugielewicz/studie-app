import { useState } from "react";
import { ActionButton, Badge, PageState, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date } from "../lib/format";
import type { PromoCode } from "../lib/types";

type Tab = "easysesh" | "studios" | "offers";

/** EasySesh promo codes (valid at every studio, EasySesh pays the discount), plus an overview of
 *  the studios' own codes and offers, which admins can switch off. */
export default function PromoCodesPage() {
  const api = useApi();
  const codes = useLoad(() => api.promoCodes());
  const offers = useLoad(() => api.studioOffers());
  const [tab, setTab] = useState<Tab>("easysesh");
  const [code, setCode] = useState("");
  const [percent, setPercent] = useState(10);
  const [description, setDescription] = useState("");
  const [maxUses, setMaxUses] = useState("");
  const [perUser, setPerUser] = useState(1);
  const [ends, setEnds] = useState("");

  const all = codes.data ?? [];
  const rows = all.filter((c) => (tab === "easysesh" ? c.studio_id === null : c.studio_id !== null));
  const validCode = /^[A-Z0-9]{3,20}$/.test(code);

  const create = async () => {
    await api.savePromoCode({
      code, studio_id: null, percent_off: percent, description: description.trim(),
      max_uses: maxUses ? Number(maxUses) : null, max_uses_per_user: perUser,
      ends_at: ends ? new Date(`${ends}T23:59:59`).toISOString() : null, is_active: true,
    });
    setCode(""); setDescription(""); setMaxUses(""); setEnds("");
    await codes.reload();
  };

  const status = (c: { is_active: boolean; ends_at: string | null }) =>
    !c.is_active ? <Badge value="cancelled" text="Off" /> : c.ends_at && new Date(c.ends_at) <= new Date() ? <Badge value="expired" text="Ended" /> : <Badge value="active" text="Active" />;

  return (
    <>
      <header className="page-header"><h1>Promo codes</h1></header>
      <p className="muted">
        Artists type a code at checkout to get a percentage off. <strong>EasySesh codes</strong> work at every studio and are paid by
        EasySesh: the studio is paid as if there were no code (card payouts come from the EasySesh Stripe balance; for cash bookings the
        discount is taken off the studio's fee, or credited to it). Studios make their own codes and offers, which come off their price.
      </p>

      <div className="card form">
        <h2>New EasySesh code</h2>
        <div className="row gap wrap">
          <label>Code<input className="mono" placeholder="WELCOME10" value={code} maxLength={20}
            onChange={(e) => setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ""))} /></label>
          <label>Discount (%)<input type="number" min={1} max={50} value={percent} onChange={(e) => setPercent(Math.min(50, Math.max(1, Number(e.target.value) || 1)))} /></label>
          <label>Uses in total<input type="number" min={1} placeholder="No limit" value={maxUses} onChange={(e) => setMaxUses(e.target.value.replace(/\D/g, ""))} /></label>
          <label>Uses per artist<input type="number" min={1} max={100} value={perUser} onChange={(e) => setPerUser(Math.min(100, Math.max(1, Number(e.target.value) || 1)))} /></label>
          <label>Last day<input type="date" value={ends} onChange={(e) => setEnds(e.target.value)} /></label>
        </div>
        <label>Note for artists (optional)<input placeholder="e.g. 10% off your first session" value={description} onChange={(e) => setDescription(e.target.value)} /></label>
        <div>
          <ActionButton disabled={!validCode} confirm={`Create ${code} for ${percent}% off at every studio, paid by EasySesh?`} onClick={create}>Create code</ActionButton>
        </div>
      </div>

      <Tabs<Tab>
        value={tab}
        onChange={setTab}
        tabs={[
          { id: "easysesh", title: "EasySesh codes", count: all.filter((c) => c.studio_id === null).length },
          { id: "studios", title: "Studio codes", count: all.filter((c) => c.studio_id !== null).length },
          { id: "offers", title: "Studio offers", count: (offers.data ?? []).length },
        ]}
      />

      {tab !== "offers" ? (
        <PageState loading={codes.loading && !codes.data} error={codes.error} empty={rows.length === 0}>
          <div className="card flush">
            <table>
              <thead><tr><th>Code</th><th>Discount</th>{tab === "studios" && <th>Studio</th>}<th>Used</th><th>Ends</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {rows.map((c: PromoCode) => (
                  <tr key={c.id}>
                    <td><span className="strong mono">{c.code}</span>{c.description && <div className="muted small">{c.description}</div>}</td>
                    <td>{c.percent_off}%</td>
                    {tab === "studios" && <td>{c.studio_name ?? "–"}</td>}
                    <td>{c.uses ?? 0}{c.max_uses ? ` / ${c.max_uses}` : ""}<div className="muted small">{c.max_uses_per_user}× per artist</div></td>
                    <td>{c.ends_at ? date(c.ends_at) : "–"}</td>
                    <td>{status(c)}</td>
                    <td className="actions">
                      <ActionButton kind="secondary" onClick={async () => { await api.savePromoCode({ id: c.id, is_active: !c.is_active }); await codes.reload(); }}>
                        {c.is_active ? "Turn off" : "Turn on"}
                      </ActionButton>
                      <ActionButton kind="danger" confirm={`Delete ${c.code}? Bookings that used it keep their discount.`} onClick={async () => { await api.removePromoCode(c.id); await codes.reload(); }}>Delete</ActionButton>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </PageState>
      ) : (
        <PageState loading={offers.loading && !offers.data} error={offers.error} empty={(offers.data ?? []).length === 0}>
          <div className="card flush">
            <table>
              <thead><tr><th>Studio</th><th>Offer</th><th>Discount</th><th>Ends</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {(offers.data ?? []).map((o) => (
                  <tr key={o.id}>
                    <td className="strong">{o.studio_name}</td>
                    <td>{o.title}<div className="muted small">{o.applies_to.replace("_", " ")}{o.target_id ? ` · ${o.target_id}` : ""}</div></td>
                    <td>{o.percent_off}%</td>
                    <td>{o.ends_at ? date(o.ends_at) : "–"}</td>
                    <td>{status(o)}</td>
                    <td className="actions">
                      <ActionButton kind="secondary" onClick={async () => { await api.setOfferActive(o.id, !o.is_active); await offers.reload(); }}>{o.is_active ? "Turn off" : "Turn on"}</ActionButton>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </PageState>
      )}
    </>
  );
}
