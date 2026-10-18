import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App";
import { adminBase, adminUrl, hasAdminSubdomain, isAdminHost } from "../lib/hosts";
import "./styles.css";

// Deep links like /admin/users can reach the website's index.html first (hosts such as Cloudflare
// Pages only fall back to it); the website then forwards them as /admin/?to=users.
const to = new URLSearchParams(window.location.search).get("to");
const path = (to ?? window.location.pathname.replace(/^\/admin\/?/, "")).replace(/^\/+/, "");

if (hasAdminSubdomain && !isAdminHost) {
  // easysesh.live/admin/... moved to admin.easysesh.live/...
  window.location.replace(adminUrl(path));
} else {
  if (to) window.history.replaceState(null, "", `${adminBase.replace(/\/$/, "")}/${path}`);
  ReactDOM.createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
      <BrowserRouter basename={adminBase}>
        <App />
      </BrowserRouter>
    </React.StrictMode>,
  );
}
