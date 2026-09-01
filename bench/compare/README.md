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

The workload set covers integer-heavy and float-heavy kernels:

- `sieve`: raw word-memory loops and stores
- `vector_sort`: vector-backed in-place heapsort plus binary search
- `graph_reach`: adjacency-matrix reachability with vector queues
- `mandelbrot`: `f64` escape-count loops with explicit `i64` to `f64`
  conversion
- `nbody`: five-body solar-system update loop with `f64` state and `sqrt`
- `sorted_lookup`: sorted_map build plus binary-search lookups through an
  indirect comparator (an ordered-collection churn canary)
- `iterator_pipeline_direct`: direct-loop control over the iterator workload
- `iterator_pipeline`: lazy range-map-filter-take-fold through each language's
  iterator or pull-closure surface (a fusion and abstraction-erasure canary)

Further float-heavy published benchmarks such as `spectral-norm` need broader
math surfaces and better typed float storage and array ergonomics.
