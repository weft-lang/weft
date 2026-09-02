#!/bin/bash
# Negative type-checking tests. These assert diagnostics for programs that
# should be rejected by the checker even though code emission is still lenient.
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
WEFT_TEST_RUNAWAY_RSS_LIMIT_KB=${WEFT_TEST_RUNAWAY_RSS_LIMIT_KB:-24000000}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-$WEFT_TEST_RUNAWAY_RSS_LIMIT_KB}
WEFT_TEST_JOBS=${WEFT_TEST_JOBS:-$(default_test_jobs)}
PASS=0
FAIL=0
ERRORS=""
NAMES=()
FILES=()
PATTERNS=()
EXPECTED_ERRORS=()
OUTPUTS=()

export WEFT
export WEFT_TEST_COMPILE_TIMEOUT
export WEFT_TEST_COMPILE_RSS_LIMIT_KB

CENSUS_ONLY=0
if [ "${1:-}" = "__census" ]; then
  CENSUS_ONLY=1
fi

if [ "$CENSUS_ONLY" -eq 0 ]; then
  echo "=== Negative Test Suite ==="
  echo ""
fi
JOB_N=0

# Register only. One public multi-root project check below owns every source,
# runs bounded root workers, and replays diagnostics in this exact order.
check_rejects() {
  if [ "$CENSUS_ONLY" -eq 1 ]; then
    JOB_N=$((JOB_N+1))
    return
  fi
  NAMES[$JOB_N]="$1"
  FILES[$JOB_N]="$2"
  PATTERNS[$JOB_N]="$3"
  EXPECTED_ERRORS[$JOB_N]="${4:-}"
  JOB_N=$((JOB_N+1))
}

check_rejects "par_map_effectful" "test/negative/par_map_effectful.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> i64`, found `(i64) -[Log]> i64`'
check_rejects "deep_release_mask_overflow_record" "test/negative/deep_release_mask_overflow_record.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "deep_release_mask_overflow_variant_closure" "test/negative/deep_release_mask_overflow_variant_closure.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "deep_release_mask_overflow_variant_array" "test/negative/deep_release_mask_overflow_variant_array.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "deep_release_mask_overflow_weak" "test/negative/deep_release_mask_overflow_weak.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "deep_release_mask_overflow_generic" "test/negative/deep_release_mask_overflow_generic.weft" "type error: aggregate field may require release beyond 16-word mask"
check_rejects "par_map_scoped_effectful" "test/negative/par_map_scoped_effectful.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> i64`, found `(i64) -[Log]> i64`'
check_rejects "par_pool_submit_effectful" "test/negative/par_pool_submit_effectful.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> i64`, found `(i64) -[Log]> i64`'
check_rejects "par_prepared_submit_public" "test/negative/par_prepared_submit_public.weft" "type error: prepared Par submission is compiler-internal"
check_rejects "generic_par_task_double_await" "test/negative/generic_par_task_double_await.weft" "type error: unique value used more than once"
check_rejects "generic_par_task_non_sendable_result" "test/negative/generic_par_task_non_sendable_result.weft" 'error[E1004]: type `Vector<i64>` does not implement `Sendable`'
check_rejects "generic_par_task_non_sendable_capture" "test/negative/generic_par_task_non_sendable_capture.weft" "type error: closure capture is not Sendable across scoped Par"
check_rejects "generic_par_task_type_mismatch" "test/negative/generic_par_task_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `unique ParTask<str>`, found `unique ParTask<i64>`'
check_rejects "generic_par_task_forged" "test/negative/generic_par_task_forged.weft" "type error: ParTask is a sealed runtime token and cannot be constructed"
check_rejects "spawn_requires_effect" "test/negative/spawn_requires_effect.weft" 'error[E2001]: effect `Spawn` is not available in this context'
check_rejects "spawn_child_effect_requires_contract" "test/negative/spawn_child_effect_requires_contract.weft" 'error[E2001]: effect `SpawnChildNoise` is not available in this context'
check_rejects "spawn_non_sendable_result" "test/negative/spawn_non_sendable_result.weft" 'error[E1004]: type `Vector<i64>` does not implement `Sendable`'
check_rejects "spawn_non_sendable_capture" "test/negative/spawn_non_sendable_capture.weft" "type error: task closure is not Sendable across structured Spawn"
check_rejects "spawn_task_scope_escape" "test/negative/spawn_task_scope_escape.weft" "type error: SpawnTask cannot escape its structured Spawn scope"
check_rejects "spawn_task_event_loop_scope_escape" "test/negative/spawn_task_event_loop_scope_escape.weft" "type error: SpawnTask cannot escape its structured Spawn scope"
check_rejects "spawn_task_channel_scope_escape" "test/negative/spawn_task_channel_scope_escape.weft" "type error: SpawnTask cannot escape its structured Spawn scope"
check_rejects "spawn_task_shutdown_scope_escape" "test/negative/spawn_task_shutdown_scope_escape.weft" "type error: SpawnTask cannot escape its structured Spawn scope"
check_rejects "spawn_task_channel_shutdown_scope_escape" "test/negative/spawn_task_channel_shutdown_scope_escape.weft" "type error: SpawnTask cannot escape its structured Spawn scope"
check_rejects "channel_non_sendable_element" "test/negative/channel_non_sendable_element.weft" 'does not implement `Sendable`'
check_rejects "channel_non_sendable_signature" "test/negative/channel_non_sendable_signature.weft" 'does not implement `Sendable`' 1
check_rejects "channel_non_sendable_handler" "test/negative/channel_non_sendable_handler.weft" 'does not implement `Sendable`' 1
check_rejects "spawn_task_double_join" "test/negative/spawn_task_double_join.weft" "type error: unique value used more than once"
check_rejects "spawn_task_constructor_private" "test/negative/spawn_task_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "cancellation_request_requires_effect" "test/negative/cancellation_request_requires_effect.weft" 'error[E2001]: effect `Cancellation` is not available in this context'
check_rejects "cancellation_checkpoint_requires_effect" "test/negative/cancellation_checkpoint_requires_effect.weft" 'error[E2001]: effects `Cancellation, Fail<cancellation.CancellationReason>` are not available in this context'
check_rejects "cancellation_deadline_requires_time" "test/negative/cancellation_deadline_requires_time.weft" 'error[E2001]: effect `Time` is not available in this context'
check_rejects "generator_start_non_literal_producer" "test/negative/generator_start_non_literal_producer.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_start_function_with_arg" "test/negative/generator_start_function_with_arg.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_start_mutable_closure_producer" "test/negative/generator_start_mutable_closure_producer.weft" "type error: generator producer must be literal zero-arg lambda, known zero-arg function, or known zero-arg closure"
check_rejects "generator_start_return_type_mismatch" "test/negative/generator_start_return_type_mismatch.weft" 'error[E1002]: lambda return value type mismatch: expected `i64`, found `str`'
check_rejects "generator_yield_unhandled" "test/negative/generator_yield_unhandled.weft" "error[E2001]:"
check_rejects "unhandled_effect_perform" "test/negative/unhandled_effect_perform.weft" 'error[E2001]: effect `State` is not available in this context'
check_rejects "source_acquire_requires_effect" "test/negative/source_acquire_requires_effect.weft" 'error[E2001]: effect `SourceAcquire` is not available in this context'
check_rejects "secure_random_effect_unavailable" "test/negative/secure_random_effect_unavailable.weft" 'error[E2001]: effect `SecureRandom` is not available in this context'
check_rejects "secure_random_prefixed_function_retired" "test/negative/secure_random_prefixed_function_retired.weft" "error[E4002]: unknown module member 'secure_random_bytes' in import" 1
check_rejects "secure_random_wrapper_retired" "test/negative/secure_random_wrapper_retired.weft" "error[E4002]: unknown module member 'secure_random_with_deterministic' in import" 1
check_rejects "secure_random_platform_wrapper_retired" "test/negative/secure_random_platform_wrapper_retired.weft" "error[E4002]: unknown module member 'runtime_platform_secure_random' in import" 1
check_rejects "secure_random_raw_backend_private" "test/negative/secure_random_raw_backend_private.weft" "module member 'runtime_secure_random_fill_raw' is not visible in this import" 1
check_rejects "tls_client_open_requires_authority" "test/negative/tls_client_open_requires_authority.weft" 'error[E2001]: effects `SecureRandom, Time` are not available in this context'
check_rejects "tls_server_open_requires_authority" "test/negative/tls_server_open_requires_authority.weft" 'error[E2001]: effect `SecureRandom` is not available in this context'
check_rejects "http_client_cannot_listen" "test/negative/http_client_cannot_listen.weft" 'error[E2001]: effect `HttpServer` is not available in this context'
check_rejects "http_server_cannot_connect" "test/negative/http_server_cannot_connect.weft" 'error[E2001]: effect `HttpClient<TlsStream>` is not available in this context'
check_rejects "http_server_cannot_reuse_client_connection" "test/negative/http_server_cannot_reuse_client_connection.weft" 'error[E2001]: effect `HttpClient<TlsStream>` is not available in this context'
check_rejects "http_client_cannot_read_server_connection" "test/negative/http_client_cannot_read_server_connection.weft" 'error[E2001]: effect `HttpServer` is not available in this context'
check_rejects "http_json_reader_constructor_private" "test/negative/http_json_reader_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "http_json_prefixed_reader_removed" "test/negative/http_json_prefixed_reader_removed.weft" "error[E4002]: unknown module member 'http_json_reader' in import" 1
check_rejects "http_json_prefixed_read_removed" "test/negative/http_json_prefixed_read_removed.weft" "error[E4002]: unknown module member 'http_json_read' in import" 1
check_rejects "http_json_prefixed_write_removed" "test/negative/http_json_prefixed_write_removed.weft" "error[E4002]: unknown module member 'http_json_write' in import" 1
check_rejects "http_json_prefixed_document_value_removed" "test/negative/http_json_prefixed_document_value_removed.weft" "error[E4002]: unknown module member 'http_json_document_value' in import" 1
check_rejects "http_json_prefixed_document_trailers_removed" "test/negative/http_json_prefixed_document_trailers_removed.weft" "error[E4002]: unknown module member 'http_json_document_trailers' in import" 1
check_rejects "http_json_prefixed_failure_error_removed" "test/negative/http_json_prefixed_failure_error_removed.weft" "error[E4002]: unknown module member 'http_json_failure_error' in import" 1
check_rejects "http_json_prefixed_failure_trailers_removed" "test/negative/http_json_prefixed_failure_trailers_removed.weft" "error[E4002]: unknown module member 'http_json_failure_trailers' in import" 1
check_rejects "http_replay_prefixed_fixture_removed" "test/negative/http_replay_prefixed_fixture_removed.weft" "error[E4002]: unknown module member 'http_replay_fixture' in import" 1
check_rejects "http_replay_prefixed_stats_removed" "test/negative/http_replay_prefixed_stats_removed.weft" "error[E4002]: unknown module member 'http_replay_stats' in import" 1
check_rejects "http_client_prefixed_pool_limit_removed" "test/negative/http_client_prefixed_pool_limit_removed.weft" "error[E4002]: unknown module member 'http_pool_max_idle' in import" 1
check_rejects "http_client_prefixed_pool_removed" "test/negative/http_client_prefixed_pool_removed.weft" "error[E4002]: unknown module member 'http_connection_pool' in import" 1
check_rejects "http_client_prefixed_pool_len_removed" "test/negative/http_client_prefixed_pool_len_removed.weft" "error[E4002]: unknown module member 'http_pool_len' in import" 1
check_rejects "http_client_prefixed_pool_checkout_removed" "test/negative/http_client_prefixed_pool_checkout_removed.weft" "error[E4002]: unknown module member 'http_pool_checkout' in import" 1
check_rejects "http_client_prefixed_pool_release_removed" "test/negative/http_client_prefixed_pool_release_removed.weft" "error[E4002]: unknown module member 'http_pool_release' in import" 1
check_rejects "http_client_prefixed_pool_begin_removed" "test/negative/http_client_prefixed_pool_begin_removed.weft" "error[E4002]: unknown module member 'http_client_pool_begin' in import" 1
check_rejects "http_client_prefixed_redirect_policy_removed" "test/negative/http_client_prefixed_redirect_policy_removed.weft" "error[E4002]: unknown module member 'http_redirect_policy' in import" 1
check_rejects "http_client_prefixed_redirect_history_removed" "test/negative/http_client_prefixed_redirect_history_removed.weft" "error[E4002]: unknown module member 'http_redirect_history' in import" 1
check_rejects "http_client_prefixed_redirect_history_len_removed" "test/negative/http_client_prefixed_redirect_history_len_removed.weft" "error[E4002]: unknown module member 'http_redirect_history_len' in import" 1
check_rejects "http_client_prefixed_redirect_step_removed" "test/negative/http_client_prefixed_redirect_step_removed.weft" "error[E4002]: unknown module member 'http_redirect_step' in import" 1
check_rejects "tls_raw_backend_private" "test/negative/tls_raw_backend_private.weft" "module member 'tls_mbedtls_handshake' is not visible in this import" 1
check_rejects "tls_session_use_after_move" "test/negative/tls_session_use_after_move.weft" "type error: owned value used more than once"
check_rejects "tls_stream_constructor_private" "test/negative/tls_stream_constructor_private.weft" "opaque constructor is private to its declaring module"
check_rejects "net_address_constructor_private" "test/negative/net_address_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "net_address_projection_private" "test/negative/net_address_projection_private.weft" "type error: opaque projection pattern is private to its declaring module; use an exported accessor"
check_rejects "net_prefixed_parser_removed" "test/negative/net_prefixed_parser_removed.weft" "error[E4002]: unknown module member 'socket_address_parse' in import" 1
check_rejects "dns_prefixed_resolve_removed" "test/negative/dns_prefixed_resolve_removed.weft" "error[E4002]: unknown module member 'dns_resolve' in import" 1
check_rejects "idna_prefixed_parse_removed" "test/negative/idna_prefixed_parse_removed.weft" "error[E4002]: unknown module member 'domain_name_parse' in import" 1
check_rejects "idna_domain_constructor_private" "test/negative/idna_domain_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "idna_domain_projection_private" "test/negative/idna_domain_projection_private.weft" "type error: opaque projection pattern is private to its declaring module; use an exported accessor"
check_rejects "url_constructor_private" "test/negative/url_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "url_prefixed_parse_removed" "test/negative/url_prefixed_parse_removed.weft" "error[E4002]: unknown module member 'url_parse' in import" 1
check_rejects "http_target_constructor_private" "test/negative/http_target_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "http_prefixed_limits_removed" "test/negative/http_prefixed_limits_removed.weft" "error[E4002]: unknown module member 'http_default_limits' in import" 1
check_rejects "http_body_prefixed_read_removed" "test/negative/http_body_prefixed_read_removed.weft" "error[E4002]: unknown module member 'http_body_read' in import" 1
check_rejects "http_client_prefixed_begin_removed" "test/negative/http_client_prefixed_begin_removed.weft" "error[E4002]: unknown module member 'http_client_begin' in import" 1
check_rejects "sse_decoder_constructor_private" "test/negative/sse_decoder_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "sse_prefixed_limits_removed" "test/negative/sse_prefixed_limits_removed.weft" "error[E4002]: unknown module member 'sse_limits' in import" 1
check_rejects "sse_reader_constructor_private" "test/negative/sse_reader_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "sse_stream_prefixed_reader_removed" "test/negative/sse_stream_prefixed_reader_removed.weft" "error[E4002]: unknown module member 'sse_reader' in import" 1
check_rejects "websocket_message_state_constructor_private" "test/negative/websocket_message_state_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "websocket_stream_constructor_private" "test/negative/websocket_stream_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "websocket_prefixed_limits_removed" "test/negative/websocket_prefixed_limits_removed.weft" "error[E4002]: unknown module member 'websocket_limits' in import" 1
check_rejects "websocket_stream_prefixed_client_removed" "test/negative/websocket_stream_prefixed_client_removed.weft" "error[E4002]: unknown module member 'websocket_client_stream' in import" 1
check_rejects "websocket_client_write_requires_random" "test/negative/websocket_client_write_requires_random.weft" 'error[E2001]: effect `SecureRandom` is not available in this context'
check_rejects "dns_resolve_requires_effect" "test/negative/dns_resolve_requires_effect.weft" 'error[E2001]: effect `DnsResolve` is not available in this context'
check_rejects "dns_policy_requires_authority" "test/negative/dns_policy_requires_authority.weft" 'error[E2001]: effect `DnsResolve` is not available in this context'
check_rejects "dns_policy_wrapper_retired" "test/negative/dns_policy_wrapper_retired.weft" "error[E4002]: unknown module member 'dns_with_policy' in import" 1
check_rejects "dns_fake_wrapper_retired" "test/negative/dns_fake_wrapper_retired.weft" "error[E4002]: unknown module member 'dns_with_fake' in import" 1
check_rejects "dns_policy_types_relocated" "test/negative/dns_policy_types_relocated.weft" "error[E4002]: unknown module member 'DnsPolicy' in import" 3
check_rejects "dns_fake_types_relocated" "test/negative/dns_fake_types_relocated.weft" "error[E4002]: unknown module member 'DnsFakeAddresses' in import" 3
check_rejects "dns_policy_constructor_private" "test/negative/dns_policy_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "dns_fake_resolver_constructor_private" "test/negative/dns_fake_resolver_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "dns_platform_wrapper_retired" "test/negative/dns_platform_wrapper_retired.weft" "error[E4002]: unknown module member 'runtime_platform_dns' in import" 1
check_rejects "dns_raw_backend_private" "test/negative/dns_raw_backend_private.weft" "module member 'runtime_dns_getaddrinfo' is not visible in this import" 1
check_rejects "dns_raw_getaddrinfo_requires_trusted" "test/negative/dns_raw_getaddrinfo_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "tcp_connect_requires_authority" "test/negative/tcp_connect_requires_authority.weft" 'error[E2001]: effect `TcpConnect` is not available in this context'
check_rejects "tcp_listen_requires_authority" "test/negative/tcp_listen_requires_authority.weft" 'error[E2001]: effect `TcpListen` is not available in this context'
check_rejects "tcp_connect_does_not_grant_listen" "test/negative/tcp_connect_does_not_grant_listen.weft" 'error[E2001]: effect `TcpListen` is not available in this context'
check_rejects "tcp_listen_does_not_grant_connect" "test/negative/tcp_listen_does_not_grant_connect.weft" 'error[E2001]: effect `TcpConnect` is not available in this context'
check_rejects "tcp_connect_policy_requires_authority" "test/negative/tcp_connect_policy_requires_authority.weft" 'error[E2001]: effect `TcpConnect` is not available in this context'
check_rejects "tcp_policy_authorities_are_distinct" "test/negative/tcp_policy_authorities_are_distinct.weft" 'error[E1002]:'
check_rejects "tcp_prefixed_surface_retired" "test/negative/tcp_prefixed_surface_retired.weft" "error[E4002]: unknown module member 'tcp_accept' in import" 17
check_rejects "tcp_policy_wrappers_retired" "test/negative/tcp_policy_wrappers_retired.weft" "error[E4002]: unknown module member 'TcpConnectPolicy' in import" 6
check_rejects "tls_prefixed_surface_retired" "test/negative/tls_prefixed_surface_retired.weft" "error[E4002]: unknown module member 'tls_client_open' in import" 11
check_rejects "tls_stream_prefixed_surface_retired" "test/negative/tls_stream_prefixed_surface_retired.weft" "error[E4002]: unknown module member 'tls_stream_close' in import" 4
check_rejects "tcp_listener_constructor_is_private" "test/negative/tcp_listener_constructor_is_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "tcp_listener_projection_is_private" "test/negative/tcp_listener_projection_is_private.weft" "type error: opaque projection pattern is private to its declaring module; use an exported accessor"
check_rejects "tcp_stream_constructor_is_private" "test/negative/tcp_stream_constructor_is_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "tcp_stream_projection_is_private" "test/negative/tcp_stream_projection_is_private.weft" "type error: opaque projection pattern is private to its declaring module; use an exported accessor"
check_rejects "tcp_raw_backend_private" "test/negative/tcp_raw_backend_private.weft" "module member 'runtime_tcp_connect_raw' is not visible in this import" 1
check_rejects "unhandled_alloc_effect" "test/negative/unhandled_alloc_effect.weft" "error[E2001]:"
check_rejects "unsafe_raw_syscall_requires_effect" "test/negative/unsafe_raw_syscall_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_raw_offset_requires_effect" "test/negative/unsafe_raw_offset_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_transmute_requires_effect" "test/negative/unsafe_transmute_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_int_to_ptr_requires_effect" "test/negative/unsafe_int_to_ptr_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_runtime_state_requires_effect" "test/negative/unsafe_runtime_state_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_set_runtime_state_requires_effect" "test/negative/unsafe_set_runtime_state_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_set_handler_stack_requires_effect" "test/negative/unsafe_set_handler_stack_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_raw_call_i64_requires_effect" "test/negative/unsafe_raw_call_i64_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_call_closure_i64_requires_effect" "test/negative/unsafe_call_closure_i64_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_fiber_suspend_requires_effect" "test/negative/unsafe_fiber_suspend_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_fiber_resume_requires_effect" "test/negative/unsafe_fiber_resume_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_fiber_wrapper_requires_effect" "test/negative/unsafe_fiber_wrapper_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_got_requires_effect" "test/negative/unsafe_got_requires_effect.weft" "error[E2001]:"
check_rejects "platform_read_requires_trusted" "test/negative/platform_read_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_open_read_requires_trusted" "test/negative/platform_open_read_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_open_write_create_new_requires_trusted" "test/negative/platform_open_write_create_new_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_open_write_create_truncate_requires_trusted" "test/negative/platform_open_write_create_truncate_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_open_write_append_requires_trusted" "test/negative/platform_open_write_append_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_open_read_write_create_truncate_requires_trusted" "test/negative/platform_open_read_write_create_truncate_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_seek_start_requires_trusted" "test/negative/platform_seek_start_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_seek_current_requires_trusted" "test/negative/platform_seek_current_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_seek_end_requires_trusted" "test/negative/platform_seek_end_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_file_flush_requires_trusted" "test/negative/platform_file_flush_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_open_requires_trusted" "test/negative/platform_dir_open_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_read_requires_trusted" "test/negative/platform_dir_read_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_entry_record_len_requires_trusted" "test/negative/platform_dir_entry_record_len_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_entry_name_requires_trusted" "test/negative/platform_dir_entry_name_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_entry_is_directory_requires_trusted" "test/negative/platform_dir_entry_is_directory_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_stat_follow_requires_trusted" "test/negative/platform_stat_follow_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_stat_nofollow_requires_trusted" "test/negative/platform_stat_nofollow_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_mkdir_requires_trusted" "test/negative/platform_dir_mkdir_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_getcwd_requires_trusted" "test/negative/platform_dir_getcwd_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_remove_directory_requires_trusted" "test/negative/platform_dir_remove_directory_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_dir_current_requires_trusted" "test/negative/platform_dir_current_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_time_realtime_requires_trusted" "test/negative/platform_time_realtime_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_time_monotonic_requires_trusted" "test/negative/platform_time_monotonic_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_time_sleep_requires_trusted" "test/negative/platform_time_sleep_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_close_requires_trusted" "test/negative/platform_close_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_remove_requires_trusted" "test/negative/platform_remove_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_rename_requires_trusted" "test/negative/platform_rename_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_io_error_requires_trusted" "test/negative/platform_io_error_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_map_rw_anonymous_requires_trusted" "test/negative/platform_map_rw_anonymous_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_remap_rw_anonymous_fixed_requires_trusted" "test/negative/platform_remap_rw_anonymous_fixed_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_unmap_requires_trusted" "test/negative/platform_unmap_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_write_requires_trusted" "test/negative/platform_write_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_exit_requires_trusted" "test/negative/platform_exit_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_native_host_target_requires_trusted" "test/negative/platform_native_host_target_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_terminal_is_tty_requires_trusted" "test/negative/platform_terminal_is_tty_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "platform_compiler_host_primitives_require_trusted" "test/negative/platform_compiler_host_primitives_require_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code" 7
check_rejects "platform_thread_primitives_require_trusted" "test/negative/platform_thread_primitives_require_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code" 13
check_rejects "platform_tcp_primitives_require_trusted" "test/negative/platform_tcp_primitives_require_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code" 14
check_rejects "platform_readiness_primitives_require_trusted" "test/negative/platform_readiness_primitives_require_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code" 12
check_rejects "platform_dns_primitives_require_trusted" "test/negative/platform_dns_primitives_require_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code" 9
check_rejects "root_raw_syscall_with_effect_requires_trusted" "test/negative/root_raw_syscall_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "root_mem_with_effect_requires_trusted" "test/negative/root_mem_with_effect_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "frame_pointer_requires_trusted" "test/negative/frame_pointer_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
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
check_rejects "unsafe_wrapper_must_discharge" "test/negative/unsafe_wrapper_must_discharge.weft" "error[E2001]:"
check_rejects "unsafe_raw_offset_wrapper_requires_effect" "test/negative/unsafe_raw_offset_wrapper_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_transmute_wrapper_requires_effect" "test/negative/unsafe_transmute_wrapper_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_int_to_ptr_wrapper_requires_effect" "test/negative/unsafe_int_to_ptr_wrapper_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_raw_offset_pointer_arg_required" "test/negative/unsafe_raw_offset_pointer_arg_required.weft" 'error[E1002]: argument type mismatch: expected `*any`, found `i64`'
check_rejects "unsafe_raw_offset_wrapper_pointer_arg_required" "test/negative/unsafe_raw_offset_wrapper_pointer_arg_required.weft" 'error[E1002]: argument type mismatch: expected `*i64`, found `i64`'
check_rejects "unsafe_int_to_ptr_addr_mismatch" "test/negative/unsafe_int_to_ptr_addr_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "unsafe_transmute_arity_mismatch" "test/negative/unsafe_transmute_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "unsafe_runtime_state_wrapper_requires_effect" "test/negative/unsafe_runtime_state_wrapper_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_process_run_command_requires_effect" "test/negative/unsafe_process_run_command_requires_effect.weft" "error[E2001]:"
check_rejects "process_platform_wrappers_retired" "test/negative/process_platform_wrappers_retired.weft" "error[E4002]: unknown module member 'runtime_platform_proc' in import" 3
check_rejects "env_platform_wrappers_retired" "test/negative/env_platform_wrappers_retired.weft" "error[E4002]: unknown module member 'runtime_platform_env' in import" 2
check_rejects "tcp_platform_wrapper_retired" "test/negative/tcp_platform_wrapper_retired.weft" "error[E4002]: unknown module member 'runtime_platform_tcp' in import" 1
check_rejects "file_stream_platform_wrappers_retired" "test/negative/file_stream_platform_wrappers_retired.weft" "error[E4002]: unknown module member 'runtime_platform_file_stream' in import" 2
check_rejects "safe_io_facade_retired" "test/negative/safe_io_facade_retired.weft" "error[E1001]: unknown function 'runtime_platform_safe_io'" 1
check_rejects "unsafe_method_call_requires_effect" "test/negative/unsafe_method_call_requires_effect.weft" "error[E2001]:"
check_rejects "unsafe_lambda_to_pure_fn" "test/negative/unsafe_lambda_to_pure_fn.weft" "error[E2001]:"
check_rejects "non_unsafe_handler_raw_call" "test/negative/non_unsafe_handler_raw_call.weft" "error[E2001]:"
check_rejects "unhandled_effect_in_while" "test/negative/unhandled_effect_in_while.weft" "error[E2001]:"
check_rejects "unhandled_effect_in_defer" "test/negative/unhandled_effect_in_defer.weft" "error[E2001]:"
check_rejects "unhandled_try_effect" "test/negative/unhandled_try_effect.weft" 'error[E2001]: effect `Fail<i64>` is not available in this context'
check_rejects "unhandled_optional_chain_effect" "test/negative/unhandled_optional_chain_effect.weft" "error[E2001]:"
check_rejects "effect_perform_arg_mismatch" "test/negative/effect_perform_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "effectful_lambda_to_pure_fn" "test/negative/effectful_lambda_to_pure_fn.weft" "error[E2001]:"
check_rejects "fusion_effectful_map_callback" "test/negative/fusion_effectful_map_callback.weft" "error[E2001]:"
check_rejects "fusion_effectful_filter_callback" "test/negative/fusion_effectful_filter_callback.weft" "error[E2001]:"
check_rejects "fusion_alloc_effect_callback" "test/negative/fusion_alloc_effect_callback.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> i64`, found `(i64) -[Alloc]> i64`'
check_rejects "iter_fold_effectful_callback" "test/negative/iter_fold_effectful_callback.weft" "error[E2001]:"
check_rejects "iter_map_collect_effectful_callback" "test/negative/iter_map_collect_effectful_callback.weft" "error[E2001]:"
check_rejects "iter_map_effectful_callback" "test/negative/iter_map_effectful_callback.weft" "error[E2001]:"
check_rejects "iter_filter_effectful_callback" "test/negative/iter_filter_effectful_callback.weft" "error[E2001]:"
check_rejects "iterator_collect_item_mismatch" "test/negative/iterator_collect_item_mismatch.weft" "type error: associated type constraint mismatch"
check_rejects "iterator_collect_missing_impl" "test/negative/iterator_collect_missing_impl.weft" 'error[E1004]: type `NotACollection` does not implement `Collect`'
check_rejects "effectful_lambda_to_pure_effect_op" "test/negative/effectful_lambda_to_pure_effect_op.weft" "error[E2001]:"
check_rejects "function_value_effect_unavailable" "test/negative/function_value_effect_unavailable.weft" "error[E2001]:"
check_rejects "function_value_arg_mismatch" "test/negative/function_value_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "function_value_return_mismatch" "test/negative/function_value_return_mismatch.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `str`'
check_rejects "method_call_arity_too_few" "test/negative/method_call_arity_too_few.weft" "type error: arity mismatch"
check_rejects "method_call_arity_too_many" "test/negative/method_call_arity_too_many.weft" "type error: arity mismatch"
check_rejects "iterator_combinator_type_arity" "test/negative/iterator_combinator_type_arity.weft" "type error: wrong number of type arguments"
check_rejects "generic_method_type_bound" "test/negative/generic_method_type_bound.weft" 'error[E1004]: type `str` does not implement `GenericMethodMarker`'
check_rejects "method_call_arg_mismatch" "test/negative/method_call_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "method_call_trait_arg_mismatch" "test/negative/method_call_trait_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "method_call_effect_unavailable" "test/negative/method_call_effect_unavailable.weft" 'error[E2001]: effect `MethodEffect` is not available in this context'
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
check_rejects "generic_impl_conditional_bound" "test/negative/generic_impl_conditional_bound.weft" 'error[E1004]: type `ConditionalBox<bool>` does not implement `Identity`'
check_rejects "generic_impl_target_arity" "test/negative/generic_impl_target_arity.weft" "type error: impl target type argument count mismatch"
check_rejects "generic_impl_unconstrained_parameter" "test/negative/generic_impl_unconstrained_parameter.weft" "type error: impl parameter is not determined by the target type"
check_rejects "generic_impl_repeated_receiver_mismatch" "test/negative/generic_impl_repeated_receiver_mismatch.weft" "type error: unknown method"
check_rejects "generic_inherent_impl_overlap" "test/negative/generic_inherent_impl_overlap.weft" "type error: conflicting inherent implementations for method"
check_rejects "trait_assoc_missing" "test/negative/trait_assoc_missing.weft" "type error: impl missing required associated type"
check_rejects "trait_assoc_duplicate" "test/negative/trait_assoc_duplicate.weft" "type error: duplicate associated type binding"
check_rejects "trait_assoc_extra" "test/negative/trait_assoc_extra.weft" "type error: impl associated type is not declared by trait"
check_rejects "trait_assoc_bound_concrete" "test/negative/trait_assoc_bound_concrete.weft" 'error[E1004]: type `str` does not implement `AssocBoundConcreteValue`'
check_rejects "trait_assoc_bound_generic" "test/negative/trait_assoc_bound_generic.weft" 'error[E1004]: type `T` does not implement `AssocBoundGenericValue`'
check_rejects "trait_assoc_signature_mismatch" "test/negative/trait_assoc_signature_mismatch.weft" "type error: impl method parameter type mismatch"
check_rejects "trait_assoc_constraint_mismatch" "test/negative/trait_assoc_constraint_mismatch.weft" "type error: associated type constraint mismatch"
check_rejects "trait_assoc_constraint_unknown" "test/negative/trait_assoc_constraint_unknown.weft" "type error: unknown associated type in trait constraint"
check_rejects "trait_assoc_constraint_duplicate" "test/negative/trait_assoc_constraint_duplicate.weft" "type error: duplicate associated type constraint"
check_rejects "trait_assoc_constraint_conditional_impl" "test/negative/trait_assoc_constraint_conditional_impl.weft" 'error[E1004]: type `ConditionalWrapper<ConditionalText>` does not implement `ConditionalEvidence`'
check_rejects "trait_assoc_constraint_missing_type" "test/negative/trait_assoc_constraint_missing_type.weft" "error[E0002]: expected type after associated-type '='"
check_rejects "trait_impl_conflict" "test/negative/trait_impl_conflict.weft" "type error: conflicting implementations of trait for type"
check_rejects "ord_missing_impl" "test/negative/ord_missing_impl.weft" 'error[E1004]: type `Unordered` does not implement `Ord`'
check_rejects "sorted_map_key_missing_ord" "test/negative/sorted_map_key_missing_ord.weft" 'error[E1004]: type `UnorderedKey` does not implement `Ord`'
check_rejects "sorted_map_constructor_private" "test/negative/sorted_map_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "sorted_set_constructor_private" "test/negative/sorted_set_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "ord_operand_mismatch" "test/negative/ord_operand_mismatch.weft" "type error: ordering operand type mismatch"
check_rejects "ord_unbounded_generic" "test/negative/ord_unbounded_generic.weft" 'error[E1004]: type `T` does not implement `Ord`'
check_rejects "ord_wrong_signature" "test/negative/ord_wrong_signature.weft" "type error: Ord must define pure compare(self, Self) -> Ordering"
check_rejects "ord_effectful_signature" "test/negative/ord_effectful_signature.weft" "type error: Ord must define pure compare(self, Self) -> Ordering"
check_rejects "ord_legacy_i64_signature" "test/negative/ord_legacy_i64_signature.weft" "type error: Ord must define pure compare(self, Self) -> Ordering"
check_rejects "display_missing_impl" "test/negative/display_missing_impl.weft" "error[E1004]:"
check_rejects "hash_missing_impl" "test/negative/hash_missing_impl.weft" 'error[E1004]: type `bool` does not implement `Hash`'
check_rejects "display_wrong_signature" "test/negative/display_wrong_signature.weft" "type error: impl method return type mismatch"
check_rejects "display_effectful_signature" "test/negative/display_effectful_signature.weft" "type error: impl method effect mismatch"
check_rejects "default_missing_impl" "test/negative/default_missing_impl.weft" "error[E1004]:"
check_rejects "default_impl_return_mismatch" "test/negative/default_impl_return_mismatch.weft" "type error: impl method return type mismatch"
check_rejects "default_impl_effect_mismatch" "test/negative/default_impl_effect_mismatch.weft" "type error: impl method effect mismatch"
check_rejects "associated_function_value_call" "test/negative/associated_function_value_call.weft" "type error: associated function must be called on a type"
check_rejects "associated_function_arity_mismatch" "test/negative/associated_function_arity_mismatch.weft" "type error: arity mismatch"
check_rejects "instance_method_type_call" "test/negative/instance_method_type_call.weft" "type error: instance method must be called on a value"
check_rejects "option_unwrap_or_type_mismatch" "test/negative/option_unwrap_or_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `str`, found `i64`'
check_rejects "result_unwrap_or_type_mismatch" "test/negative/result_unwrap_or_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `str`, found `i64`'
check_rejects "list_prepend_type_mismatch" "test/negative/list_prepend_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `str`, found `i64`'
check_rejects "vector_cross_type_push" "test/negative/vector_cross_type_push.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "persistent_vector_cross_type_push" "test/negative/persistent_vector_cross_type_push.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "vector_sort_missing_ord" "test/negative/vector_sort_missing_ord.weft" "error[E1004]:"
check_rejects "vector_sort_effectful_comparator" "test/negative/vector_sort_effectful_comparator.weft" 'error[E1002]: argument type mismatch: expected `(i64, i64) -> Ordering`, found `(i64, i64) -[SortNoise]> Ordering`'
check_rejects "vector_filter_effectful_predicate" "test/negative/vector_filter_effectful_predicate.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> bool`, found `(i64) -[FilterNoise]> bool`'
check_rejects "vector_concat_type_mismatch" "test/negative/vector_concat_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `Vector<i64>`, found `Vector<str>`'
check_rejects "generic_function_ref_unresolved" "test/negative/generic_function_ref_unresolved.weft" "type error: cannot infer generic function reference"
check_rejects "generic_call_unresolved" "test/negative/generic_call_unresolved.weft" "type error: cannot infer generic call type arguments; write explicit type arguments"
check_rejects "generic_qualified_call_unresolved" "test/negative/generic_qualified_call_unresolved.weft" "type error: cannot infer generic call type arguments; write explicit type arguments"
check_rejects "map_wrong_key_type" "test/negative/map_wrong_key_type.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "map_wrong_value_type" "test/negative/map_wrong_value_type.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "map_key_requires_hash" "test/negative/map_key_requires_hash.weft" "error[E1004]:"
check_rejects "set_wrong_element_type" "test/negative/set_wrong_element_type.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "map_set_handle_confusion" "test/negative/map_set_handle_confusion.weft" 'type error: unknown method'
check_rejects "map_sentinel_lookup_removed" "test/negative/map_sentinel_lookup_removed.weft" "type error: arity mismatch"
check_rejects "map_remove_wrong_key_type" "test/negative/map_remove_wrong_key_type.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "set_remove_wrong_element_type" "test/negative/set_remove_wrong_element_type.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "set_union_element_type_mismatch" "test/negative/set_union_element_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `Set<i64>`, found `Set<str>`'
check_rejects "set_intersection_element_type_mismatch" "test/negative/set_intersection_element_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `Set<i64>`, found `Set<str>`'
check_rejects "set_difference_element_type_mismatch" "test/negative/set_difference_element_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `Set<i64>`, found `Set<str>`'
check_rejects "option_expect_message_type_mismatch" "test/negative/option_expect_message_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `str`, found `i64`'
check_rejects "result_expect_message_type_mismatch" "test/negative/result_expect_message_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `str`, found `i64`'
check_rejects "assert_eq_type_mismatch" "test/negative/assert_eq_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "stdlib_test_assert_true_type_mismatch" "test/negative/stdlib_test_assert_true_type_mismatch.weft" 'error[E1002]: argument type mismatch: expected `bool`, found `i64`'
check_rejects "list_sentinel_head_removed" "test/negative/list_sentinel_head_removed.weft" "type error: unknown method"
check_rejects "self_outside_method" "test/negative/self_outside_method.weft" "type error: Self is only valid in trait and impl method signatures"
check_rejects "self_in_data_type" "test/negative/self_in_data_type.weft" "type error: Self is only valid in trait and impl method signatures"
check_rejects "drop_impl_missing_method" "test/negative/drop_impl_missing_method.weft" "type error: Drop impl missing concrete drop method"
check_rejects "drop_impl_arity_mismatch" "test/negative/drop_impl_arity_mismatch.weft" "type error: Drop impl method arity mismatch"
check_rejects "drop_impl_param_mismatch" "test/negative/drop_impl_param_mismatch.weft" "type error: Drop impl method parameter type mismatch"
check_rejects "drop_impl_return_mismatch" "test/negative/drop_impl_return_mismatch.weft" "type error: Drop impl method return type mismatch"
check_rejects "let_bound_lambda_effect_mismatch" "test/negative/let_bound_lambda_effect_mismatch.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> i64`, found `(i64) -[Log]> i64`'
check_rejects "let_bound_lambda_record_effect_mismatch" "test/negative/let_bound_lambda_record_effect_mismatch.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> EffectRecord`, found `(i64) -[Log]> EffectRecord`'
check_rejects "let_bound_lambda_method_effect_mismatch" "test/negative/let_bound_lambda_method_effect_mismatch.weft" 'error[E1002]: argument type mismatch: expected `(EffectMethodBox) -> i64`, found `(EffectMethodBox) -[Log]> i64`'
check_rejects "let_bound_lambda_effect_unavailable" "test/negative/let_bound_lambda_effect_unavailable.weft" "error[E2001]:"
check_rejects "let_bound_lambda_return_mismatch" "test/negative/let_bound_lambda_return_mismatch.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> i64`, found `(i64) -> str`'
check_rejects "unknown_identifier" "test/negative/unknown_identifier.weft" "error[E1001]: unknown identifier 'missing'"
check_rejects "unicode_identifier_non_nfc" "test/negative/unicode_identifier_non_nfc.weft" "error[E0001]: identifier must use NFC normalization"
check_rejects "unicode_identifier_default_ignorable" "test/negative/unicode_identifier_default_ignorable.weft" "error[E0001]: default-ignorable code point is not permitted in an identifier"
check_rejects "unicode_identifier_continue_only_start" "test/negative/unicode_identifier_continue_only_start.weft" "error[E0001]: Unicode scalar is not permitted at this identifier position"
check_rejects "unicode_identifier_non_xid" "test/negative/unicode_identifier_non_xid.weft" "error[E0001]: Unicode scalar is not permitted at this identifier position"
check_rejects "unknown_function" "test/negative/unknown_function.weft" "error[E1001]: unknown function 'missing'"
check_rejects "unknown_intrinsic_call" "test/negative/unknown_intrinsic_call.weft" "error[E1001]: unknown function '__definitely_not_an_intrinsic'"
check_rejects "unknown_function_in_import" "test/negative/unknown_function_in_import.weft" "error[E1001]: unknown function 'some_function_that_does_not_exist'"
check_rejects "module_plain_import_does_not_leak_value" "test/negative/module_plain_import_does_not_leak_value.weft" "error[E1001]: unknown function 'work'"
check_rejects "prelude_excludes_option_helpers" "test/negative/prelude_excludes_option_helpers.weft" "error[E1001]: unknown function 'option_some'"
check_rejects "result_helper_removed" "test/negative/result_helper_removed.weft" "error[E1001]: unknown function 'result_ok'"
check_rejects "option_prefixed_map_removed" "test/negative/option_prefixed_map_removed.weft" "error[E4002]: unknown module member 'option_map' in import" 1
check_rejects "result_prefixed_map_removed" "test/negative/result_prefixed_map_removed.weft" "error[E4002]: unknown module member 'result_map' in import" 1
check_rejects "list_nil_removed" "test/negative/list_nil_removed.weft" "error[E4002]: unknown module member 'list_nil' in import" 1
check_rejects "list_cons_removed" "test/negative/list_cons_removed.weft" "error[E4002]: unknown module member 'list_cons' in import" 1
check_rejects "list_fold_removed" "test/negative/list_fold_removed.weft" "error[E4002]: unknown module member 'list_fold' in import" 1
check_rejects "list_empty_removed" "test/negative/list_empty_removed.weft" "error[E4002]: unknown module member 'list_empty' in import" 1
check_rejects "list_first_or_removed" "test/negative/list_first_or_removed.weft" "error[E4002]: unknown module member 'list_first_or' in import" 1
check_rejects "list_rest_or_nil_removed" "test/negative/list_rest_or_nil_removed.weft" "error[E4002]: unknown module member 'list_rest_or_nil' in import" 1
check_rejects "list_len_removed" "test/negative/list_len_removed.weft" "error[E4002]: unknown module member 'list_len' in import" 1
check_rejects "list_nth_removed" "test/negative/list_nth_removed.weft" "error[E4002]: unknown module member 'list_nth' in import" 1
check_rejects "list_map_removed" "test/negative/list_map_removed.weft" "error[E4002]: unknown module member 'list_map' in import" 1
check_rejects "list_reverse_removed" "test/negative/list_reverse_removed.weft" "error[E4002]: unknown module member 'list_reverse' in import" 1
check_rejects "list_concat_removed" "test/negative/list_concat_removed.weft" "error[E4002]: unknown module member 'list_concat' in import" 1
check_rejects "list_append_removed" "test/negative/list_append_removed.weft" "error[E4002]: unknown module member 'list_append' in import" 1
check_rejects "list_filter_removed" "test/negative/list_filter_removed.weft" "error[E4002]: unknown module member 'list_filter' in import" 1
check_rejects "list_range_removed" "test/negative/list_range_removed.weft" "error[E4002]: unknown module member 'list_range' in import" 1
check_rejects "list_map_fold_i64_removed" "test/negative/list_map_fold_i64_removed.weft" "error[E4002]: unknown module member 'list_map_fold_i64' in import" 1
check_rejects "list_filter_fold_i64_removed" "test/negative/list_filter_fold_i64_removed.weft" "error[E4002]: unknown module member 'list_filter_fold_i64' in import" 1
check_rejects "list_map_filter_fold_i64_removed" "test/negative/list_map_filter_fold_i64_removed.weft" "error[E4002]: unknown module member 'list_map_filter_fold_i64' in import" 1
check_rejects "prelude_methods_require_explicit_import" "test/negative/prelude_methods_require_explicit_import.weft" "type error: unknown method"
check_rejects "quoted_import_removed" "test/negative/quoted_import_removed.weft" "error[E0002]: expected path-form module after 'use'"
check_rejects "extern_keyword_removed" "test/negative/extern_keyword_removed.weft" "error[E0002]: unexpected token at module level"
check_rejects "module_qualified_function_unknown" "test/negative/module_qualified_function_unknown.weft" "error[E4002]: unknown module member 'left.missing'"
check_rejects "module_qualified_function_private" "test/negative/module_qualified_function_private.weft" "error[E4004]: module member 'left.hidden' is not visible"
check_rejects "module_qualified_function_arity" "test/negative/module_qualified_function_arity.weft" "type error: arity mismatch"
check_rejects "module_qualified_function_argument" "test/negative/module_qualified_function_argument.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "module_qualified_constructor_unknown" "test/negative/module_qualified_constructor_unknown.weft" "error[E4002]: unknown module member 'left.Missing'"
check_rejects "module_qualified_constructor_private" "test/negative/module_qualified_constructor_private.weft" "error[E4004]: module member 'left.Hidden' is not visible"
check_rejects "module_qualified_constructor_argument" "test/negative/module_qualified_constructor_argument.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "module_qualified_pattern_unknown" "test/negative/module_qualified_pattern_unknown.weft" "error[E4002]: unknown module member 'left.Missing'"
check_rejects "module_qualified_pattern_private" "test/negative/module_qualified_pattern_private.weft" "error[E4004]: module member 'left.Hidden' is not visible"
check_rejects "module_qualified_pattern_identity_mismatch" "test/negative/module_qualified_pattern_identity_mismatch.weft" "type error: constructor pattern does not match scrutinee"
check_rejects "module_inherent_method_private" "test/negative/module_inherent_method_private.weft" "type error: method is not visible"
check_rejects "module_inherent_method_unknown" "test/negative/module_inherent_method_unknown.weft" "type error: unknown method"
check_rejects "module_associated_method_private" "test/negative/module_associated_method_private.weft" "type error: method is not visible"
check_rejects "module_associated_method_unknown" "test/negative/module_associated_method_unknown.weft" "type error: unknown method"
check_rejects "module_associated_method_type_arity" "test/negative/module_associated_method_type_arity.weft" "type error: generic type argument count mismatch"
check_rejects "module_qualified_effect_unknown" "test/negative/module_qualified_effect_unknown.weft" "error[E4002]: unknown module member 'bank.Missing'"
check_rejects "module_qualified_effect_private" "test/negative/module_qualified_effect_private.weft" "error[E4004]: module member 'bank.Hidden' is not visible"
check_rejects "module_qualified_effect_arity" "test/negative/module_qualified_effect_arity.weft" "type error: effect type argument count mismatch"
check_rejects "module_qualified_effect_operation" "test/negative/module_qualified_effect_operation.weft" "type error: unknown effect operation"
check_rejects "module_qualified_effect_identity_mismatch" "test/negative/module_qualified_effect_identity_mismatch.weft" 'error[E2001]: effect `module_fixtures/g2_effect_bank.Box<i64>` is not available in this context'
check_rejects "module_qualified_trait_unknown" "test/negative/module_qualified_trait_unknown.weft" "error[E4002]: unknown module member 'traits.Missing'"
check_rejects "module_qualified_trait_private" "test/negative/module_qualified_trait_private.weft" "error[E4004]: module member 'traits.HiddenGauge' is not visible"
check_rejects "module_qualified_trait_identity_mismatch" "test/negative/module_qualified_trait_identity_mismatch.weft" "type error: impl missing required method"
check_rejects "module_qualified_trait_bound_identity_mismatch" "test/negative/module_qualified_trait_bound_identity_mismatch.weft" 'error[E1004]: type `QualifiedBoundMismatchBox` does not implement `module_fixtures/g2_trait_right.Gauge`'
check_rejects "module_qualified_trait_bound_unknown" "test/negative/module_qualified_trait_bound_unknown.weft" "error[E4002]: unknown module member 'traits.Missing'"
check_rejects "module_qualified_trait_bound_private" "test/negative/module_qualified_trait_bound_private.weft" "error[E4004]: module member 'traits.HiddenGauge' is not visible"
check_rejects "module_qualified_member_ambiguous" "test/negative/module_qualified_member_ambiguous.weft" "error[E4003]: module item 'work' is ambiguous in this scope" 1
check_rejects "module_selection_missing_unused" "test/negative/module_selection_missing_unused.weft" "error[E4002]: unknown module member 'missing' in import" 1
check_rejects "module_selection_private_unused" "test/negative/module_selection_private_unused.weft" "error[E4004]: module member 'hidden' is not visible in this import" 1
check_rejects "module_selection_missing_referenced" "test/negative/module_selection_missing_referenced.weft" "error[E4002]: unknown module member 'missing' in import" 1
check_rejects "module_selection_private_referenced" "test/negative/module_selection_private_referenced.weft" "error[E4004]: module member 'hidden' is not visible in this import" 1
check_rejects "module_reexport_widening_unused" "test/negative/module_reexport_widening_unused.weft" "error[E4006]: module member 'package_value' cannot be re-exported at wider visibility" 1
check_rejects "module_selection_alias_collision" "test/negative/module_selection_alias_collision.weft" "error[E4003]: module item 'duplicate' is ambiguous in this scope" 1
check_rejects "module_alias_collision" "test/negative/module_alias_collision.weft" "error[E4003]: module item 'duplicate' is ambiguous in this scope" 1
check_rejects "module_local_collision" "test/negative/module_local_collision.weft" "error[E4003]: module item 'duplicate' is ambiguous in this scope" 1
check_rejects "module_local_import_collision" "test/negative/module_local_import_collision.weft" "error[E4003]: module item 'duplicate' is ambiguous in this scope" 1
check_rejects "module_import_local_collision" "test/negative/module_import_local_collision.weft" "error[E4003]: module item 'duplicate' is ambiguous in this scope" 1
check_rejects "module_qualified_member_wrong_kind" "test/negative/module_qualified_member_wrong_kind.weft" "error[E4005]: module member 'left.LeftChoice' is not a function value"
check_rejects "proc_run_requires_effect" "test/negative/proc_run_requires_effect.weft" "error[E2001]:"
check_rejects "proc_spawn_requires_effect" "test/negative/proc_spawn_requires_effect.weft" "error[E2001]:"
check_rejects "proc_wait_requires_effect" "test/negative/proc_wait_requires_effect.weft" "error[E2001]:"
check_rejects "proc_wait_until_requires_effect" "test/negative/proc_wait_until_requires_effect.weft" "error[E2001]:"
check_rejects "proc_release_requires_effect" "test/negative/proc_release_requires_effect.weft" "error[E2001]:"
check_rejects "proc_handle_used_twice" "test/negative/proc_handle_used_twice.weft" "type error: owned value used more than once"
check_rejects "proc_handle_drop_requires_effect" "test/negative/proc_handle_drop_requires_effect.weft" "type error: owned Drop effect not available in caller"
check_rejects "proc_handle_constructor_is_private" "test/negative/proc_handle_constructor_is_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "proc_handle_projection_is_private" "test/negative/proc_handle_projection_is_private.weft" "type error: opaque projection pattern is private to its declaring module; use an exported accessor"
check_rejects "proc_raw_pipe_requires_trusted" "test/negative/proc_raw_pipe_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "proc_raw_fcntl_is_unsupported" "test/negative/proc_raw_fcntl_is_unsupported.weft" "type error: unknown GOT symbol"
check_rejects "proc_raw_actions_init_requires_trusted" "test/negative/proc_raw_actions_init_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "proc_raw_actions_adddup2_requires_trusted" "test/negative/proc_raw_actions_adddup2_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "proc_raw_actions_addclose_requires_trusted" "test/negative/proc_raw_actions_addclose_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "proc_raw_actions_destroy_requires_trusted" "test/negative/proc_raw_actions_destroy_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "proc_raw_kill_requires_trusted" "test/negative/proc_raw_kill_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "env_arg_requires_effect" "test/negative/env_arg_requires_effect.weft" "error[E2001]:"
check_rejects "env_arg_requires_missing_case" "test/negative/env_arg_requires_missing_case.weft" 'type annotation type mismatch: expected `str`, found `str | nil`'
check_rejects "env_var_requires_effect" "test/negative/env_var_requires_effect.weft" "error[E2001]:"
check_rejects "env_raw_getenv_requires_trusted" "test/negative/env_raw_getenv_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "time_now_nanos_requires_effect" "test/negative/time_now_nanos_requires_effect.weft" "error[E2001]:"
check_rejects "time_date_surface_retired" "test/negative/time_date_surface_retired.weft" "unknown module member" 14
check_rejects "time_date_constructor_private" "test/negative/time_date_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "time_weekday_is_not_integer" "test/negative/time_weekday_is_not_integer.weft" 'return value type mismatch: expected `i64`, found `time.Weekday`'
check_rejects "time_value_surface_retired" "test/negative/time_value_surface_retired.weft" "unknown module member" 22
check_rejects "time_duration_constructor_private" "test/negative/time_duration_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "time_instant_constructor_private" "test/negative/time_instant_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "time_platform_wrappers_retired" "test/negative/time_platform_wrappers_retired.weft" "error[E4002]: unknown module member 'runtime_platform_time' in import" 2
check_rejects "time_sleep_requires_effect" "test/negative/time_sleep_requires_effect.weft" "error[E2001]:"
check_rejects "time_raw_clock_requires_trusted" "test/negative/time_raw_clock_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "time_raw_sleep_requires_trusted" "test/negative/time_raw_sleep_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_list_requires_effect" "test/negative/dir_list_requires_effect.weft" "error[E2001]:"
check_rejects "dir_stat_requires_effect" "test/negative/dir_stat_requires_effect.weft" "error[E2001]:"
check_rejects "dir_lstat_requires_effect" "test/negative/dir_lstat_requires_effect.weft" "error[E2001]:"
check_rejects "dir_mkdir_requires_effect" "test/negative/dir_mkdir_requires_effect.weft" "error[E2001]:"
check_rejects "dir_remove_requires_effect" "test/negative/dir_remove_requires_effect.weft" "error[E2001]:"
check_rejects "dir_rename_requires_effect" "test/negative/dir_rename_requires_effect.weft" "error[E2001]:"
check_rejects "dir_getcwd_requires_effect" "test/negative/dir_getcwd_requires_effect.weft" "error[E2001]:"
check_rejects "dir_raw_opendir_requires_trusted" "test/negative/dir_raw_opendir_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_raw_readdir_requires_trusted" "test/negative/dir_raw_readdir_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_raw_closedir_requires_trusted" "test/negative/dir_raw_closedir_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_raw_stat_requires_trusted" "test/negative/dir_raw_stat_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_raw_mkdir_requires_trusted" "test/negative/dir_raw_mkdir_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_raw_remove_requires_trusted" "test/negative/dir_raw_remove_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_raw_rename_requires_trusted" "test/negative/dir_raw_rename_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_raw_getcwd_requires_trusted" "test/negative/dir_raw_getcwd_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "dir_raw_errno_requires_trusted" "test/negative/dir_raw_errno_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "call_non_function" "test/negative/call_non_function.weft" "error[E1002]: value is not callable"
check_rejects "no_payload_variant_not_function" "test/negative/no_payload_variant_not_function.weft" "error[E1002]: value is not callable"
check_rejects "unknown_record_field" "test/negative/unknown_record_field.weft" "type error: unknown field"
check_rejects "field_access_non_record" "test/negative/field_access_non_record.weft" "type error: field access on non-record"
check_rejects "record_init_unknown_type" "test/negative/record_init_unknown_type.weft" "type error: unknown record type"
check_rejects "record_init_unknown_field" "test/negative/record_init_unknown_field.weft" "type error: unknown record field"
check_rejects "record_init_missing_field" "test/negative/record_init_missing_field.weft" "type error: missing record field"
check_rejects "record_init_duplicate_field" "test/negative/record_init_duplicate_field.weft" "type error: duplicate record field"
check_rejects "record_init_variant_type" "test/negative/record_init_variant_type.weft" "type error: not a record type"
check_rejects "record_init_field_type_mismatch" "test/negative/record_init_field_type_mismatch.weft" 'error[E1002]: record field type mismatch: expected `str`, found `i64`'
check_rejects "record_field_access_type_mismatch" "test/negative/record_field_access_type_mismatch.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `str`'
check_rejects "match_arm_i64_str_mismatch" "test/negative/match_arm_i64_str_mismatch.weft" 'error[E1002]: match arm type mismatch: expected `i64`, found `str`'
check_rejects "match_arm_str_bool_mismatch" "test/negative/match_arm_str_bool_mismatch.weft" 'error[E1002]: match arm type mismatch: expected `str`, found `bool`'
check_rejects "match_arm_record_mismatch" "test/negative/match_arm_record_mismatch.weft" 'error[E1002]: match arm type mismatch: expected `Point`, found `Person`'
check_rejects "match_non_exhaustive_int" "test/negative/match_non_exhaustive_int.weft" 'error[E1003]: non-exhaustive match: value `0` is not covered'
check_rejects "match_non_exhaustive_constructor" "test/negative/match_non_exhaustive_constructor.weft" 'error[E1003]: non-exhaustive match: value `Right(0)` is not covered'
check_rejects "match_duplicate_constructor" "test/negative/match_duplicate_constructor.weft" "type error: duplicate match constructor arm"
check_rejects "match_final_guarded" "test/negative/match_final_guarded.weft" 'error[E1003]: non-exhaustive match: value `0` is not covered'
check_rejects "pattern_literal_str_scrutinee" "test/negative/pattern_literal_str_scrutinee.weft" "type error: literal pattern does not match scrutinee"
check_rejects "pattern_unknown_constructor" "test/negative/pattern_unknown_constructor.weft" "type error: unknown constructor pattern"
check_rejects "pattern_constructor_on_i64" "test/negative/pattern_constructor_on_i64.weft" "type error: constructor pattern does not match scrutinee"
check_rejects "pattern_constructor_wrong_variant" "test/negative/pattern_constructor_wrong_variant.weft" "type error: constructor pattern does not match scrutinee"
check_rejects "pattern_constructor_arity_too_few" "test/negative/pattern_constructor_arity_too_few.weft" "type error: constructor pattern arity mismatch"
check_rejects "pattern_constructor_arity_too_many" "test/negative/pattern_constructor_arity_too_many.weft" "type error: constructor pattern arity mismatch"
check_rejects "pattern_nested_unknown_constructor" "test/negative/pattern_nested_unknown_constructor.weft" "type error: unknown constructor pattern"
check_rejects "pattern_nested_constructor_wrong_payload" "test/negative/pattern_nested_constructor_wrong_payload.weft" "type error: constructor pattern does not match scrutinee"
check_rejects "pattern_nested_constructor_arity" "test/negative/pattern_nested_constructor_arity.weft" "type error: constructor pattern arity mismatch"
check_rejects "pattern_nested_literal_mismatch" "test/negative/pattern_nested_literal_mismatch.weft" "type error: literal pattern does not match scrutinee"
check_rejects "pattern_nested_typed_nondiscriminable" "test/negative/pattern_nested_typed_nondiscriminable.weft" "type error: typed match arm needs a runtime-discriminable union"
check_rejects "pattern_nested_non_exhaustive" "test/negative/pattern_nested_non_exhaustive.weft" 'error[E1003]: non-exhaustive match: value `Wrap(Right)` is not covered'
check_rejects "pattern_nested_malformed" "test/negative/pattern_nested_malformed.weft" "error[E0002]: expected ',' or ')' after constructor pattern payload"
check_rejects "pattern_nested_unclosed" "test/negative/pattern_nested_unclosed.weft" "error[E0002]: expected ')' after constructor pattern"
check_rejects "opaque_construct_imported" "test/negative/opaque_construct_imported.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "opaque_project_imported" "test/negative/opaque_project_imported.weft" "type error: opaque projection pattern is private to its declaring module; use an exported accessor"
check_rejects "opaque_identity_module_mismatch" "test/negative/opaque_identity_module_mismatch.weft" 'error[E1002]: return value type mismatch: expected `opaque_left.Same`, found `opaque_right.Same`'
check_rejects "opaque_representation_return" "test/negative/opaque_representation_return.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `UserId`'
check_rejects "opaque_representation_argument" "test/negative/opaque_representation_argument.weft" 'error[E1002]: argument type mismatch: expected `UserId`, found `i64`'
check_rejects "opaque_type_arg_arity" "test/negative/opaque_type_arg_arity.weft" "type error: opaque type argument count mismatch"
check_rejects "opaque_recursive_representation" "test/negative/opaque_recursive_representation.weft" "type error: opaque value representation is recursively defined"
check_rejects "opaque_projection_arity_zero" "test/negative/opaque_projection_arity_zero.weft" "type error: opaque projection pattern requires exactly one child pattern"
check_rejects "opaque_projection_arity_many" "test/negative/opaque_projection_arity_many.weft" "type error: opaque projection pattern requires exactly one child pattern" 3
check_rejects "opaque_projection_non_exhaustive" "test/negative/opaque_projection_non_exhaustive.weft" 'error[E1003]: non-exhaustive match: value `UserId(1)` is not covered'
check_rejects "opaque_missing_marker" "test/negative/opaque_missing_marker.weft" "error[E0002]: expected 'opaque' after '=' in type declaration"
check_rejects "opaque_missing_representation" "test/negative/opaque_missing_representation.weft" "error[E0002]: expected representation type after 'opaque'"
check_rejects "opaque_any_return" "test/negative/opaque_any_return.weft" 'error[E1002]: return value type mismatch: expected `Secret`, found `any`'
check_rejects "opaque_any_assignment" "test/negative/opaque_any_assignment.weft" 'error[E1002]: assignment type mismatch: expected `Secret`, found `any`'
check_rejects "opaque_record_fabrication" "test/negative/opaque_record_fabrication.weft" "type error: not a record type"
check_rejects "opaque_field_projection" "test/negative/opaque_field_projection.weft" "type error: unknown field"
check_rejects "opaque_construct_reexported" "test/negative/opaque_construct_reexported.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "opaque_missing_drop" "test/negative/opaque_missing_drop.weft" "type error: owned type requires Drop resource conformance"
check_rejects "opaque_use_after_move" "test/negative/opaque_use_after_move.weft" "type error: owned value used more than once"
check_rejects "opaque_representation_too_wide" "test/negative/opaque_representation_too_wide.weft" "type error: result type exceeds 8-lane native ABI"
check_rejects "opaque_mutable_representation_not_sendable" "test/negative/opaque_mutable_representation_not_sendable.weft" 'error[E1004]: type `MutableOpaque` does not implement `Sendable`'
check_rejects "file_handle_constructor_private" "test/negative/file_handle_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "file_handle_record_fabrication" "test/negative/file_handle_record_fabrication.weft" "type error: not a record type"
check_rejects "file_handle_field_private" "test/negative/file_handle_field_private.weft" "type error: unknown field"
check_rejects "file_handle_raw_factory_private" "test/negative/file_handle_raw_factory_private.weft" "module member 'io_file_from_fd' is not visible in this import"
check_rejects "bytes_constructor_private" "test/negative/bytes_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "bytes_prefixed_constructor_removed" "test/negative/bytes_prefixed_constructor_removed.weft" "error[E4002]: unknown module member 'bytes_from_str' in import" 1
check_rejects "path_constructor_private" "test/negative/path_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "path_prefixed_constructor_removed" "test/negative/path_prefixed_constructor_removed.weft" "error[E4002]: unknown module member 'path_from_utf8' in import" 1
check_rejects "string_find_is_option" "test/negative/string_find_is_option.weft" 'return value type mismatch: expected `i64`, found `Option<i64>`'
check_rejects "json_bool_requires_bool" "test/negative/json_bool_requires_bool.weft" 'argument type mismatch: expected `bool`, found `i64`'
check_rejects "io_helper_effect_unavailable" "test/negative/io_helper_effect_unavailable.weft" "error[E2001]:"
check_rejects "io_helpers_module_retired" "test/negative/io_helpers_module_retired.weft" "error[E1001]: unknown function 'io_read_all_with'" 1
check_rejects "io_transfer_functions_retired" "test/negative/io_transfer_functions_retired.weft" "unknown module member" 3
check_rejects "io_progress_mirrors_retired" "test/negative/io_progress_mirrors_retired.weft" "unknown module member" 3
check_rejects "io_error_mirrors_retired" "test/negative/io_error_mirrors_retired.weft" "unknown module member" 5
check_rejects "file_prefixed_read_removed" "test/negative/file_prefixed_read_removed.weft" "error[E4002]: unknown module member 'file_read_all' in import" 1
check_rejects "file_read_cannot_write" "test/negative/file_read_cannot_write.weft" "error[E2001]:"
check_rejects "file_platform_wrappers_retired" "test/negative/file_platform_wrappers_retired.weft" "error[E4002]: unknown module member 'runtime_platform_file_read' in import" 4
check_rejects "dir_inspect_cannot_mutate" "test/negative/dir_inspect_cannot_mutate.weft" "error[E2001]:"
check_rejects "dir_platform_wrappers_retired" "test/negative/dir_platform_wrappers_retired.weft" "error[E4002]: unknown module member 'runtime_platform_dir_inspect' in import" 4
check_rejects "dir_prefixed_list_removed" "test/negative/dir_prefixed_list_removed.weft" "error[E4002]: unknown module member 'dir_list' in import" 1
check_rejects "console_cannot_write_file" "test/negative/console_cannot_write_file.weft" "error[E2001]:"
check_rejects "console_platform_wrappers_retired" "test/negative/console_platform_wrappers_retired.weft" "error[E4002]: unknown module member 'runtime_platform_console_read' in import" 4
check_rejects "safe_io_platform_residual_effect" "test/negative/safe_io_platform_residual_effect.weft" "error[E2001]:"
check_rejects "if_condition_not_bool" "test/negative/if_condition_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "while_condition_not_bool" "test/negative/while_condition_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "for_iter_non_list" "test/negative/for_iter_non_list.weft" "type error: for iterator requires an array, slice, Cons/Nil list, or IntoIterator"
check_rejects "not_operand_not_bool" "test/negative/not_operand_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "logical_operand_not_bool" "test/negative/logical_operand_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "match_guard_not_bool" "test/negative/match_guard_not_bool.weft" "type error: boolean expression is not bool"
check_rejects "operator_equality_mismatch" "test/negative/operator_equality_mismatch.weft" "type error: equality operand mismatch"
check_rejects "operator_bitwise_bool" "test/negative/operator_bitwise_bool.weft" "type error: bitwise operand is not i64"
check_rejects "operator_shift_bool" "test/negative/operator_shift_bool.weft" "type error: bitwise operand is not i64"
check_rejects "f64_i64_arithmetic_mismatch" "test/negative/f64_i64_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "f64_i64_comparison_mismatch" "test/negative/f64_i64_comparison_mismatch.weft" "type error: comparison operand type mismatch"
check_rejects "f64_bitwise" "test/negative/f64_bitwise.weft" "type error: bitwise operand is not i64"
check_rejects "f64_modulo" "test/negative/f64_modulo.weft" "type error: arithmetic operand is not i64"
check_rejects "f32_f64_arithmetic_mismatch" "test/negative/f32_f64_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "f32_i64_arithmetic_mismatch" "test/negative/f32_i64_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "f32_f64_comparison_mismatch" "test/negative/f32_f64_comparison_mismatch.weft" "type error: comparison operand type mismatch"
check_rejects "f32_f64_assignment_mismatch" "test/negative/f32_f64_assignment_mismatch.weft" 'error[E1002]: type annotation type mismatch: expected `f64`, found `f32`'
check_rejects "f32_bitwise" "test/negative/f32_bitwise.weft" "type error: bitwise operand is not i64"
check_rejects "f32_call_f64_arg_mismatch" "test/negative/f32_call_f64_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `f64`, found `f32`'
check_rejects "i32_i64_arithmetic_mismatch" "test/negative/i32_i64_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "i32_literal_out_of_range" "test/negative/i32_literal_out_of_range.weft" 'error[E1002]: integer literal does not fit expected type `i32`'
check_rejects "i64_positive_literal_out_of_range" "test/negative/i64_positive_literal_out_of_range.weft" 'error[E1002]: integer literal does not fit expected type `i64`'
check_rejects "untyped_integer_literal_out_of_range" "test/negative/untyped_integer_literal_out_of_range.weft" "type error: integer literal out of range"
check_rejects "i32_i64_assignment_mismatch" "test/negative/i32_i64_assignment_mismatch.weft" 'error[E1002]: type annotation type mismatch: expected `i32`, found `i64`'
check_rejects "i32_call_i64_arg_mismatch" "test/negative/i32_call_i64_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i32`, found `i64`'
check_rejects "i8_literal_out_of_range" "test/negative/i8_literal_out_of_range.weft" 'error[E1002]: integer literal does not fit expected type `i8`'
check_rejects "u8_negative_literal" "test/negative/u8_negative_literal.weft" 'error[E1002]: integer literal does not fit expected type `u8`'
check_rejects "u64_literal_out_of_range" "test/negative/u64_literal_out_of_range.weft" 'error[E1002]: integer literal does not fit expected type `u64`'
check_rejects "u64_return_literal_out_of_range" "test/negative/u64_return_literal_out_of_range.weft" 'error[E1002]: integer literal does not fit expected type `u64`'
check_rejects "u64_negative_literal" "test/negative/u64_negative_literal.weft" 'error[E1002]: integer literal does not fit expected type `u64`'
check_rejects "u64_pattern_literal_out_of_range" "test/negative/u64_pattern_literal_out_of_range.weft" "type error: literal pattern does not match scrutinee"
check_rejects "u8_i8_arithmetic_mismatch" "test/negative/u8_i8_arithmetic_mismatch.weft" "type error: arithmetic operand type mismatch"
check_rejects "u32_i32_comparison_mismatch" "test/negative/u32_i32_comparison_mismatch.weft" "type error: comparison operand type mismatch"
check_rejects "usize_i64_assignment_mismatch" "test/negative/usize_i64_assignment_mismatch.weft" 'error[E1002]: type annotation type mismatch: expected `usize`, found `i64`'
check_rejects "u8_call_i64_arg_mismatch" "test/negative/u8_call_i64_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `u8`, found `i64`'
check_rejects "intrinsic_i64_to_f64_arg_mismatch" "test/negative/intrinsic_i64_to_f64_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `f64`'
check_rejects "intrinsic_u64_to_f64_arg_mismatch" "test/negative/intrinsic_u64_to_f64_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `u64`, found `i64`'
check_rejects "num_to_i64_exact_wrong_receiver" "test/negative/num_to_i64_exact_wrong_receiver.weft" "type error: unknown method"
check_rejects "num_parse_f64_default_mismatch" "test/negative/num_parse_f64_default_mismatch.weft" 'error[E1002]: argument type mismatch: expected `f64`, found `str`'
check_rejects "num_parse_float_lane_mismatch" "test/negative/num_parse_float_lane_mismatch.weft" 'error[E1002]: type annotation type mismatch: expected `Result<f64, num.NumParseError>`, found `Result<f32, num.NumParseError>`'
check_rejects "intrinsic_f64_to_i64_arg_mismatch" "test/negative/intrinsic_f64_to_i64_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `f64`, found `i64`'
check_rejects "num_to_f64_receiver_mismatch" "test/negative/num_to_f64_receiver_mismatch.weft" "unknown method"
check_rejects "num_to_f32_round_receiver_mismatch" "test/negative/num_to_f32_round_receiver_mismatch.weft" "unknown method"
check_rejects "intrinsic_f32_to_f64_arg_mismatch" "test/negative/intrinsic_f32_to_f64_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `f32`, found `f64`'
check_rejects "intrinsic_f64_to_f32_arg_mismatch" "test/negative/intrinsic_f64_to_f32_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `f64`, found `i64`'
check_rejects "intrinsic_i16_to_f32_arg_mismatch" "test/negative/intrinsic_i16_to_f32_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i16`, found `u16`'
check_rejects "math_sqrt_f64_arg_mismatch" "test/negative/math_sqrt_f64_arg_mismatch.weft" "type error: unknown method"
check_rejects "math_sqrt_f32_arg_mismatch" "test/negative/math_sqrt_f32_arg_mismatch.weft" "type error: unknown method"
check_rejects "math_prefixed_surface_retired" "test/negative/math_prefixed_surface_retired.weft" "error[E4002]: unknown module member 'math_abs_f32' in import" 22
check_rejects "math_scalar_functions_retired" "test/negative/math_scalar_functions_retired.weft" "unknown module member" 16
check_rejects "utf8_prefixed_surface_retired" "test/negative/utf8_prefixed_surface_retired.weft" "unknown module member" 7
check_rejects "unicode_prefixed_surface_retired" "test/negative/unicode_prefixed_surface_retired.weft" "unknown module member" 56
check_rejects "iterator_free_functions_retired" "test/negative/iterator_free_functions_retired.weft" "unknown module member" 10
check_rejects "generator_functions_retired" "test/negative/generator_functions_retired.weft" "unknown module member" 8
check_rejects "channel_functions_retired" "test/negative/channel_functions_retired.weft" "unknown module member" 4
check_rejects "collection_constructors_retired" "test/negative/collection_constructors_retired.weft" "unknown module member" 4
check_rejects "map_iterator_helper_retired" "test/negative/map_iterator_helper_retired.weft" "module member" 1
check_rejects "vector_constructors_retired" "test/negative/vector_constructors_retired.weft" "module member" 4
check_rejects "state_surface_retired" "test/negative/state_surface_retired.weft" "unknown module member" 4
check_rejects "effect_interpreters_retired" "test/negative/effect_interpreters_retired.weft" "unknown module member" 2
check_rejects "ord_compare_retired" "test/negative/ord_compare_retired.weft" "unknown module member" 1
check_rejects "num_trait_forwarders_retired" "test/negative/num_trait_forwarders_retired.weft" "unknown module member" 9
check_rejects "num_value_functions_retired" "test/negative/num_value_functions_retired.weft" "unknown module member" 56
check_rejects "num_parse_functions_retired" "test/negative/num_parse_functions_retired.weft" "unknown module member" 6
check_rejects "mini_sql_grammar_retired" "test/negative/mini_sql_grammar_retired.weft" "unknown module member" 1
check_rejects "f64_table_prefixed_surface_retired" "test/negative/f64_table_prefixed_surface_retired.weft" "in import" 4
check_rejects "f64_table_constructor_private" "test/negative/f64_table_constructor_private.weft" "type error: opaque constructor is private to its declaring module; use an exported factory"
check_rejects "intrinsic_f64_sqrt_arg_mismatch" "test/negative/intrinsic_f64_sqrt_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `f64`, found `i64`'
check_rejects "intrinsic_f32_sqrt_arg_mismatch" "test/negative/intrinsic_f32_sqrt_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `f32`, found `i64`'
check_rejects "num_checked_cast_receiver_mismatch" "test/negative/num_checked_cast_receiver_mismatch.weft" "unknown method"
check_rejects "num_checked_cast_default_mismatch" "test/negative/num_checked_cast_default_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i8`, found `str`'
check_rejects "intrinsic_i64_to_i8_arg_mismatch" "test/negative/intrinsic_i64_to_i8_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `u64`'
check_rejects "intrinsic_u16_to_u64_arg_mismatch" "test/negative/intrinsic_u16_to_u64_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `u16`, found `f64`'
check_rejects "num_trait_bool_not_numeric" "test/negative/num_trait_bool_not_numeric.weft" "error[E1004]:"
check_rejects "num_trait_str_not_integer" "test/negative/num_trait_str_not_integer.weft" "error[E1004]:"
check_rejects "num_trait_float_not_integer" "test/negative/num_trait_float_not_integer.weft" "error[E1004]:"
check_rejects "num_trait_unsigned_not_signed" "test/negative/num_trait_unsigned_not_signed.weft" "error[E1004]:"
check_rejects "num_trait_signed_not_unsigned" "test/negative/num_trait_signed_not_unsigned.weft" "error[E1004]:"
check_rejects "unhandled_effect_in_if_condition" "test/negative/unhandled_effect_in_if_condition.weft" "error[E2001]:"
check_rejects "unhandled_effect_in_match_guard" "test/negative/unhandled_effect_in_match_guard.weft" "error[E2001]:"
check_rejects "assignment_unknown_target" "test/negative/assignment_unknown_target.weft" "error[E1001]: unknown identifier 'missing'"
check_rejects "assignment_i64_str_mismatch" "test/negative/assignment_i64_str_mismatch.weft" 'error[E1002]: assignment type mismatch: expected `i64`, found `str`'
check_rejects "assignment_str_i64_mismatch" "test/negative/assignment_str_i64_mismatch.weft" 'error[E1002]: assignment type mismatch: expected `str`, found `i64`'
check_rejects "assignment_bool_i64_mismatch" "test/negative/assignment_bool_i64_mismatch.weft" 'error[E1002]: assignment type mismatch: expected `bool`, found `i64`'
check_rejects "assignment_immutable_let" "test/negative/assignment_immutable_let.weft" "type error: cannot assign to immutable binding"
check_rejects "assignment_immutable_typed_let" "test/negative/assignment_immutable_typed_let.weft" "type error: cannot assign to immutable binding"
check_rejects "assignment_param_immutable" "test/negative/assignment_param_immutable.weft" "type error: cannot assign to immutable binding"
check_rejects "assignment_pattern_binding_immutable" "test/negative/assignment_pattern_binding_immutable.weft" "type error: cannot assign to immutable binding"
check_rejects "assignment_for_range_index" "test/negative/assignment_for_range_index.weft" "type error: cannot assign to immutable binding"
check_rejects "pointer_address_requires_unsafe" "test/negative/pointer_address_requires_unsafe.weft" "error[E2001]:"
check_rejects "pointer_deref_requires_unsafe" "test/negative/pointer_deref_requires_unsafe.weft" "error[E2001]:"
check_rejects "pointer_assignment_requires_unsafe" "test/negative/pointer_assignment_requires_unsafe.weft" "error[E2001]:"
check_rejects "imported_pointer_address_requires_trusted" "test/negative/imported_pointer_address_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "imported_pointer_deref_requires_trusted" "test/negative/imported_pointer_deref_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "imported_pointer_store_requires_trusted" "test/negative/imported_pointer_store_requires_trusted.weft" "type error: Unsafe is sealed to trusted runtime/platform code"
check_rejects "pointer_address_of_literal" "test/negative/pointer_address_of_literal.weft" "type error: address-of target must be a binding"
check_rejects "pointer_deref_non_pointer" "test/negative/pointer_deref_non_pointer.weft" "type error: dereference of non-pointer"
check_rejects "pointer_mut_address_of_immutable" "test/negative/pointer_mut_address_of_immutable.weft" "type error: cannot take mutable pointer to immutable binding"
check_rejects "pointer_value_to_param" "test/negative/pointer_value_to_param.weft" 'error[E1002]: argument type mismatch: expected `*i64`, found `i64`'
check_rejects "pointer_assignment_immutable" "test/negative/pointer_assignment_immutable.weft" "type error: cannot write through immutable pointer"
check_rejects "pointer_assignment_type_mismatch" "test/negative/pointer_assignment_type_mismatch.weft" 'error[E1002]: pointer assignment type mismatch: expected `i64`, found `str`'
check_rejects "pointer_assignment_non_pointer" "test/negative/pointer_assignment_non_pointer.weft" "type error: dereference of non-pointer"
check_rejects "rc_bind_non_rc" "test/negative/rc_bind_non_rc.weft" 'error[E1002]: type annotation type mismatch: expected `unknown`, found `i64`'
check_rejects "arc_public_param" "test/negative/arc_public_param.weft" "type error: arc is not public syntax"
check_rejects "arc_public_type_field" "test/negative/arc_public_type_field.weft" "type error: arc is not public syntax"
check_rejects "arc_public_let_annotation" "test/negative/arc_public_let_annotation.weft" "type error: arc is not public syntax"
check_rejects "arc_public_generic_arg" "test/negative/arc_public_generic_arg.weft" "type error: arc is not public syntax"
check_rejects "arc_public_vector_field" "test/negative/arc_public_vector_field.weft" "type error: arc is not public syntax"
check_rejects "rc_public_param" "test/negative/rc_public_param.weft" "type error: rc is not public syntax"
check_rejects "rc_public_type_field" "test/negative/rc_public_type_field.weft" "type error: rc is not public syntax"
check_rejects "rc_public_let_annotation" "test/negative/rc_public_let_annotation.weft" "type error: rc is not public syntax"
check_rejects "rc_public_generic_arg" "test/negative/rc_public_generic_arg.weft" "type error: rc is not public syntax"
check_rejects "rc_public_vector_field" "test/negative/rc_public_vector_field.weft" "type error: rc is not public syntax"
check_rejects "unique_param_used_twice" "test/negative/unique_param_used_twice.weft" "type error: unique value used more than once"
check_rejects "unique_let_used_twice" "test/negative/unique_let_used_twice.weft" "type error: unique value used more than once"
check_rejects "unique_closure_capture" "test/negative/unique_closure_capture.weft" "type error: unique value cannot be captured by closure"
check_rejects "unique_contextual_lambda_param_used_twice" "test/negative/unique_contextual_lambda_param_used_twice.weft" "type error: unique value used more than once"
check_rejects "unique_par_spawn_use_after_move" "test/negative/unique_par_spawn_use_after_move.weft" "type error: unique value used more than once"
check_rejects "owned_param_used_twice" "test/negative/owned_param_used_twice.weft" "type error: owned value used more than once"
check_rejects "owned_let_used_twice" "test/negative/owned_let_used_twice.weft" "type error: owned value used more than once"
check_rejects "owned_borrow_after_move" "test/negative/owned_borrow_after_move.weft" "type error: owned value used more than once"
check_rejects "linear_pattern_binding_used_twice" "test/negative/linear_pattern_binding_used_twice.weft" "type error: owned value used more than once"
check_rejects "linear_pattern_guard_consumes_binding" "test/negative/linear_pattern_guard_consumes_binding.weft" "type error: linear pattern binding cannot be consumed in a match guard"
check_rejects "linear_try_result_used_after_move" "test/negative/linear_try_result_used_after_move.weft" "type error: linear aggregate value used more than once"
check_rejects "owned_closure_capture" "test/negative/owned_closure_capture.weft" "type error: owned value cannot be captured by closure"
check_rejects "owned_plain_i64_requires_drop" "test/negative/owned_plain_i64_requires_drop.weft" "type error: owned type requires Drop resource conformance"
check_rejects "owned_inherent_drop_requires_trait" "test/negative/owned_inherent_drop_requires_trait.weft" "type error: owned type requires Drop resource conformance"
check_rejects "owned_drop_effect_unavailable" "test/negative/owned_drop_effect_unavailable.weft" "type error: owned Drop effect not available in caller"
check_rejects "owned_file_drop_effect_unavailable" "test/negative/owned_file_drop_effect_unavailable.weft" "type error: owned Drop effect not available in caller"
check_rejects "owned_record_field" "test/negative/owned_record_field.weft" "type error: owned type requires Drop resource conformance"
check_rejects "unique_record_field" "test/negative/unique_record_field.weft" "type error: Unique cannot be nested inside another storage shape"
check_rejects "owned_variant_payload" "test/negative/owned_variant_payload.weft" "type error: owned type requires Drop resource conformance"
check_rejects "owned_vector_field" "test/negative/owned_vector_field.weft" "type error: owned resource requires finite record, tuple, or tagged-variant storage; arbitrary containers remain unsupported"
check_rejects "owned_generic_param" "test/negative/owned_generic_param.weft" "type error: owned resource requires finite record, tuple, or tagged-variant storage; arbitrary containers remain unsupported"
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
check_rejects "weak_load_nullable_required" "test/negative/weak_load_nullable_required.weft" 'error[E1002]: type annotation type mismatch: expected `RuntimeRcProbe`, found `RuntimeRcProbe | nil`'
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
check_rejects "region_scoped_generator_escape" "test/negative/region_scoped_generator_escape.weft" "type error: region value cannot escape scoped arena"
check_rejects "region_scoped_iterator_escape" "test/negative/region_scoped_iterator_escape.weft" "type error: region value cannot escape scoped arena"
check_rejects "lambda_capture_mut_binding" "test/negative/lambda_capture_mut_binding.weft" "type error: cannot capture mut binding"
check_rejects "lambda_capture_mut_assignment" "test/negative/lambda_capture_mut_assignment.weft" "type error: cannot capture mut binding"
check_rejects "immediate_handler_mut_capture" "test/negative/immediate_handler_mut_capture.weft" "type error: cannot capture mut binding"
check_rejects "deferred_handler_outer_borrow_capture" "test/negative/deferred_handler_outer_borrow_capture.weft" "type error: borrowed resource cannot be captured by closure"
check_rejects "return_branch_type_mismatch" "test/negative/return_branch_type_mismatch.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `str`'
check_rejects "return_str_i64_mismatch" "test/negative/return_str_i64_mismatch.weft" 'error[E1002]: return value type mismatch: expected `str`, found `i64`'
check_rejects "unhandled_effect_in_return" "test/negative/unhandled_effect_in_return.weft" "error[E2001]:"
check_rejects "unhandled_effect_in_break" "test/negative/unhandled_effect_in_break.weft" "error[E2001]:"
check_rejects "contextual_lambda_return_stmt_mismatch" "test/negative/contextual_lambda_return_stmt_mismatch.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `str`'
check_rejects "let_bound_lambda_return_stmt_mismatch" "test/negative/let_bound_lambda_return_stmt_mismatch.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `str`'
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
check_rejects "deferred_k_alias_pass_arg" "test/negative/deferred_k_alias_pass_arg.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> i64`, found `continuation<i64, i64>`'
check_rejects "deferred_k_non_tail" "test/negative/deferred_k_non_tail.weft" "type error: continuation call must be tail position"
check_rejects "deferred_k_loop_non_tail" "test/negative/deferred_k_conditional_non_tail.weft" "type error: continuation call must be tail position"
check_rejects "deferred_k_arity" "test/negative/deferred_k_arity.weft" "type error: arity mismatch"
check_rejects "deferred_k_helper_multiple_use" "test/negative/deferred_k_helper_multiple_use.weft" "type error: continuation used more than once"
check_rejects "continuation_param_multiple_use" "test/negative/continuation_param_multiple_use.weft" "type error: continuation used more than once"
check_rejects "continuation_param_plain_function" "test/negative/continuation_param_plain_function.weft" 'error[E1002]: argument type mismatch: expected `(i64) -> i64`, found `continuation<i64, i64>`'
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
check_rejects "handler_clause_param_type_mismatch" "test/negative/handler_clause_param_type_mismatch.weft" 'error[E1002]: handler parameter type mismatch: expected `i64`, found `str`'
check_rejects "handler_clause_resume_type_mismatch" "test/negative/handler_clause_resume_type_mismatch.weft" 'error[E1002]: handler clause result type mismatch: expected `i64`, found `str`'
check_rejects "handler_clause_return_type_mismatch" "test/negative/handler_clause_return_type_mismatch.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `str`'
check_rejects "handler_clause_resume_capture_lambda" "test/negative/handler_clause_resume_capture_lambda.weft" "type error: cannot capture resume"
check_rejects "handler_clause_resume_capture_nested_lambda" "test/negative/handler_clause_resume_capture_nested_lambda.weft" "type error: cannot capture resume"
check_rejects "handler_clause_duplicate" "test/negative/handler_clause_duplicate.weft" "type error: duplicate handler clause"
check_rejects "handler_clause_missing_direct" "test/negative/handler_clause_missing_direct.weft" "type error: missing handler clause"
check_rejects "handler_clause_missing_branch" "test/negative/handler_clause_missing_branch.weft" "type error: missing handler clause"
check_rejects "module_handler_missing_operation" "test/negative/module_handler_missing_operation.weft" "type error: handler implementation is missing an effect operation"
check_rejects "module_handler_extra_operation" "test/negative/module_handler_extra_operation.weft" "type error: unknown effect operation in handler implementation"
check_rejects "module_handler_wrong_signature" "test/negative/module_handler_wrong_signature.weft" 'error[E1002]: handler parameter type mismatch: expected `i64`, found `str`'
check_rejects "module_handler_private" "test/negative/module_handler_private.weft" "type error: handler implementation is not visible from this module"
check_rejects "module_handler_effect_argument_mismatch" "test/negative/module_handler_effect_argument_mismatch.weft" "type error: handler implementation clause effect mismatch"
check_rejects "module_handler_duplicate_default" "test/negative/module_handler_duplicate_default.weft" "type error: duplicate module default for exact effect atom"
check_rejects "module_handler_escape" "test/negative/module_handler_escape.weft" "error[E1001]: unknown identifier 'basic_handler'"
check_rejects "module_handler_member_call_ambiguity" "test/negative/module_handler_member_call_ambiguity.weft" "expected '{' after handler configuration"
check_rejects "module_handler_generic_arity" "test/negative/module_handler_generic_arity.weft" "type error: wrong number of handler type arguments"
check_rejects "module_handler_constructor_type" "test/negative/module_handler_constructor_type.weft" 'error[E1002]: handler constructor argument type mismatch: expected `RuntimeRcProbe`, found `i64`'
check_rejects "resume_outside_handler" "test/negative/resume_outside_handler.weft" "type error: resume outside handler clause"
check_rejects "resume_outside_handler_lambda" "test/negative/resume_outside_handler_lambda.weft" "type error: resume outside handler clause"
check_rejects "generic_type_payload_mismatch" "test/negative/generic_type_payload_mismatch.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "generic_type_return_mismatch" "test/negative/generic_type_return_mismatch.weft" 'error[E1002]: type annotation type mismatch: expected `List<i64>`, found `List<str>`'
check_rejects "generic_type_constructor_arity" "test/negative/generic_type_constructor_arity.weft" "type error: arity mismatch"
check_rejects "generic_type_arg_count" "test/negative/generic_type_arg_count.weft" "type error: wrong number of type arguments"
check_rejects "generic_type_pattern_payload_mismatch" "test/negative/generic_type_pattern_payload_mismatch.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `str`'
check_rejects "narrowing_unguarded_nilable_use" "test/negative/narrowing_unguarded_nilable_use.weft" 'error[E1002]: argument type mismatch: expected `str`, found `str | nil`'
check_rejects "narrowing_mut_guard_not_narrowed" "test/negative/narrowing_mut_guard_not_narrowed.weft" 'error[E1002]: argument type mismatch: expected `str`, found `str | nil`'
check_rejects "generic_ctor_no_context" "test/negative/generic_ctor_no_context.weft" 'error[E1002]: return value type mismatch: expected `i64`, found `Opt<unknown>`'
check_rejects "generic_ctor_annotation_mismatch" "test/negative/generic_ctor_annotation_mismatch.weft" 'error[E1002]: type annotation type mismatch: expected `Opt<i64>`, found `Opt<str>`'
check_rejects "generic_ctor_conflicting_args" "test/negative/generic_ctor_conflicting_args.weft" 'error[E1002]: argument type mismatch: expected `i64`, found `str`'
check_rejects "qualified_ctor_call" "test/negative/qualified_ctor_call.weft" "type error: qualified constructor syntax is not supported"
check_rejects "qualified_ctor_nullary" "test/negative/qualified_ctor_nullary.weft" "type error: qualified constructor syntax is not supported"
check_rejects "interp_display_missing_impl" "test/negative/interp_display_missing_impl.weft" "implement Display for the interpolated type"
check_rejects "typed_match_untagged_union" "test/negative/typed_match_untagged_union.weft" "type error: typed match arm needs a runtime-discriminable union"
check_rejects "typed_match_non_exhaustive" "test/negative/typed_match_non_exhaustive.weft" 'error[E1003]: non-exhaustive match: value `nil` is not covered'
check_rejects "typed_match_foreign_annotation" "test/negative/typed_match_foreign_annotation.weft" "type error: typed match arm annotation is not part of the scrutinee type"
check_rejects "typed_match_nil_never" "test/negative/typed_match_nil_never.weft" "type error: nil match arm on a scrutinee that is never nil"
check_rejects "structural_record_duplicate_field" "test/negative/structural_record_duplicate_field.weft" "type error: duplicate structural record field"
check_rejects "structural_record_malformed" "test/negative/structural_record_malformed.weft" "type error: structural record type is malformed"
check_rejects "structural_record_width_reverse" "test/negative/structural_record_width_reverse.weft" 'error[E1002]: return value type mismatch: expected `{name: str, age: i64}`, found `{name: str, ..}`'
check_rejects "structural_record_missing_required" "test/negative/structural_record_missing_required.weft" 'error[E1002]: return value type mismatch: expected `{name: str, age: i64, ..}`, found `{name: str}`'
check_rejects "structural_record_depth_reverse" "test/negative/structural_record_depth_reverse.weft" 'error[E1002]: return value type mismatch: expected `{value: bool, ..}`, found `{value: i64}`'
check_rejects "structural_record_exact_extra" "test/negative/structural_record_exact_extra.weft" 'error[E1002]: return value type mismatch: expected `{name: str}`, found `{name: str, age: i64}`'
check_rejects "tuple_type_arity_mismatch" "test/negative/tuple_type_arity_mismatch.weft" 'error[E1002]: return value type mismatch: expected `(i64, str)`, found `(i64,)`'
check_rejects "tuple_type_depth_reverse" "test/negative/tuple_type_depth_reverse.weft" 'error[E1002]: return value type mismatch: expected `(bool, str)`, found `(i64, str)`'
check_rejects "tuple_position_out_of_bounds" "test/negative/tuple_position_out_of_bounds.weft" "type error: unknown tuple position"
check_rejects "tuple_position_named" "test/negative/tuple_position_named.weft" "type error: tuple positions use numeric labels"
check_rejects "record_numeric_field" "test/negative/record_numeric_field.weft" "type error: tuple position access on non-tuple record"
check_rejects "structural_result_exceeds_native_abi" "test/negative/structural_result_exceeds_native_abi.weft" "type error: result type exceeds 8-lane native ABI"
check_rejects "structural_effect_result_exceeds_native_abi" "test/negative/structural_effect_result_exceeds_native_abi.weft" "type error: result type exceeds 8-lane native ABI"
check_rejects "structural_generic_result_exceeds_native_abi" "test/negative/structural_generic_result_exceeds_native_abi.weft" "type error: result type exceeds 8-lane native ABI"
check_rejects "tuple_record_distinct" "test/negative/tuple_record_distinct.weft" 'error[E1002]: return value type mismatch: expected `{}`, found `()`'
check_rejects "anonymous_record_expr_duplicate" "test/negative/anonymous_record_expr_duplicate.weft" "type error: duplicate record field"
check_rejects "anonymous_record_expr_malformed" "test/negative/anonymous_record_expr_malformed.weft" "error[E0002]: expected ',' or '}' after structural record field"
check_rejects "anonymous_record_expr_arg_mismatch" "test/negative/anonymous_record_expr_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `{x: i64, y: i64}`, found `{x: i64, y: str}`'
check_rejects "anonymous_record_expr_missing_field" "test/negative/anonymous_record_expr_missing_field.weft" 'error[E1002]: argument type mismatch: expected `{x: i64, y: i64}`, found `{x: i64}`'
check_rejects "structural_complement_rejects_field" "test/negative/structural_complement_rejects_field.weft" 'error[E1002]: argument type mismatch: expected `{..} & ~{email: any, ..}`, found `{email: str}`'
check_rejects "diagnostic_report_wrong_type" "test/negative/diagnostic_report_wrong_type.weft" 'error[E1002]: argument type mismatch: expected `Diagnostic`, found `str`'
check_rejects "diagnostic_constructor_wrong_location" "test/negative/diagnostic_constructor_wrong_location.weft" 'error[E1002]: argument type mismatch: expected `schema.DiagnosticLocation`, found `i64`'
check_rejects "semantic_render_functions_retired" "test/negative/semantic_render_functions_retired.weft" "unknown module member" 3
check_rejects "tuple_expr_arg_mismatch" "test/negative/tuple_expr_arg_mismatch.weft" 'error[E1002]: argument type mismatch: expected `(i64, str)`, found `(i64, i64)`'
check_rejects "tuple_expr_singleton_requires_comma" "test/negative/tuple_expr_singleton_requires_comma.weft" 'error[E1002]: argument type mismatch: expected `(i64,)`, found `i64`'
check_rejects "record_pattern_duplicate_field" "test/negative/record_pattern_duplicate_field.weft" "type error: duplicate record pattern field"
check_rejects "record_pattern_unknown_field" "test/negative/record_pattern_unknown_field.weft" "type error: unknown record pattern field"
check_rejects "record_pattern_tuple_mismatch" "test/negative/record_pattern_tuple_mismatch.weft" "type error: record pattern does not match scrutinee"
check_rejects "tuple_pattern_record_mismatch" "test/negative/tuple_pattern_record_mismatch.weft" "type error: tuple pattern does not match scrutinee"
check_rejects "tuple_pattern_arity_mismatch" "test/negative/tuple_pattern_arity_mismatch.weft" "type error: tuple pattern arity mismatch"
check_rejects "record_pattern_malformed" "test/negative/record_pattern_malformed.weft" "error[E0002]: expected ',' or '}' after record pattern field"
check_rejects "tuple_pattern_malformed" "test/negative/tuple_pattern_malformed.weft" "error[E0002]: expected ')' after grouped pattern"
check_rejects "record_pattern_nested_untagged_union" "test/negative/record_pattern_nested_untagged_union.weft" "type error: typed match arm needs a runtime-discriminable union"
check_rejects "record_pattern_literal_mismatch" "test/negative/record_pattern_literal_mismatch.weft" "type error: literal pattern does not match scrutinee"
check_rejects "pattern_matrix_tuple_non_exhaustive" "test/negative/pattern_matrix_tuple_non_exhaustive.weft" 'error[E1003]: non-exhaustive match: value `(MatrixTupleOne, MatrixTupleOne)` is not covered'
check_rejects "pattern_matrix_record_non_exhaustive" "test/negative/pattern_matrix_record_non_exhaustive.weft" 'error[E1003]: non-exhaustive match: value `{item: nil}` is not covered'
check_rejects "pattern_matrix_nested_ctor_non_exhaustive" "test/negative/pattern_matrix_nested_ctor_non_exhaustive.weft" 'error[E1003]: non-exhaustive match: value `MatrixOuterWrap(MatrixInnerRight)` is not covered'
check_rejects "pattern_matrix_guard_non_exhaustive" "test/negative/pattern_matrix_guard_non_exhaustive.weft" 'error[E1003]: non-exhaustive match: value `(MatrixGuardZero, MatrixGuardZero)` is not covered'
check_rejects "pattern_matrix_duplicate_literal" "test/negative/pattern_matrix_duplicate_literal.weft" "type error: unreachable match arm"
check_rejects "pattern_matrix_duplicate_tuple" "test/negative/pattern_matrix_duplicate_tuple.weft" "type error: unreachable match arm"
check_rejects "pattern_matrix_duplicate_nested_ctor" "test/negative/pattern_matrix_duplicate_nested_ctor.weft" "type error: duplicate match constructor arm"
check_rejects "destructuring_let_refutable_constructor" "test/negative/destructuring_let_refutable_constructor.weft" "type error: refutable pattern in let binding; use if let or match"
check_rejects "destructuring_let_refutable_literal" "test/negative/destructuring_let_refutable_literal.weft" "type error: refutable pattern in let binding; use if let or match"
check_rejects "destructuring_let_refutable_nil" "test/negative/destructuring_let_refutable_nil.weft" "type error: refutable pattern in let binding; use if let or match"
check_rejects "destructuring_for_refutable_constructor" "test/negative/destructuring_for_refutable_constructor.weft" "type error: refutable pattern in for binding; use if let or match inside the loop"
check_rejects "destructuring_let_mutable" "test/negative/destructuring_let_mutable.weft" "error[E0003]: mutable destructuring bindings are not supported"
check_rejects "destructuring_let_annotation_mismatch" "test/negative/destructuring_let_annotation_mismatch.weft" 'error[E1002]: type annotation type mismatch: expected `(str, str)`, found `(i64, i64)`'
check_rejects "destructuring_let_tuple_arity" "test/negative/destructuring_let_tuple_arity.weft" "type error: tuple pattern arity mismatch"
check_rejects "structural_shape_missing_field" "test/negative/structural_shape_missing_field.weft" 'error[E1002]: argument type mismatch: expected `{answer: i64, ..}`, found `StructuralShapeMissing`'
check_rejects "structural_shape_wrong_field_type" "test/negative/structural_shape_wrong_field_type.weft" 'error[E1002]: argument type mismatch: expected `{answer: i64, ..}`, found `StructuralShapeWrong`'
check_rejects "structural_shape_closed_extra_nominal" "test/negative/structural_shape_closed_extra_nominal.weft" 'error[E1002]: argument type mismatch: expected `{answer: i64}`, found `StructuralShapeExtra`'
check_rejects "structural_shape_function_value" "test/negative/structural_shape_function_value.weft" "type error: shape-polymorphic function cannot cross an opaque function-value boundary"
check_rejects "structural_shape_indirect_adaptation" "test/negative/structural_shape_indirect_adaptation.weft" "type error: structural shape adaptation requires a direct function call"
check_rejects "structural_shape_generic_conflict" "test/negative/structural_shape_generic_conflict.weft" 'error[E1002]: argument type mismatch: expected `str`, found `i64`'
check_rejects "structural_update_duplicate_field" "test/negative/structural_update_duplicate_field.weft" "type error: duplicate record field"
check_rejects "structural_update_malformed" "test/negative/structural_update_malformed.weft" "error[E0002]: expected ',' or '}' after record update field"
check_rejects "structural_update_nonrecord" "test/negative/structural_update_nonrecord.weft" "type error: functional update requires a record value"
check_rejects "structural_update_open_shape" "test/negative/structural_update_open_shape.weft" "type error: functional update requires a concrete closed structural shape"
check_rejects "nominal_update_unknown_field" "test/negative/nominal_update_unknown_field.weft" "type error: unknown record field in functional update"
check_rejects "nominal_update_field_type_mismatch" "test/negative/nominal_update_field_type_mismatch.weft" 'error[E1002]: record update type mismatch: expected `i64`, found `str`'
check_rejects "nominal_update_duplicate_field" "test/negative/nominal_update_duplicate_field.weft" "type error: duplicate record field"
check_rejects "nominal_update_variant" "test/negative/nominal_update_variant.weft" "type error: functional update requires a record value"
check_rejects "structural_update_tuple" "test/negative/structural_update_tuple.weft" "type error: named-field functional update is not available on tuples"
check_rejects "array_length_negative" "test/negative/array_length_negative.weft" "type error: array length must be a non-negative compile-time integer literal"
check_rejects "array_length_symbolic" "test/negative/array_length_symbolic.weft" "type error: array length must be a non-negative compile-time integer literal"
check_rejects "array_length_overflow" "test/negative/array_length_overflow.weft" "type error: array length exceeds compiler integer range"
check_rejects "array_type_bad_shape" "test/negative/array_type_bad_shape.weft" "type error: array or slice type must be"
check_rejects "array_type_empty" "test/negative/array_type_empty.weft" "type error: array or slice type must be"
check_rejects "array_type_mut_fixed" "test/negative/array_type_mut_fixed.weft" "type error: fixed arrays cannot use mut in the element position"
check_rejects "array_length_mismatch" "test/negative/array_length_mismatch.weft" 'error[E1002]: return value type mismatch: expected `[i64; 3]`, found `[i64; 2]`'
check_rejects "array_covariance_reverse" "test/negative/array_covariance_reverse.weft" 'error[E1002]: return value type mismatch: expected `[bool; 2]`, found `[i64; 2]`'
check_rejects "slice_covariance_reverse" "test/negative/slice_covariance_reverse.weft" 'error[E1002]: return value type mismatch: expected `[bool]`, found `[i64]`'
check_rejects "mutable_slice_invariant" "test/negative/mutable_slice_invariant.weft" 'error[E1002]: return value type mismatch: expected `[mut i64]`, found `[mut bool]`'
check_rejects "mutable_slice_requires_reborrow" "test/negative/mutable_slice_requires_reborrow.weft" 'error[E1002]: return value type mismatch: expected `[i64]`, found `[mut i64]`'
check_rejects "array_literal_repetition_unsupported" "test/negative/array_literal_unsupported.weft" "error[E0003]: array repetition syntax is not supported; write every element"
check_rejects "array_literal_length_mismatch" "test/negative/array_literal_length_mismatch.weft" 'error[E1002]: return value type mismatch: expected `[i64; 3]`, found `[i64; 2]`'
check_rejects "array_literal_element_mismatch" "test/negative/array_literal_element_mismatch.weft" 'error[E1002]: return value type mismatch: expected `[u8; 2]`, found `[i64; 2]`'
check_rejects "array_literal_missing_comma" "test/negative/array_literal_missing_comma.weft" "error[E0002]: expected ',' or ']' in array literal"
check_rejects "array_literal_mixed_storage_union" "test/negative/array_literal_mixed_storage_union.weft" "type error: array element union has no uniform untagged storage; use a variant type"
check_rejects "array_len_unknown_field" "test/negative/array_len_unknown_field.weft" "type error: unknown indexed-storage field; arrays and slices expose .len"
check_rejects "slice_len_unknown_field" "test/negative/slice_len_unknown_field.weft" "type error: unknown indexed-storage field; arrays and slices expose .len"
check_rejects "index_non_indexed" "test/negative/index_non_indexed.weft" "type error: indexing requires an array or slice"
check_rejects "index_wrong_type" "test/negative/index_wrong_type.weft" "type error: index must be usize"
check_rejects "index_missing_close" "test/negative/index_missing_close.weft" "error[E0002]: expected ']' after index"
check_rejects "index_set_immutable_array" "test/negative/index_set_immutable_array.weft" "type error: cannot mutate immutable array binding"
check_rejects "index_set_immutable_slice" "test/negative/index_set_immutable_slice.weft" "type error: cannot mutate through immutable slice"
check_rejects "index_set_unnamed_container" "test/negative/index_set_unnamed_container.weft" "type error: indexed mutation requires a named container binding"
check_rejects "index_set_non_indexed" "test/negative/index_set_non_indexed.weft" "type error: indexed mutation requires an array or mutable slice"
check_rejects "index_set_wrong_index_type" "test/negative/index_set_wrong_index_type.weft" "type error: index must be usize"
check_rejects "index_set_value_mismatch" "test/negative/index_set_value_mismatch.weft" 'error[E1002]: indexed assignment type mismatch: expected `i64`, found `str`'
check_rejects "slice_non_indexed" "test/negative/slice_non_indexed.weft" "type error: slicing requires an array, slice, or Vector"
check_rejects "slice_start_wrong_type" "test/negative/slice_start_wrong_type.weft" "type error: slice bound must be usize"
check_rejects "slice_end_wrong_type" "test/negative/slice_end_wrong_type.weft" "type error: slice bound must be usize"
check_rejects "slice_missing_close" "test/negative/slice_missing_close.weft" "error[E0002]: expected ']' after slice"
check_rejects "slice_mutable_immutable_array" "test/negative/slice_mutable_immutable_array.weft" "type error: cannot mutably slice immutable array binding"
check_rejects "slice_mutable_reborrow_immutable" "test/negative/slice_mutable_reborrow_immutable.weft" "type error: cannot mutably reborrow immutable slice"
check_rejects "slice_temporary_array_owner" "test/negative/slice_temporary_array_owner.weft" "type error: slicing an owning container temporary requires a named owner binding"
check_rejects "slice_array_temporary_call" "test/negative/slice_array_temporary_call.weft" "type error: slice provenance is unknown at escape"
check_rejects "slice_local_return_direct" "test/negative/slice_local_return_direct.weft" "type error: slice borrow escapes its owner"
check_rejects "slice_local_return_binding" "test/negative/slice_local_return_binding.weft" "type error: slice borrow escapes its owner"
check_rejects "slice_aggregate_return" "test/negative/slice_aggregate_return.weft" "type error: slice-containing aggregate cannot escape its borrow scope"
check_rejects "slice_local_closure_capture" "test/negative/slice_local_closure_capture.weft" "type error: slice borrow cannot be captured by an escaping closure"
check_rejects "slice_par_mutable_worker" "test/negative/slice_par_mutable_worker.weft" "type error: mutable slice cannot cross a scoped Par boundary"
check_rejects "sendable_bound_mutable_vector" "test/negative/sendable_bound_mutable_vector.weft" 'error[E1004]: type `Vector<i64>` does not implement `Sendable`'
check_rejects "sendable_bound_nested_mutable" "test/negative/sendable_bound_nested_mutable.weft" 'error[E1004]: type `SendableEnvelope<Vector<i64>>` does not implement `Sendable`'
check_rejects "sendable_bound_function_requires_value" "test/negative/sendable_bound_function_requires_value.weft" 'error[E1004]: type `(i64) -> i64` does not implement `Sendable`'
check_rejects "sendable_bound_slice_requires_scope" "test/negative/sendable_bound_slice_requires_scope.weft" 'error[E1004]: type `[i64]` does not implement `Sendable`'
check_rejects "sendable_par_worker_mutable_state_capture" "test/negative/sendable_par_worker_mutable_state_capture.weft" "type error: closure capture is not Sendable across scoped Par"
check_rejects "sendable_reserved_trait" "test/negative/sendable_reserved_trait.weft" "type error: Sendable is reserved as a sealed structural predicate"
check_rejects "sendable_sealed_impl" "test/negative/sendable_sealed_impl.weft" "type error: Sendable is a sealed structural predicate and cannot be implemented"
check_rejects "slice_par_permission_does_not_leak" "test/negative/slice_par_permission_does_not_leak.weft" "type error: slice borrow cannot be captured by an escaping closure"
check_rejects "slice_par_map_requires_scope" "test/negative/slice_par_map_requires_scope.weft" "type error: slice borrow cannot be captured by an escaping closure"
check_rejects "slice_escaping_closure_capture" "test/negative/slice_escaping_closure_capture.weft" "type error: escaping closure cannot capture a slice borrow"
check_rejects "slice_immutable_then_mutable_overlap" "test/negative/slice_immutable_then_mutable_overlap.weft" "type error: slice borrow conflicts with a live exclusive borrow"
check_rejects "slice_owner_mutation_while_borrowed" "test/negative/slice_owner_mutation_while_borrowed.weft" "type error: mutation conflicts with a live slice borrow"
check_rejects "slice_owner_access_while_mutable" "test/negative/slice_owner_access_while_mutable.weft" "type error: access conflicts with a live mutable slice borrow"
check_rejects "slice_parent_access_while_reborrowed" "test/negative/slice_parent_access_while_reborrowed.weft" "type error: access conflicts with a live mutable slice borrow"
check_rejects "slice_opaque_function_return" "test/negative/slice_opaque_function_return.weft" "type error: slice provenance is unknown at escape"
check_rejects "vector_slice_reallocation_while_live" "test/negative/vector_slice_reallocation_while_live.weft" "type error: Vector mutation or reallocation conflicts with a live slice borrow"
check_rejects "vector_slice_alias_reallocation_while_live" "test/negative/vector_slice_alias_reallocation_while_live.weft" "type error: Vector mutation or reallocation conflicts with a live slice borrow"
check_rejects "vector_mutable_slice_owner_access" "test/negative/vector_mutable_slice_owner_access.weft" "type error: Vector access conflicts with a live mutable slice borrow"
check_rejects "vector_slice_unknown_call_while_live" "test/negative/vector_slice_unknown_call_while_live.weft" "type error: Vector mutation or reallocation conflicts with a live slice borrow"
check_rejects "vector_slice_local_return" "test/negative/vector_slice_local_return.weft" "type error: slice borrow escapes its owner"
check_rejects "vector_slice_temporary_owner" "test/negative/vector_slice_temporary_owner.weft" "type error: slicing an owning container temporary requires a named owner binding"
check_rejects "vector_to_array_missing_length" "test/negative/vector_to_array_missing_length.weft" "error[E0002]: to_array length must be a non-negative integer literal"
check_rejects "vector_to_array_non_literal_length" "test/negative/vector_to_array_non_literal_length.weft" "error[E0002]: to_array length must be a non-negative integer literal"
check_rejects "vector_to_array_negative_length" "test/negative/vector_to_array_negative_length.weft" "error[E0002]: to_array length must be a non-negative integer literal"
check_rejects "vector_to_array_type_mismatch" "test/negative/vector_to_array_type_mismatch.weft" "type error: to_array result type must be"
check_rejects "vector_to_array_non_vector" "test/negative/vector_to_array_non_vector.weft" "type error: unknown method"
check_rejects "vector_mutable_slice_to_array_access" "test/negative/vector_mutable_slice_to_array_access.weft" "type error: Vector access conflicts with a live mutable slice borrow"
check_rejects "slice_effect_handler_state" "test/negative/slice_effect_handler_state.weft" "type error: slice borrow cannot enter effect handler state"
check_rejects "slice_overlapping_mutable_arguments" "test/negative/slice_overlapping_mutable_arguments.weft" "type error: call arguments contain overlapping mutable slice borrows"
check_rejects "slice_reassign_borrow" "test/negative/slice_reassign_borrow.weft" "type error: cannot reassign a binding that carries a slice borrow"
check_rejects "effect_type_args_arity" "test/negative/effect_type_args_arity.weft" "type error: effect type argument count mismatch"
check_rejects "effect_generic_bare_use" "test/negative/effect_generic_bare_use.weft" "type error: effect type argument count mismatch"
check_rejects "effect_type_args_wrong_count" "test/negative/effect_type_args_wrong_count.weft" "type error: effect type argument count mismatch"
check_rejects "effect_instantiation_mismatch" "test/negative/effect_instantiation_mismatch.weft" 'error[E2001]: effect `Box<str>` is not available in this context'
check_rejects "effect_try_instantiation_mismatch" "test/negative/effect_try_instantiation_mismatch.weft" "error[E2001]:"
check_rejects "effect_unqualified_perform_ambiguous" "test/negative/effect_unqualified_perform_ambiguous.weft" "type error: ambiguous effect atom; qualify the operation"
check_rejects "effect_unqualified_handler_ambiguous" "test/negative/effect_unqualified_handler_ambiguous.weft" "type error: ambiguous handler effect atom; qualify the clause"
check_rejects "effect_qualified_perform_mismatch" "test/negative/effect_qualified_perform_mismatch.weft" 'error[E2001]: effect `Box<i64>` is not available in this context'
check_rejects "effect_qualified_handler_mismatch" "test/negative/effect_qualified_handler_mismatch.weft" 'error[E2001]: effect `Box<str>` is not available in this context'
check_rejects "effect_perform_arg_instantiation_mismatch" "test/negative/effect_perform_arg_instantiation_mismatch.weft" 'error[E1002]: argument type mismatch: expected `str`, found `i64`'
check_rejects "effect_resume_instantiation_mismatch" "test/negative/effect_resume_instantiation_mismatch.weft" 'error[E1002]: handler clause result type mismatch: expected `str`, found `i64`'
check_rejects "handler_two_return_clauses" "test/negative/handler_two_return_clauses.weft" "error[E0002]: at most one return clause per handler"
check_rejects "trait_complement_surface" "test/negative/trait_complement_surface.weft" "type error: trait complement is not a surface type"
check_rejects "import_cycle" "test/negative/import_cycle.weft" "error[E4001]: circular import: test/negative/import_cycle -> test/negative/import_cycle_helper -> test/negative/import_cycle"
check_rejects "import_cycle_direct" "test/negative/import_cycle_direct.weft" "error[E4001]: circular import: test/negative/import_cycle_direct -> test/negative/import_cycle_direct"
check_rejects "call_site_label_unsupported" "test/negative/call_site_label_unsupported.weft" "error[E0003]: call-site argument labels are not supported yet"
check_rejects "rigid_tail_concrete_perform" "test/negative/rigid_tail_concrete_perform.weft" "error[E2001]:"
check_rejects "rigid_tail_concrete_call" "test/negative/rigid_tail_concrete_call.weft" "error[E2001]:"
check_rejects "borrow_return_position" "test/negative/borrow_return_position.weft" "type error: borrow is only valid on callable parameters"
check_rejects "borrow_local_position" "test/negative/borrow_local_position.weft" "type error: borrow is only valid on callable parameters"
check_rejects "borrow_field_position" "test/negative/borrow_field_position.weft" "type error: borrow is only valid on callable parameters"
check_rejects "borrow_non_resource" "test/negative/borrow_non_resource.weft" "type error: borrow requires an owned resource type"
check_rejects "borrow_nested_ownership" "test/negative/borrow_nested_ownership.weft" "type error: borrow cannot wrap another ownership qualifier"
check_rejects "borrow_temporary_actual" "test/negative/borrow_temporary_actual.weft" "type error: resource borrow requires a named owned binding"
check_rejects "borrow_mut_immutable_owner" "test/negative/borrow_mut_immutable_owner.weft" "type error: exclusive resource borrow requires a mutable owner binding"
check_rejects "borrow_shared_to_exclusive" "test/negative/borrow_shared_to_exclusive.weft" "type error: shared resource borrow cannot be forwarded as exclusive"
check_rejects "borrow_actual_type_mismatch" "test/negative/borrow_actual_type_mismatch.weft" 'error[E1002]: borrowed argument type mismatch: expected `BorrowExpectedToken`, found `BorrowActualToken`'
check_rejects "borrow_conflicting_call" "test/negative/borrow_conflicting_call.weft" "type error: conflicting resource borrows in one call"
check_rejects "borrow_escape_to_owned" "test/negative/borrow_escape_to_owned.weft" 'error[E1002]: argument type mismatch: expected `owned BorrowEscapeToken`, found `borrow BorrowEscapeToken`'
check_rejects "borrow_pattern_extract_owned" "test/negative/borrow_pattern_extract_owned.weft" 'error[E1002]: return value type mismatch: expected `owned BorrowPatternToken`, found `borrow BorrowPatternToken`'
check_rejects "borrow_mut_method_immutable_owner" "test/negative/borrow_mut_method_immutable_owner.weft" "type error: exclusive resource borrow requires a mutable owner binding"
check_rejects "borrow_effect_conflicting_perform" "test/negative/borrow_effect_conflicting_perform.weft" "type error: conflicting resource borrows in one call" 1
check_rejects "borrow_effect_deferred_continuation" "test/negative/borrow_effect_deferred_continuation.weft" "type error: borrowed effect parameter cannot enter a deferred continuation" 1
check_rejects "borrow_closure_capture" "test/negative/borrow_closure_capture.weft" "type error: borrowed resource cannot be captured by closure" 1
check_rejects "borrow_par_spawn_capture" "test/negative/borrow_par_spawn_capture.weft" "type error: borrowed resource cannot be captured by closure" 1

if [ "$CENSUS_ONLY" -eq 1 ]; then
  echo "$JOB_N"
  exit 0
fi

BATCH_OUTPUT=$(mktemp /tmp/weft_negative_batch_XXXXXX)
trap 'rm -f "$BATCH_OUTPUT"' EXIT
set +e
"$WEFT" check --jobs "$WEFT_TEST_JOBS" "${FILES[@]}" > /dev/null 2> "$BATCH_OUTPUT"
BATCH_STATUS=$?
set -e

# The compiler's canonical root headers make the human diagnostic stream a
# deterministic sequence without sacrificing the exact rendered messages
# these regressions pin.
SECTION=-1
NEXT_SECTION=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$NEXT_SECTION" -lt "$JOB_N" ] && [ "$line" = "==> ${FILES[$NEXT_SECTION]} <==" ]; then
    SECTION=$NEXT_SECTION
    NEXT_SECTION=$((NEXT_SECTION+1))
  elif [ "$SECTION" -ge 0 ]; then
    OUTPUTS[$SECTION]="${OUTPUTS[$SECTION]}${line}"$'\n'
  else
    ERRORS="$ERRORS\n  batch checker emitted output before the first root boundary"
  fi
done < "$BATCH_OUTPUT"

if [ "$NEXT_SECTION" -ne "$JOB_N" ]; then
  ERRORS="$ERRORS\n  batch checker returned $NEXT_SECTION of $JOB_N root sections (exit $BATCH_STATUS)"
fi

ji=0
while [ "$ji" -lt "$JOB_N" ]; do
  name=${NAMES[$ji]}
  pattern=${PATTERNS[$ji]}
  expected_errors=${EXPECTED_ERRORS[$ji]}
  out=${OUTPUTS[$ji]}
  diagnostic_match=0
  if [[ "$out" == *"$pattern"* ]]; then diagnostic_match=1; fi
  exact_errors=1
  if [ -n "$expected_errors" ] && [[ "$out" != *"check: "*" $expected_errors errors"* ]]; then exact_errors=0; fi
  if [ "$diagnostic_match" -eq 1 ] && [ "$exact_errors" -eq 1 ]; then
    echo "  ✓ $name"
    PASS=$((PASS+1))
  else
    echo "  ✗ $name"
    FAIL=$((FAIL+1))
    if [ -n "$expected_errors" ]; then
      ERRORS="$ERRORS\n  $name: expected diagnostic '$pattern' with exactly $expected_errors checker error(s)"
    else
      ERRORS="$ERRORS\n  $name: expected diagnostic '$pattern'"
    fi
  fi
  ji=$((ji+1))
done
rm -f "$BATCH_OUTPUT"
trap - EXIT

echo ""
echo "=== Negative Summary ==="
echo "$PASS passed, $FAIL failed"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
