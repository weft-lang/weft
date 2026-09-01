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
# This is a per-process runaway-regression stop, not a memory scheduler or a
# worker-count throttle. Whole-compiler test workers inherit a large
# copy-on-write project image and legitimately report up to ~18.7 million KiB
# max RSS on target-local Linux; that figure cannot be summed across the fork
# tree without double counting shared pages. The repaired structural-layout
# leak crossed 47 GiB in one worker and left abandoned trees above 94 GiB. Keep
# generous headroom above the measured two-target baseline while still
# terminating that failure mode live.
WEFT_TEST_RUNAWAY_RSS_LIMIT_KB=${WEFT_TEST_RUNAWAY_RSS_LIMIT_KB:-24000000}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-$WEFT_TEST_RUNAWAY_RSS_LIMIT_KB}
WEFT_TEST_RUN_RSS_LIMIT_KB=${WEFT_TEST_RUN_RSS_LIMIT_KB:-$WEFT_TEST_RUNAWAY_RSS_LIMIT_KB}
WEFT_TEST_SHOW_TIMINGS=${WEFT_TEST_SHOW_TIMINGS:-1}
WEFT_HOST_JOBS=$(default_test_jobs)
WEFT_TOOL_JOBS=${WEFT_TOOL_JOBS:-4}
case "$WEFT_TOOL_JOBS" in
  ''|*[!0-9]*) echo "WEFT_TOOL_JOBS must be a positive integer" >&2; exit 2 ;;
esac
if [ "$WEFT_TOOL_JOBS" -lt 1 ]; then
  echo "WEFT_TOOL_JOBS must be a positive integer" >&2
  exit 2
fi
# The runtime planner and independent tool shards run concurrently. Reserve
# the tool width from the host-selected total unless the caller explicitly
# chooses a planner width; the runaway stop remains observational only.
if [ -z "${WEFT_TEST_JOBS:-}" ]; then
  WEFT_TEST_JOBS=$((WEFT_HOST_JOBS - WEFT_TOOL_JOBS))
  if [ "$WEFT_TEST_JOBS" -lt 1 ]; then WEFT_TEST_JOBS=1; fi
fi
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
export WEFT_TEST_RUNAWAY_RSS_LIMIT_KB
export WEFT_TEST_COMPILE_RSS_LIMIT_KB
export WEFT_TEST_RUN_RSS_LIMIT_KB
export WEFT_TEST_SHOW_TIMINGS
export WEFT_TOOL_JOBS

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

process_tree_snapshot() {
  ps -axo pid=,ppid=,rss= 2>/dev/null
}

process_tree_members() {
  local root_pid="$1"
  process_tree_snapshot | awk -v root="$root_pid" '
    { order[NR] = $1; parent[$1] = $2 }
    END {
      for (i = 1; i <= NR; i++) {
        pid = order[i]
        cursor = pid
        depth = 0
        while (cursor > 1 && depth < 128) {
          if (cursor == root) { print pid; break }
          cursor = parent[cursor]
          depth++
        }
      }
    }
  '
}

terminate_process_tree() {
  local root_pid="$1"
  local members
  members=$(process_tree_members "$root_pid")

  # Stop the scheduler before its current workers so it cannot refill slots
  # while the tree is being drained.
  kill "$root_pid" 2>/dev/null || true
  for member in $members; do
    if [ "$member" != "$root_pid" ]; then kill "$member" 2>/dev/null || true; fi
  done
  sleep 1

  members=$(process_tree_members "$root_pid")
  for member in $members; do kill -9 "$member" 2>/dev/null || true; done
  wait "$root_pid" 2>/dev/null || true
}

run_tree_process_rss_guarded() {
  local rss_limit_kb="$1"
  shift

  "$@" <&0 &
  local pid=$!
  local interrupted=0
  local polls=0
  local previous_int
  local previous_term
  previous_int=$(trap -p INT)
  previous_term=$(trap -p TERM)
  trap 'interrupted=1' INT TERM

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$interrupted" -eq 1 ]; then
      terminate_process_tree "$pid"
      if [ -n "$previous_int" ]; then eval "$previous_int"; else trap - INT; fi
      if [ -n "$previous_term" ]; then eval "$previous_term"; else trap - TERM; fi
      return 130
    fi

    local stat
    stat=$(ps -o stat= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ "$stat" == Z* ]]; then break; fi

    local offender
    offender=$(process_tree_snapshot | awk -v root="$pid" -v limit="$rss_limit_kb" '
      { order[NR] = $1; parent[$1] = $2; rss[$1] = $3 }
      END {
        for (i = 1; i <= NR; i++) {
          candidate = order[i]
          cursor = candidate
          depth = 0
          while (cursor > 1 && depth < 128) {
            if (cursor == root) {
              if (rss[candidate] > limit) { print candidate " " rss[candidate]; exit }
              break
            }
            cursor = parent[cursor]
            depth++
          }
        }
      }
    ')
    if [ -n "$offender" ]; then
      echo "planner runaway RSS stop: pid ${offender%% *} used ${offender##* } KB (per-process limit ${rss_limit_kb} KB)" >&2
      terminate_process_tree "$pid"
      if [ -n "$previous_int" ]; then eval "$previous_int"; else trap - INT; fi
      if [ -n "$previous_term" ]; then eval "$previous_term"; else trap - TERM; fi
      return 125
    fi

    polls=$((polls+1))
    if [ "$polls" -le 20 ]; then sleep 0.1; else sleep 1; fi
  done

  local status=0
  wait "$pid" || status=$?
  if [ -n "$previous_int" ]; then eval "$previous_int"; else trap - INT; fi
  if [ -n "$previous_term" ]; then eval "$previous_term"; else trap - TERM; fi
  return "$status"
}

run_timed_phase() {
  local label="$1"
  shift
  local started
  local status=0
  started=$(now_s)
  "$@" || status=$?
  echo "$label timing: $(($(now_s) - started))s wall"
  return "$status"
}

run_markdown_phase() {
  bash test/docs/run_markdown_examples.sh README.md docs/getting-started.md docs/networking.md &&
    bash test/docs/check_readme_facts.sh
}

run_bootstrap_phase() {
  local started
  local tmpw1
  local tmpw2
  local tmpw3
  local bootstrap_ok=1
  started=$(now_s)
  tmpw1=$(mktemp /tmp/weft_test_XXXXXX)
  tmpw2=$(mktemp /tmp/weft_test_XXXXXX)
  tmpw3=$(mktemp /tmp/weft_test_XXXXXX)

  if run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$WEFT" build compiler/main.weft -o "$tmpw1" > /dev/null 2>&1; then
    chmod +x "$tmpw1"
  else
    bootstrap_ok=0
    echo "  ✗ bootstrap stage 1 failed"
  fi
  if [ "$bootstrap_ok" -eq 1 ]; then
    if run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$tmpw1" build compiler/main.weft -o "$tmpw2" > /dev/null 2>&1; then
      chmod +x "$tmpw2"
    else
      bootstrap_ok=0
      echo "  ✗ bootstrap stage 2 failed"
    fi
  fi
  if [ "$bootstrap_ok" -eq 1 ]; then
    if run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$tmpw2" build compiler/main.weft -o "$tmpw3" > /dev/null 2>&1; then
      chmod +x "$tmpw3"
    else
      bootstrap_ok=0
      echo "  ✗ bootstrap stage 3 failed"
    fi
  fi
  if [ "$bootstrap_ok" -eq 1 ] && diff <(xxd "$tmpw2") <(xxd "$tmpw3") > /dev/null 2>&1; then
    echo "  ✓ weft2 == weft3 (byte-identical)"
  else
    bootstrap_ok=0
    echo "  ✗ bootstrap gate failed"
  fi
  rm -f "$tmpw1" "$tmpw2" "$tmpw3"
  echo "Bootstrap timing: $(($(now_s) - started))s wall"
  [ "$bootstrap_ok" -eq 1 ]
}

collect_phase() {
  local label="$1"
  local pid="$2"
  local log="$3"
  local status=0
  wait "$pid" || status=$?
  /bin/cat "$log"
  if [ "$status" -eq 0 ]; then
    PASS=$((PASS+1))
  else
    echo "  ✗ $label failed"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $label failed"
  fi
}

RESULTS_DIR=""
TOOL_PHASE_PID=""
BOOTSTRAP_PHASE_PID=""
LINKED_PHASE_PID=""
CHECKER_PHASE_PID=""
SIGNING_PHASE_PID=""
FORMATTER_PHASE_PID=""
MARKDOWN_PHASE_PID=""
NEGATIVE_PHASE_PID=""

cleanup_suite() {
  local status=$?
  local phase_pid
  trap - EXIT INT TERM
  for phase_pid in \
    "$TOOL_PHASE_PID" \
    "$BOOTSTRAP_PHASE_PID" \
    "$LINKED_PHASE_PID" \
    "$CHECKER_PHASE_PID" \
    "$SIGNING_PHASE_PID" \
    "$FORMATTER_PHASE_PID" \
    "$MARKDOWN_PHASE_PID" \
    "$NEGATIVE_PHASE_PID"; do
    if [ -n "$phase_pid" ] && kill -0 "$phase_pid" 2>/dev/null; then
      terminate_process_tree "$phase_pid"
    fi
  done
  if [ -n "$RESULTS_DIR" ] && [ -d "$RESULTS_DIR" ]; then
    rm -rf "$RESULTS_DIR"
  fi
  exit "$status"
}

trap cleanup_suite EXIT
trap 'exit 130' INT TERM

SUITE_STARTED=$(now_s)
echo "=== Weft Test Suite ==="
echo "runtime compile timeout: ${WEFT_TEST_COMPILE_TIMEOUT}s"
echo "runtime run timeout: ${WEFT_TEST_RUN_TIMEOUT}s"
echo "runtime per-worker compile RSS result limit: ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB"
echo "runtime per-worker run RSS result limit: ${WEFT_TEST_RUN_RSS_LIMIT_KB} KB"
echo "live per-process runaway RSS stop: ${WEFT_TEST_RUNAWAY_RSS_LIMIT_KB} KB"
echo "runtime jobs: ${WEFT_TEST_JOBS}"
echo "tool shard jobs: ${WEFT_TOOL_JOBS}"
echo ""

RESULTS_DIR=$(mktemp -d /tmp/weft_suite_XXXXXX)
PLANNER_ERR="$RESULTS_DIR/planner.err"
PLANNER_OUT="$RESULTS_DIR/planner.out"
TOOL_PHASE_LOG="$RESULTS_DIR/tool.log"
(echo ""; echo "=== Tool Boundary Tests ==="; run_timed_phase "Tool boundary" bash test/tools/run_tool_tests.sh) > "$TOOL_PHASE_LOG" 2>&1 &
TOOL_PHASE_PID=$!
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
  run_tree_process_rss_guarded "$WEFT_TEST_RUNAWAY_RSS_LIMIT_KB" env WEFT_TEST_METRICS=1 "$WEFT" test --jobs "$WEFT_TEST_JOBS" "${RUNTIME_TEST_FILES[@]}" > "$PLANNER_OUT" 2> "$PLANNER_ERR" || planner_exit=$?
  if [ "$planner_exit" -eq 130 ]; then exit 130; fi
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

BOOTSTRAP_PHASE_LOG="$RESULTS_DIR/bootstrap.log"
LINKED_PHASE_LOG="$RESULTS_DIR/linked.log"
CHECKER_PHASE_LOG="$RESULTS_DIR/checker.log"
SIGNING_PHASE_LOG="$RESULTS_DIR/signing.log"
FORMATTER_PHASE_LOG="$RESULTS_DIR/formatter.log"
MARKDOWN_PHASE_LOG="$RESULTS_DIR/markdown.log"
NEGATIVE_PHASE_LOG="$RESULTS_DIR/negative.log"

(echo ""; echo "=== Bootstrap Gate ==="; run_bootstrap_phase) > "$BOOTSTRAP_PHASE_LOG" 2>&1 &
BOOTSTRAP_PHASE_PID=$!
(echo ""; echo "=== Linked Tests ==="; run_timed_phase "Linked tests" bash test/linked/run_linked_tests.sh) > "$LINKED_PHASE_LOG" 2>&1 &
LINKED_PHASE_PID=$!
(echo ""; echo "=== Checker Tests ==="; run_timed_phase "Checker tests" bash test/checker/run_checker_tests.sh) > "$CHECKER_PHASE_LOG" 2>&1 &
CHECKER_PHASE_PID=$!
(echo ""; echo "=== Release Signing Tests ==="; run_timed_phase "Release signing" bash test/run_release_signing.sh) > "$SIGNING_PHASE_LOG" 2>&1 &
SIGNING_PHASE_PID=$!
(echo ""; echo "=== Formatter Dogfood ==="; run_timed_phase "Formatter dogfood" bash test/tools/run_formatter_dogfood.sh) > "$FORMATTER_PHASE_LOG" 2>&1 &
FORMATTER_PHASE_PID=$!
(echo ""; echo "=== Markdown Examples ==="; run_timed_phase "Markdown examples" run_markdown_phase) > "$MARKDOWN_PHASE_LOG" 2>&1 &
MARKDOWN_PHASE_PID=$!
(echo ""; echo "=== Negative Tests ==="; run_timed_phase "Negative tests" bash test/negative/run_negative_tests.sh) > "$NEGATIVE_PHASE_LOG" 2>&1 &
NEGATIVE_PHASE_PID=$!

collect_phase "bootstrap gate" "$BOOTSTRAP_PHASE_PID" "$BOOTSTRAP_PHASE_LOG"
BOOTSTRAP_PHASE_PID=""
collect_phase "linked tests" "$LINKED_PHASE_PID" "$LINKED_PHASE_LOG"
LINKED_PHASE_PID=""
collect_phase "checker tests" "$CHECKER_PHASE_PID" "$CHECKER_PHASE_LOG"
CHECKER_PHASE_PID=""
collect_phase "tool boundary tests" "$TOOL_PHASE_PID" "$TOOL_PHASE_LOG"
TOOL_PHASE_PID=""
collect_phase "release signing tests" "$SIGNING_PHASE_PID" "$SIGNING_PHASE_LOG"
SIGNING_PHASE_PID=""
collect_phase "formatter dogfood" "$FORMATTER_PHASE_PID" "$FORMATTER_PHASE_LOG"
FORMATTER_PHASE_PID=""
collect_phase "markdown examples" "$MARKDOWN_PHASE_PID" "$MARKDOWN_PHASE_LOG"
MARKDOWN_PHASE_PID=""
collect_phase "negative tests" "$NEGATIVE_PHASE_PID" "$NEGATIVE_PHASE_LOG"
NEGATIVE_PHASE_PID=""

rm -rf "$RESULTS_DIR"
RESULTS_DIR=""

echo ""
echo "=== Summary ==="
echo "$PASS suite groups passed, $FAIL failed"
echo "Runtime tests: $RUNTIME_FILES files, $RUNTIME_TESTS test blocks"
echo "Runtime compile time: ${RUNTIME_COMPILE_SECONDS}s (cpu-summed; planner worker width ${WEFT_TEST_JOBS})"
echo "Runtime execution time: ${RUNTIME_RUN_SECONDS}s (cpu-summed)"
echo "Complete wall time: $(($(now_s) - SUITE_STARTED))s"
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
