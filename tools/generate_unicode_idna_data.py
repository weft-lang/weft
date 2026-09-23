#!/usr/bin/env python3
"""Generate pinned Unicode UTS #46 data and the complete ToASCII corpus."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import sys
import urllib.request

import weft_generated_source


UNICODE_VERSION = "17.0.0"
UTS46_REVISION = "35"
INPUTS = {
    "mapping": (
        "https://www.unicode.org/Public/17.0.0/idna/IdnaMappingTable.txt",
        "87f05505dc026fdb2bff16132bdc68a8014675836882a9a2b1844540ad3be382",
    ),
    "tests": (
        "https://www.unicode.org/Public/17.0.0/idna/IdnaTestV2.txt",
        "beb5d0be20e896189b03209a82fdc34f06351502bbd4b8e2523583fc2954d9cf",
    ),
    "bidi": (
        "https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedBidiClass.txt",
        "4867b4b7f0731ed1bfcd34cc6251211ff1542541fce0734b6fbda139ee80b3a4",
    ),
    "joining": (
        "https://www.unicode.org/Public/17.0.0/ucd/extracted/DerivedJoiningType.txt",
        "f39ebe974825d6736aee15582250307aa532b2cfab3caf3f86bd23fddc9c5c4d",
    ),
}

BIDI_NAMES = (
    "Left_To_Right",
    "Right_To_Left",
    "Arabic_Letter",
    "European_Number",
    "Arabic_Number",
    "European_Separator",
    "Common_Separator",
    "European_Terminator",
    "Other_Neutral",
    "Boundary_Neutral",
    "Nonspacing_Mark",
    "Paragraph_Separator",
    "Segment_Separator",
    "White_Space",
    "Left_To_Right_Embedding",
    "Left_To_Right_Override",
    "Right_To_Left_Embedding",
    "Right_To_Left_Override",
    "Pop_Directional_Format",
    "Left_To_Right_Isolate",
    "Right_To_Left_Isolate",
    "First_Strong_Isolate",
    "Pop_Directional_Isolate",
)
BIDI_ALIASES = (
    "L", "R", "AL", "EN", "AN", "ES", "CS", "ET", "ON", "BN", "NSM",
    "B", "S", "WS", "LRE", "LRO", "RLE", "RLO", "PDF", "LRI", "RLI",
    "FSI", "PDI",
)
JOINING_NAMES = (
    "Non_Joining",
    "Left_Joining",
    "Dual_Joining",
    "Right_Joining",
    "Join_Causing",
    "Transparent",
)
JOINING_ALIASES = ("U", "L", "D", "R", "C", "T")
EXPECTED_MAPPING_ROWS = 9262
EXPECTED_TEST_ROWS = 6391


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


def chunks(values: list, size: int) -> list[list]:
    return [values[index : index + size] for index in range(0, len(values), size)]


def parse_mapping(
    data: bytes,
) -> list[tuple[int, int, int, tuple[int, ...]]]:
    rows: list[tuple[int, int, int, tuple[int, ...]]] = []
    input_rows = 0
    previous_hi = -1
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        input_rows += 1
        fields = [field.strip() for field in body.split(";")]
        if len(fields) < 2:
            raise SystemExit("malformed IDNA mapping row")
        lo, hi = parse_range(fields[0])
        if lo != previous_hi + 1:
            raise SystemExit(f"IDNA mapping table has a gap at U+{lo:04X}")
        previous_hi = hi
        status = fields[1]
        mapping = tuple(int(value, 16) for value in fields[2].split()) if len(fields) > 2 else ()
        if status in ("valid", "deviation"):
            if mapping and status == "valid":
                raise SystemExit(f"valid mapping row has a replacement at U+{lo:04X}")
            continue
        if status == "ignored":
            kind = 0
            mapping = ()
        elif status == "mapped":
            kind = 1
            if not mapping:
                raise SystemExit(f"mapped row lacks a replacement at U+{lo:04X}")
        elif status in (
            "disallowed",
            "disallowed_STD3_valid",
            "disallowed_STD3_mapped",
        ):
            kind = 2
            mapping = ()
        else:
            raise SystemExit(f"unexpected IDNA mapping status {status}")
        if len(mapping) > 255:
            raise SystemExit(f"IDNA mapping expansion is too large at U+{lo:04X}")
        rows.append((lo, hi, kind, mapping))
    if previous_hi != 0x10FFFF:
        raise SystemExit("IDNA mapping table does not cover the Unicode range")
    if input_rows != EXPECTED_MAPPING_ROWS:
        raise SystemExit(f"Unicode 17 IDNA mapping row count changed: {input_rows}")
    return rows


def parse_property(
    data: bytes, names: tuple[str, ...], aliases: tuple[str, ...]
) -> list[tuple[int, int, int]]:
    ids = {name: index for index, name in enumerate(names)}
    ids.update({name: index for index, name in enumerate(aliases)})
    values = [0] * 0x110000
    text = data.decode("utf-8")
    for raw_line in text.splitlines():
        if not raw_line.startswith("# @missing:"):
            continue
        fields = [field.strip() for field in raw_line[11:].split(";")]
        if len(fields) != 2 or fields[1] not in ids:
            raise SystemExit(f"malformed property default: {raw_line}")
        lo, hi = parse_range(fields[0])
        code = ids[fields[1]]
        values[lo : hi + 1] = [code] * (hi - lo + 1)
    for raw_line in text.splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if len(fields) != 2 or fields[1] not in ids:
            raise SystemExit(f"unexpected property row: {body}")
        lo, hi = parse_range(fields[0])
        code = ids[fields[1]]
        values[lo : hi + 1] = [code] * (hi - lo + 1)
    ranges: list[tuple[int, int, int]] = []
    lo = 0
    code = values[0]
    for scalar in range(1, 0x110000):
        if values[scalar] != code:
            ranges.append((lo, scalar - 1, code))
            lo = scalar
            code = values[scalar]
    ranges.append((lo, 0x10FFFF, code))
    return ranges


ESCAPE = re.compile(r"\\u([0-9A-Fa-f]{4})|\\x\{([0-9A-Fa-f]+)\}")


def decode_field(field: str) -> tuple[str | None, bool]:
    value = field.strip()
    if value == '""':
        return "", True
    scalars: list[int] = []
    pos = 0
    for match in ESCAPE.finditer(value):
        scalars.extend(ord(ch) for ch in value[pos : match.start()])
        scalars.append(int(match.group(1) or match.group(2), 16))
        pos = match.end()
    scalars.extend(ord(ch) for ch in value[pos:])
    result: list[str] = []
    index = 0
    while index < len(scalars):
        scalar = scalars[index]
        if 0xD800 <= scalar <= 0xDBFF and index + 1 < len(scalars):
            low = scalars[index + 1]
            if 0xDC00 <= low <= 0xDFFF:
                scalar = 0x10000 + (scalar - 0xD800) * 0x400 + low - 0xDC00
                index += 1
        if scalar > 0x10FFFF or 0xD800 <= scalar <= 0xDFFF:
            return None, False
        result.append(chr(scalar))
        index += 1
    return "".join(result), True


def parse_status(field: str, fallback: frozenset[str]) -> frozenset[str]:
    value = field.strip()
    if not value:
        return fallback
    if value == "[]":
        return frozenset()
    if not (value.startswith("[") and value.endswith("]")):
        raise SystemExit(f"malformed IDNA test status {field}")
    return frozenset(part.strip() for part in value[1:-1].split(",") if part.strip())


def absolute_root_artifact_is_only_error(
    ascii_value: str, ascii_status: frozenset[str]
) -> bool:
    """Accept the trailing DNS root while preserving real A4_2 failures."""
    if not ascii_value.endswith(".") or ascii_status != frozenset(("A4_2",)):
        return False
    canonical = ascii_value[:-1]
    try:
        canonical_bytes = canonical.encode("ascii")
        labels = [label.encode("ascii") for label in canonical.split(".")]
    except UnicodeEncodeError:
        return False
    return (
        bool(canonical)
        and len(canonical_bytes) <= 253
        and all(0 < len(label) <= 63 for label in labels)
    )


def parse_tests(
    data: bytes,
) -> tuple[list[tuple[bytes, bytes, int, int]], int]:
    cases: list[tuple[bytes, bytes, int, int]] = []
    skipped_ill_formed = 0
    input_rows = 0
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0]
        if not body.strip():
            continue
        fields = body.split(";")
        if len(fields) < 7:
            raise SystemExit(f"malformed IDNA test row: {raw_line}")
        input_rows += 1
        source, source_ok = decode_field(fields[0])
        if not source_ok or source is None:
            skipped_ill_formed += 1
            continue
        to_unicode, unicode_ok = decode_field(fields[1]) if fields[1].strip() else (source, True)
        if not unicode_ok or to_unicode is None:
            raise SystemExit("well-formed IDNA source has an ill-formed Unicode result")
        unicode_status = parse_status(fields[2], frozenset())
        ascii_value, ascii_ok = decode_field(fields[3]) if fields[3].strip() else (to_unicode, True)
        if not ascii_ok or ascii_value is None:
            raise SystemExit("well-formed IDNA source has an ill-formed ASCII result")
        ascii_status = parse_status(fields[4], unicode_status)
        absolute = 1 if ascii_value.endswith(".") else 0
        root_artifact_only = absolute_root_artifact_is_only_error(
            ascii_value, ascii_status
        )
        succeeds = 1 if not ascii_status or root_artifact_only else 0
        expected = ascii_value[:-1] if absolute == 1 else ascii_value
        source_bytes = source.encode("utf-8")
        expected_bytes = expected.encode("ascii") if succeeds == 1 else b""
        if len(source_bytes) > 0xFFFF or len(expected_bytes) > 0xFFFF:
            raise SystemExit("IDNA conformance case exceeds packed length")
        cases.append((source_bytes, expected_bytes, succeeds, absolute))
    if input_rows != EXPECTED_TEST_ROWS:
        raise SystemExit(f"Unicode 17 IDNA test row count changed: {input_rows}")
    return cases, skipped_ill_formed


def encode_mapping_chunk(
    values: list[tuple[int, int, int, tuple[int, ...]]]
) -> tuple[str, str]:
    mapping_offset = 0
    records: list[str] = []
    mappings: list[str] = []
    for lo, hi, kind, mapping in values:
        records.append(f"{lo:06X}{hi:06X}{kind:X}{mapping_offset:06X}{len(mapping):02X}")
        mappings.extend(f"{scalar:06X}" for scalar in mapping)
        mapping_offset += len(mapping) * 6
    if mapping_offset >= 0x1000000:
        raise SystemExit("IDNA mapping chunk exceeds packed offset")
    return "".join(records), "".join(mappings)


def generate_mapping_lookup(
    values: list[tuple[int, int, int, tuple[int, ...]]]
) -> str:
    parts = ["pub(package) fn unicode_idna_map_push(scalar: i64, out: borrow mut Vector<i64>) -> bool {"]
    table_chunks = chunks(values, 450)
    for index, chunk in enumerate(table_chunks):
        ranges, mappings = encode_mapping_chunk(chunk)
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} scalar <= {chunk[-1][1]} {{")
        parts.append(
            "    unicode_idna_map_from_tables(scalar, "
            f'"{ranges}", {len(chunk)}, "{mappings}", out)'
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append("  else {\n    out.push(scalar)\n    true\n  }" + " }" * (len(table_chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def encode_property_ranges(values: list[tuple[int, int, int]]) -> str:
    return "".join(f"{lo:06X}{hi:06X}{code:02X}" for lo, hi, code in values)


def generate_property_lookup(name: str, values: list[tuple[int, int, int]]) -> str:
    parts = [f"pub(package) fn unicode_idna_{name}_code(scalar: i64) -> i64 {{"]
    table_chunks = chunks(values, 650)
    for index, chunk in enumerate(table_chunks):
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} scalar <= {chunk[-1][1]} {{")
        parts.append(
            "    unicode_idna_range_value(scalar, "
            f'"{encode_property_ranges(chunk)}", {len(chunk)})'
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append("  else { 0 }" + " }" * (len(table_chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def generate_data_source(
    mappings: list[tuple[int, int, int, tuple[int, ...]]],
    bidi: list[tuple[int, int, int]],
    joining: list[tuple[int, int, int]],
) -> str:
    bidi_constants = "\n".join(
        f"pub(package) fn unicode_idna_bidi_{name.lower()}() -> i64 {{ {index} }}"
        for index, name in enumerate(BIDI_NAMES)
    )
    joining_constants = "\n".join(
        f"pub(package) fn unicode_idna_joining_{name.lower()}() -> i64 {{ {index} }}"
        for index, name in enumerate(JOINING_NAMES)
    )
    return f'''-- stdlib/unicode/data/idna.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION} UTS #46 revision {UTS46_REVISION} nontransitional data.
-- IdnaMappingTable SHA-256: {INPUTS["mapping"][1]}
-- DerivedBidiClass SHA-256: {INPUTS["bidi"][1]}
-- DerivedJoiningType SHA-256: {INPUTS["joining"][1]}
-- Generator: tools/generate_unicode_idna_data.py

use runtime/string.{{runtime_str_byte_at}}
use stdlib/vector as vector
use stdlib/vector/handles.{{Vector}}

pub(package) fn unicode_idna_data_version() -> str {{ "{UNICODE_VERSION}" }}

pub(package) fn unicode_idna_hex_value(ch: i64) -> i64 {{
  if ch >= 48 and ch <= 57 {{ ch - 48 }}
  else {{ if ch >= 65 and ch <= 70 {{ ch - 55 }} else {{ 0 }} }}
}}

pub(package) fn unicode_idna_hex(src: str, offset: i64, digits: i64) -> i64 {{
  let mut value = 0
  let mut i = 0
  while i < digits {{
    value = value * 16 + unicode_idna_hex_value(runtime_str_byte_at(src, offset + i))
    i = i + 1
  }}
  value
}}

-- Push the UTS #46 mapping of `scalar` onto `out`: nothing when ignored, the
-- mapped scalars, or the scalar itself when valid. Disallowed pushes nothing
-- and reports false.
pub(package) fn unicode_idna_map_from_tables(scalar: i64, ranges: str, count: i64, mappings: str, out: borrow mut Vector<i64>) -> bool {{
  let mut lo = 0
  let mut hi = count
  let mut found = 0
  let mut result = true
  while lo < hi and found == 0 {{
    let mid = lo + (hi - lo) / 2
    let offset = mid * 21
    let first = unicode_idna_hex(ranges, offset, 6)
    let last = unicode_idna_hex(ranges, offset + 6, 6)
    if scalar < first {{ hi = mid }}
    else {{ if scalar > last {{ lo = mid + 1 }}
    else {{
      let kind = unicode_idna_hex(ranges, offset + 12, 1)
      let mapping_offset = unicode_idna_hex(ranges, offset + 13, 6)
      let mapping_count = unicode_idna_hex(ranges, offset + 19, 2)
      if kind == 2 {{ result = false }}
      else {{ if kind == 1 {{
        let mut i = 0
        while i < mapping_count {{
          out.push(unicode_idna_hex(mappings, mapping_offset + i * 6, 6))
          i = i + 1
        }}
      }} else {{ nil }} }}
      found = 1
    }} }}
  }}
  if found == 0 {{ out.push(scalar) }} else {{ nil }}
  result
}}

pub(package) fn unicode_idna_range_value(scalar: i64, ranges: str, count: i64) -> i64 {{
  let mut lo = 0
  let mut hi = count
  let mut result = 0
  let mut found = 0
  while lo < hi and found == 0 {{
    let mid = lo + (hi - lo) / 2
    let offset = mid * 14
    let first = unicode_idna_hex(ranges, offset, 6)
    let last = unicode_idna_hex(ranges, offset + 6, 6)
    if scalar < first {{ hi = mid }}
    else {{ if scalar > last {{ lo = mid + 1 }}
    else {{ result = unicode_idna_hex(ranges, offset + 12, 2) found = 1 }} }}
  }}
  result
}}

{bidi_constants}

{joining_constants}

{generate_mapping_lookup(mappings)}

{generate_property_lookup("bidi", bidi)}

{generate_property_lookup("joining", joining)}
'''


def encode_test_chunk(
    values: list[tuple[bytes, bytes, int, int]]
) -> tuple[str, str]:
    offset = 0
    indexes: list[str] = []
    encoded: list[str] = []
    for source, expected, succeeds, absolute in values:
        value = (
            f"{len(source):04X}{len(expected):04X}{succeeds}{absolute}"
            + source.hex().upper()
            + expected.hex().upper()
        )
        indexes.append(f"{offset:06X}")
        encoded.append(value)
        offset += len(value)
    if offset >= 0x1000000:
        raise SystemExit("IDNA test chunk exceeds packed offset")
    return "".join(indexes), "".join(encoded)


def generate_test_lookup(values: list[tuple[bytes, bytes, int, int]]) -> str:
    parts = ["pub(package) fn unicode_idna_test_case(index: i64) -> UnicodeIdnaTestCase {"]
    first_index = 0
    table_chunks = chunks(values, 160)
    for chunk_index, chunk in enumerate(table_chunks):
        indexes, data = encode_test_chunk(chunk)
        last_index = first_index + len(chunk)
        prefix = "  if" if chunk_index == 0 else "  else { if"
        parts.append(f"{prefix} index < {last_index} {{")
        parts.append(
            "    UnicodeIdnaTestCase(\""
            + indexes
            + "\", \""
            + data
            + f'\", index - {first_index})'
        )
        parts.append("  }" if chunk_index == 0 else "  }")
        first_index = last_index
    parts.append(
        '  else { UnicodeIdnaTestCase("", "", 0) }'
        + " }" * (len(table_chunks) - 1)
    )
    parts.append("}")
    return "\n".join(parts)


def generate_test_source(
    tests: list[tuple[bytes, bytes, int, int]], skipped_ill_formed: int
) -> str:
    return f'''-- test/unicode_idna_conformance_data.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION} complete well-formed UTS #46 ToASCII conformance data.
-- IdnaTestV2 SHA-256: {INPUTS["tests"][1]}
-- {skipped_ill_formed} ill-formed UTF-16/source rows are excluded because Weft str is valid UTF-8.
-- Generator: tools/generate_unicode_idna_data.py

use runtime/string.{{runtime_str_byte_at, runtime_str_from_utf8_vector}}
use stdlib/panic.{{panic}}
use stdlib/unicode/data/idna.{{unicode_idna_hex}}
use stdlib/vector as vector

pub(package) type UnicodeIdnaTestCase {{
  UnicodeIdnaTestCase(str, str, i64)
}}

pub(package) fn unicode_idna_test_case_offset(value: UnicodeIdnaTestCase) -> i64 {{
  match value {{
    UnicodeIdnaTestCase(indexes, data, index) -> unicode_idna_hex(indexes, index * 6, 6)
  }}
}}

pub(package) fn unicode_idna_test_case_source_len(value: UnicodeIdnaTestCase) -> i64 {{
  match value {{
    UnicodeIdnaTestCase(indexes, data, index) -> unicode_idna_hex(data, unicode_idna_test_case_offset(value), 4)
  }}
}}

pub(package) fn unicode_idna_test_case_expected_len(value: UnicodeIdnaTestCase) -> i64 {{
  match value {{
    UnicodeIdnaTestCase(indexes, data, index) -> unicode_idna_hex(data, unicode_idna_test_case_offset(value) + 4, 4)
  }}
}}

pub(package) fn unicode_idna_test_case_success(value: UnicodeIdnaTestCase) -> i64 {{
  match value {{
    UnicodeIdnaTestCase(indexes, data, index) -> runtime_str_byte_at(data, unicode_idna_test_case_offset(value) + 8) - 48
  }}
}}

pub(package) fn unicode_idna_test_case_absolute(value: UnicodeIdnaTestCase) -> i64 {{
  match value {{
    UnicodeIdnaTestCase(indexes, data, index) -> runtime_str_byte_at(data, unicode_idna_test_case_offset(value) + 9) - 48
  }}
}}

pub(package) fn unicode_idna_test_case_text(value: UnicodeIdnaTestCase, expected: i64) -> str {{
  match value {{
    UnicodeIdnaTestCase(indexes, data, index) -> {{
      let offset = unicode_idna_test_case_offset(value)
      let source_len = unicode_idna_hex(data, offset, 4)
      let expected_len = unicode_idna_hex(data, offset + 4, 4)
      let len = if expected == 1 {{ expected_len }} else {{ source_len }}
      let encoded_offset = if expected == 1 {{ offset + 10 + source_len * 2 }} else {{ offset + 10 }}
      let mut bytes = vector.with_capacity<u8>(__i64_to_usize(len))
      let mut i = 0
      while i < len {{
        bytes.push(__i64_to_u8(unicode_idna_hex(data, encoded_offset + i * 2, 2)))
        i = i + 1
      }}
      -- Only well-formed rows are generated, so every case decodes as text.
      match runtime_str_from_utf8_vector(bytes) {{
        nil -> panic("IDNA conformance row is not UTF-8")
        text: str -> text
      }}
    }}
  }}
}}

pub(package) fn unicode_idna_test_case_source(value: UnicodeIdnaTestCase) -> str {{
  unicode_idna_test_case_text(value, 0)
}}

pub(package) fn unicode_idna_test_case_expected(value: UnicodeIdnaTestCase) -> str {{
  unicode_idna_test_case_text(value, 1)
}}

pub(package) fn unicode_idna_test_case_count() -> i64 {{ {len(tests)} }}
pub(package) fn unicode_idna_ill_formed_test_count() -> i64 {{ {skipped_ill_formed} }}

{generate_test_lookup(tests)}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in INPUTS:
        parser.add_argument(f"--{name.replace('_', '-')}", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("stdlib/unicode/data/idna.weft"),
    )
    parser.add_argument(
        "--test-output",
        type=pathlib.Path,
        default=pathlib.Path("test/unicode_idna_conformance_data.weft"),
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    loaded = {name: load(getattr(args, name), name) for name in INPUTS}
    mappings = parse_mapping(loaded["mapping"])
    bidi = parse_property(loaded["bidi"], BIDI_NAMES, BIDI_ALIASES)
    joining = parse_property(loaded["joining"], JOINING_NAMES, JOINING_ALIASES)
    tests, skipped_ill_formed = parse_tests(loaded["tests"])
    generated = weft_generated_source.canonical(
        generate_data_source(mappings, bidi, joining).encode("utf-8")
    )
    generated_tests = weft_generated_source.canonical(
        generate_test_source(tests, skipped_ill_formed).encode("utf-8")
    )

    if args.check:
        stale = False
        for path, expected in ((args.output, generated), (args.test_output, generated_tests)):
            if not path.exists() or path.read_bytes() != expected:
                print(f"out of date: {path}", file=sys.stderr)
                stale = True
        if stale:
            return 1
        print(
            f"ok: Unicode {UNICODE_VERSION} IDNA data "
            f"({len(tests)} well-formed cases; {skipped_ill_formed} ill-formed excluded)"
        )
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.test_output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(generated)
    args.test_output.write_bytes(generated_tests)
    print(
        f"wrote Unicode {UNICODE_VERSION} IDNA data "
        f"({len(tests)} well-formed cases; {skipped_ill_formed} ill-formed excluded)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
