// App-wide state, the same as the apps' AppState: the signed-in account, their artist profile or
// studio, badges, update notes, warnings and device preferences.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { api } from "./api";
import { TERMS_VERSION } from "./config";
import { onLanguageChange, setLanguage, storedLanguage } from "./i18n";
import type { AppNotification, ArtistProfile, ChangelogEntry, ModerationWarning, Studio, UserAccount } from "./types";

export type Appearance = "system" | "light" | "dark";

function read<T>(key: string, fallback: T): T {
  try { const v = localStorage.getItem(key); return v == null ? fallback : (JSON.parse(v) as T); } catch { return fallback; }
}
function write(key: string, value: unknown) { try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* ignore */ } }

/** Terms versions are dates ("2026-09-25", optionally with a suffix), so they compare as text. */
const newest = (a: string, b?: string | null) => (b && b > a ? b : a);

export interface AppState {
  ready: boolean;
  account: UserAccount | null;
  artistProfile: ArtistProfile | null;
  ownedStudio: Studio | null;
  notifications: AppNotification[];
  unreadMessages: number;
  unreadNotifications: number;
  warnings: ModerationWarning[];
  changelog: ChangelogEntry[];
  unseenChangelog: ChangelogEntry[];
  needsTermsAcceptance: boolean;
  requiredTermsVersion: string;
  pendingLegalUpdate: ChangelogEntry | null;
  needsNewPassword: boolean;
  appearance: Appearance;
  reduceEffects: boolean;
  language: string;
  setAccount(account: UserAccount | null): void;
  setArtistProfile(profile: ArtistProfile | null): void;
  setOwnedStudio(studio: Studio | null): void;
  setNeedsNewPassword(value: boolean): void;
  didAuthenticate(account: UserAccount): Promise<void>;
  signOut(): Promise<void>;
  refreshBadges(): Promise<void>;
  refreshUpdates(): Promise<void>;
  setNotifications(list: AppNotification[]): void;
  acknowledgeWarning(w: ModerationWarning): Promise<void>;
  markChangelogSeen(): void;
  setAppearance(a: Appearance): void;
  setReduceEffects(v: boolean): void;
  changeLanguage(code: string): Promise<void>;
}

const Context = createContext<AppState | null>(null);

/** An admin with a filled-in artist profile is shown the artist side of the website. */
function asArtistIfAdmin(account: UserAccount | null, profile: ArtistProfile | null): UserAccount | null {
  if (account?.role !== "admin" || !profile?.artist_name.trim()) return account;
  return { ...account, role: "artist", is_admin: true };
}

export function AppStateProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [account, setAccount] = useState<UserAccount | null>(null);
  const [artistProfile, setArtistProfile] = useState<ArtistProfile | null>(null);
  const [ownedStudio, setOwnedStudio] = useState<Studio | null>(null);
  const [notifications, setNotifications] = useState<AppNotification[]>([]);
  const [unreadMessages, setUnreadMessages] = useState(0);
  const [warnings, setWarnings] = useState<ModerationWarning[]>([]);
  const [changelog, setChangelog] = useState<ChangelogEntry[]>([]);
  const [changelogSeenAt, setChangelogSeenAt] = useState<string | null>(null);
  const [requiredTermsVersion, setRequiredTermsVersion] = useState(TERMS_VERSION);
  const [needsNewPassword, setNeedsNewPassword] = useState(false);
  const [appearance, setAppearanceState] = useState<Appearance>(() => read("easysesh.appearance", "system"));
  const [reduceEffects, setReduceEffectsState] = useState<boolean>(() => read("easysesh.reduceEffects", false));
  const [language, setLanguageState] = useState(storedLanguage());
  // A team member (admin) with an artist profile uses the website as an artist (the database allows it too);
  // the admin dashboard stays at admin.easysesh.live.
  const effectiveAccount = useMemo(() => asArtistIfAdmin(account, artistProfile), [account, artistProfile]);
  const accountRef = useRef<UserAccount | null>(null);
  accountRef.current = effectiveAccount;

  const refreshUpdates = useCallback(async () => {
    const current = accountRef.current;
    if (!current) return;
    if (current.role !== "admin") api.unacknowledgedWarnings().then(setWarnings).catch(() => undefined);
    setChangelogSeenAt(read<string | null>(`easysesh.changelog.seen.${current.id}`, null));
    api.currentTermsVersion().then((v) => setRequiredTermsVersion(newest(TERMS_VERSION, v))).catch(() => undefined);
    api.changelog().then((list) => setChangelog(list.filter((e) => e.audience === "all" || e.audience === current.role))).catch(() => undefined);
  }, []);

  const refreshBadges = useCallback(async () => {
    const current = accountRef.current;
    if (!current) return;
    const [notes, conversations] = await Promise.all([api.notifications().catch(() => null), api.conversations().catch(() => null)]);
    if (notes) setNotifications(notes);
    if (conversations) {
      setUnreadMessages(conversations.reduce((n, c) => {
        // Message requests and declined threads don't count towards the badge for artists.
        if (current.role === "artist" && (c.request_status ?? "accepted") !== "accepted") return n;
        return n + (current.role === "artist" ? c.artist_unread : c.studio_unread);
      }, 0));
    }
  }, []);

  const didAuthenticate = useCallback(async (next: UserAccount) => {
    accountRef.current = next;
    if (next.role === "artist" || next.role === "admin") {
      const profile = await api.artistProfile(next.id).catch(() => null);
      setArtistProfile(profile);
      accountRef.current = asArtistIfAdmin(next, profile);
    }
    if (next.role === "studio_owner") setOwnedStudio(await api.ownedStudio().catch(() => null));
    setAccount(next);
    await Promise.all([refreshUpdates(), refreshBadges()]);
  }, [refreshBadges, refreshUpdates]);

  const signOut = useCallback(async () => {
    await api.signOut();
    accountRef.current = null;
    setAccount(null); setArtistProfile(null); setOwnedStudio(null); setNotifications([]); setUnreadMessages(0); setWarnings([]); setChangelog([]);
  }, []);

  // Restore the session on load, and follow sign-in / password-recovery events from email links.
  useEffect(() => {
    setLanguage(storedLanguage(), false).finally(async () => {
      const restored = await api.restoreSession().catch(() => null);
      if (restored) await didAuthenticate(restored);
      setReady(true);
    });
    const { data } = api.client.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") setNeedsNewPassword(true);
    });
    const off = onLanguageChange(() => setLanguageState(document.documentElement.lang));
    return () => { data.subscription.unsubscribe(); off(); };
  }, [didAuthenticate]);

  // Live badges, plus a refresh when the tab becomes visible again.
  useEffect(() => {
    if (!account) return;
    const stop = api.subscribeNotifications(account.id, () => { refreshBadges(); });
    const onVisible = () => { if (document.visibilityState === "visible") { refreshBadges(); refreshUpdates(); } };
    document.addEventListener("visibilitychange", onVisible);
    const timer = window.setInterval(refreshBadges, 60_000);
    return () => { stop(); document.removeEventListener("visibilitychange", onVisible); window.clearInterval(timer); };
  }, [account, refreshBadges, refreshUpdates]);

  // Theme on <html>.
  useEffect(() => {
    const root = document.documentElement;
    if (appearance === "system") root.removeAttribute("data-theme"); else root.setAttribute("data-theme", appearance);
    root.toggleAttribute("data-reduce-effects", reduceEffects);
  }, [appearance, reduceEffects]);

  const value = useMemo<AppState>(() => {
    const account = effectiveAccount;
    const unseen = account ? changelog.filter((e) => new Date(e.published_at) > new Date(changelogSeenAt ?? account.created_at)) : [];
    return {
      ready, account: effectiveAccount, artistProfile, ownedStudio, notifications, unreadMessages,
      unreadNotifications: notifications.filter((n) => !n.is_read).length,
      warnings, changelog, unseenChangelog: unseen, requiredTermsVersion,
      needsTermsAcceptance: !!account && account.role !== "admin" && (account.accepted_terms_version ?? "") < requiredTermsVersion,
      pendingLegalUpdate: changelog.find((e) => e.is_legal_update && e.version > (account?.accepted_terms_version ?? "")) ?? null,
      needsNewPassword, appearance, reduceEffects, language,
      setAccount, setArtistProfile, setOwnedStudio, setNeedsNewPassword, didAuthenticate, signOut, refreshBadges, refreshUpdates, setNotifications,
      async acknowledgeWarning(w) { await api.acknowledgeWarning(w.id).catch(() => undefined); setWarnings((list) => list.filter((x) => x.id !== w.id)); },
      markChangelogSeen() {
        if (!account || !changelog[0]) return;
        write(`easysesh.changelog.seen.${account.id}`, changelog[0].published_at);
        setChangelogSeenAt(changelog[0].published_at);
      },
      setAppearance(a) { setAppearanceState(a); write("easysesh.appearance", a); },
      setReduceEffects(v) { setReduceEffectsState(v); write("easysesh.reduceEffects", v); },
      changeLanguage: (code) => setLanguage(code),
    };
  }, [ready, effectiveAccount, artistProfile, ownedStudio, notifications, unreadMessages, warnings, changelog, changelogSeenAt, requiredTermsVersion,
    needsNewPassword, appearance, reduceEffects, language, didAuthenticate, signOut, refreshBadges, refreshUpdates]);

  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useApp(): AppState {
  const value = useContext(Context);
  if (!value) throw new Error("AppStateProvider missing");
  return value;
}

/** Loads data for a page; `reload` runs it again. Errors go to `error`. */
export function useLoad<T>(load: () => Promise<T>, deps: unknown[]): { data: T | undefined; loading: boolean; error: string | null; reload: () => Promise<void>; setData: (v: T) => void } {
  const [data, setData] = useState<T>();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const run = useCallback(async () => {
    try { setData(await load()); setError(null); } catch (e) { const { userMessage } = await import("./api"); setError(userMessage(e)); }
    setLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(() => { run(); }, [run]);
  return { data, loading, error, reload: run, setData };
}
