const std = @import("std");
const Allocator = std.mem.Allocator;
const intern_mod = @import("intern.zig");
const InternedString = intern_mod.InternedString;
const InternPool = intern_mod.InternPool;
const types_mod = @import("types.zig");
pub const Type = types_mod.Type;

// ── ID types ────────────────────────────────────────────────────────────

pub const ValueId = enum(u32) {
    _,

    pub fn index(self: ValueId) u32 {
        return @intFromEnum(self);
    }
};

pub const BlockId = enum(u32) {
    _,

    pub fn index(self: BlockId) u32 {
        return @intFromEnum(self);
    }
};

pub const FuncId = enum(u32) {
    _,

    pub fn index(self: FuncId) u32 {
        return @intFromEnum(self);
    }
};

// ── Binary / Unary ops ──────────────────────────────────────────────────

pub const BinaryOp = enum(u8) {
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    bit_and,
    bit_or,
    bit_xor,
    shl,
    shr,
    @"and",
    @"or",
    concat,
};

pub const UnaryOp = enum(u8) {
    neg,
    not,
    bit_not,
};

// ── Instructions ────────────────────────────────────────────────────────

pub const Inst = struct {
    result: ValueId,
    op: Op,

    pub const Op = union(enum) {
        // Constants
        const_int: i64,
        const_float: f64,
        const_string: InternedString,
        const_bool: bool,
        const_nil,

        // Arithmetic
        binary: struct { op: BinaryOp, lhs: ValueId, rhs: ValueId },
        unary: struct { op: UnaryOp, operand: ValueId },

        // Records
        record_init: struct { fields: []const FieldInit },
        record_field: struct { record: ValueId, field: InternedString },
        record_update: struct { base: ValueId, updates: []const FieldInit },

        // Tagged unions
        tag_init: struct { tag: InternedString, payload: ?ValueId },
        tag_test: struct { value: ValueId, tag: InternedString },
        tag_payload: struct { value: ValueId, tag: InternedString },

        // Lists
        list_init: struct { elements: []const ValueId },

        // Functions
        call: struct { callee: ValueId, args: []const ValueId },
        call_direct: struct { func: FuncId, args: []const ValueId },
        call_builtin: struct { name: InternedString, args: []const ValueId },
        closure: struct { func: FuncId, captures: []const ValueId },

        // Effects
        perform: struct { effect: InternedString, op: InternedString, args: []const ValueId },

        // Memory
        retain: ValueId,
        release: ValueId,

        // Misc
        copy: ValueId,
    };
};

pub const FieldInit = struct {
    name: InternedString,
    value: ValueId,
};

// ── Terminators ─────────────────────────────────────────────────────────

pub const Terminator = union(enum) {
    ret: ?ValueId,
    jump: struct { target: BlockId, args: []const ValueId },
    branch: struct { cond: ValueId, then_block: BlockId, else_block: BlockId },
    switch_tag: struct { value: ValueId, cases: []const SwitchCase, default: ?BlockId },
    unreachable_term,
};

pub const SwitchCase = struct {
    tag: InternedString,
    target: BlockId,
};

// ── Blocks ──────────────────────────────────────────────────────────────

pub const Block = struct {
    id: BlockId,
    params: []const ValueId,
    insts: []const Inst,
    terminator: Terminator,
};

// ── Effect sets (canonical definition in types.zig) ─────────────────────

pub const EffectSet = types_mod.EffectSet;

// ── Handler definitions ─────────────────────────────────────────────────

pub const HandlerClause = struct {
    op: InternedString,
    params: []const ValueId,
    resume_param: ValueId,
    body: BlockId,
};

pub const ReturnClause = struct {
    param: ValueId,
    body: BlockId,
};

pub const HandleDef = struct {
    body_block: BlockId,
    effect: InternedString,
    clauses: []const HandlerClause,
    return_clause: ?ReturnClause,
};

// ── Functions ───────────────────────────────────────────────────────────

pub const Func = struct {
    id: FuncId,
    name: InternedString,
    params: []const ValueId,
    /// Type reference — opaque until brief 0b lands.
    return_type: ?*const Type,
    effect_set: EffectSet,
    blocks: []const Block,
    entry: BlockId,
    handle_defs: []const HandleDef,
    value_count: u32,
};

// ── Module ──────────────────────────────────────────────────────────────

pub const Module = struct {
    funcs: []const Func,
    entry: ?FuncId,
};

// ── Builder ─────────────────────────────────────────────────────────────

pub const Builder = struct {
    gpa: Allocator,

    // Current function being built.
    func_name: InternedString = @enumFromInt(0),
    func_params: std.ArrayListUnmanaged(ValueId) = .empty,
    func_effect_set: EffectSet = EffectSet.pure,
    func_handle_defs: std.ArrayListUnmanaged(HandleDef) = .empty,
    blocks: std.ArrayListUnmanaged(Block) = .empty,
    entry_block: ?BlockId = null,
    value_counter: u32 = 0,

    // Current block being built.
    block_params: std.ArrayListUnmanaged(ValueId) = .empty,
    block_insts: std.ArrayListUnmanaged(Inst) = .empty,
    current_block_id: ?BlockId = null,

    // All functions.
    funcs: std.ArrayListUnmanaged(Func) = .empty,
    func_counter: u32 = 0,

    pub fn init(gpa: Allocator) Builder {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Builder) void {
        self.func_params.deinit(self.gpa);
        self.func_handle_defs.deinit(self.gpa);
        self.blocks.deinit(self.gpa);
        self.block_params.deinit(self.gpa);
        self.block_insts.deinit(self.gpa);
        self.funcs.deinit(self.gpa);
    }

    pub fn freshValue(self: *Builder) ValueId {
        const id: ValueId = @enumFromInt(self.value_counter);
        self.value_counter += 1;
        return id;
    }

    pub fn freshBlockId(self: *Builder) BlockId {
        const id: BlockId = @enumFromInt(@as(u32, @intCast(self.blocks.items.len)));
        return id;
    }

    // ── Function building ───────────────────────────────────────────

    pub fn beginFunc(self: *Builder, name: InternedString) void {
        self.func_name = name;
        self.func_params.clearRetainingCapacity();
        self.func_handle_defs.clearRetainingCapacity();
        self.blocks.clearRetainingCapacity();
        self.entry_block = null;
        self.value_counter = 0;
    }

    pub fn addParam(self: *Builder) !ValueId {
        const v = self.freshValue();
        try self.func_params.append(self.gpa, v);
        return v;
    }

    pub fn endFunc(self: *Builder) !FuncId {
        const id: FuncId = @enumFromInt(self.func_counter);
        self.func_counter += 1;

        try self.funcs.append(self.gpa, .{
            .id = id,
            .name = self.func_name,
            .params = try self.gpa.dupe(ValueId, self.func_params.items),
            .return_type = null,
            .effect_set = self.func_effect_set,
            .blocks = try self.gpa.dupe(Block, self.blocks.items),
            .entry = self.entry_block orelse @enumFromInt(0),
            .handle_defs = try self.gpa.dupe(HandleDef, self.func_handle_defs.items),
            .value_count = self.value_counter,
        });

        return id;
    }

    // ── Block building ──────────────────────────────────────────────

    pub fn beginBlock(self: *Builder) BlockId {
        const id = self.freshBlockId();
        self.current_block_id = id;
        self.block_params.clearRetainingCapacity();
        self.block_insts.clearRetainingCapacity();
        if (self.entry_block == null) self.entry_block = id;
        return id;
    }

    pub fn addBlockParam(self: *Builder) !ValueId {
        const v = self.freshValue();
        try self.block_params.append(self.gpa, v);
        return v;
    }

    pub fn addInst(self: *Builder, op: Inst.Op) !ValueId {
        const result = self.freshValue();
        try self.block_insts.append(self.gpa, .{ .result = result, .op = op });
        return result;
    }

    pub fn endBlock(self: *Builder, terminator: Terminator) !void {
        try self.blocks.append(self.gpa, .{
            .id = self.current_block_id.?,
            .params = try self.gpa.dupe(ValueId, self.block_params.items),
            .insts = try self.gpa.dupe(Inst, self.block_insts.items),
            .terminator = terminator,
        });
        self.current_block_id = null;
    }

    // ── Build module ────────────────────────────────────────────────

    pub fn build(self: *Builder, entry: ?FuncId) !Module {
        return .{
            .funcs = try self.gpa.dupe(Func, self.funcs.items),
            .entry = entry,
        };
    }
};

// ── Serialization ───────────────────────────────────────────────────────

pub const MAGIC = [4]u8{ 'R', 'H', 'I', 'Z' };
pub const FORMAT_VERSION: u32 = 1;

pub fn serialize(module: Module, pool: *const InternPool, writer: anytype) !void {
    // Magic + version
    try writer.writeAll(&MAGIC);
    try writer.writeInt(u32, FORMAT_VERSION, .little);

    // String table
    try writer.writeInt(u32, pool.count(), .little);
    for (pool.strings.items) |s| {
        try writer.writeInt(u32, @intCast(s.len), .little);
        try writer.writeAll(s);
    }

    // Functions
    try writer.writeInt(u32, @intCast(module.funcs.len), .little);
    for (module.funcs) |func| {
        try serializeFunc(func, writer);
    }

    // Entry
    try writer.writeByte(if (module.entry != null) 1 else 0);
    if (module.entry) |e| try writer.writeInt(u32, e.index(), .little);
}

fn serializeFunc(func: Func, writer: anytype) !void {
    try writer.writeInt(u32, @intFromEnum(func.name), .little);
    try writer.writeInt(u32, @intCast(func.params.len), .little);
    for (func.params) |p| try writer.writeInt(u32, p.index(), .little);
    try writer.writeInt(u32, func.value_count, .little);
    try writer.writeInt(u32, func.entry.index(), .little);

    // Blocks
    try writer.writeInt(u32, @intCast(func.blocks.len), .little);
    for (func.blocks) |block| {
        try serializeBlock(block, writer);
    }

    // Handle defs
    try writer.writeInt(u32, @intCast(func.handle_defs.len), .little);
    for (func.handle_defs) |hd| {
        try serializeHandleDef(hd, writer);
    }
}

fn serializeBlock(block: Block, writer: anytype) !void {
    try writer.writeInt(u32, block.id.index(), .little);
    try writer.writeInt(u32, @intCast(block.params.len), .little);
    for (block.params) |p| try writer.writeInt(u32, p.index(), .little);

    try writer.writeInt(u32, @intCast(block.insts.len), .little);
    for (block.insts) |inst| {
        try serializeInst(inst, writer);
    }

    try serializeTerminator(block.terminator, writer);
}

fn serializeInst(inst: Inst, writer: anytype) !void {
    try writer.writeInt(u32, inst.result.index(), .little);

    // Tag byte for op variant
    const tag: u8 = switch (inst.op) {
        .const_int => 0,
        .const_float => 1,
        .const_string => 2,
        .const_bool => 3,
        .const_nil => 4,
        .binary => 5,
        .unary => 6,
        .record_init => 7,
        .record_field => 8,
        .record_update => 9,
        .tag_init => 10,
        .tag_test => 11,
        .tag_payload => 12,
        .list_init => 13,
        .call => 14,
        .call_direct => 15,
        .call_builtin => 16,
        .closure => 17,
        .perform => 18,
        .retain => 19,
        .release => 20,
        .copy => 21,
    };
    try writer.writeByte(tag);

    switch (inst.op) {
        .const_int => |v| try writer.writeInt(i64, v, .little),
        .const_float => |v| try writer.writeAll(std.mem.asBytes(&v)),
        .const_string => |v| try writer.writeInt(u32, @intFromEnum(v), .little),
        .const_bool => |v| try writer.writeByte(if (v) 1 else 0),
        .const_nil => {},
        .binary => |v| {
            try writer.writeByte(@intFromEnum(v.op));
            try writer.writeInt(u32, v.lhs.index(), .little);
            try writer.writeInt(u32, v.rhs.index(), .little);
        },
        .unary => |v| {
            try writer.writeByte(@intFromEnum(v.op));
            try writer.writeInt(u32, v.operand.index(), .little);
        },
        .record_init => |v| {
            try writer.writeInt(u32, @intCast(v.fields.len), .little);
            for (v.fields) |f| {
                try writer.writeInt(u32, @intFromEnum(f.name), .little);
                try writer.writeInt(u32, f.value.index(), .little);
            }
        },
        .record_field => |v| {
            try writer.writeInt(u32, v.record.index(), .little);
            try writer.writeInt(u32, @intFromEnum(v.field), .little);
        },
        .record_update => |v| {
            try writer.writeInt(u32, v.base.index(), .little);
            try writer.writeInt(u32, @intCast(v.updates.len), .little);
            for (v.updates) |f| {
                try writer.writeInt(u32, @intFromEnum(f.name), .little);
                try writer.writeInt(u32, f.value.index(), .little);
            }
        },
        .tag_init => |v| {
            try writer.writeInt(u32, @intFromEnum(v.tag), .little);
            try writer.writeByte(if (v.payload != null) 1 else 0);
            if (v.payload) |p| try writer.writeInt(u32, p.index(), .little);
        },
        .tag_test => |v| {
            try writer.writeInt(u32, v.value.index(), .little);
            try writer.writeInt(u32, @intFromEnum(v.tag), .little);
        },
        .tag_payload => |v| {
            try writer.writeInt(u32, v.value.index(), .little);
            try writer.writeInt(u32, @intFromEnum(v.tag), .little);
        },
        .list_init => |v| {
            try writer.writeInt(u32, @intCast(v.elements.len), .little);
            for (v.elements) |e| try writer.writeInt(u32, e.index(), .little);
        },
        .call => |v| {
            try writer.writeInt(u32, v.callee.index(), .little);
            try writeValueSlice(v.args, writer);
        },
        .call_direct => |v| {
            try writer.writeInt(u32, v.func.index(), .little);
            try writeValueSlice(v.args, writer);
        },
        .call_builtin => |v| {
            try writer.writeInt(u32, @intFromEnum(v.name), .little);
            try writeValueSlice(v.args, writer);
        },
        .closure => |v| {
            try writer.writeInt(u32, v.func.index(), .little);
            try writeValueSlice(v.captures, writer);
        },
        .perform => |v| {
            try writer.writeInt(u32, @intFromEnum(v.effect), .little);
            try writer.writeInt(u32, @intFromEnum(v.op), .little);
            try writeValueSlice(v.args, writer);
        },
        .retain => |v| try writer.writeInt(u32, v.index(), .little),
        .release => |v| try writer.writeInt(u32, v.index(), .little),
        .copy => |v| try writer.writeInt(u32, v.index(), .little),
    }
}

fn writeValueSlice(values: []const ValueId, writer: anytype) !void {
    try writer.writeInt(u32, @intCast(values.len), .little);
    for (values) |v| try writer.writeInt(u32, v.index(), .little);
}

fn serializeTerminator(term: Terminator, writer: anytype) !void {
    const tag: u8 = switch (term) {
        .ret => 0,
        .jump => 1,
        .branch => 2,
        .switch_tag => 3,
        .unreachable_term => 4,
    };
    try writer.writeByte(tag);

    switch (term) {
        .ret => |v| {
            try writer.writeByte(if (v != null) 1 else 0);
            if (v) |val| try writer.writeInt(u32, val.index(), .little);
        },
        .jump => |v| {
            try writer.writeInt(u32, v.target.index(), .little);
            try writeValueSlice(v.args, writer);
        },
        .branch => |v| {
            try writer.writeInt(u32, v.cond.index(), .little);
            try writer.writeInt(u32, v.then_block.index(), .little);
            try writer.writeInt(u32, v.else_block.index(), .little);
        },
        .switch_tag => |v| {
            try writer.writeInt(u32, v.value.index(), .little);
            try writer.writeInt(u32, @intCast(v.cases.len), .little);
            for (v.cases) |c| {
                try writer.writeInt(u32, @intFromEnum(c.tag), .little);
                try writer.writeInt(u32, c.target.index(), .little);
            }
            try writer.writeByte(if (v.default != null) 1 else 0);
            if (v.default) |d| try writer.writeInt(u32, d.index(), .little);
        },
        .unreachable_term => {},
    }
}

fn serializeHandleDef(hd: HandleDef, writer: anytype) !void {
    try writer.writeInt(u32, hd.body_block.index(), .little);
    try writer.writeInt(u32, @intFromEnum(hd.effect), .little);
    try writer.writeInt(u32, @intCast(hd.clauses.len), .little);
    for (hd.clauses) |cl| {
        try writer.writeInt(u32, @intFromEnum(cl.op), .little);
        try writeValueSlice(cl.params, writer);
        try writer.writeInt(u32, cl.resume_param.index(), .little);
        try writer.writeInt(u32, cl.body.index(), .little);
    }
    try writer.writeByte(if (hd.return_clause != null) 1 else 0);
    if (hd.return_clause) |rc| {
        try writer.writeInt(u32, rc.param.index(), .little);
        try writer.writeInt(u32, rc.body.index(), .little);
    }
}

// ── Deserialization ─────────────────────────────────────────────────────

pub const DeserializeError = error{
    InvalidMagic,
    UnsupportedVersion,
    InvalidData,
    OutOfMemory,
    EndOfStream,
    Overflow,
};

pub fn deserialize(reader: anytype, gpa: Allocator, pool: *InternPool) DeserializeError!Module {
    // Magic
    var magic: [4]u8 = undefined;
    reader.readNoEof(&magic) catch return error.InvalidData;
    if (!std.mem.eql(u8, &magic, &MAGIC)) return error.InvalidMagic;

    // Version
    const version = reader.readInt(u32, .little) catch return error.InvalidData;
    if (version != FORMAT_VERSION) return error.UnsupportedVersion;

    // String table
    const str_count = reader.readInt(u32, .little) catch return error.InvalidData;
    for (0..str_count) |_| {
        const len = reader.readInt(u32, .little) catch return error.InvalidData;
        const buf = gpa.alloc(u8, len) catch return error.OutOfMemory;
        defer gpa.free(buf);
        reader.readNoEof(buf) catch return error.InvalidData;
        _ = pool.intern(gpa, buf) catch return error.OutOfMemory;
    }

    // Functions
    const func_count = reader.readInt(u32, .little) catch return error.InvalidData;
    const funcs = gpa.alloc(Func, func_count) catch return error.OutOfMemory;
    for (funcs) |*func| {
        func.* = try deserializeFunc(reader, gpa);
    }

    // Entry
    const has_entry = reader.readByte() catch return error.InvalidData;
    const entry: ?FuncId = if (has_entry == 1)
        @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData)
    else
        null;

    return .{ .funcs = funcs, .entry = entry };
}

fn deserializeFunc(reader: anytype, gpa: Allocator) DeserializeError!Func {
    const name: InternedString = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
    const param_count = reader.readInt(u32, .little) catch return error.InvalidData;
    const params = gpa.alloc(ValueId, param_count) catch return error.OutOfMemory;
    for (params) |*p| p.* = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);

    const value_count = reader.readInt(u32, .little) catch return error.InvalidData;
    const entry: BlockId = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);

    const block_count = reader.readInt(u32, .little) catch return error.InvalidData;
    const blocks = gpa.alloc(Block, block_count) catch return error.OutOfMemory;
    for (blocks) |*blk| blk.* = try deserializeBlock(reader, gpa);

    const hd_count = reader.readInt(u32, .little) catch return error.InvalidData;
    const handle_defs = gpa.alloc(HandleDef, hd_count) catch return error.OutOfMemory;
    for (handle_defs) |*hd| hd.* = try deserializeHandleDef(reader, gpa);

    return .{
        .id = @enumFromInt(0), // Caller should fix up
        .name = name,
        .params = params,
        .return_type = null,
        .effect_set = EffectSet.pure,
        .blocks = blocks,
        .entry = entry,
        .handle_defs = handle_defs,
        .value_count = value_count,
    };
}

fn deserializeBlock(reader: anytype, gpa: Allocator) DeserializeError!Block {
    const id: BlockId = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
    const param_count = reader.readInt(u32, .little) catch return error.InvalidData;
    const params = gpa.alloc(ValueId, param_count) catch return error.OutOfMemory;
    for (params) |*p| p.* = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);

    const inst_count = reader.readInt(u32, .little) catch return error.InvalidData;
    const insts = gpa.alloc(Inst, inst_count) catch return error.OutOfMemory;
    for (insts) |*inst| inst.* = try deserializeInst(reader, gpa);

    const terminator = try deserializeTerminator(reader, gpa);

    return .{ .id = id, .params = params, .insts = insts, .terminator = terminator };
}

fn readValueSlice(reader: anytype, gpa: Allocator) DeserializeError![]const ValueId {
    const count = reader.readInt(u32, .little) catch return error.InvalidData;
    const vals = gpa.alloc(ValueId, count) catch return error.OutOfMemory;
    for (vals) |*v| v.* = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
    return vals;
}

fn deserializeInst(reader: anytype, gpa: Allocator) DeserializeError!Inst {
    const result: ValueId = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
    const tag = reader.readByte() catch return error.InvalidData;

    const op: Inst.Op = switch (tag) {
        0 => .{ .const_int = reader.readInt(i64, .little) catch return error.InvalidData },
        1 => blk: {
            var bytes: [8]u8 = undefined;
            reader.readNoEof(&bytes) catch return error.InvalidData;
            break :blk .{ .const_float = @bitCast(bytes) };
        },
        2 => .{ .const_string = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData) },
        3 => .{ .const_bool = (reader.readByte() catch return error.InvalidData) != 0 },
        4 => .const_nil,
        5 => .{ .binary = .{
            .op = @enumFromInt(reader.readByte() catch return error.InvalidData),
            .lhs = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .rhs = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
        } },
        6 => .{ .unary = .{
            .op = @enumFromInt(reader.readByte() catch return error.InvalidData),
            .operand = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
        } },
        7 => blk: { // record_init
            const count = reader.readInt(u32, .little) catch return error.InvalidData;
            const fields = gpa.alloc(FieldInit, count) catch return error.OutOfMemory;
            for (fields) |*f| {
                f.name = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
                f.value = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
            }
            break :blk .{ .record_init = .{ .fields = fields } };
        },
        8 => .{ .record_field = .{
            .record = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .field = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
        } },
        9 => blk: { // record_update
            const base: ValueId = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
            const count = reader.readInt(u32, .little) catch return error.InvalidData;
            const updates = gpa.alloc(FieldInit, count) catch return error.OutOfMemory;
            for (updates) |*f| {
                f.name = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
                f.value = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
            }
            break :blk .{ .record_update = .{ .base = base, .updates = updates } };
        },
        10 => blk: { // tag_init
            const t: InternedString = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
            const has_payload = (reader.readByte() catch return error.InvalidData) != 0;
            const payload: ?ValueId = if (has_payload)
                @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData)
            else
                null;
            break :blk .{ .tag_init = .{ .tag = t, .payload = payload } };
        },
        11 => .{ .tag_test = .{
            .value = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .tag = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
        } },
        12 => .{ .tag_payload = .{
            .value = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .tag = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
        } },
        13 => blk: { // list_init
            const count = reader.readInt(u32, .little) catch return error.InvalidData;
            const elems = gpa.alloc(ValueId, count) catch return error.OutOfMemory;
            for (elems) |*e| e.* = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
            break :blk .{ .list_init = .{ .elements = elems } };
        },
        14 => .{ .call = .{
            .callee = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .args = try readValueSlice(reader, gpa),
        } },
        15 => .{ .call_direct = .{
            .func = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .args = try readValueSlice(reader, gpa),
        } },
        16 => .{ .call_builtin = .{
            .name = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .args = try readValueSlice(reader, gpa),
        } },
        17 => .{ .closure = .{
            .func = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .captures = try readValueSlice(reader, gpa),
        } },
        18 => .{ .perform = .{
            .effect = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .op = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .args = try readValueSlice(reader, gpa),
        } },
        19 => .{ .retain = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData) },
        20 => .{ .release = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData) },
        21 => .{ .copy = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData) },
        else => return error.InvalidData,
    };

    return .{ .result = result, .op = op };
}

fn deserializeTerminator(reader: anytype, gpa: Allocator) DeserializeError!Terminator {
    const tag = reader.readByte() catch return error.InvalidData;
    return switch (tag) {
        0 => blk: { // ret
            const has_val = (reader.readByte() catch return error.InvalidData) != 0;
            break :blk .{ .ret = if (has_val)
                @as(ValueId, @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData))
            else
                null };
        },
        1 => .{ .jump = .{
            .target = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .args = try readValueSlice(reader, gpa),
        } },
        2 => .{ .branch = .{
            .cond = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .then_block = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
            .else_block = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
        } },
        3 => blk: { // switch_tag
            const value: ValueId = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
            const case_count = reader.readInt(u32, .little) catch return error.InvalidData;
            const cases = gpa.alloc(SwitchCase, case_count) catch return error.OutOfMemory;
            for (cases) |*c| {
                c.tag = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
                c.target = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
            }
            const has_default = (reader.readByte() catch return error.InvalidData) != 0;
            const default: ?BlockId = if (has_default)
                @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData)
            else
                null;
            break :blk .{ .switch_tag = .{ .value = value, .cases = cases, .default = default } };
        },
        4 => .unreachable_term,
        else => error.InvalidData,
    };
}

fn deserializeHandleDef(reader: anytype, gpa: Allocator) DeserializeError!HandleDef {
    const body_block: BlockId = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
    const effect: InternedString = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
    const clause_count = reader.readInt(u32, .little) catch return error.InvalidData;
    const clauses = gpa.alloc(HandlerClause, clause_count) catch return error.OutOfMemory;
    for (clauses) |*cl| {
        cl.op = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
        cl.params = try readValueSlice(reader, gpa);
        cl.resume_param = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
        cl.body = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData);
    }
    const has_rc = (reader.readByte() catch return error.InvalidData) != 0;
    const return_clause: ?ReturnClause = if (has_rc) .{
        .param = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
        .body = @enumFromInt(reader.readInt(u32, .little) catch return error.InvalidData),
    } else null;

    return .{
        .body_block = body_block,
        .effect = effect,
        .clauses = clauses,
        .return_clause = return_clause,
    };
}

// ── Tests ───────────────────────────────────────────────────────────────

test "ir: builder basics" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    var b = Builder.init(gpa);
    defer b.deinit();

    const main_name = try pool.intern(gpa, "main");
    b.beginFunc(main_name);

    const blk = b.beginBlock();
    const v0 = try b.addInst(.{ .const_int = 42 });
    try b.endBlock(.{ .ret = v0 });

    _ = blk;
    const fid = try b.endFunc();
    const module = try b.build(fid);
    defer gpa.free(module.funcs);

    try std.testing.expectEqual(@as(usize, 1), module.funcs.len);
    try std.testing.expectEqual(@as(usize, 1), module.funcs[0].blocks.len);
    try std.testing.expectEqual(@as(usize, 1), module.funcs[0].blocks[0].insts.len);

    // Clean up duped slices
    gpa.free(module.funcs[0].params);
    gpa.free(module.funcs[0].blocks[0].params);
    gpa.free(module.funcs[0].blocks[0].insts);
    gpa.free(module.funcs[0].blocks);
    gpa.free(module.funcs[0].handle_defs);
}

test "ir: branch" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    var b = Builder.init(gpa);
    defer b.deinit();

    b.beginFunc(try pool.intern(gpa, "test_branch"));

    const entry = b.beginBlock();
    const cond = try b.addInst(.{ .const_bool = true });
    _ = entry;

    // We need the block IDs before ending, so pre-allocate
    // Actually, we need to end entry first, then create then/else blocks
    // But we don't know the IDs yet. Use a placeholder approach:
    // Create the blocks, get IDs, then end entry with branch.
    try b.endBlock(.{ .branch = .{
        .cond = cond,
        .then_block = @enumFromInt(1),
        .else_block = @enumFromInt(2),
    } });

    const then_blk = b.beginBlock();
    _ = then_blk;
    const v1 = try b.addInst(.{ .const_int = 1 });
    try b.endBlock(.{ .ret = v1 });

    const else_blk = b.beginBlock();
    _ = else_blk;
    const v2 = try b.addInst(.{ .const_int = 0 });
    try b.endBlock(.{ .ret = v2 });

    const fid = try b.endFunc();
    const module = try b.build(fid);
    defer gpa.free(module.funcs);

    try std.testing.expectEqual(@as(usize, 3), module.funcs[0].blocks.len);

    // Cleanup
    for (module.funcs[0].blocks) |blk| {
        gpa.free(blk.params);
        gpa.free(blk.insts);
    }
    gpa.free(module.funcs[0].params);
    gpa.free(module.funcs[0].blocks);
    gpa.free(module.funcs[0].handle_defs);
}

test "ir: serialization round-trip" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    var b = Builder.init(gpa);
    defer b.deinit();

    const name = try pool.intern(gpa, "round_trip");
    const hello = try pool.intern(gpa, "hello");

    b.beginFunc(name);
    _ = b.beginBlock();
    const v0 = try b.addInst(.{ .const_int = 42 });
    const v1 = try b.addInst(.{ .const_string = hello });
    const v2 = try b.addInst(.{ .const_bool = true });
    _ = v1;
    _ = v2;
    try b.endBlock(.{ .ret = v0 });

    const fid = try b.endFunc();
    const module = try b.build(fid);
    defer gpa.free(module.funcs);

    // Serialize
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    try serialize(module, &pool, buf.writer(gpa));

    // Deserialize
    var pool2 = InternPool.init(gpa);
    defer pool2.deinit(gpa);

    var stream = std.io.fixedBufferStream(buf.items);
    const module2 = try deserialize(stream.reader(), gpa, &pool2);

    try std.testing.expectEqual(module.funcs.len, module2.funcs.len);
    try std.testing.expectEqual(
        module.funcs[0].blocks[0].insts.len,
        module2.funcs[0].blocks[0].insts.len,
    );

    // Verify first instruction is const_int 42
    const inst0 = module2.funcs[0].blocks[0].insts[0];
    try std.testing.expectEqual(@as(i64, 42), inst0.op.const_int);

    // Verify string was interned
    try std.testing.expectEqualStrings("round_trip", pool2.get(@enumFromInt(0)));
    try std.testing.expectEqualStrings("hello", pool2.get(@enumFromInt(1)));

    // Cleanup original
    for (module.funcs[0].blocks) |blk| {
        gpa.free(blk.params);
        gpa.free(blk.insts);
    }
    gpa.free(module.funcs[0].params);
    gpa.free(module.funcs[0].blocks);
    gpa.free(module.funcs[0].handle_defs);

    // Cleanup deserialized
    for (module2.funcs[0].blocks) |blk| {
        gpa.free(blk.params);
        gpa.free(blk.insts);
    }
    gpa.free(module2.funcs[0].params);
    gpa.free(module2.funcs[0].blocks);
    gpa.free(module2.funcs[0].handle_defs);
    gpa.free(module2.funcs);
}

test "ir: invalid magic" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const bad_data = "NOPE" ++ "\x01\x00\x00\x00";
    var stream = std.io.fixedBufferStream(bad_data);
    const result = deserialize(stream.reader(), gpa, &pool);
    try std.testing.expectError(error.InvalidMagic, result);
}

test "ir: unsupported version" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const bad_data = "RHIZ" ++ "\xff\x00\x00\x00";
    var stream = std.io.fixedBufferStream(bad_data);
    const result = deserialize(stream.reader(), gpa, &pool);
    try std.testing.expectError(error.UnsupportedVersion, result);
}

test "ir: every const variant" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    var b = Builder.init(gpa);
    defer b.deinit();

    b.beginFunc(try pool.intern(gpa, "consts"));
    _ = b.beginBlock();

    const vi = try b.addInst(.{ .const_int = -100 });
    const vf = try b.addInst(.{ .const_float = 3.14 });
    const vs = try b.addInst(.{ .const_string = try pool.intern(gpa, "test") });
    const vb = try b.addInst(.{ .const_bool = false });
    const vn = try b.addInst(.const_nil);
    _ = vf;
    _ = vs;
    _ = vb;
    _ = vn;

    try b.endBlock(.{ .ret = vi });
    const fid = try b.endFunc();
    const module = try b.build(fid);
    defer gpa.free(module.funcs);

    try std.testing.expectEqual(@as(usize, 5), module.funcs[0].blocks[0].insts.len);

    for (module.funcs[0].blocks) |blk| {
        gpa.free(blk.params);
        gpa.free(blk.insts);
    }
    gpa.free(module.funcs[0].params);
    gpa.free(module.funcs[0].blocks);
    gpa.free(module.funcs[0].handle_defs);
}

test "ir: all instruction variants serialize round-trip" {
    const gpa = std.testing.allocator;
    var arena = @import("arena.zig").Arena.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const name = try pool.intern(gpa, "all_variants");
    const field_a = try pool.intern(gpa, "a");
    const tag_x = try pool.intern(gpa, "X");
    const effect_io = try pool.intern(gpa, "IO");
    const op_print = try pool.intern(gpa, "print");
    const builtin_len = try pool.intern(gpa, "len");

    var b = Builder.init(alloc);

    // A second function to reference with call_direct/closure.
    b.beginFunc(try pool.intern(gpa, "helper"));
    _ = b.beginBlock();
    const helper_ret = try b.addInst(.{ .const_int = 0 });
    try b.endBlock(.{ .ret = helper_ret });
    const helper_fid = try b.endFunc();

    // Main function with every instruction variant.
    b.beginFunc(name);
    _ = b.beginBlock();

    const v_int = try b.addInst(.{ .const_int = -999 });
    const v_float = try b.addInst(.{ .const_float = 2.718 });
    const v_str = try b.addInst(.{ .const_string = field_a });
    const v_bool = try b.addInst(.{ .const_bool = true });
    const v_nil = try b.addInst(.const_nil);
    const v_bin = try b.addInst(.{ .binary = .{ .op = .add, .lhs = v_int, .rhs = v_int } });
    const v_un = try b.addInst(.{ .unary = .{ .op = .neg, .operand = v_int } });
    const v_rec = try b.addInst(.{ .record_init = .{ .fields = &.{.{ .name = field_a, .value = v_int }} } });
    _ = try b.addInst(.{ .record_field = .{ .record = v_rec, .field = field_a } });
    _ = try b.addInst(.{ .record_update = .{ .base = v_rec, .updates = &.{.{ .name = field_a, .value = v_float }} } });
    const v_tag = try b.addInst(.{ .tag_init = .{ .tag = tag_x, .payload = v_int } });
    _ = try b.addInst(.{ .tag_test = .{ .value = v_tag, .tag = tag_x } });
    _ = try b.addInst(.{ .tag_payload = .{ .value = v_tag, .tag = tag_x } });
    const v_lst = try b.addInst(.{ .list_init = .{ .elements = &.{ v_int, v_float } } });
    _ = try b.addInst(.{ .call = .{ .callee = v_nil, .args = &.{v_int} } });
    _ = try b.addInst(.{ .call_direct = .{ .func = helper_fid, .args = &.{v_int} } });
    _ = try b.addInst(.{ .call_builtin = .{ .name = builtin_len, .args = &.{v_lst} } });
    _ = try b.addInst(.{ .closure = .{ .func = helper_fid, .captures = &.{v_int} } });
    _ = try b.addInst(.{ .perform = .{ .effect = effect_io, .op = op_print, .args = &.{v_str} } });
    _ = try b.addInst(.{ .retain = v_rec });
    _ = try b.addInst(.{ .release = v_rec });
    _ = try b.addInst(.{ .copy = v_int });
    _ = v_bin;
    _ = v_un;
    _ = v_bool;

    try b.endBlock(.{ .ret = v_nil });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    try std.testing.expectEqual(@as(usize, 22), module.funcs[1].blocks[0].insts.len);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    try serialize(module, &pool, buf.writer(gpa));

    // Use a backing arena so pool2 + deserialized data share one allocator
    var backing2 = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing2.deinit();
    const alloc2 = backing2.allocator();

    var pool2 = InternPool.init(alloc2);

    var stream = std.io.fixedBufferStream(buf.items);
    const module2 = try deserialize(stream.reader(), alloc2, &pool2);

    try std.testing.expectEqual(module.funcs.len, module2.funcs.len);
    try std.testing.expectEqual(@as(usize, 22), module2.funcs[1].blocks[0].insts.len);

    const insts = module2.funcs[1].blocks[0].insts;
    try std.testing.expectEqual(@as(i64, -999), insts[0].op.const_int);
    try std.testing.expectApproxEqAbs(@as(f64, 2.718), insts[1].op.const_float, 0.001);
    try std.testing.expect(insts[3].op.const_bool);
    try std.testing.expect(insts[4].op == .const_nil);
    try std.testing.expectEqual(BinaryOp.add, insts[5].op.binary.op);
    try std.testing.expectEqual(UnaryOp.neg, insts[6].op.unary.op);
    try std.testing.expectEqual(@as(usize, 1), insts[7].op.record_init.fields.len);
    try std.testing.expectEqual(@as(usize, 2), insts[13].op.list_init.elements.len);
    try std.testing.expect(insts[18].op == .perform);
    try std.testing.expect(insts[19].op == .retain);
    try std.testing.expect(insts[20].op == .release);
    try std.testing.expect(insts[21].op == .copy);
}

test "ir: all terminator variants serialize round-trip" {
    const gpa = std.testing.allocator;
    var arena = @import("arena.zig").Arena.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const tag_a = try pool.intern(gpa, "A");
    const tag_b = try pool.intern(gpa, "B");

    var b = Builder.init(alloc);
    b.beginFunc(try pool.intern(gpa, "terminators"));

    _ = b.beginBlock();
    const cond = try b.addInst(.{ .const_bool = true });
    try b.endBlock(.{ .branch = .{ .cond = cond, .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } });

    _ = b.beginBlock();
    const rv = try b.addInst(.{ .const_int = 1 });
    try b.endBlock(.{ .ret = rv });

    _ = b.beginBlock();
    try b.endBlock(.{ .jump = .{ .target = @enumFromInt(1), .args = &.{} } });

    _ = b.beginBlock();
    const sv = try b.addInst(.{ .const_int = 0 });
    try b.endBlock(.{ .switch_tag = .{
        .value = sv,
        .cases = &.{ .{ .tag = tag_a, .target = @enumFromInt(1) }, .{ .tag = tag_b, .target = @enumFromInt(2) } },
        .default = @enumFromInt(1),
    } });

    _ = b.beginBlock();
    try b.endBlock(.unreachable_term);

    _ = b.beginBlock();
    try b.endBlock(.{ .ret = null });

    const fid = try b.endFunc();
    const module = try b.build(fid);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    try serialize(module, &pool, buf.writer(gpa));

    var backing2 = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing2.deinit();
    const alloc2 = backing2.allocator();

    var pool2 = InternPool.init(alloc2);

    var stream = std.io.fixedBufferStream(buf.items);
    const module2 = try deserialize(stream.reader(), alloc2, &pool2);

    try std.testing.expectEqual(@as(usize, 6), module2.funcs[0].blocks.len);
    try std.testing.expect(module2.funcs[0].blocks[0].terminator == .branch);
    try std.testing.expect(module2.funcs[0].blocks[1].terminator.ret != null);
    try std.testing.expect(module2.funcs[0].blocks[2].terminator == .jump);
    try std.testing.expect(module2.funcs[0].blocks[3].terminator == .switch_tag);
    try std.testing.expectEqual(@as(usize, 2), module2.funcs[0].blocks[3].terminator.switch_tag.cases.len);
    try std.testing.expect(module2.funcs[0].blocks[3].terminator.switch_tag.default != null);
    try std.testing.expect(module2.funcs[0].blocks[4].terminator == .unreachable_term);
    try std.testing.expect(module2.funcs[0].blocks[5].terminator.ret == null);
}

test "ir: truncated input" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const truncated = "RHIZ" ++ "\x01\x00\x00\x00";
    var stream = std.io.fixedBufferStream(truncated);
    const result = deserialize(stream.reader(), gpa, &pool);
    try std.testing.expectError(error.InvalidData, result);
}

test "ir: empty module round-trip" {
    const gpa = std.testing.allocator;
    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    var b = Builder.init(gpa);
    defer b.deinit();
    const module = try b.build(null);
    defer gpa.free(module.funcs);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    try serialize(module, &pool, buf.writer(gpa));

    var pool2 = InternPool.init(gpa);
    defer pool2.deinit(gpa);
    var stream = std.io.fixedBufferStream(buf.items);
    const module2 = try deserialize(stream.reader(), gpa, &pool2);
    defer gpa.free(module2.funcs);

    try std.testing.expectEqual(@as(usize, 0), module2.funcs.len);
    try std.testing.expect(module2.entry == null);
}

test "ir: handle_def serialize round-trip" {
    const gpa = std.testing.allocator;
    var arena = @import("arena.zig").Arena.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    var pool = InternPool.init(gpa);
    defer pool.deinit(gpa);

    const effect_state = try pool.intern(gpa, "State");
    const op_get = try pool.intern(gpa, "get");

    var b = Builder.init(alloc);
    b.beginFunc(try pool.intern(gpa, "with_handler"));

    _ = b.beginBlock();
    const hv = try b.addInst(.{ .const_int = 42 });
    try b.endBlock(.{ .ret = hv });

    _ = b.beginBlock();
    const resume_val = try b.addInst(.{ .const_int = 0 });
    try b.endBlock(.{ .ret = resume_val });

    _ = b.beginBlock();
    const ret_val = try b.addInst(.{ .const_int = 1 });
    try b.endBlock(.{ .ret = ret_val });

    const resume_param = b.freshValue();
    const clause_param = b.freshValue();
    const ret_param = b.freshValue();
    try b.func_handle_defs.append(alloc, .{
        .body_block = @enumFromInt(0),
        .effect = effect_state,
        .clauses = &.{.{
            .op = op_get,
            .params = &.{clause_param},
            .resume_param = resume_param,
            .body = @enumFromInt(1),
        }},
        .return_clause = .{ .param = ret_param, .body = @enumFromInt(2) },
    });

    const fid = try b.endFunc();
    const module = try b.build(fid);

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    try serialize(module, &pool, buf.writer(gpa));

    var backing2 = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing2.deinit();
    const alloc2 = backing2.allocator();

    var pool2 = InternPool.init(alloc2);

    var stream = std.io.fixedBufferStream(buf.items);
    const module2 = try deserialize(stream.reader(), alloc2, &pool2);

    try std.testing.expectEqual(@as(usize, 1), module2.funcs[0].handle_defs.len);
    const hd = module2.funcs[0].handle_defs[0];
    try std.testing.expectEqual(@as(usize, 1), hd.clauses.len);
    try std.testing.expect(hd.return_clause != null);
    try std.testing.expectEqualStrings("State", pool2.get(hd.effect));
    try std.testing.expectEqualStrings("get", pool2.get(hd.clauses[0].op));
}
