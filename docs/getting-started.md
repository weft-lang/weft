# Getting started with Weft

Weft is self-hosted on macOS/AArch64 and Linux/AArch64. The checked-in `weft`
binary is the macOS compiler; it does not download a second compiler or route
through C/LLVM. It emits Mach-O or ELF directly, and the Linux product and
compiler are static kernel-ABI executables. x86-64 is post-alpha.

This guide describes both the repository toolchain and the extracted SDK shape
as they exist now. `weft build` is the native final-product path, including
cross-target selection and artifact facts. Installed-SDK discovery,
deterministic target archives, direct `weft run` execution, and immutable
locked-source acquisition are implemented. The release command enforces
detached project signatures on every public artifact. The default macOS
community channel is free and explicit; optional Developer ID/notarization is
a separate distribution channel. Private keys remain release-owner authority,
never repository data.

## Install a local SDK archive

From a checkout, build and verify the target-specific archive:

```bash
mkdir -p dist
tools/build_release_bundle.sh macos-aarch64 dist
(cd dist && shasum -a 256 -c weft-0.1.0-macos-aarch64.tar.sha256)
tar -xf dist/weft-0.1.0-macos-aarch64.tar
export PATH="$PWD/weft-0.1.0-macos-aarch64/bin:$PATH"
weft --version
```

For Linux/AArch64, select `linux-aarch64` and verify with `sha256sum -c`.
Preserve the extracted layout: `bin/weft` locates canonical `stdlib/` and
`runtime/` modules under the adjacent `lib/weft/` SDK. Installation is moving
that directory to a user-owned location and putting its `bin/` on `PATH`;
uninstallation removes that directory and its PATH entry. No unrelated files
are mutated.

The checksum detects accidental corruption; a public download is authenticated
by its signed release manifest. Obtain the project's OpenSSH allowed-signers
file through a separately trusted project channel, then verify before
extracting:

```bash
tools/verify_release_bundle.sh \
  weft-0.1.0-macos-aarch64.tar \
  /path/to/weft-allowed-signers weft-release
```

The verifier authenticates `*.tar.release.sig` in the `weft-release` signature
namespace before trusting the manifest, then checks its archive name, target,
SHA-256, byte length, source commit, platform-signing facts, safe member paths,
unique members, and absence of links or special files. A macOS manifest must
name exactly one supported channel: the community channel binds the embedded
ad-hoc code-directory hash and states that notarization was not requested; the
optional notarized channel binds a Developer ID code-directory hash and the
matching accepted notarization result. A Linux manifest must explicitly state
that platform code signing and notarization do not apply. The detached project
signature is mandatory in every case.

## Release-owner ceremony

Release signing is intentionally distinct from deterministic local bundle
construction. The OpenSSH private key path, its public allowed-signers policy,
and signer principal are explicit release-owner inputs:

```bash
WEFT_RELEASE_SIGNING_KEY=/secure/weft-release-ed25519 \
WEFT_RELEASE_SIGNER=weft-release \
WEFT_RELEASE_ALLOWED_SIGNERS=/secure/weft-allowed-signers \
tools/publish_release_bundle.sh linux-aarch64 dist
```

The default macOS community ceremony needs no Apple account or paid identity:

```bash
WEFT_RELEASE_SIGNING_KEY=/secure/weft-release-ed25519 \
WEFT_RELEASE_SIGNER=weft-release \
WEFT_RELEASE_ALLOWED_SIGNERS=/secure/weft-allowed-signers \
tools/publish_release_bundle.sh macos-aarch64 dist
```

It authenticates the archive with the project key and records the compiler's
deterministic ad-hoc Mach-O code-directory hash. The first time a downloaded
compiler is run, Gatekeeper may block the unidentified developer. After that
launch attempt, open **System Settings → Privacy & Security**, choose **Open
Anyway** for `weft`, authenticate, and run the command again. This is a
one-time approval for that compiler; it does not weaken Gatekeeper globally.

If a future release owner chooses the paid Apple channel, select it explicitly
with a 40-hex Developer ID certificate identity and an existing `notarytool`
Keychain profile:

```bash
WEFT_RELEASE_SIGNING_KEY=/secure/weft-release-ed25519 \
WEFT_RELEASE_SIGNER=weft-release \
WEFT_RELEASE_ALLOWED_SIGNERS=/secure/weft-allowed-signers \
WEFT_MACOS_DISTRIBUTION=notarized \
WEFT_MACOS_SIGNING_IDENTITY=0123456789abcdef0123456789abcdef01234567 \
WEFT_NOTARY_KEYCHAIN_PROFILE=weft-release \
tools/publish_release_bundle.sh macos-aarch64 dist
```

Publish mode refuses a dirty checkout, untracked SDK input, missing authority,
malformed identities, contradictory target-signing facts, or any pre-existing
output it could overwrite. Community publishing verifies the exact ad-hoc
Mach-O signature before fixing the archive digest. Notarized publishing signs
that exact Mach-O before hashing, submits a temporary ZIP containing the same
code directory, requires an `Accepted` response, and exercises `spctl`. Every
release distributes `.tar`, `.tar.sha256`, `.tar.release`, and
`.tar.release.sig`; only the notarized macOS channel adds
`.tar.notarization.json`.

The repository trust root remains a valid contributor setup. On an
Apple-Silicon Mac, clone the repository and verify it directly:

```bash
git clone <repository-url> weft
cd weft
chmod +x weft
./weft check examples/fibonacci.weft
export PATH="$PWD:$PATH"
```

Repository development additionally uses `just`; platform linkers compile test
fixtures and serve as differential oracles only. Ordinary product builds need
no separate language toolchain or linker.

## Your first program

Save this as `hello.weft`:

```weft run
fn main() -> i64 {
  0
}
```

Check it, compile it, and run it:

```bash
weft check hello.weft
weft run hello.weft
weft compile hello.weft > hello
chmod +x hello
./hello
```

The process exit code is the value returned by `main`. Compiler diagnostics go
to stderr; the low-level `compile` artifact goes to stdout. `weft run PATH`
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
manifest, lock, native-binding ABI, and artifact-facts schema versions. `target
show` reports the binary format, minimum platform ABI, default standalone
contract, and whether the selected target is the current host. Unknown target
aliases fail rather than silently selecting a nearby target.

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
use stdlib/unicode.{unicode_grapheme_count, unicode_normalize_nfc}

fn main() -> i64 {
  let composed = unicode_normalize_nfc("é")
  if unicode_grapheme_count(composed) == 1 { 0 } else { 1 }
}
```

Use `bytes_to_utf8` or `path_to_utf8` when crossing from arbitrary bytes to
text; both preserve a typed failure with the invalid byte offset.

## Packages and locked sources

Package identity is content-locked and module imports are qualified. With an
extracted SDK's `bin/` (or the repository root) on `PATH`, start in an empty
project directory. Local path dependencies remain the shortest first example:

```bash project
mkdir -p deps/math
(cd deps/math && weft pkg init math)
weft pkg init app
weft pkg add math deps/math
```

`pkg init app` records `source_roots: ["."]` and a typed binary target named
`app` whose source is `app.weft`. The JSON `kind` field is the persistence form
of the compiler's `binary | library` target variants; it is not an integer tag
API. Additional target sources must stay beneath one of the declared roots.

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
weft run
weft build
./target/macos-aarch64/app
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

An installed compiler resolves canonical `stdlib/` and `runtime/` imports from
its own adjacent SDK while project and dependency imports continue through the
project graph. `test/run_release_bundle.sh` verifies the commands above from an
actual archive moved into a clean installation root, with only the installed
bundle's `bin/` on the compiler PATH. It acquires a pinned archive through a
deterministic local HTTPS-provider fixture, removes that provider and source,
performs the offline rebuild in a network-disabled Linux/AArch64 container,
and removes the exact installed SDK at the end. `test/run_release_signing.sh`
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

Before the public-alpha cut, the workboard still requires the complete
target-local Linux release matrix on adequate hardware, platform diagnostics,
release-key governance, and release hardening. Paid Apple notarization is not
an alpha gate.
x86-64, a hosted package registry,
HTTP/2+ and a forever-stable native ABI are explicitly later.
The authoritative live status is the repository README and, for contributors,
`internal/briefs/INDEX.md`.

All marked Weft fences in this guide are checked by `run_tests.sh`; runnable
examples are compiled and executed, and test fences use the real native test
harness.
