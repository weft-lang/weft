# -[weft]>

A compiled, general-purpose language with set-theoretic types, algebraic effects, and deterministic managed memory.

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
type Shape { Circle(i64), Square(i64) }

fn area3(input: Shape | nil) -> i64 {
  match input {
    s: Shape -> match s { Circle(r) -> r * 3, Square(w) -> w * 4 }
    nil      -> 0 - 1
  }
}

fn main() -> i64 {
  if area3(Circle(5)) == 15 {
    if area3(nil) == 0 - 1 { 0 } else { 2 }
  } else { 1 }
}
```

After `s: Shape`, the binding is `Shape` — the union has been narrowed by set difference, and exhaustiveness is checked as residual-set emptiness. The same narrowing works in guard position: after `if x != nil`, an `x: str | nil` binding is `str`. `T?` is sugar for `T | nil`. Typed arms require a runtime-discriminable union (nil-sentinel or variant family) — untagged unions like `i64 | str` carry no invisible boxing, and the diagnostic suggests a variant type instead.

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

Small algorithm kernels with sibling Weft, Go, and Rust implementations (same algorithm, same data sizes, checksum-verified). Every Weft program is written against the public surface — bounds-checked stdlib vectors, managed memory — not runtime internals. Rust is built `-C opt-level=3 -C target-cpu=native`, Go with its default toolchain. Minimum of 7 runs after warmup, Apple M-series, 2026-08-03, repo commit `d7d6813`:

| workload | Weft | Go | Rust | Weft binary | Weft build |
|---|---|---|---|---|---|
| vector_sort | 3.9 ms | 4.0 ms | 3.9 ms | 144 KB | 184 ms |
| graph_reach | 6.5 ms | 5.1 ms | 3.8 ms | 144 KB | 184 ms |
| nbody | 8.9 ms | 5.7 ms | 5.4 ms | 144 KB | 204 ms |
| sieve | 26.5 ms | 14.6 ms | 10.0 ms | 144 KB | 177 ms |
| mandelbrot | 29.5 ms | 15.7 ms | 16.2 ms | 192 KB | 258 ms |
| sorted_lookup | 69.1 ms | 28.4 ms | 13.4 ms | 192 KB | 256 ms |

Read this honestly: vector-heavy integer code is at parity with Go (and Rust, on vector_sort); branchy and floating-point kernels run at 1.3–1.9× Go while the FP register file and bounds machinery mature; allocation-heavy lookup code trails furthest while reference-count elision is built out. All three are active, measured work. Go and Rust binaries for the same programs are 1.7 MB and 460 KB. The compiler — a 240,000-instruction self-hosted program — builds itself in about 5 seconds.

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
