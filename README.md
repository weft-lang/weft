# Weft

A compiled systems language with set-theoretic types, algebraic effects, and explicit memory management.

**Types are sets. Effects are capabilities. Memory is yours. Safety is the default.**

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
- **Explicit memory** -- no GC, no hidden allocations. `rc T` for opt-in deterministic reference counting. `defer` for cleanup. Allocation is an effect -- handlers choose the strategy (arena, system allocator, etc.).
- **Memory-safe by default** -- code without the `Unsafe` effect cannot perform pointer arithmetic or type-punning. `Unsafe` propagates through the type system, making trust boundaries visible and auditable. No borrow checker -- safety comes from the effect system instead.
- **Immutable by default** -- `let` is immutable. `mut` is opt-in. The compiler exploits immutability for reordering, caching, and parallelism.

## Status

Weft is in bootstrap. The Zig kernel (Layer 0) interprets a seed compiler that emits native aarch64 Mach-O binaries. The goal is self-hosting: a Weft compiler written in Weft, compiled by the seed, that then compiles itself.

```
Layer 0: Zig IR kernel          -- done
Seed grammar: parser as IR      -- done
Seed compiler: typeck + codegen -- in progress
Layer 1: Weft-in-Weft           -- next
Layer 2: self-hosted, Zig shed  -- the finish line
```

## Quick Start

**Prerequisites:** Zig 0.15.2, just

```bash
just build              # build the weft binary
just test               # run all tests
just run FILE=test/hello.weft   # interpret a .weft file
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

### Memory is explicit, safety is typed

```weft
-- Safe: rc values, stack values, defer
let config: rc Config = rc Config.default()
let alias = config  -- rc increment, not a copy

-- Safe: pointer dereference
let x: i64 = 42
let p: *i64 = &x
let val = p.*       -- safe read

-- Unsafe: pointer arithmetic (requires Unsafe effect)
fn write_at[T](buf: *mut T, index: usize, val: T) -[Unsafe]> nil {
  let ptr = Unsafe.raw_offset(buf, index)
  ptr.* = val
}
```

## Architecture

The compiler is a Weft program. IR is a Weft type. Passes are effect-annotated functions. Tools are handler configurations over the same pipeline:

| Tool | Pipeline | Effect binding |
|------|----------|----------------|
| Compiler | full pipeline | all effects handled |
| Formatter | parse only | no type-checking effects |
| LSP | parse + check | incremental handlers |
| REPL | full pipeline | JIT emit handler |

## License

TBD
