import { useEffect, useState } from "react";
import type { MfaState } from "./lib/types";
import { NavLink, Navigate, Route, Routes } from "react-router-dom";
import { api, ApiContext } from "./lib/apiContext";
import OverviewPage from "./pages/OverviewPage";
import StudiosPage from "./pages/StudiosPage";
import UsersPage from "./pages/UsersPage";
import BookingsPage from "./pages/BookingsPage";
import PaymentsPage from "./pages/PaymentsPage";
import ModerationPage from "./pages/ModerationPage";

const nav = [
  { to: "/", title: "Overview", icon: "📊" },
  { to: "/studios", title: "Studios", icon: "🎚️" },
  { to: "/users", title: "Users", icon: "👥" },
  { to: "/bookings", title: "Bookings", icon: "📅" },
  { to: "/payments", title: "Payments", icon: "💳" },
  { to: "/moderation", title: "Moderation", icon: "🛡️" },
];

export default function App() {
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
  if (!email) return <Login onSignedIn={setEmail} />;
  if (!mfa) return <div className="center muted">Checking two-factor authentication…</div>;
  if (mfa.kind !== "verified") {
    return <TwoFactor state={mfa} onVerified={refreshMfa} onCancel={async () => { await api.signOut(); setEmail(null); setMfa(null); }} />;
  }

  return (
    <ApiContext.Provider value={api}>
      <div className="layout">
        <aside className="sidebar">
          <div className="logo">〰 SONORA <span className="muted small">admin</span></div>
          <nav>
            {nav.map((item) => (
              <NavLink key={item.to} to={item.to} end={item.to === "/"} className={({ isActive }) => (isActive ? "nav active" : "nav")}>
                <span>{item.icon}</span> {item.title}
              </NavLink>
            ))}
          </nav>
          <div className="sidebar-footer">
            {api.isDemo && <div className="badge orange">Demo data</div>}
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

function Login({ onSignedIn }: { onSignedIn: (email: string) => void }) {
  const [email, setEmail] = useState(api.isDemo ? "admin@sonora.app" : "");
  const [password, setPassword] = useState(api.isDemo ? "demo" : "");
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
        <div className="logo big">〰 SONORA</div>
        <p className="muted">Admin dashboard</p>
        {api.isDemo && <p className="badge orange">Demo mode – no Supabase keys configured</p>}
        <label>Email<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required /></label>
        <label>Password<input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required /></label>
        {error && <p className="error-text">{error}</p>}
        <button className="primary" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
      </form>
    </div>
  );
}

/** Admins must use an authenticator app (TOTP). First sign-in enrols, later sign-ins verify. */
function TwoFactor({ state, onVerified, onCancel }: { state: Exclude<MfaState, { kind: "verified" }>; onVerified: () => void; onCancel: () => void }) {
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
        <div className="logo big">〰 SONORA</div>
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
