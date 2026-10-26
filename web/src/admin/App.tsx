import { useEffect, useState } from "react";
import type { MfaState, StaffRank } from "./lib/types";
import { NavLink, Navigate, Route, Routes, useLocation } from "react-router-dom";
import { api as configuredApi, ApiContext, rankAtLeast, StaffContext } from "./lib/apiContext";
import { ReasonDialog } from "./ReasonDialog";
import TeamPage from "./pages/TeamPage";
import AuditPage from "./pages/AuditPage";
import EmailPage from "./pages/EmailPage";
import CampaignsPage from "./pages/CampaignsPage";
import BannersPage from "./pages/BannersPage";
import FlagRulesPage from "./pages/FlagRulesPage";
import { websiteUrl } from "../lib/hosts";
import type { AdminApi } from "./lib/api";
import OverviewPage from "./pages/OverviewPage";
import StudiosPage from "./pages/StudiosPage";
import UsersPage from "./pages/UsersPage";
import BookingsPage from "./pages/BookingsPage";
import PaymentsPage from "./pages/PaymentsPage";
import ModerationPage from "./pages/ModerationPage";
import SupportPage from "./pages/SupportPage";
import PromotionsPage from "./pages/PromotionsPage";
import PromoCodesPage from "./pages/PromoCodesPage";
import ChangelogPage from "./pages/ChangelogPage";
import VerificationPage from "./pages/VerificationPage";
import StoriesPage from "./pages/StoriesPage";

// Simple 24px stroke icons (Lucide-style paths).
const icons: Record<string, string> = {
  overview: "M3 3v18h18M7 15l4-4 3 3 5-6",
  studios: "M4 21V8l8-5 8 5v13M9 21v-6h6v6",
  users: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75",
  bookings: "M8 2v4M16 2v4M3 10h18M5 4h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z",
  payments: "M2 7h20v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2zM2 11h20M6 16h4",
  moderation: "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z",
  promotions: "M3 11l18-5v12L3 14v-3zM11.6 16.8a3 3 0 1 1-5.8-1.6",
  team: "M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M19 8l2 2 4-4",
  audit: "M9 11l3 3L22 4M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11",
  campaigns: "M22 2L11 13M22 2l-7 20-4-9-9-4z",
  email: "M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zM22 6l-10 7L2 6",
  banners: "M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1zM4 22v-7",
  codes: "M20.6 13.4l-7.2 7.2a2 2 0 0 1-2.8 0L2 12V2h10l8.6 8.6a2 2 0 0 1 0 2.8zM7 7h.01",
  changelog: "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z",
  verification: "M12 2l2.4 2.4 3.4-.4.4 3.4L20.6 10l-2.4 2.4.4 3.4-3.4.4L12.8 18.6 10.4 16.2 7 16.6l-.4-3.4L4.2 10.8 6.6 8.4 6.2 5l3.4-.4zM9 11l2 2 4-4",
  stories: "M12 2a10 10 0 1 0 10 10M12 7v5l3 3M17 2.5a10 10 0 0 1 4.5 4.5",
  support: "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2zM8 9h8M8 13h5",
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
      easysesh<span className="dot" />
      {tag && <span className="tag">{tag}</span>}
    </div>
  );
}

const nav: { to: string; title: string; icon: string; min?: StaffRank }[] = [
  { to: "/", title: "Overview", icon: "overview" },
  { to: "/studios", title: "Studios", icon: "studios" },
  { to: "/users", title: "Users", icon: "users" },
  { to: "/bookings", title: "Bookings", icon: "bookings" },
  { to: "/payments", title: "Payments", icon: "payments" },
  { to: "/promotions", title: "Promotions", icon: "promotions" },
  { to: "/promo-codes", title: "Promo codes", icon: "codes" },
  { to: "/moderation", title: "Moderation", icon: "moderation" },
  { to: "/verification", title: "Verification", icon: "verification" },
  { to: "/stories", title: "Stories", icon: "stories" },
  { to: "/support", title: "Support", icon: "support" },
  { to: "/changelog", title: "Changelog", icon: "changelog" },
  { to: "/banners", title: "Banners", icon: "banners", min: "admin" as StaffRank },
  { to: "/auto-flags", title: "Auto-flags", icon: "moderation", min: "admin" as StaffRank },
  { to: "/email", title: "Email", icon: "email" },
  { to: "/campaigns", title: "Campaigns", icon: "campaigns", min: "admin" as StaffRank },
  { to: "/team", title: "Team", icon: "team", min: "owner" as StaffRank },
  { to: "/audit", title: "Audit log", icon: "audit", min: "owner" as StaffRank },
];

export default function App() {
  if (!configuredApi) {
    return (
      <div className="center">
        <div className="card login">
          <Logo big />
          <h2>Missing configuration</h2>
          <p className="muted">The Supabase keys are missing. Check <span className="mono">ios/Config/App.xcconfig</span> or set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in web/.env.local.</p>
        </div>
      </div>
    );
  }
  return <Dashboard api={configuredApi} />;
}

/**
 * On phones, tables become stacked cards (styles.css). Each cell needs its column name for that, so
 * copy the header text onto the cells as data-label; React leaves unknown attributes alone, and the
 * observer labels rows that appear later (filters, reloads).
 */
function useMobileTableLabels() {
  useEffect(() => {
    const label = () => {
      for (const table of Array.from(document.querySelectorAll<HTMLTableElement>(".content table"))) {
        const headers = Array.from(table.querySelectorAll("thead th")).map((th) => th.textContent?.trim() ?? "");
        for (const row of Array.from(table.querySelectorAll("tbody tr"))) {
          Array.from(row.children).forEach((cell, i) => {
            if (headers[i] && cell.getAttribute("data-label") !== headers[i]) cell.setAttribute("data-label", headers[i]);
          });
        }
      }
    };
    label();
    const observer = new MutationObserver(label);
    observer.observe(document.body, { childList: true, subtree: true });
    return () => observer.disconnect();
  }, []);
}

function Dashboard({ api }: { api: AdminApi }) {
  const [email, setEmail] = useState<string | null | undefined>(undefined);
  const [mfa, setMfa] = useState<MfaState | null>(null);
  const [openSupport, setOpenSupport] = useState(0);
  const location = useLocation();
  useMobileTableLabels();

  // Support requests waiting for a reply, refreshed every 30 seconds and on navigation.
  useEffect(() => {
    if (mfa?.kind !== "verified") return;
    const refresh = () => api.supportOpenCount().then(setOpenSupport).catch(() => {});
    void refresh();
    const timer = window.setInterval(refresh, 30_000);
    return () => window.clearInterval(timer);
  }, [mfa?.kind, location.pathname]);

  useEffect(() => {
    document.title = openSupport > 0 ? `(${openSupport}) EasySesh Admin` : "EasySesh Admin";
  }, [openSupport]);

  const refreshMfa = () => api.mfaState().then(setMfa).catch(() => setMfa(null));

  useEffect(() => {
    api.currentAdminEmail().then(setEmail).catch(() => setEmail(null));
  }, []);

  useEffect(() => {
    if (email) void refreshMfa();
  }, [email]);

  const [staff, setStaff] = useState<{ email: string; rank: StaffRank } | null>(null);
  useEffect(() => {
    if (mfa?.kind === "verified") api.currentStaff().then(setStaff).catch(() => setStaff({ email: email ?? "", rank: "support" }));
  }, [mfa?.kind, api, email]);

  if (email === undefined) return <div className="center muted">Loading…</div>;
  if (!email) return <Login api={api} onSignedIn={setEmail} />;
  if (!mfa) return <div className="center muted">Checking two-factor authentication…</div>;
  if (mfa.kind !== "verified") {
    return <TwoFactor api={api} state={mfa} onVerified={refreshMfa} onCancel={async () => { await api.signOut(); setEmail(null); setMfa(null); }} />;
  }

  if (!staff) return <div className="center muted">Loading…</div>;
  const allowed = (min?: StaffRank) => !min || rankAtLeast(staff.rank, min);

  return (
    <ApiContext.Provider value={api}>
     <StaffContext.Provider value={staff}>
      <ReasonDialog />
      <div className="layout">
        <aside className="sidebar">
          <Logo tag="admin" />
          <nav>
            {nav.filter((item) => allowed(item.min)).map((item) => (
              <NavLink key={item.to} to={item.to} end={item.to === "/"} className={({ isActive }) => (isActive ? "nav active" : "nav")}>
                <Icon name={item.icon} /> {item.title}
                {item.to === "/support" && openSupport > 0 && (
                  <span className="nav-badge" title={`${openSupport} waiting for a reply`}>{openSupport}</span>
                )}
              </NavLink>
            ))}
          </nav>
          <div className="sidebar-footer">
            <div className="muted small account-email">{email} · {staff.rank}</div>
            <a href={websiteUrl} className="muted small">Open the website</a>
            <button className="ghost" onClick={async () => { await api.signOut(); setEmail(null); }}>Sign out</button>
          </div>
        </aside>
        <main className="content">
          <Routes>
            <Route path="/" element={<OverviewPage openSupport={openSupport} />} />
            <Route path="/studios" element={<StudiosPage />} />
            <Route path="/users" element={<UsersPage />} />
            <Route path="/bookings" element={<BookingsPage />} />
            <Route path="/payments" element={<PaymentsPage />} />
            <Route path="/moderation" element={<ModerationPage />} />
            <Route path="/verification" element={<VerificationPage />} />
            <Route path="/stories" element={<StoriesPage />} />
            <Route path="/support" element={<SupportPage />} />
            <Route path="/promotions" element={<PromotionsPage />} />
            <Route path="/promo-codes" element={<PromoCodesPage />} />
            <Route path="/changelog" element={<ChangelogPage />} />
            <Route path="/email" element={<EmailPage />} />
            {allowed("admin") && <Route path="/banners" element={<BannersPage />} />}
            {allowed("admin") && <Route path="/auto-flags" element={<FlagRulesPage />} />}
            {allowed("admin") && <Route path="/campaigns" element={<CampaignsPage />} />}
            {allowed("owner") && <Route path="/team" element={<TeamPage />} />}
            {allowed("owner") && <Route path="/audit" element={<AuditPage />} />}
            <Route path="*" element={<Navigate to="/" />} />
          </Routes>
        </main>
      </div>
     </StaffContext.Provider>
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
        <a href={websiteUrl} className="muted small" style={{ alignSelf: "center" }}>Back to the website</a>
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
