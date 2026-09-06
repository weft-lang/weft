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
BENCH_COMPARE_RUNS=21 bash bench_compare.sh
BENCH_COMPARE_WARMUPS=2 bash bench_compare.sh
BENCH_COMPARE_RECORD=0 bash bench_compare.sh
WEFT=./.weft-under-test bash bench_compare.sh
```

The workload set covers integer-heavy and float-heavy kernels:

- `sieve`: bounds-checked mutable slices over an owned vector
- `vector_sort`: vector-backed in-place heapsort plus binary search
- `graph_reach`: adjacency-matrix reachability with vector queues
- `mandelbrot`: `f64` escape-count loops with explicit `i64` to `f64`
  conversion
- `nbody`: five-body solar-system update loop using the shape-checked
  `F64Table` API, optional lookup results, and `sqrt`
- `sorted_lookup`: sorted-map construction and optional lookups through its
  comparator (an ordered-collection churn canary)
- `iterator_pipeline_direct`: direct-loop control over the iterator workload
- `iterator_pipeline`: lazy range-map-filter-take-fold through each language's
  iterator or pull-closure surface (a fusion and abstraction-erasure canary)

Every workload checks its result; a nonzero exit invalidates its timing. The
Weft kernels use public collection APIs. Keep algorithms, data sizes, and
checksums aligned with the Go and Rust siblings when changing those APIs.

For compiler comparisons, keep both compiler binaries beside the checkout's
`weft` so they load the same SDK source. A detached compiler uses its embedded
SDK instead. Use verified fixed-point roots and interleaved measurements:

```bash
python3 bench_verdict.py --a ./.weft-before --b ./weft \
  --workloads self_compile --pairs 10 --out /tmp/weft-self-compile.jsonl
```

Run timing experiments without concurrent builds or tests. Record the compiler
hash, source revision, warmups, sample count, and whether numbers are minima
or medians. Use the RC census and compiler phase metrics to locate costs before
selecting an optimization; allocation counts do not measure elapsed time.
