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
assert_equals "mcp_tools_list_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"parse_summary"},{"name":"check_summary"},{"name":"ir_summary"},{"name":"type_lookup"},{"name":"effect_lookup"},{"name":"diagnostics"}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/list","meta":[true,null,1,-2.5,3e4,{"x":"y"}]}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_nested_extra_json_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tools":[{"name":"parse_summary"},{"name":"check_summary"},{"name":"ir_summary"},{"name":"type_lookup"},{"name":"effect_lookup"},{"name":"diagnostics"}]}}'

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

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"\nfn broken -> i64 { 0 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_parse_error_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":1,"functions":1,"check_errors":0,"items":[{"severity":"error","message":"error: expected '\''('\'' after function name","span":4,"line":2,"col":4}]}}'

mcp_out=$(printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"diagnostics","arguments":{"source":"fn one -> i64 { 0 }\nfn two -> i64 { 1 }"}}}' | "$WEFT" mcp 2>&1)
assert_equals "mcp_diagnostics_many_parse_errors_snapshot" "$mcp_out" '{"jsonrpc":"2.0","id":1,"result":{"tool":"diagnostics","ok":true,"phase":"parse+check","diagnostics":2,"functions":2,"check_errors":0,"items":[{"severity":"error","message":"error: expected '\''('\'' after function name","span":3,"line":1,"col":4},{"severity":"error","message":"error: expected '\''('\'' after function name","span":23,"line":2,"col":4}]}}'

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

echo "Tool boundary summary: 96 passed, 0 failed"
