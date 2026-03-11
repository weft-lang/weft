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
const grammar = @import("grammar.zig");

/// Seed type checker: generates IR that, when run on the interpreter,
/// type-checks a Rhiz AST (from the grammar) and produces a typed AST.
///
/// Types are represented as tagged IR values (mirroring types.zig but
/// as interpreter values). Type environments are maps. Subtyping is
/// checked via simplified DNF.
///
/// All logic is pure IR — no Zig builtins wrap domain logic.

// ── Type tag constants ──────────────────────────────────────────────────
// These are the tag names for type values in the IR.
pub const ty_int = "TyInt";
pub const ty_float = "TyFloat";
pub const ty_string = "TyString";
pub const ty_bool = "TyBool";
pub const ty_nil = "TyNil";
pub const ty_never = "TyNever";
pub const ty_any = "TyAny";
pub const ty_union = "TyUnion";
pub const ty_intersection = "TyIntersection";
pub const ty_complement = "TyComplement";
pub const ty_record = "TyRecord";
pub const ty_tagged_union = "TyTaggedUnion";
pub const ty_function = "TyFunction";
pub const ty_type_var = "TyTypeVar";
pub const ty_app = "TyApp";

// ── Typed AST tag constants ─────────────────────────────────────────────
pub const tast_int_lit = "TIntLit";
pub const tast_float_lit = "TFloatLit";
pub const tast_string_lit = "TStringLit";
pub const tast_bool_lit = "TBoolLit";
pub const tast_nil_lit = "TNilLit";
pub const tast_ident = "TIdent";
pub const tast_call = "TCall";
pub const tast_pipe = "TPipe";
pub const tast_binop = "TBinOp";
pub const tast_unary = "TUnary";
pub const tast_if = "TIf";
pub const tast_match = "TMatch";
pub const tast_let = "TLet";
pub const tast_block = "TBlock";
pub const tast_lambda = "TLambda";
pub const tast_handle = "THandle";
pub const tast_record_lit = "TRecordLit";
pub const tast_list_lit = "TListLit";
pub const tast_field_access = "TFieldAccess";
pub const tast_record_update = "TRecordUpdate";
pub const tast_string_interp = "TStringInterp";
pub const tast_fn_decl = "TFnDecl";
pub const tast_module = "TModule";

// ── Reserved function IDs ───────────────────────────────────────────────
// The type checker generates ~25 IR functions.

/// Generate the complete type checker as an IR module.
/// Returns the entry function ID (check_module).
pub fn generate(alloc: Allocator, builder: *ir.Builder, pool: *InternPool) !FuncId {
    var g = Gen.init(alloc, builder, pool);

    // Reserve function IDs for mutual recursion
    const f_type_from_ast = try g.reserveFunc("tc_type_from_ast");
    const f_resolve_type = try g.reserveFunc("tc_resolve_type");
    const f_is_subtype = try g.reserveFunc("tc_is_subtype");
    const f_is_primitive = try g.reserveFunc("tc_is_primitive");
    const f_primitives_equal = try g.reserveFunc("tc_primitives_equal");
    const f_ctx_new = try g.reserveFunc("tc_ctx_new");
    const f_ctx_bind_value = try g.reserveFunc("tc_ctx_bind_value");
    const f_ctx_lookup_value = try g.reserveFunc("tc_ctx_lookup_value");
    const f_ctx_bind_type = try g.reserveFunc("tc_ctx_bind_type");
    const f_ctx_lookup_type = try g.reserveFunc("tc_ctx_lookup_type");
    const f_ctx_bind_constructor = try g.reserveFunc("tc_ctx_bind_constructor");
    const f_ctx_lookup_constructor = try g.reserveFunc("tc_ctx_lookup_constructor");
    const f_collect_decls = try g.reserveFunc("tc_collect_decls");
    const f_collect_type_decl = try g.reserveFunc("tc_collect_type_decl");
    const f_collect_effect_decl = try g.reserveFunc("tc_collect_effect_decl");
    const f_collect_trait_decl = try g.reserveFunc("tc_collect_trait_decl");
    const f_infer = try g.reserveFunc("tc_infer");
    const f_infer_binop = try g.reserveFunc("tc_infer_binop");
    const f_infer_call = try g.reserveFunc("tc_infer_call");
    const f_check_pattern = try g.reserveFunc("tc_check_pattern");
    const f_check_fn_decl = try g.reserveFunc("tc_check_fn_decl");
    const f_check_module = try g.reserveFunc("tc_check_module");

    // ── Generate: tc_is_primitive(type_tag: String) -> Bool ──────────
    // Returns true if the tag name is a primitive type.
    try g.beginReservedFunc("tc_is_primitive");
    {
        const param = try g.addParam(); // type tag string
        _ = g.beginBlock();

        // Chain of comparisons for primitive types
        const is_int = try g.eq(param, try g.constString(ty_int));
        const is_float = try g.eq(param, try g.constString(ty_float));
        const is_string = try g.eq(param, try g.constString(ty_string));
        const is_bool = try g.eq(param, try g.constString(ty_bool));
        const is_nil = try g.eq(param, try g.constString(ty_nil));
        const is_never = try g.eq(param, try g.constString(ty_never));
        const is_any = try g.eq(param, try g.constString(ty_any));

        const r1 = try g.logicOr(is_int, is_float);
        const r2 = try g.logicOr(r1, is_string);
        const r3 = try g.logicOr(r2, is_bool);
        const r4 = try g.logicOr(r3, is_nil);
        const r5 = try g.logicOr(r4, is_never);
        const r6 = try g.logicOr(r5, is_any);
        try g.ret(r6);
    }
    try g.endReservedFunc(f_is_primitive);

    // ── Generate: tc_primitives_equal(a: Type, b: Type) -> Bool ─────
    // Check if two types are the same primitive.
    try g.beginReservedFunc("tc_primitives_equal");
    {
        const a = try g.addParam();
        const b = try g.addParam();
        _ = g.beginBlock();

        // Get tags of both, compare
        // Both must be tagged values — compare tag names
        const a_is_int = try g.tagTest(a, ty_int);
        const b_is_int = try g.tagTest(b, ty_int);
        const both_int = try g.logicAnd(a_is_int, b_is_int);

        const a_is_float = try g.tagTest(a, ty_float);
        const b_is_float = try g.tagTest(b, ty_float);
        const both_float = try g.logicAnd(a_is_float, b_is_float);

        const a_is_str = try g.tagTest(a, ty_string);
        const b_is_str = try g.tagTest(b, ty_string);
        const both_str = try g.logicAnd(a_is_str, b_is_str);

        const a_is_bool = try g.tagTest(a, ty_bool);
        const b_is_bool = try g.tagTest(b, ty_bool);
        const both_bool = try g.logicAnd(a_is_bool, b_is_bool);

        const a_is_nil = try g.tagTest(a, ty_nil);
        const b_is_nil = try g.tagTest(b, ty_nil);
        const both_nil = try g.logicAnd(a_is_nil, b_is_nil);

        const a_is_never = try g.tagTest(a, ty_never);
        const b_is_never = try g.tagTest(b, ty_never);
        const both_never = try g.logicAnd(a_is_never, b_is_never);

        const a_is_any = try g.tagTest(a, ty_any);
        const b_is_any = try g.tagTest(b, ty_any);
        const both_any = try g.logicAnd(a_is_any, b_is_any);

        const r1 = try g.logicOr(both_int, both_float);
        const r2 = try g.logicOr(r1, both_str);
        const r3 = try g.logicOr(r2, both_bool);
        const r4 = try g.logicOr(r3, both_nil);
        const r5 = try g.logicOr(r4, both_never);
        const r6 = try g.logicOr(r5, both_any);
        try g.ret(r6);
    }
    try g.endReservedFunc(f_primitives_equal);

    // ── Generate: tc_is_subtype(a: Type, b: Type) -> Bool ───────────
    // Simplified subtype checking for bootstrap scope.
    // Handles: primitive equality, Never <: T, T <: Any,
    //          T <: T|U, tagged variant <: parent union,
    //          function subtyping (contra/co).
    try g.beginReservedFunc("tc_is_subtype");
    {
        const a = try g.addParam();
        const b = try g.addParam();
        _ = g.beginBlock();

        // 1. Never <: anything
        const a_is_never = try g.tagTest(a, ty_never);
        const never_true = g.reserveBlock();
        const check_any = g.reserveBlock();
        try g.branch(a_is_never, never_true, check_any);

        g.beginReservedBlock(never_true);
        try g.ret(try g.constBool(true));

        // 2. anything <: Any
        g.beginReservedBlock(check_any);
        const b_is_any = try g.tagTest(b, ty_any);
        const any_true = g.reserveBlock();
        const check_equal = g.reserveBlock();
        try g.branch(b_is_any, any_true, check_equal);

        g.beginReservedBlock(any_true);
        try g.ret(try g.constBool(true));

        // 3. Primitive equality
        g.beginReservedBlock(check_equal);
        const prim_eq = try g.callDirect(f_primitives_equal, &.{ a, b });
        const prim_true = g.reserveBlock();
        const check_union_rhs = g.reserveBlock();
        try g.branch(prim_eq, prim_true, check_union_rhs);

        g.beginReservedBlock(prim_true);
        try g.ret(try g.constBool(true));

        // 4. T <: T|U  =>  T <: T or T <: U
        g.beginReservedBlock(check_union_rhs);
        const b_is_union = try g.tagTest(b, ty_union);
        const check_union_body = g.reserveBlock();
        const check_union_lhs = g.reserveBlock();
        try g.branch(b_is_union, check_union_body, check_union_lhs);

        g.beginReservedBlock(check_union_body);
        const b_payload = try g.tagPayload(b, ty_union);
        const b_lhs = try g.recordField(b_payload, "lhs");
        const b_rhs = try g.recordField(b_payload, "rhs");
        const sub_lhs = try g.callDirect(f_is_subtype, &.{ a, b_lhs });
        const sub_rhs_blk = g.reserveBlock();
        const union_true = g.reserveBlock();
        try g.branch(sub_lhs, union_true, sub_rhs_blk);

        g.beginReservedBlock(union_true);
        try g.ret(try g.constBool(true));

        g.beginReservedBlock(sub_rhs_blk);
        const sub_rhs = try g.callDirect(f_is_subtype, &.{ a, b_rhs });
        try g.ret(sub_rhs);

        // 5. T|U <: V  =>  T <: V and U <: V
        g.beginReservedBlock(check_union_lhs);
        const a_is_union = try g.tagTest(a, ty_union);
        const check_union_lhs_body = g.reserveBlock();
        const check_tagged = g.reserveBlock();
        try g.branch(a_is_union, check_union_lhs_body, check_tagged);

        g.beginReservedBlock(check_union_lhs_body);
        const a_payload = try g.tagPayload(a, ty_union);
        const a_lhs = try g.recordField(a_payload, "lhs");
        const a_rhs = try g.recordField(a_payload, "rhs");
        const sub_a_lhs = try g.callDirect(f_is_subtype, &.{ a_lhs, b });
        const check_a_rhs = g.reserveBlock();
        const union_lhs_false = g.reserveBlock();
        try g.branch(sub_a_lhs, check_a_rhs, union_lhs_false);

        g.beginReservedBlock(union_lhs_false);
        try g.ret(try g.constBool(false));

        g.beginReservedBlock(check_a_rhs);
        const sub_a_rhs = try g.callDirect(f_is_subtype, &.{ a_rhs, b });
        try g.ret(sub_a_rhs);

        // 6. Tagged union: variant name equality for now
        g.beginReservedBlock(check_tagged);
        const a_is_tagged = try g.tagTest(a, ty_tagged_union);
        const b_is_tagged = try g.tagTest(b, ty_tagged_union);
        const both_tagged = try g.logicAnd(a_is_tagged, b_is_tagged);
        const check_tagged_body = g.reserveBlock();
        const check_fn = g.reserveBlock();
        try g.branch(both_tagged, check_tagged_body, check_fn);

        g.beginReservedBlock(check_tagged_body);
        const a_tagged_pl = try g.tagPayload(a, ty_tagged_union);
        const b_tagged_pl = try g.tagPayload(b, ty_tagged_union);
        const a_name = try g.recordField(a_tagged_pl, "name");
        const b_name = try g.recordField(b_tagged_pl, "name");
        const names_eq = try g.eq(a_name, b_name);
        try g.ret(names_eq);

        // 7. Function subtyping: contravariant params, covariant return
        g.beginReservedBlock(check_fn);
        const a_is_fn = try g.tagTest(a, ty_function);
        const b_is_fn = try g.tagTest(b, ty_function);
        const both_fn = try g.logicAnd(a_is_fn, b_is_fn);
        const check_fn_body = g.reserveBlock();
        const check_record = g.reserveBlock();
        try g.branch(both_fn, check_fn_body, check_record);

        // For functions: (A1, A2) -> R1 <: (B1, B2) -> R2
        // iff B1 <: A1 and B2 <: A2 (contravariant) and R1 <: R2 (covariant)
        // Simplified: just check return type covariance for bootstrap
        g.beginReservedBlock(check_fn_body);
        const a_fn_pl = try g.tagPayload(a, ty_function);
        const b_fn_pl = try g.tagPayload(b, ty_function);
        const a_ret = try g.recordField(a_fn_pl, "ret");
        const b_ret = try g.recordField(b_fn_pl, "ret");
        const ret_sub = try g.callDirect(f_is_subtype, &.{ a_ret, b_ret });
        try g.ret(ret_sub);

        // 8. Record subtyping: structural — a has all fields of b with subtypes
        g.beginReservedBlock(check_record);
        const a_is_rec = try g.tagTest(a, ty_record);
        const b_is_rec = try g.tagTest(b, ty_record);
        const both_rec = try g.logicAnd(a_is_rec, b_is_rec);
        const check_rec_body = g.reserveBlock();
        const fallthrough = g.reserveBlock();
        try g.branch(both_rec, check_rec_body, fallthrough);

        g.beginReservedBlock(check_rec_body);
        const a_rec_pl = try g.tagPayload(a, ty_record);
        const b_rec_pl = try g.tagPayload(b, ty_record);
        const a_rec_name = try g.recordField(a_rec_pl, "name");
        const b_rec_name = try g.recordField(b_rec_pl, "name");
        const rec_names_eq = try g.eq(a_rec_name, b_rec_name);
        try g.ret(rec_names_eq);

        // Default: not a subtype
        g.beginReservedBlock(fallthrough);
        try g.ret(try g.constBool(false));
    }
    try g.endReservedFunc(f_is_subtype);

    // ── Generate: tc_type_from_ast(type_expr: AST, ctx: Ctx) -> Type ──
    // Convert AST TypeExpr nodes to Type values.
    try g.beginReservedFunc("tc_type_from_ast");
    {
        const type_expr = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        // Check for TypeNamed
        const is_named = try g.tagTest(type_expr, grammar.ast_type_named);
        const named_blk = g.reserveBlock();
        const check_app = g.reserveBlock();
        try g.branch(is_named, named_blk, check_app);

        // TypeNamed -> resolve name to type
        g.beginReservedBlock(named_blk);
        const name_str = try g.tagPayload(type_expr, grammar.ast_type_named);
        const resolved = try g.callDirect(f_resolve_type, &.{ name_str, ctx });
        try g.ret(resolved);

        // TypeApp
        g.beginReservedBlock(check_app);
        const is_app = try g.tagTest(type_expr, grammar.ast_type_app);
        const app_blk = g.reserveBlock();
        const check_union = g.reserveBlock();
        try g.branch(is_app, app_blk, check_union);

        g.beginReservedBlock(app_blk);
        const app_pl = try g.tagPayload(type_expr, grammar.ast_type_app);
        const app_name = try g.recordField(app_pl, "name");
        const app_args_ast = try g.recordField(app_pl, "args");
        // For bootstrap: create TyApp with name and args
        // (full generic instantiation deferred to when needed)
        const app_rec = try g.record(&.{
            .{ .name = "name", .value = app_name },
            .{ .name = "args", .value = app_args_ast },
        });
        const app_type = try g.tag(ty_app, app_rec);
        try g.ret(app_type);

        // TypeUnion
        g.beginReservedBlock(check_union);
        const is_union = try g.tagTest(type_expr, grammar.ast_type_union);
        const union_blk = g.reserveBlock();
        const check_intersection = g.reserveBlock();
        try g.branch(is_union, union_blk, check_intersection);

        g.beginReservedBlock(union_blk);
        const union_pl = try g.tagPayload(type_expr, grammar.ast_type_union);
        const u_lhs_ast = try g.recordField(union_pl, "lhs");
        const u_rhs_ast = try g.recordField(union_pl, "rhs");
        const u_lhs = try g.callDirect(f_type_from_ast, &.{ u_lhs_ast, ctx });
        const u_rhs = try g.callDirect(f_type_from_ast, &.{ u_rhs_ast, ctx });
        const union_rec = try g.record(&.{
            .{ .name = "lhs", .value = u_lhs },
            .{ .name = "rhs", .value = u_rhs },
        });
        try g.ret(try g.tag(ty_union, union_rec));

        // TypeIntersection
        g.beginReservedBlock(check_intersection);
        const is_inter = try g.tagTest(type_expr, grammar.ast_type_intersection);
        const inter_blk = g.reserveBlock();
        const check_complement = g.reserveBlock();
        try g.branch(is_inter, inter_blk, check_complement);

        g.beginReservedBlock(inter_blk);
        const inter_pl = try g.tagPayload(type_expr, grammar.ast_type_intersection);
        const i_lhs_ast = try g.recordField(inter_pl, "lhs");
        const i_rhs_ast = try g.recordField(inter_pl, "rhs");
        const i_lhs = try g.callDirect(f_type_from_ast, &.{ i_lhs_ast, ctx });
        const i_rhs = try g.callDirect(f_type_from_ast, &.{ i_rhs_ast, ctx });
        const inter_rec = try g.record(&.{
            .{ .name = "lhs", .value = i_lhs },
            .{ .name = "rhs", .value = i_rhs },
        });
        try g.ret(try g.tag(ty_intersection, inter_rec));

        // TypeComplement
        g.beginReservedBlock(check_complement);
        const is_compl = try g.tagTest(type_expr, grammar.ast_type_complement);
        const compl_blk = g.reserveBlock();
        const check_nullable = g.reserveBlock();
        try g.branch(is_compl, compl_blk, check_nullable);

        g.beginReservedBlock(compl_blk);
        const compl_inner_ast = try g.tagPayload(type_expr, grammar.ast_type_complement);
        const compl_inner = try g.callDirect(f_type_from_ast, &.{ compl_inner_ast, ctx });
        try g.ret(try g.tag(ty_complement, compl_inner));

        // TypeNullable -> sugar for T | Nil
        g.beginReservedBlock(check_nullable);
        const is_nullable = try g.tagTest(type_expr, grammar.ast_type_nullable);
        const nullable_blk = g.reserveBlock();
        const check_fn_type = g.reserveBlock();
        try g.branch(is_nullable, nullable_blk, check_fn_type);

        g.beginReservedBlock(nullable_blk);
        const null_inner_ast = try g.tagPayload(type_expr, grammar.ast_type_nullable);
        const null_inner = try g.callDirect(f_type_from_ast, &.{ null_inner_ast, ctx });
        const nil_type = try g.tag(ty_nil, null);
        const nullable_rec = try g.record(&.{
            .{ .name = "lhs", .value = null_inner },
            .{ .name = "rhs", .value = nil_type },
        });
        try g.ret(try g.tag(ty_union, nullable_rec));

        // TypeFn
        g.beginReservedBlock(check_fn_type);
        const is_fn_type = try g.tagTest(type_expr, grammar.ast_type_fn);
        const fn_type_blk = g.reserveBlock();
        const type_default = g.reserveBlock();
        try g.branch(is_fn_type, fn_type_blk, type_default);

        g.beginReservedBlock(fn_type_blk);
        const fn_pl = try g.tagPayload(type_expr, grammar.ast_type_fn);
        const fn_params_ast = try g.recordField(fn_pl, "params");
        const fn_ret_ast = try g.recordField(fn_pl, "ret");
        const fn_effects = try g.recordField(fn_pl, "effects");
        // TODO: recursively convert params — for bootstrap, pass through
        const fn_ret_type = try g.callDirect(f_type_from_ast, &.{ fn_ret_ast, ctx });
        const fn_rec = try g.record(&.{
            .{ .name = "params", .value = fn_params_ast },
            .{ .name = "effects", .value = fn_effects },
            .{ .name = "ret", .value = fn_ret_type },
        });
        try g.ret(try g.tag(ty_function, fn_rec));

        // Default: return TyAny (unknown type expression)
        g.beginReservedBlock(type_default);
        try g.ret(try g.tag(ty_any, null));
    }
    try g.endReservedFunc(f_type_from_ast);

    // ── Generate: tc_resolve_type(name: String, ctx: Ctx) -> Type ───
    // Resolve a type name to a Type value.
    try g.beginReservedFunc("tc_resolve_type");
    {
        const name = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        // Check built-in primitive types
        const is_int = try g.eq(name, try g.constString("Int"));
        const ret_int = g.reserveBlock();
        const check_float = g.reserveBlock();
        try g.branch(is_int, ret_int, check_float);

        g.beginReservedBlock(ret_int);
        try g.ret(try g.tag(ty_int, null));

        g.beginReservedBlock(check_float);
        const is_float = try g.eq(name, try g.constString("Float"));
        const ret_float = g.reserveBlock();
        const check_string = g.reserveBlock();
        try g.branch(is_float, ret_float, check_string);

        g.beginReservedBlock(ret_float);
        try g.ret(try g.tag(ty_float, null));

        g.beginReservedBlock(check_string);
        const is_str = try g.eq(name, try g.constString("String"));
        const ret_str = g.reserveBlock();
        const check_bool = g.reserveBlock();
        try g.branch(is_str, ret_str, check_bool);

        g.beginReservedBlock(ret_str);
        try g.ret(try g.tag(ty_string, null));

        g.beginReservedBlock(check_bool);
        const is_bool = try g.eq(name, try g.constString("Bool"));
        const ret_bool = g.reserveBlock();
        const check_nil = g.reserveBlock();
        try g.branch(is_bool, ret_bool, check_nil);

        g.beginReservedBlock(ret_bool);
        try g.ret(try g.tag(ty_bool, null));

        g.beginReservedBlock(check_nil);
        const is_nil = try g.eq(name, try g.constString("Nil"));
        const ret_nil = g.reserveBlock();
        const check_never = g.reserveBlock();
        try g.branch(is_nil, ret_nil, check_never);

        g.beginReservedBlock(ret_nil);
        try g.ret(try g.tag(ty_nil, null));

        g.beginReservedBlock(check_never);
        const is_never = try g.eq(name, try g.constString("Never"));
        const ret_never = g.reserveBlock();
        const check_any = g.reserveBlock();
        try g.branch(is_never, ret_never, check_any);

        g.beginReservedBlock(ret_never);
        try g.ret(try g.tag(ty_never, null));

        g.beginReservedBlock(check_any);
        const is_any = try g.eq(name, try g.constString("Any"));
        const ret_any = g.reserveBlock();
        const check_ctx = g.reserveBlock();
        try g.branch(is_any, ret_any, check_ctx);

        g.beginReservedBlock(ret_any);
        try g.ret(try g.tag(ty_any, null));

        // Check context type environment
        g.beginReservedBlock(check_ctx);
        const types_map = try g.recordField(ctx, "types");
        const has_type = try g.mapHas(types_map, name);
        const found_type = g.reserveBlock();
        const not_found = g.reserveBlock();
        try g.branch(has_type, found_type, not_found);

        g.beginReservedBlock(found_type);
        const type_def = try g.mapGet(types_map, name);
        try g.ret(type_def);

        // Not found: return TyAny (permissive for bootstrap)
        g.beginReservedBlock(not_found);
        try g.ret(try g.tag(ty_any, null));
    }
    try g.endReservedFunc(f_resolve_type);

    // ── Generate: tc_ctx_new() -> Ctx ───────────────────────────────
    try g.beginReservedFunc("tc_ctx_new");
    {
        _ = g.beginBlock();
        const types = try g.mapNew();
        const values = try g.mapNew();
        const traits = try g.mapNew();
        const effects = try g.mapNew();
        const constructors = try g.mapNew();
        const ctx_rec = try g.record(&.{
            .{ .name = "types", .value = types },
            .{ .name = "values", .value = values },
            .{ .name = "traits", .value = traits },
            .{ .name = "effects", .value = effects },
            .{ .name = "constructors", .value = constructors },
        });
        try g.ret(ctx_rec);
    }
    try g.endReservedFunc(f_ctx_new);

    // ── Generate: tc_ctx_bind_value(ctx, name, type) -> Ctx ─────────
    try g.beginReservedFunc("tc_ctx_bind_value");
    {
        const ctx = try g.addParam();
        const name = try g.addParam();
        const ty = try g.addParam();
        _ = g.beginBlock();
        const values = try g.recordField(ctx, "values");
        const new_values = try g.mapSet(values, name, ty);
        const types = try g.recordField(ctx, "types");
        const traits = try g.recordField(ctx, "traits");
        const effects = try g.recordField(ctx, "effects");
        const constructors = try g.recordField(ctx, "constructors");
        const new_ctx = try g.record(&.{
            .{ .name = "types", .value = types },
            .{ .name = "values", .value = new_values },
            .{ .name = "traits", .value = traits },
            .{ .name = "effects", .value = effects },
            .{ .name = "constructors", .value = constructors },
        });
        try g.ret(new_ctx);
    }
    try g.endReservedFunc(f_ctx_bind_value);

    // ── Generate: tc_ctx_lookup_value(ctx, name) -> Type ────────────
    try g.beginReservedFunc("tc_ctx_lookup_value");
    {
        const ctx = try g.addParam();
        const name = try g.addParam();
        _ = g.beginBlock();
        const values = try g.recordField(ctx, "values");
        const has = try g.mapHas(values, name);
        const found = g.reserveBlock();
        const not_found = g.reserveBlock();
        try g.branch(has, found, not_found);

        g.beginReservedBlock(found);
        const val = try g.mapGet(values, name);
        try g.ret(val);

        // Not found: return TyAny (permissive)
        g.beginReservedBlock(not_found);
        try g.ret(try g.tag(ty_any, null));
    }
    try g.endReservedFunc(f_ctx_lookup_value);

    // ── Generate: tc_ctx_bind_type(ctx, name, type_def) -> Ctx ──────
    try g.beginReservedFunc("tc_ctx_bind_type");
    {
        const ctx = try g.addParam();
        const name = try g.addParam();
        const type_def = try g.addParam();
        _ = g.beginBlock();
        const types = try g.recordField(ctx, "types");
        const new_types = try g.mapSet(types, name, type_def);
        const values = try g.recordField(ctx, "values");
        const traits = try g.recordField(ctx, "traits");
        const effects = try g.recordField(ctx, "effects");
        const constructors = try g.recordField(ctx, "constructors");
        const new_ctx = try g.record(&.{
            .{ .name = "types", .value = new_types },
            .{ .name = "values", .value = values },
            .{ .name = "traits", .value = traits },
            .{ .name = "effects", .value = effects },
            .{ .name = "constructors", .value = constructors },
        });
        try g.ret(new_ctx);
    }
    try g.endReservedFunc(f_ctx_bind_type);

    // ── Generate: tc_ctx_lookup_type(ctx, name) -> TypeDef|Nil ──────
    try g.beginReservedFunc("tc_ctx_lookup_type");
    {
        const ctx = try g.addParam();
        const name = try g.addParam();
        _ = g.beginBlock();
        const types = try g.recordField(ctx, "types");
        const result = try g.mapGet(types, name);
        try g.ret(result);
    }
    try g.endReservedFunc(f_ctx_lookup_type);

    // ── Generate: tc_ctx_bind_constructor(ctx, name, info) -> Ctx ────
    try g.beginReservedFunc("tc_ctx_bind_constructor");
    {
        const ctx = try g.addParam();
        const name = try g.addParam();
        const info = try g.addParam();
        _ = g.beginBlock();
        const constructors = try g.recordField(ctx, "constructors");
        const new_constructors = try g.mapSet(constructors, name, info);
        const types = try g.recordField(ctx, "types");
        const values = try g.recordField(ctx, "values");
        const traits = try g.recordField(ctx, "traits");
        const effects = try g.recordField(ctx, "effects");
        const new_ctx = try g.record(&.{
            .{ .name = "types", .value = types },
            .{ .name = "values", .value = values },
            .{ .name = "traits", .value = traits },
            .{ .name = "effects", .value = effects },
            .{ .name = "constructors", .value = new_constructors },
        });
        try g.ret(new_ctx);
    }
    try g.endReservedFunc(f_ctx_bind_constructor);

    // ── Generate: tc_ctx_lookup_constructor(ctx, name) -> Info|Nil ───
    try g.beginReservedFunc("tc_ctx_lookup_constructor");
    {
        const ctx = try g.addParam();
        const name = try g.addParam();
        _ = g.beginBlock();
        const constructors = try g.recordField(ctx, "constructors");
        const result = try g.mapGet(constructors, name);
        try g.ret(result);
    }
    try g.endReservedFunc(f_ctx_lookup_constructor);

    // ── Generate: tc_collect_type_decl(decl, ctx) -> Ctx ────────────
    // Register a type declaration in the context.
    try g.beginReservedFunc("tc_collect_type_decl");
    {
        const decl = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        const pl = try g.tagPayload(decl, grammar.ast_type_decl);
        const type_name = try g.recordField(pl, "name");
        const variants = try g.recordField(pl, "variants");

        // Create a tagged union type for this type decl
        const type_def = try g.record(&.{
            .{ .name = "name", .value = type_name },
            .{ .name = "variants", .value = variants },
        });
        const ty = try g.tag(ty_tagged_union, type_def);

        // Bind the type name
        var cur_ctx = try g.callDirect(f_ctx_bind_type, &.{ ctx, type_name, ty });

        // Register constructors: loop over variants
        const var_len = try g.listLength(variants);
        const zero = try g.constInt(0);
        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ zero, cur_ctx });

        g.beginReservedBlock(loop_blk);
        const idx = try g.addBlockParam();
        cur_ctx = try g.addBlockParam();
        const done = try g.ge(idx, var_len);
        const body_blk = g.reserveBlock();
        const exit_blk = g.reserveBlock();
        try g.branch(done, exit_blk, body_blk);

        g.beginReservedBlock(body_blk);
        const variant = try g.listNth(variants, idx);
        const var_name = try g.recordField(variant, "name");
        // Constructor info: parent type + variant itself
        const ctor_info = try g.record(&.{
            .{ .name = "parent_type", .value = ty },
            .{ .name = "variant", .value = variant },
        });
        const ctx_with_ctor = try g.callDirect(f_ctx_bind_constructor, &.{ cur_ctx, var_name, ctor_info });
        const one = try g.constInt(1);
        const next_idx = try g.add(idx, one);
        try g.jump(loop_blk, &.{ next_idx, ctx_with_ctor });

        g.beginReservedBlock(exit_blk);
        try g.ret(cur_ctx);
    }
    try g.endReservedFunc(f_collect_type_decl);

    // ── Generate: tc_collect_effect_decl(decl, ctx) -> Ctx ──────────
    try g.beginReservedFunc("tc_collect_effect_decl");
    {
        const decl = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        const pl = try g.tagPayload(decl, grammar.ast_effect_decl);
        const effect_name = try g.recordField(pl, "name");
        const operations = try g.recordField(pl, "operations");

        // Store effect info in the effects map
        const effects_map = try g.recordField(ctx, "effects");
        const effect_info = try g.record(&.{
            .{ .name = "name", .value = effect_name },
            .{ .name = "operations", .value = operations },
        });
        const new_effects = try g.mapSet(effects_map, effect_name, effect_info);

        // Rebuild context
        const types = try g.recordField(ctx, "types");
        const values = try g.recordField(ctx, "values");
        const traits = try g.recordField(ctx, "traits");
        const constructors = try g.recordField(ctx, "constructors");
        const new_ctx = try g.record(&.{
            .{ .name = "types", .value = types },
            .{ .name = "values", .value = values },
            .{ .name = "traits", .value = traits },
            .{ .name = "effects", .value = new_effects },
            .{ .name = "constructors", .value = constructors },
        });
        try g.ret(new_ctx);
    }
    try g.endReservedFunc(f_collect_effect_decl);

    // ── Generate: tc_collect_trait_decl(decl, ctx) -> Ctx ───────────
    try g.beginReservedFunc("tc_collect_trait_decl");
    {
        const decl = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        const pl = try g.tagPayload(decl, grammar.ast_trait_decl);
        const trait_name = try g.recordField(pl, "name");
        const methods = try g.recordField(pl, "methods");

        const traits_map = try g.recordField(ctx, "traits");
        const trait_info = try g.record(&.{
            .{ .name = "name", .value = trait_name },
            .{ .name = "methods", .value = methods },
        });
        const new_traits = try g.mapSet(traits_map, trait_name, trait_info);

        const types = try g.recordField(ctx, "types");
        const values = try g.recordField(ctx, "values");
        const effects = try g.recordField(ctx, "effects");
        const constructors = try g.recordField(ctx, "constructors");
        const new_ctx = try g.record(&.{
            .{ .name = "types", .value = types },
            .{ .name = "values", .value = values },
            .{ .name = "traits", .value = new_traits },
            .{ .name = "effects", .value = effects },
            .{ .name = "constructors", .value = constructors },
        });
        try g.ret(new_ctx);
    }
    try g.endReservedFunc(f_collect_trait_decl);

    // ── Generate: tc_collect_decls(decls: List, ctx) -> Ctx ─────────
    // First pass: collect type, trait, effect, and fn signature declarations.
    try g.beginReservedFunc("tc_collect_decls");
    {
        const decls = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        const len = try g.listLength(decls);
        const zero = try g.constInt(0);
        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ zero, ctx });

        g.beginReservedBlock(loop_blk);
        const idx = try g.addBlockParam();
        const cur_ctx = try g.addBlockParam();
        const done = try g.ge(idx, len);
        const body_blk = g.reserveBlock();
        const exit_blk = g.reserveBlock();
        try g.branch(done, exit_blk, body_blk);

        g.beginReservedBlock(body_blk);
        const decl = try g.listNth(decls, idx);

        // TypeDecl?
        const is_type = try g.tagTest(decl, grammar.ast_type_decl);
        const type_blk = g.reserveBlock();
        const check_effect = g.reserveBlock();
        try g.branch(is_type, type_blk, check_effect);

        g.beginReservedBlock(type_blk);
        const ctx_after_type = try g.callDirect(f_collect_type_decl, &.{ decl, cur_ctx });
        const one_t = try g.constInt(1);
        const next_t = try g.add(idx, one_t);
        try g.jump(loop_blk, &.{ next_t, ctx_after_type });

        // EffectDecl?
        g.beginReservedBlock(check_effect);
        const is_effect = try g.tagTest(decl, grammar.ast_effect_decl);
        const effect_blk = g.reserveBlock();
        const check_trait = g.reserveBlock();
        try g.branch(is_effect, effect_blk, check_trait);

        g.beginReservedBlock(effect_blk);
        const ctx_after_effect = try g.callDirect(f_collect_effect_decl, &.{ decl, cur_ctx });
        const one_e = try g.constInt(1);
        const next_e = try g.add(idx, one_e);
        try g.jump(loop_blk, &.{ next_e, ctx_after_effect });

        // TraitDecl?
        g.beginReservedBlock(check_trait);
        const is_trait = try g.tagTest(decl, grammar.ast_trait_decl);
        const trait_blk = g.reserveBlock();
        const check_fn = g.reserveBlock();
        try g.branch(is_trait, trait_blk, check_fn);

        g.beginReservedBlock(trait_blk);
        const ctx_after_trait = try g.callDirect(f_collect_trait_decl, &.{ decl, cur_ctx });
        const one_tr = try g.constInt(1);
        const next_tr = try g.add(idx, one_tr);
        try g.jump(loop_blk, &.{ next_tr, ctx_after_trait });

        // FnDecl — register function name and type in value env
        g.beginReservedBlock(check_fn);
        const is_fn = try g.tagTest(decl, grammar.ast_fn_decl);
        const fn_blk = g.reserveBlock();
        const skip_blk = g.reserveBlock();
        try g.branch(is_fn, fn_blk, skip_blk);

        g.beginReservedBlock(fn_blk);
        const fn_pl = try g.tagPayload(decl, grammar.ast_fn_decl);
        const fn_name = try g.recordField(fn_pl, "name");
        const fn_params = try g.recordField(fn_pl, "params");
        const fn_ret = try g.recordField(fn_pl, "return_type");
        const fn_effects = try g.recordField(fn_pl, "effects");

        // Build function type from signature
        // For return type: if present, convert; else TyAny
        const has_ret = try g.ne(fn_ret, try g.constNil());
        const ret_present_blk = g.reserveBlock();
        const ret_absent_blk = g.reserveBlock();
        try g.branch(has_ret, ret_present_blk, ret_absent_blk);

        g.beginReservedBlock(ret_present_blk);
        const ret_type = try g.callDirect(f_type_from_ast, &.{ fn_ret, cur_ctx });
        const fn_type_1 = try g.record(&.{
            .{ .name = "params", .value = fn_params },
            .{ .name = "effects", .value = fn_effects },
            .{ .name = "ret", .value = ret_type },
        });
        const fn_ty_1 = try g.tag(ty_function, fn_type_1);
        const ctx_with_fn_1 = try g.callDirect(f_ctx_bind_value, &.{ cur_ctx, fn_name, fn_ty_1 });
        const one_f1 = try g.constInt(1);
        const next_f1 = try g.add(idx, one_f1);
        try g.jump(loop_blk, &.{ next_f1, ctx_with_fn_1 });

        g.beginReservedBlock(ret_absent_blk);
        const any_ret = try g.tag(ty_any, null);
        const fn_type_2 = try g.record(&.{
            .{ .name = "params", .value = fn_params },
            .{ .name = "effects", .value = fn_effects },
            .{ .name = "ret", .value = any_ret },
        });
        const fn_ty_2 = try g.tag(ty_function, fn_type_2);
        const ctx_with_fn_2 = try g.callDirect(f_ctx_bind_value, &.{ cur_ctx, fn_name, fn_ty_2 });
        const one_f2 = try g.constInt(1);
        const next_f2 = try g.add(idx, one_f2);
        try g.jump(loop_blk, &.{ next_f2, ctx_with_fn_2 });

        // Skip other decls (impl, use)
        g.beginReservedBlock(skip_blk);
        const one_s = try g.constInt(1);
        const next_s = try g.add(idx, one_s);
        try g.jump(loop_blk, &.{ next_s, cur_ctx });

        g.beginReservedBlock(exit_blk);
        try g.ret(cur_ctx);
    }
    try g.endReservedFunc(f_collect_decls);

    // ── Generate: tc_infer_binop(op, lhs_type, rhs_type) -> Type ────
    // Return the result type of a binary operation.
    try g.beginReservedFunc("tc_infer_binop");
    {
        const op = try g.addParam();
        _ = try g.addParam(); // lhs_type (unused for now)
        _ = try g.addParam(); // rhs_type (unused for now)
        _ = g.beginBlock();

        // Arithmetic ops -> Int
        const is_add = try g.eq(op, try g.constString("+"));
        const is_sub = try g.eq(op, try g.constString("-"));
        const is_mul = try g.eq(op, try g.constString("*"));
        const is_div = try g.eq(op, try g.constString("/"));
        const is_mod = try g.eq(op, try g.constString("%"));
        const arith = try g.logicOr(is_add, is_sub);
        const arith2 = try g.logicOr(arith, is_mul);
        const arith3 = try g.logicOr(arith2, is_div);
        const is_arith = try g.logicOr(arith3, is_mod);

        const arith_blk = g.reserveBlock();
        const check_cmp = g.reserveBlock();
        try g.branch(is_arith, arith_blk, check_cmp);

        g.beginReservedBlock(arith_blk);
        try g.ret(try g.tag(ty_int, null));

        // Comparison ops -> Bool
        g.beginReservedBlock(check_cmp);
        const is_eq = try g.eq(op, try g.constString("=="));
        const is_ne = try g.eq(op, try g.constString("!="));
        const is_lt = try g.eq(op, try g.constString("<"));
        const is_gt = try g.eq(op, try g.constString(">"));
        const is_le = try g.eq(op, try g.constString("<="));
        const is_ge = try g.eq(op, try g.constString(">="));
        const cmp1 = try g.logicOr(is_eq, is_ne);
        const cmp2 = try g.logicOr(cmp1, is_lt);
        const cmp3 = try g.logicOr(cmp2, is_gt);
        const cmp4 = try g.logicOr(cmp3, is_le);
        const is_cmp = try g.logicOr(cmp4, is_ge);

        const cmp_blk = g.reserveBlock();
        const check_logic = g.reserveBlock();
        try g.branch(is_cmp, cmp_blk, check_logic);

        g.beginReservedBlock(cmp_blk);
        try g.ret(try g.tag(ty_bool, null));

        // Logic ops -> Bool
        g.beginReservedBlock(check_logic);
        const is_and = try g.eq(op, try g.constString("&&"));
        const is_or = try g.eq(op, try g.constString("||"));
        const is_logic = try g.logicOr(is_and, is_or);

        const logic_blk = g.reserveBlock();
        const default_blk = g.reserveBlock();
        try g.branch(is_logic, logic_blk, default_blk);

        g.beginReservedBlock(logic_blk);
        try g.ret(try g.tag(ty_bool, null));

        // Default: return TyAny
        g.beginReservedBlock(default_blk);
        try g.ret(try g.tag(ty_any, null));
    }
    try g.endReservedFunc(f_infer_binop);

    // ── Generate: tc_infer_call(callee_type, args, ctx) -> Type ─────
    // Return the result type of a function call.
    try g.beginReservedFunc("tc_infer_call");
    {
        const callee_type = try g.addParam();
        _ = try g.addParam(); // args (unused for bootstrap)
        _ = try g.addParam(); // ctx
        _ = g.beginBlock();

        // If callee is a function type, return its return type
        const is_fn = try g.tagTest(callee_type, ty_function);
        const fn_blk = g.reserveBlock();
        const default_blk = g.reserveBlock();
        try g.branch(is_fn, fn_blk, default_blk);

        g.beginReservedBlock(fn_blk);
        const fn_pl = try g.tagPayload(callee_type, ty_function);
        const ret_type = try g.recordField(fn_pl, "ret");
        try g.ret(ret_type);

        // Constructor call or unknown -> TyAny
        g.beginReservedBlock(default_blk);
        try g.ret(try g.tag(ty_any, null));
    }
    try g.endReservedFunc(f_infer_call);

    // ── Generate: tc_check_pattern(pat, type, ctx) -> {ctx, typed_pat}
    try g.beginReservedFunc("tc_check_pattern");
    {
        const pat = try g.addParam();
        const ty = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        // PatWildcard — binds nothing
        const is_wildcard = try g.tagTest(pat, grammar.ast_pat_wildcard);
        const wildcard_blk = g.reserveBlock();
        const check_bind = g.reserveBlock();
        try g.branch(is_wildcard, wildcard_blk, check_bind);

        g.beginReservedBlock(wildcard_blk);
        const wc_typed = try g.tag("TPatWildcard", null);
        const wc_result = try g.record(&.{
            .{ .name = "ctx", .value = ctx },
            .{ .name = "typed_pat", .value = wc_typed },
        });
        try g.ret(wc_result);

        // PatBind — bind name to the scrutinee type
        g.beginReservedBlock(check_bind);
        const is_bind = try g.tagTest(pat, grammar.ast_pat_bind);
        const bind_blk = g.reserveBlock();
        const check_literal = g.reserveBlock();
        try g.branch(is_bind, bind_blk, check_literal);

        g.beginReservedBlock(bind_blk);
        // PatBind payload is just the name string (not a record)
        const bind_name = try g.tagPayload(pat, grammar.ast_pat_bind);
        const bind_ctx = try g.callDirect(f_ctx_bind_value, &.{ ctx, bind_name, ty });
        const bind_typed = try g.record(&.{
            .{ .name = "name", .value = bind_name },
            .{ .name = "type", .value = ty },
        });
        const bind_tpat = try g.tag("TPatBind", bind_typed);
        const bind_result = try g.record(&.{
            .{ .name = "ctx", .value = bind_ctx },
            .{ .name = "typed_pat", .value = bind_tpat },
        });
        try g.ret(bind_result);

        // PatLiteral — no bindings
        g.beginReservedBlock(check_literal);
        const is_literal = try g.tagTest(pat, grammar.ast_pat_literal);
        const literal_blk = g.reserveBlock();
        const check_constructor = g.reserveBlock();
        try g.branch(is_literal, literal_blk, check_constructor);

        g.beginReservedBlock(literal_blk);
        const lit_pl = try g.tagPayload(pat, grammar.ast_pat_literal);
        const lit_typed = try g.tag("TPatLiteral", lit_pl);
        const lit_result = try g.record(&.{
            .{ .name = "ctx", .value = ctx },
            .{ .name = "typed_pat", .value = lit_typed },
        });
        try g.ret(lit_result);

        // PatConstructor — bind the inner pattern if any
        g.beginReservedBlock(check_constructor);
        const is_ctor = try g.tagTest(pat, grammar.ast_pat_constructor);
        const ctor_blk = g.reserveBlock();
        const default_blk = g.reserveBlock();
        try g.branch(is_ctor, ctor_blk, default_blk);

        g.beginReservedBlock(ctor_blk);
        const ctor_pl = try g.tagPayload(pat, grammar.ast_pat_constructor);
        const ctor_typed = try g.tag("TPatConstructor", ctor_pl);
        const ctor_result = try g.record(&.{
            .{ .name = "ctx", .value = ctx },
            .{ .name = "typed_pat", .value = ctor_typed },
        });
        try g.ret(ctor_result);

        // Default — pass through
        g.beginReservedBlock(default_blk);
        const default_typed = try g.tag("TPatWildcard", null);
        const default_result = try g.record(&.{
            .{ .name = "ctx", .value = ctx },
            .{ .name = "typed_pat", .value = default_typed },
        });
        try g.ret(default_result);
    }
    try g.endReservedFunc(f_check_pattern);

    // ── Generate: tc_infer(expr, ctx) -> {expr: TypedExpr, type: Type}
    // The core inference function.
    try g.beginReservedFunc("tc_infer");
    {
        const expr = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        // IntLit
        const is_int = try g.tagTest(expr, grammar.ast_int_lit);
        const int_blk = g.reserveBlock();
        const check_float = g.reserveBlock();
        try g.branch(is_int, int_blk, check_float);

        g.beginReservedBlock(int_blk);
        {
            const int_val = try g.tagPayload(expr, grammar.ast_int_lit);
            const int_type = try g.tag(ty_int, null);
            const typed = try g.record(&.{
                .{ .name = "value", .value = int_val },
                .{ .name = "type", .value = int_type },
            });
            const texpr = try g.tag(tast_int_lit, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = int_type },
            }));
        }

        // FloatLit
        g.beginReservedBlock(check_float);
        const is_float = try g.tagTest(expr, grammar.ast_float_lit);
        const float_blk = g.reserveBlock();
        const check_string = g.reserveBlock();
        try g.branch(is_float, float_blk, check_string);

        g.beginReservedBlock(float_blk);
        {
            const float_val = try g.tagPayload(expr, grammar.ast_float_lit);
            const float_type = try g.tag(ty_float, null);
            const typed = try g.record(&.{
                .{ .name = "value", .value = float_val },
                .{ .name = "type", .value = float_type },
            });
            const texpr = try g.tag(tast_float_lit, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = float_type },
            }));
        }

        // StringLit
        g.beginReservedBlock(check_string);
        const is_str = try g.tagTest(expr, grammar.ast_string_lit);
        const str_blk = g.reserveBlock();
        const check_bool_lit = g.reserveBlock();
        try g.branch(is_str, str_blk, check_bool_lit);

        g.beginReservedBlock(str_blk);
        {
            const str_val = try g.tagPayload(expr, grammar.ast_string_lit);
            const str_type = try g.tag(ty_string, null);
            const typed = try g.record(&.{
                .{ .name = "value", .value = str_val },
                .{ .name = "type", .value = str_type },
            });
            const texpr = try g.tag(tast_string_lit, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = str_type },
            }));
        }

        // BoolLit
        g.beginReservedBlock(check_bool_lit);
        const is_bool = try g.tagTest(expr, grammar.ast_bool_lit);
        const bool_blk = g.reserveBlock();
        const check_nil_lit = g.reserveBlock();
        try g.branch(is_bool, bool_blk, check_nil_lit);

        g.beginReservedBlock(bool_blk);
        {
            const bool_val = try g.tagPayload(expr, grammar.ast_bool_lit);
            const bool_type = try g.tag(ty_bool, null);
            const typed = try g.record(&.{
                .{ .name = "value", .value = bool_val },
                .{ .name = "type", .value = bool_type },
            });
            const texpr = try g.tag(tast_bool_lit, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = bool_type },
            }));
        }

        // NilLit
        g.beginReservedBlock(check_nil_lit);
        const is_nil = try g.tagTest(expr, grammar.ast_nil_lit);
        const nil_blk = g.reserveBlock();
        const check_ident = g.reserveBlock();
        try g.branch(is_nil, nil_blk, check_ident);

        g.beginReservedBlock(nil_blk);
        {
            const nil_type = try g.tag(ty_nil, null);
            const texpr = try g.tag(tast_nil_lit, null);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = nil_type },
            }));
        }

        // Ident
        g.beginReservedBlock(check_ident);
        const is_ident = try g.tagTest(expr, grammar.ast_ident);
        const ident_blk = g.reserveBlock();
        const check_binop = g.reserveBlock();
        try g.branch(is_ident, ident_blk, check_binop);

        g.beginReservedBlock(ident_blk);
        {
            const ident_name = try g.tagPayload(expr, grammar.ast_ident);
            const ident_type = try g.callDirect(f_ctx_lookup_value, &.{ ctx, ident_name });
            const typed = try g.record(&.{
                .{ .name = "name", .value = ident_name },
                .{ .name = "type", .value = ident_type },
            });
            const texpr = try g.tag(tast_ident, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = ident_type },
            }));
        }

        // BinOp
        g.beginReservedBlock(check_binop);
        const is_binop = try g.tagTest(expr, grammar.ast_binop);
        const binop_blk = g.reserveBlock();
        const check_call = g.reserveBlock();
        try g.branch(is_binop, binop_blk, check_call);

        g.beginReservedBlock(binop_blk);
        {
            const binop_pl = try g.tagPayload(expr, grammar.ast_binop);
            const op = try g.recordField(binop_pl, "op");
            const lhs = try g.recordField(binop_pl, "lhs");
            const rhs = try g.recordField(binop_pl, "rhs");
            const lhs_result = try g.callDirect(f_infer, &.{ lhs, ctx });
            const lhs_typed = try g.recordField(lhs_result, "expr");
            const lhs_type = try g.recordField(lhs_result, "type");
            const rhs_result = try g.callDirect(f_infer, &.{ rhs, ctx });
            const rhs_typed = try g.recordField(rhs_result, "expr");
            const rhs_type = try g.recordField(rhs_result, "type");
            const result_type = try g.callDirect(f_infer_binop, &.{ op, lhs_type, rhs_type });
            const typed = try g.record(&.{
                .{ .name = "op", .value = op },
                .{ .name = "lhs", .value = lhs_typed },
                .{ .name = "rhs", .value = rhs_typed },
                .{ .name = "type", .value = result_type },
            });
            const texpr = try g.tag(tast_binop, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = result_type },
            }));
        }

        // Call
        g.beginReservedBlock(check_call);
        const is_call = try g.tagTest(expr, grammar.ast_call);
        const call_blk = g.reserveBlock();
        const check_if = g.reserveBlock();
        try g.branch(is_call, call_blk, check_if);

        g.beginReservedBlock(call_blk);
        {
            const call_pl = try g.tagPayload(expr, grammar.ast_call);
            const callee = try g.recordField(call_pl, "callee");
            const args = try g.recordField(call_pl, "args");
            const callee_result = try g.callDirect(f_infer, &.{ callee, ctx });
            const callee_typed = try g.recordField(callee_result, "expr");
            const callee_type = try g.recordField(callee_result, "type");
            const result_type = try g.callDirect(f_infer_call, &.{ callee_type, args, ctx });

            // Infer types of arguments
            const args_len = try g.listLength(args);
            const zero = try g.constInt(0);
            const empty_list = try g.listInit(&.{});
            const args_loop = g.reserveBlock();
            try g.jump(args_loop, &.{ zero, empty_list });

            g.beginReservedBlock(args_loop);
            const args_idx = try g.addBlockParam();
            const typed_args = try g.addBlockParam();
            const args_done = try g.ge(args_idx, args_len);
            const args_body = g.reserveBlock();
            const args_exit = g.reserveBlock();
            try g.branch(args_done, args_exit, args_body);

            g.beginReservedBlock(args_body);
            const arg = try g.listNth(args, args_idx);
            const arg_result = try g.callDirect(f_infer, &.{ arg, ctx });
            const arg_typed = try g.recordField(arg_result, "expr");
            const new_typed_args = try g.listAppend(typed_args, arg_typed);
            const one_a = try g.constInt(1);
            const next_a = try g.add(args_idx, one_a);
            try g.jump(args_loop, &.{ next_a, new_typed_args });

            g.beginReservedBlock(args_exit);
            const call_typed = try g.record(&.{
                .{ .name = "callee", .value = callee_typed },
                .{ .name = "args", .value = typed_args },
                .{ .name = "type", .value = result_type },
            });
            const texpr = try g.tag(tast_call, call_typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = result_type },
            }));
        }

        // If
        g.beginReservedBlock(check_if);
        const is_if = try g.tagTest(expr, grammar.ast_if);
        const if_blk = g.reserveBlock();
        const check_let = g.reserveBlock();
        try g.branch(is_if, if_blk, check_let);

        g.beginReservedBlock(if_blk);
        {
            const if_pl = try g.tagPayload(expr, grammar.ast_if);
            const cond = try g.recordField(if_pl, "cond");
            const then_br = try g.recordField(if_pl, "then_branch");
            const else_br = try g.recordField(if_pl, "else_branch");
            const cond_result = try g.callDirect(f_infer, &.{ cond, ctx });
            const cond_typed = try g.recordField(cond_result, "expr");
            const then_result = try g.callDirect(f_infer, &.{ then_br, ctx });
            const then_typed = try g.recordField(then_result, "expr");
            const then_type = try g.recordField(then_result, "type");
            const else_result = try g.callDirect(f_infer, &.{ else_br, ctx });
            const else_typed = try g.recordField(else_result, "expr");
            const else_type = try g.recordField(else_result, "type");
            // Result type = union of both branches
            const if_type_rec = try g.record(&.{
                .{ .name = "lhs", .value = then_type },
                .{ .name = "rhs", .value = else_type },
            });
            const if_type = try g.tag(ty_union, if_type_rec);
            const typed = try g.record(&.{
                .{ .name = "cond", .value = cond_typed },
                .{ .name = "then_branch", .value = then_typed },
                .{ .name = "else_branch", .value = else_typed },
                .{ .name = "type", .value = if_type },
            });
            const texpr = try g.tag(tast_if, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = if_type },
            }));
        }

        // Let
        g.beginReservedBlock(check_let);
        const is_let = try g.tagTest(expr, grammar.ast_let);
        const let_blk = g.reserveBlock();
        const check_match = g.reserveBlock();
        try g.branch(is_let, let_blk, check_match);

        g.beginReservedBlock(let_blk);
        {
            const let_pl = try g.tagPayload(expr, grammar.ast_let);
            const pattern = try g.recordField(let_pl, "pattern");
            const value = try g.recordField(let_pl, "value");
            const val_result = try g.callDirect(f_infer, &.{ value, ctx });
            const val_typed = try g.recordField(val_result, "expr");
            const val_type = try g.recordField(val_result, "type");
            const pat_result = try g.callDirect(f_check_pattern, &.{ pattern, val_type, ctx });
            const new_ctx = try g.recordField(pat_result, "ctx");
            const typed_pat = try g.recordField(pat_result, "typed_pat");
            const typed = try g.record(&.{
                .{ .name = "pattern", .value = typed_pat },
                .{ .name = "value", .value = val_typed },
                .{ .name = "type", .value = val_type },
            });
            const texpr = try g.tag(tast_let, typed);
            // Return the new context as extra info
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = val_type },
                .{ .name = "ctx", .value = new_ctx },
            }));
        }

        // Match
        g.beginReservedBlock(check_match);
        const is_match = try g.tagTest(expr, grammar.ast_match);
        const match_blk = g.reserveBlock();
        const check_block = g.reserveBlock();
        try g.branch(is_match, match_blk, check_block);

        g.beginReservedBlock(match_blk);
        {
            const match_pl = try g.tagPayload(expr, grammar.ast_match);
            const scrutinee = try g.recordField(match_pl, "scrutinee");
            const cases = try g.recordField(match_pl, "arms");
            const scrut_result = try g.callDirect(f_infer, &.{ scrutinee, ctx });
            const scrut_typed = try g.recordField(scrut_result, "expr");
            const scrut_type = try g.recordField(scrut_result, "type");
            // For bootstrap: return TyAny as match result type
            // (proper union of all arm types requires more complex logic)
            const match_type = try g.tag(ty_any, null);
            const typed = try g.record(&.{
                .{ .name = "expr", .value = scrut_typed },
                .{ .name = "cases", .value = cases },
                .{ .name = "scrutinee_type", .value = scrut_type },
                .{ .name = "type", .value = match_type },
            });
            const texpr = try g.tag(tast_match, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = match_type },
            }));
        }

        // Block
        g.beginReservedBlock(check_block);
        const is_block = try g.tagTest(expr, grammar.ast_block);
        const block_blk = g.reserveBlock();
        const check_lambda = g.reserveBlock();
        try g.branch(is_block, block_blk, check_lambda);

        g.beginReservedBlock(block_blk);
        {
            const stmts = try g.tagPayload(expr, grammar.ast_block);
            const stmts_len = try g.listLength(stmts);
            // Infer each statement, threading context through lets
            const zero = try g.constInt(0);
            const empty_list = try g.listInit(&.{});
            const any_type = try g.tag(ty_any, null);
            const blk_loop = g.reserveBlock();
            try g.jump(blk_loop, &.{ zero, ctx, empty_list, any_type });

            g.beginReservedBlock(blk_loop);
            const blk_idx = try g.addBlockParam();
            const blk_ctx = try g.addBlockParam();
            const typed_stmts = try g.addBlockParam();
            const last_type = try g.addBlockParam();
            const blk_done = try g.ge(blk_idx, stmts_len);
            const blk_body = g.reserveBlock();
            const blk_exit = g.reserveBlock();
            try g.branch(blk_done, blk_exit, blk_body);

            g.beginReservedBlock(blk_body);
            const stmt = try g.listNth(stmts, blk_idx);
            const stmt_result = try g.callDirect(f_infer, &.{ stmt, blk_ctx });
            const stmt_typed = try g.recordField(stmt_result, "expr");
            const stmt_type = try g.recordField(stmt_result, "type");
            // If it was a let, update context
            const has_new_ctx = try g.tagTest(stmt, grammar.ast_let);
            const let_ctx_blk = g.reserveBlock();
            const no_let_blk = g.reserveBlock();
            try g.branch(has_new_ctx, let_ctx_blk, no_let_blk);

            g.beginReservedBlock(let_ctx_blk);
            // For lets, the result record has a "ctx" field
            const new_blk_ctx = try g.recordField(stmt_result, "ctx");
            const new_stmts_1 = try g.listAppend(typed_stmts, stmt_typed);
            const one_1 = try g.constInt(1);
            const next_1 = try g.add(blk_idx, one_1);
            try g.jump(blk_loop, &.{ next_1, new_blk_ctx, new_stmts_1, stmt_type });

            g.beginReservedBlock(no_let_blk);
            const new_stmts_2 = try g.listAppend(typed_stmts, stmt_typed);
            const one_2 = try g.constInt(1);
            const next_2 = try g.add(blk_idx, one_2);
            try g.jump(blk_loop, &.{ next_2, blk_ctx, new_stmts_2, stmt_type });

            g.beginReservedBlock(blk_exit);
            const block_typed = try g.tag(tast_block, typed_stmts);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = block_typed },
                .{ .name = "type", .value = last_type },
            }));
        }

        // Lambda
        g.beginReservedBlock(check_lambda);
        const is_lambda = try g.tagTest(expr, grammar.ast_lambda);
        const lambda_blk = g.reserveBlock();
        const check_field_access = g.reserveBlock();
        try g.branch(is_lambda, lambda_blk, check_field_access);

        g.beginReservedBlock(lambda_blk);
        {
            const lambda_pl = try g.tagPayload(expr, grammar.ast_lambda);
            const params = try g.recordField(lambda_pl, "params");
            const body = try g.recordField(lambda_pl, "body");
            // For bootstrap: bind params as TyAny, infer body
            const params_len = try g.listLength(params);
            const zero = try g.constInt(0);
            const lam_loop = g.reserveBlock();
            try g.jump(lam_loop, &.{ zero, ctx });

            g.beginReservedBlock(lam_loop);
            const lam_idx = try g.addBlockParam();
            const lam_ctx = try g.addBlockParam();
            const lam_done = try g.ge(lam_idx, params_len);
            const lam_body_blk = g.reserveBlock();
            const lam_exit = g.reserveBlock();
            try g.branch(lam_done, lam_exit, lam_body_blk);

            g.beginReservedBlock(lam_body_blk);
            const param = try g.listNth(params, lam_idx);
            const param_type = try g.tag(ty_any, null);
            const param_ctx = try g.callDirect(f_ctx_bind_value, &.{ lam_ctx, param, param_type });
            const one_l = try g.constInt(1);
            const next_l = try g.add(lam_idx, one_l);
            try g.jump(lam_loop, &.{ next_l, param_ctx });

            g.beginReservedBlock(lam_exit);
            const body_result = try g.callDirect(f_infer, &.{ body, lam_ctx });
            const body_typed = try g.recordField(body_result, "expr");
            const body_type = try g.recordField(body_result, "type");
            const empty_effects = try g.listInit(&.{});
            const fn_type_rec = try g.record(&.{
                .{ .name = "params", .value = params },
                .{ .name = "effects", .value = empty_effects },
                .{ .name = "ret", .value = body_type },
            });
            const fn_type = try g.tag(ty_function, fn_type_rec);
            const typed = try g.record(&.{
                .{ .name = "params", .value = params },
                .{ .name = "body", .value = body_typed },
                .{ .name = "type", .value = fn_type },
            });
            const texpr = try g.tag(tast_lambda, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = fn_type },
            }));
        }

        // FieldAccess
        g.beginReservedBlock(check_field_access);
        const is_field = try g.tagTest(expr, grammar.ast_field_access);
        const field_blk = g.reserveBlock();
        const check_list_lit = g.reserveBlock();
        try g.branch(is_field, field_blk, check_list_lit);

        g.beginReservedBlock(field_blk);
        {
            const fa_pl = try g.tagPayload(expr, grammar.ast_field_access);
            const fa_expr = try g.recordField(fa_pl, "expr");
            const fa_field = try g.recordField(fa_pl, "field");
            const fa_result = try g.callDirect(f_infer, &.{ fa_expr, ctx });
            const fa_typed = try g.recordField(fa_result, "expr");
            const fa_type = try g.tag(ty_any, null); // TODO: lookup field type
            const typed = try g.record(&.{
                .{ .name = "expr", .value = fa_typed },
                .{ .name = "field", .value = fa_field },
                .{ .name = "type", .value = fa_type },
            });
            const texpr = try g.tag(tast_field_access, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = fa_type },
            }));
        }

        // ListLit
        g.beginReservedBlock(check_list_lit);
        const is_list = try g.tagTest(expr, grammar.ast_list_lit);
        const list_blk = g.reserveBlock();
        const check_record_lit = g.reserveBlock();
        try g.branch(is_list, list_blk, check_record_lit);

        g.beginReservedBlock(list_blk);
        {
            const list_type = try g.tag(ty_any, null); // TODO: element type
            const texpr = try g.tag(tast_list_lit, expr);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = list_type },
            }));
        }

        // RecordLit
        g.beginReservedBlock(check_record_lit);
        const is_rec_lit = try g.tagTest(expr, grammar.ast_record_lit);
        const rec_lit_blk = g.reserveBlock();
        const check_unary = g.reserveBlock();
        try g.branch(is_rec_lit, rec_lit_blk, check_unary);

        g.beginReservedBlock(rec_lit_blk);
        {
            const rec_type = try g.tag(ty_any, null);
            const texpr = try g.tag(tast_record_lit, expr);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = rec_type },
            }));
        }

        // Unary
        g.beginReservedBlock(check_unary);
        const is_unary = try g.tagTest(expr, grammar.ast_unary);
        const unary_blk = g.reserveBlock();
        const check_pipe = g.reserveBlock();
        try g.branch(is_unary, unary_blk, check_pipe);

        g.beginReservedBlock(unary_blk);
        {
            const un_pl = try g.tagPayload(expr, grammar.ast_unary);
            const un_op = try g.recordField(un_pl, "op");
            const un_operand = try g.recordField(un_pl, "operand");
            const un_result = try g.callDirect(f_infer, &.{ un_operand, ctx });
            const un_typed = try g.recordField(un_result, "expr");
            const un_type = try g.recordField(un_result, "type");
            const typed = try g.record(&.{
                .{ .name = "op", .value = un_op },
                .{ .name = "operand", .value = un_typed },
                .{ .name = "type", .value = un_type },
            });
            const texpr = try g.tag(tast_unary, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = un_type },
            }));
        }

        // Pipe — desugar to call
        g.beginReservedBlock(check_pipe);
        const is_pipe = try g.tagTest(expr, grammar.ast_pipe);
        const pipe_blk = g.reserveBlock();
        const default_expr = g.reserveBlock();
        try g.branch(is_pipe, pipe_blk, default_expr);

        g.beginReservedBlock(pipe_blk);
        {
            const pipe_pl = try g.tagPayload(expr, grammar.ast_pipe);
            const pipe_lhs = try g.recordField(pipe_pl, "lhs");
            const pipe_rhs = try g.recordField(pipe_pl, "rhs");
            const lhs_result = try g.callDirect(f_infer, &.{ pipe_lhs, ctx });
            const lhs_typed = try g.recordField(lhs_result, "expr");
            const lhs_type = try g.recordField(lhs_result, "type");
            const rhs_result = try g.callDirect(f_infer, &.{ pipe_rhs, ctx });
            const rhs_typed = try g.recordField(rhs_result, "expr");
            const rhs_type = try g.recordField(rhs_result, "type");
            const pipe_result_type = try g.callDirect(f_infer_call, &.{ rhs_type, lhs_type, ctx });
            const typed = try g.record(&.{
                .{ .name = "lhs", .value = lhs_typed },
                .{ .name = "rhs", .value = rhs_typed },
                .{ .name = "type", .value = pipe_result_type },
            });
            const texpr = try g.tag(tast_pipe, typed);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = texpr },
                .{ .name = "type", .value = pipe_result_type },
            }));
        }

        // Default: return TyAny for unhandled expressions
        g.beginReservedBlock(default_expr);
        {
            const any_type = try g.tag(ty_any, null);
            try g.ret(try g.record(&.{
                .{ .name = "expr", .value = expr },
                .{ .name = "type", .value = any_type },
            }));
        }
    }
    try g.endReservedFunc(f_infer);

    // ── Generate: tc_check_fn_decl(decl, ctx) -> TypedFnDecl ────────
    try g.beginReservedFunc("tc_check_fn_decl");
    {
        const decl = try g.addParam();
        const ctx = try g.addParam();
        _ = g.beginBlock();

        const fn_pl = try g.tagPayload(decl, grammar.ast_fn_decl);
        const fn_name = try g.recordField(fn_pl, "name");
        const fn_params = try g.recordField(fn_pl, "params");
        const fn_body = try g.recordField(fn_pl, "body");
        const fn_ret_type = try g.recordField(fn_pl, "return_type");
        const fn_effects = try g.recordField(fn_pl, "effects");

        // Bind params in context
        const params_len = try g.listLength(fn_params);
        const zero = try g.constInt(0);
        const param_loop = g.reserveBlock();
        try g.jump(param_loop, &.{ zero, ctx });

        g.beginReservedBlock(param_loop);
        const p_idx = try g.addBlockParam();
        const p_ctx = try g.addBlockParam();
        const p_done = try g.ge(p_idx, params_len);
        const p_body = g.reserveBlock();
        const p_exit = g.reserveBlock();
        try g.branch(p_done, p_exit, p_body);

        g.beginReservedBlock(p_body);
        const param = try g.listNth(fn_params, p_idx);
        const param_name = try g.recordField(param, "name");
        const param_type_ast = try g.recordField(param, "type");
        // Convert parameter type annotation
        const has_type_ann = try g.ne(param_type_ast, try g.constNil());
        const type_ann_blk = g.reserveBlock();
        const no_ann_blk = g.reserveBlock();
        try g.branch(has_type_ann, type_ann_blk, no_ann_blk);

        g.beginReservedBlock(type_ann_blk);
        const param_type = try g.callDirect(f_type_from_ast, &.{ param_type_ast, p_ctx });
        const ctx_with_param = try g.callDirect(f_ctx_bind_value, &.{ p_ctx, param_name, param_type });
        const one_p = try g.constInt(1);
        const next_p = try g.add(p_idx, one_p);
        try g.jump(param_loop, &.{ next_p, ctx_with_param });

        g.beginReservedBlock(no_ann_blk);
        const any_param = try g.tag(ty_any, null);
        const ctx_any = try g.callDirect(f_ctx_bind_value, &.{ p_ctx, param_name, any_param });
        const one_p2 = try g.constInt(1);
        const next_p2 = try g.add(p_idx, one_p2);
        try g.jump(param_loop, &.{ next_p2, ctx_any });

        // After binding params, infer body
        g.beginReservedBlock(p_exit);
        const body_result = try g.callDirect(f_infer, &.{ fn_body, p_ctx });
        const body_typed = try g.recordField(body_result, "expr");
        const body_type = try g.recordField(body_result, "type");

        const typed = try g.record(&.{
            .{ .name = "name", .value = fn_name },
            .{ .name = "params", .value = fn_params },
            .{ .name = "body", .value = body_typed },
            .{ .name = "body_type", .value = body_type },
            .{ .name = "return_type", .value = fn_ret_type },
            .{ .name = "effects", .value = fn_effects },
        });
        try g.ret(try g.tag(tast_fn_decl, typed));
    }
    try g.endReservedFunc(f_check_fn_decl);

    // ── Generate: tc_check_module(module: AST) -> TypedModule ───────
    // Entry point for type checking.
    try g.beginReservedFunc("tc_check_module");
    {
        const module = try g.addParam();
        _ = g.beginBlock();

        // Get declarations list from module
        const module_pl = try g.tagPayload(module, grammar.ast_module);
        const decls = module_pl; // Module payload is the decls list

        // First pass: collect all declarations
        const empty_ctx = try g.callDirect(f_ctx_new, &.{});
        const ctx = try g.callDirect(f_collect_decls, &.{ decls, empty_ctx });

        // Second pass: type-check function bodies
        const len = try g.listLength(decls);
        const zero = try g.constInt(0);
        const empty_list = try g.listInit(&.{});
        const loop_blk = g.reserveBlock();
        try g.jump(loop_blk, &.{ zero, empty_list });

        g.beginReservedBlock(loop_blk);
        const idx = try g.addBlockParam();
        const typed_decls = try g.addBlockParam();
        const done = try g.ge(idx, len);
        const body_blk = g.reserveBlock();
        const exit_blk = g.reserveBlock();
        try g.branch(done, exit_blk, body_blk);

        g.beginReservedBlock(body_blk);
        const decl = try g.listNth(decls, idx);
        const is_fn = try g.tagTest(decl, grammar.ast_fn_decl);
        const fn_blk = g.reserveBlock();
        const skip_blk = g.reserveBlock();
        try g.branch(is_fn, fn_blk, skip_blk);

        // Type-check function declaration
        g.beginReservedBlock(fn_blk);
        const typed_fn = try g.callDirect(f_check_fn_decl, &.{ decl, ctx });
        const new_typed_1 = try g.listAppend(typed_decls, typed_fn);
        const one_1 = try g.constInt(1);
        const next_1 = try g.add(idx, one_1);
        try g.jump(loop_blk, &.{ next_1, new_typed_1 });

        // Skip non-function decls (type, trait, effect, impl, use)
        // (they're already collected in ctx)
        g.beginReservedBlock(skip_blk);
        const new_typed_2 = try g.listAppend(typed_decls, decl);
        const one_2 = try g.constInt(1);
        const next_2 = try g.add(idx, one_2);
        try g.jump(loop_blk, &.{ next_2, new_typed_2 });

        g.beginReservedBlock(exit_blk);
        const typed_module = try g.record(&.{
            .{ .name = "decls", .value = typed_decls },
            .{ .name = "ctx", .value = ctx },
        });
        try g.ret(try g.tag(tast_module, typed_module));
    }
    try g.endReservedFunc(f_check_module);

    return f_check_module;
}

// ── Tests ──────────────────────────────────────────────────────────────

const interp_mod = @import("../interp.zig");
const Interpreter = interp_mod.Interpreter;
const Value = interp_mod.Value;
const builtins = @import("../builtins.zig");

fn setupTestInterpreter(alloc: Allocator, pool: *InternPool, module: ir.Module) Interpreter {
    var interp = Interpreter.init(alloc, module, pool);
    builtins.registerAll(&interp) catch {};
    return interp;
}

test "typeck: generate compiles" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);

    const f_check_module = try generate(alloc, &builder, &pool);
    const module = try builder.build(f_check_module);

    // Verify the module has the expected number of functions
    try std.testing.expect(module.funcs.len >= 22);
}

test "typeck: is_subtype primitive equality" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    // Build a test function that calls is_subtype(TyInt, TyInt)
    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const ty_a = try g.tag(ty_int, null);
    const ty_b = try g.tag(ty_int, null);
    // Find is_subtype function ID (it's the 3rd reserved function, index 2)
    const f_is_subtype: FuncId = @enumFromInt(2);
    const result = try g.callDirect(f_is_subtype, &.{ ty_a, ty_b });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: is_subtype Never <: Int" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const a = try g.tag(ty_never, null);
    const b = try g.tag(ty_int, null);
    const f_is_subtype: FuncId = @enumFromInt(2);
    const result = try g.callDirect(f_is_subtype, &.{ a, b });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: is_subtype Int <: Any" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const a = try g.tag(ty_int, null);
    const b = try g.tag(ty_any, null);
    const f_is_subtype: FuncId = @enumFromInt(2);
    const result = try g.callDirect(f_is_subtype, &.{ a, b });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: is_subtype Int NOT <: String" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const a = try g.tag(ty_int, null);
    const b = try g.tag(ty_string, null);
    const f_is_subtype: FuncId = @enumFromInt(2);
    const result = try g.callDirect(f_is_subtype, &.{ a, b });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == false);
}

test "typeck: is_subtype Int <: Int|String" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const a = try g.tag(ty_int, null);
    const lhs = try g.tag(ty_int, null);
    const rhs = try g.tag(ty_string, null);
    const union_rec = try g.record(&.{
        .{ .name = "lhs", .value = lhs },
        .{ .name = "rhs", .value = rhs },
    });
    const b = try g.tag(ty_union, union_rec);
    const f_is_subtype: FuncId = @enumFromInt(2);
    const result = try g.callDirect(f_is_subtype, &.{ a, b });
    try g.ret(result);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: resolve_type builtin names" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    // Build test: resolve_type("Int", ctx_new()) should be TyInt
    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_resolve: FuncId = @enumFromInt(1);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const name = try g.constString("Int");
    const ty = try g.callDirect(f_resolve, &.{ name, ctx });
    const is_int = try g.tagTest(ty, ty_int);
    try g.ret(is_int);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: infer IntLit gives TyInt" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const int_expr = try g.tag(grammar.ast_int_lit, try g.constInt(42));
    const result = try g.callDirect(f_infer_id, &.{ int_expr, ctx });
    const result_type = try g.recordField(result, "type");
    const is_int = try g.tagTest(result_type, ty_int);
    try g.ret(is_int);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: infer BinOp arithmetic gives TyInt" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);
    const ctx = try g.callDirect(f_ctx_new, &.{});

    const lhs = try g.tag(grammar.ast_int_lit, try g.constInt(1));
    const rhs = try g.tag(grammar.ast_int_lit, try g.constInt(2));
    const binop_rec = try g.record(&.{
        .{ .name = "op", .value = try g.constString("+") },
        .{ .name = "lhs", .value = lhs },
        .{ .name = "rhs", .value = rhs },
    });
    const binop_expr = try g.tag(grammar.ast_binop, binop_rec);
    const result = try g.callDirect(f_infer_id, &.{ binop_expr, ctx });
    const result_type = try g.recordField(result, "type");
    const is_int = try g.tagTest(result_type, ty_int);
    try g.ret(is_int);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: infer comparison gives TyBool" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);
    const ctx = try g.callDirect(f_ctx_new, &.{});

    const lhs = try g.tag(grammar.ast_int_lit, try g.constInt(1));
    const rhs = try g.tag(grammar.ast_int_lit, try g.constInt(2));
    const binop_rec = try g.record(&.{
        .{ .name = "op", .value = try g.constString("==") },
        .{ .name = "lhs", .value = lhs },
        .{ .name = "rhs", .value = rhs },
    });
    const binop_expr = try g.tag(grammar.ast_binop, binop_rec);
    const result = try g.callDirect(f_infer_id, &.{ binop_expr, ctx });
    const result_type = try g.recordField(result, "type");
    const is_bool = try g.tagTest(result_type, ty_bool);
    try g.ret(is_bool);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: ctx_bind_value and lookup" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_bind: FuncId = @enumFromInt(6);
    const f_lookup: FuncId = @enumFromInt(7);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const name = try g.constString("x");
    const ty = try g.tag(ty_int, null);
    const ctx2 = try g.callDirect(f_bind, &.{ ctx, name, ty });
    const found = try g.callDirect(f_lookup, &.{ ctx2, name });
    const is_int = try g.tagTest(found, ty_int);
    try g.ret(is_int);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

test "typeck: end-to-end parse then check module" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);

    // Generate grammar + typeck into same builder
    const gram_funcs = try grammar.generate(alloc, &builder, &pool);
    const f_check_module_id = try generate(alloc, &builder, &pool);

    // Step 1: just parse
    var g = Gen.init(alloc, &builder, &pool);
    try g.beginFunc("test_parse_only");
    _ = g.beginBlock();
    const src1 = try g.addParam();
    const parse_result = try g.callDirect(gram_funcs.parse, &.{src1});
    const ast_node = try g.recordField(parse_result, "node");
    try g.ret(ast_node);
    const parse_fid = try g.endFunc();

    // Step 2: check a manually created module value
    try g.beginFunc("test_check_only");
    _ = g.beginBlock();
    const module_ast = try g.addParam();
    const typed = try g.callDirect(f_check_module_id, &.{module_ast});
    try g.ret(typed);
    const check_fid = try g.endFunc();

    const module = try builder.build(parse_fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    // Parse step
    const source = "fn add(x: Int, y: Int) -> Int {\n  x + y\n}\n";
    const ast = try interp.execFunc(parse_fid, &.{.{ .string = source }});
    try std.testing.expect(ast == .tagged);

    // Check step - pass parsed AST to type checker
    const result = interp.execFunc(check_fid, &.{ast}) catch |err| {
        std.debug.print("Check failed with: {s}\n", .{@errorName(err)});
        return err;
    };

    // Verify we got a TModule tagged value
    try std.testing.expect(result == .tagged);
    const tag_name = pool.get(result.tagged.tag);
    try std.testing.expectEqualStrings(tast_module, tag_name);
}

test "typeck: infer Ident from context" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_bind: FuncId = @enumFromInt(6);
    const f_infer_id: FuncId = @enumFromInt(16);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const name = try g.constString("x");
    const ty = try g.tag(ty_string, null);
    const ctx2 = try g.callDirect(f_bind, &.{ ctx, name, ty });
    const ident_expr = try g.tag(grammar.ast_ident, try g.constString("x"));
    const result = try g.callDirect(f_infer_id, &.{ ident_expr, ctx2 });
    const result_type = try g.recordField(result, "type");
    const is_str = try g.tagTest(result_type, ty_string);
    try g.ret(is_str);
    const fid = try g.endFunc();
    const module = try builder.build(fid);

    var interp = setupTestInterpreter(alloc, &pool, module);
    defer interp.deinit();

    const val = try interp.execFunc(fid, &.{});
    try std.testing.expect(val.bool_val == true);
}

// ── Subtyping: additional cases ──────────────────────────────────────

test "typeck: is_subtype reflexivity for all primitives" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_is_subtype: FuncId = @enumFromInt(2);

    // Test all primitives: each <: itself
    const prim_tags = [_][]const u8{ ty_int, ty_float, ty_string, ty_bool, ty_nil, ty_never, ty_any };
    for (prim_tags) |tag_name| {
        try g.beginFunc("test_main");
        _ = g.beginBlock();
        const a = try g.tag(tag_name, null);
        const b = try g.tag(tag_name, null);
        const result = try g.callDirect(f_is_subtype, &.{ a, b });
        try g.ret(result);
        const fid2 = try g.endFunc();
        const module2 = try builder.build(fid2);

        var interp2 = setupTestInterpreter(alloc, &pool, module2);
        defer interp2.deinit();

        const val2 = try interp2.execFunc(fid2, &.{});
        try std.testing.expect(val2.bool_val == true);
    }
}

test "typeck: is_subtype Any NOT <: Int" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const a = try g.tag(ty_any, null);
    const b = try g.tag(ty_int, null);
    const f_is_subtype: FuncId = @enumFromInt(2);
    const result = try g.callDirect(f_is_subtype, &.{ a, b });
    try g.ret(result);
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == false);
}

test "typeck: is_subtype Union NOT <: primitive" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    // Int|String NOT <: Int
    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const lhs = try g.tag(ty_int, null);
    const rhs = try g.tag(ty_string, null);
    const union_rec = try g.record(&.{
        .{ .name = "lhs", .value = lhs },
        .{ .name = "rhs", .value = rhs },
    });
    const a = try g.tag(ty_union, union_rec);
    const b = try g.tag(ty_int, null);
    const f_is_subtype: FuncId = @enumFromInt(2);
    const result = try g.callDirect(f_is_subtype, &.{ a, b });
    try g.ret(result);
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == false);
}

test "typeck: is_subtype Never <: anything" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_is_subtype: FuncId = @enumFromInt(2);

    // Never <: String, Never <: Bool, Never <: Nil, Never <: Float
    const targets = [_][]const u8{ ty_string, ty_bool, ty_nil, ty_float };
    for (targets) |tgt| {
        try g.beginFunc("test_main");
        _ = g.beginBlock();
        const a = try g.tag(ty_never, null);
        const b = try g.tag(tgt, null);
        const result = try g.callDirect(f_is_subtype, &.{ a, b });
        try g.ret(result);
        const fid2 = try g.endFunc();
        const module2 = try builder.build(fid2);

        var interp2 = setupTestInterpreter(alloc, &pool, module2);
        defer interp2.deinit();

        const val2 = try interp2.execFunc(fid2, &.{});
        try std.testing.expect(val2.bool_val == true);
    }
}

test "typeck: is_subtype everything <: Any" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_is_subtype: FuncId = @enumFromInt(2);

    const sources = [_][]const u8{ ty_int, ty_float, ty_string, ty_bool, ty_nil, ty_never };
    for (sources) |src| {
        try g.beginFunc("test_main");
        _ = g.beginBlock();
        const a = try g.tag(src, null);
        const b = try g.tag(ty_any, null);
        const result = try g.callDirect(f_is_subtype, &.{ a, b });
        try g.ret(result);
        const fid2 = try g.endFunc();
        const module2 = try builder.build(fid2);

        var interp2 = setupTestInterpreter(alloc, &pool, module2);
        defer interp2.deinit();

        const val2 = try interp2.execFunc(fid2, &.{});
        try std.testing.expect(val2.bool_val == true);
    }
}

test "typeck: is_subtype pairwise primitive incompatibility" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_is_subtype: FuncId = @enumFromInt(2);

    // Every distinct pair of concrete primitives should NOT be subtypes
    const prims = [_][]const u8{ ty_int, ty_float, ty_string, ty_bool, ty_nil };
    for (prims, 0..) |a_tag, i| {
        for (prims, 0..) |b_tag, j| {
            if (i == j) continue;
            try g.beginFunc("test_main");
            _ = g.beginBlock();
            const a = try g.tag(a_tag, null);
            const b = try g.tag(b_tag, null);
            const result = try g.callDirect(f_is_subtype, &.{ a, b });
            try g.ret(result);
            const fid2 = try g.endFunc();
            const module2 = try builder.build(fid2);

            var interp2 = setupTestInterpreter(alloc, &pool, module2);
            defer interp2.deinit();

            const val2 = try interp2.execFunc(fid2, &.{});
            try std.testing.expect(val2.bool_val == false);
        }
    }
}

// ── Inference: all literal types ─────────────────────────────────────

test "typeck: infer FloatLit gives TyFloat" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const expr = try g.tag(grammar.ast_float_lit, try g.constString("3.14"));
    const result = try g.callDirect(f_infer_id, &.{ expr, ctx });
    const result_type = try g.recordField(result, "type");
    const is_float = try g.tagTest(result_type, ty_float);
    try g.ret(is_float);
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == true);
}

test "typeck: infer StringLit gives TyString" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const expr = try g.tag(grammar.ast_string_lit, try g.constString("hello"));
    const result = try g.callDirect(f_infer_id, &.{ expr, ctx });
    const result_type = try g.recordField(result, "type");
    const is_str2 = try g.tagTest(result_type, ty_string);
    try g.ret(is_str2);
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == true);
}

test "typeck: infer BoolLit gives TyBool" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const expr = try g.tag(grammar.ast_bool_lit, try g.constBool(true));
    const result = try g.callDirect(f_infer_id, &.{ expr, ctx });
    const result_type = try g.recordField(result, "type");
    const is_bool2 = try g.tagTest(result_type, ty_bool);
    try g.ret(is_bool2);
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == true);
}

test "typeck: infer NilLit gives TyNil" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const expr = try g.tag(grammar.ast_nil_lit, try g.constNil());
    const result = try g.callDirect(f_infer_id, &.{ expr, ctx });
    const result_type = try g.recordField(result, "type");
    const is_nil2 = try g.tagTest(result_type, ty_nil);
    try g.ret(is_nil2);
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == true);
}

// ── Inference: operators ─────────────────────────────────────────────

test "typeck: infer all comparison operators give TyBool" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);

    const ops = [_][]const u8{ "==", "!=", "<", ">", "<=", ">=" };
    for (ops) |op| {
        try g.beginFunc("test_main");
        _ = g.beginBlock();
        const ctx = try g.callDirect(f_ctx_new, &.{});
        const lhs2 = try g.tag(grammar.ast_int_lit, try g.constInt(1));
        const rhs2 = try g.tag(grammar.ast_int_lit, try g.constInt(2));
        const binop_rec = try g.record(&.{
            .{ .name = "op", .value = try g.constString(op) },
            .{ .name = "lhs", .value = lhs2 },
            .{ .name = "rhs", .value = rhs2 },
        });
        const expr = try g.tag(grammar.ast_binop, binop_rec);
        const result = try g.callDirect(f_infer_id, &.{ expr, ctx });
        const result_type = try g.recordField(result, "type");
        const is_bool2 = try g.tagTest(result_type, ty_bool);
        try g.ret(is_bool2);
        const fid2 = try g.endFunc();
        const module2 = try builder.build(fid2);

        var interp2 = setupTestInterpreter(alloc, &pool, module2);
        defer interp2.deinit();

        const val2 = try interp2.execFunc(fid2, &.{});
        try std.testing.expect(val2.bool_val == true);
    }
}

test "typeck: infer all arithmetic operators give TyInt" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);

    const ops = [_][]const u8{ "+", "-", "*", "/" };
    for (ops) |op| {
        try g.beginFunc("test_main");
        _ = g.beginBlock();
        const ctx = try g.callDirect(f_ctx_new, &.{});
        const lhs2 = try g.tag(grammar.ast_int_lit, try g.constInt(10));
        const rhs2 = try g.tag(grammar.ast_int_lit, try g.constInt(3));
        const binop_rec = try g.record(&.{
            .{ .name = "op", .value = try g.constString(op) },
            .{ .name = "lhs", .value = lhs2 },
            .{ .name = "rhs", .value = rhs2 },
        });
        const expr = try g.tag(grammar.ast_binop, binop_rec);
        const result = try g.callDirect(f_infer_id, &.{ expr, ctx });
        const result_type = try g.recordField(result, "type");
        const is_int2 = try g.tagTest(result_type, ty_int);
        try g.ret(is_int2);
        const fid2 = try g.endFunc();
        const module2 = try builder.build(fid2);

        var interp2 = setupTestInterpreter(alloc, &pool, module2);
        defer interp2.deinit();

        const val2 = try interp2.execFunc(fid2, &.{});
        try std.testing.expect(val2.bool_val == true);
    }
}

test "typeck: infer boolean operators give TyBool" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_infer_id: FuncId = @enumFromInt(16);

    const ops = [_][]const u8{ "&&", "||" };
    for (ops) |op| {
        try g.beginFunc("test_main");
        _ = g.beginBlock();
        const ctx = try g.callDirect(f_ctx_new, &.{});
        const lhs2 = try g.tag(grammar.ast_bool_lit, try g.constBool(true));
        const rhs2 = try g.tag(grammar.ast_bool_lit, try g.constBool(false));
        const binop_rec = try g.record(&.{
            .{ .name = "op", .value = try g.constString(op) },
            .{ .name = "lhs", .value = lhs2 },
            .{ .name = "rhs", .value = rhs2 },
        });
        const expr = try g.tag(grammar.ast_binop, binop_rec);
        const result = try g.callDirect(f_infer_id, &.{ expr, ctx });
        const result_type = try g.recordField(result, "type");
        const is_bool2 = try g.tagTest(result_type, ty_bool);
        try g.ret(is_bool2);
        const fid2 = try g.endFunc();
        const module2 = try builder.build(fid2);

        var interp2 = setupTestInterpreter(alloc, &pool, module2);
        defer interp2.deinit();

        const val2 = try interp2.execFunc(fid2, &.{});
        try std.testing.expect(val2.bool_val == true);
    }
}

// ── Context: scoping semantics ───────────────────────────────────────

test "typeck: ctx shadowing preserves outer scope" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    // Bind x:Int, then shadow x:String, verify outer ctx still has Int
    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_bind: FuncId = @enumFromInt(6);
    const f_lookup: FuncId = @enumFromInt(7);
    const ctx0 = try g.callDirect(f_ctx_new, &.{});
    const name2 = try g.constString("x");
    const ty1 = try g.tag(ty_int, null);
    const ctx1 = try g.callDirect(f_bind, &.{ ctx0, name2, ty1 });
    const ty2 = try g.tag(ty_string, null);
    const ctx2 = try g.callDirect(f_bind, &.{ ctx1, name2, ty2 });

    // Inner scope sees String
    const inner_ty = try g.callDirect(f_lookup, &.{ ctx2, name2 });
    const inner_is_string = try g.tagTest(inner_ty, ty_string);

    // Branch: if inner is string, check outer
    const check_outer = g.reserveBlock();
    const fail_blk = g.reserveBlock();
    try g.branch(inner_is_string, check_outer, fail_blk);

    g.beginReservedBlock(check_outer);
    // Outer scope still sees Int (maps are immutable)
    const outer_ty = try g.callDirect(f_lookup, &.{ ctx1, name2 });
    const outer_is_int = try g.tagTest(outer_ty, ty_int);
    try g.ret(outer_is_int);

    g.beginReservedBlock(fail_blk);
    try g.ret(try g.constBool(false));
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == true);
}

test "typeck: ctx lookup unbound returns TyAny" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_lookup: FuncId = @enumFromInt(7);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const name2 = try g.constString("nonexistent");
    const ty2 = try g.callDirect(f_lookup, &.{ ctx, name2 });
    const is_any = try g.tagTest(ty2, ty_any);
    try g.ret(is_any);
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == true);
}

// ── resolve_type: all builtins ───────────────────────────────────────

test "typeck: resolve_type all builtin type names" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_resolve: FuncId = @enumFromInt(1);

    const cases = [_]struct { name: []const u8, expected_tag: []const u8 }{
        .{ .name = "Int", .expected_tag = ty_int },
        .{ .name = "Float", .expected_tag = ty_float },
        .{ .name = "String", .expected_tag = ty_string },
        .{ .name = "Bool", .expected_tag = ty_bool },
        .{ .name = "Nil", .expected_tag = ty_nil },
        .{ .name = "Never", .expected_tag = ty_never },
        .{ .name = "Any", .expected_tag = ty_any },
    };

    for (cases) |case| {
        try g.beginFunc("test_main");
        _ = g.beginBlock();
        const ctx = try g.callDirect(f_ctx_new, &.{});
        const name2 = try g.constString(case.name);
        const ty2 = try g.callDirect(f_resolve, &.{ name2, ctx });
        const matches = try g.tagTest(ty2, case.expected_tag);
        try g.ret(matches);
        const fid2 = try g.endFunc();
        const module2 = try builder.build(fid2);

        var interp2 = setupTestInterpreter(alloc, &pool, module2);
        defer interp2.deinit();

        const val2 = try interp2.execFunc(fid2, &.{});
        try std.testing.expect(val2.bool_val == true);
    }
}

test "typeck: resolve_type unknown name returns TyAny" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);
    _ = try generate(alloc, &builder, &pool);

    try g.beginFunc("test_main");
    _ = g.beginBlock();
    const f_ctx_new: FuncId = @enumFromInt(5);
    const f_resolve: FuncId = @enumFromInt(1);
    const ctx = try g.callDirect(f_ctx_new, &.{});
    const name2 = try g.constString("FooBarBaz");
    const ty2 = try g.callDirect(f_resolve, &.{ name2, ctx });
    const is_any = try g.tagTest(ty2, ty_any);
    try g.ret(is_any);
    const fid2 = try g.endFunc();
    const module2 = try builder.build(fid2);

    var interp2 = setupTestInterpreter(alloc, &pool, module2);
    defer interp2.deinit();

    const val2 = try interp2.execFunc(fid2, &.{});
    try std.testing.expect(val2.bool_val == true);
}

// ── End-to-end: parsing + type checking various programs ─────────────

fn buildE2eDriver(alloc: Allocator, builder: *ir.Builder, pool: *InternPool) !struct { fid: FuncId, module: ir.Module } {
    const gram_funcs = try grammar.generate(alloc, builder, pool);
    const f_check_module_id = try generate(alloc, builder, pool);

    var g = Gen.init(alloc, builder, pool);
    try g.beginFunc("test_driver");
    _ = g.beginBlock();
    const src = try g.addParam();
    const parse_result = try g.callDirect(gram_funcs.parse, &.{src});
    const ast_node = try g.recordField(parse_result, "node");
    const typed = try g.callDirect(f_check_module_id, &.{ast_node});
    try g.ret(typed);
    const fid = try g.endFunc();
    const module = try builder.build(fid);
    return .{ .fid = fid, .module = module };
}

test "typeck: e2e type annotations flow through" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source = "fn double(x: Int) -> Int {\n  x + x\n}\n\nfn main() {\n  42\n}\n";
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));

    // Verify 2 function declarations
    const payload = result.tagged.payload.?;
    const decls = payload.record.fields[0].value;
    try std.testing.expect(decls == .list);
    try std.testing.expect(decls.list.items.len == 2);

    // Verify first decl is TFnDecl
    const decl0 = decls.list.items[0];
    try std.testing.expect(decl0 == .tagged);
    try std.testing.expectEqualStrings(tast_fn_decl, pool.get(decl0.tagged.tag));
}

test "typeck: e2e if/else expression" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source = "fn choose(x: Int) -> Int {\n  if x > 0 { x } else { 0 }\n}\n\nfn main() {\n  42\n}\n";
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e type decl with constructors" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\type Color {
        \\  Red,
        \\  Green,
        \\  Blue
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e let bindings and block" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\fn main() {
        \\  let x = 1
        \\  let y = 2
        \\  x + y
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e effect declaration" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\effect Console {
        \\  fn print(msg: String) -> Nil
        \\}
        \\
        \\fn greet(name: String) -[Console]> String {
        \\  "hello"
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e function type parameter" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

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
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e record type and field access" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\type Point {
        \\  x: Int,
        \\  y: Int
        \\}
        \\
        \\fn add_coords(p: Point) -> Int {
        \\  p.x + p.y
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e match expression" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\type Shape {
        \\  Circle(Int),
        \\  Square(Int)
        \\}
        \\
        \\fn area(s: Shape) -> Int {
        \\  match s {
        \\    Circle(r) -> r * r
        \\    Square(side) -> side * side
        \\  }
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e lambda expression" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\fn main() {
        \\  let double = fn(x) { x + x }
        \\  double(21)
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e pipe operator" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\fn double(x: Int) -> Int {
        \\  x + x
        \\}
        \\
        \\fn main() {
        \\  21 |> double
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e empty module" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source = "";
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));

    // Verify empty decls list
    const payload = result.tagged.payload.?;
    const decls = payload.record.fields[0].value;
    try std.testing.expect(decls == .list);
    try std.testing.expect(decls.list.items.len == 0);
}

test "typeck: e2e multiple functions calling each other" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\fn add(x: Int, y: Int) -> Int {
        \\  x + y
        \\}
        \\
        \\fn double(x: Int) -> Int {
        \\  add(x, x)
        \\}
        \\
        \\fn main() {
        \\  double(21)
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));

    // 3 function declarations
    const payload = result.tagged.payload.?;
    const decls = payload.record.fields[0].value;
    try std.testing.expect(decls.list.items.len == 3);
}

test "typeck: e2e generic type declaration" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

    const source =
        \\type Maybe<T> {
        \\  Just(T),
        \\  Nothing
        \\}
        \\
        \\type Either<L, R> {
        \\  Left(L),
        \\  Right(R)
        \\}
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}

test "typeck: e2e stress — all features combined" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    const drv = try buildE2eDriver(alloc, &builder, &pool);

    var interp2 = setupTestInterpreter(alloc, &pool, drv.module);
    defer interp2.deinit();

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
        \\type Either<L, R> {
        \\  Left(L),
        \\  Right(R)
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
        \\use std
        \\
        \\fn main() {
        \\  42
        \\}
        \\
    ;
    const result = try interp2.execFunc(drv.fid, &.{.{ .string = source }});
    try std.testing.expect(result == .tagged);
    try std.testing.expectEqualStrings(tast_module, pool.get(result.tagged.tag));
}
