# Weft Mbed TLS adapter

Weft's alpha TLS backend is built from the official Mbed TLS 3.6.7 release
archive, not GitHub's generated source snapshots:

`https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2`

The required archive digest is
`sha256:a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6`.
`build_archive.sh` verifies that identity before extracting anything and
builds only on the matching AArch64 target host. The release pipeline runs the
build twice and requires byte-identical archives.

The target-local native-binding diagnostic gate exercises both the owned
handle/scoped-byte fixture and the real TLS handshake/read/write/close path:

```sh
# macOS/AArch64: runs the pinned archive under Guard Malloc with guard pages
# alternated before and after allocations.
just native-binding-diagnostics

# Linux/AArch64: rebuilds a diagnostic-only archive from the same pinned source
# with protected edge pages, checked alignment redzones, and unmap-on-free.
just native-binding-diagnostics /path/to/mbedtls-3.6.7.tar.bz2
```

The Linux mode sets `WEFT_MBEDTLS_PLATFORM_DIAGNOSTICS=1` only for that
temporary build and verifies a diagnostic marker before executing it. A normal
build remains the release input and must still reproduce the content digest
above exactly.

The adapter deliberately exposes no foreign callback through the Weft ABI.
Mbed TLS calls four fixed archive-internal functions for bounded memory I/O,
per-session HMAC-DRBG output and explicit certificate time verification. Weft
retains TCP, `SecureRandom`, `Time`, cancellation and buffer ownership.

The current profile is TLS 1.2 only. Mbed TLS 3.6's TLS 1.3 path requires PSA's
process-global random generator; enabling that would violate Weft's
per-session capability boundary. TLS 1.3 therefore remains an explicit design
obligation rather than silently weakening randomness ownership.

Generated archives belong in `native/lib/` for source-tree product tests and
in the target SDK bundle for release. They are content-addressed product
inputs and are not committed to git.

Mbed TLS is Copyright The Mbed TLS Contributors and is distributed here under
the Apache-2.0 side of its `Apache-2.0 OR GPL-2.0-or-later` release licence.
The SDK's `LICENSE-APACHE` contains the applicable full licence text, and its
machine-readable third-party inventory records both source and target-archive
digests.
