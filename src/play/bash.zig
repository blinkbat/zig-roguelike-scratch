const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const clock = @import("clock.zig");
const damage = @import("damage.zig");

const P = mathx.P;

pub const COST: i32 = 20;
pub const COOLDOWN: u8 = 3;
pub const DMG_LO: i32 = 2;
pub const DMG_HI: i32 = 4;
pub const CHANCE: u32 = 50;
pub const VERB = "shield-bashes";
pub const TAKES = clock.STUNNED;
pub const DESCRIPTION = std.fmt.comptimePrint("{s} to an adjacent foe and knocks it back a tile. {s}.", .{ BASE.text(null), clock.stunNote(CHANCE) });

pub const BASE = damage.Base{ .lo = DMG_LO, .hi = DMG_HI };

pub const procs = damage.chance(CHANCE);
pub const afflict = clock.stuns;

/// A body or barrel beside `from`.
pub fn aimable(lv: *const grid.Level, from: P, to: P) bool {
    const d = mathx.dirTo(from, to) orelse return false;
    return lv.passOk(from, d) and lv.taken(to);
}

/// Where the body `id` at `at` is knocked to, struck the way `d` goes; null when something stands there or it may not step there.
pub fn knocked(lv: *const grid.Level, at: P, d: mathx.Dir, id: u16) ?P {
    return if (lv.stepOk(at, d, id)) at.add(d.delta()) else null;
}

test "a bash reaches a body or barrel beside the knight, and knocks a body back onto open ground only" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    const foe = P{ .x = 21, .y = 21 };
    lv.stand(foe, 2);
    try std.testing.expect(aimable(&lv, from, foe));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 21, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 22, .y = 22 }));
    lv.putBarrel(.{ .x = 19, .y = 20 });
    try std.testing.expect(aimable(&lv, from, .{ .x = 19, .y = 20 }));
    try std.testing.expectEqual(@as(?P, .{ .x = 22, .y = 22 }), knocked(&lv, foe, .se, 2));
    lv.set(.{ .x = 22, .y = 22 }, .wall);
    try std.testing.expectEqual(@as(?P, null), knocked(&lv, foe, .se, 2));
    lv.set(.{ .x = 22, .y = 22 }, .floor);
    lv.stand(.{ .x = 22, .y = 22 }, 3);
    try std.testing.expectEqual(@as(?P, null), knocked(&lv, foe, .se, 2));
    std.debug.print("shield bash: reach 1, knockback 1 onto open ground; {d}% stun\n", .{CHANCE});
}
