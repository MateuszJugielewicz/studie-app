import { useEffect, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import { marked } from "marked";
import { ArrowDownToLine, BookOpen, Building2, FileText, Hand, HardDrive, Share, Undo2, Users, type LucideIcon } from "lucide-react";
import { config } from "../lib/config";
import { format, language, LANGUAGES, t } from "../lib/i18n";
import { useApp } from "../lib/state";
import { api, userMessage } from "../lib/api";
import { Item, ItemLabel, Loading, NavItem, PageHead, Section, Spinner, Tiles, useToast } from "../components/ui";
import type { UserRole } from "../lib/types";

export interface LegalDocument { raw: string; title: string; icon: LucideIcon }

export const LEGAL: Record<string, LegalDocument> = {
  terms: { raw: "terms", title: "Terms & Conditions", icon: FileText },
  privacy: { raw: "privacy", title: "Privacy Policy", icon: Hand },
  cookies: { raw: "cookies", title: "Cookie Policy", icon: HardDrive },
  refunds: { raw: "refund-and-cancellation", title: "Refund & Cancellation Policy", icon: Undo2 },
  studio: { raw: "studio-agreement", title: "Studio Agreement", icon: Building2 },
  community: { raw: "community-guidelines", title: "Community Guidelines", icon: Users },
};

/** Documents a user of the given role must accept. */
export const requiredDocuments = (role: UserRole) => (role === "studio_owner" ? ["terms", "privacy", "studio"] : ["terms", "privacy"]);

// The documents live in /legal (shared with the apps); each language is its own folder.
const files = import.meta.glob<string>("../../../legal/**/*.md", { query: "?raw", import: "default" });

async function loadMarkdown(doc: LegalDocument, lang = language()): Promise<string> {
  const localized = files[`../../../legal/${lang}/${doc.raw}.md`];
  const english = files[`../../../legal/${doc.raw}.md`];
  const loader = (lang !== "en" && localized) || english;
  return loader ? loader() : `# ${t(doc.title)}`;
}

/** A legal document, rendered from its Markdown file. */
export function LegalDocumentBody({ doc, lang }: { doc: LegalDocument; lang?: string }) {
  const [html, setHtml] = useState<string | null>(null);
  useEffect(() => {
    loadMarkdown(doc, lang).then((md) => setHtml(marked.parse(md, { async: false }) as string));
  }, [doc, lang]);
  if (html == null) return <Loading />;
  return <article className="markdown card" style={{ padding: "8px 22px 22px" }} dangerouslySetInnerHTML={{ __html: html }} />;
}

export function LegalList({ base = "/legal" }: { base?: string }) {
  const app = useApp();
  const footer = config.supportEmail
    ? format("Version %@. Questions? %@", app.requiredTermsVersion, config.supportEmail)
    : format("Version %@. Questions? Write to us in Settings → Support.", app.requiredTermsVersion);
  return (
    <Section footer={footer} translate={false}>
      {Object.entries(LEGAL).map(([key, doc]) => <NavItem key={key} to={`${base}/${key}`} title={doc.title} icon={doc.icon} />)}
    </Section>
  );
}

export default function Legal() {
  const { doc } = useParams();
  // Links from the App Store listing / the old legal pages can ask for a language: ?lang=da
  const requested = useSearchParams()[0].get("lang");
  const lang = LANGUAGES.some((l) => l.code === requested) ? requested! : undefined;
  const document = doc ? LEGAL[doc] ?? Object.values(LEGAL).find((d) => d.raw === doc) ?? null : null;
  return (
    <main className="page narrow">
      <PageHead title={document ? document.title : "Legal"} />
      {document ? <LegalDocumentBody doc={document} lang={lang} /> : <LegalList />}
    </main>
  );
}

/** GDPR: download everything EasySesh stores about you, as a JSON file. */
export function DataExportItem() {
  const toast = useToast();
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  async function run() {
    setBusy(true);
    try {
      const json = await api.exportPersonalData();
      const url = URL.createObjectURL(new Blob([json], { type: "application/json" }));
      const a = Object.assign(document.createElement("a"), { href: url, download: `easysesh-data-${new Date().toISOString().slice(0, 10)}.json` });
      a.click();
      URL.revokeObjectURL(url);
      setDone(true);
    } catch (e) { toast(userMessage(e)); }
    setBusy(false);
  }
  return (
    <Item onClick={busy ? undefined : run}>
      <ItemLabel title={busy ? "Preparing…" : done ? "Share my data file" : "Download my data"} icon={done ? Share : ArrowDownToLine} colors={done ? Tiles.mint : Tiles.ocean} />
      {busy && <Spinner size={18} />}
    </Item>
  );
}

export const LegalIcon = BookOpen;
