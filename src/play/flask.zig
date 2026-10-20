const std = @import("std");
const mathx = @import("../core/mathx.zig");

pub const Kind = enum { life, mana };

/// After PoE2's flasks: charges spent a drink at a time, and refilled by kills.
pub const CHARGES: u8 = 60;
pub const USE: u8 = 20;
pub const PER_KILL: u8 = 5;
/// Turns its recovery runs, from the end of the turn it is drunk in.
pub const TURNS: u8 = 3;
pub const LIFE_PCT: i32 = 50;
pub const MANA_GAIN: i32 = 50;
const CHARGE_NOTE = std.fmt.comptimePrint("Uses {d} of {d} charges; kills refill {d}.", .{ USE, CHARGES, PER_KILL });

pub const Life = struct {
    pub const KIND: Kind = .life;
    pub const DESCRIPTION = std.fmt.comptimePrint("Recover {d}% of life over {d} turns. {s}", .{ LIFE_PCT, TURNS, CHARGE_NOTE });
};

pub const Mana = struct {
    pub const KIND: Kind = .mana;
    pub const DESCRIPTION = std.fmt.comptimePrint("Recover {d} mana over {d} turns. {s}", .{ MANA_GAIN, TURNS, CHARGE_NOTE });
};

pub const Flask = struct {
    charges: u8 = CHARGES,
    /// What its last drink has still to recover, and over how many turns.
    left: i32 = 0,
    turns: u8 = 0,

    pub fn full(self: Flask) bool {
        return self.charges >= USE;
    }

    /// Drunk again while recovering, it starts over on the new amount.
    pub fn drink(self: *Flask, amount: i32) void {
        std.debug.assert(self.full());
        self.charges -= USE;
        self.left = amount;
        self.turns = TURNS;
    }

    pub fn tick(self: *Flask) i32 {
        if (self.turns == 0) return 0;
        const n = std.math.divCeil(i32, self.left, self.turns) catch unreachable;
        self.left -= n;
        self.turns -= 1;
        return n;
    }

    pub fn fill(self: *Flask, n: u8) void {
        self.charges = @min(CHARGES, self.charges +| n);
    }

    /// Drinks its charges hold.
    pub fn uses(self: Flask) u8 {
        return self.charges / USE;
    }
};

pub fn lifeOf(max: i32) i32 {
    return mathx.percentOf(max, LIFE_PCT);
}

test "a flask holds three drinks, each recovering its amount whole over three turns, and kills refill it" {
    var f = Flask{};
    try std.testing.expectEqual(CHARGES / USE, f.uses());
    f.drink(lifeOf(24));
    var total: i32 = 0;
    for (0..TURNS + 2) |_| total += f.tick();
    try std.testing.expectEqual(lifeOf(24), total);
    f.drink(10);
    f.drink(10);
    try std.testing.expect(!f.full());
    for (0..USE / PER_KILL) |_| f.fill(PER_KILL);
    try std.testing.expect(f.full());
    for (0..100) |_| f.fill(PER_KILL);
    try std.testing.expectEqual(CHARGES, f.charges);
    std.debug.print("flask: {d} drinks from full, {d}% of 24 hp is {d} over {d} turns, {d} kills refill a drink\n", .{ CHARGES / USE, LIFE_PCT, total, TURNS, USE / PER_KILL });
}
