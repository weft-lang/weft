#!/bin/bash
# bench_compare.sh - compare Weft algorithm workloads with Go and Rust siblings.
# Records JSONL to bench/compare/results.jsonl unless BENCH_COMPARE_RECORD=0.
set -e

WEFT=${WEFT:-./weft}
RUNS=${BENCH_COMPARE_RUNS:-7}
WARMUPS=${BENCH_COMPARE_WARMUPS:-1}
RECORD=${BENCH_COMPARE_RECORD:-1}
OUT=${BENCH_COMPARE_OUT:-bench/compare/results.jsonl}
SHA=$(git rev-parse --short HEAD)
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TMP_ROOT=$(mktemp -d /tmp/weft_compare_XXXXXX)

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

now_ms() {
  python3 -c "import time; print(int(time.perf_counter() * 1000))"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

time_command() {
  local start end status
  start=$(now_ms)
  set +e
  "$@" >/dev/null 2>/dev/null
  status=$?
  set -e
  end=$(now_ms)
  if [ "$status" -ne 0 ]; then
    echo "-1"
    return "$status"
  fi
  echo $((end - start))
  return 0
}

mean_ms() {
  local csv="$1"
  python3 -c 'import sys
vals=[int(x) for x in sys.argv[1].split(",") if x]
print(sum(vals)//len(vals) if vals else -1)' "$csv"
}

min_ms() {
  local csv="$1"
  python3 -c 'import sys
vals=[int(x) for x in sys.argv[1].split(",") if x]
print(min(vals) if vals else -1)' "$csv"
}

json_escape() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1])[1:-1])' "$1"
}

build_weft() {
  local case="$1"
  local out="$2"
  "$WEFT" < "bench/compare/weft/${case}.weft" > "$out" 2>/dev/null
  chmod +x "$out"
}

build_go() {
  local case="$1"
  local out="$2"
  go build -o "$out" "bench/compare/go/${case}.go" >/dev/null 2>/dev/null
}

build_rust() {
  local case="$1"
  local out="$2"
  rustc -C opt-level=3 -C codegen-units=1 -C target-cpu=native \
    "bench/compare/rust/${case}.rs" -o "$out" >/dev/null 2>/dev/null
}

run_binary_many() {
  local bin="$1"
  local runs="$2"
  local durations=""
  local i=0
  while [ "$i" -lt "$WARMUPS" ]; do
    time_command "$bin" >/dev/null || return 1
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$runs" ]; do
    local elapsed
    elapsed=$(time_command "$bin") || return 1
    if [ -n "$durations" ]; then durations="${durations},"; fi
    durations="${durations}${elapsed}"
    i=$((i + 1))
  done
  echo "$durations"
}

measure_variant() {
  local case="$1"
  local lang="$2"
  local build_fn="$3"
  local bin="$TMP_ROOT/${case}_${lang}"
  local build_start build_end build_ms size durations run_min run_mean ok

  build_start=$(now_ms)
  if "$build_fn" "$case" "$bin"; then
    build_end=$(now_ms)
    build_ms=$((build_end - build_start))
    size=$(wc -c < "$bin" | tr -d ' ')
    if durations=$(run_binary_many "$bin" "$RUNS"); then
      run_min=$(min_ms "$durations")
      run_mean=$(mean_ms "$durations")
      ok=true
    else
      run_min=-1
      run_mean=-1
      durations=""
      ok=false
    fi
  else
    build_end=$(now_ms)
    build_ms=$((build_end - build_start))
    size=0
    run_min=-1
    run_mean=-1
    durations=""
    ok=false
  fi

  echo "    ${lang}: build ${build_ms}ms, run min ${run_min}ms, mean ${run_mean}ms, size ${size}b"
  local escaped_durations
  escaped_durations=$(json_escape "$durations")
  VARIANT_JSON="\"${lang}\": {\"ok\": ${ok}, \"build_ms\": ${build_ms}, \"run_min_ms\": ${run_min}, \"run_mean_ms\": ${run_mean}, \"runs_ms\": \"${escaped_durations}\", \"size\": ${size}}"
}

require_cmd python3
require_cmd go
require_cmd rustc

mkdir -p "$(dirname "$OUT")"

CASES="sieve vector_sort graph_reach"
RESULTS=""
FAIL=0

echo "=== Weft Comparative Benchmarks (${SHA}) ==="
echo "runs per binary: ${RUNS}"
echo "warmups per binary: ${WARMUPS}"
echo ""

for case in $CASES; do
  echo "  ${case}"
  CASE_JSON=""

  measure_variant "$case" "weft" build_weft
  WEFT_JSON="$VARIANT_JSON"
  measure_variant "$case" "go" build_go
  GO_JSON="$VARIANT_JSON"
  measure_variant "$case" "rust" build_rust
  RUST_JSON="$VARIANT_JSON"

  CASE_JSON="\"${case}\": {${WEFT_JSON}, ${GO_JSON}, ${RUST_JSON}}"
  if [ -n "$RESULTS" ]; then RESULTS="${RESULTS}, "; fi
  RESULTS="${RESULTS}${CASE_JSON}"

  case "$WEFT_JSON$GO_JSON$RUST_JSON" in
    *"\"ok\": false"*) FAIL=$((FAIL + 1)) ;;
  esac
  echo ""
done

RESULT="{\"sha\": \"${SHA}\", \"ts\": \"${TS}\", \"runs\": ${RUNS}, \"warmups\": ${WARMUPS}, \"cases\": {${RESULTS}}}"
if [ "$RECORD" != "0" ]; then
  echo "$RESULT" >> "$OUT"
  echo "recorded: $OUT"
else
  echo "$RESULT"
fi

if [ "$FAIL" -gt 0 ]; then
  echo "comparative benchmark failures: ${FAIL}" >&2
  exit 1
fi
