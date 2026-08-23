#!/bin/bash
# Formatter dogfood: rewrite a repository mirror, then prove the formatted
# compiler and representative direct/linked programs retain their behaviour.
set -e

WEFT=${WEFT:-./weft}
WEFT_TEST_COMPILE_TIMEOUT=${WEFT_TEST_COMPILE_TIMEOUT:-120}
WEFT_TEST_RUN_TIMEOUT=${WEFT_TEST_RUN_TIMEOUT:-120}
WEFT_TEST_RUNAWAY_RSS_LIMIT_KB=${WEFT_TEST_RUNAWAY_RSS_LIMIT_KB:-16000000}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-$WEFT_TEST_RUNAWAY_RSS_LIMIT_KB}
WEFT_TEST_RUN_RSS_LIMIT_KB=${WEFT_TEST_RUN_RSS_LIMIT_KB:-1000000}
case "$WEFT" in
  /*) WEFT_ABS="$WEFT" ;;
  *) WEFT_ABS="$(pwd)/$WEFT" ;;
esac

SOURCE_ROOT=$(pwd)
MIRROR=$(mktemp -d /tmp/weft_formatter_dogfood_XXXXXX)
trap 'rm -rf "$MIRROR"' EXIT

PASS=0

ok() {
  echo "  ok $1"
  PASS=$((PASS+1))
}

fail() {
  echo "  fail $1"
  if [ -n "$2" ] && [ -s "$2" ]; then
    while IFS= read -r line; do
      echo "    $line"
    done < "$2"
  fi
  exit 1
}

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

    polls=$((polls+1))
    if [ "$polls" -le 20 ]; then
      sleep 0.1
    else
      sleep 1
    fi
  done

  wait "$pid"
}

echo "=== Formatter Dogfood ==="
echo ""

cp -R compiler runtime stdlib tools test "$MIRROR/"

if (
  cd "$MIRROR"
  "$WEFT_ABS" fmt --write compiler runtime stdlib tools test/*.weft \
    test/linked/tool_platform.weft > fmt-write.out 2> fmt-write.err
); then
  ok "formatter_rewrites_repository_mirror"
else
  fail "formatter_rewrites_repository_mirror" "$MIRROR/fmt-write.err"
fi

if [ ! -s "$MIRROR/fmt-write.out" ] && [ ! -s "$MIRROR/fmt-write.err" ]; then
  ok "formatter_mirror_write_is_silent"
else
  fail "formatter_mirror_write_is_silent" "$MIRROR/fmt-write.err"
fi

if (
  cd "$MIRROR"
  "$WEFT_ABS" fmt --check compiler runtime stdlib tools test/*.weft \
    test/linked/tool_platform.weft > fmt-check.out 2> fmt-check.err
); then
  ok "formatter_repository_mirror_is_idempotent"
else
  fail "formatter_repository_mirror_is_idempotent" "$MIRROR/fmt-check.err"
fi

if [ ! -s "$MIRROR/fmt-check.out" ] && [ ! -s "$MIRROR/fmt-check.err" ]; then
  ok "formatter_mirror_check_is_silent"
else
  fail "formatter_mirror_check_is_silent" "$MIRROR/fmt-check.err"
fi

if (
  cd "$MIRROR"
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" \
    "$WEFT_ABS" check compiler/main.weft > compiler-check.out 2> compiler-check.err
); then
  ok "formatted_compiler_typechecks"
else
  fail "formatted_compiler_typechecks" "$MIRROR/compiler-check.err"
fi

if ! grep -qF "0 errors" "$MIRROR/compiler-check.out" && \
   ! grep -qF "0 errors" "$MIRROR/compiler-check.err"; then
  fail "formatted_compiler_reports_zero_errors" "$MIRROR/compiler-check.err"
fi
ok "formatted_compiler_reports_zero_errors"

if ! (
  cd "$MIRROR"
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" \
    "$WEFT_ABS" compile compiler/main.weft > weft-formatted-1 2> compiler-1.err
); then
  fail "formatted_compiler_stage_one_builds" "$MIRROR/compiler-1.err"
fi
chmod +x "$MIRROR/weft-formatted-1"

if ! (
  cd "$MIRROR"
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" \
    ./weft-formatted-1 compile compiler/main.weft > weft-formatted-2 2> compiler-2.err
); then
  fail "formatted_compiler_self_compiles" "$MIRROR/compiler-2.err"
fi

if cmp -s "$MIRROR/weft-formatted-1" "$MIRROR/weft-formatted-2"; then
  ok "formatted_compiler_gate_is_byte_identical"
else
  fail "formatted_compiler_gate_is_byte_identical" ""
fi

if ! run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" \
  "$WEFT_ABS" compile "$SOURCE_ROOT/test/e2e_pipeline.weft" \
  > "$MIRROR/direct-original" 2> "$MIRROR/direct-original.err"; then
  fail "formatter_direct_original_compiles" "$MIRROR/direct-original.err"
fi
if ! (
  cd "$MIRROR"
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" \
    "$WEFT_ABS" compile test/e2e_pipeline.weft \
    > direct-formatted 2> direct-formatted.err
); then
  fail "formatter_direct_formatted_compiles" "$MIRROR/direct-formatted.err"
fi
chmod +x "$MIRROR/direct-original" "$MIRROR/direct-formatted"

set +e
run_guarded "$WEFT_TEST_RUN_TIMEOUT" "$WEFT_TEST_RUN_RSS_LIMIT_KB" \
  "$MIRROR/direct-original" > "$MIRROR/direct-original.out" 2> "$MIRROR/direct-original.run.err"
direct_original_status=$?
run_guarded "$WEFT_TEST_RUN_TIMEOUT" "$WEFT_TEST_RUN_RSS_LIMIT_KB" \
  "$MIRROR/direct-formatted" > "$MIRROR/direct-formatted.out" 2> "$MIRROR/direct-formatted.run.err"
direct_formatted_status=$?
set -e

if [ "$direct_original_status" -eq 42 ] && \
   [ "$direct_formatted_status" -eq 42 ] && \
   cmp -s "$MIRROR/direct-original.out" "$MIRROR/direct-formatted.out" && \
   cmp -s "$MIRROR/direct-original.run.err" "$MIRROR/direct-formatted.run.err"; then
  ok "formatter_preserves_direct_program_behavior"
else
  fail "formatter_preserves_direct_program_behavior" "$MIRROR/direct-formatted.run.err"
fi

if ! run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" \
  "$WEFT_ABS" test --emit "$SOURCE_ROOT/test/linked/tool_platform.weft" \
  > "$MIRROR/linked-original" 2> "$MIRROR/linked-original.err"; then
  fail "formatter_linked_original_compiles" "$MIRROR/linked-original.err"
fi
if ! (
  cd "$MIRROR"
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" \
    "$WEFT_ABS" test --emit test/linked/tool_platform.weft \
    > linked-formatted 2> linked-formatted.err
); then
  fail "formatter_linked_formatted_compiles" "$MIRROR/linked-formatted.err"
fi
chmod +x "$MIRROR/linked-original" "$MIRROR/linked-formatted"

set +e
run_guarded "$WEFT_TEST_RUN_TIMEOUT" "$WEFT_TEST_RUN_RSS_LIMIT_KB" \
  "$MIRROR/linked-original" > "$MIRROR/linked-original.out" 2> "$MIRROR/linked-original.run.err"
linked_original_status=$?
run_guarded "$WEFT_TEST_RUN_TIMEOUT" "$WEFT_TEST_RUN_RSS_LIMIT_KB" \
  "$MIRROR/linked-formatted" > "$MIRROR/linked-formatted.out" 2> "$MIRROR/linked-formatted.run.err"
linked_formatted_status=$?
set -e

if [ "$linked_original_status" -eq 0 ] && \
   [ "$linked_formatted_status" -eq 0 ] && \
   cmp -s "$MIRROR/linked-original.out" "$MIRROR/linked-formatted.out" && \
   cmp -s "$MIRROR/linked-original.run.err" "$MIRROR/linked-formatted.run.err"; then
  ok "formatter_preserves_linked_program_behavior"
else
  fail "formatter_preserves_linked_program_behavior" "$MIRROR/linked-formatted.run.err"
fi

echo ""
echo "Formatter dogfood summary: $PASS passed, 0 failed"
