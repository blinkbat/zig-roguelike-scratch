const std = @import("std");
const mathx = @import("../core/mathx.zig");
const resilience = @import("resilience.zig");

pub const TURNS: u8 = 4;
pub const MOST: u8 = 3;
/// Points of armour each stack takes off.
pub const PER_STACK: i32 = 10;
pub const TAKES = "is sundered";
pub const STATUS = std.fmt.comptimePrint("Physical damage reduction lowered by {d}% per stack, up to {d} stacks.", .{ PER_STACK, MOST });

/// Its stacks, which all fall away when its turns run out.
pub const Sunder = struct {
    stacks: u8 = 0,
    turns: u8 = 0,

    /// Another stack, up to `MOST`, and its turns begin again.
    pub fn stack(self: *Sunder) void {
        self.stacks = @min(MOST, self.stacks + 1);
        self.turns = TURNS;
    }

    /// The armour it takes off.
    pub fn lost(self: Sunder) i32 {
        return PER_STACK * self.stacks;
    }

    pub fn wear(self: *Sunder) void {
        _ = resilience.wearTurn(&self.turns);
        if (self.turns == 0) self.stacks = 0;
    }
};

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.sunder.stack();
}

test "sunder stacks to three, each refreshing its turns, and every stack falls away together" {
    var s = Sunder{};
    for (0..MOST + 2) |_| s.stack();
    try std.testing.expectEqual(MOST, s.stacks);
    try std.testing.expectEqual(PER_STACK * MOST, s.lost());
    for (0..TURNS - 1) |_| s.wear();
    s.stack();
    for (0..TURNS - 1) |_| s.wear();
    try std.testing.expectEqual(PER_STACK * MOST, s.lost());
    s.wear();
    try std.testing.expectEqualDeep(Sunder{}, s);
    try std.testing.expectEqual(@as(i32, 0), s.lost());
    std.debug.print("sunder: {d} stacks of {d} armour, {d} turns from the latest stack, then all at once\n", .{ MOST, PER_STACK, TURNS });
}
