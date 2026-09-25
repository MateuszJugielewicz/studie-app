import { useState } from "react";
import { ActionButton, Badge, PageState, Stat } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label } from "../lib/format";
import type { ChangelogEntry } from "../lib/types";

/** Update notes shown in the app ("What's new"). A legal update makes every user read and
 *  accept the terms again before they can continue. */
export default function ChangelogPage() {
  const api = useApi();
  const entries = useLoad(() => api.changelog());
  const terms = useLoad(() => api.termsStatus());
  const [version, setVersion] = useState("");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [audience, setAudience] = useState<ChangelogEntry["audience"]>("all");
  const [legal, setLegal] = useState(false);

  const publish = async () => {
    await api.publishChangelog({ version: version.trim(), title: title.trim(), body: body.trim(), audience, legalUpdate: legal });
    setVersion(""); setTitle(""); setBody(""); setLegal(false);
    await entries.reload();
    await terms.reload();
  };

  return (
    <>
      <header className="page-header"><h1>Changelog</h1></header>
      <div className="grid stats">
        <Stat title="Current terms version" value={terms.data?.version ?? "…"} />
        <Stat title="Accepted current terms" value={terms.data ? `${terms.data.accepted} / ${terms.data.total}` : "…"} hint="Users (not admins)" />
      </div>

      <div className="card form">
        <h2>Publish an update</h2>
        <div className="row gap wrap">
          <label>Version<input placeholder="e.g. 1.4" value={version} onChange={(e) => setVersion(e.target.value)} /></label>
          <label>Shown to
            <select value={audience} onChange={(e) => setAudience(e.target.value as ChangelogEntry["audience"])}>
              <option value="all">Everyone</option>
              <option value="artist">Artists</option>
              <option value="studio_owner">Studios</option>
            </select>
          </label>
        </div>
        <label>Title<input placeholder="e.g. Check in when you arrive" value={title} onChange={(e) => setTitle(e.target.value)} /></label>
        <label>What's new<textarea rows={5} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Describe the changes in plain words." /></label>
        <label className="row gap">
          <input type="checkbox" checked={legal} onChange={(e) => setLegal(e.target.checked)} />
          <span><strong>Legal update</strong> – terms, privacy policy or agreements changed. Everyone must read the documents and accept them again.</span>
        </label>
        {legal && <div className="card notice small">Remember to update the documents in the <span className="mono">legal/</span> folder (all languages) and ship the app first, so users read the new text.</div>}
        <div>
          <ActionButton disabled={!title.trim()} confirm={legal ? "Publish and ask every user to accept the terms again?" : undefined} onClick={publish}>
            Publish
          </ActionButton>
        </div>
      </div>

      <PageState loading={entries.loading && !entries.data} error={entries.error} empty={(entries.data ?? []).length === 0}>
        <div className="stack">
          {(entries.data ?? []).map((e) => (
            <div key={e.id} className="card">
              <div className="row between">
                <div className="row gap">
                  <strong>{e.version}</strong>
                  {e.is_legal_update && <Badge value="pending" text="Legal update" />}
                  <span className="muted small">{label(e.audience === "studio_owner" ? "studios" : e.audience === "artist" ? "artists" : "everyone")} · {date(e.published_at, true)}</span>
                </div>
                <ActionButton kind="secondary" confirm="Delete this entry? (A legal update stays in force.)" onClick={async () => { await api.deleteChangelog(e.id); await entries.reload(); }}>Delete</ActionButton>
              </div>
              <p className="strong">{e.title}</p>
              {e.body && <p style={{ whiteSpace: "pre-wrap" }}>{e.body}</p>}
            </div>
          ))}
        </div>
      </PageState>
    </>
  );
}
