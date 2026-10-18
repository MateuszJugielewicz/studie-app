import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { Route, Routes, useNavigate } from "react-router-dom";
import {
  BadgeEuro, Bolt, Check, CheckCircle2, Circle, CircleAlert, Clock, Hourglass, ImagePlus, Landmark, LocateFixed, MapPin, MinusCircle, Plus, SearchCheck,
  SlidersVertical, Trash2, UserPlus, X, ImageIcon,
} from "lucide-react";
import { api, userMessage } from "../lib/api";
import { formatMinutes, Money, OPENING_DISPLAY_ORDER, studioProblems, Studios, weekdayName } from "../lib/core";
import { compressImage } from "../lib/image";
import { format, t } from "../lib/i18n";
import { geocode } from "../lib/location";
import { useApp } from "../lib/state";
import {
  ADD_ON_KINDS, CANCELLATION, EQUIPMENT_CATEGORIES, FACILITIES, GENRES, PRICE_UNITS, type CancellationPolicy, type EquipmentCategory, type OpeningHours, type Studio,
} from "../lib/types";
import { ChipPicker, InputItem, Item, Notice, PageHead, Section, Segmented, SelectItem, Spinner, Stepper, ToggleItem, ToolButton, useToast } from "../components/ui";
import { StudioMap } from "../components/StudioMap";
import { PayoutPage } from "./StudioExtras";

// The listing being edited, shared by the editor and its sections (the apps pass a Binding<Studio>).
let draft: Studio | null = null;
const listeners = new Set<() => void>();
const store = {
  get: () => draft,
  set(next: Studio) { draft = next; listeners.forEach((l) => l()); },
  subscribe(l: () => void) { listeners.add(l); return () => { listeners.delete(l); }; },
};
const newId = () => crypto.randomUUID().toLowerCase();

function useDraft(): [Studio, (s: Studio) => void] {
  const app = useApp();
  const current = useSyncExternalStore(store.subscribe, store.get);
  const owned = app.ownedStudio;
  if (!current || (owned && current.id !== owned.id)) {
    const initial = owned ?? (current && current.owner_id === app.account!.id ? current : Studios.newDraft(app.account!.id));
    draft = initial;
    return [initial, store.set];
  }
  return [current, store.set];
}

export default function StudioEditor() {
  return (
    <Routes>
      <Route index element={<EditorHome />} />
      <Route path="basics" element={<Basics />} />
      <Route path="location" element={<Location />} />
      <Route path="pricing" element={<SectionPage title="Prices & services"><Pricing /></SectionPage>} />
      <Route path="hours" element={<SectionPage title="Opening hours"><Hours /></SectionPage>} />
      <Route path="features" element={<Features />} />
      <Route path="policy" element={<SectionPage title="Booking settings"><Policy /></SectionPage>} />
      <Route path="payouts" element={<ApplicationPayouts />} />
    </Routes>
  );
}

/** Saves the whole listing (the owner can only change listing content; moderation fields are protected). */
function useSave() {
  const app = useApp();
  const toast = useToast();
  const [studio, setStudio] = useDraft();
  const [saving, setSaving] = useState(false);
  async function save(): Promise<boolean> {
    setSaving(true);
    try {
      const saved = await api.saveStudio(studio);
      setStudio(saved);
      app.setOwnedStudio(saved);
      setSaving(false);
      return true;
    } catch (e) {
      toast(userMessage(e));
      // If the application was stored after all, show it instead of this unsaved draft.
      const existing = await api.ownedStudio().catch(() => null);
      if (existing) app.setOwnedStudio(existing);
      setSaving(false);
      return false;
    }
  }
  return { save, saving };
}

function SaveButton({ after }: { after?: () => void }) {
  const { save, saving } = useSave();
  return <ToolButton title={saving ? "Saving…" : "Save"} bold disabled={saving} onClick={async () => { if (await save()) after?.(); }} />;
}

function EditorHome() {
  const app = useApp();
  const navigate = useNavigate();
  const [studio] = useDraft();
  const isApplication = !app.ownedStudio || !["approved", "suspended"].includes(app.ownedStudio.status);
  const problems = studioProblems(studio);
  const link = (to: string, title: string, Icon: typeof Clock, done: boolean) => (
    <Item to={`/studio/edit/${to}`}>
      <Icon size={20} color="var(--accent)" /><span className="label">{t(title)}</span>
      {done ? <CheckCircle2 size={20} color="var(--positive)" /> : <Circle size={20} className="secondary" />}
    </Item>
  );
  return (
    <main className="page narrow">
      <PageHead title={isApplication ? "Studio application" : "Edit studio"}
        leading={!app.ownedStudio ? <ToolButton title="Sign out" onClick={() => app.signOut()} /> : undefined}
        actions={<SaveButton after={() => navigate(isApplication ? "/studio" : "/studio/listing")} />} />
      <div className="stack-lg">
        {isApplication && (
          <div className="stack" style={{ gap: 6 }}>
            <h1 className="title-m bold">{t("List your studio")}</h1>
            <p className="secondary" style={{ margin: 0 }}>{t("Fill in each section. When you're ready, submit your studio for review – our team usually replies within 1–2 business days.")}</p>
          </div>
        )}
        <Section header="Your listing">
          {link("basics", "Basics & photos", ImageIcon, !!studio.name && studio.photo_urls.length > 0 && studio.description.length >= 40)}
          {link("location", "Address & contact", MapPin, !!studio.address.city && studio.latitude !== 0)}
          {link("pricing", "Prices & services", BadgeEuro, studio.session_types.length > 0)}
          {link("hours", "Opening hours", Clock, !studio.opening_hours.every((h) => h.is_closed))}
          {link("features", "Facilities, gear & genres", SlidersVertical, studio.genres.length > 0 && studio.facilities.length > 0)}
          {link("policy", "Booking settings & rules", Bolt, true)}
          {link("payouts", "Payout details", Landmark, true)}
        </Section>
        {isApplication && problems.length > 0 && (
          <Section header="Still missing">{problems.map((p) => <Item key={p}><Notice icon={CircleAlert} color="var(--warning)">{t(p)}</Notice></Item>)}</Section>
        )}
        {isApplication && <SaveAndContinue />}
      </div>
    </main>
  );
}

function SaveAndContinue() {
  const navigate = useNavigate();
  const { save, saving } = useSave();
  return <button className="btn primary block" disabled={saving} onClick={async () => { if (await save()) navigate("/studio"); }}>{saving ? <Spinner /> : t("Save")}</button>;
}

/** A section page with its own Save (back to where the owner came from). */
function SectionPage({ title, children }: { title: string; children: React.ReactNode }) {
  const navigate = useNavigate();
  return (
    <main className="page narrow">
      <PageHead title={title} actions={<SaveButton after={() => navigate(-1)} />} />
      <div className="stack-lg">{children}<BottomSave /></div>
    </main>
  );
}

function BottomSave() {
  const navigate = useNavigate();
  const { save, saving } = useSave();
  return <button className="btn primary block" disabled={saving} onClick={async () => { if (await save()) navigate(-1); }}>{saving ? <Spinner /> : t("Save")}</button>;
}

function Basics() {
  const toast = useToast();
  const [studio, set] = useDraft();
  const [uploading, setUploading] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  async function upload(files: FileList) {
    setUploading(true);
    for (const file of Array.from(files).slice(0, 10)) {
      try {
        const url = await api.uploadImage(await compressImage(file, 1600), `studios/${studio.id}`);
        set({ ...store.get()!, photo_urls: [...store.get()!.photo_urls, url] });
      } catch (e) { toast(userMessage(e)); }
    }
    setUploading(false);
  }
  return (
    <SectionPage title="Basics & photos">
      <Section header="Name">
        <InputItem placeholder="Studio name" value={studio.name} onChange={(name) => set({ ...studio, name })} />
        <InputItem placeholder="Tagline, e.g. “Warm analog vocals in Exarchia”" value={studio.tagline} onChange={(tagline) => set({ ...studio, tagline })} />
      </Section>
      <Section header="Description" footer={format("%lld characters (min. 40)", studio.description.length)} translate={false}>
        <InputItem multiline rows={7} placeholder="Describe the rooms, the vibe, who you work with…" value={studio.description} onChange={(description) => set({ ...studio, description })} />
      </Section>
      <Section header="Photos & video" footer="The first photo is your cover. Show the live room, control room and booth.">
        <Item>
          <div className="row" style={{ overflowX: "auto", gap: 8, paddingBottom: 4 }}>
            {studio.photo_urls.map((url) => (
              <div key={url} style={{ position: "relative", flexShrink: 0 }}>
                <img src={url} alt="" style={{ width: 120, height: 90, objectFit: "cover", borderRadius: 10 }} />
                <button onClick={() => set({ ...studio, photo_urls: studio.photo_urls.filter((u) => u !== url) })} aria-label={t("Delete")}
                  style={{ position: "absolute", top: 4, right: 4, width: 22, height: 22, borderRadius: 11, background: "rgba(0,0,0,0.6)", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center" }}><X size={12} /></button>
              </div>
            ))}
            <button onClick={() => input.current?.click()} disabled={uploading} style={{ width: 120, height: 90, borderRadius: 10, background: "var(--card)", flexShrink: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 4, color: "var(--accent)" }}>
              {uploading ? <Hourglass size={20} /> : <ImagePlus size={20} />}<span className="caption">{t("Add")}</span>
            </button>
            <input ref={input} type="file" accept="image/*" multiple hidden onChange={(e) => { if (e.target.files?.length) upload(e.target.files); e.target.value = ""; }} />
          </div>
        </Item>
        <InputItem type="url" placeholder="Video link (YouTube, Vimeo…)" value={studio.video_url ?? ""} onChange={(v) => set({ ...studio, video_url: v || null })} />
      </Section>
    </SectionPage>
  );
}

function Location() {
  const [studio, set] = useDraft();
  const [locating, setLocating] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const a = studio.address;
  const setAddress = (patch: Partial<typeof a>) => set({ ...studio, address: { ...a, ...patch } });
  async function locate() {
    setLocating(true);
    const point = await geocode(Studios.singleLine(studio));
    if (point) { set({ ...store.get()!, latitude: point.latitude, longitude: point.longitude }); setMessage(null); }
    else setMessage("We couldn't find that address. Check the spelling.");
    setLocating(false);
  }
  return (
    <SectionPage title="Address & contact">
      <Section header="Address" footer="Artists see the area before booking and the full address after booking.">
        <InputItem placeholder="Street and number" autoComplete="address-line1" value={a.street} onChange={(street) => setAddress({ street })} />
        <InputItem placeholder="Postal code" autoComplete="postal-code" value={a.postal_code} onChange={(postal_code) => setAddress({ postal_code })} />
        <InputItem placeholder="City" autoComplete="address-level2" value={a.city} onChange={(city) => setAddress({ city })} />
        <InputItem placeholder="Area / neighbourhood" value={a.area} onChange={(area) => setAddress({ area })} />
        <InputItem placeholder="Country" autoComplete="country-name" value={a.country} onChange={(country) => setAddress({ country })} />
      </Section>
      <Section>
        <Item onClick={locating || !a.city ? undefined : locate}><SearchCheck size={20} color={locating || !a.city ? "var(--text-2)" : "var(--accent)"} /><span className="label" style={{ color: locating || !a.city ? "var(--text-2)" : "var(--accent)" }}>{t(locating ? "Finding…" : "Find on map")}</span></Item>
        {(studio.latitude !== 0 || studio.longitude !== 0) && <div style={{ padding: 0 }}><StudioMap key={`${studio.latitude},${studio.longitude}`} height={200} center={studio} interactive={false} pins={[{ id: studio.id, point: studio, label: studio.name || t("Studio") }]} /></div>}
        {message && <Item><span className="footnote secondary">{t(message)}</span></Item>}
      </Section>
      <Section header="Contact">
        <InputItem type="tel" placeholder="Phone" autoComplete="tel" value={studio.contact.phone} onChange={(phone) => set({ ...studio, contact: { ...studio.contact, phone } })} />
        <InputItem type="email" placeholder="Email" autoComplete="email" value={studio.contact.email} onChange={(email) => set({ ...studio, contact: { ...studio.contact, email } })} />
        <InputItem type="url" placeholder="Website" value={studio.contact.website} onChange={(website) => set({ ...studio, contact: { ...studio.contact, website } })} />
      </Section>
    </SectionPage>
  );
}

function MoneyInput({ title, amount, currency, onChange }: { title: string; amount: number; currency: string; onChange: (n: number) => void }) {
  const [text, setText] = useState(Money.editable(amount));
  return (
    <Item>
      <span className="label">{t(title)}</span>
      <input type="text" inputMode="decimal" value={text} placeholder="0" style={{ width: 90, flex: "0 0 auto", textAlign: "right" }} onChange={(e) => { setText(e.target.value); const p = Money.parse(e.target.value); if (p != null) onChange(p); }} />
      <span className="secondary">{currency}</span>
    </Item>
  );
}

function Pricing() {
  const [studio, set] = useDraft();
  const updateType = (i: number, patch: Partial<Studio["session_types"][number]>) => set({ ...studio, session_types: studio.session_types.map((x, j) => (j === i ? { ...x, ...patch } : x)) });
  const updateAddOn = (i: number, patch: Partial<Studio["add_ons"][number]>) => set({ ...studio, add_ons: studio.add_ons.map((x, j) => (j === i ? { ...x, ...patch } : x)) });
  return (
    <>
      <Section><SelectItem title="Currency" value={studio.currency} translateOptions={false} options={["EUR", "DKK", "SEK", "NOK", "GBP", "USD"].map((c) => [c, c] as [string, string])} onChange={(currency) => set({ ...studio, currency })} /></Section>
      <Section header="Session types" footer="e.g. Recording, Recording + engineer, Mixing session, Podcast, Rehearsal.">
        {studio.session_types.map((type, i) => (
          <div key={type.id} style={{ borderBottom: "0.5px solid var(--stroke)" }}>
            <Item><input placeholder={t("Session name")} value={type.name} style={{ fontWeight: 600 }} onChange={(e) => updateType(i, { name: e.target.value })} />
              <button className="danger" onClick={() => set({ ...studio, session_types: studio.session_types.filter((x) => x.id !== type.id) })} aria-label={t("Delete")}><Trash2 size={17} /></button></Item>
            <InputItem placeholder="Short description" value={type.details} onChange={(details) => updateType(i, { details })} />
            <MoneyInput title="Per hour" amount={type.hourly_rate} currency={studio.currency} onChange={(hourly_rate) => updateType(i, { hourly_rate })} />
            <Item><span className="label">{format("Minimum %lld h", type.minimum_hours)}</span><Stepper value={type.minimum_hours} min={1} max={8} onChange={(minimum_hours) => updateType(i, { minimum_hours })} /></Item>
            <ToggleItem title="Engineer included" checked={type.includes_engineer} onChange={(includes_engineer) => updateType(i, { includes_engineer })} />
          </div>
        ))}
        <Item onClick={() => set({ ...studio, session_types: [...studio.session_types, { id: newId(), name: "", details: "", hourly_rate: studio.price_from > 0 ? studio.price_from : 3000, minimum_hours: 1, includes_engineer: false }] })}>
          <Plus size={20} color="var(--accent)" /><span className="label accent">{t("Add session type")}</span>
        </Item>
      </Section>
      <Section header="Mix, mastering, engineer & producer">
        {studio.add_ons.map((addOn, i) => (
          <div key={addOn.id} style={{ borderBottom: "0.5px solid var(--stroke)" }}>
            <SelectItem title="Type" value={addOn.kind} options={ADD_ON_KINDS} onChange={(kind) => updateAddOn(i, { kind })} />
            <Item><input placeholder={t("Name")} value={addOn.name} onChange={(e) => updateAddOn(i, { name: e.target.value })} />
              <button className="danger" onClick={() => set({ ...studio, add_ons: studio.add_ons.filter((x) => x.id !== addOn.id) })} aria-label={t("Delete")}><Trash2 size={17} /></button></Item>
            <MoneyInput title="Price" amount={addOn.price} currency={studio.currency} onChange={(price) => updateAddOn(i, { price })} />
            <div style={{ padding: "8px 12px" }}><Segmented value={addOn.unit} options={PRICE_UNITS.map(([value, label]) => ({ value, label }))} onChange={(unit) => updateAddOn(i, { unit })} /></div>
          </div>
        ))}
        <Item onClick={() => set({ ...studio, add_ons: [...studio.add_ons, { id: newId(), kind: "mixing", name: "Mixing", price: 5000, unit: "per_track" }] })}>
          <Plus size={20} color="var(--accent)" /><span className="label accent">{t("Add service")}</span>
        </Item>
      </Section>
    </>
  );
}

function Hours() {
  const [studio, set] = useDraft();
  useEffect(() => {
    const missing = [1, 2, 3, 4, 5, 6, 7].filter((d) => !studio.opening_hours.some((h) => h.weekday === d));
    if (missing.length) set({ ...studio, opening_hours: [...studio.opening_hours, ...missing.map((weekday) => ({ weekday, is_closed: true, opens_at: 600, closes_at: 1320 }))] });
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  const update = (day: OpeningHours) => set({ ...studio, opening_hours: studio.opening_hours.map((h) => (h.weekday === day.weekday ? day : h)) });
  const options = (from: number, to: number) => {
    const list: [number, string][] = [];
    for (let m = from; m <= to; m += 30) list.push([m, formatMinutes(m) + (m >= 1440 ? " (+1)" : "")]);
    return list;
  };
  return (
    <>
      {OPENING_DISPLAY_ORDER.map((weekday) => {
        const day = studio.opening_hours.find((h) => h.weekday === weekday);
        if (!day) return null;
        return (
          <Section key={weekday} header={weekdayName(weekday)} translate={false}>
            <ToggleItem title="Open" checked={!day.is_closed} onChange={(open) => update({ ...day, is_closed: !open })} />
            {!day.is_closed && <>
              <SelectItem title="Opens" value={day.opens_at} options={options(0, 23 * 60 + 30)} translateOptions={false} onChange={(opens_at) => update({ ...day, opens_at })} />
              <SelectItem title="Closes" value={day.closes_at} options={options(60, 30 * 60)} translateOptions={false} onChange={(closes_at) => update({ ...day, closes_at })} />
            </>}
          </Section>
        );
      })}
      <Section footer="Closing times after midnight (e.g. 02:00) are allowed for late sessions.">
        <Item onClick={() => {
          const monday = studio.opening_hours.find((h) => h.weekday === 2);
          if (monday) set({ ...studio, opening_hours: studio.opening_hours.map((h) => ({ ...h, is_closed: monday.is_closed, opens_at: monday.opens_at, closes_at: monday.closes_at })) });
        }}><span className="label accent">{t("Copy Monday to all days")}</span></Item>
      </Section>
    </>
  );
}

function Features() {
  const [studio, set] = useDraft();
  const [category, setCategory] = useState<EquipmentCategory>("microphone");
  const [item, setItem] = useState("");
  return (
    <SectionPage title="Facilities & gear">
      <Section header="Capacity"><Item><span className="label">{format("Up to %lld people", studio.capacity)}</span><Stepper value={studio.capacity} min={1} max={60} onChange={(capacity) => set({ ...studio, capacity })} /></Item></Section>
      <Section header="Facilities"><Item><ChipPicker items={FACILITIES} selected={studio.facilities} onChange={(v) => set({ ...studio, facilities: FACILITIES.map(([k]) => k).filter((k) => v.includes(k)) })} /></Item></Section>
      <Section header="Genres you work with"><Item><ChipPicker items={GENRES} selected={studio.genres} onChange={(v) => set({ ...studio, genres: GENRES.map(([k]) => k).filter((k) => v.includes(k)) })} /></Item></Section>
      <Section header="Equipment & microphones">
        {EQUIPMENT_CATEGORIES.map(([cat, title]) => {
          const items = studio.equipment.filter((e) => e.category === cat);
          return items.length ? (
            <Item key={cat}>
              <div className="stack grow" style={{ gap: 4 }}>
                <div className="caption bold secondary">{t(title)}</div>
                {items.map((e) => <div key={e.id} className="row"><span className="grow">{e.name}</span><button onClick={() => set({ ...studio, equipment: studio.equipment.filter((x) => x.id !== e.id) })} aria-label={t("Delete")}><MinusCircle size={20} color="var(--red)" /></button></div>)}
              </div>
            </Item>
          ) : null;
        })}
        <SelectItem title="Category" value={category} options={EQUIPMENT_CATEGORIES} onChange={setCategory} />
        <Item>
          <input placeholder={t("e.g. Neumann U87 Ai")} value={item} onChange={(e) => setItem(e.target.value)} />
          <button className="link-btn" disabled={!item.trim()} onClick={() => { set({ ...studio, equipment: [...studio.equipment, { id: newId(), category, name: item.trim() }] }); setItem(""); }}>{t("Add")}</button>
        </Item>
      </Section>
      <Section header="Engineers & producers">
        {studio.engineers.map((p, i) => {
          const update = (patch: Partial<typeof p>) => set({ ...studio, engineers: studio.engineers.map((x, j) => (j === i ? { ...x, ...patch } : x)) });
          return (
            <div key={p.id} style={{ borderBottom: "0.5px solid var(--stroke)" }}>
              <Item><input placeholder={t("Name")} value={p.name} style={{ fontWeight: 600 }} onChange={(e) => update({ name: e.target.value })} /><button className="danger" onClick={() => set({ ...studio, engineers: studio.engineers.filter((x) => x.id !== p.id) })} aria-label={t("Delete")}><Trash2 size={17} /></button></Item>
              <InputItem placeholder="Role (Engineer, Producer…)" value={p.role} onChange={(role) => update({ role })} />
              <InputItem placeholder="Short bio" value={p.bio} onChange={(bio) => update({ bio })} />
            </div>
          );
        })}
        <Item onClick={() => set({ ...studio, engineers: [...studio.engineers, { id: newId(), name: "", role: "Engineer", bio: "" }] })}><UserPlus size={20} color="var(--accent)" /><span className="label accent">{t("Add person")}</span></Item>
      </Section>
    </SectionPage>
  );
}

function Policy() {
  const [studio, set] = useDraft();
  const [rule, setRule] = useState("");
  const p = studio.booking_policy;
  const update = (patch: Partial<typeof p>) => set({ ...studio, booking_policy: { ...p, ...patch } });
  return (
    <>
      <Section header="How artists book" footer={p.instant_book ? "Artists are confirmed immediately when they book." : "You accept or decline each request within 24 hours; unanswered requests expire. Card payments are only charged when you accept."}>
        <Item onClick={() => update({ instant_book: true })}><Bolt size={20} color="var(--accent)" /><span className="label">{t("Instant booking")}</span>{p.instant_book && <Check size={18} color="var(--accent)" />}</Item>
        <Item onClick={() => update({ instant_book: false })}><Hourglass size={20} color="var(--accent)" /><span className="label">{t("Request – I approve within 24 hours")}</span>{!p.instant_book && <Check size={18} color="var(--accent)" />}</Item>
      </Section>
      <Section header="House rules">
        {studio.rules.map((r, i) => <Item key={i}><span className="label">{r}</span><button onClick={() => set({ ...studio, rules: studio.rules.filter((_, j) => j !== i) })} aria-label={t("Delete")}><Trash2 size={17} className="danger" /></button></Item>)}
        <Item><input placeholder={t("Add a rule")} value={rule} onChange={(e) => setRule(e.target.value)} /><button className="link-btn" disabled={!rule.trim()} onClick={() => { set({ ...studio, rules: [...studio.rules, rule.trim()] }); setRule(""); }}>{t("Add")}</button></Item>
      </Section>
      <Section>
        <SelectItem title="Cancellation policy" value={p.cancellation_policy} options={(Object.keys(CANCELLATION) as CancellationPolicy[]).map((k) => [k, CANCELLATION[k].title])} onChange={(cancellation_policy) => update({ cancellation_policy })} />
        <Item><span className="footnote secondary">{t(CANCELLATION[p.cancellation_policy].summary)}</span></Item>
      </Section>
      <Section footer="With a deposit, the rest is charged automatically after the session.">
        <SelectItem title="Deposit" value={p.deposit_percent} translateOptions={false}
          options={[[0, t("No deposit – full payment")], ...[20, 30, 50].map((n) => [n, format("%lld%% deposit", n)] as [number, string])]}
          onChange={(deposit_percent) => update({ deposit_percent, accepts_cash: deposit_percent > 0 ? false : p.accepts_cash })} />
      </Section>
      <Section translate={false} footer={p.deposit_percent > 0 ? t("Cash isn't available when you require a deposit.") : format("Artists can choose to pay you in cash at the session. EasySesh's %lld%% platform fee on cash bookings is deducted from your next payout or invoiced monthly. Cash bookings have no card guarantee for no-shows.", Studios.feePercent(studio))}>
        <ToggleItem title="Accept cash payments" checked={p.accepts_cash} disabled={p.deposit_percent > 0} onChange={(accepts_cash) => update({ accepts_cash })} />
      </Section>
      <Section header="Check-in" footerColor={p.check_in_enabled ? undefined : "var(--warning)"}
        footer={p.check_in_enabled ? "Recommended. Artists can check in in the app when they arrive and you can confirm it. It protects both of you against fraud and helps EasySesh settle disputes." : "Check-in is off. EasySesh can't promise artists a refund if something goes wrong, and artists see this before they book. Disputes are decided on the other evidence available."}>
        <ToggleItem title="Check-in on arrival" icon={LocateFixed} checked={p.check_in_enabled} onChange={(check_in_enabled) => update({ check_in_enabled })} />
      </Section>
      <Section header="Scheduling">
        <Item><span className="label">{format("Min. notice: %lld h", p.minimum_notice_hours)}</span><Stepper value={p.minimum_notice_hours} min={0} max={72} onChange={(minimum_notice_hours) => update({ minimum_notice_hours })} /></Item>
        <Item><span className="label">{format("Book up to %lld days ahead", p.max_advance_days)}</span><Stepper value={p.max_advance_days} min={7} max={365} step={7} onChange={(max_advance_days) => update({ max_advance_days })} /></Item>
        <Item><span className="label">{format("Buffer between sessions: %lld min", p.buffer_minutes)}</span><Stepper value={p.buffer_minutes} min={0} max={120} step={15} onChange={(buffer_minutes) => update({ buffer_minutes })} /></Item>
      </Section>
      <Section header="Booking terms"><InputItem multiline rows={4} placeholder="Overtime, damage, guests, recording rights…" value={p.terms} onChange={(terms) => update({ terms })} /></Section>
    </>
  );
}

/** Payout details from the application: a new application is saved as a draft first. */
function ApplicationPayouts() {
  const app = useApp();
  const [studio] = useDraft();
  const { save } = useSave();
  const isApplication = !app.ownedStudio || !["approved", "suspended"].includes(app.ownedStudio.status);
  return <PayoutPage studioId={studio.id} prepare={isApplication ? async () => { if (!(await save())) throw new Error(t("Something went wrong. Please try again.")); } : undefined} />;
}

