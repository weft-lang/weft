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

ast_out=$("$WEFT" ast < "$tmp_src" 2>&1)
assert_contains "ast_parse_only_header" "$ast_out" "--- AST: 1 functions ---"
assert_contains "ast_parse_only_literal" "$ast_out" "IntLit(42)"

check_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_parse_and_typecheck" "$check_out" "check: 1 functions, 0 errors"

printf 'fn broken() -> i64 { 1\nfn after() -> i64 { 2 }\n' > "$tmp_src"
parse_recovery_out=$("$WEFT" ast < "$tmp_src" 2>&1)
assert_contains "ast_reports_parse_recovery" "$parse_recovery_out" "error: expected '}' before declaration"
assert_contains "ast_recovers_after_parse_error" "$parse_recovery_out" "--- AST: 2 functions ---"

printf 'fn main() -> i64 { missing }\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reports_diagnostics" "$diag_out" "type error: unknown identifier"

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

: > "$tmp_src"
for ((i = 0; i < 1800; i++)); do
  printf 'test "t%d" { Test.assert_eq(1, 1) }\n' "$i" >> "$tmp_src"
done
"$WEFT" test < "$tmp_src" > "$tmp_bin" 2>/dev/null
chmod +x "$tmp_bin"
"$tmp_bin"
echo "  ok test_builds_large_harness"

echo "Tool boundary summary: 14 passed, 0 failed"
