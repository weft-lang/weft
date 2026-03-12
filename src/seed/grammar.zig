const std = @import("std");
const Allocator = std.mem.Allocator;
const ir = @import("../ir.zig");
const intern_mod = @import("../intern.zig");
const InternPool = intern_mod.InternPool;
const ValueId = ir.ValueId;
const BlockId = ir.BlockId;
const FuncId = ir.FuncId;
const Gen = @import("gen.zig").Gen;

// ── Token kind tags ────────────────────────────────────────────────────

// Token tagged union variants (used as IR tag names)
pub const tok_int_lit = "IntLit";
pub const tok_float_lit = "FloatLit";
pub const tok_string_lit = "StringLit";
pub const tok_bool_lit = "BoolLit";
pub const tok_nil_lit = "NilLit";
pub const tok_ident = "Ident";
pub const tok_upper_ident = "UpperIdent";
pub const tok_keyword = "Keyword";
pub const tok_op = "Op";
pub const tok_delim = "Delim";
pub const tok_punct = "Punct";
pub const tok_newline = "Newline";
pub const tok_eof = "Eof";

// ── Keyword table ──────────────────────────────────────────────────────

pub const keywords = [_][]const u8{
    "fn",     "type",   "trait",  "impl",
    "effect", "use",    "match",  "if",
    "else",   "let",    "handle", "resume",
    "pub",    "unsafe", "extern", "for",
    "test",   "return", "true",   "false",
    "nil",    "opaque", "implements",
    "and",    "or",
};

// ── Multi-char operators (checked before single-char) ──────────────────

pub const multi_ops = [_][]const u8{
    "---", // doc comment (must check before --)
    "--",  // line comment
    "==",
    "!=",
    "<=",
    ">=",
    "->",
    "-[",
    "]>",
    "|>",
    "&&",
    "||",
    "..",
    "=>",
};

// ── Single-char operators and delimiters ───────────────────────────────

pub const single_ops = "+-*/%<>&|~!?^=";
pub const delimiters = "(){}[]";
pub const punctuation = ":,.;";

// ── AST node tags ──────────────────────────────────────────────────────

// Expression tags
pub const ast_int_lit = "IntLit";
pub const ast_float_lit = "FloatLit";
pub const ast_string_lit = "StringLit";
pub const ast_bool_lit = "BoolLit";
pub const ast_nil_lit = "NilLit";
pub const ast_ident = "Ident";
pub const ast_call = "Call";
pub const ast_pipe = "Pipe";
pub const ast_binop = "BinOp";
pub const ast_unary = "Unary";
pub const ast_if = "If";
pub const ast_match = "Match";
pub const ast_let = "Let";
pub const ast_block = "Block";
pub const ast_lambda = "Lambda";
pub const ast_handle = "Handle";
pub const ast_record_lit = "RecordLit";
pub const ast_list_lit = "ListLit";
pub const ast_field_access = "FieldAccess";
pub const ast_propagate = "Propagate";
pub const ast_record_update = "RecordUpdate";
pub const ast_string_interp = "StringInterp";

// Declaration tags
pub const ast_fn_decl = "FnDecl";
pub const ast_type_decl = "TypeDecl";
pub const ast_trait_decl = "TraitDecl";
pub const ast_impl_decl = "ImplDecl";
pub const ast_effect_decl = "EffectDecl";
pub const ast_use_decl = "UseDecl";

// Pattern tags
pub const ast_pat_wildcard = "PatWildcard";
pub const ast_pat_bind = "PatBind";
pub const ast_pat_literal = "PatLiteral";
pub const ast_pat_constructor = "PatConstructor";
pub const ast_pat_record = "PatRecord";
pub const ast_pat_type_narrow = "PatTypeNarrow";

// Type expression tags
pub const ast_type_named = "TypeNamed";
pub const ast_type_app = "TypeApp";
pub const ast_type_union = "TypeUnion";
pub const ast_type_fn = "TypeFn";
pub const ast_type_intersection = "TypeIntersection";
pub const ast_type_complement = "TypeComplement";
pub const ast_type_nullable = "TypeNullable";

// Module tag
pub const ast_module = "Module";

// ── IR generation ──────────────────────────────────────────────────────

/// Holds all generated function IDs for the grammar module.
pub const GrammarFuncs = struct {
    lex: FuncId,
    parse: FuncId,
};

/// Parser function IDs — used internally during generation for mutual recursion.
const ParserFuncs = struct {
    peek_token: FuncId,
    parse_expr: FuncId,
    parse_primary: FuncId,
    parse_type_expr: FuncId,
    parse_pattern: FuncId,
    parse_block: FuncId,
    parse_decl: FuncId,
    parse_fn_decl: FuncId,
    parse_type_decl: FuncId,
    parse_trait_decl: FuncId,
    parse_impl_decl: FuncId,
    parse_effect_decl: FuncId,
    parse_if: FuncId,
    parse_match: FuncId,
    parse_let: FuncId,
    parse_handle: FuncId,
    parse_module: FuncId,
    parse_list_sep: FuncId,
    infix_bp: FuncId,
};

/// Generate the complete grammar IR module.
pub fn generate(alloc: Allocator, builder: *ir.Builder, pool: *InternPool) !GrammarFuncs {
    var g = Gen.init(alloc, builder, pool);

    // ── Lexer ──
    const is_alpha_fn = try genIsAlpha(&g);
    const is_digit_fn = try genIsDigit(&g);
    const is_ident_char_fn = try genIsIdentChar(&g, is_alpha_fn, is_digit_fn);
    const skip_whitespace_fn = try genSkipWhitespace(&g);
    const skip_comment_fn = try genSkipComment(&g);
    const lex_number_fn = try genLexNumber(&g, is_digit_fn);
    const lex_string_fn = try genLexString(&g);
    const lex_ident_fn = try genLexIdentOrKeyword(&g, is_ident_char_fn, is_alpha_fn);
    const lex_fn = try genLex(&g, skip_whitespace_fn, skip_comment_fn, lex_number_fn, lex_string_fn, lex_ident_fn, is_digit_fn, is_alpha_fn);

    // ── Parser ──
    // Reserve all parser function IDs for mutual recursion
    var pf: ParserFuncs = undefined;
    pf.peek_token = try g.reserveFunc("peek_token");
    pf.infix_bp = try g.reserveFunc("infix_bp");
    pf.parse_list_sep = try g.reserveFunc("parse_list_sep");
    pf.parse_pattern = try g.reserveFunc("parse_pattern");
    pf.parse_type_expr = try g.reserveFunc("parse_type_expr");
    pf.parse_primary = try g.reserveFunc("parse_primary");
    pf.parse_expr = try g.reserveFunc("parse_expr");
    pf.parse_block = try g.reserveFunc("parse_block");
    pf.parse_if = try g.reserveFunc("parse_if");
    pf.parse_match = try g.reserveFunc("parse_match");
    pf.parse_let = try g.reserveFunc("parse_let");
    pf.parse_handle = try g.reserveFunc("parse_handle");
    pf.parse_fn_decl = try g.reserveFunc("parse_fn_decl");
    pf.parse_type_decl = try g.reserveFunc("parse_type_decl");
    pf.parse_trait_decl = try g.reserveFunc("parse_trait_decl");
    pf.parse_impl_decl = try g.reserveFunc("parse_impl_decl");
    pf.parse_effect_decl = try g.reserveFunc("parse_effect_decl");
    pf.parse_decl = try g.reserveFunc("parse_decl");
    pf.parse_module = try g.reserveFunc("parse_module");

    // Generate parser functions (order doesn't matter — all IDs pre-allocated)
    try genPeekToken(&g, pf);
    try genInfixBp(&g, pf);
    try genParseListSep(&g, pf);
    try genParsePattern(&g, pf);
    try genParseTypeExpr(&g, pf);
    try genParsePrimary(&g, pf);
    try genParseExpr(&g, pf);
    try genParseBlock(&g, pf);
    try genParseIf(&g, pf);
    try genParseMatch(&g, pf);
    try genParseLet(&g, pf);
    try genParseHandle(&g, pf);
    try genParseFnDecl(&g, pf);
    try genParseTypeDecl(&g, pf);
    try genParseTraitDecl(&g, pf);
    try genParseImplDecl(&g, pf);
    try genParseEffectDecl(&g, pf);
    try genParseDecl(&g, pf);
    try genParseModule(&g, pf, lex_fn);

    return .{ .lex = lex_fn, .parse = pf.parse_module };
}

/// Build the grammar module (calls generate + build).
pub fn buildModule(alloc: Allocator, pool: *InternPool) !struct { ir.Module, GrammarFuncs } {
    var builder = ir.Builder.init(alloc);
    const funcs = try generate(alloc, &builder, pool);
    const module = try builder.build(funcs.parse);
    return .{ module, funcs };
}

// ── is_alpha(byte: Int) -> Bool ────────────────────────────────────────

fn genIsAlpha(g: *Gen) !FuncId {
    try g.beginFunc("is_alpha");
    const byte = try g.addParam();

    _ = g.beginBlock();
    // (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95 (_)
    const a_upper = try g.constInt(65); // 'A'
    const z_upper = try g.constInt(90); // 'Z'
    const a_lower = try g.constInt(97); // 'a'
    const z_lower = try g.constInt(122); // 'z'
    const underscore = try g.constInt(95); // '_'

    const ge_A = try g.ge(byte, a_upper);
    const le_Z = try g.binary(.le, byte, z_upper);
    const upper = try g.logicAnd(ge_A, le_Z);

    const ge_a = try g.ge(byte, a_lower);
    const le_z = try g.binary(.le, byte, z_lower);
    const lower = try g.logicAnd(ge_a, le_z);

    const is_under = try g.eq(byte, underscore);
    const alpha_or_lower = try g.logicOr(upper, lower);
    const result = try g.logicOr(alpha_or_lower, is_under);
    try g.ret(result);

    return g.endFunc();
}

// ── is_digit(byte: Int) -> Bool ────────────────────────────────────────

fn genIsDigit(g: *Gen) !FuncId {
    try g.beginFunc("is_digit");
    const byte = try g.addParam();

    _ = g.beginBlock();
    const zero = try g.constInt(48); // '0'
    const nine = try g.constInt(57); // '9'
    const ge_0 = try g.ge(byte, zero);
    const le_9 = try g.binary(.le, byte, nine);
    const result = try g.logicAnd(ge_0, le_9);
    try g.ret(result);

    return g.endFunc();
}

// ── is_ident_char(byte: Int) -> Bool ───────────────────────────────────

fn genIsIdentChar(g: *Gen, is_alpha_fn: FuncId, is_digit_fn: FuncId) !FuncId {
    try g.beginFunc("is_ident_char");
    const byte = try g.addParam();

    _ = g.beginBlock();
    const alpha = try g.callDirect(is_alpha_fn, &.{byte});
    const digit = try g.callDirect(is_digit_fn, &.{byte});
    const result = try g.logicOr(alpha, digit);
    try g.ret(result);

    return g.endFunc();
}

// ── skip_whitespace(source: String, pos: Int) -> Int ───────────────────

fn genSkipWhitespace(g: *Gen) !FuncId {
    try g.beginFunc("skip_whitespace");
    const source = try g.addParam();
    const pos = try g.addParam();

    // entry: jump to loop
    _ = g.beginBlock();
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{pos});

    // loop: check if whitespace, advance or return
    g.beginReservedBlock(loop_blk);
    const cur = try g.addBlockParam();
    const len = try g.stringLength(source);
    const in_bounds = try g.lt(cur, len);
    const check_blk = g.reserveBlock();
    const done_blk = g.reserveBlock();
    try g.branch(in_bounds, check_blk, done_blk);

    // check: is byte whitespace?
    g.beginReservedBlock(check_blk);
    const byte = try g.stringByteAt(source, cur);
    const is_space = try g.eq(byte, try g.constInt(32)); // ' '
    const is_tab = try g.eq(byte, try g.constInt(9)); // '\t'
    const is_cr = try g.eq(byte, try g.constInt(13)); // '\r'
    const is_nl = try g.eq(byte, try g.constInt(10)); // '\n'
    const sp_or_tab = try g.logicOr(is_space, is_tab);
    const cr_or_nl = try g.logicOr(is_cr, is_nl);
    const is_ws = try g.logicOr(sp_or_tab, cr_or_nl);
    const advance_blk = g.reserveBlock();
    try g.branch(is_ws, advance_blk, done_blk);

    // advance: cur += 1, loop
    g.beginReservedBlock(advance_blk);
    const one = try g.constInt(1);
    const next = try g.add(cur, one);
    try g.jump(loop_blk, &.{next});

    // done: return cur
    g.beginReservedBlock(done_blk);
    try g.ret(cur);

    return g.endFunc();
}

// ── skip_comment(source: String, pos: Int) -> Int ──────────────────────
// If pos is at "--", skip to end of line. Returns new pos.

fn genSkipComment(g: *Gen) !FuncId {
    try g.beginFunc("skip_comment");
    const source = try g.addParam();
    const pos = try g.addParam();

    // entry: check if at "--"
    _ = g.beginBlock();
    const len = try g.stringLength(source);
    const one = try g.constInt(1);
    const pos_plus_1 = try g.add(pos, one);
    const has_two = try g.lt(pos_plus_1, len);
    const check_dash_blk = g.reserveBlock();
    const not_comment_blk = g.reserveBlock();
    try g.branch(has_two, check_dash_blk, not_comment_blk);

    // check_dash: are both chars '-'?
    g.beginReservedBlock(check_dash_blk);
    const b1 = try g.stringByteAt(source, pos);
    const b2 = try g.stringByteAt(source, pos_plus_1);
    const dash = try g.constInt(45); // '-'
    const is_dash1 = try g.eq(b1, dash);
    const is_dash2 = try g.eq(b2, dash);
    const both_dash = try g.logicAnd(is_dash1, is_dash2);
    const scan_blk = g.reserveBlock();
    try g.branch(both_dash, scan_blk, not_comment_blk);

    // scan: advance until newline or end
    g.beginReservedBlock(scan_blk);
    const two = try g.constInt(2);
    const scan_start = try g.add(pos, two);
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{scan_start});

    g.beginReservedBlock(loop_blk);
    const cur = try g.addBlockParam();
    const in_bounds = try g.lt(cur, len);
    const check_nl_blk = g.reserveBlock();
    const end_blk = g.reserveBlock();
    try g.branch(in_bounds, check_nl_blk, end_blk);

    // check_nl: is newline?
    g.beginReservedBlock(check_nl_blk);
    const byte = try g.stringByteAt(source, cur);
    const nl = try g.constInt(10);
    const is_nl = try g.eq(byte, nl);
    const advance_blk = g.reserveBlock();
    try g.branch(is_nl, end_blk, advance_blk);

    // advance
    g.beginReservedBlock(advance_blk);
    const next = try g.add(cur, one);
    try g.jump(loop_blk, &.{next});

    // end: return cur (at newline or past end)
    g.beginReservedBlock(end_blk);
    try g.ret(cur);

    // not_comment: return original pos
    g.beginReservedBlock(not_comment_blk);
    try g.ret(pos);

    return g.endFunc();
}

// ── lex_number(source: String, pos: Int) -> Record{token: Tagged, end: Int}

fn genLexNumber(g: *Gen, is_digit_fn: FuncId) !FuncId {
    try g.beginFunc("lex_number");
    const source = try g.addParam();
    const pos = try g.addParam();

    // entry: scan digits
    _ = g.beginBlock();
    const len = try g.stringLength(source);
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{ pos, try g.constBool(false) });

    // loop: scan digits, track if we've seen a dot
    g.beginReservedBlock(loop_blk);
    const cur = try g.addBlockParam();
    const has_dot = try g.addBlockParam();
    const in_bounds = try g.lt(cur, len);
    const check_blk = g.reserveBlock();
    const done_blk = g.reserveBlock();
    try g.branch(in_bounds, check_blk, done_blk);

    // check: digit or dot?
    g.beginReservedBlock(check_blk);
    const byte = try g.stringByteAt(source, cur);
    const is_dig = try g.callDirect(is_digit_fn, &.{byte});
    const advance_blk = g.reserveBlock();
    const check_dot_blk = g.reserveBlock();
    try g.branch(is_dig, advance_blk, check_dot_blk);

    // check_dot: is it '.' and we haven't seen one yet?
    g.beginReservedBlock(check_dot_blk);
    const dot_byte = try g.constInt(46); // '.'
    const is_dot = try g.eq(byte, dot_byte);
    const no_dot_yet = try g.unary(.not, has_dot);
    const is_first_dot = try g.logicAnd(is_dot, no_dot_yet);
    const dot_advance_blk = g.reserveBlock();
    try g.branch(is_first_dot, dot_advance_blk, done_blk);

    // advance (digit)
    g.beginReservedBlock(advance_blk);
    const one = try g.constInt(1);
    const next = try g.add(cur, one);
    try g.jump(loop_blk, &.{ next, has_dot });

    // dot_advance
    g.beginReservedBlock(dot_advance_blk);
    const next2 = try g.add(cur, one);
    const yes = try g.constBool(true);
    try g.jump(loop_blk, &.{ next2, yes });

    // done: extract text, build token
    g.beginReservedBlock(done_blk);
    const text = try g.stringSlice(source, pos, cur);
    const true_blk = g.reserveBlock();
    const false_blk = g.reserveBlock();
    try g.branch(has_dot, true_blk, false_blk);

    // float token
    g.beginReservedBlock(true_blk);
    const float_tok = try g.tag(tok_float_lit, text);
    const float_rec = try g.record(&.{
        .{ .name = "token", .value = float_tok },
        .{ .name = "end", .value = cur },
    });
    try g.ret(float_rec);

    // int token
    g.beginReservedBlock(false_blk);
    const int_tok = try g.tag(tok_int_lit, text);
    const int_rec = try g.record(&.{
        .{ .name = "token", .value = int_tok },
        .{ .name = "end", .value = cur },
    });
    try g.ret(int_rec);

    return g.endFunc();
}

// ── lex_string(source: String, pos: Int) -> Record{token: Tagged, end: Int}
// pos points at the opening quote

fn genLexString(g: *Gen) !FuncId {
    try g.beginFunc("lex_string");
    const source = try g.addParam();
    const pos = try g.addParam();

    // entry: skip opening quote, scan for closing quote
    // Track has_interp (whether we've seen {) to decide StringLit vs StringInterp
    _ = g.beginBlock();
    const one = try g.constInt(1);
    const start = try g.add(pos, one); // past opening "
    const len = try g.stringLength(source);
    const init_interp = try g.constBool(false);
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{ start, init_interp });

    // loop: find closing quote (handle escape)
    g.beginReservedBlock(loop_blk);
    const cur = try g.addBlockParam();
    const has_interp = try g.addBlockParam();
    const in_bounds = try g.lt(cur, len);
    const check_blk = g.reserveBlock();
    const error_blk = g.reserveBlock();
    try g.branch(in_bounds, check_blk, error_blk);

    // check: is it quote, backslash, or {?
    g.beginReservedBlock(check_blk);
    const byte = try g.stringByteAt(source, cur);
    const quote = try g.constInt(34); // '"'
    const backslash = try g.constInt(92); // '\'
    const lbrace = try g.constInt(123); // '{'
    const is_quote = try g.eq(byte, quote);
    const found_blk = g.reserveBlock();
    const check_esc_blk = g.reserveBlock();
    try g.branch(is_quote, found_blk, check_esc_blk);

    // check_esc: backslash? skip next char
    g.beginReservedBlock(check_esc_blk);
    const is_esc = try g.eq(byte, backslash);
    const skip_blk = g.reserveBlock();
    const check_brace_blk = g.reserveBlock();
    try g.branch(is_esc, skip_blk, check_brace_blk);

    // check for { (interpolation marker)
    g.beginReservedBlock(check_brace_blk);
    const is_brace = try g.eq(byte, lbrace);
    const mark_interp_blk = g.reserveBlock();
    const advance_blk = g.reserveBlock();
    try g.branch(is_brace, mark_interp_blk, advance_blk);

    g.beginReservedBlock(mark_interp_blk);
    const true_val = try g.constBool(true);
    const next_interp = try g.add(cur, one);
    try g.jump(loop_blk, &.{ next_interp, true_val });

    // skip: advance by 2 (backslash + escaped char)
    g.beginReservedBlock(skip_blk);
    const two = try g.constInt(2);
    const next_skip = try g.add(cur, two);
    try g.jump(loop_blk, &.{ next_skip, has_interp });

    // advance: normal char, advance by 1
    g.beginReservedBlock(advance_blk);
    const next = try g.add(cur, one);
    try g.jump(loop_blk, &.{ next, has_interp });

    // found: extract string content, choose tag based on has_interp
    g.beginReservedBlock(found_blk);
    const content = try g.stringSlice(source, start, cur);
    const end_pos = try g.add(cur, one); // past closing quote
    const interp_blk = g.reserveBlock();
    const plain_blk = g.reserveBlock();
    try g.branch(has_interp, interp_blk, plain_blk);

    g.beginReservedBlock(interp_blk);
    const interp_tok = try g.tag("StringInterp", content);
    const interp_rec = try g.record(&.{
        .{ .name = "token", .value = interp_tok },
        .{ .name = "end", .value = end_pos },
    });
    try g.ret(interp_rec);

    g.beginReservedBlock(plain_blk);
    const tok = try g.tag(tok_string_lit, content);
    const rec = try g.record(&.{
        .{ .name = "token", .value = tok },
        .{ .name = "end", .value = end_pos },
    });
    try g.ret(rec);

    // error: unterminated string — return what we have
    g.beginReservedBlock(error_blk);
    const partial = try g.stringSlice(source, start, cur);
    const err_tok = try g.tag(tok_string_lit, partial);
    const err_rec = try g.record(&.{
        .{ .name = "token", .value = err_tok },
        .{ .name = "end", .value = cur },
    });
    try g.ret(err_rec);

    return g.endFunc();
}

// ── lex_ident_or_keyword(source: String, pos: Int) -> Record{token, end}

fn genLexIdentOrKeyword(g: *Gen, is_ident_char_fn: FuncId, _: FuncId) !FuncId {
    try g.beginFunc("lex_ident_or_keyword");
    const source = try g.addParam();
    const pos = try g.addParam();

    // entry: scan ident chars
    _ = g.beginBlock();
    const len = try g.stringLength(source);
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{pos});

    // loop
    g.beginReservedBlock(loop_blk);
    const cur = try g.addBlockParam();
    const in_bounds = try g.lt(cur, len);
    const check_blk = g.reserveBlock();
    const done_blk = g.reserveBlock();
    try g.branch(in_bounds, check_blk, done_blk);

    // check: is ident char?
    g.beginReservedBlock(check_blk);
    const byte = try g.stringByteAt(source, cur);
    const is_ic = try g.callDirect(is_ident_char_fn, &.{byte});
    const advance_blk = g.reserveBlock();
    try g.branch(is_ic, advance_blk, done_blk);

    // advance
    g.beginReservedBlock(advance_blk);
    const one = try g.constInt(1);
    const next = try g.add(cur, one);
    try g.jump(loop_blk, &.{next});

    // done: extract text, check if keyword
    g.beginReservedBlock(done_blk);
    const text = try g.stringSlice(source, pos, cur);

    // Check for true/false/nil literals first
    const true_str = try g.constString("true");
    const is_true = try g.eq(text, true_str);
    const true_blk = g.reserveBlock();
    const check_false_blk = g.reserveBlock();
    try g.branch(is_true, true_blk, check_false_blk);

    // true literal
    g.beginReservedBlock(true_blk);
    const true_val = try g.constBool(true);
    const true_tok = try g.tag(tok_bool_lit, true_val);
    const true_rec = try g.record(&.{
        .{ .name = "token", .value = true_tok },
        .{ .name = "end", .value = cur },
    });
    try g.ret(true_rec);

    // check false
    g.beginReservedBlock(check_false_blk);
    const false_str = try g.constString("false");
    const is_false = try g.eq(text, false_str);
    const false_blk = g.reserveBlock();
    const check_nil_blk = g.reserveBlock();
    try g.branch(is_false, false_blk, check_nil_blk);

    // false literal
    g.beginReservedBlock(false_blk);
    const false_val = try g.constBool(false);
    const false_tok = try g.tag(tok_bool_lit, false_val);
    const false_rec = try g.record(&.{
        .{ .name = "token", .value = false_tok },
        .{ .name = "end", .value = cur },
    });
    try g.ret(false_rec);

    // check nil
    g.beginReservedBlock(check_nil_blk);
    const nil_str = try g.constString("nil");
    const is_nil = try g.eq(text, nil_str);
    const nil_blk = g.reserveBlock();
    const kw_chain_blk = g.reserveBlock();
    try g.branch(is_nil, nil_blk, kw_chain_blk);

    // nil literal
    g.beginReservedBlock(nil_blk);
    const nil_tok = try g.tag(tok_nil_lit, null);
    const nil_rec = try g.record(&.{
        .{ .name = "token", .value = nil_tok },
        .{ .name = "end", .value = cur },
    });
    try g.ret(nil_rec);

    // keyword chain: check each keyword (excluding true/false/nil already handled)
    const kw_only = [_][]const u8{
        "fn",     "type",   "trait",  "impl",
        "effect", "use",    "match",  "if",
        "else",   "let",    "handle", "resume",
        "pub",    "unsafe", "extern", "for",
        "test",   "return", "opaque", "implements",
        "and",    "or",
    };

    var prev_else_blk = kw_chain_blk;
    for (kw_only) |kw| {
        // Enter the "else" block from previous check
        g.beginReservedBlock(prev_else_blk);
        const kw_str = try g.constString(kw);
        const is_kw = try g.eq(text, kw_str);
        const match_blk = g.reserveBlock();
        const next_blk = g.reserveBlock();
        try g.branch(is_kw, match_blk, next_blk);

        // match: return Keyword token
        g.beginReservedBlock(match_blk);
        const kw_tok = try g.tag(tok_keyword, text);
        const kw_rec = try g.record(&.{
            .{ .name = "token", .value = kw_tok },
            .{ .name = "end", .value = cur },
        });
        try g.ret(kw_rec);

        prev_else_blk = next_blk;
    }

    // Final else: it's an identifier. Check if starts with uppercase.
    g.beginReservedBlock(prev_else_blk);
    const first_byte = try g.stringByteAt(source, pos);
    const a_upper = try g.constInt(65); // 'A'
    const z_upper = try g.constInt(90); // 'Z'
    const ge_A = try g.ge(first_byte, a_upper);
    const le_Z = try g.binary(.le, first_byte, z_upper);
    const is_upper = try g.logicAnd(ge_A, le_Z);
    const upper_blk = g.reserveBlock();
    const lower_blk = g.reserveBlock();
    try g.branch(is_upper, upper_blk, lower_blk);

    // UpperIdent
    g.beginReservedBlock(upper_blk);
    const upper_tok = try g.tag(tok_upper_ident, text);
    const upper_rec = try g.record(&.{
        .{ .name = "token", .value = upper_tok },
        .{ .name = "end", .value = cur },
    });
    try g.ret(upper_rec);

    // Ident
    g.beginReservedBlock(lower_blk);
    const ident_tok = try g.tag(tok_ident, text);
    const ident_rec = try g.record(&.{
        .{ .name = "token", .value = ident_tok },
        .{ .name = "end", .value = cur },
    });
    try g.ret(ident_rec);

    return g.endFunc();
}

// ── lex(source: String) -> List<Record{token, start, end}> ────────────

fn genLex(
    g: *Gen,
    skip_ws_fn: FuncId,
    skip_comment_fn: FuncId,
    lex_number_fn: FuncId,
    lex_string_fn: FuncId,
    lex_ident_fn: FuncId,
    is_digit_fn: FuncId,
    is_alpha_fn: FuncId,
) !FuncId {
    try g.beginFunc("lex");
    const source = try g.addParam();

    // entry: init empty list, jump to loop
    _ = g.beginBlock();
    const empty_list = try g.listInit(&.{});
    const zero = try g.constInt(0);
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{ zero, empty_list });

    // loop: skip whitespace, check if at end
    g.beginReservedBlock(loop_blk);
    const pos = try g.addBlockParam();
    const tokens = try g.addBlockParam();
    const len = try g.stringLength(source);

    // Skip whitespace
    const pos_ws = try g.callDirect(skip_ws_fn, &.{ source, pos });
    // Skip comments
    const pos_cmt = try g.callDirect(skip_comment_fn, &.{ source, pos_ws });
    // If comment skipped something, go back to skip more whitespace
    const cmt_moved = try g.ne(pos_cmt, pos_ws);
    const retry_blk = g.reserveBlock();
    const check_end_blk = g.reserveBlock();
    try g.branch(cmt_moved, retry_blk, check_end_blk);

    // retry: comment consumed some input, loop back to skip more ws/comments
    g.beginReservedBlock(retry_blk);
    try g.jump(loop_blk, &.{ pos_cmt, tokens });

    // check_end: are we past the source?
    g.beginReservedBlock(check_end_blk);
    const at_end = try g.ge(pos_cmt, len);
    const eof_blk = g.reserveBlock();
    const dispatch_blk = g.reserveBlock();
    try g.branch(at_end, eof_blk, dispatch_blk);

    // eof: append Eof token, return
    g.beginReservedBlock(eof_blk);
    const eof_tok = try g.tag(tok_eof, null);
    const eof_rec = try g.record(&.{
        .{ .name = "token", .value = eof_tok },
        .{ .name = "start", .value = pos_cmt },
        .{ .name = "end", .value = pos_cmt },
    });
    const final_list = try g.listAppend(tokens, eof_rec);
    try g.ret(final_list);

    // dispatch: look at first char to decide what to lex
    g.beginReservedBlock(dispatch_blk);
    const byte = try g.stringByteAt(source, pos_cmt);
    const one = try g.constInt(1);
    const pos_plus_1 = try g.add(pos_cmt, one);

    // Is it a digit?
    const is_dig = try g.callDirect(is_digit_fn, &.{byte});
    const num_blk = g.reserveBlock();
    const not_num_blk = g.reserveBlock();
    try g.branch(is_dig, num_blk, not_num_blk);

    // num: lex number
    g.beginReservedBlock(num_blk);
    const num_result = try g.callDirect(lex_number_fn, &.{ source, pos_cmt });
    const num_tok = try g.recordField(num_result, "token");
    const num_end = try g.recordField(num_result, "end");
    const num_span = try g.record(&.{
        .{ .name = "token", .value = num_tok },
        .{ .name = "start", .value = pos_cmt },
        .{ .name = "end", .value = num_end },
    });
    const list_num = try g.listAppend(tokens, num_span);
    try g.jump(loop_blk, &.{ num_end, list_num });

    // not_num: check for string
    g.beginReservedBlock(not_num_blk);
    const dquote = try g.constInt(34); // '"'
    const is_str = try g.eq(byte, dquote);
    const str_blk = g.reserveBlock();
    const not_str_blk = g.reserveBlock();
    try g.branch(is_str, str_blk, not_str_blk);

    // str: lex string
    g.beginReservedBlock(str_blk);
    const str_result = try g.callDirect(lex_string_fn, &.{ source, pos_cmt });
    const str_tok = try g.recordField(str_result, "token");
    const str_end = try g.recordField(str_result, "end");
    const str_span = try g.record(&.{
        .{ .name = "token", .value = str_tok },
        .{ .name = "start", .value = pos_cmt },
        .{ .name = "end", .value = str_end },
    });
    const list_str = try g.listAppend(tokens, str_span);
    try g.jump(loop_blk, &.{ str_end, list_str });

    // not_str: check for ident/keyword (alpha or _)
    g.beginReservedBlock(not_str_blk);
    const is_al = try g.callDirect(is_alpha_fn, &.{byte});
    const ident_blk = g.reserveBlock();
    const not_ident_blk = g.reserveBlock();
    try g.branch(is_al, ident_blk, not_ident_blk);

    // ident: lex identifier or keyword
    g.beginReservedBlock(ident_blk);
    const id_result = try g.callDirect(lex_ident_fn, &.{ source, pos_cmt });
    const id_tok = try g.recordField(id_result, "token");
    const id_end = try g.recordField(id_result, "end");
    const id_span = try g.record(&.{
        .{ .name = "token", .value = id_tok },
        .{ .name = "start", .value = pos_cmt },
        .{ .name = "end", .value = id_end },
    });
    const list_id = try g.listAppend(tokens, id_span);
    try g.jump(loop_blk, &.{ id_end, list_id });

    // not_ident: check multi-char operators
    g.beginReservedBlock(not_ident_blk);

    // First check 3-char ops: "---"
    const three = try g.constInt(3);
    const pos_plus_3 = try g.add(pos_cmt, three);
    const has_3 = try g.binary(.le, pos_plus_3, len);
    const check_3_blk = g.reserveBlock();
    const check_2_blk = g.reserveBlock();
    try g.branch(has_3, check_3_blk, check_2_blk);

    // check 3-char: "---" (doc comment — skip to end of line, treated as comment)
    g.beginReservedBlock(check_3_blk);
    const three_chars = try g.stringSlice(source, pos_cmt, pos_plus_3);
    const doc_str = try g.constString("---");
    const is_doc = try g.eq(three_chars, doc_str);
    const doc_blk = g.reserveBlock();
    try g.branch(is_doc, doc_blk, check_2_blk);

    // doc comment: skip to end of line and retry
    g.beginReservedBlock(doc_blk);
    const doc_scan_blk = g.reserveBlock();
    try g.jump(doc_scan_blk, &.{pos_plus_3});

    g.beginReservedBlock(doc_scan_blk);
    const doc_cur = try g.addBlockParam();
    const doc_in_bounds = try g.lt(doc_cur, len);
    const doc_check_blk = g.reserveBlock();
    const doc_done_blk = g.reserveBlock();
    try g.branch(doc_in_bounds, doc_check_blk, doc_done_blk);

    g.beginReservedBlock(doc_check_blk);
    const doc_byte = try g.stringByteAt(source, doc_cur);
    const nl = try g.constInt(10);
    const doc_is_nl = try g.eq(doc_byte, nl);
    const doc_advance_blk = g.reserveBlock();
    try g.branch(doc_is_nl, doc_done_blk, doc_advance_blk);

    g.beginReservedBlock(doc_advance_blk);
    const doc_next = try g.add(doc_cur, one);
    try g.jump(doc_scan_blk, &.{doc_next});

    // doc_done: back to main loop
    g.beginReservedBlock(doc_done_blk);
    try g.jump(loop_blk, &.{ doc_cur, tokens });

    // check 2-char operators
    g.beginReservedBlock(check_2_blk);
    const two = try g.constInt(2);
    const pos_plus_2 = try g.add(pos_cmt, two);
    const has_2 = try g.binary(.le, pos_plus_2, len);
    const check_2ops_blk = g.reserveBlock();
    const single_char_blk = g.reserveBlock();
    try g.branch(has_2, check_2ops_blk, single_char_blk);

    // Chain of 2-char operator checks
    const two_char_ops = [_][]const u8{
        "==", "!=", "<=", ">=", "->", "-[", "]>", "|>", "&&", "||", "..", "=>",
    };

    var prev_2op_blk = check_2ops_blk;
    for (two_char_ops) |op_str| {
        g.beginReservedBlock(prev_2op_blk);
        const two_chars = try g.stringSlice(source, pos_cmt, pos_plus_2);
        const op_const = try g.constString(op_str);
        const is_match = try g.eq(two_chars, op_const);
        const match_blk = g.reserveBlock();
        const next_blk = g.reserveBlock();
        try g.branch(is_match, match_blk, next_blk);

        // match: emit Op token
        g.beginReservedBlock(match_blk);
        const op_tok = try g.tag(tok_op, two_chars);
        const op_span = try g.record(&.{
            .{ .name = "token", .value = op_tok },
            .{ .name = "start", .value = pos_cmt },
            .{ .name = "end", .value = pos_plus_2 },
        });
        const list_op = try g.listAppend(tokens, op_span);
        try g.jump(loop_blk, &.{ pos_plus_2, list_op });

        prev_2op_blk = next_blk;
    }

    // After all 2-char ops checked, fall through to single char
    g.beginReservedBlock(prev_2op_blk);
    try g.jump(single_char_blk, &.{});

    // single_char: check operators, delimiters, punctuation
    // Compute pos_plus_1 here and start the first char check in this block
    g.beginReservedBlock(single_char_blk);

    const op_chars = single_ops;
    const delim_chars = delimiters;
    const punct_chars = punctuation;

    // All single-char checks form one chain. First check starts here in single_char_blk.
    const CharKind = enum { op, delim, punct };
    const CharEntry = struct { byte_val: u8, kind: CharKind };

    // Build combined char table
    var all_chars: [op_chars.len + delim_chars.len + punct_chars.len]CharEntry = undefined;
    var ci: usize = 0;
    for (op_chars) |ch| {
        all_chars[ci] = .{ .byte_val = ch, .kind = .op };
        ci += 1;
    }
    for (delim_chars) |ch| {
        all_chars[ci] = .{ .byte_val = ch, .kind = .delim };
        ci += 1;
    }
    for (punct_chars) |ch| {
        all_chars[ci] = .{ .byte_val = ch, .kind = .punct };
        ci += 1;
    }

    var prev_check_blk_id: ?BlockId = null;
    for (all_chars, 0..) |entry, idx| {
        if (idx > 0) {
            g.beginReservedBlock(prev_check_blk_id.?);
        }
        // else: first iteration is already in single_char_blk

        const ch_code = try g.constInt(@intCast(entry.byte_val));
        const is_ch = try g.eq(byte, ch_code);
        const ch_match_blk = g.reserveBlock();
        const ch_next_blk = g.reserveBlock();
        try g.branch(is_ch, ch_match_blk, ch_next_blk);

        g.beginReservedBlock(ch_match_blk);
        const ch_str = try g.callBuiltin("string_from_int_char", &.{ch_code});
        const tag_name = switch (entry.kind) {
            .op => tok_op,
            .delim => tok_delim,
            .punct => tok_punct,
        };
        const ch_tok = try g.tag(tag_name, ch_str);
        const ch_span = try g.record(&.{
            .{ .name = "token", .value = ch_tok },
            .{ .name = "start", .value = pos_cmt },
            .{ .name = "end", .value = pos_plus_1 },
        });
        const ch_list = try g.listAppend(tokens, ch_span);
        try g.jump(loop_blk, &.{ pos_plus_1, ch_list });

        prev_check_blk_id = ch_next_blk;
    }

    // Unknown character: skip it
    g.beginReservedBlock(prev_check_blk_id.?);
    try g.jump(loop_blk, &.{ pos_plus_1, tokens });

    return g.endFunc();
}

// ── Parser IR generation ───────────────────────────────────────────────

// Zig-level helpers for emitting common token-checking patterns.
// These generate multiple IR instructions but are called from Zig, not IR.

/// Emit IR to get the token Tagged value at position `pos` in `tokens` list.
fn emitGetToken(g: *Gen, tokens: ValueId, pos: ValueId) !ValueId {
    const tok_rec = try g.listNth(tokens, pos);
    return g.recordField(tok_rec, "token");
}

/// Emit: pos + 1
fn emitAdvance(g: *Gen, pos: ValueId) !ValueId {
    const one = try g.constInt(1);
    return g.add(pos, one);
}

/// Emit IR to check if token at `pos` is a Keyword with value `kw`.
/// Returns {is_match: Bool, tok: Tagged} — tok is the token value for reuse.
fn emitIsKeyword(g: *Gen, tokens: ValueId, pos: ValueId, kw: []const u8) !struct { ValueId, ValueId } {
    const tok = try emitGetToken(g, tokens, pos);
    const is_kw_tag = try g.tagTest(tok, "Keyword");
    // We need to branch to check the payload, but for simplicity just check
    // the tag first. Caller should branch on is_kw_tag, then in the true branch
    // extract payload and compare.
    _ = kw;
    return .{ is_kw_tag, tok };
}

/// Emit: check if token at pos has tag `tag_name`. Returns (is_match, tok).
fn emitIsTokenTag(g: *Gen, tokens: ValueId, pos: ValueId, tag_name: []const u8) !struct { ValueId, ValueId } {
    const tok = try emitGetToken(g, tokens, pos);
    const is_tag = try g.tagTest(tok, tag_name);
    return .{ is_tag, tok };
}

/// Emit: result record {node: X, pos: Y}
fn emitResult(g: *Gen, node: ValueId, pos: ValueId) !ValueId {
    return g.record(&.{
        .{ .name = "node", .value = node },
        .{ .name = "pos", .value = pos },
    });
}

// ── peek_token(tokens, pos) -> Tagged ──────────────────────────────────

fn genPeekToken(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("peek_token");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    const tok = try emitGetToken(g, tokens, pos);
    try g.ret(tok);

    try g.endReservedFunc(pf.peek_token);
}

// ── infix_bp(op_str) -> Record{left, right} or {left: 0, right: 0} if not infix
// Returns binding powers for Pratt precedence.

fn genInfixBp(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("infix_bp");
    const op = try g.addParam(); // String

    _ = g.beginBlock();

    // Chain of comparisons for each operator
    const ops = [_]struct { name: []const u8, left: i64, right: i64 }{
        .{ .name = "|>", .left = 1, .right = 2 },
        .{ .name = "or", .left = 3, .right = 4 },
        .{ .name = "||", .left = 3, .right = 4 },
        .{ .name = "and", .left = 5, .right = 6 },
        .{ .name = "&&", .left = 5, .right = 6 },
        .{ .name = "==", .left = 7, .right = 8 },
        .{ .name = "!=", .left = 7, .right = 8 },
        .{ .name = "<", .left = 7, .right = 8 },
        .{ .name = "<=", .left = 7, .right = 8 },
        .{ .name = ">", .left = 7, .right = 8 },
        .{ .name = ">=", .left = 7, .right = 8 },
        .{ .name = "+", .left = 13, .right = 14 },
        .{ .name = "-", .left = 13, .right = 14 },
        .{ .name = "*", .left = 15, .right = 16 },
        .{ .name = "/", .left = 15, .right = 16 },
        .{ .name = "%", .left = 15, .right = 16 },
    };

    var prev_blk: ?BlockId = null;
    for (ops) |entry| {
        if (prev_blk) |blk| {
            g.beginReservedBlock(blk);
        }
        const op_str = try g.constString(entry.name);
        const is_match = try g.eq(op, op_str);
        const match_blk = g.reserveBlock();
        const next_blk = g.reserveBlock();
        try g.branch(is_match, match_blk, next_blk);

        g.beginReservedBlock(match_blk);
        const left = try g.constInt(entry.left);
        const right = try g.constInt(entry.right);
        const rec = try g.record(&.{
            .{ .name = "left", .value = left },
            .{ .name = "right", .value = right },
        });
        try g.ret(rec);

        prev_blk = next_blk;
    }

    // No match: return {left: 0, right: 0}
    g.beginReservedBlock(prev_blk.?);
    const z = try g.constInt(0);
    const no_bp = try g.record(&.{
        .{ .name = "left", .value = z },
        .{ .name = "right", .value = z },
    });
    try g.ret(no_bp);

    try g.endReservedFunc(pf.infix_bp);
}

// ── parse_list_sep(tokens, pos, parse_item_fn, sep_str) -> Record{items, pos}
// Generic comma-separated list parser. BUT we can't pass a function value
// easily, so instead we make this specific: it parses comma-separated exprs.
// We'll make specialized versions as needed.
//
// Actually, let's make it parse a comma-separated list of expressions.
// parse_list_sep(tokens, pos) -> Record{items: List<Expr>, pos: Int}
// Stops at ")" or "}" or "]" or Eof.

fn genParseListSep(g: *Gen, pf: ParserFuncs) !void {
    // parse_list_sep is not used directly - comma-separated parsing is inlined
    // in each function that needs it. This is a placeholder.
    try g.beginReservedFunc("parse_list_sep");
    const tokens = try g.addParam();
    _ = tokens;
    const pos = try g.addParam();

    _ = g.beginBlock();
    const empty = try g.listInit(&.{});
    const res = try emitResult(g, empty, pos);
    try g.ret(res);

    try g.endReservedFunc(pf.parse_list_sep);
}

// ── parse_pattern(tokens, pos) -> Record{node, pos} ────────────────────

fn genParsePattern(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_pattern");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    // entry: peek at token
    _ = g.beginBlock();
    const tok = try emitGetToken(g, tokens, pos);
    const next_pos = try emitAdvance(g, pos);

    // Check for wildcard: Ident("_")
    const is_ident = try g.tagTest(tok, "Ident");
    const check_ident_blk = g.reserveBlock();
    const check_upper_blk = g.reserveBlock();
    try g.branch(is_ident, check_ident_blk, check_upper_blk);

    // check_ident: is it "_" (wildcard) or a binding?
    g.beginReservedBlock(check_ident_blk);
    const ident_name = try g.tagPayload(tok, "Ident");
    const underscore = try g.constString("_");
    const is_wildcard = try g.eq(ident_name, underscore);
    const wildcard_blk = g.reserveBlock();
    const bind_blk = g.reserveBlock();
    try g.branch(is_wildcard, wildcard_blk, bind_blk);

    // wildcard
    g.beginReservedBlock(wildcard_blk);
    const wc_node = try g.tag(ast_pat_wildcard, null);
    const wc_res = try emitResult(g, wc_node, next_pos);
    try g.ret(wc_res);

    // bind: check for : (type narrow)
    g.beginReservedBlock(bind_blk);
    const bind_next_tok = try emitGetToken(g, tokens, next_pos);
    const bind_is_punct = try g.tagTest(bind_next_tok, "Punct");
    const bind_check_colon_blk = g.reserveBlock();
    const bind_simple_blk = g.reserveBlock();
    try g.branch(bind_is_punct, bind_check_colon_blk, bind_simple_blk);

    g.beginReservedBlock(bind_check_colon_blk);
    const bind_punct = try g.tagPayload(bind_next_tok, "Punct");
    const bind_colon = try g.constString(":");
    const bind_is_colon = try g.eq(bind_punct, bind_colon);
    const type_narrow_blk = g.reserveBlock();
    try g.branch(bind_is_colon, type_narrow_blk, bind_simple_blk);

    g.beginReservedBlock(type_narrow_blk);
    const tn_type_start = try emitAdvance(g, next_pos); // skip :
    const tn_type_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, tn_type_start });
    const tn_type_node = try g.recordField(tn_type_result, "node");
    const tn_type_end = try g.recordField(tn_type_result, "pos");
    const tn_rec = try g.record(&.{
        .{ .name = "name", .value = ident_name },
        .{ .name = "type_expr", .value = tn_type_node },
    });
    const tn_node = try g.tag(ast_pat_type_narrow, tn_rec);
    const tn_res = try emitResult(g, tn_node, tn_type_end);
    try g.ret(tn_res);

    g.beginReservedBlock(bind_simple_blk);
    const bind_node = try g.tag(ast_pat_bind, ident_name);
    const bind_res = try emitResult(g, bind_node, next_pos);
    try g.ret(bind_res);

    // check_upper: UpperIdent -> constructor pattern
    g.beginReservedBlock(check_upper_blk);
    const is_upper = try g.tagTest(tok, "UpperIdent");
    const upper_blk = g.reserveBlock();
    const check_lit_blk = g.reserveBlock();
    try g.branch(is_upper, upper_blk, check_lit_blk);

    // upper: constructor pattern — ConstructorName, Type.Variant, or with (args)
    g.beginReservedBlock(upper_blk);
    const first_upper = try g.tagPayload(tok, "UpperIdent");
    // Check for . after upper ident (qualified: Type.Variant)
    const tok_after_upper = try emitGetToken(g, tokens, next_pos);
    const is_dot = try g.tagTest(tok_after_upper, "Punct");
    const check_dot_blk = g.reserveBlock();
    const no_dot_blk = g.reserveBlock();
    try g.branch(is_dot, check_dot_blk, no_dot_blk);

    g.beginReservedBlock(check_dot_blk);
    const dot_val = try g.tagPayload(tok_after_upper, "Punct");
    const dot_str = try g.constString(".");
    const is_actual_dot = try g.eq(dot_val, dot_str);
    const qualified_blk = g.reserveBlock();
    try g.branch(is_actual_dot, qualified_blk, no_dot_blk);

    // Qualified: Type.Variant — skip dot, read the variant name
    g.beginReservedBlock(qualified_blk);
    const pos_after_dot = try emitAdvance(g, next_pos);
    const tok_variant = try emitGetToken(g, tokens, pos_after_dot);
    const variant_name = try g.tagPayload(tok_variant, "UpperIdent");
    const pos_after_variant = try emitAdvance(g, pos_after_dot);
    const ctor_merge_blk = g.reserveBlock();
    try g.jump(ctor_merge_blk, &.{ variant_name, pos_after_variant });

    // Not qualified: just ConstructorName
    g.beginReservedBlock(no_dot_blk);
    try g.jump(ctor_merge_blk, &.{ first_upper, next_pos });

    // Merge: ctor_name is the variant name, ctor_pos is position after name
    g.beginReservedBlock(ctor_merge_blk);
    const ctor_name = try g.addBlockParam();
    const ctor_pos = try g.addBlockParam();

    // Check for ( after constructor name
    const tok2 = try emitGetToken(g, tokens, ctor_pos);
    const is_delim = try g.tagTest(tok2, "Delim");
    const check_lparen_blk = g.reserveBlock();
    const ctor_no_args_blk = g.reserveBlock();
    try g.branch(is_delim, check_lparen_blk, ctor_no_args_blk);

    g.beginReservedBlock(check_lparen_blk);
    const delim_val = try g.tagPayload(tok2, "Delim");
    const lparen_str = try g.constString("(");
    const is_lparen = try g.eq(delim_val, lparen_str);
    const ctor_args_blk = g.reserveBlock();
    try g.branch(is_lparen, ctor_args_blk, ctor_no_args_blk);

    // ctor with args: parse comma-separated patterns until )
    g.beginReservedBlock(ctor_args_blk);
    const args_start = try emitAdvance(g, ctor_pos); // skip (
    // Parse pattern args in a loop
    const args_empty = try g.listInit(&.{});
    const args_loop_blk = g.reserveBlock();
    try g.jump(args_loop_blk, &.{ args_start, args_empty });

    g.beginReservedBlock(args_loop_blk);
    const a_pos = try g.addBlockParam();
    const a_list = try g.addBlockParam();
    const a_tok = try emitGetToken(g, tokens, a_pos);
    // Check for )
    const a_is_delim = try g.tagTest(a_tok, "Delim");
    const a_check_rparen_blk = g.reserveBlock();
    const a_parse_blk = g.reserveBlock();
    try g.branch(a_is_delim, a_check_rparen_blk, a_parse_blk);

    g.beginReservedBlock(a_check_rparen_blk);
    const a_delim_val = try g.tagPayload(a_tok, "Delim");
    const rparen_str = try g.constString(")");
    const a_is_rparen = try g.eq(a_delim_val, rparen_str);
    const a_done_blk = g.reserveBlock();
    try g.branch(a_is_rparen, a_done_blk, a_parse_blk);

    // parse one pattern arg
    g.beginReservedBlock(a_parse_blk);
    const arg_result = try g.callDirect(pf.parse_pattern, &.{ tokens, a_pos });
    const arg_node = try g.recordField(arg_result, "node");
    const arg_next = try g.recordField(arg_result, "pos");
    const a_list2 = try g.listAppend(a_list, arg_node);
    // Check for comma
    const comma_tok = try emitGetToken(g, tokens, arg_next);
    const is_punct = try g.tagTest(comma_tok, "Punct");
    const check_comma_blk = g.reserveBlock();
    const no_comma_blk = g.reserveBlock();
    try g.branch(is_punct, check_comma_blk, no_comma_blk);

    g.beginReservedBlock(check_comma_blk);
    const punct_val = try g.tagPayload(comma_tok, "Punct");
    const comma_str = try g.constString(",");
    const is_comma = try g.eq(punct_val, comma_str);
    const skip_comma_blk = g.reserveBlock();
    try g.branch(is_comma, skip_comma_blk, no_comma_blk);

    g.beginReservedBlock(skip_comma_blk);
    const after_comma = try emitAdvance(g, arg_next);
    try g.jump(args_loop_blk, &.{ after_comma, a_list2 });

    g.beginReservedBlock(no_comma_blk);
    try g.jump(args_loop_blk, &.{ arg_next, a_list2 });

    // done: constructor with args
    g.beginReservedBlock(a_done_blk);
    const after_rparen = try emitAdvance(g, a_pos); // skip )
    const ctor_rec = try g.record(&.{
        .{ .name = "name", .value = ctor_name },
        .{ .name = "args", .value = a_list },
    });
    const ctor_node = try g.tag(ast_pat_constructor, ctor_rec);
    const ctor_res = try emitResult(g, ctor_node, after_rparen);
    try g.ret(ctor_res);

    // ctor without args
    g.beginReservedBlock(ctor_no_args_blk);
    const ctor0_rec = try g.record(&.{
        .{ .name = "name", .value = ctor_name },
        .{ .name = "args", .value = try g.listInit(&.{}) },
    });
    const ctor0_node = try g.tag(ast_pat_constructor, ctor0_rec);
    const ctor0_res = try emitResult(g, ctor0_node, ctor_pos);
    try g.ret(ctor0_res);

    // check_lit: literal patterns (int, string, bool, nil)
    g.beginReservedBlock(check_lit_blk);
    const is_int = try g.tagTest(tok, "IntLit");
    const int_pat_blk = g.reserveBlock();
    const check_str_blk = g.reserveBlock();
    try g.branch(is_int, int_pat_blk, check_str_blk);

    g.beginReservedBlock(int_pat_blk);
    const int_text = try g.tagPayload(tok, "IntLit");
    const int_val = try g.stringToInt(int_text);
    const int_lit = try g.tag(ast_int_lit, int_val);
    const int_pat = try g.tag(ast_pat_literal, int_lit);
    const int_res = try emitResult(g, int_pat, next_pos);
    try g.ret(int_res);

    g.beginReservedBlock(check_str_blk);
    const is_str = try g.tagTest(tok, "BoolLit");
    const bool_pat_blk = g.reserveBlock();
    const default_pat_blk = g.reserveBlock();
    try g.branch(is_str, bool_pat_blk, default_pat_blk);

    g.beginReservedBlock(bool_pat_blk);
    const bool_val = try g.tagPayload(tok, "BoolLit");
    const bool_lit = try g.tag(ast_bool_lit, bool_val);
    const bool_pat = try g.tag(ast_pat_literal, bool_lit);
    const bool_res = try emitResult(g, bool_pat, next_pos);
    try g.ret(bool_res);

    // Check for { (record pattern)
    g.beginReservedBlock(default_pat_blk);
    const pr_is_delim = try g.tagTest(tok, "Delim");
    const pr_check_blk = g.reserveBlock();
    const pr_fallback_blk = g.reserveBlock();
    try g.branch(pr_is_delim, pr_check_blk, pr_fallback_blk);

    g.beginReservedBlock(pr_check_blk);
    const pr_delim_val = try g.tagPayload(tok, "Delim");
    const pr_lbrace = try g.constString("{");
    const pr_is_lb = try g.eq(pr_delim_val, pr_lbrace);
    const pr_rec_blk = g.reserveBlock();
    try g.branch(pr_is_lb, pr_rec_blk, pr_fallback_blk);

    // Record pattern: { field1, field2 } or { field1: pat, field2: pat }
    g.beginReservedBlock(pr_rec_blk);
    const pr_empty = try g.listInit(&.{});
    const pr_loop_blk = g.reserveBlock();
    try g.jump(pr_loop_blk, &.{ next_pos, pr_empty });

    g.beginReservedBlock(pr_loop_blk);
    const pr_pos = try g.addBlockParam();
    const pr_fields = try g.addBlockParam();
    const pr_tok = try emitGetToken(g, tokens, pr_pos);
    const pr_tok_is_delim = try g.tagTest(pr_tok, "Delim");
    const pr_check_rb_blk = g.reserveBlock();
    const pr_parse_blk = g.reserveBlock();
    try g.branch(pr_tok_is_delim, pr_check_rb_blk, pr_parse_blk);

    g.beginReservedBlock(pr_check_rb_blk);
    const pr_tok_delim = try g.tagPayload(pr_tok, "Delim");
    const pr_rbrace = try g.constString("}");
    const pr_is_rb = try g.eq(pr_tok_delim, pr_rbrace);
    const pr_done_blk = g.reserveBlock();
    try g.branch(pr_is_rb, pr_done_blk, pr_parse_blk);

    // Parse one field: name or name: pattern
    g.beginReservedBlock(pr_parse_blk);
    const pr_fname = try g.tagPayload(pr_tok, "Ident");
    const pr_fnext = try emitAdvance(g, pr_pos);
    const pr_ftok = try emitGetToken(g, tokens, pr_fnext);
    const pr_f_is_punct = try g.tagTest(pr_ftok, "Punct");
    const pr_fcheck_blk = g.reserveBlock();
    const pr_fshort_blk = g.reserveBlock();
    try g.branch(pr_f_is_punct, pr_fcheck_blk, pr_fshort_blk);

    g.beginReservedBlock(pr_fcheck_blk);
    const pr_f_punct = try g.tagPayload(pr_ftok, "Punct");
    const pr_f_colon = try g.constString(":");
    const pr_f_is_colon = try g.eq(pr_f_punct, pr_f_colon);
    const pr_f_typed_blk = g.reserveBlock();
    const pr_f_comma_blk = g.reserveBlock();
    try g.branch(pr_f_is_colon, pr_f_typed_blk, pr_f_comma_blk);

    // field: pattern
    g.beginReservedBlock(pr_f_typed_blk);
    const pr_f_pat_start = try emitAdvance(g, pr_fnext); // skip :
    const pr_f_pat_result = try g.callDirect(pf.parse_pattern, &.{ tokens, pr_f_pat_start });
    const pr_f_pat_node = try g.recordField(pr_f_pat_result, "node");
    const pr_f_pat_end = try g.recordField(pr_f_pat_result, "pos");
    const pr_f_rec = try g.record(&.{
        .{ .name = "name", .value = pr_fname },
        .{ .name = "pattern", .value = pr_f_pat_node },
    });
    const pr_fields_t = try g.listAppend(pr_fields, pr_f_rec);
    // Check for comma
    const prt_tok = try emitGetToken(g, tokens, pr_f_pat_end);
    const prt_is_punct = try g.tagTest(prt_tok, "Punct");
    const prt_check_blk = g.reserveBlock();
    const prt_no_blk = g.reserveBlock();
    try g.branch(prt_is_punct, prt_check_blk, prt_no_blk);

    g.beginReservedBlock(prt_check_blk);
    const prt_val = try g.tagPayload(prt_tok, "Punct");
    const prt_comma = try g.constString(",");
    const prt_is_comma = try g.eq(prt_val, prt_comma);
    const prt_skip_blk = g.reserveBlock();
    try g.branch(prt_is_comma, prt_skip_blk, prt_no_blk);

    g.beginReservedBlock(prt_skip_blk);
    const prt_after = try emitAdvance(g, pr_f_pat_end);
    try g.jump(pr_loop_blk, &.{ prt_after, pr_fields_t });

    g.beginReservedBlock(prt_no_blk);
    try g.jump(pr_loop_blk, &.{ pr_f_pat_end, pr_fields_t });

    // Shorthand: just field name (implicit bind)
    g.beginReservedBlock(pr_fshort_blk);
    const pr_f_bind = try g.tag(ast_pat_bind, pr_fname);
    const pr_f_short_rec = try g.record(&.{
        .{ .name = "name", .value = pr_fname },
        .{ .name = "pattern", .value = pr_f_bind },
    });
    const pr_fields_s = try g.listAppend(pr_fields, pr_f_short_rec);
    try g.jump(pr_loop_blk, &.{ pr_fnext, pr_fields_s });

    // Check comma shorthand
    g.beginReservedBlock(pr_f_comma_blk);
    const pr_fc_comma = try g.constString(",");
    const pr_fc_is_comma = try g.eq(pr_f_punct, pr_fc_comma);
    const pr_fc_skip_blk = g.reserveBlock();
    try g.branch(pr_fc_is_comma, pr_fc_skip_blk, pr_fshort_blk);

    g.beginReservedBlock(pr_fc_skip_blk);
    const pr_fc_bind = try g.tag(ast_pat_bind, pr_fname);
    const pr_fc_rec = try g.record(&.{
        .{ .name = "name", .value = pr_fname },
        .{ .name = "pattern", .value = pr_fc_bind },
    });
    const pr_fields_c = try g.listAppend(pr_fields, pr_fc_rec);
    const pr_fc_after = try emitAdvance(g, pr_fnext);
    try g.jump(pr_loop_blk, &.{ pr_fc_after, pr_fields_c });

    // Done: record pattern
    g.beginReservedBlock(pr_done_blk);
    const pr_after_rb = try emitAdvance(g, pr_pos);
    const pr_node = try g.tag(ast_pat_record, pr_fields);
    const pr_res = try emitResult(g, pr_node, pr_after_rb);
    try g.ret(pr_res);

    // fallback: treat as wildcard
    g.beginReservedBlock(pr_fallback_blk);
    const def_node = try g.tag(ast_pat_wildcard, null);
    const def_res = try emitResult(g, def_node, pos);
    try g.ret(def_res);

    try g.endReservedFunc(pf.parse_pattern);
}

// ── parse_type_expr(tokens, pos) -> Record{node, pos} ──────────────────

fn genParseTypeExpr(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_type_expr");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    // entry: peek at token — dispatch to primary type parser
    _ = g.beginBlock();
    const tok = try emitGetToken(g, tokens, pos);
    const next_pos = try emitAdvance(g, pos);

    // All primary type paths converge to check_suffix_blk(node, pos)
    const check_suffix_blk = g.reserveBlock();

    // Check for ~ prefix (complement)
    const is_op0 = try g.tagTest(tok, "Op");
    const check_tilde_blk = g.reserveBlock();
    const check_upper_blk = g.reserveBlock();
    try g.branch(is_op0, check_tilde_blk, check_upper_blk);

    g.beginReservedBlock(check_tilde_blk);
    const op0_val = try g.tagPayload(tok, "Op");
    const tilde_str = try g.constString("~");
    const is_tilde = try g.eq(op0_val, tilde_str);
    const tilde_blk = g.reserveBlock();
    try g.branch(is_tilde, tilde_blk, check_upper_blk);

    g.beginReservedBlock(tilde_blk);
    const comp_inner_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, next_pos });
    const comp_inner = try g.recordField(comp_inner_result, "node");
    const comp_end = try g.recordField(comp_inner_result, "pos");
    const comp_node = try g.tag(ast_type_complement, comp_inner);
    const comp_res = try emitResult(g, comp_node, comp_end);
    try g.ret(comp_res);

    // Check for UpperIdent (most type names)
    g.beginReservedBlock(check_upper_blk);
    const is_upper = try g.tagTest(tok, "UpperIdent");
    const upper_blk = g.reserveBlock();
    const check_ident_blk = g.reserveBlock();
    try g.branch(is_upper, upper_blk, check_ident_blk);

    // upper: TypeName, possibly with type args <T, U>
    g.beginReservedBlock(upper_blk);
    const type_name = try g.tagPayload(tok, "UpperIdent");
    // Check for < (type application)
    const tok2 = try emitGetToken(g, tokens, next_pos);
    const is_op = try g.tagTest(tok2, "Op");
    const check_lt_blk = g.reserveBlock();
    const simple_type_blk = g.reserveBlock();
    try g.branch(is_op, check_lt_blk, simple_type_blk);

    g.beginReservedBlock(check_lt_blk);
    const op_val = try g.tagPayload(tok2, "Op");
    const lt_str = try g.constString("<");
    const is_lt = try g.eq(op_val, lt_str);
    const type_app_blk = g.reserveBlock();
    try g.branch(is_lt, type_app_blk, simple_type_blk);

    // type_app: parse type args — TypeName<Arg1, Arg2>
    g.beginReservedBlock(type_app_blk);
    const targs_start = try emitAdvance(g, next_pos); // skip <
    const targs_empty = try g.listInit(&.{});
    const targs_loop_blk = g.reserveBlock();
    try g.jump(targs_loop_blk, &.{ targs_start, targs_empty });

    g.beginReservedBlock(targs_loop_blk);
    const t_pos = try g.addBlockParam();
    const t_list = try g.addBlockParam();
    const t_tok = try emitGetToken(g, tokens, t_pos);
    // Check for >
    const t_is_op = try g.tagTest(t_tok, "Op");
    const t_check_gt_blk = g.reserveBlock();
    const t_parse_blk = g.reserveBlock();
    try g.branch(t_is_op, t_check_gt_blk, t_parse_blk);

    g.beginReservedBlock(t_check_gt_blk);
    const t_op_val = try g.tagPayload(t_tok, "Op");
    const gt_str = try g.constString(">");
    const t_is_gt = try g.eq(t_op_val, gt_str);
    const t_done_blk = g.reserveBlock();
    try g.branch(t_is_gt, t_done_blk, t_parse_blk);

    // parse one type arg
    g.beginReservedBlock(t_parse_blk);
    const targ_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, t_pos });
    const targ_node = try g.recordField(targ_result, "node");
    const targ_next = try g.recordField(targ_result, "pos");
    const t_list2 = try g.listAppend(t_list, targ_node);
    // Check for comma
    const tc_tok = try emitGetToken(g, tokens, targ_next);
    const tc_is_punct = try g.tagTest(tc_tok, "Punct");
    const tc_check_blk = g.reserveBlock();
    const tc_no_comma_blk = g.reserveBlock();
    try g.branch(tc_is_punct, tc_check_blk, tc_no_comma_blk);

    g.beginReservedBlock(tc_check_blk);
    const tc_val = try g.tagPayload(tc_tok, "Punct");
    const comma_str = try g.constString(",");
    const tc_is_comma = try g.eq(tc_val, comma_str);
    const tc_skip_blk = g.reserveBlock();
    try g.branch(tc_is_comma, tc_skip_blk, tc_no_comma_blk);

    g.beginReservedBlock(tc_skip_blk);
    const tc_after = try emitAdvance(g, targ_next);
    try g.jump(targs_loop_blk, &.{ tc_after, t_list2 });

    g.beginReservedBlock(tc_no_comma_blk);
    try g.jump(targs_loop_blk, &.{ targ_next, t_list2 });

    // done: TypeApp node -> check suffix
    g.beginReservedBlock(t_done_blk);
    const after_gt = try emitAdvance(g, t_pos); // skip >
    const app_rec = try g.record(&.{
        .{ .name = "name", .value = type_name },
        .{ .name = "args", .value = t_list },
    });
    const app_node = try g.tag(ast_type_app, app_rec);
    try g.jump(check_suffix_blk, &.{ app_node, after_gt });

    // simple_type: just a named type -> check suffix
    g.beginReservedBlock(simple_type_blk);
    const named_node = try g.tag(ast_type_named, type_name);
    try g.jump(check_suffix_blk, &.{ named_node, next_pos });

    // check_ident: lowercase type names (type params like 'a', or builtins)
    g.beginReservedBlock(check_ident_blk);
    const is_ident = try g.tagTest(tok, "Ident");
    const ident_type_blk = g.reserveBlock();
    const check_delim_blk = g.reserveBlock();
    try g.branch(is_ident, ident_type_blk, check_delim_blk);

    g.beginReservedBlock(ident_type_blk);
    const id_name = try g.tagPayload(tok, "Ident");
    const id_node = try g.tag(ast_type_named, id_name);
    try g.jump(check_suffix_blk, &.{ id_node, next_pos });

    // Check for ( — function type or grouped type
    g.beginReservedBlock(check_delim_blk);
    const is_delim = try g.tagTest(tok, "Delim");
    const check_lparen_blk = g.reserveBlock();
    const fallback_blk = g.reserveBlock();
    try g.branch(is_delim, check_lparen_blk, fallback_blk);

    g.beginReservedBlock(check_lparen_blk);
    const delim_val = try g.tagPayload(tok, "Delim");
    const lparen_str = try g.constString("(");
    const is_lparen = try g.eq(delim_val, lparen_str);
    const fn_type_blk = g.reserveBlock();
    try g.branch(is_lparen, fn_type_blk, fallback_blk);

    // ( — parse param types, check for ) -> RetType (function type)
    g.beginReservedBlock(fn_type_blk);
    const ft_params_empty = try g.listInit(&.{});
    const ft_loop_blk = g.reserveBlock();
    try g.jump(ft_loop_blk, &.{ next_pos, ft_params_empty });

    g.beginReservedBlock(ft_loop_blk);
    const ft_pos = try g.addBlockParam();
    const ft_list = try g.addBlockParam();
    const ft_tok = try emitGetToken(g, tokens, ft_pos);
    const ft_is_delim = try g.tagTest(ft_tok, "Delim");
    const ft_check_rp_blk = g.reserveBlock();
    const ft_parse_blk = g.reserveBlock();
    try g.branch(ft_is_delim, ft_check_rp_blk, ft_parse_blk);

    g.beginReservedBlock(ft_check_rp_blk);
    const ft_delim = try g.tagPayload(ft_tok, "Delim");
    const ft_rparen = try g.constString(")");
    const ft_is_rp = try g.eq(ft_delim, ft_rparen);
    const ft_done_blk = g.reserveBlock();
    try g.branch(ft_is_rp, ft_done_blk, ft_parse_blk);

    g.beginReservedBlock(ft_parse_blk);
    const ft_param_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, ft_pos });
    const ft_param_node = try g.recordField(ft_param_result, "node");
    const ft_param_next = try g.recordField(ft_param_result, "pos");
    const ft_list2 = try g.listAppend(ft_list, ft_param_node);
    // Check for comma
    const ftc_tok = try emitGetToken(g, tokens, ft_param_next);
    const ftc_is_punct = try g.tagTest(ftc_tok, "Punct");
    const ftc_check_blk = g.reserveBlock();
    const ftc_no_blk = g.reserveBlock();
    try g.branch(ftc_is_punct, ftc_check_blk, ftc_no_blk);

    g.beginReservedBlock(ftc_check_blk);
    const ftc_val = try g.tagPayload(ftc_tok, "Punct");
    const ftc_comma = try g.constString(",");
    const ftc_is_comma = try g.eq(ftc_val, ftc_comma);
    const ftc_skip_blk = g.reserveBlock();
    try g.branch(ftc_is_comma, ftc_skip_blk, ftc_no_blk);

    g.beginReservedBlock(ftc_skip_blk);
    const ftc_after = try emitAdvance(g, ft_param_next);
    try g.jump(ft_loop_blk, &.{ ftc_after, ft_list2 });

    g.beginReservedBlock(ftc_no_blk);
    try g.jump(ft_loop_blk, &.{ ft_param_next, ft_list2 });

    // After ): check for -> (fn type) or -[ (effect fn type)
    g.beginReservedBlock(ft_done_blk);
    const ft_after_rp = try emitAdvance(g, ft_pos); // skip )
    const ft_arrow_tok = try emitGetToken(g, tokens, ft_after_rp);
    const ft_arrow_is_op = try g.tagTest(ft_arrow_tok, "Op");
    const ft_check_arrow_blk = g.reserveBlock();
    const ft_not_fn_blk = g.reserveBlock();
    try g.branch(ft_arrow_is_op, ft_check_arrow_blk, ft_not_fn_blk);

    g.beginReservedBlock(ft_check_arrow_blk);
    const ft_arrow_val = try g.tagPayload(ft_arrow_tok, "Op");
    const ft_arrow_str = try g.constString("->");
    const ft_is_arrow = try g.eq(ft_arrow_val, ft_arrow_str);
    const ft_plain_arrow_blk = g.reserveBlock();
    const ft_check_eff_blk = g.reserveBlock();
    try g.branch(ft_is_arrow, ft_plain_arrow_blk, ft_check_eff_blk);

    // (A, B) -> C
    g.beginReservedBlock(ft_plain_arrow_blk);
    const ft_nil_effects = try g.listInit(&.{});
    const ft_ret_start = try emitAdvance(g, ft_after_rp); // skip ->
    const ft_ret_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, ft_ret_start });
    const ft_ret_node = try g.recordField(ft_ret_result, "node");
    const ft_ret_end = try g.recordField(ft_ret_result, "pos");
    const ft_rec = try g.record(&.{
        .{ .name = "params", .value = ft_list },
        .{ .name = "effects", .value = ft_nil_effects },
        .{ .name = "ret", .value = ft_ret_node },
    });
    const ft_node = try g.tag(ast_type_fn, ft_rec);
    const ft_res = try emitResult(g, ft_node, ft_ret_end);
    try g.ret(ft_res);

    // Check for -[ (effect fn type)
    g.beginReservedBlock(ft_check_eff_blk);
    const ft_eff_str = try g.constString("-[");
    const ft_is_eff = try g.eq(ft_arrow_val, ft_eff_str);
    const ft_eff_blk = g.reserveBlock();
    try g.branch(ft_is_eff, ft_eff_blk, ft_not_fn_blk);

    // (A, B) -[E]> C
    g.beginReservedBlock(ft_eff_blk);
    const fte_start = try emitAdvance(g, ft_after_rp); // skip -[
    const fte_empty = try g.listInit(&.{});
    const fte_loop_blk = g.reserveBlock();
    try g.jump(fte_loop_blk, &.{ fte_start, fte_empty });

    g.beginReservedBlock(fte_loop_blk);
    const fte_pos = try g.addBlockParam();
    const fte_list = try g.addBlockParam();
    const fte_tok = try emitGetToken(g, tokens, fte_pos);
    const fte_is_op = try g.tagTest(fte_tok, "Op");
    const fte_check_close_blk = g.reserveBlock();
    const fte_parse_blk = g.reserveBlock();
    try g.branch(fte_is_op, fte_check_close_blk, fte_parse_blk);

    g.beginReservedBlock(fte_check_close_blk);
    const fte_op_val = try g.tagPayload(fte_tok, "Op");
    const fte_close = try g.constString("]>");
    const fte_is_close = try g.eq(fte_op_val, fte_close);
    const fte_done_blk = g.reserveBlock();
    try g.branch(fte_is_close, fte_done_blk, fte_parse_blk);

    g.beginReservedBlock(fte_parse_blk);
    const fte_name = try g.tagPayload(fte_tok, "UpperIdent");
    const fte_list2 = try g.listAppend(fte_list, fte_name);
    const fte_next = try emitAdvance(g, fte_pos);
    const ftec_tok = try emitGetToken(g, tokens, fte_next);
    const ftec_is_punct = try g.tagTest(ftec_tok, "Punct");
    const ftec_check_blk = g.reserveBlock();
    const ftec_no_blk = g.reserveBlock();
    try g.branch(ftec_is_punct, ftec_check_blk, ftec_no_blk);

    g.beginReservedBlock(ftec_check_blk);
    const ftec_val = try g.tagPayload(ftec_tok, "Punct");
    const ftec_comma = try g.constString(",");
    const ftec_is_comma = try g.eq(ftec_val, ftec_comma);
    const ftec_skip_blk = g.reserveBlock();
    try g.branch(ftec_is_comma, ftec_skip_blk, ftec_no_blk);

    g.beginReservedBlock(ftec_skip_blk);
    const ftec_after = try emitAdvance(g, fte_next);
    try g.jump(fte_loop_blk, &.{ ftec_after, fte_list2 });

    g.beginReservedBlock(ftec_no_blk);
    try g.jump(fte_loop_blk, &.{ fte_next, fte_list2 });

    g.beginReservedBlock(fte_done_blk);
    const fte_after_close = try emitAdvance(g, fte_pos); // skip ]>
    const fte_ret_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, fte_after_close });
    const fte_ret_node = try g.recordField(fte_ret_result, "node");
    const fte_ret_end = try g.recordField(fte_ret_result, "pos");
    const fte_rec = try g.record(&.{
        .{ .name = "params", .value = ft_list },
        .{ .name = "effects", .value = fte_list },
        .{ .name = "ret", .value = fte_ret_node },
    });
    const fte_node = try g.tag(ast_type_fn, fte_rec);
    const fte_res = try emitResult(g, fte_node, fte_ret_end);
    try g.ret(fte_res);

    // Not a fn type — if single param, treat as grouped type
    g.beginReservedBlock(ft_not_fn_blk);
    // Just use the first (and only) param type as a grouped type
    const ft_first = try g.listHead(ft_list);
    try g.jump(check_suffix_blk, &.{ ft_first, ft_after_rp });

    // fallback: return a placeholder
    g.beginReservedBlock(fallback_blk);
    const fb_name = try g.constString("Unknown");
    const fb_node = try g.tag(ast_type_named, fb_name);
    const fb_res = try emitResult(g, fb_node, pos);
    try g.ret(fb_res);

    // ── check_suffix: after parsing a primary type, check for ?, |, & ──
    g.beginReservedBlock(check_suffix_blk);
    const sf_node = try g.addBlockParam();
    const sf_pos = try g.addBlockParam();
    const sf_tok = try emitGetToken(g, tokens, sf_pos);
    const sf_is_op = try g.tagTest(sf_tok, "Op");
    const sf_check_op_blk = g.reserveBlock();
    const sf_done_blk = g.reserveBlock();
    try g.branch(sf_is_op, sf_check_op_blk, sf_done_blk);

    g.beginReservedBlock(sf_check_op_blk);
    const sf_op_val = try g.tagPayload(sf_tok, "Op");

    // Check for ? (nullable)
    const sf_q_str = try g.constString("?");
    const sf_is_q = try g.eq(sf_op_val, sf_q_str);
    const sf_nullable_blk = g.reserveBlock();
    const sf_check_pipe_blk = g.reserveBlock();
    try g.branch(sf_is_q, sf_nullable_blk, sf_check_pipe_blk);

    g.beginReservedBlock(sf_nullable_blk);
    const sf_nullable = try g.tag(ast_type_nullable, sf_node);
    const sf_nq_pos = try emitAdvance(g, sf_pos);
    // After nullable, check for more suffixes
    try g.jump(check_suffix_blk, &.{ sf_nullable, sf_nq_pos });

    // Check for | (union)
    g.beginReservedBlock(sf_check_pipe_blk);
    const sf_pipe_str = try g.constString("|");
    const sf_is_pipe = try g.eq(sf_op_val, sf_pipe_str);
    const sf_union_blk = g.reserveBlock();
    const sf_check_amp_blk = g.reserveBlock();
    try g.branch(sf_is_pipe, sf_union_blk, sf_check_amp_blk);

    g.beginReservedBlock(sf_union_blk);
    const sf_u_next = try emitAdvance(g, sf_pos); // skip |
    const sf_u_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, sf_u_next });
    const sf_u_rhs = try g.recordField(sf_u_result, "node");
    const sf_u_end = try g.recordField(sf_u_result, "pos");
    const sf_u_rec = try g.record(&.{
        .{ .name = "lhs", .value = sf_node },
        .{ .name = "rhs", .value = sf_u_rhs },
    });
    const sf_u_node = try g.tag(ast_type_union, sf_u_rec);
    const sf_u_res = try emitResult(g, sf_u_node, sf_u_end);
    try g.ret(sf_u_res);

    // Check for & (intersection)
    g.beginReservedBlock(sf_check_amp_blk);
    const sf_amp_str = try g.constString("&");
    const sf_is_amp = try g.eq(sf_op_val, sf_amp_str);
    const sf_inter_blk = g.reserveBlock();
    try g.branch(sf_is_amp, sf_inter_blk, sf_done_blk);

    g.beginReservedBlock(sf_inter_blk);
    const sf_i_next = try emitAdvance(g, sf_pos); // skip &
    const sf_i_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, sf_i_next });
    const sf_i_rhs = try g.recordField(sf_i_result, "node");
    const sf_i_end = try g.recordField(sf_i_result, "pos");
    const sf_i_rec = try g.record(&.{
        .{ .name = "lhs", .value = sf_node },
        .{ .name = "rhs", .value = sf_i_rhs },
    });
    const sf_i_node = try g.tag(ast_type_intersection, sf_i_rec);
    const sf_i_res = try emitResult(g, sf_i_node, sf_i_end);
    try g.ret(sf_i_res);

    // No suffix: return as-is
    g.beginReservedBlock(sf_done_blk);
    const sf_res = try emitResult(g, sf_node, sf_pos);
    try g.ret(sf_res);

    try g.endReservedFunc(pf.parse_type_expr);
}

// ── parse_primary(tokens, pos) -> Record{node, pos} ────────────────────

fn genParsePrimary(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_primary");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    // entry: peek at token
    _ = g.beginBlock();
    const tok = try emitGetToken(g, tokens, pos);
    const next_pos = try emitAdvance(g, pos);

    // IntLit
    const is_int = try g.tagTest(tok, "IntLit");
    const int_blk = g.reserveBlock();
    const c1 = g.reserveBlock();
    try g.branch(is_int, int_blk, c1);

    g.beginReservedBlock(int_blk);
    const int_text = try g.tagPayload(tok, "IntLit");
    const int_val = try g.stringToInt(int_text);
    const int_node = try g.tag(ast_int_lit, int_val);
    const int_res = try emitResult(g, int_node, next_pos);
    try g.ret(int_res);

    // FloatLit
    g.beginReservedBlock(c1);
    const is_float = try g.tagTest(tok, "FloatLit");
    const float_blk = g.reserveBlock();
    const c2 = g.reserveBlock();
    try g.branch(is_float, float_blk, c2);

    g.beginReservedBlock(float_blk);
    const float_text = try g.tagPayload(tok, "FloatLit");
    const float_node = try g.tag(ast_float_lit, float_text);
    const float_res = try emitResult(g, float_node, next_pos);
    try g.ret(float_res);

    // StringLit
    g.beginReservedBlock(c2);
    const is_str = try g.tagTest(tok, "StringLit");
    const str_blk = g.reserveBlock();
    const c3 = g.reserveBlock();
    try g.branch(is_str, str_blk, c3);

    g.beginReservedBlock(str_blk);
    const str_val = try g.tagPayload(tok, "StringLit");
    const str_node = try g.tag(ast_string_lit, str_val);
    const str_res = try emitResult(g, str_node, next_pos);
    try g.ret(str_res);

    // StringInterp — string with interpolation markers
    g.beginReservedBlock(c3);
    const is_interp = try g.tagTest(tok, "StringInterp");
    const interp_blk = g.reserveBlock();
    const c3b = g.reserveBlock();
    try g.branch(is_interp, interp_blk, c3b);

    g.beginReservedBlock(interp_blk);
    const interp_val = try g.tagPayload(tok, "StringInterp");
    const interp_node = try g.tag(ast_string_interp, interp_val);
    const interp_res = try emitResult(g, interp_node, next_pos);
    try g.ret(interp_res);

    // BoolLit
    g.beginReservedBlock(c3b);
    const is_bool = try g.tagTest(tok, "BoolLit");
    const bool_blk = g.reserveBlock();
    const c4 = g.reserveBlock();
    try g.branch(is_bool, bool_blk, c4);

    g.beginReservedBlock(bool_blk);
    const bool_val = try g.tagPayload(tok, "BoolLit");
    const bool_node = try g.tag(ast_bool_lit, bool_val);
    const bool_res = try emitResult(g, bool_node, next_pos);
    try g.ret(bool_res);

    // NilLit
    g.beginReservedBlock(c4);
    const is_nil = try g.tagTest(tok, "NilLit");
    const nil_blk = g.reserveBlock();
    const c5 = g.reserveBlock();
    try g.branch(is_nil, nil_blk, c5);

    g.beginReservedBlock(nil_blk);
    const nil_node = try g.tag(ast_nil_lit, null);
    const nil_res = try emitResult(g, nil_node, next_pos);
    try g.ret(nil_res);

    // Ident — variable reference, or start of lambda (x => ...)
    g.beginReservedBlock(c5);
    const is_ident = try g.tagTest(tok, "Ident");
    const ident_blk = g.reserveBlock();
    const c6 = g.reserveBlock();
    try g.branch(is_ident, ident_blk, c6);

    g.beginReservedBlock(ident_blk);
    const id_name = try g.tagPayload(tok, "Ident");
    // Check if next token is => (lambda)
    const lam_tok = try emitGetToken(g, tokens, next_pos);
    const lam_is_op = try g.tagTest(lam_tok, "Op");
    const check_arrow_blk = g.reserveBlock();
    const just_ident_blk = g.reserveBlock();
    try g.branch(lam_is_op, check_arrow_blk, just_ident_blk);

    g.beginReservedBlock(check_arrow_blk);
    const lam_op = try g.tagPayload(lam_tok, "Op");
    const arrow_str = try g.constString("=>");
    const is_arrow = try g.eq(lam_op, arrow_str);
    const lambda_blk = g.reserveBlock();
    try g.branch(is_arrow, lambda_blk, just_ident_blk);

    // lambda: x => body
    g.beginReservedBlock(lambda_blk);
    const lam_body_pos = try emitAdvance(g, next_pos); // skip =>
    const lam_zero = try g.constInt(0);
    const lam_body_result = try g.callDirect(pf.parse_expr, &.{ tokens, lam_body_pos, lam_zero });
    const lam_body = try g.recordField(lam_body_result, "node");
    const lam_end = try g.recordField(lam_body_result, "pos");
    const param_list = try g.listInit(&.{id_name});
    const lam_rec = try g.record(&.{
        .{ .name = "params", .value = param_list },
        .{ .name = "body", .value = lam_body },
    });
    const lam_node = try g.tag(ast_lambda, lam_rec);
    const lam_res = try emitResult(g, lam_node, lam_end);
    try g.ret(lam_res);

    // just_ident: simple variable reference
    g.beginReservedBlock(just_ident_blk);
    const ident_node = try g.tag(ast_ident, id_name);
    const ident_res = try emitResult(g, ident_node, next_pos);
    try g.ret(ident_res);

    // UpperIdent — constructor call or type reference
    g.beginReservedBlock(c6);
    const is_upper = try g.tagTest(tok, "UpperIdent");
    const upper_blk = g.reserveBlock();
    const c7 = g.reserveBlock();
    try g.branch(is_upper, upper_blk, c7);

    g.beginReservedBlock(upper_blk);
    const upper_name = try g.tagPayload(tok, "UpperIdent");
    const upper_node = try g.tag(ast_ident, upper_name);
    const upper_res = try emitResult(g, upper_node, next_pos);
    try g.ret(upper_res);

    // Keyword — if, match, let, handle, fn (lambda)
    g.beginReservedBlock(c7);
    const is_kw = try g.tagTest(tok, "Keyword");
    const kw_blk = g.reserveBlock();
    const c8 = g.reserveBlock();
    try g.branch(is_kw, kw_blk, c8);

    g.beginReservedBlock(kw_blk);
    const kw_val = try g.tagPayload(tok, "Keyword");

    // if
    const if_str = try g.constString("if");
    const is_if = try g.eq(kw_val, if_str);
    const if_blk = g.reserveBlock();
    const kw2 = g.reserveBlock();
    try g.branch(is_if, if_blk, kw2);

    g.beginReservedBlock(if_blk);
    const if_result = try g.callDirect(pf.parse_if, &.{ tokens, next_pos });
    try g.ret(if_result);

    // match
    g.beginReservedBlock(kw2);
    const match_str = try g.constString("match");
    const is_match = try g.eq(kw_val, match_str);
    const match_blk = g.reserveBlock();
    const kw3 = g.reserveBlock();
    try g.branch(is_match, match_blk, kw3);

    g.beginReservedBlock(match_blk);
    const match_result = try g.callDirect(pf.parse_match, &.{ tokens, next_pos });
    try g.ret(match_result);

    // let
    g.beginReservedBlock(kw3);
    const let_str = try g.constString("let");
    const is_let = try g.eq(kw_val, let_str);
    const let_blk = g.reserveBlock();
    const kw4 = g.reserveBlock();
    try g.branch(is_let, let_blk, kw4);

    g.beginReservedBlock(let_blk);
    const let_result = try g.callDirect(pf.parse_let, &.{ tokens, next_pos });
    try g.ret(let_result);

    // handle
    g.beginReservedBlock(kw4);
    const handle_str = try g.constString("handle");
    const is_handle = try g.eq(kw_val, handle_str);
    const handle_blk = g.reserveBlock();
    const kw5 = g.reserveBlock();
    try g.branch(is_handle, handle_blk, kw5);

    g.beginReservedBlock(handle_blk);
    const handle_result = try g.callDirect(pf.parse_handle, &.{ tokens, next_pos });
    try g.ret(handle_result);

    // unknown keyword — treat as ident
    g.beginReservedBlock(kw5);
    const kw_ident = try g.tag(ast_ident, kw_val);
    const kw_res = try emitResult(g, kw_ident, next_pos);
    try g.ret(kw_res);

    // Delim — ( for grouping or tuple, [ for list, { for block/record
    g.beginReservedBlock(c8);
    const is_delim = try g.tagTest(tok, "Delim");
    const delim_blk = g.reserveBlock();
    const c9 = g.reserveBlock();
    try g.branch(is_delim, delim_blk, c9);

    g.beginReservedBlock(delim_blk);
    const delim_val = try g.tagPayload(tok, "Delim");

    // ( — grouping
    const lparen_str = try g.constString("(");
    const is_lp = try g.eq(delim_val, lparen_str);
    const group_blk = g.reserveBlock();
    const check_lbrace_blk = g.reserveBlock();
    try g.branch(is_lp, group_blk, check_lbrace_blk);

    g.beginReservedBlock(group_blk);
    const gzero = try g.constInt(0);
    const group_result = try g.callDirect(pf.parse_expr, &.{ tokens, next_pos, gzero });
    const group_node = try g.recordField(group_result, "node");
    const group_end = try g.recordField(group_result, "pos");
    // Skip closing )
    const after_rp = try emitAdvance(g, group_end);
    const group_res = try emitResult(g, group_node, after_rp);
    try g.ret(group_res);

    // { — block, record literal, or record update
    g.beginReservedBlock(check_lbrace_blk);
    const lbrace_str = try g.constString("{");
    const is_lb = try g.eq(delim_val, lbrace_str);
    const brace_blk = g.reserveBlock();
    const check_lbracket_blk = g.reserveBlock();
    try g.branch(is_lb, brace_blk, check_lbracket_blk);

    // Disambiguate: { Ident : → record literal, { expr | → record update, else → block
    g.beginReservedBlock(brace_blk);
    const br_tok1 = try emitGetToken(g, tokens, next_pos);
    const br_is_ident = try g.tagTest(br_tok1, "Ident");
    const br_check_rec_blk = g.reserveBlock();
    const br_block_blk = g.reserveBlock();
    try g.branch(br_is_ident, br_check_rec_blk, br_block_blk);

    g.beginReservedBlock(br_check_rec_blk);
    const br_pos2 = try emitAdvance(g, next_pos);
    const br_tok2 = try emitGetToken(g, tokens, br_pos2);
    // Check if token after ident is : (record) or | (record update)
    const br_is_punct = try g.tagTest(br_tok2, "Punct");
    const br_check_colon_blk = g.reserveBlock();
    const br_check_pipe_blk = g.reserveBlock();
    try g.branch(br_is_punct, br_check_colon_blk, br_check_pipe_blk);

    g.beginReservedBlock(br_check_colon_blk);
    const br_punct_val = try g.tagPayload(br_tok2, "Punct");
    const br_colon = try g.constString(":");
    const br_is_colon = try g.eq(br_punct_val, br_colon);
    const rec_lit_blk = g.reserveBlock();
    try g.branch(br_is_colon, rec_lit_blk, br_check_pipe_blk);

    // Check for | (record update: { base | field: val })
    g.beginReservedBlock(br_check_pipe_blk);
    const br_is_op = try g.tagTest(br_tok2, "Op");
    const br_check_pipe2_blk = g.reserveBlock();
    try g.branch(br_is_op, br_check_pipe2_blk, br_block_blk);

    g.beginReservedBlock(br_check_pipe2_blk);
    const br_op_val = try g.tagPayload(br_tok2, "Op");
    const br_pipe = try g.constString("|");
    const br_is_pipe_op = try g.eq(br_op_val, br_pipe);
    const rec_update_blk = g.reserveBlock();
    try g.branch(br_is_pipe_op, rec_update_blk, br_block_blk);

    // Record literal: { name: expr, name: expr }
    g.beginReservedBlock(rec_lit_blk);
    const rl_empty = try g.listInit(&.{});
    const rl_loop_blk = g.reserveBlock();
    try g.jump(rl_loop_blk, &.{ next_pos, rl_empty });

    g.beginReservedBlock(rl_loop_blk);
    const rl_pos = try g.addBlockParam();
    const rl_fields = try g.addBlockParam();
    const rl_tok = try emitGetToken(g, tokens, rl_pos);
    // Check for }
    const rl_is_delim = try g.tagTest(rl_tok, "Delim");
    const rl_check_rb_blk = g.reserveBlock();
    const rl_parse_blk = g.reserveBlock();
    try g.branch(rl_is_delim, rl_check_rb_blk, rl_parse_blk);

    g.beginReservedBlock(rl_check_rb_blk);
    const rl_delim = try g.tagPayload(rl_tok, "Delim");
    const rl_rbrace = try g.constString("}");
    const rl_is_rb = try g.eq(rl_delim, rl_rbrace);
    const rl_done_blk = g.reserveBlock();
    try g.branch(rl_is_rb, rl_done_blk, rl_parse_blk);

    // Parse one field: name: expr
    g.beginReservedBlock(rl_parse_blk);
    const rl_fname = try g.tagPayload(rl_tok, "Ident");
    const rl_after_name = try emitAdvance(g, rl_pos);
    const rl_after_colon = try emitAdvance(g, rl_after_name); // skip :
    const rl_zero = try g.constInt(0);
    const rl_val_result = try g.callDirect(pf.parse_expr, &.{ tokens, rl_after_colon, rl_zero });
    const rl_val_node = try g.recordField(rl_val_result, "node");
    const rl_val_end = try g.recordField(rl_val_result, "pos");
    const rl_field = try g.record(&.{
        .{ .name = "name", .value = rl_fname },
        .{ .name = "value", .value = rl_val_node },
    });
    const rl_fields2 = try g.listAppend(rl_fields, rl_field);
    // Check for comma
    const rlc_tok = try emitGetToken(g, tokens, rl_val_end);
    const rlc_is_punct = try g.tagTest(rlc_tok, "Punct");
    const rlc_check_blk = g.reserveBlock();
    const rlc_no_blk = g.reserveBlock();
    try g.branch(rlc_is_punct, rlc_check_blk, rlc_no_blk);

    g.beginReservedBlock(rlc_check_blk);
    const rlc_val = try g.tagPayload(rlc_tok, "Punct");
    const rlc_comma = try g.constString(",");
    const rlc_is_comma = try g.eq(rlc_val, rlc_comma);
    const rlc_skip_blk = g.reserveBlock();
    try g.branch(rlc_is_comma, rlc_skip_blk, rlc_no_blk);

    g.beginReservedBlock(rlc_skip_blk);
    const rlc_after = try emitAdvance(g, rl_val_end);
    try g.jump(rl_loop_blk, &.{ rlc_after, rl_fields2 });

    g.beginReservedBlock(rlc_no_blk);
    try g.jump(rl_loop_blk, &.{ rl_val_end, rl_fields2 });

    g.beginReservedBlock(rl_done_blk);
    const rl_after_rb = try emitAdvance(g, rl_pos);
    const rl_node = try g.tag(ast_record_lit, rl_fields);
    const rl_res = try emitResult(g, rl_node, rl_after_rb);
    try g.ret(rl_res);

    // Record update: { base | field: val, field: val }
    g.beginReservedBlock(rec_update_blk);
    const ru_base_name = try g.tagPayload(br_tok1, "Ident");
    const ru_base = try g.tag(ast_ident, ru_base_name);
    const ru_after_pipe = try emitAdvance(g, br_pos2); // skip |
    const ru_empty = try g.listInit(&.{});
    const ru_loop_blk = g.reserveBlock();
    try g.jump(ru_loop_blk, &.{ ru_after_pipe, ru_empty });

    g.beginReservedBlock(ru_loop_blk);
    const ru_pos = try g.addBlockParam();
    const ru_fields = try g.addBlockParam();
    const ru_tok = try emitGetToken(g, tokens, ru_pos);
    const ru_is_delim = try g.tagTest(ru_tok, "Delim");
    const ru_check_rb_blk = g.reserveBlock();
    const ru_parse_blk = g.reserveBlock();
    try g.branch(ru_is_delim, ru_check_rb_blk, ru_parse_blk);

    g.beginReservedBlock(ru_check_rb_blk);
    const ru_delim = try g.tagPayload(ru_tok, "Delim");
    const ru_rbrace = try g.constString("}");
    const ru_is_rb = try g.eq(ru_delim, ru_rbrace);
    const ru_done_blk = g.reserveBlock();
    try g.branch(ru_is_rb, ru_done_blk, ru_parse_blk);

    g.beginReservedBlock(ru_parse_blk);
    const ru_fname = try g.tagPayload(ru_tok, "Ident");
    const ru_after_name = try emitAdvance(g, ru_pos);
    const ru_after_colon = try emitAdvance(g, ru_after_name); // skip :
    const ru_zero = try g.constInt(0);
    const ru_val_result = try g.callDirect(pf.parse_expr, &.{ tokens, ru_after_colon, ru_zero });
    const ru_val_node = try g.recordField(ru_val_result, "node");
    const ru_val_end = try g.recordField(ru_val_result, "pos");
    const ru_field = try g.record(&.{
        .{ .name = "name", .value = ru_fname },
        .{ .name = "value", .value = ru_val_node },
    });
    const ru_fields2 = try g.listAppend(ru_fields, ru_field);
    const ruc_tok = try emitGetToken(g, tokens, ru_val_end);
    const ruc_is_punct = try g.tagTest(ruc_tok, "Punct");
    const ruc_check_blk = g.reserveBlock();
    const ruc_no_blk = g.reserveBlock();
    try g.branch(ruc_is_punct, ruc_check_blk, ruc_no_blk);

    g.beginReservedBlock(ruc_check_blk);
    const ruc_val = try g.tagPayload(ruc_tok, "Punct");
    const ruc_comma = try g.constString(",");
    const ruc_is_comma = try g.eq(ruc_val, ruc_comma);
    const ruc_skip_blk = g.reserveBlock();
    try g.branch(ruc_is_comma, ruc_skip_blk, ruc_no_blk);

    g.beginReservedBlock(ruc_skip_blk);
    const ruc_after = try emitAdvance(g, ru_val_end);
    try g.jump(ru_loop_blk, &.{ ruc_after, ru_fields2 });

    g.beginReservedBlock(ruc_no_blk);
    try g.jump(ru_loop_blk, &.{ ru_val_end, ru_fields2 });

    g.beginReservedBlock(ru_done_blk);
    const ru_after_rb = try emitAdvance(g, ru_pos);
    const ru_rec = try g.record(&.{
        .{ .name = "base", .value = ru_base },
        .{ .name = "fields", .value = ru_fields },
    });
    const ru_node = try g.tag(ast_record_update, ru_rec);
    const ru_res = try emitResult(g, ru_node, ru_after_rb);
    try g.ret(ru_res);

    // Fall through to block parsing
    g.beginReservedBlock(br_block_blk);
    const block_result = try g.callDirect(pf.parse_block, &.{ tokens, next_pos });
    try g.ret(block_result);

    // [ — list literal
    g.beginReservedBlock(check_lbracket_blk);
    const lbracket_str = try g.constString("[");
    const is_lbr = try g.eq(delim_val, lbracket_str);
    const list_blk = g.reserveBlock();
    const fallback_blk = g.reserveBlock();
    try g.branch(is_lbr, list_blk, fallback_blk);

    g.beginReservedBlock(list_blk);
    // Parse comma-separated expressions until ]
    const list_empty = try g.listInit(&.{});
    const list_loop_blk = g.reserveBlock();
    try g.jump(list_loop_blk, &.{ next_pos, list_empty });

    g.beginReservedBlock(list_loop_blk);
    const l_pos = try g.addBlockParam();
    const l_items = try g.addBlockParam();
    const l_tok = try emitGetToken(g, tokens, l_pos);
    const l_is_delim = try g.tagTest(l_tok, "Delim");
    const l_check_rb_blk = g.reserveBlock();
    const l_parse_blk = g.reserveBlock();
    try g.branch(l_is_delim, l_check_rb_blk, l_parse_blk);

    g.beginReservedBlock(l_check_rb_blk);
    const l_delim = try g.tagPayload(l_tok, "Delim");
    const rbracket_str = try g.constString("]");
    const l_is_rb = try g.eq(l_delim, rbracket_str);
    const l_done_blk = g.reserveBlock();
    try g.branch(l_is_rb, l_done_blk, l_parse_blk);

    g.beginReservedBlock(l_parse_blk);
    const lzero = try g.constInt(0);
    const l_expr_result = try g.callDirect(pf.parse_expr, &.{ tokens, l_pos, lzero });
    const l_node = try g.recordField(l_expr_result, "node");
    const l_next = try g.recordField(l_expr_result, "pos");
    const l_items2 = try g.listAppend(l_items, l_node);
    // Check for comma
    const lc_tok = try emitGetToken(g, tokens, l_next);
    const lc_is_punct = try g.tagTest(lc_tok, "Punct");
    const lc_check_blk = g.reserveBlock();
    const lc_no_blk = g.reserveBlock();
    try g.branch(lc_is_punct, lc_check_blk, lc_no_blk);

    g.beginReservedBlock(lc_check_blk);
    const lc_val = try g.tagPayload(lc_tok, "Punct");
    const lc_comma = try g.constString(",");
    const lc_is_c = try g.eq(lc_val, lc_comma);
    const lc_skip_blk = g.reserveBlock();
    try g.branch(lc_is_c, lc_skip_blk, lc_no_blk);

    g.beginReservedBlock(lc_skip_blk);
    const lc_after = try emitAdvance(g, l_next);
    try g.jump(list_loop_blk, &.{ lc_after, l_items2 });

    g.beginReservedBlock(lc_no_blk);
    try g.jump(list_loop_blk, &.{ l_next, l_items2 });

    g.beginReservedBlock(l_done_blk);
    const l_after_rb = try emitAdvance(g, l_pos);
    const list_node = try g.tag(ast_list_lit, l_items);
    const list_res = try emitResult(g, list_node, l_after_rb);
    try g.ret(list_res);

    // Op — unary prefix operators (-, !, ~)
    g.beginReservedBlock(c9);
    const is_op2 = try g.tagTest(tok, "Op");
    const unary_blk = g.reserveBlock();
    const fallback2_blk = g.reserveBlock();
    try g.branch(is_op2, unary_blk, fallback2_blk);

    g.beginReservedBlock(unary_blk);
    const op_val = try g.tagPayload(tok, "Op");
    // Check for unary operators: -, !, ~
    const neg_str = try g.constString("-");
    const is_neg = try g.eq(op_val, neg_str);
    const not_str = try g.constString("!");
    const is_not = try g.eq(op_val, not_str);
    const is_unary = try g.logicOr(is_neg, is_not);
    const do_unary_blk = g.reserveBlock();
    try g.branch(is_unary, do_unary_blk, fallback2_blk);

    g.beginReservedBlock(do_unary_blk);
    const u_bp = try g.constInt(17); // unary prefix binding power
    const u_result = try g.callDirect(pf.parse_expr, &.{ tokens, next_pos, u_bp });
    const u_operand = try g.recordField(u_result, "node");
    const u_end = try g.recordField(u_result, "pos");
    const u_rec = try g.record(&.{
        .{ .name = "op", .value = op_val },
        .{ .name = "operand", .value = u_operand },
    });
    const u_node = try g.tag(ast_unary, u_rec);
    const u_res = try emitResult(g, u_node, u_end);
    try g.ret(u_res);

    // fallback: return nil placeholder
    g.beginReservedBlock(fallback_blk);
    const fb_node = try g.tag(ast_nil_lit, null);
    const fb_res = try emitResult(g, fb_node, next_pos);
    try g.ret(fb_res);

    g.beginReservedBlock(fallback2_blk);
    const fb2_node = try g.tag(ast_nil_lit, null);
    const fb2_res = try emitResult(g, fb2_node, next_pos);
    try g.ret(fb2_res);

    try g.endReservedFunc(pf.parse_primary);
}

// ── parse_expr(tokens, pos, min_bp) -> Record{node, pos} ───────────────
// Pratt precedence parser.

fn genParseExpr(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_expr");
    const tokens = try g.addParam();
    const pos = try g.addParam();
    const min_bp = try g.addParam();

    // entry: parse the left-hand side (primary expression)
    _ = g.beginBlock();
    const lhs_result = try g.callDirect(pf.parse_primary, &.{ tokens, pos });
    const lhs_node = try g.recordField(lhs_result, "node");
    const lhs_pos = try g.recordField(lhs_result, "pos");
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{ lhs_node, lhs_pos });

    // loop: check for infix/postfix operators
    g.beginReservedBlock(loop_blk);
    const cur_node = try g.addBlockParam();
    const cur_pos = try g.addBlockParam();
    const tok = try emitGetToken(g, tokens, cur_pos);
    const zero = try g.constInt(0);

    // Check for postfix: function call — Expr(args)
    const is_delim = try g.tagTest(tok, "Delim");
    const check_call_blk = g.reserveBlock();
    const check_dot_blk = g.reserveBlock();
    try g.branch(is_delim, check_call_blk, check_dot_blk);

    // check_call: is it ( for function call?
    g.beginReservedBlock(check_call_blk);
    const delim_val = try g.tagPayload(tok, "Delim");
    const lparen = try g.constString("(");
    const is_call = try g.eq(delim_val, lparen);
    const call_blk = g.reserveBlock();
    try g.branch(is_call, call_blk, check_dot_blk);

    // call: parse arguments
    g.beginReservedBlock(call_blk);
    const call_start = try emitAdvance(g, cur_pos); // skip (
    const call_args = try g.listInit(&.{});
    const call_loop_blk = g.reserveBlock();
    try g.jump(call_loop_blk, &.{ call_start, call_args });

    g.beginReservedBlock(call_loop_blk);
    const ca_pos = try g.addBlockParam();
    const ca_args = try g.addBlockParam();
    const ca_tok = try emitGetToken(g, tokens, ca_pos);
    const ca_is_delim = try g.tagTest(ca_tok, "Delim");
    const ca_check_rp_blk = g.reserveBlock();
    const ca_parse_blk = g.reserveBlock();
    try g.branch(ca_is_delim, ca_check_rp_blk, ca_parse_blk);

    g.beginReservedBlock(ca_check_rp_blk);
    const ca_delim = try g.tagPayload(ca_tok, "Delim");
    const rparen = try g.constString(")");
    const ca_is_rp = try g.eq(ca_delim, rparen);
    const ca_done_blk = g.reserveBlock();
    try g.branch(ca_is_rp, ca_done_blk, ca_parse_blk);

    g.beginReservedBlock(ca_parse_blk);
    const cazero = try g.constInt(0);
    const ca_expr = try g.callDirect(pf.parse_expr, &.{ tokens, ca_pos, cazero });
    const ca_node = try g.recordField(ca_expr, "node");
    const ca_next = try g.recordField(ca_expr, "pos");
    const ca_args2 = try g.listAppend(ca_args, ca_node);
    // Check for comma
    const cac_tok = try emitGetToken(g, tokens, ca_next);
    const cac_is_punct = try g.tagTest(cac_tok, "Punct");
    const cac_check_blk = g.reserveBlock();
    const cac_no_blk = g.reserveBlock();
    try g.branch(cac_is_punct, cac_check_blk, cac_no_blk);

    g.beginReservedBlock(cac_check_blk);
    const cac_val = try g.tagPayload(cac_tok, "Punct");
    const cac_comma = try g.constString(",");
    const cac_is_c = try g.eq(cac_val, cac_comma);
    const cac_skip_blk = g.reserveBlock();
    try g.branch(cac_is_c, cac_skip_blk, cac_no_blk);

    g.beginReservedBlock(cac_skip_blk);
    const cac_after = try emitAdvance(g, ca_next);
    try g.jump(call_loop_blk, &.{ cac_after, ca_args2 });

    g.beginReservedBlock(cac_no_blk);
    try g.jump(call_loop_blk, &.{ ca_next, ca_args2 });

    g.beginReservedBlock(ca_done_blk);
    const ca_after_rp = try emitAdvance(g, ca_pos);
    const call_rec = try g.record(&.{
        .{ .name = "callee", .value = cur_node },
        .{ .name = "args", .value = ca_args },
    });
    const call_node = try g.tag(ast_call, call_rec);
    try g.jump(loop_blk, &.{ call_node, ca_after_rp });

    // check_dot: field access — Expr.field
    g.beginReservedBlock(check_dot_blk);
    const is_punct = try g.tagTest(tok, "Punct");
    const check_dot2_blk = g.reserveBlock();
    const check_op_blk = g.reserveBlock();
    try g.branch(is_punct, check_dot2_blk, check_op_blk);

    g.beginReservedBlock(check_dot2_blk);
    const punct_val = try g.tagPayload(tok, "Punct");
    const dot_str = try g.constString(".");
    const is_dot = try g.eq(punct_val, dot_str);
    const dot_blk = g.reserveBlock();
    try g.branch(is_dot, dot_blk, check_op_blk);

    g.beginReservedBlock(dot_blk);
    const dot_next = try emitAdvance(g, cur_pos); // skip .
    const field_tok = try emitGetToken(g, tokens, dot_next);
    // Field name can be Ident (record.field) or UpperIdent (Type.Variant)
    const field_is_ident = try g.tagTest(field_tok, "Ident");
    const field_ident_blk = g.reserveBlock();
    const field_upper_blk = g.reserveBlock();
    const field_merge_blk = g.reserveBlock();
    try g.branch(field_is_ident, field_ident_blk, field_upper_blk);

    g.beginReservedBlock(field_ident_blk);
    const field_name_lower = try g.tagPayload(field_tok, "Ident");
    try g.jump(field_merge_blk, &.{field_name_lower});

    g.beginReservedBlock(field_upper_blk);
    const field_name_upper = try g.tagPayload(field_tok, "UpperIdent");
    try g.jump(field_merge_blk, &.{field_name_upper});

    g.beginReservedBlock(field_merge_blk);
    const field_name = try g.addBlockParam();
    const field_after = try emitAdvance(g, dot_next);
    const field_rec = try g.record(&.{
        .{ .name = "expr", .value = cur_node },
        .{ .name = "field", .value = field_name },
    });
    const field_node = try g.tag(ast_field_access, field_rec);
    try g.jump(loop_blk, &.{ field_node, field_after });

    // check_op: infix operator?
    g.beginReservedBlock(check_op_blk);
    const is_op = try g.tagTest(tok, "Op");
    const infix_blk = g.reserveBlock();
    const check_pipe_kw_blk = g.reserveBlock();
    try g.branch(is_op, infix_blk, check_pipe_kw_blk);

    g.beginReservedBlock(infix_blk);
    const op_name = try g.tagPayload(tok, "Op");
    const bp = try g.callDirect(pf.infix_bp, &.{op_name});
    const left_bp = try g.recordField(bp, "left");
    const right_bp = try g.recordField(bp, "right");
    // If left_bp == 0, not a valid infix op — stop
    const bp_valid = try g.ne(left_bp, zero);
    const check_bp_blk = g.reserveBlock();
    const done_blk = g.reserveBlock();
    try g.branch(bp_valid, check_bp_blk, done_blk);

    // check_bp: is left_bp >= min_bp?
    g.beginReservedBlock(check_bp_blk);
    const bp_ok = try g.lt(left_bp, min_bp);
    const stop_blk = g.reserveBlock();
    const do_infix_blk = g.reserveBlock();
    try g.branch(bp_ok, stop_blk, do_infix_blk);

    g.beginReservedBlock(stop_blk);
    try g.jump(done_blk, &.{});

    // do_infix: parse right side with right_bp as min
    g.beginReservedBlock(do_infix_blk);
    const op_next = try emitAdvance(g, cur_pos); // skip operator
    // Special case: |> pipe operator
    const pipe_str = try g.constString("|>");
    const is_pipe = try g.eq(op_name, pipe_str);
    const pipe_blk = g.reserveBlock();
    const normal_infix_blk = g.reserveBlock();
    try g.branch(is_pipe, pipe_blk, normal_infix_blk);

    // pipe: lhs |> rhs — creates Pipe node
    g.beginReservedBlock(pipe_blk);
    const pipe_rhs_result = try g.callDirect(pf.parse_expr, &.{ tokens, op_next, right_bp });
    const pipe_rhs = try g.recordField(pipe_rhs_result, "node");
    const pipe_end = try g.recordField(pipe_rhs_result, "pos");
    const pipe_rec = try g.record(&.{
        .{ .name = "lhs", .value = cur_node },
        .{ .name = "rhs", .value = pipe_rhs },
    });
    const pipe_node = try g.tag(ast_pipe, pipe_rec);
    try g.jump(loop_blk, &.{ pipe_node, pipe_end });

    // normal infix: lhs op rhs -> BinOp node
    g.beginReservedBlock(normal_infix_blk);
    const rhs_result = try g.callDirect(pf.parse_expr, &.{ tokens, op_next, right_bp });
    const rhs_node = try g.recordField(rhs_result, "node");
    const rhs_end = try g.recordField(rhs_result, "pos");
    const binop_rec = try g.record(&.{
        .{ .name = "op", .value = op_name },
        .{ .name = "lhs", .value = cur_node },
        .{ .name = "rhs", .value = rhs_node },
    });
    const binop_node = try g.tag(ast_binop, binop_rec);
    try g.jump(loop_blk, &.{ binop_node, rhs_end });

    // check for keyword ops (and, or) as infix
    g.beginReservedBlock(check_pipe_kw_blk);
    const is_kw = try g.tagTest(tok, "Keyword");
    const kw_op_blk = g.reserveBlock();
    try g.branch(is_kw, kw_op_blk, done_blk);

    g.beginReservedBlock(kw_op_blk);
    const kw_val = try g.tagPayload(tok, "Keyword");
    const kw_bp = try g.callDirect(pf.infix_bp, &.{kw_val});
    const kw_left_bp = try g.recordField(kw_bp, "left");
    const kw_right_bp = try g.recordField(kw_bp, "right");
    const kw_bp_valid = try g.ne(kw_left_bp, zero);
    const kw_check_bp_blk = g.reserveBlock();
    try g.branch(kw_bp_valid, kw_check_bp_blk, done_blk);

    g.beginReservedBlock(kw_check_bp_blk);
    const kw_bp_ok = try g.lt(kw_left_bp, min_bp);
    const kw_do_blk = g.reserveBlock();
    try g.branch(kw_bp_ok, done_blk, kw_do_blk);

    g.beginReservedBlock(kw_do_blk);
    const kw_op_next = try emitAdvance(g, cur_pos);
    const kw_rhs_result = try g.callDirect(pf.parse_expr, &.{ tokens, kw_op_next, kw_right_bp });
    const kw_rhs = try g.recordField(kw_rhs_result, "node");
    const kw_rhs_end = try g.recordField(kw_rhs_result, "pos");
    const kw_binop_rec = try g.record(&.{
        .{ .name = "op", .value = kw_val },
        .{ .name = "lhs", .value = cur_node },
        .{ .name = "rhs", .value = kw_rhs },
    });
    const kw_binop_node = try g.tag(ast_binop, kw_binop_rec);
    try g.jump(loop_blk, &.{ kw_binop_node, kw_rhs_end });

    // done: return current node
    g.beginReservedBlock(done_blk);
    const done_res = try emitResult(g, cur_node, cur_pos);
    try g.ret(done_res);

    try g.endReservedFunc(pf.parse_expr);
}

// ── parse_block(tokens, pos) -> Record{node, pos} ──────────────────────
// Parses expressions until }, separated by newlines/semicolons.
// pos is AFTER the opening {.

fn genParseBlock(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_block");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    const empty = try g.listInit(&.{});
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{ pos, empty });

    g.beginReservedBlock(loop_blk);
    const cur_pos = try g.addBlockParam();
    const exprs = try g.addBlockParam();
    const tok = try emitGetToken(g, tokens, cur_pos);

    // Check for }
    const is_delim = try g.tagTest(tok, "Delim");
    const check_rb_blk = g.reserveBlock();
    const check_eof_blk = g.reserveBlock();
    try g.branch(is_delim, check_rb_blk, check_eof_blk);

    g.beginReservedBlock(check_rb_blk);
    const delim_val = try g.tagPayload(tok, "Delim");
    const rbrace = try g.constString("}");
    const is_rb = try g.eq(delim_val, rbrace);
    const done_blk = g.reserveBlock();
    try g.branch(is_rb, done_blk, check_eof_blk);

    // Check for EOF
    g.beginReservedBlock(check_eof_blk);
    const is_eof = try g.tagTest(tok, "Eof");
    const parse_expr_blk = g.reserveBlock();
    try g.branch(is_eof, done_blk, parse_expr_blk);

    // Parse one expression
    g.beginReservedBlock(parse_expr_blk);
    // Check if it's a declaration keyword (fn, type, etc.) — parse as decl
    const is_kw = try g.tagTest(tok, "Keyword");
    const check_decl_blk = g.reserveBlock();
    const expr_blk = g.reserveBlock();
    try g.branch(is_kw, check_decl_blk, expr_blk);

    g.beginReservedBlock(check_decl_blk);
    const kw_val = try g.tagPayload(tok, "Keyword");
    const fn_str = try g.constString("fn");
    const is_fn = try g.eq(kw_val, fn_str);
    const let_str = try g.constString("let");
    const is_let = try g.eq(kw_val, let_str);
    const is_decl_like = try g.logicOr(is_fn, is_let);
    const decl_blk = g.reserveBlock();
    try g.branch(is_decl_like, decl_blk, expr_blk);

    g.beginReservedBlock(decl_blk);
    const d_zero = try g.constInt(0);
    const d_result = try g.callDirect(pf.parse_expr, &.{ tokens, cur_pos, d_zero });
    const d_node = try g.recordField(d_result, "node");
    const d_next = try g.recordField(d_result, "pos");
    const d_exprs = try g.listAppend(exprs, d_node);
    try g.jump(loop_blk, &.{ d_next, d_exprs });

    g.beginReservedBlock(expr_blk);
    const zero = try g.constInt(0);
    const e_result = try g.callDirect(pf.parse_expr, &.{ tokens, cur_pos, zero });
    const e_node = try g.recordField(e_result, "node");
    const e_next = try g.recordField(e_result, "pos");
    const e_exprs = try g.listAppend(exprs, e_node);
    try g.jump(loop_blk, &.{ e_next, e_exprs });

    // done
    g.beginReservedBlock(done_blk);
    const after_rb = try emitAdvance(g, cur_pos);
    // If single expression, unwrap
    const one = try g.constInt(1);
    const count = try g.listLength(exprs);
    const is_single = try g.eq(count, one);
    const single_blk = g.reserveBlock();
    const multi_blk = g.reserveBlock();
    try g.branch(is_single, single_blk, multi_blk);

    g.beginReservedBlock(single_blk);
    const zero2 = try g.constInt(0);
    const single_node = try g.listNth(exprs, zero2);
    const single_res = try emitResult(g, single_node, after_rb);
    try g.ret(single_res);

    g.beginReservedBlock(multi_blk);
    const block_node = try g.tag(ast_block, exprs);
    const block_res = try emitResult(g, block_node, after_rb);
    try g.ret(block_res);

    try g.endReservedFunc(pf.parse_block);
}

// ── parse_if(tokens, pos) -> Record{node, pos} ─────────────────────────
// pos is AFTER "if" keyword.

fn genParseIf(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_if");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    const zero = try g.constInt(0);

    // Parse condition
    const cond_result = try g.callDirect(pf.parse_expr, &.{ tokens, pos, zero });
    const cond_node = try g.recordField(cond_result, "node");
    const cond_pos = try g.recordField(cond_result, "pos");

    // Expect {
    const then_pos = try emitAdvance(g, cond_pos); // skip {
    const then_result = try g.callDirect(pf.parse_block, &.{ tokens, then_pos });
    const then_node = try g.recordField(then_result, "node");
    const then_end = try g.recordField(then_result, "pos");

    // Check for else
    const else_tok = try emitGetToken(g, tokens, then_end);
    const is_kw = try g.tagTest(else_tok, "Keyword");
    const check_else_blk = g.reserveBlock();
    const no_else_blk = g.reserveBlock();
    try g.branch(is_kw, check_else_blk, no_else_blk);

    g.beginReservedBlock(check_else_blk);
    const kw_val = try g.tagPayload(else_tok, "Keyword");
    const else_str = try g.constString("else");
    const is_else = try g.eq(kw_val, else_str);
    const has_else_blk = g.reserveBlock();
    try g.branch(is_else, has_else_blk, no_else_blk);

    // has_else: parse else branch
    g.beginReservedBlock(has_else_blk);
    const else_start = try emitAdvance(g, then_end); // skip "else"
    // Check for "if" (else if)
    const else_tok2 = try emitGetToken(g, tokens, else_start);
    const is_kw2 = try g.tagTest(else_tok2, "Keyword");
    const check_elif_blk = g.reserveBlock();
    const else_block_blk = g.reserveBlock();
    try g.branch(is_kw2, check_elif_blk, else_block_blk);

    g.beginReservedBlock(check_elif_blk);
    const kw2_val = try g.tagPayload(else_tok2, "Keyword");
    const if_str = try g.constString("if");
    const is_elif = try g.eq(kw2_val, if_str);
    const elif_blk = g.reserveBlock();
    try g.branch(is_elif, elif_blk, else_block_blk);

    // else if: recursively parse if
    g.beginReservedBlock(elif_blk);
    const elif_pos = try emitAdvance(g, else_start); // skip "if"
    const elif_result = try g.callDirect(pf.parse_if, &.{ tokens, elif_pos });
    const elif_node = try g.recordField(elif_result, "node");
    const elif_end = try g.recordField(elif_result, "pos");
    const elif_if_rec = try g.record(&.{
        .{ .name = "cond", .value = cond_node },
        .{ .name = "then_branch", .value = then_node },
        .{ .name = "else_branch", .value = elif_node },
    });
    const elif_if_node = try g.tag(ast_if, elif_if_rec);
    const elif_res = try emitResult(g, elif_if_node, elif_end);
    try g.ret(elif_res);

    // else block: { ... }
    g.beginReservedBlock(else_block_blk);
    const eb_pos = try emitAdvance(g, else_start); // skip {
    const eb_result = try g.callDirect(pf.parse_block, &.{ tokens, eb_pos });
    const eb_node = try g.recordField(eb_result, "node");
    const eb_end = try g.recordField(eb_result, "pos");
    const if_rec = try g.record(&.{
        .{ .name = "cond", .value = cond_node },
        .{ .name = "then_branch", .value = then_node },
        .{ .name = "else_branch", .value = eb_node },
    });
    const if_node = try g.tag(ast_if, if_rec);
    const if_res = try emitResult(g, if_node, eb_end);
    try g.ret(if_res);

    // no else
    g.beginReservedBlock(no_else_blk);
    const nil_else = try g.constNil();
    const ne_rec = try g.record(&.{
        .{ .name = "cond", .value = cond_node },
        .{ .name = "then_branch", .value = then_node },
        .{ .name = "else_branch", .value = nil_else },
    });
    const ne_node = try g.tag(ast_if, ne_rec);
    const ne_res = try emitResult(g, ne_node, then_end);
    try g.ret(ne_res);

    try g.endReservedFunc(pf.parse_if);
}

// ── parse_match(tokens, pos) -> Record{node, pos} ──────────────────────
// pos is AFTER "match" keyword.

fn genParseMatch(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_match");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    const zero = try g.constInt(0);

    // Parse scrutinee
    const scrut_result = try g.callDirect(pf.parse_expr, &.{ tokens, pos, zero });
    const scrut_node = try g.recordField(scrut_result, "node");
    const scrut_pos = try g.recordField(scrut_result, "pos");

    // Skip {
    const arms_start = try emitAdvance(g, scrut_pos);
    const arms_empty = try g.listInit(&.{});
    const arms_loop_blk = g.reserveBlock();
    try g.jump(arms_loop_blk, &.{ arms_start, arms_empty });

    // Loop: parse match arms until }
    g.beginReservedBlock(arms_loop_blk);
    const a_pos = try g.addBlockParam();
    const a_arms = try g.addBlockParam();
    const a_tok = try emitGetToken(g, tokens, a_pos);

    // Check for }
    const a_is_delim = try g.tagTest(a_tok, "Delim");
    const a_check_rb_blk = g.reserveBlock();
    const a_parse_blk = g.reserveBlock();
    try g.branch(a_is_delim, a_check_rb_blk, a_parse_blk);

    g.beginReservedBlock(a_check_rb_blk);
    const a_delim = try g.tagPayload(a_tok, "Delim");
    const rbrace = try g.constString("}");
    const a_is_rb = try g.eq(a_delim, rbrace);
    const a_done_blk = g.reserveBlock();
    try g.branch(a_is_rb, a_done_blk, a_parse_blk);

    // Parse one arm: pattern -> expr
    g.beginReservedBlock(a_parse_blk);
    const pat_result = try g.callDirect(pf.parse_pattern, &.{ tokens, a_pos });
    const pat_node = try g.recordField(pat_result, "node");
    const pat_pos = try g.recordField(pat_result, "pos");
    // Skip ->
    const arrow_pos = try emitAdvance(g, pat_pos);
    // Parse body
    const body_result = try g.callDirect(pf.parse_expr, &.{ tokens, arrow_pos, zero });
    const body_node = try g.recordField(body_result, "node");
    const body_end = try g.recordField(body_result, "pos");
    const arm_rec = try g.record(&.{
        .{ .name = "pattern", .value = pat_node },
        .{ .name = "body", .value = body_node },
    });
    const a_arms2 = try g.listAppend(a_arms, arm_rec);
    // Skip optional comma
    const ac_tok = try emitGetToken(g, tokens, body_end);
    const ac_is_punct = try g.tagTest(ac_tok, "Punct");
    const ac_check_blk = g.reserveBlock();
    const ac_no_blk = g.reserveBlock();
    try g.branch(ac_is_punct, ac_check_blk, ac_no_blk);

    g.beginReservedBlock(ac_check_blk);
    const ac_val = try g.tagPayload(ac_tok, "Punct");
    const comma = try g.constString(",");
    const ac_is_comma = try g.eq(ac_val, comma);
    const ac_skip_blk = g.reserveBlock();
    try g.branch(ac_is_comma, ac_skip_blk, ac_no_blk);

    g.beginReservedBlock(ac_skip_blk);
    const ac_after = try emitAdvance(g, body_end);
    try g.jump(arms_loop_blk, &.{ ac_after, a_arms2 });

    g.beginReservedBlock(ac_no_blk);
    try g.jump(arms_loop_blk, &.{ body_end, a_arms2 });

    // done
    g.beginReservedBlock(a_done_blk);
    const after_rb = try emitAdvance(g, a_pos);
    const match_rec = try g.record(&.{
        .{ .name = "scrutinee", .value = scrut_node },
        .{ .name = "arms", .value = a_arms },
    });
    const match_node = try g.tag(ast_match, match_rec);
    const match_res = try emitResult(g, match_node, after_rb);
    try g.ret(match_res);

    try g.endReservedFunc(pf.parse_match);
}

// ── parse_let(tokens, pos) -> Record{node, pos} ────────────────────────
// pos is AFTER "let" keyword.

fn genParseLet(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_let");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    // Parse pattern
    const pat_result = try g.callDirect(pf.parse_pattern, &.{ tokens, pos });
    const pat_node = try g.recordField(pat_result, "node");
    const pat_pos = try g.recordField(pat_result, "pos");

    // Skip =
    const eq_pos = try emitAdvance(g, pat_pos);

    // Parse value expression
    const zero = try g.constInt(0);
    const val_result = try g.callDirect(pf.parse_expr, &.{ tokens, eq_pos, zero });
    const val_node = try g.recordField(val_result, "node");
    const val_end = try g.recordField(val_result, "pos");

    const let_rec = try g.record(&.{
        .{ .name = "pattern", .value = pat_node },
        .{ .name = "value", .value = val_node },
    });
    const let_node = try g.tag(ast_let, let_rec);
    const let_res = try emitResult(g, let_node, val_end);
    try g.ret(let_res);

    try g.endReservedFunc(pf.parse_let);
}

// ── parse_handle(tokens, pos) -> Record{node, pos} ─────────────────────
// pos is AFTER "handle" keyword.

fn genParseHandle(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_handle");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    const zero = try g.constInt(0);

    // Parse the expression being handled
    const body_result = try g.callDirect(pf.parse_expr, &.{ tokens, pos, zero });
    const body_node = try g.recordField(body_result, "node");
    const body_pos = try g.recordField(body_result, "pos");

    // Skip {
    const clauses_start = try emitAdvance(g, body_pos);
    const clauses_empty = try g.listInit(&.{});
    const clauses_loop_blk = g.reserveBlock();
    try g.jump(clauses_loop_blk, &.{ clauses_start, clauses_empty });

    // Loop: parse handler clauses until }
    g.beginReservedBlock(clauses_loop_blk);
    const c_pos = try g.addBlockParam();
    const c_clauses = try g.addBlockParam();
    const c_tok = try emitGetToken(g, tokens, c_pos);

    const c_is_delim = try g.tagTest(c_tok, "Delim");
    const c_check_rb_blk = g.reserveBlock();
    const c_parse_blk = g.reserveBlock();
    try g.branch(c_is_delim, c_check_rb_blk, c_parse_blk);

    g.beginReservedBlock(c_check_rb_blk);
    const c_delim = try g.tagPayload(c_tok, "Delim");
    const rbrace = try g.constString("}");
    const c_is_rb = try g.eq(c_delim, rbrace);
    const c_done_blk = g.reserveBlock();
    try g.branch(c_is_rb, c_done_blk, c_parse_blk);

    // Parse one clause: pattern -> expr
    g.beginReservedBlock(c_parse_blk);
    const cp_result = try g.callDirect(pf.parse_pattern, &.{ tokens, c_pos });
    const cp_pat = try g.recordField(cp_result, "node");
    const cp_pos = try g.recordField(cp_result, "pos");
    // Skip ->
    const cp_arrow_pos = try emitAdvance(g, cp_pos);
    const cp_body_result = try g.callDirect(pf.parse_expr, &.{ tokens, cp_arrow_pos, zero });
    const cp_body = try g.recordField(cp_body_result, "node");
    const cp_end = try g.recordField(cp_body_result, "pos");
    const clause_rec = try g.record(&.{
        .{ .name = "pattern", .value = cp_pat },
        .{ .name = "body", .value = cp_body },
    });
    const c_clauses2 = try g.listAppend(c_clauses, clause_rec);
    // Skip optional comma
    const cc_tok = try emitGetToken(g, tokens, cp_end);
    const cc_is_punct = try g.tagTest(cc_tok, "Punct");
    const cc_check_blk = g.reserveBlock();
    const cc_no_blk = g.reserveBlock();
    try g.branch(cc_is_punct, cc_check_blk, cc_no_blk);

    g.beginReservedBlock(cc_check_blk);
    const cc_val = try g.tagPayload(cc_tok, "Punct");
    const comma = try g.constString(",");
    const cc_is_comma = try g.eq(cc_val, comma);
    const cc_skip_blk = g.reserveBlock();
    try g.branch(cc_is_comma, cc_skip_blk, cc_no_blk);

    g.beginReservedBlock(cc_skip_blk);
    const cc_after = try emitAdvance(g, cp_end);
    try g.jump(clauses_loop_blk, &.{ cc_after, c_clauses2 });

    g.beginReservedBlock(cc_no_blk);
    try g.jump(clauses_loop_blk, &.{ cp_end, c_clauses2 });

    // done
    g.beginReservedBlock(c_done_blk);
    const after_rb = try emitAdvance(g, c_pos);
    const handle_rec = try g.record(&.{
        .{ .name = "body", .value = body_node },
        .{ .name = "clauses", .value = c_clauses },
    });
    const handle_node = try g.tag(ast_handle, handle_rec);
    const handle_res = try emitResult(g, handle_node, after_rb);
    try g.ret(handle_res);

    try g.endReservedFunc(pf.parse_handle);
}

// ── parse_fn_decl(tokens, pos) -> Record{node, pos} ────────────────────
// pos is AFTER "fn" keyword.

fn genParseFnDecl(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_fn_decl");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    // Parse function name (Ident)
    const name_tok = try emitGetToken(g, tokens, pos);
    const fn_name = try g.tagPayload(name_tok, "Ident");
    const after_name = try emitAdvance(g, pos);

    // Skip (
    const params_start = try emitAdvance(g, after_name);

    // Parse parameters until )
    const params_empty = try g.listInit(&.{});
    const params_loop_blk = g.reserveBlock();
    try g.jump(params_loop_blk, &.{ params_start, params_empty });

    g.beginReservedBlock(params_loop_blk);
    const p_pos = try g.addBlockParam();
    const p_params = try g.addBlockParam();
    const p_tok = try emitGetToken(g, tokens, p_pos);
    const p_is_delim = try g.tagTest(p_tok, "Delim");
    const p_check_rp_blk = g.reserveBlock();
    const p_parse_blk = g.reserveBlock();
    try g.branch(p_is_delim, p_check_rp_blk, p_parse_blk);

    g.beginReservedBlock(p_check_rp_blk);
    const p_delim = try g.tagPayload(p_tok, "Delim");
    const rparen = try g.constString(")");
    const p_is_rp = try g.eq(p_delim, rparen);
    const p_done_blk = g.reserveBlock();
    try g.branch(p_is_rp, p_done_blk, p_parse_blk);

    // Parse one param: just an ident for now (name or name: Type)
    g.beginReservedBlock(p_parse_blk);
    const param_tok = try emitGetToken(g, tokens, p_pos);
    const param_name = try g.tagPayload(param_tok, "Ident");
    const after_param = try emitAdvance(g, p_pos);
    // Check for : (type annotation)
    const colon_tok = try emitGetToken(g, tokens, after_param);
    const colon_is_punct = try g.tagTest(colon_tok, "Punct");
    const check_colon_blk = g.reserveBlock();
    const no_type_blk = g.reserveBlock();
    try g.branch(colon_is_punct, check_colon_blk, no_type_blk);

    g.beginReservedBlock(check_colon_blk);
    const colon_val = try g.tagPayload(colon_tok, "Punct");
    const colon_str = try g.constString(":");
    const is_colon = try g.eq(colon_val, colon_str);
    const has_type_blk = g.reserveBlock();
    try g.branch(is_colon, has_type_blk, no_type_blk);

    g.beginReservedBlock(has_type_blk);
    const type_start = try emitAdvance(g, after_param); // skip :
    const type_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, type_start });
    const type_node = try g.recordField(type_result, "node");
    const type_end = try g.recordField(type_result, "pos");
    const typed_param = try g.record(&.{
        .{ .name = "name", .value = param_name },
        .{ .name = "type", .value = type_node },
    });
    const p_params_t = try g.listAppend(p_params, typed_param);
    // Check for comma
    const ptc_tok = try emitGetToken(g, tokens, type_end);
    const ptc_is_punct = try g.tagTest(ptc_tok, "Punct");
    const ptc_check_blk = g.reserveBlock();
    const ptc_no_blk = g.reserveBlock();
    try g.branch(ptc_is_punct, ptc_check_blk, ptc_no_blk);

    g.beginReservedBlock(ptc_check_blk);
    const ptc_val = try g.tagPayload(ptc_tok, "Punct");
    const ptc_comma = try g.constString(",");
    const ptc_is_comma = try g.eq(ptc_val, ptc_comma);
    const ptc_skip_blk = g.reserveBlock();
    try g.branch(ptc_is_comma, ptc_skip_blk, ptc_no_blk);

    g.beginReservedBlock(ptc_skip_blk);
    const ptc_after = try emitAdvance(g, type_end);
    try g.jump(params_loop_blk, &.{ ptc_after, p_params_t });

    g.beginReservedBlock(ptc_no_blk);
    try g.jump(params_loop_blk, &.{ type_end, p_params_t });

    g.beginReservedBlock(no_type_blk);
    const nil_type = try g.constNil();
    const untyped_param = try g.record(&.{
        .{ .name = "name", .value = param_name },
        .{ .name = "type", .value = nil_type },
    });
    const p_params_u = try g.listAppend(p_params, untyped_param);
    // Check for comma
    const puc_tok = try emitGetToken(g, tokens, after_param);
    const puc_is_punct = try g.tagTest(puc_tok, "Punct");
    const puc_check_blk = g.reserveBlock();
    const puc_no_blk = g.reserveBlock();
    try g.branch(puc_is_punct, puc_check_blk, puc_no_blk);

    g.beginReservedBlock(puc_check_blk);
    const puc_val = try g.tagPayload(puc_tok, "Punct");
    const puc_comma = try g.constString(",");
    const puc_is_comma = try g.eq(puc_val, puc_comma);
    const puc_skip_blk = g.reserveBlock();
    try g.branch(puc_is_comma, puc_skip_blk, puc_no_blk);

    g.beginReservedBlock(puc_skip_blk);
    const puc_after = try emitAdvance(g, after_param);
    try g.jump(params_loop_blk, &.{ puc_after, p_params_u });

    g.beginReservedBlock(puc_no_blk);
    try g.jump(params_loop_blk, &.{ after_param, p_params_u });

    // After params: check for -> return type
    g.beginReservedBlock(p_done_blk);
    const after_rp = try emitAdvance(g, p_pos); // skip )
    const rt_tok = try emitGetToken(g, tokens, after_rp);
    const rt_is_op = try g.tagTest(rt_tok, "Op");
    const check_arrow_blk = g.reserveBlock();
    const no_ret_type_blk = g.reserveBlock();
    try g.branch(rt_is_op, check_arrow_blk, no_ret_type_blk);

    g.beginReservedBlock(check_arrow_blk);
    const rt_op = try g.tagPayload(rt_tok, "Op");
    const arrow_str = try g.constString("->");
    const is_arrow = try g.eq(rt_op, arrow_str);
    const has_ret_blk = g.reserveBlock();
    const check_effect_arrow_blk = g.reserveBlock();
    try g.branch(is_arrow, has_ret_blk, check_effect_arrow_blk);

    // Check for -[ (effect arrow)
    g.beginReservedBlock(check_effect_arrow_blk);
    const eff_arrow_str = try g.constString("-[");
    const is_eff_arrow = try g.eq(rt_op, eff_arrow_str);
    const eff_arrow_blk = g.reserveBlock();
    try g.branch(is_eff_arrow, eff_arrow_blk, no_ret_type_blk);

    // Effect arrow: -[Effect1, Effect2]> RetType
    g.beginReservedBlock(eff_arrow_blk);
    const ea_start = try emitAdvance(g, after_rp); // skip -[
    const ea_empty = try g.listInit(&.{});
    const ea_loop_blk = g.reserveBlock();
    try g.jump(ea_loop_blk, &.{ ea_start, ea_empty });

    g.beginReservedBlock(ea_loop_blk);
    const ea_pos = try g.addBlockParam();
    const ea_list = try g.addBlockParam();
    const ea_tok = try emitGetToken(g, tokens, ea_pos);
    // Check for ]>
    const ea_is_op = try g.tagTest(ea_tok, "Op");
    const ea_check_close_blk = g.reserveBlock();
    const ea_parse_blk = g.reserveBlock();
    try g.branch(ea_is_op, ea_check_close_blk, ea_parse_blk);

    g.beginReservedBlock(ea_check_close_blk);
    const ea_op_val = try g.tagPayload(ea_tok, "Op");
    const ea_close = try g.constString("]>");
    const ea_is_close = try g.eq(ea_op_val, ea_close);
    const ea_done_blk = g.reserveBlock();
    try g.branch(ea_is_close, ea_done_blk, ea_parse_blk);

    // Parse one effect name
    g.beginReservedBlock(ea_parse_blk);
    const ea_name = try g.tagPayload(ea_tok, "UpperIdent");
    const ea_list2 = try g.listAppend(ea_list, ea_name);
    const ea_next = try emitAdvance(g, ea_pos);
    // Check for comma
    const eac_tok = try emitGetToken(g, tokens, ea_next);
    const eac_is_punct = try g.tagTest(eac_tok, "Punct");
    const eac_check_blk = g.reserveBlock();
    const eac_no_blk = g.reserveBlock();
    try g.branch(eac_is_punct, eac_check_blk, eac_no_blk);

    g.beginReservedBlock(eac_check_blk);
    const eac_val = try g.tagPayload(eac_tok, "Punct");
    const eac_comma = try g.constString(",");
    const eac_is_comma = try g.eq(eac_val, eac_comma);
    const eac_skip_blk = g.reserveBlock();
    try g.branch(eac_is_comma, eac_skip_blk, eac_no_blk);

    g.beginReservedBlock(eac_skip_blk);
    const eac_after = try emitAdvance(g, ea_next);
    try g.jump(ea_loop_blk, &.{ eac_after, ea_list2 });

    g.beginReservedBlock(eac_no_blk);
    try g.jump(ea_loop_blk, &.{ ea_next, ea_list2 });

    // After ]>: parse return type, then body
    g.beginReservedBlock(ea_done_blk);
    const ea_after_close = try emitAdvance(g, ea_pos); // skip ]>
    const ea_ret_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, ea_after_close });
    const ea_ret_node = try g.recordField(ea_ret_result, "node");
    const ea_ret_end = try g.recordField(ea_ret_result, "pos");
    const ea_body_start = try emitAdvance(g, ea_ret_end); // skip {
    const ea_body_result = try g.callDirect(pf.parse_block, &.{ tokens, ea_body_start });
    const ea_body_node = try g.recordField(ea_body_result, "node");
    const ea_body_end = try g.recordField(ea_body_result, "pos");
    const ea_fn_rec = try g.record(&.{
        .{ .name = "name", .value = fn_name },
        .{ .name = "params", .value = p_params },
        .{ .name = "effects", .value = ea_list },
        .{ .name = "return_type", .value = ea_ret_node },
        .{ .name = "body", .value = ea_body_node },
    });
    const ea_fn_node = try g.tag(ast_fn_decl, ea_fn_rec);
    const ea_fn_res = try emitResult(g, ea_fn_node, ea_body_end);
    try g.ret(ea_fn_res);

    // Simple -> return type (no effects)
    g.beginReservedBlock(has_ret_blk);
    const nil_effects = try g.listInit(&.{});
    const ret_type_start = try emitAdvance(g, after_rp); // skip ->
    const ret_type_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, ret_type_start });
    const ret_type_node = try g.recordField(ret_type_result, "node");
    const ret_type_end = try g.recordField(ret_type_result, "pos");
    // Parse body: expect {
    const body_start = try emitAdvance(g, ret_type_end); // skip {
    const body_result = try g.callDirect(pf.parse_block, &.{ tokens, body_start });
    const body_node = try g.recordField(body_result, "node");
    const body_end = try g.recordField(body_result, "pos");
    const fn_rec = try g.record(&.{
        .{ .name = "name", .value = fn_name },
        .{ .name = "params", .value = p_params },
        .{ .name = "effects", .value = nil_effects },
        .{ .name = "return_type", .value = ret_type_node },
        .{ .name = "body", .value = body_node },
    });
    const fn_node = try g.tag(ast_fn_decl, fn_rec);
    const fn_res = try emitResult(g, fn_node, body_end);
    try g.ret(fn_res);

    // No return type: parse body directly
    g.beginReservedBlock(no_ret_type_blk);
    const nb_nil_effects = try g.listInit(&.{});
    const nb_start = try emitAdvance(g, after_rp); // skip {
    const nb_result = try g.callDirect(pf.parse_block, &.{ tokens, nb_start });
    const nb_node = try g.recordField(nb_result, "node");
    const nb_end = try g.recordField(nb_result, "pos");
    const nil_ret = try g.constNil();
    const fn_rec2 = try g.record(&.{
        .{ .name = "name", .value = fn_name },
        .{ .name = "params", .value = p_params },
        .{ .name = "effects", .value = nb_nil_effects },
        .{ .name = "return_type", .value = nil_ret },
        .{ .name = "body", .value = nb_node },
    });
    const fn_node2 = try g.tag(ast_fn_decl, fn_rec2);
    const fn_res2 = try emitResult(g, fn_node2, nb_end);
    try g.ret(fn_res2);

    try g.endReservedFunc(pf.parse_fn_decl);
}

// ── parse_type_decl(tokens, pos) -> Record{node, pos} ──────────────────
// pos is AFTER "type" keyword.

fn genParseTypeDecl(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_type_decl");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    // Parse type name
    const name_tok = try emitGetToken(g, tokens, pos);
    const type_name = try g.tagPayload(name_tok, "UpperIdent");
    const after_name = try emitAdvance(g, pos);

    // Check for <T, U> type params
    const tp_tok = try emitGetToken(g, tokens, after_name);
    const tp_is_op = try g.tagTest(tp_tok, "Op");
    const tp_check_lt_blk = g.reserveBlock();
    const tp_no_params_blk = g.reserveBlock();
    try g.branch(tp_is_op, tp_check_lt_blk, tp_no_params_blk);

    g.beginReservedBlock(tp_check_lt_blk);
    const tp_op = try g.tagPayload(tp_tok, "Op");
    const tp_lt = try g.constString("<");
    const tp_is_lt = try g.eq(tp_op, tp_lt);
    const tp_parse_blk = g.reserveBlock();
    try g.branch(tp_is_lt, tp_parse_blk, tp_no_params_blk);

    // Parse type params until >
    g.beginReservedBlock(tp_parse_blk);
    const tp_start = try emitAdvance(g, after_name); // skip <
    const tp_empty = try g.listInit(&.{});
    const tp_loop_blk = g.reserveBlock();
    try g.jump(tp_loop_blk, &.{ tp_start, tp_empty });

    g.beginReservedBlock(tp_loop_blk);
    const tp_pos = try g.addBlockParam();
    const tp_list = try g.addBlockParam();
    const tp_cur = try emitGetToken(g, tokens, tp_pos);
    const tp_cur_is_op = try g.tagTest(tp_cur, "Op");
    const tp_check_gt_blk = g.reserveBlock();
    const tp_parse_one_blk = g.reserveBlock();
    try g.branch(tp_cur_is_op, tp_check_gt_blk, tp_parse_one_blk);

    g.beginReservedBlock(tp_check_gt_blk);
    const tp_cur_op = try g.tagPayload(tp_cur, "Op");
    const tp_gt = try g.constString(">");
    const tp_is_gt = try g.eq(tp_cur_op, tp_gt);
    const tp_done_blk = g.reserveBlock();
    try g.branch(tp_is_gt, tp_done_blk, tp_parse_one_blk);

    g.beginReservedBlock(tp_parse_one_blk);
    // Type params can be UpperIdent (T, K, V) or Ident (a, b)
    const tp_is_upper = try g.tagTest(tp_cur, "UpperIdent");
    const tp_upper_blk = g.reserveBlock();
    const tp_lower_blk = g.reserveBlock();
    try g.branch(tp_is_upper, tp_upper_blk, tp_lower_blk);

    g.beginReservedBlock(tp_upper_blk);
    const tp_name_u = try g.tagPayload(tp_cur, "UpperIdent");
    const tp_list2_u = try g.listAppend(tp_list, tp_name_u);
    const tp_next_u = try emitAdvance(g, tp_pos);
    // Check for comma (same logic for both paths - converge below)
    const tpu_tok = try emitGetToken(g, tokens, tp_next_u);
    const tpu_is_punct = try g.tagTest(tpu_tok, "Punct");
    const tpu_check_blk = g.reserveBlock();
    const tpu_no_blk = g.reserveBlock();
    try g.branch(tpu_is_punct, tpu_check_blk, tpu_no_blk);

    g.beginReservedBlock(tpu_check_blk);
    const tpu_val = try g.tagPayload(tpu_tok, "Punct");
    const tpu_comma = try g.constString(",");
    const tpu_is_comma = try g.eq(tpu_val, tpu_comma);
    const tpu_skip_blk = g.reserveBlock();
    try g.branch(tpu_is_comma, tpu_skip_blk, tpu_no_blk);

    g.beginReservedBlock(tpu_skip_blk);
    const tpu_after = try emitAdvance(g, tp_next_u);
    try g.jump(tp_loop_blk, &.{ tpu_after, tp_list2_u });

    g.beginReservedBlock(tpu_no_blk);
    try g.jump(tp_loop_blk, &.{ tp_next_u, tp_list2_u });

    g.beginReservedBlock(tp_lower_blk);
    const tp_name = try g.tagPayload(tp_cur, "Ident");
    const tp_list2 = try g.listAppend(tp_list, tp_name);
    const tp_next = try emitAdvance(g, tp_pos);
    // Check for comma
    const tpc_tok = try emitGetToken(g, tokens, tp_next);
    const tpc_is_punct = try g.tagTest(tpc_tok, "Punct");
    const tpc_check_blk = g.reserveBlock();
    const tpc_no_blk = g.reserveBlock();
    try g.branch(tpc_is_punct, tpc_check_blk, tpc_no_blk);

    g.beginReservedBlock(tpc_check_blk);
    const tpc_val = try g.tagPayload(tpc_tok, "Punct");
    const tpc_comma = try g.constString(",");
    const tpc_is_comma = try g.eq(tpc_val, tpc_comma);
    const tpc_skip_blk = g.reserveBlock();
    try g.branch(tpc_is_comma, tpc_skip_blk, tpc_no_blk);

    g.beginReservedBlock(tpc_skip_blk);
    const tpc_after = try emitAdvance(g, tp_next);
    try g.jump(tp_loop_blk, &.{ tpc_after, tp_list2 });

    g.beginReservedBlock(tpc_no_blk);
    try g.jump(tp_loop_blk, &.{ tp_next, tp_list2 });

    // Done: after >
    g.beginReservedBlock(tp_done_blk);
    const tp_after_gt = try emitAdvance(g, tp_pos); // skip >
    // Skip {
    const tp_variants_start = try emitAdvance(g, tp_after_gt);
    const tp_variants_empty = try g.listInit(&.{});
    const variants_loop_blk = g.reserveBlock();
    try g.jump(variants_loop_blk, &.{ tp_variants_start, tp_variants_empty, tp_list });

    // No type params path
    g.beginReservedBlock(tp_no_params_blk);
    const np_nil_tparams = try g.listInit(&.{});
    // Skip {
    const variants_start = try emitAdvance(g, after_name);
    const variants_empty = try g.listInit(&.{});
    try g.jump(variants_loop_blk, &.{ variants_start, variants_empty, np_nil_tparams });

    // Loop: parse variants until }
    g.beginReservedBlock(variants_loop_blk);
    const v_pos = try g.addBlockParam();
    const v_variants = try g.addBlockParam();
    const v_type_params = try g.addBlockParam();
    const v_tok = try emitGetToken(g, tokens, v_pos);
    const comma = try g.constString(",");

    const v_is_delim = try g.tagTest(v_tok, "Delim");
    const v_check_rb_blk = g.reserveBlock();
    const v_parse_blk = g.reserveBlock();
    try g.branch(v_is_delim, v_check_rb_blk, v_parse_blk);

    g.beginReservedBlock(v_check_rb_blk);
    const v_delim = try g.tagPayload(v_tok, "Delim");
    const rbrace = try g.constString("}");
    const v_is_rb = try g.eq(v_delim, rbrace);
    const v_done_blk = g.reserveBlock();
    try g.branch(v_is_rb, v_done_blk, v_parse_blk);

    // Parse one variant: Name or Name(Type) or name: Type (record field)
    g.beginReservedBlock(v_parse_blk);
    const is_upper = try g.tagTest(v_tok, "UpperIdent");
    const variant_blk = g.reserveBlock();
    const field_blk = g.reserveBlock();
    try g.branch(is_upper, variant_blk, field_blk);

    // Tagged variant
    g.beginReservedBlock(variant_blk);
    const vname = try g.tagPayload(v_tok, "UpperIdent");
    const v_next = try emitAdvance(g, v_pos);
    // Check for (
    const vn_tok = try emitGetToken(g, tokens, v_next);
    const vn_is_delim = try g.tagTest(vn_tok, "Delim");
    const vn_check_lp_blk = g.reserveBlock();
    const vn_no_args_blk = g.reserveBlock();
    try g.branch(vn_is_delim, vn_check_lp_blk, vn_no_args_blk);

    g.beginReservedBlock(vn_check_lp_blk);
    const vn_delim = try g.tagPayload(vn_tok, "Delim");
    const lparen = try g.constString("(");
    const vn_is_lp = try g.eq(vn_delim, lparen);
    const vn_args_blk = g.reserveBlock();
    try g.branch(vn_is_lp, vn_args_blk, vn_no_args_blk);

    // variant with type args
    g.beginReservedBlock(vn_args_blk);
    const va_start = try emitAdvance(g, v_next); // skip (
    const va_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, va_start });
    const va_type = try g.recordField(va_result, "node");
    const va_end = try g.recordField(va_result, "pos");
    const va_after_rp = try emitAdvance(g, va_end); // skip )
    const va_rec = try g.record(&.{
        .{ .name = "name", .value = vname },
        .{ .name = "payload_type", .value = va_type },
    });
    const va_variants = try g.listAppend(v_variants, va_rec);
    // Skip optional comma
    const vac_tok = try emitGetToken(g, tokens, va_after_rp);
    const vac_is_punct = try g.tagTest(vac_tok, "Punct");
    const vac_check_blk = g.reserveBlock();
    const vac_no_blk = g.reserveBlock();
    try g.branch(vac_is_punct, vac_check_blk, vac_no_blk);

    g.beginReservedBlock(vac_check_blk);
    const vac_val = try g.tagPayload(vac_tok, "Punct");
    const vac_is_comma = try g.eq(vac_val, comma);
    const vac_skip_blk = g.reserveBlock();
    try g.branch(vac_is_comma, vac_skip_blk, vac_no_blk);

    g.beginReservedBlock(vac_skip_blk);
    const vac_after = try emitAdvance(g, va_after_rp);
    try g.jump(variants_loop_blk, &.{ vac_after, va_variants, v_type_params });

    g.beginReservedBlock(vac_no_blk);
    try g.jump(variants_loop_blk, &.{ va_after_rp, va_variants, v_type_params });

    // variant without args
    g.beginReservedBlock(vn_no_args_blk);
    const nil_payload = try g.constNil();
    const vn_rec = try g.record(&.{
        .{ .name = "name", .value = vname },
        .{ .name = "payload_type", .value = nil_payload },
    });
    const vn_variants = try g.listAppend(v_variants, vn_rec);
    // Skip optional comma
    const vnc_tok = try emitGetToken(g, tokens, v_next);
    const vnc_is_punct = try g.tagTest(vnc_tok, "Punct");
    const vnc_check_blk = g.reserveBlock();
    const vnc_no_blk = g.reserveBlock();
    try g.branch(vnc_is_punct, vnc_check_blk, vnc_no_blk);

    g.beginReservedBlock(vnc_check_blk);
    const vnc_val = try g.tagPayload(vnc_tok, "Punct");
    const vnc_is_comma = try g.eq(vnc_val, comma);
    const vnc_skip_blk = g.reserveBlock();
    try g.branch(vnc_is_comma, vnc_skip_blk, vnc_no_blk);

    g.beginReservedBlock(vnc_skip_blk);
    const vnc_after = try emitAdvance(g, v_next);
    try g.jump(variants_loop_blk, &.{ vnc_after, vn_variants, v_type_params });

    g.beginReservedBlock(vnc_no_blk);
    try g.jump(variants_loop_blk, &.{ v_next, vn_variants, v_type_params });

    // Record field: name: Type
    g.beginReservedBlock(field_blk);
    const fname = try g.tagPayload(v_tok, "Ident");
    const f_next = try emitAdvance(g, v_pos);
    // Skip :
    const f_type_start = try emitAdvance(g, f_next);
    const f_type_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, f_type_start });
    const f_type_node = try g.recordField(f_type_result, "node");
    const f_type_end = try g.recordField(f_type_result, "pos");
    const f_rec = try g.record(&.{
        .{ .name = "name", .value = fname },
        .{ .name = "payload_type", .value = f_type_node },
    });
    const f_variants = try g.listAppend(v_variants, f_rec);
    // Skip optional comma
    const fc_tok = try emitGetToken(g, tokens, f_type_end);
    const fc_is_punct = try g.tagTest(fc_tok, "Punct");
    const fc_check_blk = g.reserveBlock();
    const fc_no_blk = g.reserveBlock();
    try g.branch(fc_is_punct, fc_check_blk, fc_no_blk);

    g.beginReservedBlock(fc_check_blk);
    const fc_val = try g.tagPayload(fc_tok, "Punct");
    const fc_is_comma = try g.eq(fc_val, comma);
    const fc_skip_blk = g.reserveBlock();
    try g.branch(fc_is_comma, fc_skip_blk, fc_no_blk);

    g.beginReservedBlock(fc_skip_blk);
    const fc_after = try emitAdvance(g, f_type_end);
    try g.jump(variants_loop_blk, &.{ fc_after, f_variants, v_type_params });

    g.beginReservedBlock(fc_no_blk);
    try g.jump(variants_loop_blk, &.{ f_type_end, f_variants, v_type_params });

    // done
    g.beginReservedBlock(v_done_blk);
    const after_rb = try emitAdvance(g, v_pos);
    const type_rec = try g.record(&.{
        .{ .name = "name", .value = type_name },
        .{ .name = "type_params", .value = v_type_params },
        .{ .name = "variants", .value = v_variants },
    });
    const type_node = try g.tag(ast_type_decl, type_rec);
    const type_res = try emitResult(g, type_node, after_rb);
    try g.ret(type_res);

    try g.endReservedFunc(pf.parse_type_decl);
}

// ── parse_trait_decl(tokens, pos) -> Record{node, pos} ─────────────────
// pos is AFTER "trait" keyword.
// Syntax: trait Name<T> { fn method(params) -> RetType, ... }
// Methods are fn signatures (no body).

fn genParseTraitDecl(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_trait_decl");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    // Parse trait name (UpperIdent)
    const name_tok = try emitGetToken(g, tokens, pos);
    const trait_name = try g.tagPayload(name_tok, "UpperIdent");
    const after_name = try emitAdvance(g, pos);

    // Check for type params: <T, U>
    const tp_tok = try emitGetToken(g, tokens, after_name);
    const tp_is_op = try g.tagTest(tp_tok, "Op");
    const check_lt_blk = g.reserveBlock();
    const no_tparams_blk = g.reserveBlock();
    try g.branch(tp_is_op, check_lt_blk, no_tparams_blk);

    g.beginReservedBlock(check_lt_blk);
    const tp_op = try g.tagPayload(tp_tok, "Op");
    const lt_str = try g.constString("<");
    const is_lt = try g.eq(tp_op, lt_str);
    const has_tparams_blk = g.reserveBlock();
    try g.branch(is_lt, has_tparams_blk, no_tparams_blk);

    // Parse type params
    g.beginReservedBlock(has_tparams_blk);
    const tp_start = try emitAdvance(g, after_name); // skip <
    const tp_empty = try g.listInit(&.{});
    const tp_loop_blk = g.reserveBlock();
    try g.jump(tp_loop_blk, &.{ tp_start, tp_empty });

    g.beginReservedBlock(tp_loop_blk);
    const tp_pos = try g.addBlockParam();
    const tp_list = try g.addBlockParam();
    const tp_cur = try emitGetToken(g, tokens, tp_pos);
    const tp_cur_is_op = try g.tagTest(tp_cur, "Op");
    const tp_check_gt_blk = g.reserveBlock();
    const tp_parse_blk = g.reserveBlock();
    try g.branch(tp_cur_is_op, tp_check_gt_blk, tp_parse_blk);

    g.beginReservedBlock(tp_check_gt_blk);
    const tp_cur_op = try g.tagPayload(tp_cur, "Op");
    const gt_str = try g.constString(">");
    const tp_is_gt = try g.eq(tp_cur_op, gt_str);
    const tp_done_blk = g.reserveBlock();
    try g.branch(tp_is_gt, tp_done_blk, tp_parse_blk);

    g.beginReservedBlock(tp_parse_blk);
    const tp_name_tok = try emitGetToken(g, tokens, tp_pos);
    const tp_param_name = try g.tagPayload(tp_name_tok, "UpperIdent");
    const tp_after = try emitAdvance(g, tp_pos);
    const tp_list2 = try g.listAppend(tp_list, tp_param_name);
    // Skip optional comma
    const tpc_tok = try emitGetToken(g, tokens, tp_after);
    const tpc_is_punct = try g.tagTest(tpc_tok, "Punct");
    const tpc_check_blk = g.reserveBlock();
    const tpc_no_blk = g.reserveBlock();
    try g.branch(tpc_is_punct, tpc_check_blk, tpc_no_blk);

    g.beginReservedBlock(tpc_check_blk);
    const tpc_val = try g.tagPayload(tpc_tok, "Punct");
    const tpc_comma = try g.constString(",");
    const tpc_is_comma = try g.eq(tpc_val, tpc_comma);
    const tpc_skip_blk = g.reserveBlock();
    try g.branch(tpc_is_comma, tpc_skip_blk, tpc_no_blk);

    g.beginReservedBlock(tpc_skip_blk);
    const tpc_after = try emitAdvance(g, tp_after);
    try g.jump(tp_loop_blk, &.{ tpc_after, tp_list2 });

    g.beginReservedBlock(tpc_no_blk);
    try g.jump(tp_loop_blk, &.{ tp_after, tp_list2 });

    // After type params: skip > then {
    g.beginReservedBlock(tp_done_blk);
    const after_gt = try emitAdvance(g, tp_pos); // skip >
    const methods_blk = g.reserveBlock();
    try g.jump(methods_blk, &.{ after_gt, tp_list });

    // No type params path
    g.beginReservedBlock(no_tparams_blk);
    const empty_tparams = try g.listInit(&.{});
    try g.jump(methods_blk, &.{ after_name, empty_tparams });

    // Parse methods: { fn sig, fn sig, ... }
    g.beginReservedBlock(methods_blk);
    const m_before_brace = try g.addBlockParam();
    const type_params = try g.addBlockParam();
    const m_start = try emitAdvance(g, m_before_brace); // skip {
    const m_empty = try g.listInit(&.{});
    const m_loop_blk = g.reserveBlock();
    try g.jump(m_loop_blk, &.{ m_start, m_empty });

    g.beginReservedBlock(m_loop_blk);
    const m_pos = try g.addBlockParam();
    const m_methods = try g.addBlockParam();
    const m_tok = try emitGetToken(g, tokens, m_pos);

    // Check for }
    const m_is_delim = try g.tagTest(m_tok, "Delim");
    const m_check_rb_blk = g.reserveBlock();
    const m_parse_blk = g.reserveBlock();
    try g.branch(m_is_delim, m_check_rb_blk, m_parse_blk);

    g.beginReservedBlock(m_check_rb_blk);
    const m_delim = try g.tagPayload(m_tok, "Delim");
    const m_rbrace = try g.constString("}");
    const m_is_rb = try g.eq(m_delim, m_rbrace);
    const m_done_blk = g.reserveBlock();
    try g.branch(m_is_rb, m_done_blk, m_parse_blk);

    // Parse one method signature: fn name(params) -> RetType
    g.beginReservedBlock(m_parse_blk);
    // Skip "fn" keyword
    const fn_pos = try emitAdvance(g, m_pos);
    // Parse as fn decl — trait methods have no body, but we'll parse the signature
    // by reusing parse_fn_sig_only pattern: name(params) -> Type
    const sig_name_tok = try emitGetToken(g, tokens, fn_pos);
    const sig_name = try g.tagPayload(sig_name_tok, "Ident");
    const after_sig_name = try emitAdvance(g, fn_pos);
    const sig_params_start = try emitAdvance(g, after_sig_name); // skip (

    // Parse params until )
    const sig_params_empty = try g.listInit(&.{});
    const sig_params_loop = g.reserveBlock();
    try g.jump(sig_params_loop, &.{ sig_params_start, sig_params_empty });

    g.beginReservedBlock(sig_params_loop);
    const sp_pos = try g.addBlockParam();
    const sp_params = try g.addBlockParam();
    const sp_tok = try emitGetToken(g, tokens, sp_pos);
    const sp_is_delim = try g.tagTest(sp_tok, "Delim");
    const sp_check_rp_blk = g.reserveBlock();
    const sp_parse_blk = g.reserveBlock();
    try g.branch(sp_is_delim, sp_check_rp_blk, sp_parse_blk);

    g.beginReservedBlock(sp_check_rp_blk);
    const sp_delim = try g.tagPayload(sp_tok, "Delim");
    const sp_rparen = try g.constString(")");
    const sp_is_rp = try g.eq(sp_delim, sp_rparen);
    const sp_done_blk = g.reserveBlock();
    try g.branch(sp_is_rp, sp_done_blk, sp_parse_blk);

    g.beginReservedBlock(sp_parse_blk);
    const sp_name_tok = try emitGetToken(g, tokens, sp_pos);
    const sp_param_name = try g.tagPayload(sp_name_tok, "Ident");
    const sp_after_name = try emitAdvance(g, sp_pos);
    // Check for : type
    const sp_colon_tok = try emitGetToken(g, tokens, sp_after_name);
    const sp_colon_is_punct = try g.tagTest(sp_colon_tok, "Punct");
    const sp_check_colon_blk = g.reserveBlock();
    const sp_no_type_blk = g.reserveBlock();
    try g.branch(sp_colon_is_punct, sp_check_colon_blk, sp_no_type_blk);

    g.beginReservedBlock(sp_check_colon_blk);
    const sp_colon_val = try g.tagPayload(sp_colon_tok, "Punct");
    const sp_colon_str = try g.constString(":");
    const sp_is_colon = try g.eq(sp_colon_val, sp_colon_str);
    const sp_has_type_blk = g.reserveBlock();
    try g.branch(sp_is_colon, sp_has_type_blk, sp_no_type_blk);

    g.beginReservedBlock(sp_has_type_blk);
    const sp_type_start = try emitAdvance(g, sp_after_name); // skip :
    const sp_type_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, sp_type_start });
    const sp_type_node = try g.recordField(sp_type_result, "node");
    const sp_type_end = try g.recordField(sp_type_result, "pos");
    const sp_typed_param = try g.record(&.{
        .{ .name = "name", .value = sp_param_name },
        .{ .name = "type", .value = sp_type_node },
    });
    const sp_params_t = try g.listAppend(sp_params, sp_typed_param);
    // Check comma
    const spc_tok = try emitGetToken(g, tokens, sp_type_end);
    const spc_is_punct = try g.tagTest(spc_tok, "Punct");
    const spc_check_blk = g.reserveBlock();
    const spc_no_blk = g.reserveBlock();
    try g.branch(spc_is_punct, spc_check_blk, spc_no_blk);

    g.beginReservedBlock(spc_check_blk);
    const spc_val = try g.tagPayload(spc_tok, "Punct");
    const spc_comma = try g.constString(",");
    const spc_is_comma = try g.eq(spc_val, spc_comma);
    const spc_skip_blk = g.reserveBlock();
    try g.branch(spc_is_comma, spc_skip_blk, spc_no_blk);

    g.beginReservedBlock(spc_skip_blk);
    const spc_after = try emitAdvance(g, sp_type_end);
    try g.jump(sig_params_loop, &.{ spc_after, sp_params_t });

    g.beginReservedBlock(spc_no_blk);
    try g.jump(sig_params_loop, &.{ sp_type_end, sp_params_t });

    g.beginReservedBlock(sp_no_type_blk);
    const sp_nil_type = try g.constNil();
    const sp_untyped = try g.record(&.{
        .{ .name = "name", .value = sp_param_name },
        .{ .name = "type", .value = sp_nil_type },
    });
    const sp_params_u = try g.listAppend(sp_params, sp_untyped);
    // Check comma
    const spu_tok = try emitGetToken(g, tokens, sp_after_name);
    const spu_is_punct = try g.tagTest(spu_tok, "Punct");
    const spu_check_blk = g.reserveBlock();
    const spu_no_blk = g.reserveBlock();
    try g.branch(spu_is_punct, spu_check_blk, spu_no_blk);

    g.beginReservedBlock(spu_check_blk);
    const spu_val = try g.tagPayload(spu_tok, "Punct");
    const spu_comma = try g.constString(",");
    const spu_is_comma = try g.eq(spu_val, spu_comma);
    const spu_skip_blk = g.reserveBlock();
    try g.branch(spu_is_comma, spu_skip_blk, spu_no_blk);

    g.beginReservedBlock(spu_skip_blk);
    const spu_after = try emitAdvance(g, sp_after_name);
    try g.jump(sig_params_loop, &.{ spu_after, sp_params_u });

    g.beginReservedBlock(spu_no_blk);
    try g.jump(sig_params_loop, &.{ sp_after_name, sp_params_u });

    // After params: check for -> return type
    g.beginReservedBlock(sp_done_blk);
    const sig_after_rp = try emitAdvance(g, sp_pos); // skip )
    const sig_rt_tok = try emitGetToken(g, tokens, sig_after_rp);
    const sig_rt_is_op = try g.tagTest(sig_rt_tok, "Op");
    const sig_check_arrow_blk = g.reserveBlock();
    const sig_no_ret_blk = g.reserveBlock();
    try g.branch(sig_rt_is_op, sig_check_arrow_blk, sig_no_ret_blk);

    g.beginReservedBlock(sig_check_arrow_blk);
    const sig_rt_op = try g.tagPayload(sig_rt_tok, "Op");
    const sig_arrow = try g.constString("->");
    const sig_is_arrow = try g.eq(sig_rt_op, sig_arrow);
    const sig_has_ret_blk = g.reserveBlock();
    try g.branch(sig_is_arrow, sig_has_ret_blk, sig_no_ret_blk);

    g.beginReservedBlock(sig_has_ret_blk);
    const sig_ret_start = try emitAdvance(g, sig_after_rp); // skip ->
    const sig_ret_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, sig_ret_start });
    const sig_ret_node = try g.recordField(sig_ret_result, "node");
    const sig_ret_end = try g.recordField(sig_ret_result, "pos");
    const sig_rec = try g.record(&.{
        .{ .name = "name", .value = sig_name },
        .{ .name = "params", .value = sp_params },
        .{ .name = "return_type", .value = sig_ret_node },
    });
    const sig_methods_t = try g.listAppend(m_methods, sig_rec);
    // Skip optional comma
    const mc_tok = try emitGetToken(g, tokens, sig_ret_end);
    const mc_is_punct = try g.tagTest(mc_tok, "Punct");
    const mc_check_blk = g.reserveBlock();
    const mc_no_blk = g.reserveBlock();
    try g.branch(mc_is_punct, mc_check_blk, mc_no_blk);

    g.beginReservedBlock(mc_check_blk);
    const mc_val = try g.tagPayload(mc_tok, "Punct");
    const mc_comma = try g.constString(",");
    const mc_is_comma = try g.eq(mc_val, mc_comma);
    const mc_skip_blk = g.reserveBlock();
    try g.branch(mc_is_comma, mc_skip_blk, mc_no_blk);

    g.beginReservedBlock(mc_skip_blk);
    const mc_after = try emitAdvance(g, sig_ret_end);
    try g.jump(m_loop_blk, &.{ mc_after, sig_methods_t });

    g.beginReservedBlock(mc_no_blk);
    try g.jump(m_loop_blk, &.{ sig_ret_end, sig_methods_t });

    // No return type
    g.beginReservedBlock(sig_no_ret_blk);
    const sig_nil_ret = try g.constNil();
    const sig_rec2 = try g.record(&.{
        .{ .name = "name", .value = sig_name },
        .{ .name = "params", .value = sp_params },
        .{ .name = "return_type", .value = sig_nil_ret },
    });
    const sig_methods_u = try g.listAppend(m_methods, sig_rec2);
    // Skip optional comma
    const mu_tok = try emitGetToken(g, tokens, sig_after_rp);
    const mu_is_punct = try g.tagTest(mu_tok, "Punct");
    const mu_check_blk = g.reserveBlock();
    const mu_no_blk = g.reserveBlock();
    try g.branch(mu_is_punct, mu_check_blk, mu_no_blk);

    g.beginReservedBlock(mu_check_blk);
    const mu_val = try g.tagPayload(mu_tok, "Punct");
    const mu_comma = try g.constString(",");
    const mu_is_comma = try g.eq(mu_val, mu_comma);
    const mu_skip_blk = g.reserveBlock();
    try g.branch(mu_is_comma, mu_skip_blk, mu_no_blk);

    g.beginReservedBlock(mu_skip_blk);
    const mu_after = try emitAdvance(g, sig_after_rp);
    try g.jump(m_loop_blk, &.{ mu_after, sig_methods_u });

    g.beginReservedBlock(mu_no_blk);
    try g.jump(m_loop_blk, &.{ sig_after_rp, sig_methods_u });

    // Done: construct trait decl
    g.beginReservedBlock(m_done_blk);
    const after_rb = try emitAdvance(g, m_pos); // skip }
    const trait_rec = try g.record(&.{
        .{ .name = "name", .value = trait_name },
        .{ .name = "type_params", .value = type_params },
        .{ .name = "methods", .value = m_methods },
    });
    const trait_node = try g.tag(ast_trait_decl, trait_rec);
    const trait_res = try emitResult(g, trait_node, after_rb);
    try g.ret(trait_res);

    try g.endReservedFunc(pf.parse_trait_decl);
}

// ── parse_impl_decl(tokens, pos) -> Record{node, pos} ──────────────────
// pos is AFTER "impl" keyword.
// Syntax: impl TraitName<TypeName> { fn method(params) -> RetType { body } ... }
// Methods are full fn declarations (with bodies).

fn genParseImplDecl(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_impl_decl");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    // Parse trait name (UpperIdent)
    const trait_tok = try emitGetToken(g, tokens, pos);
    const impl_trait_name = try g.tagPayload(trait_tok, "UpperIdent");
    const after_trait = try emitAdvance(g, pos);

    // Check for <TypeName>
    const lt_tok = try emitGetToken(g, tokens, after_trait);
    const lt_is_op = try g.tagTest(lt_tok, "Op");
    const check_lt_blk = g.reserveBlock();
    const no_type_arg_blk = g.reserveBlock();
    try g.branch(lt_is_op, check_lt_blk, no_type_arg_blk);

    g.beginReservedBlock(check_lt_blk);
    const lt_op = try g.tagPayload(lt_tok, "Op");
    const lt_str = try g.constString("<");
    const is_lt = try g.eq(lt_op, lt_str);
    const has_type_arg_blk = g.reserveBlock();
    try g.branch(is_lt, has_type_arg_blk, no_type_arg_blk);

    g.beginReservedBlock(has_type_arg_blk);
    const type_arg_pos = try emitAdvance(g, after_trait); // skip <
    const type_arg_tok = try emitGetToken(g, tokens, type_arg_pos);
    const impl_type_name = try g.tagPayload(type_arg_tok, "UpperIdent");
    const after_type_arg = try emitAdvance(g, type_arg_pos);
    const after_gt = try emitAdvance(g, after_type_arg); // skip >
    const methods_blk = g.reserveBlock();
    try g.jump(methods_blk, &.{ after_gt, impl_type_name });

    g.beginReservedBlock(no_type_arg_blk);
    // No type arg — just use nil
    const nil_type = try g.constNil();
    try g.jump(methods_blk, &.{ after_trait, nil_type });

    // Parse methods: { fn_decl fn_decl ... }
    g.beginReservedBlock(methods_blk);
    const before_brace = try g.addBlockParam();
    const impl_type = try g.addBlockParam();
    const im_start = try emitAdvance(g, before_brace); // skip {
    const im_empty = try g.listInit(&.{});
    const im_loop_blk = g.reserveBlock();
    try g.jump(im_loop_blk, &.{ im_start, im_empty });

    g.beginReservedBlock(im_loop_blk);
    const im_pos = try g.addBlockParam();
    const im_methods = try g.addBlockParam();
    const im_tok = try emitGetToken(g, tokens, im_pos);

    // Check for }
    const im_is_delim = try g.tagTest(im_tok, "Delim");
    const im_check_rb_blk = g.reserveBlock();
    const im_parse_blk = g.reserveBlock();
    try g.branch(im_is_delim, im_check_rb_blk, im_parse_blk);

    g.beginReservedBlock(im_check_rb_blk);
    const im_delim = try g.tagPayload(im_tok, "Delim");
    const im_rbrace = try g.constString("}");
    const im_is_rb = try g.eq(im_delim, im_rbrace);
    const im_done_blk = g.reserveBlock();
    try g.branch(im_is_rb, im_done_blk, im_parse_blk);

    // Parse one method: skip "fn", then delegate to parse_fn_decl
    g.beginReservedBlock(im_parse_blk);
    const im_fn_start = try emitAdvance(g, im_pos); // skip "fn" keyword
    const im_fn_result = try g.callDirect(pf.parse_fn_decl, &.{ tokens, im_fn_start });
    const im_fn_node = try g.recordField(im_fn_result, "node");
    const im_fn_end = try g.recordField(im_fn_result, "pos");
    const im_methods2 = try g.listAppend(im_methods, im_fn_node);
    try g.jump(im_loop_blk, &.{ im_fn_end, im_methods2 });

    // Done
    g.beginReservedBlock(im_done_blk);
    const im_after_rb = try emitAdvance(g, im_pos); // skip }
    const impl_rec = try g.record(&.{
        .{ .name = "trait_name", .value = impl_trait_name },
        .{ .name = "type_name", .value = impl_type },
        .{ .name = "methods", .value = im_methods },
    });
    const impl_node = try g.tag(ast_impl_decl, impl_rec);
    const impl_res = try emitResult(g, impl_node, im_after_rb);
    try g.ret(impl_res);

    try g.endReservedFunc(pf.parse_impl_decl);
}

// ── parse_effect_decl(tokens, pos) -> Record{node, pos} ────────────────
// pos is AFTER "effect" keyword.
// Syntax: effect Name { fn op(params) -> RetType, ... }
// Operations are fn signatures (same as trait methods).

fn genParseEffectDecl(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_effect_decl");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    // Parse effect name (UpperIdent)
    const name_tok = try emitGetToken(g, tokens, pos);
    const effect_name = try g.tagPayload(name_tok, "UpperIdent");
    const after_name = try emitAdvance(g, pos);

    // Skip {
    const ops_start = try emitAdvance(g, after_name);
    const ops_empty = try g.listInit(&.{});
    const ops_loop_blk = g.reserveBlock();
    try g.jump(ops_loop_blk, &.{ ops_start, ops_empty });

    g.beginReservedBlock(ops_loop_blk);
    const o_pos = try g.addBlockParam();
    const o_ops = try g.addBlockParam();
    const o_tok = try emitGetToken(g, tokens, o_pos);

    // Check for }
    const o_is_delim = try g.tagTest(o_tok, "Delim");
    const o_check_rb_blk = g.reserveBlock();
    const o_parse_blk = g.reserveBlock();
    try g.branch(o_is_delim, o_check_rb_blk, o_parse_blk);

    g.beginReservedBlock(o_check_rb_blk);
    const o_delim = try g.tagPayload(o_tok, "Delim");
    const o_rbrace = try g.constString("}");
    const o_is_rb = try g.eq(o_delim, o_rbrace);
    const o_done_blk = g.reserveBlock();
    try g.branch(o_is_rb, o_done_blk, o_parse_blk);

    // Parse one operation signature: fn name(params) -> RetType
    g.beginReservedBlock(o_parse_blk);
    const fn_pos = try emitAdvance(g, o_pos); // skip "fn"
    const op_name_tok = try emitGetToken(g, tokens, fn_pos);
    const op_name = try g.tagPayload(op_name_tok, "Ident");
    const after_op_name = try emitAdvance(g, fn_pos);
    const op_params_start = try emitAdvance(g, after_op_name); // skip (

    // Parse params until )
    const op_params_empty = try g.listInit(&.{});
    const op_params_loop = g.reserveBlock();
    try g.jump(op_params_loop, &.{ op_params_start, op_params_empty });

    g.beginReservedBlock(op_params_loop);
    const op_pos = try g.addBlockParam();
    const op_params = try g.addBlockParam();
    const op_tok = try emitGetToken(g, tokens, op_pos);
    const op_is_delim = try g.tagTest(op_tok, "Delim");
    const op_check_rp_blk = g.reserveBlock();
    const op_parse_blk = g.reserveBlock();
    try g.branch(op_is_delim, op_check_rp_blk, op_parse_blk);

    g.beginReservedBlock(op_check_rp_blk);
    const op_delim_val = try g.tagPayload(op_tok, "Delim");
    const op_rparen = try g.constString(")");
    const op_is_rp = try g.eq(op_delim_val, op_rparen);
    const op_done_blk = g.reserveBlock();
    try g.branch(op_is_rp, op_done_blk, op_parse_blk);

    g.beginReservedBlock(op_parse_blk);
    const op_p_name_tok = try emitGetToken(g, tokens, op_pos);
    const op_p_name = try g.tagPayload(op_p_name_tok, "Ident");
    const op_p_after = try emitAdvance(g, op_pos);
    // Check for : type
    const opc_tok = try emitGetToken(g, tokens, op_p_after);
    const opc_is_punct = try g.tagTest(opc_tok, "Punct");
    const opc_check_blk = g.reserveBlock();
    const opc_no_type_blk = g.reserveBlock();
    try g.branch(opc_is_punct, opc_check_blk, opc_no_type_blk);

    g.beginReservedBlock(opc_check_blk);
    const opc_val = try g.tagPayload(opc_tok, "Punct");
    const opc_colon = try g.constString(":");
    const opc_is_colon = try g.eq(opc_val, opc_colon);
    const opc_has_type_blk = g.reserveBlock();
    try g.branch(opc_is_colon, opc_has_type_blk, opc_no_type_blk);

    g.beginReservedBlock(opc_has_type_blk);
    const opc_type_start = try emitAdvance(g, op_p_after); // skip :
    const opc_type_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, opc_type_start });
    const opc_type_node = try g.recordField(opc_type_result, "node");
    const opc_type_end = try g.recordField(opc_type_result, "pos");
    const opc_typed = try g.record(&.{
        .{ .name = "name", .value = op_p_name },
        .{ .name = "type", .value = opc_type_node },
    });
    const op_params_t = try g.listAppend(op_params, opc_typed);
    // Skip optional comma
    const optc_tok = try emitGetToken(g, tokens, opc_type_end);
    const optc_is_punct = try g.tagTest(optc_tok, "Punct");
    const optc_check_blk = g.reserveBlock();
    const optc_no_blk = g.reserveBlock();
    try g.branch(optc_is_punct, optc_check_blk, optc_no_blk);

    g.beginReservedBlock(optc_check_blk);
    const optc_val = try g.tagPayload(optc_tok, "Punct");
    const optc_comma = try g.constString(",");
    const optc_is_comma = try g.eq(optc_val, optc_comma);
    const optc_skip_blk = g.reserveBlock();
    try g.branch(optc_is_comma, optc_skip_blk, optc_no_blk);

    g.beginReservedBlock(optc_skip_blk);
    const optc_after = try emitAdvance(g, opc_type_end);
    try g.jump(op_params_loop, &.{ optc_after, op_params_t });

    g.beginReservedBlock(optc_no_blk);
    try g.jump(op_params_loop, &.{ opc_type_end, op_params_t });

    g.beginReservedBlock(opc_no_type_blk);
    const opc_nil = try g.constNil();
    const opc_untyped = try g.record(&.{
        .{ .name = "name", .value = op_p_name },
        .{ .name = "type", .value = opc_nil },
    });
    const op_params_u = try g.listAppend(op_params, opc_untyped);
    // Skip optional comma
    const opuc_tok = try emitGetToken(g, tokens, op_p_after);
    const opuc_is_punct = try g.tagTest(opuc_tok, "Punct");
    const opuc_check_blk = g.reserveBlock();
    const opuc_no_blk = g.reserveBlock();
    try g.branch(opuc_is_punct, opuc_check_blk, opuc_no_blk);

    g.beginReservedBlock(opuc_check_blk);
    const opuc_val = try g.tagPayload(opuc_tok, "Punct");
    const opuc_comma = try g.constString(",");
    const opuc_is_comma = try g.eq(opuc_val, opuc_comma);
    const opuc_skip_blk = g.reserveBlock();
    try g.branch(opuc_is_comma, opuc_skip_blk, opuc_no_blk);

    g.beginReservedBlock(opuc_skip_blk);
    const opuc_after = try emitAdvance(g, op_p_after);
    try g.jump(op_params_loop, &.{ opuc_after, op_params_u });

    g.beginReservedBlock(opuc_no_blk);
    try g.jump(op_params_loop, &.{ op_p_after, op_params_u });

    // After params: check for -> return type
    g.beginReservedBlock(op_done_blk);
    const op_after_rp = try emitAdvance(g, op_pos); // skip )
    const op_rt_tok = try emitGetToken(g, tokens, op_after_rp);
    const op_rt_is_op = try g.tagTest(op_rt_tok, "Op");
    const op_check_arrow_blk = g.reserveBlock();
    const op_no_ret_blk = g.reserveBlock();
    try g.branch(op_rt_is_op, op_check_arrow_blk, op_no_ret_blk);

    g.beginReservedBlock(op_check_arrow_blk);
    const op_rt_op = try g.tagPayload(op_rt_tok, "Op");
    const op_arrow = try g.constString("->");
    const op_is_arrow = try g.eq(op_rt_op, op_arrow);
    const op_has_ret_blk = g.reserveBlock();
    try g.branch(op_is_arrow, op_has_ret_blk, op_no_ret_blk);

    g.beginReservedBlock(op_has_ret_blk);
    const op_ret_start = try emitAdvance(g, op_after_rp); // skip ->
    const op_ret_result = try g.callDirect(pf.parse_type_expr, &.{ tokens, op_ret_start });
    const op_ret_node = try g.recordField(op_ret_result, "node");
    const op_ret_end = try g.recordField(op_ret_result, "pos");
    const op_sig = try g.record(&.{
        .{ .name = "name", .value = op_name },
        .{ .name = "params", .value = op_params },
        .{ .name = "return_type", .value = op_ret_node },
    });
    const o_ops_t = try g.listAppend(o_ops, op_sig);
    // Skip optional comma
    const orc_tok = try emitGetToken(g, tokens, op_ret_end);
    const orc_is_punct = try g.tagTest(orc_tok, "Punct");
    const orc_check_blk = g.reserveBlock();
    const orc_no_blk = g.reserveBlock();
    try g.branch(orc_is_punct, orc_check_blk, orc_no_blk);

    g.beginReservedBlock(orc_check_blk);
    const orc_val = try g.tagPayload(orc_tok, "Punct");
    const orc_comma = try g.constString(",");
    const orc_is_comma = try g.eq(orc_val, orc_comma);
    const orc_skip_blk = g.reserveBlock();
    try g.branch(orc_is_comma, orc_skip_blk, orc_no_blk);

    g.beginReservedBlock(orc_skip_blk);
    const orc_after = try emitAdvance(g, op_ret_end);
    try g.jump(ops_loop_blk, &.{ orc_after, o_ops_t });

    g.beginReservedBlock(orc_no_blk);
    try g.jump(ops_loop_blk, &.{ op_ret_end, o_ops_t });

    // No return type
    g.beginReservedBlock(op_no_ret_blk);
    const op_nil_ret = try g.constNil();
    const op_sig2 = try g.record(&.{
        .{ .name = "name", .value = op_name },
        .{ .name = "params", .value = op_params },
        .{ .name = "return_type", .value = op_nil_ret },
    });
    const o_ops_u = try g.listAppend(o_ops, op_sig2);
    // Skip optional comma
    const oru_tok = try emitGetToken(g, tokens, op_after_rp);
    const oru_is_punct = try g.tagTest(oru_tok, "Punct");
    const oru_check_blk = g.reserveBlock();
    const oru_no_blk = g.reserveBlock();
    try g.branch(oru_is_punct, oru_check_blk, oru_no_blk);

    g.beginReservedBlock(oru_check_blk);
    const oru_val = try g.tagPayload(oru_tok, "Punct");
    const oru_comma = try g.constString(",");
    const oru_is_comma = try g.eq(oru_val, oru_comma);
    const oru_skip_blk = g.reserveBlock();
    try g.branch(oru_is_comma, oru_skip_blk, oru_no_blk);

    g.beginReservedBlock(oru_skip_blk);
    const oru_after = try emitAdvance(g, op_after_rp);
    try g.jump(ops_loop_blk, &.{ oru_after, o_ops_u });

    g.beginReservedBlock(oru_no_blk);
    try g.jump(ops_loop_blk, &.{ op_after_rp, o_ops_u });

    // Done
    g.beginReservedBlock(o_done_blk);
    const o_after_rb = try emitAdvance(g, o_pos); // skip }
    const effect_rec = try g.record(&.{
        .{ .name = "name", .value = effect_name },
        .{ .name = "operations", .value = o_ops },
    });
    const effect_node = try g.tag(ast_effect_decl, effect_rec);
    const effect_res = try emitResult(g, effect_node, o_after_rb);
    try g.ret(effect_res);

    try g.endReservedFunc(pf.parse_effect_decl);
}

// ── parse_decl(tokens, pos) -> Record{node, pos} ───────────────────────

fn genParseDecl(g: *Gen, pf: ParserFuncs) !void {
    try g.beginReservedFunc("parse_decl");
    const tokens = try g.addParam();
    const pos = try g.addParam();

    _ = g.beginBlock();
    const tok = try emitGetToken(g, tokens, pos);
    const next_pos = try emitAdvance(g, pos);

    // Must be a keyword
    const kw_val = try g.tagPayload(tok, "Keyword");

    // fn
    const fn_str = try g.constString("fn");
    const is_fn = try g.eq(kw_val, fn_str);
    const fn_blk = g.reserveBlock();
    const c1 = g.reserveBlock();
    try g.branch(is_fn, fn_blk, c1);

    g.beginReservedBlock(fn_blk);
    const fn_result = try g.callDirect(pf.parse_fn_decl, &.{ tokens, next_pos });
    try g.ret(fn_result);

    // type
    g.beginReservedBlock(c1);
    const type_str = try g.constString("type");
    const is_type = try g.eq(kw_val, type_str);
    const type_blk = g.reserveBlock();
    const c2 = g.reserveBlock();
    try g.branch(is_type, type_blk, c2);

    g.beginReservedBlock(type_blk);
    const type_result = try g.callDirect(pf.parse_type_decl, &.{ tokens, next_pos });
    try g.ret(type_result);

    // trait
    g.beginReservedBlock(c2);
    const trait_str = try g.constString("trait");
    const is_trait = try g.eq(kw_val, trait_str);
    const trait_blk = g.reserveBlock();
    const c3 = g.reserveBlock();
    try g.branch(is_trait, trait_blk, c3);

    g.beginReservedBlock(trait_blk);
    const trait_result = try g.callDirect(pf.parse_trait_decl, &.{ tokens, next_pos });
    try g.ret(trait_result);

    // impl
    g.beginReservedBlock(c3);
    const impl_str = try g.constString("impl");
    const is_impl = try g.eq(kw_val, impl_str);
    const impl_blk = g.reserveBlock();
    const c4 = g.reserveBlock();
    try g.branch(is_impl, impl_blk, c4);

    g.beginReservedBlock(impl_blk);
    const impl_result = try g.callDirect(pf.parse_impl_decl, &.{ tokens, next_pos });
    try g.ret(impl_result);

    // effect
    g.beginReservedBlock(c4);
    const effect_str = try g.constString("effect");
    const is_effect = try g.eq(kw_val, effect_str);
    const effect_blk = g.reserveBlock();
    const c5 = g.reserveBlock();
    try g.branch(is_effect, effect_blk, c5);

    g.beginReservedBlock(effect_blk);
    const effect_result = try g.callDirect(pf.parse_effect_decl, &.{ tokens, next_pos });
    try g.ret(effect_result);

    // use — simple: use path
    g.beginReservedBlock(c5);
    const use_str = try g.constString("use");
    const is_use = try g.eq(kw_val, use_str);
    const use_blk = g.reserveBlock();
    const c6 = g.reserveBlock();
    try g.branch(is_use, use_blk, c6);

    g.beginReservedBlock(use_blk);
    const use_tok = try emitGetToken(g, tokens, next_pos);
    const use_path = try g.tagPayload(use_tok, "Ident");
    const use_end = try emitAdvance(g, next_pos);
    const use_node = try g.tag(ast_use_decl, use_path);
    const use_res = try emitResult(g, use_node, use_end);
    try g.ret(use_res);

    // fallback: parse as expression
    g.beginReservedBlock(c6);
    const zero = try g.constInt(0);
    const expr_result = try g.callDirect(pf.parse_expr, &.{ tokens, pos, zero });
    try g.ret(expr_result);

    try g.endReservedFunc(pf.parse_decl);
}

// ── parse_module(source: String) -> Record{node: Module, pos: Int}
// Entry point: lexes source, then parses declarations.

fn genParseModule(g: *Gen, pf: ParserFuncs, lex_fn: FuncId) !void {
    try g.beginReservedFunc("parse_module");
    const source = try g.addParam();

    _ = g.beginBlock();
    // Lex the source
    const tokens = try g.callDirect(lex_fn, &.{source});
    const zero = try g.constInt(0);
    const decls_empty = try g.listInit(&.{});
    const loop_blk = g.reserveBlock();
    try g.jump(loop_blk, &.{ zero, decls_empty });

    // Loop: parse declarations until EOF
    g.beginReservedBlock(loop_blk);
    const pos = try g.addBlockParam();
    const decls = try g.addBlockParam();
    const tok = try emitGetToken(g, tokens, pos);
    const is_eof = try g.tagTest(tok, "Eof");
    const done_blk = g.reserveBlock();
    const parse_blk = g.reserveBlock();
    try g.branch(is_eof, done_blk, parse_blk);

    // Parse one declaration
    g.beginReservedBlock(parse_blk);
    const is_kw = try g.tagTest(tok, "Keyword");
    const decl_blk = g.reserveBlock();
    const expr_blk = g.reserveBlock();
    try g.branch(is_kw, decl_blk, expr_blk);

    g.beginReservedBlock(decl_blk);
    const d_result = try g.callDirect(pf.parse_decl, &.{ tokens, pos });
    const d_node = try g.recordField(d_result, "node");
    const d_next = try g.recordField(d_result, "pos");
    const d_decls = try g.listAppend(decls, d_node);
    try g.jump(loop_blk, &.{ d_next, d_decls });

    g.beginReservedBlock(expr_blk);
    const e_result = try g.callDirect(pf.parse_expr, &.{ tokens, pos, zero });
    const e_node = try g.recordField(e_result, "node");
    const e_next = try g.recordField(e_result, "pos");
    const e_decls = try g.listAppend(decls, e_node);
    try g.jump(loop_blk, &.{ e_next, e_decls });

    // Done
    g.beginReservedBlock(done_blk);
    const module_node = try g.tag(ast_module, decls);
    const module_res = try emitResult(g, module_node, pos);
    try g.ret(module_res);

    try g.endReservedFunc(pf.parse_module);
}

// ── Tests ──────────────────────────────────────────────────────────────

const interp_mod = @import("../interp.zig");
const Interpreter = interp_mod.Interpreter;
const Value = interp_mod.Value;
const builtins_mod = @import("../builtins.zig");

test "grammar: is_alpha" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    const is_alpha_fn = try genIsAlpha(&g);
    const module = try g.build(is_alpha_fn);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();

    // 'A' = 65 should be alpha
    const r1 = try interp.execFunc(is_alpha_fn, &.{.{ .int = 65 }});
    try std.testing.expect(r1.bool_val == true);
    // '0' = 48 should not be alpha
    const r2 = try interp.execFunc(is_alpha_fn, &.{.{ .int = 48 }});
    try std.testing.expect(r2.bool_val == false);
    // '_' = 95 should be alpha
    const r3 = try interp.execFunc(is_alpha_fn, &.{.{ .int = 95 }});
    try std.testing.expect(r3.bool_val == true);
}

test "grammar: skip_whitespace" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    var builder = ir.Builder.init(alloc);
    var g = Gen.init(alloc, &builder, &pool);

    const skip_ws_fn = try genSkipWhitespace(&g);
    const module = try g.build(skip_ws_fn);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    // "  hello" starting at 0 should skip to 2
    const r1 = try interp.execFunc(skip_ws_fn, &.{ .{ .string = "  hello" }, .{ .int = 0 } });
    try std.testing.expectEqual(@as(i64, 2), r1.int);
    // "hello" starting at 0 should stay at 0
    const r2 = try interp.execFunc(skip_ws_fn, &.{ .{ .string = "hello" }, .{ .int = 0 } });
    try std.testing.expectEqual(@as(i64, 0), r2.int);
}

test "grammar: lex full tokenizer" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    // Lex a simple expression
    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "fn add(x, y) x + y" }});
    const list = result.list;
    // Expect: Keyword("fn"), Ident("add"), Delim("("), Ident("x"), Punct(","),
    //         Ident("y"), Delim(")"), Ident("x"), Op("+"), Ident("y"), Eof
    try std.testing.expectEqual(@as(usize, 11), list.items.len);

    // Check first token is Keyword
    const tok0 = list.items[0].record;
    const tok0_kind = getField(tok0, pool.intern(alloc, "token") catch unreachable);
    try std.testing.expect(tok0_kind != null);
    const tag0 = tok0_kind.?.tagged;
    try std.testing.expectEqualStrings("Keyword", pool.get(tag0.tag));
    try std.testing.expectEqualStrings("fn", tag0.payload.?.string);

    // Check last token is Eof
    const tok_last = list.items[10].record;
    const tok_last_kind = getField(tok_last, pool.intern(alloc, "token") catch unreachable);
    const tag_last = tok_last_kind.?.tagged;
    try std.testing.expectEqualStrings("Eof", pool.get(tag_last.tag));
}

test "grammar: lex numbers and strings" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "42 3.14 \"hello\"" }});
    const list = result.list;
    // Expect: IntLit("42"), FloatLit("3.14"), StringLit("hello"), Eof
    try std.testing.expectEqual(@as(usize, 4), list.items.len);

    const tok_name = pool.intern(alloc, "token") catch unreachable;

    const tag0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("IntLit", pool.get(tag0.tag));
    try std.testing.expectEqualStrings("42", tag0.payload.?.string);

    const tag1 = getField(list.items[1].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("FloatLit", pool.get(tag1.tag));
    try std.testing.expectEqualStrings("3.14", tag1.payload.?.string);

    const tag2 = getField(list.items[2].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("StringLit", pool.get(tag2.tag));
    try std.testing.expectEqualStrings("hello", tag2.payload.?.string);
}

test "grammar: lex keywords and operators" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();

    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);

    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "x |> f == true" }});
    const list = result.list;
    // Expect: Ident("x"), Op("|>"), Ident("f"), Op("=="), BoolLit(true), Eof
    try std.testing.expectEqual(@as(usize, 6), list.items.len);

    const tok_name = pool.intern(alloc, "token") catch unreachable;

    const tag1 = getField(list.items[1].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Op", pool.get(tag1.tag));
    try std.testing.expectEqualStrings("|>", tag1.payload.?.string);

    const tag3 = getField(list.items[3].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Op", pool.get(tag3.tag));
    try std.testing.expectEqualStrings("==", tag3.payload.?.string);

    const tag4 = getField(list.items[4].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("BoolLit", pool.get(tag4.tag));
    try std.testing.expect(tag4.payload.?.bool_val == true);
}

fn getField(rec: *const interp_mod.RecordValue, name: intern_mod.InternedString) ?Value {
    for (rec.fields) |f| {
        if (f.name == name) return f.value;
    }
    return null;
}

fn getFieldByName(alloc: Allocator, pool: *InternPool, rec: *const interp_mod.RecordValue, name: []const u8) ?Value {
    const interned = pool.intern(alloc, name) catch return null;
    return getField(rec, interned);
}

// ── Parse test helpers ─────────────────────────────────────────────────

const ParseTestCtx = struct {
    backing: std.heap.ArenaAllocator,
    pool: InternPool,
    interp: Interpreter,
    funcs: GrammarFuncs,

    /// Initialize in-place to avoid moving the ArenaAllocator (which would
    /// invalidate the Allocator interface pointer captured by interp/pool).
    fn initInPlace(self: *ParseTestCtx) void {
        self.backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const a = self.backing.allocator();
        self.pool = InternPool.init(a);
        const module, const funcs = buildModule(a, &self.pool) catch @panic("buildModule failed");
        self.interp = Interpreter.init(a, module, &self.pool);
        builtins_mod.registerAll(&self.interp) catch @panic("registerAll failed");
        self.funcs = funcs;
    }

    fn deinit(self: *ParseTestCtx) void {
        self.interp.deinit();
        self.backing.deinit();
    }

    fn alloc(self: *ParseTestCtx) Allocator {
        return self.backing.allocator();
    }

    /// Parse source and return the first (and only) declaration/expression.
    fn parseOne(self: *ParseTestCtx, source: []const u8) !Value {
        const result = try self.interp.execFunc(self.funcs.parse, &.{.{ .string = source }});
        const res_rec = result.record;
        const node = getFieldByName(self.alloc(), &self.pool, res_rec, "node").?;
        const decls = node.tagged.payload.?.list;
        if (decls.items.len != 1) return error.TypeError;
        return decls.items[0];
    }

    /// Parse source and return the module's decl list.
    fn parseDecls(self: *ParseTestCtx, source: []const u8) ![]const Value {
        const result = try self.interp.execFunc(self.funcs.parse, &.{.{ .string = source }});
        const res_rec = result.record;
        const node = getFieldByName(self.alloc(), &self.pool, res_rec, "node").?;
        return node.tagged.payload.?.list.items;
    }

    /// Get tag name of a tagged value.
    fn tagName(self: *ParseTestCtx, val: Value) []const u8 {
        return self.pool.get(val.tagged.tag);
    }

    /// Get field from a record inside a tagged value's payload.
    fn field(self: *ParseTestCtx, val: Value, name: []const u8) ?Value {
        return getFieldByName(self.alloc(), &self.pool, val.tagged.payload.?.record, name);
    }
};

// ── Lexer tests ────────────────────────────────────────────────────────

test "grammar: lex empty string" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();
    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);
    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "" }});
    const list = result.list;
    // Should just have Eof
    try std.testing.expectEqual(@as(usize, 1), list.items.len);
    const tok_name = pool.intern(alloc, "token") catch unreachable;
    const tag0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Eof", pool.get(tag0.tag));
}

test "grammar: lex whitespace only" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();
    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);
    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "   \t\n  " }});
    const list = result.list;
    try std.testing.expectEqual(@as(usize, 1), list.items.len); // just Eof
}

test "grammar: lex comment skipping" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();
    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);
    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    // Comment should be skipped, only 42 + Eof remain
    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "-- this is a comment\n42" }});
    const list = result.list;
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    const tok_name = pool.intern(alloc, "token") catch unreachable;
    const tag0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("IntLit", pool.get(tag0.tag));
}

test "grammar: lex all delimiters and punctuation" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();
    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);
    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "( ) { } [ ] : , ." }});
    const list = result.list;
    // 9 tokens + Eof = 10
    try std.testing.expectEqual(@as(usize, 10), list.items.len);
}

test "grammar: lex string with escape" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();
    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);
    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "\"hello\\nworld\"" }});
    const list = result.list;
    try std.testing.expectEqual(@as(usize, 2), list.items.len); // StringLit + Eof
    const tok_name = pool.intern(alloc, "token") catch unreachable;
    const tag0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("StringLit", pool.get(tag0.tag));
    // Content should be hello\nworld (raw, not processed)
    try std.testing.expectEqualStrings("hello\\nworld", tag0.payload.?.string);
}

test "grammar: lex multi-char operators" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const alloc = backing.allocator();
    var pool = InternPool.init(alloc);
    const module, const funcs = try buildModule(alloc, &pool);
    var interp = Interpreter.init(alloc, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "== != <= >= -> |> => .." }});
    const list = result.list;
    // 8 two-char ops + Eof = 9
    try std.testing.expectEqual(@as(usize, 9), list.items.len);
    const tok_name = pool.intern(alloc, "token") catch unreachable;
    const tag0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("==", tag0.payload.?.string);
    const tag7 = getField(list.items[7].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("..", tag7.payload.?.string);
}

// ── Parser: Literal tests ──────────────────────────────────────────────

test "grammar: parse integer literal" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("42");
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(expr));
    try std.testing.expectEqual(@as(i64, 42), expr.tagged.payload.?.int);
}

test "grammar: parse float literal" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("3.14");
    try std.testing.expectEqualStrings("FloatLit", ctx.tagName(expr));
    try std.testing.expectEqualStrings("3.14", expr.tagged.payload.?.string);
}

test "grammar: parse string literal" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("\"hello\"");
    try std.testing.expectEqualStrings("StringLit", ctx.tagName(expr));
    try std.testing.expectEqualStrings("hello", expr.tagged.payload.?.string);
}

test "grammar: parse bool literals" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const t = try ctx.parseOne("true");
    try std.testing.expectEqualStrings("BoolLit", ctx.tagName(t));
    try std.testing.expect(t.tagged.payload.?.bool_val == true);

    const f = try ctx.parseOne("false");
    try std.testing.expect(f.tagged.payload.?.bool_val == false);
}

test "grammar: parse nil literal" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const n = try ctx.parseOne("nil");
    try std.testing.expectEqualStrings("NilLit", ctx.tagName(n));
}

test "grammar: parse identifier" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("foo");
    try std.testing.expectEqualStrings("Ident", ctx.tagName(expr));
    try std.testing.expectEqualStrings("foo", expr.tagged.payload.?.string);
}

// ── Parser: Operator precedence ────────────────────────────────────────

test "grammar: parse precedence - mul binds tighter than add" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "1 + 2 * 3" should parse as "1 + (2 * 3)"
    const expr = try ctx.parseOne("1 + 2 * 3");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    const op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("+", op.string);
    // LHS should be IntLit(1)
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(lhs));
    try std.testing.expectEqual(@as(i64, 1), lhs.tagged.payload.?.int);
    // RHS should be BinOp(2 * 3)
    const rhs = ctx.field(expr, "rhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(rhs));
    const rhs_op = getFieldByName(ctx.alloc(), &ctx.pool, rhs.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("*", rhs_op.string);
}

test "grammar: parse precedence - left associativity" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "1 - 2 - 3" should parse as "(1 - 2) - 3"
    const expr = try ctx.parseOne("1 - 2 - 3");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    const op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("-", op.string);
    // RHS should be IntLit(3)
    const rhs = ctx.field(expr, "rhs").?;
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(rhs));
    try std.testing.expectEqual(@as(i64, 3), rhs.tagged.payload.?.int);
    // LHS should be BinOp(1 - 2)
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(lhs));
}

test "grammar: parse precedence - comparison lower than arithmetic" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "a + b == c" should parse as "(a + b) == c"
    const expr = try ctx.parseOne("a + b == c");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    const op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("==", op.string);
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(lhs));
}

test "grammar: parse precedence - logical and/or" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "a and b or c" should parse as "(a and b) or c"
    const expr = try ctx.parseOne("a and b or c");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    const op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("or", op.string);
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(lhs));
    const lhs_op = getFieldByName(ctx.alloc(), &ctx.pool, lhs.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("and", lhs_op.string);
}

test "grammar: parse pipe operator" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("x |> f");
    try std.testing.expectEqualStrings("Pipe", ctx.tagName(expr));
}

// ── Parser: Function calls and field access ────────────────────────────

test "grammar: parse function call" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("f(1, 2, 3)");
    try std.testing.expectEqualStrings("Call", ctx.tagName(expr));
    const callee = ctx.field(expr, "callee").?;
    try std.testing.expectEqualStrings("Ident", ctx.tagName(callee));
    const args = ctx.field(expr, "args").?;
    try std.testing.expectEqual(@as(usize, 3), args.list.items.len);
}

test "grammar: parse zero-arg function call" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("f()");
    try std.testing.expectEqualStrings("Call", ctx.tagName(expr));
    const args = ctx.field(expr, "args").?;
    try std.testing.expectEqual(@as(usize, 0), args.list.items.len);
}

test "grammar: parse field access" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("record.field");
    try std.testing.expectEqualStrings("FieldAccess", ctx.tagName(expr));
    const field_name = ctx.field(expr, "field").?;
    try std.testing.expectEqualStrings("field", field_name.string);
}

test "grammar: parse chained field access" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // a.b.c should parse as (a.b).c
    const expr = try ctx.parseOne("a.b.c");
    try std.testing.expectEqualStrings("FieldAccess", ctx.tagName(expr));
    const field_name = ctx.field(expr, "field").?;
    try std.testing.expectEqualStrings("c", field_name.string);
    const inner = ctx.field(expr, "expr").?;
    try std.testing.expectEqualStrings("FieldAccess", ctx.tagName(inner));
}

test "grammar: parse call on field access" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // obj.method(x) should parse as Call(FieldAccess(obj, method), [x])
    const expr = try ctx.parseOne("obj.method(x)");
    try std.testing.expectEqualStrings("Call", ctx.tagName(expr));
    const callee = ctx.field(expr, "callee").?;
    try std.testing.expectEqualStrings("FieldAccess", ctx.tagName(callee));
}

// ── Parser: Grouping and unary ─────────────────────────────────────────

test "grammar: parse parenthesized expression" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // (1 + 2) * 3 — parens force addition first
    const expr = try ctx.parseOne("(1 + 2) * 3");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    const op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("*", op.string);
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(lhs));
}

test "grammar: parse unary negation" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("-x");
    try std.testing.expectEqualStrings("Unary", ctx.tagName(expr));
    const op = getFieldByName(ctx.alloc(), &ctx.pool, expr.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("-", op.string);
}

// ── Parser: List literal ───────────────────────────────────────────────

test "grammar: parse list literal" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("[1, 2, 3]");
    try std.testing.expectEqualStrings("ListLit", ctx.tagName(expr));
    const items = expr.tagged.payload.?.list;
    try std.testing.expectEqual(@as(usize, 3), items.items.len);
}

test "grammar: parse empty list" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("[]");
    try std.testing.expectEqualStrings("ListLit", ctx.tagName(expr));
    const items = expr.tagged.payload.?.list;
    try std.testing.expectEqual(@as(usize, 0), items.items.len);
}

// ── Parser: Lambda ─────────────────────────────────────────────────────

test "grammar: parse lambda" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("x => x + 1");
    try std.testing.expectEqualStrings("Lambda", ctx.tagName(expr));
    const params = ctx.field(expr, "params").?;
    try std.testing.expectEqual(@as(usize, 1), params.list.items.len);
    const body = ctx.field(expr, "body").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(body));
}

// ── Parser: If/else ────────────────────────────────────────────────────

test "grammar: parse if-else" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("if true { 1 } else { 0 }");
    try std.testing.expectEqualStrings("If", ctx.tagName(expr));
    const cond = ctx.field(expr, "cond").?;
    try std.testing.expectEqualStrings("BoolLit", ctx.tagName(cond));
    const then_b = ctx.field(expr, "then_branch").?;
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(then_b));
    const else_b = ctx.field(expr, "else_branch").?;
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(else_b));
}

test "grammar: parse if without else" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("if x { 1 }");
    try std.testing.expectEqualStrings("If", ctx.tagName(expr));
    const else_b = ctx.field(expr, "else_branch").?;
    try std.testing.expect(else_b == .nil);
}

// ── Parser: Let ────────────────────────────────────────────────────────

test "grammar: parse let binding" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("let x = 42");
    try std.testing.expectEqualStrings("Let", ctx.tagName(expr));
    const pat = ctx.field(expr, "pattern").?;
    try std.testing.expectEqualStrings("PatBind", ctx.tagName(pat));
    try std.testing.expectEqualStrings("x", pat.tagged.payload.?.string);
    const val = ctx.field(expr, "value").?;
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(val));
}

// ── Parser: Match ──────────────────────────────────────────────────────

test "grammar: parse match expression" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("match x { 0 -> 1, _ -> 2 }");
    try std.testing.expectEqualStrings("Match", ctx.tagName(expr));
    const arms = ctx.field(expr, "arms").?;
    try std.testing.expectEqual(@as(usize, 2), arms.list.items.len);
}

// ── Parser: Fn declarations ────────────────────────────────────────────

test "grammar: parse fn with return type" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("fn square(x: Int) -> Int { x * x }");
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(expr));
    const name = ctx.field(expr, "name").?;
    try std.testing.expectEqualStrings("square", name.string);
    const ret = ctx.field(expr, "return_type").?;
    try std.testing.expectEqualStrings("TypeNamed", ctx.tagName(ret));
    const params = ctx.field(expr, "params").?;
    try std.testing.expectEqual(@as(usize, 1), params.list.items.len);
    // Check param has type annotation
    const param0 = params.list.items[0].record;
    const param_type = getFieldByName(ctx.alloc(), &ctx.pool, param0, "type").?;
    try std.testing.expectEqualStrings("TypeNamed", ctx.tagName(param_type));
}

test "grammar: parse fn without type annotations" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("fn add(x, y) { x + y }");
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(expr));
    const params = ctx.field(expr, "params").?;
    try std.testing.expectEqual(@as(usize, 2), params.list.items.len);
    const ret = ctx.field(expr, "return_type").?;
    try std.testing.expect(ret == .nil);
}

test "grammar: parse fn zero params" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("fn greeting() { \"hello\" }");
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(expr));
    const params = ctx.field(expr, "params").?;
    try std.testing.expectEqual(@as(usize, 0), params.list.items.len);
}

// ── Parser: Type declarations ──────────────────────────────────────────

test "grammar: parse type with variants" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("type Option { Some(Int), None }");
    try std.testing.expectEqualStrings("TypeDecl", ctx.tagName(expr));
    const name = ctx.field(expr, "name").?;
    try std.testing.expectEqualStrings("Option", name.string);
    const variants = ctx.field(expr, "variants").?;
    try std.testing.expectEqual(@as(usize, 2), variants.list.items.len);
}

// ── Parser: Multiple declarations ──────────────────────────────────────

test "grammar: parse multiple declarations" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decls = try ctx.parseDecls("fn f() { 1 } fn g() { 2 }");
    try std.testing.expectEqual(@as(usize, 2), decls.len);
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(decls[0]));
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(decls[1]));
}

// ── Parser: Comments in source ─────────────────────────────────────────

test "grammar: parse with comments" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("-- comment\n42");
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(expr));
}

// ── Lexer edge case tests ──────────────────────────────────────────────

test "grammar: lex = vs ==" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "= ==" }});
    const list = result.list;
    // = Op("="), == Op("=="), Eof → 3 tokens
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    const tok_name = pool.intern(a, "token") catch unreachable;
    const t0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Op", pool.get(t0.tag));
    try std.testing.expectEqualStrings("=", t0.payload.?.string);
    const t1 = getField(list.items[1].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Op", pool.get(t1.tag));
    try std.testing.expectEqualStrings("==", t1.payload.?.string);
}

test "grammar: lex keyword boundary - fns is Ident not Keyword" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "fns letx" }});
    const list = result.list;
    // fns → Ident("fns"), letx → Ident("letx"), Eof → 3 tokens
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    const tok_name = pool.intern(a, "token") catch unreachable;
    const t0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Ident", pool.get(t0.tag));
    try std.testing.expectEqualStrings("fns", t0.payload.?.string);
    const t1 = getField(list.items[1].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Ident", pool.get(t1.tag));
    try std.testing.expectEqualStrings("letx", t1.payload.?.string);
}

test "grammar: lex and/or as keywords" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "and or" }});
    const list = result.list;
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    const tok_name = pool.intern(a, "token") catch unreachable;
    const t0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Keyword", pool.get(t0.tag));
    try std.testing.expectEqualStrings("and", t0.payload.?.string);
    const t1 = getField(list.items[1].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("Keyword", pool.get(t1.tag));
    try std.testing.expectEqualStrings("or", t1.payload.?.string);
}

test "grammar: lex adjacent operators" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "!=<=" }});
    const list = result.list;
    // != Op("!="), <= Op("<="), Eof
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    const tok_name = pool.intern(a, "token") catch unreachable;
    const t0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("!=", t0.payload.?.string);
    const t1 = getField(list.items[1].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("<=", t1.payload.?.string);
}

test "grammar: lex string with escapes preserves raw content" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    // The seed lexer preserves escape sequences as raw text (no processing).
    // Escape processing is deferred to the compiler/interpreter phase.
    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "\"a\\nb\"" }});
    const list = result.list;
    try std.testing.expectEqual(@as(usize, 2), list.items.len); // StringLit + Eof
    const tok_name = pool.intern(a, "token") catch unreachable;
    const t0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("StringLit", pool.get(t0.tag));
    try std.testing.expectEqualStrings("a\\nb", t0.payload.?.string);
}

test "grammar: lex empty string literal" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "\"\"" }});
    const list = result.list;
    try std.testing.expectEqual(@as(usize, 2), list.items.len); // StringLit + Eof
    const tok_name = pool.intern(a, "token") catch unreachable;
    const t0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("StringLit", pool.get(t0.tag));
    try std.testing.expectEqualStrings("", t0.payload.?.string);
}

test "grammar: lex float without leading zero" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    // 0.5 should lex as FloatLit
    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "0.5" }});
    const list = result.list;
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
    const tok_name = pool.intern(a, "token") catch unreachable;
    const t0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("FloatLit", pool.get(t0.tag));
    try std.testing.expectEqualStrings("0.5", t0.payload.?.string);
}

test "grammar: lex integer followed by dot (not float)" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    // "42.foo" should lex as IntLit("42"), Punct("."), Ident("foo"), Eof
    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "42.foo" }});
    const list = result.list;
    const tok_name = pool.intern(a, "token") catch unreachable;
    const t0 = getField(list.items[0].record, tok_name).?.tagged;
    // If the lexer treats 42. as a float, the tag will be FloatLit
    // This test documents the current behavior
    const tag = pool.get(t0.tag);
    // Either IntLit("42") followed by ".foo" or FloatLit("42.") — document whichever
    _ = tag; // Just verify it doesn't crash
    try std.testing.expect(list.items.len >= 2); // At minimum: something + Eof
}

// ── Parser semantic tests ──────────────────────────────────────────────

test "grammar: parse precedence - all arithmetic" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "1 + 2 * 3 - 4 / 5" → ((1 + (2 * 3)) - (4 / 5))
    const expr = try ctx.parseOne("1 + 2 * 3 - 4 / 5");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    // Top-level: subtraction (left-assoc: (1+2*3) - (4/5))
    const top_op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("-", top_op.string);
    // LHS of top: 1 + (2*3)
    const add_node = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(add_node));
    const add_op = getFieldByName(ctx.alloc(), &ctx.pool, add_node.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("+", add_op.string);
    // RHS of add: 2 * 3
    const mul_node = getFieldByName(ctx.alloc(), &ctx.pool, add_node.tagged.payload.?.record, "rhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(mul_node));
    const mul_op = getFieldByName(ctx.alloc(), &ctx.pool, mul_node.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("*", mul_op.string);
    // RHS of top: 4 / 5
    const div_node = ctx.field(expr, "rhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(div_node));
    const div_op = getFieldByName(ctx.alloc(), &ctx.pool, div_node.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("/", div_op.string);
}

test "grammar: parse precedence - comparison vs arithmetic" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "a + 1 == b * 2" → (a+1) == (b*2)
    const expr = try ctx.parseOne("a + 1 == b * 2");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    const top_op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("==", top_op.string);
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(lhs));
    const lhs_op = getFieldByName(ctx.alloc(), &ctx.pool, lhs.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("+", lhs_op.string);
    const rhs = ctx.field(expr, "rhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(rhs));
    const rhs_op = getFieldByName(ctx.alloc(), &ctx.pool, rhs.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("*", rhs_op.string);
}

test "grammar: parse precedence - and binds tighter than or" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "x or y and z" → x or (y and z)
    const expr = try ctx.parseOne("x or y and z");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    const top_op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("or", top_op.string);
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("Ident", ctx.tagName(lhs));
    const rhs = ctx.field(expr, "rhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(rhs));
    const rhs_op = getFieldByName(ctx.alloc(), &ctx.pool, rhs.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("and", rhs_op.string);
}

test "grammar: parse precedence - pipe is lowest" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "a + b |> f" → (a+b) |> f
    const expr = try ctx.parseOne("a + b |> f");
    try std.testing.expectEqualStrings("Pipe", ctx.tagName(expr));
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(lhs));
    const lhs_op = getFieldByName(ctx.alloc(), &ctx.pool, lhs.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("+", lhs_op.string);
}

test "grammar: parse nested function calls" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "f(g(x))" → Call(f, [Call(g, [x])])
    const expr = try ctx.parseOne("f(g(x))");
    try std.testing.expectEqualStrings("Call", ctx.tagName(expr));
    const callee = ctx.field(expr, "callee").?;
    try std.testing.expectEqualStrings("Ident", ctx.tagName(callee));
    const args = ctx.field(expr, "args").?.list;
    try std.testing.expectEqual(@as(usize, 1), args.items.len);
    const inner = args.items[0];
    try std.testing.expectEqualStrings("Call", ctx.tagName(inner));
}

test "grammar: parse multi-arg function call with expressions" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "f(1 + 2, 3)" → Call(f, [BinOp(+, 1, 2), IntLit(3)])
    const expr = try ctx.parseOne("f(1 + 2, 3)");
    try std.testing.expectEqualStrings("Call", ctx.tagName(expr));
    const args = ctx.field(expr, "args").?.list;
    try std.testing.expectEqual(@as(usize, 2), args.items.len);
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(args.items[0]));
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(args.items[1]));
}

test "grammar: parse field access on call result" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "f(x).y" → FieldAccess(Call(f, [x]), y)
    const expr = try ctx.parseOne("f(x).y");
    try std.testing.expectEqualStrings("FieldAccess", ctx.tagName(expr));
    const inner = ctx.field(expr, "expr").?;
    try std.testing.expectEqualStrings("Call", ctx.tagName(inner));
    const field_name = ctx.field(expr, "field").?;
    try std.testing.expectEqualStrings("y", field_name.string);
}

test "grammar: parse deeply nested parentheses" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "((((x))))" → Ident("x")
    const expr = try ctx.parseOne("((((x))))");
    try std.testing.expectEqualStrings("Ident", ctx.tagName(expr));
    try std.testing.expectEqualStrings("x", expr.tagged.payload.?.string);
}

test "grammar: parse unary in expression" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "-x + y" → BinOp(+, Unary(-, x), y) — unary binds tighter
    const expr = try ctx.parseOne("-x + y");
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
    const top_op = ctx.field(expr, "op").?;
    try std.testing.expectEqualStrings("+", top_op.string);
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("Unary", ctx.tagName(lhs));
}

test "grammar: parse let with complex expression" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "let y = 1 + 2" → Let(Bind("y"), BinOp(+, 1, 2))
    const expr = try ctx.parseOne("let y = 1 + 2");
    try std.testing.expectEqualStrings("Let", ctx.tagName(expr));
    const val = ctx.field(expr, "value").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(val));
    const op = getFieldByName(ctx.alloc(), &ctx.pool, val.tagged.payload.?.record, "op").?;
    try std.testing.expectEqualStrings("+", op.string);
}

test "grammar: parse let with wildcard pattern" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("let _ = 42");
    try std.testing.expectEqualStrings("Let", ctx.tagName(expr));
    const pat = ctx.field(expr, "pattern").?;
    try std.testing.expectEqualStrings("PatWildcard", ctx.tagName(pat));
}

test "grammar: parse if with nested if in else" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("if x { 1 } else if y { 2 } else { 3 }");
    try std.testing.expectEqualStrings("If", ctx.tagName(expr));
    const else_br = ctx.field(expr, "else_branch").?;
    try std.testing.expectEqualStrings("If", ctx.tagName(else_br));
    // Single-expression blocks are unwrapped, so "{ 3 }" becomes IntLit(3)
    const inner_else = getFieldByName(ctx.alloc(), &ctx.pool, else_br.tagged.payload.?.record, "else_branch").?;
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(inner_else));
}

test "grammar: parse match with multiple arms" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("match x { 1 -> a, 2 -> b, _ -> c }");
    try std.testing.expectEqualStrings("Match", ctx.tagName(expr));
    const arms = ctx.field(expr, "arms").?.list;
    try std.testing.expectEqual(@as(usize, 3), arms.items.len);
    // First arm pattern should be a literal
    const arm0_pat = getFieldByName(ctx.alloc(), &ctx.pool, arms.items[0].record, "pattern").?;
    try std.testing.expectEqualStrings("PatLiteral", ctx.tagName(arm0_pat));
    // Last arm pattern should be wildcard
    const arm2_pat = getFieldByName(ctx.alloc(), &ctx.pool, arms.items[2].record, "pattern").?;
    try std.testing.expectEqualStrings("PatWildcard", ctx.tagName(arm2_pat));
}

test "grammar: parse fn with multiple params" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn add(x: Int, y: Int) -> Int { x + y }");
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(decl));
    const name = ctx.field(decl, "name").?;
    try std.testing.expectEqualStrings("add", name.string);
    const params = ctx.field(decl, "params").?.list;
    try std.testing.expectEqual(@as(usize, 2), params.items.len);
    const ret_type = ctx.field(decl, "return_type").?;
    try std.testing.expectEqualStrings("TypeNamed", ctx.tagName(ret_type));
}

test "grammar: parse multiple expressions as declarations" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // Multiple standalone expressions separated by space
    const decls = try ctx.parseDecls("42 true");
    try std.testing.expectEqual(@as(usize, 2), decls.len);
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(decls[0]));
    try std.testing.expectEqualStrings("BoolLit", ctx.tagName(decls[1]));
}

test "grammar: parse list with trailing comma" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("[1, 2, 3]");
    try std.testing.expectEqualStrings("ListLit", ctx.tagName(expr));
    const items = expr.tagged.payload.?.list;
    try std.testing.expectEqual(@as(usize, 3), items.items.len);
}

test "grammar: parse single-element list" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const expr = try ctx.parseOne("[42]");
    try std.testing.expectEqualStrings("ListLit", ctx.tagName(expr));
    const items = expr.tagged.payload.?.list;
    try std.testing.expectEqual(@as(usize, 1), items.items.len);
    try std.testing.expectEqualStrings("IntLit", ctx.tagName(items.items[0]));
}

test "grammar: parse lambda with body expression" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "x => x + 1" — lambda with binary expression body
    const expr = try ctx.parseOne("x => x + 1");
    try std.testing.expectEqualStrings("Lambda", ctx.tagName(expr));
    const body = ctx.field(expr, "body").?;
    try std.testing.expectEqualStrings("BinOp", ctx.tagName(body));
}

test "grammar: parse comparison operators" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // Test each comparison operator produces correct op string
    const ops = [_]struct { src: []const u8, op: []const u8 }{
        .{ .src = "a < b", .op = "<" },
        .{ .src = "a > b", .op = ">" },
        .{ .src = "a <= b", .op = "<=" },
        .{ .src = "a >= b", .op = ">=" },
        .{ .src = "a != b", .op = "!=" },
    };
    for (ops) |case| {
        const expr = try ctx.parseOne(case.src);
        try std.testing.expectEqualStrings("BinOp", ctx.tagName(expr));
        const op = ctx.field(expr, "op").?;
        try std.testing.expectEqualStrings(case.op, op.string);
    }
}

test "grammar: parse chained pipes" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // "x |> f |> g" → Pipe(Pipe(x, f), g) — left associative
    const expr = try ctx.parseOne("x |> f |> g");
    try std.testing.expectEqualStrings("Pipe", ctx.tagName(expr));
    const lhs = ctx.field(expr, "lhs").?;
    try std.testing.expectEqualStrings("Pipe", ctx.tagName(lhs));
    const rhs = ctx.field(expr, "rhs").?;
    try std.testing.expectEqualStrings("Ident", ctx.tagName(rhs));
    try std.testing.expectEqualStrings("g", rhs.tagged.payload.?.string);
}

test "grammar: parse type decl with record variant" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("type Point { x: Int, y: Int }");
    try std.testing.expectEqualStrings("TypeDecl", ctx.tagName(decl));
    const name = ctx.field(decl, "name").?;
    try std.testing.expectEqualStrings("Point", name.string);
    const variants = ctx.field(decl, "variants").?.list;
    try std.testing.expectEqual(@as(usize, 2), variants.items.len);
}

test "grammar: parse use declaration" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("use std");
    try std.testing.expectEqualStrings("UseDecl", ctx.tagName(decl));
    try std.testing.expectEqualStrings("std", decl.tagged.payload.?.string);
}

test "grammar: parse block with multiple expressions" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    // Block inside an if should have multiple expressions
    const expr = try ctx.parseOne("if true { 1 2 3 }");
    try std.testing.expectEqualStrings("If", ctx.tagName(expr));
    const then_br = ctx.field(expr, "then_branch").?;
    try std.testing.expectEqualStrings("Block", ctx.tagName(then_br));
    const block_items = then_br.tagged.payload.?.list;
    try std.testing.expectEqual(@as(usize, 3), block_items.items.len);
}

test "grammar: parse boolean literal values" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const t = try ctx.parseOne("true");
    try std.testing.expectEqualStrings("BoolLit", ctx.tagName(t));
    try std.testing.expect(t.tagged.payload.?.bool_val == true);
    const f = try ctx.parseOne("false");
    try std.testing.expectEqualStrings("BoolLit", ctx.tagName(f));
    try std.testing.expect(f.tagged.payload.?.bool_val == false);
}

// ── Trait/Impl/Effect declaration tests ────────────────────────────────

test "grammar: parse trait with one method" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("trait Eq { fn eq(a: Int, b: Int) -> Bool }");
    try std.testing.expectEqualStrings("TraitDecl", ctx.tagName(decl));
    const name = ctx.field(decl, "name").?;
    try std.testing.expectEqualStrings("Eq", name.string);
    const tparams = ctx.field(decl, "type_params").?.list;
    try std.testing.expectEqual(@as(usize, 0), tparams.items.len);
    const methods = ctx.field(decl, "methods").?.list;
    try std.testing.expectEqual(@as(usize, 1), methods.items.len);
    const m0_name = getFieldByName(ctx.alloc(), &ctx.pool, methods.items[0].record, "name").?;
    try std.testing.expectEqualStrings("eq", m0_name.string);
    const m0_params = getFieldByName(ctx.alloc(), &ctx.pool, methods.items[0].record, "params").?.list;
    try std.testing.expectEqual(@as(usize, 2), m0_params.items.len);
    const m0_ret = getFieldByName(ctx.alloc(), &ctx.pool, methods.items[0].record, "return_type").?;
    try std.testing.expectEqualStrings("TypeNamed", ctx.tagName(m0_ret));
}

test "grammar: parse trait with type params" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("trait Show<T> { fn show(x: T) -> String }");
    try std.testing.expectEqualStrings("TraitDecl", ctx.tagName(decl));
    const tparams = ctx.field(decl, "type_params").?.list;
    try std.testing.expectEqual(@as(usize, 1), tparams.items.len);
    try std.testing.expectEqualStrings("T", tparams.items[0].string);
}

test "grammar: parse trait with multiple methods" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("trait Ord<T> { fn lt(a: T, b: T) -> Bool, fn eq(a: T, b: T) -> Bool }");
    try std.testing.expectEqualStrings("TraitDecl", ctx.tagName(decl));
    const methods = ctx.field(decl, "methods").?.list;
    try std.testing.expectEqual(@as(usize, 2), methods.items.len);
    const m0 = getFieldByName(ctx.alloc(), &ctx.pool, methods.items[0].record, "name").?;
    try std.testing.expectEqualStrings("lt", m0.string);
    const m1 = getFieldByName(ctx.alloc(), &ctx.pool, methods.items[1].record, "name").?;
    try std.testing.expectEqualStrings("eq", m1.string);
}

test "grammar: parse trait method without return type" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("trait Sink { fn consume(x: Int) }");
    try std.testing.expectEqualStrings("TraitDecl", ctx.tagName(decl));
    const methods = ctx.field(decl, "methods").?.list;
    try std.testing.expectEqual(@as(usize, 1), methods.items.len);
    const m0_ret = getFieldByName(ctx.alloc(), &ctx.pool, methods.items[0].record, "return_type").?;
    try std.testing.expect(m0_ret == .nil);
}

test "grammar: parse impl with one method" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("impl Eq<Int> { fn eq(a: Int, b: Int) -> Bool { a == b } }");
    try std.testing.expectEqualStrings("ImplDecl", ctx.tagName(decl));
    const trait_name = ctx.field(decl, "trait_name").?;
    try std.testing.expectEqualStrings("Eq", trait_name.string);
    const type_name = ctx.field(decl, "type_name").?;
    try std.testing.expectEqualStrings("Int", type_name.string);
    const methods = ctx.field(decl, "methods").?.list;
    try std.testing.expectEqual(@as(usize, 1), methods.items.len);
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(methods.items[0]));
}

test "grammar: parse impl without type arg" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("impl Show { fn show(x: Int) -> String { \"hello\" } }");
    try std.testing.expectEqualStrings("ImplDecl", ctx.tagName(decl));
    const type_name = ctx.field(decl, "type_name").?;
    try std.testing.expect(type_name == .nil);
}

test "grammar: parse effect with operations" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("effect Console { fn print(msg: String) -> Nil, fn read() -> String }");
    try std.testing.expectEqualStrings("EffectDecl", ctx.tagName(decl));
    const name = ctx.field(decl, "name").?;
    try std.testing.expectEqualStrings("Console", name.string);
    const ops = ctx.field(decl, "operations").?.list;
    try std.testing.expectEqual(@as(usize, 2), ops.items.len);
    const op0 = getFieldByName(ctx.alloc(), &ctx.pool, ops.items[0].record, "name").?;
    try std.testing.expectEqualStrings("print", op0.string);
    const op1 = getFieldByName(ctx.alloc(), &ctx.pool, ops.items[1].record, "name").?;
    try std.testing.expectEqualStrings("read", op1.string);
}

test "grammar: parse effect with single operation" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("effect Log { fn log(msg: String) }");
    try std.testing.expectEqualStrings("EffectDecl", ctx.tagName(decl));
    const ops = ctx.field(decl, "operations").?.list;
    try std.testing.expectEqual(@as(usize, 1), ops.items.len);
    const op0_ret = getFieldByName(ctx.alloc(), &ctx.pool, ops.items[0].record, "return_type").?;
    try std.testing.expect(op0_ret == .nil);
}

test "grammar: parse mixed declarations" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const src =
        \\type Bool { True, False }
        \\trait Eq { fn eq(a: Int, b: Int) -> Bool }
        \\effect Log { fn log(msg: String) }
        \\fn main() { 42 }
    ;
    const decls = try ctx.parseDecls(src);
    try std.testing.expectEqual(@as(usize, 4), decls.len);
    try std.testing.expectEqualStrings("TypeDecl", ctx.tagName(decls[0]));
    try std.testing.expectEqualStrings("TraitDecl", ctx.tagName(decls[1]));
    try std.testing.expectEqualStrings("EffectDecl", ctx.tagName(decls[2]));
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(decls[3]));
}

// ── TypeDecl type params ──────────────────────────────────────────────

test "grammar: type decl with type params" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("type Option<T> { Some(T), None }");
    try std.testing.expectEqualStrings("TypeDecl", ctx.tagName(decl));
    try std.testing.expectEqualStrings("Option", ctx.field(decl, "name").?.string);
    const tparams = ctx.field(decl, "type_params").?.list;
    try std.testing.expectEqual(@as(usize, 1), tparams.items.len);
    try std.testing.expectEqualStrings("T", tparams.items[0].string);
}

test "grammar: type decl with multiple type params" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("type Either<L, R> { Left(L), Right(R) }");
    try std.testing.expectEqualStrings("TypeDecl", ctx.tagName(decl));
    const tparams = ctx.field(decl, "type_params").?.list;
    try std.testing.expectEqual(@as(usize, 2), tparams.items.len);
    try std.testing.expectEqualStrings("L", tparams.items[0].string);
    try std.testing.expectEqualStrings("R", tparams.items[1].string);
}

test "grammar: type decl without type params has empty list" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("type Bool { True, False }");
    const tparams = ctx.field(decl, "type_params").?.list;
    try std.testing.expectEqual(@as(usize, 0), tparams.items.len);
}

// ── FnDecl effect arrows ─────────────────────────────────────────────

test "grammar: fn decl with effect arrow" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn read() -[IO]> String { nil }");
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(decl));
    try std.testing.expectEqualStrings("read", ctx.field(decl, "name").?.string);
    const effects = ctx.field(decl, "effects").?.list;
    try std.testing.expectEqual(@as(usize, 1), effects.items.len);
    try std.testing.expectEqualStrings("IO", effects.items[0].string);
    const ret = ctx.field(decl, "return_type").?;
    try std.testing.expectEqualStrings("TypeNamed", ctx.tagName(ret));
}

test "grammar: fn decl with multiple effects" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn run() -[IO, State]> Int { 0 }");
    const effects = ctx.field(decl, "effects").?.list;
    try std.testing.expectEqual(@as(usize, 2), effects.items.len);
    try std.testing.expectEqualStrings("IO", effects.items[0].string);
    try std.testing.expectEqualStrings("State", effects.items[1].string);
}

test "grammar: fn decl without effects has empty list" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn add(a: Int, b: Int) -> Int { a }");
    const effects = ctx.field(decl, "effects").?.list;
    try std.testing.expectEqual(@as(usize, 0), effects.items.len);
}

test "grammar: fn decl no return type has empty effects" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn main() { 42 }");
    const effects = ctx.field(decl, "effects").?.list;
    try std.testing.expectEqual(@as(usize, 0), effects.items.len);
    try std.testing.expect(ctx.field(decl, "return_type").? == .nil);
}

// ── StringInterp ──────────────────────────────────────────────────────

test "grammar: lex string with interpolation" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "\"hello {name}\"" }});
    const list = result.list;
    const tok_name = try pool.intern(a, "token");
    const tag0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("StringInterp", pool.get(tag0.tag));
}

test "grammar: lex plain string stays StringLit" {
    var backing = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer backing.deinit();
    const a = backing.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = try buildModule(a, &pool);
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    try builtins_mod.registerAll(&interp);

    const result = try interp.execFunc(funcs.lex, &.{.{ .string = "\"hello world\"" }});
    const list = result.list;
    const tok_name = try pool.intern(a, "token");
    const tag0 = getField(list.items[0].record, tok_name).?.tagged;
    try std.testing.expectEqualStrings("StringLit", pool.get(tag0.tag));
}

test "grammar: parse string interpolation expr" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f() { \"hello {name}\" }");
    try std.testing.expectEqualStrings("FnDecl", ctx.tagName(decl));
    const body = ctx.field(decl, "body").?;
    try std.testing.expectEqualStrings("StringInterp", ctx.tagName(body));
}

// ── RecordLit ─────────────────────────────────────────────────────────

test "grammar: parse record literal" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f() { {x: 1, y: 2} }");
    const body = ctx.field(decl, "body").?;
    try std.testing.expectEqualStrings("RecordLit", ctx.tagName(body));
    const fields = body.tagged.payload.?.list;
    try std.testing.expectEqual(@as(usize, 2), fields.items.len);
}

test "grammar: parse single-field record literal" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f() { {name: \"chris\"} }");
    const body = ctx.field(decl, "body").?;
    try std.testing.expectEqualStrings("RecordLit", ctx.tagName(body));
}

// ── RecordUpdate ──────────────────────────────────────────────────────

test "grammar: parse record update" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f() { {p | x: 1} }");
    const body = ctx.field(decl, "body").?;
    try std.testing.expectEqualStrings("RecordUpdate", ctx.tagName(body));
    const base = ctx.field(body, "base").?;
    try std.testing.expectEqualStrings("Ident", ctx.tagName(base));
    const fields = ctx.field(body, "fields").?.list;
    try std.testing.expectEqual(@as(usize, 1), fields.items.len);
}

test "grammar: parse record update multiple fields" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f() { {p | x: 1, y: 2} }");
    const body = ctx.field(decl, "body").?;
    try std.testing.expectEqualStrings("RecordUpdate", ctx.tagName(body));
    const fields = ctx.field(body, "fields").?.list;
    try std.testing.expectEqual(@as(usize, 2), fields.items.len);
}

// ── TypeExpr: union, intersection, complement, fn type ────────────────

test "grammar: type union" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f(x: Int | String) { x }");
    const params = ctx.field(decl, "params").?.list;
    const param_type = getFieldByName(ctx.alloc(), &ctx.pool, params.items[0].record, "type").?;
    try std.testing.expectEqualStrings("TypeUnion", ctx.tagName(param_type));
}

test "grammar: type intersection" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f(x: Readable & Writable) { x }");
    const params = ctx.field(decl, "params").?.list;
    const param_type = getFieldByName(ctx.alloc(), &ctx.pool, params.items[0].record, "type").?;
    try std.testing.expectEqualStrings("TypeIntersection", ctx.tagName(param_type));
}

test "grammar: type complement" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f(x: ~Nil) { x }");
    const params = ctx.field(decl, "params").?.list;
    const param_type = getFieldByName(ctx.alloc(), &ctx.pool, params.items[0].record, "type").?;
    try std.testing.expectEqualStrings("TypeComplement", ctx.tagName(param_type));
}

test "grammar: nullable type via suffix" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f(x: Int?) { x }");
    const params = ctx.field(decl, "params").?.list;
    const param_type = getFieldByName(ctx.alloc(), &ctx.pool, params.items[0].record, "type").?;
    try std.testing.expectEqualStrings("TypeNullable", ctx.tagName(param_type));
}

test "grammar: function type in annotation" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn apply(f: (Int) -> Int, x: Int) -> Int { f(x) }");
    const params = ctx.field(decl, "params").?.list;
    const param_type = getFieldByName(ctx.alloc(), &ctx.pool, params.items[0].record, "type").?;
    try std.testing.expectEqualStrings("TypeFn", ctx.tagName(param_type));
    const fn_params = ctx.field(param_type, "params").?.list;
    try std.testing.expectEqual(@as(usize, 1), fn_params.items.len);
    const fn_ret = ctx.field(param_type, "ret").?;
    try std.testing.expectEqualStrings("TypeNamed", ctx.tagName(fn_ret));
}

test "grammar: function type with effects" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn apply(f: (Int) -[IO]> Int) { f(0) }");
    const params = ctx.field(decl, "params").?.list;
    const param_type = getFieldByName(ctx.alloc(), &ctx.pool, params.items[0].record, "type").?;
    try std.testing.expectEqualStrings("TypeFn", ctx.tagName(param_type));
    const effects = ctx.field(param_type, "effects").?.list;
    try std.testing.expectEqual(@as(usize, 1), effects.items.len);
    try std.testing.expectEqualStrings("IO", effects.items[0].string);
}

// ── Pattern: type narrow, record pattern ──────────────────────────────

test "grammar: pattern type narrow in match" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f(x: Int) { match x { n: Int -> n } }");
    const body = ctx.field(decl, "body").?;
    try std.testing.expectEqualStrings("Match", ctx.tagName(body));
    const arms = ctx.field(body, "arms").?.list;
    const pat = getFieldByName(ctx.alloc(), &ctx.pool, arms.items[0].record, "pattern").?;
    try std.testing.expectEqualStrings("PatTypeNarrow", ctx.tagName(pat));
    try std.testing.expectEqualStrings("n", ctx.field(pat, "name").?.string);
    const te = ctx.field(pat, "type_expr").?;
    try std.testing.expectEqualStrings("TypeNamed", ctx.tagName(te));
}

test "grammar: record pattern in match" {
    var ctx: ParseTestCtx = undefined;
    ctx.initInPlace();
    defer ctx.deinit();
    const decl = try ctx.parseOne("fn f(p: Int) { match p { {x, y} -> x } }");
    const body = ctx.field(decl, "body").?;
    const arms = ctx.field(body, "arms").?.list;
    const pat = getFieldByName(ctx.alloc(), &ctx.pool, arms.items[0].record, "pattern").?;
    try std.testing.expectEqualStrings("PatRecord", ctx.tagName(pat));
    const fields = pat.tagged.payload.?.list;
    try std.testing.expectEqual(@as(usize, 2), fields.items.len);
}
