const std = @import("std");
const Allocator = std.mem.Allocator;

/// Thin wrapper over std.heap.ArenaAllocator for bulk allocation and free.
pub const Arena = struct {
    inner: std.heap.ArenaAllocator,

    pub fn init(backing: Allocator) Arena {
        return .{ .inner = std.heap.ArenaAllocator.init(backing) };
    }

    pub fn deinit(self: *Arena) void {
        self.inner.deinit();
    }

    pub fn allocator(self: *Arena) Allocator {
        return self.inner.allocator();
    }

    pub fn create(self: *Arena, comptime T: type) !*T {
        return self.inner.allocator().create(T);
    }

    pub fn alloc(self: *Arena, comptime T: type, n: usize) ![]T {
        return self.inner.allocator().alloc(T, n);
    }

    pub fn dupe(self: *Arena, s: []const u8) ![]const u8 {
        return self.inner.allocator().dupe(u8, s);
    }

    pub fn reset(self: *Arena) void {
        _ = self.inner.reset(.retain_capacity);
    }
};

test "arena: allocate and use" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();

    const ptr = try arena.create(u64);
    ptr.* = 42;
    try std.testing.expectEqual(@as(u64, 42), ptr.*);
}

test "arena: multiple allocations" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();

    const a = try arena.create(u32);
    const b = try arena.create(u32);
    a.* = 1;
    b.* = 2;
    try std.testing.expectEqual(@as(u32, 1), a.*);
    try std.testing.expectEqual(@as(u32, 2), b.*);
}

test "arena: alloc slice" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();

    const slice = try arena.alloc(u8, 10);
    for (slice, 0..) |*byte, i| byte.* = @intCast(i);
    try std.testing.expectEqual(@as(u8, 5), slice[5]);
}

test "arena: dupe" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();

    const original = "hello world";
    const duped = try arena.dupe(original);
    try std.testing.expectEqualStrings(original, duped);
    try std.testing.expect(original.ptr != duped.ptr);
}

test "arena: reset" {
    var arena = Arena.init(std.testing.allocator);
    defer arena.deinit();

    _ = try arena.alloc(u8, 1024);
    arena.reset();
    _ = try arena.alloc(u8, 1024);
}
