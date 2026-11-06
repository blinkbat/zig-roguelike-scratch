const std = @import("std");
const mathx = @import("../core/mathx.zig");
const day = @import("day.zig");

// Outdoor weather, a pure function of the profile, run seed and minutes; only its rain reaches the rules (`terrain.rained`, `fire.damped`).

/// How the day's light looks under this sky.
pub const Light = enum {
    /// The day as `gfx/sky.zig` keys it.
    clear,
    /// Overcast: a weaker, greyer sun and a dimmer, colder sky.
    bleak,

    /// The least overcast this light keeps under any weather.
    pub fn overcast(l: Light) f32 {
        return switch (l) {
            .clear => 0,
            .bleak => 1,
        };
    }
};

/// The weather profile over this sky.
pub const Weather = enum {
    clear,
    /// A very soft rain that never lets up.
    drizzle,
    /// A grey sea coast: squalls blow in and out, and sea fog comes on in the lulls.
    coastal,
    /// Thunderstorms build, break and clear, lightning in the worst of them.
    stormy,
    /// Long spells of fog, now and then a little rain.
    misty,
};

/// The slow tides every profile reads its layers from: how foul the sky runs, and how thick the air hangs.
pub const Drive = enum { storm, haze };

/// Each spell of a drive rolls afresh, holds, then eases into the next.
pub const Cycle = struct {
    /// Game minutes a spell lasts.
    spell: u16 = 240,
    /// Rolls raised to this: below 1 the drive runs high more often, above 1 low.
    lean: f32 = 1,
};

/// A layer's strength: `least` while its drive is at or below `from`, rising to `most` at the drive's top.
pub const Span = struct {
    on: Drive = .storm,
    least: f32 = 0,
    most: f32 = 0,
    from: f32 = 0,

    fn at(s: Span, d: std.EnumArray(Drive, f32)) f32 {
        const v = d.get(s.on);
        const k = if (v <= s.from) 0 else (v - s.from) / (1 - s.from);
        return mathx.lerpF(s.least, s.most, k);
    }
};

pub const Layer = enum { overcast, rain, mist, lightning };

/// What each layer is at a moment, 0 none to 1 its heaviest.
pub const Now = std.EnumArray(Layer, f32);

pub const Profile = struct {
    cycle: std.EnumArray(Drive, Cycle) = .initFill(.{}),
    layer: std.EnumArray(Layer, Span) = .initFill(.{}),
};

/// The drizzle's rain, all day long.
pub const DRIZZLE: f32 = 0.19;

pub const PROFILES = std.EnumArray(Weather, Profile).init(.{
    .clear = .{},
    .drizzle = .{ .layer = .init(.{
        .overcast = .{},
        .rain = .{ .least = DRIZZLE, .most = DRIZZLE },
        .mist = .{},
        .lightning = .{},
    }) },
    .coastal = .{
        .cycle = .init(.{ .storm = .{ .spell = 180 }, .haze = .{ .spell = 180, .lean = 1.3 } }),
        .layer = .init(.{
            .overcast = .{ .least = 0.4, .most = 1 },
            .rain = .{ .most = 0.75, .from = 0.4 },
            .mist = .{ .on = .haze, .least = 0.1, .most = 0.8, .from = 0.3 },
            .lightning = .{ .most = 0.2, .from = 0.85 },
        }),
    },
    .stormy = .{
        .cycle = .init(.{ .storm = .{ .spell = 240 }, .haze = .{} }),
        .layer = .init(.{
            .overcast = .{ .least = 0.2, .most = 1 },
            .rain = .{ .most = 1, .from = 0.45 },
            .mist = .{ .on = .haze, .most = 0.3, .from = 0.6 },
            .lightning = .{ .most = 1, .from = 0.65 },
        }),
    },
    .misty = .{
        .cycle = .init(.{ .storm = .{ .spell = 300, .lean = 1.5 }, .haze = .{ .spell = 360, .lean = 0.6 } }),
        .layer = .init(.{
            .overcast = .{ .least = 0.2, .most = 0.6 },
            .rain = .{ .most = 0.25, .from = 0.75 },
            .mist = .{ .on = .haze, .least = 0.4, .most = 1 },
            .lightning = .{},
        }),
    },
});

pub const Climate = struct {
    light: Light = .clear,
    weather: Weather = .clear,

    /// Its weather `minutes` into the run whose seed is `seed`; every node shares the drives, each reading them by its own profile.
    pub fn now(c: Climate, seed: u64, minutes: u64) Now {
        const p = PROFILES.get(c.weather);
        var d = std.EnumArray(Drive, f32).initUndefined();
        for (std.enums.values(Drive)) |k| d.set(k, drive(seed, k, p.cycle.get(k), minutes));
        var n = Now.initUndefined();
        for (std.enums.values(Layer)) |l| n.set(l, p.layer.get(l).at(d));
        n.set(.overcast, @max(n.get(.overcast), c.light.overcast()));
        return n;
    }
};

/// Of a spell, the share at its end over which it eases into the next.
const EASE_SHARE: f32 = 0.6;

fn drive(seed: u64, k: Drive, c: Cycle, minutes: u64) f32 {
    const spell: u64 = @max(c.spell, 1);
    const n = minutes / spell;
    const t = @as(f32, @floatFromInt(minutes % spell)) / @as(f32, @floatFromInt(spell));
    return mathx.lerpF(roll(seed, k, c, n), roll(seed, k, c, n + 1), mathx.smoothstep(1 - EASE_SHARE, 1, t));
}

fn roll(seed: u64, k: Drive, c: Cycle, n: u64) f32 {
    var h = std.hash.Wyhash.init(seed);
    h.update(std.mem.asBytes(&@intFromEnum(k)));
    h.update(std.mem.asBytes(&n));
    const u = mathx.unitOf(h.final());
    return std.math.pow(f32, u, c.lean);
}

pub fn eased(from: Now, to: Now, k: f32) Now {
    var n = from;
    for (std.enums.values(Layer)) |l| n.set(l, mathx.lerpF(from.get(l), to.get(l), k));
    return n;
}

test "a sky left alone is the clear day it always was" {
    const c = Climate{};
    try std.testing.expectEqual(Light.clear, c.light);
    try std.testing.expectEqual(Weather.clear, c.weather);
    for (0..200) |m| {
        for (c.now(7, m * 37).values) |v| try std.testing.expectEqual(@as(f32, 0), v);
    }
}

test "a profile's weather holds, changes by spells, keeps each layer in its span, and is the same for the same seed and time" {
    const days = 30;
    const step = day.TURN_MINUTES;
    for (std.enums.values(Weather)) |w| {
        const c = Climate{ .weather = w };
        const p = PROFILES.get(w);
        var shown = std.EnumArray(Layer, f32).initFill(0);
        var wet: usize = 0;
        var most_turn: f32 = 0;
        var before = c.now(42, 0);
        var m: u64 = step;
        while (m < days * day.MINUTES) : (m += step) {
            const n = c.now(42, m);
            try std.testing.expectEqual(n, c.now(42, m));
            for (std.enums.values(Layer)) |l| {
                const s = p.layer.get(l);
                try std.testing.expect(n.get(l) >= s.least - 1e-5 and n.get(l) <= s.most + 1e-5);
                shown.set(l, @max(shown.get(l), n.get(l)));
                most_turn = @max(most_turn, @abs(n.get(l) - before.get(l)));
            }
            if (n.get(.rain) > 0) wet += 1;
            before = n;
        }
        const turns: f32 = @floatFromInt(days * day.MINUTES / step);
        std.debug.print("{s} over {d} days: raining {d:.0}% of turns; heaviest rain {d:.2}, mist {d:.2}, lightning {d:.2}; at most {d:.3} of a layer a turn\n", .{ @tagName(w), days, @as(f32, @floatFromInt(wet)) / turns * 100, shown.get(.rain), shown.get(.mist), shown.get(.lightning), most_turn });
        try std.testing.expect(most_turn < 0.2);
    }
    const coast = Climate{ .weather = .coastal };
    try std.testing.expect(!std.meta.eql(coast.now(1, 600), coast.now(2, 600)));
    const bleak = Climate{ .light = .bleak, .weather = .coastal };
    try std.testing.expectEqual(@as(f32, 1), bleak.now(1, 600).get(.overcast));
}
