const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Path of Exile's outer buffer, Diablo II's border blocks.

pub const WIDTH_MAX: u8 = 12;
pub const ROUGH_MAX: u8 = 12;

pub const Params = struct {
    tile: grid.Tile = .rock,
    width: u8 = 3,
    /// Cells it frays inward by, at most.
    rough: u8 = 3,

    pub fn fit(p: Params) Params {
        var q = p;
        q.width = std.math.clamp(p.width, 1, WIDTH_MAX);
        q.rough = @min(p.rough, ROUGH_MAX);
        return q;
    }
};

pub fn apply(lv: *grid.Level, _: *mathx.Rng, seed: u64, _: carve.Palette, p: Params) void {
    const noise = carve.Noise.init(seed, .border);
    for (0..grid.CELLS) |i| {
        const q = grid.Level.of(i);
        const in = grid.Level.edgeDist(q);
        const reach = @as(f32, @floatFromInt(p.width)) + noise.at(q, 6, 2) * @as(f32, @floatFromInt(p.rough));
        if (@as(f32, @floatFromInt(in)) + 0.5 < reach) lv.tile[i] = p.tile;
    }
}

test "a border's every rough frays: rough 1 is not a solid row deeper" {
    var same: usize = 0;
    var frayed: usize = 0;
    var rng = mathx.Rng.init(1);
    for (0..50) |s| {
        var a = grid.Level.blank();
        var b = grid.Level.blank();
        carve.fill(&a, .grass);
        carve.fill(&b, .grass);
        apply(&a, &rng, s, carve.Palette.WILD, .{ .width = 3, .rough = 1 });
        apply(&b, &rng, s, carve.Palette.WILD, .{ .width = 4, .rough = 0 });
        if (std.mem.eql(grid.Tile, &a.tile, &b.tile)) same += 1;
        frayed += carve.count(&b, .rock) - carve.count(&a, .rock);
    }
    std.debug.print("border width 3 rough 1 against width 4 rough 0, 50 seeds: {d} identical, {d} cells frayed open\n", .{ same, frayed });
    try std.testing.expectEqual(@as(usize, 0), same);
}

test "a border is at least its width deep everywhere" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(1);
    carve.fill(&lv, .grass);
    apply(&lv, &rng, 9, carve.Palette.WILD, .{ .tile = .water, .width = 4, .rough = 6 });
    for (0..grid.CELLS) |i| {
        if (grid.Level.edgeDist(grid.Level.of(i)) < 4) try std.testing.expectEqual(grid.Tile.water, lv.tile[i]);
    }
    std.debug.print("a water border 4 deep, frayed by 6: {d} of {d} cells\n", .{ carve.count(&lv, .water), grid.CELLS });
}
