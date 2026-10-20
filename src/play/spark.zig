const std = @import("std");
const mathx = @import("../core/mathx.zig");
const damage = @import("damage.zig");
const clock = @import("clock.zig");

pub const COST: i32 = 10;
pub const LIGHTNING_LO: i32 = 3;
pub const LIGHTNING_HI: i32 = 6;
pub const CHANCE: u32 = 50;
pub const VERB = "sparks";
pub const BOLT = "spark";
pub const TAKES = clock.STUNNED;
pub const ELEMENT: damage.Element = .lightning;
pub const DESCRIPTION = std.fmt.comptimePrint("Strike a target in sight with lightning. {s}.", .{clock.stunNote(CHANCE)});

pub const BASE = damage.Base{ .lo = LIGHTNING_LO, .hi = LIGHTNING_HI };

pub const procs = damage.chance(CHANCE);
pub const afflict = clock.stuns;

test "a spark stuns about half the time" {
    var rng = mathx.Rng.init(813);
    var hits: usize = 0;
    for (0..1000) |_| {
        if (procs(&rng, 0)) hits += 1;
    }
    try std.testing.expect(hits > 400 and hits < 600);
    std.debug.print("spark: {d}/1000 stun\n", .{hits});
}
