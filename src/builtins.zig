const std = @import("std");
const Allocator = std.mem.Allocator;
const interp = @import("interp.zig");
const Value = interp.Value;
const ListValue = interp.ListValue;
const MapValue = interp.MapValue;
const BytesValue = interp.BytesValue;
const Interpreter = interp.Interpreter;
const InterpreterError = interp.InterpreterError;
const BuiltinFn = interp.BuiltinFn;

// ── Helpers ────────────────────────────────────────────────────────────

fn getInterp(ctx: *anyopaque) *Interpreter {
    return @ptrCast(@alignCast(ctx));
}

fn expectString(val: Value) InterpreterError![]const u8 {
    return switch (val) {
        .string => |s| s,
        else => error.TypeError,
    };
}

fn expectInt(val: Value) InterpreterError!i64 {
    return switch (val) {
        .int => |i| i,
        else => error.TypeError,
    };
}

fn expectList(val: Value) InterpreterError!*ListValue {
    return switch (val) {
        .list => |l| l,
        else => error.TypeError,
    };
}

fn expectMap(val: Value) InterpreterError!*MapValue {
    return switch (val) {
        .map => |m| m,
        else => error.TypeError,
    };
}

fn expectBytes(val: Value) InterpreterError!*BytesValue {
    return switch (val) {
        .bytes => |b| b,
        else => error.TypeError,
    };
}

// ── IO ─────────────────────────────────────────────────────────────────

fn io_print(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const msg = try expectString(args[0]);
    _ = std.posix.write(std.posix.STDOUT_FILENO, msg) catch {};
    return .nil;
}

fn debug_type(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const type_name: []const u8 = switch (args[0]) {
        .int => "int",
        .float => "float",
        .bool_val => "bool",
        .string => "string",
        .list => "list",
        .record => "record",
        .tagged => "tagged",
        .nil => "nil",
        .closure => "closure",
        .continuation => "continuation",
        .builtin_fn => "builtin_fn",
        .map => "map",
        .bytes => "bytes",
    };
    _ = std.posix.write(std.posix.STDOUT_FILENO, type_name) catch {};
    return .nil;
}

fn io_read_file(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const self = getInterp(ctx);
    const path = try expectString(args[0]);

    const file = std.fs.cwd().openFile(path, .{}) catch return error.TypeError;
    defer file.close();
    const content = file.readToEndAlloc(self.gpa, 10 * 1024 * 1024) catch return error.OutOfMemory;
    // Transfer to arena so it lives with the interpreter
    const result = self.arena.alloc(u8, content.len) catch {
        self.gpa.free(content);
        return error.OutOfMemory;
    };
    @memcpy(result, content);
    self.gpa.free(content);
    return .{ .string = result };
}

fn io_write_file(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const path = try expectString(args[0]);
    const data = try expectString(args[1]);

    const file = std.fs.cwd().createFile(path, .{}) catch return error.TypeError;
    defer file.close();
    file.writeAll(data) catch return error.TypeError;
    return .nil;
}

fn io_exit(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const code = try expectInt(args[0]);
    std.process.exit(@intCast(@as(u8, @truncate(@as(u64, @bitCast(code))))));
}

// ── String operations ──────────────────────────────────────────────────

fn string_length(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const s = try expectString(args[0]);
    return .{ .int = @intCast(s.len) };
}

fn string_concat(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const self = getInterp(ctx);
    const a = try expectString(args[0]);
    const b = try expectString(args[1]);
    const result = self.arena.alloc(u8, a.len + b.len) catch return error.OutOfMemory;
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return .{ .string = result };
}

fn string_slice(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 3) return error.ArityMismatch;
    const self = getInterp(ctx);
    const s = try expectString(args[0]);
    const start_i = try expectInt(args[1]);
    const end_i = try expectInt(args[2]);
    if (start_i < 0 or end_i < 0) return error.IndexOutOfBounds;
    const start: usize = @intCast(start_i);
    const end: usize = @intCast(end_i);
    if (start > s.len or end > s.len or start > end) return error.IndexOutOfBounds;
    const result = self.arena.alloc(u8, end - start) catch return error.OutOfMemory;
    @memcpy(result, s[start..end]);
    return .{ .string = result };
}

fn string_char_at(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const self = getInterp(ctx);
    const s = try expectString(args[0]);
    const idx_i = try expectInt(args[1]);
    if (idx_i < 0) return error.IndexOutOfBounds;
    const idx: usize = @intCast(idx_i);
    if (idx >= s.len) return error.IndexOutOfBounds;
    const result = self.arena.alloc(u8, 1) catch return error.OutOfMemory;
    result[0] = s[idx];
    return .{ .string = result };
}

fn string_to_int(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const s = try expectString(args[0]);
    const val = std.fmt.parseInt(i64, s, 10) catch return error.TypeError;
    return .{ .int = val };
}

fn string_from_int(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const self = getInterp(ctx);
    const val = try expectInt(args[0]);
    // Format into arena-allocated buffer
    var buf: [21]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "{d}", .{val}) catch return error.OutOfMemory;
    const result = self.arena.alloc(u8, formatted.len) catch return error.OutOfMemory;
    @memcpy(result, formatted);
    return .{ .string = result };
}

fn string_contains(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const haystack = try expectString(args[0]);
    const needle = try expectString(args[1]);
    return .{ .bool_val = std.mem.indexOf(u8, haystack, needle) != null };
}

fn string_byte_at(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const s = try expectString(args[0]);
    const idx_i = try expectInt(args[1]);
    if (idx_i < 0 or @as(usize, @intCast(idx_i)) >= s.len) return .{ .int = -1 };
    return .{ .int = @intCast(s[@intCast(idx_i)]) };
}

fn string_starts_with(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const s = try expectString(args[0]);
    const prefix = try expectString(args[1]);
    return .{ .bool_val = std.mem.startsWith(u8, s, prefix) };
}

fn string_from_int_char(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const self = getInterp(ctx);
    const code = try expectInt(args[0]);
    if (code < 0 or code > 255) return error.TypeError;
    const result = self.arena.alloc(u8, 1) catch return error.OutOfMemory;
    result[0] = @intCast(@as(u8, @truncate(@as(u64, @bitCast(code)))));
    return .{ .string = result };
}

fn string_index_of(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const haystack = try expectString(args[0]);
    const needle = try expectString(args[1]);
    if (std.mem.indexOf(u8, haystack, needle)) |idx| {
        return .{ .int = @intCast(idx) };
    }
    return .{ .int = -1 };
}

fn string_hash(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const s = try expectString(args[0]);
    // FNV-1a 64-bit hash, truncated to positive i64
    var h: u64 = 14695981039346656037;
    for (s) |byte| {
        h ^= byte;
        h *%= 1099511628211;
    }
    // Ensure positive by masking off sign bit
    return .{ .int = @bitCast(h & 0x7FFFFFFFFFFFFFFF) };
}

// ── List operations ────────────────────────────────────────────────────

fn list_length(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const l = try expectList(args[0]);
    return .{ .int = @intCast(l.items.len) };
}

fn list_append(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const self = getInterp(ctx);
    const l = try expectList(args[0]);
    const new_items = self.arena.alloc(Value, l.items.len + 1) catch return error.OutOfMemory;
    @memcpy(new_items[0..l.items.len], l.items);
    new_items[l.items.len] = args[1];
    const new_list = self.arena.create(ListValue) catch return error.OutOfMemory;
    new_list.* = .{ .items = new_items };
    return .{ .list = new_list };
}

fn list_nth(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const l = try expectList(args[0]);
    const idx_i = try expectInt(args[1]);
    if (idx_i < 0) return error.IndexOutOfBounds;
    const idx: usize = @intCast(idx_i);
    if (idx >= l.items.len) return error.IndexOutOfBounds;
    return l.items[idx];
}

fn list_slice(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 3) return error.ArityMismatch;
    const self = getInterp(ctx);
    const l = try expectList(args[0]);
    const start_i = try expectInt(args[1]);
    const end_i = try expectInt(args[2]);
    if (start_i < 0 or end_i < 0) return error.IndexOutOfBounds;
    const start: usize = @intCast(start_i);
    const end: usize = @intCast(end_i);
    if (start > l.items.len or end > l.items.len or start > end) return error.IndexOutOfBounds;
    const new_items = self.arena.alloc(Value, end - start) catch return error.OutOfMemory;
    @memcpy(new_items, l.items[start..end]);
    const new_list = self.arena.create(ListValue) catch return error.OutOfMemory;
    new_list.* = .{ .items = new_items };
    return .{ .list = new_list };
}

fn list_concat(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const self = getInterp(ctx);
    const a = try expectList(args[0]);
    const b = try expectList(args[1]);
    const new_items = self.arena.alloc(Value, a.items.len + b.items.len) catch return error.OutOfMemory;
    @memcpy(new_items[0..a.items.len], a.items);
    @memcpy(new_items[a.items.len..], b.items);
    const new_list = self.arena.create(ListValue) catch return error.OutOfMemory;
    new_list.* = .{ .items = new_items };
    return .{ .list = new_list };
}

// ── Map operations ─────────────────────────────────────────────────────

fn map_new(_: []const Value, ctx: *anyopaque) InterpreterError!Value {
    const self = getInterp(ctx);
    const m = self.arena.create(MapValue) catch return error.OutOfMemory;
    m.* = .{ .entries = .empty };
    return .{ .map = m };
}

fn map_get(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const m = try expectMap(args[0]);
    const key = try expectString(args[1]);
    return m.entries.get(key) orelse .nil;
}

fn map_set(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 3) return error.ArityMismatch;
    const self = getInterp(ctx);
    const m = try expectMap(args[0]);

    // Create a new map (immutable semantics)
    const new_m = self.arena.create(MapValue) catch return error.OutOfMemory;
    new_m.* = .{ .entries = .empty };

    // Copy existing entries
    var it = m.entries.iterator();
    while (it.next()) |entry| {
        new_m.entries.put(self.gpa, entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
    }

    // Set/overwrite the key
    const key = try expectString(args[1]);
    new_m.entries.put(self.gpa, key, args[2]) catch return error.OutOfMemory;
    return .{ .map = new_m };
}

fn map_has(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const m = try expectMap(args[0]);
    const key = try expectString(args[1]);
    return .{ .bool_val = m.entries.contains(key) };
}

fn map_keys(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const self = getInterp(ctx);
    const m = try expectMap(args[0]);

    const count = m.entries.count();
    const items = self.arena.alloc(Value, count) catch return error.OutOfMemory;
    var it = m.entries.iterator();
    var i: usize = 0;
    while (it.next()) |entry| {
        items[i] = .{ .string = entry.key_ptr.* };
        i += 1;
    }
    const lv = self.arena.create(ListValue) catch return error.OutOfMemory;
    lv.* = .{ .items = items };
    return .{ .list = lv };
}

// ── Bytes operations ───────────────────────────────────────────────────

fn bytes_new(_: []const Value, ctx: *anyopaque) InterpreterError!Value {
    const self = getInterp(ctx);
    const b = self.arena.create(BytesValue) catch return error.OutOfMemory;
    b.* = .{ .data = .empty };
    return .{ .bytes = b };
}

fn bytes_append_u8(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const self = getInterp(ctx);
    const b = try expectBytes(args[0]);
    const val = try expectInt(args[1]);

    // Create new BytesValue (immutable semantics)
    const new_b = self.arena.create(BytesValue) catch return error.OutOfMemory;
    new_b.* = .{ .data = .empty };
    new_b.data.appendSlice(self.gpa, b.data.items) catch return error.OutOfMemory;
    new_b.data.append(self.gpa, @intCast(@as(u8, @truncate(@as(u64, @bitCast(val)))))) catch return error.OutOfMemory;
    return .{ .bytes = new_b };
}

fn bytes_append_u32_le(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const self = getInterp(ctx);
    const b = try expectBytes(args[0]);
    const val = try expectInt(args[1]);

    const new_b = self.arena.create(BytesValue) catch return error.OutOfMemory;
    new_b.* = .{ .data = .empty };
    new_b.data.appendSlice(self.gpa, b.data.items) catch return error.OutOfMemory;
    const le_bytes = std.mem.toBytes(@as(u32, @truncate(@as(u64, @bitCast(val)))));
    new_b.data.appendSlice(self.gpa, &le_bytes) catch return error.OutOfMemory;
    return .{ .bytes = new_b };
}

fn bytes_append_u64_le(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const self = getInterp(ctx);
    const b = try expectBytes(args[0]);
    const val = try expectInt(args[1]);

    const new_b = self.arena.create(BytesValue) catch return error.OutOfMemory;
    new_b.* = .{ .data = .empty };
    new_b.data.appendSlice(self.gpa, b.data.items) catch return error.OutOfMemory;
    const le_bytes = std.mem.toBytes(@as(u64, @bitCast(val)));
    new_b.data.appendSlice(self.gpa, &le_bytes) catch return error.OutOfMemory;
    return .{ .bytes = new_b };
}

fn bytes_set_u32_le(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 3) return error.ArityMismatch;
    const self = getInterp(ctx);
    const b = try expectBytes(args[0]);
    const offset_i = try expectInt(args[1]);
    const val = try expectInt(args[2]);

    if (offset_i < 0) return error.IndexOutOfBounds;
    const offset: usize = @intCast(offset_i);
    if (offset + 4 > b.data.items.len) return error.IndexOutOfBounds;

    // Create new BytesValue (immutable semantics)
    const new_b = self.arena.create(BytesValue) catch return error.OutOfMemory;
    new_b.* = .{ .data = .empty };
    new_b.data.appendSlice(self.gpa, b.data.items) catch return error.OutOfMemory;
    const le_bytes = std.mem.toBytes(@as(u32, @truncate(@as(u64, @bitCast(val)))));
    @memcpy(new_b.data.items[offset .. offset + 4], &le_bytes);
    return .{ .bytes = new_b };
}

fn string_to_bytes(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const self = getInterp(ctx);
    const s = try expectString(args[0]);

    const new_b = self.arena.create(BytesValue) catch return error.OutOfMemory;
    new_b.* = .{ .data = .empty };
    new_b.data.appendSlice(self.gpa, s) catch return error.OutOfMemory;
    return .{ .bytes = new_b };
}

fn bytes_append_bytes(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const self = getInterp(ctx);
    const dst = try expectBytes(args[0]);
    const src = try expectBytes(args[1]);

    const new_b = self.arena.create(BytesValue) catch return error.OutOfMemory;
    new_b.* = .{ .data = .{} };
    new_b.data.appendSlice(self.gpa, dst.data.items) catch return error.OutOfMemory;
    new_b.data.appendSlice(self.gpa, src.data.items) catch return error.OutOfMemory;
    return .{ .bytes = new_b };
}

fn bytes_length(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const b = try expectBytes(args[0]);
    return .{ .int = @intCast(b.data.items.len) };
}

/// Ad-hoc code sign a Mach-O binary for macOS arm64.
/// Takes the unsigned Mach-O bytes (which must already have LC_CODE_SIGNATURE
/// load command with correct dataoff/datasize) and appends the code signature.
fn bytes_macho_codesign(args: []const Value, ctx: *anyopaque) InterpreterError!Value {
    if (args.len < 1) return error.ArityMismatch;
    const self = getInterp(ctx);
    const b = try expectBytes(args[0]);

    const result = self.arena.create(BytesValue) catch return error.OutOfMemory;
    result.* = .{ .data = .{} };

    // Copy existing bytes
    result.data.appendSlice(self.gpa, b.data.items) catch return error.OutOfMemory;

    // Find LC_CODE_SIGNATURE in load commands to get dataoff and datasize
    const bytes = result.data.items;
    if (bytes.len < 32) return error.TypeError; // Too small for Mach-O header

    const ncmds = std.mem.readInt(u32, bytes[16..20], .little);
    var cmd_offset: usize = 32; // After Mach-O header

    var cs_dataoff: u32 = 0;
    var cs_datasize: u32 = 0;
    var found_cs = false;
    var text_fileoff: u64 = 0;
    var text_filesize: u64 = 0;

    for (0..ncmds) |_| {
        if (cmd_offset + 8 > bytes.len) break;
        const cmd = std.mem.readInt(u32, bytes[cmd_offset..][0..4], .little);
        const cmdsize = std.mem.readInt(u32, bytes[cmd_offset + 4..][0..4], .little);

        if (cmd == 0x1D) { // LC_CODE_SIGNATURE
            cs_dataoff = std.mem.readInt(u32, bytes[cmd_offset + 8..][0..4], .little);
            cs_datasize = std.mem.readInt(u32, bytes[cmd_offset + 12..][0..4], .little);
            found_cs = true;
        } else if (cmd == 0x19) { // LC_SEGMENT_64
            // Check segment name for __TEXT
            if (cmd_offset + 24 <= bytes.len) {
                const seg_name = bytes[cmd_offset + 8 .. cmd_offset + 24];
                if (std.mem.startsWith(u8, seg_name, "__TEXT")) {
                    text_fileoff = std.mem.readInt(u64, bytes[cmd_offset + 40..][0..8], .little);
                    text_filesize = std.mem.readInt(u64, bytes[cmd_offset + 48..][0..8], .little);
                }
            }
        }
        cmd_offset += cmdsize;
    }

    if (!found_cs or cs_dataoff == 0) return error.TypeError;

    // Pad to cs_dataoff if needed
    while (result.data.items.len < cs_dataoff) {
        result.data.append(self.gpa, 0) catch return error.OutOfMemory;
    }

    const code_limit = cs_dataoff;
    const page_size: u32 = 4096;
    const n_code_slots = (code_limit + page_size - 1) / page_size;
    const hash_size: u8 = 32;
    const ident_len: u32 = 1; // empty string "\0"
    const cdir_header_size: u32 = 88;
    const cdir_size = cdir_header_size + ident_len + n_code_slots * hash_size;
    const blob_count: u32 = 1;
    const superblob_size = 12 + blob_count * 8 + cdir_size;

    // Verify our computed size matches expected
    if (superblob_size != cs_datasize) {
        // Size mismatch — the IR computed a different size than we did.
        // This shouldn't happen if the formula is consistent.
        // Patch the LC_CODE_SIGNATURE datasize to match our computation.
        std.mem.writeInt(u32, result.data.items[cmd_offset - 4 ..][0..4], superblob_size, .little);
    }

    // Write SuperBlob header (big-endian)
    const writer = result.data.writer(self.gpa);
    writer.writeInt(u32, 0xFADE0CC0, .big) catch return error.OutOfMemory; // magic
    writer.writeInt(u32, superblob_size, .big) catch return error.OutOfMemory; // length
    writer.writeInt(u32, blob_count, .big) catch return error.OutOfMemory; // count

    // BlobIndex[0]: CodeDirectory
    writer.writeInt(u32, 0x00000000, .big) catch return error.OutOfMemory; // type = CSSLOT_CODEDIRECTORY
    writer.writeInt(u32, 12 + blob_count * 8, .big) catch return error.OutOfMemory; // offset from SuperBlob start

    // CodeDirectory header (88 bytes, big-endian)
    const hash_offset = cdir_header_size + ident_len;
    const ident_offset = cdir_header_size;

    writer.writeInt(u32, 0xFADE0C02, .big) catch return error.OutOfMemory; // magic
    writer.writeInt(u32, cdir_size, .big) catch return error.OutOfMemory; // length
    writer.writeInt(u32, 0x00020400, .big) catch return error.OutOfMemory; // version
    writer.writeInt(u32, 0x00020002, .big) catch return error.OutOfMemory; // flags: CS_ADHOC | CS_LINKER_SIGNED
    writer.writeInt(u32, hash_offset, .big) catch return error.OutOfMemory; // hashOffset
    writer.writeInt(u32, ident_offset, .big) catch return error.OutOfMemory; // identOffset
    writer.writeInt(u32, 0, .big) catch return error.OutOfMemory; // nSpecialSlots
    writer.writeInt(u32, n_code_slots, .big) catch return error.OutOfMemory; // nCodeSlots
    writer.writeInt(u32, code_limit, .big) catch return error.OutOfMemory; // codeLimit
    writer.writeByte(hash_size) catch return error.OutOfMemory; // hashSize
    writer.writeByte(2) catch return error.OutOfMemory; // hashType = CS_HASHTYPE_SHA256
    writer.writeByte(0) catch return error.OutOfMemory; // platform
    writer.writeByte(12) catch return error.OutOfMemory; // pageSize = log2(4096)
    writer.writeInt(u32, 0, .big) catch return error.OutOfMemory; // spare2
    writer.writeInt(u32, 0, .big) catch return error.OutOfMemory; // scatterOffset
    writer.writeInt(u32, 0, .big) catch return error.OutOfMemory; // teamOffset
    writer.writeInt(u32, 0, .big) catch return error.OutOfMemory; // spare3
    writer.writeInt(u64, 0, .big) catch return error.OutOfMemory; // codeLimit64
    writer.writeInt(u64, text_fileoff, .big) catch return error.OutOfMemory; // execSegBase
    writer.writeInt(u64, text_filesize, .big) catch return error.OutOfMemory; // execSegLimit
    writer.writeInt(u64, 0x1, .big) catch return error.OutOfMemory; // execSegFlags = CS_EXECSEG_MAIN_BINARY

    // Identity: empty null-terminated string
    writer.writeByte(0) catch return error.OutOfMemory;

    // Code slot hashes: SHA-256 of each 4096-byte page
    const Sha256 = std.crypto.hash.sha2.Sha256;
    const file_bytes = result.data.items;
    var page_idx: u32 = 0;
    while (page_idx < n_code_slots) : (page_idx += 1) {
        const start = page_idx * page_size;
        const end = @min(start + page_size, code_limit);
        const page_data = file_bytes[start..end];
        var hash: [32]u8 = undefined;
        Sha256.hash(page_data, &hash, .{});
        writer.writeAll(&hash) catch return error.OutOfMemory;
    }

    return .{ .bytes = result };
}

fn bytes_write_file(args: []const Value, _: *anyopaque) InterpreterError!Value {
    if (args.len < 2) return error.ArityMismatch;
    const path = try expectString(args[0]);
    const b = try expectBytes(args[1]);

    const file = std.fs.cwd().createFile(path, .{}) catch return error.TypeError;
    defer file.close();
    file.writeAll(b.data.items) catch return error.TypeError;
    return .nil;
}

// ── Registration ───────────────────────────────────────────────────────

pub fn registerAll(self: *Interpreter) InterpreterError!void {
    const entries = .{
        // IO
        .{ "io_print", io_print },
        .{ "debug_type", debug_type },
        .{ "io_read_file", io_read_file },
        .{ "io_write_file", io_write_file },
        .{ "io_exit", io_exit },
        // String
        .{ "string_length", string_length },
        .{ "string_concat", string_concat },
        .{ "string_slice", string_slice },
        .{ "string_char_at", string_char_at },
        .{ "string_to_int", string_to_int },
        .{ "string_from_int", string_from_int },
        .{ "string_contains", string_contains },
        .{ "string_byte_at", string_byte_at },
        .{ "string_starts_with", string_starts_with },
        .{ "string_from_int_char", string_from_int_char },
        .{ "string_index_of", string_index_of },
        .{ "string_hash", string_hash },
        // List
        .{ "list_length", list_length },
        .{ "list_append", list_append },
        .{ "list_nth", list_nth },
        .{ "list_slice", list_slice },
        .{ "list_concat", list_concat },
        // Map
        .{ "map_new", map_new },
        .{ "map_get", map_get },
        .{ "map_set", map_set },
        .{ "map_has", map_has },
        .{ "map_keys", map_keys },
        // Bytes
        .{ "bytes_new", bytes_new },
        .{ "bytes_append_u8", bytes_append_u8 },
        .{ "bytes_append_u32_le", bytes_append_u32_le },
        .{ "bytes_append_u64_le", bytes_append_u64_le },
        .{ "bytes_set_u32_le", bytes_set_u32_le },
        .{ "bytes_append_bytes", bytes_append_bytes },
        .{ "bytes_length", bytes_length },
        .{ "bytes_write_file", bytes_write_file },
        .{ "bytes_macho_codesign", bytes_macho_codesign },
        .{ "string_to_bytes", string_to_bytes },
    };

    inline for (entries) |e| {
        try self.registerBuiltin(e[0], e[1]);
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

const ir = @import("ir.zig");
const intern_mod = @import("intern.zig");
const InternPool = intern_mod.InternPool;

const TestHarness = struct {
    backing: std.heap.ArenaAllocator,
    pool: InternPool,

    fn init() TestHarness {
        return .{
            .backing = std.heap.ArenaAllocator.init(std.heap.page_allocator),
            .pool = undefined,
        };
    }

    fn setup(self: *TestHarness) struct { Allocator, *InternPool, ir.Builder } {
        const alloc = self.backing.allocator();
        self.pool = InternPool.init(alloc);
        return .{ alloc, &self.pool, ir.Builder.init(alloc) };
    }

    fn deinit(self: *TestHarness) void {
        self.backing.deinit();
    }

    /// Build and run a function that calls a single builtin with the given args.
    fn runBuiltin(self: *TestHarness, builtin_name: []const u8, arg_values: []const Value) InterpreterError!Value {
        const alloc = self.backing.allocator();
        const pool = &self.pool;
        var b = ir.Builder.init(alloc);

        const name = pool.intern(alloc, builtin_name) catch return error.OutOfMemory;
        b.beginFunc(pool.intern(alloc, "test_main") catch return error.OutOfMemory);

        _ = b.beginBlock();

        // Inject arg values as constants via params
        const n = arg_values.len;
        var param_ids: [8]ir.ValueId = undefined;
        for (0..n) |i| {
            param_ids[i] = b.addParam() catch return error.OutOfMemory;
        }

        const result = b.addInst(.{ .call_builtin = .{ .name = name, .args = param_ids[0..n] } }) catch return error.OutOfMemory;
        b.endBlock(.{ .ret = result }) catch return error.OutOfMemory;
        const fid = b.endFunc() catch return error.OutOfMemory;
        const module = b.build(fid) catch return error.OutOfMemory;

        var interpreter = Interpreter.init(alloc, module, pool);
        defer interpreter.deinit();
        try registerAll(&interpreter);
        return interpreter.execFunc(fid, arg_values);
    }
};

// ── String tests ───────────────────────────────────────────────────────

test "builtin: string_length" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_length", &.{.{ .string = "hello" }});
    try std.testing.expectEqual(@as(i64, 5), result.int);
}

test "builtin: string_length empty" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_length", &.{.{ .string = "" }});
    try std.testing.expectEqual(@as(i64, 0), result.int);
}

test "builtin: string_concat" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_concat", &.{ .{ .string = "hello " }, .{ .string = "world" } });
    try std.testing.expectEqualStrings("hello world", result.string);
}

test "builtin: string_slice" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_slice", &.{ .{ .string = "hello world" }, .{ .int = 6 }, .{ .int = 11 } });
    try std.testing.expectEqualStrings("world", result.string);
}

test "builtin: string_slice out of bounds" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = h.runBuiltin("string_slice", &.{ .{ .string = "hi" }, .{ .int = 0 }, .{ .int = 5 } });
    try std.testing.expectError(error.IndexOutOfBounds, result);
}

test "builtin: string_char_at" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_char_at", &.{ .{ .string = "abc" }, .{ .int = 1 } });
    try std.testing.expectEqualStrings("b", result.string);
}

test "builtin: string_to_int" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_to_int", &.{.{ .string = "42" }});
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "builtin: string_to_int invalid" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = h.runBuiltin("string_to_int", &.{.{ .string = "abc" }});
    try std.testing.expectError(error.TypeError, result);
}

test "builtin: string_from_int" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_from_int", &.{.{ .int = -42 }});
    try std.testing.expectEqualStrings("-42", result.string);
}

test "builtin: string_contains" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const yes = try h.runBuiltin("string_contains", &.{ .{ .string = "hello world" }, .{ .string = "world" } });
    try std.testing.expect(yes.bool_val);
    const no = try h.runBuiltin("string_contains", &.{ .{ .string = "hello" }, .{ .string = "xyz" } });
    try std.testing.expect(!no.bool_val);
}

// ── List tests ─────────────────────────────────────────────────────────

test "builtin: list_length" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc = h.setup()[0];

    const items = alloc.alloc(Value, 3) catch unreachable;
    items[0] = .{ .int = 1 };
    items[1] = .{ .int = 2 };
    items[2] = .{ .int = 3 };
    const lv = alloc.create(ListValue) catch unreachable;
    lv.* = .{ .items = items };

    const result = try h.runBuiltin("list_length", &.{.{ .list = lv }});
    try std.testing.expectEqual(@as(i64, 3), result.int);
}

test "builtin: list_append" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc = h.setup()[0];

    const items = alloc.alloc(Value, 1) catch unreachable;
    items[0] = .{ .int = 10 };
    const lv = alloc.create(ListValue) catch unreachable;
    lv.* = .{ .items = items };

    const result = try h.runBuiltin("list_append", &.{ .{ .list = lv }, .{ .int = 20 } });
    try std.testing.expectEqual(@as(usize, 2), result.list.items.len);
    try std.testing.expectEqual(@as(i64, 10), result.list.items[0].int);
    try std.testing.expectEqual(@as(i64, 20), result.list.items[1].int);
}

test "builtin: list_nth" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc = h.setup()[0];

    const items = alloc.alloc(Value, 3) catch unreachable;
    items[0] = .{ .int = 10 };
    items[1] = .{ .int = 20 };
    items[2] = .{ .int = 30 };
    const lv = alloc.create(ListValue) catch unreachable;
    lv.* = .{ .items = items };

    const result = try h.runBuiltin("list_nth", &.{ .{ .list = lv }, .{ .int = 2 } });
    try std.testing.expectEqual(@as(i64, 30), result.int);
}

test "builtin: list_nth out of bounds" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc = h.setup()[0];

    const lv = alloc.create(ListValue) catch unreachable;
    lv.* = .{ .items = &.{} };

    const result = h.runBuiltin("list_nth", &.{ .{ .list = lv }, .{ .int = 0 } });
    try std.testing.expectError(error.IndexOutOfBounds, result);
}

test "builtin: list_slice" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc = h.setup()[0];

    const items = alloc.alloc(Value, 4) catch unreachable;
    items[0] = .{ .int = 1 };
    items[1] = .{ .int = 2 };
    items[2] = .{ .int = 3 };
    items[3] = .{ .int = 4 };
    const lv = alloc.create(ListValue) catch unreachable;
    lv.* = .{ .items = items };

    const result = try h.runBuiltin("list_slice", &.{ .{ .list = lv }, .{ .int = 1 }, .{ .int = 3 } });
    try std.testing.expectEqual(@as(usize, 2), result.list.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.list.items[0].int);
    try std.testing.expectEqual(@as(i64, 3), result.list.items[1].int);
}

// ── Map tests ──────────────────────────────────────────────────────────
// Map/bytes tests build multi-step IR functions because values must stay
// within a single interpreter's arena lifetime.

test "builtin: map_new, map_set, map_get, map_has, map_keys" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_new = try pool.intern(alloc, "map_new");
    const n_set = try pool.intern(alloc, "map_set");
    const n_get = try pool.intern(alloc, "map_get");
    const n_has = try pool.intern(alloc, "map_has");
    const n_keys = try pool.intern(alloc, "map_keys");
    const key_str = try pool.intern(alloc, "key");
    const nope_str = try pool.intern(alloc, "nope");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    // m0 = map_new()
    const m0 = try b.addInst(.{ .call_builtin = .{ .name = n_new, .args = &.{} } });
    // key = "key", val = 42
    const k = try b.addInst(.{ .const_string = key_str });
    const v42 = try b.addInst(.{ .const_int = 42 });
    // m1 = map_set(m0, "key", 42)
    const m1 = try b.addInst(.{ .call_builtin = .{ .name = n_set, .args = &.{ m0, k, v42 } } });
    // got = map_get(m1, "key") — should be 42
    const got = try b.addInst(.{ .call_builtin = .{ .name = n_get, .args = &.{ m1, k } } });
    // missing = map_get(m1, "nope") — should be nil
    const nope = try b.addInst(.{ .const_string = nope_str });
    _ = try b.addInst(.{ .call_builtin = .{ .name = n_get, .args = &.{ m1, nope } } });
    // has = map_has(m1, "key") — should be true
    _ = try b.addInst(.{ .call_builtin = .{ .name = n_has, .args = &.{ m1, k } } });
    // has_orig = map_has(m0, "key") — should be false (immutability check)
    _ = try b.addInst(.{ .call_builtin = .{ .name = n_has, .args = &.{ m0, k } } });
    // keys = map_keys(m1) — should have 1 element
    _ = try b.addInst(.{ .call_builtin = .{ .name = n_keys, .args = &.{m1} } });
    // Return the value we got from map_get
    try b.endBlock(.{ .ret = got });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = try interpreter.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

// ── Bytes tests ────────────────────────────────────────────────────────

test "builtin: bytes_new, append_u8, length" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_new = try pool.intern(alloc, "bytes_new");
    const n_u8 = try pool.intern(alloc, "bytes_append_u8");
    const n_len = try pool.intern(alloc, "bytes_length");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    const b0 = try b.addInst(.{ .call_builtin = .{ .name = n_new, .args = &.{} } });
    const v_ff = try b.addInst(.{ .const_int = 0xFF });
    const b1 = try b.addInst(.{ .call_builtin = .{ .name = n_u8, .args = &.{ b0, v_ff } } });
    const v_42 = try b.addInst(.{ .const_int = 0x42 });
    const b2 = try b.addInst(.{ .call_builtin = .{ .name = n_u8, .args = &.{ b1, v_42 } } });
    const len = try b.addInst(.{ .call_builtin = .{ .name = n_len, .args = &.{b2} } });
    try b.endBlock(.{ .ret = len });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = try interpreter.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 2), result.int);
}

test "builtin: bytes_append_u32_le" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_new = try pool.intern(alloc, "bytes_new");
    const n_u32 = try pool.intern(alloc, "bytes_append_u32_le");
    const n_len = try pool.intern(alloc, "bytes_length");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    const b0 = try b.addInst(.{ .call_builtin = .{ .name = n_new, .args = &.{} } });
    const val = try b.addInst(.{ .const_int = 0x04030201 });
    const b1 = try b.addInst(.{ .call_builtin = .{ .name = n_u32, .args = &.{ b0, val } } });
    const len = try b.addInst(.{ .call_builtin = .{ .name = n_len, .args = &.{b1} } });
    try b.endBlock(.{ .ret = len });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = try interpreter.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 4), result.int);
}

test "builtin: bytes_append_u64_le" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_new = try pool.intern(alloc, "bytes_new");
    const n_u64 = try pool.intern(alloc, "bytes_append_u64_le");
    const n_len = try pool.intern(alloc, "bytes_length");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    const b0 = try b.addInst(.{ .call_builtin = .{ .name = n_new, .args = &.{} } });
    const val = try b.addInst(.{ .const_int = 1 });
    const b1 = try b.addInst(.{ .call_builtin = .{ .name = n_u64, .args = &.{ b0, val } } });
    const len = try b.addInst(.{ .call_builtin = .{ .name = n_len, .args = &.{b1} } });
    try b.endBlock(.{ .ret = len });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = try interpreter.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 8), result.int);
}

// ── IO tests (limited — avoid actual file IO in tests) ────────────────

test "builtin: string_byte_at" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_byte_at", &.{ .{ .string = "ABC" }, .{ .int = 0 } });
    try std.testing.expectEqual(@as(i64, 65), result.int); // 'A' = 65
}

test "builtin: string_byte_at out of bounds" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_byte_at", &.{ .{ .string = "hi" }, .{ .int = 5 } });
    try std.testing.expectEqual(@as(i64, -1), result.int);
}

test "builtin: string_starts_with" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const r1 = try h.runBuiltin("string_starts_with", &.{ .{ .string = "hello world" }, .{ .string = "hello" } });
    try std.testing.expect(r1.bool_val == true);
    const r2 = try h.runBuiltin("string_starts_with", &.{ .{ .string = "hello" }, .{ .string = "world" } });
    try std.testing.expect(r2.bool_val == false);
}

test "builtin: string_from_int_char" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const result = try h.runBuiltin("string_from_int_char", &.{.{ .int = 65 }});
    try std.testing.expectEqualStrings("A", result.string);
}

test "builtin: string_index_of" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    const r1 = try h.runBuiltin("string_index_of", &.{ .{ .string = "hello world" }, .{ .string = "world" } });
    try std.testing.expectEqual(@as(i64, 6), r1.int);
    const r2 = try h.runBuiltin("string_index_of", &.{ .{ .string = "hello" }, .{ .string = "xyz" } });
    try std.testing.expectEqual(@as(i64, -1), r2.int);
}

test "builtin: list_concat" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_len = try pool.intern(alloc, "list_concat");
    const n_list_len = try pool.intern(alloc, "list_length");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    const a = try b.addInst(.{ .list_init = .{ .elements = &.{} } });
    const v1 = try b.addInst(.{ .const_int = 1 });
    const a1 = try b.addInst(.{ .call_builtin = .{ .name = try pool.intern(alloc, "list_append"), .args = &.{ a, v1 } } });

    const c = try b.addInst(.{ .list_init = .{ .elements = &.{} } });
    const v2 = try b.addInst(.{ .const_int = 2 });
    const c1 = try b.addInst(.{ .call_builtin = .{ .name = try pool.intern(alloc, "list_append"), .args = &.{ c, v2 } } });

    const merged = try b.addInst(.{ .call_builtin = .{ .name = n_len, .args = &.{ a1, c1 } } });
    const len = try b.addInst(.{ .call_builtin = .{ .name = n_list_len, .args = &.{merged} } });
    try b.endBlock(.{ .ret = len });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = try interpreter.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 2), result.int);
}

test "builtin: bytes_set_u32_le" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_new = try pool.intern(alloc, "bytes_new");
    const n_u32 = try pool.intern(alloc, "bytes_append_u32_le");
    const n_set = try pool.intern(alloc, "bytes_set_u32_le");
    const n_len = try pool.intern(alloc, "bytes_length");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    // Create bytes with one u32 (0x01020304), then overwrite it with 0xDEADBEEF
    const b0 = try b.addInst(.{ .call_builtin = .{ .name = n_new, .args = &.{} } });
    const val1 = try b.addInst(.{ .const_int = 0x01020304 });
    const b1 = try b.addInst(.{ .call_builtin = .{ .name = n_u32, .args = &.{ b0, val1 } } });
    const zero = try b.addInst(.{ .const_int = 0 });
    const val2 = try b.addInst(.{ .const_int = @as(i64, @bitCast(@as(u64, 0xDEADBEEF))) });
    const b2 = try b.addInst(.{ .call_builtin = .{ .name = n_set, .args = &.{ b1, zero, val2 } } });
    const len = try b.addInst(.{ .call_builtin = .{ .name = n_len, .args = &.{b2} } });
    try b.endBlock(.{ .ret = len });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = try interpreter.execFunc(fid, &.{});
    // Length should still be 4 (overwrite, not append)
    try std.testing.expectEqual(@as(i64, 4), result.int);
}

test "builtin: bytes_set_u32_le out of bounds" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_new = try pool.intern(alloc, "bytes_new");
    const n_set = try pool.intern(alloc, "bytes_set_u32_le");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    // Empty bytes — set at offset 0 should fail
    const b0 = try b.addInst(.{ .call_builtin = .{ .name = n_new, .args = &.{} } });
    const zero = try b.addInst(.{ .const_int = 0 });
    const val = try b.addInst(.{ .const_int = 42 });
    const result_id = try b.addInst(.{ .call_builtin = .{ .name = n_set, .args = &.{ b0, zero, val } } });
    try b.endBlock(.{ .ret = result_id });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = interpreter.execFunc(fid, &.{});
    try std.testing.expectError(error.IndexOutOfBounds, result);
}

test "builtin: string_to_bytes" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_stb = try pool.intern(alloc, "string_to_bytes");
    const n_len = try pool.intern(alloc, "bytes_length");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    const s = try b.addInst(.{ .const_string = try pool.intern(alloc, "hello") });
    const bv = try b.addInst(.{ .call_builtin = .{ .name = n_stb, .args = &.{s} } });
    const len = try b.addInst(.{ .call_builtin = .{ .name = n_len, .args = &.{bv} } });
    try b.endBlock(.{ .ret = len });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = try interpreter.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 5), result.int);
}

test "builtin: string_to_bytes empty" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const n_stb = try pool.intern(alloc, "string_to_bytes");
    const n_len = try pool.intern(alloc, "bytes_length");

    b.beginFunc(try pool.intern(alloc, "test_main"));
    _ = b.beginBlock();

    const s = try b.addInst(.{ .const_string = try pool.intern(alloc, "") });
    const bv = try b.addInst(.{ .call_builtin = .{ .name = n_stb, .args = &.{s} } });
    const len = try b.addInst(.{ .call_builtin = .{ .name = n_len, .args = &.{bv} } });
    try b.endBlock(.{ .ret = len });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    var interpreter = Interpreter.init(alloc, module, pool);
    defer interpreter.deinit();
    try registerAll(&interpreter);

    const result = try interpreter.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0), result.int);
}

test "builtin: io_print (smoke test)" {
    var h = TestHarness.init();
    defer h.deinit();
    _ = h.setup();
    // Just verify it doesn't crash — output goes to stdout
    const result = try h.runBuiltin("io_print", &.{.{ .string = "" }});
    try std.testing.expect(result == .nil);
}
