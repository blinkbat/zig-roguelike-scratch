const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");

pub const RANGE: i32 = 3;
pub const COOLDOWN: u8 = 3;
pub const COST: i32 = 20;
pub const DESCRIPTION = std.fmt.comptimePrint("Jump to visible empty ground within {d} tiles. {d} mana, no turn cost, {d}-turn cooldown.", .{ RANGE, COST, COOLDOWN });

pub fn aimable(lv: *const grid.Level, from: mathx.P, to: mathx.P) bool {
    const d = mathx.dist(from, to);
    return d >= 1 and d <= RANGE and lv.isLit(to) and lv.vacant(to);
}

test "juke lands up to three tiles away across obstacles but only on visible empty ground" {
    var lv = grid.openFloor();
    const from = mathx.P{ .x = 20, .y = 20 };
    lv.lit = @splat(true);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    lv.set(.{ .x = 20, .y = 21 }, .water);
    try std.testing.expect(aimable(&lv, from, .{ .x = 23, .y = 23 }));
    try std.testing.expect(aimable(&lv, from, .{ .x = 23, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 24, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, from));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 21, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 20, .y = 21 }));
    const to = mathx.P{ .x = 23, .y = 20 };
    lv.putBarrel(to);
    try std.testing.expect(!aimable(&lv, from, to));
    _ = lv.breakBarrel(to);
    lv.stand(to, 2);
    try std.testing.expect(!aimable(&lv, from, to));
    lv.clear(to);
    lv.lightless();
    try std.testing.expect(!aimable(&lv, from, to));
    std.debug.print("Juke range: {d} tiles, diagonal and obstacle crossings checked\n", .{RANGE});
}
