#!/usr/bin/env python3
"""Generate Weft's pinned Unicode identifier-property tables.

The generated file is checked in; ordinary compiler builds never access the
network or host Unicode libraries. Run with --check to verify an existing
output byte-for-byte, or --input to use an already downloaded UCD file.
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys
import urllib.request


UNICODE_VERSION = "17.0.0"
DERIVED_CORE_PROPERTIES_URL = (
    "https://www.unicode.org/Public/17.0.0/ucd/DerivedCoreProperties.txt"
)
DERIVED_CORE_PROPERTIES_SHA256 = (
    "24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08"
)
PROPERTIES = (
    "XID_Start",
    "XID_Continue",
    "Default_Ignorable_Code_Point",
)


def fetch_input() -> bytes:
    with urllib.request.urlopen(DERIVED_CORE_PROPERTIES_URL) as response:
        return response.read()


def verify_input(data: bytes) -> None:
    actual = hashlib.sha256(data).hexdigest()
    if actual != DERIVED_CORE_PROPERTIES_SHA256:
        raise SystemExit(
            "Unicode input checksum mismatch: "
            f"expected {DERIVED_CORE_PROPERTIES_SHA256}, got {actual}"
        )


def merge_ranges(ranges: list[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for lo, hi in sorted(ranges):
        if not merged or lo > merged[-1][1] + 1:
            merged.append((lo, hi))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], hi))
    return merged


def parse_properties(data: bytes) -> dict[str, list[tuple[int, int]]]:
    found = {name: [] for name in PROPERTIES}
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        code_range, property_name = (part.strip() for part in body.split(";", 1))
        if property_name not in found:
            continue
        first, separator, last = code_range.partition("..")
        lo = int(first, 16)
        hi = int(last, 16) if separator else lo
        found[property_name].append((lo, hi))
    missing = [name for name, ranges in found.items() if not ranges]
    if missing:
        raise SystemExit(f"Unicode input omitted properties: {', '.join(missing)}")
    return {name: merge_ranges(ranges) for name, ranges in found.items()}


def encode_ranges(ranges: list[tuple[int, int]]) -> str:
    return "".join(f"{lo:06X}{hi:06X}" for lo, hi in ranges)


def generate_source(properties: dict[str, list[tuple[int, int]]]) -> str:
    xid_start = encode_ranges(properties["XID_Start"])
    xid_continue = encode_ranges(properties["XID_Continue"])
    default_ignorable = encode_ranges(properties["Default_Ignorable_Code_Point"])
    return f'''-- compiler/unicode_identifier_data.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION}, UAX #31 identifier properties.
-- Source: {DERIVED_CORE_PROPERTIES_URL}
-- SHA-256: {DERIVED_CORE_PROPERTIES_SHA256}
-- Generator: tools/generate_unicode_identifier_data.py
-- Ranges are merged inclusive endpoints, each encoded as two six-digit hex words.

use runtime/memory.{{mem_load8_at}}

pub(package) fn unicode_identifier_data_version() -> str {{ "{UNICODE_VERSION}" }}

pub(package) fn unicode_identifier_hex_value(ch: i64) -> i64 {{
  if ch >= 48 and ch <= 57 {{ ch - 48 }}
  else {{ if ch >= 65 and ch <= 70 {{ ch - 55 }} else {{ 0 }} }}
}}

pub(package) fn unicode_identifier_hex24(src: i64, offset: i64) -> i64 {{
  unicode_identifier_hex_value(mem_load8_at(src, offset)) * 1048576 +
    unicode_identifier_hex_value(mem_load8_at(src, offset + 1)) * 65536 +
    unicode_identifier_hex_value(mem_load8_at(src, offset + 2)) * 4096 +
    unicode_identifier_hex_value(mem_load8_at(src, offset + 3)) * 256 +
    unicode_identifier_hex_value(mem_load8_at(src, offset + 4)) * 16 +
    unicode_identifier_hex_value(mem_load8_at(src, offset + 5))
}}

pub(package) fn unicode_identifier_range_contains(scalar: i64, ranges: i64, count: i64) -> i64 {{
  if scalar < 0 or scalar > 1114111 {{ 0 }}
  else {{
    let mut lo = 0
    let mut hi = count
    let mut found = 0
    while lo < hi and found == 0 {{
      let mid = lo + (hi - lo) / 2
      let offset = mid * 12
      let first = unicode_identifier_hex24(ranges, offset)
      let last = unicode_identifier_hex24(ranges, offset + 6)
      if scalar < first {{ hi = mid }}
      else {{ if scalar > last {{ lo = mid + 1 }} else {{ found = 1 }} }}
    }}
    found
  }}
}}

pub(package) fn unicode_xid_start(scalar: i64) -> i64 {{
  unicode_identifier_range_contains(scalar, __str_ptr("{xid_start}"), {len(properties['XID_Start'])})
}}

pub(package) fn unicode_xid_continue(scalar: i64) -> i64 {{
  unicode_identifier_range_contains(scalar, __str_ptr("{xid_continue}"), {len(properties['XID_Continue'])})
}}

pub(package) fn unicode_default_ignorable(scalar: i64) -> i64 {{
  unicode_identifier_range_contains(scalar, __str_ptr("{default_ignorable}"), {len(properties['Default_Ignorable_Code_Point'])})
}}

pub(package) fn unicode_identifier_profile_start(scalar: i64) -> i64 {{
  if scalar == 95 {{ 1 }}
  else {{ if unicode_xid_start(scalar) == 1 and unicode_default_ignorable(scalar) == 0 {{ 1 }} else {{ 0 }} }}
}}

pub(package) fn unicode_identifier_profile_continue(scalar: i64) -> i64 {{
  if scalar == 95 {{ 1 }}
  else {{ if unicode_xid_continue(scalar) == 1 and unicode_default_ignorable(scalar) == 0 {{ 1 }} else {{ 0 }} }}
}}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("compiler/unicode_identifier_data.weft"),
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    data = args.input.read_bytes() if args.input else fetch_input()
    verify_input(data)
    generated = generate_source(parse_properties(data)).encode("utf-8")

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
