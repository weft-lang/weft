const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("../ir.zig");
const intern_mod = @import("../intern.zig");
const InternPool = intern_mod.InternPool;
const ValueId = ir.ValueId;
const BlockId = ir.BlockId;
const FuncId = ir.FuncId;
const Gen = @import("gen.zig").Gen;

// ── IR repr tag constants (matching lower.zig conventions) ──────────────
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
pub const ir_handle_setup = "IrHandleSetup";
pub const ir_handle_pop = "IrHandlePop";
pub const ir_perform = "IrPerform";
pub const ir_resume = "IrResume";
pub const ir_arg_receive = "IrArgReceive";
pub const ir_string_eq = "IrStringEq";
pub const ir_string_ne = "IrStringNe";
pub const ir_record_update = "IrRecordUpdate";

pub const ir_ret = "IrRet";
pub const ir_jump = "IrJump";
pub const ir_branch = "IrBranch";

// ── aarch64 condition codes ─────────────────────────────────────────────
// EQ=0, NE=1, LT=11, GE=10, LE=13, GT=12

/// Generate the complete native emitter as IR functions.
/// Returns the entry function ID (ec_emit_module).
pub fn generate(alloc: Allocator, builder: *ir.Builder, pool: *InternPool) !FuncId {
    var g = Gen.init(alloc, builder, pool);

    // Reserve all function IDs upfront for mutual recursion
    const f_encode_add_reg = try g.reserveFunc("ec_encode_add_reg");
    const f_encode_sub_reg = try g.reserveFunc("ec_encode_sub_reg");
    const f_encode_mul = try g.reserveFunc("ec_encode_mul");
    const f_encode_sdiv = try g.reserveFunc("ec_encode_sdiv");
    const f_encode_add_imm = try g.reserveFunc("ec_encode_add_imm");
    const f_encode_sub_imm = try g.reserveFunc("ec_encode_sub_imm");
    const f_encode_cmp_reg = try g.reserveFunc("ec_encode_cmp_reg");
    const f_encode_cset = try g.reserveFunc("ec_encode_cset");
    const f_encode_movz = try g.reserveFunc("ec_encode_movz");
    const f_encode_movk = try g.reserveFunc("ec_encode_movk");
    const f_encode_b = try g.reserveFunc("ec_encode_b");
    const f_encode_bl = try g.reserveFunc("ec_encode_bl");
    const f_encode_ret_inst = try g.reserveFunc("ec_encode_ret_inst");
    const f_encode_svc = try g.reserveFunc("ec_encode_svc");
    const f_encode_stp_pre = try g.reserveFunc("ec_encode_stp_pre");
    const f_encode_ldp_post = try g.reserveFunc("ec_encode_ldp_post");
    const f_encode_b_cond = try g.reserveFunc("ec_encode_b_cond");
    const f_encode_ldr = try g.reserveFunc("ec_encode_ldr");
    const f_encode_str = try g.reserveFunc("ec_encode_str");
    const f_encode_and_reg = try g.reserveFunc("ec_encode_and_reg");
    const f_encode_orr_reg = try g.reserveFunc("ec_encode_orr_reg");
    const f_encode_blr = try g.reserveFunc("ec_encode_blr");
    const f_encode_br = try g.reserveFunc("ec_encode_br");
    const f_encode_adr = try g.reserveFunc("ec_encode_adr");
    const f_encode_msub = try g.reserveFunc("ec_encode_msub");

    const f_mov_imm64 = try g.reserveFunc("ec_mov_imm64");
    const f_emit_heap_init = try g.reserveFunc("ec_emit_heap_init");
    const f_emit_bump_alloc = try g.reserveFunc("ec_emit_bump_alloc");
    const f_emit_exit = try g.reserveFunc("ec_emit_exit");
    const f_emit_prologue = try g.reserveFunc("ec_emit_prologue");
    const f_emit_epilogue = try g.reserveFunc("ec_emit_epilogue");
    const f_alloc_reg = try g.reserveFunc("ec_alloc_reg");
    const f_get_reg = try g.reserveFunc("ec_get_reg");
    const f_load_spill = try g.reserveFunc("ec_load_spill");
    const f_store_spill = try g.reserveFunc("ec_store_spill");
    const f_emit_inst = try g.reserveFunc("ec_emit_inst");
    const f_emit_term = try g.reserveFunc("ec_emit_term");
    const f_emit_block = try g.reserveFunc("ec_emit_block");
    const f_emit_func = try g.reserveFunc("ec_emit_func");
    const f_emit_module = try g.reserveFunc("ec_emit_module");
    const f_emit_macho = try g.reserveFunc("ec_emit_macho");
    const f_append_inst = try g.reserveFunc("ec_append_inst");
    const f_pad_to_page = try g.reserveFunc("ec_pad_to_page");
    const f_append_segment_cmd = try g.reserveFunc("ec_append_segment_cmd");
    const f_append_section = try g.reserveFunc("ec_append_section");
    const f_append_segname = try g.reserveFunc("ec_append_segname");

    // ── ec_encode_add_reg(rd, rn, rm) -> Int ─────────────────────────
    // ADD Xd, Xn, Xm: 0x8B000000 | (Rm << 16) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_add_reg");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const rm = try g.addParam();
        const base = try g.constInt(0x8B000000);
        const c16 = try g.constInt(16);
        const c5 = try g.constInt(5);
        const rm_shifted = try g.binary(.shl, rm, c16);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_add_reg);

    // ── ec_encode_sub_reg(rd, rn, rm) -> Int ─────────────────────────
    // SUB Xd, Xn, Xm: 0xCB000000 | (Rm << 16) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_sub_reg");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const rm = try g.addParam();
        const base = try g.constInt(0xCB000000);
        const c16 = try g.constInt(16);
        const c5 = try g.constInt(5);
        const rm_shifted = try g.binary(.shl, rm, c16);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_sub_reg);

    // ── ec_encode_mul(rd, rn, rm) -> Int ─────────────────────────────
    // MUL Xd, Xn, Xm: 0x9B007C00 | (Rm << 16) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_mul");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const rm = try g.addParam();
        const base = try g.constInt(0x9B007C00);
        const c16 = try g.constInt(16);
        const c5 = try g.constInt(5);
        const rm_shifted = try g.binary(.shl, rm, c16);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_mul);

    // ── ec_encode_sdiv(rd, rn, rm) -> Int ────────────────────────────
    // SDIV Xd, Xn, Xm: 0x9AC00C00 | (Rm << 16) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_sdiv");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const rm = try g.addParam();
        const base = try g.constInt(0x9AC00C00);
        const c16 = try g.constInt(16);
        const c5 = try g.constInt(5);
        const rm_shifted = try g.binary(.shl, rm, c16);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_sdiv);

    // ── ec_encode_add_imm(rd, rn, imm12) -> Int ─────────────────────
    // ADD Xd, Xn, #imm12: 0x91000000 | (imm12 << 10) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_add_imm");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const imm12 = try g.addParam();
        const base = try g.constInt(0x91000000);
        const c10 = try g.constInt(10);
        const c5 = try g.constInt(5);
        const imm_shifted = try g.binary(.shl, imm12, c10);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, imm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_add_imm);

    // ── ec_encode_sub_imm(rd, rn, imm12) -> Int ─────────────────────
    // SUB Xd, Xn, #imm12: 0xD1000000 | (imm12 << 10) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_sub_imm");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const imm12 = try g.addParam();
        const base = try g.constInt(0xD1000000);
        const c10 = try g.constInt(10);
        const c5 = try g.constInt(5);
        const imm_shifted = try g.binary(.shl, imm12, c10);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, imm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_sub_imm);

    // ── ec_encode_cmp_reg(rn, rm) -> Int ─────────────────────────────
    // CMP Xn, Xm (= SUBS XZR, Xn, Xm): 0xEB00001F | (Rm << 16) | (Rn << 5)
    try g.beginReservedFunc("ec_encode_cmp_reg");
    {
        _ = g.beginBlock();
        const rn = try g.addParam();
        const rm = try g.addParam();
        const base = try g.constInt(0xEB00001F);
        const c16 = try g.constInt(16);
        const c5 = try g.constInt(5);
        const rm_shifted = try g.binary(.shl, rm, c16);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        try g.ret(r2);
    }
    try g.endReservedFunc(f_encode_cmp_reg);

    // ── ec_encode_cset(rd, cond) -> Int ──────────────────────────────
    // CSET Xd, cond = CSINC Xd, XZR, XZR, cond^1
    // 0x9A9F07E0 | ((cond^1) << 12) | Rd
    try g.beginReservedFunc("ec_encode_cset");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const cond = try g.addParam();
        const base = try g.constInt(0x9A9F07E0);
        const c1 = try g.constInt(1);
        const c12 = try g.constInt(12);
        const cond_inv = try g.binary(.bit_xor, cond, c1);
        const cond_shifted = try g.binary(.shl, cond_inv, c12);
        const r1 = try g.binary(.bit_or, base, cond_shifted);
        const r2 = try g.binary(.bit_or, r1, rd);
        try g.ret(r2);
    }
    try g.endReservedFunc(f_encode_cset);

    // ── ec_encode_movz(rd, imm16, shift) -> Int ──────────────────────
    // MOVZ Xd, #imm16, LSL #shift: 0xD2800000 | ((shift/16) << 21) | (imm16 << 5) | Rd
    try g.beginReservedFunc("ec_encode_movz");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const imm16 = try g.addParam();
        const shift = try g.addParam();
        const base = try g.constInt(0xD2800000);
        const c16 = try g.constInt(16);
        const c21 = try g.constInt(21);
        const c5 = try g.constInt(5);
        const hw = try g.binary(.div, shift, c16);
        const hw_shifted = try g.binary(.shl, hw, c21);
        const imm_shifted = try g.binary(.shl, imm16, c5);
        const r1 = try g.binary(.bit_or, base, hw_shifted);
        const r2 = try g.binary(.bit_or, r1, imm_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_movz);

    // ── ec_encode_movk(rd, imm16, shift) -> Int ──────────────────────
    // MOVK Xd, #imm16, LSL #shift: 0xF2800000 | ((shift/16) << 21) | (imm16 << 5) | Rd
    try g.beginReservedFunc("ec_encode_movk");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const imm16 = try g.addParam();
        const shift = try g.addParam();
        const base = try g.constInt(0xF2800000);
        const c16 = try g.constInt(16);
        const c21 = try g.constInt(21);
        const c5 = try g.constInt(5);
        const hw = try g.binary(.div, shift, c16);
        const hw_shifted = try g.binary(.shl, hw, c21);
        const imm_shifted = try g.binary(.shl, imm16, c5);
        const r1 = try g.binary(.bit_or, base, hw_shifted);
        const r2 = try g.binary(.bit_or, r1, imm_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_movk);

    // ── ec_encode_b(offset) -> Int ───────────────────────────────────
    // B offset: 0x14000000 | ((offset/4) & 0x3FFFFFF)
    try g.beginReservedFunc("ec_encode_b");
    {
        _ = g.beginBlock();
        const offset = try g.addParam();
        const base = try g.constInt(0x14000000);
        const c4 = try g.constInt(4);
        const c_mask = try g.constInt(0x3FFFFFF);
        const off_div = try g.binary(.div, offset, c4);
        const off_masked = try g.binary(.bit_and, off_div, c_mask);
        const r = try g.binary(.bit_or, base, off_masked);
        try g.ret(r);
    }
    try g.endReservedFunc(f_encode_b);

    // ── ec_encode_bl(offset) -> Int ──────────────────────────────────
    // BL offset: 0x94000000 | ((offset/4) & 0x3FFFFFF)
    try g.beginReservedFunc("ec_encode_bl");
    {
        _ = g.beginBlock();
        const offset = try g.addParam();
        const base = try g.constInt(0x94000000);
        const c4 = try g.constInt(4);
        const c_mask = try g.constInt(0x3FFFFFF);
        const off_div = try g.binary(.div, offset, c4);
        const off_masked = try g.binary(.bit_and, off_div, c_mask);
        const r = try g.binary(.bit_or, base, off_masked);
        try g.ret(r);
    }
    try g.endReservedFunc(f_encode_bl);

    // ── ec_encode_ret_inst() -> Int ──────────────────────────────────
    // RET: 0xD65F03C0
    try g.beginReservedFunc("ec_encode_ret_inst");
    {
        _ = g.beginBlock();
        const v = try g.constInt(0xD65F03C0);
        try g.ret(v);
    }
    try g.endReservedFunc(f_encode_ret_inst);

    // ── ec_encode_svc(imm16) -> Int ──────────────────────────────────
    // SVC #imm16: 0xD4000001 | (imm16 << 5)
    try g.beginReservedFunc("ec_encode_svc");
    {
        _ = g.beginBlock();
        const imm16 = try g.addParam();
        const base = try g.constInt(0xD4000001);
        const c5 = try g.constInt(5);
        const imm_shifted = try g.binary(.shl, imm16, c5);
        const r = try g.binary(.bit_or, base, imm_shifted);
        try g.ret(r);
    }
    try g.endReservedFunc(f_encode_svc);

    // ── ec_encode_stp_pre(rt1, rt2, rn, offset) -> Int ───────────────
    // STP Xt1, Xt2, [Xn, #off]! (pre-index):
    // 0xA9800000 | (((off/8) & 0x7F) << 15) | (Rt2 << 10) | (Rn << 5) | Rt1
    try g.beginReservedFunc("ec_encode_stp_pre");
    {
        _ = g.beginBlock();
        const rt1 = try g.addParam();
        const rt2 = try g.addParam();
        const rn = try g.addParam();
        const offset = try g.addParam();
        const base = try g.constInt(0xA9800000);
        const c8 = try g.constInt(8);
        const c_7f = try g.constInt(0x7F);
        const c15 = try g.constInt(15);
        const c10 = try g.constInt(10);
        const c5 = try g.constInt(5);
        const off_div = try g.binary(.div, offset, c8);
        const off_masked = try g.binary(.bit_and, off_div, c_7f);
        const off_shifted = try g.binary(.shl, off_masked, c15);
        const rt2_shifted = try g.binary(.shl, rt2, c10);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, off_shifted);
        const r2 = try g.binary(.bit_or, r1, rt2_shifted);
        const r3 = try g.binary(.bit_or, r2, rn_shifted);
        const r4 = try g.binary(.bit_or, r3, rt1);
        try g.ret(r4);
    }
    try g.endReservedFunc(f_encode_stp_pre);

    // ── ec_encode_ldp_post(rt1, rt2, rn, offset) -> Int ──────────────
    // LDP Xt1, Xt2, [Xn], #off (post-index):
    // 0xA8C00000 | (((off/8) & 0x7F) << 15) | (Rt2 << 10) | (Rn << 5) | Rt1
    try g.beginReservedFunc("ec_encode_ldp_post");
    {
        _ = g.beginBlock();
        const rt1 = try g.addParam();
        const rt2 = try g.addParam();
        const rn = try g.addParam();
        const offset = try g.addParam();
        const base = try g.constInt(0xA8C00000);
        const c8 = try g.constInt(8);
        const c_7f = try g.constInt(0x7F);
        const c15 = try g.constInt(15);
        const c10 = try g.constInt(10);
        const c5 = try g.constInt(5);
        const off_div = try g.binary(.div, offset, c8);
        const off_masked = try g.binary(.bit_and, off_div, c_7f);
        const off_shifted = try g.binary(.shl, off_masked, c15);
        const rt2_shifted = try g.binary(.shl, rt2, c10);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, off_shifted);
        const r2 = try g.binary(.bit_or, r1, rt2_shifted);
        const r3 = try g.binary(.bit_or, r2, rn_shifted);
        const r4 = try g.binary(.bit_or, r3, rt1);
        try g.ret(r4);
    }
    try g.endReservedFunc(f_encode_ldp_post);

    // ── ec_encode_b_cond(offset, cond) -> Int ────────────────────────
    // B.cond off: 0x54000000 | (((off/4) & 0x7FFFF) << 5) | cond
    try g.beginReservedFunc("ec_encode_b_cond");
    {
        _ = g.beginBlock();
        const offset = try g.addParam();
        const cond = try g.addParam();
        const base = try g.constInt(0x54000000);
        const c4 = try g.constInt(4);
        const c_mask = try g.constInt(0x7FFFF);
        const c5 = try g.constInt(5);
        const off_div = try g.binary(.div, offset, c4);
        const off_masked = try g.binary(.bit_and, off_div, c_mask);
        const off_shifted = try g.binary(.shl, off_masked, c5);
        const r1 = try g.binary(.bit_or, base, off_shifted);
        const r2 = try g.binary(.bit_or, r1, cond);
        try g.ret(r2);
    }
    try g.endReservedFunc(f_encode_b_cond);

    // ── ec_encode_ldr(rt, rn, offset) -> Int ─────────────────────────
    // LDR Xt, [Xn, #off]: 0xF9400000 | ((off/8) << 10) | (Rn << 5) | Rt
    try g.beginReservedFunc("ec_encode_ldr");
    {
        _ = g.beginBlock();
        const rt = try g.addParam();
        const rn = try g.addParam();
        const offset = try g.addParam();
        const base = try g.constInt(0xF9400000);
        const c8 = try g.constInt(8);
        const c10 = try g.constInt(10);
        const c5 = try g.constInt(5);
        const off_div = try g.binary(.div, offset, c8);
        const off_shifted = try g.binary(.shl, off_div, c10);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, off_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rt);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_ldr);

    // ── ec_encode_str(rt, rn, offset) -> Int ─────────────────────────
    // STR Xt, [Xn, #off]: 0xF9000000 | ((off/8) << 10) | (Rn << 5) | Rt
    try g.beginReservedFunc("ec_encode_str");
    {
        _ = g.beginBlock();
        const rt = try g.addParam();
        const rn = try g.addParam();
        const offset = try g.addParam();
        const base = try g.constInt(0xF9000000);
        const c8 = try g.constInt(8);
        const c10 = try g.constInt(10);
        const c5 = try g.constInt(5);
        const off_div = try g.binary(.div, offset, c8);
        const off_shifted = try g.binary(.shl, off_div, c10);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, off_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rt);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_str);

    // ── ec_encode_and_reg(rd, rn, rm) -> Int ─────────────────────────
    // AND Xd, Xn, Xm: 0x8A000000 | (Rm << 16) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_and_reg");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const rm = try g.addParam();
        const base = try g.constInt(0x8A000000);
        const c16 = try g.constInt(16);
        const c5 = try g.constInt(5);
        const rm_shifted = try g.binary(.shl, rm, c16);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_and_reg);

    // ── ec_encode_orr_reg(rd, rn, rm) -> Int ─────────────────────────
    // ORR Xd, Xn, Xm: 0xAA000000 | (Rm << 16) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_orr_reg");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const rm = try g.addParam();
        const base = try g.constInt(0xAA000000);
        const c16 = try g.constInt(16);
        const c5 = try g.constInt(5);
        const rm_shifted = try g.binary(.shl, rm, c16);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rm_shifted);
        const r2 = try g.binary(.bit_or, r1, rn_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_orr_reg);

    // ── ec_encode_blr(rn) -> Int ─────────────────────────────────────
    // BLR Xn: 0xD63F0000 | (Rn << 5)
    try g.beginReservedFunc("ec_encode_blr");
    {
        _ = g.beginBlock();
        const rn = try g.addParam();
        const base = try g.constInt(0xD63F0000);
        const c5 = try g.constInt(5);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rn_shifted);
        try g.ret(r1);
    }
    try g.endReservedFunc(f_encode_blr);

    // ── ec_encode_br(rn) -> Int ──────────────────────────────────────
    // BR Xn: 0xD61F0000 | (Rn << 5)
    try g.beginReservedFunc("ec_encode_br");
    {
        _ = g.beginBlock();
        const rn = try g.addParam();
        const base = try g.constInt(0xD61F0000);
        const c5 = try g.constInt(5);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rn_shifted);
        try g.ret(r1);
    }
    try g.endReservedFunc(f_encode_br);

    // ── ec_encode_adr(rd, imm21) -> Int ──────────────────────────────
    // ADR Xd, #imm: PC-relative address within ±1MB
    // Encoding: 0x10000000 | (immlo << 29) | (immhi << 5) | Rd
    // immlo = imm & 3, immhi = (imm >> 2) & 0x7FFFF
    try g.beginReservedFunc("ec_encode_adr");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const imm = try g.addParam();
        const base = try g.constInt(0x10000000);
        const c3 = try g.constInt(3);
        const immlo = try g.binary(.bit_and, imm, c3);
        const c29 = try g.constInt(29);
        const immlo_shifted = try g.binary(.shl, immlo, c29);
        const c2 = try g.constInt(2);
        const imm_shr2 = try g.binary(.shr, imm, c2);
        const c0x7ffff = try g.constInt(0x7FFFF);
        const immhi = try g.binary(.bit_and, imm_shr2, c0x7ffff);
        const c5 = try g.constInt(5);
        const immhi_shifted = try g.binary(.shl, immhi, c5);
        const r1 = try g.binary(.bit_or, base, immlo_shifted);
        const r2 = try g.binary(.bit_or, r1, immhi_shifted);
        const r3 = try g.binary(.bit_or, r2, rd);
        try g.ret(r3);
    }
    try g.endReservedFunc(f_encode_adr);

    // ── ec_encode_msub(rd, rn, rm, ra) -> Int ────────────────────────
    // MSUB Xd, Xn, Xm, Xa: 0x9B008000 | (Rm << 16) | (Ra << 10) | (Rn << 5) | Rd
    try g.beginReservedFunc("ec_encode_msub");
    {
        _ = g.beginBlock();
        const rd = try g.addParam();
        const rn = try g.addParam();
        const rm = try g.addParam();
        const ra = try g.addParam();
        const base = try g.constInt(0x9B008000);
        const c16 = try g.constInt(16);
        const c10 = try g.constInt(10);
        const c5 = try g.constInt(5);
        const rm_shifted = try g.binary(.shl, rm, c16);
        const ra_shifted = try g.binary(.shl, ra, c10);
        const rn_shifted = try g.binary(.shl, rn, c5);
        const r1 = try g.binary(.bit_or, base, rm_shifted);
        const r2 = try g.binary(.bit_or, r1, ra_shifted);
        const r3 = try g.binary(.bit_or, r2, rn_shifted);
        const r4 = try g.binary(.bit_or, r3, rd);
        try g.ret(r4);
    }
    try g.endReservedFunc(f_encode_msub);

    // ── ec_append_inst(bytes, inst_word) -> Bytes ────────────────────
    // Append a 32-bit instruction word to bytes buffer as little-endian.
    try g.beginReservedFunc("ec_append_inst");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();
        const inst = try g.addParam();
        const result = try g.callBuiltin("bytes_append_u32_le", &.{ bytes, inst });
        try g.ret(result);
    }
    try g.endReservedFunc(f_append_inst);

    // ── ec_mov_imm64(bytes, rd, value) -> Bytes ──────────────────────
    // Emit MOVZ + up to 3 MOVKs to load a 64-bit immediate into Xd.
    try g.beginReservedFunc("ec_mov_imm64");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();
        const rd = try g.addParam();
        const value = try g.addParam();

        const c_ffff = try g.constInt(0xFFFF);
        const c16 = try g.constInt(16);
        const c32 = try g.constInt(32);
        const c48 = try g.constInt(48);
        const c0 = try g.constInt(0);

        // Extract 16-bit chunks
        const chunk0 = try g.binary(.bit_and, value, c_ffff);
        const shifted16 = try g.binary(.shr, value, c16);
        const chunk1 = try g.binary(.bit_and, shifted16, c_ffff);
        const shifted32 = try g.binary(.shr, value, c32);
        const chunk2 = try g.binary(.bit_and, shifted32, c_ffff);
        const shifted48 = try g.binary(.shr, value, c48);
        const chunk3 = try g.binary(.bit_and, shifted48, c_ffff);

        // MOVZ Xd, #chunk0, LSL #0
        const movz_inst = try g.callDirect(f_encode_movz, &.{ rd, chunk0, c0 });
        const b1 = try g.callDirect(f_append_inst, &.{ bytes, movz_inst });

        // Check if we need MOVK for chunk1
        const need1 = try g.ne(chunk1, c0);
        const blk_k1 = g.reserveBlock();
        const blk_skip1 = g.reserveBlock();
        const blk_after1 = g.reserveBlock();
        try g.branch(need1, blk_k1, blk_skip1);

        g.beginReservedBlock(blk_k1);
        const movk1 = try g.callDirect(f_encode_movk, &.{ rd, chunk1, c16 });
        const b1_k = try g.callDirect(f_append_inst, &.{ b1, movk1 });
        try g.jump(blk_after1, &.{b1_k});

        g.beginReservedBlock(blk_skip1);
        try g.jump(blk_after1, &.{b1});

        g.beginReservedBlock(blk_after1);
        const b2 = try g.addBlockParam();

        // Check chunk2
        const need2 = try g.ne(chunk2, c0);
        const blk_k2 = g.reserveBlock();
        const blk_skip2 = g.reserveBlock();
        const blk_after2 = g.reserveBlock();
        try g.branch(need2, blk_k2, blk_skip2);

        g.beginReservedBlock(blk_k2);
        const movk2 = try g.callDirect(f_encode_movk, &.{ rd, chunk2, c32 });
        const b2_k = try g.callDirect(f_append_inst, &.{ b2, movk2 });
        try g.jump(blk_after2, &.{b2_k});

        g.beginReservedBlock(blk_skip2);
        try g.jump(blk_after2, &.{b2});

        g.beginReservedBlock(blk_after2);
        const b3 = try g.addBlockParam();

        // Check chunk3
        const need3 = try g.ne(chunk3, c0);
        const blk_k3 = g.reserveBlock();
        const blk_skip3 = g.reserveBlock();
        const blk_done = g.reserveBlock();
        try g.branch(need3, blk_k3, blk_skip3);

        g.beginReservedBlock(blk_k3);
        const movk3 = try g.callDirect(f_encode_movk, &.{ rd, chunk3, c48 });
        const b3_k = try g.callDirect(f_append_inst, &.{ b3, movk3 });
        try g.jump(blk_done, &.{b3_k});

        g.beginReservedBlock(blk_skip3);
        try g.jump(blk_done, &.{b3});

        g.beginReservedBlock(blk_done);
        const b_final = try g.addBlockParam();
        try g.ret(b_final);
    }
    try g.endReservedFunc(f_mov_imm64);

    // ── ec_emit_heap_init(bytes) -> Bytes ────────────────────────────
    // Emit mmap syscall to allocate 64MB heap, store base in x28.
    // mmap(0, 0x4000000, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0)
    // x16 = 0x20000C5 (BSD class | 197)
    // x0=0 (addr), x1=64MB, x2=3 (RW), x3=0x1002 (PRIVATE|ANON), x4=-1 (fd), x5=0
    // SVC #0x80 → result in x0, move to x28
    try g.beginReservedFunc("ec_emit_heap_init");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();

        // MOVZ x16, #0x00C5; MOVK x16, #0x0200, LSL #16
        const c16 = try g.constInt(16);
        const c0 = try g.constInt(0);
        const mmap_lo = try g.constInt(0x00C5);
        const movz_x16 = try g.callDirect(f_encode_movz, &.{ c16, mmap_lo, c0 });
        const b1 = try g.callDirect(f_append_inst, &.{ bytes, movz_x16 });
        const mmap_hi = try g.constInt(0x0200);
        const c16_shift = try g.constInt(16);
        const movk_x16 = try g.callDirect(f_encode_movk, &.{ c16, mmap_hi, c16_shift });
        const b2 = try g.callDirect(f_append_inst, &.{ b1, movk_x16 });

        // MOVZ x0, #0 (addr = NULL)
        const movz_x0 = try g.callDirect(f_encode_movz, &.{ c0, c0, c0 });
        const b3 = try g.callDirect(f_append_inst, &.{ b2, movz_x0 });

        // MOV x1, #0x4000000 (64MB) = MOVZ x1, #0x0400, LSL #16
        const c1 = try g.constInt(1);
        const heap_hi = try g.constInt(0x0400);
        const movz_x1 = try g.callDirect(f_encode_movz, &.{ c1, c0, c0 });
        const b4 = try g.callDirect(f_append_inst, &.{ b3, movz_x1 });
        const movk_x1 = try g.callDirect(f_encode_movk, &.{ c1, heap_hi, c16_shift });
        const b5 = try g.callDirect(f_append_inst, &.{ b4, movk_x1 });

        // MOVZ x2, #3 (PROT_READ | PROT_WRITE)
        const c2 = try g.constInt(2);
        const c3 = try g.constInt(3);
        const movz_x2 = try g.callDirect(f_encode_movz, &.{ c2, c3, c0 });
        const b6 = try g.callDirect(f_append_inst, &.{ b5, movz_x2 });

        // MOVZ x3, #0x1002 (MAP_PRIVATE | MAP_ANON)
        const map_flags = try g.constInt(0x1002);
        const movz_x3 = try g.callDirect(f_encode_movz, &.{ c3, map_flags, c0 });
        const b7 = try g.callDirect(f_append_inst, &.{ b6, movz_x3 });

        // MOV x4, #-1 (fd = -1) → MOVN x4, #0
        // MOVN Xd, #imm = 0x92800000 | (imm16 << 5) | Rd → sets Xd = ~imm16
        const c4 = try g.constInt(4);
        const movn_base = try g.constInt(0x92800000);
        const movn_x4 = try g.binary(.bit_or, movn_base, c4);
        const b8 = try g.callDirect(f_append_inst, &.{ b7, movn_x4 });

        // MOVZ x5, #0 (offset = 0)
        const c5 = try g.constInt(5);
        const movz_x5 = try g.callDirect(f_encode_movz, &.{ c5, c0, c0 });
        const b9 = try g.callDirect(f_append_inst, &.{ b8, movz_x5 });

        // SVC #0x80
        const svc = try g.constInt(0xD4001001); // SVC #0x80
        const b10 = try g.callDirect(f_append_inst, &.{ b9, svc });

        // MOV x28, x0 (move mmap result to bump pointer register)
        // ADD x28, x0, #0
        const c28 = try g.constInt(28);
        const mov_x28 = try g.callDirect(f_encode_add_imm, &.{ c28, c0, c0 });
        const b11 = try g.callDirect(f_append_inst, &.{ b10, mov_x28 });

        try g.ret(b11);
    }
    try g.endReservedFunc(f_emit_heap_init);

    // ── ec_emit_bump_alloc(bytes, dst_reg, size) -> Bytes ────────────
    // Emit: MOV dst, x28; ADD x28, x28, #size
    // Returns current bump pointer in dst_reg, advances by size bytes.
    try g.beginReservedFunc("ec_emit_bump_alloc");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();
        const dst_reg = try g.addParam();
        const size = try g.addParam();

        // MOV dst_reg, x28 → ADD dst_reg, x28, #0
        const c28 = try g.constInt(28);
        const c0 = try g.constInt(0);
        const mov_dst = try g.callDirect(f_encode_add_imm, &.{ dst_reg, c28, c0 });
        const b1 = try g.callDirect(f_append_inst, &.{ bytes, mov_dst });

        // ADD x28, x28, #size
        const add_bump = try g.callDirect(f_encode_add_imm, &.{ c28, c28, size });
        const b2 = try g.callDirect(f_append_inst, &.{ b1, add_bump });

        try g.ret(b2);
    }
    try g.endReservedFunc(f_emit_bump_alloc);

    // ── ec_emit_exit(bytes, exit_code_reg) -> Bytes ──────────────────
    // Move exit code to x0 (if needed) and RET to dyld (which calls exit)
    try g.beginReservedFunc("ec_emit_exit");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();
        const exit_reg = try g.addParam();

        // MOV x0, exit_reg: ADD x0, exit_reg, #0 (if exit_reg != x0)
        const c0 = try g.constInt(0);
        const is_x0 = try g.eq(exit_reg, c0);
        const blk_move = g.reserveBlock();
        const blk_skip_move = g.reserveBlock();
        const blk_after_move = g.reserveBlock();
        try g.branch(is_x0, blk_skip_move, blk_move);

        g.beginReservedBlock(blk_move);
        const add_inst = try g.callDirect(f_encode_add_imm, &.{ c0, exit_reg, c0 });
        const b1 = try g.callDirect(f_append_inst, &.{ bytes, add_inst });
        try g.jump(blk_after_move, &.{b1});

        g.beginReservedBlock(blk_skip_move);
        try g.jump(blk_after_move, &.{bytes});

        g.beginReservedBlock(blk_after_move);
        const b2 = try g.addBlockParam();

        // RET — return to dyld, which calls exit(x0)
        const ret_inst = try g.callDirect(f_encode_ret_inst, &.{});
        const b3 = try g.callDirect(f_append_inst, &.{ b2, ret_inst });
        try g.ret(b3);
    }
    try g.endReservedFunc(f_emit_exit);

    // ── ec_emit_prologue(frame_size) -> Bytes ────────────────────────
    // Save all usable registers: x8-x15 (overflow temps), x19-x26 (callee-saved), x29/x30
    // 9 STP pre-index pairs, then ADD x29, sp, #0
    try g.beginReservedFunc("ec_emit_prologue");
    {
        _ = g.beginBlock();
        const frame_size = try g.addParam();
        _ = frame_size;
        const bytes = try g.callBuiltin("bytes_new", &.{});
        const c31 = try g.constInt(31); // sp
        const neg16 = try g.constInt(-16);
        const c0 = try g.constInt(0);

        // Save overflow temp registers so they survive recursive calls
        // STP x8, x9, [sp, #-16]!
        const c8 = try g.constInt(8);
        const c9 = try g.constInt(9);
        const stp_t1 = try g.callDirect(f_encode_stp_pre, &.{ c8, c9, c31, neg16 });
        var b = try g.callDirect(f_append_inst, &.{ bytes, stp_t1 });

        // STP x10, x11, [sp, #-16]!
        const c10 = try g.constInt(10);
        const c11 = try g.constInt(11);
        const stp_t2 = try g.callDirect(f_encode_stp_pre, &.{ c10, c11, c31, neg16 });
        b = try g.callDirect(f_append_inst, &.{ b, stp_t2 });

        // STP x12, x13, [sp, #-16]!
        const c12 = try g.constInt(12);
        const c13 = try g.constInt(13);
        const stp_t3 = try g.callDirect(f_encode_stp_pre, &.{ c12, c13, c31, neg16 });
        b = try g.callDirect(f_append_inst, &.{ b, stp_t3 });

        // STP x14, x15, [sp, #-16]!
        const c14 = try g.constInt(14);
        const c15 = try g.constInt(15);
        const stp_t4 = try g.callDirect(f_encode_stp_pre, &.{ c14, c15, c31, neg16 });
        b = try g.callDirect(f_append_inst, &.{ b, stp_t4 });

        // Standard callee-saved registers
        // STP x19, x20, [sp, #-16]!
        const c19 = try g.constInt(19);
        const c20 = try g.constInt(20);
        const stp1 = try g.callDirect(f_encode_stp_pre, &.{ c19, c20, c31, neg16 });
        b = try g.callDirect(f_append_inst, &.{ b, stp1 });

        // STP x21, x22, [sp, #-16]!
        const c21 = try g.constInt(21);
        const c22 = try g.constInt(22);
        const stp2 = try g.callDirect(f_encode_stp_pre, &.{ c21, c22, c31, neg16 });
        b = try g.callDirect(f_append_inst, &.{ b, stp2 });

        // STP x23, x24, [sp, #-16]!
        const c23 = try g.constInt(23);
        const c24 = try g.constInt(24);
        const stp3 = try g.callDirect(f_encode_stp_pre, &.{ c23, c24, c31, neg16 });
        b = try g.callDirect(f_append_inst, &.{ b, stp3 });

        // STP x25, x26, [sp, #-16]!
        const c25 = try g.constInt(25);
        const c26 = try g.constInt(26);
        const stp4 = try g.callDirect(f_encode_stp_pre, &.{ c25, c26, c31, neg16 });
        b = try g.callDirect(f_append_inst, &.{ b, stp4 });

        // STP x29, x30, [sp, #-16]!
        const c29 = try g.constInt(29);
        const c30 = try g.constInt(30);
        const stp5 = try g.callDirect(f_encode_stp_pre, &.{ c29, c30, c31, neg16 });
        b = try g.callDirect(f_append_inst, &.{ b, stp5 });

        // ADD x29, sp, #0  (frame pointer)
        const mov_fp = try g.callDirect(f_encode_add_imm, &.{ c29, c31, c0 });
        b = try g.callDirect(f_append_inst, &.{ b, mov_fp });

        // SUB sp, sp, #2048  (256 spill slots × 8 bytes, 16-byte aligned)
        const spill_size = try g.constInt(1024);
        const sub_sp = try g.callDirect(f_encode_sub_imm, &.{ c31, c31, spill_size });
        b = try g.callDirect(f_append_inst, &.{ b, sub_sp });
        try g.ret(b);
    }
    try g.endReservedFunc(f_emit_prologue);

    // ── ec_emit_epilogue(frame_size) -> Bytes ────────────────────────
    // Restore all registers in reverse order, then RET
    try g.beginReservedFunc("ec_emit_epilogue");
    {
        _ = g.beginBlock();
        const frame_size = try g.addParam();
        _ = frame_size;
        const bytes = try g.callBuiltin("bytes_new", &.{});
        const c31 = try g.constInt(31); // sp
        const c16 = try g.constInt(16);

        // ADD sp, sp, #2048  (undo spill area)
        const c0 = try g.constInt(0);
        _ = c0;
        const spill_size = try g.constInt(1024);
        const add_sp = try g.callDirect(f_encode_add_imm, &.{ c31, c31, spill_size });
        var b = try g.callDirect(f_append_inst, &.{ bytes, add_sp });

        // LDP x29, x30, [sp], #16
        const c29 = try g.constInt(29);
        const c30 = try g.constInt(30);
        const ldp1 = try g.callDirect(f_encode_ldp_post, &.{ c29, c30, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp1 });

        // LDP x25, x26, [sp], #16
        const c25 = try g.constInt(25);
        const c26 = try g.constInt(26);
        const ldp2 = try g.callDirect(f_encode_ldp_post, &.{ c25, c26, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp2 });

        // LDP x23, x24, [sp], #16
        const c23 = try g.constInt(23);
        const c24 = try g.constInt(24);
        const ldp3 = try g.callDirect(f_encode_ldp_post, &.{ c23, c24, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp3 });

        // LDP x21, x22, [sp], #16
        const c21 = try g.constInt(21);
        const c22 = try g.constInt(22);
        const ldp4 = try g.callDirect(f_encode_ldp_post, &.{ c21, c22, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp4 });

        // LDP x19, x20, [sp], #16
        const c19 = try g.constInt(19);
        const c20 = try g.constInt(20);
        const ldp5 = try g.callDirect(f_encode_ldp_post, &.{ c19, c20, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp5 });

        // Restore overflow temp registers
        // LDP x14, x15, [sp], #16
        const c14 = try g.constInt(14);
        const c15 = try g.constInt(15);
        const ldp_t4 = try g.callDirect(f_encode_ldp_post, &.{ c14, c15, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp_t4 });

        // LDP x12, x13, [sp], #16
        const c12 = try g.constInt(12);
        const c13 = try g.constInt(13);
        const ldp_t3 = try g.callDirect(f_encode_ldp_post, &.{ c12, c13, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp_t3 });

        // LDP x10, x11, [sp], #16
        const c10 = try g.constInt(10);
        const c11 = try g.constInt(11);
        const ldp_t2 = try g.callDirect(f_encode_ldp_post, &.{ c10, c11, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp_t2 });

        // LDP x8, x9, [sp], #16
        const c8 = try g.constInt(8);
        const c9 = try g.constInt(9);
        const ldp_t1 = try g.callDirect(f_encode_ldp_post, &.{ c8, c9, c31, c16 });
        b = try g.callDirect(f_append_inst, &.{ b, ldp_t1 });

        const ret_inst = try g.callDirect(f_encode_ret_inst, &.{});
        b = try g.callDirect(f_append_inst, &.{ b, ret_inst });
        try g.ret(b);
    }
    try g.endReservedFunc(f_emit_epilogue);

    // ── ec_alloc_reg(ctx, value_id) -> {reg: Int, ctx} ──────────────
    // Allocate a register for a value ID. ctx has field "reg_map" (map) and "next_reg" (int).
    // Registers: x8-x15 (8-15), then x19-x28 (19-28). Total 18.
    try g.beginReservedFunc("ec_alloc_reg");
    {
        _ = g.beginBlock();
        const ctx = try g.addParam();
        const val_id = try g.addParam();

        const reg_map = try g.recordField(ctx, "reg_map");
        const next_reg = try g.recordField(ctx, "next_reg");

        // Check if already allocated
        const id_str = try g.callBuiltin("string_from_int", &.{val_id});
        const has = try g.mapHas(reg_map, id_str);
        const blk_existing = g.reserveBlock();
        const blk_new = g.reserveBlock();
        try g.branch(has, blk_existing, blk_new);

        // Already allocated: return existing
        g.beginReservedBlock(blk_existing);
        const existing_reg = try g.mapGet(reg_map, id_str);
        const result_existing = try g.record(&.{
            .{ .name = "reg", .value = existing_reg },
            .{ .name = "ctx", .value = ctx },
        });
        try g.ret(result_existing);

        // New allocation: callee-saved only, then spill.
        // Skip x8-x15 entirely — they get clobbered by function calls.
        g.beginReservedBlock(blk_new);
        const c8_val = try g.constInt(8);
        const is_spill = try g.ge(next_reg, c8_val);
        const blk_callee = g.reserveBlock();
        const blk_spill = g.reserveBlock();
        try g.branch(is_spill, blk_spill, blk_callee);

        g.beginReservedBlock(blk_callee);
        // counter 0-7 -> x19-x26
        const c19_val = try g.constInt(19);
        const reg_callee = try g.add(next_reg, c19_val);
        const blk_assign = g.reserveBlock();
        try g.jump(blk_assign, &.{reg_callee});

        // Spill to stack: counter 8 -> reg 116, 9 -> 117, etc.
        // load_spill/store_spill use (reg - 116) * 8 for offset
        g.beginReservedBlock(blk_spill);
        const c108 = try g.constInt(108);
        const spill_slot = try g.add(c108, next_reg); // 108+8=116, 108+9=117, etc.
        try g.jump(blk_assign, &.{spill_slot});

        g.beginReservedBlock(blk_assign);
        const actual_reg = try g.addBlockParam();
        const c1 = try g.constInt(1);
        const new_next = try g.add(next_reg, c1);
        const new_map = try g.mapSet(reg_map, id_str, actual_reg);
        const new_ctx = try g.record(&.{
            .{ .name = "reg_map", .value = new_map },
            .{ .name = "next_reg", .value = new_next },
            .{ .name = "func_map", .value = try g.recordField(ctx, "func_map") },
            .{ .name = "block_offsets", .value = try g.recordField(ctx, "block_offsets") },
            .{ .name = "data", .value = try g.recordField(ctx, "data") },
            .{ .name = "data_offsets", .value = try g.recordField(ctx, "data_offsets") },
            .{ .name = "blocks_start", .value = try g.recordField(ctx, "blocks_start") },
            .{ .name = "fields_map", .value = try g.recordField(ctx, "fields_map") },
        });
        const result_new = try g.record(&.{
            .{ .name = "reg", .value = actual_reg },
            .{ .name = "ctx", .value = new_ctx },
        });
        try g.ret(result_new);
    }
    try g.endReservedFunc(f_alloc_reg);

    // ── ec_get_reg(ctx, value_id) -> Int ─────────────────────────────
    // Get register number for a value_id from ctx.reg_map.
    // If not found (block param), returns x0 (block param convention).
    try g.beginReservedFunc("ec_get_reg");
    {
        _ = g.beginBlock();
        const ctx = try g.addParam();
        const val_id = try g.addParam();
        const reg_map = try g.recordField(ctx, "reg_map");
        const id_str = try g.callBuiltin("string_from_int", &.{val_id});
        const has_key = try g.mapHas(reg_map, id_str);
        const blk_found = g.reserveBlock();
        const blk_not_found = g.reserveBlock();
        try g.branch(has_key, blk_found, blk_not_found);

        g.beginReservedBlock(blk_found);
        const reg = try g.mapGet(reg_map, id_str);
        try g.ret(reg);

        // Block param convention: unregistered values are in x0
        g.beginReservedBlock(blk_not_found);
        const c0 = try g.constInt(0);
        try g.ret(c0);
    }
    try g.endReservedFunc(f_get_reg);

    // ── ec_load_spill(bytes, reg, temp) -> {bytes, actual_reg} ────────
    // If reg >= 100, emit LDR temp, [sp, #(reg - 116) * 8] and return temp.
    // Otherwise return reg as-is (no load needed).
    try g.beginReservedFunc("ec_load_spill");
    {
        _ = g.beginBlock();
        const load_bytes = try g.addParam();
        const load_reg = try g.addParam();
        const load_temp = try g.addParam();
        const c100_l = try g.constInt(100);
        const is_spilled = try g.ge(load_reg, c100_l);
        const blk_spilled = g.reserveBlock();
        const blk_physical = g.reserveBlock();
        try g.branch(is_spilled, blk_spilled, blk_physical);

        g.beginReservedBlock(blk_physical);
        try g.ret(try g.record(&.{
            .{ .name = "bytes", .value = load_bytes },
            .{ .name = "reg", .value = load_reg },
        }));

        g.beginReservedBlock(blk_spilled);
        // offset = (reg - 116) * 8
        const c116_l = try g.constInt(116);
        const slot_idx = try g.sub(load_reg, c116_l);
        const c8_l = try g.constInt(8);
        const offset = try g.binary(.mul, slot_idx, c8_l);
        const c31_l = try g.constInt(31); // sp
        const ldr_enc = try g.callDirect(f_encode_ldr, &.{ load_temp, c31_l, offset });
        const new_bytes = try g.callDirect(f_append_inst, &.{ load_bytes, ldr_enc });
        try g.ret(try g.record(&.{
            .{ .name = "bytes", .value = new_bytes },
            .{ .name = "reg", .value = load_temp },
        }));
    }
    try g.endReservedFunc(f_load_spill);

    // ── ec_store_spill(bytes, reg, src_reg) -> bytes ─────────────────
    // If reg >= 100 (spilled), emit STR src_reg, [sp, #(reg - 116) * 8].
    // Otherwise return bytes unchanged (value is already in its physical register).
    try g.beginReservedFunc("ec_store_spill");
    {
        _ = g.beginBlock();
        const st_bytes = try g.addParam();
        const st_reg = try g.addParam();
        const st_src = try g.addParam();
        const c100_s = try g.constInt(100);
        const is_spilled_s = try g.ge(st_reg, c100_s);
        const blk_spilled_s = g.reserveBlock();
        const blk_physical_s = g.reserveBlock();
        try g.branch(is_spilled_s, blk_spilled_s, blk_physical_s);

        g.beginReservedBlock(blk_physical_s);
        try g.ret(st_bytes);

        g.beginReservedBlock(blk_spilled_s);
        const c116_s = try g.constInt(116);
        const slot_s = try g.sub(st_reg, c116_s);
        const c8_s = try g.constInt(8);
        const offset_s = try g.binary(.mul, slot_s, c8_s);
        const c31_s = try g.constInt(31); // sp
        const str_enc = try g.callDirect(f_encode_str, &.{ st_src, c31_s, offset_s });
        const new_bytes_s = try g.callDirect(f_append_inst, &.{ st_bytes, str_enc });
        try g.ret(new_bytes_s);
    }
    try g.endReservedFunc(f_store_spill);

    // ── ec_emit_inst(inst, bytes, ctx) -> {bytes, ctx} ───────────────
    // Emit machine code for a single IR instruction.
    try g.beginReservedFunc("ec_emit_inst");
    {
        _ = g.beginBlock();
        const inst = try g.addParam();
        const bytes = try g.addParam();
        const ctx = try g.addParam();

        // Dispatch on inst tag
        const is_const_int = try g.tagTest(inst, ir_const_int);
        const blk_const_int = g.reserveBlock();
        const blk_not_const_int = g.reserveBlock();
        try g.branch(is_const_int, blk_const_int, blk_not_const_int);

        // IrConstInt: {dst, value} -> MOVZ/MOVK sequence
        g.beginReservedBlock(blk_const_int);
        const ci_payload = try g.tagPayload(inst, ir_const_int);
        const ci_dst = try g.recordField(ci_payload, "dst");
        const ci_value = try g.recordField(ci_payload, "value");
        const ci_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ci_dst });
        const ci_reg = try g.recordField(ci_alloc, "reg");
        const ci_ctx = try g.recordField(ci_alloc, "ctx");
        // If dst is spilled, load into x27, then store to stack
        const ci_c100 = try g.constInt(100);
        const ci_spilled = try g.ge(ci_reg, ci_c100);
        const blk_ci_spill = g.reserveBlock();
        const blk_ci_phys = g.reserveBlock();
        try g.branch(ci_spilled, blk_ci_spill, blk_ci_phys);

        g.beginReservedBlock(blk_ci_phys);
        {
            const ci_bytes = try g.callDirect(f_mov_imm64, &.{ bytes, ci_reg, ci_value });
            try g.ret(try g.record(&.{
                .{ .name = "bytes", .value = ci_bytes },
                .{ .name = "ctx", .value = ci_ctx },
            }));
        }
        g.beginReservedBlock(blk_ci_spill);
        {
            const ci_tmp = try g.constInt(16); // x16 as spill temp
            const ci_bytes = try g.callDirect(f_mov_imm64, &.{ bytes, ci_tmp, ci_value });
            const ci_bytes2 = try g.callDirect(f_store_spill, &.{ ci_bytes, ci_reg, ci_tmp });
            try g.ret(try g.record(&.{
                .{ .name = "bytes", .value = ci_bytes2 },
                .{ .name = "ctx", .value = ci_ctx },
            }));
        }

        // Not const_int: check binary
        g.beginReservedBlock(blk_not_const_int);
        const is_binary = try g.tagTest(inst, ir_binary);
        const blk_binary = g.reserveBlock();
        const blk_not_binary = g.reserveBlock();
        try g.branch(is_binary, blk_binary, blk_not_binary);

        // IrBinary: {dst, op, lhs, rhs}
        g.beginReservedBlock(blk_binary);
        const bin_payload = try g.tagPayload(inst, ir_binary);
        const bin_dst = try g.recordField(bin_payload, "dst");
        const bin_op = try g.recordField(bin_payload, "op");
        const bin_lhs = try g.recordField(bin_payload, "lhs");
        const bin_rhs = try g.recordField(bin_payload, "rhs");

        const bin_alloc_dst = try g.callDirect(f_alloc_reg, &.{ ctx, bin_dst });
        const bin_rd_raw = try g.recordField(bin_alloc_dst, "reg");
        const bin_ctx1 = try g.recordField(bin_alloc_dst, "ctx");

        const bin_rn_raw = try g.callDirect(f_get_reg, &.{ bin_ctx1, bin_lhs });
        const bin_rm_raw = try g.callDirect(f_get_reg, &.{ bin_ctx1, bin_rhs });

        // Load spilled operands into temp registers (x16 for lhs, x17 for rhs)
        const c16_b = try g.constInt(16);
        const c17_b = try g.constInt(17);
        const lhs_load = try g.callDirect(f_load_spill, &.{ bytes, bin_rn_raw, c16_b });
        const bytes_l1 = try g.recordField(lhs_load, "bytes");
        const bin_rn = try g.recordField(lhs_load, "reg");
        const rhs_load = try g.callDirect(f_load_spill, &.{ bytes_l1, bin_rm_raw, c17_b });
        const bytes_l2 = try g.recordField(rhs_load, "bytes");
        const bin_rm = try g.recordField(rhs_load, "reg");

        // If dst is spilled, compute into x16, then store to stack later
        const c100_b = try g.constInt(100);
        const dst_is_spilled = try g.ge(bin_rd_raw, c100_b);
        const blk_dst_spill = g.reserveBlock();
        const blk_dst_phys = g.reserveBlock();
        const blk_dst_merge = g.reserveBlock();
        try g.branch(dst_is_spilled, blk_dst_spill, blk_dst_phys);
        g.beginReservedBlock(blk_dst_spill);
        try g.jump(blk_dst_merge, &.{c16_b}); // use x16 as compute target
        g.beginReservedBlock(blk_dst_phys);
        try g.jump(blk_dst_merge, &.{bin_rd_raw});
        g.beginReservedBlock(blk_dst_merge);
        const bin_rd = try g.addBlockParam();
        // Reserve merge block for store-spill after binary op
        const bin_store_merge = g.reserveBlock();

        // Dispatch on op string — all branches use bytes_l2 (post spill-load)
        // and jump to bin_store_merge instead of returning directly
        const op_add = try g.constString("+");
        const is_add = try g.eq(bin_op, op_add);
        const blk_add = g.reserveBlock();
        const blk_not_add = g.reserveBlock();
        try g.branch(is_add, blk_add, blk_not_add);

        g.beginReservedBlock(blk_add);
        {
            const add_enc = try g.callDirect(f_encode_add_reg, &.{ bin_rd, bin_rn, bin_rm });
            const add_bytes = try g.callDirect(f_append_inst, &.{ bytes_l2, add_enc });
            try g.jump(bin_store_merge, &.{add_bytes});
        }

        g.beginReservedBlock(blk_not_add);
        const op_sub = try g.constString("-");
        const is_sub = try g.eq(bin_op, op_sub);
        const blk_sub = g.reserveBlock();
        const blk_not_sub = g.reserveBlock();
        try g.branch(is_sub, blk_sub, blk_not_sub);

        g.beginReservedBlock(blk_sub);
        {
            const sub_enc = try g.callDirect(f_encode_sub_reg, &.{ bin_rd, bin_rn, bin_rm });
            const sub_bytes = try g.callDirect(f_append_inst, &.{ bytes_l2, sub_enc });
            try g.jump(bin_store_merge, &.{sub_bytes});
        }

        g.beginReservedBlock(blk_not_sub);
        const op_mul = try g.constString("*");
        const is_mul = try g.eq(bin_op, op_mul);
        const blk_mul = g.reserveBlock();
        const blk_not_mul = g.reserveBlock();
        try g.branch(is_mul, blk_mul, blk_not_mul);

        g.beginReservedBlock(blk_mul);
        {
            const mul_enc = try g.callDirect(f_encode_mul, &.{ bin_rd, bin_rn, bin_rm });
            const mul_bytes = try g.callDirect(f_append_inst, &.{ bytes_l2, mul_enc });
            try g.jump(bin_store_merge, &.{mul_bytes});
        }

        g.beginReservedBlock(blk_not_mul);
        const op_div = try g.constString("/");
        const is_div = try g.eq(bin_op, op_div);
        const blk_div = g.reserveBlock();
        const blk_not_div = g.reserveBlock();
        try g.branch(is_div, blk_div, blk_not_div);

        g.beginReservedBlock(blk_div);
        {
            const div_enc = try g.callDirect(f_encode_sdiv, &.{ bin_rd, bin_rn, bin_rm });
            const div_bytes = try g.callDirect(f_append_inst, &.{ bytes_l2, div_enc });
            try g.jump(bin_store_merge, &.{div_bytes});
        }

        // == comparison
        g.beginReservedBlock(blk_not_div);
        const op_eq = try g.constString("==");
        const is_eq_op = try g.eq(bin_op, op_eq);
        const blk_eq = g.reserveBlock();
        const blk_not_eq = g.reserveBlock();
        try g.branch(is_eq_op, blk_eq, blk_not_eq);

        g.beginReservedBlock(blk_eq);
        {
            const cmp_eq = try g.callDirect(f_encode_cmp_reg, &.{ bin_rn, bin_rm });
            const b_eq1 = try g.callDirect(f_append_inst, &.{ bytes_l2, cmp_eq });
            const cond_eq = try g.constInt(0); // EQ
            const cset_eq = try g.callDirect(f_encode_cset, &.{ bin_rd, cond_eq });
            const b_eq2 = try g.callDirect(f_append_inst, &.{ b_eq1, cset_eq });
            try g.jump(bin_store_merge, &.{b_eq2});
        }

        // < comparison
        g.beginReservedBlock(blk_not_eq);
        const op_lt = try g.constString("<");
        const is_lt_op = try g.eq(bin_op, op_lt);
        const blk_lt = g.reserveBlock();
        const blk_not_lt = g.reserveBlock();
        try g.branch(is_lt_op, blk_lt, blk_not_lt);

        g.beginReservedBlock(blk_lt);
        {
            const cmp_lt = try g.callDirect(f_encode_cmp_reg, &.{ bin_rn, bin_rm });
            const b_lt1 = try g.callDirect(f_append_inst, &.{ bytes_l2, cmp_lt });
            const cond_lt = try g.constInt(11); // LT
            const cset_lt = try g.callDirect(f_encode_cset, &.{ bin_rd, cond_lt });
            const b_lt2 = try g.callDirect(f_append_inst, &.{ b_lt1, cset_lt });
            try g.jump(bin_store_merge, &.{b_lt2});
        }

        // > comparison
        g.beginReservedBlock(blk_not_lt);
        const op_gt = try g.constString(">");
        const is_gt_op = try g.eq(bin_op, op_gt);
        const blk_gt = g.reserveBlock();
        const blk_not_gt = g.reserveBlock();
        try g.branch(is_gt_op, blk_gt, blk_not_gt);

        g.beginReservedBlock(blk_gt);
        {
            const cmp_gt = try g.callDirect(f_encode_cmp_reg, &.{ bin_rn, bin_rm });
            const b_gt1 = try g.callDirect(f_append_inst, &.{ bytes_l2, cmp_gt });
            const cond_gt = try g.constInt(12); // GT
            const cset_gt = try g.callDirect(f_encode_cset, &.{ bin_rd, cond_gt });
            const b_gt2 = try g.callDirect(f_append_inst, &.{ b_gt1, cset_gt });
            try g.jump(bin_store_merge, &.{b_gt2});
        }

        // <= comparison
        g.beginReservedBlock(blk_not_gt);
        const op_le = try g.constString("<=");
        const is_le_op = try g.eq(bin_op, op_le);
        const blk_le = g.reserveBlock();
        const blk_not_le = g.reserveBlock();
        try g.branch(is_le_op, blk_le, blk_not_le);

        g.beginReservedBlock(blk_le);
        {
            const cmp_le = try g.callDirect(f_encode_cmp_reg, &.{ bin_rn, bin_rm });
            const b_le1 = try g.callDirect(f_append_inst, &.{ bytes_l2, cmp_le });
            const cond_le = try g.constInt(13); // LE
            const cset_le = try g.callDirect(f_encode_cset, &.{ bin_rd, cond_le });
            const b_le2 = try g.callDirect(f_append_inst, &.{ b_le1, cset_le });
            try g.jump(bin_store_merge, &.{b_le2});
        }

        // >= comparison
        g.beginReservedBlock(blk_not_le);
        const op_ge = try g.constString(">=");
        const is_ge_op = try g.eq(bin_op, op_ge);
        const blk_ge_op = g.reserveBlock();
        const blk_not_ge_op = g.reserveBlock();
        try g.branch(is_ge_op, blk_ge_op, blk_not_ge_op);

        g.beginReservedBlock(blk_ge_op);
        {
            const cmp_ge = try g.callDirect(f_encode_cmp_reg, &.{ bin_rn, bin_rm });
            const b_ge1 = try g.callDirect(f_append_inst, &.{ bytes_l2, cmp_ge });
            const cond_ge = try g.constInt(10); // GE
            const cset_ge = try g.callDirect(f_encode_cset, &.{ bin_rd, cond_ge });
            const b_ge2 = try g.callDirect(f_append_inst, &.{ b_ge1, cset_ge });
            try g.jump(bin_store_merge, &.{b_ge2});
        }

        // != comparison
        g.beginReservedBlock(blk_not_ge_op);
        const op_ne = try g.constString("!=");
        const is_ne_op = try g.eq(bin_op, op_ne);
        const blk_ne_op = g.reserveBlock();
        const blk_not_ne_op = g.reserveBlock();
        try g.branch(is_ne_op, blk_ne_op, blk_not_ne_op);

        g.beginReservedBlock(blk_ne_op);
        {
            const cmp_ne = try g.callDirect(f_encode_cmp_reg, &.{ bin_rn, bin_rm });
            const b_ne1 = try g.callDirect(f_append_inst, &.{ bytes_l2, cmp_ne });
            const cond_ne = try g.constInt(1); // NE
            const cset_ne = try g.callDirect(f_encode_cset, &.{ bin_rd, cond_ne });
            const b_ne2 = try g.callDirect(f_append_inst, &.{ b_ne1, cset_ne });
            try g.jump(bin_store_merge, &.{b_ne2});
        }

        // % modulo: SDIV Xdst, Xlhs, Xrhs; MSUB Xdst, Xdst, Xrhs, Xlhs
        g.beginReservedBlock(blk_not_ne_op);
        const op_mod = try g.constString("%");
        const is_mod_op = try g.eq(bin_op, op_mod);
        const blk_mod = g.reserveBlock();
        const blk_not_mod = g.reserveBlock();
        try g.branch(is_mod_op, blk_mod, blk_not_mod);

        g.beginReservedBlock(blk_mod);
        {
            const sdiv_enc = try g.callDirect(f_encode_sdiv, &.{ bin_rd, bin_rn, bin_rm });
            const b_mod1 = try g.callDirect(f_append_inst, &.{ bytes_l2, sdiv_enc });
            const msub_enc = try g.callDirect(f_encode_msub, &.{ bin_rd, bin_rd, bin_rm, bin_rn });
            const b_mod2 = try g.callDirect(f_append_inst, &.{ b_mod1, msub_enc });
            try g.jump(bin_store_merge, &.{b_mod2});
        }

        // "and" logical: AND Xd, Xn, Xm
        g.beginReservedBlock(blk_not_mod);
        const op_and = try g.constString("and");
        const is_and_op = try g.eq(bin_op, op_and);
        const blk_and = g.reserveBlock();
        const blk_not_and = g.reserveBlock();
        try g.branch(is_and_op, blk_and, blk_not_and);

        g.beginReservedBlock(blk_and);
        {
            const and_enc = try g.callDirect(f_encode_and_reg, &.{ bin_rd, bin_rn, bin_rm });
            const b_and = try g.callDirect(f_append_inst, &.{ bytes_l2, and_enc });
            try g.jump(bin_store_merge, &.{b_and});
        }

        // "or" logical: ORR Xd, Xn, Xm
        g.beginReservedBlock(blk_not_and);
        const op_or = try g.constString("or");
        const is_or_op = try g.eq(bin_op, op_or);
        const blk_or = g.reserveBlock();
        const blk_not_or = g.reserveBlock();
        try g.branch(is_or_op, blk_or, blk_not_or);

        g.beginReservedBlock(blk_or);
        {
            const orr_enc = try g.callDirect(f_encode_orr_reg, &.{ bin_rd, bin_rn, bin_rm });
            const b_or = try g.callDirect(f_append_inst, &.{ bytes_l2, orr_enc });
            try g.jump(bin_store_merge, &.{b_or});
        }

        // Default: treat unknown op as NOP (return unchanged)
        g.beginReservedBlock(blk_not_or);
        try g.jump(bin_store_merge, &.{bytes_l2});

        // ── Binary op merge: store result to spill slot if dst is spilled ──
        g.beginReservedBlock(bin_store_merge);
        const bin_op_bytes = try g.addBlockParam();
        // If bin_rd_raw >= 100, the result was computed into x16 (bin_rd); store to stack
        const bin_final_bytes = try g.callDirect(f_store_spill, &.{ bin_op_bytes, bin_rd_raw, bin_rd });
        const bin_final_result = try g.record(&.{
            .{ .name = "bytes", .value = bin_final_bytes },
            .{ .name = "ctx", .value = bin_ctx1 },
        });
        try g.ret(bin_final_result);

        // Not binary: check string_eq
        g.beginReservedBlock(blk_not_binary);
        const is_str_eq = try g.tagTest(inst, ir_string_eq);
        const blk_str_eq = g.reserveBlock();
        const blk_not_str_eq = g.reserveBlock();
        try g.branch(is_str_eq, blk_str_eq, blk_not_str_eq);

        // ── IrStringEq: inline string comparison ──
        // Emits ~23 aarch64 instructions: compare lengths, then compare data word-by-word
        g.beginReservedBlock(blk_str_eq);
        {
            const se_payload = try g.tagPayload(inst, ir_string_eq);
            const se_dst = try g.recordField(se_payload, "dst");
            const se_lhs = try g.recordField(se_payload, "lhs");
            const se_rhs = try g.recordField(se_payload, "rhs");

            // Alloc reg for dst
            const se_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, se_dst });
            const se_rd_raw = try g.recordField(se_alloc, "reg");
            const se_ctx = try g.recordField(se_alloc, "ctx");

            // Get regs for lhs, rhs
            const se_rn_raw = try g.callDirect(f_get_reg, &.{ se_ctx, se_lhs });
            const se_rm_raw = try g.callDirect(f_get_reg, &.{ se_ctx, se_rhs });

            // Load spilled operands into x16 (lhs) and x17 (rhs)
            const c16_se = try g.constInt(16);
            const c17_se = try g.constInt(17);
            const se_lhs_load = try g.callDirect(f_load_spill, &.{ bytes, se_rn_raw, c16_se });
            const se_b1 = try g.recordField(se_lhs_load, "bytes");
            const se_rn = try g.recordField(se_lhs_load, "reg");
            const se_rhs_load = try g.callDirect(f_load_spill, &.{ se_b1, se_rm_raw, c17_se });
            const se_b2 = try g.recordField(se_rhs_load, "bytes");
            const se_rm = try g.recordField(se_rhs_load, "reg");

            // Determine dst register (use x6 as temp if spilled)
            const c100_se = try g.constInt(100);
            const se_dst_spilled = try g.ge(se_rd_raw, c100_se);
            const se_spill_blk = g.reserveBlock();
            const se_phys_blk = g.reserveBlock();
            const se_merge_blk = g.reserveBlock();
            try g.branch(se_dst_spilled, se_spill_blk, se_phys_blk);
            g.beginReservedBlock(se_spill_blk);
            const c6_se = try g.constInt(6);
            try g.jump(se_merge_blk, &.{c6_se});
            g.beginReservedBlock(se_phys_blk);
            try g.jump(se_merge_blk, &.{se_rd_raw});
            g.beginReservedBlock(se_merge_blk);
            const se_rd = try g.addBlockParam();

            // Register constants (also used as immediates where value matches)
            const c0 = try g.constInt(0);
            const c1_se = try g.constInt(1);
            const c2_se = try g.constInt(2);
            const c3_se = try g.constInt(3);
            const c4_se = try g.constInt(4);
            const c5_se = try g.constInt(5);
            const c31 = try g.constInt(31); // XZR
            const c7_se = try g.constInt(7);
            const c8_se = try g.constInt(8);

            // Instr 0: LDR x0, [Rn, #8]  — lhs.len
            const se_i0 = try g.callDirect(f_encode_ldr, &.{ c0, se_rn, c8_se });
            const se_b3 = try g.callDirect(f_append_inst, &.{ se_b2, se_i0 });
            // Instr 1: LDR x1, [Rm, #8]  — rhs.len
            const se_i1 = try g.callDirect(f_encode_ldr, &.{ c1_se, se_rm, c8_se });
            const se_b4 = try g.callDirect(f_append_inst, &.{ se_b3, se_i1 });
            // Instr 2: CMP x0, x1
            const se_i2 = try g.callDirect(f_encode_cmp_reg, &.{ c0, c1_se });
            const se_b5 = try g.callDirect(f_append_inst, &.{ se_b4, se_i2 });
            // Instr 3: B.NE +76  → not_equal (instr 22, offset=(22-3)*4=76)
            const c76 = try g.constInt(76);
            const se_i3 = try g.callDirect(f_encode_b_cond, &.{ c76, c1_se }); // NE=1
            const se_b6 = try g.callDirect(f_append_inst, &.{ se_b5, se_i3 });
            // Instr 4: LDR x2, [Rn, #0]  — lhs.ptr
            const se_i4 = try g.callDirect(f_encode_ldr, &.{ c2_se, se_rn, c0 });
            const se_b7 = try g.callDirect(f_append_inst, &.{ se_b6, se_i4 });
            // Instr 5: LDR x3, [Rm, #0]  — rhs.ptr
            const se_i5 = try g.callDirect(f_encode_ldr, &.{ c3_se, se_rm, c0 });
            const se_b8 = try g.callDirect(f_append_inst, &.{ se_b7, se_i5 });
            // Instr 6: ADD x0, x0, #7
            const se_i6 = try g.callDirect(f_encode_add_imm, &.{ c0, c0, c7_se });
            const se_b9 = try g.callDirect(f_append_inst, &.{ se_b8, se_i6 });
            // Instr 7: MOVZ x1, #8
            const se_i7 = try g.callDirect(f_encode_movz, &.{ c1_se, c8_se, c0 });
            const se_b10 = try g.callDirect(f_append_inst, &.{ se_b9, se_i7 });
            // Instr 8: SDIV x0, x0, x1  — num_words = (len+7)/8
            const se_i8 = try g.callDirect(f_encode_sdiv, &.{ c0, c0, c1_se });
            const se_b11 = try g.callDirect(f_append_inst, &.{ se_b10, se_i8 });
            // Instr 9: CMP x0, XZR  — check if 0 words
            const se_i9 = try g.callDirect(f_encode_cmp_reg, &.{ c0, c31 });
            const se_b12 = try g.callDirect(f_append_inst, &.{ se_b11, se_i9 });
            // Instr 10: B.EQ +40  → equal (instr 20, offset=(20-10)*4=40)
            const c40 = try g.constInt(40);
            const se_i10 = try g.callDirect(f_encode_b_cond, &.{ c40, c0 }); // EQ=0
            const se_b13 = try g.callDirect(f_append_inst, &.{ se_b12, se_i10 });
            // Instr 11: LDR x4, [x2, #0]  — load lhs word (loop start)
            const se_i11 = try g.callDirect(f_encode_ldr, &.{ c4_se, c2_se, c0 });
            const se_b14 = try g.callDirect(f_append_inst, &.{ se_b13, se_i11 });
            // Instr 12: LDR x5, [x3, #0]  — load rhs word
            const se_i12 = try g.callDirect(f_encode_ldr, &.{ c5_se, c3_se, c0 });
            const se_b15 = try g.callDirect(f_append_inst, &.{ se_b14, se_i12 });
            // Instr 13: CMP x4, x5
            const se_i13 = try g.callDirect(f_encode_cmp_reg, &.{ c4_se, c5_se });
            const se_b16 = try g.callDirect(f_append_inst, &.{ se_b15, se_i13 });
            // Instr 14: B.NE +32  → not_equal (instr 22, offset=(22-14)*4=32)
            const c32_se = try g.constInt(32);
            const se_i14 = try g.callDirect(f_encode_b_cond, &.{ c32_se, c1_se }); // NE=1
            const se_b17 = try g.callDirect(f_append_inst, &.{ se_b16, se_i14 });
            // Instr 15: ADD x2, x2, #8  — advance lhs ptr
            const se_i15 = try g.callDirect(f_encode_add_imm, &.{ c2_se, c2_se, c8_se });
            const se_b18 = try g.callDirect(f_append_inst, &.{ se_b17, se_i15 });
            // Instr 16: ADD x3, x3, #8  — advance rhs ptr
            const se_i16 = try g.callDirect(f_encode_add_imm, &.{ c3_se, c3_se, c8_se });
            const se_b19 = try g.callDirect(f_append_inst, &.{ se_b18, se_i16 });
            // Instr 17: SUB x0, x0, #1  — decrement word count
            const se_i17 = try g.callDirect(f_encode_sub_imm, &.{ c0, c0, c1_se });
            const se_b20 = try g.callDirect(f_append_inst, &.{ se_b19, se_i17 });
            // Instr 18: CMP x0, XZR  — check if done
            const se_i18 = try g.callDirect(f_encode_cmp_reg, &.{ c0, c31 });
            const se_b21 = try g.callDirect(f_append_inst, &.{ se_b20, se_i18 });
            // Instr 19: B.NE -32  → loop (instr 11, offset=(11-19)*4=-32)
            // Negative offset: -32 as signed will be masked to 19-bit two's complement
            const cn32 = try g.constInt(-32);
            const se_i19 = try g.callDirect(f_encode_b_cond, &.{ cn32, c1_se }); // NE=1
            const se_b22 = try g.callDirect(f_append_inst, &.{ se_b21, se_i19 });
            // Instr 20: MOVZ Rd, #1  — equal
            const se_i20 = try g.callDirect(f_encode_movz, &.{ se_rd, c1_se, c0 });
            const se_b23 = try g.callDirect(f_append_inst, &.{ se_b22, se_i20 });
            // Instr 21: B +8  → done (instr 23, offset=(23-21)*4=8)
            const se_i21 = try g.callDirect(f_encode_b, &.{c8_se});
            const se_b24 = try g.callDirect(f_append_inst, &.{ se_b23, se_i21 });
            // Instr 22: MOVZ Rd, #0  — not_equal
            const se_i22 = try g.callDirect(f_encode_movz, &.{ se_rd, c0, c0 });
            const se_b25 = try g.callDirect(f_append_inst, &.{ se_b24, se_i22 });
            // Instr 23 is the done point (next instruction after)

            // Store result to spill slot if dst is spilled
            const se_final = try g.callDirect(f_store_spill, &.{ se_b25, se_rd_raw, se_rd });
            const se_result = try g.record(&.{
                .{ .name = "bytes", .value = se_final },
                .{ .name = "ctx", .value = se_ctx },
            });
            try g.ret(se_result);
        }

        // Not string_eq: check string_ne
        g.beginReservedBlock(blk_not_str_eq);
        const is_str_ne = try g.tagTest(inst, ir_string_ne);
        const blk_str_ne = g.reserveBlock();
        const blk_not_str_ne = g.reserveBlock();
        try g.branch(is_str_ne, blk_str_ne, blk_not_str_ne);

        // ── IrStringNe: same as IrStringEq but with result inverted ──
        g.beginReservedBlock(blk_str_ne);
        {
            const sn_payload = try g.tagPayload(inst, ir_string_ne);
            const sn_dst = try g.recordField(sn_payload, "dst");
            const sn_lhs = try g.recordField(sn_payload, "lhs");
            const sn_rhs = try g.recordField(sn_payload, "rhs");

            const sn_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, sn_dst });
            const sn_rd_raw = try g.recordField(sn_alloc, "reg");
            const sn_ctx = try g.recordField(sn_alloc, "ctx");

            const sn_rn_raw = try g.callDirect(f_get_reg, &.{ sn_ctx, sn_lhs });
            const sn_rm_raw = try g.callDirect(f_get_reg, &.{ sn_ctx, sn_rhs });

            const c16_sn = try g.constInt(16);
            const c17_sn = try g.constInt(17);
            const sn_lhs_load = try g.callDirect(f_load_spill, &.{ bytes, sn_rn_raw, c16_sn });
            const sn_b1 = try g.recordField(sn_lhs_load, "bytes");
            const sn_rn = try g.recordField(sn_lhs_load, "reg");
            const sn_rhs_load = try g.callDirect(f_load_spill, &.{ sn_b1, sn_rm_raw, c17_sn });
            const sn_b2 = try g.recordField(sn_rhs_load, "bytes");
            const sn_rm = try g.recordField(sn_rhs_load, "reg");

            const c100_sn = try g.constInt(100);
            const sn_dst_spilled = try g.ge(sn_rd_raw, c100_sn);
            const sn_spill_blk = g.reserveBlock();
            const sn_phys_blk = g.reserveBlock();
            const sn_merge_blk = g.reserveBlock();
            try g.branch(sn_dst_spilled, sn_spill_blk, sn_phys_blk);
            g.beginReservedBlock(sn_spill_blk);
            const c6_sn = try g.constInt(6);
            try g.jump(sn_merge_blk, &.{c6_sn});
            g.beginReservedBlock(sn_phys_blk);
            try g.jump(sn_merge_blk, &.{sn_rd_raw});
            g.beginReservedBlock(sn_merge_blk);
            const sn_rd = try g.addBlockParam();

            // Same comparison as IrStringEq but swap equal/not_equal results
            const sn_c0 = try g.constInt(0);
            const sn_c1 = try g.constInt(1);
            const sn_c2 = try g.constInt(2);
            const sn_c3 = try g.constInt(3);
            const sn_c4 = try g.constInt(4);
            const sn_c5 = try g.constInt(5);
            const sn_c31 = try g.constInt(31);
            const sn_c7 = try g.constInt(7);
            const sn_c8 = try g.constInt(8);

            const sn_i0 = try g.callDirect(f_encode_ldr, &.{ sn_c0, sn_rn, sn_c8 });
            const sn_b3 = try g.callDirect(f_append_inst, &.{ sn_b2, sn_i0 });
            const sn_i1 = try g.callDirect(f_encode_ldr, &.{ sn_c1, sn_rm, sn_c8 });
            const sn_b4 = try g.callDirect(f_append_inst, &.{ sn_b3, sn_i1 });
            const sn_i2 = try g.callDirect(f_encode_cmp_reg, &.{ sn_c0, sn_c1 });
            const sn_b5 = try g.callDirect(f_append_inst, &.{ sn_b4, sn_i2 });
            // B.NE → not_equal → result=1 (strings ARE not-equal)
            const sn_c76 = try g.constInt(76);
            const sn_i3 = try g.callDirect(f_encode_b_cond, &.{ sn_c76, sn_c1 });
            const sn_b6 = try g.callDirect(f_append_inst, &.{ sn_b5, sn_i3 });
            const sn_i4 = try g.callDirect(f_encode_ldr, &.{ sn_c2, sn_rn, sn_c0 });
            const sn_b7 = try g.callDirect(f_append_inst, &.{ sn_b6, sn_i4 });
            const sn_i5 = try g.callDirect(f_encode_ldr, &.{ sn_c3, sn_rm, sn_c0 });
            const sn_b8 = try g.callDirect(f_append_inst, &.{ sn_b7, sn_i5 });
            const sn_i6 = try g.callDirect(f_encode_add_imm, &.{ sn_c0, sn_c0, sn_c7 });
            const sn_b9 = try g.callDirect(f_append_inst, &.{ sn_b8, sn_i6 });
            const sn_i7 = try g.callDirect(f_encode_movz, &.{ sn_c1, sn_c8, sn_c0 });
            const sn_b10 = try g.callDirect(f_append_inst, &.{ sn_b9, sn_i7 });
            const sn_i8 = try g.callDirect(f_encode_sdiv, &.{ sn_c0, sn_c0, sn_c1 });
            const sn_b11 = try g.callDirect(f_append_inst, &.{ sn_b10, sn_i8 });
            const sn_i9 = try g.callDirect(f_encode_cmp_reg, &.{ sn_c0, sn_c31 });
            const sn_b12 = try g.callDirect(f_append_inst, &.{ sn_b11, sn_i9 });
            // B.EQ → equal → result=0 (strings are equal, so NOT not-equal)
            const sn_c40 = try g.constInt(40);
            const sn_i10 = try g.callDirect(f_encode_b_cond, &.{ sn_c40, sn_c0 });
            const sn_b13 = try g.callDirect(f_append_inst, &.{ sn_b12, sn_i10 });
            const sn_i11 = try g.callDirect(f_encode_ldr, &.{ sn_c4, sn_c2, sn_c0 });
            const sn_b14 = try g.callDirect(f_append_inst, &.{ sn_b13, sn_i11 });
            const sn_i12 = try g.callDirect(f_encode_ldr, &.{ sn_c5, sn_c3, sn_c0 });
            const sn_b15 = try g.callDirect(f_append_inst, &.{ sn_b14, sn_i12 });
            const sn_i13 = try g.callDirect(f_encode_cmp_reg, &.{ sn_c4, sn_c5 });
            const sn_b16 = try g.callDirect(f_append_inst, &.{ sn_b15, sn_i13 });
            const sn_c32 = try g.constInt(32);
            const sn_i14 = try g.callDirect(f_encode_b_cond, &.{ sn_c32, sn_c1 });
            const sn_b17 = try g.callDirect(f_append_inst, &.{ sn_b16, sn_i14 });
            const sn_i15 = try g.callDirect(f_encode_add_imm, &.{ sn_c2, sn_c2, sn_c8 });
            const sn_b18 = try g.callDirect(f_append_inst, &.{ sn_b17, sn_i15 });
            const sn_i16 = try g.callDirect(f_encode_add_imm, &.{ sn_c3, sn_c3, sn_c8 });
            const sn_b19 = try g.callDirect(f_append_inst, &.{ sn_b18, sn_i16 });
            const sn_i17 = try g.callDirect(f_encode_sub_imm, &.{ sn_c0, sn_c0, sn_c1 });
            const sn_b20 = try g.callDirect(f_append_inst, &.{ sn_b19, sn_i17 });
            const sn_i18 = try g.callDirect(f_encode_cmp_reg, &.{ sn_c0, sn_c31 });
            const sn_b21 = try g.callDirect(f_append_inst, &.{ sn_b20, sn_i18 });
            const sn_cn32 = try g.constInt(-32);
            const sn_i19 = try g.callDirect(f_encode_b_cond, &.{ sn_cn32, sn_c1 });
            const sn_b22 = try g.callDirect(f_append_inst, &.{ sn_b21, sn_i19 });
            // equal → result=0 (for !=, equal strings means false)
            const sn_i20 = try g.callDirect(f_encode_movz, &.{ sn_rd, sn_c0, sn_c0 });
            const sn_b23 = try g.callDirect(f_append_inst, &.{ sn_b22, sn_i20 });
            const sn_i21 = try g.callDirect(f_encode_b, &.{sn_c8});
            const sn_b24 = try g.callDirect(f_append_inst, &.{ sn_b23, sn_i21 });
            // not_equal → result=1 (for !=, different strings means true)
            const sn_i22 = try g.callDirect(f_encode_movz, &.{ sn_rd, sn_c1, sn_c0 });
            const sn_b25 = try g.callDirect(f_append_inst, &.{ sn_b24, sn_i22 });

            const sn_final = try g.callDirect(f_store_spill, &.{ sn_b25, sn_rd_raw, sn_rd });
            const sn_result = try g.record(&.{
                .{ .name = "bytes", .value = sn_final },
                .{ .name = "ctx", .value = sn_ctx },
            });
            try g.ret(sn_result);
        }

        // Not string_ne: check const_bool
        g.beginReservedBlock(blk_not_str_ne);
        const is_const_bool = try g.tagTest(inst, ir_const_bool);
        const blk_const_bool = g.reserveBlock();
        const blk_not_const_bool = g.reserveBlock();
        try g.branch(is_const_bool, blk_const_bool, blk_not_const_bool);

        g.beginReservedBlock(blk_const_bool);
        const cb_payload = try g.tagPayload(inst, ir_const_bool);
        const cb_dst = try g.recordField(cb_payload, "dst");
        const cb_value = try g.recordField(cb_payload, "value");
        // Convert boolean to integer: true → 1, false → 0
        const blk_cb_true = g.reserveBlock();
        const blk_cb_false = g.reserveBlock();
        const blk_cb_merge = g.reserveBlock();
        try g.branch(cb_value, blk_cb_true, blk_cb_false);

        g.beginReservedBlock(blk_cb_true);
        const cb_int_one = try g.constInt(1);
        try g.jump(blk_cb_merge, &.{cb_int_one});

        g.beginReservedBlock(blk_cb_false);
        const cb_int_zero = try g.constInt(0);
        try g.jump(blk_cb_merge, &.{cb_int_zero});

        g.beginReservedBlock(blk_cb_merge);
        const cb_int_val = try g.addBlockParam();
        const cb_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, cb_dst });
        const cb_reg = try g.recordField(cb_alloc, "reg");
        const cb_ctx = try g.recordField(cb_alloc, "ctx");
        const cb_bytes = try g.callDirect(f_mov_imm64, &.{ bytes, cb_reg, cb_int_val });
        const cb_result = try g.record(&.{
            .{ .name = "bytes", .value = cb_bytes },
            .{ .name = "ctx", .value = cb_ctx },
        });
        try g.ret(cb_result);

        // Not const_bool: check const_nil
        g.beginReservedBlock(blk_not_const_bool);
        const is_const_nil = try g.tagTest(inst, ir_const_nil);
        const blk_const_nil = g.reserveBlock();
        const blk_fallthrough = g.reserveBlock();
        try g.branch(is_const_nil, blk_const_nil, blk_fallthrough);

        g.beginReservedBlock(blk_const_nil);
        const cn_payload = try g.tagPayload(inst, ir_const_nil);
        const cn_dst = try g.recordField(cn_payload, "dst");
        const cn_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, cn_dst });
        const cn_reg = try g.recordField(cn_alloc, "reg");
        const cn_ctx = try g.recordField(cn_alloc, "ctx");
        const cn_zero = try g.constInt(0);
        const cn_bytes = try g.callDirect(f_mov_imm64, &.{ bytes, cn_reg, cn_zero });
        const cn_result = try g.record(&.{
            .{ .name = "bytes", .value = cn_bytes },
            .{ .name = "ctx", .value = cn_ctx },
        });
        try g.ret(cn_result);

        // Not const_nil: check IrCall
        g.beginReservedBlock(blk_fallthrough);
        const is_call = try g.tagTest(inst, ir_call);
        const blk_call = g.reserveBlock();
        const blk_not_call = g.reserveBlock();
        try g.branch(is_call, blk_call, blk_not_call);

        // IrCall: {dst, callee, args} -> move args to x0..xN, BL callee, MOV dst, x0
        g.beginReservedBlock(blk_call);
        {
            const call_payload = try g.tagPayload(inst, ir_call);
            const call_dst = try g.recordField(call_payload, "dst");
            const call_callee = try g.recordField(call_payload, "callee");
            const call_args = try g.recordField(call_payload, "args");
            const call_num_args = try g.listLength(call_args);

            // Move args to x0..x7
            const c0_call = try g.constInt(0);
            const args_loop = g.reserveBlock();
            try g.jump(args_loop, &.{ c0_call, bytes, ctx });

            g.beginReservedBlock(args_loop);
            const ai = try g.addBlockParam();
            const ab = try g.addBlockParam();
            const ac = try g.addBlockParam();
            const args_done = try g.ge(ai, call_num_args);
            const args_exit = g.reserveBlock();
            const args_body = g.reserveBlock();
            try g.branch(args_done, args_exit, args_body);

            g.beginReservedBlock(args_body);
            {
                // Get the register for this arg value
                const arg_val_id = try g.listNth(call_args, ai);
                const arg_reg_raw = try g.callDirect(f_get_reg, &.{ ac, arg_val_id });
                // Load from spill slot if needed (use x16 as temp)
                const c16_ca = try g.constInt(16);
                const arg_load = try g.callDirect(f_load_spill, &.{ ab, arg_reg_raw, c16_ca });
                const ab_loaded = try g.recordField(arg_load, "bytes");
                const arg_reg = try g.recordField(arg_load, "reg");
                // Target register is xi (i = ai)
                // Only emit MOV if arg_reg != ai
                const need_mov = try g.ne(arg_reg, ai);
                const do_mov = g.reserveBlock();
                const skip_mov = g.reserveBlock();
                const after_mov = g.reserveBlock();
                try g.branch(need_mov, do_mov, skip_mov);

                g.beginReservedBlock(do_mov);
                // MOV xi, arg_reg: ADD xi, arg_reg, #0
                const c0_m = try g.constInt(0);
                const mov_enc = try g.callDirect(f_encode_add_imm, &.{ ai, arg_reg, c0_m });
                const mb = try g.callDirect(f_append_inst, &.{ ab_loaded, mov_enc });
                try g.jump(after_mov, &.{mb});

                g.beginReservedBlock(skip_mov);
                try g.jump(after_mov, &.{ab_loaded});

                g.beginReservedBlock(after_mov);
                const ab2 = try g.addBlockParam();
                const c1_a = try g.constInt(1);
                const next_ai = try g.add(ai, c1_a);
                try g.jump(args_loop, &.{ next_ai, ab2, ac });
            }

            // Args done — check if direct or indirect call
            g.beginReservedBlock(args_exit);
            {
                const call_fmap = try g.recordField(ac, "func_map");
                const has_callee = try g.mapHas(call_fmap, call_callee);
                const blk_direct_call = g.reserveBlock();
                const blk_indirect_call = g.reserveBlock();
                try g.branch(has_callee, blk_direct_call, blk_indirect_call);

                const blk_call_merge = g.reserveBlock();

                // Direct call: BL to known function
                g.beginReservedBlock(blk_direct_call);
                {
                    const target_off = try g.mapGet(call_fmap, call_callee);
                    const cur_off = try g.callBuiltin("bytes_length", &.{ab});
                    const rel_off = try g.sub(target_off, cur_off);
                    const bl_enc = try g.callDirect(f_encode_bl, &.{rel_off});
                    const bl_bytes = try g.callDirect(f_append_inst, &.{ ab, bl_enc });
                    try g.jump(blk_call_merge, &.{ bl_bytes, ac });
                }

                // Indirect call: BLR Xn — use callee_val (value ID) to get register
                g.beginReservedBlock(blk_indirect_call);
                {
                    const call_callee_val = try g.recordField(call_payload, "callee_val");
                    const ind_reg_raw = try g.callDirect(f_get_reg, &.{ ac, call_callee_val });
                    // Load from spill if needed (use x16 as temp)
                    const c16_ind = try g.constInt(16);
                    const ind_load = try g.callDirect(f_load_spill, &.{ ab, ind_reg_raw, c16_ind });
                    const ind_bytes = try g.recordField(ind_load, "bytes");
                    const ind_reg = try g.recordField(ind_load, "reg");
                    const blr_enc = try g.callDirect(f_encode_blr, &.{ind_reg});
                    const blr_bytes = try g.callDirect(f_append_inst, &.{ ind_bytes, blr_enc });
                    try g.jump(blk_call_merge, &.{ blr_bytes, ac });
                }

                // Merge: allocate dst register, move x0 if needed
                g.beginReservedBlock(blk_call_merge);
                const call_bytes_m = try g.addBlockParam();
                const call_ctx_m = try g.addBlockParam();

                const call_alloc = try g.callDirect(f_alloc_reg, &.{ call_ctx_m, call_dst });
                const dst_reg = try g.recordField(call_alloc, "reg");
                const call_ctx = try g.recordField(call_alloc, "ctx");

                const c0_r = try g.constInt(0);
                // Check if dst is spilled
                const c100_cr = try g.constInt(100);
                const call_dst_spilled = try g.ge(dst_reg, c100_cr);
                const blk_call_dst_spill = g.reserveBlock();
                const blk_call_dst_phys = g.reserveBlock();
                try g.branch(call_dst_spilled, blk_call_dst_spill, blk_call_dst_phys);

                // Physical register: MOV dst_reg, x0 (if not already x0)
                g.beginReservedBlock(blk_call_dst_phys);
                {
                    const dst_is_x0 = try g.eq(dst_reg, c0_r);
                    const blk_need_ret_mov = g.reserveBlock();
                    const blk_skip_ret_mov = g.reserveBlock();
                    const blk_after_ret_mov = g.reserveBlock();
                    try g.branch(dst_is_x0, blk_skip_ret_mov, blk_need_ret_mov);

                    g.beginReservedBlock(blk_need_ret_mov);
                    const ret_mov_enc = try g.callDirect(f_encode_add_imm, &.{ dst_reg, c0_r, c0_r });
                    const ret_mov_bytes = try g.callDirect(f_append_inst, &.{ call_bytes_m, ret_mov_enc });
                    try g.jump(blk_after_ret_mov, &.{ret_mov_bytes});

                    g.beginReservedBlock(blk_skip_ret_mov);
                    try g.jump(blk_after_ret_mov, &.{call_bytes_m});

                    g.beginReservedBlock(blk_after_ret_mov);
                    const final_bytes_p = try g.addBlockParam();
                    const call_result_p = try g.record(&.{
                        .{ .name = "bytes", .value = final_bytes_p },
                        .{ .name = "ctx", .value = call_ctx },
                    });
                    try g.ret(call_result_p);
                }

                // Spilled register: STR x0, [sp, #offset]
                g.beginReservedBlock(blk_call_dst_spill);
                {
                    const spill_bytes = try g.callDirect(f_store_spill, &.{ call_bytes_m, dst_reg, c0_r });
                    const call_result_s = try g.record(&.{
                        .{ .name = "bytes", .value = spill_bytes },
                        .{ .name = "ctx", .value = call_ctx },
                    });
                    try g.ret(call_result_s);
                }
            }
        }

        // Fallthrough: unknown instruction, return bytes unchanged
        // Not call: check IrRecordInit
        g.beginReservedBlock(blk_not_call);
        const is_record_init = try g.tagTest(inst, ir_record_init);
        const blk_record_init = g.reserveBlock();
        const blk_not_record_init = g.reserveBlock();
        try g.branch(is_record_init, blk_record_init, blk_not_record_init);

        // IrRecordInit: {dst, fields: [{name, value}]} -> bump alloc + STR each field
        g.beginReservedBlock(blk_record_init);
        {
            const ri_payload = try g.tagPayload(inst, ir_record_init);
            const ri_dst = try g.recordField(ri_payload, "dst");
            const ri_fields = try g.recordField(ri_payload, "fields");
            const ri_num_fields = try g.listLength(ri_fields);

            // Allocate register for the record pointer
            const ri_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ri_dst });
            const ri_reg_raw = try g.recordField(ri_alloc, "reg");
            const ri_ctx = try g.recordField(ri_alloc, "ctx");

            // If dst is spilled, use x16 as physical register for bump alloc + STR base
            const c100_ri = try g.constInt(100);
            const ri_spilled = try g.ge(ri_reg_raw, c100_ri);
            const blk_ri_spill = g.reserveBlock();
            const blk_ri_phys = g.reserveBlock();
            const blk_ri_merge = g.reserveBlock();
            try g.branch(ri_spilled, blk_ri_spill, blk_ri_phys);
            g.beginReservedBlock(blk_ri_spill);
            const c16_ri = try g.constInt(16);
            try g.jump(blk_ri_merge, &.{c16_ri});
            g.beginReservedBlock(blk_ri_phys);
            try g.jump(blk_ri_merge, &.{ri_reg_raw});
            g.beginReservedBlock(blk_ri_merge);
            const ri_reg = try g.addBlockParam();

            // Bump alloc: n_fields * 8 bytes
            const c8_ri = try g.constInt(8);
            const ri_size = try g.binary(.mul, ri_num_fields, c8_ri);
            const ri_bytes1 = try g.callDirect(f_emit_bump_alloc, &.{ bytes, ri_reg, ri_size });

            // STR each field value at [ri_reg, #i*8]
            const c0_ri = try g.constInt(0);
            const ri_loop = g.reserveBlock();
            try g.jump(ri_loop, &.{ c0_ri, ri_bytes1, ri_ctx });

            g.beginReservedBlock(ri_loop);
            const ri_i = try g.addBlockParam();
            const ri_b = try g.addBlockParam();
            const ri_c = try g.addBlockParam();
            const ri_done = try g.ge(ri_i, ri_num_fields);
            const ri_body = g.reserveBlock();
            const ri_exit = g.reserveBlock();
            try g.branch(ri_done, ri_exit, ri_body);

            g.beginReservedBlock(ri_body);
            {
                const ri_field = try g.listNth(ri_fields, ri_i);
                const ri_fval = try g.recordField(ri_field, "value");
                const ri_fval_reg_raw = try g.callDirect(f_get_reg, &.{ ri_c, ri_fval });

                // Load field value from spill slot if needed (use x17 as temp for field value)
                const c17_ri = try g.constInt(17);
                const ri_fval_load = try g.callDirect(f_load_spill, &.{ ri_b, ri_fval_reg_raw, c17_ri });
                const ri_b_loaded = try g.recordField(ri_fval_load, "bytes");
                const ri_fval_reg = try g.recordField(ri_fval_load, "reg");

                // STR ri_fval_reg, [ri_reg, #i*8]
                const ri_offset = try g.binary(.mul, ri_i, c8_ri);
                const ri_off_div8 = try g.binary(.div, ri_offset, c8_ri);
                const str_base = try g.constInt(0xF9000000);
                const c10_ri = try g.constInt(10);
                const c5_ri = try g.constInt(5);
                const str_off = try g.binary(.shl, ri_off_div8, c10_ri);
                const str_rn = try g.binary(.shl, ri_reg, c5_ri);
                const str_r1 = try g.binary(.bit_or, str_base, str_off);
                const str_r2 = try g.binary(.bit_or, str_r1, str_rn);
                const str_enc = try g.binary(.bit_or, str_r2, ri_fval_reg);
                const ri_b2 = try g.callDirect(f_append_inst, &.{ ri_b_loaded, str_enc });

                const one_ri = try g.constInt(1);
                const ri_next = try g.add(ri_i, one_ri);
                try g.jump(ri_loop, &.{ ri_next, ri_b2, ri_c });
            }

            g.beginReservedBlock(ri_exit);
            {
                // Store field names in fields_map for later IrFieldGet resolution
                // Build field names list
                const c0_fn = try g.constInt(0);
                const fn_list = try g.listInit(&.{});
                const fn_loop = g.reserveBlock();
                try g.jump(fn_loop, &.{ c0_fn, fn_list });

                g.beginReservedBlock(fn_loop);
                const fn_i = try g.addBlockParam();
                const fn_l = try g.addBlockParam();
                const fn_done = try g.ge(fn_i, ri_num_fields);
                const fn_body = g.reserveBlock();
                const fn_exit = g.reserveBlock();
                try g.branch(fn_done, fn_exit, fn_body);

                g.beginReservedBlock(fn_body);
                {
                    const fn_field = try g.listNth(ri_fields, fn_i);
                    const fn_name = try g.recordField(fn_field, "name");
                    const fn_l2 = try g.listAppend(fn_l, fn_name);
                    const one_fn = try g.constInt(1);
                    const fn_next = try g.add(fn_i, one_fn);
                    try g.jump(fn_loop, &.{ fn_next, fn_l2 });
                }

                g.beginReservedBlock(fn_exit);
                {
                    // Store: fields_map[dst_str] = field_names_list
                    const dst_str = try g.callBuiltin("string_from_int", &.{ri_dst});
                    const old_fm = try g.recordField(ri_c, "fields_map");
                    const new_fm = try g.mapSet(old_fm, dst_str, fn_l);
                    // Rebuild ctx with new fields_map
                    const ri_ctx_final = try g.record(&.{
                        .{ .name = "reg_map", .value = try g.recordField(ri_c, "reg_map") },
                        .{ .name = "next_reg", .value = try g.recordField(ri_c, "next_reg") },
                        .{ .name = "func_map", .value = try g.recordField(ri_c, "func_map") },
                        .{ .name = "block_offsets", .value = try g.recordField(ri_c, "block_offsets") },
                        .{ .name = "data", .value = try g.recordField(ri_c, "data") },
                        .{ .name = "data_offsets", .value = try g.recordField(ri_c, "data_offsets") },
                        .{ .name = "blocks_start", .value = try g.recordField(ri_c, "blocks_start") },
                        .{ .name = "fields_map", .value = new_fm },
                    });
                    // Store record pointer to spill slot if dst was spilled
                    const ri_b_final = try g.callDirect(f_store_spill, &.{ ri_b, ri_reg_raw, ri_reg });
                    const ri_result = try g.record(&.{
                        .{ .name = "bytes", .value = ri_b_final },
                        .{ .name = "ctx", .value = ri_ctx_final },
                    });
                    try g.ret(ri_result);
                }
            }
        }

        // Not record_init: check IrRecordUpdate
        g.beginReservedBlock(blk_not_record_init);
        const is_record_update = try g.tagTest(inst, "IrRecordUpdate");
        const blk_record_update = g.reserveBlock();
        const blk_not_record_update = g.reserveBlock();
        try g.branch(is_record_update, blk_record_update, blk_not_record_update);

        // IrRecordUpdate: {dst, base, updates: [{name, value}]}
        // Copies base record, overriding specified fields
        g.beginReservedBlock(blk_record_update);
        {
            const rup = try g.tagPayload(inst, "IrRecordUpdate");
            const ru_dst = try g.recordField(rup, "dst");
            const ru_base = try g.recordField(rup, "base");
            const ru_updates = try g.recordField(rup, "updates");

            // Look up base's fields in fields_map
            const ru_base_str = try g.callBuiltin("string_from_int", &.{ru_base});
            const ru_fm = try g.recordField(ctx, "fields_map");
            const ru_field_names = try g.mapGet(ru_fm, ru_base_str);
            const ru_num_fields = try g.listLength(ru_field_names);

            // Alloc register for dst
            const ru_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ru_dst });
            const ru_dst_reg_raw = try g.recordField(ru_alloc, "reg");
            const ru_ctx1 = try g.recordField(ru_alloc, "ctx");

            // Handle spill for dst register
            const c100_ru = try g.constInt(100);
            const ru_spilled = try g.ge(ru_dst_reg_raw, c100_ru);
            const blk_ru_spill = g.reserveBlock();
            const blk_ru_phys = g.reserveBlock();
            const blk_ru_merge = g.reserveBlock();
            try g.branch(ru_spilled, blk_ru_spill, blk_ru_phys);
            g.beginReservedBlock(blk_ru_spill);
            const c16_ru = try g.constInt(16);
            try g.jump(blk_ru_merge, &.{c16_ru});
            g.beginReservedBlock(blk_ru_phys);
            try g.jump(blk_ru_merge, &.{ru_dst_reg_raw});
            g.beginReservedBlock(blk_ru_merge);
            const ru_dst_reg = try g.addBlockParam();

            // Get base register
            const ru_base_reg_raw = try g.callDirect(f_get_reg, &.{ ru_ctx1, ru_base });
            // Load base from spill if needed
            const c17_ru = try g.constInt(17);
            const ru_base_load = try g.callDirect(f_load_spill, &.{ bytes, ru_base_reg_raw, c17_ru });
            const ru_b0 = try g.recordField(ru_base_load, "bytes");
            const ru_base_reg = try g.recordField(ru_base_load, "reg");

            // Bump alloc: num_fields * 8 bytes
            const c8_ru = try g.constInt(8);
            const ru_alloc_size = try g.binary(.mul, ru_num_fields, c8_ru);
            const ru_b1 = try g.callDirect(f_emit_bump_alloc, &.{ ru_b0, ru_dst_reg, ru_alloc_size });

            // Loop: for each field, decide whether to copy from base or use update value
            const c0_ru = try g.constInt(0);
            const ru_field_loop = g.reserveBlock();
            try g.jump(ru_field_loop, &.{ c0_ru, ru_b1, ru_ctx1 });

            g.beginReservedBlock(ru_field_loop);
            const ru_fi = try g.addBlockParam();
            const ru_fb = try g.addBlockParam();
            const ru_fc = try g.addBlockParam();
            const ru_fdone = try g.ge(ru_fi, ru_num_fields);
            const ru_fbody = g.reserveBlock();
            const ru_fexit = g.reserveBlock();
            try g.branch(ru_fdone, ru_fexit, ru_fbody);

            g.beginReservedBlock(ru_fbody);
            {
                const ru_fname = try g.listNth(ru_field_names, ru_fi);

                // Check if this field is in the update list
                const ru_num_updates = try g.listLength(ru_updates);
                const c0_ru2 = try g.constInt(0);
                const ru_upd_loop = g.reserveBlock();
                try g.jump(ru_upd_loop, &.{ c0_ru2 });

                g.beginReservedBlock(ru_upd_loop);
                const ru_ui = try g.addBlockParam();
                const ru_udone = try g.ge(ru_ui, ru_num_updates);
                const ru_ubody = g.reserveBlock();
                const ru_unot_found = g.reserveBlock();
                try g.branch(ru_udone, ru_unot_found, ru_ubody);

                g.beginReservedBlock(ru_ubody);
                {
                    const ru_upd = try g.listNth(ru_updates, ru_ui);
                    const ru_uname = try g.recordField(ru_upd, "name");
                    const ru_match = try g.eq(ru_uname, ru_fname);
                    const ru_found = g.reserveBlock();
                    const ru_unext_blk = g.reserveBlock();
                    try g.branch(ru_match, ru_found, ru_unext_blk);

                    // Found update: use update value's register
                    g.beginReservedBlock(ru_found);
                    {
                        const ru_uval = try g.recordField(ru_upd, "value");
                        const ru_uval_reg_raw = try g.callDirect(f_get_reg, &.{ ru_fc, ru_uval });
                        // Load from spill if needed
                        const ru_uval_load = try g.callDirect(f_load_spill, &.{ ru_fb, ru_uval_reg_raw, c17_ru });
                        const ru_fb_u = try g.recordField(ru_uval_load, "bytes");
                        const ru_uval_reg = try g.recordField(ru_uval_load, "reg");

                        // STR ru_uval_reg, [ru_dst_reg, #fi*8]
                        const ru_offset = try g.binary(.mul, ru_fi, c8_ru);
                        const ru_off_d8 = try g.binary(.div, ru_offset, c8_ru);
                        const str_base_ru = try g.constInt(0xF9000000);
                        const c10_ru = try g.constInt(10);
                        const c5_ru = try g.constInt(5);
                        const str_off_ru = try g.binary(.shl, ru_off_d8, c10_ru);
                        const str_rn_ru = try g.binary(.shl, ru_dst_reg, c5_ru);
                        const str_r1_ru = try g.binary(.bit_or, str_base_ru, str_off_ru);
                        const str_r2_ru = try g.binary(.bit_or, str_r1_ru, str_rn_ru);
                        const str_enc_ru = try g.binary(.bit_or, str_r2_ru, ru_uval_reg);
                        const ru_fb_u2 = try g.callDirect(f_append_inst, &.{ ru_fb_u, str_enc_ru });

                        const one_ru = try g.constInt(1);
                        const ru_fi_next = try g.add(ru_fi, one_ru);
                        try g.jump(ru_field_loop, &.{ ru_fi_next, ru_fb_u2, ru_fc });
                    }

                    // Not this update, continue searching
                    g.beginReservedBlock(ru_unext_blk);
                    {
                        const one_ru2 = try g.constInt(1);
                        const ru_ui_next = try g.add(ru_ui, one_ru2);
                        try g.jump(ru_upd_loop, &.{ru_ui_next});
                    }
                }

                // Field not in updates: copy from base record (LDR + STR)
                g.beginReservedBlock(ru_unot_found);
                {
                    // LDR x17, [base_reg, #fi*8] — load from base
                    const ru_offset2 = try g.binary(.mul, ru_fi, c8_ru);
                    const ru_off2_d8 = try g.binary(.div, ru_offset2, c8_ru);
                    const ldr_base_ru = try g.constInt(0xF9400000);
                    const c10_ru2 = try g.constInt(10);
                    const c5_ru2 = try g.constInt(5);
                    const ldr_off_ru = try g.binary(.shl, ru_off2_d8, c10_ru2);
                    const ldr_rn_ru = try g.binary(.shl, ru_base_reg, c5_ru2);
                    const ldr_r1_ru = try g.binary(.bit_or, ldr_base_ru, ldr_off_ru);
                    const ldr_r2_ru = try g.binary(.bit_or, ldr_r1_ru, ldr_rn_ru);
                    const ldr_enc_ru = try g.binary(.bit_or, ldr_r2_ru, c17_ru);
                    const ru_fb_c1 = try g.callDirect(f_append_inst, &.{ ru_fb, ldr_enc_ru });

                    // STR x17, [dst_reg, #fi*8]
                    const str_base_ru2 = try g.constInt(0xF9000000);
                    const str_off_ru2 = try g.binary(.shl, ru_off2_d8, c10_ru2);
                    const str_rn_ru2 = try g.binary(.shl, ru_dst_reg, c5_ru2);
                    const str_r1_ru2 = try g.binary(.bit_or, str_base_ru2, str_off_ru2);
                    const str_r2_ru2 = try g.binary(.bit_or, str_r1_ru2, str_rn_ru2);
                    const str_enc_ru2 = try g.binary(.bit_or, str_r2_ru2, c17_ru);
                    const ru_fb_c2 = try g.callDirect(f_append_inst, &.{ ru_fb_c1, str_enc_ru2 });

                    const one_ru3 = try g.constInt(1);
                    const ru_fi_next2 = try g.add(ru_fi, one_ru3);
                    try g.jump(ru_field_loop, &.{ ru_fi_next2, ru_fb_c2, ru_fc });
                }
            }

            g.beginReservedBlock(ru_fexit);
            {
                // Update fields_map: new dst has same field names as base
                const ru_dst_str = try g.callBuiltin("string_from_int", &.{ru_dst});
                const old_fm_ru = try g.recordField(ru_fc, "fields_map");
                const new_fm_ru = try g.mapSet(old_fm_ru, ru_dst_str, ru_field_names);
                const ru_ctx_final = try g.record(&.{
                    .{ .name = "reg_map", .value = try g.recordField(ru_fc, "reg_map") },
                    .{ .name = "next_reg", .value = try g.recordField(ru_fc, "next_reg") },
                    .{ .name = "func_map", .value = try g.recordField(ru_fc, "func_map") },
                    .{ .name = "block_offsets", .value = try g.recordField(ru_fc, "block_offsets") },
                    .{ .name = "data", .value = try g.recordField(ru_fc, "data") },
                    .{ .name = "data_offsets", .value = try g.recordField(ru_fc, "data_offsets") },
                    .{ .name = "blocks_start", .value = try g.recordField(ru_fc, "blocks_start") },
                    .{ .name = "fields_map", .value = new_fm_ru },
                });
                // Store dst to spill if needed
                const ru_b_final = try g.callDirect(f_store_spill, &.{ ru_fb, ru_dst_reg_raw, ru_dst_reg });
                try g.ret(try g.record(&.{
                    .{ .name = "bytes", .value = ru_b_final },
                    .{ .name = "ctx", .value = ru_ctx_final },
                }));
            }
        }

        // Not record_update: check IrFieldGet
        g.beginReservedBlock(blk_not_record_update);
        const is_field_get = try g.tagTest(inst, ir_field_get);
        const blk_field_get = g.reserveBlock();
        const blk_not_field_get = g.reserveBlock();
        try g.branch(is_field_get, blk_field_get, blk_not_field_get);

        // IrFieldGet: {dst, base, field, index} -> LDR dst, [base, #index*8]
        g.beginReservedBlock(blk_field_get);
        {
            const fg_payload = try g.tagPayload(inst, ir_field_get);
            const fg_dst = try g.recordField(fg_payload, "dst");
            const fg_base = try g.recordField(fg_payload, "base");
            const fg_field = try g.recordField(fg_payload, "field");
            const fg_index = try g.recordField(fg_payload, "index");

            // Check if base is in fields_map
            const fg_base_str = try g.callBuiltin("string_from_int", &.{fg_base});
            const fg_fm = try g.recordField(ctx, "fields_map");
            const fg_has = try g.mapHas(fg_fm, fg_base_str);
            const blk_fg_has_map = g.reserveBlock();
            const blk_fg_no_map = g.reserveBlock();
            try g.branch(fg_has, blk_fg_has_map, blk_fg_no_map);

            // Has fields_map entry: find field index by name
            g.beginReservedBlock(blk_fg_has_map);
            {
                const fg_names = try g.mapGet(fg_fm, fg_base_str);
                const fg_num = try g.listLength(fg_names);
                const c0_fg = try g.constInt(0);
                const fg_find = g.reserveBlock();
                try g.jump(fg_find, &.{c0_fg});

                g.beginReservedBlock(fg_find);
                const fg_fi = try g.addBlockParam();
                const fg_fi_done = try g.ge(fg_fi, fg_num);
                const fg_not_found = g.reserveBlock();
                const fg_check = g.reserveBlock();
                try g.branch(fg_fi_done, fg_not_found, fg_check);

                g.beginReservedBlock(fg_check);
                {
                    const fg_name_i = try g.listNth(fg_names, fg_fi);
                    const fg_match = try g.eq(fg_name_i, fg_field);
                    const fg_found = g.reserveBlock();
                    const fg_next_blk = g.reserveBlock();
                    try g.branch(fg_match, fg_found, fg_next_blk);

                    g.beginReservedBlock(fg_found);
                    {
                        const fg_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, fg_dst });
                        const fg_reg_raw = try g.recordField(fg_alloc, "reg");
                        const fg_ctx = try g.recordField(fg_alloc, "ctx");
                        const fg_base_reg_raw = try g.callDirect(f_get_reg, &.{ fg_ctx, fg_base });

                        // Load base from spill if needed
                        const c17_fg = try g.constInt(17);
                        const fg_base_load = try g.callDirect(f_load_spill, &.{ bytes, fg_base_reg_raw, c17_fg });
                        const fg_b1 = try g.recordField(fg_base_load, "bytes");
                        const fg_base_reg = try g.recordField(fg_base_load, "reg");

                        // Use x27 as dst if spilled
                        const c100_fg = try g.constInt(100);
                        const fg_dst_spilled = try g.ge(fg_reg_raw, c100_fg);
                        const blk_fg_sp = g.reserveBlock();
                        const blk_fg_ph = g.reserveBlock();
                        const blk_fg_dm = g.reserveBlock();
                        try g.branch(fg_dst_spilled, blk_fg_sp, blk_fg_ph);
                        g.beginReservedBlock(blk_fg_sp);
                        const c16_fg = try g.constInt(16);
                        try g.jump(blk_fg_dm, &.{c16_fg});
                        g.beginReservedBlock(blk_fg_ph);
                        try g.jump(blk_fg_dm, &.{fg_reg_raw});
                        g.beginReservedBlock(blk_fg_dm);
                        const fg_reg = try g.addBlockParam();

                        const ldr_base = try g.constInt(0xF9400000);
                        const c10_fg = try g.constInt(10);
                        const c5_fg = try g.constInt(5);
                        const ldr_off = try g.binary(.shl, fg_fi, c10_fg);
                        const ldr_rn = try g.binary(.shl, fg_base_reg, c5_fg);
                        const ldr_r1 = try g.binary(.bit_or, ldr_base, ldr_off);
                        const ldr_r2 = try g.binary(.bit_or, ldr_r1, ldr_rn);
                        const ldr_enc = try g.binary(.bit_or, ldr_r2, fg_reg);
                        const fg_bytes = try g.callDirect(f_append_inst, &.{ fg_b1, ldr_enc });

                        // Store dst to spill if needed
                        const fg_bytes_final = try g.callDirect(f_store_spill, &.{ fg_bytes, fg_reg_raw, fg_reg });
                        const fg_result = try g.record(&.{
                            .{ .name = "bytes", .value = fg_bytes_final },
                            .{ .name = "ctx", .value = fg_ctx },
                        });
                        try g.ret(fg_result);
                    }

                    g.beginReservedBlock(fg_next_blk);
                    {
                        const one_fg = try g.constInt(1);
                        const fg_next = try g.add(fg_fi, one_fg);
                        try g.jump(fg_find, &.{fg_next});
                    }
                }

                // Field not found in names list: use index from payload, fallback to 0
                g.beginReservedBlock(fg_not_found);
                {
                    // Use fg_index from payload if >= 0, else default to 0
                    const neg_one_fb = try g.constInt(-1);
                    const has_idx_fb = try g.binary(.ne, fg_index, neg_one_fb);
                    const blk_use_idx_fb = g.reserveBlock();
                    const blk_use_zero_fb = g.reserveBlock();
                    const blk_idx_merge_fb = g.reserveBlock();
                    try g.branch(has_idx_fb, blk_use_idx_fb, blk_use_zero_fb);
                    g.beginReservedBlock(blk_use_idx_fb);
                    try g.jump(blk_idx_merge_fb, &.{fg_index});
                    g.beginReservedBlock(blk_use_zero_fb);
                    const c0_idx_fb = try g.constInt(0);
                    try g.jump(blk_idx_merge_fb, &.{c0_idx_fb});
                    g.beginReservedBlock(blk_idx_merge_fb);
                    const resolved_idx_fb = try g.addBlockParam();

                    const fg_alloc2 = try g.callDirect(f_alloc_reg, &.{ ctx, fg_dst });
                    const fg_reg2_raw = try g.recordField(fg_alloc2, "reg");
                    const fg_ctx2 = try g.recordField(fg_alloc2, "ctx");
                    const fg_base_reg2_raw = try g.callDirect(f_get_reg, &.{ fg_ctx2, fg_base });

                    const c17_fb = try g.constInt(17);
                    const fg_base_load2 = try g.callDirect(f_load_spill, &.{ bytes, fg_base_reg2_raw, c17_fb });
                    const fg_b2 = try g.recordField(fg_base_load2, "bytes");
                    const fg_base_reg2 = try g.recordField(fg_base_load2, "reg");

                    const c100_fb = try g.constInt(100);
                    const fg_dst_sp2 = try g.ge(fg_reg2_raw, c100_fb);
                    const blk_fg_sp2 = g.reserveBlock();
                    const blk_fg_ph2 = g.reserveBlock();
                    const blk_fg_dm2 = g.reserveBlock();
                    try g.branch(fg_dst_sp2, blk_fg_sp2, blk_fg_ph2);
                    g.beginReservedBlock(blk_fg_sp2);
                    const c16_fb = try g.constInt(16);
                    try g.jump(blk_fg_dm2, &.{c16_fb});
                    g.beginReservedBlock(blk_fg_ph2);
                    try g.jump(blk_fg_dm2, &.{fg_reg2_raw});
                    g.beginReservedBlock(blk_fg_dm2);
                    const fg_reg2 = try g.addBlockParam();

                    // LDR dst, [base, #resolved_idx*8] — use resolved_idx for offset
                    const ldr_base2 = try g.constInt(0xF9400000);
                    const c10_fb = try g.constInt(10);
                    const c5_fb = try g.constInt(5);
                    const ldr_off2 = try g.binary(.shl, resolved_idx_fb, c10_fb);
                    const ldr_rn2 = try g.binary(.shl, fg_base_reg2, c5_fb);
                    const ldr_r1b = try g.binary(.bit_or, ldr_base2, ldr_off2);
                    const ldr_r2b = try g.binary(.bit_or, ldr_r1b, ldr_rn2);
                    const ldr_enc2 = try g.binary(.bit_or, ldr_r2b, fg_reg2);
                    const fg_bytes2 = try g.callDirect(f_append_inst, &.{ fg_b2, ldr_enc2 });
                    const fg_bytes2_final = try g.callDirect(f_store_spill, &.{ fg_bytes2, fg_reg2_raw, fg_reg2 });
                    const fg_result2 = try g.record(&.{
                        .{ .name = "bytes", .value = fg_bytes2_final },
                        .{ .name = "ctx", .value = fg_ctx2 },
                    });
                    try g.ret(fg_result2);
                }
            }

            // No fields_map entry (cross-function): use index from payload, fallback to 0
            g.beginReservedBlock(blk_fg_no_map);
            {
                // Use fg_index from payload if >= 0, else default to 0
                const neg_one_c = try g.constInt(-1);
                const has_idx = try g.binary(.ne, fg_index, neg_one_c);
                const blk_use_idx = g.reserveBlock();
                const blk_use_zero = g.reserveBlock();
                const blk_idx_merge = g.reserveBlock();
                try g.branch(has_idx, blk_use_idx, blk_use_zero);
                g.beginReservedBlock(blk_use_idx);
                try g.jump(blk_idx_merge, &.{fg_index});
                g.beginReservedBlock(blk_use_zero);
                const c0_idx = try g.constInt(0);
                try g.jump(blk_idx_merge, &.{c0_idx});
                g.beginReservedBlock(blk_idx_merge);
                const resolved_idx = try g.addBlockParam();

                const fg_alloc3 = try g.callDirect(f_alloc_reg, &.{ ctx, fg_dst });
                const fg_reg3_raw = try g.recordField(fg_alloc3, "reg");
                const fg_ctx3 = try g.recordField(fg_alloc3, "ctx");
                const fg_base_reg3_raw = try g.callDirect(f_get_reg, &.{ fg_ctx3, fg_base });

                const c17_nm = try g.constInt(17);
                const fg_base_load3 = try g.callDirect(f_load_spill, &.{ bytes, fg_base_reg3_raw, c17_nm });
                const fg_b3 = try g.recordField(fg_base_load3, "bytes");
                const fg_base_reg3 = try g.recordField(fg_base_load3, "reg");

                const c100_nm = try g.constInt(100);
                const fg_dst_sp3 = try g.ge(fg_reg3_raw, c100_nm);
                const blk_fg_sp3 = g.reserveBlock();
                const blk_fg_ph3 = g.reserveBlock();
                const blk_fg_dm3 = g.reserveBlock();
                try g.branch(fg_dst_sp3, blk_fg_sp3, blk_fg_ph3);
                g.beginReservedBlock(blk_fg_sp3);
                const c16_nm = try g.constInt(16);
                try g.jump(blk_fg_dm3, &.{c16_nm});
                g.beginReservedBlock(blk_fg_ph3);
                try g.jump(blk_fg_dm3, &.{fg_reg3_raw});
                g.beginReservedBlock(blk_fg_dm3);
                const fg_reg3 = try g.addBlockParam();

                // LDR dst, [base, #resolved_idx*8] — use resolved_idx for offset
                const ldr_base3 = try g.constInt(0xF9400000);
                const c10_nm = try g.constInt(10);
                const c5_nm = try g.constInt(5);
                const ldr_off3 = try g.binary(.shl, resolved_idx, c10_nm);
                const ldr_rn3 = try g.binary(.shl, fg_base_reg3, c5_nm);
                const ldr_r1c = try g.binary(.bit_or, ldr_base3, ldr_off3);
                const ldr_r2c = try g.binary(.bit_or, ldr_r1c, ldr_rn3);
                const ldr_enc3 = try g.binary(.bit_or, ldr_r2c, fg_reg3);
                const fg_bytes3 = try g.callDirect(f_append_inst, &.{ fg_b3, ldr_enc3 });
                const fg_bytes3_final = try g.callDirect(f_store_spill, &.{ fg_bytes3, fg_reg3_raw, fg_reg3 });
                const fg_result3 = try g.record(&.{
                    .{ .name = "bytes", .value = fg_bytes3_final },
                    .{ .name = "ctx", .value = fg_ctx3 },
                });
                try g.ret(fg_result3);
            }
        }

        // Not field_get: check IrConstString
        g.beginReservedBlock(blk_not_field_get);
        const is_const_string = try g.tagTest(inst, ir_const_string);
        const blk_const_string = g.reserveBlock();
        const blk_not_const_string = g.reserveBlock();
        try g.branch(is_const_string, blk_const_string, blk_not_const_string);

        // IrConstString: {dst, value} -> heap-alloc string data + descriptor
        // String layout: data = packed bytes on heap, descriptor = {ptr, len} (16 bytes)
        // dst register points to the descriptor
        g.beginReservedBlock(blk_const_string);
        {
            const cs_payload = try g.tagPayload(inst, ir_const_string);
            const cs_dst = try g.recordField(cs_payload, "dst");
            const cs_str = try g.recordField(cs_payload, "value");

            // Alloc register for dst
            const cs_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, cs_dst });
            const cs_reg_raw = try g.recordField(cs_alloc, "reg");
            const cs_ctx = try g.recordField(cs_alloc, "ctx");

            // Handle spill: if spilled, use x16 as physical register
            const c100_cs = try g.constInt(100);
            const cs_spilled = try g.ge(cs_reg_raw, c100_cs);
            const blk_cs_spill = g.reserveBlock();
            const blk_cs_phys = g.reserveBlock();
            const blk_cs_merge = g.reserveBlock();
            try g.branch(cs_spilled, blk_cs_spill, blk_cs_phys);
            g.beginReservedBlock(blk_cs_spill);
            const c16_spill_cs = try g.constInt(16);
            try g.jump(blk_cs_merge, &.{c16_spill_cs});
            g.beginReservedBlock(blk_cs_phys);
            try g.jump(blk_cs_merge, &.{cs_reg_raw});
            g.beginReservedBlock(blk_cs_merge);
            const cs_reg = try g.addBlockParam();
            // x16 as temp register for string data packing (always accessible)
            const c16_cs = try g.constInt(16);

            const cs_len = try g.callBuiltin("string_length", &.{cs_str});
            const c8_cs = try g.constInt(8);
            const c7_cs = try g.constInt(7);
            const c0_cs = try g.constInt(0);

            // Round up to multiple of 8 for data allocation
            const cs_len_plus7 = try g.add(cs_len, c7_cs);
            const cs_data_size = try g.binary(.div, cs_len_plus7, c8_cs);
            const cs_data_bytes = try g.binary(.mul, cs_data_size, c8_cs);

            // Bump-alloc data bytes: x17 = data pointer
            const c17_cs = try g.constInt(17);
            const cs_b1 = try g.callDirect(f_emit_bump_alloc, &.{ bytes, c17_cs, cs_data_bytes });

            // Loop: pack and store each 8-byte chunk
            const cs_chunk_loop = g.reserveBlock();
            try g.jump(cs_chunk_loop, &.{ c0_cs, cs_b1 });

            g.beginReservedBlock(cs_chunk_loop);
            const cs_ci = try g.addBlockParam(); // chunk index (0, 1, 2, ...)
            const cs_cb = try g.addBlockParam(); // bytes buffer
            const cs_ci_done = try g.ge(cs_ci, cs_data_size);
            const cs_chunk_body = g.reserveBlock();
            const cs_chunk_exit = g.reserveBlock();
            try g.branch(cs_ci_done, cs_chunk_exit, cs_chunk_body);

            g.beginReservedBlock(cs_chunk_body);
            {
                // Pack up to 8 bytes starting at cs_ci * 8
                const cs_base_idx = try g.binary(.mul, cs_ci, c8_cs);
                // Inner loop: pack bytes into a 64-bit value
                const cs_pack_loop = g.reserveBlock();
                try g.jump(cs_pack_loop, &.{ c0_cs, c0_cs }); // (byte_i_within_chunk, accum)

                g.beginReservedBlock(cs_pack_loop);
                const cs_bi = try g.addBlockParam(); // byte index within chunk (0..7)
                const cs_accum = try g.addBlockParam(); // accumulated 64-bit value
                const cs_bi_done_val = try g.ge(cs_bi, c8_cs);
                const cs_pack_body = g.reserveBlock();
                const cs_pack_exit = g.reserveBlock();
                try g.branch(cs_bi_done_val, cs_pack_exit, cs_pack_body);

                g.beginReservedBlock(cs_pack_body);
                {
                    const cs_abs_idx = try g.add(cs_base_idx, cs_bi);
                    // Check if abs_idx < len (don't read past end)
                    const cs_in_bounds = try g.lt(cs_abs_idx, cs_len);
                    const cs_read_byte = g.reserveBlock();
                    const cs_zero_byte = g.reserveBlock();
                    const cs_byte_merge = g.reserveBlock();
                    try g.branch(cs_in_bounds, cs_read_byte, cs_zero_byte);

                    g.beginReservedBlock(cs_read_byte);
                    const cs_byte_val = try g.callBuiltin("string_byte_at", &.{ cs_str, cs_abs_idx });
                    try g.jump(cs_byte_merge, &.{cs_byte_val});

                    g.beginReservedBlock(cs_zero_byte);
                    try g.jump(cs_byte_merge, &.{c0_cs});

                    g.beginReservedBlock(cs_byte_merge);
                    const cs_byte = try g.addBlockParam();
                    // Shift byte to position: byte << (bi * 8)
                    const cs_shift = try g.binary(.mul, cs_bi, c8_cs);
                    const cs_shifted = try g.binary(.shl, cs_byte, cs_shift);
                    const cs_new_accum = try g.binary(.bit_or, cs_accum, cs_shifted);
                    const c1_cs = try g.constInt(1);
                    const cs_bi_next = try g.add(cs_bi, c1_cs);
                    try g.jump(cs_pack_loop, &.{ cs_bi_next, cs_new_accum });
                }

                g.beginReservedBlock(cs_pack_exit);
                {
                    // cs_accum has the packed 64-bit value, store via x16
                    // MOV x16, packed_value
                    const cs_cb2 = try g.callDirect(f_mov_imm64, &.{ cs_cb, c16_cs, cs_accum });
                    // STR x16, [x17, #ci*8]
                    const cs_store_off = try g.binary(.mul, cs_ci, c8_cs);
                    const cs_store_off_d8 = try g.binary(.div, cs_store_off, c8_cs);
                    const str_base_cs = try g.constInt(0xF9000000);
                    const c10_cs = try g.constInt(10);
                    const c5_cs = try g.constInt(5);
                    const str_off_cs = try g.binary(.shl, cs_store_off_d8, c10_cs);
                    const str_rn_cs = try g.binary(.shl, c17_cs, c5_cs);
                    const str_r1_cs = try g.binary(.bit_or, str_base_cs, str_off_cs);
                    const str_r2_cs = try g.binary(.bit_or, str_r1_cs, str_rn_cs);
                    const str_enc_cs = try g.binary(.bit_or, str_r2_cs, c16_cs);
                    const cs_cb3 = try g.callDirect(f_append_inst, &.{ cs_cb2, str_enc_cs });

                    const c1_cs2 = try g.constInt(1);
                    const cs_ci_next = try g.add(cs_ci, c1_cs2);
                    try g.jump(cs_chunk_loop, &.{ cs_ci_next, cs_cb3 });
                }
            }

            g.beginReservedBlock(cs_chunk_exit);
            {
                // Data is stored on heap at x17. Now alloc descriptor (16 bytes).
                const c16_desc = try g.constInt(16);
                const cs_cb_desc = try g.callDirect(f_emit_bump_alloc, &.{ cs_cb, cs_reg, c16_desc });

                // STR x17, [cs_reg, #0]  — store data pointer
                const str_base_d = try g.constInt(0xF9000000);
                const c5_d = try g.constInt(5);
                const str_rn_d = try g.binary(.shl, cs_reg, c5_d);
                const str_r1_d = try g.binary(.bit_or, str_base_d, str_rn_d);
                const str_enc_d = try g.binary(.bit_or, str_r1_d, c17_cs);
                const cs_cb_d1 = try g.callDirect(f_append_inst, &.{ cs_cb_desc, str_enc_d });

                // MOV x17, len; STR x17, [cs_reg, #8]  — store length
                const cs_cb_d2 = try g.callDirect(f_mov_imm64, &.{ cs_cb_d1, c17_cs, cs_len });
                const c10_d = try g.constInt(10);
                const c1_off = try g.constInt(1); // offset/8 = 1 for #8
                const str_off_d = try g.binary(.shl, c1_off, c10_d);
                const str_r1_d2 = try g.binary(.bit_or, str_base_d, str_off_d);
                const str_r2_d2 = try g.binary(.bit_or, str_r1_d2, str_rn_d);
                const str_enc_d2 = try g.binary(.bit_or, str_r2_d2, c17_cs);
                const cs_cb_d3 = try g.callDirect(f_append_inst, &.{ cs_cb_d2, str_enc_d2 });

                // Store to spill if needed
                const cs_b_final = try g.callDirect(f_store_spill, &.{ cs_cb_d3, cs_reg_raw, cs_reg });

                // Update fields_map: string descriptor has fields "ptr" and "len"
                const cs_ptr_str = try g.constString("ptr");
                const cs_len_str = try g.constString("len");
                const cs_field_names = try g.listInit(&.{ cs_ptr_str, cs_len_str });
                const cs_dst_str = try g.callBuiltin("string_from_int", &.{cs_dst});
                const cs_old_fm = try g.recordField(cs_ctx, "fields_map");
                const cs_new_fm = try g.mapSet(cs_old_fm, cs_dst_str, cs_field_names);
                const cs_ctx_final = try g.record(&.{
                    .{ .name = "reg_map", .value = try g.recordField(cs_ctx, "reg_map") },
                    .{ .name = "next_reg", .value = try g.recordField(cs_ctx, "next_reg") },
                    .{ .name = "func_map", .value = try g.recordField(cs_ctx, "func_map") },
                    .{ .name = "block_offsets", .value = try g.recordField(cs_ctx, "block_offsets") },
                    .{ .name = "data", .value = try g.recordField(cs_ctx, "data") },
                    .{ .name = "data_offsets", .value = try g.recordField(cs_ctx, "data_offsets") },
                    .{ .name = "blocks_start", .value = try g.recordField(cs_ctx, "blocks_start") },
                    .{ .name = "fields_map", .value = cs_new_fm },
                });

                try g.ret(try g.record(&.{
                    .{ .name = "bytes", .value = cs_b_final },
                    .{ .name = "ctx", .value = cs_ctx_final },
                }));
            }
        }

        // Not const_string: check IrClosure
        g.beginReservedBlock(blk_not_const_string);
        const is_closure = try g.tagTest(inst, ir_closure);
        const blk_closure = g.reserveBlock();
        const blk_not_closure = g.reserveBlock();
        try g.branch(is_closure, blk_closure, blk_not_closure);

        // IrClosure: {dst, func} -> look up func in func_map, load offset into dst
        g.beginReservedBlock(blk_closure);
        {
            const cl_payload = try g.tagPayload(inst, ir_closure);
            const cl_dst = try g.recordField(cl_payload, "dst");
            const cl_func = try g.recordField(cl_payload, "func");
            const cl_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, cl_dst });
            const cl_reg_raw = try g.recordField(cl_alloc, "reg");
            const cl_ctx = try g.recordField(cl_alloc, "ctx");

            // If dst is spilled, use x16 as temp register for ADR/MOV
            const c100_cl = try g.constInt(100);
            const cl_spilled = try g.ge(cl_reg_raw, c100_cl);
            const blk_cl_spill = g.reserveBlock();
            const blk_cl_phys = g.reserveBlock();
            const blk_cl_reg_merge = g.reserveBlock();
            try g.branch(cl_spilled, blk_cl_spill, blk_cl_phys);
            g.beginReservedBlock(blk_cl_spill);
            const c16_cl = try g.constInt(16);
            try g.jump(blk_cl_reg_merge, &.{c16_cl});
            g.beginReservedBlock(blk_cl_phys);
            try g.jump(blk_cl_reg_merge, &.{cl_reg_raw});
            g.beginReservedBlock(blk_cl_reg_merge);
            const cl_reg = try g.addBlockParam();

            const cl_fmap = try g.recordField(cl_ctx, "func_map");
            const cl_has = try g.mapHas(cl_fmap, cl_func);
            const blk_cl_found = g.reserveBlock();
            const blk_cl_notfound = g.reserveBlock();
            try g.branch(cl_has, blk_cl_found, blk_cl_notfound);

            g.beginReservedBlock(blk_cl_found);
            {
                const cl_off = try g.mapGet(cl_fmap, cl_func);
                const cl_cur_off = try g.callBuiltin("bytes_length", &.{bytes});
                const cl_rel = try g.sub(cl_off, cl_cur_off);
                const cl_adr = try g.callDirect(f_encode_adr, &.{ cl_reg, cl_rel });
                const cl_bytes = try g.callDirect(f_append_inst, &.{ bytes, cl_adr });
                // Store to spill slot if needed
                const cl_bytes_final = try g.callDirect(f_store_spill, &.{ cl_bytes, cl_reg_raw, cl_reg });
                const cl_result = try g.record(&.{
                    .{ .name = "bytes", .value = cl_bytes_final },
                    .{ .name = "ctx", .value = cl_ctx },
                });
                try g.ret(cl_result);
            }

            g.beginReservedBlock(blk_cl_notfound);
            {
                const cl_zero = try g.constInt(0);
                const cl_bytes2 = try g.callDirect(f_mov_imm64, &.{ bytes, cl_reg, cl_zero });
                // Store to spill slot if needed
                const cl_bytes2_final = try g.callDirect(f_store_spill, &.{ cl_bytes2, cl_reg_raw, cl_reg });
                const cl_result2 = try g.record(&.{
                    .{ .name = "bytes", .value = cl_bytes2_final },
                    .{ .name = "ctx", .value = cl_ctx },
                });
                try g.ret(cl_result2);
            }
        }

        // Not closure: check IrListInit
        g.beginReservedBlock(blk_not_closure);
        const is_list_init = try g.tagTest(inst, ir_list_init);
        const blk_list_init = g.reserveBlock();
        const blk_not_list_init = g.reserveBlock();
        try g.branch(is_list_init, blk_list_init, blk_not_list_init);

        // IrListInit: {dst, elements} -> bump alloc (1+n)*8 bytes, store length + elements
        g.beginReservedBlock(blk_list_init);
        {
            const li_payload = try g.tagPayload(inst, ir_list_init);
            const li_dst = try g.recordField(li_payload, "dst");
            const li_elems = try g.recordField(li_payload, "elements");
            const li_num = try g.listLength(li_elems);

            const li_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, li_dst });
            const li_reg_raw = try g.recordField(li_alloc, "reg");
            const li_ctx = try g.recordField(li_alloc, "ctx");

            // If dst is spilled, use x16 as physical register
            const c100_li = try g.constInt(100);
            const li_spilled = try g.ge(li_reg_raw, c100_li);
            const blk_li_sp = g.reserveBlock();
            const blk_li_ph = g.reserveBlock();
            const blk_li_mg = g.reserveBlock();
            try g.branch(li_spilled, blk_li_sp, blk_li_ph);
            g.beginReservedBlock(blk_li_sp);
            const c16_li = try g.constInt(16);
            try g.jump(blk_li_mg, &.{c16_li});
            g.beginReservedBlock(blk_li_ph);
            try g.jump(blk_li_mg, &.{li_reg_raw});
            g.beginReservedBlock(blk_li_mg);
            const li_reg = try g.addBlockParam();

            // Bump alloc: (1 + n) * 8 bytes (slot 0 = length, slots 1..n = elements)
            const c1_li = try g.constInt(1);
            const li_slots = try g.add(li_num, c1_li);
            const c8_li = try g.constInt(8);
            const li_size = try g.binary(.mul, li_slots, c8_li);
            const li_bytes1 = try g.callDirect(f_emit_bump_alloc, &.{ bytes, li_reg, li_size });

            // Store length at offset 0
            const li_len_reg = try g.constInt(17); // use x17 as temp for length
            const li_ctx2 = li_ctx;
            const li_bytes2 = try g.callDirect(f_mov_imm64, &.{ li_bytes1, li_len_reg, li_num });
            const c0_li = try g.constInt(0);
            const li_str_len = try g.callDirect(f_encode_str, &.{ li_len_reg, li_reg, c0_li });
            const li_bytes3 = try g.callDirect(f_append_inst, &.{ li_bytes2, li_str_len });

            // STR each element at [li_reg, #(i+1)*8]
            const li_elem_loop = g.reserveBlock();
            try g.jump(li_elem_loop, &.{ c0_li, li_bytes3, li_ctx2 });

            g.beginReservedBlock(li_elem_loop);
            const li_ei = try g.addBlockParam();
            const li_eb = try g.addBlockParam();
            const li_ec = try g.addBlockParam();
            const li_edone = try g.ge(li_ei, li_num);
            const li_ebody = g.reserveBlock();
            const li_eexit = g.reserveBlock();
            try g.branch(li_edone, li_eexit, li_ebody);

            g.beginReservedBlock(li_ebody);
            {
                const li_elem = try g.listNth(li_elems, li_ei);
                const li_elem_reg_raw = try g.callDirect(f_get_reg, &.{ li_ec, li_elem });
                // Load element from spill if needed (use x17 as temp)
                const c17_li = try g.constInt(17);
                const li_elem_load = try g.callDirect(f_load_spill, &.{ li_eb, li_elem_reg_raw, c17_li });
                const li_eb_loaded = try g.recordField(li_elem_load, "bytes");
                const li_elem_reg = try g.recordField(li_elem_load, "reg");

                const c1_ei = try g.constInt(1);
                const li_slot = try g.add(li_ei, c1_ei);
                const li_str_elem = try g.callDirect(f_encode_str, &.{ li_elem_reg, li_reg, li_slot });
                const li_eb2 = try g.callDirect(f_append_inst, &.{ li_eb_loaded, li_str_elem });
                const li_next_ei = try g.add(li_ei, c1_ei);
                try g.jump(li_elem_loop, &.{ li_next_ei, li_eb2, li_ec });
            }

            g.beginReservedBlock(li_eexit);
            {
                // Store list pointer to spill slot if needed
                const li_b_final = try g.callDirect(f_store_spill, &.{ li_eb, li_reg_raw, li_reg });
                const li_result = try g.record(&.{
                    .{ .name = "bytes", .value = li_b_final },
                    .{ .name = "ctx", .value = li_ec },
                });
                try g.ret(li_result);
            }
        }

        // Not list_init: check IrTagInit
        g.beginReservedBlock(blk_not_list_init);
        const is_tag_init = try g.tagTest(inst, ir_tag_init);
        const blk_tag_init = g.reserveBlock();
        const blk_not_tag_init = g.reserveBlock();
        try g.branch(is_tag_init, blk_tag_init, blk_not_tag_init);

        // IrTagInit: {dst, tag, payload} -> bump alloc 16 bytes, store [tag_hash, payload]
        g.beginReservedBlock(blk_tag_init);
        {
            const ti_payload = try g.tagPayload(inst, ir_tag_init);
            const ti_dst = try g.recordField(ti_payload, "dst");
            const ti_tag = try g.recordField(ti_payload, "tag");
            const ti_pl_val = try g.recordField(ti_payload, "payload");

            const ti_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ti_dst });
            const ti_reg_raw = try g.recordField(ti_alloc, "reg");
            const ti_ctx = try g.recordField(ti_alloc, "ctx");

            // Spill merge for dst: use x16 if spilled
            const c100_ti = try g.constInt(100);
            const ti_spilled = try g.ge(ti_reg_raw, c100_ti);
            const blk_ti_sp = g.reserveBlock();
            const blk_ti_ph = g.reserveBlock();
            const blk_ti_mg = g.reserveBlock();
            try g.branch(ti_spilled, blk_ti_sp, blk_ti_ph);
            g.beginReservedBlock(blk_ti_sp);
            const c16_ti_spill = try g.constInt(16);
            try g.jump(blk_ti_mg, &.{c16_ti_spill});
            g.beginReservedBlock(blk_ti_ph);
            try g.jump(blk_ti_mg, &.{ti_reg_raw});
            g.beginReservedBlock(blk_ti_mg);
            const ti_reg = try g.addBlockParam();

            // Bump alloc 16 bytes: [tag_hash at +0, payload at +8]
            const c16_ti = try g.constInt(16);
            var ti_bytes = try g.callDirect(f_emit_bump_alloc, &.{ bytes, ti_reg, c16_ti });

            // Compute tag hash and store at [ti_reg, #0]
            const ti_hash = try g.callBuiltin("string_hash", &.{ti_tag});
            const c17_ti = try g.constInt(17); // use x17 as temp
            ti_bytes = try g.callDirect(f_mov_imm64, &.{ ti_bytes, c17_ti, ti_hash });
            const c0_ti = try g.constInt(0);
            const ti_str_hash = try g.callDirect(f_encode_str, &.{ c17_ti, ti_reg, c0_ti });
            ti_bytes = try g.callDirect(f_append_inst, &.{ ti_bytes, ti_str_hash });

            // Store payload at [ti_reg, #8] (if payload != -1)
            const ti_neg1 = try g.constInt(-1);
            const ti_has_payload = try g.binary(.ne, ti_pl_val, ti_neg1);
            const blk_ti_has_pl = g.reserveBlock();
            const blk_ti_no_pl = g.reserveBlock();
            const blk_ti_done = g.reserveBlock();
            try g.branch(ti_has_payload, blk_ti_has_pl, blk_ti_no_pl);

            g.beginReservedBlock(blk_ti_has_pl);
            {
                const ti_pl_reg_raw = try g.callDirect(f_get_reg, &.{ ti_ctx, ti_pl_val });
                // Load from spill if needed
                const c17_ti2 = try g.constInt(17);
                const ti_pl_load = try g.callDirect(f_load_spill, &.{ ti_bytes, ti_pl_reg_raw, c17_ti2 });
                const ti_b_pl = try g.recordField(ti_pl_load, "bytes");
                const ti_pl_reg = try g.recordField(ti_pl_load, "reg");
                const c8_ti = try g.constInt(8);
                const ti_str_pl = try g.callDirect(f_encode_str, &.{ ti_pl_reg, ti_reg, c8_ti });
                const ti_b_pl2 = try g.callDirect(f_append_inst, &.{ ti_b_pl, ti_str_pl });
                try g.jump(blk_ti_done, &.{ti_b_pl2});
            }

            g.beginReservedBlock(blk_ti_no_pl);
            {
                // No payload — store 0 at [ti_reg, #8]
                const c17_ti3 = try g.constInt(17);
                const ti_b_np = try g.callDirect(f_mov_imm64, &.{ ti_bytes, c17_ti3, c0_ti });
                const c8_ti2 = try g.constInt(8);
                const ti_str_np = try g.callDirect(f_encode_str, &.{ c17_ti3, ti_reg, c8_ti2 });
                const ti_b_np2 = try g.callDirect(f_append_inst, &.{ ti_b_np, ti_str_np });
                try g.jump(blk_ti_done, &.{ti_b_np2});
            }

            g.beginReservedBlock(blk_ti_done);
            const ti_bytes_final = try g.addBlockParam();
            // Store to spill slot if needed
            const ti_b_spill = try g.callDirect(f_store_spill, &.{ ti_bytes_final, ti_reg_raw, ti_reg });
            const ti_result = try g.record(&.{
                .{ .name = "bytes", .value = ti_b_spill },
                .{ .name = "ctx", .value = ti_ctx },
            });
            try g.ret(ti_result);
        }

        // Not tag_init: check IrTagTest
        g.beginReservedBlock(blk_not_tag_init);
        const is_tag_test = try g.tagTest(inst, ir_tag_test);
        const blk_tag_test = g.reserveBlock();
        const blk_not_tag_test = g.reserveBlock();
        try g.branch(is_tag_test, blk_tag_test, blk_not_tag_test);

        // IrTagTest: {dst, value, tag} -> load tag_hash from [value, #0], compare with expected
        g.beginReservedBlock(blk_tag_test);
        {
            const tt_payload = try g.tagPayload(inst, ir_tag_test);
            const tt_dst = try g.recordField(tt_payload, "dst");
            const tt_value = try g.recordField(tt_payload, "value");
            const tt_tag = try g.recordField(tt_payload, "tag");

            const tt_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, tt_dst });
            const tt_dst_reg_raw = try g.recordField(tt_alloc, "reg");
            const tt_ctx = try g.recordField(tt_alloc, "ctx");

            // Spill merge for dst: use x16 if spilled
            const c100_tt = try g.constInt(100);
            const tt_spilled = try g.ge(tt_dst_reg_raw, c100_tt);
            const blk_tt_sp = g.reserveBlock();
            const blk_tt_ph = g.reserveBlock();
            const blk_tt_mg = g.reserveBlock();
            try g.branch(tt_spilled, blk_tt_sp, blk_tt_ph);
            g.beginReservedBlock(blk_tt_sp);
            const c16_tt = try g.constInt(16);
            try g.jump(blk_tt_mg, &.{c16_tt});
            g.beginReservedBlock(blk_tt_ph);
            try g.jump(blk_tt_mg, &.{tt_dst_reg_raw});
            g.beginReservedBlock(blk_tt_mg);
            const tt_dst_reg = try g.addBlockParam();

            // Get the value register (the tagged value pointer)
            const tt_val_reg_raw = try g.callDirect(f_get_reg, &.{ tt_ctx, tt_value });
            const c17_tt = try g.constInt(17);
            const tt_val_load = try g.callDirect(f_load_spill, &.{ bytes, tt_val_reg_raw, c17_tt });
            var tt_bytes = try g.recordField(tt_val_load, "bytes");
            const tt_val_reg = try g.recordField(tt_val_load, "reg");

            // LDR x17, [value_reg, #0] — load the stored tag hash
            const c0_tt = try g.constInt(0);
            const tt_ldr = try g.callDirect(f_encode_ldr, &.{ c17_tt, tt_val_reg, c0_tt });
            tt_bytes = try g.callDirect(f_append_inst, &.{ tt_bytes, tt_ldr });

            // Compute expected tag hash and load into dst_reg
            const tt_hash = try g.callBuiltin("string_hash", &.{tt_tag});
            tt_bytes = try g.callDirect(f_mov_imm64, &.{ tt_bytes, tt_dst_reg, tt_hash });

            // CMP x17, dst_reg
            const tt_cmp = try g.callDirect(f_encode_cmp_reg, &.{ c17_tt, tt_dst_reg });
            tt_bytes = try g.callDirect(f_append_inst, &.{ tt_bytes, tt_cmp });

            // CSET dst_reg, EQ (cond=0)
            const tt_cset = try g.callDirect(f_encode_cset, &.{ tt_dst_reg, c0_tt });
            tt_bytes = try g.callDirect(f_append_inst, &.{ tt_bytes, tt_cset });

            // Store to spill slot if needed
            tt_bytes = try g.callDirect(f_store_spill, &.{ tt_bytes, tt_dst_reg_raw, tt_dst_reg });
            const tt_result = try g.record(&.{
                .{ .name = "bytes", .value = tt_bytes },
                .{ .name = "ctx", .value = tt_ctx },
            });
            try g.ret(tt_result);
        }

        // Not tag_test: check IrTagPayload
        g.beginReservedBlock(blk_not_tag_test);
        const is_tag_payload = try g.tagTest(inst, ir_tag_payload);
        const blk_tag_payload = g.reserveBlock();
        const blk_not_tag_payload = g.reserveBlock();
        try g.branch(is_tag_payload, blk_tag_payload, blk_not_tag_payload);

        // IrTagPayload: {dst, value, tag} -> LDR dst, [value, #8]
        g.beginReservedBlock(blk_tag_payload);
        {
            const tp_payload = try g.tagPayload(inst, ir_tag_payload);
            const tp_dst = try g.recordField(tp_payload, "dst");
            const tp_value = try g.recordField(tp_payload, "value");

            const tp_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, tp_dst });
            const tp_dst_reg_raw = try g.recordField(tp_alloc, "reg");
            const tp_ctx = try g.recordField(tp_alloc, "ctx");

            // Spill merge for dst: use x27 if spilled
            const c100_tp = try g.constInt(100);
            const tp_spilled = try g.ge(tp_dst_reg_raw, c100_tp);
            const blk_tp_sp = g.reserveBlock();
            const blk_tp_ph = g.reserveBlock();
            const blk_tp_mg = g.reserveBlock();
            try g.branch(tp_spilled, blk_tp_sp, blk_tp_ph);
            g.beginReservedBlock(blk_tp_sp);
            const c27_tp = try g.constInt(27);
            try g.jump(blk_tp_mg, &.{c27_tp});
            g.beginReservedBlock(blk_tp_ph);
            try g.jump(blk_tp_mg, &.{tp_dst_reg_raw});
            g.beginReservedBlock(blk_tp_mg);
            const tp_dst_reg = try g.addBlockParam();

            // Get the value register
            const tp_val_reg_raw = try g.callDirect(f_get_reg, &.{ tp_ctx, tp_value });
            const c17_tp = try g.constInt(17);
            const tp_val_load = try g.callDirect(f_load_spill, &.{ bytes, tp_val_reg_raw, c17_tp });
            var tp_bytes = try g.recordField(tp_val_load, "bytes");
            const tp_val_reg = try g.recordField(tp_val_load, "reg");

            // LDR dst_reg, [value_reg, #8] — load payload from offset 8
            const c8_tp = try g.constInt(8);
            const tp_ldr = try g.callDirect(f_encode_ldr, &.{ tp_dst_reg, tp_val_reg, c8_tp });
            tp_bytes = try g.callDirect(f_append_inst, &.{ tp_bytes, tp_ldr });

            // Store to spill slot if needed
            tp_bytes = try g.callDirect(f_store_spill, &.{ tp_bytes, tp_dst_reg_raw, tp_dst_reg });
            const tp_result = try g.record(&.{
                .{ .name = "bytes", .value = tp_bytes },
                .{ .name = "ctx", .value = tp_ctx },
            });
            try g.ret(tp_result);
        }

        // Not tag_payload: check IrHandleSetup
        g.beginReservedBlock(blk_not_tag_payload);
        const is_handle_setup = try g.tagTest(inst, ir_handle_setup);
        const blk_handle_setup = g.reserveBlock();
        const blk_not_handle_setup = g.reserveBlock();
        try g.branch(is_handle_setup, blk_handle_setup, blk_not_handle_setup);

        // IrHandleSetup: {dst, effect, clause_block}
        // Bump alloc 48-byte handler frame on x28:
        //   [0] effect_hash, [8] prev_handler (x27), [16] handler_addr (clause block),
        //   [24] saved_sp, [32] saved_fp, [40] saved_lr
        // Then set x27 = new frame
        g.beginReservedBlock(blk_handle_setup);
        {
            const hs_payload = try g.tagPayload(inst, ir_handle_setup);
            const hs_dst = try g.recordField(hs_payload, "dst");
            const hs_effect = try g.recordField(hs_payload, "effect");
            const hs_clause_blk = try g.recordField(hs_payload, "clause_block");
            // Allocate dst to keep counter in sync
            const hs_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, hs_dst });
            const hs_ctx = try g.recordField(hs_alloc, "ctx");

            // Bump alloc 48 bytes: x17 = frame ptr
            const c17_hs = try g.constInt(17);
            const c48_hs = try g.constInt(48);
            var hs_bytes = try g.callDirect(f_emit_bump_alloc, &.{ bytes, c17_hs, c48_hs });

            // Store effect hash at [x17, #0]
            const hs_hash = try g.callBuiltin("string_hash", &.{hs_effect});
            const c16_hs = try g.constInt(16);
            hs_bytes = try g.callDirect(f_mov_imm64, &.{ hs_bytes, c16_hs, hs_hash });
            const c0_hs = try g.constInt(0);
            const hs_str_hash = try g.callDirect(f_encode_str, &.{ c16_hs, c17_hs, c0_hs });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_str_hash });

            // Store prev handler (x27) at [x17, #8]
            const c27_hs = try g.constInt(27);
            const c8_hs = try g.constInt(8);
            const hs_str_prev = try g.callDirect(f_encode_str, &.{ c27_hs, c17_hs, c8_hs });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_str_prev });

            // Compute handler clause address via ADR and store at [x17, #16]
            // offset = (blocks_start + block_offsets[clause_block]) - current_offset
            const hs_bo = try g.recordField(hs_ctx, "block_offsets");
            const hs_bs = try g.recordField(hs_ctx, "blocks_start");
            const hs_clause_str = try g.callBuiltin("string_from_int", &.{hs_clause_blk});
            const hs_clause_off = try g.mapGet(hs_bo, hs_clause_str);
            const hs_clause_abs = try g.add(hs_bs, hs_clause_off);
            const hs_cur = try g.callBuiltin("bytes_length", &.{hs_bytes});
            const hs_rel = try g.sub(hs_clause_abs, hs_cur);
            const hs_adr = try g.callDirect(f_encode_adr, &.{ c16_hs, hs_rel });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_adr });
            const hs_str_addr = try g.callDirect(f_encode_str, &.{ c16_hs, c17_hs, c16_hs });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_str_addr });

            // Save SP at [x17, #24]: MOV x16, SP; STR x16, [x17, #24]
            const c31_hs = try g.constInt(31);
            const hs_mov_sp = try g.callDirect(f_encode_add_imm, &.{ c16_hs, c31_hs, c0_hs });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_mov_sp });
            const c24_hs = try g.constInt(24);
            const hs_str_sp = try g.callDirect(f_encode_str, &.{ c16_hs, c17_hs, c24_hs });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_str_sp });

            // Save FP (x29) at [x17, #32]
            const c29_hs = try g.constInt(29);
            const c32_hs = try g.constInt(32);
            const hs_str_fp = try g.callDirect(f_encode_str, &.{ c29_hs, c17_hs, c32_hs });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_str_fp });

            // Save LR (x30) at [x17, #40]
            const c30_hs = try g.constInt(30);
            const c40_hs = try g.constInt(40);
            const hs_str_lr = try g.callDirect(f_encode_str, &.{ c30_hs, c17_hs, c40_hs });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_str_lr });

            // Set x27 = new frame: MOV x27, x17 (ADD x27, x17, #0)
            const hs_mov_x27 = try g.callDirect(f_encode_add_imm, &.{ c27_hs, c17_hs, c0_hs });
            hs_bytes = try g.callDirect(f_append_inst, &.{ hs_bytes, hs_mov_x27 });

            const hs_result = try g.record(&.{
                .{ .name = "bytes", .value = hs_bytes },
                .{ .name = "ctx", .value = hs_ctx },
            });
            try g.ret(hs_result);
        }

        // Not handle_setup: check IrHandlePop
        g.beginReservedBlock(blk_not_handle_setup);
        const is_handle_pop = try g.tagTest(inst, ir_handle_pop);
        const blk_handle_pop = g.reserveBlock();
        const blk_not_handle_pop = g.reserveBlock();
        try g.branch(is_handle_pop, blk_handle_pop, blk_not_handle_pop);

        // IrHandlePop: {dst} -> LDR x27, [x27, #8] (restore prev handler)
        g.beginReservedBlock(blk_handle_pop);
        {
            const hp_payload = try g.tagPayload(inst, ir_handle_pop);
            const hp_dst = try g.recordField(hp_payload, "dst");
            const hp_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, hp_dst });
            const hp_ctx = try g.recordField(hp_alloc, "ctx");
            const c27_hp = try g.constInt(27);
            const c8_hp = try g.constInt(8);
            const hp_ldr = try g.callDirect(f_encode_ldr, &.{ c27_hp, c27_hp, c8_hp });
            const hp_bytes = try g.callDirect(f_append_inst, &.{ bytes, hp_ldr });

            const hp_result = try g.record(&.{
                .{ .name = "bytes", .value = hp_bytes },
                .{ .name = "ctx", .value = hp_ctx },
            });
            try g.ret(hp_result);
        }

        // Not handle_pop: check IrPerform
        g.beginReservedBlock(blk_not_handle_pop);
        const is_perform = try g.tagTest(inst, ir_perform);
        const blk_perform = g.reserveBlock();
        const blk_not_perform = g.reserveBlock();
        try g.branch(is_perform, blk_perform, blk_not_perform);

        // IrPerform: {dst, effect, op, args}
        // 1. Move perform args to x1..xN
        // 2. Bump alloc 104-byte continuation on x28
        // 3. Save resume_addr (ADR), SP, x19-x26, FP, LR, consumed=0 into continuation
        // 4. x0 = continuation ptr
        // 5. LDR handler_addr from handler frame [x27, #16]
        // 6. Pop handler: LDR x27, [x27, #8]
        // 7. BR handler_addr
        // 8. Resume point: result in x0, MOV dst, x0
        g.beginReservedBlock(blk_perform);
        {
            const pf_payload = try g.tagPayload(inst, ir_perform);
            const pf_dst = try g.recordField(pf_payload, "dst");
            const pf_args = try g.recordField(pf_payload, "args");
            const pf_num_args = try g.listLength(pf_args);

            // Step 1: Move perform args to x1..xN (skip x0, reserved for continuation)
            const c0_pf = try g.constInt(0);
            const pf_args_loop = g.reserveBlock();
            try g.jump(pf_args_loop, &.{ c0_pf, bytes, ctx });

            g.beginReservedBlock(pf_args_loop);
            const pf_ai = try g.addBlockParam();
            const pf_ab = try g.addBlockParam();
            const pf_ac = try g.addBlockParam();
            const pf_args_done = try g.ge(pf_ai, pf_num_args);
            const pf_args_exit = g.reserveBlock();
            const pf_args_body = g.reserveBlock();
            try g.branch(pf_args_done, pf_args_exit, pf_args_body);

            g.beginReservedBlock(pf_args_body);
            {
                const pf_arg_val = try g.listNth(pf_args, pf_ai);
                const pf_arg_reg_raw = try g.callDirect(f_get_reg, &.{ pf_ac, pf_arg_val });
                const c17_pf = try g.constInt(17);
                const pf_arg_load = try g.callDirect(f_load_spill, &.{ pf_ab, pf_arg_reg_raw, c17_pf });
                const pf_ab_loaded = try g.recordField(pf_arg_load, "bytes");
                const pf_arg_reg = try g.recordField(pf_arg_load, "reg");
                // Target register is x(ai+1) — args go in x1, x2, ... (x0 is continuation)
                const c1_pf_a = try g.constInt(1);
                const pf_tgt = try g.add(pf_ai, c1_pf_a);
                const pf_need_mov = try g.ne(pf_arg_reg, pf_tgt);
                const pf_do_mov = g.reserveBlock();
                const pf_skip_mov = g.reserveBlock();
                const pf_after_mov = g.reserveBlock();
                try g.branch(pf_need_mov, pf_do_mov, pf_skip_mov);

                g.beginReservedBlock(pf_do_mov);
                const pf_c0_m = try g.constInt(0);
                const pf_mov = try g.callDirect(f_encode_add_imm, &.{ pf_tgt, pf_arg_reg, pf_c0_m });
                const pf_mb = try g.callDirect(f_append_inst, &.{ pf_ab_loaded, pf_mov });
                try g.jump(pf_after_mov, &.{pf_mb});

                g.beginReservedBlock(pf_skip_mov);
                try g.jump(pf_after_mov, &.{pf_ab_loaded});

                g.beginReservedBlock(pf_after_mov);
                const pf_ab2 = try g.addBlockParam();
                const pf_next_ai = try g.add(pf_ai, c1_pf_a);
                try g.jump(pf_args_loop, &.{ pf_next_ai, pf_ab2, pf_ac });
            }

            // Step 2-7: Emit fixed instruction sequence for perform
            g.beginReservedBlock(pf_args_exit);
            {
                // Bump alloc 112 bytes for continuation: x17 = continuation ptr
                // Layout: [0]resume_addr [8]sp [16]x19 [24]x20 [32]x21 [40]x22
                //         [48]x23 [56]x24 [64]x25 [72]x26 [80]x27 [88]x29
                //         [96]x30 [104]consumed
                const c17_pf = try g.constInt(17);
                const c112_pf = try g.constInt(112);
                var pf_bytes = try g.callDirect(f_emit_bump_alloc, &.{ pf_ab, c17_pf, c112_pf });

                // ADR x16, #80 — resume point is 20 instructions from here
                // Instructions after ADR: STR resume(1) + MOV SP(1) + STR sp(1) +
                //   STR x19-x26(8) + STR x27(1) + STR fp(1) + STR lr(1) + STR consumed(1) +
                //   MOV x0(1) + LDR handler(1) + LDR pop(1) + BR(1) = 19
                // Resume point = ADR + (19+1)*4 = ADR + 80 bytes
                const c16_pf = try g.constInt(16);
                const c80_pf2 = try g.constInt(80);
                const pf_adr = try g.callDirect(f_encode_adr, &.{ c16_pf, c80_pf2 });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_adr });

                // STR x16, [x17, #0] — store resume_addr
                const c0_pfs = try g.constInt(0);
                const pf_str_resume = try g.callDirect(f_encode_str, &.{ c16_pf, c17_pf, c0_pfs });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str_resume });

                // MOV x16, SP: ADD x16, x31, #0
                const c31_pf = try g.constInt(31);
                const pf_mov_sp = try g.callDirect(f_encode_add_imm, &.{ c16_pf, c31_pf, c0_pfs });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_mov_sp });

                // STR x16, [x17, #8] — saved_sp
                const c8_pf = try g.constInt(8);
                const pf_str_sp = try g.callDirect(f_encode_str, &.{ c16_pf, c17_pf, c8_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str_sp });

                // STR x19, [x17, #16]
                const c19_pf = try g.constInt(19);
                const pf_str19 = try g.callDirect(f_encode_str, &.{ c19_pf, c17_pf, c16_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str19 });

                // STR x20, [x17, #24]
                const c20_pf = try g.constInt(20);
                const c24_pf = try g.constInt(24);
                const pf_str20 = try g.callDirect(f_encode_str, &.{ c20_pf, c17_pf, c24_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str20 });

                // STR x21, [x17, #32]
                const c21_pf = try g.constInt(21);
                const c32_pf = try g.constInt(32);
                const pf_str21 = try g.callDirect(f_encode_str, &.{ c21_pf, c17_pf, c32_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str21 });

                // STR x22, [x17, #40]
                const c22_pf = try g.constInt(22);
                const c40_pf = try g.constInt(40);
                const pf_str22 = try g.callDirect(f_encode_str, &.{ c22_pf, c17_pf, c40_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str22 });

                // STR x23, [x17, #48]
                const c23_pf = try g.constInt(23);
                const c48_pf = try g.constInt(48);
                const pf_str23 = try g.callDirect(f_encode_str, &.{ c23_pf, c17_pf, c48_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str23 });

                // STR x24, [x17, #56]
                const c24_pf2 = try g.constInt(24);
                const c56_pf = try g.constInt(56);
                const pf_str24 = try g.callDirect(f_encode_str, &.{ c24_pf2, c17_pf, c56_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str24 });

                // STR x25, [x17, #64]
                const c25_pf = try g.constInt(25);
                const c64_pf = try g.constInt(64);
                const pf_str25 = try g.callDirect(f_encode_str, &.{ c25_pf, c17_pf, c64_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str25 });

                // STR x26, [x17, #72]
                const c26_pf = try g.constInt(26);
                const c72_pf = try g.constInt(72);
                const pf_str26 = try g.callDirect(f_encode_str, &.{ c26_pf, c17_pf, c72_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str26 });

                // STR x27, [x17, #80] — saved handler stack pointer
                const c27_pf = try g.constInt(27);
                const c80_pf = try g.constInt(80);
                const pf_str27 = try g.callDirect(f_encode_str, &.{ c27_pf, c17_pf, c80_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str27 });

                // STR x29, [x17, #88] — saved_fp
                const c29_pf = try g.constInt(29);
                const c88_pf = try g.constInt(88);
                const pf_str29 = try g.callDirect(f_encode_str, &.{ c29_pf, c17_pf, c88_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str29 });

                // STR x30, [x17, #96] — saved_lr
                const c30_pf = try g.constInt(30);
                const c96_pf = try g.constInt(96);
                const pf_str30 = try g.callDirect(f_encode_str, &.{ c30_pf, c17_pf, c96_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str30 });

                // STR xzr, [x17, #104] — consumed = 0 (x31 in STR = XZR)
                const c104_pf2 = try g.constInt(104);
                const pf_str_consumed = try g.callDirect(f_encode_str, &.{ c31_pf, c17_pf, c104_pf2 });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_str_consumed });

                // MOV x0, x17: ADD x0, x17, #0 — x0 = continuation ptr
                const pf_mov_x0 = try g.callDirect(f_encode_add_imm, &.{ c0_pfs, c17_pf, c0_pfs });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_mov_x0 });

                // LDR x16, [x27, #16] — load handler clause address
                const pf_ldr_handler = try g.callDirect(f_encode_ldr, &.{ c16_pf, c27_pf, c16_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_ldr_handler });

                // Pop handler: LDR x27, [x27, #8]
                const pf_pop = try g.callDirect(f_encode_ldr, &.{ c27_pf, c27_pf, c8_pf });
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_pop });

                // BR x16 — jump to handler clause
                const pf_br = try g.callDirect(f_encode_br, &.{c16_pf});
                pf_bytes = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_br });

                // === RESUME POINT ===
                // When handler calls resume(val), execution returns here with x0 = val
                // Allocate register for dst and MOV from x0
                const pf_alloc = try g.callDirect(f_alloc_reg, &.{ pf_ac, pf_dst });
                const pf_dst_reg = try g.recordField(pf_alloc, "reg");
                const pf_ctx_out = try g.recordField(pf_alloc, "ctx");

                // Check if dst is spilled
                const c100_pf = try g.constInt(100);
                const pf_spilled = try g.ge(pf_dst_reg, c100_pf);
                const blk_pf_spill = g.reserveBlock();
                const blk_pf_phys = g.reserveBlock();
                try g.branch(pf_spilled, blk_pf_spill, blk_pf_phys);

                // Spilled: STR x0, [sp, #spill_offset]
                g.beginReservedBlock(blk_pf_spill);
                {
                    const pf_sb = try g.callDirect(f_store_spill, &.{ pf_bytes, pf_dst_reg, c0_pfs });
                    const pf_sr = try g.record(&.{
                        .{ .name = "bytes", .value = pf_sb },
                        .{ .name = "ctx", .value = pf_ctx_out },
                    });
                    try g.ret(pf_sr);
                }

                // Physical: MOV dst_reg, x0 (if needed)
                g.beginReservedBlock(blk_pf_phys);
                {
                    const pf_is_x0 = try g.eq(pf_dst_reg, c0_pfs);
                    const blk_pf_need_mov = g.reserveBlock();
                    const blk_pf_skip_mov = g.reserveBlock();
                    const blk_pf_done = g.reserveBlock();
                    try g.branch(pf_is_x0, blk_pf_skip_mov, blk_pf_need_mov);

                    g.beginReservedBlock(blk_pf_need_mov);
                    const pf_dst_mov = try g.callDirect(f_encode_add_imm, &.{ pf_dst_reg, c0_pfs, c0_pfs });
                    const pf_db = try g.callDirect(f_append_inst, &.{ pf_bytes, pf_dst_mov });
                    try g.jump(blk_pf_done, &.{pf_db});

                    g.beginReservedBlock(blk_pf_skip_mov);
                    try g.jump(blk_pf_done, &.{pf_bytes});

                    g.beginReservedBlock(blk_pf_done);
                    const pf_fb = try g.addBlockParam();
                    const pf_fr = try g.record(&.{
                        .{ .name = "bytes", .value = pf_fb },
                        .{ .name = "ctx", .value = pf_ctx_out },
                    });
                    try g.ret(pf_fr);
                }
            }
        }

        // Not perform: check IrResume
        g.beginReservedBlock(blk_not_perform);
        const is_resume = try g.tagTest(inst, ir_resume);
        const blk_resume = g.reserveBlock();
        const blk_not_resume = g.reserveBlock();
        try g.branch(is_resume, blk_resume, blk_not_resume);

        // IrResume: {dst, continuation, value}
        // The continuation is ALWAYS in x0 (set by IrPerform before jumping to handler).
        // Steps:
        // 1. Copy x0 (continuation) to x17 (safe temp, never allocated)
        // 2. Get resume value register
        // 3. Check consumed flag via [x17, #96] (trap if non-zero)
        // 4. Set consumed = 1
        // 5. Put resume value in x0
        // 6. Restore callee-saved regs, FP, LR, SP from [x17, ...]
        // 7. Load resume_addr from [x17, #0] and BR to it
        g.beginReservedBlock(blk_resume);
        {
            const rs_payload = try g.tagPayload(inst, ir_resume);
            const rs_dst = try g.recordField(rs_payload, "dst");
            const rs_continuation = try g.recordField(rs_payload, "continuation");
            const rs_value = try g.recordField(rs_payload, "value");

            // Allocate dst to keep counter in sync
            const rs_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, rs_dst });
            const rs_ctx = try g.recordField(rs_alloc, "ctx");

            const c0_rs = try g.constInt(0);
            const c16_rs = try g.constInt(16);
            const c17_rs = try g.constInt(17);

            const rs_cont_reg_raw = try g.callDirect(f_get_reg, &.{ rs_ctx, rs_continuation });
            const rs_cont_load = try g.callDirect(f_load_spill, &.{ bytes, rs_cont_reg_raw, c16_rs });
            var rs_bytes = try g.recordField(rs_cont_load, "bytes");
            const rs_cont_reg = try g.recordField(rs_cont_load, "reg");
            const rs_save_cont = try g.callDirect(f_encode_add_imm, &.{ c17_rs, rs_cont_reg, c0_rs });
            rs_bytes = try g.callDirect(f_append_inst, &.{ rs_bytes, rs_save_cont });

            // Step 2: Check consumed flag FIRST (uses x16 as temp)
            // LDR x16, [x17, #104]
            const c104_rs = try g.constInt(104);
            const rs_ldr_consumed = try g.callDirect(f_encode_ldr, &.{ c16_rs, c17_rs, c104_rs });
            rs_bytes = try g.callDirect(f_append_inst, &.{ rs_bytes, rs_ldr_consumed });

            // CBZ x16, #8 — skip trap if consumed == 0
            const cbz_base_rs = try g.constInt(0xB4000000);
            const c2_rs = try g.constInt(2); // offset = 8 bytes / 4 = 2
            const c5_rs = try g.constInt(5);
            const cbz_off_rs = try g.binary(.shl, c2_rs, c5_rs);
            const cbz_rs = try g.binary(.bit_or, cbz_base_rs, cbz_off_rs);
            const cbz_enc_rs = try g.binary(.bit_or, cbz_rs, c16_rs);
            rs_bytes = try g.callDirect(f_append_inst, &.{ rs_bytes, cbz_enc_rs });

            // BRK #1 — trap on double-resume
            const brk_enc = try g.constInt(0xD4200020); // BRK #1
            rs_bytes = try g.callDirect(f_append_inst, &.{ rs_bytes, brk_enc });

            // Step 3: Set consumed = 1: MOVZ x16, #1; STR x16, [x17, #104]
            const c1_rs = try g.constInt(1);
            const rs_movz_1 = try g.callDirect(f_encode_movz, &.{ c16_rs, c1_rs, c0_rs });
            rs_bytes = try g.callDirect(f_append_inst, &.{ rs_bytes, rs_movz_1 });
            const rs_str_consumed = try g.callDirect(f_encode_str, &.{ c16_rs, c17_rs, c104_rs });
            rs_bytes = try g.callDirect(f_append_inst, &.{ rs_bytes, rs_str_consumed });

            // Step 4: Get value register (x16 is now free for spill loading)
            const rs_val_reg_raw = try g.callDirect(f_get_reg, &.{ rs_ctx, rs_value });
            const rs_val_load = try g.callDirect(f_load_spill, &.{ rs_bytes, rs_val_reg_raw, c16_rs });
            rs_bytes = try g.recordField(rs_val_load, "bytes");
            const rs_val_reg = try g.recordField(rs_val_load, "reg");

            // Step 5: MOV x0, value_reg (if not already x0)
            const rs_is_x0 = try g.eq(rs_val_reg, c0_rs);
            const blk_rs_need_mov = g.reserveBlock();
            const blk_rs_skip_mov = g.reserveBlock();
            const blk_rs_after_mov = g.reserveBlock();
            try g.branch(rs_is_x0, blk_rs_skip_mov, blk_rs_need_mov);

            g.beginReservedBlock(blk_rs_need_mov);
            {
                const rs_mov_val = try g.callDirect(f_encode_add_imm, &.{ c0_rs, rs_val_reg, c0_rs });
                const rs_mb = try g.callDirect(f_append_inst, &.{ rs_bytes, rs_mov_val });
                try g.jump(blk_rs_after_mov, &.{rs_mb});
            }

            g.beginReservedBlock(blk_rs_skip_mov);
            try g.jump(blk_rs_after_mov, &.{rs_bytes});

            g.beginReservedBlock(blk_rs_after_mov);
            var rs_b = try g.addBlockParam();

            // Step 6: Restore callee-saved registers from continuation (x17)
            // LDR x19, [x17, #16]
            const c19_rs = try g.constInt(19);
            const rs_ldr19 = try g.callDirect(f_encode_ldr, &.{ c19_rs, c17_rs, c16_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr19 });

            // LDR x20, [x17, #24]
            const c20_rs = try g.constInt(20);
            const c24_rs = try g.constInt(24);
            const rs_ldr20 = try g.callDirect(f_encode_ldr, &.{ c20_rs, c17_rs, c24_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr20 });

            // LDR x21, [x17, #32]
            const c21_rs = try g.constInt(21);
            const c32_rs = try g.constInt(32);
            const rs_ldr21 = try g.callDirect(f_encode_ldr, &.{ c21_rs, c17_rs, c32_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr21 });

            // LDR x22, [x17, #40]
            const c22_rs = try g.constInt(22);
            const c40_rs = try g.constInt(40);
            const rs_ldr22 = try g.callDirect(f_encode_ldr, &.{ c22_rs, c17_rs, c40_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr22 });

            // LDR x23, [x17, #48]
            const c23_rs = try g.constInt(23);
            const c48_rs = try g.constInt(48);
            const rs_ldr23 = try g.callDirect(f_encode_ldr, &.{ c23_rs, c17_rs, c48_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr23 });

            // LDR x24, [x17, #56]
            const c24_rs2 = try g.constInt(24);
            const c56_rs = try g.constInt(56);
            const rs_ldr24 = try g.callDirect(f_encode_ldr, &.{ c24_rs2, c17_rs, c56_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr24 });

            // LDR x25, [x17, #64]
            const c25_rs = try g.constInt(25);
            const c64_rs = try g.constInt(64);
            const rs_ldr25 = try g.callDirect(f_encode_ldr, &.{ c25_rs, c17_rs, c64_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr25 });

            // LDR x26, [x17, #72]
            const c26_rs = try g.constInt(26);
            const c72_rs = try g.constInt(72);
            const rs_ldr26 = try g.callDirect(f_encode_ldr, &.{ c26_rs, c17_rs, c72_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr26 });

            // LDR x27, [x17, #80] — restore handler stack pointer
            const c27_rs = try g.constInt(27);
            const c80_rs = try g.constInt(80);
            const rs_ldr27 = try g.callDirect(f_encode_ldr, &.{ c27_rs, c17_rs, c80_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr27 });

            // LDR x29, [x17, #88] — restore FP
            const c29_rs = try g.constInt(29);
            const c88_rs = try g.constInt(88);
            const rs_ldr29 = try g.callDirect(f_encode_ldr, &.{ c29_rs, c17_rs, c88_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr29 });

            // LDR x30, [x17, #96] — restore LR
            const c30_rs = try g.constInt(30);
            const c96_rs = try g.constInt(96);
            const rs_ldr30 = try g.callDirect(f_encode_ldr, &.{ c30_rs, c17_rs, c96_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr30 });

            // Step 7: Restore SP and jump
            // LDR x16, [x17, #8] — saved_sp
            const c8_rs = try g.constInt(8);
            const rs_ldr_sp = try g.callDirect(f_encode_ldr, &.{ c16_rs, c17_rs, c8_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr_sp });

            // MOV SP, x16: ADD SP, x16, #0
            const c31_rs = try g.constInt(31);
            const rs_mov_sp = try g.callDirect(f_encode_add_imm, &.{ c31_rs, c16_rs, c0_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_mov_sp });

            // LDR x16, [x17, #0] — resume_addr
            const rs_ldr_resume = try g.callDirect(f_encode_ldr, &.{ c16_rs, c17_rs, c0_rs });
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_ldr_resume });

            // BR x16 — jump to resume point
            const rs_br = try g.callDirect(f_encode_br, &.{c16_rs});
            rs_b = try g.callDirect(f_append_inst, &.{ rs_b, rs_br });

            const rs_result = try g.record(&.{
                .{ .name = "bytes", .value = rs_b },
                .{ .name = "ctx", .value = rs_ctx },
            });
            try g.ret(rs_result);
        }

        // Not resume: check IrArgReceive
        g.beginReservedBlock(blk_not_resume);
        const is_arg_receive = try g.tagTest(inst, ir_arg_receive);
        const blk_arg_receive = g.reserveBlock();
        const blk_not_arg_receive = g.reserveBlock();
        try g.branch(is_arg_receive, blk_arg_receive, blk_not_arg_receive);

        g.beginReservedBlock(blk_arg_receive);
        {
            const ar_payload = try g.tagPayload(inst, ir_arg_receive);
            const ar_dst = try g.recordField(ar_payload, "dst");
            const ar_index = try g.recordField(ar_payload, "index");

            // Allocate register for dst
            const ar_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ar_dst });
            const ar_dst_reg = try g.recordField(ar_alloc, "reg");
            const ar_ctx = try g.recordField(ar_alloc, "ctx");

            // Check if dst is a spill slot (>= 100)
            const c100_ar = try g.constInt(100);
            const ar_is_spill = try g.ge(ar_dst_reg, c100_ar);
            const blk_ar_spill = g.reserveBlock();
            const blk_ar_phys = g.reserveBlock();
            try g.branch(ar_is_spill, blk_ar_spill, blk_ar_phys);

            // Physical register: MOV x(dst_reg), x(index)
            g.beginReservedBlock(blk_ar_phys);
            const c0_ar = try g.constInt(0);
            const ar_mov = try g.callDirect(f_encode_add_imm, &.{ ar_dst_reg, ar_index, c0_ar });
            const ar_bytes_p = try g.callDirect(f_append_inst, &.{ bytes, ar_mov });
            const ar_result_p = try g.record(&.{
                .{ .name = "bytes", .value = ar_bytes_p },
                .{ .name = "ctx", .value = ar_ctx },
            });
            try g.ret(ar_result_p);

            // Spill slot: MOV x17, x(index), then STR x17, [sp, #offset]
            g.beginReservedBlock(blk_ar_spill);
            const c17_ar = try g.constInt(17);
            const c0_ar2 = try g.constInt(0);
            const ar_mov_tmp = try g.callDirect(f_encode_add_imm, &.{ c17_ar, ar_index, c0_ar2 });
            const ar_bytes_s1 = try g.callDirect(f_append_inst, &.{ bytes, ar_mov_tmp });
            const ar_bytes_s2 = try g.callDirect(f_store_spill, &.{ ar_bytes_s1, ar_dst_reg, c17_ar });
            const ar_result_s = try g.record(&.{
                .{ .name = "bytes", .value = ar_bytes_s2 },
                .{ .name = "ctx", .value = ar_ctx },
            });
            try g.ret(ar_result_s);
        }

        // IrRetain / IrRelease: no-ops in bootstrap (bump allocator, no actual RC)
        g.beginReservedBlock(blk_not_arg_receive);
        const is_retain = try g.tagTest(inst, "IrRetain");
        const is_release = try g.tagTest(inst, "IrRelease");
        const is_rc_op = try g.logicOr(is_retain, is_release);
        const blk_rc_noop = g.reserveBlock();
        const blk_not_rc = g.reserveBlock();
        try g.branch(is_rc_op, blk_rc_noop, blk_not_rc);

        g.beginReservedBlock(blk_rc_noop);
        const rc_noop_result = try g.record(&.{
            .{ .name = "bytes", .value = bytes },
            .{ .name = "ctx", .value = ctx },
        });
        try g.ret(rc_noop_result);

        // IrStore: variable or pointer write
        g.beginReservedBlock(blk_not_rc);
        const is_store = try g.tagTest(inst, "IrStore");
        const blk_store = g.reserveBlock();
        const blk_not_store = g.reserveBlock();
        try g.branch(is_store, blk_store, blk_not_store);

        g.beginReservedBlock(blk_store);
        {
            const store_payload = try g.tagPayload(inst, "IrStore");
            const store_dst = try g.recordField(store_payload, "dst");
            const store_target = try g.recordField(store_payload, "target");
            const store_value = try g.recordField(store_payload, "value");
            // Allocate dst to keep counter in sync
            const store_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, store_dst });
            const store_ctx = try g.recordField(store_alloc, "ctx");
            const tgt_reg_raw = try g.callDirect(f_get_reg, &.{ store_ctx, store_target });
            const val_reg_raw = try g.callDirect(f_get_reg, &.{ store_ctx, store_value });
            const c16_st = try g.constInt(16);
            const c17_st = try g.constInt(17);
            const tgt_load = try g.callDirect(f_load_spill, &.{ bytes, tgt_reg_raw, c16_st });
            const bytes_st1 = try g.recordField(tgt_load, "bytes");
            const tgt_reg = try g.recordField(tgt_load, "reg");
            const val_load = try g.callDirect(f_load_spill, &.{ bytes_st1, val_reg_raw, c17_st });
            const bytes_st2 = try g.recordField(val_load, "bytes");
            const val_reg = try g.recordField(val_load, "reg");
            const c0_st = try g.constInt(0);
            const st_mov = try g.callDirect(f_encode_add_imm, &.{ tgt_reg, val_reg, c0_st });
            const st_bytes = try g.callDirect(f_append_inst, &.{ bytes_st2, st_mov });
            const st_bytes2 = try g.callDirect(f_store_spill, &.{ st_bytes, tgt_reg_raw, tgt_reg });
            const st_result = try g.record(&.{
                .{ .name = "bytes", .value = st_bytes2 },
                .{ .name = "ctx", .value = store_ctx },
            });
            try g.ret(st_result);
        }

        // IrPtrStore: store value through pointer — STR value_reg, [ptr_reg, #0]
        g.beginReservedBlock(blk_not_store);
        const is_ptr_store = try g.tagTest(inst, "IrPtrStore");
        const blk_ptr_store = g.reserveBlock();
        const blk_not_ptr_store = g.reserveBlock();
        try g.branch(is_ptr_store, blk_ptr_store, blk_not_ptr_store);

        g.beginReservedBlock(blk_ptr_store);
        {
            const ps_payload = try g.tagPayload(inst, "IrPtrStore");
            const ps_dst = try g.recordField(ps_payload, "dst");
            const ps_ptr = try g.recordField(ps_payload, "ptr");
            const ps_value = try g.recordField(ps_payload, "value");
            // Allocate dst to keep counter in sync
            const ps_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ps_dst });
            const ps_ctx = try g.recordField(ps_alloc, "ctx");
            const ps_ptr_raw = try g.callDirect(f_get_reg, &.{ ps_ctx, ps_ptr });
            const ps_val_raw = try g.callDirect(f_get_reg, &.{ ps_ctx, ps_value });
            const c16_ps = try g.constInt(16);
            const c17_ps = try g.constInt(17);
            const ps_ptr_load = try g.callDirect(f_load_spill, &.{ bytes, ps_ptr_raw, c16_ps });
            const ps_bytes1 = try g.recordField(ps_ptr_load, "bytes");
            const ps_ptr_reg = try g.recordField(ps_ptr_load, "reg");
            const ps_val_load = try g.callDirect(f_load_spill, &.{ ps_bytes1, ps_val_raw, c17_ps });
            const ps_bytes2 = try g.recordField(ps_val_load, "bytes");
            const ps_val_reg = try g.recordField(ps_val_load, "reg");
            const ps_str_inst = try g.callDirect(f_encode_str, &.{ ps_val_reg, ps_ptr_reg, try g.constInt(0) });
            const ps_bytes3 = try g.callDirect(f_append_inst, &.{ ps_bytes2, ps_str_inst });
            const ps_result = try g.record(&.{
                .{ .name = "bytes", .value = ps_bytes3 },
                .{ .name = "ctx", .value = ps_ctx },
            });
            try g.ret(ps_result);
        }

        // IrSyscall: emit MOV x16, BSD_CLASS|num; MOV x0-x5, args; SVC #0x80
        g.beginReservedBlock(blk_not_ptr_store);
        const is_syscall = try g.tagTest(inst, "IrSyscall");
        const blk_syscall = g.reserveBlock();
        const blk_not_syscall = g.reserveBlock();
        try g.branch(is_syscall, blk_syscall, blk_not_syscall);

        g.beginReservedBlock(blk_syscall);
        {
            const sc_payload = try g.tagPayload(inst, "IrSyscall");
            const sc_dst = try g.recordField(sc_payload, "dst");
            const sc_args = try g.recordField(sc_payload, "args");

            // First arg is syscall number
            const sc_num_id = try g.listNth(sc_args, try g.constInt(0));
            const sc_num_raw = try g.callDirect(f_get_reg, &.{ ctx, sc_num_id });
            const c16_sc = try g.constInt(16);
            const c17_sc = try g.constInt(17);
            const sc_num_load = try g.callDirect(f_load_spill, &.{ bytes, sc_num_raw, c17_sc });
            var sc_bytes = try g.recordField(sc_num_load, "bytes");
            const sc_num_reg = try g.recordField(sc_num_load, "reg");

            // MOV x16, syscall_num | 0x2000000 (BSD class)
            // ADD x16, sc_num_reg, #0 first to get it into x16
            const c0_sc = try g.constInt(0);
            const mov_x16 = try g.callDirect(f_encode_add_imm, &.{ c16_sc, sc_num_reg, c0_sc });
            sc_bytes = try g.callDirect(f_append_inst, &.{ sc_bytes, mov_x16 });
            // Now add BSD class: ORR x16, x16, #0x2000000
            // Use MOVK x16, #0x200, LSL #16
            const bsd_hi = try g.constInt(0x200);
            const c16_shift = try g.constInt(16);
            const movk_bsd = try g.callDirect(f_encode_movk, &.{ c16_sc, bsd_hi, c16_shift });
            sc_bytes = try g.callDirect(f_append_inst, &.{ sc_bytes, movk_bsd });

            // Move args 1-6 into x0-x5
            const sc_args_len = try g.listLength(sc_args);
            const one_sc = try g.constInt(1);
            const sc_arg_loop = g.reserveBlock();
            try g.jump(sc_arg_loop, &.{ one_sc, sc_bytes });

            g.beginReservedBlock(sc_arg_loop);
            const sc_ai = try g.addBlockParam();
            const sc_ab = try g.addBlockParam();
            const sc_ai_done = try g.ge(sc_ai, sc_args_len);
            const sc_arg_body = g.reserveBlock();
            const sc_arg_exit = g.reserveBlock();
            try g.branch(sc_ai_done, sc_arg_exit, sc_arg_body);

            g.beginReservedBlock(sc_arg_body);
            const sc_arg_id = try g.listNth(sc_args, sc_ai);
            const sc_arg_raw = try g.callDirect(f_get_reg, &.{ ctx, sc_arg_id });
            const sc_arg_load = try g.callDirect(f_load_spill, &.{ sc_ab, sc_arg_raw, c17_sc });
            const sc_ab2 = try g.recordField(sc_arg_load, "bytes");
            const sc_arg_reg = try g.recordField(sc_arg_load, "reg");
            // MOV x(ai-1), arg_reg — target register is ai-1 (args[1]→x0, args[2]→x1, etc.)
            const sc_target_reg = try g.sub(sc_ai, one_sc);
            const sc_mov_arg = try g.callDirect(f_encode_add_imm, &.{ sc_target_reg, sc_arg_reg, c0_sc });
            const sc_ab3 = try g.callDirect(f_append_inst, &.{ sc_ab2, sc_mov_arg });
            const sc_next = try g.add(sc_ai, one_sc);
            try g.jump(sc_arg_loop, &.{ sc_next, sc_ab3 });

            g.beginReservedBlock(sc_arg_exit);
            // Emit SVC #0x80
            const svc_inst = try g.constInt(0xD4001001); // SVC #0x80
            const sc_bytes_svc = try g.callDirect(f_append_inst, &.{ sc_ab, svc_inst });

            // Move result from x0 to dst register (use x17 as temp for spill safety)
            const sc_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, sc_dst });
            const sc_dst_reg = try g.recordField(sc_alloc, "reg");
            const sc_ctx2 = try g.recordField(sc_alloc, "ctx");
            const c0_result = try g.constInt(0);
            const c0_imm = try g.constInt(0);
            const c17_result = try g.constInt(17);
            // MOV x17, x0: ADD x17, x0, #0
            const sc_mov_to_tmp = try g.callDirect(f_encode_add_imm, &.{ c17_result, c0_result, c0_imm });
            const sc_bytes_tmp = try g.callDirect(f_append_inst, &.{ sc_bytes_svc, sc_mov_to_tmp });
            // Move x17 to dst (physical or spill)
            const c100_sc2 = try g.constInt(100);
            const sc_dst_spilled = try g.ge(sc_dst_reg, c100_sc2);
            const sc_dst_sp = g.reserveBlock();
            const sc_dst_ph = g.reserveBlock();
            const sc_dst_mg = g.reserveBlock();
            try g.branch(sc_dst_spilled, sc_dst_sp, sc_dst_ph);

            g.beginReservedBlock(sc_dst_ph);
            const sc_mov_phys = try g.callDirect(f_encode_add_imm, &.{ sc_dst_reg, c17_result, c0_imm });
            const sc_bp = try g.callDirect(f_append_inst, &.{ sc_bytes_tmp, sc_mov_phys });
            try g.jump(sc_dst_mg, &.{sc_bp});

            g.beginReservedBlock(sc_dst_sp);
            const sc_bs = try g.callDirect(f_store_spill, &.{ sc_bytes_tmp, sc_dst_reg, c17_result });
            try g.jump(sc_dst_mg, &.{sc_bs});

            g.beginReservedBlock(sc_dst_mg);
            const sc_bytes_final = try g.addBlockParam();
            const sc_result = try g.record(&.{
                .{ .name = "bytes", .value = sc_bytes_final },
                .{ .name = "ctx", .value = sc_ctx2 },
            });
            try g.ret(sc_result);
        }

        // IrStrPtr: pass-through — strings are already pointers in registers
        g.beginReservedBlock(blk_not_syscall);
        const is_str_ptr = try g.tagTest(inst, "IrStrPtr");
        const blk_str_ptr = g.reserveBlock();
        const blk_default = g.reserveBlock();
        try g.branch(is_str_ptr, blk_str_ptr, blk_default);

        g.beginReservedBlock(blk_str_ptr);
        {
            const sp_payload = try g.tagPayload(inst, "IrStrPtr");
            const sp_dst = try g.recordField(sp_payload, "dst");
            const sp_value = try g.recordField(sp_payload, "value");
            // Allocate dst register
            const sp_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, sp_dst });
            const sp_dst_reg_raw = try g.recordField(sp_alloc, "reg");
            const sp_ctx = try g.recordField(sp_alloc, "ctx");
            // Get the descriptor register
            const sp_val_raw = try g.callDirect(f_get_reg, &.{ sp_ctx, sp_value });
            const c16_sp = try g.constInt(16);
            const c17_sp = try g.constInt(17);
            // Load descriptor into x16 (if spilled)
            const sp_load = try g.callDirect(f_load_spill, &.{ bytes, sp_val_raw, c16_sp });
            const sp_bytes = try g.recordField(sp_load, "bytes");
            const sp_val_reg = try g.recordField(sp_load, "reg");
            // Use x17 as dst temp (in case dst is spilled)
            const c0_sp = try g.constInt(0);
            const sp_ldr = try g.callDirect(f_encode_ldr, &.{ c17_sp, sp_val_reg, c0_sp });
            const sp_bytes2 = try g.callDirect(f_append_inst, &.{ sp_bytes, sp_ldr });
            // Store x17 to dst (spill or physical)
            const c100_sp = try g.constInt(100);
            const sp_is_spilled = try g.ge(sp_dst_reg_raw, c100_sp);
            const sp_spill_blk = g.reserveBlock();
            const sp_phys_blk = g.reserveBlock();
            const sp_merge_blk = g.reserveBlock();
            try g.branch(sp_is_spilled, sp_spill_blk, sp_phys_blk);

            g.beginReservedBlock(sp_phys_blk);
            // MOV dst_reg, x17
            const sp_mov = try g.callDirect(f_encode_add_imm, &.{ sp_dst_reg_raw, c17_sp, c0_sp });
            const sp_bytes_p = try g.callDirect(f_append_inst, &.{ sp_bytes2, sp_mov });
            try g.jump(sp_merge_blk, &.{sp_bytes_p});

            g.beginReservedBlock(sp_spill_blk);
            // STR x17, [sp, #offset]
            const sp_bytes_s = try g.callDirect(f_store_spill, &.{ sp_bytes2, sp_dst_reg_raw, c17_sp });
            try g.jump(sp_merge_blk, &.{sp_bytes_s});

            g.beginReservedBlock(sp_merge_blk);
            const sp_bytes3 = try g.addBlockParam();
            const sp_result = try g.record(&.{
                .{ .name = "bytes", .value = sp_bytes3 },
                .{ .name = "ctx", .value = sp_ctx },
            });
            try g.ret(sp_result);
        }

        // IrMemStore8: STRB value, [addr] — __mem_store8(addr, val)
        g.beginReservedBlock(blk_default);
        const is_ms8 = try g.tagTest(inst, "IrMemStore8");
        const blk_ms8 = g.reserveBlock();
        const blk_not_ms8 = g.reserveBlock();
        try g.branch(is_ms8, blk_ms8, blk_not_ms8);

        g.beginReservedBlock(blk_ms8);
        {
            const ms_payload = try g.tagPayload(inst, "IrMemStore8");
            const ms_dst = try g.recordField(ms_payload, "dst");
            const ms_args = try g.recordField(ms_payload, "args");
            const ms_addr_id = try g.listNth(ms_args, try g.constInt(0));
            const ms_val_id = try g.listNth(ms_args, try g.constInt(1));
            // Allocate dst to keep counter in sync
            const ms_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ms_dst });
            const ms_ctx = try g.recordField(ms_alloc, "ctx");
            const ms_addr_raw = try g.callDirect(f_get_reg, &.{ ms_ctx, ms_addr_id });
            const ms_val_raw = try g.callDirect(f_get_reg, &.{ ms_ctx, ms_val_id });
            const c16_ms = try g.constInt(16);
            const c17_ms = try g.constInt(17);
            const ms_addr_load = try g.callDirect(f_load_spill, &.{ bytes, ms_addr_raw, c16_ms });
            const ms_bytes1 = try g.recordField(ms_addr_load, "bytes");
            const ms_addr_reg = try g.recordField(ms_addr_load, "reg");
            const ms_val_load = try g.callDirect(f_load_spill, &.{ ms_bytes1, ms_val_raw, c17_ms });
            const ms_bytes2 = try g.recordField(ms_val_load, "bytes");
            const ms_val_reg = try g.recordField(ms_val_load, "reg");
            const ms_base = try g.constInt(0x39000000);
            const c5_ms = try g.constInt(5);
            const ms_rn_shifted = try g.binary(.shl, ms_addr_reg, c5_ms);
            const ms_enc1 = try g.binary(.bit_or, ms_base, ms_rn_shifted);
            const ms_enc2 = try g.binary(.bit_or, ms_enc1, ms_val_reg);
            const ms_bytes3 = try g.callDirect(f_append_inst, &.{ ms_bytes2, ms_enc2 });
            try g.ret(try g.record(&.{ .{ .name = "bytes", .value = ms_bytes3 }, .{ .name = "ctx", .value = ms_ctx } }));
        }

        // IrMemLoad8: LDRB dst, [addr] — __mem_load8(addr)
        g.beginReservedBlock(blk_not_ms8);
        const is_ml8 = try g.tagTest(inst, "IrMemLoad8");
        const blk_ml8 = g.reserveBlock();
        const blk_not_ml8 = g.reserveBlock();
        try g.branch(is_ml8, blk_ml8, blk_not_ml8);

        g.beginReservedBlock(blk_ml8);
        {
            const ml_payload = try g.tagPayload(inst, "IrMemLoad8");
            const ml_dst = try g.recordField(ml_payload, "dst");
            const ml_args = try g.recordField(ml_payload, "args");
            const ml_addr_id = try g.listNth(ml_args, try g.constInt(0));
            const ml_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ml_dst });
            const ml_dst_reg_raw = try g.recordField(ml_alloc, "reg");
            const ml_ctx = try g.recordField(ml_alloc, "ctx");
            const ml_addr_raw = try g.callDirect(f_get_reg, &.{ ml_ctx, ml_addr_id });
            const c16_ml = try g.constInt(16);
            const c17_ml = try g.constInt(17);
            const ml_load = try g.callDirect(f_load_spill, &.{ bytes, ml_addr_raw, c16_ml });
            const ml_bytes1 = try g.recordField(ml_load, "bytes");
            const ml_addr_reg = try g.recordField(ml_load, "reg");
            // LDRB x17, [addr_reg] — always use x17 as temp dst
            const ml_base = try g.constInt(0x39400000);
            const c5_ml = try g.constInt(5);
            const ml_rn_shifted = try g.binary(.shl, ml_addr_reg, c5_ml);
            const ml_enc1 = try g.binary(.bit_or, ml_base, ml_rn_shifted);
            const ml_enc2 = try g.binary(.bit_or, ml_enc1, c17_ml);
            const ml_bytes2 = try g.callDirect(f_append_inst, &.{ ml_bytes1, ml_enc2 });
            // Store x17 to dst (physical or spill)
            const c100_ml = try g.constInt(100);
            const ml_spilled = try g.ge(ml_dst_reg_raw, c100_ml);
            const ml_sp_blk = g.reserveBlock();
            const ml_ph_blk = g.reserveBlock();
            const ml_mg_blk = g.reserveBlock();
            try g.branch(ml_spilled, ml_sp_blk, ml_ph_blk);

            g.beginReservedBlock(ml_ph_blk);
            const c0_ml = try g.constInt(0);
            const ml_mov = try g.callDirect(f_encode_add_imm, &.{ ml_dst_reg_raw, c17_ml, c0_ml });
            const ml_bp = try g.callDirect(f_append_inst, &.{ ml_bytes2, ml_mov });
            try g.jump(ml_mg_blk, &.{ml_bp});

            g.beginReservedBlock(ml_sp_blk);
            const ml_bs = try g.callDirect(f_store_spill, &.{ ml_bytes2, ml_dst_reg_raw, c17_ml });
            try g.jump(ml_mg_blk, &.{ml_bs});

            g.beginReservedBlock(ml_mg_blk);
            const ml_bytes3 = try g.addBlockParam();
            try g.ret(try g.record(&.{ .{ .name = "bytes", .value = ml_bytes3 }, .{ .name = "ctx", .value = ml_ctx } }));
        }

        // IrMemStore64: STR value, [addr] — __mem_store64(addr, val)
        g.beginReservedBlock(blk_not_ml8);
        const is_ms64 = try g.tagTest(inst, "IrMemStore64");
        const blk_ms64 = g.reserveBlock();
        const blk_not_ms64 = g.reserveBlock();
        try g.branch(is_ms64, blk_ms64, blk_not_ms64);

        g.beginReservedBlock(blk_ms64);
        {
            const ms64_payload = try g.tagPayload(inst, "IrMemStore64");
            const ms64_dst = try g.recordField(ms64_payload, "dst");
            const ms64_args = try g.recordField(ms64_payload, "args");
            const ms64_addr_id = try g.listNth(ms64_args, try g.constInt(0));
            const ms64_val_id = try g.listNth(ms64_args, try g.constInt(1));
            // Allocate dst register to keep counter in sync with lowerer
            const ms64_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ms64_dst });
            const ms64_ctx = try g.recordField(ms64_alloc, "ctx");
            const ms64_addr_raw = try g.callDirect(f_get_reg, &.{ ms64_ctx, ms64_addr_id });
            const ms64_val_raw = try g.callDirect(f_get_reg, &.{ ms64_ctx, ms64_val_id });
            const c16_ms64 = try g.constInt(16);
            const c17_ms64 = try g.constInt(17);
            const ms64_al = try g.callDirect(f_load_spill, &.{ bytes, ms64_addr_raw, c16_ms64 });
            const ms64_b1 = try g.recordField(ms64_al, "bytes");
            const ms64_ar = try g.recordField(ms64_al, "reg");
            const ms64_vl = try g.callDirect(f_load_spill, &.{ ms64_b1, ms64_val_raw, c17_ms64 });
            const ms64_b2 = try g.recordField(ms64_vl, "bytes");
            const ms64_vr = try g.recordField(ms64_vl, "reg");
            const c0_ms64 = try g.constInt(0);
            const ms64_enc = try g.callDirect(f_encode_str, &.{ ms64_vr, ms64_ar, c0_ms64 });
            const ms64_b3 = try g.callDirect(f_append_inst, &.{ ms64_b2, ms64_enc });
            try g.ret(try g.record(&.{ .{ .name = "bytes", .value = ms64_b3 }, .{ .name = "ctx", .value = ms64_ctx } }));
        }

        // IrMemLoad64: LDR dst, [addr] — __mem_load64(addr)
        g.beginReservedBlock(blk_not_ms64);
        const is_ml64 = try g.tagTest(inst, "IrMemLoad64");
        const blk_ml64 = g.reserveBlock();
        const blk_not_ml64 = g.reserveBlock();
        try g.branch(is_ml64, blk_ml64, blk_not_ml64);

        g.beginReservedBlock(blk_ml64);
        {
            const ml64_payload = try g.tagPayload(inst, "IrMemLoad64");
            const ml64_dst = try g.recordField(ml64_payload, "dst");
            const ml64_args = try g.recordField(ml64_payload, "args");
            const ml64_addr_id = try g.listNth(ml64_args, try g.constInt(0));
            const ml64_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ml64_dst });
            const ml64_dst_reg_raw = try g.recordField(ml64_alloc, "reg");
            const ml64_ctx = try g.recordField(ml64_alloc, "ctx");
            const ml64_addr_raw = try g.callDirect(f_get_reg, &.{ ml64_ctx, ml64_addr_id });
            const c16_ml64 = try g.constInt(16);
            const c17_ml64 = try g.constInt(17);
            const ml64_load = try g.callDirect(f_load_spill, &.{ bytes, ml64_addr_raw, c16_ml64 });
            const ml64_b1 = try g.recordField(ml64_load, "bytes");
            const ml64_ar = try g.recordField(ml64_load, "reg");
            // LDR x17, [addr_reg, #0] — always use x17 as temp dst
            const c0_ml64 = try g.constInt(0);
            const ml64_enc = try g.callDirect(f_encode_ldr, &.{ c17_ml64, ml64_ar, c0_ml64 });
            const ml64_b2 = try g.callDirect(f_append_inst, &.{ ml64_b1, ml64_enc });
            // Move x17 to dst (physical or spill)
            const c100_ml64 = try g.constInt(100);
            const ml64_spilled = try g.ge(ml64_dst_reg_raw, c100_ml64);
            const ml64_sp = g.reserveBlock();
            const ml64_ph = g.reserveBlock();
            const ml64_mg = g.reserveBlock();
            try g.branch(ml64_spilled, ml64_sp, ml64_ph);

            g.beginReservedBlock(ml64_ph);
            const ml64_mov = try g.callDirect(f_encode_add_imm, &.{ ml64_dst_reg_raw, c17_ml64, c0_ml64 });
            const ml64_bp = try g.callDirect(f_append_inst, &.{ ml64_b2, ml64_mov });
            try g.jump(ml64_mg, &.{ml64_bp});

            g.beginReservedBlock(ml64_sp);
            const ml64_bs = try g.callDirect(f_store_spill, &.{ ml64_b2, ml64_dst_reg_raw, c17_ml64 });
            try g.jump(ml64_mg, &.{ml64_bs});

            g.beginReservedBlock(ml64_mg);
            const ml64_b3 = try g.addBlockParam();
            try g.ret(try g.record(&.{ .{ .name = "bytes", .value = ml64_b3 }, .{ .name = "ctx", .value = ml64_ctx } }));
        }

        // IrBumpAlloc: MOV dst, x28; ADD x28, x28, size — __bump_alloc(size)
        g.beginReservedBlock(blk_not_ml64);
        const is_ba = try g.tagTest(inst, "IrBumpAlloc");
        const blk_ba = g.reserveBlock();
        const blk_not_ba = g.reserveBlock();
        try g.branch(is_ba, blk_ba, blk_not_ba);

        g.beginReservedBlock(blk_ba);
        {
            const ba_payload = try g.tagPayload(inst, "IrBumpAlloc");
            const ba_dst = try g.recordField(ba_payload, "dst");
            const ba_args = try g.recordField(ba_payload, "args");
            const ba_size_id = try g.listNth(ba_args, try g.constInt(0));
            const ba_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, ba_dst });
            const ba_dst_reg_raw = try g.recordField(ba_alloc, "reg");
            const ba_ctx = try g.recordField(ba_alloc, "ctx");
            const ba_size_raw = try g.callDirect(f_get_reg, &.{ ba_ctx, ba_size_id });
            const c16_ba = try g.constInt(16);
            const c17_ba = try g.constInt(17);
            const ba_load = try g.callDirect(f_load_spill, &.{ bytes, ba_size_raw, c16_ba });
            const ba_b1 = try g.recordField(ba_load, "bytes");
            const ba_size_reg = try g.recordField(ba_load, "reg");
            // MOV x17, x28 → ADD x17, x28, #0 (use x17 as temp dst)
            const c28_ba = try g.constInt(28);
            const c0_ba = try g.constInt(0);
            const ba_mov = try g.callDirect(f_encode_add_imm, &.{ c17_ba, c28_ba, c0_ba });
            const ba_b2 = try g.callDirect(f_append_inst, &.{ ba_b1, ba_mov });
            // ADD x28, x28, size_reg
            const ba_add = try g.callDirect(f_encode_add_reg, &.{ c28_ba, c28_ba, ba_size_reg });
            const ba_b3 = try g.callDirect(f_append_inst, &.{ ba_b2, ba_add });
            // Move x17 to dst (physical or spill)
            const c100_ba = try g.constInt(100);
            const ba_spilled = try g.ge(ba_dst_reg_raw, c100_ba);
            const ba_sp = g.reserveBlock();
            const ba_ph = g.reserveBlock();
            const ba_mg = g.reserveBlock();
            try g.branch(ba_spilled, ba_sp, ba_ph);

            g.beginReservedBlock(ba_ph);
            const ba_movd = try g.callDirect(f_encode_add_imm, &.{ ba_dst_reg_raw, c17_ba, c0_ba });
            const ba_bp = try g.callDirect(f_append_inst, &.{ ba_b3, ba_movd });
            try g.jump(ba_mg, &.{ba_bp});

            g.beginReservedBlock(ba_sp);
            const ba_bs = try g.callDirect(f_store_spill, &.{ ba_b3, ba_dst_reg_raw, c17_ba });
            try g.jump(ba_mg, &.{ba_bs});

            g.beginReservedBlock(ba_mg);
            const ba_b4 = try g.addBlockParam();
            try g.ret(try g.record(&.{ .{ .name = "bytes", .value = ba_b4 }, .{ .name = "ctx", .value = ba_ctx } }));
        }

        // IrStrLen: load string length from descriptor[8]
        g.beginReservedBlock(blk_not_ba);
        const is_str_len = try g.tagTest(inst, "IrStrLen");
        const blk_str_len = g.reserveBlock();
        const blk_real_default = g.reserveBlock();
        try g.branch(is_str_len, blk_str_len, blk_real_default);

        g.beginReservedBlock(blk_str_len);
        {
            const sl_payload = try g.tagPayload(inst, "IrStrLen");
            const sl_dst = try g.recordField(sl_payload, "dst");
            const sl_value = try g.recordField(sl_payload, "value");
            const sl_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, sl_dst });
            const sl_dst_reg_raw = try g.recordField(sl_alloc, "reg");
            const sl_ctx = try g.recordField(sl_alloc, "ctx");
            const sl_val_raw = try g.callDirect(f_get_reg, &.{ sl_ctx, sl_value });
            const c16_sl = try g.constInt(16);
            const c17_sl = try g.constInt(17);
            const sl_load = try g.callDirect(f_load_spill, &.{ bytes, sl_val_raw, c16_sl });
            const sl_bytes = try g.recordField(sl_load, "bytes");
            const sl_val_reg = try g.recordField(sl_load, "reg");
            // LDR x17, [descriptor, #8] — use x17 as temp dst
            const c8_sl = try g.constInt(8);
            const sl_ldr = try g.callDirect(f_encode_ldr, &.{ c17_sl, sl_val_reg, c8_sl });
            const sl_bytes2 = try g.callDirect(f_append_inst, &.{ sl_bytes, sl_ldr });
            // Move x17 to dst (physical or spill)
            const c100_sl = try g.constInt(100);
            const c0_sl = try g.constInt(0);
            const sl_spilled = try g.ge(sl_dst_reg_raw, c100_sl);
            const sl_sp = g.reserveBlock();
            const sl_ph = g.reserveBlock();
            const sl_mg = g.reserveBlock();
            try g.branch(sl_spilled, sl_sp, sl_ph);

            g.beginReservedBlock(sl_ph);
            const sl_mov = try g.callDirect(f_encode_add_imm, &.{ sl_dst_reg_raw, c17_sl, c0_sl });
            const sl_bp = try g.callDirect(f_append_inst, &.{ sl_bytes2, sl_mov });
            try g.jump(sl_mg, &.{sl_bp});

            g.beginReservedBlock(sl_sp);
            const sl_bs = try g.callDirect(f_store_spill, &.{ sl_bytes2, sl_dst_reg_raw, c17_sl });
            try g.jump(sl_mg, &.{sl_bs});

            g.beginReservedBlock(sl_mg);
            const sl_bytes3 = try g.addBlockParam();
            const sl_result = try g.record(&.{
                .{ .name = "bytes", .value = sl_bytes3 },
                .{ .name = "ctx", .value = sl_ctx },
            });
            try g.ret(sl_result);
        }

        // Default fallthrough: return bytes unchanged
        g.beginReservedBlock(blk_real_default);
        const ft_result = try g.record(&.{
            .{ .name = "bytes", .value = bytes },
            .{ .name = "ctx", .value = ctx },
        });
        try g.ret(ft_result);
    }
    try g.endReservedFunc(f_emit_inst);

    // ── ec_emit_term(term, bytes, ctx) -> {bytes, ctx} ───────────────
    // Emit machine code for a terminator.
    try g.beginReservedFunc("ec_emit_term");
    {
        _ = g.beginBlock();
        const term = try g.addParam();
        const bytes = try g.addParam();
        const ctx = try g.addParam();

        // Check IrRet
        const is_ret = try g.tagTest(term, ir_ret);
        const blk_ret = g.reserveBlock();
        const blk_not_ret = g.reserveBlock();
        try g.branch(is_ret, blk_ret, blk_not_ret);

        // IrRet: {value} -> MOV x0, Xvalue; epilogue; RET
        g.beginReservedBlock(blk_ret);
        const ret_payload = try g.tagPayload(term, ir_ret);
        const ret_val_id = try g.recordField(ret_payload, "value");
        const ret_reg_raw = try g.callDirect(f_get_reg, &.{ ctx, ret_val_id });
        // Load from spill slot if needed
        const c16_ret = try g.constInt(16);
        const ret_load = try g.callDirect(f_load_spill, &.{ bytes, ret_reg_raw, c16_ret });
        const ret_bytes_loaded = try g.recordField(ret_load, "bytes");
        const ret_reg = try g.recordField(ret_load, "reg");
        // MOV x0, Xn: ADD x0, Xn, #0
        const c0_v = try g.constInt(0);
        const is_x0 = try g.eq(ret_reg, c0_v);
        const blk_need_mov = g.reserveBlock();
        const blk_skip_mov = g.reserveBlock();
        const blk_after_mov = g.reserveBlock();
        try g.branch(is_x0, blk_skip_mov, blk_need_mov);

        g.beginReservedBlock(blk_need_mov);
        const mov_inst = try g.callDirect(f_encode_add_imm, &.{ c0_v, ret_reg, c0_v });
        const ret_b1 = try g.callDirect(f_append_inst, &.{ ret_bytes_loaded, mov_inst });
        try g.jump(blk_after_mov, &.{ret_b1});

        g.beginReservedBlock(blk_skip_mov);
        try g.jump(blk_after_mov, &.{ret_bytes_loaded});

        g.beginReservedBlock(blk_after_mov);
        const ret_bytes = try g.addBlockParam();
        const ret_result = try g.record(&.{
            .{ .name = "bytes", .value = ret_bytes },
            .{ .name = "ctx", .value = ctx },
        });
        try g.ret(ret_result);

        // Not ret: check IrJump
        g.beginReservedBlock(blk_not_ret);
        const is_jump = try g.tagTest(term, ir_jump);
        const blk_jump = g.reserveBlock();
        const blk_not_jump = g.reserveBlock();
        try g.branch(is_jump, blk_jump, blk_not_jump);

        // IrJump: {target, args} -> move args to x0..xN, B target
        g.beginReservedBlock(blk_jump);
        {
            const jmp_payload = try g.tagPayload(term, ir_jump);
            const jmp_target = try g.recordField(jmp_payload, "target");
            const jmp_args = try g.recordField(jmp_payload, "args");
            const jmp_num_args = try g.listLength(jmp_args);

            // Move args to x0, x1, ... (block param convention)
            const jc0 = try g.constInt(0);
            const jmp_args_loop = g.reserveBlock();
            try g.jump(jmp_args_loop, &.{ jc0, bytes, ctx });

            g.beginReservedBlock(jmp_args_loop);
            const ji = try g.addBlockParam();
            const jb = try g.addBlockParam();
            const jc = try g.addBlockParam();
            const j_args_done = try g.ge(ji, jmp_num_args);
            const j_args_exit = g.reserveBlock();
            const j_args_body = g.reserveBlock();
            try g.branch(j_args_done, j_args_exit, j_args_body);

            g.beginReservedBlock(j_args_body);
            {
                const j_arg_id = try g.listNth(jmp_args, ji);
                const j_arg_reg_raw = try g.callDirect(f_get_reg, &.{ jc, j_arg_id });
                // Load from spill if needed
                const c16_j = try g.constInt(16);
                const j_load = try g.callDirect(f_load_spill, &.{ jb, j_arg_reg_raw, c16_j });
                const jb_loaded = try g.recordField(j_load, "bytes");
                const j_arg_reg = try g.recordField(j_load, "reg");
                // Move to x0+i (block param register)
                const j_need_mov = try g.ne(j_arg_reg, ji);
                const j_do_mov = g.reserveBlock();
                const j_skip_mov = g.reserveBlock();
                const j_after_mov = g.reserveBlock();
                try g.branch(j_need_mov, j_do_mov, j_skip_mov);

                g.beginReservedBlock(j_do_mov);
                const jc0m = try g.constInt(0);
                const j_mov = try g.callDirect(f_encode_add_imm, &.{ ji, j_arg_reg, jc0m });
                const j_mb = try g.callDirect(f_append_inst, &.{ jb_loaded, j_mov });
                try g.jump(j_after_mov, &.{j_mb});

                g.beginReservedBlock(j_skip_mov);
                try g.jump(j_after_mov, &.{jb_loaded});

                g.beginReservedBlock(j_after_mov);
                const jb2 = try g.addBlockParam();
                const j_one = try g.constInt(1);
                const j_next = try g.add(ji, j_one);
                try g.jump(jmp_args_loop, &.{ j_next, jb2, jc });
            }

            // Emit B to target block
            g.beginReservedBlock(j_args_exit);
            {
                const j_bo = try g.recordField(jc, "block_offsets");
                const j_bs = try g.recordField(jc, "blocks_start");
                const j_tgt_str = try g.callBuiltin("string_from_int", &.{jmp_target});
                const j_tgt_off = try g.mapGet(j_bo, j_tgt_str);
                // target_abs = blocks_start + block_offsets[target]
                const j_tgt_abs = try g.add(j_bs, j_tgt_off);
                // current_abs = bytes_length(bytes)
                const j_cur_abs = try g.callBuiltin("bytes_length", &.{jb});
                // rel = target_abs - current_abs
                const j_rel = try g.sub(j_tgt_abs, j_cur_abs);
                const j_b_enc = try g.callDirect(f_encode_b, &.{j_rel});
                const j_final = try g.callDirect(f_append_inst, &.{ jb, j_b_enc });
                const j_result = try g.record(&.{
                    .{ .name = "bytes", .value = j_final },
                    .{ .name = "ctx", .value = jc },
                });
                try g.ret(j_result);
            }
        }

        // Not jump: check IrBranch
        g.beginReservedBlock(blk_not_jump);
        const is_branch = try g.tagTest(term, ir_branch);
        const blk_branch = g.reserveBlock();
        const blk_default = g.reserveBlock();
        try g.branch(is_branch, blk_branch, blk_default);

        // IrBranch: {cond, then_blk, else_blk}
        // Emit: CBZ cond_reg, else_offset (skip to else if cond==0/false)
        // Then block follows immediately (fall-through)
        g.beginReservedBlock(blk_branch);
        {
            const br_payload = try g.tagPayload(term, ir_branch);
            const br_cond = try g.recordField(br_payload, "cond");
            const br_else = try g.recordField(br_payload, "else_blk");

            const br_cond_reg_raw = try g.callDirect(f_get_reg, &.{ ctx, br_cond });
            // Load from spill if needed
            const c16_br = try g.constInt(16);
            const br_load = try g.callDirect(f_load_spill, &.{ bytes, br_cond_reg_raw, c16_br });
            const br_bytes_loaded = try g.recordField(br_load, "bytes");
            const br_cond_reg = try g.recordField(br_load, "reg");

            // Compute offset to else block
            const br_bo = try g.recordField(ctx, "block_offsets");
            const br_bs = try g.recordField(ctx, "blocks_start");
            const br_else_str = try g.callBuiltin("string_from_int", &.{br_else});
            const br_else_off = try g.mapGet(br_bo, br_else_str);
            const br_else_abs = try g.add(br_bs, br_else_off);
            const br_cur_abs = try g.callBuiltin("bytes_length", &.{br_bytes_loaded});
            const br_rel = try g.sub(br_else_abs, br_cur_abs);

            // CBZ Xt, offset: branch if cond==0 (false) to else
            // 0xB4000000 | ((offset/4 & 0x7FFFF) << 5) | Xt
            const cbz_base = try g.constInt(0xB4000000);
            const cbz_c4 = try g.constInt(4);
            const cbz_mask = try g.constInt(0x7FFFF);
            const cbz_c5 = try g.constInt(5);
            const cbz_off_div = try g.binary(.div, br_rel, cbz_c4);
            const cbz_off_masked = try g.binary(.bit_and, cbz_off_div, cbz_mask);
            const cbz_off_shifted = try g.binary(.shl, cbz_off_masked, cbz_c5);
            const cbz_r1 = try g.binary(.bit_or, cbz_base, cbz_off_shifted);
            const cbz_enc = try g.binary(.bit_or, cbz_r1, br_cond_reg);
            const br_bytes = try g.callDirect(f_append_inst, &.{ br_bytes_loaded, cbz_enc });
            // Then block is next (fall-through), no need for extra B
            const br_result = try g.record(&.{
                .{ .name = "bytes", .value = br_bytes },
                .{ .name = "ctx", .value = ctx },
            });
            try g.ret(br_result);
        }

        // Default: return bytes unchanged
        g.beginReservedBlock(blk_default);
        const def_result = try g.record(&.{
            .{ .name = "bytes", .value = bytes },
            .{ .name = "ctx", .value = ctx },
        });
        try g.ret(def_result);
    }
    try g.endReservedFunc(f_emit_term);

    // ── ec_emit_block(block, bytes, ctx) -> {bytes, ctx} ─────────────
    // Emit all instructions in a block, then the terminator.
    try g.beginReservedFunc("ec_emit_block");
    {
        _ = g.beginBlock();
        const block = try g.addParam();
        const bytes = try g.addParam();
        const ctx = try g.addParam();

        const insts = try g.recordField(block, "insts");
        const term = try g.recordField(block, "term");
        const num_insts = try g.listLength(insts);

        // Loop over instructions
        const c0 = try g.constInt(0);
        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ c0, bytes, ctx });

        g.beginReservedBlock(loop_blk);
        const idx = try g.addBlockParam();
        const cur_bytes = try g.addBlockParam();
        const cur_ctx = try g.addBlockParam();

        const done = try g.ge(idx, num_insts);
        const blk_done = g.reserveBlock();
        const blk_body = g.reserveBlock();
        try g.branch(done, blk_done, blk_body);

        g.beginReservedBlock(blk_body);
        const inst_val = try g.listNth(insts, idx);
        const inst_result = try g.callDirect(f_emit_inst, &.{ inst_val, cur_bytes, cur_ctx });
        const new_bytes = try g.recordField(inst_result, "bytes");
        const new_ctx = try g.recordField(inst_result, "ctx");
        const c1 = try g.constInt(1);
        const next_idx = try g.add(idx, c1);
        try g.jump(loop_blk, &.{ next_idx, new_bytes, new_ctx });

        // Done: emit terminator
        g.beginReservedBlock(blk_done);
        const term_result = try g.callDirect(f_emit_term, &.{ term, cur_bytes, cur_ctx });
        try g.ret(term_result);
    }
    try g.endReservedFunc(f_emit_block);

    // ── ec_emit_func(func, code, ctx) -> {code, ctx} ────────────────
    // Emit prologue, all blocks, epilogue for a function.
    try g.beginReservedFunc("ec_emit_func");
    {
        _ = g.beginBlock();
        const func = try g.addParam();
        const code = try g.addParam();
        const ctx = try g.addParam();

        // Record function offset in func_map
        const func_name = try g.recordField(func, "name");
        const code_len = try g.callBuiltin("bytes_length", &.{code});
        const func_map = try g.recordField(ctx, "func_map");
        const new_func_map = try g.mapSet(func_map, func_name, code_len);

        // Reset reg_map and next_reg for this function
        // Pre-populate reg_map with parameter bindings using actual value IDs from the lowerer
        const params = try g.recordField(func, "params");
        const param_ids = try g.recordField(func, "param_ids");
        const num_params = try g.listLength(params);
        const c0 = try g.constInt(0);
        const init_rm = try g.mapNew();

        const param_loop = g.reserveBlock();
        try g.jump(param_loop, &.{ c0, init_rm });

        g.beginReservedBlock(param_loop);
        const pi = try g.addBlockParam();
        const pi_rm = try g.addBlockParam();
        const pi_done = try g.ge(pi, num_params);
        const param_exit_blk = g.reserveBlock();
        const param_body_blk = g.reserveBlock();
        try g.branch(pi_done, param_exit_blk, param_body_blk);

        g.beginReservedBlock(param_body_blk);
        {
            // Map actual value_id (from lowerer) to callee-saved register x(19+pi)
            const c19_p = try g.constInt(19);
            const callee_reg = try g.add(pi, c19_p);
            const actual_vid = try g.listNth(param_ids, pi);
            const pi_str = try g.callBuiltin("string_from_int", &.{actual_vid});
            const pi_rm2 = try g.mapSet(pi_rm, pi_str, callee_reg);
            const pi_one = try g.constInt(1);
            const pi_next = try g.add(pi, pi_one);
            try g.jump(param_loop, &.{ pi_next, pi_rm2 });
        }

        // Exit the param loop — forward pi_rm to done block via jump
        g.beginReservedBlock(param_exit_blk);
        const param_done_blk = g.reserveBlock();
        try g.jump(param_done_blk, &.{pi_rm});

        g.beginReservedBlock(param_done_blk);
        const func_reg_map = try g.addBlockParam();
        // Emit prologue: save all callee-saved registers
        const c16 = try g.constInt(16);
        const pro_bytes = try g.callDirect(f_emit_prologue, &.{c16});
        const code_after_pro = try g.callBuiltin("bytes_append_bytes", &.{ code, pro_bytes });

        // Move params from x0-x7 (caller-saved) to callee-saved x19+ after prologue
        const mov_param_loop = g.reserveBlock();
        try g.jump(mov_param_loop, &.{ c0, code_after_pro });

        g.beginReservedBlock(mov_param_loop);
        const mpi = try g.addBlockParam();
        const mp_code = try g.addBlockParam();
        const mp_done = try g.ge(mpi, num_params);
        const mp_exit = g.reserveBlock();
        const mp_body = g.reserveBlock();
        try g.branch(mp_done, mp_exit, mp_body);

        g.beginReservedBlock(mp_body);
        {
            // MOV x(19+i), xi: ADD x(19+i), xi, #0
            const c19_m = try g.constInt(19);
            const dst_reg_m = try g.add(mpi, c19_m);
            const c0_m = try g.constInt(0);
            const mov_enc = try g.callDirect(f_encode_add_imm, &.{ dst_reg_m, mpi, c0_m });
            const mp_code2 = try g.callDirect(f_append_inst, &.{ mp_code, mov_enc });
            const mp_one = try g.constInt(1);
            const mp_next = try g.add(mpi, mp_one);
            try g.jump(mov_param_loop, &.{ mp_next, mp_code2 });
        }

        g.beginReservedBlock(mp_exit);
        const code2 = try g.copy(mp_code);

        const blocks = try g.recordField(func, "blocks");
        const num_blocks = try g.listLength(blocks);

        // ── Pass 1: sizing pass to compute block offsets ───────────────
        // Pre-populate block_offsets with 0 for all blocks (avoids forward ref errors)
        const pre_bo = try g.mapNew();
        const pre_loop = g.reserveBlock();
        try g.jump(pre_loop, &.{ c0, pre_bo });

        g.beginReservedBlock(pre_loop);
        const pre_i = try g.addBlockParam();
        const pre_m = try g.addBlockParam();
        const pre_done = try g.ge(pre_i, num_blocks);
        const pre_exit = g.reserveBlock();
        const pre_body = g.reserveBlock();
        try g.branch(pre_done, pre_exit, pre_body);

        g.beginReservedBlock(pre_body);
        {
            const pre_block = try g.listNth(blocks, pre_i);
            const pre_bid = try g.recordField(pre_block, "id");
            const pre_bid_str = try g.callBuiltin("string_from_int", &.{pre_bid});
            const pre_m2 = try g.mapSet(pre_m, pre_bid_str, c0);
            const pre_one = try g.constInt(1);
            const pre_next = try g.add(pre_i, pre_one);
            try g.jump(pre_loop, &.{ pre_next, pre_m2 });
        }

        g.beginReservedBlock(pre_exit);
        const init_bo = try g.copy(pre_m);

        // Emit blocks to a temp buffer; record block_offsets[block.id] = offset
        const temp_bytes = try g.callBuiltin("bytes_new", &.{});
        const sizing_ctx = try g.record(&.{
            .{ .name = "reg_map", .value = func_reg_map },
            .{ .name = "next_reg", .value = num_params },
            .{ .name = "func_map", .value = new_func_map },
            .{ .name = "block_offsets", .value = init_bo },
            .{ .name = "data", .value = try g.recordField(ctx, "data") },
            .{ .name = "data_offsets", .value = try g.recordField(ctx, "data_offsets") },
            .{ .name = "blocks_start", .value = c0 },
            .{ .name = "fields_map", .value = try g.recordField(ctx, "fields_map") },
        });

        const sizing_loop = g.reserveBlock();
        try g.jump(sizing_loop, &.{ c0, temp_bytes, sizing_ctx });

        g.beginReservedBlock(sizing_loop);
        const s_idx = try g.addBlockParam();
        const s_bytes = try g.addBlockParam();
        const s_ctx = try g.addBlockParam();

        const s_done = try g.ge(s_idx, num_blocks);
        const s_exit = g.reserveBlock();
        const s_body = g.reserveBlock();
        try g.branch(s_done, s_exit, s_body);

        g.beginReservedBlock(s_body);
        {
            // Record block offset before emitting
            const s_block = try g.listNth(blocks, s_idx);
            const s_block_id = try g.recordField(s_block, "id");
            const s_block_id_str = try g.callBuiltin("string_from_int", &.{s_block_id});
            const s_cur_off = try g.callBuiltin("bytes_length", &.{s_bytes});
            const s_bo = try g.recordField(s_ctx, "block_offsets");
            const s_new_bo = try g.mapSet(s_bo, s_block_id_str, s_cur_off);
            // Update ctx with new block_offsets
            const s_ctx2 = try g.record(&.{
                .{ .name = "reg_map", .value = try g.recordField(s_ctx, "reg_map") },
                .{ .name = "next_reg", .value = try g.recordField(s_ctx, "next_reg") },
                .{ .name = "func_map", .value = try g.recordField(s_ctx, "func_map") },
                .{ .name = "block_offsets", .value = s_new_bo },
                .{ .name = "data", .value = try g.recordField(s_ctx, "data") },
                .{ .name = "data_offsets", .value = try g.recordField(s_ctx, "data_offsets") },
                .{ .name = "blocks_start", .value = try g.recordField(s_ctx, "blocks_start") },
                .{ .name = "fields_map", .value = try g.recordField(s_ctx, "fields_map") },
            });
            const s_result = try g.callDirect(f_emit_block, &.{ s_block, s_bytes, s_ctx2 });
            const s_new_bytes = try g.recordField(s_result, "bytes");
            const s_new_ctx = try g.recordField(s_result, "ctx");
            const s_one = try g.constInt(1);
            const s_next = try g.add(s_idx, s_one);
            try g.jump(sizing_loop, &.{ s_next, s_new_bytes, s_new_ctx });
        }

        // Pass 1 done: extract block_offsets (relative to blocks start)
        g.beginReservedBlock(s_exit);
        const final_bo = try g.recordField(s_ctx, "block_offsets");

        // ── Pass 2: real emit with correct block offsets ────────────────
        const blocks_start = try g.callBuiltin("bytes_length", &.{code2});
        const real_ctx = try g.record(&.{
            .{ .name = "reg_map", .value = func_reg_map },
            .{ .name = "next_reg", .value = num_params },
            .{ .name = "func_map", .value = new_func_map },
            .{ .name = "block_offsets", .value = final_bo },
            .{ .name = "data", .value = try g.recordField(ctx, "data") },
            .{ .name = "data_offsets", .value = try g.recordField(ctx, "data_offsets") },
            .{ .name = "blocks_start", .value = blocks_start },
            .{ .name = "fields_map", .value = try g.recordField(ctx, "fields_map") },
        });

        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ c0, code2, real_ctx });

        g.beginReservedBlock(loop_blk);
        const b_idx = try g.addBlockParam();
        const cur_code = try g.addBlockParam();
        const cur_ctx = try g.addBlockParam();

        const b_done = try g.ge(b_idx, num_blocks);
        const blk_done = g.reserveBlock();
        const blk_body = g.reserveBlock();
        try g.branch(b_done, blk_done, blk_body);

        g.beginReservedBlock(blk_body);
        const block_val = try g.listNth(blocks, b_idx);
        const block_result = try g.callDirect(f_emit_block, &.{ block_val, cur_code, cur_ctx });
        const new_code = try g.recordField(block_result, "bytes");
        const new_ctx = try g.recordField(block_result, "ctx");
        const c1 = try g.constInt(1);
        const next_b_idx = try g.add(b_idx, c1);
        try g.jump(loop_blk, &.{ next_b_idx, new_code, new_ctx });

        // Done: emit epilogue (restore all callee-saved registers + RET)
        g.beginReservedBlock(blk_done);
        const epi_bytes = try g.callDirect(f_emit_epilogue, &.{c16});
        const code_epi2 = try g.callBuiltin("bytes_append_bytes", &.{ cur_code, epi_bytes });

        const func_result = try g.record(&.{
            .{ .name = "code", .value = code_epi2 },
            .{ .name = "ctx", .value = cur_ctx },
        });
        try g.ret(func_result);
    }
    try g.endReservedFunc(f_emit_func);

    // ── ec_pad_to_page(bytes) -> Bytes ───────────────────────────────
    // Pad bytes to next page boundary (16384).
    try g.beginReservedFunc("ec_pad_to_page");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();
        const len = try g.callBuiltin("bytes_length", &.{bytes});
        const page_size = try g.constInt(16384);
        const remainder = try g.binary(.mod, len, page_size);
        const c0 = try g.constInt(0);
        const is_aligned = try g.eq(remainder, c0);
        const blk_done = g.reserveBlock();
        const blk_pad = g.reserveBlock();
        try g.branch(is_aligned, blk_done, blk_pad);

        g.beginReservedBlock(blk_pad);
        const padding_needed = try g.sub(page_size, remainder);
        // Loop to add zero bytes
        const pad_loop = g.reserveBlock();
        try g.jump(pad_loop, &.{ c0, bytes });

        g.beginReservedBlock(pad_loop);
        const pad_idx = try g.addBlockParam();
        const pad_bytes = try g.addBlockParam();
        const pad_done = try g.ge(pad_idx, padding_needed);
        const blk_pad_done = g.reserveBlock();
        const blk_pad_body = g.reserveBlock();
        try g.branch(pad_done, blk_pad_done, blk_pad_body);

        g.beginReservedBlock(blk_pad_body);
        const new_bytes = try g.callBuiltin("bytes_append_u8", &.{ pad_bytes, c0 });
        const c1 = try g.constInt(1);
        const next_pad_idx = try g.add(pad_idx, c1);
        try g.jump(pad_loop, &.{ next_pad_idx, new_bytes });

        g.beginReservedBlock(blk_pad_done);
        try g.ret(pad_bytes);

        g.beginReservedBlock(blk_done);
        try g.ret(bytes);
    }
    try g.endReservedFunc(f_pad_to_page);

    // ── ec_append_segname(bytes, name) -> Bytes ──────────────────────
    // Append a 16-byte segment/section name (padded with zeros).
    try g.beginReservedFunc("ec_append_segname");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();
        const name = try g.addParam();
        const name_bytes = try g.callBuiltin("string_to_bytes", &.{name});
        const name_len = try g.callBuiltin("bytes_length", &.{name_bytes});
        const c16 = try g.constInt(16);
        const c0 = try g.constInt(0);

        // Append name bytes one at a time
        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ c0, bytes });

        g.beginReservedBlock(loop_blk);
        const idx = try g.addBlockParam();
        const cur = try g.addBlockParam();
        const done = try g.ge(idx, c16);
        const blk_done = g.reserveBlock();
        const blk_body = g.reserveBlock();
        try g.branch(done, blk_done, blk_body);

        g.beginReservedBlock(blk_body);
        // If idx < name_len, append name byte; else append 0
        const in_name = try g.lt(idx, name_len);
        const blk_name_byte = g.reserveBlock();
        const blk_zero_byte = g.reserveBlock();
        try g.branch(in_name, blk_name_byte, blk_zero_byte);

        g.beginReservedBlock(blk_name_byte);
        const name_str = try g.callBuiltin("string_byte_at", &.{ name, idx });
        const cur_with_byte = try g.callBuiltin("bytes_append_u8", &.{ cur, name_str });
        const blk_next = g.reserveBlock();
        try g.jump(blk_next, &.{cur_with_byte});

        g.beginReservedBlock(blk_zero_byte);
        const cur_with_zero = try g.callBuiltin("bytes_append_u8", &.{ cur, c0 });
        try g.jump(blk_next, &.{cur_with_zero});

        g.beginReservedBlock(blk_next);
        const updated = try g.addBlockParam();
        const c1 = try g.constInt(1);
        const next_idx = try g.add(idx, c1);
        try g.jump(loop_blk, &.{ next_idx, updated });

        g.beginReservedBlock(blk_done);
        try g.ret(cur);
    }
    try g.endReservedFunc(f_append_segname);

    // ── ec_append_segment_cmd(bytes, segname, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects) -> Bytes
    // Append an LC_SEGMENT_64 command (72 bytes).
    try g.beginReservedFunc("ec_append_segment_cmd");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();
        const segname = try g.addParam();
        const vmaddr = try g.addParam();
        const vmsize = try g.addParam();
        const fileoff = try g.addParam();
        const filesize = try g.addParam();
        const maxprot = try g.addParam();
        const initprot = try g.addParam();
        const nsects = try g.addParam();

        // cmd = 0x19 (LC_SEGMENT_64)
        const cmd = try g.constInt(0x19);
        // cmdsize = 72 + nsects * 80
        const c72 = try g.constInt(72);
        const c80 = try g.constInt(80);
        const sect_size = try g.binary(.mul, nsects, c80);
        const cmdsize = try g.add(c72, sect_size);

        var b = try g.callBuiltin("bytes_append_u32_le", &.{ bytes, cmd });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, cmdsize });
        b = try g.callDirect(f_append_segname, &.{ b, segname });
        b = try g.callBuiltin("bytes_append_u64_le", &.{ b, vmaddr });
        b = try g.callBuiltin("bytes_append_u64_le", &.{ b, vmsize });
        b = try g.callBuiltin("bytes_append_u64_le", &.{ b, fileoff });
        b = try g.callBuiltin("bytes_append_u64_le", &.{ b, filesize });
        const c0 = try g.constInt(0);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, maxprot });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, initprot });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, nsects });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // flags
        try g.ret(b);
    }
    try g.endReservedFunc(f_append_segment_cmd);

    // ── ec_append_section(bytes, sectname, segname, addr, size, offset, align_val, flags) -> Bytes
    // Append an 80-byte section header.
    try g.beginReservedFunc("ec_append_section");
    {
        _ = g.beginBlock();
        const bytes = try g.addParam();
        const sectname = try g.addParam();
        const segname = try g.addParam();
        const addr = try g.addParam();
        const size = try g.addParam();
        const offset = try g.addParam();
        const align_val = try g.addParam();
        const flags = try g.addParam();

        var b = try g.callDirect(f_append_segname, &.{ bytes, sectname });
        b = try g.callDirect(f_append_segname, &.{ b, segname });
        b = try g.callBuiltin("bytes_append_u64_le", &.{ b, addr });
        b = try g.callBuiltin("bytes_append_u64_le", &.{ b, size });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, offset });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, align_val });
        const c0 = try g.constInt(0);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // reloff
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // nreloc
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, flags });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // reserved1
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // reserved2
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // reserved3
        try g.ret(b);
    }
    try g.endReservedFunc(f_append_section);

    // ── ec_emit_macho(code_len, entry_offset) -> Bytes ──────────────
    // Build a Mach-O header (padded to page boundary). The caller appends
    // code bytes directly after calling this, since there is no bytes_concat.
    // Includes __LINKEDIT, LC_SYMTAB, and LC_CODE_SIGNATURE for ad-hoc signing.
    try g.beginReservedFunc("ec_emit_macho");
    {
        _ = g.beginBlock();
        const code_len = try g.addParam();
        const entry_offset = try g.addParam();

        const page_size = try g.constInt(16384);
        const c0 = try g.constInt(0);

        // text_offset = page_size (code starts after first page)
        const text_offset = try g.copy(page_size);

        // text_vmsize = page_align(code_len), minimum page_size
        const c1 = try g.constInt(1);
        const ps_minus1 = try g.sub(page_size, c1);
        const code_plus = try g.add(code_len, ps_minus1);
        const code_pages = try g.binary(.div, code_plus, page_size);
        const text_vmsize = try g.binary(.mul, code_pages, page_size);

        // __TEXT segment: vmaddr=0x100000000, vmsize=text_offset+text_vmsize
        const base_addr = try g.constInt(0x100000000);
        const text_seg_size = try g.add(text_offset, text_vmsize);

        // code_limit = text_seg_size (everything before __LINKEDIT)
        // sig_size = 109 + ceil(code_limit / 4096) * 32
        const hash_page_size = try g.constInt(4096);
        const c4095 = try g.constInt(4095);
        const cl_plus = try g.add(text_seg_size, c4095);
        const n_code_slots = try g.binary(.div, cl_plus, hash_page_size);
        const c32 = try g.constInt(32);
        const hash_bytes = try g.binary(.mul, n_code_slots, c32);
        const c109 = try g.constInt(109); // 12 + 8 + 88 + 1
        const sig_size = try g.add(c109, hash_bytes);

        // __LINKEDIT: vmaddr after __DATA, fileoff=code_limit, filesize=sig_size
        const linkedit_vmaddr = try g.add(base_addr, try g.add(text_seg_size, page_size));
        const linkedit_vmsize = try g.copy(page_size); // virtual size >= file size, page-aligned

        var b = try g.callBuiltin("bytes_new", &.{});

        // Mach-O header (32 bytes)
        // ncmds=10: PAGEZERO, TEXT, DATA, LINKEDIT, MAIN, LOAD_DYLINKER, LOAD_DYLIB, DYLD_INFO_ONLY, SYMTAB, CODE_SIGNATURE
        // sizeofcmds=648: 72 + 152 + 152 + 72 + 24 + 32 + 56 + 48 + 24 + 16
        const magic = try g.constInt(0xFEEDFACF);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, magic });
        const cputype = try g.constInt(0x0100000C); // ARM64
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, cputype });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // cpusubtype
        const filetype = try g.constInt(2); // MH_EXECUTE
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, filetype });
        const ncmds = try g.constInt(10);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, ncmds });
        const sizeofcmds = try g.constInt(648);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, sizeofcmds });
        const flags = try g.constInt(0x00200085);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, flags });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // reserved

        // LC_SEGMENT_64 __PAGEZERO (72 bytes, no sections)
        const pagezero_name = try g.constString("__PAGEZERO");
        const pagezero_vmsize = try g.constInt(0x100000000);
        b = try g.callDirect(f_append_segment_cmd, &.{
            b, pagezero_name, c0, pagezero_vmsize, c0, c0, c0, c0, c0,
        });

        // LC_SEGMENT_64 __TEXT (72 + 80 = 152 bytes, 1 section)
        const text_name = try g.constString("__TEXT");
        const c5_prot = try g.constInt(5); // r-x
        const c1_sect = try g.constInt(1);
        b = try g.callDirect(f_append_segment_cmd, &.{
            b, text_name, base_addr, text_seg_size, c0, text_seg_size, c5_prot, c5_prot, c1_sect,
        });

        // Section __text in __TEXT
        const sect_text = try g.constString("__text");
        const text_addr = try g.add(base_addr, text_offset);
        const c2_align = try g.constInt(2); // 2^2 = 4 byte alignment
        const text_flags = try g.constInt(0x80000400);
        b = try g.callDirect(f_append_section, &.{
            b, sect_text, text_name, text_addr, code_len, text_offset, c2_align, text_flags,
        });

        // LC_SEGMENT_64 __DATA (72 + 80 = 152 bytes, 1 section, filesize=0)
        const data_name = try g.constString("__DATA");
        const data_vmaddr = try g.add(base_addr, text_seg_size);
        const c3_prot = try g.constInt(3); // rw-
        b = try g.callDirect(f_append_segment_cmd, &.{
            b, data_name, data_vmaddr, page_size, text_seg_size, c0, c3_prot, c3_prot, c1_sect,
        });

        // Section __const in __DATA (empty, no file backing)
        const sect_const = try g.constString("__const");
        b = try g.callDirect(f_append_section, &.{
            b, sect_const, data_name, data_vmaddr, c0, text_seg_size, c2_align, c0,
        });

        // LC_SEGMENT_64 __LINKEDIT (72 bytes, no sections)
        const linkedit_name = try g.constString("__LINKEDIT");
        const c1_prot = try g.constInt(1); // r--
        b = try g.callDirect(f_append_segment_cmd, &.{
            b, linkedit_name, linkedit_vmaddr, linkedit_vmsize, text_seg_size, sig_size, c1_prot, c1_prot, c0,
        });

        // LC_MAIN (24 bytes)
        const lc_main_cmd = try g.constInt(0x80000028);
        const lc_main_size = try g.constInt(24);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_main_cmd });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_main_size });
        const entryoff = try g.add(text_offset, entry_offset);
        b = try g.callBuiltin("bytes_append_u64_le", &.{ b, entryoff });
        b = try g.callBuiltin("bytes_append_u64_le", &.{ b, c0 }); // stacksize

        // LC_SYMTAB (24 bytes) — empty, but required for code signing
        const lc_symtab_cmd = try g.constInt(0x02); // LC_SYMTAB
        const lc_symtab_size = try g.constInt(24);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_symtab_cmd });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_symtab_size });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // symoff
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // nsyms
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // stroff
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // strsize

        // LC_LOAD_DYLINKER (32 bytes)
        // cmd=0x0E, cmdsize=32, name_offset=12, "/usr/lib/dyld\0" + 6 bytes padding
        const lc_dylinker_cmd = try g.constInt(0x0E); // LC_LOAD_DYLINKER
        const lc_dylinker_size = try g.constInt(32);
        const lc_dylinker_off = try g.constInt(12); // offset to string within LC
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_dylinker_cmd });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_dylinker_size });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_dylinker_off });
        // "/usr/lib/dyld" = 13 bytes + null = 14, then 6 bytes padding to reach 20 (32-12)
        const dylinker_str = try g.constString("/usr/lib/dyld");
        const dylinker_bytes = try g.callBuiltin("string_to_bytes", &.{dylinker_str});
        b = try g.callBuiltin("bytes_append_bytes", &.{ b, dylinker_bytes });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 }); // null terminator
        // 6 bytes padding
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });

        // LC_LOAD_DYLIB (56 bytes)
        // cmd=0x0C, cmdsize=56, name_offset=24, timestamp=0, current_ver=0, compat_ver=0
        // "/usr/lib/libSystem.B.dylib\0" = 27 bytes + 5 bytes padding
        const lc_dylib_cmd = try g.constInt(0x0C); // LC_LOAD_DYLIB
        const lc_dylib_size = try g.constInt(56);
        const lc_dylib_off = try g.constInt(24); // offset to string within LC
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_dylib_cmd });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_dylib_size });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_dylib_off });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // timestamp
        const libsys_ver = try g.constInt(0x10000); // current_version 1.0.0
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, libsys_ver });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, libsys_ver }); // compat_version
        const libsys_str = try g.constString("/usr/lib/libSystem.B.dylib");
        const libsys_bytes = try g.callBuiltin("string_to_bytes", &.{libsys_str});
        b = try g.callBuiltin("bytes_append_bytes", &.{ b, libsys_bytes });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 }); // null terminator
        // 5 bytes padding to reach 32 (56-24)
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });
        b = try g.callBuiltin("bytes_append_u8", &.{ b, c0 });

        // LC_DYLD_INFO_ONLY (48 bytes) — all zeros (no rebases, binds, exports)
        const lc_dyld_info_cmd = try g.constInt(0x80000022); // LC_DYLD_INFO_ONLY
        const lc_dyld_info_size = try g.constInt(48);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_dyld_info_cmd });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_dyld_info_size });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // rebase_off
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // rebase_size
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // bind_off
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // bind_size
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // weak_bind_off
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // weak_bind_size
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // lazy_bind_off
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // lazy_bind_size
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // export_off
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, c0 }); // export_size

        // LC_CODE_SIGNATURE (16 bytes)
        const lc_codesig_cmd = try g.constInt(0x1D); // LC_CODE_SIGNATURE
        const lc_codesig_size = try g.constInt(16);
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_codesig_cmd });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, lc_codesig_size });
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, text_seg_size }); // dataoff = code_limit
        b = try g.callBuiltin("bytes_append_u32_le", &.{ b, sig_size }); // datasize

        // Pad header to page boundary
        b = try g.callDirect(f_pad_to_page, &.{b});
        try g.ret(b);
    }
    try g.endReservedFunc(f_emit_macho);

    // ── ec_emit_module(ir_module) -> Bytes ───────────────────────────
    // Entry point: takes IR module repr, produces Mach-O binary.
    // Strategy: first emit all code to a temp buffer (to know code_len),
    // then build Mach-O header, then re-emit code directly into the
    // macho buffer (since there's no bytes_concat builtin).
    try g.beginReservedFunc("ec_emit_module");
    {
        _ = g.beginBlock();
        const ir_mod = try g.addParam();

        const functions = try g.recordField(ir_mod, "functions");
        const entry_name = try g.recordField(ir_mod, "entry");
        const num_funcs = try g.listLength(functions);
        const c0 = try g.constInt(0);

        // Initialize context
        const reg_map = try g.mapNew();
        const func_map = try g.mapNew();
        const block_offsets = try g.mapNew();
        const data = try g.callBuiltin("bytes_new", &.{});
        const data_offsets = try g.mapNew();
        const fields_map = try g.mapNew();
        const init_ctx = try g.record(&.{
            .{ .name = "reg_map", .value = reg_map },
            .{ .name = "next_reg", .value = c0 },
            .{ .name = "func_map", .value = func_map },
            .{ .name = "block_offsets", .value = block_offsets },
            .{ .name = "data", .value = data },
            .{ .name = "data_offsets", .value = data_offsets },
            .{ .name = "blocks_start", .value = c0 },
            .{ .name = "fields_map", .value = fields_map },
        });

        // First pass: emit all functions to get code bytes and context
        // Emit heap init (mmap + store bump pointer in x28) + placeholder B main
        const code_init = try g.callBuiltin("bytes_new", &.{});
        const code_heap = try g.callDirect(f_emit_heap_init, &.{code_init});
        // Append placeholder B instruction (will be patched in pass 2)
        const nop_inst = try g.constInt(0x14000001); // B +4 (branch over self = NOP)
        const code = try g.callDirect(f_append_inst, &.{ code_heap, nop_inst });
        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ c0, code, init_ctx });

        g.beginReservedBlock(loop_blk);
        const f_idx = try g.addBlockParam();
        const cur_code = try g.addBlockParam();
        const cur_ctx = try g.addBlockParam();

        const f_done = try g.ge(f_idx, num_funcs);
        const blk_done = g.reserveBlock();
        const blk_body = g.reserveBlock();
        try g.branch(f_done, blk_done, blk_body);

        g.beginReservedBlock(blk_body);
        const func_val = try g.listNth(functions, f_idx);
        const func_result = try g.callDirect(f_emit_func, &.{ func_val, cur_code, cur_ctx });
        const new_code = try g.recordField(func_result, "code");
        const new_ctx = try g.recordField(func_result, "ctx");
        const c1 = try g.constInt(1);
        const next_f_idx = try g.add(f_idx, c1);
        try g.jump(loop_blk, &.{ next_f_idx, new_code, new_ctx });

        // All functions emitted. Append exit sequence.
        g.beginReservedBlock(blk_done);
        const exit_code_reg = try g.constInt(0);
        const final_code = try g.callDirect(f_emit_exit, &.{ cur_code, exit_code_reg });
        const code_len = try g.callBuiltin("bytes_length", &.{final_code});

        // Find entry function offset (default to 0)
        const final_func_map = try g.recordField(cur_ctx, "func_map");
        const has_entry = try g.mapHas(final_func_map, entry_name);
        const blk_has_entry = g.reserveBlock();
        const blk_no_entry = g.reserveBlock();
        try g.branch(has_entry, blk_has_entry, blk_no_entry);

        g.beginReservedBlock(blk_has_entry);
        // Entry point is 0: start at heap_init, B jumps to main
        const blk_build = g.reserveBlock();
        const has_main_true = try g.constBool(true);
        try g.jump(blk_build, &.{ c0, has_main_true });

        g.beginReservedBlock(blk_no_entry);
        const has_main_false = try g.constBool(false);
        try g.jump(blk_build, &.{ c0, has_main_false });

        // Build Mach-O header (padded to page boundary)
        g.beginReservedBlock(blk_build);
        const entry_offset = try g.addBlockParam();
        const has_main = try g.addBlockParam();
        const macho_header = try g.callDirect(f_emit_macho, &.{ code_len, entry_offset });

        // Second pass: re-emit all functions directly into the macho buffer.
        // Carry func_map from pass 1 so BL targets can be resolved.
        // Adjust offsets: pass 1 recorded code-relative offsets (0-based),
        // but pass 2 appends to macho_header, so we need to add header_size.
        // ec_emit_func will overwrite entries with pass 2 offsets anyway,
        // but for forward references we need pass 1's map + header offset.
        const pass1_func_map = try g.recordField(cur_ctx, "func_map");
        // Note: pass 1 offsets are code-relative. For forward references,
        // callee functions must be defined BEFORE callers in the source.
        const reg_map2 = try g.mapNew();
        const block_offsets2 = try g.mapNew();
        const data2 = try g.callBuiltin("bytes_new", &.{});
        const data_offsets2 = try g.mapNew();
        const fields_map2 = try g.mapNew();
        const ctx2 = try g.record(&.{
            .{ .name = "reg_map", .value = reg_map2 },
            .{ .name = "next_reg", .value = c0 },
            .{ .name = "func_map", .value = pass1_func_map },
            .{ .name = "block_offsets", .value = block_offsets2 },
            .{ .name = "data", .value = data2 },
            .{ .name = "data_offsets", .value = data_offsets2 },
            .{ .name = "blocks_start", .value = c0 },
            .{ .name = "fields_map", .value = fields_map2 },
        });

        // Emit heap init into macho buffer (before functions)
        const macho_with_heap_raw = try g.callDirect(f_emit_heap_init, &.{macho_header});

        // Branch on has_main: if true, emit B main; if false, skip
        const blk_emit_b_main = g.reserveBlock();
        const blk_skip_b_main = g.reserveBlock();
        const blk_after_b_main = g.reserveBlock();
        try g.branch(has_main, blk_emit_b_main, blk_skip_b_main);

        g.beginReservedBlock(blk_emit_b_main);
        {
            // Append B instruction to jump to main function
            const header_size = try g.callBuiltin("bytes_length", &.{macho_header});
            const main_entry_off = try g.mapGet(final_func_map, entry_name);
            const main_abs = try g.add(header_size, main_entry_off);
            const cur_pos = try g.callBuiltin("bytes_length", &.{macho_with_heap_raw});
            const b_rel = try g.sub(main_abs, cur_pos);
            const c4_b = try g.constInt(4);
            const b_rel_div4 = try g.binary(.div, b_rel, c4_b);
            const b_base = try g.constInt(0x14000000);
            const b_mask = try g.constInt(0x03FFFFFF);
            const b_imm = try g.binary(.bit_and, b_rel_div4, b_mask);
            const b_enc = try g.binary(.bit_or, b_base, b_imm);
            const macho_with_b = try g.callDirect(f_append_inst, &.{ macho_with_heap_raw, b_enc });
            try g.jump(blk_after_b_main, &.{macho_with_b});
        }

        g.beginReservedBlock(blk_skip_b_main);
        try g.jump(blk_after_b_main, &.{macho_with_heap_raw});

        g.beginReservedBlock(blk_after_b_main);
        const macho_with_heap = try g.addBlockParam();

        const loop2 = g.reserveBlock();
        try g.jump(loop2, &.{ c0, macho_with_heap, ctx2 });

        g.beginReservedBlock(loop2);
        const f_idx2 = try g.addBlockParam();
        const cur_macho = try g.addBlockParam();
        const cur_ctx2 = try g.addBlockParam();

        const f_done2 = try g.ge(f_idx2, num_funcs);
        const blk_done2 = g.reserveBlock();
        const blk_body2 = g.reserveBlock();
        try g.branch(f_done2, blk_done2, blk_body2);

        g.beginReservedBlock(blk_body2);
        const func_val2 = try g.listNth(functions, f_idx2);
        const func_result2 = try g.callDirect(f_emit_func, &.{ func_val2, cur_macho, cur_ctx2 });
        const new_macho = try g.recordField(func_result2, "code");
        const new_ctx2 = try g.recordField(func_result2, "ctx");
        const c1b = try g.constInt(1);
        const next_f_idx2 = try g.add(f_idx2, c1b);
        try g.jump(loop2, &.{ next_f_idx2, new_macho, new_ctx2 });

        // Append exit sequence to final binary
        g.beginReservedBlock(blk_done2);
        const exit_reg2 = try g.constInt(0);
        const final_macho = try g.callDirect(f_emit_exit, &.{ cur_macho, exit_reg2 });

        // Pad code to page boundary (code_limit alignment)
        const padded = try g.callDirect(f_pad_to_page, &.{final_macho});

        // Ad-hoc code sign the Mach-O binary
        const signed = try g.callBuiltin("bytes_macho_codesign", &.{padded});
        try g.ret(signed);
    }
    try g.endReservedFunc(f_emit_module);

    return f_emit_module;
}

// ── Tests ──────────────────────────────────────────────────────────────

const interp_mod = @import("../interp.zig");
const Interpreter = interp_mod.Interpreter;
const builtins = @import("../builtins.zig");

fn setupTestInterpreter(alloc: Allocator, pool: *InternPool, module: ir.Module) Interpreter {
    var interp = Interpreter.init(alloc, module, pool);
    builtins.registerAll(&interp) catch {};
    return interp;
}

fn findFuncByName(alloc: Allocator, builder: *ir.Builder, pool: *InternPool, name: []const u8) ?FuncId {
    const target = pool.intern(alloc, name) catch return null;
    for (builder.funcs.items, 0..) |func, i| {
        if (func.name == target) return @enumFromInt(i);
    }
    return null;
}

test "emit: generate compiles" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);

    const f_emit_module = try generate(alloc, &builder, &pool);
    const module = try builder.build(f_emit_module);

    // Verify the module has a reasonable number of functions
    try std.testing.expect(module.funcs.len >= 30);
}

test "emit: encode_add_reg known value" {
    // ADD x0, x1, x2 = 0x8B020020
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(0);
    const rn = try g.constInt(1);
    const rm = try g.constInt(2);
    const f_encode: FuncId = @enumFromInt(0); // ec_encode_add_reg
    const result = try g.callDirect(f_encode, &.{ rd, rn, rm });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0x8B020020), val.int);
}

test "emit: encode_sub_reg known value" {
    // SUB x0, x1, x2 = 0xCB020020
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(0);
    const rn = try g.constInt(1);
    const rm = try g.constInt(2);
    const f_encode: FuncId = @enumFromInt(1); // ec_encode_sub_reg
    const result = try g.callDirect(f_encode, &.{ rd, rn, rm });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0xCB020020), val.int);
}

test "emit: encode_ret known value" {
    // RET = 0xD65F03C0
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_encode: FuncId = @enumFromInt(12); // ec_encode_ret_inst
    const result = try g.callDirect(f_encode, &.{});
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0xD65F03C0), val.int);
}

test "emit: encode_svc known value" {
    // SVC #0x80 = 0xD4001001
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const imm = try g.constInt(0x80);
    const f_encode: FuncId = @enumFromInt(13); // ec_encode_svc
    const result = try g.callDirect(f_encode, &.{imm});
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0xD4001001), val.int);
}

test "emit: encode_movz known value" {
    // MOVZ x0, #42, LSL #0 = 0xD2800540
    // 0xD2800000 | (0 << 21) | (42 << 5) | 0 = 0xD2800000 | 0x540 = 0xD2800540
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(0);
    const imm = try g.constInt(42);
    const shift = try g.constInt(0);
    const f_encode: FuncId = @enumFromInt(8); // ec_encode_movz
    const result = try g.callDirect(f_encode, &.{ rd, imm, shift });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0xD2800540), val.int);
}

test "emit: encode_b known value" {
    // B #0 = 0x14000000
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const offset = try g.constInt(0);
    const f_encode: FuncId = @enumFromInt(10); // ec_encode_b
    const result = try g.callDirect(f_encode, &.{offset});
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0x14000000), val.int);
}

test "emit: encode_mul known value" {
    // MUL x3, x1, x2 = 0x9B027C23
    // 0x9B007C00 | (2 << 16) | (1 << 5) | 3 = 0x9B007C00 | 0x20000 | 0x20 | 3
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(3);
    const rn = try g.constInt(1);
    const rm = try g.constInt(2);
    const f_encode: FuncId = @enumFromInt(2); // ec_encode_mul
    const result = try g.callDirect(f_encode, &.{ rd, rn, rm });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0x9B027C23), val.int);
}

test "emit: macho header starts with magic" {
    // Call ec_emit_macho with code_len=0, check length = page size (16384)
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    // Build test function: call ec_emit_macho(code_len=0, entry_offset=0), return bytes_length
    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const code_len = try g.constInt(0);
    const entry_off = try g.constInt(0);
    const f_macho: FuncId = @enumFromInt(40); // ec_emit_macho
    const macho = try g.callDirect(f_macho, &.{ code_len, entry_off });
    // Check length — should be one page (16384) for the header
    const len = try g.callBuiltin("bytes_length", &.{macho});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // Header is padded to page boundary
    try std.testing.expectEqual(@as(i64, 16384), val.int);
}

// ── Boundary / adversarial encoding tests ─────────────────────────────

test "emit: encode_add_reg max registers x30, x30, x30" {
    // ADD x30, x30, x30 = 0x8B1E03DE
    // 0x8B000000 | (30 << 16) | (30 << 5) | 30
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const r30 = try g.constInt(30);
    const f_encode: FuncId = @enumFromInt(0);
    const result = try g.callDirect(f_encode, &.{ r30, r30, r30 });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0x8B000000 | (30 << 16) | (30 << 5) | 30;
    try std.testing.expectEqual(expected, val.int);
}

test "emit: encode_add_imm max immediate 4095" {
    // ADD x0, x1, #4095 = 0x91000000 | (4095 << 10) | (1 << 5) | 0
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(0);
    const rn = try g.constInt(1);
    const imm = try g.constInt(4095);
    const f_encode: FuncId = @enumFromInt(4); // ec_encode_add_imm
    const result = try g.callDirect(f_encode, &.{ rd, rn, imm });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0x91000000 | (4095 << 10) | (1 << 5) | 0;
    try std.testing.expectEqual(expected, val.int);
}

test "emit: encode_movz with shift 16 (hw=1)" {
    // MOVZ x5, #0xABCD, LSL #16 = 0xD2800000 | (1 << 21) | (0xABCD << 5) | 5
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(5);
    const imm = try g.constInt(0xABCD);
    const shift = try g.constInt(16);
    const f_encode: FuncId = @enumFromInt(8); // ec_encode_movz
    const result = try g.callDirect(f_encode, &.{ rd, imm, shift });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0xD2800000 | (1 << 21) | (0xABCD << 5) | 5;
    try std.testing.expectEqual(expected, val.int);
}

test "emit: encode_b nonzero offset" {
    // B +16 = jump 4 instructions forward
    // 0x14000000 | (16/4 & 0x3FFFFFF) = 0x14000004
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const offset = try g.constInt(16);
    const f_encode: FuncId = @enumFromInt(10); // ec_encode_b
    const result = try g.callDirect(f_encode, &.{offset});
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0x14000004), val.int);
}

test "emit: encode_bl nonzero offset" {
    // BL +8 = 0x94000000 | (8/4 & 0x3FFFFFF) = 0x94000002
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const offset = try g.constInt(8);
    const f_encode: FuncId = @enumFromInt(11); // ec_encode_bl
    const result = try g.callDirect(f_encode, &.{offset});
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expectEqual(@as(i64, 0x94000002), val.int);
}

test "emit: encode_sdiv known value" {
    // SDIV x0, x1, x2 = 0x9AC20C20
    // 0x9AC00C00 | (2 << 16) | (1 << 5) | 0
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(0);
    const rn = try g.constInt(1);
    const rm = try g.constInt(2);
    const f_encode: FuncId = @enumFromInt(3); // ec_encode_sdiv
    const result = try g.callDirect(f_encode, &.{ rd, rn, rm });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0x9AC00C00 | (2 << 16) | (1 << 5) | 0;
    try std.testing.expectEqual(expected, val.int);
}

test "emit: encode_cmp_reg known value" {
    // CMP x3, x4 = SUBS xzr, x3, x4
    // 0xEB00001F | (4 << 16) | (3 << 5) = 0xEB04007F
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rn = try g.constInt(3);
    const rm = try g.constInt(4);
    const f_encode: FuncId = @enumFromInt(6); // ec_encode_cmp_reg
    const result = try g.callDirect(f_encode, &.{ rn, rm });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0xEB00001F | (4 << 16) | (3 << 5);
    try std.testing.expectEqual(expected, val.int);
}

test "emit: encode_ldr known value" {
    // LDR x0, [x1, #16] = 0xF9400000 | ((16/8) << 10) | (1 << 5) | 0
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rt = try g.constInt(0);
    const rn = try g.constInt(1);
    const offset = try g.constInt(16);
    const f_encode: FuncId = @enumFromInt(17); // ec_encode_ldr
    const result = try g.callDirect(f_encode, &.{ rt, rn, offset });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0xF9400000 | ((16 / 8) << 10) | (1 << 5) | 0;
    try std.testing.expectEqual(expected, val.int);
}

test "emit: encode_str known value" {
    // STR x5, [x29, #8] = 0xF9000000 | ((8/8) << 10) | (29 << 5) | 5
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rt = try g.constInt(5);
    const rn = try g.constInt(29);
    const offset = try g.constInt(8);
    const f_encode: FuncId = @enumFromInt(18); // ec_encode_str
    const result = try g.callDirect(f_encode, &.{ rt, rn, offset });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0xF9000000 | ((8 / 8) << 10) | (29 << 5) | 5;
    try std.testing.expectEqual(expected, val.int);
}

// ── Register allocation semantic tests ─────────────────────────────────

test "emit: alloc_reg maps first value to x8" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    // Build a ctx: {reg_map: empty, next_reg: 0, func_map: empty, block_offsets: empty, data: empty, data_offsets: empty}
    const rm = try g.mapNew();
    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    const c0 = try g.constInt(0);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c0 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = c0 },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });
    const val_id = try g.constInt(0);
    const f_alloc: FuncId = @enumFromInt(31); // ec_alloc_reg
    const result = try g.callDirect(f_alloc, &.{ ctx, val_id });
    const reg = try g.recordField(result, "reg");
    try g.ret(reg);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // First allocation: next_reg=0, reg = 0+19 = x19 (callee-saved first)
    try std.testing.expectEqual(@as(i64, 19), val.int);
}

test "emit: alloc_reg returns same reg for same value_id" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rm = try g.mapNew();
    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    const c0 = try g.constInt(0);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c0 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = c0 },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });
    const val_id = try g.constInt(42);
    const f_alloc: FuncId = @enumFromInt(31); // ec_alloc_reg
    // Allocate once
    const r1 = try g.callDirect(f_alloc, &.{ ctx, val_id });
    const reg1 = try g.recordField(r1, "reg");
    const ctx1 = try g.recordField(r1, "ctx");
    // Allocate same value_id again — should get same register
    const r2 = try g.callDirect(f_alloc, &.{ ctx1, val_id });
    const reg2 = try g.recordField(r2, "reg");
    // Compare
    const same = try g.eq(reg1, reg2);
    try g.ret(same);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "emit: alloc_reg temps start at x8 after callee-saved" {
    // After allocating 8 callee-saved registers (x19-x26), the 9th goes to x8
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rm = try g.mapNew();
    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    // Start with next_reg=8 (all temp regs used)
    const c8 = try g.constInt(8);
    const c0_cs = try g.constInt(0);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c8 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = c0_cs },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });
    const val_id = try g.constInt(99);
    const f_alloc: FuncId = @enumFromInt(31); // ec_alloc_reg
    const result = try g.callDirect(f_alloc, &.{ ctx, val_id });
    const reg = try g.recordField(result, "reg");
    try g.ret(reg);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // next_reg=8 >= 8, so spill: reg = 108 + 8 = 116 (spill slot 0)
    // With callee-saved-only allocator, x8-x15 are skipped entirely
    try std.testing.expectEqual(@as(i64, 116), val.int);
}

// ── Code generation semantic tests ─────────────────────────────────────

test "emit: emit_inst const_int produces 4 bytes for small value" {
    // A small integer (fits in 16 bits) should produce exactly one MOVZ = 4 bytes
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    // Create an IrConstInt instruction
    const dst = try g.constInt(0);
    const value = try g.constInt(42);
    const inst = try g.tag("IrConstInt", try g.record(&.{
        .{ .name = "dst", .value = dst },
        .{ .name = "value", .value = value },
    }));

    // Create context
    const rm = try g.mapNew();
    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    const c0 = try g.constInt(0);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c0 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = c0 },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });

    const bytes = try g.callBuiltin("bytes_new", &.{});
    const f_emit: FuncId = @enumFromInt(35); // ec_emit_inst
    const result = try g.callDirect(f_emit, &.{ inst, bytes, ctx });
    const result_bytes = try g.recordField(result, "bytes");
    const len = try g.callBuiltin("bytes_length", &.{result_bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // Small value (42) fits in one MOVZ = 4 bytes
    try std.testing.expectEqual(@as(i64, 4), val.int);
}

test "emit: emit_inst const_int large value produces 8 bytes (MOVZ+MOVK)" {
    // A value with bits in chunk1 produces MOVZ + MOVK = 8 bytes
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const dst = try g.constInt(0);
    const value = try g.constInt(0x10042); // bits in both chunk0 and chunk1
    const inst = try g.tag("IrConstInt", try g.record(&.{
        .{ .name = "dst", .value = dst },
        .{ .name = "value", .value = value },
    }));

    const rm = try g.mapNew();
    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    const c0 = try g.constInt(0);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c0 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = c0 },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });

    const bytes = try g.callBuiltin("bytes_new", &.{});
    const f_emit: FuncId = @enumFromInt(35); // ec_emit_inst
    const result = try g.callDirect(f_emit, &.{ inst, bytes, ctx });
    const result_bytes = try g.recordField(result, "bytes");
    const len = try g.callBuiltin("bytes_length", &.{result_bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // MOVZ + MOVK = 8 bytes
    try std.testing.expectEqual(@as(i64, 8), val.int);
}

test "emit: emit_inst unknown tag falls through returning bytes unchanged" {
    // An unknown instruction tag should return bytes as-is (0 bytes added)
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const inst = try g.tag("IrUnknownFutureInst", try g.constNil());

    const rm = try g.mapNew();
    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    const c0 = try g.constInt(0);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c0 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = c0 },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });

    const bytes = try g.callBuiltin("bytes_new", &.{});
    const f_emit: FuncId = @enumFromInt(35); // ec_emit_inst
    const result = try g.callDirect(f_emit, &.{ inst, bytes, ctx });
    const result_bytes = try g.recordField(result, "bytes");
    const len = try g.callBuiltin("bytes_length", &.{result_bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // Unknown instruction: no bytes emitted
    try std.testing.expectEqual(@as(i64, 0), val.int);
}

test "emit: emit_inst binary add produces 4 bytes" {
    // IrBinary with "+" op on two known values -> one ADD instruction = 4 bytes
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();

    // Pre-populate reg_map with lhs(value 1) -> x8, rhs(value 2) -> x9
    var rm = try g.mapNew();
    const s1 = try g.callBuiltin("string_from_int", &.{try g.constInt(1)});
    rm = try g.mapSet(rm, s1, try g.constInt(8));
    const s2 = try g.callBuiltin("string_from_int", &.{try g.constInt(2)});
    rm = try g.mapSet(rm, s2, try g.constInt(9));

    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    const c2 = try g.constInt(2); // next_reg=2 (two already allocated)
    const c0_bs = try g.constInt(0);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c2 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = c0_bs },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });

    const inst = try g.tag("IrBinary", try g.record(&.{
        .{ .name = "dst", .value = try g.constInt(3) },
        .{ .name = "op", .value = try g.constString("+") },
        .{ .name = "lhs", .value = try g.constInt(1) },
        .{ .name = "rhs", .value = try g.constInt(2) },
    }));

    const bytes = try g.callBuiltin("bytes_new", &.{});
    const f_emit: FuncId = @enumFromInt(35); // ec_emit_inst
    const result = try g.callDirect(f_emit, &.{ inst, bytes, ctx });
    const result_bytes = try g.recordField(result, "bytes");
    const len = try g.callBuiltin("bytes_length", &.{result_bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // ADD instruction = 4 bytes
    try std.testing.expectEqual(@as(i64, 4), val.int);
}

test "emit: emit_inst binary unknown op produces 0 bytes" {
    // IrBinary with unknown op "^^" -> fallthrough, 0 bytes
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();

    var rm = try g.mapNew();
    const s1 = try g.callBuiltin("string_from_int", &.{try g.constInt(1)});
    rm = try g.mapSet(rm, s1, try g.constInt(8));
    const s2 = try g.callBuiltin("string_from_int", &.{try g.constInt(2)});
    rm = try g.mapSet(rm, s2, try g.constInt(9));

    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    const c2 = try g.constInt(2);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c2 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = try g.constInt(0) },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });

    const inst = try g.tag("IrBinary", try g.record(&.{
        .{ .name = "dst", .value = try g.constInt(3) },
        .{ .name = "op", .value = try g.constString("^^") },
        .{ .name = "lhs", .value = try g.constInt(1) },
        .{ .name = "rhs", .value = try g.constInt(2) },
    }));

    const bytes = try g.callBuiltin("bytes_new", &.{});
    const f_emit: FuncId = @enumFromInt(35); // ec_emit_inst
    const result = try g.callDirect(f_emit, &.{ inst, bytes, ctx });
    const result_bytes = try g.recordField(result, "bytes");
    const len = try g.callBuiltin("bytes_length", &.{result_bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // Unknown op: no bytes emitted
    try std.testing.expectEqual(@as(i64, 0), val.int);
}

test "emit: emit_inst binary == produces 8 bytes (CMP+CSET)" {
    // IrBinary with "==" op -> CMP + CSET = 8 bytes
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();

    var rm = try g.mapNew();
    const s1 = try g.callBuiltin("string_from_int", &.{try g.constInt(1)});
    rm = try g.mapSet(rm, s1, try g.constInt(8));
    const s2 = try g.callBuiltin("string_from_int", &.{try g.constInt(2)});
    rm = try g.mapSet(rm, s2, try g.constInt(9));

    const fm = try g.mapNew();
    const bo = try g.mapNew();
    const d = try g.callBuiltin("bytes_new", &.{});
    const do_ = try g.mapNew();
    const c2 = try g.constInt(2);
    const ctx = try g.record(&.{
        .{ .name = "reg_map", .value = rm },
        .{ .name = "next_reg", .value = c2 },
        .{ .name = "func_map", .value = fm },
        .{ .name = "block_offsets", .value = bo },
        .{ .name = "data", .value = d },
        .{ .name = "data_offsets", .value = do_ },
        .{ .name = "blocks_start", .value = try g.constInt(0) },
        .{ .name = "fields_map", .value = try g.mapNew() },
    });

    const inst = try g.tag("IrBinary", try g.record(&.{
        .{ .name = "dst", .value = try g.constInt(3) },
        .{ .name = "op", .value = try g.constString("==") },
        .{ .name = "lhs", .value = try g.constInt(1) },
        .{ .name = "rhs", .value = try g.constInt(2) },
    }));

    const bytes = try g.callBuiltin("bytes_new", &.{});
    const f_emit: FuncId = @enumFromInt(35); // ec_emit_inst
    const result = try g.callDirect(f_emit, &.{ inst, bytes, ctx });
    const result_bytes = try g.recordField(result, "bytes");
    const len = try g.callBuiltin("bytes_length", &.{result_bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // CMP + CSET = 8 bytes
    try std.testing.expectEqual(@as(i64, 8), val.int);
}

// ── Prologue/Epilogue semantic tests ───────────────────────────────────

test "emit: prologue produces 44 bytes (9 STP + MOV fp + SUB sp)" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const frame_size = try g.constInt(16);
    const f_pro: FuncId = @enumFromInt(29); // ec_emit_prologue
    const bytes = try g.callDirect(f_pro, &.{frame_size});
    const len = try g.callBuiltin("bytes_length", &.{bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // 9 STP (36 bytes) + ADD (4 bytes) + SUB sp (4 bytes) = 44 bytes
    try std.testing.expectEqual(@as(i64, 44), val.int);
}

test "emit: epilogue produces 44 bytes (ADD sp + 9 LDP + RET)" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const frame_size = try g.constInt(16);
    const f_epi: FuncId = @enumFromInt(30); // ec_emit_epilogue
    const bytes = try g.callDirect(f_epi, &.{frame_size});
    const len = try g.callBuiltin("bytes_length", &.{bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // ADD sp (4 bytes) + 9 LDP (36 bytes) + RET (4 bytes) = 44 bytes
    try std.testing.expectEqual(@as(i64, 44), val.int);
}

// ── Encoding cross-check: AND/ORR ──────────────────────────────────────

test "emit: encode_and_reg known value" {
    // AND x0, x1, x2 = 0x8A020020
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(0);
    const rn = try g.constInt(1);
    const rm = try g.constInt(2);
    const f_encode: FuncId = @enumFromInt(19); // ec_encode_and_reg
    const result = try g.callDirect(f_encode, &.{ rd, rn, rm });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0x8A000000 | (2 << 16) | (1 << 5) | 0;
    try std.testing.expectEqual(expected, val.int);
}

test "emit: encode_orr_reg known value" {
    // ORR x0, x1, x2 = 0xAA020020
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(0);
    const rn = try g.constInt(1);
    const rm = try g.constInt(2);
    const f_encode: FuncId = @enumFromInt(20); // ec_encode_orr_reg
    const result = try g.callDirect(f_encode, &.{ rd, rn, rm });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    const expected: i64 = 0xAA000000 | (2 << 16) | (1 << 5) | 0;
    try std.testing.expectEqual(expected, val.int);
}

// ── Encoding property: encoding is deterministic ────────────────────────

test "emit: encoding is deterministic (same inputs = same output)" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    // Encode ADD x7, x19, x28 twice — must get identical results
    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const rd = try g.constInt(7);
    const rn = try g.constInt(19);
    const rm = try g.constInt(28);
    const f_encode: FuncId = @enumFromInt(0);
    const r1 = try g.callDirect(f_encode, &.{ rd, rn, rm });
    const r2 = try g.callDirect(f_encode, &.{ rd, rn, rm });
    const same = try g.eq(r1, r2);
    try g.ret(same);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

// ── mov_imm64 tests ────────────────────────────────────────────────────

test "emit: mov_imm64 zero produces 4 bytes" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const bytes = try g.callBuiltin("bytes_new", &.{});
    const rd = try g.constInt(0);
    const value = try g.constInt(0);
    const f_mov: FuncId = @enumFromInt(25); // ec_mov_imm64
    const result = try g.callDirect(f_mov, &.{ bytes, rd, value });
    const len = try g.callBuiltin("bytes_length", &.{result});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // MOVZ only (all chunks are 0, but MOVZ always emitted) = 4 bytes
    try std.testing.expectEqual(@as(i64, 4), val.int);
}

test "emit: mov_imm64 large value produces 12 bytes (3 chunks)" {
    // 0x0001_0002_0003 has chunk0=3, chunk1=2, chunk2=1 -> MOVZ + 2 MOVK = 12 bytes
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const bytes = try g.callBuiltin("bytes_new", &.{});
    const rd = try g.constInt(0);
    const value = try g.constInt(0x0001_0002_0003);
    const f_mov: FuncId = @enumFromInt(25); // ec_mov_imm64
    const result = try g.callDirect(f_mov, &.{ bytes, rd, value });
    const len = try g.callBuiltin("bytes_length", &.{result});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // MOVZ + MOVK + MOVK = 12 bytes
    try std.testing.expectEqual(@as(i64, 12), val.int);
}

// ── pad_to_page tests ──────────────────────────────────────────────────

test "emit: pad_to_page already aligned returns same length" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    // Pad something already page-aligned — result should be unchanged
    const f_macho: FuncId = @enumFromInt(40); // ec_emit_macho returns page-aligned buffer
    const c0 = try g.constInt(0);
    const header = try g.callDirect(f_macho, &.{ c0, c0 });
    const f_pad: FuncId = @enumFromInt(42); // ec_pad_to_page
    const padded = try g.callDirect(f_pad, &.{header});
    const len = try g.callBuiltin("bytes_length", &.{padded});
    // Header is already page-aligned (16384), padding should not change it
    const header_len = try g.callBuiltin("bytes_length", &.{header});
    const same = try g.eq(len, header_len);
    try g.ret(same);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

// ── b_cond encoding test ───────────────────────────────────────────────

test "emit: encode_b_cond EQ offset 8" {
    // B.EQ +8: 0x54000000 | (((8/4) & 0x7FFFF) << 5) | 0 = 0x54000040
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const offset = try g.constInt(8);
    const cond = try g.constInt(0); // EQ
    const f_encode = findFuncByName(alloc, &builder, &pool, "ec_encode_b_cond") orelse return error.TestUnexpectedResult;
    const result = try g.callDirect(f_encode, &.{ offset, cond });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // (8/4)=2, (2 & 0x7FFFF)=2, (2 << 5)=64=0x40
    try std.testing.expectEqual(@as(i64, 0x54000040), val.int);
}
