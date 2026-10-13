const std = @import("std");

// A procgen node's sky: how its daylight looks and what falls from it. Only a node open to the sky shows either, and
// nothing in the simulation reads them: `gfx/sky.zig` turns `Light` into the sky's colours, `gfx/weather.zig` draws `Weather`.

/// How the day's light looks under this sky.
pub const Light = enum {
    /// The day as `gfx/sky.zig` keys it.
    clear,
    /// Overcast: a weaker, greyer sun and a dimmer, colder sky.
    bleak,
};

/// What falls from this sky.
pub const Weather = enum {
    clear,
    /// A very soft rain: few faint streaks.
    drizzle,
};

pub const Climate = struct {
    light: Light = .clear,
    weather: Weather = .clear,
};

test "a sky left alone is the clear day it always was" {
    const c = Climate{};
    try std.testing.expectEqual(Light.clear, c.light);
    try std.testing.expectEqual(Weather.clear, c.weather);
    try std.testing.expectEqual(@as(usize, 2), std.meta.fields(Climate).len);
}
