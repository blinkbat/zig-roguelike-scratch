const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's caverns, Diablo II's Den of Evil, Dwarf Fortress's caverns; spires are DF's passage density.

pub const FILL_MAX: u8 = 70;
pub const SPIRES_MAX: u16 = 80;

pub const Params = struct {
    /// Percent of the ground sown with rock before it is smoothed.
    fill: u8 = 46,
    smooth: u8 = 5,
    /// Per thousand cells of open floor, a lone rock spire.
    spires: u16 = 6,

    pub fn fit(p: Params) Params {
        var q = p;
        q.fill = @min(p.fill, FILL_MAX);
        q.smooth = @min(p.smooth, carve.SMOOTH_MAX);
        q.spires = @min(p.spires, SPIRES_MAX);
        return q;
    }
};

pub fn palette(_: Params) carve.Palette {
    return carve.Palette.CAVE.pocketed();
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    carve.cellular(lv, rng, p.fill, p.smooth, p.spires, palette(p));
}
