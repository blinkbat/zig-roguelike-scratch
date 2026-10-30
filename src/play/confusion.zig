const std = @import("std");
const mathx = @import("../core/mathx.zig");

pub const TURNS: u8 = 3;
/// Percent of a confused body's moves that go a random way.
pub const CHANCE: u32 = 50;
pub const TAKES = "is confused";
pub const STUMBLES = "stumbles";
pub const STATUS = std.fmt.comptimePrint("{d}% of moves go a random way.", .{CHANCE});

/// Its turns left moving unsteadily.
pub const Confusion = struct {
    turns: u8 = 0,

    pub fn start(self: *Confusion) void {
        self.turns = @max(self.turns, TURNS);
    }

    /// One of its turns: whether it is confused this turn.
    pub fn wear(self: *Confusion) bool {
        if (self.turns == 0) return false;
        self.turns -= 1;
        return true;
    }
};

/// Whether a move goes astray; a body not confused draws nothing.
pub fn strays(confused: bool, rng: *mathx.Rng) bool {
    return confused and rng.percent(CHANCE);
}

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.confusion.start();
}

test "confusion sends about half of moves astray for three turns and draws nothing once it ends" {
    var rng = mathx.Rng.init(0xC0F);
    var astray: usize = 0;
    for (0..1000) |_| astray += @intFromBool(strays(true, &rng));
    try std.testing.expect(astray > 450 and astray < 550);
    var c = Confusion{};
    c.start();
    var confused: u8 = 0;
    while (c.wear()) confused += 1;
    try std.testing.expectEqual(TURNS, confused);
    const before = rng;
    try std.testing.expect(!strays(false, &rng));
    try std.testing.expectEqualDeep(before, rng);
    std.debug.print("confusion: {d}/1000 moves astray, {d} turns, no draw when clear\n", .{ astray, confused });
}
