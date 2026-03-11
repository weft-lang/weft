const std = @import("std");
const Allocator = std.mem.Allocator;
const span_mod = @import("span.zig");
const Span = span_mod.Span;
const SourceMap = span_mod.SourceMap;

pub const Severity = enum {
    err,
    warn,
    note,

    pub fn symbol(self: Severity) []const u8 {
        return switch (self) {
            .err => "error",
            .warn => "warning",
            .note => "note",
        };
    }

    pub fn color(self: Severity) []const u8 {
        return switch (self) {
            .err => "\x1b[1;31m",
            .warn => "\x1b[1;33m",
            .note => "\x1b[1;36m",
        };
    }
};

pub const Label = struct {
    span: Span,
    message: []const u8,
};

pub const Diagnostic = struct {
    severity: Severity,
    code: []const u8,
    message: []const u8,
    primary: ?Span,
    labels: []const Label,
    help: ?[]const u8,

    // Builder API
    pub fn err(code: []const u8, message: []const u8) Diagnostic {
        return .{
            .severity = .err,
            .code = code,
            .message = message,
            .primary = null,
            .labels = &.{},
            .help = null,
        };
    }

    pub fn warn(code: []const u8, message: []const u8) Diagnostic {
        return .{
            .severity = .warn,
            .code = code,
            .message = message,
            .primary = null,
            .labels = &.{},
            .help = null,
        };
    }

    pub fn note(code: []const u8, message: []const u8) Diagnostic {
        return .{
            .severity = .note,
            .code = code,
            .message = message,
            .primary = null,
            .labels = &.{},
            .help = null,
        };
    }

    pub fn at(self: Diagnostic, span: Span) Diagnostic {
        var d = self;
        d.primary = span;
        return d;
    }

    pub fn withLabel(self: Diagnostic, gpa: Allocator, span: Span, message: []const u8) !Diagnostic {
        var d = self;
        const new_labels = try gpa.alloc(Label, self.labels.len + 1);
        @memcpy(new_labels[0..self.labels.len], self.labels);
        new_labels[self.labels.len] = .{ .span = span, .message = message };
        d.labels = new_labels;
        return d;
    }

    pub fn withHelp(self: Diagnostic, h: []const u8) Diagnostic {
        var d = self;
        d.help = h;
        return d;
    }

    /// Render diagnostic to writer with ANSI colors and source context.
    pub fn render(self: *const Diagnostic, sm: *const SourceMap, writer: anytype) !void {
        const reset = "\x1b[0m";
        const bold = "\x1b[1m";
        const sev_color = self.severity.color();

        // Header: error[E001]: message
        try writer.print("{s}{s}[{s}]{s}: {s}{s}{s}\n", .{
            sev_color, self.severity.symbol(), self.code, reset,
            bold,      self.message,           reset,
        });

        // Primary span
        if (self.primary) |pspan| {
            try renderSpan(pspan, null, sm, sev_color, writer);
        }

        // Labels
        for (self.labels) |label| {
            try renderSpan(label.span, label.message, sm, "\x1b[1;34m", writer);
        }

        // Help
        if (self.help) |h| {
            try writer.print("{s}help{s}: {s}\n", .{ "\x1b[1;32m", reset, h });
        }
    }
};

fn renderSpan(span: Span, label_msg: ?[]const u8, sm: *const SourceMap, color: []const u8, writer: anytype) !void {
    const reset = "\x1b[0m";
    const file_name = sm.getFileName(span.file);
    const lc = sm.offsetToLineCol(span.file, span.start);
    const source = sm.getSource(span.file);

    try writer.print("  \x1b[1;34m-->\x1b[0m {s}:{d}:{d}\n", .{
        file_name, lc.line + 1, lc.col + 1,
    });

    // Find the source line.
    const line_start: u32 = span.start - lc.col;
    var line_end: u32 = line_start;
    while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}

    const line_text = source[line_start..line_end];
    const line_num = lc.line + 1;

    try writer.print("   {d: >4} | {s}\n", .{ line_num, line_text });

    // Underline
    const underline_start = lc.col;
    const underline_len = @min(span.len(), line_end - span.start);
    try writer.writeAll("        | ");
    for (0..underline_start) |_| try writer.writeByte(' ');
    try writer.writeAll(color);
    if (underline_len == 0) {
        try writer.writeByte('^');
    } else {
        for (0..underline_len) |_| try writer.writeByte('^');
    }
    try writer.writeAll(reset);
    if (label_msg) |msg| {
        try writer.print(" {s}", .{msg});
    }
    try writer.writeByte('\n');

}

pub const DiagnosticList = struct {
    items: std.ArrayListUnmanaged(Diagnostic),

    pub const empty: DiagnosticList = .{ .items = .empty };

    pub fn deinit(self: *DiagnosticList, gpa: Allocator) void {
        self.items.deinit(gpa);
    }

    pub fn emit(self: *DiagnosticList, gpa: Allocator, diag: Diagnostic) !void {
        try self.items.append(gpa, diag);
    }

    pub fn hasErrors(self: *const DiagnosticList) bool {
        for (self.items.items) |d| {
            if (d.severity == .err) return true;
        }
        return false;
    }

    pub fn renderAll(self: *const DiagnosticList, sm: *const SourceMap, writer: anytype) !void {
        for (self.items.items) |*d| {
            try d.render(sm, writer);
            try writer.writeByte('\n');
        }
    }
};

test "diag: builder chain" {
    const d = Diagnostic.err("E001", "type mismatch")
        .at(Span.dummy())
        .withHelp("expected Int, got String");

    try std.testing.expectEqual(Severity.err, d.severity);
    try std.testing.expectEqualStrings("E001", d.code);
    try std.testing.expect(d.primary != null);
    try std.testing.expect(d.help != null);
}

test "diag: severity" {
    try std.testing.expectEqualStrings("error", Severity.err.symbol());
    try std.testing.expectEqualStrings("warning", Severity.warn.symbol());
    try std.testing.expectEqualStrings("note", Severity.note.symbol());
}

test "diag: render" {
    const gpa = std.testing.allocator;
    var sm: SourceMap = .empty;
    defer sm.deinit(gpa);

    const src = "let x = true + 1";
    const fid = try sm.addFile(gpa, "test.rz", src);

    const span = Span{ .file = fid, .start = 8, .end = 16 };
    const d = Diagnostic.err("E001", "type mismatch")
        .at(span)
        .withHelp("cannot add Bool and Int");

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    try d.render(&sm, buf.writer(gpa));

    const output = buf.items;
    // Strip ANSI codes for content verification
    // Verify structural elements are present
    try std.testing.expect(std.mem.indexOf(u8, output, "error[E001]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "type mismatch") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test.rz:1:9") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "let x = true + 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "^^^^^^^^") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "help") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "cannot add Bool and Int") != null);
}

test "diag: render with label" {
    const gpa = std.testing.allocator;
    var sm: SourceMap = .empty;
    defer sm.deinit(gpa);

    const src = "let x = foo(bar)";
    const fid = try sm.addFile(gpa, "test.rz", src);

    const primary_span = Span{ .file = fid, .start = 8, .end = 16 };
    const label_span = Span{ .file = fid, .start = 12, .end = 15 };
    const d = try Diagnostic.err("E003", "argument error")
        .at(primary_span)
        .withLabel(gpa, label_span, "this has type String");
    defer gpa.free(d.labels);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    try d.render(&sm, buf.writer(gpa));

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "error[E003]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "argument error") != null);
    // Primary span renders first, then label
    try std.testing.expect(std.mem.indexOf(u8, output, "this has type String") != null);
}

test "diag: render all severities" {
    const gpa = std.testing.allocator;
    var sm: SourceMap = .empty;
    defer sm.deinit(gpa);

    const src = "let x = 1";
    const fid = try sm.addFile(gpa, "test.rz", src);
    const span = Span{ .file = fid, .start = 4, .end = 5 };

    var list: DiagnosticList = .empty;
    defer list.deinit(gpa);

    try list.emit(gpa, Diagnostic.err("E001", "error msg").at(span));
    try list.emit(gpa, Diagnostic.warn("W001", "warn msg").at(span));
    try list.emit(gpa, Diagnostic.note("N001", "note msg").at(span));

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    try list.renderAll(&sm, buf.writer(gpa));

    const output = buf.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "error[E001]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "warning[W001]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "note[N001]") != null);
}

test "diag: list hasErrors" {
    const gpa = std.testing.allocator;
    var list: DiagnosticList = .empty;
    defer list.deinit(gpa);

    try list.emit(gpa, Diagnostic.warn("W001", "unused variable"));
    try std.testing.expect(!list.hasErrors());

    try list.emit(gpa, Diagnostic.err("E001", "type error"));
    try std.testing.expect(list.hasErrors());
}

test "diag: with label" {
    const gpa = std.testing.allocator;
    const d = try Diagnostic.err("E002", "undefined variable")
        .at(Span.dummy())
        .withLabel(gpa, Span.dummy(), "not found in scope");
    defer gpa.free(d.labels);

    try std.testing.expectEqual(@as(usize, 1), d.labels.len);
    try std.testing.expectEqualStrings("not found in scope", d.labels[0].message);
}
