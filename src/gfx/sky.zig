const std = @import("std");
const mathx = @import("../core/mathx.zig");
const day = @import("../map/day.zig");
const climate = @import("../map/climate.zig");

// Directions point toward light: x east, y south (screen-down), z up.

pub const Rgb = @Vector(3, f32);

pub fn mix(a: Rgb, b: Rgb, k: f32) Rgb {
    return a + (b - a) * splat(k);
}

pub fn splat(k: f32) Rgb {
    return @splat(k);
}

fn flatOf(d: [3]f32) f32 {
    return mathx.len(d[0], d[1]);
}

const HOURS = day.HOURS;
const SUNRISE = day.SUNRISE;
const SUNSET = day.SUNSET;
const wrapHour = day.wrapHour;
const DAY_SPAN: f32 = SUNSET - SUNRISE;
const NIGHT_SPAN: f32 = HOURS - DAY_SPAN;
/// Bearings clockwise from north the sun rises and sets on; it stands in the south at noon.
const AZ_RISE: f32 = 100;
const AZ_SET: f32 = 262;
const SUN_ALT_MAX: f32 = 60;
/// Clamp casting altitude to keep shadows visible and on screen; leave the true sun altitude unchanged.
const KEY_ALT_MIN = std.math.degreesToRadians(@as(f32, 35));
const KEY_ALT_MAX = std.math.degreesToRadians(@as(f32, 42));
/// Cells the longest shadow the sky throws runs along the ground per cell of height.
pub const REACH_MAX: f32 = 1 / @tan(KEY_ALT_MIN);
/// Where the moon takes over from the sun as the light that casts, and back.
const KEY_SWAP_DAWN: f32 = SUNRISE - 1.0;
const KEY_SWAP_DUSK: f32 = SUNSET + 0.8;
/// Hours from the horizon over which night gives way to dawn's colours, and morning's to full day.
const GLOW_HOURS: f32 = 2.5;
const KEY_SWAP_FADE: f32 = 0.45;
/// A light leaning along the ground less than this stands straight up.
pub const OVERHEAD: f32 = 1e-4;
/// The palette's sky is a hemisphere's; seen from above it lights the ground in shade this many times over.
const SKY_GAIN: f32 = 1.6;
/// The palette's key is a 3D scene's; on art drawn flat it is this strong.
const KEY_GAIN: f32 = 0.85;
const NIGHT_FILL_MIN: f32 = 0.72;
/// The share of the night either side of its dead point over which the carried light's fill climbs back to whole.
const NIGHT_FILL_SPREAD: f32 = 0.4;
/// The moon's key as if it stood this high, whatever its true altitude.
const MOON_LIFT: f32 = 0.7;
/// Of the casting light's lean north or south, the share the map shows, so shadows run mostly across the screen.
const NORTH_SOUTH: f32 = 0.35;

comptime {
    std.debug.assert(KEY_SWAP_DAWN < SUNRISE and KEY_SWAP_DUSK > SUNSET);
}

/// 0 to 1 across the day, then 1 to 2 across the night, measured on from sunset through midnight.
fn dayU(hour: f32) f32 {
    const h = wrapHour(hour);
    if (h >= SUNRISE and h <= SUNSET) return (h - SUNRISE) / DAY_SPAN;
    const past = if (h > SUNSET) h - SUNSET else h + (HOURS - SUNSET);
    return 1 + past / NIGHT_SPAN;
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

/// The sun's true path: under the ground at night, the bearing going all the way round once a day.
fn sunDir(hour: f32) [3]f32 {
    const u = dayU(hour);
    const alt = SUN_ALT_MAX * @sin(std.math.pi * u);
    const az = if (u <= 1) AZ_RISE + (AZ_SET - AZ_RISE) * u else AZ_SET + (360 - (AZ_SET - AZ_RISE)) * (u - 1);
    return dirFrom(az, alt);
}

/// Swap sun and moon through the zenith while `keyDim` hides the shadow flip.
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

/// The key's strength through the swap: 1 either side of it, 0 at the crossing.
fn keyDim(hour: f32) f32 {
    const k = 1 - 2 * moonShare(hour);
    return k * k;
}

const Palette = struct { key: Rgb, sky: Rgb };
const Key = struct { at: f32, key: Rgb, sky: Rgb };

const NIGHT = Palette{ .key = .{ 0.018, 0.036, 0.100 }, .sky = .{ 0.008, 0.018, 0.050 } };
const DEEPEST_NIGHT = Palette{ .key = .{ 0.003, 0.006, 0.020 }, .sky = .{ 0.002, 0.004, 0.012 } };

/// Equal endpoints at the middle of the night avoid a seam.
const KEYS = [_]Key{
    .{ .at = day.DEAD_OF_NIGHT, .key = DEEPEST_NIGHT.key, .sky = DEEPEST_NIGHT.sky },
    .{ .at = SUNRISE - GLOW_HOURS, .key = NIGHT.key, .sky = NIGHT.sky },
    .{ .at = KEY_SWAP_DAWN, .key = .{ 0.088, 0.104, 0.168 }, .sky = .{ 0.046, 0.056, 0.088 } },
    .{ .at = SUNRISE, .key = .{ 1.100, 0.620, 0.340 }, .sky = .{ 0.120, 0.124, 0.166 } },
    .{ .at = SUNRISE + GLOW_HOURS, .key = .{ 1.300, 1.070, 0.800 }, .sky = .{ 0.196, 0.208, 0.250 } },
    .{ .at = day.NOON, .key = .{ 1.380, 1.250, 1.040 }, .sky = .{ 0.220, 0.230, 0.260 } },
    .{ .at = SUNSET - 2.55, .key = .{ 1.320, 1.100, 0.800 }, .sky = .{ 0.168, 0.188, 0.244 } },
    .{ .at = SUNSET - 0.6, .key = .{ 1.180, 0.660, 0.320 }, .sky = .{ 0.132, 0.136, 0.186 } },
    .{ .at = KEY_SWAP_DUSK, .key = .{ 0.130, 0.150, 0.230 }, .sky = .{ 0.058, 0.068, 0.102 } },
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
    /// Toward the light that casts, a unit vector.
    dir: [3]f32,
    /// That light's colour and strength, dimmed through the swap.
    key: Rgb,
    /// What reaches ground in shade.
    ambient: Rgb,
    /// How much of the hero's own light still shows: none by day.
    carry: f32,
    /// How far the light that casts is the moon's: 0 by day, 1 by night.
    moon: f32,

    /// How far the light that casts is the sun's.
    pub fn sun(s: Sky) f32 {
        return 1 - s.moon;
    }

    /// The length of `dir` along the ground.
    pub fn flat(s: Sky) f32 {
        return flatOf(s.dir);
    }

    /// Along the ground toward it, a unit vector; south when it stands straight up.
    pub fn across(s: Sky) [2]f32 {
        const f = s.flat();
        return if (upright(f)) .{ 0, 1 } else .{ s.dir[0] / f, s.dir[1] / f };
    }

    /// Cells a shadow runs along the ground per cell of height.
    pub fn reach(s: Sky) f32 {
        return s.flat() / @max(s.dir[2], 1e-3);
    }

    /// Cells up per cell along the ground toward it.
    pub fn rise(s: Sky) f32 {
        return s.dir[2] / @max(s.flat(), OVERHEAD);
    }
};

/// A light whose length along the ground is `flat` stands straight over what it lights, and casts no shadow.
pub fn upright(flat: f32) bool {
    return flat < OVERHEAD;
}

const Look = struct { key: f32 = 1, sky: f32 = 1, grey: f32 = 0, tint: Rgb = splat(1) };

/// Bleak is an overcast: most of the sun's light spread into the sky, so shadows go soft and the day a little dark.
const LOOKS = std.EnumArray(climate.Light, Look).init(.{
    .clear = .{},
    .bleak = .{ .key = 0.3, .sky = 1.75, .grey = 0.55, .tint = .{ 0.92, 0.98, 1.06 } },
});

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

/// Open ground's light under `s`, 1 at a clear noon.
pub fn brightness(s: Sky) f32 {
    return lit(s) / lit(at(day.NOON));
}

pub fn at(hour: f32) Sky {
    return under(hour, .clear);
}

pub fn under(hour: f32, light: climate.Light) Sky {
    const p = paletteAt(hour);
    const l = LOOKS.get(light);
    const dir = acrossScreen(keyDir(hour));
    const moon = moonShare(hour);
    const gain = mathx.lerpF(1, MOON_LIFT / dir[2], moon);
    const night_fill = mathx.lerpF(NIGHT_FILL_MIN, 1, mathx.smoothstep(0, NIGHT_SPAN * NIGHT_FILL_SPREAD, @abs(day.toward(day.DEAD_OF_NIGHT, hour))));
    return .{
        .dir = dir,
        .key = looked(p.key, keyDim(hour) * KEY_GAIN * l.key * gain, l),
        .ambient = looked(p.sky, SKY_GAIN * l.sky, l),
        .carry = (1 - day.daylight(hour)) * night_fill,
        .moon = moon,
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
    const n = @sqrt(x * x + y * y + d[2] * d[2]);
    return .{ x / n, y / n, d[2] / n };
}

test "a bleak sky is a little darker than a clear one, greyer, and its shadows softer" {
    const spread = struct {
        fn f(c: Rgb) f32 {
            return @reduce(.Max, c) - @reduce(.Min, c);
        }
    }.f;
    for ([_]f32{ 8.5, day.NOON, 17.45 }) |h| {
        const clear = under(h, .clear);
        const bleak = under(h, .bleak);
        const lit_clear = lit(clear);
        const lit_bleak = lit(bleak);
        const share_clear = luma(clear.key) / (luma(clear.key) + luma(clear.ambient));
        const share_bleak = luma(bleak.key) / (luma(bleak.key) + luma(bleak.ambient));
        std.debug.print("at {d:.2}: open ground {d:.2} clear, {d:.2} bleak ({d:.0}%); the sun's share {d:.2} against {d:.2}\n", .{ h, lit_clear, lit_bleak, lit_bleak / lit_clear * 100, share_clear, share_bleak });
        try std.testing.expect(lit_bleak > lit_clear * 0.6 and lit_bleak < lit_clear * 0.9);
        try std.testing.expect(share_bleak < share_clear * 0.6);
        try std.testing.expect(spread(bleak.key) / luma(bleak.key) < spread(clear.key) / luma(clear.key));
    }
    try std.testing.expectEqual(at(day.NOON), under(day.NOON, .clear));
}

test "a noon shadow reaches beyond a cell-tall sprite" {
    const reach = at(day.NOON).reach();
    std.debug.print("noon shadow reaches {d:.2} sprite heights\n", .{reach});
    try std.testing.expect(reach > 1.05 and reach < 1.3);
}

test "each climate is darkest halfway through the night, blue at night and warmer by day" {
    const middle = day.DEAD_OF_NIGHT;
    try std.testing.expectApproxEqAbs(day.toward(SUNSET, middle), day.toward(middle, SUNRISE), 1e-5);
    for (std.enums.values(climate.Light)) |profile| {
        const darkest = lit(under(middle, profile));
        for (0..1440) |minute| {
            const hour = @as(f32, @floatFromInt(minute)) / 60;
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
        std.debug.print("{s} sky: 1440 minutes checked; minimum at {d:.1}h, night blue/red {d:.2}, noon key red/blue {d:.2}\n", .{ @tagName(profile), middle, night.key[2] / night.key[0], noon.key[0] / noon.key[2] });
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
    std.debug.print("a shadow is at most {d:.2} cells long a cell of height\n", .{longest});
    try std.testing.expect(longest <= REACH_MAX + 1e-3);
    try std.testing.expect(keyDir(KEY_SWAP_DUSK)[2] > 0.9 and keyDim(KEY_SWAP_DUSK) < 1e-4);
    const moon = keyDir(day.DEAD_OF_NIGHT);
    const sun = sunDir(day.DEAD_OF_NIGHT);
    try std.testing.expect(moon[0] * sun[0] + moon[1] * sun[1] < 0);
}

test "noon is bright and midnight dark, the day turns in a ramp, and midnight is no seam" {
    const noon = at(day.NOON);
    const night = at(0);
    std.debug.print("key at noon {d:.2} {d:.2} {d:.2}, at midnight {d:.3} {d:.3} {d:.3}; shade at noon {d:.2}, at midnight {d:.3}\n", .{ noon.key[0], noon.key[1], noon.key[2], night.key[0], night.key[1], night.key[2], noon.ambient[1], night.ambient[1] });
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
