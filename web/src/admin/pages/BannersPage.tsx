import { useState } from "react";
import { ActionButton, Badge, PageState } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label } from "../lib/format";
import type { SiteBanner } from "../lib/types";

const KINDS: SiteBanner["kind"][] = ["info", "warning", "outage", "success"];
const AUDIENCES: SiteBanner["audience"][] = ["everyone", "guests", "artist", "studio_owner"];

/** Banners at the top of the website and the apps: outages, maintenance, announcements. */
export default function BannersPage() {
  const api = useApi();
  const banners = useLoad(() => api.banners());
  const [kind, setKind] = useState<SiteBanner["kind"]>("info");
  const [audience, setAudience] = useState<SiteBanner["audience"]>("everyone");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [link, setLink] = useState("");
  const [linkLabel, setLinkLabel] = useState("");
  const [ends, setEnds] = useState("");
  const [dismissible, setDismissible] = useState(true);
  const linkValid = !link || /^https:\/\//.test(link);

  const create = async () => {
    await api.saveBanner({
      kind, audience, title: title.trim(), body: body.trim(), link_url: link.trim() || null, link_label: linkLabel.trim() || null,
      ends_at: ends ? new Date(ends).toISOString() : null, dismissible, is_active: true,
    });
    setTitle(""); setBody(""); setLink(""); setLinkLabel(""); setEnds("");
    await banners.reload();
  };
  const live = (b: SiteBanner) => b.is_active && new Date(b.starts_at) <= new Date() && (!b.ends_at || new Date(b.ends_at) > new Date());

  return (
    <>
      <header className="page-header"><h1>Banners</h1></header>
      <p className="muted">Shown at the top of the website and the apps right away. Use “outage” for problems (red, can't be closed if you untick “can be closed”).</p>
      <div className="card form">
        <h2>New banner</h2>
        <div className="row gap wrap">
          <label>Type<select value={kind} onChange={(e) => setKind(e.target.value as SiteBanner["kind"])}>{KINDS.map((k) => <option key={k} value={k}>{label(k)}</option>)}</select></label>
          <label>Shown to<select value={audience} onChange={(e) => setAudience(e.target.value as SiteBanner["audience"])}>{AUDIENCES.map((a) => <option key={a} value={a}>{a === "studio_owner" ? "Studios" : a === "artist" ? "Artists" : label(a)}</option>)}</select></label>
          <label>Ends (optional)<input type="datetime-local" value={ends} onChange={(e) => setEnds(e.target.value)} /></label>
          <label className="row gap"><input type="checkbox" checked={dismissible} onChange={(e) => setDismissible(e.target.checked)} /> Can be closed</label>
        </div>
        <label>Title<input maxLength={120} placeholder="e.g. Card payments are down" value={title} onChange={(e) => setTitle(e.target.value)} /></label>
        <label>Text (optional)<textarea rows={3} maxLength={600} placeholder="e.g. We're working on it. You can still book and pay cash." value={body} onChange={(e) => setBody(e.target.value)} /></label>
        <div className="row gap wrap">
          <label style={{ flex: 1 }}>Link (optional, https://)<input value={link} onChange={(e) => setLink(e.target.value)} /></label>
          <label>Link text<input value={linkLabel} placeholder="Read more" onChange={(e) => setLinkLabel(e.target.value)} /></label>
        </div>
        <div><ActionButton disabled={title.trim().length < 2 || !linkValid} onClick={create}>Publish banner</ActionButton></div>
      </div>
      <PageState loading={banners.loading && !banners.data} error={banners.error} empty={(banners.data ?? []).length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Banner</th><th>Type</th><th>Shown to</th><th>Ends</th><th>Status</th><th></th></tr></thead>
            <tbody>
              {(banners.data ?? []).map((b) => (
                <tr key={b.id}>
                  <td className="strong">{b.title}{b.body && <div className="muted small">{b.body}</div>}</td>
                  <td>{label(b.kind)}</td>
                  <td>{b.audience === "studio_owner" ? "Studios" : label(b.audience)}</td>
                  <td>{b.ends_at ? date(b.ends_at, true) : "–"}</td>
                  <td>{live(b) ? <Badge value="active" text="Live" /> : <Badge value="expired" text={b.is_active ? "Ended" : "Off"} />}</td>
                  <td className="actions">
                    <ActionButton kind="secondary" onClick={async () => { await api.saveBanner({ id: b.id, is_active: !b.is_active }); await banners.reload(); }}>{b.is_active ? "Turn off" : "Turn on"}</ActionButton>
                    <ActionButton kind="danger" confirm="Delete this banner?" onClick={async () => { await api.removeBanner(b.id); await banners.reload(); }}>Delete</ActionButton>
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
