import { useState } from "react";
import { ActionButton, PageState } from "../components";
import { rankAtLeast, useApi, useLoad, useStaff } from "../lib/apiContext";
import { date } from "../lib/format";

/** Write an email from an @easysesh.live address. Replies go back to that address (iCloud). */
export default function EmailPage() {
  const api = useApi();
  const me = useStaff();
  const sent = useLoad(() => api.sentEmails());
  const senders = me.rank === "owner" ? ["support", "easysesh", "noreply", "mateusz"] : rankAtLeast(me.rank, "admin") ? ["support", "easysesh", "noreply"] : ["support"];
  const [from, setFrom] = useState(senders[0]);
  const [custom, setCustom] = useState("");
  const [to, setTo] = useState(() => new URLSearchParams(window.location.search).get("to") ?? "");
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [done, setDone] = useState<string | null>(null);
  const sender = from === "other" ? custom.trim().toLowerCase() : from;

  const send = async () => {
    await api.sendEmail({ from: sender, to, subject: subject.trim(), body: body.trim() });
    setDone(`Sent to ${to}.`);
    setSubject(""); setBody("");
    await sent.reload();
  };

  return (
    <>
      <header className="page-header"><h1>Email</h1></header>
      <p className="muted">Sent through Resend with the EasySesh email design. Replies arrive in the sender's iCloud inbox.</p>
      <div className="card form">
        <div className="row gap wrap">
          <label>From
            <select value={from} onChange={(e) => setFrom(e.target.value)}>
              {senders.map((s) => <option key={s} value={s}>{s}@easysesh.live</option>)}
              {me.rank === "owner" && <option value="other">Other…</option>}
            </select>
          </label>
          {from === "other" && <label>Address<input placeholder="hello" value={custom} onChange={(e) => setCustom(e.target.value.replace(/@.*$/, ""))} /></label>}
          <label style={{ flex: 1, minWidth: 240 }}>To (comma-separated, max 20)<input value={to} onChange={(e) => setTo(e.target.value)} placeholder="artist@example.com" /></label>
        </div>
        <label>Subject<input value={subject} onChange={(e) => setSubject(e.target.value)} /></label>
        <label>Message<textarea rows={10} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Hi …" /></label>
        {done && <div className="card notice small">{done}</div>}
        <div>
          <ActionButton disabled={!sender || !to.includes("@") || !subject.trim() || !body.trim()} confirm={`Send from ${sender}@easysesh.live to ${to}?`} onClick={send}>Send email</ActionButton>
        </div>
      </div>
      <h2>Sent</h2>
      <PageState loading={sent.loading && !sent.data} error={sent.error} empty={(sent.data ?? []).length === 0}>
        <div className="card flush">
          <table>
            <thead><tr><th>When</th><th>From</th><th>To</th><th>Subject</th><th>By</th></tr></thead>
            <tbody>
              {(sent.data ?? []).map((m) => (
                <tr key={m.id} title={m.body}>
                  <td>{date(m.created_at, true)}</td>
                  <td>{m.from_address}</td>
                  <td>{m.to_addresses.join(", ")}</td>
                  <td className="strong">{m.subject}</td>
                  <td className="muted">{m.sender_email}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </PageState>
    </>
  );
}
