const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const bash = @import("bash.zig");

const P = mathx.P;

pub const COST: i32 = 20;
pub const COOLDOWN: u8 = 4;
pub const RANGE: i32 = 3;
pub const MIN_RANGE: i32 = 2;
pub const DMG_LO: i32 = 3;
pub const DMG_HI: i32 = 5;
pub const VERB = "charges into";
pub const DESCRIPTION = std.fmt.comptimePrint("Rush in a straight line at a foe {d} to {d} tiles away: {d}-{d} damage, and it is knocked back a tile. {d} mana, {d}-turn cooldown.", .{ MIN_RANGE, RANGE, DMG_LO, DMG_HI, COST, COOLDOWN });

pub const roll = mathx.Rng.rolls(DMG_LO, DMG_HI);

pub const knocked = bash.knocked;

/// The way from `from` to `to` along a row, a column or a diagonal; null off them.
pub fn wayTo(from: P, to: P) ?mathx.Dir {
    const d = to.sub(from);
    if (d.x != 0 and d.y != 0 and @abs(d.x) != @abs(d.y)) return null;
    return mathx.dirTo(from, from.add(d.sign()));
}

/// Where the hero stops: the cell before the body it charges.
pub fn stop(from: P, to: P) P {
    return to.sub(wayTo(from, to).?.delta());
}

/// A lit body in a line, `MIN_RANGE` tiles off at least, with open ground to it that nothing stands on.
pub fn aimable(lv: *const grid.Level, from: P, to: P) bool {
    const d = wayTo(from, to) orelse return false;
    const n = mathx.dist(from, to);
    if (n < MIN_RANGE or n > RANGE or !lv.isLit(to) or lv.who(to) == grid.NO_ONE) return false;
    var at = from;
    for (0..@intCast(n - 1)) |_| {
        if (!lv.passOk(at, d)) return false;
        at = at.add(d.delta());
        if (!lv.vacant(at)) return false;
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
