const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const gen = @import("gen.zig");
const carve = @import("carve.zig");
const open = @import("biome/open.zig");
const wilds = @import("biome/wilds.zig");
const caves = @import("biome/caves.zig");
const cavern = @import("biome/cavern.zig");
const strata = @import("biome/strata.zig");
const labyrinth = @import("biome/labyrinth.zig");
const hall = @import("biome/hall.zig");
const maze = @import("biome/maze.zig");
const topology = @import("biome/topology.zig");
const terrain = @import("biome/terrain.zig");
const keep = @import("biome/keep.zig");
const town = @import("biome/town.zig");
const dunes = @import("biome/dunes.zig");
const site = @import("biome/site.zig");
const river = @import("feature/river.zig");
const lake = @import("feature/lake.zig");
const road = @import("feature/road.zig");
const scatter = @import("feature/scatter.zig");
const border = @import("feature/border.zig");
const buildings = @import("feature/buildings.zig");
const farms = @import("feature/farms.zig");
const setpiece = @import("feature/setpiece.zig");

const P = mathx.P;

pub const MAX_FEATURES: usize = 6;
/// Its features draw from another stream than the base, so adding one leaves the base as it was.
const FEATURE_SALT: u64 = 0xFEA7_0BE5;

/// A base biome: `gen.around`'s rooms, or a module with `Params`, `shape` and `palette`.
pub const Algo = enum { rooms, open, wilds, caves, cavern, strata, labyrinth, hall, maze, topology, terrain, keep, town, dunes, site };

const BASES = .{
    .open = open,
    .wilds = wilds,
    .caves = caves,
    .cavern = cavern,
    .strata = strata,
    .labyrinth = labyrinth,
    .hall = hall,
    .maze = maze,
    .topology = topology,
    .terrain = terrain,
    .keep = keep,
    .town = town,
    .dunes = dunes,
    .site = site,
};

pub const Floor = union(Algo) {
    rooms: gen.Params,
    open: open.Params,
    wilds: wilds.Params,
    caves: caves.Params,
    cavern: cavern.Params,
    strata: strata.Params,
    labyrinth: labyrinth.Params,
    hall: hall.Params,
    maze: maze.Params,
    topology: topology.Params,
    terrain: terrain.Params,
    keep: keep.Params,
    town: town.Params,
    dunes: dunes.Params,
    site: site.Params,

    pub fn of(a: Algo) Floor {
        return switch (a) {
            inline else => |t| @unionInit(Floor, @tagName(t), .{}),
        };
    }

    pub fn fit(f: Floor) Floor {
        return switch (f) {
            inline else => |p, t| @unionInit(Floor, @tagName(t), p.fit()),
        };
    }

    pub fn valid(f: *const Floor) bool {
        return std.meta.eql(f.fit(), f.*);
    }

    pub fn outdoor(f: Floor) bool {
        return switch (f) {
            .open, .wilds, .terrain, .keep, .town, .dunes, .site => true,
            .rooms, .caves, .cavern, .strata, .labyrinth, .maze => false,
            .hall => |p| switch (p.style) {
                .graves, .grove => true,
                .bare, .pillars => false,
            },
            .topology => |p| switch (p.filler) {
                .rock, .wall => false,
                .shrub, .water, .chasm, .lava, .fence => true,
            },
        };
    }

    pub fn palette(f: Floor) carve.Palette {
        return switch (f) {
            .rooms => carve.Palette.BUILT,
            inline else => |p, t| @field(BASES, @tagName(t)).palette(p),
        };
    }
};


/// Laid over a base, in order.
pub const Kind = enum { river, lake, road, scatter, border, buildings, farms, setpiece };

const FEATURES = .{
    .river = river,
    .lake = lake,
    .road = road,
    .scatter = scatter,
    .border = border,
    .buildings = buildings,
    .farms = farms,
    .setpiece = setpiece,
};

pub const Feature = union(Kind) {
    river: river.Params,
    lake: lake.Params,
    road: road.Params,
    scatter: scatter.Params,
    border: border.Params,
    buildings: buildings.Params,
    farms: farms.Params,
    setpiece: setpiece.Params,

    pub fn of(k: Kind) Feature {
        return switch (k) {
            inline else => |t| @unionInit(Feature, @tagName(t), .{}),
        };
    }

    pub fn fit(f: Feature) Feature {
        return switch (f) {
            inline else => |p, t| @unionInit(Feature, @tagName(t), p.fit()),
        };
    }

    pub fn valid(f: *const Feature) bool {
        return std.meta.eql(f.fit(), f.*);
    }

    fn apply(f: Feature, lv: *grid.Level, rng: *mathx.Rng, seed: u64, pal: carve.Palette) void {
        switch (f) {
            inline else => |p, t| @field(FEATURES, @tagName(t)).apply(lv, rng, seed, pal, p),
        }
    }
};

/// Reproducible from the seed, the doors and the plan; the edge sealed, then every open cell joined, each door too.
pub fn roll(lv: *grid.Level, seed: u64, doors: []const P, floor: Floor, features: []const Feature) void {
    std.debug.assert(doors.len <= grid.MAX_DOORS);
    const pal = floor.palette();
    var rooms: ?*const Shaped = null;
    var shaped: Shaped = undefined;
    switch (floor) {
        .rooms => |p| {
            _ = gen.around(lv, seed, doors, p);
            if (features.len == 0) return;
            shaped = .{ .tile = lv.tile, .shape = lv.shape };
            rooms = &shaped;
        },
        inline else => |p, t| {
            lv.* = grid.Level.blank();
            var rng = mathx.Rng.init(seed);
            @field(BASES, @tagName(t)).shape(lv, &rng, seed, p.fit());
            carve.openDoors(lv, doors, pal.open);
        },
    }
    var rng = mathx.Rng.init(seed ^ FEATURE_SALT);
    for (features, 0..) |f, i| f.fit().apply(lv, &rng, seed +% i *% FEATURE_SALT, pal);
    carve.seal(lv, pal.solid);
    carve.openDoors(lv, doors, pal.open);
    if (lv.firstOpen() == null) carve.disc(lv, grid.MIDDLE, CLEARING_R, pal.open, null);
    carve.connect(lv, &rng, pal);
    settle(lv, rooms);
}

/// A floor rolled with no open ground and no door gets this clearing at its middle to start in.
const CLEARING_R: f32 = 3;

/// The rooms' tiles and wall shapes before any feature was laid.
const Shaped = struct { tile: [grid.CELLS]grid.Tile, shape: [grid.CELLS]?grid.WallShape };

fn settle(lv: *grid.Level, rooms: ?*const Shaped) void {
    for (0..grid.CELLS) |i| {
        if (lv.barrel[i] and (lv.tile[i].solid() or lv.door[i] != grid.NO_DOOR)) lv.barrel[i] = false;
    }
    carve.unbar(lv);
    gen.shapeWalls(lv);
    if (rooms) |was| {
        for (0..grid.CELLS) |i| {
            if (was.shape[i] != null and lv.shape[i] != null and untouched(lv, &was.tile, grid.Level.of(i))) lv.shape[i] = was.shape[i];
        }
    }
    var kept: usize = 0;
    for (lv.torches()) |t| {
        if (lv.wallShape(t) != .top or !lv.walkable(lume.torchFloor(t))) continue;
        lv.torch[kept] = t;
        kept += 1;
    }
    lv.torch_n = kept;
}

fn untouched(lv: *const grid.Level, was: *const [grid.CELLS]grid.Tile, p: P) bool {
    var cells = grid.Cells.around(p, 1);
    while (cells.next()) |q| {
        if (lv.at(q) != grid.cellOr(grid.Tile, was, q, .wall)) return false;
    }
    return true;
}

const TEST_RUNS: usize = 12;

test "every base, bare and under every feature, joins its ground, reaches its doors and seals its edge" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var rng = mathx.Rng.init(0x9E0);
    const kinds = comptime std.enums.values(Kind);
    var all: [kinds.len]Feature = undefined;
    for (kinds, &all) |k, *f| f.* = Feature.of(k);
    for (std.enums.values(Algo)) |a| {
        var least: usize = grid.CELLS;
        var most: usize = 0;
        for (0..TEST_RUNS) |i| {
            const doors = [_]P{
                .{ .x = 0, .y = rng.range(1, grid.H - 2) },
                .{ .x = grid.W - 1, .y = rng.range(1, grid.H - 2) },
                .{ .x = rng.range(1, grid.W - 2), .y = grid.H - 1 },
                .{ .x = rng.range(3, grid.W - 4), .y = rng.range(3, grid.H - 4) },
            };
            const features: []const Feature = switch (i % 3) {
                0 => &.{},
                1 => all[0 .. all.len / 2],
                else => &all,
            };
            const seed = 0x51ED +% i *% 7919;
            roll(&lv, seed, &doors, Floor.of(a), features);
            var open_n: usize = 0;
            for (lv.tile) |t| {
                if (!t.solid()) open_n += 1;
            }
            try std.testing.expectEqual(open_n, grid.distances(&lv, doors[0], &dist, &queue));
            for (doors, 0..) |d, k| try std.testing.expectEqual(@as(?usize, k), lv.doorAt(d));
            for (0..grid.CELLS) |k| {
                const p = grid.Level.of(k);
                if (grid.Level.onRim(p) and lv.walkable(p)) try std.testing.expect(lv.doorAt(p) != null);
                if (lv.barrel[k]) try std.testing.expect(lv.walkable(p));
            }
            var again: grid.Level = undefined;
            roll(&again, seed, &doors, Floor.of(a), features);
            try std.testing.expectEqualSlices(grid.Tile, &lv.tile, &again.tile);
            carve.unbar(&again);
            try std.testing.expectEqualSlices(bool, &lv.barrel, &again.barrel);
            least = @min(least, open_n);
            most = @max(most, open_n);
        }
        std.debug.print("{s}: open ground {d}% to {d}% of the map\n", .{ @tagName(a), least * 100 / grid.CELLS, most * 100 / grid.CELLS });
        try std.testing.expect(least * 10 > grid.CELLS);
    }
}

test "a doorless floor rolled all solid still has ground to start on" {
    var lv: grid.Level = undefined;
    const thick = [_]Feature{.{ .scatter = .{ .tile = .shrub, .on = .grass, .amount = 1000 } }};
    roll(&lv, 0xD0, &.{}, .{ .open = .{ .decor = .{ .tiny_shrubs = 0, .tall_grass = 0, .shrooms = 0 } } }, &thick);
    try std.testing.expect(lv.firstOpen() != null);
    try std.testing.expect(lv.walkable(grid.MIDDLE));
}

test "a feature that changes nothing leaves the rooms' wall shapes as they were" {
    var bare: grid.Level = undefined;
    var laid: grid.Level = undefined;
    const none = [_]Feature{.{ .scatter = .{ .tile = .shrub, .on = .grass, .amount = 0 } }};
    roll(&bare, 0x2007, &.{}, Floor.of(.rooms), &.{});
    roll(&laid, 0x2007, &.{}, Floor.of(.rooms), &none);
    try std.testing.expectEqualSlices(grid.Tile, &bare.tile, &laid.tile);
    try std.testing.expectEqualSlices(?grid.WallShape, &bare.shape, &laid.shape);
}
