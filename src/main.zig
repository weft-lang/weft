const std = @import("std");

// Pull in all module tests.
comptime {
    _ = @import("arena.zig");
    _ = @import("intern.zig");
    _ = @import("span.zig");
    _ = @import("diag.zig");
    _ = @import("types.zig");
    _ = @import("ir.zig");
    _ = @import("interp.zig");
    _ = @import("builtins.zig");
}

pub fn main() !void {
    _ = std.posix.write(std.posix.STDOUT_FILENO, "rhiz kernel v0.0.1\n") catch {};
}
