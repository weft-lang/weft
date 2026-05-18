#!/bin/bash
# run_linked_tests.sh — compile, link, and run test files that use __got_* calls
# These tests emit .o files (not standalone binaries) and need ld to link.
set -e

WEFT=${WEFT:-./weft}
SDK=$(xcrun --show-sdk-path)
PASS=0
FAIL=0
ERRORS=""

echo "=== Linked Test Suite ==="
echo ""

for f in test/linked/*.weft; do
  name=$(basename "$f" .weft)
  tmpobj=$(mktemp /tmp/weft_linked_XXXXXX)
  tmpbin=$(mktemp /tmp/weft_linked_XXXXXX)

  # Compile test blocks to .o. The test harness emits an object whenever
  # __got_* calls are present.
  if ! timeout 30 "$WEFT" test < "$f" > "$tmpobj" 2>/dev/null; then
    echo "  ✗ $name (compilation failed)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: compilation failed"
    rm -f "$tmpobj" "$tmpbin"
    continue
  fi

  # Link with ld
  if ! /usr/bin/ld -o "$tmpbin" "$tmpobj" -lSystem -syslibroot "$SDK" -e _main -arch arm64 2>/dev/null; then
    echo "  ✗ $name (linking failed)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: linking failed"
    rm -f "$tmpobj" "$tmpbin"
    continue
  fi

  chmod +x "$tmpbin"

  # Run and check exit code (0 = pass). Fresh linked binaries can spend more
  # than 10s in cold macOS ad-hoc signature verification on first launch.
  exit_code=0
  timeout 30 "$tmpbin" >/dev/null 2>/dev/null || exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo "  ✓ $name"
    PASS=$((PASS+1))
  else
    echo "  ✗ $name (exit $exit_code)"
    FAIL=$((FAIL+1))
    ERRORS="$ERRORS\n  $name: exit $exit_code"
  fi

  rm -f "$tmpobj" "$tmpbin"
done

echo ""
echo "=== Linked Summary ==="
echo "$PASS passed, $FAIL failed"
if [ -n "$ERRORS" ]; then
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
fi
if [ $FAIL -gt 0 ]; then exit 1; fi
