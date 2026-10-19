#!/usr/bin/env python3
"""Merge translated units into the macOS string catalogs (Python 3.9+).

    python3 scripts/shellx/l10n/import_translations.py --map DIR/vi-missing-00.vi.json [--map ...]
    python3 scripts/shellx/l10n/import_translations.py --staged DIR      # en-to-ids.json + batch-NN.{en,vi}.json
    python3 scripts/shellx/l10n/import_translations.py --map fixes.json --replace   # rewrite existing values
    python3 scripts/shellx/l10n/import_translations.py --identity reasons.json ...  # {key: reason} for vi == English
    add --dry-run to validate without writing

Inputs:
  --map FILE    {"<unit id>": "<translation>"} or {"<unit id>": {"vi": ..., "en": ...}}
                (unit ids as written by export_missing.py). Later files win.
  --staged DIR  deduplicated batches: en-to-ids.json ({English: [unit ids]}) plus
                batch-NN.en.json ([{i, en, comment}]) / batch-NN.vi.json ({"i": translation}).
                --map entries win over staged ones.

Each entry gets the locale built from the English shape: a stringUnit, a
`variations.plural.other` for a plural, and for each substitution the same
argNum/formatSpecifier with `variations.plural.other` (Vietnamese has only the
plural category "other"). An entry is refused, and left untouched, when a
translation's placeholders or line breaks differ from the English, when the
English changed since translation (beyond the cmux -> ShellX rebrand), or when
`scripts/localization_catalog.py check` would reject it. Only the new locale
block is inserted (same 2-space layout as the catalog), so the git diff adds
lines; rerunning is a no-op. Existing translations stay unless --replace.
"""
from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import export_missing  # noqa: E402
from export_missing import ROOT, catalog_tool, source_units, target_unit  # noqa: E402

REBRAND = re.compile(r"cmux|shellx", re.I)


def translated(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def compose(english: dict, units: dict[str, str]) -> dict:
    """The locale block for one entry, shaped like the English one."""
    localization: dict = {}
    if "stringUnit" in english:
        localization.update(translated(units["value"]))
    if "plural" in english.get("variations", {}):
        localization["variations"] = {"plural": {"other": translated(units["plural.other"])}}
    if english.get("substitutions"):
        localization["substitutions"] = {
            name: {
                "argNum": substitution.get("argNum"),
                "formatSpecifier": substitution.get("formatSpecifier"),
                "variations": {"plural": {"other": translated(units[f"sub.{name}.other"])}},
            }
            for name, substitution in english["substitutions"].items()
        }
    return localization


def same_after_rebrand(a: str, b: str) -> bool:
    return REBRAND.sub("X", a) == REBRAND.sub("X", b)


def unit_problem(english: str, target: str, known_english: str | None) -> str | None:
    if known_english is not None and known_english != english and not same_after_rebrand(known_english, english):
        return f"English changed since translation: {known_english!r} -> {english!r}"
    if catalog_tool.placeholders(target) != catalog_tool.placeholders(english):
        return f"placeholders {catalog_tool.placeholders(target)} != {catalog_tool.placeholders(english)}"
    if target.count("\n") != english.count("\n"):
        return "line breaks differ"
    if not target.strip() and english.strip():
        return "empty translation"
    return None


def import_text(text: str, path: str, translations: dict, locale: str = "vi", *, validate: bool = True,
                replace: bool = False, omissions: dict | None = None, counts: dict | None = None):
    """Return (new text, stats). `translations` maps unit id -> str or {"vi"/locale, "en"}."""
    if validate and (omissions is None or counts is None):
        omissions = catalog_tool.load_metadata("localization-allowed-omissions.json")
        counts = catalog_tool.load_metadata("localization-plurals.json")
    stats = {"added": 0, "replaced": 0, "unchanged": 0, "missing": [], "refused": []}
    changes = []
    for entry in catalog_tool.catalog_entries(text):
        if entry.value.get("shouldTranslate") is False:
            continue
        localizations = entry.value.get("localizations", {})
        english = localizations.get("en", {})
        current = localizations.get(locale)
        sources = source_units(english)
        complete = current is not None and all(target_unit(current, suffix) for suffix, _ in sources)
        if complete and not replace:
            stats["unchanged"] += 1
            continue
        units, problems = {}, []
        for suffix, source in sources:
            unit_id = f"{path}::{entry.key}::{suffix}"
            row = translations.get(unit_id)
            if row is None:
                kept = target_unit(current, suffix) if current else None
                if kept is None:
                    stats["missing"].append(unit_id)
                    problems.append(None)
                    continue
                units[suffix] = kept
                continue
            value, known = (row, None) if isinstance(row, str) else (row.get(locale, row.get("vi")), row.get("en"))
            if not isinstance(value, str):
                stats["missing"].append(unit_id)
                problems.append(None)
                continue
            problem = unit_problem(source, value, known)
            if problem:
                problems.append(f"{suffix}: {problem}")
            units[suffix] = value
        if problems:
            reasons = [problem for problem in problems if problem]
            if reasons:
                stats["refused"].append({"path": path, "key": entry.key, "reason": "; ".join(reasons)})
            continue
        localization = compose(english, units)
        if current == localization:
            stats["unchanged"] += 1
            continue
        if validate:
            candidate = copy.deepcopy(entry.value)
            candidate.setdefault("localizations", {})[locale] = localization
            errors = catalog_tool.check_entry(catalog_tool.Member(entry.key, candidate, 0, 0), locale, omissions, counts)
            if errors:
                stats["refused"].append({"path": path, "key": entry.key, "reason": "; ".join(errors)})
                continue
        changes.append(catalog_tool.replace_locale(text, entry, locale, localization))
        stats["replaced" if current is not None else "added"] += 1
    text = catalog_tool.apply_changes(text, changes)
    catalog_tool.catalog_entries(text)
    return text, stats


def load_staged(folder: Path) -> dict:
    """Unit id -> {"vi", "en"} from deduplicated staging batches."""
    ids = json.loads((folder / "en-to-ids.json").read_text(encoding="utf-8"))
    result = {}
    for source in sorted(folder.glob("batch-*.en.json")):
        target = source.with_name(source.name.replace(".en.json", ".vi.json"))
        if not target.exists():
            continue
        translations = json.loads(target.read_text(encoding="utf-8"))
        for row in json.loads(source.read_text(encoding="utf-8")):
            value = translations.get(str(row["i"]))
            if isinstance(value, str):
                for unit_id in ids.get(row["en"], []):
                    result[unit_id] = {"vi": value, "en": row["en"]}
    return result


def load_map(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected an object of unit id -> translation")
    # An export batch next to the answers supplies the English it was translated from.
    batch = path.with_name(path.name.replace(".vi.json", ".json"))
    english = {}
    if batch != path and batch.exists():
        english = {row["id"]: row["en"] for row in json.loads(batch.read_text(encoding="utf-8"))}
    return {unit_id: (value if isinstance(value, dict) else ({"vi": value, "en": english[unit_id]} if unit_id in english else value))
            for unit_id, value in data.items()}


OMISSIONS = "localization-allowed-omissions.json"


def record_identity(omissions: dict, reasons: dict, english: dict, locale: str) -> tuple[int, list[str]]:
    """Add identityLocales.<locale> reasons (a reviewed translation spelled like the English).

    Returns (records changed, keys refused because the metadata names another English source).
    """
    changed, refused = 0, []
    for key, reason in reasons.items():
        if key not in english or not isinstance(reason, str) or not reason.strip():
            refused.append(key)
            continue
        record = omissions.get(key)
        if record is None:
            omissions[key] = {"source": english[key], "identityLocales": {locale: reason}}
            changed += 1
        elif record.get("source") != english[key]:
            refused.append(key)
        elif record.setdefault("identityLocales", {}).get(locale) != reason:
            record["identityLocales"][locale] = reason
            changed += 1
    return changed, refused


def english_sources(root: Path) -> dict:
    sources = {}
    for path, _relative in export_missing.covered_catalogs(root):
        for entry in catalog_tool.catalog_entries(path.read_text(encoding="utf-8")):
            sources.setdefault(entry.key, catalog_tool.source(entry.value))
    return sources


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--locale", default="vi", choices=[locale for locale in catalog_tool.LOCALES if locale != "en"])
    parser.add_argument("--staged", type=Path, action="append", default=[])
    parser.add_argument("--map", type=Path, action="append", default=[])
    parser.add_argument("--replace", action="store_true", help="also rewrite existing translations")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--report", type=Path, help="write refused and missing units here as JSON")
    parser.add_argument("--identity", type=Path, action="append", default=[],
                        help=f"JSON {{key: reason}}: record identityLocales.<locale> in scripts/{OMISSIONS}"
                             " for reviewed translations spelled like the English")
    args = parser.parse_args()
    translations: dict = {}
    for folder in args.staged:
        translations.update(load_staged(folder))
    for path in args.map:
        translations.update(load_map(path))
    omissions = catalog_tool.load_metadata(OMISSIONS)
    counts = catalog_tool.load_metadata("localization-plurals.json")
    refused, missing = [], []
    if args.identity:
        reasons = {}
        for path in args.identity:
            reasons.update(json.loads(path.read_text(encoding="utf-8")))
        changed, bad = record_identity(omissions, reasons, english_sources(args.root), args.locale)
        refused.extend({"path": "scripts/" + OMISSIONS, "key": key, "reason": "unknown key or another English source"}
                       for key in bad)
        print(f"scripts/{OMISSIONS}: {changed} {args.locale} identity records")
        if changed and not args.dry_run:
            # Same layout as the checked-in file (2-space indent, raw UTF-8), so the diff only adds records.
            catalog_tool.atomic_write(catalog_tool.ROOT / "scripts" / OMISSIONS,
                                      json.dumps(omissions, ensure_ascii=False, indent=2) + "\n")
    for path, relative in export_missing.covered_catalogs(args.root):
        original = path.read_text(encoding="utf-8")
        text, stats = import_text(original, relative, translations, args.locale, replace=args.replace,
                                  omissions=omissions, counts=counts)
        if text != original and not args.dry_run:
            catalog_tool.atomic_write(path, text)
        refused.extend(stats["refused"])
        missing.extend(stats["missing"])
        print(f"{relative}: added {stats['added']}, replaced {stats['replaced']}, unchanged {stats['unchanged']}, "
              f"refused {len(stats['refused'])}, missing {len(stats['missing'])}")
    for row in refused[:20]:
        print(f"refused {row['path']}:{row['key']}: {row['reason'][:300]}", file=sys.stderr)
    if args.report:
        args.report.write_text(json.dumps({"refused": refused, "missing": missing}, ensure_ascii=False, indent=1) + "\n",
                               encoding="utf-8")
    return 1 if refused or missing else 0


if __name__ == "__main__":
    raise SystemExit(main())
