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
        var q = p;
        q.fill = @min(p.fill, FILL_MAX);
        q.smooth = @min(p.smooth, SMOOTH_MAX);
        q.spires = @min(p.spires, SPIRES_MAX);
        return q;
    }
};

pub fn palette(_: Params) carve.Palette {
    var pal = carve.Palette.CAVE;
    pal.pocket = pal.solid;
    return pal;
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    const pal = palette(p);
    carve.sow(lv, rng, p.fill, pal.solid, pal.open);
    carve.smooth(lv, p.smooth, pal.solid, pal.open);
    carve.scatter(lv, rng, p.spires, pal.open, pal.solid, true);
}
