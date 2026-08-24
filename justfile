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
    ./weft build compiler/main.weft -o /tmp/weft_b1
    chmod +x /tmp/weft_b1
    echo "Stage 2: weft1 → weft2"
    /tmp/weft_b1 build compiler/main.weft -o /tmp/weft_b2
    chmod +x /tmp/weft_b2
    echo "Stage 3: weft2 → weft3"
    /tmp/weft_b2 build compiler/main.weft -o /tmp/weft_b3
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
    ./weft build compiler/main.weft -o "$bin"
    chmod +x "$bin"
    echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"opt_counters","arguments":{"source":"use compiler/main.{*}"}}}' | "$bin" mcp
    echo ""

# Build the live compiler with 5a's measurement-only reclamation census, then
# use it for one self-compile. Static site classes and dynamic RC helper-entry
# counts are emitted on stderr; both temporary binaries are removed.
rc-census:
    #!/usr/bin/env bash
    set -e
    live=$(mktemp /tmp/weft_rc_census_live_XXXXXX)
    instrumented=$(mktemp /tmp/weft_rc_census_XXXXXX)
    output=$(mktemp /tmp/weft_rc_census_output_XXXXXX)
    trap 'rm -f "$live" "$instrumented" "$output"' EXIT
    ./weft build compiler/main.weft -o "$live"
    chmod +x "$live"
    "$live" compile --rc-census compiler/main.weft > "$instrumented"
    chmod +x "$instrumented"
    "$instrumented" compile compiler/main.weft > "$output"

# Run benchmarks and record results
bench:
    bash bench.sh
