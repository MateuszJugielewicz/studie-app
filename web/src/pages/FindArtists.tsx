// Studios find artists the way artists find studios: search, filters and sorting over every artist,
// with promoted artists first (Promoted tag). Opening an artist shows their profile; "Message" starts
// a conversation (artists who never booked the studio get it as a message request).
import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowUpDown, Check, MessageCircle, Mic2, Search, SlidersHorizontal, XCircle } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { normalizeText } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp, useLoad } from "../lib/state";
import { GENRES, genreTitle, type Conversation, type DiscoveredArtist, type Genre } from "../lib/types";
import {
  AdminBadge, Avatar, ChipPicker, Empty, Item, LargeHead, Loading, PromotedTag, RatingLabel, Section, Segmented, Sheet, ToggleItem, ToolButton,
  VerifiedBadge, useToast,
} from "../components/ui";

type ArtistSort = "recommended" | "top_rated" | "most_sessions" | "newest";
const SORTS: [ArtistSort, string][] = [["recommended", "Recommended"], ["top_rated", "Top rated"], ["most_sessions", "Most sessions"], ["newest", "Newest"]];

interface ArtistFilters { query: string; genres: Genre[]; verifiedOnly: boolean; bookedBefore: boolean; minRating: number | null }
const EMPTY: ArtistFilters = { query: "", genres: [], verifiedOnly: false, bookedBefore: false, minRating: null };
const filterCount = (f: ArtistFilters) => f.genres.length + (f.verifiedOnly ? 1 : 0) + (f.bookedBefore ? 1 : 0) + (f.minRating != null ? 1 : 0);

// Filters survive opening an artist and coming back.
let saved: { filters: ArtistFilters; sort: ArtistSort } = { filters: EMPTY, sort: "recommended" };

export function searchArtists(artists: DiscoveredArtist[], f: ArtistFilters, sort: ArtistSort): DiscoveredArtist[] {
  const words = normalizeText(f.query.trim()).split(" ").filter(Boolean);
  const results = artists.filter((a) => {
    if (words.length) {
      const text = normalizeText([a.artist_name, a.city, a.bio, ...a.genres.map((g) => t(genreTitle(g)))].join(" "));
      if (!words.every((w) => text.includes(w))) return false;
    }
    if (f.genres.length && !f.genres.some((g) => a.genres.includes(g))) return false;
    if (f.verifiedOnly && !a.is_verified) return false;
    if (f.bookedBefore && !a.has_booked) return false;
    if (f.minRating != null && (a.review_count === 0 || a.rating_average < f.minRating)) return false;
    return true;
  });
  const sorted = [...results].sort((a, b) => {
    if (sort === "top_rated") return b.rating_average - a.rating_average || b.review_count - a.review_count;
    if (sort === "most_sessions") return b.session_count - a.session_count;
    if (sort === "newest") return +new Date(b.joined_at) - +new Date(a.joined_at);
    // Recommended: artists who worked with the studio, then rating and experience.
    return Number(b.has_booked) - Number(a.has_booked) || b.rating_average * Math.min(b.review_count, 5) - a.rating_average * Math.min(a.review_count, 5) || b.session_count - a.session_count;
  });
  // Promoted artists first; the chosen sort applies within each group (same as studios in Discover).
  return [...sorted.filter((a) => a.is_promoted), ...sorted.filter((a) => !a.is_promoted)];
}

export default function FindArtists() {
  const navigate = useNavigate();
  const [filters, setFilters] = useState(saved.filters);
  const [sort, setSort] = useState(saved.sort);
  const [sortOpen, setSortOpen] = useState(false);
  const [showFilters, setShowFilters] = useState(false);
  const [messaging, setMessaging] = useState<DiscoveredArtist | null>(null);
  const { data: artists, loading, error } = useLoad(() => api.discoverArtists(), []);
  useEffect(() => { saved = { filters, sort }; }, [filters, sort]);
  const results = useMemo(() => searchArtists(artists ?? [], filters, sort), [artists, filters, sort]);
  const count = filterCount(filters);
  const promoted = results.filter((a) => a.is_promoted).length;

  return (
    <main className="page wide">
      <LargeHead title="Find artists" eyebrow="For your studio" />
      <div className="stack">
        <label className="field">
          <Search size={18} />
          <input type="search" placeholder={t("Artist, genre or city")} value={filters.query} onChange={(e) => setFilters({ ...filters, query: e.target.value })} />
          {filters.query && <button onClick={() => setFilters({ ...filters, query: "" })} aria-label={t("Clear")}><XCircle size={18} /></button>}
        </label>
        <div className="row wrap" style={{ gap: 8 }}>
          <button className={`chip ${count ? "on" : ""}`} onClick={() => setShowFilters(true)}><SlidersHorizontal size={15} />{count ? format("Filters · %lld", count) : t("Filters")}</button>
          <div style={{ position: "relative" }}>
            <button className="chip" onClick={() => setSortOpen(!sortOpen)}><ArrowUpDown size={15} />{t(SORTS.find(([k]) => k === sort)![1])}</button>
            {sortOpen && (
              <div className="card tight" style={{ position: "absolute", top: 44, left: 0, zIndex: 10, minWidth: 200, padding: 6 }}>
                {SORTS.map(([key, title]) => (
                  <button key={key} className="item" style={{ minHeight: 40, borderRadius: 10 }} onClick={() => { setSort(key); setSortOpen(false); }}>
                    <span className="label">{t(title)}</span>{key === sort && <Check size={16} color="var(--accent)" />}
                  </button>
                ))}
              </div>
            )}
          </div>
          <span className="grow" />
          <span className="chip footnote bold" style={{ cursor: "default" }}><span style={{ width: 7, height: 7, borderRadius: 4, background: "var(--primary)" }} />{format("%lld artists", results.length)}</span>
        </div>
        {promoted > 0 && <div className="caption secondary">{t("Promoted artists are shown first.")}</div>}
        {error && <div className="card danger">{error}</div>}
        {loading ? <Loading /> : results.length === 0 ? (
          <Empty icon={Mic2} title="No artists found" message="Try another search or fewer filters.">
            {count > 0 && <button className="btn secondary small" onClick={() => setFilters({ ...EMPTY, query: filters.query })}>{t("Clear filters")}</button>}
          </Empty>
        ) : (
          <div className="grid-cards" style={{ gap: 16 }}>
            {results.map((a) => <ArtistCard key={a.id} artist={a} onOpen={() => navigate(`/artists/${a.id}`)} onMessage={() => setMessaging(a)} />)}
          </div>
        )}
      </div>
      <ArtistFilterSheet open={showFilters} initial={filters} onClose={() => setShowFilters(false)} onApply={(f) => { setFilters(f); setShowFilters(false); }} />
      <MessageArtistSheet artist={messaging} onClose={() => setMessaging(null)} onSent={(c) => navigate(`/messages/${c.id}`)} />
    </main>
  );
}

export function ArtistCard({ artist: a, onOpen, onMessage }: { artist: DiscoveredArtist; onOpen: () => void; onMessage: () => void }) {
  return (
    <div className="card stack" style={{ gap: 12, border: a.is_promoted ? "1.5px solid var(--primary)" : undefined, position: "relative" }}>
      {a.is_promoted && <span style={{ position: "absolute", top: 12, right: 12 }}><PromotedTag /></span>}
      <button className="row pressable" style={{ textAlign: "left", gap: 12 }} onClick={onOpen}>
        <Avatar url={a.avatar_url} name={a.artist_name} size={60} ring={a.is_promoted} />
        <span className="grow" style={{ minWidth: 0, paddingRight: a.is_promoted ? 92 : 0 }}>
          <span className="row" style={{ gap: 4 }}><span className="headline clamp-1">{a.artist_name}</span>{a.is_verified && <VerifiedBadge />}{a.has_admin_badge && <AdminBadge compact />}</span>
          <span className="subhead secondary clamp-1" style={{ display: "block" }}>{[a.city, a.has_booked ? t("Booked you before") : null].filter(Boolean).join(" · ")}</span>
          <span className="row caption secondary" style={{ gap: 10, marginTop: 2 }}>
            {a.review_count > 0 && <RatingLabel rating={a.rating_average} count={a.review_count} />}
            {a.session_count > 0 && <span>{format("%lld sessions", a.session_count)}</span>}
          </span>
        </span>
      </button>
      {a.bio && <div className="footnote secondary clamp-2">{a.bio}</div>}
      {a.genres.length > 0 && <div className="chips">{a.genres.slice(0, 4).map((g) => <span key={g} className="chip footnote" style={{ cursor: "default", minHeight: 28, padding: "4px 10px" }}>{t(genreTitle(g))}</span>)}</div>}
      <button className="btn secondary small block" onClick={onMessage}><MessageCircle size={15} />{t("Message")}</button>
    </div>
  );
}

function ArtistFilterSheet({ open, initial, onClose, onApply }: { open: boolean; initial: ArtistFilters; onClose: () => void; onApply: (f: ArtistFilters) => void }) {
  const [draft, setDraft] = useState(initial);
  useEffect(() => { if (open) setDraft(initial); }, [open, initial]);
  const set = (patch: Partial<ArtistFilters>) => setDraft({ ...draft, ...patch });
  return (
    <Sheet open={open} onClose={onClose} title="Filters" closeLabel="Cancel"
      actions={<><ToolButton title="Reset" onClick={() => setDraft({ ...EMPTY, query: initial.query })} /><ToolButton title="Show results" bold onClick={() => onApply(draft)} /></>}>
      <div className="stack-lg">
        <Section header="Rating">
          <div style={{ padding: 10 }}>
            <Segmented value={String(draft.minRating)} options={[null, 4, 4.5, 4.8].map((v) => ({ value: String(v), label: v == null ? "Any" : `${v.toFixed(1)}+` }))}
              onChange={(v) => set({ minRating: v === "null" ? null : Number(v) })} />
          </div>
        </Section>
        <Section header="Artists">
          <ToggleItem title="Verified artists only" checked={draft.verifiedOnly} onChange={(v) => set({ verifiedOnly: v })} />
          <ToggleItem title="Booked your studio before" checked={draft.bookedBefore} onChange={(v) => set({ bookedBefore: v })} />
        </Section>
        <Section header="Genres"><div style={{ padding: 12 }}><ChipPicker items={GENRES} selected={draft.genres} onChange={(genres) => set({ genres })} /></div></Section>
        <button className="btn primary block" onClick={() => onApply(draft)}>{t("Show results")}</button>
      </div>
    </Sheet>
  );
}

/** Write the first message to an artist (a message request unless they booked the studio before). */
export function MessageArtistSheet({ artist, onClose, onSent }: { artist: { id: string; artist_name: string } | null; onClose: () => void; onSent: (c: Conversation) => void }) {
  const toast = useToast();
  const app = useApp();
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  useEffect(() => { if (artist) setMessage(""); }, [artist]);
  async function send() {
    if (!artist) return;
    setSending(true);
    try { const c = await api.startConversation(artist.id, message.trim()); await app.refreshBadges(); onClose(); onSent(c); } catch (e) { toast(userMessage(e)); }
    setSending(false);
  }
  return (
    <Sheet open={!!artist} onClose={onClose} title={artist?.artist_name ?? ""} translateTitle={false} closeLabel="Cancel"
      actions={<ToolButton title={sending ? "Sending…" : "Send"} bold disabled={sending || !message.trim()} onClick={send} />}>
      <div className="stack">
        <Section><Item><textarea rows={5} autoFocus placeholder={t("Write a message…")} value={message} onChange={(e) => setMessage(e.target.value.slice(0, 2000))} /></Item></Section>
        <div className="caption secondary">{t("Artists who haven't booked your studio get this as a message request.")}</div>
      </div>
    </Sheet>
  );
}
