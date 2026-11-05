const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const juke = @import("juke.zig");

pub const RANGE: i32 = 4;
pub const COOLDOWN: u8 = 3;
pub const COST: i32 = 7;
pub const TELEPORTS = true;
pub const DONE = "blinks away";
pub const DESCRIBED = "Teleport to visible empty ground within {d} tiles.";
pub const DESCRIPTION = std.fmt.comptimePrint(DESCRIBED, .{RANGE});

comptime {
    std.debug.assert(RANGE > juke.RANGE and COST > juke.COST);
}

pub const aimable = juke.aimable;

test "blink lands further than juke, across obstacles, only on visible empty ground" {
    var lv = grid.openFloor();
    const from = mathx.P{ .x = 20, .y = 20 };
    lv.lit = @splat(true);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    const far = mathx.P{ .x = 24, .y = 24 };
    try std.testing.expect(aimable(&lv, from, far, RANGE));
    try std.testing.expect(!juke.aimable(&lv, from, .{ .x = 23, .y = 23 }, juke.RANGE));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 25, .y = 20 }, RANGE));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 21, .y = 20 }, RANGE));
    lv.lightless();
    try std.testing.expect(!aimable(&lv, from, far, RANGE));
    std.debug.print("Blink range: {d} tiles against Juke's {d}; {d} mana against {d}\n", .{ RANGE, juke.RANGE, COST, juke.COST });
}
