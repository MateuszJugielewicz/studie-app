import { useState } from "react";
import { ActionButton, Badge, PageState } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { label } from "../lib/format";
import type { FlagRule } from "../lib/types";

const CATEGORIES: FlagRule["category"][] = ["minors", "off_platform_payment", "illegal", "contact_details", "other"];

/** Messages, bios, studio texts and reviews matching these patterns are reported automatically (Moderation → Reports). */
export default function FlagRulesPage() {
  const api = useApi();
  const rules = useLoad(() => api.flagRules());
  const [category, setCategory] = useState<FlagRule["category"]>("other");
  const [pattern, setPattern] = useState("");
  const [note, setNote] = useState("");
  const [test, setTest] = useState("");
  let valid = true;
  try { new RegExp(pattern, "i"); } catch { valid = false; }
  const jsPattern = (p: string) => p.replace(/\\m|\\M/g, "\\b");
  const matches = (p: string) => { try { return test && new RegExp(jsPattern(p), "i").exec(test)?.[0]; } catch { return null; } };

  return (
    <>
      <header className="page-header"><h1>Auto-flags</h1></header>
      <p className="muted">
        New or changed messages, bios, studio texts and reviews are checked against these patterns. A match creates a report in
        Moderation (reported by “automatic”) for someone to look at – nothing is hidden or blocked. Phone numbers, emails and chat
        apps are only checked in messages. Patterns are case-insensitive regular expressions; <span className="mono">\m</span> and <span className="mono">\M</span> mark word starts and ends.
      </p>
      <div className="card form">
        <h2>Try a text</h2>
        <textarea rows={2} value={test} placeholder="Paste a message to see which rules match" onChange={(e) => setTest(e.target.value)} />
      </div>
      <div className="card form">
        <h2>New rule</h2>
        <div className="row gap wrap">
          <label>Category<select value={category} onChange={(e) => setCategory(e.target.value as FlagRule["category"])}>{CATEGORIES.map((c) => <option key={c} value={c}>{label(c)}</option>)}</select></label>
          <label style={{ flex: 1, minWidth: 260 }}>Pattern<input className="mono" placeholder="\m(word|other word)\M" value={pattern} onChange={(e) => setPattern(e.target.value)} /></label>
          <label>Note<input value={note} placeholder="What it catches" onChange={(e) => setNote(e.target.value)} /></label>
        </div>
        {!valid && <div className="card notice small">That pattern isn't valid.</div>}
        <div><ActionButton disabled={pattern.length < 2 || !valid} onClick={async () => { await api.saveFlagRule({ category, pattern, note, is_active: true }); setPattern(""); setNote(""); await rules.reload(); }}>Add rule</ActionButton></div>
      </div>
      <PageState loading={rules.loading && !rules.data} error={rules.error} empty={(rules.data ?? []).length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Category</th><th>Pattern</th><th>Note</th>{test && <th>Test</th>}<th>Status</th><th></th></tr></thead>
            <tbody>
              {(rules.data ?? []).map((r) => (
                <tr key={r.id}>
                  <td className="strong">{label(r.category)}</td>
                  <td className="mono small" style={{ wordBreak: "break-all" }}>{r.pattern}</td>
                  <td>{r.note}</td>
                  {test && <td>{matches(r.pattern) ? <Badge value="open" text={`matches “${matches(r.pattern)}”`} /> : <span className="muted">–</span>}</td>}
                  <td>{r.is_active ? <Badge value="active" text="On" /> : <Badge value="expired" text="Off" />}</td>
                  <td className="actions">
                    <ActionButton kind="secondary" onClick={async () => { await api.saveFlagRule({ id: r.id, is_active: !r.is_active }); await rules.reload(); }}>{r.is_active ? "Turn off" : "Turn on"}</ActionButton>
                    <ActionButton kind="danger" confirm="Delete this rule?" onClick={async () => { await api.removeFlagRule(r.id); await rules.reload(); }}>Delete</ActionButton>
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
