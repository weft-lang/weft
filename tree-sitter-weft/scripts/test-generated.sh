#!/bin/sh
set -eu

mode=${1:-all}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
grammar_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
repo_root=$(CDPATH= cd -- "$grammar_dir/.." && pwd)
tree_sitter="$grammar_dir/node_modules/.bin/tree-sitter"
temp_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "${temp_root%/}/weft-tree-sitter.XXXXXX")
parser="$work_dir/weft.so"
generator="$work_dir/weft-tree-sitter-grammar"
weft=${WEFT:-"$repo_root/weft"}

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

if [ ! -x "$tree_sitter" ]; then
  echo "tree-sitter-weft: run npm install before testing the parser" >&2
  exit 1
fi

case "$mode" in
  all|grammar|corpus|queries|rejections) ;;
  *)
    echo "usage: $0 [all|grammar|corpus|queries|rejections]" >&2
    exit 2
    ;;
esac

(cd "$repo_root" && "$weft" compile tools/tree_sitter_grammar.weft) > "$generator"
chmod +x "$generator"
"$generator" > "$work_dir/grammar.js"
"$generator" > "$work_dir/grammar-second.js"
cmp "$work_dir/grammar.js" "$work_dir/grammar-second.js"

"$tree_sitter" generate \
  --abi 14 \
  --output "$work_dir/src" \
  "$work_dir/grammar.js"
XDG_CACHE_HOME="$work_dir/cache" "$tree_sitter" build --output "$parser" "$work_dir"

if [ "$mode" = all ] || [ "$mode" = grammar ]; then
  mkdir -p "$work_dir/test"
  cp -R "$grammar_dir/test/corpus" "$work_dir/test/corpus"
  (cd "$grammar_dir" && XDG_CACHE_HOME="$work_dir/cache" "$tree_sitter" test \
    --grammar-path "$work_dir" \
    --lib-path "$parser" \
    --lang-name weft)
fi

if [ "$mode" = all ] || [ "$mode" = corpus ]; then
  # Include nested source modules and runnable examples. Negative fixtures are
  # intentionally outside this acceptance corpus. NUL framing preserves paths.
  {
    find "$repo_root/compiler" "$repo_root/stdlib" "$repo_root/runtime" \
      "$repo_root/tools" "$repo_root/examples" -type f -name '*.weft' -print0
    printf '%s\0' "$repo_root"/test/*.weft
  } | xargs -0 "$tree_sitter" parse \
    --lib-path "$parser" \
    --lang-name weft \
    --quiet \
    --stat
fi

if [ "$mode" = all ] || [ "$mode" = queries ]; then
  query_source="$work_dir/query-fixture.weft"
  highlight_output="$work_dir/highlights.txt"
  locals_output="$work_dir/locals.txt"
  printf '%s\n' \
    'use stdlib/grammar.{Grammar}' \
    'type QueryBox { value: i64 }' \
    'fn query_read(input: QueryBox) -> i64 {' \
    '  let local = input' \
    '  local.value' \
    '}' \
    'effect Cell<T> { fn get() -> T }' \
    'pub implements<T> Cell<T>(initial: T) {' \
    '  Cell<T>.get() -> resume(initial)' \
    '}' \
    'default handler defaults()' \
    'fn query_handler() -> i64 { with state<i64>(42) { Cell<i64>.get() } }' > "$query_source"

  "$tree_sitter" query \
    --lib-path "$parser" \
    --lang-name weft \
    "$grammar_dir/queries/weft/highlights.scm" \
    "$query_source" > "$highlight_output"
  test -s "$highlight_output"
  grep -q -- '- keyword' "$highlight_output"
  grep -q -- '- function' "$highlight_output"
  grep -q -- 'keyword.*text: `implements`' "$highlight_output"
  grep -q -- 'keyword.*text: `default`' "$highlight_output"
  grep -q -- 'module.*text: `state`' "$highlight_output"

  "$tree_sitter" query \
    --lib-path "$parser" \
    --lang-name weft \
    "$grammar_dir/queries/weft/locals.scm" \
    "$query_source" > "$locals_output"
  test -s "$locals_output"
  grep -q -- '- local.definition' "$locals_output"
  grep -q -- '- local.reference' "$locals_output"
  grep -q -- 'local.definition.*text: `initial`' "$locals_output"
  grep -q -- 'local.reference.*text: `initial`' "$locals_output"
fi

if [ "$mode" = all ] || [ "$mode" = rejections ]; then
  # Both parsers must reject unsupported module syntax. These fixtures carry
  # no checker-only rejection and must never yield formatted source.
  for fixture in module_stray_brace module_stray_paren module_stray_bracket \
    module_stray_comma module_stray_colon module_stray_equals \
    module_empty_block module_empty_parens module_empty_brackets \
    module_bare_let module_bare_else module_bare_return \
    module_trailing_visibility module_trailing_package_visibility \
    module_repeated_visibility module_keyword_body; do
    source="$repo_root/test/negative/$fixture.weft"
    if "$tree_sitter" parse --lib-path "$parser" --lang-name weft --quiet \
      "$source" > "$work_dir/rejection.txt" 2>&1; then
      echo "tree-sitter-weft: accepted invalid syntax in $fixture" >&2
      exit 1
    fi
    grep -Eq 'ERROR|MISSING' "$work_dir/rejection.txt"
    if (cd "$repo_root" && "$weft" fmt "$source") \
      > "$work_dir/formatted.weft" 2> "$work_dir/diagnostic.txt"; then
      echo "weft: accepted invalid syntax in $fixture" >&2
      exit 1
    fi
    test ! -s "$work_dir/formatted.weft"
    grep -Fq 'error[E0002]' "$work_dir/diagnostic.txt"
  done
fi
