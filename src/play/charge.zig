const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const bash = @import("bash.zig");

const P = mathx.P;

pub const COST: i32 = 3;
pub const COOLDOWN: u8 = 4;
/// The furthest foe struck: the tile past the end of the longest rush.
pub const RANGE: i32 = 4;
pub const MIN_RANGE: i32 = 1;
pub const VERB = "charges into";
pub const DONE = "charges";
pub const DESCRIBED = "Rush along a clear line to strike a foe {d}-{d} tiles away and knock it back a tile, or retreat to empty ground short of that.";
pub const DESCRIPTION = std.fmt.comptimePrint(DESCRIBED, .{ MIN_RANGE, RANGE });

pub const BASE = damage.Base{ .lo = 5, .hi = 8 };

pub const knocked = bash.knocked;

/// The way from `from` to `to` along a row, a column or a diagonal; null off them.
pub fn wayTo(from: P, to: P) ?mathx.Dir {
    const d = to.sub(from);
    if (d.x != 0 and d.y != 0 and @abs(d.x) != @abs(d.y)) return null;
    return mathx.toward(from, to);
}

/// Where the hero stops: the cell before the body it charges.
pub fn stop(from: P, to: P) P {
    return to.sub(wayTo(from, to).?.delta());
}

/// A lit body within `range`, or an empty landing short of it, in a straight line; every intervening cell must be lit and vacant.
pub fn aimable(lv: *const grid.Level, from: P, to: P, range: i32) bool {
    const d = wayTo(from, to) orelse return false;
    const n = mathx.dist(from, to);
    const body = lv.who(to) != grid.NO_ONE;
    if (n < MIN_RANGE or n > range - @intFromBool(!body) or !lv.isLit(to) or (!lv.vacant(to) and !body)) return false;
    var at = from;
    for (0..@intCast(n - 1)) |_| {
        if (!lv.passOk(at, d)) return false;
        at = at.add(d.delta());
        if (!lv.vacant(at) or !lv.isLit(at)) return false;
    }
    return true;
}

test "a charge strikes a lit body one to four tiles off, the tile past its longest rush" {
    var lv = grid.openFloor();
    lv.lit = @splat(true);
    const from = P{ .x = 20, .y = 20 };
    const far = P{ .x = 20, .y = 20 + RANGE };
    try std.testing.expect(!aimable(&lv, from, far, RANGE));
    try std.testing.expect(aimable(&lv, from, .{ .x = 20, .y = 20 + RANGE - 1 }, RANGE));
    lv.stand(far, 2);
    try std.testing.expect(aimable(&lv, from, far, RANGE));
    try std.testing.expectEqual(P{ .x = 20, .y = 20 + RANGE - 1 }, stop(from, far));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 20, .y = 21 + RANGE }, RANGE + 1));
    std.debug.print("charge: rush up to {d} tiles, strike up to {d}\n", .{ RANGE - 1, RANGE });
}

test "a charge runs a straight open line to a lit body in range, and stops beside it" {
    var lv = grid.openFloor();
    lv.lit = @splat(true);
    const from = P{ .x = 20, .y = 20 };
    lv.stand(.{ .x = 23, .y = 20 }, 2);
    lv.stand(.{ .x = 22, .y = 22 }, 3);
    lv.stand(.{ .x = 21, .y = 19 }, 4);
    lv.stand(.{ .x = 22, .y = 17 }, 5);
    try std.testing.expect(aimable(&lv, from, .{ .x = 23, .y = 20 }, RANGE));
    try std.testing.expectEqual(P{ .x = 22, .y = 20 }, stop(from, .{ .x = 23, .y = 20 }));
    try std.testing.expect(aimable(&lv, from, .{ .x = 22, .y = 22 }, RANGE));
    try std.testing.expect(aimable(&lv, from, .{ .x = 21, .y = 19 }, RANGE));
    try std.testing.expectEqual(from, stop(from, .{ .x = 21, .y = 19 }));
    try std.testing.expect(aimable(&lv, from, .{ .x = 20, .y = 21 }, RANGE));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 22, .y = 17 }, RANGE));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 24, .y = 20 }, RANGE));
    lv.putBarrel(.{ .x = 21, .y = 20 });
    try std.testing.expect(!aimable(&lv, from, .{ .x = 23, .y = 20 }, RANGE));
    _ = lv.breakBarrel(.{ .x = 21, .y = 20 });
    lv.set(.{ .x = 21, .y = 21 }, .water);
    try std.testing.expect(!aimable(&lv, from, .{ .x = 22, .y = 22 }, RANGE));
    lv.stand(.{ .x = 24, .y = 20 }, 6);
    lv.lit[grid.Level.idx(.{ .x = 23, .y = 20 })] = false;
    try std.testing.expect(!aimable(&lv, from, .{ .x = 23, .y = 20 }, RANGE));
    std.debug.print("charge: {d} to {d} tiles in {d} lines, blocked by a barrel, water, a body or darkness\n", .{ MIN_RANGE, RANGE, mathx.ALL_DIRS.len });
}
