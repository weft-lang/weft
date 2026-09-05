"""Mutate only a test copy of a compiler's authenticated SDK payload."""

import hashlib
import pathlib
import struct
import sys

source, destination, mode = sys.argv[1:]
image = bytearray(pathlib.Path(source).read_bytes())
candidates = []
offset = 0
while True:
    offset = image.find(b"WEFTSDK1", offset)
    if offset < 0:
        break
    if offset + 96 <= len(image):
        version, count, stride, size, index = struct.unpack_from("<5q", image, offset + 8)
        if version == 1 and count > 200 and stride == 32 and index == 96 and 96 <= size <= len(image) - offset:
            archive = bytearray(image[offset:offset + size])
            digest = bytes(archive[64:96])
            archive[64:96] = bytes(32)
            if hashlib.sha256(archive).digest() == digest:
                candidates.append((offset, size, count))
    offset += 8
assert len(candidates) == 1, "expected exactly one complete authenticated SDK"
base, size, count = candidates[0]

if mode == "magic":
    image[base] ^= 1
elif mode == "version":
    struct.pack_into("<q", image, base + 8, 999)
elif mode == "declared_extent":
    struct.pack_into("<q", image, base + 32, 2**63 - 1)
elif mode == "entry_extent":
    struct.pack_into("<q", image, base + 96 + 24, 2**63 - 1)
elif mode == "digest":
    image[base + 64] ^= 1
elif mode == "payload":
    image[base + size - 1] ^= 1
else:
    wanted = b"stdlib/console.weft" if mode == "missing_module" else b"weft.pkg"
    found = False
    for i in range(count):
        path, path_len, data, data_len = struct.unpack_from("<4q", image, base + 96 + i * 32)
        if image[base + path:base + path + path_len] == wanted:
            assert not found
            found = True
            if mode in ("missing_module", "missing_manifest"):
                image[base + path + path_len - 1] += 1
            elif mode == "invalid_manifest":
                image[base + data] = ord("!")
            else:
                raise AssertionError("unknown mutation")
    assert found, "requested SDK entry must exist"
    paths = []
    for i in range(count):
        path, path_len = struct.unpack_from("<2q", image, base + 96 + i * 32)
        paths.append(bytes(image[base + path:base + path + path_len]))
    assert paths == sorted(set(paths)), "mutation must preserve canonical ordering"
    image[base + 64:base + 96] = bytes(32)
    image[base + 64:base + 96] = hashlib.sha256(image[base:base + size]).digest()

# Preserve the compiler's outer ad-hoc signature format while rehashing only
# this disposable fixture. Apple's replacement signer cannot rewrite every
# native-emitter layout; verification and execution remain independent gates.
if image[:4] == bytes.fromhex("cffaedfe"):
    command = 32
    signature = None
    for _ in range(struct.unpack_from("<I", image, 16)[0]):
        kind, command_size = struct.unpack_from("<2I", image, command)
        if kind == 0x1D:
            signature = struct.unpack_from("<I", image, command + 8)[0]
        command += command_size
    assert signature is not None
    assert struct.unpack_from(">I", image, signature)[0] == 0xFADE0CC0
    assert struct.unpack_from(">I", image, signature + 8)[0] == 1
    assert struct.unpack_from(">I", image, signature + 12)[0] == 0
    directory = signature + struct.unpack_from(">I", image, signature + 16)[0]
    assert struct.unpack_from(">I", image, directory)[0] == 0xFADE0C02
    assert struct.unpack_from(">I", image, directory + 12)[0] & 2
    hashes, _, special, slots, limit = struct.unpack_from(">5I", image, directory + 16)
    hash_size, hash_type, _, shift = image[directory + 36:directory + 40]
    assert special == 0 and hash_size == 32 and hash_type == 2 and shift == 12
    assert limit <= signature and slots == (limit + 4095) // 4096
    for page in range(slots):
        start = page * 4096
        digest = hashlib.sha256(image[start:min(start + 4096, limit)]).digest()
        position = directory + hashes + page * 32
        image[position:position + 32] = digest

pathlib.Path(destination).write_bytes(image)
