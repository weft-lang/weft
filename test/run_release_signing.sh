#!/usr/bin/env bash
# Fast release-ceremony contract tests. Production keys and optional Apple
# credentials are never fixtures; an ephemeral Ed25519 key proves the project
# signature boundary while every distribution channel remains explicit.
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d "${TMPDIR:-/tmp}/weft-release-signing-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

expect_failure() {
  local name=$1
  shift
  if "$@" > "$work/failure.out" 2> "$work/failure.err"; then
    echo "release signing test: expected failure: $name" >&2
    exit 1
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

write_linux_manifest() {
  local archive=$1
  local signer=$2
  local code_signing=$3
  local notarization=$4
  local archive_name
  local archive_sha
  local archive_bytes
  archive_name=$(basename "$archive")
  archive_sha=$(sha256_file "$archive")
  archive_bytes=$(wc -c < "$archive" | tr -d ' ')
  printf '%s\n' \
    'schema weft-release-manifest-v1' \
    'target linux-aarch64' \
    "artifact $archive_name" \
    "sha256 $archive_sha" \
    "bytes $archive_bytes" \
    "signer $signer" \
    'source-commit 0000000000000000000000000000000000000000' \
    "code-signing $code_signing" \
    "notarization $notarization" > "$archive.release"
  printf '%s  %s\n' "$archive_sha" "$archive_name" > "$archive.sha256"
}

mkdir -p "$work/stage/weft-0.1.0-linux-aarch64/bin" "$work/release"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$work/stage/weft-0.1.0-linux-aarch64/bin/weft"
chmod 755 "$work/stage/weft-0.1.0-linux-aarch64/bin/weft"
archive="$work/release/weft-0.1.0-linux-aarch64.tar"
tar -cf "$archive" -C "$work/stage" weft-0.1.0-linux-aarch64

ssh-keygen -q -t ed25519 -N '' -C weft-release-test -f "$work/key"
public_key=$(cat "$work/key.pub")
printf '%s %s\n' weft-release "$public_key" > "$work/allowed_signers"

write_linux_manifest "$archive" weft-release none not-applicable
WEFT_RELEASE_SIGNING_KEY="$work/key" \
  "$project_root/tools/sign_release_manifest.sh" "$archive.release" >/dev/null
"$project_root/tools/verify_release_bundle.sh" \
  "$archive" "$work/allowed_signers" weft-release >/dev/null

expect_failure "signature overwrite" env WEFT_RELEASE_SIGNING_KEY="$work/key" \
  "$project_root/tools/sign_release_manifest.sh" "$archive.release"

cp "$archive" "$work/archive.saved"
printf 'tamper' >> "$archive"
expect_failure "tampered archive" "$project_root/tools/verify_release_bundle.sh" \
  "$archive" "$work/allowed_signers" weft-release
mv "$work/archive.saved" "$archive"

ssh-keygen -q -t ed25519 -N '' -C stranger -f "$work/stranger"
printf '%s %s\n' stranger "$(cat "$work/stranger.pub")" > "$work/stranger_allowed"
expect_failure "untrusted signer" "$project_root/tools/verify_release_bundle.sh" \
  "$archive" "$work/stranger_allowed" weft-release

rm "$archive.release.sig"
write_linux_manifest "$archive" weft-release developer-id:TEAM:0000000000000000000000000000000000000000 not-applicable
WEFT_RELEASE_SIGNING_KEY="$work/key" \
  "$project_root/tools/sign_release_manifest.sh" "$archive.release" >/dev/null
expect_failure "contradictory Linux platform signature" \
  "$project_root/tools/verify_release_bundle.sh" \
  "$archive" "$work/allowed_signers" weft-release

unsafe="$work/unsafe/weft-0.1.0-linux-aarch64.tar"
mkdir -p "$work/unsafe/stage/weft-0.1.0-linux-aarch64/bin"
ln -s /tmp "$work/unsafe/stage/weft-0.1.0-linux-aarch64/bin/weft"
tar -cf "$unsafe" -C "$work/unsafe/stage" weft-0.1.0-linux-aarch64
write_linux_manifest "$unsafe" weft-release none not-applicable
WEFT_RELEASE_SIGNING_KEY="$work/key" \
  "$project_root/tools/sign_release_manifest.sh" "$unsafe.release" >/dev/null
expect_failure "archive link" "$project_root/tools/verify_release_bundle.sh" \
  "$unsafe" "$work/allowed_signers" weft-release

if command -v codesign >/dev/null 2>&1; then
  mac_archive="$work/macos/weft-0.1.0-macos-aarch64.tar"
  mac_bundle="$work/macos/stage/weft-0.1.0-macos-aarch64"
  mkdir -p "$mac_bundle/bin"
  cp /usr/bin/true "$mac_bundle/bin/weft"
  codesign --force --sign - "$mac_bundle/bin/weft"
  codesign --display --verbose=4 "$mac_bundle/bin/weft" > /dev/null 2> "$work/macos-signature"
  mac_cdhash=$(sed -n 's/^CDHash=//p' "$work/macos-signature" | head -1)
  tar -cf "$mac_archive" -C "$work/macos/stage" weft-0.1.0-macos-aarch64
  mac_sha=$(sha256_file "$mac_archive")
  mac_bytes=$(wc -c < "$mac_archive" | tr -d ' ')
  printf '%s\n' \
    'schema weft-release-manifest-v1' \
    'target macos-aarch64' \
    'artifact weft-0.1.0-macos-aarch64.tar' \
    "sha256 $mac_sha" \
    "bytes $mac_bytes" \
    'signer weft-release' \
    'source-commit 0000000000000000000000000000000000000000' \
    "code-signing adhoc:$mac_cdhash" \
    'notarization not-requested' > "$mac_archive.release"
  printf '%s  %s\n' "$mac_sha" weft-0.1.0-macos-aarch64.tar > "$mac_archive.sha256"
  WEFT_RELEASE_SIGNING_KEY="$work/key" \
    "$project_root/tools/sign_release_manifest.sh" "$mac_archive.release" >/dev/null
  "$project_root/tools/verify_release_bundle.sh" \
    "$mac_archive" "$work/allowed_signers" weft-release >/dev/null

  printf '%s\n' '{"id":"00000000-0000-0000-0000-000000000000","status":"Accepted"}' > "$mac_archive.notarization.json"
  expect_failure "contradictory community notarization" \
    "$project_root/tools/verify_release_bundle.sh" \
    "$mac_archive" "$work/allowed_signers" weft-release

  rm "$mac_archive.release.sig"
  printf '%s\n' \
    'schema weft-release-manifest-v1' \
    'target macos-aarch64' \
    'artifact weft-0.1.0-macos-aarch64.tar' \
    "sha256 $mac_sha" \
    "bytes $mac_bytes" \
    'signer weft-release' \
    'source-commit 0000000000000000000000000000000000000000' \
    "code-signing developer-id:TESTTEAM:$mac_cdhash" \
    'notarization accepted:00000000-0000-0000-0000-000000000000' > "$mac_archive.release"
  WEFT_RELEASE_SIGNING_KEY="$work/key" \
    "$project_root/tools/sign_release_manifest.sh" "$mac_archive.release" >/dev/null
  expect_failure "claimed Developer ID" "$project_root/tools/verify_release_bundle.sh" \
    "$mac_archive" "$work/allowed_signers" weft-release
fi

expect_failure "publish authority" env \
  -u WEFT_RELEASE_SIGNING_KEY \
  -u WEFT_RELEASE_SIGNER \
  -u WEFT_RELEASE_ALLOWED_SIGNERS \
  "$project_root/tools/publish_release_bundle.sh" linux-aarch64 "$work/publish"
expect_failure "Developer ID authority" env \
  WEFT_RELEASE_PUBLISH=1 \
  WEFT_MACOS_DISTRIBUTION=notarized \
  -u WEFT_MACOS_SIGNING_IDENTITY \
  "$project_root/tools/build_release_bundle.sh" macos-aarch64 "$work/publish"
expect_failure "community Apple authority" env \
  WEFT_RELEASE_PUBLISH=1 \
  WEFT_MACOS_DISTRIBUTION=community \
  WEFT_MACOS_SIGNING_IDENTITY=0123456789abcdef0123456789abcdef01234567 \
  "$project_root/tools/build_release_bundle.sh" macos-aarch64 "$work/publish"

echo "release signing tests: pass (trusted manifest, community macOS, platform facts, safe archive)"
