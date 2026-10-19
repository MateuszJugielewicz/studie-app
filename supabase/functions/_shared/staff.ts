// The EasySesh team: ranks (support < admin < owner) and the audit log for actions taken in edge
// functions (table changes are logged by database triggers).
import { HttpError } from "./http.ts";
import { admin, requireAdmin } from "./supabase.ts";
import type { Profile } from "./types.ts";

export type Rank = "support" | "admin" | "owner";
const ORDER: Rank[] = ["support", "admin", "owner"];

export type Staff = Profile & { admin_rank: Rank };

/** An admin with two-factor and at least the given rank. */
export async function requireStaff(req: Request, minimum: Rank = "support"): Promise<Staff> {
  const user = await requireAdmin(req) as Staff;
  const rank = (user.admin_rank ?? "admin") as Rank;
  if (ORDER.indexOf(rank) < ORDER.indexOf(minimum)) throw new HttpError(403, `This needs the ${minimum} rank.`);
  return { ...user, admin_rank: rank };
}

/** The explanation the admin panel sends with each change (base64 of UTF-8). */
export function adminReason(req: Request, body?: Record<string, unknown>): string | null {
  if (typeof body?.reason === "string" && body.reason.trim()) return body.reason.trim().slice(0, 2000);
  const raw = req.headers.get("x-admin-reason");
  if (!raw) return null;
  try {
    return new TextDecoder().decode(Uint8Array.from(atob(raw), (c) => c.charCodeAt(0))).slice(0, 2000);
  } catch {
    return null;
  }
}

export async function audit(
  staff: Staff, action: string, target: { table?: string; id?: string; user?: string | null }, reason: string | null, details: Record<string, unknown> = {},
) {
  const { error } = await admin.rpc("write_admin_audit", {
    p_admin: staff.id, p_action: action, p_table: target.table ?? null, p_target: target.id ?? null,
    p_user: target.user ?? null, p_reason: reason, p_details: details,
  });
  if (error) console.error("Audit log failed", error.message);
}
