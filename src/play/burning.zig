const std = @import("std");
const mathx = @import("../core/mathx.zig");
const damage = @import("damage.zig");

pub const COST: i32 = 20;
pub const FIRE_LO: i32 = 2;
pub const FIRE_HI: i32 = 4;
pub const CHANCE: u32 = 50;
pub const TURNS: u8 = 3;
pub const PER_TURN: i32 = 4;
pub const VERB = "shoots a burning arrow into";
pub const TAKES = "catches fire";
pub const ELEMENT: damage.Element = .fire;
pub const DESCRIPTION = std.fmt.comptimePrint("Adds {d}-{d} fire damage. {d}% burn chance: {d} fire damage for {d} turns. {d} mana.", .{ FIRE_LO, FIRE_HI, CHANCE, PER_TURN, TURNS, COST });

pub const Burn = damage.Lasting(TURNS, i16, seared);

fn seared(fire_resist: i16) i32 {
    return damage.resisted(PER_TURN, fire_resist);
}

pub const roll = mathx.Rng.rolls(FIRE_LO, FIRE_HI);

pub fn procs(rng: *mathx.Rng, _: i16) bool {
    return rng.percent(CHANCE);
}

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.burn.start();
}

test "burning begins next turn, lasts three ticks and refreshes without stacking or postponing a tick" {
    var b = Burn{};
    b.start();
    try std.testing.expectEqual(@as(?i32, null), b.tick(0));
    try std.testing.expectEqual(@as(?i32, PER_TURN), b.tick(0));
    b.start();
    var total: i32 = 0;
    for (0..TURNS) |_| total += b.tick(50).?;
    try std.testing.expectEqual(damage.resisted(PER_TURN, 50) * TURNS, total);
    try std.testing.expectEqual(@as(?i32, null), b.tick(0));
    var rng = mathx.Rng.init(811);
    var hits: usize = 0;
    for (0..1000) |_| {
        if (procs(&rng, 0)) hits += 1;
    }
    try std.testing.expect(hits > 400 and hits < 600);
    std.debug.print("burning: {d}/1000 ignites, {d} ticks, {d} damage at 50% fire resistance\n", .{ hits, TURNS, total });
}
