#!/bin/bash
# run_checker_tests.sh -- checker-positive regression tests.
set -e

WEFT=${WEFT:-./weft}
WEFT_TEST_COMPILE_TIMEOUT=${WEFT_TEST_COMPILE_TIMEOUT:-120}
WEFT_TEST_RUNAWAY_RSS_LIMIT_KB=${WEFT_TEST_RUNAWAY_RSS_LIMIT_KB:-16000000}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-$WEFT_TEST_RUNAWAY_RSS_LIMIT_KB}
PASS=0
FAIL=0
ERRORS=""

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

check_accepts() {
  local name="$1"
  local file="$2"
  local out
  local status
  set +e
  out=$(run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$WEFT" check "$file" 2>&1 >/dev/null)
  status=$?
  set -e
  if [ "$status" -eq 124 ]; then
    echo "  FAIL $name (checker timed out)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: checker timed out"
    return
  fi
  if [ "$status" -eq 125 ]; then
    echo "  FAIL $name (checker exceeded ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB RSS)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: checker exceeded ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB RSS"
    return
  fi
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
check_accepts "runtime_syscall_unsafe_wrapper" "runtime/syscall.weft"
check_accepts "runtime_rc_unsafe_wrapper" "runtime/rc.weft"
check_accepts "stdlib_process_unsafe_surface" "stdlib/process.weft"
check_accepts "stdlib_io_typed_drop_receiver" "stdlib/io.weft"
check_accepts "contextual_lambda_pure" "test/checker/contextual_lambda_pure.weft"
check_accepts "contextual_lambda_effectful" "test/checker/contextual_lambda_effectful.weft"
check_accepts "contextual_effect_op_lambda" "test/checker/contextual_effect_op_lambda.weft"
check_accepts "function_value_pure_call" "test/checker/function_value_pure_call.weft"
check_accepts "function_value_effect_call" "test/checker/function_value_effect_call.weft"
check_accepts "method_calls" "test/checker/method_calls.weft"
check_accepts "trait_impl_signatures" "test/checker/trait_impl_signatures.weft"
check_accepts "trait_associated_types" "test/checker/trait_associated_types.weft"
check_accepts "orphan_trait_local" "test/checker/orphan_trait_local.weft"
check_accepts "orphan_type_local" "test/checker/orphan_type_local.weft"
check_accepts "let_bound_lambdas" "test/checker/let_bound_lambdas.weft"
check_accepts "name_resolution" "test/checker/name_resolution.weft"
check_accepts "field_access" "test/checker/field_access.weft"
check_accepts "record_init" "test/checker/record_init.weft"
check_accepts "match_arm_types" "test/checker/match_arm_types.weft"
check_accepts "pattern_shapes" "test/checker/pattern_shapes.weft"
check_accepts "bool_contexts" "test/checker/bool_contexts.weft"
check_accepts "assignment_types" "test/checker/assignment_types.weft"
check_accepts "control_transfer" "test/checker/control_transfer.weft"
check_accepts "operator_types" "test/checker/operator_types.weft"
check_accepts "arity_happy_paths" "test/checker/arity_happy_paths.weft"
check_accepts "handler_clause_typing" "test/checker/handler_clause_typing.weft"
check_accepts "handler_clause_coverage" "test/checker/handler_clause_coverage.weft"
check_accepts "generic_type_declarations" "test/checker/generic_type_declarations.weft"
check_accepts "array_slice_types" "test/checker/array_slice_types.weft"
check_accepts "structural_types" "test/checker/structural_types.weft"
check_accepts "no_else_nil" "test/checker/no_else_nil.weft"
check_accepts "compiler_self_check" "compiler/main.weft"

echo ""
echo "Checker summary: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
  echo ""
  echo "Checker test failures:"
  echo -e "$ERRORS"
  exit 1
fi

exit 0
