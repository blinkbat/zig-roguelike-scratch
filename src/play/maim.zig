const std = @import("std");
const mathx = @import("../core/mathx.zig");
const resilience = @import("resilience.zig");

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

    /// A step taken: whether it costs the body its next turn.
    pub fn step(self: *Maim) bool {
        if (self.turns == 0) return false;
        defer self.limp = !self.limp;
        return self.limp;
    }

    pub fn wear(self: *Maim) bool {
        const ran = resilience.wearTurn(&self.turns);
        if (self.turns == 0) self.limp = false;
        return ran;
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
        lost += @intFromBool(m.step());
        _ = m.wear();
    }
    try std.testing.expectEqual(@as(usize, TURNS / 2), lost);
    try std.testing.expectEqualDeep(Maim{}, m);
    try std.testing.expect(!m.step());
    m.turns = 9;
    m.start();
    try std.testing.expectEqual(@as(u8, 9), m.turns);
    std.debug.print("maim: {d} of {d} steps cost a turn; none once worn off\n", .{ lost, TURNS });
}
