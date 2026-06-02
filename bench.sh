#!/bin/bash
# bench.sh — benchmark the Weft compiler and example programs
# Records results as JSON lines appended to bench/results.jsonl
# Each line: {"sha": "...", "ts": "...", "metrics": {...}}
set -e

SHA=$(git rev-parse --short HEAD)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p bench
BENCH_TIMEOUT="${WEFT_BENCH_TIMEOUT:-}"
EXAMPLE_RUNS="${WEFT_BENCH_EXAMPLE_RUNS:-7}"
EXAMPLE_WARMUPS="${WEFT_BENCH_EXAMPLE_WARMUPS:-1}"

now_ms() {
  python3 -c "import time; print(int(time.perf_counter()*1000))"
}

min_ms() {
  local csv="$1"
  python3 -c 'import sys
vals=[float(x) for x in sys.argv[1].split(",") if x]
print(f"{min(vals):.3f}" if vals else "-1")' "$csv"
}

mean_ms() {
  local csv="$1"
  python3 -c 'import sys
vals=[float(x) for x in sys.argv[1].split(",") if x]
print(f"{sum(vals)/len(vals):.3f}" if vals else "-1")' "$csv"
}

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1])[1:-1])' "$1"
}

time_binary_many() {
  local bin="$1"
  python3 - "$bin" "$EXAMPLE_WARMUPS" "$EXAMPLE_RUNS" "$BENCH_TIMEOUT" <<'PY'
import subprocess
import sys
import time

bin_path = sys.argv[1]
warmups = int(sys.argv[2])
runs = int(sys.argv[3])
timeout_arg = sys.argv[4]
timeout = None if timeout_arg == "" else float(timeout_arg)

def run_once():
    start = time.perf_counter_ns()
    try:
        result = subprocess.run(
            [bin_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return (124, None)
    elapsed_ms = (time.perf_counter_ns() - start) / 1_000_000.0
    return (result.returncode, elapsed_ms)

status = 0
for _ in range(warmups):
    status, _ = run_once()
    if status != 0:
        print(f"{status}\t-1\t-1\t")
        raise SystemExit(0)

durations = []
for _ in range(runs):
    status, elapsed = run_once()
    if status != 0:
        print(f"{status}\t-1\t-1\t")
        raise SystemExit(0)
    durations.append(elapsed)

dur_csv = ",".join(f"{v:.3f}" for v in durations)
run_min = min(durations) if durations else -1
run_mean = (sum(durations) / len(durations)) if durations else -1
print(f"0\t{run_min:.3f}\t{run_mean:.3f}\t{dur_csv}")
PY
}

run_bench_cmd() {
  if [ -n "$BENCH_TIMEOUT" ]; then
    timeout "$BENCH_TIMEOUT" "$@"
  else
    "$@"
  fi
}

echo "=== Weft Benchmarks (${SHA}) ==="
echo ""
echo "Example runs: ${EXAMPLE_RUNS} measured, ${EXAMPLE_WARMUPS} warmup"
echo ""

# Build the compiler first
./weft < compiler/main.weft > /tmp/bench_weft 2>/dev/null
chmod +x /tmp/bench_weft

# ── Self-compilation time ──
echo "Self-compilation (weft1 → weft2):"
SELF_START=$(now_ms)
/tmp/bench_weft < compiler/main.weft > /tmp/bench_weft2 2>/dev/null
SELF_END=$(now_ms)
SELF_MS=$((SELF_END - SELF_START))
SELF_SIZE=$(wc -c < /tmp/bench_weft2 | tr -d ' ')
echo "  time: ${SELF_MS}ms  size: ${SELF_SIZE} bytes"
chmod +x /tmp/bench_weft2

# ── Test suite time ──
echo ""
echo "Test suite:"
TEST_START=$(now_ms)
WEFT=/tmp/bench_weft2 bash run_tests.sh > /tmp/bench_test_out 2>/dev/null
TEST_END=$(now_ms)
TEST_MS=$((TEST_END - TEST_START))
TEST_FILES=$(grep "Runtime tests:" /tmp/bench_test_out | tail -1 | sed 's/.*Runtime tests: //' | sed 's/ files.*//')
TEST_TOTAL=$(grep "Runtime tests:" /tmp/bench_test_out | tail -1 | sed 's/.*files, //' | sed 's/ test blocks.*//')
echo "  time: ${TEST_MS}ms  files: ${TEST_FILES}  tests: ${TEST_TOTAL}"

# ── Example compilation + execution ──
echo ""
echo "Examples:"
EXAMPLES=""
EXAMPLE_FAIL=0
for f in examples/*.weft; do
  name=$(basename $f .weft)

  # Compilation time
  COMP_START=$(now_ms)
  set +e
  run_bench_cmd /tmp/bench_weft2 < "$f" > /tmp/bench_ex 2>/tmp/bench_ex_err
  COMP_STATUS=$?
  set -e
  COMP_END=$(now_ms)
  COMP_MS=$((COMP_END - COMP_START))
  EX_SIZE=$(wc -c < /tmp/bench_ex | tr -d ' ')
  DIAG_SIZE=$(wc -c < /tmp/bench_ex_err | tr -d ' ')

  if [ "$COMP_STATUS" -ne 0 ] || [ "$DIAG_SIZE" -ne 0 ] || [ "$EX_SIZE" -eq 0 ]; then
    echo "  ${name}: compile ${COMP_MS}ms, compile failed, size ${EX_SIZE}b"
    EXAMPLE_FAIL=$((EXAMPLE_FAIL+1))

    if [ -n "$EXAMPLES" ]; then EXAMPLES="${EXAMPLES}, "; fi
    EXAMPLES="${EXAMPLES}\"${name}\": {\"compile_ms\": ${COMP_MS}, \"run_ms\": 0, \"size\": ${EX_SIZE}, \"ok\": false}"

    rm -f /tmp/bench_ex /tmp/bench_ex_err
    continue
  fi

  chmod +x /tmp/bench_ex

  # Execution time. The first launch of a freshly emitted Mach-O can include
  # macOS validation/cache work, so warm once and record measured min/mean.
  TIMING_RESULT=$(time_binary_many /tmp/bench_ex)
  IFS=$'\t' read -r RUN_STATUS RUN_MS RUN_MEAN_MS RUN_DURATIONS <<< "$TIMING_RESULT"
  RUN_DURATIONS_ESCAPED=$(json_escape "$RUN_DURATIONS")

  if [ "$RUN_STATUS" -eq 0 ]; then
    echo "  ${name}: compile ${COMP_MS}ms, run min ${RUN_MS}ms, mean ${RUN_MEAN_MS}ms, size ${EX_SIZE}b"
  else
    echo "  ${name}: compile ${COMP_MS}ms, run failed (${RUN_STATUS}), size ${EX_SIZE}b"
    EXAMPLE_FAIL=$((EXAMPLE_FAIL+1))
  fi

  if [ -n "$EXAMPLES" ]; then EXAMPLES="${EXAMPLES}, "; fi
  if [ "$RUN_STATUS" -eq 0 ]; then
    EXAMPLES="${EXAMPLES}\"${name}\": {\"compile_ms\": ${COMP_MS}, \"run_ms\": ${RUN_MS}, \"run_min_ms\": ${RUN_MS}, \"run_mean_ms\": ${RUN_MEAN_MS}, \"runs_ms\": \"${RUN_DURATIONS_ESCAPED}\", \"size\": ${EX_SIZE}, \"ok\": true}"
  else
    EXAMPLES="${EXAMPLES}\"${name}\": {\"compile_ms\": ${COMP_MS}, \"run_ms\": ${RUN_MS}, \"run_min_ms\": ${RUN_MS}, \"run_mean_ms\": ${RUN_MEAN_MS}, \"runs_ms\": \"${RUN_DURATIONS_ESCAPED}\", \"size\": ${EX_SIZE}, \"ok\": false, \"exit_code\": ${RUN_STATUS}}"
  fi

  rm -f /tmp/bench_ex /tmp/bench_ex_err
done

# ── Record results ──
RESULT="{\"sha\": \"${SHA}\", \"ts\": \"${TS}\", \"self_compile_ms\": ${SELF_MS}, \"self_size\": ${SELF_SIZE}, \"test_ms\": ${TEST_MS}, \"test_files\": ${TEST_FILES}, \"test_count\": ${TEST_TOTAL}, \"examples\": {${EXAMPLES}}}"

# ── Summary ──
echo "Summary:"
echo "  Self-compile:  ${SELF_MS}ms (${SELF_SIZE} bytes)"
echo "  Test suite:    ${TEST_MS}ms (${TEST_TOTAL} tests)"
echo "  Examples:      ${EXAMPLE_FAIL} failed"
echo "  SHA: ${SHA}"

rm -f /tmp/bench_weft /tmp/bench_weft2 /tmp/bench_test_out
if [ "$EXAMPLE_FAIL" -gt 0 ]; then exit 1; fi

echo "$RESULT" >> bench/results.jsonl

echo ""
echo "=== Results recorded to bench/results.jsonl ==="
