#!/bin/bash
# run_linked_tests.sh — compile and run programs that use native system calls.
# Weft's native linker owns the Mach-O/GOT/bind finalization exercised here.
set -e

WEFT=${WEFT:-./weft}
WEFT_TEST_COMPILE_TIMEOUT=${WEFT_TEST_COMPILE_TIMEOUT:-30}
WEFT_TEST_RUN_TIMEOUT=${WEFT_TEST_RUN_TIMEOUT:-120}
WEFT_TEST_RUNAWAY_RSS_LIMIT_KB=${WEFT_TEST_RUNAWAY_RSS_LIMIT_KB:-16000000}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-$WEFT_TEST_RUNAWAY_RSS_LIMIT_KB}
WEFT_TEST_RUN_RSS_LIMIT_KB=${WEFT_TEST_RUN_RSS_LIMIT_KB:-1000000}
PASS=0
FAIL=0
SKIP=0
ERRORS=""
WEFT_TEST_PLATFORM=${WEFT_TEST_PLATFORM:-$(uname -s)}

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

    # Fine-grained polling early so sub-second guarded processes are not
    # billed a full 1s sleep quantum; long-running ones fall back to 1s.
    polls=$((polls+1))
    if [ "$polls" -le 20 ]; then
      sleep 0.1
    else
      sleep 1
    fi
  done

  wait "$pid"
}

echo "=== Linked Test Suite ==="
echo ""

for f in test/linked/*.weft; do
  name=$(basename "$f" .weft)

  # Linux standalone artifacts intentionally have no system dynamic library or
  # GOT. These two tests exercise Darwin's documented libSystem bind contract;
  # target-neutral semantic write/thread/provenance coverage runs on both.
  case "$WEFT_TEST_PLATFORM:$name" in
    Linux:got_basic|Linux:imported_got)
      echo "  - $name (Darwin system-GOT contract)"
      SKIP=$((SKIP+1))
      continue
      ;;
  esac

  tmpbin=$(mktemp /tmp/weft_linked_XXXXXX)

  # Compile straight to the final native-linked executable. No host linker or
  # SDK discovery participates in this product gate.
  compile_exit=0
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$WEFT" test --emit "$f" > "$tmpbin" 2>/dev/null || compile_exit=$?
  if [ "$compile_exit" -ne 0 ]; then
    if [ "$compile_exit" -eq 124 ]; then
      echo "  ✗ $name (compilation timed out)"
      ERRORS="$ERRORS\n  $name: compilation timed out"
    elif [ "$compile_exit" -eq 125 ]; then
      echo "  ✗ $name (compilation exceeded ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB RSS)"
      ERRORS="$ERRORS\n  $name: compilation exceeded ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB RSS"
    else
      echo "  ✗ $name (compilation failed)"
      ERRORS="$ERRORS\n  $name: compilation failed"
    fi
    FAIL=$((FAIL+1))
    rm -f "$tmpbin"
    continue
  fi

  chmod +x "$tmpbin"

  # Run and check exit code (0 = pass). Fresh linked binaries can spend more
  # than 10s in cold macOS ad-hoc signature verification on first launch.
  exit_code=0
  run_guarded "$WEFT_TEST_RUN_TIMEOUT" "$WEFT_TEST_RUN_RSS_LIMIT_KB" "$tmpbin" >/dev/null 2>/dev/null || exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo "  ✓ $name"
    PASS=$((PASS+1))
  else
    if [ "$exit_code" -eq 124 ]; then
      echo "  ✗ $name (runtime timed out)"
      ERRORS="$ERRORS\n  $name: runtime timed out"
    elif [ "$exit_code" -eq 125 ]; then
      echo "  ✗ $name (runtime exceeded ${WEFT_TEST_RUN_RSS_LIMIT_KB} KB RSS)"
      ERRORS="$ERRORS\n  $name: runtime exceeded ${WEFT_TEST_RUN_RSS_LIMIT_KB} KB RSS"
    else
      echo "  ✗ $name (exit $exit_code)"
      ERRORS="$ERRORS\n  $name: exit $exit_code"
    fi
    FAIL=$((FAIL+1))
  fi

  rm -f "$tmpbin"
done

echo ""
echo "=== Linked Summary ==="
echo "$PASS passed, $FAIL failed, $SKIP target-specific skipped"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
