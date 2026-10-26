import { useEffect, useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ArrowUpDown, Check, List, Map as MapIcon, Search, SlidersHorizontal, XCircle, Zap, AudioLines } from "lucide-react";
import { api } from "../lib/api";
import {
  activeFilterCount, addDays, EMPTY_FILTERS, formatDistance, greeting, Money, searchStudios, SORTS, startOfDay, Studios, Dates,
  type SearchFilters, type StudioResult, type StudioSort,
} from "../lib/core";
import { format, t } from "../lib/i18n";
import { useLocation } from "../lib/location";
import { useApp, useLoad } from "../lib/state";
import { PlatformConfig } from "../lib/config";
import { EQUIPMENT_CATEGORIES, FACILITIES, GENRES, type Interval } from "../lib/types";
import {
  AdminBadge, ChipPicker, Empty, InputItem, Item, LargeHead, Loading, Photo, PromotedTag, RatingLabel, Section, Segmented, Sheet,
  SpecialTag, Stepper, ToggleItem, ToolButton, VerifiedBadge,
} from "../components/ui";
import { StudioMap } from "../components/StudioMap";
import { StoryBar } from "../components/Stories";

// Filters survive going to a studio and back. The map starts open on wide screens, where it sits beside the list.
let saved: { filters: SearchFilters; sort: StudioSort; map: boolean } = { filters: EMPTY_FILTERS, sort: "nearest", map: typeof window !== "undefined" && window.innerWidth > 1100 };

export default function Discover() {
  const app = useApp();
  const navigate = useNavigate();
  const location = useLocation();
  const [params] = useSearchParams();
  const [filters, setFilters] = useState(() => (params.get("q") != null ? { ...saved.filters, query: params.get("q") ?? "" } : saved.filters));
  const [sort, setSort] = useState(saved.sort);
  const [showMap, setShowMap] = useState(saved.map);
  const [showFilters, setShowFilters] = useState(false);
  const [sortOpen, setSortOpen] = useState(false);
  const [busy, setBusy] = useState<Record<string, Interval[]>>({});
  const { data: studios, loading, error } = useLoad(() => api.publishedStudios(), []);
  const metric = app.account?.settings?.use_metric_units ?? true;
  const radius = app.account?.settings?.search_radius_km ?? 5;

  useEffect(() => { saved = { filters, sort, map: showMap }; }, [filters, sort, showMap]);
  useEffect(() => { location.request(); }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Availability filtering needs bookings/blocks for the chosen day.
  useEffect(() => {
    const day = filters.availableOn;
    if (!day || !studios) { setBusy({}); return; }
    api.busyIntervals(studios.map((s) => s.id), startOfDay(day), addDays(startOfDay(day), 2)).then(setBusy).catch(() => setBusy({}));
  }, [filters.availableOn, filters.sessionHours, studios]);

  const origin = location.effective;
  const results = useMemo(() => searchStudios(studios ?? [], filters, sort, origin, busy), [studios, filters, sort, origin, busy]);
  const nearby = useMemo(() => searchStudios(studios ?? [], EMPTY_FILTERS, "nearest", origin).filter((r) => (r.distance ?? 0) <= radius * 1000), [studios, origin, radius]);
  const cheapest = nearby.reduce<StudioResult | null>((min, r) => (!min || r.studio.price_from < min.studio.price_from ? r : min), null);
  const searching = !!filters.query.trim();
  const count = activeFilterCount(filters);

  const summary = searching
    ? t("Searching everywhere, sorted by distance.")
    : nearby.length === 0 && results.length > 0
      ? format("No studios within %lld km yet – %lld elsewhere. Search a city or country to find them.", Math.round(radius), results.length)
      : format("%lld studios within %lld km", nearby.length, Math.round(radius)) + (cheapest ? " · " + format("from %@/h", Money.format(cheapest.studio.price_from, cheapest.studio.currency)) : "");

  const pins = results.filter((r) => r.studio.latitude || r.studio.longitude).map((r) => ({ id: r.studio.id, point: r.studio, label: Money.format(r.studio.price_from, r.studio.currency) }));

  return (
    <main className="page wide">
      <LargeHead title="Find a studio" eyebrow={location.city ?? greeting()} />
      <StoryBar />
      <div className="toolbar">
        <label className="field grow" style={{ minWidth: 240, maxWidth: 520 }}>
          <Search size={18} />
          <input type="search" placeholder={t("Studio, area or city")} value={filters.query} onChange={(e) => setFilters({ ...filters, query: e.target.value })} />
          {filters.query && <button onClick={() => setFilters({ ...filters, query: "" })} aria-label={t("Clear")}><XCircle size={18} /></button>}
        </label>
        <button className={`chip ${count ? "on" : ""}`} onClick={() => setShowFilters(true)}><SlidersHorizontal size={15} />{count ? format("Filters · %lld", count) : t("Filters")}</button>
        <div style={{ position: "relative" }}>
          <button className="chip" onClick={() => setSortOpen(!sortOpen)} aria-expanded={sortOpen}><ArrowUpDown size={15} />{t(SORTS.find(([k]) => k === sort)![1])}</button>
          {sortOpen && (
            <div className="menu">
              {SORTS.map(([key, title]) => (
                <button key={key} className="item" onClick={() => { setSort(key); setSortOpen(false); }}>
                  <span className="label">{t(title)}</span>{key === sort && <Check size={16} color="var(--primary)" />}
                </button>
              ))}
            </div>
          )}
        </div>
        <span className="grow" />
        <button className="chip" onClick={() => setShowMap(!showMap)}>{showMap ? <List size={15} /> : <MapIcon size={15} />}{showMap ? <><span className="hide-mobile">{t("Hide map")}</span><span className="only-mobile">{t("Show list")}</span></> : t("Show map")}</button>
      </div>
      <div className={`discover-layout ${showMap ? "with-map" : ""}`}>
        <div className="discover-list stack" style={{ gap: 20 }}>
          <div className="row spread wrap" style={{ gap: 8 }}>
            <div>
              <h2 className="title-m">{searching ? format("%lld studios", results.length) : location.city ?? t("Near you")}</h2>
              <div className="subhead secondary">{summary}</div>
            </div>
          </div>
          {error && <div className="card danger">{error}</div>}
          {loading ? <Loading /> : results.length === 0 ? (
            <Empty icon={AudioLines} title="No studios found" message="Try widening your filters or search area.">
              {count > 0 && <button className="btn secondary small" onClick={() => setFilters({ ...EMPTY_FILTERS, query: filters.query })}>{t("Clear filters")}</button>}
            </Empty>
          ) : (
            <div className="grid-cards" style={{ rowGap: 32 }}>
              {results.map((r) => <StudioCard key={r.studio.id} result={r} metric={metric} onClick={() => navigate(`/studios/${r.studio.id}`)} />)}
            </div>
          )}
        </div>
        {showMap && (
          <div className="discover-map">
            <StudioMap height="min(calc(100vh - 112px), 860px)" center={origin} onSelect={(id) => navigate(`/studios/${id}`)} pins={pins} />
          </div>
        )}
      </div>
      <FilterSheet open={showFilters} initial={filters} onClose={() => setShowFilters(false)} onApply={(f) => { setFilters(f); setShowFilters(false); }} />
    </main>
  );
}

/** Photo-first listing card: image on top, facts underneath. */
export function StudioCard({ result, metric, onClick }: { result: StudioResult; metric: boolean; onClick: () => void }) {
  const s = result.studio;
  const promoted = Studios.isPromoted(s);
  return (
    <button className="listing pressable" onClick={onClick}>
      <Photo url={s.photo_urls[0]} style={promoted ? { outline: "2px solid var(--primary)", outlineOffset: -2 } : undefined}>
        {s.booking_policy.instant_book && (
          <span className="tag" style={{ position: "absolute", top: 10, left: 10, background: "var(--card)", color: "var(--text)", boxShadow: "var(--shadow-sm)" }}><Zap size={13} color="var(--accent)" fill="var(--accent)" />{t("Instant book")}</span>
        )}
        {promoted && <span style={{ position: "absolute", top: 10, right: 10 }}><PromotedTag /></span>}
      </Photo>
      <div style={{ display: "flex", flexDirection: "column", gap: 3 }}>
        <div className="row" style={{ gap: 4 }}>
          <span className="headline clamp-1">{s.name}</span>
          {s.is_verified && <VerifiedBadge />}
          {s.has_admin_badge && <AdminBadge compact />}
          <span className="grow" />
          <RatingLabel rating={s.rating_average} count={s.review_count} />
        </div>
        <div className="subhead secondary clamp-1">{[Studios.publicArea(s), result.distance != null ? formatDistance(result.distance, metric) : null].filter(Boolean).join(" · ")}</div>
        <div className="subhead" style={{ marginTop: 2 }}><span className="semibold">{Money.format(s.price_from, s.currency)}</span> <span className="secondary">{t("/ hour")}</span></div>
        {!!s.admin_tags?.length && <div className="row" style={{ gap: 6, marginTop: 4 }}>{s.admin_tags.slice(0, 2).map((tag) => <SpecialTag key={tag} title={tag} />)}</div>}
      </div>
    </button>
  );
}

function FilterSheet({ open, initial, onClose, onApply }: { open: boolean; initial: SearchFilters; onClose: () => void; onApply: (f: SearchFilters) => void }) {
  const [draft, setDraft] = useState(initial);
  useEffect(() => { if (open) setDraft(initial); }, [open, initial]);
  const set = (patch: Partial<SearchFilters>) => setDraft({ ...draft, ...patch });
  const opt = <T,>(values: (T | null)[], label: (v: T) => string) => values.map((v) => ({ value: String(v), label: v == null ? "Any" : label(v) }));
  return (
    <Sheet open={open} onClose={onClose} title="Filters" closeLabel="Cancel"
      actions={<><ToolButton title="Reset" onClick={() => setDraft({ ...EMPTY_FILTERS, query: initial.query })} /><ToolButton title="Show results" bold onClick={() => onApply(draft)} /></>}>
      <div className="stack-lg">
        <Section header="Max price per hour">
          <div style={{ padding: 10 }}>
            <Segmented value={String(draft.maxPrice)} options={opt([null, 1500, 2500, 4000, 6000], (v) => Money.format(v, "EUR"))} onChange={(v) => set({ maxPrice: v === "null" ? null : Number(v) })} />
          </div>
        </Section>
        <Section header="Distance">
          <div style={{ padding: 10 }}>
            <Segmented value={String(draft.maxDistanceKm)} options={opt([null, 2, 5, 10, 25], (v) => format("%lld km", v))} onChange={(v) => set({ maxDistanceKm: v === "null" ? null : Number(v) })} />
          </div>
        </Section>
        <Section header="Availability">
          <ToggleItem title="Available on a specific day" checked={!!draft.availableOn} onChange={(on) => set({ availableOn: on ? addDays(startOfDay(new Date()), 1) : null })} />
          {draft.availableOn && (
            <>
              <Item><span className="label">{t("Day")}</span><input type="date" min={Dates.iso(new Date())} value={Dates.iso(draft.availableOn)} onChange={(e) => e.target.value && set({ availableOn: new Date(e.target.value + "T00:00") })} /></Item>
              <Item><span className="label">{format("For at least %lld hours", draft.sessionHours)}</span><Stepper value={draft.sessionHours} min={1} max={PlatformConfig.MAX_SESSION_HOURS} onChange={(v) => set({ sessionHours: v })} /></Item>
            </>
          )}
          <ToggleItem title="Instant book only" checked={draft.instantBookOnly} onChange={(v) => set({ instantBookOnly: v })} />
        </Section>
        <Section header="Rating">
          <div style={{ padding: 10 }}>
            <Segmented value={String(draft.minRating)} options={opt([null, 4, 4.5, 4.8], (v) => `${v.toFixed(1)}+`)} onChange={(v) => set({ minRating: v === "null" ? null : Number(v) })} />
          </div>
        </Section>
        <Section header="Genres"><div style={{ padding: 12 }}><ChipPicker items={GENRES} selected={draft.genres} onChange={(genres) => set({ genres })} /></div></Section>
        <Section header="Facilities"><div style={{ padding: 12 }}><ChipPicker items={FACILITIES} selected={draft.facilities} onChange={(facilities) => set({ facilities })} /></div></Section>
        <Section header="Services">
          <ToggleItem title="Engineer available" checked={draft.engineerIncluded} onChange={(v) => set({ engineerIncluded: v })} />
          <ToggleItem title="Mixing" checked={draft.offersMixing} onChange={(v) => set({ offersMixing: v })} />
          <ToggleItem title="Mastering" checked={draft.offersMastering} onChange={(v) => set({ offersMastering: v })} />
        </Section>
        <Section header="Equipment">
          <InputItem placeholder="e.g. U87, SM7B, Neve" value={draft.equipmentQuery} onChange={(v) => set({ equipmentQuery: v })} />
          <Item><ChipPicker items={EQUIPMENT_CATEGORIES} selected={draft.equipmentCategories} onChange={(equipmentCategories) => set({ equipmentCategories })} /></Item>
        </Section>
        <button className="btn primary block" onClick={() => onApply(draft)}>{t("Show results")}</button>
      </div>
    </Sheet>
  );
}

