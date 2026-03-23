default: check

check:
    zig build

test:
    zig build test

build:
    zig build -Doptimize=ReleaseSafe

fmt:
    zig fmt src/

run *args:
    zig build run -- {{args}}

checkpoint: check test

# Rebuild ./weft through the bootstrap chain and verify byte-identical gate
bootstrap:
    #!/usr/bin/env bash
    set -e
    echo "=== Bootstrap chain ==="
    echo "Stage 1: ./weft → weft1"
    ./weft < compiler/main.weft > /tmp/weft_b1
    chmod +x /tmp/weft_b1
    echo "Stage 2: weft1 → weft2"
    /tmp/weft_b1 < compiler/main.weft > /tmp/weft_b2
    chmod +x /tmp/weft_b2
    echo "Stage 3: weft2 → weft3"
    /tmp/weft_b2 < compiler/main.weft > /tmp/weft_b3
    chmod +x /tmp/weft_b3
    echo "=== Gate check ==="
    codesign --remove-signature /tmp/weft_b2 2>/dev/null || true
    codesign --remove-signature /tmp/weft_b3 2>/dev/null || true
    if diff <(xxd /tmp/weft_b2) <(xxd /tmp/weft_b3) > /dev/null; then
        echo "✓ weft2 == weft3 (byte-identical)"
        mv /tmp/weft_b2 ./weft
        chmod +x ./weft
        echo "✓ Updated ./weft"
    else
        echo "✗ Gate FAILED: weft2 != weft3"
        exit 1
    fi

# Run the full self-hosting test suite
selfhost:
    bash test_self_host.sh

# Run benchmarks and record results
bench:
    bash bench.sh
