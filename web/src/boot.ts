import { isAdminHost } from "./lib/hosts";
import { captureViewAs } from "./lib/viewAs";

// A "view as user" link from the admin panel: keep its session for this tab, then open the website.
captureViewAs();

// admin.easysesh.live (and /admin on localhost and preview hosts) opens the admin dashboard; every other
// address opens the website. Both are loaded on demand, so each brings its own styles.
// Keep these as two separate import() statements: in one `a ? import(x) : import(y)` expression the
// build attaches only one branch's stylesheet.
// After a deploy, a tab that was open (or a page Safari kept) still asks for the previous version's code
// files, which no longer exist: reload once to get the new version instead of showing a white page.
function reloadForNewVersion() {
  const key = "easysesh.reloadedForNewVersion";
  try {
    const last = Number(sessionStorage.getItem(key) ?? 0);
    if (Date.now() - last < 30_000) return; // already tried just now: don't loop
    sessionStorage.setItem(key, String(Date.now()));
  } catch { /* storage unavailable: reload anyway */ }
  window.location.reload();
}
window.addEventListener("vite:preloadError", (event) => { event.preventDefault(); reloadForNewVersion(); });

if (isAdminHost || /^\/admin(\/|$)/.test(window.location.pathname)) {
  import("./admin/main").catch(reloadForNewVersion);
} else {
  import("./main").catch(reloadForNewVersion);
}
