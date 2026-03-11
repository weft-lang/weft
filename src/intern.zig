const std = @import("std");
const Allocator = std.mem.Allocator;
const Arena = @import("arena.zig").Arena;

/// A type-safe handle to an interned string. Compare by value, not content.
pub const InternedString = enum(u32) {
    _,

    pub fn index(self: InternedString) u32 {
        return @intFromEnum(self);
    }
};

/// String interning pool. Deduplicates strings and allows O(1) comparison by index.
pub const InternPool = struct {
    map: std.StringHashMapUnmanaged(InternedString),
    strings: std.ArrayListUnmanaged([]const u8),
    arena: Arena,

    pub fn init(backing: Allocator) InternPool {
        return .{
            .map = .empty,
            .strings = .empty,
            .arena = Arena.init(backing),
        };
    }

    pub fn deinit(self: *InternPool, gpa: Allocator) void {
        self.map.deinit(gpa);
        self.strings.deinit(gpa);
        self.arena.deinit();
    }

    /// Intern a string. Returns the same id for the same content.
    pub fn intern(self: *InternPool, gpa: Allocator, s: []const u8) !InternedString {
        if (self.map.get(s)) |id| return id;

        const duped = try self.arena.dupe(s);
        const id: InternedString = @enumFromInt(@as(u32, @intCast(self.strings.items.len)));
        try self.strings.append(gpa, duped);
        try self.map.put(gpa, duped, id);
        return id;
    }

    /// Retrieve the string content for an interned id.
    pub fn get(self: *const InternPool, id: InternedString) []const u8 {
        return self.strings.items[@intFromEnum(id)];
    }

    pub fn count(self: *const InternPool) u32 {
        return @intCast(self.strings.items.len);
    }
};

test "intern: idempotency" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const a = try pool.intern(gpa, "hello");
    const b = try pool.intern(gpa, "hello");
    try std.testing.expectEqual(a, b);
}

test "intern: distinctness" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const a = try pool.intern(gpa, "hello");
    const b = try pool.intern(gpa, "world");
    try std.testing.expect(a != b);
}

test "intern: round-trip" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const id = try pool.intern(gpa, "test string");
    try std.testing.expectEqualStrings("test string", pool.get(id));
}

test "intern: empty string" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const id = try pool.intern(gpa, "");
    try std.testing.expectEqualStrings("", pool.get(id));
}

test "intern: many strings" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    var ids: [100]InternedString = undefined;
    for (&ids, 0..) |*slot, i| {
        var buf: [16]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "str_{d}", .{i}) catch unreachable;
        slot.* = try pool.intern(gpa, s);
    }
    try std.testing.expectEqual(@as(u32, 100), pool.count());

    // Re-intern all — count should not change.
    for (0..100) |i| {
        var buf: [16]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "str_{d}", .{i}) catch unreachable;
        const id = try pool.intern(gpa, s);
        try std.testing.expectEqual(ids[i], id);
    }
    try std.testing.expectEqual(@as(u32, 100), pool.count());
}

test "intern: unicode" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const id = try pool.intern(gpa, "café ☕ 日本語");
    try std.testing.expectEqualStrings("café ☕ 日本語", pool.get(id));
}
