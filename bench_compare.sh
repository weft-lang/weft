#!/bin/bash
# Preserve the public command and environment knobs; orchestration, structured
# records, and direct process timing share one implementation.
set -euo pipefail
cd "$(dirname "$0")"
exec python3 bench_compare.py "$@"
