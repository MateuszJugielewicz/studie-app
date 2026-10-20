import { lazy, Suspense, useEffect, type ReactNode } from "react";
import { BrowserRouter, Link, Navigate, NavLink, Route, Routes, useLocation } from "react-router-dom";
import { Bell, Building2, CalendarDays, LayoutGrid, LogIn, MessagesSquare, SearchCheck, UserRound, type LucideIcon } from "lucide-react";
import { useApp } from "./lib/state";
import { t } from "./lib/i18n";
import { Avatar, Loading, Logo } from "./components/ui";
import { GlobalSheets } from "./pages/Gates";
import { adminUrl, hasAdminSubdomain } from "./lib/hosts";
import { VerifyEmailBanner } from "./pages/VerifyEmail";
import { SiteBanners, ViewAsBar } from "./components/TopBanners";

const Landing = lazy(() => import("./pages/Landing"));
const Auth = lazy(() => import("./pages/Auth"));
const Discover = lazy(() => import("./pages/Discover"));
const StudioDetail = lazy(() => import("./pages/StudioDetail"));
const BookingFlow = lazy(() => import("./pages/BookingFlow"));
const Bookings = lazy(() => import("./pages/Bookings"));
const Chat = lazy(() => import("./pages/Chat"));
const Inbox = lazy(() => import("./pages/Inbox"));
const Profile = lazy(() => import("./pages/Profile"));
const Settings = lazy(() => import("./pages/Settings"));
const Support = lazy(() => import("./pages/Support"));
const Legal = lazy(() => import("./pages/Legal"));
const ArtistPublic = lazy(() => import("./pages/ArtistPublic"));
const Reviews = lazy(() => import("./pages/Reviews"));
const StudioOwner = lazy(() => import("./pages/StudioOwner"));
const StudioEditor = lazy(() => import("./pages/StudioEditor"));
const VerifyEmail = lazy(() => import("./pages/VerifyEmail"));

interface Tab { to: string; title: string; icon: LucideIcon; badge?: number; match?: string[] }

function useTabs(): Tab[] {
  const app = useApp();
  if (!app.account) return [{ to: "/studios", title: "Discover", icon: SearchCheck }];
  if (app.account.role === "studio_owner") {
    if (!app.ownedStudio || !["approved", "suspended"].includes(app.ownedStudio.status)) return [];
    return [
      { to: "/studio", title: "Dashboard", icon: LayoutGrid },
      { to: "/studio/calendar", title: "Calendar", icon: CalendarDays },
      { to: "/messages", title: "Messages", icon: MessagesSquare, badge: app.unreadMessages },
      { to: "/inbox", title: "Inbox", icon: Bell, badge: app.unreadNotifications },
      { to: "/studio/listing", title: "Studio", icon: Building2 },
    ];
  }
  if (app.account.role === "admin") return [];
  return [
    { to: "/studios", title: "Discover", icon: SearchCheck },
    { to: "/sessions", title: "Sessions", icon: CalendarDays },
    { to: "/messages", title: "Messages", icon: MessagesSquare, badge: app.unreadMessages },
    { to: "/inbox", title: "Inbox", icon: Bell, badge: app.unreadNotifications },
    { to: "/profile", title: "Profile", icon: UserRound },
  ];
}

function isActive(tab: Tab, path: string) {
  if (tab.to === "/studio") return path === "/studio" || path.startsWith("/sessions") || path.startsWith("/studio/earnings") || path.startsWith("/studio/bookings") || path.startsWith("/studio/reviews");
  if (tab.to === "/studio/listing") return path.startsWith("/studio/listing") || path.startsWith("/studio/edit") || path.startsWith("/studio/payouts") || path.startsWith("/studio/promotion") || path.startsWith("/studio/offers") || path.startsWith("/studio/artist-link");
  if (tab.to === "/profile") return path.startsWith("/profile") || path.startsWith("/settings") || path.startsWith("/support");
  return path === tab.to || path.startsWith(tab.to + "/");
}

function Shell({ children }: { children: ReactNode }) {
  const app = useApp();
  const tabs = useTabs();
  const { pathname } = useLocation();
  const animated = pathname === "/" || pathname.startsWith("/signin") || pathname.startsWith("/signup");
  useEffect(() => { window.scrollTo(0, 0); }, [pathname]);
  const name = app.artistProfile?.artist_name || app.ownedStudio?.name || app.account?.email || "";
  return (
    <>
      <div className={`aurora ${animated ? "animated" : ""}`}><span /><i /></div>
      <div className="app">
        <header className="topbar">
          <Link to="/" aria-label="EasySesh"><Logo size={24} /></Link>
          <nav>
            {tabs.length > 1 && tabs.map((tab) => (
              <NavLink key={tab.to} to={tab.to} className={() => (isActive(tab, pathname) ? "active" : "")}>
                <tab.icon size={17} />{t(tab.title)}{!!tab.badge && <span className="badge-count">{tab.badge > 99 ? "99+" : tab.badge}</span>}
              </NavLink>
            ))}
          </nav>
          <div className="row" style={{ gap: 8, marginLeft: "auto" }}>
            {app.account ? (
              app.account.role !== "admin" && (
                <Link to={app.account.role === "studio_owner" ? "/settings" : "/profile"} aria-label={t("Profile")}>
                  <Avatar url={app.artistProfile?.avatar_url ?? app.ownedStudio?.photo_urls[0]} name={name} size={34} />
                </Link>
              )
            ) : (
              <>
                <Link to="/signin" className="btn secondary small hide-mobile"><LogIn size={16} />{t("Sign in")}</Link>
                <Link to="/signup" className="btn primary small">{t("Sign up")}</Link>
              </>
            )}
          </div>
        </header>
        <ViewAsBar />
        <SiteBanners />
        <VerifyEmailBanner />
        <Suspense fallback={<Loading />}>{children}</Suspense>
        <nav className={`tabbar ${tabs.length > 1 ? "show" : ""}`}>
          {tabs.length > 1 && tabs.map((tab) => (
            <Link key={tab.to} to={tab.to} className={isActive(tab, pathname) ? "active" : ""}>
              <tab.icon size={20} />{t(tab.title)}{!!tab.badge && <span className="badge-count">{tab.badge > 99 ? "99+" : tab.badge}</span>}
            </Link>
          ))}
        </nav>
      </div>
    </>
  );
}

/** Pages that need an account send guests to sign-up first (like the app's guest mode). */
function RequireAuth({ children, role }: { children: ReactNode; role?: "artist" | "studio_owner" }) {
  const app = useApp();
  const location = useLocation();
  if (!app.account) return <Navigate to={`/signin?next=${encodeURIComponent(location.pathname + location.search)}`} replace />;
  if (role && app.account.role !== role) return <Navigate to="/" replace />;
  return <>{children}</>;
}

function Home() {
  const app = useApp();
  if (!app.account) return <Landing />;
  if (app.account.role === "studio_owner") return <Navigate to="/studio" replace />;
  if (app.account.role === "admin") return <Navigate to="/admin" replace />;
  return <Navigate to="/studios" replace />;
}

/** New artists finish their profile first (iOS ArtistOnboardingView). */
function Onboarding({ children }: { children: ReactNode }) {
  const app = useApp();
  const { pathname } = useLocation();
  const incomplete = app.account?.role === "artist" && !(app.artistProfile?.artist_name.trim() && app.artistProfile.city);
  // Links from emails (confirming the address) work before the profile is finished.
  const exempt = ["/onboarding", "/legal", "/auth", "/verify-email"].some((p) => pathname.startsWith(p));
  if (incomplete && !exempt) return <Navigate to="/onboarding" replace />;
  return <>{children}</>;
}

export default function App() {
  const app = useApp();
  if (!app.ready) return <Splash />;
  return (
    <BrowserRouter>
      <Shell>
        <Onboarding>
          <Routes key={app.language}>
            <Route path="/" element={<Home />} />
            <Route path="/signin" element={<Auth mode="signin" />} />
            <Route path="/signup" element={<Auth mode="signup" />} />
            <Route path="/auth/callback" element={<Auth mode="callback" />} />
            <Route path="/verify-email" element={<VerifyEmail />} />
            <Route path="/studios" element={<Discover />} />
            <Route path="/studios/:id" element={<StudioDetail />} />
            <Route path="/studios/:id/reviews" element={<Reviews />} />
            <Route path="/artists/:id" element={<ArtistPublic />} />
            <Route path="/legal" element={<Legal />} />
            <Route path="/legal/:doc" element={<Legal />} />
            <Route path="/book/:studioId" element={<RequireAuth role="artist"><BookingFlow /></RequireAuth>} />
            <Route path="/sessions/*" element={<RequireAuth><Bookings /></RequireAuth>} />
            <Route path="/messages/*" element={<RequireAuth><Chat /></RequireAuth>} />
            <Route path="/inbox" element={<RequireAuth><Inbox /></RequireAuth>} />
            <Route path="/onboarding" element={<RequireAuth role="artist"><Profile onboarding /></RequireAuth>} />
            <Route path="/profile/*" element={<RequireAuth role="artist"><Profile /></RequireAuth>} />
            <Route path="/settings/*" element={<RequireAuth><Settings /></RequireAuth>} />
            <Route path="/support/*" element={<RequireAuth><Support /></RequireAuth>} />
            <Route path="/studio/edit/*" element={<RequireAuth role="studio_owner"><StudioEditor /></RequireAuth>} />
            <Route path="/studio/*" element={<RequireAuth role="studio_owner"><StudioOwner /></RequireAuth>} />
            <Route path="/admin/*" element={<AdminRedirect />} />
            <Route path="*" element={<NotFound />} />
          </Routes>
        </Onboarding>
        <GlobalSheets />
      </Shell>
    </BrowserRouter>
  );
}

function Splash() {
  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 22 }}>
      <div className="aurora animated"><span /><i /></div>
      <div style={{ position: "relative" }}><Logo size={46} /></div>
      <div className="meter" style={{ height: 26, width: 60, position: "relative" }}>{[0.45, 0.8, 1, 0.65, 0.9, 0.5, 0.75].map((h, i) => <span key={i} style={{ height: `${h * 100}%`, animationDelay: `${i * 60}ms` }} />)}</div>
    </div>
  );
}

/** The admin dashboard is a separate app (admin.easysesh.live, or /admin elsewhere): leave with a full page load. */
function AdminRedirect() {
  const { pathname, search } = useLocation();
  useEffect(() => {
    const rest = pathname.replace(/^\/admin\/?/, "") + search;
    window.location.replace(hasAdminSubdomain ? adminUrl(rest) : `/admin/${rest}`);
  }, []);
  return <Loading />;
}

function NotFound() {
  return (
    <main className="page narrow">
      <div className="card empty" style={{ marginTop: 40 }}>
        <div className="title-m">{t("We couldn't find that.")}</div>
        <Link to="/" className="btn primary" style={{ marginTop: 12 }}>{t("Continue")}</Link>
      </div>
    </main>
  );
}
