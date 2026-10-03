const std = @import("std");
const mathx = @import("../core/mathx.zig");

// The hour, simulation: a turn moves it on, a run saves it, and the sky (`gfx/sky.zig`) is drawn from it.

pub const HOURS: f32 = 24;
pub const SUNRISE: f32 = 6;
pub const SUNSET: f32 = 20;
const PER_HOUR: u16 = 60;
const MINUTES: u16 = @as(u16, @intFromFloat(HOURS)) * PER_HOUR;
/// Game minutes a turn takes: a day is `MINUTES / TURN_MINUTES` turns.
pub const TURN_MINUTES: u16 = 6;
/// A run starts at half past eight, a whole day ahead of it.
pub const START_MINUTE: u16 = 8 * PER_HOUR + 30;

comptime {
    std.debug.assert(MINUTES % TURN_MINUTES == 0 and START_MINUTE < MINUTES);
}

/// Whole minutes into the day, so no turn's worth is ever lost to rounding.
pub const Clock = struct {
    minute: u16 = START_MINUTE,

    pub fn turn(c: *Clock) void {
        c.minute = (c.minute + TURN_MINUTES) % MINUTES;
    }

    pub fn hour(c: Clock) f32 {
        return @as(f32, @floatFromInt(c.minute)) / PER_HOUR;
    }

    pub fn at(h: f32) Clock {
        return .{ .minute = @intFromFloat(@mod(@round(wrapHour(h) * PER_HOUR), @as(f32, @floatFromInt(MINUTES)))) };
    }
};

pub fn wrapHour(h: f32) f32 {
    if (!std.math.isFinite(h)) return (Clock{}).hour();
    const r = @rem(h, HOURS);
    return if (r < 0) r + HOURS else r;
}

/// From `from` to `to` the short way round the clock, hours: negative going back.
pub fn toward(from: f32, to: f32) f32 {
    const d = wrapHour(to - from);
    return if (d > HOURS / 2) d - HOURS else d;
}

/// How much of the sky's light there is to see by: all of it by day, none from an hour and a half past sunset to as
/// long before sunrise, so the dead of night is as dark as underground.
pub fn daylight(hour: f32) f32 {
    return mathx.smoothstep(-TWILIGHT, TWILIGHT, sunUp(hour));
}

/// Hours either side of the horizon over which the sky's light to see by comes and goes.
const TWILIGHT: f32 = 1.5;

/// Hours since sunrise or until sunset, whichever is nearer; negative at night.
fn sunUp(hour: f32) f32 {
    const h = wrapHour(hour);
    return if (h < SUNRISE) h - SUNRISE else if (h > SUNSET) SUNSET - h else @min(h - SUNRISE, SUNSET - h);
}

test "a turn moves the clock on, a day is 240 turns, and it comes round to where it began" {
    var c = Clock{};
    const turns = MINUTES / TURN_MINUTES;
    for (0..turns) |_| c.turn();
    std.debug.print("a day is {d} turns\n", .{turns});
    try std.testing.expectEqual(START_MINUTE, c.minute);
    c = Clock.at(23.99);
    c.turn();
    try std.testing.expect(c.hour() < @as(f32, @floatFromInt(TURN_MINUTES)) / PER_HOUR);
    try std.testing.expectApproxEqAbs(@as(f32, -0.5), toward(0.25, 23.75), 1e-4);
}

test "the light to see by turns from day to night in a ramp, half at each horizon" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), daylight(SUNSET), 1e-4);
    try std.testing.expectEqual(@as(f32, 1), daylight(12));
    try std.testing.expectEqual(@as(f32, 0), daylight(SUNSET + TWILIGHT));
    try std.testing.expectEqual(@as(f32, 0), daylight(SUNRISE - TWILIGHT));
    try std.testing.expect(daylight(SUNSET + 1) > 0);
}
