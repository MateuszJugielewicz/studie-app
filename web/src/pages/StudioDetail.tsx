import { useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import {
  CalendarDays, ChevronLeft, ChevronRight, CircleCheck, CreditCard, Flag, Globe, Hand, HandMetal, Map as MapIcon, MapPin, MessageCircle,
  Navigation, PlayCircle, UserRound, Users, Zap,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import {
  availableSlots, Dates, distanceMeters, formatDistance, hoursLabel, Money, OPENING_DISPLAY_ORDER, resolveLink, Studios, studioZone,
  addDays, startOfDay, weekdayName, type TimeSlot,
} from "../lib/core";
import { format, t } from "../lib/i18n";
import { useLocation, directionsUrl, mapsUrl } from "../lib/location";
import { useApp } from "../lib/state";
import { CANCELLATION, EQUIPMENT_CATEGORIES, PRICE_UNITS, genreTitle, facilityTitle, type ArtistProfile, type Review, type Studio } from "../lib/types";
import {
  AdminBadge, Avatar, Chip, ConfirmDialog, GlowHead, Loading, Photo, PromotedTag, RatingLabel, SpecialTag, VerifiedBadge, useToast,
} from "../components/ui";
import { ReportSheet, ReviewRow, ReviewSummary } from "../components/social";
import { StudioMap } from "../components/StudioMap";
import { facilityIcon } from "../components/icons";


export default function StudioDetail() {
  const { id = "" } = useParams();
  const app = useApp();
  const toast = useToast();
  const navigate = useNavigate();
  const location = useLocation();
  const [studio, setStudio] = useState<Studio | null>(null);
  const [reviews, setReviews] = useState<Review[]>([]);
  const [slots, setSlots] = useState<TimeSlot[]>([]);
  const [linkedArtist, setLinkedArtist] = useState<ArtistProfile | null>(null);
  const [blocked, setBlocked] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [confirmBlock, setConfirmBlock] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const loaded = await api.studio(id);
        setStudio(loaded);
        const me = app.account?.id;
        if (me && loaded.owner_id !== me) api.blockedUsers().then((list) => setBlocked(list.some((b) => b.user_id === loaded.owner_id))).catch(() => undefined);
        api.studioArtistLink(id).then(async (link) => { if (link?.status === "accepted") setLinkedArtist(await api.artistProfile(link.artist_id)); }).catch(() => undefined);
        setReviews(await api.reviews(id));
        // Next free times over the coming week (2 per day, like the apps).
        const start = startOfDay(new Date());
        const busy = (await api.busyIntervals([id], start, addDays(start, 8)).catch(() => ({} as Record<string, never[]>)))[id] ?? [];
        const hours = Math.min(...loaded.session_types.map((s) => s.minimum_hours), 24) || 1;
        const found: TimeSlot[] = [];
        for (let i = 0; i < 7; i++) found.push(...availableSlots(loaded, addDays(start, i), hours, busy).slice(0, 2));
        setSlots(found);
      } catch (e) { setError(userMessage(e)); }
    })();
  }, [id, app.account?.id]);

  if (error) return <main className="page narrow"><div className="card empty" style={{ marginTop: 40 }}>{error}</div></main>;
  if (!studio) return <Loading />;

  const zone = studioZone(studio);
  const isArtist = app.account?.role === "artist";
  const isOwner = app.account?.id === studio.owner_id;
  const book = () => (app.account ? navigate(`/book/${studio.id}`) : navigate(`/signup?next=${encodeURIComponent(`/book/${studio.id}`)}`));
  async function message() {
    try { const c = await api.conversation(studio!.id, null); navigate(`/messages/${c.id}`); } catch (e) { toast(userMessage(e)); }
  }
  async function setBlock(block: boolean) {
    try { if (block) await api.blockStudio(studio!.id); else await api.unblockUser(studio!.owner_id); setBlocked(block); } catch (e) { toast(userMessage(e)); }
  }
  const video = studio.video_url ? resolveLink({ platform: "youtube", url: studio.video_url }) : null;
  const website = resolveLink({ platform: "website", url: studio.contact.website });

  const bookingCard = (
    <div className="card big stack" style={{ gap: 12 }}>
      <div>
        <div className="title-m">{format("From %@/h", Money.format(studio.price_from, studio.currency))}</div>
        <div className="caption secondary">{t(studio.booking_policy.instant_book ? "Instant confirmation" : "Studio confirms within 24h")}</div>
      </div>
      {!app.account ? (
        <button className="btn primary block" onClick={book}>{t("Sign up to book")}</button>
      ) : isArtist ? (
        <div className="row"><button className="icon-btn" style={{ width: 52, height: 52 }} onClick={message} aria-label={t("Message")}><MessageCircle size={20} /></button><button className="btn primary grow" onClick={book}>{t("Book")}</button></div>
      ) : isOwner ? <Link to="/studio/listing" className="btn secondary block">{t("Edit profile")}</Link> : null}
    </div>
  );

  return (
    <main className="page wide with-cta" style={{ paddingTop: 0 }}>
      <div className="bleed" style={{ position: "relative" }}>
        <Gallery urls={studio.photo_urls} />
        <button className="icon-btn" style={{ position: "absolute", top: 14, left: "calc(var(--gutter) + 6px)", zIndex: 2 }} onClick={() => (window.history.length > 1 ? navigate(-1) : navigate("/studios"))} aria-label={t("Back")}><ChevronLeft size={22} /></button>
      </div>
      <div className="two-col" style={{ marginTop: 24 }}>
        <div className="stack-lg">
          <div className="stack" style={{ gap: 8 }}>
            {Studios.isPromoted(studio) && <div><PromotedTag /></div>}
            <div className="row" style={{ gap: 6 }}><h1 className="title-l">{studio.name}</h1>{studio.is_verified && <VerifiedBadge />}{studio.has_admin_badge && <AdminBadge />}</div>
            {!!studio.admin_tags?.length && <div className="chips">{studio.admin_tags.map((tag) => <SpecialTag key={tag} title={tag} />)}</div>}
            {linkedArtist && (
              <Link to={`/artists/${linkedArtist.id}`} className="card tight row pressable" style={{ maxWidth: 360, borderRadius: 18 }}>
                <Avatar url={linkedArtist.avatar_url} name={linkedArtist.artist_name} size={34} ring />
                <span className="grow"><div className="caption2 bold secondary">{t("Run by").toUpperCase()}</div><div className="subhead bold row" style={{ gap: 4 }}>{linkedArtist.artist_name}{linkedArtist.has_admin_badge && <AdminBadge compact />}</div></span>
                <ChevronRight size={16} className="tertiary" />
              </Link>
            )}
            {studio.tagline && <div className="secondary">{studio.tagline}</div>}
            <div className="row wrap" style={{ gap: 14 }}>
              <RatingLabel rating={studio.rating_average} count={studio.review_count} />
              <span className="row subhead" style={{ gap: 4 }}><MapPin size={15} color="var(--accent)" />{Studios.publicArea(studio)}</span>
              {location.point && (studio.latitude || studio.longitude) ? <span className="subhead secondary">{formatDistance(distanceMeters(location.point, studio))}</span> : null}
            </div>
            <div className="chips" style={{ marginTop: 4 }}>
              {studio.booking_policy.instant_book && <Chip title="Instant book" icon={Zap} />}
              <Chip title={format("Up to %lld people", studio.capacity)} icon={Users} translate={false} />
              <Chip title={format("%lld sessions booked", studio.booking_count)} icon={CalendarDays} translate={false} />
            </div>
          </div>

          {slots.length > 0 && (
            <section className="stack" style={{ gap: 10 }}>
              <GlowHead title="Next available" />
              <div className="row" style={{ overflowX: "auto", gap: 8, paddingBottom: 4 }}>
                {slots.slice(0, 8).map((slot, i) => (
                  <button key={slot.start.toISOString()} onClick={book} className={i === 0 ? "" : "card flat"} style={{ flexShrink: 0, padding: "10px 16px", borderRadius: 16, textAlign: "center", ...(i === 0 ? { background: "var(--neon)", color: "#fff", boxShadow: "0 0 14px color-mix(in srgb, var(--magenta) 40%, transparent)" } : {}) }}>
                    <div className="caption semibold" style={{ opacity: 0.8 }}>{new Intl.DateTimeFormat(undefined, { weekday: "short", day: "numeric", timeZone: zone }).format(slot.start)}</div>
                    <div className="subhead heavy">{Dates.time(slot.start, zone)}</div>
                  </button>
                ))}
              </div>
            </section>
          )}

          <section className="stack" style={{ gap: 10 }}>
            <GlowHead title="Prices" />
            {studio.session_types.map((type) => (
              <div key={type.id} className="card row top">
                <div className="grow">
                  <div className="row semibold" style={{ gap: 6 }}>{type.name}{type.includes_engineer && <UserRound size={16} color="var(--accent)" />}</div>
                  {type.details && <div className="footnote secondary">{type.details}</div>}
                  <div className="caption secondary">{format("Min. %lldh", type.minimum_hours)}</div>
                </div>
                <div className="bold">{Money.format(type.hourly_rate, studio.currency)}/h</div>
              </div>
            ))}
            {studio.add_ons.length > 0 && (
              <>
                <div className="headline" style={{ marginTop: 4 }}>{t("Add-ons")}</div>
                {studio.add_ons.map((a) => <div key={a.id} className="row spread subhead"><span>{a.name}</span><span className="secondary">{Money.format(a.price, studio.currency)} {t(PRICE_UNITS.find(([k]) => k === a.unit)![1])}</span></div>)}
              </>
            )}
            {studio.booking_policy.deposit_percent > 0 && <div className="row footnote secondary" style={{ gap: 6 }}><CreditCard size={15} />{format("%lld%% deposit at booking, the rest is charged after your session.", studio.booking_policy.deposit_percent)}</div>}
          </section>

          {studio.description && <section className="stack" style={{ gap: 8 }}><GlowHead title="About" /><div className="secondary pre">{studio.description}</div></section>}
          {(video || website) && (
            <div className="row wrap" style={{ gap: 10 }}>
              {video && <a className="chip semibold" href={video} target="_blank" rel="noreferrer"><PlayCircle size={16} color="var(--accent)" />{t("Studio tour")}</a>}
              {website && <a className="chip semibold" href={website} target="_blank" rel="noreferrer"><Globe size={16} color="var(--accent)" />{t("Website")}</a>}
            </div>
          )}

          {studio.facilities.length > 0 && (
            <section className="stack" style={{ gap: 10 }}>
              <GlowHead title="Facilities" />
              <div className="grid-2">{studio.facilities.map((f) => { const I = facilityIcon(f); return <div key={f} className="row subhead" style={{ gap: 8 }}><I size={17} color="var(--accent)" />{t(facilityTitle(f))}</div>; })}</div>
            </section>
          )}
          {studio.equipment.length > 0 && (
            <section className="stack" style={{ gap: 10 }}>
              <GlowHead title="Equipment" />
              {EQUIPMENT_CATEGORIES.map(([cat, title]) => {
                const items = studio.equipment.filter((e) => e.category === cat);
                return items.length ? <div key={cat}><div className="subhead bold">{t(title)}</div>{items.map((i) => <div key={i.id} className="subhead secondary">• {i.name}</div>)}</div> : null;
              })}
            </section>
          )}
          {studio.engineers.length > 0 && (
            <section className="stack" style={{ gap: 10 }}>
              <GlowHead title="Engineers & producers" />
              {studio.engineers.map((p) => <div key={p.id} className="row"><Avatar name={p.name} size={40} /><div><div className="semibold">{p.name}</div><div className="caption accent">{p.role}</div>{p.bio && <div className="caption secondary">{p.bio}</div>}</div></div>)}
            </section>
          )}
          {studio.genres.length > 0 && <section className="stack" style={{ gap: 10 }}><GlowHead title="Genres" /><div className="chips">{studio.genres.map((g) => <Chip key={g} title={genreTitle(g)} />)}</div></section>}
          <section className="stack" style={{ gap: 6 }}>
            <GlowHead title="Opening hours" />
            {OPENING_DISPLAY_ORDER.map((d) => { const h = Studios.hours(studio, d); return h ? <div key={d} className="row spread subhead"><span>{weekdayName(d)}</span><span className={h.is_closed ? "secondary" : ""}>{hoursLabel(h)}</span></div> : null; })}
          </section>
          <section className="stack" style={{ gap: 8 }}>
            <GlowHead title="Rules & terms" />
            {studio.rules.map((r, i) => <div key={i} className="row subhead" style={{ gap: 8 }}><CircleCheck size={17} color="var(--accent)" />{r}</div>)}
            <div className="subhead bold" style={{ marginTop: 4 }}>{format("Cancellation: %@", t(CANCELLATION[studio.booking_policy.cancellation_policy].title))}</div>
            <div className="footnote secondary">{t(CANCELLATION[studio.booking_policy.cancellation_policy].summary)}</div>
            {studio.booking_policy.terms && <div className="footnote secondary pre">{studio.booking_policy.terms}</div>}
          </section>
          {(studio.latitude || studio.longitude) ? (
            <section className="stack" style={{ gap: 10 }}>
              <GlowHead title="Location" />
              <StudioMap height={220} center={studio} interactive={false} pins={[{ id: studio.id, point: studio, label: studio.name }]} />
              <div className="subhead">{Studios.publicArea(studio)}</div>
              <div className="caption secondary">{t("The exact address is shared after booking.")}</div>
              <div className="row" style={{ gap: 10 }}>
                <a className="btn primary grow" href={directionsUrl(studio)} target="_blank" rel="noreferrer"><Navigation size={18} />{t("Directions")}</a>
                <a className="btn secondary grow" href={mapsUrl(studio)} target="_blank" rel="noreferrer"><MapIcon size={18} />Google Maps</a>
              </div>
            </section>
          ) : null}
          <section className="stack" style={{ gap: 12 }}>
            <GlowHead title="Reviews" />
            <ReviewSummary studio={studio} reviews={reviews} />
            {reviews.slice(0, 3).map((r) => <ReviewRow key={r.id} initial={r} canReply={false} />)}
            {reviews.length > 3 && <Link to={`/studios/${studio.id}/reviews`} className="semibold accent">{format("See all %lld reviews", reviews.length)}</Link>}
          </section>
          {app.account && !isOwner && (
            <div className="row" style={{ gap: 18 }}>
              <button className="row footnote secondary" style={{ gap: 6 }} onClick={() => setShowReport(true)}><Flag size={15} />{t("Report this studio")}</button>
              <button className="row footnote secondary" style={{ gap: 6 }} onClick={() => (blocked ? setBlock(false) : setConfirmBlock(true))}>{blocked ? <HandMetal size={15} /> : <Hand size={15} />}{t(blocked ? "Unblock" : "Block studio")}</button>
            </div>
          )}
        </div>
        <aside className="sticky hide-mobile">{bookingCard}</aside>
      </div>
      {(isArtist || !app.account) && (
        <div className="only-mobile" style={{ position: "fixed", left: 12, right: 12, bottom: `calc(${app.account ? 88 : 12}px + env(safe-area-inset-bottom))`, zIndex: 25 }}>
          <div className="card row" style={{ padding: 12, borderRadius: 24 }}>
            <div className="grow"><div className="headline">{format("From %@/h", Money.format(studio.price_from, studio.currency))}</div><div className="caption secondary">{t(studio.booking_policy.instant_book ? "Instant confirmation" : "Studio confirms within 24h")}</div></div>
            {app.account && <button className="icon-btn" onClick={message} aria-label={t("Message")}><MessageCircle size={18} /></button>}
            <button className="btn primary small" style={{ height: 44 }} onClick={book}>{t(app.account ? "Book" : "Sign up to book")}</button>
          </div>
        </div>
      )}
      <ReportSheet open={showReport} onClose={() => setShowReport(false)} target="studio" targetId={studio.id} />
      <ConfirmDialog open={confirmBlock} onClose={() => setConfirmBlock(false)} translateTitle={false} title={format("Block %@?", studio.name)}
        message={t("Neither of you can send messages in this conversation. You can unblock them any time in Settings → Blocked accounts.")}
        actions={[{ title: "Block", destructive: true, action: () => setBlock(true) }]} />
    </main>
  );
}

export function Gallery({ urls }: { urls: string[] }) {
  const [index, setIndex] = useState(0);
  const pages = urls.length ? urls : [null];
  return (
    <div style={{ position: "relative", height: "min(52vh, 460px)", overflow: "hidden" }}>
      <div style={{ display: "flex", height: "100%", transform: `translateX(-${index * 100}%)`, transition: "transform 0.35s ease" }}>
        {pages.map((url, i) => <Photo key={i} url={url} style={{ flex: "0 0 100%", height: "100%" }} />)}
      </div>
      {pages.length > 1 && (
        <>
          <button className="icon-btn" style={{ position: "absolute", top: "50%", left: 34, transform: "translateY(-50%)" }} onClick={() => setIndex((index - 1 + pages.length) % pages.length)} aria-label={t("Previous")}><ChevronLeft size={20} /></button>
          <button className="icon-btn" style={{ position: "absolute", top: "50%", right: 34, transform: "translateY(-50%)" }} onClick={() => setIndex((index + 1) % pages.length)} aria-label={t("Next")}><ChevronRight size={20} /></button>
          <div className="row" style={{ position: "absolute", bottom: 12, left: 0, right: 0, justifyContent: "center", gap: 6 }}>
            {pages.map((_, i) => <button key={i} onClick={() => setIndex(i)} style={{ width: 7, height: 7, borderRadius: 4, background: i === index ? "#fff" : "rgba(255,255,255,0.45)" }} aria-label={String(i + 1)} />)}
          </div>
        </>
      )}
    </div>
  );
}
