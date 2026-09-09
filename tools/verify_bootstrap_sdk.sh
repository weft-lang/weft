#!/usr/bin/env bash
# Check detached bootstrap products before accepting or installing a trust root.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: bash tools/verify_bootstrap_sdk.sh COMPILER..." >&2
  exit 1
fi

# Product identity emits this canonical JSON object. Compare only SDK identity,
# not unrelated compiler-version metadata. A checkout origin is not proof that
# the executable carries an archive: callers must supply detached products.
sdk_pattern='"sdk":(\{"kind":"embedded","archive_version":[1-9][0-9]*,"digest":"sha256:[0-9a-f]{64}"\})'
expected_sdk=
for compiler in "$@"; do
  if ! identity=$("$compiler" version --json); then
    echo "bootstrap SDK gate: cannot inspect $compiler" >&2
    exit 1
  fi
  if [[ ! $identity =~ $sdk_pattern ]]; then
    echo "bootstrap SDK gate: $compiler does not report a valid embedded SDK" >&2
    echo "Build every generation with --embed-sdk ROOT and inspect it outside the checkout." >&2
    exit 1
  fi
  actual_sdk=${BASH_REMATCH[1]}
  if [ -n "$expected_sdk" ] && [ "$actual_sdk" != "$expected_sdk" ]; then
    echo "bootstrap SDK gate: $compiler has a different SDK snapshot" >&2
    echo "expected: $expected_sdk" >&2
    echo "actual:   $actual_sdk" >&2
    exit 1
  fi
  expected_sdk=$actual_sdk
done
echo "✓ Bootstrap products share $expected_sdk"
