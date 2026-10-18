// Studio payout details (bank + Stripe identity check), promotion status and the artist-profile link.
import { useCallback, useEffect, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { ArrowRight, ArrowUpToLine, BadgeCheck, Info, Landmark, LockKeyhole, Megaphone, IdCard, Search, ShieldCheck, TriangleAlert, UserCheck, UserRound, Link2 } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { PlatformConfig } from "../lib/config";
import { Dates, Money, Studios } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { PROMOTION_PACKAGE_TITLE, PROMOTION_STATUS_TITLE, type ArtistProfile, type ArtistSearchResult, type PayoutAccount, type StudioArtistLink, type StudioPromotion } from "../lib/types";
import { AdminBadge, Avatar, C, Empty, GlowHead, IconTile, Item, ItemLabel, Loading, PageHead, PromotedTag, PulseDot, Section, Spinner, StatusPill, Tiles, VerifiedBadge, useToast } from "../components/ui";
import { getStripe } from "./BookingFlow";

// MARK: Payouts

/** Letters and digits only, upper-cased ("dk50 0040 0440…" → "DK500040…"). */
const normalizeIban = (iban: string) => iban.toUpperCase().replace(/[^A-Z0-9]/g, "");

/** Standard IBAN checksum (mod 97), so typos are caught before asking Stripe. */
export function isValidIban(iban: string): boolean {
  const value = normalizeIban(iban);
  if (value.length < 15 || value.length > 34 || !/^[A-Z]{2}/.test(value)) return false;
  const rearranged = value.slice(4) + value.slice(0, 4);
  let remainder = 0;
  for (const ch of rearranged) {
    const digits = /[A-Z]/.test(ch) ? String(ch.charCodeAt(0) - 55) : ch;
    for (const d of digits) remainder = (remainder * 10 + Number(d)) % 97;
  }
  return remainder === 1;
}

const CURRENCY: Record<string, string> = { DK: "dkk", SE: "sek", NO: "nok", GB: "gbp", PL: "pln", CH: "chf" };

export function PayoutPage({ studioId, prepare }: { studioId?: string; prepare?: () => Promise<void> }) {
  const app = useApp();
  const toast = useToast();
  const [params] = useSearchParams();
  const id = studioId ?? app.ownedStudio!.id;
  const [account, setAccount] = useState<PayoutAccount | null | undefined>(undefined);
  const [holder, setHolder] = useState("");
  const [iban, setIban] = useState("");
  const [editingBank, setEditingBank] = useState(false);
  const [savingBank, setSavingBank] = useState(false);
  const [opening, setOpening] = useState(false);
  const hasBank = !!account?.iban_last4;
  const ibanOk = isValidIban(iban);

  const load = useCallback(async () => {
    const a = await api.payoutAccount(id).catch(() => null);
    setAccount(a);
    setHolder((h) => h || a?.account_holder || "");
    if (a?.stripe_account_id) api.syncPayoutAccount(id).then((synced) => { if (synced) setAccount(synced); }).catch(() => undefined);
  }, [id]);
  // Coming back from Stripe's pages (?stripe=done) re-reads the status.
  useEffect(() => { load(); }, [load, params]);

  async function saveBank() {
    setSavingBank(true);
    try {
      await prepare?.();
      const stripe = await getStripe();
      if (!stripe) throw new Error("Stripe is not configured.");
      const number = normalizeIban(iban);
      const { token, error } = await stripe.createToken("bank_account", {
        country: number.slice(0, 2), currency: CURRENCY[number.slice(0, 2)] ?? "eur", account_number: number,
        account_holder_name: holder.trim(), account_holder_type: "individual",
      });
      if (error || !token) throw new Error(error?.message ?? "Stripe request failed.");
      setAccount(await api.savePayoutBank(id, holder.trim(), token.id));
      setIban("");
      setEditingBank(false);
    } catch (e) { toast(userMessage(e)); }
    setSavingBank(false);
  }

  async function openStripe() {
    setOpening(true);
    try {
      await prepare?.();
      const url = await api.payoutOnboardingUrl(id, holder.trim());
      // Stripe's identity check opens in this tab and sends the studio back here when done.
      if (url) window.location.href = url;
    } catch (e) { toast(userMessage(e)); }
    setOpening(false);
  }

  if (account === undefined) return <main className="page narrow"><PageHead title="Payout details" /><Loading /></main>;
  return (
    <main className="page narrow">
      <PageHead title="Payout details" />
      <div className="stack-lg">
        <Section footer={format("You're paid only after a session is completed: payouts are sent %lld days after each completed session, minus EasySesh's %lld%% platform fee. Platform fees for cash bookings are deducted from the same payouts.",
          PlatformConfig.PAYOUT_DELAY_DAYS, app.ownedStudio ? Studios.feePercent(app.ownedStudio) : PlatformConfig.PLATFORM_FEE_PERCENT)} translate={false}>
          <Item>
            {account?.payouts_enabled ? <><BadgeCheck color="var(--positive)" /><span className="label positive">{account.iban_last4 ? format("Payouts enabled to •••• %@", account.iban_last4) : t("Payouts enabled")}</span></>
              : hasBank ? <><UserCheck color="var(--warning)" /><span className="label warning">{t("Bank added – confirm your identity to receive payouts")}</span></>
              : <><TriangleAlert color="var(--warning)" /><span className="label warning">{t("Payouts not set up yet")}</span></>}
          </Item>
        </Section>
        <Section header="Bank account" footer="Your bank details go straight to Stripe, our payment provider. EasySesh only keeps the last 4 digits.">
          {hasBank && !editingBank ? (
            <>
              <Item><Landmark size={20} color="var(--accent)" /><span className="label">{format("Bank account •••• %@", account!.iban_last4)}</span><button className="link-btn" onClick={() => setEditingBank(true)}>{t("Change")}</button></Item>
              {account!.account_holder && <Item><span className="footnote secondary">{account!.account_holder}</span></Item>}
            </>
          ) : (
            <>
              <Item><input placeholder={t("Account holder / company name")} autoComplete="name" value={holder} onChange={(e) => setHolder(e.target.value)} /></Item>
              <Item><input className="mono" placeholder={t("IBAN, e.g. DK50 0040 0440 1162 43")} value={iban} autoCapitalize="characters" autoCorrect="off" onChange={(e) => setIban(e.target.value)} /></Item>
              {iban && !ibanOk && <Item><span className="footnote warning">{t("Check the IBAN – it doesn't look right yet.")}</span></Item>}
              <Item onClick={savingBank || !holder.trim() || !ibanOk ? undefined : saveBank}><ItemLabel title={savingBank ? "Saving…" : "Save bank account"} icon={LockKeyhole} color={savingBank || !holder.trim() || !ibanOk ? "var(--text-2)" : "var(--accent)"} /></Item>
              {hasBank && <Item onClick={() => { setEditingBank(false); setIban(""); }}><span className="label secondary">{t("Cancel")}</span></Item>}
            </>
          )}
        </Section>
        <Section header="Identity check" footer="Required by law once: Stripe confirms who you are (name, date of birth, address and sometimes a photo ID). It opens right here in the app.">
          {account?.payouts_enabled ? <Item><ShieldCheck color="var(--positive)" /><span className="label positive">{t("Identity confirmed")}</span></Item> : (
            <Item onClick={opening || !hasBank ? undefined : openStripe}>
              <ItemLabel title={opening ? "Opening…" : "Confirm identity"} icon={IdCard} color={opening || !hasBank ? "var(--text-2)" : "var(--accent)"} />{opening && <Spinner size={18} />}
            </Item>
          )}
        </Section>
      </div>
    </main>
  );
}

// MARK: Promotion

/**
 * A studio's promotion status: a "Promoted" tag and a place at the top of search for a period.
 * Promotions are granted by the EasySesh team (admin panel); the app doesn't sell them.
 */
export function PromotionPage() {
  const app = useApp();
  const toast = useToast();
  const studio = app.ownedStudio!;
  const [promotions, setPromotions] = useState<StudioPromotion[]>([]);
  useEffect(() => { api.promotions(studio.id).then(setPromotions).catch((e) => toast(userMessage(e))); }, [studio.id, toast]);
  const active = promotions.find((p) => p.status === "active");
  const history = promotions.filter((p) => p.status !== "pending" && p.status !== "active");
  const end = active?.ends_at ?? studio.promoted_until;
  return (
    <main className="page narrow">
      <PageHead title="Promote" />
      <div className="stack">
        <div className="card big">
          <div className="row"><IconTile icon={Megaphone} size={48} /><div><div style={{ fontSize: 26, fontWeight: 800 }}>{t("Get seen first")}</div><div className="subhead secondary">{t("Promoted studios are shown at the top of Discover and search, with a Promoted tag.")}</div></div></div>
          <div className="row caption semibold secondary" style={{ gap: 8, marginTop: 12 }}><PromotedTag /><ArrowRight size={12} /><ArrowUpToLine size={12} />{t("Top of results")}</div>
        </div>
        {active ? (
          <div className="card row">
            <PulseDot color={C.positive} />
            <div className="grow"><div className="headline">{t("Your studio is promoted")}</div>{end && <div className="subhead secondary">{format("Until %@", Dates.abbreviatedWithTime(end))}</div>}</div>
            <PromotedTag />
          </div>
        ) : <div className="card row subhead secondary" style={{ gap: 8 }}><Info size={16} />{t("Your studio isn't promoted right now.")}</div>}
        {history.length > 0 && <GlowHead title="History" count={history.length} />}
        {history.map((p) => (
          <div key={p.id} className="card tight row">
            <div className="grow"><div className="subhead semibold">{t(PROMOTION_PACKAGE_TITLE[p.package] ?? "Promotion")}</div><div className="caption secondary">{Dates.abbreviated(p.created_at)}</div></div>
            <span className="subhead">{Money.format(p.amount, p.currency)}</span>
            <StatusPill text={PROMOTION_STATUS_TITLE[p.status]} color={p.status === "expired" ? C.secondary : C.red} />
          </div>
        ))}
      </div>
    </main>
  );
}

// MARK: Artist profile link

/** A studio shows its owner's artist profile on its page (and the studio on the artist profile) once the artist confirms. */
export function ArtistLinkPage() {
  const app = useApp();
  const toast = useToast();
  const studio = app.ownedStudio!;
  const [link, setLink] = useState<StudioArtistLink | null | undefined>(undefined);
  const [artist, setArtist] = useState<ArtistProfile | null>(null);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<ArtistSearchResult[]>([]);
  const [working, setWorking] = useState(false);
  useEffect(() => {
    api.studioArtistLink(studio.id).then(async (l) => { setLink(l); if (l) setArtist(await api.artistProfile(l.artist_id).catch(() => null)); }).catch((e) => { toast(userMessage(e)); setLink(null); });
  }, [studio.id, toast]);
  useEffect(() => {
    if (query.length < 2) { setResults([]); return; }
    const timer = window.setTimeout(() => api.searchArtists(query).then(setResults).catch(() => setResults([])), 250);
    return () => window.clearTimeout(timer);
  }, [query]);
  async function request(a: ArtistSearchResult) {
    setWorking(true);
    try { setLink(await api.requestStudioArtistLink(a.id)); setArtist(await api.artistProfile(a.id).catch(() => null)); } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  }
  async function remove() {
    setWorking(true);
    try { await api.removeStudioArtistLink(studio.id); setLink(null); setArtist(null); } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  }
  return (
    <main className="page narrow">
      <PageHead title="Artist profile" />
      <div className="stack">
        <div className="row top"><IconTile icon={Link2} size={48} colors={Tiles.violet} /><div><div style={{ fontSize: 26, fontWeight: 800 }}>{t("Your artist profile")}</div><div className="subhead secondary">{t("Are you an artist too? Connect your artist profile: it's shown on your studio page, and your studio on your artist profile.")}</div></div></div>
        {link === undefined ? <Loading /> : link ? (
          <div className="card stack">
            <div className="row"><Avatar url={artist?.avatar_url} name={artist?.artist_name ?? "?"} size={48} /><div><div className="headline">{artist?.artist_name ?? "…"}</div><div className="caption" style={{ color: link.status === "accepted" ? "var(--positive)" : "var(--text-2)" }}>{t(link.status === "accepted" ? "Connected" : "Waiting for the artist to confirm in their profile")}</div></div></div>
            {link.status === "accepted" && <Link to={`/artists/${link.artist_id}`} className="row subhead semibold accent" style={{ gap: 6 }}><UserRound size={16} />{t("View artist profile")}</Link>}
            <button className="btn danger block" disabled={working} onClick={remove}>{t(link.status === "accepted" ? "Remove connection" : "Cancel request")}</button>
          </div>
        ) : (
          <>
            <label className="field"><Search size={18} /><input placeholder={t("Search your artist name")} value={query} onChange={(e) => setQuery(e.target.value)} autoCapitalize="none" /></label>
            <div className="caption secondary">{t("The artist has to confirm the connection from their profile, so only your own profile can be connected.")}</div>
            {query.length >= 2 && results.length === 0 && <Empty icon={Search} title="No artists found." />}
            {results.map((a) => (
              <div key={a.id} className="card tight row">
                <Avatar url={a.avatar_url} name={a.artist_name} size={42} />
                <div className="grow"><div className="row subhead semibold" style={{ gap: 4 }}>{a.artist_name}{a.is_verified && <VerifiedBadge />}{a.has_admin_badge && <AdminBadge compact />}</div>{a.city && <div className="caption secondary">{a.city}</div>}</div>
                <button className="btn primary small" disabled={working} onClick={() => request(a)}>{t("Connect")}</button>
              </div>
            ))}
          </>
        )}
      </div>
    </main>
  );
}
