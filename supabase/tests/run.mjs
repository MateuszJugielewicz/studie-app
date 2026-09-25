// Applies all migrations to an in-memory Postgres (PGlite) with Supabase stubs, then runs flow.sql.
// Usage: cd supabase/tests && npm install && npm test
import { PGlite } from "@electric-sql/pglite";
import { btree_gist } from "@electric-sql/pglite/contrib/btree_gist";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const migrations = path.join(here, "..", "migrations");
const db = new PGlite({ extensions: { btree_gist } });

await db.exec(fs.readFileSync(path.join(here, "supabase_stubs.sql"), "utf8"));
for (const file of fs.readdirSync(migrations).sort()) {
  // pg_cron / pg_net are stubbed in supabase_stubs.sql.
  const sql = fs.readFileSync(path.join(migrations, file), "utf8").replace(/create extension if not exists (pg_cron|pg_net)[^;]*;/g, "");
  await db.exec(sql);
  console.log("applied", file);
}

const results = await db.exec(fs.readFileSync(path.join(here, "flow.sql"), "utf8"));
const rows = results.flatMap((r) => r.rows);
const expect = (label, predicate) => {
  const row = rows.find((r) => Object.values(r).includes(label));
  if (!row || !predicate(row)) {
    console.error("FAILED:", label, JSON.stringify(row));
    process.exitCode = 1;
  } else {
    console.log("ok:", label);
  }
};

expect("after self-approve", (r) => r.status === "draft" && r.is_active === false);
expect("still live", (r) => r.status === "approved" && r.is_active === true);
expect("resave", (r) => r.name === "Renamed Studio" && r.status === "draft");
expect("artist role after attempt", (r) => r.role === "artist");
expect("booking_count", (r) => r.booking_count === 1);
expect("owner unread", (r) => r.studio_unread === 1);
expect("notif title", (r) => r.title !== "hacked");
expect("review", (r) => r.studio_reply === null);
expect("rating", (r) => r.rating_average === 4 && r.review_count === 1);
expect("has_review", (r) => r.has_review === true);
expect("stats", (r) => Number(r.rate) === 100 && r.live === 1);
for (const label of ["unapproved block denied", "artist self review denied", "db clash blocked", "db closed hours blocked", "owner grant denied", "rating others denied", "declined request blocks studio", "declined direct insert blocked", "artist cannot search artists", "support forge denied", "support other denied", "second studio denied", "artist studio denied", "admin without mfa denied"]) {
  if (!rows.some((r) => r.r === label)) {
    console.error("FAILED:", label);
    process.exitCode = 1;
  } else console.log("ok:", label);
}
expect("fee balance", (r) => r.balance === 500);
expect("cash received", (r) => r.status === "paid");
expect("owner sees ledger", (r) => Number(r.n) === 1);
expect("settled", (r) => r.amount === -500);
expect("balance after", (r) => r.balance === 0);
expect("terms", (r) => r.version === "2026-09-25");
expect("ticket created", (r) => r.status === "open");
expect("owner sees tickets", (r) => Number(r.n) === 0);
expect("admin inbox", (r) => !!r.user_name && r.admin_unread === 1);
expect("ticket answered", (r) => r.status === "answered" && r.user_unread === 1 && Number(r.n) === 2);
expect("support notified", (r) => Number(r.n) === 1);
expect("ticket closed", (r) => r.status === "closed");
expect("artist search", (r) => Number(r.n) === 1);
expect("known artist", (r) => r.status === "accepted");
expect("cold request", (r) => r.status === "pending");
expect("request notified", (r) => Number(r.n) === 1);
expect("declined", (r) => r.status === "declined");
expect("support rated", (r) => r.rating === 5);
expect("self badge", (r) => r.has_admin_badge === false);
expect("self promo", (r) => r.admin_tags.length === 0 && r.promoted_until === null && r.has_admin_badge === false);
expect("admin tags", (r) => r.n === 2);
expect("granted", (r) => r.status === "active");
expect("promoted", (r) => r.ok === true);
expect("badge set", (r) => r.has_admin_badge === true);
expect("db booking", (r) => r.status === "awaiting_payment" && r.subtotal === 5000 && r.ref_ok === true);
expect("db cash", (r) => r.status === "confirmed");
expect("db moved", (r) => r.hour === 15);
expect("db cancelled", (r) => r.status === "cancelled");
expect("artist rated", (r) => r.rating === 4);
expect("artist rating", (r) => r.avg === 4 && r.review_count === 1);
expect("rating locked", (r) => r.review_count === 1);
expect("notifications deleted", (r) => Number(r.n) === 0);
expect("promo requested", (r) => r.status === "pending" && r.days === 14 && r.amount === 3500 && r.currency === "EUR");
expect("promo activated", (r) => r.status === "active");
expect("promo pending list", (r) => Number(r.n) === 0);
expect("fee invoices created", (r) => r.n === 1);
expect("fee reminder", (r) => Number(r.n) === 1);
expect("fee final notice", (r) => Number(r.n) === 1);
expect("fee collections", (r) => r.invoice_status === "collections" && r.studio_status === "suspended" && r.active === false);
expect("fee reinstated", (r) => r.status === "approved" && r.invoice_status === "paid");
expect("fee deal", (r) => r.pct === 5);
expect("deal booking", (r) => r.commission === 250 && r.subtotal === 5000);
expect("deal locked", (r) => r.platform_fee_percent === 5);
expect("contact rules", (r) => r.needs_phone === true);
expect("rating disputed", (r) => r.status === "open");
expect("dispute resolved", (r) => r.status === "removed" && r.hidden === true);
expect("link requested", (r) => r.status === "pending");
expect("link hidden while pending", (r) => Number(r.n) === 0);
expect("link public", (r) => r.status === "accepted");
expect("request expired", (r) => r.status === "expired" && r.payment_status === "unpaid");
expect("checked in", (r) => r.ok === true && r.dist < 50);
expect("arrival confirmed", (r) => r.ok === true);
if (!rows.some((r) => r.r === "blocked ok")) {
  console.error("FAILED: overlapping booking was not blocked");
  process.exitCode = 1;
}
