const std = @import("std");
const mathx = @import("../core/mathx.zig");
const day = @import("../map/day.zig");

// Directions point toward light: x east, y south (screen-down), z up.

pub const Rgb = @Vector(3, f32);

pub fn mix(a: Rgb, b: Rgb, k: f32) Rgb {
    return a + (b - a) * splat(k);
}

pub fn splat(k: f32) Rgb {
    return @splat(k);
}

pub fn norm(v: Rgb) f32 {
    return @sqrt(@reduce(.Add, v * v));
}

pub fn unit(v: Rgb) Rgb {
    return v / splat(norm(v));
}

fn flatOf(d: [3]f32) f32 {
    return mathx.len(d[0], d[1]);
}

const HOURS = day.HOURS;
const SUNRISE = day.SUNRISE;
const SUNSET = day.SUNSET;
const wrapHour = day.wrapHour;
/// Bearings clockwise from north.
const AZ_RISE: f32 = 100;
const AZ_SET: f32 = 262;
const SUN_ALT_MAX: f32 = 60;
const KEY_ALT_MIN = std.math.degreesToRadians(@as(f32, 35));
const KEY_ALT_MAX = std.math.degreesToRadians(@as(f32, 42));
pub const REACH_MAX: f32 = 1 / @tan(KEY_ALT_MIN);
const KEY_SWAP_LEAD: f32 = 1.0;
const KEY_SWAP_LAG: f32 = 0.8;
const KEY_SWAP_DAWN: f32 = SUNRISE - KEY_SWAP_LEAD;
const KEY_SWAP_DUSK: f32 = SUNSET + KEY_SWAP_LAG;
const GLOW_HOURS: f32 = 2.5;
const FULL_MORNING: f32 = SUNRISE + GLOW_HOURS;
const LATE_DAY: f32 = SUNSET - 2.55;
const DUSK_GLOW: f32 = SUNSET - 0.6;
const KEY_SWAP_FADE: f32 = 0.45;
const OVERHEAD: f32 = 1e-4;
/// The palette's sky is a hemisphere's; seen from above it lights the ground in shade this many times over.
const SKY_GAIN: f32 = 1.6;
/// The palette's key is a 3D scene's; on art drawn flat it is this strong.
const KEY_GAIN: f32 = 0.85;
const NIGHT_FILL_MIN: f32 = 0.72;
const NIGHT_FILL_SPREAD: f32 = 0.4;
const MOON_LIFT: f32 = 0.7;
const NORTH_SOUTH: f32 = 0.35;

comptime {
    std.debug.assert(KEY_SWAP_DAWN < SUNRISE and KEY_SWAP_DUSK > SUNSET);
}

/// 0 to 1 across the day, then 1 to 2 across the night, measured on from sunset through midnight.
fn dayU(hour: f32) f32 {
    const a = day.arc(hour);
    return if (a.day) a.u else 1 + a.u;
}

fn moonShare(hour: f32) f32 {
    const h = wrapHour(hour);
    if (h > SUNSET) return mathx.smoothstep(KEY_SWAP_DUSK - KEY_SWAP_FADE, KEY_SWAP_DUSK + KEY_SWAP_FADE, h);
    if (h < SUNRISE) return 1 - mathx.smoothstep(KEY_SWAP_DAWN - KEY_SWAP_FADE, KEY_SWAP_DAWN + KEY_SWAP_FADE, h);
    return 0;
}

fn dirFrom(az_deg: f32, alt_deg: f32) [3]f32 {
    const az = std.math.degreesToRadians(az_deg);
    const alt = std.math.degreesToRadians(alt_deg);
    const c = @cos(alt);
    return .{ @sin(az) * c, -@cos(az) * c, @sin(alt) };
}

fn sunDir(hour: f32) [3]f32 {
    const u = dayU(hour);
    const alt = SUN_ALT_MAX * @sin(std.math.pi * u);
    const az = if (u <= 1) mathx.lerpF(AZ_RISE, AZ_SET, u) else AZ_SET + (360 - (AZ_SET - AZ_RISE)) * (u - 1);
    return dirFrom(az, alt);
}

fn keyDir(hour: f32) [3]f32 {
    const s = sunDir(hour);
    const flat = flatOf(s);
    const h = [2]f32{ s[0] / flat, s[1] / flat };
    const sun_alt = std.math.asin(std.math.clamp(s[2], -1, 1));
    const tip_sun = 1 / @tan(@max(sun_alt, KEY_ALT_MIN));
    const tip_moon = -1 / @tan(@max(-sun_alt, KEY_ALT_MIN));
    const elev = std.math.atan2(1.0, mathx.lerpF(tip_sun, tip_moon, moonShare(hour)));
    const c = @cos(elev);
    return .{ h[0] * c, h[1] * c, @sin(elev) };
}

fn keyDim(hour: f32) f32 {
    const k = 1 - 2 * moonShare(hour);
    return k * k;
}

const Palette = struct { key: Rgb, sky: Rgb };
const Key = struct { at: f32, key: Rgb, sky: Rgb };

const NIGHT = Palette{ .key = .{ 0.012, 0.024, 0.068 }, .sky = .{ 0.005, 0.012, 0.034 } };
const DEEPEST_NIGHT = Palette{ .key = .{ 0.002, 0.004, 0.013 }, .sky = .{ 0.001, 0.003, 0.008 } };

/// Equal endpoints at the middle of the night avoid a seam.
const KEYS = [_]Key{
    .{ .at = day.DEAD_OF_NIGHT, .key = DEEPEST_NIGHT.key, .sky = DEEPEST_NIGHT.sky },
    .{ .at = SUNRISE - GLOW_HOURS, .key = NIGHT.key, .sky = NIGHT.sky },
    .{ .at = KEY_SWAP_DAWN, .key = .{ 0.104, 0.096, 0.168 }, .sky = .{ 0.054, 0.052, 0.090 } },
    .{ .at = SUNRISE, .key = .{ 1.040, 0.700, 0.640 }, .sky = .{ 0.144, 0.126, 0.172 } },
    .{ .at = FULL_MORNING, .key = .{ 1.300, 1.070, 0.800 }, .sky = .{ 0.196, 0.208, 0.250 } },
    .{ .at = day.NOON, .key = .{ 1.380, 1.250, 1.040 }, .sky = .{ 0.220, 0.230, 0.260 } },
    .{ .at = LATE_DAY, .key = .{ 1.320, 1.100, 0.800 }, .sky = .{ 0.168, 0.188, 0.244 } },
    .{ .at = DUSK_GLOW, .key = .{ 1.120, 0.720, 0.620 }, .sky = .{ 0.152, 0.130, 0.182 } },
    .{ .at = KEY_SWAP_DUSK, .key = .{ 0.144, 0.132, 0.226 }, .sky = .{ 0.064, 0.060, 0.104 } },
    .{ .at = SUNSET + GLOW_HOURS, .key = NIGHT.key, .sky = NIGHT.sky },
    .{ .at = HOURS + day.DEAD_OF_NIGHT, .key = DEEPEST_NIGHT.key, .sky = DEEPEST_NIGHT.sky },
};

comptime {
    std.debug.assert(KEYS[0].at == day.DEAD_OF_NIGHT and KEYS[KEYS.len - 1].at == HOURS + day.DEAD_OF_NIGHT);
    for (KEYS[1..], 0..) |k, i| std.debug.assert(k.at > KEYS[i].at);
}

fn paletteAt(hour: f32) Palette {
    const wrapped = wrapHour(hour);
    const h = if (wrapped < KEYS[0].at) wrapped + HOURS else wrapped;
    var i: usize = 0;
    while (i + 2 < KEYS.len and KEYS[i + 1].at <= h) i += 1;
    const a = KEYS[i];
    const b = KEYS[i + 1];
    const t = mathx.smoothstep(a.at, b.at, h);
    return .{ .key = mix(a.key, b.key, t), .sky = mix(a.sky, b.sky, t) };
}

pub const Sky = struct {
    /// Toward the light that casts.
    dir: [3]f32,
    key: Rgb,
    ambient: Rgb,
    carry: f32,
    moon: f32,
    daylight: f32,

    pub fn struck(s: Sky, f: f32) Sky {
        var lit_up = s;
        lit_up.ambient += LIGHTNING * splat(std.math.clamp(f, 0, 1));
        return lit_up;
    }

    pub fn sun(s: Sky) f32 {
        return 1 - s.moon;
    }

    pub fn flat(s: Sky) f32 {
        return flatOf(s.dir);
    }

    /// Along the ground toward it, a unit vector; south when it stands straight up.
    pub fn across(s: Sky) [2]f32 {
        const f = s.flat();
        return if (upright(f)) .{ 0, 1 } else .{ s.dir[0] / f, s.dir[1] / f };
    }

    pub fn reach(s: Sky) f32 {
        return s.flat() / @max(s.dir[2], 1e-3);
    }

    pub fn rise(s: Sky) f32 {
        return s.dir[2] / @max(s.flat(), OVERHEAD);
    }
};

pub fn upright(flat: f32) bool {
    return flat < OVERHEAD;
}

const Look = struct { key: f32 = 1, sky: f32 = 1, grey: f32 = 0, tint: Rgb = splat(1) };

const CLEAR = Look{};
const OVERCAST = Look{ .key = 0.3, .sky = 1.75, .grey = 0.55, .tint = .{ 0.92, 0.98, 1.06 } };
const LIGHTNING = Rgb{ 0.62, 0.68, 0.85 };

fn lookAt(overcast: f32) Look {
    const k = std.math.clamp(overcast, 0, 1);
    var l: Look = undefined;
    inline for (std.meta.fields(Look)) |field| @field(l, field.name) = if (field.type == Rgb) mix(@field(CLEAR, field.name), @field(OVERCAST, field.name), k) else mathx.lerpF(@field(CLEAR, field.name), @field(OVERCAST, field.name), k);
    return l;
}

/// Rec. 709's weights of red, green and blue in what the eye reads as brightness.
pub const LUMA = [3]f32{ 0.2126, 0.7152, 0.0722 };

pub fn luma(c: Rgb) f32 {
    return c[0] * LUMA[0] + c[1] * LUMA[1] + c[2] * LUMA[2];
}

fn looked(c: Rgb, strength: f32, l: Look) Rgb {
    return mix(c, splat(luma(c)), l.grey) * l.tint * splat(strength);
}

fn lit(s: Sky) f32 {
    return luma(s.ambient) + luma(s.key) * s.dir[2];
}

pub fn brightness(s: Sky) f32 {
    return lit(s) / lit(at(day.NOON));
}

pub fn at(hour: f32) Sky {
    return under(hour, 0);
}

pub fn under(hour: f32, overcast: f32) Sky {
    const p = paletteAt(hour);
    const l = lookAt(overcast);
    const dir = acrossScreen(keyDir(hour));
    const moon = moonShare(hour);
    const gain = mathx.lerpF(1, MOON_LIFT / dir[2], moon);
    const night_fill = mathx.lerpF(NIGHT_FILL_MIN, 1, mathx.smoothstep(0, day.NIGHT_SPAN * NIGHT_FILL_SPREAD, @abs(day.toward(day.DEAD_OF_NIGHT, hour))));
    const daylight = day.daylight(hour);
    return .{
        .dir = dir,
        .key = looked(p.key, keyDim(hour) * KEY_GAIN * l.key * gain, l),
        .ambient = looked(p.sky, SKY_GAIN * l.sky, l),
        .carry = (1 - daylight) * night_fill,
        .moon = moon,
        .daylight = daylight,
    };
}

fn acrossScreen(d: [3]f32) [3]f32 {
    var x = d[0];
    var y = d[1] * NORTH_SOUTH;
    const flat = mathx.len(x, y);
    const least = d[2] / @tan(KEY_ALT_MAX);
    if (!upright(flat) and flat < least) {
        x *= least / flat;
        y *= least / flat;
    }
    return unit(.{ x, y, d[2] });
}

test "a full overcast is a little darker than a clear sky, greyer, and its shadows softer" {
    const spread = struct {
        fn f(c: Rgb) f32 {
            return @reduce(.Max, c) - @reduce(.Min, c);
        }
    }.f;
    for ([_]f32{ FULL_MORNING, day.NOON, LATE_DAY }) |h| {
        const clear = under(h, 0);
        const bleak = under(h, 1);
        const lit_clear = lit(clear);
        const lit_bleak = lit(bleak);
        const share_clear = luma(clear.key) / (luma(clear.key) + luma(clear.ambient));
        const share_bleak = luma(bleak.key) / (luma(bleak.key) + luma(bleak.ambient));
        try std.testing.expect(lit_bleak > lit_clear * 0.6 and lit_bleak < lit_clear * 0.9);
        try std.testing.expect(share_bleak < share_clear * 0.6);
        try std.testing.expect(spread(bleak.key) / luma(bleak.key) < spread(clear.key) / luma(clear.key));
    }
    try std.testing.expectEqual(at(day.NOON), under(day.NOON, 0));
    const half = lit(under(day.NOON, 0.5));
    try std.testing.expect(half < lit(at(day.NOON)) and half > lit(under(day.NOON, 1)));
}

test "a lightning flash lights the dead of night as bright as a grey day, and none leaves the sky as it was" {
    const night = at(day.DEAD_OF_NIGHT);
    try std.testing.expectEqual(night, night.struck(0));
    const lit_up = brightness(night.struck(1));
    try std.testing.expect(lit_up > 0.5 and lit_up < 1);
}

test "a noon shadow reaches beyond a cell-tall sprite" {
    const reach = at(day.NOON).reach();
    try std.testing.expect(reach > 1.05 and reach < 1.3);
}

test "every overcast is darkest halfway through the night, blue at night and warmer by day" {
    const middle = day.DEAD_OF_NIGHT;
    try std.testing.expectApproxEqAbs(day.toward(SUNSET, middle), day.toward(middle, SUNRISE), 1e-5);
    for ([_]f32{ 0, 0.5, 1 }) |profile| {
        const darkest = lit(under(middle, profile));
        for (0..day.MINUTES) |minute| {
            const hour = @as(f32, @floatFromInt(minute)) / day.MINUTES * day.HOURS;
            try std.testing.expect(lit(under(hour, profile)) >= darkest - 1e-6);
        }
        const night = under(middle, profile);
        const noon = under(day.NOON, profile);
        try std.testing.expect(night.key[2] > night.key[0] * 2);
        try std.testing.expect(night.ambient[2] > night.ambient[0] * 2);
        try std.testing.expectEqual(NIGHT_FILL_MIN, night.carry);
        try std.testing.expect(under(middle - 3, profile).carry > night.carry and under(middle + 3, profile).carry > night.carry);
        try std.testing.expect(noon.key[0] / noon.key[2] > night.key[0] / night.key[2] * 2);
        const before = lit(under(middle - 0.01, profile));
        const after = lit(under(middle + 0.01, profile));
        try std.testing.expectApproxEqAbs(before, after, 1e-5);
    }
}

test "the sun rises in the east, stands in the south at noon, sets in the west and is under the ground at midnight" {
    const rise = sunDir(SUNRISE);
    const noon = sunDir(day.SOLAR_NOON);
    const set = sunDir(SUNSET);
    try std.testing.expect(@abs(rise[2]) < 1e-4 and rise[0] > 0.9);
    try std.testing.expect(@abs(set[2]) < 1e-4 and set[0] < -0.9);
    try std.testing.expect(noon[1] > 0 and noon[2] > 0.8);
    try std.testing.expect(sunDir(0)[2] < -0.5);
}

test "one light always casts, its altitude floored, and it changes hands at the zenith in the dark" {
    const floor_z = @sin(KEY_ALT_MIN);
    var h: f32 = 0;
    var longest: f32 = 0;
    while (h < HOURS) : (h += 0.05) {
        const d = keyDir(h);
        try std.testing.expectApproxEqAbs(@as(f32, 1), @sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]), 1e-4);
        try std.testing.expect(d[2] >= floor_z - 1e-4);
        longest = @max(longest, at(h).reach());
    }
    try std.testing.expect(longest <= REACH_MAX + 1e-3);
    try std.testing.expect(keyDir(KEY_SWAP_DUSK)[2] > 0.9 and keyDim(KEY_SWAP_DUSK) < 1e-4);
    const moon = keyDir(day.DEAD_OF_NIGHT);
    const sun = sunDir(day.DEAD_OF_NIGHT);
    try std.testing.expect(moon[0] * sun[0] + moon[1] * sun[1] < 0);
}

test "noon is bright and midnight dark, the day turns in a ramp, and midnight is no seam" {
    const noon = at(day.NOON);
    const night = at(0);
    try std.testing.expect(noon.key[0] > 1.0 and night.key[0] < 0.1);
    try std.testing.expectEqual(@as(f32, 0), noon.carry);
    try std.testing.expect(night.carry >= NIGHT_FILL_MIN and night.carry < 1);
    var h: f32 = 0;
    var was = at(0);
    while (h <= HOURS) : (h += 0.02) {
        const now = at(h);
        try std.testing.expect(@abs(now.key[0] - was.key[0]) < 0.05 and @abs(now.carry - was.carry) < 0.05);
        was = now;
    }
}
