// Studio payout details (bank + Stripe identity check), promotions (studio and artist) and the artist-profile link.
import { useCallback, useEffect, useState } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { ArrowRight, ArrowUpToLine, BadgeCheck, Info, Landmark, LockKeyhole, Megaphone, IdCard, Search, ShieldCheck, TriangleAlert, UserCheck, UserRound, Link2 } from "lucide-react";
import { api, userMessage } from "../lib/api";
import { config, PlatformConfig } from "../lib/config";
import { Dates, Money, Studios } from "../lib/core";
import { format, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { PROMOTION_PACKAGE_TITLE, PROMOTION_PACKAGES, PROMOTION_STATUS_TITLE, promotionPrice, type ArtistProfile, type ArtistSearchResult, type PayoutAccount, type StudioArtistLink, type StudioPromotion } from "../lib/types";
import { AdminBadge, Avatar, C, Empty, GlowHead, IconTile, Item, ItemLabel, Loading, PageHead, PromotedTag, PulseDot, Section, Spinner, StatusPill, Tiles, VerifiedBadge, useToast } from "../components/ui";
import { Elements, PaymentElement, useElements, useStripe } from "@stripe/react-stripe-js";
import { getStripe, stripeAppearance } from "./BookingFlow";

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
  const navigate = useNavigate();
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
        {!PlatformConfig.PAYMENTS_LIVE && !account?.payouts_enabled && (
          <div className="card stack" style={{ gap: 10, borderColor: "color-mix(in srgb, var(--primary) 35%, var(--stroke))", background: "color-mix(in srgb, var(--primary) 6%, var(--card))" }}>
            <div className="headline">{t("You can skip this for now")}</div>
            <div className="subhead secondary">{t("Card payments and payouts aren't live yet, so you don't need to set this up to apply or to be approved. When they go live, we'll email you and ask you to add your bank account and confirm your identity before you can receive payouts.")}</div>
            {prepare && <div><button className="btn secondary small" onClick={() => navigate("/studio/edit")}>{t("Skip for now")}</button></div>}
          </div>
        )}
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
 * Promotion for a studio (top of Discover and search, with a Promoted tag) or an artist profile (first
 * in the studios' artist search, with a Promoted tag). Bought here on the website with Stripe; the
 * apps only show the status (App Store / Play rules). The EasySesh team can also grant one.
 */
export function PromotionPage() {
  const app = useApp();
  const studio = app.ownedStudio!;
  return (
    <PromotionScreen
      load={() => api.promotions(studio.id)}
      currency={studio.currency}
      promotedUntil={studio.promoted_until}
      onChanged={async () => app.setOwnedStudio(await api.ownedStudio().catch(() => studio))}
      pitch="Promoted studios are shown at the top of Discover and search, with a Promoted tag."
      activeTitle="Your studio is promoted"
      inactiveTitle="Your studio isn't promoted right now."
      returnPath="/studio/promotion"
    />
  );
}

export function ArtistPromotionPage() {
  const app = useApp();
  const profile = app.artistProfile;
  if (!profile) return <main className="page narrow"><Loading /></main>;
  return (
    <PromotionScreen
      load={() => api.artistPromotions(profile.id)}
      currency="EUR"
      promotedUntil={profile.promoted_until}
      onChanged={async () => app.setArtistProfile(await api.artistProfile(profile.id).catch(() => profile))}
      pitch="Promoted artists are shown first, with a Promoted tag, when studios look for artists to work with."
      activeTitle="Your artist profile is promoted"
      inactiveTitle="Your artist profile isn't promoted right now."
      returnPath="/profile/promotion"
      needsName={!profile.artist_name}
    />
  );
}

function PromotionScreen({ load, currency, promotedUntil, onChanged, pitch, activeTitle, inactiveTitle, returnPath, needsName }: {
  load: () => Promise<StudioPromotion[]>; currency: string; promotedUntil?: string | null; onChanged: () => void | Promise<void>;
  pitch: string; activeTitle: string; inactiveTitle: string; returnPath: string; needsName?: boolean;
}) {
  const toast = useToast();
  const [params, setParams] = useSearchParams();
  const [promotions, setPromotions] = useState<StudioPromotion[]>([]);
  const [pkg, setPkg] = useState<string>("two_weeks");
  const [checkout, setCheckout] = useState<{ promotion: StudioPromotion; clientSecret: string } | null>(null);
  const [working, setWorking] = useState(false);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const reload = useCallback(() => load().then(setPromotions).catch((e) => toast(userMessage(e))), [toast]);
  useEffect(() => { reload(); }, [reload]);

  // Back from a payment method that redirects (e.g. bank apps): finish it here.
  const returned = params.get("promotion");
  useEffect(() => {
    if (!returned) return;
    api.confirmPromotion(returned)
      .then(async () => { toast(t("Payment received – your promotion has started.")); await onChanged(); reload(); })
      .catch((e) => toast(userMessage(e)))
      .finally(() => setParams({}, { replace: true }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [returned]);

  const active = promotions.find((p) => p.status === "active");
  const history = promotions.filter((p) => p.status !== "pending" && p.status !== "active");
  const end = active?.ends_at ?? promotedUntil;
  const cardAvailable = !!config.stripePublishableKey;

  async function buy() {
    setWorking(true);
    try {
      const promotion = await api.requestPromotion(pkg);
      const payment = await api.promotionPayment(promotion.id);
      setCheckout({ promotion, clientSecret: payment.client_secret });
    } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  }
  async function paid() {
    setCheckout(null);
    toast(t("Payment received – your promotion has started."));
    await onChanged();
    reload();
  }
  async function cancel() {
    if (checkout) await api.cancelPromotionRequest(checkout.promotion.id).catch(() => undefined);
    setCheckout(null);
  }

  return (
    <main className="page narrow">
      <PageHead title="Promote" />
      <div className="stack">
        <div className="card big">
          <div className="row"><IconTile icon={Megaphone} size={48} /><div><div style={{ fontSize: 26, fontWeight: 800 }}>{t("Get seen first")}</div><div className="subhead secondary">{t(pitch)}</div></div></div>
          <div className="row caption semibold secondary" style={{ gap: 8, marginTop: 12 }}><PromotedTag /><ArrowRight size={12} /><ArrowUpToLine size={12} />{t("Top of results")}</div>
        </div>
        {active ? (
          <div className="card row">
            <PulseDot color={C.positive} />
            <div className="grow"><div className="headline">{t(activeTitle)}</div>{end && <div className="subhead secondary">{format("Until %@", Dates.abbreviatedWithTime(end))}</div>}</div>
            <PromotedTag />
          </div>
        ) : <div className="card row subhead secondary" style={{ gap: 8 }}><Info size={16} />{t(inactiveTitle)}</div>}

        <GlowHead title={active ? "Extend your promotion" : "Buy a promotion"} />
        {checkout ? (
          <Elements stripe={getStripe()} options={{ clientSecret: checkout.clientSecret, appearance: stripeAppearance() }}>
            <PromotionPaymentForm promotion={checkout.promotion} returnPath={returnPath} onPaid={paid} onCancel={cancel} />
          </Elements>
        ) : (
          <div className="stack">
            {PROMOTION_PACKAGES.map((p) => (
              <button key={p} className={`card tight row pressable${pkg === p ? " selected" : ""}`} style={pkg === p ? { outline: "2px solid var(--primary)" } : undefined} onClick={() => setPkg(p)}>
                <div className="grow" style={{ textAlign: "left" }}><div className="headline">{t(PROMOTION_PACKAGE_TITLE[p])}</div></div>
                <span className="headline">{Money.format(promotionPrice(p, currency), currency)}</span>
              </button>
            ))}
            {active && <div className="caption secondary">{t("A new promotion starts when the current one ends.")}</div>}
            {needsName && <div className="caption" style={{ color: "var(--warning)" }}>{t("Finish your artist profile first.")}</div>}
            <button className="btn primary block" disabled={working || !cardAvailable || needsName} onClick={buy}>
              {working ? <Spinner /> : format("Pay %@", Money.format(promotionPrice(pkg, currency), currency))}
            </button>
            <div className="row caption secondary" style={{ gap: 6 }}><LockKeyhole size={13} />{t(cardAvailable ? "Card, Apple Pay or Google Pay – securely processed by Stripe." : "Card payments aren't available yet. Contact EasySesh support to be promoted.")}</div>
          </div>
        )}

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

function PromotionPaymentForm({ promotion, returnPath, onPaid, onCancel }: { promotion: StudioPromotion; returnPath: string; onPaid: () => void; onCancel: () => void }) {
  const stripe = useStripe();
  const elements = useElements();
  const toast = useToast();
  const [paying, setPaying] = useState(false);
  async function submit() {
    if (!stripe || !elements) return;
    setPaying(true);
    const { error } = await stripe.confirmPayment({
      elements, redirect: "if_required",
      confirmParams: { return_url: `${window.location.origin}${returnPath}?promotion=${promotion.id}` },
    });
    if (error) { toast(format("Payment failed: %@", error.message ?? "")); setPaying(false); return; }
    try { await api.confirmPromotion(promotion.id); onPaid(); } catch (e) { toast(userMessage(e)); }
    setPaying(false);
  }
  return (
    <div className="card stack">
      <div className="row"><div className="grow headline">{t(PROMOTION_PACKAGE_TITLE[promotion.package] ?? "Promotion")}</div><span className="headline">{Money.format(promotion.amount, promotion.currency)}</span></div>
      <PaymentElement options={{ layout: "tabs" }} />
      <button className="btn primary block" disabled={!stripe || paying} onClick={submit}>{paying ? <Spinner /> : format("Pay %@", Money.format(promotion.amount, promotion.currency))}</button>
      <button className="btn block" disabled={paying} onClick={onCancel}>{t("Cancel")}</button>
    </div>
  );
}

// MARK: Artist profiles

/**
 * The artist profiles a studio shows on its page (and the studio on theirs): the owner's own, and
 * co-owners' or in-house artists'. Each artist confirms from their own profile. Up to 10.
 */
export function ArtistLinkPage() {
  const app = useApp();
  const toast = useToast();
  const studio = app.ownedStudio!;
  const [links, setLinks] = useState<StudioArtistLink[] | undefined>(undefined);
  const [artists, setArtists] = useState<Record<string, ArtistProfile>>({});
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<ArtistSearchResult[]>([]);
  const [working, setWorking] = useState(false);
  const [adding, setAdding] = useState(false);

  const load = useCallback(async () => {
    try {
      const list = await api.studioArtistLinks(studio.id);
      setLinks(list);
      const profiles = await Promise.all(list.map((l) => api.artistProfile(l.artist_id).catch(() => null)));
      setArtists(Object.fromEntries(profiles.filter((p): p is ArtistProfile => !!p).map((p) => [p.id, p])));
    } catch (e) { toast(userMessage(e)); setLinks([]); }
  }, [studio.id, toast]);
  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    if (query.length < 2) { setResults([]); return; }
    const timer = window.setTimeout(() => api.searchArtists(query).then(setResults).catch(() => setResults([])), 250);
    return () => window.clearTimeout(timer);
  }, [query]);

  async function request(a: ArtistSearchResult) {
    setWorking(true);
    try { await api.requestStudioArtistLink(a.id); setQuery(""); setAdding(false); await load(); } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  }
  async function remove(link: StudioArtistLink) {
    setWorking(true);
    try { await api.removeStudioArtistLink(studio.id, link.artist_id); await load(); } catch (e) { toast(userMessage(e)); }
    setWorking(false);
  }
  const linkedIds = new Set((links ?? []).map((l) => l.artist_id));
  const showSearch = links !== undefined && (links.length === 0 || adding) && links.length < 10;

  return (
    <main className="page narrow">
      <PageHead title="Artist profiles" />
      <div className="stack">
        <div className="row top"><IconTile icon={Link2} size={48} colors={Tiles.violet} /><div><div style={{ fontSize: 26, fontWeight: 800 }}>{t("Artist profiles")}</div><div className="subhead secondary">{t("Are you artists too? Connect the artist profiles of the people behind the studio (co-owners included): they're shown on your studio page, and your studio on their profiles.")}</div></div></div>
        {links === undefined ? <Loading /> : (
          <>
            {links.map((link) => {
              const artist = artists[link.artist_id];
              return (
                <div key={link.artist_id} className="card stack">
                  <div className="row">
                    <Avatar url={artist?.avatar_url} name={artist?.artist_name ?? "?"} size={48} />
                    <div className="grow"><div className="headline">{artist?.artist_name ?? "…"}</div><div className="caption" style={{ color: link.status === "accepted" ? "var(--positive)" : "var(--text-2)" }}>{t(link.status === "accepted" ? "Connected" : "Waiting for the artist to confirm in their profile")}</div></div>
                    {link.status === "accepted" && <Link to={`/artists/${link.artist_id}`} className="icon-btn" aria-label={t("View artist profile")}><UserRound size={16} /></Link>}
                  </div>
                  <button className="btn danger block" disabled={working} onClick={() => remove(link)}>{t(link.status === "accepted" ? "Remove connection" : "Cancel request")}</button>
                </div>
              );
            })}
            {links.length > 0 && !adding && links.length < 10 && (
              <button className="btn block" onClick={() => setAdding(true)}>{t("Add another artist profile")}</button>
            )}
            {showSearch && (
              <>
                <label className="field"><Search size={18} /><input placeholder={t("Search by artist name")} value={query} onChange={(e) => setQuery(e.target.value)} autoCapitalize="none" autoFocus={adding} /></label>
                <div className="caption secondary">{t("Each artist has to confirm the connection from their own profile.")}</div>
                {query.length >= 2 && results.length === 0 && <Empty icon={Search} title="No artists found." />}
                {results.filter((a) => !linkedIds.has(a.id)).map((a) => (
                  <div key={a.id} className="card tight row">
                    <Avatar url={a.avatar_url} name={a.artist_name} size={42} />
                    <div className="grow"><div className="row subhead semibold" style={{ gap: 4 }}>{a.artist_name}{a.is_verified && <VerifiedBadge />}{a.has_admin_badge && <AdminBadge compact />}</div>{a.city && <div className="caption secondary">{a.city}</div>}</div>
                    <button className="btn primary small" disabled={working} onClick={() => request(a)}>{t("Connect")}</button>
                  </div>
                ))}
              </>
            )}
            {links.length >= 10 && <div className="caption secondary">{t("A studio can show up to 10 artist profiles.")}</div>}
          </>
        )}
      </div>
    </main>
  );
}
