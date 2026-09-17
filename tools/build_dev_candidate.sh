#!/bin/bash
# Build one SDK-bearing compiler generation for focused local feedback.
# This is deliberately not a bootstrap or acceptance proof.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
output=${1:-"$repo_root/.weft-dev-candidate"}
stamp="${output}.inputs"
temporary=$(mktemp "$repo_root/.weft-dev-candidate-build-XXXXXX")
temporary_stamp=$(mktemp "$repo_root/.weft-dev-candidate-inputs-XXXXXX")
trap 'rm -f "$temporary" "$temporary_stamp"' EXIT

cd "$repo_root"

# These are exactly the inputs admitted by compiler/sdk/embed plus the trust
# root that performs the one-generation build. Test and documentation edits do
# not invalidate the compiler, so repeated focused runs after an expectation
# fix can start immediately.
sdk_input_fingerprint() {
  {
    find compiler runtime stdlib -type f -name '*.weft' -print
    printf '%s\n' \
      weft \
      weft.pkg \
      native/lib/macos-aarch64/libweft_mbedtls.a \
      native/lib/linux-aarch64/libweft_mbedtls.a
  } |
    LC_ALL=C sort |
    while IFS= read -r path; do shasum -a 256 "$path"; done |
    shasum -a 256 |
    awk '{print $1}'
}

fingerprint=$(sdk_input_fingerprint)

previous=""
if [ -r "$stamp" ]; then read -r previous < "$stamp" || previous=""; fi
if [ "$fingerprint" = "$previous" ] && [ -x "$output" ]; then
  identity=$("$output" version --json)
  if [[ "$identity" == *'"sdk":{"kind":"checkout"'* ]]; then
    echo "development candidate: reused $output"
    echo "note: one generation only; run just test-candidate for acceptance"
    exit 0
  fi
fi

./weft build compiler/main.weft -o "$temporary" --embed-sdk .
chmod +x "$temporary"

confirmed_fingerprint=$(sdk_input_fingerprint)
if [ "$confirmed_fingerprint" != "$fingerprint" ]; then
  echo "development candidate: compiler or SDK inputs changed during the build" >&2
  exit 1
fi

identity=$("$temporary" version --json)
if [[ "$identity" != *'"sdk":{"kind":"checkout"'* ]]; then
  echo "development candidate: expected checkout SDK selection: $identity" >&2
  exit 1
fi

# Replacing by name rather than overwriting the executable avoids stale macOS
# code-signing cache entries while keeping a stable path for focused commands.
rm -f "$output"
mv "$temporary" "$output"
printf '%s\n' "$fingerprint" > "$temporary_stamp"
rm -f "$stamp"
mv "$temporary_stamp" "$stamp"
trap - EXIT
echo "development candidate: $output"
echo "note: one generation only; run just test-candidate for acceptance"
