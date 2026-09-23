#!/usr/bin/env python3
"""Differential census of the typed checker against the legacy checker.

Builds tools/typed_differential.weft once, runs it for each root in parallel,
and classifies each root:

  agree_accept         both checkers accept
  agree_reject         both reject; `site` compares the first legacy error line
                       with the typed rejection line (same_line, other_site,
                       typed_unlocated)
  typed_false_accept   legacy rejects but the typed checker accepts; these are
                       soundness gaps and must reach zero before the switch
  typed_false_reject   legacy accepts but the typed checker rejects; these are
                       coverage gaps in the typed checker
  excluded_parse       legacy rejects during parsing; not a checker comparison
  harness_failure      the worker produced no record (timeout, crash, RSS)

Roots are checked as untrusted strict user code, as `weft check` treats any
root outside the trusted compiler/runtime tree; trusted roots are out of scope.
This is test scaffolding for the no-bridge cutover. It never makes the typed
path authoritative and must be deleted with the legacy checker.
"""

import argparse
import collections
import concurrent.futures
import glob
import os
import re
import subprocess
import sys

RECORD = re.compile(
    r"^typed-differential legacy=(?P<legacy>\S+) legacy_errors=(?P<legacy_errors>\S+) "
    r"legacy_at=(?P<legacy_at>\S+) typed=(?P<typed>\S+) stage=(?P<stage>\S+) "
    r"module=(?P<module>\S+) function=(?P<function>\S+) category=(?P<category>\S+)"
    r"(?: typed_errors=\S+)? typed_at=(?P<typed_at>\S+) \| (?P<message>.*)$"
)


def negative_roots():
    roots = []
    with open("test/negative/run_negative_tests.sh", encoding="utf-8") as handle:
        for line in handle:
            if not line.startswith("check_rejects "):
                continue
            # Names and paths never contain spaces; patterns may hold any text.
            roots.append(line.split()[2].strip("\"'"))
    return roots


def runtime_roots():
    roots = []
    for path in sorted(glob.glob("test/*.weft")):
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        if 'test "' in text or re.search(r"(^|\s)fn\s+main\s*\(", text):
            roots.append(path)
    return roots


def example_roots():
    return sorted(glob.glob("examples/*.weft"))


ROOT_SETS = {
    "negatives": negative_roots,
    "runtime": runtime_roots,
    "examples": example_roots,
}


FAILURE = re.compile(r"weft: (panic|trap): .*")


def build_tool(builder, output):
    completed = subprocess.run(
        [builder, "build", "tools/typed_differential.weft", "-o", output],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        sys.stderr.write(completed.stderr.decode("utf-8", "replace"))
        raise SystemExit(f"could not build the differential tool with {builder}")


def run_root(tool, root, timeout):
    try:
        completed = subprocess.run(
            [tool, root], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            timeout=timeout, check=False,
        )
    except subprocess.TimeoutExpired:
        return None, "worker timed out"
    text = completed.stderr.decode("utf-8", "replace")
    for raw in text.splitlines():
        match = RECORD.match(raw)
        if match:
            return match.groupdict(), None
    found = FAILURE.search(text)
    if found:
        return None, found.group(0)
    return None, f"no record (exit {completed.returncode})"


def run(tool, jobs, roots, timeout):
    records, failures = {}, {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = {pool.submit(run_root, tool, root, timeout): root for root in roots}
        for future in concurrent.futures.as_completed(futures):
            root = futures[future]
            record, failure = future.result()
            if record is not None:
                records[root] = record
            else:
                failures[root] = failure
    return records, failures


def line_of(location):
    if location in ("-", "?"):
        return None
    path, _, rest = location.rpartition(":")
    path, _, line = path.rpartition(":")
    return (path, line)


def classify(record):
    if record is None:
        return "harness_failure", "-"
    legacy = record["legacy"]
    typed = record["typed"]
    if legacy == "parse_rejected":
        return "excluded_parse", "-"
    typed_rejected = typed in ("rejected", "load_rejected", "root_unregistered")
    if legacy == "accepted":
        return ("typed_false_reject", "-") if typed_rejected else ("agree_accept", "-")
    if legacy == "rejected":
        if not typed_rejected:
            return "typed_false_accept", "-"
        legacy_line = line_of(record["legacy_at"])
        typed_line = line_of(record["typed_at"])
        if typed_line is None:
            return "agree_reject", "typed_unlocated"
        if legacy_line == typed_line:
            return "agree_reject", "same_line"
        return "agree_reject", "other_site"
    return "harness_failure", "-"


def message_class(message):
    message = re.sub(r"`[^`]*`", "`_`", message)
    message = re.sub(r"'[^']*'", "'_'", message)
    return message[:90]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--builder", default="./.weft-dev-candidate",
                        help="compiler used to build tools/typed_differential.weft")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--timeout", type=int, default=300, help="seconds per root")
    parser.add_argument("--set", action="append", choices=sorted(ROOT_SETS), dest="sets")
    parser.add_argument("--out", help="write per-root TSV records to this file")
    parser.add_argument("--detail", type=int, default=25, help="rows per breakdown table")
    options = parser.parse_args()
    sets = options.sets or ["negatives", "runtime", "examples"]

    tool = f"/tmp/weft-typed-differential-{os.getpid()}"
    build_tool(options.builder, tool)
    rows = []
    for name in sets:
        roots = ROOT_SETS[name]()
        records, failures = run(tool, options.jobs, roots, options.timeout)
        for root in roots:
            record = records.get(root)
            verdict, site = classify(record)
            if verdict == "harness_failure":
                site = failures.get(root, "no record")
            rows.append((name, root, verdict, site, record))

    if options.out:
        with open(options.out, "w", encoding="utf-8") as handle:
            handle.write("set\troot\tverdict\tsite\tstage\tmodule\tfunction\tcategory"
                         "\tlegacy_at\ttyped_at\tmessage\n")
            for name, root, verdict, site, record in rows:
                record = record or collections.defaultdict(lambda: "-")
                handle.write("\t".join([
                    name, root, verdict, site, record["stage"], record["module"],
                    record["function"], record["category"], record["legacy_at"],
                    record["typed_at"], record["message"],
                ]) + "\n")

    for name in sets:
        selected = [row for row in rows if row[0] == name]
        verdicts = collections.Counter(row[2] for row in selected)
        print(f"== {name}: {len(selected)} roots")
        for verdict, count in sorted(verdicts.items()):
            print(f"  {verdict:20} {count}")
        sites = collections.Counter(row[3] for row in selected if row[2] == "agree_reject")
        if sites:
            print("  agree_reject sites: " + ", ".join(
                f"{site}={count}" for site, count in sorted(sites.items())))
        false_rejects = collections.Counter(
            (row[4]["stage"], row[4]["category"], row[4]["module"])
            for row in selected if row[2] == "typed_false_reject")
        if false_rejects:
            print("  typed_false_reject by stage/category/module:")
            for (stage, category, module), count in false_rejects.most_common(options.detail):
                print(f"    {count:5}  {stage}/{category}  {module}")
        false_accepts = collections.Counter(
            message_class(row[4]["message"])
            for row in selected if row[2] == "typed_false_accept")
        if false_accepts:
            print("  typed_false_accept by legacy message:")
            for message, count in false_accepts.most_common(options.detail):
                print(f"    {count:5}  {message}")
        failures = collections.Counter(
            row[3][:100] for row in selected if row[2] == "harness_failure")
        if failures:
            print("  harness_failure by message:")
            for message, count in failures.most_common(options.detail):
                print(f"    {count:5}  {message}")
    os.remove(tool)
    return 0


if __name__ == "__main__":
    sys.exit(main())
