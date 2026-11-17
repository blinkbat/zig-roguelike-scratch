const std = @import("std");
const damage = @import("damage.zig");

pub const AILMENT = @import("resilience.zig").Kind.bleed;
pub const TURNS: u8 = 5;
pub const STILL: i32 = 1;
pub const MOVE_FACTOR: i32 = 2;
pub const MOVING: i32 = STILL * MOVE_FACTOR;
pub const TAKES = "starts bleeding";
pub const RETAKES = "bleeds anew";
pub const STATUS = std.fmt.comptimePrint("Lose {d} life per turn, or {d} when moving.", .{ STILL, MOVING });

pub const Bleed = struct {
    turns: u8 = 0,
    fresh: bool = false,
    amount: i32 = STILL,
    move_bonus: i32 = 0,

    pub fn start(self: *Bleed) void {
        self.startWith(STILL);
    }

    /// What starting it now says: read before it starts.
    pub fn said(self: Bleed) []const u8 {
        return if (self.turns == 0) TAKES else RETAKES;
    }

    pub fn startWith(self: *Bleed, amount: i32) void {
        self.startWound(amount, 0);
    }

    pub fn startWound(self: *Bleed, amount: i32, move_bonus: i32) void {
        const fresh = damage.begin(self, TURNS);
        self.amount = if (fresh) amount else @max(self.amount, amount);
        self.move_bonus = if (fresh) move_bonus else @max(self.move_bonus, move_bonus);
    }

    pub fn tick(self: *Bleed, moved: bool) ?i32 {
        if (!damage.due(self)) return null;
        return if (moved) self.amount * MOVE_FACTOR + self.move_bonus else self.amount;
    }

    pub fn settle(self: *Bleed) void {
        self.fresh = false;
    }
};

test "bleeding begins next turn, lasts five ticks, doubles on a turn moved and refreshes without stacking" {
    var b = Bleed{};
    b.start();
    try std.testing.expectEqual(@as(?i32, null), b.tick(true));
    try std.testing.expectEqual(@as(?i32, STILL), b.tick(false));
    try std.testing.expectEqual(@as(?i32, MOVING), b.tick(true));
    b.start();
    var still: i32 = 0;
    for (0..TURNS) |_| still += b.tick(false).?;
    try std.testing.expectEqual(@as(?i32, null), b.tick(true));
    b.start();
    b.fresh = false;
    var moving: i32 = 0;
    for (0..TURNS) |_| moving += b.tick(true).?;
    try std.testing.expectEqual(STILL * TURNS, still);
    try std.testing.expectEqual(MOVING * TURNS, moving);
}

test "strong weapon bleed survives weaker refresh without postponing a tick" {
    var b = Bleed{};
    b.startWith(2);
    b.settle();
    b.start();
    try std.testing.expectEqual(@as(?i32, 4), b.tick(true));
    for (0..TURNS - 1) |_| _ = b.tick(false);
    b.start();
    b.settle();
    try std.testing.expectEqual(@as(?i32, STILL), b.tick(false));
}

test "grievous wounds retain their movement bonus on refresh and reset after expiry" {
    var b = Bleed{};
    b.startWound(2, 1);
    b.settle();
    try std.testing.expectEqual(@as(?i32, 2), b.tick(false));
    try std.testing.expectEqual(@as(?i32, 5), b.tick(true));
    b.start();
    try std.testing.expectEqual(@as(?i32, 5), b.tick(true));
    for (0..TURNS - 1) |_| _ = b.tick(false);
    b.start();
    b.settle();
    try std.testing.expectEqual(@as(?i32, MOVING), b.tick(true));
}
