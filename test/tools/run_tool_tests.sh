#!/bin/bash
# Tool boundary tests: parse-only, check-only, and AST tool paths.
set -e

WEFT=${WEFT:-./weft}
tmp_src=$(mktemp /tmp/weft_tool_src_XXXXXX)
tmp_import=$(mktemp /tmp/weft_tool_import_XXXXXX)
tmp_bin=$(mktemp /tmp/weft_tool_bin_XXXXXX)
tmp_err=$(mktemp /tmp/weft_tool_err_XXXXXX)
trap 'rm -f "$tmp_src" "$tmp_import" "$tmp_bin" "$tmp_err"' EXIT

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
  "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
  chmod +x "$tmp_bin"
  set +e
  "$tmp_bin" >/dev/null 2>&1
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
  "$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
  chmod +x "$tmp_bin"
  set +e
  "$tmp_bin" >/dev/null 2>"$tmp_err"
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
  out=$("$WEFT" test < "$tmp_src" 2>&1 >/dev/null || true)
  assert_contains "$name" "$out" "$pattern"
}

write_large_padding() {
  local file="$1"
  : > "$file"
  for ((i = 0; i < 1800; i++)); do
    printf -- '-- padding padding padding padding padding padding padding padding padding padding\n' >> "$file"
  done
}

printf 'fn main() -> i64 { 42 }\n' > "$tmp_src"

fmt_out=$("$WEFT" fmt < "$tmp_src" 2>&1)
assert_contains "fmt_parse_only" "$fmt_out" "fn main() -> i64 { 42 }"
assert_equals "fmt_snapshot_exact" "$fmt_out" "fn main() -> i64 { 42 }"

ast_out=$("$WEFT" ast < "$tmp_src" 2>&1)
assert_contains "ast_parse_only_header" "$ast_out" "--- AST: 1 functions ---"
assert_contains "ast_parse_only_literal" "$ast_out" "IntLit(42)"
assert_equals "ast_snapshot_exact" "$ast_out" $'--- AST: 1 functions ---\n\nfn main:\n  IntLit(42)'

check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_parse_and_typecheck" "$check_out" "check: 1 functions, 0 errors"

printf 'fn broken() -> i64 { 1\nfn after() -> i64 { 2 }\n' > "$tmp_src"
parse_recovery_out=$("$WEFT" ast < "$tmp_src" 2>&1)
assert_contains "ast_reports_parse_recovery" "$parse_recovery_out" "error: expected '}' before declaration"
assert_contains "ast_recovers_after_parse_error" "$parse_recovery_out" "--- AST: 2 functions ---"

printf 'fn main() -> i64 { missing }\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reports_diagnostics" "$diag_out" "type error: unknown identifier"
assert_equals "diagnostic_snapshot_exact" "$diag_out" $'line 1, col 20: type error: unknown identifier\ncheck: 1 functions, 0 errors'

mcp_out=$(printf '%s' '{ "jsonrpc" : "2.0", "id" : 1, "method" : "tools/list" }' | "$WEFT" mcp 2>&1)
assert_equals "mcp_tools_list_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"parse_summary"},{"name":"check_summary"},{"name":"ir_summary"},{"name":"type_lookup"},{"name":"effect_lookup"},{"name":"diagnostics"},{"name":"grammar_parse"},{"name":"grammar_check"},{"name":"grammar_diagnostics"}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/list","meta":[true,null,1,-2.5,3e4,{"x":"y"}]}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_nested_extra_json_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"parse_summary"},{"name":"check_summary"},{"name":"ir_summary"},{"name":"type_lookup"},{"name":"effect_lookup"},{"name":"diagnostics"},{"name":"grammar_parse"},{"name":"grammar_check"},{"name":"grammar_diagnostics"}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"parse_summary","arguments":{"source" : "fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_parse_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"parse_summary","ok":true,"functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"check_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_check_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"check_summary","ok":true,"functions":1,"first_body_tag":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"ir_summary","arguments":{"source":"fn main() -> i64 { 42 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_ir_summary_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"ir_summary","ok":true,"functions":1,"blocks":1,"insts":1}}'

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

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_parse","arguments":{"grammar":"mini_sql","source":"select id, name from users where id = 1"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_parse_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_parse","ok":true,"grammar":"mini_sql","root_tag":701,"columns":2,"star":0,"table":"users","where":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select id from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"users","where":0,"check_errors":0}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_check","arguments":{"grammar":"mini_sql","source":"select nope from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_check_unknown_column_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_check","ok":true,"grammar":"mini_sql","root_tag":701,"columns":1,"star":0,"table":"users","where":0,"check_errors":1}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select nope from users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_type_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":1,"check_errors":1,"items":[{"severity":"error","message":"mini_sql type error: unknown column","span":7,"line":1,"col":8}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grammar_diagnostics","arguments":{"grammar":"mini_sql","source":"select id users"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_grammar_diagnostics_parse_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"grammar_diagnostics","ok":true,"grammar":"mini_sql","phase":"parse+check","diagnostics":2,"check_errors":0,"items":[{"severity":"error","message":"mini_sql parse error: expected FROM","span":10,"line":1,"col":11},{"severity":"error","message":"mini_sql parse error: expected table name","span":15,"line":1,"col":16}]}}'

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

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type M { v: i64 } impl M { fn add(self: i64, n: i64) -> i64 { __mem_load64(self) + n } } fn bad(b: M) -> i64 { b.add() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_method_arity_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: arity mismatch","span":111,"line":1,"col":112}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type M { v: i64 } impl M { fn add(self: i64, n: i64) -> i64 { __mem_load64(self) + n } } fn bad(b: M) -> i64 { b.add(\"nope\") }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_method_arg_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: argument type mismatch","span":111,"line":1,"col":112}]}}'

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
assert_equals "mcp_diagnostics_unknown_got_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown GOT symbol","span":26,"line":1,"col":27}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"type NoMeth { v: i64 } fn bad(x: NoMeth) -> i64 { x.missing() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_unknown_method_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: unknown method","span":50,"line":1,"col":51}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let mut x = 1 let f = () => x f() }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_mut_capture_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: cannot capture mut binding","span":46,"line":1,"col":47}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.put() -> resume(0) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_unknown_op_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":2,"functions":1,"check_errors":2,"items":[{"severity":"error","message":"type error: missing handler clause","span":64,"line":1,"col":65},{"severity":"error","message":"type error: unknown effect operation","span":78,"line":1,"col":79}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect A { fn f() -> i64 } effect B { fn f() -> i64 } fn bad() -> i64 { handle A.f() { A.f() -> resume(1) B.f() -> resume(2) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_effect_mismatch_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: handler clause effect mismatch","span":106,"line":1,"col":107}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect PlainDelay { fn get() -> i64 } fn main() -> i64 { handle PlainDelay.get() { PlainDelay.get() with k -> resume(42) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_non_deferred_k_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":2,"functions":1,"check_errors":2,"items":[{"severity":"error","message":"type error: handler continuation requires deferred effect operation","span":105,"line":1,"col":106},{"severity":"error","message":"type error: use continuation binding instead of resume","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> resume(\"nope\") } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_resume_type_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: resume type mismatch","span":78,"line":1,"col":79}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> resume(1) State.get() -> resume(2) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_duplicate_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: duplicate handler clause","span":103,"line":1,"col":104}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 fn put(v: i64) -> i64 } fn bad() -> i64 { handle { State.get() + State.put(1) } { State.get() -> resume(1) } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_handler_missing_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: missing handler clause","span":102,"line":1,"col":103}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { resume(1) }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_resume_outside_handler_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: resume outside handler clause","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect State { fn get() -> i64 } fn bad() -> i64 { handle State.get() { State.get() -> { let f = x => resume(x) f(1) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_resume_capture_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: cannot capture resume","span":109,"line":1,"col":110}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Async { @deferred fn get() -> i64 } fn apply_saved(f: (i64) -> i64) -> i64 { f(1) } fn bad() -> i64 { handle Async.get() { Async.get() with k -> { let f = x => k(x) apply_saved(f) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_continuation_escape_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: continuation cannot escape","span":184,"line":1,"col":185}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect Async { @deferred fn get() -> i64 } fn bad() -> i64 { handle Async.get() { Async.get() with k -> { k(1) k(2) } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_continuation_multiple_use_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: continuation used more than once","span":99,"line":1,"col":100}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"effect DeferredK { @deferred fn step(value: rc i64) -> rc i64 } fn go(value: rc i64) -[DeferredK]> rc i64 { DeferredK.step(value) } fn main(p: rc i64) -> rc i64 { handle go(p) { DeferredK.step(value) with k -> { let resumed = k(value) resumed } } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_continuation_non_tail_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":2,"check_errors":1,"items":[{"severity":"error","message":"type error: continuation call must be tail position","span":205,"line":1,"col":206}]}}'

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
assert_equals "mcp_diagnostics_pattern_literal_scrutinee_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: literal pattern does not match scrutinee","span":0,"line":1,"col":1}]}}'

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
assert_equals "mcp_diagnostics_if_condition_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { let mut x = 0 while 1 { x = x + 1 } x }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_while_condition_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { not 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_not_operand_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { true and 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_logical_operand_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad(n: i64) -> i64 { match n { x if x -> x _ -> 0 } }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_match_guard_bool_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: boolean expression is not bool","span":39,"line":1,"col":40}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { 1 == \"one\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_equality_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: equality operand mismatch","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> bool { \"a\" < \"b\" }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_comparison_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":2,"functions":1,"check_errors":2,"items":[{"severity":"error","message":"type error: comparison operand is not i64","span":-1,"line":-1,"col":-1},{"severity":"error","message":"type error: comparison operand is not i64","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { true band 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_bitwise_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: bitwise operand is not i64","span":-1,"line":-1,"col":-1}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn bad() -> i64 { 1 bshl false }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_shift_operand_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":1,"items":[{"severity":"error","message":"type error: bitwise operand is not i64","span":-1,"line":-1,"col":-1}]}}'

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
amp_diag_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_rejects_symbolic_and" "$amp_diag_out" "error: expected '}'"

write_large_padding "$tmp_src"
printf 'fn main() -> i64 { 0 }\n' >> "$tmp_src"
large_check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reads_large_stdin" "$large_check_out" "check: 1 functions, 0 errors"
"$WEFT" < "$tmp_src" > "$tmp_bin" 2>/dev/null
chmod +x "$tmp_bin"
"$tmp_bin"
echo "  ok compile_reads_large_stdin"

write_large_padding "$tmp_import"
printf 'fn sentinel() -> i64 { 99 }\n' >> "$tmp_import"
printf 'use "%s"\nfn main() -> i64 { sentinel() }\n' "$tmp_import" > "$tmp_src"
large_import_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reads_large_import" "$large_import_out" "check: 2 functions, 0 errors"

printf 'test "plain" { Test.assert_eq(1, 1) }\n' > "$tmp_src"
"$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_not_contains_file "test_harness_binds_runtime_without_missing_symbols" "$tmp_err" "required runtime function unavailable"
chmod +x "$tmp_bin"
"$tmp_bin"
echo "  ok test_harness_binds_runtime_after_synthesis"

printf 'test "helpers" { Test.assert_eq(1, 1) Test.assert_ne(1, 2) Test.assert_true(1 == 1) Test.assert_false(1 == 2) Test.assert_lt(1, 2) Test.assert_le(2, 2) Test.assert_gt(3, 2) Test.assert_ge(3, 3) Test.forall_i64_range(0, 3, x => x < 3) Test.assert_eq(Test.with_state_i64(4, () => State.get()), 4) Test.assert_eq(Test.expect_fail_i64(5, () => Fail.fail(5)), 5) Test.assert_eq(Test.with_io_i64(() => IO.write(1, 0, 2)), 2) Test.assert_eq(Test.with_diagnose_i64(() => Diagnose.error("x", 0 - 1)), 1) }\n' > "$tmp_src"
"$WEFT" test < "$tmp_src" > "$tmp_bin" 2>"$tmp_err"
assert_not_contains_file "test_harness_supports_assertion_helpers" "$tmp_err" "unknown effect operation"
chmod +x "$tmp_bin"
"$tmp_bin"
echo "  ok test_assertion_helpers_pass"

assert_test_exit_code "test_assert_eq_failure_returns_one" 'test "fail_eq" { Test.assert_eq(1, 2) }' 1
assert_test_exit_code "test_assert_eq_and_ne_two_clause_harness_runs" 'test "eq_ne" { Test.assert_eq(0, 0) Test.assert_ne(1, 2) }' 0
assert_test_exit_code "test_assert_ne_failure_returns_one" 'test "fail_ne" { Test.assert_ne(2, 2) }' 1
assert_test_exit_code "test_assert_bool_failures_return_two" $'test "fail_true" { Test.assert_true(1 == 2) }\ntest "fail_false" { Test.assert_false(1 == 1) }' 2
assert_test_exit_code "test_assert_comparison_failure_returns_one" 'test "fail_cmp" { Test.assert_lt(2, 1) }' 1
assert_test_failure_contains "test_assertion_failure_reports_diagnostic" 'test "fail_eq_diag" { Test.assert_eq(1, 2) }' 1 "test assertion failed: assert_eq"
assert_test_failure_contains "test_snapshot_mismatch_reports_diagnostic" 'test "fail_snapshot" { Test.assert_snapshot("actual", "expected") }' 1 "test assertion failed: snapshot"
assert_test_failure_contains "test_property_failure_reports_diagnostic" 'test "fail_property" { Test.forall_i64_range(0, 4, x => x < 2) }' 1 "test assertion failed: forall_i64_range"
assert_test_failure_contains "test_property_empty_range_reports_exhaustion" 'test "empty_property" { Test.forall_i64_range(3, 3, x => true) }' 1 "test assertion failed: forall_i64_range_empty"
assert_test_exit_code "test_effect_fixtures_pass" 'test "fixtures" { Test.assert_eq(Test.with_state_i64(2, () => { State.put(State.get() + 1) State.get() }), 3) Test.assert_eq(Test.expect_fail_i64(8, () => Fail.fail(8)), 8) Test.assert_eq(Test.with_io_i64(() => IO.open(0, 7, 0)), 107) Test.assert_eq(Test.with_diagnose_i64(() => Diagnose.note("ok", 0)), 3) }' 0
assert_test_failure_contains "test_fixture_missing_fail_reports_diagnostic" 'test "missing_fail" { Test.expect_fail_i64(1, () => 0) }' 1 "test assertion failed: expect_fail_missing"
assert_test_failure_contains "test_fixture_wrong_fail_reports_diagnostic" 'test "wrong_fail" { Test.expect_fail_i64(1, () => Fail.fail(2)) }' 1 "test assertion failed: expect_fail_i64"
assert_test_compile_rejects "test_assert_true_rejects_i64" 'test "bad_bool" { Test.assert_true(1) }' "type error: argument type mismatch"
assert_test_compile_rejects "test_assert_str_eq_rejects_i64" 'test "bad_str" { Test.assert_str_eq(1, "one") }' "type error: argument type mismatch"
assert_test_compile_rejects "test_property_rejects_i64_predicate" 'test "bad_property" { Test.forall_i64_range(0, 1, x => x + 1) }' "type error: return type mismatch"
assert_test_compile_rejects "test_property_rejects_effectful_predicate" $'effect Log { fn hit() -> i64 }\ntest "bad_property_effect" { Test.forall_i64_range(0, 1, x => Log.hit() == x) }' "type error: effect not available in caller"
assert_test_compile_rejects "test_fixture_rejects_unhandled_state" 'test "bad_state" { State.get() }' "type error: effect not available in caller"
assert_test_compile_rejects "test_fixture_rejects_wrong_effect_body" 'test "bad_fixture_effect" { Test.with_state_i64(0, () => IO.write(1, 0, 1)) }' "type error: effect not available in caller"
assert_test_compile_rejects "test_fixture_rejects_wrong_return_body" 'test "bad_fixture_return" { Test.with_io_i64(() => true) }' "type error: return type mismatch"

: > "$tmp_src"
for ((i = 0; i < 1800; i++)); do
  printf 'test "t%d" { Test.assert_eq(1, 1) }\n' "$i" >> "$tmp_src"
done
"$WEFT" test < "$tmp_src" > "$tmp_bin" 2>/dev/null
chmod +x "$tmp_bin"
"$tmp_bin"
echo "  ok test_builds_large_harness"

echo "Tool boundary summary: 178 passed, 0 failed"
