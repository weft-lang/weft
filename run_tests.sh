#!/bin/bash
# run_tests.sh — thin test runner for weft test files
# Compiles each test/*.weft file with `weft test`, runs the binary, reports results.
set -e

WEFT=${WEFT:-./weft}
PASS=0
FAIL=0
ERRORS=""
RUNTIME_FILES=0
RUNTIME_TESTS=0

echo "=== Weft Test Suite ==="
echo ""

for f in $(grep -l 'test "' test/*.weft 2>/dev/null); do
  name=$(basename "$f" .weft)
  tmpbin=$(mktemp /tmp/weft_test_XXXXXX)
  file_tests=$(grep -c 'test "' "$f")
  RUNTIME_FILES=$((RUNTIME_FILES+1))
  RUNTIME_TESTS=$((RUNTIME_TESTS+file_tests))

  # Compile test file
  if [ "$name" = "unsafe_boundary" ]; then
    compile_cmd=(timeout 30 "$WEFT" test "$f")
  else
    compile_cmd=(timeout 30 "$WEFT" test)
  fi
  if [ "$name" = "unsafe_boundary" ]; then
    if ! "${compile_cmd[@]}" > "$tmpbin" 2>/dev/null; then
      echo "  ✗ $name (compilation failed)"
      FAIL=$((FAIL+1))
      ERRORS="$ERRORS\n  $name: compilation failed"
      rm -f "$tmpbin"
      continue
    fi
  elif ! "${compile_cmd[@]}" < "$f" > "$tmpbin" 2>/dev/null; then
    echo "  ✗ $name (compilation failed)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: compilation failed"
    rm -f "$tmpbin"
    continue
  fi

  chmod +x "$tmpbin"

  # Run test binary
  exit_code=0
  timeout 10 "$tmpbin" 2>/dev/null || exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo "  ✓ $name"
    PASS=$((PASS+1))
  else
    echo "  ✗ $name ($exit_code failures)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: $exit_code failures"
  fi

  rm -f "$tmpbin"
done

echo ""
echo "=== Bootstrap Gate ==="
# Quick 3-stage bootstrap check
tmpw1=$(mktemp /tmp/weft_test_XXXXXX)
tmpw2=$(mktemp /tmp/weft_test_XXXXXX)
tmpw3=$(mktemp /tmp/weft_test_XXXXXX)
bootstrap_ok=1
if "$WEFT" compile compiler/main.weft > "$tmpw1" 2>/dev/null; then
  chmod +x "$tmpw1"
else
  bootstrap_ok=0
  echo "  ✗ bootstrap stage 1 failed"
fi
if [ $bootstrap_ok -eq 1 ]; then
  if "$tmpw1" compile compiler/main.weft > "$tmpw2" 2>/dev/null; then
    chmod +x "$tmpw2"
  else
    bootstrap_ok=0
    echo "  ✗ bootstrap stage 2 failed"
  fi
fi
if [ $bootstrap_ok -eq 1 ]; then
  if "$tmpw2" compile compiler/main.weft > "$tmpw3" 2>/dev/null; then
    chmod +x "$tmpw3"
  else
    bootstrap_ok=0
    echo "  ✗ bootstrap stage 3 failed"
  fi
fi
if [ $bootstrap_ok -eq 1 ] && diff <(xxd "$tmpw2") <(xxd "$tmpw3") > /dev/null 2>&1; then
  echo "  ✓ weft2 == weft3 (byte-identical)"
  PASS=$((PASS+1))
else
  echo "  ✗ bootstrap gate failed"
  FAIL=$((FAIL+1))
fi
rm -f "$tmpw1" "$tmpw2" "$tmpw3"

echo ""
echo "=== Linked Tests ==="
if bash test/linked/run_linked_tests.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ linked tests failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  linked tests failed"
fi

echo ""
echo "=== Checker Tests ==="
if bash test/checker/run_checker_tests.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ checker tests failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  checker tests failed"
fi

echo ""
echo "=== Tool Boundary Tests ==="
if bash test/tools/run_tool_tests.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ tool boundary tests failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  tool boundary tests failed"
fi

echo ""
echo "=== Negative Tests ==="
if bash test/negative/run_negative_tests.sh; then
  PASS=$((PASS+1))
else
  echo "  ✗ negative tests failed"
  FAIL=$((FAIL+1))
  ERRORS="$ERRORS\n  negative tests failed"
fi

echo ""
echo "=== Summary ==="
echo "$PASS suite groups passed, $FAIL failed"
echo "Runtime tests: $RUNTIME_FILES files, $RUNTIME_TESTS test blocks"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
