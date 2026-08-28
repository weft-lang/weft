#!/usr/bin/env bash
# Build one relocatable, target-specific Weft SDK archive and checksum.
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
case "$weft_bin" in
  /*) ;;
  *) weft_bin=$(CDPATH= cd -- "$(dirname "$weft_bin")" && pwd -P)/$(basename "$weft_bin") ;;
esac

if [ "${WEFT_RELEASE_ALLOW_DIRTY:-0}" != 1 ]; then
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
mkdir -p "$bundle/bin" "$bundle/lib/weft" "$bundle/share/weft"

(cd "$project_root" && "$weft_bin" build compiler/main.weft \
  -o "$bundle/bin/weft" \
  --target "$target" \
  --artifact-facts "$bundle/share/weft/compiler.facts.json" \
  --strip-debug)
chmod 755 "$bundle/bin/weft"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sdk_files="$work/sdk-files"
git -C "$project_root" ls-files --cached --others --exclude-standard -- compiler runtime stdlib | LC_ALL=C sort > "$sdk_files"
while IFS= read -r source; do
  destination="$bundle/lib/weft/$source"
  mkdir -p "$(dirname "$destination")"
  cp "$project_root/$source" "$destination"
  chmod 644 "$destination"
done < "$sdk_files"

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
mkdir -p "$bundle/lib/weft/native/lib/$target"
cp "$project_root/weft.pkg" "$bundle/lib/weft/weft.pkg"
cp "$native_archive" "$bundle/lib/weft/$native_archive_rel"
cp "$project_root/native/mbedtls/README.md" "$bundle/share/weft/mbedtls.md"

cp "$project_root/LICENSE-MIT" "$bundle/LICENSE-MIT"
cp "$project_root/LICENSE-APACHE" "$bundle/LICENSE-APACHE"
chmod 644 "$bundle/LICENSE-MIT" "$bundle/LICENSE-APACHE"
printf '%s\n' "$identity_json" > "$bundle/share/weft/product-identity.json"

compiler_sha=$(sha256_file "$bundle/bin/weft")
standalone_contract="stable libSystem operating-system ABI"
if [ "$target" = linux-aarch64 ]; then
  standalone_contract="Linux kernel ABI; no interpreter or runtime library"
fi
printf '%s\n' \
  "{\"release_schema_version\":1,\"target\":\"$target\",\"source_commit\":\"$source_commit\",\"compiler_sha256\":\"$compiler_sha\",\"sdk_layout\":\"lib/weft\",\"standalone_contract\":\"$standalone_contract\",\"native_dependencies\":[{\"name\":\"Mbed TLS\",\"version\":\"3.6.7\",\"source\":\"https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2\",\"source_sha256\":\"a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6\",\"archive_sha256\":\"$native_archive_sha\",\"license\":\"Apache-2.0\"}],\"product_identity\":$identity_json}" \
  > "$bundle/share/weft/provenance.json"
chmod 644 "$bundle/share/weft/"*.json

archive_entries="$work/archive-entries"
directories="$work/directories"
{
  printf '%s/\n' "$bundle_name"
  printf '%s/bin/\n' "$bundle_name"
  printf '%s/lib/\n' "$bundle_name"
  printf '%s/lib/weft/\n' "$bundle_name"
  printf '%s/share/\n' "$bundle_name"
  printf '%s/share/weft/\n' "$bundle_name"
  printf '%s/lib/weft/native/\n' "$bundle_name"
  printf '%s/lib/weft/native/lib/\n' "$bundle_name"
  printf '%s/lib/weft/native/lib/%s/\n' "$bundle_name" "$target"
  while IFS= read -r source; do
    directory=$(dirname "$source")
    while [ "$directory" != . ]; do
      printf '%s/lib/weft/%s/\n' "$bundle_name" "$directory"
      parent=$(dirname "$directory")
      if [ "$parent" = "$directory" ]; then
        break
      fi
      directory=$parent
    done
  done < "$sdk_files"
} | LC_ALL=C sort -u > "$directories"

{
  cat "$directories"
  printf '%s/LICENSE-APACHE\n' "$bundle_name"
  printf '%s/LICENSE-MIT\n' "$bundle_name"
  printf '%s/bin/weft\n' "$bundle_name"
  printf '%s/lib/weft/native/lib/%s/libweft_mbedtls.a\n' "$bundle_name" "$target"
  printf '%s/lib/weft/weft.pkg\n' "$bundle_name"
  printf '%s/share/weft/compiler.facts.json\n' "$bundle_name"
  printf '%s/share/weft/mbedtls.md\n' "$bundle_name"
  printf '%s/share/weft/product-identity.json\n' "$bundle_name"
  printf '%s/share/weft/provenance.json\n' "$bundle_name"
  while IFS= read -r source; do
    printf '%s/lib/weft/%s\n' "$bundle_name" "$source"
  done < "$sdk_files"
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
cp "$archive" "$output_archive"
archive_sha=$(sha256_file "$output_archive")
printf '%s  %s\n' "$archive_sha" "$bundle_name.tar" > "$output_archive.sha256"

echo "$output_archive"
