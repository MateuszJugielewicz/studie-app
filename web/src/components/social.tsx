// Reviews, reports, ratings and the small "⋯" menu, shared by several pages.
import { useEffect, useRef, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import {
  Ban, CalendarX, CheckCircle2, Circle, CreditCard, EllipsisVertical, EyeOff, Flag, Hand, Mail, MessageCircleMore, Reply, Scale,
  ShieldAlert, ShieldCheck, Star, UserRoundSearch, type LucideIcon,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { REPORT_REASONS, REPORT_TITLE, type Booking, type ReportReason, type ReportTarget, type Review, type Studio } from "../lib/types";
import { Avatar, GlowHead, IconTile, Item, Section, Sheet, StarPicker, Stars, Tiles, ToggleItem, ToolButton, useToast } from "./ui";

// MARK: Menu

export interface MenuEntry { title: string; icon: LucideIcon; destructive?: boolean; onClick: () => void; translate?: boolean }

/** A "⋯" button that opens a small menu (iOS Menu / Android DropdownMenu). */
export function Menu({ entries, trigger }: { entries: MenuEntry[]; trigger?: ReactNode }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent) => { if (!ref.current?.contains(e.target as Node)) setOpen(false); };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [open]);
  if (!entries.length) return null;
  return (
    <div ref={ref} style={{ position: "relative" }}>
      <button className="icon-btn" style={{ width: 34, height: 34 }} onClick={() => setOpen(!open)} aria-label={t("More")}>{trigger ?? <EllipsisVertical size={18} />}</button>
      {open && (
        <div className="card tight" style={{ position: "absolute", right: 0, top: 40, zIndex: 15, minWidth: 220, padding: 6 }}>
          {entries.map((e) => (
            <button key={e.title} className="item" style={{ minHeight: 42, borderRadius: 10, color: e.destructive ? "var(--red)" : undefined }} onClick={() => { setOpen(false); e.onClick(); }}>
              <e.icon size={18} /><span className="label">{e.translate === false ? e.title : t(e.title)}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// MARK: Reviews

export function ReviewSummary({ studio, reviews }: { studio: Studio; reviews: Review[] }) {
  const avg = (values: number[]) => (values.length ? values.reduce((a, b) => a + b, 0) / values.length : 0);
  const engineer = reviews.map((r) => r.engineer_rating).filter((x): x is number => x != null);
  return (
    <div className="card row" style={{ gap: 20 }}>
      <div className="center">
        <div style={{ fontSize: 44, fontWeight: 800, lineHeight: 1 }}>{studio.review_count === 0 ? "–" : studio.rating_average.toFixed(1)}</div>
        <Stars rating={studio.rating_average} size={12} />
        <div className="caption secondary">{format("%lld reviews", studio.review_count)}</div>
      </div>
      {reviews.length > 0 && (
        <div className="grow stack" style={{ gap: 6 }}>
          <Bar title="Facilities" value={avg(reviews.map((r) => r.facilities_rating))} />
          <Bar title="Experience" value={avg(reviews.map((r) => r.experience_rating))} />
          {engineer.length > 0 && <Bar title="Engineer" value={avg(engineer)} />}
        </div>
      )}
    </div>
  );
}

function Bar({ title, value }: { title: string; value: number }) {
  return (
    <div className="row caption" style={{ gap: 8 }}>
      <span style={{ width: 80 }}>{t(title)}</span>
      <span className="grow" style={{ height: 4, borderRadius: 2, background: "var(--fill)" }}><span style={{ display: "block", height: 4, borderRadius: 2, width: `${(value / 5) * 100}%`, background: "var(--text)" }} /></span>
      <span>{value.toFixed(1)}</span>
    </div>
  );
}

export function ReviewRow({ initial, canReply }: { initial: Review; canReply: boolean }) {
  const app = useApp();
  const navigate = useNavigate();
  const [review, setReview] = useState(initial);
  const [sheet, setSheet] = useState<"reply" | "report" | "dispute" | null>(null);
  const [disputed, setDisputed] = useState(false);
  const entries: MenuEntry[] = [];
  if (canReply && !review.studio_reply) entries.push({ title: "Reply", icon: Reply, onClick: () => setSheet("reply") });
  if (canReply && !disputed) entries.push({ title: "Dispute rating", icon: Scale, onClick: () => setSheet("dispute") });
  entries.push({ title: "Report review", icon: Flag, onClick: () => (app.account ? setSheet("report") : navigate("/signin")) });
  return (
    <div className="card">
      <div className="row" style={{ gap: 8 }}>
        <Avatar name={review.artist_name} size={32} />
        <div className="grow"><div className="subhead bold">{review.artist_name}</div><div className="caption secondary">{Dates.abbreviated(review.created_at)}</div></div>
        <Stars rating={review.rating} size={12} />
        <Menu entries={entries} />
      </div>
      {review.text && <div className="subhead pre" style={{ marginTop: 8 }}>{review.text}</div>}
      {review.studio_reply && (
        <div style={{ marginTop: 8, padding: 10, borderRadius: 10, background: "color-mix(in srgb, var(--accent) 12%, transparent)" }}>
          <div className="caption bold">{t("Response from the studio")}</div>
          <div className="caption pre">{review.studio_reply}</div>
        </div>
      )}
      <ReportSheet open={sheet === "report"} onClose={() => setSheet(null)} target="review" targetId={review.id} />
      <ReplySheet open={sheet === "reply"} onClose={() => setSheet(null)} review={review} onSaved={setReview} />
      <DisputeRatingSheet open={sheet === "dispute"} onClose={() => setSheet(null)} kind="studio_review" reviewId={review.id} onSent={() => setDisputed(true)} />
    </div>
  );
}

function ReplySheet({ open, onClose, review, onSaved }: { open: boolean; onClose: () => void; review: Review; onSaved: (r: Review) => void }) {
  const toast = useToast();
  const [text, setText] = useState("");
  async function post() {
    try { onSaved(await api.replyToReview(review.id, text)); onClose(); } catch (e) { toast(userMessage(e)); }
  }
  return (
    <Sheet open={open} onClose={onClose} title="Reply to review" closeLabel="Cancel" actions={<ToolButton title="Post" bold disabled={!text.trim()} onClick={post} />}>
      <div className="stack-lg">
        <Section><Item><span className="secondary pre">{review.text}</span></Item></Section>
        <Section header="Your public reply">
          <Item><textarea rows={5} placeholder={t("Thank the artist or respond to feedback")} value={text} onChange={(e) => setText(e.target.value)} /></Item>
        </Section>
      </div>
    </Sheet>
  );
}

export function WriteReviewSheet({ open, onClose, booking, onSubmitted }: { open: boolean; onClose: () => void; booking: Booking; onSubmitted?: () => void }) {
  const app = useApp();
  const toast = useToast();
  const [rating, setRating] = useState(5);
  const [facilities, setFacilities] = useState(5);
  const [experience, setExperience] = useState(5);
  const [hadEngineer, setHadEngineer] = useState(/engineer/i.test(booking.session_type_name) || booking.add_ons.some((a) => a.id === "producer"));
  const [engineer, setEngineer] = useState(5);
  const [text, setText] = useState("");
  const [saving, setSaving] = useState(false);
  async function submit() {
    setSaving(true);
    try {
      await api.submitReview({
        booking_id: booking.id, studio_id: booking.studio_id, artist_name: app.artistProfile?.artist_name || booking.artist_name, rating,
        facilities_rating: facilities, experience_rating: experience, engineer_rating: hadEngineer ? engineer : null, text: text.trim(),
      });
      onSubmitted?.();
      onClose();
    } catch (e) { toast(userMessage(e)); }
    setSaving(false);
  }
  return (
    <Sheet open={open} onClose={onClose} title="Review your session" closeLabel="Later" actions={<ToolButton title="Submit" bold disabled={saving || text.length < 10} onClick={submit} />}>
      <div className="stack-lg">
        <Section><Item><div><div className="headline">{booking.studio_name}</div><div className="caption secondary">{booking.session_type_name} · {Dates.abbreviated(booking.starts_at)}</div></div></Item></Section>
        <Section header="Ratings">
          <StarRow title="Overall" value={rating} onChange={setRating} />
          <StarRow title="Facilities" value={facilities} onChange={setFacilities} />
          <StarRow title="Studio experience" value={experience} onChange={setExperience} />
          <ToggleItem title="I worked with an engineer/producer" checked={hadEngineer} onChange={setHadEngineer} />
          {hadEngineer && <StarRow title="Engineer/producer" value={engineer} onChange={setEngineer} />}
        </Section>
        <Section header="Your review" footer="Reviews are public and shown with your artist name.">
          <Item><textarea rows={5} placeholder={t("What was great? What could be better?")} value={text} onChange={(e) => setText(e.target.value)} /></Item>
        </Section>
        <button className="btn primary block" disabled={saving || text.length < 10} onClick={submit}>{t("Submit")}</button>
      </div>
    </Sheet>
  );
}

function StarRow({ title, value, onChange }: { title: string; value: number; onChange: (n: number) => void }) {
  return <Item><span className="label">{t(title)}</span><span className="row" style={{ gap: 4 }}>{[1, 2, 3, 4, 5].map((n) => <button key={n} onClick={() => onChange(n)} style={{ color: n <= value ? "var(--accent)" : "var(--text-3)" }} aria-label={format("%lld stars", n)}><Star size={22} fill={n <= value ? "currentColor" : "none"} /></button>)}</span></Item>;
}

// MARK: Reports

const REASON_ICONS: Record<ReportReason, LucideIcon> = { fake: UserRoundSearch, spam: Mail, abusive: Hand, inappropriate: EyeOff, fraud: CreditCard, no_show: CalendarX, other: MessageCircleMore };

export function ReportSheet({ open, onClose, target, targetId }: { open: boolean; onClose: () => void; target: ReportTarget; targetId: string }) {
  const toast = useToast();
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState("");
  const [sent, setSent] = useState(false);
  const [sending, setSending] = useState(false);
  useEffect(() => { if (open) { setSent(false); setReason(null); setDetails(""); } }, [open]);
  async function send() {
    if (!reason) return;
    setSending(true);
    try { await api.report(target, targetId, reason, details); setSent(true); } catch (e) { toast(userMessage(e)); }
    setSending(false);
  }
  return (
    <Sheet open={open} onClose={onClose} closeLabel={sent ? "Done" : "Cancel"}>
      {sent ? (
        <div className="stack center" style={{ alignItems: "center", padding: "40px 10px" }}>
          <IconTile icon={ShieldCheck} size={84} colors={Tiles.mint} />
          <div className="title-m heavy">{t("Thanks for letting us know")}</div>
          <div className="subhead secondary">{t("Our moderation team will look into it, usually within 24 hours. We may contact you if we need more details.")}</div>
          <button className="btn primary" onClick={onClose}>{t("Done")}</button>
        </div>
      ) : (
        <div className="stack">
          <div className="row"><IconTile icon={Flag} size={48} /><div><div className="title-m heavy">{t(REPORT_TITLE[target])}</div><div className="subhead secondary">{t("Reports are private. The other side isn't told who reported them.")}</div></div></div>
          <GlowHead title="What's wrong?" />
          {REPORT_REASONS.map(([key, title, hint]) => {
            const on = reason === key;
            const Icon = REASON_ICONS[key];
            return (
              <button key={key} className="card tight row" style={{ textAlign: "left", borderRadius: 18, border: on ? "1.5px solid var(--magenta)" : undefined }} onClick={() => setReason(key)}>
                <IconTile icon={Icon} size={34} colors={on ? Tiles.signal : Tiles.muted} />
                <span className="grow"><div className="subhead semibold">{t(title)}</div><div className="caption secondary">{t(hint)}</div></span>
                {on ? <CheckCircle2 color="var(--accent)" /> : <Circle className="tertiary" />}
              </button>
            );
          })}
          <GlowHead title="Details (optional)" />
          <label className="field area"><textarea rows={4} placeholder={t("Tell us what happened. Dates, messages and names help us act faster.")} value={details} onChange={(e) => setDetails(e.target.value)} /></label>
          <div className="row caption secondary" style={{ gap: 6 }}><ShieldAlert size={14} />{t("If someone is in danger, contact the local emergency services first.")}</div>
          <button className="btn primary block" disabled={!reason || sending} onClick={send}>{t(sending ? "Sending…" : "Send report")}</button>
        </div>
      )}
    </Sheet>
  );
}

// MARK: Ratings of artists

/** A studio rates the artist after a completed session. Shown on the artist's profile; the artist can dispute it. */
export function RateArtistSheet({ open, onClose, booking, onSubmitted }: { open: boolean; onClose: () => void; booking: Booking; onSubmitted?: () => void }) {
  const toast = useToast();
  const [rating, setRating] = useState(5);
  const [text, setText] = useState("");
  const [saving, setSaving] = useState(false);
  async function submit() {
    setSaving(true);
    try { await api.reviewArtist(booking.id, rating, text.trim()); onSubmitted?.(); onClose(); } catch (e) { toast(userMessage(e)); }
    setSaving(false);
  }
  return (
    <Sheet open={open} onClose={onClose} closeLabel="Later">
      <div className="stack">
        <div className="row"><IconTile icon={Star} size={44} colors={Tiles.violet} /><div><div className="title-m heavy">{format("Rate %@", booking.artist_name)}</div><div className="caption secondary">{booking.session_type_name} · {Dates.abbreviated(booking.starts_at)}</div></div></div>
        <div className="card"><div className="subhead semibold center" style={{ marginBottom: 8 }}>{t("Overall")}</div><StarPicker value={rating} onChange={setRating} /></div>
        <label className="field area"><textarea rows={4} placeholder={t("How was the session? Punctual, respectful, prepared?")} value={text} onChange={(e) => setText(e.target.value)} /></label>
        <div className="caption secondary">{t("Ratings are shown on the artist's profile with your studio name. Be fair: the artist can ask EasySesh to review it.")}</div>
        <button className="btn primary block" disabled={saving} onClick={submit}>{t(saving ? "Sending…" : "Submit rating")}</button>
      </div>
    </Sheet>
  );
}

export function DisputeRatingSheet({ open, onClose, kind, reviewId, onSent }: { open: boolean; onClose: () => void; kind: "studio_review" | "artist_review"; reviewId: string; onSent?: () => void }) {
  const toast = useToast();
  const [reason, setReason] = useState("");
  const [sending, setSending] = useState(false);
  async function send() {
    setSending(true);
    try { await api.disputeRating(kind, reviewId, reason); onSent?.(); onClose(); } catch (e) { toast(userMessage(e)); }
    setSending(false);
  }
  return (
    <Sheet open={open} onClose={onClose} closeLabel="Cancel">
      <div className="stack">
        <div className="row top"><IconTile icon={Scale} size={44} colors={Tiles.violet} /><div><div className="title-m heavy">{t("Dispute this rating")}</div><div className="subhead secondary">{t("Our team checks the booking and the rating. If it breaks our guidelines or isn't about a real session, we remove it.")}</div></div></div>
        <label className="field area"><textarea rows={5} placeholder={t("Why is this rating unfair?")} value={reason} onChange={(e) => setReason(e.target.value)} /></label>
        <button className="btn primary block" disabled={sending || reason.trim().length < 10} onClick={send}>{t(sending ? "Sending…" : "Send dispute")}</button>
      </div>
    </Sheet>
  );
}

export const BlockIcon = Ban;
