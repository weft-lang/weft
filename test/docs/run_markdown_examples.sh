#!/bin/bash
# Compile-verify fenced Weft examples in public Markdown documentation.
#
#   ```weft check   type-check the complete fenced module
#   ```weft run     compile and run it; default expected exit is zero
#   ```weft test    compile and run it through the native Test harness
#   ```weft file=PATH
#                    write a project source file in the clean workspace
#   ```bash project  execute the shown commands there, in order
#
# A run block may contain `-- doctest-exit: N` to select another exit code.
set -e

WEFT=${WEFT:-./weft}
if [ "$#" -eq 0 ]; then
  set -- README.md
fi

tmp_src=$(mktemp /tmp/weft_markdown_example_XXXXXX.weft)
tmp_bin=$(mktemp /tmp/weft_markdown_example_bin_XXXXXX)
tmp_linked=$(mktemp /tmp/weft_markdown_example_linked_XXXXXX)
tmp_err=$(mktemp /tmp/weft_markdown_example_err_XXXXXX)
tmp_project=$(mktemp -d /tmp/weft_markdown_project_XXXXXX)
tmp_project_bin=$(mktemp -d /tmp/weft_markdown_tools_XXXXXX)
trap 'rm -f "$tmp_src" "$tmp_bin" "$tmp_linked" "$tmp_err"; rm -rf "$tmp_project" "$tmp_project_bin"' EXIT

WEFT_ABS=$(cd "$(dirname "$WEFT")" && pwd)/$(basename "$WEFT")
ln -s "$WEFT_ABS" "$tmp_project_bin/weft"

passed=0

run_example() {
  local source_file="$1"
  local block_number="$2"
  local mode="$3"
  local expected_exit="$4"
  local project_path="$5"
  local label="${source_file}#${block_number}"

  if [ "$mode" = "file" ]; then
    if [[ ! "$project_path" =~ ^[A-Za-z0-9_./-]+$ ]] ||
       [[ "$project_path" = /* || "$project_path" = ".." || "$project_path" = ../* ||
          "$project_path" = */../* || "$project_path" = */.. ]]; then
      echo "  fail $label (invalid project path: $project_path)"
      exit 1
    fi
    mkdir -p "$tmp_project/$(dirname "$project_path")"
    cp "$tmp_src" "$tmp_project/$project_path"
  elif [ "$mode" = "project" ]; then
    set +e
    (cd "$tmp_project" && PATH="$tmp_project_bin:$PATH" /bin/bash -e "$tmp_src") > /dev/null 2> "$tmp_err"
    local project_exit=$?
    set -e
    if [ "$project_exit" -ne 0 ]; then
      echo "  fail $label (project)"
      sed 's/^/    /' "$tmp_err"
      exit 1
    fi
  elif [ "$mode" = "check" ]; then
    set +e
    "$WEFT" check "$tmp_src" > /dev/null 2> "$tmp_err"
    local check_exit=$?
    set -e
    if [ "$check_exit" -ne 0 ]; then
      echo "  fail $label (check)"
      sed 's/^/    /' "$tmp_err"
      exit 1
    fi
  else
    set +e
    if [ "$mode" = "test" ]; then
      "$WEFT" test --emit "$tmp_src" > "$tmp_bin" 2> "$tmp_err"
    else
      "$WEFT" compile "$tmp_src" > "$tmp_bin" 2> "$tmp_err"
    fi
    local compile_exit=$?
    set -e
    if [ "$compile_exit" -ne 0 ]; then
      echo "  fail $label (compile)"
      sed 's/^/    /' "$tmp_err"
      exit 1
    fi
    local run_bin="$tmp_bin"
    local artifact_kind
    artifact_kind=$(/usr/bin/file -b "$tmp_bin")
    if [[ "$artifact_kind" == *"Mach-O 64-bit object"* ]]; then
      set +e
      /usr/bin/clang -o "$tmp_linked" "$tmp_bin" 2> "$tmp_err"
      local link_exit=$?
      set -e
      if [ "$link_exit" -ne 0 ]; then
        echo "  fail $label (link)"
        sed 's/^/    /' "$tmp_err"
        exit 1
      fi
      run_bin="$tmp_linked"
    fi
    chmod +x "$run_bin"
    set +e
    "$run_bin" > /dev/null 2> "$tmp_err"
    local run_exit=$?
    set -e
    if [ "$run_exit" -ne "$expected_exit" ]; then
      echo "  fail $label (run)"
      echo "    expected exit: $expected_exit"
      echo "    actual exit: $run_exit"
      sed 's/^/    /' "$tmp_err"
      exit 1
    fi
  fi

  echo "  ok $label ($mode)"
  passed=$((passed + 1))
}

for markdown_file in "$@"; do
  if [ ! -f "$markdown_file" ]; then
    echo "  fail $markdown_file (missing documentation file)"
    exit 1
  fi

  in_block=0
  block_mode=""
  block_number=0
  file_blocks=0
  expected_exit=0
  project_path=""
  : > "$tmp_src"

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_block" -eq 0 ]; then
      if [ "$line" = '```weft check' ]; then
        in_block=1
        block_mode="check"
        block_number=$((block_number + 1))
        expected_exit=0
        : > "$tmp_src"
      elif [ "$line" = '```weft run' ]; then
        in_block=1
        block_mode="run"
        block_number=$((block_number + 1))
        expected_exit=0
        : > "$tmp_src"
      elif [ "$line" = '```weft test' ]; then
        in_block=1
        block_mode="test"
        block_number=$((block_number + 1))
        expected_exit=0
        : > "$tmp_src"
      elif [[ "$line" == '```weft file='* ]]; then
        in_block=1
        block_mode="file"
        block_number=$((block_number + 1))
        expected_exit=0
        project_path="${line#*file=}"
        : > "$tmp_src"
      elif [ "$line" = '```bash project' ]; then
        in_block=1
        block_mode="project"
        block_number=$((block_number + 1))
        expected_exit=0
        project_path=""
        : > "$tmp_src"
      fi
    elif [ "$line" = '```' ]; then
      run_example "$markdown_file" "$block_number" "$block_mode" "$expected_exit" "$project_path"
      file_blocks=$((file_blocks + 1))
      in_block=0
      block_mode=""
      project_path=""
    else
      if [[ "$line" =~ ^[[:space:]]*--[[:space:]]doctest-exit:[[:space:]]([0-9]+)$ ]]; then
        expected_exit="${BASH_REMATCH[1]}"
      fi
      printf '%s\n' "$line" >> "$tmp_src"
    fi
  done < "$markdown_file"

  if [ "$in_block" -ne 0 ]; then
    echo "  fail $markdown_file (unterminated checked Weft fence)"
    exit 1
  fi
  if [ "$file_blocks" -eq 0 ]; then
    echo "  fail $markdown_file (no checked Weft fences)"
    exit 1
  fi
done

echo "Markdown example summary: $passed passed, 0 failed"
