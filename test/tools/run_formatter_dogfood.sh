#!/bin/bash
# Formatter dogfood: rewrite a repository mirror and prove every formatted
# source is already the canonical byte-for-byte checkout source.
set -e

WEFT=${WEFT:-./weft}
case "$WEFT" in
  /*) WEFT_ABS="$WEFT" ;;
  *) WEFT_ABS="$(pwd)/$WEFT" ;;
esac

MIRROR=$(mktemp -d /tmp/weft_formatter_dogfood_XXXXXX)
trap 'rm -rf "$MIRROR"' EXIT

PASS=0

ok() {
  echo "  ok $1"
  PASS=$((PASS+1))
}

fail() {
  echo "  fail $1"
  if [ -n "$2" ] && [ -s "$2" ]; then
    while IFS= read -r line; do
      echo "    $line"
    done < "$2"
  fi
  exit 1
}

echo "=== Formatter Dogfood ==="
echo ""

# Run the formatter in a complete checkout mirror so its module discovery and
# SDK selection are identical to the repository invocation.
cp -R compiler runtime stdlib tools test module_fixtures native "$MIRROR/"
cp weft.pkg "$MIRROR/"
cp "$WEFT_ABS" "$MIRROR/weft-bootstrap"

if (
  cd "$MIRROR"
  ./weft-bootstrap fmt --write compiler runtime stdlib tools test/*.weft \
    test/linked/tool_platform.weft > fmt-write.out 2> fmt-write.err
); then
  ok "formatter_rewrites_repository_mirror"
else
  fail "formatter_rewrites_repository_mirror" "$MIRROR/fmt-write.err"
fi

if [ ! -s "$MIRROR/fmt-write.out" ] && [ ! -s "$MIRROR/fmt-write.err" ]; then
  ok "formatter_mirror_write_is_silent"
else
  fail "formatter_mirror_write_is_silent" "$MIRROR/fmt-write.err"
fi

if (
  cd "$MIRROR"
  ./weft-bootstrap fmt --check compiler runtime stdlib tools test/*.weft \
    test/linked/tool_platform.weft > fmt-check.out 2> fmt-check.err
); then
  ok "formatter_repository_mirror_is_idempotent"
else
  fail "formatter_repository_mirror_is_idempotent" "$MIRROR/fmt-check.err"
fi

if [ ! -s "$MIRROR/fmt-check.out" ] && [ ! -s "$MIRROR/fmt-check.err" ]; then
  ok "formatter_mirror_check_is_silent"
else
  fail "formatter_mirror_check_is_silent" "$MIRROR/fmt-check.err"
fi

formatter_sources_match_checkout() {
  local source
  while IFS= read -r -d '' source; do
    if ! cmp -s "$source" "$MIRROR/$source"; then return 1; fi
  done < <(find compiler runtime stdlib tools -type f -name '*.weft' -print0)
  for source in test/*.weft test/linked/tool_platform.weft; do
    if ! cmp -s "$source" "$MIRROR/$source"; then return 1; fi
  done
}

# When these bytes match, the ordinary bootstrap gate already proves the
# formatted compiler: rebuilding three generations from an identical mirror
# adds no evidence and only competes with the runtime suite for the host.
if formatter_sources_match_checkout; then
  ok "repository_weft_sources_are_canonical"
else
  fail "repository_weft_sources_are_canonical" "$MIRROR/fmt-write.err"
fi

echo ""
echo "Formatter dogfood summary: $PASS passed, 0 failed"
