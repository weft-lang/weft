#!/usr/bin/env bash
# Build and authenticate one release, with optional Apple notarization.
set -euo pipefail

usage() {
  echo "usage: tools/publish_release_bundle.sh macos-aarch64|linux-aarch64 OUTPUT_DIR" >&2
  exit 2
}

if [ "$#" -ne 2 ]; then
  usage
fi

target=$1
output_dir=$2
case "$target" in
  macos-aarch64|linux-aarch64) ;;
  *) usage ;;
esac

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
signing_key=${WEFT_RELEASE_SIGNING_KEY:-}
signer=${WEFT_RELEASE_SIGNER:-}
allowed_signers=${WEFT_RELEASE_ALLOWED_SIGNERS:-}
if [ -z "$signing_key" ] || [ -z "$signer" ] || [ -z "$allowed_signers" ]; then
  echo "release publish: WEFT_RELEASE_SIGNING_KEY, WEFT_RELEASE_SIGNER, and WEFT_RELEASE_ALLOWED_SIGNERS are required" >&2
  exit 1
fi
if ! [[ "$signer" =~ ^[A-Za-z0-9._@+-]+$ ]]; then
  echo "release publish: WEFT_RELEASE_SIGNER is malformed" >&2
  exit 2
fi
if [ ! -f "$signing_key" ] || [ ! -f "$allowed_signers" ]; then
  echo "release publish: signing key or allowed-signers file does not exist" >&2
  exit 1
fi

macos_distribution=not-applicable
macos_identity=${WEFT_MACOS_SIGNING_IDENTITY:-}
notary_profile=${WEFT_NOTARY_KEYCHAIN_PROFILE:-}
notary_timeout=${WEFT_NOTARY_TIMEOUT:-30m}
if [ "$target" = macos-aarch64 ]; then
  macos_distribution=${WEFT_MACOS_DISTRIBUTION:-community}
  case "$macos_distribution" in
    community)
      if [ -n "$macos_identity" ] || [ -n "$notary_profile" ] ||
         [ -n "${WEFT_NOTARY_TIMEOUT+x}" ]; then
        echo "release publish: community distribution cannot consume Apple signing or notarization settings" >&2
        exit 2
      fi
      ;;
    notarized)
      if [ -z "$macos_identity" ] || [ -z "$notary_profile" ]; then
        echo "release publish: notarized macOS distribution requires WEFT_MACOS_SIGNING_IDENTITY and WEFT_NOTARY_KEYCHAIN_PROFILE" >&2
        exit 1
      fi
      if ! [[ "$notary_timeout" =~ ^[0-9]+[smh]?$ ]]; then
        echo "release publish: WEFT_NOTARY_TIMEOUT is malformed" >&2
        exit 2
      fi
      ;;
    *)
      echo "release publish: WEFT_MACOS_DISTRIBUTION must be community or notarized" >&2
      exit 2
      ;;
  esac
elif [ -n "${WEFT_MACOS_DISTRIBUTION+x}" ] || [ -n "$macos_identity" ] ||
     [ -n "$notary_profile" ] || [ -n "${WEFT_NOTARY_TIMEOUT+x}" ]; then
  echo "release publish: macOS distribution settings cannot be applied to a Linux release" >&2
  exit 2
fi

if [ "$target" = macos-aarch64 ]; then
  archive=$(WEFT_RELEASE_PUBLISH=1 \
    WEFT_MACOS_DISTRIBUTION="$macos_distribution" \
    "$project_root/tools/build_release_bundle.sh" "$target" "$output_dir")
else
  archive=$(WEFT_RELEASE_PUBLISH=1 \
    "$project_root/tools/build_release_bundle.sh" "$target" "$output_dir")
fi
archive=$(CDPATH= cd -- "$(dirname "$archive")" && pwd -P)/$(basename "$archive")
archive_name=$(basename "$archive")
source_commit=$(git -C "$project_root" rev-parse HEAD)
notarization=not-applicable
code_signing=none

work=$(mktemp -d "${TMPDIR:-/tmp}/weft-release-publish.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

if [ "$target" = macos-aarch64 ]; then
  mkdir -p "$work/extracted"
  tar -xf "$archive" -C "$work/extracted"
  bundle_root="$work/extracted/${archive_name%.tar}"
  compiler="$bundle_root/bin/weft"
  signature_details="$work/compiler-signature.txt"
  codesign --verify --strict --verbose=2 "$compiler"
  codesign --display --verbose=4 "$compiler" > /dev/null 2> "$signature_details"
  signature_cdhash=$(sed -n 's/^CDHash=//p' "$signature_details" | head -1)
  if ! [[ "$signature_cdhash" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "release publish: archive code-directory identity is malformed" >&2
    exit 1
  fi
  if [ "$macos_distribution" = community ]; then
    signature_kind=$(sed -n 's/^Signature=//p' "$signature_details" | head -1)
    signature_authority=$(sed -n 's/^Authority=//p' "$signature_details" | head -1)
    if [ "$signature_kind" != adhoc ] || [ -n "$signature_authority" ]; then
      echo "release publish: community archive does not carry the expected ad-hoc signature" >&2
      exit 1
    fi
    code_signing="adhoc:$signature_cdhash"
    notarization=not-requested
  else
    signature_authority=$(sed -n 's/^Authority=//p' "$signature_details" | head -1)
    signature_team=$(sed -n 's/^TeamIdentifier=//p' "$signature_details" | head -1)
    if [[ "$signature_authority" != 'Developer ID Application: '* ]] ||
       ! [[ "$signature_team" =~ ^[A-Za-z0-9]+$ ]]; then
      echo "release publish: notarized archive does not carry a valid Developer ID identity" >&2
      exit 1
    fi
    code_signing="developer-id:$signature_team:$signature_cdhash"

    notary_zip="$work/${archive_name%.tar}.zip"
    ditto -c -k --keepParent "$bundle_root" "$notary_zip"
    notary_result="$archive.notarization.json"
    xcrun notarytool submit "$notary_zip" \
      --keychain-profile "$notary_profile" \
      --wait --timeout "$notary_timeout" \
      --output-format json > "$notary_result"
    notary_status=$(plutil -extract status raw -o - "$notary_result")
    notary_id=$(plutil -extract id raw -o - "$notary_result")
    if [ "$notary_status" != Accepted ] ||
       ! [[ "$notary_id" =~ ^[[:xdigit:]-]+$ ]]; then
      echo "release publish: Apple notarization was not accepted" >&2
      exit 1
    fi
    notarization="accepted:$notary_id"

    # A bare command-line executable cannot carry a stapled ticket. The Notary
    # service records its code-directory hash; assess that accepted compiler.
    spctl --assess --type execute --verbose=4 "$compiler"
  fi
fi

if command -v sha256sum >/dev/null 2>&1; then
  archive_sha=$(sha256sum "$archive" | awk '{print $1}')
else
  archive_sha=$(shasum -a 256 "$archive" | awk '{print $1}')
fi
archive_bytes=$(wc -c < "$archive" | tr -d ' ')
manifest="$archive.release"
if [ -e "$manifest" ] || [ -e "$manifest.sig" ]; then
  echo "release publish: refusing to overwrite an existing release manifest" >&2
  exit 1
fi
printf '%s\n' \
  'schema weft-release-manifest-v1' \
  "target $target" \
  "artifact $archive_name" \
  "sha256 $archive_sha" \
  "bytes $archive_bytes" \
  "signer $signer" \
  "source-commit $source_commit" \
  "code-signing $code_signing" \
  "notarization $notarization" > "$manifest"
chmod 644 "$manifest"

"$project_root/tools/sign_release_manifest.sh" "$manifest" >/dev/null
"$project_root/tools/verify_release_bundle.sh" \
  "$archive" "$allowed_signers" "$signer"

echo "$archive"
echo "$manifest"
echo "$manifest.sig"
