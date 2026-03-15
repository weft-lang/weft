const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("ir.zig");
const intern_mod = @import("intern.zig");
const InternedString = intern_mod.InternedString;
const InternPool = intern_mod.InternPool;
const Arena = @import("arena.zig").Arena;

// ── Value representation ────────────────────────────────────────────────

pub const Value = union(enum) {
    int: i64,
    float: f64,
    bool_val: bool,
    string: []const u8,
    nil,
    list: *ListValue,
    record: *RecordValue,
    tagged: *TaggedValue,
    closure: *ClosureValue,
    continuation: *Continuation,
    builtin_fn: *const anyopaque,  // actually a BuiltinFn, stored opaque to break cycle
    map: *MapValue,
    bytes: *BytesValue,

    pub const uninit: Value = .nil;
};

pub const ListValue = struct {
    items: []const Value,
    ref_count: u32 = 1,
};

pub const RecordValue = struct {
    fields: []const FieldEntry,
    ref_count: u32 = 1,
};

pub const FieldEntry = struct {
    name: InternedString,
    value: Value,
};

pub const TaggedValue = struct {
    tag: InternedString,
    payload: ?Value,
    ref_count: u32 = 1,
};

pub const ClosureValue = struct {
    func: ir.FuncId,
    captures: []const Value,
    ref_count: u32 = 1,
};

pub const Continuation = struct {
    frames: []const CallFrame,
    handlers: []const HandlerFrame,
    perform_result: ir.ValueId, // ValueId in top frame to bind resume arg to
    consumed: bool = false,
    ref_count: u32 = 1,
};

pub const MapValue = struct {
    entries: std.StringHashMapUnmanaged(Value),
    ref_count: u32 = 1,
};

pub const BytesValue = struct {
    data: std.ArrayListUnmanaged(u8),
    ref_count: u32 = 1,
};

/// BuiltinFn receives args and an opaque pointer to the Interpreter.
/// Cast with @ptrCast/@alignCast inside the builtin to access the interpreter.
pub const BuiltinFn = *const fn (args: []const Value, ctx: *anyopaque) InterpreterError!Value;

// ── Errors ──────────────────────────────────────────────────────────────

pub const InterpreterError = error{
    TypeError,
    DivisionByZero,
    FieldNotFound,
    TagMismatch,
    IndexOutOfBounds,
    UnhandledEffect,
    ContinuationConsumed,
    ArityMismatch,
    UnreachableReached,
    StackOverflow,
    OutOfMemory,
};

// ── Call frame ──────────────────────────────────────────────────────────

pub const CallFrame = struct {
    func: *const ir.Func,
    block_idx: u32,
    inst_idx: u32,
    env: []Value,
    /// ValueId in the caller's frame to receive the return value.
    return_dst: ?ir.ValueId,
};

// ── Handler frame ───────────────────────────────────────────────────────

pub const HandlerFrame = struct {
    effect: InternedString,
    handle_def: *const ir.HandleDef,
    func: *const ir.Func,
    /// Call stack index of the body frame. Everything from here up gets captured.
    stack_depth: usize,
    /// Where to deliver the final handle expression result.
    return_dst: ?ir.ValueId,
};

// ── Interpreter ─────────────────────────────────────────────────────────

const MAX_STACK_DEPTH = 4096;

pub const Interpreter = struct {
    gpa: Allocator,
    arena: Arena,
    module: ir.Module,
    pool: *const InternPool,

    call_stack: std.ArrayListUnmanaged(CallFrame),
    handler_stack: std.ArrayListUnmanaged(HandlerFrame),
    builtins: std.StringHashMapUnmanaged(BuiltinFn),
    final_value: Value,

    pub fn init(gpa: Allocator, module: ir.Module, pool: *const InternPool) Interpreter {
        return .{
            .gpa = gpa,
            .arena = Arena.init(gpa),
            .module = module,
            .pool = pool,
            .call_stack = .empty,
            .handler_stack = .empty,
            .builtins = .empty,
            .final_value = .nil,
        };
    }

    pub fn deinit(self: *Interpreter) void {
        for (self.call_stack.items) |frame| {
            self.gpa.free(frame.env);
        }
        self.call_stack.deinit(self.gpa);
        self.handler_stack.deinit(self.gpa);
        self.builtins.deinit(self.gpa);
        self.arena.deinit();
    }

    pub fn registerBuiltin(self: *Interpreter, name: []const u8, func: BuiltinFn) !void {
        try self.builtins.put(self.gpa, name, func);
    }

    // ── Entry point ─────────────────────────────────────────────────

    pub fn execFunc(self: *Interpreter, func_id: ir.FuncId, args: []const Value) InterpreterError!Value {
        const func = &self.module.funcs[func_id.index()];
        try self.pushFrame(func, args, null);
        return self.run();
    }

    fn pushFrame(self: *Interpreter, func: *const ir.Func, args: []const Value, return_dst: ?ir.ValueId) InterpreterError!void {
        if (self.call_stack.items.len >= MAX_STACK_DEPTH) return error.StackOverflow;

        const env = self.gpa.alloc(Value, func.value_count) catch return error.OutOfMemory;
        @memset(env, Value.uninit);

        // Bind function params
        for (func.params, 0..) |param, i| {
            if (i < args.len) {
                env[param.index()] = args[i];
            }
        }

        // Determine entry block: if handle_defs exist, start at body_block
        const entry = if (func.handle_defs.len > 0)
            func.handle_defs[0].body_block.index()
        else
            func.entry.index();

        self.call_stack.append(self.gpa, .{
            .func = func,
            .block_idx = entry,
            .inst_idx = 0,
            .env = env,
            .return_dst = return_dst,
        }) catch return error.OutOfMemory;

        // Install handlers for this function's handle_defs
        const body_frame_idx = self.call_stack.items.len - 1;
        for (func.handle_defs) |*hd| {
            self.handler_stack.append(self.gpa, .{
                .effect = hd.effect,
                .handle_def = hd,
                .func = func,
                .stack_depth = body_frame_idx,
                .return_dst = return_dst,
            }) catch return error.OutOfMemory;
        }
    }

    // ── Main loop ───────────────────────────────────────────────────

    fn run(self: *Interpreter) InterpreterError!Value {
        while (self.call_stack.items.len > 0) {
            try self.step();
        }
        return self.final_value;
    }

    fn step(self: *Interpreter) InterpreterError!void {
        const frame_idx = self.call_stack.items.len - 1;
        const frame = &self.call_stack.items[frame_idx];
        const block = &frame.func.blocks[frame.block_idx];

        if (frame.inst_idx < block.insts.len) {
            const inst = &block.insts[frame.inst_idx];
            frame.inst_idx += 1;
            try self.execInst(inst, frame_idx);
        } else {
            try self.execTerminator(block.terminator, frame);
        }
    }

    // ── Instruction execution ───────────────────────────────────────

    fn resolve(frame: *const CallFrame, vid: ir.ValueId) Value {
        return frame.env[vid.index()];
    }

    fn bind(frame: *CallFrame, vid: ir.ValueId, val: Value) void {
        frame.env[vid.index()] = val;
    }

    fn execInst(self: *Interpreter, inst: *const ir.Inst, frame_idx: usize) InterpreterError!void {
        const frame = &self.call_stack.items[frame_idx];
        const val: Value = switch (inst.op) {
            .const_int => |v| .{ .int = v },
            .const_float => |v| .{ .float = v },
            .const_string => |v| .{ .string = self.pool.get(v) },
            .const_bool => |v| .{ .bool_val = v },
            .const_nil => .nil,

            .binary => |v| try self.execBinary(v.op, resolve(frame, v.lhs), resolve(frame, v.rhs)),
            .unary => |v| try execUnary(v.op, resolve(frame, v.operand)),

            .record_init => |v| try self.execRecordInit(v.fields, frame),
            .record_field => |v| try self.execRecordField(resolve(frame, v.record), v.field),
            .record_update => |v| try self.execRecordUpdate(resolve(frame, v.base), v.updates, frame),

            .tag_init => |v| try self.execTagInit(v.tag, if (v.payload) |p| resolve(frame, p) else null),
            .tag_test => |v| execTagTest(resolve(frame, v.value), v.tag),
            .tag_payload => |v| try execTagPayload(resolve(frame, v.value), v.tag),

            .list_init => |v| try self.execListInit(v.elements, frame),

            .call => |v| try self.execCall(resolve(frame, v.callee), v.args, frame, inst.result),
            .call_direct => |v| try self.execCallDirect(v.func, v.args, frame, inst.result),
            .call_builtin => |v| try self.execCallBuiltin(v.name, v.args, frame),
            .closure => |v| try self.execClosure(v.func, v.captures, frame),

            .perform => |v| try self.execPerform(v.effect, v.op, v.args, frame, inst.result),

            .retain => |v| blk: {
                retainValue(resolve(frame, v));
                break :blk resolve(frame, v);
            },
            .release => |v| blk: {
                releaseValue(resolve(frame, v));
                break :blk .nil;
            },
            .copy => |v| try self.copyValue(resolve(frame, v)),
        };

        // For call/call_direct/perform, return value is delivered asynchronously
        // (when the callee returns). Don't bind here if we pushed a frame or
        // the stack was restructured (perform).
        switch (inst.op) {
            .call, .call_direct, .perform => {
                // If the stack changed (new frame pushed, or frames restructured by perform),
                // the result will be bound later. Use index comparison instead of pointer.
                if (self.call_stack.items.len - 1 != frame_idx) {
                    return;
                }
                // Otherwise (e.g., builtin call via .call), bind normally
                const f = &self.call_stack.items[frame_idx];
                bind(f, inst.result, val);
            },
            else => {
                const f = &self.call_stack.items[frame_idx];
                bind(f, inst.result, val);
            },
        }
    }

    // ── Binary operations ───────────────────────────────────────────

    fn execBinary(self: *Interpreter, op: ir.BinaryOp, lhs: Value, rhs: Value) InterpreterError!Value {
        // Int × Int
        if (lhs == .int and rhs == .int) {
            const a = lhs.int;
            const b = rhs.int;
            return switch (op) {
                .add => .{ .int = a +% b },
                .sub => .{ .int = a -% b },
                .mul => .{ .int = a *% b },
                .div => if (b == 0) error.DivisionByZero else .{ .int = @divTrunc(a, b) },
                .mod => if (b == 0) error.DivisionByZero else .{ .int = @mod(a, b) },
                .eq => .{ .bool_val = a == b },
                .ne => .{ .bool_val = a != b },
                .lt => .{ .bool_val = a < b },
                .le => .{ .bool_val = a <= b },
                .gt => .{ .bool_val = a > b },
                .ge => .{ .bool_val = a >= b },
                .bit_and => .{ .int = a & b },
                .bit_or => .{ .int = a | b },
                .bit_xor => .{ .int = a ^ b },
                .shl => .{ .int = std.math.shlExact(i64, a, @intCast(@as(u6, @truncate(@as(u64, @bitCast(b)))))) catch a },
                .shr => .{ .int = a >> @intCast(@as(u6, @truncate(@as(u64, @bitCast(b))))) },
                .@"and", .@"or", .concat => error.TypeError,
            };
        }

        // Float × Float
        if (lhs == .float and rhs == .float) {
            const a = lhs.float;
            const b = rhs.float;
            return switch (op) {
                .add => .{ .float = a + b },
                .sub => .{ .float = a - b },
                .mul => .{ .float = a * b },
                .div => .{ .float = a / b },
                .mod => .{ .float = @mod(a, b) },
                .eq => .{ .bool_val = a == b },
                .ne => .{ .bool_val = a != b },
                .lt => .{ .bool_val = a < b },
                .le => .{ .bool_val = a <= b },
                .gt => .{ .bool_val = a > b },
                .ge => .{ .bool_val = a >= b },
                else => error.TypeError,
            };
        }

        // Bool × Bool
        if (lhs == .bool_val and rhs == .bool_val) {
            return switch (op) {
                .@"and" => .{ .bool_val = lhs.bool_val and rhs.bool_val },
                .@"or" => .{ .bool_val = lhs.bool_val or rhs.bool_val },
                .eq => .{ .bool_val = lhs.bool_val == rhs.bool_val },
                .ne => .{ .bool_val = lhs.bool_val != rhs.bool_val },
                else => error.TypeError,
            };
        }

        // String concat
        if (lhs == .string and rhs == .string and op == .concat) {
            const result = self.arena.alloc(u8, lhs.string.len + rhs.string.len) catch return error.OutOfMemory;
            @memcpy(result[0..lhs.string.len], lhs.string);
            @memcpy(result[lhs.string.len..], rhs.string);
            return .{ .string = result };
        }

        // String equality
        if (lhs == .string and rhs == .string) {
            return switch (op) {
                .eq => .{ .bool_val = std.mem.eql(u8, lhs.string, rhs.string) },
                .ne => .{ .bool_val = !std.mem.eql(u8, lhs.string, rhs.string) },
                else => error.TypeError,
            };
        }

        // Nil equality
        if (lhs == .nil and rhs == .nil) {
            return switch (op) {
                .eq => .{ .bool_val = true },
                .ne => .{ .bool_val = false },
                else => error.TypeError,
            };
        }

        // Cross-type equality: different types are never equal.
        // This handles tagged vs nil, record vs nil, list vs nil, etc.
        if (op == .eq) return .{ .bool_val = false };
        if (op == .ne) return .{ .bool_val = true };

        return error.TypeError;
    }

    // ── Unary operations ────────────────────────────────────────────

    fn execUnary(op: ir.UnaryOp, operand: Value) InterpreterError!Value {
        return switch (op) {
            .neg => switch (operand) {
                .int => |v| .{ .int = -%v },
                .float => |v| .{ .float = -v },
                else => error.TypeError,
            },
            .not => switch (operand) {
                .bool_val => |v| .{ .bool_val = !v },
                else => error.TypeError,
            },
            .bit_not => switch (operand) {
                .int => |v| .{ .int = ~v },
                else => error.TypeError,
            },
        };
    }

    // ── Record operations ───────────────────────────────────────────

    fn execRecordInit(self: *Interpreter, fields: []const ir.FieldInit, frame: *const CallFrame) InterpreterError!Value {
        const entries = self.arena.alloc(FieldEntry, fields.len) catch return error.OutOfMemory;
        for (fields, 0..) |f, i| {
            entries[i] = .{ .name = f.name, .value = resolve(frame, f.value) };
        }
        const rec = self.arena.create(RecordValue) catch return error.OutOfMemory;
        rec.* = .{ .fields = entries };
        return .{ .record = rec };
    }

    fn execRecordField(self: *const Interpreter, record_val: Value, field: InternedString) InterpreterError!Value {
        _ = self;
        const rec = switch (record_val) {
            .record => |r| r,
            else => return error.TypeError,
        };
        for (rec.fields) |f| {
            if (f.name == field) return f.value;
        }
        return error.FieldNotFound;
    }

    fn execRecordUpdate(self: *Interpreter, base_val: Value, updates: []const ir.FieldInit, frame: *const CallFrame) InterpreterError!Value {
        const base = switch (base_val) {
            .record => |r| r,
            else => return error.TypeError,
        };
        const entries = self.arena.alloc(FieldEntry, base.fields.len) catch return error.OutOfMemory;
        @memcpy(entries, base.fields);

        for (updates) |u| {
            var found = false;
            for (entries) |*e| {
                if (e.name == u.name) {
                    e.value = resolve(frame, u.value);
                    found = true;
                    break;
                }
            }
            if (!found) return error.FieldNotFound;
        }
        const rec = self.arena.create(RecordValue) catch return error.OutOfMemory;
        rec.* = .{ .fields = entries };
        return .{ .record = rec };
    }

    // ── Tag operations ──────────────────────────────────────────────

    fn execTagInit(self: *Interpreter, tag: InternedString, payload: ?Value) InterpreterError!Value {
        const tv = self.arena.create(TaggedValue) catch return error.OutOfMemory;
        tv.* = .{ .tag = tag, .payload = payload };
        return .{ .tagged = tv };
    }

    fn execTagTest(value: Value, tag: InternedString) Value {
        return switch (value) {
            .tagged => |tv| .{ .bool_val = tv.tag == tag },
            else => .{ .bool_val = false },
        };
    }

    fn execTagPayload(value: Value, tag: InternedString) InterpreterError!Value {
        const tv = switch (value) {
            .tagged => |t| t,
            else => return error.TypeError,
        };
        if (tv.tag != tag) return error.TagMismatch;
        return tv.payload orelse .nil;
    }

    // ── List operations ─────────────────────────────────────────────

    fn execListInit(self: *Interpreter, elements: []const ir.ValueId, frame: *const CallFrame) InterpreterError!Value {
        const items = self.arena.alloc(Value, elements.len) catch return error.OutOfMemory;
        for (elements, 0..) |eid, i| {
            items[i] = resolve(frame, eid);
        }
        const lv = self.arena.create(ListValue) catch return error.OutOfMemory;
        lv.* = .{ .items = items };
        return .{ .list = lv };
    }

    // ── Closure ─────────────────────────────────────────────────────

    fn execClosure(self: *Interpreter, func_id: ir.FuncId, captures: []const ir.ValueId, frame: *const CallFrame) InterpreterError!Value {
        const caps = self.arena.alloc(Value, captures.len) catch return error.OutOfMemory;
        for (captures, 0..) |c, i| {
            caps[i] = resolve(frame, c);
        }
        const cv = self.arena.create(ClosureValue) catch return error.OutOfMemory;
        cv.* = .{ .func = func_id, .captures = caps };
        return .{ .closure = cv };
    }

    // ── Call operations ─────────────────────────────────────────────

    fn execCallDirect(self: *Interpreter, func_id: ir.FuncId, arg_ids: []const ir.ValueId, frame: *CallFrame, result_dst: ir.ValueId) InterpreterError!Value {
        const args = self.resolveArgs(arg_ids, frame) catch return error.OutOfMemory;
        defer self.gpa.free(args);
        const target = &self.module.funcs[func_id.index()];
        try self.pushFrame(target, args, result_dst);
        return .nil; // placeholder — actual return delivered via popFrame
    }

    fn execCall(self: *Interpreter, callee: Value, arg_ids: []const ir.ValueId, frame: *CallFrame, result_dst: ir.ValueId) InterpreterError!Value {
        return switch (callee) {
            .closure => |cv| {
                const target = &self.module.funcs[cv.func.index()];
                // Build args: captures first, then call args
                const total = cv.captures.len + arg_ids.len;
                const args = self.gpa.alloc(Value, total) catch return error.OutOfMemory;
                defer self.gpa.free(args);
                @memcpy(args[0..cv.captures.len], cv.captures);
                for (arg_ids, 0..) |aid, i| {
                    args[cv.captures.len + i] = resolve(frame, aid);
                }
                try self.pushFrame(target, args, result_dst);
                return .nil;
            },
            .builtin_fn => |opaque_fn| {
                const bfn: BuiltinFn = @ptrCast(@alignCast(opaque_fn));
                const args = self.resolveArgs(arg_ids, frame) catch return error.OutOfMemory;
                defer self.gpa.free(args);
                return bfn(args, @ptrCast(self));
            },
            .continuation => |cont| {
                return self.execResume(cont, arg_ids, frame, result_dst);
            },
            else => error.TypeError,
        };
    }

    fn execCallBuiltin(self: *Interpreter, name: InternedString, arg_ids: []const ir.ValueId, frame: *const CallFrame) InterpreterError!Value {
        const name_str = self.pool.get(name);
        const bfn = self.builtins.get(name_str) orelse return error.TypeError;
        const args = self.resolveArgs(arg_ids, frame) catch return error.OutOfMemory;
        defer self.gpa.free(args);
        return bfn(args, @ptrCast(self));
    }

    fn resolveArgs(self: *Interpreter, arg_ids: []const ir.ValueId, frame: *const CallFrame) Allocator.Error![]Value {
        const args = try self.gpa.alloc(Value, arg_ids.len);
        for (arg_ids, 0..) |aid, i| {
            args[i] = resolve(frame, aid);
        }
        return args;
    }

    // ── Perform / Resume ────────────────────────────────────────────

    fn execPerform(self: *Interpreter, effect: InternedString, op: InternedString, arg_ids: []const ir.ValueId, frame: *CallFrame, result_dst: ir.ValueId) InterpreterError!Value {
        // Resolve args before we touch the stacks
        const args = self.resolveArgs(arg_ids, frame) catch return error.OutOfMemory;
        defer self.gpa.free(args);

        // Find matching handler (walk backwards = innermost first)
        var handler_idx: ?usize = null;
        {
            var i: usize = self.handler_stack.items.len;
            while (i > 0) {
                i -= 1;
                if (self.handler_stack.items[i].effect == effect) {
                    handler_idx = i;
                    break;
                }
            }
        }

        const hidx = handler_idx orelse return error.UnhandledEffect;
        const hframe = self.handler_stack.items[hidx];
        const hdef = hframe.handle_def;

        // Find matching clause
        for (hdef.clauses) |clause| {
            if (clause.op == op) {
                // Capture continuation: all frames from handler's body frame to top
                const depth = hframe.stack_depth;
                const captured_slice = self.call_stack.items[depth..];
                const cont_frames = self.arena.alloc(CallFrame, captured_slice.len) catch return error.OutOfMemory;
                @memcpy(cont_frames, captured_slice);

                // Capture inner handlers (those installed after the matched one)
                const inner_handlers = self.handler_stack.items[hidx + 1 ..];
                const cont_handlers = self.arena.alloc(HandlerFrame, inner_handlers.len) catch return error.OutOfMemory;
                @memcpy(cont_handlers, inner_handlers);

                const cont = self.arena.create(Continuation) catch return error.OutOfMemory;
                cont.* = .{
                    .frames = cont_frames,
                    .handlers = cont_handlers,
                    .perform_result = result_dst,
                };

                // Pop frames down to handler depth (don't free envs — they're in the continuation)
                self.call_stack.items.len = depth;

                // Pop matched handler and all inner handlers
                self.handler_stack.items.len = hidx;

                // Push clause frame
                const clause_env = self.gpa.alloc(Value, hframe.func.value_count) catch return error.OutOfMemory;
                @memset(clause_env, Value.uninit);

                // Bind clause params (operation args)
                for (clause.params, 0..) |param, pi| {
                    if (pi < args.len) {
                        clause_env[param.index()] = args[pi];
                    }
                }
                // Bind continuation to resume_param
                clause_env[clause.resume_param.index()] = .{ .continuation = cont };

                self.call_stack.append(self.gpa, .{
                    .func = hframe.func,
                    .block_idx = clause.body.index(),
                    .inst_idx = 0,
                    .env = clause_env,
                    .return_dst = hframe.return_dst,
                }) catch return error.OutOfMemory;

                return .nil;
            }
        }

        return error.UnhandledEffect;
    }

    fn execResume(self: *Interpreter, cont: *Continuation, arg_ids: []const ir.ValueId, frame: *const CallFrame, result_dst: ir.ValueId) InterpreterError!Value {
        if (cont.consumed) return error.ContinuationConsumed;
        cont.consumed = true;

        // Resolve the resume argument before modifying stacks
        const resume_val: Value = if (arg_ids.len > 0) resolve(frame, arg_ids[0]) else .nil;

        // Restore captured handlers
        for (cont.handlers) |hf| {
            self.handler_stack.append(self.gpa, hf) catch return error.OutOfMemory;
        }

        // Push captured frames back (copy envs so continuation can't alias them)
        const base_idx = self.call_stack.items.len;
        for (cont.frames) |cf| {
            const env_copy = self.gpa.alloc(Value, cf.env.len) catch return error.OutOfMemory;
            @memcpy(env_copy, cf.env);
            self.call_stack.append(self.gpa, .{
                .func = cf.func,
                .block_idx = cf.block_idx,
                .inst_idx = cf.inst_idx,
                .env = env_copy,
                .return_dst = cf.return_dst,
            }) catch return error.OutOfMemory;
        }

        // The bottom restored frame's return_dst must point back to the
        // resume call site so the body's return value flows to resume's result.
        if (cont.frames.len > 0) {
            self.call_stack.items[base_idx].return_dst = result_dst;
        }

        // Bind resume argument to the perform's result ValueId in the top restored frame
        const top = &self.call_stack.items[self.call_stack.items.len - 1];
        top.env[cont.perform_result.index()] = resume_val;

        return .nil;
    }

    // ── RC operations ───────────────────────────────────────────────

    fn retainValue(val: Value) void {
        switch (val) {
            .list => |v| v.ref_count += 1,
            .record => |v| v.ref_count += 1,
            .tagged => |v| v.ref_count += 1,
            .closure => |v| v.ref_count += 1,
            .continuation => |v| v.ref_count += 1,
            .map => |v| v.ref_count += 1,
            .bytes => |v| v.ref_count += 1,
            else => {},
        }
    }

    fn releaseValue(val: Value) void {
        switch (val) {
            .list => |v| {
                if (v.ref_count > 0) v.ref_count -= 1;
            },
            .record => |v| {
                if (v.ref_count > 0) v.ref_count -= 1;
            },
            .tagged => |v| {
                if (v.ref_count > 0) v.ref_count -= 1;
            },
            .closure => |v| {
                if (v.ref_count > 0) v.ref_count -= 1;
            },
            .continuation => |v| {
                if (v.ref_count > 0) v.ref_count -= 1;
            },
            .map => |v| {
                if (v.ref_count > 0) v.ref_count -= 1;
            },
            .bytes => |v| {
                if (v.ref_count > 0) v.ref_count -= 1;
            },
            else => {},
        }
    }

    fn copyValue(self: *Interpreter, val: Value) InterpreterError!Value {
        return switch (val) {
            .int, .float, .bool_val, .string, .nil, .builtin_fn => val,
            .list => |v| {
                const items = self.arena.alloc(Value, v.items.len) catch return error.OutOfMemory;
                @memcpy(items, v.items);
                const new = self.arena.create(ListValue) catch return error.OutOfMemory;
                new.* = .{ .items = items };
                return .{ .list = new };
            },
            .record => |v| {
                const entries = self.arena.alloc(FieldEntry, v.fields.len) catch return error.OutOfMemory;
                @memcpy(entries, v.fields);
                const new = self.arena.create(RecordValue) catch return error.OutOfMemory;
                new.* = .{ .fields = entries };
                return .{ .record = new };
            },
            .tagged => |v| {
                const new = self.arena.create(TaggedValue) catch return error.OutOfMemory;
                new.* = .{ .tag = v.tag, .payload = v.payload };
                return .{ .tagged = new };
            },
            .closure => |v| {
                const caps = self.arena.alloc(Value, v.captures.len) catch return error.OutOfMemory;
                @memcpy(caps, v.captures);
                const new = self.arena.create(ClosureValue) catch return error.OutOfMemory;
                new.* = .{ .func = v.func, .captures = caps };
                return .{ .closure = new };
            },
            .continuation, .map, .bytes => val, // shallow copy for now
        };
    }

    // ── Terminator execution ────────────────────────────────────────

    fn execTerminator(self: *Interpreter, term: ir.Terminator, frame: *CallFrame) InterpreterError!void {
        switch (term) {
            .ret => |vid| {
                const ret_val = if (vid) |v| resolve(frame, v) else Value.nil;
                try self.popFrame(ret_val);
            },
            .jump => |j| {
                const target_block = &frame.func.blocks[j.target.index()];
                // Resolve ALL args before binding ANY params (phi-node semantics).
                // This prevents aliasing bugs where a jump arg references a ValueId
                // that was already overwritten by an earlier block param binding.
                var resolved_args: [16]Value = undefined;
                const n_args = @min(j.args.len, target_block.params.len);
                for (0..n_args) |i| {
                    resolved_args[i] = resolve(frame, j.args[i]);
                }
                for (target_block.params, 0..) |param, i| {
                    if (i < n_args) {
                        bind(frame, param, resolved_args[i]);
                    }
                }
                frame.block_idx = j.target.index();
                frame.inst_idx = 0;
            },
            .branch => |b| {
                const cond = resolve(frame, b.cond);
                const taken = switch (cond) {
                    .bool_val => |v| v,
                    else => return error.TypeError,
                };
                const target = if (taken) b.then_block else b.else_block;
                frame.block_idx = target.index();
                frame.inst_idx = 0;
            },
            .switch_tag => |s| {
                const val = resolve(frame, s.value);
                const tv = switch (val) {
                    .tagged => |t| t,
                    else => return error.TypeError,
                };
                for (s.cases) |case| {
                    if (case.tag == tv.tag) {
                        frame.block_idx = case.target.index();
                        frame.inst_idx = 0;
                        return;
                    }
                }
                if (s.default) |d| {
                    frame.block_idx = d.index();
                    frame.inst_idx = 0;
                } else {
                    return error.TagMismatch;
                }
            },
            .unreachable_term => return error.UnreachableReached,
        }
    }

    fn popFrame(self: *Interpreter, ret_val: Value) InterpreterError!void {
        const old = self.call_stack.pop().?;
        self.gpa.free(old.env);

        const new_depth = self.call_stack.items.len;

        // Check if any handler's body just returned (handler's body frame was at new_depth)
        var handler_found: ?usize = null;
        for (self.handler_stack.items, 0..) |hf, hi| {
            if (hf.stack_depth == new_depth) {
                handler_found = hi;
                break;
            }
        }

        if (handler_found) |hidx| {
            const hframe = self.handler_stack.items[hidx];
            // Remove handler
            _ = self.handler_stack.orderedRemove(hidx);

            if (hframe.handle_def.return_clause) |rc| {
                // Run return clause: transform the body's return value
                const rc_env = self.gpa.alloc(Value, hframe.func.value_count) catch return error.OutOfMemory;
                @memset(rc_env, Value.uninit);
                rc_env[rc.param.index()] = ret_val;

                self.call_stack.append(self.gpa, .{
                    .func = hframe.func,
                    .block_idx = rc.body.index(),
                    .inst_idx = 0,
                    .env = rc_env,
                    .return_dst = hframe.return_dst,
                }) catch return error.OutOfMemory;
            } else {
                // No return clause — deliver directly
                if (self.call_stack.items.len > 0) {
                    if (hframe.return_dst) |dst| {
                        const caller = &self.call_stack.items[self.call_stack.items.len - 1];
                        bind(caller, dst, ret_val);
                    }
                } else {
                    self.final_value = ret_val;
                }
            }
        } else {
            // Normal return — no handler involved
            if (self.call_stack.items.len > 0) {
                if (old.return_dst) |dst| {
                    const caller = &self.call_stack.items[self.call_stack.items.len - 1];
                    bind(caller, dst, ret_val);
                }
            } else {
                self.final_value = ret_val;
            }
        }
    }

};

// ── Tests ───────────────────────────────────────────────────────────────

/// Test harness: wraps builder + pool + interp in a single arena so
/// all IR allocations are cleaned up automatically.
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

    fn run(self: *TestHarness, module: ir.Module, fid: ir.FuncId, args: []const Value) InterpreterError!Value {
        // Use the backing arena so returned heap values survive past run()
        const alloc = self.backing.allocator();
        var interp = Interpreter.init(alloc, module, &self.pool);
        defer interp.deinit();
        return interp.execFunc(fid, args);
    }
};

test "interp: const int return" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "main"));
    _ = b.beginBlock();
    const v = try b.addInst(.{ .const_int = 42 });
    try b.endBlock(.{ .ret = v });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "interp: const float return" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const v = try b.addInst(.{ .const_float = 3.14 });
    try b.endBlock(.{ .ret = v });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), result.float, 0.001);
}

test "interp: const bool, string, nil" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const hello = try pool.intern(alloc, "hello");
    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    _ = try b.addInst(.{ .const_bool = true });
    _ = try b.addInst(.{ .const_string = hello });
    const v = try b.addInst(.const_nil);
    try b.endBlock(.{ .ret = v });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expect(result == .nil);
}

test "interp: binary add" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_int = 10 });
    const bv = try b.addInst(.{ .const_int = 32 });
    const sum = try b.addInst(.{ .binary = .{ .op = .add, .lhs = a, .rhs = bv } });
    try b.endBlock(.{ .ret = sum });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "interp: division by zero" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_int = 10 });
    const bv = try b.addInst(.{ .const_int = 0 });
    const div = try b.addInst(.{ .binary = .{ .op = .div, .lhs = a, .rhs = bv } });
    try b.endBlock(.{ .ret = div });
    const fid = try b.endFunc();

    const result = h.run(try b.build(fid), fid, &.{});
    try std.testing.expectError(error.DivisionByZero, result);
}

test "interp: unary neg and not" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_int = 5 });
    const neg = try b.addInst(.{ .unary = .{ .op = .neg, .operand = a } });
    try b.endBlock(.{ .ret = neg });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, -5), result.int);
}

test "interp: record init and field access" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const field_x = try pool.intern(alloc, "x");
    const field_y = try pool.intern(alloc, "y");

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const vx = try b.addInst(.{ .const_int = 10 });
    const vy = try b.addInst(.{ .const_int = 20 });
    const rec = try b.addInst(.{ .record_init = .{ .fields = &.{
        .{ .name = field_x, .value = vx },
        .{ .name = field_y, .value = vy },
    } } });
    const got = try b.addInst(.{ .record_field = .{ .record = rec, .field = field_y } });
    try b.endBlock(.{ .ret = got });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 20), result.int);
}

test "interp: record update" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const field_x = try pool.intern(alloc, "x");

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const v1 = try b.addInst(.{ .const_int = 10 });
    const rec = try b.addInst(.{ .record_init = .{ .fields = &.{
        .{ .name = field_x, .value = v1 },
    } } });
    const v2 = try b.addInst(.{ .const_int = 99 });
    const rec2 = try b.addInst(.{ .record_update = .{ .base = rec, .updates = &.{
        .{ .name = field_x, .value = v2 },
    } } });
    const got = try b.addInst(.{ .record_field = .{ .record = rec2, .field = field_x } });
    try b.endBlock(.{ .ret = got });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 99), result.int);
}

test "interp: tag init, test, payload" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const tag_some = try pool.intern(alloc, "Some");
    const tag_none = try pool.intern(alloc, "None");
    _ = tag_none;

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const payload = try b.addInst(.{ .const_int = 42 });
    const tagged = try b.addInst(.{ .tag_init = .{ .tag = tag_some, .payload = payload } });
    _ = try b.addInst(.{ .tag_test = .{ .value = tagged, .tag = tag_some } });
    const got = try b.addInst(.{ .tag_payload = .{ .value = tagged, .tag = tag_some } });
    try b.endBlock(.{ .ret = got });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "interp: list init" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_int = 1 });
    const bv = try b.addInst(.{ .const_int = 2 });
    const c = try b.addInst(.{ .const_int = 3 });
    const lst = try b.addInst(.{ .list_init = .{ .elements = &.{ a, bv, c } } });
    try b.endBlock(.{ .ret = lst });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(usize, 3), result.list.items.len);
    try std.testing.expectEqual(@as(i64, 2), result.list.items[1].int);
}

test "interp: string concat" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const hello = try pool.intern(alloc, "hello ");
    const world = try pool.intern(alloc, "world");

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_string = hello });
    const bv = try b.addInst(.{ .const_string = world });
    const cat = try b.addInst(.{ .binary = .{ .op = .concat, .lhs = a, .rhs = bv } });
    try b.endBlock(.{ .ret = cat });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqualStrings("hello world", result.string);
}

test "interp: boolean and/or" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const t = try b.addInst(.{ .const_bool = true });
    const f = try b.addInst(.{ .const_bool = false });
    _ = try b.addInst(.{ .binary = .{ .op = .@"and", .lhs = t, .rhs = f } });
    const or_val = try b.addInst(.{ .binary = .{ .op = .@"or", .lhs = t, .rhs = f } });
    try b.endBlock(.{ .ret = or_val });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expect(result.bool_val);
}

test "interp: float arithmetic" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_float = 3.0 });
    const bv = try b.addInst(.{ .const_float = 1.5 });
    const mul = try b.addInst(.{ .binary = .{ .op = .mul, .lhs = a, .rhs = bv } });
    try b.endBlock(.{ .ret = mul });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectApproxEqAbs(@as(f64, 4.5), result.float, 0.001);
}

test "interp: comparison ops" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_int = 5 });
    const bv = try b.addInst(.{ .const_int = 10 });
    const lt = try b.addInst(.{ .binary = .{ .op = .lt, .lhs = a, .rhs = bv } });
    try b.endBlock(.{ .ret = lt });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expect(result.bool_val);
}

test "interp: type error on mismatched binary" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_int = 5 });
    const bv = try b.addInst(.{ .const_bool = true });
    const bad = try b.addInst(.{ .binary = .{ .op = .add, .lhs = a, .rhs = bv } });
    try b.endBlock(.{ .ret = bad });
    const fid = try b.endFunc();

    const result = h.run(try b.build(fid), fid, &.{});
    try std.testing.expectError(error.TypeError, result);
}

test "interp: ret nil (void return)" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    try b.endBlock(.{ .ret = null });
    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expect(result == .nil);
}

test "interp: direct function call" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    // Helper function: returns 100
    b.beginFunc(try pool.intern(alloc, "helper"));
    _ = try b.addParam();
    _ = b.beginBlock();
    const rv = try b.addInst(.{ .const_int = 100 });
    try b.endBlock(.{ .ret = rv });
    const helper_fid = try b.endFunc();

    // Main function: calls helper
    b.beginFunc(try pool.intern(alloc, "main"));
    _ = b.beginBlock();
    const arg = try b.addInst(.{ .const_int = 0 });
    const result = try b.addInst(.{ .call_direct = .{ .func = helper_fid, .args = &.{arg} } });
    try b.endBlock(.{ .ret = result });
    const main_fid = try b.endFunc();

    const val = try h.run(try b.build(main_fid), main_fid, &.{});
    try std.testing.expectEqual(@as(i64, 100), val.int);
}

test "interp: branch true/false" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const cond = try b.addInst(.{ .const_bool = true });
    try b.endBlock(.{ .branch = .{ .cond = cond, .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } });

    _ = b.beginBlock();
    const v_then = try b.addInst(.{ .const_int = 1 });
    try b.endBlock(.{ .ret = v_then });

    _ = b.beginBlock();
    const v_else = try b.addInst(.{ .const_int = 2 });
    try b.endBlock(.{ .ret = v_else });

    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 1), result.int);
}

test "interp: jump with block params (loop)" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    // Sum 1..5 using a loop with block params
    b.beginFunc(try pool.intern(alloc, "sum"));

    _ = b.beginBlock();
    const init_i = try b.addInst(.{ .const_int = 1 });
    const init_acc = try b.addInst(.{ .const_int = 0 });
    try b.endBlock(.{ .jump = .{ .target = @enumFromInt(1), .args = &.{ init_i, init_acc } } });

    _ = b.beginBlock();
    const i_param = try b.addBlockParam();
    const acc_param = try b.addBlockParam();
    const five = try b.addInst(.{ .const_int = 5 });
    const done = try b.addInst(.{ .binary = .{ .op = .gt, .lhs = i_param, .rhs = five } });
    try b.endBlock(.{ .branch = .{ .cond = done, .then_block = @enumFromInt(2), .else_block = @enumFromInt(3) } });

    _ = b.beginBlock();
    try b.endBlock(.{ .ret = acc_param });

    _ = b.beginBlock();
    const one = try b.addInst(.{ .const_int = 1 });
    const next_i = try b.addInst(.{ .binary = .{ .op = .add, .lhs = i_param, .rhs = one } });
    const next_acc = try b.addInst(.{ .binary = .{ .op = .add, .lhs = acc_param, .rhs = i_param } });
    try b.endBlock(.{ .jump = .{ .target = @enumFromInt(1), .args = &.{ next_i, next_acc } } });

    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 15), result.int);
}

test "interp: switch_tag dispatch" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const tag_a = try pool.intern(alloc, "A");
    const tag_b = try pool.intern(alloc, "B");

    b.beginFunc(try pool.intern(alloc, "f"));

    _ = b.beginBlock();
    const payload = try b.addInst(.{ .const_int = 99 });
    const tagged = try b.addInst(.{ .tag_init = .{ .tag = tag_b, .payload = payload } });
    try b.endBlock(.{ .switch_tag = .{
        .value = tagged,
        .cases = &.{
            .{ .tag = tag_a, .target = @enumFromInt(1) },
            .{ .tag = tag_b, .target = @enumFromInt(2) },
        },
        .default = null,
    } });

    _ = b.beginBlock();
    const va = try b.addInst(.{ .const_int = 1 });
    try b.endBlock(.{ .ret = va });

    _ = b.beginBlock();
    const vb = try b.addInst(.{ .const_int = 2 });
    try b.endBlock(.{ .ret = vb });

    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 2), result.int);
}

test "interp: unreachable error" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    try b.endBlock(.unreachable_term);
    const fid = try b.endFunc();

    const result = h.run(try b.build(fid), fid, &.{});
    try std.testing.expectError(error.UnreachableReached, result);
}

test "interp: builtin call" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const add_name = try pool.intern(alloc, "test_add");
    b.beginFunc(try pool.intern(alloc, "main"));
    _ = b.beginBlock();
    const a = try b.addInst(.{ .const_int = 3 });
    const bv = try b.addInst(.{ .const_int = 7 });
    const result = try b.addInst(.{ .call_builtin = .{ .name = add_name, .args = &.{ a, bv } } });
    try b.endBlock(.{ .ret = result });
    const fid = try b.endFunc();
    const module = try b.build(fid);

    const ialloc = h.backing.allocator();
    var interp = Interpreter.init(ialloc, module, &h.pool);
    defer interp.deinit();

    try interp.registerBuiltin("test_add", struct {
        fn call(args: []const Value, _: *anyopaque) InterpreterError!Value {
            return .{ .int = args[0].int + args[1].int };
        }
    }.call);

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 10), val.int);
}

test "interp: closure capture and call" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "adder"));
    const cap = try b.addParam();
    const arg = try b.addParam();
    _ = b.beginBlock();
    const sum = try b.addInst(.{ .binary = .{ .op = .add, .lhs = cap, .rhs = arg } });
    try b.endBlock(.{ .ret = sum });
    const adder_fid = try b.endFunc();

    b.beginFunc(try pool.intern(alloc, "main"));
    _ = b.beginBlock();
    const ten = try b.addInst(.{ .const_int = 10 });
    const cls = try b.addInst(.{ .closure = .{ .func = adder_fid, .captures = &.{ten} } });
    const call_arg = try b.addInst(.{ .const_int = 32 });
    const result = try b.addInst(.{ .call = .{ .callee = cls, .args = &.{call_arg} } });
    try b.endBlock(.{ .ret = result });
    const main_fid = try b.endFunc();

    const val = try h.run(try b.build(main_fid), main_fid, &.{});
    try std.testing.expectEqual(@as(i64, 42), val.int);
}

test "interp: recursive factorial" {
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    b.beginFunc(try pool.intern(alloc, "fact"));
    const n = try b.addParam();

    _ = b.beginBlock();
    const one = try b.addInst(.{ .const_int = 1 });
    const cond = try b.addInst(.{ .binary = .{ .op = .le, .lhs = n, .rhs = one } });
    try b.endBlock(.{ .branch = .{ .cond = cond, .then_block = @enumFromInt(1), .else_block = @enumFromInt(2) } });

    _ = b.beginBlock();
    const one2 = try b.addInst(.{ .const_int = 1 });
    try b.endBlock(.{ .ret = one2 });

    _ = b.beginBlock();
    const one3 = try b.addInst(.{ .const_int = 1 });
    const nm1 = try b.addInst(.{ .binary = .{ .op = .sub, .lhs = n, .rhs = one3 } });
    const fact_fid: ir.FuncId = @enumFromInt(0);
    const sub_result = try b.addInst(.{ .call_direct = .{ .func = fact_fid, .args = &.{nm1} } });
    const product = try b.addInst(.{ .binary = .{ .op = .mul, .lhs = n, .rhs = sub_result } });
    try b.endBlock(.{ .ret = product });

    const fid = try b.endFunc();

    const result = try h.run(try b.build(fid), fid, &.{.{ .int = 5 }});
    try std.testing.expectEqual(@as(i64, 120), result.int);
}

// ── Stage 5: Effects + Handlers + Continuations ─────────────────────────

test "interp: perform + resume (State.get)" {
    // Handler function that:
    //   body (block 0): result = perform State.get(); return result
    //   clause (block 1): resume(42)
    // Expected: body gets 42 from perform, returns it
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const eff_state = try pool.intern(alloc, "State");
    const op_get = try pool.intern(alloc, "get");

    b.beginFunc(try pool.intern(alloc, "handled"));

    // Block 0: body — perform State.get(), return result
    _ = b.beginBlock();
    const perf_result = try b.addInst(.{ .perform = .{ .effect = eff_state, .op = op_get, .args = &.{} } });
    try b.endBlock(.{ .ret = perf_result });

    // Block 1: clause body — resume(42)
    _ = b.beginBlock();
    const val_42 = try b.addInst(.{ .const_int = 42 });
    // resume_param is a ValueId that holds the continuation
    const resume_param = b.freshValue();
    const resume_result = try b.addInst(.{ .call = .{ .callee = resume_param, .args = &.{val_42} } });
    try b.endBlock(.{ .ret = resume_result });

    // Clause param (for op args — State.get has none, but we need a slot)
    const clause_param = b.freshValue();
    _ = clause_param;

    try b.func_handle_defs.append(alloc, .{
        .body_block = @enumFromInt(0),
        .effect = eff_state,
        .clauses = &.{.{
            .op = op_get,
            .params = &.{},
            .resume_param = resume_param,
            .body = @enumFromInt(1),
        }},
        .return_clause = null,
    });

    const fid = try b.endFunc();
    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "interp: non-resumption (Fail/exception)" {
    // Handler that catches a Fail effect and returns a default value
    //   body (block 0): perform Fail.fail(99); return 0  (never reached)
    //   clause (block 1): return -1  (doesn't resume)
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const eff_fail = try pool.intern(alloc, "Fail");
    const op_fail = try pool.intern(alloc, "fail");

    b.beginFunc(try pool.intern(alloc, "handled"));

    // Block 0: body — perform Fail.fail(99); return 0
    _ = b.beginBlock();
    const err_val = try b.addInst(.{ .const_int = 99 });
    _ = try b.addInst(.{ .perform = .{ .effect = eff_fail, .op = op_fail, .args = &.{err_val} } });
    const zero = try b.addInst(.{ .const_int = 0 });
    try b.endBlock(.{ .ret = zero });

    // Block 1: clause body — return -1 (no resume)
    _ = b.beginBlock();
    const neg_one = try b.addInst(.{ .const_int = -1 });
    try b.endBlock(.{ .ret = neg_one });

    const resume_param = b.freshValue();
    const err_param = b.freshValue();

    try b.func_handle_defs.append(alloc, .{
        .body_block = @enumFromInt(0),
        .effect = eff_fail,
        .clauses = &.{.{
            .op = op_fail,
            .params = &.{err_param},
            .resume_param = resume_param,
            .body = @enumFromInt(1),
        }},
        .return_clause = null,
    });

    const fid = try b.endFunc();
    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, -1), result.int);
}

test "interp: double resume error" {
    // Handler clause tries to resume twice — second should error
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const eff = try pool.intern(alloc, "Eff");
    const op = try pool.intern(alloc, "op");

    b.beginFunc(try pool.intern(alloc, "handled"));

    // Block 0: body — perform Eff.op(); return result
    _ = b.beginBlock();
    const perf = try b.addInst(.{ .perform = .{ .effect = eff, .op = op, .args = &.{} } });
    try b.endBlock(.{ .ret = perf });

    // Block 1: clause body — resume(1); resume(2)  <-- second should fail
    _ = b.beginBlock();
    const v1 = try b.addInst(.{ .const_int = 1 });
    const resume_param = b.freshValue();
    _ = try b.addInst(.{ .call = .{ .callee = resume_param, .args = &.{v1} } });
    const v2 = try b.addInst(.{ .const_int = 2 });
    const bad = try b.addInst(.{ .call = .{ .callee = resume_param, .args = &.{v2} } });
    try b.endBlock(.{ .ret = bad });

    try b.func_handle_defs.append(alloc, .{
        .body_block = @enumFromInt(0),
        .effect = eff,
        .clauses = &.{.{
            .op = op,
            .params = &.{},
            .resume_param = resume_param,
            .body = @enumFromInt(1),
        }},
        .return_clause = null,
    });

    const fid = try b.endFunc();
    const result = h.run(try b.build(fid), fid, &.{});
    try std.testing.expectError(error.ContinuationConsumed, result);
}

test "interp: unhandled effect error" {
    // perform with no handler installed
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const eff = try pool.intern(alloc, "Missing");
    const op = try pool.intern(alloc, "op");

    b.beginFunc(try pool.intern(alloc, "f"));
    _ = b.beginBlock();
    const perf = try b.addInst(.{ .perform = .{ .effect = eff, .op = op, .args = &.{} } });
    try b.endBlock(.{ .ret = perf });
    const fid = try b.endFunc();

    const result = h.run(try b.build(fid), fid, &.{});
    try std.testing.expectError(error.UnhandledEffect, result);
}

test "interp: return clause transforms body result" {
    // Handler with return_clause that doubles the body's return value
    //   body (block 0): return 21
    //   return_clause (block 1): return param * 2
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const eff = try pool.intern(alloc, "Eff");

    b.beginFunc(try pool.intern(alloc, "handled"));

    // Block 0: body — return 21
    _ = b.beginBlock();
    const v21 = try b.addInst(.{ .const_int = 21 });
    try b.endBlock(.{ .ret = v21 });

    // Block 1: return clause body — return param * 2
    _ = b.beginBlock();
    const ret_param = b.freshValue();
    const two = try b.addInst(.{ .const_int = 2 });
    const doubled = try b.addInst(.{ .binary = .{ .op = .mul, .lhs = ret_param, .rhs = two } });
    try b.endBlock(.{ .ret = doubled });

    try b.func_handle_defs.append(alloc, .{
        .body_block = @enumFromInt(0),
        .effect = eff,
        .clauses = &.{},
        .return_clause = .{ .param = ret_param, .body = @enumFromInt(1) },
    });

    const fid = try b.endFunc();
    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 42), result.int);
}

test "interp: perform passes args to handler clause" {
    // Body performs with an argument, clause receives it
    //   body (block 0): perform Log.log(100); return 0
    //   clause (block 1): return the arg (don't resume)
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const eff = try pool.intern(alloc, "Log");
    const op = try pool.intern(alloc, "log");

    b.beginFunc(try pool.intern(alloc, "handled"));

    // Block 0: body
    _ = b.beginBlock();
    const val_100 = try b.addInst(.{ .const_int = 100 });
    _ = try b.addInst(.{ .perform = .{ .effect = eff, .op = op, .args = &.{val_100} } });
    const zero = try b.addInst(.{ .const_int = 0 });
    try b.endBlock(.{ .ret = zero });

    // Block 1: clause body — return the arg
    _ = b.beginBlock();
    const clause_param = b.freshValue();
    const resume_param = b.freshValue();
    try b.endBlock(.{ .ret = clause_param });

    try b.func_handle_defs.append(alloc, .{
        .body_block = @enumFromInt(0),
        .effect = eff,
        .clauses = &.{.{
            .op = op,
            .params = &.{clause_param},
            .resume_param = resume_param,
            .body = @enumFromInt(1),
        }},
        .return_clause = null,
    });

    const fid = try b.endFunc();
    const result = try h.run(try b.build(fid), fid, &.{});
    try std.testing.expectEqual(@as(i64, 100), result.int);
}

test "interp: cross-function perform" {
    // Handler installed in outer function, perform happens in inner function
    //   func "inner" (func 0): perform State.get(); return result
    //   func "outer" (func 1): handled — body calls inner, handler resumes with 77
    var h = TestHarness.init();
    defer h.deinit();
    const alloc, const pool, var b = h.setup();

    const eff = try pool.intern(alloc, "State");
    const op_get = try pool.intern(alloc, "get");

    // func 0: inner — performs State.get() and returns it
    b.beginFunc(try pool.intern(alloc, "inner"));
    _ = b.beginBlock();
    const perf = try b.addInst(.{ .perform = .{ .effect = eff, .op = op_get, .args = &.{} } });
    try b.endBlock(.{ .ret = perf });
    const inner_fid = try b.endFunc();

    // func 1: outer — handled, body calls inner
    b.beginFunc(try pool.intern(alloc, "outer"));

    // Block 0: body — call inner, return its result
    _ = b.beginBlock();
    const call_result = try b.addInst(.{ .call_direct = .{ .func = inner_fid, .args = &.{} } });
    try b.endBlock(.{ .ret = call_result });

    // Block 1: clause body — resume(77)
    _ = b.beginBlock();
    const v77 = try b.addInst(.{ .const_int = 77 });
    const resume_p = b.freshValue();
    const resume_r = try b.addInst(.{ .call = .{ .callee = resume_p, .args = &.{v77} } });
    try b.endBlock(.{ .ret = resume_r });

    try b.func_handle_defs.append(alloc, .{
        .body_block = @enumFromInt(0),
        .effect = eff,
        .clauses = &.{.{
            .op = op_get,
            .params = &.{},
            .resume_param = resume_p,
            .body = @enumFromInt(1),
        }},
        .return_clause = null,
    });

    const outer_fid = try b.endFunc();
    const result = try h.run(try b.build(outer_fid), outer_fid, &.{});
    try std.testing.expectEqual(@as(i64, 77), result.int);
}
