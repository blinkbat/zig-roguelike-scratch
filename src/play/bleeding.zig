const std = @import("std");
const mathx = @import("../core/mathx.zig");
const damage = @import("damage.zig");

pub const TURNS: u8 = 5;
pub const STILL: i32 = 1;
pub const MOVE_FACTOR: i32 = 2;
pub const MOVING: i32 = STILL * MOVE_FACTOR;
pub const TAKES = "starts bleeding";
pub const STATUS = std.fmt.comptimePrint("Lose {d} life per turn, or {d} when moving.", .{ STILL, MOVING });

pub const Bleed = struct {
    turns: u8 = 0,
    fresh: bool = false,
    amount: i32 = STILL,

    pub fn start(self: *Bleed) void {
        self.startWith(STILL);
    }

    pub fn startWith(self: *Bleed, amount: i32) void {
        if (self.turns == 0) {
            self.fresh = true;
            self.amount = amount;
        } else self.amount = @max(self.amount, amount);
        self.turns = TURNS;
    }

    pub fn tick(self: *Bleed, moved: bool) ?i32 {
        if (self.turns == 0) return null;
        if (self.fresh) {
            self.fresh = false;
            return null;
        }
        self.turns -= 1;
        return if (moved) self.amount * MOVE_FACTOR else self.amount;
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
    std.debug.print("bleeding: {d} damage over {d} turns standing, {d} moving every turn\n", .{ still, TURNS, moving });
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
    std.debug.print("weapon bleed: strong refresh retains 2/4 damage; expiry restores normal 1/2\n", .{});
}
