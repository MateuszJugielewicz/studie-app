import { useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { Apple, Building2, Check, CheckCircle2, Circle, Eye, EyeOff, FileText, Lock, Mail, Mic } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { passwordProblem, passwordStrength } from "../lib/core";
import { t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { IconTile, Loading, Logo, Sheet, Tiles, useToast } from "../components/ui";
import { LEGAL, LegalDocumentBody, requiredDocuments, type LegalDocument } from "./Legal";
import type { UserRole } from "../lib/types";

export default function Auth({ mode: initial }: { mode: "signin" | "signup" | "callback" }) {
  if (initial === "callback") return <AuthCallback />;
  return <AuthForm initial={initial} />;
}

/** Email confirmation, password reset and Apple/Google sign-in return here (easysesh://auth-callback in the apps). */
function AuthCallback() {
  const app = useApp();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    const description = params.get("error_description");
    if (description) { setError(description); return; }
    let done = false;
    const finish = async () => {
      if (done) return;
      const { data } = await api.client.auth.getSession();
      if (!data.session) return;
      done = true;
      try {
        const account = await api.finishSocialSignIn();
        if (account) await app.didAuthenticate(account);
        if (params.get("type") === "recovery") app.setNeedsNewPassword(true);
        navigate("/", { replace: true });
      } catch (e) { setError(userMessage(e)); }
    };
    // supabase-js exchanges the code in the URL for a session on its own; wait for it.
    const { data } = api.client.auth.onAuthStateChange(() => { finish(); });
    finish();
    const timer = window.setTimeout(() => { if (!done) setError(t("This link has expired or was already used. Please try again.")); }, 10_000);
    return () => { data.subscription.unsubscribe(); window.clearTimeout(timer); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return (
    <main className="page narrow">
      {error ? (
        <div className="card empty" style={{ marginTop: 40 }}>
          <div className="headline">{error}</div>
          <Link to="/signin" className="btn primary" style={{ marginTop: 12 }}>{t("Sign in")}</Link>
        </div>
      ) : <Loading />}
    </main>
  );
}

function AuthForm({ initial }: { initial: "signin" | "signup" }) {
  const app = useApp();
  const toast = useToast();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [signUp, setSignUp] = useState(initial === "signup");
  const [role, setRole] = useState<UserRole>(params.get("role") === "studio" ? "studio_owner" : "artist");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [accepted, setAccepted] = useState(false);
  const [working, setWorking] = useState(false);
  const [legal, setLegal] = useState<LegalDocument | null>(null);
  // Only paths on this site, never "//other.site" or "https://…" (no open redirect after sign-in).
  const requested = params.get("next") ?? "";
  const next = /^\/(?![/\\])/.test(requested) ? requested : "/";
  const canSubmit = !working && email.includes("@") && password.length > 0 && (!signUp || (accepted && !passwordProblem(password)));

  useEffect(() => { setSignUp(initial === "signup"); }, [initial]);
  useEffect(() => { if (app.account) navigate(next, { replace: true }); }, [app.account, navigate, next]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setWorking(true);
    try {
      const account = signUp ? await api.signUp(email.trim(), password, role) : await api.signIn(email.trim(), password);
      await app.didAuthenticate(account);
    } catch (error) { toast(userMessage(error), signUp && userMessage(error).includes("@") ? "info" : "error"); }
    setWorking(false);
  }

  async function oauth(provider: "apple" | "google") {
    try { await api.startOAuth(provider, role); } catch (e) { toast(userMessage(e)); }
  }

  async function forgot() {
    try { await api.sendPasswordReset(email.trim()); toast(t("Check your inbox for a reset link."), "info"); } catch (e) { toast(userMessage(e)); }
  }

  return (
    <main className="page" style={{ maxWidth: 480 }}>
      <form className="stack-lg" onSubmit={submit} style={{ paddingTop: 16 }}>
        <div className="stack" style={{ gap: 10 }}>
          <Logo />
          <h1 className="title-l" style={{ fontSize: 36, marginTop: 10 }}>{t(signUp ? "Create your account" : "Welcome back")}</h1>
          <p className="secondary" style={{ margin: 0 }}>{t(signUp ? "Book studios or list your own in minutes." : "Sign in to book, chat and manage your sessions.")}</p>
        </div>

        {signUp && (
          <div className="stack" style={{ gap: 10 }}>
            <div className="eyebrow">{t("I am")}</div>
            <div className="grid-2" style={{ gap: 10 }}>
              <RoleCard title="Artist" subtitle="Find & book studios" icon={Mic} colors={Tiles.signal} on={role === "artist"} onClick={() => setRole("artist")} />
              <RoleCard title="Studio owner" subtitle="List your studio" icon={Building2} colors={Tiles.violet} on={role === "studio_owner"} onClick={() => setRole("studio_owner")} />
            </div>
            <div className="footnote secondary">{t(role === "artist"
              ? "Find and book studios, pay in the app or cash, and chat with studios about your sessions."
              : "Studio accounts are separate from artist accounts. You get access to studio tools only after our team has reviewed and approved your studio.")}</div>
          </div>
        )}

        <div className="stack" style={{ gap: 10 }}>
          <button type="button" className="btn dark block" onClick={() => oauth("apple")}><Apple size={20} fill="currentColor" />{t(signUp ? "Sign up with Apple" : "Sign in with Apple")}</button>
          <button type="button" className="btn secondary block" onClick={() => oauth("google")}><GoogleG />{t("Continue with Google")}</button>
        </div>

        <div className="row" style={{ gap: 12 }}>
          <span className="grow divider" /><span className="caption semibold secondary">{t("Or with email")}</span><span className="grow divider" />
        </div>

        <div className="stack" style={{ gap: 12 }}>
          <label className="field"><Mail size={18} /><input type="email" placeholder={t("Email")} autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} /></label>
          <label className="field">
            <Lock size={18} />
            <input type={showPassword ? "text" : "password"} placeholder={t("Password")} autoComplete={signUp ? "new-password" : "current-password"} value={password} onChange={(e) => setPassword(e.target.value)} />
            <button type="button" onClick={() => setShowPassword(!showPassword)} aria-label={t("Show password")}>{showPassword ? <EyeOff size={18} /> : <Eye size={18} />}</button>
          </label>
          {signUp && password && <StrengthMeter password={password} />}
          {!signUp && <div style={{ textAlign: "right" }}><button type="button" className="link-btn footnote" disabled={!email.includes("@")} onClick={forgot}>{t("Forgot password?")}</button></div>}
        </div>

        {signUp && (
          <div className="stack" style={{ gap: 10 }}>
            <button type="button" className="row top" style={{ textAlign: "left" }} onClick={() => setAccepted(!accepted)}>
              <span style={{ width: 24, height: 24, borderRadius: 12, flexShrink: 0, display: "inline-flex", alignItems: "center", justifyContent: "center", background: accepted ? "var(--primary)" : "transparent", border: accepted ? 0 : "1.5px solid var(--text-3)" }}>
                {accepted && <Check size={14} color="#fff" strokeWidth={3} />}
              </span>
              <span className="footnote">{t(role === "studio_owner" ? "I accept the Terms, the Studio Agreement and the Privacy Policy" : "I accept the Terms and the Privacy Policy")}</span>
            </button>
            <div className="chips" style={{ paddingLeft: 36 }}>
              {requiredDocuments(role).map((key) => (
                <button key={key} type="button" className="chip caption semibold" onClick={() => setLegal(LEGAL[key])}><FileText size={13} />{t(LEGAL[key].title)}</button>
              ))}
            </div>
          </div>
        )}

        <button type="submit" className="btn primary block" disabled={!canSubmit}>{working ? <span className="spinner" style={{ borderTopColor: "#fff" }} /> : t(signUp ? "Create account" : "Sign in")}</button>

        <div className="row subhead" style={{ justifyContent: "center", gap: 4 }}>
          <span className="secondary">{t(signUp ? "Already have an account?" : "New to EasySesh?")}</span>
          <Link to={`${signUp ? "/signin" : "/signup"}${params.toString() ? `?${params}` : ""}`} className="bold accent">{t(signUp ? "Sign in" : "Create account")}</Link>
        </div>
      </form>
      <Sheet open={!!legal} onClose={() => setLegal(null)} title={legal?.title} closeLabel="Done">
        {legal && <LegalDocumentBody doc={legal} />}
      </Sheet>
    </main>
  );
}

function RoleCard({ title, subtitle, icon, colors, on, onClick }: { title: string; subtitle: string; icon: typeof Mic; colors: string[]; on: boolean; onClick: () => void }) {
  return (
    <button type="button" onClick={onClick} className="card pressable" style={{ textAlign: "left", padding: 14, border: on ? "2px solid var(--primary)" : undefined, boxShadow: on ? "0 0 0 3px color-mix(in srgb, var(--primary) 15%, transparent)" : undefined }}>
      <div className="row spread">
        <IconTile icon={icon} size={38} colors={on ? colors : Tiles.muted} />
        {on ? <CheckCircle2 size={22} color="var(--primary)" /> : <Circle size={22} className="tertiary" />}
      </div>
      <div className="subhead heavy" style={{ marginTop: 12 }}>{t(title)}</div>
      <div className="caption secondary">{t(subtitle)}</div>
    </button>
  );
}

function StrengthMeter({ password }: { password: string }) {
  const score = passwordStrength(password);
  const label = score <= 1 ? "Too weak" : score === 2 ? "Okay" : score === 3 ? "Strong" : "Very strong";
  const problem = passwordProblem(password);
  return (
    <div className="stack" style={{ gap: 6, padding: "0 4px" }}>
      <div className="row" style={{ gap: 6 }}>{[0, 1, 2, 3].map((i) => <span key={i} style={{ flex: 1, height: 5, borderRadius: 3, background: i < score ? "var(--primary)" : "var(--fill)" }} />)}</div>
      <div className="row spread caption"><span className="bold">{t(label)}</span>{problem && <span className="warning" style={{ textAlign: "right" }}>{problem}</span>}</div>
    </div>
  );
}

function GoogleG() {
  return (
    <svg width="18" height="18" viewBox="0 0 48 48" aria-hidden>
      <path fill="#FFC107" d="M43.6 20.5H42V20H24v8h11.3C33.7 32.7 29.2 36 24 36c-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.8 1.2 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.4-.4-3.5z" />
      <path fill="#FF3D00" d="M6.3 14.7l6.6 4.8C14.7 15.1 19 12 24 12c3.1 0 5.8 1.2 7.9 3l5.7-5.7C34 6.1 29.3 4 24 4 16.3 4 9.7 8.3 6.3 14.7z" />
      <path fill="#4CAF50" d="M24 44c5.2 0 9.9-2 13.4-5.2l-6.2-5.2C29.2 35.1 26.7 36 24 36c-5.2 0-9.6-3.3-11.3-8l-6.5 5C9.5 39.6 16.2 44 24 44z" />
      <path fill="#1976D2" d="M43.6 20.5H42V20H24v8h11.3c-.8 2.2-2.2 4.2-4.1 5.6l6.2 5.2C37 39.2 44 34 44 24c0-1.3-.1-2.4-.4-3.5z" />
    </svg>
  );
}
