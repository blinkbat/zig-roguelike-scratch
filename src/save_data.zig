const std = @import("std");
const game = @import("game.zig");
const atlas = @import("map/atlas.zig");
const hero = @import("play/hero.zig");
const menu = @import("ui/menu.zig");

/// Where in the game a saved field lives, `game` or its field of that name; the file names it by its field name alone.
pub const Part = enum { game, sim, pic };

pub fn Of(comptime p: Part) type {
    return if (p == .game) game.Game else @FieldType(game.Game, @tagName(p));
}

pub fn part(g: *game.Game, comptime p: Part) *Of(p) {
    return if (p == .game) g else &@field(g, @tagName(p));
}

pub const HEAD_PART: Part = .sim;
pub const Run = Of(HEAD_PART);

/// The legacy header also classifies the run's separately stored map and visits.
pub const Header = struct {
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
pub const HEAD_FIELDS = std.meta.fieldNames(Header);

comptime {
    const by_hand = .{ "seed", "map", "node", "visited", "visits" };
    std.debug.assert(HEAD_FIELDS.len == by_hand.len);
    for (HEAD_FIELDS, by_hand) |f, h| {
        if (!std.mem.eql(u8, f, h)) @compileError("save.Header: write, inspect and read take " ++ h ++ " here by hand, not " ++ f);
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
/// Not saved: the picture, the input, what the app sets on whatever it plays, and what `game.resumeRun` rebuilds.
pub const UNSAVED = .{
    .game = .{
        "character",
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
    .pic = .{
        "occlusion",
        "glide",
        "turning",
        "pictured",
        "seq",
        "split_from",
        "dropped_gold",
        "owed",
        "shot",
        "foe_shots",
        "busy",
        "lead",
        "fx",
        "gold_taken",
        "mana_held",
        "flasks_shown",
        "xp_aim",
        "xp_shown",
        "life_fill",
        "mana_fill",
        "growth_shown",
        "gold_shown",
        "hour_shown",
    },
};

comptime {
    @setEvalBranchQuota(100_000);
    for (std.enums.values(Part)) |p| {
        const T = Of(p);
        const unsaved = @field(UNSAVED, @tagName(p));
        for (std.meta.fields(T)) |f| {
            var n: usize = 0;
            if (p == HEAD_PART) for (HEAD_FIELDS) |name| {
                if (std.mem.eql(u8, f.name, name)) n += 1;
            };
            for (TAIL_FIELDS) |t| {
                if (t[0] == p and std.mem.eql(u8, f.name, t[1])) n += 1;
            }
            for (unsaved) |name| {
                if (std.mem.eql(u8, f.name, name)) n += 1;
            }
            if (p == .game) for (std.enums.values(Part)) |q| {
                if (q != .game and std.mem.eql(u8, f.name, @tagName(q))) n += 1;
            };
            if (n != 1) @compileError("save.zig: say whether " ++ @typeName(T) ++ "." ++ f.name ++ " is saved");
        }
        for (unsaved) |name| {
            if (!@hasField(T, name)) @compileError("save.zig: " ++ @typeName(T) ++ " has no field " ++ name);
        }
    }
    for (TAIL_FIELDS) |t| {
        if (!@hasField(Of(t[0]), t[1])) @compileError("save.zig: " ++ @typeName(Of(t[0])) ++ " has no field " ++ t[1]);
    }
}

const REQUIRED_FIELDS = .{ "lv", "pool", "hero", "rng", "name", "class", "growth" };

pub const Tail = blk: {
    var fs: [TAIL_FIELDS.len]std.builtin.Type.StructField = undefined;
    for (TAIL_FIELDS, 0..) |f, i| {
        const T = @FieldType(Of(f[0]), f[1]);
        const default = fallback: {
            for (REQUIRED_FIELDS) |required| {
                if (std.mem.eql(u8, f[1], required)) break :fallback null;
            }
            for (std.meta.fields(Of(f[0]))) |source| {
                if (std.mem.eql(u8, source.name, f[1])) break :fallback source.default_value_ptr;
            }
            unreachable;
        };
        fs[i] = .{ .name = f[1], .type = T, .default_value_ptr = default, .is_comptime = false, .alignment = @alignOf(T) };
    }
    break :blk @Type(.{ .@"struct" = .{ .layout = .auto, .fields = &fs, .decls = &.{}, .is_tuple = false } });
};
pub const TAIL = blk: {
    var n: usize = 0;
    for (std.meta.fields(Tail)) |f| n += @sizeOf(f.type);
    break :blk n;
};

pub const Summary = struct {
    name: hero.Name,
    hp: i32,
    max: i32,
    gold: i32,
    /// Null on a generated floor.
    node: ?usize,
    place: atlas.Label = .{},

    pub fn details(self: *const Summary, buf: []u8) [:0]const u8 {
        var at: [atlas.TITLE_MAX]u8 = undefined;
        const where = if (self.node) |n| atlas.titleOf(self.place.text(), n, &at) else "a generated floor";
        return std.fmt.bufPrintZ(buf, hero.HP_FMT ++ menu.SEP ++ hero.GOLD_FMT ++ menu.SEP ++ "{s}", .{ self.hp, self.max, self.gold, where }) catch "";
    }
};
