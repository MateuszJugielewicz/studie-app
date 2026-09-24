import { useState } from "react";
import { ActionButton, Badge, PageState, Search, Tabs } from "../components";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label } from "../lib/format";
import type { AccountStatus, AdminUser } from "../lib/types";

type Tab = "artist" | "studio_owner" | "suspended" | "admin";

export default function UsersPage() {
  const api = useApi();
  const { data, loading, error, reload } = useLoad(() => api.users());
  const [tab, setTab] = useState<Tab>("artist");
  const [query, setQuery] = useState("");
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [resetResult, setResetResult] = useState<{ email: string; password?: string } | null>(null);
  const [copied, setCopied] = useState(false);

  const resetPassword = (user: AdminUser, mode: "email" | "temporary") => async () => {
    setCopied(false);
    setResetResult(await api.resetPassword(user.id, mode));
  };

  const users = data ?? [];
  const q = query.toLowerCase();
  const rows = users
    .filter((u) => (tab === "suspended" ? u.status !== "active" : u.role === tab))
    .filter((u) => !q || `${u.email} ${u.artist_name ?? ""} ${u.studio_name ?? ""} ${u.artist_city ?? ""}`.toLowerCase().includes(q));

  const setStatus = (user: AdminUser, status: AccountStatus) => async () => {
    const reason = status === "active" ? undefined : (reasons[user.id]?.trim() || (status === "banned" ? "Banned by admin" : "Suspended by admin"));
    await api.setUserStatus(user.id, status, reason);
    await reload();
  };

  return (
    <>
      <header className="page-header">
        <h1>Users</h1>
        <Search value={query} onChange={setQuery} placeholder="Search email, name, city…" />
      </header>
      <Tabs<Tab>
        value={tab}
        onChange={setTab}
        tabs={[
          { id: "artist", title: "Artists", count: users.filter((u) => u.role === "artist").length },
          { id: "studio_owner", title: "Studios", count: users.filter((u) => u.role === "studio_owner").length },
          { id: "suspended", title: "Suspended / banned", count: users.filter((u) => u.status !== "active").length },
          { id: "admin", title: "Admins" },
        ]}
      />
      {resetResult && (
        <div className="card notice">
          <div className="row between">
            {resetResult.password ? (
              <div>
                <strong>Temporary password for {resetResult.email}</strong>
                <div className="row gap wrap">
                  <span className="mono big-mono">{resetResult.password}</span>
                  <button className="secondary" onClick={async () => { await navigator.clipboard.writeText(resetResult.password!); setCopied(true); }}>
                    {copied ? "Copied" : "Copy"}
                  </button>
                </div>
                <div className="muted small">Shown only once. Give it to the user privately; they should change it in Settings → Change password. They also got a notification.</div>
              </div>
            ) : (
              <div><strong>Reset email sent to {resetResult.email}.</strong><div className="muted small">The link lets them choose a new password in the app.</div></div>
            )}
            <button className="ghost" onClick={() => setResetResult(null)}>Close</button>
          </div>
        </div>
      )}
      <PageState loading={loading && !data} error={error} empty={rows.length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th>Verified</th><th>Bookings</th><th>Joined</th><th></th></tr></thead>
            <tbody>
              {rows.map((u) => (
                <tr key={u.id}>
                  <td className="strong">{u.artist_name || u.studio_name || "–"}<div className="muted small">{u.artist_city}</div></td>
                  <td>{u.email}</td>
                  <td>{label(u.role)}</td>
                  <td><Badge value={u.status} />{u.status_reason && <div className="muted small">{u.status_reason}</div>}</td>
                  <td>{u.is_verified ? "Yes" : <span className="muted">No</span>}</td>
                  <td>{u.booking_count}</td>
                  <td>{date(u.created_at)}</td>
                  <td className="actions">
                    {u.role !== "admin" && (
                      <>
                        <ActionButton kind="secondary" onClick={async () => { await api.verifyUser(u.id, !u.is_verified); await reload(); }}>
                          {u.is_verified ? "Unverify" : "Verify"}
                        </ActionButton>
                        <ActionButton kind="secondary" confirm={`Send a password reset email to ${u.email}?`} onClick={resetPassword(u, "email")}>
                          Reset password
                        </ActionButton>
                        <ActionButton kind="secondary" confirm={`Set a temporary password for ${u.email}? Their current password stops working.`} onClick={resetPassword(u, "temporary")}>
                          Temp password
                        </ActionButton>
                        {u.status === "active" ? (
                          <>
                            <input className="reason" placeholder="Reason (optional)" value={reasons[u.id] ?? ""} onChange={(e) => setReasons({ ...reasons, [u.id]: e.target.value })} />
                            <ActionButton kind="secondary" confirm={`Suspend ${u.email}?`} onClick={setStatus(u, "suspended")}>Suspend</ActionButton>
                            <ActionButton kind="danger" confirm={`Ban ${u.email} permanently?`} onClick={setStatus(u, "banned")}>Ban</ActionButton>
                          </>
                        ) : (
                          <ActionButton kind="secondary" onClick={setStatus(u, "active")}>Reactivate</ActionButton>
                        )}
                      </>
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
