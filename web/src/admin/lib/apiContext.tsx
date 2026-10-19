import { createContext, useCallback, useContext, useEffect, useState } from "react";
import type { AdminApi } from "./api";
import type { StaffRank } from "./types";
import { SupabaseAdminApi } from "./supabaseApi";

import { config } from "../../lib/config";

const url = config.supabaseUrl;
const key = config.supabaseAnonKey;

/** Null when the Supabase keys are missing. */
export const api: AdminApi | null = url && key ? new SupabaseAdminApi(url, key) : null;

export const ApiContext = createContext<AdminApi>(api as AdminApi);
export const useApi = () => useContext(ApiContext);

/** The signed-in staff member's rank (owner > admin > support). */
export const StaffContext = createContext<{ email: string; rank: StaffRank }>({ email: "", rank: "support" });
export const useStaff = () => useContext(StaffContext);
const ORDER: StaffRank[] = ["support", "admin", "owner"];
export const rankAtLeast = (rank: StaffRank, minimum: StaffRank) => ORDER.indexOf(rank) >= ORDER.indexOf(minimum);

/** Loads data with `load`, exposing a reload function and loading/error state. */
export function useLoad<T>(load: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      setData(await load());
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);

  useEffect(() => {
    void reload();
  }, [reload]);

  return { data, error, loading, reload };
}
