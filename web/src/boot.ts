import { isAdminHost } from "./lib/hosts";

// admin.easysesh.live (and /admin on localhost and preview hosts) opens the admin dashboard; every other
// address opens the website. Both are loaded on demand, so each brings its own styles.
// Keep these as two separate import() statements: in one `a ? import(x) : import(y)` expression the
// build attaches only one branch's stylesheet.
if (isAdminHost || /^\/admin(\/|$)/.test(window.location.pathname)) {
  void import("./admin/main");
} else {
  void import("./main");
}
