const std = @import("std");
const rl = @import("raylib");
const state = @import("effect_state.zig");
const impact_queue = @import("impact_queue.zig");
pub const Matter = state.Matter;
pub const ActorImpact = state.ActorImpact;
pub const Impact = state.Impact;
const Blow = state.Blow;
pub const Status = state.Status;
pub const Body = state.Body;
pub const After = state.After;
pub const Drip = state.Drip;
pub const Puff = state.Puff;
pub const TICK_WISPS = state.TICK_WISPS;
pub const BURST_WISPS = state.BURST_WISPS;
pub const Sting = state.Sting;
const Settle = state.Settle;
const Burst = state.Burst;
pub const Zap = state.Zap;
const Shimmer = state.Shimmer;
pub const FLASH_S = impact_queue.FLASH_S;
pub const DEATH_RGB = impact_queue.DEATH_RGB;
pub const OWED_KINDS = impact_queue.OWED_KINDS;
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const damage = @import("../play/damage.zig");
const glacial = @import("../play/glacial.zig");
const burning = @import("../play/burning.zig");
const shock = @import("../play/shock.zig");
const confusion = @import("../play/confusion.zig");
const ward = @import("../play/ward.zig");
const look = @import("look.zig");
const font = @import("font.zig");
const skillbar = @import("../play/skillbar.zig");
const nova = @import("../play/nova.zig");
const pixel = @import("pixel.zig");
const light = @import("light.zig");
const sky = @import("sky.zig");

/// A body's, or a barrel's (null).
pub fn matterOf(kind: ?actor.Kind) Matter {
    const k = kind orelse return .wood;
    return switch (k) {
        .archer, .wizard, .knight, .rat, .pib, .beefy_pib, .bandit_crossbowman, .bandit_netter, .bandit_shieldbearer, .pib_shaman, .bog_leech => .blood,
        .slime, .slime_half, .slime_quarter => .ooze,
        .bloat, .frost_wisp, .pyre_bloat => .ichor,
        .mimic => .wood,
    };
}

/// Cells, ground to where a blow lands on a body.
const STRIKE_Z: f32 = 0.3;
const STAIN_S: f32 = 1.8;
/// Of a stain's life, the last part over which it fades.
const STAIN_FADE: f32 = 0.6;
/// Of a stain's own radius, flattened onto the floor.
const STAIN_W: f32 = 1.5;
const STAIN_H: f32 = 0.8;
/// Of a flight that leaves no stain, the last part over which the mote fades.
const FLY_FADE: f32 = 0.5;
/// Maximum simulation step in seconds; prevents motes tunnelling through walls.
const MOTE_STEP: f32 = 1.0 / 30.0;
/// Of its speed along the ground a mote keeps through each bounce.
const SKID: f32 = 0.6;
const CONTACT_S: f32 = 0.09;
/// Sprite pixels.
const CONTACT_R: f32 = 7;
/// Of `CONTACT_R`, a killing blow's.
const KILL_POP: f32 = 1.6;

const Spray = struct {
    col: rl.Color,
    hit: usize,
    kill: usize,
    /// Cells a second along the blow, and across it either way.
    along_lo: f32,
    along_hi: f32,
    fan: f32,
    up_lo: f32,
    up_hi: f32,
    /// Cells a second squared, and 1/s.
    grav: f32,
    drag: f32,
    life_lo: f32,
    life_hi: f32,
    /// Sprite pixels.
    r_lo: f32,
    r_hi: f32,
    stains: bool,
    bounce: f32 = 0,
    add: bool = false,
};

fn sprayOf(m: Matter) Spray {
    return switch (m) {
        .blood => .{ .col = look.BLOOD, .hit = 6, .kill = 14, .along_lo = 0.6, .along_hi = 2.2, .fan = 0.8, .up_lo = 0.6, .up_hi = 1.6, .grav = 7, .drag = 3, .life_lo = 0.35, .life_hi = 0.6, .r_lo = 1.2, .r_hi = 2.4, .stains = true },
        .ooze => .{ .col = look.OOZE, .hit = 6, .kill = 15, .along_lo = 0.4, .along_hi = 1.7, .fan = 0.9, .up_lo = 0.5, .up_hi = 1.4, .grav = 5.5, .drag = 3, .life_lo = 0.3, .life_hi = 0.6, .r_lo = 1.4, .r_hi = 2.8, .stains = true },
        .wood => .{ .col = look.SPLINTER, .hit = 6, .kill = 11, .along_lo = 0.2, .along_hi = 1.2, .fan = 1.4, .up_lo = 0.8, .up_hi = 1.9, .grav = 9, .drag = 2, .life_lo = 0.4, .life_hi = 0.7, .r_lo = 1.2, .r_hi = 2.2, .stains = false, .bounce = 0.35 },
        .ichor => blk: {
            var s = sprayOf(.blood);
            s.col = look.ICHOR;
            break :blk s;
        },
    };
}

pub const Mote = struct {
    /// Cells: `x`, `y` on the ground and `z` up off it.
    p: [3]f32,
    v: [3]f32,
    life: f32 = 0,
    max: f32 = 1,
    r: f32,
    col: rl.Color,
    grav: f32 = 0,
    drag: f32 = 0,
    bounce: f32 = 0,
    stains: bool = false,
    landed: bool = false,
    add: bool = false,
    terrain: bool = true,
    /// Of its radius, how much wider it has grown by the end of its life.
    grow: f32 = 0,
    vapor: bool = false,
};

const STATUS_FLICKER: f32 = 0.1;
const STATUS_FLICKER_RAD_S: f32 = 11;

const WISP_A: f32 = 0.5;

const MOTES: usize = 320;
const ARCS: usize = 12;
pub const PULSES: usize = 32;
const RIPPLES: usize = 24;

/// `ring`'s slot at `head`, the oldest, with `head` moved on past it.
fn claim(comptime T: type, ring: []T, head: *usize) *T {
    const at = &ring[head.*];
    head.* = (head.* + 1) % ring.len;
    return at;
}

const ARC_S: f32 = 0.18;
/// An arc's kinks: cells apart along it and the most they stray across it, a fork every `ARC_FORK` kinks, and its light every `ARC_GLOW_EVERY` cells.
const ARC_STEP: f32 = 0.2;
const ARC_JITTER: f32 = 0.16;
const ARC_FORK = 6;
const ARC_GLOW_EVERY: f32 = 2;
const ARC_POINTS = 96;
const Arc = struct {
    points: [ARC_POINTS][2]f32 = undefined,
    n: usize = 0,
    life: f32 = 0,
};

/// A brief light an effect casts: reach in cells, peak gain, and seconds to fade.
pub const Glow = struct { radius: f32, gain: f32, life: f32 };
pub const Mark = struct { x: f32, y: f32, cell: f32, seed: usize, ink: rl.Color, alpha: f32, stacks: u8 };
pub const EMBER_GLOW = Glow{ .radius = 2.2, .gain = 0.8, .life = 0.32 };
const SHIMMER_GLOW = Glow{ .radius = 2.2, .gain = 0.65, .life = 0.4 };
const FIRE_BURST_GLOW = Glow{ .radius = 3.5, .gain = 1.4, .life = 0.35 };
const COLD_BURST_GLOW = Glow{ .radius = 3, .gain = 0.6, .life = 0.35 };
const ARC_GLOW = Glow{ .radius = 1.8, .gain = 0.85, .life = ARC_S };

const Pulse = struct {
    source: light.Emission = .{ .at = @splat(0), .col = rl.Color.blank, .radius = 0, .gain = 0 },
    life: f32 = 0,
    max: f32 = 1,
};

const Ripple = struct {
    at: [2]f32 = @splat(0),
    t: f32 = RIPPLE_S,

    const Ring = struct { r: f32, a: f32 };

    /// Its outermost ring.
    fn ring(self: Ripple) ?Ring {
        if (self.t >= RIPPLE_S) return null;
        const k = self.t / RIPPLE_S;
        return .{ .r = mathx.lerpF(RIPPLE_R[0], RIPPLE_R[1], 1 - (1 - k) * (1 - k)), .a = 1 - k };
    }
};

pub const JUKE_S: f32 = 0.6;
const JUKE_R = [2]f32{ 2, 5 };
const CELL_MOTES: usize = 12;
/// Cap burst motes so wide bursts leave room for stains and hit effects.
const BURST_MOTES: usize = 144;

fn burstMotes(cells: usize) usize {
    return std.math.clamp(BURST_MOTES / @max(cells, 1), 1, CELL_MOTES);
}
const TRAIL_MOTES: usize = 20;
const DUST_MOTES: usize = 24;
const WHIRL_MOTES: usize = 36;
/// A sweep's ring: cells out from the sweeper, cells a second its streaks race round, their longest life, and how flat the ring lies.
const WHIRL_R: f32 = 0.7;
const WHIRL_SPEED: f32 = 3.2;
const WHIRL_S: f32 = 0.34;
const WHIRL_FLAT: f32 = 0.6;
/// Motes a cell of a zap's line.
const ZAP_MOTES: usize = 5;
/// How far a zap's motes stray off its line, in cells.
const ZAP_JITTER: f32 = 0.18;
const EMBERS = Spray{ .col = look.FIRE, .hit = 18, .kill = 18, .along_lo = 0.4, .along_hi = 1.4, .fan = 0, .up_lo = 0.5, .up_hi = 1.5, .grav = 0, .drag = 2, .life_lo = 0.25, .life_hi = 0.55, .r_lo = 1, .r_hi = 2.5, .stains = false, .add = true };
const DRIP_MOTES: usize = 5;
const WATER_MOTES = [2]u32{ 5, 9 };
/// Cells below a body's middle its footfall rises from, and how far across and down it spreads.
pub const SPLASH_FOOT: f32 = 0.32;
pub const SPLASH_R: f32 = 0.26;
pub const SPLASH_RY: f32 = 0.09;
/// A footfall's rings: the outermost grows across `RIPPLE_R` sprite pixels in `RIPPLE_S`, the rest follow `RIPPLE_GAP` inside it, all `RIPPLE_FLAT` as tall as wide.
const RIPPLE_RINGS: usize = 4;
const RIPPLE_GAP: f32 = 5;
const RIPPLE_S: f32 = 0.9;
const RIPPLE_R = [2]f32{ 2, 20 };
const RIPPLE_FLAT: f32 = 0.45;
const STEP_DUST = [2]u32{ 3, 6 };
const BLEED_DROPS = 4;
const CHILL_FLAKES = 5;
const BURN_FLAMES = 7;
const TORCH_FLAMES = 7;
const FLAME_HZ: f32 = 1.7;
const TORCH_RISE_PX: f32 = 16;
const TORCH_FLECK_PX: f32 = 3.5;
/// Sprite pixels above its foot the tallest flame reaches.
pub const TORCH_TOP_PX = 20;

comptime {
    std.debug.assert(TORCH_RISE_PX + TORCH_FLECK_PX <= TORCH_TOP_PX);
}
const WARD_DOTS = 48;
const SHOCK_SPARKS = 4;
/// Flickers a second of shock's sparks.
const SHOCK_HZ: f32 = 9;
const CONFUSION_DOTS = 3;
/// Cells under a body's top its blindness and confusion marks sit, and how wide confusion circles.
const HALO_Y: f32 = 0.1;
const HALO_R: f32 = 0.2;
/// Across a body's cell, where enfeeblement's chevron sinks, and how often a second.
const ENFEEBLE_X: f32 = 0.2;
const ENFEEBLE_HZ: f32 = 0.8;
/// Across a body's cell, where fright's mark trembles, how far either way, and how fast.
const FRIGHT_X: f32 = 0.8;
const FRIGHT_SHAKE: f32 = 0.015;
const FRIGHT_RAD_S: f32 = 30;
const SHIMMER_MOTES = 24;
/// Stake (horizontal position, lean) pairs in cell units.
const PIN_STAKES = [_][2]f32{ .{ 0.24, -0.06 }, .{ 0.5, 0 }, .{ 0.76, 0.06 } };
const PIN_H: f32 = 0.16;
const PIN_FOOT: f32 = 0.92;
/// A ward's ring, out from the body's middle in cells.
const WARD_R: f32 = 0.46;
/// Its breathing.
const WARD_RAD_S: f32 = 2.4;
/// Where across a body's cell chill's flakes and burn's flames begin, and how far they spread.
const MARKS_FROM: f32 = 0.22;
const MARKS_SPAN: f32 = 0.56;

/// `jitter` is a fraction of the gap between headings.
fn ringDir(rng: *mathx.Rng, i: usize, n: usize, jitter: f32) [2]f32 {
    return heading((@as(f32, @floatFromInt(i)) + rng.unit() * jitter) * mathx.TAU / @as(f32, @floatFromInt(n)));
}

pub const FRIGHT_WORDS = [_][:0]const u8{ "Eek!", "Ah!", "[snorts]", "[squeals]" };
pub const SPEECH_S: f32 = 1.1;
/// Its last seconds, fading out.
pub const SPEECH_FADE_S: f32 = 0.4;
/// Cells over the body's head it starts, and how far it rises by its end.
const SPEECH_LIFT: f32 = 0.04;
const SPEECH_RISE: f32 = 0.3;

const Speech = struct {
    after: ?usize = null,
    life: f32 = 0,
    word: usize = 0,
};

pub const LEVEL_UP_S: f32 = 2;
const LEVEL_UP_TEXT = "Level up!";
/// Seconds the effect, and each glint, takes to show; and the effect, and the shaft, to fade.
const LEVEL_IN_S: f32 = 0.12;
const LEVEL_OUT_S: f32 = 0.65;
/// Seconds after the gain the shaft is gone.
const SHAFT_S: f32 = 1.55;
const LEVEL_GLOW = Glow{ .radius = 2.5, .gain = 0.65, .life = LEVEL_UP_S };
/// The body's added light at its peak.
const LEVEL_BODY_GAIN: f32 = 0.18;
const LEVEL_GLINTS = 18;
/// Spreads the glints evenly: the golden ratio's fraction, and the golden angle.
const GOLDEN_FRACTION: f32 = 0.618034;
const GOLDEN_ANGLE: f32 = 2.399963;
/// A glint this bright flashes a cross, at this share of its alpha.
const GLINT_FLASH: f32 = 0.85;
const GLINT_CROSS_A: f32 = 0.65;

pub const LevelUp = struct {
    life: f32 = 0,

    fn age(self: LevelUp) f32 {
        return LEVEL_UP_S - self.life;
    }

    fn alpha(self: LevelUp) f32 {
        return std.math.clamp(self.age() / LEVEL_IN_S, 0, 1) * std.math.clamp(self.life / LEVEL_OUT_S, 0, 1);
    }

    pub fn bodyGlow(self: LevelUp) [3]f32 {
        const gain = self.alpha() * LEVEL_BODY_GAIN;
        return sky.splat(gain) * @as(sky.Rgb, look.LEVEL_BODY_TINT);
    }

    pub fn emission(self: LevelUp, at: [2]f32) ?light.Emission {
        const gain = self.alpha() * LEVEL_GLOW.gain;
        if (gain <= 0) return null;
        return .{ .at = .{ at[0], at[1], light.BODY_Z }, .col = look.LEVEL_GOLD, .radius = LEVEL_GLOW.radius, .gain = gain };
    }

    pub fn drawBeam(self: LevelUp, at: [2]f32, ox: f32, oy: f32, cell: f32) void {
        if (self.life <= 0) return;
        const a = self.alpha() * std.math.clamp((SHAFT_S - self.age()) / LEVEL_OUT_S, 0, 1);
        const base = screen(.{ at[0], at[1], -0.28 }, ox, oy, cell);
        const h: i32 = @intFromFloat(@max(0, base.y));
        if (h == 0 or a <= 0) return;
        const bands = [_]struct { width: f32, alpha: f32 }{
            .{ .width = 0.48, .alpha = 0.025 },
            .{ .width = 0.32, .alpha = 0.045 },
            .{ .width = 0.19, .alpha = 0.08 },
            .{ .width = 0.09, .alpha = 0.14 },
            .{ .width = 0.025, .alpha = 0.35 },
        };
        for (bands) |band| {
            const w: i32 = @intFromFloat(@max(1, cell * band.width));
            rl.drawRectangleGradientV(@as(i32, @intFromFloat(base.x)) - @divTrunc(w, 2), 0, w, h, look.fade(look.LEVEL_GOLD, a * band.alpha * 0.1), look.fade(look.LEVEL_CORE, a * band.alpha));
        }
    }

    pub fn drawSparks(self: LevelUp, at: [2]f32, ox: f32, oy: f32, cell: f32) void {
        if (self.life <= 0) return;
        const k = pxScale(cell);
        for (0..LEVEL_GLINTS) |i| {
            const seed: f32 = @floatFromInt(i);
            const phase = @mod(seed * GOLDEN_FRACTION, 1);
            const t = @max(0, self.age() - phase * 0.3);
            const theta = seed * GOLDEN_ANGLE + t * 0.3;
            const radius = 0.22 + phase * 0.24 + t * 0.12;
            const spark = screen(.{
                at[0] + @cos(theta) * radius,
                at[1] + @sin(theta) * radius * 0.45,
                0.1 + phase * 0.4 + t * (0.45 + phase * 0.4),
            }, ox, oy, cell);
            const shine = @max(0, @sin(t * 7 + seed * 1.7));
            const a = self.alpha() * std.math.clamp(t / LEVEL_IN_S, 0, 1) * (0.4 + shine * 0.6);
            pixel.fleck(spark, 0.7 + phase * 0.45, k, look.fade(look.LEVEL_GOLD, a));
            if (shine > GLINT_FLASH) {
                pixel.cross(spark, 3, k, look.fade(look.LEVEL_CORE, a * GLINT_CROSS_A));
            }
        }
    }

    pub fn drawText(self: LevelUp, at: [2]f32, face: *const font.Face, ox: f32, oy: f32, cell: f32) void {
        if (self.life <= 0) return;
        const top = screen(.{ at[0], at[1], 0.85 + self.age() * 0.25 }, ox, oy, cell);
        const x: i32 = @intFromFloat(top.x);
        const y: i32 = @intFromFloat(top.y);
        const size: i32 = @intFromFloat(pxScale(cell) * font.HEAD);
        face.engravedMid(LEVEL_UP_TEXT, x, y, size, look.fade(look.LEVEL_CORE, self.alpha()));
    }
};

pub const Fx = struct {
    level_up: LevelUp = .{},
    arcs: [ARCS]Arc = @splat(.{}),
    arc_head: usize = 0,
    pulses: [PULSES]Pulse = @splat(.{}),
    pulse_head: usize = 0,
    ripples: [RIPPLES]Ripple = @splat(.{}),
    ripple_head: usize = 0,
    motes: [MOTES]Mote = @splat(.{ .p = @splat(0), .v = @splat(0), .r = 0, .col = rl.Color.blank }),
    head: usize = 0,
    impacts: impact_queue.Queue = .{},
    speech: [actor.MAX]Speech = @splat(.{}),
    rng: mathx.Rng = mathx.Rng.init(0xF1A5),
    seconds: mathx.Seconds = .{},

    pub fn clear(self: *Fx) void {
        self.level_up = .{};
        for (&self.arcs) |*a| a.life = 0;
        for (&self.pulses) |*p| p.life = 0;
        for (&self.motes) |*m| m.life = 0;
        for (&self.ripples) |*r| r.t = RIPPLE_S;
        self.impacts.clear();
        self.speech = @splat(.{});
    }

    pub fn levelUp(self: *Fx) void {
        self.level_up = .{ .life = LEVEL_UP_S };
    }

    pub fn frighten(self: *Fx, slot: usize, fallen: usize) void {
        self.speech[slot].after = fallen;
    }

    pub fn react(self: *Fx, bodies: []const Body) void {
        for (self.speech[0..bodies.len], bodies) |*s, b| {
            if (b.down()) {
                s.* = .{};
                continue;
            }
            const fallen = s.after orelse continue;
            if (!bodies[fallen].down()) continue;
            s.* = .{ .life = SPEECH_S, .word = @intCast(self.rng.below(FRIGHT_WORDS.len)) };
        }
    }

    pub fn drawSpeech(self: *const Fx, face: *const font.Face, slot: usize, x: i32, y: i32, cell: f32, sight: f32) void {
        const s = self.speech[slot];
        if (s.life <= 0) return;
        const age = 1 - s.life / SPEECH_S;
        const size: i32 = @intFromFloat(pxScale(cell) * font.SMALL);
        const cx = x + @as(i32, @intFromFloat(cell * 0.5));
        const top = y - size - @as(i32, @intFromFloat(cell * (SPEECH_LIFT + age * SPEECH_RISE)));
        face.textMid(FRIGHT_WORDS[s.word], cx, top, size, look.fade(look.TEXT, sight * @min(1, s.life / SPEECH_FADE_S)));
    }

    /// Schedule a resolved blow `wait` seconds ahead.
    pub fn strike(self: *Fx, wait: f32, b: Blow) void {
        self.later(wait, .{ .blow = b });
    }

    pub fn sting(self: *Fx, wait: f32, s: Sting) void {
        self.later(wait, .{ .sting = s });
    }

    pub fn settle(self: *Fx, wait: f32, s: Settle) void {
        self.later(wait, .{ .settle = s });
    }

    pub fn burst(self: *Fx, wait: f32, b: Burst) void {
        self.later(wait, .{ .burst = b });
    }

    pub fn zap(self: *Fx, wait: f32, z: Zap) void {
        self.later(wait, .{ .zap = z });
    }

    pub fn puff(self: *Fx, wait: f32, p: Puff) void {
        self.later(wait, .{ .puff = p });
    }

    pub fn shimmerIn(self: *Fx, wait: f32, s: Shimmer) void {
        self.later(wait, .{ .shimmer = s });
    }

    pub fn sweep(self: *Fx, wait: f32, at: [2]f32) void {
        self.later(wait, .{ .whirl = at });
    }

    fn later(self: *Fx, wait: f32, what: impact_queue.Event) void {
        if (self.impacts.schedule(wait, what)) |ready| self.fire(ready.event, ready.late);
    }

    fn fire(self: *Fx, what: impact_queue.Event, late: f32) void {
        switch (what) {
            .blow => |b| self.land(b),
            .burst => |b| self.spill(b),
            .zap => |z| self.arc(z),
            .puff => |p| self.wisps(p),
            .shimmer => |s| self.shimmer(s.at, s.col),
            .whirl => |at| self.whirl(at),
            .settle => |s| if (s.puff) |p| self.wisps(p),
            .sting => |s| {
                if (s.fire_at) |at| self.embers(at);
                if (s.drip) |d| self.drip(d);
                if (s.puff) |p| self.wisps(p);
            },
        }
        self.impacts.land(what, late);
    }
    /// A status glow's gain, wavering out of step with others by `phase`.
    pub fn statusFlicker(self: *const Fx, phase: f32) f32 {
        return 1 - STATUS_FLICKER + STATUS_FLICKER * @sin(self.seconds.at() * STATUS_FLICKER_RAD_S + phase);
    }

    pub fn step(self: *Fx, lv: *const grid.Level, dt: f32) void {
        self.seconds.step(dt);
        self.level_up.life = @max(0, self.level_up.life - dt);
        for (&self.arcs) |*a| a.life = @max(0, a.life - dt);
        for (&self.pulses) |*p| p.life = @max(0, p.life - dt);
        for (&self.ripples) |*r| r.t = @min(RIPPLE_S, r.t + dt);
        self.impacts.advance(dt);
        for (&self.speech) |*s| s.life = @max(0, s.life - dt);
        for (&self.motes) |*m| advance(m, lv, dt);
        var ready = self.impacts.ready();
        while (ready.next()) |event| self.fire(event.event, event.late);
    }

    fn land(self: *Fx, b: Blow) void {
        const at = mathx.centre(b.impact.at());
        if (b.fire) self.embers(at);
        self.emit(.{ .p = .{ at[0], at[1], STRIKE_Z }, .v = .{ 0, 0, 0 }, .life = CONTACT_S, .r = CONTACT_R * (if (b.impact.lethal()) KILL_POP else 1), .col = look.CONTACT, .add = true });
        const s = sprayOf(b.matter);
        self.spray(at, b.dir, s, if (b.impact.lethal()) s.kill else s.hit);
    }

    fn spray(self: *Fx, at: [2]f32, dir: ?[2]f32, s: Spray, n: usize) void {
        const rng = &self.rng;
        for (0..n) |_| {
            const d = dir orelse heading(rng.unit() * mathx.TAU);
            const along = rng.between(s.along_lo, s.along_hi);
            const across = rng.spread(2 * s.fan);
            self.emit(.{
                .p = .{ at[0], at[1], STRIKE_Z },
                .v = .{ d[0] * along - d[1] * across, d[1] * along + d[0] * across, rng.between(s.up_lo, s.up_hi) },
                .life = rng.between(s.life_lo, s.life_hi),
                .r = rng.between(s.r_lo, s.r_hi),
                .col = s.col,
                .grav = s.grav,
                .drag = s.drag,
                .bounce = s.bounce,
                .stains = s.stains,
                .add = s.add,
            });
        }
    }

    fn embers(self: *Fx, at: [2]f32) void {
        self.spray(at, null, EMBERS, EMBERS.hit);
        self.glow(at, look.FIRE, EMBER_GLOW);
    }

    pub fn glow(self: *Fx, at: [2]f32, col: rl.Color, g: Glow) void {
        claim(Pulse, &self.pulses, &self.pulse_head).* = .{ .source = .{ .at = .{ at[0], at[1], STRIKE_Z }, .col = col, .radius = g.radius, .gain = g.gain }, .life = g.life, .max = g.life };
    }

    pub fn trail(self: *Fx, lv: *const grid.Level, at: [2]f32, dir: [2]f32, act: skillbar.Act, age: f32) void {
        const m = flareOf(act.element()) orelse return;
        const life = m.trail_s;
        if (age >= life) return;
        const motes = missileOf(act).trail_r;
        advance(self.spawn(.{
            .p = .{ at[0] + self.rng.spread(0.08), at[1] + self.rng.spread(0.08), STRIKE_Z },
            .v = .{ -dir[0] * 0.8 + self.rng.spread(0.6), -dir[1] * 0.8 + self.rng.spread(0.6), m.rise },
            .life = life,
            .r = self.rng.between(motes[0], motes[1]),
            .col = look.arrowInk(act),
            .drag = 3,
            .add = m.add,
        }), lv, age);
    }

    pub fn shimmer(self: *Fx, at: [2]f32, col: rl.Color) void {
        for (0..SHIMMER_MOTES) |i| {
            const d = ringDir(&self.rng, i, SHIMMER_MOTES, 0.6);
            self.emit(.{ .p = .{ at[0] + d[0] * 0.3, at[1] + d[1] * 0.18, self.rng.between(0, 0.65) }, .v = .{ d[0] * 0.45, d[1] * 0.3, self.rng.between(0.4, 0.9) }, .life = self.rng.between(0.25, 0.5), .r = self.rng.between(0.7, 1.7), .col = col, .drag = 2, .add = true });
        }
        self.glow(at, col, SHIMMER_GLOW);
    }

    fn drip(self: *Fx, d: Drip) void {
        const s = sprayOf(d.matter);
        const at = d.at;
        for (0..DRIP_MOTES) |_| {
            self.emit(.{
                .p = .{ at[0] + self.rng.spread(0.4), at[1] + self.rng.spread(0.2), self.rng.between(STRIKE_Z, STRIKE_Z + 0.2) },
                .v = .{ self.rng.spread(0.3), self.rng.spread(0.3), 0 },
                .life = s.life_hi,
                .r = self.rng.between(s.r_lo, s.r_hi),
                .col = s.col,
                .grav = s.grav,
                .drag = s.drag,
                .stains = true,
            });
        }
    }

    /// Slow, soft and swelling as they rise; a bigger puff spreads wider.
    fn wisps(self: *Fx, p: Puff) void {
        const ink = look.fade(p.ink, WISP_A);
        const wide = @sqrt(@as(f32, @floatFromInt(p.motes)) / @as(f32, @floatFromInt(TICK_WISPS)));
        for (0..p.motes) |i| {
            const d = ringDir(&self.rng, i, p.motes, 0.8);
            const out = self.rng.between(0.12, 0.4) * wide;
            self.emit(.{
                .p = .{ p.at[0] + d[0] * 0.2, p.at[1] + d[1] * 0.12, self.rng.between(0.1, 0.55) },
                .v = .{ d[0] * out, d[1] * out * 0.6, self.rng.between(0.2, 0.45) },
                .life = self.rng.between(0.55, 0.9),
                .r = self.rng.between(2.5, 4.5),
                .col = ink,
                .drag = 1.6,
                .terrain = false,
                .grow = 0.9,
                .vapor = true,
            });
        }
    }

    /// A status's mark over a body whose cell's top-left is `m.x`, `m.y`.
    pub fn drawStatus(self: *const Fx, s: Status, m: Mark) void {
        const mark = markOf(s) orelse return;
        mark(self, m);
    }

    /// Null for a status shown only on the hud; `Status.marked` must agree.
    fn markOf(s: Status) ?*const fn (*const Fx, Mark) void {
        return switch (s) {
            .bleeding => &drawBleeding,
            .burning => &markBurning,
            .chilled => &drawChilled,
            .pinned => &drawPinned,
            .shocked => &drawShocked,
            .sundered => &drawSundered,
            .blinded => &drawBlinded,
            .confused => &drawConfused,
            .enfeebled => &drawEnfeebled,
            .maimed => &drawMaimed,
            .frightened => &drawFrightened,
            .warded => &drawWarded,
            .resistant, .guarding, .unyielding, .steady, .overwatch => null,
        };
    }

    fn markBurning(self: *const Fx, m: Mark) void {
        self.drawBurning(m.x, m.y, m.cell, m.seed, m.alpha);
    }

    /// Each glow pulse's light as it stands, faded by its age.
    pub fn pulseLights(self: *const Fx, buf: *[PULSES]light.Emission) []const light.Emission {
        var n: usize = 0;
        for (&self.pulses) |*p| {
            if (p.life <= 0) continue;
            buf[n] = p.source;
            buf[n].gain *= p.life / p.max;
            n += 1;
        }
        return buf[0..n];
    }

    fn drawBleeding(self: *const Fx, m: Mark) void {
        const x, const y, const cell, const seed, const ink = .{ m.x, m.y, m.cell, m.seed, m.ink };
        const t = self.seconds.at();
        for (0..BLEED_DROPS) |i| {
            const phase = @as(f32, @floatFromInt(i)) / BLEED_DROPS;
            const age = @mod(t * 0.9 + phase + @as(f32, @floatFromInt(seed)) * 0.23, 1);
            const at = rl.Vector2{ .x = x + cell * (0.3 + phase * 0.4), .y = y + cell * (0.45 + age * 0.4) };
            const r = look.SPRITE_PX * (0.022 + age * 0.012);
            pixel.rect(at, r, r * 1.8, pxScale(cell), look.fade(ink, (1 - age * age) * 0.9));
        }
    }

    fn spill(self: *Fx, b: Burst) void {
        const from = mathx.centre(b.at);
        const s = flareOf(b.element) orelse return;
        const col = look.elementInk(b.element);
        self.glow(from, col, s.burst);
        for (b.area.slice()) |p| {
            const to = mathx.centre(p);
            for (0..burstMotes(b.area.n)) |_| {
                const life = self.rng.between(0.22, 0.4);
                self.emit(.{
                    .p = .{ to[0] + self.rng.spread(0.5), to[1] + self.rng.spread(0.5), STRIKE_Z },
                    .v = .{ (to[0] - from[0]) * 0.25, (to[1] - from[1]) * 0.25, self.rng.between(0, 0.3) },
                    .life = life,
                    .r = self.rng.between(0.8, 2.8),
                    .col = col,
                    .add = s.add,
                });
            }
        }
    }

    fn arc(self: *Fx, z: Zap) void {
        const a = claim(Arc, &self.arcs, &self.arc_head);
        a.life = ARC_S;
        const span = mathx.len(z.to[0] - z.from[0], z.to[1] - z.from[1]);
        const across: [2]f32 = if (span > 0) .{ -(z.to[1] - z.from[1]) / span, (z.to[0] - z.from[0]) / span } else .{ 0, 0 };
        const segments: usize = @intFromFloat(std.math.clamp(@round(span / ARC_STEP), 1, ARC_POINTS - 1));
        a.n = segments + 1;
        for (a.points[0..a.n], 0..) |*p, i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments));
            const off = if (i == 0 or i == segments) 0 else self.rng.spread(ARC_JITTER);
            const on = mathx.lerp2(z.from, z.to, t);
            p.* = .{ on[0] + across[0] * off, on[1] + across[1] * off };
        }
        const glows: usize = @intFromFloat(@max(1, @round(span / ARC_GLOW_EVERY)));
        for (0..glows) |i| self.glow(mathx.lerp2(z.from, z.to, (@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(glows))), look.LIGHTNING, ARC_GLOW);
        const len = @max(1, span);
        const count: usize = @intFromFloat(@ceil(len * ZAP_MOTES));
        for (0..count) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
            const on = mathx.lerp2(z.from, z.to, t);
            self.emit(.{
                .p = .{ on[0] + self.rng.spread(ZAP_JITTER), on[1] + self.rng.spread(ZAP_JITTER), STRIKE_Z },
                .v = .{ self.rng.spread(2.8), self.rng.spread(2.8), self.rng.between(0.3, 1.3) },
                .life = 0.12 + t * 0.1,
                .r = self.rng.between(0.6, 1.6),
                .col = look.LIGHTNING,
                .add = true,
                .terrain = false,
            });
        }
    }

    fn drawChilled(self: *const Fx, m: Mark) void {
        const x, const y, const cell, const seed, const ink = .{ m.x, m.y, m.cell, m.seed, m.ink };
        const t = self.seconds.at() + @as(f32, @floatFromInt(seed));
        for (0..CHILL_FLAKES) |i| {
            const phase = @as(f32, @floatFromInt(i)) / CHILL_FLAKES;
            const cx = x + cell * (MARKS_FROM + phase * MARKS_SPAN);
            const cy = y + cell * (0.75 + @sin(t * 2 + phase * mathx.TAU) * 0.06);
            const across = @as(f32, look.SPRITE_PX) * 0.07;
            const col = look.fade(ink, 0.7 + @sin(t * 3 + phase) * 0.2);
            pixel.cross(.{ .x = cx, .y = cy }, across, pxScale(cell), col);
        }
    }

    /// Stakes driven in round its feet.
    fn drawPinned(_: *const Fx, m: Mark) void {
        const x, const y, const cell, const ink = .{ m.x, m.y, m.cell, m.ink };
        for (PIN_STAKES) |s| {
            const foot = rl.Vector2{ .x = x + cell * s[0], .y = y + cell * PIN_FOOT };
            const top = rl.Vector2{ .x = foot.x + cell * s[1], .y = foot.y - cell * PIN_H };
            pixel.line(top, foot, 2, pxScale(cell), ink);
        }
    }

    /// A ring round it, breathing.
    fn drawWarded(self: *const Fx, m: Mark) void {
        const x, const y, const cell, const ink = .{ m.x, m.y, m.cell, m.ink };
        const breath = @sin(self.seconds.at() * WARD_RAD_S);
        const r = cell * (WARD_R + breath * 0.02);
        for (0..WARD_DOTS) |i| {
            const a = @as(f32, @floatFromInt(i)) * mathx.TAU / WARD_DOTS;
            const k = 0.35 + 0.25 * @sin(a * 3 + self.seconds.at() * 2);
            pixel.rect(.{ .x = x + cell * 0.5 + @cos(a) * r, .y = y + cell * 0.5 + @sin(a) * r }, 1, 2, pxScale(cell), look.fade(ink, k));
        }
    }

    /// Sparks flickering across it.
    fn drawShocked(self: *const Fx, m: Mark) void {
        const x, const y, const cell, const seed, const ink = .{ m.x, m.y, m.cell, m.seed, m.ink };
        const t = self.seconds.at() * SHOCK_HZ + @as(f32, @floatFromInt(seed)) * 0.37;
        const k = pxScale(cell);
        const arm = cell * 0.05;
        for (0..SHOCK_SPARKS) |i| {
            const phase = @as(f32, @floatFromInt(i)) / SHOCK_SPARKS;
            if (@mod(t + phase * 3.7, 1) > 0.45) continue;
            const at = rl.Vector2{ .x = x + cell * (MARKS_FROM + phase * MARKS_SPAN), .y = y + cell * (0.35 + @mod(phase * 2.3 + @floor(t) * 0.17, 0.4)) };
            const bend = rl.Vector2{ .x = at.x + arm * 0.3, .y = at.y };
            pixel.line(.{ .x = at.x - arm, .y = at.y - arm }, bend, 1, k, ink);
            pixel.line(bend, .{ .x = at.x - arm * 0.3, .y = at.y + arm * 1.2 }, 1, k, ink);
        }
    }

    /// A crack across its middle for each stack.
    fn drawSundered(_: *const Fx, m: Mark) void {
        const x, const y, const cell, const stacks, const ink = .{ m.x, m.y, m.cell, m.stacks, m.ink };
        const k = pxScale(cell);
        for (0..stacks) |i| {
            const cx = x + cell * (0.3 + @as(f32, @floatFromInt(i)) * 0.2);
            const top = y + cell * 0.45;
            const mid = rl.Vector2{ .x = cx + cell * 0.04, .y = top + cell * 0.08 };
            pixel.line(.{ .x = cx, .y = top }, mid, 1, k, ink);
            pixel.line(mid, .{ .x = cx - cell * 0.02, .y = top + cell * 0.16 }, 1, k, ink);
        }
    }

    /// A shut eye over its head.
    fn drawBlinded(_: *const Fx, m: Mark) void {
        const x, const y, const cell, const ink = .{ m.x, m.y, m.cell, m.ink };
        const k = pxScale(cell);
        const lid = y + cell * HALO_Y;
        pixel.line(.{ .x = x + cell * 0.38, .y = lid }, .{ .x = x + cell * 0.62, .y = lid }, 1, k, ink);
        for ([_]f32{ 0.42, 0.5, 0.58 }) |across| pixel.line(.{ .x = x + cell * across, .y = lid }, .{ .x = x + cell * across, .y = lid + cell * 0.04 }, 1, k, ink);
    }

    /// Dots circling over its head.
    fn drawConfused(self: *const Fx, m: Mark) void {
        const x, const y, const cell, const seed, const ink = .{ m.x, m.y, m.cell, m.seed, m.ink };
        const t = self.seconds.at() * 3 + @as(f32, @floatFromInt(seed));
        for (0..CONFUSION_DOTS) |i| {
            const a = t + @as(f32, @floatFromInt(i)) * mathx.TAU / CONFUSION_DOTS;
            const at = rl.Vector2{ .x = x + cell * (0.5 + @cos(a) * HALO_R), .y = y + cell * (HALO_Y + @sin(a) * HALO_R * 0.35) };
            pixel.rect(at, 2, 2, pxScale(cell), look.fade(ink, 0.65 + 0.3 * @sin(a)));
        }
    }

    /// A chevron sinking beside its head.
    fn drawEnfeebled(self: *const Fx, m: Mark) void {
        const x, const y, const cell, const seed, const ink = .{ m.x, m.y, m.cell, m.seed, m.ink };
        const k = pxScale(cell);
        const sink = @mod(self.seconds.at() * ENFEEBLE_HZ + @as(f32, @floatFromInt(seed)) * 0.31, 1);
        const tip = rl.Vector2{ .x = x + cell * ENFEEBLE_X, .y = y + cell * (HALO_Y + 0.08 + sink * 0.08) };
        const arm = cell * 0.05;
        const col = look.fade(ink, 0.9 - sink * 0.5);
        pixel.line(.{ .x = tip.x - arm, .y = tip.y - arm }, tip, 1, k, col);
        pixel.line(tip, .{ .x = tip.x + arm, .y = tip.y - arm }, 1, k, col);
    }

    /// A bent bar at its feet, the leg it favours.
    fn drawMaimed(_: *const Fx, m: Mark) void {
        const x, const y, const cell, const ink = .{ m.x, m.y, m.cell, m.ink };
        const k = pxScale(cell);
        const foot = y + cell * PIN_FOOT;
        const knee = rl.Vector2{ .x = x + cell * 0.3, .y = foot - cell * 0.1 };
        pixel.line(.{ .x = x + cell * 0.24, .y = foot }, knee, 2, k, ink);
        pixel.line(knee, .{ .x = x + cell * 0.38, .y = foot - cell * 0.04 }, 2, k, ink);
    }

    /// A trembling mark beside its head.
    fn drawFrightened(self: *const Fx, m: Mark) void {
        const x, const y, const cell, const seed, const ink = .{ m.x, m.y, m.cell, m.seed, m.ink };
        const k = pxScale(cell);
        const shake = @sin(self.seconds.at() * FRIGHT_RAD_S + @as(f32, @floatFromInt(seed))) * FRIGHT_SHAKE;
        const top = rl.Vector2{ .x = x + cell * (FRIGHT_X + shake), .y = y + cell * HALO_Y };
        pixel.rect(top, 2, 6, k, ink);
        pixel.rect(.{ .x = top.x, .y = top.y + 6 * k }, 2, 2, k, ink);
    }

    pub fn drawBurning(self: *const Fx, x: f32, y: f32, cell: f32, seed: usize, alpha: f32) void {
        const t = self.seconds.at();
        for (0..BURN_FLAMES) |i| {
            const phase = @as(f32, @floatFromInt(i)) / BURN_FLAMES;
            const age = flameAge(t, phase, @as(f32, @floatFromInt(seed)) * 0.17);
            const sway = @sin(t * 6 + phase * mathx.TAU) * 0.04;
            const at = rl.Vector2{ .x = x + cell * (MARKS_FROM + phase * MARKS_SPAN + sway), .y = y + cell * (0.82 - age * 0.65) };
            const r = look.SPRITE_PX * (0.065 - age * 0.045);
            pixel.fleck(at, r, pxScale(cell), look.fade(Status.burning.ink(), (1 - age) * 0.85 * alpha));
            pixel.rect(at, r, r * 1.5, pxScale(cell), look.fade(look.FIRE_CORE, (1 - age) * 0.9 * alpha));
        }
    }

    pub fn drawTorch(self: *const Fx, x: f32, y: f32, cell: f32, seed: f32, lit: f32, memory: f32) void {
        const k = pxScale(cell);
        pixel.rect(.{ .x = x, .y = y + 7 * k }, 3, 12, k, look.fade(look.SPLINTER, memory * 0.7));
        pixel.rect(.{ .x = x, .y = y + k }, 7, 3, k, look.fade(look.TORCH_DIM, memory));
        const t = self.seconds.at();
        for (0..TORCH_FLAMES) |i| {
            const f: f32 = @floatFromInt(i);
            const age = flameAge(t, f / TORCH_FLAMES, seed);
            const p = rl.Vector2{ .x = x + @sin(t * 7 + f * 3 + seed) * (1 + age * 2) * k, .y = y - age * TORCH_RISE_PX * k };
            pixel.fleck(p, TORCH_FLECK_PX - age * 2.8, k, look.fade(look.FIRE, (1 - age) * lit));
            pixel.rect(p, 2 - age, 3 - age * 2, k, look.fade(look.FIRE_CORE, (1 - age) * lit));
        }
    }

    fn footfallCount(self: *Fx, bounds: [2]u32) usize {
        return @intCast(self.rng.range(@intCast(bounds[0]), @intCast(bounds[1])));
    }

    /// Somewhere on a footfall's ring, at least `near` of the way out, and the way out to it.
    fn footSpot(self: *Fx, at: [2]f32, near: f32) struct { dir: [2]f32, p: [3]f32 } {
        const dir = heading(self.rng.unit() * mathx.TAU);
        const out = self.rng.between(near, 1);
        return .{ .dir = dir, .p = .{ at[0] + dir[0] * SPLASH_R * out, at[1] + SPLASH_FOOT + dir[1] * SPLASH_RY * out, 0.02 } };
    }

    pub fn splash(self: *Fx, at: [2]f32) void {
        for (0..self.footfallCount(WATER_MOTES)) |_| {
            const spot = self.footSpot(at, 0.6);
            const dir = spot.dir;
            self.emit(.{
                .p = spot.p,
                .v = .{ dir[0] * self.rng.between(0.25, 0.8), dir[1] * self.rng.between(0.05, 0.3), self.rng.between(0.8, 1.7) },
                .life = self.rng.between(0.24, 0.4),
                .r = if (self.rng.chance(0.6)) self.rng.between(0.9, 1.3) else self.rng.between(1.4, 2),
                .col = look.fade(look.WATER_DROP, self.rng.between(0.6, 1)),
                .grav = 9,
                .drag = 2,
            });
        }
        claim(Ripple, &self.ripples, &self.ripple_head).* = .{ .at = .{ at[0], at[1] + SPLASH_FOOT }, .t = 0 };
    }

    pub fn dust(self: *Fx, at: [2]f32, col: rl.Color) void {
        for (0..self.footfallCount(STEP_DUST)) |_| {
            const spot = self.footSpot(at, 0.5);
            const dir = spot.dir;
            self.emit(.{
                .p = spot.p,
                .v = .{ dir[0] * self.rng.between(0.2, 0.6), dir[1] * self.rng.between(0.05, 0.25), self.rng.between(0.15, 0.4) },
                .life = self.rng.between(0.35, 0.55),
                .r = self.rng.between(1.2, 2.2),
                .col = look.fade(col, self.rng.between(0.55, 1)),
                .drag = 4,
                .grow = self.rng.between(0.6, 1.2),
            });
        }
    }

    /// A sweep's swing: streaks turning round the sweeper, the first gone first, and dust kicked off the ground.
    fn whirl(self: *Fx, at: [2]f32) void {
        for (0..WHIRL_MOTES) |i| {
            const k = @as(f32, @floatFromInt(i)) / WHIRL_MOTES;
            const d = heading(k * mathx.TAU);
            const r = WHIRL_R + self.rng.spread(0.06);
            self.emit(.{
                .p = .{ at[0] + d[0] * r, at[1] + d[1] * r * WHIRL_FLAT, self.rng.between(0.15, 0.45) },
                .v = .{ -d[1] * WHIRL_SPEED, d[0] * WHIRL_SPEED * WHIRL_FLAT, 0 },
                .life = WHIRL_S * (0.35 + k * 0.65),
                .r = self.rng.between(1.2, 2.2),
                .col = look.SWEEP,
                .drag = 3,
                .terrain = false,
            });
        }
        self.dustRing(at, .{ .r = WHIRL_R, .flat = WHIRL_FLAT, .speed = .{ 0.6, 1.8 }, .rise = .{ 0.2, 0.7 }, .life = .{ WHIRL_S * 0.6, WHIRL_S * 1.2 } });
    }

    /// Dust kicked out round `at`, from `r` cells out, its ring `flat` as tall as wide.
    fn dustRing(self: *Fx, at: [2]f32, ring: struct { r: f32, flat: f32 = 1, speed: [2]f32, rise: [2]f32, life: [2]f32 }) void {
        for (0..DUST_MOTES) |i| {
            const d = ringDir(&self.rng, i, DUST_MOTES, 1);
            const speed = self.rng.between(ring.speed[0], ring.speed[1]);
            self.emit(.{
                .p = .{ at[0] + d[0] * ring.r, at[1] + d[1] * ring.r * ring.flat, 0.04 },
                .v = .{ d[0] * speed, d[1] * speed * ring.flat, self.rng.between(ring.rise[0], ring.rise[1]) },
                .life = self.rng.between(ring.life[0], ring.life[1]),
                .r = self.rng.between(JUKE_R[0], JUKE_R[1]),
                .col = look.JUKE_DUST,
                .grav = 2,
                .drag = 3,
            });
        }
    }

    pub fn juke(self: *Fx, from: mathx.P, to: mathx.P) void {
        const a = mathx.centre(from);
        const b = mathx.centre(to);
        const count = @as(usize, @intCast(mathx.dist(from, to))) * TRAIL_MOTES;
        for (0..count) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
            const on = mathx.lerp2(a, b, t);
            self.emit(.{
                .p = .{ on[0], on[1], self.rng.between(0.15, 0.5) },
                .v = .{ 0, 0, 0.12 },
                .life = 0.18 + t * 0.16,
                .r = self.rng.between(JUKE_R[0], JUKE_R[1]),
                .col = look.JUKE_TRAIL,
                .terrain = false,
            });
        }
        self.dustRing(b, .{ .r = 0.28, .speed = .{ 0.8, 2.6 }, .rise = .{ 0.3, 1 }, .life = .{ JUKE_S / 2, JUKE_S } });
    }

    fn emit(self: *Fx, m: Mote) void {
        _ = self.spawn(m);
    }

    fn spawn(self: *Fx, m: Mote) *Mote {
        const slot = claim(Mote, &self.motes, &self.head);
        slot.* = m;
        slot.max = m.life;
        return slot;
    }

    /// Draw before lighting/fog; stains precede airborne motes.
    pub fn draw(self: *const Fx, ox: f32, oy: f32, cell: f32) void {
        const k = pxScale(cell);
        for (&self.ripples) |r| {
            const ring = r.ring() orelse continue;
            const x = ox + (@round(r.at[0] * look.SPRITE_PX) + 0.5) * k;
            const y = oy + (@round(r.at[1] * look.SPRITE_PX) + 0.5) * k;
            var dots: [RIPPLE_RINGS * ringDotsMax()]Dot = undefined;
            const col = look.fade(look.RIPPLE, ring.a);
            for (rippleDots(ring.r, &dots)) |d| {
                pixel.rect(.{ .x = x + @as(f32, @floatFromInt(d.x)) * k, .y = y + @as(f32, @floatFromInt(d.y)) * k }, 1, 1, k, col);
            }
        }
        for (&self.motes) |*m| {
            if (m.life <= 0 or !m.landed) continue;
            const a = m.life / (m.max * STAIN_FADE);
            const s = screen(m.p, ox, oy, cell);
            pixel.rect(s, m.r * STAIN_W * 2, m.r * STAIN_H * 2, k, look.fade(m.col, a));
        }
        for (&self.motes, 0..) |*m, i| {
            if (m.life <= 0 or m.landed or m.add) continue;
            const a = if (m.stains) 1 else m.life / (m.max * FLY_FADE);
            const age = 1 - m.life / m.max;
            const at = screen(m.p, ox, oy, cell);
            const r = m.r * (1 + m.grow * age);
            if (m.vapor) {
                pixel.haze(at, r, k, @as(f32, @floatFromInt(i)) * 1.7 + age * 1.2, look.fade(m.col, a));
            } else {
                pixel.fleck(at, r, k, look.fade(m.col, a));
            }
        }
    }

    pub fn drawGlow(self: *const Fx, lv: *const grid.Level, sight: *const [grid.CELLS]f32, ox: f32, oy: f32, cell: f32) void {
        const k = pxScale(cell);
        for (&self.motes) |*m| {
            if (m.life <= 0 or !m.add) continue;
            const p = mathx.cellOf(.{ m.p[0], m.p[1] });
            if (!lv.isLit(p)) continue;
            const t = m.life / m.max;
            const alpha = t * grid.cellOr(f32, sight, p, 0);
            const at = screen(m.p, ox, oy, cell);
            pixel.fleck(at, m.r * (0.5 + t * 0.5), k, look.fade(m.col, alpha));
            if (m.r >= 2) pixel.rect(at, 1, 1, k, look.fade(look.FIRE_CORE, alpha));
        }
        for (&self.arcs) |*a| {
            if (a.life <= 0) continue;
            for (a.points[1..a.n], a.points[0 .. a.n - 1], 0..) |p, from, i| {
                if (!lv.isLit(mathx.cellOf(p)) or !lv.isLit(mathx.cellOf(from))) continue;
                const alpha = @min(1, a.life / (ARC_S * 0.5)) * grid.cellOr(f32, sight, mathx.cellOf(p), 0);
                const v = projected(from, ox, oy, cell);
                const w = projected(p, ox, oy, cell);
                pixel.gridLine(v, w, .{ ox, oy }, k, look.fade(look.LIGHTNING_CORE, alpha), i > 0);
                if (i % ARC_FORK == ARC_FORK / 2) {
                    const tip = rl.Vector2{ .x = w.x + (w.y - v.y) * 1.8, .y = w.y - (w.x - v.x) * 1.8 };
                    const at = mathx.cellOf(unprojected(tip, ox, oy, cell));
                    if (lv.isLit(at) and grid.clearLine(lv, mathx.cellOf(p), at)) pixel.gridLine(w, tip, .{ ox, oy }, k, look.fade(look.LIGHTNING, alpha), true);
                }
            }
        }
    }
};

fn ringDotsMax() usize {
    return ringSteps(RIPPLE_R[1]);
}

/// Angles round a ring of radius `r` sampled for its pixels, a few past one a pixel of its rim.
fn ringSteps(r: f32) usize {
    return @as(usize, @intFromFloat(@ceil(mathx.TAU * r))) + 4;
}

const RING_STEPS_MIN = ringSteps(RIPPLE_R[0]);
/// Per step count, each step's cosine and sine, filled at run time so they match `@cos`/`@sin` there.
var ring_trig: [ringDotsMax() - RING_STEPS_MIN + 1][ringDotsMax()][2]f32 = undefined;
var ring_trig_ready = false;

fn ringTrig(steps: usize) []const [2]f32 {
    if (!ring_trig_ready) {
        for (&ring_trig, RING_STEPS_MIN..) |*row, n| {
            for (row[0..n], 0..) |*t, i| {
                const angle = @as(f32, @floatFromInt(i)) * mathx.TAU / @as(f32, @floatFromInt(n));
                t.* = .{ @cos(angle), @sin(angle) };
            }
        }
        ring_trig_ready = true;
    }
    return ring_trig[steps - RING_STEPS_MIN][0..steps];
}

/// The sprite pixels a ring of radius `r` passes through, each once.
fn ringDots(r: f32, out: *[ringDotsMax()][2]i32) []const [2]i32 {
    const steps = @min(out.len, ringSteps(r));
    var n: usize = 0;
    for (ringTrig(steps)) |t| {
        const d = [2]i32{ @intFromFloat(@round(t[0] * r)), @intFromFloat(@round(t[1] * r * RIPPLE_FLAT)) };
        if (n > 0 and (std.meta.eql(d, out[n - 1]) or std.meta.eql(d, out[0]))) continue;
        out[n] = d;
        n += 1;
    }
    return out[0..n];
}

const Dot = struct { x: i32, y: i32, ring: u8 };

fn touchesTaken(taken: *RippleGrid, x: i32, y: i32) bool {
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (rippleAt(taken, x + dx, y + dy).*) return true;
        }
    }
    return false;
}

const RIPPLE_HALF_W: i32 = @intFromFloat(@ceil(RIPPLE_R[1]) + 2);
const RIPPLE_HALF_H: i32 = @intFromFloat(@ceil(RIPPLE_R[1] * RIPPLE_FLAT) + 2);
const RippleGrid = [2 * RIPPLE_HALF_H + 1][2 * RIPPLE_HALF_W + 1]bool;

fn rippleAt(g: *RippleGrid, x: i32, y: i32) *bool {
    return &g[@intCast(y + RIPPLE_HALF_H)][@intCast(x + RIPPLE_HALF_W)];
}

/// A ripple's rings, outermost `outer` sprite pixels across; an inner ring drops any pixel touching one outside it.
fn rippleDots(outer: f32, out: *[RIPPLE_RINGS * ringDotsMax()]Dot) []const Dot {
    var taken: RippleGrid = @splat(@splat(false));
    var n: usize = 0;
    for (0..RIPPLE_RINGS) |i| {
        const r = outer - @as(f32, @floatFromInt(i)) * RIPPLE_GAP;
        if (r < RIPPLE_R[0]) break;
        var buf: [ringDotsMax()][2]i32 = undefined;
        const from = n;
        var here: RippleGrid = @splat(@splat(false));
        for (ringDots(r, &buf)) |d| {
            const mine = rippleAt(&here, d[0], d[1]);
            if (mine.* or touchesTaken(&taken, d[0], d[1])) continue;
            mine.* = true;
            out[n] = .{ .x = d[0], .y = d[1], .ring = @intCast(i) };
            n += 1;
        }
        for (out[from..n]) |d| rippleAt(&taken, d.x, d.y).* = true;
    }
    return out[0..n];
}

test "a ring's dots from the cached angles are the dots its own trig gives" {
    var buf: [ringDotsMax()][2]i32 = undefined;
    var radii: usize = 0;
    var r: f32 = RIPPLE_R[0];
    while (r <= RIPPLE_R[1]) : (r += 0.01) {
        const steps = @min(buf.len, ringSteps(r));
        var want: [ringDotsMax()][2]i32 = undefined;
        var n: usize = 0;
        for (0..steps) |i| {
            const angle = @as(f32, @floatFromInt(i)) * mathx.TAU / @as(f32, @floatFromInt(steps));
            const d = [2]i32{ @intFromFloat(@round(@cos(angle) * r)), @intFromFloat(@round(@sin(angle) * r * RIPPLE_FLAT)) };
            if (n > 0 and (std.meta.eql(d, want[n - 1]) or std.meta.eql(d, want[0]))) continue;
            want[n] = d;
            n += 1;
        }
        try std.testing.expectEqualSlices([2]i32, want[0..n], ringDots(r, &buf));
        radii += 1;
    }
    std.debug.print("ripple rings: {d} radii from cached angles match direct trig\n", .{radii});
}

fn projected(at: [2]f32, ox: f32, oy: f32, cell: f32) rl.Vector2 {
    return screen(.{ at[0], at[1], STRIKE_Z }, ox, oy, cell);
}

/// The ground point under a spot drawn at strike height, `projected`'s inverse.
fn unprojected(v: rl.Vector2, ox: f32, oy: f32, cell: f32) [2]f32 {
    return .{ (v.x - ox) / cell, (v.y - oy) / cell + STRIKE_Z };
}

const pxScale = look.pxScale;

fn flameAge(t: f32, phase: f32, seed: f32) f32 {
    return @mod(t * FLAME_HZ + phase + seed, 1);
}

/// By element: a trailed missile's light, how long the motes it sheds live and how fast they rise, the glow its
/// burst flashes, and whether its motes add light.
const Flare = struct { radius: f32, gain: f32, trail_s: f32, rise: f32, burst: Glow, add: bool };

const Missile = struct { trail_r: [2]f32 = .{ 0.7, 1.7 }, reach: ?f32 = null, ball: bool = false };
const FIREBALL = Missile{ .trail_r = .{ 1.5, 3.5 }, .reach = 2.8, .ball = true };

fn missileOf(act: skillbar.Act) Missile {
    return if (act == .fireball) FIREBALL else .{};
}

fn flareOf(element: ?damage.Element) ?Flare {
    return switch (element orelse return null) {
        .fire => .{ .radius = 1.6, .gain = 0.85, .trail_s = 0.24, .rise = 0.5, .burst = FIRE_BURST_GLOW, .add = true },
        .cold => .{ .radius = 1.6, .gain = 0.35, .trail_s = 0.18, .rise = 0.12, .burst = COLD_BURST_GLOW, .add = false },
        .chaos, .lightning => null,
    };
}

pub fn missileLight(at: [2]f32, act: skillbar.Act) ?light.Emission {
    const m = flareOf(act.element()) orelse return null;
    return .{
        .at = .{ at[0], at[1], STRIKE_Z },
        .col = look.arrowInk(act),
        .radius = missileOf(act).reach orelse m.radius,
        .gain = m.gain,
    };
}

pub fn drawMissile(at: [2]f32, dir: [2]f32, act: skillbar.Act, t: f32, ox: f32, oy: f32, cell: f32) void {
    if (act.element() == .lightning) return;
    const p = projected(at, ox, oy, cell);
    const k = pxScale(cell);
    const col = look.arrowInk(act);
    if (missileOf(act).ball) {
        for (0..6) |i| {
            const f: f32 = @floatFromInt(i);
            const w = rl.Vector2{ .x = p.x - dir[0] * f * 4 * k, .y = p.y - dir[1] * f * 4 * k + @sin(t * 65 + f * 2) * 2 * k };
            pixel.fleck(w, 5.5 - f * 0.7, k, look.fade(look.FIRE, 1 - f * 0.13));
        }
        pixel.fleck(p, 3, k, look.FIRE_CORE);
        pixel.rect(p, 2, 2, k, rl.Color.white);
        return;
    }
    drawArrow(p, dir, col, .{ ox, oy }, k);
}

const NET_SPIN: f32 = 14;
const NET_R: f32 = 8;

/// A thrown net: a square mesh tumbling as it flies.
pub fn drawNet(at: [2]f32, t: f32, ox: f32, oy: f32, cell: f32) void {
    const p = projected(at, ox, oy, cell);
    const k = pxScale(cell);
    const c = @cos(t * NET_SPIN);
    const s = @sin(t * NET_SPIN);
    const Mesh = struct {
        p: rl.Vector2,
        c: f32,
        s: f32,
        k: f32,
        fn knot(m: @This(), x: f32, y: f32) rl.Vector2 {
            return .{ .x = m.p.x + (x * m.c - y * m.s) * m.k, .y = m.p.y + (x * m.s + y * m.c) * m.k };
        }
    };
    const m = Mesh{ .p = p, .c = c, .s = s, .k = k };
    for ([_]f32{ -NET_R, 0, NET_R }) |o| {
        pixel.line(m.knot(-NET_R, o), m.knot(NET_R, o), 1, k, look.NET);
        pixel.line(m.knot(o, -NET_R), m.knot(o, NET_R), 1, k, look.NET);
    }
}

/// On the art-pixel grid `k` screen pixels a side from `origin`.
pub fn drawArrow(p: rl.Vector2, dir: [2]f32, col: rl.Color, origin: [2]f32, k: f32) void {
    const tail = rl.Vector2{ .x = p.x - dir[0] * 16 * k, .y = p.y - dir[1] * 16 * k };
    pixel.gridLine(tail, p, origin, k, look.SPLINTER, false);
    const back = rl.Vector2{ .x = p.x - dir[0] * 4 * k, .y = p.y - dir[1] * 4 * k };
    for ([_]f32{ -2, -1, 0, 1, 2 }) |side| {
        pixel.gridLine(p, .{ .x = back.x - dir[1] * side * k, .y = back.y + dir[0] * side * k }, origin, k, col, false);
    }
    const nock = rl.Vector2{ .x = tail.x + dir[0] * 4 * k, .y = tail.y + dir[1] * 4 * k };
    for ([_]f32{ -1, 1 }) |side| {
        const feather = rl.Vector2{ .x = tail.x - dir[1] * side * 3 * k, .y = tail.y + dir[0] * side * 3 * k };
        pixel.gridLine(feather, nock, origin, k, col, false);
    }
}

fn heading(a: f32) [2]f32 {
    return .{ @cos(a), @sin(a) };
}

fn screen(p: [3]f32, ox: f32, oy: f32, cell: f32) rl.Vector2 {
    return .{ .x = ox + p[0] * cell, .y = oy + (p[1] - p[2]) * cell };
}

fn advance(m: *Mote, lv: *const grid.Level, dt: f32) void {
    var left = dt;
    while (left > 0 and m.life > 0) : (left -= MOTE_STEP) tick(m, lv, @min(left, MOTE_STEP));
}

/// Airborne staining motes do not age, ensuring they leave a stain.
fn tick(m: *Mote, lv: *const grid.Level, dt: f32) void {
    if (m.life <= 0) return;
    if (!m.stains or m.landed) m.life -= dt;
    if (m.landed) return;
    const k = 1 / (1 + m.drag * dt);
    for (0..3) |i| m.p[i] += m.v[i] * dt;
    m.v[0] *= k;
    m.v[1] *= k;
    m.v[2] = m.v[2] * k - m.grav * dt;
    const cell = mathx.cellOf(.{ m.p[0], m.p[1] });
    if (m.terrain and !lv.flat(cell)) {
        m.life = 0;
        return;
    }
    if (m.p[2] > 0) return;
    if (m.terrain and !lv.walkable(cell)) {
        m.life = 0;
        return;
    }
    m.p[2] = 0;
    if (m.stains) {
        m.landed = true;
        m.life = STAIN_S;
        m.max = STAIN_S;
    } else if (m.bounce > 0 and m.v[2] < 0) {
        m.v[2] = -m.v[2] * m.bounce;
        m.v[0] *= SKID;
        m.v[1] *= SKID;
    } else {
        m.v[2] = 0;
    }
}

const Live = struct { flying: usize, stains: usize };

fn live(fx: *const Fx) Live {
    var out = Live{ .flying = 0, .stains = 0 };
    for (fx.motes) |m| {
        if (m.life <= 0 or m.add) continue;
        if (m.landed) out.stains += 1 else out.flying += 1;
    }
    return out;
}

const TEST_BLOW = Blow{ .impact = .{ .actor = .{ .slot = .fromIndex(3), .at = .{ .x = 20, .y = 20 }, .lethal = false } }, .dir = .{ 1, 0 }, .matter = .blood };

test "a status draws a mark over its body exactly when it is marked" {
    var marks: usize = 0;
    for (std.enums.values(Status)) |s| {
        try std.testing.expectEqual(s.marked(), Fx.markOf(s) != null);
        marks += @intFromBool(s.marked());
    }
    std.debug.print("status marks: {d} of {d} statuses draw one\n", .{ marks, std.enums.values(Status).len });
}

test "an arc kinks, strays and lights at the same spacing whatever its length" {
    var widest_gap: [2]f32 = .{ 1, 0 };
    var widest_stray: f32 = 0;
    for ([_][2]f32{ .{ 21.5, 20.5 }, .{ 24.5, 23.5 }, .{ 28.5, 28.5 }, .{ 20.5, 31.5 } }) |to| {
        var effects = Fx{};
        const z = Zap{ .from = .{ 20.5, 20.5 }, .to = to };
        effects.arc(z);
        const a = effects.arcs[0];
        const span = mathx.len(to[0] - z.from[0], to[1] - z.from[1]);
        try std.testing.expectEqualDeep(z.from, a.points[0]);
        try std.testing.expectEqualDeep(z.to, a.points[a.n - 1]);
        const step = span / @as(f32, @floatFromInt(a.n - 1));
        try std.testing.expect(@abs(step - ARC_STEP) < ARC_STEP * 0.15);
        for (a.points[0..a.n]) |p| {
            const stray = @abs((p[0] - z.from[0]) * (to[1] - z.from[1]) - (p[1] - z.from[1]) * (to[0] - z.from[0])) / span;
            try std.testing.expect(stray <= ARC_JITTER / 2 + 0.0001);
            widest_stray = @max(widest_stray, stray);
        }
        widest_gap = .{ @min(widest_gap[0], step), @max(widest_gap[1], step) };
        var lights: usize = 0;
        for (effects.pulses) |p| lights += @intFromBool(p.life > 0);
        try std.testing.expectEqual(@as(usize, @intFromFloat(@max(1, @round(span / ARC_GLOW_EVERY)))), lights);
    }
    std.debug.print("arcs from 1 to 11 cells: kinks {d:.3} to {d:.3} cells apart, straying at most {d:.3} cells, a light every ~{d} cells\n", .{ widest_gap[0], widest_gap[1], widest_stray, ARC_GLOW_EVERY });
}

test "a delayed effect starts its particles and light together after a long frame" {
    const lv = grid.openFloor();
    var effects = Fx{};
    effects.zap(0.2, .{ .from = .{ 20.5, 20.5 }, .to = .{ 24.5, 20.5 } });
    effects.step(&lv, 0.4);
    var particles: usize = 0;
    for (effects.motes) |m| {
        if (m.life > 0) particles += 1;
    }
    try std.testing.expect(particles > 0);
    try std.testing.expectEqual(ARC_S, effects.arcs[0].life);
    try std.testing.expectEqual(ARC_S, effects.pulses[0].life);
    effects.step(&lv, 1);
    for (effects.motes) |m| try std.testing.expect(m.life <= 0);
    try std.testing.expectEqual(@as(f32, 0), effects.arcs[0].life);
    try std.testing.expectEqual(@as(f32, 0), effects.pulses[0].life);
    std.debug.print("delayed effect: {d} particles start with arc and light after a 400 ms frame; all expire\n", .{particles});
}

test "electrical particles move between tiles and delayed arcs and light expire together" {
    const lv = grid.openFloor();
    var effects = Fx{};
    effects.zap(0.1, .{ .from = .{ 20.5, 20.5 }, .to = .{ 24.5, 20.5 } });
    effects.step(&lv, 0.05);
    try std.testing.expectEqual(@as(f32, 0), effects.arcs[0].life);
    effects.step(&lv, 0.05);
    try std.testing.expect(effects.arcs[0].life > 0 and effects.pulses[0].life > 0);
    const at = effects.motes[0].p;
    effects.step(&lv, 1.0 / 120.0);
    const moved = effects.motes[0].p;
    try std.testing.expect(!std.meta.eql(at, moved));
    try std.testing.expect(mathx.len(at[0] - moved[0], at[1] - moved[1]) < 0.05);
    effects.step(&lv, 1);
    for (effects.arcs) |a| try std.testing.expect(a.life <= 0);
    for (effects.pulses) |p| try std.testing.expect(p.life <= 0);
    for (effects.motes) |m| try std.testing.expect(m.life <= 0);
    std.debug.print("electric arc: delayed onset, sub-tile particle motion, all light and particles expired\n", .{});
}

fn footfallCounts(comptime emit_one: fn (*Fx) void, comptime bounds: [2]u32) !void {
    var effects = Fx{};
    var seen = [_]bool{false} ** (bounds[1] + 1);
    for (0..24) |_| {
        const before = live(&effects).flying;
        emit_one(&effects);
        const n = live(&effects).flying - before;
        try std.testing.expect(n >= bounds[0] and n <= bounds[1]);
        seen[n] = true;
        for (&effects.motes) |*m| m.life = 0;
    }
    try std.testing.expect(std.mem.count(bool, &seen, &.{true}) > 1);
}

test "water footsteps throw a varying few small drops that vanish without stains or flashes" {
    try footfallCounts(struct {
        fn one(f: *Fx) void {
            f.splash(.{ 20.5, 20.5 });
        }
    }.one, WATER_MOTES);
    for ([_]grid.Tile{ .shallows, .water }) |water| {
        var lv = grid.openFloor();
        lv.set(.{ .x = 20, .y = 20 }, water);
        var effects = Fx{};
        effects.splash(.{ 20.5, 20.5 });
        const n = live(&effects).flying;
        var peak: f32 = 0;
        var wide: f32 = 0;
        for (0..120) |_| {
            for (effects.motes) |m| {
                if (m.life <= 0) continue;
                try std.testing.expect(!m.stains and !m.add);
                try std.testing.expect(m.r <= 2 and m.col.a <= look.WATER_DROP.a);
                peak = @max(peak, m.p[2]);
                wide = @max(wide, @abs(m.p[0] - 20.5));
            }
            effects.step(&lv, mathx.TEST_DT);
        }
        try std.testing.expect(peak < 0.2 and wide < 0.55);
        try std.testing.expectEqual(@as(usize, 0), live(&effects).flying + live(&effects).stains);
        for (effects.impacts.flash) |f| try std.testing.expectEqual(@as(f32, 0), f);
        std.debug.print("water footsteps on {s}: {d} drops, peak {d:.3} cells up, {d:.3} cells out, no stains or flashes\n", .{ @tagName(water), n, peak, wide });
    }
}

test "water footsteps leave thin concentric rings a pixel apart that widen and fade, then vanish" {
    const lv = grid.openFloor();
    var effects = Fx{};
    effects.splash(.{ 20.5, 20.5 });
    var first: ?Ripple.Ring = null;
    var last_r: f32 = 0;
    var last_a: f32 = 1;
    var most: u8 = 0;
    var elapsed: f32 = 0;
    var dots: [RIPPLE_RINGS * ringDotsMax()]Dot = undefined;
    while (elapsed < RIPPLE_S + 0.1) : (elapsed += mathx.TEST_DT) {
        if (effects.ripples[0].ring()) |ring| {
            const all = rippleDots(ring.r, &dots);
            for (all, 0..) |d, i| {
                most = @max(most, d.ring + 1);
                for (all[0..i]) |e| {
                    const apart = @max(@abs(d.x - e.x), @abs(d.y - e.y));
                    try std.testing.expect(if (d.ring == e.ring) apart > 0 else apart >= 2);
                }
            }
            if (first == null) first = ring;
            try std.testing.expect(ring.r >= last_r and ring.a <= last_a);
            try std.testing.expect(ring.r <= RIPPLE_R[1]);
            last_r = ring.r;
            last_a = ring.a;
        }
        effects.step(&lv, mathx.TEST_DT);
    }
    try std.testing.expect(first != null and most == RIPPLE_RINGS);
    for (effects.ripples) |r| try std.testing.expect(r.ring() == null);
    std.debug.print("water ripples: up to {d} rings, outermost {d:.1} to {d:.1} sprite px across {d:.2} s, alpha {d:.2} to {d:.2}, {d} pixels at widest, none touching another ring\n", .{ most, first.?.r, last_r, RIPPLE_S, first.?.a, last_a, rippleDots(RIPPLE_R[1], &dots).len });
}

test "dust footsteps puff a varying few low motes, then vanish without stains" {
    try footfallCounts(struct {
        fn one(f: *Fx) void {
            f.dust(.{ 20.5, 20.5 }, look.DIRT_DUST);
        }
    }.one, STEP_DUST);
    var lv = grid.openFloor();
    var effects = Fx{};
    effects.dust(.{ 20.5, 20.5 }, look.DIRT_DUST);
    const n = live(&effects).flying;
    var peak: f32 = 0;
    var wide: f32 = 0;
    var biggest: f32 = 0;
    for (0..160) |_| {
        for (effects.motes) |m| {
            if (m.life <= 0) continue;
            try std.testing.expect(!m.stains and !m.add);
            peak = @max(peak, m.p[2]);
            wide = @max(wide, @abs(m.p[0] - 20.5));
            biggest = @max(biggest, m.r * (1 + m.grow * (1 - m.life / m.max)));
        }
        effects.step(&lv, mathx.TEST_DT);
    }
    try std.testing.expect(peak < 0.12 and wide < 0.5 and biggest <= 4.9);
    try std.testing.expectEqual(@as(usize, 0), live(&effects).flying + live(&effects).stains);
    std.debug.print("dust footsteps: {d} motes, peak {d:.3} cells up, {d:.3} cells out, widest {d:.1} sprite px\n", .{ n, peak, wide, biggest });
}

test "glacial frost waits for impact then fills only its cone and clears without stains" {
    const lv = grid.openFloor();
    var fx = Fx{};
    const at = mathx.P{ .x = 20, .y = 20 };
    const area = glacial.cone(&lv, .{ .x = 15, .y = 20 }, at);
    fx.burst(0.2, .{ .at = at, .area = area, .element = .cold });
    fx.step(&lv, 0.1);
    try std.testing.expectEqual(@as(usize, 0), live(&fx).flying);
    fx.step(&lv, 0.11);
    const n = live(&fx).flying;
    try std.testing.expectEqual(area.n * burstMotes(area.n), n);
    try std.testing.expect(nova.OPEN_CELLS * burstMotes(nova.OPEN_CELLS) <= BURST_MOTES);
    for (fx.motes) |m| {
        if (m.life <= 0) continue;
        try std.testing.expect(std.meta.eql(look.COLD, m.col));
        try std.testing.expect(area.has(mathx.cellOf(.{ m.p[0], m.p[1] })));
    }
    fx.step(&lv, 1);
    try std.testing.expectEqual(@as(usize, 0), live(&fx).flying + live(&fx).stains);
    std.debug.print("glacial frost: {d} motes delayed to impact, contained in the cone, gone without stains\n", .{n});
}

test "juke leaves a fading trail and landing dust without stains or damage flashes" {
    var lv = grid.openFloor();
    lv.set(.{ .x = 21, .y = 20 }, .water);
    var fx = Fx{};
    fx.juke(.{ .x = 20, .y = 20 }, .{ .x = 23, .y = 20 });
    const emitted = live(&fx).flying;
    try std.testing.expect(emitted > DUST_MOTES);
    fx.step(&lv, 0.1);
    var dust: usize = 0;
    var trail: usize = 0;
    for (fx.motes) |m| {
        if (m.life <= 0) continue;
        if (std.meta.eql(m.col, look.JUKE_DUST)) {
            dust += 1;
            try std.testing.expect(mathx.len(m.p[0] - 23.5, m.p[1] - 20.5) > 0.16);
        } else trail += 1;
    }
    try std.testing.expectEqual(3 * TRAIL_MOTES, trail);
    try std.testing.expectEqual(DUST_MOTES, dust);
    fx.step(&lv, 1);
    try std.testing.expectEqual(@as(usize, 0), live(&fx).flying + live(&fx).stains);
    for (fx.impacts.flash) |f| try std.testing.expectEqual(@as(f32, 0), f);
    std.debug.print("Juke effects: {d} trail motes, {d} landing dust motes, all gone after 1.1 s\n", .{ trail, dust });
}

test "a blow flashes its body for a beat and sprays blood a fraction of a cell, which lies a moment and is gone" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    fx.strike(0, TEST_BLOW);
    try std.testing.expectApproxEqAbs(impact_queue.FLASH_GAIN, fx.impacts.flashOf(.fromIndex(3)), 1e-6);
    try std.testing.expectEqual(@as(f32, 0), fx.impacts.flashOf(.fromIndex(2)));
    const dt = mathx.TEST_DT;
    var reach: f32 = 0;
    var ahead: usize = 0;
    var t: f32 = 0;
    var flash_gone: ?f32 = null;
    while (t < 3) : (t += dt) {
        fx.step(&lv, dt);
        if (flash_gone == null and fx.impacts.flashOf(.fromIndex(3)) == 0) flash_gone = t;
        for (fx.motes) |m| {
            if (m.life <= 0 or m.add) continue;
            reach = @max(reach, mathx.len(m.p[0] - mathx.centre(TEST_BLOW.impact.at())[0], m.p[1] - mathx.centre(TEST_BLOW.impact.at())[1]));
        }
        if (@abs(t - 0.7) < dt * 0.5) {
            for (fx.motes) |m| {
                if (m.landed and m.life > 0 and m.p[0] > mathx.centre(TEST_BLOW.impact.at())[0]) ahead += 1;
            }
            try std.testing.expectEqual(@as(usize, sprayOf(.blood).hit), live(&fx).stains);
        }
    }
    std.debug.print("blood: flash gone at {d:.3} s, spray reaches {d:.2} cells, {d} of {d} stains ahead of the blow, all gone by 3 s\n", .{ flash_gone.?, reach, ahead, sprayOf(.blood).hit });
    try std.testing.expectApproxEqAbs(FLASH_S, flash_gone.?, dt * 1.5);
    try std.testing.expect(reach > 0.15 and reach < 1.0);
    try std.testing.expect(ahead * 2 > sprayOf(.blood).hit);
    try std.testing.expectEqual(@as(usize, 0), live(&fx).flying + live(&fx).stains);
}

test "splinters bounce and leave no stain, and a mote that flies into a wall is gone" {
    var lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    var b = TEST_BLOW;
    b.matter = .wood;
    b.impact.actor.lethal = true;
    fx.strike(0, b);
    var bounced = false;
    var t: f32 = 0;
    while (t < 1.5) : (t += mathx.TEST_DT) {
        fx.step(&lv, mathx.TEST_DT);
        for (fx.motes) |m| {
            if (m.life > 0 and !m.add and m.p[2] == 0 and m.v[2] > 0) bounced = true;
        }
        try std.testing.expectEqual(@as(usize, 0), live(&fx).stains);
    }
    try std.testing.expect(bounced);
    var y: i32 = 15;
    while (y < 26) : (y += 1) lv.set(.{ .x = 21, .y = y }, .wall);
    b.matter = .blood;
    fx.strike(0, b);
    t = 0;
    while (t < 1) : (t += mathx.TEST_DT) fx.step(&lv, mathx.TEST_DT);
    for (fx.motes) |m| {
        if (m.life > 0 and !m.add) try std.testing.expect(m.p[0] < 21);
    }
    fx.clear();
    fx.strike(0, b);
    fx.step(&lv, 1.0);
    for (fx.motes) |m| {
        if (m.life > 0 and !m.add) try std.testing.expect(m.p[0] < 21);
    }
}

test "a drop flies on over water and leaves no stain where it falls in" {
    var lv = grid.openFloor();
    lv.set(.{ .x = 21, .y = 20 }, .water);
    lv.set(.{ .x = 22, .y = 20 }, .water);
    var m = Mote{ .p = .{ 20.5, 20.5, 0.5 }, .v = .{ 1.5, 0, 0 }, .life = 1, .r = 1, .col = rl.Color.red, .grav = 2, .stains = true };
    var over_water = false;
    var t: f32 = 0;
    while (m.life > 0 and t < 2) : (t += mathx.TEST_DT) {
        tick(&m, &lv, mathx.TEST_DT);
        if (m.life > 0 and m.p[2] > 0 and m.p[0] >= 21) over_water = true;
    }
    std.debug.print("a drop thrown off the bank flies to x {d:.2} and falls in\n", .{m.p[0]});
    try std.testing.expect(over_water);
    try std.testing.expect(!m.landed and m.life <= 0 and m.p[0] >= 21 and m.p[0] < 23);
}

test "a blow from nowhere sprays all round, not in one heap" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    var b = TEST_BLOW;
    b.dir = null;
    b.impact.actor.lethal = true;
    fx.strike(0, b);
    for (0..240) |_| fx.step(&lv, mathx.TEST_DT);
    var sum = [2]f32{ 0, 0 };
    var reach: f32 = 0;
    var n: f32 = 0;
    for (fx.motes) |m| {
        if (!m.landed or m.life <= 0) continue;
        const dx = m.p[0] - mathx.centre(b.impact.at())[0];
        const dy = m.p[1] - mathx.centre(b.impact.at())[1];
        sum = .{ sum[0] + dx, sum[1] + dy };
        reach = @max(reach, mathx.len(dx, dy));
        n += 1;
    }
    const drift = mathx.len(sum[0], sum[1]) / n;
    std.debug.print("a spray from nowhere: {d} stains out to {d:.2} cells, their middle {d:.2} cells off the blow\n", .{ n, reach, drift });
    try std.testing.expectEqual(@as(f32, @floatFromInt(sprayOf(.blood).kill)), n);
    try std.testing.expect(reach > 0.15);
    try std.testing.expect(drift < reach * 0.5);
}

test "a blow dealt now lands when the picture gets there" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    fx.strike(0.1, TEST_BLOW);
    fx.step(&lv, 0.05);
    try std.testing.expectEqual(@as(f32, 0), fx.impacts.flashOf(.fromIndex(3)));
    fx.step(&lv, 0.06);
    try std.testing.expect(fx.impacts.flashOf(.fromIndex(3)) > 0);
}

test "overdue flashes keep the latest impact time regardless of queue order" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.sting(0.12, .{ .slot = .fromIndex(3) });
    fx.strike(0.02, TEST_BLOW);
    fx.sting(0.08, .{ .slot = .fromIndex(3) });
    fx.step(&lv, 0.15);
    try std.testing.expectApproxEqAbs(FLASH_S - 0.03, fx.impacts.flash[3], 1e-6);
    fx.step(&lv, FLASH_S);
    try std.testing.expect(!fx.impacts.holds(.fromIndex(3)));
    fx.strike(-FLASH_S, TEST_BLOW);
    try std.testing.expect(!fx.impacts.holds(.fromIndex(3)));
    std.debug.print("flash timing: 3 unordered impacts and an overdue immediate blow checked\n", .{});
}

test "a sting flashes its body when the picture gets there and sprays nothing" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    fx.sting(0.1, .{ .slot = .fromIndex(3) });
    fx.step(&lv, 0.05);
    try std.testing.expectEqual(@as(f32, 0), fx.impacts.flashOf(.fromIndex(3)));
    fx.step(&lv, 0.06);
    try std.testing.expectApproxEqAbs(impact_queue.FLASH_GAIN, fx.impacts.flashOf(.fromIndex(3)), 0.1);
    try std.testing.expectEqual(@as(usize, 0), live(&fx).flying + live(&fx).stains);
    for (fx.motes) |m| try std.testing.expect(m.life <= 0);
}

test "a killed foe darkens as its death lands, then fades out; a hurt one and a dead hero do not" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    const body = Body{ .kind = .rat, .hp = 0, .max = 6, .seq = 1 };
    var kill = TEST_BLOW;
    kill.impact.actor.lethal = true;
    kill.impact.actor.after = .{ .body = body };
    fx.strike(0.1, kill);
    var hurt = TEST_BLOW;
    hurt.impact.actor.slot = .fromIndex(4);
    hurt.impact.actor.after = .{ .body = .{ .kind = .rat, .hp = 3, .max = 6, .seq = 1 } };
    fx.strike(0.1, hurt);
    fx.settle(0.1, .{ .slot = .fromIndex(0), .after = .{ .body = .{ .kind = .archer, .hp = 0, .max = 20, .seq = 1 } } });
    fx.step(&lv, 0.05);
    try std.testing.expectEqual(impact_queue.Dying{}, fx.impacts.dyingOf(.fromIndex(3)));
    const dt = mathx.TEST_DT;
    var dark_at: ?f32 = null;
    var gone_at: ?f32 = null;
    var t: f32 = 0.05;
    while (t < 1) {
        fx.step(&lv, dt);
        t += dt;
        if (dark_at == null and fx.impacts.dyingOf(.fromIndex(3)).dark >= 1) dark_at = t - 0.1;
        if (dark_at != null and gone_at == null and !fx.impacts.isDying(.fromIndex(3))) gone_at = t - 0.1;
        try std.testing.expectEqual(impact_queue.Dying{}, fx.impacts.dyingOf(.fromIndex(4)));
        try std.testing.expectEqual(impact_queue.Dying{}, fx.impacts.dyingOf(.fromIndex(0)));
    }
    std.debug.print("death fade: wholly dark {d:.3} s after landing, gone at {d:.3} s\n", .{ dark_at.?, gone_at.? });
    try std.testing.expectApproxEqAbs(impact_queue.DEATH_S * impact_queue.DEATH_DARKEN, dark_at.?, dt * 1.5);
    try std.testing.expectApproxEqAbs(impact_queue.DEATH_S, gone_at.?, dt * 1.5);
}
