const std = @import("std");
const mathx = @import("../core/mathx.zig");
const resilience = @import("resilience.zig");

pub const AILMENT = resilience.Kind.enfeeble;
pub const TURNS: u8 = 3;
/// Percent less damage an enfeebled body's blows deal, rounded up so a blow still lands.
pub const LESS: i32 = 30;
pub const TAKES = "is enfeebled";
pub const STATUS = std.fmt.comptimePrint("Deals {d}% less damage with its blows.", .{LESS});

/// Its turns left striking weakly.
pub const Enfeeble = resilience.Turns(TURNS);

/// `dmg` as a blow struck by a body, enfeebled or not, deals it.
pub fn weaken(enfeebled: bool, dmg: i32) i32 {
    if (!enfeebled or dmg <= 0) return dmg;
    return mathx.lessCeil(dmg, LESS);
}

pub const afflict = resilience.Starts(AILMENT).afflict;

test "an enfeebled blow deals 30% less, rounded up so it never falls to nothing, for three turns" {
    const cases = [_][2]i32{ .{ 1, 1 }, .{ 2, 2 }, .{ 3, 3 }, .{ 4, 3 }, .{ 10, 7 }, .{ 15, 11 } };
    for (cases) |c| {
        try std.testing.expectEqual(c[1], weaken(true, c[0]));
        try std.testing.expectEqual(c[0], weaken(false, c[0]));
    }
    try std.testing.expectEqual(@as(i32, 0), weaken(true, 0));
    var e = Enfeeble{};
    e.start();
    var weak: u8 = 0;
    while (e.wear()) weak += 1;
    try std.testing.expectEqual(TURNS, weak);
    std.debug.print("enfeeble: {d} blows weakened by {d}% rounded up, {d} turns\n", .{ cases.len, LESS, weak });
}
