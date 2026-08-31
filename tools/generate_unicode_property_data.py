#!/usr/bin/env python3
"""Generate Weft's pinned public Unicode property substrate."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys
import urllib.request


UNICODE_VERSION = "17.0.0"
INPUTS = {
    "unicode_data": (
        "https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt",
        "2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c",
    ),
    "scripts": (
        "https://www.unicode.org/Public/17.0.0/ucd/Scripts.txt",
        "9f5e50d3abaee7d6ce09480f325c706f485ae3240912527e651954d2d6b035bf",
    ),
    "derived_core": (
        "https://www.unicode.org/Public/17.0.0/ucd/DerivedCoreProperties.txt",
        "24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08",
    ),
    "prop_list": (
        "https://www.unicode.org/Public/17.0.0/ucd/PropList.txt",
        "130dcddcaadaf071008bdfce1e7743e04fdfbc910886f017d9f9ac931d8c64dd",
    ),
    "emoji_data": (
        "https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt",
        "2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b",
    ),
}

DERIVED_PROPERTIES = (
    "Alphabetic",
    "Lowercase",
    "Uppercase",
    "Cased",
    "Case_Ignorable",
    "Grapheme_Base",
    "Grapheme_Extend",
    "Grapheme_Link",
)
PROP_LIST_PROPERTIES = (
    "White_Space",
    "Pattern_White_Space",
    "Pattern_Syntax",
    "Join_Control",
    "Regional_Indicator",
    "Prepended_Concatenation_Mark",
    "Variation_Selector",
    "Noncharacter_Code_Point",
    "Bidi_Control",
    "Soft_Dotted",
)
EMOJI_PROPERTIES = ("Extended_Pictographic",)
BINARY_PROPERTIES = DERIVED_PROPERTIES + PROP_LIST_PROPERTIES + EMOJI_PROPERTIES


def load(path: pathlib.Path | None, name: str) -> bytes:
    data = path.read_bytes() if path else urllib.request.urlopen(INPUTS[name][0]).read()
    actual = hashlib.sha256(data).hexdigest()
    if actual != INPUTS[name][1]:
        raise SystemExit(
            f"{name} checksum mismatch: expected {INPUTS[name][1]}, got {actual}"
        )
    return data


def parse_range(text: str) -> tuple[int, int]:
    first, separator, last = text.partition("..")
    lo = int(first, 16)
    return lo, int(last, 16) if separator else lo


def merge_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for lo, hi in sorted(ranges):
        if not merged or lo > merged[-1][1] + 1:
            merged.append((lo, hi))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], hi))
    return merged


def merge_value_ranges(
    ranges: list[tuple[int, int, str]],
) -> list[tuple[int, int, str]]:
    merged: list[tuple[int, int, str]] = []
    for lo, hi, value in sorted(ranges):
        if merged and value == merged[-1][2] and lo == merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], hi, value)
        else:
            merged.append((lo, hi, value))
    return merged


def parse_unicode_categories(data: bytes) -> list[tuple[int, int, str]]:
    ranges: list[tuple[int, int, str]] = []
    pending: tuple[int, str] | None = None
    for raw_line in data.decode("utf-8").splitlines():
        fields = raw_line.split(";")
        scalar = int(fields[0], 16)
        name = fields[1]
        category = fields[2]
        if name.endswith(", First>"):
            if pending is not None:
                raise SystemExit("nested UnicodeData range")
            pending = (scalar, category)
        elif name.endswith(", Last>"):
            if pending is None or pending[1] != category:
                raise SystemExit("invalid UnicodeData range end")
            ranges.append((pending[0], scalar, category))
            pending = None
        else:
            ranges.append((scalar, scalar, category))
    if pending is not None:
        raise SystemExit("unterminated UnicodeData range")
    return merge_value_ranges(ranges)


def parse_named_ranges(data: bytes) -> list[tuple[int, int, str]]:
    ranges: list[tuple[int, int, str]] = []
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        code_range, value = (field.strip() for field in body.split(";", 1))
        lo, hi = parse_range(code_range)
        ranges.append((lo, hi, value))
    return merge_value_ranges(ranges)


def parse_binary_properties(
    inputs: tuple[tuple[bytes, tuple[str, ...]], ...],
) -> dict[str, list[tuple[int, int]]]:
    found = {name: [] for name in BINARY_PROPERTIES}
    for data, accepted in inputs:
        for raw_line in data.decode("utf-8").splitlines():
            body = raw_line.split("#", 1)[0].strip()
            if not body:
                continue
            fields = [field.strip() for field in body.split(";")]
            property_name = fields[1]
            if property_name not in accepted:
                continue
            found[property_name].append(parse_range(fields[0]))
    missing = [name for name, ranges in found.items() if not ranges]
    if missing:
        raise SystemExit(f"Unicode inputs omitted properties: {', '.join(missing)}")
    return {name: merge_ranges(ranges) for name, ranges in found.items()}


def binary_mask_ranges(
    properties: dict[str, list[tuple[int, int]]],
) -> list[tuple[int, int, int]]:
    events: dict[int, list[tuple[int, bool]]] = {}
    for index, name in enumerate(BINARY_PROPERTIES):
        bit = 1 << index
        for lo, hi in properties[name]:
            events.setdefault(lo, []).append((bit, True))
            if hi < 0x10FFFF:
                events.setdefault(hi + 1, []).append((bit, False))
    result: list[tuple[int, int, int]] = []
    mask = 0
    previous = 0
    for position in sorted(events):
        if mask and position > previous:
            if result and result[-1][2] == mask and result[-1][1] + 1 == previous:
                result[-1] = (result[-1][0], position - 1, mask)
            else:
                result.append((previous, position - 1, mask))
        for bit, present in events[position]:
            mask = (mask | bit) if present else (mask & ~bit)
        previous = position
    if mask:
        result.append((previous, 0x10FFFF, mask))
    return result


def chunks(values: list[tuple], size: int) -> list[list[tuple]]:
    return [values[index : index + size] for index in range(0, len(values), size)]


def encode_value_ranges(values: list[tuple[int, int, int]], digits: int) -> str:
    return "".join(
        f"{lo:06X}{hi:06X}{value:0{digits}X}" for lo, hi, value in values
    )


def generate_chunked_lookup(
    function_name: str,
    values: list[tuple[int, int, int]],
    value_digits: int,
    default: int,
) -> str:
    parts = [f"pub(package) fn {function_name}(scalar: i64) -> i64 {{"]
    table_chunks = chunks(values, 600)
    for index, chunk in enumerate(table_chunks):
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} scalar <= {chunk[-1][1]} {{")
        parts.append(
            "    unicode_property_range_value(scalar, "
            f'__str_ptr("{encode_value_ranges(chunk, value_digits)}"), '
            f"{len(chunk)}, {value_digits}, {default})"
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append(f"  else {{ {default} }}" + " }" * (len(table_chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def generate_name_lookup(function_name: str, names: list[str], default: str) -> str:
    arms = "\n".join(f'    {index} -> "{name}"' for index, name in enumerate(names))
    return f'''pub(package) fn {function_name}(value: i64) -> str {{
  match value {{
{arms}
    _ -> "{default}"
  }}
}}'''


def generate_source(
    categories: list[tuple[int, int, str]],
    scripts: list[tuple[int, int, str]],
    binary_ranges: list[tuple[int, int, int]],
) -> str:
    category_names = sorted({value for _, _, value in categories} | {"Cn"})
    script_names = sorted({value for _, _, value in scripts} | {"Unknown"})
    category_ids = {name: index for index, name in enumerate(category_names)}
    script_ids = {name: index for index, name in enumerate(script_names)}
    encoded_categories = [
        (lo, hi, category_ids[value]) for lo, hi, value in categories
    ]
    encoded_scripts = [(lo, hi, script_ids[value]) for lo, hi, value in scripts]
    binary_bits = "\n".join(
        f"pub(package) fn unicode_property_{name.lower()}_bit() -> i64 {{ {1 << index} }}"
        for index, name in enumerate(BINARY_PROPERTIES)
    )
    return f'''-- stdlib/unicode/data/property.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION} general-category, script and binary properties.
-- UnicodeData SHA-256: {INPUTS['unicode_data'][1]}
-- Scripts SHA-256: {INPUTS['scripts'][1]}
-- DerivedCoreProperties SHA-256: {INPUTS['derived_core'][1]}
-- PropList SHA-256: {INPUTS['prop_list'][1]}
-- emoji-data SHA-256: {INPUTS['emoji_data'][1]}
-- Generator: tools/generate_unicode_property_data.py

use runtime/memory.{{mem_load8_at}}

pub(package) fn unicode_property_data_version() -> str {{ "{UNICODE_VERSION}" }}

pub(package) fn unicode_property_hex_value(ch: i64) -> i64 {{
  if ch >= 48 and ch <= 57 {{ ch - 48 }}
  else {{ if ch >= 65 and ch <= 70 {{ ch - 55 }} else {{ 0 }} }}
}}

pub(package) fn unicode_property_hex(src: i64, offset: i64, digits: i64) -> i64 {{
  let mut value = 0
  let mut i = 0
  while i < digits {{
    value = value * 16 + unicode_property_hex_value(mem_load8_at(src, offset + i))
    i = i + 1
  }}
  value
}}

pub(package) fn unicode_property_range_value(scalar: i64, ranges: i64, count: i64, value_digits: i64, default: i64) -> i64 {{
  if scalar < 0 or scalar > 1114111 {{ default }}
  else {{
    let width = 12 + value_digits
    let mut lo = 0
    let mut hi = count
    let mut result = default
    let mut found = 0
    while lo < hi and found == 0 {{
      let mid = lo + (hi - lo) / 2
      let offset = mid * width
      let first = unicode_property_hex(ranges, offset, 6)
      let last = unicode_property_hex(ranges, offset + 6, 6)
      if scalar < first {{ hi = mid }}
      else {{ if scalar > last {{ lo = mid + 1 }}
      else {{ result = unicode_property_hex(ranges, offset + 12, value_digits) found = 1 }} }}
    }}
    result
  }}
}}

{generate_chunked_lookup("unicode_general_category_code", encoded_categories, 2, category_ids["Cn"])}

{generate_name_lookup("unicode_general_category_name", category_names, "Cn")}

{generate_chunked_lookup("unicode_script_code", encoded_scripts, 2, script_ids["Unknown"])}

{generate_name_lookup("unicode_script_name", script_names, "Unknown")}

{generate_chunked_lookup("unicode_binary_property_mask", binary_ranges, 5, 0)}

{binary_bits}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in INPUTS:
        parser.add_argument(f"--{name.replace('_', '-')}", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("stdlib/unicode/data/property.weft"),
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    loaded = {
        name: load(getattr(args, name), name)
        for name in INPUTS
    }
    categories = parse_unicode_categories(loaded["unicode_data"])
    scripts = parse_named_ranges(loaded["scripts"])
    binary = parse_binary_properties(
        (
            (loaded["derived_core"], DERIVED_PROPERTIES),
            (loaded["prop_list"], PROP_LIST_PROPERTIES),
            (loaded["emoji_data"], EMOJI_PROPERTIES),
        )
    )
    generated = generate_source(
        categories, scripts, binary_mask_ranges(binary)
    ).encode("utf-8")

    if args.check:
        if not args.output.exists() or args.output.read_bytes() != generated:
            print(f"out of date: {args.output}", file=sys.stderr)
            return 1
        print(f"ok: {args.output} (Unicode {UNICODE_VERSION})")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(generated)
    print(f"wrote {args.output} (Unicode {UNICODE_VERSION})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
