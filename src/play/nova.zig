const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const glacial = @import("glacial.zig");

const P = mathx.P;

pub const COST: i32 = 6;
pub const COOLDOWN: u8 = 3;
pub const RANGE: i32 = 2;
pub const OPEN_CELLS: usize = @intCast(grid.Cells.square(RANGE) - 1);
pub const VERB = "freezes";
pub const DONE = "casts a frost nova";
pub const TAKES = glacial.TAKES;
pub const ELEMENT: damage.Element = .cold;
pub const DESCRIPTION = std.fmt.comptimePrint("A cold blast hits every foe within {d} tiles. {s}.", .{ RANGE, glacial.CHILL_NOTE });

comptime {
    std.debug.assert(RANGE <= glacial.BURST_MAX);
}

pub const BASE = damage.Base{ .lo = 3, .hi = 5 };

pub const CHANCE = glacial.CHANCE;
pub const procs = glacial.procs;
pub const chance = glacial.chance;
pub const afflict = glacial.afflict;
pub const AILMENT = glacial.AILMENT;

/// Every cell within `RANGE` of `from` the burst reaches past the terrain, `from` aside.
pub fn around(lv: *const grid.Level, from: P) glacial.Burst {
    return glacial.spread(lv, from, RANGE, from, notAt);
}

fn notAt(from: P, p: P) bool {
    return !p.eq(from);
}

test "a frost nova reaches every open cell within two tiles but the caster's, and stops at a wall" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    var area = around(&lv, from);
    try std.testing.expectEqual(OPEN_CELLS, area.n);
    try std.testing.expect(!area.has(from));
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    area = around(&lv, from);
    try std.testing.expect(!area.has(.{ .x = 21, .y = 20 }));
    try std.testing.expect(!area.has(.{ .x = 22, .y = 20 }));
    try std.testing.expect(area.has(.{ .x = 22, .y = 22 }));
    std.debug.print("frost nova: {d} cells round the caster on open ground, a wall shading the cell behind it\n", .{OPEN_CELLS});
}
