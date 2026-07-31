#!/bin/bash
# run_tests.sh — thin test runner for weft test files
# Compiles each test/*.weft file with `weft test`, runs the binary, reports results.
set -e

WEFT=${WEFT:-./weft}
WEFT_TEST_COMPILE_TIMEOUT=${WEFT_TEST_COMPILE_TIMEOUT:-120}
WEFT_TEST_RUN_TIMEOUT=${WEFT_TEST_RUN_TIMEOUT:-120}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-8000000}
# Whole-compiler in-process tripwire tests (ir_verifier_metrics,
# emission_audit_metrics) legitimately peak at ~1.7 GB arena RSS; the
# limit guards runaways above that with margin.
# 4 GB: full-tree checking (every imported body) grew in-process pipeline
# metric tests' peak RSS from ~2.5 GB to ~3.7 GB. Checker allocation
# frugality / identifier interning is the queued lever to bring this down.
WEFT_TEST_RUN_RSS_LIMIT_KB=${WEFT_TEST_RUN_RSS_LIMIT_KB:-4000000}
WEFT_TEST_SHOW_TIMINGS=${WEFT_TEST_SHOW_TIMINGS:-1}
PASS=0
FAIL=0
ERRORS=""
RUNTIME_FILES=0
RUNTIME_TESTS=0
RUNTIME_COMPILE_SECONDS=0
RUNTIME_RUN_SECONDS=0

export WEFT
export WEFT_TEST_COMPILE_TIMEOUT
export WEFT_TEST_RUN_TIMEOUT
export WEFT_TEST_COMPILE_RSS_LIMIT_KB
export WEFT_TEST_RUN_RSS_LIMIT_KB

now_s() {
  date +%s
}

run_guarded() {
  local timeout_s="$1"
  local rss_limit_kb="$2"
  shift 2

  "$@" <&0 &
  local pid=$!
  local start
  start=$(now_s)

  while kill -0 "$pid" 2>/dev/null; do
    local stat
    stat=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ "$stat" == Z* ]]; then
      break
    fi

    local rss
    rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -n "$rss" ] && [ "$rss" -gt "$rss_limit_kb" ]; then
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 125
    fi

    local elapsed
    elapsed=$(($(now_s) - start))
    if [ "$elapsed" -ge "$timeout_s" ]; then
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi

    sleep 1
  done

  wait "$pid"
}

echo "=== Weft Test Suite ==="
echo "runtime compile timeout: ${WEFT_TEST_COMPILE_TIMEOUT}s"
echo "runtime run timeout: ${WEFT_TEST_RUN_TIMEOUT}s"
echo "runtime compile RSS limit: ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB"
echo "runtime run RSS limit: ${WEFT_TEST_RUN_RSS_LIMIT_KB} KB"
echo ""

for f in $(grep -l 'test "' test/*.weft 2>/dev/null); do
  name=$(basename "$f" .weft)
  tmpbin=$(mktemp /tmp/weft_test_XXXXXX)
  file_tests=$(grep -c 'test "' "$f")
  RUNTIME_FILES=$((RUNTIME_FILES+1))
  RUNTIME_TESTS=$((RUNTIME_TESTS+file_tests))

  # Compile test file through strict path-mode; stdin test compilation is strict
  # too, but path-mode keeps source identity explicit in the project suite.
  compile_exit=0
  compile_start=$(now_s)
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$WEFT" test "$f" > "$tmpbin" 2>/dev/null || compile_exit=$?
  compile_elapsed=$(($(now_s) - compile_start))
  RUNTIME_COMPILE_SECONDS=$((RUNTIME_COMPILE_SECONDS+compile_elapsed))
  if [ $compile_exit -ne 0 ]; then
    if [ $compile_exit -eq 124 ]; then
      echo "  ✗ $name (compilation timed out after ${WEFT_TEST_COMPILE_TIMEOUT}s; compile ${compile_elapsed}s)"
      ERRORS="$ERRORS\n  $name: compilation timed out after ${WEFT_TEST_COMPILE_TIMEOUT}s (compile ${compile_elapsed}s)"
    elif [ $compile_exit -eq 125 ]; then
      echo "  ✗ $name (compilation exceeded ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB RSS; compile ${compile_elapsed}s)"
      ERRORS="$ERRORS\n  $name: compilation exceeded ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB RSS (compile ${compile_elapsed}s)"
    else
      echo "  ✗ $name (compilation failed; exit $compile_exit; compile ${compile_elapsed}s)"
      ERRORS="$ERRORS\n  $name: compilation failed (exit $compile_exit, compile ${compile_elapsed}s)"
    fi
    FAIL=$((FAIL+1))
    rm -f "$tmpbin"
    continue
  fi

  chmod +x "$tmpbin"

  # Run test binary
  exit_code=0
  run_start=$(now_s)
  run_guarded "$WEFT_TEST_RUN_TIMEOUT" "$WEFT_TEST_RUN_RSS_LIMIT_KB" "$tmpbin" 2>/dev/null || exit_code=$?
  run_elapsed=$(($(now_s) - run_start))
  RUNTIME_RUN_SECONDS=$((RUNTIME_RUN_SECONDS+run_elapsed))

  if [ $exit_code -eq 0 ]; then
    if [ "$WEFT_TEST_SHOW_TIMINGS" -eq 1 ]; then
      echo "  ✓ $name (compile ${compile_elapsed}s, run ${run_elapsed}s)"
    else
      echo "  ✓ $name"
    fi
    PASS=$((PASS+1))
  elif [ $exit_code -eq 124 ]; then
    echo "  ✗ $name (runtime timed out after ${WEFT_TEST_RUN_TIMEOUT}s; compile ${compile_elapsed}s, run ${run_elapsed}s)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: runtime timed out after ${WEFT_TEST_RUN_TIMEOUT}s (compile ${compile_elapsed}s, run ${run_elapsed}s)"
  elif [ $exit_code -eq 125 ]; then
    echo "  ✗ $name (runtime exceeded ${WEFT_TEST_RUN_RSS_LIMIT_KB} KB RSS; compile ${compile_elapsed}s, run ${run_elapsed}s)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: runtime exceeded ${WEFT_TEST_RUN_RSS_LIMIT_KB} KB RSS (compile ${compile_elapsed}s, run ${run_elapsed}s)"
  else
    echo "  ✗ $name ($exit_code failures; compile ${compile_elapsed}s, run ${run_elapsed}s)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: $exit_code failures (compile ${compile_elapsed}s, run ${run_elapsed}s)"
  fi

  rm -f "$tmpbin"
done

# Main-style legacy programs (no test blocks): compile + run, comparing
# the exit code against the REQUIRED '-- Expected exit code: N'
# annotation. A missing annotation is a failure — these files were
# silently skipped for months because the loop above only iterates
# files containing test blocks (2u).
for f in test/*.weft; do
  grep -q 'test "' "$f" && continue
  name=$(basename "$f" .weft)
  RUNTIME_FILES=$((RUNTIME_FILES+1))
  RUNTIME_TESTS=$((RUNTIME_TESTS+1))
  expected=$(grep -o 'Expected exit code: [0-9]*' "$f" | head -1 | grep -o '[0-9]*$')
  if [ -z "$expected" ]; then
    echo "  ✗ $name (main-style file missing '-- Expected exit code: N' annotation)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: missing expected-exit annotation"
    continue
  fi
  tmpbin=$(mktemp /tmp/weft_main_XXXXXX)
  compile_exit=0
  compile_start=$(now_s)
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$WEFT" compile "$f" > "$tmpbin" 2>/dev/null || compile_exit=$?
  compile_elapsed=$(($(now_s) - compile_start))
  RUNTIME_COMPILE_SECONDS=$((RUNTIME_COMPILE_SECONDS+compile_elapsed))
  if [ $compile_exit -ne 0 ]; then
    echo "  ✗ $name (compilation failed; exit $compile_exit; compile ${compile_elapsed}s)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: compilation failed (exit $compile_exit)"
    rm -f "$tmpbin"
    continue
  fi
  chmod +x "$tmpbin"
  # Expected values must stay below 124: run_guarded reserves 124/125
  # for timeout/RSS kills, and exit codes are mod-256 anyway.
  exit_code=0
  run_start=$(now_s)
  run_guarded "$WEFT_TEST_RUN_TIMEOUT" "$WEFT_TEST_RUN_RSS_LIMIT_KB" "$tmpbin" >/dev/null 2>/dev/null || exit_code=$?
  run_elapsed=$(($(now_s) - run_start))
  RUNTIME_RUN_SECONDS=$((RUNTIME_RUN_SECONDS+run_elapsed))
  if [ "$exit_code" = "$expected" ]; then
    if [ "$WEFT_TEST_SHOW_TIMINGS" -eq 1 ]; then
      echo "  ✓ $name (=$expected; compile ${compile_elapsed}s, run ${run_elapsed}s)"
    else
      echo "  ✓ $name"
    fi
    PASS=$((PASS+1))
  else
    echo "  ✗ $name (exit $exit_code, expected $expected)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: exit $exit_code != expected $expected"
  fi
  rm -f "$tmpbin"
done

echo ""
echo "=== Bootstrap Gate ==="
# Quick 3-stage bootstrap check
tmpw1=$(mktemp /tmp/weft_test_XXXXXX)
tmpw2=$(mktemp /tmp/weft_test_XXXXXX)
tmpw3=$(mktemp /tmp/weft_test_XXXXXX)
bootstrap_ok=1
if run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$WEFT" compile compiler/main.weft > "$tmpw1" 2>/dev/null; then
  chmod +x "$tmpw1"
else
  bootstrap_ok=0
  echo "  ✗ bootstrap stage 1 failed"
fi
if [ $bootstrap_ok -eq 1 ]; then
  if run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$tmpw1" compile compiler/main.weft > "$tmpw2" 2>/dev/null; then
    chmod +x "$tmpw2"
  else
    bootstrap_ok=0
    echo "  ✗ bootstrap stage 2 failed"
  fi
fi
if [ $bootstrap_ok -eq 1 ]; then
  if run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$tmpw2" compile compiler/main.weft > "$tmpw3" 2>/dev/null; then
    chmod +x "$tmpw3"
  else
    bootstrap_ok=0
    echo "  ✗ bootstrap stage 3 failed"
  fi
fi
if [ $bootstrap_ok -eq 1 ] && diff <(xxd "$tmpw2") <(xxd "$tmpw3") > /dev/null 2>&1; then
  echo "  ✓ weft2 == weft3 (byte-identical)"
  PASS=$((PASS+1))
else
  echo "  ✗ bootstrap gate failed"
  FAIL=$((FAIL+1))
fi
rm -f "$tmpw1" "$tmpw2" "$tmpw3"

echo ""
echo "=== Linked Tests ==="
if bash test/linked/run_linked_tests.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ linked tests failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  linked tests failed"
fi

echo ""
echo "=== Checker Tests ==="
if bash test/checker/run_checker_tests.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ checker tests failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  checker tests failed"
fi

echo ""
echo "=== Tool Boundary Tests ==="
if bash test/tools/run_tool_tests.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ tool boundary tests failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  tool boundary tests failed"
fi

echo ""
echo "=== Negative Tests ==="
if bash test/negative/run_negative_tests.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ negative tests failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  negative tests failed"
fi

echo ""
echo "=== Summary ==="
echo "$PASS suite groups passed, $FAIL failed"
echo "Runtime tests: $RUNTIME_FILES files, $RUNTIME_TESTS test blocks"
echo "Runtime compile time: ${RUNTIME_COMPILE_SECONDS}s"
echo "Runtime execution time: ${RUNTIME_RUN_SECONDS}s"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
