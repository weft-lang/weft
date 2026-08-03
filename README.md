# -[weft]>

A compiled systems language with set-theoretic types, algebraic effects, and deterministic managed memory.

**Every type is a set. Every side effect is in the signature.**

```weft
use "stdlib/io.weft"
use "stdlib/display.weft"

effect Greet {
  fn greet(name: str) -> nil
}

fn hello() -[Greet, IO]> nil {
  Greet.greet("world")
}

fn run() -[IO]> i64 {
  handle hello() {
    Greet.greet(name) -> {
      io_print("hello {name}\n")
      resume(nil)
    }
  }
  0
}

fn main() -> i64 {
  with_raw_io_i64(run)
}
```

Every code example in this README compiles and runs with the checked-in `./weft` binary.

## What is Weft?

Weft is a compiled language that combines set-theoretic types, algebraic effects, and deterministic managed memory. The type system tracks what your code *does* — which effects it performs, what types flow through it, where trust boundaries live — and the compiler uses that information to verify correctness and generate efficient native code. No LLVM, no C middleman: the compiler emits aarch64 Mach-O directly, and it compiles itself.

- **Set-theoretic types** — types are sets. Union (`i64 | str`), intersection (`Display & Eq`), complement via flow narrowing. Subtyping is set inclusion. One algebra for everything.
- **Algebraic effects** — every side effect is declared in the function's type. `->` is a purity guarantee the compiler enforces. Effects subsume error handling, state, iterators, and parallelism under one mechanism, and handlers decide policy at the call boundary.
- **Deterministic managed memory** — heap values that escape use deterministic reference counting, inserted and aggressively elided by the compiler. Ordinary source writes `T`, never `rc T`. No tracing GC, no pauses. `weak` breaks cycles; `owned` gives single-owner move semantics with ordered `Drop` for resources; the `Alloc` effect lets a handler choose the allocation strategy (arenas, pools) for a whole call tree.
- **A sealed trusted ring** — raw pointers, syscalls, and FFI live behind the `Unsafe` effect, which is sealed inside the runtime/platform modules. Ordinary code cannot perform or handle it; safety comes from the effect system, not a borrow checker. The trust boundary is visible, auditable, and small.
- **Immutable by default** — `let` is immutable, `mut` is opt-in, and nil-guard narrowing only applies to immutable bindings.

## Status

**Self-hosted.** The compiler is written in Weft, compiles itself to native aarch64 Mach-O (including its own ad-hoc code signature), and the bootstrap gate requires generation two and generation three to be byte-identical. The Zig seed interpreter is archived in git history; `./weft` is the checked-in trust root.

- 2,500+ runtime test blocks across 200+ files, plus ~350 negative (must-fail) tests
- Tools as handler configurations over one pipeline: `weft compile`, `weft fmt`, `weft check`, `weft ast`, `weft test`, and a JSON-RPC MCP server (`weft mcp`)
- Threads via the `Par` effect (pthreads), object-file emission, effect-aware optimizer with an emission-replay allocation checker
- Current work: register allocation (the compiler self-compiles in ~5s; see benchmarks below)

## Quick Start

**Prerequisites:** macOS on Apple Silicon. No toolchain — the checked-in binary is the compiler.

```bash
# Compile and run a program (the compiler emits a signed executable)
echo 'fn main() -> i64 { 42 }' > answer.weft
./weft compile answer.weft > answer && chmod +x answer
./answer; echo $?   # 42

# Type-check without compiling
./weft check answer.weft

# Verify self-hosting: the gate is byte-identical generations
just bootstrap

# Run the full test suite (~3 minutes, parallel)
bash run_tests.sh
```

## The Ideas

### Effects make policy pluggable

The function says *what* it needs; the handler at the boundary decides *how* — and not resuming is an early exit, which is how error handling falls out for free:

```weft
use "stdlib/fail.weft"

fn risky(n: i64) -[Fail]> i64 {
  if n < 0 { Fail.fail(1) } else { n * 2 }
}

fn main() -> i64 {
  handle risky(0 - 5) {
    Fail.fail(e) -> 99   -- no resume: unwind to the handler
  }
}
-- exits 99
```

The same mechanism handles allocation strategy — a handler can serve `Alloc.alloc(size, align)` from an arena for a whole call tree — state, iteration, and fork/join parallelism (`Par`), which preserves deterministic observation order by default.

### Types are sets, and control flow narrows them

```weft
use "stdlib/string.weft"
use "stdlib/display.weft"

fn label(x: str | nil) -> str {
  -- after the guard, x : (str | nil) & ~nil = str
  if x != nil { "some: {x}" } else { "none" }
}

fn main() -> i64 {
  if str_eq(label("weft"), "some: weft") == 1 {
    if str_eq(label(nil), "none") == 1 { 0 } else { 2 }
  } else { 1 }
}
```

`T?` is sugar for `T | nil`. The checker reasons about unions, intersections, and complements as sets — exhaustiveness is set coverage, narrowing is set difference.

### Memory: four layers, one visible boundary

| Layer | Surface | Memory model |
|-------|---------|--------------|
| Application | `-> T` | stack/value/inline where possible; deterministic strong managed heap when values escape |
| Allocation-aware | `-[Alloc]> T` | strategy chosen by a handler (arena, pool, default heap) |
| Resource | `owned T` | single owner, move semantics, ordered `Drop` |
| Trusted runtime | sealed `-[Unsafe]> T` | raw pointers, syscalls, FFI — runtime/platform modules only |

Application code just writes `T`. The compiler classifies storage (stack, inline, managed, region) and inserts retain/release, then elides them where lifetimes provably nest — ownership operations are a first-class optimizer target, not a fixed tax. `weak` breaks reference cycles. Values that cross a thread boundary are atomically promoted at that boundary — there is no separate `arc` type. And `Unsafe` is not an escape hatch you opt into: it is sealed inside the runtime, so an ordinary module *cannot* fabricate a pointer, and you can audit the entire trusted ring.

```weft
use "stdlib/io.weft"

-- owned resource: single owner, Drop runs on scope exit
fn copy_first_line(path: str) -[IO]> str {
  let f: owned FileHandle = io_file_open_read(path)
  io_read_line(f)
}   -- f dropped here: IO.close runs, in order
```

## Benchmarks

Small algorithm kernels with sibling Weft, Go, and Rust implementations (same algorithm, same data sizes, checksum-verified). Rust is built `-C opt-level=3 -C target-cpu=native`, Go with its default toolchain. Minimum of 7 runs after warmup, Apple M-series, 2026-08-03, repo commit `5307a96`:

| workload | Weft | Go | Rust | Weft binary | Weft build |
|---|---|---|---|---|---|
| vector_sort | 3.7 ms | 3.4 ms | 3.0 ms | 115 KB | 87 ms |
| sieve | 20.0 ms | 15.1 ms | 9.8 ms | 115 KB | 71 ms |
| graph_reach | 6.4 ms | 4.7 ms | 3.8 ms | 115 KB | ~80 ms |
| nbody | 9.5 ms | 5.6 ms | 5.3 ms | 115 KB | ~80 ms |
| mandelbrot | 29.6 ms | 15.7 ms | 16.5 ms | 115 KB | ~80 ms |
| sorted_lookup | 63.5 ms | 28.6 ms | 13.5 ms | 180 KB | 265 ms |

Read this honestly: integer/branchy code runs at 1.1–1.4× Go; floating-point and allocation-heavy code trails further while the FP register file and reference-count elision are still being built out (both are active work). Go and Rust binaries for the same programs are 1.7 MB and 460 KB. The compiler — a 240,000-instruction self-hosted program — builds itself in about 5 seconds.

Reproduce with `bash bench_compare.sh` (records JSONL with commit + timestamps). These are lowering/codegen tracking benchmarks, not a language scorecard; the most representative single number is the self-compile.

## Architecture

The compiler is a Weft program: the IR is a Weft type, passes are effect-annotated functions, and every tool is a handler configuration over the same pipeline.

| Tool | Pipeline | Effect binding |
|------|----------|----------------|
| `weft compile` | full pipeline | all effects handled |
| `weft fmt` | parse only | cannot depend on type info by construction |
| `weft check` | parse + check | no emission effects |
| `weft ast` | parse | structure dump |
| `weft test` | full pipeline | `Test` effect harness |
| `weft mcp` | parse + check + counters | JSON-RPC handlers |

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache 2.0](LICENSE-APACHE), at your option.

Copyright 2026 Amplified AI, Inc.
