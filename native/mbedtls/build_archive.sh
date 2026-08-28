#!/usr/bin/env bash
# Build Weft's pinned callback-free Mbed TLS archive on an alpha target host.
set -euo pipefail

version=3.6.7
source_sha256=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6

usage() {
  echo "usage: native/mbedtls/build_archive.sh macos-aarch64|linux-aarch64 MBEDTLS_RELEASE_TAR OUTPUT_ARCHIVE" >&2
  exit 2
}

if [ "$#" -ne 3 ]; then
  usage
fi

target=$1
source_archive=$2
output_archive=$3
case "$target" in
  macos-aarch64|linux-aarch64) ;;
  *) usage ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd -P)

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

actual_source_sha256=$(sha256_file "$source_archive")
if [ "$actual_source_sha256" != "$source_sha256" ]; then
  echo "mbedtls: source archive hash mismatch" >&2
  echo "  expected: sha256:$source_sha256" >&2
  echo "  actual:   sha256:$actual_source_sha256" >&2
  exit 1
fi

host_os=$(uname -s)
host_arch=$(uname -m)
case "$target:$host_os:$host_arch" in
  macos-aarch64:Darwin:arm64) ;;
  linux-aarch64:Linux:aarch64|linux-aarch64:Linux:arm64) ;;
  *)
    echo "mbedtls: $target archives must be built target-locally; host is $host_os/$host_arch" >&2
    exit 1
    ;;
esac

cc=${CC:-cc}
for command_name in cmake tar "$cc"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "mbedtls: required release-build tool is missing: $command_name" >&2
    exit 1
  fi
done
if [ "$target" = "macos-aarch64" ] && ! command -v libtool >/dev/null 2>&1; then
  echo "mbedtls: required release-build tool is missing: libtool" >&2
  exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/weft-mbedtls-$version.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
tar -xf "$source_archive" -C "$work"
source_dir="$work/mbedtls-$version"
if [ ! -f "$source_dir/CMakeLists.txt" ]; then
  echo "mbedtls: official archive did not contain mbedtls-$version/CMakeLists.txt" >&2
  exit 1
fi

common_flags="-O2 -fno-builtin -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables"
target_flags=""
compiler_flags=""
case "$target" in
  macos-aarch64)
    target_flags="-ffunction-sections -fdata-sections"
    compiler_flags="-arch arm64"
    ;;
  linux-aarch64)
    target_flags="-ffreestanding -fno-pie -fno-pic"
    ;;
esac
all_flags="$common_flags $target_flags"

build_dir="$work/build"
cmake \
  -S "$source_dir" \
  -B "$build_dir" \
  -DENABLE_PROGRAMS=OFF \
  -DENABLE_TESTING=OFF \
  -DUSE_SHARED_MBEDTLS_LIBRARY=OFF \
  -DUSE_STATIC_MBEDTLS_LIBRARY=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DMBEDTLS_CONFIG_FILE="$script_dir/weft_mbedtls_config.h" \
  -DCMAKE_C_FLAGS="$all_flags"
ZERO_AR_DATE=1 cmake --build "$build_dir" --parallel "${WEFT_MBEDTLS_JOBS:-4}"

"$cc" $compiler_flags $all_flags -Wall -Wextra -Werror \
  -I "$script_dir" \
  -I "$source_dir/include" \
  -DMBEDTLS_CONFIG_FILE='"weft_mbedtls_config.h"' \
  -c "$script_dir/weft_tls_adapter.c" \
  -o "$work/weft_tls_adapter.o"
"$cc" $compiler_flags $all_flags -Wall -Wextra -Werror \
  -c "$script_dir/weft_tls_platform.c" \
  -o "$work/weft_tls_platform.o"

combined="$work/libweft_mbedtls.a"
case "$target" in
  macos-aarch64)
    ZERO_AR_DATE=1 libtool -static -o "$combined" \
      "$work/weft_tls_adapter.o" \
      "$work/weft_tls_platform.o" \
      "$build_dir/library/libmbedtls.a" \
      "$build_dir/library/libmbedx509.a" \
      "$build_dir/library/libmbedcrypto.a" \
      "$build_dir/3rdparty/p256-m/libp256m.a" \
      "$build_dir/3rdparty/everest/libeverest.a"
    ;;
  linux-aarch64)
    if ! command -v ar >/dev/null 2>&1; then
      echo "mbedtls: required release-build tool is missing: ar" >&2
      exit 1
    fi
    printf '%s\n' \
      "create $combined" \
      "addmod $work/weft_tls_adapter.o" \
      "addmod $work/weft_tls_platform.o" \
      "addlib $build_dir/library/libmbedtls.a" \
      "addlib $build_dir/library/libmbedx509.a" \
      "addlib $build_dir/library/libmbedcrypto.a" \
      "addlib $build_dir/3rdparty/p256-m/libp256m.a" \
      "addlib $build_dir/3rdparty/everest/libeverest.a" \
      save \
      end | ar -M
    ;;
esac

output_parent=$(dirname "$output_archive")
mkdir -p "$output_parent"
cp "$combined" "$output_archive"
printf 'sha256:%s\n' "$(sha256_file "$output_archive")"
