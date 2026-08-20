#!/bin/bash
# run_tests.sh — repository gate over the public project test planner.
# Every runnable root enters one `weft test` project session so shared checked
# dependency products survive across both test blocks and expected-exit programs.
set -e

default_test_jobs() {
  local detected
  detected=$(sysctl -n hw.ncpu 2>/dev/null || true)
  if ! [[ "$detected" =~ ^[0-9]+$ ]] || [ "$detected" -lt 1 ]; then
    detected=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
  fi
  if ! [[ "$detected" =~ ^[0-9]+$ ]] || [ "$detected" -lt 1 ]; then
    detected=4
  fi
  echo "$detected"
}

WEFT=${WEFT:-./weft}
WEFT_TEST_COMPILE_TIMEOUT=${WEFT_TEST_COMPILE_TIMEOUT:-120}
WEFT_TEST_RUN_TIMEOUT=${WEFT_TEST_RUN_TIMEOUT:-120}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-8000000}
# Whole-compiler in-process tripwire tests (alloc_checker_metrics and
# emission_audit_metrics) briefly peak at ~6.3 GB arena RSS.  The previous
# 4 GB guard was below that honest baseline and passed nondeterministically
# whenever its one-second polling missed the peak.  Keep a real runaway
# guard with margin; checker allocation frugality / identifier interning is
# the queued lever to bring this baseline down.
WEFT_TEST_RUN_RSS_LIMIT_KB=${WEFT_TEST_RUN_RSS_LIMIT_KB:-8000000}
WEFT_TEST_SHOW_TIMINGS=${WEFT_TEST_SHOW_TIMINGS:-1}
WEFT_TEST_JOBS=${WEFT_TEST_JOBS:-$(default_test_jobs)}
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
export WEFT_TEST_SHOW_TIMINGS

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
  local polls=0

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

    # Fine-grained polling keeps sub-second guarded commands from being billed
    # a full 1s sleep quantum; fall back to 1s for long-running processes.
    polls=$((polls+1))
    if [ "$polls" -le 20 ]; then
      sleep 0.1
    else
      sleep 1
    fi
  done

  wait "$pid"
}

echo "=== Weft Test Suite ==="
echo "runtime compile timeout: ${WEFT_TEST_COMPILE_TIMEOUT}s"
echo "runtime run timeout: ${WEFT_TEST_RUN_TIMEOUT}s"
echo "runtime compile RSS limit: ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB"
echo "runtime run RSS limit: ${WEFT_TEST_RUN_RSS_LIMIT_KB} KB"
echo "runtime jobs: ${WEFT_TEST_JOBS}"
echo ""

RESULTS_DIR=$(mktemp -d /tmp/weft_suite_XXXXXX)
PLANNER_ERR="$RESULTS_DIR/planner.err"
PLANNER_OUT="$RESULTS_DIR/planner.out"
RUNTIME_TEST_FILES=()
RUNTIME_TEST_BLOCKS=0

for f in test/*.weft; do
  if grep -q 'test "' "$f"; then
    RUNTIME_TEST_FILES+=("$f")
    file_blocks=$(grep -c 'test "' "$f")
    RUNTIME_TEST_BLOCKS=$((RUNTIME_TEST_BLOCKS + file_blocks))
  elif grep -qE '(^|[[:space:]])fn[[:space:]]+main[[:space:]]*\(' "$f"; then
    # Imported helper/data modules also live under test/. Only standalone
    # programs with an actual main declaration are project roots. The planner
    # validates their required expected-exit directive.
    RUNTIME_TEST_FILES+=("$f")
    RUNTIME_TEST_BLOCKS=$((RUNTIME_TEST_BLOCKS + 1))
  fi
done

# The public planner owns discovery, checked-dependency sharing, root
# isolation, compile/link/run timeouts, RSS accounting, and worker scheduling.
# Capture once, then replay root results in canonical path order so repository
# observation stays deterministic even though workers finish out of order.
runtime_count=${#RUNTIME_TEST_FILES[@]}
if [ "$runtime_count" -gt 0 ]; then
  planner_exit=0
  WEFT_TEST_METRICS=1 "$WEFT" test --jobs "$WEFT_TEST_JOBS" "${RUNTIME_TEST_FILES[@]}" > "$PLANNER_OUT" 2> "$PLANNER_ERR" || planner_exit=$?
  planner_failures=0
  for f in "${RUNTIME_TEST_FILES[@]}"; do
    pass_report=$(grep -F "  pass: $f (" "$PLANNER_ERR" | tail -1 || true)
    fail_report=$(grep -F "  FAIL: $f (" "$PLANNER_ERR" | tail -1 || true)
    RUNTIME_FILES=$((RUNTIME_FILES+1))
    if [ -n "$pass_report" ] && [ -z "$fail_report" ]; then
      echo "$pass_report"
      PASS=$((PASS+1))
    elif [ -n "$fail_report" ]; then
      echo "$fail_report"
      FAIL=$((FAIL+1))
      planner_failures=$((planner_failures+1))
    else
      echo "  FAIL: $f (public planner produced no root result)"
      FAIL=$((FAIL+1))
      planner_failures=$((planner_failures+1))
    fi
  done
  RUNTIME_TESTS=$((RUNTIME_TESTS + RUNTIME_TEST_BLOCKS))

  metrics_line=$(grep '^WEFT_TEST_METRICS ' "$PLANNER_ERR" | tail -1 || true)
  read -r metrics_marker metrics_version metrics_roots metrics_measured metrics_wall metrics_discovery metrics_planning metrics_compile metrics_link metrics_run metrics_user metrics_system metrics_peak metrics_shared_groups metrics_shared_roots metrics_reused_pairs metrics_query_hits metrics_query_misses metrics_query_executions metrics_extra <<< "$metrics_line"
  metrics_valid=1
  if [ "$metrics_marker" != "WEFT_TEST_METRICS" ] || [ "$metrics_version" != "2" ] || [ -n "${metrics_extra:-}" ]; then
    metrics_valid=0
  elif ! [[ "$metrics_roots" =~ ^[0-9]+$ && "$metrics_measured" =~ ^[0-9]+$ && "$metrics_wall" =~ ^[0-9]+$ && "$metrics_discovery" =~ ^[0-9]+$ && "$metrics_planning" =~ ^[0-9]+$ && "$metrics_compile" =~ ^[0-9]+$ && "$metrics_link" =~ ^[0-9]+$ && "$metrics_run" =~ ^[0-9]+$ && "$metrics_user" =~ ^[0-9]+$ && "$metrics_system" =~ ^[0-9]+$ && "$metrics_peak" =~ ^[0-9]+$ && "$metrics_shared_groups" =~ ^[0-9]+$ && "$metrics_shared_roots" =~ ^[0-9]+$ && "$metrics_reused_pairs" =~ ^[0-9]+$ && "$metrics_query_hits" =~ ^[0-9]+$ && "$metrics_query_misses" =~ ^[0-9]+$ && "$metrics_query_executions" =~ ^[0-9]+$ ]]; then
    metrics_valid=0
  elif [ "$metrics_roots" -ne "$runtime_count" ] || [ "$metrics_measured" -gt "$metrics_roots" ] || [ "$metrics_shared_groups" -gt "$metrics_shared_roots" ] || [ "$metrics_shared_roots" -gt "$metrics_roots" ]; then
    metrics_valid=0
  elif [ "$planner_failures" -eq 0 ] && [ "$metrics_measured" -ne "$runtime_count" ]; then
    metrics_valid=0
  fi
  if [ "$metrics_valid" -eq 1 ]; then
    RUNTIME_COMPILE_SECONDS=$((RUNTIME_COMPILE_SECONDS + (metrics_compile + metrics_link + 999) / 1000))
    RUNTIME_RUN_SECONDS=$((RUNTIME_RUN_SECONDS + (metrics_run + 999) / 1000))
    human_metrics=$(grep '^test metrics:' "$PLANNER_ERR" | tail -1 || true)
    if [ -n "$human_metrics" ]; then echo "  $human_metrics"; fi
  else
    echo "  FAIL: public planner emitted invalid aggregate metrics"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  public planner emitted invalid aggregate metrics: $metrics_line"
  fi

  expected_planner_exit=0
  if [ "$planner_failures" -gt 0 ]; then expected_planner_exit=1; fi
  if [ "$planner_exit" -ne "$expected_planner_exit" ]; then
    echo "  FAIL: public planner exit $planner_exit disagrees with $planner_failures failed roots"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  public planner exit/result disagreement"
  fi
  if [ "$planner_failures" -gt 0 ]; then
    ERRORS="$ERRORS\n$(cat "$PLANNER_ERR")"
  fi
fi

rm -rf "$RESULTS_DIR"

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
echo "=== Formatter Dogfood ==="
if bash test/tools/run_formatter_dogfood.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ formatter dogfood failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  formatter dogfood failed"
fi

echo ""
echo "=== Markdown Examples ==="
if bash test/docs/run_markdown_examples.sh README.md docs/getting-started.md && bash test/docs/check_readme_facts.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ markdown examples failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  markdown examples failed"
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
echo "Runtime compile time: ${RUNTIME_COMPILE_SECONDS}s (cpu-summed; planner worker width ${WEFT_TEST_JOBS})"
echo "Runtime execution time: ${RUNTIME_RUN_SECONDS}s (cpu-summed)"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi

if [ "$FAIL" -eq 0 ]; then
  exit 0
else
  exit 1
fi
