#!/usr/bin/env python3
"""Generate pinned Unicode break properties and UAX #29 conformance cases."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys
import urllib.request


UNICODE_VERSION = "17.0.0"
INPUTS = {
    "grapheme_property": (
        "https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakProperty.txt",
        "d6b51d1d2ae5c33b451b7ed994b48f1f4dc62b2272a5831e7fd418514a6bae89",
    ),
    "word_property": (
        "https://www.unicode.org/Public/17.0.0/ucd/auxiliary/WordBreakProperty.txt",
        "72274cac1e6b919507db35655c3e175aa27274668a1ece95c28d2069f2ad9852",
    ),
    "sentence_property": (
        "https://www.unicode.org/Public/17.0.0/ucd/auxiliary/SentenceBreakProperty.txt",
        "871c0c985ad95125e25b302414065a10839d068970bceb383ecec138f22a0a18",
    ),
    "derived_core_properties": (
        "https://www.unicode.org/Public/17.0.0/ucd/DerivedCoreProperties.txt",
        "24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08",
    ),
    "emoji_data": (
        "https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt",
        "2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b",
    ),
    "grapheme_test": (
        "https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakTest.txt",
        "e2d134d2c52919bace503ebb6a551c1855fe1a1faec18478c78fff254a1793ec",
    ),
    "word_test": (
        "https://www.unicode.org/Public/17.0.0/ucd/auxiliary/WordBreakTest.txt",
        "1de23a75f37904abc7d206239ee8d34f8fdf0fb4ab32a7174dfbabbde25419b2",
    ),
    "sentence_test": (
        "https://www.unicode.org/Public/17.0.0/ucd/auxiliary/SentenceBreakTest.txt",
        "12cb47d028ded0c1cb8a28558f95479cbcd24559c46977015c82f3b50a1cc6e4",
    ),
}

PROPERTY_NAMES = {
    "grapheme": (
        "Other", "CR", "LF", "Control", "Extend", "ZWJ",
        "Regional_Indicator", "Prepend", "SpacingMark", "L", "V", "T",
        "LV", "LVT",
    ),
    "word": (
        "Other", "CR", "LF", "Newline", "Extend", "ZWJ",
        "Regional_Indicator", "Format", "Katakana", "Hebrew_Letter",
        "ALetter", "Single_Quote", "Double_Quote", "MidNumLet", "MidLetter",
        "MidNum", "Numeric", "ExtendNumLet", "WSegSpace",
    ),
    "sentence": (
        "Other", "CR", "LF", "Sep", "Extend", "Format", "Sp", "Lower",
        "Upper", "OLetter", "Numeric", "ATerm", "STerm", "Close", "SContinue",
    ),
}
INCB_NAMES = ("None", "Consonant", "Extend", "Linker")
EXPECTED_RANGE_COUNTS = {
    "grapheme": 1429,
    "word": 1432,
    "sentence": 2930,
    "incb": 505,
    "extended_pictographic": 451,
}
EXPECTED_CASE_COUNTS = {"grapheme": 766, "word": 1944, "sentence": 512}


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


def parse_properties(
    data: bytes, names: tuple[str, ...]
) -> list[tuple[int, int, int]]:
    ids = {name: index for index, name in enumerate(names)}
    ranges: list[tuple[int, int, int]] = []
    seen: set[str] = set()
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        code_range, name = (field.strip() for field in body.split(";", 1))
        if name not in ids or name == "Other":
            raise SystemExit(f"unexpected break property {name}")
        lo, hi = parse_range(code_range)
        ranges.append((lo, hi, ids[name]))
        seen.add(name)
    missing = set(names) - {"Other"} - seen
    if missing:
        raise SystemExit(f"break property input omitted {sorted(missing)}")
    return sorted(ranges)


def parse_incb(data: bytes) -> list[tuple[int, int, int]]:
    ids = {name: index for index, name in enumerate(INCB_NAMES)}
    ranges: list[tuple[int, int, int]] = []
    seen: set[str] = set()
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) != 3 or fields[1] != "InCB":
            continue
        name = fields[2]
        if name not in ids or name == "None":
            raise SystemExit(f"unexpected Indic_Conjunct_Break property {name}")
        lo, hi = parse_range(fields[0])
        ranges.append((lo, hi, ids[name]))
        seen.add(name)
    missing = set(INCB_NAMES) - {"None"} - seen
    if missing:
        raise SystemExit(f"DerivedCoreProperties omitted InCB values {sorted(missing)}")
    return sorted(ranges)


def parse_extended_pictographic(data: bytes) -> list[tuple[int, int, int]]:
    ranges: list[tuple[int, int, int]] = []
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) != 2 or fields[1] != "Extended_Pictographic":
            continue
        lo, hi = parse_range(fields[0])
        ranges.append((lo, hi, 1))
    if not ranges:
        raise SystemExit("emoji-data omitted Extended_Pictographic")
    return sorted(ranges)


def validate_ranges(name: str, ranges: list[tuple[int, int, int]]) -> None:
    previous_hi = -1
    for lo, hi, _ in ranges:
        if lo > hi or lo <= previous_hi:
            raise SystemExit(f"{name} ranges overlap or are out of order at U+{lo:04X}")
        previous_hi = hi


def parse_tests(data: bytes) -> list[tuple[tuple[int, ...], tuple[int, ...]]]:
    cases: list[tuple[tuple[int, ...], tuple[int, ...]]] = []
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        tokens = body.split()
        boundaries: list[int] = []
        scalars: list[int] = []
        expect_boundary = True
        for token in tokens:
            if expect_boundary:
                if token not in ("÷", "×"):
                    raise SystemExit("break test omitted boundary marker")
                boundaries.append(1 if token == "÷" else 0)
            else:
                scalar = int(token, 16)
                if scalar < 0 or scalar > 0x10FFFF or 0xD800 <= scalar <= 0xDFFF:
                    raise SystemExit("break test contains a non-scalar")
                scalars.append(scalar)
            expect_boundary = not expect_boundary
        if expect_boundary or len(boundaries) != len(scalars) + 1:
            raise SystemExit("malformed break test sequence")
        if boundaries[0] != 1 or boundaries[-1] != 1:
            raise SystemExit("break test must begin and end with a boundary")
        if len(scalars) > 255:
            raise SystemExit("break test exceeds packed scalar count")
        cases.append((tuple(scalars), tuple(boundaries)))
    return cases


def chunks(values: list[tuple], size: int) -> list[list[tuple]]:
    return [values[index : index + size] for index in range(0, len(values), size)]


def encode_property_ranges(values: list[tuple[int, int, int]]) -> str:
    return "".join(f"{lo:06X}{hi:06X}{value:02X}" for lo, hi, value in values)


def generate_property_lookup(name: str, values: list[tuple[int, int, int]]) -> str:
    parts = [f"pub(package) fn unicode_{name}_break_code(scalar: i64) -> i64 {{"]
    table_chunks = chunks(values, 650)
    for index, chunk in enumerate(table_chunks):
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} scalar <= {chunk[-1][1]} {{")
        parts.append(
            "    unicode_segmentation_range_value(scalar, "
            f'__str_ptr("{encode_property_ranges(chunk)}"), {len(chunk)})'
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append("  else { 0 }" + " }" * (len(table_chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def generate_property_source(
    properties: dict[str, list[tuple[int, int, int]]]
) -> str:
    constants: list[str] = []
    for kind, names in PROPERTY_NAMES.items():
        prefix = {"grapheme": "gcb", "word": "wb", "sentence": "sb"}[kind]
        for index, name in enumerate(names):
            constants.append(
                f"pub(package) fn unicode_{prefix}_{name.lower()}() -> i64 {{ {index} }}"
            )
    for index, name in enumerate(INCB_NAMES):
        constants.append(
            f"pub(package) fn unicode_incb_{name.lower()}() -> i64 {{ {index} }}"
        )
    return f'''-- stdlib/unicode_segmentation_data.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION} UAX #29 break properties.
-- GraphemeBreakProperty SHA-256: {INPUTS['grapheme_property'][1]}
-- WordBreakProperty SHA-256: {INPUTS['word_property'][1]}
-- SentenceBreakProperty SHA-256: {INPUTS['sentence_property'][1]}
-- DerivedCoreProperties SHA-256: {INPUTS['derived_core_properties'][1]}
-- emoji-data SHA-256: {INPUTS['emoji_data'][1]}
-- Generator: tools/generate_unicode_segmentation_data.py

use runtime/memory.{{mem_load8_at}}

pub(package) fn unicode_segmentation_data_version() -> str {{ "{UNICODE_VERSION}" }}

pub(package) fn unicode_segmentation_hex_value(ch: i64) -> i64 {{
  if ch >= 48 and ch <= 57 {{ ch - 48 }}
  else {{ if ch >= 65 and ch <= 70 {{ ch - 55 }} else {{ 0 }} }}
}}

pub(package) fn unicode_segmentation_hex(src: i64, offset: i64, digits: i64) -> i64 {{
  let mut value = 0
  let mut i = 0
  while i < digits {{
    value = value * 16 + unicode_segmentation_hex_value(mem_load8_at(src, offset + i))
    i = i + 1
  }}
  value
}}

pub(package) fn unicode_segmentation_range_value(scalar: i64, ranges: i64, count: i64) -> i64 {{
  if scalar < 0 or scalar > 1114111 {{ 0 }}
  else {{
    let mut lo = 0
    let mut hi = count
    let mut result = 0
    let mut found = 0
    while lo < hi and found == 0 {{
      let mid = lo + (hi - lo) / 2
      let offset = mid * 14
      let first = unicode_segmentation_hex(ranges, offset, 6)
      let last = unicode_segmentation_hex(ranges, offset + 6, 6)
      if scalar < first {{ hi = mid }}
      else {{ if scalar > last {{ lo = mid + 1 }}
      else {{ result = unicode_segmentation_hex(ranges, offset + 12, 2) found = 1 }} }}
    }}
    result
  }}
}}

{chr(10).join(constants)}

{generate_property_lookup("grapheme", properties["grapheme"])}

{generate_property_lookup("word", properties["word"])}

{generate_property_lookup("sentence", properties["sentence"])}

{generate_property_lookup("incb", properties["incb"])}

{generate_property_lookup("extended_pictographic", properties["extended_pictographic"])}
'''


def encode_case(case: tuple[tuple[int, ...], tuple[int, ...]]) -> str:
    scalars, boundaries = case
    return (
        f"{len(scalars):02X}"
        + "".join(
            f"{boundaries[index]}{scalar:06X}"
            for index, scalar in enumerate(scalars)
        )
        + str(boundaries[-1])
    )


def encode_case_chunk(
    values: list[tuple[tuple[int, ...], tuple[int, ...]]]
) -> tuple[str, str]:
    offset = 0
    indexes: list[str] = []
    encoded: list[str] = []
    for case in values:
        value = encode_case(case)
        indexes.append(f"{offset:06X}")
        encoded.append(value)
        offset += len(value)
    if offset >= 0x1000000:
        raise SystemExit("segmentation conformance chunk exceeds packed offset")
    return "".join(indexes), "".join(encoded)


def generate_case_lookup(
    name: str, values: list[tuple[tuple[int, ...], tuple[int, ...]]]
) -> str:
    parts = [f"pub(package) fn unicode_{name}_break_test_case(index: i64) -> UnicodeSegmentationTestCase {{"]
    table_chunks = chunks(values, 180)
    first_index = 0
    for chunk_index, chunk in enumerate(table_chunks):
        indexes, data = encode_case_chunk(chunk)
        last_index = first_index + len(chunk)
        prefix = "  if" if chunk_index == 0 else "  else { if"
        parts.append(f"{prefix} index < {last_index} {{")
        parts.append(
            "    unicode_segmentation_test_case_from_tables(index - "
            f'{first_index}, __str_ptr("{indexes}"), __str_ptr("{data}"))'
        )
        parts.append("  }" if chunk_index == 0 else "  }")
        first_index = last_index
    parts.append(
        '  else { UnicodeSegmentationTestCase(__str_ptr(""), 0, 0) }'
        + " }" * (len(table_chunks) - 1)
    )
    parts.append("}")
    return "\n".join(parts)


def generate_test_source(
    tests: dict[str, list[tuple[tuple[int, ...], tuple[int, ...]]]]
) -> str:
    return f'''-- test/unicode_segmentation_conformance_data.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION} complete UAX #29 default-boundary conformance data.
-- GraphemeBreakTest SHA-256: {INPUTS['grapheme_test'][1]}
-- WordBreakTest SHA-256: {INPUTS['word_test'][1]}
-- SentenceBreakTest SHA-256: {INPUTS['sentence_test'][1]}
-- Generator: tools/generate_unicode_segmentation_data.py

use runtime/memory.{{mem_load8_at}}
use stdlib/unicode_segmentation_data.{{unicode_segmentation_hex}}

pub(package) type UnicodeSegmentationTestCase {{
  UnicodeSegmentationTestCase(i64, i64, i64)
}}

pub(package) fn unicode_segmentation_test_case_from_tables(index: i64, indexes: i64, data: i64) -> UnicodeSegmentationTestCase {{
  let offset = unicode_segmentation_hex(indexes, index * 6, 6)
  let count = unicode_segmentation_hex(data, offset, 2)
  UnicodeSegmentationTestCase(data, offset + 2, count)
}}

pub(package) fn unicode_segmentation_test_case_count(value: UnicodeSegmentationTestCase) -> i64 {{
  match value {{ UnicodeSegmentationTestCase(data, offset, count) -> count }}
}}

pub(package) fn unicode_segmentation_test_case_scalar(value: UnicodeSegmentationTestCase, index: i64) -> i64 {{
  match value {{
    UnicodeSegmentationTestCase(data, offset, count) -> unicode_segmentation_hex(data, offset + index * 7 + 1, 6)
  }}
}}

pub(package) fn unicode_segmentation_test_case_boundary(value: UnicodeSegmentationTestCase, index: i64) -> i64 {{
  match value {{
    UnicodeSegmentationTestCase(data, offset, count) -> mem_load8_at(data, offset + index * 7) - 48
  }}
}}

pub(package) fn unicode_grapheme_break_test_count() -> i64 {{ {len(tests["grapheme"])} }}
pub(package) fn unicode_word_break_test_count() -> i64 {{ {len(tests["word"])} }}
pub(package) fn unicode_sentence_break_test_count() -> i64 {{ {len(tests["sentence"])} }}

{generate_case_lookup("grapheme", tests["grapheme"])}

{generate_case_lookup("word", tests["word"])}

{generate_case_lookup("sentence", tests["sentence"])}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in INPUTS:
        parser.add_argument(f"--{name.replace('_', '-')}", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("stdlib/unicode_segmentation_data.weft"),
    )
    parser.add_argument(
        "--test-output",
        type=pathlib.Path,
        default=pathlib.Path("test/unicode_segmentation_conformance_data.weft"),
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    loaded = {name: load(getattr(args, name), name) for name in INPUTS}
    properties = {
        kind: parse_properties(loaded[f"{kind}_property"], PROPERTY_NAMES[kind])
        for kind in PROPERTY_NAMES
    }
    properties["incb"] = parse_incb(loaded["derived_core_properties"])
    properties["extended_pictographic"] = parse_extended_pictographic(
        loaded["emoji_data"]
    )
    range_counts = {kind: len(values) for kind, values in properties.items()}
    if range_counts != EXPECTED_RANGE_COUNTS:
        raise SystemExit(f"Unicode 17 segmentation range counts changed: {range_counts}")
    for kind, ranges in properties.items():
        validate_ranges(kind, ranges)
    tests = {
        kind: parse_tests(loaded[f"{kind}_test"])
        for kind in PROPERTY_NAMES
    }
    counts = {kind: len(values) for kind, values in tests.items()}
    if counts != EXPECTED_CASE_COUNTS:
        raise SystemExit(f"Unicode 17 segmentation case counts changed: {counts}")
    generated = generate_property_source(properties).encode("utf-8")
    generated_tests = generate_test_source(tests).encode("utf-8")

    if args.check:
        stale = False
        for path, expected in ((args.output, generated), (args.test_output, generated_tests)):
            if not path.exists() or path.read_bytes() != expected:
                print(f"out of date: {path}", file=sys.stderr)
                stale = True
        if stale:
            return 1
        print(
            f"ok: Unicode {UNICODE_VERSION} segmentation data "
            f"({counts['grapheme']} grapheme; {counts['word']} word; "
            f"{counts['sentence']} sentence cases)"
        )
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.test_output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(generated)
    args.test_output.write_bytes(generated_tests)
    print(
        f"wrote Unicode {UNICODE_VERSION} segmentation data "
        f"({counts['grapheme']} grapheme; {counts['word']} word; "
        f"{counts['sentence']} sentence cases)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
