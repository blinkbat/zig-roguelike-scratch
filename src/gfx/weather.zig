const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const climate = @import("../map/climate.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const pixel = @import("pixel.zig");
const window = @import("../core/window.zig");

/// Drops per `AREA`; speed/drift in sprite pixels per second, lengths/widths in sprite pixels; alpha at full day.
const Fall = struct { drops: f32, speed: f32, drift: f32, len: f32, width: f32, alpha: f32, splash_s: f32, ring: f32 };

const LIGHTEST = Fall{ .drops = 40, .speed = 700, .drift = 90, .len = 14, .width = 1, .alpha = 0.26, .splash_s = 0.22, .ring = 4 };
const HEAVIEST = Fall{ .drops = 520, .speed = 1150, .drift = 320, .len = 30, .width = 1.5, .alpha = 0.42, .splash_s = 0.26, .ring = 6 };

fn fallOf(rain: f32) ?Fall {
    if (rain <= 0) return null;
    const k = @min(rain, 1);
    var f: Fall = undefined;
    inline for (std.meta.fields(Fall)) |field| @field(f, field.name) = mathx.lerpF(@field(LIGHTEST, field.name), @field(HEAVIEST, field.name), k);
    return f;
}

const AREA_AT = window.SCREEN_1080;
const AREA: f32 = @floatFromInt(AREA_AT.x * AREA_AT.y);
const SCREENS_MOST: u32 = 4;
const DROPS_MAX: usize = @as(usize, @intFromFloat(HEAVIEST.drops)) * SCREENS_MOST;
const FALL_LEAST: f32 = 0.2;
const FALL_MOST: f32 = 0.6;
const INK = look.RAIN;
const DIM_FLOOR: f32 = 0.25;
const SPLASH_DROPS = 4;
const SEED: u64 = 0x5A1_2A17;
const STROKE_GAP_S: f32 = 7;
const STROKE_LEAST: f32 = 0.5;
const STROKE_FLOOR: f32 = 0.4;
const FLASH_RISE_S: f32 = 0.04;
const FLASH_FALL_S: f32 = 0.35;
const RETURN_S: f32 = 0.16;
const RETURN_SHARE: f32 = 0.6;

const Drop = struct {
    /// Screen pixels from the wrapped origin, where it is now.
    x: f32,
    y: f32,
    land: f32,
    /// Seconds since it landed; negative while it falls.
    since: f32,
};

pub const Weather = struct {
    drop: [DROPS_MAX]Drop = undefined,
    n: usize = 0,
    rng: mathx.Rng = mathx.Rng.init(SEED),
    w: f32 = 0,
    h: f32 = 0,
    stroke_s: f32 = std.math.inf(f32),
    stroke: f32 = 0,

    pub fn clear(self: *Weather) void {
        self.n = 0;
        self.stroke_s = std.math.inf(f32);
    }

    /// `now` null under a roof.
    pub fn step(self: *Weather, dt: f32, now: ?climate.Now, w: i32, h: i32, cell: f32) void {
        const n = now orelse return self.clear();
        self.stroke_s += dt;
        const lightning = n.get(.lightning);
        if (lightning > 0 and self.rng.unit() < dt * lightning / STROKE_GAP_S) {
            self.stroke_s = 0;
            self.stroke = self.rng.between(STROKE_LEAST, 1) * @min(1, STROKE_FLOOR + lightning);
        }
        const fall = fallOf(n.get(.rain)) orelse {
            self.n = 0;
            return;
        };
        const scale = look.pxScale(cell);
        self.w = @floatFromInt(w);
        self.h = @floatFromInt(h);
        const want: usize = @min(DROPS_MAX, @as(usize, @intFromFloat(fall.drops * self.w * self.h / AREA)));
        while (self.n < want) : (self.n += 1) self.drop[self.n] = self.fresh(true);
        self.n = want;
        for (self.drop[0..self.n]) |*d| {
            if (d.since < 0) {
                d.y += fall.speed * scale * dt;
                d.x += fall.drift * scale * dt;
                if (d.y >= d.land) {
                    d.since = (d.y - d.land) / (fall.speed * scale);
                    d.x -= fall.drift * d.since * scale;
                    d.y = d.land;
                }
            } else {
                d.since += dt;
                if (d.since >= fall.splash_s) d.* = self.fresh(false);
            }
        }
    }

    pub fn flash(self: *const Weather) f32 {
        return @min(1, self.stroke * (pulse(self.stroke_s) + RETURN_SHARE * pulse(self.stroke_s - RETURN_S)));
    }

    fn pulse(s: f32) f32 {
        if (s < 0 or s >= FLASH_RISE_S + FLASH_FALL_S) return 0;
        if (s < FLASH_RISE_S) return s / FLASH_RISE_S;
        const k = 1 - (s - FLASH_RISE_S) / FLASH_FALL_S;
        return k * k;
    }

    fn fresh(self: *Weather, starting: bool) Drop {
        const x = self.rng.unit() * self.w;
        const land = self.rng.unit() * self.h;
        const drop = self.rng.between(FALL_LEAST, FALL_MOST) * self.h;
        const y = land - drop * (if (starting) self.rng.unit() else 1);
        return .{ .x = x, .y = y, .land = land, .since = -1 };
    }

    pub fn draw(self: *const Weather, now: ?climate.Now, sight: *const [grid.CELLS]f32, ox: f32, oy: f32, cell: f32, bright: f32) void {
        const n = now orelse return;
        const fall = fallOf(n.get(.rain)) orelse return;
        if (self.n == 0 or self.w <= 0 or self.h <= 0) return;
        const scale = look.pxScale(cell);
        const lean = fall.drift / fall.speed;
        const len = fall.len * scale;
        for (self.drop[0..self.n]) |d| {
            const x = @mod(d.x + ox, self.w);
            const y = @mod(d.y + oy, self.h);
            const at = mathx.cellOf(.{ (x - ox) / cell, (y - oy) / cell });
            const seen = grid.cellOr(f32, sight, at, 0);
            if (seen <= 0) continue;
            const a = fall.alpha * std.math.clamp(bright, DIM_FLOOR, 1) * seen;
            if (d.since < 0) {
                const tail = rl.Vector2{ .x = x - lean * len, .y = y - len };
                pixel.line(tail, .{ .x = x, .y = y }, fall.width, scale, look.fade(INK, a));
            } else {
                const k = d.since / fall.splash_s;
                const r = mathx.lerpF(1, fall.ring, k) * scale;
                for (0..SPLASH_DROPS) |i| {
                    const angle = mathx.spoke(@floatFromInt(i), SPLASH_DROPS);
                    pixel.rect(.{ .x = x + @cos(angle) * r, .y = y + @sin(angle) * r * 0.5 }, 1, 1, scale, look.fade(INK, a * (1 - k)));
                }
            }
        }
    }
};

fn raining(rain: f32) climate.Now {
    var n = climate.Now.initFill(0);
    n.set(.rain, rain);
    return n;
}

test "rain keeps its drops falling and landing, more the harder it rains, none for a dry sky, and as many for a bigger screen's area" {
    var w = Weather{};
    const drizzle = climate.PROFILES.get(.drizzle).layer.get(.rain).most;
    w.step(mathx.FRAME_DT, raining(drizzle), AREA_AT.x, AREA_AT.y, look.SPRITE_PX);
    const at_1080 = w.n;
    var landed: usize = 0;
    for (0..600) |_| {
        w.step(mathx.FRAME_DT, raining(drizzle), AREA_AT.x, AREA_AT.y, look.SPRITE_PX);
        for (w.drop[0..w.n]) |d| {
            if (d.since >= 0) landed += 1;
            try std.testing.expect(d.y <= d.land + 1e-3);
        }
    }
    w.step(mathx.FRAME_DT, raining(drizzle), window.SCREEN_720.x, window.SCREEN_720.y, look.SPRITE_PX);
    const at_720 = w.n;
    w.step(mathx.FRAME_DT, raining(1), AREA_AT.x, AREA_AT.y, look.SPRITE_PX);
    const downpour = w.n;
    try std.testing.expect(at_1080 > 100 and at_1080 < 160);
    try std.testing.expect(at_720 * 2 < at_1080 + at_1080 / 4 and at_720 * 2 > at_1080 - at_1080 / 4);
    try std.testing.expect(landed > 0);
    try std.testing.expectEqual(@as(usize, @intFromFloat(HEAVIEST.drops)), downpour);
    w.step(mathx.FRAME_DT, raining(0), AREA_AT.x, AREA_AT.y, look.SPRITE_PX);
    try std.testing.expectEqual(@as(usize, 0), w.n);
    w.step(mathx.FRAME_DT, null, AREA_AT.x, AREA_AT.y, look.SPRITE_PX);
    try std.testing.expectEqual(@as(usize, 0), w.n);
}

test "lightning strikes about as often as its strength asks, each stroke flashing then returning, and never under a roof" {
    var w = Weather{};
    var n = climate.Now.initFill(0);
    n.set(.lightning, 1);
    const seconds = 600;
    const frames: usize = @intFromFloat(seconds / mathx.FRAME_DT);
    var strokes: usize = 0;
    var brightest: f32 = 0;
    for (0..frames) |_| {
        w.step(mathx.FRAME_DT, n, AREA_AT.x, AREA_AT.y, look.SPRITE_PX);
        if (w.stroke_s == 0) strokes += 1;
        brightest = @max(brightest, w.flash());
    }
    const expected = seconds / STROKE_GAP_S;
    try std.testing.expect(@as(f32, @floatFromInt(strokes)) > expected * 0.6 and @as(f32, @floatFromInt(strokes)) < expected * 1.4);
    try std.testing.expect(brightest > 0.5 and brightest <= 1);
    try std.testing.expect(Weather.pulse(RETURN_S) < Weather.pulse(FLASH_RISE_S));
    w.step(mathx.FRAME_DT, null, AREA_AT.x, AREA_AT.y, look.SPRITE_PX);
    try std.testing.expectEqual(@as(f32, 0), w.flash());
}
