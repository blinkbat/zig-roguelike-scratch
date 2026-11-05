const std = @import("std");
const mathx = @import("../core/mathx.zig");
const resilience = @import("resilience.zig");

pub const AILMENT = resilience.Kind.maim;
pub const TURNS: u8 = 4;
pub const TAKES = "is maimed";
pub const LIMPS = "limps";
pub const STATUS = "Every second step costs an extra turn.";

/// Its turns left limping, and whether its next step is the one that costs a turn.
pub const Maim = struct {
    turns: u8 = 0,
    limp: bool = false,

    pub fn start(self: *Maim) void {
        resilience.lengthen(&self.turns, TURNS);
    }

    /// A step taken on a turn it held, worn already or not: whether it costs the body its next turn.
    pub fn step(self: *Maim) bool {
        const costs = self.limp;
        self.limp = !self.limp and self.turns > 0;
        return costs;
    }

    pub fn wear(self: *Maim) bool {
        return resilience.wearTurn(&self.turns);
    }

    /// The turn is over: a limp outlives no maim.
    pub fn settle(self: *Maim) void {
        if (self.turns == 0) self.limp = false;
    }
};

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.maim.start();
}

test "a maimed body loses a turn to every second step, and walks freely once it wears off" {
    var m = Maim{};
    m.start();
    var lost: usize = 0;
    for (0..TURNS) |_| {
        lost += @intFromBool(m.turns > 0 and m.step());
        _ = m.wear();
    }
    try std.testing.expectEqual(@as(usize, TURNS / 2), lost);
    m.settle();
    try std.testing.expectEqualDeep(Maim{}, m);
    try std.testing.expect(!(m.turns > 0 and m.step()));
    var worn_first = Maim{};
    worn_first.start();
    var foe_lost: usize = 0;
    for (0..TURNS) |_| {
        const maimed = worn_first.turns > 0;
        _ = worn_first.wear();
        foe_lost += @intFromBool(maimed and worn_first.step());
    }
    worn_first.settle();
    try std.testing.expectEqual(lost, foe_lost);
    try std.testing.expectEqualDeep(Maim{}, worn_first);
    m.turns = 9;
    m.start();
    try std.testing.expectEqual(@as(u8, 9), m.turns);
    std.debug.print("maim: {d} of {d} steps cost a turn; none once worn off\n", .{ lost, TURNS });
}
