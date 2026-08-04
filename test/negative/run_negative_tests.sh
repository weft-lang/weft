#!/bin/bash
# Negative type-checking tests. These assert diagnostics for programs that
# should be rejected by the checker even though code emission is still lenient.
set -e

WEFT=${WEFT:-./weft}
WEFT_TEST_COMPILE_TIMEOUT=${WEFT_TEST_COMPILE_TIMEOUT:-120}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-8000000}
WEFT_TEST_JOBS=${WEFT_TEST_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}
PASS=0
FAIL=0
ERRORS=""

export WEFT
export WEFT_TEST_COMPILE_TIMEOUT
export WEFT_TEST_COMPILE_RSS_LIMIT_KB

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

    # Fine-grained polling early: each negative case is a sub-second
    # `weft check`, and a 1s quantum billed 349 cases ~6 minutes of
    # pure sleep. Long-running processes fall back to 1s polls.
    polls=$((polls+1))
    if [ "$polls" -le 20 ]; then
      sleep 0.1
    else
      sleep 1
    fi
  done

  wait "$pid"
}

# ---------------------------------------------------------------------------
# Worker mode: `bash run_negative_tests.sh __worker <jobfile>` runs ONE
# check (jobfile lines: name / file / pattern), streams its ✓/✗ line, and
# writes a .meta (pass|fail) + .err record beside the jobfile. Always
# exits 0; the parent aggregates in job order.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "__worker" ]; then
  jobf="$2"
  name=$(sed -n 1p "$jobf")
  file=$(sed -n 2p "$jobf")
  pattern=$(sed -n 3p "$jobf")

  set +e
  out=$(run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$WEFT" check "$file" 2>&1 >/dev/null)
  status=$?
  set -e
  if [ "$status" -eq 124 ]; then
    echo "  ✗ $name"
    echo "  $name: checker timed out" > "$jobf.err"
    echo "fail" > "$jobf.meta"
    exit 0
  fi
  if [ "$status" -eq 125 ]; then
    echo "  ✗ $name"
    echo "  $name: checker exceeded ${WEFT_TEST_COMPILE_RSS_LIMIT_KB} KB RSS" > "$jobf.err"
    echo "fail" > "$jobf.meta"
    exit 0
  fi
  if echo "$out" | grep -q "$pattern"; then
    echo "  ✓ $name"
    echo "pass" > "$jobf.meta"
  else
    echo "  ✗ $name"
    echo "  $name: expected diagnostic '$pattern'" > "$jobf.err"
    echo "fail" > "$jobf.meta"
  fi
  exit 0
fi

echo "=== Negative Test Suite ==="
echo ""

JOBS_DIR=$(mktemp -d /tmp/weft_negative_XXXXXX)
JOB_N=0

# Enqueue only — the call sites below stay declarative; the pool at the
# end runs them WEFT_TEST_JOBS wide through worker mode.
check_rejects() {
  JOB_N=$((JOB_N+1))
  local jf
  jf=$(printf '%s/job_%04d' "$JOBS_DIR" "$JOB_N")
  printf '%s\n%s\n%s\n' "$1" "$2" "$3" > "$jf"
}

check_rejects "par_map_effectful" "test/negative/par_map_effectful.weft" "type error: argument type mismatch"
check_rejects "deep_release_mask_overflow_record" "test/negative/deep_release_mask_overflow_record.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "deep_release_mask_overflow_variant_closure" "test/negative/deep_release_mask_overflow_variant_closure.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "deep_release_mask_overflow_weak" "test/negative/deep_release_mask_overflow_weak.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "deep_release_mask_overflow_generic" "test/negative/deep_release_mask_overflow_generic.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "par_map_scoped_effectful" "test/negative/par_map_scoped_effectful.weft" "type error: argument type mismatch"
check_rejects "par_pool_submit_effectful" "test/negative/par_pool_submit_effectful.weft" "type error: argument type mismatch"
check_rejects "par_prepared_submit_public" "test/negative/par_prepared_submit_public.weft" "type error: prepared Par submission is compiler-internal"
check_rejects "generator_new_non_literal_producer" "test/negative/generator_new_non_literal_producer.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_new_nonzero_arg_producer" "test/negative/generator_new_nonzero_arg_producer.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_new_function_with_arg" "test/negative/generator_new_function_with_arg.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_new_mutable_closure_producer" "test/negative/generator_new_mutable_closure_producer.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_new_return_type_mismatch" "test/negative/generator_new_return_type_mismatch.weft" "type error: return type mismatch"
check_rejects "generator_yield_unhandled" "test/negative/generator_yield_unhandled.weft" "type error: effect not available in caller"
check_rejects "generator_generic_new_non_literal_producer" "test/negative/generator_generic_new_non_literal_producer.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_generic_new_function_with_arg" "test/negative/generator_generic_new_function_with_arg.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_generic_new_mutable_closure_producer" "test/negative/generator_generic_new_mutable_closure_producer.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_generic_new_return_type_mismatch" "test/negative/generator_generic_new_return_type_mismatch.weft" "type error: return type mismatch"
check_rejects "generator_generic_yield_unhandled" "test/negative/generator_generic_yield_unhandled.weft" "type error: effect not available in caller"
check_rejects "unhandled_effect_perform" "test/negative/unhandled_effect_perform.weft" "type error: effect not available in caller"
check_rejects "unhandled_alloc_effect" "test/negative/unhandled_alloc_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_raw_syscall_requires_effect" "test/negative/unsafe_raw_syscall_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_raw_offset_requires_effect" "test/negative/unsafe_raw_offset_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_transmute_requires_effect" "test/negative/unsafe_transmute_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_int_to_ptr_requires_effect" "test/negative/unsafe_int_to_ptr_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_runtime_state_requires_effect" "test/negative/unsafe_runtime_state_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_set_runtime_state_requires_effect" "test/negative/unsafe_set_runtime_state_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_set_handler_stack_requires_effect" "test/negative/unsafe_set_handler_stack_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_raw_call_i64_requires_effect" "test/negative/unsafe_raw_call_i64_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_call_closure_i64_requires_effect" "test/negative/unsafe_call_closure_i64_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_fiber_suspend_requires_effect" "test/negative/unsafe_fiber_suspend_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_fiber_resume_requires_effect" "test/negative/unsafe_fiber_resume_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_fiber_wrapper_requires_effect" "test/negative/unsafe_fiber_wrapper_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_got_requires_effect" "test/negative/unsafe_got_requires_effect.weft" "type error: effect not available in caller"
check_rejects "root_raw_syscall_with_effect_requires_trusted" "test/negative/root_raw_syscall_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "root_mem_with_effect_requires_trusted" "test/negative/root_mem_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "root_alloc_with_effect_requires_trusted" "test/negative/root_alloc_with_effect_requires_trusted.weft" "type error: raw allocation is sealed to trusted runtime/platform code"
check_rejects "root_atomic_lock_with_effect_requires_trusted" "test/negative/root_atomic_lock_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "root_pointer_with_effect_requires_trusted" "test/negative/root_pointer_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "root_unsafe_handler_requires_trusted" "test/negative/root_unsafe_handler_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "root_unsafe_perform_requires_trusted" "test/negative/root_unsafe_perform_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "unsafe_runtime_helper_with_effect_requires_trusted" "test/negative/unsafe_runtime_helper_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "pipeline_origin_helper_requires_trusted" "test/negative/pipeline_origin_helper_requires_trusted.weft" "type error: source trust is sealed to trusted compiler/runtime code"
check_rejects "pipeline_trust_helper_requires_trusted" "test/negative/pipeline_trust_helper_requires_trusted.weft" "type error: source trust is sealed to trusted compiler/runtime code"
check_rejects "ttable_mark_trusted_requires_trusted" "test/negative/ttable_mark_trusted_requires_trusted.weft" "type error: source trust is sealed to trusted compiler/runtime code"
check_rejects "unsafe_imported_got_requires_trusted" "test/negative/unsafe_imported_got_requires_effect.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "unsafe_imported_mem_requires_trusted" "test/negative/unsafe_imported_mem_requires_effect.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "unsafe_imported_mem_store_requires_trusted" "test/negative/unsafe_imported_mem_store_requires_effect.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "unsafe_imported_got_with_effect_requires_trusted" "test/negative/unsafe_imported_got_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "unsafe_imported_mem_with_effect_requires_trusted" "test/negative/unsafe_imported_mem_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "unsafe_imported_mem_store_with_effect_requires_trusted" "test/negative/unsafe_imported_mem_store_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "imported_bump_alloc_requires_trusted" "test/negative/imported_bump_alloc_requires_trusted.weft" "type error: raw allocation is sealed to trusted runtime/platform code"
check_rejects "imported_alloc_bump_with_effect_requires_trusted" "test/negative/imported_alloc_bump_with_effect_requires_trusted.weft" "type error: raw allocation is sealed to trusted runtime/platform code"
check_rejects "unsafe_imported_handler_requires_trusted" "test/negative/unsafe_imported_handler_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "unsafe_imported_perform_requires_trusted" "test/negative/unsafe_imported_perform_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "unknown_got_symbol" "test/negative/unknown_got_symbol.weft" "type error: unknown GOT symbol"
check_rejects "unknown_imported_got_symbol" "test/negative/unknown_imported_got_symbol.weft" "type error: unknown GOT symbol"
check_rejects "unsafe_wrapper_must_discharge" "test/negative/unsafe_wrapper_must_discharge.weft" "type error: effect not available in caller"
check_rejects "unsafe_raw_offset_wrapper_requires_effect" "test/negative/unsafe_raw_offset_wrapper_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_transmute_wrapper_requires_effect" "test/negative/unsafe_transmute_wrapper_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_int_to_ptr_wrapper_requires_effect" "test/negative/unsafe_int_to_ptr_wrapper_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_raw_offset_pointer_arg_required" "test/negative/unsafe_raw_offset_pointer_arg_required.weft" "type error: argument type mismatch"
check_rejects "unsafe_raw_offset_wrapper_pointer_arg_required" "test/negative/unsafe_raw_offset_wrapper_pointer_arg_required.weft" "type error: argument type mismatch"
check_rejects "unsafe_int_to_ptr_addr_mismatch" "test/negative/unsafe_int_to_ptr_addr_mismatch.weft" "type error: argument type mismatch"
check_rejects "unsafe_transmute_arity_mismatch" "test/negative/unsafe_transmute_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "unsafe_runtime_state_wrapper_requires_effect" "test/negative/unsafe_runtime_state_wrapper_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_process_run_command_requires_effect" "test/negative/unsafe_process_run_command_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_method_call_requires_effect" "test/negative/unsafe_method_call_requires_effect.weft" "type error: effect not available in caller"
check_rejects "unsafe_lambda_to_pure_fn" "test/negative/unsafe_lambda_to_pure_fn.weft" "type error: effect not available in caller"
check_rejects "non_unsafe_handler_raw_call" "test/negative/non_unsafe_handler_raw_call.weft" "type error: effect not available in caller"
check_rejects "unhandled_effect_in_while" "test/negative/unhandled_effect_in_while.weft" "type error: effect not available in caller"
check_rejects "unhandled_effect_in_defer" "test/negative/unhandled_effect_in_defer.weft" "type error: effect not available in caller"
check_rejects "unhandled_try_effect" "test/negative/unhandled_try_effect.weft" "type error: effect not available in caller"
check_rejects "unhandled_optional_chain_effect" "test/negative/unhandled_optional_chain_effect.weft" "type error: effect not available in caller"
check_rejects "effect_perform_arg_mismatch" "test/negative/effect_perform_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "effectful_lambda_to_pure_fn" "test/negative/effectful_lambda_to_pure_fn.weft" "type error: effect not available in caller"
check_rejects "fusion_effectful_map_callback" "test/negative/fusion_effectful_map_callback.weft" "type error: effect not available in caller"
check_rejects "fusion_effectful_filter_callback" "test/negative/fusion_effectful_filter_callback.weft" "type error: effect not available in caller"
check_rejects "fusion_alloc_effect_callback" "test/negative/fusion_alloc_effect_callback.weft" "type error: argument type mismatch"
check_rejects "iter_fold_effectful_callback" "test/negative/iter_fold_effectful_callback.weft" "type error: effect not available in caller"
check_rejects "iter_map_collect_effectful_callback" "test/negative/iter_map_collect_effectful_callback.weft" "type error: effect not available in caller"
check_rejects "iter_map_effectful_callback" "test/negative/iter_map_effectful_callback.weft" "type error: effect not available in caller"
check_rejects "iter_filter_effectful_callback" "test/negative/iter_filter_effectful_callback.weft" "type error: effect not available in caller"
check_rejects "effectful_lambda_to_pure_effect_op" "test/negative/effectful_lambda_to_pure_effect_op.weft" "type error: effect not available in caller"
check_rejects "function_value_effect_unavailable" "test/negative/function_value_effect_unavailable.weft" "type error: effect not available in caller"
check_rejects "function_value_arg_mismatch" "test/negative/function_value_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "function_value_return_mismatch" "test/negative/function_value_return_mismatch.weft" "type error: return type mismatch"
check_rejects "method_call_arity_too_few" "test/negative/method_call_arity_too_few.weft" "type error: arity mismatch"
check_rejects "method_call_arity_too_many" "test/negative/method_call_arity_too_many.weft" "type error: arity mismatch"
check_rejects "method_call_arg_mismatch" "test/negative/method_call_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "method_call_trait_arg_mismatch" "test/negative/method_call_trait_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "method_call_effect_unavailable" "test/negative/method_call_effect_unavailable.weft" "type error: effect not available in caller"
check_rejects "method_call_unknown" "test/negative/method_call_unknown.weft" "type error: unknown method"
check_rejects "method_call_trait_unknown" "test/negative/method_call_trait_unknown.weft" "type error: unknown method"
check_rejects "trait_impl_missing_method" "test/negative/trait_impl_missing_method.weft" "type error: impl missing required method"
check_rejects "trait_impl_arity_mismatch" "test/negative/trait_impl_arity_mismatch.weft" "type error: impl method arity mismatch"
check_rejects "trait_impl_param_mismatch" "test/negative/trait_impl_param_mismatch.weft" "type error: impl method parameter type mismatch"
check_rejects "trait_self_impl_param_mismatch" "test/negative/trait_self_impl_param_mismatch.weft" "type error: impl method parameter type mismatch"
check_rejects "trait_impl_return_mismatch" "test/negative/trait_impl_return_mismatch.weft" "type error: impl method return type mismatch"
check_rejects "trait_impl_effect_mismatch" "test/negative/trait_impl_effect_mismatch.weft" "type error: impl method effect mismatch"
check_rejects "generic_impl_overlap_conflict" "test/negative/generic_impl_overlap_conflict.weft" "type error: conflicting implementations of trait for type"
check_rejects "generic_impl_repeated_overlap_conflict" "test/negative/generic_impl_repeated_overlap_conflict.weft" "type error: conflicting implementations of trait for type"
check_rejects "generic_impl_conditional_bound" "test/negative/generic_impl_conditional_bound.weft" "type error: type does not satisfy trait bound"
check_rejects "generic_impl_target_arity" "test/negative/generic_impl_target_arity.weft" "type error: impl target type argument count mismatch"
check_rejects "generic_impl_unconstrained_parameter" "test/negative/generic_impl_unconstrained_parameter.weft" "type error: impl parameter is not determined by the target type"
check_rejects "generic_impl_repeated_receiver_mismatch" "test/negative/generic_impl_repeated_receiver_mismatch.weft" "type error: unknown method"
check_rejects "generic_inherent_impl_overlap" "test/negative/generic_inherent_impl_overlap.weft" "type error: conflicting inherent implementations for method"
check_rejects "impl_method_type_params_unsupported" "test/negative/impl_method_type_params_unsupported.weft" "type error: method-specific type parameters are not yet supported"
check_rejects "trait_assoc_missing" "test/negative/trait_assoc_missing.weft" "type error: impl missing required associated type"
check_rejects "trait_assoc_duplicate" "test/negative/trait_assoc_duplicate.weft" "type error: duplicate associated type binding"
check_rejects "trait_assoc_extra" "test/negative/trait_assoc_extra.weft" "type error: impl associated type is not declared by trait"
check_rejects "trait_assoc_bound_concrete" "test/negative/trait_assoc_bound_concrete.weft" "type error: associated type does not satisfy trait bound"
check_rejects "trait_assoc_bound_generic" "test/negative/trait_assoc_bound_generic.weft" "type error: associated type does not satisfy trait bound"
check_rejects "trait_assoc_signature_mismatch" "test/negative/trait_assoc_signature_mismatch.weft" "type error: impl method parameter type mismatch"
check_rejects "trait_impl_conflict" "test/negative/trait_impl_conflict.weft" "type error: conflicting implementations of trait for type"
check_rejects "orphan_neither_local" "test/negative/orphan_neither_local.weft" "type error: orphan impl is not allowed — define the trait or target type in this file"
check_rejects "orphan_primitive_foreign_trait" "test/negative/orphan_primitive_foreign_trait.weft" "type error: orphan impl is not allowed — define the trait or target type in this file"
check_rejects "ord_missing_impl" "test/negative/ord_missing_impl.weft" "type error: ordering operands must implement Ord"
check_rejects "ord_operand_mismatch" "test/negative/ord_operand_mismatch.weft" "type error: ordering operand type mismatch"
check_rejects "ord_unbounded_generic" "test/negative/ord_unbounded_generic.weft" "type error: ordering operands must implement Ord"
check_rejects "ord_wrong_signature" "test/negative/ord_wrong_signature.weft" "type error: Ord must define compare(self, Self) -> i64"
check_rejects "ord_effectful_signature" "test/negative/ord_effectful_signature.weft" "type error: Ord must define compare(self, Self) -> i64"
check_rejects "display_missing_impl" "test/negative/display_missing_impl.weft" "type error: type does not satisfy trait bound"
check_rejects "display_wrong_signature" "test/negative/display_wrong_signature.weft" "type error: impl method return type mismatch"
check_rejects "display_effectful_signature" "test/negative/display_effectful_signature.weft" "type error: impl method effect mismatch"
check_rejects "default_missing_impl" "test/negative/default_missing_impl.weft" "type error: type does not satisfy trait bound"
check_rejects "default_impl_return_mismatch" "test/negative/default_impl_return_mismatch.weft" "type error: impl method return type mismatch"
check_rejects "default_impl_effect_mismatch" "test/negative/default_impl_effect_mismatch.weft" "type error: impl method effect mismatch"
check_rejects "associated_function_value_call" "test/negative/associated_function_value_call.weft" "type error: associated function must be called on a type"
check_rejects "associated_function_arity_mismatch" "test/negative/associated_function_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "instance_method_type_call" "test/negative/instance_method_type_call.weft" "type error: instance method must be called on a value"
check_rejects "option_unwrap_or_type_mismatch" "test/negative/option_unwrap_or_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "result_unwrap_or_type_mismatch" "test/negative/result_unwrap_or_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "list_prepend_type_mismatch" "test/negative/list_prepend_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "vector_cross_type_push" "test/negative/vector_cross_type_push.weft" "type error: argument type mismatch"
check_rejects "vector_sort_missing_ord" "test/negative/vector_sort_missing_ord.weft" "type error: type does not satisfy trait bound"
check_rejects "vector_sort_effectful_comparator" "test/negative/vector_sort_effectful_comparator.weft" "type error: argument type mismatch"
check_rejects "vector_filter_effectful_predicate" "test/negative/vector_filter_effectful_predicate.weft" "type error: argument type mismatch"
check_rejects "vector_concat_type_mismatch" "test/negative/vector_concat_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "generic_function_ref_unresolved" "test/negative/generic_function_ref_unresolved.weft" "type error: cannot infer generic function reference"
check_rejects "map_wrong_key_type" "test/negative/map_wrong_key_type.weft" "type error: argument type mismatch"
check_rejects "map_wrong_value_type" "test/negative/map_wrong_value_type.weft" "type error: argument type mismatch"
check_rejects "set_wrong_element_type" "test/negative/set_wrong_element_type.weft" "type error: argument type mismatch"
check_rejects "map_set_handle_confusion" "test/negative/map_set_handle_confusion.weft" "type error: argument type mismatch"
check_rejects "map_sentinel_lookup_removed" "test/negative/map_sentinel_lookup_removed.weft" "type error: arity mismatch"
check_rejects "option_expect_message_type_mismatch" "test/negative/option_expect_message_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "result_expect_message_type_mismatch" "test/negative/result_expect_message_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "assert_eq_type_mismatch" "test/negative/assert_eq_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "list_sentinel_head_removed" "test/negative/list_sentinel_head_removed.weft" "type error: unknown method"
check_rejects "self_outside_method" "test/negative/self_outside_method.weft" "type error: Self is only valid in trait and impl method signatures"
check_rejects "self_in_data_type" "test/negative/self_in_data_type.weft" "type error: Self is only valid in trait and impl method signatures"
check_rejects "drop_impl_missing_method" "test/negative/drop_impl_missing_method.weft" "type error: Drop impl missing concrete drop method"
check_rejects "drop_impl_arity_mismatch" "test/negative/drop_impl_arity_mismatch.weft" "type error: Drop impl method arity mismatch"
check_rejects "drop_impl_param_mismatch" "test/negative/drop_impl_param_mismatch.weft" "type error: Drop impl method parameter type mismatch"
check_rejects "drop_impl_return_mismatch" "test/negative/drop_impl_return_mismatch.weft" "type error: Drop impl method return type mismatch"
check_rejects "let_bound_lambda_effect_mismatch" "test/negative/let_bound_lambda_effect_mismatch.weft" "type error: argument type mismatch"
check_rejects "let_bound_lambda_record_effect_mismatch" "test/negative/let_bound_lambda_record_effect_mismatch.weft" "type error: argument type mismatch"
check_rejects "let_bound_lambda_method_effect_mismatch" "test/negative/let_bound_lambda_method_effect_mismatch.weft" "type error: argument type mismatch"
check_rejects "let_bound_lambda_effect_unavailable" "test/negative/let_bound_lambda_effect_unavailable.weft" "type error: effect not available in caller"
check_rejects "let_bound_lambda_return_mismatch" "test/negative/let_bound_lambda_return_mismatch.weft" "type error: argument type mismatch"
check_rejects "unknown_identifier" "test/negative/unknown_identifier.weft" "type error: unknown identifier"
check_rejects "unknown_function" "test/negative/unknown_function.weft" "type error: unknown function"
check_rejects "unknown_intrinsic_call" "test/negative/unknown_intrinsic_call.weft" "type error: unknown function"
check_rejects "unknown_function_in_import" "test/negative/unknown_function_in_import.weft" "type error: unknown function"
check_rejects "proc_run_requires_effect" "test/negative/proc_run_requires_effect.weft" "type error: effect not available in caller"
check_rejects "env_arg_requires_effect" "test/negative/env_arg_requires_effect.weft" "type error: effect not available in caller"
check_rejects "call_non_function" "test/negative/call_non_function.weft" "type error: called value is not a function"
check_rejects "no_payload_variant_not_function" "test/negative/no_payload_variant_not_function.weft" "type error: called value is not a function"
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
check_rejects "match_non_exhaustive_int" "test/negative/match_non_exhaustive_int.weft" "type error: non-exhaustive match"
check_rejects "match_non_exhaustive_constructor" "test/negative/match_non_exhaustive_constructor.weft" "type error: non-exhaustive match"
check_rejects "match_duplicate_constructor" "test/negative/match_duplicate_constructor.weft" "type error: duplicate match constructor arm"
check_rejects "match_final_guarded" "test/negative/match_final_guarded.weft" "type error: non-exhaustive match"
check_rejects "pattern_literal_str_scrutinee" "test/negative/pattern_literal_str_scrutinee.weft" "type error: literal pattern does not match scrutinee"
check_rejects "pattern_unknown_constructor" "test/negative/pattern_unknown_constructor.weft" "type error: unknown constructor pattern"
check_rejects "pattern_constructor_on_i64" "test/negative/pattern_constructor_on_i64.weft" "type error: constructor pattern does not match scrutinee"
check_rejects "pattern_constructor_wrong_variant" "test/negative/pattern_constructor_wrong_variant.weft" "type error: constructor pattern does not match scrutinee"
check_rejects "pattern_constructor_arity_too_few" "test/negative/pattern_constructor_arity_too_few.weft" "type error: constructor pattern arity mismatch"
check_rejects "pattern_constructor_arity_too_many" "test/negative/pattern_constructor_arity_too_many.weft" "type error: constructor pattern arity mismatch"
check_rejects "if_condition_not_bool" "test/negative/if_condition_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "while_condition_not_bool" "test/negative/while_condition_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "for_iter_non_list" "test/negative/for_iter_non_list.weft" "type error: for iterator requires a Cons/Nil list"
check_rejects "not_operand_not_bool" "test/negative/not_operand_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "logical_operand_not_bool" "test/negative/logical_operand_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "match_guard_not_bool" "test/negative/match_guard_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "operator_equality_mismatch" "test/negative/operator_equality_mismatch.weft" "type error: equality operand mismatch"
check_rejects "operator_relational_str" "test/negative/operator_relational_str.weft" "type error: ordering operands must implement Ord"
check_rejects "operator_bitwise_bool" "test/negative/operator_bitwise_bool.weft" "type error: bitwise operand is not i64"
check_rejects "operator_shift_bool" "test/negative/operator_shift_bool.weft" "type error: bitwise operand is not i64"
check_rejects "f64_i64_arithmetic_mismatch" "test/negative/f64_i64_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "f64_i64_comparison_mismatch" "test/negative/f64_i64_comparison_mismatch.weft" "type error: comparison operand type mismatch"
check_rejects "f64_bitwise" "test/negative/f64_bitwise.weft" "type error: bitwise operand is not i64"
check_rejects "f64_modulo" "test/negative/f64_modulo.weft" "type error: arithmetic operand is not i64"
check_rejects "f32_f64_arithmetic_mismatch" "test/negative/f32_f64_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "f32_i64_arithmetic_mismatch" "test/negative/f32_i64_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "f32_f64_comparison_mismatch" "test/negative/f32_f64_comparison_mismatch.weft" "type error: comparison operand type mismatch"
check_rejects "f32_f64_assignment_mismatch" "test/negative/f32_f64_assignment_mismatch.weft" "type error: value does not match let type annotation"
check_rejects "f32_bitwise" "test/negative/f32_bitwise.weft" "type error: bitwise operand is not i64"
check_rejects "f32_call_f64_arg_mismatch" "test/negative/f32_call_f64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "i32_i64_arithmetic_mismatch" "test/negative/i32_i64_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "i32_literal_out_of_range" "test/negative/i32_literal_out_of_range.weft" "type error: value does not match let type annotation"
check_rejects "i64_positive_literal_out_of_range" "test/negative/i64_positive_literal_out_of_range.weft" "type error: value does not match let type annotation"
check_rejects "untyped_integer_literal_out_of_range" "test/negative/untyped_integer_literal_out_of_range.weft" "type error: integer literal out of range"
check_rejects "i32_i64_assignment_mismatch" "test/negative/i32_i64_assignment_mismatch.weft" "type error: value does not match let type annotation"
check_rejects "i32_call_i64_arg_mismatch" "test/negative/i32_call_i64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "i8_literal_out_of_range" "test/negative/i8_literal_out_of_range.weft" "type error: value does not match let type annotation"
check_rejects "u8_negative_literal" "test/negative/u8_negative_literal.weft" "type error: value does not match let type annotation"
check_rejects "u64_literal_out_of_range" "test/negative/u64_literal_out_of_range.weft" "type error: value does not match let type annotation"
check_rejects "u64_return_literal_out_of_range" "test/negative/u64_return_literal_out_of_range.weft" "type error: return type mismatch"
check_rejects "u64_negative_literal" "test/negative/u64_negative_literal.weft" "type error: value does not match let type annotation"
check_rejects "u64_pattern_literal_out_of_range" "test/negative/u64_pattern_literal_out_of_range.weft" "type error: literal pattern does not match scrutinee"
check_rejects "u8_i8_arithmetic_mismatch" "test/negative/u8_i8_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "u32_i32_comparison_mismatch" "test/negative/u32_i32_comparison_mismatch.weft" "type error: comparison operand type mismatch"
check_rejects "usize_i64_assignment_mismatch" "test/negative/usize_i64_assignment_mismatch.weft" "type error: value does not match let type annotation"
check_rejects "u8_call_i64_arg_mismatch" "test/negative/u8_call_i64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_i64_to_f64_arg_mismatch" "test/negative/num_i64_to_f64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_i64_to_f64_arg_mismatch" "test/negative/intrinsic_i64_to_f64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_u32_to_f64_arg_mismatch" "test/negative/num_u32_to_f64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_u64_to_f64_arg_mismatch" "test/negative/intrinsic_u64_to_f64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_f64_to_i64_exact_arg_mismatch" "test/negative/num_f64_to_i64_exact_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_f64_to_i64_arg_mismatch" "test/negative/intrinsic_f64_to_i64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_f32_to_f64_arg_mismatch" "test/negative/num_f32_to_f64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_f64_to_f32_round_arg_mismatch" "test/negative/num_f64_to_f32_round_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_i32_to_f32_round_arg_mismatch" "test/negative/num_i32_to_f32_round_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_f32_to_f64_arg_mismatch" "test/negative/intrinsic_f32_to_f64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_f64_to_f32_arg_mismatch" "test/negative/intrinsic_f64_to_f32_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_i16_to_f32_arg_mismatch" "test/negative/intrinsic_i16_to_f32_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "math_sqrt_f64_arg_mismatch" "test/negative/math_sqrt_f64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "math_sqrt_f32_arg_mismatch" "test/negative/math_sqrt_f32_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_f64_sqrt_arg_mismatch" "test/negative/intrinsic_f64_sqrt_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_f32_sqrt_arg_mismatch" "test/negative/intrinsic_f32_sqrt_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_i64_to_i8_checked_arg_mismatch" "test/negative/num_i64_to_i8_checked_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_int_cast_value_or_default_mismatch" "test/negative/num_int_cast_value_or_default_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_i64_to_i8_arg_mismatch" "test/negative/intrinsic_i64_to_i8_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "intrinsic_u16_to_u64_arg_mismatch" "test/negative/intrinsic_u16_to_u64_arg_mismatch.weft" "type error: argument type mismatch"
check_rejects "num_trait_bool_not_numeric" "test/negative/num_trait_bool_not_numeric.weft" "type error: type does not satisfy trait bound"
check_rejects "num_trait_str_not_integer" "test/negative/num_trait_str_not_integer.weft" "type error: type does not satisfy trait bound"
check_rejects "num_trait_float_not_integer" "test/negative/num_trait_float_not_integer.weft" "type error: type does not satisfy trait bound"
check_rejects "num_trait_unsigned_not_signed" "test/negative/num_trait_unsigned_not_signed.weft" "type error: type does not satisfy trait bound"
check_rejects "num_trait_signed_not_unsigned" "test/negative/num_trait_signed_not_unsigned.weft" "type error: type does not satisfy trait bound"
check_rejects "unhandled_effect_in_if_condition" "test/negative/unhandled_effect_in_if_condition.weft" "type error: effect not available in caller"
check_rejects "unhandled_effect_in_match_guard" "test/negative/unhandled_effect_in_match_guard.weft" "type error: effect not available in caller"
check_rejects "assignment_unknown_target" "test/negative/assignment_unknown_target.weft" "type error: unknown identifier"
check_rejects "assignment_i64_str_mismatch" "test/negative/assignment_i64_str_mismatch.weft" "type error: assignment type mismatch"
check_rejects "assignment_str_i64_mismatch" "test/negative/assignment_str_i64_mismatch.weft" "type error: assignment type mismatch"
check_rejects "assignment_bool_i64_mismatch" "test/negative/assignment_bool_i64_mismatch.weft" "type error: assignment type mismatch"
check_rejects "assignment_immutable_let" "test/negative/assignment_immutable_let.weft" "type error: cannot assign to immutable binding"
check_rejects "assignment_immutable_typed_let" "test/negative/assignment_immutable_typed_let.weft" "type error: cannot assign to immutable binding"
check_rejects "assignment_param_immutable" "test/negative/assignment_param_immutable.weft" "type error: cannot assign to immutable binding"
check_rejects "assignment_pattern_binding_immutable" "test/negative/assignment_pattern_binding_immutable.weft" "type error: cannot assign to immutable binding"
check_rejects "assignment_for_range_index" "test/negative/assignment_for_range_index.weft" "type error: cannot assign to immutable binding"
check_rejects "pointer_address_requires_unsafe" "test/negative/pointer_address_requires_unsafe.weft" "type error: effect not available in caller"
check_rejects "pointer_deref_requires_unsafe" "test/negative/pointer_deref_requires_unsafe.weft" "type error: effect not available in caller"
check_rejects "pointer_assignment_requires_unsafe" "test/negative/pointer_assignment_requires_unsafe.weft" "type error: effect not available in caller"
check_rejects "imported_pointer_address_requires_trusted" "test/negative/imported_pointer_address_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "imported_pointer_deref_requires_trusted" "test/negative/imported_pointer_deref_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "imported_pointer_store_requires_trusted" "test/negative/imported_pointer_store_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "pointer_address_of_literal" "test/negative/pointer_address_of_literal.weft" "type error: address-of target must be a binding"
check_rejects "pointer_deref_non_pointer" "test/negative/pointer_deref_non_pointer.weft" "type error: dereference of non-pointer"
check_rejects "pointer_mut_address_of_immutable" "test/negative/pointer_mut_address_of_immutable.weft" "type error: cannot take mutable pointer to immutable binding"
check_rejects "pointer_value_to_param" "test/negative/pointer_value_to_param.weft" "type error: argument type mismatch"
check_rejects "pointer_assignment_immutable" "test/negative/pointer_assignment_immutable.weft" "type error: cannot write through immutable pointer"
check_rejects "pointer_assignment_type_mismatch" "test/negative/pointer_assignment_type_mismatch.weft" "type error: pointer assignment type mismatch"
check_rejects "pointer_assignment_non_pointer" "test/negative/pointer_assignment_non_pointer.weft" "type error: dereference of non-pointer"
check_rejects "rc_bind_non_rc" "test/negative/rc_bind_non_rc.weft" "type error: value does not match let type annotation"
check_rejects "arc_public_param" "test/negative/arc_public_param.weft" "type error: arc is not public syntax"
check_rejects "arc_public_type_field" "test/negative/arc_public_type_field.weft" "type error: arc is not public syntax"
check_rejects "arc_public_let_annotation" "test/negative/arc_public_let_annotation.weft" "type error: arc is not public syntax"
check_rejects "arc_public_generic_arg" "test/negative/arc_public_generic_arg.weft" "type error: arc is not public syntax"
check_rejects "arc_public_vector_field" "test/negative/arc_public_vector_field.weft" "type error: arc is not public syntax"
check_rejects "unique_param_used_twice" "test/negative/unique_param_used_twice.weft" "type error: unique value used more than once"
check_rejects "unique_let_used_twice" "test/negative/unique_let_used_twice.weft" "type error: unique value used more than once"
check_rejects "unique_closure_capture" "test/negative/unique_closure_capture.weft" "type error: unique value cannot be captured by closure"
check_rejects "unique_contextual_lambda_param_used_twice" "test/negative/unique_contextual_lambda_param_used_twice.weft" "type error: unique value used more than once"
check_rejects "unique_par_spawn_use_after_move" "test/negative/unique_par_spawn_use_after_move.weft" "type error: unique value used more than once"
check_rejects "owned_param_used_twice" "test/negative/owned_param_used_twice.weft" "type error: owned value used more than once"
check_rejects "owned_let_used_twice" "test/negative/owned_let_used_twice.weft" "type error: owned value used more than once"
check_rejects "owned_closure_capture" "test/negative/owned_closure_capture.weft" "type error: owned value cannot be captured by closure"
check_rejects "owned_plain_i64_requires_drop" "test/negative/owned_plain_i64_requires_drop.weft" "type error: owned type requires Drop resource conformance"
check_rejects "owned_inherent_drop_requires_trait" "test/negative/owned_inherent_drop_requires_trait.weft" "type error: owned type requires Drop resource conformance"
check_rejects "owned_drop_effect_unavailable" "test/negative/owned_drop_effect_unavailable.weft" "type error: owned Drop effect not available in caller"
check_rejects "owned_file_drop_effect_unavailable" "test/negative/owned_file_drop_effect_unavailable.weft" "type error: owned Drop effect not available in caller"
check_rejects "owned_record_field" "test/negative/owned_record_field.weft" "type error: move-only type cannot be nested in copyable storage"
check_rejects "unique_record_field" "test/negative/unique_record_field.weft" "type error: move-only type cannot be nested in copyable storage"
check_rejects "owned_variant_payload" "test/negative/owned_variant_payload.weft" "type error: move-only type cannot be nested in copyable storage"
check_rejects "owned_vector_field" "test/negative/owned_vector_field.weft" "type error: move-only type cannot be nested in copyable storage"
check_rejects "owned_generic_param" "test/negative/owned_generic_param.weft" "type error: move-only type cannot be nested in copyable storage"
check_rejects "ownership_cycle_vector_self" "test/negative/ownership_cycle_vector_self.weft" "type error: strong ownership cycle requires weak or id edge"
check_rejects "ownership_cycle_vector_mutual" "test/negative/ownership_cycle_vector_mutual.weft" "type error: strong ownership cycle requires weak or id edge"
check_rejects "ownership_cycle_vector_generic_box" "test/negative/ownership_cycle_vector_generic_box.weft" "type error: strong ownership cycle requires weak or id edge"
check_rejects "ownership_cycle_sorted_map_self" "test/negative/ownership_cycle_sorted_map_self.weft" "type error: strong ownership cycle requires weak or id edge"
check_rejects "ownership_cycle_sorted_set_self" "test/negative/ownership_cycle_sorted_set_self.weft" "type error: strong ownership cycle requires weak or id edge"
check_rejects "ownership_cycle_vector_closure" "test/negative/ownership_cycle_vector_closure.weft" "type error: closure capture cycle requires weak or id edge"
check_rejects "ownership_cycle_vector_closure_box" "test/negative/ownership_cycle_vector_closure_box.weft" "type error: closure capture cycle requires weak or id edge"
check_rejects "ownership_cycle_vector_continuation" "test/negative/ownership_cycle_vector_continuation.weft" "type error: closure capture cycle requires weak or id edge"
check_rejects "weak_ref_unmanaged" "test/negative/weak_ref_unmanaged.weft" "type error: weak_ref requires managed value"
check_rejects "weak_load_nonweak" "test/negative/weak_load_nonweak.weft" "type error: weak_load requires weak managed reference"
check_rejects "weak_ref_arity" "test/negative/weak_ref_arity.weft" "type error: arity mismatch"
check_rejects "weak_load_nullable_required" "test/negative/weak_load_nullable_required.weft" "type error: value does not match let type annotation"
check_rejects "region_scoped_return_alloc" "test/negative/region_scoped_return_alloc.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_return_bound_alloc" "test/negative/region_scoped_return_bound_alloc.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_capture_alloc" "test/negative/region_scoped_capture_alloc.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_unknown_call_arg" "test/negative/region_scoped_unknown_call_arg.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_handler_body_result" "test/negative/region_scoped_handler_body_result.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_handler_resume_region" "test/negative/region_scoped_handler_resume_region.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_store_to_outer_slot" "test/negative/region_scoped_store_to_outer_slot.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_store_sized_to_outer_slot" "test/negative/region_scoped_store_sized_to_outer_slot.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_value_return_alloc" "test/negative/region_scoped_value_return_alloc.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_promote_size_region" "test/negative/region_scoped_promote_size_region.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_promote_align_region" "test/negative/region_scoped_promote_align_region.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_deferred_continuation_outer_region" "test/negative/region_scoped_deferred_continuation_outer_region.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_deferred_continuation_body_region" "test/negative/region_scoped_deferred_continuation_body_region.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_deferred_continuation_function_boundary" "test/negative/region_scoped_deferred_continuation_function_boundary.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_deferred_continuation_store_outer" "test/negative/region_scoped_deferred_continuation_store_outer.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_par_spawn_lambda_capture" "test/negative/region_scoped_par_spawn_lambda_capture.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_par_spawn_region_arg" "test/negative/region_scoped_par_spawn_region_arg.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_par_spawn_branch_lambda_capture" "test/negative/region_scoped_par_spawn_branch_lambda_capture.weft" "type error: region value cannot escape scoped arena"
check_rejects "lambda_capture_mut_binding" "test/negative/lambda_capture_mut_binding.weft" "type error: cannot capture mut binding"
check_rejects "lambda_capture_mut_assignment" "test/negative/lambda_capture_mut_assignment.weft" "type error: cannot capture mut binding"
check_rejects "return_branch_type_mismatch" "test/negative/return_branch_type_mismatch.weft" "type error: return type mismatch"
check_rejects "return_str_i64_mismatch" "test/negative/return_str_i64_mismatch.weft" "type error: return type mismatch"
check_rejects "unhandled_effect_in_return" "test/negative/unhandled_effect_in_return.weft" "type error: effect not available in caller"
check_rejects "unhandled_effect_in_break" "test/negative/unhandled_effect_in_break.weft" "type error: effect not available in caller"
check_rejects "contextual_lambda_return_stmt_mismatch" "test/negative/contextual_lambda_return_stmt_mismatch.weft" "type error: return type mismatch"
check_rejects "let_bound_lambda_return_stmt_mismatch" "test/negative/let_bound_lambda_return_stmt_mismatch.weft" "type error: return type mismatch"
check_rejects "call_arity_too_few" "test/negative/call_arity_too_few.weft" "type error: arity mismatch"
check_rejects "call_arity_too_many" "test/negative/call_arity_too_many.weft" "type error: arity mismatch"
check_rejects "generic_call_arity_mismatch" "test/negative/generic_call_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "generic_call_non_generic_function" "test/negative/generic_call_non_generic_function.weft" "type error: generic call target is not generic"
check_rejects "generic_call_function_value" "test/negative/generic_call_function_value.weft" "type error: generic call target is not generic"
check_rejects "generic_call_non_generic_constructor" "test/negative/generic_call_non_generic_constructor.weft" "type error: generic call target is not generic"
check_rejects "function_value_arity_mismatch" "test/negative/function_value_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "effect_perform_arity_too_few" "test/negative/effect_perform_arity_too_few.weft" "type error: arity mismatch"
check_rejects "effect_perform_arity_too_many" "test/negative/effect_perform_arity_too_many.weft" "type error: arity mismatch"
check_rejects "deferred_with_k_non_deferred" "test/negative/deferred_with_k_non_deferred.weft" "type error: handler continuation requires deferred effect operation"
check_rejects "deferred_k_capture_lambda" "test/negative/deferred_k_capture_lambda.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_escape_value" "test/negative/deferred_k_escape_value.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_multiple_use" "test/negative/deferred_k_multiple_use.weft" "type error: continuation used more than once"
check_rejects "deferred_k_alias_multiple_use" "test/negative/deferred_k_alias_multiple_use.weft" "type error: continuation used more than once"
check_rejects "deferred_k_capture_lambda_body_multiple_use" "test/negative/deferred_k_capture_lambda_body_multiple_use.weft" "type error: continuation used more than once"
check_rejects "deferred_k_capture_lambda_multiple_use" "test/negative/deferred_k_capture_lambda_multiple_use.weft" "type error: continuation used more than once"
check_rejects "deferred_k_alias_capture_lambda" "test/negative/deferred_k_alias_capture_lambda.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_alias_pass_arg" "test/negative/deferred_k_alias_pass_arg.weft" "type error: argument type mismatch"
check_rejects "deferred_k_non_tail" "test/negative/deferred_k_non_tail.weft" "type error: continuation call must be tail position"
check_rejects "deferred_k_loop_non_tail" "test/negative/deferred_k_conditional_non_tail.weft" "type error: continuation call must be tail position"
check_rejects "deferred_k_arity" "test/negative/deferred_k_arity.weft" "type error: arity mismatch"
check_rejects "deferred_k_helper_multiple_use" "test/negative/deferred_k_helper_multiple_use.weft" "type error: continuation used more than once"
check_rejects "continuation_param_multiple_use" "test/negative/continuation_param_multiple_use.weft" "type error: continuation used more than once"
check_rejects "continuation_param_plain_function" "test/negative/continuation_param_plain_function.weft" "type error: argument type mismatch"
check_rejects "continuation_param_return_any" "test/negative/continuation_param_return_any.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_direct_resume" "test/negative/deferred_k_direct_resume.weft" "type error: use continuation binding instead of resume"
check_rejects "deferred_k_intrinsic_store" "test/negative/deferred_k_intrinsic_store.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_record_store" "test/negative/deferred_k_record_store.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_variant_store" "test/negative/deferred_k_variant_store.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_generic_list_store" "test/negative/deferred_k_generic_list_store.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_generic_identity" "test/negative/deferred_k_generic_identity.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_returned_alias_non_tail" "test/negative/deferred_k_returned_alias_non_tail.weft" "type error: continuation call must be tail position"
check_rejects "deferred_k_returned_alias_record_store" "test/negative/deferred_k_returned_alias_record_store.weft" "type error: continuation cannot escape"
check_rejects "deferred_k_returned_alias_multiple_use" "test/negative/deferred_k_returned_alias_multiple_use.weft" "type error: continuation used more than once"
check_rejects "stored_continuation_store_twice" "test/negative/stored_continuation_store_twice.weft" "type error: continuation used more than once"
check_rejects "stored_continuation_use_after_store" "test/negative/stored_continuation_use_after_store.weft" "type error: continuation used more than once"
check_rejects "handler_clause_unknown_op" "test/negative/handler_clause_unknown_op.weft" "type error: unknown effect operation"
check_rejects "handler_clause_effect_mismatch" "test/negative/handler_clause_effect_mismatch.weft" "type error: handler clause effect mismatch"
check_rejects "handler_clause_arity_too_few" "test/negative/handler_clause_arity_too_few.weft" "type error: arity mismatch"
check_rejects "handler_clause_arity_too_many" "test/negative/handler_clause_arity_too_many.weft" "type error: arity mismatch"
check_rejects "handler_clause_param_type_mismatch" "test/negative/handler_clause_param_type_mismatch.weft" "type error: argument type mismatch"
check_rejects "handler_clause_resume_type_mismatch" "test/negative/handler_clause_resume_type_mismatch.weft" "type error: resume type mismatch"
check_rejects "handler_clause_return_type_mismatch" "test/negative/handler_clause_return_type_mismatch.weft" "type error: return type mismatch"
check_rejects "handler_clause_resume_capture_lambda" "test/negative/handler_clause_resume_capture_lambda.weft" "type error: cannot capture resume"
check_rejects "handler_clause_resume_capture_nested_lambda" "test/negative/handler_clause_resume_capture_nested_lambda.weft" "type error: cannot capture resume"
check_rejects "handler_clause_duplicate" "test/negative/handler_clause_duplicate.weft" "type error: duplicate handler clause"
check_rejects "handler_clause_missing_direct" "test/negative/handler_clause_missing_direct.weft" "type error: missing handler clause"
check_rejects "handler_clause_missing_branch" "test/negative/handler_clause_missing_branch.weft" "type error: missing handler clause"
check_rejects "resume_outside_handler" "test/negative/resume_outside_handler.weft" "type error: resume outside handler clause"
check_rejects "resume_outside_handler_lambda" "test/negative/resume_outside_handler_lambda.weft" "type error: resume outside handler clause"
check_rejects "generic_type_payload_mismatch" "test/negative/generic_type_payload_mismatch.weft" "type error: argument type mismatch"
check_rejects "generic_type_return_mismatch" "test/negative/generic_type_return_mismatch.weft" "type error: value does not match let type annotation"
check_rejects "generic_type_constructor_arity" "test/negative/generic_type_constructor_arity.weft" "type error: arity mismatch"
check_rejects "generic_type_arg_count" "test/negative/generic_type_arg_count.weft" "type error: wrong number of type arguments"
check_rejects "generic_type_pattern_payload_mismatch" "test/negative/generic_type_pattern_payload_mismatch.weft" "type error: return type mismatch"
check_rejects "narrowing_unguarded_nilable_use" "test/negative/narrowing_unguarded_nilable_use.weft" "type error: argument type mismatch"
check_rejects "narrowing_mut_guard_not_narrowed" "test/negative/narrowing_mut_guard_not_narrowed.weft" "type error: argument type mismatch"
check_rejects "generic_ctor_no_context" "test/negative/generic_ctor_no_context.weft" "type error: return type mismatch"
check_rejects "generic_ctor_annotation_mismatch" "test/negative/generic_ctor_annotation_mismatch.weft" "type error: value does not match let type annotation"
check_rejects "generic_ctor_conflicting_args" "test/negative/generic_ctor_conflicting_args.weft" "type error: argument type mismatch"
check_rejects "qualified_ctor_call" "test/negative/qualified_ctor_call.weft" "type error: qualified constructor syntax is not supported"
check_rejects "qualified_ctor_nullary" "test/negative/qualified_ctor_nullary.weft" "type error: qualified constructor syntax is not supported"
check_rejects "interp_display_missing_import" "test/negative/interp_display_missing_import.weft" "add use \"stdlib/display.weft\""
check_rejects "typed_match_untagged_union" "test/negative/typed_match_untagged_union.weft" "type error: typed match arm needs a runtime-discriminable union"
check_rejects "typed_match_non_exhaustive" "test/negative/typed_match_non_exhaustive.weft" "type error: non-exhaustive match"
check_rejects "typed_match_foreign_annotation" "test/negative/typed_match_foreign_annotation.weft" "type error: typed match arm annotation is not part of the scrutinee type"
check_rejects "typed_match_nil_never" "test/negative/typed_match_nil_never.weft" "type error: nil match arm on a scrutinee that is never nil"
check_rejects "structural_record_type_unsupported" "test/negative/structural_record_type_unsupported.weft" "type error: structural record types are not implemented yet"
check_rejects "tuple_type_unsupported" "test/negative/tuple_type_unsupported.weft" "type error: tuple types are not implemented yet"
check_rejects "array_type_unsupported" "test/negative/array_type_unsupported.weft" "type error: array and slice types are not implemented yet"
check_rejects "array_literal_unsupported" "test/negative/array_literal_unsupported.weft" "error: array/slice syntax is not implemented yet"
check_rejects "effect_type_args_arity" "test/negative/effect_type_args_arity.weft" "type error: effect type argument count mismatch"
check_rejects "effect_generic_bare_use" "test/negative/effect_generic_bare_use.weft" "type error: effect type argument count mismatch"
check_rejects "effect_type_args_wrong_count" "test/negative/effect_type_args_wrong_count.weft" "type error: effect type argument count mismatch"
check_rejects "effect_instantiation_mismatch" "test/negative/effect_instantiation_mismatch.weft" "type error: effect not available in caller"
check_rejects "effect_duplicate_head_instantiations" "test/negative/effect_duplicate_head_instantiations.weft" "type error: duplicate effect heads in one signature are not yet supported"
check_rejects "effect_perform_arg_instantiation_mismatch" "test/negative/effect_perform_arg_instantiation_mismatch.weft" "type error: argument type mismatch"
check_rejects "effect_resume_instantiation_mismatch" "test/negative/effect_resume_instantiation_mismatch.weft" "type error: resume type mismatch"
check_rejects "return_clause_deferred" "test/negative/return_clause_deferred.weft" "type error: return clause with deferred clauses is not yet supported"
check_rejects "handler_two_return_clauses" "test/negative/handler_two_return_clauses.weft" "error: at most one return clause per handler"
check_rejects "trait_complement_surface" "test/negative/trait_complement_surface.weft" "type error: trait complement is not a surface type"
check_rejects "import_cycle" "test/negative/import_cycle.weft" "error: circular import"
check_rejects "call_site_label_unsupported" "test/negative/call_site_label_unsupported.weft" "error: call-site argument labels are not supported yet"
check_rejects "rigid_tail_concrete_perform" "test/negative/rigid_tail_concrete_perform.weft" "type error: effect not available in caller"
check_rejects "rigid_tail_concrete_call" "test/negative/rigid_tail_concrete_call.weft" "type error: effect not available in caller"

ls "$JOBS_DIR"/job_???? | xargs -n1 -P "$WEFT_TEST_JOBS" bash "$0" __worker || true

ji=1
while [ "$ji" -le "$JOB_N" ]; do
  jf=$(printf '%s/job_%04d' "$JOBS_DIR" "$ji")
  if [ -f "$jf.meta" ] && [ "$(cat "$jf.meta")" = "pass" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    if [ -f "$jf.err" ]; then
      ERRORS="$ERRORS\n$(cat "$jf.err")"
    else
      ERRORS="$ERRORS\n  $(sed -n 1p "$jf"): worker produced no result"
    fi
  fi
  ji=$((ji+1))
done
rm -rf "$JOBS_DIR"

echo ""
echo "=== Negative Summary ==="
echo "$PASS passed, $FAIL failed"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
