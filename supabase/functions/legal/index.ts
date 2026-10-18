// Public legal and support links for the App Store / Play listings and the apps:
//   /functions/v1/legal                 → easysesh.live/legal
//   /functions/v1/legal/privacy         → easysesh.live/legal/privacy
//   /functions/v1/legal/privacy?lang=da → the Danish version
//   /functions/v1/legal/support         → how to contact EasySesh (plain text)
// The documents themselves are on the website (from legal/), so this only redirects.

const SITE = (Deno.env.get("SITE_URL") ?? "https://easysesh.live").replace(/\/+$/, "");
const SUPPORT_EMAIL = Deno.env.get("SUPPORT_EMAIL") ?? "support@easysesh.live";
const PAGES = new Set(["terms", "privacy", "cookies", "refund-and-cancellation", "studio-agreement", "community-guidelines"]);
const LANGS = new Set(["en", "da", "de", "pl", "el", "fr", "es", "it", "sv", "nl"]);

const SUPPORT = `EasySesh – Support

EasySesh connects music artists with recording studios: find a studio, book a session and pay in the app.

How to reach us:
- In the app: Settings → Support. Our team answers there, usually within 24 hours.
- Email: ${SUPPORT_EMAIL}

Delete your account: Settings → Delete account (in the app or on ${SITE}).
Download your data: Settings → Your data → Download my data.

Privacy policy: ${SITE}/legal/privacy
Terms & Conditions: ${SITE}/legal/terms
Community Guidelines: ${SITE}/legal/community-guidelines
`;

Deno.serve((req) => {
  const url = new URL(req.url);
  const page = url.pathname.replace(/^.*\/legal\/?/, "").replace(/\/+$/, "").toLowerCase();
  if (page === "support") {
    return new Response(SUPPORT, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=300" } });
  }
  const lang = (url.searchParams.get("lang") ?? "").toLowerCase();
  const query = LANGS.has(lang) ? `?lang=${lang}` : "";
  const target = PAGES.has(page) ? `${SITE}/legal/${page}${query}` : `${SITE}/legal`;
  return new Response(null, { status: 302, headers: { Location: target, "Cache-Control": "public, max-age=300" } });
});
