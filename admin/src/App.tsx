import { useEffect, useState } from "react";
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

  useEffect(() => {
    api.currentAdminEmail().then(setEmail).catch(() => setEmail(null));
  }, []);

  if (email === undefined) return <div className="center muted">Loading…</div>;
  if (!email) return <Login onSignedIn={setEmail} />;

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
