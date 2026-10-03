const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Dwarf Fortress's pools and cavern lakes, ADOM's ponds; filled with rock, Diablo II's Act 4 mesas.

const P = mathx.P;

pub const COUNT_MAX: u8 = 12;
pub const SIZE_MIN: u8 = 2;
pub const SIZE_MAX: u8 = 14;
/// Of a blob's disc, noise above this is fill.
const EDGE: f32 = 0.42;
const RING: f32 = 0.12;
/// An island's share of a blob's size.
const ISLAND_OF: f32 = 0.35;
const TRIES: usize = 80;

pub const Params = struct {
    fill: grid.Tile = .water,
    count: u8 = 3,
    /// The biggest one's half-width.
    size: u8 = 6,
    ring: carve.Bank = .shallows,
    /// Percent of them that keep an island at their heart.
    island: u8 = 0,

    pub fn fit(p: Params) Params {
        var q = p;
        q.count = std.math.clamp(p.count, 1, COUNT_MAX);
        q.size = std.math.clamp(p.size, SIZE_MIN, SIZE_MAX);
        q.island = @min(p.island, mathx.PERCENT);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, seed: u64, _: carve.Palette, p: Params) void {
    const noise = carve.Noise.init(seed ^ 0x1A4E);
    const most: i32 = p.size;
    for (0..p.count) |_| {
        const c = for (0..TRIES) |_| {
            const half = @divTrunc(most, 2);
            const q = grid.Box.inMap(half + 1).roll(rng);
            if (lv.walkable(q)) break q;
        } else continue;
        const r = rng.range(SIZE_MIN, most);
        const isle = rng.percent(p.island);
        const rf: f32 = @floatFromInt(r);
        var cells = grid.Cells.around(c, r + 1);
        while (cells.next()) |q| {
            if (grid.Level.onRim(q) or !lv.walkable(q)) continue;
            const d = mathx.distEuclid(q, c) / rf;
            if (isle and d < ISLAND_OF) continue;
            const v = noise.at(q, 4, 2) * (1.4 - d);
            if (v > EDGE) {
                lv.set(q, p.fill);
            } else if (v > EDGE - RING) {
                if (p.ring.tile()) |t| lv.set(q, t);
            }
        }
    }
}

test "lakes fill open ground, and an island stays dry" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x1A4E);
    carve.field(&lv, carve.Palette.WILD);
    const pal = carve.Palette.WILD;
    apply(&lv, &rng, 1, pal, .{ .count = 4, .size = 10, .island = 100 });
    std.debug.print("4 lakes with islands: {d} water, {d} shallows\n", .{ carve.count(&lv, .water), carve.count(&lv, .shallows) });
    try std.testing.expect(carve.count(&lv, .water) > 40);
}
