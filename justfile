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
