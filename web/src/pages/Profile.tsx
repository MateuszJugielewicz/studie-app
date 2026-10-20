import { useEffect, useRef, useState } from "react";
import { Link, Route, Routes, useNavigate } from "react-router-dom";
import {
  AudioWaveform, Building2, Camera, CalendarDays, Check, ChevronRight, CircleUserRound, FileText, Globe, History, Link2, MapPin, Music2,
  Megaphone, Pencil, PlayCircle, SlidersHorizontal, UserRound, CircleHelp, Instagram, Youtube, Contact, type LucideIcon,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Bookings, greeting } from "../lib/core";
import { compressImage } from "../lib/image";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { GENRES, SOCIAL_PLATFORMS, PLATFORM_COLORS, platformTitle, type ArtistProfile, type Booking, type Genre, type SocialPlatform } from "../lib/types";
import { C, Chip, IconTile, LargeHead, PageHead, PulseDot, Spinner, StatCard, TileLink, Tiles, ToolButton, useToast } from "../components/ui";
import { ArtistHero, SocialLinks } from "./ArtistPublic";
import { ArtistPromotionPage } from "./StudioExtras";
import { VerificationCard } from "./Verification";

const PLATFORM_ICONS: Record<SocialPlatform, LucideIcon> = {
  spotify: Music2, apple_music: Music2, instagram: Instagram, tiktok: PlayCircle, youtube: Youtube, soundcloud: AudioWaveform, website: Globe,
};
export const platformIcon = (p: SocialPlatform) => PLATFORM_ICONS[p] ?? Globe;

export default function Profile({ onboarding }: { onboarding?: boolean }) {
  if (onboarding) return <OnboardingPage />;
  return (
    <Routes>
      <Route index element={<ArtistProfilePage />} />
      <Route path="edit" element={<EditPage />} />
      <Route path="promotion" element={<ArtistPromotionPage />} />
    </Routes>
  );
}

function ArtistProfilePage() {
  const app = useApp();
  const navigate = useNavigate();
  const [bookings, setBookings] = useState<Booking[]>([]);
  const [pendingLinks, setPendingLinks] = useState(0);
  const profile = app.artistProfile;
  useEffect(() => {
    api.artistBookings().then(setBookings).catch(() => undefined);
    const id = app.account!.id;
    api.artistProfile(id).then((p) => p && app.setArtistProfile(p)).catch(() => undefined);
    api.artistStudioLinks(id).then((l) => setPendingLinks(l.filter((x) => x.status !== "accepted").length)).catch(() => undefined);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const completed = bookings.filter((b) => b.status === "completed");

  return (
    <main className="page narrow">
      <LargeHead title="Profile" eyebrow={greeting()} actions={<Link to="/profile/edit" className="icon-btn" aria-label={t("Edit profile")}><Pencil size={17} /></Link>} />
      <div className="stack">
        {profile && (
          <>
            <ArtistHero profile={profile}>
              <button onClick={() => navigate("/profile/edit")} aria-label={t("Change photo")} style={{ position: "absolute", right: 0, bottom: 0, width: 32, height: 32, borderRadius: 16, background: "var(--neon)", color: "#fff", border: "2px solid rgba(255,255,255,0.8)", display: "flex", alignItems: "center", justifyContent: "center" }}><Camera size={14} /></button>
            </ArtistHero>
            <div className="grid-3">
              <StatCard title="Sessions" value={String(completed.length)} icon={AudioWaveform} colors={Tiles.signal} />
              <StatCard title="Upcoming" value={String(bookings.filter(Bookings.isUpcoming).length)} icon={CalendarDays} colors={Tiles.ocean} />
              <StatCard title="Studios" value={String(new Set(completed.map((b) => b.studio_id)).size)} icon={Building2} colors={Tiles.violet} />
            </div>
            <SocialLinks profile={profile} />
            <VerificationCard kind="artist" verified={!!profile.is_verified} />
            {pendingLinks > 0 && (
              <Link to={`/artists/${profile.id}`} className="card row pressable" style={{ padding: 14 }}>
                <IconTile icon={Link2} colors={Tiles.violet} />
                <span className="grow"><div className="subhead bold">{t("A studio wants to connect")}</div><div className="caption secondary">{t("Confirm to show it on your profile")}</div></span>
                <PulseDot color={C.accent} />
              </Link>
            )}
          </>
        )}
        <div className="grid-2">
          {profile && <TileLink to={`/artists/${profile.id}`} title="Public profile" subtitle="Studio & ratings" icon={Contact} colors={Tiles.signal} />}
          {profile && <TileLink to="/profile/promotion" title="Promotion" subtitle={profile.promoted_until && new Date(profile.promoted_until) > new Date() ? "Promoted now" : "Get seen first"} icon={Megaphone} colors={Tiles.blue} />}
          <TileLink to="/sessions/history" title="Sessions" subtitle="History & receipts" icon={History} colors={Tiles.ocean} />
          <TileLink to="/settings" title="Account" subtitle="Notifications & data" icon={CircleUserRound} colors={Tiles.muted} />
          <TileLink to="/settings/app" title="App settings" subtitle="Language, look, storage" icon={SlidersHorizontal} colors={Tiles.violet} />
          <TileLink to="/support" title="Support" subtitle="Talk to EasySesh" icon={CircleHelp} colors={Tiles.warm} />
        </div>
        <Link to="/legal" className="card row pressable" style={{ padding: 12 }}>
          <IconTile icon={FileText} size={32} colors={Tiles.muted} /><span className="grow" style={{ fontWeight: 500 }}>{t("Terms & privacy")}</span><ChevronRight size={14} className="tertiary" />
        </Link>
        <SignOutButton />
      </div>
    </main>
  );
}

export function SignOutButton() {
  const app = useApp();
  return <button className="btn danger block" onClick={() => app.signOut()}>{t("Sign out")}</button>;
}

function EditPage() {
  const app = useApp();
  const navigate = useNavigate();
  if (!app.artistProfile) return null;
  return <ArtistProfileEditor initial={app.artistProfile} onboarding={false} onDone={() => navigate("/profile")} />;
}

/** First-run profile setup after sign-up. */
function OnboardingPage() {
  const app = useApp();
  const navigate = useNavigate();
  const initial: ArtistProfile = app.artistProfile ?? { id: app.account!.id, artist_name: "", genres: [], city: "", bio: "", avatar_url: null, links: [] };
  return <ArtistProfileEditor initial={initial} onboarding onDone={() => navigate("/studios", { replace: true })} />;
}

function ArtistProfileEditor({ initial, onboarding, onDone }: { initial: ArtistProfile; onboarding: boolean; onDone: () => void }) {
  const app = useApp();
  const toast = useToast();
  const [profile, setProfile] = useState(initial);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);
  const canSave = !saving && !!profile.artist_name.trim() && !!profile.city;
  const set = (patch: Partial<ArtistProfile>) => setProfile({ ...profile, ...patch });

  async function upload(file: File) {
    setUploading(true);
    try { const url = await api.uploadImage(await compressImage(file, 800), `avatars/${profile.id}`); setProfile((p) => ({ ...p, avatar_url: url })); } catch (e) { toast(userMessage(e)); }
    setUploading(false);
  }
  async function save() {
    setSaving(true);
    try {
      const saved = await api.saveArtistProfile({ ...profile, genres: GENRES.map(([g]) => g).filter((g) => profile.genres.includes(g)) });
      app.setArtistProfile(saved);
      onDone();
    } catch (e) { toast(userMessage(e)); }
    setSaving(false);
  }
  function setLink(platform: SocialPlatform, value: string) {
    const others = profile.links.filter((l) => l.platform !== platform);
    set({ links: value.trim() ? [...others, { platform, url: value.trim() }] : others });
  }
  const toggleGenre = (g: Genre) => set({ genres: profile.genres.includes(g) ? profile.genres.filter((x) => x !== g) : [...profile.genres, g] });

  return (
    <main className="page narrow">
      <PageHead title={onboarding ? "Welcome" : "Edit profile"}
        leading={onboarding ? <ToolButton title="Sign out" onClick={() => app.signOut()} /> : <ToolButton title="Cancel" onClick={onDone} />}
        actions={<ToolButton title={onboarding ? "Continue" : "Save"} bold disabled={!canSave} onClick={save} />} />
      <div className="stack-lg" style={{ maxWidth: 560, margin: "0 auto" }}>
        {onboarding && (
          <div className="stack" style={{ gap: 6 }}>
            <h1 className="title-l">{t("Set up your artist profile")}</h1>
            <p className="secondary" style={{ margin: 0 }}>{t("Studios see this when you book or message them.")}</p>
          </div>
        )}
        <div className="stack center" style={{ alignItems: "center", gap: 10 }}>
          <button onClick={() => fileInput.current?.click()} aria-label={t("Change photo")} style={{ position: "relative" }}>
            <div style={{ position: "absolute", inset: -10, borderRadius: "50%", background: "var(--neon)", filter: "blur(20px)", opacity: 0.5 }} />
            <span style={{ position: "relative", display: "inline-flex" }}>
              <span className="ring"><span className="avatar" style={{ width: 116, height: 116, fontSize: 40 }}>{profile.avatar_url ? <img src={profile.avatar_url} alt="" /> : (profile.artist_name[0] ?? "?").toUpperCase()}</span></span>
              {uploading && <span style={{ position: "absolute", inset: 4, borderRadius: "50%", background: "rgba(0,0,0,0.45)", display: "flex", alignItems: "center", justifyContent: "center" }}><Spinner /></span>}
            </span>
            <span style={{ position: "absolute", right: 0, bottom: 0, width: 36, height: 36, borderRadius: 18, background: "var(--neon)", color: "#fff", border: "2px solid rgba(255,255,255,0.85)", display: "flex", alignItems: "center", justifyContent: "center" }}><Camera size={15} /></span>
          </button>
          <input ref={fileInput} type="file" accept="image/*" hidden onChange={(e) => { const f = e.target.files?.[0]; if (f) upload(f); e.target.value = ""; }} />
          <div className="headline" style={{ color: profile.artist_name ? undefined : "var(--text-2)" }}>{profile.artist_name || t("Add a photo")}</div>
        </div>

        <EditorSection title="About you">
          <label className="field"><UserRound size={18} /><input placeholder={t("Artist name")} autoComplete="nickname" value={profile.artist_name} onChange={(e) => set({ artist_name: e.target.value })} /></label>
          <label className="field"><MapPin size={18} /><input placeholder={t("City")} autoComplete="address-level2" value={profile.city} onChange={(e) => set({ city: e.target.value })} /></label>
          <label className="field area" style={{ flexDirection: "column", alignItems: "stretch" }}>
            <textarea rows={4} placeholder={t("Short bio")} value={profile.bio} onChange={(e) => set({ bio: e.target.value })} />
            <span className="caption2 semibold" style={{ textAlign: "right", color: profile.bio.length > 300 ? "var(--warning)" : "var(--text-2)" }}>{profile.bio.length}/300</span>
          </label>
        </EditorSection>

        <EditorSection title="Genres" trailing={profile.genres.length ? format("%lld selected", profile.genres.length) : undefined}>
          <div className="chips">{GENRES.map(([g, title]) => <Chip key={g} title={title} on={profile.genres.includes(g)} icon={profile.genres.includes(g) ? Check : undefined} onClick={() => toggleGenre(g)} />)}</div>
        </EditorSection>

        <EditorSection title="Links" footer="Paste profile links, e.g. https://open.spotify.com/artist/…">
          {SOCIAL_PLATFORMS.map(([p]) => (
            <div key={p} className="row">
              <IconTile icon={platformIcon(p)} colors={PLATFORM_COLORS[p]} />
              <label className="field grow"><Link2 size={18} /><input type="url" placeholder={t(platformTitle(p))} value={profile.links.find((l) => l.platform === p)?.url ?? ""} onChange={(e) => setLink(p, e.target.value)} autoCapitalize="none" /></label>
            </div>
          ))}
        </EditorSection>

        <button className="btn primary block" disabled={!canSave} onClick={save}>{saving ? <Spinner /> : t(onboarding ? "Continue" : "Save")}</button>
      </div>
    </main>
  );
}

function EditorSection({ title, trailing, footer, children }: { title: string; trailing?: string; footer?: string; children: React.ReactNode }) {
  return (
    <div className="stack" style={{ gap: 10 }}>
      <div className="row spread"><span className="eyebrow">{t(title)}</span>{trailing && <span className="caption bold accent">{trailing}</span>}</div>
      {children}
      {footer && <div className="caption secondary">{t(footer)}</div>}
    </div>
  );
}
