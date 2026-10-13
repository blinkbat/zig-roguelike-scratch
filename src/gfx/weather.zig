const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const climate = @import("../world/climate.zig");
const grid = @import("../world/grid.zig");

// What falls from a node's sky, drawn over the world as it lies: drops keep their place on the ground as the camera
// moves, wrapping round the screen, and show only where the archer sees. Nothing in the simulation reads it.

/// A weather's drops on `AREA` pixels of screen, how fast they fall and drift (px a second, at one pixel a sprite
/// pixel), each streak's length and width, its alpha in full daylight, and how long its splash rings.
const Fall = struct { drops: u32, speed: f32, drift: f32, len: f32, width: f32, alpha: f32, splash_s: f32, ring: f32 };

const FALLS = std.EnumArray(climate.Weather, ?Fall).init(.{
    .clear = null,
    .drizzle = .{ .drops = 130, .speed = 760, .drift = 110, .len = 16, .width = 1, .alpha = 0.3, .splash_s = 0.22, .ring = 4 },
});

const AREA: f32 = 1920 * 1080;
/// A 4K screen holds four `AREA`s.
const SCREENS_MOST: u32 = 4;
pub const DROPS_MAX: usize = 600;
/// Of the screen's height, the least and the most a drop falls before it lands.
const FALL_LEAST: f32 = 0.2;
const FALL_MOST: f32 = 0.6;
const INK = rl.Color{ .r = 196, .g = 208, .b = 226, .a = 255 };
/// Drops are drawn no fainter than this share of their daylight alpha, so rain still shows at night.
const DIM_FLOOR: f32 = 0.25;
const SEED: u64 = 0x5A1_2A17;

comptime {
    for (FALLS.values) |f| {
        if (f) |fall| std.debug.assert(fall.drops * SCREENS_MOST <= DROPS_MAX);
    }
}

const Drop = struct {
    /// Screen pixels from the wrapped origin, where it is now.
    x: f32,
    y: f32,
    /// Where it lands.
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

    pub fn clear(self: *Weather) void {
        self.n = 0;
    }

    /// `w` by `h` the screen, `scale` screen pixels a sprite pixel.
    pub fn step(self: *Weather, dt: f32, kind: ?climate.Weather, w: i32, h: i32, scale: f32) void {
        const fall = FALLS.get(kind orelse .clear) orelse return self.clear();
        self.w = @floatFromInt(w);
        self.h = @floatFromInt(h);
        const want: usize = @min(DROPS_MAX, @as(usize, @intFromFloat(@as(f32, @floatFromInt(fall.drops)) * self.w * self.h / AREA)));
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

    /// Partway down its fall when the rain starts, so it does not arrive as one sheet; else at the top of it.
    fn fresh(self: *Weather, starting: bool) Drop {
        const x = self.rng.unit() * self.w;
        const land = self.rng.unit() * self.h;
        const drop = (FALL_LEAST + self.rng.unit() * (FALL_MOST - FALL_LEAST)) * self.h;
        const y = land - drop * (if (starting) self.rng.unit() else 1);
        return .{ .x = x, .y = y, .land = land, .since = -1 };
    }

    /// Over the cells of `lv` in sight, its top-left landing at `ox, oy`, `cell` pixels a cell; `bright` is the sky's light, 1 at full day.
    pub fn draw(self: *const Weather, kind: ?climate.Weather, lv: *const grid.Level, ox: f32, oy: f32, cell: f32, scale: f32, bright: f32) void {
        const fall = FALLS.get(kind orelse .clear) orelse return;
        if (self.n == 0 or self.w <= 0 or self.h <= 0) return;
        const a = fall.alpha * std.math.clamp(bright, DIM_FLOOR, 1);
        const lean = fall.drift / fall.speed;
        const len = fall.len * scale;
        for (self.drop[0..self.n]) |d| {
            const x = @mod(d.x + ox, self.w);
            const y = @mod(d.y + oy, self.h);
            const at = mathx.P{ .x = @intFromFloat(@floor((x - ox) / cell)), .y = @intFromFloat(@floor((y - oy) / cell)) };
            if (!lv.isLit(at)) continue;
            if (d.since < 0) {
                const tail = rl.Vector2{ .x = x - lean * len, .y = y - len };
                rl.drawLineEx(tail, .{ .x = x, .y = y }, fall.width * scale, fade(a));
            } else {
                const k = d.since / fall.splash_s;
                rl.drawCircleLinesV(.{ .x = x, .y = y }, (1 + k * (fall.ring - 1)) * scale, fade(a * (1 - k)));
            }
        }
    }
};

fn fade(a: f32) rl.Color {
    var c = INK;
    c.a = @intFromFloat(std.math.clamp(a, 0, 1) * 255);
    return c;
}

test "a drizzle keeps its drops falling and landing, none for a clear sky, and as many for a bigger screen's area" {
    var w = Weather{};
    w.step(1.0 / 60.0, .drizzle, 1920, 1080, 1);
    const at_1080 = w.n;
    var landed: usize = 0;
    for (0..600) |_| {
        w.step(1.0 / 60.0, .drizzle, 1920, 1080, 1);
        for (w.drop[0..w.n]) |d| {
            if (d.since >= 0) landed += 1;
            try std.testing.expect(d.y <= d.land + 1e-3);
        }
    }
    w.step(1.0 / 60.0, .drizzle, 1280, 720, 1);
    const at_720 = w.n;
    std.debug.print("a drizzle: {d} drops at 1080p, {d} at 720p, {d} drop-frames spent splashing over 10 s\n", .{ at_1080, at_720, landed });
    try std.testing.expectEqual(@as(usize, FALLS.get(.drizzle).?.drops), at_1080);
    try std.testing.expect(at_720 * 2 < at_1080 + at_1080 / 4 and at_720 * 2 > at_1080 - at_1080 / 4);
    try std.testing.expect(landed > 0);
    w.step(1.0 / 60.0, .clear, 1920, 1080, 1);
    try std.testing.expectEqual(@as(usize, 0), w.n);
    w.step(1.0 / 60.0, null, 1920, 1080, 1);
    try std.testing.expectEqual(@as(usize, 0), w.n);
}
