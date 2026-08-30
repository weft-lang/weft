#!/usr/bin/env bash
# Authenticate and structurally validate one published Weft SDK archive.
set -euo pipefail

usage() {
  echo "usage: tools/verify_release_bundle.sh ARCHIVE ALLOWED_SIGNERS SIGNER" >&2
  exit 2
}

if [ "$#" -ne 3 ]; then
  usage
fi

archive=$1
allowed_signers=$2
expected_signer=$3
manifest="$archive.release"
signature="$manifest.sig"
checksum="$archive.sha256"

if [ ! -f "$archive" ] || [ ! -f "$checksum" ] ||
   [ ! -f "$manifest" ] || [ ! -f "$signature" ]; then
  echo "release verification: archive or required sidecar is missing" >&2
  exit 1
fi
if [ ! -f "$allowed_signers" ]; then
  echo "release verification: allowed-signers file does not exist" >&2
  exit 1
fi
if ! [[ "$expected_signer" =~ ^[A-Za-z0-9._@+-]+$ ]]; then
  echo "release verification: signer identity is malformed" >&2
  exit 2
fi
if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "release verification: ssh-keygen with SSH signature support is required" >&2
  exit 1
fi

if ! ssh-keygen -Y verify \
  -f "$allowed_signers" \
  -I "$expected_signer" \
  -n weft-release \
  -s "$signature" < "$manifest" >/dev/null; then
  echo "release verification: manifest signature is not trusted" >&2
  exit 1
fi

manifest_value() {
  local key=$1
  local count
  count=$(awk -v wanted="$key" '$1 == wanted { count++ } END { print count + 0 }' "$manifest")
  if [ "$count" -ne 1 ]; then
    echo "release verification: manifest field '$key' must occur exactly once" >&2
    exit 1
  fi
  awk -v wanted="$key" '$1 == wanted && NF == 2 { print $2 }' "$manifest"
}

if [ "$(wc -l < "$manifest" | tr -d ' ')" -ne 9 ]; then
  echo "release verification: manifest must contain exactly nine fields" >&2
  exit 1
fi

schema=$(manifest_value schema)
target=$(manifest_value target)
artifact=$(manifest_value artifact)
expected_sha=$(manifest_value sha256)
expected_bytes=$(manifest_value bytes)
signer=$(manifest_value signer)
source_commit=$(manifest_value source-commit)
code_signing=$(manifest_value code-signing)
notarization=$(manifest_value notarization)

if [ "$schema" != weft-release-manifest-v1 ]; then
  echo "release verification: unsupported manifest schema" >&2
  exit 1
fi
case "$target" in
  macos-aarch64|linux-aarch64) ;;
  *)
    echo "release verification: unsupported target" >&2
    exit 1
    ;;
esac
archive_name=$(basename "$archive")
if [ "$artifact" != "$archive_name" ] ||
   ! [[ "$artifact" =~ ^weft-[0-9]+\.[0-9]+\.[0-9]+-$target\.tar$ ]]; then
  echo "release verification: artifact identity does not match the archive" >&2
  exit 1
fi
if ! [[ "$expected_sha" =~ ^[[:xdigit:]]{64}$ ]] ||
   ! [[ "$expected_bytes" =~ ^[0-9]+$ ]] ||
   ! [[ "$source_commit" =~ ^[[:xdigit:]]{40}$ ]] ||
   [ "$signer" != "$expected_signer" ]; then
  echo "release verification: manifest identity or digest field is malformed" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual_sha=$(sha256sum "$archive" | awk '{print $1}')
else
  actual_sha=$(shasum -a 256 "$archive" | awk '{print $1}')
fi
actual_bytes=$(wc -c < "$archive" | tr -d ' ')
if [ "$actual_sha" != "$expected_sha" ] || [ "$actual_bytes" != "$expected_bytes" ]; then
  echo "release verification: archive bytes do not match the signed manifest" >&2
  exit 1
fi
if [ "$(cat "$checksum")" != "$expected_sha  $artifact" ]; then
  echo "release verification: checksum sidecar disagrees with the signed manifest" >&2
  exit 1
fi

case "$target" in
  macos-aarch64)
    if [[ "$code_signing" =~ ^developer-id:([A-Za-z0-9]+):([[:xdigit:]]{40})$ ]]; then
      macos_distribution=notarized
      signed_team=${BASH_REMATCH[1]}
      signed_cdhash=${BASH_REMATCH[2]}
      if ! [[ "$notarization" =~ ^accepted:[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
        echo "release verification: notarized macOS release lacks an accepted notarization identity" >&2
        exit 1
      fi
      notary_id=${notarization#accepted:}
      notary_result="$archive.notarization.json"
      if [ ! -f "$notary_result" ] ||
         ! grep -Eq '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$notary_result" ||
         ! grep -Eq '"id"[[:space:]]*:[[:space:]]*"'"$notary_id"'"' "$notary_result"; then
        echo "release verification: notarization result does not match the signed manifest" >&2
        exit 1
      fi
    elif [[ "$code_signing" =~ ^adhoc:([[:xdigit:]]{40})$ ]]; then
      macos_distribution=community
      signed_cdhash=${BASH_REMATCH[1]}
      if [ "$notarization" != not-requested ] ||
         [ -e "$archive.notarization.json" ]; then
        echo "release verification: community macOS release contains contradictory notarization facts" >&2
        exit 1
      fi
    else
      echo "release verification: macOS release has an unsupported signing identity" >&2
      exit 1
    fi
    ;;
  linux-aarch64)
    macos_distribution=not-applicable
    if [ "$code_signing" != none ] || [ "$notarization" != not-applicable ]; then
      echo "release verification: Linux release contains contradictory platform-signing facts" >&2
      exit 1
    fi
    ;;
esac

work=$(mktemp -d "${TMPDIR:-/tmp}/weft-release-verify.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
entries="$work/entries"
listing="$work/listing"
tar -tf "$archive" > "$entries"
tar -tvf "$archive" > "$listing"
LC_ALL=C sort -c "$entries"
if LC_ALL=C sort "$entries" | uniq -d | grep -q .; then
  echo "release verification: archive contains duplicate entries" >&2
  exit 1
fi
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$entries";
then
  echo "release verification: archive contains an unsafe path" >&2
  exit 1
fi
if awk 'substr($0, 1, 1) != "-" && substr($0, 1, 1) != "d" { bad = 1 } END { exit bad ? 0 : 1 }' "$listing";
then
  echo "release verification: archive contains a link or special file" >&2
  exit 1
fi
bundle_name=${artifact%.tar}
if awk -v root="$bundle_name/" 'index($0, root) != 1 { bad = 1 } END { exit bad ? 0 : 1 }' "$entries";
then
  echo "release verification: archive contains a member outside its release root" >&2
  exit 1
fi

if [ "$target" = macos-aarch64 ]; then
  if ! command -v codesign >/dev/null 2>&1; then
    echo "release verification: codesign is required to verify a macOS archive" >&2
    exit 1
  fi
  mkdir -p "$work/extracted"
  tar -xf "$archive" -C "$work/extracted" "$bundle_name/bin/weft"
  compiler="$work/extracted/$bundle_name/bin/weft"
  codesign --verify --strict --verbose=2 "$compiler"
  signature_details="$work/compiler-signature.txt"
  codesign --display --verbose=4 "$compiler" > /dev/null 2> "$signature_details"
  actual_authority=$(sed -n 's/^Authority=//p' "$signature_details" | head -1)
  actual_team=$(sed -n 's/^TeamIdentifier=//p' "$signature_details" | head -1)
  actual_cdhash=$(sed -n 's/^CDHash=//p' "$signature_details" | head -1)
  if [ "$macos_distribution" = community ]; then
    actual_kind=$(sed -n 's/^Signature=//p' "$signature_details" | head -1)
    if [ "$actual_kind" != adhoc ] || [ -n "$actual_authority" ] ||
       [ "$actual_cdhash" != "$signed_cdhash" ]; then
      echo "release verification: embedded ad-hoc signature does not match the signed manifest" >&2
      exit 1
    fi
  else
    if [[ "$actual_authority" != 'Developer ID Application: '* ]] ||
       [ "$actual_team" != "$signed_team" ] || [ "$actual_cdhash" != "$signed_cdhash" ]; then
      echo "release verification: embedded Developer ID does not match the signed manifest" >&2
      exit 1
    fi
  fi
fi

echo "release verification: pass ($target, signer $signer, $macos_distribution)"
