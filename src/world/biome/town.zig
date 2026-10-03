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
/// A house on a lot: whole, a barrel at most, a torch in three.
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
    const street = p.ground.tile();
    carve.fill(lv, p.outside.tile());
    carve.rim(lv, .shrub);
    const lo = P{ .x = MARGIN, .y = MARGIN };
    const hi = P{ .x = grid.W - MARGIN, .y = grid.H - MARGIN };
    carve.box(lv, lo, hi, street);
    const step: i32 = @as(i32, p.block) + p.street;
    const s: i32 = p.street;
    const top = lo.y + s;
    var y = top;
    while (y + p.block <= hi.y - s) : (y += step) {
        if (carve.percent(rng, p.canals)) {
            carve.box(lv, .{ .x = lo.x, .y = y - s }, .{ .x = hi.x, .y = y }, .water);
        }
    }
    y = top;
    while (y + p.block <= hi.y - s) : (y += step) {
        var x = lo.x + s;
        while (x + p.block <= hi.x - s) : (x += step) {
            const b = buildings.Box{ .lo = .{ .x = x, .y = y }, .hi = .{ .x = x + p.block, .y = y + p.block } };
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
    {
        const wl = lo.sub(.{ .x = 1, .y = 1 });
        const wh = hi.add(.{ .x = 1, .y = 1 });
        const walled = buildings.Box{ .lo = wl, .hi = wh };
        var cells = grid.Cells.of(wl, wh);
        while (cells.next()) |q| {
            if (walled.onEdge(q)) lv.set(q, ring);
        }
        for ([_]P{ .{ .x = grid.MIDDLE.x, .y = wl.y }, .{ .x = grid.MIDDLE.x, .y = wh.y - 1 }, .{ .x = wl.x, .y = grid.MIDDLE.y }, .{ .x = wh.x - 1, .y = grid.MIDDLE.y } }) |g| {
            carve.disc(lv, g, 1.5, street, null);
        }
    }
}

/// Every canal cell from `lo` up to `hi` bridged.
fn bridge(lv: *grid.Level, lo: P, hi: P) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |q| {
        if (lv.at(q).liquid()) lv.set(q, .bridge);
    }
}

/// Cut into lots by alleys; each lot built on, a house walled round with a doorway onto a street, or left a yard. An
/// alley from top to bottom with a canal at both ends gets one across, to the streets either side.
fn block(lv: *grid.Level, rng: *mathx.Rng, b: buildings.Box, p: Params, street: grid.Tile) void {
    const w = b.hi.x - b.lo.x;
    const h = b.hi.y - b.lo.y;
    const split_x = w >= 2 * HOUSE_LEAST + 1 and rng.chance(SPLIT_CHANCE);
    const crosses = h >= 2 * HOUSE_LEAST + 1;
    var split_y = crosses and rng.chance(SPLIT_CHANCE);
    const mx = if (split_x) rng.range(b.lo.x + HOUSE_LEAST, b.hi.x - HOUSE_LEAST - 1) else b.hi.x;
    if (split_x and crosses and lv.at(.{ .x = mx, .y = b.lo.y - 1 }).liquid() and lv.at(.{ .x = mx, .y = b.hi.y }).liquid()) split_y = true;
    const my = if (split_y) rng.range(b.lo.y + HOUSE_LEAST, b.hi.y - HOUSE_LEAST - 1) else b.hi.y;
    const lots = [_]buildings.Box{
        .{ .lo = b.lo, .hi = .{ .x = mx, .y = my } },
        .{ .lo = .{ .x = mx + 1, .y = b.lo.y }, .hi = .{ .x = b.hi.x, .y = my } },
        .{ .lo = .{ .x = b.lo.x, .y = my + 1 }, .hi = .{ .x = mx, .y = b.hi.y } },
        .{ .lo = .{ .x = mx + 1, .y = my + 1 }, .hi = b.hi },
    };
    for (lots) |lot| {
        if (lot.hi.x - lot.lo.x < HOUSE_LEAST or lot.hi.y - lot.lo.y < HOUSE_LEAST) continue;
        if (!carve.percent(rng, p.houses)) {
            carve.box(lv, lot.lo, lot.hi, .grass);
            continue;
        }
        buildings.raise(lv, rng, lot, HOUSE, street);
    }
}

test "no house's doorway opens on a canal" {
    const TOWNS = 100;
    var lv = grid.Level.blank();
    var region: [grid.CELLS]u16 = undefined;
    var size: [grid.CELLS]u32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var sealed: usize = 0;
    for (0..TOWNS) |i| {
        var rng = mathx.Rng.init(i);
        shape(&lv, &rng, 0, .{ .canals = 100, .street = 3 });
        const most = carve.biggest(size[0..carve.label(&lv, &region, &size, &queue)]);
        for (lv.tile, region) |t, r| {
            if (t == .floor and r != most) sealed += 1;
        }
    }
    std.debug.print("{d} towns all canals: {d} house floor cells shut off from the streets\n", .{ TOWNS, sealed });
    try std.testing.expectEqual(@as(usize, 0), sealed);
}

test "a town's houses each open onto its streets" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x7083);
    shape(&lv, &rng, 0, .{ .canals = 50 });
    std.debug.print("a town: {d} wall, {d} floor, {d} canal, {d} bridge\n", .{ carve.count(&lv, .wall), carve.count(&lv, .floor), carve.count(&lv, .water), carve.count(&lv, .bridge) });
    try std.testing.expect(carve.count(&lv, .floor) > 400);
}
