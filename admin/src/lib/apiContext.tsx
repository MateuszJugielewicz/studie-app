import { createContext, useCallback, useContext, useEffect, useState } from "react";
import type { AdminApi } from "./api";
import { DemoAdminApi } from "./demoApi";
import { SupabaseAdminApi } from "./supabaseApi";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const api: AdminApi = url && key ? new SupabaseAdminApi(url, key) : new DemoAdminApi();

export const ApiContext = createContext<AdminApi>(api);
export const useApi = () => useContext(ApiContext);

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
