const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Dwarf Fortress's tower-caps, ADOM's lone trees; at a thousand a thousand, Qud's "but frozen" (grass to snow, water to ice).

pub const AMOUNT_MAX: u16 = mathx.MILLE;
pub const CLUMP_MAX: u8 = 32;
pub const RANGE_MAX: u8 = 12;

pub const Params = struct {
    tile: grid.Tile = .shrub,
    on: grid.Tile = .grass,
    /// Of the `on` cells, how many a thousand it takes.
    amount: u16 = 20,
    /// Clumps about this many cells across; 0 lays it a cell at a time, where it closes no way if it is solid.
    clump: u8 = 0,
    water_range: u8 = 0,
    /// Lays none within this many cells of water.
    water_clear: u8 = 0,
    /// Lays only within this many cells of dry ground other than `on`.
    land_range: u8 = 0,

    pub fn fit(p: Params) Params {
        var q = p;
        q.amount = @min(p.amount, AMOUNT_MAX);
        q.clump = @min(p.clump, CLUMP_MAX);
        inline for (carve.Over.RANGES) |f| @field(q, f) = @min(@field(p, f), RANGE_MAX);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, seed: u64, _: carve.Palette, p: Params) void {
    var on = carve.Over{ .tile = p.on, .decked = true };
    inline for (carve.Over.RANGES) |f| @field(on, f) = @field(p, f);
    if (p.clump == 0) {
        carve.scatter(lv, rng, p.amount, on, p.tile, p.tile.solid() and p.amount < AMOUNT_MAX);
        return;
    }
    carve.clumps(lv, carve.Noise.init(seed, .scatter), @floatFromInt(p.clump), p.amount, on, p.tile);
}

test "clumps take the share asked of the ground, and lone solids never touch" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x5CA7);
    carve.field(&lv, carve.Palette.WILD);
    const open = carve.count(&lv, .grass);
    const pal = carve.Palette.WILD;
    apply(&lv, &rng, 3, pal, .{ .tile = .reeds, .amount = 250, .clump = 8 });
    const reeds = carve.count(&lv, .reeds);
    std.debug.print("reeds in clumps at 250 a thousand: {d} of {d} grass, {d} a thousand\n", .{ reeds, open, reeds * 1000 / open });
    try std.testing.expect(reeds * 1000 / open > 200 and reeds * 1000 / open < 300);
    apply(&lv, &rng, 3, pal, .{ .tile = .snow, .on = .grass, .amount = AMOUNT_MAX });
    try std.testing.expectEqual(@as(usize, 0), carve.count(&lv, .grass));
}

test "water-limited scatter keeps single trees and clumps on dry nearby ground" {
    var checked: usize = 0;
    for ([_]u8{ 0, 5 }) |clump| {
        var lv = grid.Level.blank();
        var rng = mathx.Rng.init(0x5A4D);
        carve.fill(&lv, .dirt);
        apply(&lv, &rng, 7, carve.Palette.WILD, .{ .tile = .swamp_tree, .on = .dirt, .amount = 500, .clump = clump, .water_range = 3 });
        try std.testing.expectEqual(@as(usize, 0), carve.count(&lv, .swamp_tree));
        lv.set(.{ .x = 24, .y = 24 }, .water);
        lv.set(.{ .x = 60, .y = 40 }, .shallows);
        apply(&lv, &rng, 7, carve.Palette.WILD, .{ .tile = .swamp_tree, .on = .dirt, .amount = 500, .clump = clump, .water_range = 3 });
        const count = carve.count(&lv, .swamp_tree);
        try std.testing.expect(count > 0);
        for (lv.tile, 0..) |t, i| {
            if (t != .swamp_tree) continue;
            try std.testing.expect(carve.nearWater(&lv, grid.Level.of(i), 3));
            checked += 1;
        }
        try std.testing.expectEqual(grid.Tile.water, lv.at(.{ .x = 24, .y = 24 }));
        try std.testing.expectEqual(grid.Tile.shallows, lv.at(.{ .x = 60, .y = 40 }));
    }
    std.debug.print("waterside scatter: {d} trees/clump cells within 3 cells of water; dry maps and both water depths preserved\n", .{checked});
}

test "a scatter kept off water lays nothing that near it, and still lays further out" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x5A4F);
    carve.fill(&lv, .dirt);
    for (0..grid.H) |y| lv.set(.{ .x = 0, .y = @intCast(y) }, .water);
    apply(&lv, &rng, 7, carve.Palette.WILD, .{ .tile = .swamp_tree, .on = .dirt, .amount = 500, .water_range = 7, .water_clear = 4 });
    const span = columns(&lv, .swamp_tree);
    std.debug.print("trees kept 4 off water within 7 of it: {d} laid, columns {d} to {d}\n", .{ carve.count(&lv, .swamp_tree), span.nearest, span.farthest });
    try std.testing.expect(carve.count(&lv, .swamp_tree) > 0 and span.nearest == 5 and span.farthest == 7);
}

fn columns(lv: *const grid.Level, tile: grid.Tile) struct { nearest: i32, farthest: i32 } {
    var nearest: i32 = grid.W;
    var farthest: i32 = 0;
    for (lv.tile, 0..) |t, i| {
        if (t != tile) continue;
        const x = grid.Level.of(i).x;
        nearest = @min(nearest, x);
        farthest = @max(farthest, x);
    }
    return .{ .nearest = nearest, .farthest = farthest };
}

test "a scatter kept near land lays only along the edge of its ground away from water" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x5A50);
    carve.fill(&lv, .grass);
    for (0..grid.H) |y| {
        for (0..12) |x| lv.set(.{ .x = @intCast(x), .y = @intCast(y) }, if (x == 0) .water else .dirt);
    }
    apply(&lv, &rng, 7, carve.Palette.WILD, .{ .tile = .swamp_tree, .on = .dirt, .amount = 500, .water_clear = 4, .land_range = 2 });
    const span = columns(&lv, .swamp_tree);
    std.debug.print("trees on a beach from column 1 to 11, kept 4 off water and 2 from land: columns {d} to {d}\n", .{ span.nearest, span.farthest });
    try std.testing.expect(carve.count(&lv, .swamp_tree) > 0 and span.nearest >= 10 and span.farthest <= 11);
}

test "scattered water reaches only from the water there before it, not from what it lays" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x5A4E);
    carve.fill(&lv, .dirt);
    const pool = mathx.P{ .x = 24, .y = 24 };
    lv.set(pool, .water);
    apply(&lv, &rng, 7, carve.Palette.WILD, .{ .tile = .shallows, .on = .dirt, .amount = AMOUNT_MAX, .water_range = 1 });
    var far: usize = 0;
    for (lv.tile, 0..) |t, i| {
        if (t == .shallows and mathx.dist(grid.Level.of(i), pool) > 1) far += 1;
    }
    std.debug.print("water scatter at range 1: {d} shallows, {d} beyond the pool's ring\n", .{ carve.count(&lv, .shallows), far });
    try std.testing.expectEqual(@as(usize, 8), carve.count(&lv, .shallows));
    try std.testing.expectEqual(@as(usize, 0), far);
}
