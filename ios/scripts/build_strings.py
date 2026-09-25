#!/usr/bin/env python3
"""Builds EasySesh/Localizable.xcstrings from scripts/translations/*.txt.

Each line: English | da | de | pl | el | fr | es | it | sv | nl  (" | " separated, "\\n" = line break).
Strings without a translation fall back to English at runtime.
Run from ios/:  python3 scripts/build_strings.py
"""
import glob
import json
import os

LANGS = ["da", "de", "pl", "el", "fr", "es", "it", "sv", "nl"]
here = os.path.dirname(os.path.abspath(__file__))
rows = {}
for path in sorted(glob.glob(os.path.join(here, "translations", "*.txt"))):
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if not line.strip() or line.startswith("#"):
            continue
        parts = [p.replace("\\n", "\n") for p in line.split(" | ")]
        if len(parts) != len(LANGS) + 1:
            raise SystemExit(f"{os.path.basename(path)}:{number}: expected {len(LANGS) + 1} columns, got {len(parts)}")
        rows[parts[0]] = dict(zip(LANGS, parts[1:]))

catalog = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
for key in sorted(rows):
    catalog["strings"][key] = {
        "extractionState": "manual",
        "localizations": {
            lang: {"stringUnit": {"state": "translated", "value": value}} for lang, value in rows[key].items()
        },
    }
out = os.path.join(here, "..", "EasySesh", "Localizable.xcstrings")
with open(out, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
print(f"Localizable.xcstrings: {len(rows)} strings × {len(LANGS)} languages")
