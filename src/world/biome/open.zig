const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's plains square, Diablo II's Blood Moor before its fills.

pub const Params = struct {
    ground: carve.Ground = .grass,
    edge: carve.Solid = .shrub,
    litter: carve.Litter = .{},

    pub fn fit(p: Params) Params {
        var q = p;
        q.litter = p.litter.fit();
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    const g = p.ground.tile();
    return .{ .open = g, .solid = p.edge.tile(), .path = g };
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    carve.fill(lv, p.ground.tile());
    carve.rim(lv, p.edge.tile());
    p.litter.strew(lv, rng);
}

test "a field strews lone tiny shrubs and boulders, open ground all round each" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x0B1D);
    const most = carve.Litter{ .tiny_shrubs = carve.LITTER_MAX, .boulders = carve.LITTER_MAX };
    shape(&lv, &rng, 0, .{ .litter = most });
    var shrubs: usize = 0;
    var boulders: usize = 0;
    for (lv.tile, 0..) |t, k| {
        if (t != .tiny_shrub and t != .boulder) continue;
        if (t == .tiny_shrub) shrubs += 1 else boulders += 1;
        try std.testing.expect(carve.clearAround(&lv, grid.Level.of(k)));
    }
    std.debug.print("a field at {d} a thousand of each: {d} tiny shrubs, {d} boulders\n", .{ carve.LITTER_MAX, shrubs, boulders });
    try std.testing.expect(shrubs > 200 and boulders > 100);
}
