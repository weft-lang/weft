const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("../ir.zig");
const intern_mod = @import("../intern.zig");
const InternPool = intern_mod.InternPool;
const InternedString = intern_mod.InternedString;
const ValueId = ir.ValueId;
const BlockId = ir.BlockId;
const FuncId = ir.FuncId;
const BinaryOp = ir.BinaryOp;
const UnaryOp = ir.UnaryOp;

/// High-level IR generation helper wrapping ir.Builder.
///
/// Makes generating IR from Zig code ergonomic: provides shorthand for
/// constants, builtins, control flow, and data construction. All generated
/// IR runs on the standard interpreter.
pub const Gen = struct {
    b: *ir.Builder,
    pool: *InternPool,
    alloc: Allocator,
    /// Tracks the next block ID to allocate. Both beginBlock and reserveBlock
    /// increment this, ensuring unique IDs. Blocks are stored by endBlock at
    /// their ID position in the blocks array (with placeholders for gaps).
    next_block_id: u32 = 0,

    pub fn init(alloc: Allocator, builder: *ir.Builder, pool: *InternPool) Gen {
        return .{ .b = builder, .pool = pool, .alloc = alloc };
    }

    // ── Interning ──────────────────────────────────────────────────────

    pub fn intern(self: *Gen, s: []const u8) !InternedString {
        return self.pool.intern(self.alloc, s) catch return error.OutOfMemory;
    }

    // ── Constants ──────────────────────────────────────────────────────

    pub fn constInt(self: *Gen, val: i64) !ValueId {
        return self.b.addInst(.{ .const_int = val });
    }

    pub fn constFloat(self: *Gen, val: f64) !ValueId {
        return self.b.addInst(.{ .const_float = val });
    }

    pub fn constString(self: *Gen, s: []const u8) !ValueId {
        const interned = try self.intern(s);
        return self.b.addInst(.{ .const_string = interned });
    }

    pub fn constBool(self: *Gen, val: bool) !ValueId {
        return self.b.addInst(.{ .const_bool = val });
    }

    pub fn constNil(self: *Gen) !ValueId {
        return self.b.addInst(.const_nil);
    }

    // ── Binary / Unary ─────────────────────────────────────────────────

    pub fn binary(self: *Gen, op: BinaryOp, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.b.addInst(.{ .binary = .{ .op = op, .lhs = lhs, .rhs = rhs } });
    }

    pub fn unary(self: *Gen, op: UnaryOp, operand: ValueId) !ValueId {
        return self.b.addInst(.{ .unary = .{ .op = op, .operand = operand } });
    }

    pub fn add(self: *Gen, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.binary(.add, lhs, rhs);
    }

    pub fn sub(self: *Gen, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.binary(.sub, lhs, rhs);
    }

    pub fn eq(self: *Gen, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.binary(.eq, lhs, rhs);
    }

    pub fn ne(self: *Gen, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.binary(.ne, lhs, rhs);
    }

    pub fn lt(self: *Gen, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.binary(.lt, lhs, rhs);
    }

    pub fn ge(self: *Gen, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.binary(.ge, lhs, rhs);
    }

    pub fn logicAnd(self: *Gen, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.binary(.@"and", lhs, rhs);
    }

    pub fn logicOr(self: *Gen, lhs: ValueId, rhs: ValueId) !ValueId {
        return self.binary(.@"or", lhs, rhs);
    }

    // ── Builtin calls ──────────────────────────────────────────────────

    pub fn callBuiltin(self: *Gen, name: []const u8, args: []const ValueId) !ValueId {
        const interned = try self.intern(name);
        const duped = try self.alloc.dupe(ValueId, args);
        return self.b.addInst(.{ .call_builtin = .{ .name = interned, .args = duped } });
    }

    // Convenience wrappers for frequently used builtins
    pub fn stringByteAt(self: *Gen, s: ValueId, idx: ValueId) !ValueId {
        return self.callBuiltin("string_byte_at", &.{ s, idx });
    }

    pub fn stringSlice(self: *Gen, s: ValueId, start: ValueId, end: ValueId) !ValueId {
        return self.callBuiltin("string_slice", &.{ s, start, end });
    }

    pub fn stringLength(self: *Gen, s: ValueId) !ValueId {
        return self.callBuiltin("string_length", &.{s});
    }

    pub fn stringConcat(self: *Gen, a: ValueId, b_val: ValueId) !ValueId {
        return self.callBuiltin("string_concat", &.{ a, b_val });
    }

    pub fn stringStartsWith(self: *Gen, s: ValueId, prefix: ValueId) !ValueId {
        return self.callBuiltin("string_starts_with", &.{ s, prefix });
    }

    pub fn stringIndexOf(self: *Gen, haystack: ValueId, needle: ValueId) !ValueId {
        return self.callBuiltin("string_index_of", &.{ haystack, needle });
    }

    pub fn stringToInt(self: *Gen, s: ValueId) !ValueId {
        return self.callBuiltin("string_to_int", &.{s});
    }

    pub fn listAppend(self: *Gen, list: ValueId, item: ValueId) !ValueId {
        return self.callBuiltin("list_append", &.{ list, item });
    }

    pub fn listLength(self: *Gen, list: ValueId) !ValueId {
        return self.callBuiltin("list_length", &.{list});
    }

    pub fn listNth(self: *Gen, list: ValueId, idx: ValueId) !ValueId {
        return self.callBuiltin("list_nth", &.{ list, idx });
    }

    pub fn listHead(self: *Gen, list: ValueId) !ValueId {
        const zero = try self.constInt(0);
        return self.callBuiltin("list_nth", &.{ list, zero });
    }

    pub fn ioPrint(self: *Gen, msg: ValueId) !ValueId {
        return self.callBuiltin("io_print", &.{msg});
    }

    // Map builtins
    pub fn mapNew(self: *Gen) !ValueId {
        return self.callBuiltin("map_new", &.{});
    }

    pub fn mapGet(self: *Gen, m: ValueId, key: ValueId) !ValueId {
        return self.callBuiltin("map_get", &.{ m, key });
    }

    pub fn mapSet(self: *Gen, m: ValueId, key: ValueId, val: ValueId) !ValueId {
        return self.callBuiltin("map_set", &.{ m, key, val });
    }

    pub fn mapHas(self: *Gen, m: ValueId, key: ValueId) !ValueId {
        return self.callBuiltin("map_has", &.{ m, key });
    }

    pub fn mapKeys(self: *Gen, m: ValueId) !ValueId {
        return self.callBuiltin("map_keys", &.{m});
    }

    pub fn listConcat(self: *Gen, a: ValueId, b_val: ValueId) !ValueId {
        return self.callBuiltin("list_concat", &.{ a, b_val });
    }

    // ── Data construction ──────────────────────────────────────────────

    pub fn tag(self: *Gen, name: []const u8, payload: ?ValueId) !ValueId {
        const interned = try self.intern(name);
        return self.b.addInst(.{ .tag_init = .{ .tag = interned, .payload = payload } });
    }

    pub fn tagTest(self: *Gen, value: ValueId, name: []const u8) !ValueId {
        const interned = try self.intern(name);
        return self.b.addInst(.{ .tag_test = .{ .value = value, .tag = interned } });
    }

    pub fn tagPayload(self: *Gen, value: ValueId, name: []const u8) !ValueId {
        const interned = try self.intern(name);
        return self.b.addInst(.{ .tag_payload = .{ .value = value, .tag = interned } });
    }

    pub const FieldPair = struct { name: []const u8, value: ValueId };

    pub fn record(self: *Gen, fields: []const FieldPair) !ValueId {
        const ir_fields = try self.alloc.alloc(ir.FieldInit, fields.len);
        for (fields, 0..) |f, i| {
            ir_fields[i] = .{ .name = try self.intern(f.name), .value = f.value };
        }
        return self.b.addInst(.{ .record_init = .{ .fields = ir_fields } });
    }

    pub fn recordField(self: *Gen, rec: ValueId, field: []const u8) !ValueId {
        const interned = try self.intern(field);
        return self.b.addInst(.{ .record_field = .{ .record = rec, .field = interned } });
    }

    pub fn listInit(self: *Gen, elements: []const ValueId) !ValueId {
        const duped = try self.alloc.dupe(ValueId, elements);
        return self.b.addInst(.{ .list_init = .{ .elements = duped } });
    }

    pub fn copy(self: *Gen, val: ValueId) !ValueId {
        return self.b.addInst(.{ .copy = val });
    }

    // ── Function calls ─────────────────────────────────────────────────

    pub fn callDirect(self: *Gen, func: FuncId, args: []const ValueId) !ValueId {
        const duped = try self.alloc.dupe(ValueId, args);
        return self.b.addInst(.{ .call_direct = .{ .func = func, .args = duped } });
    }

    pub fn call(self: *Gen, callee: ValueId, args: []const ValueId) !ValueId {
        const duped = try self.alloc.dupe(ValueId, args);
        return self.b.addInst(.{ .call = .{ .callee = callee, .args = duped } });
    }

    // ── Block / Function management ────────────────────────────────────

    pub fn beginFunc(self: *Gen, name: []const u8) !void {
        const interned = try self.intern(name);
        self.b.beginFunc(interned);
        self.next_block_id = 0;
    }

    pub fn addParam(self: *Gen) !ValueId {
        return self.b.addParam();
    }

    pub fn endFunc(self: *Gen) !FuncId {
        return self.b.endFunc();
    }

    /// Reserve a FuncId for forward/mutual references. Appends a placeholder
    /// to the funcs array. Use beginReservedFunc/endReservedFunc to fill it in.
    pub fn reserveFunc(self: *Gen, name: []const u8) !FuncId {
        const interned = try self.intern(name);
        const id: FuncId = @enumFromInt(self.b.func_counter);
        self.b.func_counter += 1;
        try self.b.funcs.append(self.alloc, .{
            .id = id,
            .name = interned,
            .params = &.{},
            .return_type = null,
            .effect_set = ir.EffectSet.pure,
            .blocks = &.{},
            .entry = @enumFromInt(0),
            .handle_defs = &.{},
            .value_count = 0,
        });
        return id;
    }

    /// Begin building a previously reserved function.
    pub fn beginReservedFunc(self: *Gen, name: []const u8) !void {
        const interned = try self.intern(name);
        self.b.beginFunc(interned);
        self.next_block_id = 0;
    }

    /// End building and store at the reserved FuncId position.
    pub fn endReservedFunc(self: *Gen, id: FuncId) !void {
        self.b.funcs.items[id.index()] = .{
            .id = id,
            .name = self.b.func_name,
            .params = try self.alloc.dupe(ValueId, self.b.func_params.items),
            .return_type = null,
            .effect_set = self.b.func_effect_set,
            .blocks = try self.alloc.dupe(ir.Block, self.b.blocks.items),
            .entry = self.b.entry_block orelse @enumFromInt(0),
            .handle_defs = try self.alloc.dupe(ir.HandleDef, self.b.func_handle_defs.items),
            .value_count = self.b.value_counter,
        };
    }

    /// Begin a new block with an auto-allocated ID.
    pub fn beginBlock(self: *Gen) BlockId {
        const id: BlockId = @enumFromInt(self.next_block_id);
        self.next_block_id += 1;
        self.startBlock(id);
        return id;
    }

    /// Begin building a previously reserved block.
    pub fn beginReservedBlock(self: *Gen, id: BlockId) void {
        self.startBlock(id);
    }

    fn startBlock(self: *Gen, id: BlockId) void {
        self.b.current_block_id = id;
        self.b.block_params.clearRetainingCapacity();
        self.b.block_insts.clearRetainingCapacity();
        if (self.b.entry_block == null) self.b.entry_block = id;
    }

    pub fn addBlockParam(self: *Gen) !ValueId {
        return self.b.addBlockParam();
    }

    pub fn endBlock(self: *Gen, term: ir.Terminator) !void {
        const id = self.b.current_block_id.?;
        const idx = id.index();
        const block = ir.Block{
            .id = id,
            .params = try self.alloc.dupe(ValueId, self.b.block_params.items),
            .insts = try self.alloc.dupe(ir.Inst, self.b.block_insts.items),
            .terminator = term,
        };
        // Ensure blocks array is large enough
        while (self.b.blocks.items.len <= idx) {
            try self.b.blocks.append(self.alloc, .{
                .id = @enumFromInt(@as(u32, @intCast(self.b.blocks.items.len))),
                .params = &.{},
                .insts = &.{},
                .terminator = .unreachable_term,
            });
        }
        self.b.blocks.items[idx] = block;
        self.b.current_block_id = null;
    }

    pub fn ret(self: *Gen, val: ValueId) !void {
        try self.endBlock(.{ .ret = val });
    }

    pub fn retNone(self: *Gen) !void {
        try self.endBlock(.{ .ret = null });
    }

    pub fn jump(self: *Gen, target: BlockId, args: []const ValueId) !void {
        const duped = try self.alloc.dupe(ValueId, args);
        try self.endBlock(.{ .jump = .{ .target = target, .args = duped } });
    }

    pub fn branch(self: *Gen, cond: ValueId, then_block: BlockId, else_block: BlockId) !void {
        try self.endBlock(.{ .branch = .{ .cond = cond, .then_block = then_block, .else_block = else_block } });
    }

    pub fn switchTag(self: *Gen, value: ValueId, cases: []const ir.SwitchCase, default: ?BlockId) !void {
        const duped = try self.alloc.dupe(ir.SwitchCase, cases);
        try self.endBlock(.{ .switch_tag = .{ .value = value, .cases = duped, .default = default } });
    }

    // ── Higher-level patterns ──────────────────────────────────────────

    /// Reserve a block ID for forward reference. Use beginReservedBlock(id)
    /// later to start building the block at this ID.
    pub fn reserveBlock(self: *Gen) BlockId {
        const id: BlockId = @enumFromInt(self.next_block_id);
        self.next_block_id += 1;
        return id;
    }

    /// Build module from accumulated functions.
    pub fn build(self: *Gen, entry: ?FuncId) !ir.Module {
        return self.b.build(entry);
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

const interp_mod = @import("../interp.zig");
const Interpreter = interp_mod.Interpreter;
const builtins = @import("../builtins.zig");

test "gen: basic constant and return" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const v = try g.constInt(42);
    try g.ret(v);
    const fid = try g.endFunc();
    const module = try g.build(fid);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    const result = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "gen: builtin call" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const s = try g.constString("hello");
    const len = try g.stringLength(s);
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try g.build(fid);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins.registerAll(&interp);
    const result = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 5), result.int);
}

test "gen: tag construction and test" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const payload = try g.constInt(99);
    const tagged = try g.tag("IntLit", payload);
    const is_int = try g.tagTest(tagged, "IntLit");
    try g.ret(is_int);
    const fid = try g.endFunc();
    const module = try g.build(fid);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    const result = try interp.execFunc(fid, &.{});
    try std.testing.expect(result.bool_val == true);
}

test "gen: record construction and field access" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const pos = try g.constInt(5);
    const tok = try g.constString("fn");
    const rec = try g.record(&.{
        .{ .name = "pos", .value = pos },
        .{ .name = "text", .value = tok },
    });
    const got_pos = try g.recordField(rec, "pos");
    try g.ret(got_pos);
    const fid = try g.endFunc();
    const module = try g.build(fid);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    const result = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 5), result.int);
}

test "gen: branch control flow" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    try g.beginFunc("test_main");

    // Block 0: branch on true
    _ = g.beginBlock();
    const cond = try g.constBool(true);
    const then_blk = g.reserveBlock();
    const else_blk = g.reserveBlock();
    try g.branch(cond, then_blk, else_blk);

    // Block 1 (then): return 1
    g.beginReservedBlock(then_blk);
    const v1 = try g.constInt(1);
    try g.ret(v1);

    // Block 2 (else): return 0
    g.beginReservedBlock(else_blk);
    const v0 = try g.constInt(0);
    try g.ret(v0);

    const fid = try g.endFunc();
    const module = try g.build(fid);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    const result = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 1), result.int);
}

test "gen: loop with block params (sum 1..5)" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    try g.beginFunc("test_main");

    // Block 0 (entry): jump to loop with i=1, acc=0
    _ = g.beginBlock();
    const init_i = try g.constInt(1);
    const init_acc = try g.constInt(0);
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{ init_i, init_acc });

    // Block 1 (loop header): i, acc as block params
    g.beginReservedBlock(loop_blk);
    const i = try g.addBlockParam(); // i
    const acc = try g.addBlockParam(); // acc
    const limit = try g.constInt(6);
    const done = try g.ge(i, limit);
    const body_blk = g.reserveBlock();
    const exit_blk = g.reserveBlock();
    try g.branch(done, exit_blk, body_blk);

    // Block 2 (body): acc += i, i += 1, jump back to loop
    g.beginReservedBlock(body_blk);
    const new_acc = try g.add(acc, i);
    const one = try g.constInt(1);
    const new_i = try g.add(i, one);
    try g.jump(loop_blk, &.{ new_i, new_acc });

    // Block 3 (exit): return acc
    g.beginReservedBlock(exit_blk);
    try g.ret(acc);

    const fid = try g.endFunc();
    const module = try g.build(fid);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    const result = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 15), result.int); // 1+2+3+4+5
}
