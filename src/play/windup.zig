const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");

const P = mathx.P;

/// The farthest a wound-up charge or hook reaches.
pub const LONGEST: i32 = 8;
pub const Lane = grid.Bounded(P, LONGEST);
/// The nearest a hero is braced at; beside it, it strikes instead.
pub const NEAREST: i32 = 2;

/// The way from `from` to `to` when `to` lies on one of the eight straight lines through it.
pub fn lineTo(from: P, to: P) ?mathx.Dir {
    const v = to.sub(from);
    if (v.x == 0 and v.y == 0) return null;
    if (v.x != 0 and v.y != 0 and @abs(v.x) != @abs(v.y)) return null;
    return mathx.toward(from, to);
}

/// The cells along `d` from `from`, `reach` at most, stopping short of the first a step cannot enter.
pub fn lane(lv: *const grid.Level, from: P, d: mathx.Dir, reach: i32) Lane {
    std.debug.assert(reach <= LONGEST);
    var out = Lane{};
    var at = from;
    for (0..@intCast(@max(0, reach))) |_| {
        if (!lv.passOk(at, d)) break;
        at = at.add(d.delta());
        out.push(at);
    }
    return out;
}

/// `lane`, ending on `to` with nothing standing in the cells before it.
pub fn openTo(lv: *const grid.Level, from: P, to: P, reach: i32) ?mathx.Dir {
    const d = lineTo(from, to) orelse return null;
    const l = lane(lv, from, d, reach);
    for (l.slice()) |p| {
        if (p.eq(to)) return d;
        if (lv.held(p)) return null;
    }
    return null;
}

test "only the eight straight lines lead anywhere, and a wall shortens the lane" {
    const from = P{ .x = 10, .y = 10 };
    try std.testing.expectEqual(@as(?mathx.Dir, .e), lineTo(from, .{ .x = 14, .y = 10 }));
    try std.testing.expectEqual(@as(?mathx.Dir, .nw), lineTo(from, .{ .x = 7, .y = 7 }));
    try std.testing.expectEqual(@as(?mathx.Dir, null), lineTo(from, .{ .x = 13, .y = 11 }));
    try std.testing.expectEqual(@as(?mathx.Dir, null), lineTo(from, from));
    var lv = grid.openFloor();
    try std.testing.expectEqual(@as(usize, 5), lane(&lv, from, .s, 5).n);
    lv.set(.{ .x = 10, .y = 13 }, .wall);
    const short = lane(&lv, from, .s, 5);
    try std.testing.expectEqualSlices(P, &.{ .{ .x = 10, .y = 11 }, .{ .x = 10, .y = 12 } }, short.slice());
}

test "an open lane needs every cell short of its end empty" {
    var lv = grid.openFloor();
    const from = P{ .x = 10, .y = 10 };
    const to = P{ .x = 14, .y = 14 };
    try std.testing.expectEqual(@as(?mathx.Dir, .se), openTo(&lv, from, to, 5));
    try std.testing.expectEqual(@as(?mathx.Dir, null), openTo(&lv, from, to, 3));
    lv.putBarrel(.{ .x = 12, .y = 12 });
    try std.testing.expectEqual(@as(?mathx.Dir, null), openTo(&lv, from, to, 5));
}
