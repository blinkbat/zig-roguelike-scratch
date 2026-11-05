const std = @import("std");

pub const Violation = struct { line: usize, imported: []const u8 };

fn listed(list: []const []const u8, path: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, path, item)) return true;
    }
    return false;
}

const GAME_RULES = [_][]const u8{ "game/sim.zig", "game/attacks.zig", "game/rewards.zig" };

fn gameRules(path: []const u8) bool {
    return listed(&GAME_RULES, path);
}

fn domain(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "play/") or std.mem.startsWith(u8, path, "map/") or
        gameRules(path) or std.mem.eql(u8, path, "edit/preview.zig");
}

const INDEPENDENT = [_][]const u8{
    "edit/widgets.zig",       "edit/thumbnails.zig",   "edit/tool_catalog.zig",   "edit/name_field.zig",
    "edit/history.zig",       "edit/text_catalog.zig", "ui/character_view.zig",   "ui/character_layout.zig",
    "ui/character_stats.zig", "ui/item_card.zig",      "core/input_bindings.zig", "core/input_names.zig",
    "gfx/light_model.zig",    "gfx/light_gpu.zig",     "gfx/sprite_assets.zig",   "gfx/sprite_materials.zig",
    "gfx/impact_queue.zig",   "gfx/effect_state.zig",
};

const SPLIT_FROM = [_]struct { owners: [2][]const u8, parent: []const u8 }{
    .{ .owners = .{ "gfx/sprite_assets.zig", "gfx/sprite_materials.zig" }, .parent = "gfx/sprites.zig" },
    .{ .owners = .{ "gfx/impact_queue.zig", "gfx/effect_state.zig" }, .parent = "gfx/fx.zig" },
    .{ .owners = .{ "core/input_bindings.zig", "core/input_names.zig" }, .parent = "core/input.zig" },
    .{ .owners = .{ "gfx/light_model.zig", "gfx/light_gpu.zig" }, .parent = "gfx/light.zig" },
};

fn allowed(owner: []const u8, target: []const u8) bool {
    for (SPLIT_FROM) |split| {
        if (listed(&split.owners, owner) and std.mem.eql(u8, target, split.parent)) return false;
    }
    if (domain(owner)) {
        if (!std.mem.endsWith(u8, target, ".zig")) return !std.mem.eql(u8, target, "raylib");
        return std.mem.startsWith(u8, target, "core/") or std.mem.startsWith(u8, target, "play/") or
            std.mem.startsWith(u8, target, "map/") or
            (gameRules(owner) and gameRules(target));
    }
    const interaction = std.mem.eql(u8, owner, "edit/interaction.zig");
    return (interaction or !std.mem.eql(u8, target, "edit/editor.zig")) and !std.mem.eql(u8, target, "game.zig") and
        !std.mem.startsWith(u8, target, "game/") and !std.mem.eql(u8, target, "app.zig") and
        (!std.mem.startsWith(u8, owner, "ui/") or !std.mem.eql(u8, target, "ui/book.zig"));
}

pub fn check(alloc: std.mem.Allocator, owner: []const u8, source: [:0]const u8) !?Violation {
    if (!domain(owner) and !listed(&INDEPENDENT, owner) and !std.mem.eql(u8, owner, "edit/interaction.zig")) return null;
    var tree = try std.zig.Ast.parse(alloc, source, .zig);
    defer tree.deinit(alloc);
    if (tree.errors.len != 0) return error.InvalidSyntax;
    const tags = tree.tokens.items(.tag);
    tokens: for (tags, 0..) |tag, i| {
        const token: u32 = @intCast(i);
        if (tag != .builtin or !std.mem.eql(u8, tree.tokenSlice(token), "@import")) continue;
        for (tree.nodes.items(.tag), 0..) |node_tag, n| {
            if (node_tag != .test_decl) continue;
            const node: u32 = @intCast(n);
            if (token >= tree.firstToken(node) and token <= tree.lastToken(node)) continue :tokens;
        }
        if (i + 3 >= tags.len or tags[i + 1] != .l_paren or tags[i + 2] != .string_literal) return error.NonliteralImport;
        const closing = i + 3 + @as(usize, @intFromBool(tags[i + 3] == .comma));
        if (closing >= tags.len or tags[closing] != .r_paren) return error.NonliteralImport;
        const literal = tree.tokenSlice(token + 2);
        const imported = try std.zig.string_literal.parseAlloc(alloc, literal);
        defer alloc.free(imported);
        std.mem.replaceScalar(u8, imported, '\\', '/');
        const resolved = try std.fs.path.resolvePosix(alloc, &.{ "/", std.fs.path.dirnamePosix(owner) orelse ".", imported });
        defer alloc.free(resolved);
        const target = if (std.mem.endsWith(u8, imported, ".zig")) resolved[1..] else imported;
        if (!allowed(owner, target)) return .{ .line = tree.tokenLocation(0, token).line + 1, .imported = literal };
    }
    return null;
}

test "source boundaries reject rendering and application imports in domain code" {
    const alloc = std.testing.allocator;
    var rejected: usize = 0;
    var kept: usize = 0;
    for ([_][]const u8{ "play/items.zig", "map/atlas.zig", "game/sim.zig", "game/attacks.zig", "game/rewards.zig", "edit/preview.zig" }) |owner| {
        for ([_][:0]const u8{
            "const bad = @import(\"../ui/menu.zig\");",
            "const bad = @import(\"../gfx/look.zig\");",
            "const bad = @import(\"../edit/editor.zig\");",
            "const bad = @import(\"../game.zig\");",
            "const bad = @import(\"raylib\");",
        }) |source| {
            try std.testing.expect((try check(alloc, owner, source)) != null);
            rejected += 1;
        }
        try std.testing.expect((try check(alloc, owner, "const ok = @import(\"../core/wording.zig\");")) == null);
        kept += 1;
    }
    try std.testing.expect((try check(alloc, "game/attacks.zig", "const sim = @import(\"sim.zig\");")) == null);
    kept += 1;
    for (SPLIT_FROM) |split| for (split.owners) |owner| {
        const source = try std.fmt.allocPrintZ(alloc, "const parent = @import(\"{s}\");", .{std.fs.path.basenamePosix(split.parent)});
        defer alloc.free(source);
        try std.testing.expect((try check(alloc, owner, source)) != null);
        rejected += 1;
    };
    try std.testing.expect((try check(alloc, "play/items.zig", "const bad = @import(\"../core/../ui/menu.zig\");")) != null);
    rejected += 1;
    std.debug.print("source boundaries: {d} forbidden imports rejected, {d} allowed imports retained\n", .{ rejected, kept });
}

test "source boundaries recognize real imports and permit integration tests" {
    const source =
        \\// @import("../ui/menu.zig")
        \\const sample = "@import(\"../ui/menu.zig\")";
        \\test "integration" { _ = @import("../game.zig"); }
        \\const Nested = struct { test "integration" { _ = @import("../gfx/look.zig"); } };
        \\const wording = @import("../core/wording.zig");
    ;
    const alloc = std.testing.allocator;
    try std.testing.expect((try check(alloc, "play/items.zig", source)) == null);
    try std.testing.expect((try check(alloc, "play/items.zig", "const good = @import(\"../core/wording.zig\",);")) == null);
    try std.testing.expectError(error.NonliteralImport, check(alloc, "play/items.zig", "const bad = @import(\"../ui/\" ++ \"menu.zig\");"));
    for (INDEPENDENT) |owner| {
        try std.testing.expect((try check(alloc, owner, "const bad = @import(\"../edit/editor.zig\");")) != null);
        try std.testing.expect((try check(alloc, owner, "const bad = @import(\"../game.zig\");")) != null);
        try std.testing.expect((try check(alloc, owner, "const good = @import(\"../gfx/raster.zig\");")) == null);
    }
    try std.testing.expect((try check(alloc, "ui/character_stats.zig", "const bad = @import(\"book.zig\");")) != null);
    try std.testing.expect((try check(alloc, "ui/item_card.zig", "const good = @import(\"character_layout.zig\");")) == null);
    try std.testing.expect((try check(alloc, "edit/interaction.zig", "const good = @import(\"editor.zig\");")) == null);
    try std.testing.expect((try check(alloc, "edit/interaction.zig", "const bad = @import(\"../game.zig\");")) != null);
    try std.testing.expect((try check(alloc, "edit/interaction.zig", "const bad = @import(\"../app.zig\");")) != null);
    const found = (try check(alloc, "play/items.zig", "const ok = 0;\nconst bad = @import(\"../ui/menu.zig\");")).?;
    try std.testing.expectEqual(@as(usize, 2), found.line);
    try std.testing.expectEqualStrings("\"../ui/menu.zig\"", found.imported);
    std.debug.print("source boundaries: comments, strings, nested tests, editor independence and diagnostics checked\n", .{});
}
