const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");

pub const RANGE: i32 = 2;
/// The one leap that spends no turn.
pub const FREE = true;
pub const COOLDOWN: u8 = 3;
pub const COST: i32 = 25;
pub const DESCRIPTION = std.fmt.comptimePrint("Jump to visible empty ground within {d} tiles. {d} mana, no turn cost, {d}-turn cooldown.", .{ RANGE, COST, COOLDOWN });

pub fn inReach(from: mathx.P, to: mathx.P, range: i32) bool {
    return mathx.dist(from, to) <= range;
}

/// Any leap's landings: visible vacant ground within `range`, whatever lies between.
pub fn lands(lv: *const grid.Level, from: mathx.P, to: mathx.P, range: i32) bool {
    return !to.eq(from) and inReach(from, to, range) and lv.isLit(to) and lv.vacant(to);
}

pub fn aimable(lv: *const grid.Level, from: mathx.P, to: mathx.P) bool {
    return lands(lv, from, to, RANGE);
}

test "juke lands up to two tiles away across obstacles but only on visible empty ground" {
    var lv = grid.openFloor();
    const from = mathx.P{ .x = 20, .y = 20 };
    lv.lit = @splat(true);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    lv.set(.{ .x = 20, .y = 21 }, .water);
    try std.testing.expect(aimable(&lv, from, .{ .x = 22, .y = 22 }));
    try std.testing.expect(aimable(&lv, from, .{ .x = 22, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 23, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, from));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 21, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 20, .y = 21 }));
    const to = mathx.P{ .x = 22, .y = 20 };
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
