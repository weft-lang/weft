# Getting started with Weft

Weft is self-hosted and usable today on macOS with Apple Silicon. The checked-in
`weft` binary is the compiler; it does not download a second compiler or route
through C/LLVM. Linux/aarch64 is still an explicit public-alpha gate, and
x86-64 is post-alpha.

This guide describes the repository toolchain as it exists now. In particular,
the final project-level `weft build`/`weft run` workflow has not landed yet, so
the current compile command names an input and redirects the artifact. That
transition is called out here rather than hidden behind commands that do not
exist.

## Install the repository toolchain

Clone the repository on an Apple-Silicon Mac, then verify the trust root:

```bash
git clone <repository-url> weft
cd weft
chmod +x weft
./weft check examples/fibonacci.weft
```

Repository development additionally uses `just`; linked object tests use the
macOS command-line linker. Ordinary single-file programs need no separate
language toolchain.

## Your first program

Save this as `hello.weft`:

```weft run
fn main() -> i64 {
  0
}
```

Check it, compile it, and run it:

```bash
./weft check hello.weft
./weft compile hello.weft > hello
chmod +x hello
./hello
```

The process exit code is the value returned by `main`. Compiler diagnostics go
to stderr; the native artifact goes to stdout.

## Tests

Tests are native Weft programs using the `Test` effect. Save this as
`test/arithmetic.weft`:

```weft test
test "addition is exact" {
  Test.assert_eq(20 + 22, 42)
}

test "integer division truncates" {
  Test.assert_eq(7 / 2, 3)
}
```

Run one file or recursively discover every `.weft` test below a directory:

```bash
./weft test test/arithmetic.weft
./weft test test
```

Multiple paths and globs are accepted, duplicate discoveries are removed, and
`--jobs N` controls the bounded native worker pool.

## Effects and early failure

`->` is a purity guarantee. A function that may fail says so in its type, and a
handler chooses what failure means at the call boundary:

```weft run
use stdlib/fail.{Fail}

fn require_positive(value: i64) -[Fail<str>]> i64 {
  if value > 0 { value } else { Fail<str>.fail("expected a positive value") }
}

fn main() -> i64 {
  handle require_positive(0 - 1) {
    Fail<str>.fail(message) -> if message == "expected a positive value" { 0 } else { 1 }
  }
}
```

The handler clause does not call `resume`, so control aborts to the handler.
Continuations are one-shot; deferred resumption uses the explicit `with k`
form.

## Text and bytes

`str` is valid UTF-8 text. `Bytes` is the immutable binary type for arbitrary
payloads and native paths preserve native bytes. Unicode algorithms are pinned
to Unicode 17.0.0 and are deterministic across hosts:

```weft run
use stdlib/unicode.{unicode_grapheme_count, unicode_normalize_nfc}

fn main() -> i64 {
  let composed = unicode_normalize_nfc("é")
  if unicode_grapheme_count(composed) == 1 { 0 } else { 1 }
}
```

Use `bytes_to_utf8` or `path_to_utf8` when crossing from arbitrary bytes to
text; both preserve a typed failure with the invalid byte offset.

## Local path packages

Package identity is content-locked and module imports are qualified. The
current CLI manages local/path dependencies:

```bash
mkdir -p deps/math
(cd deps/math && ../../weft pkg init math)
./weft pkg init app
./weft pkg add math deps/math
./weft pkg lock
```

Put a public module in `deps/math/lib.weft`:

```weft check
--- Add two integers.
pub fn add(left: i64, right: i64) -> i64 {
  left + right
}
```

Then import the package/module/declaration from `app.weft`:

```weft
use math/lib.{add}

fn answer() -> i64 {
  add(20, 22)
}
```

Compile from the directory containing `weft.pkg` so dependency paths and the
lockfile have an unambiguous root. A hosted registry and full semver solver are
not part of the first alpha; local locked source dependencies are.

## Diagnostics, formatting, and API docs

Useful feedback commands are:

```bash
./weft check app.weft
./weft explain E1002
./weft fmt --check .
./weft fmt --write app.weft
./weft doc stdlib/result.weft
```

Diagnostics have stable append-only codes, source provenance, related
locations, and actionable help. `--color auto|always|never` is a process-wide
presentation option. `weft doc` renders checked signatures and reports the
documented/public API census; it never reconstructs signatures from text.

## Where the alpha deliberately stops

Before the public-alpha cut, the workboard still requires the Linux/aarch64
platform row, safe networking/TLS/HTTP, the final project build/release
workflow, and release hardening. x86-64, a hosted package registry, HTTP/2+
and a forever-stable native ABI are explicitly later. The authoritative live
status is the repository README and, for contributors, `internal/briefs/INDEX.md`.

All marked Weft fences in this guide are checked by `run_tests.sh`; runnable
examples are compiled and executed, and test fences use the real native test
harness.
