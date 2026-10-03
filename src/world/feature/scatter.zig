const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Dwarf Fortress's tower-caps, ADOM's lone trees; at a thousand a thousand, Qud's "but frozen" (grass to snow, water to ice).

pub const AMOUNT_MAX: u16 = mathx.MILLE;
pub const CLUMP_MAX: u8 = 32;

pub const Params = struct {
    tile: grid.Tile = .shrub,
    on: grid.Tile = .grass,
    /// Of the `on` cells, how many a thousand it takes.
    amount: u16 = 20,
    /// Clumps about this many cells across; 0 lays it a cell at a time, where it closes no way if it is solid.
    clump: u8 = 0,

    pub fn fit(p: Params) Params {
        var q = p;
        q.amount = @min(p.amount, AMOUNT_MAX);
        q.clump = @min(p.clump, CLUMP_MAX);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, seed: u64, _: carve.Palette, p: Params) void {
    const on = carve.Over{ .tile = p.on, .decked = true };
    if (p.clump == 0) {
        carve.scatter(lv, rng, p.amount, on, p.tile, p.tile.solid() and p.amount < AMOUNT_MAX);
        return;
    }
    carve.clumps(lv, carve.Noise.init(seed ^ 0x5CA7), @floatFromInt(p.clump), p.amount, on, p.tile);
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
