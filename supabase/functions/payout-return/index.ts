// Stripe sends studios here when they finish (or need to restart) payout onboarding. It bounces
// them straight back into the app, so no website of our own is needed.
Deno.serve((req) => {
  const to = new URL(req.url).searchParams.get("to") === "refresh" ? "refresh" : "done";
  return new Response(null, { status: 302, headers: { Location: `easysesh://payouts/${to}` } });
});
