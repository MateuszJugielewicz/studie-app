// Translations come from the apps' string catalog (ios/EasySesh/Localizable.xcstrings), split per
// language by scripts/build-l10n.mjs. English text is the key, exactly like in the apps.

export interface Language { code: string; name: string; flag: string }

export const LANGUAGES: Language[] = [
  { code: "en", name: "English", flag: "🇬🇧" },
  { code: "da", name: "Dansk", flag: "🇩🇰" },
  { code: "de", name: "Deutsch", flag: "🇩🇪" },
  { code: "pl", name: "Polski", flag: "🇵🇱" },
  { code: "el", name: "Ελληνικά", flag: "🇬🇷" },
  { code: "fr", name: "Français", flag: "🇫🇷" },
  { code: "es", name: "Español", flag: "🇪🇸" },
  { code: "it", name: "Italiano", flag: "🇮🇹" },
  { code: "sv", name: "Svenska", flag: "🇸🇪" },
  { code: "nl", name: "Nederlands", flag: "🇳🇱" },
];

const loaders = import.meta.glob<{ default: Record<string, string> }>("../l10n/*.json");

let current = "en";
let strings: Record<string, string> = {};
const listeners = new Set<() => void>();

export function storedLanguage(): string {
  try {
    const saved = localStorage.getItem("easysesh.language");
    if (saved && LANGUAGES.some((l) => l.code === saved)) return saved;
  } catch { /* storage blocked */ }
  const browser = (navigator.language || "en").slice(0, 2).toLowerCase();
  return LANGUAGES.some((l) => l.code === browser) ? browser : "en";
}

export async function setLanguage(code: string, remember = true): Promise<void> {
  const loader = loaders[`../l10n/${code}.json`];
  strings = code !== "en" && loader ? (await loader()).default : {};
  current = code;
  document.documentElement.lang = code;
  if (remember) try { localStorage.setItem("easysesh.language", code); } catch { /* ignore */ }
  listeners.forEach((l) => l());
}

export const language = () => current;
/** Formatting locale: the browser's regional variant when it matches the chosen language (en-GB, de-AT…). */
export const locale = () => {
  const browser = navigator.languages?.find((l) => l.toLowerCase().startsWith(current)) ?? "";
  return browser || (current === "en" ? "en-GB" : current);
};
export function onLanguageChange(listener: () => void) { listeners.add(listener); return () => { listeners.delete(listener); }; }

/** Translated text for an English key. */
export function t(key: string): string {
  return strings[key] ?? key;
}

/**
 * String with arguments, using the catalog's iOS format specifiers (%@, %lld, %1$@ …).
 * Numbers are formatted for the current language.
 */
export function format(key: string, ...args: (string | number)[]): string {
  const template = t(key);
  let index = 0;
  return template.replace(/%(?:(\d+)\$)?(@|lld|ld|d|%)/g, (_, position: string | undefined, spec: string) => {
    if (spec === "%") return "%";
    const value = args[position ? Number(position) - 1 : index++];
    if (value === undefined) return "";
    return typeof value === "number" ? new Intl.NumberFormat(locale()).format(value) : value;
  });
}
