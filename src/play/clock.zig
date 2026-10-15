const std = @import("std");

/// Brogue's ticks: a turn is `TURN` of them, and an action costs its body's pace.
pub const TURN: i32 = 100;
const STUN: i32 = TURN;
pub const STUNNED = "is stunned";

/// Brogue's `ticksUntilTurn`: what a body owes before it may act. Every turn pays `TURN` off it; a turn it is still
/// owing is lost.
pub const Clock = struct {
    ticks: i32 = 0,
    /// This turn found it still owing, so it does not act.
    stalled: bool = false,

    pub fn delay(self: *Clock, ticks: i32) void {
        self.ticks += @max(0, ticks);
    }

    /// The one stun, whatever deals it: the body loses its next turn.
    pub fn stun(self: *Clock) void {
        self.delay(STUN);
    }

    pub fn pass(self: *Clock, pace: i32) void {
        self.ticks -= TURN;
        self.stalled = self.ticks >= 0;
        if (!self.stalled) self.ticks += pace;
    }
};

fn lost(c: *Clock, pace: i32, turns: usize) usize {
    var n: usize = 0;
    for (0..turns) |_| {
        c.pass(pace);
        if (c.stalled) n += 1;
    }
    return n;
}

test "a stun costs the next turn, delay costs a turn for each whole turn of ticks it adds, and a slow pace acts less" {
    var c = Clock{};
    try std.testing.expectEqual(@as(usize, 0), lost(&c, TURN, 10));
    c.stun();
    c.pass(TURN);
    try std.testing.expect(c.stalled);
    c.pass(TURN);
    try std.testing.expect(!c.stalled);
    c.delay(TURN / 2);
    try std.testing.expectEqual(@as(usize, 0), lost(&c, TURN, 10));
    c.delay(TURN / 2);
    try std.testing.expectEqual(@as(usize, 1), lost(&c, TURN, 10));
    c.delay(TURN * 3);
    try std.testing.expectEqual(@as(usize, 3), lost(&c, TURN, 10));
    var slow = Clock{};
    try std.testing.expectEqual(@as(usize, 5), lost(&slow, TURN * 2, 10));
    std.debug.print("clock: a stun loses the next turn; two half-turn delays 1, three turns' 3; a body of pace {d} loses 5 of 10\n", .{TURN * 2});
}
