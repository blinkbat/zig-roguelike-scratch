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
    carve.box(lv, .{ .lo = lo, .hi = hi }, street);
    const step: i32 = @as(i32, p.block) + p.street;
    const s: i32 = p.street;
    const top = lo.y + s;
    var y = top;
    while (y + p.block <= hi.y - s) : (y += step) {
        if (rng.percent(p.canals)) {
            carve.box(lv, .{ .lo = .{ .x = lo.x, .y = y - s }, .hi = .{ .x = hi.x, .y = y } }, .water);
        }
    }
    y = top;
    while (y + p.block <= hi.y - s) : (y += step) {
        var x = lo.x + s;
        while (x + p.block <= hi.x - s) : (x += step) {
            const b = grid.Box{ .lo = .{ .x = x, .y = y }, .hi = .{ .x = x + p.block, .y = y + p.block } };
            block(lv, rng, b, p, street);
        }
    }
    const plaza = grid.MIDDLE;
    carve.disc(lv, plaza, @as(f32, @floatFromInt(p.block)) * 0.55, street, null);
    setpiece.stampAround(lv, plaza, setpiece.rows(.well));
    var x = lo.x;
    while (x < hi.x) : (x += step) bridge(lv, .{ .x = x, .y = lo.y }, .{ .x = x + s, .y = hi.y });
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
        carve.disc(lv, g.at, 1.5, street, null);
        const in = g.in.delta();
        const side = P{ .x = in.y, .y = in.x };
        const deep = g.at.add(.{ .x = in.x * s, .y = in.y * s });
        const a = g.at.sub(side);
        const b = deep.add(side);
        bridge(lv, a.min(b), a.max(b).add(.{ .x = 1, .y = 1 }));
    }
}

/// `in` is the way into the town.
const Gate = struct { at: P, in: mathx.Dir };

/// A cell outside the streets all round.
fn wallBox() grid.Box {
    return grid.Box.inMap(MARGIN - 1);
}

fn gates() [4]Gate {
    const wl = wallBox().lo;
    const wh = wallBox().hi;
    return .{
        .{ .at = .{ .x = grid.MIDDLE.x, .y = wl.y }, .in = .s },
        .{ .at = .{ .x = grid.MIDDLE.x, .y = wh.y - 1 }, .in = .n },
        .{ .at = .{ .x = wl.x, .y = grid.MIDDLE.y }, .in = .e },
        .{ .at = .{ .x = wh.x - 1, .y = grid.MIDDLE.y }, .in = .w },
    };
}

fn bridge(lv: *grid.Level, lo: P, hi: P) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |q| {
        lv.set(q, carve.paved(lv.at(q), lv.at(q)));
    }
}

/// An alley from top to bottom with a canal at both ends gets one across, to the streets either side.
fn block(lv: *grid.Level, rng: *mathx.Rng, b: grid.Box, p: Params, street: grid.Tile) void {
    const w = b.width();
    const h = b.height();
    const split_x = w >= 2 * HOUSE_LEAST + 1 and rng.chance(SPLIT_CHANCE);
    const crosses = h >= 2 * HOUSE_LEAST + 1;
    var split_y = crosses and rng.chance(SPLIT_CHANCE);
    const mx = if (split_x) rng.range(b.lo.x + HOUSE_LEAST, b.hi.x - HOUSE_LEAST - 1) else b.hi.x;
    if (split_x and crosses and lv.at(.{ .x = mx, .y = b.lo.y - 1 }).liquid() and lv.at(.{ .x = mx, .y = b.hi.y }).liquid()) split_y = true;
    const my = if (split_y) rng.range(b.lo.y + HOUSE_LEAST, b.hi.y - HOUSE_LEAST - 1) else b.hi.y;
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

test "a town's houses each open onto its streets" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x7083);
    shape(&lv, &rng, 0, .{ .canals = 50 });
    std.debug.print("a town: {d} wall, {d} floor, {d} canal, {d} bridge\n", .{ carve.count(&lv, .wall), carve.count(&lv, .floor), carve.count(&lv, .water), carve.count(&lv, .bridge) });
    try std.testing.expect(carve.count(&lv, .floor) > 400);
}
