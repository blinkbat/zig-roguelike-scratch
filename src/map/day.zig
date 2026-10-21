const std = @import("std");
const mathx = @import("../core/mathx.zig");

pub const HOURS: f32 = 24;
pub const SUNRISE: f32 = 6;
pub const SUNSET: f32 = 20;
pub const NOON: f32 = 12;
/// Midway between sunrise and sunset, where the sun stands highest; not `NOON`, as the day is lopsided.
pub const SOLAR_NOON: f32 = (SUNRISE + SUNSET) / 2;
pub const DAY_SPAN: f32 = SUNSET - SUNRISE;
pub const NIGHT_SPAN: f32 = HOURS - DAY_SPAN;
pub const DEAD_OF_NIGHT: f32 = @mod(SUNSET + NIGHT_SPAN / 2, HOURS);
const PER_HOUR: u16 = 60;
const MINUTES: u16 = @as(u16, @intFromFloat(HOURS)) * PER_HOUR;
pub const TURN_MINUTES: u16 = 6;
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

pub const Arc = struct { day: bool, u: f32 };

/// Whose half of the clock it is, and how far from rising (0) to setting (1).
pub fn arc(hour: f32) Arc {
    const h = wrapHour(hour);
    if (h >= SUNRISE and h < SUNSET) return .{ .day = true, .u = (h - SUNRISE) / DAY_SPAN };
    return .{ .day = false, .u = wrapHour(h - SUNSET) / NIGHT_SPAN };
}

/// None from `TWILIGHT` past sunset to as long before sunrise, so the dead of night is as dark as underground.
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

test "the sun rides the arc by day and the moon by night, each highest midway" {
    const noon = arc(SOLAR_NOON);
    const night = arc(DEAD_OF_NIGHT);
    std.debug.print("solar noon {d:.3} of the day arc, dead of night {d:.3} of the night arc\n", .{ noon.u, night.u });
    try std.testing.expect(noon.day and !night.day);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), noon.u, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), night.u, 1e-4);
    try std.testing.expectEqual(Arc{ .day = true, .u = 0 }, arc(SUNRISE));
    try std.testing.expectEqual(Arc{ .day = false, .u = 0 }, arc(SUNSET));
    try std.testing.expect(arc(SUNRISE - 0.01).u > 0.99);
}

test "the light to see by turns from day to night in a ramp, half at each horizon" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), daylight(SUNSET), 1e-4);
    try std.testing.expectEqual(@as(f32, 1), daylight(NOON));
    try std.testing.expectEqual(@as(f32, 0), daylight(SUNSET + TWILIGHT));
    try std.testing.expectEqual(@as(f32, 0), daylight(SUNRISE - TWILIGHT));
    try std.testing.expect(daylight(SUNSET + 1) > 0);
}
