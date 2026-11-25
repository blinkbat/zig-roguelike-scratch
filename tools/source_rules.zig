const std = @import("std");

pub const Violation = struct { line: usize, imported: []const u8 };

fn listed(list: []const []const u8, path: []const u8) bool {
    for (list) |item| {
        if (std.mem.eql(u8, path, item)) return true;
    }
    return false;
}

const GAME_RULES = [_][]const u8{ "game/sim.zig", "game/attacks.zig", "game/rewards.zig", "game/foe_rules.zig" };

fn gameRules(path: []const u8) bool {
    return listed(&GAME_RULES, path);
}

const DOMAIN_EDIT = [_][]const u8{ "edit/preview.zig", "edit/plot_fields.zig" };

fn domain(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "play/") or std.mem.startsWith(u8, path, "map/") or
        gameRules(path) or listed(&DOMAIN_EDIT, path);
}

const INTERACTION = "edit/interaction.zig";
const TURN_SCHEDULE = "game/turn_schedule.zig";
const COMBAT_IMPACTS = "game/combat_impacts.zig";

const SPLIT_FROM = [_]struct { owners: []const []const u8, parent: []const u8 }{
    .{ .owners = &.{ "gfx/sprite_assets.zig", "gfx/sprite_materials.zig" }, .parent = "gfx/sprites.zig" },
    .{ .owners = &.{ "gfx/impact_queue.zig", "gfx/effect_state.zig", "gfx/status_marks.zig" }, .parent = "gfx/fx.zig" },
    .{ .owners = &.{ "core/input_bindings.zig", "core/input_names.zig" }, .parent = "core/input.zig" },
    .{ .owners = &.{ "gfx/light_model.zig", "gfx/light_gpu.zig" }, .parent = "gfx/light.zig" },
};

const INDEPENDENT = [_][]const u8{
    "game/projectile_motion.zig",
    "edit/widgets.zig",
    "edit/thumbnails.zig",
    "edit/tool_catalog.zig",
    "edit/name_field.zig",
    "edit/history.zig",
    "edit/text_catalog.zig",
    "ui/character_view.zig",
    "ui/character_layout.zig",
    "ui/character_stats.zig",
    "ui/item_card.zig",
} ++ blk: {
    var owners: []const []const u8 = &.{};
    for (SPLIT_FROM) |split| owners = owners ++ split.owners;
    break :blk owners[0..owners.len].*;
};

fn governed(owner: []const u8) bool {
    return domain(owner) or listed(&INDEPENDENT, owner) or listed(&.{ INTERACTION, TURN_SCHEDULE, COMBAT_IMPACTS }, owner);
}

fn allowed(owner: []const u8, target: []const u8) bool {
    if (!governed(owner)) return true;
    if (std.mem.eql(u8, owner, TURN_SCHEDULE)) {
        return std.mem.eql(u8, target, "std") or std.mem.startsWith(u8, target, "core/") or std.mem.startsWith(u8, target, "play/");
    }
    if (std.mem.eql(u8, owner, COMBAT_IMPACTS)) {
        return !listed(&.{ "game/combat.zig", "game/skills.zig", "game/foe_rules.zig" }, target);
    }
    for (SPLIT_FROM) |split| {
        if (listed(split.owners, owner) and std.mem.eql(u8, target, split.parent)) return false;
    }
    if (domain(owner)) {
        if (!std.mem.endsWith(u8, target, ".zig")) return !std.mem.eql(u8, target, "raylib");
        if (std.mem.eql(u8, owner, "game/attacks.zig") and gameRules(target))
            return std.mem.eql(u8, target, "game/sim.zig");
        return std.mem.startsWith(u8, target, "core/") or std.mem.startsWith(u8, target, "play/") or
            std.mem.startsWith(u8, target, "map/") or
            (gameRules(owner) and gameRules(target));
    }
    const interaction = std.mem.eql(u8, owner, INTERACTION);
    return (interaction or !std.mem.eql(u8, target, "edit/editor.zig")) and !std.mem.eql(u8, target, "game.zig") and
        !std.mem.startsWith(u8, target, "game/") and !std.mem.eql(u8, target, "app.zig") and
        (!std.mem.startsWith(u8, owner, "ui/") or !std.mem.eql(u8, target, "ui/book.zig"));
}

fn parse(alloc: std.mem.Allocator, source: [:0]const u8) !std.zig.Ast {
    var tree = try std.zig.Ast.parse(alloc, source, .zig);
    errdefer tree.deinit(alloc);
    if (tree.errors.len != 0) return error.InvalidSyntax;
    return tree;
}

fn isImport(tree: *const std.zig.Ast, token: u32) bool {
    return tree.tokens.items(.tag)[token] == .builtin and std.mem.eql(u8, tree.tokenSlice(token), "@import");
}

pub fn check(alloc: std.mem.Allocator, owner: []const u8, source: [:0]const u8) !?Violation {
    var tree = try parse(alloc, source);
    defer tree.deinit(alloc);
    if (tree.rootDecls().len == 0) return error.EmptyModule;
    if (!governed(owner)) return null;
    tokens: for (0..tree.tokens.len) |i| {
        const token: u32 = @intCast(i);
        if (!isImport(&tree, token)) continue;
        for (tree.nodes.items(.tag), 0..) |node_tag, n| {
            if (node_tag != .test_decl) continue;
            const node: u32 = @intCast(n);
            if (token >= tree.firstToken(node) and token <= tree.lastToken(node)) continue :tokens;
        }
        const literal = try importLiteral(&tree, token);
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

fn importLiteral(tree: *const std.zig.Ast, token: u32) ![]const u8 {
    const tags = tree.tokens.items(.tag);
    if (token + 3 >= tags.len or tags[token + 1] != .l_paren or tags[token + 2] != .string_literal) return error.NonliteralImport;
    const closing = token + 3 + @as(usize, @intFromBool(tags[token + 3] == .comma));
    if (closing >= tags.len or tags[closing] != .r_paren) return error.NonliteralImport;
    return tree.tokenSlice(token + 2);
}

pub fn testRoster(alloc: std.mem.Allocator, source: [:0]const u8) !std.StringHashMapUnmanaged(void) {
    var tree = try parse(alloc, source);
    defer tree.deinit(alloc);
    var roster: std.StringHashMapUnmanaged(void) = .{};
    errdefer roster.deinit(alloc);
    var found = false;
    for (tree.rootDecls()) |node| {
        if (tree.nodes.items(.tag)[node] != .test_decl or tree.nodes.items(.data)[node].lhs != 0) continue;
        found = true;
        for (tree.firstToken(node)..tree.lastToken(node) + 1) |i| {
            const token: u32 = @intCast(i);
            if (!isImport(&tree, token)) continue;
            const literal = try importLiteral(&tree, token);
            try roster.put(alloc, literal[1 .. literal.len - 1], {});
        }
    }
    if (!found) return error.MissingRoster;
    return roster;
}

test "the test roster counts import tokens inside unnamed tests only" {
    const alloc = std.testing.allocator;
    var roster = try testRoster(alloc, "const live = @import(\"live.zig\");\n" ++
        "test \"named\" { _ = @import(\"named.zig\"); }\n" ++
        "test {\n    // @import(\"comment.zig\")\n" ++
        "    _ =\n    \\\\@import(\"text.zig\")\n    ;\n" ++
        "    _ = @import(\"actual.zig\");\n}\n");
    defer roster.deinit(alloc);
    try std.testing.expectEqual(@as(u32, 1), roster.count());
    try std.testing.expect(roster.contains("actual.zig"));
    try std.testing.expectError(error.MissingRoster, testRoster(alloc, "test \"named\" {}"));
}

test "source validation accepts small modules and rejects empty or truncated source in every layer" {
    const alloc = std.testing.allocator;
    for ([_][]const u8{ "play/items.zig", "game/combat.zig", "ui/book.zig" }) |owner| {
        try std.testing.expect((try check(alloc, owner, "pub const answer = 42;")) == null);
        try std.testing.expectError(error.EmptyModule, check(alloc, owner, ""));
        try std.testing.expectError(error.EmptyModule, check(alloc, owner, "// padding\n" ** 60));
        try std.testing.expectError(error.InvalidSyntax, check(alloc, owner, "// padding\n" ** 60 ++ "pub fn broken() void {"));
    }
}

test "attack resolution cannot import death rewards or foe turn coordination" {
    const alloc = std.testing.allocator;
    try std.testing.expect((try check(alloc, "game/attacks.zig", "const sim = @import(\"sim.zig\");")) == null);
    try std.testing.expect((try check(alloc, "game/attacks.zig", "const rewards = @import(\"rewards.zig\");")) != null);
    try std.testing.expect((try check(alloc, "game/attacks.zig", "const foes = @import(\"foe_rules.zig\");")) != null);
}

test "turn scheduling stays independent and impact resolution cannot call its combat coordinator" {
    const alloc = std.testing.allocator;
    for ([_][:0]const u8{
        "const parent = @import(\"presentation.zig\");",
        "const game = @import(\"../game.zig\");",
        "const sim = @import(\"sim.zig\");",
        "const renderer = @import(\"../gfx/fx.zig\");",
        "const device = @import(\"raylib\");",
    }) |source| try std.testing.expect((try check(alloc, TURN_SCHEDULE, source)) != null);
    try std.testing.expect((try check(alloc, TURN_SCHEDULE, "const std = @import(\"std\"); const p = @import(\"../core/mathx.zig\"); const actor = @import(\"../play/actor.zig\");")) == null);
    for ([_][:0]const u8{
        "const parent = @import(\"combat.zig\");",
        "const skills = @import(\"skills.zig\");",
        "const foes = @import(\"foe_rules.zig\");",
    }) |source| try std.testing.expect((try check(alloc, COMBAT_IMPACTS, source)) != null);
    try std.testing.expect((try check(alloc, COMBAT_IMPACTS, "const rules = @import(\"attacks.zig\"); const rewards = @import(\"rewards.zig\"); const game = @import(\"../game.zig\");")) == null);
}

test "source boundaries reject rendering and application imports in domain code" {
    const alloc = std.testing.allocator;
    for (GAME_RULES ++ DOMAIN_EDIT ++ [_][]const u8{ "play/items.zig", "play/item_bases.zig", "play/affixes.zig", "play/loot.zig", "play/gear.zig", "play/inventory.zig", "play/ground_items.zig", "map/atlas.zig" }) |owner| {
        for ([_][:0]const u8{
            "const bad = @import(\"../ui/menu.zig\");",
            "const bad = @import(\"../gfx/look.zig\");",
            "const bad = @import(\"../edit/editor.zig\");",
            "const bad = @import(\"../game.zig\");",
            "const bad = @import(\"raylib\");",
        }) |source| {
            try std.testing.expect((try check(alloc, owner, source)) != null);
        }
        try std.testing.expect((try check(alloc, owner, "const ok = @import(\"../core/wording.zig\");")) == null);
    }
    try std.testing.expect((try check(alloc, "game/projectile_motion.zig", "const bad = @import(\"presentation.zig\");")) != null);
    try std.testing.expect((try check(alloc, "edit/plot_fields.zig", "const bad = @import(\"plot.zig\");")) != null);
    for (SPLIT_FROM) |split| for (split.owners) |owner| {
        const source = try std.fmt.allocPrintZ(alloc, "const parent = @import(\"{s}\");", .{std.fs.path.basenamePosix(split.parent)});
        defer alloc.free(source);
        try std.testing.expect((try check(alloc, owner, source)) != null);
    };
    try std.testing.expect((try check(alloc, "play/items.zig", "const bad = @import(\"../core/../ui/menu.zig\");")) != null);
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
}
