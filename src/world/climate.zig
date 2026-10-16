const std = @import("std");

// Outdoor appearance only; the simulation never reads climate.

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
