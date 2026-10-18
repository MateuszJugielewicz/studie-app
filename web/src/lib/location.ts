// The browser's location (with permission) and address lookups via OpenStreetMap (no API key).
import { useEffect, useState } from "react";
import { language } from "./i18n";
import type { GeoPoint } from "./core";

/** Used when location is denied so the page still shows something sensible (same as the apps). */
export const FALLBACK: GeoPoint = { latitude: 37.9838, longitude: 23.7275 }; // Athens

interface LocationState { point: GeoPoint | null; city: string | null; asked: boolean; denied: boolean }
let state: LocationState = { point: null, city: null, asked: false, denied: false };
const listeners = new Set<() => void>();
const emit = (next: Partial<LocationState>) => { state = { ...state, ...next }; listeners.forEach((l) => l()); };

export function requestLocation() {
  if (state.asked || !("geolocation" in navigator)) return;
  emit({ asked: true });
  navigator.geolocation.getCurrentPosition(
    async (pos) => {
      const point = { latitude: pos.coords.latitude, longitude: pos.coords.longitude };
      emit({ point, denied: false });
      emit({ city: await reverseGeocode(point) });
    },
    () => emit({ denied: true }),
    { enableHighAccuracy: false, timeout: 10_000, maximumAge: 600_000 },
  );
}

/** A fresh position for check-in (asks for permission if needed). */
export function freshLocation(): Promise<GeoPoint | null> {
  return new Promise((resolve) => {
    if (!("geolocation" in navigator)) return resolve(null);
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ latitude: pos.coords.latitude, longitude: pos.coords.longitude }),
      () => resolve(null), { enableHighAccuracy: true, timeout: 8000 },
    );
  });
}

export function useLocation() {
  const [, force] = useState(0);
  useEffect(() => { const l = () => force((n) => n + 1); listeners.add(l); return () => { listeners.delete(l); }; }, []);
  return { ...state, effective: state.point ?? FALLBACK, request: requestLocation };
}

async function reverseGeocode(p: GeoPoint): Promise<string | null> {
  try {
    const r = await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&zoom=10&lat=${p.latitude}&lon=${p.longitude}&accept-language=${language()}`);
    const json = await r.json();
    const a = json.address ?? {};
    return a.city ?? a.town ?? a.village ?? a.municipality ?? null;
  } catch { return null; }
}

/** Turns a typed address into coordinates (studio onboarding). */
export async function geocode(address: string): Promise<GeoPoint | null> {
  try {
    const r = await fetch(`https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${encodeURIComponent(address)}`);
    const [first] = await r.json();
    return first ? { latitude: Number(first.lat), longitude: Number(first.lon) } : null;
  } catch { return null; }
}

export const directionsUrl = (p: GeoPoint) => `https://www.google.com/maps/dir/?api=1&destination=${p.latitude},${p.longitude}`;
export const mapsUrl = (p: GeoPoint) => `https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}`;
