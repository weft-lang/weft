#!/usr/bin/env python3
"""The raw boundary's transitional list only shrinks.

Every listed logical path must name an existing strict file that still reaches
raw memory: it binds a trusted runtime module by wildcard, names a trusted
export outside that module's audited safe surface by selection or through a
module alias, installs an unaudited handler of a trusted runtime module, or
uses the __str_ptr/__str_len intrinsics. A file therefore leaves the list
together with its last raw binding. The list must stay sorted and free of duplicates,
because the compiler searches it by bisection. Its length is pinned to
CEILING: an entry that leaves the list lowers the ceiling with it, and the
ceiling never rises. Prints one summary line; exits nonzero on the first
violation.

`--compute` prints the strict files that reach raw memory today instead, one
logical path per line, for deliberately re-deriving the list.
"""
import glob
import json
import re
import sys

# Lower this with every entry that leaves the list. Never raise it: strict code
# that needs raw memory it does not reach today needs an honest trusted leaf.
CEILING = 462

POLICY = "compiler/source/raw_boundary.weft"
TRUST = "compiler/source/trust.weft"
MANIFEST = "weft.pkg"
SOURCE_ROOTS = ("compiler", "runtime", "stdlib", "tools", "test", "examples", "module_fixtures")


def listed_paths(source):
    listing = source.split("pub(package) fn raw_boundary_transitional")[1]
    return re.findall(r'"([^"]+)"', listing.split("]", 1)[0])


def safe_exports(source):
    table = source.split("pub(package) fn raw_boundary_safe_export")[1]
    return set(re.findall(r'"([^"]+)"', table.split("]", 1)[0]))


def safe_handlers(source):
    table = source.split("pub(package) fn raw_boundary_safe_handler")[1]
    return set(re.findall(r'"([^"]+)"', table.split("]", 1)[0]))


def trusted_modules():
    """The trusted runtime ring: trusted runtime files and runtime bindings."""
    text = open(TRUST, encoding="utf-8").read()
    body = text.split("pub(package) fn source_trust_is_runtime_file")[1].split("\n}\n", 1)[0]
    modules = set(path[:-5] for path in re.findall(r'"(runtime/[^"]+\.weft)"', body))
    manifest = json.load(open(MANIFEST, encoding="utf-8"))
    bindings = manifest.get("trusted_bindings", [])
    # The raw ring is the trusted modules under runtime/; the checker applies
    # the same rule through raw_boundary_trusted_runtime.
    return set(m for m in modules | set(bindings) if m.startswith("runtime/"))


def trusted_root(path):
    if path.startswith("test/linked/"):
        return True
    if path.startswith("test/") and path.endswith("_metrics.weft"):
        return True
    text = open(TRUST, encoding="utf-8").read()
    body = text.split("pub(package) fn source_trust_is_runtime_test_root")[1].split("\n}\n", 1)[0]
    return path in re.findall(r'"([^"]+\.weft)"', body)


def alias_reaches_raw_memory(text, module, alias, safe, handlers):
    """Each qualified use and handler installation through an alias is decided
    on its own, as the checker decides it."""
    for member in re.findall(r"\b" + re.escape(alias) + r"\.([A-Za-z_][A-Za-z0-9_]*)", text):
        if module + "." + member not in safe:
            return True
    installs = r"(?:\bwith\s+|\bdefault\s+handler\s+)" + re.escape(alias) + r"\s*[<(]"
    return re.search(installs, text) is not None and module not in handlers


def reaches_raw_memory(text, trusted, safe, handlers):
    text = re.sub(r'r#"[\s\S]*?"#', '""', text)
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    text = re.sub(r"--[^\n]*", "", text)
    for match in re.finditer(
        r"(?m)^\s*(?:pub(?:\(package\))? )?use ([a-z_]+/[a-z0-9_/]+)(\.\{([^}]*)\}|\s+as\s+(\w+))?",
        text,
    ):
        module = match.group(1)
        if module not in trusted:
            continue
        selection = match.group(3)
        alias = match.group(4)
        if alias is not None:
            if alias_reaches_raw_memory(text, module, alias, safe, handlers):
                return True
            continue
        if selection is None or selection.strip() == "*":
            return True
        names = re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\b", re.sub(r"\bas\s+\w+", "", selection))
        if any(module + "." + name not in safe for name in names):
            return True
    return re.search(r"\b__str_(ptr|len)\(", text) is not None


def logical_path(path):
    return path[:-5]


def source_text(logical):
    try:
        return open(logical + ".weft", encoding="utf-8").read()
    except OSError:
        return None


def refused_by_design(logical):
    """The boundary's own negatives and wrapper fixture exist to be refused."""
    return logical.rsplit("/", 1)[-1].startswith("raw_boundary_")


def fail(message):
    print("raw boundary list: " + message)
    sys.exit(1)


def main():
    source = open(POLICY, encoding="utf-8").read()
    paths = listed_paths(source)
    safe = safe_exports(source)
    handlers = safe_handlers(source)
    trusted = trusted_modules()
    if "--compute" in sys.argv[1:]:
        for directory in SOURCE_ROOTS:
            for path in sorted(glob.glob(directory + "/**/*.weft", recursive=True)):
                logical = logical_path(path)
                if logical in trusted or trusted_root(path) or refused_by_design(logical):
                    continue
                if reaches_raw_memory(open(path, encoding="utf-8").read(), trusted, safe, handlers):
                    print(logical)
        return
    if not paths:
        fail("no transitional paths found")
    if paths != sorted(paths):
        fail("paths are not sorted")
    if len(set(paths)) != len(paths):
        fail("paths repeat")
    if len(paths) > CEILING:
        fail("%d paths exceed the ceiling of %d; the list only shrinks" % (len(paths), CEILING))
    if len(paths) < CEILING:
        fail("%d paths remain; lower the ceiling from %d to match" % (len(paths), CEILING))
    for path in paths:
        text = source_text(path)
        if text is None:
            fail("listed path " + path + " has no source file")
        if not reaches_raw_memory(text, trusted, safe, handlers):
            fail("listed path " + path + " no longer reaches raw memory; remove it")
    print("raw boundary list: sorted, and every entry still reaches raw memory")


main()
