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
    var y = lo.y + s;
    while (y + p.block <= hi.y - s) : (y += step) {
        var x = lo.x + s;
        while (x + p.block <= hi.x - s) : (x += step) {
            const b = buildings.Box{ .lo = .{ .x = x, .y = y }, .hi = .{ .x = x + p.block, .y = y + p.block } };
            block(lv, rng, b, p, street);
        }
        if (carve.percent(rng, p.canals)) {
            carve.box(lv, .{ .x = lo.x, .y = y - s }, .{ .x = hi.x, .y = y }, .water);
        }
    }
    const plaza = grid.MIDDLE;
    carve.disc(lv, plaza, @as(f32, @floatFromInt(p.block)) * 0.55, street, null);
    setpiece.stamp(lv, plaza.sub(.{ .x = 2, .y = 2 }), setpiece.rows(.well));
    var x = lo.x;
    while (x < hi.x) : (x += step) {
        var yy = lo.y;
        while (yy < hi.y) : (yy += 1) {
            var k: i32 = 0;
            while (k < s) : (k += 1) {
                const q = P{ .x = x + k, .y = yy };
                if (lv.at(q) == .water) lv.set(q, .bridge);
            }
        }
    }
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

/// Cut into lots by alleys; each lot built on, a house walled round with a doorway onto a street, or left a yard.
fn block(lv: *grid.Level, rng: *mathx.Rng, b: buildings.Box, p: Params, street: grid.Tile) void {
    const w = b.hi.x - b.lo.x;
    const h = b.hi.y - b.lo.y;
    const split_x = w >= 2 * HOUSE_LEAST + 1 and rng.chance(0.7);
    const split_y = h >= 2 * HOUSE_LEAST + 1 and rng.chance(0.7);
    const mx = if (split_x) rng.range(b.lo.x + HOUSE_LEAST, b.hi.x - HOUSE_LEAST - 1) else b.hi.x;
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

test "a town's houses each open onto its streets" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x7083);
    shape(&lv, &rng, 0, .{ .canals = 50 });
    std.debug.print("a town: {d} wall, {d} floor, {d} canal, {d} bridge\n", .{ carve.count(&lv, .wall), carve.count(&lv, .floor), carve.count(&lv, .water), carve.count(&lv, .bridge) });
    try std.testing.expect(carve.count(&lv, .floor) > 400);
}
