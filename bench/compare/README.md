# Comparative Algorithm Benchmarks

This directory contains sibling Weft, Go, and Rust implementations for small
algorithm workloads. The goal is local, repeatable comparison that points at
Weft lowering/codegen opportunities, not broad language-score claims.

Run:

```bash
bash bench_compare.sh
```

Useful knobs:

```bash
BENCH_COMPARE_RUNS=11 bash bench_compare.sh
BENCH_COMPARE_WARMUPS=2 bash bench_compare.sh
BENCH_COMPARE_RECORD=0 bash bench_compare.sh
WEFT=/tmp/weft-under-test bash bench_compare.sh
```

The first workload set is intentionally integer-only:

- `sieve`: raw word-memory loops and stores
- `vector_sort`: vector-backed insertion sort plus binary search
- `graph_reach`: adjacency-matrix reachability with vector queues

Float-heavy published benchmarks such as `n-body` and `spectral-norm` should
wait until Weft's `f64` implementation is shipped.
