#!/usr/bin/env bash
# Sign one canonical Weft release manifest with an OpenSSH signing key.
set -euo pipefail

usage() {
  echo "usage: WEFT_RELEASE_SIGNING_KEY=PATH tools/sign_release_manifest.sh MANIFEST" >&2
  exit 2
}

if [ "$#" -ne 1 ]; then
  usage
fi

manifest=$1
signing_key=${WEFT_RELEASE_SIGNING_KEY:-}
if [ -z "$signing_key" ]; then
  echo "release signing: WEFT_RELEASE_SIGNING_KEY is required" >&2
  exit 1
fi
if [ ! -f "$manifest" ]; then
  echo "release signing: manifest does not exist: $manifest" >&2
  exit 1
fi
if [ ! -f "$signing_key" ]; then
  echo "release signing: signing key does not exist: $signing_key" >&2
  exit 1
fi
if ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "release signing: ssh-keygen with SSH signature support is required" >&2
  exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/weft-release-sign.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
staged_manifest="$work/manifest"
cp "$manifest" "$staged_manifest"
ssh-keygen -Y sign -f "$signing_key" -n weft-release "$staged_manifest" >/dev/null
if [ ! -f "$staged_manifest.sig" ]; then
  echo "release signing: ssh-keygen did not produce a signature" >&2
  exit 1
fi

signature="$manifest.sig"
if [ -e "$signature" ]; then
  echo "release signing: refusing to overwrite existing signature: $signature" >&2
  exit 1
fi
mv "$staged_manifest.sig" "$signature"
chmod 644 "$signature"
echo "$signature"
