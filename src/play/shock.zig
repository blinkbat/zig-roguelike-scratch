const std = @import("std");
const mathx = @import("../core/mathx.zig");
const resilience = @import("resilience.zig");

pub const TURNS: u8 = 3;
/// Percent more damage the hit it is spent on deals, rounded up.
pub const MORE: i32 = 50;
pub const TAKES = "is shocked";
pub const STATUS = std.fmt.comptimePrint("The next hit taken deals {d}% more damage.", .{MORE});

/// Its turns left waiting for a hit; the first that deals damage spends it.
pub const Shock = struct {
    turns: u8 = 0,

    pub fn start(self: *Shock) void {
        resilience.lengthen(&self.turns, TURNS);
    }

    /// `dmg` as the hit it is spent on deals it; a hit dealing nothing leaves it waiting.
    pub fn spend(self: *Shock, dmg: i32) i32 {
        if (self.turns == 0 or dmg <= 0) return dmg;
        self.turns = 0;
        return std.math.lossyCast(i32, @divTrunc(@as(i64, dmg) * (mathx.PERCENT + MORE) + mathx.PERCENT - 1, mathx.PERCENT));
    }

    pub fn wear(self: *Shock) void {
        _ = resilience.wearTurn(&self.turns);
    }
};

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.shock.start();
}

test "a shock adds half again to the next damaging hit, rounded up, then is gone" {
    const cases = [_][2]i32{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 5 }, .{ 4, 6 }, .{ 10, 15 } };
    for (cases) |c| {
        var s = Shock{};
        s.start();
        try std.testing.expectEqual(c[1], s.spend(c[0]));
        try std.testing.expectEqual(@as(u8, 0), s.turns);
        try std.testing.expectEqual(c[0], s.spend(c[0]));
    }
    var s = Shock{};
    s.start();
    try std.testing.expectEqual(@as(i32, 0), s.spend(0));
    try std.testing.expectEqual(TURNS, s.turns);
    for (0..TURNS) |_| s.wear();
    try std.testing.expectEqual(@as(i32, 4), s.spend(4));
    s.start();
    try std.testing.expectEqual(std.math.maxInt(i32), s.spend(std.math.maxInt(i32)));
    std.debug.print("shock: {d} hits each amplified once ({d}% rounded up); a 0-damage hit keeps it; {d} unhit turns end it\n", .{ cases.len, MORE, TURNS });
}
