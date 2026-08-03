default: test

# Full test suite + bootstrap gate
test:
    bash run_tests.sh

# Type-check the compiler tree (no codegen)
check:
    ./weft check compiler/main.weft

# Verify the bootstrap chain + byte-identical gate. Does NOT touch ./weft —
# a trust-root refresh is a deliberate, separate act: `just update-root`.
bootstrap:
    #!/usr/bin/env bash
    set -e
    echo "=== Bootstrap chain ==="
    echo "Stage 1: ./weft → weft1"
    ./weft compile compiler/main.weft > /tmp/weft_b1
    chmod +x /tmp/weft_b1
    echo "Stage 2: weft1 → weft2"
    /tmp/weft_b1 compile compiler/main.weft > /tmp/weft_b2
    chmod +x /tmp/weft_b2
    echo "Stage 3: weft2 → weft3"
    /tmp/weft_b2 compile compiler/main.weft > /tmp/weft_b3
    chmod +x /tmp/weft_b3
    echo "=== Gate check ==="
    if diff <(xxd /tmp/weft_b2) <(xxd /tmp/weft_b3) > /dev/null; then
        echo "✓ weft2 == weft3 (byte-identical)"
        if cmp -s /tmp/weft_b2 ./weft; then
            echo "✓ ./weft already matches the fresh chain (no refresh implied)"
        else
            echo "note: fresh binary differs from checked-in ./weft (expected whenever compiler source changed)."
            echo "      Run 'just update-root' ONLY for a deliberate trust-root refresh; commit it as a separate chore."
        fi
    else
        echo "✗ Gate FAILED: weft2 != weft3"
        exit 1
    fi

# Deliberate trust-root refresh: run the gate, then install weft2 as ./weft.
# rm-first (never overwrite in place) for the macOS signature cache.
update-root: bootstrap
    #!/usr/bin/env bash
    set -e
    rm -f ./weft
    cp /tmp/weft_b2 ./weft
    chmod +x ./weft
    echo "✓ Installed new trust root ./weft"
    echo "  Commit it together with (only) the source change that required it:"
    echo "  chore: update trust root — <reason>"

# Whole-compiler opt_counters (sp ops, residency, alloc checker) through a
# FRESH build of the live tree. Never measure via the checked-in root's own
# `weft mcp`: its in-process pipeline (incl. the checker) is the OLD source.
counters:
    #!/usr/bin/env bash
    set -e
    bin=$(mktemp /tmp/weft_counters_XXXXXX)
    trap 'rm -f "$bin"' EXIT
    ./weft compile compiler/main.weft > "$bin"
    chmod +x "$bin"
    echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{"source":"use \"compiler/main.weft\""}}}' | "$bin" mcp
    echo ""

# Run the full self-hosting test suite
selfhost:
    bash test_self_host.sh

# Run benchmarks and record results
bench:
    bash bench.sh
