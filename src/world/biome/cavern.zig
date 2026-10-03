const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's cavernous levels: large circular rooms joined by short corridors, each to the nearest before it.

const P = mathx.P;

pub const CHAMBERS_MAX: u8 = 40;
pub const RADIUS_MIN: u8 = 2;
pub const RADIUS_MAX: u8 = 14;
const TRIES: usize = 400;
/// Of a chamber's radius, how far one may reach into another.
const OVERLAP: f32 = 0.3;

pub const Params = struct {
    chambers: u8 = 18,
    radius: [2]u8 = .{ 3, 8 },
    /// Percent of a chamber's edge frayed by noise.
    fray: u8 = 40,

    pub fn fit(p: Params) Params {
        var q = p;
        q.chambers = std.math.clamp(p.chambers, 1, CHAMBERS_MAX);
        q.radius = mathx.span(u8, p.radius, RADIUS_MIN, RADIUS_MAX);
        q.fray = @min(p.fray, mathx.PERCENT);
        return q;
    }
};

pub fn palette(_: Params) carve.Palette {
    return carve.Palette.CAVE;
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    const pal = palette(p);
    carve.fill(lv, pal.solid);
    const noise = carve.Noise.init(seed ^ 0xCA4E);
    const fray = @as(f32, @floatFromInt(p.fray)) / mathx.PERCENT;
    var centre: [CHAMBERS_MAX]P = undefined;
    var radius: [CHAMBERS_MAX]i32 = undefined;
    var n: usize = 0;
    var tries: usize = 0;
    while (n < p.chambers and tries < TRIES) : (tries += 1) {
        const r = rng.range(p.radius[0], p.radius[1]);
        const c = grid.Box.inMap(r + 1).roll(rng);
        const crowded = for (centre[0..n], radius[0..n]) |o, ro| {
            if (mathx.distEuclid(c, o) < @as(f32, @floatFromInt(r + ro)) * (1 - OVERLAP)) break true;
        } else false;
        if (crowded) continue;
        centre[n] = c;
        radius[n] = r;
        n += 1;
        carve.blob(lv, noise, c, @floatFromInt(r), 3, 1, -fray, pal.open);
    }
    for (1..n) |i| {
        var best: usize = 0;
        for (1..i) |j| {
            if (mathx.distEuclid(centre[i], centre[j]) < mathx.distEuclid(centre[i], centre[best])) best = j;
        }
        carve.trail(lv, rng, centre[i], centre[best], pal.path);
    }
}

test "chambers are round and joined" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xCA4E);
    shape(&lv, &rng, 1, .{});
    var st: carve.Stretches = .{};
    const parts = st.label(&lv);
    std.debug.print("a cavern: {d} open cells in {d} stretch\n", .{ carve.count(&lv, .dirt), parts });
    try std.testing.expectEqual(@as(usize, 1), parts);
}
