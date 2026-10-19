import { useMemo, useState } from "react";
import { Modal, PageState, Search } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label } from "../lib/format";
import type { AuditEntry } from "../lib/types";

/** Owners: every change made by the admin team, with who, when, why and what changed. */
export default function AuditPage() {
  const api = useApi();
  const log = useLoad(() => api.auditLog(1000));
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState<AuditEntry | null>(null);
  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (log.data ?? []).filter((e) => !q || [e.admin_email, e.action, e.target_table, e.target_id, e.reason, e.affected_user].some((v) => v?.toLowerCase().includes(q)));
  }, [log.data, query]);

  return (
    <>
      <header className="page-header"><h1>Audit log</h1></header>
      <p className="muted">Recorded automatically for every change made by an admin (and for viewing as a user, emails and refunds). Entries can't be edited or deleted.</p>
      <Search value={query} onChange={setQuery} placeholder="Search admin, action, table, reason…" />
      <PageState loading={log.loading && !log.data} error={log.error} empty={rows.length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>When</th><th>Admin</th><th>Action</th><th>Why</th><th></th></tr></thead>
            <tbody>
              {rows.map((e) => (
                <tr key={e.id}>
                  <td>{date(e.created_at, true)}</td>
                  <td>{e.admin_email ?? "–"}<div className="muted small">{e.admin_rank}</div></td>
                  <td className="strong">{label(e.action)}{e.target_table && <div className="muted small">{label(e.target_table)}{e.target_id ? ` · ${e.target_id.slice(0, 8)}` : ""}</div>}</td>
                  <td>{e.reason ?? <span className="muted">–</span>}</td>
                  <td className="actions"><button className="secondary" onClick={() => setOpen(e)}>Details</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
      {open && (
        <Modal title={`${label(open.action)} · ${date(open.created_at, true)}`} onClose={() => setOpen(null)}>
          <p><strong>{open.admin_email}</strong> ({open.admin_rank}){open.affected_user && <> · affected user <span className="mono">{open.affected_user}</span></>}</p>
          {open.reason && <p>Why: {open.reason}</p>}
          <pre className="mono small" style={{ whiteSpace: "pre-wrap", wordBreak: "break-word" }}>{JSON.stringify(open.details, null, 2)}</pre>
        </Modal>
      )}
    </>
  );
}
