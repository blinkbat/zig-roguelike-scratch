const std = @import("std");

pub const COST: i32 = 30;
pub const COOLDOWN: u8 = 8;
pub const TURNS: u8 = 5;
pub const DONE = "raises a mana shield";
pub const STATUS = "Damage drains mana before life.";
pub const DESCRIPTION = std.fmt.comptimePrint("For {d} turns, harm is taken from mana before life, a point for a point.", .{TURNS});
pub const FLAVOR = "Spend the mind to spare the flesh.";

/// Its turns left: the turn it is raised in is the first, the foes' blows in it already turned.
pub const Ward = struct {
    turns: u8 = 0,

    pub fn raise(self: *Ward) void {
        self.turns = TURNS;
    }

    /// A turn of it is spent.
    pub fn wear(self: *Ward) void {
        self.turns -|= 1;
    }

    /// Of `dmg`, what `mana` takes while it holds.
    pub fn takes(self: Ward, mana: i32, dmg: i32) i32 {
        return if (self.turns == 0) 0 else std.math.clamp(dmg, 0, @max(0, mana));
    }
};

test "a mana shield takes harm from mana first, until the mana or its turns run out" {
    var w = Ward{};
    try std.testing.expectEqual(@as(i32, 0), w.takes(50, 6));
    w.raise();
    try std.testing.expectEqual(@as(i32, 6), w.takes(50, 6));
    try std.testing.expectEqual(@as(i32, 4), w.takes(4, 6));
    try std.testing.expectEqual(@as(i32, 0), w.takes(0, 6));
    for (0..TURNS) |_| w.wear();
    try std.testing.expectEqual(@as(i32, 0), w.takes(50, 6));
    std.debug.print("mana shield: {d} turns, a point of mana a point of harm\n", .{TURNS});
}
