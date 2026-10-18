// Stripe sends studios here when they finish (or need to restart) payout onboarding. It bounces
// them straight back: into the app, or to the website's payout page when they started there
// (env SITE_URL, e.g. https://easysesh.app).
Deno.serve((req) => {
  const params = new URL(req.url).searchParams;
  const to = params.get("to") === "refresh" ? "refresh" : "done";
  const site = Deno.env.get("SITE_URL")?.replace(/\/+$/, "");
  const location = params.get("client") === "web" && site ? `${site}/studio/payouts?stripe=${to}` : `easysesh://payouts/${to}`;
  return new Response(null, { status: 302, headers: { Location: location } });
});
