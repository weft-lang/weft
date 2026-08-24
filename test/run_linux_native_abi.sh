#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
fixture_root="$project_root/test/fixtures/linux_native_abi"
weft_bin=${WEFT:-"$project_root/weft"}

case "$weft_bin" in
  /*) ;;
  *) weft_bin=$(CDPATH= cd -- "$(dirname "$weft_bin")" && pwd -P)/$(basename "$weft_bin") ;;
esac

if [ "$(uname -s)" != Linux ]; then
  echo "linux native ABI gate requires a Linux host" >&2
  exit 2
fi
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) echo "linux native ABI gate requires an AArch64 host" >&2; exit 2 ;;
esac

command -v cc >/dev/null
command -v ar >/dev/null
command -v sha256sum >/dev/null
command -v readelf >/dev/null

work=$(mktemp -d "${TMPDIR:-/tmp}/weft-linux-native-abi.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/native/lib" "$work/no-toolchain"

cc \
  -fno-asynchronous-unwind-tables \
  -fno-unwind-tables \
  -fno-stack-protector \
  -c "$fixture_root/fixture.c" \
  -o "$work/native/lib/fixture.o"
ar rcs "$work/native/lib/libfixture.a" "$work/native/lib/fixture.o"
archive_sha=$(sha256sum "$work/native/lib/libfixture.a" | awk '{print $1}')

sed "s/@ARCHIVE_SHA256@/$archive_sha/" "$fixture_root/weft.pkg.in" > "$work/weft.pkg"
cp "$fixture_root/main.weft" "$work/main.weft"
ln -s "$project_root/stdlib" "$work/stdlib"
ln -s "$project_root/runtime" "$work/runtime"

(cd "$work" && "$weft_bin" check main.weft)
(cd "$work" && PATH="$work/no-toolchain" "$weft_bin" build main.weft -o app --artifact-facts app.facts.json)
(cd "$work" && PATH="$work/no-toolchain" "$weft_bin" build main.weft -o app.second --artifact-facts app.second.facts.json)

cmp "$work/app" "$work/app.second"
cmp "$work/app.facts.json" "$work/app.second.facts.json"

set +e
"$work/app"
product_status=$?
set -e
if [ "$product_status" -ne 42 ]; then
  echo "linux native ABI product exited $product_status, expected 42" >&2
  exit 1
fi

readelf -l "$work/app" > "$work/program-headers.txt"
readelf -d "$work/app" > "$work/dynamic.txt"
if grep -q 'INTERP' "$work/program-headers.txt" || grep -q 'NEEDED' "$work/dynamic.txt"; then
  echo "static native ABI product unexpectedly has a loader dependency" >&2
  exit 1
fi
grep -q '"target":"linux-aarch64"' "$work/app.facts.json"
grep -q '"abi":"kernel"' "$work/app.facts.json"
grep -q '"standalone":true' "$work/app.facts.json"
grep -q '"dependencies":\[\]' "$work/app.facts.json"
grep -q '"content":"sha256:'"$archive_sha"'"' "$work/app.facts.json"

echo "linux native ABI matrix: pass (static, deterministic, no external product linker)"
