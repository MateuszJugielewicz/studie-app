import { useState } from "react";
import { ActionButton, Badge, Modal, PageState, Search, Tabs } from "../components";
import { ModerationPanel } from "../moderation";
import { useApi, useLoad } from "../lib/apiContext";
import { date, label } from "../lib/format";
import type { AdminUser } from "../lib/types";

type Tab = "artist" | "studio_owner" | "suspended" | "warned" | "admin";

export default function UsersPage() {
  const api = useApi();
  const { data, loading, error, reload } = useLoad(() => api.users());
  const [tab, setTab] = useState<Tab>("artist");
  const [query, setQuery] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const users = data ?? [];
  const selected = users.find((u) => u.id === selectedId) ?? null;
  const q = query.toLowerCase();
  const filters: Record<Tab, (u: AdminUser) => boolean> = {
    artist: (u) => u.role === "artist",
    studio_owner: (u) => u.role === "studio_owner",
    suspended: (u) => u.status !== "active",
    warned: (u) => (u.warning_count ?? 0) > 0,
    admin: (u) => u.role === "admin",
  };
  const rows = users
    .filter(filters[tab])
    .filter((u) => !q || `${u.email} ${u.artist_name ?? ""} ${u.studio_name ?? ""} ${u.artist_city ?? ""}`.toLowerCase().includes(q));

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
          { id: "artist", title: "Artists", count: users.filter(filters.artist).length },
          { id: "studio_owner", title: "Studios", count: users.filter(filters.studio_owner).length },
          { id: "suspended", title: "Suspended / banned", count: users.filter(filters.suspended).length },
          { id: "warned", title: "Warned", count: users.filter(filters.warned).length },
          { id: "admin", title: "Admins" },
        ]}
      />
      <PageState loading={loading && !data} error={error} empty={rows.length === 0}>
        <div className="card flush">
          <table className="clickable">
            <thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th>Warnings</th><th>Verified</th><th>Bookings</th><th>Joined</th></tr></thead>
            <tbody>
              {rows.map((u) => (
                <tr key={u.id} onClick={() => setSelectedId(u.id)}>
                  <td className="strong">
                    {u.artist_name || u.studio_name || "–"}
                    {u.has_admin_badge && <span className="badge blue" style={{ marginLeft: 6 }}>Team</span>}
                    <div className="muted small">{u.artist_city}</div>
                  </td>
                  <td>{u.email}</td>
                  <td>{label(u.role)}</td>
                  <td>
                    <Badge value={u.status} />
                    {u.status !== "active" && <div className="muted small">{u.status_until ? `until ${date(u.status_until, true)}` : "until lifted"}</div>}
                    {u.status_reason && <div className="muted small">{u.status_reason}</div>}
                  </td>
                  <td>{u.warning_count ? <Badge value="pending" text={String(u.warning_count)} /> : <span className="muted">0</span>}</td>
                  <td>{u.is_verified ? "Yes" : <span className="muted">No</span>}</td>
                  <td>{u.booking_count}</td>
                  <td>{date(u.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
      {selected && <UserModal user={selected} onClose={() => setSelectedId(null)} onChanged={reload} />}
    </>
  );
}

function UserModal({ user, onClose, onChanged }: { user: AdminUser; onClose: () => void; onChanged: () => Promise<void> }) {
  const api = useApi();
  const [resetResult, setResetResult] = useState<{ email: string; password?: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const isAdmin = user.role === "admin";

  const resetPassword = (mode: "email" | "temporary") => async () => {
    setCopied(false);
    setResetResult(await api.resetPassword(user.id, mode));
  };

  return (
    <Modal title={user.artist_name || user.studio_name || user.email} onClose={onClose}>
      <div className="row gap wrap">
        <Badge value={user.status} />
        <span className="muted">{label(user.role)} · {user.email} · joined {date(user.created_at)}</span>
        {user.studio_name && <span className="muted">· studio: {user.studio_name}</span>}
      </div>

      {!isAdmin && (
        <div className="row gap wrap">
          <ActionButton kind="secondary" onClick={async () => { await api.verifyUser(user.id, !user.is_verified); await onChanged(); }}>
            {user.is_verified ? "Remove verification" : "Verify"}
          </ActionButton>
          <ActionButton kind="secondary" onClick={async () => { await api.setAdminBadge(user.id, !user.has_admin_badge); await onChanged(); }}>
            {user.has_admin_badge ? "Remove team badge" : "Give team badge"}
          </ActionButton>
          <ActionButton kind="secondary" confirm={`Send a password reset email to ${user.email}?`} onClick={resetPassword("email")}>Reset password</ActionButton>
          <ActionButton kind="secondary" confirm={`Set a temporary password for ${user.email}? Their current password stops working.`} onClick={resetPassword("temporary")}>Temp password</ActionButton>
        </div>
      )}
      {!isAdmin && <p className="muted small">The team badge is only a label on the profile ("EasySesh team"). It gives no admin rights.</p>}

      {resetResult && (
        <div className="card notice">
          {resetResult.password ? (
            <div>
              <strong>Temporary password for {resetResult.email}</strong>
              <div className="row gap wrap">
                <span className="mono big-mono">{resetResult.password}</span>
                <button className="secondary" onClick={async () => { await navigator.clipboard.writeText(resetResult.password!); setCopied(true); }}>
                  {copied ? "Copied" : "Copy"}
                </button>
              </div>
              <div className="muted small">Shown only once. Give it to the user privately; they should change it in Settings → Change password.</div>
            </div>
          ) : (
            <div><strong>Reset email sent to {resetResult.email}.</strong></div>
          )}
        </div>
      )}

      {!isAdmin && (
        <ModerationPanel
          userId={user.id}
          studioId={user.studio_id}
          status={user.status}
          statusUntil={user.status_until}
          onChanged={onChanged}
        />
      )}
    </Modal>
  );
}
