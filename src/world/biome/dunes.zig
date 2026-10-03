const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Qud's salt dunes and Diablo II's Rocky Waste.

pub const RIDGES_MAX: u8 = 30;
pub const MESAS_MAX: u8 = 30;
pub const SCALE_MIN: u8 = 6;
pub const SCALE_MAX: u8 = 48;

pub const Params = struct {
    ground: carve.Ground = .sand,
    /// Hundredths of the noise either side of a crest that stand as ridge.
    ridges: u8 = 6,
    /// Crest noise over 1 less 2.5 times this percent stands as mesa.
    mesas: u8 = 4,
    scale: u8 = 18,

    pub fn fit(p: Params) Params {
        var q = p;
        q.ridges = @min(p.ridges, RIDGES_MAX);
        q.mesas = @min(p.mesas, MESAS_MAX);
        q.scale = std.math.clamp(p.scale, SCALE_MIN, SCALE_MAX);
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    const g = p.ground.tile();
    return .{ .open = g, .solid = .rock, .path = g };
}

pub fn shape(lv: *grid.Level, _: *mathx.Rng, seed: u64, p: Params) void {
    const pal = palette(p);
    const crest = carve.Noise.init(seed ^ 0xD0E5);
    const broken = carve.Noise.init(seed ^ 0xB20C);
    const s: f32 = @floatFromInt(p.scale);
    const band = mathx.fraction(p.ridges);
    const high = 1 - mathx.fraction(p.mesas) * 2.5;
    for (0..grid.CELLS) |i| {
        const q = grid.Level.of(i);
        const v = crest.at(q, s, 3);
        const ridge = @abs(v - 0.5) < band and broken.at(q, s / 2, 2) > 0.45;
        const mesa = v > high;
        lv.tile[i] = if (ridge or mesa) pal.solid else pal.open;
    }
    carve.rim(lv, pal.solid);
}
