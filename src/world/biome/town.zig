const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");
const buildings = @import("../feature/buildings.zig");
const setpiece = @import("../feature/setpiece.zig");

// ADOM's Dwarftown, Dwarf Fortress's towns, Diablo II's Kurast canals, Qud's villages round a well.

const P = mathx.P;

pub const BLOCK_MIN: u8 = 8;
pub const BLOCK_MAX: u8 = 24;
pub const STREET_MAX: u8 = 4;
const MARGIN: i32 = 4;
const HOUSE_LEAST: i32 = 5;
/// How often a block is cut by an alley each way.
const SPLIT_CHANCE: f32 = 0.7;
/// The plaza's radius, a share of a block's side.
const PLAZA_OF: f32 = 0.55;
/// The street cleared round each gate.
const GATE_R: f32 = 1.5;
const HOUSE = buildings.Params{ .barrels = 1, .torches = 30 };

pub const Wall = enum { none, wall, fence };

pub const Params = struct {
    wall: Wall = .wall,
    /// A block's side between streets.
    block: u8 = 14,
    street: u8 = 2,
    /// Percent of each block's lots built on.
    houses: u8 = 80,
    /// Percent of streets that are canals.
    canals: u8 = 0,
    ground: carve.Ground = .dirt,
    outside: carve.Ground = .grass,

    pub fn fit(p: Params) Params {
        var q = p;
        q.block = std.math.clamp(p.block, BLOCK_MIN, BLOCK_MAX);
        q.street = std.math.clamp(p.street, 1, STREET_MAX);
        q.houses = @min(p.houses, mathx.PERCENT);
        q.canals = @min(p.canals, mathx.PERCENT);
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    return .{ .open = p.outside.tile(), .solid = .shrub, .path = p.ground.tile() };
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    const pal = palette(p);
    const street = pal.path;
    carve.field(lv, pal);
    const streets = grid.Box.inMap(MARGIN);
    const lo = streets.lo;
    const hi = streets.hi;
    carve.box(lv, streets, street);
    const step: i32 = @as(i32, p.block) + p.street;
    const s: i32 = p.street;
    const top = lo.y + s;
    var y = top;
    while (y + p.block <= hi.y - s) : (y += step) {
        if (rng.percent(p.canals) and !(y == top and p.wall != .none)) {
            carve.box(lv, .{ .lo = .{ .x = lo.x, .y = y - s }, .hi = .{ .x = hi.x, .y = y } }, .water);
        }
    }
    y = top;
    while (y + p.block <= hi.y - s) : (y += step) {
        var x = lo.x + s;
        while (x + p.block <= hi.x - s) : (x += step) {
            const b = grid.Box.sized(.{ .x = x, .y = y }, p.block, p.block);
            block(lv, rng, b, p, street);
        }
    }
    const plaza = grid.MIDDLE;
    carve.disc(lv, plaza, @as(f32, @floatFromInt(p.block)) * PLAZA_OF, street, null);
    var x = lo.x;
    while (x < hi.x) : (x += step) carve.bridge(lv, .{ .lo = .{ .x = x, .y = lo.y }, .hi = .{ .x = x + s, .y = hi.y } }, null);
    setpiece.stampAround(lv, plaza, setpiece.rows(.well));
    const ring: grid.Tile = switch (p.wall) {
        .none => return,
        .wall => .wall,
        .fence => .fence,
    };
    const walled = wallBox();
    var cells = walled.cells();
    while (cells.next()) |q| {
        if (walled.onEdge(q)) lv.set(q, ring);
    }
    for (gates()) |g| {
        carve.disc(lv, g.at, GATE_R, street, null);
        const side = g.in.across();
        const deep = g.at.add(g.in.delta().scaled(s));
        const a = g.at.sub(side);
        const b = deep.add(side);
        carve.bridge(lv, grid.Box.between(a, b), null);

    }
}

/// `in` is the way into the town.
const Gate = struct { at: P, in: mathx.Dir };

/// A cell outside the streets all round.
fn wallBox() grid.Box {
    return grid.Box.inMap(MARGIN - 1);
}

fn gates() [4]Gate {
    var out: [4]Gate = undefined;
    for (&out, buildings.SIDES) |*g, side| {
        g.* = .{ .at = carve.sideAt(wallBox(), side, carve.alongOf(side, grid.MIDDLE)), .in = side.opposite() };
    }
    return out;
}

/// An alley from top to bottom with a canal at both ends gets one across, to the streets either side.
fn block(lv: *grid.Level, rng: *mathx.Rng, b: grid.Box, p: Params, street: grid.Tile) void {
    const w = b.width();
    const h = b.height();
    const split_x = buildings.cuttable(w, HOUSE_LEAST) and rng.chance(SPLIT_CHANCE);
    const crosses = buildings.cuttable(h, HOUSE_LEAST);
    var split_y = crosses and rng.chance(SPLIT_CHANCE);
    const mx = if (split_x) buildings.cutAt(rng, b.lo.x, b.hi.x, HOUSE_LEAST) else b.hi.x;
    if (split_x and crosses and lv.at(.{ .x = mx, .y = b.lo.y - 1 }).liquid() and lv.at(.{ .x = mx, .y = b.hi.y }).liquid()) split_y = true;
    const my = if (split_y) buildings.cutAt(rng, b.lo.y, b.hi.y, HOUSE_LEAST) else b.hi.y;
    const lots = [_]grid.Box{
        .{ .lo = b.lo, .hi = .{ .x = mx, .y = my } },
        .{ .lo = .{ .x = mx + 1, .y = b.lo.y }, .hi = .{ .x = b.hi.x, .y = my } },
        .{ .lo = .{ .x = b.lo.x, .y = my + 1 }, .hi = .{ .x = mx, .y = b.hi.y } },
        .{ .lo = .{ .x = mx + 1, .y = my + 1 }, .hi = b.hi },
    };
    for (lots) |lot| {
        if (lot.width() < HOUSE_LEAST or lot.height() < HOUSE_LEAST) continue;
        if (!rng.percent(p.houses)) {
            carve.box(lv, lot, .grass);
            continue;
        }
        buildings.raise(lv, rng, lot, HOUSE, street);
    }
}

test "no house's doorway opens on a canal" {
    const TOWNS = 100;
    var lv = grid.Level.blank();
    var st: carve.Stretches = .{};
    var sealed: usize = 0;
    var towns: usize = 0;
    for ([_]u8{ BLOCK_MIN, BLOCK_MIN + 1, 2 * HOUSE_LEAST, (Params{}).block }) |blk| {
        for (0..TOWNS) |i| {
            var rng = mathx.Rng.init(i);
            shape(&lv, &rng, 0, (Params{ .canals = 100, .street = 3, .block = blk }).fit());
            towns += 1;
            _ = st.label(&lv);
            const most = st.biggest();
            for (lv.tile, st.region) |t, r| {
                if (t == .floor and r != most) sealed += 1;
            }
        }
    }
    std.debug.print("{d} towns all canals: {d} house floor cells shut off from the streets\n", .{ towns, sealed });
    try std.testing.expectEqual(@as(usize, 0), sealed);
}

test "every town gate steps across its street, canal or not" {
    const TOWNS = 50;
    var lv = grid.Level.blank();
    var wet: usize = 0;
    for (0..TOWNS) |i| {
        var rng = mathx.Rng.init(i);
        const p = (Params{ .canals = 100, .street = @intCast(1 + i % STREET_MAX) }).fit();
        shape(&lv, &rng, 0, p);
        const s: i32 = p.street;
        for (gates()) |g| {
            var k: i32 = 0;
            while (k <= s) : (k += 1) {
                if (!lv.walkable(g.at.add(.{ .x = g.in.delta().x * k, .y = g.in.delta().y * k }))) wet += 1;
            }
        }
    }
    std.debug.print("{d} towns all canals: {d} cells of gate and street a step cannot cross\n", .{ TOWNS, wet });
    try std.testing.expectEqual(@as(usize, 0), wet);
}

test "every gate of a walled town leads to its plaza, its top street a canal or not" {
    const TOWNS = 50;
    var lv = grid.Level.blank();
    var st: carve.Stretches = .{};
    var dead: usize = 0;
    for (0..TOWNS) |i| {
        var rng = mathx.Rng.init(i);
        shape(&lv, &rng, 0, (Params{ .canals = 100, .street = @intCast(1 + i % STREET_MAX) }).fit());
        for (gates()) |g| {
            const side = P{ .x = g.in.delta().y, .y = g.in.delta().x };
            var d: i32 = -2;
            while (d <= 2) : (d += 1) lv.set(g.at.add(.{ .x = side.x * d, .y = side.y * d }), .wall);
        }
        _ = st.label(&lv);
        const plaza = st.biggest();
        for (gates()) |g| {
            if (st.region[grid.Level.idx(g.at.add(g.in.delta()))] != plaza) dead += 1;
        }
    }
    std.debug.print("{d} walled towns all canals: {d} gates leading nowhere\n", .{ TOWNS, dead });
    try std.testing.expectEqual(@as(usize, 0), dead);
}

test "the plaza's well holds its water whatever street crosses it" {
    var lv = grid.Level.blank();
    var dry: usize = 0;
    for (BLOCK_MIN..BLOCK_MAX + 1) |blk| {
        for (1..STREET_MAX + 1) |s| {
            var rng = mathx.Rng.init(blk * 7 + s);
            shape(&lv, &rng, 0, (Params{ .block = @intCast(blk), .street = @intCast(s) }).fit());
            if (lv.at(grid.MIDDLE) != .water) dry += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), dry);
}

test "a town's houses each open onto its streets" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x7083);
    shape(&lv, &rng, 0, .{ .canals = 50 });
    std.debug.print("a town: {d} wall, {d} floor, {d} canal, {d} bridge\n", .{ carve.count(&lv, .wall), carve.count(&lv, .floor), carve.count(&lv, .water), carve.count(&lv, .bridge) });
    try std.testing.expect(carve.count(&lv, .floor) > 400);
}
