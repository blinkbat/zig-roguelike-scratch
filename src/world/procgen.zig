const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
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
const coast = @import("feature/coast.zig");

const P = mathx.P;

pub const MAX_FEATURES: usize = 6;
/// Its features draw from another stream than the base, so adding one leaves the base as it was.
const FEATURE_SALT: u64 = 0xFEA7_0BE5;

/// A base biome: `gen.around`'s rooms, or a module with `Params`, `shape` and `palette`.
pub const Algo = std.meta.Tag(Floor);

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

pub const Floor = union(enum) {
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
            inline else => |p, t| @unionInit(Floor, @tagName(t), carve.fitDress(p.fit())),
        };
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
pub const Kind = std.meta.Tag(Feature);

const FEATURES = .{
    .river = river,
    .lake = lake,
    .road = road,
    .scatter = scatter,
    .border = border,
    .buildings = buildings,
    .farms = farms,
    .setpiece = setpiece,
    .coast = coast,
};

/// Every module listed is an arm of its union, holding the module's `Params`.
fn armsOf(comptime U: type, comptime modules: anytype) void {
    for (std.meta.fieldNames(@TypeOf(modules))) |name| {
        if (!@hasField(U, name) or @FieldType(U, name) != @field(modules, name).Params) @compileError(name ++ " is no arm of " ++ @typeName(U));
    }
}

comptime {
    armsOf(Floor, BASES);
    armsOf(Feature, FEATURES);
}

pub const Feature = union(enum) {
    river: river.Params,
    lake: lake.Params,
    road: road.Params,
    scatter: scatter.Params,
    border: border.Params,
    buildings: buildings.Params,
    farms: farms.Params,
    setpiece: setpiece.Params,
    coast: coast.Params,

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

    fn apply(f: Feature, lv: *grid.Level, rng: *mathx.Rng, seed: u64, pal: carve.Palette, lots: *buildings.Lots) void {
        switch (f) {
            inline else => |p, t| {
                const m = @field(FEATURES, @tagName(t));
                if (comptime takesLots(m)) {
                    lots.begin();
                    m.apply(lv, rng, seed, pal, lots, p);
                } else m.apply(lv, rng, seed, pal, p);
            },
        }
    }
};

/// A feature that raises things on lots, clear of every other feature's.
fn takesLots(comptime m: type) bool {
    for (@typeInfo(@TypeOf(m.apply)).@"fn".params) |a| {
        if (a.type == *buildings.Lots) return true;
    }
    return false;
}

comptime {
    var most: usize = 0;
    for (std.meta.fieldNames(@TypeOf(FEATURES))) |name| {
        const m = @field(FEATURES, name);
        if (takesLots(m)) most = @max(most, m.COUNT_MAX);
    }
    std.debug.assert(buildings.LOTS_MAX >= MAX_FEATURES * most);
}

/// Reproducible from the seed, the doors and the plan; the edge sealed, then every open cell joined, each door too.
pub fn roll(lv: *grid.Level, seed: u64, doors: []const P, floor: Floor, features: []const Feature) void {
    std.debug.assert(doors.len <= grid.MAX_DOORS);
    const pal = floor.palette();
    switch (floor.fit()) {
        .rooms => |p| {
            _ = gen.around(lv, seed, doors, p);
            if (features.len == 0) return;
        },
        inline else => |p, t| {
            var rng = mathx.Rng.init(seed);
            lay(@field(BASES, @tagName(t)), lv, &rng, seed, p);
            carve.openDoors(lv, doors, pal.open);
        },
    }
    var rng = mathx.Rng.init(seed ^ FEATURE_SALT);
    const base = lv.tile;
    var lots: buildings.Lots = .{};
    for (features, 0..) |f, i| {
        reshape(lv);
        f.fit().apply(lv, &rng, seed +% i *% FEATURE_SALT, pal, &lots);
    }
    carve.seal(lv, pal.solid);
    carve.openDoors(lv, doors, pal.open);
    if (lv.firstOpen() == null) carve.disc(lv, grid.MIDDLE, CLEARING_R, pal.open, null);
    carve.connect(lv, &rng, pal, .{ .lots = lots.slice(), .before = &base });
    settle(lv);
}

fn lay(comptime base: type, lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: anytype) void {
    lv.* = grid.Level.blank();
    base.shape(lv, rng, seed, p);
    carve.dress(p, lv, rng, seed);
}

/// A floor rolled with no open ground and no door gets this clearing at its middle to start in.
const CLEARING_R: f32 = 3;

fn settle(lv: *grid.Level) void {
    for (0..grid.CELLS) |i| {
        if (lv.barrel[i] and (lv.tile[i].solid() or lv.door[i] != grid.NO_DOOR)) lv.barrel[i] = false;
    }
    carve.unbar(lv);
    reshape(lv);
}

/// Walls shaped afresh and the torches they no longer bear dropped, so a buried torch frees its slot.
fn reshape(lv: *grid.Level) void {
    gen.shapeWalls(lv);
    gen.keepTorches(lv);
}

const TEST_RUNS: usize = 12;
/// Maps a count test rolls to say how many of them go wrong.
const COUNT_RUNS: usize = 200;
const SMALL_HOUSES = (buildings.Params{ .count = buildings.COUNT_MAX, .size = .{ 5, 6 } }).fit();
const PACKED_SHRINES = (setpiece.Params{ .piece = .shrine, .count = setpiece.COUNT_MAX, .apart = 0 }).fit();

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
            const open_n = lv.openCount();
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

test "a torch a border buries frees its slot for the houses raised after it" {
    var lv: grid.Level = undefined;
    const floor = Floor{ .rooms = .{ .torches = mathx.PERCENT } };
    const features = [_]Feature{
        .{ .border = .{ .width = border.WIDTH_MAX } },
        .{ .buildings = .{ .count = buildings.COUNT_MAX, .size = .{ 5, 6 }, .torches = mathx.PERCENT } },
    };
    var least: usize = grid.MAX_TORCHES;
    var sum: usize = 0;
    for (0..COUNT_RUNS) |i| {
        roll(&lv, 0x70C +% i *% 7919, &.{}, floor, &features);
        least = @min(least, lv.torch.n);
        sum += lv.torch.n;
    }
    std.debug.print("rooms all torched, a wide border, then houses all torched: {d} to {d} torches, {d} average of {d}\n", .{ least, grid.MAX_TORCHES, sum / COUNT_RUNS, grid.MAX_TORCHES });
    try std.testing.expect(sum / COUNT_RUNS * 2 > grid.MAX_TORCHES);
}

test "a doorless floor rolled all solid still has ground to start on" {
    var lv: grid.Level = undefined;
    const thick = [_]Feature{.{ .scatter = .{ .tile = .shrub, .on = .grass, .amount = scatter.AMOUNT_MAX } }};
    roll(&lv, 0xD0, &.{}, .{ .open = .{ .decor = .{ .tiny_shrubs = 0, .tall_grass = 0, .shrooms = 0 } } }, &thick);
    try std.testing.expect(lv.firstOpen() != null);
    try std.testing.expect(lv.walkable(grid.MIDDLE));
}

test "a set piece in a thicket opens onto the ground round it, so no join fills or breaks into it" {
    var lv: grid.Level = undefined;
    var st: carve.Stretches = .{};
    const p = (wilds.Params{}).fit();
    for (std.enums.values(setpiece.Piece)) |pc| {
        var shut: usize = 0;
        for (0..COUNT_RUNS) |i| {
            const seed = 0x5E7 +% i *% 7919;
            var rng = mathx.Rng.init(seed);
            lay(wilds, &lv, &rng, seed, p);
            var lots: buildings.Lots = .{};
            setpiece.apply(&lv, &rng, seed, wilds.palette(p), &lots, .{ .piece = pc, .count = 1 });
            _ = st.label(&lv);
            const inside = for (lv.tile, 0..) |t, k| {
                if (t == .floor or t == .dirt) break k;
            } else continue;
            const r = st.region[inside];
            const out = for (lv.tile, 0..) |t, k| {
                if (st.region[k] == r and t == .grass) break true;
            } else false;
            if (!out) shut += 1;
        }
        std.debug.print("{s} in the wilds: {d} of {d} shut in\n", .{ @tagName(pc), shut, COUNT_RUNS });
        try std.testing.expectEqual(@as(usize, 0), shut);
    }
}

test "a set piece in a thicket or in rock keeps its ground through the joins" {
    var lv: grid.Level = undefined;
    inline for (.{ wilds, caves }) |base| {
        const p = (base.Params{}).fit();
        const pal = base.palette(p);
        for (std.enums.values(setpiece.Piece)) |pc| {
            var lost: usize = 0;
            for (0..COUNT_RUNS) |i| {
                const seed = 0x5E7 +% i *% 7919;
                var rng = mathx.Rng.init(seed);
                lay(base, &lv, &rng, seed, p);
                const art = setpiece.rows(pc);
                const at = setpiece.cornerFor(grid.MIDDLE, art);
                setpiece.place(&lv, at, art, pal);
                carve.seal(&lv, pal.solid);
                carve.connect(&lv, &rng, pal, .{});
                var gone = false;
                var spots = setpiece.Spots{ .at = at, .art = art };
                while (spots.next()) |s| {
                    const t = grid.Tile.ofLetter(s.c) orelse continue;
                    if (!t.solid() and lv.at(s.q).solid()) gone = true;
                }
                if (gone) lost += 1;
            }
            std.debug.print("{s} in {s}: {d} of {d} maps lost ground to the joins\n", .{ @tagName(pc), @typeName(base), lost, COUNT_RUNS });
            try std.testing.expectEqual(@as(usize, 0), lost);
        }
    }
}

test "a house in a thicket or in rock keeps its floor through the joins" {
    var lv: grid.Level = undefined;
    inline for (.{ wilds, caves, topology }) |base| {
        const p = (base.Params{}).fit();
        const pal = base.palette(p);
        var lost: usize = 0;
        for (0..COUNT_RUNS) |i| {
            const seed = 0x51ED +% i *% 7919;
            var rng = mathx.Rng.init(seed);
            lay(base, &lv, &rng, seed, p);
            var lots: buildings.Lots = .{};
            buildings.apply(&lv, &rng, seed, pal, &lots, (buildings.Params{}).fit());
            carve.seal(&lv, pal.solid);
            const before = carve.count(&lv, .floor);
            carve.connect(&lv, &rng, pal, .{});
            if (carve.count(&lv, .floor) < before) lost += 1;
        }
        std.debug.print("houses in {s}: {d} of {d} maps lost floor to the joins\n", .{ @typeName(base), lost, COUNT_RUNS });
        try std.testing.expectEqual(@as(usize, 0), lost);
    }
}

test "a small house or shrine walled in by an earlier feature keeps its floor through the joins" {
    var lv: grid.Level = undefined;
    inline for (.{ wilds, caves }) |base| {
        const p = (base.Params{}).fit();
        const pal = base.palette(p);
        var lost: usize = 0;
        for (0..COUNT_RUNS) |i| {
            const seed = 0xB0DE +% i *% 7919;
            var rng = mathx.Rng.init(seed);
            lay(base, &lv, &rng, seed, p);
            var lots: buildings.Lots = .{};
            if (base == wilds) border.apply(&lv, &rng, seed, pal, (border.Params{}).fit()) else buildings.apply(&lv, &rng, seed, pal, &lots, SMALL_HOUSES);
            lots.begin();
            buildings.apply(&lv, &rng, seed, pal, &lots, SMALL_HOUSES);
            lots.begin();
            setpiece.apply(&lv, &rng, seed, pal, &lots, PACKED_SHRINES);
            carve.seal(&lv, pal.solid);
            const before = carve.count(&lv, .floor);
            carve.connect(&lv, &rng, pal, .{});
            if (carve.count(&lv, .floor) < before) lost += 1;
        }
        std.debug.print("small houses and shrines after a feature in {s}: {d} of {d} maps lost floor to the joins\n", .{ @typeName(base), lost, COUNT_RUNS });
        try std.testing.expectEqual(@as(usize, 0), lost);
    }
}

test "a small house a later thicket shuts in keeps its floor through the joins" {
    var lv: grid.Level = undefined;
    const p = (wilds.Params{}).fit();
    const pal = wilds.palette(p);
    for ([_]scatter.Params{ .{ .amount = 300, .clump = 6 }, .{ .amount = scatter.AMOUNT_MAX } }) |thicket| {
        var lost: usize = 0;
        for (0..COUNT_RUNS) |i| {
            const seed = 0x7A1C +% i *% 7919;
            var rng = mathx.Rng.init(seed);
            lay(wilds, &lv, &rng, seed, p);
            var lots: buildings.Lots = .{};
            buildings.apply(&lv, &rng, seed, pal, &lots, SMALL_HOUSES);
            scatter.apply(&lv, &rng, seed, pal, thicket.fit());
            carve.seal(&lv, pal.solid);
            const before = carve.count(&lv, .floor);
            carve.connect(&lv, &rng, pal, .{});
            if (carve.count(&lv, .floor) < before) lost += 1;
        }
        std.debug.print("small houses under a thicket of {d} a thousand, clumps {d}: {d} of {d} maps lost floor to the joins\n", .{ thicket.amount, thicket.clump, lost, COUNT_RUNS });
        try std.testing.expectEqual(@as(usize, 0), lost);
    }
}

test "a house floored as the base's own ground keeps it through the joins, a border shutting it in" {
    var lv: grid.Level = undefined;
    const rim = (border.Params{ .width = 6, .rough = border.ROUGH_MAX }).fit();
    inline for (.{ .{ hall, hall.Params{ .style = .grove } }, .{ topology, topology.Params{ .ground = .floor } } }) |b| {
        const p = b[1].fit();
        const pal = b[0].palette(p);
        var lost: usize = 0;
        for (0..COUNT_RUNS) |i| {
            const seed = 0xF100 +% i *% 7919;
            var rng = mathx.Rng.init(seed);
            lay(b[0], &lv, &rng, seed, p);
            var lots: buildings.Lots = .{};
            buildings.apply(&lv, &rng, seed, pal, &lots, SMALL_HOUSES);
            border.apply(&lv, &rng, seed, pal, rim);
            carve.seal(&lv, pal.solid);
            var laid = std.StaticBitSet(grid.CELLS).initEmpty();
            for (lots.slice()) |box| {
                var cells = box.cells();
                while (cells.next()) |q| {
                    if (!lv.at(q).solid()) laid.set(grid.Level.idx(q));
                }
            }
            carve.connect(&lv, &rng, pal, .{ .lots = lots.slice() });
            if (filled(&lv, &laid)) lost += 1;
        }
        std.debug.print("houses then a border in {s}: {d} of {d} maps lost house floor to the joins\n", .{ @typeName(b[0]), lost, COUNT_RUNS });
        try std.testing.expectEqual(@as(usize, 0), lost);
    }
}

test "a field in a thicket keeps its fence through the joins" {
    var lv: grid.Level = undefined;
    inline for (.{wilds}) |base| {
        const p = (base.Params{}).fit();
        const pal = base.palette(p);
        var broken: usize = 0;
        for (0..COUNT_RUNS) |i| {
            const seed = 0xFA2E +% i *% 7919;
            var rng = mathx.Rng.init(seed);
            lay(base, &lv, &rng, seed, p);
            var lots: buildings.Lots = .{};
            farms.apply(&lv, &rng, seed, pal, &lots, (farms.Params{}).fit());
            carve.seal(&lv, pal.solid);
            const before = carve.count(&lv, .fence);
            carve.connect(&lv, &rng, pal, .{ .lots = lots.slice() });
            if (carve.count(&lv, .fence) < before) broken += 1;
        }
        std.debug.print("fields in {s}: {d} of {d} maps had a join break a fence\n", .{ @typeName(base), broken, COUNT_RUNS });
        try std.testing.expectEqual(@as(usize, 0), broken);
    }
}

test "a cliff's fords keep their crossing through the joins" {
    var lv: grid.Level = undefined;
    var base: [grid.CELLS]grid.Tile = undefined;
    const cliff = (river.Params{ .fill = .rock, .bank = .none, .course = .across, .fords = river.FORDS_MAX }).fit();
    inline for (.{ wilds, caves, topology }) |b| {
        const p = (b.Params{}).fit();
        const pal = b.palette(p);
        var lost: usize = 0;
        for (0..COUNT_RUNS) |i| {
            const seed = 0xF02D +% i *% 7919;
            var rng = mathx.Rng.init(seed);
            lay(b, &lv, &rng, seed, p);
            base = lv.tile;
            river.apply(&lv, &rng, seed, pal, cliff);
            carve.seal(&lv, pal.solid);
            var opened = std.StaticBitSet(grid.CELLS).initEmpty();
            for (lv.tile, base, 0..) |t, was, k| opened.setValue(k, was.solid() and !t.solid());
            carve.connect(&lv, &rng, pal, .{ .before = &base });
            if (filled(&lv, &opened)) lost += 1;
        }
        std.debug.print("rock cliffs with {d} fords in {s}: {d} of {d} maps filled a ford\n", .{ cliff.fords, @typeName(b), lost, COUNT_RUNS });
        try std.testing.expectEqual(@as(usize, 0), lost);
    }
}

test "a house or set piece is raised clear of what an earlier feature laid" {
    var lv: grid.Level = undefined;
    var base: [grid.CELLS]grid.Tile = undefined;
    var was: [grid.CELLS]grid.Tile = undefined;
    const houses = (buildings.Params{ .count = 8, .size = .{ 5, 9 } }).fit();
    inline for (.{ .{ open, open.Params{} }, .{ hall, hall.Params{} } }) |b| {
        const p = b[1].fit();
        const pal = b[0].palette(p);
        var hit: usize = 0;
        for (0..COUNT_RUNS) |i| {
            const seed = 0x4A3 +% i *% 7919;
            var rng = mathx.Rng.init(seed);
            lay(b[0], &lv, &rng, seed, p);
            var lots: buildings.Lots = .{};
            base = lv.tile;
            farms.apply(&lv, &rng, seed, pal, &lots, (farms.Params{ .count = 6 }).fit());
            was = lv.tile;
            lots.begin();
            buildings.apply(&lv, &rng, seed, pal, &lots, houses);
            var over = laidOver(&lv, &was, &base, pal);
            was = lv.tile;
            lots.begin();
            setpiece.apply(&lv, &rng, seed, pal, &lots, PACKED_SHRINES);
            over = over or laidOver(&lv, &was, &base, pal);
            if (over) hit += 1;
        }
        std.debug.print("houses after fields, shrines after both, in {s}: {d} of {d} maps laid over them\n", .{ @typeName(b[0]), hit, COUNT_RUNS });
        try std.testing.expectEqual(@as(usize, 0), hit);
    }
}

fn filled(lv: *const grid.Level, cells: *const std.StaticBitSet(grid.CELLS)) bool {
    var it = cells.iterator(.{});
    while (it.next()) |k| {
        if (lv.tile[k].solid()) return true;
    }
    return false;
}

/// A cell an earlier feature laid, more than the base's open ground, changed since `was`.
fn laidOver(lv: *const grid.Level, was: *const [grid.CELLS]grid.Tile, base: *const [grid.CELLS]grid.Tile, pal: carve.Palette) bool {
    for (lv.tile, was, base) |t, w, s| {
        if (w != s and w != pal.open and t != w) return true;
    }
    return false;
}

test "a scatter over grass takes the decor standing on it too" {
    var lv: grid.Level = undefined;
    const frozen = [_]Feature{.{ .scatter = .{ .tile = .snow, .on = .grass, .amount = scatter.AMOUNT_MAX } }};
    roll(&lv, 0xF0, &.{}, Floor.of(.open), &frozen);
    const decor = carve.count(&lv, .tall_grass) + carve.count(&lv, .tiny_shrub) + carve.count(&lv, .shrooms);
    std.debug.print("open ground but frozen: {d} decor left, {d} snow\n", .{ decor, carve.count(&lv, .snow) });
    try std.testing.expectEqual(@as(usize, 0), decor);
}

test "a feature that changes nothing leaves the rooms as they were" {
    var bare: grid.Level = undefined;
    var laid: grid.Level = undefined;
    const none = [_]Feature{.{ .scatter = .{ .tile = .shrub, .on = .grass, .amount = 0 } }};
    roll(&bare, 0x2007, &.{}, Floor.of(.rooms), &.{});
    roll(&laid, 0x2007, &.{}, Floor.of(.rooms), &none);
    try std.testing.expectEqualSlices(grid.Tile, &bare.tile, &laid.tile);
}
