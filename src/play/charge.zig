const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const bash = @import("bash.zig");

const P = mathx.P;

pub const COST: i32 = 3;
pub const COOLDOWN: u8 = 4;
pub const RANGE: i32 = 3;
pub const MIN_RANGE: i32 = 2;
pub const VERB = "charges into";
pub const DONE = "charges";
pub const DESCRIPTION = std.fmt.comptimePrint("Rush {d}-{d} tiles along a clear line. Strike a foe at the end and knock it back a tile, or retreat to empty ground.", .{ MIN_RANGE, RANGE });
pub const FLAVOR = "Distance is only a matter of resolve.";

pub const BASE = damage.Base{ .lo = 3, .hi = 5 };

pub const knocked = bash.knocked;

/// The way from `from` to `to` along a row, a column or a diagonal; null off them.
pub fn wayTo(from: P, to: P) ?mathx.Dir {
    const d = to.sub(from);
    if (d.x != 0 and d.y != 0 and @abs(d.x) != @abs(d.y)) return null;
    return mathx.stepDir(d.sign());
}

/// Where the hero stops: the cell before the body it charges.
pub fn stop(from: P, to: P) P {
    return to.sub(wayTo(from, to).?.delta());
}

/// A lit body or empty landing in a straight line; every intervening cell must be lit and vacant.
pub fn aimable(lv: *const grid.Level, from: P, to: P) bool {
    const d = wayTo(from, to) orelse return false;
    const n = mathx.dist(from, to);
    if (n < MIN_RANGE or n > RANGE or !lv.isLit(to) or (!lv.vacant(to) and lv.who(to) == grid.NO_ONE)) return false;
    var at = from;
    for (0..@intCast(n - 1)) |_| {
        if (!lv.passOk(at, d)) return false;
        at = at.add(d.delta());
        if (!lv.vacant(at) or !lv.isLit(at)) return false;
    }
    return true;
}

test "a charge runs a straight open line of two or three tiles to a lit body, and stops beside it" {
    var lv = grid.openFloor();
    lv.lit = @splat(true);
    const from = P{ .x = 20, .y = 20 };
    lv.stand(.{ .x = 23, .y = 20 }, 2);
    lv.stand(.{ .x = 22, .y = 22 }, 3);
    lv.stand(.{ .x = 21, .y = 19 }, 4);
    lv.stand(.{ .x = 22, .y = 17 }, 5);
    try std.testing.expect(aimable(&lv, from, .{ .x = 23, .y = 20 }));
    try std.testing.expectEqual(P{ .x = 22, .y = 20 }, stop(from, .{ .x = 23, .y = 20 }));
    try std.testing.expect(aimable(&lv, from, .{ .x = 22, .y = 22 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 21, .y = 19 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 22, .y = 17 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 24, .y = 20 }));
    lv.putBarrel(.{ .x = 21, .y = 20 });
    try std.testing.expect(!aimable(&lv, from, .{ .x = 23, .y = 20 }));
    _ = lv.breakBarrel(.{ .x = 21, .y = 20 });
    lv.set(.{ .x = 21, .y = 21 }, .water);
    try std.testing.expect(!aimable(&lv, from, .{ .x = 22, .y = 22 }));
    lv.stand(.{ .x = 24, .y = 20 }, 6);
    lv.lit[grid.Level.idx(.{ .x = 23, .y = 20 })] = false;
    try std.testing.expect(!aimable(&lv, from, .{ .x = 23, .y = 20 }));
    std.debug.print("charge: {d} to {d} tiles in 8 lines, blocked by a barrel, water, a body or darkness\n", .{ MIN_RANGE, RANGE });
}
