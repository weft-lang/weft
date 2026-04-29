#!/bin/bash
# Negative type-checking tests. These assert diagnostics for programs that
# should be rejected by the checker even though code emission is still lenient.
set -e

WEFT=${WEFT:-./weft}
PASS=0
FAIL=0
ERRORS=""

echo "=== Negative Test Suite ==="
echo ""

check_rejects() {
  local name="$1"
  local file="$2"
  local pattern="$3"
  local out

  out=$(timeout 30 "$WEFT" check < "$file" 2>&1 >/dev/null || true)
  if echo "$out" | grep -q "$pattern"; then
    echo "  ✓ $name"
    PASS=$((PASS+1))
  else
    echo "  ✗ $name"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: expected diagnostic '$pattern'"
  fi
}

check_rejects "par_map_effectful" "test/negative/par_map_effectful.weft" "type error: argument type mismatch"
check_rejects "unhandled_effect_perform" "test/negative/unhandled_effect_perform.weft" "type error: effect not available in caller"
check_rejects "unhandled_effect_in_while" "test/negative/unhandled_effect_in_while.weft" "type error: effect not available in caller"
check_rejects "unhandled_try_effect" "test/negative/unhandled_try_effect.weft" "type error: effect not available in caller"

echo ""
echo "=== Negative Summary ==="
echo "$PASS passed, $FAIL failed"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
