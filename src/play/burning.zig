const std = @import("std");
const mathx = @import("../core/mathx.zig");
const damage = @import("damage.zig");

pub const COST: i32 = 4;
pub const AILMENT = @import("resilience.zig").Kind.burn;
pub const CHANCE: u32 = 50;
pub const TURNS: u8 = 3;
pub const PER_TURN: i32 = 4;
pub const VERB = "shoots a burning arrow into";
pub const TAKES = "catches fire";
pub const ELEMENT: damage.Element = .fire;
/// Its chance to burn, as every fire skill's description says it.
pub const BURN_NOTE = std.fmt.comptimePrint("{d}% burn chance", .{CHANCE});
pub const STATUS = std.fmt.comptimePrint("Take {d} fire damage per turn, reduced by fire resistance.", .{PER_TURN});
pub const DESCRIPTION = std.fmt.comptimePrint("Add fire damage to an arrow. {s}: {d} fire damage per turn for {d} turns.", .{ BURN_NOTE, PER_TURN, TURNS });
pub const FLAVOR = "Pitch, rag and a spark of spite.";

pub const Burn = damage.Lasting(TURNS, i16, seared);

fn seared(fire_resist: i16) i32 {
    return damage.resisted(PER_TURN, fire_resist);
}

pub const BASE = damage.Base{ .lo = 2, .hi = 4 };

pub const procs = damage.chance(CHANCE);

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
