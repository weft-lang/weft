#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
grammar_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
repo_root=$(CDPATH= cd -- "$grammar_dir/.." && pwd)
tree_sitter="$grammar_dir/node_modules/.bin/tree-sitter"
build_root=${TREE_SITTER_BUILD_DIR:-"$grammar_dir/build/generated"}
grammar_js="$build_root/grammar.js"
generator="$build_root/weft-tree-sitter-grammar"
generator_tmp="$build_root/.weft-tree-sitter-grammar.$$"
weft=${WEFT:-"$repo_root/weft"}

cleanup() {
  rm -f "$generator_tmp"
}
trap cleanup EXIT HUP INT TERM

if [ ! -x "$tree_sitter" ]; then
  echo "tree-sitter-weft: run npm install before generating the parser" >&2
  exit 1
fi

mkdir -p "$build_root/src"
(cd "$repo_root" && "$weft" compile tools/tree_sitter_grammar.weft) > "$generator_tmp"
chmod +x "$generator_tmp"
mv "$generator_tmp" "$generator"
"$generator" > "$grammar_js"
XDG_CACHE_HOME="$build_root/cache" "$tree_sitter" generate \
  --abi "${TREE_SITTER_ABI_VERSION:-14}" \
  --output "$build_root/src" \
  "$grammar_js"
