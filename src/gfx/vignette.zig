const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const look = @import("look.zig");

/// Seconds a blow's reddening takes to rise, and to fade.
const RISE_S: f32 = 0.12;
const PAIN_S: f32 = 0.9;
const PAIN_A: f32 = 0.2;
/// Of full hp, where the low glow starts.
const LOW: f32 = 1.0 / 3.0;
const LOW_A: f32 = 0.3;
/// Per second.
const LOW_EASE: f32 = 4.0;
const BEAT_HZ: f32 = 1.1;
/// Of the low glow, the share that throbs with the beat.
const BEAT: f32 = 0.3;
const TEX_PX: i32 = 128;
/// Of the half-diagonal from the middle, where the reddening starts and where it is whole.
const CLEAR_R: f32 = 0.45;
const FULL_R: f32 = 1.0;

pub const Vignette = struct {
    pain: f32 = 0,
    rising: bool = false,
    low: f32 = 0,
    t: f32 = 0,
    /// The archer's flash last frame: it rising is a blow landing.
    was: f32 = 0,
    tex: ?rl.Texture2D = null,

    pub fn clear(self: *Vignette) void {
        self.pain = 0;
        self.rising = false;
        self.low = 0;
        self.was = 0;
    }

    /// `flash` is the archer's, as `fx.flashOf` gives it.
    pub fn step(self: *Vignette, dt: f32, flash: f32, hp: i32, max: i32) void {
        if (flash > self.was) self.rising = true;
        self.was = flash;
        if (self.rising) {
            self.pain = @min(1, self.pain + dt / RISE_S);
            self.rising = self.pain < 1;
        } else {
            self.pain = @max(0, self.pain - dt / PAIN_S);
        }
        const k = mathx.easing(dt, LOW_EASE);
        self.low = mathx.ease(self.low, lowOf(hp, max), k, k);
        self.t += dt;
    }

    pub fn alpha(self: Vignette) f32 {
        const beat = 0.5 + 0.5 * @sin(self.t * BEAT_HZ * mathx.TAU);
        return @min(1, PAIN_A * self.pain * self.pain + LOW_A * self.low * (1 - BEAT + BEAT * beat));
    }

    /// Needs a live GL context.
    pub fn load(self: *Vignette) void {
        self.tex = look.radial(TEX_PX, edgeAlpha);
    }

    pub fn unload(self: *Vignette) void {
        if (self.tex) |t| rl.unloadTexture(t);
        self.tex = null;
    }

    /// Over the view, `w` by `h` from the screen's top-left.
    pub fn draw(self: Vignette, w: i32, h: i32) void {
        const tex = self.tex orelse return;
        const a = self.alpha();
        if (a <= 0) return;
        look.stretch(tex, look.rect(0, 0, w, h), look.fade(look.LIFE, a));
    }
};

fn edgeAlpha(r: f32) f32 {
    const corner = r / std.math.sqrt2;
    return mathx.smooth((corner - CLEAR_R) / (FULL_R - CLEAR_R));
}

fn lowOf(hp: i32, max: i32) f32 {
    const left = @as(f32, @floatFromInt(hp)) / @as(f32, @floatFromInt(max));
    return std.math.clamp((LOW - left) / LOW, 0, 1);
}

test "a blow on the archer starts reddening the edge as it lands, rises, and fades within its time" {
    var v = Vignette{};
    v.step(1.0 / 60.0, 0, 24, 24);
    try std.testing.expectEqual(@as(f32, 0), v.alpha());
    const dt: f32 = 1.0 / 240.0;
    var flash: f32 = 0.45;
    v.step(dt, flash, 24, 24);
    const first = v.alpha();
    var t: f32 = dt;
    var peak: f32 = first;
    var peak_at: f32 = t;
    while (v.pain > 0 and t < 3) : (t += dt) {
        flash = @max(0, flash - dt);
        v.step(dt, flash, 24, 24);
        if (v.alpha() > peak) {
            peak = v.alpha();
            peak_at = t + dt;
        }
    }
    std.debug.print("a blow's vignette: {d:.3} the frame it lands, {d:.2} at its height {d:.3} s on, gone {d:.3} s on\n", .{ first, peak, peak_at, t });
    try std.testing.expect(first > 0 and first < peak * 0.1);
    try std.testing.expectApproxEqAbs(PAIN_A, peak, 1e-3);
    try std.testing.expectApproxEqAbs(RISE_S, peak_at, dt * 2);
    try std.testing.expectApproxEqAbs(RISE_S + PAIN_S, t, dt * 3);
}

test "the low glow is off above a third of full hp and grows as hp falls toward nothing" {
    std.debug.print("low-hp vignette, settled, by hp of 24:", .{});
    var last: f32 = -1;
    for ([_]i32{ 24, 9, 8, 6, 4, 2, 1 }) |hp| {
        var v = Vignette{};
        for (0..600) |_| v.step(1.0 / 60.0, 0, hp, 24);
        v.t = 0.25 / BEAT_HZ;
        const a = v.alpha();
        std.debug.print(" {d}:{d:.2}", .{ hp, a });
        if (hp >= 8) try std.testing.expectEqual(@as(f32, 0), a) else try std.testing.expect(a > last);
        last = a;
    }
    std.debug.print("\n", .{});
    try std.testing.expect(last <= LOW_A);
}
