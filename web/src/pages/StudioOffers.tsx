// Studio offers ("Mixing 50% off", applied automatically) and the studio's own promo codes.
// Both come off the studio's price; EasySesh's 10% is taken from the discounted price.
import { useCallback, useEffect, useState } from "react";
import { BadgePercent, CalendarClock, Plus, Tag, Ticket, Trash2, Users } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { Dates } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import type { OfferTarget, PromoCode, Studio, StudioOffer } from "../lib/types";
import { ConfirmDialog, InputItem, Item, ItemLabel, PageHead, Section, SelectItem, Sheet, Spinner, Stepper, Toggle, ToolButton, useToast } from "../components/ui";
import { offerTargetName } from "./BookingFlow";

const TARGETS: [OfferTarget, string][] = [
  ["everything", "Everything"], ["sessions", "All sessions"], ["add_ons", "All extras"], ["session_type", "One session type"], ["add_on", "One extra"],
];

/** "2026-11-30" for <input type="date">, and back to the end of that day. */
const dayValue = (iso: string | null) => (iso ? iso.slice(0, 10) : "");
const endOfDay = (value: string) => (value ? new Date(`${value}T23:59:59`).toISOString() : null);

export default function StudioOffersPage() {
  const app = useApp();
  const toast = useToast();
  const studio = app.ownedStudio!;
  const [offers, setOffers] = useState<StudioOffer[] | null>(null);
  const [codes, setCodes] = useState<PromoCode[] | null>(null);
  const [editingOffer, setEditingOffer] = useState<Partial<StudioOffer> | null>(null);
  const [editingCode, setEditingCode] = useState<Partial<PromoCode> | null>(null);
  const [removing, setRemoving] = useState<{ kind: "offer" | "code"; id: string } | null>(null);

  const reload = useCallback(() => {
    api.studioOffers(studio.id).then(setOffers).catch((e) => toast(userMessage(e)));
    api.promoCodes(studio.id).then(setCodes).catch((e) => toast(userMessage(e)));
  }, [studio.id, toast]);
  useEffect(reload, [reload]);

  async function toggleOffer(offer: StudioOffer, on: boolean) {
    try { await api.saveOffer({ ...offer, is_active: on }); reload(); } catch (e) { toast(userMessage(e)); }
  }
  async function toggleCode(code: PromoCode, on: boolean) {
    try { await api.savePromoCode({ id: code.id, studio_id: studio.id, is_active: on }); reload(); } catch (e) { toast(userMessage(e)); }
  }
  async function remove() {
    if (!removing) return;
    try {
      if (removing.kind === "offer") await api.removeOffer(removing.id); else await api.removePromoCode(removing.id);
      reload();
    } catch (e) { toast(userMessage(e)); }
  }

  const expired = (end: string | null) => !!end && new Date(end) <= new Date();

  return (
    <main className="page narrow">
      <PageHead title="Offers & promo codes" />
      <div className="stack">
        <Section header="Offers" footer="Offers are applied automatically when artists book, and shown on your studio page. If several match, the biggest one is used."
          translate>
          {offers === null ? <Item><Spinner /></Item> : offers.length === 0 ? (
            <Item><span className="secondary">{t("No offers yet. For example: Mixing 50% off.")}</span></Item>
          ) : offers.map((o) => (
            <Item key={o.id}>
              <BadgePercent size={20} color="var(--accent)" style={{ flexShrink: 0 }} />
              <div className="label pressable" onClick={() => setEditingOffer(o)}>
                <div className="semibold">{o.title} · −{o.percent_off}%</div>
                <div className="caption secondary">{offerTargetName(o, studio)}{o.ends_at ? " · " + (expired(o.ends_at) ? t("Ended") : format("Until %@", Dates.abbreviated(o.ends_at))) : ""}</div>
              </div>
              <Toggle checked={o.is_active} onChange={(on) => toggleOffer(o, on)} label={o.title} />
              <button className="tool-btn" aria-label={t("Delete")} onClick={() => setRemoving({ kind: "offer", id: o.id })}><Trash2 size={18} /></button>
            </Item>
          ))}
          <Item onClick={() => setEditingOffer({ title: "", percent_off: 20, applies_to: "everything", target_id: null, ends_at: null, is_active: true })}>
            <ItemLabel title="New offer" icon={Plus} color="var(--accent)" />
          </Item>
        </Section>

        <Section header="Promo codes" footer="Give a code to artists (on social media, to regulars…). They type it in at checkout to get the discount." translate>
          {codes === null ? <Item><Spinner /></Item> : codes.length === 0 ? (
            <Item><span className="secondary">{t("No promo codes yet.")}</span></Item>
          ) : codes.map((c) => (
            <Item key={c.id}>
              <Ticket size={20} color="var(--accent)" style={{ flexShrink: 0 }} />
              <div className="label pressable" onClick={() => setEditingCode(c)}>
                <div className="semibold mono">{c.code} · −{c.percent_off}%</div>
                <div className="caption secondary">
                  {c.max_uses ? format("Used %lld of %lld", c.uses ?? 0, c.max_uses) : format("Used %lld times", c.uses ?? 0)}
                  {c.ends_at ? " · " + (expired(c.ends_at) ? t("Ended") : format("Until %@", Dates.abbreviated(c.ends_at))) : ""}
                </div>
              </div>
              <Toggle checked={c.is_active} onChange={(on) => toggleCode(c, on)} label={c.code} />
              <button className="tool-btn" aria-label={t("Delete")} onClick={() => setRemoving({ kind: "code", id: c.id })}><Trash2 size={18} /></button>
            </Item>
          ))}
          <Item onClick={() => setEditingCode({ code: "", percent_off: 10, max_uses: null, max_uses_per_user: 1, ends_at: null, description: "", is_active: true })}>
            <ItemLabel title="New promo code" icon={Plus} color="var(--accent)" />
          </Item>
        </Section>
        <p className="footnote secondary" style={{ margin: "0 4px" }}>{t("Discounts come off your price. EasySesh's platform fee is calculated on the discounted price.")}</p>
      </div>

      {editingOffer && <OfferSheet studio={studio} offer={editingOffer} onClose={() => setEditingOffer(null)} onSaved={() => { setEditingOffer(null); reload(); }} />}
      {editingCode && <CodeSheet studio={studio} code={editingCode} onClose={() => setEditingCode(null)} onSaved={() => { setEditingCode(null); reload(); }} />}
      <ConfirmDialog open={!!removing} title={removing?.kind === "offer" ? "Delete this offer?" : "Delete this promo code?"} onClose={() => setRemoving(null)}
        actions={[{ title: "Delete", destructive: true, action: remove }]} />
    </main>
  );
}

function OfferSheet({ studio, offer, onClose, onSaved }: { studio: Studio; offer: Partial<StudioOffer>; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [draft, setDraft] = useState(offer);
  const [saving, setSaving] = useState(false);
  const targets: [string, string][] = draft.applies_to === "session_type"
    ? studio.session_types.map((s) => [s.id, s.name])
    : draft.applies_to === "add_on" ? studio.add_ons.map((a) => [a.id, a.name]) : [];
  const needsTarget = draft.applies_to === "session_type" || draft.applies_to === "add_on";
  const valid = (draft.title ?? "").trim().length >= 2 && (!needsTarget || !!draft.target_id);

  async function save() {
    setSaving(true);
    try {
      await api.saveOffer({
        id: draft.id, studio_id: studio.id, title: draft.title!.trim(), percent_off: draft.percent_off!, applies_to: draft.applies_to!,
        target_id: needsTarget ? draft.target_id! : null, ends_at: draft.ends_at ?? null, is_active: draft.is_active ?? true,
      });
      onSaved();
    } catch (e) { toast(userMessage(e)); }
    setSaving(false);
  }

  return (
    <Sheet open onClose={onClose} title={draft.id ? "Edit offer" : "New offer"}
      actions={saving ? <Spinner /> : <ToolButton title="Save" bold disabled={!valid} onClick={save} />}>
      <div className="stack">
        <Section header="Offer" footer="Shown to artists, e.g. “Mixing half price” or “Weekday deal”.">
          <InputItem placeholder="Title" value={draft.title ?? ""} onChange={(title) => setDraft({ ...draft, title })} />
          <Item>
            <ItemLabel title="Discount" icon={Tag} />
            <span className="bold">{draft.percent_off}%</span>
            <Stepper value={draft.percent_off ?? 20} min={5} max={90} step={5} onChange={(percent_off) => setDraft({ ...draft, percent_off })} />
          </Item>
        </Section>
        <Section header="Applies to">
          <SelectItem title="Discount on" value={draft.applies_to ?? "everything"} options={TARGETS}
            onChange={(applies_to) => setDraft({ ...draft, applies_to, target_id: null })} />
          {needsTarget && (
            targets.length === 0
              ? <Item><span className="secondary">{t(draft.applies_to === "add_on" ? "Add extras to your prices first." : "Add a session type first.")}</span></Item>
              : <SelectItem title={draft.applies_to === "add_on" ? "Extra" : "Session type"} value={draft.target_id ?? ""} translateOptions={false}
                  options={[["", t("Choose…")], ...targets]} onChange={(target_id) => setDraft({ ...draft, target_id: target_id || null })} />
          )}
        </Section>
        <Section header="Ends" footer="Leave empty to keep the offer until you turn it off.">
          <Item>
            <ItemLabel title="Last day" icon={CalendarClock} />
            <input type="date" value={dayValue(draft.ends_at ?? null)} min={new Date().toISOString().slice(0, 10)} onChange={(e) => setDraft({ ...draft, ends_at: endOfDay(e.target.value) })} />
          </Item>
        </Section>
      </div>
    </Sheet>
  );
}

function CodeSheet({ studio, code, onClose, onSaved }: { studio: Studio; code: Partial<PromoCode>; onClose: () => void; onSaved: () => void }) {
  const toast = useToast();
  const [draft, setDraft] = useState(code);
  const [saving, setSaving] = useState(false);
  const valid = /^[A-Z0-9]{3,20}$/.test(draft.code ?? "");

  async function save() {
    setSaving(true);
    try {
      await api.savePromoCode({
        id: draft.id, studio_id: studio.id, code: draft.code, percent_off: draft.percent_off, description: (draft.description ?? "").trim(),
        max_uses: draft.max_uses || null, max_uses_per_user: draft.max_uses_per_user ?? 1, ends_at: draft.ends_at ?? null, is_active: draft.is_active ?? true,
      });
      onSaved();
    } catch (e) { toast(userMessage(e)); }
    setSaving(false);
  }

  return (
    <Sheet open onClose={onClose} title={draft.id ? "Edit promo code" : "New promo code"}
      actions={saving ? <Spinner /> : <ToolButton title="Save" bold disabled={!valid} onClick={save} />}>
      <div className="stack">
        <Section header="Code" footer="3–20 letters or digits, e.g. SUMMER20.">
          <Item>
            <input className="mono" placeholder="SUMMER20" value={draft.code ?? ""} maxLength={20} autoCapitalize="characters" spellCheck={false}
              onChange={(e) => setDraft({ ...draft, code: e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, "") })} />
          </Item>
          <Item>
            <ItemLabel title="Discount" icon={Tag} />
            <span className="bold">{draft.percent_off}%</span>
            <Stepper value={draft.percent_off ?? 10} min={1} max={90} onChange={(percent_off) => setDraft({ ...draft, percent_off })} />
          </Item>
          <InputItem placeholder="Note for artists (optional)" value={draft.description ?? ""} onChange={(description) => setDraft({ ...draft, description })} />
        </Section>
        <Section header="Limits">
          <Item>
            <ItemLabel title="Uses in total" icon={Ticket} />
            <span className="bold">{draft.max_uses ? draft.max_uses : t("No limit")}</span>
            <Stepper value={draft.max_uses ?? 0} min={0} max={1000} step={draft.max_uses && draft.max_uses >= 10 ? 10 : 1} onChange={(max_uses) => setDraft({ ...draft, max_uses: max_uses || null })} />
          </Item>
          <Item>
            <ItemLabel title="Uses per artist" icon={Users} />
            <span className="bold">{draft.max_uses_per_user ?? 1}</span>
            <Stepper value={draft.max_uses_per_user ?? 1} min={1} max={100} onChange={(max_uses_per_user) => setDraft({ ...draft, max_uses_per_user })} />
          </Item>
          <Item>
            <ItemLabel title="Last day" icon={CalendarClock} />
            <input type="date" value={dayValue(draft.ends_at ?? null)} min={new Date().toISOString().slice(0, 10)} onChange={(e) => setDraft({ ...draft, ends_at: endOfDay(e.target.value) })} />
          </Item>
        </Section>
      </div>
    </Sheet>
  );
}
