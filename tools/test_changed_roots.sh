#!/bin/bash
# Run changed repository test roots through an already-built candidate.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: tools/test_changed_roots.sh CANDIDATE" >&2
  exit 2
fi

repo_root=$(cd "$(dirname "$0")/.." && pwd)
candidate=$1
if [[ "$candidate" != /* ]]; then candidate="$repo_root/${candidate#./}"; fi
if [ ! -x "$candidate" ]; then
  echo "changed-root preflight: candidate is not executable: $candidate" >&2
  exit 2
fi

changed=$(mktemp /tmp/weft_changed_roots_XXXXXX)
trap 'rm -f "$changed"' EXIT
cd "$repo_root"

git diff --name-only --diff-filter=ACMR -- 'test/*.weft' >> "$changed"
git diff --cached --name-only --diff-filter=ACMR -- 'test/*.weft' >> "$changed"
git ls-files --others --exclude-standard -- 'test/*.weft' >> "$changed"
if [ -n "${WEFT_CHANGED_BASE:-}" ]; then
  git diff --name-only --diff-filter=ACMR "$WEFT_CHANGED_BASE" -- 'test/*.weft' >> "$changed"
fi

roots=()
while IFS= read -r path; do
  if [ -z "$path" ] || [ ! -f "$path" ]; then continue; fi
  if grep -q 'test "' "$path" || grep -qE '(^|[[:space:]])fn[[:space:]]+main[[:space:]]*\(' "$path"; then
    roots+=("$path")
  fi
done < <(sort -u "$changed")

if [ "${#roots[@]}" -eq 0 ]; then
  echo "changed-root preflight: no changed runnable test roots"
  exit 0
fi

jobs=${WEFT_FOCUS_JOBS:-4}
case "$jobs" in
  ''|*[!0-9]*) echo "WEFT_FOCUS_JOBS must be a positive integer" >&2; exit 2 ;;
esac
if [ "$jobs" -lt 1 ]; then
  echo "WEFT_FOCUS_JOBS must be a positive integer" >&2
  exit 2
fi

echo "changed-root preflight: ${#roots[@]} roots, $jobs jobs"
printf '  %s\n' "${roots[@]}"
"$candidate" test --jobs "$jobs" "${roots[@]}"
