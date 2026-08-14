#!/usr/bin/env python3
"""Generate Weft's pinned Unicode default case-mapping data."""

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
    "special_casing": (
        "https://www.unicode.org/Public/17.0.0/ucd/SpecialCasing.txt",
        "efc25faf19de21b92c1194c111c932e03d2a5eaf18194e33f1156e96de4c9588",
    ),
    "case_folding": (
        "https://www.unicode.org/Public/17.0.0/ucd/CaseFolding.txt",
        "ff8d8fefbf123574205085d6714c36149eb946d717a0c585c27f0f4ef58c4183",
    ),
}


def load(path: pathlib.Path | None, name: str) -> bytes:
    data = path.read_bytes() if path else urllib.request.urlopen(INPUTS[name][0]).read()
    actual = hashlib.sha256(data).hexdigest()
    if actual != INPUTS[name][1]:
        raise SystemExit(
            f"{name} checksum mismatch: expected {INPUTS[name][1]}, got {actual}"
        )
    return data


def scalar_sequence(field: str) -> tuple[int, ...]:
    return tuple(int(value, 16) for value in field.split()) if field else ()


def parse_simple_mappings(
    data: bytes,
) -> tuple[dict[int, tuple[int, ...]], dict[int, tuple[int, ...]], dict[int, tuple[int, ...]]]:
    upper: dict[int, tuple[int, ...]] = {}
    lower: dict[int, tuple[int, ...]] = {}
    title: dict[int, tuple[int, ...]] = {}
    for raw_line in data.decode("utf-8").splitlines():
        fields = raw_line.split(";")
        scalar = int(fields[0], 16)
        if fields[12]:
            upper[scalar] = (int(fields[12], 16),)
        if fields[13]:
            lower[scalar] = (int(fields[13], 16),)
        if fields[14]:
            title[scalar] = (int(fields[14], 16),)
        elif fields[12]:
            # Default Simple_Titlecase_Mapping is Simple_Uppercase_Mapping.
            title[scalar] = (int(fields[12], 16),)
    return upper, lower, title


def apply_unconditional_special_casing(
    data: bytes,
    upper: dict[int, tuple[int, ...]],
    lower: dict[int, tuple[int, ...]],
    title: dict[int, tuple[int, ...]],
) -> int:
    count = 0
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if fields[4]:
            continue
        scalar = int(fields[0], 16)
        lower[scalar] = scalar_sequence(fields[1])
        title[scalar] = scalar_sequence(fields[2])
        upper[scalar] = scalar_sequence(fields[3])
        count += 1
    return count


def default_contexts(data: bytes) -> set[str]:
    contexts: set[str] = set()
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        condition = fields[4]
        if not condition:
            continue
        first = condition.split()[0]
        if first not in ("lt", "tr", "az"):
            contexts.add(condition)
    return contexts


def parse_full_case_folding(data: bytes) -> dict[int, tuple[int, ...]]:
    common: dict[int, tuple[int, ...]] = {}
    full: dict[int, tuple[int, ...]] = {}
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        scalar = int(fields[0], 16)
        status = fields[1]
        mapping = scalar_sequence(fields[2])
        if status == "C":
            common[scalar] = mapping
        elif status == "F":
            full[scalar] = mapping
    common.update(full)
    return common


def non_identity(
    mappings: dict[int, tuple[int, ...]],
) -> list[tuple[int, tuple[int, ...]]]:
    return sorted(
        (scalar, target)
        for scalar, target in mappings.items()
        if target != (scalar,)
    )


def mapping_chunks(
    values: list[tuple[int, tuple[int, ...]]],
    max_entries: int = 700,
    max_scalars: int = 1800,
) -> list[list[tuple[int, tuple[int, ...]]]]:
    result: list[list[tuple[int, tuple[int, ...]]]] = []
    current: list[tuple[int, tuple[int, ...]]] = []
    scalar_count = 0
    for entry in values:
        if current and (
            len(current) >= max_entries or scalar_count + len(entry[1]) > max_scalars
        ):
            result.append(current)
            current = []
            scalar_count = 0
        current.append(entry)
        scalar_count += len(entry[1])
    if current:
        result.append(current)
    return result


def encode_mapping_index(values: list[tuple[int, tuple[int, ...]]]) -> str:
    offset = 0
    encoded: list[str] = []
    for scalar, target in values:
        encoded.append(f"{scalar:06X}{offset:04X}{len(target):02X}")
        offset += len(target)
    return "".join(encoded)


def encode_mapping_values(values: list[tuple[int, tuple[int, ...]]]) -> str:
    return "".join(f"{scalar:06X}" for _, target in values for scalar in target)


def generate_mapping_function(
    function_name: str, values: list[tuple[int, tuple[int, ...]]]
) -> str:
    parts = [f"pub(package) fn {function_name}(scalar: i64, out: i64, count: i64) -> i64 {{"]
    chunks = mapping_chunks(values)
    for index, chunk in enumerate(chunks):
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} scalar <= {chunk[-1][0]} {{")
        parts.append(
            "    unicode_case_mapping_lookup(scalar, "
            f'__str_ptr("{encode_mapping_index(chunk)}"), {len(chunk)}, '
            f'__str_ptr("{encode_mapping_values(chunk)}"), out, count)'
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append("  else { 0 - 1 }" + " }" * (len(chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def generate_source(
    upper: list[tuple[int, tuple[int, ...]]],
    lower: list[tuple[int, tuple[int, ...]]],
    title: list[tuple[int, tuple[int, ...]]],
    folding: list[tuple[int, tuple[int, ...]]],
    unconditional_special_count: int,
) -> str:
    maximum_expansion = max(
        [1]
        + [len(target) for values in (upper, lower, title, folding) for _, target in values]
    )
    return f'''-- stdlib/unicode_case_data.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION} default full case mappings and case folding.
-- UnicodeData SHA-256: {INPUTS['unicode_data'][1]}
-- SpecialCasing SHA-256: {INPUTS['special_casing'][1]}
-- CaseFolding SHA-256: {INPUTS['case_folding'][1]}
-- Unconditional SpecialCasing entries: {unconditional_special_count}
-- Generator: tools/generate_unicode_case_data.py

use runtime/memory.{{mem_load8_at, mem_store64_at}}

pub(package) fn unicode_case_data_version() -> str {{ "{UNICODE_VERSION}" }}
pub(package) fn unicode_case_max_expansion() -> i64 {{ {maximum_expansion} }}

pub(package) fn unicode_case_hex_value(ch: i64) -> i64 {{
  if ch >= 48 and ch <= 57 {{ ch - 48 }}
  else {{ if ch >= 65 and ch <= 70 {{ ch - 55 }} else {{ 0 }} }}
}}

pub(package) fn unicode_case_hex(src: i64, offset: i64, digits: i64) -> i64 {{
  let mut value = 0
  let mut i = 0
  while i < digits {{
    value = value * 16 + unicode_case_hex_value(mem_load8_at(src, offset + i))
    i = i + 1
  }}
  value
}}

pub(package) fn unicode_case_mapping_lookup(scalar: i64, entries: i64, entry_count: i64, values: i64, out: i64, count: i64) -> i64 {{
  let mut lo = 0
  let mut hi = entry_count
  let mut found = 0 - 1
  while lo < hi and found < 0 {{
    let mid = lo + (hi - lo) / 2
    let key = unicode_case_hex(entries, mid * 12, 6)
    if scalar < key {{ hi = mid }}
    else {{ if scalar > key {{ lo = mid + 1 }} else {{ found = mid }} }}
  }}
  if found < 0 {{ 0 - 1 }}
  else {{
    let entry_offset = found * 12
    let value_offset = unicode_case_hex(entries, entry_offset + 6, 4)
    let value_count = unicode_case_hex(entries, entry_offset + 10, 2)
    let mut next = count
    let mut i = 0
    while i < value_count {{
      mem_store64_at(out, next * 8, unicode_case_hex(values, (value_offset + i) * 6, 6))
      next = next + 1
      i = i + 1
    }}
    next
  }}
}}

{generate_mapping_function("unicode_full_uppercase_map_into", upper)}

{generate_mapping_function("unicode_full_lowercase_map_into", lower)}

{generate_mapping_function("unicode_full_titlecase_map_into", title)}

{generate_mapping_function("unicode_full_casefold_map_into", folding)}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in INPUTS:
        parser.add_argument(f"--{name.replace('_', '-')}", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("stdlib/unicode_case_data.weft"),
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    loaded = {name: load(getattr(args, name), name) for name in INPUTS}
    upper, lower, title = parse_simple_mappings(loaded["unicode_data"])
    special_count = apply_unconditional_special_casing(
        loaded["special_casing"], upper, lower, title
    )
    contexts = default_contexts(loaded["special_casing"])
    if contexts != {"Final_Sigma"}:
        raise SystemExit(
            "unsupported locale-neutral SpecialCasing contexts: "
            + ", ".join(sorted(contexts))
        )
    folding = parse_full_case_folding(loaded["case_folding"])
    tables = tuple(non_identity(table) for table in (upper, lower, title, folding))
    generated = generate_source(*tables, special_count).encode("utf-8")

    summary = (
        f"Unicode {UNICODE_VERSION}; upper {len(tables[0])}; lower {len(tables[1])}; "
        f"title {len(tables[2])}; fold {len(tables[3])}; special {special_count}"
    )
    if args.check:
        if not args.output.exists() or args.output.read_bytes() != generated:
            print(f"out of date: {args.output}", file=sys.stderr)
            return 1
        print(f"ok: {args.output} ({summary})")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(generated)
    print(f"wrote {args.output} ({summary})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
