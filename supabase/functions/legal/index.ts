// Public legal and support pages for the App Store listing (privacy policy URL, support URL) and
// for links from the app:
//   /functions/v1/legal                 → index
//   /functions/v1/legal/privacy         → privacy policy (English)
//   /functions/v1/legal/privacy?lang=da → Danish
//   /functions/v1/legal/support         → how to contact EasySesh
// Supabase serves function responses as plain text, so the documents are sent as readable text.
import { DOCS } from "./docs.ts";

const NAMES: Record<string, string> = {
  terms: "Terms & Conditions",
  privacy: "Privacy Policy",
  cookies: "Cookie Policy",
  "refund-and-cancellation": "Refund & Cancellation Policy",
  "studio-agreement": "Studio Agreement",
  "community-guidelines": "Community Guidelines",
};

function text(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=300" },
  });
}

function support(base: string): string {
  const email = Deno.env.get("SUPPORT_EMAIL");
  return [
    "EasySesh – Support",
    "",
    "EasySesh connects music artists with recording studios: find a studio, book a session and pay in the app.",
    "",
    "How to reach us:",
    "- In the app: Settings → Support. Our team answers there, usually within 24 hours.",
    email ? `- Email: ${email}` : null,
    "",
    "Delete your account: Settings → Delete account (in the app). This deletes your profile, photos, messages and reviews.",
    "Download your data: Settings → Your data → Download my data.",
    "",
    `Privacy policy: ${base}/privacy`,
    `Terms & Conditions: ${base}/terms`,
    `Community Guidelines: ${base}/community-guidelines`,
  ].filter((line) => line !== null).join("\n") + "\n";
}

Deno.serve((req) => {
  const url = new URL(req.url);
  const base = `${Deno.env.get("SUPABASE_URL") ?? url.origin}/functions/v1/legal`;
  const page = url.pathname.replace(/^.*\/legal\/?/, "").replace(/\/+$/, "").toLowerCase();
  const lang = (url.searchParams.get("lang") ?? "en").toLowerCase();

  if (page === "" || page === "index") {
    const list = Object.entries(NAMES).map(([slug, name]) => `- ${name}: ${base}/${slug}`).join("\n");
    return text(`EasySesh – legal documents\n\n${list}\n- Support: ${base}/support\n\nOther languages: add ?lang=da, de, pl, el, fr, es, it, sv or nl.\n`);
  }
  if (page === "support") return text(support(base));
  const doc = DOCS[`${lang}/${page}`] ?? DOCS[`en/${page}`];
  return doc ? text(doc) : text("Not found.\n", 404);
});
