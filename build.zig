const std = @import("std");

const SRC = "src";
const ROOT = SRC ++ "/main.zig";
const ASSETS = "assets";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const macos_sdk = if (target.result.os.tag == .macos)
        b.lazyDependency("xcode_frameworks", .{}) orelse return
    else
        null;
    const root = Root{
        .b = b,
        .target = target,
        .optimize = optimize,
        .strip = b.option(bool, "strip", "Remove debug information from release binaries") orelse false,
        .raylib = b.dependency("raylib_zig", .{
            .target = target,
            .optimize = optimize,
            .linux_display_backend = .X11,
        }),
        .assets = assetNames(b),
        .macos_sdk = macos_sdk,
    };

    if (target.result.os.tag == .macos) fixMacosDpi(b, root.raylib.artifact("raylib"));

    if (target.result.os.tag == .linux) {
        // Zig 0.14.1 packs shared libraries into static archives; link them through the bindings instead.
        const links = &root.raylib.artifact("raylib").root_module.link_objects;
        const bindings = root.raylib.module("raylib");
        var i: usize = 0;
        while (i < links.items.len) {
            if (links.items[i] == .system_lib) {
                bindings.link_objects.append(b.allocator, links.orderedRemove(i)) catch @panic("OOM linking raylib");
            } else i += 1;
        }
    }

    const exe = b.addExecutable(.{ .name = "cistern", .root_module = root.module() });
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
    const run_tests = std.Build.Step.Run.create(b, "run test");
    run_tests.addArtifactArg(unit_tests);
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

fn fixMacosDpi(b: *std.Build, raylib: *std.Build.Step.Compile) void {
    const module = raylib.root_module;
    for (module.link_objects.items) |link| {
        if (link != .c_source_files) continue;
        const sources = link.c_source_files;
        for (sources.files, 0..) |name, i| {
            if (!std.mem.eql(u8, name, "src/rcore.c")) continue;
            const original = sources.root.path(b, name);
            const source = std.fs.cwd().readFileAlloc(b.allocator, original.getPath(b), 1 << 20) catch |err|
                std.debug.panic("Could not read raylib core: {s}", .{@errorName(err)});
            const old = "Vector2 scale = GetWindowScaleDPI();";
            const new = "Vector2 scale = IsWindowState(FLAG_WINDOW_HIGHDPI)? GetWindowScaleDPI() : (Vector2){ 1.0f, 1.0f };";
            if (std.mem.count(u8, source, old) != 7)
                @panic("Pinned raylib DPI code changed; review the macOS framebuffer fix");
            const patched = std.mem.replaceOwned(u8, b.allocator, source, old, new) catch @panic("OOM patching raylib");
            const generated = b.addWriteFiles().add("rcore.c", patched);
            const remaining = b.allocator.alloc([]const u8, sources.files.len - 1) catch @panic("OOM listing raylib sources");
            @memcpy(remaining[0..i], sources.files[0..i]);
            @memcpy(remaining[i..], sources.files[i + 1 ..]);
            sources.files = remaining;
            module.addIncludePath(original.dirname());
            module.addCSourceFile(.{ .file = generated, .flags = sources.flags, .language = sources.language });
            return;
        }
    }
    @panic("Pinned raylib core source missing; review the macOS framebuffer fix");
}

const Root = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    raylib: *std.Build.Dependency,
    assets: []const []const u8,
    macos_sdk: ?*std.Build.Dependency,

    fn module(r: Root) *std.Build.Module {
        const m = r.b.createModule(.{ .root_source_file = r.b.path(ROOT), .target = r.target, .optimize = r.optimize, .strip = r.strip });
        if (r.macos_sdk) |sdk| {
            m.addSystemFrameworkPath(sdk.path("Frameworks"));
            m.addSystemIncludePath(sdk.path("include"));
            m.addLibraryPath(sdk.path("lib"));
        }
        m.linkLibrary(r.raylib.artifact("raylib"));
        m.addImport("raylib", r.raylib.module("raylib"));
        for (r.assets) |name| m.addAnonymousImport(name, .{ .root_source_file = r.b.path(r.b.fmt(ASSETS ++ "/{s}", .{name})) });
        const listed = r.b.addOptions();
        listed.addOption([]const []const u8, "names", r.assets);
        m.addImport("assets", listed.createModule());
        return m;
    }
};

const EMBEDDED = [_][]const u8{ ".png", ".ttf", ".txt" };

/// Embedded by filename; `assets.names` lets callers check for optional artwork.
fn assetNames(b: *std.Build) []const []const u8 {
    var dir = b.build_root.handle.openDir(ASSETS, .{ .iterate = true }) catch |e|
        std.debug.panic(ASSETS ++ "/ could not be opened ({s})", .{@errorName(e)});
    defer dir.close();
    var names = std.ArrayList([]const u8).init(b.allocator);
    var it = dir.iterate();
    while (it.next() catch |e| std.debug.panic(ASSETS ++ "/ could not be listed ({s})", .{@errorName(e)})) |ent| {
        if (ent.kind != .file or !embedded(ent.name)) continue;
        names.append(b.dupe(ent.name)) catch @panic("OOM listing " ++ ASSETS ++ "/");
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lessThan);
    return names.items;
}

fn embedded(name: []const u8) bool {
    for (EMBEDDED) |ext| {
        if (std.mem.endsWith(u8, name, ext)) return true;
    }
    return false;
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

fn named(root: []const u8, want: []const u8) bool {
    var lines = std.mem.splitScalar(u8, root, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "//")) continue;
        if (std.mem.indexOf(u8, line, want) != null) return true;
    }
    return false;
}
