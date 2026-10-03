const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's caverns, Diablo II's Den of Evil, Dwarf Fortress's caverns; spires are DF's passage density.

pub const FILL_MAX: u8 = 70;
pub const SMOOTH_MAX: u8 = 8;
pub const SPIRES_MAX: u16 = 80;

pub const Params = struct {
    /// Percent of the ground sown with rock before it is smoothed.
    fill: u8 = 46,
    smooth: u8 = 5,
    /// Per thousand cells of open floor, a lone rock spire.
    spires: u16 = 6,

    pub fn fit(p: Params) Params {
        return .{ .fill = @min(p.fill, FILL_MAX), .smooth = @min(p.smooth, SMOOTH_MAX), .spires = @min(p.spires, SPIRES_MAX) };
    }
};

pub fn palette(_: Params) carve.Palette {
    var pal = carve.Palette.CAVE;
    pal.pocket = .rock;
    return pal;
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    carve.sow(lv, rng, p.fill, .rock, .dirt);
    carve.smooth(lv, p.smooth, .rock, .dirt);
    carve.scatter(lv, rng, p.spires, .dirt, .rock, true);
}
