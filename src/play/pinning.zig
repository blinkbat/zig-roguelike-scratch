const std = @import("std");
const mathx = @import("../core/mathx.zig");
const damage = @import("damage.zig");

pub const COST: i32 = 30;
pub const TURNS_LO: u8 = 2;
pub const TURNS_HI: u8 = 4;
pub const VERB = "pins";
pub const TAKES = "is pinned";
pub const DESCRIPTION = std.fmt.comptimePrint("Arrow damage. A target it leaves alive is pinned for {d}-{d} turns: it cannot move, but strikes what stands beside it.", .{ TURNS_LO, TURNS_HI });

/// Its turns left held to its cell.
pub const Pin = struct {
    turns: u8 = 0,

    /// One of its turns: whether it is held this turn.
    pub fn hold(self: *Pin) bool {
        if (self.turns == 0) return false;
        self.turns -= 1;
        return true;
    }
};

pub const procs = damage.always;

/// Pinned again, it is held for the longer of the two.
pub fn afflict(a: anytype, rng: *mathx.Rng) void {
    a.pin.turns = @max(a.pin.turns, @as(u8, @intCast(rng.range(TURNS_LO, TURNS_HI))));
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
