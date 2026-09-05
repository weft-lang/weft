#!/usr/bin/env bash
# Exercise acquisition failures in an otherwise valid copied compiler image.
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)
compiler=${WEFT:-"$project_root/weft"}
compiler_dir=$(CDPATH= cd -- "$(dirname "$compiler")" && pwd -P)
compiler="$compiler_dir/$(basename "$compiler")"
work=$(mktemp -d "${TMPDIR:-/tmp}/weft-sdk-acquisition.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bin" "$work/app"
cp "$project_root/test/fixtures/sdk_acquisition_probe.weft" "$work/app/main.weft"
cp "$compiler" "$work/bin/pristine"
(cd "$work/app" && "$work/bin/pristine" check main.weft) > "$work/pristine.log" 2>&1
(cd "$work/app" && "$work/bin/pristine" version --json) > "$work/version.json"
grep -q '"sdk":{"kind":"embedded","archive_version":1,"digest":"sha256:' "$work/version.json"
python3 "$project_root/test/fixtures/sdk_tool_diagnostics.py" "$work/bin/pristine" "$work/app"

for mode in magic version declared_extent entry_extent digest payload missing_module missing_manifest invalid_manifest; do
  damaged="$work/bin/$mode"
  python3 "$project_root/test/fixtures/corrupt_sdk.py" "$compiler" "$damaged" "$mode"
  chmod +x "$damaged"
  if [ "$(uname -s)" = Darwin ]; then
    # The fixture writer rehashes its outer ad-hoc signature so macOS lets
    # the SDK validator run. No actual bootstrap generation is modified.
    if ! codesign --verify --strict "$damaged" > "$work/signing.log" 2>&1; then
      sed -n '1,20p' "$work/signing.log" >&2
      exit 1
    fi
  fi
  if (cd "$work/app" && "$damaged" check main.weft) > "$work/$mode.log" 2>&1; then
    echo "SDK acquisition gate: $mode was unexpectedly accepted" >&2
    exit 1
  fi
  case "$mode" in
    missing_module)
      grep -q 'stdlib/console.weft:.*E5016' "$work/$mode.log" ;;
    missing_manifest)
      grep -q 'weft.pkg:.*E5016' "$work/$mode.log" ;;
    invalid_manifest)
      grep -q 'weft.pkg:.*E5017' "$work/$mode.log" ;;
    *) grep -q 'E5015' "$work/$mode.log" ;;
  esac
done
echo "SDK acquisition gate passed: copied binary, six corrupt images, and three canonical-path failures"
