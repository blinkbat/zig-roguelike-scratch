const std = @import("std");
const mathx = @import("../core/mathx.zig");
const day = @import("../world/day.zig");

// zig-soulslike's `world/daynight.zig` seen from above. Directions point toward the light: x east, y south (down the screen), z up.

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
/// The casting light's altitude is clamped to these, so a shadow neither outruns the screen nor hides under its caster; the sun's own is not.
const KEY_ALT_MIN = std.math.degreesToRadians(@as(f32, 35));
const KEY_ALT_MAX = std.math.degreesToRadians(@as(f32, 50));
/// Cells the longest shadow the sky throws runs along the ground per cell of height.
pub const REACH_MAX: f32 = 1 / @tan(KEY_ALT_MIN);
/// Where the moon takes over from the sun as the light that casts, and back.
const KEY_SWAP_DAWN: f32 = 5.0;
const KEY_SWAP_DUSK: f32 = 20.8;
const KEY_SWAP_FADE: f32 = 0.45;
/// A light leaning along the ground less than this stands straight up.
pub const OVERHEAD: f32 = 1e-4;
/// The palette's sky is a hemisphere's; seen from above it lights the ground in shade this many times over.
const SKY_GAIN: f32 = 1.6;
/// The palette's key is a 3D scene's; on art drawn flat it is this strong.
const KEY_GAIN: f32 = 0.85;
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
pub fn sunDir(hour: f32) [3]f32 {
    const u = dayU(hour);
    const alt = SUN_ALT_MAX * @sin(std.math.pi * u);
    const az = if (u <= 1) AZ_RISE + (AZ_SET - AZ_RISE) * u else AZ_SET + (360 - (AZ_SET - AZ_RISE)) * (u - 1);
    return dirFrom(az, alt);
}

/// The one light that casts, altitude floored; it changes hands over the zenith in the sun's vertical plane, so a shadow shrinks to its foot and regrows opposite, never turning.
pub fn keyDir(hour: f32) [3]f32 {
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
pub fn keyDim(hour: f32) f32 {
    const k = 1 - 2 * moonShare(hour);
    return k * k;
}

const Key = struct { at: f32, key: Rgb, sky: Rgb };

/// Night, darker than zig-soulslike's so the dark outdoors reads as dark, and darkest at midnight.
const NIGHT = Key{ .at = 0, .key = .{ 0.022, 0.030, 0.060 }, .sky = .{ 0.014, 0.018, 0.034 } };
const MIDNIGHT = Key{ .at = 0, .key = .{ 0.006, 0.008, 0.018 }, .sky = .{ 0.004, 0.005, 0.011 } };

/// zig-soulslike's key and sky rows, 0 and 24 equal so midnight is no seam; sunrise and sunset keys warmed to gold, as its deep orange takes the green out of grass seen flat.
const KEYS = [_]Key{
    MIDNIGHT,
    .{ .at = 2.5, .key = NIGHT.key, .sky = NIGHT.sky },
    .{ .at = KEY_SWAP_DAWN, .key = .{ 0.088, 0.104, 0.168 }, .sky = .{ 0.046, 0.056, 0.088 } },
    .{ .at = SUNRISE, .key = .{ 1.100, 0.620, 0.340 }, .sky = .{ 0.120, 0.124, 0.166 } },
    .{ .at = 8.5, .key = .{ 1.250, 1.070, 0.860 }, .sky = .{ 0.176, 0.208, 0.276 } },
    .{ .at = 12.0, .key = .{ 1.310, 1.280, 1.180 }, .sky = .{ 0.196, 0.232, 0.310 } },
    .{ .at = 17.45, .key = .{ 1.320, 1.100, 0.800 }, .sky = .{ 0.168, 0.188, 0.244 } },
    .{ .at = 19.4, .key = .{ 1.180, 0.660, 0.320 }, .sky = .{ 0.132, 0.136, 0.186 } },
    .{ .at = KEY_SWAP_DUSK, .key = .{ 0.130, 0.150, 0.230 }, .sky = .{ 0.058, 0.068, 0.102 } },
    .{ .at = 21.5, .key = NIGHT.key, .sky = NIGHT.sky },
    .{ .at = HOURS, .key = MIDNIGHT.key, .sky = MIDNIGHT.sky },
};

comptime {
    std.debug.assert(KEYS[0].at == 0 and KEYS[KEYS.len - 1].at == HOURS);
    for (KEYS[1..], 0..) |k, i| std.debug.assert(k.at > KEYS[i].at);
}

fn paletteAt(hour: f32) struct { key: Rgb, sky: Rgb } {
    const h = wrapHour(hour);
    var i: usize = 0;
    while (i + 2 < KEYS.len and KEYS[i + 1].at <= h) i += 1;
    const a = KEYS[i];
    const b = KEYS[i + 1];
    const t = mathx.smooth((h - a.at) / (b.at - a.at));
    return .{ .key = mix(a.key, b.key, t), .sky = mix(a.sky, b.sky, t) };
}

pub const Sky = struct {
    /// Toward the light that casts, a unit vector.
    dir: [3]f32,
    /// That light's colour and strength, dimmed through the swap.
    key: Rgb,
    /// What reaches ground in shade.
    ambient: Rgb,
    /// How much of the archer's own light still shows: none by day.
    carry: f32,
    /// How far the light that casts is the moon's: 0 by day, 1 by night.
    moon: f32,

    /// The length of `dir` along the ground.
    pub fn flat(s: Sky) f32 {
        return flatOf(s.dir);
    }

    /// Along the ground toward it, a unit vector; south when it stands straight up.
    pub fn across(s: Sky) [2]f32 {
        const f = s.flat();
        return if (f > OVERHEAD) .{ s.dir[0] / f, s.dir[1] / f } else .{ 0, 1 };
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

pub fn at(hour: f32) Sky {
    const p = paletteAt(hour);
    return .{
        .dir = acrossScreen(keyDir(hour)),
        .key = p.key * splat(keyDim(hour) * KEY_GAIN),
        .ambient = p.sky * splat(SKY_GAIN),
        .carry = 1 - day.daylight(hour),
        .moon = moonShare(hour),
    };
}

/// Its north-south lean squashed, then laid no steeper than `KEY_ALT_MAX`; straight overhead, as at the swap, it stays.
fn acrossScreen(d: [3]f32) [3]f32 {
    var x = d[0];
    var y = d[1] * NORTH_SOUTH;
    const flat = mathx.len(x, y);
    const least = d[2] / @tan(KEY_ALT_MAX);
    if (flat > OVERHEAD and flat < least) {
        x *= least / flat;
        y *= least / flat;
    }
    const n = @sqrt(x * x + y * y + d[2] * d[2]);
    return .{ x / n, y / n, d[2] / n };
}

test "the sun rises in the east, stands in the south at noon, sets in the west and is under the ground at midnight" {
    const rise = sunDir(SUNRISE);
    const noon = sunDir(13);
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
    const moon = keyDir(1);
    const sun = sunDir(1);
    try std.testing.expect(moon[0] * sun[0] + moon[1] * sun[1] < 0);
}

test "noon is bright and midnight dark, the day turns in a ramp, and midnight is no seam" {
    const noon = at(12);
    const night = at(0);
    std.debug.print("key at noon {d:.2} {d:.2} {d:.2}, at midnight {d:.3} {d:.3} {d:.3}; shade at noon {d:.2}, at midnight {d:.3}\n", .{ noon.key[0], noon.key[1], noon.key[2], night.key[0], night.key[1], night.key[2], noon.ambient[1], night.ambient[1] });
    try std.testing.expect(noon.key[0] > 1.0 and night.key[0] < 0.1);
    try std.testing.expectEqual(@as(f32, 0), noon.carry);
    try std.testing.expectEqual(@as(f32, 1), night.carry);
    var h: f32 = 0;
    var was = at(0);
    while (h <= HOURS) : (h += 0.02) {
        const now = at(h);
        try std.testing.expect(@abs(now.key[0] - was.key[0]) < 0.05 and @abs(now.carry - was.carry) < 0.05);
        was = now;
    }
}
