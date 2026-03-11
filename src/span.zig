const std = @import("std");
const Allocator = std.mem.Allocator;

/// Type-safe file identifier.
pub const FileId = enum(u32) {
    _,

    pub fn index(self: FileId) u32 {
        return @intFromEnum(self);
    }
};

/// A byte-offset range within a source file.
pub const Span = struct {
    file: FileId,
    start: u32,
    end: u32,

    pub fn len(self: Span) u32 {
        return self.end - self.start;
    }

    pub fn contains(self: Span, offset: u32) bool {
        return offset >= self.start and offset < self.end;
    }

    /// Merge two spans in the same file into a span covering both.
    pub fn merge(a: Span, b: Span) Span {
        std.debug.assert(a.file == b.file);
        return .{
            .file = a.file,
            .start = @min(a.start, b.start),
            .end = @max(a.end, b.end),
        };
    }

    pub fn dummy() Span {
        return .{ .file = @enumFromInt(0), .start = 0, .end = 0 };
    }
};

/// Attach a span to any value.
pub fn Spanned(comptime T: type) type {
    return struct {
        node: T,
        span: Span,
    };
}

const FileEntry = struct {
    name: []const u8,
    source: []const u8,
    /// Cached line start offsets for O(log n) line/col lookup.
    line_starts: std.ArrayListUnmanaged(u32),
};

pub const LineCol = struct {
    line: u32,
    col: u32,
};

/// Maps file ids to source text and file names. Supports line/col lookup.
pub const SourceMap = struct {
    files: std.ArrayListUnmanaged(FileEntry),

    pub const empty: SourceMap = .{ .files = .empty };

    pub fn deinit(self: *SourceMap, gpa: Allocator) void {
        for (self.files.items) |*f| f.line_starts.deinit(gpa);
        self.files.deinit(gpa);
    }

    pub fn addFile(self: *SourceMap, gpa: Allocator, name: []const u8, source: []const u8) !FileId {
        const id: FileId = @enumFromInt(@as(u32, @intCast(self.files.items.len)));
        var line_starts: std.ArrayListUnmanaged(u32) = .empty;
        try line_starts.append(gpa, 0);
        for (source, 0..) |c, i| {
            if (c == '\n') try line_starts.append(gpa, @intCast(i + 1));
        }
        try self.files.append(gpa, .{
            .name = name,
            .source = source,
            .line_starts = line_starts,
        });
        return id;
    }

    pub fn getSource(self: *const SourceMap, id: FileId) []const u8 {
        return self.files.items[@intFromEnum(id)].source;
    }

    pub fn getFileName(self: *const SourceMap, id: FileId) []const u8 {
        return self.files.items[@intFromEnum(id)].name;
    }

    /// Convert a byte offset to a 0-based line and column.
    pub fn offsetToLineCol(self: *const SourceMap, id: FileId, offset: u32) LineCol {
        const starts = self.files.items[@intFromEnum(id)].line_starts.items;
        // Binary search for the line containing offset.
        var lo: u32 = 0;
        var hi: u32 = @intCast(starts.len);
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (starts[mid] <= offset) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        const line = lo - 1;
        return .{ .line = line, .col = offset - starts[line] };
    }
};

test "span: merge" {
    const file: FileId = @enumFromInt(0);
    const a = Span{ .file = file, .start = 5, .end = 10 };
    const b = Span{ .file = file, .start = 8, .end = 15 };
    const m = a.merge(b);
    try std.testing.expectEqual(@as(u32, 5), m.start);
    try std.testing.expectEqual(@as(u32, 15), m.end);
}

test "span: contains" {
    const file: FileId = @enumFromInt(0);
    const s = Span{ .file = file, .start = 5, .end = 10 };
    try std.testing.expect(s.contains(5));
    try std.testing.expect(s.contains(9));
    try std.testing.expect(!s.contains(10));
    try std.testing.expect(!s.contains(4));
}

test "span: len" {
    const file: FileId = @enumFromInt(0);
    const s = Span{ .file = file, .start = 3, .end = 7 };
    try std.testing.expectEqual(@as(u32, 4), s.len());
}

test "span: dummy" {
    const d = Span.dummy();
    try std.testing.expectEqual(@as(u32, 0), d.len());
}

test "spanned" {
    const file: FileId = @enumFromInt(0);
    const s: Spanned(u32) = .{
        .node = 42,
        .span = .{ .file = file, .start = 0, .end = 2 },
    };
    try std.testing.expectEqual(@as(u32, 42), s.node);
}

test "source_map: line/col" {
    const gpa = std.testing.allocator;
    var sm: SourceMap = .empty;
    defer sm.deinit(gpa);

    const src = "hello\nworld\nfoo";
    const fid = try sm.addFile(gpa, "test.rz", src);

    // 'h' at 0,0
    const lc0 = sm.offsetToLineCol(fid, 0);
    try std.testing.expectEqual(@as(u32, 0), lc0.line);
    try std.testing.expectEqual(@as(u32, 0), lc0.col);

    // 'w' at 1,0
    const lc1 = sm.offsetToLineCol(fid, 6);
    try std.testing.expectEqual(@as(u32, 1), lc1.line);
    try std.testing.expectEqual(@as(u32, 0), lc1.col);

    // 'o' in "world" at 1,1
    const lc2 = sm.offsetToLineCol(fid, 7);
    try std.testing.expectEqual(@as(u32, 1), lc2.line);
    try std.testing.expectEqual(@as(u32, 1), lc2.col);

    // 'f' at 2,0
    const lc3 = sm.offsetToLineCol(fid, 12);
    try std.testing.expectEqual(@as(u32, 2), lc3.line);
    try std.testing.expectEqual(@as(u32, 0), lc3.col);
}

test "source_map: file name" {
    const gpa = std.testing.allocator;
    var sm: SourceMap = .empty;
    defer sm.deinit(gpa);

    const fid = try sm.addFile(gpa, "main.rz", "fn main() {}");
    try std.testing.expectEqualStrings("main.rz", sm.getFileName(fid));
    try std.testing.expectEqualStrings("fn main() {}", sm.getSource(fid));
}

test "source_map: multiple files" {
    const gpa = std.testing.allocator;
    var sm: SourceMap = .empty;
    defer sm.deinit(gpa);

    const fid0 = try sm.addFile(gpa, "a.rz", "let a = 1\nlet b = 2");
    const fid1 = try sm.addFile(gpa, "b.rz", "let c = 3");

    try std.testing.expect(fid0 != fid1);
    try std.testing.expectEqualStrings("a.rz", sm.getFileName(fid0));
    try std.testing.expectEqualStrings("b.rz", sm.getFileName(fid1));

    // line/col in first file, second line
    const lc = sm.offsetToLineCol(fid0, 10);
    try std.testing.expectEqual(@as(u32, 1), lc.line);
    try std.testing.expectEqual(@as(u32, 0), lc.col);

    // line/col in second file
    const lc2 = sm.offsetToLineCol(fid1, 4);
    try std.testing.expectEqual(@as(u32, 0), lc2.line);
    try std.testing.expectEqual(@as(u32, 4), lc2.col);
}
