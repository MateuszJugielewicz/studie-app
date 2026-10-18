// Turns the app's string catalog (ios/EasySesh/Localizable.xcstrings, shared with Android) into one
// small JSON file per language in src/l10n/, loaded on demand by the website.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const catalog = JSON.parse(readFileSync(join(here, "../../ios/EasySesh/Localizable.xcstrings"), "utf8"));
const out = join(here, "../src/l10n");
mkdirSync(out, { recursive: true });

const languages = {};
for (const [key, entry] of Object.entries(catalog.strings)) {
  for (const [lang, localization] of Object.entries(entry.localizations ?? {})) {
    const value = localization.stringUnit?.value;
    if (value && value !== key) (languages[lang] ??= {})[key] = value;
  }
}
for (const [lang, strings] of Object.entries(languages)) {
  writeFileSync(join(out, `${lang}.json`), JSON.stringify(strings));
}
console.log(`l10n: ${Object.keys(languages).length} languages`);
