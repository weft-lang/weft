# -[weft]>

A compiled, general-purpose language with set-theoretic types, algebraic effects, and deterministic managed memory.

**Every type is a set. Every side effect is in the signature.**

```weft run
use runtime/console_write as terminal
use stdlib/console.{println}

default handler terminal()

trait Greeting {
  fn greeting(self) -> str
}

impl Greeting for str {
  fn greeting(self: str) -> str { "hello, {self}!" }
}

effect Greet {
  fn say(message: str) -> nil
}

fn welcome<T: Greeting>(guest: T) -[Greet]> nil {
  Greet.say(guest.greeting())
}

fn main() -> nil {
  handle welcome<str>("world") {
    Greet.say(message) -> {
      println(message)
      resume(nil)
    }
  }
}
```

The trait is pure, `Greet` describes the program's intent, and its handler
chooses terminal output as the interpretation. `default handler terminal()`
installs the production `ConsoleWrite` implementation for the module. Normal
`nil` completion means exit status 0. `println` is the terminal-on-write-error
convenience; `try_println` preserves `Result<usize, IoError>` when recovery is
part of the program. No runtime callback or ignored error is hiding here.

Every Weft example in this README is checked by the suite; complete programs
are compiled and run with the checked-in `./weft` binary.

## What is Weft?

Weft is a compiled language that combines set-theoretic types, algebraic effects, and deterministic managed memory. The type system tracks what your code *does* — which effects it performs, what types flow through it, where trust boundaries live — and the compiler uses that information to verify correctness and generate efficient native code. No LLVM, no C middleman: the compiler emits AArch64 Mach-O and ELF directly, and it compiles itself.

- **Set-theoretic types** — types are sets. Union (`i64 | str`), intersection (`Display & Eq`), complement via flow narrowing. Subtyping is set inclusion. One algebra for everything.
- **Algebraic effects** — every side effect is declared in the function's type. `->` is a purity guarantee the compiler enforces. Effects subsume error handling, state, iterators, and parallelism under one mechanism, and handlers decide policy at the call boundary.
- **Deterministic managed memory** — heap values that escape use deterministic reference counting, inserted and aggressively elided by the compiler. Ordinary source writes `T`, never `rc T`. No tracing GC, no pauses. `weak` breaks cycles; `owned` gives single-owner move semantics with ordered `Drop` for resources; the `Alloc` effect lets a handler choose the allocation strategy (arenas, pools) for a whole call tree.
- **A sealed trusted ring** — raw pointers, syscalls, and FFI live behind the `Unsafe` effect, which is sealed inside the runtime/platform modules. Ordinary code cannot perform or handle it; safety comes from the effect system, not a borrow checker. The trust boundary is visible, auditable, and small.
- **Immutable by default** — `let` is immutable, `mut` is opt-in, and nil-guard narrowing only applies to immutable bindings.

## Status

**Pre-alpha and self-hosted.** The compiler is written in Weft and bootstraps byte-identically on macOS/AArch64 and Linux/AArch64. Mach-O products carry their own deterministic ad-hoc signature; standalone Linux products are static kernel-ABI ELF. The Zig seed interpreter is archived in git history; `./weft` is the checked-in macOS trust root. Until the public-alpha gate closes, source, package, fact-schema, and versioned native-binding contracts may change without compatibility support.

- 4,613 runtime test blocks, plus 1,061 negative (must-fail) cases
- Tools as handler configurations over one pipeline: compile/check/test, the lossless formatter, checked API docs, diagnostic explanations, LSP, and JSON-RPC MCP
- Threads via the `Par` effect (pthreads), object-file emission, effect-aware optimizer with an emission-replay allocation checker
- Current release gates: the complete target-local Linux suite on adequate hardware, hardening/governance, final status/support documentation, and the two-target outside-user exercise. Install/release UX, project signing, free community macOS distribution, and native-binding platform diagnostics are complete

## Quick Start

For the complete checked first-project path, including tests, effects, Unicode,
local packages, diagnostics, and the current alpha boundary, see
[Getting started with Weft](docs/getting-started.md). The split network
capabilities, value policies, owned sockets, and readiness contract are covered
in [Networking in Weft](docs/networking.md). The distinction between checked
parallelism, effectful task scheduling, bounded channels, and cancellation is
covered in [Concurrency in Weft](docs/concurrency.md).
Deterministic generation, shrinking, and replay are introduced in
[Property testing in Weft](docs/testing.md).

**Prerequisites:** macOS on Apple Silicon. No toolchain — the checked-in binary is the compiler.

```bash
# Compile and run a program (the compiler emits a signed executable)
echo 'fn main() -> i64 { 42 }' > answer.weft
./weft compile answer.weft > answer && chmod +x answer
./answer; echo $?   # 42

# Type-check without compiling
./weft check answer.weft

# Build the host target, run it directly, and forward its exit status
./weft run answer.weft; echo $?   # 42

# Explicit low-level product path and versioned link/BOM facts
./weft build answer.weft -o answer --artifact-facts answer.facts.json

# Cross-build the same source as standalone Linux/AArch64 ELF
./weft build answer.weft -o answer-linux --target linux-aarch64 \
  --artifact-facts answer-linux.facts.json

# Inspect the compiler/schema identity and the exact target contract
./weft --version
./weft target list
./weft target show linux-aarch64

# Verify self-hosting: the gate is byte-identical generations
just bootstrap

# Run the full test suite (parallel; duration is host-dependent)
bash run_tests.sh
```

Development products include function/file/line DWARF by default. Add
`--strip-debug` to `weft build` when the smaller release artifact matters; the
artifact-facts sidecar reports whether debug information is present.
Normal products incorporate the Weft runtime and stdlib code they use. A
standalone macOS artifact depends only on the stable `libSystem` OS ABI; a
standalone Linux artifact uses the recorded kernel ABI and has no interpreter.
Manifest-declared dynamic libraries are explicit deployment dependencies and
make the artifact facts report `standalone: false`.

Inside a package created by `weft pkg init NAME`, the manifest carries an
explicit source root and typed binary target. Plain `weft build` writes the
host product and its facts to `target/<platform>/<name>` and
`target/<platform>/<name>.facts.json`; `weft run` selects and executes the same
default target. A named target can be selected as `weft build NAME` or
`weft run NAME -- ARG...`. The `build PATH -o OUTPUT` form above remains the
explicit low-level artifact path.

Dependencies are typed as live owner-relative paths, exact Git revisions, or
HTTPS archives with a declared SHA-256. `weft pkg lock`/`fetch` populate an
immutable content-addressed cache; ordinary project commands are cache-only,
and `weft pkg fetch --offline` verifies the complete locked graph without
network authority. Updating a dependency covered by a root trust grant first
reports deterministic old/new native-authority and safe-wrapper facts as
`E5014` and restores the manifest and lock. The same command with
`--accept-trust-change` accepts the reviewed identity without widening its
trusted module set. Acquisition helpers are not linked into Weft products.

`weft version --json` reports the same compiler, language, manifest, lock,
native-binding ABI, artifact-facts schema, and supported-target identities as
machine-readable data. These values come from the compatibility facts used by
the manifest/lock validators and artifact-facts emitter; the banner is not a
separately maintained version string.

Target-specific SDK archives are built without a host linker and include the
compiler, its `stdlib/` and `runtime/` sources, compatibility facts, provenance,
licenses, and a checksum. This command produces the byte-reproducible local
probe used by the repository gate:

```bash
tools/build_release_bundle.sh macos-aarch64 dist
(cd dist && shasum -a 256 -c weft-0.1.0-macos-aarch64.tar.sha256)
tar -xf dist/weft-0.1.0-macos-aarch64.tar
export PATH="$PWD/weft-0.1.0-macos-aarch64/bin:$PATH"
weft --version
```

Use `linux-aarch64` and `sha256sum -c` on Linux. Keep the extracted `bin/` and
`lib/weft/` tree together: the compiler discovers its SDK relative to its own
executable, with no checkout path or environment override. Removing that one
directory uninstalls it. The archive bytes and clean install, project, offline
rebuild, and uninstall flow are tested on both targets.

Published artifacts use a separate fail-closed ceremony. Every target carries
a signed `*.tar.release` manifest binding the archive digest, size, source
commit, target, and platform-authenticity facts. Verify it using the project's
allowed-signers file obtained through a separately trusted channel:

```bash
tools/verify_release_bundle.sh \
  dist/weft-0.1.0-macos-aarch64.tar \
  /path/to/weft-allowed-signers weft-release
```

`tools/publish_release_bundle.sh` creates those sidecars. Linux and the default
macOS community channel are authenticated by the same project signature. The
macOS compiler retains its deterministic ad-hoc code signature, so Gatekeeper
may require one launch attempt followed by **System Settings → Privacy &
Security → Open Anyway**. Developer ID and notarization are an optional
`WEFT_MACOS_DISTRIBUTION=notarized` channel, not an alpha or source-build
requirement. Private project keys and optional Apple credentials are never
accepted from a manifest or committed to the SDK.

## The Ideas

### Effects make policy pluggable

The function says *what* it needs; the handler at the boundary decides *how* — and not resuming is an early exit, which is how error handling falls out for free:

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

The same mechanism handles allocation strategy — a handler can serve `Alloc.alloc(size, align)` from an arena for a whole call tree — state, iteration, and fork/join parallelism (`Par`), which preserves deterministic observation order by default.

### Types are sets, and control flow narrows them

```weft run
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

Small algorithm kernels with sibling Weft, Go, and Rust implementations (same algorithm, same data sizes, checksum-verified). Every Weft program is written against the public surface — bounds-checked stdlib vectors, managed memory — not runtime internals. Rust is built `-C opt-level=3 -C target-cpu=native`, Go with its default toolchain. Minimum of 11 runs after two warmups, Apple M-series, 2026-08-31, repo commit `aa16159`:

| workload | Weft | Go | Rust | Weft binary | Weft build |
|---|---|---|---|---|---|
| vector_sort | 2.8 ms | 2.4 ms | 1.7 ms | 160 KB | 316 ms |
| graph_reach | 5.1 ms | 3.5 ms | 3.1 ms | 160 KB | 306 ms |
| nbody | 5.6 ms | 3.9 ms | 3.8 ms | 160 KB | 346 ms |
| sieve | 18.4 ms | 9.5 ms | 6.1 ms | 144 KB | 297 ms |
| mandelbrot | 17.4 ms | 9.6 ms | 9.7 ms | 144 KB | 470 ms |
| sorted_lookup | 38.5 ms | 17.6 ms | 8.1 ms | 160 KB | 397 ms |

Read this table as a dated lowering/codegen snapshot, not a language scorecard.
The same repository audit initially found a real compiler-throughput regression:
three quiet self-compiles took 30.47–31.76 seconds. Executable function-graph
closure was rescanning every relocation for every candidate function on every
fixpoint pass. Indexing relocation demands at their producer removed that
quadratic path. Three quiet fixed-point self-compiles now take 22.51–23.22
seconds (median 23.04); median phase time is 22.88 seconds, including 12.23
seconds optimizing and 6.05 seconds emitting 13,035 functions. On identical
2026-08-21 source, ten alternating pairs put the fixed compiler at 17.91 seconds
versus 18.80 seconds for the historical compiler (4.60% faster). All six
algorithm products remain byte-identical across the change and their paired
runtime verdicts are flat.

Reproduce the algorithm snapshot with `bash bench_compare.sh`; its timestamped
JSONL output is local measurement data and is ignored by Git. For compiler
changes, use `bench_verdict.py` for same-session interleaved A/B measurements.
The most representative single number remains self-compilation.

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
