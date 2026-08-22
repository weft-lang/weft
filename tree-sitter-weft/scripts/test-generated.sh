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
  all|grammar|corpus|queries) ;;
  *)
    echo "usage: $0 [all|grammar|corpus|queries]" >&2
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
  "$tree_sitter" parse \
    --lib-path "$parser" \
    --lang-name weft \
    --quiet \
    --stat \
    "$repo_root"/compiler/*.weft \
    "$repo_root"/stdlib/*.weft \
    "$repo_root"/runtime/*.weft \
    "$repo_root"/tools/*.weft \
    "$repo_root"/test/*.weft
fi

if [ "$mode" = all ] || [ "$mode" = queries ]; then
  query_source="$work_dir/query-fixture.weft"
  highlight_output="$work_dir/highlights.txt"
  locals_output="$work_dir/locals.txt"
  printf '%s\n' \
    'use compiler/grammar.{*}' \
    'type QueryBox { value: i64 }' \
    'fn query_read(input: QueryBox) -> i64 {' \
    '  let local = input' \
    '  local.value' \
    '}' > "$query_source"

  "$tree_sitter" query \
    --lib-path "$parser" \
    --lang-name weft \
    "$grammar_dir/queries/weft/highlights.scm" \
    "$query_source" > "$highlight_output"
  test -s "$highlight_output"
  grep -q -- '- keyword' "$highlight_output"
  grep -q -- '- function' "$highlight_output"

  "$tree_sitter" query \
    --lib-path "$parser" \
    --lang-name weft \
    "$grammar_dir/queries/weft/locals.scm" \
    "$query_source" > "$locals_output"
  test -s "$locals_output"
  grep -q -- '- local.definition' "$locals_output"
  grep -q -- '- local.reference' "$locals_output"
fi
