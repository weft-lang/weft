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
BENCH_COMPARE_STARTUP_RUNS=51 bash bench_compare.sh
BENCH_COMPARE_CASES=vector_sort,iterator_pipeline bash bench_compare.sh
BENCH_COMPARE_RECORD=0 bash bench_compare.sh
WEFT=./.weft-under-test bash bench_compare.sh
```

The workload set includes a separate startup control plus integer-heavy and
float-heavy kernels:

- `empty`: an empty entry point, compiled with each language's normal settings
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
and mass in body records, advance five bodies for 2,000,000 steps with `dt = 0.01`,
and check the same final energy within `1e-9`.

## Workload revisions and startup

The current algorithm workloads are revision 2. Revision 1's small workloads
remain identifiable in git and in historical records; their timings must not
be compared directly with revision 2 as compiler speedups or regressions.

| Workload | Revision 2 work per process |
|---|---|
| sieve | 240 sieves below 200,000 |
| vector_sort | 60 sorts, sizes 30,000 through 30,059 |
| graph_reach | Reachability from every start in a 768-node graph |
| mandelbrot | Three 1,024 × 1,024 grids, 80-iteration limit |
| nbody | 2,000,000 steps over five body records |
| sorted_lookup | 100 sweeps over 20,000 entries, probe spans 40,000 through 40,099 |
| both iterator cases | 300 ranges, lengths 1,000,000 through 1,000,897, step 3 |

Iterator, sort and lookup repetitions vary their input rather than repeating
an identical pure call. The checksums cover every repetition. The n-body
energy and Mandelbrot count were cross-checked against both sibling programs
before pinning the larger workloads' expected results.

Elapsed times cover a whole child process: launch, executable/runtime startup,
the workload, and exit. They are not isolated kernel timings. Taking a minimum
reduces some scheduling noise but does not remove startup cost, and startup
differs across toolchains. The empty program is always included, even with a
selected subset of cases. By default it receives 51 measured runs. All builds
finish before runtime sampling; language order rotates and reverses between
rounds. The report leads with medians and retains minima, means and every raw
sample.

Each algorithm row reports the corresponding language's empty-program median
as a percentage of its workload median. Above 5%, it is labelled
`startup-sensitive`. This threshold is a measurement warning, not a claim that
the remaining percentage consists entirely of algorithm work. Larger workloads
were calibrated to clear it on the development host; other hosts or future
optimizers may make another scaling revision necessary.

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

The comparative harness records the compiler SHA-256 and SDK selection, host
architecture, Go/Rust versions, workload revisions and parameters, per-language
source and binary hashes, and build commands. Schema 2 stores `runs_ms` as a
numeric array (schema 1 used a comma-separated string) and adds median and
startup fields. The paired harness uses the same workload catalog and includes
an automatic empty-program control whenever algorithm workloads are selected.
Its verdict still describes whole-process time and carries startup warnings;
neither harness manufactures startup-subtracted kernel times. The paired harness's
`--null` control repeats the same compiler path, preserving SDK selection.
Both harnesses wait directly for process exit; timeout polling would distort
the shortest runtimes. A statistical warning on byte-identical products is
evidence to check the measurement environment before changing the compiler.

Run the harness regression tests with `python3 test/test_bench_compare.py`.
They also run in the repository gate. Benchmark checksums themselves are
validated by executing every compiled sibling, not by the harness unit tests.
