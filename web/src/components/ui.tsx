// The web versions of the apps' building blocks (ios/EasySesh/Components, android/.../ui/components).
import { createContext, useCallback, useContext, useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { Link, useNavigate } from "react-router-dom";
import { AlertCircle, BadgeCheck, ChevronLeft, ChevronRight, Info, Megaphone, Minus, Plus, Sparkle, Star, X, type LucideIcon } from "lucide-react";
import { format, t } from "../lib/i18n";
import { Dates, sameDay, startOfDay } from "../lib/core";
import type { BookingStatus, StudioStatus } from "../lib/types";

// MARK: Colours

export const C = {
  accent: "var(--accent)", magenta: "var(--magenta)", violet: "var(--violet)", cyan: "var(--cyan)", positive: "var(--positive)",
  warning: "var(--warning)", red: "var(--red)", blue: "var(--blue)", gray: "#8E8E93", secondary: "var(--text-2)",
};

export const Tiles = {
  signal: [C.accent, C.magenta], violet: [C.magenta, C.violet], ocean: [C.violet, C.cyan], mint: [C.cyan, C.positive],
  muted: ["rgba(128,128,128,0.7)", "rgba(128,128,128,0.45)"], danger: ["#FF3B30", C.magenta], warm: [C.warning, C.accent],
  blue: ["#007AFF", C.cyan],
};

export const bookingStatusColor = (s: BookingStatus) =>
  s === "awaiting_payment" || s === "pending_approval" ? C.warning : s === "confirmed" ? C.positive : s === "completed" ? C.secondary : s === "disputed" ? C.red : C.gray;
export const studioStatusColor = (s: StudioStatus) =>
  s === "draft" ? C.gray : s === "pending_review" || s === "changes_requested" ? C.warning : s === "approved" ? C.positive : C.red;

// MARK: Basics

export function Logo({ size = 26 }: { size?: number }) {
  return <span className="logo" style={{ fontSize: size }}>easysesh<i /></span>;
}

export function IconTile({ icon: Icon, size = 36, colors = Tiles.signal, radius }: { icon: LucideIcon; size?: number; colors?: string[]; radius?: number }) {
  return (
    <span className="tile" style={{ width: size, height: size, borderRadius: radius ?? Math.min(12, size * 0.26), background: `color-mix(in srgb, ${colors[0]} 13%, transparent)`, color: colors[0] }}>
      <Icon size={size * 0.5} strokeWidth={2} />
    </span>
  );
}

export function Avatar({ url, name, size = 44, ring }: { url?: string | null; name: string; size?: number; ring?: boolean }) {
  const [failed, setFailed] = useState(false);
  const initials = name.split(" ").filter(Boolean).slice(0, 2).map((w) => w[0]).join("").toUpperCase();
  const inner = (
    <span className="avatar" style={{ width: size, height: size, fontSize: size * 0.36 }}>
      {url && !failed ? <img src={url} alt="" loading="lazy" onError={() => setFailed(true)} /> : initials || "?"}
    </span>
  );
  return ring ? <span className="ring">{inner}</span> : inner;
}

export function Photo({ url, style, className, children }: { url?: string | null; style?: CSSProperties; className?: string; children?: ReactNode }) {
  const [failed, setFailed] = useState(false);
  return (
    <div className={`photo ${className ?? ""}`} style={style}>
      {url && !failed ? <img src={url} alt="" loading="lazy" onError={() => setFailed(true)} /> : <div style={{ width: "100%", height: "100%", background: "linear-gradient(135deg, color-mix(in srgb, var(--violet) 30%, transparent), color-mix(in srgb, var(--magenta) 25%, transparent))" }} />}
      {children}
    </div>
  );
}

export const Spinner = ({ size = 22 }: { size?: number }) => <div className="spinner" style={{ width: size, height: size }} />;
export const Loading = () => <div className="row" style={{ justifyContent: "center", padding: 40 }}><Spinner /></div>;

export function PulseDot({ color = C.positive, active = true }: { color?: string; active?: boolean }) {
  return <span className={`pulse-dot ${active ? "on" : ""}`} style={{ background: color, color }} />;
}

export function StatusPill({ text, color }: { text: string; color: string }) {
  return <span className="pill" style={{ color, background: `color-mix(in srgb, ${color} 14%, transparent)` }}>{t(text)}</span>;
}

export function Stars({ rating, size = 14 }: { rating: number; size?: number }) {
  return (
    <span className="stars" aria-label={format("%lld of 5 stars", rating)}>
      {[1, 2, 3, 4, 5].map((n) => <Star key={n} size={size} fill={n <= Math.round(rating) ? "currentColor" : "none"} strokeWidth={2} style={{ opacity: n <= Math.round(rating) ? 1 : 0.4 }} />)}
    </span>
  );
}

export function StarPicker({ value, onChange, size = 30 }: { value: number; onChange: (n: number) => void; size?: number }) {
  return (
    <div className="row" style={{ gap: 10, justifyContent: "center" }}>
      {[1, 2, 3, 4, 5].map((n) => (
        <button key={n} type="button" onClick={() => onChange(n)} aria-label={format("%lld stars", n)} style={{ color: n <= value ? "var(--accent)" : "var(--text-3)", transform: n === value ? "scale(1.15)" : undefined, transition: "transform 0.2s" }}>
          <Star size={size} fill={n <= value ? "currentColor" : "none"} />
        </button>
      ))}
    </div>
  );
}

export function RatingLabel({ rating, count }: { rating: number; count: number }) {
  if (count === 0) return <span className="caption secondary">{t("New")}</span>;
  return <span className="row" style={{ gap: 4 }}><Star size={13} fill="var(--accent)" color="var(--accent)" /><span className="footnote bold">{rating.toFixed(1)}</span><span className="footnote secondary">({count})</span></span>;
}

export const VerifiedBadge = () => <BadgeCheck size={17} color="var(--blue)" fill="color-mix(in srgb, var(--blue) 20%, transparent)" aria-label={t("Verified")} />;

export function AdminBadge({ compact }: { compact?: boolean }) {
  return <span className="tag" style={{ background: "var(--neon)", color: "#fff", padding: compact ? "3px 5px" : "3px 7px", fontSize: 9, letterSpacing: "0.08em" }}><Sparkle size={10} fill="#fff" />{!compact && "TEAM"}</span>;
}

export function PromotedTag() {
  return <span className="tag" style={{ background: "var(--neon)", color: "#fff", fontSize: 10, letterSpacing: "0.05em", boxShadow: "0 0 10px color-mix(in srgb, var(--magenta) 45%, transparent)" }}><Megaphone size={11} />{t("Promoted").toUpperCase()}</span>;
}

export function SpecialTag({ title }: { title: string }) {
  return <span className="tag" style={{ border: "1px solid var(--magenta)", background: "color-mix(in srgb, var(--magenta) 12%, transparent)" }}><Star size={10} fill="var(--magenta)" color="var(--magenta)" /><span className="gradient-text">{t(title)}</span></span>;
}

export function Chip({ title, on, icon: Icon, onClick, translate = true }: { title: string; on?: boolean; icon?: LucideIcon; onClick?: () => void; translate?: boolean }) {
  return <button type="button" className={`chip ${on ? "on" : ""}`} onClick={onClick}>{Icon && <Icon size={14} />}{translate ? t(title) : title}</button>;
}

export function ChipPicker<T extends string>({ items, selected, onChange }: { items: [T, string][]; selected: T[]; onChange: (v: T[]) => void }) {
  return (
    <div className="chips">
      {items.map(([key, title]) => {
        const on = selected.includes(key);
        return <Chip key={key} title={title} on={on} onClick={() => onChange(on ? selected.filter((x) => x !== key) : [...selected, key])} />;
      })}
    </div>
  );
}

export function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { value: T; label: string; icon?: LucideIcon }[]; onChange: (v: T) => void }) {
  return (
    <div className="segmented" role="tablist">
      {options.map((o) => (
        <button key={o.value} role="tab" aria-selected={o.value === value} className={o.value === value ? "on" : ""} onClick={() => onChange(o.value)}>
          {o.icon && <o.icon size={15} />}{t(o.label)}
        </button>
      ))}
    </div>
  );
}

export function Toggle({ checked, onChange, disabled, label }: { checked: boolean; onChange: (v: boolean) => void; disabled?: boolean; label?: string }) {
  return (
    <label className="toggle" aria-label={label}>
      <input type="checkbox" checked={checked} disabled={disabled} onChange={(e) => onChange(e.target.checked)} />
      <span />
    </label>
  );
}

export function Stepper({ value, min, max, step = 1, onChange }: { value: number; min: number; max: number; step?: number; onChange: (v: number) => void }) {
  return (
    <span className="row" style={{ gap: 0, background: "var(--fill)", borderRadius: 9 }}>
      <button type="button" style={{ padding: "6px 12px" }} disabled={value - step < min} onClick={() => onChange(Math.max(min, value - step))} aria-label="-"><Minus size={16} /></button>
      <span style={{ width: 1, height: 18, background: "var(--stroke)" }} />
      <button type="button" style={{ padding: "6px 12px" }} disabled={value + step > max} onClick={() => onChange(Math.min(max, value + step))} aria-label="+"><Plus size={16} /></button>
    </span>
  );
}

export function GlowHead({ title, count, translate = true }: { title: string; count?: number; translate?: boolean }) {
  return <div className="glow-head">{translate ? t(title) : title}{count != null && count > 0 && <span className="count">{count}</span>}</div>;
}

export function Empty({ icon: Icon, title, message, children }: { icon: LucideIcon; title: string; message?: string; children?: ReactNode }) {
  return (
    <div className="card empty">
      <IconTile icon={Icon} size={48} colors={Tiles.violet} />
      <div className="headline">{t(title)}</div>
      {message && <div className="subhead secondary">{t(message)}</div>}
      {children}
    </div>
  );
}

export function Notice({ icon: Icon = Info, children, color = "var(--text-2)" }: { icon?: LucideIcon; children: ReactNode; color?: string }) {
  return <div className="row top footnote" style={{ color, gap: 8 }}><Icon size={16} style={{ flexShrink: 0, marginTop: 1 }} /><div>{children}</div></div>;
}

export function StatCard({ title, value, icon, colors }: { title: string; value: string; icon: LucideIcon; colors?: string[] }) {
  return (
    <div className="card tight" style={{ borderRadius: 20, padding: 14 }}>
      <IconTile icon={icon} size={30} colors={colors} />
      <div style={{ marginTop: 12, fontSize: 24, fontWeight: 800, fontVariantNumeric: "tabular-nums" }} className="clamp-1">{value}</div>
      <div className="caption secondary clamp-1" style={{ fontWeight: 500 }}>{t(title)}</div>
    </div>
  );
}

export function TileLink({ to, title, subtitle, icon, colors }: { to: string; title: string; subtitle: string; icon: LucideIcon; colors: string[] }) {
  return (
    <Link to={to} className="card pressable" style={{ borderRadius: 20, padding: 14, display: "block" }}>
      <IconTile icon={icon} size={38} colors={colors} />
      <div className="subhead bold" style={{ marginTop: 14 }}>{t(title)}</div>
      <div className="caption secondary clamp-1">{t(subtitle)}</div>
    </Link>
  );
}

// MARK: Grouped forms

export function Section({ header, footer, children, footerColor, translate = true }: { header?: ReactNode; footer?: ReactNode; children: ReactNode; footerColor?: string; translate?: boolean }) {
  return (
    <section className="section">
      {header != null && <div className="section-header">{typeof header === "string" && translate ? t(header) : header}</div>}
      <div className="group">{children}</div>
      {footer != null && <div className="section-footer" style={{ color: footerColor }}>{typeof footer === "string" && translate ? t(footer) : footer}</div>}
    </section>
  );
}

export function Item({ children, onClick, to, className }: { children: ReactNode; onClick?: () => void; to?: string; className?: string }) {
  if (to) return <Link to={to} className={`item ${className ?? ""}`}>{children}</Link>;
  if (onClick) return <button type="button" className={`item ${className ?? ""}`} onClick={onClick}>{children}</button>;
  return <div className={`item ${className ?? ""}`}>{children}</div>;
}

export function ItemLabel({ title, icon, colors, color, translate = true }: { title: string; icon?: LucideIcon; colors?: string[]; color?: string; translate?: boolean }) {
  return (
    <>
      {icon && (colors ? <IconTile icon={icon} size={30} colors={colors} radius={8} /> : (() => { const I = icon; return <I size={20} color={color ?? "var(--accent)"} />; })())}
      <span className="label" style={{ color }}>{translate ? t(title) : title}</span>
    </>
  );
}

export function NavItem({ to, title, icon, colors, value, translate = true, onClick }: { to?: string; title: string; icon?: LucideIcon; colors?: string[]; value?: string; translate?: boolean; onClick?: () => void }) {
  return (
    <Item to={to} onClick={onClick}>
      <ItemLabel title={title} icon={icon} colors={colors} translate={translate} />
      {value && <span className="value clamp-1">{value}</span>}
      <ChevronRight size={18} className="chev" />
    </Item>
  );
}

export function ToggleItem({ title, checked, onChange, icon, colors, disabled }: { title: string; checked: boolean; onChange: (v: boolean) => void; icon?: LucideIcon; colors?: string[]; disabled?: boolean }) {
  return (
    <Item>
      <ItemLabel title={title} icon={icon} colors={colors} color={disabled ? "var(--text-2)" : undefined} />
      <Toggle checked={checked} onChange={onChange} disabled={disabled} label={t(title)} />
    </Item>
  );
}

export function SelectItem<T extends string | number>({ title, value, options, onChange, icon, colors, translateOptions = true }: {
  title: string; value: T; options: [T, string][]; onChange: (v: T) => void; icon?: LucideIcon; colors?: string[]; translateOptions?: boolean;
}) {
  return (
    <Item>
      <ItemLabel title={title} icon={icon} colors={colors} />
      <select value={String(value)} onChange={(e) => {
        const found = options.find(([v]) => String(v) === e.target.value);
        if (found) onChange(found[0]);
      }}>
        {options.map(([v, label]) => <option key={String(v)} value={String(v)}>{translateOptions ? t(label) : label}</option>)}
      </select>
      <ChevronRight size={16} className="chev" style={{ transform: "rotate(90deg)" }} />
    </Item>
  );
}

export function InputItem({ placeholder, value, onChange, type = "text", label, multiline, rows = 4, mono, autoComplete, translate = true }: {
  placeholder: string; value: string; onChange: (v: string) => void; type?: string; label?: string; multiline?: boolean; rows?: number; mono?: boolean; autoComplete?: string; translate?: boolean;
}) {
  const ph = translate ? t(placeholder) : placeholder;
  return (
    <Item>
      {label && <span style={{ minWidth: 110 }}>{t(label)}</span>}
      {multiline
        ? <textarea placeholder={ph} value={value} rows={rows} onChange={(e) => onChange(e.target.value)} />
        : <input type={type} placeholder={ph} value={value} autoComplete={autoComplete} className={mono ? "mono" : undefined} onChange={(e) => onChange(e.target.value)} />}
    </Item>
  );
}

export function InfoRow({ icon: Icon, title, value, translate = true }: { icon: LucideIcon; title: string; value?: ReactNode; translate?: boolean }) {
  return (
    <div className="row" style={{ gap: 10, width: "100%" }}>
      <Icon size={18} color="var(--accent)" style={{ flexShrink: 0 }} />
      <span className="grow">{translate ? t(title) : title}</span>
      {value != null && <span className="secondary" style={{ textAlign: "right" }}>{value}</span>}
    </div>
  );
}

// MARK: Page chrome

/** Page header: back button, title, toolbar actions. */
export function PageHead({ title, back = true, backTo, leading, actions, translate = true }: { title?: string; back?: boolean; backTo?: string; leading?: ReactNode; actions?: ReactNode; translate?: boolean }) {
  const navigate = useNavigate();
  return (
    <div className="page-head">
      <div className="side">
        {leading ?? (back && (
          <button className="icon-btn" aria-label={t("Back")} onClick={() => (backTo ? navigate(backTo) : window.history.length > 1 ? navigate(-1) : navigate("/"))}>
            <ChevronLeft size={22} />
          </button>
        ))}
      </div>
      <h1 className="clamp-1">{title ? (translate ? t(title) : title) : ""}</h1>
      <div className="side end">{actions}</div>
    </div>
  );
}

/** Top-level page header: large title with an eyebrow. */
export function LargeHead({ title, eyebrow, actions, translate = true }: { title: string; eyebrow?: string; actions?: ReactNode; translate?: boolean }) {
  return (
    <div className="large-head">
      <div style={{ minWidth: 0 }}>
        {eyebrow && <div className="eyebrow" style={{ marginBottom: 4 }}>{t(eyebrow)}</div>}
        <h1 className="title-l clamp-1">{translate ? t(title) : title}</h1>
      </div>
      {actions && <div className="row" style={{ gap: 8 }}>{actions}</div>}
    </div>
  );
}

export function ToolButton({ title, onClick, disabled, bold }: { title: string; onClick: () => void; disabled?: boolean; bold?: boolean }) {
  return <button className={`tool-btn ${bold ? "bold" : ""}`} disabled={disabled} onClick={onClick}>{t(title)}</button>;
}

// MARK: Sheets, dialogs, toasts

/** A modal sheet (iOS .sheet); bottom sheet on phones. */
export function Sheet({ open, onClose, title, actions, children, translateTitle = true, closeLabel }: {
  open: boolean; onClose: () => void; title?: string; actions?: ReactNode; children: ReactNode; translateTitle?: boolean; closeLabel?: string;
}) {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => { document.removeEventListener("keydown", onKey); document.body.style.overflow = ""; };
  }, [open, onClose]);
  if (!open) return null;
  return createPortal(
    <div className="backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="sheet" role="dialog" aria-modal="true">
        <PageHead title={title} translate={translateTitle} back={false}
          leading={<button className="tool-btn" onClick={onClose}>{closeLabel ? t(closeLabel) : <X size={20} />}</button>} actions={actions} />
        <div className="sheet-body">{children}</div>
      </div>
    </div>,
    document.body,
  );
}

export interface DialogAction { title: string; destructive?: boolean; action: () => void; translate?: boolean }

export function ConfirmDialog({ open, title, message, actions, onClose, translateTitle = true }: {
  open: boolean; title: string; message?: string; actions: DialogAction[]; onClose: () => void; translateTitle?: boolean;
}) {
  if (!open) return null;
  return createPortal(
    <div className="backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="dialog" role="alertdialog">
        <div className="headline">{translateTitle ? t(title) : title}</div>
        {message && <div className="subhead secondary" style={{ marginTop: 6 }}>{message}</div>}
        <div className="actions">
          {actions.map((a) => <button key={a.title} className={a.destructive ? "destructive" : ""} onClick={() => { onClose(); a.action(); }}>{a.translate === false ? a.title : t(a.title)}</button>)}
          <button className="cancel" onClick={onClose}>{t("Cancel")}</button>
        </div>
      </div>
    </div>,
    document.body,
  );
}

const ToastContext = createContext<(message: string, kind?: "error" | "info") => void>(() => undefined);

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<{ message: string; kind: "error" | "info" } | null>(null);
  const timer = useRef<number>();
  const show = useCallback((message: string, kind: "error" | "info" = "error") => {
    if (!message) return;
    setToast({ message, kind });
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setToast(null), 5000);
  }, []);
  return (
    <ToastContext.Provider value={show}>
      {children}
      {toast && createPortal(
        <div className="toast" role="alert" onClick={() => setToast(null)}>
          {toast.kind === "error" ? <AlertCircle size={18} color="var(--red)" style={{ flexShrink: 0 }} /> : <Info size={18} color="var(--accent)" style={{ flexShrink: 0 }} />}
          <span className="subhead">{toast.message}</span>
        </div>, document.body)}
    </ToastContext.Provider>
  );
}

/** Shows an error or a short message at the bottom of the screen (iOS .errorAlert). */
export const useToast = () => useContext(ToastContext);

// MARK: Calendar

/** Month grid with dots for booked days (and red dots for blocked days). */
export function MonthCalendar({ selected, onSelect, marked = [], blocked = [], min }: { selected: Date; onSelect: (d: Date) => void; marked?: Date[]; blocked?: Date[]; min?: Date }) {
  const [month, setMonth] = useState(new Date(selected.getFullYear(), selected.getMonth(), 1));
  const first = new Date(month.getFullYear(), month.getMonth(), 1);
  const offset = (first.getDay() + 6) % 7; // Monday first
  const days = Array.from({ length: 42 }, (_, i) => new Date(month.getFullYear(), month.getMonth(), 1 - offset + i));
  const weeks = days[35].getMonth() !== month.getMonth() ? days.slice(0, 35) : days;
  const dow = Array.from({ length: 7 }, (_, i) => Dates.weekdayShort(new Date(2026, 9, 19 + i)));
  const today = new Date();
  return (
    <div className="card">
      <div className="row spread" style={{ marginBottom: 8 }}>
        <div className="headline">{Dates.monthYear(month)}</div>
        <div className="row" style={{ gap: 4 }}>
          <button className="icon-btn" style={{ width: 32, height: 32 }} onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))} aria-label={t("Previous month")}><ChevronLeft size={18} /></button>
          <button className="icon-btn" style={{ width: 32, height: 32 }} onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))} aria-label={t("Next month")}><ChevronRight size={18} /></button>
        </div>
      </div>
      <div className="cal">
        {dow.map((d) => <div key={d} className="dow">{d}</div>)}
        {weeks.map((d) => {
          const isMarked = marked.some((m) => sameDay(m, d));
          const isBlocked = blocked.some((m) => sameDay(m, d));
          const disabled = !!min && d < startOfDay(min);
          return (
            <button key={d.toISOString()} disabled={disabled} onClick={() => onSelect(d)}
              className={[sameDay(d, selected) && "sel", sameDay(d, today) && "today", d.getMonth() !== month.getMonth() && "out"].filter(Boolean).join(" ")}>
              {d.getDate()}
              {isMarked && <span className="dot" style={isBlocked ? { left: "calc(50% - 7px)" } : undefined} />}
              {isBlocked && <span className="dot blocked" />}
            </button>
          );
        })}
      </div>
    </div>
  );
}
