#!/bin/bash
# bench.sh — benchmark the Weft compiler and example programs
# Records results as JSON lines appended to bench/results.jsonl
# Each line: {"sha": "...", "ts": "...", "metrics": {...}}
set -e

SHA=$(git rev-parse --short HEAD)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p bench

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
bash test_self_host.sh 2>/dev/null | tail -5 > /tmp/bench_test_out
TEST_END=$(python3 -c "import time; print(int(time.time()*1000))")
TEST_MS=$((TEST_END - TEST_START))
TEST_TOTAL=$(grep "Total:" /tmp/bench_test_out | tail -1 | sed 's/.*Total: //' | sed 's/ passed.*//')
echo "  time: ${TEST_MS}ms  tests: ${TEST_TOTAL}"

# ── Example compilation + execution ──
echo ""
echo "Examples:"
EXAMPLES=""
for f in examples/*.weft; do
  name=$(basename $f .weft)

  # Compilation time
  COMP_START=$(python3 -c "import time; print(int(time.time()*1000))")
  /tmp/bench_weft2 < "$f" > /tmp/bench_ex 2>/dev/null
  COMP_END=$(python3 -c "import time; print(int(time.time()*1000))")
  COMP_MS=$((COMP_END - COMP_START))
  chmod +x /tmp/bench_ex
  EX_SIZE=$(wc -c < /tmp/bench_ex | tr -d ' ')

  # Execution time
  RUN_START=$(python3 -c "import time; print(int(time.time()*1000))")
  timeout 30 /tmp/bench_ex > /dev/null 2>/dev/null
  RUN_END=$(python3 -c "import time; print(int(time.time()*1000))")
  RUN_MS=$((RUN_END - RUN_START))

  echo "  ${name}: compile ${COMP_MS}ms, run ${RUN_MS}ms, size ${EX_SIZE}b"

  if [ -n "$EXAMPLES" ]; then EXAMPLES="${EXAMPLES}, "; fi
  EXAMPLES="${EXAMPLES}\"${name}\": {\"compile_ms\": ${COMP_MS}, \"run_ms\": ${RUN_MS}, \"size\": ${EX_SIZE}}"

  rm -f /tmp/bench_ex
done

# ── Record results ──
RESULT="{\"sha\": \"${SHA}\", \"ts\": \"${TS}\", \"self_compile_ms\": ${SELF_MS}, \"self_size\": ${SELF_SIZE}, \"test_ms\": ${TEST_MS}, \"test_count\": ${TEST_TOTAL}, \"examples\": {${EXAMPLES}}}"
echo "$RESULT" >> bench/results.jsonl

echo ""
echo "=== Results recorded to bench/results.jsonl ==="
echo ""

# ── Summary ──
echo "Summary:"
echo "  Self-compile:  ${SELF_MS}ms (${SELF_SIZE} bytes)"
echo "  Test suite:    ${TEST_MS}ms (${TEST_TOTAL} tests)"
echo "  SHA: ${SHA}"

rm -f /tmp/bench_weft /tmp/bench_weft2 /tmp/bench_test_out
