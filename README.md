# -[weft]>

A compiled, general-purpose language with set-theoretic types, algebraic effects, and deterministic managed memory.

Run a file-writing program entirely in memory:

```weft test
use stdlib/file as file
use stdlib/file.{FileWrite}
use stdlib/io/types.{IoError}
use stdlib/path as path
use stdlib/result.{Result, Ok}
use stdlib/test.{Test}

fn publish() -[FileWrite]> usize {
  let page = path.from_utf8("index.html").expect("valid path")
  file.write_text(page, "<h1>Hello, world!</h1>").expect("write failed")
}

test "preview the page without touching disk" {
  let written = handle publish() {
    FileWrite.write_all(destination, contents, mode) -> {
      Test.assert_str_eq(contents.to_utf8().expect("UTF-8 page"), "<h1>Hello, world!</h1>")
      resume(Ok<usize, IoError>(contents.len()))
    }
  }
  Test.assert_eq_usize(written, 22)
}
```

The handler intercepts writes even inside the standard library, checks the
contents, and resumes `publish`. The compiler checks that `FileWrite` is its
only required capability. Tests, previews, and real filesystem writes can all
run the same application code with different handlers.

Every Weft example in this README is checked by the suite; complete programs
are compiled and run with the checked-in `./weft` binary.

## What is Weft?

Weft brings checked capabilities, replaceable I/O, and predictable resource cleanup into one language. A function's signature tells you what it needs. Handlers supply those capabilities for production, tests, or simulation. Types describe the values that can reach each branch, and owned resources are cleaned up on normal return and handled failure.

The compiler emits AArch64 Mach-O and ELF directly and is written in Weft. The language is still pre-alpha; it is ready for experiments and feedback, with compatibility changes expected before the public-alpha release.

- **Set-theoretic types** — types are sets. Union (`i64 | str`), intersection (`Display & Eq`), complement via flow narrowing. Subtyping is set inclusion.
- **Algebraic effects** — functions declare the capabilities they use; `->` declares an empty effect set. Handlers choose how operations run. The same mechanism supports error handling, state, generators, and parallel scheduling.
- **Deterministic managed memory** — heap values that escape use reference counting, inserted and elided where proven by the compiler. Ordinary source writes `T`. There is no tracing garbage collector; releasing a value can still run cleanup work. `weak` breaks cycles; `owned` gives single-owner move semantics with ordered `Drop` for resources; the `Alloc` effect lets a handler choose an allocation strategy for a call tree.
- **A sealed trusted ring** — raw pointers, syscalls, and FFI live behind the `Unsafe` effect. Ordinary code cannot perform or handle it. Capability, ownership, and borrow checking work together to enforce that boundary. Runtime/platform code and explicitly declared native binding modules form the trusted code.
- **Immutable by default** — `let` is immutable, `mut` is opt-in, and nil-guard narrowing only applies to immutable bindings.

## Status

**Pre-alpha and self-hosted.** The compiler is written in Weft and bootstraps byte-identically on macOS/AArch64 and Linux/AArch64. Mach-O products carry their own deterministic ad-hoc signature; standalone Linux products are static kernel-ABI ELF. The Zig seed interpreter is archived in git history; `./weft` is the checked-in macOS trust root. Until the public-alpha gate closes, source, package, fact-schema, and versioned native-binding contracts may change without compatibility support.

- 5074 runtime test blocks across 444 files, plus 1087 negative (must-fail) cases
- Tools as handler configurations over one pipeline: compile/check/test, the lossless formatter, checked API docs, diagnostic explanations, LSP, and JSON-RPC MCP
- Threads via the `Par` effect (pthreads), object-file emission, effect-aware optimizer with an emission-replay allocation checker
- Current release gates: the complete target-local Linux suite on adequate hardware, hardening/governance, final status/support documentation, and the two-target outside-user exercise. Install/release UX, project signing, free community macOS distribution, and native-binding platform diagnostics are complete

## Quick Start

On an Apple-Silicon Mac, the checked-in compiler includes its matching SDK.
From this repository's root:

```bash
# Check and run one source file.
echo 'fn main() -> i64 { 42 }' > answer.weft
./weft check answer.weft
./weft run answer.weft; echo $?   # 42

# Keep a native executable and its deployment facts.
./weft build answer.weft -o answer --artifact-facts answer.facts.json

# Cross-build standalone Linux/AArch64 ELF from the same source.
./weft build answer.weft -o answer-linux --target linux-aarch64

# Inspect the compiler and its target contract.
./weft --version
./weft target show linux-aarch64
```

Ordinary applications incorporate the Weft runtime and library code they use.
macOS artifacts use the operating system's `libSystem`; default Linux artifacts
use the kernel ABI. Declared native dynamic libraries remain explicit
deployment dependencies. Users do not install a separate Weft runtime.

The public guides cover:

- [Getting started](docs/getting-started.md): programs, tests, effects, Unicode, and packages.
- [Networking](docs/networking.md): narrow authority, owned connections, and bounded web streams.
- [Concurrency](docs/concurrency.md): deterministic parallel work, effectful tasks, and cancellation.
- [Property testing](docs/testing.md): generated cases, shrinking, and exact replay.
- [Installation and distribution](docs/distribution.md): compiler archives, verification, and release signing.

Contributors can run `bash run_tests.sh` for the complete suite and
`just bootstrap` for the compiler's three-generation byte-identity gate.

## The Ideas

### Effects make policy pluggable

A handler can choose how to recover from a failure without changing the function that reports it:

```weft run
use stdlib/fail.{Fail}

fn risky(n: i64) -[Fail<i64>]> i64 {
  if n < 0 { Fail<i64>.fail(1) } else { n * 2 }
}

fn main() -> i64 {
  -- doctest-exit: 99
  handle risky(0 - 5) {
    Fail<i64>.fail(e) -> 99   -- no resume: unwind to the handler
  }
}
-- exits 99
```

Returning without `resume` leaves the handled computation and runs its cleanup. Other handlers use the same mechanism to select allocation strategies, interpret state, or schedule pure parallel work while preserving deterministic observation order.

### Types are sets, and control flow narrows them

Missing configuration and an explicit decision to stop remain distinct:

```weft run
type RetryPolicy { Retry(usize), Stop }

fn attempts(input: RetryPolicy | nil) -> usize {
  let no_attempts: usize = 0
  let default_attempts: usize = 3
  match input {
    policy: RetryPolicy -> match policy { Retry(count) -> count, Stop -> no_attempts }
    nil -> default_attempts
  }
}

fn main() -> i64 {
  if attempts(Retry(5)) == 5 and attempts(Stop) == 0 and attempts(nil) == 3 { 0 } else { 1 }
}
```

Inside the typed arm, `policy` is a `RetryPolicy`; the compiler checks that the matches cover every remaining case. The same narrowing works after `if x != nil` for an immutable `x: str | nil`. `T?` is shorthand for `T | nil`.

Runtime matching needs a distinguishable representation, such as a variant or a nil sentinel. An untagged union such as `i64 | str` cannot be distinguished this way; use a variant when a runtime tag is needed.

### Memory: four layers, one visible boundary

| Layer | Surface | Memory model |
|-------|---------|--------------|
| Application | `-> T` | stack/value/inline where possible; deterministic strong managed heap when values escape |
| Allocation-aware | `-[Alloc]> T` | strategy chosen by a handler (arena, pool, default heap) |
| Resource | `owned T` | single owner, move semantics, ordered `Drop` |
| Trusted runtime | sealed `-[Unsafe]> T` | raw pointers, syscalls, FFI — runtime/platform modules only |

Most application data uses ordinary `T`. The compiler selects its storage and manages reference lifetimes. Thread-crossing values use atomic managed references where needed, under checked `Sendable` constraints.

An `owned` resource has one owner. Moving it transfers the cleanup obligation; normal return and handled failure run `Drop`. Explicit close is useful when the caller needs to inspect the close result:

```weft check
use stdlib/fail.{Fail}
use stdlib/file as file
use stdlib/file.{FileHandle}
use stdlib/io.{IO}
use stdlib/io/types.{IoError}
use stdlib/path.{Path}
use stdlib/result.{Result}

-- owned resource: one owner, explicit consuming close
fn open_and_close(path: Path) -[IO, Fail<IoError>]> Result<nil, IoError> {
  let stream: owned FileHandle = file.open_read(path)
  stream.close()
}
```

## Benchmarks

Small algorithm kernels have sibling Weft, Go, and Rust implementations with
the same algorithms, data sizes, and checked results. The Weft programs use
public collection APIs, including checked slices and optional lookups.
Minimum elapsed time from 21 runs after two warmups, Apple M4 Max,
2026-09-07, benchmark sources `42f915db` and compiler `c9e466a4`:

| Workload | Weft | Go | Rust |
|---|---:|---:|---:|
| vector_sort | 3.12 ms | 2.07 ms | 1.77 ms |
| graph_reach | 8.18 ms | 2.81 ms | 2.38 ms |
| nbody | 5.25 ms | 3.26 ms | 3.40 ms |
| sieve | 21.74 ms | 8.92 ms | 5.55 ms |
| mandelbrot | 16.57 ms | 8.80 ms | 9.33 ms |
| sorted_lookup | 32.96 ms | 17.36 ms | 7.58 ms |
| iterator_pipeline_direct | 1.52 ms | 2.08 ms | 1.86 ms |
| iterator_pipeline | 1.70 ms | 2.12 ms | 1.75 ms |

Rust uses `-C opt-level=3 -C codegen-units=1 -C target-cpu=native`; Go uses
its default build settings. These are small, process-level measurements;
startup noise matters especially for the shortest workloads.

Self-compilation at this checkpoint: **29.13 seconds** (median).

Reproduce the table with
`BENCH_COMPARE_RUNS=21 BENCH_COMPARE_WARMUPS=2 bash bench_compare.sh`.
The [benchmark guide](bench/compare/README.md) explains same-source compiler
comparisons, toolchain records, and measurement discipline.

## Architecture

The compiler is a Weft program: the IR is a Weft type, passes are effect-annotated functions, and every tool is a handler configuration over the same pipeline.

| Tool | Pipeline | Effect binding |
|------|----------|----------------|
| `weft compile` | full pipeline | all effects handled |
| `weft build` | full native pipeline | typed project/target/link/fact handlers; deterministic target directory; no host linker |
| `weft run` | full host-native pipeline | same typed project target; direct process execution; exact args/status forwarding |
| `weft fmt` | parse only | cannot depend on type info by construction |
| `weft check` | parse + check | no emission effects |
| `weft ast` | parse | structure dump |
| `weft test` | full pipeline | `Test` effect harness |
| `weft doc` | parse + check | checker-owned API facts; no lower/emit |
| `weft explain` | diagnostic registry | append-only code teaching bodies |
| `weft mcp` | parse + check + counters | JSON-RPC handlers |
| `weft lsp` | incremental parse + check | persistent project-query handlers |

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache 2.0](LICENSE-APACHE), at your option.

Copyright 2026 Amplified AI, Inc.
