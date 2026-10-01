const std = @import("std");

const SRC = "src";
const ROOT = SRC ++ "/main.zig";
const ASSETS = "assets";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const root = Root{
        .b = b,
        .target = target,
        .optimize = optimize,
        .raylib = b.dependency("raylib_zig", .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = .X11,
        }),
        .assets = assetNames(b),
    };

    const exe = b.addExecutable(.{ .name = "roguelike", .root_module = root.module() });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Build and run");
    run_step.dependOn(&run_cmd.step);

    const test_filter = b.option([]const u8, "test-filter", "Run only tests whose name contains this");
    const unit_tests = b.addTest(.{
        .root_module = root.module(),
        .filters = if (test_filter) |f| &.{f} else &.{},
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    checkTestRoster(b);
    test_step.dependOn(&run_tests.step);

    // No step may install or run these two — Step.Compile passes -fno-emit-bin only while nothing asks for the binary.
    const check_step = b.step("check", "Type-check only — no codegen, no link, no binary");
    for ([_]*std.Build.Step.Compile{
        b.addExecutable(.{ .name = "check-exe", .root_module = root.module() }),
        b.addTest(.{ .root_module = root.module() }),
    }) |c| check_step.dependOn(&c.step);
}

const Root = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    raylib: *std.Build.Dependency,
    assets: []const []const u8,

    fn module(r: Root) *std.Build.Module {
        const m = r.b.createModule(.{ .root_source_file = r.b.path(ROOT), .target = r.target, .optimize = r.optimize });
        m.linkLibrary(r.raylib.artifact("raylib"));
        m.addImport("raylib", r.raylib.module("raylib"));
        for (r.assets) |name| m.addAnonymousImport(name, .{ .root_source_file = r.b.path(r.b.fmt(ASSETS ++ "/{s}", .{name})) });
        return m;
    }
};

/// Every PNG and TTF in `assets/` is embedded under its file name, so the exe runs from any directory. `@embedFile("<name>")` reads one.
fn assetNames(b: *std.Build) []const []const u8 {
    var dir = b.build_root.handle.openDir(ASSETS, .{ .iterate = true }) catch |e|
        std.debug.panic(ASSETS ++ "/ could not be opened ({s})", .{@errorName(e)});
    defer dir.close();
    var names = std.ArrayList([]const u8).init(b.allocator);
    var it = dir.iterate();
    while (it.next() catch |e| std.debug.panic(ASSETS ++ "/ could not be listed ({s})", .{@errorName(e)})) |ent| {
        if (ent.kind != .file or !(std.mem.endsWith(u8, ent.name, ".png") or std.mem.endsWith(u8, ent.name, ".ttf"))) continue;
        names.append(b.dupe(ent.name)) catch @panic("OOM listing " ++ ASSETS ++ "/");
    }
    return names.items;
}

const MIN_SRC: u64 = 512;

fn checkTestRoster(b: *std.Build) void {
    const file = b.build_root.handle.readFileAlloc(b.allocator, ROOT, 1 << 20) catch |e|
        std.debug.panic(ROOT ++ " could not be read ({s})", .{@errorName(e)});
    const at = std.mem.indexOf(u8, file, "\ntest {") orelse
        std.debug.panic(ROOT ++ " has no `test {{` block", .{});
    const root = file[at..];
    var dir = b.build_root.handle.openDir(SRC, .{ .iterate = true }) catch |e|
        std.debug.panic(SRC ++ "/ could not be opened ({s})", .{@errorName(e)});
    defer dir.close();
    var it = dir.walk(b.allocator) catch |e|
        std.debug.panic(SRC ++ "/ could not be walked ({s})", .{@errorName(e)});
    defer it.deinit();
    while (it.next() catch |e| std.debug.panic(SRC ++ "/ walk failed ({s})", .{@errorName(e)})) |ent| {
        if (ent.kind != .file or !std.mem.endsWith(u8, ent.path, ".zig")) continue;
        if (std.mem.eql(u8, ent.path, std.fs.path.basename(ROOT))) continue;
        const slashed = b.allocator.dupe(u8, ent.path) catch @panic("OOM in the roster check");
        std.mem.replaceScalar(u8, slashed, '\\', '/');
        const st = ent.dir.statFile(ent.basename) catch |e|
            std.debug.panic(SRC ++ "/{s} could not be stat'd ({s})", .{ slashed, @errorName(e) });
        if (st.size < MIN_SRC) std.debug.panic(SRC ++ "/{s} is {d} bytes — a truncated file, not a module", .{ slashed, st.size });
        const want = b.fmt("@import(\"{s}\")", .{slashed});
        if (!named(root, want)) {
            std.debug.panic(ROOT ++ "'s test block does not name {s}. Add `_ = {s};`.", .{ slashed, want });
        }
    }
}

/// On a line of the test block that is not commented out.
fn named(root: []const u8, want: []const u8) bool {
    var lines = std.mem.splitScalar(u8, root, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "//")) continue;
        if (std.mem.indexOf(u8, line, want) != null) return true;
    }
    return false;
}
