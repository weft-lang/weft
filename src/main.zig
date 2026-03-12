const std = @import("std");
const ir = @import("ir.zig");
const intern_mod = @import("intern.zig");
const InternPool = intern_mod.InternPool;
const interp_mod = @import("interp.zig");
const Interpreter = interp_mod.Interpreter;
const Value = interp_mod.Value;
const builtins_mod = @import("builtins.zig");
const grammar = @import("seed/grammar.zig");
const typeck = @import("seed/typeck.zig");
const lower = @import("seed/lower.zig");
const emit = @import("seed/emit.zig");

// Pull in all module tests.
comptime {
    _ = @import("arena.zig");
    _ = @import("intern.zig");
    _ = @import("span.zig");
    _ = @import("diag.zig");
    _ = @import("types.zig");
    _ = @import("ir.zig");
    _ = @import("interp.zig");
    _ = @import("builtins.zig");
    _ = @import("seed/gen.zig");
    _ = @import("seed/grammar.zig");
    _ = @import("seed/typeck.zig");
    _ = @import("seed/lower.zig");
    _ = @import("seed/emit.zig");
}

fn write(s: []const u8) void {
    _ = std.posix.write(std.posix.STDOUT_FILENO, s) catch {};
}

fn writeErr(s: []const u8) void {
    _ = std.posix.write(std.posix.STDERR_FILENO, s) catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        write("rhiz kernel v0.0.1\nUsage: rhiz <parse|check|compile> <file.rz>\n");
        return;
    }

    if (std.mem.eql(u8, args[1], "parse")) {
        if (args.len < 3) {
            writeErr("Error: parse requires a file argument\n");
            std.process.exit(1);
        }
        runParse(alloc, args[2]);
    } else if (std.mem.eql(u8, args[1], "check")) {
        if (args.len < 3) {
            writeErr("Error: check requires a file argument\n");
            std.process.exit(1);
        }
        runCheck(alloc, args[2]);
    } else if (std.mem.eql(u8, args[1], "compile")) {
        if (args.len < 3) {
            writeErr("Error: compile requires a file argument\n");
            std.process.exit(1);
        }
        // Default output: input with .rz replaced by empty, or "a.out"
        const output = if (args.len >= 5 and std.mem.eql(u8, args[3], "-o"))
            args[4]
        else
            "a.out";
        runCompile(alloc, args[2], output);
    } else {
        writeErr("Unknown command: ");
        writeErr(args[1]);
        writeErr("\n");
        std.process.exit(1);
    }
}

fn runParse(alloc: std.mem.Allocator, path: []const u8) void {
    // Read source file
    const source = std.fs.cwd().readFileAlloc(alloc, path, 10 * 1024 * 1024) catch {
        writeErr("Error reading file: ");
        writeErr(path);
        writeErr("\n");
        std.process.exit(1);
    };
    defer alloc.free(source);

    // Build grammar module
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();
    var pool = InternPool.init(a);
    const module, const funcs = grammar.buildModule(a, &pool) catch {
        writeErr("Error building grammar module\n");
        std.process.exit(1);
    };

    // Run parser
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    builtins_mod.registerAll(&interp) catch {
        writeErr("Error registering builtins\n");
        std.process.exit(1);
    };

    const result = interp.execFunc(funcs.parse, &.{.{ .string = source }}) catch {
        writeErr("Parse error\n");
        std.process.exit(1);
    };

    // Print AST
    const res_rec = result.record;
    const node_name = pool.intern(a, "node") catch unreachable;
    const node = getField(res_rec, node_name).?;

    // Format into a buffer and write
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    printValue(buf.writer(alloc), &pool, node, 0) catch {
        writeErr("Error formatting output\n");
        std.process.exit(1);
    };
    buf.append(alloc, '\n') catch {};
    write(buf.items);
}

fn runCheck(alloc: std.mem.Allocator, path: []const u8) void {
    // Read source file
    const source = std.fs.cwd().readFileAlloc(alloc, path, 10 * 1024 * 1024) catch {
        writeErr("Error reading file: ");
        writeErr(path);
        writeErr("\n");
        std.process.exit(1);
    };
    defer alloc.free(source);

    // Build grammar + typeck modules
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();
    var pool = InternPool.init(a);
    var builder = ir.Builder.init(a);

    const gram_funcs = grammar.generate(a, &builder, &pool) catch {
        writeErr("Error building grammar module\n");
        std.process.exit(1);
    };

    const f_check_module = typeck.generate(a, &builder, &pool) catch {
        writeErr("Error building typeck module\n");
        std.process.exit(1);
    };

    // Build a driver function that:
    // 1. Calls parse(source) -> {node, pos}
    // 2. Extracts the AST node
    // 3. Calls check_module(ast) -> typed module
    const Gen = @import("seed/gen.zig").Gen;
    var g = Gen.init(a, &builder, &pool);
    g.beginFunc("driver") catch unreachable;
    _ = g.beginBlock();
    const src_param = g.addParam() catch unreachable;

    // Parse
    const parse_result = g.callDirect(gram_funcs.parse, &.{src_param}) catch unreachable;
    const ast_node = g.recordField(parse_result, "node") catch unreachable;

    // Type check the parsed AST
    const typed_module = g.callDirect(f_check_module, &.{ast_node}) catch unreachable;
    g.ret(typed_module) catch unreachable;
    const driver_fid = g.endFunc() catch unreachable;
    const module = builder.build(driver_fid) catch {
        writeErr("Error building module\n");
        std.process.exit(1);
    };

    // Run
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    builtins_mod.registerAll(&interp) catch {
        writeErr("Error registering builtins\n");
        std.process.exit(1);
    };

    const result = interp.execFunc(driver_fid, &.{.{ .string = source }}) catch |err| {
        writeErr("Type check error: ");
        writeErr(@errorName(err));
        writeErr("\n");
        std.process.exit(1);
    };

    // Print typed AST
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(alloc);
    printValue(buf.writer(alloc), &pool, result, 0) catch {
        writeErr("Error formatting output\n");
        std.process.exit(1);
    };
    buf.append(alloc, '\n') catch {};
    write(buf.items);
}

fn runCompile(alloc: std.mem.Allocator, path: []const u8, output: []const u8) void {
    // Read source file
    const source = std.fs.cwd().readFileAlloc(alloc, path, 10 * 1024 * 1024) catch {
        writeErr("Error reading file: ");
        writeErr(path);
        writeErr("\n");
        std.process.exit(1);
    };
    defer alloc.free(source);

    // Build all seed modules: grammar + typeck + lower + emit
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const a = arena.allocator();
    var pool = InternPool.init(a);
    var builder = ir.Builder.init(a);

    const gram_funcs = grammar.generate(a, &builder, &pool) catch {
        writeErr("Error building grammar module\n");
        std.process.exit(1);
    };

    const f_check_module = typeck.generate(a, &builder, &pool) catch {
        writeErr("Error building typeck module\n");
        std.process.exit(1);
    };

    const f_lower_module = lower.generate(a, &builder, &pool) catch {
        writeErr("Error building lower module\n");
        std.process.exit(1);
    };

    const f_emit_module = emit.generate(a, &builder, &pool) catch {
        writeErr("Error building emit module\n");
        std.process.exit(1);
    };

    // Build driver: parse -> check -> lower -> emit -> write_file
    const Gen = @import("seed/gen.zig").Gen;
    var g = Gen.init(a, &builder, &pool);
    g.beginFunc("compile_driver") catch unreachable;
    _ = g.beginBlock();
    const src_param = g.addParam() catch unreachable;
    const out_param = g.addParam() catch unreachable;

    // Parse
    const parse_result = g.callDirect(gram_funcs.parse, &.{src_param}) catch unreachable;
    const ast_node = g.recordField(parse_result, "node") catch unreachable;
    const msg1 = g.constString("parse ok\n") catch unreachable;
    _ = g.callBuiltin("io_print", &.{msg1}) catch unreachable;

    // Type check
    const typed_mod = g.callDirect(f_check_module, &.{ast_node}) catch unreachable;
    const msg2 = g.constString("check ok\n") catch unreachable;
    _ = g.callBuiltin("io_print", &.{msg2}) catch unreachable;

    // Lower to IR repr
    const ir_mod = g.callDirect(f_lower_module, &.{typed_mod}) catch unreachable;
    const msg3 = g.constString("lower ok\n") catch unreachable;
    _ = g.callBuiltin("io_print", &.{msg3}) catch unreachable;

    // Emit native code (Mach-O)
    const binary = g.callDirect(f_emit_module, &.{ir_mod}) catch unreachable;
    const msg4 = g.constString("emit ok\n") catch unreachable;
    _ = g.callBuiltin("io_print", &.{msg4}) catch unreachable;

    // Write to file
    const write_result = g.callBuiltin("bytes_write_file", &.{ out_param, binary }) catch unreachable;
    g.ret(write_result) catch unreachable;
    const driver_fid = g.endFunc() catch unreachable;
    const module = builder.build(driver_fid) catch {
        writeErr("Error building module\n");
        std.process.exit(1);
    };

    // Run the compilation pipeline
    var interp = Interpreter.init(a, module, &pool);
    defer interp.deinit();
    builtins_mod.registerAll(&interp) catch {
        writeErr("Error registering builtins\n");
        std.process.exit(1);
    };

    _ = interp.execFunc(driver_fid, &.{ .{ .string = source }, .{ .string = output } }) catch |err| {
        writeErr("Compilation error: ");
        writeErr(@errorName(err));
        writeErr("\n");
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
        std.process.exit(1);
    };

    // Make output executable
    const out_file = std.fs.cwd().openFile(output, .{ .mode = .read_write }) catch {
        writeErr("Error opening output file\n");
        std.process.exit(1);
    };
    defer out_file.close();
    out_file.chmod(0o755) catch {};

    write("Compiled: ");
    write(path);
    write(" -> ");
    write(output);
    write("\n");
}

fn getField(rec: *const interp_mod.RecordValue, name: intern_mod.InternedString) ?Value {
    for (rec.fields) |f| {
        if (f.name == name) return f.value;
    }
    return null;
}

fn printValue(writer: anytype, pool: *const InternPool, val: Value, indent: u32) !void {
    switch (val) {
        .int => |v| try writer.print("{d}", .{v}),
        .float => |v| try writer.print("{d}", .{v}),
        .bool_val => |v| try writer.print("{}", .{v}),
        .string => |v| try writer.print("\"{s}\"", .{v}),
        .nil => try writer.print("nil", .{}),
        .tagged => |t| {
            const tag_name = pool.get(t.tag);
            if (t.payload) |p| {
                switch (p) {
                    .record => |rec| {
                        try writer.print("{s}(\n", .{tag_name});
                        for (rec.fields, 0..) |f, i| {
                            try printIndent(writer, indent + 1);
                            try writer.print("{s}: ", .{pool.get(f.name)});
                            try printValue(writer, pool, f.value, indent + 1);
                            if (i + 1 < rec.fields.len) try writer.print(",", .{});
                            try writer.print("\n", .{});
                        }
                        try printIndent(writer, indent);
                        try writer.print(")", .{});
                    },
                    .list => |lst| {
                        try writer.print("{s}[\n", .{tag_name});
                        for (lst.items, 0..) |item, i| {
                            try printIndent(writer, indent + 1);
                            try printValue(writer, pool, item, indent + 1);
                            if (i + 1 < lst.items.len) try writer.print(",", .{});
                            try writer.print("\n", .{});
                        }
                        try printIndent(writer, indent);
                        try writer.print("]", .{});
                    },
                    else => {
                        try writer.print("{s}(", .{tag_name});
                        try printValue(writer, pool, p, indent);
                        try writer.print(")", .{});
                    },
                }
            } else {
                try writer.print("{s}", .{tag_name});
            }
        },
        .list => |lst| {
            try writer.print("[\n", .{});
            for (lst.items, 0..) |item, i| {
                try printIndent(writer, indent + 1);
                try printValue(writer, pool, item, indent + 1);
                if (i + 1 < lst.items.len) try writer.print(",", .{});
                try writer.print("\n", .{});
            }
            try printIndent(writer, indent);
            try writer.print("]", .{});
        },
        .record => |rec| {
            try writer.print("{{\n", .{});
            for (rec.fields, 0..) |f, i| {
                try printIndent(writer, indent + 1);
                try writer.print("{s}: ", .{pool.get(f.name)});
                try printValue(writer, pool, f.value, indent + 1);
                if (i + 1 < rec.fields.len) try writer.print(",", .{});
                try writer.print("\n", .{});
            }
            try printIndent(writer, indent);
            try writer.print("}}", .{});
        },
        else => try writer.print("<value>", .{}),
    }
}

fn printIndent(writer: anytype, level: u32) !void {
    for (0..level) |_| {
        try writer.print("  ", .{});
    }
}
