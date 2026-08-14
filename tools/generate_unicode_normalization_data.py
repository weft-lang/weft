#!/usr/bin/env python3
"""Generate the pinned Unicode NFC quick-check substrate for Weft."""

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
    "derived_normalization": (
        "https://www.unicode.org/Public/17.0.0/ucd/DerivedNormalizationProps.txt",
        "71fd6a206a2c0cdd41feb6b7f656aa31091db45e9cedc926985d718397f9e488",
    ),
    "normalization_test": (
        "https://www.unicode.org/Public/17.0.0/ucd/NormalizationTest.txt",
        "5019ffd530751a741900c849c0e010332f142a3612234639bd200b82138a87db",
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
    values: list[tuple[int, int]],
) -> list[tuple[int, int, int]]:
    merged: list[tuple[int, int, int]] = []
    for codepoint, value in sorted(values):
        if merged and value == merged[-1][2] and codepoint == merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], codepoint, value)
        else:
            merged.append((codepoint, codepoint, value))
    return merged


def parse_derived(data: bytes) -> tuple[list[tuple[int, int]], list[tuple[int, int]], set[int]]:
    no: list[tuple[int, int]] = []
    maybe: list[tuple[int, int]] = []
    exclusions: set[int] = set()
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        lo, hi = parse_range(fields[0])
        if fields[1] == "NFC_QC" and fields[2] == "N":
            no.append((lo, hi))
        elif fields[1] == "NFC_QC" and fields[2] == "M":
            maybe.append((lo, hi))
        elif fields[1] == "Full_Composition_Exclusion":
            exclusions.update(range(lo, hi + 1))
    return merge_ranges(no), merge_ranges(maybe), exclusions


def parse_unicode_data(
    data: bytes, exclusions: set[int]
) -> tuple[
    list[tuple[int, int, int]],
    list[tuple[int, tuple[int, ...]]],
    list[tuple[int, int, int]],
]:
    combining: list[tuple[int, int]] = []
    decompositions: list[tuple[int, tuple[int, ...]]] = []
    compositions: list[tuple[int, int, int]] = []
    pending_range: tuple[int, int] | None = None
    for line in data.decode("utf-8").splitlines():
        fields = line.split(";")
        codepoint = int(fields[0], 16)
        name = fields[1]
        ccc = int(fields[3])
        if name.endswith(", First>"):
            pending_range = (codepoint, ccc)
        elif name.endswith(", Last>"):
            if pending_range is None:
                raise SystemExit("UnicodeData range end without range start")
            first, range_ccc = pending_range
            if range_ccc:
                combining.extend((scalar, range_ccc) for scalar in range(first, codepoint + 1))
            pending_range = None
        elif ccc:
            combining.append((codepoint, ccc))

        decomposition = fields[5]
        if decomposition and not decomposition.startswith("<"):
            parts = [int(part, 16) for part in decomposition.split()]
            decompositions.append((codepoint, tuple(parts)))
            if len(parts) == 2 and codepoint not in exclusions:
                compositions.append((parts[0], parts[1], codepoint))
    if pending_range is not None:
        raise SystemExit("UnicodeData unterminated range")
    return (
        merge_value_ranges(combining),
        sorted(decompositions),
        sorted(set(compositions)),
    )


def in_ranges(value: int, ranges: list[tuple[int, int]]) -> bool:
    lo = 0
    hi = len(ranges)
    while lo < hi:
        mid = lo + (hi - lo) // 2
        first, last = ranges[mid]
        if value < first:
            hi = mid
        elif value > last:
            lo = mid + 1
        else:
            return True
    return False


def combining_class(value: int, ranges: list[tuple[int, int, int]]) -> int:
    lo = 0
    hi = len(ranges)
    while lo < hi:
        mid = lo + (hi - lo) // 2
        first, last, ccc = ranges[mid]
        if value < first:
            hi = mid
        elif value > last:
            lo = mid + 1
        else:
            return ccc
    return 0


def hangul_composition(first: int, second: int) -> int | None:
    if 0x1100 <= first < 0x1100 + 19 and 0x1161 <= second < 0x1161 + 21:
        return 0xAC00 + ((first - 0x1100) * 21 + (second - 0x1161)) * 28
    s_index = first - 0xAC00
    if (
        0 <= s_index < 11172
        and s_index % 28 == 0
        and 0x11A7 < second < 0x11A7 + 28
    ):
        return first + second - 0x11A7
    return None


def canonical_decompose(
    scalar: int,
    decompositions: dict[int, tuple[int, ...]],
) -> tuple[int, ...]:
    if 0xAC00 <= scalar < 0xAC00 + 11172:
        s_index = scalar - 0xAC00
        leading = 0x1100 + s_index // 588
        vowel = 0x1161 + (s_index % 588) // 28
        trailing_index = s_index % 28
        if trailing_index:
            return (leading, vowel, 0x11A7 + trailing_index)
        return (leading, vowel)
    direct = decompositions.get(scalar)
    if direct is None:
        return (scalar,)
    return tuple(
        nested
        for part in direct
        for nested in canonical_decompose(part, decompositions)
    )


def normalize_nfc(
    scalars: tuple[int, ...],
    combining: list[tuple[int, int, int]],
    decompositions: dict[int, tuple[int, ...]],
    compositions: dict[tuple[int, int], int],
) -> tuple[int, ...]:
    ordered: list[int] = []
    segment_start = 0
    for scalar in scalars:
        for part in canonical_decompose(scalar, decompositions):
            ccc = combining_class(part, combining)
            if ccc == 0:
                ordered.append(part)
                segment_start = len(ordered)
            else:
                insert = len(ordered)
                while insert > segment_start:
                    previous_ccc = combining_class(ordered[insert - 1], combining)
                    if previous_ccc <= ccc:
                        break
                    insert -= 1
                ordered.insert(insert, part)

    if not ordered:
        return ()
    composed = [ordered[0]]
    starter_index = 0 if combining_class(ordered[0], combining) == 0 else -1
    last_ccc = 0
    for scalar in ordered[1:]:
        ccc = combining_class(scalar, combining)
        unblocked = last_ccc == 0 or last_ccc < ccc
        replacement = None
        if starter_index >= 0 and unblocked:
            starter = composed[starter_index]
            replacement = compositions.get((starter, scalar))
            if replacement is None:
                replacement = hangul_composition(starter, scalar)
        if replacement is not None:
            composed[starter_index] = replacement
        else:
            if ccc == 0:
                starter_index = len(composed)
            composed.append(scalar)
            last_ccc = ccc
    return tuple(composed)


def parse_sequence(text: str) -> tuple[int, ...]:
    return tuple(int(value, 16) for value in text.strip().split())


def verify_conformance(
    data: bytes,
    combining: list[tuple[int, int, int]],
    decompositions: list[tuple[int, tuple[int, ...]]],
    compositions: list[tuple[int, int, int]],
) -> int:
    decomposition_map = dict(decompositions)
    composition_map = {(first, second): result for first, second, result in compositions}
    checked = 0
    for line_number, raw_line in enumerate(data.decode("utf-8").splitlines(), 1):
        body = raw_line.split("#", 1)[0].strip()
        if not body or body.startswith("@"):
            continue
        columns = [parse_sequence(column) for column in body.split(";")[:5]]
        c1, c2, c3, c4, c5 = columns
        expected = (c1 == c2, True, c3 == c2, True, c5 == c4)
        for index, (sequence, wanted) in enumerate(zip(columns, expected), 1):
            actual = normalize_nfc(
                sequence, combining, decomposition_map, composition_map
            ) == sequence
            if actual != wanted:
                raise SystemExit(
                    f"NormalizationTest line {line_number} column {index}: "
                    f"is_nfc={actual}, expected {wanted}"
                )
            checked += 1
    return checked


def encode_ranges(ranges: list[tuple[int, int]]) -> str:
    return "".join(f"{lo:06X}{hi:06X}" for lo, hi in ranges)


def encode_value_ranges(ranges: list[tuple[int, int, int]]) -> str:
    return "".join(f"{lo:06X}{hi:06X}{value:03X}" for lo, hi, value in ranges)


def encode_decompositions(values: list[tuple[int, tuple[int, ...]]]) -> str:
    return "".join(
        f"{scalar:06X}{len(parts):01X}{parts[0]:06X}"
        f"{parts[1] if len(parts) == 2 else 0:06X}"
        for scalar, parts in values
    )


def encode_compositions(values: list[tuple[int, int, int]]) -> str:
    return "".join(
        f"{first:06X}{second:06X}{result:06X}"
        for first, second, result in values
    )


def chunks(values: list[tuple], size: int) -> list[list[tuple]]:
    return [values[index : index + size] for index in range(0, len(values), size)]


def generate_decomposition_lookup(values: list[tuple[int, tuple[int, ...]]]) -> str:
    parts = [
        "pub(package) fn unicode_canonical_decomposition_lookup(scalar: i64, values: i64, count: i64) -> i64 {",
        "  let mut lo = 0",
        "  let mut hi = count",
        "  let mut result = 0",
        "  while lo < hi and result == 0 {",
        "    let mid = lo + (hi - lo) / 2",
        "    let offset = mid * 19",
        "    let key = unicode_normalization_hex(values, offset, 6)",
        "    if scalar < key { hi = mid }",
        "    else { if scalar > key { lo = mid + 1 }",
        "    else {",
        "      let count = unicode_normalization_hex(values, offset + 6, 1)",
        "      let first = unicode_normalization_hex(values, offset + 7, 6)",
        "      let second = unicode_normalization_hex(values, offset + 13, 6)",
        "      result = count * 4398046511104 + first * 2097152 + second",
        "    } }",
        "  }",
        "  result",
        "}",
        "",
        "pub(package) fn unicode_canonical_decomposition(scalar: i64) -> i64 {",
    ]
    table_chunks = chunks(values, 700)
    for index, chunk in enumerate(table_chunks):
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} scalar <= {chunk[-1][0]} {{")
        parts.append(
            "    unicode_canonical_decomposition_lookup(scalar, "
            f'__str_ptr("{encode_decompositions(chunk)}"), {len(chunk)})'
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append("  else { 0 }" + " }" * (len(table_chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def generate_composition_lookup(values: list[tuple[int, int, int]]) -> str:
    parts = [
        "pub(package) fn unicode_canonical_composition_lookup(first: i64, second: i64, values: i64, count: i64) -> i64 {",
        "  let mut lo = 0",
        "  let mut hi = count",
        "  let mut result = 0 - 1",
        "  while lo < hi and result < 0 {",
        "    let mid = lo + (hi - lo) / 2",
        "    let offset = mid * 18",
        "    let pair_first = unicode_normalization_hex(values, offset, 6)",
        "    let pair_second = unicode_normalization_hex(values, offset + 6, 6)",
        "    if first < pair_first or (first == pair_first and second < pair_second) { hi = mid }",
        "    else { if first > pair_first or (first == pair_first and second > pair_second) { lo = mid + 1 }",
        "    else { result = unicode_normalization_hex(values, offset + 12, 6) } }",
        "  }",
        "  result",
        "}",
        "",
        "pub(package) fn unicode_canonical_composition(first: i64, second: i64) -> i64 {",
    ]
    table_chunks = chunks(values, 700)
    for index, chunk in enumerate(table_chunks):
        max_first, max_second, _ = chunk[-1]
        condition = f"first < {max_first} or (first == {max_first} and second <= {max_second})"
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} {condition} {{")
        parts.append(
            "    unicode_canonical_composition_lookup(first, second, "
            f'__str_ptr("{encode_compositions(chunk)}"), {len(chunk)})'
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append("  else { 0 - 1 }" + " }" * (len(table_chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def generate_source(
    no: list[tuple[int, int]],
    maybe: list[tuple[int, int]],
    combining: list[tuple[int, int, int]],
    decompositions: list[tuple[int, tuple[int, ...]]],
    compositions: list[tuple[int, int, int]],
    conformance_cases: int,
) -> str:
    return f'''-- compiler/unicode_normalization_data.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION} NFC quick-check and canonical-composition substrate.
-- UnicodeData SHA-256: {INPUTS['unicode_data'][1]}
-- DerivedNormalizationProps SHA-256: {INPUTS['derived_normalization'][1]}
-- NormalizationTest SHA-256: {INPUTS['normalization_test'][1]}
-- Generator: tools/generate_unicode_normalization_data.py
-- Generator conformance: {conformance_cases} NormalizationTest sequence checks.

use compiler/source_position.{{source_position_utf8_scalar, source_position_utf8_width}}
use runtime/alloc.{{alloc_words}}
use runtime/memory.{{mem_load8_at, mem_load64_at, mem_store64_at}}

pub(package) fn unicode_normalization_data_version() -> str {{ "{UNICODE_VERSION}" }}

pub(package) fn unicode_normalization_hex_value(ch: i64) -> i64 {{
  if ch >= 48 and ch <= 57 {{ ch - 48 }}
  else {{ if ch >= 65 and ch <= 70 {{ ch - 55 }} else {{ 0 }} }}
}}

pub(package) fn unicode_normalization_hex(src: i64, offset: i64, digits: i64) -> i64 {{
  let mut i = 0
  let mut value = 0
  while i < digits {{
    value = value * 16 + unicode_normalization_hex_value(mem_load8_at(src, offset + i))
    i = i + 1
  }}
  value
}}

pub(package) fn unicode_normalization_range_contains(scalar: i64, ranges: i64, count: i64) -> i64 {{
  if scalar < 0 or scalar > 1114111 {{ 0 }}
  else {{
    let mut lo = 0
    let mut hi = count
    let mut found = 0
    while lo < hi and found == 0 {{
      let mid = lo + (hi - lo) / 2
      let offset = mid * 12
      let first = unicode_normalization_hex(ranges, offset, 6)
      let last = unicode_normalization_hex(ranges, offset + 6, 6)
      if scalar < first {{ hi = mid }}
      else {{ if scalar > last {{ lo = mid + 1 }} else {{ found = 1 }} }}
    }}
    found
  }}
}}

pub(package) fn unicode_nfc_quick_check_no(scalar: i64) -> i64 {{
  unicode_normalization_range_contains(scalar, __str_ptr("{encode_ranges(no)}"), {len(no)})
}}

pub(package) fn unicode_nfc_quick_check_maybe(scalar: i64) -> i64 {{
  unicode_normalization_range_contains(scalar, __str_ptr("{encode_ranges(maybe)}"), {len(maybe)})
}}

pub(package) fn unicode_canonical_combining_class(scalar: i64) -> i64 {{
  let ranges = __str_ptr("{encode_value_ranges(combining)}")
  let mut lo = 0
  let mut hi = {len(combining)}
  let mut result = 0
  while lo < hi and result == 0 {{
    let mid = lo + (hi - lo) / 2
    let offset = mid * 15
    let first = unicode_normalization_hex(ranges, offset, 6)
    let last = unicode_normalization_hex(ranges, offset + 6, 6)
    if scalar < first {{ hi = mid }}
    else {{ if scalar > last {{ lo = mid + 1 }}
    else {{ result = unicode_normalization_hex(ranges, offset + 12, 3) }} }}
  }}
  result
}}

{generate_decomposition_lookup(decompositions)}

{generate_composition_lookup(compositions)}

pub(package) fn unicode_hangul_composition(first: i64, second: i64) -> i64 {{
  if first >= 4352 and first < 4371 and second >= 4449 and second < 4470 {{
    44032 + ((first - 4352) * 21 + (second - 4449)) * 28
  }}
  else {{
    let s_index = first - 44032
    if s_index >= 0 and s_index < 11172 and s_index % 28 == 0 and second > 4519 and second < 4547 {{ first + second - 4519 }}
    else {{ 0 - 1 }}
  }}
}}

pub(package) fn unicode_canonical_decompose_into(scalar: i64, out: i64, count: i64) -> i64 {{
  if scalar >= 44032 and scalar < 55204 {{
    let s_index = scalar - 44032
    mem_store64_at(out, count * 8, 4352 + s_index / 588)
    mem_store64_at(out, count * 8 + 8, 4449 + (s_index % 588) / 28)
    let trailing = s_index % 28
    if trailing == 0 {{ count + 2 }}
    else {{ mem_store64_at(out, count * 8 + 16, 4519 + trailing) count + 3 }}
  }} else {{
    let packed = unicode_canonical_decomposition(scalar)
    if packed == 0 {{ mem_store64_at(out, count * 8, scalar) count + 1 }}
    else {{
      let parts = packed / 4398046511104
      let remainder = packed - parts * 4398046511104
      let first = remainder / 2097152
      let second = remainder - first * 2097152
      let after_first = unicode_canonical_decompose_into(first, out, count)
      if parts == 1 {{ after_first }} else {{ unicode_canonical_decompose_into(second, out, after_first) }}
    }}
  }}
}}

pub(package) fn unicode_canonical_order(values: i64, count: i64) -> i64 {{
  let mut i = 1
  while i < count {{
    let scalar = mem_load64_at(values, i * 8)
    let ccc = unicode_canonical_combining_class(scalar)
    if ccc != 0 {{
      let mut j = i
      let mut done = 0
      while j > 0 and done == 0 {{
        let previous = mem_load64_at(values, (j - 1) * 8)
        let previous_ccc = unicode_canonical_combining_class(previous)
        if previous_ccc == 0 or previous_ccc <= ccc {{ done = 1 }}
        else {{ mem_store64_at(values, j * 8, previous) j = j - 1 }}
      }}
      mem_store64_at(values, j * 8, scalar)
    }} else {{ 0 }}
    i = i + 1
  }}
  count
}}

pub(package) fn unicode_canonical_compose(values: i64, count: i64, out: i64) -> i64 {{
  if count == 0 {{ 0 }}
  else {{
    let first = mem_load64_at(values, 0)
    mem_store64_at(out, 0, first)
    let mut out_count = 1
    let mut starter_index = if unicode_canonical_combining_class(first) == 0 {{ 0 }} else {{ 0 - 1 }}
    let mut last_ccc = 0
    let mut i = 1
    while i < count {{
      let scalar = mem_load64_at(values, i * 8)
      let ccc = unicode_canonical_combining_class(scalar)
      let unblocked = last_ccc == 0 or last_ccc < ccc
      let mut replacement = 0 - 1
      if starter_index >= 0 and unblocked {{
        let starter = mem_load64_at(out, starter_index * 8)
        replacement = unicode_canonical_composition(starter, scalar)
        if replacement < 0 {{ replacement = unicode_hangul_composition(starter, scalar) }} else {{ 0 }}
      }} else {{ 0 }}
      if replacement >= 0 {{ mem_store64_at(out, starter_index * 8, replacement) }}
      else {{
        if ccc == 0 {{ starter_index = out_count }} else {{ 0 }}
        mem_store64_at(out, out_count * 8, scalar)
        out_count = out_count + 1
        last_ccc = ccc
      }}
      i = i + 1
    }}
    out_count
  }}
}}

pub(package) fn unicode_bytes_are_nfc(src: i64, start: i64, len: i64) -> i64 {{
  let end = start + len
  let mut pos = start
  let decomposed = alloc_words(len * 4 + 4)
  let mut decomposed_count = 0
  let mut valid = 1
  while pos < end and valid == 1 {{
    let width = source_position_utf8_width(src, end, pos)
    let scalar = source_position_utf8_scalar(src, end, pos)
    if width < 0 or scalar < 0 {{ valid = 0 }}
    else {{ decomposed_count = unicode_canonical_decompose_into(scalar, decomposed, decomposed_count) pos = pos + width }}
  }}
  if valid == 0 or pos != end {{ 0 }}
  else {{
    unicode_canonical_order(decomposed, decomposed_count)
    let composed = alloc_words(decomposed_count + 1)
    let composed_count = unicode_canonical_compose(decomposed, decomposed_count, composed)
    let mut source_pos = start
    let mut index = 0
    let mut equal = 1
    while source_pos < end and index < composed_count and equal == 1 {{
      let width = source_position_utf8_width(src, end, source_pos)
      let scalar = source_position_utf8_scalar(src, end, source_pos)
      if width < 0 or scalar != mem_load64_at(composed, index * 8) {{ equal = 0 }}
      else {{ source_pos = source_pos + width index = index + 1 }}
    }}
    if equal == 1 and source_pos == end and index == composed_count {{ 1 }} else {{ 0 }}
  }}
}}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--unicode-data", type=pathlib.Path)
    parser.add_argument("--derived-normalization", type=pathlib.Path)
    parser.add_argument("--normalization-test", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("compiler/unicode_normalization_data.weft"),
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    unicode_data = load(args.unicode_data, "unicode_data")
    derived = load(args.derived_normalization, "derived_normalization")
    normalization_test = load(args.normalization_test, "normalization_test")
    no, maybe, exclusions = parse_derived(derived)
    combining, decompositions, compositions = parse_unicode_data(unicode_data, exclusions)
    conformance_cases = verify_conformance(
        normalization_test, combining, decompositions, compositions
    )
    generated = generate_source(
        no, maybe, combining, decompositions, compositions, conformance_cases
    ).encode("utf-8")

    if args.check:
        if not args.output.exists() or args.output.read_bytes() != generated:
            print(f"out of date: {args.output}", file=sys.stderr)
            return 1
        print(
            f"ok: {args.output} (Unicode {UNICODE_VERSION}; "
            f"{conformance_cases} conformance checks)"
        )
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(generated)
    print(
        f"wrote {args.output} (Unicode {UNICODE_VERSION}; "
        f"{conformance_cases} conformance checks)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
