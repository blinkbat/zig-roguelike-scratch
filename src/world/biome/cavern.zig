const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's cavernous levels: large circular rooms joined by short corridors, each to the nearest before it.

const P = mathx.P;

pub const CHAMBERS_MAX: u8 = 40;
pub const RADIUS_MIN: u8 = 2;
pub const RADIUS_MAX: u8 = 14;
pub const FRAY_MAX: u8 = mathx.PERCENT;
const TRIES: usize = 400;
/// Of a chamber's radius, how far one may reach into another.
const OVERLAP: f32 = 0.3;

pub const Params = struct {
    chambers: u8 = 18,
    radius: [2]u8 = .{ 3, 8 },
    /// Percent of a chamber's edge frayed by noise.
    fray: u8 = 40,

    pub fn fit(p: Params) Params {
        return .{ .chambers = std.math.clamp(p.chambers, 1, CHAMBERS_MAX), .radius = mathx.span(u8, p.radius, RADIUS_MIN, RADIUS_MAX), .fray = @min(p.fray, FRAY_MAX) };
    }
};

pub fn palette(_: Params) carve.Palette {
    return carve.Palette.CAVE;
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    carve.fill(lv, .rock);
    const noise = carve.Noise.init(seed ^ 0xCA4E);
    const fray = @as(f32, @floatFromInt(p.fray)) / mathx.PERCENT;
    var centre: [CHAMBERS_MAX]P = undefined;
    var radius: [CHAMBERS_MAX]i32 = undefined;
    var n: usize = 0;
    var tries: usize = 0;
    while (n < p.chambers and tries < TRIES) : (tries += 1) {
        const r = rng.range(p.radius[0], p.radius[1]);
        const c = P{ .x = rng.range(r + 1, grid.W - 2 - r), .y = rng.range(r + 1, grid.H - 2 - r) };
        const crowded = for (centre[0..n], radius[0..n]) |o, ro| {
            if (mathx.distEuclid(c, o) < @as(f32, @floatFromInt(r + ro)) * (1 - OVERLAP)) break true;
        } else false;
        if (crowded) continue;
        centre[n] = c;
        radius[n] = r;
        n += 1;
        const rf: f32 = @floatFromInt(r);
        var cells = grid.Cells.around(c, r);
        while (cells.next()) |q| {
            if (grid.Level.onRim(q)) continue;
            const d = mathx.distEuclid(q, c) / rf;
            if (d <= 1 - fray * noise.at(q, 3, 2)) lv.set(q, .dirt);
        }
    }
    for (1..n) |i| {
        var best: usize = 0;
        for (1..i) |j| {
            if (mathx.distEuclid(centre[i], centre[j]) < mathx.distEuclid(centre[i], centre[best])) best = j;
        }
        carve.trail(lv, rng, centre[i], centre[best], .dirt);
    }
}

test "chambers are round and joined" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xCA4E);
    shape(&lv, &rng, 1, .{});
    var region: [grid.CELLS]u16 = undefined;
    var size: [grid.CELLS]u32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const parts = carve.label(&lv, &region, &size, &queue);
    std.debug.print("a cavern: {d} open cells in {d} stretch\n", .{ carve.count(&lv, .dirt), parts });
    try std.testing.expectEqual(@as(usize, 1), parts);
}
