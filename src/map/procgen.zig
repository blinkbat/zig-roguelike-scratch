const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const gen = @import("gen.zig");
const carve = @import("carve.zig");
const branches = @import("branches.zig");
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
const tee = @import("biome/tee.zig");
const river = @import("feature/river.zig");
const lake = @import("feature/lake.zig");
const road = @import("feature/road.zig");
const scatter = @import("feature/scatter.zig");
const border = @import("feature/border.zig");
const buildings = @import("feature/buildings.zig");
const farms = @import("feature/farms.zig");
const setpiece = @import("feature/setpiece.zig");
const coast = @import("feature/coast.zig");
const section = @import("section.zig");

const P = mathx.P;

pub const MAX_FEATURES: usize = 10;
const FEATURE_STRIDE: u64 = @intFromEnum(carve.Salt.features);

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
    .tee = tee,
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
    tee: tee.Params,

    pub fn of(a: Algo) Floor {
        return defaultArm(Floor, a);
    }

    pub fn fit(f: Floor) Floor {
        return fitArm(f);
    }

    pub fn outdoor(f: Floor) bool {
        return switch (f) {
            .open, .wilds, .terrain, .keep, .town, .dunes, .site, .tee => true,
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
        return defaultArm(Feature, k);
    }

    pub fn fit(f: Feature) Feature {
        return fitArm(f);
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

fn defaultArm(comptime U: type, tag: std.meta.Tag(U)) U {
    return switch (tag) {
        inline else => |t| @unionInit(U, @tagName(t), .{}),
    };
}

fn fitArm(u: anytype) @TypeOf(u) {
    return switch (u) {
        inline else => |p, t| @unionInit(@TypeOf(u), @tagName(t), carve.fitted(p)),
    };
}

fn takesLots(comptime m: type) bool {
    for (@typeInfo(@TypeOf(m.apply)).@"fn".params) |a| {
        if (a.type == *buildings.Lots) return true;
    }
    return false;
}

pub const LOTS_MAX: usize = blk: {
    var most: usize = 0;
    for (std.meta.fieldNames(@TypeOf(FEATURES))) |name| {
        const m = @field(FEATURES, name);
        if (takesLots(m)) most = @max(most, m.COUNT_MAX);
    }
    break :blk MAX_FEATURES * most + buildings.SECTION_LOTS;
};

/// Reproducible from the seed, the doors and the plan; the edge sealed, then every open cell joined, each door too.
pub fn roll(lv: *grid.Level, seed: u64, doors: []const P, floor: Floor, features: []const Feature) void {
    rollWith(lv, seed, doors, floor, features, null);
}

/// `roll`, the section's box kept from every feature's lots and its cells painted over theirs; doors win its cells.
pub fn rollWith(lv: *grid.Level, seed: u64, doors: []const P, floor: Floor, features: []const Feature, authored: ?section.Placed) void {
    std.debug.assert(doors.len <= grid.MAX_DOORS);
    const fitted = floor.fit();
    const pal = fitted.palette();
    switch (fitted) {
        .rooms => |p| {
            _ = gen.around(lv, seed, doors, p);
            if (features.len == 0 and authored == null) return;
        },
        inline else => |p, t| {
            var rng = mathx.Rng.init(seed);
            lay(@field(BASES, @tagName(t)), lv, &rng, seed, p);
            carve.openDoors(lv, doors, pal.open);
        },
    }
    var rng = carve.Salt.features.rng(seed);
    const base = lv.tile;
    var lots: buildings.Lots = .{};
    var painted = grid.CellSet.initEmpty();
    if (authored) |s| {
        lots.reserve(s.area);
        painted = s.cells();
    }
    for (features, 0..) |f, i| {
        gen.keepTorches(lv);
        f.fit().apply(lv, &rng, seed +% i *% FEATURE_STRIDE, pal, &lots);
    }
    if (authored) |s| s.stamp(lv);
    carve.seal(lv, pal.solid);
    carve.openDoors(lv, doors, pal.open);
    if (lv.firstOpen() == null) carve.disc(lv, grid.MIDDLE, CLEARING_R, pal.open, null);
    carve.connect(lv, &rng, pal, .{ .lots = lots.slice(), .before = &base, .authored = if (authored != null) &painted else null });
    settle(lv);
    if (fitted == .wilds and branches.improves(fitted.wilds)) {
        _ = branches.improveRound(lv, seed, doors, fitted.wilds, &painted);
        settle(lv);
    }
}

pub fn lay(comptime base: type, lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: anytype) void {
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
    grid.mendProps(&lv.tile);
    carve.unbar(lv);
    gen.reshape(lv);
}

const TEST_RUNS: usize = 12;
const KINDS = std.enums.values(Kind);

fn everyFeature() [KINDS.len]Feature {
    var all: [KINDS.len]Feature = undefined;
    for (KINDS, &all) |k, *f| f.* = Feature.of(k);
    return all;
}

fn testDoors(rng: *mathx.Rng) [4]P {
    return .{
        .{ .x = 0, .y = rng.range(1, grid.H - 2) },
        .{ .x = grid.W - 1, .y = rng.range(1, grid.H - 2) },
        .{ .x = rng.range(1, grid.W - 2), .y = grid.H - 1 },
        .{ .x = rng.range(3, grid.W - 4), .y = rng.range(3, grid.H - 4) },
    };
}

fn testMix(all: []const Feature, i: usize) []const Feature {
    return switch (i % 3) {
        0 => &.{},
        1 => all[0 .. all.len / 2],
        else => all,
    };
}
const COUNT_RUNS: usize = 200;
const SMALL_HOUSES = (buildings.Params{ .count = buildings.COUNT_MAX, .size = .{ 5, 6 } }).fit();
const PACKED_SHRINES = (setpiece.Params{ .piece = .shrine, .count = setpiece.COUNT_MAX, .apart = 0 }).fit();

test "every base, bare and under every feature, joins its ground, reaches its doors and seals its edge" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var rng = mathx.Rng.init(0x9E0);
    const all = everyFeature();
    for (std.enums.values(Algo)) |a| {
        var least: usize = grid.CELLS;
        var most: usize = 0;
        for (0..TEST_RUNS) |i| {
            const doors = testDoors(&rng);
            const features = testMix(&all, i);
            const seed = 0x51ED +% i *% grid.TEST_SEED_STRIDE;
            roll(&lv, seed, &doors, Floor.of(a), features);
            try grid.expectAllReached(&lv, doors[0], &dist, &queue);
            const open_n = lv.openCount();
            for (doors, 0..) |d, k| try std.testing.expectEqual(@as(?usize, k), lv.doorAt(d));
            try std.testing.expectEqual(@as(usize, 0), carve.leaks(&lv));
            for (0..grid.CELLS) |k| {
                if (lv.barrel[k]) try std.testing.expect(lv.walkable(grid.Level.of(k)));
            }
            var again: grid.Level = undefined;
            roll(&again, seed, &doors, Floor.of(a), features);
            try std.testing.expectEqualSlices(grid.Tile, &lv.tile, &again.tile);
            carve.unbar(&again);
            try std.testing.expectEqualSlices(bool, &lv.barrel, &again.barrel);
            least = @min(least, open_n);
            most = @max(most, open_n);
        }
        try std.testing.expect(least * 10 > grid.CELLS);
    }
}

const SECTION_ROOM = grid.Box.sized(.{ .x = 30, .y = 20 }, 9, 7);
const SECTION_TORCH = P{ .x = 34, .y = 20 };

/// A walled room, its way in on the south side unless `shut`, a barrel and a torch inside.
fn testSection(anchor: section.Anchor, shut: bool) section.Section {
    var s = section.Section{ .anchor = anchor };
    var it = SECTION_ROOM.cells();
    while (it.next()) |p| _ = s.paint(p, if (SECTION_ROOM.onEdge(p)) .wall else .floor);
    if (!shut) _ = s.paint(.{ .x = 34, .y = SECTION_ROOM.hi.y - 1 }, .floor);
    _ = s.addTorch(SECTION_TORCH);
    _ = s.putBarrel(SECTION_ROOM.lo.add(.{ .x = 1, .y = 1 }));
    return s;
}

fn nearDoor(q: P, doors: []const P) bool {
    return grid.anyNear(q, doors, 2);
}

test "every base under every feature mix keeps a section's painted cells and torch, joined to its doors" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var rng = mathx.Rng.init(0x5EC);
    const all = everyFeature();
    const anchors = std.enums.values(section.Anchor);
    var lost: usize = 0;
    var dark: usize = 0;
    for (std.enums.values(Algo)) |a| {
        for (0..TEST_RUNS) |i| {
            const doors = testDoors(&rng);
            const features = testMix(&all, i);
            const seed = 0x5EC7 +% i *% grid.TEST_SEED_STRIDE;
            const s = testSection(anchors[i % anchors.len], false);
            const laid = s.lands(seed, &doors).?;
            rollWith(&lv, seed, &doors, Floor.of(a), features, laid);
            try grid.expectAllReached(&lv, doors[0], &dist, &queue);
            try std.testing.expectEqual(@as(usize, 0), carve.leaks(&lv));
            for (s.tile, 0..) |t, k| {
                const q = laid.at(grid.Level.of(k));
                if (t == null or nearDoor(q, &doors)) continue;
                const here = grid.Level.idx(q);
                if (lv.tile[here] != t.?) lost += 1;
            }
            if (!nearDoor(laid.at(SECTION_TORCH), &doors) and !lv.torch.has(laid.at(SECTION_TORCH))) dark += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), lost);
    try std.testing.expectEqual(@as(usize, 0), dark);
}

test "a section painted shut is opened through one wall cell and the rest of its walls stand" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const doors = [_]P{ .{ .x = 0, .y = 30 }, .{ .x = grid.W - 1, .y = 12 } };
    const RUNS = 50;
    for ([_]Algo{ .open, .wilds, .caves, .rooms }) |a| {
        var other: usize = 0;
        var dark: usize = 0;
        for (0..RUNS) |i| {
            const seed = 0x5407 +% i *% grid.TEST_SEED_STRIDE;
            const s = testSection(.roams, true);
            const laid = s.lands(seed, &doors).?;
            rollWith(&lv, seed, &doors, Floor.of(a), &.{}, laid);
            try grid.expectAllReached(&lv, doors[0], &dist, &queue);
            if (!nearDoor(laid.at(SECTION_TORCH), &doors) and !lv.torch.has(laid.at(SECTION_TORCH))) dark += 1;
            var breached: usize = 0;
            var it = SECTION_ROOM.cells();
            while (it.next()) |p| {
                if (SECTION_ROOM.onEdge(p) and !lv.at(laid.at(p)).solid()) breached += 1;
            }
            if (breached != 1) other += 1;
        }
        try std.testing.expectEqual(@as(usize, 0), other);
        try std.testing.expectEqual(@as(usize, 0), dark);
    }
}

test "no house, farm or set piece is raised in a section's box" {
    var lv: grid.Level = undefined;
    const features = [_]Feature{
        .{ .farms = (farms.Params{ .count = farms.COUNT_MAX }).fit() },
        .{ .buildings = SMALL_HOUSES },
        .{ .setpiece = PACKED_SHRINES },
    };
    var s = section.Section{ .anchor = .roams };
    const b = grid.Box.sized(.{ .x = 40, .y = 25 }, 16, 12);
    for (carve.corners(b)) |p| _ = s.paint(p, .dirt);
    var built: usize = 0;
    var over: usize = 0;
    for (0..COUNT_RUNS) |i| {
        const seed = 0xB0C5 +% i *% grid.TEST_SEED_STRIDE;
        const laid = s.lands(seed, &.{}).?;
        rollWith(&lv, seed, &.{}, Floor.of(.open), &features, laid);
        built += carve.count(&lv, .wall);
        var it = laid.area.cells();
        while (it.next()) |q| {
            const t = lv.at(q);
            if (t == .wall or t == .fence or t == .crop) over += 1;
        }
    }
    try std.testing.expect(built > COUNT_RUNS);
    try std.testing.expectEqual(@as(usize, 0), over);
}

test "a node with no section, roaming or not, rolls exactly the plain roll" {
    var plain: grid.Level = undefined;
    var with: grid.Level = undefined;
    const doors = [_]P{ .{ .x = 0, .y = 30 }, .{ .x = 50, .y = grid.H - 1 } };
    const features = [_]Feature{ Feature.of(.buildings), Feature.of(.river) };
    for (std.enums.values(Algo)) |a| {
        for (std.enums.values(section.Anchor)) |anchor| {
            const s = section.Section{ .anchor = anchor };
            roll(&plain, 0xE3, &doors, Floor.of(a), &features);
            rollWith(&with, 0xE3, &doors, Floor.of(a), &features, s.lands(0xE3, &doors));
            try std.testing.expectEqualSlices(grid.Tile, &plain.tile, &with.tile);
            try std.testing.expectEqualSlices(bool, &plain.barrel, &with.barrel);
        }
    }
}

test "a torch a border buries frees its slot for the houses raised after it" {
    var lv: grid.Level = undefined;
    const floor = Floor{ .rooms = .{ .torches = mathx.PERCENT } };
    const features = [_]Feature{
        .{ .border = .{ .width = border.WIDTH_MAX / 2 } },
        .{ .buildings = .{ .count = buildings.COUNT_MAX, .size = .{ 5, 6 }, .torches = mathx.PERCENT } },
    };
    var least: usize = grid.MAX_TORCHES;
    var sum: usize = 0;
    for (0..COUNT_RUNS) |i| {
        roll(&lv, 0x70C +% i *% grid.TEST_SEED_STRIDE, &.{}, floor, &features);
        least = @min(least, lv.torch.n);
        sum += lv.torch.n;
    }
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
            const seed = 0x5E7 +% i *% grid.TEST_SEED_STRIDE;
            var rng = laidAt(wilds, &lv, seed, p);
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
                const seed = 0x5E7 +% i *% grid.TEST_SEED_STRIDE;
                var rng = laidAt(base, &lv, seed, p);
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
            const seed = 0x51ED +% i *% grid.TEST_SEED_STRIDE;
            var rng = laidAt(base, &lv, seed, p);
            var lots: buildings.Lots = .{};
            buildings.apply(&lv, &rng, seed, pal, &lots, (buildings.Params{}).fit());
            if (joinsLose(&lv, &rng, pal, .{}, .floor)) lost += 1;
        }
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
            const seed = 0xB0DE +% i *% grid.TEST_SEED_STRIDE;
            var rng = laidAt(base, &lv, seed, p);
            var lots: buildings.Lots = .{};
            if (base == wilds) border.apply(&lv, &rng, seed, pal, (border.Params{}).fit()) else buildings.apply(&lv, &rng, seed, pal, &lots, SMALL_HOUSES);
            lots.begin();
            buildings.apply(&lv, &rng, seed, pal, &lots, SMALL_HOUSES);
            lots.begin();
            setpiece.apply(&lv, &rng, seed, pal, &lots, PACKED_SHRINES);
            if (joinsLose(&lv, &rng, pal, .{}, .floor)) lost += 1;
        }
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
            const seed = 0x7A1C +% i *% grid.TEST_SEED_STRIDE;
            var rng = laidAt(wilds, &lv, seed, p);
            var lots: buildings.Lots = .{};
            buildings.apply(&lv, &rng, seed, pal, &lots, SMALL_HOUSES);
            scatter.apply(&lv, &rng, seed, pal, thicket.fit());
            if (joinsLose(&lv, &rng, pal, .{}, .floor)) lost += 1;
        }
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
            const seed = 0xF100 +% i *% grid.TEST_SEED_STRIDE;
            var rng = laidAt(b[0], &lv, seed, p);
            var lots: buildings.Lots = .{};
            buildings.apply(&lv, &rng, seed, pal, &lots, SMALL_HOUSES);
            border.apply(&lv, &rng, seed, pal, rim);
            carve.seal(&lv, pal.solid);
            var laid = grid.CellSet.initEmpty();
            for (lots.slice()) |box| {
                var cells = box.cells();
                while (cells.next()) |q| {
                    if (!lv.at(q).solid()) laid.set(grid.Level.idx(q));
                }
            }
            carve.connect(&lv, &rng, pal, .{ .lots = lots.slice() });
            if (filled(&lv, &laid)) lost += 1;
        }
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
            const seed = 0xFA2E +% i *% grid.TEST_SEED_STRIDE;
            var rng = laidAt(base, &lv, seed, p);
            var lots: buildings.Lots = .{};
            farms.apply(&lv, &rng, seed, pal, &lots, (farms.Params{}).fit());
            if (joinsLose(&lv, &rng, pal, .{ .lots = lots.slice() }, .fence)) broken += 1;
        }
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
            const seed = 0xF02D +% i *% grid.TEST_SEED_STRIDE;
            var rng = laidAt(b, &lv, seed, p);
            base = lv.tile;
            river.apply(&lv, &rng, seed, pal, cliff);
            carve.seal(&lv, pal.solid);
            var opened = grid.CellSet.initEmpty();
            for (lv.tile, base, 0..) |t, was, k| opened.setValue(k, was.solid() and !t.solid());
            carve.connect(&lv, &rng, pal, .{ .before = &base });
            if (filled(&lv, &opened)) lost += 1;
        }
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
            const seed = 0x4A3 +% i *% grid.TEST_SEED_STRIDE;
            var rng = laidAt(b[0], &lv, seed, p);
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
        try std.testing.expectEqual(@as(usize, 0), hit);
    }
}

fn laidAt(comptime base: type, lv: *grid.Level, seed: u64, p: anytype) mathx.Rng {
    var rng = mathx.Rng.init(seed);
    lay(base, lv, &rng, seed, p);
    return rng;
}

fn joinsLose(lv: *grid.Level, rng: *mathx.Rng, pal: carve.Palette, laid: carve.Laid, t: grid.Tile) bool {
    carve.seal(lv, pal.solid);
    const before = carve.count(lv, t);
    carve.connect(lv, rng, pal, laid);
    return carve.count(lv, t) < before;
}

fn filled(lv: *const grid.Level, cells: *const grid.CellSet) bool {
    var it = cells.iterator(.{});
    while (it.next()) |k| {
        if (lv.tile[k].solid()) return true;
    }
    return false;
}

/// Excludes changes to the base's open ground.
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
    var decor: usize = 0;
    var plants = grid.LITTER_TILES.iterator();
    while (plants.next()) |t| decor += carve.count(&lv, t);
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
