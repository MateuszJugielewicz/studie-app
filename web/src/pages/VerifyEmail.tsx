// "Confirm your email": the banner for unverified accounts and the page the emailed link opens.
// Unverified users can look around; the server blocks booking, messaging, reviews and studio approval.
import { useEffect, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { CircleCheck, CircleX, MailCheck } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { Empty, Loading, useToast } from "../components/ui";

export function VerifyEmailBanner() {
  const app = useApp();
  const toast = useToast();
  const [sending, setSending] = useState(false);
  const account = app.account;
  const unverified = !!account && account.role !== "admin" && !account.email_verified_at;

  // Pick up a confirmation made in another tab or on another device.
  useEffect(() => {
    if (!unverified) return;
    const check = () => {
      if (document.visibilityState !== "visible") return;
      api.currentAccount().then((next) => { if (next?.email_verified_at) app.setAccount(next); }).catch(() => undefined);
    };
    document.addEventListener("visibilitychange", check);
    return () => document.removeEventListener("visibilitychange", check);
  }, [unverified, app]);

  if (!unverified) return null;
  const resend = async () => {
    setSending(true);
    try {
      await api.resendVerificationEmail();
      toast(t("Email sent. Check your inbox."), "info");
    } catch (error) {
      toast(userMessage(error));
    } finally {
      setSending(false);
    }
  };
  return (
    <div className="verify-banner" role="status">
      <MailCheck size={18} style={{ flexShrink: 0 }} />
      <span>
        {t(account.role === "studio_owner" ? "Verify your email to send your studio for approval and message artists." : "Verify your email to book sessions and send messages.")}{" "}
        {t("We sent a link to your email.")}
      </span>
      <button className="btn secondary small" onClick={resend} disabled={sending}>{t("Resend email")}</button>
    </div>
  );
}

export default function VerifyEmail() {
  const app = useApp();
  const [params] = useSearchParams();
  const [state, setState] = useState<"working" | "done" | "failed">("working");
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    api.verifyEmail(params.get("token") ?? "")
      .then(async (ok) => {
        setState(ok ? "done" : "failed");
        if (!ok) return;
        // Hide the banner straight away, then load the updated account.
        if (app.account) app.setAccount({ ...app.account, email_verified_at: app.account.email_verified_at ?? new Date().toISOString() });
        const next = await api.currentAccount().catch(() => null);
        if (next?.email_verified_at) app.setAccount(next);
      })
      .catch(() => setState("failed"));
  }, [params, app]);

  if (state === "working") return <main className="page"><Loading /><p className="center subhead">{t("Confirming your email…")}</p></main>;
  const home = app.account?.role === "studio_owner" ? "/studio" : "/studios";
  return (
    <main className="page">
      {state === "done" ? (
        <Empty icon={CircleCheck} title="Email confirmed" message="Thanks! You can now book sessions and send messages.">
          <Link to={app.account ? home : "/signin"} className="btn primary">{t(app.account ? "Continue" : "Sign in")}</Link>
        </Empty>
      ) : (
        <Empty icon={CircleX} title="Something went wrong. Please try again." message="This link has expired or was already used. Sign in to get a new one.">
          <Link to={app.account ? home : "/signin"} className="btn primary">{t(app.account ? "Continue" : "Sign in")}</Link>
        </Empty>
      )}
    </main>
  );
}
