# Getting started with Weft

Weft makes a function's required capabilities part of its type. Handlers let
you run the same code with real files, deterministic test data, or a different
scheduling policy. This guide starts with a native program, then adds tests,
effects, Unicode text, and a local package.

Weft is pre-alpha. macOS/AArch64 and Linux/AArch64 are implemented; source and
package contracts may change before the public-alpha release. See the
[README status](../README.md#status) for the current release gates.

## Use the compiler

On an Apple-Silicon Mac, start in this repository's root:

```bash
./weft --version
export PATH="$PWD:$PATH"
```

The checked-in binary includes its matching standard library and needs no
separate compiler, SDK, or host linker to build ordinary programs. For a
portable compiler archive, Linux/AArch64 installation, or signed downloads,
see [Installing and distributing Weft](distribution.md).

## Your first program

Save this as `hello.weft`:

```weft run
use stdlib/console as console
use stdlib/console/terminal as terminal

fn main() -> nil {
  with terminal() {
    console.println("Hello, Weft!")
  }
}
```

Check it, compile it, and run it:

```bash
weft check hello.weft
weft run hello.weft
weft build hello.weft -o hello
./hello
```

The terminal handler supplies console access. Returning `nil` from `main`
means success; an `i64` return value sets the process exit code. Diagnostics go
to stderr. `weft run PATH`
builds the host target through the same checked/native pipeline as `build`,
executes it directly with inherited standard streams and environment, forwards
its exact exit status, and removes its private temporary executable. Product
arguments follow `--`, for example `weft run hello.weft -- first "two words"`.

The explicit path form uses the Weft-owned native linker and is useful for
one-file probes and custom output paths. It can cross-build standalone
Linux/AArch64 ELF from the checked-in macOS compiler:

```bash
weft build hello.weft -o hello --artifact-facts hello.facts.json
weft build hello.weft -o hello-linux --target linux-aarch64 \
  --artifact-facts hello-linux.facts.json
```

`--target` accepts the same canonical identities used by package manifests:
`macos-aarch64` and `linux-aarch64`. Static products incorporate the Weft code
and archive members they use. Declared dynamic native libraries remain explicit
deployment dependencies and are reported as non-standalone in the facts file.

Inspect the installed compiler's compatibility and target facts directly:

```bash
weft --version
weft version --json
weft target list
weft target show linux-aarch64
```

The version report includes the compiler and language versions plus the
manifest, lock, native-binding ABI, artifact-facts schema, and SDK identity. An
installed compiler names the SHA-256 of the embedded SDK it will use; when
invoked from its own development checkout it names that checkout, so editing the
stdlib remains an immediate compiler-development loop. Before distributing a
compiler after SDK source changes, run `just update-root` to rebuild and verify
the embedded snapshot. Keep that binary refresh separate from the source/API
commit. A copied binary always uses its own snapshot, not subsequent edits to
the checkout. `target show` reports
the binary format, minimum platform ABI, default standalone contract, and
whether the selected target is the current host. Unknown target aliases fail
rather than silently selecting a nearby target.

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
weft test test/arithmetic.weft
weft test test
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
use stdlib/string
use stdlib/unicode

fn main() -> i64 {
  let composed = "é".normalize_nfc()
  if composed.len() == 2 and composed.scalar_count() == 1 and composed.grapheme_count() == 1 { 0 } else { 1 }
}
```

Lengths, counts, and byte offsets use `usize`. `str.len()` counts UTF-8 bytes;
`scalar_count()` counts Unicode scalars; `grapheme_count()` counts extended
grapheme clusters. Unicode boundary methods and `utf8.decode_next` take byte
offsets, not scalar ordinals. A next-boundary query stays at the end of text;
decoding at the end fails because no scalar begins there.

Boundary queries currently decode the whole string on each call. Use the
counting methods when only a count is needed; repeatedly asking for the next
boundary rescans the text.

Use `bytes.to_utf8()` or `path.to_utf8()` when crossing from arbitrary bytes to
text; both preserve a typed failure with the invalid byte offset.

Numeric prefix parsers use the same byte offsets. A successful parse returns
the value and the first unconsumed offset, ready for the next parser. Errors
carry a `usize` position; starting at or beyond the end preserves the requested
position in `NumParseEmpty`.

```weft run
use stdlib/num as num
use stdlib/result.{Ok, Err}
use stdlib/option.{Option}
use stdlib/string

fn main() -> i64 {
  let source = "Ω42-1.5"
  let start = source.find("42").expect("number follows the Unicode prefix")
  match num.parse_i64_prefix(source, start) {
    Ok((integer, next)) -> match num.parse_f64_prefix(source, next) {
      Ok((fraction, end)) -> if integer == 42 and fraction == -1.5 and end == source.len() { 0 } else { 1 }
      Err(_) -> 2
    }
    Err(_) -> 3
  }
}
```

## Collection methods and traversal

Collection methods infer their type arguments from values and typed callbacks.
For example, a map fold can build another map without repeating the accumulator
type at the call. Use the `iter` namespace for lazy transformation pipelines:

```weft run
use stdlib/map as map
use stdlib/map.{Map}
use stdlib/iter as iter

fn main() -> i64 {
  let flags = map.new<i64, bool>().insert(7, true).insert(11, false)
  let enabled = flags.fold(map.new<i64, bool>(),
    (result: Map<i64, bool>, key: i64, value: bool) => {
      if value { result.insert(key, value) } else { result }
    })
  let count = flags.keys()
    |> iter.filter((key: i64) => key > 0)
    |> iter.count()
  if enabled.len() == 1 and enabled.contains_key(7) and count == 2 { 0 } else { 1 }
}
```

Map iteration and folding use unspecified hash-trie order. A fold's callback
is pure; iterator consumers that accept effectful callbacks declare those
effects. Each lazy pipeline owns its iterator state and releases it when
traversal finishes or exits early.

## Packages and locked sources

Package identity is content-locked and module imports are qualified. With an
installed `weft` binary (or the repository root) on `PATH`, start in an empty
project directory. Local path dependencies remain the shortest first example:

```bash project
mkdir -p deps/math
(cd deps/math && weft pkg init math)
weft pkg init app
weft pkg add math deps/math
```

`pkg init app` creates `app.weft` and records it as the default binary target
in `weft.pkg`. Additional target sources must stay beneath one of the
manifest's declared source roots.

Put a public module in `deps/math/lib.weft`:

```weft file=deps/math/lib.weft
--- Add two integers.
pub fn add(left: i64, right: i64) -> i64 {
  left + right
}
```

Then import the package/module/declaration from `app.weft`:

```weft file=app.weft
use math/lib.{add}

fn answer() -> i64 {
  add(20, 22)
}

fn main() -> i64 {
  if answer() == 42 { 0 } else { 1 }
}
```

Lock only after the package source exists, then check, build, and run
from the directory containing `weft.pkg`:

```bash project
weft pkg lock
weft check app.weft
weft build
weft run
```

The normal build prints its deterministic artifact path and writes the
adjacent `app.facts.json` deployment/provenance report. Use `weft build app`
or `weft run app -- first "two words"` when naming the target explicitly.
Cross-building keeps the same layout, for example
`weft build app --target linux-aarch64` writes
`target/linux-aarch64/app`. Source-library targets describe package roots for
checking, documentation, and whole-program compilation; they do not pretend
that Weft has frozen a native archive ABI.

That ordering matters: changing any path-package source after `pkg lock`
changes its content identity, and the next consuming command rejects the stale
lock. Path dependencies are deliberately live and owner-relative; the cache
never shadows them.

Remote dependencies use an exact typed source rather than a moving version
range. Git sources require a lowercase 40- or 64-hex object revision. Archive
sources require an HTTPS URL and the `sha256:` transport digest:

```bash
weft pkg add parser --git https://example.org/parser.git \
  --revision 0123456789abcdef0123456789abcdef01234567
weft pkg add data --archive https://example.org/data.tar \
  --sha256 sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
weft pkg lock
weft pkg fetch --offline
```

`pkg lock` and online `pkg fetch` are the only operations here that may invoke
the audited Git/HTTPS provider commands. Ordinary `build`, `run`, `check`,
`test`, `fmt`, and `doc` are cache-only and never start a network process.
Verified trees live at `.weft/cache/sha256/<tree-digest>`; archive traversal,
links, special files, duplicate paths, size-limit violations, and byte drift
are rejected before admission. `pkg update NAME --revision HEX` or
`pkg update NAME --sha256 sha256:HEX` is the explicit pin-changing operation.
When the dependency is covered by a root trust grant, the ordinary update
acquires and checks the candidate but reports `E5014` with deterministic
before/after authority facts, then restores both `weft.pkg` and `weft.lock`.
After reviewing native libraries, symbols, safe wrapper signatures, and
effects, rerun that exact command with `--accept-trust-change` to commit the
candidate. Acceptance refreshes only the grant's exact version/source/content
identity; it never grants newly declared trusted modules.
An offline miss reports `E5011`, cache drift reports `E5012`, and provider or
transport refusal reports `E5013`. Git and `curl` are acquisition-time helper
requirements only—not compiler, linker, or deployed-program dependencies.

A hosted registry and full semver solver are not part of the first alpha.

An installed compiler resolves canonical `stdlib/` and `runtime/` imports and
SDK-native archives from its own embedded, digested payload while project and
dependency imports continue through the project graph.
The compiler validates the archive layout and whole-payload SHA-256 once,
then borrows module bytes directly from the verified image. `weft version
--json`, compiler artifact facts, and release provenance report the same SDK
archive version and digest. This integrity check is not a substitute for
verifying the release signature.

`E5015` means the embedded SDK is corrupt or incompatible: reinstall the
matching compiler binary. `E5016` names an unavailable canonical SDK path:
check the import spelling and namespace first. `E5017` identifies a malformed
or incompatible SDK `weft.pkg`, rather than a problem in the application's
manifest. Contributors using a live checkout should repair its SDK sources
or manifest; installed users should replace the compiler as one unit.

`test/run_release_bundle.sh` verifies the commands above from an actual archive
moved into a clean installation root, with only the single installed compiler
binary on the compiler PATH. It acquires a pinned archive through a
deterministic local HTTPS-provider fixture, removes that provider and source,
performs the offline rebuild in a network-disabled Linux/AArch64 container,
and removes the exact installed compiler at the end. `test/run_release_signing.sh`
pins signature trust, tamper refusal, platform-fact consistency, archive safety,
and missing-authority failures without containing any production credential.

## Diagnostics, formatting, and API docs

Useful feedback commands are:

```bash
weft check app.weft
weft explain E1002
weft fmt --check .
weft fmt --write app.weft
weft doc deps/math/lib.weft
```

Diagnostics have stable append-only codes, source provenance, related
locations, and actionable help. `--color auto|always|never` is a process-wide
presentation option. `weft doc` renders checked signatures and reports the
documented/public API census; it never reconstructs signatures from text.

## Where the alpha deliberately stops

Before the public-alpha cut, the remaining release gates are the complete
target-local Linux suite on adequate hardware, release-key/security/support
governance, hostile-input hardening, and the final two-target outside-user
exercise. Native-binding platform diagnostics are complete. Paid Apple
notarization is not an alpha gate.
x86-64, a hosted package registry,
HTTP/2+ and a forever-stable native ABI are explicitly later.
The authoritative public status is the repository README.

All marked Weft fences in this guide are checked by `run_tests.sh`; runnable
examples are compiled and executed, and test fences use the real native test
harness.
