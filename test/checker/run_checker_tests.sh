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
check_accepts "handled_effect_perform" "test/checker/handled_effect_perform.weft"
check_accepts "handled_try_effect" "test/checker/handled_try_effect.weft"
check_accepts "imported_effect_perform_args" "test/checker/imported_effect_perform_args.weft"
check_accepts "contextual_lambda_pure" "test/checker/contextual_lambda_pure.weft"
check_accepts "contextual_lambda_effectful" "test/checker/contextual_lambda_effectful.weft"
check_accepts "contextual_effect_op_lambda" "test/checker/contextual_effect_op_lambda.weft"
check_accepts "function_value_pure_call" "test/checker/function_value_pure_call.weft"
check_accepts "function_value_effect_call" "test/checker/function_value_effect_call.weft"
check_accepts "let_bound_lambdas" "test/checker/let_bound_lambdas.weft"
check_accepts "name_resolution" "test/checker/name_resolution.weft"
check_accepts "field_access" "test/checker/field_access.weft"
check_accepts "record_init" "test/checker/record_init.weft"
check_accepts "match_arm_types" "test/checker/match_arm_types.weft"
check_accepts "bool_contexts" "test/checker/bool_contexts.weft"
check_accepts "arity_happy_paths" "test/checker/arity_happy_paths.weft"
check_accepts "handler_clause_typing" "test/checker/handler_clause_typing.weft"
check_accepts "handler_clause_coverage" "test/checker/handler_clause_coverage.weft"
check_accepts "generic_type_declarations" "test/checker/generic_type_declarations.weft"
check_accepts "compiler_self_check" "compiler/main.weft"

if [ $FAIL -gt 0 ]; then
  echo ""
  echo "Checker test failures:"
  echo -e "$ERRORS"
  exit 1
fi

exit 0
