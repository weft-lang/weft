#!/bin/bash
# Tool boundary tests: parse-only, check-only, and AST tool paths.
set -e

WEFT=${WEFT:-./weft}
WEFT_TEST_COMPILE_TIMEOUT=${WEFT_TEST_COMPILE_TIMEOUT:-120}
WEFT_TEST_RUN_TIMEOUT=${WEFT_TEST_RUN_TIMEOUT:-120}
WEFT_TEST_COMPILE_RSS_LIMIT_KB=${WEFT_TEST_COMPILE_RSS_LIMIT_KB:-8000000}
WEFT_TEST_RUN_RSS_LIMIT_KB=${WEFT_TEST_RUN_RSS_LIMIT_KB:-1000000}
case "$WEFT" in
  /*) WEFT_ABS="$WEFT" ;;
  *) WEFT_ABS="$(pwd)/$WEFT" ;;
esac
tmp_src=$(mktemp /tmp/weft_tool_src_XXXXXX)
tmp_import=$(mktemp /tmp/weft_tool_import_XXXXXX)
tmp_bin=$(mktemp /tmp/weft_tool_bin_XXXXXX)
tmp_err=$(mktemp /tmp/weft_tool_err_XXXXXX)
tmp_out=$(mktemp /tmp/weft_tool_out_XXXXXX)
tmp_tool_obj=$(mktemp /tmp/weft_tool_runner_obj_XXXXXX)
tmp_tool_bin=$(mktemp /tmp/weft_tool_runner_bin_XXXXXX)
tmp_test_fail_one=$(mktemp /tmp/weft_tool_test_fail_one_XXXXXX.weft)
tmp_test_fail_two=$(mktemp /tmp/weft_tool_test_fail_two_XXXXXX.weft)
tmp_test_after=$(mktemp /tmp/weft_tool_test_after_XXXXXX.weft)
tmp_test_dir=$(mktemp -d /tmp/weft_tool_test_dir_XXXXXX)
tmp_pkg_dir=$(mktemp -d /tmp/weft_tool_pkg_XXXXXX)
tmp_pkg_cli_dir=$(mktemp -d /tmp/weft_tool_pkg_cli_XXXXXX)
tmp_pkg_missing_dir=$(mktemp -d /tmp/weft_tool_pkg_missing_XXXXXX)
tmp_outside_dir=$(mktemp -d /tmp/weft_tool_outside_XXXXXX)
tmp_compiler_probe="compiler/_weft_trust_probe_$$.weft"
tmp_runtime_probe="runtime/_weft_trust_probe_$$.weft"
tmp_stdlib_probe="stdlib/_weft_trust_probe_$$.weft"
trap 'rm -f "$tmp_src" "$tmp_import" "$tmp_bin" "$tmp_err" "$tmp_out" "$tmp_tool_obj" "$tmp_tool_bin" "$tmp_test_fail_one" "$tmp_test_fail_two" "$tmp_test_after" "$tmp_compiler_probe" "$tmp_runtime_probe" "$tmp_stdlib_probe"; rm -rf "$tmp_pkg_dir" "$tmp_pkg_cli_dir" "$tmp_pkg_missing_dir" "$tmp_outside_dir" "$tmp_test_dir"' EXIT

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

assert_program_failure_equals() {
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
  assert_equals "${name}_stderr" "$err" "$expected_stderr"
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

fmt_out=$("$WEFT" fmt < "$tmp_src" 2>&1)
assert_contains "fmt_parse_only" "$fmt_out" "fn main() -> i64 { 42 }"
assert_equals "fmt_snapshot_exact" "$fmt_out" "fn main() -> i64 { 42 }"

fmt_path_out=$("$WEFT" fmt "$tmp_src" 2>&1)
assert_equals "fmt_path_snapshot_exact" "$fmt_path_out" "fn main() -> i64 { 42 }"

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

run_weft_compile_guarded "$WEFT" compile "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
chmod +x "$tmp_bin"
set +e
run_binary_guarded "$tmp_bin" >/dev/null 2>&1
compile_path_exit=$?
set -e
assert_equals "compile_path_binary_exit" "$compile_path_exit" "42"

assert_program_failure_equals "panic_boundary" "test/panic_exit.weft" "101" "weft: panic: direct panic boundary"
assert_program_failure_equals "checked_index_bounds_panic" "test/array_index_oob_exit.weft" "101" "weft: panic: index out of bounds"
assert_program_failure_equals "checked_index_mutation_bounds_panic" "test/array_index_set_oob_exit.weft" "101" "weft: panic: index out of bounds"
assert_program_failure_equals "result_unwrap_panic" "test/result_unwrap_exit.weft" "101" "weft: panic: Result.unwrap called on Err"
assert_program_failure_equals "result_expect_panic" "test/result_expect_exit.weft" "101" "weft: panic: required result failed"
assert_program_failure_equals "option_unwrap_panic" "test/option_unwrap_exit.weft" "101" "weft: panic: Option.unwrap called on None"
assert_program_failure_equals "option_expect_panic" "test/option_expect_exit.weft" "101" "weft: panic: required option missing"

printf 'fn broken() -> i64 { 1\nfn after() -> i64 { 2 }\n' > "$tmp_src"
parse_recovery_out=$("$WEFT" ast < "$tmp_src" 2>&1)
assert_contains "ast_reports_parse_recovery" "$parse_recovery_out" "error: expected '}' before declaration"
assert_contains "ast_recovers_after_parse_error" "$parse_recovery_out" "--- AST: 2 functions ---"

printf 'fn main() -> i64 { missing }\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1 || true)
assert_contains "check_reports_diagnostics" "$diag_out" "type error: unknown identifier"
assert_equals "diagnostic_snapshot_exact" "$diag_out" $'line 1, col 20: type error: unknown identifier\ncheck: 1 functions, 1 errors'

mcp_out=$(printf '%s' '{ "jsonrpc" : "2.0", "id" : 1, "method" : "tools/list" }' | "$WEFT" mcp 2>&1)
assert_equals "mcp_tools_list_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"parse_summary"},{"name":"check_summary"},{"name":"ir_summary"},{"name":"type_lookup"},{"name":"effect_lookup"},{"name":"diagnostics"},{"name":"grammar_parse"},{"name":"grammar_check"},{"name":"grammar_diagnostics"},{"name":"opt_counters"}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/list","meta":[true,null,1,-2.5,3e4,{"x":"y"}]}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_nested_extra_json_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"parse_summary"},{"name":"check_summary"},{"name":"ir_summary"},{"name":"type_lookup"},{"name":"effect_lookup"},{"name":"diagnostics"},{"name":"grammar_parse"},{"name":"grammar_check"},{"name":"grammar_diagnostics"},{"name":"opt_counters"}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source" : "fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_parse_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_check_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"check_summary","ok":true,"functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_ir_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"ir_summary","ok":true,"functions":1,"blocks":1,"insts":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"effect E { @deferred fn get() -> i64 } fn f() -> i64 { handle E.get() { E.get() with k -> k(20) } } test \"x\" { Test.assert_eq(f(), 20) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_ir_summary_test_deferred_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"ir_summary","ok":true,"functions":2,"blocks":3,"insts":4}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn add(x: i64, y: i64) -[Log]> i64 { x + y }\neffect Log { fn hit() -> i64 }","name":"add"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_function_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"name":"add","found":true,"kind":"function","params":2,"return_type_tag":2,"return_type_prim":0,"effects":1,"effect_tail":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"type Pair { left: i64, right: str }\nfn main() -> i64 { 0 }","name":"Pair"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_record_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"name":"Pair","found":true,"kind":"record","items":2,"type_params":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn main() -> i64 { 0 }","name":"missing"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"name":"missing","found":false}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"effect Log { fn hit(x: i64) -> bool }\nfn main() -> i64 { 0 }","name":"Log"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"name":"Log","found":true,"kind":"effect","ops":1,"first_op":"hit","first_op_params":1,"first_op_return_type_tag":2,"first_op_return_type_prim":2,"first_op_deferred":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"effect Async { @deferred fn wait() -> i64 }\nfn main() -> i64 { 0 }","name":"Async"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_deferred_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"name":"Async","found":true,"kind":"effect","ops":1,"first_op":"wait","first_op_params":0,"first_op_return_type_tag":2,"first_op_return_type_prim":0,"first_op_deferred":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"fn main() -> i64 { 0 }","name":"Missing"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"name":"Missing","found":false}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_clean_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":0,"functions":1,"check_errors":0,"items":[]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"test \"x\" { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_test_block_clean_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":0,"functions":1,"check_errors":0,"items":[]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -[Unsafe]> i64 { __mem_load64(0) }"}}}' | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostics_rejects_root_raw_memory" "$mcp_out" "type error: Unsafe is sealed to trusted runtime/platform code"

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_parse","arguments":{"grammar":"mini_sql","source":"select id, name from users where id = 1"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_parse","ok":true,"grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"users","where":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select id from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select nope from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_unknown_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"users","where":0,"check_errors":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo from invoices where memo = '\''paid'\''","host_source":"type invoices { total: i64, memo: str }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_source_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo from invoices where total >= 10 and paid = true","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_compound_predicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo as label, total amount, true marker from invoices where paid","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_projection_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":3,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select total + 5 adjusted, memo || '\''!'\'' label from invoices where total * 2 >= 20","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_scalar_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo from invoices where paid order by total + 5 desc, memo || '\''!'\''","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_order_by_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select memo from invoices where paid order by total desc limit total + 5 offset 1","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_limit_offset_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"invoices","where":1,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select paid, count(*), sum(total) from invoices group by paid order by sum(total) desc limit 10","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_group_aggregate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":3,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select paid, count(*), sum(total) from invoices group by paid having sum(total) > 100 and paid = true order by sum(total) desc limit 10","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_having_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":3,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select total + 5 adjusted, memo from invoices order by adjusted desc","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_order_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select paid, sum(total) total_due from invoices group by paid having total_due > 100 order by total_due desc","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_having_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select i.paid, sum(i.total) as total_due from invoices i group by i.paid having total_due > 100 order by i.paid","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_qualified_ref_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"invoices","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select u.name, o.total from users u join orders o on u.id = o.user_id","host_source":"type users { id: i64, name: str, active: bool }\ntype orders { id: i64, user_id: i64, total: i64 }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_join_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select distinct name from users order by name"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_distinct_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"distinct":1,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select distinct u.name, o.total from users u join orders o on u.id = o.user_id","host_source":"type users { id: i64, name: str, active: bool }\ntype orders { id: i64, user_id: i64, total: i64 }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_host_distinct_join_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"distinct":1,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select nope from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_type_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select nope from invoices","host_source":"type invoices { total: i64, memo: str }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_unknown_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total from invoices where total = '\''bad'\''","host_source":"type invoices { total: i64, memo: str }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_predicate_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: predicate type mismatch","span":42,"line":1,"col":43}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users where name > '\''Ada'\''","host_source":"type users { id: i64, name: str, active: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_relational_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: relational predicate requires i64","span":35,"line":1,"col":36}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users where id and active = true","host_source":"type users { id: i64, name: str, active: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_logical_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: logical predicate operand must be bool","span":27,"line":1,"col":28}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select missing as alias from invoices","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_projection_unknown_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select memo + 1 from invoices","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_arithmetic_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: arithmetic expression requires i64","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total || '\''!'\'' from invoices","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_concat_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: concat expression requires str","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total from invoices where memo + 1 = 2","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_predicate_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: arithmetic expression requires i64","span":33,"line":1,"col":34}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select memo from invoices order by missing","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_order_unknown_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":35,"line":1,"col":36}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users order by"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_order_missing_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected order expression","span":29,"line":1,"col":30}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users order id"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_order_missing_by_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected BY","span":27,"line":1,"col":28}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select memo from invoices limit memo","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_host_limit_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: limit expression requires i64","span":32,"line":1,"col":33}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users limit"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_limit_missing_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected limit expression","span":26,"line":1,"col":27}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users offset 1 limit 2"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_limit_after_offset_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: unexpected trailing input","span":30,"line":1,"col":31}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select paid, memo, count(*) from invoices group by paid","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_ungrouped_projection_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: non-aggregate projection must appear in GROUP BY","span":13,"line":1,"col":14}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select sum(memo) from invoices","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_sum_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: aggregate sum requires i64","span":11,"line":1,"col":12}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users group by"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_missing_expr_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected group expression","span":29,"line":1,"col":30}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select avg(id) from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_unknown_aggregate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: unknown aggregate function","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select count(*) from users limit count(*)"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_group_aggregate_tail_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: aggregate not allowed in query tail","span":33,"line":1,"col":34}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select paid, count(*) from invoices group by paid having memo = '\''late'\''","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_having_ungrouped_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: non-aggregate HAVING expression must appear in GROUP BY","span":57,"line":1,"col":58}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select paid, count(*) from invoices group by paid having count(*)","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_having_non_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: having expression must be bool","span":57,"line":1,"col":58}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select count(*) from users having"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_having_missing_predicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected predicate expression","span":33,"line":1,"col":34}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total as x, memo as x from invoices order by x","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_ambiguous_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: ambiguous projection alias","span":52,"line":1,"col":53}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select total as memo from invoices order by memo + 1","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_alias_column_shadow_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: arithmetic expression requires i64","span":44,"line":1,"col":45}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select o.memo from invoices as i","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_qualified_unknown_alias_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: unknown table qualifier","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select i. from invoices i","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_qualified_missing_field_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected field after '\''.'\''","span":10,"line":1,"col":11}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select i.memo + 1 from invoices i","host_source":"type invoices { total: i64, memo: str, paid: bool }\nfn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_qualified_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: arithmetic expression requires i64","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users join orders on users.id = orders.user_id"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_join_ambiguous_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: ambiguous column","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select u.name from users u join orders o on u.name = o.total"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_join_predicate_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: predicate type mismatch","span":53,"line":1,"col":54}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select u.name from users u join orders o"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_join_missing_on_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected ON","span":40,"line":1,"col":41}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select distinct id from users join orders on users.id = orders.user_id"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_distinct_ambiguous_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: ambiguous column","span":16,"line":1,"col":17}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id as distinct from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_distinct_alias_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":2,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected alias after AS","span":13,"line":1,"col":14},{"severity":"error","message":"mini_sql parse error: expected FROM","span":13,"line":1,"col":14}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_parse_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":2,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected FROM","span":15,"line":1,"col":16},{"severity":"error","message":"mini_sql parse error: expected table name","span":15,"line":1,"col":16}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id as from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_alias_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected alias after AS","span":13,"line":1,"col":14}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id + from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_scalar_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected expression after operator","span":12,"line":1,"col":13}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id from users where id >= 1 and"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_predicate_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected predicate expression","span":38,"line":1,"col":39}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_parse","arguments":{"grammar":"bogus","source":"select id from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_unknown_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"unknown grammar"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_parse","arguments":{"source":"select id from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing grammar"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"\nfn broken -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_parse_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":0,"items":[{"severity":"error","message":"error: expected '\''('\'' after function name","span":4,"line":2,"col":4}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn one -> i64 { 0 }\nfn two -> i64 { 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_many_parse_errors_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":2,"functions":2,"check_errors":0,"items":[{"severity":"error","message":"error: expected '\''('\'' after function name","span":3,"line":1,"col":4},{"severity":"error","message":"error: expected '\''('\'' after function name","span":23,"line":2,"col":4}]}}'

large_mcp_source=""
for ((i = 0; i < 40; i++)); do
  large_mcp_source+="fn broken$i -> i64 { $i } "
done
mcp_out=$(printf '%s' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"diagnostics\",\"arguments\":{\"source\":\"$large_mcp_source\"}}}" | "$WEFT" mcp 2>&1)
assert_contains "mcp_diagnostics_large_response_count" "$mcp_out" '"diagnostics":40'
assert_contains "mcp_diagnostics_large_response_items" "$mcp_out" '"items":[{"severity":"error"'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn main() -> i64 { missing }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_identifier_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown identifier","span":19,"line":1,"col":20}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn call() -> i64 { missing_fn() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_function_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown function","span":19,"line":1,"col":20}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let x = 1 x() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_non_function_call_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: called value is not a function","span":28,"line":1,"col":29}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id(x: i64) -> i64 { x } fn bad() -> i64 { id<i64>(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_generic_non_generic_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: generic call target is not generic","span":45,"line":1,"col":46}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let n = 42 n.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_field_non_record_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: field access on non-record","span":31,"line":1,"col":32}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Point { x: i64 } fn bad() -> i64 { let p = Point { x: 42, y: 0 } p.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_record_field_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown record field","span":63,"line":1,"col":64}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let p = Missing { x: 42 } 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_record_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown record type","span":26,"line":1,"col":27}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Shape { Circle(i64) } fn bad() -> i64 { let p = Shape { x: 42 } 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_record_init_variant_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: not a record type","span":53,"line":1,"col":54}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Point { x: i64, y: i64 } fn bad() -> i64 { let p = Point { x: 42 } p.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_missing_record_field_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: missing record field","span":56,"line":1,"col":57}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Point { x: i64 } fn bad() -> i64 { let p = Point { x: 1, x: 2 } p.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_duplicate_record_field_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: duplicate record field","span":62,"line":1,"col":63}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Point { x: i64 } fn bad() -> i64 { let p = Point { x: \"oops\" } p.x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_record_field_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: record field type mismatch","span":56,"line":1,"col":57}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn add(a: i64, b: i64) -> i64 { a + b } fn bad() -> i64 { add(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_call_arity_few_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: arity mismatch","span":58,"line":1,"col":59}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id(x: i64) -> i64 { x } fn bad() -> i64 { id(1, 2) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_call_arity_many_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: arity mismatch","span":45,"line":1,"col":46}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id(x: i64) -> i64 { x } fn bad() -> i64 { id(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_call_arg_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: argument type mismatch","span":45,"line":1,"col":46}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id<T>(x: T) -> T { x } fn bad() -> i64 { id<i64>() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_generic_call_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: arity mismatch","span":44,"line":1,"col":45}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id<T>(x: T) -> T { x } fn bad() -> i64 { id<i64>(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_generic_call_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: argument type mismatch","span":44,"line":1,"col":45}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(f: (i64) -> i64) -> i64 { f(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_function_value_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: argument type mismatch","span":33,"line":1,"col":34}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type M { v: i64 } impl M { fn add(self: M, n: i64) -> i64 { self.v + n } } fn bad(b: M) -> i64 { b.add() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_method_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: arity mismatch","span":97,"line":1,"col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type M { v: i64 } impl M { fn add(self: M, n: i64) -> i64 { self.v + n } } fn bad(b: M) -> i64 { b.add(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_method_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: argument type mismatch","span":97,"line":1,"col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Pair { fn add(a: i64, b: i64) -> i64 } fn bad() -[Pair]> i64 { Pair.add(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_effect_perform_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: arity mismatch","span":75,"line":1,"col":76}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Pair { fn add(a: i64, b: i64) -> i64 } fn bad() -[Pair]> i64 { Pair.add(1, \"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_effect_perform_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: argument type mismatch","span":75,"line":1,"col":76}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Pair { fn add(a: i64, b: i64) -> i64 } fn bad() -> i64 { handle Pair.add(1, 2) { Pair.add(a) -> resume(a) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_clause_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: arity mismatch","span":93,"line":1,"col":94}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Pair { fn add(a: i64, b: i64) -> i64 } fn bad() -> i64 { handle Pair.add(1, 2) { Pair.add(a: str, b: i64) -> resume(0) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_clause_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: argument type mismatch","span":97,"line":1,"col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { State.get() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_effect_perform_unavailable_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: effect not available in caller","span":51,"line":1,"col":52}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Log { fn hit() -> i64 } fn bad(f: (i64) -[Log]> i64) -> i64 { f(41) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_function_value_effect_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: effect not available in caller","span":69,"line":1,"col":70}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Log { fn hit() -> i64 } fn noisy<T>(x: T) -[Log]> i64 { Log.hit() } fn bad() -> i64 { noisy<i64>(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_generic_call_effect_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: effect not available in caller","span":93,"line":1,"col":94}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect MethodEffect { fn ping() -> i64 } type Box { v: i64 } impl Box { fn noisy(self: i64) -[MethodEffect]> i64 { MethodEffect.ping() } } fn bad(b: Box) -> i64 { b.noisy() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_method_effect_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: effect not available in caller","span":163,"line":1,"col":164}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedTwo { fn one(self: i64) -> i64 fn two(self: i64) -> i64 } type BoxNeed { v: i64 } impl NeedTwo for BoxNeed { fn one(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_missing_method_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: impl missing required method","span":109,"line":1,"col":110}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedArity { fn add(self: i64, n: i64) -> i64 } type BoxArity { v: i64 } impl NeedArity for BoxArity { fn add(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_method_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: impl method arity mismatch","span":97,"line":1,"col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedParam { fn set(self: i64, n: i64) -> i64 } type BoxParam { v: i64 } impl NeedParam for BoxParam { fn set(self: i64, n: str) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_method_param_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: impl method parameter type mismatch","span":97,"line":1,"col":98}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedRet { fn get(self: i64) -> i64 } type BoxRet { v: i64 } impl NeedRet for BoxRet { fn get(self: i64) -> str { \"x\" } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_method_return_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: impl method return type mismatch","span":83,"line":1,"col":84}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect LogTrait { fn hit() -> i64 } trait NeedPure { fn get(self: i64) -> i64 } type BoxEff { v: i64 } impl NeedPure for BoxEff { fn get(self: i64) -[LogTrait]> i64 { LogTrait.hit() } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_method_effect_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: impl method effect mismatch","span":121,"line":1,"col":122}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedAssoc { type Item fn next(self: i64) -> i64 } type BoxAssocMissing { v: i64 } impl NeedAssoc for BoxAssocMissing { fn next(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_assoc_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: impl missing required associated type","span":107,"line":1,"col":108}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedAssocDup { type Item fn next(self: i64) -> i64 } type BoxAssocDup { v: i64 } impl NeedAssocDup for BoxAssocDup { type Item = i64 type Item = str fn next(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_assoc_duplicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: duplicate associated type binding","span":109,"line":1,"col":110}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait NeedAssocExtra { fn next(self: i64) -> i64 } type BoxAssocExtra { v: i64 } impl NeedAssocExtra for BoxAssocExtra { type Item = i64 fn next(self: i64) -> i64 { 1 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_assoc_extra_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: impl associated type is not declared by trait","span":105,"line":1,"col":106}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait BoundNeed { fn val(self: i64) -> i64 } fn use_bound<T: BoundNeed>(x: T) -> i64 { x.val() } fn bad() -> i64 { use_bound<i64>(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_bound_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: type does not satisfy trait bound","span":115,"line":1,"col":116}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"trait DupTrait { fn val(self: i64) -> i64 } type DupBox { v: i64 } impl DupTrait for DupBox { fn val(self: i64) -> i64 { 1 } } impl DupTrait for DupBox { fn val(self: i64) -> i64 { 2 } } fn main() -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_trait_impl_conflict_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":3,"check_errors":1,"items":[{"severity":"error","message":"type error: conflicting implementations of trait for type","span":145,"line":1,"col":146}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn id<T>(x: T) -> T { x } fn bad() -> i64 { let y = id<i64, str>(1) 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_generic_type_arg_count_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: wrong number of type arguments","span":52,"line":1,"col":53}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { for x in 42 { 0 } 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_for_iter_non_list_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: for iterator requires a Cons/Nil list","span":22,"line":1,"col":23}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -[Unsafe]> i64 { __got_nope() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_got_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":3,"functions":1,"check_errors":3,"items":[{"severity":"error","message":"type error: unknown GOT symbol","span":26,"line":1,"col":27},{"severity":"error","message":"type error: unknown GOT symbol","span":26,"line":1,"col":27},{"severity":"error","message":"type error: Unsafe is sealed to trusted runtime/platform code","span":26,"line":1,"col":27}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type NoMeth { v: i64 } fn bad(x: NoMeth) -> i64 { x.missing() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_method_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown method","span":50,"line":1,"col":51}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let mut x = 1 let f = () => x f() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_mut_capture_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: cannot capture mut binding","span":46,"line":1,"col":47}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.put() -> resume(0) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_unknown_op_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":2,"functions":1,"check_errors":2,"items":[{"severity":"error","message":"type error: missing handler clause","span":64,"line":1,"col":65},{"severity":"error","message":"type error: unknown effect operation","span":78,"line":1,"col":79}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect A { fn f() -> i64 } effect B { fn f() -> i64 } fn bad() -> i64 { handle A.f() { A.f() -> resume(1) B.f() -> resume(2) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_effect_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: handler clause effect mismatch","span":106,"line":1,"col":107}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect PlainDelay { fn get() -> i64 } fn main() -> i64 { handle PlainDelay.get() { PlainDelay.get() with k -> resume(42) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_non_deferred_k_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":2,"functions":1,"check_errors":2,"items":[{"severity":"error","message":"type error: handler continuation requires deferred effect operation","span":105,"line":1,"col":106},{"severity":"error","message":"type error: use continuation binding instead of resume","span":117,"line":1,"col":118}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> resume(\"nope\") } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_resume_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: resume type mismatch","span":78,"line":1,"col":79}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> resume(1) State.get() -> resume(2) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_duplicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: duplicate handler clause","span":103,"line":1,"col":104}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 fn put(v: i64) -> i64 } fn bad() -> i64 { handle { State.get() + State.put(1) } { State.get() -> resume(1) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: missing handler clause","span":102,"line":1,"col":103}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { resume(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_resume_outside_handler_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: resume outside handler clause","span":25,"line":1,"col":26}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> { let f = x => resume(x) f(1) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_resume_capture_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: cannot capture resume","span":109,"line":1,"col":110}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Async { @deferred fn get() -> i64 } fn apply_saved(f: (i64) -> i64) -> i64 { f(1) } fn bad() -> i64 { handle Async.get() { Async.get() with k -> { let f = x => k(x) apply_saved(f) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_continuation_escape_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: continuation cannot escape","span":184,"line":1,"col":185}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Async { @deferred fn get() -> i64 } fn bad() -> i64 { handle Async.get() { Async.get() with k -> { k(1) k(2) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_continuation_multiple_use_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: continuation used more than once","span":99,"line":1,"col":100}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(value: rc i64) -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_rc_public_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: rc is not public syntax","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Async { @deferred fn get() -> i64 } fn bad() -> (i64) -> i64 { handle Async.get() { Async.get() with k -> x => k(x) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_continuation_closure_local_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":3,"functions":1,"check_errors":3,"items":[{"severity":"error","message":"type error: continuation-capturing closure must stay local","span":108,"line":1,"col":109},{"severity":"error","message":"type error: resume type mismatch","span":97,"line":1,"col":98},{"severity":"error","message":"type error: return type mismatch","span":46,"line":1,"col":47}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(n: i64) -> i64 { let x = match n { 0 -> 42 _ -> \"oops\" } 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_match_arm_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: match arm type mismatch","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(n: i64) -> i64 { match n { 1 -> 2 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_match_int_exhaustive_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: non-exhaustive match","span":30,"line":1,"col":31}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Choice { Left(i64), Right(i64) } fn bad(x: Choice) -> i64 { match x { Left(v) -> v } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_match_ctor_exhaustive_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: non-exhaustive match","span":71,"line":1,"col":72}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type Choice { Left(i64), Right(i64) } fn bad(x: Choice) -> i64 { match x { Left(v) -> v Left(v) -> v + 1 Right(v) -> v } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_match_duplicate_ctor_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: duplicate match constructor arm","span":88,"line":1,"col":89}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(s: str) -> i64 { match s { 0 -> 1 _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_literal_scrutinee_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: literal pattern does not match scrutinee","span":34,"line":1,"col":35}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type KnownPattern { KnownVariant(i64) } fn bad(k: KnownPattern) -> i64 { match k { MissingVariant(x) -> x _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_unknown_ctor_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown constructor pattern","span":83,"line":1,"col":84}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type BoxPattern { BoxedPattern(i64) } fn bad(n: i64) -> i64 { match n { BoxedPattern(v) -> v _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_ctor_on_i64_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: constructor pattern does not match scrutinee","span":72,"line":1,"col":73}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type ShapePatternBad { BadCircle(i64) } type ColorPatternBad { BadRed(i64) } fn bad(c: ColorPatternBad) -> i64 { match c { BadCircle(r) -> r _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_wrong_ctor_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: constructor pattern does not match scrutinee","span":123,"line":1,"col":124}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type PayloadPattern { PayloadOne(i64) } fn bad(p: PayloadPattern) -> i64 { match p { PayloadOne -> 1 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_ctor_arity_few_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: constructor pattern arity mismatch","span":85,"line":1,"col":86}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type PayloadPatternMany { PayloadSingle(i64) } fn bad(p: PayloadPatternMany) -> i64 { match p { PayloadSingle(x, y) -> x + y } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_pattern_ctor_arity_many_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: constructor pattern arity mismatch","span":96,"line":1,"col":97}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { if 1 { 42 } else { 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_if_condition_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":21,"line":1,"col":22}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let mut x = 0 while 1 { x = x + 1 } x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_while_condition_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":38,"line":1,"col":39}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { not 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_not_operand_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":23,"line":1,"col":24}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { true and 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_logical_operand_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(n: i64) -> i64 { match n { x if x -> x _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_match_guard_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":39,"line":1,"col":40}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { 1 == \"one\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_equality_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: equality operand mismatch","span":19,"line":1,"col":20}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { \"a\" < \"b\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_comparison_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: ordering operands must implement Ord","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { true band 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_bitwise_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: bitwise operand is not i64","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { 1 bshl false }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_shift_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: bitwise operand is not i64","span":18,"line":1,"col":19}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { \"a\" + 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_arithmetic_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: arithmetic operand is not i64","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { missing = 1 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_assignment_unknown_target_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown identifier","span":18,"line":1,"col":19}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let x = 0 x = 1 x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_assignment_immutable_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: cannot assign to immutable binding","span":28,"line":1,"col":29}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let mut x = 0 x = \"oops\" x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_assignment_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: assignment type mismatch","span":32,"line":1,"col":33}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let x: i64 = \"oops\" x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_let_annotation_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: value does not match let type annotation","span":22,"line":1,"col":23}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { return \"oops\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_explicit_return_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: return type mismatch","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { \"oops\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_body_return_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: return type mismatch","span":3,"line":1,"col":4}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"fn main() -> str { \"Ω\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_unicode_source_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"functions":1,"first_body_tag":9}}'

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
assert_equals "mcp_parse_summary_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { missing }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_check_summary_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"check_summary","ok":true,"functions":1,"first_body_tag":2}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"fn main() -> i64 { missing }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_ir_summary_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"ir_summary","ok":true,"functions":0,"blocks":0,"insts":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"type_lookup","arguments":{"source":"fn main() -> i64 { missing }","name":"main"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_type_lookup_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"type_lookup","ok":true,"name":"main","found":true,"kind":"function","params":0,"return_type_tag":2,"return_type_prim":0,"effects":0,"effect_tail":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"effect_lookup","arguments":{"source":"effect Log { fn hit() -> i64 } fn main() -> i64 { missing }","name":"Log"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_effect_lookup_invalid_source_json_only_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"effect_lookup","ok":true,"name":"Log","found":true,"kind":"effect","ops":1,"first_op":"hit","first_op_params":0,"first_op_return_type_tag":2,"first_op_return_type_prim":0,"first_op_deferred":0}}'

# opt_counters: full optimise + native-lower pipeline counter report
mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{"source":"fn add(a: i64, b: i64) -> i64 { a + b }\nfn main() -> i64 { add(1, 2) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_opt_counters_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"opt_counters","ok":true,"handler_inline_sites":0,"handler_residual_sites":0,"handler_evidence_candidate_sites":0,"const_fold_sites":1,"algebraic_fold_sites":0,"dead_inst_sites":2,"pure_call_dce_sites":0,"match_final_arm_elision_sites":0,"block_entry_narrowing_sites":0,"direct_call_inline_sites":1,"functions":2,"insts":4,"sp_load":0,"sp_store":0,"sp_pair_load":1,"sp_pair_store":1,"sp_fp_pair_load":0,"sp_fp_pair_store":0,"rc_elision":0,"rc_borrowable_param_facts":0,"managed_drop_specializations":0,"managed_reuse_candidates":0,"managed_reuse_lowerings":0,"static_pair_slots":0,"static_pair_sites":0,"alloc_elisions":0,"fusions":0,"vector_bounds_elisions":0,"vector_full_bounds_elisions":0,"vector_scaled_addrs":0,"vector_push_no_grows":0,"param_residents":0,"volatile_residents":0,"call_window_residents":0,"low_pool_residents":0,"dead_store_elisions":0,"remat_small_const_defs":0,"remat_small_const_uses":0,"remat_large_const_defs":0,"remat_large_const_uses":0,"remat_movn_const_defs":0,"remat_movn_const_uses":0,"leaf_fns":2,"leaf_fn_pairs":4,"leaf_small_fns":2,"leaf_small_fn_pairs":4,"crossblock_barrier_free_defs":0,"crossblock_barrier_free_uses":0,"residual_slotlike":0,"residual_machinery_reads":0,"residual_call_use":0,"residual_pool_full":0,"residual_cs_exhausted":0,"residual_use_sum":0,"split_candidate_defs":0,"split_segment_uses":0,"split_residents":0,"fwd_only_defs":0,"fp_residents":0,"register_pinned":0,"pinned_slots":0,"loop_pinned_slots":0,"cs_residents":0,"bank_swaps":0,"typed_lowering_failures":0,"residency_audit_violations":0,"alloc_ck_violations":0,"alloc_ck_checked":4,"live_functions_measured":2,"max_pressure":2,"pressure_fns_le8":2,"pressure_fns_9_13":0,"pressure_fns_14_21":0,"pressure_fns_22_27":0,"pressure_fns_28_up":0,"call_sites_measured":0,"max_live_across_call":0,"lac_sites_0":0,"lac_sites_1_4":0,"lac_sites_5_8":0,"lac_sites_9_up":0,"spill_defs_loads_0":0,"spill_defs_loads_1":0,"spill_defs_loads_2_3":0,"spill_defs_loads_4_up":0,"shape_l0_param":0,"shape_l1_param":0,"shape_d2_param":0,"shape_ls_param":0,"shape_l0_call":0,"shape_l1_call":0,"shape_d2_call":0,"shape_ls_call":0,"shape_l0_const_small":0,"shape_l1_const_small":0,"shape_d2_const_small":0,"shape_ls_const_small":0,"shape_l0_const_large":0,"shape_l1_const_large":0,"shape_d2_const_large":0,"shape_ls_const_large":0,"shape_l0_field_load":0,"shape_l1_field_load":0,"shape_d2_field_load":0,"shape_ls_field_load":0,"shape_l0_variant":0,"shape_l1_variant":0,"shape_d2_variant":0,"shape_ls_variant":0,"shape_l0_slot_load":0,"shape_l1_slot_load":0,"shape_d2_slot_load":0,"shape_ls_slot_load":0,"shape_l0_arith":0,"shape_l1_arith":0,"shape_d2_arith":0,"shape_ls_arith":0,"shape_l0_ctor":0,"shape_l1_ctor":0,"shape_d2_ctor":0,"shape_ls_ctor":0,"shape_l0_addr_frame":0,"shape_l1_addr_frame":0,"shape_d2_addr_frame":0,"shape_ls_addr_frame":0,"shape_l0_effect_op":0,"shape_l1_effect_op":0,"shape_d2_effect_op":0,"shape_ls_effect_op":0,"shape_l0_fp":0,"shape_l1_fp":0,"shape_d2_fp":0,"shape_ls_fp":0,"shape_l0_addr_far":0,"shape_l1_addr_far":0,"shape_d2_addr_far":0,"shape_ls_addr_far":0,"shape_l0_variant_dead":0,"shape_l1_variant_dead":0,"shape_d2_variant_dead":0,"shape_ls_variant_dead":0,"shape_l0_param_dead":0,"shape_l1_param_dead":0,"shape_d2_param_dead":0,"shape_ls_param_dead":0,"shape_l0_unscanned":0,"shape_l1_unscanned":0,"shape_d2_unscanned":0,"shape_ls_unscanned":0,"split2_upper_saved":0,"split2_defs":0,"split2_loads":0,"pair_census_saved":0,"pair_census_tail_dead":0,"pair_census_interior_dead":0,"pair_census_half_dead":0,"pair_census_written_unsaved":0,"pair_census_unknown_fns":0,"pair_census_first_fn_hash":0,"pair_census_first_reg":0,"pair_census_first_delta":0,"pair_census_first_word":0,"soft_barrier_events":0,"true_barrier_events":0,"soft_barrier_only_fns":0,"naked_leaf_fns":2,"naked_leaf_shed_pairs":6,"naked_leaf_blocked_by_params":0,"naked_leaf_blocked_by_cleanup":0,"naked2_fns":0,"naked2_pairs":0,"naked2_spilled_defs":0,"fn_param_pool_residents":0,"fn_param_call_residents":0,"crossblock_pool_residents":0,"crossblock_pool_call_residents":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{"source":"fn main() -> i64 { nope() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_opt_counters_check_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"opt_counters","ok":false,"reason":"check errors"}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_opt_counters_missing_source_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"missing source"}}'

# JSON \uXXXX escapes are mandatory spec syntax: BMP escape decodes into
# source bytes, surrogate pairs decode to 4-byte UTF-8, invalid hex rejects.
mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"\u0066n main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_json_unicode_escape_bmp_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"check_summary","ok":true,"functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"-- \ud83d\ude00\nfn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_json_unicode_escape_surrogate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { \uZZZZ }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_json_unicode_escape_invalid_hex_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"invalid json-rpc"}}'

# MCP serve mode: persistent newline-delimited JSON-RPC. One process
# handles the whole session: initialize handshake (protocol version
# echoed), the initialized notification is not answered, tools/list
# carries input schemas, tools/call echoes the request id (string ids
# included) and wraps the payload as MCP text content.
mcp_serve_out=$(
  { printf '%s\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":"call-2","method":"tools/call","params":{"name":"parse_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}'
    printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"ping"}'
    printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"bogus/method"}'
  } | "$WEFT" mcp serve 2>&1)
assert_contains "mcp_serve_initialize_echoes_protocol" "$mcp_serve_out" '"protocolVersion":"2025-06-18"'
assert_contains "mcp_serve_initialize_serverinfo" "$mcp_serve_out" '"serverInfo":{"name":"weft"'
assert_contains "mcp_serve_tools_list_has_schema" "$mcp_serve_out" '"inputSchema":{"type":"object"'
assert_contains "mcp_serve_call_wraps_content_and_echoes_id" "$mcp_serve_out" '{"jsonrpc":"2.0","id":"call-2","result":{"content":[{"type":"text","text":"{\"tool\":\"parse_summary\",\"ok\":true'
assert_contains "mcp_serve_ping" "$mcp_serve_out" '{"jsonrpc":"2.0","id":3,"result":{}}'
assert_contains "mcp_serve_unknown_method_error" "$mcp_serve_out" '{"jsonrpc":"2.0","id":4,"error":{"code":-32601,"message":"method not found"}}'
assert_equals "mcp_serve_notification_not_answered" "$(printf '%s\n' "$mcp_serve_out" | grep -c jsonrpc)" "5"

lsp_init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
lsp_out=$(lsp_frame "$lsp_init" | "$WEFT" lsp 2>&1)
assert_contains "lsp_initialize_framed_header" "$lsp_out" "Content-Length:"
assert_contains "lsp_initialize_capabilities" "$lsp_out" '"hoverProvider":true'
assert_contains "lsp_initialize_definition_capability" "$lsp_out" '"definitionProvider":true'
assert_contains "lsp_initialize_completion_hook" "$lsp_out" '"completionProvider"'
assert_contains "lsp_initialize_code_action_hook" "$lsp_out" '"codeActionProvider":true'

lsp_open_clean='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///clean.weft","version":1,"text":"fn main() -> i64 { 0 }"}}}'
lsp_out=$(lsp_frame "$lsp_open_clean" | "$WEFT" lsp 2>&1)
assert_contains "lsp_open_clean_publish_diagnostics" "$lsp_out" '"method":"textDocument/publishDiagnostics"'
assert_contains "lsp_open_clean_empty_diagnostics" "$lsp_out" '"diagnostics":[]'

lsp_open_parse='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///parse.weft","version":1,"text":"fn broken -> i64 { 0 }"}}}'
lsp_out=$(lsp_frame "$lsp_open_parse" | "$WEFT" lsp 2>&1)
assert_contains "lsp_open_parse_error_diagnostic" "$lsp_out" "error: expected"
assert_contains "lsp_open_parse_error_range" "$lsp_out" '"range":{"start":{"line":0,"character":3}'

lsp_open_type='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///type.weft","version":1,"text":"fn main() -> i64 { missing }"}}}'
lsp_out=$(lsp_frame "$lsp_open_type" | "$WEFT" lsp 2>&1)
assert_contains "lsp_open_type_error_diagnostic" "$lsp_out" "type error: unknown identifier"
assert_contains "lsp_open_type_error_range" "$lsp_out" '"character":19'

lsp_open_raw='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///raw.weft","version":1,"text":"fn main() -[Unsafe]> i64 { __mem_load64(0) }"}}}'
lsp_out=$(lsp_frame "$lsp_open_raw" | "$WEFT" lsp 2>&1)
assert_contains "lsp_open_rejects_root_raw_memory" "$lsp_out" "type error: Unsafe is sealed to trusted runtime/platform code"

lsp_open_unicode='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///unicode.weft","version":1,"text":"fn main() -> i64 { let s = \"Ω\" missing }"}}}'
lsp_out=$(lsp_frame "$lsp_open_unicode" | "$WEFT" lsp 2>&1)
assert_contains "lsp_unicode_source_diagnostic" "$lsp_out" "type error: unknown identifier"
assert_contains "lsp_unicode_source_range" "$lsp_out" '"line":0'

large_lsp_source=""
for ((i = 0; i < 40; i++)); do
  large_lsp_source+="fn broken$i -> i64 { $i } "
done
lsp_large_open="{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"file:///large.weft\",\"version\":1,\"text\":\"$large_lsp_source\"}}}"
lsp_out=$(lsp_frame "$lsp_large_open" | "$WEFT" lsp 2>&1)
assert_contains "lsp_large_diagnostics_response" "$lsp_out" '"diagnostics":[{"range"'
assert_contains "lsp_large_diagnostics_late_range" "$lsp_out" '"character":997'

lsp_open_hover='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///hover.weft","version":1,"text":"fn add(x: i64) -> i64 { x } fn main() -> i64 { add(1) }"}}}'
lsp_hover='{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///hover.weft"},"position":{"line":0,"character":3}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_hover")" "$(lsp_frame "$lsp_hover")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_hover_function" "$lsp_out" '"value":"function add: params=1 return_type_tag=2 effects=0"'

lsp_definition='{"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///hover.weft"},"position":{"line":0,"character":47}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_hover")" "$(lsp_frame "$lsp_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_definition_function" "$lsp_out" '"range":{"start":{"line":0,"character":3},"end":{"line":0,"character":6}}'

lsp_open_local='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///local.weft","version":1,"text":"fn main() -> i64 { let value = 41 value + 1 }"}}}'
lsp_local_hover='{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///local.weft"},"position":{"line":0,"character":34}}}'
lsp_local_definition='{"jsonrpc":"2.0","id":5,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///local.weft"},"position":{"line":0,"character":34}}}'
lsp_out=$(printf '%s%s%s' "$(lsp_frame "$lsp_open_local")" "$(lsp_frame "$lsp_local_hover")" "$(lsp_frame "$lsp_local_definition")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_hover_local" "$lsp_out" '"value":"local value"'
assert_contains "lsp_definition_local" "$lsp_out" '"range":{"start":{"line":0,"character":23},"end":{"line":0,"character":28}}'

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
assert_contains "lsp_rapid_edit_bad_diagnostic" "$lsp_out" "type error: unknown identifier"
assert_contains "lsp_rapid_edit_final_clean" "$lsp_out" '"uri":"file:///rapid.weft","diagnostics":[]'

lsp_stale_change='{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///stale.weft","version":1},"contentChanges":[{"text":"fn main() -> i64 { missing }"}]}}'
lsp_open_stale='{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///stale.weft","version":2,"text":"fn main() -> i64 { 0 }"}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_stale")" "$(lsp_frame "$lsp_stale_change")" | "$WEFT" lsp 2>&1)
assert_not_contains "lsp_stale_update_ignored" "$lsp_out" "type error: unknown identifier"

# Slow writer: frames delivered across multiple pipe reads must not be
# truncated (read_fd_all once treated any short read as EOF).
lsp_slow_full="$(lsp_frame "$lsp_open_hover")$(lsp_frame "$lsp_definition")"
lsp_slow_head=${lsp_slow_full:0:40}
lsp_slow_tail=${lsp_slow_full:40}
lsp_out=$( { printf '%s' "$lsp_slow_head"; sleep 0.2; printf '%s' "$lsp_slow_tail"; } | "$WEFT" lsp 2>&1)
assert_contains "lsp_slow_writer_definition" "$lsp_out" '"range":{"start":{"line":0,"character":3},"end":{"line":0,"character":6}}'

lsp_completion='{"jsonrpc":"2.0","id":7,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///hover.weft"},"position":{"line":0,"character":1}}}'
lsp_out=$(printf '%s%s' "$(lsp_frame "$lsp_open_hover")" "$(lsp_frame "$lsp_completion")" | "$WEFT" lsp 2>&1)
assert_contains "lsp_completion_hook_items" "$lsp_out" '"label":"par_map"'

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
assert_contains "check_rejects_symbolic_and" "$amp_diag_out" "error: expected '}'"

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
printf 'fn sentinel() -> i64 { 99 }\n' >> "$tmp_import"
printf 'use "%s"\nfn main() -> i64 { sentinel() }\n' "$tmp_import" > "$tmp_src"
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
printf 'fn add(a: i64, b: i64) -> i64 { a + b }\n' > "$tmp_pkg_dir/deps/math/lib.weft"
printf 'use "math/lib.weft"\nfn main() -> i64 { if add(40, 2) == 42 { 0 } else { 1 } }\n' > "$tmp_pkg_dir/app.weft"
(cd "$tmp_pkg_dir" && run_weft_compile_guarded "$WEFT_ABS" < app.weft > app 2>"$tmp_err")
chmod +x "$tmp_pkg_dir/app"
run_binary_guarded "$tmp_pkg_dir/app"
echo "  ok package_local_dep_import_compiles"

mkdir -p "$tmp_pkg_dir/.weft/cache/math"
printf 'fn cached_value() -> i64 { 1 }\n' > "$tmp_pkg_dir/deps/math/lib.weft"
printf 'fn cached_value() -> i64 { 42 }\n' > "$tmp_pkg_dir/.weft/cache/math/lib.weft"
printf 'use "math/lib.weft"\nfn main() -> i64 { if cached_value() == 42 { 0 } else { 1 } }\n' > "$tmp_pkg_dir/app.weft"
(cd "$tmp_pkg_dir" && run_weft_compile_guarded "$WEFT_ABS" < app.weft > app 2>"$tmp_err")
chmod +x "$tmp_pkg_dir/app"
run_binary_guarded "$tmp_pkg_dir/app"
echo "  ok package_cache_hit_prefers_cached_file"

outside_name=$(basename "$tmp_outside_dir")
printf 'fn hidden() -> i64 { 0 }\n' > "$tmp_outside_dir/lib.weft"
printf 'package app\ndep evil ../%s\n' "$outside_name" > "$tmp_pkg_dir/weft.pkg"
printf 'use "evil/lib.weft"\nfn main() -> i64 { hidden() }\n' > "$tmp_pkg_dir/app.weft"
traversal_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_rejects_traversal_dep_path" "$traversal_out" "type error: unknown function"

printf 'package app\ndep math deps/math 1.0.0\n' > "$tmp_pkg_dir/weft.pkg"
printf 'use "math/lib.weft"\nfn main() -> i64 { add(1, 2) }\n' > "$tmp_pkg_dir/app.weft"
unsupported_out=$(cd "$tmp_pkg_dir" && "$WEFT_ABS" check < app.weft 2>&1 || true)
assert_contains "package_rejects_unsupported_version_token" "$unsupported_out" "type error: unknown function"

mkdir -p "$tmp_pkg_cli_dir/deps/math"
pkg_init_out=$(cd "$tmp_pkg_cli_dir" && "$WEFT_ABS" pkg init cli_app 2>&1)
assert_contains "pkg_init_writes_manifest" "$pkg_init_out" "pkg: wrote weft.pkg"
pkg_manifest=$(< "$tmp_pkg_cli_dir/weft.pkg")
assert_contains "pkg_init_manifest_package" "$pkg_manifest" '"package":"cli_app"'

pkg_add_out=$(cd "$tmp_pkg_cli_dir" && "$WEFT_ABS" pkg add math deps/math 2>&1)
assert_contains "pkg_add_records_dependency" "$pkg_add_out" "pkg: added dependency"
pkg_manifest=$(< "$tmp_pkg_cli_dir/weft.pkg")
assert_contains "pkg_add_manifest_dep" "$pkg_manifest" '"math":"deps/math"'
printf 'fn add(a: i64, b: i64) -> i64 { a + b }\n' > "$tmp_pkg_cli_dir/deps/math/lib.weft"
printf 'use "math/lib.weft"\nfn main() -> i64 { if add(40, 2) == 42 { 0 } else { 1 } }\n' > "$tmp_pkg_cli_dir/app.weft"
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

printf 'test "plain" { Test.assert_eq(1, 1) }\n' > "$tmp_src"
run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_not_contains_file "test_harness_binds_runtime_without_missing_symbols" "$tmp_err" "required runtime function unavailable"
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin"
echo "  ok test_harness_binds_runtime_after_synthesis"

printf 'fn tool_fail5() -[Fail<i64>]> i64 { Fail.fail(5) } test "helpers" { Test.assert_eq(1, 1) Test.assert_ne(1, 2) Test.assert_true(1 == 1) Test.assert_false(1 == 2) Test.assert_lt(1, 2) Test.assert_le(2, 2) Test.assert_gt(3, 2) Test.assert_ge(3, 3) Test.assert_eq_f64(1.5, 1.5) Test.assert_near_f64(0.1 + 0.2, 0.3, 1e-12) Test.forall_i64_range(0, 3, x => x < 3) Test.assert_eq(Test.with_state_i64(4, () => TestState.get()), 4) Test.assert_eq(Test.expect_fail_i64(5, () => tool_fail5()), 5) Test.assert_eq(Test.with_io_i64(() => IO.write(1, 0, 2)), 2) Test.assert_eq(Test.with_diagnose_i64(() => Diagnose.error("x", 0 - 1)), 1) }\n' > "$tmp_src"
run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_not_contains_file "test_harness_supports_assertion_helpers" "$tmp_err" "unknown effect operation"
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin"
echo "  ok test_assertion_helpers_pass"

printf 'test "path" { Test.assert_eq(21 + 21, 42) }\n' > "$tmp_src"
run_weft_compile_guarded "$WEFT" test --emit "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_not_contains_file "test_path_compiles_strict_source" "$tmp_err" "type error:"
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin"
echo "  ok test_path_binary_runs"

run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_out" 2>"$tmp_err"
if cmp "$tmp_bin" "$tmp_out"; then
  echo "  ok test_path_emit_matches_stdin"
else
  echo "  fail test_path_emit_matches_stdin"
  exit 1
fi

set +e
run_weft_compile_guarded "$WEFT" test "$tmp_src" > "$tmp_out" 2>"$tmp_err"
test_path_native_exit=$?
set -e
assert_equals "test_path_native_exit_zero" "$test_path_native_exit" "0"
assert_equals "test_path_native_stdout_empty" "$(<"$tmp_out")" ""
test_path_native_err=$(<"$tmp_err")
assert_contains "test_path_native_reports_pass" "$test_path_native_err" "  pass: $tmp_src ("
assert_contains "test_path_native_reports_summary" "$test_path_native_err" "1 passed, 0 failed"

printf 'test "first failure" { Test.assert_eq(1, 2) }\n' > "$tmp_test_fail_one"
printf 'test "second failure" { Test.assert_true(false) }\n' > "$tmp_test_fail_two"
printf 'test "runs after failure" { Test.assert_eq(42, 42) }\n' > "$tmp_test_after"
set +e
run_weft_compile_guarded "$WEFT" test "$tmp_test_fail_one" "$tmp_test_after" "$tmp_test_fail_two" > "$tmp_out" 2>"$tmp_err"
test_path_multi_exit=$?
set -e
assert_equals "test_path_native_counts_failed_files" "$test_path_multi_exit" "2"
assert_equals "test_path_native_failure_stdout_empty" "$(<"$tmp_out")" ""
test_path_multi_err=$(<"$tmp_err")
assert_contains "test_path_native_preserves_assertion_diagnostic" "$test_path_multi_err" "test assertion failed: assert_eq got=1 want=2"
assert_contains "test_path_native_reports_first_failure" "$test_path_multi_err" "  FAIL: $tmp_test_fail_one ("
assert_contains "test_path_native_continues_after_failure" "$test_path_multi_err" "  pass: $tmp_test_after ("
assert_contains "test_path_native_reports_second_failure" "$test_path_multi_err" "  FAIL: $tmp_test_fail_two ("
assert_contains "test_path_native_aggregates_summary" "$test_path_multi_err" "1 passed, 2 failed"

printf 'test "directory a" { Test.assert_eq(1, 1) }\n' > "$tmp_test_dir/a_pass.weft"
printf 'test "directory b" { Test.assert_eq(2, 2) }\n' > "$tmp_test_dir/b_pass.weft"
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
assert_contains "test_directory_reports_summary" "$test_dir_err" "2 passed, 0 failed"
assert_not_contains "test_directory_ignores_non_weft" "$test_dir_err" "ignored.txt"

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
assert_contains "test_directory_overlap_deduplicates" "$(<"$tmp_err")" "2 passed, 0 failed"

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
assert_contains "test_runner_capability_tool_directory_summary" "$(<"$tmp_err")" "2 passed, 0 failed"

set +e
run_binary_guarded "$tmp_tool_bin" "$WEFT_ABS" "$tmp_test_fail_one" > "$tmp_out" 2>"$tmp_err"
test_tool_failure_exit=$?
set -e
assert_equals "test_runner_capability_tool_failure_exit_one" "$test_tool_failure_exit" "1"
test_tool_failure_err=$(<"$tmp_err")
assert_contains "test_runner_capability_tool_preserves_diagnostic" "$test_tool_failure_err" "test assertion failed: assert_eq got=1 want=2"
assert_contains "test_runner_capability_tool_failure_summary" "$test_tool_failure_err" "0 passed, 1 failed"

printf 'test "raw" { let p = __bump_alloc(8) Test.assert_eq(p, p) }\n' > "$tmp_src"
test_path_raw_out=$(run_weft_compile_guarded "$WEFT" test "$tmp_src" > "$tmp_bin" 2>"$tmp_err" || true; cat "$tmp_err")
assert_contains "test_path_rejects_root_raw_memory" "$test_path_raw_out" "type error: raw allocation is sealed to trusted runtime/platform code"

test_stdin_raw_out=$(run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err" || true; cat "$tmp_err")
assert_contains "test_stdin_rejects_root_raw_memory" "$test_stdin_raw_out" "type error: raw allocation is sealed to trusted runtime/platform code"

printf 'fn leaked() -> i64 { __mem_load64(0) }\n' > "$tmp_compiler_probe"
compiler_probe_root_out=$("$WEFT" check "$tmp_compiler_probe" 2>&1 || true)
assert_contains "compiler_unlisted_root_rejects_raw_memory" "$compiler_probe_root_out" "type error: Unsafe is sealed to trusted runtime/platform code"

printf 'use "%s"\nfn main() -> i64 { leaked() }\n' "$tmp_compiler_probe" > "$tmp_src"
compiler_probe_import_out=$("$WEFT" check "$tmp_src" 2>&1 || true)
assert_contains "compiler_unlisted_import_rejects_raw_memory" "$compiler_probe_import_out" "type error: Unsafe is sealed to trusted runtime/platform code"
rm -f "$tmp_compiler_probe"

printf 'fn leaked() -> i64 { __mem_load64(0) }\n' > "$tmp_runtime_probe"
runtime_probe_root_out=$("$WEFT" check "$tmp_runtime_probe" 2>&1 || true)
assert_contains "runtime_unlisted_root_rejects_raw_memory" "$runtime_probe_root_out" "type error: Unsafe is sealed to trusted runtime/platform code"

printf 'use "%s"\nfn main() -> i64 { leaked() }\n' "$tmp_runtime_probe" > "$tmp_src"
runtime_probe_import_out=$("$WEFT" check "$tmp_src" 2>&1 || true)
assert_contains "runtime_unlisted_import_rejects_raw_memory" "$runtime_probe_import_out" "type error: Unsafe is sealed to trusted runtime/platform code"
rm -f "$tmp_runtime_probe"

printf 'fn leaked() -> i64 { __mem_load64(0) }\n' > "$tmp_stdlib_probe"
stdlib_probe_root_out=$("$WEFT" check "$tmp_stdlib_probe" 2>&1 || true)
assert_contains "stdlib_unlisted_root_rejects_raw_memory" "$stdlib_probe_root_out" "type error: Unsafe is sealed to trusted runtime/platform code"

printf 'use "%s"\nfn main() -> i64 { leaked() }\n' "$tmp_stdlib_probe" > "$tmp_src"
stdlib_probe_import_out=$("$WEFT" check "$tmp_src" 2>&1 || true)
assert_contains "stdlib_unlisted_import_rejects_raw_memory" "$stdlib_probe_import_out" "type error: Unsafe is sealed to trusted runtime/platform code"
rm -f "$tmp_stdlib_probe"

assert_test_exit_code "test_assert_eq_failure_returns_one" 'test "fail_eq" { Test.assert_eq(1, 2) }' 1
assert_test_exit_code "test_assert_eq_and_ne_two_clause_harness_runs" 'test "eq_ne" { Test.assert_eq(0, 0) Test.assert_ne(1, 2) }' 0
assert_test_exit_code "test_assert_ne_failure_returns_one" 'test "fail_ne" { Test.assert_ne(2, 2) }' 1
assert_test_exit_code "test_assert_bool_failures_return_two" $'test "fail_true" { Test.assert_true(1 == 2) }\ntest "fail_false" { Test.assert_false(1 == 1) }' 2
assert_test_exit_code "test_assert_comparison_failure_returns_one" 'test "fail_cmp" { Test.assert_lt(2, 1) }' 1
assert_test_failure_contains "test_assertion_failure_reports_diagnostic" 'test "fail_eq_diag" { Test.assert_eq(1, 2) }' 1 "test assertion failed: assert_eq"
assert_test_failure_contains "test_assert_eq_f64_failure_reports_diagnostic" 'test "fail_eq_f64" { Test.assert_eq_f64(1.0, 2.0) }' 1 "test assertion failed: assert_eq_f64"
assert_test_failure_contains "test_assert_eq_f64_nan_fails" 'test "fail_eq_f64_nan" { Test.assert_eq_f64(0.0 / 0.0, 0.0 / 0.0) }' 1 "test assertion failed: assert_eq_f64"
assert_test_failure_contains "test_assert_near_f64_outside_epsilon_fails" 'test "fail_near_f64" { Test.assert_near_f64(1.0, 1.5, 0.25) }' 1 "test assertion failed: assert_near_f64"
assert_test_failure_contains "test_assert_near_f64_negative_epsilon_fails" 'test "fail_near_f64_epsilon" { Test.assert_near_f64(1.0, 1.0, 0.0 - 0.1) }' 1 "test assertion failed: assert_near_f64"
assert_test_failure_contains "test_snapshot_mismatch_reports_diagnostic" 'test "fail_snapshot" { Test.assert_snapshot("actual", "expected") }' 1 "test assertion failed: snapshot"
assert_test_failure_contains "test_property_failure_reports_diagnostic" 'test "fail_property" { Test.forall_i64_range(0, 4, x => x < 2) }' 1 "test assertion failed: forall_i64_range"
assert_test_failure_contains "test_property_empty_range_reports_exhaustion" 'test "empty_property" { Test.forall_i64_range(3, 3, x => true) }' 1 "test assertion failed: forall_i64_range_empty"
assert_test_exit_code "test_effect_fixtures_pass" 'fn tool_fail8() -[Fail<i64>]> i64 { Fail.fail(8) } test "fixtures" { Test.assert_eq(Test.with_state_i64(2, () => { TestState.put(TestState.get() + 1) TestState.get() }), 3) Test.assert_eq(Test.expect_fail_i64(8, () => tool_fail8()), 8) Test.assert_eq(Test.with_io_i64(() => IO.open("path", 7, 0)), 107) Test.assert_eq(Test.with_diagnose_i64(() => Diagnose.note("ok", 0)), 3) }' 0
assert_test_failure_contains "test_fixture_missing_fail_reports_diagnostic" 'test "missing_fail" { Test.expect_fail_i64(1, () => 0) }' 1 "test assertion failed: expect_fail_missing"
assert_test_failure_contains "test_fixture_wrong_fail_reports_diagnostic" 'fn tool_fail2() -[Fail<i64>]> i64 { Fail.fail(2) } test "wrong_fail" { Test.expect_fail_i64(1, () => tool_fail2()) }' 1 "test assertion failed: expect_fail_i64"
assert_test_compile_rejects "test_assert_true_rejects_i64" 'test "bad_bool" { Test.assert_true(2) }' "type error: argument type mismatch"
assert_test_compile_rejects "test_assert_str_eq_rejects_i64" 'test "bad_str" { Test.assert_str_eq(1, "one") }' "type error: argument type mismatch"
assert_test_compile_rejects "test_assert_eq_f64_rejects_i64" 'test "bad_f64" { Test.assert_eq_f64(1, 1.0) }' "type error: argument type mismatch"
assert_test_compile_rejects "test_assert_near_f64_rejects_i64_epsilon" 'test "bad_f64_epsilon" { Test.assert_near_f64(1.0, 1.0, 1) }' "type error: argument type mismatch"
assert_test_compile_rejects "test_property_rejects_i64_predicate" 'test "bad_property" { Test.forall_i64_range(0, 1, x => x + 1) }' "type error: return type mismatch"
assert_test_compile_rejects "test_property_rejects_effectful_predicate" $'effect Log { fn hit() -> i64 }\ntest "bad_property_effect" { Test.forall_i64_range(0, 1, x => Log.hit() == x) }' "type error: effect not available in caller"
assert_test_compile_rejects "test_fixture_rejects_unhandled_state" 'test "bad_state" { TestState.get() }' "type error: effect not available in caller"
assert_test_compile_rejects "test_fixture_rejects_wrong_effect_body" 'test "bad_fixture_effect" { Test.with_state_i64(0, () => IO.write(1, 0, 1)) }' "type error: effect not available in caller"
assert_test_compile_rejects "test_fixture_rejects_wrong_return_body" 'test "bad_fixture_return" { Test.with_io_i64(() => "nope") }' "type error: return type mismatch"

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

: > "$tmp_src"
for ((i = 0; i < 1800; i++)); do
  printf 'test "t%d" { Test.assert_eq(1, 1) }\n' "$i" >> "$tmp_src"
done
large_test_check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reads_large_test_harness" "$large_test_check_out" "0 errors"
run_weft_compile_guarded "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>/dev/null
chmod +x "$tmp_bin"
run_binary_guarded "$tmp_bin"
echo "  ok test_builds_large_harness"

echo "Tool boundary summary: 303 passed, 0 failed"
