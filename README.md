# -[weft]>

A compiled systems language with set-theoretic types, algebraic effects, and explicit memory management.

**Every type is a set. Every side effect is in the signature.**

```weft
effect Greet {
  fn greet(name: str) -> nil
}

fn hello() -[Greet]> nil {
  Greet.greet("world")
}

fn main() -[IO]> nil {
  handle hello() {
    Greet.greet(name) -> {
      IO.print("hello {name}")
      resume(nil)
    }
  }
}
```

## What is Weft?

Weft is a compiled language that combines set-theoretic types, algebraic effects, and explicit memory management. The type system tracks what your code *does* -- which effects it performs, what types flow through it, where unsafety lives -- and the compiler uses that information to verify correctness and generate efficient code.

- **Set-theoretic types** -- types are sets. Union (`i64 | str`), intersection (`Display & Eq`), complement (`~nil`). Subtyping is set inclusion. Pattern matching narrows by set difference. One algebra for everything.
- **Algebraic effects** -- every side effect is declared in the function's type. Pure functions are proven pure by the compiler. Effects subsume error handling, async, iterators, and concurrency under one mechanism.
- **Managed by default, manual when needed** -- heap values use deterministic reference counting automatically. No annotation, no GC. When you need control, raw pointers and explicit allocators are available within the language via the `Alloc` and `Unsafe` effects.
- **Memory-safe by default** -- code without the `Unsafe` effect cannot perform pointer arithmetic or type-punning. `Unsafe` propagates through the type system, making trust boundaries visible and auditable. No borrow checker -- safety comes from the effect system instead.
- **Immutable by default** -- `let` is immutable. `mut` is opt-in. The compiler exploits immutability for reordering, caching, and parallelism.

## Status

Weft has achieved self-hosting. The compiler, written in Weft, compiles itself to native aarch64 Mach-O binaries.

```
Layer 0: Zig IR kernel             -- done
Seed:    parser + compiler as IR   -- done
Layer 1: Weft-in-Weft              -- done (self-hosting achieved)
Layer 2: self-hosted, Zig shed     -- next
```

The bootstrap path: a Zig IR interpreter runs a seed compiler (the Weft grammar and codegen expressed as IR). The seed compiles `compiler/main.weft` -- a Weft compiler written in Weft -- which then compiles itself. The output is a native aarch64 Mach-O binary with no runtime dependencies beyond OS syscalls.

## Quick Start

**Prerequisites:** Zig 0.15.2, just

```bash
just build                          # build the weft binary
just test                           # run all tests
just run FILE=test/hello.weft       # interpret a .weft file
weft compile test/exit42.weft -o /tmp/exit42 && /tmp/exit42  # compile to native
```

## The Ideas

### Effects replace everything

Error handling, async, iterators, concurrency -- these are all effects with different handlers:

```weft
-- Error handling: Fail effect, handler returns early
effect Fail[E] {
  fn fail(err: E) -> never
}

fn parse_int(s: str) -[Fail[ParseError]]> i64 {
  -- ...
  if bad { Fail.fail(ParseError.InvalidDigit) }
  result
}

-- The caller must handle it
handle parse_int("123") {
  Fail.fail(e) -> IO.print("error: {e}")
}
```

```weft
-- Allocation strategy: handler decides
handle compile(source) {
  Alloc.alloc(layout) -> resume(arena.bump_alloc(layout))
  Alloc.free(_, _) -> resume(nil)  -- arena frees in bulk
}
```

### Types are sets, all the way down

```weft
fn describe(val: i64 | str | nil) -> str {
  match val {
    s: str -> "string: {s}"
    n: i64 -> "number: {n}"
    nil    -> "nothing"
  }
}

-- The compiler proves exhaustiveness via set coverage
-- After matching str, remaining type is (i64 | str | nil) & ~str = i64 | nil
```

### Memory: managed by default, the floor drops out

```weft
-- Application code: RC is automatic, just write code
fn parse(source: str) -> Ast {
  let tokens = List.new()   -- heap-allocated, RC-managed
  Ast { decls: List.new() }
}

-- Performance-critical: explicit allocation strategy
fn parse_fast(source: str) -[Alloc]> Ast {
  let tokens = List.new()   -- allocated from arena
  Ast { decls: List.new() }
}

-- Systems code: raw pointers, manual memory
fn write_at[T](buf: *mut T, index: usize, val: T) -[Unsafe]> nil {
  let ptr = Unsafe.raw_offset(buf, index)
  ptr.* = val
}
```

The effect signature tells you which level you're at. `-> T` is managed.
`-[Alloc]>` controls allocation strategy. `-[Unsafe]>` is raw.

## Architecture

The compiler is a Weft program. IR is a Weft type. Passes are effect-annotated functions. Tools are handler configurations over the same pipeline:

| Tool | Pipeline | Effect binding |
|------|----------|----------------|
| Compiler | full pipeline | all effects handled |
| Formatter | parse only | no type-checking effects |
| LSP | parse + check | incremental handlers |
| REPL | full pipeline | JIT emit handler |

## License

Dual-licensed under [MIT](LICENSE-MIT) or [Apache 2.0](LICENSE-APACHE), at your option.

Copyright 2026 Amplified AI, Inc.
