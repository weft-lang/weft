#!/bin/bash
# run_checker_tests.sh -- checker-positive regression tests.
set -e

WEFT=${WEFT:-./weft}
PASS=0
FAIL=0
ERRORS=""

check_accepts() {
  local name="$1"
  local file="$2"
  local out
  out=$(timeout 30 "$WEFT" check < "$file" 2>&1 >/dev/null || true)
  if echo "$out" | grep -q "type error:"; then
    echo "  FAIL $name (unexpected type error)"
    echo "$out" | sed 's/^/    /'
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: unexpected type error"
  else
    echo "  ok $name"
    PASS=$((PASS+1))
  fi
}

check_accepts "method_return_let" "test/checker/method_return_let.weft"
check_accepts "compiler_self_check" "compiler/main.weft"

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "Checker test failures:"
  echo -e "$ERRORS"
  exit 1
fi

exit 0
