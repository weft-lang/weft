# Weft examples

Start with programs that show the language rather than its benchmark harnesses:

- [`hello.weft`](hello.weft) — a pure trait, a generic function, a custom
  effect, a named production handler, interpolation, and ordinary terminal
  output.
- [`iterator_pipeline.weft`](iterator_pipeline.weft) — a lazy iterator chain
  that specializes to a scalar loop before printing its result.
- [`error_pipeline.weft`](error_pipeline.weft) — typed error variants,
  `Fail<E>`, `?`, and recovery chosen by a handler.

Run one directly from the repository root:

```sh
./weft run examples/hello.weft
./weft run examples/iterator_pipeline.weft
```

The remaining files are executable workloads used to exercise particular
compiler and stdlib paths. They check their own result through the process
status, so most are intentionally quiet when successful:

| Area | Workloads |
|---|---|
| Collections and algorithms | `vector_algorithms.weft`, `quicksort.weft`, `sieve.weft`, `graph_workload.weft`, `sorted_collections_workload.weft` |
| Types and specialization | `generic_pipeline.weft`, `mono_heavy.weft`, `record_vector_workload.weft`, `closure_heavy.weft` |
| Effects and state | `effect_heavy.weft`, `state_machine.weft` |
| Strings and numeric work | `text_workload.weft`, `string_heavy.weft`, `time_workload.weft`, `fibonacci.weft`, `map_benchmark.weft` |
| Full-stack networking | `https_json_streams.weft` |

All examples use public language, stdlib, and runtime-handler surfaces. Raw
syscalls and pointer-shaped runtime implementation details do not belong here.
