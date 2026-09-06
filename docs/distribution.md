# Installing and distributing Weft

The compiler binary contains its matching SDK. Applications built with it
incorporate the Weft runtime and library code they use; deploying an application
does not require installing the compiler. Declared native dynamic libraries
remain explicit deployment dependencies.

For a first program from a checkout, start with
[Getting started](getting-started.md). This guide covers local compiler
archives, download verification, and release-owner signing.

## Install a local compiler archive

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
`bin/weft` contains its complete matching SDK: canonical `stdlib/`, `runtime/`,
and compiler modules, the SDK manifest, and both target-native archives. The
binary can be copied to any user-owned location and put on `PATH`; it does not
need the archive's metadata directory or a checkout at runtime. Uninstallation
removes that binary and its PATH entry. No unrelated files are mutated.

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
