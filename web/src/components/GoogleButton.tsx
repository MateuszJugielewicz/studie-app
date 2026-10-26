// "Sign in with Google" rendered by Google itself (Google Identity Services). Google's window then says
// easysesh.live instead of the Supabase address the redirect flow shows. If Google's script can't load
// (blocked, offline), the caller's fallback button is shown instead.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { config } from "../lib/config";
import { language } from "../lib/i18n";

interface GoogleId {
  initialize(options: { client_id: string; nonce: string; callback: (r: { credential: string }) => void; use_fedcm_for_prompt?: boolean; ux_mode?: "popup" }): void;
  renderButton(parent: HTMLElement, options: Record<string, string | number>): void;
}
declare global { interface Window { google?: { accounts: { id: GoogleId } } } }

let script: Promise<GoogleId> | null = null;
function loadGoogle(): Promise<GoogleId> {
  script ??= new Promise((resolve, reject) => {
    if (window.google?.accounts?.id) return resolve(window.google.accounts.id);
    const tag = document.createElement("script");
    tag.src = "https://accounts.google.com/gsi/client";
    tag.async = true;
    tag.onload = () => (window.google?.accounts?.id ? resolve(window.google.accounts.id) : reject(new Error("Google sign-in unavailable")));
    tag.onerror = () => { script = null; reject(new Error("Google sign-in unavailable")); };
    document.head.appendChild(tag);
  });
  return script;
}

async function sha256Hex(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

export function GoogleButton({ signUp, onCredential, fallback }: {
  signUp: boolean; onCredential: (idToken: string, rawNonce: string) => void; fallback: ReactNode;
}) {
  const host = useRef<HTMLDivElement>(null);
  const [failed, setFailed] = useState(false);
  const callback = useRef(onCredential);
  callback.current = onCredential;

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const google = await loadGoogle();
        // A fresh nonce per button: Google signs the hash into the ID token, Supabase checks the raw value.
        const raw = Array.from(crypto.getRandomValues(new Uint8Array(16)), (b) => b.toString(16).padStart(2, "0")).join("");
        const hashed = await sha256Hex(raw);
        if (cancelled || !host.current) return;
        google.initialize({ client_id: config.googleClientId, nonce: hashed, ux_mode: "popup", use_fedcm_for_prompt: true, callback: (r) => callback.current(r.credential, raw) });
        const dark = document.documentElement.dataset.theme === "dark" || (!document.documentElement.dataset.theme && window.matchMedia("(prefers-color-scheme: dark)").matches);
        host.current.innerHTML = "";
        google.renderButton(host.current, {
          type: "standard", theme: dark ? "filled_black" : "outline", size: "large", shape: "rectangular",
          text: signUp ? "signup_with" : "continue_with", logo_alignment: "center",
          width: Math.min(400, Math.max(200, Math.round(host.current.getBoundingClientRect().width))), locale: language(),
        });
      } catch {
        if (!cancelled) setFailed(true);
      }
    })();
    return () => { cancelled = true; };
  }, [signUp]);

  if (failed) return <>{fallback}</>;
  return <div ref={host} style={{ display: "flex", justifyContent: "center", minHeight: 44, colorScheme: "light" }} />;
}
