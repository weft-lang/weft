#!/bin/bash
# Tool boundary tests: parse-only, check-only, and AST tool paths.
set -e

WEFT=${WEFT:-./weft}
tmp_src=$(mktemp /tmp/weft_tool_src_XXXXXX)
tmp_import=$(mktemp /tmp/weft_tool_import_XXXXXX)
tmp_bin=$(mktemp /tmp/weft_tool_bin_XXXXXX)
trap 'rm -f "$tmp_src" "$tmp_import" "$tmp_bin"' EXIT

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

printf 'fn main() -> i64 { missing }\n' > "$tmp_src"
diag_out=$("$WEFT" check < "$tmp_src" 2>&1)
assert_contains "check_reports_diagnostics" "$diag_out" "type error: unknown identifier"

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

echo "Tool boundary summary: 8 passed, 0 failed"
