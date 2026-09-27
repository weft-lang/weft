#!/usr/bin/env python3
"""The raw boundary's transitional list only shrinks.

Every listed logical path must name an existing strict file that still reaches
raw memory, so a file leaves the list together with its last raw use. The list
must stay sorted and free of duplicates, because the compiler searches it by
bisection. Its length is pinned to CEILING: an entry that leaves the list
lowers the ceiling with it, and the ceiling never rises. Prints one summary
line; exits nonzero on the first violation.
"""
import re
import sys

# Lower this with every entry that leaves the list. Never raise it: strict code
# that needs raw memory it does not reach today needs an honest trusted leaf.
CEILING = 299

POLICY = sys.argv[1] if len(sys.argv) > 1 else "compiler/source/raw_boundary.weft"

source = open(POLICY, encoding="utf-8").read()
listing = source.split("pub(package) fn raw_boundary_transitional")[1]
listing = listing.split("]", 1)[0]
paths = re.findall(r'"([^"]+)"', listing)
members = re.findall(
    r'"([^"]+)"',
    source.split("pub(package) fn raw_boundary_string_member")[1].split("]", 1)[0],
)


def fail(message):
    print("raw boundary list: " + message)
    sys.exit(1)


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


def reaches_raw_memory(text):
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    text = re.sub(r"--[^\n]*", "", text)
    if re.search(r"^\s*(pub(\(package\))? )?use runtime/(memory|buffer|alloc)\b", text, re.M):
        return True
    for match in re.finditer(r"use runtime/string(\s+as\s+\w+|\.\{([^}]*)\})", text):
        selection = match.group(2)
        if selection is None or selection.strip() == "*":
            return True
        if any(re.search(r"\b" + member + r"\b", selection) for member in members):
            return True
    return re.search(r"\b__str_(ptr|len)\(", text) is not None


for path in paths:
    try:
        text = open(path + ".weft", encoding="utf-8").read()
    except OSError:
        fail("listed path " + path + " has no source file")
    if not reaches_raw_memory(text):
        fail("listed path " + path + " no longer reaches raw memory; remove it")

print("raw boundary list: sorted, and every entry still reaches raw memory")
