#!/usr/bin/env bash
# Verify the actual public release shape from archive bytes through a clean
# package workflow. Linux execution uses an already-present AArch64 container
# image so the gate never silently downloads tooling or gains network access.
set -euo pipefail

usage() {
  echo "usage: test/run_release_bundle.sh macos-aarch64|linux-aarch64" >&2
  exit 2
}

if [ "$#" -ne 1 ]; then
  usage
fi

target=$1
case "$target" in
  macos-aarch64|linux-aarch64) ;;
  *) usage ;;
esac

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
linux_image=${WEFT_LINUX_IMAGE:-debian:bookworm-slim}
work=$(mktemp -d "${TMPDIR:-/tmp}/weft-release-gate.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/one" "$work/two" "$work/extracted" "$work/project/deps/math" "$work/project/test"

archive_one=$($project_root/tools/build_release_bundle.sh "$target" "$work/one")
archive_two=$($project_root/tools/build_release_bundle.sh "$target" "$work/two")
bundle_name="weft-0.1.0-$target"

cmp "$archive_one" "$archive_two"
cmp "$archive_one.sha256" "$archive_two.sha256"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

expected_sha=$(awk '{print $1}' "$archive_one.sha256")
actual_sha=$(sha256_file "$archive_one")
if [ "$expected_sha" != "$actual_sha" ]; then
  echo "release gate: checksum sidecar does not match archive" >&2
  exit 1
fi

tar -tf "$archive_one" > "$work/archive-entries"
LC_ALL=C sort -c "$work/archive-entries"
if LC_ALL=C sort "$work/archive-entries" | uniq -d | grep -q .; then
  echo "release gate: archive contains duplicate entries" >&2
  exit 1
fi
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$work/archive-entries"; then
  echo "release gate: archive contains an unsafe path" >&2
  exit 1
fi
if LC_ALL=C grep -aF "$project_root" "$archive_one" >/dev/null; then
  echo "release gate: archive contains its checkout path" >&2
  exit 1
fi

tar -xf "$archive_one" -C "$work/extracted"
bundle_root="$work/extracted/$bundle_name"
facts="$bundle_root/share/weft/compiler.facts.json"
provenance="$bundle_root/share/weft/provenance.json"
identity="$bundle_root/share/weft/product-identity.json"

grep -q '"target":"'"$target"'"' "$facts"
grep -q '"standalone":true' "$facts"
grep -q '"debug_information":{"kind":"absent"}' "$facts"
grep -q '"release_schema_version":1' "$provenance"
grep -q '"target":"'"$target"'"' "$provenance"
grep -q '"sdk_layout":"lib/weft"' "$provenance"
grep -q '"compiler_version":"0.1.0"' "$identity"
if grep -Eqi '(clang|/Users/|/home/)' "$facts" "$provenance" "$identity"; then
  echo "release gate: release metadata contains a host tool or checkout path" >&2
  exit 1
fi

case "$target" in
  macos-aarch64)
    file "$bundle_root/bin/weft" | grep -q 'Mach-O 64-bit executable arm64'
    ;;
  linux-aarch64)
    file "$bundle_root/bin/weft" | grep -q 'ELF 64-bit LSB executable, ARM aarch64.*statically linked'
    if ! command -v docker >/dev/null 2>&1; then
      echo "release gate: docker is required to execute the Linux/AArch64 archive" >&2
      exit 2
    fi
    if ! docker image inspect "$linux_image" >/dev/null 2>&1; then
      echo "release gate: image '$linux_image' must already be present" >&2
      exit 2
    fi
    ;;
esac

run_weft_in() {
  local relative=$1
  shift
  if [ "$target" = macos-aarch64 ]; then
    (cd "$work/project/$relative" && env PATH="$bundle_root/bin" weft "$@")
  else
    docker run --rm --network none \
      -v "$bundle_root:/release:ro" \
      -v "$work/project:/work" \
      -w "/work/$relative" \
      "$linux_image" \
      /bin/sh -c 'PATH=/release/bin exec weft "$@"' sh "$@"
  fi
}

run_product() {
  if [ "$target" = macos-aarch64 ]; then
    "$work/project/app.one"
  else
    docker run --rm --network none \
      -v "$work/project:/work:ro" \
      -w /work \
      "$linux_image" \
      ./app.one
  fi
}

run_weft_in deps/math pkg init math >/dev/null
run_weft_in . pkg init app >/dev/null
run_weft_in . pkg add math deps/math >/dev/null

printf '%s\n' \
  '--- Add two integers.' \
  'pub fn add(left: i64, right: i64) -> i64 {' \
  '  left + right' \
  '}' > "$work/project/deps/math/lib.weft"

printf '%s\n' \
  'use math/lib.{add}' \
  '' \
  'fn answer() -> i64 {' \
  '  add(20, 22)' \
  '}' \
  '' \
  'fn main() -> i64 {' \
  '  if answer() == 42 { 0 } else { 1 }' \
  '}' > "$work/project/app.weft"

printf '%s\n' \
  'use math/lib.{add}' \
  '' \
  'test "locked dependency resolves from an extracted SDK" {' \
  '  Test.assert_eq(add(20, 22), 42)' \
  '}' > "$work/project/test/arithmetic.weft"

run_weft_in . fmt --write .
run_weft_in . fmt --check .
run_weft_in . pkg lock >/dev/null
run_weft_in . check app.weft
run_weft_in . test --jobs 2 test
run_weft_in . doc deps/math/lib.weft > "$work/project/api.md"
grep -q 'pub fn add(left: i64, right: i64) -> i64' "$work/project/api.md"
build_output=$(run_weft_in . build)
if [ "$build_output" != "target/$target/app" ]; then
  echo "release gate: normal build reported an unexpected artifact path" >&2
  exit 1
fi
cp "$work/project/target/$target/app" "$work/project/app.one"
cp "$work/project/target/$target/app.facts.json" "$work/project/app.one.facts.json"
run_weft_in . build >/dev/null
cp "$work/project/target/$target/app" "$work/project/app.two"
cp "$work/project/target/$target/app.facts.json" "$work/project/app.two.facts.json"
cmp "$work/project/app.one" "$work/project/app.two"
cmp "$work/project/app.one.facts.json" "$work/project/app.two.facts.json"
run_product
run_weft_in . run

run_weft_in . version --json > "$work/project/version.json"
run_weft_in . target show "$target" > "$work/project/target.json"
grep -q '"compiler_version":"0.1.0"' "$work/project/version.json"
grep -q '"target":"'"$target"'"' "$work/project/target.json"
grep -q '"host":true' "$work/project/target.json"
grep -q '"standalone":true' "$work/project/app.one.facts.json"
grep -q '"target":"'"$target"'"' "$work/project/app.one.facts.json"
if LC_ALL=C grep -aF "$project_root" "$work/project/app.one" "$work/project/app.one.facts.json" >/dev/null; then
  echo "release gate: product contains its compiler checkout path" >&2
  exit 1
fi

echo "release bundle gate: pass ($target, deterministic archive, extracted SDK, clean package workflow)"
