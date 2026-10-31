const std = @import("std");
const mathx = @import("../core/mathx.zig");
const damage = @import("damage.zig");
const resilience = @import("resilience.zig");

pub const COST: i32 = 6;
pub const AILMENT = resilience.Kind.pin;
pub const TURNS_LO: u8 = 2;
pub const TURNS_HI: u8 = 4;
pub const VERB = "pins";
pub const TAKES = "is pinned";
pub const SLIP: u32 = 30;
pub const STATUS = std.fmt.comptimePrint("Cannot move. Can still attack. Each struggle has a {d}% chance to break free.", .{SLIP});
pub const DESCRIPTION = std.fmt.comptimePrint("Arrow damage. Pins for {d}-{d} turns.", .{ TURNS_LO, TURNS_HI });

/// Its turns left held to its cell.
pub const Pin = struct {
    turns: u8 = 0,

    /// One of its turns: whether it is held this turn.
    pub fn hold(self: *Pin) bool {
        return resilience.wearTurn(&self.turns);
    }

    /// Pinned again, it is held for the longer of the two.
    pub fn extend(self: *Pin, turns: u8) void {
        resilience.lengthen(&self.turns, turns);
    }

    /// A struggle against it: whether this turn is its last.
    pub fn struggle(self: *Pin, rng: *mathx.Rng) bool {
        if (!rng.percent(SLIP)) return false;
        self.turns = @min(self.turns, 1);
        return true;
    }
};

pub const CHANCE: u32 = mathx.PERCENT;
pub const procs = damage.chance(CHANCE);
pub const chance = damage.flat(CHANCE);

pub fn afflict(a: anytype, rng: *mathx.Rng) void {
    a.pin.extend(@intCast(rng.range(TURNS_LO, TURNS_HI)));
}

test "a pin holds for two to four turns, and a second never shortens the first" {
    var rng = mathx.Rng.init(0x919);
    var seen = [_]bool{false} ** (TURNS_HI + 1);
    for (0..300) |_| {
        var a: struct { pin: Pin = .{} } = .{};
        afflict(&a, &rng);
        seen[a.pin.turns] = true;
        var held: u8 = 0;
        while (a.pin.hold()) held += 1;
        try std.testing.expect(held >= TURNS_LO and held <= TURNS_HI);
    }
    for (TURNS_LO..TURNS_HI + 1) |t| try std.testing.expect(seen[t]);
    var a: struct { pin: Pin = .{ .turns = 9 } } = .{};
    afflict(&a, &rng);
    try std.testing.expectEqual(@as(u8, 9), a.pin.turns);
    std.debug.print("pinning shot: every length {d}-{d} rolled in 300 pins; a re-pin keeps the longer\n", .{ TURNS_LO, TURNS_HI });
}

test "a struggle sometimes makes this turn the pin's last" {
    var rng = mathx.Rng.init(0x51);
    var freed: u32 = 0;
    for (0..1000) |_| {
        var p = Pin{ .turns = 4 };
        if (p.struggle(&rng)) {
            freed += 1;
            try std.testing.expect(p.hold() and !p.hold());
        } else try std.testing.expectEqual(@as(u8, 4), p.turns);
    }
    try std.testing.expect(freed > 250 and freed < 350);
    std.debug.print("pin struggle: {d} of 1000 broke free at {d}%\n", .{ freed, SLIP });
}
