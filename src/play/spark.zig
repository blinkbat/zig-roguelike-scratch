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
pub const DESCRIPTION = std.fmt.comptimePrint("{d}-{d} lightning damage to a target in sight. {d}% chance to stun. {d} mana.", .{ LIGHTNING_LO, LIGHTNING_HI, CHANCE, COST });

pub const roll = mathx.Rng.rolls(LIGHTNING_LO, LIGHTNING_HI);

pub fn procs(rng: *mathx.Rng, _: i16) bool {
    return rng.percent(CHANCE);
}

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.clock.stun();
}

test "a spark stuns about half the time" {
    var rng = mathx.Rng.init(813);
    var hits: usize = 0;
    for (0..1000) |_| {
        if (procs(&rng, 0)) hits += 1;
    }
    try std.testing.expect(hits > 400 and hits < 600);
    std.debug.print("spark: {d}/1000 stun\n", .{hits});
}
