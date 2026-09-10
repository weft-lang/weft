#!/usr/bin/env python3
"""Whole-process Weft/Go/Rust comparisons, with explicit startup controls."""

import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parent
LANGUAGES = ("weft", "go", "rust")
EXTENSIONS = {"weft": "weft", "go": "go", "rust": "rs"}
# Revision 1 results remain historical; changed work is never compared as if
# only the compiler changed. Source hashes additionally identify local edits.
WORKLOADS = {
    "empty": {"revision": 1, "kind": "startup_control"},
    "sieve": {"revision": 2, "limit": 200000, "repetitions": 240, "checksum": 4316160},
    "vector_sort": {"revision": 2, "sizes": [30000, 30059], "repetitions": 60,
                    "checksum": 27054936800},
    "graph_reach": {"revision": 2, "nodes": 768, "checksum": 295296},
    "mandelbrot": {"revision": 2, "size": 1024, "max_iter": 80,
                   "repetitions": 3, "checksum": 816975},
    "nbody": {"revision": 2, "steps": 2000000, "dt": 0.01,
              "energy": -0.16902628585285398, "tolerance": 1e-9},
    "sorted_lookup": {"revision": 2, "entries": 20000, "spans": [40000, 40099],
                      "repetitions": 100, "checksum": 20001004950},
    "iterator_pipeline_direct": {"revision": 2, "sizes": [1000000, 1000897],
                                 "size_step": 3, "repetitions": 300,
                                 "checksum": 100089626820300},
    "iterator_pipeline": {"revision": 2, "sizes": [1000000, 1000897],
                          "size_step": 3, "repetitions": 300,
                          "checksum": 100089626820300},
}
STARTUP_WARNING_PCT = 5.0


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_path(case, language):
    return REPO / "bench" / "compare" / language / f"{case}.{EXTENSIONS[language]}"


def workload_identity(case):
    return {**WORKLOADS[case], "source_sha256": {
        language: digest(source_path(case, language)) for language in LANGUAGES
    }}


def rotated_order(items, iteration):
    """Cycle all positions and alternate direction, without random ordering."""
    items = list(items)
    if not items:
        return []
    shift = iteration % len(items)
    order = items[shift:] + items[:shift]
    return order if iteration % 2 == 0 else list(reversed(order))


def summaries(samples):
    if not samples:
        raise ValueError("a timing summary requires successful measurements")
    return {"run_min_ms": min(samples), "run_median_ms": statistics.median(samples),
            "run_mean_ms": statistics.mean(samples), "runs_ms": samples}


def startup_comparison(elapsed, empty):
    if elapsed <= 0 or empty <= 0:
        raise ValueError("timings must be positive")
    ratio = 100 * empty / elapsed
    return {"startup_floor_pct": ratio,
            "startup_sensitive": ratio > STARTUP_WARNING_PCT}


def timed(command):
    # No timeout polling: it quantizes short samples. Blocking wait includes
    # process launch, runtime/image startup, the workload, and exit.
    start = time.perf_counter_ns()
    result = subprocess.run(command, cwd=REPO, stdin=subprocess.DEVNULL,
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    elapsed = (time.perf_counter_ns() - start) / 1_000_000
    if result.returncode:
        raise RuntimeError(f"exit {result.returncode}: {' '.join(map(str, command))}\n"
                           + result.stderr.decode(errors="replace"))
    return elapsed


def capture(command):
    return subprocess.check_output(command, cwd=REPO, text=True).strip()


def build_command(case, language, compiler, output):
    source = str(source_path(case, language).relative_to(REPO))
    if language == "weft":
        return [compiler, "compile", source]
    if language == "go":
        return ["go", "build", "-o", str(output), source]
    return ["rustc", "-C", "opt-level=3", "-C", "codegen-units=1",
            "-C", "target-cpu=native", source, "-o", str(output)]


def build(case, language, compiler, directory):
    output = directory / f"{case}_{language}"
    command = build_command(case, language, compiler, output)
    start = time.perf_counter_ns()
    if language == "weft":
        with output.open("wb") as binary:
            result = subprocess.run(command, cwd=REPO, stdout=binary, stderr=subprocess.PIPE)
    else:
        result = subprocess.run(command, cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    elapsed = (time.perf_counter_ns() - start) / 1_000_000
    if result.returncode or not output.exists() or not output.stat().st_size:
        raise RuntimeError(f"build failed: {' '.join(command)}\n"
                           + result.stderr.decode(errors="replace"))
    output.chmod(0o755)
    return output, {"ok": True, "build_ms": elapsed, "size": output.stat().st_size,
                    "binary_sha256": digest(output), "build_command": command}


def measure_group(binaries, variants, runs, warmups):
    samples = {language: [] for language in binaries}
    for iteration in range(warmups + runs):
        for language in rotated_order(binaries, iteration):
            if not variants[language]["ok"]:
                continue
            try:
                elapsed = timed([str(binaries[language])])
            except RuntimeError as error:
                # A failed checksum, including during warmup, invalidates the
                # whole variant. Never publish a median from its partial runs.
                variants[language].update(ok=False, error=str(error))
                continue
            if iteration >= warmups:
                samples[language].append(elapsed)
    for language, values in samples.items():
        if variants[language]["ok"]:
            variants[language].update(summaries(values))


def env_count(name, default, minimum):
    value = int(os.environ.get(name, default))
    if value < minimum:
        raise ValueError(f"{name} must be at least {minimum}")
    return value


def selected_cases(value):
    names = list(dict.fromkeys(value.replace(",", " ").split()))
    unknown = set(names) - WORKLOADS.keys()
    if unknown:
        raise ValueError(f"unknown cases: {', '.join(sorted(unknown))}")
    return ["empty"] + [name for name in names if name != "empty"]


def main():
    compiler = os.path.abspath(os.environ.get("WEFT", "./weft"))
    runs = env_count("BENCH_COMPARE_RUNS", "7", 1)
    warmups = env_count("BENCH_COMPARE_WARMUPS", "1", 0)
    startup_runs = env_count("BENCH_COMPARE_STARTUP_RUNS", "51", 1)
    cases = selected_cases(os.environ.get("BENCH_COMPARE_CASES", " ".join(WORKLOADS)))
    record = {
        "schema_version": 2, "measurement": "whole_process_wall",
        "startup_warning_pct": STARTUP_WARNING_PCT,
        "sha": capture(["git", "rev-parse", "--short", "HEAD"]),
        "dirty": bool(capture(["git", "status", "--porcelain"])),
        "compiler_sha256": digest(compiler),
        "compiler_identity": json.loads(capture([compiler, "version", "--json"])),
        "host": f"{platform.system()} {platform.machine()}",
        "go_version": capture(["go", "version"]),
        "rust_version": capture(["rustc", "--version"]),
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "runs": runs, "warmups": warmups, "startup_runs": startup_runs,
        "workloads": {case: workload_identity(case) for case in cases},
        "cases": {case: {} for case in cases},
    }
    print(f"=== Weft comparative benchmarks ({record['sha']}, schema 2) ===", flush=True)
    print(f"whole-process wall time; {runs} runs, {warmups} warmups; "
          f"{startup_runs} startup runs", flush=True)
    with tempfile.TemporaryDirectory(prefix="weft_compare_") as directory:
        binaries = {case: {} for case in cases}
        # Finish all compilation before runtime sampling. Compiler work must
        # not be interleaved with just one language's short measurements.
        for case in cases:
            for language in LANGUAGES:
                try:
                    binary, result = build(case, language, compiler, Path(directory))
                    binaries[case][language] = binary
                    record["cases"][case][language] = result
                except RuntimeError as error:
                    record["cases"][case][language] = {"ok": False, "error": str(error)}
                    print(str(error), flush=True)
        for case in cases:
            variants = record["cases"][case]
            measure_group(binaries[case], variants,
                          startup_runs if case == "empty" else runs, warmups)
            print(f"  {case} (revision {WORKLOADS[case]['revision']}):", flush=True)
            for language in LANGUAGES:
                result = variants[language]
                if not result["ok"]:
                    print(f"    {language}: FAILED {result['error']}", flush=True)
                    continue
                suffix = ""
                empty = record["cases"]["empty"][language]
                if case != "empty" and empty["ok"]:
                    result.update(startup_comparison(result["run_median_ms"], empty["run_median_ms"]))
                    suffix = f"; empty/workload {result['startup_floor_pct']:.1f}%"
                    if result["startup_sensitive"]:
                        suffix += " [startup-sensitive]"
                print(f"    {language}: median {result['run_median_ms']:.3f}ms, "
                      f"min {result['run_min_ms']:.3f}ms, "
                      f"mean {result['run_mean_ms']:.3f}ms{suffix}", flush=True)
    output = json.dumps(record)
    if os.environ.get("BENCH_COMPARE_RECORD", "1") != "0":
        path = Path(os.environ.get("BENCH_COMPARE_OUT", REPO / "bench/compare/results.jsonl"))
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as log:
            log.write(output + "\n")
        print(f"recorded: {path}")
    else:
        print(output)
    return int(any(not result["ok"] for variants in record["cases"].values()
                   for result in variants.values()))


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"bench_compare: {error}")
