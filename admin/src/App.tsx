import { useEffect, useState } from "react";
import type { MfaState } from "./lib/types";
import { NavLink, Navigate, Route, Routes } from "react-router-dom";
import { api as configuredApi, ApiContext } from "./lib/apiContext";
import type { AdminApi } from "./lib/api";
import OverviewPage from "./pages/OverviewPage";
import StudiosPage from "./pages/StudiosPage";
import UsersPage from "./pages/UsersPage";
import BookingsPage from "./pages/BookingsPage";
import PaymentsPage from "./pages/PaymentsPage";
import ModerationPage from "./pages/ModerationPage";

// Simple 24px stroke icons (Lucide-style paths).
const icons: Record<string, string> = {
  overview: "M3 3v18h18M7 15l4-4 3 3 5-6",
  studios: "M4 21V8l8-5 8 5v13M9 21v-6h6v6",
  users: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75",
  bookings: "M8 2v4M16 2v4M3 10h18M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z",
  payments: "M2 7h20v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2zM2 11h20M6 16h4",
  moderation: "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z",
};

function Icon({ name }: { name: string }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={icons[name]} />
    </svg>
  );
}

export function Logo({ big = false, tag }: { big?: boolean; tag?: string }) {
  return (
    <div className={big ? "logo big" : "logo"}>
      sonora<span className="dot" />
      {tag && <span className="tag">{tag}</span>}
    </div>
  );
}

const nav = [
  { to: "/", title: "Overview", icon: "overview" },
  { to: "/studios", title: "Studios", icon: "studios" },
  { to: "/users", title: "Users", icon: "users" },
  { to: "/bookings", title: "Bookings", icon: "bookings" },
  { to: "/payments", title: "Payments", icon: "payments" },
  { to: "/moderation", title: "Moderation", icon: "moderation" },
];

export default function App() {
  if (!configuredApi) {
    return (
      <div className="center">
        <div className="card login">
          <Logo big />
          <h2>Missing configuration</h2>
          <p className="muted">Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to admin/.env.development, then restart <span className="mono">npm run dev</span>.</p>
        </div>
      </div>
    );
  }
  return <Dashboard api={configuredApi} />;
}

function Dashboard({ api }: { api: AdminApi }) {
  const [email, setEmail] = useState<string | null | undefined>(undefined);
  const [mfa, setMfa] = useState<MfaState | null>(null);

  const refreshMfa = () => api.mfaState().then(setMfa).catch(() => setMfa(null));

  useEffect(() => {
    api.currentAdminEmail().then(setEmail).catch(() => setEmail(null));
  }, []);

  useEffect(() => {
    if (email) void refreshMfa();
  }, [email]);

  if (email === undefined) return <div className="center muted">Loading…</div>;
  if (!email) return <Login api={api} onSignedIn={setEmail} />;
  if (!mfa) return <div className="center muted">Checking two-factor authentication…</div>;
  if (mfa.kind !== "verified") {
    return <TwoFactor api={api} state={mfa} onVerified={refreshMfa} onCancel={async () => { await api.signOut(); setEmail(null); setMfa(null); }} />;
  }

  return (
    <ApiContext.Provider value={api}>
      <div className="layout">
        <aside className="sidebar">
          <Logo tag="admin" />
          <nav>
            {nav.map((item) => (
              <NavLink key={item.to} to={item.to} end={item.to === "/"} className={({ isActive }) => (isActive ? "nav active" : "nav")}>
                <Icon name={item.icon} /> {item.title}
              </NavLink>
            ))}
          </nav>
          <div className="sidebar-footer">
            <div className="muted small">{email}</div>
            <button className="ghost" onClick={async () => { await api.signOut(); setEmail(null); }}>Sign out</button>
          </div>
        </aside>
        <main className="content">
          <Routes>
            <Route path="/" element={<OverviewPage />} />
            <Route path="/studios" element={<StudiosPage />} />
            <Route path="/users" element={<UsersPage />} />
            <Route path="/bookings" element={<BookingsPage />} />
            <Route path="/payments" element={<PaymentsPage />} />
            <Route path="/moderation" element={<ModerationPage />} />
            <Route path="*" element={<Navigate to="/" />} />
          </Routes>
        </main>
      </div>
    </ApiContext.Provider>
  );
}

function Login({ api, onSignedIn }: { api: AdminApi; onSignedIn: (email: string) => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <div className="center">
      <form
        className="card login"
        onSubmit={async (e) => {
          e.preventDefault();
          setBusy(true);
          try {
            await api.signIn(email, password);
            onSignedIn((await api.currentAdminEmail()) ?? email);
          } catch (err) {
            setError((err as Error).message);
          } finally {
            setBusy(false);
          }
        }}
      >
        <Logo big />
        <p className="muted">Admin dashboard</p>
        <label>Email<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required /></label>
        <label>Password<input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required /></label>
        {error && <p className="error-text">{error}</p>}
        <button className="primary" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
      </form>
    </div>
  );
}

/** Admins must use an authenticator app (TOTP). First sign-in enrols, later sign-ins verify. */
function TwoFactor({ api, state, onVerified, onCancel }: { api: AdminApi; state: Exclude<MfaState, { kind: "verified" }>; onVerified: () => void; onCancel: () => void }) {
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  return (
    <div className="center">
      <form
        className="card login"
        onSubmit={async (e) => {
          e.preventDefault();
          setBusy(true);
          try {
            await api.verifyMfa(state.factorId, code.replace(/\s/g, ""));
            onVerified();
          } catch (err) {
            setError((err as Error).message);
          } finally {
            setBusy(false);
          }
        }}
      >
        <Logo big />
        <h2>Two-factor authentication</h2>
        {state.kind === "enroll" ? (
          <>
            <p className="muted">Admin accounts require an authenticator app. Scan the code with Google Authenticator, 1Password or similar, then enter the 6-digit code.</p>
            <img src={state.qrCode} alt="Authenticator QR code" style={{ width: 200, height: 200, background: "white", borderRadius: 8, alignSelf: "center" }} />
            <p className="muted small">Can't scan? Enter this key: <span className="mono">{state.secret}</span></p>
          </>
        ) : (
          <p className="muted">Enter the 6-digit code from your authenticator app.</p>
        )}
        <label>Code<input inputMode="numeric" autoComplete="one-time-code" value={code} onChange={(e) => setCode(e.target.value)} required /></label>
        {error && <p className="error-text">{error}</p>}
        <button className="primary" disabled={busy || code.replace(/\s/g, "").length < 6}>{busy ? "Verifying…" : "Verify"}</button>
        <button type="button" className="ghost" onClick={onCancel}>Cancel</button>
      </form>
    </div>
  );
}
