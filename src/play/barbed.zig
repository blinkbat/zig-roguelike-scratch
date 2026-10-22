const std = @import("std");
const mathx = @import("../core/mathx.zig");
const bleeding = @import("bleeding.zig");
const damage = @import("damage.zig");

pub const COST: i32 = 6;
pub const AILMENT = @import("resilience.zig").Kind.bleed;
pub const VERB = "shoots a barbed arrow into";
pub const TAKES = bleeding.TAKES;
pub const DESCRIPTION = std.fmt.comptimePrint("Arrow damage. A surviving target bleeds unless resisted: {d} a turn, {d} when moving, for {d} turns.", .{ bleeding.STILL, bleeding.MOVING, bleeding.TURNS });
pub const FLAVOR = "Easy going in. Impossible coming out.";

pub const procs = damage.always;

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
