const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's forest square, Qud's jungle, Diablo II's Dark Wood.

pub const THICKET_MAX: u8 = 75;
pub const SMOOTH_MAX: u8 = 8;
pub const STRAYS_MAX: u16 = 100;

pub const Params = struct {
    /// Percent of the ground sown with shrub before it is smoothed.
    thicket: u8 = 42,
    /// Smoothing passes; more, rounder thickets and wider glades.
    smooth: u8 = 4,
    /// Per thousand cells of open grass, a lone shrub.
    strays: u16 = 20,
    litter: carve.Litter = .{},
    decor: carve.Decor = .{},

    pub fn fit(p: Params) Params {
        var q = p;
        q.thicket = @min(p.thicket, THICKET_MAX);
        q.smooth = @min(p.smooth, SMOOTH_MAX);
        q.strays = @min(p.strays, STRAYS_MAX);
        q.litter = p.litter.fit();
        q.decor = p.decor.fit();
        return q;
    }
};

pub fn palette(_: Params) carve.Palette {
    var pal = carve.Palette.WILD;
    pal.pocket = pal.solid;
    return pal;
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    const pal = palette(p);
    carve.sow(lv, rng, p.thicket, pal.solid, pal.open);
    carve.smooth(lv, p.smooth, pal.solid, pal.open);
    carve.scatter(lv, rng, p.strays, pal.open, pal.solid, true);
    p.litter.strew(lv, rng);
    p.decor.strew(lv, rng, seed);
}

test "lone shrubs stand in the open, none touching another shrub" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x51A7);
    shape(&lv, &rng, 0, .{ .thicket = 0, .strays = STRAYS_MAX });
    var lone: usize = 0;
    for (0..grid.CELLS) |k| {
        const p = grid.Level.of(k);
        if (grid.Level.onRim(p) or lv.tile[k] != .shrub) continue;
        var touching: usize = 0;
        for (mathx.ALL_DIRS) |d| {
            const q = p.add(d.delta());
            if (!grid.Level.onRim(q) and lv.at(q).solid()) touching += 1;
        }
        if (touching == 0) lone += 1;
    }
    std.debug.print("an open wilds at {d} strays a thousand: {d} lone shrubs\n", .{ STRAYS_MAX, lone });
    try std.testing.expect(lone > 100);
}
