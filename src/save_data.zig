const std = @import("std");
const game = @import("game.zig");
const atlas = @import("map/atlas.zig");
const hero = @import("play/hero.zig");
const menu = @import("ui/menu.zig");
const contains = @import("core/text.zig").contains;
const count = @import("core/text.zig").count;

/// Where in the game a saved field lives, `game` or its field of that name; the file names it by its field name alone.
pub const Part = enum { game, sim, pic };

fn Of(comptime p: Part) type {
    return if (p == .game) game.Game else @FieldType(game.Game, @tagName(p));
}

pub fn part(g: *game.Game, comptime p: Part) *Of(p) {
    return if (p == .game) g else &@field(g, @tagName(p));
}

const HEAD_PART: Part = .sim;
const Run = Of(HEAD_PART);

/// The legacy header also classifies the run's separately stored map and visits.
const Header = struct {
    seed: @FieldType(Run, "seed"),
    map: std.meta.Child(std.meta.Child(@FieldType(Run, "map"))),
    node: @FieldType(Run, "node"),
    visited: @FieldType(Run, "visited"),
    visits: std.meta.Elem(@FieldType(Run, "visits")),
};
pub const Seed = @FieldType(Header, "seed");
pub const Map = @FieldType(Header, "map");
pub const Node = @FieldType(Header, "node");
pub const Visited = @FieldType(Header, "visited");
pub const Visit = @FieldType(Header, "visits");
const HEAD_FIELDS = std.meta.fieldNames(Header);

/// The level's first field added since raw saves were written; every field from it on is newer.
const LEVEL_ADDED_FROM = "folk";
/// What raw saves wrote before fields were added to the end of the level and the map; the legacy reader takes them in this shape.
pub const LegacyLevel = blk: {
    const Level = @FieldType(Visit, "lv");
    const kept = std.meta.fieldIndex(Level, LEVEL_ADDED_FROM).?;
    break :blk Struct(std.meta.fields(Level)[0..kept].*);
};
pub const LegacyMap = Without(Map, "script");
pub const LegacyVisit = Replaced(Visit, "lv", LegacyLevel);
pub const LegacyHeader = Replaced(Replaced(Header, "map", LegacyMap), "visits", LegacyVisit);

comptime {
    const by_hand = .{ "seed", "map", "node", "visited", "visits" };
    std.debug.assert(HEAD_FIELDS.len == by_hand.len);
    for (HEAD_FIELDS, by_hand) |f, h| {
        if (!std.mem.eql(u8, f, h)) @compileError("save_data.Header: save.zig's writeLegacy, inspect and parseLegacy take " ++ h ++ " here by hand, not " ++ f);
    }
}
/// Field identities shared by portable saves and the ordered legacy tail.
pub const TAIL_FIELDS = .{
    .{ .sim, "lv" },
    .{ .sim, "pool" },
    .{ .sim, "hero" },
    .{ .sim, "rng" },
    .{ .sim, "kills" },
    .{ .sim, "gold" },
    .{ .sim, "log" },
    .{ .game, "bar" },
    .{ .pic, "facing" },
    .{ .sim, "name" },
    .{ .sim, "clock" },
    .{ .sim, "mana" },
    .{ .sim, "mana_recovery" },
    .{ .sim, "flasks" },
    .{ .sim, "cooldown" },
    .{ .sim, "stepped" },
    .{ .sim, "class" },
    .{ .sim, "inventory" },
    .{ .sim, "growth" },
    .{ .sim, "ground" },
    .{ .sim, "loot_rng" },
};
/// Saved by portable saves alone, each defaulted for a file written before it.
pub const PORTABLE_FIELDS = .{
    .{ .sim, "plot" },
    .{ .sim, "days" },
};
const PIC = game.presentation.Fields;
/// Not saved: the picture but the facing, the input, what the app sets on whatever it plays, and what `game.resumeRun` rebuilds.
const UNSAVED = .{
    .game = .{
        "character",
        "looted",
        "loot_gold",
        "nearby",
        "pause_page",
        "debug",
        "mode",
        "died_in",
        "pause_menu",
        "back",
        "exit",
        "permadeath",
        "hall",
        "epitaph",
        "st",
        "binds",
        "target",
        "cam",
        "screen",
        "framebuffer",
        "pending",
        "mouse",
        "vignette",
        "cinema",
        "mini",
        "sprites",
        "face",
        "light",
        "cloud",
        "graphics_ready",
        "art",
        "rain",
        "inspecting",
        "inspect_scroll",
        "perf",
    },
    .sim = .{
        "outdoors",
        "unkillable",
        "playground",
        "unsaved",
        "travel",
        "chronicle",
        "displaced",
        "order",
        "order_n",
        "ran",
        "flowed",
        "flow",
        "queue",
    },
    .pic = PIC.turn ++ PIC.run ++ PIC.settled ++ PIC.scratch ++ PIC.kept,
};

comptime {
    @setEvalBranchQuota(100_000);
    for (std.enums.values(Part)) |p| {
        const T = Of(p);
        const unsaved = @field(UNSAVED, @tagName(p));
        for (std.meta.fields(T)) |f| {
            var n: usize = 0;
            if (p == HEAD_PART) n += count(HEAD_FIELDS, f.name);
            for (TAIL_FIELDS ++ PORTABLE_FIELDS) |t| {
                if (t[0] == p and std.mem.eql(u8, f.name, t[1])) n += 1;
            }
            n += count(&unsaved, f.name);
            if (p == .game) for (std.enums.values(Part)) |q| {
                if (q != .game and std.mem.eql(u8, f.name, @tagName(q))) n += 1;
            };
            if (n != 1) @compileError("save_data.zig: say whether " ++ @typeName(T) ++ "." ++ f.name ++ " is saved");
        }
        for (unsaved) |name| {
            if (!@hasField(T, name)) @compileError("save_data.zig: " ++ @typeName(T) ++ " has no field " ++ name);
        }
    }
    for (TAIL_FIELDS ++ PORTABLE_FIELDS) |t| {
        if (!@hasField(Of(t[0]), t[1])) @compileError("save_data.zig: " ++ @typeName(Of(t[0])) ++ " has no field " ++ t[1]);
    }
}

fn eachOnce(comptime T: type, comptime lists: anytype, comptime label: []const u8) void {
    @setEvalBranchQuota(100_000);
    for (std.meta.fields(T)) |f| {
        var n: usize = 0;
        for (lists) |list| n += count(&list, f.name);
        if (n != 1) @compileError(label ++ ": say once when " ++ f.name ++ " is reset");
    }
    for (lists) |list| for (list) |name| {
        if (!@hasField(T, name)) @compileError(label ++ ": " ++ @typeName(T) ++ " has no field " ++ name);
    };
}

comptime {
    @setEvalBranchQuota(100_000);
    const F = game.simulation.Fields;
    eachOnce(Of(.sim), .{ F.hero, F.start, F.derived, F.rebuilt, F.run, F.resumed, F.turn, F.marks, F.set, F.scratch, F.kept }, "sim.Fields");
    const restored = F.derived ++ F.rebuilt ++ F.resumed ++ F.turn ++ F.marks ++ F.scratch ++ F.kept;
    for (UNSAVED.sim) |name| {
        if (!contains(&restored, name)) @compileError("save_data.UNSAVED: game.resumeRun does not rebuild " ++ name);
    }
    for (restored) |r| {
        if (!contains(&UNSAVED.sim, r)) @compileError("save_data.UNSAVED: " ++ r ++ " is rebuilt on resume but saved");
    }
}

comptime {
    @setEvalBranchQuota(100_000);
    const F = game.Fields;
    const lists = .{ F.loot, F.run, F.resumed, F.turn, F.graphics, F.set, F.scratch };
    for (UNSAVED.game) |name| {
        var n: usize = 0;
        for (lists) |list| n += count(&list, name);
        if (n != 1) @compileError("game.Fields: say once when " ++ name ++ " is reset");
    }
    for (lists) |list| for (list) |l| {
        if (!contains(&UNSAVED.game, l)) @compileError("game.Fields: " ++ l ++ " is not in save_data.UNSAVED.game");
    };
}

comptime {
    eachOnce(Of(.pic), .{ PIC.turn, PIC.run, PIC.facing, PIC.settled, PIC.scratch, PIC.kept }, "presentation.Fields");
}

const REQUIRED_FIELDS = .{ "lv", "pool", "hero", "rng", "name", "class", "growth" };

comptime {
    for (REQUIRED_FIELDS) |required| {
        for (TAIL_FIELDS) |t| {
            if (std.mem.eql(u8, t[1], required)) break;
        } else @compileError("save_data.REQUIRED_FIELDS names " ++ required ++ ", which TAIL_FIELDS does not");
    }
}

pub const Tail = blk: {
    @setEvalBranchQuota(10_000);
    var fs: [TAIL_FIELDS.len]std.builtin.Type.StructField = undefined;
    for (TAIL_FIELDS, 0..) |f, i| {
        const T = @FieldType(Of(f[0]), f[1]);
        const default = fallback: {
            if (contains(&REQUIRED_FIELDS, f[1])) break :fallback null;
            for (std.meta.fields(Of(f[0]))) |source| {
                if (std.mem.eql(u8, source.name, f[1])) break :fallback source.default_value_ptr;
            }
            unreachable;
        };
        fs[i] = fieldOf(f[1], T, default);
    }
    break :blk Struct(fs);
};
pub const LegacyTail = Replaced(Tail, "lv", LegacyLevel);
/// The legacy tail's bytes, field after field.
pub const TAIL = blk: {
    var n: usize = 0;
    for (std.meta.fields(LegacyTail)) |f| n += @sizeOf(f.type);
    break :blk n;
};

pub const Portable = blk: {
    var fs: [PORTABLE_FIELDS.len]std.builtin.Type.StructField = undefined;
    for (PORTABLE_FIELDS, 0..) |f, i| {
        const source = std.meta.fieldInfo(Of(f[0]), @field(std.meta.FieldEnum(Of(f[0])), f[1]));
        fs[i] = fieldOf(f[1], source.type, source.default_value_ptr orelse @compileError(f[1] ++ " needs a default for files written before it"));
    }
    break :blk Struct(fs);
};

pub fn Struct(comptime fields: anytype) type {
    return @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fields, .decls = &.{}, .is_tuple = false } });
}

pub fn fieldOf(comptime name: [:0]const u8, comptime T: type, comptime default: ?*const anyopaque) std.builtin.Type.StructField {
    return .{ .name = name, .type = T, .default_value_ptr = default, .is_comptime = false, .alignment = @alignOf(T) };
}

/// `T` without its field `name`.
fn Without(comptime T: type, comptime name: []const u8) type {
    const all = std.meta.fields(T);
    var fs: [all.len - 1]std.builtin.Type.StructField = undefined;
    var n: usize = 0;
    for (all) |f| {
        if (std.mem.eql(u8, f.name, name)) continue;
        if (n == fs.len) @compileError(@typeName(T) ++ " has no field " ++ name);
        fs[n] = f;
        n += 1;
    }
    return Struct(fs);
}

/// `T` with its field `name` of type `U` instead.
fn Replaced(comptime T: type, comptime name: []const u8, comptime U: type) type {
    const all = std.meta.fields(T);
    var fs: [all.len]std.builtin.Type.StructField = undefined;
    var found = false;
    for (all, 0..) |f, i| {
        fs[i] = f;
        if (!std.mem.eql(u8, f.name, name)) continue;
        fs[i] = fieldOf(f.name, U, null);
        found = true;
    }
    if (!found) @compileError(@typeName(T) ++ " has no field " ++ name);
    return Struct(fs);
}

/// Into `dest` whatever of `src` it shares, field by field; what `src` lacks takes its default.
pub fn convert(dest: anytype, src: anytype) void {
    const D = std.meta.Child(@TypeOf(dest));
    const S = std.meta.Child(@TypeOf(src));
    if (D == S) {
        dest.* = src.*;
        return;
    }
    inline for (std.meta.fields(D)) |f| {
        if (@hasField(S, f.name)) {
            convert(&@field(dest, f.name), &@field(src, f.name));
        } else @field(dest, f.name) = f.defaultValue() orelse @compileError(@typeName(D) ++ "." ++ f.name ++ " has no default to convert into");
    }
}

test "the legacy shapes keep every byte older raw saves wrote and convert both ways" {
    const grid = @import("map/grid.zig");
    try std.testing.expectEqual(std.meta.fields(Map).len - 1, std.meta.fields(LegacyMap).len);
    try std.testing.expectEqual(std.meta.fieldIndex(grid.Level, LEVEL_ADDED_FROM).?, std.meta.fields(LegacyLevel).len);
    const raw = try std.testing.allocator.create(LegacyVisit);
    defer std.testing.allocator.destroy(raw);
    const now = try std.testing.allocator.create(Visit);
    defer std.testing.allocator.destroy(now);
    now.lv = grid.Level.blank();
    now.lv.putFolk(.{ .x = 3, .y = 4 }, 2);
    now.lv.tile[7] = .lava;
    convert(raw, now);
    try std.testing.expectEqual(grid.Tile.lava, raw.lv.tile[7]);
    now.lv.tile[7] = .floor;
    convert(now, raw);
    try std.testing.expectEqual(grid.Tile.lava, now.lv.tile[7]);
    try std.testing.expectEqual(@as(?usize, null), now.lv.folkAt(.{ .x = 3, .y = 4 }));
    std.debug.print("legacy shapes: map and level read without their added fields; a visit converts both ways and the added folk default\n", .{});
}

pub const Summary = struct {
    name: hero.Name,
    hp: i32,
    max: i32,
    gold: i32,
    /// Null on a generated floor.
    node: ?usize,
    place: atlas.Label = .{},

    /// Null with no hero to describe.
    pub fn of(g: *game.Game) ?Summary {
        const body = g.sim.heroActor() orelse return null;
        var s = Summary{ .name = g.sim.name, .hp = body.hp, .max = body.max, .gold = g.sim.gold, .node = null };
        if (g.sim.map) |map| {
            s.node = g.sim.node;
            s.place = map.node[g.sim.node].label;
        }
        return s;
    }

    pub fn details(self: *const Summary, buf: []u8) [:0]const u8 {
        var at: [atlas.TITLE_MAX]u8 = undefined;
        const where = if (self.node) |n| atlas.titleOf(self.place.text(), n, &at) else "a generated floor";
        return std.fmt.bufPrintZ(buf, hero.HP_FMT ++ menu.SEP ++ hero.GOLD_FMT ++ menu.SEP ++ "{s}", .{ self.hp, self.max, self.gold, where }) catch "";
    }
};
