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

  const users = data ?? [];
  const q = query.toLowerCase();
  const rows = users
    .filter((u) => (tab === "suspended" ? u.status !== "active" : u.role === tab))
    .filter((u) => !q || `${u.email} ${u.artist_name ?? ""} ${u.studio_name ?? ""} ${u.artist_city ?? ""}`.toLowerCase().includes(q));

  const setStatus = (user: AdminUser, status: AccountStatus) => async () => {
    const reason = status === "active" ? undefined : window.prompt(`Reason for ${status === "banned" ? "banning" : "suspending"} ${user.email}?`) ?? undefined;
    if (status !== "active" && reason === undefined) return;
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
                  <td>{u.is_verified ? "✔︎" : ""}</td>
                  <td>{u.booking_count}</td>
                  <td>{date(u.created_at)}</td>
                  <td className="actions">
                    {u.role !== "admin" && (
                      <>
                        <ActionButton kind="secondary" onClick={async () => { await api.verifyUser(u.id, !u.is_verified); await reload(); }}>
                          {u.is_verified ? "Unverify" : "Verify"}
                        </ActionButton>
                        {u.status === "active" ? (
                          <>
                            <ActionButton kind="secondary" onClick={setStatus(u, "suspended")}>Suspend</ActionButton>
                            <ActionButton kind="danger" onClick={setStatus(u, "banned")}>Ban</ActionButton>
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
