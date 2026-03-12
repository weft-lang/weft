// Seed modules — IR generators that teach the kernel how to parse and compile .weft files.
//
// The seed is a self-contained compiler written as IR that runs on the kernel's
// interpreter. It bootstraps the language: once Weft can compile itself, the seed
// is no longer needed.

pub const grammar = @import("seed/grammar.zig");
pub const gen = @import("seed/gen.zig");
pub const typeck = @import("seed/typeck.zig");
pub const lower = @import("seed/lower.zig");
pub const emit = @import("seed/emit.zig");
