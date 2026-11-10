const std = @import("std");
const mathx = @import("../core/mathx.zig");
const bleeding = @import("bleeding.zig");
const damage = @import("damage.zig");
const resilience = @import("resilience.zig");

pub const COST: i32 = 6;
pub const AILMENT = bleeding.AILMENT;
pub const VERB = "shoots a barbed arrow into";
pub const TAKES = bleeding.TAKES;
pub const DESCRIPTION = "Arrow damage. Inflicts bleeding.";

pub const CHANCE: u32 = mathx.PERCENT;
pub const procs = damage.chance(CHANCE);
pub const chance = damage.flat(CHANCE);

pub const afflict = resilience.Starts(AILMENT).afflict;

test "a barbed arrow always opens a bleed" {
    var rng = mathx.Rng.init(0xBA4B);
    var a: struct { bleed: bleeding.Bleed = .{} } = .{};
    const tries = 100;
    for (0..tries) |_| try std.testing.expect(procs(&rng, 0));
    afflict(&a, &rng);
    try std.testing.expectEqual(bleeding.TURNS, a.bleed.turns);
    std.debug.print("barbed arrow: {d} of {d} procs, a bleed of {d} turns\n", .{ tries, tries, bleeding.TURNS });
}
