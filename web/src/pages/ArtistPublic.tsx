import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { CheckCircle2, ChevronRight, Flag, Hand, HandMetal, Link2, MapPin, Star, Unlink } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates, resolveLink, Studios } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { genreTitle, platformTitle, PLATFORM_COLORS, type ArtistProfile, type ArtistReview, type Studio, type StudioArtistLink } from "../lib/types";
import { AdminBadge, Avatar, ConfirmDialog, Empty, GlowHead, IconTile, Loading, PageHead, Photo, PromotedTag, Stars, Tiles, VerifiedBadge, useToast } from "../components/ui";
import { DisputeRatingSheet, Menu, ReportSheet } from "../components/social";
import { platformIcon } from "./Profile";

/**
 * An artist's public profile: seen by studios (from a chat, booking or studio page) and by the
 * artist themself, who can also dispute ratings and confirm studio connections here.
 */
export default function ArtistPublic() {
  const { id = "" } = useParams();
  const app = useApp();
  const toast = useToast();
  const isOwn = app.account?.id === id;
  const [profile, setProfile] = useState<ArtistProfile | null>(null);
  const [reviews, setReviews] = useState<ArtistReview[]>([]);
  const [links, setLinks] = useState<StudioArtistLink[]>([]);
  const [studios, setStudios] = useState<Record<string, Studio>>({});
  const [disputing, setDisputing] = useState<ArtistReview | null>(null);
  const [disputed, setDisputed] = useState<string[]>([]);
  const [blocked, setBlocked] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState(false);

  const load = useCallback(async () => {
    try {
      if (!isOwn && app.account) api.blockedUsers().then((l) => setBlocked(l.some((b) => b.user_id === id))).catch(() => undefined);
      setProfile(await api.artistProfile(id));
      setReviews(await api.artistReviews(id));
      const list = await api.artistStudioLinks(id);
      setLinks(list);
      const loaded: Record<string, Studio> = {};
      await Promise.all(list.map(async (l) => { loaded[l.studio_id] = await api.studio(l.studio_id).catch(() => undefined as never); }));
      setStudios(loaded);
    } catch (e) { toast(userMessage(e)); }
  }, [id, isOwn, app.account, toast]);
  useEffect(() => { load(); }, [load]);

  async function setBlock(block: boolean) {
    try { if (block) await api.blockUser(id); else await api.unblockUser(id); setBlocked(block); } catch (e) { toast(userMessage(e)); }
  }
  async function respond(link: StudioArtistLink, accept: boolean) {
    try { await api.respondStudioArtistLink(link.studio_id, accept); load(); } catch (e) { toast(userMessage(e)); }
  }

  if (!profile) return <Loading />;
  const accepted = links.filter((l) => l.status === "accepted");
  const pending = links.filter((l) => l.status !== "accepted");

  return (
    <main className="page narrow">
      <PageHead title={profile.artist_name || t("Artist")} translate={false} actions={!isOwn && app.account && (
        <Menu entries={[
          { title: "Report artist", icon: Flag, onClick: () => setShowReport(true) },
          blocked ? { title: "Unblock", icon: HandMetal, onClick: () => setBlock(false) } : { title: "Block artist", icon: Hand, destructive: true, onClick: () => setConfirmBlock(true) },
        ]} />
      )} />
      <div className="stack">
        <ArtistHero profile={profile} />
        <SocialLinks profile={profile} />
        {isOwn && pending.map((link) => (
          <div key={link.studio_id} className="card stack" style={{ gap: 10 }}>
            <div className="row"><IconTile icon={Link2} colors={Tiles.violet} /><div><div className="subhead bold">{t("Connect your studio?")}</div><div className="caption secondary">{format("%@ wants to show your artist profile on its page, and the studio on your profile.", studios[link.studio_id]?.name ?? t("A studio"))}</div></div></div>
            <div className="row" style={{ gap: 10 }}><button className="btn secondary grow" onClick={() => respond(link, false)}>{t("Decline")}</button><button className="btn primary grow" onClick={() => respond(link, true)}>{t("Connect")}</button></div>
          </div>
        ))}
        {accepted.length > 0 && <GlowHead title="Studio" />}
        {accepted.map((link) => {
          const s = studios[link.studio_id];
          if (!s) return null;
          return (
            <div key={s.id} className="card tight row">
              <Link to={`/studios/${s.id}`} className="row grow"><Photo url={s.photo_urls[0]} style={{ width: 54, height: 54, borderRadius: 14 }} /><span className="grow"><div className="headline">{s.name}</div><div className="caption secondary">{Studios.publicArea(s)}</div></span></Link>
              {isOwn && <button onClick={async () => { await api.removeStudioArtistLink(s.id).catch(() => undefined); load(); }} aria-label={t("Remove connection")} className="secondary"><Unlink size={18} /></button>}
              <ChevronRight size={14} className="tertiary" />
            </div>
          );
        })}
        <GlowHead title="Ratings from studios" count={reviews.length} />
        {reviews.length === 0 && <Empty icon={Star} title="No ratings yet" message="Studios can rate artists after a completed session." />}
        {reviews.map((r) => (
          <div key={r.id} className="card stack" style={{ gap: 8, padding: 14 }}>
            <div className="row"><span className="grow subhead bold">{r.studio_name}</span><Stars rating={r.rating} size={13} /></div>
            {r.text && <div className="subhead secondary pre">{r.text}</div>}
            <div className="row">
              <span className="grow caption2 tertiary">{Dates.abbreviated(r.created_at)}</span>
              {isOwn && (disputed.includes(r.id)
                ? <span className="row caption semibold positive" style={{ gap: 4 }}><CheckCircle2 size={13} />{t("Dispute sent")}</span>
                : <button className="row caption semibold accent" style={{ gap: 4 }} onClick={() => setDisputing(r)}><Flag size={13} />{t("Dispute")}</button>)}
            </div>
          </div>
        ))}
      </div>
      <ConfirmDialog open={confirmBlock} onClose={() => setConfirmBlock(false)} translateTitle={false} title={format("Block %@?", profile.artist_name)}
        message={t("Neither of you can send messages in this conversation. You can unblock them any time in Settings → Blocked accounts.")}
        actions={[{ title: "Block", destructive: true, action: () => setBlock(true) }]} />
      <ReportSheet open={showReport} onClose={() => setShowReport(false)} target="user" targetId={id} />
      {disputing && <DisputeRatingSheet open onClose={() => setDisputing(null)} kind="artist_review" reviewId={disputing.id} onSent={() => setDisputed([...disputed, disputing.id])} />}
    </main>
  );
}

export function ArtistHero({ profile, children }: { profile: ArtistProfile; children?: React.ReactNode }) {
  return (
    <div className="card big stack center" style={{ alignItems: "center", gap: 12 }}>
      <div style={{ position: "relative" }}>
        <div style={{ position: "absolute", inset: -10, borderRadius: "50%", background: "var(--neon)", filter: "blur(18px)", opacity: 0.5 }} />
        <span style={{ position: "relative" }}><Avatar url={profile.avatar_url} name={profile.artist_name || "?"} size={104} ring /></span>
        {children}
      </div>
      <div className="row" style={{ gap: 6, justifyContent: "center" }}>
        <span style={{ fontSize: 26, fontWeight: 800, letterSpacing: "-0.02em" }}>{profile.artist_name || t("Artist")}</span>
        {profile.is_verified && <VerifiedBadge />}{profile.has_admin_badge && <AdminBadge />}{profile.promoted_until && new Date(profile.promoted_until) > new Date() && <PromotedTag />}
      </div>
      <div className="row wrap" style={{ gap: 8, justifyContent: "center" }}>
        {profile.city && <span className="chip subhead semibold secondary" style={{ cursor: "default" }}><MapPin size={14} />{profile.city}</span>}
        {(profile.review_count ?? 0) > 0 && <span className="chip" style={{ cursor: "default" }}><Star size={13} fill="var(--accent)" color="var(--accent)" /><b>{(profile.rating_average ?? 0).toFixed(1)}</b><span className="secondary">({profile.review_count})</span></span>}
      </div>
      {profile.genres.length > 0 && <div className="chips" style={{ justifyContent: "center", gap: 6 }}>{profile.genres.map((g) => <span key={g} className="pill" style={{ background: "color-mix(in srgb, var(--violet) 14%, transparent)", color: "var(--violet)", padding: "5px 10px" }}>{t(genreTitle(g))}</span>)}</div>}
      {profile.bio && <div className="subhead secondary pre" style={{ maxWidth: 520 }}>{profile.bio}</div>}
    </div>
  );
}

export function SocialLinks({ profile }: { profile: ArtistProfile }) {
  if (!profile.links.length) return null;
  return (
    <div className="row" style={{ gap: 8, overflowX: "auto", padding: "2px 0" }}>
      {profile.links.map((link) => {
        const url = resolveLink(link);
        if (!url) return null;
        return (
          <a key={link.platform + link.url} href={url} target="_blank" rel="noreferrer" className="chip semibold" style={{ padding: "6px 14px 6px 6px", flexShrink: 0 }}>
            <IconTile icon={platformIcon(link.platform)} size={26} colors={PLATFORM_COLORS[link.platform]} radius={13} />{t(platformTitle(link.platform))}
          </a>
        );
      })}
    </div>
  );
}
