const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");

const P = mathx.P;

pub const COST: i32 = 2;
pub const VERB = "cleaves";
/// Turns off the way aimed, round the hero, of the tiles it sweeps.
const SPREAD = [_]u3{ 7, 0, 1 };
pub const WIDTH: usize = SPREAD.len;
pub const DESCRIPTION = std.fmt.comptimePrint("Swing through the {d} tiles in an arc ahead, striking each foe there.", .{WIDTH});

pub const BASE = damage.Base{ .lo = 2, .hi = 4 };

pub const Arc = grid.Area(WIDTH);

/// The cell toward `to` and the two either side of it round `from`, those a step could reach.
pub fn arc(lv: *const grid.Level, from: P, to: P) Arc {
    const d = mathx.dirTo(from, to) orelse return .{};
    var dirs: [WIDTH]mathx.Dir = undefined;
    for (SPREAD, &dirs) |turn, *s| s.* = d.turned(turn);
    return lv.reachable(WIDTH, from, dirs);
}

/// An arc with a body or barrel in it.
pub fn aimable(lv: *const grid.Level, from: P, to: P) bool {
    const a = arc(lv, from, to);
    for (a.slice()) |p| {
        if (lv.taken(p)) return true;
    }
    return false;
}

test "a cleave sweeps the three tiles round the one aimed at, cardinal or diagonal, and never through a wall" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    var a = arc(&lv, from, .{ .x = 20, .y = 19 });
    try std.testing.expectEqual(WIDTH, a.n);
    for ([_]P{ .{ .x = 19, .y = 19 }, .{ .x = 20, .y = 19 }, .{ .x = 21, .y = 19 } }) |p| try std.testing.expect(a.has(p));
    a = arc(&lv, from, .{ .x = 21, .y = 21 });
    for ([_]P{ .{ .x = 21, .y = 20 }, .{ .x = 21, .y = 21 }, .{ .x = 20, .y = 21 } }) |p| try std.testing.expect(a.has(p));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 21, .y = 21 }));
    lv.stand(.{ .x = 20, .y = 21 }, 2);
    try std.testing.expect(aimable(&lv, from, .{ .x = 21, .y = 21 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 20, .y = 19 }));
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    try std.testing.expectEqual(@as(usize, 2), arc(&lv, from, .{ .x = 21, .y = 21 }).n);
    try std.testing.expectEqual(@as(usize, 0), arc(&lv, from, .{ .x = 22, .y = 22 }).n);
    std.debug.print("cleave: {d}-tile arc, cardinal and diagonal, walls excluded\n", .{WIDTH});
}
