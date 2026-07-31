#!/usr/bin/env python3
"""bench_verdict.py — paired A/B benchmark verdicts for Weft builds.

Enforces the roadmap §3.2 measurement discipline by tooling: only
same-session, interleaved, paired measurements are decision-grade. Given two
compiler binaries (A = baseline, B = candidate), runs each workload as
alternating AB/BA pairs and emits a verdict per workload:

    improved / regressed / flat, with pair count and confidence.

The verdict is a two-sided exact sign test over per-pair deltas (deterministic,
no RNG — §3.11 discipline applies to tooling too), plus the median paired
delta. A workload is only called improved/regressed when the sign test is
significant AND the median delta magnitude clears a noise floor.

Workloads:
  zoo cases   compile bench/compare/weft/<case>.weft with each compiler once,
              then run the two binaries in interleaved pairs (run time).
  self_compile  time `<compiler> compile compiler/main.weft` itself, paired.
  check_tree  time `<compiler> check compiler/main.weft` (imports pull in the
              full tree — 6.4k functions), paired.
  fmt_tree    time `<compiler> fmt <file>` summed over every compiler source
              (parse-only per file), paired (front-end throughput; §3.12(a)).
  test_runner  compile tools/test_runner.weft with each compiler (linked-object
              flow: weft emits a .o, ld links against libSystem), then time the
              runner binary driving a small fixed test set. The spawned
              compiler is pinned to the baseline ./weft on BOTH sides so the
              paired delta isolates the runner binary's own code.
  mcp_roundtrip  time `<compiler> mcp` answering a check_summary request over
              compiler/parse.weft, paired.

Results append to bench/verdicts.jsonl (BENCH_VERDICT_RECORD=0 to disable).

Usage:
  python3 bench_verdict.py --a ./weft --b /tmp/weft_candidate
  python3 bench_verdict.py --a ./weft --b /tmp/w2 --workloads sieve,self_compile --pairs 10
"""

import argparse
import json
import math
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

ZOO_CASES = ["sieve", "vector_sort", "graph_reach", "mandelbrot", "nbody", "sorted_lookup"]
TOOL_WORKLOADS = ["self_compile", "check_tree", "fmt_tree", "test_runner", "mcp_roundtrip"]
DEFAULT_WORKLOADS = ZOO_CASES + ["self_compile"]

# Verdict thresholds. The sign test answers "is B consistently on one side of
# A"; the floor keeps a consistent-but-small drift from being called a result.
# The floor default is calibrated by a measured null run: byte-identical
# binaries at different paths showed a *consistent* ~2.4% check_tree delta
# (sign test would confirm it at high pair counts), so anything under 3% is
# environment, not effect. Use --null to measure your own session's floor.
ALPHA = 0.05
FLAT_FLOOR_PCT = 3.0
MIN_PAIRS_FOR_VERDICT = 10

REPO = os.path.dirname(os.path.abspath(__file__))

MCP_REQUEST_TEMPLATE = (
    '{"jsonrpc":"2.0","id":1,"method":"tools/call",'
    '"params":{"name":"check_summary","arguments":{"source":%s}}}'
)


def fail(msg):
    print(f"bench_verdict: {msg}", file=sys.stderr)
    raise SystemExit(1)


def sign_test_p(n_pos, n_neg):
    """Two-sided exact binomial sign test p-value, ties dropped."""
    n = n_pos + n_neg
    if n == 0:
        return 1.0
    k = min(n_pos, n_neg)
    tail = sum(math.comb(n, i) for i in range(0, k + 1)) / (2 ** n)
    return min(1.0, 2.0 * tail)


def run_timed(cmd, stdin_path=None, timeout=600):
    """Run cmd from the repo root, return elapsed ms. Nonzero exit is a hard failure."""
    stdin_f = open(stdin_path, "rb") if stdin_path else subprocess.DEVNULL
    try:
        start = time.perf_counter_ns()
        result = subprocess.run(
            cmd,
            stdin=stdin_f,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
            cwd=REPO,
        )
        elapsed_ms = (time.perf_counter_ns() - start) / 1e6
    finally:
        if stdin_path:
            stdin_f.close()
    if result.returncode != 0:
        fail(f"command failed ({result.returncode}): {' '.join(cmd)}")
    return elapsed_ms


def compile_with(compiler, source, out_path):
    with open(out_path, "wb") as out:
        result = subprocess.run(
            [compiler, "compile", source],
            stdout=out,
            stderr=subprocess.DEVNULL,
        )
    if result.returncode != 0 or os.path.getsize(out_path) == 0:
        fail(f"{compiler} failed to compile {source}")
    os.chmod(out_path, 0o755)


def tree_sources():
    comp = sorted(
        os.path.join("compiler", f)
        for f in os.listdir(os.path.join(REPO, "compiler"))
        if f.endswith(".weft")
    )
    return comp


class Workload:
    """A workload yields one timed sample per invocation, per side."""

    def __init__(self, name):
        self.name = name

    def prepare(self, a, b, tmp):
        pass

    def sample(self, side):
        raise NotImplementedError


class ZooRun(Workload):
    def __init__(self, case):
        super().__init__(case)
        self.case = case
        self.bins = {}

    def prepare(self, a, b, tmp):
        src = os.path.join(REPO, "bench", "compare", "weft", f"{self.case}.weft")
        if not os.path.exists(src):
            fail(f"unknown zoo case: {self.case}")
        for side, compiler in (("a", a), ("b", b)):
            out = os.path.join(tmp, f"{self.case}_{side}")
            compile_with(compiler, src, out)
            self.bins[side] = out
        # one unmeasured warmup per binary (macOS first-launch validation)
        for side in ("a", "b"):
            run_timed([self.bins[side]])

    def sample(self, side):
        return run_timed([self.bins[side]])


class CompilerCmd(Workload):
    """Time the compiler binary itself on a fixed command."""

    def __init__(self, name, args, stdin_path=None):
        super().__init__(name)
        self.args = args
        self.stdin_path = stdin_path
        self.compilers = {}

    def prepare(self, a, b, tmp):
        self.compilers = {"a": a, "b": b}
        for side in ("a", "b"):
            self.sample(side)  # warmup

    def sample(self, side):
        return run_timed([self.compilers[side]] + self.args, stdin_path=self.stdin_path)


class TreeCmd(Workload):
    """Sum of per-file compiler invocations over the compiler sources."""

    def __init__(self, name, subcmd):
        super().__init__(name)
        self.subcmd = subcmd
        self.compilers = {}
        self.files = []

    def prepare(self, a, b, tmp):
        self.compilers = {"a": a, "b": b}
        self.files = tree_sources()
        for side in ("a", "b"):
            self.sample(side)  # warmup

    def sample(self, side):
        total = 0.0
        for f in self.files:
            total += run_timed([self.compilers[side], self.subcmd, f])
        return total


TEST_RUNNER_SET = ["test/basics.weft"]


class TestRunnerRun(Workload):
    """tools/test_runner.weft uses `use` imports, so weft emits a Mach-O
    object that must be linked against libSystem (the 3h linked-object flow)."""

    def __init__(self):
        super().__init__("test_runner")
        self.bins = {}

    def prepare(self, a, b, tmp):
        src = os.path.join(REPO, "tools", "test_runner.weft")
        sdk = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True,
                             text=True).stdout.strip()
        for side, compiler in (("a", a), ("b", b)):
            obj = os.path.join(tmp, f"test_runner_{side}.o")
            out = os.path.join(tmp, f"test_runner_{side}")
            compile_with(compiler, src, obj)
            link = subprocess.run(
                ["/usr/bin/ld", "-o", out, obj, "-lSystem", "-syslibroot", sdk,
                 "-e", "_main", "-arch", "arm64",
                 "-platform_version", "macos", "11.0", "15.0"],
                capture_output=True)
            if link.returncode != 0:
                fail(f"linking test_runner ({side}) failed: {link.stderr.decode()[:200]}")
            self.bins[side] = out
        for side in ("a", "b"):
            self.sample(side)  # warmup

    def sample(self, side):
        baseline_weft = os.path.join(REPO, "weft")
        return run_timed([self.bins[side], baseline_weft] + TEST_RUNNER_SET)


class McpRoundtrip(Workload):
    def __init__(self):
        super().__init__("mcp_roundtrip")
        self.compilers = {}
        self.request_path = None

    def prepare(self, a, b, tmp):
        self.compilers = {"a": a, "b": b}
        with open(os.path.join(REPO, "compiler", "parse.weft")) as f:
            source = f.read()
        self.request_path = os.path.join(tmp, "mcp_request.json")
        with open(self.request_path, "w") as f:
            # ensure_ascii=False: the MCP JSON reader takes raw UTF-8 strings
            f.write(MCP_REQUEST_TEMPLATE % json.dumps(source, ensure_ascii=False))
        for side in ("a", "b"):
            # validate once: an error response would silently time the wrong path
            with open(self.request_path, "rb") as req:
                out = subprocess.run([self.compilers[side], "mcp"], stdin=req,
                                     capture_output=True, cwd=REPO).stdout
            if b'"ok":true' not in out:
                fail(f"mcp_roundtrip ({side}) returned an error: {out[:120]}")
            self.sample(side)  # warmup

    def sample(self, side):
        return run_timed([self.compilers[side], "mcp"], stdin_path=self.request_path)


def make_workload(name):
    if name in ZOO_CASES:
        return ZooRun(name)
    if name == "self_compile":
        return SelfCompile()
    if name == "check_tree":
        return CompilerCmd("check_tree", ["check", os.path.join("compiler", "main.weft")])
    if name == "fmt_tree":
        return TreeCmd("fmt_tree", "fmt")
    if name == "test_runner":
        return TestRunnerRun()
    if name == "mcp_roundtrip":
        return McpRoundtrip()
    fail(f"unknown workload: {name}")


class SelfCompile(CompilerCmd):
    def __init__(self):
        super().__init__("self_compile", ["compile", os.path.join(REPO, "compiler", "main.weft")])

    def sample(self, side):
        # discard the emitted binary; time the compile itself
        compiler = self.compilers[side]
        start = time.perf_counter_ns()
        result = subprocess.run(
            [compiler, "compile", os.path.join(REPO, "compiler", "main.weft")],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        elapsed_ms = (time.perf_counter_ns() - start) / 1e6
        if result.returncode != 0:
            fail(f"{compiler} self-compile failed")
        return elapsed_ms


def measure_workload(wl, a, b, tmp, pairs, floor=FLAT_FLOOR_PCT):
    wl.prepare(a, b, tmp)
    samples = {"a": [], "b": []}
    for i in range(pairs):
        # interleaved AB/BA: even pairs run A first, odd pairs run B first
        order = ("a", "b") if i % 2 == 0 else ("b", "a")
        for side in order:
            samples[side].append(wl.sample(side))
    deltas = [bi - ai for ai, bi in zip(samples["a"], samples["b"])]
    n_pos = sum(1 for d in deltas if d > 0)   # B slower
    n_neg = sum(1 for d in deltas if d < 0)   # B faster
    p = sign_test_p(n_pos, n_neg)
    med_a = statistics.median(samples["a"])
    med_b = statistics.median(samples["b"])
    med_delta_pct = 100.0 * statistics.median(
        [d / ai for d, ai in zip(deltas, samples["a"]) if ai > 0]
    ) if samples["a"] else 0.0

    if pairs < MIN_PAIRS_FOR_VERDICT:
        verdict = "insufficient-pairs"
    elif p < ALPHA and abs(med_delta_pct) >= floor:
        verdict = "improved" if med_delta_pct < 0 else "regressed"
    else:
        verdict = "flat"

    return {
        "workload": wl.name,
        "pairs": pairs,
        "verdict": verdict,
        "median_a_ms": round(med_a, 3),
        "median_b_ms": round(med_b, 3),
        "median_delta_pct": round(med_delta_pct, 3),
        "sign_test_p": round(p, 6),
        "b_faster_pairs": n_neg,
        "b_slower_pairs": n_pos,
        "tied_pairs": pairs - n_pos - n_neg,
        "samples_a_ms": [round(v, 3) for v in samples["a"]],
        "samples_b_ms": [round(v, 3) for v in samples["b"]],
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", default=os.path.join(REPO, "weft"), help="baseline compiler binary (default ./weft)")
    ap.add_argument("--b", help="candidate compiler binary")
    ap.add_argument("--null", action="store_true",
                    help="null calibration: run A against a copy of A; any non-flat "
                         "verdict here is your environment's bias floor, not an effect")
    ap.add_argument("--floor", type=float, default=FLAT_FLOOR_PCT,
                    help=f"flat floor in %% (default {FLAT_FLOOR_PCT})")
    ap.add_argument("--pairs", type=int, default=25, help="AB/BA pairs per workload (default 25)")
    ap.add_argument("--workloads", default=",".join(DEFAULT_WORKLOADS),
                    help=f"comma list from: {','.join(ZOO_CASES + TOOL_WORKLOADS)}")
    ap.add_argument("--out", default=os.path.join(REPO, "bench", "verdicts.jsonl"))
    ap.add_argument("--label", default="", help="free-form label recorded with the result")
    args = ap.parse_args()

    a = os.path.abspath(args.a)
    if args.null:
        b = None  # copied into the tmp dir below
    elif args.b:
        b = os.path.abspath(args.b)
    else:
        fail("--b is required (or pass --null for a calibration run)")
    for path in (a,) if b is None else (a, b):
        if not (os.path.isfile(path) and os.access(path, os.X_OK)):
            fail(f"not an executable: {path}")

    names = [w.strip() for w in args.workloads.split(",") if w.strip()]
    if args.pairs < MIN_PAIRS_FOR_VERDICT:
        print(f"warning: {args.pairs} pairs is below the decision-grade minimum "
              f"({MIN_PAIRS_FOR_VERDICT}); verdicts will read insufficient-pairs",
              file=sys.stderr)

    sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO,
                         capture_output=True, text=True).stdout.strip()
    tmp = tempfile.mkdtemp(prefix="weft_verdict_")
    results = []
    try:
        if args.null:
            b = os.path.join(tmp, "weft_null_copy")
            shutil.copy2(a, b)
            os.chmod(b, 0o755)
        b_label = "copy-of-A (null)" if args.null else args.b
        print(f"=== bench_verdict ({sha}) A={args.a} B={b_label} pairs={args.pairs} floor={args.floor}% ===")
        for name in names:
            wl = make_workload(name)
            r = measure_workload(wl, a, b, tmp, args.pairs, args.floor)
            results.append(r)
            print(f"  {r['workload']:<14} {r['verdict']:<10} "
                  f"A {r['median_a_ms']:>9.3f}ms  B {r['median_b_ms']:>9.3f}ms  "
                  f"delta {r['median_delta_pct']:+7.3f}%  "
                  f"p={r['sign_test_p']:.4f}  ({r['b_faster_pairs']}v{r['b_slower_pairs']}, {r['pairs']} pairs)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    record = {
        "sha": sha,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "a": args.a,
        "b": "null" if args.null else args.b,
        "pairs": args.pairs,
        "floor_pct": args.floor,
        "label": args.label,
        "results": results,
    }
    if os.environ.get("BENCH_VERDICT_RECORD", "1") != "0":
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "a") as f:
            f.write(json.dumps(record) + "\n")
        print(f"recorded: {os.path.relpath(args.out, REPO)}")
    else:
        print(json.dumps(record))

    worst = next((r for r in results if r["verdict"] == "regressed"), None)
    return 0 if worst is None else 2


if __name__ == "__main__":
    raise SystemExit(main())
