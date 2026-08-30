#!/usr/bin/env bash
# Run the manifest-trusted fixture and real Mbed TLS backend under the strongest
# allocation diagnostics available without adding a host linker/runtime to a
# Weft product. macOS uses Guard Malloc in both guard directions. Linux uses a
# target-local archive whose mmap allocator has protected edge pages, checked
# alignment redzones, header validation, and immediate unmapping on free.
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
fixture_root="$project_root/test/fixtures/native_binding_diagnostics"
weft_bin=${WEFT:-"$project_root/weft"}

case "$weft_bin" in
  /*) ;;
  *) weft_bin=$(CDPATH= cd -- "$(dirname "$weft_bin")" && pwd -P)/$(basename "$weft_bin") ;;
esac

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

host_os=$(uname -s)
host_arch=$(uname -m)
case "$host_os:$host_arch" in
  Darwin:arm64) target=macos-aarch64 ;;
  Linux:aarch64|Linux:arm64) target=linux-aarch64 ;;
  *)
    echo "native binding diagnostics require an alpha target host; found $host_os/$host_arch" >&2
    exit 2
    ;;
esac

for command_name in cc sed "$weft_bin"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "native binding diagnostics: required tool is missing: $command_name" >&2
    exit 2
  fi
done

work=$(mktemp -d "${TMPDIR:-/tmp}/weft-native-binding-diagnostics.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

run_guard_malloc() {
  local binary=$1
  local direction=$2
  local log="$work/guard-malloc-$(basename "$binary")-$direction.log"
  local status=0

  case "$direction" in
    after)
      env \
        DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib \
        MALLOC_CHECK_HEADER=1 \
        MALLOC_FILL_SPACE=1 \
        MALLOC_LOG_FILE="$log" \
        "$binary" || status=$?
      ;;
    before)
      env \
        DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib \
        MALLOC_CHECK_HEADER=1 \
        MALLOC_FILL_SPACE=1 \
        MALLOC_LOG_FILE="$log" \
        MALLOC_PROTECT_BEFORE=1 \
        "$binary" || status=$?
      ;;
    *) return 2 ;;
  esac
  if [ "$status" -ne 0 ]; then
    echo "native binding diagnostics: Guard Malloc $direction run exited $status: $binary" >&2
    if [ -f "$log" ]; then sed -n '1,120p' "$log" >&2; fi
    return 1
  fi
  if ! grep -q 'GuardMalloc.*version' "$log"; then
    echo "native binding diagnostics: Guard Malloc did not interpose: $binary" >&2
    if [ -f "$log" ]; then sed -n '1,120p' "$log" >&2; fi
    return 1
  fi
}

guard_malloc_rejects_canary() {
  local binary=$1
  local log="$work/guard-malloc-canary.log"
  local status=0

  env \
    DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib \
    MALLOC_CHECK_HEADER=1 \
    MALLOC_LOG_FILE="$log" \
    "$binary" >/dev/null 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    echo "native binding diagnostics: Guard Malloc accepted the overflow canary" >&2
    return 1
  fi
  if ! grep -q 'GuardMalloc.*version' "$log"; then
    echo "native binding diagnostics: Guard Malloc did not interpose on the overflow canary" >&2
    return 1
  fi
}

fixture_project="$work/fixture"
mkdir -p "$fixture_project/native/lib"
cp "$fixture_root/main.weft" "$fixture_project/main.weft"
cp "$fixture_root/native_raw.weft" "$fixture_project/native_raw.weft"
ln -s "$project_root/runtime" "$fixture_project/runtime"
ln -s "$project_root/stdlib" "$fixture_project/stdlib"

case "$target" in
  macos-aarch64)
    command -v libtool >/dev/null
    cc -arch arm64 -O1 -g -Wall -Wextra -Werror \
      -c "$fixture_root/fixture.c" -o "$work/fixture.o"
    ZERO_AR_DATE=1 libtool -static -o "$fixture_project/native/lib/libfixture.a" \
      "$work/fixture.o"
    cc -arch arm64 -O1 -g -Wall -Wextra -Werror \
      "$fixture_root/canary.c" "$work/fixture.o" -o "$work/diagnostic-canary"
    ;;
  linux-aarch64)
    command -v ar >/dev/null
    cc -O1 -g -fno-stack-protector -fno-asynchronous-unwind-tables \
      -fno-unwind-tables -Wall -Wextra -Werror \
      -c "$fixture_root/fixture.c" -o "$work/fixture.o"
    ar rcs "$fixture_project/native/lib/libfixture.a" "$work/fixture.o"
    cc -O1 -g -Wall -Wextra -Werror \
      "$fixture_root/canary.c" "$work/fixture.o" -o "$work/diagnostic-canary"
    ;;
esac

fixture_hash=$(sha256_file "$fixture_project/native/lib/libfixture.a")
sed \
  -e "s/@TARGET@/$target/" \
  -e "s/@ARCHIVE_SHA256@/$fixture_hash/" \
  "$fixture_root/weft.pkg.in" > "$fixture_project/weft.pkg"

(cd "$fixture_project" && "$weft_bin" check main.weft)
(cd "$fixture_project" && "$weft_bin" build main.weft -o fixture-diagnostics)
chmod +x "$fixture_project/fixture-diagnostics"

if [ "$target" = macos-aarch64 ]; then
  if [ ! -f /usr/lib/libgmalloc.dylib ]; then
    echo "native binding diagnostics: /usr/lib/libgmalloc.dylib is unavailable" >&2
    exit 2
  fi
  guard_malloc_rejects_canary "$work/diagnostic-canary"
  run_guard_malloc "$fixture_project/fixture-diagnostics" after
  run_guard_malloc "$fixture_project/fixture-diagnostics" before
else
  canary_status=0
  (ulimit -c 0; "$work/diagnostic-canary" >/dev/null 2>&1) || canary_status=$?
  if [ "$canary_status" -eq 0 ]; then
    echo "native binding diagnostics: Linux guard pages accepted the overflow canary" >&2
    exit 1
  fi
  "$fixture_project/fixture-diagnostics"
fi

if [ "$target" = macos-aarch64 ]; then
  tls_archive="$project_root/native/lib/$target/libweft_mbedtls.a"
  if [ ! -f "$tls_archive" ]; then
    echo "native binding diagnostics: generate the pinned $target Mbed TLS archive first" >&2
    exit 2
  fi
  tls_binary="$work/tls-diagnostics"
  (cd "$project_root" &&
    "$weft_bin" build test/linked/tls_conformance.weft -o "$tls_binary")
else
  tls_project="$work/tls"
  mkdir -p "$tls_project/native/lib/$target"
  ln -s "$project_root/compiler" "$tls_project/compiler"
  ln -s "$project_root/runtime" "$tls_project/runtime"
  ln -s "$project_root/stdlib" "$tls_project/stdlib"
  ln -s "$project_root/test" "$tls_project/test"
  source_archive=${WEFT_MBEDTLS_SOURCE_ARCHIVE:-}
  if [ -z "$source_archive" ] || [ ! -f "$source_archive" ]; then
    echo "native binding diagnostics: Linux requires WEFT_MBEDTLS_SOURCE_ARCHIVE pointing at the pinned Mbed TLS 3.6.7 release tar" >&2
    exit 2
  fi
  release_archive="$project_root/native/lib/$target/libweft_mbedtls.a"
  if [ ! -f "$release_archive" ]; then
    echo "native binding diagnostics: generate the pinned $target Mbed TLS archive first" >&2
    exit 2
  fi
  tls_archive="$tls_project/native/lib/$target/libweft_mbedtls.a"
  WEFT_MBEDTLS_PLATFORM_DIAGNOSTICS=1 \
    "$project_root/native/mbedtls/build_archive.sh" \
      "$target" "$source_archive" "$tls_archive"
  if ! command -v nm >/dev/null 2>&1; then
    echo "native binding diagnostics: nm is required to verify the Linux guard-page archive" >&2
    exit 2
  fi
  nm "$tls_archive" > "$work/tls-archive-symbols.txt"
  if ! grep -q 'weft_tls_platform_diagnostics_enabled' "$work/tls-archive-symbols.txt"; then
    echo "native binding diagnostics: Linux diagnostic archive lacks its guard-page marker" >&2
    exit 1
  fi
  release_hash=$(sha256_file "$release_archive")
  diagnostic_hash=$(sha256_file "$tls_archive")
  if [ "$release_hash" = "$diagnostic_hash" ]; then
    echo "native binding diagnostics: Linux diagnostic archive unexpectedly matches the release archive" >&2
    exit 1
  fi
  sed "s/$release_hash/$diagnostic_hash/" "$project_root/weft.pkg" > "$tls_project/weft.pkg"
  tls_binary="$tls_project/tls-diagnostics"
  (cd "$tls_project" &&
    "$weft_bin" build test/linked/tls_conformance.weft -o "$tls_binary")
fi

chmod +x "$tls_binary"

if [ "$target" = macos-aarch64 ]; then
  run_guard_malloc "$tls_binary" after
  run_guard_malloc "$tls_binary" before
  echo "native binding diagnostics: pass ($target; fixture + Mbed TLS; guard-after + guard-before)"
else
  "$tls_binary"
  echo "native binding diagnostics: pass ($target; fixture + Mbed TLS; guard pages + redzones)"
fi
