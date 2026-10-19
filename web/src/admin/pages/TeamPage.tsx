import { useState } from "react";
import { ActionButton, Badge, PageState } from "../components";
import { useApi, useLoad, useStaff } from "../lib/apiContext";
import { date } from "../lib/format";
import type { StaffRank } from "../lib/types";

const RANKS: { id: StaffRank; text: string }[] = [
  { id: "owner", text: "Owner – everything, incl. the team and the audit log" },
  { id: "admin", text: "Admin – everything except the team and the audit log" },
  { id: "support", text: "Support – can see everything, but only answer support requests" },
];

/** Owners manage who is on the admin team. */
export default function TeamPage() {
  const api = useApi();
  const me = useStaff();
  const team = useLoad(() => api.team());
  const [email, setEmail] = useState("");
  const [rank, setRank] = useState<StaffRank>("support");

  return (
    <>
      <header className="page-header"><h1>Team</h1></header>
      <p className="muted">Admins sign in on this panel with their EasySesh account and two-factor authentication. Studio owner accounts can't be admins – use a separate account.</p>
      <div className="card form">
        <h2>Add someone</h2>
        <div className="row gap wrap">
          <label>Their EasySesh account email<input type="email" placeholder="name@easysesh.live" value={email} onChange={(e) => setEmail(e.target.value)} /></label>
          <label>Rank
            <select value={rank} onChange={(e) => setRank(e.target.value as StaffRank)}>
              {RANKS.map((r) => <option key={r.id} value={r.id}>{r.id}</option>)}
            </select>
          </label>
        </div>
        <ul className="muted small">{RANKS.map((r) => <li key={r.id}>{r.text}</li>)}</ul>
        <div>
          <ActionButton disabled={!email.includes("@")} confirm={`Give ${email} the ${rank} rank?`} onClick={async () => { await api.setRank(email.trim(), rank); setEmail(""); await team.reload(); }}>Add to team</ActionButton>
        </div>
      </div>
      <PageState loading={team.loading && !team.data} error={team.error} empty={(team.data ?? []).length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Email</th><th>Rank</th><th>Since</th><th></th></tr></thead>
            <tbody>
              {(team.data ?? []).map((m) => (
                <tr key={m.id}>
                  <td className="strong">{m.email}{m.email === me.email && <span className="muted small"> (you)</span>}</td>
                  <td><Badge value={m.admin_rank === "owner" ? "approved" : m.admin_rank === "admin" ? "pending" : "draft"} text={m.admin_rank} /></td>
                  <td>{date(m.created_at)}</td>
                  <td className="actions">
                    {RANKS.filter((r) => r.id !== m.admin_rank).map((r) => (
                      <ActionButton key={r.id} kind="secondary" confirm={`Make ${m.email} ${r.id}?`} onClick={async () => { await api.setRank(m.email, r.id); await team.reload(); }}>Make {r.id}</ActionButton>
                    ))}
                    {m.email !== me.email && (
                      <ActionButton kind="danger" confirm={`Remove ${m.email} from the team? Their account becomes a normal artist account.`} onClick={async () => { await api.setRank(m.email, null); await team.reload(); }}>Remove</ActionButton>
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
