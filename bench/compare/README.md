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
- `nbody`: five-body solar-system update loop over named `Body` records,
  fixed arrays, checked slices, record updates, and `sqrt`
- `sorted_lookup`: sorted-map construction and optional lookups through its
  comparator (an ordered-collection churn canary)
- `iterator_pipeline_direct`: direct-loop control over the iterator workload
- `iterator_pipeline`: lazy range-map-filter-take-fold through each language's
  iterator or pull-closure surface (a fusion and abstraction-erasure canary)

Every workload checks its result; a nonzero exit invalidates its timing. The
Weft kernels use ordinary language features and public collection APIs. Keep
data representations, algorithms, data sizes, and checksums aligned with the
Go and Rust siblings. The n-body implementations all store position, velocity,
and mass in body records, advance five bodies for 50,000 steps with `dt = 0.01`,
and check the same final energy within `1e-9`.

Elapsed times cover a whole child process: launch, executable/runtime startup,
the workload, and exit. They are not isolated kernel timings. Taking a minimum
reduces some scheduling noise but does not remove startup cost, and startup
differs across toolchains. In particular, the iterator controls can approach
the process-startup floor; sub-millisecond differences there do not establish
an algorithm-throughput ranking.

For throughput claims, also measure an empty executable from each toolchain
under the same conditions and use longer in-process batches or time the kernel
inside the process. Keep batching, input sizes, result checks, and optimization
barriers equivalent across languages. Report this as a separate measurement,
without silently changing the historical workloads. An empty executable is a
floor comparison, not an exact quantity to subtract from a different image.

`../diagnostic/nbody_table.weft` retains the earlier table representation as a
separate compiler diagnostic. It is excluded from the comparative workload set
and published n-body results. Compiler improvements must benefit the canonical
record implementation; changing its representation to bypass a language cost
does not establish comparative performance recovery.

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

The paired harness's `self_compile` workload times
`compile compiler/main.weft`. A complete compiler build with
`build compiler/main.weft -o ... --embed-sdk .` additionally performs final
linkage and embeds the SDK; record that as a separate metric. Keep historical
absolute checkpoints alongside identical-current-source comparisons: a flat
compiler comparison does not show that accumulated self-compilation time has
stayed flat as the compiler and its dependency closure grow.

The comparative harness records the compiler SHA-256, host architecture, and
Go/Rust versions alongside every sample. The paired harness records both
compiler hashes and includes the direct and fused iterator workloads. Its
`--null` control repeats the same compiler path, preserving SDK selection.
Both harnesses wait directly for process exit; timeout polling would distort
the shortest runtimes. A statistical warning on byte-identical products is
evidence to check the measurement environment before changing the compiler.
