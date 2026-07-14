#!/usr/bin/env python3
"""Attribute macOS `sample` output for a weft-compiled binary.

Usage:
  ./weft symbols program.weft > symbols.txt
  ./weft compile program.weft > prog && chmod +x prog
  ./prog ... &  sample $! 5 -file profile.txt
  python3 symbolize_profile.py symbols.txt prog profile.txt

`weft symbols` prints one "offset name" line per emitted function (named
declarations plus h<hash> entries for specialisations and lambdas). This
script maps sample's load-address offsets back through the binary's
__text file offset and prints a ranked, named top-of-stack profile.
"""
import re, sys, bisect, subprocess
from collections import Counter

symbols_path, binary_path, profile_path = sys.argv[1], sys.argv[2], sys.argv[3]

out = subprocess.run(["otool", "-l", binary_path], capture_output=True, text=True).stdout
lines = out.splitlines()
toff = None
for i, l in enumerate(lines):
    if "sectname __text" in l:
        for j in range(i, i + 10):
            if "offset" in lines[j] and "fileoff" not in lines[j] and toff is None:
                toff = int(lines[j].split()[-1])
        break
assert toff is not None, "no __text section found"

syms = []
for line in open(symbols_path):
    p = line.split(" ", 1)
    if len(p) == 2:
        syms.append((int(p[0]), p[1].strip()))
syms.sort()
offs = [s[0] for s in syms]

def name(buf_pos):
    i = bisect.bisect_right(offs, buf_pos) - 1
    return syms[i][1] if i >= 0 else "???"

c = Counter()
total = 0
started = False
for line in open(profile_path):
    if "Sort by top of stack" in line:
        started = True
        continue
    if not started:
        continue
    m = re.search(r"load address 0x[0-9a-f]+ \+ 0x([0-9a-f]+).*?\s(\d+)\s*$", line)
    if m:
        off = int(m.group(1), 16) - toff
        n = int(m.group(2))
        total += n
        c[name(off)] += n

print(f"total samples attributed: {total}")
for fn, n in c.most_common(20):
    print(f"{100*n/total:5.1f}%  {n:6}  {fn}")
