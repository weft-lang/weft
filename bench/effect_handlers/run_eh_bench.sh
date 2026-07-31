#!/bin/bash
# run_eh_bench.sh — run the Effect Handlers Benchmark Suite ports.
# Records JSONL to bench/effect_handlers/results.jsonl unless
# EH_BENCH_RECORD=0. Each benchmark self-verifies its spec output and
# exits 0 on success, so a wrong result is a run failure, not a silent
# number. See README.md for port fidelity notes and N/A entries.
set -e

WEFT=${WEFT:-./weft}
RUNS=${EH_BENCH_RUNS:-5}
WARMUPS=${EH_BENCH_WARMUPS:-1}
RECORD=${EH_BENCH_RECORD:-1}
OUT=${EH_BENCH_OUT:-bench/effect_handlers/results.jsonl}
SHA=$(git rev-parse --short HEAD)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP_ROOT=$(mktemp -d /tmp/weft_ehb_XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT

BENCHES="countdown fibonacci_recursive product_early iterator generator handler_sieve parsing_dollars"

RESULTS=""
FAIL=0
echo "=== Effect Handlers Benchmark Suite (${SHA}) ==="
for b in $BENCHES; do
  bin="$TMP_ROOT/$b"
  if ! "$WEFT" compile "bench/effect_handlers/${b}.weft" > "$bin" 2>/dev/null; then
    echo "  $b: COMPILE FAILED"; FAIL=$((FAIL+1)); continue
  fi
  chmod +x "$bin"
  durations=$(python3 - "$bin" "$WARMUPS" "$RUNS" <<'PY'
import subprocess, sys, time
bin_path, warmups, runs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
def once():
    start = time.perf_counter_ns()
    r = subprocess.run([bin_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return r.returncode, (time.perf_counter_ns() - start) / 1e6
for _ in range(warmups):
    code, _ = once()
    if code != 0: raise SystemExit(code)
vals = []
for _ in range(runs):
    code, ms = once()
    if code != 0: raise SystemExit(code)
    vals.append(ms)
print(",".join(f"{v:.1f}" for v in vals))
PY
  ) || { echo "  $b: RUN FAILED (wrong output or crash)"; FAIL=$((FAIL+1)); continue; }
  min_ms=$(python3 -c "print(min(float(x) for x in '$durations'.split(',')))")
  echo "  $b: min ${min_ms}ms  [$durations]"
  if [ -n "$RESULTS" ]; then RESULTS="$RESULTS, "; fi
  RESULTS="$RESULTS\"$b\": {\"ok\": true, \"min_ms\": $min_ms, \"runs_ms\": \"$durations\"}"
done

RESULT="{\"sha\": \"$SHA\", \"ts\": \"$TS\", \"runs\": $RUNS, \"benches\": {$RESULTS}}"
if [ "$RECORD" != "0" ]; then
  echo "$RESULT" >> "$OUT"
  echo "recorded: $OUT"
else
  echo "$RESULT"
fi
[ "$FAIL" -eq 0 ] || { echo "failures: $FAIL" >&2; exit 1; }
