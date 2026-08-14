#!/usr/bin/env python3
"""Generate Weft's pinned UTS #39 identifier-security data."""

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
    "script_extensions": (
        "https://www.unicode.org/Public/17.0.0/ucd/ScriptExtensions.txt",
        "ec2107e58825a1586acee8e0911ce18260394ac8b87e535ca325f1ccbeb06bc6",
    ),
    "property_value_aliases": (
        "https://www.unicode.org/Public/17.0.0/ucd/PropertyValueAliases.txt",
        "64e9a5f76f7a1e8b5a47d6a1f9a26522a251208f5276bdfa1559dac7cf2e827a",
    ),
    "confusables": (
        "https://www.unicode.org/Public/17.0.0/security/confusables.txt",
        "091c7f82fc39ef208faf8f94d29c244de99254675e09de163160c810d13ef22a",
    ),
}

SCRIPT_WORD_BITS = 60
SCRIPT_WORDS = 3


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


def parse_aliases(data: bytes) -> dict[str, str]:
    aliases: dict[str, str] = {}
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        if fields[0] != "sc":
            continue
        short = fields[1]
        for alias in fields[1:]:
            aliases[alias] = short
    return aliases


def parse_scripts(data: bytes, aliases: dict[str, str]) -> list[tuple[int, int, str]]:
    ranges: list[tuple[int, int, str]] = []
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        code_range, name = (field.strip() for field in body.split(";", 1))
        if name not in aliases:
            raise SystemExit(f"Scripts.txt uses unknown script alias {name}")
        lo, hi = parse_range(code_range)
        ranges.append((lo, hi, aliases[name]))
    return sorted(ranges)


def parse_script_extensions(
    data: bytes,
) -> list[tuple[int, int, tuple[str, ...]]]:
    ranges: list[tuple[int, int, tuple[str, ...]]] = []
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        code_range, names = (field.strip() for field in body.split(";", 1))
        lo, hi = parse_range(code_range)
        ranges.append((lo, hi, tuple(names.split())))
    return sorted(ranges)


def script_mask(
    scripts: tuple[str, ...], script_ids: dict[str, int]
) -> tuple[int, int, int]:
    augmented = set(scripts)
    if "Hani" in augmented:
        augmented.update(("Hanb", "Jpan", "Kore"))
    if "Hira" in augmented or "Kana" in augmented:
        augmented.add("Jpan")
    if "Hang" in augmented:
        augmented.add("Kore")
    if "Bopo" in augmented:
        augmented.add("Hanb")
    if "Zyyy" in augmented or "Zinh" in augmented:
        augmented = set(script_ids)
    words = [0, 0, 0]
    for name in augmented:
        script_id = script_ids[name]
        word = script_id // SCRIPT_WORD_BITS
        bit = script_id % SCRIPT_WORD_BITS
        words[word] |= 1 << bit
    return words[0], words[1], words[2]


def build_script_masks(
    scripts: list[tuple[int, int, str]],
    extensions: list[tuple[int, int, tuple[str, ...]]],
) -> tuple[list[tuple[int, int, tuple[int, int, int]]], tuple[int, int, int], int]:
    names = {name for _, _, name in scripts}
    for _, _, values in extensions:
        names.update(values)
    names.update(("Zzzz", "Hanb", "Jpan", "Kore"))
    ordered_names = sorted(names)
    if len(ordered_names) > SCRIPT_WORD_BITS * SCRIPT_WORDS:
        raise SystemExit("script mask needs more than three words")
    script_ids = {name: index for index, name in enumerate(ordered_names)}
    all_mask = script_mask(("Zyyy",), script_ids)

    result: list[tuple[int, int, tuple[int, int, int]]] = []
    script_index = 0
    extension_index = 0
    for scalar in range(0x110000):
        while script_index < len(scripts) and scalar > scripts[script_index][1]:
            script_index += 1
        while extension_index < len(extensions) and scalar > extensions[extension_index][1]:
            extension_index += 1
        base = "Zzzz"
        if script_index < len(scripts):
            lo, hi, value = scripts[script_index]
            if lo <= scalar <= hi:
                base = value
        values = (base,)
        if extension_index < len(extensions):
            lo, hi, extension_values = extensions[extension_index]
            if lo <= scalar <= hi:
                values = extension_values
        mask = script_mask(values, script_ids)
        if result and result[-1][2] == mask and result[-1][1] + 1 == scalar:
            result[-1] = (result[-1][0], scalar, mask)
        else:
            result.append((scalar, scalar, mask))
    return result, all_mask, len(ordered_names)


def parse_confusables(data: bytes) -> list[tuple[int, tuple[int, ...]]]:
    mappings: list[tuple[int, tuple[int, ...]]] = []
    for raw_line in data.decode("utf-8").splitlines():
        body = raw_line.split("#", 1)[0].strip()
        if not body:
            continue
        fields = [field.strip() for field in body.split(";")]
        source = tuple(int(value, 16) for value in fields[0].split())
        target = tuple(int(value, 16) for value in fields[1].split())
        if len(source) != 1:
            raise SystemExit("UTS #39 source mapping is not a scalar")
        mappings.append((source[0], target))
    return sorted(mappings)


def parse_canonical_decompositions(data: bytes) -> dict[int, tuple[int, ...]]:
    mappings: dict[int, tuple[int, ...]] = {}
    for raw_line in data.decode("utf-8").splitlines():
        fields = raw_line.split(";")
        decomposition = fields[5]
        if decomposition and not decomposition.startswith("<"):
            mappings[int(fields[0], 16)] = tuple(
                int(value, 16) for value in decomposition.split()
            )
    return mappings


def canonical_decompose(
    scalar: int, mappings: dict[int, tuple[int, ...]]
) -> tuple[int, ...]:
    if 0xAC00 <= scalar < 0xAC00 + 11172:
        s_index = scalar - 0xAC00
        parts = [0x1100 + s_index // 588, 0x1161 + (s_index % 588) // 28]
        if s_index % 28:
            parts.append(0x11A7 + s_index % 28)
        return tuple(parts)
    direct = mappings.get(scalar)
    if direct is None:
        return (scalar,)
    return tuple(
        nested
        for part in direct
        for nested in canonical_decompose(part, mappings)
    )


def maximum_skeleton_expansion(
    mappings: list[tuple[int, tuple[int, ...]]],
    canonical: dict[int, tuple[int, ...]],
) -> int:
    maximum = 4
    for _, target in mappings:
        maximum = max(
            maximum,
            sum(len(canonical_decompose(part, canonical)) for part in target),
        )
    return maximum


def chunks(values: list[tuple], size: int) -> list[list[tuple]]:
    return [values[index : index + size] for index in range(0, len(values), size)]


def decomposition_chunks(
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


def encode_script_masks(
    values: list[tuple[int, int, tuple[int, int, int]]]
) -> str:
    return "".join(
        f"{lo:06X}{hi:06X}{mask[0]:015X}{mask[1]:015X}{mask[2]:015X}"
        for lo, hi, mask in values
    )


def encode_mapping_index(values: list[tuple[int, tuple[int, ...]]]) -> str:
    offset = 0
    encoded: list[str] = []
    for scalar, target in values:
        encoded.append(f"{scalar:06X}{offset:04X}{len(target):02X}")
        offset += len(target)
    return "".join(encoded)


def encode_mapping_values(values: list[tuple[int, tuple[int, ...]]]) -> str:
    return "".join(f"{scalar:06X}" for _, target in values for scalar in target)


def generate_script_lookup(
    ranges: list[tuple[int, int, tuple[int, int, int]]]
) -> str:
    parts = [
        "pub(package) fn unicode_security_script_mask_lookup(scalar: i64, word: i64, ranges: i64, count: i64) -> i64 {",
        "  let mut lo = 0",
        "  let mut hi = count",
        "  let mut result = 0",
        "  let mut found = 0",
        "  while lo < hi and found == 0 {",
        "    let mid = lo + (hi - lo) / 2",
        "    let offset = mid * 57",
        "    let first = unicode_security_hex(ranges, offset, 6)",
        "    let last = unicode_security_hex(ranges, offset + 6, 6)",
        "    if scalar < first { hi = mid }",
        "    else { if scalar > last { lo = mid + 1 }",
        "    else { result = unicode_security_hex(ranges, offset + 12 + word * 15, 15) found = 1 } }",
        "  }",
        "  result",
        "}",
        "",
        "pub(package) fn unicode_security_script_mask(scalar: i64, word: i64) -> i64 {",
    ]
    table_chunks = chunks(ranges, 200)
    for index, chunk in enumerate(table_chunks):
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} scalar <= {chunk[-1][1]} {{")
        parts.append(
            "    unicode_security_script_mask_lookup(scalar, word, "
            f'__str_ptr("{encode_script_masks(chunk)}"), {len(chunk)})'
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append("  else { 0 }" + " }" * (len(table_chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def generate_confusable_lookup(
    mappings: list[tuple[int, tuple[int, ...]]]
) -> str:
    parts = [
        "pub(package) fn unicode_confusable_lookup(scalar: i64, entries: i64, entry_count: i64, values: i64, out: i64, count: i64) -> i64 {",
        "  let mut lo = 0",
        "  let mut hi = entry_count",
        "  let mut found = 0 - 1",
        "  while lo < hi and found < 0 {",
        "    let mid = lo + (hi - lo) / 2",
        "    let key = unicode_security_hex(entries, mid * 12, 6)",
        "    if scalar < key { hi = mid }",
        "    else { if scalar > key { lo = mid + 1 } else { found = mid } }",
        "  }",
        "  if found < 0 { 0 - 1 }",
        "  else {",
        "    let entry_offset = found * 12",
        "    let value_offset = unicode_security_hex(entries, entry_offset + 6, 4)",
        "    let value_count = unicode_security_hex(entries, entry_offset + 10, 2)",
        "    let mut next = count",
        "    let mut i = 0",
        "    while i < value_count {",
        "      let target = unicode_security_hex(values, (value_offset + i) * 6, 6)",
        "      next = unicode_canonical_decompose_into(target, out, next)",
        "      i = i + 1",
        "    }",
        "    next",
        "  }",
        "}",
        "",
        "pub(package) fn unicode_confusable_map_into(scalar: i64, out: i64, count: i64) -> i64 {",
    ]
    table_chunks = decomposition_chunks(mappings)
    for index, chunk in enumerate(table_chunks):
        prefix = "  if" if index == 0 else "  else { if"
        parts.append(f"{prefix} scalar <= {chunk[-1][0]} {{")
        parts.append(
            "    unicode_confusable_lookup(scalar, "
            f'__str_ptr("{encode_mapping_index(chunk)}"), {len(chunk)}, '
            f'__str_ptr("{encode_mapping_values(chunk)}"), out, count)'
        )
        parts.append("  }" if index == 0 else "  }")
    parts.append("  else { 0 - 1 }" + " }" * (len(table_chunks) - 1))
    parts.append("}")
    return "\n".join(parts)


def generate_source(
    script_ranges: list[tuple[int, int, tuple[int, int, int]]],
    all_mask: tuple[int, int, int],
    script_count: int,
    mappings: list[tuple[int, tuple[int, ...]]],
    maximum_expansion: int,
) -> str:
    return f'''-- compiler/unicode_security_data.weft -- GENERATED; DO NOT EDIT
-- Unicode {UNICODE_VERSION} UTS #39 mixed-script and confusable substrate.
-- UnicodeData SHA-256: {INPUTS['unicode_data'][1]}
-- Scripts SHA-256: {INPUTS['scripts'][1]}
-- ScriptExtensions SHA-256: {INPUTS['script_extensions'][1]}
-- PropertyValueAliases SHA-256: {INPUTS['property_value_aliases'][1]}
-- confusables SHA-256: {INPUTS['confusables'][1]}
-- Generator: tools/generate_unicode_security_data.py

use compiler/unicode_normalization_data.{{unicode_canonical_decompose_into}}
use runtime/memory.{{mem_load8_at}}

pub(package) fn unicode_security_data_version() -> str {{ "{UNICODE_VERSION}" }}
pub(package) fn unicode_security_script_count() -> i64 {{ {script_count} }}
pub(package) fn unicode_security_script_all_0() -> i64 {{ {all_mask[0]} }}
pub(package) fn unicode_security_script_all_1() -> i64 {{ {all_mask[1]} }}
pub(package) fn unicode_security_script_all_2() -> i64 {{ {all_mask[2]} }}
pub(package) fn unicode_confusable_max_expansion() -> i64 {{ {maximum_expansion} }}

pub(package) fn unicode_security_hex_value(ch: i64) -> i64 {{
  if ch >= 48 and ch <= 57 {{ ch - 48 }}
  else {{ if ch >= 65 and ch <= 70 {{ ch - 55 }} else {{ 0 }} }}
}}

pub(package) fn unicode_security_hex(src: i64, offset: i64, digits: i64) -> i64 {{
  let mut value = 0
  let mut i = 0
  while i < digits {{
    value = value * 16 + unicode_security_hex_value(mem_load8_at(src, offset + i))
    i = i + 1
  }}
  value
}}

{generate_script_lookup(script_ranges)}

pub(package) fn unicode_security_script_mask_0(scalar: i64) -> i64 {{ unicode_security_script_mask(scalar, 0) }}
pub(package) fn unicode_security_script_mask_1(scalar: i64) -> i64 {{ unicode_security_script_mask(scalar, 1) }}
pub(package) fn unicode_security_script_mask_2(scalar: i64) -> i64 {{ unicode_security_script_mask(scalar, 2) }}

{generate_confusable_lookup(mappings)}
'''


def main() -> int:
    parser = argparse.ArgumentParser()
    for name in INPUTS:
        parser.add_argument(f"--{name.replace('_', '-')}", type=pathlib.Path)
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        default=pathlib.Path("compiler/unicode_security_data.weft"),
    )
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    loaded = {name: load(getattr(args, name), name) for name in INPUTS}
    aliases = parse_aliases(loaded["property_value_aliases"])
    scripts = parse_scripts(loaded["scripts"], aliases)
    extensions = parse_script_extensions(loaded["script_extensions"])
    script_ranges, all_mask, script_count = build_script_masks(scripts, extensions)
    mappings = parse_confusables(loaded["confusables"])
    canonical = parse_canonical_decompositions(loaded["unicode_data"])
    generated = generate_source(
        script_ranges,
        all_mask,
        script_count,
        mappings,
        maximum_skeleton_expansion(mappings, canonical),
    ).encode("utf-8")

    if args.check:
        if not args.output.exists() or args.output.read_bytes() != generated:
            print(f"out of date: {args.output}", file=sys.stderr)
            return 1
        print(
            f"ok: {args.output} (Unicode {UNICODE_VERSION}; "
            f"{script_count} scripts; {len(mappings)} confusable mappings)"
        )
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(generated)
    print(
        f"wrote {args.output} (Unicode {UNICODE_VERSION}; "
        f"{script_count} scripts; {len(mappings)} confusable mappings)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
