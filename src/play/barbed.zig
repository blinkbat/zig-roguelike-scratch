const std = @import("std");
const mathx = @import("../core/mathx.zig");
const bleeding = @import("bleeding.zig");

pub const COST: i32 = 30;
pub const VERB = "shoots a barbed arrow into";
pub const TAKES = bleeding.TAKES;
pub const DESCRIPTION = std.fmt.comptimePrint("Arrow damage. A target it leaves alive always bleeds: {d} a turn, {d} on a turn it moves, for {d} turns. {d} mana.", .{ bleeding.STILL, bleeding.MOVING, bleeding.TURNS, COST });

pub fn procs(_: *mathx.Rng, _: i16) bool {
    return true;
}

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.bleed.start();
}

test "a barbed arrow always opens a bleed" {
    var rng = mathx.Rng.init(0xBA4B);
    var a: struct { bleed: bleeding.Bleed = .{} } = .{};
    for (0..100) |_| try std.testing.expect(procs(&rng, 0));
    afflict(&a, &rng);
    try std.testing.expectEqual(bleeding.TURNS, a.bleed.turns);
    std.debug.print("barbed arrow: 100 of 100 procs, a bleed of {d} turns\n", .{bleeding.TURNS});
}
