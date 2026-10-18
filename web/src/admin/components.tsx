import { useState, type ReactNode } from "react";
import { label } from "./lib/format";

const tone: Record<string, string> = {
  approved: "green", answered: "green", active: "green", confirmed: "green", completed: "blue", paid: "green", succeeded: "green", resolved: "green",
  pending_review: "orange", pending_approval: "orange", scheduled: "orange", open: "orange", authorized: "orange", in_transit: "orange", deposit_paid: "orange", pending: "orange",
  changes_requested: "yellow", partially_refunded: "yellow",
  rejected: "red", suspended: "red", banned: "red", failed: "red", disputed: "red",
  cancelled: "gray", closed: "gray", declined: "gray", expired: "gray", dismissed: "gray", draft: "gray", refunded: "gray", unpaid: "gray",
};

export function Badge({ value, text }: { value: string; text?: string }) {
  return <span className={`badge ${tone[value] ?? "gray"}`}>{text ?? label(value)}</span>;
}

export function Stat({ title, value, hint }: { title: string; value: ReactNode; hint?: string }) {
  return (
    <div className="card stat">
      <div className="muted small">{title}</div>
      <div className={typeof value === "string" && value.includes("\n") ? "stat-value multi" : "stat-value"}>{value}</div>
      {hint && <div className="muted small">{hint}</div>}
    </div>
  );
}

export function Tabs<T extends string>({ tabs, value, onChange }: { tabs: { id: T; title: string; count?: number }[]; value: T; onChange: (id: T) => void }) {
  return (
    <div className="tabs">
      {tabs.map((t) => (
        <button key={t.id} className={t.id === value ? "tab active" : "tab"} onClick={() => onChange(t.id)}>
          {t.title}
          {t.count !== undefined && <span className="count">{t.count}</span>}
        </button>
      ))}
    </div>
  );
}

export function Modal({ title, onClose, children, footer }: { title: string; onClose: () => void; children: ReactNode; footer?: ReactNode }) {
  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-label={title}>
        <div className="modal-header">
          <h2>{title}</h2>
          <button className="ghost" onClick={onClose} aria-label="Close">Close</button>
        </div>
        <div className="modal-body">{children}</div>
        {footer && <div className="modal-footer">{footer}</div>}
      </div>
    </div>
  );
}

export function PageState({ loading, error, empty, children }: { loading: boolean; error: string | null; empty?: boolean; children: ReactNode }) {
  if (error) return <div className="card error">{error}</div>;
  if (loading) return <div className="card muted">Loading…</div>;
  if (empty) return <div className="card muted">Nothing here.</div>;
  return <>{children}</>;
}

/** Button that runs an async action, shows progress and reports errors. */
export function ActionButton({ onClick, children, kind = "primary", confirm, disabled }: {
  onClick: () => Promise<void>; children: ReactNode; kind?: "primary" | "danger" | "secondary"; confirm?: string; disabled?: boolean;
}) {
  const [busy, setBusy] = useState(false);
  const [armed, setArmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  return (
    <span className="action">
      <button
        className={kind}
        disabled={busy || disabled}
        title={armed ? confirm : undefined}
        onBlur={() => setArmed(false)}
        onClick={async () => {
          // Destructive actions need a second click instead of a browser dialog.
          if (confirm && !armed) {
            setArmed(true);
            return;
          }
          setArmed(false);
          setError(null);
          setBusy(true);
          try {
            await onClick();
          } catch (e) {
            setError((e as Error).message);
          } finally {
            setBusy(false);
          }
        }}
      >
        {busy ? "Working…" : armed ? "Click again to confirm" : children}
      </button>
      {armed && confirm && <span className="muted small">{confirm}</span>}
      {error && <span className="error-text small">{error}</span>}
    </span>
  );
}

export function BarChart({ data, height = 160 }: { data: { label: string; value: number }[]; height?: number }) {
  const max = Math.max(1, ...data.map((d) => d.value));
  const width = Math.max(data.length * 22, 200);
  return (
    <svg viewBox={`0 0 ${width} ${height + 20}`} className="chart" preserveAspectRatio="none" role="img" aria-label="Bookings per day">
      {data.map((d, i) => {
        const h = (d.value / max) * height;
        return (
          <g key={d.label}>
            <rect x={i * 22 + 3} y={height - h} width={16} height={h} rx={3} className="bar">
              <title>{`${d.label}: ${d.value}`}</title>
            </rect>
            {i % Math.ceil(data.length / 8) === 0 && (
              <text x={i * 22 + 11} y={height + 14} textAnchor="middle" className="axis">{d.label.slice(5)}</text>
            )}
          </g>
        );
      })}
    </svg>
  );
}

export function Search({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder: string }) {
  return <input className="search" value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} />;
}
