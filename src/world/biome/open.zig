const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's plains square, Diablo II's Blood Moor before its fills.

pub const Params = struct {
    ground: carve.Ground = .grass,
    edge: carve.Solid = .shrub,
    litter: carve.Litter = .{},
    decor: carve.Decor = .{},

    pub fn fit(p: Params) Params {
        return p;
    }
};

pub fn palette(p: Params) carve.Palette {
    const g = p.ground.tile();
    return .{ .open = g, .solid = p.edge.tile(), .path = g };
}

pub fn shape(lv: *grid.Level, _: *mathx.Rng, _: u64, p: Params) void {
    carve.field(lv, palette(p));
}

fn dressed(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    shape(lv, rng, seed, p);
    carve.dress(p, lv, rng, seed);
}

test "a field strews lone boulders, open ground all round each" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x0B1D);
    dressed(&lv, &rng, 0, .{ .litter = .{ .boulders = carve.LITTER_MAX } });
    var boulders: usize = 0;
    for (lv.tile, 0..) |t, k| {
        if (t != .boulder) continue;
        boulders += 1;
        try std.testing.expect(carve.clearAround(&lv, grid.Level.of(k)));
    }
    std.debug.print("a field at {d} a thousand: {d} boulders\n", .{ carve.LITTER_MAX, boulders });
    try std.testing.expect(boulders > 100);
}

test "a field strews tiny shrubs, tall grass in patches and shrooms, and a step goes through each" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xDEC0);
    dressed(&lv, &rng, 0xDEC0, .{});
    var tall: usize = 0;
    var patched: usize = 0;
    var shrooms: usize = 0;
    var shrubs: usize = 0;
    for (lv.tile, 0..) |t, k| {
        if (t == .shrooms) shrooms += 1;
        if (t == .tiny_shrub) shrubs += 1;
        if (t != .tall_grass) continue;
        tall += 1;
        const p = grid.Level.of(k);
        for (mathx.CARDINALS) |d| {
            if (lv.at(p.add(d)) == .tall_grass) {
                patched += 1;
                break;
            }
        }
    }
    std.debug.print("a field's decor: {d} tiny shrubs, {d} tall grass, {d} of it beside more, {d} shrooms\n", .{ shrubs, tall, patched, shrooms });
    try std.testing.expect(shrubs > 10 and tall > 200 and patched * 10 > tall * 9 and shrooms > 10);
    for ([_]grid.Tile{ .tiny_shrub, .tall_grass, .shrooms }) |t| try std.testing.expect(!t.solid() and !t.blind());
}
