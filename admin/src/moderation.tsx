import { useState } from "react";
import { ActionButton, Badge } from "./components";
import { useApi, useLoad } from "./lib/apiContext";
import { date, label } from "./lib/format";
import type { ModerationEvent } from "./lib/types";

const presets = [
  { id: "1", title: "1 day", days: 1 },
  { id: "3", title: "3 days", days: 3 },
  { id: "7", title: "7 days", days: 7 },
  { id: "30", title: "30 days", days: 30 },
  { id: "custom", title: "Custom", days: 0 },
  { id: "forever", title: "Until lifted", days: null },
] as const;

type PresetId = (typeof presets)[number]["id"];

/** Picks how long a suspension or ban lasts. Returns days (fractions allowed) or null = until lifted. */
export function DurationPicker({ value, onChange }: { value: number | null; onChange: (days: number | null) => void }) {
  const [preset, setPreset] = useState<PresetId>("7");
  const [amount, setAmount] = useState(12);
  const [unit, setUnit] = useState<"hours" | "days">("hours");

  const choose = (id: PresetId) => {
    setPreset(id);
    const p = presets.find((x) => x.id === id)!;
    if (id === "custom") onChange(unit === "hours" ? amount / 24 : amount);
    else onChange(p.days);
  };
  const custom = (n: number, u: "hours" | "days") => {
    setAmount(n);
    setUnit(u);
    onChange(n > 0 ? (u === "hours" ? n / 24 : n) : 0);
  };

  return (
    <div className="duration">
      <div className="segmented">
        {presets.map((p) => (
          <button key={p.id} type="button" className={preset === p.id ? "seg active" : "seg"} onClick={() => choose(p.id)}>{p.title}</button>
        ))}
      </div>
      {preset === "custom" && (
        <div className="row gap">
          <input type="number" min={1} value={amount} onChange={(e) => custom(Number(e.target.value), unit)} style={{ width: 90 }} />
          <select value={unit} onChange={(e) => custom(amount, e.target.value as "hours" | "days")}>
            <option value="hours">hours</option>
            <option value="days">days</option>
          </select>
        </div>
      )}
      <div className="muted small">
        {value === null ? "Lasts until an admin lifts it." : value > 0 ? `Ends ${date(new Date(Date.now() + value * 86_400_000).toISOString(), true)} and lifts automatically.` : "Choose a length."}
      </div>
    </div>
  );
}

/** Warn, suspend or ban a user (and their studio), for a chosen period, with the full history. */
export function ModerationPanel({ userId, studioId, status, statusUntil, studioSuspended, onChanged }: {
  userId: string;
  studioId?: string | null;
  status?: "active" | "suspended" | "banned";
  statusUntil?: string | null;
  studioSuspended?: boolean;
  onChanged: () => Promise<void>;
}) {
  const api = useApi();
  const history = useLoad(() => api.moderationHistory({ userId, studioId: studioId ?? undefined }), [userId, studioId]);
  const [reason, setReason] = useState("");
  const [days, setDays] = useState<number | null>(7);

  const done = async () => {
    setReason("");
    await history.reload();
    await onChanged();
  };
  const needsReason = !reason.trim();
  const validDays = days === null || days > 0;

  return (
    <div className="moderation">
      <h3>Moderation</h3>
      {status && status !== "active" && (
        <div className="card notice">
          <Badge value={status} /> {statusUntil ? `until ${date(statusUntil, true)}` : "until lifted"}
          <ActionButton kind="secondary" onClick={async () => { await api.moderateUser(userId, "lift", null, reason); await done(); }}>Lift now</ActionButton>
        </div>
      )}
      {studioId && studioSuspended && (
        <div className="card notice">
          <Badge value="suspended" text="Studio suspended" />
          <ActionButton kind="secondary" onClick={async () => { await api.moderateStudio(studioId, "lift", null, reason); await done(); }}>Lift studio suspension</ActionButton>
        </div>
      )}
      <label className="form">
        Reason (shown to the user)
        <textarea rows={2} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="e.g. Asked an artist to pay outside EasySesh." />
      </label>
      <DurationPicker value={days} onChange={setDays} />
      <div className="row gap wrap">
        <ActionButton kind="secondary" disabled={needsReason} onClick={async () => { await api.warnUser(userId, reason.trim(), studioId ?? undefined); await done(); }}>
          Send warning
        </ActionButton>
        {studioId && (
          <ActionButton kind="danger" disabled={needsReason || !validDays} confirm="Hide this studio from artists for the chosen period?" onClick={async () => { await api.moderateStudio(studioId, "suspend", days, reason.trim()); await done(); }}>
            Suspend studio
          </ActionButton>
        )}
        <ActionButton kind="danger" disabled={needsReason || !validDays} confirm="Suspend this account for the chosen period?" onClick={async () => { await api.moderateUser(userId, "suspend", days, reason.trim()); await done(); }}>
          Suspend account
        </ActionButton>
        <ActionButton kind="danger" disabled={needsReason || !validDays} confirm="Ban this account for the chosen period?" onClick={async () => { await api.moderateUser(userId, "ban", days, reason.trim()); await done(); }}>
          Ban account
        </ActionButton>
      </div>

      <h3>History</h3>
      {history.error && <div className="error-text small">{history.error}</div>}
      {(history.data ?? []).length === 0 && !history.loading && <div className="muted small">No warnings, suspensions or reports.</div>}
      <ul className="timeline">
        {(history.data ?? []).map((e: ModerationEvent) => (
          <li key={`${e.kind}-${e.id}`}>
            <span className="muted small">{date(e.created_at, true)}</span> <Badge value={tone(e.kind)} text={label(e.kind)} />{" "}
            {e.details}
            {e.ends_at && <span className="muted small"> · until {date(e.ends_at, true)}</span>}
            {e.kind === "warning" && <span className="muted small"> · {e.acknowledged_at ? "seen" : "not seen yet"}</span>}
            {e.actor_email && <div className="muted small">by {e.actor_email}</div>}
          </li>
        ))}
      </ul>
    </div>
  );
}

function tone(kind: ModerationEvent["kind"]): string {
  switch (kind) {
    case "warning": return "pending";
    case "suspension": return "suspended";
    case "ban": return "banned";
    case "lifted": return "active";
    case "report": return "open";
    default: return "draft";
  }
}
