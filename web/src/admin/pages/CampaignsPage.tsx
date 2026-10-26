import { useEffect, useMemo, useState } from "react";
import { ActionButton, Badge, PageState } from "../components";
import { useApi, useLoad, useStaff } from "../lib/apiContext";
import { CAMPAIGN_TEMPLATES } from "../lib/campaignTemplates";
import { date } from "../lib/format";
import type { CampaignRecipient, EmailCampaign, NewCampaignRecipient } from "../lib/types";

const EMAIL = /^[^\s@<>,;"]+@[^\s@<>,;"]+\.[a-z]{2,}$/i;

/** "email; name; city; website; source" per line (tabs and commas work too, so a spreadsheet paste works). */
function parseRecipients(text: string): { rows: NewCampaignRecipient[]; bad: string[] } {
  const rows: NewCampaignRecipient[] = [];
  const bad: string[] = [];
  for (const line of text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean)) {
    const parts = line.split(/\t|;|,(?=(?:[^"]*"[^"]*")*[^"]*$)/).map((p) => p.trim().replace(/^"|"$/g, ""));
    const index = parts.findIndex((p) => EMAIL.test(p));
    if (index < 0) { bad.push(line); continue; }
    const rest = parts.filter((_, i) => i !== index);
    rows.push({ email: parts[index].toLowerCase(), name: rest[0] ?? "", city: rest[1] ?? "", website: rest[2] ?? "", source: rest[3] ?? "" });
  }
  return { rows, bad };
}

// {{name}}, or {{name|there}} with a fallback for when the value is empty (same as admin-campaign-send).
const fill = (template: string, r: Pick<CampaignRecipient, "name" | "city" | "website">) =>
  template.replace(/\{\{\s*(name|city|website)\s*(?:\|([^}]*))?\}\}/gi, (_, key: string, fallback?: string) =>
    r[key.toLowerCase() as "name" | "city" | "website"]?.trim() || (fallback ?? "").trim());

/**
 * Owners write campaigns (from scratch or from a template) and send them a batch at a time; any admin
 * can read them and must approve one before it can be sent. Edits clear the approval.
 */
export default function CampaignsPage() {
  const api = useApi();
  const me = useStaff();
  const owner = me.rank === "owner";
  const campaigns = useLoad(() => api.campaigns());
  const [templateMessage, setTemplateMessage] = useState<string | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  useEffect(() => {
    if (!selected && campaigns.data?.length) setSelected(campaigns.data[0].id);
  }, [campaigns.data, selected]);
  const current = campaigns.data?.find((c) => c.id === selected) ?? null;

  return (
    <>
      <header className="page-header">
        <h1>Campaigns</h1>
        {owner && <ActionButton onClick={async () => { const id = await api.saveCampaign({ name: "New campaign", from_local: "easysesh" }); await campaigns.reload(); setSelected(id); }}>New campaign</ActionButton>}
      </header>
      <p className="muted">
        One email, sent separately to each address on a list, with {"{{name}}"}, {"{{city}}"} and {"{{website}}"} filled in ({"{{name|there}}"} uses "there" when the name is empty).
        Every campaign needs an admin's approval before it can be sent, and any change to the email or the list clears that approval. Owners write and send; admins can read and approve.
      </p>

      {owner && (
        <details className="card" style={{ marginBottom: 16 }}>
          <summary className="strong" style={{ cursor: "pointer" }}>Start from a template</summary>
          <p className="muted small">Creates a draft with the matching users already on the list. Only active accounts that haven't turned off emails or asked not to be contacted are included.</p>
          <div className="card flush">
            <table>
              <thead><tr><th>Template</th><th>Who gets it</th><th></th></tr></thead>
              <tbody>
                {CAMPAIGN_TEMPLATES.map((tpl) => (
                  <tr key={tpl.id}>
                    <td className="strong">{tpl.title}<div className="muted small">{tpl.subject}</div></td>
                    <td className="small">{tpl.audience}</td>
                    <td className="actions">
                      <ActionButton kind="secondary" onClick={async () => {
                        const people = await api.campaignAudience(tpl.id);
                        const id = await api.saveCampaign({ name: `${tpl.title} – ${new Date().toLocaleDateString("en-GB")}`, from_local: tpl.from, subject: tpl.subject, body: tpl.body, footer: tpl.footer, note: `Template: ${tpl.title}. ${tpl.audience}`, template: tpl.id });
                        const added = people.length ? await api.addCampaignRecipients(id, people) : 0;
                        setTemplateMessage(`Draft created with ${added} ${added === 1 ? "person" : "people"}. Review it below.`);
                        await campaigns.reload();
                        setSelected(id);
                      }}>Create draft</ActionButton>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {templateMessage && <div className="small" style={{ marginTop: 8 }}>{templateMessage}</div>}
        </details>
      )}
      <PageState loading={campaigns.loading && !campaigns.data} error={campaigns.error} empty={(campaigns.data ?? []).length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Campaign</th><th>Status</th><th>Review</th><th>Waiting</th><th>Sent</th><th>Failed / skipped</th><th>Updated</th></tr></thead>
            <tbody>
              {(campaigns.data ?? []).map((c) => (
                <tr key={c.id} onClick={() => setSelected(c.id)} style={{ cursor: "pointer", background: c.id === selected ? "var(--accent-soft)" : undefined }}>
                  <td className="strong">{c.name}</td>
                  <td><Badge value={c.status === "done" ? "completed" : c.status === "sending" ? "pending" : "draft"} text={c.status} /></td>
                  <td>{c.reviewed_at ? <Badge value="approved" text="approved" /> : <Badge value="pending" text="needs review" />}</td>
                  <td>{c.pending_count}</td>
                  <td>{c.sent_count}</td>
                  <td>{c.failed_count} / {c.skipped_count}</td>
                  <td className="muted">{date(c.updated_at, true)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
      {current && <CampaignEditor key={current.id} campaign={current} owner={owner} onChanged={campaigns.reload} onDeleted={async () => { setSelected(null); await campaigns.reload(); }} />}
    </>
  );
}

function CampaignEditor({ campaign, owner, onChanged, onDeleted }: { campaign: EmailCampaign; owner: boolean; onChanged: () => Promise<void>; onDeleted: () => Promise<void> }) {
  const api = useApi();
  const recipients = useLoad(() => api.campaignRecipients(campaign.id), [campaign.id]);
  const [draft, setDraft] = useState(campaign);
  const [paste, setPaste] = useState("");
  const [batch, setBatch] = useState(20);
  const [message, setMessage] = useState<string | null>(null);
  const [previewId, setPreviewId] = useState<string | null>(null);
  const parsed = useMemo(() => parseRecipients(paste), [paste]);
  const dirty = (["name", "from_local", "subject", "body", "footer", "note"] as const).some((k) => draft[k] !== campaign[k]);
  const list = recipients.data ?? [];
  const pending = list.filter((r) => r.status === "pending").length;
  const sample = list.find((r) => r.id === previewId) ?? list[0] ?? { name: "Studio", city: "København", website: "" };
  const set = (patch: Partial<EmailCampaign>) => setDraft({ ...draft, ...patch });

  const reloadAll = async () => { await recipients.reload(); await onChanged(); };

  return (
    <>
      <h2 style={{ marginTop: 28 }}>{campaign.name}</h2>
      <div className="grid" style={{ gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1fr)", alignItems: "start" }}>
        <fieldset className="card form" disabled={!owner} style={{ margin: 0, minWidth: 0 }}>
          <label>Name (only the team sees it)<input value={draft.name} onChange={(e) => set({ name: e.target.value })} /></label>
          <label>From
            <div className="row gap"><input value={draft.from_local} onChange={(e) => set({ from_local: e.target.value.toLowerCase().replace(/@.*$/, "") })} style={{ maxWidth: 180 }} /><span className="muted">@easysesh.live (replies arrive there)</span></div>
          </label>
          <label>Subject<input value={draft.subject} onChange={(e) => set({ subject: e.target.value })} /></label>
          <label>Message<textarea rows={16} value={draft.body} onChange={(e) => set({ body: e.target.value })} placeholder={"Hej {{name}},\n\n…"} /></label>
          <label>Small print under the email<textarea rows={3} value={draft.footer} onChange={(e) => set({ footer: e.target.value })} placeholder="Why they got this email and how to say no thanks." /></label>
          <label>Notes (not sent)<textarea rows={4} value={draft.note} onChange={(e) => set({ note: e.target.value })} /></label>
          <div className="row gap wrap">
            <ActionButton disabled={!dirty || draft.name.trim().length < 2} onClick={async () => { await api.saveCampaign(draft); await onChanged(); setMessage("Saved."); }}>Save</ActionButton>
            {campaign.sent_count === 0 && <ActionButton kind="danger" confirm="Delete this campaign and its list?" onClick={async () => { await api.deleteCampaign(campaign.id); await onDeleted(); }}>Delete campaign</ActionButton>}
          </div>
        </fieldset>

        <div className="stack" style={{ gap: 16 }}>
          <div className="card">
            <div className="row gap wrap" style={{ justifyContent: "space-between", marginBottom: 8 }}>
              <h3 style={{ margin: 0 }}>Preview</h3>
              {list.length > 0 && (
                <select value={previewId ?? list[0].id} onChange={(e) => setPreviewId(e.target.value)} style={{ maxWidth: 260 }}>
                  {list.map((r) => <option key={r.id} value={r.id}>{r.name || r.email}</option>)}
                </select>
              )}
            </div>
            <div className="muted small">From {draft.from_local}@easysesh.live · To {"email" in sample ? sample.email : "…"}</div>
            <div className="strong" style={{ margin: "8px 0" }}>{fill(draft.subject, sample) || <span className="muted">No subject yet</span>}</div>
            <div style={{ whiteSpace: "pre-wrap", lineHeight: 1.5 }}>{fill(draft.body, sample) || <span className="muted">No message yet</span>}</div>
            {draft.footer && <div className="muted small" style={{ whiteSpace: "pre-wrap", marginTop: 12, borderTop: "1px solid var(--stroke)", paddingTop: 8 }}>{fill(draft.footer, sample)}</div>}
          </div>

          <div className="card">
            <h3 style={{ marginTop: 0 }}>Review</h3>
            {campaign.reviewed_at ? (
              <p className="small" style={{ marginTop: 0 }}><Badge value="approved" text="approved" /> by {campaign.reviewed_by_email ?? "an admin"} on {date(campaign.reviewed_at, true)}. Any change to the email or the list clears this.</p>
            ) : (
              <p className="small" style={{ marginTop: 0 }}><Badge value="pending" text="needs review" /> Read the email in the preview (try a few recipients), check the list below, then approve it. {dirty && "Save your changes first."}</p>
            )}
            <div className="row gap wrap">
              {campaign.reviewed_at
                ? <ActionButton kind="secondary" onClick={async () => { await api.reviewCampaign(campaign.id, false); await onChanged(); }}>Withdraw approval</ActionButton>
                : <ActionButton disabled={dirty || !campaign.subject.trim() || !campaign.body.trim() || list.length === 0} confirm={`Approve "${campaign.subject}" for ${list.length} ${list.length === 1 ? "person" : "people"}? You've read the email and checked the list.`}
                    onClick={async () => { await api.reviewCampaign(campaign.id, true); await onChanged(); }}>Approve for sending</ActionButton>}
            </div>
          </div>

          {owner && <div className="card notice">
            <h3 style={{ marginTop: 0 }}>Send</h3>
            <p className="small" style={{ marginTop: 0 }}>
              Save first; the server sends the saved version. Each address gets its own email. At most 80 emails a day leave the admin panel (Resend's free plan allows 100, shared with booking emails).
              Danish law (markedsføringsloven § 10) generally forbids marketing emails, also to businesses, without their consent. Check that before sending to people who haven't asked to hear from you.
            </p>
            <div className="row gap wrap">
              <ActionButton kind="secondary" disabled={dirty} onClick={async () => { const r = await api.sendCampaign(campaign.id, "test"); setMessage(`Test sent to ${r.to}.`); }}>Send a test to me</ActionButton>
              <label className="row gap small" style={{ margin: 0 }}>Next
                <input type="number" min={1} max={50} value={batch} onChange={(e) => setBatch(Math.max(1, Math.min(50, Number(e.target.value) || 1)))} style={{ width: 64 }} />
              </label>
              <ActionButton disabled={dirty || pending === 0 || !campaign.reviewed_at} confirm={`Send to the next ${Math.min(batch, pending)} of ${pending} waiting addresses now? This can't be undone.`}
                onClick={async () => { const r = await api.sendCampaign(campaign.id, "batch", batch); setMessage(`Sent ${r.sent}, failed ${r.failed ?? 0}, skipped ${r.skipped ?? 0}. ${r.left ?? 0} still waiting.`); await reloadAll(); }}>
                Send batch
              </ActionButton>
            </div>
            {!campaign.reviewed_at && <div className="small" style={{ marginTop: 8 }}>Sending unlocks once an admin has approved the campaign.</div>}
            {message && <div className="small" style={{ marginTop: 8 }}>{message}</div>}
          </div>}
        </div>
      </div>

      <h2 style={{ marginTop: 28 }}>Recipients <span className="muted small">({list.length}, {pending} waiting)</span></h2>
      {owner && <div className="card form">
        <label>Add addresses – one per line: email; name; city; website; source (a spreadsheet paste works)
          <textarea rows={5} value={paste} onChange={(e) => setPaste(e.target.value)} placeholder={"kontakt@studio.dk; Studio Nord; Aarhus; https://studionord.dk"} />
        </label>
        {paste.trim() && <div className="small muted">{parsed.rows.length} addresses found{parsed.bad.length ? `, ${parsed.bad.length} lines without an email address` : ""}.</div>}
        <div>
          <ActionButton disabled={parsed.rows.length === 0} onClick={async () => { const n = await api.addCampaignRecipients(campaign.id, parsed.rows); setPaste(""); setMessage(`${n} added (duplicates skipped).`); await reloadAll(); }}>Add to list</ActionButton>
        </div>
      </div>}
      <PageState loading={recipients.loading && !recipients.data} error={recipients.error} empty={list.length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Name</th><th>Email</th><th>City</th><th>Website</th><th>Status</th><th></th></tr></thead>
            <tbody>
              {list.map((r) => (
                <tr key={r.id}>
                  <td className="strong">{r.name}</td>
                  <td>{r.email}</td>
                  <td>{r.city}</td>
                  <td className="small">{r.website && <a href={r.website.startsWith("http") ? r.website : `https://${r.website}`} target="_blank" rel="noreferrer">{r.website.replace(/^https?:\/\/(www\.)?/, "").replace(/\/$/, "")}</a>}</td>
                  <td><Badge value={r.status === "sent" ? "completed" : r.status === "pending" ? "pending" : r.status === "failed" ? "failed" : "cancelled"} text={r.status} />{r.error && <div className="muted small">{r.error}</div>}{r.sent_at && <div className="muted small">{date(r.sent_at, true)}</div>}</td>
                  <td className="actions">
                    {owner && r.status === "pending" && <ActionButton kind="secondary" onClick={async () => { await api.removeCampaignRecipient(r.id); await reloadAll(); }}>Remove</ActionButton>}
                    {owner && r.status !== "skipped" && <ActionButton kind="danger" confirm={`Never email ${r.email} from a campaign again?`} onClick={async () => { await api.doNotContact(r.email, "Marked in the admin panel"); await reloadAll(); }}>Do not contact</ActionButton>}
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
