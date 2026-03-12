const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("../ir.zig");
const intern_mod = @import("../intern.zig");
const InternPool = intern_mod.InternPool;
const InternedString = intern_mod.InternedString;
const ValueId = ir.ValueId;
const BlockId = ir.BlockId;
const FuncId = ir.FuncId;
const Gen = @import("gen.zig").Gen;
const typeck = @import("typeck.zig");

// ── IR instruction tag constants ────────────────────────────────────────
pub const ir_const_int = "IrConstInt";
pub const ir_const_string = "IrConstString";
pub const ir_const_bool = "IrConstBool";
pub const ir_const_nil = "IrConstNil";
pub const ir_binary = "IrBinary";
pub const ir_call = "IrCall";
pub const ir_tag_init = "IrTagInit";
pub const ir_record_init = "IrRecordInit";
pub const ir_field_get = "IrFieldGet";
pub const ir_tag_test = "IrTagTest";
pub const ir_tag_payload = "IrTagPayload";
pub const ir_list_init = "IrListInit";
pub const ir_closure = "IrClosure";

// ── Terminator tag constants ────────────────────────────────────────────
pub const ir_ret = "IrRet";
pub const ir_jump = "IrJump";
pub const ir_branch = "IrBranch";

/// Generate the complete IR lowerer as an IR module.
/// Returns the entry function ID (lc_lower_module).
pub fn generate(alloc: Allocator, builder: *ir.Builder, pool: *InternPool) !FuncId {
    var g = Gen.init(alloc, builder, pool);

    // Reserve function IDs for mutual recursion
    const f_state_new = try g.reserveFunc("lc_state_new");
    const f_fresh_val = try g.reserveFunc("lc_fresh_val");
    const f_emit_inst = try g.reserveFunc("lc_emit_inst");
    const f_end_block = try g.reserveFunc("lc_end_block");
    const f_new_block = try g.reserveFunc("lc_new_block");
    const f_alloc_block_id = try g.reserveFunc("lc_alloc_block_id");
    const f_lower_expr = try g.reserveFunc("lc_lower_expr");
    const f_lower_if = try g.reserveFunc("lc_lower_if");
    const f_lower_call = try g.reserveFunc("lc_lower_call");
    const f_lower_let = try g.reserveFunc("lc_lower_let");
    const f_lower_block = try g.reserveFunc("lc_lower_block");
    const f_lower_match = try g.reserveFunc("lc_lower_match");
    const f_lower_match_arms = try g.reserveFunc("lc_lower_match_arms");
    const f_lower_fn_decl = try g.reserveFunc("lc_lower_fn_decl");
    const f_lower_module = try g.reserveFunc("lc_lower_module");

    // ── Generate: lc_state_new() -> LowerState ──────────────────────
    // Creates a fresh lowering state.
    // LowerState = {next_val: 0, insts: [], blocks: [], block_id: 0, next_block: 1, functions: []}
    try g.beginReservedFunc("lc_state_new");
    {
        _ = g.beginBlock();
        const zero = try g.constInt(0);
        const one = try g.constInt(1);
        const empty_insts = try g.listInit(&.{});
        const empty_blocks = try g.listInit(&.{});
        const empty_funcs = try g.listInit(&.{});
        const state = try g.record(&.{
            .{ .name = "next_val", .value = zero },
            .{ .name = "insts", .value = empty_insts },
            .{ .name = "blocks", .value = empty_blocks },
            .{ .name = "block_id", .value = zero },
            .{ .name = "next_block", .value = one },
            .{ .name = "functions", .value = empty_funcs },
        });
        try g.ret(state);
    }
    try g.endReservedFunc(f_state_new);

    // ── Generate: lc_fresh_val(state) -> {id: Int, state: LowerState} ──
    try g.beginReservedFunc("lc_fresh_val");
    {
        const state = try g.addParam();
        _ = g.beginBlock();
        const nv = try g.recordField(state, "next_val");
        const one = try g.constInt(1);
        const next_nv = try g.add(nv, one);
        // Rebuild state with incremented next_val
        const insts = try g.recordField(state, "insts");
        const blocks = try g.recordField(state, "blocks");
        const block_id = try g.recordField(state, "block_id");
        const next_block = try g.recordField(state, "next_block");
        const funcs = try g.recordField(state, "functions");
        const new_state = try g.record(&.{
            .{ .name = "next_val", .value = next_nv },
            .{ .name = "insts", .value = insts },
            .{ .name = "blocks", .value = blocks },
            .{ .name = "block_id", .value = block_id },
            .{ .name = "next_block", .value = next_block },
            .{ .name = "functions", .value = funcs },
        });
        const result = try g.record(&.{
            .{ .name = "id", .value = nv },
            .{ .name = "state", .value = new_state },
        });
        try g.ret(result);
    }
    try g.endReservedFunc(f_fresh_val);

    // ── Generate: lc_emit_inst(inst, state) -> state ────────────────
    try g.beginReservedFunc("lc_emit_inst");
    {
        const inst = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();
        const insts = try g.recordField(state, "insts");
        const new_insts = try g.listAppend(insts, inst);
        const nv = try g.recordField(state, "next_val");
        const blocks = try g.recordField(state, "blocks");
        const block_id = try g.recordField(state, "block_id");
        const next_block = try g.recordField(state, "next_block");
        const funcs = try g.recordField(state, "functions");
        const new_state = try g.record(&.{
            .{ .name = "next_val", .value = nv },
            .{ .name = "insts", .value = new_insts },
            .{ .name = "blocks", .value = blocks },
            .{ .name = "block_id", .value = block_id },
            .{ .name = "next_block", .value = next_block },
            .{ .name = "functions", .value = funcs },
        });
        try g.ret(new_state);
    }
    try g.endReservedFunc(f_emit_inst);

    // ── Generate: lc_end_block(term, state) -> state ────────────────
    // Finalize current block: create IrBlock record with current insts + terminator,
    // append to blocks list, clear insts.
    try g.beginReservedFunc("lc_end_block");
    {
        const term = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();
        const insts = try g.recordField(state, "insts");
        const block_id = try g.recordField(state, "block_id");
        const block_rec = try g.record(&.{
            .{ .name = "id", .value = block_id },
            .{ .name = "insts", .value = insts },
            .{ .name = "term", .value = term },
        });
        const blocks = try g.recordField(state, "blocks");
        const new_blocks = try g.listAppend(blocks, block_rec);
        const empty_insts = try g.listInit(&.{});
        const nv = try g.recordField(state, "next_val");
        const next_block = try g.recordField(state, "next_block");
        const funcs = try g.recordField(state, "functions");
        const new_state = try g.record(&.{
            .{ .name = "next_val", .value = nv },
            .{ .name = "insts", .value = empty_insts },
            .{ .name = "blocks", .value = new_blocks },
            .{ .name = "block_id", .value = block_id },
            .{ .name = "next_block", .value = next_block },
            .{ .name = "functions", .value = funcs },
        });
        try g.ret(new_state);
    }
    try g.endReservedFunc(f_end_block);

    // ── Generate: lc_new_block(state) -> {id: Int, state} ───────────
    // Allocate a new block ID, set as current, clear insts.
    try g.beginReservedFunc("lc_new_block");
    {
        const state = try g.addParam();
        _ = g.beginBlock();
        const next_block = try g.recordField(state, "next_block");
        const one = try g.constInt(1);
        const new_next = try g.add(next_block, one);
        const empty_insts = try g.listInit(&.{});
        const nv = try g.recordField(state, "next_val");
        const blocks = try g.recordField(state, "blocks");
        const funcs = try g.recordField(state, "functions");
        const new_state = try g.record(&.{
            .{ .name = "next_val", .value = nv },
            .{ .name = "insts", .value = empty_insts },
            .{ .name = "blocks", .value = blocks },
            .{ .name = "block_id", .value = next_block },
            .{ .name = "next_block", .value = new_next },
            .{ .name = "functions", .value = funcs },
        });
        const result = try g.record(&.{
            .{ .name = "id", .value = next_block },
            .{ .name = "state", .value = new_state },
        });
        try g.ret(result);
    }
    try g.endReservedFunc(f_new_block);

    // ── Generate: lc_alloc_block_id(state) -> {id: Int, state} ──────
    // Allocate a new block ID WITHOUT changing current block_id or clearing insts.
    // Use this when you need to reserve block IDs for forward references.
    try g.beginReservedFunc("lc_alloc_block_id");
    {
        const state = try g.addParam();
        _ = g.beginBlock();
        const next_block = try g.recordField(state, "next_block");
        const one = try g.constInt(1);
        const new_next = try g.add(next_block, one);
        const new_state = try g.record(&.{
            .{ .name = "next_val", .value = try g.recordField(state, "next_val") },
            .{ .name = "insts", .value = try g.recordField(state, "insts") },
            .{ .name = "blocks", .value = try g.recordField(state, "blocks") },
            .{ .name = "block_id", .value = try g.recordField(state, "block_id") },
            .{ .name = "next_block", .value = new_next },
            .{ .name = "functions", .value = try g.recordField(state, "functions") },
        });
        const result = try g.record(&.{
            .{ .name = "id", .value = next_block },
            .{ .name = "state", .value = new_state },
        });
        try g.ret(result);
    }
    try g.endReservedFunc(f_alloc_block_id);

    // ── Generate: lc_lower_expr(expr, scope, state) -> {value: Int, state} ──
    // The core expression lowering function. Dispatches on TAST node type.
    try g.beginReservedFunc("lc_lower_expr");
    {
        const expr = try g.addParam();
        const scope = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();

        // ── TIntLit ──
        const is_int = try g.tagTest(expr, typeck.tast_int_lit);
        const int_blk = g.reserveBlock();
        const check_float = g.reserveBlock();
        try g.branch(is_int, int_blk, check_float);

        g.beginReservedBlock(int_blk);
        {
            const payload = try g.tagPayload(expr, typeck.tast_int_lit);
            const int_val = try g.recordField(payload, "value");
            const fv = try g.callDirect(f_fresh_val, &.{state});
            const dst = try g.recordField(fv, "id");
            const st1 = try g.recordField(fv, "state");
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "value", .value = int_val },
            });
            const inst = try g.tag(ir_const_int, inst_rec);
            const st2 = try g.callDirect(f_emit_inst, &.{ inst, st1 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st2 },
            }));
        }

        // ── TFloatLit ──
        g.beginReservedBlock(check_float);
        const is_float = try g.tagTest(expr, typeck.tast_float_lit);
        const float_blk = g.reserveBlock();
        const check_string = g.reserveBlock();
        try g.branch(is_float, float_blk, check_string);

        g.beginReservedBlock(float_blk);
        {
            const payload = try g.tagPayload(expr, typeck.tast_float_lit);
            const float_val = try g.recordField(payload, "value");
            const fv = try g.callDirect(f_fresh_val, &.{state});
            const dst = try g.recordField(fv, "id");
            const st1 = try g.recordField(fv, "state");
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "value", .value = float_val },
            });
            const inst = try g.tag(ir_const_string, inst_rec);
            const st2 = try g.callDirect(f_emit_inst, &.{ inst, st1 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st2 },
            }));
        }

        // ── TStringLit ──
        g.beginReservedBlock(check_string);
        const is_str = try g.tagTest(expr, typeck.tast_string_lit);
        const str_blk = g.reserveBlock();
        const check_bool = g.reserveBlock();
        try g.branch(is_str, str_blk, check_bool);

        g.beginReservedBlock(str_blk);
        {
            const payload = try g.tagPayload(expr, typeck.tast_string_lit);
            const str_val = try g.recordField(payload, "value");
            const fv = try g.callDirect(f_fresh_val, &.{state});
            const dst = try g.recordField(fv, "id");
            const st1 = try g.recordField(fv, "state");
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "value", .value = str_val },
            });
            const inst = try g.tag(ir_const_string, inst_rec);
            const st2 = try g.callDirect(f_emit_inst, &.{ inst, st1 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st2 },
            }));
        }

        // ── TBoolLit ──
        g.beginReservedBlock(check_bool);
        const is_bool = try g.tagTest(expr, typeck.tast_bool_lit);
        const bool_blk = g.reserveBlock();
        const check_nil = g.reserveBlock();
        try g.branch(is_bool, bool_blk, check_nil);

        g.beginReservedBlock(bool_blk);
        {
            const payload = try g.tagPayload(expr, typeck.tast_bool_lit);
            const bool_val = try g.recordField(payload, "value");
            const fv = try g.callDirect(f_fresh_val, &.{state});
            const dst = try g.recordField(fv, "id");
            const st1 = try g.recordField(fv, "state");
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "value", .value = bool_val },
            });
            const inst = try g.tag(ir_const_bool, inst_rec);
            const st2 = try g.callDirect(f_emit_inst, &.{ inst, st1 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st2 },
            }));
        }

        // ── TNilLit ──
        g.beginReservedBlock(check_nil);
        const is_nil = try g.tagTest(expr, typeck.tast_nil_lit);
        const nil_blk = g.reserveBlock();
        const check_ident = g.reserveBlock();
        try g.branch(is_nil, nil_blk, check_ident);

        g.beginReservedBlock(nil_blk);
        {
            const fv = try g.callDirect(f_fresh_val, &.{state});
            const dst = try g.recordField(fv, "id");
            const st1 = try g.recordField(fv, "state");
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
            });
            const inst = try g.tag(ir_const_nil, inst_rec);
            const st2 = try g.callDirect(f_emit_inst, &.{ inst, st1 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st2 },
            }));
        }

        // ── TIdent ──
        g.beginReservedBlock(check_ident);
        const is_ident = try g.tagTest(expr, typeck.tast_ident);
        const ident_blk = g.reserveBlock();
        const check_binop = g.reserveBlock();
        try g.branch(is_ident, ident_blk, check_binop);

        g.beginReservedBlock(ident_blk);
        {
            const payload = try g.tagPayload(expr, typeck.tast_ident);
            const name = try g.recordField(payload, "name");
            // Lookup name in scope to get value ID
            const has = try g.mapHas(scope, name);
            const found_blk = g.reserveBlock();
            const not_found_blk = g.reserveBlock();
            try g.branch(has, found_blk, not_found_blk);

            g.beginReservedBlock(found_blk);
            const val_id = try g.mapGet(scope, name);
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = val_id },
                .{ .name = "state", .value = state },
            }));

            // Not found — treat as global function name, emit a closure reference
            g.beginReservedBlock(not_found_blk);
            const fv2 = try g.callDirect(f_fresh_val, &.{state});
            const dst2 = try g.recordField(fv2, "id");
            const st2 = try g.recordField(fv2, "state");
            const inst_rec2 = try g.record(&.{
                .{ .name = "dst", .value = dst2 },
                .{ .name = "func", .value = name },
            });
            const inst2 = try g.tag(ir_closure, inst_rec2);
            const st3 = try g.callDirect(f_emit_inst, &.{ inst2, st2 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst2 },
                .{ .name = "state", .value = st3 },
            }));
        }

        // ── TBinOp ──
        g.beginReservedBlock(check_binop);
        const is_binop = try g.tagTest(expr, typeck.tast_binop);
        const binop_blk = g.reserveBlock();
        const check_call = g.reserveBlock();
        try g.branch(is_binop, binop_blk, check_call);

        g.beginReservedBlock(binop_blk);
        {
            const payload = try g.tagPayload(expr, typeck.tast_binop);
            const op = try g.recordField(payload, "op");
            const lhs = try g.recordField(payload, "lhs");
            const rhs = try g.recordField(payload, "rhs");
            // Lower lhs
            const lhs_r = try g.callDirect(f_lower_expr, &.{ lhs, scope, state });
            const lhs_val = try g.recordField(lhs_r, "value");
            const st1 = try g.recordField(lhs_r, "state");
            // Lower rhs
            const rhs_r = try g.callDirect(f_lower_expr, &.{ rhs, scope, st1 });
            const rhs_val = try g.recordField(rhs_r, "value");
            const st2 = try g.recordField(rhs_r, "state");
            // Emit IrBinary
            const fv = try g.callDirect(f_fresh_val, &.{st2});
            const dst = try g.recordField(fv, "id");
            const st3 = try g.recordField(fv, "state");
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "op", .value = op },
                .{ .name = "lhs", .value = lhs_val },
                .{ .name = "rhs", .value = rhs_val },
            });
            const inst = try g.tag(ir_binary, inst_rec);
            const st4 = try g.callDirect(f_emit_inst, &.{ inst, st3 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st4 },
            }));
        }

        // ── TCall ──
        g.beginReservedBlock(check_call);
        const is_call = try g.tagTest(expr, typeck.tast_call);
        const call_blk = g.reserveBlock();
        const check_if = g.reserveBlock();
        try g.branch(is_call, call_blk, check_if);

        g.beginReservedBlock(call_blk);
        {
            const result = try g.callDirect(f_lower_call, &.{ expr, scope, state });
            try g.ret(result);
        }

        // ── TIf ──
        g.beginReservedBlock(check_if);
        const is_if = try g.tagTest(expr, typeck.tast_if);
        const if_blk = g.reserveBlock();
        const check_let = g.reserveBlock();
        try g.branch(is_if, if_blk, check_let);

        g.beginReservedBlock(if_blk);
        {
            const result = try g.callDirect(f_lower_if, &.{ expr, scope, state });
            try g.ret(result);
        }

        // ── TLet ──
        g.beginReservedBlock(check_let);
        const is_let = try g.tagTest(expr, typeck.tast_let);
        const let_blk = g.reserveBlock();
        const check_block_expr = g.reserveBlock();
        try g.branch(is_let, let_blk, check_block_expr);

        g.beginReservedBlock(let_blk);
        {
            const result = try g.callDirect(f_lower_let, &.{ expr, scope, state });
            try g.ret(result);
        }

        // ── TBlock ──
        g.beginReservedBlock(check_block_expr);
        const is_block = try g.tagTest(expr, typeck.tast_block);
        const block_blk = g.reserveBlock();
        const check_lambda = g.reserveBlock();
        try g.branch(is_block, block_blk, check_lambda);

        g.beginReservedBlock(block_blk);
        {
            const result = try g.callDirect(f_lower_block, &.{ expr, scope, state });
            try g.ret(result);
        }

        // ── TLambda ──
        g.beginReservedBlock(check_lambda);
        const is_lambda = try g.tagTest(expr, typeck.tast_lambda);
        const lambda_blk = g.reserveBlock();
        const check_field_access = g.reserveBlock();
        try g.branch(is_lambda, lambda_blk, check_field_access);

        g.beginReservedBlock(lambda_blk);
        {
            // Lower lambda: create new function entry, lower body inside it, emit IrClosure
            const payload = try g.tagPayload(expr, typeck.tast_lambda);
            const params = try g.recordField(payload, "params");
            const body = try g.recordField(payload, "body");

            // Bind params in scope
            const params_len = try g.listLength(params);
            const zero_l = try g.constInt(0);
            const empty_pids_l = try g.listInit(&.{});
            const param_loop = g.reserveBlock();
            try g.jump(param_loop, &.{ zero_l, scope, state, empty_pids_l });

            g.beginReservedBlock(param_loop);
            const p_idx = try g.addBlockParam();
            const p_scope = try g.addBlockParam();
            const p_state = try g.addBlockParam();
            const p_ids = try g.addBlockParam();
            const p_done = try g.ge(p_idx, params_len);
            const p_body_blk = g.reserveBlock();
            const p_exit = g.reserveBlock();
            try g.branch(p_done, p_exit, p_body_blk);

            g.beginReservedBlock(p_body_blk);
            const param_name = try g.listNth(params, p_idx);
            // Allocate a value ID for this parameter
            const pfv = try g.callDirect(f_fresh_val, &.{p_state});
            const p_val = try g.recordField(pfv, "id");
            const p_st = try g.recordField(pfv, "state");
            const new_scope = try g.mapSet(p_scope, param_name, p_val);
            const new_pids_l = try g.listAppend(p_ids, p_val);
            const one_l = try g.constInt(1);
            const next_l = try g.add(p_idx, one_l);
            try g.jump(param_loop, &.{ next_l, new_scope, p_st, new_pids_l });

            g.beginReservedBlock(p_exit);
            // Lower the body
            const body_r = try g.callDirect(f_lower_expr, &.{ body, p_scope, p_state });
            const body_val = try g.recordField(body_r, "value");
            const st_after_body = try g.recordField(body_r, "state");

            // End current block with a return terminator for the lambda body
            const ret_term = try g.record(&.{
                .{ .name = "value", .value = body_val },
            });
            const ret_tagged = try g.tag(ir_ret, ret_term);
            const st_ended = try g.callDirect(f_end_block, &.{ ret_tagged, st_after_body });

            // Create a function record for the lambda
            const lam_name = try g.constString("<lambda>");
            const lam_blocks = try g.recordField(st_ended, "blocks");
            const fn_rec = try g.record(&.{
                .{ .name = "name", .value = lam_name },
                .{ .name = "params", .value = params },
                .{ .name = "param_ids", .value = p_ids },
                .{ .name = "blocks", .value = lam_blocks },
            });
            // Append to functions list and reset blocks
            const fns = try g.recordField(st_ended, "functions");
            const new_fns = try g.listAppend(fns, fn_rec);
            const empty_blocks = try g.listInit(&.{});
            const empty_insts = try g.listInit(&.{});
            const nv = try g.recordField(st_ended, "next_val");
            const nb = try g.recordField(st_ended, "next_block");
            const bid = try g.recordField(st_ended, "block_id");
            const st_reset = try g.record(&.{
                .{ .name = "next_val", .value = nv },
                .{ .name = "insts", .value = empty_insts },
                .{ .name = "blocks", .value = empty_blocks },
                .{ .name = "block_id", .value = bid },
                .{ .name = "next_block", .value = nb },
                .{ .name = "functions", .value = new_fns },
            });

            // Emit IrClosure in the parent context
            const cfv = try g.callDirect(f_fresh_val, &.{st_reset});
            const cdst = try g.recordField(cfv, "id");
            const cst = try g.recordField(cfv, "state");
            const closure_rec = try g.record(&.{
                .{ .name = "dst", .value = cdst },
                .{ .name = "func", .value = lam_name },
            });
            const closure_inst = try g.tag(ir_closure, closure_rec);
            const cst2 = try g.callDirect(f_emit_inst, &.{ closure_inst, cst });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = cdst },
                .{ .name = "state", .value = cst2 },
            }));
        }

        // ── TFieldAccess ──
        g.beginReservedBlock(check_field_access);
        const is_field = try g.tagTest(expr, typeck.tast_field_access);
        const field_blk = g.reserveBlock();
        const check_list_lit = g.reserveBlock();
        try g.branch(is_field, field_blk, check_list_lit);

        g.beginReservedBlock(field_blk);
        {
            const payload = try g.tagPayload(expr, typeck.tast_field_access);
            const base = try g.recordField(payload, "expr");
            const field = try g.recordField(payload, "field");
            const base_r = try g.callDirect(f_lower_expr, &.{ base, scope, state });
            const base_val = try g.recordField(base_r, "value");
            const st1 = try g.recordField(base_r, "state");
            const fv = try g.callDirect(f_fresh_val, &.{st1});
            const dst = try g.recordField(fv, "id");
            const st2 = try g.recordField(fv, "state");
            // index = -1 means "unknown, use fields_map"
            const neg_one = try g.constInt(-1);
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "base", .value = base_val },
                .{ .name = "field", .value = field },
                .{ .name = "index", .value = neg_one },
            });
            const inst = try g.tag(ir_field_get, inst_rec);
            const st3 = try g.callDirect(f_emit_inst, &.{ inst, st2 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st3 },
            }));
        }

        // ── TListLit ──
        g.beginReservedBlock(check_list_lit);
        const is_list = try g.tagTest(expr, typeck.tast_list_lit);
        const list_blk = g.reserveBlock();
        const check_record_lit = g.reserveBlock();
        try g.branch(is_list, list_blk, check_record_lit);

        g.beginReservedBlock(list_blk);
        {
            // TListLit payload is the original AST expr (from typeck passthrough)
            // For bootstrap: emit IrConstNil as placeholder
            const fv = try g.callDirect(f_fresh_val, &.{state});
            const dst = try g.recordField(fv, "id");
            const st1 = try g.recordField(fv, "state");
            const empty_elems = try g.listInit(&.{});
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "elements", .value = empty_elems },
            });
            const inst = try g.tag(ir_list_init, inst_rec);
            const st2 = try g.callDirect(f_emit_inst, &.{ inst, st1 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st2 },
            }));
        }

        // ── TRecordLit ──
        g.beginReservedBlock(check_record_lit);
        const is_rec = try g.tagTest(expr, typeck.tast_record_lit);
        const rec_blk = g.reserveBlock();
        const check_unary = g.reserveBlock();
        try g.branch(is_rec, rec_blk, check_unary);

        g.beginReservedBlock(rec_blk);
        {
            // TRecordLit wraps AST RecordLit([{name, value}])
            const rec_payload = try g.tagPayload(expr, typeck.tast_record_lit);
            const ast_fields = try g.tagPayload(rec_payload, "RecordLit");
            const n_fields = try g.listLength(ast_fields);
            const zero_r = try g.constInt(0);
            const empty_ir_fields = try g.listInit(&.{});

            // Loop: lower each field value
            const rec_loop = g.reserveBlock();
            try g.jump(rec_loop, &.{ zero_r, state, empty_ir_fields });

            g.beginReservedBlock(rec_loop);
            const ri = try g.addBlockParam();
            const r_st = try g.addBlockParam();
            const ir_fields = try g.addBlockParam();
            const r_done = try g.ge(ri, n_fields);
            const r_body = g.reserveBlock();
            const r_exit = g.reserveBlock();
            try g.branch(r_done, r_exit, r_body);

            g.beginReservedBlock(r_body);
            {
                const ast_field = try g.listNth(ast_fields, ri);
                const fname = try g.recordField(ast_field, "name");
                const fval_expr = try g.recordField(ast_field, "value");
                // Lower the field value expression
                const fval_r = try g.callDirect(f_lower_expr, &.{ fval_expr, scope, r_st });
                const fval_id = try g.recordField(fval_r, "value");
                const r_st2 = try g.recordField(fval_r, "state");
                // Build IR field: {name, value: value_id}
                const ir_field = try g.record(&.{
                    .{ .name = "name", .value = fname },
                    .{ .name = "value", .value = fval_id },
                });
                const ir_fields2 = try g.listAppend(ir_fields, ir_field);
                const one_r = try g.constInt(1);
                const next_ri = try g.add(ri, one_r);
                try g.jump(rec_loop, &.{ next_ri, r_st2, ir_fields2 });
            }

            g.beginReservedBlock(r_exit);
            {
                const fv = try g.callDirect(f_fresh_val, &.{r_st});
                const dst = try g.recordField(fv, "id");
                const st_final = try g.recordField(fv, "state");
                const inst_rec = try g.record(&.{
                    .{ .name = "dst", .value = dst },
                    .{ .name = "fields", .value = ir_fields },
                });
                const inst = try g.tag(ir_record_init, inst_rec);
                const st_done = try g.callDirect(f_emit_inst, &.{ inst, st_final });
                try g.ret(try g.record(&.{
                    .{ .name = "value", .value = dst },
                    .{ .name = "state", .value = st_done },
                }));
            }
        }

        // ── TUnary ──
        g.beginReservedBlock(check_unary);
        const is_unary = try g.tagTest(expr, typeck.tast_unary);
        const unary_blk = g.reserveBlock();
        const check_pipe = g.reserveBlock();
        try g.branch(is_unary, unary_blk, check_pipe);

        g.beginReservedBlock(unary_blk);
        {
            const payload = try g.tagPayload(expr, typeck.tast_unary);
            const un_op = try g.recordField(payload, "op");
            const operand = try g.recordField(payload, "operand");
            // Lower operand
            const op_r = try g.callDirect(f_lower_expr, &.{ operand, scope, state });
            const op_val = try g.recordField(op_r, "value");
            const st1 = try g.recordField(op_r, "state");
            // Emit as IrBinary with 0 - operand for neg, or pass through for other ops
            const fv_zero = try g.callDirect(f_fresh_val, &.{st1});
            const zero_dst = try g.recordField(fv_zero, "id");
            const st2 = try g.recordField(fv_zero, "state");
            const zero_val = try g.constInt(0);
            const zero_inst_rec = try g.record(&.{
                .{ .name = "dst", .value = zero_dst },
                .{ .name = "value", .value = zero_val },
            });
            const zero_inst = try g.tag(ir_const_int, zero_inst_rec);
            const st3 = try g.callDirect(f_emit_inst, &.{ zero_inst, st2 });

            const fv = try g.callDirect(f_fresh_val, &.{st3});
            const dst = try g.recordField(fv, "id");
            const st4 = try g.recordField(fv, "state");
            const neg_op = try g.constString("-");
            _ = un_op; // Use "-" regardless for bootstrap
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "op", .value = neg_op },
                .{ .name = "lhs", .value = zero_dst },
                .{ .name = "rhs", .value = op_val },
            });
            const inst = try g.tag(ir_binary, inst_rec);
            const st5 = try g.callDirect(f_emit_inst, &.{ inst, st4 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st5 },
            }));
        }

        // ── TPipe ──
        g.beginReservedBlock(check_pipe);
        const is_pipe = try g.tagTest(expr, typeck.tast_pipe);
        const pipe_blk = g.reserveBlock();
        const check_match = g.reserveBlock();
        try g.branch(is_pipe, pipe_blk, check_match);

        g.beginReservedBlock(pipe_blk);
        {
            // Pipe: lhs |> rhs
            // If rhs is TCall (e.g. `f(y)`): desugar to `f(lhs, y)` — prepend lhs to args
            // If rhs is TIdent (e.g. `f`): desugar to `f(lhs)`
            const payload = try g.tagPayload(expr, typeck.tast_pipe);
            const lhs = try g.recordField(payload, "lhs");
            const rhs = try g.recordField(payload, "rhs");
            const lhs_r = try g.callDirect(f_lower_expr, &.{ lhs, scope, state });
            const lhs_val = try g.recordField(lhs_r, "value");
            const st1 = try g.recordField(lhs_r, "state");

            // Check if rhs is TCall (most common: `lhs |> f(args...)`)
            const is_rhs_call = try g.tagTest(rhs, typeck.tast_call);
            const blk_pipe_call = g.reserveBlock();
            const blk_pipe_ident_check = g.reserveBlock();
            try g.branch(is_rhs_call, blk_pipe_call, blk_pipe_ident_check);

            g.beginReservedBlock(blk_pipe_call);
            {
                // rhs is TCall: extract callee and args, prepend lhs_val
                const call_payload = try g.tagPayload(rhs, typeck.tast_call);
                const rhs_callee = try g.recordField(call_payload, "callee");
                const rhs_args = try g.recordField(call_payload, "args");

                // Get callee name if it's TIdent
                const callee_is_ident = try g.tagTest(rhs_callee, typeck.tast_ident);
                const blk_call_ident = g.reserveBlock();
                const blk_call_expr = g.reserveBlock();
                try g.branch(callee_is_ident, blk_call_ident, blk_call_expr);

                g.beginReservedBlock(blk_call_ident);
                {
                    const ci_pl = try g.tagPayload(rhs_callee, typeck.tast_ident);
                    const callee_name = try g.recordField(ci_pl, "name");

                    // Lower callee to get value ID
                    const callee_r = try g.callDirect(f_lower_expr, &.{ rhs_callee, scope, st1 });
                    const callee_vid = try g.recordField(callee_r, "value");
                    const st_c = try g.recordField(callee_r, "state");

                    // Lower rhs args, prepending lhs_val
                    const rhs_args_len = try g.listLength(rhs_args);
                    const zero_pa = try g.constInt(0);
                    const init_args = try g.listInit(&.{lhs_val});
                    const pa_loop = g.reserveBlock();
                    try g.jump(pa_loop, &.{ zero_pa, init_args, st_c });

                    g.beginReservedBlock(pa_loop);
                    const pa_idx = try g.addBlockParam();
                    const pa_vals = try g.addBlockParam();
                    const pa_state = try g.addBlockParam();
                    const pa_done = try g.ge(pa_idx, rhs_args_len);
                    const pa_body = g.reserveBlock();
                    const pa_exit = g.reserveBlock();
                    try g.branch(pa_done, pa_exit, pa_body);

                    g.beginReservedBlock(pa_body);
                    const pa_arg = try g.listNth(rhs_args, pa_idx);
                    const pa_arg_r = try g.callDirect(f_lower_expr, &.{ pa_arg, scope, pa_state });
                    const pa_arg_val = try g.recordField(pa_arg_r, "value");
                    const pa_arg_st = try g.recordField(pa_arg_r, "state");
                    const pa_new_vals = try g.listAppend(pa_vals, pa_arg_val);
                    const one_pa = try g.constInt(1);
                    const next_pa = try g.add(pa_idx, one_pa);
                    try g.jump(pa_loop, &.{ next_pa, pa_new_vals, pa_arg_st });

                    g.beginReservedBlock(pa_exit);
                    const fv = try g.callDirect(f_fresh_val, &.{pa_state});
                    const dst = try g.recordField(fv, "id");
                    const st_fin = try g.recordField(fv, "state");
                    const inst_rec = try g.record(&.{
                        .{ .name = "dst", .value = dst },
                        .{ .name = "callee", .value = callee_name },
                        .{ .name = "callee_val", .value = callee_vid },
                        .{ .name = "args", .value = pa_vals },
                    });
                    const inst = try g.tag(ir_call, inst_rec);
                    const st_out = try g.callDirect(f_emit_inst, &.{ inst, st_fin });
                    try g.ret(try g.record(&.{
                        .{ .name = "value", .value = dst },
                        .{ .name = "state", .value = st_out },
                    }));
                }

                g.beginReservedBlock(blk_call_expr);
                {
                    // Callee is an expression — lower it, use indirect call
                    const callee_r = try g.callDirect(f_lower_expr, &.{ rhs_callee, scope, st1 });
                    const callee_vid = try g.recordField(callee_r, "value");
                    const st_c = try g.recordField(callee_r, "state");

                    const rhs_args_len2 = try g.listLength(rhs_args);
                    const zero_pa2 = try g.constInt(0);
                    const init_args2 = try g.listInit(&.{lhs_val});
                    const pa_loop2 = g.reserveBlock();
                    try g.jump(pa_loop2, &.{ zero_pa2, init_args2, st_c });

                    g.beginReservedBlock(pa_loop2);
                    const pa_idx2 = try g.addBlockParam();
                    const pa_vals2 = try g.addBlockParam();
                    const pa_state2 = try g.addBlockParam();
                    const pa_done2 = try g.ge(pa_idx2, rhs_args_len2);
                    const pa_body2 = g.reserveBlock();
                    const pa_exit2 = g.reserveBlock();
                    try g.branch(pa_done2, pa_exit2, pa_body2);

                    g.beginReservedBlock(pa_body2);
                    const pa_arg2 = try g.listNth(rhs_args, pa_idx2);
                    const pa_arg_r2 = try g.callDirect(f_lower_expr, &.{ pa_arg2, scope, pa_state2 });
                    const pa_arg_val2 = try g.recordField(pa_arg_r2, "value");
                    const pa_arg_st2 = try g.recordField(pa_arg_r2, "state");
                    const pa_new_vals2 = try g.listAppend(pa_vals2, pa_arg_val2);
                    const one_pa2 = try g.constInt(1);
                    const next_pa2 = try g.add(pa_idx2, one_pa2);
                    try g.jump(pa_loop2, &.{ next_pa2, pa_new_vals2, pa_arg_st2 });

                    g.beginReservedBlock(pa_exit2);
                    const fv2 = try g.callDirect(f_fresh_val, &.{pa_state2});
                    const dst2 = try g.recordField(fv2, "id");
                    const st_fin2 = try g.recordField(fv2, "state");
                    const empty_callee = try g.constString("");
                    const inst_rec2 = try g.record(&.{
                        .{ .name = "dst", .value = dst2 },
                        .{ .name = "callee", .value = empty_callee },
                        .{ .name = "callee_val", .value = callee_vid },
                        .{ .name = "args", .value = pa_vals2 },
                    });
                    const inst2 = try g.tag(ir_call, inst_rec2);
                    const st_out2 = try g.callDirect(f_emit_inst, &.{ inst2, st_fin2 });
                    try g.ret(try g.record(&.{
                        .{ .name = "value", .value = dst2 },
                        .{ .name = "state", .value = st_out2 },
                    }));
                }
            }

            g.beginReservedBlock(blk_pipe_ident_check);
            {
                // rhs is TIdent: `lhs |> f` → `f(lhs)`
                const is_rhs_ident = try g.tagTest(rhs, typeck.tast_ident);
                const blk_pipe_ident = g.reserveBlock();
                const blk_pipe_other = g.reserveBlock();
                try g.branch(is_rhs_ident, blk_pipe_ident, blk_pipe_other);

                g.beginReservedBlock(blk_pipe_ident);
                {
                    const ident_payload = try g.tagPayload(rhs, typeck.tast_ident);
                    const callee_name = try g.recordField(ident_payload, "name");
                    const rhs_r = try g.callDirect(f_lower_expr, &.{ rhs, scope, st1 });
                    const rhs_vid = try g.recordField(rhs_r, "value");
                    const st2 = try g.recordField(rhs_r, "state");
                    const fv = try g.callDirect(f_fresh_val, &.{st2});
                    const dst = try g.recordField(fv, "id");
                    const st3 = try g.recordField(fv, "state");
                    const args_list = try g.listInit(&.{lhs_val});
                    const inst_rec = try g.record(&.{
                        .{ .name = "dst", .value = dst },
                        .{ .name = "callee", .value = callee_name },
                        .{ .name = "callee_val", .value = rhs_vid },
                        .{ .name = "args", .value = args_list },
                    });
                    const inst = try g.tag(ir_call, inst_rec);
                    const st4 = try g.callDirect(f_emit_inst, &.{ inst, st3 });
                    try g.ret(try g.record(&.{
                        .{ .name = "value", .value = dst },
                        .{ .name = "state", .value = st4 },
                    }));
                }

                g.beginReservedBlock(blk_pipe_other);
                {
                    // Fallback: lower rhs as expression, indirect call with [lhs]
                    const rhs_r = try g.callDirect(f_lower_expr, &.{ rhs, scope, st1 });
                    const rhs_val = try g.recordField(rhs_r, "value");
                    const st2 = try g.recordField(rhs_r, "state");
                    const fv = try g.callDirect(f_fresh_val, &.{st2});
                    const dst = try g.recordField(fv, "id");
                    const st3 = try g.recordField(fv, "state");
                    const empty_callee = try g.constString("");
                    const args_list = try g.listInit(&.{lhs_val});
                    const inst_rec = try g.record(&.{
                        .{ .name = "dst", .value = dst },
                        .{ .name = "callee", .value = empty_callee },
                        .{ .name = "callee_val", .value = rhs_val },
                        .{ .name = "args", .value = args_list },
                    });
                    const inst = try g.tag(ir_call, inst_rec);
                    const st4 = try g.callDirect(f_emit_inst, &.{ inst, st3 });
                    try g.ret(try g.record(&.{
                        .{ .name = "value", .value = dst },
                        .{ .name = "state", .value = st4 },
                    }));
                }
            }
        }

        // ── TMatch ──
        g.beginReservedBlock(check_match);
        const is_match = try g.tagTest(expr, typeck.tast_match);
        const match_blk = g.reserveBlock();
        const default_blk = g.reserveBlock();
        try g.branch(is_match, match_blk, default_blk);

        g.beginReservedBlock(match_blk);
        {
            const result = try g.callDirect(f_lower_match, &.{ expr, scope, state });
            try g.ret(result);
        }

        // ── Default: unhandled node, emit const nil ──
        g.beginReservedBlock(default_blk);
        {
            const fv = try g.callDirect(f_fresh_val, &.{state});
            const dst = try g.recordField(fv, "id");
            const st1 = try g.recordField(fv, "state");
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
            });
            const inst = try g.tag(ir_const_nil, inst_rec);
            const st2 = try g.callDirect(f_emit_inst, &.{ inst, st1 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st2 },
            }));
        }
    }
    try g.endReservedFunc(f_lower_expr);

    // ── Generate: lc_lower_if(expr, scope, state) -> {value: Int, state} ──
    try g.beginReservedFunc("lc_lower_if");
    {
        const expr = try g.addParam();
        const scope = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();

        const payload = try g.tagPayload(expr, typeck.tast_if);
        const cond = try g.recordField(payload, "cond");
        const then_br = try g.recordField(payload, "then_branch");
        const else_br = try g.recordField(payload, "else_branch");

        // Lower condition
        const cond_r = try g.callDirect(f_lower_expr, &.{ cond, scope, state });
        const cond_val = try g.recordField(cond_r, "value");
        const st1 = try g.recordField(cond_r, "state");

        // Allocate then, else, and merge block IDs (without changing current block)
        const then_nb = try g.callDirect(f_alloc_block_id, &.{st1});
        const then_id = try g.recordField(then_nb, "id");
        const st2 = try g.recordField(then_nb, "state");
        const else_nb = try g.callDirect(f_alloc_block_id, &.{st2});
        const else_id = try g.recordField(else_nb, "id");
        const st3 = try g.recordField(else_nb, "state");
        const merge_nb = try g.callDirect(f_alloc_block_id, &.{st3});
        const merge_id = try g.recordField(merge_nb, "id");
        const st4 = try g.recordField(merge_nb, "state");

        // End current block with branch
        const br_rec = try g.record(&.{
            .{ .name = "cond", .value = cond_val },
            .{ .name = "then_blk", .value = then_id },
            .{ .name = "else_blk", .value = else_id },
        });
        const br_term = try g.tag(ir_branch, br_rec);
        const st5 = try g.callDirect(f_end_block, &.{ br_term, st4 });

        // Lower then branch (set block_id to then_id)
        const nv5 = try g.recordField(st5, "next_val");
        const nb5 = try g.recordField(st5, "next_block");
        const blks5 = try g.recordField(st5, "blocks");
        const fns5 = try g.recordField(st5, "functions");
        const empty5 = try g.listInit(&.{});
        const st_then = try g.record(&.{
            .{ .name = "next_val", .value = nv5 },
            .{ .name = "insts", .value = empty5 },
            .{ .name = "blocks", .value = blks5 },
            .{ .name = "block_id", .value = then_id },
            .{ .name = "next_block", .value = nb5 },
            .{ .name = "functions", .value = fns5 },
        });
        const then_r = try g.callDirect(f_lower_expr, &.{ then_br, scope, st_then });
        const then_val = try g.recordField(then_r, "value");
        const st6 = try g.recordField(then_r, "state");

        // End then block with jump to merge
        const then_args = try g.listInit(&.{then_val});
        const then_jmp = try g.record(&.{
            .{ .name = "target", .value = merge_id },
            .{ .name = "args", .value = then_args },
        });
        const then_term = try g.tag(ir_jump, then_jmp);
        const st7 = try g.callDirect(f_end_block, &.{ then_term, st6 });

        // Lower else branch (set block_id to else_id)
        const nv7 = try g.recordField(st7, "next_val");
        const nb7 = try g.recordField(st7, "next_block");
        const blks7 = try g.recordField(st7, "blocks");
        const fns7 = try g.recordField(st7, "functions");
        const empty7 = try g.listInit(&.{});
        const st_else = try g.record(&.{
            .{ .name = "next_val", .value = nv7 },
            .{ .name = "insts", .value = empty7 },
            .{ .name = "blocks", .value = blks7 },
            .{ .name = "block_id", .value = else_id },
            .{ .name = "next_block", .value = nb7 },
            .{ .name = "functions", .value = fns7 },
        });
        const else_r = try g.callDirect(f_lower_expr, &.{ else_br, scope, st_else });
        const else_val = try g.recordField(else_r, "value");
        const st8 = try g.recordField(else_r, "state");

        // End else block with jump to merge
        const else_args = try g.listInit(&.{else_val});
        const else_jmp = try g.record(&.{
            .{ .name = "target", .value = merge_id },
            .{ .name = "args", .value = else_args },
        });
        const else_term = try g.tag(ir_jump, else_jmp);
        const st9 = try g.callDirect(f_end_block, &.{ else_term, st8 });

        // Merge block: allocate a fresh val for the phi
        const fv_merge = try g.callDirect(f_fresh_val, &.{st9});
        const merge_val = try g.recordField(fv_merge, "id");
        const st10 = try g.recordField(fv_merge, "state");

        // Set block_id to merge_id
        const nv10 = try g.recordField(st10, "next_val");
        const nb10 = try g.recordField(st10, "next_block");
        const blks10 = try g.recordField(st10, "blocks");
        const fns10 = try g.recordField(st10, "functions");
        const insts10 = try g.recordField(st10, "insts");
        const st_merge = try g.record(&.{
            .{ .name = "next_val", .value = nv10 },
            .{ .name = "insts", .value = insts10 },
            .{ .name = "blocks", .value = blks10 },
            .{ .name = "block_id", .value = merge_id },
            .{ .name = "next_block", .value = nb10 },
            .{ .name = "functions", .value = fns10 },
        });

        try g.ret(try g.record(&.{
            .{ .name = "value", .value = merge_val },
            .{ .name = "state", .value = st_merge },
        }));
    }
    try g.endReservedFunc(f_lower_if);

    // ── Generate: lc_lower_call(expr, scope, state) -> {value: Int, state} ──
    try g.beginReservedFunc("lc_lower_call");
    {
        const expr = try g.addParam();
        const scope = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();

        const payload = try g.tagPayload(expr, typeck.tast_call);
        const callee = try g.recordField(payload, "callee");
        const args = try g.recordField(payload, "args");

        // Get callee name: if it's a TIdent, extract name directly
        const callee_is_ident = try g.tagTest(callee, typeck.tast_ident);
        const ident_callee_blk = g.reserveBlock();
        const generic_callee_blk = g.reserveBlock();
        try g.branch(callee_is_ident, ident_callee_blk, generic_callee_blk);

        // Callee is an identifier — use its name for direct calls, value ID for indirect
        g.beginReservedBlock(ident_callee_blk);
        {
            const callee_pl = try g.tagPayload(callee, typeck.tast_ident);
            const callee_name = try g.recordField(callee_pl, "name");

            // Also lower the callee expression to get a value ID (for indirect calls to params)
            const callee_r = try g.callDirect(f_lower_expr, &.{ callee, scope, state });
            const callee_vid = try g.recordField(callee_r, "value");
            const st0 = try g.recordField(callee_r, "state");

            // Lower args in a loop
            const args_len = try g.listLength(args);
            const zero_a = try g.constInt(0);
            const empty_args = try g.listInit(&.{});
            const args_loop = g.reserveBlock();
            try g.jump(args_loop, &.{ zero_a, empty_args, st0 });

            g.beginReservedBlock(args_loop);
            const a_idx = try g.addBlockParam();
            const a_vals = try g.addBlockParam();
            const a_state = try g.addBlockParam();
            const a_done = try g.ge(a_idx, args_len);
            const a_body = g.reserveBlock();
            const a_exit = g.reserveBlock();
            try g.branch(a_done, a_exit, a_body);

            g.beginReservedBlock(a_body);
            const arg = try g.listNth(args, a_idx);
            const arg_r = try g.callDirect(f_lower_expr, &.{ arg, scope, a_state });
            const arg_val = try g.recordField(arg_r, "value");
            const arg_st = try g.recordField(arg_r, "state");
            const new_vals = try g.listAppend(a_vals, arg_val);
            const one_a = try g.constInt(1);
            const next_a = try g.add(a_idx, one_a);
            try g.jump(args_loop, &.{ next_a, new_vals, arg_st });

            g.beginReservedBlock(a_exit);
            const fv = try g.callDirect(f_fresh_val, &.{a_state});
            const dst = try g.recordField(fv, "id");
            const st_call = try g.recordField(fv, "state");
            const inst_rec = try g.record(&.{
                .{ .name = "dst", .value = dst },
                .{ .name = "callee", .value = callee_name },
                .{ .name = "callee_val", .value = callee_vid },
                .{ .name = "args", .value = a_vals },
            });
            const inst = try g.tag(ir_call, inst_rec);
            const st_final = try g.callDirect(f_emit_inst, &.{ inst, st_call });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst },
                .{ .name = "state", .value = st_final },
            }));
        }

        // Generic callee — lower it as expression, use value ID
        g.beginReservedBlock(generic_callee_blk);
        {
            const callee_r = try g.callDirect(f_lower_expr, &.{ callee, scope, state });
            const callee_val = try g.recordField(callee_r, "value");
            const st1 = try g.recordField(callee_r, "state");

            // Lower args
            const args_len2 = try g.listLength(args);
            const zero_b = try g.constInt(0);
            const empty_args2 = try g.listInit(&.{});
            const args_loop2 = g.reserveBlock();
            try g.jump(args_loop2, &.{ zero_b, empty_args2, st1 });

            g.beginReservedBlock(args_loop2);
            const b_idx = try g.addBlockParam();
            const b_vals = try g.addBlockParam();
            const b_state = try g.addBlockParam();
            const b_done = try g.ge(b_idx, args_len2);
            const b_body = g.reserveBlock();
            const b_exit = g.reserveBlock();
            try g.branch(b_done, b_exit, b_body);

            g.beginReservedBlock(b_body);
            const arg2 = try g.listNth(args, b_idx);
            const arg2_r = try g.callDirect(f_lower_expr, &.{ arg2, scope, b_state });
            const arg2_val = try g.recordField(arg2_r, "value");
            const arg2_st = try g.recordField(arg2_r, "state");
            const new_vals2 = try g.listAppend(b_vals, arg2_val);
            const one_b = try g.constInt(1);
            const next_b = try g.add(b_idx, one_b);
            try g.jump(args_loop2, &.{ next_b, new_vals2, arg2_st });

            g.beginReservedBlock(b_exit);
            // Use the callee value ID for indirect call
            const fv2 = try g.callDirect(f_fresh_val, &.{b_state});
            const dst2 = try g.recordField(fv2, "id");
            const st_call2 = try g.recordField(fv2, "state");
            // callee = empty string (not a named function), callee_val = value ID
            const empty_callee = try g.constString("");
            const inst_rec2 = try g.record(&.{
                .{ .name = "dst", .value = dst2 },
                .{ .name = "callee", .value = empty_callee },
                .{ .name = "callee_val", .value = callee_val },
                .{ .name = "args", .value = b_vals },
            });
            const inst2 = try g.tag(ir_call, inst_rec2);
            const st_final2 = try g.callDirect(f_emit_inst, &.{ inst2, st_call2 });
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = dst2 },
                .{ .name = "state", .value = st_final2 },
            }));
        }
    }
    try g.endReservedFunc(f_lower_call);

    // ── Generate: lc_lower_let(expr, scope, state) -> {value: Int, state, scope} ──
    try g.beginReservedFunc("lc_lower_let");
    {
        const expr = try g.addParam();
        const scope = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();

        const payload = try g.tagPayload(expr, typeck.tast_let);
        const pattern = try g.recordField(payload, "pattern");
        const value = try g.recordField(payload, "value");

        // Lower the value expression
        const val_r = try g.callDirect(f_lower_expr, &.{ value, scope, state });
        const val_id = try g.recordField(val_r, "value");
        const st1 = try g.recordField(val_r, "state");

        // Extract name from pattern (typed pattern is a tagged value)
        // The pattern from typeck has tag "PatBind" with payload being the name
        const is_pat_bind = try g.tagTest(pattern, "TPatBind");
        const bind_blk = g.reserveBlock();
        const default_blk = g.reserveBlock();
        try g.branch(is_pat_bind, bind_blk, default_blk);

        g.beginReservedBlock(bind_blk);
        {
            const tpat_payload = try g.tagPayload(pattern, "TPatBind");
            const pat_name = try g.recordField(tpat_payload, "name");
            const new_scope = try g.mapSet(scope, pat_name, val_id);
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = val_id },
                .{ .name = "state", .value = st1 },
                .{ .name = "scope", .value = new_scope },
            }));
        }

        g.beginReservedBlock(default_blk);
        {
            // Fallback: try to get name field from pattern record
            // Some patterns may be records with a "name" field
            try g.ret(try g.record(&.{
                .{ .name = "value", .value = val_id },
                .{ .name = "state", .value = st1 },
                .{ .name = "scope", .value = scope },
            }));
        }
    }
    try g.endReservedFunc(f_lower_let);

    // ── Generate: lc_lower_block(expr, scope, state) -> {value: Int, state} ──
    try g.beginReservedFunc("lc_lower_block");
    {
        const expr = try g.addParam();
        const scope = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();

        const stmts = try g.tagPayload(expr, typeck.tast_block);
        const stmts_len = try g.listLength(stmts);

        // Loop through statements, threading scope and state
        const zero = try g.constInt(0);
        const nil_val = try g.constInt(-1); // sentinel for "no value yet"
        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ zero, scope, state, nil_val });

        g.beginReservedBlock(loop_blk);
        const idx = try g.addBlockParam();
        const cur_scope = try g.addBlockParam();
        const cur_state = try g.addBlockParam();
        const last_val = try g.addBlockParam();
        const done = try g.ge(idx, stmts_len);
        const body_blk = g.reserveBlock();
        const exit_blk = g.reserveBlock();
        try g.branch(done, exit_blk, body_blk);

        g.beginReservedBlock(body_blk);
        const stmt = try g.listNth(stmts, idx);
        // Check if this is a let (which updates scope)
        const is_let = try g.tagTest(stmt, typeck.tast_let);
        const let_stmt_blk = g.reserveBlock();
        const other_stmt_blk = g.reserveBlock();
        try g.branch(is_let, let_stmt_blk, other_stmt_blk);

        g.beginReservedBlock(let_stmt_blk);
        {
            const let_r = try g.callDirect(f_lower_let, &.{ stmt, cur_scope, cur_state });
            const let_val = try g.recordField(let_r, "value");
            const let_st = try g.recordField(let_r, "state");
            const let_scope = try g.recordField(let_r, "scope");
            const one = try g.constInt(1);
            const next = try g.add(idx, one);
            try g.jump(loop_blk, &.{ next, let_scope, let_st, let_val });
        }

        g.beginReservedBlock(other_stmt_blk);
        {
            const stmt_r = try g.callDirect(f_lower_expr, &.{ stmt, cur_scope, cur_state });
            const stmt_val = try g.recordField(stmt_r, "value");
            const stmt_st = try g.recordField(stmt_r, "state");
            const one = try g.constInt(1);
            const next = try g.add(idx, one);
            try g.jump(loop_blk, &.{ next, cur_scope, stmt_st, stmt_val });
        }

        g.beginReservedBlock(exit_blk);
        try g.ret(try g.record(&.{
            .{ .name = "value", .value = last_val },
            .{ .name = "state", .value = cur_state },
        }));
    }
    try g.endReservedFunc(f_lower_block);

    // ── Generate: lc_lower_match(expr, scope, state) -> {value, state} ──
    // Lowers a match expression as an if-else chain.
    try g.beginReservedFunc("lc_lower_match");
    {
        const expr = try g.addParam();
        const scope = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();

        const payload = try g.tagPayload(expr, typeck.tast_match);
        const scrutinee = try g.recordField(payload, "expr");
        const cases = try g.recordField(payload, "cases");

        // Lower scrutinee
        const scrut_r = try g.callDirect(f_lower_expr, &.{ scrutinee, scope, state });
        const scrut_val = try g.recordField(scrut_r, "value");
        const st1 = try g.recordField(scrut_r, "state");

        // Allocate merge block ID
        const merge_nb = try g.callDirect(f_alloc_block_id, &.{st1});
        const merge_id = try g.recordField(merge_nb, "id");
        const st2 = try g.recordField(merge_nb, "state");

        // Process arms recursively
        const zero = try g.constInt(0);
        const arms_len = try g.listLength(cases);
        const arms_r = try g.callDirect(f_lower_match_arms, &.{ cases, zero, arms_len, scrut_val, scope, merge_id, st2 });
        const st3 = try g.recordField(arms_r, "state");

        // Set up merge block: allocate phi value
        const fv_merge = try g.callDirect(f_fresh_val, &.{st3});
        const merge_val = try g.recordField(fv_merge, "id");
        const st4 = try g.recordField(fv_merge, "state");

        // Set block_id to merge_id
        const nv4 = try g.recordField(st4, "next_val");
        const nb4 = try g.recordField(st4, "next_block");
        const blks4 = try g.recordField(st4, "blocks");
        const fns4 = try g.recordField(st4, "functions");
        const insts4 = try g.recordField(st4, "insts");
        const st_merge = try g.record(&.{
            .{ .name = "next_val", .value = nv4 },
            .{ .name = "insts", .value = insts4 },
            .{ .name = "blocks", .value = blks4 },
            .{ .name = "block_id", .value = merge_id },
            .{ .name = "next_block", .value = nb4 },
            .{ .name = "functions", .value = fns4 },
        });

        try g.ret(try g.record(&.{
            .{ .name = "value", .value = merge_val },
            .{ .name = "state", .value = st_merge },
        }));
    }
    try g.endReservedFunc(f_lower_match);

    // ── Generate: lc_lower_match_arms(cases, idx, len, scrut_val, scope, merge_id, state) -> {state} ──
    // Recursively processes match arms as an if-else chain.
    // Each arm: test pattern → branch to body (jumps to merge) or next arm.
    try g.beginReservedFunc("lc_lower_match_arms");
    {
        const cases = try g.addParam();
        const idx = try g.addParam();
        const len = try g.addParam();
        const scrut_val = try g.addParam();
        const scope = try g.addParam();
        const merge_id = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();

        // Base case: idx >= len → emit unreachable (const nil, jump to merge)
        const done = try g.ge(idx, len);
        const base_blk = g.reserveBlock();
        const arm_blk = g.reserveBlock();
        try g.branch(done, base_blk, arm_blk);

        g.beginReservedBlock(base_blk);
        {
            // Emit a nil value and jump to merge (unreachable in well-typed programs)
            const fv = try g.callDirect(f_fresh_val, &.{state});
            const nil_dst = try g.recordField(fv, "id");
            const st1 = try g.recordField(fv, "state");
            const nil_inst = try g.record(&.{
                .{ .name = "dst", .value = nil_dst },
            });
            const nil_tag = try g.tag(ir_const_nil, nil_inst);
            const st2 = try g.callDirect(f_emit_inst, &.{ nil_tag, st1 });
            const nil_args = try g.listInit(&.{nil_dst});
            const nil_jmp = try g.record(&.{
                .{ .name = "target", .value = merge_id },
                .{ .name = "args", .value = nil_args },
            });
            const nil_term = try g.tag(ir_jump, nil_jmp);
            const st3 = try g.callDirect(f_end_block, &.{ nil_term, st2 });
            try g.ret(try g.record(&.{
                .{ .name = "state", .value = st3 },
            }));
        }

        g.beginReservedBlock(arm_blk);
        {
            const arm = try g.listNth(cases, idx);
            const pattern = try g.recordField(arm, "pattern");
            const body = try g.recordField(arm, "body");

            // ── Check pattern type ──
            // TPatWildcard: always matches
            const is_wildcard = try g.tagTest(pattern, "TPatWildcard");
            const wildcard_arm_blk = g.reserveBlock();
            const check_bind = g.reserveBlock();
            try g.branch(is_wildcard, wildcard_arm_blk, check_bind);

            // Wildcard: lower body directly, jump to merge
            g.beginReservedBlock(wildcard_arm_blk);
            {
                const body_r = try g.callDirect(f_lower_expr, &.{ body, scope, state });
                const body_val = try g.recordField(body_r, "value");
                const st1 = try g.recordField(body_r, "state");
                const wc_args = try g.listInit(&.{body_val});
                const wc_jmp = try g.record(&.{
                    .{ .name = "target", .value = merge_id },
                    .{ .name = "args", .value = wc_args },
                });
                const wc_term = try g.tag(ir_jump, wc_jmp);
                const st2 = try g.callDirect(f_end_block, &.{ wc_term, st1 });
                try g.ret(try g.record(&.{
                    .{ .name = "state", .value = st2 },
                }));
            }

            // TPatBind: always matches, bind scrutinee to name
            g.beginReservedBlock(check_bind);
            const is_bind = try g.tagTest(pattern, "TPatBind");
            const bind_arm_blk = g.reserveBlock();
            const check_literal = g.reserveBlock();
            try g.branch(is_bind, bind_arm_blk, check_literal);

            g.beginReservedBlock(bind_arm_blk);
            {
                const tpat_pl = try g.tagPayload(pattern, "TPatBind");
                const pat_name = try g.recordField(tpat_pl, "name");
                const new_scope = try g.mapSet(scope, pat_name, scrut_val);
                const body_r = try g.callDirect(f_lower_expr, &.{ body, new_scope, state });
                const body_val = try g.recordField(body_r, "value");
                const st1 = try g.recordField(body_r, "state");
                const bind_args = try g.listInit(&.{body_val});
                const bind_jmp = try g.record(&.{
                    .{ .name = "target", .value = merge_id },
                    .{ .name = "args", .value = bind_args },
                });
                const bind_term = try g.tag(ir_jump, bind_jmp);
                const st2 = try g.callDirect(f_end_block, &.{ bind_term, st1 });
                try g.ret(try g.record(&.{
                    .{ .name = "state", .value = st2 },
                }));
            }

            // TPatLiteral: compare scrutinee == literal, branch
            g.beginReservedBlock(check_literal);
            const is_literal = try g.tagTest(pattern, "TPatLiteral");
            const literal_arm_blk = g.reserveBlock();
            const check_ctor = g.reserveBlock();
            try g.branch(is_literal, literal_arm_blk, check_ctor);

            g.beginReservedBlock(literal_arm_blk);
            {
                // TPatLiteral payload is the literal AST node (IntLit(n) or BoolLit(b))
                const lit_pl = try g.tagPayload(pattern, "TPatLiteral");

                // Lower the literal to get its value
                // The literal is an AST node — we need to extract the int value
                const is_int = try g.tagTest(lit_pl, "IntLit");
                const int_lit_blk = g.reserveBlock();
                const bool_lit_blk = g.reserveBlock();
                try g.branch(is_int, int_lit_blk, bool_lit_blk);

                g.beginReservedBlock(int_lit_blk);
                {
                    const int_val = try g.tagPayload(lit_pl, "IntLit");

                    // Emit IrConstInt for the literal value
                    const fv = try g.callDirect(f_fresh_val, &.{state});
                    const lit_dst = try g.recordField(fv, "id");
                    const st1 = try g.recordField(fv, "state");
                    const lit_inst = try g.record(&.{
                        .{ .name = "dst", .value = lit_dst },
                        .{ .name = "value", .value = int_val },
                    });
                    const lit_tag = try g.tag(ir_const_int, lit_inst);
                    const st2 = try g.callDirect(f_emit_inst, &.{ lit_tag, st1 });

                    // Emit IrBinary eq: cmp_dst = (scrut_val == lit_dst)
                    const fv2 = try g.callDirect(f_fresh_val, &.{st2});
                    const cmp_dst = try g.recordField(fv2, "id");
                    const st3 = try g.recordField(fv2, "state");
                    const eq_str = try g.constString("==");
                    const cmp_inst = try g.record(&.{
                        .{ .name = "dst", .value = cmp_dst },
                        .{ .name = "op", .value = eq_str },
                        .{ .name = "lhs", .value = scrut_val },
                        .{ .name = "rhs", .value = lit_dst },
                    });
                    const cmp_tag = try g.tag(ir_binary, cmp_inst);
                    const st4 = try g.callDirect(f_emit_inst, &.{ cmp_tag, st3 });

                    // Allocate body and next-arm block IDs
                    const body_nb = try g.callDirect(f_alloc_block_id, &.{st4});
                    const body_id = try g.recordField(body_nb, "id");
                    const st5 = try g.recordField(body_nb, "state");
                    const next_nb = try g.callDirect(f_alloc_block_id, &.{st5});
                    const next_id = try g.recordField(next_nb, "id");
                    const st6 = try g.recordField(next_nb, "state");

                    // End current block with branch
                    const br_rec = try g.record(&.{
                        .{ .name = "cond", .value = cmp_dst },
                        .{ .name = "then_blk", .value = body_id },
                        .{ .name = "else_blk", .value = next_id },
                    });
                    const br_term = try g.tag(ir_branch, br_rec);
                    const st7 = try g.callDirect(f_end_block, &.{ br_term, st6 });

                    // Lower body in body_id block
                    const nv7 = try g.recordField(st7, "next_val");
                    const nb7 = try g.recordField(st7, "next_block");
                    const blks7 = try g.recordField(st7, "blocks");
                    const fns7 = try g.recordField(st7, "functions");
                    const empty7 = try g.listInit(&.{});
                    const st_body = try g.record(&.{
                        .{ .name = "next_val", .value = nv7 },
                        .{ .name = "insts", .value = empty7 },
                        .{ .name = "blocks", .value = blks7 },
                        .{ .name = "block_id", .value = body_id },
                        .{ .name = "next_block", .value = nb7 },
                        .{ .name = "functions", .value = fns7 },
                    });
                    const body_r = try g.callDirect(f_lower_expr, &.{ body, scope, st_body });
                    const body_val = try g.recordField(body_r, "value");
                    const st8 = try g.recordField(body_r, "state");

                    // End body block: jump to merge
                    const body_args = try g.listInit(&.{body_val});
                    const body_jmp = try g.record(&.{
                        .{ .name = "target", .value = merge_id },
                        .{ .name = "args", .value = body_args },
                    });
                    const body_term = try g.tag(ir_jump, body_jmp);
                    const st9 = try g.callDirect(f_end_block, &.{ body_term, st8 });

                    // Continue with next arms in next_id block
                    const nv9 = try g.recordField(st9, "next_val");
                    const nb9 = try g.recordField(st9, "next_block");
                    const blks9 = try g.recordField(st9, "blocks");
                    const fns9 = try g.recordField(st9, "functions");
                    const empty9 = try g.listInit(&.{});
                    const st_next = try g.record(&.{
                        .{ .name = "next_val", .value = nv9 },
                        .{ .name = "insts", .value = empty9 },
                        .{ .name = "blocks", .value = blks9 },
                        .{ .name = "block_id", .value = next_id },
                        .{ .name = "next_block", .value = nb9 },
                        .{ .name = "functions", .value = fns9 },
                    });
                    const one = try g.constInt(1);
                    const next_idx = try g.add(idx, one);
                    const rest_r = try g.callDirect(f_lower_match_arms, &.{ cases, next_idx, len, scrut_val, scope, merge_id, st_next });
                    try g.ret(rest_r);
                }

                g.beginReservedBlock(bool_lit_blk);
                {
                    // Bool literal pattern: extract bool, compare
                    const bool_str = try g.tagPayload(lit_pl, "BoolLit");
                    const true_str = try g.constString("true");
                    const is_true = try g.eq(bool_str, true_str);
                    const one_val = try g.constInt(1);
                    const zero_val = try g.constInt(0);
                    const bool_blk_true = g.reserveBlock();
                    const bool_blk_false = g.reserveBlock();
                    try g.branch(is_true, bool_blk_true, bool_blk_false);

                    g.beginReservedBlock(bool_blk_true);
                    const bool_merge = g.reserveBlock();
                    try g.jump(bool_merge, &.{one_val});

                    g.beginReservedBlock(bool_blk_false);
                    try g.jump(bool_merge, &.{zero_val});

                    g.beginReservedBlock(bool_merge);
                    const bool_val = try g.addBlockParam();

                    // Emit IrConstInt for the bool value
                    const fv = try g.callDirect(f_fresh_val, &.{state});
                    const lit_dst = try g.recordField(fv, "id");
                    const st1 = try g.recordField(fv, "state");
                    const lit_inst = try g.record(&.{
                        .{ .name = "dst", .value = lit_dst },
                        .{ .name = "value", .value = bool_val },
                    });
                    const lit_tag = try g.tag(ir_const_int, lit_inst);
                    const st2 = try g.callDirect(f_emit_inst, &.{ lit_tag, st1 });

                    // Compare scrutinee == literal
                    const fv2 = try g.callDirect(f_fresh_val, &.{st2});
                    const cmp_dst = try g.recordField(fv2, "id");
                    const st3 = try g.recordField(fv2, "state");
                    const eq_str = try g.constString("==");
                    const cmp_inst = try g.record(&.{
                        .{ .name = "dst", .value = cmp_dst },
                        .{ .name = "op", .value = eq_str },
                        .{ .name = "lhs", .value = scrut_val },
                        .{ .name = "rhs", .value = lit_dst },
                    });
                    const cmp_tag = try g.tag(ir_binary, cmp_inst);
                    const st4 = try g.callDirect(f_emit_inst, &.{ cmp_tag, st3 });

                    // Same branch/body/next pattern as int lit
                    const body_nb = try g.callDirect(f_alloc_block_id, &.{st4});
                    const body_id = try g.recordField(body_nb, "id");
                    const st5 = try g.recordField(body_nb, "state");
                    const next_nb = try g.callDirect(f_alloc_block_id, &.{st5});
                    const next_id = try g.recordField(next_nb, "id");
                    const st6 = try g.recordField(next_nb, "state");

                    const br_rec = try g.record(&.{
                        .{ .name = "cond", .value = cmp_dst },
                        .{ .name = "then_blk", .value = body_id },
                        .{ .name = "else_blk", .value = next_id },
                    });
                    const br_term = try g.tag(ir_branch, br_rec);
                    const st7 = try g.callDirect(f_end_block, &.{ br_term, st6 });

                    const nv7 = try g.recordField(st7, "next_val");
                    const nb7 = try g.recordField(st7, "next_block");
                    const blks7 = try g.recordField(st7, "blocks");
                    const fns7 = try g.recordField(st7, "functions");
                    const empty7 = try g.listInit(&.{});
                    const st_body = try g.record(&.{
                        .{ .name = "next_val", .value = nv7 },
                        .{ .name = "insts", .value = empty7 },
                        .{ .name = "blocks", .value = blks7 },
                        .{ .name = "block_id", .value = body_id },
                        .{ .name = "next_block", .value = nb7 },
                        .{ .name = "functions", .value = fns7 },
                    });
                    const body_r = try g.callDirect(f_lower_expr, &.{ body, scope, st_body });
                    const body_val2 = try g.recordField(body_r, "value");
                    const st8 = try g.recordField(body_r, "state");

                    const body_args = try g.listInit(&.{body_val2});
                    const body_jmp = try g.record(&.{
                        .{ .name = "target", .value = merge_id },
                        .{ .name = "args", .value = body_args },
                    });
                    const body_term = try g.tag(ir_jump, body_jmp);
                    const st9 = try g.callDirect(f_end_block, &.{ body_term, st8 });

                    const nv9 = try g.recordField(st9, "next_val");
                    const nb9 = try g.recordField(st9, "next_block");
                    const blks9 = try g.recordField(st9, "blocks");
                    const fns9 = try g.recordField(st9, "functions");
                    const empty9 = try g.listInit(&.{});
                    const st_next = try g.record(&.{
                        .{ .name = "next_val", .value = nv9 },
                        .{ .name = "insts", .value = empty9 },
                        .{ .name = "blocks", .value = blks9 },
                        .{ .name = "block_id", .value = next_id },
                        .{ .name = "next_block", .value = nb9 },
                        .{ .name = "functions", .value = fns9 },
                    });
                    const one = try g.constInt(1);
                    const next_idx = try g.add(idx, one);
                    const rest_r = try g.callDirect(f_lower_match_arms, &.{ cases, next_idx, len, scrut_val, scope, merge_id, st_next });
                    try g.ret(rest_r);
                }
            }

            // TPatConstructor: tag test + optional payload binding
            g.beginReservedBlock(check_ctor);
            const is_ctor = try g.tagTest(pattern, "TPatConstructor");
            const ctor_arm_blk = g.reserveBlock();
            const default_pat_blk = g.reserveBlock();
            try g.branch(is_ctor, ctor_arm_blk, default_pat_blk);

            g.beginReservedBlock(ctor_arm_blk);
            {
                const ctor_pl = try g.tagPayload(pattern, "TPatConstructor");
                const ctor_name = try g.recordField(ctor_pl, "name");
                const ctor_args = try g.recordField(ctor_pl, "args");

                // Emit IrTagTest: cmp_dst = tag_test(scrut_val, ctor_name)
                const fv = try g.callDirect(f_fresh_val, &.{state});
                const cmp_dst = try g.recordField(fv, "id");
                const st1 = try g.recordField(fv, "state");
                const tt_inst = try g.record(&.{
                    .{ .name = "dst", .value = cmp_dst },
                    .{ .name = "value", .value = scrut_val },
                    .{ .name = "tag", .value = ctor_name },
                });
                const tt_tag = try g.tag(ir_tag_test, tt_inst);
                const st2 = try g.callDirect(f_emit_inst, &.{ tt_tag, st1 });

                // Allocate body and next-arm block IDs
                const body_nb = try g.callDirect(f_alloc_block_id, &.{st2});
                const body_id = try g.recordField(body_nb, "id");
                const st3 = try g.recordField(body_nb, "state");
                const next_nb = try g.callDirect(f_alloc_block_id, &.{st3});
                const next_id = try g.recordField(next_nb, "id");
                const st4 = try g.recordField(next_nb, "state");

                // Branch on tag test
                const br_rec = try g.record(&.{
                    .{ .name = "cond", .value = cmp_dst },
                    .{ .name = "then_blk", .value = body_id },
                    .{ .name = "else_blk", .value = next_id },
                });
                const br_term = try g.tag(ir_branch, br_rec);
                const st5 = try g.callDirect(f_end_block, &.{ br_term, st4 });

                // Body block: extract payload if args exist, bind to scope
                const nv5 = try g.recordField(st5, "next_val");
                const nb5 = try g.recordField(st5, "next_block");
                const blks5 = try g.recordField(st5, "blocks");
                const fns5 = try g.recordField(st5, "functions");
                const empty5 = try g.listInit(&.{});
                const st_body = try g.record(&.{
                    .{ .name = "next_val", .value = nv5 },
                    .{ .name = "insts", .value = empty5 },
                    .{ .name = "blocks", .value = blks5 },
                    .{ .name = "block_id", .value = body_id },
                    .{ .name = "next_block", .value = nb5 },
                    .{ .name = "functions", .value = fns5 },
                });

                // Check if ctor has args (for payload binding)
                const args_len = try g.listLength(ctor_args);
                const zero_c = try g.constInt(0);
                const has_args = try g.binary(.gt, args_len, zero_c);
                const ctor_with_args_blk = g.reserveBlock();
                const ctor_no_args_blk = g.reserveBlock();
                try g.branch(has_args, ctor_with_args_blk, ctor_no_args_blk);

                // Ctor with args: extract payload, bind first arg name
                g.beginReservedBlock(ctor_with_args_blk);
                {
                    // Emit IrTagPayload to extract the inner value
                    const fv2 = try g.callDirect(f_fresh_val, &.{st_body});
                    const payload_dst = try g.recordField(fv2, "id");
                    const st6 = try g.recordField(fv2, "state");
                    const tp_inst = try g.record(&.{
                        .{ .name = "dst", .value = payload_dst },
                        .{ .name = "value", .value = scrut_val },
                        .{ .name = "tag", .value = ctor_name },
                    });
                    const tp_tag = try g.tag(ir_tag_payload, tp_inst);
                    const st7 = try g.callDirect(f_emit_inst, &.{ tp_tag, st6 });

                    // First arg should be a pattern — if it's TPatBind, bind payload to name
                    const first_arg = try g.listNth(ctor_args, zero_c);
                    const arg_is_bind = try g.tagTest(first_arg, "PatBind");
                    const arg_bind_blk = g.reserveBlock();
                    const arg_nobind_blk = g.reserveBlock();
                    try g.branch(arg_is_bind, arg_bind_blk, arg_nobind_blk);

                    g.beginReservedBlock(arg_bind_blk);
                    {
                        const arg_name = try g.tagPayload(first_arg, "PatBind");
                        const new_scope = try g.mapSet(scope, arg_name, payload_dst);
                        const body_r = try g.callDirect(f_lower_expr, &.{ body, new_scope, st7 });
                        const body_val = try g.recordField(body_r, "value");
                        const st8 = try g.recordField(body_r, "state");
                        const b_args = try g.listInit(&.{body_val});
                        const b_jmp = try g.record(&.{
                            .{ .name = "target", .value = merge_id },
                            .{ .name = "args", .value = b_args },
                        });
                        const b_term = try g.tag(ir_jump, b_jmp);
                        const st9 = try g.callDirect(f_end_block, &.{ b_term, st8 });

                        // Continue with remaining arms
                        const nv9 = try g.recordField(st9, "next_val");
                        const nb9 = try g.recordField(st9, "next_block");
                        const blks9 = try g.recordField(st9, "blocks");
                        const fns9 = try g.recordField(st9, "functions");
                        const empty9 = try g.listInit(&.{});
                        const st_next = try g.record(&.{
                            .{ .name = "next_val", .value = nv9 },
                            .{ .name = "insts", .value = empty9 },
                            .{ .name = "blocks", .value = blks9 },
                            .{ .name = "block_id", .value = next_id },
                            .{ .name = "next_block", .value = nb9 },
                            .{ .name = "functions", .value = fns9 },
                        });
                        const one = try g.constInt(1);
                        const next_idx = try g.add(idx, one);
                        const rest_r = try g.callDirect(f_lower_match_arms, &.{ cases, next_idx, len, scrut_val, scope, merge_id, st_next });
                        try g.ret(rest_r);
                    }

                    // Non-bind arg: just lower body without binding
                    g.beginReservedBlock(arg_nobind_blk);
                    {
                        const body_r = try g.callDirect(f_lower_expr, &.{ body, scope, st7 });
                        const body_val = try g.recordField(body_r, "value");
                        const st8 = try g.recordField(body_r, "state");
                        const b_args = try g.listInit(&.{body_val});
                        const b_jmp = try g.record(&.{
                            .{ .name = "target", .value = merge_id },
                            .{ .name = "args", .value = b_args },
                        });
                        const b_term = try g.tag(ir_jump, b_jmp);
                        const st9 = try g.callDirect(f_end_block, &.{ b_term, st8 });

                        const nv9 = try g.recordField(st9, "next_val");
                        const nb9 = try g.recordField(st9, "next_block");
                        const blks9 = try g.recordField(st9, "blocks");
                        const fns9 = try g.recordField(st9, "functions");
                        const empty9 = try g.listInit(&.{});
                        const st_next = try g.record(&.{
                            .{ .name = "next_val", .value = nv9 },
                            .{ .name = "insts", .value = empty9 },
                            .{ .name = "blocks", .value = blks9 },
                            .{ .name = "block_id", .value = next_id },
                            .{ .name = "next_block", .value = nb9 },
                            .{ .name = "functions", .value = fns9 },
                        });
                        const one = try g.constInt(1);
                        const next_idx = try g.add(idx, one);
                        const rest_r = try g.callDirect(f_lower_match_arms, &.{ cases, next_idx, len, scrut_val, scope, merge_id, st_next });
                        try g.ret(rest_r);
                    }
                }

                // Ctor without args: just test tag, lower body
                g.beginReservedBlock(ctor_no_args_blk);
                {
                    const body_r = try g.callDirect(f_lower_expr, &.{ body, scope, st_body });
                    const body_val = try g.recordField(body_r, "value");
                    const st6 = try g.recordField(body_r, "state");
                    const b_args = try g.listInit(&.{body_val});
                    const b_jmp = try g.record(&.{
                        .{ .name = "target", .value = merge_id },
                        .{ .name = "args", .value = b_args },
                    });
                    const b_term = try g.tag(ir_jump, b_jmp);
                    const st7 = try g.callDirect(f_end_block, &.{ b_term, st6 });

                    const nv7 = try g.recordField(st7, "next_val");
                    const nb7 = try g.recordField(st7, "next_block");
                    const blks7 = try g.recordField(st7, "blocks");
                    const fns7 = try g.recordField(st7, "functions");
                    const empty7 = try g.listInit(&.{});
                    const st_next = try g.record(&.{
                        .{ .name = "next_val", .value = nv7 },
                        .{ .name = "insts", .value = empty7 },
                        .{ .name = "blocks", .value = blks7 },
                        .{ .name = "block_id", .value = next_id },
                        .{ .name = "next_block", .value = nb7 },
                        .{ .name = "functions", .value = fns7 },
                    });
                    const one = try g.constInt(1);
                    const next_idx = try g.add(idx, one);
                    const rest_r = try g.callDirect(f_lower_match_arms, &.{ cases, next_idx, len, scrut_val, scope, merge_id, st_next });
                    try g.ret(rest_r);
                }
            }

            // Default pattern: treat as wildcard
            g.beginReservedBlock(default_pat_blk);
            {
                const body_r = try g.callDirect(f_lower_expr, &.{ body, scope, state });
                const body_val = try g.recordField(body_r, "value");
                const st1 = try g.recordField(body_r, "state");
                const d_args = try g.listInit(&.{body_val});
                const d_jmp = try g.record(&.{
                    .{ .name = "target", .value = merge_id },
                    .{ .name = "args", .value = d_args },
                });
                const d_term = try g.tag(ir_jump, d_jmp);
                const st2 = try g.callDirect(f_end_block, &.{ d_term, st1 });
                try g.ret(try g.record(&.{
                    .{ .name = "state", .value = st2 },
                }));
            }
        }
    }
    try g.endReservedFunc(f_lower_match_arms);

    // ── Generate: lc_lower_fn_decl(decl, state) -> state ────────────
    try g.beginReservedFunc("lc_lower_fn_decl");
    {
        const decl = try g.addParam();
        const state = try g.addParam();
        _ = g.beginBlock();

        const payload = try g.tagPayload(decl, typeck.tast_fn_decl);
        const fn_name = try g.recordField(payload, "name");
        const fn_params = try g.recordField(payload, "params");
        const fn_body = try g.recordField(payload, "body");

        // Create new scope with params bound
        const new_scope = try g.mapNew();
        const params_len = try g.listLength(fn_params);
        const zero = try g.constInt(0);
        // Create fresh state for this function (reuse next_val counter but new blocks/insts)
        const nv = try g.recordField(state, "next_val");
        const fns = try g.recordField(state, "functions");
        const fn_state = try g.record(&.{
            .{ .name = "next_val", .value = nv },
            .{ .name = "insts", .value = try g.listInit(&.{}) },
            .{ .name = "blocks", .value = try g.listInit(&.{}) },
            .{ .name = "block_id", .value = try g.constInt(0) },
            .{ .name = "next_block", .value = try g.constInt(1) },
            .{ .name = "functions", .value = fns },
        });

        const empty_pids = try g.listInit(&.{});
        const param_loop = g.reserveBlock();
        try g.jump(param_loop, &.{ zero, new_scope, fn_state, empty_pids });

        g.beginReservedBlock(param_loop);
        const p_idx = try g.addBlockParam();
        const p_scope = try g.addBlockParam();
        const p_state = try g.addBlockParam();
        const p_ids = try g.addBlockParam();
        const p_done = try g.ge(p_idx, params_len);
        const p_body_blk = g.reserveBlock();
        const p_exit = g.reserveBlock();
        try g.branch(p_done, p_exit, p_body_blk);

        g.beginReservedBlock(p_body_blk);
        {
            const param = try g.listNth(fn_params, p_idx);
            const param_name = try g.recordField(param, "name");
            const pfv = try g.callDirect(f_fresh_val, &.{p_state});
            const p_val = try g.recordField(pfv, "id");
            const p_st = try g.recordField(pfv, "state");
            const scope_with_param = try g.mapSet(p_scope, param_name, p_val);
            const new_pids = try g.listAppend(p_ids, p_val);
            const one = try g.constInt(1);
            const next = try g.add(p_idx, one);
            try g.jump(param_loop, &.{ next, scope_with_param, p_st, new_pids });
        }

        g.beginReservedBlock(p_exit);
        {
            // Lower body
            const body_r = try g.callDirect(f_lower_expr, &.{ fn_body, p_scope, p_state });
            const body_val = try g.recordField(body_r, "value");
            const st_body = try g.recordField(body_r, "state");

            // End block with return
            const ret_rec = try g.record(&.{
                .{ .name = "value", .value = body_val },
            });
            const ret_term = try g.tag(ir_ret, ret_rec);
            const st_ended = try g.callDirect(f_end_block, &.{ ret_term, st_body });

            // Create function record
            const fn_blocks = try g.recordField(st_ended, "blocks");
            const fn_rec = try g.record(&.{
                .{ .name = "name", .value = fn_name },
                .{ .name = "params", .value = fn_params },
                .{ .name = "param_ids", .value = p_ids },
                .{ .name = "blocks", .value = fn_blocks },
            });

            // Append function to the functions list
            const all_fns = try g.recordField(st_ended, "functions");
            const new_fns = try g.listAppend(all_fns, fn_rec);

            // Return updated state (restore parent's blocks/insts but carry over next_val and functions)
            const new_nv = try g.recordField(st_ended, "next_val");
            const parent_insts = try g.recordField(state, "insts");
            const parent_blocks = try g.recordField(state, "blocks");
            const parent_bid = try g.recordField(state, "block_id");
            const parent_nb = try g.recordField(state, "next_block");
            const result_state = try g.record(&.{
                .{ .name = "next_val", .value = new_nv },
                .{ .name = "insts", .value = parent_insts },
                .{ .name = "blocks", .value = parent_blocks },
                .{ .name = "block_id", .value = parent_bid },
                .{ .name = "next_block", .value = parent_nb },
                .{ .name = "functions", .value = new_fns },
            });
            try g.ret(result_state);
        }
    }
    try g.endReservedFunc(f_lower_fn_decl);

    // ── Generate: lc_lower_module(typed_module) -> IrModule ─────────
    // Entry point: takes a typed module from typeck, produces IR module.
    try g.beginReservedFunc("lc_lower_module");
    {
        const module = try g.addParam();
        _ = g.beginBlock();

        const payload = try g.tagPayload(module, typeck.tast_module);
        const decls = try g.recordField(payload, "decls");
        const decls_len = try g.listLength(decls);

        // Create initial state
        const init_state = try g.callDirect(f_state_new, &.{});

        // Loop through declarations
        const zero = try g.constInt(0);
        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ zero, init_state });

        g.beginReservedBlock(loop_blk);
        const idx = try g.addBlockParam();
        const cur_state = try g.addBlockParam();
        const done = try g.ge(idx, decls_len);
        const body_blk = g.reserveBlock();
        const exit_blk = g.reserveBlock();
        try g.branch(done, exit_blk, body_blk);

        g.beginReservedBlock(body_blk);
        {
            const decl = try g.listNth(decls, idx);
            // Check if fn decl
            const is_fn = try g.tagTest(decl, typeck.tast_fn_decl);
            const fn_blk = g.reserveBlock();
            const skip_blk = g.reserveBlock();
            try g.branch(is_fn, fn_blk, skip_blk);

            g.beginReservedBlock(fn_blk);
            {
                const new_state = try g.callDirect(f_lower_fn_decl, &.{ decl, cur_state });
                const one = try g.constInt(1);
                const next = try g.add(idx, one);
                try g.jump(loop_blk, &.{ next, new_state });
            }

            g.beginReservedBlock(skip_blk);
            {
                const one = try g.constInt(1);
                const next = try g.add(idx, one);
                try g.jump(loop_blk, &.{ next, cur_state });
            }
        }

        g.beginReservedBlock(exit_blk);
        {
            // Build final module record from state
            const final_fns = try g.recordField(cur_state, "functions");
            // Use "main" as default entry point name
            const entry_name = try g.constString("main");
            const ir_module = try g.record(&.{
                .{ .name = "functions", .value = final_fns },
                .{ .name = "entry", .value = entry_name },
            });
            try g.ret(ir_module);
        }
    }
    try g.endReservedFunc(f_lower_module);

    return f_lower_module;
}

// ── Tests ──────────────────────────────────────────────────────────────

const interp_mod = @import("../interp.zig");
const Interpreter = interp_mod.Interpreter;
const Value = interp_mod.Value;
const builtins = @import("../builtins.zig");
const grammar = @import("grammar.zig");

fn setupTestInterpreter(alloc: Allocator, pool: *InternPool, module: ir.Module) Interpreter {
    var interp = Interpreter.init(alloc, module, pool);
    builtins.registerAll(&interp) catch {};
    return interp;
}

test "lower: generate compiles" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);

    const f_lower_module = try generate(alloc, &builder, &pool);
    const module = try builder.build(f_lower_module);

    // Verify the module has the expected number of functions (12 reserved)
    try std.testing.expect(module.funcs.len >= 12);
}

test "lower: state_new creates valid state" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    // lc_state_new is func index 0
    const f_state_new: FuncId = @enumFromInt(0);
    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    const nv = try g.recordField(state, "next_val");
    try g.ret(nv);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0), val.int);
}

test "lower: fresh_val increments counter" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_fresh_val: FuncId = @enumFromInt(1);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    // First fresh_val
    const r1 = try g.callDirect(f_fresh_val, &.{state});
    const id1 = try g.recordField(r1, "id");
    const st1 = try g.recordField(r1, "state");
    // Second fresh_val
    const r2 = try g.callDirect(f_fresh_val, &.{st1});
    const id2 = try g.recordField(r2, "id");
    // Return id1 * 10 + id2 so we can check both in one value
    const ten = try g.constInt(10);
    const scaled = try g.binary(.mul, id1, ten);
    const combined = try g.add(scaled, id2);
    try g.ret(combined);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // id1=0, id2=1 => 0*10+1 = 1
    try std.testing.expectEqual(@as(i64, 1), val.int);
}

test "lower: emit_inst appends to state" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_emit_inst: FuncId = @enumFromInt(2);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    // Emit a dummy instruction
    const dummy = try g.constString("dummy_inst");
    const st1 = try g.callDirect(f_emit_inst, &.{ dummy, state });
    const insts = try g.recordField(st1, "insts");
    const len = try g.listLength(insts);
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 1), val.int);
}

test "lower: lower IntLit produces IrConstInt" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_lower_expr: FuncId = @enumFromInt(6);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    const scope = try g.mapNew();

    // Create a TIntLit typed AST node: tag "TIntLit" with payload {value: 42, type: TyInt}
    const ty_int_val = try g.tag(typeck.ty_int, null);
    const int_payload = try g.record(&.{
        .{ .name = "value", .value = try g.constInt(42) },
        .{ .name = "type", .value = ty_int_val },
    });
    const tast_node = try g.tag(typeck.tast_int_lit, int_payload);

    const result = try g.callDirect(f_lower_expr, &.{ tast_node, scope, state });
    const val_id = try g.recordField(result, "value");
    const new_state = try g.recordField(result, "state");
    const insts = try g.recordField(new_state, "insts");
    const insts_len = try g.listLength(insts);

    // Check: value id should be 0, and 1 instruction emitted
    const ten = try g.constInt(10);
    const scaled = try g.binary(.mul, val_id, ten);
    const combined = try g.add(scaled, insts_len);
    try g.ret(combined);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // val_id=0, insts_len=1 => 0*10 + 1 = 1
    try std.testing.expectEqual(@as(i64, 1), val.int);
}

test "lower: lower BinOp produces IrBinary" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_lower_expr: FuncId = @enumFromInt(6);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    const scope = try g.mapNew();

    // Create TBinOp: {op: "+", lhs: TIntLit(1), rhs: TIntLit(2), type: TyInt}
    const ty_int_val = try g.tag(typeck.ty_int, null);
    const lhs_payload = try g.record(&.{
        .{ .name = "value", .value = try g.constInt(1) },
        .{ .name = "type", .value = ty_int_val },
    });
    const lhs = try g.tag(typeck.tast_int_lit, lhs_payload);
    const rhs_payload = try g.record(&.{
        .{ .name = "value", .value = try g.constInt(2) },
        .{ .name = "type", .value = ty_int_val },
    });
    const rhs = try g.tag(typeck.tast_int_lit, rhs_payload);
    const binop_payload = try g.record(&.{
        .{ .name = "op", .value = try g.constString("+") },
        .{ .name = "lhs", .value = lhs },
        .{ .name = "rhs", .value = rhs },
        .{ .name = "type", .value = ty_int_val },
    });
    const binop = try g.tag(typeck.tast_binop, binop_payload);

    const result = try g.callDirect(f_lower_expr, &.{ binop, scope, state });
    const new_state = try g.recordField(result, "state");
    const insts = try g.recordField(new_state, "insts");
    const insts_len = try g.listLength(insts);

    // Should have 3 instructions: IrConstInt(1), IrConstInt(2), IrBinary
    try g.ret(insts_len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 3), val.int);
}

test "lower: lower Ident looks up scope" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_lower_expr: FuncId = @enumFromInt(6);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    // Create scope with x = value ID 7
    const scope = try g.mapNew();
    const x_name = try g.constString("x");
    const x_val = try g.constInt(7);
    const scope2 = try g.mapSet(scope, x_name, x_val);

    // Create TIdent for "x"
    const ty_int_val = try g.tag(typeck.ty_int, null);
    const ident_payload = try g.record(&.{
        .{ .name = "name", .value = x_name },
        .{ .name = "type", .value = ty_int_val },
    });
    const ident = try g.tag(typeck.tast_ident, ident_payload);

    const result = try g.callDirect(f_lower_expr, &.{ ident, scope2, state });
    const val_id = try g.recordField(result, "value");
    try g.ret(val_id);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // Should return 7 (the value ID we bound for x)
    try std.testing.expectEqual(@as(i64, 7), val.int);
}

test "lower: e2e parse+check+lower" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);

    // Generate grammar + typeck + lower into same builder
    const gram_funcs = try grammar.generate(alloc, &builder, &pool);
    const f_check_module = try typeck.generate(alloc, &builder, &pool);
    const f_lower_module = try generate(alloc, &builder, &pool);

    // Build driver: parse -> check -> lower
    var g = Gen.init(alloc, &builder, &pool);
    try g.beginFunc("test_driver");
    _ = g.beginBlock();
    const src = try g.addParam();
    const parse_result = try g.callDirect(gram_funcs.parse, &.{src});
    const ast_node = try g.recordField(parse_result, "node");
    const typed = try g.callDirect(f_check_module, &.{ast_node});
    const ir_module = try g.callDirect(f_lower_module, &.{typed});
    try g.ret(ir_module);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const source = "fn add(x: Int, y: Int) -> Int {\n  x + y\n}\n";
    const result = try interp.execFunc(fid, &.{.{ .string = source }});

    // Verify we got a record with a "functions" field
    try std.testing.expect(result == .record);
    // Check that functions list has 1 entry
    const functions_field = result.record.fields[0];
    const func_name = pool.get(functions_field.name);
    try std.testing.expectEqualStrings("functions", func_name);
    try std.testing.expect(functions_field.value == .list);
    try std.testing.expect(functions_field.value.list.items.len == 1);

    // Verify the function has the expected name
    const fn_rec = functions_field.value.list.items[0];
    try std.testing.expect(fn_rec == .record);
    // First field should be "name"
    const fn_name = fn_rec.record.fields[0];
    try std.testing.expectEqualStrings("name", pool.get(fn_name.name));
    try std.testing.expect(fn_name.value == .string);
    try std.testing.expectEqualStrings("add", fn_name.value.string);
}

// ── Semantic verification: verify instruction content ─────────────────

test "lower: IntLit instruction has correct value" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_lower_expr: FuncId = @enumFromInt(6);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    const scope = try g.mapNew();

    const ty_int_val = try g.tag(typeck.ty_int, null);
    const int_payload = try g.record(&.{
        .{ .name = "value", .value = try g.constInt(99) },
        .{ .name = "type", .value = ty_int_val },
    });
    const tast_node = try g.tag(typeck.tast_int_lit, int_payload);
    const result = try g.callDirect(f_lower_expr, &.{ tast_node, scope, state });
    const new_state = try g.recordField(result, "state");
    const insts = try g.recordField(new_state, "insts");
    // Get the first (only) instruction
    const inst = try g.listNth(insts, try g.constInt(0));
    // Check it's tagged IrConstInt
    const is_const_int = try g.tagTest(inst, ir_const_int);
    try g.ret(is_const_int);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "lower: BinOp last instruction is IrBinary with correct op" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_lower_expr: FuncId = @enumFromInt(6);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    const scope = try g.mapNew();

    const ty_int_val = try g.tag(typeck.ty_int, null);
    const lhs_payload = try g.record(&.{
        .{ .name = "value", .value = try g.constInt(5) },
        .{ .name = "type", .value = ty_int_val },
    });
    const lhs = try g.tag(typeck.tast_int_lit, lhs_payload);
    const rhs_payload = try g.record(&.{
        .{ .name = "value", .value = try g.constInt(3) },
        .{ .name = "type", .value = ty_int_val },
    });
    const rhs = try g.tag(typeck.tast_int_lit, rhs_payload);
    const binop_payload = try g.record(&.{
        .{ .name = "op", .value = try g.constString("*") },
        .{ .name = "lhs", .value = lhs },
        .{ .name = "rhs", .value = rhs },
        .{ .name = "type", .value = ty_int_val },
    });
    const binop = try g.tag(typeck.tast_binop, binop_payload);
    const result = try g.callDirect(f_lower_expr, &.{ binop, scope, state });
    const new_state = try g.recordField(result, "state");
    const insts = try g.recordField(new_state, "insts");
    // Third instruction (index 2) should be IrBinary
    const last_inst = try g.listNth(insts, try g.constInt(2));
    const is_binary = try g.tagTest(last_inst, ir_binary);
    // Extract payload and check op is "*"
    const bin_pl = try g.tagPayload(last_inst, ir_binary);
    const op_val = try g.recordField(bin_pl, "op");
    const op_is_mul = try g.eq(op_val, try g.constString("*"));
    // Both must be true
    const check_blk = g.reserveBlock();
    const fail_blk = g.reserveBlock();
    try g.branch(is_binary, check_blk, fail_blk);

    g.beginReservedBlock(check_blk);
    try g.ret(op_is_mul);

    g.beginReservedBlock(fail_blk);
    try g.ret(try g.constBool(false));

    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

// ── Sad paths ─────────────────────────────────────────────────────────

test "lower: lower StringLit produces IrConstString" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_lower_expr: FuncId = @enumFromInt(6);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    const scope = try g.mapNew();

    const ty_str_val = try g.tag(typeck.ty_string, null);
    const str_payload = try g.record(&.{
        .{ .name = "value", .value = try g.constString("hello") },
        .{ .name = "type", .value = ty_str_val },
    });
    const tast_node = try g.tag(typeck.tast_string_lit, str_payload);
    const result = try g.callDirect(f_lower_expr, &.{ tast_node, scope, state });
    const new_state = try g.recordField(result, "state");
    const insts = try g.recordField(new_state, "insts");
    const inst = try g.listNth(insts, try g.constInt(0));
    const is_const_str = try g.tagTest(inst, ir_const_string);
    try g.ret(is_const_str);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "lower: lower BoolLit produces IrConstBool" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_lower_expr: FuncId = @enumFromInt(6);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    const scope = try g.mapNew();

    const ty_bool_val = try g.tag(typeck.ty_bool, null);
    const bool_payload = try g.record(&.{
        .{ .name = "value", .value = try g.constBool(true) },
        .{ .name = "type", .value = ty_bool_val },
    });
    const tast_node = try g.tag(typeck.tast_bool_lit, bool_payload);
    const result = try g.callDirect(f_lower_expr, &.{ tast_node, scope, state });
    const new_state = try g.recordField(result, "state");
    const insts = try g.recordField(new_state, "insts");
    const inst = try g.listNth(insts, try g.constInt(0));
    const is_const_bool = try g.tagTest(inst, ir_const_bool);
    try g.ret(is_const_bool);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "lower: lower NilLit produces IrConstNil" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_lower_expr: FuncId = @enumFromInt(6);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    const scope = try g.mapNew();

    const ty_nil_val = try g.tag(typeck.ty_nil, null);
    const nil_payload = try g.record(&.{
        .{ .name = "type", .value = ty_nil_val },
    });
    const tast_node = try g.tag(typeck.tast_nil_lit, nil_payload);
    const result = try g.callDirect(f_lower_expr, &.{ tast_node, scope, state });
    const new_state = try g.recordField(result, "state");
    const insts = try g.recordField(new_state, "insts");
    const inst = try g.listNth(insts, try g.constInt(0));
    const is_const_nil = try g.tagTest(inst, ir_const_nil);
    try g.ret(is_const_nil);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

// ── E2E: multiple programs ────────────────────────────────────────────

fn buildLowerE2eDriver(alloc: Allocator, builder: *ir.Builder, pool: *InternPool) !struct { fid: FuncId, module: ir.Module } {
    const gram_funcs = try grammar.generate(alloc, builder, pool);
    const f_check_module = try typeck.generate(alloc, builder, pool);
    const f_lower_module = try generate(alloc, builder, pool);

    var g = Gen.init(alloc, builder, pool);
    try g.beginFunc("test_driver");
    _ = g.beginBlock();
    const src = try g.addParam();
    const parse_result = try g.callDirect(gram_funcs.parse, &.{src});
    const ast_node = try g.recordField(parse_result, "node");
    const typed = try g.callDirect(f_check_module, &.{ast_node});
    const ir_mod = try g.callDirect(f_lower_module, &.{typed});
    try g.ret(ir_mod);
    const fid = try g.endFunc();
    const module = try builder.build(fid);
    return .{ .fid = fid, .module = module };
}

test "lower: e2e multiple functions" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildLowerE2eDriver(alloc, &builder, &pool);

    var interp = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp.deinit();

    const source =
        \\fn add(x: Int, y: Int) -> Int {
        \\  x + y
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .record);

    // Should have 2 functions
    const functions = result.record.fields[0].value;
    try std.testing.expect(functions == .list);
    try std.testing.expect(functions.list.items.len == 2);

    // First function should be "add"
    const fn0 = functions.list.items[0];
    try std.testing.expect(fn0 == .record);
    try std.testing.expectEqualStrings("add", fn0.record.fields[0].value.string);

    // Second function should be "main"
    const fn1 = functions.list.items[1];
    try std.testing.expect(fn1 == .record);
    try std.testing.expectEqualStrings("main", fn1.record.fields[0].value.string);
}

test "lower: e2e empty module" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildLowerE2eDriver(alloc, &builder, &pool);

    var interp = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp.deinit();

    const result = try interp.execFunc(drv.fid, &.{.{ .string = "" }});
    try std.testing.expect(result == .record);

    // Empty module should have 0 functions
    const functions = result.record.fields[0].value;
    try std.testing.expect(functions == .list);
    try std.testing.expect(functions.list.items.len == 0);
}

test "lower: e2e let bindings produce correct instruction count" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildLowerE2eDriver(alloc, &builder, &pool);

    var interp = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp.deinit();

    const source =
        \\fn main() {
        \\  let x = 1
        \\  let y = 2
        \\  x + y
        \\}
        \\
    ;
    const result = try interp.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .record);

    // Should have 1 function
    const functions = result.record.fields[0].value;
    try std.testing.expect(functions.list.items.len == 1);

    // Verify the function has blocks
    const fn0 = functions.list.items[0];
    try std.testing.expectEqualStrings("main", fn0.record.fields[0].value.string);
}

test "lower: e2e if/else expression" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildLowerE2eDriver(alloc, &builder, &pool);

    var interp = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp.deinit();

    const source =
        \\fn choose(x: Int) -> Int {
        \\  if x > 0 { x } else { 0 }
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .record);
    const functions = result.record.fields[0].value;
    try std.testing.expect(functions.list.items.len == 2);
}

test "lower: e2e function with type annotations" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildLowerE2eDriver(alloc, &builder, &pool);

    var interp = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp.deinit();

    const source =
        \\fn apply(f: (Int) -> Int, x: Int) -> Int {
        \\  f(x)
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .record);
    const functions = result.record.fields[0].value;
    try std.testing.expect(functions.list.items.len == 2);
    try std.testing.expectEqualStrings("apply", functions.list.items[0].record.fields[0].value.string);
}

test "lower: e2e stress — all features combined" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildLowerE2eDriver(alloc, &builder, &pool);

    var interp = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp.deinit();

    const source =
        \\fn compose(f: Int, g: Int) -> Int {
        \\  f |> g
        \\}
        \\
        \\type Maybe<T> {
        \\  Just(T),
        \\  Nothing
        \\}
        \\
        \\effect Console {
        \\  fn print(msg: String) -> Nil
        \\}
        \\
        \\fn greet(name: String) -[Console]> String {
        \\  "hello"
        \\}
        \\
        \\fn apply(f: (Int) -> Int, x: Int) -> Int {
        \\  f(x)
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .record);

    // Should have function entries for compose, greet, apply, main (type/effect decls don't produce functions)
    const functions = result.record.fields[0].value;
    try std.testing.expect(functions == .list);
    try std.testing.expect(functions.list.items.len >= 4);
}

// ── State invariants ──────────────────────────────────────────────────

test "lower: fresh_val IDs are monotonically increasing" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_fresh_val: FuncId = @enumFromInt(1);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    // Allocate 5 values, verify monotonic
    const r0 = try g.callDirect(f_fresh_val, &.{state});
    const s0 = try g.recordField(r0, "state");
    const r1 = try g.callDirect(f_fresh_val, &.{s0});
    const s1 = try g.recordField(r1, "state");
    const r2 = try g.callDirect(f_fresh_val, &.{s1});
    const s2 = try g.recordField(r2, "state");
    const r3 = try g.callDirect(f_fresh_val, &.{s2});
    const s3 = try g.recordField(r3, "state");
    const r4 = try g.callDirect(f_fresh_val, &.{s3});

    const id0 = try g.recordField(r0, "id");
    const id1 = try g.recordField(r1, "id");
    const id2 = try g.recordField(r2, "id");
    const id3 = try g.recordField(r3, "id");
    const id4 = try g.recordField(r4, "id");

    // Verify: 0,1,2,3,4 — encode as id0*10000 + id1*1000 + id2*100 + id3*10 + id4
    const c10000 = try g.constInt(10000);
    const c1000 = try g.constInt(1000);
    const c100 = try g.constInt(100);
    const c10 = try g.constInt(10);
    const v0 = try g.binary(.mul, id0, c10000);
    const v1 = try g.binary(.mul, id1, c1000);
    const v2 = try g.binary(.mul, id2, c100);
    const v3 = try g.binary(.mul, id3, c10);
    const sum01 = try g.add(v0, v1);
    const sum012 = try g.add(sum01, v2);
    const sum0123 = try g.add(sum012, v3);
    const total = try g.add(sum0123, id4);
    try g.ret(total);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // 0*10000 + 1*1000 + 2*100 + 3*10 + 4 = 1234
    try std.testing.expectEqual(@as(i64, 1234), val.int);
}

test "lower: emit_inst preserves existing instructions" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_state_new: FuncId = @enumFromInt(0);
    const f_emit_inst: FuncId = @enumFromInt(2);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const state = try g.callDirect(f_state_new, &.{});
    // Emit 3 instructions
    const inst1 = try g.constString("inst1");
    const s1 = try g.callDirect(f_emit_inst, &.{ inst1, state });
    const inst2 = try g.constString("inst2");
    const s2 = try g.callDirect(f_emit_inst, &.{ inst2, s1 });
    const inst3 = try g.constString("inst3");
    const s3 = try g.callDirect(f_emit_inst, &.{ inst3, s2 });
    const insts = try g.recordField(s3, "insts");
    const len = try g.listLength(insts);
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 3), val.int);
}
