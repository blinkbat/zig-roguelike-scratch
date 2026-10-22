const std = @import("std");
const mathx = @import("../core/mathx.zig");

/// Brogue's ticks: a turn is `TURN` of them, and an action costs its body's pace.
pub const TURN: i32 = 100;
const STUN: i32 = TURN;
pub const STUNNED = "is stunned";

/// A stunning skill's chance, as its description says it.
pub fn stunNote(comptime pc: u32) []const u8 {
    return std.fmt.comptimePrint("{d}% chance to stun", .{pc});
}

/// Brogue's `ticksUntilTurn`: each turn pays `TURN`; a body still owing ticks loses its action.
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

    pub fn stunBeforeAction(self: *Clock, pace: i32) void {
        self.stun();
        if (self.stalled) return;
        self.ticks -= pace;
        self.stalled = true;
    }

    /// Still paying for a stun: the hero, who keeps no pace, loses a turn to each one.
    pub fn owes(self: Clock) bool {
        return self.ticks > 0;
    }

    pub fn pass(self: *Clock, pace: i32) void {
        self.ticks -= TURN;
        self.stalled = self.ticks >= 0;
        if (!self.stalled) self.ticks += pace;
    }
};

/// A skill's `afflict` that stuns.
pub fn stuns(a: anytype, _: *mathx.Rng) void {
    a.clock.stun();
}

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

test "stunning a pending action cancels its prepaid pace without double-paying an existing stall" {
    for ([_]i32{ TURN, TURN * 2, TURN * 3 }) |pace| {
        var c = Clock{};
        c.pass(pace);
        try std.testing.expect(!c.stalled);
        c.stunBeforeAction(pace);
        try std.testing.expect(c.stalled);
        try std.testing.expectEqual(@as(i32, 0), c.ticks);
        c.pass(pace);
        try std.testing.expect(!c.stalled);
        try std.testing.expectEqual(pace - TURN, c.ticks);

        c = .{ .ticks = TURN * 2 };
        c.pass(pace);
        try std.testing.expect(c.stalled);
        c.stunBeforeAction(pace);
        try std.testing.expectEqual(TURN * 2, c.ticks);
        try std.testing.expectEqual(@as(usize, 2), lost(&c, pace, 2));
        c.pass(pace);
        try std.testing.expect(!c.stalled);
    }
    std.debug.print("pending-action stun: 3 paces cancel one action each; existing stalls retain their remaining debt\n", .{});
}
