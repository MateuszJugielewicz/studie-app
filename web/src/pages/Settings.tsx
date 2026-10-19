import { useEffect, useState } from "react";
import { Route, Routes, useNavigate } from "react-router-dom";
import { ShieldAlert } from "lucide-react";
import AccountHistory from "./AccountHistory";
import {
  AlarmClock, BadgeCheck, Bell, BellRing, CalendarDays, Contrast, FileText, Globe, Hand, KeyRound, LogOut, Mail, MailOpen, Megaphone, MessagesSquare,
  MapPin, Ruler, ScanSearch, ShieldCheck, Sparkles, SlidersHorizontal, Star, Trash2, CheckCircle2,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates, passwordProblem } from "../lib/core";
import { format, LANGUAGES, t } from "../lib/i18n";
import { useLocation } from "../lib/location";
import { useApp } from "../lib/state";
import { DEFAULT_SETTINGS, ROLE_TITLE, type BlockedUser, type UserSettings } from "../lib/types";
import {
  Avatar, C, ConfirmDialog, Empty, IconTile, Item, ItemLabel, Loading, NavItem, PageHead, Section, SelectItem, Spinner, Tiles, ToggleItem, useToast,
} from "../components/ui";
import { DataExportItem } from "./Legal";
import { ChangelogCard } from "./Gates";
import packageInfo from "../../package.json";

export default function Settings() {
  return (
    <Routes>
      <Route index element={<AccountSettings />} />
      <Route path="app" element={<AppSettings />} />
      <Route path="password" element={<main className="page narrow"><PageHead title="Change password" /><ChangePasswordForm /></main>} />
      <Route path="blocked" element={<BlockedAccounts />} />
      <Route path="whats-new" element={<WhatsNewPage />} />
      <Route path="history" element={<AccountHistory />} />
    </Routes>
  );
}

function AccountSettings() {
  const app = useApp();
  const toast = useToast();
  const location = useLocation();
  const account = app.account!;
  const [settings, setSettings] = useState<UserSettings>({ ...DEFAULT_SETTINGS, ...account.settings });
  const [confirmDelete, setConfirmDelete] = useState(false);
  const isArtist = account.role === "artist";
  const name = app.artistProfile?.artist_name || app.ownedStudio?.name || account.email;

  async function update(next: UserSettings) {
    setSettings(next);
    try { app.setAccount(await api.updateSettings(next)); } catch (e) { toast(userMessage(e)); }
  }
  const toggle = (key: keyof UserSettings) => (v: boolean) => update({ ...settings, [key]: v });

  return (
    <main className="page narrow">
      <PageHead title="Settings" />
      <div className="stack-lg">
        <Section>
          <Item>
            <Avatar url={app.artistProfile?.avatar_url ?? app.ownedStudio?.photo_urls[0]} name={name} size={56} ring />
            <div className="label">
              <div className="headline clamp-1">{name}</div>
              <div className="subhead secondary clamp-1">{account.email}</div>
              <span className="pill" style={{ marginTop: 3, background: "color-mix(in srgb, var(--violet) 15%, transparent)", color: "var(--violet)" }}>{t(ROLE_TITLE[account.role])}</span>
            </div>
          </Item>
        </Section>
        <Section footer="Language, appearance, effects and storage on this device.">
          <NavItem to="/settings/app" title="App settings" icon={SlidersHorizontal} colors={Tiles.ocean} />
          <NavItem to="/settings/password" title="Change password" icon={KeyRound} colors={Tiles.signal} />
        </Section>
        <Section header="Notifications">
          <ToggleItem title="Push notifications" checked={settings.push_enabled} onChange={toggle("push_enabled")} icon={BellRing} colors={Tiles.signal} />
          <ToggleItem title="Email notifications" checked={settings.email_enabled} onChange={toggle("email_enabled")} icon={Mail} colors={Tiles.violet} />
        </Section>
        <Section header="Notify me about" footer="Payment receipts and security messages are always sent.">
          <ToggleItem title="Booking updates" checked={settings.booking_updates} onChange={toggle("booking_updates")} icon={CalendarDays} colors={Tiles.ocean} />
          <ToggleItem title="Messages" checked={settings.messages} onChange={toggle("messages")} icon={MessagesSquare} colors={Tiles.mint} />
          {isArtist && <ToggleItem title="Session reminders" checked={settings.reminders} onChange={toggle("reminders")} icon={AlarmClock} colors={Tiles.warm} />}
          {isArtist && <ToggleItem title="Review prompts" checked={settings.review_prompts} onChange={toggle("review_prompts")} icon={Star} colors={Tiles.violet} />}
          <ToggleItem title="News & offers" checked={settings.marketing} onChange={toggle("marketing")} icon={Megaphone} colors={Tiles.muted} />
        </Section>
        {isArtist && (
          <Section header="Search">
            <Item>
              <div className="stack" style={{ width: "100%", gap: 8 }}>
                <div className="row"><IconTile icon={ScanSearch} size={30} colors={Tiles.ocean} radius={8} /><span className="grow">{t("Default radius")}</span><span className="subhead bold">{Math.round(settings.search_radius_km)} km</span></div>
                <input type="range" min={1} max={50} step={1} value={settings.search_radius_km} style={{ width: "100%", accentColor: "var(--accent)" }}
                  onChange={(e) => setSettings({ ...settings, search_radius_km: Number(e.target.value) })} onMouseUp={() => update(settings)} onTouchEnd={() => update(settings)} onKeyUp={() => update(settings)} />
              </div>
            </Item>
            <ToggleItem title="Use kilometres" checked={settings.use_metric_units} onChange={toggle("use_metric_units")} icon={Ruler} colors={Tiles.muted} />
            <Item onClick={location.point ? undefined : location.request}><ItemLabel title={location.point ? "Location allowed" : "Allow location access"} icon={MapPin} colors={Tiles.mint} /></Item>
          </Section>
        )}
        <Section header="Legal">
          <NavItem to="/legal" title="Terms, privacy & policies" icon={FileText} colors={Tiles.muted} />
          <NavItem to="/settings/blocked" title="Blocked accounts" icon={Hand} colors={Tiles.danger} />
          <NavItem to="/settings/history" title="Warnings & account history" icon={ShieldAlert} colors={[C.warning, C.accent]} />
          {account.accepted_terms_at && <Item><ItemLabel title="Terms accepted" icon={BadgeCheck} colors={Tiles.mint} /><span className="value">{Dates.abbreviated(account.accepted_terms_at)}</span></Item>}
        </Section>
        <Section header="Your data" footer="Download a copy of everything EasySesh stores about you (GDPR). Deleting your account removes your profile; receipts are kept as required by accounting law.">
          <DataExportItem />
          <NavItem to="/support" title="Contact us about your data" icon={MailOpen} colors={Tiles.violet} />
        </Section>
        <Section>
          <Item onClick={() => app.signOut()}><ItemLabel title="Sign out" icon={LogOut} colors={Tiles.muted} /></Item>
          <Item onClick={() => setConfirmDelete(true)}><ItemLabel title="Delete account" icon={Trash2} colors={Tiles.danger} color="var(--red)" /></Item>
        </Section>
      </div>
      <ConfirmDialog open={confirmDelete} onClose={() => setConfirmDelete(false)} title="Delete your account?"
        message={t("Your profile, messages and upcoming bookings will be removed. Receipts are kept for accounting as required by law.")}
        actions={[{ title: "Delete account", destructive: true, action: async () => { try { await api.deleteAccount(); await app.signOut(); } catch (e) { toast(userMessage(e)); } } }]} />
    </main>
  );
}

/** Device settings: language, look and effects (iOS AppSettingsView). */
function AppSettings() {
  const app = useApp();
  return (
    <main className="page narrow">
      <PageHead title="App settings" />
      <div className="stack-lg">
        <Section>
          <SelectItem title="Language" icon={Globe} colors={Tiles.ocean} value={app.language} translateOptions={false}
            options={LANGUAGES.map((l) => [l.code, `${l.flag} ${l.name}`] as [string, string])} onChange={(code) => app.changeLanguage(code)} />
        </Section>
        <Section header="Look & feel" footer="Reduce visual effects turns off moving backgrounds and pulsing animations. It can also save battery.">
          <SelectItem title="Appearance" icon={Contrast} colors={Tiles.violet} value={app.appearance} options={[["system", "Automatic"], ["light", "Light"], ["dark", "Dark"]]} onChange={app.setAppearance} />
          <ToggleItem title="Reduce visual effects" checked={app.reduceEffects} onChange={app.setReduceEffects} icon={Sparkles} colors={Tiles.signal} />
        </Section>
        <Section header="About">
          <Item><span className="label">{t("Version")}</span><span className="value">{packageInfo.version} (web)</span></Item>
          <NavItem to="/settings/whats-new" title="What's new" />
          <NavItem to="/legal" title="Terms, privacy & policies" />
        </Section>
      </div>
    </main>
  );
}

function WhatsNewPage() {
  const app = useApp();
  useEffect(() => { app.refreshUpdates(); }, []); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <main className="page narrow">
      <PageHead title="What's new" />
      <div className="stack">
        {app.changelog.length === 0 ? <Empty icon={Sparkles} title="No updates yet" message="Update notes from the EasySesh team show up here." /> : app.changelog.map((e) => <ChangelogCard key={e.id} entry={e} />)}
      </div>
    </main>
  );
}

/** Choose a new password: from Settings, or after opening a password-reset link. */
export function ChangePasswordForm({ isRecovery, onDone }: { isRecovery?: boolean; onDone?: () => void }) {
  const toast = useToast();
  const navigate = useNavigate();
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const problem = !password ? null : passwordProblem(password) ?? (confirmation && confirmation !== password ? t("The passwords don't match.") : null);
  const canSave = !saving && !passwordProblem(password) && password === confirmation;
  async function save() {
    setSaving(true);
    try {
      await api.changePassword(password);
      setSaved(true);
      window.setTimeout(() => (onDone ? onDone() : navigate(-1)), 1000);
    } catch (e) { toast(userMessage(e)); }
    setSaving(false);
  }
  return (
    <div className="stack-lg">
      <Section>
        <Item>
          <IconTile icon={saved ? ShieldCheck : KeyRound} size={44} colors={saved ? Tiles.mint : Tiles.signal} />
          <span className="label subhead secondary">{t(isRecovery ? "Choose a new password for your account." : "Use at least 10 characters with upper- and lowercase letters and a number.")}</span>
        </Item>
      </Section>
      <Section footer={problem ?? undefined} footerColor="var(--warning)" translate={false}>
        <Item><input type="password" autoComplete="new-password" placeholder={t("New password")} value={password} onChange={(e) => setPassword(e.target.value)} /></Item>
        <Item><input type="password" autoComplete="new-password" placeholder={t("Repeat new password")} value={confirmation} onChange={(e) => setConfirmation(e.target.value)} /></Item>
      </Section>
      <button className="btn primary block" disabled={!canSave || saved} onClick={save}>
        {saving ? <Spinner /> : saved ? <><CheckCircle2 size={18} />{t("Password changed")}</> : t("Save new password")}
      </button>
    </div>
  );
}

/** People and studios you've blocked; unblocking lets you message each other again. */
function BlockedAccounts() {
  const toast = useToast();
  const [blocked, setBlocked] = useState<BlockedUser[] | null>(null);
  useEffect(() => { api.blockedUsers().then(setBlocked).catch((e) => { toast(userMessage(e)); setBlocked([]); }); }, [toast]);
  async function unblock(u: BlockedUser) {
    try { await api.unblockUser(u.user_id); setBlocked((l) => (l ?? []).filter((x) => x.user_id !== u.user_id)); } catch (e) { toast(userMessage(e)); }
  }
  return (
    <main className="page narrow">
      <PageHead title="Blocked accounts" />
      {blocked == null ? <Loading /> : (
        <Section>
          {blocked.length === 0 && <Item><span className="secondary">{t("You haven't blocked anyone.")}</span></Item>}
          {blocked.map((u) => (
            <Item key={u.user_id}>
              <Avatar url={u.avatar_url} name={u.display_name} size={36} />
              <div className="label"><div className="subhead semibold">{u.display_name}</div><div className="caption secondary">{format("Blocked %@", Dates.abbreviated(u.blocked_at))}</div></div>
              <button className="link-btn" onClick={() => unblock(u)}>{t("Unblock")}</button>
            </Item>
          ))}
        </Section>
      )}
    </main>
  );
}

export const SettingsIcon = Bell;
