import { useEffect, useRef, useState } from "react";
import { Modal } from "./components";
import { setReasonAsker } from "./lib/reason";

/** Asks "Why?" before a change; the answer goes to the audit log and to the person affected. */
export function ReasonDialog() {
  const [request, setRequest] = useState<{ action: string; resolve: (reason: string | null) => void } | null>(null);
  const [text, setText] = useState("");
  const input = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    setReasonAsker((action) => new Promise((resolve) => { setText(""); setRequest({ action, resolve }); }));
    return () => setReasonAsker(null);
  }, []);
  useEffect(() => { if (request) setTimeout(() => input.current?.focus(), 0); }, [request]);

  if (!request) return null;
  const finish = (value: string | null) => { request.resolve(value); setRequest(null); };
  const valid = text.trim().length >= 5;
  return (
    <Modal title={`Why? (${request.action})`} onClose={() => finish(null)}
      footer={<>
        <button className="secondary" onClick={() => finish(null)}>Cancel</button>
        <button className="primary" disabled={!valid} onClick={() => finish(text.trim())}>Continue</button>
      </>}>
      <p className="muted small">
        Explain the change in plain words. It's saved in the audit log, and if it changes someone's account it's emailed to
        them from noreply@easysesh.live (they can reply to support@ if they disagree).
      </p>
      <textarea ref={input} rows={4} value={text} placeholder="e.g. Studio asked us to update their address by email."
        onChange={(e) => setText(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter" && (e.metaKey || e.ctrlKey) && valid) finish(text.trim()); }} />
    </Modal>
  );
}
