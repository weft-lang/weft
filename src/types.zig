const std = @import("std");
const Allocator = std.mem.Allocator;
const Arena = @import("arena.zig").Arena;
const intern_mod = @import("intern.zig");
const InternedString = intern_mod.InternedString;

// ── ID types ────────────────────────────────────────────────────────────

pub const TypeVarId = enum(u32) {
    _,

    pub fn index(self: TypeVarId) u32 {
        return @intFromEnum(self);
    }
};

// ── Effect sets ─────────────────────────────────────────────────────────

pub const EffectSet = struct {
    /// Sorted by InternedString index. Empty = pure.
    effects: []const InternedString,
    /// Open effect variable for polymorphism (null = closed/pure).
    tail_var: ?u32,

    pub const pure: EffectSet = .{ .effects = &.{}, .tail_var = null };

    /// Returns true if self's effects are a subset of other's effects.
    pub fn isSubset(self: EffectSet, other: EffectSet) bool {
        // Pure is subset of everything.
        if (self.effects.len == 0 and self.tail_var == null) return true;

        // Check concrete effects: every effect in self must appear in other.
        for (self.effects) |e| {
            var found = false;
            for (other.effects) |o| {
                if (e == o) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }

        // Both closed: concrete subset check is sufficient.
        if (self.tail_var == null and other.tail_var == null) return true;

        // Self is open, other is closed: not a subset (self could have more effects).
        if (self.tail_var != null and other.tail_var == null) return false;

        // Self is closed, other is open: valid (open absorbs more).
        if (self.tail_var == null and other.tail_var != null) return true;

        // Both open: same tail variable required (conservative).
        return self.tail_var.? == other.tail_var.?;
    }
};

// ── Type representation ─────────────────────────────────────────────────

pub const BinaryPayload = struct {
    left: *const Type,
    right: *const Type,
};

pub const Field = struct {
    name: InternedString,
    ty: *const Type,
};

pub const RecordType = struct {
    name: InternedString,
    fields: []const Field,
};

pub const AnonRecordType = struct {
    fields: []const Field,
    open: bool,
};

pub const Variant = struct {
    tag: InternedString,
    payloads: []const *const Type,
};

pub const TaggedType = struct {
    name: InternedString,
    variants: []const Variant,
};

pub const FunctionType = struct {
    params: []const *const Type,
    return_type: *const Type,
    effects: EffectSet,
};

pub const AppType = struct {
    constructor: InternedString,
    args: []const *const Type,
};

pub const Type = union(enum) {
    // Primitives (14, matching kernel.md §1)
    int,
    int8,
    int16,
    int32,
    uint8,
    uint16,
    uint32,
    uint64,
    float,
    float32,
    bool_type,
    string,
    nil,
    never,

    // Set-theoretic operations
    union_type: BinaryPayload,
    intersection: BinaryPayload,
    complement: *const Type,

    // Compound types
    record: RecordType,
    anon_record: AnonRecordType,
    tagged: TaggedType,
    function: FunctionType,
    unique: *const Type,
    type_var: TypeVarId,
    app: AppType,

    /// Returns a tag for fast disjointness checking.
    /// Scalar primitives (0-13) with different tags are always disjoint.
    /// Set operations and type vars return null.
    pub fn primitiveTag(self: *const Type) ?u8 {
        return switch (self.*) {
            .int => 0,
            .int8 => 1,
            .int16 => 2,
            .int32 => 3,
            .uint8 => 4,
            .uint16 => 5,
            .uint32 => 6,
            .uint64 => 7,
            .float => 8,
            .float32 => 9,
            .bool_type => 10,
            .string => 11,
            .nil => 12,
            .never => 13,
            .record => 14,
            .anon_record => 15,
            .tagged => 16,
            .function => 17,
            .unique => 18,
            .app => 19,
            .union_type, .intersection, .complement, .type_var => null,
        };
    }
};

// ── Type equality ───────────────────────────────────────────────────────

pub fn typeEqual(a: *const Type, b: *const Type) bool {
    if (a == b) return true;

    const tag_a = std.meta.activeTag(a.*);
    const tag_b = std.meta.activeTag(b.*);
    if (tag_a != tag_b) return false;

    return switch (a.*) {
        // Payload-less primitives: discriminant match is sufficient.
        .int, .int8, .int16, .int32, .uint8, .uint16, .uint32, .uint64, .float, .float32, .bool_type, .string, .nil, .never => true,

        .union_type => |au| typeEqual(au.left, b.union_type.left) and typeEqual(au.right, b.union_type.right),
        .intersection => |ai| typeEqual(ai.left, b.intersection.left) and typeEqual(ai.right, b.intersection.right),
        .complement => |ac| typeEqual(ac, b.complement),
        .unique => |au| typeEqual(au, b.unique),
        .type_var => |av| av == b.type_var,
        .function => |af| blk: {
            const bf = b.function;
            if (af.params.len != bf.params.len) break :blk false;
            for (af.params, bf.params) |ap, bp| {
                if (!typeEqual(ap, bp)) break :blk false;
            }
            if (!typeEqual(af.return_type, bf.return_type)) break :blk false;
            break :blk effectSetEqual(af.effects, bf.effects);
        },
        .record => |ar| blk: {
            const br = b.record;
            if (ar.name != br.name) break :blk false;
            if (ar.fields.len != br.fields.len) break :blk false;
            for (ar.fields, br.fields) |af, bf| {
                if (af.name != bf.name) break :blk false;
                if (!typeEqual(af.ty, bf.ty)) break :blk false;
            }
            break :blk true;
        },
        .anon_record => |ar| blk: {
            const br = b.anon_record;
            if (ar.open != br.open) break :blk false;
            if (ar.fields.len != br.fields.len) break :blk false;
            for (ar.fields, br.fields) |af, bf| {
                if (af.name != bf.name) break :blk false;
                if (!typeEqual(af.ty, bf.ty)) break :blk false;
            }
            break :blk true;
        },
        .tagged => |at| blk: {
            const bt = b.tagged;
            if (at.name != bt.name) break :blk false;
            if (at.variants.len != bt.variants.len) break :blk false;
            for (at.variants, bt.variants) |av, bv| {
                if (av.tag != bv.tag) break :blk false;
                if (av.payloads.len != bv.payloads.len) break :blk false;
                for (av.payloads, bv.payloads) |ap, bp| {
                    if (!typeEqual(ap, bp)) break :blk false;
                }
            }
            break :blk true;
        },
        .app => |aa| blk: {
            const ba = b.app;
            if (aa.constructor != ba.constructor) break :blk false;
            if (aa.args.len != ba.args.len) break :blk false;
            for (aa.args, ba.args) |aarg, barg| {
                if (!typeEqual(aarg, barg)) break :blk false;
            }
            break :blk true;
        },
    };
}

fn effectSetEqual(a: EffectSet, b_set: EffectSet) bool {
    if (a.effects.len != b_set.effects.len) return false;
    if (a.tail_var != b_set.tail_var) return false;
    for (a.effects, b_set.effects) |ae, be| {
        if (ae != be) return false;
    }
    return true;
}

// ── TypeContext ──────────────────────────────────────────────────────────

pub const TypeContext = struct {
    arena: Arena,

    pub fn init(backing: Allocator) TypeContext {
        return .{ .arena = Arena.init(backing) };
    }

    pub fn deinit(self: *TypeContext) void {
        self.arena.deinit();
    }

    fn put(self: *TypeContext, ty: Type) !*const Type {
        const ptr = try self.arena.create(Type);
        ptr.* = ty;
        return ptr;
    }

    fn dupeTypes(self: *TypeContext, types: []const *const Type) ![]const *const Type {
        if (types.len == 0) return &.{};
        const result = try self.arena.alloc(*const Type, types.len);
        @memcpy(result, types);
        return result;
    }

    fn dupeFields(self: *TypeContext, fields: []const Field) ![]const Field {
        if (fields.len == 0) return &.{};
        const result = try self.arena.alloc(Field, fields.len);
        @memcpy(result, fields);
        return result;
    }

    fn dupeVariants(self: *TypeContext, variants: []const Variant) ![]const Variant {
        if (variants.len == 0) return &.{};
        const result = try self.arena.alloc(Variant, variants.len);
        @memcpy(result, variants);
        return result;
    }

    fn dupeEffects(self: *TypeContext, effects: []const InternedString) ![]const InternedString {
        if (effects.len == 0) return &.{};
        const result = try self.arena.alloc(InternedString, effects.len);
        @memcpy(result, effects);
        return result;
    }

    // ── Primitives ──────────────────────────────────────────────────

    pub fn makeInt(self: *TypeContext) !*const Type {
        return self.put(.int);
    }
    pub fn makeInt8(self: *TypeContext) !*const Type {
        return self.put(.int8);
    }
    pub fn makeInt16(self: *TypeContext) !*const Type {
        return self.put(.int16);
    }
    pub fn makeInt32(self: *TypeContext) !*const Type {
        return self.put(.int32);
    }
    pub fn makeUInt8(self: *TypeContext) !*const Type {
        return self.put(.uint8);
    }
    pub fn makeUInt16(self: *TypeContext) !*const Type {
        return self.put(.uint16);
    }
    pub fn makeUInt32(self: *TypeContext) !*const Type {
        return self.put(.uint32);
    }
    pub fn makeUInt64(self: *TypeContext) !*const Type {
        return self.put(.uint64);
    }
    pub fn makeFloat(self: *TypeContext) !*const Type {
        return self.put(.float);
    }
    pub fn makeFloat32(self: *TypeContext) !*const Type {
        return self.put(.float32);
    }
    pub fn makeBool(self: *TypeContext) !*const Type {
        return self.put(.bool_type);
    }
    pub fn makeString(self: *TypeContext) !*const Type {
        return self.put(.string);
    }
    pub fn makeNil(self: *TypeContext) !*const Type {
        return self.put(.nil);
    }
    pub fn makeNever(self: *TypeContext) !*const Type {
        return self.put(.never);
    }

    // ── Set operations ──────────────────────────────────────────────

    pub fn makeUnion(self: *TypeContext, left: *const Type, right: *const Type) !*const Type {
        return self.put(.{ .union_type = .{ .left = left, .right = right } });
    }

    pub fn makeIntersection(self: *TypeContext, left: *const Type, right: *const Type) !*const Type {
        return self.put(.{ .intersection = .{ .left = left, .right = right } });
    }

    pub fn makeComplement(self: *TypeContext, inner: *const Type) !*const Type {
        return self.put(.{ .complement = inner });
    }

    // ── Compound types ──────────────────────────────────────────────

    pub fn makeFunction(self: *TypeContext, params: []const *const Type, return_type: *const Type, effects: EffectSet) !*const Type {
        return self.put(.{ .function = .{
            .params = try self.dupeTypes(params),
            .return_type = return_type,
            .effects = .{
                .effects = try self.dupeEffects(effects.effects),
                .tail_var = effects.tail_var,
            },
        } });
    }

    pub fn makeUnique(self: *TypeContext, inner: *const Type) !*const Type {
        return self.put(.{ .unique = inner });
    }

    pub fn makeRecord(self: *TypeContext, name: InternedString, fields: []const Field) !*const Type {
        return self.put(.{ .record = .{
            .name = name,
            .fields = try self.dupeFields(fields),
        } });
    }

    pub fn makeAnonRecord(self: *TypeContext, fields: []const Field, open: bool) !*const Type {
        return self.put(.{ .anon_record = .{
            .fields = try self.dupeFields(fields),
            .open = open,
        } });
    }

    pub fn makeTagged(self: *TypeContext, name: InternedString, variants: []const Variant) !*const Type {
        return self.put(.{ .tagged = .{
            .name = name,
            .variants = try self.dupeVariants(variants),
        } });
    }

    pub fn makeTypeVar(self: *TypeContext, id: TypeVarId) !*const Type {
        return self.put(.{ .type_var = id });
    }

    pub fn makeApp(self: *TypeContext, constructor: InternedString, args: []const *const Type) !*const Type {
        return self.put(.{ .app = .{
            .constructor = constructor,
            .args = try self.dupeTypes(args),
        } });
    }
};

// ── DNF normalization ───────────────────────────────────────────────────

pub const DnfClause = struct {
    positive: []const *const Type,
    negative: []const *const Type,
};

pub const Dnf = struct {
    clauses: []const DnfClause,
};

const MAX_DEPTH: u32 = 64;

pub fn toDnf(ty: *const Type, gpa: Allocator, depth: u32) !Dnf {
    if (depth >= MAX_DEPTH) {
        return dnfAtom(ty, gpa);
    }

    switch (ty.*) {
        .union_type => |u| {
            const left = try toDnf(u.left, gpa, depth + 1);
            const right = try toDnf(u.right, gpa, depth + 1);
            const combined = try gpa.alloc(DnfClause, left.clauses.len + right.clauses.len);
            @memcpy(combined[0..left.clauses.len], left.clauses);
            @memcpy(combined[left.clauses.len..], right.clauses);
            if (left.clauses.len > 0) gpa.free(left.clauses);
            if (right.clauses.len > 0) gpa.free(right.clauses);
            return .{ .clauses = combined };
        },
        .intersection => |inter| {
            const left = try toDnf(inter.left, gpa, depth + 1);
            const right = try toDnf(inter.right, gpa, depth + 1);
            var result = std.ArrayListUnmanaged(DnfClause).empty;
            for (left.clauses) |cl| {
                for (right.clauses) |cr| {
                    const pos = try concat(gpa, cl.positive, cr.positive);
                    const neg = try concat(gpa, cl.negative, cr.negative);
                    try result.append(gpa, .{ .positive = pos, .negative = neg });
                }
            }
            freeDnf(gpa, left);
            freeDnf(gpa, right);
            const owned = try result.toOwnedSlice(gpa);
            return .{ .clauses = owned };
        },
        .complement => |inner| {
            // Bootstrap simplification: single negative atom.
            const neg = try gpa.alloc(*const Type, 1);
            neg[0] = inner;
            const clause = try gpa.alloc(DnfClause, 1);
            clause[0] = .{ .positive = &.{}, .negative = neg };
            return .{ .clauses = clause };
        },
        else => return dnfAtom(ty, gpa),
    }
}

fn dnfAtom(ty: *const Type, gpa: Allocator) !Dnf {
    const pos = try gpa.alloc(*const Type, 1);
    pos[0] = ty;
    const clause = try gpa.alloc(DnfClause, 1);
    clause[0] = .{ .positive = pos, .negative = &.{} };
    return .{ .clauses = clause };
}

fn concat(gpa: Allocator, a: []const *const Type, b: []const *const Type) ![]const *const Type {
    if (a.len == 0) {
        if (b.len == 0) return &.{};
        const result = try gpa.alloc(*const Type, b.len);
        @memcpy(result, b);
        return result;
    }
    if (b.len == 0) {
        const result = try gpa.alloc(*const Type, a.len);
        @memcpy(result, a);
        return result;
    }
    const result = try gpa.alloc(*const Type, a.len + b.len);
    @memcpy(result[0..a.len], a);
    @memcpy(result[a.len..], b);
    return result;
}

pub fn freeDnf(gpa: Allocator, dnf: Dnf) void {
    for (dnf.clauses) |clause| {
        if (clause.positive.len > 0) gpa.free(clause.positive);
        if (clause.negative.len > 0) gpa.free(clause.negative);
    }
    if (dnf.clauses.len > 0) gpa.free(dnf.clauses);
}

// ── isEmpty ─────────────────────────────────────────────────────────────

pub fn isEmpty(ty: *const Type, _: *TypeContext, gpa: Allocator) !bool {
    if (ty.* == .never) return true;

    const dnf = try toDnf(ty, gpa, 0);
    defer freeDnf(gpa, dnf);

    if (dnf.clauses.len == 0) return true;

    for (dnf.clauses) |clause| {
        if (!clauseIsUnsatisfiable(clause)) return false;
    }
    return true;
}

fn clauseIsUnsatisfiable(clause: DnfClause) bool {
    // 1. Never in positive position.
    for (clause.positive) |p| {
        if (p.* == .never) return true;
    }

    // 2. Same atom in positive and negative (T & ~T = empty).
    for (clause.positive) |p| {
        for (clause.negative) |n| {
            if (typeEqual(p, n)) return true;
        }
    }

    // 3. Two distinct scalar primitives in positive (Int & Bool = empty).
    var seen_scalar_tag: ?u8 = null;
    for (clause.positive) |p| {
        if (p.primitiveTag()) |tag| {
            if (tag <= 13) { // scalar primitive range
                if (seen_scalar_tag) |prev| {
                    if (prev != tag) return true;
                } else {
                    seen_scalar_tag = tag;
                }
            }
        }
    }

    return false;
}

// ── isSubtype ───────────────────────────────────────────────────────────

pub const SubtypeError = Allocator.Error;

pub fn isSubtype(a: *const Type, b: *const Type, ctx: *TypeContext, gpa: Allocator) SubtypeError!bool {
    _ = ctx;
    // Fast: identical pointers.
    if (a == b) return true;

    // Fast: Never <: anything.
    if (a.* == .never) return true;

    // Fast: structural equality.
    if (typeEqual(a, b)) return true;

    // Unique<T> <: U if T <: U.
    if (a.* == .unique) {
        var tmp = TypeContext.init(gpa);
        defer tmp.deinit();
        return isSubtype(a.unique, b, &tmp, gpa);
    }

    // Function structural subtyping: contravariant params, covariant return, effect subset.
    if (a.* == .function and b.* == .function) {
        return functionSubtype(a.function, b.function, gpa);
    }

    // General: DNF clause subsumption.
    // Every clause of DNF(A) must be subsumed by some clause of DNF(B).
    const dnf_a = try toDnf(a, gpa, 0);
    defer freeDnf(gpa, dnf_a);
    const dnf_b = try toDnf(b, gpa, 0);
    defer freeDnf(gpa, dnf_b);

    // Empty A (no clauses) => A = Never <: anything.
    if (dnf_a.clauses.len == 0) return true;

    for (dnf_a.clauses) |ca| {
        // If clause A is unsatisfiable, it's vacuously subsumed.
        if (clauseIsUnsatisfiable(ca)) continue;

        var subsumed = false;
        for (dnf_b.clauses) |cb| {
            if (clauseSubsumes(cb, ca)) {
                subsumed = true;
                break;
            }
        }
        if (!subsumed) return false;
    }
    return true;
}

/// Does clause B subsume clause A?
/// P_b ⊆ P_a (B's positive requirements are a subset of A's)
/// AND N_a ⊆ N_b (A's negative requirements are a subset of B's)
fn clauseSubsumes(b: DnfClause, a: DnfClause) bool {
    // Every positive atom of B must appear in A's positive atoms.
    for (b.positive) |pb| {
        var found = false;
        for (a.positive) |pa| {
            if (typeEqual(pb, pa)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    // Every negative atom of A must appear in B's negative atoms.
    for (a.negative) |na| {
        var found = false;
        for (b.negative) |nb| {
            if (typeEqual(na, nb)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }

    return true;
}

fn functionSubtype(a: FunctionType, b: FunctionType, gpa: Allocator) SubtypeError!bool {
    if (a.params.len != b.params.len) return false;

    // Contravariant params: b.params[i] <: a.params[i]
    // Use a temporary TypeContext for any subtype checks that need it.
    var tmp_ctx = TypeContext.init(gpa);
    defer tmp_ctx.deinit();

    for (a.params, b.params) |ap, bp| {
        if (!try isSubtype(bp, ap, &tmp_ctx, gpa)) return false;
    }

    // Covariant return: a.return <: b.return
    if (!try isSubtype(a.return_type, b.return_type, &tmp_ctx, gpa)) return false;

    // Effect subset: a.effects ⊆ b.effects
    return a.effects.isSubset(b.effects);
}

// ── Tests ───────────────────────────────────────────────────────────────

test "types: all primitives constructible" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const primitives = .{
        try ctx.makeInt(),     try ctx.makeInt8(),    try ctx.makeInt16(),
        try ctx.makeInt32(),   try ctx.makeUInt8(),   try ctx.makeUInt16(),
        try ctx.makeUInt32(),  try ctx.makeUInt64(),  try ctx.makeFloat(),
        try ctx.makeFloat32(), try ctx.makeBool(),    try ctx.makeString(),
        try ctx.makeNil(),     try ctx.makeNever(),
    };
    inline for (primitives, 0..) |p, i| {
        try std.testing.expectEqual(@as(?u8, @intCast(i)), p.primitiveTag());
    }
}

test "types: set operation construction" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();

    const u = try ctx.makeUnion(int_t, str_t);
    try std.testing.expect(u.* == .union_type);
    try std.testing.expect(typeEqual(u.union_type.left, int_t));

    const i = try ctx.makeIntersection(int_t, str_t);
    try std.testing.expect(i.* == .intersection);

    const c = try ctx.makeComplement(int_t);
    try std.testing.expect(c.* == .complement);
}

test "types: nested set operations" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    // (Int | String) & ~Bool
    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const bool_t = try ctx.makeBool();
    const u = try ctx.makeUnion(int_t, str_t);
    const not_bool = try ctx.makeComplement(bool_t);
    const result = try ctx.makeIntersection(u, not_bool);
    try std.testing.expect(result.* == .intersection);
}

test "types: typeEqual" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const a = try ctx.makeInt();
    const b = try ctx.makeInt();
    const c = try ctx.makeString();
    try std.testing.expect(typeEqual(a, b));
    try std.testing.expect(!typeEqual(a, c));
}

test "types: DNF atom" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const dnf = try toDnf(int_t, gpa, 0);
    defer freeDnf(gpa, dnf);

    try std.testing.expectEqual(@as(usize, 1), dnf.clauses.len);
    try std.testing.expectEqual(@as(usize, 1), dnf.clauses[0].positive.len);
    try std.testing.expectEqual(@as(usize, 0), dnf.clauses[0].negative.len);
}

test "types: DNF union" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const u = try ctx.makeUnion(int_t, str_t);

    const dnf = try toDnf(u, gpa, 0);
    defer freeDnf(gpa, dnf);

    // Union of two atoms = 2 clauses.
    try std.testing.expectEqual(@as(usize, 2), dnf.clauses.len);
}

test "types: DNF intersection" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const i = try ctx.makeIntersection(int_t, str_t);

    const dnf = try toDnf(i, gpa, 0);
    defer freeDnf(gpa, dnf);

    // Intersection of two atoms = 1 clause with 2 positive atoms.
    try std.testing.expectEqual(@as(usize, 1), dnf.clauses.len);
    try std.testing.expectEqual(@as(usize, 2), dnf.clauses[0].positive.len);
}

test "types: isEmpty Never" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const never = try ctx.makeNever();
    try std.testing.expect(try isEmpty(never, &ctx, gpa));
}

test "types: isEmpty disjoint primitives" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const i = try ctx.makeIntersection(int_t, str_t);
    try std.testing.expect(try isEmpty(i, &ctx, gpa));
}

test "types: non-empty primitive" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    try std.testing.expect(!try isEmpty(int_t, &ctx, gpa));
}

test "types: T & ~T is empty" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const not_int = try ctx.makeComplement(int_t);
    const result = try ctx.makeIntersection(int_t, not_int);
    try std.testing.expect(try isEmpty(result, &ctx, gpa));
}

test "types: all pairs of scalar primitives are disjoint" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const makers = .{
        &TypeContext.makeInt,     &TypeContext.makeInt8,    &TypeContext.makeInt16,
        &TypeContext.makeInt32,   &TypeContext.makeUInt8,   &TypeContext.makeUInt16,
        &TypeContext.makeUInt32,  &TypeContext.makeUInt64,  &TypeContext.makeFloat,
        &TypeContext.makeFloat32, &TypeContext.makeBool,    &TypeContext.makeString,
        &TypeContext.makeNil,
    };

    var types: [makers.len]*const Type = undefined;
    inline for (makers, 0..) |maker, i| {
        types[i] = try maker(&ctx);
    }

    for (types, 0..) |a, i| {
        for (types, 0..) |b, j| {
            if (i == j) continue;
            const inter = try ctx.makeIntersection(a, b);
            try std.testing.expect(try isEmpty(inter, &ctx, gpa));
        }
    }
}

test "types: isSubtype reflexivity" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const bool_t = try ctx.makeBool();

    try std.testing.expect(try isSubtype(int_t, int_t, &ctx, gpa));
    try std.testing.expect(try isSubtype(str_t, str_t, &ctx, gpa));
    try std.testing.expect(try isSubtype(bool_t, bool_t, &ctx, gpa));
}

test "types: isSubtype union widening" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const u = try ctx.makeUnion(int_t, str_t);

    // Int <: Int | String
    try std.testing.expect(try isSubtype(int_t, u, &ctx, gpa));
    // String <: Int | String
    try std.testing.expect(try isSubtype(str_t, u, &ctx, gpa));
}

test "types: isSubtype disjoint primitives" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();

    try std.testing.expect(!try isSubtype(int_t, str_t, &ctx, gpa));
    try std.testing.expect(!try isSubtype(str_t, int_t, &ctx, gpa));
}

test "types: Never <: T" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const never = try ctx.makeNever();
    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const u = try ctx.makeUnion(int_t, str_t);

    try std.testing.expect(try isSubtype(never, int_t, &ctx, gpa));
    try std.testing.expect(try isSubtype(never, str_t, &ctx, gpa));
    try std.testing.expect(try isSubtype(never, u, &ctx, gpa));
}

test "types: Unique<T> <: T" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const unique_int = try ctx.makeUnique(int_t);

    try std.testing.expect(try isSubtype(unique_int, int_t, &ctx, gpa));
    try std.testing.expect(!try isSubtype(int_t, unique_int, &ctx, gpa));
}

test "types: nested Unique" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const uniq1 = try ctx.makeUnique(int_t);
    const uniq2 = try ctx.makeUnique(uniq1);

    // Unique<Unique<Int>> <: Int
    try std.testing.expect(try isSubtype(uniq2, int_t, &ctx, gpa));
}

test "types: function pure <: effectful" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    var pool = intern_mod.InternPool.init(gpa);
    defer pool.deinit(gpa);
    const io = try pool.intern(gpa, "IO");

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();

    const pure_fn = try ctx.makeFunction(&.{int_t}, str_t, EffectSet.pure);
    const io_fn = try ctx.makeFunction(&.{int_t}, str_t, .{ .effects = &.{io}, .tail_var = null });

    // (Int) -> String <: (Int) -[IO]> String
    try std.testing.expect(try isSubtype(pure_fn, io_fn, &ctx, gpa));
    // (Int) -[IO]> String NOT <: (Int) -> String
    try std.testing.expect(!try isSubtype(io_fn, pure_fn, &ctx, gpa));
}

test "types: effect set subset" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    var pool = intern_mod.InternPool.init(gpa);
    defer pool.deinit(gpa);
    const io = try pool.intern(gpa, "IO");
    const log = try pool.intern(gpa, "Log");

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();

    const io_fn = try ctx.makeFunction(&.{int_t}, str_t, .{ .effects = &.{io}, .tail_var = null });
    const io_log_fn = try ctx.makeFunction(&.{int_t}, str_t, .{ .effects = &.{ io, log }, .tail_var = null });

    // (Int) -[IO]> String <: (Int) -[IO, Log]> String
    try std.testing.expect(try isSubtype(io_fn, io_log_fn, &ctx, gpa));
    // NOT the reverse
    try std.testing.expect(!try isSubtype(io_log_fn, io_fn, &ctx, gpa));
}

test "types: EffectSet.isSubset" {
    const gpa = std.testing.allocator;
    var pool = intern_mod.InternPool.init(gpa);
    defer pool.deinit(gpa);

    const io = try pool.intern(gpa, "IO");
    const log = try pool.intern(gpa, "Log");

    // Pure subset of everything.
    try std.testing.expect(EffectSet.pure.isSubset(.{ .effects = &.{io}, .tail_var = null }));
    try std.testing.expect(EffectSet.pure.isSubset(EffectSet.pure));

    // {IO} subset of {IO, Log}.
    const io_set = EffectSet{ .effects = &.{io}, .tail_var = null };
    const io_log_set = EffectSet{ .effects = &.{ io, log }, .tail_var = null };
    try std.testing.expect(io_set.isSubset(io_log_set));

    // {IO, Log} NOT subset of {IO}.
    try std.testing.expect(!io_log_set.isSubset(io_set));

    // {IO} NOT subset of pure.
    try std.testing.expect(!io_set.isSubset(EffectSet.pure));

    // Closed subset of open.
    const open_io = EffectSet{ .effects = &.{io}, .tail_var = 0 };
    try std.testing.expect(io_set.isSubset(open_io));

    // Open NOT subset of closed.
    try std.testing.expect(!open_io.isSubset(io_set));
}

test "types: function contravariant params" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const int_or_str = try ctx.makeUnion(int_t, str_t);

    // (Int | String) -> Int <: (Int) -> Int
    // Because param is contravariant: Int <: Int | String
    const wide_param = try ctx.makeFunction(&.{int_or_str}, int_t, EffectSet.pure);
    const narrow_param = try ctx.makeFunction(&.{int_t}, int_t, EffectSet.pure);

    try std.testing.expect(try isSubtype(wide_param, narrow_param, &ctx, gpa));
    try std.testing.expect(!try isSubtype(narrow_param, wide_param, &ctx, gpa));
}

test "types: function covariant return" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const int_or_str = try ctx.makeUnion(int_t, str_t);

    // (Int) -> Int <: (Int) -> Int | String
    // Because return is covariant: Int <: Int | String
    const narrow_ret = try ctx.makeFunction(&.{int_t}, int_t, EffectSet.pure);
    const wide_ret = try ctx.makeFunction(&.{int_t}, int_or_str, EffectSet.pure);

    try std.testing.expect(try isSubtype(narrow_ret, wide_ret, &ctx, gpa));
    try std.testing.expect(!try isSubtype(wide_ret, narrow_ret, &ctx, gpa));
}

test "types: function reflexivity" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const f = try ctx.makeFunction(&.{int_t}, str_t, EffectSet.pure);

    try std.testing.expect(try isSubtype(f, f, &ctx, gpa));
}

test "types: union subset" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const int_t = try ctx.makeInt();
    const str_t = try ctx.makeString();
    const bool_t = try ctx.makeBool();
    const small = try ctx.makeUnion(int_t, str_t);
    const big = try ctx.makeUnion(small, bool_t);

    // Int | String <: Int | String | Bool
    try std.testing.expect(try isSubtype(small, big, &ctx, gpa));
    // NOT the reverse
    try std.testing.expect(!try isSubtype(big, small, &ctx, gpa));
}

test "types: Never <: function" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const never = try ctx.makeNever();
    const int_t = try ctx.makeInt();
    const f = try ctx.makeFunction(&.{int_t}, int_t, EffectSet.pure);

    try std.testing.expect(try isSubtype(never, f, &ctx, gpa));
}

test "types: deeply nested unions" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    // Build a chain: Int | Int | Int | ... (50 levels, well under MAX_DEPTH)
    var current = try ctx.makeInt();
    for (0..50) |_| {
        current = try ctx.makeUnion(current, try ctx.makeInt());
    }

    const dnf = try toDnf(current, gpa, 0);
    defer freeDnf(gpa, dnf);

    // Should produce 51 clauses (each union adds one).
    try std.testing.expectEqual(@as(usize, 51), dnf.clauses.len);
}

test "types: compound type construction" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    var pool = intern_mod.InternPool.init(gpa);
    defer pool.deinit(gpa);

    const user_name = try pool.intern(gpa, "User");
    const name_field = try pool.intern(gpa, "name");
    const age_field = try pool.intern(gpa, "age");

    const str_t = try ctx.makeString();
    const int_t = try ctx.makeInt();

    const record = try ctx.makeRecord(user_name, &.{
        .{ .name = name_field, .ty = str_t },
        .{ .name = age_field, .ty = int_t },
    });
    try std.testing.expect(record.* == .record);
    try std.testing.expectEqual(@as(usize, 2), record.record.fields.len);

    const shape_name = try pool.intern(gpa, "Shape");
    const circle_tag = try pool.intern(gpa, "Circle");
    const point_tag = try pool.intern(gpa, "Point");
    const float_t = try ctx.makeFloat();

    const tagged = try ctx.makeTagged(shape_name, &.{
        .{ .tag = circle_tag, .payloads = &.{float_t} },
        .{ .tag = point_tag, .payloads = &.{} },
    });
    try std.testing.expect(tagged.* == .tagged);
    try std.testing.expectEqual(@as(usize, 2), tagged.tagged.variants.len);
}

test "types: type variable" {
    const gpa = std.testing.allocator;
    var ctx = TypeContext.init(gpa);
    defer ctx.deinit();

    const tv: TypeVarId = @enumFromInt(0);
    const t = try ctx.makeTypeVar(tv);
    try std.testing.expect(t.* == .type_var);
    try std.testing.expect(t.primitiveTag() == null);
}
