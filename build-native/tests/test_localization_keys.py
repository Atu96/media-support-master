#!/usr/bin/env python3
"""Verify every Localizable.strings file has the same keys and placeholders."""

from __future__ import annotations

import pathlib
import re
import sys


def placeholders(value: str) -> list[str]:
    return sorted(re.findall(r"%(?:\d+\$)?(?:[-+ #0']*\d*(?:\.\d+)?)?[a-zA-Z@]", value))


root = pathlib.Path(sys.argv[1])
locales = sys.argv[2:]
tables: dict[str, dict[str, str]] = {}
for locale in locales:
    path = root / f"{locale}.lproj" / "Localizable.strings"
    table: dict[str, str] = {}
    entry = re.compile(r'^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;\s*$')
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("/*") or stripped.startswith("//"):
            continue
        match = entry.match(line)
        if not match:
            raise SystemExit(f"{locale}:{line_number}: invalid .strings entry")
        key, value = match.groups()
        if key in table:
            raise SystemExit(f"{locale}:{line_number}: duplicate key {key!r}")
        table[key] = value
    tables[locale] = table

reference = tables[locales[0]]
for locale in locales[1:]:
    current = tables[locale]
    missing = sorted(reference.keys() - current.keys())
    extra = sorted(current.keys() - reference.keys())
    if missing or extra:
        raise SystemExit(f"{locale}: missing={missing}, extra={extra}")
    for key, value in current.items():
        expected = placeholders(reference[key])
        actual = placeholders(value)
        if actual != expected:
            raise SystemExit(
                f"{locale}: placeholder mismatch for {key!r}: {actual} != {expected}"
            )

# Static SwiftUI copy is localized automatically only when its source string is
# present in Localizable.strings. Guard Vietnamese literals so a new control
# cannot silently ship untranslated.
source_root = root.parent.parent
swift_text = "\n".join(
    path.read_text(encoding="utf-8", errors="ignore")
    for path in source_root.rglob("*.swift")
)
static_patterns = [
    r'(?:Text|Button|Label|Picker|Section|ContentUnavailableView)\(\s*"([^"]*)"',
    r'(?:help|accessibilityLabel|accessibilityHint)\(\s*"([^"]*)"',
    r'AppPillButton\(\s*title:\s*"([^"]*)"',
    r'timeline(?:Tool|CueEdit)Button\([^\n]*?title:\s*"([^"]*)"',
]
static_keys: set[str] = set()
for pattern in static_patterns:
    static_keys.update(re.findall(pattern, swift_text))
missing_static = sorted(
    key
    for key in static_keys
    if "\\(" not in key
    and any(ord(character) > 127 for character in key)
    and key not in reference
)
if missing_static:
    raise SystemExit(f"unlocalized static UI strings: {missing_static}")

# English must never silently fall back to Vietnamese. Proper names and format
# tokens may match, but Vietnamese copy with distinctive characters may not.
english = tables.get("en", {})
english_fallbacks = sorted(
    key for key, value in english.items()
    if key == value and any(character in key for character in "ăâđêôơưĂÂĐÊÔƠƯ")
)
if english_fallbacks:
    raise SystemExit(f"English still falls back to Vietnamese: {english_fallbacks}")

print(f"localization keys: {len(reference)} · locales: {len(locales)}")
