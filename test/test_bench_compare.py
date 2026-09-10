#!/usr/bin/env python3
"""Benchmark observations must retain workload identity and startup limits."""
from collections import Counter
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bench_compare as bench
import bench_verdict as verdict


class BenchmarkMeasurements(unittest.TestCase):
    def test_language_order_balances_every_position(self):
        orders = [bench.rotated_order(bench.LANGUAGES, i) for i in range(6)]
        self.assertEqual(len({tuple(order) for order in orders}), 6)
        for position in range(3):
            self.assertEqual(Counter(order[position] for order in orders),
                             Counter({language: 2 for language in bench.LANGUAGES}))

    def test_empty_and_single_language_groups(self):
        self.assertEqual(bench.rotated_order([], 0), [])
        self.assertEqual(bench.rotated_order(["rust"], 5), ["rust"])
        bench.measure_group({}, {}, 3, 1)

    def test_summary_keeps_raw_samples_and_distinguishes_median(self):
        result = bench.summaries([1, 2, 90])
        self.assertEqual(result["run_min_ms"], 1)
        self.assertEqual(result["run_median_ms"], 2)
        self.assertEqual(result["run_mean_ms"], 31)
        self.assertEqual(result["runs_ms"], [1, 2, 90])
        with self.assertRaises(ValueError):
            bench.summaries([])

    def test_startup_floor_is_not_subtracted_or_capped(self):
        for duration, expected, sensitive in [(100, 1.5, False), (30, 5, False),
                                              (3, 50, True), (1, 150, True)]:
            with self.subTest(duration=duration):
                result = bench.startup_comparison(duration, 1.5)
                self.assertEqual(result, {"startup_floor_pct": expected,
                                          "startup_sensitive": sensitive})
        for elapsed, empty in [(0, 1), (-1, 1), (1, 0)]:
            with self.assertRaises(ValueError):
                bench.startup_comparison(elapsed, empty)

    def test_warmups_are_excluded_and_exact_sample_counts_preserved(self):
        variants = {language: {"ok": True} for language in bench.LANGUAGES}
        with patch.object(bench, "timed", side_effect=list(range(1, 13))) as timed:
            bench.measure_group(dict(zip(bench.LANGUAGES, bench.LANGUAGES)), variants, 3, 1)
        self.assertEqual(timed.call_count, 12)
        samples = [sample for variant in variants.values() for sample in variant["runs_ms"]]
        self.assertEqual(sorted(samples), list(range(4, 13)))
        self.assertTrue(all(len(variant["runs_ms"]) == 3 for variant in variants.values()))

    def test_warmup_or_measured_failure_invalidates_partial_results(self):
        for values in [[RuntimeError("bad checksum")], [1, 2, RuntimeError("bad checksum")]]:
            with self.subTest(values=values):
                variants = {"weft": {"ok": True}}
                with patch.object(bench, "timed", side_effect=values):
                    bench.measure_group({"weft": "program"}, variants, 5, 1)
                self.assertFalse(variants["weft"]["ok"])
                self.assertNotIn("run_median_ms", variants["weft"])
                self.assertIn("bad checksum", variants["weft"]["error"])

    def test_direct_wait_never_uses_timeout_polling(self):
        with patch.object(bench.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stderr=b"")) as run:
            with patch.object(bench.time, "perf_counter_ns", side_effect=[1000000, 3000000]):
                self.assertEqual(bench.timed(["program"]), 2)
        self.assertNotIn("timeout", run.call_args.kwargs)

    def test_nonzero_process_exit_is_not_a_timing(self):
        with patch.object(bench.subprocess, "run", return_value=subprocess.CompletedProcess([], 9, stderr=b"checksum")):
            with self.assertRaisesRegex(RuntimeError, "exit 9.*program"):
                bench.timed(["program"])

    def test_case_selection_always_includes_one_startup_control(self):
        self.assertEqual(bench.selected_cases("sieve,empty sieve graph_reach"),
                         ["empty", "sieve", "graph_reach"])
        self.assertEqual(bench.selected_cases(""), ["empty"])
        with self.assertRaises(ValueError):
            bench.selected_cases("../source")

    def test_counts_reject_zero_runs_but_allow_no_warmups(self):
        for value in ["0", "-1", "not a count"]:
            with patch.dict(os.environ, BENCH_COMPARE_RUNS=value):
                with self.assertRaises(ValueError):
                    bench.env_count("BENCH_COMPARE_RUNS", "7", 1)
        with patch.dict(os.environ, BENCH_COMPARE_WARMUPS="0"):
            self.assertEqual(bench.env_count("BENCH_COMPARE_WARMUPS", "1", 0), 0)

    def test_current_workload_sources_are_digested_for_every_language(self):
        for case in bench.WORKLOADS:
            identity = bench.workload_identity(case)
            self.assertEqual(set(identity["source_sha256"]), set(bench.LANGUAGES))
            for language in bench.LANGUAGES:
                self.assertEqual(identity["source_sha256"][language], bench.digest(bench.source_path(case, language)))

    def test_larger_checksums_follow_independent_reference_formulas(self):
        # Odd input values are selected after mapping: 4, 10, 16, ... .
        iterator = sum(3 * ((1000000 + r * 3) // 3) ** 2 + (1000000 + r * 3) // 3
                       for r in range(300))
        sort = sum(n * (n - 1) // 2 + n // 2 + n - 1 for n in range(30000, 30060))
        for case, expected in [("iterator_pipeline", iterator), ("iterator_pipeline_direct", iterator),
                               ("vector_sort", sort), ("graph_reach", 768 * 769 // 2),
                               ("sieve", 17984 * 240),
                               ("sorted_lookup", sum(200010000 + r for r in range(100))),
                               ("mandelbrot", 272325 * 3)]:
            self.assertEqual(bench.WORKLOADS[case]["checksum"], expected)
            self.assertEqual(bench.WORKLOADS[case]["revision"], 2)
            for language in bench.LANGUAGES:
                self.assertIn(str(expected), bench.source_path(case, language).read_text())

    def test_build_failure_preserves_compiler_diagnostic(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(bench.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, stderr=b"invalid source")):
                with self.assertRaisesRegex(RuntimeError, "invalid source"):
                    bench.build("empty", "weft", "compiler", Path(directory))

    def test_matrix_record_and_failure_status(self):
        for failed in [False, True]:
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as directory:
                log = Path(directory) / "results.jsonl"

                def capture(command):
                    return '{"sdk":{"kind":"checkout"}}' if "--json" in command else "test-version"

                def build(case, language, compiler, temporary):
                    if failed and case == "sieve" and language == "go":
                        raise RuntimeError("broken build")
                    return temporary / f"{case}-{language}", {"ok": True}

                env = {"BENCH_COMPARE_CASES": "sieve", "BENCH_COMPARE_RUNS": "3",
                       "BENCH_COMPARE_STARTUP_RUNS": "5", "BENCH_COMPARE_WARMUPS": "1",
                       "BENCH_COMPARE_RECORD": "1", "BENCH_COMPARE_OUT": str(log)}
                with patch.dict(os.environ, env), patch.object(bench, "capture", side_effect=capture), \
                     patch.object(bench, "build", side_effect=build), patch.object(bench, "timed", return_value=2), \
                     redirect_stdout(io.StringIO()):
                    self.assertEqual(bench.main(), int(failed))
                record = json.loads(log.read_text())
                self.assertEqual(record["schema_version"], 2)
                self.assertEqual(record["measurement"], "whole_process_wall")
                self.assertEqual(len(record["cases"]["empty"]["rust"]["runs_ms"]), 5)
                self.assertEqual(len(record["cases"]["sieve"]["weft"]["runs_ms"]), 3)
                self.assertEqual(record["cases"]["sieve"]["go"]["ok"], not failed)
                self.assertTrue(record["cases"]["sieve"]["rust"]["startup_sensitive"])

    def test_paired_harness_uses_same_workloads_and_automatic_startup_control(self):
        self.assertEqual(verdict.ZOO_CASES, list(bench.WORKLOADS))
        self.assertEqual(verdict.include_startup_control(["sieve", "empty", "sieve"]), ["empty", "sieve"])
        self.assertEqual(verdict.include_startup_control(["self_compile"]), ["self_compile"])
        self.assertEqual(verdict.include_startup_control(["self_compile", "sieve"]), ["empty", "self_compile", "sieve"])

    def test_paired_harness_warns_without_changing_process_verdict(self):
        result = {"workload": "sieve", "verdict": "improved", "median_a_ms": 2, "median_b_ms": 1.5}
        verdict.annotate_startup(result, {"median_a_ms": 1.4, "median_b_ms": 1.3})
        self.assertEqual(result["verdict"], "improved")
        self.assertTrue(result["startup"]["a"]["startup_sensitive"])
        self.assertTrue(result["startup"]["b"]["startup_sensitive"])


if __name__ == "__main__":
    unittest.main()
