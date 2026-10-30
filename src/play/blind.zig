const std = @import("std");
const mathx = @import("../core/mathx.zig");
const resilience = @import("resilience.zig");

pub const TURNS: u8 = 3;
/// Cells a blinded body sees.
pub const SIGHT: i32 = 1;
pub const TAKES = "is blinded";
pub const STATUS = "Sees only adjacent cells.";

/// Its turns left unable to see past the cells beside it.
pub const Blind = resilience.Turns(TURNS);

/// The cells a body whose eyes reach `normal` sees.
pub fn sight(blinded: bool, normal: i32) i32 {
    return if (blinded) @min(normal, SIGHT) else normal;
}

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.blind.start();
}

test "blindness narrows sight to the next cell for three turns, and a second never shortens the first" {
    var b = Blind{};
    b.start();
    var blinded: u8 = 0;
    while (b.wear()) blinded += 1;
    try std.testing.expectEqual(TURNS, blinded);
    try std.testing.expectEqual(SIGHT, sight(true, 10));
    try std.testing.expectEqual(@as(i32, 0), sight(true, 0));
    try std.testing.expectEqual(@as(i32, 10), sight(false, 10));
    b.turns = 9;
    b.start();
    try std.testing.expectEqual(@as(u8, 9), b.turns);
    std.debug.print("blind: {d} turns seeing {d} cell, sight 10 restored after\n", .{ blinded, SIGHT });
}
