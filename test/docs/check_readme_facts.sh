#!/bin/bash
# Keep README corpus claims tied to the runner's actual discovery rules.
set -e

runtime_files=0
runtime_blocks=0

for test_file in test/*.weft; do
  if grep -q 'test "' "$test_file"; then
    file_blocks=$(grep -c 'test "' "$test_file")
    runtime_files=$((runtime_files + 1))
    runtime_blocks=$((runtime_blocks + file_blocks))
  elif grep -qE '(^|[[:space:]])fn[[:space:]]+main[[:space:]]*\(' "$test_file"; then
    runtime_files=$((runtime_files + 1))
    runtime_blocks=$((runtime_blocks + 1))
  fi
done

negative_files=0
for negative_file in test/negative/*.weft; do
  if [ -f "$negative_file" ]; then
    negative_files=$((negative_files + 1))
  fi
done

expected="${runtime_blocks} runtime test blocks across ${runtime_files} files, plus ${negative_files} negative (must-fail) cases"
if grep -Fq "$expected" README.md; then
  echo "  ok README corpus census ($runtime_blocks blocks, $runtime_files files, $negative_files negatives)"
else
  echo "  fail README corpus census"
  echo "    expected README.md to contain: $expected"
  exit 1
fi
