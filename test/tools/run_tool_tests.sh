#!/bin/bash
# Tool boundary tests: parse-only, check-only, and AST tool paths.
set -e

WEFT=${WEFT:-./weft}
WEFT_TEST_COMPILE_TIMEOUT=${WEFT_TEST_COMPILE_TIMEOUT:-120}
WEFT_TEST_RUN_TIMEOUT=${WEFT_TEST_RUN_TIMEOUT:-120}
WEFT_TEST_RUNAWAY_RSS_LIMIT_KB=${WEFT_TEST_RUNAWAY_RSS_LIMIT_KB:-16000000}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-$WEFT_TEST_RUNAWAY_RSS_LIMIT_KB}
WEFT_TEST_RUN_RSS_LIMIT_KB=${WEFT_TEST_RUN_RSS_LIMIT_KB:-1000000}
PROJECT_ROOT=$(pwd)
case "$WEFT" in
  /*) WEFT_ABS="$WEFT" ;;
  *) WEFT_ABS="$(pwd)/$WEFT" ;;
esac
tmp_src=$(mktemp /tmp/weft_tool_src_XXXXXX)
tmp_import="module_fixtures/_weft_tool_import_$$.weft"
tmp_bin=$(mktemp /tmp/weft_tool_bin_XXXXXX)
tmp_err=$(mktemp /tmp/weft_tool_err_XXXXXX)
tmp_out=$(mktemp /tmp/weft_tool_out_XXXXXX)
tmp_tool_obj=$(mktemp /tmp/weft_tool_runner_obj_XXXXXX)
tmp_tool_bin=$(mktemp /tmp/weft_tool_runner_bin_XXXXXX)
tmp_fake_weft=$(mktemp /tmp/weft_tool_fake_weft_XXXXXX)
tmp_test_fail_one=$(mktemp /tmp/weft_tool_test_fail_one_XXXXXX.weft)
tmp_test_fail_two=$(mktemp /tmp/weft_tool_test_fail_two_XXXXXX.weft)
tmp_test_after=$(mktemp /tmp/weft_tool_test_after_XXXXXX.weft)
tmp_test_timeout=$(mktemp /tmp/weft_tool_test_timeout_XXXXXX.weft)
tmp_test_parse_fail=$(mktemp /tmp/weft_tool_a_parse_fail_XXXXXX.weft)
tmp_test_shared_one=$(mktemp /tmp/weft_tool_shared_one_XXXXXX.weft)
tmp_test_shared_two=$(mktemp /tmp/weft_tool_shared_two_XXXXXX.weft)
tmp_check_clean=$(mktemp /tmp/weft_tool_check_clean_XXXXXX.weft)
tmp_check_fail=$(mktemp /tmp/weft_tool_check_fail_XXXXXX.weft)
tmp_rc_census_src=$(mktemp /tmp/weft_tool_rc_census_XXXXXX.weft)
tmp_test_shared_module="_weft_tool_test_shared_$$"
tmp_test_shared_support="module_fixtures/${tmp_test_shared_module}.weft"
tmp_test_dir=$(mktemp -d /tmp/weft_tool_test_dir_XXXXXX)
tmp_check_dir=$(mktemp -d /tmp/weft_tool_check_dir_XXXXXX)
tmp_fmt_dir=$(mktemp -d /tmp/weft_tool_fmt_dir_XXXXXX)
tmp_pkg_dir=$(mktemp -d /tmp/weft_tool_pkg_XXXXXX)
tmp_pkg_cli_dir=$(mktemp -d /tmp/weft_tool_pkg_cli_XXXXXX)
tmp_pkg_lock_dir=$(mktemp -d /tmp/weft_tool_pkg_lock_XXXXXX)
tmp_pkg_trust_dir=$(mktemp -d /tmp/weft_tool_pkg_trust_XXXXXX)
tmp_pkg_missing_dir=$(mktemp -d /tmp/weft_tool_pkg_missing_XXXXXX)
tmp_outside_dir=$(mktemp -d /tmp/weft_tool_outside_XXXXXX)
tmp_lsp_stream_dir=$(mktemp -d /tmp/weft_tool_lsp_stream_XXXXXX)
tmp_tree_sitter_grammar=$(mktemp /tmp/weft_tool_tree_sitter_grammar_XXXXXX)
tmp_tree_sitter_grammar_second=$(mktemp /tmp/weft_tool_tree_sitter_grammar_second_XXXXXX)
tmp_tree_sitter_generator=$(mktemp /tmp/weft_tool_tree_sitter_generator_XXXXXX)
tmp_elf_generator=$(mktemp /tmp/weft_tool_elf_generator_XXXXXX)
tmp_elf_product=$(mktemp /tmp/weft_tool_elf_product_XXXXXX)
tmp_elf_product_second=$(mktemp /tmp/weft_tool_elf_product_second_XXXXXX)
tmp_native_debug_dir=$(mktemp -d /tmp/weft_tool_native_debug_XXXXXX)
chmod 755 "$tmp_native_debug_dir"
tmp_native_debug_bin="$tmp_native_debug_dir/native_forward"
tmp_native_debug_lldb=$(mktemp /tmp/weft_tool_native_debug_lldb_XXXXXX)
tmp_compiler_probe="compiler/_weft_trust_probe_$$.weft"
tmp_runtime_probe="runtime/_weft_trust_probe_$$.weft"
tmp_stdlib_probe="stdlib/_weft_trust_probe_$$.weft"
trap 'rm -f "$tmp_src" "$tmp_import" "$tmp_bin" "$tmp_err" "$tmp_out" "$tmp_tool_obj" "$tmp_tool_bin" "$tmp_fake_weft" "$tmp_test_fail_one" "$tmp_test_fail_two" "$tmp_test_after" "$tmp_test_timeout" "$tmp_test_parse_fail" "$tmp_test_shared_one" "$tmp_test_shared_two" "$tmp_test_shared_support" "$tmp_check_clean" "$tmp_check_fail" "$tmp_rc_census_src" "$tmp_tree_sitter_grammar" "$tmp_tree_sitter_grammar_second" "$tmp_tree_sitter_generator" "$tmp_elf_generator" "$tmp_elf_product" "$tmp_elf_product_second" "$tmp_native_debug_lldb" "$tmp_compiler_probe" "$tmp_runtime_probe" "$tmp_stdlib_probe"; rm -rf "$tmp_pkg_dir" "$tmp_pkg_cli_dir" "$tmp_pkg_lock_dir" "$tmp_pkg_trust_dir" "$tmp_pkg_missing_dir" "$tmp_outside_dir" "$tmp_test_dir" "$tmp_check_dir" "$tmp_fmt_dir" "$tmp_lsp_stream_dir" "$tmp_native_debug_dir"' EXIT

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

run_weft_compile_guarded() {
  run_guarded "$WEFT_TEST_COMPILE_TIMEOUT" "$WEFT_TEST_COMPILE_RSS_LIMIT_KB" "$@"
}

run_binary_guarded() {
  run_guarded "$WEFT_TEST_RUN_TIMEOUT" "$WEFT_TEST_RUN_RSS_LIMIT_KB" "$@"
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  ok $name"
  else
    echo "  fail $name"
    echo "    expected to contain: $needle"
    exit 1
  fi
}

assert_equals() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ok $name"
  else
    echo "  fail $name"
    echo "    expected: $expected"
    echo "    actual: $actual"
    exit 1
  fi
}

# Stable diagnostic payloads are additive inside each legacy summary item.
# Existing goldens still pin every pre-v1 summary byte through this adapter;
# dedicated wire goldens below pin the complete typed value itself.
strip_mcp_diagnostic_payloads() {
  local input="$1"
  local marker=',"diagnostic":'
  local marker_len=${#marker}
  local input_len=${#input}
  local output=""
  local i=0

  while [ "$i" -lt "$input_len" ]; do
    if [[ "${input:i:marker_len}" == "$marker" ]]; then
      i=$((i + marker_len))
      if [[ "${input:i:1}" != "{" ]]; then
        echo "malformed diagnostic payload in MCP snapshot" >&2
        return 1
      fi
      local depth=0
      local in_string=0
      local escaped=0
      while [ "$i" -lt "$input_len" ]; do
        local ch="${input:i:1}"
        if [ "$in_string" -eq 1 ]; then
          if [ "$escaped" -eq 1 ]; then
            escaped=0
          elif [[ "$ch" == "\\" ]]; then
            escaped=1
          elif [[ "$ch" == '"' ]]; then
            in_string=0
          fi
        else
          if [[ "$ch" == '"' ]]; then
            in_string=1
          elif [[ "$ch" == "{" ]]; then
            depth=$((depth + 1))
          elif [[ "$ch" == "}" ]]; then
            depth=$((depth - 1))
            if [ "$depth" -eq 0 ]; then
              i=$((i + 1))
              break
            fi
          fi
        fi
        i=$((i + 1))
      done
      if [ "$depth" -ne 0 ] || [ "$in_string" -ne 0 ]; then
        echo "unterminated diagnostic payload in MCP snapshot" >&2
        return 1
      fi
    else
      output+="${input:i:1}"
      i=$((i + 1))
    fi
  done
  printf '%s' "$output"
}

assert_equals_without_diagnostic_payload() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  local legacy
  legacy=$(strip_mcp_diagnostic_payloads "$actual") || exit 1
  assert_equals "$name" "$legacy" "$expected"
}

assert_files_equal() {
  local name="$1"
  local actual="$2"
  local expected="$3"
  if cmp -s "$actual" "$expected"; then
    echo "  ok $name"
  else
    echo "  fail $name"
    echo "    files differ: $actual != $expected"
    exit 1
  fi
}

assert_not_equals() {
  local name="$1"
  local actual="$2"
  local unexpected="$3"
  if [[ "$actual" != "$unexpected" ]]; then
    echo "  ok $name"
  else
    echo "  fail $name"
    echo "    unexpected equality: $actual"
    exit 1
  fi
}

pkg_lock_digest() {
  local json="$1"
  local name="$2"
  local tail=${json#*\"name\":\"$name\"}
  tail=${tail#*\"content\":\"}
  printf '%s' "${tail%%\"*}"
}

assert_not_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  fail $name"
    echo "    unexpected content: $needle"
    exit 1
  else
    echo "  ok $name"
  fi
}

assert_not_contains_file() {
  local name="$1"
  local file="$2"
  local needle="$3"
  if grep -q "$needle" "$file"; then
    echo "  fail $name"
    echo "    unexpected stderr: $needle"
    exit 1
  else
    echo "  ok $name"
  fi
}

lsp_frame() {
  local body="$1"
  local len
  len=$(printf '%s' "$body" | LC_ALL=C wc -c)
  len=${len//[[:space:]]/}
  printf 'Content-Length: %s\r\n\r\n%s' "$len" "$body"
}

json_escape_bytes() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

assert_test_exit_code() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local exit_code
  printf '%s\n' "$source" > "$tmp_src"
  run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
  chmod +x "$tmp_bin"
  set +e
  run_binary_guarded "$tmp_bin" >/dev/null 2>&1
  exit_code=$?
  set -e
  if [ "$exit_code" -eq "$expected" ]; then
    echo "  ok $name"
  else
    echo "  fail $name"
    echo "    expected exit code: $expected"
    echo "    actual exit code: $exit_code"
    exit 1
  fi
}

assert_test_failure_contains() {
  local name="$1"
  local source="$2"
  local expected="$3"
  local needle="$4"
  local exit_code
  local err
  printf '%s\n' "$source" > "$tmp_src"
  run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
  chmod +x "$tmp_bin"
  set +e
  run_binary_guarded "$tmp_bin" >/dev/null 2>"$tmp_err"
  exit_code=$?
  set -e
  err=$(<"$tmp_err")
  if [ "$exit_code" -ne "$expected" ]; then
    echo "  fail $name"
    echo "    expected exit code: $expected"
    echo "    actual exit code: $exit_code"
    exit 1
  fi
  assert_contains "$name" "$err" "$needle"
}

assert_test_compile_rejects() {
  local name="$1"
  local source="$2"
  local pattern="$3"
  local out
  printf '%s\n' "$source" > "$tmp_src"
  out=$(run_weft_compile_guarded "$WEFT" test < "$tmp_src" 2>&1 >/dev/null || true)
  assert_contains "$name" "$out" "$pattern"
}

assert_program_failure_contains() {
  local name="$1"
  local source_path="$2"
  local expected_exit="$3"
  local expected_stderr="$4"
  local exit_code
  local err
  run_weft_compile_guarded "$WEFT" compile "$source_path" > "$tmp_bin" 2>"$tmp_err"
  chmod +x "$tmp_bin"
  set +e
  run_binary_guarded "$tmp_bin" >/dev/null 2>"$tmp_err"
  exit_code=$?
  set -e
  err=$(<"$tmp_err")
  assert_equals "${name}_exit" "$exit_code" "$expected_exit"
  assert_contains "${name}_stderr" "$err" "$expected_stderr"
}

write_large_padding() {
  local file="$1"
  : > "$file"
  for ((i = 0; i < 1800; i++)); do
    printf -- '-- padding padding padding padding padding padding padding padding padding padding\n' >> "$file"
  done
}

write_huge_padding() {
  local file="$1"
  : > "$file"
  printf -- '-- ' >> "$file"
  for ((i = 0; i < 15000; i++)); do
    printf -- 'padding padding padding padding padding padding padding padding padding padding ' >> "$file"
  done
  printf '\n' >> "$file"
}

printf 'fn main() -> i64 { 42 }\n' > "$tmp_src"

set +e
"$WEFT" explain E1002 > "$tmp_out" 2> "$tmp_err"
explain_exit=$?
set -e
assert_equals "explain_known_code_exits_zero" "$explain_exit" "0"
assert_equals "explain_known_code_stderr_empty" "$(<"$tmp_err")" ""
explain_out=$(<"$tmp_out")
assert_contains "explain_known_code_prints_heading" "$explain_out" "E1002 [type]"
assert_contains "explain_known_code_prints_registry_summary" "$explain_out" "expression does not match the expected type"
assert_contains "explain_known_code_teaches_cause" "$explain_out" "What happened:"
assert_contains "explain_known_code_teaches_fix" "$explain_out" "How to fix:"
assert_contains "explain_known_code_includes_example" "$explain_out" "Example:"

set +e
"$WEFT" explain E9999 > "$tmp_out" 2> "$tmp_err"
explain_unknown_exit=$?
set -e
assert_equals "explain_unknown_code_exits_one" "$explain_unknown_exit" "1"
assert_equals "explain_unknown_code_stdout_empty" "$(<"$tmp_out")" ""
assert_contains "explain_unknown_code_is_actionable" "$(<"$tmp_err")" "unknown diagnostic code: E9999"

set +e
"$WEFT" explain > "$tmp_out" 2> "$tmp_err"
explain_missing_exit=$?
set -e
assert_equals "explain_missing_code_exits_usage" "$explain_missing_exit" "2"
assert_contains "explain_missing_code_prints_usage" "$(<"$tmp_err")" "usage: weft explain CODE"

set +e
"$WEFT" explain E1002 extra > "$tmp_out" 2> "$tmp_err"
explain_extra_exit=$?
set -e
assert_equals "explain_extra_arg_exits_usage" "$explain_extra_exit" "2"
assert_contains "explain_extra_arg_prints_usage" "$(<"$tmp_err")" "usage: weft explain CODE"

printf '%s\n' '--- Returns the checked answer.' 'pub fn answer(value: i64) -> i64 { value }' 'fn hidden() -> i64 { 0 }' > "$tmp_src"
set +e
"$WEFT" doc "$tmp_src" > "$tmp_out" 2> "$tmp_err"
doc_exit=$?
set -e
assert_equals "doc_checked_module_exits_zero" "$doc_exit" "0"
assert_equals "doc_checked_module_stderr_empty" "$(<"$tmp_err")" ""
doc_out=$(<"$tmp_out")
assert_contains "doc_checked_module_names_source" "$doc_out" "# API: \`$tmp_src\`"
assert_contains "doc_checked_module_marks_fact_origin" "$doc_out" "Generated from checked semantic facts"
assert_contains "doc_checked_module_reports_coverage" "$doc_out" "Public API items: 1. Documented: 1."
assert_contains "doc_checked_module_attaches_comment" "$doc_out" "Returns the checked answer."
assert_contains "doc_checked_module_renders_signature" "$doc_out" "pub fn answer(value: i64) -> i64"
assert_not_contains "doc_checked_module_omits_private" "$doc_out" "hidden"

printf '%s\n' '--- The public answer.' 'pub const ANSWER: i64 = 42' 'const PRIVATE: i64 = 7' 'fn main() -> i64 { ANSWER }' > "$tmp_src"
"$WEFT" doc "$tmp_src" > "$tmp_out" 2> "$tmp_err"
assert_equals "doc_constant_stderr_empty" "$(<"$tmp_err")" ""
assert_contains "doc_constant_has_distinct_heading" "$(<"$tmp_out")" '## Constant `ANSWER`'
assert_contains "doc_constant_renders_typed_signature" "$(<"$tmp_out")" 'pub const ANSWER: i64'
assert_not_contains "doc_constant_omits_private" "$(<"$tmp_out")" 'PRIVATE'

set +e
"$WEFT" doc stdlib/result.weft > "$tmp_out" 2> "$tmp_err"
doc_stdlib_exit=$?
set -e
assert_equals "doc_stdlib_facade_constituent_exits_zero" "$doc_stdlib_exit" "0"
assert_equals "doc_stdlib_facade_constituent_stderr_empty" "$(<"$tmp_err")" ""
doc_stdlib_out=$(<"$tmp_out")
assert_contains "doc_stdlib_facade_constituent_names_api" "$doc_stdlib_out" '# API: `stdlib/result.weft`'
assert_contains "doc_stdlib_facade_constituent_renders_checked_variant" "$doc_stdlib_out" $'pub type Result<T, E> {\n  Ok(T),\n  Err(E)\n}'

# Every module in the frozen stdlib reference island must remain complete;
# adding an exported member without adjacent `---` prose fails immediately.
stdlib_doc_modules=(
  stdlib/assert.weft stdlib/default.weft stdlib/display.weft stdlib/drop.weft
  stdlib/eq.weft stdlib/hash.weft stdlib/ord.weft stdlib/panic.weft
  stdlib/list.weft stdlib/option.weft stdlib/result.weft stdlib/fail.weft
  stdlib/maybe.weft stdlib/bytes.weft stdlib/path.weft stdlib/io_types.weft
  stdlib/console.weft stdlib/file.weft stdlib/dir.weft stdlib/unicode.weft
  stdlib/test.weft stdlib/math.weft stdlib/time.weft stdlib/json.weft
  stdlib/secure_random.weft stdlib/net_address.weft stdlib/idna.weft
  stdlib/dns.weft stdlib/tcp.weft
  stdlib/state.weft stdlib/diagnostic_type.weft stdlib/diagnostic.weft
  stdlib/diagnostic_registry.weft stdlib/map.weft stdlib/set.weft
  stdlib/sorted_map.weft stdlib/sorted_set.weft stdlib/vector_type.weft
  stdlib/vector.weft stdlib/generator.weft stdlib/iter.weft
  stdlib/semantic_type.weft stdlib/semantic_type_render.weft
  stdlib/f64_table.weft stdlib/num.weft stdlib/io_helpers.weft
  stdlib/utf8.weft stdlib/string.weft
  stdlib/io.weft stdlib/par.weft stdlib/cancellation.weft
  stdlib/shutdown.weft stdlib/channel.weft stdlib/spawn.weft
)
for stdlib_doc_module in "${stdlib_doc_modules[@]}"; do
  stdlib_doc_name=${stdlib_doc_module#stdlib/}
  stdlib_doc_name=${stdlib_doc_name%.weft}
  set +e
  "$WEFT" doc "$stdlib_doc_module" > "$tmp_out" 2> "$tmp_err"
  stdlib_doc_exit=$?
  set -e
  assert_equals "doc_stdlib_${stdlib_doc_name}_exits_zero" "$stdlib_doc_exit" "0"
  assert_equals "doc_stdlib_${stdlib_doc_name}_stderr_empty" "$(<"$tmp_err")" ""
  stdlib_doc_coverage=$(grep -m1 '^Public API items:' "$tmp_out" || true)
  if [[ "$stdlib_doc_coverage" =~ ^Public\ API\ items:\ ([0-9]+)\.\ Documented:\ ([0-9]+)\.$ ]]; then
    assert_equals "doc_stdlib_${stdlib_doc_name}_fully_documented" "${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}"
  else
    echo "  fail doc_stdlib_${stdlib_doc_name}_coverage_shape"
    echo "    actual: $stdlib_doc_coverage"
    exit 1
  fi
  # These audited facades must not regrow legacy runtime mechanics.
  if [ "$stdlib_doc_name" = "utf8" ]; then
    assert_contains "doc_stdlib_utf8_pins_public_surface" "$(<"$tmp_out")" "Public API items: 12. Documented: 12."
  elif [ "$stdlib_doc_name" = "io_helpers" ]; then
    assert_contains "doc_stdlib_io_helpers_pins_public_surface" "$(<"$tmp_out")" "Public API items: 3. Documented: 3."
  elif [ "$stdlib_doc_name" = "string" ]; then
    assert_contains "doc_stdlib_string_pins_public_surface" "$(<"$tmp_out")" "Public API items: 17. Documented: 17."
  elif [ "$stdlib_doc_name" = "net_address" ]; then
    assert_contains "doc_stdlib_net_address_pins_public_surface" "$(<"$tmp_out")" "Public API items: 23. Documented: 23."
  elif [ "$stdlib_doc_name" = "idna" ]; then
    assert_contains "doc_stdlib_idna_pins_public_surface" "$(<"$tmp_out")" "Public API items: 15. Documented: 15."
  elif [ "$stdlib_doc_name" = "dns" ]; then
    assert_contains "doc_stdlib_dns_pins_public_surface" "$(<"$tmp_out")" "Public API items: 25. Documented: 25."
    assert_contains "doc_stdlib_dns_policy_preserves_authority_fact" "$(<"$tmp_out")" "pub fn dns_with_policy<T, E>(policy: DnsPolicy, body: () -[DnsResolve, E]> T) -[DnsResolve, E]> T"
  elif [ "$stdlib_doc_name" = "tcp" ]; then
assert_contains "doc_stdlib_tcp_pins_public_surface" "$(<"$tmp_out")" "Public API items: 83. Documented: 83."
    assert_contains "doc_stdlib_tcp_connect_preserves_owned_authority_fact" "$(<"$tmp_out")" "pub fn tcp_connect(address: SocketAddress, options: TcpConnectOptions) -[TcpConnect]> Result<owned TcpStream, TcpError>"
    assert_contains "doc_stdlib_tcp_connect_policy_preserves_authority_fact" "$(<"$tmp_out")" "pub fn tcp_connect_with_policy<T, E>(policy: TcpConnectPolicy, body: () -[TcpConnect, E]> T) -[TcpConnect, E]> T"
    assert_contains "doc_stdlib_tcp_listen_policy_preserves_authority_fact" "$(<"$tmp_out")" "pub fn tcp_listen_with_policy<T, E>(policy: TcpListenPolicy, body: () -[TcpListen, E]> T) -[TcpListen, E]> T"
  elif [ "$stdlib_doc_name" = "channel" ]; then
    assert_contains "doc_stdlib_channel_pins_public_surface" "$(<"$tmp_out")" "Public API items: 21. Documented: 21."
    assert_contains "doc_stdlib_channel_pins_sendable_effect" "$(<"$tmp_out")" "pub effect Channel<T: Sendable>"
    assert_contains "doc_stdlib_channel_pins_bounded_send" "$(<"$tmp_out")" "pub fn channel_send<T: Sendable>(value: T) -[Channel<T>]> ChannelSend<T>"
  elif [ "$stdlib_doc_name" = "spawn" ]; then
    assert_contains "doc_stdlib_spawn_pins_public_surface" "$(<"$tmp_out")" "Public API items: 13. Documented: 13."
    assert_contains "doc_stdlib_spawn_pins_channel_handler" "$(<"$tmp_out")" "pub fn with_event_loop_channel<C: Sendable, T, E>(capacity: ChannelCapacity<C>, body: () -[Spawn, Time, TcpReadiness, Channel<C>, E]> T) -[E]> T"
    assert_contains "doc_stdlib_spawn_pins_shutdown_handler" "$(<"$tmp_out")" "pub fn with_event_loop_shutdown<T, E>(body: () -[Spawn, Time, TcpReadiness, Cancellation, Fail<CancellationReason>, E]> T) -[E]> CancellationOutcome<T>"
    assert_contains "doc_stdlib_spawn_pins_channel_shutdown_handler" "$(<"$tmp_out")" "pub fn with_event_loop_channel_shutdown<C: Sendable, T, E>(capacity: ChannelCapacity<C>, body: () -[Spawn, Time, TcpReadiness, Channel<C>, Cancellation, Fail<CancellationReason>, E]> T) -[E]> CancellationOutcome<T>"
  elif [ "$stdlib_doc_name" = "cancellation" ]; then
    assert_contains "doc_stdlib_cancellation_pins_public_surface" "$(<"$tmp_out")" "Public API items: 20. Documented: 20."
  elif [ "$stdlib_doc_name" = "shutdown" ]; then
    assert_contains "doc_stdlib_shutdown_pins_public_surface" "$(<"$tmp_out")" "Public API items: 3. Documented: 3."
  elif [ "$stdlib_doc_name" = "io" ] || [ "$stdlib_doc_name" = "par" ]; then
    assert_contains "doc_stdlib_${stdlib_doc_name}_pins_public_surface" "$(<"$tmp_out")" "Public API items: 8. Documented: 8."
  fi
done

# Package plumbing and generated Unicode tables deliberately expose no public
# API. Pinning every zero-public module closes the other half of the reference
# tripwire: none can silently sprout an undocumented alpha contract.
internal_stdlib_modules=(
  continuation
  prelude
  process
  test_report
  thread
  unicode_case_data
  unicode_compatibility_data
  unicode_idna_data
  unicode_property_data
  unicode_security
  unicode_segmentation
  unicode_segmentation_data
  unsafe
)
for internal_stdlib_module in "${internal_stdlib_modules[@]}"; do
  set +e
  "$WEFT" doc "stdlib/${internal_stdlib_module}.weft" > "$tmp_out" 2> "$tmp_err"
  internal_stdlib_exit=$?
  set -e
  assert_equals "doc_${internal_stdlib_module}_internal_module_exits_zero" "$internal_stdlib_exit" "0"
  assert_equals "doc_${internal_stdlib_module}_internal_module_stderr_empty" "$(<"$tmp_err")" ""
  assert_contains "doc_${internal_stdlib_module}_internal_module_has_no_public_api" "$(<"$tmp_out")" "Public API items: 0. Documented: 0."
done

printf 'pub fn broken(\n' > "$tmp_src"
set +e
"$WEFT" doc "$tmp_src" > "$tmp_out" 2> "$tmp_err"
doc_parse_exit=$?
set -e
assert_equals "doc_parse_failure_exits_one" "$doc_parse_exit" "1"
assert_equals "doc_parse_failure_stdout_empty" "$(<"$tmp_out")" ""
assert_contains "doc_parse_failure_preserves_diagnostic" "$(<"$tmp_err")" "error[E0002]"
assert_contains "doc_parse_failure_reports_summary" "$(<"$tmp_err")" "doc: parse failed with"

printf 'pub fn bad() -> i64 { "wrong" }\n' > "$tmp_src"
set +e
"$WEFT" doc "$tmp_src" > "$tmp_out" 2> "$tmp_err"
doc_type_exit=$?
set -e
assert_equals "doc_type_failure_exits_one" "$doc_type_exit" "1"
assert_equals "doc_type_failure_stdout_empty" "$(<"$tmp_out")" ""
assert_contains "doc_type_failure_preserves_diagnostic" "$(<"$tmp_err")" "error[E1002]"
assert_contains "doc_type_failure_reports_summary" "$(<"$tmp_err")" "doc: type check failed with"

set +e
"$WEFT" doc "$tmp_src.missing" > "$tmp_out" 2> "$tmp_err"
doc_missing_path_exit=$?
set -e
assert_equals "doc_missing_path_exits_one" "$doc_missing_path_exit" "1"
assert_equals "doc_missing_path_stdout_empty" "$(<"$tmp_out")" ""
assert_contains "doc_missing_path_is_actionable" "$(<"$tmp_err")" "doc: could not read input file"

set +e
"$WEFT" doc > "$tmp_out" 2> "$tmp_err"
doc_missing_arg_exit=$?
set -e
assert_equals "doc_missing_arg_exits_usage" "$doc_missing_arg_exit" "2"
assert_contains "doc_missing_arg_prints_usage" "$(<"$tmp_err")" "usage: weft doc PATH"

set +e
"$WEFT" doc "$tmp_src" extra > "$tmp_out" 2> "$tmp_err"
doc_extra_arg_exit=$?
set -e
assert_equals "doc_extra_arg_exits_usage" "$doc_extra_arg_exit" "2"
assert_contains "doc_extra_arg_prints_usage" "$(<"$tmp_err")" "usage: weft doc PATH"

"$WEFT" compile tools/tree_sitter_grammar.weft > "$tmp_tree_sitter_generator" 2> "$tmp_err"
chmod +x "$tmp_tree_sitter_generator"
assert_equals "tree_sitter_generator_build_stderr_empty" "$(<"$tmp_err")" ""
"$tmp_tree_sitter_generator" > "$tmp_tree_sitter_grammar" 2> "$tmp_err"
assert_equals "tree_sitter_generator_run_stderr_empty" "$(<"$tmp_err")" ""
assert_contains "tree_sitter_grammar_marks_generated_source" "$(<"$tmp_tree_sitter_grammar")" '@generated by tools/tree_sitter_grammar.weft; do not edit'
assert_contains "tree_sitter_grammar_has_source_file" "$(<"$tmp_tree_sitter_grammar")" 'source_file: $ => repeat(choice($._declaration, $.stray_closing_brace))'
"$tmp_tree_sitter_generator" > "$tmp_tree_sitter_grammar_second" 2> "$tmp_err"
assert_files_equal "tree_sitter_grammar_is_deterministic" "$tmp_tree_sitter_grammar" "$tmp_tree_sitter_grammar_second"

run_weft_compile_guarded "$WEFT" compile tools/elf_linux_aarch64_smoke.weft > "$tmp_elf_generator" 2> "$tmp_err"
chmod +x "$tmp_elf_generator"
assert_equals "elf_linux_aarch64_generator_build_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product" 2> "$tmp_err"
assert_equals "elf_linux_aarch64_generator_run_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product_second" 2> "$tmp_err"
assert_files_equal "elf_linux_aarch64_product_is_deterministic" "$tmp_elf_product" "$tmp_elf_product_second"
elf_file=$(/usr/bin/file -b "$tmp_elf_product")
assert_contains "elf_linux_aarch64_file_reports_architecture" "$elf_file" "ARM aarch64"
assert_contains "elf_linux_aarch64_file_reports_static_linkage" "$elf_file" "statically linked"
elf_headers=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --file-headers --private-headers "$tmp_elf_product")
assert_contains "elf_linux_aarch64_has_little_endian_format" "$elf_headers" "file format elf64-littleaarch64"
assert_contains "elf_linux_aarch64_has_aarch64_architecture" "$elf_headers" "architecture: aarch64"
assert_contains "elf_linux_aarch64_has_exact_entry" "$elf_headers" "start address: 0x0000000000401000"
assert_contains "elf_linux_aarch64_load_is_read_execute" "$elf_headers" "flags r-x"
assert_contains "elf_linux_aarch64_stack_is_read_write" "$elf_headers" "flags rw-"
assert_not_contains "elf_linux_aarch64_has_no_interpreter" "$elf_headers" "INTERP off"
assert_not_contains "elf_linux_aarch64_has_no_dynamic_segment" "$elf_headers" "DYNAMIC off"
elf_disassembly=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --disassemble "$tmp_elf_product")
assert_contains "elf_linux_aarch64_sets_exit_status" "$elf_disassembly" $'mov\tx0, #0x2a'
assert_contains "elf_linux_aarch64_sets_exit_syscall" "$elf_disassembly" $'mov\tx8, #0x5d'
assert_contains "elf_linux_aarch64_invokes_linux_svc" "$elf_disassembly" $'svc\t#0'

# The real target path must lower ordinary Weft source through the shared
# NativeModule -> LinkPlan -> LinkGraph pipeline, not only package a hand-built
# instruction fixture. It remains Darwin-hosted here; Linux execution is the
# target-local product gate in brief 1e.
run_weft_compile_guarded "$WEFT" compile tools/elf_linux_aarch64_pipeline_smoke.weft > "$tmp_elf_generator" 2> "$tmp_err"
chmod +x "$tmp_elf_generator"
assert_equals "elf_linux_pipeline_generator_build_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product" 2> "$tmp_err"
assert_equals "elf_linux_pipeline_generator_run_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product_second" 2> "$tmp_err"
assert_files_equal "elf_linux_pipeline_product_is_deterministic" "$tmp_elf_product" "$tmp_elf_product_second"
elf_pipeline_file=$(/usr/bin/file -b "$tmp_elf_product")
assert_contains "elf_linux_pipeline_file_reports_architecture" "$elf_pipeline_file" "ARM aarch64"
assert_contains "elf_linux_pipeline_file_reports_static_linkage" "$elf_pipeline_file" "statically linked"
elf_pipeline_headers=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --file-headers --private-headers "$tmp_elf_product")
assert_contains "elf_linux_pipeline_has_little_endian_format" "$elf_pipeline_headers" "file format elf64-littleaarch64"
assert_contains "elf_linux_pipeline_has_exact_entry" "$elf_pipeline_headers" "start address: 0x0000000000401000"
assert_contains "elf_linux_pipeline_load_is_read_execute" "$elf_pipeline_headers" "flags r-x"
assert_contains "elf_linux_pipeline_stack_is_read_write" "$elf_pipeline_headers" "flags rw-"
assert_not_contains "elf_linux_pipeline_has_no_interpreter" "$elf_pipeline_headers" "INTERP off"
assert_not_contains "elf_linux_pipeline_has_no_dynamic_segment" "$elf_pipeline_headers" "DYNAMIC off"
elf_pipeline_disassembly=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --disassemble "$tmp_elf_product")
assert_contains "elf_linux_pipeline_reads_argc_from_initial_stack" "$elf_pipeline_disassembly" $'ldr\tx25, [sp]'
assert_contains "elf_linux_pipeline_selects_mmap_syscall" "$elf_pipeline_disassembly" $'mov\tx8, #0xde'
assert_contains "elf_linux_pipeline_selects_anonymous_private_map" "$elf_pipeline_disassembly" $'mov\tx3, #0x22'
assert_contains "elf_linux_pipeline_invokes_linux_svc" "$elf_pipeline_disassembly" $'svc\t#0'
assert_contains "elf_linux_pipeline_compiles_main_result" "$elf_pipeline_disassembly" $'mov\tx8, #0x2a'
assert_contains "elf_linux_pipeline_selects_exit_group" "$elf_pipeline_disassembly" $'mov\tx8, #0x5e'

# Fatal reporting is the first target-neutral runtime capability: its semantic
# write/exit operations lower independently of arbitrary raw syscall numbers.
run_weft_compile_guarded "$WEFT" compile tools/elf_linux_aarch64_panic_smoke.weft > "$tmp_elf_generator" 2> "$tmp_err"
chmod +x "$tmp_elf_generator"
assert_equals "elf_linux_panic_generator_build_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product" 2> "$tmp_err"
assert_equals "elf_linux_panic_generator_run_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product_second" 2> "$tmp_err"
assert_files_equal "elf_linux_panic_product_is_deterministic" "$tmp_elf_product" "$tmp_elf_product_second"
assert_contains "elf_linux_panic_product_is_static" "$(/usr/bin/file -b "$tmp_elf_product")" "statically linked"
elf_linux_panic_disassembly=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --disassemble "$tmp_elf_product")
elf_linux_panic_headers=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --private-headers "$tmp_elf_product")
assert_contains "elf_linux_panic_selects_write" "$elf_linux_panic_disassembly" $'mov\tx8, #0x40'
assert_contains "elf_linux_panic_selects_exit_group" "$elf_linux_panic_disassembly" $'mov\tx8, #0x5e'
assert_contains "elf_linux_panic_invokes_linux_svc" "$elf_linux_panic_disassembly" $'svc\t#0'
assert_contains "elf_linux_panic_uses_aarch64_max_page_alignment" "$elf_linux_panic_headers" "align 2**16"
assert_contains "elf_linux_panic_maps_compiler_zero_fill_rw" "$elf_linux_panic_headers" "memsz 0x0000000000000010 flags rw-"

# Typed console input stays at the ConsoleRead effect surface while the sealed
# bridge selects Linux read(63). The generated product remains a standalone
# static image; target-local execution is covered by brief 1e's Docker gate.
run_weft_compile_guarded "$WEFT" compile tools/elf_linux_aarch64_console_read_smoke.weft > "$tmp_elf_generator" 2> "$tmp_err"
chmod +x "$tmp_elf_generator"
assert_equals "elf_linux_console_read_generator_build_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product" 2> "$tmp_err"
assert_equals "elf_linux_console_read_generator_run_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product_second" 2> "$tmp_err"
assert_files_equal "elf_linux_console_read_product_is_deterministic" "$tmp_elf_product" "$tmp_elf_product_second"
assert_contains "elf_linux_console_read_product_is_static" "$(/usr/bin/file -b "$tmp_elf_product")" "statically linked"
elf_linux_console_read_disassembly=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --disassemble "$tmp_elf_product")
elf_linux_console_read_headers=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --private-headers "$tmp_elf_product")
assert_contains "elf_linux_console_read_selects_read" "$elf_linux_console_read_disassembly" $'mov\tx8, #0x3f'
assert_contains "elf_linux_console_read_selects_exit_group" "$elf_linux_console_read_disassembly" $'mov\tx8, #0x5e'
assert_contains "elf_linux_console_read_invokes_linux_svc" "$elf_linux_console_read_disassembly" $'svc\t#0'
assert_not_contains "elf_linux_console_read_has_no_interpreter" "$elf_linux_console_read_headers" "INTERP off"
assert_not_contains "elf_linux_console_read_has_no_dynamic_segment" "$elf_linux_console_read_headers" "DYNAMIC off"

# Typed standard output selects only ConsoleWrite policy; both stream variants
# and unbuffered flush live above the sealed Linux write(64) leaf.
run_weft_compile_guarded "$WEFT" compile tools/elf_linux_aarch64_console_write_smoke.weft > "$tmp_elf_generator" 2> "$tmp_err"
chmod +x "$tmp_elf_generator"
assert_equals "elf_linux_console_write_generator_build_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product" 2> "$tmp_err"
assert_equals "elf_linux_console_write_generator_run_stderr_empty" "$(<"$tmp_err")" ""
run_binary_guarded "$tmp_elf_generator" > "$tmp_elf_product_second" 2> "$tmp_err"
assert_files_equal "elf_linux_console_write_product_is_deterministic" "$tmp_elf_product" "$tmp_elf_product_second"
assert_contains "elf_linux_console_write_product_is_static" "$(/usr/bin/file -b "$tmp_elf_product")" "statically linked"
elf_linux_console_write_disassembly=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --disassemble "$tmp_elf_product")
elf_linux_console_write_headers=$(/Library/Developer/CommandLineTools/usr/bin/llvm-objdump --private-headers "$tmp_elf_product")
assert_contains "elf_linux_console_write_selects_write" "$elf_linux_console_write_disassembly" $'mov\tx8, #0x40'
assert_contains "elf_linux_console_write_selects_exit_group" "$elf_linux_console_write_disassembly" $'mov\tx8, #0x5e'
assert_contains "elf_linux_console_write_invokes_linux_svc" "$elf_linux_console_write_disassembly" $'svc\t#0'
assert_not_contains "elf_linux_console_write_has_no_interpreter" "$elf_linux_console_write_headers" "INTERP off"
assert_not_contains "elf_linux_console_write_has_no_dynamic_segment" "$elf_linux_console_write_headers" "DYNAMIC off"

printf 'fn main() -> i64 { 42 }\n' > "$tmp_src"
fmt_out=$("$WEFT" fmt < "$tmp_src" 2>"$tmp_err")
assert_contains "fmt_parse_only" "$fmt_out" "fn main() -> i64 { 42 }"
assert_equals "fmt_snapshot_exact" "$fmt_out" "fn main() -> i64 { 42 }"
assert_equals "fmt_valid_stderr_empty" "$(<"$tmp_err")" ""

fmt_path_out=$("$WEFT" fmt "$tmp_src" 2>"$tmp_err")
assert_equals "fmt_path_snapshot_exact" "$fmt_path_out" "fn main() -> i64 { 42 }"
assert_equals "fmt_path_stderr_empty" "$(<"$tmp_err")" ""

printf '%s\n' 'pub   const ANSWER:i64=40+2' 'fn main()->i64{ANSWER}' > "$tmp_src"
"$WEFT" fmt "$tmp_src" > "$tmp_out" 2> "$tmp_err"
assert_equals "fmt_constant_snapshot_exact" "$(<"$tmp_out")" $'pub const ANSWER: i64 = 40 + 2\n\nfn main() -> i64 { ANSWER }'
"$WEFT" fmt "$tmp_out" > "$tmp_bin" 2> "$tmp_err"
assert_files_equal "fmt_constants_are_idempotent" "$tmp_bin" "$tmp_out"

printf '%s\n' 'fn   πρόσθεση ( α : i64, β: i64 ) -> i64 { α + β }' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_preserves_unicode_identifier_identity" "$(<"$tmp_out")" 'fn πρόσθεση(α: i64, β: i64) -> i64 { α + β }'
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_unicode_identifiers_are_idempotent" "$tmp_bin" "$tmp_out"

printf '%s\n' '-- leading  text' 'fn   main ( )  ->  i64   {  42  } -- trailing  text' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_canonical_horizontal_gaps_and_comments" "$(<"$tmp_out")" $'-- leading  text\n\nfn main() -> i64 { 42 } -- trailing  text'
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_canonical_horizontal_idempotent" "$tmp_bin" "$tmp_out"
"$WEFT" compile < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
"$WEFT" compile < "$tmp_out" > "$tmp_tool_obj" 2>"$tmp_err"
chmod +x "$tmp_bin" "$tmp_tool_obj"
set +e
run_binary_guarded "$tmp_bin" >/dev/null 2>"$tmp_err"
fmt_original_status=$?
run_binary_guarded "$tmp_tool_obj" >/dev/null 2>"$tmp_err"
fmt_formatted_status=$?
set -e
assert_equals "fmt_canonical_native_equivalent" "$fmt_original_status:$fmt_formatted_status" "42:42"

printf 'fn id < T > (x: T) -> T { x }\nfn main() -> i64 { if 1   <   2 { id < i64 > (42) } else { 0 } }\n' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_distinguishes_generic_angles_and_comparisons" "$(<"$tmp_out")" $'fn id<T>(x: T) -> T { x }\n\nfn main() -> i64 { if 1 < 2 { id<i64>(42) } else { 0 } }'
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_angle_roles_are_idempotent" "$tmp_bin" "$tmp_out"

printf 'use compiler / formatter.{ * }\nfn f() -[ Diagnose ]> i64 { resume (0) }\nfn main() -> i64 { for i in 0 .. 2 { 0 } 0 }\n' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_canonical_context_punctuation" "$(<"$tmp_out")" $'use compiler/formatter.{*}\n\nfn f() -[Diagnose]> i64 { resume(0) }\n\nfn main() -> i64 { for i in 0..2 { 0 } 0 }'
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_context_punctuation_is_idempotent" "$tmp_bin" "$tmp_out"

printf 'fn   value ( ) -> str {  "a\\n\\\"b"  }\n' > "$tmp_src"
fmt_out=$("$WEFT" fmt < "$tmp_src" 2>"$tmp_err")
assert_equals "fmt_preserves_literal_spelling" "$fmt_out" 'fn value() -> str { "a\n\"b" }'

printf 'fn main() -> i64 { let x = 41;  x + 1 }\n' > "$tmp_src"
fmt_out=$("$WEFT" fmt < "$tmp_src" 2>"$tmp_err")
assert_equals "fmt_preserves_explicit_semicolon" "$fmt_out" 'fn main() -> i64 { let x = 41; x + 1 }'

printf 'fn main() -> i64 {\n  let x = 41\n  x + 1\n}\n' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_files_equal "fmt_preserves_inserted_semicolon_newlines" "$tmp_out" "$tmp_src"

printf '%s\n' '-- leading  text — exact' 'fn main() -> i64 {' ' let x = 40 -- inline  text' ' if true {' '    -- nested  text' ' x   +   2' ' } else {' '0' '}' '}' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_canonical_block_indentation_and_comments" "$(<"$tmp_out")" $'-- leading  text — exact\n\nfn main() -> i64 {\n  let x = 40 -- inline  text\n  if true {\n    -- nested  text\n    x + 2\n  } else {\n    0\n  }\n}'
assert_equals "fmt_indentation_stderr_empty" "$(<"$tmp_err")" ""
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_block_indentation_is_idempotent" "$tmp_bin" "$tmp_out"

printf '%s\n' 'fn continued() -> bool {' ' true and' ' false' '}' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_canonical_continuation_indentation" "$(<"$tmp_out")" $'fn continued() -> bool {\n  true and\n    false\n}'
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_continuation_indentation_is_idempotent" "$tmp_bin" "$tmp_out"

printf 'fn main() -> i64 {\r\nlet x = 41\r\nx + 1\r\n}\r\n' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
printf 'fn main() -> i64 {\r\n  let x = 41\r\n  x + 1\r\n}\r\n' > "$tmp_bin"
assert_files_equal "fmt_preserves_crlf_while_indenting" "$tmp_out" "$tmp_bin"
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_crlf_indentation_is_idempotent" "$tmp_bin" "$tmp_out"

printf '%s\n' 'use compiler/formatter.{*}' '' '' 'use compiler/lex.{*}' 'fn first() -> i64 { 1 }' '' '' 'fn second() -> i64 { 2 }' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_groups_top_level_imports_and_declarations" "$(<"$tmp_out")" $'use compiler/formatter.{*}\nuse compiler/lex.{*}\n\nfn first() -> i64 { 1 }\n\nfn second() -> i64 { 2 }'
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_top_level_grouping_is_idempotent" "$tmp_bin" "$tmp_out"

printf '%s\n' 'fn first() -> i64 { 1 } fn second() -> i64 { 2 }' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_separates_same_line_top_level_declarations" "$(<"$tmp_out")" $'fn first() -> i64 { 1 }\n\nfn second() -> i64 { 2 }'

printf '%s\n' '-- module  header' '' '' 'use compiler/formatter.{*}' '' '' '-- import  note' '' 'use compiler/lex.{*}' '' 'fn first() -> i64 { 1 } -- trailing  exact' '' '' '--- next  docs' '' '' 'fn second() -> i64 { 2 }' > "$tmp_src"
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_equals "fmt_attaches_top_level_comments_canonically" "$(<"$tmp_out")" $'-- module  header\n\nuse compiler/formatter.{*}\n-- import  note\nuse compiler/lex.{*}\n\nfn first() -> i64 { 1 } -- trailing  exact\n\n--- next  docs\nfn second() -> i64 { 2 }'
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_top_level_comment_attachment_is_idempotent" "$tmp_bin" "$tmp_out"

"$WEFT" fmt compiler/main.weft > "$tmp_out" 2>"$tmp_err"
echo "  ok fmt_canonical_compiler_surface"
assert_equals "fmt_lossless_compiler_stderr_empty" "$(<"$tmp_err")" ""
"$WEFT" fmt < "$tmp_out" > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_idempotent_compiler_surface" "$tmp_bin" "$tmp_out"

"$WEFT" compile tools/fmt.weft > "$tmp_tool_bin" 2>"$tmp_err"
chmod +x "$tmp_tool_bin"
echo "  ok fmt_standalone_builds"
"$tmp_tool_bin" < compiler/main.weft > "$tmp_bin" 2>"$tmp_err"
assert_files_equal "fmt_standalone_shares_engine" "$tmp_bin" "$tmp_out"
assert_equals "fmt_standalone_stderr_empty" "$(<"$tmp_err")" ""

printf 'fn main() -> i64 { missing }\n' > "$tmp_src"
fmt_out=$("$WEFT" fmt < "$tmp_src" 2>"$tmp_err")
assert_equals "fmt_remains_parse_only" "$fmt_out" "fn main() -> i64 { missing }"
assert_equals "fmt_parse_only_stderr_empty" "$(<"$tmp_err")" ""

printf 'fn broken() -> i64 { 1\nfn after() -> i64 { 2 }\n' > "$tmp_src"
set +e
"$WEFT" fmt < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
fmt_parse_failure_exit=$?
set -e
assert_equals "fmt_parse_failure_exit" "$fmt_parse_failure_exit" "1"
assert_equals "fmt_parse_failure_no_stdout" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
fmt_parse_failure_err=$(<"$tmp_err")
assert_contains "fmt_parse_failure_diagnostic" "$fmt_parse_failure_err" "error[E0002]: expected '}' before declaration"
assert_contains "fmt_parse_failure_summary" "$fmt_parse_failure_err" "fmt: parse failed with 1 errors; no output written"

set +e
"$WEFT" fmt --check > "$tmp_out" 2>"$tmp_err"
fmt_check_usage_exit=$?
set -e
assert_equals "fmt_check_requires_paths" "$fmt_check_usage_exit" "1"
assert_equals "fmt_check_usage_stdout_empty" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_contains "fmt_check_usage_is_actionable" "$(<"$tmp_err")" "usage: weft fmt (--check | --write) <path...>"

fmt_clean="$tmp_fmt_dir/clean.weft"
fmt_dirty="$tmp_fmt_dir/dirty.weft"
printf 'fn clean() -> i64 { 1 }\n' > "$fmt_clean"
printf 'fn dirty()  ->  i64 { 2 }\n' > "$fmt_dirty"
set +e
"$WEFT" fmt --check "$fmt_clean" > "$tmp_out" 2>"$tmp_err"
fmt_check_clean_exit=$?
set -e
assert_equals "fmt_check_clean_exit_zero" "$fmt_check_clean_exit" "0"
assert_equals "fmt_check_clean_stdout_empty" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_equals "fmt_check_clean_stderr_empty" "$(<"$tmp_err")" ""

cp "$fmt_dirty" "$tmp_bin"
set +e
"$WEFT" fmt --check "$fmt_dirty" > "$tmp_out" 2>"$tmp_err"
fmt_check_dirty_exit=$?
set -e
assert_equals "fmt_check_dirty_exits_one" "$fmt_check_dirty_exit" "1"
assert_equals "fmt_check_dirty_stdout_empty" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_contains "fmt_check_dirty_names_path" "$(<"$tmp_err")" "fmt: would reformat: $fmt_dirty"
assert_files_equal "fmt_check_dirty_leaves_source_unchanged" "$fmt_dirty" "$tmp_bin"

chmod 664 "$fmt_dirty"
fmt_dirty_mode_before=$(stat -f '%Lp' "$fmt_dirty")
set +e
"$WEFT" fmt --write "$fmt_dirty" > "$tmp_out" 2>"$tmp_err"
fmt_write_dirty_exit=$?
set -e
assert_equals "fmt_write_dirty_exit_zero" "$fmt_write_dirty_exit" "0"
assert_equals "fmt_write_dirty_stdout_empty" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_equals "fmt_write_dirty_stderr_empty" "$(<"$tmp_err")" ""
assert_equals "fmt_write_dirty_replaces_canonically" "$(<"$fmt_dirty")" "fn dirty() -> i64 { 2 }"
assert_equals "fmt_write_preserves_permissions" "$(stat -f '%Lp' "$fmt_dirty")" "$fmt_dirty_mode_before"
assert_equals "fmt_write_removes_temporary" "$(test -e "$fmt_dirty.weft-fmt.tmp"; echo $?)" "1"
set +e
"$WEFT" fmt --check "$fmt_dirty" > "$tmp_out" 2>"$tmp_err"
fmt_write_idempotent_exit=$?
set -e
assert_equals "fmt_write_result_passes_check" "$fmt_write_idempotent_exit" "0"
assert_equals "fmt_write_result_check_stderr_empty" "$(<"$tmp_err")" ""

fmt_recursive_root="$tmp_fmt_dir/recursive"
mkdir -p "$fmt_recursive_root/nested/deeper"
fmt_recursive_a="$fmt_recursive_root/a.weft"
fmt_recursive_b="$fmt_recursive_root/nested/deeper/b.weft"
printf 'fn a()  ->  i64 { 3 }\n' > "$fmt_recursive_a"
printf 'fn b()  ->  i64 { 4 }\n' > "$fmt_recursive_b"
printf 'leave  this alone\n' > "$fmt_recursive_root/ignored.txt"
ln -s "$fmt_recursive_root" "$fmt_recursive_root/nested/loop"
set +e
"$WEFT" fmt --write "$fmt_recursive_root" > "$tmp_out" 2>"$tmp_err"
fmt_recursive_write_exit=$?
set -e
assert_equals "fmt_write_directory_exit_zero" "$fmt_recursive_write_exit" "0"
assert_equals "fmt_write_directory_stdout_empty" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_equals "fmt_write_directory_stderr_empty" "$(<"$tmp_err")" ""
assert_equals "fmt_write_directory_formats_root_file" "$(<"$fmt_recursive_a")" "fn a() -> i64 { 3 }"
assert_equals "fmt_write_directory_formats_nested_file" "$(<"$fmt_recursive_b")" "fn b() -> i64 { 4 }"
assert_equals "fmt_write_directory_ignores_other_extensions" "$(<"$fmt_recursive_root/ignored.txt")" "leave  this alone"

printf 'fn a()  ->  i64 { 3 }\n' > "$fmt_recursive_a"
cp "$fmt_recursive_a" "$tmp_bin"
set +e
"$WEFT" fmt --check "$fmt_recursive_a" "$fmt_recursive_root" > "$tmp_out" 2>"$tmp_err"
fmt_overlap_exit=$?
set -e
assert_equals "fmt_overlap_dirty_exits_one" "$fmt_overlap_exit" "1"
assert_equals "fmt_overlap_deduplicates_path" "$(grep -cF "fmt: would reformat: $fmt_recursive_a" "$tmp_err")" "1"
assert_files_equal "fmt_overlap_check_leaves_source_unchanged" "$fmt_recursive_a" "$tmp_bin"

fmt_order_a="$tmp_fmt_dir/a_order.weft"
fmt_order_z="$tmp_fmt_dir/z_order.weft"
printf 'fn order_a()  ->  i64 { 1 }\n' > "$fmt_order_a"
printf 'fn order_z()  ->  i64 { 2 }\n' > "$fmt_order_z"
set +e
"$WEFT" fmt --check "$fmt_order_z" "$fmt_order_a" > "$tmp_out" 2>"$tmp_err"
fmt_order_exit=$?
set -e
assert_equals "fmt_multiple_paths_dirty_exit_one" "$fmt_order_exit" "1"
fmt_order_a_line=$(grep -nF "fmt: would reformat: $fmt_order_a" "$tmp_err" | cut -d: -f1)
fmt_order_z_line=$(grep -nF "fmt: would reformat: $fmt_order_z" "$tmp_err" | cut -d: -f1)
if [ "$fmt_order_a_line" -lt "$fmt_order_z_line" ]; then
  echo "  ok fmt_multiple_paths_are_deterministic"
else
  echo "  fail fmt_multiple_paths_are_deterministic"
  exit 1
fi

fmt_broken="$tmp_fmt_dir/broken.weft"
printf 'fn broken() -> i64 {\n' > "$fmt_broken"
cp "$fmt_broken" "$tmp_bin"
set +e
"$WEFT" fmt --write "$fmt_broken" > "$tmp_out" 2>"$tmp_err"
fmt_broken_write_exit=$?
set -e
assert_equals "fmt_write_parse_error_exits_one" "$fmt_broken_write_exit" "1"
assert_equals "fmt_write_parse_error_stdout_empty" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_contains "fmt_write_parse_error_preserves_eof_coordinate" "$(<"$tmp_err")" "line 2, col 1: error[E0002]: expected '}' before end of file"
assert_contains "fmt_write_parse_error_summary" "$(<"$tmp_err")" "fmt: parse failed for $fmt_broken"
assert_files_equal "fmt_write_parse_error_leaves_source_unchanged" "$fmt_broken" "$tmp_bin"
assert_equals "fmt_write_parse_error_creates_no_temporary" "$(test -e "$fmt_broken.weft-fmt.tmp"; echo $?)" "1"

fmt_readonly="$tmp_fmt_dir/readonly.weft"
printf 'fn readonly()  ->  i64 { 5 }\n' > "$fmt_readonly"
cp "$fmt_readonly" "$tmp_bin"
chmod 444 "$fmt_readonly"
set +e
"$WEFT" fmt --write "$fmt_readonly" > "$tmp_out" 2>"$tmp_err"
fmt_readonly_exit=$?
set -e
assert_equals "fmt_write_readonly_exits_one" "$fmt_readonly_exit" "1"
assert_contains "fmt_write_readonly_is_explicit" "$(<"$tmp_err")" "fmt: source file is read-only: $fmt_readonly"
assert_files_equal "fmt_write_readonly_leaves_source_unchanged" "$fmt_readonly" "$tmp_bin"
assert_equals "fmt_write_readonly_creates_no_temporary" "$(test -e "$fmt_readonly.weft-fmt.tmp"; echo $?)" "1"
chmod 644 "$fmt_readonly"

fmt_interrupted="$tmp_fmt_dir/interrupted.weft"
fmt_interrupted_temp="$fmt_interrupted.weft-fmt.tmp"
printf 'fn interrupted()  ->  i64 { 6 }\n' > "$fmt_interrupted"
printf 'previous temporary bytes\n' > "$fmt_interrupted_temp"
cp "$fmt_interrupted" "$tmp_bin"
set +e
"$WEFT" fmt --write "$fmt_interrupted" > "$tmp_out" 2>"$tmp_err"
fmt_interrupted_exit=$?
set -e
assert_equals "fmt_write_interrupted_exits_one" "$fmt_interrupted_exit" "1"
assert_contains "fmt_write_interrupted_reports_temporary" "$(<"$tmp_err")" "fmt: could not create temporary file: $fmt_interrupted_temp"
assert_files_equal "fmt_write_interrupted_leaves_source_unchanged" "$fmt_interrupted" "$tmp_bin"
assert_equals "fmt_write_interrupted_preserves_existing_temporary" "$(<"$fmt_interrupted_temp")" "previous temporary bytes"
rm -f "$fmt_interrupted_temp"

fmt_symlink_target="$tmp_fmt_dir/symlink_target.weft"
fmt_symlink_path="$tmp_fmt_dir/symlink.weft"
printf 'fn symlink_target()  ->  i64 { 7 }\n' > "$fmt_symlink_target"
cp "$fmt_symlink_target" "$tmp_bin"
ln -s "$fmt_symlink_target" "$fmt_symlink_path"
set +e
"$WEFT" fmt --write "$fmt_symlink_path" > "$tmp_out" 2>"$tmp_err"
fmt_symlink_exit=$?
set -e
assert_equals "fmt_write_symlink_exits_one" "$fmt_symlink_exit" "1"
assert_contains "fmt_write_symlink_is_explicit" "$(<"$tmp_err")" "fmt: refusing to replace symbolic link: $fmt_symlink_path"
assert_files_equal "fmt_write_symlink_leaves_target_unchanged" "$fmt_symlink_target" "$tmp_bin"
if [ -L "$fmt_symlink_path" ]; then
  echo "  ok fmt_write_symlink_remains_link"
else
  echo "  fail fmt_write_symlink_remains_link"
  exit 1
fi

fmt_empty="$tmp_fmt_dir/empty.weft"
: > "$fmt_empty"
set +e
"$WEFT" fmt --check "$fmt_empty" > "$tmp_out" 2>"$tmp_err"
fmt_empty_exit=$?
set -e
assert_equals "fmt_check_accepts_empty_file" "$fmt_empty_exit" "0"
assert_equals "fmt_check_empty_file_stderr_empty" "$(<"$tmp_err")" ""

fmt_empty_dir="$tmp_fmt_dir/no_sources"
mkdir -p "$fmt_empty_dir"
set +e
"$WEFT" fmt --check "$fmt_empty_dir" > "$tmp_out" 2>"$tmp_err"
fmt_empty_dir_exit=$?
set -e
assert_equals "fmt_check_empty_directory_exits_one" "$fmt_empty_dir_exit" "1"
assert_contains "fmt_check_empty_directory_names_path" "$(<"$tmp_err")" "fmt: no .weft files in directory: $fmt_empty_dir"

fmt_missing="$tmp_fmt_dir/missing.weft"
set +e
"$WEFT" fmt --check "$fmt_missing" > "$tmp_out" 2>"$tmp_err"
fmt_missing_exit=$?
set -e
assert_equals "fmt_check_missing_file_exits_one" "$fmt_missing_exit" "1"
assert_contains "fmt_check_missing_file_names_path" "$(<"$tmp_err")" "fmt: could not read input file: $fmt_missing"

set +e
"$WEFT" fmt "$fmt_clean" "$fmt_dirty" > "$tmp_out" 2>"$tmp_err"
fmt_plain_multiple_exit=$?
set -e
assert_equals "fmt_plain_multiple_paths_require_mode" "$fmt_plain_multiple_exit" "1"
assert_contains "fmt_plain_multiple_paths_show_usage" "$(<"$tmp_err")" "usage: weft fmt (--check | --write) <path...>"

printf '%s\n' 'extern fn placeholder(n: i64) -> i64 { n }' 'fn main() -> i64 { 42 }' > "$tmp_src"
set +e
"$WEFT" check < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
check_parse_failure_exit=$?
set -e
assert_equals "check_parse_failure_exit" "$check_parse_failure_exit" "1"
assert_equals "check_parse_failure_no_stdout" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_contains "check_parse_failure_diagnostic" "$(<"$tmp_err")" "error[E0002]: unexpected token at module level"
assert_contains "check_parse_failure_summary" "$(<"$tmp_err")" "check: 2 functions, 1 errors"

set +e
"$WEFT" compile < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
compile_parse_failure_exit=$?
set -e
assert_equals "compile_parse_failure_exit" "$compile_parse_failure_exit" "1"
assert_equals "compile_parse_failure_no_binary" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_contains "compile_parse_failure_diagnostic" "$(<"$tmp_err")" "error[E0002]: unexpected token at module level"
assert_contains "compile_parse_failure_summary" "$(<"$tmp_err")" "compile: parse failed with 1 errors"

printf '%s\n' 'extern fn placeholder(n: i64) -> i64 { n }' 'test "recovered body must not run" { Test.assert_eq(1, 1) }' > "$tmp_src"
set +e
"$WEFT" test < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
test_parse_failure_exit=$?
set -e
assert_equals "test_parse_failure_exit" "$test_parse_failure_exit" "1"
assert_equals "test_parse_failure_no_binary" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
assert_contains "test_parse_failure_diagnostic" "$(<"$tmp_err")" "line 1, col 1: error[E0002]: unexpected token at module level"
assert_contains "test_parse_failure_summary" "$(<"$tmp_err")" "test: parse failed with 1 errors"

printf 'fn main() -> i64 { 42 }\n' > "$tmp_src"
ast_out=$("$WEFT" ast < "$tmp_src" 2>&1)
assert_contains "ast_parse_only_header" "$ast_out" "--- AST: 1 functions ---"
assert_contains "ast_parse_only_literal" "$ast_out" "IntLit(42)"
assert_equals "ast_snapshot_exact" "$ast_out" $'--- AST: 1 functions ---\n\nfn main:\n  IntLit(42)'

ast_path_out=$("$WEFT" ast "$tmp_src" 2>&1)
assert_equals "ast_path_snapshot_exact" "$ast_path_out" $'--- AST: 1 functions ---\n\nfn main:\n  IntLit(42)'

check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_parse_and_typecheck" "$check_out" "check: 1 functions, 0 errors"

check_path_out=$("$WEFT" check "$tmp_src" 2>&1)
assert_contains "check_path_parse_and_typecheck" "$check_path_out" "check: 1 functions, 0 errors"

printf 'fn clean() -> i64 { 42 }\n' > "$tmp_check_clean"
printf 'fn first_bad() -> i64 { missing_first }\n' > "$tmp_check_fail"
tmp_check_spaced="$tmp_check_dir/check spaced.weft"
printf 'fn second_bad() -> i64 { missing_second }\n' > "$tmp_check_spaced"
tmp_check_missing="$tmp_check_dir/check missing.weft"
set +e
"$WEFT" check --jobs 2 "$tmp_check_fail" "$tmp_check_clean" "$tmp_check_spaced" "$tmp_check_missing" > "$tmp_out" 2> "$tmp_err"
check_batch_exit=$?
set -e
assert_equals "check_batch_failure_exit" "$check_batch_exit" "1"
assert_equals "check_batch_stdout_empty" "$(wc -c < "$tmp_out" | tr -d ' ')" "0"
check_batch_headers=$(grep '^==> ' "$tmp_err")
assert_equals "check_batch_replays_argument_order" "$check_batch_headers" "$(printf '==> %s <==\n==> %s <==\n==> %s <==\n==> %s <==' "$tmp_check_fail" "$tmp_check_clean" "$tmp_check_spaced" "$tmp_check_missing")"
check_batch_out=$(<"$tmp_err")
assert_contains "check_batch_keeps_first_diagnostic" "$check_batch_out" "unknown identifier 'missing_first'"
assert_contains "check_batch_continues_through_clean_root" "$check_batch_out" "==> $tmp_check_clean <=="$'\n'"check: 1 functions, 0 errors"
assert_contains "check_batch_supports_spaced_path" "$check_batch_out" "==> $tmp_check_spaced <=="
assert_contains "check_batch_keeps_later_diagnostic" "$check_batch_out" "unknown identifier 'missing_second'"
assert_contains "check_batch_isolates_missing_root" "$check_batch_out" "==> $tmp_check_missing <=="$'\n'"check: could not read input file"

set +e
"$WEFT" check --jobs 0 "$tmp_check_clean" > "$tmp_out" 2> "$tmp_err"
check_bad_jobs_exit=$?
set -e
assert_equals "check_batch_rejects_invalid_jobs" "$check_bad_jobs_exit" "2"
assert_contains "check_batch_invalid_jobs_is_actionable" "$(<"$tmp_err")" "check: --jobs must be an integer from 1 to 64"

set +e
"$WEFT" check -j 1 > "$tmp_out" 2> "$tmp_err"
check_missing_paths_exit=$?
set -e
assert_equals "check_batch_requires_paths" "$check_missing_paths_exit" "2"
assert_contains "check_batch_missing_paths_shows_usage" "$(<"$tmp_err")" "usage: weft check [--jobs N] <path...>"

run_weft_compile_guarded "$WEFT" compile "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_equals "compile_path_default_stderr_empty" "$(<"$tmp_err")" ""
chmod +x "$tmp_bin"
set +e
run_binary_guarded "$tmp_bin" >/dev/null 2>&1
compile_path_exit=$?
set -e
assert_equals "compile_path_binary_exit" "$compile_path_exit" "42"

set +e
run_weft_compile_guarded "$WEFT" compile --metrics "$tmp_src" > "$tmp_out" 2>"$tmp_err"
compile_metrics_exit=$?
set -e
assert_equals "compile_metrics_exit_zero" "$compile_metrics_exit" "0"
if cmp -s "$tmp_bin" "$tmp_out"; then
  echo "  ok compile_metrics_preserves_binary_bytes"
else
  echo "  fail compile_metrics_preserves_binary_bytes"
  exit 1
fi
compile_metrics_line=$(grep '^WEFT_COMPILE_METRICS ' "$tmp_err")
read -r compile_metric_tag compile_metric_version compile_metric_source compile_metric_parse compile_metric_check compile_metric_lower compile_metric_optimise compile_metric_native compile_metric_package compile_metric_write compile_metric_total compile_metric_checked_fns compile_metric_ir_fns compile_metric_native_fns compile_metric_extra <<< "$compile_metrics_line"
assert_equals "compile_metrics_machine_schema_version" "$compile_metric_tag:$compile_metric_version" "WEFT_COMPILE_METRICS:1"
assert_equals "compile_metrics_machine_schema_has_exact_fields" "$compile_metric_extra" ""
if [[ "$compile_metric_source" =~ ^[0-9]+$ ]] && [[ "$compile_metric_parse" =~ ^[0-9]+$ ]] && [[ "$compile_metric_check" =~ ^[0-9]+$ ]] && [[ "$compile_metric_lower" =~ ^[0-9]+$ ]] && [[ "$compile_metric_optimise" =~ ^[0-9]+$ ]] && [[ "$compile_metric_native" =~ ^[0-9]+$ ]] && [[ "$compile_metric_package" =~ ^[0-9]+$ ]] && [[ "$compile_metric_write" =~ ^[0-9]+$ ]] && [[ "$compile_metric_total" =~ ^[0-9]+$ ]]; then
  echo "  ok compile_metrics_machine_stages_are_numeric"
else
  echo "  fail compile_metrics_machine_stages_are_numeric"
  echo "    metrics: $compile_metrics_line"
  exit 1
fi
compile_metric_accounted=$((compile_metric_source + compile_metric_parse + compile_metric_check + compile_metric_lower + compile_metric_optimise + compile_metric_native + compile_metric_package + compile_metric_write))
if [ "$compile_metric_total" -gt 0 ] && [ "$compile_metric_total" -ge "$compile_metric_accounted" ]; then
  echo "  ok compile_metrics_total_covers_accounted_phases"
else
  echo "  fail compile_metrics_total_covers_accounted_phases"
  echo "    metrics: $compile_metrics_line"
  exit 1
fi
if [[ "$compile_metric_checked_fns" =~ ^[0-9]+$ ]] && [[ "$compile_metric_ir_fns" =~ ^[0-9]+$ ]] && [[ "$compile_metric_native_fns" =~ ^[0-9]+$ ]] && [ "$compile_metric_checked_fns" -gt 0 ] && [ "$compile_metric_ir_fns" -gt 0 ] && [ "$compile_metric_native_fns" -gt 0 ]; then
  echo "  ok compile_metrics_machine_counts_functions"
else
  echo "  fail compile_metrics_machine_counts_functions"
  echo "    metrics: $compile_metrics_line"
  exit 1
fi
compile_metrics_err=$(<"$tmp_err")
assert_contains "compile_metrics_human_reports_total" "$compile_metrics_err" "compile metrics: total_ms="
assert_contains "compile_metrics_human_reports_expensive_phases" "$compile_metrics_err" "optimise_ms="
chmod +x "$tmp_out"
set +e
run_binary_guarded "$tmp_out" >/dev/null 2>&1
compile_metrics_binary_exit=$?
set -e
assert_equals "compile_metrics_binary_exit" "$compile_metrics_binary_exit" "42"

set +e
"$WEFT" compile --metrics > "$tmp_out" 2>"$tmp_err"
compile_metrics_missing_exit=$?
set -e
assert_equals "compile_metrics_missing_path_exits_usage" "$compile_metrics_missing_exit" "2"
assert_equals "compile_metrics_missing_path_stdout_empty" "$(<"$tmp_out")" ""
assert_contains "compile_metrics_missing_path_prints_usage" "$(<"$tmp_err")" "usage: weft compile [--metrics] PATH"

set +e
"$WEFT" compile --metrics "$tmp_src" "$tmp_check_clean" > "$tmp_out" 2>"$tmp_err"
compile_metrics_extra_exit=$?
set -e
assert_equals "compile_metrics_extra_path_exits_usage" "$compile_metrics_extra_exit" "2"
assert_contains "compile_metrics_extra_path_prints_usage" "$(<"$tmp_err")" "usage: weft compile [--metrics] PATH"

printf 'type CensusBox { value: i64 } type CensusOuter { inner: CensusBox } fn census_observe(box: CensusBox) -> i64 { box.value } fn census_consume(box: CensusBox) -> i64 { let outer = CensusOuter { inner: box } outer.inner.value } fn main() -> i64 { let box = CensusBox { value: 42 } let left = census_observe(box) let right = census_consume(box) if left == right { 42 } else { 0 } }\n' > "$tmp_rc_census_src"
set +e
run_weft_compile_guarded "$WEFT" compile --rc-census "$tmp_rc_census_src" > "$tmp_out" 2> "$tmp_err"
compile_rc_census_exit=$?
set -e
assert_equals "compile_rc_census_exit_zero" "$compile_rc_census_exit" "0"
rc_site_line=$(grep '^WEFT_RC_SITE_CENSUS ' "$tmp_err")
read -r rc_site_tag rc_site_version rc_site_counted rc_site_stack rc_site_region rc_site_arena rc_site_reuse rc_site_unique rc_site_owned rc_site_frozen rc_site_promotions rc_site_total rc_site_extra <<< "$rc_site_line"
assert_equals "compile_rc_census_site_schema_version" "$rc_site_tag:$rc_site_version" "WEFT_RC_SITE_CENSUS:1"
assert_equals "compile_rc_census_site_schema_has_exact_fields" "$rc_site_extra" ""
if [[ "$rc_site_counted" =~ ^[0-9]+$ && "$rc_site_stack" =~ ^[0-9]+$ && "$rc_site_region" =~ ^[0-9]+$ && "$rc_site_arena" =~ ^[0-9]+$ && "$rc_site_reuse" =~ ^[0-9]+$ && "$rc_site_unique" =~ ^[0-9]+$ && "$rc_site_owned" =~ ^[0-9]+$ && "$rc_site_frozen" =~ ^[0-9]+$ && "$rc_site_promotions" =~ ^[0-9]+$ && "$rc_site_total" =~ ^[0-9]+$ ]] && [ "$rc_site_counted" -gt 0 ] && [ "$rc_site_total" -ge "$rc_site_counted" ]; then
  echo "  ok compile_rc_census_site_fields_are_numeric_and_populated"
else
  echo "  fail compile_rc_census_site_fields_are_numeric_and_populated"
  echo "    census: $rc_site_line"
  exit 1
fi
assert_contains "compile_rc_census_site_human_names_classes" "$(<"$tmp_err")" "rc site census: counted="

chmod +x "$tmp_out"
set +e
run_binary_guarded "$tmp_out" >/dev/null 2> "$tmp_err"
compile_rc_census_binary_exit=$?
set -e
assert_equals "compile_rc_census_binary_preserves_exit" "$compile_rc_census_binary_exit" "42"
rc_dynamic_line=$(grep '^WEFT_RC_CENSUS ' "$tmp_err")
read -r rc_dynamic_tag rc_dynamic_version rc_dynamic_alloc rc_dynamic_retain rc_dynamic_release rc_dynamic_child rc_dynamic_promoted_retain rc_dynamic_promoted_release rc_dynamic_closure_retain rc_dynamic_closure_release rc_dynamic_closure_promoted_release rc_dynamic_weak_retain rc_dynamic_weak_release rc_dynamic_weak_load rc_dynamic_region_alloc rc_dynamic_promotions rc_dynamic_call_owned rc_dynamic_call_borrowed rc_dynamic_reuse_attempts rc_dynamic_reuse_allocs rc_dynamic_reuse_hits rc_dynamic_managed_retain rc_dynamic_managed_release rc_dynamic_origin_unknown_retain rc_dynamic_origin_unknown_release rc_dynamic_origin_result_retain rc_dynamic_origin_result_release rc_dynamic_origin_call_retain rc_dynamic_origin_call_release rc_dynamic_origin_binding_retain rc_dynamic_origin_binding_release rc_dynamic_origin_aggregate_retain rc_dynamic_origin_aggregate_release rc_dynamic_origin_arm_retain rc_dynamic_origin_arm_release rc_dynamic_origin_discard_retain rc_dynamic_origin_discard_release rc_dynamic_origin_cleanup_retain rc_dynamic_origin_cleanup_release rc_dynamic_origin_control_retain rc_dynamic_origin_control_release rc_dynamic_extra <<< "$rc_dynamic_line"
assert_equals "compile_rc_census_dynamic_schema_version" "$rc_dynamic_tag:$rc_dynamic_version" "WEFT_RC_CENSUS:5"
assert_equals "compile_rc_census_dynamic_schema_has_exact_fields" "$rc_dynamic_extra" ""
if [[ "$rc_dynamic_alloc" =~ ^[0-9]+$ && "$rc_dynamic_retain" =~ ^[0-9]+$ && "$rc_dynamic_release" =~ ^[0-9]+$ && "$rc_dynamic_child" =~ ^[0-9]+$ && "$rc_dynamic_promoted_retain" =~ ^[0-9]+$ && "$rc_dynamic_promoted_release" =~ ^[0-9]+$ && "$rc_dynamic_closure_retain" =~ ^[0-9]+$ && "$rc_dynamic_closure_release" =~ ^[0-9]+$ && "$rc_dynamic_closure_promoted_release" =~ ^[0-9]+$ && "$rc_dynamic_weak_retain" =~ ^[0-9]+$ && "$rc_dynamic_weak_release" =~ ^[0-9]+$ && "$rc_dynamic_weak_load" =~ ^[0-9]+$ && "$rc_dynamic_region_alloc" =~ ^[0-9]+$ && "$rc_dynamic_promotions" =~ ^[0-9]+$ && "$rc_dynamic_call_owned" =~ ^[0-9]+$ && "$rc_dynamic_call_borrowed" =~ ^[0-9]+$ && "$rc_dynamic_reuse_attempts" =~ ^[0-9]+$ && "$rc_dynamic_reuse_allocs" =~ ^[0-9]+$ && "$rc_dynamic_reuse_hits" =~ ^[0-9]+$ && "$rc_dynamic_managed_retain" =~ ^[0-9]+$ && "$rc_dynamic_managed_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_unknown_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_unknown_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_result_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_result_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_call_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_call_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_binding_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_binding_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_aggregate_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_aggregate_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_arm_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_arm_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_discard_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_discard_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_cleanup_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_cleanup_release" =~ ^[0-9]+$ && "$rc_dynamic_origin_control_retain" =~ ^[0-9]+$ && "$rc_dynamic_origin_control_release" =~ ^[0-9]+$ ]]; then
  rc_dynamic_origin_retain_sum=$((rc_dynamic_origin_unknown_retain + rc_dynamic_origin_result_retain + rc_dynamic_origin_call_retain + rc_dynamic_origin_binding_retain + rc_dynamic_origin_aggregate_retain + rc_dynamic_origin_arm_retain + rc_dynamic_origin_discard_retain + rc_dynamic_origin_cleanup_retain + rc_dynamic_origin_control_retain))
  rc_dynamic_origin_release_sum=$((rc_dynamic_origin_unknown_release + rc_dynamic_origin_result_release + rc_dynamic_origin_call_release + rc_dynamic_origin_binding_release + rc_dynamic_origin_aggregate_release + rc_dynamic_origin_arm_release + rc_dynamic_origin_discard_release + rc_dynamic_origin_cleanup_release + rc_dynamic_origin_control_release))
else
  rc_dynamic_origin_retain_sum=-1
  rc_dynamic_origin_release_sum=-1
fi
if [ "$rc_dynamic_alloc" -gt 0 ] && [ "$rc_dynamic_release" -gt 0 ] && [ "$rc_dynamic_call_owned" -gt 0 ] && [ "$rc_dynamic_call_borrowed" -gt 0 ] && [ "$rc_dynamic_managed_retain" -gt 0 ] && [ "$rc_dynamic_managed_release" -gt 0 ] && [ "$rc_dynamic_managed_retain" -le "$rc_dynamic_retain" ] && [ "$rc_dynamic_managed_release" -le "$rc_dynamic_release" ] && [ "$rc_dynamic_origin_unknown_retain" -eq 0 ] && [ "$rc_dynamic_origin_unknown_release" -eq 0 ] && [ "$rc_dynamic_origin_retain_sum" -eq "$rc_dynamic_managed_retain" ] && [ "$rc_dynamic_origin_release_sum" -eq "$rc_dynamic_managed_release" ]; then
  echo "  ok compile_rc_census_dynamic_fields_are_numeric_and_populated"
else
  echo "  fail compile_rc_census_dynamic_fields_are_numeric_and_populated"
  echo "    census: $rc_dynamic_line"
  exit 1
fi
assert_contains "compile_rc_census_dynamic_human_names_events" "$(<"$tmp_err")" "rc census: default_alloc="
assert_contains "compile_rc_census_dynamic_human_names_origins" "$(<"$tmp_err")" "origin_call_transport_retain="

set +e
"$WEFT" compile --rc-census > "$tmp_out" 2> "$tmp_err"
compile_rc_census_missing_exit=$?
set -e
assert_equals "compile_rc_census_missing_path_exits_usage" "$compile_rc_census_missing_exit" "2"
assert_equals "compile_rc_census_missing_path_stdout_empty" "$(<"$tmp_out")" ""
assert_contains "compile_rc_census_missing_path_prints_usage" "$(<"$tmp_err")" "usage: weft compile [--metrics|--rc-census] PATH"

set +e
"$WEFT" compile --rc-census "$tmp_rc_census_src" "$tmp_check_clean" > "$tmp_out" 2> "$tmp_err"
compile_rc_census_extra_exit=$?
set -e
assert_equals "compile_rc_census_extra_path_exits_usage" "$compile_rc_census_extra_exit" "2"
assert_contains "compile_rc_census_extra_path_prints_usage" "$(<"$tmp_err")" "usage: weft compile [--metrics|--rc-census] PATH"

assert_program_failure_contains "panic_boundary" "test/panic_exit.weft" "101" "weft: panic: direct panic boundary"
assert_program_failure_contains "checked_index_bounds_panic" "test/array_index_oob_exit.weft" "101" "weft: panic: index out of bounds"
assert_program_failure_contains "checked_index_mutation_bounds_panic" "test/array_index_set_oob_exit.weft" "101" "weft: panic: index out of bounds"
assert_program_failure_contains "checked_slice_order_panic" "test/array_slice_order_oob_exit.weft" "101" "weft: panic: index out of bounds"
assert_program_failure_contains "checked_slice_upper_panic" "test/array_slice_upper_oob_exit.weft" "101" "weft: panic: index out of bounds"
assert_program_failure_contains "result_unwrap_panic" "test/result_unwrap_exit.weft" "101" "weft: panic: Result.unwrap called on Err"
assert_program_failure_contains "result_expect_panic" "test/result_expect_exit.weft" "101" "weft: panic: required result failed"
assert_program_failure_contains "option_unwrap_panic" "test/option_unwrap_exit.weft" "101" "weft: panic: Option.unwrap called on None"
assert_program_failure_contains "option_expect_panic" "test/option_expect_exit.weft" "101" "weft: panic: required option missing"

run_weft_compile_guarded "$WEFT" compile "test/panic_trace_exit.weft" > "$tmp_bin" 2>"$tmp_err"
chmod +x "$tmp_bin"
set +e
run_binary_guarded "$tmp_bin" >/dev/null 2>"$tmp_err"
panic_trace_exit=$?
set -e
panic_trace_err=$(<"$tmp_err")
assert_equals "panic_trace_exit" "$panic_trace_exit" "101"
assert_contains "panic_trace_message" "$panic_trace_err" "weft: panic: traced panic boundary"
assert_contains "panic_trace_header" "$panic_trace_err" "stack backtrace:"
assert_contains "panic_trace_leaf" "$panic_trace_err" "panic_trace_leaf at test/panic_trace_exit.weft:5:4"
assert_contains "panic_trace_main" "$panic_trace_err" "main at test/panic_trace_exit.weft:13:4"

run_weft_compile_guarded "$WEFT" compile "test/trap_exit.weft" > "$tmp_bin" 2>"$tmp_err"
chmod +x "$tmp_bin"
set +e
run_binary_guarded "$tmp_bin" >/dev/null 2>"$tmp_err"
trap_exit=$?
set -e
trap_err=$(<"$tmp_err")
assert_equals "trap_exit" "$trap_exit" "102"
assert_contains "trap_reason" "$trap_err" "weft: trap: invalid native value home (code 20)"
assert_contains "trap_trace_header" "$trap_err" "stack backtrace:"
assert_contains "trap_trace_main" "$trap_err" "main at test/trap_exit.weft:5:4"

printf 'fn broken() -> i64 { 1\nfn after() -> i64 { 2 }\n' > "$tmp_src"
parse_recovery_out=$("$WEFT" ast < "$tmp_src" 2>&1)
assert_contains "ast_reports_parse_recovery" "$parse_recovery_out" "error[E0002]: expected '}' before declaration"
assert_contains "ast_recovers_after_parse_error" "$parse_recovery_out" "--- AST: 2 functions ---"

printf 'fn main() -> i64 { missing }\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_contains "check_reports_diagnostics" "$diag_out" "error[E1001]: unknown identifier 'missing'"
assert_equals "diagnostic_snapshot_exact" "$diag_out" $'line 1, col 20: error[E1001]: unknown identifier \x27missing\x27\n  |\n1 | fn main() -> i64 { missing }\n  |                    ^~~~~~~ unknown identifier \x27missing\x27\ncheck: 1 functions, 1 errors'

ansi_escape=$'\033'
color_out=$("$WEFT" --color=always check < "$tmp_src" 2>&1 || true)
assert_contains "diagnostic_color_always_styles_error_heading" "$color_out" "${ansi_escape}[1;31merror[E1001]${ansi_escape}[0m"
assert_contains "diagnostic_color_always_styles_primary_caret" "$color_out" "${ansi_escape}[1;31m^~~~~~~${ansi_escape}[0m unknown identifier"

plain_out=$("$WEFT" --color=never check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_color_never_is_byte_stable" "$plain_out" "$diag_out"
plain_out=$("$WEFT" --no-color check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_no_color_alias_is_byte_stable" "$plain_out" "$diag_out"
color_out=$("$WEFT" --color always check < "$tmp_src" 2>&1 || true)
assert_contains "diagnostic_color_accepts_separate_value" "$color_out" "${ansi_escape}[1;31merror[E1001]${ansi_escape}[0m"

tty_out=$(env -u NO_COLOR TERM=xterm script -q /dev/null "$WEFT" check "$tmp_src" 2>&1 || true)
assert_contains "diagnostic_color_auto_detects_tty" "$tty_out" "${ansi_escape}[1;31merror[E1001]${ansi_escape}[0m"
tty_out=$(NO_COLOR=1 TERM=xterm script -q /dev/null "$WEFT" check "$tmp_src" 2>&1 || true)
assert_not_contains "diagnostic_no_color_environment_disables_tty_ansi" "$tty_out" "$ansi_escape"
tty_out=$(TERM=dumb env -u NO_COLOR script -q /dev/null "$WEFT" check "$tmp_src" 2>&1 || true)
assert_not_contains "diagnostic_dumb_terminal_disables_tty_ansi" "$tty_out" "$ansi_escape"
tty_out=$(NO_COLOR=1 TERM=dumb script -q /dev/null "$WEFT" --color=always check "$tmp_src" 2>&1 || true)
assert_contains "diagnostic_explicit_color_overrides_environment" "$tty_out" "${ansi_escape}[1;31merror[E1001]${ansi_escape}[0m"

set +e
"$WEFT" --color=rainbow check "$tmp_src" >"$tmp_out" 2>"$tmp_err"
color_invalid_exit=$?
set -e
assert_equals "diagnostic_invalid_color_value_exits_usage" "$color_invalid_exit" "2"
assert_contains "diagnostic_invalid_color_value_is_actionable" "$(<"$tmp_err")" "expected auto, always, or never"
set +e
"$WEFT" --color >"$tmp_out" 2>"$tmp_err"
color_missing_exit=$?
set -e
assert_equals "diagnostic_missing_color_value_exits_usage" "$color_missing_exit" "2"
assert_contains "diagnostic_missing_color_value_is_actionable" "$(<"$tmp_err")" "--color requires auto, always, or never"

run_weft_compile_guarded "$WEFT" compile test/fixtures/diagnostic_style_probe.weft > "$tmp_bin" 2>"$tmp_err"
chmod +x "$tmp_bin"
color_out=$(run_binary_guarded "$tmp_bin" 2>&1)
assert_contains "diagnostic_warning_heading_is_yellow" "$color_out" "${ansi_escape}[1;33mwarning${ansi_escape}[0m: warning role"
assert_contains "diagnostic_warning_caret_is_yellow" "$color_out" "${ansi_escape}[1;33m^~~~~${ansi_escape}[0m warning role"
assert_contains "diagnostic_related_heading_is_blue" "$color_out" "${ansi_escape}[1;34mnote${ansi_escape}[0m: related role"
assert_contains "diagnostic_related_caret_is_blue" "$color_out" "${ansi_escape}[1;34m^~~~${ansi_escape}[0m related role"
assert_contains "diagnostic_note_heading_is_cyan" "$color_out" "${ansi_escape}[1;36mnote${ansi_escape}[0m: note role"
assert_contains "diagnostic_note_caret_is_cyan" "$color_out" "${ansi_escape}[1;36m^~~~~${ansi_escape}[0m note role"

printf 'fn main() -> i64 { let s = "😀" missing }\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_unicode_columns_count_scalars" "$diag_out" $'line 1, col 32: error[E1001]: unknown identifier \x27missing\x27\n  |\n1 | fn main() -> i64 { let s = "😀" missing }\n  |                                ^~~~~~~ unknown identifier \x27missing\x27\ncheck: 1 functions, 1 errors'

printf 'fn main() -> i64 { let counter = 1 counte }\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_unknown_name_suggestion_golden" "$diag_out" $'line 1, col 36: error[E1001]: unknown identifier \x27counte\x27\n  |\n1 | fn main() -> i64 { let counter = 1 counte }\n  |                                    ^~~~~~ unknown identifier \x27counte\x27\nline 1, col 24: note: similarly named declaration\n  |\n1 | fn main() -> i64 { let counter = 1 counte }\n  |                        ^~~~~~~ similarly named declaration\nhelp: did you mean \x27counter\x27?\ncheck: 1 functions, 1 errors'

printf '%s\n' 'fn takes(value: i64) -> i64 { value } fn main() -> i64 { takes("snow") }' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_type_mismatch_teaches_contract_golden" "$diag_out" $'line 1, col 64: error[E1002]: argument type mismatch: expected `i64`, found `str`\n  |\n1 | fn takes(value: i64) -> i64 { value } fn main() -> i64 { takes("snow") }\n  |                                                                ^~~~~~ argument type mismatch: expected `i64`, found `str`\nline 1, col 10: note: expected type established here\n  |\n1 | fn takes(value: i64) -> i64 { value } fn main() -> i64 { takes("snow") }\n  |          ^~~~~ expected type established here\nhelp: Weft accepts a value here when its type is a subtype of the expected type.\ncheck: 2 functions, 1 errors'

printf '%s\n' 'type Choice { Left(i64), Right(i64) } fn bad(value: Choice) -> i64 { match value { Left(n) -> n } }' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_exhaustiveness_teaches_counterexample_golden" "$diag_out" $'line 1, col 76: error[E1003]: non-exhaustive match: value `Right(0)` is not covered\n  |\n1 | type Choice { Left(i64), Right(i64) } fn bad(value: Choice) -> i64 { match value { Left(n) -> n } }\n  |                                                                            ^~~~~ non-exhaustive match: value `Right(0)` is not covered\nline 1, col 6: note: matched type declared here\n  |\n1 | type Choice { Left(i64), Right(i64) } fn bad(value: Choice) -> i64 { match value { Left(n) -> n } }\n  |      ^~~~~~ matched type declared here\nhelp: add an arm matching `Right(0)`; the uncovered witness is `Right(0)`.\ncheck: 1 functions, 1 errors'

printf '%s\n' 'effect Box<T> { fn get() -> T } fn need() -[Box<str>]> str { Box.get() } fn bad() -> i64 { handle need() { Box<i64>.get() -> resume(42) } 0 }' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_effect_discharge_teaches_parameter_identity_golden" "$diag_out" $'line 1, col 99: error[E2001]: effect `Box<str>` is not available in this context\n  |\n1 | ... -[Box<str>]> str { Box.get() } fn bad() -> i64 { handle need() { Box<i64>.get() -> resume(42) } 0 }\n  |                                                             ^~~~ effect `Box<str>` is not available in this context\nline 1, col 108: note: nearest handler handles a different instantiation of this effect\n  |\n1 | ... -[Box<str>]> str { Box.get() } fn bad() -> i64 { handle need() { Box<i64>.get() -> resume(42) } 0 }\n  |                                                                      ^~~ nearest handler handles a different instantiation of this effect\nline 1, col 36: note: callee declares this effect\n  |\n1 | ...T> { fn get() -> T } fn need() -[Box<str>]> str { Box.get() } fn bad() -> i64 { handle need() { Box<...\n  |                            ^~~~ callee declares this effect\nhelp: `Box<i64>` is available, but it does not discharge `Box<str>`; effect type arguments are part of capability identity.\ncheck: 458 functions, 1 errors'

printf '%s\n' 'type Box<T> { Box(T) } trait Marked { } trait Identity { } impl Marked for i64 { } impl<T: Marked> Identity for Box<T> { } fn need<T: Identity>(value: T) -> T { value } fn main() -> Box<bool> { need<Box<bool>>(Box<bool>(true)) }' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_trait_conformance_replays_conditional_proof_golden" "$diag_out" $'line 1, col 200: error[E1004]: type `Box<bool>` does not implement `Identity`\n  |\n1 | ...ed<T: Identity>(value: T) -> T { value } fn main() -> Box<bool> { need<Box<bool>>(Box<bool>(true)) }\n  |                                                                           ^~~~~~~~~ type `Box<bool>` does not implement `Identity`\nline 1, col 113: note: matching impl candidate rejected by its own bound\n  |\n1 | ...T: Marked> Identity for Box<T> { } fn need<T: Identity>(value: T) -> T { value } fn main() -> Box<bo...\n  |                            ^~~ matching impl candidate rejected by its own bound\nline 1, col 135: note: required by this trait bound\n  |\n1 | ...r Box<T> { } fn need<T: Identity>(value: T) -> T { value } fn main() -> Box<bool> { need<Box<bool>>(...\n  |                            ^~~~~~~~ required by this trait bound\nline 1, col 47: note: trait declared here\n  |\n1 | ... trait Marked { } trait Identity { } impl Marked for i64 { } impl<T: Marked> Identity for Box<T> { }...\n  |                            ^~~~~~~~ trait declared here\nline 1, col 6: note: target type declared here\n  |\n1 | type Box<T> { Box(T) } trait Marked { } trait Identity { } impl Marked for i64 { } impl<T: Marked> I...\n  |      ^~~ target type declared here\nhelp: a matching `Box<T>` impl candidate exists, but it requires `bool: Marked`; satisfy that nested bound or use another type.\ncheck: 458 functions, 1 errors'

printf '%s\n' 'fn main() -> i64 { let café = 1 café }' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_rejects_non_nfc_identifier_at_scalar_column" "$diag_out" $'line 1, col 24: error[E0001]: identifier must use NFC normalization\n  |\n1 | fn main() -> i64 { let café = 1 café }\n  |                        ^~~~~ identifier must use NFC normalization\ncheck: 0 functions, 1 errors'

printf '\303(' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_rejects_malformed_utf8_before_tokenization" "$diag_out" $'line 1, col 1: error[E0001]: source is not valid UTF-8\n  |\n1 | \x5cxC3(\n  | ^~~~ source is not valid UTF-8\ncheck: 0 functions, 1 errors'

printf '%s\n' 'fn paypal() -> i64 { 20 } fn pаypаl() -> i64 { 22 } fn main() -> i64 { paypal() + pаypаl() }' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_equals "diagnostic_unicode_security_warnings_do_not_fail_check" "$diag_out" $'line 1, col 30: warning[W0001]: identifier contains mixed scripts\n  |\n1 | fn paypal() -> i64 { 20 } fn pаypаl() -> i64 { 22 } fn main() -> i64 { paypal() + pаypаl() }\n  |                              ^~~~~~ identifier contains mixed scripts\nline 1, col 30: warning[W0002]: identifier is confusable with another spelling in this source\n  |\n1 | fn paypal() -> i64 { 20 } fn pаypаl() -> i64 { 22 } fn main() -> i64 { paypal() + pаypаl() }\n  |                              ^~~~~~ identifier is confusable with another spelling in this source\nline 1, col 4: note: confusable spelling appears here\n  |\n1 | fn paypal() -> i64 { 20 } fn pаypаl() -> i64 { 22 } fn main() -> i64 { paypal() + pаypаl() }\n  |    ^~~~~~ confusable spelling appears here\ncheck: 3 functions, 0 errors'

printf '%s' $'-- abc\u202Edef\nfn main() -> i64 { 42 }\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_equals "diagnostic_bidi_comment_warning_does_not_fail_check" "$diag_out" $'line 1, col 7: warning[W0003]: source text contains an invisible bidi formatting control\n  |\n1 | -- abc\x5cu{202E}def\n  |       ^~~~~~~~ source text contains an invisible bidi formatting control\ncheck: 1 functions, 0 errors'

printf 'fn broken() -> i64 { 1\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_eof_insertion_has_zero_width_caret" "$diag_out" $'line 2, col 1: error[E0002]: expected \x27}\x27 before end of file\n  |\n2 | \n  | ^ expected \x27}\x27 before end of file\nline 1, col 20: note: construct opened here\n  |\n1 | fn broken() -> i64 { 1\n  |                    ^ construct opened here\nhelp: insert `}` to close this block.\ncheck: 1 functions, 1 errors'

printf 'fn main() -> i64 {\n\tmissing\n}\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_tabs_expand_with_matching_caret" "$diag_out" $'line 2, col 2: error[E1001]: unknown identifier \x27missing\x27\n  |\n2 |     missing\n  |     ^~~~~~~ unknown identifier \x27missing\x27\ncheck: 1 functions, 1 errors'

printf '%s\n' 'fn main() -> i64 { let abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz = 1 missing }' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_equals "diagnostic_long_line_clips_around_primary" "$diag_out" $'line 1, col 133: error[E1001]: unknown identifier \x27missing\x27\n  |\n1 | ...stuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz = 1 missing }\n  |                                                                                               ^~~~~~~ unknown identifier \x27missing\x27\ncheck: 1 functions, 1 errors'

run_weft_compile_guarded "$WEFT" compile test/fixtures/diagnostic_frame_probe.weft > "$tmp_bin" 2>"$tmp_err"
chmod +x "$tmp_bin"
diag_out=$(run_binary_guarded "$tmp_bin" 2>&1)
assert_equals "diagnostic_multiline_range_clips_middle_lines" "$diag_out" $'probe.weft: line 1, col 3: error: range crosses the omitted middle\n  |\n1 | zero\n  |   ^~\n2 | one two\n  | ^~~~~~~\n... | ...\n6 | six seven\n  | ^~~~~~~~~\n7 | eight\n  | ^~~ range crosses the omitted middle'

mcp_out=$(printf '%s' '{ "jsonrpc" : "2.0", "id" : 1, "method" : "tools/list" }' | "$WEFT" mcp 2>&1)
assert_equals "mcp_tools_list_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"schema_version":1,"tools":[{"name":"parse_summary","stability":"internal"},{"name":"check_summary","stability":"internal"},{"name":"ir_summary","stability":"internal"},{"name":"type_lookup","stability":"stable"},{"name":"effect_lookup","stability":"stable"},{"name":"diagnostics","stability":"stable"},{"name":"grammar_parse","stability":"internal"},{"name":"grammar_check","stability":"internal"},{"name":"grammar_diagnostics","stability":"stable"},{"name":"opt_counters","stability":"internal"},{"name":"fact_at_position","stability":"stable"},{"name":"visible_bindings","stability":"stable"},{"name":"conformance_at_position","stability":"stable"},{"name":"format_source","stability":"stable"}]}}'
mcp_tools_list_expected="$mcp_out"

mcp_out=$(printf '%s' '{"jsonr\u0070c":"2.0","i\u0064":1,"meth\u006fd":"tools\/list","meta":"\uD83D\uDC69"}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_decodes_escaped_keys_methods_and_surrogate_pairs" "$mcp_out" "$mcp_tools_list_expected"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/list","meta":"\uD800"}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_rejects_unpaired_high_surrogate" "$mcp_out" '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"invalid json-rpc"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/list","meta":"\uDC00"}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_rejects_unpaired_low_surrogate" "$mcp_out" '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"invalid json-rpc"}}'

mcp_out=$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/list","meta":"\303("}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_rejects_malformed_raw_utf8" "$mcp_out" '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"invalid json-rpc"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/list","meta":[true,null,1,-2.5,3e4,{"x":"y"}]}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_nested_extra_json_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"schema_version":1,"tools":[{"name":"parse_summary","stability":"internal"},{"name":"check_summary","stability":"internal"},{"name":"ir_summary","stability":"internal"},{"name":"type_lookup","stability":"stable"},{"name":"effect_lookup","stability":"stable"},{"name":"diagnostics","stability":"stable"},{"name":"grammar_parse","stability":"internal"},{"name":"grammar_check","stability":"internal"},{"name":"grammar_diagnostics","stability":"stable"},{"name":"opt_counters","stability":"internal"},{"name":"fact_at_position","stability":"stable"},{"name":"visible_bindings","stability":"stable"},{"name":"conformance_at_position","stability":"stable"},{"name":"format_source","stability":"stable"}]}}'

# Formatter transports are framing-only adapters over the CLI engine. Derive
# the expected bytes from `weft fmt` so Unicode and JSON escape handling cannot
# silently drift between CLI, MCP, and LSP.
format_transport_source=$'-- Ω\n''fn   value ( ) -> str { "a\n\"b" }'
format_cli=$(printf '%s' "$format_transport_source" | "$WEFT" fmt 2>"$tmp_err")
assert_equals "format_transport_cli_stderr_empty" "$(<"$tmp_err")" ""
format_transport_source_json=$(json_escape_bytes "$format_transport_source")
format_cli_json=$(json_escape_bytes "$format_cli")

mcp_out=$(printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"format_source\",\"arguments\":{\"source\":\"$format_transport_source_json\"}}}" | "$WEFT" mcp 2>&1)
assert_equals "mcp_format_source_matches_cli_bytes" "$mcp_out" "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tool\":\"format_source\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"formatted\":\"$format_cli_json\",\"diagnostics\":0,\"position_units\":{\"span\":\"utf-8-byte-offset\",\"line_base\":1,\"col\":\"utf-8-byte-column\",\"scalar_col\":\"unicode-scalar-column\",\"utf16_col\":\"utf-16-code-unit-column\"},\"items\":[]}}"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"format_source","arguments":{"source":"fn broken -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_format_source_parse_failure_is_structured" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"format_source","ok":false,"schema_version":1,"stability":"stable","error_count":1,"diagnostics":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"expected '\''('\'' after function name","code":"E0002","span":10,"line":1,"col":11,"scalar_col":11,"utf16_col":11,"end_span":12,"end_line":1,"end_col":13,"end_scalar_col":13,"end_utf16_col":13,"diagnostic":{"schema_version":1,"severity":"error","class":"parse","code":"E0002","message":"expected '\''('\'' after function name","position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"primary":{"source":{"kind":"input"},"span":10,"end_span":12,"line":1,"col":11,"scalar_col":11,"utf16_col":11,"end_line":1,"end_col":13,"end_scalar_col":13,"end_utf16_col":13},"related":[],"fields":[{"kind":"text","name":"reason","value":"syntax_error"},{"kind":"text","name":"context","value":"function declaration"},{"kind":"text","name":"expectation","value":"expected '\''('\'' after function name"},{"kind":"text","name":"found","value":"->"},{"kind":"text","name":"recovery","value":"resume_at_declaration"}]}}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"format_source","arguments":{}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_format_source_requires_source" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing source"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source" : "fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_parse_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"use stdlib/io.{IO} fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_parse_summary_import_isolation_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_check_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"check_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"use stdlib/io.{IO} fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_check_summary_import_isolation_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"check_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_ir_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"ir_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"blocks":1,"insts":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"use stdlib/io.{IO} fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_ir_summary_import_isolation_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"ir_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"blocks":1,"insts":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"effect E { @deferred fn get() -> i64 } fn f() -> i64 { handle E.get() { E.get() with k -> k(20) } } test \"x\" { Test.assert_eq(f(), 20) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_ir_summary_test_deferred_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"ir_summary","ok":true,"schema_version":1,"stability":"internal","functions":2,"blocks":3,"insts":4}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn add(x: i64, y: i64) -[Log]> i64 { x + y }\neffect Log { fn hit() -> i64 }","name":"add"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_function_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"schema_version":1,"stability":"stable","name":"add","found":true,"fact":{"kind":"function","name":"add","parameters":[{"name":"x","type":{"kind":"primitive","name":"i64"}},{"name":"y","type":{"kind":"primitive","name":"i64"}}],"return_type":{"kind":"primitive","name":"i64"},"effects":{"kind":"closed","atoms":[{"name":"Log","arguments":[]}]},"purity":"effectful","ownership":{"kind":"borrowed_parameters","indices":[]},"return_shape":{"kind":"words","count":1,"lanes":["gpr"]},"bounds":{"kind":"type_parameters","parameters":[]}}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn choose(xs: [i64], ys: [i64], first: bool) -> [i64] { if first { xs } else { ys } } fn forward(xs: [i64], ys: [i64], first: bool) -> [i64] { choose(xs, ys, first) }","name":"forward"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_interprocedural_borrow_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"schema_version":1,"stability":"stable","name":"forward","found":true,"fact":{"kind":"function","name":"forward","parameters":[{"name":"xs","type":{"kind":"slice","element":{"kind":"primitive","name":"i64"},"mutable":false}},{"name":"ys","type":{"kind":"slice","element":{"kind":"primitive","name":"i64"},"mutable":false}},{"name":"first","type":{"kind":"primitive","name":"bool"}}],"return_type":{"kind":"slice","element":{"kind":"primitive","name":"i64"},"mutable":false},"effects":{"kind":"closed","atoms":[]},"purity":"pure","ownership":{"kind":"borrowed_parameters","indices":[0,1]},"return_shape":{"kind":"words","count":2,"lanes":["gpr","gpr"]},"bounds":{"kind":"type_parameters","parameters":[]}}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn identity<T>(value: T) -> T { value }","name":"identity"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_type_lookup_generic_borrow_snapshot" "$mcp_out" '"ownership":{"kind":"borrowed_parameters","indices":[0]}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn opaque(f: ([i64]) -> [i64], xs: [i64]) -> [i64] { f(xs) }","name":"opaque"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_type_lookup_unknown_borrow_snapshot" "$mcp_out" '"ownership":{"kind":"unknown"}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"type Pair { left: i64, right: str }\nfn main() -> i64 { 0 }","name":"Pair"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_record_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"schema_version":1,"stability":"stable","name":"Pair","found":true,"fact":{"kind":"type_declaration","name":"Pair","declaration_kind":"record","type_parameters":[],"items":2}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"type Secret<T> = opaque T\nfn main() -> i64 { 0 }","name":"Secret"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_opaque_hides_representation" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"schema_version":1,"stability":"stable","name":"Secret","found":true,"fact":{"kind":"type_declaration","name":"Secret","declaration_kind":"opaque","type_parameters":[{"name":"T","bounds":{"kind":"traits","traits":[]}}],"items":0}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn main() -> i64 { 0 }","name":"missing"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"schema_version":1,"stability":"stable","name":"missing","found":false}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"effect Log { fn hit(x: i64) -> bool }\nfn main() -> i64 { 0 }","name":"Log"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"schema_version":1,"stability":"stable","name":"Log","found":true,"fact":{"kind":"effect_declaration","name":"Log","type_parameters":[],"operations":[{"name":"hit","parameters":[{"name":"x","type":{"kind":"primitive","name":"i64"}}],"return_type":{"kind":"primitive","name":"bool"},"deferred":false}]}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"effect Async { @deferred fn wait() -> i64 }\nfn main() -> i64 { 0 }","name":"Async"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_deferred_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"schema_version":1,"stability":"stable","name":"Async","found":true,"fact":{"kind":"effect_declaration","name":"Async","type_parameters":[],"operations":[{"name":"wait","parameters":[],"return_type":{"kind":"primitive","name":"i64"},"deferred":true}]}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn fact_invoke<E>(body: () -[E]> i64) -[E]> i64 { body() }","name":"fact_invoke"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_open_effect_fact_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"schema_version":1,"stability":"stable","name":"fact_invoke","found":true,"fact":{"kind":"function","name":"fact_invoke","parameters":[{"name":"body","type":{"kind":"function","parameters":[],"return_type":{"kind":"primitive","name":"i64"},"effects":{"kind":"open","atoms":[],"tail":"E"}}}],"return_type":{"kind":"primitive","name":"i64"},"effects":{"kind":"open","atoms":[],"tail":"E"},"purity":"open","ownership":{"kind":"unknown"},"return_shape":{"kind":"words","count":1,"lanes":["gpr"]},"bounds":{"kind":"type_parameters","parameters":[{"name":"E","bounds":{"kind":"traits","traits":[]}}]}}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"effect Box<T> { fn get(value: T) -> T } fn main() -> i64 { 0 }","name":"Box"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_parameterized_fact_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"schema_version":1,"stability":"stable","name":"Box","found":true,"fact":{"kind":"effect_declaration","name":"Box","type_parameters":[{"name":"T","bounds":{"kind":"traits","traits":[]}}],"operations":[{"name":"get","parameters":[{"name":"value","type":{"kind":"variable","name":"T"}}],"return_type":{"kind":"variable","name":"T"},"deferred":false}]}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"use stdlib/drop.{*} type ToolBorrowToken = opaque i64 impl Drop for ToolBorrowToken { fn drop(self) -> nil { nil } } effect ToolBorrowEffect { fn inspect(token: borrow ToolBorrowToken) -> i64 fn mutate(token: borrow mut ToolBorrowToken) -> nil } fn main() -> i64 { 0 }","name":"ToolBorrowEffect"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_borrow_contract_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"schema_version":1,"stability":"stable","name":"ToolBorrowEffect","found":true,"fact":{"kind":"effect_declaration","name":"ToolBorrowEffect","type_parameters":[],"operations":[{"name":"inspect","parameters":[{"name":"token","type":{"kind":"borrow","inner":{"kind":"named","name":"ToolBorrowToken","arguments":[]},"mutable":false}}],"return_type":{"kind":"primitive","name":"i64"},"deferred":false},{"name":"mutate","parameters":[{"name":"token","type":{"kind":"borrow","inner":{"kind":"named","name":"ToolBorrowToken","arguments":[]},"mutable":true}}],"return_type":{"kind":"primitive","name":"nil"},"deferred":false}]}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"trait First { } trait Second { } fn layout<T: First & Second>(value: T) -> (f32, f64, i64) { (1.0, 2.0, 3) }","name":"layout"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_type_lookup_exact_lane_layout" "$mcp_out" '"return_shape":{"kind":"words","count":3,"lanes":["f32","f64","gpr"]}'
assert_contains "mcp_type_lookup_resolved_trait_bounds" "$mcp_out" '"bounds":{"kind":"type_parameters","parameters":[{"name":"T","bounds":{"kind":"traits","traits":["First","Second"]}}]}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"fn main() -> i64 { 0 }","name":"Missing"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"schema_version":1,"stability":"stable","name":"Missing","found":false}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fact_at_position","arguments":{"source":"fn main() -> i64 { 0 }","offset":7}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_fact_at_position_cursor_end_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"fact_at_position","ok":true,"schema_version":1,"stability":"stable","offset":7,"found":true,"fact":{"kind":"symbol","name":"main","symbol_kind":"function","type":{"kind":"function","parameters":[],"return_type":{"kind":"primitive","name":"i64"},"effects":{"kind":"closed","atoms":[]}},"occurrence":{"path":"","start":3,"length":4},"definition":{"path":"","start":3,"length":4}}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fact_at_position","arguments":{"source":"fn main() -> i64 { 0 }","offset":8}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_fact_at_position_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"fact_at_position","ok":true,"schema_version":1,"stability":"stable","offset":8,"found":false}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fact_at_position","arguments":{"source":"const ANSWER: i64 = 42 fn main() -> i64 { ANSWER }","offset":47}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_fact_at_position_constant_kind" "$mcp_out" '"symbol_kind":"constant"'
assert_contains "mcp_fact_at_position_constant_type" "$mcp_out" '"type":{"kind":"primitive","name":"i64"}'

mcp_binding_source='fn inspect(value: i64) -> i64 { value }'
mcp_binding_prefix='fn inspect(value: i64) -> i64 { '
mcp_binding_offset=${#mcp_binding_prefix}
mcp_out=$(printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"visible_bindings\",\"arguments\":{\"source\":\"$mcp_binding_source\",\"offset\":$mcp_binding_offset}}}" | "$WEFT" mcp 2>&1)
assert_contains "mcp_visible_bindings_schema" "$mcp_out" "{\"tool\":\"visible_bindings\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"offset\":$mcp_binding_offset,\"bindings\":["
assert_contains "mcp_visible_bindings_typed_parameter" "$mcp_out" '{"name":"value","symbol_kind":"parameter","type":{"kind":"primitive","name":"i64"}}'

mcp_conformance_source='trait Mark { fn mark(self) -> i64 } impl Mark for i64 { fn mark(self: i64) -> i64 { self } } fn main() -> i64 { let value = 1 let other = true if other { value } else { value } }'
mcp_conformance_value_prefix='trait Mark { fn mark(self) -> i64 } impl Mark for i64 { fn mark(self: i64) -> i64 { self } } fn main() -> i64 { let value = 1 let other = true if other { '
mcp_conformance_value_offset=${#mcp_conformance_value_prefix}
mcp_conformance_bool_prefix='trait Mark { fn mark(self) -> i64 } impl Mark for i64 { fn mark(self: i64) -> i64 { self } } fn main() -> i64 { let value = 1 let other = true if '
mcp_conformance_bool_offset=${#mcp_conformance_bool_prefix}
mcp_out=$(printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"conformance_at_position\",\"arguments\":{\"source\":\"$mcp_conformance_source\",\"offset\":$mcp_conformance_value_offset,\"trait\":\"Mark\"}}}" | "$WEFT" mcp 2>&1)
assert_equals "mcp_conformance_at_position_yes_snapshot" "$mcp_out" "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tool\":\"conformance_at_position\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"offset\":$mcp_conformance_value_offset,\"found\":true,\"fact\":{\"kind\":\"conformance\",\"type\":{\"kind\":\"primitive\",\"name\":\"i64\"},\"trait\":\"Mark\",\"decision\":\"yes\"}}}"

mcp_out=$(printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"conformance_at_position\",\"arguments\":{\"source\":\"$mcp_conformance_source\",\"offset\":$mcp_conformance_bool_offset,\"trait\":\"Mark\"}}}" | "$WEFT" mcp 2>&1)
assert_equals "mcp_conformance_at_position_no_snapshot" "$mcp_out" "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tool\":\"conformance_at_position\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"offset\":$mcp_conformance_bool_offset,\"found\":true,\"fact\":{\"kind\":\"conformance\",\"type\":{\"kind\":\"primitive\",\"name\":\"bool\"},\"trait\":\"Mark\",\"decision\":\"no\"}}}"

mcp_out=$(printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"conformance_at_position\",\"arguments\":{\"source\":\"$mcp_conformance_source\",\"offset\":$mcp_conformance_value_offset,\"trait\":\"MissingTrait\"}}}" | "$WEFT" mcp 2>&1)
assert_equals "mcp_conformance_at_position_unknown_trait_snapshot" "$mcp_out" "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tool\":\"conformance_at_position\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"offset\":$mcp_conformance_value_offset,\"found\":true,\"fact\":{\"kind\":\"conformance\",\"type\":{\"kind\":\"primitive\",\"name\":\"i64\"},\"trait\":\"MissingTrait\",\"decision\":{\"kind\":\"unknown\",\"reason\":\"unknown_trait\"}}}}"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fact_at_position","arguments":{"source":"fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_fact_at_position_requires_offset" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing position offset"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"fact_at_position","arguments":{"source":"fn main() -> i64 { 0 }","offset":99}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_fact_at_position_rejects_out_of_range" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"position offset out of range"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"conformance_at_position","arguments":{"source":"fn main() -> i64 { 0 }","offset":3}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_conformance_at_position_requires_trait" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing trait name"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_clean_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":0,"functions":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"test \"x\" { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_test_block_clean_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":0,"functions":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"use test/negative/import_cycle_direct fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_module_cycle_stable_code" "$mcp_out" '"code":"E4001"'
assert_contains "mcp_module_cycle_message" "$mcp_out" 'circular import: test/negative/import_cycle_direct -> test/negative/import_cycle_direct'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"use module_fixtures/g2_function_left as left fn main() -> i64 { left.missing() }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_module_member_stable_code" "$mcp_out" '"code":"E4002"'
assert_contains "mcp_module_member_qualified_name" "$mcp_out" "unknown module member 'left.missing'"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"use module_fixtures/g2_function_left.{missing} fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_module_scope_audit_stable_code" "$mcp_out" '"code":"E4002"'
assert_contains "mcp_module_scope_audit_message" "$mcp_out" "unknown module member 'missing' in import"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -[Unsafe]> i64 { __mem_load64(0) }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostics_rejects_root_raw_memory" "$mcp_out" "type error: Unsafe is sealed to trusted runtime/platform code"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_parse","arguments":{"grammar":"mini_sql","source":"select id, name from users where id = 1"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_parse","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"users","where":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select id from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select nope from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_unknown_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"users","where":0,"check_errors":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo from invoices where memo = '\''paid'\''","host_source":"type invoices { total: i64, memo: str }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_source_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo from invoices where total >= 10 and paid = true","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_compound_predicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo as label, total amount, true marker from invoices where paid","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_projection_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":3,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select total + 5 adjusted, memo || '\''!'\'' label from invoices where total * 2 >= 20","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_scalar_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo from invoices where paid order by total + 5 desc, memo || '\''!'\''","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_order_by_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo from invoices where paid order by total desc limit total + 5 offset 1","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_limit_offset_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select paid, count(*), sum(total) from invoices group by paid order by sum(total) desc limit 10","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_group_aggregate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":3,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select paid, count(*), sum(total) from invoices group by paid having sum(total) > 100 and paid = true order by sum(total) desc limit 10","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_having_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":3,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select total + 5 adjusted, memo from invoices order by adjusted desc","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_order_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select paid, sum(total) total_due from invoices group by paid having total_due > 100 order by total_due desc","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_having_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select i.paid, sum(i.total) as total_due from invoices i group by i.paid having total_due > 100 order by i.paid","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_qualified_ref_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select u.name, o.total from users u join orders o on u.id = o.user_id","host_source":"type users { id: i64, name: str, active: bool }\ntype orders { id: i64, user_id: i64, total: i64 }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_join_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select distinct name from users order by name"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_distinct_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"distinct":1,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select distinct u.name, o.total from users u join orders o on u.id = o.user_id","host_source":"type users { id: i64, name: str, active: bool }\ntype orders { id: i64, user_id: i64, total: i64 }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_distinct_join_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"schema_version":1,"stability":"internal","grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"distinct":1,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select nope from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_type_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select nope from invoices","host_source":"type invoices { total: i64, memo: str }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_unknown_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total from invoices where total = '\''bad'\''","host_source":"type invoices { total: i64, memo: str }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_predicate_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: predicate type mismatch","span":42,"line":1,"col":43,"scalar_col":43,"utf16_col":43}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users where name > '\''Ada'\''","host_source":"type users { id: i64, name: str, active: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_relational_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: relational predicate requires i64","span":35,"line":1,"col":36,"scalar_col":36,"utf16_col":36}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users where id and active = true","host_source":"type users { id: i64, name: str, active: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_logical_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: logical predicate operand must be bool","span":27,"line":1,"col":28,"scalar_col":28,"utf16_col":28}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select missing as alias from invoices","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_projection_unknown_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select memo + 1 from invoices","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_arithmetic_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: arithmetic expression requires i64","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total || '\''!'\'' from invoices","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_concat_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: concat expression requires str","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total from invoices where memo + 1 = 2","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_predicate_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: arithmetic expression requires i64","span":33,"line":1,"col":34,"scalar_col":34,"utf16_col":34}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select memo from invoices order by missing","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_order_unknown_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":35,"line":1,"col":36,"scalar_col":36,"utf16_col":36}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users order by"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_order_missing_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected order expression","span":29,"line":1,"col":30,"scalar_col":30,"utf16_col":30}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users order id"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_order_missing_by_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected BY","span":27,"line":1,"col":28,"scalar_col":28,"utf16_col":28}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select memo from invoices limit memo","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_limit_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: limit expression requires i64","span":32,"line":1,"col":33,"scalar_col":33,"utf16_col":33}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users limit"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_limit_missing_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected limit expression","span":26,"line":1,"col":27,"scalar_col":27,"utf16_col":27}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users offset 1 limit 2"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_limit_after_offset_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: unexpected trailing input","span":30,"line":1,"col":31,"scalar_col":31,"utf16_col":31}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select paid, memo, count(*) from invoices group by paid","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_ungrouped_projection_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: non-aggregate projection must appear in GROUP BY","span":13,"line":1,"col":14,"scalar_col":14,"utf16_col":14}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select sum(memo) from invoices","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_sum_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: aggregate sum requires i64","span":11,"line":1,"col":12,"scalar_col":12,"utf16_col":12}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users group by"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_missing_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected group expression","span":29,"line":1,"col":30,"scalar_col":30,"utf16_col":30}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select avg(id) from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_unknown_aggregate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: unknown aggregate function","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select count(*) from users limit count(*)"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_aggregate_tail_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: aggregate not allowed in query tail","span":33,"line":1,"col":34,"scalar_col":34,"utf16_col":34}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select paid, count(*) from invoices group by paid having memo = '\''late'\''","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_having_ungrouped_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: non-aggregate HAVING expression must appear in GROUP BY","span":57,"line":1,"col":58,"scalar_col":58,"utf16_col":58}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select paid, count(*) from invoices group by paid having count(*)","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_having_non_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: having expression must be bool","span":57,"line":1,"col":58,"scalar_col":58,"utf16_col":58}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select count(*) from users having"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_having_missing_predicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected predicate expression","span":33,"line":1,"col":34,"scalar_col":34,"utf16_col":34}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total as x, memo as x from invoices order by x","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_ambiguous_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: ambiguous projection alias","span":52,"line":1,"col":53,"scalar_col":53,"utf16_col":53}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total as memo from invoices order by memo + 1","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_alias_column_shadow_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: arithmetic expression requires i64","span":44,"line":1,"col":45,"scalar_col":45,"utf16_col":45}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select o.memo from invoices as i","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_qualified_unknown_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: unknown table qualifier","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select i. from invoices i","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_qualified_missing_field_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected field after '\''.'\''","span":10,"line":1,"col":11,"scalar_col":11,"utf16_col":11}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select i.memo + 1 from invoices i","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_qualified_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: arithmetic expression requires i64","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users join orders on users.id = orders.user_id"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_join_ambiguous_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: ambiguous column","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select u.name from users u join orders o on u.name = o.total"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_join_predicate_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: predicate type mismatch","span":53,"line":1,"col":54,"scalar_col":54,"utf16_col":54}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select u.name from users u join orders o"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_join_missing_on_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected ON","span":40,"line":1,"col":41,"scalar_col":41,"utf16_col":41}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select distinct id from users join orders on users.id = orders.user_id"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_distinct_ambiguous_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql type error: ambiguous column","span":16,"line":1,"col":17,"scalar_col":17,"utf16_col":17}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id as distinct from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_distinct_alias_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":2,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected alias after AS","span":13,"line":1,"col":14,"scalar_col":14,"utf16_col":14},{"severity":"error","message":"mini_sql parse error: expected FROM","span":13,"line":1,"col":14,"scalar_col":14,"utf16_col":14}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_parse_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":2,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected FROM","span":15,"line":1,"col":16,"scalar_col":16,"utf16_col":16},{"severity":"error","message":"mini_sql parse error: expected table name","span":15,"line":1,"col":16,"scalar_col":16,"utf16_col":16}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id as from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_alias_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected alias after AS","span":13,"line":1,"col":14,"scalar_col":14,"utf16_col":14}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id + from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_scalar_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected expression after operator","span":12,"line":1,"col":13,"scalar_col":13,"utf16_col":13}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users where id >= 1 and"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_predicate_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"schema_version":1,"stability":"stable","grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"mini_sql parse error: expected predicate expression","span":38,"line":1,"col":39,"scalar_col":39,"utf16_col":39}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_parse","arguments":{"grammar":"bogus","source":"select id from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_unknown_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"unknown grammar"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_parse","arguments":{"source":"select id from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing grammar"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"\nfn broken -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_parse_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"expected '\''('\'' after function name","code":"E0002","span":11,"line":2,"col":11,"scalar_col":11,"utf16_col":11,"end_span":13,"end_line":2,"end_col":13,"end_scalar_col":13,"end_utf16_col":13}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn one -> i64 { 0 }\nfn two -> i64 { 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_many_parse_errors_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":2,"functions":2,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"expected '\''('\'' after function name","code":"E0002","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8,"end_span":9,"end_line":1,"end_col":10,"end_scalar_col":10,"end_utf16_col":10},{"severity":"error","message":"expected '\''('\'' after function name","code":"E0002","span":27,"line":2,"col":8,"scalar_col":8,"utf16_col":8,"end_span":29,"end_line":2,"end_col":10,"end_scalar_col":10,"end_utf16_col":10}]}}'

large_mcp_source=""
for ((i = 0; i < 40; i++)); do
  large_mcp_source+="fn broken$i -> i64 { $i } "
done
mcp_out=$(printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"diagnostics\",\"arguments\":{\"source\":\"$large_mcp_source\"}}}" | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostics_large_response_count" "$mcp_out" '"diagnostics":40'
assert_contains "mcp_diagnostics_large_response_items" "$mcp_out" '"items":[{"severity":"error"'

# The stable wire value is the producer-owned Diagnostic, not a reconstruction
# from its message. Cover every field family through real parser/checker
# producers and retain a few fragments for the LSP parity assertions below.
wire_type_expected='{"kind":"type","name":"expected_type","value":{"kind":"primitive","name":"i64"}}'
wire_type_found='{"kind":"type","name":"found_type","value":{"kind":"primitive","name":"str"}}'
wire_effect_atom='{"kind":"effect_atom","name":"missing_effect","value":{"name":"Box","arguments":[{"kind":"primitive","name":"str"}]}}'
wire_effect_set='{"kind":"effect_set","name":"available_effects","value":{"kind":"closed","atoms":[{"name":"Box","arguments":[{"kind":"primitive","name":"i64"}]}]}}'
wire_unknown_suggestion='{"kind":"suggestion","value":{"message":"replace the unresolved name","applicability":"maybe-incorrect"'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { let counter = 1 counte }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostic_wire_carries_stable_envelope" "$mcp_out" '"diagnostic":{"schema_version":1,"severity":"error","class":"type","code":"E1001"'
assert_contains "mcp_diagnostic_wire_names_anonymous_input" "$mcp_out" '"primary":{"source":{"kind":"input"}'
assert_contains "mcp_diagnostic_wire_carries_related_provenance" "$mcp_out" '"related":[{"label":"similarly named declaration","location":{"source":{"kind":"input"}'
assert_contains "mcp_diagnostic_wire_carries_text_field" "$mcp_out" '{"kind":"text","name":"suggestion","value":"counter"}'
assert_contains "mcp_diagnostic_wire_carries_i64_field" "$mcp_out" '{"kind":"i64","name":"suggestion_distance","value":1}'
assert_contains "mcp_diagnostic_wire_carries_location_field" "$mcp_out" '{"kind":"location","name":"suggestion_declaration","value":{"source":{"kind":"input"}'
assert_contains "mcp_diagnostic_wire_carries_suggestion" "$mcp_out" "$wire_unknown_suggestion"
assert_contains "mcp_diagnostic_wire_carries_typed_edit" "$mcp_out" '"replacement":"counter"'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn takes(value: i64) -> i64 { value } fn main() -> i64 { takes(\"snow\") }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostic_wire_carries_expected_type" "$mcp_out" "$wire_type_expected"
assert_contains "mcp_diagnostic_wire_carries_found_type" "$mcp_out" "$wire_type_found"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Box<T> { fn get() -> T } fn need() -[Box<str>]> i64 { 1 } fn bad() -[Box<i64>]> i64 { need() }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostic_wire_carries_exact_effect_atom" "$mcp_out" "$wire_effect_atom"
assert_contains "mcp_diagnostic_wire_carries_exact_effect_set" "$mcp_out" "$wire_effect_set"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait BoundNeed { fn val(self: i64) -> i64 } fn use_bound<T: BoundNeed>(x: T) -> i64 { x.val() } fn bad() -> i64 { use_bound<i64>(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostic_wire_carries_bool_field" "$mcp_out" '{"kind":"bool","name":"impl_allowed_here","value":true}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn broken() -> i64 { 1"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostic_wire_carries_machine_applicability" "$mcp_out" '"applicability":"machine-applicable"'
assert_contains "mcp_diagnostic_wire_preserves_zero_width_edit" "$mcp_out" '"span":22,"end_span":22'
assert_contains "mcp_diagnostic_wire_carries_insertion_text" "$mcp_out" '"replacement":"}"'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { missing }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_unknown_identifier_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"unknown identifier '\''missing'\''","code":"E1001","span":19,"line":1,"col":20,"scalar_col":20,"utf16_col":20,"end_span":26,"end_line":1,"end_col":27,"end_scalar_col":27,"end_utf16_col":27}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { let s = \"😀\" missing }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_names_byte_scalar_and_utf16_columns" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"unknown identifier '\''missing'\''","code":"E1001","span":34,"line":1,"col":35,"scalar_col":32,"utf16_col":33,"end_span":41,"end_line":1,"end_col":42,"end_scalar_col":39,"end_utf16_col":40}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { let café = 1 café }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_preserves_non_nfc_identifier_range" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":0,"check_errors":0,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"identifier must use NFC normalization","code":"E0001","span":23,"line":1,"col":24,"scalar_col":24,"utf16_col":24,"end_span":29,"end_line":1,"end_col":30,"end_scalar_col":29,"end_utf16_col":29}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn πρόσθεση(α: i64, β: i64) -> i64 { α + β } fn main() -> i64 { πρόσθεση(40, 2) }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostics_accepts_unicode_identifier_identity" "$mcp_out" '"diagnostics":0,"functions":2,"check_errors":0'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn paypal() -> i64 { 20 } fn pаypаl() -> i64 { 22 }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_unicode_security_warning_severity" "$mcp_out" '"severity":"warn"'
assert_contains "mcp_unicode_security_warning_mixed_script_code" "$mcp_out" '"code":"W0001"'
assert_contains "mcp_unicode_security_warning_confusable_code" "$mcp_out" '"code":"W0002"'
assert_contains "mcp_unicode_security_warnings_keep_zero_errors" "$mcp_out" '"check_errors":0'

bidi_source=$'fn main() -> str { "abc\u202Edef" }'
bidi_source_json=$(json_escape_bytes "$bidi_source")
mcp_out=$(printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"diagnostics\",\"arguments\":{\"source\":\"$bidi_source_json\"}}}" | "$WEFT" mcp 2>&1)
assert_contains "mcp_bidi_source_warning_code" "$mcp_out" '"code":"W0003"'
assert_contains "mcp_bidi_source_warning_range" "$mcp_out" '"span":23,"line":1,"col":24,"scalar_col":24,"utf16_col":24,"end_span":26'
assert_contains "mcp_bidi_source_warning_keeps_zero_errors" "$mcp_out" '"check_errors":0'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn call() -> i64 { missing_fn() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_unknown_function_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"unknown function '\''missing_fn'\''","code":"E1001","span":19,"line":1,"col":20,"scalar_col":20,"utf16_col":20,"end_span":29,"end_line":1,"end_col":30,"end_scalar_col":30,"end_utf16_col":30}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let x = 1 x() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_non_function_call_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"value is not callable: expected callable type `() -> any`, found `i64`","code":"E1002","span":28,"line":1,"col":29,"scalar_col":29,"utf16_col":29,"end_span":29,"end_line":1,"end_col":30,"end_scalar_col":30,"end_utf16_col":30}]}}'
assert_contains "mcp_diagnostics_non_function_call_expected_type" "$mcp_out" '"expected_type","value":{"kind":"function","parameters":[],"return_type":{"kind":"top"},"effects":{"kind":"closed","atoms":[]}}'
assert_contains "mcp_diagnostics_non_function_call_found_type" "$mcp_out" '"found_type","value":{"kind":"primitive","name":"i64"}'
assert_contains "mcp_diagnostics_non_function_call_reason" "$mcp_out" '"reason","value":"non_callable"'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id(x: i64) -> i64 { x } fn bad() -> i64 { id<i64>(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_generic_non_generic_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: generic call target is not generic","span":45,"line":1,"col":46,"scalar_col":46,"utf16_col":46}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let n = 42 n.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_field_non_record_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: field access on non-record","span":31,"line":1,"col":32,"scalar_col":32,"utf16_col":32}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Point { x: i64 } fn bad() -> i64 { let p = Point { x: 42, y: 0 } p.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_record_field_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: unknown record field","span":63,"line":1,"col":64,"scalar_col":64,"utf16_col":64}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let p = Missing { x: 42 } 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_record_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: unknown record type","span":26,"line":1,"col":27,"scalar_col":27,"utf16_col":27}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Shape { Circle(i64) } fn bad() -> i64 { let p = Shape { x: 42 } 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_record_init_variant_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: not a record type","span":53,"line":1,"col":54,"scalar_col":54,"utf16_col":54}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Point { x: i64, y: i64 } fn bad() -> i64 { let p = Point { x: 42 } p.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_missing_record_field_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: missing record field","span":56,"line":1,"col":57,"scalar_col":57,"utf16_col":57}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Point { x: i64 } fn bad() -> i64 { let p = Point { x: 1, x: 2 } p.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_duplicate_record_field_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: duplicate record field","span":62,"line":1,"col":63,"scalar_col":63,"utf16_col":63}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Point { x: i64 } fn bad() -> i64 { let p = Point { x: \"oops\" } p.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_record_field_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"record field type mismatch: expected `i64`, found `str`","code":"E1002","span":59,"line":1,"col":60,"scalar_col":60,"utf16_col":60,"end_span":65,"end_line":1,"end_col":66,"end_scalar_col":66,"end_utf16_col":66}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn add(a: i64, b: i64) -> i64 { a + b } fn bad() -> i64 { add(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_call_arity_few_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: arity mismatch","span":58,"line":1,"col":59,"scalar_col":59,"utf16_col":59}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id(x: i64) -> i64 { x } fn bad() -> i64 { id(1, 2) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_call_arity_many_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: arity mismatch","span":45,"line":1,"col":46,"scalar_col":46,"utf16_col":46}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id(x: i64) -> i64 { x } fn bad() -> i64 { id(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_call_arg_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"argument type mismatch: expected `i64`, found `str`","code":"E1002","span":48,"line":1,"col":49,"scalar_col":49,"utf16_col":49,"end_span":54,"end_line":1,"end_col":55,"end_scalar_col":55,"end_utf16_col":55}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id<T>(x: T) -> T { x } fn bad() -> i64 { id<i64>() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_generic_call_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: arity mismatch","span":44,"line":1,"col":45,"scalar_col":45,"utf16_col":45}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id<T>(x: T) -> T { x } fn bad() -> i64 { id<i64>(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_generic_call_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"argument type mismatch: expected `i64`, found `str`","code":"E1002","span":52,"line":1,"col":53,"scalar_col":53,"utf16_col":53,"end_span":58,"end_line":1,"end_col":59,"end_scalar_col":59,"end_utf16_col":59}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(f: (i64) -> i64) -> i64 { f(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_function_value_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"argument type mismatch: expected `i64`, found `str`","code":"E1002","span":35,"line":1,"col":36,"scalar_col":36,"utf16_col":36,"end_span":41,"end_line":1,"end_col":42,"end_scalar_col":42,"end_utf16_col":42}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type M { v: i64 } impl M { fn add(self: M, n: i64) -> i64 { self.v + n } } fn bad(b: M) -> i64 { b.add() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_method_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: arity mismatch","span":97,"line":1,"col":98,"scalar_col":98,"utf16_col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type M { v: i64 } impl M { fn add(self: M, n: i64) -> i64 { self.v + n } } fn bad(b: M) -> i64 { b.add(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_method_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"argument type mismatch: expected `i64`, found `str`","code":"E1002","span":103,"line":1,"col":104,"scalar_col":104,"utf16_col":104,"end_span":109,"end_line":1,"end_col":110,"end_scalar_col":110,"end_utf16_col":110}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Pair { fn add(a: i64, b: i64) -> i64 } fn bad() -[Pair]> i64 { Pair.add(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_effect_perform_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: arity mismatch","span":75,"line":1,"col":76,"scalar_col":76,"utf16_col":76}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Pair { fn add(a: i64, b: i64) -> i64 } fn bad() -[Pair]> i64 { Pair.add(1, \"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_effect_perform_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"argument type mismatch: expected `i64`, found `str`","code":"E1002","span":82,"line":1,"col":83,"scalar_col":83,"utf16_col":83,"end_span":88,"end_line":1,"end_col":89,"end_scalar_col":89,"end_utf16_col":89}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Pair { fn add(a: i64, b: i64) -> i64 } fn bad() -> i64 { handle Pair.add(1, 2) { Pair.add(a) -> resume(a) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_clause_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: arity mismatch","span":93,"line":1,"col":94,"scalar_col":94,"utf16_col":94}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Pair { fn add(a: i64, b: i64) -> i64 } fn bad() -> i64 { handle Pair.add(1, 2) { Pair.add(a: str, b: i64) -> resume(0) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_handler_clause_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"handler parameter type mismatch: expected `i64`, found `str`","code":"E1002","span":97,"line":1,"col":98,"scalar_col":98,"utf16_col":98,"end_span":98,"end_line":1,"end_col":99,"end_scalar_col":99,"end_utf16_col":99}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { State.get() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_effect_perform_unavailable_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"effect `State` is not available in this context","code":"E2001","span":51,"line":1,"col":52,"scalar_col":52,"utf16_col":52,"end_span":56,"end_line":1,"end_col":57,"end_scalar_col":57,"end_utf16_col":57}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Log { fn hit() -> i64 } fn bad(f: (i64) -[Log]> i64) -> i64 { f(41) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_function_value_effect_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"effect `Log` is not available in this context","code":"E2001","span":69,"line":1,"col":70,"scalar_col":70,"utf16_col":70,"end_span":70,"end_line":1,"end_col":71,"end_scalar_col":71,"end_utf16_col":71}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Log { fn hit() -> i64 } fn noisy<T>(x: T) -[Log]> i64 { Log.hit() } fn bad() -> i64 { noisy<i64>(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_generic_call_effect_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"effect `Log` is not available in this context","code":"E2001","span":93,"line":1,"col":94,"scalar_col":94,"utf16_col":94,"end_span":98,"end_line":1,"end_col":99,"end_scalar_col":99,"end_utf16_col":99}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect MethodEffect { fn ping() -> i64 } type Box { v: i64 } impl Box { fn noisy(self: i64) -[MethodEffect]> i64 { MethodEffect.ping() } } fn bad(b: Box) -> i64 { b.noisy() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_method_effect_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"effect `MethodEffect` is not available in this context","code":"E2001","span":165,"line":1,"col":166,"scalar_col":166,"utf16_col":166,"end_span":170,"end_line":1,"end_col":171,"end_scalar_col":171,"end_utf16_col":171}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedTwo { fn one(self: i64) -> i64 fn two(self: i64) -> i64 } type BoxNeed { v: i64 } impl NeedTwo for BoxNeed { fn one(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_missing_method_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: impl missing required method","span":109,"line":1,"col":110,"scalar_col":110,"utf16_col":110}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedArity { fn add(self: i64, n: i64) -> i64 } type BoxArity { v: i64 } impl NeedArity for BoxArity { fn add(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_method_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: impl method arity mismatch","span":97,"line":1,"col":98,"scalar_col":98,"utf16_col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedParam { fn set(self: i64, n: i64) -> i64 } type BoxParam { v: i64 } impl NeedParam for BoxParam { fn set(self: i64, n: str) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_method_param_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: impl method parameter type mismatch","span":97,"line":1,"col":98,"scalar_col":98,"utf16_col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedRet { fn get(self: i64) -> i64 } type BoxRet { v: i64 } impl NeedRet for BoxRet { fn get(self: i64) -> str { \"x\" } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_method_return_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: impl method return type mismatch","span":83,"line":1,"col":84,"scalar_col":84,"utf16_col":84}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect LogTrait { fn hit() -> i64 } trait NeedPure { fn get(self: i64) -> i64 } type BoxEff { v: i64 } impl NeedPure for BoxEff { fn get(self: i64) -[LogTrait]> i64 { LogTrait.hit() } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_method_effect_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: impl method effect mismatch","span":121,"line":1,"col":122,"scalar_col":122,"utf16_col":122}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedAssoc { type Item fn next(self: i64) -> i64 } type BoxAssocMissing { v: i64 } impl NeedAssoc for BoxAssocMissing { fn next(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_assoc_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: impl missing required associated type","span":107,"line":1,"col":108,"scalar_col":108,"utf16_col":108}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedAssocDup { type Item fn next(self: i64) -> i64 } type BoxAssocDup { v: i64 } impl NeedAssocDup for BoxAssocDup { type Item = i64 type Item = str fn next(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_assoc_duplicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: duplicate associated type binding","span":109,"line":1,"col":110,"scalar_col":110,"utf16_col":110}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedAssocExtra { fn next(self: i64) -> i64 } type BoxAssocExtra { v: i64 } impl NeedAssocExtra for BoxAssocExtra { type Item = i64 fn next(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_assoc_extra_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: impl associated type is not declared by trait","span":105,"line":1,"col":106,"scalar_col":106,"utf16_col":106}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait BoundNeed { fn val(self: i64) -> i64 } fn use_bound<T: BoundNeed>(x: T) -> i64 { x.val() } fn bad() -> i64 { use_bound<i64>(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_trait_bound_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type `i64` does not implement `BoundNeed`","code":"E1004","span":125,"line":1,"col":126,"scalar_col":126,"utf16_col":126,"end_span":128,"end_line":1,"end_col":129,"end_scalar_col":129,"end_utf16_col":129}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"use module_fixtures/g2_trait_left as left use module_fixtures/g2_trait_right as right type Box { value: i64 } impl left.Gauge for Box { fn left(self) -> i64 { self.value } } fn need<T: right.Gauge>(value: T) -> i64 { value.right() } fn main() -> i64 { need<Box>(Box { value: 1 }) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_trait_bound_preserves_qualified_identity" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":3,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type `Box` does not implement `module_fixtures/g2_trait_right.Gauge`","code":"E1004","span":257,"line":1,"col":258,"scalar_col":258,"utf16_col":258,"end_span":260,"end_line":1,"end_col":261,"end_scalar_col":261,"end_utf16_col":261}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait DupTrait { fn val(self: i64) -> i64 } type DupBox { v: i64 } impl DupTrait for DupBox { fn val(self: i64) -> i64 { 1 } } impl DupTrait for DupBox { fn val(self: i64) -> i64 { 2 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_impl_conflict_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":3,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: conflicting implementations of trait for type","span":145,"line":1,"col":146,"scalar_col":146,"utf16_col":146}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id<T>(x: T) -> T { x } fn bad() -> i64 { let y = id<i64, str>(1) 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_generic_type_arg_count_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: wrong number of type arguments","span":52,"line":1,"col":53,"scalar_col":53,"utf16_col":53}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { for x in 42 { 0 } 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_for_iter_non_list_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: for iterator requires an array, slice, or Cons/Nil list","span":22,"line":1,"col":23,"scalar_col":23,"utf16_col":23}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -[Unsafe]> i64 { __got_nope() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_got_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":3,"functions":1,"check_errors":3,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: unknown GOT symbol","span":26,"line":1,"col":27,"scalar_col":27,"utf16_col":27},{"severity":"error","message":"type error: unknown GOT symbol","span":26,"line":1,"col":27,"scalar_col":27,"utf16_col":27},{"severity":"error","message":"type error: Unsafe is sealed to trusted runtime/platform code","span":26,"line":1,"col":27,"scalar_col":27,"utf16_col":27}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type NoMeth { v: i64 } fn bad(x: NoMeth) -> i64 { x.missing() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_method_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: unknown method","span":50,"line":1,"col":51,"scalar_col":51,"utf16_col":51}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let mut x = 1 let f = () => x f() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_mut_capture_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: cannot capture mut binding","span":46,"line":1,"col":47,"scalar_col":47,"utf16_col":47}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.put() -> resume(0) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_unknown_op_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":2,"functions":1,"check_errors":2,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: missing handler clause","span":64,"line":1,"col":65,"scalar_col":65,"utf16_col":65},{"severity":"error","message":"type error: unknown effect operation","span":78,"line":1,"col":79,"scalar_col":79,"utf16_col":79}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect A { fn f() -> i64 } effect B { fn f() -> i64 } fn bad() -> i64 { handle A.f() { A.f() -> resume(1) B.f() -> resume(2) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_effect_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: handler clause effect mismatch","span":106,"line":1,"col":107,"scalar_col":107,"utf16_col":107}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect PlainDelay { fn get() -> i64 } fn main() -> i64 { handle PlainDelay.get() { PlainDelay.get() with k -> resume(42) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_non_deferred_k_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":2,"functions":1,"check_errors":2,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: handler continuation requires deferred effect operation","span":105,"line":1,"col":106,"scalar_col":106,"utf16_col":106},{"severity":"error","message":"type error: use continuation binding instead of resume","span":117,"line":1,"col":118,"scalar_col":118,"utf16_col":118}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> resume(\"nope\") } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_handler_resume_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"handler clause result type mismatch: expected `i64`, found `str`","code":"E1002","span":0,"line":1,"col":1,"scalar_col":1,"utf16_col":1,"end_span":1,"end_line":1,"end_col":2,"end_scalar_col":2,"end_utf16_col":2}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> resume(1) State.get() -> resume(2) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_duplicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: duplicate handler clause","span":103,"line":1,"col":104,"scalar_col":104,"utf16_col":104}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 fn put(v: i64) -> i64 } fn bad() -> i64 { handle { State.get() + State.put(1) } { State.get() -> resume(1) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: missing handler clause","span":102,"line":1,"col":103,"scalar_col":103,"utf16_col":103}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { resume(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_resume_outside_handler_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: resume outside handler clause","span":25,"line":1,"col":26,"scalar_col":26,"utf16_col":26}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> { let f = x => resume(x) f(1) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_resume_capture_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: cannot capture resume","span":109,"line":1,"col":110,"scalar_col":110,"utf16_col":110}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Async { @deferred fn get() -> i64 } fn apply_saved(f: (i64) -> i64) -> i64 { f(1) } fn bad() -> i64 { handle Async.get() { Async.get() with k -> { let f = x => k(x) apply_saved(f) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_continuation_escape_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: continuation cannot escape","span":184,"line":1,"col":185,"scalar_col":185,"utf16_col":185}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Async { @deferred fn get() -> i64 } fn bad() -> i64 { handle Async.get() { Async.get() with k -> { k(1) k(2) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_continuation_multiple_use_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: continuation used more than once","span":99,"line":1,"col":100,"scalar_col":100,"utf16_col":100}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(value: rc i64) -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_rc_public_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: rc is not public syntax","span":7,"line":1,"col":8,"scalar_col":8,"utf16_col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Async { @deferred fn get() -> i64 } fn bad() -> (i64) -> i64 { handle Async.get() { Async.get() with k -> x => k(x) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_continuation_closure_local_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":3,"functions":1,"check_errors":3,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: continuation-capturing closure must stay local","span":108,"line":1,"col":109,"scalar_col":109,"utf16_col":109},{"severity":"error","message":"handler clause result type mismatch: expected `i64`, found `(i64) -> i64`","code":"E1002","span":0,"line":1,"col":1,"scalar_col":1,"utf16_col":1,"end_span":1,"end_line":1,"end_col":2,"end_scalar_col":2,"end_utf16_col":2},{"severity":"error","message":"return value type mismatch: expected `(i64) -> i64`, found `i64`","code":"E1002","span":0,"line":1,"col":1,"scalar_col":1,"utf16_col":1,"end_span":1,"end_line":1,"end_col":2,"end_scalar_col":2,"end_utf16_col":2}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(n: i64) -> i64 { let x = match n { 0 -> 42 _ -> \"oops\" } 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_match_arm_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"match arm type mismatch: expected `i64`, found `str`","code":"E1002","span":55,"line":1,"col":56,"scalar_col":56,"utf16_col":56,"end_span":61,"end_line":1,"end_col":62,"end_scalar_col":62,"end_utf16_col":62}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(n: i64) -> i64 { match n { 1 -> 2 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_match_int_exhaustive_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"non-exhaustive match: value `0` is not covered","code":"E1003","span":30,"line":1,"col":31,"scalar_col":31,"utf16_col":31,"end_span":31,"end_line":1,"end_col":32,"end_scalar_col":32,"end_utf16_col":32}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Choice { Left(i64), Right(i64) } fn bad(x: Choice) -> i64 { match x { Left(v) -> v } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_match_ctor_exhaustive_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"non-exhaustive match: value `Right(0)` is not covered","code":"E1003","span":71,"line":1,"col":72,"scalar_col":72,"utf16_col":72,"end_span":72,"end_line":1,"end_col":73,"end_scalar_col":73,"end_utf16_col":73}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Box<T> { fn get() -> T } fn need() -[Box<str>]> i64 { 1 } fn bad() -[Box<i64>]> i64 { need() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_effect_discharge_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"effect `Box<str>` is not available in this context","code":"E2001","span":93,"line":1,"col":94,"scalar_col":94,"utf16_col":94,"end_span":97,"end_line":1,"end_col":98,"end_scalar_col":98,"end_utf16_col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Choice { Left(i64), Right(i64) } fn bad(x: Choice) -> i64 { match x { Left(v) -> v Left(v) -> v + 1 Right(v) -> v } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_match_duplicate_ctor_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: duplicate match constructor arm","span":88,"line":1,"col":89,"scalar_col":89,"utf16_col":89}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(s: str) -> i64 { match s { 0 -> 1 _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_literal_scrutinee_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: literal pattern does not match scrutinee","span":34,"line":1,"col":35,"scalar_col":35,"utf16_col":35}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type KnownPattern { KnownVariant(i64) } fn bad(k: KnownPattern) -> i64 { match k { MissingVariant(x) -> x _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_unknown_ctor_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: unknown constructor pattern","span":83,"line":1,"col":84,"scalar_col":84,"utf16_col":84}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type BoxPattern { BoxedPattern(i64) } fn bad(n: i64) -> i64 { match n { BoxedPattern(v) -> v _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_ctor_on_i64_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: constructor pattern does not match scrutinee","span":72,"line":1,"col":73,"scalar_col":73,"utf16_col":73}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type ShapePatternBad { BadCircle(i64) } type ColorPatternBad { BadRed(i64) } fn bad(c: ColorPatternBad) -> i64 { match c { BadCircle(r) -> r _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_wrong_ctor_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: constructor pattern does not match scrutinee","span":123,"line":1,"col":124,"scalar_col":124,"utf16_col":124}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type PayloadPattern { PayloadOne(i64) } fn bad(p: PayloadPattern) -> i64 { match p { PayloadOne -> 1 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_ctor_arity_few_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: constructor pattern arity mismatch","span":85,"line":1,"col":86,"scalar_col":86,"utf16_col":86}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type PayloadPatternMany { PayloadSingle(i64) } fn bad(p: PayloadPatternMany) -> i64 { match p { PayloadSingle(x, y) -> x + y } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_ctor_arity_many_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: constructor pattern arity mismatch","span":96,"line":1,"col":97,"scalar_col":97,"utf16_col":97}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { if 1 { 42 } else { 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_if_condition_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":21,"line":1,"col":22,"scalar_col":22,"utf16_col":22}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let mut x = 0 while 1 { x = x + 1 } x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_while_condition_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":38,"line":1,"col":39,"scalar_col":39,"utf16_col":39}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { not 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_not_operand_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":23,"line":1,"col":24,"scalar_col":24,"utf16_col":24}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { true and 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_logical_operand_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":19,"line":1,"col":20,"scalar_col":20,"utf16_col":20}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(n: i64) -> i64 { match n { x if x -> x _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_match_guard_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":39,"line":1,"col":40,"scalar_col":40,"utf16_col":40}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { 1 == \"one\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_equality_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: equality operand mismatch","span":19,"line":1,"col":20,"scalar_col":20,"utf16_col":20}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { \"a\" < \"b\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_comparison_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type `str` does not implement `Ord`","code":"E1004","span":19,"line":1,"col":20,"scalar_col":20,"utf16_col":20,"end_span":22,"end_line":1,"end_col":23,"end_scalar_col":23,"end_utf16_col":23}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { true band 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_bitwise_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: bitwise operand is not i64","span":18,"line":1,"col":19,"scalar_col":19,"utf16_col":19}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { 1 bshl false }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_shift_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: bitwise operand is not i64","span":18,"line":1,"col":19,"scalar_col":19,"utf16_col":19}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { \"a\" + 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_arithmetic_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: arithmetic operand is not i64","span":18,"line":1,"col":19,"scalar_col":19,"utf16_col":19}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { missing = 1 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_assignment_unknown_target_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"unknown identifier '\''missing'\''","code":"E1001","span":18,"line":1,"col":19,"scalar_col":19,"utf16_col":19,"end_span":25,"end_line":1,"end_col":26,"end_scalar_col":26,"end_utf16_col":26}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let x = 0 x = 1 x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_assignment_immutable_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type error: cannot assign to immutable binding","span":28,"line":1,"col":29,"scalar_col":29,"utf16_col":29}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let mut x = 0 x = \"oops\" x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_assignment_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"assignment type mismatch: expected `i64`, found `str`","code":"E1002","span":36,"line":1,"col":37,"scalar_col":37,"utf16_col":37,"end_span":42,"end_line":1,"end_col":43,"end_scalar_col":43,"end_utf16_col":43}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let x: i64 = \"oops\" x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_let_annotation_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"type annotation type mismatch: expected `i64`, found `str`","code":"E1002","span":31,"line":1,"col":32,"scalar_col":32,"utf16_col":32,"end_span":37,"end_line":1,"end_col":38,"end_scalar_col":38,"end_utf16_col":38}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { return \"oops\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_explicit_return_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"return value type mismatch: expected `i64`, found `str`","code":"E1002","span":25,"line":1,"col":26,"scalar_col":26,"utf16_col":26,"end_span":31,"end_line":1,"end_col":32,"end_scalar_col":32,"end_utf16_col":32}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { \"oops\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals_without_diagnostic_payload "mcp_diagnostics_body_return_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"schema_version":1,"stability":"stable","phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"position_units":{"span":"utf-8-byte-offset","line_base":1,"col":"utf-8-byte-column","scalar_col":"unicode-scalar-column","utf16_col":"utf-16-code-unit-column"},"items":[{"severity":"error","message":"return value type mismatch: expected `i64`, found `str`","code":"E1002","span":18,"line":1,"col":19,"scalar_col":19,"utf16_col":19,"end_span":24,"end_line":1,"end_col":25,"end_scalar_col":25,"end_utf16_col":25}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"fn main() -> str { \"Ω\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_unicode_source_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":9}}'

mcp_out=$(printf '%s' 'not-json' | "$WEFT" mcp 2>&1)
assert_equals "mcp_invalid_json_rpc_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"invalid json-rpc"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/list"' | "$WEFT" mcp 2>&1)
assert_equals "mcp_malformed_object_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"invalid json-rpc"}}'

mcp_out=$(printf '%s' '{"id":1,"method":"tools/list"}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_missing_jsonrpc_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"invalid request"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_missing_method_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32600,"message":"invalid request"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"unknown","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_unknown_tool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"unknown tool"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"arguments":{"name":"parse_summary","source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_nested_tool_name_ignored_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing tool name"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_missing_source_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing source"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_missing_source_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing source"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_lookup_missing_name_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing lookup name"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"fn broken -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_parse_summary_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { missing }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_check_summary_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"check_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":2}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"fn main() -> i64 { missing }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_ir_summary_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"ir_summary","ok":true,"schema_version":1,"stability":"internal","functions":0,"blocks":0,"insts":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn main() -> i64 { missing }","name":"main"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"schema_version":1,"stability":"stable","name":"main","found":true,"fact":{"kind":"function","name":"main","parameters":[],"return_type":{"kind":"primitive","name":"i64"},"effects":{"kind":"closed","atoms":[]},"purity":"pure","ownership":{"kind":"borrowed_parameters","indices":[]},"return_shape":{"kind":"words","count":1,"lanes":["gpr"]},"bounds":{"kind":"type_parameters","parameters":[]}}}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"effect Log { fn hit() -> i64 } fn main() -> i64 { missing }","name":"Log"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"schema_version":1,"stability":"stable","name":"Log","found":true,"fact":{"kind":"effect_declaration","name":"Log","type_parameters":[],"operations":[{"name":"hit","parameters":[],"return_type":{"kind":"primitive","name":"i64"},"deferred":false}]}}}'

# opt_counters: full optimise + native-lower pipeline counter report
mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{"source":"fn add(a: i64, b: i64) -> i64 { a + b }\nfn main() -> i64 { add(1, 2) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_opt_counters_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"opt_counters","ok":true,"schema_version":1,"stability":"internal","handler_inline_sites":0,"handler_residual_sites":0,"handler_evidence_candidate_sites":0,"const_fold_sites":1,"algebraic_fold_sites":0,"dead_inst_sites":2,"pure_call_dce_sites":0,"match_final_arm_elision_sites":0,"block_entry_narrowing_sites":0,"direct_call_inline_sites":1,"functions":2,"insts":4,"sp_load":0,"sp_store":0,"sp_pair_load":1,"sp_pair_store":1,"sp_fp_pair_load":0,"sp_fp_pair_store":0,"rc_elision":0,"rc_borrowable_param_facts":0,"managed_drop_specializations":0,"managed_reuse_candidates":0,"managed_reuse_lowerings":0,"static_pair_slots":0,"static_pair_sites":0,"alloc_elisions":0,"fusions":0,"indexed_bounds_elisions":0,"indexed_full_bounds_elisions":0,"vector_bounds_elisions":0,"vector_full_bounds_elisions":0,"vector_scaled_addrs":0,"vector_push_no_grows":0,"param_residents":0,"volatile_residents":0,"call_window_residents":0,"low_pool_residents":0,"dead_store_elisions":0,"remat_small_const_defs":0,"remat_small_const_uses":0,"remat_large_const_defs":0,"remat_large_const_uses":0,"remat_movn_const_defs":0,"remat_movn_const_uses":0,"leaf_fns":2,"leaf_fn_pairs":4,"leaf_small_fns":2,"leaf_small_fn_pairs":4,"crossblock_barrier_free_defs":0,"crossblock_barrier_free_uses":0,"residual_slotlike":0,"residual_machinery_reads":0,"residual_call_use":0,"residual_pool_full":0,"residual_cs_exhausted":0,"residual_use_sum":0,"split_candidate_defs":0,"split_segment_uses":0,"split_residents":0,"fwd_only_defs":0,"fp_residents":0,"register_pinned":0,"pinned_slots":0,"loop_pinned_slots":0,"cs_residents":0,"bank_swaps":0,"typed_lowering_failures":0,"residency_audit_violations":0,"alloc_ck_violations":0,"alloc_ck_checked":4,"live_functions_measured":2,"max_pressure":2,"pressure_fns_le8":2,"pressure_fns_9_13":0,"pressure_fns_14_21":0,"pressure_fns_22_27":0,"pressure_fns_28_up":0,"call_sites_measured":0,"max_live_across_call":0,"lac_sites_0":0,"lac_sites_1_4":0,"lac_sites_5_8":0,"lac_sites_9_up":0,"spill_defs_loads_0":0,"spill_defs_loads_1":0,"spill_defs_loads_2_3":0,"spill_defs_loads_4_up":0,"shape_l0_param":0,"shape_l1_param":0,"shape_d2_param":0,"shape_ls_param":0,"shape_l0_call":0,"shape_l1_call":0,"shape_d2_call":0,"shape_ls_call":0,"shape_l0_const_small":0,"shape_l1_const_small":0,"shape_d2_const_small":0,"shape_ls_const_small":0,"shape_l0_const_large":0,"shape_l1_const_large":0,"shape_d2_const_large":0,"shape_ls_const_large":0,"shape_l0_field_load":0,"shape_l1_field_load":0,"shape_d2_field_load":0,"shape_ls_field_load":0,"shape_l0_variant":0,"shape_l1_variant":0,"shape_d2_variant":0,"shape_ls_variant":0,"shape_l0_slot_load":0,"shape_l1_slot_load":0,"shape_d2_slot_load":0,"shape_ls_slot_load":0,"shape_l0_arith":0,"shape_l1_arith":0,"shape_d2_arith":0,"shape_ls_arith":0,"shape_l0_ctor":0,"shape_l1_ctor":0,"shape_d2_ctor":0,"shape_ls_ctor":0,"shape_l0_addr_frame":0,"shape_l1_addr_frame":0,"shape_d2_addr_frame":0,"shape_ls_addr_frame":0,"shape_l0_effect_op":0,"shape_l1_effect_op":0,"shape_d2_effect_op":0,"shape_ls_effect_op":0,"shape_l0_fp":0,"shape_l1_fp":0,"shape_d2_fp":0,"shape_ls_fp":0,"shape_l0_addr_far":0,"shape_l1_addr_far":0,"shape_d2_addr_far":0,"shape_ls_addr_far":0,"shape_l0_variant_dead":0,"shape_l1_variant_dead":0,"shape_d2_variant_dead":0,"shape_ls_variant_dead":0,"shape_l0_param_dead":0,"shape_l1_param_dead":0,"shape_d2_param_dead":0,"shape_ls_param_dead":0,"shape_l0_unscanned":0,"shape_l1_unscanned":0,"shape_d2_unscanned":0,"shape_ls_unscanned":0,"split2_upper_saved":0,"split2_defs":0,"split2_loads":0,"pair_census_saved":0,"pair_census_tail_dead":0,"pair_census_interior_dead":0,"pair_census_half_dead":0,"pair_census_written_unsaved":0,"pair_census_unknown_fns":0,"pair_census_first_fn_hash":0,"pair_census_first_reg":0,"pair_census_first_delta":0,"pair_census_first_word":0,"soft_barrier_events":0,"true_barrier_events":0,"soft_barrier_only_fns":0,"naked_leaf_fns":2,"naked_leaf_shed_pairs":6,"naked_leaf_blocked_by_params":0,"naked_leaf_blocked_by_cleanup":0,"naked2_fns":0,"naked2_pairs":0,"naked2_spilled_defs":0,"fn_param_pool_residents":0,"fn_param_call_residents":0,"crossblock_pool_residents":0,"crossblock_pool_call_residents":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{"source":"fn f(xs: [i64], i: usize) -> i64 { if i < xs.len { xs[i] } else { 0 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_opt_counters_indexed_bounds_total" "$mcp_out" '"indexed_bounds_elisions":1'
assert_contains "mcp_opt_counters_indexed_bounds_full" "$mcp_out" '"indexed_full_bounds_elisions":1'
assert_contains "mcp_opt_counters_indexed_bounds_not_vector" "$mcp_out" '"vector_bounds_elisions":0'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{"source":"fn main() -> i64 { nope() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_opt_counters_check_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"opt_counters","ok":false,"reason":"check errors"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_opt_counters_missing_source_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing source"}}'

# JSON \uXXXX escapes are mandatory spec syntax: BMP escape decodes into
# source bytes, surrogate pairs decode to 4-byte UTF-8, invalid hex rejects.
mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"\u0066n main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_json_unicode_escape_bmp_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"check_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"-- \ud83d\ude00\nfn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_json_unicode_escape_surrogate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"schema_version":1,"stability":"internal","functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { \uZZZZ }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_json_unicode_escape_invalid_hex_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"invalid json-rpc"}}'

# MCP serve mode: persistent newline-delimited JSON-RPC. One process
# handles the whole session: initialize handshake (protocol version
# echoed), the initialized notification is not answered, tools/list
# carries input schemas, tools/call echoes the request id (string ids
# included) and wraps the payload as MCP text content.
mcp_session_fact_source='trait Mark { fn mark(self) -> i64 } impl Mark for i64 { fn mark(self: i64) -> i64 { self } } effect Log { fn hit() -> i64 } fn inspect(value: i64) -> i64 { value }'
mcp_session_fact_prefix='trait Mark { fn mark(self) -> i64 } impl Mark for i64 { fn mark(self: i64) -> i64 { self } } effect Log { fn hit() -> i64 } fn inspect(value: i64) -> i64 { '
mcp_session_fact_json=$(json_escape_bytes "$mcp_session_fact_source")
mcp_session_fact_offset=${#mcp_session_fact_prefix}
mcp_serve_out=$(
  { printf '%s\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"call-2","method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"cache-2","method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"edit-3","method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"fn main() -> str { \"changed\" }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"check-1","method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"check-cache","method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"check-edit","method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> str { \"changed\" }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"ir-test-1","method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"test \"ok\" { Test.assert_eq(1, 1) }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"ir-test-cache","method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"test \"ok\" { Test.assert_eq(1, 1) }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"diagnostics-1","method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { missing }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"diagnostics-cache","method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { missing }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"diagnostics-edit","method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { 42 }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"diagnostics-test","method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"test \"bad\" { Test.assert_true(2) }"}}}'
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":\"fact-type\",\"method\":\"tools/call\",\"params\":{\"name\":\"type_lookup\",\"arguments\":{\"source\":\"$mcp_session_fact_json\",\"name\":\"inspect\"}}}"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":\"fact-effect\",\"method\":\"tools/call\",\"params\":{\"name\":\"effect_lookup\",\"arguments\":{\"source\":\"$mcp_session_fact_json\",\"name\":\"Log\"}}}"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":\"fact-position\",\"method\":\"tools/call\",\"params\":{\"name\":\"fact_at_position\",\"arguments\":{\"source\":\"$mcp_session_fact_json\",\"offset\":$mcp_session_fact_offset}}}"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":\"fact-bindings\",\"method\":\"tools/call\",\"params\":{\"name\":\"visible_bindings\",\"arguments\":{\"source\":\"$mcp_session_fact_json\",\"offset\":$mcp_session_fact_offset}}}"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":\"fact-conformance\",\"method\":\"tools/call\",\"params\":{\"name\":\"conformance_at_position\",\"arguments\":{\"source\":\"$mcp_session_fact_json\",\"offset\":$mcp_session_fact_offset,\"trait\":\"Mark\"}}}"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":\"fact-type-cache\",\"method\":\"tools/call\",\"params\":{\"name\":\"type_lookup\",\"arguments\":{\"source\":\"$mcp_session_fact_json\",\"name\":\"inspect\"}}}"
    printf '%s\n' '{"jsonrpc":"2.0","id":"fact-edit","method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn changed() -> str { \"edited\" }","name":"inspect"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"ping"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"bogus/method"}'
  } | "$WEFT" mcp serve 2>&1)
assert_contains "mcp_serve_initialize_echoes_protocol" "$mcp_serve_out" '"protocolVersion":"2025-06-18"'
assert_contains "mcp_serve_initialize_serverinfo" "$mcp_serve_out" '"serverInfo":{"name":"weft"'
assert_contains "mcp_serve_tools_list_has_schema" "$mcp_serve_out" '"inputSchema":{"type":"object"'
assert_contains "mcp_serve_tools_list_marks_stable_diagnostics" "$mcp_serve_out" '"name":"diagnostics","x-weft-stability":"stable"'
assert_contains "mcp_serve_tools_list_marks_stable_lookup" "$mcp_serve_out" '"name":"type_lookup","x-weft-stability":"stable"'
assert_contains "mcp_serve_type_lookup_describes_return_provenance" "$mcp_serve_out" 'including optimizer-produced return provenance'
assert_contains "mcp_serve_tools_list_marks_stable_position_facts" "$mcp_serve_out" '"name":"fact_at_position","x-weft-stability":"stable"'
assert_contains "mcp_serve_tools_list_marks_stable_formatter" "$mcp_serve_out" '"name":"format_source","x-weft-stability":"stable"'
assert_contains "mcp_serve_tools_list_marks_internal_ir" "$mcp_serve_out" '"name":"ir_summary","x-weft-stability":"internal"'
assert_contains "mcp_serve_call_wraps_content_and_echoes_id" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"call-2","result":{"content":[{"type":"text","text":"{\"tool\":\"parse_summary\",\"ok\":true'
assert_contains "mcp_serve_reuses_identical_parse_request" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"cache-2","result":{"content":[{"type":"text","text":"{\"tool\":\"parse_summary\",\"ok\":true,\"schema_version\":1,\"stability\":\"internal\",\"functions\":1,\"first_body_tag\":1}'
assert_contains "mcp_serve_invalidates_edited_parse_request" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"edit-3","result":{"content":[{"type":"text","text":"{\"tool\":\"parse_summary\",\"ok\":true,\"schema_version\":1,\"stability\":\"internal\",\"functions\":1,\"first_body_tag\":9}'
assert_contains "mcp_serve_checks_source_through_session" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"check-1","result":{"content":[{"type":"text","text":"{\"tool\":\"check_summary\",\"ok\":true,\"schema_version\":1,\"stability\":\"internal\",\"functions\":1,\"first_body_tag\":1}'
assert_contains "mcp_serve_reuses_identical_check_request" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"check-cache","result":{"content":[{"type":"text","text":"{\"tool\":\"check_summary\",\"ok\":true,\"schema_version\":1,\"stability\":\"internal\",\"functions\":1,\"first_body_tag\":1}'
assert_contains "mcp_serve_invalidates_edited_check_request" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"check-edit","result":{"content":[{"type":"text","text":"{\"tool\":\"check_summary\",\"ok\":true,\"schema_version\":1,\"stability\":\"internal\",\"functions\":1,\"first_body_tag\":9}'
assert_contains "mcp_serve_ir_uses_prepared_test_check" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"ir-test-1","result":{"content":[{"type":"text","text":"{\"tool\":\"ir_summary\",\"ok\":true,\"schema_version\":1,\"stability\":\"internal\",\"functions\":1,\"blocks\":1,\"insts\":3}'
assert_contains "mcp_serve_ir_reuses_prepared_test_check" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"ir-test-cache","result":{"content":[{"type":"text","text":"{\"tool\":\"ir_summary\",\"ok\":true,\"schema_version\":1,\"stability\":\"internal\",\"functions\":1,\"blocks\":1,\"insts\":3}'
assert_contains "mcp_serve_diagnostics_use_cached_check" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"diagnostics-1","result":{"content":[{"type":"text","text":"{\"tool\":\"diagnostics\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"phase\":\"parse+check\",\"diagnostics\":1'
assert_contains "mcp_serve_reuses_identical_diagnostics" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"diagnostics-cache","result":{"content":[{"type":"text","text":"{\"tool\":\"diagnostics\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"phase\":\"parse+check\",\"diagnostics\":1'
assert_contains "mcp_serve_invalidates_edited_diagnostics" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"diagnostics-edit","result":{"content":[{"type":"text","text":"{\"tool\":\"diagnostics\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"phase\":\"parse+check\",\"diagnostics\":0,\"functions\":1,\"check_errors\":0'
assert_contains "mcp_serve_test_diagnostics_use_prepared_check" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"diagnostics-test","result":{"content":[{"type":"text","text":"{\"tool\":\"diagnostics\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"phase\":\"parse+check\",\"diagnostics\":1,\"functions\":1,\"check_errors\":1'
assert_contains "mcp_serve_type_fact_uses_shared_check" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"fact-type","result":{"content":[{"type":"text","text":"{\"tool\":\"type_lookup\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"name\":\"inspect\",\"found\":true'
assert_contains "mcp_serve_effect_fact_reuses_shared_check" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"fact-effect","result":{"content":[{"type":"text","text":"{\"tool\":\"effect_lookup\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"name\":\"Log\",\"found\":true'
assert_contains "mcp_serve_position_fact_reuses_shared_check" "$mcp_serve_out" '"id":"fact-position","result":{"content":[{"type":"text","text":"{\"tool\":\"fact_at_position\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"offset\":'"$mcp_session_fact_offset"',\"found\":true,\"fact\":{\"kind\":\"symbol\",\"name\":\"value\"'
mcp_session_bindings_response=$(printf '%s\n' "$mcp_serve_out" | grep -F '"id":"fact-bindings"')
assert_contains "mcp_serve_bindings_reuse_shared_check" "$mcp_session_bindings_response" '{\"name\":\"value\",\"symbol_kind\":\"parameter\",\"type\":{\"kind\":\"primitive\",\"name\":\"i64\"}}'
assert_contains "mcp_serve_conformance_reuses_shared_check" "$mcp_serve_out" '"id":"fact-conformance","result":{"content":[{"type":"text","text":"{\"tool\":\"conformance_at_position\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"offset\":'"$mcp_session_fact_offset"',\"found\":true,\"fact\":{\"kind\":\"conformance\",\"type\":{\"kind\":\"primitive\",\"name\":\"i64\"},\"trait\":\"Mark\",\"decision\":\"yes\"'
assert_contains "mcp_serve_reuses_check_after_cross_tool_facts" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"fact-type-cache","result":{"content":[{"type":"text","text":"{\"tool\":\"type_lookup\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"name\":\"inspect\",\"found\":true'
assert_contains "mcp_serve_fact_edit_invalidates_shared_check" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"fact-edit","result":{"content":[{"type":"text","text":"{\"tool\":\"type_lookup\",\"ok\":true,\"schema_version\":1,\"stability\":\"stable\",\"name\":\"inspect\",\"found\":false}'
assert_contains "mcp_serve_ping" "$mcp_serve_out" '{"jsonrpc":"2.0","id":3,"result":{}}'
assert_contains "mcp_serve_unknown_method_error" "$mcp_serve_out" '{"jsonrpc":"2.0","id":4,"error":{"code":-32601,"message":"method not found"}}'
assert_equals "mcp_serve_notification_not_answered" "$(printf '%s\n' "$mcp_serve_out" | grep -c jsonrpc)" "23"

lsp_stream_fifo="$tmp_lsp_stream_dir/stdin"
lsp_stream_out="$tmp_lsp_stream_dir/stdout"
mkfifo "$lsp_stream_fifo"
"$WEFT" lsp < "$lsp_stream_fifo" > "$lsp_stream_out" 2>&1 &
lsp_stream_pid=$!
exec 9> "$lsp_stream_fifo"
lsp_stream_init='{"jsonrpc":"2.0","id":90,"method":"initialize","params":{}}'
lsp_frame "$lsp_stream_init" >&9
lsp_stream_ready=0
for ((i = 0; i < 50; i++)); do
  if grep -q '"id":90,"result"' "$lsp_stream_out" 2>/dev/null; then
    lsp_stream_ready=1
    break
  fi
  sleep 0.1
done
if [ "$lsp_stream_ready" -eq 1 ]; then
  echo "  ok lsp_streams_response_before_stdin_eof"
else
  echo "  fail lsp_streams_response_before_stdin_eof"
  exec 9>&-
  kill "$lsp_stream_pid" 2>/dev/null || true
  wait "$lsp_stream_pid" 2>/dev/null || true
  exit 1
fi
lsp_frame '{"jsonrpc":"2.0","method":"initialized","params":{}}' >&9
lsp_frame '{"jsonrpc":"2.0","id":91,"method":"shutdown","params":null}' >&9
lsp_frame '{"jsonrpc":"2.0","method":"exit","params":null}' >&9
exec 9>&-
wait "$lsp_stream_pid"
assert_contains "lsp_streaming_shutdown_response" "$(<"$lsp_stream_out")" '"id":91,"result":null'

lsp_init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
lsp_out=$(lsp_frame "$lsp_init" | "$WEFT" lsp 2>&1)
assert_contains "lsp_initialize_framed_header" "$lsp_out" "Content-Length:"
assert_contains "lsp_initialize_capabilities" "$lsp_out" '"hoverProvider":true'
assert_contains "lsp_initialize_advertises_open_close" "$lsp_out" '"textDocumentSync":{"openClose":true,"change":1}'
assert_contains "lsp_initialize_definition_capability" "$lsp_out" '"definitionProvider":true'
assert_contains "lsp_initialize_completion_hook" "$lsp_out" '"completionProvider"'
assert_contains "lsp_initialize_code_action_hook" "$lsp_out" '"codeActionProvider":true'
assert_contains "lsp_initialize_formatting_hook" "$lsp_out" '"documentFormattingProvider":true'
assert_contains "lsp_initialize_defaults_to_utf16_positions" "$lsp_out" '"positionEncoding":"utf-16"'

lsp_init_utf8='{"jsonrpc":"2.0","id":12,"method":"initialize","params":{"capabilities":{"general":{"positionEncodings":["utf-16","utf-8"]}}}}'
lsp_out=$(lsp_frame "$lsp_init_utf8" | "$WEFT" lsp 2>&1)
assert_contains "lsp_initialize_prefers_offered_utf8" "$lsp_out" '"positionEncoding":"utf-8"'

lsp_init_utf32='{"jsonrpc":"2.0","id":13,"method":"initialize","params":{"capabilities":{"general":{"positionEncodings":["utf-32"]}}}}'
lsp_out=$(lsp_frame "$lsp_init_utf32" | "$WEFT" lsp 2>&1)
assert_contains "lsp_initialize_accepts_explicit_utf32" "$lsp_out" '"positionEncoding":"utf-32"'

lsp_format_open="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///format.weft\",\"version\":1,\"text\":\"$format_transport_source_json\"}}}"
lsp_format_request='{"jsonrpc":"2.0","id":9,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file:///format.weft"},"options":{"tabSize":2,"insertSpaces":true}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_format_open")" "$(lsp_frame "$lsp_format_request")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_formatting_matches_cli_bytes" "$lsp_out" "\"newText\":\"$format_cli_json\""
assert_contains "lsp_formatting_replaces_whole_document" "$lsp_out" '"range":{"start":{"line":0,"character":0},"end":{"line":1'

lsp_bad_format_open='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///bad-format.weft","version":1,"text":"fn broken -> i64 { 0 }"}}}'
lsp_bad_format_request='{"jsonrpc":"2.0","id":10,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file:///bad-format.weft"},"options":{"tabSize":2,"insertSpaces":true}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_bad_format_open")" "$(lsp_frame "$lsp_bad_format_request")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_formatting_failure_uses_request_failed" "$lsp_out" '"id":10,"error":{"code":-32803,"message":"formatting failed"'
assert_contains "lsp_formatting_failure_returns_structured_diagnostics" "$lsp_out" '"data":{"error_count":1,"diagnostics":[{"range":{"start":{"line":0,"character":10}'
assert_contains "lsp_formatting_failure_preserves_message" "$lsp_out" "expected '(' after function name"

lsp_missing_format='{"jsonrpc":"2.0","id":11,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file:///missing-format.weft"},"options":{"tabSize":2,"insertSpaces":true}}}'
lsp_out=$(lsp_frame "$lsp_missing_format" | "$WEFT" lsp 2>&1)
assert_contains "lsp_formatting_unknown_document_is_empty" "$lsp_out" '"id":11,"result":[]'

lsp_open_clean='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///clean.weft","version":1,"text":"fn main() -> i64 { 0 }"}}}'
lsp_out=$(lsp_frame "$lsp_open_clean" | "$WEFT" lsp 2>&1)
assert_contains "lsp_open_clean_publish_diagnostics" "$lsp_out" '"method":"textDocument/publishDiagnostics"'
assert_contains "lsp_open_clean_empty_diagnostics" "$lsp_out" '"diagnostics":[]'

lsp_open_parse='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///parse.weft","version":1,"text":"fn broken -> i64 { 0 }"}}}'
lsp_out=$(lsp_frame "$lsp_open_parse" | "$WEFT" lsp 2>&1)
assert_contains "lsp_open_parse_error_diagnostic" "$lsp_out" "expected"
assert_contains "lsp_open_parse_error_range" "$lsp_out" '"range":{"start":{"line":0,"character":10}'

lsp_open_missing_closer='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///missing-closer.weft","version":1,"text":"fn broken() -> i64 { 1"}}}'
lsp_out=$(lsp_frame "$lsp_open_missing_closer" | "$WEFT" lsp 2>&1)
assert_contains "lsp_diagnostic_wire_carries_parser_class" "$lsp_out" '"data":{"schema_version":1,"severity":"error","class":"parse","code":"E0002"'
assert_contains "lsp_diagnostic_wire_carries_machine_applicability" "$lsp_out" '"applicability":"machine-applicable"'
assert_contains "lsp_diagnostic_wire_preserves_zero_width_edit" "$lsp_out" '"span":22,"end_span":22'
assert_contains "lsp_diagnostic_wire_carries_insertion_text" "$lsp_out" '"replacement":"}"'
assert_contains "lsp_diagnostic_related_information_names_opener" "$lsp_out" '"relatedInformation":[{"location":{"uri":"file:///missing-closer.weft","range":{"start":{"line":0,"character":19},"end":{"line":0,"character":20}}},"message":"construct opened here"}]'

lsp_open_type='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///type.weft","version":1,"text":"fn main() -> i64 { missing }"}}}'
lsp_out=$(lsp_frame "$lsp_open_type" | "$WEFT" lsp 2>&1)
assert_contains "lsp_open_type_error_diagnostic" "$lsp_out" "unknown identifier 'missing'"
assert_contains "lsp_open_type_error_stable_code" "$lsp_out" '"code":"E1001"'
assert_contains "lsp_open_type_error_range" "$lsp_out" '"character":19'

lsp_open_suggestion='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///suggestion.weft","version":1,"text":"fn main() -> i64 { let counter = 1 counte }"}}}'
lsp_out=$(lsp_frame "$lsp_open_suggestion" | "$WEFT" lsp 2>&1)
assert_contains "lsp_diagnostic_wire_names_file_source" "$lsp_out" '"primary":{"source":{"kind":"file","path":"/suggestion.weft"}'
assert_contains "lsp_diagnostic_wire_carries_related_information" "$lsp_out" '"relatedInformation":[{"location":{"uri":"file:///suggestion.weft","range":{"start":{"line":0,"character":23},"end":{"line":0,"character":30}}},"message":"similarly named declaration"}]'
assert_contains "lsp_diagnostic_wire_matches_mcp_suggestion" "$lsp_out" "$wire_unknown_suggestion"
assert_contains "lsp_diagnostic_wire_carries_typed_edit" "$lsp_out" '"replacement":"counter"'

lsp_open_type_mismatch='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///type-mismatch.weft","version":1,"text":"fn takes(value: i64) -> i64 { value } fn main() -> i64 { takes(\"snow\") }"}}}'
lsp_out=$(lsp_frame "$lsp_open_type_mismatch" | "$WEFT" lsp 2>&1)
assert_contains "lsp_type_mismatch_stable_code" "$lsp_out" '"code":"E1002"'
assert_contains "lsp_type_mismatch_message" "$lsp_out" 'argument type mismatch: expected `i64`, found `str`'
assert_contains "lsp_type_mismatch_precise_range" "$lsp_out" '"start":{"line":0,"character":63},"end":{"line":0,"character":69}'
assert_contains "lsp_type_mismatch_related_information" "$lsp_out" '"relatedInformation":[{"location":{"uri":"file:///type-mismatch.weft","range":{"start":{"line":0,"character":9},"end":{"line":0,"character":14}}},"message":"expected type established here"}]'
assert_contains "lsp_diagnostic_wire_matches_mcp_expected_type" "$lsp_out" "$wire_type_expected"
assert_contains "lsp_diagnostic_wire_matches_mcp_found_type" "$lsp_out" "$wire_type_found"

lsp_open_non_exhaustive='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///non-exhaustive.weft","version":1,"text":"type Choice { Left(i64), Right(i64) } fn bad(value: Choice) -> i64 { match value { Left(n) -> n } }"}}}'
lsp_out=$(lsp_frame "$lsp_open_non_exhaustive" | "$WEFT" lsp 2>&1)
assert_contains "lsp_non_exhaustive_stable_code" "$lsp_out" '"code":"E1003"'
assert_contains "lsp_non_exhaustive_teaches_witness" "$lsp_out" 'non-exhaustive match: value `Right(0)` is not covered'
assert_contains "lsp_non_exhaustive_precise_scrutinee_range" "$lsp_out" '"start":{"line":0,"character":75},"end":{"line":0,"character":80}'

lsp_open_effect_discharge='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///effect-discharge.weft","version":1,"text":"effect Box<T> { fn get() -> T } fn need() -[Box<str>]> i64 { 1 } fn bad() -[Box<i64>]> i64 { need() }"}}}'
lsp_out=$(lsp_frame "$lsp_open_effect_discharge" | "$WEFT" lsp 2>&1)
assert_contains "lsp_effect_discharge_stable_code" "$lsp_out" '"code":"E2001"'
assert_contains "lsp_effect_discharge_exact_atom" "$lsp_out" 'effect `Box<str>` is not available in this context'
assert_contains "lsp_effect_discharge_precise_callee_range" "$lsp_out" '"start":{"line":0,"character":93},"end":{"line":0,"character":97}'
assert_contains "lsp_diagnostic_wire_matches_mcp_effect_atom" "$lsp_out" "$wire_effect_atom"
assert_contains "lsp_diagnostic_wire_matches_mcp_effect_set" "$lsp_out" "$wire_effect_set"

lsp_open_trait_conformance='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///trait-conformance.weft","version":1,"text":"trait BoundNeed { fn val(self: i64) -> i64 } fn use_bound<T: BoundNeed>(x: T) -> i64 { x.val() } fn bad() -> i64 { use_bound<i64>(1) }"}}}'
lsp_out=$(lsp_frame "$lsp_open_trait_conformance" | "$WEFT" lsp 2>&1)
assert_contains "lsp_trait_conformance_stable_code" "$lsp_out" '"code":"E1004"'
assert_contains "lsp_trait_conformance_exact_identity" "$lsp_out" 'type `i64` does not implement `BoundNeed`'
assert_contains "lsp_trait_conformance_precise_type_argument_range" "$lsp_out" '"start":{"line":0,"character":125},"end":{"line":0,"character":128}'
assert_contains "lsp_diagnostic_wire_carries_bool_field" "$lsp_out" '{"kind":"bool","name":"impl_allowed_here","value":true}'

lsp_open_module_cycle='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///module-cycle.weft","version":1,"text":"use test/negative/import_cycle_direct fn main() -> i64 { 0 }"}}}'
lsp_out=$(lsp_frame "$lsp_open_module_cycle" | "$WEFT" lsp 2>&1)
assert_contains "lsp_module_cycle_stable_code" "$lsp_out" '"code":"E4001"'
assert_contains "lsp_module_cycle_message" "$lsp_out" 'circular import: test/negative/import_cycle_direct -> test/negative/import_cycle_direct'

lsp_open_module_member='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///module-member.weft","version":1,"text":"use module_fixtures/g2_function_left as left fn main() -> i64 { left.missing() }"}}}'
lsp_out=$(lsp_frame "$lsp_open_module_member" | "$WEFT" lsp 2>&1)
assert_contains "lsp_module_member_stable_code" "$lsp_out" '"code":"E4002"'
assert_contains "lsp_module_member_qualified_name" "$lsp_out" "unknown module member 'left.missing'"

lsp_open_module_scope='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///module-scope.weft","version":1,"text":"use module_fixtures/g2_function_left.{missing} fn main() -> i64 { 0 }"}}}'
lsp_out=$(lsp_frame "$lsp_open_module_scope" | "$WEFT" lsp 2>&1)
assert_contains "lsp_module_scope_audit_stable_code" "$lsp_out" '"code":"E4002"'
assert_contains "lsp_module_scope_audit_message" "$lsp_out" "unknown module member 'missing' in import"

lsp_open_raw='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///raw.weft","version":1,"text":"fn main() -[Unsafe]> i64 { __mem_load64(0) }"}}}'
lsp_out=$(lsp_frame "$lsp_open_raw" | "$WEFT" lsp 2>&1)
assert_contains "lsp_open_rejects_root_raw_memory" "$lsp_out" "type error: Unsafe is sealed to trusted runtime/platform code"

lsp_open_unicode='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///unicode.weft","version":1,"text":"fn main() -> i64 { let s = \"Ω\" missing }"}}}'
lsp_out=$(lsp_frame "$lsp_open_unicode" | "$WEFT" lsp 2>&1)
assert_contains "lsp_unicode_source_diagnostic" "$lsp_out" "unknown identifier 'missing'"
assert_contains "lsp_unicode_source_range_uses_default_utf16" "$lsp_out" '"range":{"start":{"line":0,"character":31},"end":{"line":0,"character":38}'

lsp_non_nfc_open='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///non-nfc.weft","version":1,"text":"fn main() -> i64 { let café = 1 café }"}}}'
lsp_out=$(lsp_frame "$lsp_non_nfc_open" | "$WEFT" lsp 2>&1)
assert_contains "lsp_non_nfc_identifier_diagnostic" "$lsp_out" '"message":"identifier must use NFC normalization"'
assert_contains "lsp_non_nfc_identifier_range_is_complete" "$lsp_out" '"range":{"start":{"line":0,"character":23},"end":{"line":0,"character":28}'

lsp_unicode_identifier_open='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///unicode-identifiers.weft","version":1,"text":"fn πρόσθεση(α: i64, β: i64) -> i64 { α + β } fn main() -> i64 { πρόσθεση(40, 2) }"}}}'
lsp_out=$(lsp_frame "$lsp_unicode_identifier_open" | "$WEFT" lsp 2>&1)
assert_contains "lsp_accepts_unicode_identifier_identity" "$lsp_out" '"diagnostics":[]'

lsp_unicode_security_open='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///unicode-security.weft","version":1,"text":"fn paypal() -> i64 { 20 } fn pаypаl() -> i64 { 22 }"}}}'
lsp_out=$(lsp_frame "$lsp_unicode_security_open" | "$WEFT" lsp 2>&1)
assert_contains "lsp_unicode_security_warning_severity" "$lsp_out" '"severity":2'
assert_contains "lsp_unicode_security_warning_mixed_script_code" "$lsp_out" '"code":"W0001"'
assert_contains "lsp_unicode_security_warning_confusable_code" "$lsp_out" '"code":"W0002"'

lsp_bidi_source_open='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///bidi-source.weft","version":1,"text":"fn main() -> str { \"abc\u202Edef\" }"}}}'
lsp_out=$(lsp_frame "$lsp_bidi_source_open" | "$WEFT" lsp 2>&1)
assert_contains "lsp_bidi_source_warning_severity" "$lsp_out" '"severity":2'
assert_contains "lsp_bidi_source_warning_code" "$lsp_out" '"code":"W0003"'
assert_contains "lsp_bidi_source_warning_exact_range" "$lsp_out" '"range":{"start":{"line":0,"character":23},"end":{"line":0,"character":24}'

lsp_unicode_position_open='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///unicode-position.weft","version":1,"text":"fn add() -> i64 { 1 } fn main() -> i64 { let s = \"😀\" add() }"}}}'
lsp_unicode_position_hover16='{"jsonrpc":"2.0","id":14,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///unicode-position.weft"},"position":{"line":0,"character":54}}}'
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_init")" "$(lsp_frame "$lsp_unicode_position_open")" "$(lsp_frame "$lsp_unicode_position_hover16")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_utf16_supplementary_cursor_reaches_fact" "$lsp_out" '"id":14,"result":{"contents":{"kind":"plaintext","value":"function add: () -> i64"'

lsp_unicode_position_hover8='{"jsonrpc":"2.0","id":15,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///unicode-position.weft"},"position":{"line":0,"character":56}}}'
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_init_utf8")" "$(lsp_frame "$lsp_unicode_position_open")" "$(lsp_frame "$lsp_unicode_position_hover8")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_utf8_supplementary_cursor_reaches_fact" "$lsp_out" '"id":15,"result":{"contents":{"kind":"plaintext","value":"function add: () -> i64"'

lsp_unicode_position_hover32='{"jsonrpc":"2.0","id":16,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///unicode-position.weft"},"position":{"line":0,"character":53}}}'
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_init_utf32")" "$(lsp_frame "$lsp_unicode_position_open")" "$(lsp_frame "$lsp_unicode_position_hover32")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_utf32_supplementary_cursor_reaches_fact" "$lsp_out" '"id":16,"result":{"contents":{"kind":"plaintext","value":"function add: () -> i64"'

lsp_unicode_utf8_diagnostic_open='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///unicode-utf8-diagnostic.weft","version":1,"text":"fn main() -> i64 { let s = \"😀\" missing }"}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_init_utf8")" "$(lsp_frame "$lsp_unicode_utf8_diagnostic_open")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_utf8_diagnostic_range_counts_bytes" "$lsp_out" '"range":{"start":{"line":0,"character":34},"end":{"line":0,"character":41}'

large_lsp_source=""
for ((i = 0; i < 40; i++)); do
  large_lsp_source+="fn broken$i -> i64 { $i } "
done
lsp_large_open="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///large.weft\",\"version\":1,\"text\":\"$large_lsp_source\"}}}"
lsp_out=$(lsp_frame "$lsp_large_open" | "$WEFT" lsp 2>&1)
assert_contains "lsp_large_diagnostics_response" "$lsp_out" '"diagnostics":[{"range"'
assert_contains "lsp_large_diagnostics_late_range" "$lsp_out" '"range":{"start":{"line":0,"character":1006},"end":{"line":0,"character":1008}'

lsp_open_hover='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///hover.weft","version":1,"text":"fn add(x: i64) -> i64 { x } fn main() -> i64 { add(1) }"}}}'
lsp_hover='{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///hover.weft"},"position":{"line":0,"character":3}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_hover")" "$(lsp_frame "$lsp_hover")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_hover_function" "$lsp_out" '"value":"function add: (i64) -> i64"'

lsp_definition='{"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///hover.weft"},"position":{"line":0,"character":47}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_hover")" "$(lsp_frame "$lsp_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_definition_function" "$lsp_out" '"range":{"start":{"line":0,"character":3},"end":{"line":0,"character":6}}'

lsp_open_local='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///local.weft","version":1,"text":"fn main() -> i64 { let value = 41 value + 1 }"}}}'
lsp_local_hover='{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///local.weft"},"position":{"line":0,"character":34}}}'
lsp_local_definition='{"jsonrpc":"2.0","id":5,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///local.weft"},"position":{"line":0,"character":34}}}'
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_open_local")" "$(lsp_frame "$lsp_local_hover")" "$(lsp_frame "$lsp_local_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_hover_local" "$lsp_out" '"value":"local value: i64"'
assert_contains "lsp_definition_local" "$lsp_out" '"range":{"start":{"line":0,"character":23},"end":{"line":0,"character":28}}'

lsp_constant_prefix='const answer: i64 = 42 fn main() -> i64 { '
lsp_constant_source="${lsp_constant_prefix}answer }"
lsp_constant_use=${#lsp_constant_prefix}
lsp_open_constant="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///constant.weft\",\"version\":1,\"text\":\"$lsp_constant_source\"}}}"
lsp_constant_hover="{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///constant.weft\"},\"position\":{\"line\":0,\"character\":$lsp_constant_use}}}"
lsp_constant_definition="{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///constant.weft\"},\"position\":{\"line\":0,\"character\":$lsp_constant_use}}}"
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_open_constant")" "$(lsp_frame "$lsp_constant_hover")" "$(lsp_frame "$lsp_constant_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_hover_constant" "$lsp_out" '"value":"constant answer: i64"'
assert_contains "lsp_definition_constant" "$lsp_out" '"range":{"start":{"line":0,"character":6},"end":{"line":0,"character":12}}'

lsp_pattern_before='fn main(value: ((i64, str), i64)) -> i64 { let ((left, '
lsp_pattern_middle='label), right) = value __str_len('
lsp_pattern_after='label) + left + right }'
lsp_pattern_source="${lsp_pattern_before}${lsp_pattern_middle}${lsp_pattern_after}"
lsp_pattern_def=$((${#lsp_pattern_before}))
lsp_pattern_use=$((${#lsp_pattern_before} + ${#lsp_pattern_middle}))
lsp_open_pattern="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///pattern.weft\",\"version\":1,\"text\":\"$lsp_pattern_source\"}}}"
lsp_pattern_hover="{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///pattern.weft\"},\"position\":{\"line\":0,\"character\":$lsp_pattern_use}}}"
lsp_pattern_definition="{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///pattern.weft\"},\"position\":{\"line\":0,\"character\":$lsp_pattern_use}}}"
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_open_pattern")" "$(lsp_frame "$lsp_pattern_hover")" "$(lsp_frame "$lsp_pattern_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_hover_recursive_pattern_binding" "$lsp_out" '"value":"pattern binding label: str"'
assert_contains "lsp_definition_recursive_pattern_binding" "$lsp_out" "\"character\":$lsp_pattern_def},\"end\":{\"line\":0,\"character\":$((lsp_pattern_def + 5))}"

lsp_module_prefix='use module_fixtures/g2_function_left.{work} fn main(value: i64) -> i64 { value + '
lsp_module_source="${lsp_module_prefix}work() }"
lsp_module_work=$((${#lsp_module_prefix}))
lsp_open_module_symbols="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///Users/chris/Projects/weft/lsp-root.weft\",\"version\":1,\"text\":\"$lsp_module_source\"}}}"
lsp_module_definition="{\"jsonrpc\":\"2.0\",\"id\":43,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///Users/chris/Projects/weft/lsp-root.weft\"},\"position\":{\"line\":0,\"character\":$lsp_module_work}}}"
lsp_module_completion="{\"jsonrpc\":\"2.0\",\"id\":44,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///Users/chris/Projects/weft/lsp-root.weft\"},\"position\":{\"line\":0,\"character\":$lsp_module_work}}}"
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_open_module_symbols")" "$(lsp_frame "$lsp_module_definition")" "$(lsp_frame "$lsp_module_completion")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_definition_crosses_import" "$lsp_out" '"uri":"file:///Users/chris/Projects/weft/module_fixtures/g2_function_left.weft"'
assert_contains "lsp_definition_cross_import_range" "$lsp_out" '"start":{"line":0,"character":7},"end":{"line":0,"character":11}'
assert_contains "lsp_completion_includes_visible_import" "$lsp_out" '"label":"work","kind":3,"detail":"() -> i64"'
assert_contains "lsp_completion_includes_lexical_parameter" "$lsp_out" '"label":"value","kind":6,"detail":"i64"'
assert_not_contains "lsp_completion_excludes_private_import_member" "$lsp_out" '"label":"hidden"'

lsp_field_prefix='fn main(point: {x: i64, y: str}) -> i64 { point.'
lsp_field_source="${lsp_field_prefix}x }"
lsp_field_pos=$((${#lsp_field_prefix}))
lsp_open_field="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///field.weft\",\"version\":1,\"text\":\"$lsp_field_source\"}}}"
lsp_field_completion="{\"jsonrpc\":\"2.0\",\"id\":45,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///field.weft\"},\"position\":{\"line\":0,\"character\":$lsp_field_pos}}}"
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_field")" "$(lsp_frame "$lsp_field_completion")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_completion_structural_field_i64" "$lsp_out" '"label":"x","kind":5,"detail":"i64"'
assert_contains "lsp_completion_structural_field_str" "$lsp_out" '"label":"y","kind":5,"detail":"str"'
assert_not_contains "lsp_completion_field_mode_excludes_keywords" "$lsp_out" '"label":"handle"'

lsp_nominal_field_prefix='type LspPoint { x: i64, y: str } fn main(point: LspPoint) -> i64 { point.'
lsp_nominal_field_source="${lsp_nominal_field_prefix}x }"
lsp_nominal_field_pos=$((${#lsp_nominal_field_prefix}))
lsp_open_nominal_field="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///nominal-field.weft\",\"version\":1,\"text\":\"$lsp_nominal_field_source\"}}}"
lsp_nominal_field_completion="{\"jsonrpc\":\"2.0\",\"id\":46,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///nominal-field.weft\"},\"position\":{\"line\":0,\"character\":$lsp_nominal_field_pos}}}"
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_nominal_field")" "$(lsp_frame "$lsp_nominal_field_completion")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_completion_nominal_bridge_field_i64" "$lsp_out" '"label":"x","kind":5,"detail":"i64"'
assert_contains "lsp_completion_nominal_bridge_field_str" "$lsp_out" '"label":"y","kind":5,"detail":"str"'

lsp_tuple_prefix='fn main(pair: (i64, str)) -> i64 { pair.'
lsp_tuple_source="${lsp_tuple_prefix}0 }"
lsp_tuple_pos=${#lsp_tuple_prefix}
lsp_open_tuple="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///tuple.weft\",\"version\":1,\"text\":\"$lsp_tuple_source\"}}}"
lsp_tuple_completion="{\"jsonrpc\":\"2.0\",\"id\":67,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///tuple.weft\"},\"position\":{\"line\":0,\"character\":$lsp_tuple_pos}}}"
lsp_tuple_hover="{\"jsonrpc\":\"2.0\",\"id\":68,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///tuple.weft\"},\"position\":{\"line\":0,\"character\":$lsp_tuple_pos}}}"
lsp_tuple_definition="{\"jsonrpc\":\"2.0\",\"id\":69,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///tuple.weft\"},\"position\":{\"line\":0,\"character\":$lsp_tuple_pos}}}"
lsp_out=$(printf '%s%s%s%s' "$(lsp_frame "$lsp_open_tuple")" "$(lsp_frame "$lsp_tuple_completion")" "$(lsp_frame "$lsp_tuple_hover")" "$(lsp_frame "$lsp_tuple_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_tuple_position_source_is_clean" "$lsp_out" '"diagnostics":[]'
assert_contains "lsp_completion_tuple_position_i64" "$lsp_out" '"label":"0","kind":5,"detail":"i64"'
assert_contains "lsp_completion_tuple_position_str" "$lsp_out" '"label":"1","kind":5,"detail":"str"'
assert_contains "lsp_hover_tuple_position" "$lsp_out" '"value":"tuple position 0: i64"'
assert_contains "lsp_tuple_position_has_no_definition" "$lsp_out" '"id":69,"result":null'
assert_not_contains "lsp_completion_tuple_mode_excludes_keywords" "$lsp_out" '"label":"handle"'

lsp_bad_tuple_prefix='fn main(pair: (i64, str)) -> i64 { pair.'
lsp_bad_tuple_source="${lsp_bad_tuple_prefix}2 }"
lsp_bad_tuple_pos=${#lsp_bad_tuple_prefix}
lsp_open_bad_tuple="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///bad-tuple.weft\",\"version\":1,\"text\":\"$lsp_bad_tuple_source\"}}}"
lsp_bad_tuple_hover="{\"jsonrpc\":\"2.0\",\"id\":70,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///bad-tuple.weft\"},\"position\":{\"line\":0,\"character\":$lsp_bad_tuple_pos}}}"
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_bad_tuple")" "$(lsp_frame "$lsp_bad_tuple_hover")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_unknown_tuple_position_diagnostic" "$lsp_out" 'type error: unknown tuple position'
assert_contains "lsp_unknown_tuple_position_has_no_hover" "$lsp_out" '"id":70,"result":null'

lsp_match_before_first='fn main(value: str | nil) -> i64 { match value { '
lsp_match_first_arm='text: str if __str_len(text) > 3 -> 1, '
lsp_match_second_arm='text: str -> 2, '
lsp_match_nil_arm='nil -> 3 } }'
lsp_match_source="${lsp_match_before_first}${lsp_match_first_arm}${lsp_match_second_arm}${lsp_match_nil_arm}"
lsp_match_first=${#lsp_match_before_first}
lsp_match_second=$((${#lsp_match_before_first} + ${#lsp_match_first_arm}))
lsp_match_nil=$((${#lsp_match_before_first} + ${#lsp_match_first_arm} + ${#lsp_match_second_arm}))
lsp_open_match="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///match.weft\",\"version\":1,\"text\":\"$lsp_match_source\"}}}"
lsp_match_first_hover="{\"jsonrpc\":\"2.0\",\"id\":71,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///match.weft\"},\"position\":{\"line\":0,\"character\":$lsp_match_first}}}"
lsp_match_second_hover="{\"jsonrpc\":\"2.0\",\"id\":72,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///match.weft\"},\"position\":{\"line\":0,\"character\":$lsp_match_second}}}"
lsp_match_nil_hover="{\"jsonrpc\":\"2.0\",\"id\":73,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///match.weft\"},\"position\":{\"line\":0,\"character\":$lsp_match_nil}}}"
lsp_match_definition="{\"jsonrpc\":\"2.0\",\"id\":74,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///match.weft\"},\"position\":{\"line\":0,\"character\":$lsp_match_second}}}"
lsp_out=$(printf '%s%s%s%s%s' "$(lsp_frame "$lsp_open_match")" "$(lsp_frame "$lsp_match_first_hover")" "$(lsp_frame "$lsp_match_second_hover")" "$(lsp_frame "$lsp_match_nil_hover")" "$(lsp_frame "$lsp_match_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_typed_match_source_is_clean" "$lsp_out" '"diagnostics":[]'
assert_contains "lsp_hover_guarded_match_arm_teaches_residual_rule" "$lsp_out" '"value":"match arm: narrowed str; residual after guarded arm str | nil (guards do not subtract)"'
assert_contains "lsp_hover_typed_match_arm_shows_residual" "$lsp_out" '"value":"match arm: narrowed str; residual after arm nil"'
assert_contains "lsp_hover_nil_match_arm_shows_empty_residual" "$lsp_out" '"value":"match arm: narrowed nil; residual after arm never"'
assert_contains "lsp_match_arm_has_no_definition" "$lsp_out" '"id":74,"result":null'

lsp_bad_match_before='fn main(value: str | nil) -> i64 { match value { '
lsp_bad_match_source="${lsp_bad_match_before}number: i64 -> 0, nil -> 1 } }"
lsp_bad_match_pos=${#lsp_bad_match_before}
lsp_open_bad_match="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///bad-match.weft\",\"version\":1,\"text\":\"$lsp_bad_match_source\"}}}"
lsp_bad_match_hover="{\"jsonrpc\":\"2.0\",\"id\":75,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///bad-match.weft\"},\"position\":{\"line\":0,\"character\":$lsp_bad_match_pos}}}"
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_bad_match")" "$(lsp_frame "$lsp_bad_match_hover")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_invalid_typed_match_diagnostic" "$lsp_out" 'typed match arm annotation is not part of the scrutinee type'
assert_not_contains "lsp_invalid_typed_match_has_no_residual_fact" "$lsp_out" 'match arm:'

lsp_effect_decl_prefix='effect LspState<S> { fn '
lsp_effect_prefix='effect LspState<S> { fn get() -> S fn put(value: S) -> nil } fn read() -[LspState<i64>]> i64 { LspState.'
lsp_effect_source="${lsp_effect_prefix}get() }"
lsp_effect_decl_get=${#lsp_effect_decl_prefix}
lsp_effect_atom=$((${#lsp_effect_prefix} - 9))
lsp_effect_operation=${#lsp_effect_prefix}
lsp_open_effect="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///effect.weft\",\"version\":1,\"text\":\"$lsp_effect_source\"}}}"
lsp_effect_atom_hover="{\"jsonrpc\":\"2.0\",\"id\":47,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///effect.weft\"},\"position\":{\"line\":0,\"character\":$lsp_effect_atom}}}"
lsp_effect_operation_hover="{\"jsonrpc\":\"2.0\",\"id\":48,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///effect.weft\"},\"position\":{\"line\":0,\"character\":$lsp_effect_operation}}}"
lsp_effect_operation_definition="{\"jsonrpc\":\"2.0\",\"id\":49,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///effect.weft\"},\"position\":{\"line\":0,\"character\":$lsp_effect_operation}}}"
lsp_effect_completion="{\"jsonrpc\":\"2.0\",\"id\":50,\"method\":\"textDocument/completion\",\"params\":{\"textDocument\":{\"uri\":\"file:///effect.weft\"},\"position\":{\"line\":0,\"character\":$lsp_effect_operation}}}"
lsp_out=$(printf '%s%s%s%s%s' "$(lsp_frame "$lsp_open_effect")" "$(lsp_frame "$lsp_effect_atom_hover")" "$(lsp_frame "$lsp_effect_operation_hover")" "$(lsp_frame "$lsp_effect_operation_definition")" "$(lsp_frame "$lsp_effect_completion")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_hover_exact_effect_atom" "$lsp_out" '"value":"effect LspState<i64>"'
assert_contains "lsp_hover_exact_effect_operation" "$lsp_out" '"value":"effect operation LspState<i64>.get: () -[LspState<i64>]> i64"'
assert_contains "lsp_definition_effect_operation" "$lsp_out" "\"character\":$lsp_effect_decl_get},\"end\":{\"line\":0,\"character\":$((lsp_effect_decl_get + 3))}"
assert_contains "lsp_completion_exact_effect_get" "$lsp_out" '"label":"get","kind":3,"detail":"() -[LspState<i64>]> i64"'
assert_contains "lsp_completion_exact_effect_put" "$lsp_out" '"label":"put","kind":3,"detail":"(i64) -[LspState<i64>]> nil"'
assert_not_contains "lsp_completion_effect_mode_excludes_fields" "$lsp_out" '"kind":5'

lsp_handler_prefix='effect LspHandle<S> { fn get() -> S } fn go() -[LspHandle<i64>]> i64 { LspHandle.get() } fn main() -> i64 { handle go() { LspHandle<i64>.'
lsp_handler_source="${lsp_handler_prefix}get() -> resume(42) } }"
lsp_handler_operation=${#lsp_handler_prefix}
lsp_open_handler="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///handler.weft\",\"version\":1,\"text\":\"$lsp_handler_source\"}}}"
lsp_handler_hover="{\"jsonrpc\":\"2.0\",\"id\":51,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///handler.weft\"},\"position\":{\"line\":0,\"character\":$lsp_handler_operation}}}"
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_handler")" "$(lsp_frame "$lsp_handler_hover")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_hover_exact_handler_operation" "$lsp_out" '"value":"effect operation LspHandle<i64>.get: () -[LspHandle<i64>]> i64"'

lsp_assoc_before_binding='trait LspAssoc { type Item fn get(self, value: Self.Item) -> Self.Item } type LspAssocBox { value: i64 } impl LspAssoc for LspAssocBox { type '
lsp_assoc_between='Item = [i64; 4] fn get(self, value: '
lsp_assoc_after='Self.Item) -> Self.Item { value } } fn main() -> i64 { 0 }'
lsp_assoc_source="${lsp_assoc_before_binding}${lsp_assoc_between}${lsp_assoc_after}"
lsp_assoc_binding=${#lsp_assoc_before_binding}
lsp_assoc_use=$((${#lsp_assoc_before_binding} + ${#lsp_assoc_between}))
lsp_open_assoc="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///assoc.weft\",\"version\":1,\"text\":\"$lsp_assoc_source\"}}}"
lsp_assoc_hover="{\"jsonrpc\":\"2.0\",\"id\":52,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///assoc.weft\"},\"position\":{\"line\":0,\"character\":$lsp_assoc_use}}}"
lsp_assoc_definition="{\"jsonrpc\":\"2.0\",\"id\":53,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"file:///assoc.weft\"},\"position\":{\"line\":0,\"character\":$lsp_assoc_use}}}"
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_open_assoc")" "$(lsp_frame "$lsp_assoc_hover")" "$(lsp_frame "$lsp_assoc_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_associated_type_source_is_clean" "$lsp_out" '"diagnostics":[]'
assert_contains "lsp_hover_resolves_associated_type" "$lsp_out" '"value":"associated type LspAssocBox.Item = [i64; 4]"'
assert_contains "lsp_definition_associated_type_binding" "$lsp_out" "\"character\":$lsp_assoc_binding},\"end\":{\"line\":0,\"character\":$((lsp_assoc_binding + 4))}"

lsp_missing_assoc_prefix='trait LspMissingAssoc { type Item fn get(self, value: Self.Item) -> Self.Item } type LspMissingBox { value: i64 } impl LspMissingAssoc for LspMissingBox { fn get(self, value: '
lsp_missing_assoc_source="${lsp_missing_assoc_prefix}Self.Item) -> Self.Item { value } } fn main() -> i64 { 0 }"
lsp_missing_assoc_use=${#lsp_missing_assoc_prefix}
lsp_open_missing_assoc="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///missing-assoc.weft\",\"version\":1,\"text\":\"$lsp_missing_assoc_source\"}}}"
lsp_missing_assoc_hover="{\"jsonrpc\":\"2.0\",\"id\":54,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///missing-assoc.weft\"},\"position\":{\"line\":0,\"character\":$lsp_missing_assoc_use}}}"
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_missing_assoc")" "$(lsp_frame "$lsp_missing_assoc_hover")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_missing_associated_binding_diagnostic" "$lsp_out" 'type error: impl missing required associated type'
assert_contains "lsp_missing_associated_binding_has_no_hover_fact" "$lsp_out" '"id":54,"result":null'

lsp_unknown_hover='{"jsonrpc":"2.0","id":6,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///missing.weft"},"position":{"line":0,"character":0}}}'
lsp_out=$(lsp_frame "$lsp_unknown_hover" | "$WEFT" lsp 2>&1)
assert_contains "lsp_unknown_file_hover_null" "$lsp_out" '"result":null'

lsp_unknown_definition='{"jsonrpc":"2.0","id":66,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///missing.weft"},"position":{"line":0,"character":0}}}'
lsp_out=$(lsp_frame "$lsp_unknown_definition" | "$WEFT" lsp 2>&1)
assert_contains "lsp_unknown_file_definition_null" "$lsp_out" '"result":null'

lsp_change_bad='{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///rapid.weft","version":2},"contentChanges":[{"text":"fn main() -> i64 { missing }"}]}}'
lsp_change_good='{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///rapid.weft","version":3},"contentChanges":[{"text":"fn main() -> i64 { 1 }"}]}}'
lsp_open_rapid='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///rapid.weft","version":1,"text":"fn main() -> i64 { 0 }"}}}'
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_open_rapid")" "$(lsp_frame "$lsp_change_bad")" "$(lsp_frame "$lsp_change_good")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_rapid_edit_bad_diagnostic" "$lsp_out" "unknown identifier 'missing'"
assert_contains "lsp_rapid_edit_final_clean" "$lsp_out" '"uri":"file:///rapid.weft","diagnostics":[]'

lsp_stale_change='{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///stale.weft","version":1},"contentChanges":[{"text":"fn main() -> i64 { missing }"}]}}'
lsp_open_stale='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///stale.weft","version":2,"text":"fn main() -> i64 { 0 }"}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_stale")" "$(lsp_frame "$lsp_stale_change")" | "$WEFT" lsp 2>&1)
assert_not_contains "lsp_stale_update_ignored" "$lsp_out" "unknown identifier 'missing'"

# A newer version may carry byte-identical text (save hooks and editor
# normalization do this routinely). It must preserve the cached semantic
# product while still advancing the document version used to reject stale
# traffic.
lsp_unchanged_source='fn same_value() -> i64 { 42 } fn main() -> i64 { same_value() }'
lsp_unchanged_prefix='fn same_value() -> i64 { 42 } fn main() -> i64 { '
lsp_open_unchanged="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///unchanged.weft\",\"version\":1,\"text\":\"$lsp_unchanged_source\"}}}"
lsp_change_unchanged="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"file:///unchanged.weft\",\"version\":2},\"contentChanges\":[{\"text\":\"$lsp_unchanged_source\"}]}}"
lsp_change_unchanged_stale='{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///unchanged.weft","version":1},"contentChanges":[{"text":"fn main() -> i64 { missing }"}]}}'
lsp_unchanged_hover="{\"jsonrpc\":\"2.0\",\"id\":86,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"file:///unchanged.weft\"},\"position\":{\"line\":0,\"character\":${#lsp_unchanged_prefix}}}}"
lsp_out=$(printf '%s%s%s%s' "$(lsp_frame "$lsp_open_unchanged")" "$(lsp_frame "$lsp_change_unchanged")" "$(lsp_frame "$lsp_change_unchanged_stale")" "$(lsp_frame "$lsp_unchanged_hover")" | "$WEFT" lsp 2>&1)
assert_equals "lsp_unchanged_newer_version_republishes_clean" "$(printf '%s' "$lsp_out" | grep -o '"uri":"file:///unchanged.weft","diagnostics":\[\]' | wc -l | tr -d ' ')" "2"
assert_not_contains "lsp_unchanged_newer_version_advances_stale_fence" "$lsp_out" "unknown identifier 'missing'"
assert_contains "lsp_unchanged_newer_version_reuses_semantics" "$lsp_out" '"id":86,"result":{"contents":{"kind":"plaintext","value":"function same_value: () -> i64"'

# Active document graph: the dependency paths below deliberately do not exist
# on disk. The shared resolver selects their normal module identities, while
# the source registry overlays bytes supplied by didOpen/didChange.
lsp_active_stem="_weft_lsp_active_$$_dep"
lsp_active_module="module_fixtures/$lsp_active_stem"
lsp_active_root_uri="file://$PWD/_weft_lsp_active_$$_root.weft"
lsp_active_dep_uri="file://$PWD/$lsp_active_module.weft"
lsp_active_root_prefix="use $lsp_active_module.{active_value} fn main() -> i64 { "
lsp_active_root_source="${lsp_active_root_prefix}active_value() }"
lsp_active_use=${#lsp_active_root_prefix}
lsp_active_dep_source='pub fn active_value() -> i64 { 42 }'
lsp_active_init="{\"jsonrpc\":\"2.0\",\"id\":80,\"method\":\"initialize\",\"params\":{\"rootUri\":\"file://$PWD\"}}"
lsp_active_open_root="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_root_uri\",\"version\":1,\"text\":\"$lsp_active_root_source\"}}}"
lsp_active_open_dep="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_dep_uri\",\"version\":1,\"text\":\"$lsp_active_dep_source\"}}}"
lsp_active_hover="{\"jsonrpc\":\"2.0\",\"id\":81,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_root_uri\"},\"position\":{\"line\":0,\"character\":$lsp_active_use}}}"
lsp_active_definition="{\"jsonrpc\":\"2.0\",\"id\":82,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_root_uri\"},\"position\":{\"line\":0,\"character\":$lsp_active_use}}}"
lsp_active_change_bad="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_dep_uri\",\"version\":2},\"contentChanges\":[{\"text\":\"pub fn renamed() -> i64 { 0 }\"}]}}"
lsp_active_change_good="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_dep_uri\",\"version\":3},\"contentChanges\":[{\"text\":\"$lsp_active_dep_source\"}]}}"
lsp_active_change_stale="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_dep_uri\",\"version\":2},\"contentChanges\":[{\"text\":\"pub fn stale() -> i64 { 0 }\"}]}}"
lsp_active_hover_after_stale="{\"jsonrpc\":\"2.0\",\"id\":83,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_root_uri\"},\"position\":{\"line\":0,\"character\":$lsp_active_use}}}"
lsp_active_close_dep="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_dep_uri\"}}}"
lsp_active_hover_closed="{\"jsonrpc\":\"2.0\",\"id\":84,\"method\":\"textDocument/hover\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_dep_uri\"},\"position\":{\"line\":0,\"character\":7}}}"
lsp_out=$(printf '%s%s%s%s%s%s%s%s%s%s%s' "$(lsp_frame "$lsp_active_init")" "$(lsp_frame "$lsp_active_open_root")" "$(lsp_frame "$lsp_active_open_dep")" "$(lsp_frame "$lsp_active_hover")" "$(lsp_frame "$lsp_active_definition")" "$(lsp_frame "$lsp_active_change_bad")" "$(lsp_frame "$lsp_active_change_good")" "$(lsp_frame "$lsp_active_change_stale")" "$(lsp_frame "$lsp_active_hover_after_stale")" "$(lsp_frame "$lsp_active_close_dep")" "$(lsp_frame "$lsp_active_hover_closed")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_active_graph_observes_missing_disk_module" "$lsp_out" "unknown function 'active_value'"
assert_contains "lsp_active_graph_overlay_clears_importer" "$lsp_out" "\"uri\":\"$lsp_active_root_uri\",\"diagnostics\":[]"
assert_contains "lsp_active_graph_publishes_dependency_clean" "$lsp_out" "\"uri\":\"$lsp_active_dep_uri\",\"diagnostics\":[]"
assert_contains "lsp_active_graph_hover_uses_overlay" "$lsp_out" '"id":81,"result":{"contents":{"kind":"plaintext","value":"function active_value: () -> i64"'
assert_contains "lsp_active_graph_definition_uses_overlay_uri" "$lsp_out" "\"id\":82,\"result\":{\"uri\":\"$lsp_active_dep_uri\""
assert_contains "lsp_active_graph_definition_uses_overlay_range" "$lsp_out" '"start":{"line":0,"character":7},"end":{"line":0,"character":19}'
assert_contains "lsp_active_graph_change_invalidates_importer" "$lsp_out" '"code":"E4002"'
assert_equals "lsp_active_graph_stale_change_is_ignored" "$(printf '%s' "$lsp_out" | grep -Eo '"source":"weft","message":"[^"]*","code":"E4002"' | wc -l | tr -d ' ')" "1"
assert_contains "lsp_active_graph_good_version_survives_stale_change" "$lsp_out" '"id":83,"result":{"contents":{"kind":"plaintext","value":"function active_value: () -> i64"'
assert_equals "lsp_active_graph_close_invalidates_importer" "$(printf '%s' "$lsp_out" | grep -o "\"source\":\"weft\",\"message\":\"unknown function 'active_value'\"" | wc -l | tr -d ' ')" "2"
assert_contains "lsp_active_graph_close_clears_dependency" "$lsp_out" "\"uri\":\"$lsp_active_dep_uri\",\"diagnostics\":[]"
assert_contains "lsp_active_graph_close_removes_document" "$lsp_out" '"id":84,"result":null'

lsp_active_bad_dep='pub fn active_value() -> i64 { missing }'
lsp_active_open_bad_dep="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_active_dep_uri\",\"version\":1,\"text\":\"$lsp_active_bad_dep\"}}}"
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_active_init")" "$(lsp_frame "$lsp_active_open_bad_dep")" "$(lsp_frame "$lsp_active_open_root")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_active_graph_routes_dependency_diagnostic" "$lsp_out" "\"uri\":\"$lsp_active_dep_uri\",\"diagnostics\":[{"
assert_contains "lsp_active_graph_preserves_dependency_diagnostic" "$lsp_out" "unknown identifier 'missing'"
assert_contains "lsp_active_graph_keeps_importer_clean_for_dependency_body_error" "$lsp_out" "\"uri\":\"$lsp_active_root_uri\",\"diagnostics\":[]"

lsp_reexport_mid="_weft_lsp_reexport_$$_mid"
lsp_reexport_leaf="_weft_lsp_reexport_$$_leaf"
lsp_reexport_root_uri="file://$PWD/_weft_lsp_reexport_$$_root.weft"
lsp_reexport_mid_uri="file://$PWD/module_fixtures/$lsp_reexport_mid.weft"
lsp_reexport_leaf_uri="file://$PWD/module_fixtures/$lsp_reexport_leaf.weft"
lsp_reexport_root_prefix="use module_fixtures/$lsp_reexport_mid.{active_value} fn main() -> i64 { "
lsp_reexport_root_source="${lsp_reexport_root_prefix}active_value() }"
lsp_reexport_mid_source="pub use module_fixtures/$lsp_reexport_leaf.{active_value}"
lsp_reexport_leaf_source='pub fn active_value() -> i64 { 42 }'
lsp_reexport_open_leaf="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_reexport_leaf_uri\",\"version\":1,\"text\":\"$lsp_reexport_leaf_source\"}}}"
lsp_reexport_open_mid="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_reexport_mid_uri\",\"version\":1,\"text\":\"$lsp_reexport_mid_source\"}}}"
lsp_reexport_open_root="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_reexport_root_uri\",\"version\":1,\"text\":\"$lsp_reexport_root_source\"}}}"
lsp_reexport_definition="{\"jsonrpc\":\"2.0\",\"id\":85,\"method\":\"textDocument/definition\",\"params\":{\"textDocument\":{\"uri\":\"$lsp_reexport_root_uri\"},\"position\":{\"line\":0,\"character\":${#lsp_reexport_root_prefix}}}}"
lsp_out=$(printf '%s%s%s%s%s' "$(lsp_frame "$lsp_active_init")" "$(lsp_frame "$lsp_reexport_open_leaf")" "$(lsp_frame "$lsp_reexport_open_mid")" "$(lsp_frame "$lsp_reexport_open_root")" "$(lsp_frame "$lsp_reexport_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_active_reexport_graph_is_clean" "$lsp_out" "\"uri\":\"$lsp_reexport_root_uri\",\"diagnostics\":[]"
assert_contains "lsp_active_reexport_definition_reaches_origin" "$lsp_out" "\"id\":85,\"result\":{\"uri\":\"$lsp_reexport_leaf_uri\""
assert_contains "lsp_active_reexport_definition_preserves_origin_range" "$lsp_out" '"start":{"line":0,"character":7},"end":{"line":0,"character":19}'

# Slow writer: frames delivered across multiple pipe reads must not be
# truncated (read_fd_all once treated any short read as EOF).
lsp_slow_full="$(lsp_frame "$lsp_open_hover")$(lsp_frame "$lsp_definition")"
lsp_slow_head=${lsp_slow_full:0:40}
lsp_slow_tail=${lsp_slow_full:40}
lsp_out=$( { printf '%s' "$lsp_slow_head"; sleep 0.2; printf '%s' "$lsp_slow_tail"; } | "$WEFT" lsp 2>&1)
assert_contains "lsp_slow_writer_definition" "$lsp_out" '"range":{"start":{"line":0,"character":3},"end":{"line":0,"character":6}}'

lsp_completion='{"jsonrpc":"2.0","id":7,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///hover.weft"},"position":{"line":0,"character":1}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_hover")" "$(lsp_frame "$lsp_completion")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_completion_hook_items" "$lsp_out" '"label":"add","kind":3,"detail":"(i64) -> i64"'

lsp_code_action='{"jsonrpc":"2.0","id":8,"method":"textDocument/codeAction","params":{"textDocument":{"uri":"file:///hover.weft"},"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"context":{"diagnostics":[]}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_hover")" "$(lsp_frame "$lsp_code_action")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_code_action_hook" "$lsp_out" "Consider par_map"

lsp_out=$(printf '%s' 'not-json' | "$WEFT" lsp 2>&1)
assert_contains "lsp_malformed_json_rpc_error" "$lsp_out" '"code":-32700'

lsp_unknown='{"jsonrpc":"2.0","id":9,"method":"workspace/unknown","params":{}}'
lsp_out=$(lsp_frame "$lsp_unknown" | "$WEFT" lsp 2>&1)
assert_contains "lsp_unknown_method_error" "$lsp_out" '"code":-32601'

printf 'fn main() -> i64 { let mut i = 0 let mut stop = 0 while i < 5 && stop == 0 { i = i + 1 } i }\n' > "$tmp_src"
amp_diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_contains "check_rejects_symbolic_and" "$amp_diag_out" "error[E0002]: expected '{' after while condition"

printf 'test "plain" { Test.assert_eq(1, 1) }\n' > "$tmp_src"
test_check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_accepts_test_blocks" "$test_check_out" "0 errors"
test_ast_out=$("$WEFT" ast < "$tmp_src" 2>&1)
assert_contains "ast_accepts_test_blocks" "$test_ast_out" "test plain:"

write_large_padding "$tmp_src"
printf 'fn main() -> i64 { 0 }\n' >> "$tmp_src"
large_check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reads_large_stdin" "$large_check_out" "check: 1 functions, 0 errors"
run_weft_compile_guarded "$WEFT" < "$tmp_src" > "$tmp_bin" 2>/dev/null
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin"
echo "  ok compile_reads_large_stdin"

write_large_padding "$tmp_import"
printf 'pub fn sentinel() -> i64 { 99 }\n' >> "$tmp_import"
printf 'use module_fixtures/_weft_tool_import_%s.{*}\nfn main() -> i64 { sentinel() }\n' "$$" > "$tmp_src"
large_import_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reads_large_import" "$large_import_out" "check: 2 functions, 0 errors"

write_huge_padding "$tmp_src"
printf 'fn main() -> i64 { 0 }\n' >> "$tmp_src"
huge_check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reads_huge_stdin_offsets" "$huge_check_out" "check: 1 functions, 0 errors"
run_weft_compile_guarded "$WEFT" < "$tmp_src" > "$tmp_bin" 2>/dev/null
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin"
echo "  ok compile_reads_huge_stdin_offsets"

mkdir -p "$tmp_pkg_dir/deps/math"
printf '{"package":"app","dependencies":{"math":"deps/math"}}\n' > "$tmp_pkg_dir/weft.pkg"
printf 'pub fn add(a: i64, b: i64) -> i64 { a + b }\n' > "$tmp_pkg_dir/deps/math/lib.weft"
printf 'use math/lib.{*}\nfn main() -> i64 { if add(40, 2) == 42 { 0 } else { 1 } }\n' > "$tmp_pkg_dir/app.weft"
(cd "$tmp_pkg_dir" && run_weft_compile_guarded "$WEFT_ABS" < app.weft > app 2>"$tmp_err")
chmod +x "$tmp_pkg_dir/app"
run_binary_guarded "$tmp_pkg_dir/app"
echo "  ok package_local_dep_import_compiles"

mkdir -p "$tmp_pkg_dir/.weft/cache/math"
printf 'pub fn cached_value() -> i64 { 1 }\n' > "$tmp_pkg_dir/deps/math/lib.weft"
printf 'pub fn cached_value() -> i64 { 42 }\n' > "$tmp_pkg_dir/.weft/cache/math/lib.weft"
printf 'use math/lib.{*}\nfn main() -> i64 { if cached_value() == 1 { 0 } else { 1 } }\n' > "$tmp_pkg_dir/app.weft"
(cd "$tmp_pkg_dir" && run_weft_compile_guarded "$WEFT_ABS" < app.weft > app 2>"$tmp_err")
chmod +x "$tmp_pkg_dir/app"
run_binary_guarded "$tmp_pkg_dir/app"
echo "  ok package_live_path_dep_ignores_cache_shadow"

printf 'pub fn public_value() -> i64 { 42 }\npub(package) fn package_value() -> i64 { 7 }\nfn private_value() -> i64 { 9 }\n' > "$tmp_pkg_dir/deps/math/visibility.weft"
printf 'use math/visibility.{public_value}\nfn main() -> i64 { if public_value() == 42 { 0 } else { 1 } }\n' > "$tmp_pkg_dir/app.weft"
(cd "$tmp_pkg_dir" && run_weft_compile_guarded "$WEFT_ABS" < app.weft > app 2>"$tmp_err")
chmod +x "$tmp_pkg_dir/app"
run_binary_guarded "$tmp_pkg_dir/app"
echo "  ok package_public_member_crosses_dependency_boundary"

printf 'use math/visibility.{package_value}\nfn main() -> i64 { package_value() }\n' > "$tmp_pkg_dir/app.weft"
package_visible_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_package_member_stays_inside_dependency" "$package_visible_out" "error[E4004]: module member 'package_value' is not visible in this import"

printf 'use math/visibility.{private_value}\nfn main() -> i64 { private_value() }\n' > "$tmp_pkg_dir/app.weft"
package_private_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_private_member_stays_inside_dependency_module" "$package_private_out" "error[E4004]: module member 'private_value' is not visible in this import"

mkdir -p "$tmp_pkg_dir/deps/lib/deps/base" "$tmp_pkg_dir/deps/mirror"
printf '{"package":"app","dependencies":{"lib":"deps/lib","mirror":"deps/mirror"}}\n' > "$tmp_pkg_dir/weft.pkg"
printf '{"package":"lib","dependencies":{"base":"deps/base"}}\n' > "$tmp_pkg_dir/deps/lib/weft.pkg"
printf '{"package":"base","dependencies":{}}\n' > "$tmp_pkg_dir/deps/lib/deps/base/weft.pkg"
printf '{"package":"mirror","dependencies":{}}\n' > "$tmp_pkg_dir/deps/mirror/weft.pkg"
printf 'pub(package) fn package_value() -> i64 { 40 }\n' > "$tmp_pkg_dir/deps/lib/deps/base/value.weft"
printf 'use value.{package_value}\npub fn base_value() -> i64 { package_value() + 2 }\n' > "$tmp_pkg_dir/deps/lib/deps/base/api.weft"
printf 'pub use base/api.{base_value}\n' > "$tmp_pkg_dir/deps/lib/lib.weft"
printf 'pub fn mirror_value() -> i64 { 9 }\n' > "$tmp_pkg_dir/deps/mirror/value.weft"
printf 'use lib/lib.{base_value}\nuse mirror/value.{mirror_value}\nfn main() -> i64 { if base_value() == 42 and mirror_value() == 9 { 0 } else { 1 } }\n' > "$tmp_pkg_dir/app.weft"
(cd "$tmp_pkg_dir" && run_weft_compile_guarded "$WEFT_ABS" < app.weft > app 2>"$tmp_err")
chmod +x "$tmp_pkg_dir/app"
run_binary_guarded "$tmp_pkg_dir/app"
echo "  ok package_transitive_owner_relative_reexport_compiles"
echo "  ok package_loader_keeps_same_module_path_per_owner"
echo "  ok package_visibility_allows_package_member_inside_owner"

mkdir -p "$tmp_pkg_dir/deps/broken"
printf '{"package":"app","dependencies":{"broken":"deps/broken"}}\n' > "$tmp_pkg_dir/weft.pkg"
printf '{"package":' > "$tmp_pkg_dir/deps/broken/weft.pkg"
printf 'pub fn value() -> i64 { 1 }\n' > "$tmp_pkg_dir/deps/broken/lib.weft"
printf 'use broken/lib.{value}\nfn main() -> i64 { value() }\n' > "$tmp_pkg_dir/app.weft"
package_malformed_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_malformed_manifest_stable_code" "$package_malformed_out" "error[E5001]: dependency 'broken' has a malformed manifest"

printf '{"package":"different","dependencies":{}}\n' > "$tmp_pkg_dir/deps/broken/weft.pkg"
package_mismatch_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_name_mismatch_stable_code" "$package_mismatch_out" "error[E5002]: dependency 'broken' does not match the package name in its manifest"

mkdir -p "$tmp_pkg_dir/deps/left/deps/common" "$tmp_pkg_dir/deps/right/deps/common"
printf '{"package":"app","dependencies":{"left":"deps/left","right":"deps/right"}}\n' > "$tmp_pkg_dir/weft.pkg"
printf '{"package":"left","dependencies":{"common":"deps/common"}}\n' > "$tmp_pkg_dir/deps/left/weft.pkg"
printf '{"package":"right","dependencies":{"common":"deps/common"}}\n' > "$tmp_pkg_dir/deps/right/weft.pkg"
printf '{"package":"common","dependencies":{}}\n' > "$tmp_pkg_dir/deps/left/deps/common/weft.pkg"
printf '{"package":"common","dependencies":{}}\n' > "$tmp_pkg_dir/deps/right/deps/common/weft.pkg"
printf 'pub fn common_value() -> i64 { 1 }\n' > "$tmp_pkg_dir/deps/left/deps/common/value.weft"
printf 'pub fn common_value() -> i64 { 2 }\n' > "$tmp_pkg_dir/deps/right/deps/common/value.weft"
printf 'use common/value.{common_value}\npub fn left_value() -> i64 { common_value() }\n' > "$tmp_pkg_dir/deps/left/lib.weft"
printf 'use common/value.{common_value}\npub fn right_value() -> i64 { common_value() }\n' > "$tmp_pkg_dir/deps/right/lib.weft"
printf 'use left/lib.{left_value}\nuse right/lib.{right_value}\nfn main() -> i64 { left_value() + right_value() }\n' > "$tmp_pkg_dir/app.weft"
package_conflict_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_source_conflict_stable_code" "$package_conflict_out" "error[E5003]: dependency 'common' resolves to conflicting source identities"

mkdir -p "$tmp_pkg_dir/deps/cycle_a/deps/cycle_b"
printf '{"package":"app","dependencies":{"cycle_a":"deps/cycle_a"}}\n' > "$tmp_pkg_dir/weft.pkg"
printf '{"package":"cycle_a","dependencies":{"cycle_b":"deps/cycle_b"}}\n' > "$tmp_pkg_dir/deps/cycle_a/weft.pkg"
printf '{"package":"cycle_b","dependencies":{"cycle_a":"deps/cycle_a"}}\n' > "$tmp_pkg_dir/deps/cycle_a/deps/cycle_b/weft.pkg"
printf 'use cycle_b/lib.{cycle_b_value}\npub fn cycle_a_value() -> i64 { cycle_b_value() }\n' > "$tmp_pkg_dir/deps/cycle_a/lib.weft"
printf 'use cycle_a/lib.{cycle_a_value}\npub fn cycle_b_value() -> i64 { cycle_a_value() }\n' > "$tmp_pkg_dir/deps/cycle_a/deps/cycle_b/lib.weft"
printf 'use cycle_a/lib.{cycle_a_value}\nfn main() -> i64 { cycle_a_value() }\n' > "$tmp_pkg_dir/app.weft"
package_cycle_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_dependency_cycle_stable_code" "$package_cycle_out" "error[E5004]: dependency 'cycle_a' forms a package dependency cycle"

mkdir -p "$tmp_pkg_dir/deps/lib/deps/app"
printf '{"package":"app","dependencies":{"lib":"deps/lib"}}\n' > "$tmp_pkg_dir/weft.pkg"
printf '{"package":"lib","dependencies":{"app":"deps/app"}}\n' > "$tmp_pkg_dir/deps/lib/weft.pkg"
printf '{"package":"app","dependencies":{}}\n' > "$tmp_pkg_dir/deps/lib/deps/app/weft.pkg"
printf 'use app/lib.{app_value}\npub fn lib_value() -> i64 { app_value() }\n' > "$tmp_pkg_dir/deps/lib/lib.weft"
printf 'pub fn app_value() -> i64 { 1 }\n' > "$tmp_pkg_dir/deps/lib/deps/app/lib.weft"
printf 'use lib/lib.{lib_value}\nfn main() -> i64 { lib_value() }\n' > "$tmp_pkg_dir/app.weft"
package_root_cycle_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_dependency_cycle_back_to_root_code" "$package_root_cycle_out" "error[E5004]: dependency 'app' forms a package dependency cycle"

outside_name=$(basename "$tmp_outside_dir")
printf 'fn hidden() -> i64 { 0 }\n' > "$tmp_outside_dir/lib.weft"
printf 'package app\ndep evil ../%s\n' "$outside_name" > "$tmp_pkg_dir/weft.pkg"
printf 'use evil/lib.{*}\nfn main() -> i64 { hidden() }\n' > "$tmp_pkg_dir/app.weft"
traversal_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_rejects_traversal_dep_path" "$traversal_out" "error[E1001]: unknown function"

printf 'package app\ndep math deps/math 1.0.0\n' > "$tmp_pkg_dir/weft.pkg"
printf 'use math/lib.{*}\nfn main() -> i64 { add(1, 2) }\n' > "$tmp_pkg_dir/app.weft"
unsupported_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_rejects_unsupported_version_token" "$unsupported_out" "error[E1001]: unknown function"

mkdir -p "$tmp_pkg_cli_dir/deps/math"
pkg_init_out=$(cd "$tmp_pkg_cli_dir" && "$WEFT_ABS" pkg init cli_app 2>&1)
assert_contains "pkg_init_writes_manifest" "$pkg_init_out" "pkg: wrote weft.pkg"
pkg_manifest=$(< "$tmp_pkg_cli_dir/weft.pkg")
assert_contains "pkg_init_manifest_package" "$pkg_manifest" '"package":"cli_app"'
assert_contains "pkg_init_manifest_schema_version" "$pkg_manifest" '"manifest_version":1'
assert_contains "pkg_init_manifest_package_version" "$pkg_manifest" '"version":"0.1.0"'
assert_contains "pkg_init_manifest_weft_version" "$pkg_manifest" '"weft":"0.1"'

printf 'occupied-add-temp\n' > "$tmp_pkg_cli_dir/weft.pkg.weft-tmp-0"
pkg_add_out=$(cd "$tmp_pkg_cli_dir" && "$WEFT_ABS" pkg add math deps/math 2>&1)
assert_contains "pkg_add_records_dependency" "$pkg_add_out" "pkg: added dependency"
pkg_manifest=$(< "$tmp_pkg_cli_dir/weft.pkg")
assert_contains "pkg_add_manifest_dep" "$pkg_manifest" '"math":"deps/math"'
assert_equals "pkg_add_preserves_occupied_atomic_temp" "$(< "$tmp_pkg_cli_dir/weft.pkg.weft-tmp-0")" "occupied-add-temp"
if [ -e "$tmp_pkg_cli_dir/weft.pkg.weft-tmp-1" ]; then
  echo "  fail pkg_add_atomic_replace_cleans_selected_temp"
  exit 1
else
  echo "  ok pkg_add_atomic_replace_cleans_selected_temp"
fi
printf 'pub fn add(a: i64, b: i64) -> i64 { a + b }\n' > "$tmp_pkg_cli_dir/deps/math/lib.weft"
printf 'use math/lib.{*}\nfn main() -> i64 { if add(40, 2) == 42 { 0 } else { 1 } }\n' > "$tmp_pkg_cli_dir/app.weft"
(cd "$tmp_pkg_cli_dir" && run_weft_compile_guarded "$WEFT_ABS" < app.weft > app 2>"$tmp_err")
chmod +x "$tmp_pkg_cli_dir/app"
run_binary_guarded "$tmp_pkg_cli_dir/app"
echo "  ok pkg_add_dependency_compiles"

if duplicate_out=$(cd "$tmp_pkg_cli_dir" && "$WEFT_ABS" pkg add math deps/other 2>&1); then
  echo "  fail pkg_add_rejects_duplicate"
  exit 1
else
  assert_contains "pkg_add_rejects_duplicate" "$duplicate_out" "pkg: invalid or duplicate dependency"
fi

if traversal_add_out=$(cd "$tmp_pkg_cli_dir" && "$WEFT_ABS" pkg add evil ../outside 2>&1); then
  echo "  fail pkg_add_rejects_traversal_path"
  exit 1
else
  assert_contains "pkg_add_rejects_traversal_path" "$traversal_add_out" "pkg: invalid or duplicate dependency"
fi

if missing_add_out=$(cd "$tmp_pkg_missing_dir" && "$WEFT_ABS" pkg add math deps/math 2>&1); then
  echo "  fail pkg_add_requires_manifest"
  exit 1
else
  assert_contains "pkg_add_requires_manifest" "$missing_add_out" "pkg: missing weft.pkg"
fi

if bad_init_out=$(cd "$tmp_pkg_missing_dir" && "$WEFT_ABS" pkg init bad.name 2>&1); then
  echo "  fail pkg_init_rejects_invalid_name"
  exit 1
else
  assert_contains "pkg_init_rejects_invalid_name" "$bad_init_out" "pkg: invalid package name"
fi

: > "$tmp_pkg_missing_dir/weft.pkg"
if empty_init_out=$(cd "$tmp_pkg_missing_dir" && "$WEFT_ABS" pkg init app 2>&1); then
  echo "  fail pkg_init_create_new_rejects_empty_existing_manifest"
  exit 1
else
  assert_contains "pkg_init_create_new_rejects_empty_existing_manifest" "$empty_init_out" "pkg: could not write weft.pkg"
fi
assert_equals "pkg_init_create_new_preserves_empty_existing_manifest" "$(wc -c < "$tmp_pkg_missing_dir/weft.pkg" | tr -d ' ')" "0"

printf '\377' > "$tmp_pkg_missing_dir/weft.pkg"
if (cd "$tmp_pkg_missing_dir" && "$WEFT_ABS" pkg add math deps/math >/dev/null 2>&1); then
  echo "  fail pkg_add_rejects_non_utf8_manifest"
  exit 1
else
  echo "  ok pkg_add_rejects_non_utf8_manifest"
fi
if (cd "$tmp_pkg_missing_dir" && "$WEFT_ABS" pkg exports >/dev/null 2>&1); then
  echo "  fail pkg_exports_rejects_non_utf8_manifest"
  exit 1
else
  echo "  ok pkg_exports_rejects_non_utf8_manifest"
fi
assert_equals "pkg_non_utf8_manifest_is_preserved" "$(od -An -tu1 "$tmp_pkg_missing_dir/weft.pkg" | tr -d ' ')" "255"

mkdir -p "$tmp_pkg_lock_dir/deps/lib/deps/base" "$tmp_pkg_lock_dir/.weft/cache"
printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"lib":"deps/lib"}}\n' > "$tmp_pkg_lock_dir/weft.pkg"
printf 'fn main() -> i64 { 0 }\n' > "$tmp_pkg_lock_dir/main.weft"
printf '{"package":"lib","manifest_version":1,"version":"2.0.0","weft":"0.1","dependencies":{"base":"deps/base"}}\n' > "$tmp_pkg_lock_dir/deps/lib/weft.pkg"
printf 'pub fn lib_value() -> i64 { 2 }\n' > "$tmp_pkg_lock_dir/deps/lib/lib.weft"
printf 'use lib/lib.{lib_value}\nfn main() -> i64 { lib_value() }\n' > "$tmp_pkg_lock_dir/app.weft"
printf '{"package":"base","manifest_version":1,"version":"3.0.0","weft":"0.1","dependencies":{}}\n' > "$tmp_pkg_lock_dir/deps/lib/deps/base/weft.pkg"
printf 'pub fn base_value() -> i64 { 3 }\n' > "$tmp_pkg_lock_dir/deps/lib/deps/base/base.weft"
printf 'ignored cache source\n' > "$tmp_pkg_lock_dir/.weft/cache/shadow.weft"

printf 'occupied-lock-temp\n' > "$tmp_pkg_lock_dir/weft.lock.weft-tmp-0"
pkg_lock_out=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock 2>&1)
assert_contains "pkg_lock_reports_write" "$pkg_lock_out" "pkg: wrote weft.lock"
pkg_lock_first=$(< "$tmp_pkg_lock_dir/weft.lock")
assert_contains "pkg_lock_pins_lock_schema" "$pkg_lock_first" '"lock_version":1'
assert_contains "pkg_lock_pins_manifest_schema" "$pkg_lock_first" '"manifest_version":1'
assert_contains "pkg_lock_records_root_identity" "$pkg_lock_first" '"name":"app","version":"1.0.0","source":"path:."'
assert_contains "pkg_lock_records_transitive_identity" "$pkg_lock_first" '"name":"base","version":"3.0.0","source":"path:deps/lib/deps/base"'
assert_contains "pkg_lock_sorts_package_entries" "$pkg_lock_first" '"name":"lib","version":"2.0.0","source":"path:deps/lib"'
assert_contains "pkg_lock_records_sha256_content" "$(pkg_lock_digest "$pkg_lock_first" app)" 'sha256:'
assert_equals "pkg_lock_preserves_occupied_atomic_temp" "$(< "$tmp_pkg_lock_dir/weft.lock.weft-tmp-0")" "occupied-lock-temp"
if [ -e "$tmp_pkg_lock_dir/weft.lock.weft-tmp-1" ] || [ -e "$tmp_pkg_lock_dir/weft.lock.tmp" ]; then
  echo "  fail pkg_lock_atomic_replace_cleans_temp"
  exit 1
else
  echo "  ok pkg_lock_atomic_replace_cleans_temp"
fi
rm -f "$tmp_pkg_lock_dir/weft.lock.weft-tmp-0"

# Package identity hashes arbitrary source bytes through FileRead/Bytes. NUL
# and malformed UTF-8 are content here, never a pointer-shaped text surrogate.
printf '\000\377\200A' > "$tmp_pkg_lock_dir/raw_bytes.weft"
pkg_lock_binary_out=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock 2>&1)
assert_contains "pkg_lock_accepts_binary_source_bytes" "$pkg_lock_binary_out" "pkg: wrote weft.lock"
pkg_lock_binary_first=$(< "$tmp_pkg_lock_dir/weft.lock")
assert_not_equals "pkg_lock_binary_source_changes_digest" "$(pkg_lock_digest "$pkg_lock_binary_first" app)" "$(pkg_lock_digest "$pkg_lock_first" app)"
(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock >/dev/null)
assert_equals "pkg_lock_binary_source_is_deterministic" "$(< "$tmp_pkg_lock_dir/weft.lock")" "$pkg_lock_binary_first"
rm -f "$tmp_pkg_lock_dir/raw_bytes.weft"
(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock >/dev/null)
assert_equals "pkg_lock_binary_source_removal_restores_digest" "$(pkg_lock_digest "$(< "$tmp_pkg_lock_dir/weft.lock")" app)" "$(pkg_lock_digest "$pkg_lock_first" app)"

pkg_locked_check=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" check < app.weft 2>&1)
assert_contains "package_valid_lock_identity_compiles" "$pkg_locked_check" "check: 2 functions, 0 errors"

printf '{"lock_version":2,"manifest_version":1,"weft":"0.1","packages":[]}\n' > "$tmp_pkg_lock_dir/weft.lock"
pkg_malformed_lock_out=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_malformed_lock_stable_code" "$pkg_malformed_lock_out" "error[E5005]: dependency 'lib' is blocked by a malformed or unsupported package lock"

printf '{"lock_version":1,"manifest_version":1,"weft":"0.1","packages":[{"name":"app","version":"1.0.0","source":"path:.","content":"sha256:0000000000000000000000000000000000000000000000000000000000000000"}]}\n' > "$tmp_pkg_lock_dir/weft.lock"
pkg_missing_lock_entry_out=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_missing_lock_entry_stable_code" "$pkg_missing_lock_entry_out" "error[E5006]: dependency 'lib' does not match the identity recorded in weft.lock"

printf '{"lock_version":1,"manifest_version":1,"weft":"0.1","packages":[{"name":"app","version":"1.0.0","source":"path:.","content":"sha256:0000000000000000000000000000000000000000000000000000000000000000"},{"name":"lib","version":"9.0.0","source":"path:deps/lib","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}]}\n' > "$tmp_pkg_lock_dir/weft.lock"
pkg_wrong_lock_version_out=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_wrong_lock_version_stable_code" "$pkg_wrong_lock_version_out" "error[E5006]: dependency 'lib' does not match the identity recorded in weft.lock"

printf '%s\n' "$pkg_lock_first" > "$tmp_pkg_lock_dir/weft.lock"

(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock >/dev/null)
assert_equals "pkg_lock_rerun_is_byte_deterministic" "$(< "$tmp_pkg_lock_dir/weft.lock")" "$pkg_lock_first"

printf 'not package content\n' > "$tmp_pkg_lock_dir/README.md"
printf 'changed ignored cache source\n' > "$tmp_pkg_lock_dir/.weft/cache/shadow.weft"
(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock >/dev/null)
assert_equals "pkg_lock_ignores_non_source_and_cache_files" "$(< "$tmp_pkg_lock_dir/weft.lock")" "$pkg_lock_first"

printf 'fn escaped() -> i64 { 99 }\n' > "$tmp_outside_dir/escaped.weft"
ln -s "$tmp_outside_dir" "$tmp_pkg_lock_dir/outside_link"
(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock >/dev/null)
assert_equals "pkg_lock_does_not_follow_source_symlinks" "$(< "$tmp_pkg_lock_dir/weft.lock")" "$pkg_lock_first"

app_before=$(pkg_lock_digest "$pkg_lock_first" app)
lib_before=$(pkg_lock_digest "$pkg_lock_first" lib)
base_before=$(pkg_lock_digest "$pkg_lock_first" base)
printf 'pub fn base_value() -> i64 { 30 }\n' > "$tmp_pkg_lock_dir/deps/lib/deps/base/base.weft"
(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock >/dev/null)
pkg_lock_base_changed=$(< "$tmp_pkg_lock_dir/weft.lock")
assert_equals "pkg_lock_dependency_change_does_not_rehash_root" "$(pkg_lock_digest "$pkg_lock_base_changed" app)" "$app_before"
assert_equals "pkg_lock_nested_dependency_change_does_not_rehash_owner" "$(pkg_lock_digest "$pkg_lock_base_changed" lib)" "$lib_before"
assert_not_equals "pkg_lock_source_change_rehashes_own_package" "$(pkg_lock_digest "$pkg_lock_base_changed" base)" "$base_before"

printf 'fn main() -> i64 { 1 }\n' > "$tmp_pkg_lock_dir/main.weft"
(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock >/dev/null)
pkg_lock_root_changed=$(< "$tmp_pkg_lock_dir/weft.lock")
assert_not_equals "pkg_lock_root_source_change_rehashes_root" "$(pkg_lock_digest "$pkg_lock_root_changed" app)" "$app_before"
assert_equals "pkg_lock_root_change_preserves_dependency_digest" "$(pkg_lock_digest "$pkg_lock_root_changed" lib)" "$lib_before"

printf '{"package":"app","dependencies":{"wrong":"deps/lib"}}\n' > "$tmp_pkg_lock_dir/weft.pkg"
if pkg_lock_mismatch=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock 2>&1); then
  echo "  fail pkg_lock_rejects_dependency_name_mismatch"
  exit 1
else
  assert_contains "pkg_lock_rejects_dependency_name_mismatch" "$pkg_lock_mismatch" "pkg: dependency key does not match package name"
fi

mkdir -p "$tmp_pkg_lock_dir/deps/lib/deps/app"
printf '{"package":"app","dependencies":{"lib":"deps/lib"}}\n' > "$tmp_pkg_lock_dir/weft.pkg"
printf '{"package":"lib","dependencies":{"app":"deps/app"}}\n' > "$tmp_pkg_lock_dir/deps/lib/weft.pkg"
printf '{"package":"app","dependencies":{}}\n' > "$tmp_pkg_lock_dir/deps/lib/deps/app/weft.pkg"
if pkg_lock_cycle=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock 2>&1); then
  echo "  fail pkg_lock_rejects_dependency_cycle"
  exit 1
else
  assert_contains "pkg_lock_rejects_dependency_cycle" "$pkg_lock_cycle" "pkg: package dependency cycle"
fi

mkdir -p "$tmp_pkg_lock_dir/deps/left/deps/common" "$tmp_pkg_lock_dir/deps/right/deps/common"
printf '{"package":"app","dependencies":{"left":"deps/left","right":"deps/right"}}\n' > "$tmp_pkg_lock_dir/weft.pkg"
printf '{"package":"left","dependencies":{"common":"deps/common"}}\n' > "$tmp_pkg_lock_dir/deps/left/weft.pkg"
printf '{"package":"right","dependencies":{"common":"deps/common"}}\n' > "$tmp_pkg_lock_dir/deps/right/weft.pkg"
printf '{"package":"common","version":"1.0.0","dependencies":{}}\n' > "$tmp_pkg_lock_dir/deps/left/deps/common/weft.pkg"
printf '{"package":"common","version":"1.0.0","dependencies":{}}\n' > "$tmp_pkg_lock_dir/deps/right/deps/common/weft.pkg"
printf 'pub fn value() -> i64 { 1 }\n' > "$tmp_pkg_lock_dir/deps/left/deps/common/value.weft"
printf 'pub fn value() -> i64 { 2 }\n' > "$tmp_pkg_lock_dir/deps/right/deps/common/value.weft"
if pkg_lock_conflict=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock 2>&1); then
  echo "  fail pkg_lock_rejects_content_identity_conflict"
  exit 1
else
  assert_contains "pkg_lock_rejects_content_identity_conflict" "$pkg_lock_conflict" "pkg: package identity conflict in dependency graph"
fi

printf '{"package":' > "$tmp_pkg_lock_dir/weft.pkg"
if pkg_lock_malformed=$(cd "$tmp_pkg_lock_dir" && "$WEFT_ABS" pkg lock 2>&1); then
  echo "  fail pkg_lock_rejects_malformed_root_manifest"
  exit 1
else
  assert_contains "pkg_lock_rejects_malformed_root_manifest" "$pkg_lock_malformed" "pkg: malformed or missing package manifest"
fi

# Root authority and dependency declaration must compose over the exact locked
# package identity. Neither half is independently sufficient.
mkdir -p "$tmp_pkg_trust_dir/direct/deps/dep/native"
printf 'use dep/native/raw.{*}\nfn main() -> i64 { 0 }\n' > "$tmp_pkg_trust_dir/direct/main.weft"
printf 'pub fn raw_probe(p: i64) -> i64 { __mem_load64(p) }\n' > "$tmp_pkg_trust_dir/direct/deps/dep/native/raw.weft"
printf '{"package":"dep","manifest_version":1,"version":"2.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["native/raw"]}\n' > "$tmp_pkg_trust_dir/direct/deps/dep/weft.pkg"
printf '{"lock_version":1,"manifest_version":1,"weft":"0.1","packages":[{"name":"app","version":"1.0.0","source":"path:.","content":"sha256:0000000000000000000000000000000000000000000000000000000000000000"},{"name":"dep","version":"2.0.0","source":"path:deps/dep","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}]}\n' > "$tmp_pkg_trust_dir/direct/weft.lock"

printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"dep":"deps/dep"},"trust":{"dep":{"version":"2.0.0","source":"path:deps/dep","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111","modules":["native/raw"]}}}\n' > "$tmp_pkg_trust_dir/direct/weft.pkg"
pkg_trust_exact=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1)
assert_contains "package_binding_exact_locked_grant_compiles" "$pkg_trust_exact" "check: 2 functions, 0 errors"

printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"dep":"deps/dep"},"trust":{"dep":{"version":"9.0.0","source":"path:deps/dep","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111","modules":["native/raw"]}}}\n' > "$tmp_pkg_trust_dir/direct/weft.pkg"
pkg_trust_wrong_version=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_rejects_wrong_grant_version" "$pkg_trust_wrong_version" "error[E5008]: binding module 'native/raw' in package 'dep' lacks an exact root trust grant"

printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"dep":"deps/dep"},"trust":{"dep":{"version":"2.0.0","source":"path:vendor/dep","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111","modules":["native/raw"]}}}\n' > "$tmp_pkg_trust_dir/direct/weft.pkg"
pkg_trust_wrong_source=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_rejects_wrong_grant_source" "$pkg_trust_wrong_source" "error[E5008]: binding module 'native/raw' in package 'dep' lacks an exact root trust grant"

printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"dep":"deps/dep"},"trust":{"dep":{"version":"2.0.0","source":"path:deps/dep","content":"sha256:2222222222222222222222222222222222222222222222222222222222222222","modules":["native/raw"]}}}\n' > "$tmp_pkg_trust_dir/direct/weft.pkg"
pkg_trust_wrong_content=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_rejects_wrong_grant_content" "$pkg_trust_wrong_content" "error[E5008]: binding module 'native/raw' in package 'dep' lacks an exact root trust grant"

printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"dep":"deps/dep"},"trust":{"dep":{"version":"2.0.0","source":"path:deps/dep","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111","modules":["native/other"]}}}\n' > "$tmp_pkg_trust_dir/direct/weft.pkg"
pkg_trust_wrong_module=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_rejects_wrong_grant_module" "$pkg_trust_wrong_module" "error[E5008]: binding module 'native/raw' in package 'dep' lacks an exact root trust grant"

printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"dep":"deps/dep"}}\n' > "$tmp_pkg_trust_dir/direct/weft.pkg"
pkg_trust_missing_grant=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_rejects_missing_root_grant" "$pkg_trust_missing_grant" "error[E5008]: binding module 'native/raw' in package 'dep' lacks an exact root trust grant"

printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"dep":"deps/dep"},"trust":{"dep":{"version":"2.0.0","source":"path:deps/dep","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111","modules":["native/raw"]}}}\n' > "$tmp_pkg_trust_dir/direct/weft.pkg"
printf '{"package":"dep","manifest_version":1,"version":"2.0.0","weft":"0.1","dependencies":{}}\n' > "$tmp_pkg_trust_dir/direct/deps/dep/weft.pkg"
pkg_trust_missing_declaration=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_rejects_missing_dependency_declaration" "$pkg_trust_missing_declaration" "error[E5008]: binding module 'native/raw' in package 'dep' lacks an exact root trust grant"

printf '{"package":"dep","manifest_version":1,"version":"2.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["native/raw"]}\n' > "$tmp_pkg_trust_dir/direct/deps/dep/weft.pkg"
mv "$tmp_pkg_trust_dir/direct/weft.lock" "$tmp_pkg_trust_dir/direct/weft.lock.saved"
pkg_trust_unlocked=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_rejects_unlocked_dependency" "$pkg_trust_unlocked" "error[E5008]: binding module 'native/raw' in package 'dep' lacks an exact root trust grant"
mv "$tmp_pkg_trust_dir/direct/weft.lock.saved" "$tmp_pkg_trust_dir/direct/weft.lock"

printf '{"package":"dep","manifest_version":1,"version":"2.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["native/raw"],"trust":{"other":{"version":"1.0.0","source":"path:deps/other","content":"sha256:3333333333333333333333333333333333333333333333333333333333333333","modules":["native/raw"]}}}\n' > "$tmp_pkg_trust_dir/direct/deps/dep/weft.pkg"
pkg_trust_dependency_grant=$(cd "$tmp_pkg_trust_dir/direct" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_rejects_dependency_grant" "$pkg_trust_dependency_grant" "error[E5007]: dependency 'dep' attempts to grant package trust from a dependency manifest"

# A root may authorize its own binding without a circular content hash.
mkdir -p "$tmp_pkg_trust_dir/root_owned/native"
printf '{"package":"app","trusted_bindings":["native/raw"]}\n' > "$tmp_pkg_trust_dir/root_owned/weft.pkg"
printf 'use native/raw.{*}\nfn main() -> i64 { 0 }\n' > "$tmp_pkg_trust_dir/root_owned/main.weft"
printf 'pub fn raw_probe(p: i64) -> i64 { __mem_load64(p) }\n' > "$tmp_pkg_trust_dir/root_owned/native/raw.weft"
pkg_trust_root_owned=$(cd "$tmp_pkg_trust_dir/root_owned" && "$WEFT_ABS" check main.weft 2>&1)
assert_contains "package_root_owned_binding_compiles" "$pkg_trust_root_owned" "check: 2 functions, 0 errors"

# Manifest-native declarations are synthesized only inside the exact trusted
# leaf. The checker consumes their typed ABI fact and charges Unsafe without
# adding source syntax or exposing the raw symbol through module imports.
mkdir -p "$tmp_pkg_trust_dir/native_typed/deps/dep/native"
printf 'use dep/native/raw as raw\nfn main() -> i64 { 0 }\n' > "$tmp_pkg_trust_dir/native_typed/main.weft"
printf 'fn raw_probe(value: i64) -[Unsafe]> i64 { native_abs(value) }\n' > "$tmp_pkg_trust_dir/native_typed/deps/dep/native/raw.weft"
printf '%s\n' '{"package":"dep","manifest_version":1,"version":"2.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["native/raw"],"native_bindings":{"native/raw":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"system","kind":"system","link":"System","search":["toolchain"],"content":"toolchain","optional":false}],"symbols":[{"declaration":"native_abs","symbol":"labs","library":"system","params":["i64"],"result":"i64","optional":false}]}}}}}' > "$tmp_pkg_trust_dir/native_typed/deps/dep/weft.pkg"
printf '%s\n' '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"dep":"deps/dep"},"trust":{"dep":{"version":"2.0.0","source":"path:deps/dep","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111","modules":["native/raw"]}}}' > "$tmp_pkg_trust_dir/native_typed/weft.pkg"
printf '%s\n' '{"lock_version":1,"manifest_version":1,"weft":"0.1","packages":[{"name":"app","version":"1.0.0","source":"path:.","content":"sha256:0000000000000000000000000000000000000000000000000000000000000000"},{"name":"dep","version":"2.0.0","source":"path:deps/dep","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}]}' > "$tmp_pkg_trust_dir/native_typed/weft.lock"
pkg_native_typed=$(cd "$tmp_pkg_trust_dir/native_typed" && "$WEFT_ABS" check main.weft 2>&1)
assert_contains "package_native_manifest_symbol_checks_in_exact_binding" "$pkg_native_typed" "0 errors"

printf 'fn raw_probe(value: i64) -> i64 { native_abs(value) }\n' > "$tmp_pkg_trust_dir/native_typed/deps/dep/native/raw.weft"
pkg_native_unsafe_required=$(cd "$tmp_pkg_trust_dir/native_typed" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_native_manifest_symbol_requires_unsafe" "$pkg_native_unsafe_required" "error[E2001]"
printf 'fn raw_probe(value: i64) -[Unsafe]> i64 { native_abs(value) }\n' > "$tmp_pkg_trust_dir/native_typed/deps/dep/native/raw.weft"

printf 'use dep/native/raw.{native_abs}\nfn main() -> i64 { native_abs(1) }\n' > "$tmp_pkg_trust_dir/native_typed/main.weft"
pkg_native_private=$(cd "$tmp_pkg_trust_dir/native_typed" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_native_manifest_symbol_is_private" "$pkg_native_private" "error[E4004]"

printf 'use dep/native/raw as raw\nfn main() -> i64 { 0 }\n' > "$tmp_pkg_trust_dir/native_typed/main.weft"
printf '%s\n' '{"package":"dep","manifest_version":1,"version":"2.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["native/raw"],"native_bindings":{"native/raw":{"abi_version":1,"targets":{"linux-aarch64":{"libraries":[{"id":"system","kind":"system","link":"c","search":["toolchain"],"content":"toolchain","optional":false}],"symbols":[{"declaration":"native_abs","symbol":"labs","library":"system","params":["i64"],"result":"i64","optional":false}]}}}}}' > "$tmp_pkg_trust_dir/native_typed/deps/dep/weft.pkg"
pkg_native_wrong_target=$(cd "$tmp_pkg_trust_dir/native_typed" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_native_binding_rejects_target_substitution" "$pkg_native_wrong_target" "error[E5010]: native binding 'native/raw' has no declaration for compilation target 'macos-aarch64'"

# A root-owned binding follows the same typed producer as imports and lowers
# only called symbols into the object's undefined-symbol/relocation plan. The
# linked program crosses integer, f32, f64 and mixed GPR/FP Darwin ABI lanes.
mkdir -p "$tmp_pkg_trust_dir/native_linked"
printf '%s\n' '{"package":"native-smoke","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"system","kind":"system","link":"System","search":["toolchain"],"content":"toolchain","optional":false}],"symbols":[{"declaration":"native_abs","symbol":"labs","library":"system","params":["i64"],"result":"i64","optional":false},{"declaration":"native_fabs","symbol":"fabs","library":"system","params":["f64"],"result":"f64","optional":false},{"declaration":"native_roundf","symbol":"roundf","library":"system","params":["f32"],"result":"f32","optional":false},{"declaration":"native_ldexp","symbol":"ldexp","library":"system","params":["f64","i32"],"result":"f64","optional":false},{"declaration":"native_jn","symbol":"jn","library":"system","params":["i32","f64"],"result":"f64","optional":false},{"declaration":"native_unused","symbol":"weft_symbol_intentionally_absent","library":"system","params":[],"result":"nil","optional":true}]}}}}}' > "$tmp_pkg_trust_dir/native_linked/weft.pkg"
printf '%s\n' \
  'fn main() -[Unsafe]> i64 {' \
  '  let rounded32: f32 = native_roundf(41.6)' \
  '  let checked64 = __f64_to_i64_trunc(native_fabs(0.0 - 42.75))' \
  '  let fp_then_gpr = __f64_to_i64_trunc(native_ldexp(10.5, 2))' \
  '  let gpr_then_fp = __f64_to_i64_trunc(native_jn(0, 0.0))' \
  '  if checked64 == 42 {' \
  '    if fp_then_gpr == 42 {' \
  '      if gpr_then_fp == 1 {' \
  '        native_abs(0 - __f64_to_i64_trunc(__f32_to_f64(rounded32)))' \
  '      } else { 2 }' \
  '    } else { 3 }' \
  '  } else { 1 }' \
  '}' > "$tmp_pkg_trust_dir/native_linked/main.weft"
(cd "$tmp_pkg_trust_dir/native_linked" && run_weft_compile_guarded "$WEFT_ABS" compile main.weft) > "$tmp_pkg_trust_dir/native_linked/native.o"
(cd "$tmp_pkg_trust_dir/native_linked" && run_weft_compile_guarded "$WEFT_ABS" compile main.weft) > "$tmp_pkg_trust_dir/native_linked/native_second.o"
if cmp -s "$tmp_pkg_trust_dir/native_linked/native.o" "$tmp_pkg_trust_dir/native_linked/native_second.o"; then
  echo "  ok package_native_object_is_deterministic"
else
  echo "  fail package_native_object_is_deterministic"
  exit 1
fi
native_undefined=$(nm -u "$tmp_pkg_trust_dir/native_linked/native.o")
assert_contains "package_native_object_emits_integer_symbol" "$native_undefined" "_labs"
assert_contains "package_native_object_emits_f32_symbol" "$native_undefined" "_roundf"
assert_contains "package_native_object_emits_mixed_fp_gpr_symbol" "$native_undefined" "_ldexp"
assert_contains "package_native_object_emits_mixed_gpr_fp_symbol" "$native_undefined" "_jn"
assert_not_contains "package_native_object_omits_unused_optional_symbol" "$native_undefined" "_weft_symbol_intentionally_absent"
native_link_options=$(otool -l "$tmp_pkg_trust_dir/native_linked/native.o")
assert_contains "package_native_object_autolinks_used_system_library" "$native_link_options" "string #1 -lSystem"
assert_not_contains "package_native_object_does_not_autolink_unused_optional_symbol" "$native_link_options" "weft_symbol_intentionally_absent"
/usr/bin/ld -o "$tmp_pkg_trust_dir/native_linked/native" "$tmp_pkg_trust_dir/native_linked/native.o" \
  -syslibroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
  -e _main -arch arm64 -platform_version macos 11.0 15.0 2>/dev/null
codesign -s - "$tmp_pkg_trust_dir/native_linked/native" >/dev/null
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_linked/native"
pkg_native_linked_exit=$?
set -e
assert_equals "package_native_manifest_call_links_and_runs" "$pkg_native_linked_exit" "42"

# Package archives and dynamic libraries are selected by manifest order and
# exact package-relative path, hashed before object output, then handed to the
# finalizer as those exact paths. A mismatched first candidate must not fall
# through to a same-named artifact later in the search list.
mkdir -p \
  "$tmp_pkg_trust_dir/native_artifacts/native/archive_first" \
  "$tmp_pkg_trust_dir/native_artifacts/native/archive_second" \
  "$tmp_pkg_trust_dir/native_artifacts/native/dynamic" \
  "$tmp_pkg_trust_dir/native_artifacts/native/dynamic_closure" \
  "$tmp_pkg_trust_dir/native_artifacts/native/dynamic_wrong_arch"
printf '%s\n' 'long weft_archive_value(void) { return 40; }' > "$tmp_pkg_trust_dir/native_artifacts/archive_first.c"
printf '%s\n' 'long weft_archive_value(void) { return 99; }' > "$tmp_pkg_trust_dir/native_artifacts/archive_second.c"
printf '%s\n' 'long weft_dynamic_value(void) { return 2; }' > "$tmp_pkg_trust_dir/native_artifacts/dynamic.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/archive_first.c" -o "$tmp_pkg_trust_dir/native_artifacts/archive_first.o"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/archive_second.c" -o "$tmp_pkg_trust_dir/native_artifacts/archive_second.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_first/libweft_fixture.a" "$tmp_pkg_trust_dir/native_artifacts/archive_first.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_second/libweft_fixture.a" "$tmp_pkg_trust_dir/native_artifacts/archive_second.o"
/usr/bin/clang -dynamiclib \
  "$tmp_pkg_trust_dir/native_artifacts/dynamic.c" \
  -Wl,-install_name,"$tmp_pkg_trust_dir/native_artifacts/native/dynamic/libweft_fixture_dynamic.dylib" \
  -o "$tmp_pkg_trust_dir/native_artifacts/native/dynamic/libweft_fixture_dynamic.dylib"
codesign -s - "$tmp_pkg_trust_dir/native_artifacts/native/dynamic/libweft_fixture_dynamic.dylib" >/dev/null
native_archive_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_first/libweft_fixture.a")
native_archive_digest=${native_archive_digest_line%% *}
native_dynamic_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/dynamic/libweft_fixture_dynamic.dylib")
native_dynamic_digest=${native_dynamic_digest_line%% *}

# A dynamic-only product closes entirely through Weft's typed LinkGraph and
# Mach-O leaf. The foreign dylib is test input; clang/ld are not a final-link
# stage for the executable.
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"dynamic","kind":"dynamic","link":"weft_fixture_dynamic","search":["native/dynamic"],"content":"sha256:'"$native_dynamic_digest"'","optional":false}],"symbols":[{"declaration":"native_dynamic_value","symbol":"weft_dynamic_value","library":"dynamic","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_dynamic_value() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_dynamic_only)
codesign --verify "$tmp_pkg_trust_dir/native_artifacts/native_dynamic_only"
native_dynamic_only_dependencies=$(otool -L "$tmp_pkg_trust_dir/native_artifacts/native_dynamic_only")
assert_contains "package_native_dynamic_build_records_exact_artifact" "$native_dynamic_only_dependencies" "$tmp_pkg_trust_dir/native_artifacts/native/dynamic/libweft_fixture_dynamic.dylib"
assert_contains "package_native_dynamic_build_keeps_system_abi" "$native_dynamic_only_dependencies" "/usr/lib/libSystem.B.dylib"
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_dynamic_only"
pkg_native_dynamic_only_exit=$?
set -e
assert_equals "package_native_dynamic_build_links_and_runs" "$pkg_native_dynamic_only_exit" "2"

printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"missing","kind":"dynamic","link":"weft_missing_dynamic","search":["native/dynamic_missing"],"content":"sha256:0000000000000000000000000000000000000000000000000000000000000000","optional":false}],"symbols":[{"declaration":"native_dynamic_value","symbol":"weft_dynamic_value","library":"missing","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
set +e
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_missing_dynamic) \
  > "$tmp_pkg_trust_dir/native_artifacts/native_missing_dynamic.stdout" \
  2> "$tmp_pkg_trust_dir/native_artifacts/native_missing_dynamic.err"
pkg_native_missing_dynamic_exit=$?
set -e
assert_equals "package_native_dynamic_missing_fails" "$pkg_native_missing_dynamic_exit" "1"
assert_contains "package_native_dynamic_missing_is_explicit" "$(<"$tmp_pkg_trust_dir/native_artifacts/native_missing_dynamic.err")" "is unavailable in its declared search paths"
if [ ! -e "$tmp_pkg_trust_dir/native_artifacts/native_missing_dynamic" ]; then
  echo "  ok package_native_dynamic_missing_commits_no_output"
else
  echo "  fail package_native_dynamic_missing_commits_no_output"
  exit 1
fi

native_wrong_arch_path="$tmp_pkg_trust_dir/native_artifacts/native/dynamic_wrong_arch/libweft_wrong_arch.dylib"
/usr/bin/clang -arch x86_64 -dynamiclib \
  "$tmp_pkg_trust_dir/native_artifacts/dynamic.c" \
  -Wl,-install_name,"$native_wrong_arch_path" \
  -o "$native_wrong_arch_path"
codesign -s - "$native_wrong_arch_path" >/dev/null
assert_contains "package_native_dynamic_wrong_arch_fixture_is_x86_64" "$(/usr/bin/file -b "$native_wrong_arch_path")" "x86_64"
native_wrong_arch_digest_line=$(/usr/bin/shasum -a 256 "$native_wrong_arch_path")
native_wrong_arch_digest=${native_wrong_arch_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"wrong","kind":"dynamic","link":"weft_wrong_arch","search":["native/dynamic_wrong_arch"],"content":"sha256:'"$native_wrong_arch_digest"'","optional":false}],"symbols":[{"declaration":"native_dynamic_value","symbol":"weft_dynamic_value","library":"wrong","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
set +e
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_wrong_arch) \
  > "$tmp_pkg_trust_dir/native_artifacts/native_wrong_arch.stdout" \
  2> "$tmp_pkg_trust_dir/native_artifacts/native_wrong_arch.err"
pkg_native_wrong_arch_exit=$?
set -e
assert_equals "package_native_dynamic_wrong_arch_fails" "$pkg_native_wrong_arch_exit" "1"
assert_contains "package_native_dynamic_wrong_arch_is_explicit" "$(<"$tmp_pkg_trust_dir/native_artifacts/native_wrong_arch.err")" "has no valid aarch64 Mach-O install identity"
if [ ! -e "$tmp_pkg_trust_dir/native_artifacts/native_wrong_arch" ]; then
  echo "  ok package_native_dynamic_wrong_arch_commits_no_output"
else
  echo "  fail package_native_dynamic_wrong_arch_commits_no_output"
  exit 1
fi

# The actual Mach-O load commands define deployment closure. A direct owner is
# insufficient when its locked image names another dylib: that identity must be
# satisfied by another hash-verified manifest declaration, which is selected
# transitively even when no Weft declaration directly calls it.
printf '%s\n' 'long weft_transitive_dependency(void) { return 40; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/transitive_dependency.c"
printf '%s\n' \
  'extern long weft_transitive_dependency(void);' \
  'long weft_transitive_owner(void) { return weft_transitive_dependency() + 2; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/transitive_owner.c"
native_transitive_dependency_path="$tmp_pkg_trust_dir/native_artifacts/native/dynamic_closure/libweft_transitive_dependency.dylib"
native_transitive_owner_path="$tmp_pkg_trust_dir/native_artifacts/native/dynamic_closure/libweft_transitive_owner.dylib"
/usr/bin/clang -dynamiclib \
  "$tmp_pkg_trust_dir/native_artifacts/transitive_dependency.c" \
  -Wl,-install_name,"$native_transitive_dependency_path" \
  -o "$native_transitive_dependency_path"
/usr/bin/clang -dynamiclib \
  "$tmp_pkg_trust_dir/native_artifacts/transitive_owner.c" \
  "$native_transitive_dependency_path" \
  -Wl,-install_name,"$native_transitive_owner_path" \
  -o "$native_transitive_owner_path"
codesign -s - "$native_transitive_dependency_path" >/dev/null
codesign -s - "$native_transitive_owner_path" >/dev/null
native_transitive_dependency_digest_line=$(/usr/bin/shasum -a 256 "$native_transitive_dependency_path")
native_transitive_dependency_digest=${native_transitive_dependency_digest_line%% *}
native_transitive_owner_digest_line=$(/usr/bin/shasum -a 256 "$native_transitive_owner_path")
native_transitive_owner_digest=${native_transitive_owner_digest_line%% *}

printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"owner","kind":"dynamic","link":"weft_transitive_owner","search":["native/dynamic_closure"],"content":"sha256:'"$native_transitive_owner_digest"'","optional":false}],"symbols":[{"declaration":"native_transitive_value","symbol":"weft_transitive_owner","library":"owner","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_transitive_value() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
set +e
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_transitive_undeclared) \
  > "$tmp_pkg_trust_dir/native_artifacts/native_transitive_undeclared.stdout" \
  2> "$tmp_pkg_trust_dir/native_artifacts/native_transitive_undeclared.err"
pkg_native_transitive_undeclared_exit=$?
set -e
assert_equals "package_native_dynamic_undeclared_transitive_fails" "$pkg_native_transitive_undeclared_exit" "1"
assert_contains "package_native_dynamic_undeclared_transitive_names_owner" "$(<"$tmp_pkg_trust_dir/native_artifacts/native_transitive_undeclared.err")" "$native_transitive_owner_path"
assert_contains "package_native_dynamic_undeclared_transitive_names_dependency" "$(<"$tmp_pkg_trust_dir/native_artifacts/native_transitive_undeclared.err")" "requires undeclared dynamic dependency '$native_transitive_dependency_path'"
if [ ! -e "$tmp_pkg_trust_dir/native_artifacts/native_transitive_undeclared" ]; then
  echo "  ok package_native_dynamic_undeclared_transitive_commits_no_output"
else
  echo "  fail package_native_dynamic_undeclared_transitive_commits_no_output"
  exit 1
fi

printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"owner","kind":"dynamic","link":"weft_transitive_owner","search":["native/dynamic_closure"],"content":"sha256:'"$native_transitive_owner_digest"'","license":"MIT","optional":false},{"id":"dependency","kind":"dynamic","link":"weft_transitive_dependency","search":["native/dynamic_closure"],"content":"sha256:'"$native_transitive_dependency_digest"'","license":"MIT","optional":false}],"symbols":[{"declaration":"native_transitive_value","symbol":"weft_transitive_owner","library":"owner","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_transitive --artifact-facts native_transitive.facts.json)
native_transitive_dependencies=$(otool -L "$tmp_pkg_trust_dir/native_artifacts/native_transitive")
assert_contains "package_native_dynamic_closure_records_owner" "$native_transitive_dependencies" "$native_transitive_owner_path"
assert_contains "package_native_dynamic_closure_records_dependency" "$native_transitive_dependencies" "$native_transitive_dependency_path"
native_transitive_facts=$(/bin/cat "$tmp_pkg_trust_dir/native_artifacts/native_transitive.facts.json")
assert_contains "package_native_dynamic_closure_facts_reject_standalone" "$native_transitive_facts" '"standalone":false'
assert_contains "package_native_dynamic_closure_facts_name_owner" "$native_transitive_facts" '"kind":"dynamic","identity":"'"$native_transitive_owner_path"'"'
assert_contains "package_native_dynamic_closure_facts_name_dependency" "$native_transitive_facts" '"kind":"dynamic","identity":"'"$native_transitive_dependency_path"'"'
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_transitive"
pkg_native_transitive_exit=$?
set -e
assert_equals "package_native_dynamic_transitive_closure_links_and_runs" "$pkg_native_transitive_exit" "42"

printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_fixture","search":["native/archive_first","native/archive_second"],"content":"sha256:'"$native_archive_digest"'","optional":false},{"id":"dynamic","kind":"dynamic","link":"weft_fixture_dynamic","search":["native/dynamic"],"content":"sha256:'"$native_dynamic_digest"'","optional":false}],"symbols":[{"declaration":"native_archive_value","symbol":"weft_archive_value","library":"archive","params":[],"result":"i64","optional":false},{"declaration":"native_dynamic_value","symbol":"weft_dynamic_value","library":"dynamic","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_archive_value() + native_dynamic_value() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_artifacts)
codesign --verify "$tmp_pkg_trust_dir/native_artifacts/native_artifacts"
native_artifact_dependencies=$(otool -L "$tmp_pkg_trust_dir/native_artifacts/native_artifacts")
assert_contains "package_native_build_records_exact_dynamic_artifact" "$native_artifact_dependencies" "$tmp_pkg_trust_dir/native_artifacts/native/dynamic/libweft_fixture_dynamic.dylib"
assert_not_contains "package_native_build_incorporates_selected_archive" "$native_artifact_dependencies" "libweft_fixture.a"
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_artifacts"
pkg_native_artifacts_exit=$?
set -e
assert_equals "package_native_archive_and_dynamic_link_and_run" "$pkg_native_artifacts_exit" "42"

# Static closure is a Weft linker operation. Member discovery reaches a fixed
# point in archive order, including cycles, and identical locked inputs yield
# identical final executables.
mkdir -p "$tmp_pkg_trust_dir/native_artifacts/native/archive_closure"
printf '%s\n' \
  'extern long weft_forward_b(void);' \
  'long weft_forward_a(void) { return weft_forward_b() + 1; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/forward_a.c"
printf '%s\n' 'long weft_forward_b(void) { return 41; }' > "$tmp_pkg_trust_dir/native_artifacts/forward_b.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/forward_a.c" -o "$tmp_pkg_trust_dir/native_artifacts/forward_a.o"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/forward_b.c" -o "$tmp_pkg_trust_dir/native_artifacts/forward_b.o"
native_forward_a_member_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/forward_a.o")
native_forward_a_member_digest=${native_forward_a_member_digest_line%% *}
native_forward_b_member_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/forward_b.o")
native_forward_b_member_digest=${native_forward_b_member_digest_line%% *}
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_closure/libweft_forward.a" \
  "$tmp_pkg_trust_dir/native_artifacts/forward_a.o" \
  "$tmp_pkg_trust_dir/native_artifacts/forward_b.o"
native_forward_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_closure/libweft_forward.a")
native_forward_digest=${native_forward_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_forward","search":["native/archive_closure"],"content":"sha256:'"$native_forward_digest"'","license":"MIT","optional":false}],"symbols":[{"declaration":"native_archive_value","symbol":"weft_forward_a","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_archive_value() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_forward --artifact-facts native_forward.facts.json)
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_forward_second)
if cmp -s "$tmp_pkg_trust_dir/native_artifacts/native_forward" "$tmp_pkg_trust_dir/native_artifacts/native_forward_second"; then
  echo "  ok package_native_archive_closure_is_deterministic"
else
  echo "  fail package_native_archive_closure_is_deterministic"
  exit 1
fi
native_forward_facts=$(/bin/cat "$tmp_pkg_trust_dir/native_artifacts/native_forward.facts.json")
assert_contains "package_native_artifact_facts_are_versioned" "$native_forward_facts" '"artifact_facts_version":2'
assert_contains "package_native_artifact_facts_name_target" "$native_forward_facts" '"target":"macos-aarch64"'
assert_contains "package_native_artifact_facts_name_minimum_platform" "$native_forward_facts" '"minimum_platform_abi":{"platform":"macos","major":11,"minor":0,"patch":0}'
assert_contains "package_native_artifact_facts_claim_standalone" "$native_forward_facts" '"standalone":true'
assert_contains "package_native_artifact_facts_name_system_abi" "$native_forward_facts" '"kind":"system","identity":"/usr/lib/libSystem.B.dylib"'
assert_contains "package_native_artifact_facts_name_archive_hash" "$native_forward_facts" '"content":"sha256:'"$native_forward_digest"'"'
assert_contains "package_native_artifact_facts_name_declared_license" "$native_forward_facts" '"license":"MIT"'
assert_contains "package_native_artifact_facts_name_first_member" "$native_forward_facts" '"name":"forward_a.o","content":"sha256:'"$native_forward_a_member_digest"'"'
assert_contains "package_native_artifact_facts_name_second_member" "$native_forward_facts" '"name":"forward_b.o","content":"sha256:'"$native_forward_b_member_digest"'"'
assert_contains "package_native_artifact_facts_name_entry_symbol" "$native_forward_facts" '"name":"weft_forward_a","definition":"strong"'
assert_contains "package_native_artifact_facts_name_provider_symbol" "$native_forward_facts" '"name":"weft_forward_b","definition":"strong"'
assert_contains "package_native_artifact_facts_name_root_trust" "$native_forward_facts" '"trust_grants":[{"package":"native-artifacts","version":"1.0.0","source":"path:.","content":"root","module":"main"}]'
assert_contains "package_native_artifact_facts_report_dwarf_function_line_information" "$native_forward_facts" '"debug_information":{"kind":"dwarf","version":"dwarf-v4-function-file-line"}'
assert_contains "package_native_artifact_facts_report_deterministic_ad_hoc_signing" "$native_forward_facts" '"signing":{"kind":"ad-hoc","identity":"weft","digest":"sha256","deterministic":true}'
native_forward_dependencies=$(otool -L "$tmp_pkg_trust_dir/native_artifacts/native_forward")
assert_not_contains "package_native_archive_closure_has_no_archive_runtime_dependency" "$native_forward_dependencies" "libweft_forward.a"
native_forward_load_commands=$(otool -l "$tmp_pkg_trust_dir/native_artifacts/native_forward")
assert_contains "package_native_artifact_emits_build_version" "$native_forward_load_commands" "LC_BUILD_VERSION"
assert_contains "package_native_artifact_emits_macos_platform" "$native_forward_load_commands" "platform 1"
assert_contains "package_native_artifact_emits_minimum_macos_11" "$native_forward_load_commands" "minos 11.0"
assert_contains "package_native_artifact_emits_deterministic_sdk_floor" "$native_forward_load_commands" "sdk 11.0"
assert_contains "package_native_artifact_emits_dwarf_segment" "$native_forward_load_commands" "__DWARF"
assert_contains "package_native_artifact_emits_dwarf_abbreviations" "$native_forward_load_commands" "__debug_abbrev"
assert_contains "package_native_artifact_emits_dwarf_compile_unit" "$native_forward_load_commands" "__debug_info"
assert_contains "package_native_artifact_emits_dwarf_line_program" "$native_forward_load_commands" "__debug_line"
assert_contains "package_native_artifact_emits_debugger_identity" "$native_forward_load_commands" "LC_UUID"
native_forward_symbols=$(nm -n "$tmp_pkg_trust_dir/native_artifacts/native_forward")
assert_contains "package_native_artifact_emits_main_symbol" "$native_forward_symbols" " T _main"
native_forward_dwarf_verify=$(/usr/bin/dwarfdump --verify "$tmp_pkg_trust_dir/native_artifacts/native_forward" 2>&1)
assert_contains "package_native_artifact_dwarf_verifies" "$native_forward_dwarf_verify" "No errors."
native_forward_main_debug=$(/usr/bin/dwarfdump --name main "$tmp_pkg_trust_dir/native_artifacts/native_forward")
assert_contains "package_native_artifact_names_main_subprogram" "$native_forward_main_debug" "DW_TAG_subprogram"
assert_contains "package_native_artifact_maps_main_source_attribute" "$native_forward_main_debug" "DW_AT_decl_file"
assert_contains "package_native_artifact_maps_main_source" "$native_forward_main_debug" "main.weft"
assert_contains "package_native_artifact_maps_main_line" "$native_forward_main_debug" "DW_AT_decl_line"
assert_contains "package_native_artifact_maps_main_line_one" "$native_forward_main_debug" "(1)"
/bin/cp "$tmp_pkg_trust_dir/native_artifacts/native_forward" "$tmp_native_debug_bin"
chmod +x "$tmp_native_debug_bin"
set +e
/usr/bin/lldb --batch \
  -o "settings set target.inline-breakpoint-strategy always" \
  -o "breakpoint set --name main --skip-prologue false" \
  -o run \
  -o bt \
  "$tmp_native_debug_bin" > "$tmp_native_debug_lldb" 2>&1
native_forward_lldb_exit=$?
set -e
native_forward_lldb=$(/bin/cat "$tmp_native_debug_lldb")
assert_equals "package_native_artifact_lldb_session_exits_cleanly" "$native_forward_lldb_exit" "0"
assert_contains "package_native_artifact_lldb_resolves_main" "$native_forward_lldb" "main at main.weft:1:4"
assert_contains "package_native_artifact_lldb_stops_in_main" "$native_forward_lldb" "stop reason = breakpoint"
assert_contains "package_native_artifact_lldb_walks_caller_frame" "$native_forward_lldb" "frame #1:"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_forward_stripped --artifact-facts native_forward_stripped.facts.json --strip-debug)
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_forward_stripped_second --strip-debug --artifact-facts native_forward_stripped_second.facts.json)
if cmp -s "$tmp_pkg_trust_dir/native_artifacts/native_forward_stripped" "$tmp_pkg_trust_dir/native_artifacts/native_forward_stripped_second"; then
  echo "  ok package_native_stripped_artifact_is_deterministic"
else
  echo "  fail package_native_stripped_artifact_is_deterministic"
  exit 1
fi
native_forward_stripped_facts=$(/bin/cat "$tmp_pkg_trust_dir/native_artifacts/native_forward_stripped.facts.json")
assert_contains "package_native_stripped_artifact_reports_absent_debug_information" "$native_forward_stripped_facts" '"debug_information":{"kind":"absent"}'
native_forward_stripped_load_commands=$(otool -l "$tmp_pkg_trust_dir/native_artifacts/native_forward_stripped")
assert_not_contains "package_native_stripped_artifact_omits_dwarf" "$native_forward_stripped_load_commands" "__DWARF"
native_forward_size=$(stat -f '%z' "$tmp_pkg_trust_dir/native_artifacts/native_forward")
native_forward_stripped_size=$(stat -f '%z' "$tmp_pkg_trust_dir/native_artifacts/native_forward_stripped")
if [ "$native_forward_stripped_size" -lt "$native_forward_size" ]; then
  echo "  ok package_native_strip_debug_reduces_artifact_size"
else
  echo "  fail package_native_strip_debug_reduces_artifact_size"
  exit 1
fi
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_forward_stripped"
pkg_native_forward_stripped_exit=$?
set -e
assert_equals "package_native_stripped_artifact_preserves_behavior" "$pkg_native_forward_stripped_exit" "42"
native_forward_signing=$(codesign -d --verbose=5 "$tmp_pkg_trust_dir/native_artifacts/native_forward" 2>&1)
assert_contains "package_native_artifact_signature_is_ad_hoc" "$native_forward_signing" "Signature=adhoc"
assert_contains "package_native_artifact_signature_names_weft" "$native_forward_signing" "Identifier=weft"
assert_contains "package_native_artifact_signature_uses_sha256" "$native_forward_signing" "Hash type=sha256"
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_forward"
pkg_native_forward_exit=$?
set -e
assert_equals "package_native_archive_forward_reference_links_and_runs" "$pkg_native_forward_exit" "42"

printf '%s\n' \
  'extern long weft_cycle_b(long);' \
  'long weft_cycle_a(long n) { return n == 0 ? 40 : weft_cycle_b(n - 1); }' \
  > "$tmp_pkg_trust_dir/native_artifacts/cycle_a.c"
printf '%s\n' \
  'extern long weft_cycle_a(long);' \
  'long weft_cycle_b(long n) { return n == 0 ? 2 : weft_cycle_a(n - 1); }' \
  > "$tmp_pkg_trust_dir/native_artifacts/cycle_b.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/cycle_a.c" -o "$tmp_pkg_trust_dir/native_artifacts/cycle_a.o"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/cycle_b.c" -o "$tmp_pkg_trust_dir/native_artifacts/cycle_b.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_closure/libweft_cycle.a" \
  "$tmp_pkg_trust_dir/native_artifacts/cycle_a.o" \
  "$tmp_pkg_trust_dir/native_artifacts/cycle_b.o"
native_cycle_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_closure/libweft_cycle.a")
native_cycle_digest=${native_cycle_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_cycle","search":["native/archive_closure"],"content":"sha256:'"$native_cycle_digest"'","optional":false}],"symbols":[{"declaration":"native_archive_value","symbol":"weft_cycle_a","library":"archive","params":["i64"],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_archive_value(1) }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_cycle)
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_cycle"
pkg_native_cycle_exit=$?
set -e
assert_equals "package_native_archive_cyclic_reference_links_and_runs" "$pkg_native_cycle_exit" "2"

# The real-object relocation matrix pins the exact external call and GOT-load
# alternatives admitted by the typed Mach-O parser. Closure selects the second
# member for both code and data, and finalization relaxes its GOT pair locally.
mkdir -p "$tmp_pkg_trust_dir/native_artifacts/native/archive_relocation_matrix"
printf '%s\n' \
  'extern long weft_matrix_data;' \
  'extern long weft_matrix_call(void);' \
  'long weft_matrix_entry(void) { return weft_matrix_call() + weft_matrix_data; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_entry.c"
printf '%s\n' \
  'long weft_matrix_data = 40;' \
  'long weft_matrix_call(void) { return 2; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_definitions.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_entry.c" -o "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_entry.o"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_definitions.c" -o "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_definitions.o"
native_relocation_matrix=$(otool -rv "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_entry.o")
assert_contains "package_native_archive_fixture_has_branch26_relocation" "$native_relocation_matrix" "BR26"
assert_contains "package_native_archive_fixture_has_got_page21_relocation" "$native_relocation_matrix" "GOTLDP  False"
assert_contains "package_native_archive_fixture_has_got_pageoff12_relocation" "$native_relocation_matrix" "GOTLDPOF"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_relocation_matrix/libweft_relocation_matrix.a" \
  "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_entry.o" \
  "$tmp_pkg_trust_dir/native_artifacts/relocation_matrix_definitions.o"
native_relocation_matrix_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_relocation_matrix/libweft_relocation_matrix.a")
native_relocation_matrix_digest=${native_relocation_matrix_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_relocation_matrix","search":["native/archive_relocation_matrix"],"content":"sha256:'"$native_relocation_matrix_digest"'","optional":false}],"symbols":[{"declaration":"native_relocation_matrix","symbol":"weft_matrix_entry","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_relocation_matrix() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_relocation_matrix)
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_relocation_matrix"
pkg_native_relocation_matrix_exit=$?
set -e
assert_equals "package_native_archive_branch_and_got_matrix_links_and_runs" "$pkg_native_relocation_matrix_exit" "42"

# Symbol strength is typed link data. A weak definition remains a valid
# fallback, a later strong definition wins regardless of member order, and two
# selected strong definitions fail before any output is committed.
mkdir -p "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength"
printf '%s\n' '__attribute__((weak)) long weft_weak_only(void) { return 42; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/weak_only.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/weak_only.c" -o "$tmp_pkg_trust_dir/native_artifacts/weak_only.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_weak_only.a" \
  "$tmp_pkg_trust_dir/native_artifacts/weak_only.o"
native_weak_only_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_weak_only.a")
native_weak_only_digest=${native_weak_only_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_weak_only","search":["native/archive_strength"],"content":"sha256:'"$native_weak_only_digest"'","optional":false}],"symbols":[{"declaration":"native_weak_only","symbol":"weft_weak_only","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_weak_only() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_weak_only)
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_weak_only"
pkg_native_weak_only_exit=$?
set -e
assert_equals "package_native_archive_weak_definition_is_fallback" "$pkg_native_weak_only_exit" "42"

printf '%s\n' \
  '__attribute__((weak)) long weft_choice(void) { return 7; }' \
  'long weft_weak_anchor(void) { return weft_choice(); }' \
  > "$tmp_pkg_trust_dir/native_artifacts/choice_weak.c"
printf '%s\n' \
  'long weft_choice(void) { return 42; }' \
  'long weft_strong_anchor(void) { return weft_choice(); }' \
  > "$tmp_pkg_trust_dir/native_artifacts/choice_strong.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/choice_weak.c" -o "$tmp_pkg_trust_dir/native_artifacts/choice_weak.o"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/choice_strong.c" -o "$tmp_pkg_trust_dir/native_artifacts/choice_strong.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_strength.a" \
  "$tmp_pkg_trust_dir/native_artifacts/choice_weak.o" \
  "$tmp_pkg_trust_dir/native_artifacts/choice_strong.o"
native_strength_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_strength.a")
native_strength_digest=${native_strength_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_strength","search":["native/archive_strength"],"content":"sha256:'"$native_strength_digest"'","optional":false}],"symbols":[{"declaration":"native_choice","symbol":"weft_choice","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_choice() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_strength)
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_strength"
pkg_native_strength_exit=$?
set -e
assert_equals "package_native_archive_strong_definition_beats_earlier_weak" "$pkg_native_strength_exit" "42"

printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_strength","search":["native/archive_strength"],"content":"sha256:'"$native_strength_digest"'","optional":false}],"symbols":[{"declaration":"native_weak_anchor","symbol":"weft_weak_anchor","library":"archive","params":[],"result":"i64","optional":false},{"declaration":"native_strong_anchor","symbol":"weft_strong_anchor","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_weak_anchor() + native_strong_anchor() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_strength_selected)
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_strength_selected"
pkg_native_strength_selected_exit=$?
set -e
assert_equals "package_native_archive_selected_strong_overrides_weak" "$pkg_native_strength_selected_exit" "84"

# Tentative/common storage is coalesced once across selected members. A real
# section definition outranks that coalesced storage and every reference is
# redirected to the winning address.
printf '%s\n' \
  'long weft_common_value;' \
  'long weft_common_set(long value) { weft_common_value = value; return 0; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/common_set.c"
printf '%s\n' \
  'long weft_common_value;' \
  'long weft_common_get(void) { return weft_common_value; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/common_get.c"
/usr/bin/clang -fcommon -c "$tmp_pkg_trust_dir/native_artifacts/common_set.c" -o "$tmp_pkg_trust_dir/native_artifacts/common_set.o"
/usr/bin/clang -fcommon -c "$tmp_pkg_trust_dir/native_artifacts/common_get.c" -o "$tmp_pkg_trust_dir/native_artifacts/common_get.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_common.a" \
  "$tmp_pkg_trust_dir/native_artifacts/common_set.o" \
  "$tmp_pkg_trust_dir/native_artifacts/common_get.o"
native_common_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_common.a")
native_common_digest=${native_common_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_common","search":["native/archive_strength"],"content":"sha256:'"$native_common_digest"'","optional":false}],"symbols":[{"declaration":"native_common_set","symbol":"weft_common_set","library":"archive","params":["i64"],"result":"i64","optional":false},{"declaration":"native_common_get","symbol":"weft_common_get","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_common_set(42) native_common_get() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_common)
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_common"
pkg_native_common_exit=$?
set -e
assert_equals "package_native_archive_common_storage_coalesces" "$pkg_native_common_exit" "42"

printf '%s\n' \
  'long weft_override_value;' \
  'long weft_common_read(void) { return weft_override_value; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/common_override.c"
printf '%s\n' \
  'long weft_override_value = 42;' \
  'long weft_strong_read(void) { return weft_override_value; }' \
  > "$tmp_pkg_trust_dir/native_artifacts/strong_override.c"
/usr/bin/clang -fcommon -c "$tmp_pkg_trust_dir/native_artifacts/common_override.c" -o "$tmp_pkg_trust_dir/native_artifacts/common_override.o"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/strong_override.c" -o "$tmp_pkg_trust_dir/native_artifacts/strong_override.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_common_override.a" \
  "$tmp_pkg_trust_dir/native_artifacts/common_override.o" \
  "$tmp_pkg_trust_dir/native_artifacts/strong_override.o"
native_common_override_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_common_override.a")
native_common_override_digest=${native_common_override_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_common_override","search":["native/archive_strength"],"content":"sha256:'"$native_common_override_digest"'","optional":false}],"symbols":[{"declaration":"native_common_read","symbol":"weft_common_read","library":"archive","params":[],"result":"i64","optional":false},{"declaration":"native_strong_read","symbol":"weft_strong_read","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_common_read() + native_strong_read() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_common_override)
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_common_override"
pkg_native_common_override_exit=$?
set -e
assert_equals "package_native_archive_strong_data_overrides_common" "$pkg_native_common_override_exit" "84"

# One archive member may contribute independently aligned initialized,
# constant, and zerofill sections. The output section carries the strongest
# alignment so the member-relative layout remains valid after final placement.
mkdir -p "$tmp_pkg_trust_dir/native_artifacts/native/archive_sections"
printf '%s\n' \
  '__attribute__((aligned(65536))) long weft_multi_initialized = 40;' \
  'static const volatile long weft_multi_const = 2;' \
  'static volatile long weft_multi_zero;' \
  'long weft_multi_section_value(void) {' \
  '  weft_multi_zero = weft_multi_const;' \
  '  return weft_multi_initialized + weft_multi_zero;' \
  '}' \
  > "$tmp_pkg_trust_dir/native_artifacts/multi_section.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/multi_section.c" -o "$tmp_pkg_trust_dir/native_artifacts/multi_section.o"
native_multi_object_sections=$(otool -l "$tmp_pkg_trust_dir/native_artifacts/multi_section.o")
native_multi_object_relocations=$(otool -rv "$tmp_pkg_trust_dir/native_artifacts/multi_section.o")
assert_contains "package_native_archive_fixture_has_initialized_section" "$native_multi_object_sections" "sectname __data"
assert_contains "package_native_archive_fixture_has_constant_section" "$native_multi_object_sections" "sectname __const"
assert_contains "package_native_archive_fixture_has_zerofill_section" "$native_multi_object_sections" "sectname __bss"
assert_contains "package_native_archive_fixture_has_64k_alignment" "$native_multi_object_sections" "align 2^16 (65536)"
assert_contains "package_native_archive_fixture_has_page21_relocation" "$native_multi_object_relocations" "PAGE21"
assert_contains "package_native_archive_fixture_has_pageoff12_relocation" "$native_multi_object_relocations" "PAGOF12"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_sections/libweft_sections.a" \
  "$tmp_pkg_trust_dir/native_artifacts/multi_section.o"
native_multi_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_sections/libweft_sections.a")
native_multi_digest=${native_multi_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_sections","search":["native/archive_sections"],"content":"sha256:'"$native_multi_digest"'","optional":false}],"symbols":[{"declaration":"native_multi_section_value","symbol":"weft_multi_section_value","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_multi_section_value() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_multi_section)
native_multi_output_sections=$(otool -l "$tmp_pkg_trust_dir/native_artifacts/native_multi_section")
assert_contains "package_native_archive_output_preserves_64k_alignment" "$native_multi_output_sections" "align 2^16 (65536)"
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_artifacts/native_multi_section"
pkg_native_multi_exit=$?
set -e
assert_equals "package_native_archive_multiple_sections_link_and_run" "$pkg_native_multi_exit" "42"

# A scaled load cannot encode a byte-misaligned PAGEOFF12 target. Resolution
# reports that typed residual before the product writer can commit an artifact.
mkdir -p "$tmp_pkg_trust_dir/native_artifacts/native/archive_relocations"
printf '%s\n' \
  '.text' \
  '.globl _weft_bad_reloc' \
  '_weft_bad_reloc:' \
  '  adrp x0, _weft_bad_data@PAGE' \
  '  ldr x0, [x0, _weft_bad_data@PAGEOFF]' \
  '  ret' \
  '.data' \
  '.byte 0' \
  '.globl _weft_bad_data' \
  '_weft_bad_data:' \
  '  .byte 42' \
  > "$tmp_pkg_trust_dir/native_artifacts/misaligned_pageoff.s"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/misaligned_pageoff.s" -o "$tmp_pkg_trust_dir/native_artifacts/misaligned_pageoff.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_relocations/libweft_bad_reloc.a" \
  "$tmp_pkg_trust_dir/native_artifacts/misaligned_pageoff.o"
native_bad_reloc_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_relocations/libweft_bad_reloc.a")
native_bad_reloc_digest=${native_bad_reloc_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_bad_reloc","search":["native/archive_relocations"],"content":"sha256:'"$native_bad_reloc_digest"'","optional":false}],"symbols":[{"declaration":"native_bad_reloc","symbol":"weft_bad_reloc","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_bad_reloc() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
set +e
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_bad_reloc) \
  > "$tmp_pkg_trust_dir/native_artifacts/native_bad_reloc.stdout" \
  2> "$tmp_pkg_trust_dir/native_artifacts/native_bad_reloc.err"
pkg_native_bad_reloc_exit=$?
set -e
assert_equals "package_native_archive_misaligned_relocation_fails" "$pkg_native_bad_reloc_exit" "1"
assert_contains "package_native_archive_misaligned_relocation_is_structured" "$(<"$tmp_pkg_trust_dir/native_artifacts/native_bad_reloc.err")" "pageoff12 relocation target is not aligned for its instruction"
if [ ! -e "$tmp_pkg_trust_dir/native_artifacts/native_bad_reloc" ]; then
  echo "  ok package_native_archive_misaligned_relocation_commits_no_output"
else
  echo "  fail package_native_archive_misaligned_relocation_commits_no_output"
  exit 1
fi

printf '%s\n' \
  'long weft_duplicate(void) { return 1; }' \
  'long weft_pick_a(void) { return weft_duplicate(); }' \
  > "$tmp_pkg_trust_dir/native_artifacts/duplicate_a.c"
printf '%s\n' \
  'long weft_duplicate(void) { return 2; }' \
  'long weft_pick_b(void) { return weft_duplicate(); }' \
  > "$tmp_pkg_trust_dir/native_artifacts/duplicate_b.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/duplicate_a.c" -o "$tmp_pkg_trust_dir/native_artifacts/duplicate_a.o"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_artifacts/duplicate_b.c" -o "$tmp_pkg_trust_dir/native_artifacts/duplicate_b.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_duplicate.a" \
  "$tmp_pkg_trust_dir/native_artifacts/duplicate_a.o" \
  "$tmp_pkg_trust_dir/native_artifacts/duplicate_b.o"
native_duplicate_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_strength/libweft_duplicate.a")
native_duplicate_digest=${native_duplicate_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_duplicate","search":["native/archive_strength"],"content":"sha256:'"$native_duplicate_digest"'","optional":false}],"symbols":[{"declaration":"native_pick_a","symbol":"weft_pick_a","library":"archive","params":[],"result":"i64","optional":false},{"declaration":"native_pick_b","symbol":"weft_pick_b","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_pick_a() + native_pick_b() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
set +e
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_duplicate) \
  > "$tmp_pkg_trust_dir/native_artifacts/native_duplicate.stdout" \
  2> "$tmp_pkg_trust_dir/native_artifacts/native_duplicate.err"
pkg_native_duplicate_exit=$?
set -e
assert_equals "package_native_archive_duplicate_strong_fails" "$pkg_native_duplicate_exit" "1"
assert_contains "package_native_archive_duplicate_strong_is_structured" "$(<"$tmp_pkg_trust_dir/native_artifacts/native_duplicate.err")" "strong symbol 'weft_duplicate' more than once"
if [ ! -e "$tmp_pkg_trust_dir/native_artifacts/native_duplicate" ]; then
  echo "  ok package_native_archive_duplicate_strong_commits_no_output"
else
  echo "  fail package_native_archive_duplicate_strong_commits_no_output"
  exit 1
fi

native_compiler_strings=$(strings "$WEFT_ABS")
assert_not_contains "package_native_product_compiler_has_no_clang_fallback" "$native_compiler_strings" "/usr/bin/clang"
native_compiler_load_commands=$(otool -l "$WEFT_ABS")
assert_contains "package_native_compiler_emits_build_version" "$native_compiler_load_commands" "LC_BUILD_VERSION"
assert_contains "package_native_compiler_emits_minimum_macos_11" "$native_compiler_load_commands" "minos 11.0"

printf '%s\n' '!<arch>' 'not a Mach-O member' > "$tmp_pkg_trust_dir/native_artifacts/native/archive_closure/libweft_malformed.a"
native_malformed_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_artifacts/native/archive_closure/libweft_malformed.a")
native_malformed_digest=${native_malformed_digest_line%% *}
printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_malformed","search":["native/archive_closure"],"content":"sha256:'"$native_malformed_digest"'","optional":false}],"symbols":[{"declaration":"native_archive_value","symbol":"weft_missing","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_archive_value() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
set +e
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_malformed) \
  > "$tmp_pkg_trust_dir/native_artifacts/native_malformed.stdout" \
  2> "$tmp_pkg_trust_dir/native_artifacts/native_malformed.err"
pkg_native_malformed_exit=$?
set -e
assert_equals "package_native_malformed_archive_fails_closed" "$pkg_native_malformed_exit" "1"
assert_contains "package_native_malformed_archive_is_structured" "$(<"$tmp_pkg_trust_dir/native_artifacts/native_malformed.err")" "not a supported aarch64 Mach-O archive"
if [ ! -e "$tmp_pkg_trust_dir/native_artifacts/native_malformed" ]; then
  echo "  ok package_native_malformed_archive_commits_no_output"
else
  echo "  fail package_native_malformed_archive_commits_no_output"
  exit 1
fi

printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"archive","kind":"archive","link":"weft_fixture","search":["native/archive_first","native/archive_second"],"content":"sha256:0000000000000000000000000000000000000000000000000000000000000000","optional":false}],"symbols":[{"declaration":"native_archive_value","symbol":"weft_archive_value","library":"archive","params":[],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -[Unsafe]> i64 { native_archive_value() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
set +e
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" compile main.weft) > "$tmp_pkg_trust_dir/native_artifacts/mismatched.o" 2> "$tmp_pkg_trust_dir/native_artifacts/mismatched.err"
pkg_native_mismatch_exit=$?
set -e
assert_equals "package_native_content_mismatch_fails" "$pkg_native_mismatch_exit" "1"
assert_contains "package_native_content_mismatch_is_explicit" "$(<"$tmp_pkg_trust_dir/native_artifacts/mismatched.err")" "does not match its manifest sha256 content"
if [ ! -s "$tmp_pkg_trust_dir/native_artifacts/mismatched.o" ]; then
  echo "  ok package_native_content_mismatch_emits_no_object"
else
  echo "  fail package_native_content_mismatch_emits_no_object"
  exit 1
fi

printf '%s\n' \
  '{"package":"native-artifacts","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["main"],"native_bindings":{"main":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"optional","kind":"archive","link":"weft_optional","search":["native/missing"],"content":"sha256:0000000000000000000000000000000000000000000000000000000000000000","optional":true}],"symbols":[{"declaration":"native_optional_value","symbol":"weft_optional_value","library":"optional","params":[],"result":"i64","optional":true}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_artifacts/weft.pkg"
printf '%s\n' 'fn main() -> i64 { 0 }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" compile main.weft) > "$tmp_pkg_trust_dir/native_artifacts/optional_uncalled.o"
optional_uncalled_symbols=$(nm -u "$tmp_pkg_trust_dir/native_artifacts/optional_uncalled.o")
assert_not_contains "package_native_uncalled_optional_library_is_omitted" "$optional_uncalled_symbols" "_weft_optional_value"

printf '%s\n' 'fn main() -[Unsafe]> i64 { native_optional_value() }' > "$tmp_pkg_trust_dir/native_artifacts/main.weft"
set +e
(cd "$tmp_pkg_trust_dir/native_artifacts" && run_weft_compile_guarded "$WEFT_ABS" compile main.weft) > "$tmp_pkg_trust_dir/native_artifacts/optional_called.o" 2> "$tmp_pkg_trust_dir/native_artifacts/optional_called.err"
pkg_native_optional_called_exit=$?
set -e
assert_equals "package_native_called_missing_optional_fails" "$pkg_native_optional_called_exit" "1"
assert_contains "package_native_called_missing_optional_is_explicit" "$(<"$tmp_pkg_trust_dir/native_artifacts/optional_called.err")" "is optional but unavailable in its declared search paths"
if [ ! -s "$tmp_pkg_trust_dir/native_artifacts/optional_called.o" ]; then
  echo "  ok package_native_called_missing_optional_emits_no_object"
else
  echo "  fail package_native_called_missing_optional_emits_no_object"
  exit 1
fi

# A dependency-owned trusted leaf seals a real C archive behind an ordinary
# pure API. Opaque owned handles carry exact Drop, while const_bytes/mut_bytes
# lower one scoped Weft slice to the C (pointer, length) product. The importing
# root grants only the exact leaf and never receives Unsafe authority.
mkdir -p \
  "$tmp_pkg_trust_dir/native_safe/deps/fixture/native/lib" \
  "$tmp_pkg_trust_dir/native_safe/deps/fixture/native"
ln -s "$PROJECT_ROOT/runtime" "$tmp_pkg_trust_dir/native_safe/runtime"
ln -s "$PROJECT_ROOT/stdlib" "$tmp_pkg_trust_dir/native_safe/stdlib"
printf '%s\n' \
  '#include <stdint.h>' \
  '#include <stdlib.h>' \
  'typedef struct fixture_handle { int64_t value; } fixture_handle;' \
  'static int64_t fixture_drops = 0;' \
  'void *fixture_open(int64_t value) { fixture_handle *resource = malloc(sizeof(fixture_handle)); if (resource != NULL) resource->value = value; return resource; }' \
  'int64_t fixture_get(void *raw) { fixture_handle *resource = raw; return resource == NULL ? -1 : resource->value; }' \
  'void fixture_close(void *raw) { fixture_drops += 1; free(raw); }' \
  'int64_t fixture_drop_count(void) { return fixture_drops; }' \
  'int64_t fixture_sum(const uint8_t *data, uint64_t len) { int64_t total = 0; for (uint64_t i = 0; i < len; i += 1) total += data[i]; return total; }' \
  'int64_t fixture_fill(uint8_t *data, uint64_t len, int64_t value) { for (uint64_t i = 0; i < len; i += 1) data[i] = (uint8_t)value; return (int64_t)len; }' \
  > "$tmp_pkg_trust_dir/native_safe/deps/fixture/fixture.c"
/usr/bin/clang -c "$tmp_pkg_trust_dir/native_safe/deps/fixture/fixture.c" -o "$tmp_pkg_trust_dir/native_safe/deps/fixture/fixture.o"
/usr/bin/ar rcs "$tmp_pkg_trust_dir/native_safe/deps/fixture/native/lib/libfixture.a" "$tmp_pkg_trust_dir/native_safe/deps/fixture/fixture.o"
native_safe_digest_line=$(/usr/bin/shasum -a 256 "$tmp_pkg_trust_dir/native_safe/deps/fixture/native/lib/libfixture.a")
native_safe_digest=${native_safe_digest_line%% *}
printf '%s\n' \
  '{"package":"fixture","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["native/raw"],"native_bindings":{"native/raw":{"abi_version":1,"targets":{"macos-aarch64":{"libraries":[{"id":"fixture","kind":"archive","link":"fixture","search":["native/lib"],"content":"sha256:'"$native_safe_digest"'","optional":false}],"symbols":[{"declaration":"native_open","symbol":"fixture_open","library":"fixture","params":["i64"],"result":"opaque_ptr","optional":false},{"declaration":"native_get","symbol":"fixture_get","library":"fixture","params":["opaque_ptr"],"result":"i64","optional":false},{"declaration":"native_close","symbol":"fixture_close","library":"fixture","params":["opaque_ptr"],"result":"nil","optional":false},{"declaration":"native_drop_count","symbol":"fixture_drop_count","library":"fixture","params":[],"result":"i64","optional":false},{"declaration":"native_sum","symbol":"fixture_sum","library":"fixture","params":["const_bytes"],"result":"i64","optional":false},{"declaration":"native_fill","symbol":"fixture_fill","library":"fixture","params":["mut_bytes","i64"],"result":"i64","optional":false}]}}}}}' \
  > "$tmp_pkg_trust_dir/native_safe/deps/fixture/weft.pkg"
printf '%s\n' \
  'use runtime/unsafe.{*}' \
  'use stdlib/drop.{*}' \
  'pub type FixtureHandle = opaque *any' \
  'fn fixture_seal_open(value: i64) -> *any { handle native_open(value) { Unsafe.transmute(raw) -> resume(__transmute(raw)) } }' \
  'fn fixture_seal_get(raw: *any) -> i64 { handle native_get(raw) { Unsafe.transmute(value) -> resume(__transmute(value)) } }' \
  'fn fixture_seal_close(raw: *any) -> i64 {' \
  '  handle { native_close(raw) 0 } { Unsafe.transmute(value) -> resume(__transmute(value)) }' \
  '}' \
  'impl Drop for FixtureHandle {' \
  '  fn drop(self) -> i64 { match self { FixtureHandle(raw) -> fixture_seal_close(raw) } }' \
  '}' \
  'pub fn fixture_open_safe(value: i64) -> owned FixtureHandle { FixtureHandle(fixture_seal_open(value)) }' \
  'pub fn fixture_get_safe(resource: borrow FixtureHandle) -> i64 { match resource { FixtureHandle(raw) -> fixture_seal_get(raw) } }' \
  'pub fn fixture_drop_count_safe() -> i64 { handle native_drop_count() { Unsafe.transmute(value) -> resume(__transmute(value)) } }' \
  'pub fn fixture_sum_slice(values: [u8]) -> i64 {' \
  '  handle native_sum(values) { Unsafe.transmute(value) -> resume(__transmute(value)) }' \
  '}' \
  'pub fn fixture_fill_bytes(values: [mut u8], value: i64) -> i64 {' \
  '  handle native_fill(values, value) { Unsafe.transmute(raw) -> resume(__transmute(raw)) }' \
  '}' \
  > "$tmp_pkg_trust_dir/native_safe/deps/fixture/native/raw.weft"
printf '%s\n' \
  'use fixture/native/raw.{fixture_sum_slice}' \
  'use stdlib/bytes.{*}' \
  'use stdlib/vector.{*}' \
  'pub fn fixture_sum_bytes(values: Bytes) -> i64 {' \
  '  let contiguous = bytes_to_vector(values)' \
  '  fixture_sum_slice(contiguous[..])' \
  '}' \
  > "$tmp_pkg_trust_dir/native_safe/safe_fixture.weft"
printf '%s\n' \
  '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"fixture":"deps/fixture"},"trust":{"fixture":{"version":"1.0.0","source":"path:deps/fixture","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111","modules":["native/raw"]}}}' \
  > "$tmp_pkg_trust_dir/native_safe/weft.pkg"
printf '%s\n' \
  '{"lock_version":1,"manifest_version":1,"weft":"0.1","packages":[{"name":"app","version":"1.0.0","source":"path:.","content":"sha256:0000000000000000000000000000000000000000000000000000000000000000"},{"name":"fixture","version":"1.0.0","source":"path:deps/fixture","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}]}' \
  > "$tmp_pkg_trust_dir/native_safe/weft.lock"
printf '%s\n' \
  'use fixture/native/raw.{*}' \
  'use safe_fixture.{fixture_sum_bytes}' \
  'use stdlib/bytes.{*}' \
  'use stdlib/vector.{*}' \
  'fn scoped_handle_value() -> i64 {' \
  '  let resource: owned FixtureHandle = fixture_open_safe(40)' \
  '  fixture_get_safe(resource)' \
  '}' \
  'fn main() -> i64 {' \
  '  let handle_value = scoped_handle_value()' \
  '  let text_sum = fixture_sum_bytes(bytes_from_str("*"))' \
  '  let mutable = bytes_to_vector(bytes_from_str("abc"))' \
  '  let filled = fixture_fill_bytes(mutable[..], 14)' \
  '  let filled_sum = fixture_sum_bytes(bytes_from_vector(mutable))' \
  '  if handle_value == 40 and text_sum == 42 and filled == 3 and filled_sum == 42 and fixture_drop_count_safe() == 1 { 42 } else { 1 }' \
  '}' \
  > "$tmp_pkg_trust_dir/native_safe/main.weft"
native_safe_check=$(cd "$tmp_pkg_trust_dir/native_safe" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_native_safe_dependency_hides_unsafe" "$native_safe_check" "0 errors"
native_safe_audit=$(cd "$tmp_pkg_trust_dir/native_safe" && "$WEFT_ABS" pkg audit 2>/dev/null)
native_safe_audit_second=$(cd "$tmp_pkg_trust_dir/native_safe" && "$WEFT_ABS" pkg audit 2>/dev/null)
assert_equals "package_native_audit_is_deterministic" "$native_safe_audit_second" "$native_safe_audit"
assert_contains "package_native_audit_pins_schema" "$native_safe_audit" '"schema_version":1'
assert_contains "package_native_audit_names_exact_package" "$native_safe_audit" '"package":"fixture"'
assert_contains "package_native_audit_names_exact_module" "$native_safe_audit" '"module":"native/raw"'
assert_contains "package_native_audit_names_content_identity" "$native_safe_audit" '"content":"sha256:1111111111111111111111111111111111111111111111111111111111111111"'
assert_contains "package_native_audit_lists_const_bytes" "$native_safe_audit" '"const_bytes"'
assert_contains "package_native_audit_lists_mut_bytes" "$native_safe_audit" '"mut_bytes"'
assert_contains "package_native_audit_lists_owned_handle_symbol" "$native_safe_audit" '"declaration":"native_open"'
assert_contains "package_native_audit_lists_wrapper_facts" "$native_safe_audit" '"wrappers":['
assert_contains "package_native_audit_lists_safe_wrapper" "$native_safe_audit" '"name":"fixture_open_safe"'
assert_contains "package_native_audit_lists_safe_wrapper_signature" "$native_safe_audit" '"signature":"pub fn fixture_open_safe(value: i64) -> owned FixtureHandle"'
assert_contains "package_native_audit_lists_safe_wrapper_effects" "$native_safe_audit" '"effects":"pure"'
assert_not_contains "package_native_audit_wrapper_effects_hide_unsafe" "$native_safe_audit" '"effects":"Unsafe"'
(cd "$tmp_pkg_trust_dir/native_safe" && run_weft_compile_guarded "$WEFT_ABS" build main.weft -o native_safe --artifact-facts native_safe.facts.json)
native_safe_facts=$(/bin/cat "$tmp_pkg_trust_dir/native_safe/native_safe.facts.json")
assert_contains "package_native_artifact_facts_name_dependency_trust" "$native_safe_facts" '"package":"fixture","version":"1.0.0","source":"path:deps/fixture","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111","module":"native/raw"'
codesign --verify "$tmp_pkg_trust_dir/native_safe/native_safe"
set +e
run_binary_guarded "$tmp_pkg_trust_dir/native_safe/native_safe"
native_safe_exit=$?
set -e
assert_equals "package_native_owned_handle_and_scoped_bytes_run" "$native_safe_exit" "42"

printf '%s\n' \
  'use fixture/native/raw.{*}' \
  'fn consume(resource: owned FixtureHandle) -> i64 { 0 }' \
  'fn main() -> i64 {' \
  '  let resource: owned FixtureHandle = fixture_open_safe(1)' \
  '  consume(resource) + fixture_get_safe(resource)' \
  '}' \
  > "$tmp_pkg_trust_dir/native_safe/main.weft"
native_double_drop=$(cd "$tmp_pkg_trust_dir/native_safe" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_native_owned_handle_rejects_double_consume" "$native_double_drop" "owned value used more than once"

printf '%s\n' 'pub fn leaked_pointer(raw: *any) -> *any { raw }' > "$tmp_pkg_trust_dir/native_safe/deps/fixture/native/raw.weft"
printf '%s\n' 'use fixture/native/raw.{leaked_pointer}' 'fn main() -> i64 { 0 }' > "$tmp_pkg_trust_dir/native_safe/main.weft"
native_pointer_leak=$(cd "$tmp_pkg_trust_dir/native_safe" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_native_public_pointer_is_rejected" "$native_pointer_leak" "native binding public surface cannot expose raw pointers"

printf '%s\n' 'use runtime/unsafe.{*}' 'pub fn leaked_authority() -[Unsafe]> i64 { 0 }' > "$tmp_pkg_trust_dir/native_safe/deps/fixture/native/raw.weft"
printf '%s\n' 'use fixture/native/raw.{leaked_authority}' 'fn main() -> i64 { 0 }' > "$tmp_pkg_trust_dir/native_safe/main.weft"
native_unsafe_leak=$(cd "$tmp_pkg_trust_dir/native_safe" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_native_public_unsafe_is_rejected" "$native_unsafe_leak" "native binding public wrapper cannot expose Unsafe"

# Trust belongs to the exact source buffer; importing an unlisted helper from
# a trusted binding does not make that helper trusted.
printf 'use native/helper.{*}\npub fn raw_probe(p: i64) -> i64 { helper_probe(p) }\n' > "$tmp_pkg_trust_dir/root_owned/native/raw.weft"
printf 'pub fn helper_probe(p: i64) -> i64 { __mem_load64(p) }\n' > "$tmp_pkg_trust_dir/root_owned/native/helper.weft"
pkg_trust_nonpropagating=$(cd "$tmp_pkg_trust_dir/root_owned" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_binding_trust_does_not_propagate_to_imports" "$pkg_trust_nonpropagating" "type error: Unsafe is sealed to trusted runtime/platform code"

# A dependency physically rooted at runtime/ cannot inherit the compiler's
# transitional root-package path trust.
mkdir -p "$tmp_pkg_trust_dir/path_alias/runtime"
printf '{"package":"app","dependencies":{"runtime":"runtime"}}\n' > "$tmp_pkg_trust_dir/path_alias/weft.pkg"
printf '{"package":"runtime","dependencies":{}}\n' > "$tmp_pkg_trust_dir/path_alias/runtime/weft.pkg"
printf 'use runtime/alloc.{*}\nfn main() -> i64 { 0 }\n' > "$tmp_pkg_trust_dir/path_alias/main.weft"
printf 'pub fn raw_probe(p: i64) -> i64 { __mem_load64(p) }\n' > "$tmp_pkg_trust_dir/path_alias/runtime/alloc.weft"
pkg_trust_path_alias=$(cd "$tmp_pkg_trust_dir/path_alias" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_dependency_cannot_alias_builtin_trust_path" "$pkg_trust_path_alias" "type error: Unsafe is sealed to trusted runtime/platform code"

# Root authority may explicitly name a transitive package, but the
# intermediate dependency cannot forward or synthesize that authority.
mkdir -p "$tmp_pkg_trust_dir/transitive/deps/mid/deps/leaf/native"
printf '{"package":"app","manifest_version":1,"version":"1.0.0","weft":"0.1","dependencies":{"mid":"deps/mid"},"trust":{"leaf":{"version":"3.0.0","source":"path:deps/mid/deps/leaf","content":"sha256:2222222222222222222222222222222222222222222222222222222222222222","modules":["native/raw"]}}}\n' > "$tmp_pkg_trust_dir/transitive/weft.pkg"
printf '{"package":"mid","manifest_version":1,"version":"2.0.0","weft":"0.1","dependencies":{"leaf":"deps/leaf"}}\n' > "$tmp_pkg_trust_dir/transitive/deps/mid/weft.pkg"
printf '{"package":"leaf","manifest_version":1,"version":"3.0.0","weft":"0.1","dependencies":{},"trusted_bindings":["native/raw"]}\n' > "$tmp_pkg_trust_dir/transitive/deps/mid/deps/leaf/weft.pkg"
printf 'use leaf/native/raw.{*}\npub fn wrapped() -> i64 { 0 }\n' > "$tmp_pkg_trust_dir/transitive/deps/mid/wrapper.weft"
printf 'pub fn raw_probe(p: i64) -> i64 { __mem_load64(p) }\n' > "$tmp_pkg_trust_dir/transitive/deps/mid/deps/leaf/native/raw.weft"
printf 'use mid/wrapper.{*}\nfn main() -> i64 { wrapped() }\n' > "$tmp_pkg_trust_dir/transitive/main.weft"
printf '{"lock_version":1,"manifest_version":1,"weft":"0.1","packages":[{"name":"app","version":"1.0.0","source":"path:.","content":"sha256:0000000000000000000000000000000000000000000000000000000000000000"},{"name":"leaf","version":"3.0.0","source":"path:deps/mid/deps/leaf","content":"sha256:2222222222222222222222222222222222222222222222222222222222222222"},{"name":"mid","version":"2.0.0","source":"path:deps/mid","content":"sha256:1111111111111111111111111111111111111111111111111111111111111111"}]}\n' > "$tmp_pkg_trust_dir/transitive/weft.lock"
pkg_trust_transitive=$(cd "$tmp_pkg_trust_dir/transitive" && "$WEFT_ABS" check main.weft 2>&1)
assert_contains "package_root_can_explicitly_grant_transitive_binding" "$pkg_trust_transitive" "check: 3 functions, 0 errors"

# Package export discovery is deterministic metadata over ordinary public
# declarations. The repository manifest is the first package-root fixture.
pkg_exports_out=$("$WEFT" pkg exports 2>&1)
assert_contains "pkg_exports_reports_first_party_sql_grammar" "$pkg_exports_out" '"sql":{"module":"stdlib/grammar/sql","declaration":"SqlGrammar","execution":"validate_only"}'
assert_contains "pkg_exports_reports_ast_tool" "$pkg_exports_out" '"ast":{"module":"tools/ast","declaration":"main"}'
assert_contains "pkg_exports_reports_check_tool" "$pkg_exports_out" '"check":{"module":"tools/check","declaration":"main"}'
assert_contains "pkg_exports_reports_fmt_tool" "$pkg_exports_out" '"fmt":{"module":"tools/fmt","declaration":"main"}'
assert_contains "pkg_exports_reports_test_tool" "$pkg_exports_out" '"test":{"module":"tools/test_runner","declaration":"main"}'

mkdir -p "$tmp_pkg_trust_dir/exports/deps/left/tools" "$tmp_pkg_trust_dir/exports/deps/right/tools"
printf '{"package":"app","dependencies":{"left":"deps/left","right":"deps/right"}}\n' > "$tmp_pkg_trust_dir/exports/weft.pkg"
printf '{"package":"left","dependencies":{},"exports":{"tools":{"inspect":{"module":"tools/inspect","declaration":"run"}}}}\n' > "$tmp_pkg_trust_dir/exports/deps/left/weft.pkg"
printf '{"package":"right","dependencies":{},"exports":{"tools":{"inspect":{"module":"tools/inspect","declaration":"run"}}}}\n' > "$tmp_pkg_trust_dir/exports/deps/right/weft.pkg"
printf 'pub fn run() -> i64 { 20 }\n' > "$tmp_pkg_trust_dir/exports/deps/left/tools/inspect.weft"
printf 'pub fn run() -> i64 { 22 }\n' > "$tmp_pkg_trust_dir/exports/deps/right/tools/inspect.weft"
printf 'use left/tools/inspect as left_inspect\nuse right/tools/inspect as right_inspect\nfn main() -> i64 { if left_inspect.run() + right_inspect.run() == 42 { 0 } else { 1 } }\n' > "$tmp_pkg_trust_dir/exports/main.weft"
pkg_exports_qualified=$(cd "$tmp_pkg_trust_dir/exports" && "$WEFT_ABS" check main.weft 2>&1)
assert_contains "package_exports_are_qualified_by_package_identity" "$pkg_exports_qualified" "check: 3 functions, 0 errors"

printf 'fn run() -> i64 { 20 }\n' > "$tmp_pkg_trust_dir/exports/deps/left/tools/inspect.weft"
pkg_export_private=$(cd "$tmp_pkg_trust_dir/exports" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_export_rejects_package_private_l7_target" "$pkg_export_private" "error[E5009]: package tool export 'inspect' names a declaration that is not public"

printf 'pub type Run { Run }\n' > "$tmp_pkg_trust_dir/exports/deps/left/tools/inspect.weft"
printf '{"package":"left","dependencies":{},"exports":{"tools":{"inspect":{"module":"tools/inspect","declaration":"Run"}}}}\n' > "$tmp_pkg_trust_dir/exports/deps/left/weft.pkg"
pkg_export_wrong_kind=$(cd "$tmp_pkg_trust_dir/exports" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_export_rejects_wrong_declaration_kind" "$pkg_export_wrong_kind" "error[E5009]: package tool export 'inspect' names the wrong declaration kind"

printf 'pub fn run() -> i64 { 20 }\n' > "$tmp_pkg_trust_dir/exports/deps/left/tools/inspect.weft"
printf '{"package":"left","dependencies":{},"exports":{"tools":{"inspect":{"module":"tools/inspect","declaration":"missing"}}}}\n' > "$tmp_pkg_trust_dir/exports/deps/left/weft.pkg"
pkg_export_missing=$(cd "$tmp_pkg_trust_dir/exports" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_export_rejects_missing_declaration" "$pkg_export_missing" "error[E5009]: package tool export 'inspect' does not name a declaration in its module"

printf '{"package":"left","dependencies":{},"exports":{"grammars":{"inspect":{"module":"tools/inspect","declaration":"Run","execution":"validate_only"}}}}\n' > "$tmp_pkg_trust_dir/exports/deps/left/weft.pkg"
printf 'pub type Run { Run }\n' > "$tmp_pkg_trust_dir/exports/deps/left/tools/inspect.weft"
printf 'use left/tools/inspect as left_inspect\nuse right/tools/inspect as right_inspect\nfn main() -> i64 { right_inspect.run() - 22 }\n' > "$tmp_pkg_trust_dir/exports/main.weft"
pkg_export_grammar=$(cd "$tmp_pkg_trust_dir/exports" && "$WEFT_ABS" check main.weft 2>&1)
assert_contains "package_grammar_export_resolves_public_type" "$pkg_export_grammar" "check: 2 functions, 0 errors"

# L7 is a package-product boundary, not only an in-memory visibility fact:
# Stable fact/diagnostic APIs cross a resolved dependency edge while typed IR
# remains available only inside the compiler package.
mkdir -p "$tmp_pkg_trust_dir/l7/deps/compiler"
printf '{"package":"app","dependencies":{"compiler":"deps/compiler"}}\n' > "$tmp_pkg_trust_dir/l7/weft.pkg"
printf '{"package":"compiler","dependencies":{}}\n' > "$tmp_pkg_trust_dir/l7/deps/compiler/weft.pkg"
printf 'pub fn semantic_fact_version() -> i64 { 1 }\n' > "$tmp_pkg_trust_dir/l7/deps/compiler/facts.weft"
printf 'pub fn diagnostic_schema_version() -> i64 { 1 }\n' > "$tmp_pkg_trust_dir/l7/deps/compiler/diagnostics.weft"
printf 'pub(package) fn typed_ir_version() -> i64 { 1 }\n' > "$tmp_pkg_trust_dir/l7/deps/compiler/ir.weft"
printf 'use compiler/facts.{semantic_fact_version}\nuse compiler/diagnostics.{diagnostic_schema_version}\nfn main() -> i64 { semantic_fact_version() + diagnostic_schema_version() - 2 }\n' > "$tmp_pkg_trust_dir/l7/main.weft"
pkg_l7_stable=$(cd "$tmp_pkg_trust_dir/l7" && "$WEFT_ABS" check main.weft 2>&1)
assert_contains "package_l7_stable_fact_and_diagnostic_cross_boundary" "$pkg_l7_stable" "check: 3 functions, 0 errors"

printf 'use compiler/ir.{typed_ir_version}\nfn main() -> i64 { typed_ir_version() }\n' > "$tmp_pkg_trust_dir/l7/main.weft"
pkg_l7_unstable=$(cd "$tmp_pkg_trust_dir/l7" && "$WEFT_ABS" check main.weft 2>&1 || true)
assert_contains "package_l7_unstable_ir_stays_inside_owner" "$pkg_l7_unstable" "error[E4004]: module member 'typed_ir_version' is not visible in this import"

printf 'fn helper() -> i64 { 42 }\nfn main() -> i64 { helper() }\n' > "$tmp_src"
run_weft_compile_guarded "$WEFT" symbols "$tmp_src" > "$tmp_out" 2> "$tmp_err"
symbols_out=$(<"$tmp_out")
symbols_lines=$(wc -l < "$tmp_out" | tr -d ' ')
assert_equals "symbols_emits_one_fact_per_native_function" "$symbols_lines" "2"
assert_contains "symbols_uses_checked_main_name" "$symbols_out" " main"
assert_contains "symbols_uses_checked_helper_name" "$symbols_out" " helper"

printf 'test "plain" { Test.assert_eq(1, 1) }\n' > "$tmp_src"
run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_not_contains_file "test_harness_binds_runtime_without_missing_symbols" "$tmp_err" "required runtime function unavailable"
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin" 2>"$tmp_err"
assert_contains "test_harness_emits_passing_result" "$(<"$tmp_err")" "WEFT_TEST_RESULT 1 1 0 1"
echo "  ok test_harness_binds_runtime_after_synthesis"

printf 'use stdlib/diagnostic_type.{Diagnose} use stdlib/vector.{*} fn tool_fail5() -[Fail<i64>]> i64 { Fail.fail(5) } test "helpers" { Test.assert_eq(1, 1) Test.assert_ne(1, 2) Test.assert_true(1 == 1) Test.assert_false(1 == 2) Test.assert_lt(1, 2) Test.assert_le(2, 2) Test.assert_gt(3, 2) Test.assert_ge(3, 3) Test.assert_eq_f64(1.5, 1.5) Test.assert_near_f64(0.1 + 0.2, 0.3, 1e-12) Test.forall_i64_range(0, 3, x => x < 3) let va = vector_new<i64>() let vb = vector_new<i64>() vector_push<i64>(va, 7) vector_push<i64>(vb, 7) Test.assert_i64_vector_eq(va, vb) Test.assert_eq(Test.with_state_i64(4, () => TestState.get()), 4) Test.assert_eq(Test.expect_fail_i64(5, () => tool_fail5()), 5) Test.assert_eq(Test.with_io_i64(() => IO.write(1, 0, 2)), 2) Test.assert_eq(Test.with_diagnose_i64(() => Diagnose.error("x", 0 - 1)), 1) }\n' > "$tmp_src"
run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_not_contains_file "test_harness_supports_assertion_helpers" "$tmp_err" "unknown effect operation"
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin" 2>"$tmp_err"
assert_contains "test_assertion_helpers_emit_passing_result" "$(<"$tmp_err")" "WEFT_TEST_RESULT 1 1 0 1"
echo "  ok test_assertion_helpers_pass"

printf 'test "path" { Test.assert_eq(21 + 21, 42) }\n' > "$tmp_src"
run_weft_compile_guarded "$WEFT" test --emit "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_not_contains_file "test_path_compiles_strict_source" "$tmp_err" "type error:"
if grep -aFq -- "$tmp_src" "$tmp_bin"; then
  echo "  ok test_path_emit_embeds_origin_path"
else
  echo "  fail test_path_emit_embeds_origin_path"
  exit 1
fi
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin" 2>"$tmp_err"
assert_contains "test_path_binary_emits_passing_result" "$(<"$tmp_err")" "WEFT_TEST_RESULT 1 1 0 1"
echo "  ok test_path_binary_runs"

run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
assert_not_contains_file "test_stdin_emit_omits_path_origin" "$tmp_out" "$tmp_src"
if cmp -s "$tmp_bin" "$tmp_out"; then
  echo "  fail test_path_emit_records_origin"
  exit 1
else
  echo "  ok test_path_emit_records_origin"
fi
chmod +x "$tmp_out"
run_binary_guarded "$tmp_out" 2>"$tmp_err"
assert_contains "test_stdin_emit_preserves_behavior" "$(<"$tmp_err")" "WEFT_TEST_RESULT 1 1 0 1"

set +e
run_weft_compile_guarded "$WEFT" test "$tmp_src" > "$tmp_out" 2>"$tmp_err"
test_path_native_exit=$?
set -e
assert_equals "test_path_native_exit_zero" "$test_path_native_exit" "0"
assert_equals "test_path_native_stdout_empty" "$(<"$tmp_out")" ""
test_path_native_err=$(<"$tmp_err")
assert_contains "test_path_native_reports_pass" "$test_path_native_err" "  pass: $tmp_src ("
assert_contains "test_path_native_reports_summary" "$test_path_native_err" "1 passed, 0 failed"
assert_contains "test_path_native_consumes_structured_result" "$test_path_native_err" "WEFT_TEST_RESULT 1 1 0 1"
assert_not_contains "test_path_native_omits_metrics_by_default" "$test_path_native_err" "WEFT_TEST_METRICS"

printf 'test "mixed modern root" { Test.assert_eq(6 * 7, 42) }\n' > "$tmp_test_shared_two"
set +e
run_weft_compile_guarded "$WEFT" test --jobs 2 test/parse_test.weft "$tmp_test_shared_two" > "$tmp_out" 2> "$tmp_err"
test_legacy_mixed_exit=$?
set -e
assert_equals "test_legacy_expected_exit_mixes_with_modern_root" "$test_legacy_mixed_exit" "0"
assert_contains "test_legacy_expected_exit_reports_pass" "$(<"$tmp_err")" "  pass: test/parse_test.weft ("
assert_contains "test_legacy_expected_exit_supplies_eof_stdin" "$(<"$tmp_err")" "2 passed, 0 failed"
assert_contains "test_legacy_mixed_root_preserves_structured_result" "$(<"$tmp_err")" "WEFT_TEST_RESULT 1 1 0 1"

printf '%s\n' '-- Expected exit code: 41' 'fn main() -> i64 { 42 }' > "$tmp_test_shared_one"
set +e
run_weft_compile_guarded "$WEFT" test --jobs 1 "$tmp_test_shared_one" > "$tmp_out" 2> "$tmp_err"
test_legacy_mismatch_exit=$?
set -e
assert_equals "test_legacy_expected_exit_mismatch_fails" "$test_legacy_mismatch_exit" "1"
assert_contains "test_legacy_expected_exit_mismatch_is_exact" "$(<"$tmp_err")" "legacy main exited 42, expected 41"

printf '%s\n' '-- Expected exit code: 124' 'fn main() -> i64 { 42 }' > "$tmp_test_shared_one"
set +e
run_weft_compile_guarded "$WEFT" test --jobs 1 "$tmp_test_shared_one" > "$tmp_out" 2> "$tmp_err"
test_legacy_malformed_exit=$?
set -e
assert_equals "test_legacy_reserved_status_is_rejected" "$test_legacy_malformed_exit" "1"
assert_contains "test_legacy_reserved_status_explains_range" "$(<"$tmp_err")" "malformed legacy expected-exit directive (use 0..123)"

printf 'test "first failure" { Test.assert_eq(1, 2) }\n' > "$tmp_test_fail_one"
printf 'test "second failure" { Test.assert_true(false) }\n' > "$tmp_test_fail_two"
printf 'effect Maybe { fn none() -> i64 } fn local_maybe() -[Maybe]> i64 { Maybe.none() } test "runs after failure" { Test.assert_eq(handle local_maybe() { Maybe.none() -> 42 }, 42) }\n' > "$tmp_test_after"
set +e
run_weft_compile_guarded "$WEFT" test "$tmp_test_fail_one" "$tmp_test_after" "$tmp_test_fail_two" > "$tmp_out" 2>"$tmp_err"
test_path_multi_exit=$?
set -e
assert_equals "test_path_native_returns_boolean_failure" "$test_path_multi_exit" "1"
assert_equals "test_path_native_failure_stdout_empty" "$(<"$tmp_out")" ""
test_path_multi_err=$(<"$tmp_err")
assert_contains "test_path_native_preserves_assertion_diagnostic" "$test_path_multi_err" "test assertion failed: assert_eq"
assert_contains "test_path_native_preserves_expected_payload" "$test_path_multi_err" "  expected: 2"
assert_contains "test_path_native_preserves_actual_payload" "$test_path_multi_err" "  actual:   1"
assert_contains "test_path_native_reports_first_failure" "$test_path_multi_err" "  FAIL: $tmp_test_fail_one ("
assert_contains "test_path_native_continues_after_failure" "$test_path_multi_err" "  pass: $tmp_test_after ("
assert_contains "test_path_native_reports_second_failure" "$test_path_multi_err" "  FAIL: $tmp_test_fail_two ("
assert_contains "test_path_native_aggregates_summary" "$test_path_multi_err" "1 passed, 2 failed"

export WEFT_TEST_METRICS=1
set +e
run_weft_compile_guarded "$WEFT" test --jobs 1 "$tmp_test_after" > "$tmp_out" 2>"$tmp_err"
test_metrics_exit=$?
set -e
unset WEFT_TEST_METRICS
assert_equals "test_metrics_exit_zero" "$test_metrics_exit" "0"
test_metrics_err=$(<"$tmp_err")
test_metrics_line=$(grep '^WEFT_TEST_METRICS ' "$tmp_err")
read -r metric_tag metric_version metric_roots metric_measured metric_wall metric_discovery metric_planning metric_compile metric_link metric_run metric_user metric_system metric_peak metric_shared_groups metric_shared_roots metric_reused_pairs metric_query_hits metric_query_misses metric_query_executions metric_extra <<< "$test_metrics_line"
assert_equals "test_metrics_machine_schema_version" "$metric_tag:$metric_version" "WEFT_TEST_METRICS:2"
assert_equals "test_metrics_machine_counts_root" "$metric_roots:$metric_measured" "1:1"
assert_equals "test_metrics_single_root_has_no_shared_product" "$metric_shared_groups:$metric_shared_roots:$metric_reused_pairs" "0:0:0"
assert_equals "test_metrics_single_root_has_no_project_queries" "$metric_query_hits:$metric_query_misses:$metric_query_executions" "0:0:0"
assert_equals "test_metrics_machine_schema_has_exact_fields" "$metric_extra" ""
if [[ "$metric_wall" =~ ^[0-9]+$ ]] && [[ "$metric_compile" =~ ^[0-9]+$ ]] && [[ "$metric_user" =~ ^[0-9]+$ ]] && [[ "$metric_peak" =~ ^[0-9]+$ ]] && [ "$metric_wall" -gt 0 ] && [ "$metric_compile" -gt 0 ] && [ "$metric_user" -gt 0 ] && [ "$metric_peak" -gt 0 ]; then
  echo "  ok test_metrics_machine_reports_positive_resources"
else
  echo "  fail test_metrics_machine_reports_positive_resources"
  echo "    metrics: $test_metrics_line"
  exit 1
fi
assert_contains "test_metrics_human_summary_names_phase_and_resource_fields" "$test_metrics_err" "test metrics: roots=1 measured=1 wall_ms="

printf 'test "timeout" { while true { Test.assert_eq(1, 1) } }\n' > "$tmp_test_timeout"
set +e
env WEFT_TEST_COMPILE_TIMEOUT=30 WEFT_TEST_RUN_TIMEOUT=1 "$WEFT" test --jobs 1 "$tmp_test_timeout" > "$tmp_out" 2>"$tmp_err"
test_timeout_exit=$?
set -e
assert_equals "test_timeout_returns_failure" "$test_timeout_exit" "1"
test_timeout_err=$(<"$tmp_err")
assert_contains "test_timeout_preserves_exact_worker_status" "$test_timeout_err" "  FAIL: $tmp_test_timeout ("
assert_contains "test_timeout_reports_reason" "$test_timeout_err" ", timeout)"

set +e
env WEFT_TEST_COMPILE_RSS_LIMIT_KB=1 "$WEFT" test --jobs 1 "$tmp_test_after" > "$tmp_out" 2>"$tmp_err"
test_rss_exit=$?
set -e
assert_equals "test_rss_limit_returns_failure" "$test_rss_exit" "1"
test_rss_err=$(<"$tmp_err")
assert_contains "test_rss_limit_reports_peak_and_limit" "$test_rss_err" "KB exceeded limit"
assert_contains "test_rss_limit_reports_failed_summary" "$test_rss_err" "0 passed, 1 failed"

set +e
env WEFT_TEST_COMPILE_RSS_LIMIT_KB=1 "$WEFT" test --jobs 1 "$tmp_test_fail_one" > "$tmp_out" 2>"$tmp_err"
test_failure_rss_exit=$?
set -e
assert_equals "test_semantic_failure_with_rss_overage_returns_failure" "$test_failure_rss_exit" "1"
assert_not_contains_file "test_semantic_failure_precedes_rss_overage" "$tmp_err" "peak RSS"

printf 'pub fn shared_value() -> i64 { 42 }\n' > "$tmp_test_shared_support"
printf 'use module_fixtures/%s.{shared_value} test "shared one" { Test.assert_eq(shared_value(), 42) }\n' "$tmp_test_shared_module" > "$tmp_test_shared_one"
printf 'use module_fixtures/%s.{shared_value} test "shared two" { Test.assert_eq(shared_value(), 42) }\n' "$tmp_test_shared_module" > "$tmp_test_shared_two"
set +e
export WEFT_TEST_PLAN_TRACE=1
run_weft_compile_guarded "$WEFT" test --jobs 1 "$tmp_test_shared_one" "$tmp_test_shared_two" > "$tmp_out" 2>"$tmp_err"
test_shared_roots_exit=$?
unset WEFT_TEST_PLAN_TRACE
set -e
assert_equals "test_batch_shared_module_exit_zero" "$test_shared_roots_exit" "0"
assert_contains "test_batch_shared_module_runs_both_roots" "$(<"$tmp_err")" "2 passed, 0 failed"
assert_contains "test_batch_tiny_dependency_stays_below_reuse_threshold" "$(<"$tmp_err")" "test plan: shared checked dependency groups=0 roots=0"

printf 'pub type BatchSharedBox { value: i64 }\nimpl BatchSharedBox { pub fn value(self: BatchSharedBox) -> i64 { self.value } }\n' > "$tmp_test_shared_support"
batch_pad=0
while [ "$batch_pad" -lt 32 ]; do
  printf 'pub fn batch_pad_%s() -> i64 { %s }\n' "$batch_pad" "$batch_pad" >> "$tmp_test_shared_support"
  batch_pad=$((batch_pad + 1))
done
printf 'use module_fixtures/%s.{BatchSharedBox} test "checked dependency one" { Test.assert_eq(BatchSharedBox { value: 41 }.value(), 41) }\n' "$tmp_test_shared_module" > "$tmp_test_shared_one"
printf 'use module_fixtures/%s.{BatchSharedBox} test "checked dependency two" { Test.assert_eq(BatchSharedBox { value: 42 }.value(), 42) }\n' "$tmp_test_shared_module" > "$tmp_test_shared_two"
set +e
export WEFT_TEST_PLAN_TRACE=1
export WEFT_TEST_METRICS=1
run_weft_compile_guarded "$WEFT" test --jobs 1 "$tmp_test_shared_one" "$tmp_test_shared_two" > "$tmp_out" 2>"$tmp_err"
test_checked_dependency_exit=$?
unset WEFT_TEST_PLAN_TRACE
unset WEFT_TEST_METRICS
set -e
assert_equals "test_batch_checked_dependency_exit_zero" "$test_checked_dependency_exit" "0"
assert_contains "test_batch_checked_dependency_admits_exact_group" "$(<"$tmp_err")" "test plan: shared checked dependency groups=1 roots=2"
assert_contains "test_batch_checked_dependency_runs_both_roots" "$(<"$tmp_err")" "2 passed, 0 failed"
assert_not_contains_file "test_batch_checked_dependency_has_no_missing_method" "$tmp_err" "missing method implementation"
checked_dependency_metrics=$(grep '^WEFT_TEST_METRICS ' "$tmp_err")
read -r dependency_metric_tag dependency_metric_version dependency_metric_roots dependency_metric_measured dependency_metric_wall dependency_metric_discovery dependency_metric_planning dependency_metric_compile dependency_metric_link dependency_metric_run dependency_metric_user dependency_metric_system dependency_metric_peak dependency_metric_groups dependency_metric_shared_roots dependency_metric_reused_pairs dependency_metric_hits dependency_metric_misses dependency_metric_executions dependency_metric_extra <<< "$checked_dependency_metrics"
assert_equals "test_batch_checked_dependency_metrics_schema" "$dependency_metric_tag:$dependency_metric_version:$dependency_metric_extra" "WEFT_TEST_METRICS:2:"
assert_equals "test_batch_checked_dependency_metrics_group" "$dependency_metric_groups:$dependency_metric_shared_roots" "1:2"
if [[ "$dependency_metric_reused_pairs" =~ ^[0-9]+$ ]] && [[ "$dependency_metric_hits" =~ ^[0-9]+$ ]] && [[ "$dependency_metric_misses" =~ ^[0-9]+$ ]] && [[ "$dependency_metric_executions" =~ ^[0-9]+$ ]] && [ "$dependency_metric_reused_pairs" -ge 32 ] && [ "$dependency_metric_hits" -gt 0 ] && [ "$dependency_metric_misses" -gt 0 ] && [ "$dependency_metric_executions" -gt 0 ]; then
  echo "  ok test_batch_checked_dependency_metrics_report_reuse"
else
  echo "  fail test_batch_checked_dependency_metrics_report_reuse"
  echo "    metrics: $checked_dependency_metrics"
  exit 1
fi

printf 'trait BatchLocal { fn get(self: BatchBox) -> i64 } type BatchBox { value: i64 } impl BatchLocal for BatchBox { fn get(self: BatchBox) -> i64 { self.value } } test "isolated one" { Test.assert_eq(BatchBox { value: 41 }.get(), 41) }\n' > "$tmp_test_shared_one"
printf 'trait BatchLocal { fn get(self: BatchBox) -> i64 } type BatchBox { value: i64 } impl BatchLocal for BatchBox { fn get(self: BatchBox) -> i64 { self.value } } test "isolated two" { Test.assert_eq(BatchBox { value: 42 }.get(), 42) }\n' > "$tmp_test_shared_two"
set +e
run_weft_compile_guarded "$WEFT" test --jobs 1 "$tmp_test_shared_one" "$tmp_test_shared_two" > "$tmp_out" 2>"$tmp_err"
test_isolated_roots_exit=$?
set -e
assert_equals "test_batch_same_named_roots_exit_zero" "$test_isolated_roots_exit" "0"
assert_contains "test_batch_same_named_roots_stay_isolated" "$(<"$tmp_err")" "2 passed, 0 failed"

printf 'use "removed/quoted/import.weft"\n' > "$tmp_test_parse_fail"
set +e
run_weft_compile_guarded "$WEFT" test --jobs 1 "$tmp_test_parse_fail" "$tmp_test_after" > "$tmp_out" 2>"$tmp_err"
test_parse_then_pass_exit=$?
set -e
test_parse_then_pass_err=$(<"$tmp_err")
assert_equals "test_batch_parse_failure_returns_one" "$test_parse_then_pass_exit" "1"
assert_contains "test_batch_parse_failure_preserves_diagnostic" "$test_parse_then_pass_err" "expected path-form module after 'use'"
assert_contains "test_batch_parse_failure_rotates_and_continues" "$test_parse_then_pass_err" "  pass: $tmp_test_after ("
assert_contains "test_batch_parse_failure_aggregates_summary" "$test_parse_then_pass_err" "1 passed, 1 failed"

printf 'test "directory a" { Test.assert_eq(1, 1) }\n' > "$tmp_test_dir/a_pass.weft"
printf 'test "directory b" { Test.assert_eq(2, 2) }\n' > "$tmp_test_dir/b_pass.weft"
mkdir -p "$tmp_test_dir/nested/deeper" "$tmp_test_dir/empty"
printf 'test "directory nested" { Test.assert_eq(3, 3) }\n' > "$tmp_test_dir/nested/c_pass.weft"
printf 'test "directory deep" { Test.assert_eq(4, 4) }\n' > "$tmp_test_dir/nested/deeper/d_pass.weft"
ln -s "$tmp_test_dir" "$tmp_test_dir/nested/loop"
printf 'not a test source\n' > "$tmp_test_dir/ignored.txt"
set +e
run_weft_compile_guarded "$WEFT" test --jobs 2 "$tmp_test_dir" > "$tmp_out" 2>"$tmp_err"
test_dir_exit=$?
set -e
assert_equals "test_directory_native_exit_zero" "$test_dir_exit" "0"
assert_equals "test_directory_native_stdout_empty" "$(<"$tmp_out")" ""
test_dir_err=$(<"$tmp_err")
assert_contains "test_directory_discovers_a" "$test_dir_err" "  pass: $tmp_test_dir/a_pass.weft ("
assert_contains "test_directory_discovers_b" "$test_dir_err" "  pass: $tmp_test_dir/b_pass.weft ("
assert_contains "test_directory_discovers_nested" "$test_dir_err" "  pass: $tmp_test_dir/nested/c_pass.weft ("
assert_contains "test_directory_discovers_deep" "$test_dir_err" "  pass: $tmp_test_dir/nested/deeper/d_pass.weft ("
assert_contains "test_directory_reports_summary" "$test_dir_err" "4 passed, 0 failed"
assert_not_contains "test_directory_ignores_non_weft" "$test_dir_err" "ignored.txt"
assert_not_contains "test_directory_breaks_symlink_cycles" "$test_dir_err" "/nested/loop/"

set +e
run_weft_compile_guarded "$WEFT" test --jobs 1 "$tmp_test_dir" > "$tmp_out" 2>"$tmp_err"
test_dir_order_exit=$?
set -e
assert_equals "test_directory_order_exit_zero" "$test_dir_order_exit" "0"
a_line=$(grep -nF "  pass: $tmp_test_dir/a_pass.weft (" "$tmp_err" | cut -d: -f1)
b_line=$(grep -nF "  pass: $tmp_test_dir/b_pass.weft (" "$tmp_err" | cut -d: -f1)
c_line=$(grep -nF "  pass: $tmp_test_dir/nested/c_pass.weft (" "$tmp_err" | cut -d: -f1)
d_line=$(grep -nF "  pass: $tmp_test_dir/nested/deeper/d_pass.weft (" "$tmp_err" | cut -d: -f1)
if [ "$a_line" -lt "$b_line" ] && [ "$b_line" -lt "$c_line" ] && [ "$c_line" -lt "$d_line" ]; then
  echo "  ok test_directory_order_is_deterministic"
else
  echo "  fail test_directory_order_is_deterministic"
  exit 1
fi

test_glob="$tmp_test_dir/?_pass.weft"
set +e
run_weft_compile_guarded "$WEFT" test --jobs 2 "$test_glob" > "$tmp_out" 2>"$tmp_err"
test_glob_exit=$?
set -e
assert_equals "test_glob_native_exit_zero" "$test_glob_exit" "0"
assert_contains "test_glob_discovers_matches" "$(<"$tmp_err")" "2 passed, 0 failed"

set +e
run_weft_compile_guarded "$WEFT" test --jobs 2 "$tmp_test_dir/a_pass.weft" "$tmp_test_dir" > "$tmp_out" 2>"$tmp_err"
test_overlap_exit=$?
set -e
assert_equals "test_directory_overlap_exit_zero" "$test_overlap_exit" "0"
assert_contains "test_directory_overlap_deduplicates" "$(<"$tmp_err")" "4 passed, 0 failed"

test_no_match="$tmp_test_dir/nope*.weft"
set +e
run_weft_compile_guarded "$WEFT" test "$test_no_match" > "$tmp_out" 2>"$tmp_err"
test_no_match_exit=$?
set -e
assert_equals "test_glob_no_match_exits_one" "$test_no_match_exit" "1"
assert_contains "test_glob_no_match_reports_pattern" "$(<"$tmp_err")" "test: no test files matched: $test_no_match"

set +e
run_weft_compile_guarded "$WEFT" test --jobs 0 "$tmp_test_dir/a_pass.weft" > "$tmp_out" 2>"$tmp_err"
test_jobs_exit=$?
set -e
assert_equals "test_jobs_rejects_zero" "$test_jobs_exit" "1"
assert_contains "test_jobs_reports_valid_range" "$(<"$tmp_err")" "test: --jobs must be an integer from 1 to 64"

run_weft_compile_guarded "$WEFT" compile tools/test_runner.weft > "$tmp_tool_obj" 2>"$tmp_err"
/usr/bin/ld -o "$tmp_tool_bin" "$tmp_tool_obj" -lSystem \
  -syslibroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
  -e _main -arch arm64 -platform_version macos 11.0 15.0 2>/dev/null
codesign -s - "$tmp_tool_bin"
echo "  ok test_runner_capability_tool_builds"

if grep -Eq '/bin/sh|runner_command|sh -c' tools/test_runner.weft; then
  echo "  fail test_runner_capability_tool_has_no_shell_pipeline"
  exit 1
else
  echo "  ok test_runner_capability_tool_has_no_shell_pipeline"
fi

set +e
run_binary_guarded "$tmp_tool_bin" "$WEFT_ABS" "$tmp_test_dir/a_pass.weft" "$tmp_test_dir/b_pass.weft" > "$tmp_out" 2>"$tmp_err"
test_tool_explicit_exit=$?
set -e
assert_equals "test_runner_capability_tool_explicit_exit_zero" "$test_tool_explicit_exit" "0"
assert_equals "test_runner_capability_tool_stdout_empty" "$(<"$tmp_out")" ""
assert_contains "test_runner_capability_tool_explicit_summary" "$(<"$tmp_err")" "2 passed, 0 failed"

set +e
run_binary_guarded "$tmp_tool_bin" "$WEFT_ABS" "$tmp_test_dir" > "$tmp_out" 2>"$tmp_err"
test_tool_dir_exit=$?
set -e
assert_equals "test_runner_capability_tool_directory_exit_zero" "$test_tool_dir_exit" "0"
test_tool_dir_err=$(<"$tmp_err")
assert_contains "test_runner_capability_tool_directory_summary" "$test_tool_dir_err" "4 passed, 0 failed"
assert_contains "test_runner_capability_tool_discovers_nested" "$test_tool_dir_err" "  pass: $tmp_test_dir/nested/c_pass.weft ("
assert_contains "test_runner_capability_tool_discovers_deep" "$test_tool_dir_err" "  pass: $tmp_test_dir/nested/deeper/d_pass.weft ("
assert_not_contains "test_runner_capability_tool_breaks_symlink_cycles" "$test_tool_dir_err" "/nested/loop/"

set +e
run_binary_guarded "$tmp_tool_bin" "$WEFT_ABS" "$tmp_test_fail_one" > "$tmp_out" 2>"$tmp_err"
test_tool_failure_exit=$?
set -e
assert_equals "test_runner_capability_tool_failure_exit_one" "$test_tool_failure_exit" "1"
test_tool_failure_err=$(<"$tmp_err")
assert_contains "test_runner_capability_tool_preserves_diagnostic" "$test_tool_failure_err" "test assertion failed: assert_eq"
assert_contains "test_runner_capability_tool_preserves_expected_payload" "$test_tool_failure_err" "  expected: 2"
assert_contains "test_runner_capability_tool_preserves_actual_payload" "$test_tool_failure_err" "  actual:   1"
assert_contains "test_runner_capability_tool_consumes_structured_result" "$test_tool_failure_err" "WEFT_TEST_RESULT 1 0 1 1"
assert_contains "test_runner_capability_tool_failure_summary" "$test_tool_failure_err" "0 passed, 1 failed"

printf '#!/bin/sh\nexit 0\n' > "$tmp_fake_weft"
chmod +x "$tmp_fake_weft"
set +e
run_binary_guarded "$tmp_tool_bin" "$tmp_fake_weft" "$tmp_test_dir/a_pass.weft" > "$tmp_out" 2>"$tmp_err"
test_tool_protocol_exit=$?
set -e
assert_equals "test_runner_capability_tool_rejects_missing_result" "$test_tool_protocol_exit" "1"
assert_contains "test_runner_capability_tool_reports_protocol_failure" "$(<"$tmp_err")" "invalid test-result protocol"

printf 'test "raw" { let p = __bump_alloc(8) Test.assert_eq(p, p) }\n' > "$tmp_src"
test_path_raw_out=$(run_weft_compile_guarded "$WEFT" test "$tmp_src" > "$tmp_bin" 2>"$tmp_err" || true; cat "$tmp_err")
assert_contains "test_path_rejects_root_raw_memory" "$test_path_raw_out" "type error: raw allocation is sealed to trusted runtime/platform code"

test_stdin_raw_out=$(run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err" || true; cat "$tmp_err")
assert_contains "test_stdin_rejects_root_raw_memory" "$test_stdin_raw_out" "type error: raw allocation is sealed to trusted runtime/platform code"

printf 'pub fn leaked() -> i64 { __mem_load64(0) }\n' > "$tmp_compiler_probe"
compiler_probe_root_out=$("$WEFT" check "$tmp_compiler_probe" 2>&1 || true)
assert_contains "compiler_unlisted_root_rejects_raw_memory" "$compiler_probe_root_out" "type error: Unsafe is sealed to trusted runtime/platform code"

printf 'use compiler/_weft_trust_probe_%s.{*}\nfn main() -> i64 { leaked() }\n' "$$" > "$tmp_src"
compiler_probe_import_out=$("$WEFT" check "$tmp_src" 2>&1 || true)
assert_contains "compiler_unlisted_import_rejects_raw_memory" "$compiler_probe_import_out" "type error: Unsafe is sealed to trusted runtime/platform code"
rm -f "$tmp_compiler_probe"

printf 'pub fn leaked() -> i64 { __mem_load64(0) }\n' > "$tmp_runtime_probe"
runtime_probe_root_out=$("$WEFT" check "$tmp_runtime_probe" 2>&1 || true)
assert_contains "runtime_unlisted_root_rejects_raw_memory" "$runtime_probe_root_out" "type error: Unsafe is sealed to trusted runtime/platform code"

printf 'use runtime/_weft_trust_probe_%s.{*}\nfn main() -> i64 { leaked() }\n' "$$" > "$tmp_src"
runtime_probe_import_out=$("$WEFT" check "$tmp_src" 2>&1 || true)
assert_contains "runtime_unlisted_import_rejects_raw_memory" "$runtime_probe_import_out" "type error: Unsafe is sealed to trusted runtime/platform code"
rm -f "$tmp_runtime_probe"

printf 'pub fn leaked() -> i64 { __mem_load64(0) }\n' > "$tmp_stdlib_probe"
stdlib_probe_root_out=$("$WEFT" check "$tmp_stdlib_probe" 2>&1 || true)
assert_contains "stdlib_unlisted_root_rejects_raw_memory" "$stdlib_probe_root_out" "type error: Unsafe is sealed to trusted runtime/platform code"

printf 'use stdlib/_weft_trust_probe_%s.{*}\nfn main() -> i64 { leaked() }\n' "$$" > "$tmp_src"
stdlib_probe_import_out=$("$WEFT" check "$tmp_src" 2>&1 || true)
assert_contains "stdlib_unlisted_import_rejects_raw_memory" "$stdlib_probe_import_out" "type error: Unsafe is sealed to trusted runtime/platform code"
rm -f "$tmp_stdlib_probe"

assert_test_exit_code "test_assert_eq_failure_returns_one" 'test "fail_eq" { Test.assert_eq(1, 2) }' 1
assert_test_exit_code "test_assert_eq_and_ne_two_clause_harness_runs" 'test "eq_ne" { Test.assert_eq(0, 0) Test.assert_ne(1, 2) }' 0
assert_test_exit_code "test_assert_ne_failure_returns_one" 'test "fail_ne" { Test.assert_ne(2, 2) }' 1
assert_test_exit_code "test_assert_bool_failures_return_boolean" $'test "fail_true" { Test.assert_true(1 == 2) }\ntest "fail_false" { Test.assert_false(1 == 1) }' 1
assert_test_exit_code "test_assert_comparison_failure_returns_one" 'test "fail_cmp" { Test.assert_lt(2, 1) }' 1

printf '%s\n' $'test "first named failure" { Test.assert_eq(1, 2) }\ntest "passing middle" { Test.assert_eq(3, 3) }\ntest "last named failure" { Test.assert_true(false) }' > "$tmp_src"
run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
chmod +x "$tmp_bin"
set +e
run_binary_guarded "$tmp_bin" >/dev/null 2>"$tmp_err"
test_named_failures_exit=$?
set -e
assert_equals "test_named_failures_return_boolean" "$test_named_failures_exit" "1"
test_named_failures_err=$(<"$tmp_err")
assert_contains "test_named_failures_report_structured_counts" "$test_named_failures_err" "WEFT_TEST_RESULT 1 1 2 3"
assert_contains "test_named_failures_reports_first_name" "$test_named_failures_err" "test failure: first named failure"
assert_contains "test_named_failures_reports_first_detail" "$test_named_failures_err" "test assertion failed: assert_eq"
assert_contains "test_named_failures_reports_first_expected" "$test_named_failures_err" "  expected: 2"
assert_contains "test_named_failures_reports_first_actual" "$test_named_failures_err" "  actual:   1"
assert_contains "test_named_failures_continues_past_pass" "$test_named_failures_err" "test failure: last named failure"
assert_contains "test_named_failures_reports_last_detail" "$test_named_failures_err" "test assertion failed: assert_true"
assert_contains "test_named_failures_reports_last_expected" "$test_named_failures_err" "  expected: true"
assert_contains "test_named_failures_reports_last_actual" "$test_named_failures_err" "  actual:   false"
assert_not_contains "test_named_failures_omits_passing_name" "$test_named_failures_err" "test failure: passing middle"

assert_test_failure_contains "test_assertion_failure_reports_diagnostic" 'test "fail_eq_diag" { Test.assert_eq(1, 2) }' 1 "test assertion failed: assert_eq"
assert_test_failure_contains "test_assert_eq_f64_failure_reports_diagnostic" 'test "fail_eq_f64" { Test.assert_eq_f64(1.0, 2.0) }' 1 "test assertion failed: assert_eq_f64"
assert_test_failure_contains "test_assert_eq_f64_failure_reports_expected" 'test "fail_eq_f64" { Test.assert_eq_f64(1.25, 2.5) }' 1 "  expected: 2.5"
assert_test_failure_contains "test_assert_eq_f64_failure_reports_actual" 'test "fail_eq_f64" { Test.assert_eq_f64(1.25, 2.5) }' 1 "  actual:   1.25"
assert_test_failure_contains "test_assert_eq_f64_nan_fails" 'test "fail_eq_f64_nan" { Test.assert_eq_f64(0.0 / 0.0, 0.0 / 0.0) }' 1 "test assertion failed: assert_eq_f64"
assert_test_failure_contains "test_assert_near_f64_outside_epsilon_fails" 'test "fail_near_f64" { Test.assert_near_f64(1.0, 1.5, 0.25) }' 1 "test assertion failed: assert_near_f64"
assert_test_failure_contains "test_assert_near_f64_reports_epsilon" 'test "fail_near_f64" { Test.assert_near_f64(1.0, 1.5, 0.25) }' 1 "  epsilon:  0.25"
assert_test_failure_contains "test_assert_near_f64_negative_epsilon_fails" 'test "fail_near_f64_epsilon" { Test.assert_near_f64(1.0, 1.0, 0.0 - 0.1) }' 1 "test assertion failed: assert_near_f64"
assert_test_failure_contains "test_snapshot_mismatch_reports_diagnostic" 'test "fail_snapshot" { Test.assert_snapshot("actual", "expected") }' 1 "test assertion failed: snapshot"
assert_test_failure_contains "test_property_failure_reports_diagnostic" 'test "fail_property" { Test.forall_i64_range(0, 4, x => x < 2) }' 1 "test assertion failed: forall_i64_range"
assert_test_failure_contains "test_property_failure_reports_counterexample" 'test "fail_property" { Test.forall_i64_range(0, 4, x => x < 2) }' 1 "  counterexample: 2"
assert_test_failure_contains "test_property_empty_range_reports_exhaustion" 'test "empty_property" { Test.forall_i64_range(3, 3, x => true) }' 1 "test assertion failed: forall_i64_range_empty"
assert_test_exit_code "test_effect_fixtures_pass" 'use stdlib/diagnostic_type.{Diagnose} fn tool_fail8() -[Fail<i64>]> i64 { Fail.fail(8) } test "fixtures" { Test.assert_eq(Test.with_state_i64(2, () => { TestState.put(TestState.get() + 1) TestState.get() }), 3) Test.assert_eq(Test.expect_fail_i64(8, () => tool_fail8()), 8) Test.assert_eq(Test.with_io_i64(() => IO.open("path", 7, 0)), 107) Test.assert_eq(Test.with_diagnose_i64(() => Diagnose.note("ok", 0)), 3) }' 0
assert_test_failure_contains "test_fixture_missing_fail_reports_diagnostic" 'test "missing_fail" { Test.expect_fail_i64(1, () => 0) }' 1 "test assertion failed: expect_fail_missing"
assert_test_failure_contains "test_fixture_wrong_fail_reports_diagnostic" 'fn tool_fail2() -[Fail<i64>]> i64 { Fail.fail(2) } test "wrong_fail" { Test.expect_fail_i64(1, () => tool_fail2()) }' 1 "test assertion failed: expect_fail_i64"
assert_test_failure_contains "test_fixture_wrong_fail_reports_expected" 'fn tool_fail2() -[Fail<i64>]> i64 { Fail.fail(2) } test "wrong_fail" { Test.expect_fail_i64(1, () => tool_fail2()) }' 1 "  expected: 1"
assert_test_failure_contains "test_fixture_wrong_fail_reports_actual" 'fn tool_fail2() -[Fail<i64>]> i64 { Fail.fail(2) } test "wrong_fail" { Test.expect_fail_i64(1, () => tool_fail2()) }' 1 "  actual:   2"

assert_test_failure_contains "test_string_diff_reports_byte" 'test "string_diff" { Test.assert_str_eq("a\nsnow", "a\nrain") }' 1 "  diff at byte 2:"
assert_test_failure_contains "test_string_diff_reports_expected" 'test "string_diff" { Test.assert_str_eq("a\nsnow", "a\nrain") }' 1 '    - expected "a\nrain"'
assert_test_failure_contains "test_string_diff_reports_actual" 'test "string_diff" { Test.assert_str_eq("a\nsnow", "a\nrain") }' 1 '    + actual   "a\nsnow"'
assert_test_failure_contains "test_string_ne_reports_equal_value" 'test "string_ne" { Test.assert_str_ne("same\n", "same\n") }' 1 '  value was unexpectedly equal: "same\n"'

vector_diff_source='use stdlib/vector.{*} test "vector_diff" { let actual = vector_new<i64>() vector_push<i64>(actual, 1) vector_push<i64>(actual, 2) vector_push<i64>(actual, 3) vector_push<i64>(actual, 4) let expected = vector_new<i64>() vector_push<i64>(expected, 1) vector_push<i64>(expected, 9) vector_push<i64>(expected, 3) Test.assert_i64_vector_eq(actual, expected) }'
assert_test_failure_contains "test_vector_diff_reports_header" "$vector_diff_source" 1 "test assertion failed: assert_i64_vector_eq"
assert_test_failure_contains "test_vector_diff_reports_index_and_lengths" "$vector_diff_source" 1 "  collection diff at index 1 (expected length 3, actual length 4):"
assert_test_failure_contains "test_vector_diff_reports_expected" "$vector_diff_source" 1 "    - expected [1, 9, 3]"
assert_test_failure_contains "test_vector_diff_reports_actual" "$vector_diff_source" 1 "    + actual   [1, 2, 3, 4]"
assert_test_compile_rejects "test_assert_true_rejects_i64" 'test "bad_bool" { Test.assert_true(2) }' 'error[E1002]: argument type mismatch: expected `bool`, found `i64`'
assert_test_compile_rejects "test_assert_str_eq_rejects_i64" 'test "bad_str" { Test.assert_str_eq(1, "one") }' 'error[E1002]: argument type mismatch: expected `str`, found `i64`'
assert_test_compile_rejects "test_assert_eq_f64_rejects_i64" 'test "bad_f64" { Test.assert_eq_f64(1, 1.0) }' 'error[E1002]: argument type mismatch: expected `f64`, found `i64`'
assert_test_compile_rejects "test_assert_near_f64_rejects_i64_epsilon" 'test "bad_f64_epsilon" { Test.assert_near_f64(1.0, 1.0, 1) }' 'error[E1002]: argument type mismatch: expected `f64`, found `i64`'
assert_test_compile_rejects "test_assert_i64_vector_rejects_wrong_element_type" 'use stdlib/vector.{*} test "bad_vector" { let a = vector_new<str>() let b = vector_new<str>() Test.assert_i64_vector_eq(a, b) }' 'error[E1002]: argument type mismatch: expected `Vector<i64>`, found `Vector<str>`'
assert_test_compile_rejects "test_property_rejects_i64_predicate" 'test "bad_property" { Test.forall_i64_range(0, 1, x => x + 1) }' 'error[E1002]: lambda return value type mismatch: expected `bool`, found `i64`'
assert_test_compile_rejects "test_property_rejects_effectful_predicate" $'effect Log { fn hit() -> i64 }\ntest "bad_property_effect" { Test.forall_i64_range(0, 1, x => Log.hit() == x) }' "error[E2001]:"
assert_test_compile_rejects "test_fixture_rejects_unhandled_state" 'test "bad_state" { TestState.get() }' "error[E2001]:"
assert_test_compile_rejects "test_fixture_rejects_wrong_effect_body" 'test "bad_fixture_effect" { Test.with_state_i64(0, () => IO.write(1, 0, 1)) }' "error[E2001]:"
assert_test_compile_rejects "test_fixture_rejects_wrong_return_body" 'test "bad_fixture_return" { Test.with_io_i64(() => "nope") }' 'error[E1002]: lambda return value type mismatch: expected `i64`, found `str`'

# Emission errors must fail the compile (exit nonzero, no binary written).
# Compiling a constructor-allocating program from a directory without the
# runtime tree leaves rc_default_alloc_masked unbound; before the fix this
# printed the error but exited 0 with a poisoned (BRK-carrying) binary.
printf 'type Pair {\n  MkPair(i64, i64)\n}\nfn main() -> i64 {\n  let p = MkPair(40, 2)\n  match p { MkPair(a, b) -> a + b }\n}\n' > "$tmp_outside_dir/emit_fail.weft"
set +e
(cd "$tmp_outside_dir" && "$WEFT_ABS" compile emit_fail.weft > emit_fail.bin 2> emit_fail.err)
emit_fail_exit=$?
set -e
emit_fail_err=$(<"$tmp_outside_dir/emit_fail.err")
if [ "$emit_fail_exit" != "0" ]; then
  echo "  ok compile_emission_error_exits_nonzero"
else
  echo "  fail compile_emission_error_exits_nonzero"
  echo "    expected nonzero exit, got 0"
  exit 1
fi
assert_contains "compile_emission_error_reports_missing_runtime_fn" "$emit_fail_err" "required runtime function unavailable"
assert_equals "compile_emission_error_writes_no_binary" "$(wc -c < "$tmp_outside_dir/emit_fail.bin" | tr -d ' ')" "0"

# The authoritative Mach-O fixture must emit a signed, runnable nested binary.
run_weft_compile_guarded "$WEFT" compile test/emit_test.weft > "$tmp_bin" 2>"$tmp_err"
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin" > "$tmp_out" 2>"$tmp_err"
assert_contains "signed_emitter_writes_macho" "$(/usr/bin/file -b "$tmp_out")" "Mach-O 64-bit executable arm64"
codesign -v "$tmp_out"
echo "  ok signed_emitter_embeds_valid_signature"
chmod +x "$tmp_out"
set +e
run_binary_guarded "$tmp_out" >/dev/null 2>"$tmp_err"
signed_emitter_exit=$?
set -e
assert_equals "signed_emitter_nested_binary_exits_42" "$signed_emitter_exit" "42"

: > "$tmp_src"
for ((i = 0; i < 1800; i++)); do
  printf 'test "t%d" { Test.assert_eq(1, 1) }\n' "$i" >> "$tmp_src"
done
large_test_check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reads_large_test_harness" "$large_test_check_out" "0 errors"
run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>/dev/null
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin" 2>"$tmp_err"
assert_contains "test_large_harness_emits_lossless_result" "$(<"$tmp_err")" "WEFT_TEST_RESULT 1 1800 0 1800"
echo "  ok test_builds_large_harness"

echo "Tool boundary summary: 1121 passed, 0 failed"
