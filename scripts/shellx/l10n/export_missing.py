#!/usr/bin/env python3
"""Export the macOS catalog units that still lack a translation (Python 3.9+).

    python3 scripts/shellx/l10n/export_missing.py --out /tmp/vi-batches
    python3 scripts/shellx/l10n/export_missing.py --locale vi --batch-size 300 --out DIR

Covers the catalogs `scripts/localization_catalog.py check` validates. Writes
`<locale>-missing-NN.json` files, each a list of at most 300
`{"id": ..., "en": ..., "comment": ...}` rows. A translator answers each batch
with `<locale>-missing-NN.vi.json` = `{"<id>": "<translation>"}`, which
`import_translations.py --map` merges back (see vi-glossary.md).

Unit ids are `<catalog path>::<key>::value` for a plain string,
`::plural.other` for a plural variation and `::sub.<name>.other` for a plural
substitution. Vietnamese has only the plural category "other", so every count
string is one unit.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MAX_BATCH = 300
sys.path.insert(0, str(ROOT / "scripts"))
import localization_catalog as catalog_tool  # noqa: E402


def leaf(node: dict) -> str | None:
    value = node.get("stringUnit", {}).get("value") if isinstance(node, dict) else None
    return value if isinstance(value, str) else None


def plural_source(plural: dict) -> str | None:
    return leaf(plural.get("other") or plural.get("one") or {})


def source_units(english: dict) -> list[tuple[str, str]]:
    """(unit suffix, English text) for every translatable unit of one entry."""
    found = []
    if "stringUnit" in english:
        found.append(("value", leaf(english)))
    variations = english.get("variations", {})
    unsupported = set(variations) - {"plural"}
    if unsupported:
        raise ValueError(f"unsupported variations {sorted(unsupported)}")
    if "plural" in variations:
        found.append(("plural.other", plural_source(variations["plural"])))
    for name, substitution in english.get("substitutions", {}).items():
        plural = substitution.get("variations", {}).get("plural")
        if plural is None:
            raise ValueError(f"substitution {name} has no plural variation")
        found.append((f"sub.{name}.other", plural_source(plural)))
    return [(suffix, text) for suffix, text in found if isinstance(text, str)]


def target_unit(localization: dict | None, suffix: str) -> str | None:
    """The translated text of one unit in a locale, or None when absent."""
    if not localization:
        return None
    if suffix == "value":
        node = localization
    elif suffix == "plural.other":
        node = localization.get("variations", {}).get("plural", {}).get("other", {})
    else:
        name = suffix[len("sub."):-len(".other")]
        node = localization.get("substitutions", {}).get(name, {}).get("variations", {}).get("plural", {}).get("other", {})
    unit = node.get("stringUnit", {})
    value = unit.get("value")
    if unit.get("state") != "translated" or not isinstance(value, str) or not value.strip():
        return None
    return value


def missing_units(text: str, path: str, locale: str = "vi") -> list[dict]:
    rows = []
    for entry in catalog_tool.catalog_entries(text):
        if entry.value.get("shouldTranslate") is False:
            continue
        localizations = entry.value.get("localizations", {})
        for suffix, english in source_units(localizations.get("en", {})):
            if target_unit(localizations.get(locale), suffix) is None:
                rows.append({"id": f"{path}::{entry.key}::{suffix}", "en": english,
                             "comment": entry.value.get("comment", "")})
    return rows


def batched(rows: list[dict], size: int = MAX_BATCH) -> list[list[dict]]:
    if not 1 <= size <= MAX_BATCH:
        raise ValueError(f"batch size must be between 1 and {MAX_BATCH}")
    return [rows[start:start + size] for start in range(0, len(rows), size)]


def covered_catalogs(root: Path = ROOT) -> list[tuple[Path, str]]:
    return [(path, path.relative_to(root).as_posix()) for path in catalog_tool.discover(root)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--locale", default="vi")
    parser.add_argument("--batch-size", type=int, default=MAX_BATCH)
    parser.add_argument("--out", type=Path, help="directory for the batch files; omitted prints counts only")
    args = parser.parse_args()
    rows = []
    for path, relative in covered_catalogs(args.root):
        found = missing_units(path.read_text(encoding="utf-8"), relative, args.locale)
        print(f"{relative}: {len(found)} missing {args.locale} units")
        rows.extend(found)
    batches = batched(rows, args.batch_size)
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        for number, batch in enumerate(batches):
            target = args.out / f"{args.locale}-missing-{number:02d}.json"
            target.write_text(json.dumps(batch, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(rows)} missing units in {len(batches)} batches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
