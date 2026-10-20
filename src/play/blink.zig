const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const juke = @import("juke.zig");

pub const RANGE: i32 = 4;
pub const COOLDOWN: u8 = 3;
pub const COST: i32 = 35;
pub const TELEPORTS = true;
pub const DONE = "blinks away";
pub const DESCRIPTION = std.fmt.comptimePrint("Teleport to visible empty ground within {d} tiles.", .{RANGE});

comptime {
    std.debug.assert(RANGE > juke.RANGE and COST > juke.COST);
}

pub fn aimable(lv: *const grid.Level, from: mathx.P, to: mathx.P) bool {
    return juke.lands(lv, from, to, RANGE);
}

test "blink lands further than juke, across obstacles, only on visible empty ground" {
    var lv = grid.openFloor();
    const from = mathx.P{ .x = 20, .y = 20 };
    lv.lit = @splat(true);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    const far = mathx.P{ .x = 24, .y = 24 };
    try std.testing.expect(aimable(&lv, from, far));
    try std.testing.expect(!juke.aimable(&lv, from, .{ .x = 23, .y = 23 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 25, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 21, .y = 20 }));
    lv.lightless();
    try std.testing.expect(!aimable(&lv, from, far));
    std.debug.print("Blink range: {d} tiles against Juke's {d}; {d} mana against {d}\n", .{ RANGE, juke.RANGE, COST, juke.COST });
}
