const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fire = @import("../map/fire.zig");
const ice = @import("../map/ice.zig");
const actor = @import("../play/actor.zig");
const ground = @import("ground.zig");
const raster = @import("raster.zig");
const look = @import("look.zig");
const embedded = @import("assets").names;

pub const Bodies = std.EnumArray(actor.Kind, ?rl.Texture2D);

pub const PICTURE_CASTERS = blk: {
    var n: usize = 0;
    for (std.enums.values(grid.Tile)) |t| {
        if (look.castsPicture(t)) n += 1;
    }
    var out: [n]grid.Tile = undefined;
    var i: usize = 0;
    for (std.enums.values(grid.Tile)) |t| {
        if (!look.castsPicture(t)) continue;
        out[i] = t;
        i += 1;
    }
    break :blk out;
};

pub const FIGURES: usize = LIT_FIGURES + PICTURE_CASTERS.len + WALL_MASKS.len + PROP_FIGURES.len;
pub const PROP_FIGURES = [_][:0]const u8{ "item_bag", "chest_item_bag", "mimic_closed", "shrub2" };
/// The first of `figures`, the bodies and the barrel, which the body shader lights from their normals.
pub const LIT_FIGURES: usize = Bodies.len + 1;

pub const Assets = struct {
    bodies: std.EnumSet(actor.Kind) = .initEmpty(),
    tiles: std.EnumSet(grid.Tile) = .initEmpty(),
    wall: std.StaticBitSet(WALL_MASKS.len) = .initEmpty(),
    forest: std.StaticBitSet(WALL_MASKS.len) = .initEmpty(),
    grounds: ground.Grounds = .initEmpty(),
    grass2: bool = false,
    dirt2: bool = false,
    shallows2: bool = false,
    shallows3: bool = false,
    shallows_cliff: bool = false,
    shallows_cliff_cap: bool = false,
    water_cliff: bool = false,
    water_cliff_cap: bool = false,
    dirt_shallows_edges: bool = false,
    dirt_water_edges: bool = false,
    shallows_water_edges: bool = false,
    shallows_water_cap: bool = false,
    shrub2: bool = false,
    brush: bool = false,
    flowers: bool = false,
    barrel: bool = false,
    item_bag: bool = false,
    chest_item_bag: bool = false,
    mimic_closed: bool = false,
    small_coins: bool = false,
    large_coins: bool = false,

    pub fn of(lv: *const grid.Level) Assets {
        var need = Assets{ .item_bag = true, .small_coins = true, .large_coins = true };
        for (lv.tile, lv.barrel, 0..) |t, barrel, i| {
            const p = grid.Level.of(i);
            need.decor(t, p);
            if (t.bursts()) need.beneath(t.ground().?, p);
            if (t.burns()) for (fire.ashes(t)) |ash| need.beneath(ash, p);
            if (lv.frozen(p)) need.beneath(ice.WATER, p);
            need.barrel = need.barrel or barrel or (lv.seen[i] and lv.barrel_seen[i]);
            need.chest_item_bag = need.chest_item_bag or t.isChest();
            if (t.opened()) |open| need.add(.{ .tile = open });
            if (look.standsOver(t)) {
                if (cutAt(lv, p)) |c| need.add(c);
            }
            const g = ground.bedAt(lv, p, false) orelse continue;
            need.bed(g);
            if (look.under(t)) |u| need.bed(ground.of(u).?);
        }
        return need;
    }

    fn beneath(need: *Assets, t: grid.Tile, p: mathx.P) void {
        need.decor(t, p);
        if (look.standsOver(t)) if (cutOf(t, null)) |c| need.add(c);
        if (ground.of(t)) |g| need.bed(g);
        if (look.under(t)) |u| need.bed(ground.of(u).?);
    }

    fn decor(need: *Assets, t: grid.Tile, p: mathx.P) void {
        if (grassDecor(t, p)) |d| switch (d) {
            inline else => |k| @field(need, @tagName(k)) = true,
        };
    }

    fn bed(need: *Assets, g: ground.Ground) void {
        if (g == .water) need.shallows_water_cap = true;
        inline for (WATER_EDGES) |edge| {
            if (g == edge.lower) @field(need, edge.name) = true;
        }
        switch (g) {
            inline else => |k| {
                if (comptime CLIFFS.get(k)) |c| {
                    @field(need, c.face) = true;
                    @field(need, c.cap) = true;
                }
                if (comptime GROUND_ALTERNATES.get(k)) |alts| {
                    inline for (alts.fields) |name| @field(need, name) = true;
                }
            },
        }
        if (GROUND_SHEETS.contains(g)) need.grounds.insert(g) else need.add(.{ .tile = g.tile() });
    }

    fn add(need: *Assets, c: Cut) void {
        switch (c) {
            .tile => |t| if (TILE_PNGS.get(t) != null) need.tiles.insert(t),
            .wall => |i| need.wall.set(i),
            .forest => |i| need.forest.set(i),
            .shrub2 => need.shrub2 = true,
        }
    }

    pub fn body(need: *Assets, k: actor.Kind) void {
        need.bodies.setUnion(actor.descent(k).intersectWith(PICTURED));
    }

    pub fn everything() Assets {
        var all = Assets{ .grounds = GROUND_SHEETS, .bodies = PICTURED, .wall = .initFull(), .forest = .initFull() };
        inline for (std.meta.fields(Assets)) |f| {
            if (f.type == bool) @field(all, f.name) = true;
        }
        for (std.enums.values(grid.Tile)) |t| all.add(.{ .tile = t });
        return all;
    }

    pub fn merge(a: Assets, b: Assets) Assets {
        var out: Assets = undefined;
        inline for (std.meta.fields(Assets)) |f| {
            const x = @field(a, f.name);
            const y = @field(b, f.name);
            @field(out, f.name) = if (f.type == bool) x or y else x.unionWith(y);
        }
        return out;
    }

    pub fn count(need: Assets) usize {
        var n: usize = 0;
        inline for (std.meta.fields(Assets)) |f| {
            const x = @field(need, f.name);
            n += if (f.type == bool) @intFromBool(x) else x.count();
        }
        return n;
    }
};

/// In drawing order.
pub const WATER_EDGES = [_]struct { upper: ground.Ground, lower: ground.Ground, name: [:0]const u8 }{
    .{ .upper = .shallows, .lower = .water, .name = "shallows_water_edges" },
    .{ .upper = .dirt, .lower = .shallows, .name = "dirt_shallows_edges" },
    .{ .upper = .dirt, .lower = .water, .name = "dirt_water_edges" },
};

pub const EDGE_GROUNDS = blk: {
    var s = ground.Grounds.initEmpty();
    for (WATER_EDGES) |e| {
        s.insert(e.upper);
        s.insert(e.lower);
    }
    break :blk s;
};

const Cliff = struct { face: [:0]const u8, cap: [:0]const u8 };
pub const CLIFFS = std.EnumArray(ground.Ground, ?Cliff).initDefault(@as(?Cliff, null), .{
    .shallows = .{ .face = "shallows_cliff", .cap = "shallows_cliff_cap" },
    .water = .{ .face = "water_cliff", .cap = "water_cliff_cap" },
});

fn listed(comptime name: []const u8) bool {
    @setEvalBranchQuota(10_000);
    for (embedded) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

fn optionalPng(comptime name: []const u8) ?[]const u8 {
    return if (comptime listed(name)) @embedFile(name) else null;
}

fn embedPng(comptime name: []const u8) []const u8 {
    return @embedFile(name);
}

pub const GROUND_PNGS = blk: {
    var pngs = std.EnumArray(ground.Ground, ?[]const u8).initFill(null);
    for (std.enums.values(ground.Ground)) |g| pngs.set(g, optionalPng(g.png()));
    break :blk pngs;
};

pub const GROUND_SHEETS = blk: {
    var s = ground.Grounds.initEmpty();
    for (std.enums.values(ground.Ground)) |g| {
        const png = GROUND_PNGS.get(g) orelse continue;
        std.debug.assert(std.meta.eql(pngSize(png), mathx.P{ .x = ground.COLS * look.SPRITE_PX, .y = ground.ROWS * look.SPRITE_PX }));
        s.insert(g);
    }
    break :blk s;
};

const BODY_PNGS = std.EnumArray(actor.Kind, ?[]const u8).init(.{
    .archer = @embedFile("archer.png"),
    .wizard = @embedFile("wizard.png"),
    .knight = @embedFile("knight.png"),
    .rat = @embedFile("rat.png"),
    .slime = @embedFile("slime.png"),
    .slime_half = @embedFile("slime-half.png"),
    .slime_quarter = @embedFile("slime-quarter.png"),
    .bloat = @embedFile("caustic-bloat.png"),
    .pib = @embedFile("pib.png"),
    .beefy_pib = @embedFile("beefy-pib.png"),
    .bandit_crossbowman = @embedFile("bandit-crossbowman.png"),
    .bandit_netter = @embedFile("bandit-trapper.png"),
    .bandit_shieldbearer = null,
    .frost_wisp = null,
    .pyre_bloat = @embedFile("pyre-bloat.png"),
    .pib_shaman = @embedFile("pib-shaman.png"),
    .bog_leech = @embedFile("bog-leech.png"),
    .mimic = @embedFile("mimic-open.png"),
    .goblin = null,
    .sluice_crab = null,
    .chain_gaoler = null,
    .cinder_imp = null,
    .skeleton = @embedFile("skeleton.png"),
    .caravan_guard = @embedFile("bandit-crossbowman.png"),
});

const PICTURED = blk: {
    var s = std.EnumSet(actor.Kind).initEmpty();
    for (std.enums.values(actor.Kind)) |k| s.setPresent(k, BODY_PNGS.get(k) != null);
    break :blk s;
};

const TILE_PNGS = std.EnumArray(grid.Tile, ?[]const u8).initDefault(@as(?[]const u8, null), .{
    .floor = @embedFile("floor.png"),
    .grass = @embedFile("grass.png"),
    .reeds = @embedFile("reeds.png"),
    .shrub = @embedFile("shrub.png"),
    .swamp_tree = @embedFile("swamp-tree.png"),
    .large_tree = @embedFile("large-tree.png"),
    .tiny_shrub = @embedFile("tiny-shrub.png"),
    .boulder = @embedFile("boulder.png"),
    .fungus = @embedFile("tall-shroom.png"),
    .tall_grass = @embedFile("tall-grass.png"),
    .shrooms = @embedFile("small-shrooms.png"),
    .chest = @embedFile("chest.png"),
    .chest_open = @embedFile("chest-open.png"),
    .caravan = @embedFile("caravan-cart.png"),
    .glow_plant = @embedFile("glowbulb.png"),
});

comptime {
    std.debug.assert(TILE_PNGS.get(.wall) == null);
    std.debug.assert(std.meta.eql(pngSize(TILE_PNGS.get(.large_tree).?), mathx.P{ .x = look.SPRITE_PX, .y = 2 * look.SPRITE_PX }));
    for (std.enums.values(grid.Tile)) |t| {
        if (!look.standsOver(t)) continue;
        const size = pngSize(TILE_PNGS.get(t) orelse continue);
        if (size.x != look.SPRITE_PX * t.wide() or (size.y > look.SPRITE_PX) != look.tall(t)) @compileError(@tagName(t) ++ ": a standing picture is a sprite wide a cell it stands on, and taller only when `tall`");
    }
    for (PICTURE_CASTERS) |t| {
        if (TILE_PNGS.get(t) == null) @compileError("a picture caster needs its picture: " ++ @tagName(t));
    }
}

const WALLS_PNG = @embedFile("walls.png");
const FOREST_PNG = @embedFile("forest-tree-walls.png");
pub const HUD_BORDER_PNG = @embedFile("hud-border.png");

pub const SOURCES = .{
    .bodies = BODY_PNGS,
    .tiles = TILE_PNGS,
    .grounds = GROUND_PNGS,
    .grass2 = embedPng("grass2.png"),
    .dirt2 = embedPng("dirt2.png"),
    .shallows2 = embedPng("shallows2.png"),
    .shallows3 = embedPng("shallows3.png"),
    .shallows_cliff = embedPng("shallows-cliff.png"),
    .shallows_cliff_cap = embedPng("shallows-cliff-cap.png"),
    .water_cliff = embedPng("water-cliff.png"),
    .water_cliff_cap = embedPng("water-cliff-cap.png"),
    .dirt_shallows_edges = embedPng("dirt-shallows-edges.png"),
    .dirt_water_edges = embedPng("dirt-water-edges.png"),
    .shallows_water_edges = embedPng("shallows-water-edges.png"),
    .shallows_water_cap = embedPng("shallows-water-cap.png"),
    .shrub2 = embedPng("shrub2.png"),
    .brush = embedPng("brush.png"),
    .flowers = embedPng("flowers.png"),
    .barrel = embedPng("barrel.png"),
    .item_bag = embedPng("item-bag.png"),
    .chest_item_bag = embedPng("chest-item-bag.png"),
    .mimic_closed = embedPng("mimic-closed.png"),
    .small_coins = embedPng("small-coins.png"),
    .large_coins = embedPng("large-coins.png"),
    .wall = @as([]const u8, WALLS_PNG),
    .forest = @as([]const u8, FOREST_PNG),
};

comptime {
    const want = std.meta.fieldNames(Assets);
    std.debug.assert(want.len == std.meta.fieldNames(@TypeOf(SOURCES)).len);
    for (want) |n| std.debug.assert(@hasField(@TypeOf(SOURCES), n));
}

comptime {
    std.debug.assert(std.meta.eql(pngSize(WALLS_PNG), pngSize(FOREST_PNG)));
}

const LONE_CLUMP_IN: u64 = 3;
const LONE_CLUMP_SEED: u64 = 0xF02E57;
const SHRUB2_IN: u64 = 2;
const SHRUB2_SEED: u64 = 0x5B2;
const Alternates = struct { seed: u64, in: u64, fields: []const []const u8 };
pub const GROUND_ALTERNATES = std.EnumArray(ground.Ground, ?Alternates).initDefault(@as(?Alternates, null), .{
    .grass = .{ .seed = 0x62A552, .in = 3, .fields = &.{"grass2"} },
    .dirt = .{ .seed = 0xD127, .in = 3, .fields = &.{"dirt2"} },
    .shallows = .{ .seed = 0x5A110, .in = 16, .fields = &.{ "shallows2", "shallows3" } },
});
const DECOR_IN: u64 = 60;
const BRUSH_IN: u64 = 3;
const DECOR_SEED: u64 = 0xB2754;

const GrassDecor = enum { brush, flowers };

pub fn grassDecor(t: grid.Tile, p: mathx.P) ?GrassDecor {
    if (t != .grass) return null;
    const roll = rollIn(DECOR_SEED, DECOR_IN, p);
    if (roll < BRUSH_IN) return .brush;
    return if (roll == BRUSH_IN) .flowers else null;
}

fn loneClump(p: mathx.P) bool {
    return oneIn(LONE_CLUMP_SEED, LONE_CLUMP_IN, p);
}

pub fn rollIn(seed: u64, in: u64, p: mathx.P) u64 {
    return mathx.cellHash(seed, p) % in;
}

fn oneIn(seed: u64, in: u64, p: mathx.P) bool {
    return rollIn(seed, in, p) == 0;
}

pub fn forestAt(lv: *const grid.Level, p: mathx.P) bool {
    return lv.at(p) == .shrub and (lv.tileMask(p) != 0 or loneClump(p));
}

pub const Cut = union(enum) { tile: grid.Tile, wall: usize, forest: usize, shrub2 };

pub fn cutAt(lv: *const grid.Level, p: mathx.P) ?Cut {
    if (forestAt(lv, p)) return .{ .forest = WALL_CELL[lv.tileMask(p)] };
    if (lv.at(p) == .shrub and oneIn(SHRUB2_SEED, SHRUB2_IN, p)) return .shrub2;
    return cutOf(lv.at(p), lv.tileShape(p));
}

pub fn cutOf(t: grid.Tile, shape: ?grid.WallShape) ?Cut {
    if (t == .wall) return .{ .wall = WALL_CELL[(shape orelse return null).mask()] };
    return .{ .tile = t };
}

/// Row-major masks shared with `tools/tile_art/wall_masks.lua` for both wall and forest sheets.
pub const WALL_MASKS = [_]u8{ 0, 1, 2, 4, 8, 3, 19, 5, 6, 38, 9, 137, 10, 12, 76, 7, 23, 39, 55, 11, 27, 139, 155, 13, 77, 141, 205, 14, 46, 78, 110, 15, 31, 47, 63, 79, 95, 111, 127, 143, 159, 175, 191, 207, 223, 239, 255 };
const WALL_COLS: usize = @divExact(pngSize(WALLS_PNG).x, look.SPRITE_PX);

pub fn pngSize(png: []const u8) mathx.P {
    return .{ .x = std.mem.readInt(i32, png[16..20], .big), .y = std.mem.readInt(i32, png[20..24], .big) };
}

const WALL_CELL = blk: {
    @setEvalBranchQuota(10_000);
    var at = [_]u8{0xFF} ** 256;
    for (WALL_MASKS, 0..) |m, i| {
        std.debug.assert(at[m] == 0xFF and @as(grid.WallShape, @bitCast(m)).joined().mask() == m);
        at[m] = i;
    }
    var all: [256]u8 = undefined;
    for (&all, 0..) |*cell, m| {
        cell.* = at[@as(grid.WallShape, @bitCast(@as(u8, m))).joined().mask()];
        std.debug.assert(cell.* != 0xFF);
    }
    break :blk all;
};

/// raylib's `imageFromImage` copies without clamping, so a cell off the sheet would read past it.
pub fn wallCell(sheet: rl.Image, i: usize) ?rl.Image {
    const at = mathx.unslot(i, WALL_COLS);
    if ((at.x + 1) * look.SPRITE_PX > sheet.width or (at.y + 1) * look.SPRITE_PX > sheet.height) return null;
    return rl.imageFromImage(sheet, sheetCell(at.x, at.y));
}

pub fn sheetCell(col: i32, row: i32) rl.Rectangle {
    return raster.rect(col * look.SPRITE_PX, row * look.SPRITE_PX, look.SPRITE_PX, look.SPRITE_PX);
}

test "map assets include unseen shapes, ground under props and future slime forms" {
    const gen = @import("../map/gen.zig");
    var lv = grid.Level.blank();
    @memset(&lv.tile, .rock);
    lv.set(.{ .x = 20, .y = 20 }, .wall);
    lv.set(.{ .x = 23, .y = 20 }, .shrub);
    lv.set(.{ .x = 24, .y = 20 }, .shrub);
    lv.set(.{ .x = 30, .y = 20 }, .boulder);
    gen.shapeWalls(&lv);
    var need = Assets.of(&lv);
    need.body(.archer);
    need.body(.slime_half);
    try std.testing.expect(need.tiles.contains(.floor) and need.grounds.contains(.grass) and !need.tiles.contains(.grass));
    try std.testing.expect(need.tiles.contains(.boulder) and !need.tiles.contains(.shrub));
    try std.testing.expectEqual(@as(usize, 1), need.wall.count());
    try std.testing.expect(need.wall.isSet(WALL_CELL[0]));
    try std.testing.expectEqual(@as(usize, 2), need.forest.count());
    try std.testing.expect(need.forest.isSet(WALL_CELL[2]) and need.forest.isSet(WALL_CELL[8]));
    try std.testing.expect(need.bodies.contains(.slime_half) and need.bodies.contains(.slime_quarter));
    try std.testing.expect(!need.bodies.contains(.slime) and !need.bodies.contains(.rat));
    try std.testing.expect(!need.barrel);
    need.body(.slime);
    try std.testing.expectEqual(@as(usize, 4), need.bodies.count());
    lv = grid.openFloor();
    lv.putBarrel(grid.MIDDLE);
    lv.set(.{ .x = 20, .y = 20 }, .chest);
    const next = Assets.of(&lv);
    try std.testing.expect(next.item_bag and next.chest_item_bag and next.tiles.contains(.chest_open));
    try std.testing.expect(next.barrel and next.forest.count() == 0 and next.bodies.count() == 0);
    try std.testing.expect(next.tiles.contains(.floor) and !next.tiles.contains(.grass));
    const cell = grid.Level.idx(grid.MIDDLE);
    lv.seen[cell] = true;
    lv.barrel_seen[cell] = true;
    try std.testing.expect(lv.breakBarrel(grid.MIDDLE));
    try std.testing.expect(Assets.of(&lv).barrel);
    lv.barrel_seen[cell] = false;
    try std.testing.expect(!Assets.of(&lv).barrel);
}

test "map assets hold the fallback ground a prop stands on when only unbearing neighbours are seen" {
    var lv = grid.Level.blank();
    @memset(&lv.tile, .water);
    @memset(&lv.seen, true);
    const p = grid.MIDDLE;
    lv.set(p, .boulder);
    const fallback = ground.of(look.under(.boulder).?).?;
    const other: ground.Ground = if (fallback == .dirt) .sand else .dirt;
    for (mathx.CARDINALS) |d| {
        lv.set(p.add(d), other.tile());
        lv.seen[grid.Level.idx(p.add(d))] = false;
    }
    const shown = ground.bedAt(&lv, p, true).?;
    try std.testing.expect(shown != ground.bedAt(&lv, p, false).?);
    const need = Assets.of(&lv);
    try std.testing.expect(if (GROUND_SHEETS.contains(shown)) need.grounds.contains(shown) else need.tiles.contains(shown.tile()));
}

test "map assets retain the water artwork beneath temporary ice" {
    var lv = grid.openFloor();
    const at = mathx.P{ .x = 20, .y = 20 };
    lv.set(at, .shallows);
    const thawed = Assets.of(&lv);
    lv.set(at, .ice);
    lv.thaw[grid.Level.idx(at)] = 2;
    const frozen = Assets.of(&lv);
    try std.testing.expectEqualDeep(frozen, frozen.merge(thawed));
}

test "map assets hold the grass decor a glowbulb leaves when it bursts" {
    var checked: usize = 0;
    var cells = grid.Box.inMap(1).cells();
    while (cells.next()) |p| {
        const d = grassDecor(.grass, p) orelse continue;
        var lv = grid.openFloor();
        lv.set(p, .glow_plant);
        const need = Assets.of(&lv);
        try std.testing.expect(switch (d) {
            .brush => need.brush,
            .flowers => need.flowers,
        });
        checked += 1;
        if (checked == 8) break;
    }
    try std.testing.expectEqual(@as(usize, 8), checked);
}

test "every wall and forest cell lies inside its PNG, and one past its end is refused" {
    for ([_][]const u8{ WALLS_PNG, FOREST_PNG }) |png| {
        const w = pngSize(png).x;
        const h = pngSize(png).y;
        const sheet = rl.genImageColor(w, h, rl.Color.white);
        defer rl.unloadImage(sheet);
        try std.testing.expectEqual(@as(i32, look.SPRITE_PX * WALL_COLS), w);
        try std.testing.expectEqual(@as(i32, look.SPRITE_PX * ((WALL_MASKS.len + WALL_COLS - 1) / WALL_COLS)), h);
        for (0..WALL_MASKS.len) |i| rl.unloadImage(wallCell(sheet, i) orelse return error.CellOffSheet);
        try std.testing.expect(wallCell(sheet, @intCast(@divTrunc(w, look.SPRITE_PX) * @divTrunc(h, look.SPRITE_PX))) == null);
    }
}

test "a caravan's picture spans its two cells and rises a cell above them, at native scale" {
    const size = pngSize(TILE_PNGS.get(.caravan).?);
    const tex = rl.Texture2D{ .id = 1, .width = size.x, .height = size.y, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    for ([_]f32{ look.SPRITE_PX, 2 * look.SPRITE_PX }) |cell| {
        const r = look.tileRect(.caravan, tex, .{ .x = 10 * cell, .y = 5 * cell, .width = cell, .height = cell });
        try std.testing.expectEqual(rl.Rectangle{ .x = 10 * cell, .y = 4 * cell, .width = 2 * cell, .height = 2 * cell }, r);
    }
    try std.testing.expect(look.tall(.caravan) and !look.stands(.caravan_part) and !look.castsPicture(.caravan_part));
}

test "forest sprites follow connections and isolated trees mix with clumps without changing visibility" {
    const gen = @import("../map/gen.zig");
    var lv = grid.Level.blank();
    @memset(&lv.tile, .grass);
    var sprites = @import("sprites.zig").Sprites{};
    const tree = rl.Texture2D{ .id = 1, .width = look.SPRITE_PX, .height = look.SPRITE_PX, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    sprites.tiles.set(.shrub, tree);
    var alt = tree;
    alt.id = 1000;
    sprites.shrub2 = alt;
    for (&sprites.forest, 0..) |*t, i| {
        var texture_ = tree;
        texture_.id = @intCast(i + 2);
        t.* = texture_;
    }
    const a = mathx.P{ .x = 20, .y = 20 };
    const b = a.add(.{ .x = 1, .y = 0 });
    lv.set(a, .shrub);
    lv.set(b, .shrub);
    gen.shapeWalls(&lv);
    try std.testing.expectEqual(sprites.forest[WALL_CELL[2]].?.id, sprites.tileAt(&lv, a).?.id);
    try std.testing.expectEqual(sprites.forest[WALL_CELL[8]].?.id, sprites.tileAt(&lv, b).?.id);
    lv.seen = @splat(true);
    try std.testing.expectEqual(sprites.forest[WALL_CELL[2]].?.id, sprites.tileAt(&lv, a).?.id);
    @memset(&lv.tile, .grass);
    var trees: usize = 0;
    var alts: usize = 0;
    var clumps: usize = 0;
    for (0..100) |i| {
        const p = mathx.P{ .x = 2 + @as(i32, @intCast(i % 10)) * 3, .y = 2 + @as(i32, @intCast(i / 10)) * 3 };
        lv.set(p, .shrub);
    }
    gen.shapeWalls(&lv);
    const need = Assets.of(&lv);
    try std.testing.expect(need.tiles.contains(.shrub) and need.shrub2 and need.forest.isSet(WALL_CELL[0]));
    for (lv.tile, 0..) |t, i| {
        if (t != .shrub) continue;
        const p = grid.Level.of(i);
        const id = sprites.tileAt(&lv, p).?.id;
        try std.testing.expectEqual(id, sprites.tileAt(&lv, p).?.id);
        try std.testing.expect(t.solid() and t.blind());
        if (id == tree.id) trees += 1 else if (id == alt.id) alts += 1 else if (id == sprites.forest[WALL_CELL[0]].?.id) clumps += 1 else return error.NotAnIsolatedSprite;
    }
    try std.testing.expect(trees > 20 and alts > 20 and clumps > 15 and clumps < trees + alts);
}

test "the wall sheet's masks, shape bits and face height are the ones its scripts paint" {
    try ground.expectLuaList(u8, &WALL_MASKS, "tools/tile_art/wall_masks.lua", "local masks={");
    const sides = .{ "n", "e", "s", "w", "ne", "se", "sw", "nw" };
    var bits: [sides.len]u8 = undefined;
    inline for (sides, 0..) |side, i| {
        var shape = grid.WallShape{};
        @field(shape, side) = true;
        bits[i] = shape.mask();
    }
    try ground.expectLuaList(u8, &bits, "tools/tile_art/wall_masks.lua", "local N,E,S,W,NE,SE,SW,NW=");
    try ground.expectLuaList(i32, &.{look.WALL_FACE_PX}, "tools/tile_art/export_walls.lua", "local FACE=");
    try ground.expectLuaList(i32, &.{look.WALL_FACE_PX}, "tools/tile_art/guide_walls.lua", "local FACE=tonumber(app.params.rows) or ");
    try ground.expectLuaList(i32, &.{look.WALL_FACE_PX}, "tools/tile_art/idea_walls.lua", "local FACE=");
}
