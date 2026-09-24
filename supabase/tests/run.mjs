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
expect("resave", (r) => r.name === "Renamed Studio" && r.status === "draft");
expect("artist role after attempt", (r) => r.role === "artist");
expect("booking_count", (r) => r.booking_count === 1);
expect("owner unread", (r) => r.studio_unread === 1);
expect("notif title", (r) => r.title !== "hacked");
expect("review", (r) => r.studio_reply === null);
expect("rating", (r) => r.rating_average === 4 && r.review_count === 1);
expect("has_review", (r) => r.has_review === true);
expect("stats", (r) => Number(r.rate) === 100 && r.live === 1);
for (const label of ["unapproved block denied", "second studio denied", "artist studio denied", "admin without mfa denied"]) {
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
if (!rows.some((r) => r.r === "blocked ok")) {
  console.error("FAILED: overlapping booking was not blocked");
  process.exitCode = 1;
}
