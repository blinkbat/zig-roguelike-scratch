const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const damage = @import("damage.zig");
const glacial = @import("glacial.zig");

const P = mathx.P;

pub const COST: i32 = 30;
pub const COOLDOWN: u8 = 3;
pub const RANGE: i32 = 2;
pub const OPEN_CELLS: usize = @intCast(grid.Cells.span(RANGE) * grid.Cells.span(RANGE) - 1);
pub const COLD_LO: i32 = 3;
pub const COLD_HI: i32 = 5;
pub const VERB = "freezes";
pub const TAKES = glacial.TAKES;
pub const ELEMENT: damage.Element = .cold;
pub const DESCRIPTION = std.fmt.comptimePrint("{d}-{d} cold to every foe within {d} tiles. {d}% chill (cold resistance lowers chance). {d} mana, {d}-turn cooldown.", .{ COLD_LO, COLD_HI, RANGE, glacial.CHANCE, COST, COOLDOWN });

comptime {
    std.debug.assert(RANGE <= glacial.RANGE);
}

pub fn roll(rng: *mathx.Rng) i32 {
    return rng.range(COLD_LO, COLD_HI);
}

pub const procs = glacial.procs;
pub const afflict = glacial.afflict;

/// Every cell within `RANGE` of `from` the burst reaches past the terrain, `from` aside.
pub fn around(lv: *const grid.Level, from: P) glacial.Cone {
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
