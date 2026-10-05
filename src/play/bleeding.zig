const std = @import("std");
const mathx = @import("../core/mathx.zig");
const damage = @import("damage.zig");

pub const TURNS: u8 = 5;
pub const STILL: i32 = 1;
pub const MOVING: i32 = 2;

pub const Bleed = damage.Lasting(TURNS, bool, torn);

fn torn(moved: bool) i32 {
    return if (moved) MOVING else STILL;
}

pub fn procs(rng: *mathx.Rng, chance: u32) bool {
    return chance > 0 and rng.percent(chance);
}

test "bleeding begins next turn, lasts five ticks, doubles on a turn moved and refreshes without stacking" {
    var b = Bleed{};
    b.start();
    try std.testing.expectEqual(@as(?i32, null), b.tick(true));
    try std.testing.expectEqual(@as(?i32, STILL), b.tick(false));
    try std.testing.expectEqual(@as(?i32, MOVING), b.tick(true));
    b.start();
    var still: i32 = 0;
    for (0..TURNS) |_| still += b.tick(false).?;
    try std.testing.expectEqual(@as(?i32, null), b.tick(true));
    b.start();
    b.fresh = false;
    var moving: i32 = 0;
    for (0..TURNS) |_| moving += b.tick(true).?;
    std.debug.print("bleeding: {d} damage over {d} turns standing, {d} moving every turn\n", .{ still, TURNS, moving });
    try std.testing.expectEqual(@as(i32, 5), still);
    try std.testing.expectEqual(@as(i32, 10), moving);
}
