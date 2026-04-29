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
check_rejects "let_bound_lambda_effect_mismatch" "test/negative/let_bound_lambda_effect_mismatch.weft" "type error: argument type mismatch"
check_rejects "let_bound_lambda_effect_unavailable" "test/negative/let_bound_lambda_effect_unavailable.weft" "type error: effect not available in caller"
check_rejects "let_bound_lambda_return_mismatch" "test/negative/let_bound_lambda_return_mismatch.weft" "type error: argument type mismatch"
check_rejects "unknown_identifier" "test/negative/unknown_identifier.weft" "type error: unknown identifier"
check_rejects "unknown_function" "test/negative/unknown_function.weft" "type error: unknown function"
check_rejects "call_non_function" "test/negative/call_non_function.weft" "type error: called value is not a function"
check_rejects "unknown_record_field" "test/negative/unknown_record_field.weft" "type error: unknown field"
check_rejects "field_access_non_record" "test/negative/field_access_non_record.weft" "type error: field access on non-record"
check_rejects "record_init_unknown_type" "test/negative/record_init_unknown_type.weft" "type error: unknown record type"
check_rejects "record_init_unknown_field" "test/negative/record_init_unknown_field.weft" "type error: unknown record field"
check_rejects "record_init_missing_field" "test/negative/record_init_missing_field.weft" "type error: missing record field"
check_rejects "record_init_duplicate_field" "test/negative/record_init_duplicate_field.weft" "type error: duplicate record field"
check_rejects "record_init_variant_type" "test/negative/record_init_variant_type.weft" "type error: not a record type"
check_rejects "record_init_field_type_mismatch" "test/negative/record_init_field_type_mismatch.weft" "type error: record field type mismatch"
check_rejects "record_field_access_type_mismatch" "test/negative/record_field_access_type_mismatch.weft" "type error: return type mismatch"
check_rejects "match_arm_i64_str_mismatch" "test/negative/match_arm_i64_str_mismatch.weft" "type error: match arm type mismatch"
check_rejects "match_arm_str_bool_mismatch" "test/negative/match_arm_str_bool_mismatch.weft" "type error: match arm type mismatch"
check_rejects "match_arm_record_mismatch" "test/negative/match_arm_record_mismatch.weft" "type error: match arm type mismatch"
check_rejects "call_arity_too_few" "test/negative/call_arity_too_few.weft" "type error: arity mismatch"
check_rejects "call_arity_too_many" "test/negative/call_arity_too_many.weft" "type error: arity mismatch"
check_rejects "generic_call_arity_mismatch" "test/negative/generic_call_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "function_value_arity_mismatch" "test/negative/function_value_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "effect_perform_arity_too_few" "test/negative/effect_perform_arity_too_few.weft" "type error: arity mismatch"
check_rejects "effect_perform_arity_too_many" "test/negative/effect_perform_arity_too_many.weft" "type error: arity mismatch"
check_rejects "handler_clause_unknown_op" "test/negative/handler_clause_unknown_op.weft" "type error: unknown effect operation"
check_rejects "handler_clause_effect_mismatch" "test/negative/handler_clause_effect_mismatch.weft" "type error: handler clause effect mismatch"
check_rejects "handler_clause_arity_too_few" "test/negative/handler_clause_arity_too_few.weft" "type error: arity mismatch"
check_rejects "handler_clause_arity_too_many" "test/negative/handler_clause_arity_too_many.weft" "type error: arity mismatch"
check_rejects "handler_clause_param_type_mismatch" "test/negative/handler_clause_param_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "handler_clause_resume_type_mismatch" "test/negative/handler_clause_resume_type_mismatch.weft" "type error: resume type mismatch"
check_rejects "handler_clause_duplicate" "test/negative/handler_clause_duplicate.weft" "type error: duplicate handler clause"
check_rejects "handler_clause_missing_direct" "test/negative/handler_clause_missing_direct.weft" "type error: missing handler clause"
check_rejects "handler_clause_missing_branch" "test/negative/handler_clause_missing_branch.weft" "type error: missing handler clause"
check_rejects "generic_type_payload_mismatch" "test/negative/generic_type_payload_mismatch.weft" "type error: argument type mismatch"
check_rejects "generic_type_return_mismatch" "test/negative/generic_type_return_mismatch.weft" "type error: value does not match let type annotation"
check_rejects "generic_type_constructor_arity" "test/negative/generic_type_constructor_arity.weft" "type error: arity mismatch"
check_rejects "generic_type_arg_count" "test/negative/generic_type_arg_count.weft" "type error: wrong number of type arguments"
check_rejects "generic_type_pattern_payload_mismatch" "test/negative/generic_type_pattern_payload_mismatch.weft" "type error: return type mismatch"

echo ""
echo "=== Negative Summary ==="
echo "$PASS passed, $FAIL failed"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
