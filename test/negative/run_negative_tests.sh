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
check_rejects "effect_perform_arg_mismatch" "test/negative/effect_perform_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "effectful_lambda_to_pure_fn" "test/negative/effectful_lambda_to_pure_fn.weft" "type error: effect not available in caller"
check_rejects "effectful_lambda_to_pure_effect_op" "test/negative/effectful_lambda_to_pure_effect_op.weft" "type error: effect not available in caller"
check_rejects "function_value_effect_unavailable" "test/negative/function_value_effect_unavailable.weft" "type error: effect not available in caller"
check_rejects "function_value_arg_mismatch" "test/negative/function_value_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "function_value_return_mismatch" "test/negative/function_value_return_mismatch.weft" "type error: return type mismatch"
check_rejects "call_arity_too_few" "test/negative/call_arity_too_few.weft" "type error: arity mismatch"
check_rejects "call_arity_too_many" "test/negative/call_arity_too_many.weft" "type error: arity mismatch"
check_rejects "generic_call_arity_mismatch" "test/negative/generic_call_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "function_value_arity_mismatch" "test/negative/function_value_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "effect_perform_arity_too_few" "test/negative/effect_perform_arity_too_few.weft" "type error: arity mismatch"
check_rejects "effect_perform_arity_too_many" "test/negative/effect_perform_arity_too_many.weft" "type error: arity mismatch"

echo ""
echo "=== Negative Summary ==="
echo "$PASS passed, $FAIL failed"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
