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
mkdir -p "$work/one" "$work/two" "$work/extracted" "$work/project/deps/math" "$work/project/provider" "$work/project/test"

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
mkdir -p "$work/installed"
mv "$work/extracted/$bundle_name" "$work/installed/$bundle_name"
bundle_root="$work/installed/$bundle_name"
facts="$bundle_root/share/weft/compiler.facts.json"
provenance="$bundle_root/share/weft/provenance.json"
identity="$bundle_root/share/weft/product-identity.json"
sdk_manifest="$bundle_root/lib/weft/weft.pkg"
sdk_compiler_module="$bundle_root/lib/weft/compiler/unicode_identifier_data.weft"
tls_archive="$bundle_root/lib/weft/native/lib/$target/libweft_mbedtls.a"
tls_notice="$bundle_root/share/weft/mbedtls.md"

grep -q '"target":"'"$target"'"' "$facts"
grep -q '"standalone":true' "$facts"
grep -q '"debug_information":{"kind":"absent"}' "$facts"
grep -q '"release_schema_version":2' "$provenance"
grep -q '"target":"'"$target"'"' "$provenance"
grep -q '"sdk_layout":"lib/weft"' "$provenance"
grep -q '"compiler_version":"0.1.0"' "$identity"
grep -q '"name":"Mbed TLS"' "$provenance"
grep -q '"version":"3.6.7"' "$provenance"
grep -q '"license":"Apache-2.0"' "$provenance"
grep -q '"trusted_bindings":\["runtime/tls_mbedtls"\]' "$sdk_manifest"
test -f "$sdk_compiler_module"
grep -q 'Copyright The Mbed TLS Contributors' "$tls_notice"
tls_archive_sha=$(sha256_file "$tls_archive")
grep -q '"archive_sha256":"'"$tls_archive_sha"'"' "$provenance"
if grep -Eqi '(clang|/Users/|/home/)' "$facts" "$provenance" "$identity"; then
  echo "release gate: release metadata contains a host tool or checkout path" >&2
  exit 1
fi

case "$target" in
  macos-aarch64)
    file "$bundle_root/bin/weft" | grep -q 'Mach-O 64-bit executable arm64'
    codesign --verify --strict --verbose=2 "$bundle_root/bin/weft"
    grep -q '"code_signing":{"kind":"adhoc"' "$provenance"
    ;;
  linux-aarch64)
    file "$bundle_root/bin/weft" | grep -q 'ELF 64-bit LSB executable, ARM aarch64.*statically linked'
    grep -q '"code_signing":{"kind":"none"}' "$provenance"
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

run_weft_with_provider_in() {
  local relative=$1
  shift
  if [ "$target" = macos-aarch64 ]; then
    (cd "$work/project/$relative" && env \
      PATH="$work/project/provider:$bundle_root/bin:/usr/bin:/bin" \
      WEFT_FAKE_ARCHIVE="$work/project/math.tar" \
      weft "$@")
  else
    docker run --rm --network none \
      -v "$bundle_root:/release:ro" \
      -v "$work/project:/work" \
      -w "/work/$relative" \
      -e WEFT_FAKE_ARCHIVE=/work/math.tar \
      "$linux_image" \
      /bin/sh -c 'PATH=/work/provider:/release/bin:/usr/bin:/bin exec weft "$@"' sh "$@"
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

run_tls_probe() {
  if [ "$target" = macos-aarch64 ]; then
    "$work/project/tls-probe"
  else
    docker run --rm --network none \
      -v "$work/project:/work:ro" \
      -w /work \
      "$linux_image" \
      ./tls-probe
  fi
}

run_weft_in deps/math pkg init math >/dev/null
run_weft_in . pkg init app >/dev/null

printf '%s\n' '{"package":"math","manifest_version":1,"version":"0.1.0","weft":"0.1","source_roots":["."],"targets":{"math":{"kind":"library","source":"lib.weft"}},"dependencies":{}}' > "$work/project/deps/math/weft.pkg"

printf '%s\n' \
  '--- Add two integers.' \
  'pub fn add(left: i64, right: i64) -> i64 {' \
  '  left + right' \
  '}' > "$work/project/deps/math/lib.weft"

(
  cd "$work/project/deps/math"
  git init -q
  git add weft.pkg lib.weft
  git -c user.name=Weft -c user.email=weft@example.invalid commit -qm fixture
  git archive --format=tar --output="$work/project/math.tar" HEAD
)
math_transport=$(sha256_file "$work/project/math.tar")
printf '%s\n' \
  '#!/bin/sh' \
  'output=""' \
  'while [ "$#" -gt 0 ]; do' \
  '  if [ "$1" = "--output" ]; then output="$2"; shift 2; else shift; fi' \
  'done' \
  'cp "$WEFT_FAKE_ARCHIVE" "$output"' > "$work/project/provider/curl"
chmod +x "$work/project/provider/curl"
run_weft_in . pkg add math --archive https://packages.example.invalid/math.tar --sha256 "sha256:$math_transport" >/dev/null

printf '%s\n' \
  'use math/lib.{add}' \
  '' \
  'pub fn answer() -> i64 {' \
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

printf '%s\n' \
  'use stdlib/bytes.{Bytes, bytes_from_str}' \
  'use stdlib/result.{Err, Ok}' \
  'use stdlib/secure_random.{SecureRandom, SecureRandomError}' \
  'use stdlib/time.{Time}' \
  'use stdlib/tls.{TlsTrust, tls_client_open}' \
  'use stdlib/url.{url_parse}' \
  '' \
  'fn open_with_authority() -[SecureRandom, Time]> i64 {' \
  '  match url_parse("https://localhost/") {' \
  '    Err(error) -> 1' \
  '    Ok(url) -> match tls_client_open(url.host(), bytes_from_str("bad")) {' \
  '      Err(TlsTrust) -> 0' \
  '      _ -> 2' \
  '    }' \
  '  }' \
  '}' \
  '' \
  'fn with_random() -[Time]> i64 {' \
  '  handle open_with_authority() {' \
  '    SecureRandom.bytes(count) -> resume(Ok<Bytes, SecureRandomError>(' \
  '      bytes_from_str("0123456789abcdef0123456789abcdef0123456789abcdef")' \
  '    ))' \
  '  }' \
  '}' \
  '' \
  'fn main() -> i64 {' \
  '  handle with_random() {' \
  '    Time.now_millis() -> resume(1788134400000)' \
  '    Time.now_nanos() -> resume(0)' \
  '    Time.sleep_millis(ms) -> resume(0)' \
  '  }' \
  '}' > "$work/project/tls_probe.weft"

run_weft_in . fmt --write .
run_weft_in . fmt --check .
run_weft_with_provider_in . pkg lock >/dev/null
rm -rf "$work/project/deps" "$work/project/provider" "$work/project/math.tar"
run_weft_in . pkg fetch --offline >/dev/null
run_weft_in . check app.weft
run_weft_in . test --jobs 2 test
run_weft_in . doc app.weft > "$work/project/api.md"
grep -q 'pub fn answer() -> i64' "$work/project/api.md"
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
run_weft_in . build tls_probe.weft -o tls-probe --artifact-facts tls-probe.facts.json
run_tls_probe
grep -q '"standalone":true' "$work/project/tls-probe.facts.json"
grep -q '"content":"sha256:'"$tls_archive_sha"'"' "$work/project/tls-probe.facts.json"
grep -q '"license":"Apache-2.0"' "$work/project/tls-probe.facts.json"
grep -q '"source":"sdk:bundled"' "$work/project/tls-probe.facts.json"
grep -q '"module":"runtime/tls_mbedtls"' "$work/project/tls-probe.facts.json"

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

rm -rf "$bundle_root"
if [ -e "$bundle_root" ]; then
  echo "release gate: uninstall left the installed SDK behind" >&2
  exit 1
fi

echo "release bundle gate: pass ($target, deterministic archive, install/uninstall, locked remote/offline workflow)"
