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
/// Of two chambers' radii summed, how far one may reach into the other.
const OVERLAP: f32 = 0.3;
const Chamber = struct { c: P, r: i32 };

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
    const noise = carve.Noise.init(seed, .cavern);
    const fray = mathx.fraction(p.fray);
    var chambers = grid.Bounded(Chamber, CHAMBERS_MAX){};
    var tries: usize = 0;
    while (chambers.n < p.chambers and tries < TRIES) : (tries += 1) {
        const r = rng.range(p.radius[0], p.radius[1]);
        const c = grid.Box.inMap(r + 1).roll(rng);
        const crowded = for (chambers.slice()) |o| {
            if (mathx.distEuclid(c, o.c) < @as(f32, @floatFromInt(r + o.r)) * (1 - OVERLAP)) break true;
        } else false;
        if (crowded) continue;
        chambers.push(.{ .c = c, .r = r });
        carve.blob(lv, noise, c, @floatFromInt(r), carve.CAVE_SCALE, 1, -fray, pal.open);
    }
    const all = chambers.slice();
    for (1..all.len) |i| {
        var best: usize = 0;
        for (1..i) |j| {
            if (mathx.distEuclid(all[i].c, all[j].c) < mathx.distEuclid(all[i].c, all[best].c)) best = j;
        }
        carve.trail(lv, rng, all[i].c, all[best].c, pal.path);
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
