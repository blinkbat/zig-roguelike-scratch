const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's Big Room and Animated Forest, the Caverns of Chaos graveyard, a pillared hall.

pub const MARGIN_MAX: u8 = 16;
const PILLAR_STEP: i32 = 4;
const ALCOVE_W: i32 = 3;
const ALCOVE_D: i32 = 3;
/// The Animated Forest's plant share, and the rows left clear below it, of the hall's height.
const GROVE_FILL: u32 = 50;
const GROVE_CLEAR_OF: i32 = 3;

pub const Style = enum { bare, pillars, graves, grove };

pub const Params = struct {
    style: Style = .bare,
    /// Cells of wall between the hall and the map's edge.
    margin: u8 = 4,

    pub fn fit(p: Params) Params {
        var q = p;
        q.margin = std.math.clamp(p.margin, 1, MARGIN_MAX);
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    var pal = carve.Palette.BUILT;
    pal.pocket = if (p.style == .grove) .shrub else null;
    return pal;
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    const pal = palette(p);
    carve.fill(lv, pal.solid);
    const m: i32 = p.margin;
    const lo = mathx.P{ .x = m, .y = m };
    const hi = mathx.P{ .x = grid.W - m, .y = grid.H - m };
    carve.box(lv, lo, hi, pal.open);
    switch (p.style) {
        .bare => {},
        .pillars => {
            var y = lo.y + 2;
            while (y < hi.y - 2) : (y += PILLAR_STEP) {
                var x = lo.x + 2;
                while (x < hi.x - 2) : (x += PILLAR_STEP) lv.set(.{ .x = x, .y = y }, .wall);
            }
        },
        .graves => {
            var x = lo.x + 1;
            while (x + ALCOVE_W < hi.x) : (x += ALCOVE_W + 1) {
                for ([_]i32{ lo.y, hi.y - ALCOVE_D }) |top| {
                    carve.box(lv, .{ .x = x - 1, .y = top }, .{ .x = x + ALCOVE_W, .y = top + ALCOVE_D }, .wall);
                    carve.box(lv, .{ .x = x, .y = top }, .{ .x = x + ALCOVE_W - 1, .y = top + ALCOVE_D }, .floor);
                    lv.set(.{ .x = x + 1, .y = if (top == lo.y) top else top + ALCOVE_D - 1 }, .grave);
                }
            }
        },
        .grove => {
            var cells = grid.Cells.of(lo, .{ .x = hi.x, .y = hi.y - @divTrunc(hi.y - lo.y, GROVE_CLEAR_OF) });
            while (cells.next()) |q| {
                if (rng.percent(GROVE_FILL)) lv.set(q, .shrub);
            }
        },
    }
}
