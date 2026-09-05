#!/usr/bin/env bash
# Build one relocatable, target-specific Weft compiler archive and checksum.
#
# Ordinary invocations produce the byte-reproducible probe artifact used by
# the repository gate. WEFT_RELEASE_PUBLISH=1 selects an authenticated public
# payload from an exactly clean tree. macOS defaults to the project-signed
# `community` channel; the optional `notarized` channel adds Developer ID.
set -euo pipefail

usage() {
  echo "usage: tools/build_release_bundle.sh macos-aarch64|linux-aarch64 OUTPUT_DIR" >&2
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
weft_bin=${WEFT:-"$project_root/weft"}
publish=${WEFT_RELEASE_PUBLISH:-0}
macos_signing_identity=${WEFT_MACOS_SIGNING_IDENTITY:-}
macos_distribution=${WEFT_MACOS_DISTRIBUTION:-community}
case "$publish" in
  0|1) ;;
  *)
    echo "release: WEFT_RELEASE_PUBLISH must be 0 or 1" >&2
    exit 2
    ;;
esac
if [ -n "$macos_signing_identity" ] && ! [[ "$macos_signing_identity" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "release: WEFT_MACOS_SIGNING_IDENTITY must be a 40-hex certificate identity" >&2
  exit 2
fi
release_channel=probe
if [ "$target" = macos-aarch64 ]; then
  case "$macos_distribution" in
    community|notarized) ;;
    *)
      echo "release: WEFT_MACOS_DISTRIBUTION must be community or notarized" >&2
      exit 2
      ;;
  esac
  if [ "$publish" = 0 ] &&
     { [ -n "${WEFT_MACOS_DISTRIBUTION+x}" ] || [ -n "$macos_signing_identity" ]; }; then
    echo "release: macOS distribution settings are only valid for publish mode" >&2
    exit 2
  fi
  if [ "$publish" = 1 ]; then
    release_channel=$macos_distribution
    if [ "$macos_distribution" = notarized ] && [ -z "$macos_signing_identity" ]; then
      echo "release: notarized macOS publishing requires WEFT_MACOS_SIGNING_IDENTITY" >&2
      exit 1
    fi
    if [ "$macos_distribution" = community ] && [ -n "$macos_signing_identity" ]; then
      echo "release: community macOS publishing cannot silently consume a Developer ID identity" >&2
      exit 2
    fi
  fi
elif [ -n "${WEFT_MACOS_DISTRIBUTION+x}" ] || [ -n "$macos_signing_identity" ]; then
  echo "release: macOS distribution settings cannot be applied to a Linux payload" >&2
  exit 2
elif [ "$publish" = 1 ]; then
  release_channel=community
fi
case "$weft_bin" in
  /*) ;;
  *) weft_bin=$(CDPATH= cd -- "$(dirname "$weft_bin")" && pwd -P)/$(basename "$weft_bin") ;;
esac

if [ "$publish" = 1 ]; then
  if [ -n "$(git -C "$project_root" status --porcelain=v1 --untracked-files=all)" ]; then
    echo "release: a publishable payload requires an exactly clean checkout" >&2
    exit 1
  fi
elif [ "${WEFT_RELEASE_ALLOW_DIRTY:-0}" != 1 ]; then
  if ! git -C "$project_root" diff --quiet --ignore-submodules -- ||
     ! git -C "$project_root" diff --cached --quiet --ignore-submodules --; then
    echo "release: tracked source is dirty; commit it or set WEFT_RELEASE_ALLOW_DIRTY=1 for a non-publishable probe" >&2
    exit 1
  fi
fi

identity_json=$($weft_bin version --json)
compiler_version=${identity_json#*\"compiler_version\":\"}
compiler_version=${compiler_version%%\"*}
if [ -z "$compiler_version" ] || [ "$compiler_version" = "$identity_json" ]; then
  echo "release: compiler identity is malformed" >&2
  exit 1
fi

source_commit=$(git -C "$project_root" rev-parse HEAD)
bundle_name="weft-$compiler_version-$target"
work=$(mktemp -d "${TMPDIR:-/tmp}/weft-release.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
stage="$work/stage"
bundle="$stage/$bundle_name"
mkdir -p "$bundle/bin" "$bundle/share/weft"

(cd "$project_root" && "$weft_bin" build compiler/main.weft \
  -o "$bundle/bin/weft" \
  --target "$target" \
  --artifact-facts "$bundle/share/weft/compiler.facts.json" \
  --embed-sdk . \
  --strip-debug)
chmod 755 "$bundle/bin/weft"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

native_archive_rel="native/lib/$target/libweft_mbedtls.a"
native_archive="$project_root/$native_archive_rel"
if [ ! -f "$native_archive" ]; then
  echo "release: missing pinned TLS archive: $native_archive_rel" >&2
  echo "release: build it target-locally with native/mbedtls/build_archive.sh" >&2
  exit 1
fi
native_archive_sha=$(sha256_file "$native_archive")
if ! grep -qF "\"content\":\"sha256:$native_archive_sha\"" "$project_root/weft.pkg"; then
  echo "release: TLS archive digest is not declared by weft.pkg for $target" >&2
  exit 1
fi
cp "$project_root/native/mbedtls/README.md" "$bundle/share/weft/mbedtls.md"

cp "$project_root/LICENSE-MIT" "$bundle/LICENSE-MIT"
cp "$project_root/LICENSE-APACHE" "$bundle/LICENSE-APACHE"
chmod 644 "$bundle/LICENSE-MIT" "$bundle/LICENSE-APACHE"
sdk_identity=$(sed -n 's/.*"sdk":\({"kind":"embedded"[^}]*}\).*/\1/p' "$bundle/share/weft/compiler.facts.json" | head -1)
sdk_digest=$(printf '%s\n' "$sdk_identity" | sed -n 's/.*"digest":"\([^"]*\)".*/\1/p')
sdk_archive_version=$(printf '%s\n' "$sdk_identity" | sed -n 's/.*"archive_version":\([0-9]*\).*/\1/p')
if ! [[ "$sdk_digest" =~ ^sha256:[[:xdigit:]]{64}$ ]]; then
  echo "release: compiler artifact facts do not name an embedded SDK digest" >&2
  exit 1
fi
if ! [[ "$sdk_archive_version" =~ ^[1-9][0-9]*$ ]]; then
  echo "release: compiler artifact facts do not name an SDK archive version" >&2
  exit 1
fi
identity_without_sdk=${identity_json%,\"sdk\":*}
if [ "$identity_without_sdk" = "$identity_json" ]; then
  echo "release: compiler identity does not expose SDK provenance" >&2
  exit 1
fi
release_identity_json="$identity_without_sdk,\"sdk\":$sdk_identity}"
printf '%s\n' "$release_identity_json" > "$bundle/share/weft/product-identity.json"

code_signing_json='{"kind":"none"}'
if [ "$target" = macos-aarch64 ]; then
  signature_details="$work/compiler-signature.txt"
  if [ -n "$macos_signing_identity" ]; then
    codesign --force --sign "$macos_signing_identity" --options runtime --timestamp "$bundle/bin/weft"
    if ! codesign --verify --strict --verbose=2 "$bundle/bin/weft"; then
      echo "release: Developer ID verification failed after signing" >&2
      exit 1
    fi
    codesign --display --verbose=4 "$bundle/bin/weft" > /dev/null 2> "$signature_details"
    signature_kind=developer-id
  else
    if ! codesign --verify --strict --verbose=2 "$bundle/bin/weft"; then
      echo "release: deterministic ad-hoc compiler signature is invalid" >&2
      exit 1
    fi
    codesign --display --verbose=4 "$bundle/bin/weft" > /dev/null 2> "$signature_details"
    signature_kind=adhoc
  fi

  signature_identifier=$(sed -n 's/^Identifier=//p' "$signature_details" | head -1)
  signature_cdhash=$(sed -n 's/^CDHash=//p' "$signature_details" | head -1)
  if ! [[ "$signature_identifier" =~ ^[A-Za-z0-9._-]+$ ]] ||
     ! [[ "$signature_cdhash" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "release: signed compiler identity is malformed" >&2
    exit 1
  fi

  if [ "$signature_kind" = developer-id ]; then
    signature_authority=$(sed -n 's/^Authority=//p' "$signature_details" | head -1)
    signature_team=$(sed -n 's/^TeamIdentifier=//p' "$signature_details" | head -1)
    if [[ "$signature_authority" != 'Developer ID Application: '* ]] ||
       ! [[ "$signature_team" =~ ^[A-Za-z0-9]+$ ]]; then
      echo "release: selected certificate is not a Developer ID Application identity" >&2
      exit 1
    fi
    code_signing_json="{\"kind\":\"developer-id\",\"identifier\":\"$signature_identifier\",\"team_id\":\"$signature_team\",\"cdhash\":\"$signature_cdhash\",\"hardened_runtime\":true,\"timestamped\":true}"
  else
    code_signing_json="{\"kind\":\"adhoc\",\"identifier\":\"$signature_identifier\",\"cdhash\":\"$signature_cdhash\",\"gatekeeper\":\"unidentified-developer\"}"
  fi
fi

compiler_sha=$(sha256_file "$bundle/bin/weft")
standalone_contract="stable libSystem operating-system ABI"
if [ "$target" = linux-aarch64 ]; then
  standalone_contract="Linux kernel ABI; no interpreter or runtime library"
fi
printf '%s\n' \
  "{\"release_schema_version\":3,\"release_channel\":\"$release_channel\",\"target\":\"$target\",\"source_commit\":\"$source_commit\",\"compiler_sha256\":\"$compiler_sha\",\"sdk_layout\":\"embedded\",\"sdk_digest\":\"$sdk_digest\",\"sdk_archive_version\":$sdk_archive_version,\"standalone_contract\":\"$standalone_contract\",\"code_signing\":$code_signing_json,\"native_dependencies\":[{\"name\":\"Mbed TLS\",\"version\":\"3.6.7\",\"source\":\"https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2\",\"source_sha256\":\"a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6\",\"archive_sha256\":\"$native_archive_sha\",\"license\":\"Apache-2.0\"}],\"product_identity\":$release_identity_json}" \
  > "$bundle/share/weft/provenance.json"
chmod 644 "$bundle/share/weft/"*.json

archive_entries="$work/archive-entries"
directories="$work/directories"
{
  printf '%s/\n' "$bundle_name"
  printf '%s/bin/\n' "$bundle_name"
  printf '%s/share/\n' "$bundle_name"
  printf '%s/share/weft/\n' "$bundle_name"
} | LC_ALL=C sort -u > "$directories"

{
  cat "$directories"
  printf '%s/LICENSE-APACHE\n' "$bundle_name"
  printf '%s/LICENSE-MIT\n' "$bundle_name"
  printf '%s/bin/weft\n' "$bundle_name"
  printf '%s/share/weft/compiler.facts.json\n' "$bundle_name"
  printf '%s/share/weft/mbedtls.md\n' "$bundle_name"
  printf '%s/share/weft/product-identity.json\n' "$bundle_name"
  printf '%s/share/weft/provenance.json\n' "$bundle_name"
} | LC_ALL=C sort -u > "$archive_entries"

# USTAR plus normalized metadata makes identical committed input produce the
# same bytes. The archive manifest fixes entry order; no checkout timestamps,
# owner names, ACLs or extended attributes enter the release.
while IFS= read -r entry; do
  path="$stage/$entry"
  if [ -d "$path" ]; then chmod 755 "$path"; else chmod 644 "$path"; fi
  if [ "$entry" = "$bundle_name/bin/weft" ]; then chmod 755 "$path"; fi
  touch -t 200001010000 "$path"
done < "$archive_entries"

archive="$work/$bundle_name.tar"
if tar --version 2>/dev/null | grep -q bsdtar; then
  COPYFILE_DISABLE=1 tar -cf "$archive" --format ustar --no-recursion \
    --uid 0 --gid 0 --uname root --gname root \
    -C "$stage" -T "$archive_entries"
else
  tar -cf "$archive" --format=ustar --owner=0 --group=0 --numeric-owner --no-recursion \
    -C "$stage" -T "$archive_entries"
fi

mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd -P)
output_archive="$output_dir/$bundle_name.tar"
if [ "$publish" = 1 ] &&
   { [ -e "$output_archive" ] || [ -e "$output_archive.sha256" ] ||
     [ -e "$output_archive.release" ] || [ -e "$output_archive.release.sig" ] ||
     [ -e "$output_archive.notarization.json" ]; }; then
  echo "release: refusing to overwrite an existing published artifact" >&2
  exit 1
fi
cp "$archive" "$output_archive"
archive_sha=$(sha256_file "$output_archive")
printf '%s  %s\n' "$archive_sha" "$bundle_name.tar" > "$output_archive.sha256"

echo "$output_archive"
