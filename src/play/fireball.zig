const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const burning = @import("burning.zig");
const glacial = @import("glacial.zig");

const P = mathx.P;

pub const COST: i32 = 25;
/// Tiles round what it strikes that its blast reaches.
pub const BLAST: i32 = 1;
pub const FIRE_LO: i32 = 3;
pub const FIRE_HI: i32 = 6;
pub const VERB = "blasts";
pub const BOLT = "fireball";
pub const TAKES = burning.TAKES;
pub const ELEMENT: damage.Element = .fire;
pub const DESCRIPTION = std.fmt.comptimePrint("A fire bolt bursts on impact, hitting every foe within {d} tile{s}. {s}.", .{ BLAST, mathx.plural(BLAST), burning.BURN_NOTE });

comptime {
    std.debug.assert(BLAST <= glacial.RANGE);
}

pub const BASE = damage.Base{ .lo = FIRE_LO, .hi = FIRE_HI };

pub const procs = burning.procs;
pub const afflict = burning.afflict;

pub fn burst(lv: *const grid.Level, _: P, impact: P) glacial.Cone {
    return glacial.spread(lv, impact, BLAST, {}, every);
}

fn every(_: void, _: P) bool {
    return true;
}

test "a fireball's blast takes the cell it strikes and the eight round it, but not past a wall" {
    var lv = grid.openFloor();
    const at = P{ .x = 20, .y = 20 };
    const open: usize = @intCast(grid.Cells.square(BLAST));
    var area = burst(&lv, .{ .x = 14, .y = 20 }, at);
    try std.testing.expectEqual(open, area.n);
    try std.testing.expect(area.has(at));
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    area = burst(&lv, .{ .x = 14, .y = 20 }, at);
    try std.testing.expectEqual(open - 1, area.n);
    try std.testing.expect(!area.has(.{ .x = 21, .y = 20 }));
    std.debug.print("fireball: a {d}-cell blast on open ground, {d} with a wall in it\n", .{ open, area.n });
}
