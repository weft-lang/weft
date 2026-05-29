#!/bin/bash
# bench.sh — benchmark the Weft compiler and example programs
# Records results as JSON lines appended to bench/results.jsonl
# Each line: {"sha": "...", "ts": "...", "metrics": {...}}
set -e

SHA=$(git rev-parse --short HEAD)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p bench
BENCH_TIMEOUT="${WEFT_BENCH_TIMEOUT:-}"

run_bench_cmd() {
  if [ -n "$BENCH_TIMEOUT" ]; then
    timeout "$BENCH_TIMEOUT" "$@"
  else
    "$@"
  fi
}

echo "=== Weft Benchmarks (${SHA}) ==="
echo ""

# Build the compiler first
./weft < compiler/main.weft > /tmp/bench_weft 2>/dev/null
chmod +x /tmp/bench_weft

# ── Self-compilation time ──
echo "Self-compilation (weft1 → weft2):"
SELF_START=$(python3 -c "import time; print(int(time.time()*1000))")
/tmp/bench_weft < compiler/main.weft > /tmp/bench_weft2 2>/dev/null
SELF_END=$(python3 -c "import time; print(int(time.time()*1000))")
SELF_MS=$((SELF_END - SELF_START))
SELF_SIZE=$(wc -c < /tmp/bench_weft2 | tr -d ' ')
echo "  time: ${SELF_MS}ms  size: ${SELF_SIZE} bytes"
chmod +x /tmp/bench_weft2

# ── Test suite time ──
echo ""
echo "Test suite:"
TEST_START=$(python3 -c "import time; print(int(time.time()*1000))")
WEFT=/tmp/bench_weft2 bash run_tests.sh > /tmp/bench_test_out 2>/dev/null
TEST_END=$(python3 -c "import time; print(int(time.time()*1000))")
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
  COMP_START=$(python3 -c "import time; print(int(time.time()*1000))")
  set +e
  run_bench_cmd /tmp/bench_weft2 < "$f" > /tmp/bench_ex 2>/tmp/bench_ex_err
  COMP_STATUS=$?
  set -e
  COMP_END=$(python3 -c "import time; print(int(time.time()*1000))")
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

  # Execution time
  RUN_START=$(python3 -c "import time; print(int(time.time()*1000))")
  set +e
  run_bench_cmd /tmp/bench_ex > /dev/null 2>/dev/null
  RUN_STATUS=$?
  set -e
  RUN_END=$(python3 -c "import time; print(int(time.time()*1000))")
  RUN_MS=$((RUN_END - RUN_START))

  if [ "$RUN_STATUS" -eq 0 ]; then
    echo "  ${name}: compile ${COMP_MS}ms, run ${RUN_MS}ms, size ${EX_SIZE}b"
  else
    echo "  ${name}: compile ${COMP_MS}ms, run ${RUN_MS}ms failed (${RUN_STATUS}), size ${EX_SIZE}b"
    EXAMPLE_FAIL=$((EXAMPLE_FAIL+1))
  fi

  if [ -n "$EXAMPLES" ]; then EXAMPLES="${EXAMPLES}, "; fi
  if [ "$RUN_STATUS" -eq 0 ]; then
    EXAMPLES="${EXAMPLES}\"${name}\": {\"compile_ms\": ${COMP_MS}, \"run_ms\": ${RUN_MS}, \"size\": ${EX_SIZE}, \"ok\": true}"
  else
    EXAMPLES="${EXAMPLES}\"${name}\": {\"compile_ms\": ${COMP_MS}, \"run_ms\": ${RUN_MS}, \"size\": ${EX_SIZE}, \"ok\": false, \"exit_code\": ${RUN_STATUS}}"
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
