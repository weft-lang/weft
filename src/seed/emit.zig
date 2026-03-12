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

    const f_mov_imm64 = try g.reserveFunc("ec_mov_imm64");
    const f_emit_heap_init = try g.reserveFunc("ec_emit_heap_init");
    const f_emit_bump_alloc = try g.reserveFunc("ec_emit_bump_alloc");
    const f_emit_exit = try g.reserveFunc("ec_emit_exit");
    const f_emit_prologue = try g.reserveFunc("ec_emit_prologue");
    const f_emit_epilogue = try g.reserveFunc("ec_emit_epilogue");
    const f_alloc_reg = try g.reserveFunc("ec_alloc_reg");
    const f_get_reg = try g.reserveFunc("ec_get_reg");
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
    // STP x29, x30, [sp, #-frame_size]!
    // ADD x29, sp, #0  (MOV x29, sp)
    try g.beginReservedFunc("ec_emit_prologue");
    {
        _ = g.beginBlock();
        const frame_size = try g.addParam();
        const bytes = try g.callBuiltin("bytes_new", &.{});
        const c29 = try g.constInt(29);
        const c30 = try g.constInt(30);
        const c31 = try g.constInt(31); // sp
        // STP with negative offset: we negate frame_size
        const c0 = try g.constInt(0);
        const neg_frame = try g.sub(c0, frame_size);
        const stp = try g.callDirect(f_encode_stp_pre, &.{ c29, c30, c31, neg_frame });
        const b1 = try g.callDirect(f_append_inst, &.{ bytes, stp });
        // ADD x29, sp, #0
        const mov_fp = try g.callDirect(f_encode_add_imm, &.{ c29, c31, c0 });
        const b2 = try g.callDirect(f_append_inst, &.{ b1, mov_fp });
        try g.ret(b2);
    }
    try g.endReservedFunc(f_emit_prologue);

    // ── ec_emit_epilogue(frame_size) -> Bytes ────────────────────────
    // LDP x29, x30, [sp], #frame_size
    // RET
    try g.beginReservedFunc("ec_emit_epilogue");
    {
        _ = g.beginBlock();
        const frame_size = try g.addParam();
        const bytes = try g.callBuiltin("bytes_new", &.{});
        const c29 = try g.constInt(29);
        const c30 = try g.constInt(30);
        const c31 = try g.constInt(31); // sp
        const ldp = try g.callDirect(f_encode_ldp_post, &.{ c29, c30, c31, frame_size });
        const b1 = try g.callDirect(f_append_inst, &.{ bytes, ldp });
        const ret_inst = try g.callDirect(f_encode_ret_inst, &.{});
        const b2 = try g.callDirect(f_append_inst, &.{ b1, ret_inst });
        try g.ret(b2);
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

        // New allocation
        g.beginReservedBlock(blk_new);
        // Map next_reg counter to actual register number
        // 0-7 -> x8-x15, 8-17 -> x19-x28
        const c8_val = try g.constInt(8);
        const is_callee_saved = try g.ge(next_reg, c8_val);
        const blk_callee = g.reserveBlock();
        const blk_temp = g.reserveBlock();
        try g.branch(is_callee_saved, blk_callee, blk_temp);

        g.beginReservedBlock(blk_temp);
        // reg = next_reg + 8
        const reg_temp = try g.add(next_reg, c8_val);
        const blk_assign = g.reserveBlock();
        try g.jump(blk_assign, &.{reg_temp});

        g.beginReservedBlock(blk_callee);
        // reg = next_reg - 8 + 19 = next_reg + 11
        const c11 = try g.constInt(11);
        const reg_callee = try g.add(next_reg, c11);
        try g.jump(blk_assign, &.{reg_callee});

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
        const ci_bytes = try g.callDirect(f_mov_imm64, &.{ bytes, ci_reg, ci_value });
        const ci_result = try g.record(&.{
            .{ .name = "bytes", .value = ci_bytes },
            .{ .name = "ctx", .value = ci_ctx },
        });
        try g.ret(ci_result);

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
        const bin_rd = try g.recordField(bin_alloc_dst, "reg");
        const bin_ctx1 = try g.recordField(bin_alloc_dst, "ctx");

        const bin_rn = try g.callDirect(f_get_reg, &.{ bin_ctx1, bin_lhs });
        const bin_rm = try g.callDirect(f_get_reg, &.{ bin_ctx1, bin_rhs });

        // Dispatch on op string
        const op_add = try g.constString("+");
        const is_add = try g.eq(bin_op, op_add);
        const blk_add = g.reserveBlock();
        const blk_not_add = g.reserveBlock();
        try g.branch(is_add, blk_add, blk_not_add);

        g.beginReservedBlock(blk_add);
        const add_enc = try g.callDirect(f_encode_add_reg, &.{ bin_rd, bin_rn, bin_rm });
        const add_bytes = try g.callDirect(f_append_inst, &.{ bytes, add_enc });
        const add_result = try g.record(&.{
            .{ .name = "bytes", .value = add_bytes },
            .{ .name = "ctx", .value = bin_ctx1 },
        });
        try g.ret(add_result);

        g.beginReservedBlock(blk_not_add);
        const op_sub = try g.constString("-");
        const is_sub = try g.eq(bin_op, op_sub);
        const blk_sub = g.reserveBlock();
        const blk_not_sub = g.reserveBlock();
        try g.branch(is_sub, blk_sub, blk_not_sub);

        g.beginReservedBlock(blk_sub);
        const sub_enc = try g.callDirect(f_encode_sub_reg, &.{ bin_rd, bin_rn, bin_rm });
        const sub_bytes = try g.callDirect(f_append_inst, &.{ bytes, sub_enc });
        const sub_result = try g.record(&.{
            .{ .name = "bytes", .value = sub_bytes },
            .{ .name = "ctx", .value = bin_ctx1 },
        });
        try g.ret(sub_result);

        g.beginReservedBlock(blk_not_sub);
        const op_mul = try g.constString("*");
        const is_mul = try g.eq(bin_op, op_mul);
        const blk_mul = g.reserveBlock();
        const blk_not_mul = g.reserveBlock();
        try g.branch(is_mul, blk_mul, blk_not_mul);

        g.beginReservedBlock(blk_mul);
        const mul_enc = try g.callDirect(f_encode_mul, &.{ bin_rd, bin_rn, bin_rm });
        const mul_bytes = try g.callDirect(f_append_inst, &.{ bytes, mul_enc });
        const mul_result = try g.record(&.{
            .{ .name = "bytes", .value = mul_bytes },
            .{ .name = "ctx", .value = bin_ctx1 },
        });
        try g.ret(mul_result);

        g.beginReservedBlock(blk_not_mul);
        const op_div = try g.constString("/");
        const is_div = try g.eq(bin_op, op_div);
        const blk_div = g.reserveBlock();
        const blk_not_div = g.reserveBlock();
        try g.branch(is_div, blk_div, blk_not_div);

        g.beginReservedBlock(blk_div);
        const div_enc = try g.callDirect(f_encode_sdiv, &.{ bin_rd, bin_rn, bin_rm });
        const div_bytes = try g.callDirect(f_append_inst, &.{ bytes, div_enc });
        const div_result = try g.record(&.{
            .{ .name = "bytes", .value = div_bytes },
            .{ .name = "ctx", .value = bin_ctx1 },
        });
        try g.ret(div_result);

        // == comparison
        g.beginReservedBlock(blk_not_div);
        const op_eq = try g.constString("==");
        const is_eq_op = try g.eq(bin_op, op_eq);
        const blk_eq = g.reserveBlock();
        const blk_not_eq = g.reserveBlock();
        try g.branch(is_eq_op, blk_eq, blk_not_eq);

        g.beginReservedBlock(blk_eq);
        // CMP Xn, Xm; CSET Xd, EQ (cond=0)
        const cmp_eq = try g.callDirect(f_encode_cmp_reg, &.{ bin_rn, bin_rm });
        const b_eq1 = try g.callDirect(f_append_inst, &.{ bytes, cmp_eq });
        const cond_eq = try g.constInt(0); // EQ
        const cset_eq = try g.callDirect(f_encode_cset, &.{ bin_rd, cond_eq });
        const b_eq2 = try g.callDirect(f_append_inst, &.{ b_eq1, cset_eq });
        const eq_result = try g.record(&.{
            .{ .name = "bytes", .value = b_eq2 },
            .{ .name = "ctx", .value = bin_ctx1 },
        });
        try g.ret(eq_result);

        // < comparison
        g.beginReservedBlock(blk_not_eq);
        const op_lt = try g.constString("<");
        const is_lt_op = try g.eq(bin_op, op_lt);
        const blk_lt = g.reserveBlock();
        const blk_not_lt = g.reserveBlock();
        try g.branch(is_lt_op, blk_lt, blk_not_lt);

        g.beginReservedBlock(blk_lt);
        const cmp_lt = try g.callDirect(f_encode_cmp_reg, &.{ bin_rn, bin_rm });
        const b_lt1 = try g.callDirect(f_append_inst, &.{ bytes, cmp_lt });
        const cond_lt = try g.constInt(11); // LT
        const cset_lt = try g.callDirect(f_encode_cset, &.{ bin_rd, cond_lt });
        const b_lt2 = try g.callDirect(f_append_inst, &.{ b_lt1, cset_lt });
        const lt_result = try g.record(&.{
            .{ .name = "bytes", .value = b_lt2 },
            .{ .name = "ctx", .value = bin_ctx1 },
        });
        try g.ret(lt_result);

        // Default: treat unknown op as NOP (return unchanged)
        g.beginReservedBlock(blk_not_lt);
        const default_bin_result = try g.record(&.{
            .{ .name = "bytes", .value = bytes },
            .{ .name = "ctx", .value = bin_ctx1 },
        });
        try g.ret(default_bin_result);

        // Not binary: check const_bool
        g.beginReservedBlock(blk_not_binary);
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
                const arg_reg = try g.callDirect(f_get_reg, &.{ ac, arg_val_id });
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
                const mb = try g.callDirect(f_append_inst, &.{ ab, mov_enc });
                try g.jump(after_mov, &.{mb});

                g.beginReservedBlock(skip_mov);
                try g.jump(after_mov, &.{ab});

                g.beginReservedBlock(after_mov);
                const ab2 = try g.addBlockParam();
                const c1_a = try g.constInt(1);
                const next_ai = try g.add(ai, c1_a);
                try g.jump(args_loop, &.{ next_ai, ab2, ac });
            }

            // Args done — emit BL
            g.beginReservedBlock(args_exit);
            {
                // Look up callee offset in func_map
                const call_fmap = try g.recordField(ac, "func_map");
                const target_off = try g.mapGet(call_fmap, call_callee);
                // Current position = bytes_length(ab)
                const cur_off = try g.callBuiltin("bytes_length", &.{ab});
                // Relative offset (signed): target - current
                const rel_off = try g.sub(target_off, cur_off);
                const bl_enc = try g.callDirect(f_encode_bl, &.{rel_off});
                const bl_bytes = try g.callDirect(f_append_inst, &.{ ab, bl_enc });

                // Allocate register for dst, move x0 to it if needed
                const call_alloc = try g.callDirect(f_alloc_reg, &.{ ac, call_dst });
                const dst_reg = try g.recordField(call_alloc, "reg");
                const call_ctx = try g.recordField(call_alloc, "ctx");

                const c0_r = try g.constInt(0);
                const dst_is_x0 = try g.eq(dst_reg, c0_r);
                const blk_need_ret_mov = g.reserveBlock();
                const blk_skip_ret_mov = g.reserveBlock();
                const blk_after_ret_mov = g.reserveBlock();
                try g.branch(dst_is_x0, blk_skip_ret_mov, blk_need_ret_mov);

                g.beginReservedBlock(blk_need_ret_mov);
                // MOV dst_reg, x0: ADD dst_reg, x0, #0
                const ret_mov_enc = try g.callDirect(f_encode_add_imm, &.{ dst_reg, c0_r, c0_r });
                const ret_mov_bytes = try g.callDirect(f_append_inst, &.{ bl_bytes, ret_mov_enc });
                try g.jump(blk_after_ret_mov, &.{ret_mov_bytes});

                g.beginReservedBlock(blk_skip_ret_mov);
                try g.jump(blk_after_ret_mov, &.{bl_bytes});

                g.beginReservedBlock(blk_after_ret_mov);
                const final_bytes = try g.addBlockParam();
                const call_result = try g.record(&.{
                    .{ .name = "bytes", .value = final_bytes },
                    .{ .name = "ctx", .value = call_ctx },
                });
                try g.ret(call_result);
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
            const ri_reg = try g.recordField(ri_alloc, "reg");
            const ri_ctx = try g.recordField(ri_alloc, "ctx");

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
                const ri_fval_reg = try g.callDirect(f_get_reg, &.{ ri_c, ri_fval });

                // STR ri_fval_reg, [ri_reg, #i*8]
                // STR Xt, [Xn, #imm12] = 0xF9000000 | (imm12/8 << 10) | (Xn << 5) | Xt
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
                const ri_b2 = try g.callDirect(f_append_inst, &.{ ri_b, str_enc });

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
                    const ri_result = try g.record(&.{
                        .{ .name = "bytes", .value = ri_b },
                        .{ .name = "ctx", .value = ri_ctx_final },
                    });
                    try g.ret(ri_result);
                }
            }
        }

        // Not record_init: check IrFieldGet
        g.beginReservedBlock(blk_not_record_init);
        const is_field_get = try g.tagTest(inst, ir_field_get);
        const blk_field_get = g.reserveBlock();
        const blk_not_field_get = g.reserveBlock();
        try g.branch(is_field_get, blk_field_get, blk_not_field_get);

        // IrFieldGet: {dst, base, field} -> LDR dst, [base, #index*8]
        g.beginReservedBlock(blk_field_get);
        {
            const fg_payload = try g.tagPayload(inst, ir_field_get);
            const fg_dst = try g.recordField(fg_payload, "dst");
            const fg_base = try g.recordField(fg_payload, "base");
            const fg_field = try g.recordField(fg_payload, "field");

            // Look up base value_id in fields_map to get field names list
            const fg_base_str = try g.callBuiltin("string_from_int", &.{fg_base});
            const fg_fm = try g.recordField(ctx, "fields_map");
            const fg_names = try g.mapGet(fg_fm, fg_base_str);

            // Find index of fg_field in fg_names
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
                    // Found: index = fg_fi
                    const fg_alloc = try g.callDirect(f_alloc_reg, &.{ ctx, fg_dst });
                    const fg_reg = try g.recordField(fg_alloc, "reg");
                    const fg_ctx = try g.recordField(fg_alloc, "ctx");
                    const fg_base_reg = try g.callDirect(f_get_reg, &.{ fg_ctx, fg_base });

                    // LDR Xt, [Xn, #imm12] = 0xF9400000 | (imm12/8 << 10) | (Xn << 5) | Xt
                    const c8_fg = try g.constInt(8);
                    const fg_offset = try g.binary(.mul, fg_fi, c8_fg);
                    const fg_off_div8 = try g.binary(.div, fg_offset, c8_fg);
                    const ldr_base = try g.constInt(0xF9400000);
                    const c10_fg = try g.constInt(10);
                    const c5_fg = try g.constInt(5);
                    const ldr_off = try g.binary(.shl, fg_off_div8, c10_fg);
                    const ldr_rn = try g.binary(.shl, fg_base_reg, c5_fg);
                    const ldr_r1 = try g.binary(.bit_or, ldr_base, ldr_off);
                    const ldr_r2 = try g.binary(.bit_or, ldr_r1, ldr_rn);
                    const ldr_enc = try g.binary(.bit_or, ldr_r2, fg_reg);
                    const fg_bytes = try g.callDirect(f_append_inst, &.{ bytes, ldr_enc });

                    // Copy fields_map entry for dst (so chained access works: r.x.y)
                    const fg_result = try g.record(&.{
                        .{ .name = "bytes", .value = fg_bytes },
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

            // Field not found: return unchanged (shouldn't happen if lowerer is correct)
            g.beginReservedBlock(fg_not_found);
            {
                const fg_def = try g.record(&.{
                    .{ .name = "bytes", .value = bytes },
                    .{ .name = "ctx", .value = ctx },
                });
                try g.ret(fg_def);
            }
        }

        // Default fallthrough: return bytes unchanged
        g.beginReservedBlock(blk_not_field_get);
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
        const ret_reg = try g.callDirect(f_get_reg, &.{ ctx, ret_val_id });
        // MOV x0, Xn: ADD x0, Xn, #0
        const c0_v = try g.constInt(0);
        const is_x0 = try g.eq(ret_reg, c0_v);
        const blk_need_mov = g.reserveBlock();
        const blk_skip_mov = g.reserveBlock();
        const blk_after_mov = g.reserveBlock();
        try g.branch(is_x0, blk_skip_mov, blk_need_mov);

        g.beginReservedBlock(blk_need_mov);
        const mov_inst = try g.callDirect(f_encode_add_imm, &.{ c0_v, ret_reg, c0_v });
        const ret_b1 = try g.callDirect(f_append_inst, &.{ bytes, mov_inst });
        try g.jump(blk_after_mov, &.{ret_b1});

        g.beginReservedBlock(blk_skip_mov);
        try g.jump(blk_after_mov, &.{bytes});

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
                const j_arg_reg = try g.callDirect(f_get_reg, &.{ jc, j_arg_id });
                // Move to x0+i (block param register)
                const j_need_mov = try g.ne(j_arg_reg, ji);
                const j_do_mov = g.reserveBlock();
                const j_skip_mov = g.reserveBlock();
                const j_after_mov = g.reserveBlock();
                try g.branch(j_need_mov, j_do_mov, j_skip_mov);

                g.beginReservedBlock(j_do_mov);
                const jc0m = try g.constInt(0);
                const j_mov = try g.callDirect(f_encode_add_imm, &.{ ji, j_arg_reg, jc0m });
                const j_mb = try g.callDirect(f_append_inst, &.{ jb, j_mov });
                try g.jump(j_after_mov, &.{j_mb});

                g.beginReservedBlock(j_skip_mov);
                try g.jump(j_after_mov, &.{jb});

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

            const br_cond_reg = try g.callDirect(f_get_reg, &.{ ctx, br_cond });

            // Compute offset to else block
            const br_bo = try g.recordField(ctx, "block_offsets");
            const br_bs = try g.recordField(ctx, "blocks_start");
            const br_else_str = try g.callBuiltin("string_from_int", &.{br_else});
            const br_else_off = try g.mapGet(br_bo, br_else_str);
            const br_else_abs = try g.add(br_bs, br_else_off);
            const br_cur_abs = try g.callBuiltin("bytes_length", &.{bytes});
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
            const br_bytes = try g.callDirect(f_append_inst, &.{ bytes, cbz_enc });
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
        // Pre-populate reg_map with parameter bindings: param i -> register xi (x0-x7)
        const params = try g.recordField(func, "params");
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
            // Map value_id=pi to register=pi (x0, x1, x2, ...)
            const pi_str = try g.callBuiltin("string_from_int", &.{pi});
            const pi_rm2 = try g.mapSet(pi_rm, pi_str, pi);
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
        // next_reg starts after params (they occupy x0..n-1, but our alloc starts at x8)
        // Actually alloc_reg maps counter to actual regs: counter 0->x8, etc. So next_reg=0 is correct.
        // The params are pre-bound by value ID in reg_map, bypassing the counter.
        // Emit prologue: STP x29, x30, [sp, #-16]! ; ADD x29, sp, #0
        const c16 = try g.constInt(16);
        const c29 = try g.constInt(29);
        const c30 = try g.constInt(30);
        const c31 = try g.constInt(31);
        const neg16 = try g.constInt(-16);
        const stp_inst = try g.callDirect(f_encode_stp_pre, &.{ c29, c30, c31, neg16 });
        const code1 = try g.callDirect(f_append_inst, &.{ code, stp_inst });
        // ADD x29, sp, #0
        const mov_fp = try g.callDirect(f_encode_add_imm, &.{ c29, c31, c0 });
        const code2 = try g.callDirect(f_append_inst, &.{ code1, mov_fp });

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
            .{ .name = "next_reg", .value = c0 },
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
            .{ .name = "next_reg", .value = c0 },
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

        // Done: emit epilogue
        g.beginReservedBlock(blk_done);
        // LDP x29, x30, [sp], #16
        const ldp_inst = try g.callDirect(f_encode_ldp_post, &.{ c29, c30, c31, c16 });
        const code_epi1 = try g.callDirect(f_append_inst, &.{ cur_code, ldp_inst });
        // RET
        const ret_inst = try g.callDirect(f_encode_ret_inst, &.{});
        const code_epi2 = try g.callDirect(f_append_inst, &.{ code_epi1, ret_inst });

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
        try g.jump(blk_build, &.{c0});

        g.beginReservedBlock(blk_no_entry);
        try g.jump(blk_build, &.{c0});

        // Build Mach-O header (padded to page boundary)
        g.beginReservedBlock(blk_build);
        const entry_offset = try g.addBlockParam();
        const macho_header = try g.callDirect(f_emit_macho, &.{ code_len, entry_offset });

        // Second pass: re-emit all functions directly into the macho buffer.
        // Carry func_map from pass 1 so BL targets can be resolved.
        // Adjust offsets: pass 1 recorded code-relative offsets (0-based),
        // but pass 2 appends to macho_header, so we need to add header_size.
        // ec_emit_func will overwrite entries with pass 2 offsets anyway,
        // but for forward references we need pass 1's map + header offset.
        const pass1_func_map = try g.recordField(cur_ctx, "func_map");
        // ec_emit_func overwrites entries during pass 2 with correct absolute offsets.
        // Since functions are emitted in order and callees are typically defined before callers,
        // pass 2's own entries (which have correct absolute offsets) will be used for BL.
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
        // Append B instruction to jump to main function
        // B offset = (main_abs_offset - current_pos) / 4
        // main_abs_offset = header_size + entry_off_from_pass1
        // current_pos = bytes_length(macho_with_heap_raw)
        const header_size = try g.callBuiltin("bytes_length", &.{macho_header});
        const main_entry_off = try g.mapGet(final_func_map, entry_name);
        const main_abs = try g.add(header_size, main_entry_off);
        const cur_pos = try g.callBuiltin("bytes_length", &.{macho_with_heap_raw});
        const b_rel = try g.sub(main_abs, cur_pos);
        const c4_b = try g.constInt(4);
        const b_rel_div4 = try g.binary(.div, b_rel, c4_b);
        // B imm26: 0x14000000 | (imm26 & 0x03FFFFFF)
        const b_base = try g.constInt(0x14000000);
        const b_mask = try g.constInt(0x03FFFFFF);
        const b_imm = try g.binary(.bit_and, b_rel_div4, b_mask);
        const b_enc = try g.binary(.bit_or, b_base, b_imm);
        const macho_with_heap = try g.callDirect(f_append_inst, &.{ macho_with_heap_raw, b_enc });

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
    const f_macho: FuncId = @enumFromInt(34); // ec_emit_macho
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
    const f_alloc: FuncId = @enumFromInt(27); // ec_alloc_reg
    const result = try g.callDirect(f_alloc, &.{ ctx, val_id });
    const reg = try g.recordField(result, "reg");
    try g.ret(reg);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // First allocation: next_reg=0, reg = 0+8 = x8
    try std.testing.expectEqual(@as(i64, 8), val.int);
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
    const f_alloc: FuncId = @enumFromInt(27); // ec_alloc_reg
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

test "emit: alloc_reg callee-saved starts at x19" {
    // After allocating 8 temp registers (x8-x15), the 9th goes to x19
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
    const f_alloc: FuncId = @enumFromInt(27); // ec_alloc_reg
    const result = try g.callDirect(f_alloc, &.{ ctx, val_id });
    const reg = try g.recordField(result, "reg");
    try g.ret(reg);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // next_reg=8 >= 8, so callee-saved: reg = 8 + 11 = 19 (x19)
    try std.testing.expectEqual(@as(i64, 19), val.int);
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
    const f_emit: FuncId = @enumFromInt(29); // ec_emit_inst
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
    const f_emit: FuncId = @enumFromInt(29); // ec_emit_inst
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
    const f_emit: FuncId = @enumFromInt(29); // ec_emit_inst
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
    const f_emit: FuncId = @enumFromInt(29); // ec_emit_inst
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
    // IrBinary with unknown op "%" -> fallthrough, 0 bytes
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
        .{ .name = "op", .value = try g.constString("%") },
        .{ .name = "lhs", .value = try g.constInt(1) },
        .{ .name = "rhs", .value = try g.constInt(2) },
    }));

    const bytes = try g.callBuiltin("bytes_new", &.{});
    const f_emit: FuncId = @enumFromInt(29); // ec_emit_inst
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
    const f_emit: FuncId = @enumFromInt(29); // ec_emit_inst
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

test "emit: prologue produces 8 bytes (STP + MOV fp)" {
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
    const f_pro: FuncId = @enumFromInt(25); // ec_emit_prologue
    const bytes = try g.callDirect(f_pro, &.{frame_size});
    const len = try g.callBuiltin("bytes_length", &.{bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // STP (4 bytes) + ADD (4 bytes) = 8 bytes
    try std.testing.expectEqual(@as(i64, 8), val.int);
}

test "emit: epilogue produces 8 bytes (LDP + RET)" {
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
    const f_epi: FuncId = @enumFromInt(26); // ec_emit_epilogue
    const bytes = try g.callDirect(f_epi, &.{frame_size});
    const len = try g.callBuiltin("bytes_length", &.{bytes});
    try g.ret(len);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    // LDP (4 bytes) + RET (4 bytes) = 8 bytes
    try std.testing.expectEqual(@as(i64, 8), val.int);
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
    const f_mov: FuncId = @enumFromInt(21); // ec_mov_imm64
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
    const f_mov: FuncId = @enumFromInt(21);
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
    const f_macho: FuncId = @enumFromInt(34); // ec_emit_macho returns page-aligned buffer
    const c0 = try g.constInt(0);
    const header = try g.callDirect(f_macho, &.{ c0, c0 });
    const f_pad: FuncId = @enumFromInt(36); // ec_pad_to_page
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
    const f_encode: FuncId = @enumFromInt(16); // ec_encode_b_cond
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
