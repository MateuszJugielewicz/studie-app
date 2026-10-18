import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App";
import "./styles.css";

// Hosts that only fall back to the website's index.html (e.g. Cloudflare Pages) land deep links like
// /admin/users on the website, which sends them here as /admin/?to=users. Restore the path.
const to = new URLSearchParams(window.location.search).get("to");
if (to) window.history.replaceState(null, "", `/admin/${to.replace(/^\/+/, "")}`);

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <BrowserRouter basename="/admin">
      <App />
    </BrowserRouter>
  </React.StrictMode>,
);
