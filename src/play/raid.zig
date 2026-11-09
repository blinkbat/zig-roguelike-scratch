const std = @import("std");
const grid = @import("../map/grid.zig");
const day = @import("../map/day.zig");
const actor = @import("actor.zig");

pub const RAIDER: actor.Kind = .goblin;
pub const RAIDERS_MAX: u8 = 8;
pub const XP_DIVISOR: u32 = 3;
const DUSK: u64 = @intFromFloat(day.SUNSET * 60);
const NIGHT: u64 = @intFromFloat(day.NIGHT_SPAN * 60);
const SALT: u64 = 0x4A1D;

comptime {
    std.debug.assert(RAIDER.stocked() and DUSK + NIGHT > day.MINUTES and NIGHT < day.MINUTES);
}

/// The raiders that come in through one of a procgen node's doors each night, each at its own time between dusk and dawn.
pub const Raid = struct {
    raiders: u8 = 0,
    raid_door: u8 = 0,

    pub fn fit(r: Raid) Raid {
        return .{ .raiders = @min(r.raiders, RAIDERS_MAX), .raid_door = @min(r.raid_door, grid.MAX_DOORS - 1) };
    }
};

/// How many raiders come in after the minute `from` up to and including `to`, both counted since the first day began.
pub fn arriving(r: Raid, roll: u64, from: u64, to: u64) usize {
    if (to <= from) return 0;
    var n: usize = 0;
    var night = (from -| DUSK -| NIGHT) / day.MINUTES;
    while (night * day.MINUTES + DUSK <= to) : (night += 1) {
        for (0..r.fit().raiders) |i| {
            const at = arrival(roll, night, i);
            n += @intFromBool(at > from and at <= to);
        }
    }
    return n;
}

/// The minute raider `i` of night `night` comes in, since the first day began.
fn arrival(roll: u64, night: u64, i: usize) u64 {
    const key = [3]u64{ SALT, night, i };
    return night * day.MINUTES + DUSK + std.hash.Wyhash.hash(roll, std.mem.asBytes(&key)) % NIGHT;
}

test "each night's raiders all come between dusk and dawn, at times of their own, and none by day" {
    const r = Raid{ .raiders = 3 };
    const NIGHTS: u64 = 50;
    const end = NIGHTS * day.MINUTES + DUSK - 1;
    var by_turn: usize = 0;
    var by_day: usize = 0;
    var turns_with: usize = 0;
    var t: u64 = 0;
    while (t < end) : (t += day.TURN_MINUTES) {
        const came = arriving(r, 0x5EED, t, @min(end, t + day.TURN_MINUTES));
        by_turn += came;
        turns_with += @intFromBool(came > 0);
        const hour = @as(f32, @floatFromInt((t + day.TURN_MINUTES) % day.MINUTES)) / 60;
        if (hour > day.SUNRISE and hour <= day.SUNSET) by_day += came;
    }
    const whole = arriving(r, 0x5EED, 0, end);
    std.debug.print("{d} nights of 3 raiders: {d} came a turn at a time over {d} turns, {d} counted whole, {d} by day\n", .{ NIGHTS, by_turn, turns_with, whole, by_day });
    try std.testing.expectEqual(@as(usize, 3 * NIGHTS), whole);
    try std.testing.expectEqual(whole, by_turn);
    try std.testing.expectEqual(@as(usize, 0), by_day);
    try std.testing.expect(turns_with * 10 >= whole * 9);
    try std.testing.expectEqual(@as(usize, 0), arriving(.{}, 0x5EED, 0, end));
}
