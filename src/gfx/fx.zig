const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const damage = @import("../play/damage.zig");
const glacial = @import("../play/glacial.zig");
const burning = @import("../play/burning.zig");
const bleeding = @import("../play/bleeding.zig");
const pinning = @import("../play/pinning.zig");
const ward = @import("../play/ward.zig");
const look = @import("look.zig");
const font = @import("font.zig");
const menu = @import("../ui/menu.zig");
const skillbar = @import("../play/skillbar.zig");
const nova = @import("../play/nova.zig");
const pixel = @import("pixel.zig");
const light = @import("light.zig");

/// `ichor` is Brogue's purple blood.
pub const Matter = enum { blood, ooze, wood, ichor };

/// A body's, or a barrel's (null).
pub fn matterOf(kind: ?actor.Kind) Matter {
    const k = kind orelse return .wood;
    return switch (k) {
        .archer, .wizard, .knight, .rat, .pib, .beefy_pib, .bandit_crossbowman => .blood,
        .slime, .slime_half, .slime_quarter => .ooze,
        .bloat => .ichor,
    };
}

/// Longer flashes hold every turn containing a blow.
pub const FLASH_S: f32 = 0.16;
const FLASH_GAIN: f32 = 0.75;

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
const CONTACT = look.CONTACT;
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
};

pub const Blow = struct {
    /// The pool slot to flash; null for what has no body left to flash, a barrel.
    slot: ?usize,
    /// Cells, the middle of the struck cell on the ground.
    at: [2]f32,
    /// Unit travel direction; null scatters a directionless hit such as gas.
    dir: ?[2]f32,
    matter: Matter,
    lethal: bool,
    after: ?After = null,
    fire: bool = false,
};

const StatusGlow = struct { radius: f32, gain: f32 };
const BURN_GLOW = StatusGlow{ .radius = 2, .gain = 0.55 };
const WARD_GLOW = StatusGlow{ .radius = 1.5, .gain = 0.25 };
const STATUS_FLICKER: f32 = 0.1;
const STATUS_FLICKER_HZ: f32 = 11;

/// What a body suffers for turns, in the order the hud names them.
pub const Status = enum {
    bleeding,
    burning,
    chilled,
    pinned,
    warded,
    resistant,
    guarding,
    unyielding,
    steady,
    overwatch,

    pub fn ink(s: Status) rl.Color {
        return switch (s) {
            .bleeding => look.ailmentInk(.bleed),
            .burning => look.ailmentInk(.burn),
            .chilled => look.ailmentInk(.chill),
            .pinned => look.ailmentInk(.pin),
            .warded => look.WARD,
            .resistant => look.UI_GOLD,
            .guarding, .unyielding, .steady, .overwatch => look.UI_GOLD,
        };
    }

    /// The first status a body has, in this order, that glows lights it.
    pub fn glow(s: Status) ?StatusGlow {
        return switch (s) {
            .burning => BURN_GLOW,
            .warded => WARD_GLOW,
            .bleeding, .chilled, .pinned, .resistant, .guarding, .unyielding, .steady, .overwatch => null,
        };
    }

    pub fn emission(s: Status, at: [2]f32, flicker: f32) ?light.Emission {
        const g = s.glow() orelse return null;
        return .{ .at = .{ at[0], at[1], light.BODY_Z }, .col = s.ink(), .radius = g.radius, .gain = g.gain * flicker };
    }

    pub fn title(s: Status) [:0]const u8 {
        return switch (s) {
            .warded => skillbar.Act.mana_shield.name(),
            .resistant => "Status resistance",
            .guarding => skillbar.Act.guard.name(),
            .unyielding => skillbar.Act.unyielding.name(),
            .steady => skillbar.Act.steady_aim.name(),
            .overwatch => skillbar.Act.overwatch.name(),
            inline else => |t| comptime menu.capital(@tagName(t)),
        };
    }

    /// What it does to the body, as its tooltip says.
    pub fn about(s: Status) []const u8 {
        return switch (s) {
            .resistant => @import("../play/resilience.zig").ABOUT,
            .guarding => @import("../play/tactics.zig").Guard.DESCRIPTION,
            .unyielding => @import("../play/tactics.zig").Unyielding.DESCRIPTION,
            .steady => @import("../play/tactics.zig").SteadyAim.DESCRIPTION,
            .overwatch => @import("../play/tactics.zig").Overwatch.DESCRIPTION,
            inline else => |t| module(t).STATUS,
        };
    }

    fn module(comptime s: Status) type {
        return switch (s) {
            .bleeding => bleeding,
            .burning => burning,
            .chilled => glacial,
            .pinned => pinning,
            .warded => ward,
            .resistant => @import("../play/resilience.zig"),
            .guarding, .unyielding, .steady, .overwatch => @import("../play/tactics.zig"),
        };
    }

    fn field(comptime s: Status) []const u8 {
        return switch (s) {
            .bleeding => "bleed",
            .burning => "burn",
            .chilled => "chill",
            .pinned => "pin",
            .warded => "ward",
            .resistant => "resilience",
            .guarding, .unyielding, .steady, .overwatch => "tactics",
        };
    }

    fn turnsOf(s: Status, a: actor.Actor) u8 {
        return switch (s) {
            .resistant => a.resilience.peak().turns,
            .guarding => @intFromBool(a.tactics.guard > 0),
            .unyielding => @intFromBool(a.tactics.unyielding),
            .steady => @intFromBool(a.tactics.steady > 0),
            .overwatch => @intFromBool(a.tactics.overwatch != null),
            inline else => |t| @field(a, field(t)).turns,
        };
    }

    comptime {
        for (std.meta.fields(actor.Actor)) |f| {
            if (@typeInfo(f.type) != .@"struct" or !@hasField(f.type, "turns")) continue;
            var claimed = false;
            for (std.enums.values(Status)) |s| claimed = claimed or std.mem.eql(u8, field(s), f.name);
            if (!claimed) @compileError("fx.Status: no status shows Actor." ++ f.name);
        }
    }
};

/// Presented body state; `seq` preserves simulation hit order.
pub const Body = struct {
    kind: actor.Kind,
    hp: i32,
    max: i32,
    seq: u64,
    /// Turns left of each.
    status: std.EnumArray(Status, u8) = .initFill(0),
    resilience: @import("../play/resilience.zig").State = .{},

    pub fn of(a: actor.Actor, seq: u64) Body {
        var b = Body{ .kind = a.kind, .hp = a.hp, .max = a.max, .seq = seq };
        if (a.alive) {
            b.resilience = a.resilience;
            for (std.enums.values(Status)) |s| b.status.set(s, s.turnsOf(a));
        }
        return b;
    }

    pub fn hurt(self: Body) bool {
        return self.hp < self.max;
    }

    pub fn down(self: Body) bool {
        return self.hp <= 0;
    }
};

/// State at impact; `reveals` is the newly visible split-half pool slot.
pub const After = struct { body: Body, reveals: ?usize = null, mana: i32 = 0 };

pub const Drip = struct { at: [2]f32, matter: Matter };

pub const Sting = struct { slot: usize, after: ?After = null, fire_at: ?[2]f32 = null, drip: ?Drip = null };

/// A body changed by no seen blow, as a chill wearing off or a heal: it catches up unflashed.
pub const Settle = struct { slot: usize, after: After };

const MOTES: usize = 320;
/// Capacity for every body's turn effects, hero hit and sweep, plus a burst or chain jumps.
pub const DUE: usize = actor.MAX * (9 + actor.SWEEP_CELLS) + 2;

pub const Burst = struct { at: mathx.P, area: glacial.Burst, element: damage.Element };

pub const Zap = struct { from: [2]f32, to: [2]f32 };

const ARC_S: f32 = 0.18;
const ARC_POINTS = 25;
const Arc = struct {
    points: [ARC_POINTS][2]f32 = undefined,
    life: f32 = 0,
};

/// A brief light an effect casts: reach in cells, peak gain, and seconds to fade.
pub const Glow = struct { radius: f32, gain: f32, life: f32 };
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
/// Motes a cell of a zap's line.
const ZAP_MOTES: usize = 5;
/// How far a zap's motes stray off its line, in cells.
const ZAP_JITTER: f32 = 0.18;
const EMBERS = Spray{ .col = look.FIRE, .hit = 18, .kill = 18, .along_lo = 0.4, .along_hi = 1.4, .fan = 0, .up_lo = 0.5, .up_hi = 1.5, .grav = 0, .drag = 2, .life_lo = 0.25, .life_hi = 0.55, .r_lo = 1, .r_hi = 2.5, .stains = false, .add = true };
const DRIP_MOTES: usize = 5;
const WATER_MOTES: usize = 4;
/// Cells below a body's middle its splash rises from, and how far across and down it spreads.
pub const SPLASH_FOOT: f32 = 0.32;
pub const SPLASH_R: f32 = 0.22;
pub const SPLASH_RY: f32 = 0.08;
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
const SHIMMER_MOTES = 24;
/// Stake (horizontal position, lean) pairs in cell units.
const PIN_STAKES = [_][2]f32{ .{ 0.24, -0.06 }, .{ 0.5, 0 }, .{ 0.76, 0.06 } };
const PIN_H: f32 = 0.16;
const PIN_FOOT: f32 = 0.92;
/// A ward's ring, out from the body's middle in cells.
const WARD_R: f32 = 0.46;
/// Its breathing, radians a second.
const WARD_HZ: f32 = 2.4;
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

const Due = union(enum) {
    blow: Blow,
    sting: Sting,
    settle: Settle,
    burst: Burst,
    zap: Zap,

    fn on(d: *const Due) ?usize {
        return switch (d.*) {
            .blow => |*b| b.slot,
            .sting => |*s| s.slot,
            .settle => |*s| s.slot,
            .burst, .zap => null,
        };
    }

    fn blowOf(d: *const Due) ?*const Blow {
        return switch (d.*) {
            .blow => |*b| b,
            .sting, .settle, .burst, .zap => null,
        };
    }

    fn onBarrel(d: *const Due) bool {
        const b = d.blowOf() orelse return false;
        return b.slot == null;
    }

    fn after(d: *const Due) ?After {
        return switch (d.*) {
            .blow => |*b| b.after,
            .sting => |*s| s.after,
            .settle => |*s| s.after,
            .burst, .zap => null,
        };
    }
};

pub const LEVEL_UP_S: f32 = 2;
const LEVEL_UP_TEXT = "Level up!";
/// Seconds the effect, and each glint, takes to show; and the effect, and the shaft, to fade.
const LEVEL_IN_S: f32 = 0.12;
const LEVEL_OUT_S: f32 = 0.65;
/// Seconds after the gain the shaft is gone.
const SHAFT_S: f32 = 1.55;
const LEVEL_GLOW = Glow{ .radius = 2.5, .gain = 0.65, .life = LEVEL_UP_S };
/// The body's added light at its peak, and its colour.
const LEVEL_BODY_GAIN: f32 = 0.18;
const LEVEL_BODY_TINT = [3]f32{ 1, 0.72, 0.28 };
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
        return .{ gain * LEVEL_BODY_TINT[0], gain * LEVEL_BODY_TINT[1], gain * LEVEL_BODY_TINT[2] };
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
    arcs: [12]Arc = @splat(.{}),
    arc_head: usize = 0,
    pulses: [32]Pulse = @splat(.{}),
    pulse_head: usize = 0,
    motes: [MOTES]Mote = @splat(.{ .p = @splat(0), .v = @splat(0), .r = 0, .col = rl.Color.blank }),
    head: usize = 0,
    flash: [actor.MAX]f32 = @splat(0),
    due: [DUE]struct { t: f32, what: Due } = undefined,
    due_n: usize = 0,
    /// Of `due`, the blows on a barrel.
    barrels_due: usize = 0,
    /// Indexed by pool slot: the body as the latest-dealt of the blows landed on it left it.
    landed: [actor.MAX]?Body = @splat(null),
    mana_landed: i32 = 0,
    speech: [actor.MAX]Speech = @splat(.{}),
    rng: mathx.Rng = mathx.Rng.init(0xF1A5),
    seconds: mathx.Seconds = .{},

    pub fn clear(self: *Fx) void {
        self.level_up = .{};
        for (&self.arcs) |*a| a.life = 0;
        for (&self.pulses) |*p| p.life = 0;
        for (&self.motes) |*m| m.life = 0;
        self.flash = @splat(0);
        self.due_n = 0;
        self.barrels_due = 0;
        self.landed = @splat(null);
        self.mana_landed = 0;
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

    fn later(self: *Fx, wait: f32, what: Due) void {
        if (wait <= 0 or self.due_n == DUE) return self.fire(what, @max(0, -wait));
        self.due[self.due_n] = .{ .t = wait, .what = what };
        self.due_n += 1;
        if (what.onBarrel()) self.barrels_due += 1;
    }

    fn fire(self: *Fx, what: Due, late: f32) void {
        switch (what) {
            .blow => |b| self.land(b),
            .burst => |b| self.spill(b),
            .zap => |z| self.arc(z),
            .settle => {},
            .sting => |s| {
                if (s.fire_at) |at| self.embers(at);
                if (s.drip) |d| self.drip(d);
            },
        }
        const slot = what.on() orelse return;
        switch (what) {
            .blow, .sting => self.flash[slot] = @max(self.flash[slot], FLASH_S - late),
            .settle, .burst, .zap => {},
        }
        const a = what.after() orelse return;
        self.mana_landed += a.mana;
        if (self.landed[slot]) |was| {
            if (was.seq >= a.body.seq) return;
        }
        self.landed[slot] = a.body;
    }

    /// A blow, sting or settle is still to land on the slot.
    pub fn pending(self: *const Fx, slot: usize) bool {
        return self.landsIn(slot) > 0;
    }

    pub fn landedOn(self: *const Fx, slot: usize) ?Body {
        return self.landed[slot];
    }

    /// The blow that split the body in `slot` off another is still to land.
    pub fn revealing(self: *const Fx, slot: usize) bool {
        return self.revealsIn(slot) > 0;
    }

    /// Seconds until the blow that reveals the slot lands; 0 when none is due.
    pub fn revealsIn(self: *const Fx, slot: usize) f32 {
        var t: f32 = 0;
        for (self.due[0..self.due_n]) |*d| {
            const a = d.what.after() orelse continue;
            if (a.reveals == slot) t = @max(t, d.t);
        }
        return t;
    }

    pub fn holds(self: *const Fx, slot: usize) bool {
        return self.flash[slot] > 0 or self.pending(slot);
    }

    /// Seconds until the last blow, sting or settle due on the slot lands.
    pub fn landsIn(self: *const Fx, slot: usize) f32 {
        var t: f32 = 0;
        for (self.due[0..self.due_n]) |*d| {
            if (d.what.on() == slot) t = @max(t, d.t);
        }
        return t;
    }

    /// Seconds until the slot is held no longer: its last due landed and flashed.
    pub fn heldIn(self: *const Fx, slot: usize) f32 {
        const lands = self.landsIn(slot);
        const due = if (lands > 0) lands + FLASH_S else 0;
        return @max(self.flash[slot], due);
    }

    /// A status glow's gain, wavering out of step with others by `phase`.
    pub fn statusFlicker(self: *const Fx, phase: f32) f32 {
        return 1 - STATUS_FLICKER + STATUS_FLICKER * @sin(self.seconds.at() * STATUS_FLICKER_HZ + phase);
    }

    pub fn breaking(self: *const Fx, p: mathx.P) bool {
        if (self.barrels_due == 0) return false;
        for (self.due[0..self.due_n]) |*d| {
            if (d.what.onBarrel() and mathx.cellOf(d.what.blowOf().?.at).eq(p)) return true;
        }
        return false;
    }

    /// Eased out, so it holds near full before it fades.
    pub fn flashOf(self: *const Fx, slot: usize) f32 {
        const k = std.math.clamp(self.flash[slot] / FLASH_S, 0, 1);
        return FLASH_GAIN * k * (2 - k);
    }

    pub fn step(self: *Fx, lv: *const grid.Level, dt: f32) void {
        self.seconds.step(dt);
        self.level_up.life = @max(0, self.level_up.life - dt);
        for (&self.arcs) |*a| a.life = @max(0, a.life - dt);
        for (&self.pulses) |*p| p.life = @max(0, p.life - dt);
        for (&self.flash) |*f| f.* = @max(0, f.* - dt);
        for (&self.speech) |*s| s.life = @max(0, s.life - dt);
        for (&self.motes) |*m| advance(m, lv, dt);
        var i: usize = 0;
        while (i < self.due_n) {
            self.due[i].t -= dt;
            if (self.due[i].t > 0) {
                i += 1;
                continue;
            }
            const what = self.due[i].what;
            const late = -self.due[i].t;
            self.due_n -= 1;
            self.due[i] = self.due[self.due_n];
            if (what.onBarrel()) self.barrels_due -= 1;
            self.fire(what, late);
        }
    }

    fn land(self: *Fx, b: Blow) void {
        if (b.fire) self.embers(b.at);
        self.emit(.{ .p = .{ b.at[0], b.at[1], STRIKE_Z }, .v = .{ 0, 0, 0 }, .life = CONTACT_S, .r = CONTACT_R * (if (b.lethal) KILL_POP else 1), .col = CONTACT, .add = true });
        const s = sprayOf(b.matter);
        self.spray(b.at, b.dir, s, if (b.lethal) s.kill else s.hit);
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
        self.pulses[self.pulse_head] = .{ .source = .{ .at = .{ at[0], at[1], STRIKE_Z }, .col = col, .radius = g.radius, .gain = g.gain }, .life = g.life, .max = g.life };
        self.pulse_head = (self.pulse_head + 1) % self.pulses.len;
    }

    pub fn illuminate(self: *const Fx, lv: *const grid.Level, lamps: *light.Light) void {
        lamps.clearEffects();
        for (self.pulses) |p| {
            if (p.life <= 0) continue;
            var source = p.source;
            source.gain *= p.life / p.max;
            lamps.emit(lv, source);
        }
    }

    pub fn trail(self: *Fx, lv: *const grid.Level, at: [2]f32, dir: [2]f32, act: skillbar.Act, age: f32) void {
        const m = flareOf(act.element()) orelse return;
        const life = m.trail_s;
        if (age >= life) return;
        const slot = self.head;
        self.emit(.{
            .p = .{ at[0] + self.rng.spread(0.08), at[1] + self.rng.spread(0.08), STRIKE_Z },
            .v = .{ -dir[0] * 0.8 + self.rng.spread(0.6), -dir[1] * 0.8 + self.rng.spread(0.6), m.rise },
            .life = life,
            .r = if (act == .fireball) self.rng.between(1.5, 3.5) else self.rng.between(0.7, 1.7),
            .col = look.arrowInk(act),
            .drag = 3,
            .add = m.add,
        });
        advance(&self.motes[slot], lv, age);
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

    pub fn drawBleeding(self: *const Fx, x: f32, y: f32, cell: f32, seed: usize, ink: rl.Color) void {
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
        const a = &self.arcs[self.arc_head];
        self.arc_head = (self.arc_head + 1) % self.arcs.len;
        a.life = ARC_S;
        for (&a.points, 0..) |*p, i| {
            const t = @as(f32, @floatFromInt(i)) / (ARC_POINTS - 1);
            const spread: f32 = if (i == 0 or i == ARC_POINTS - 1) 0 else ZAP_JITTER;
            const on = mathx.lerp2(z.from, z.to, t);
            p.* = .{ on[0] + self.rng.spread(spread), on[1] + self.rng.spread(spread) };
        }
        for ([_]f32{ 0.25, 0.65, 1 }) |t| self.glow(mathx.lerp2(z.from, z.to, t), look.LIGHTNING, ARC_GLOW);
        const len = @max(1, mathx.len(z.to[0] - z.from[0], z.to[1] - z.from[1]));
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

    pub fn drawChilled(self: *const Fx, x: f32, y: f32, cell: f32, seed: usize, ink: rl.Color) void {
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
    pub fn drawPinned(_: *const Fx, x: f32, y: f32, cell: f32, ink: rl.Color) void {
        for (PIN_STAKES) |s| {
            const foot = rl.Vector2{ .x = x + cell * s[0], .y = y + cell * PIN_FOOT };
            const top = rl.Vector2{ .x = foot.x + cell * s[1], .y = foot.y - cell * PIN_H };
            pixel.line(top, foot, 2, pxScale(cell), ink);
        }
    }

    /// A ring round it, breathing.
    pub fn drawWarded(self: *const Fx, x: f32, y: f32, cell: f32, ink: rl.Color) void {
        const breath = @sin(self.seconds.at() * WARD_HZ);
        const r = cell * (WARD_R + breath * 0.02);
        for (0..WARD_DOTS) |i| {
            const a = @as(f32, @floatFromInt(i)) * mathx.TAU / WARD_DOTS;
            const k = 0.35 + 0.25 * @sin(a * 3 + self.seconds.at() * 2);
            pixel.rect(.{ .x = x + cell * 0.5 + @cos(a) * r, .y = y + cell * 0.5 + @sin(a) * r }, 1, 2, pxScale(cell), look.fade(ink, k));
        }
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

    pub fn splash(self: *Fx, at: [2]f32) void {
        for (0..WATER_MOTES) |i| {
            const dir = ringDir(&self.rng, i, WATER_MOTES, 0.5);
            self.emit(.{
                .p = .{ at[0] + dir[0] * SPLASH_R, at[1] + SPLASH_FOOT + dir[1] * SPLASH_RY, 0.025 },
                .v = .{ dir[0] * 0.55, dir[1] * 0.3, self.rng.between(0.45, 0.75) },
                .life = self.rng.between(0.24, 0.34),
                .r = self.rng.between(0.8, 1.3),
                .col = look.WATER_DROP,
                .grav = 5,
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
        for (0..DUST_MOTES) |i| {
            const dir = ringDir(&self.rng, i, DUST_MOTES, 1);
            const speed = self.rng.between(0.8, 2.6);
            self.emit(.{
                .p = .{ b[0] + dir[0] * 0.28, b[1] + dir[1] * 0.28, 0.04 },
                .v = .{ dir[0] * speed, dir[1] * speed, self.rng.between(0.3, 1) },
                .life = self.rng.between(JUKE_S / 2, JUKE_S),
                .r = self.rng.between(JUKE_R[0], JUKE_R[1]),
                .col = look.JUKE_DUST,
                .grav = 2,
                .drag = 3,
            });
        }
    }

    fn emit(self: *Fx, m: Mote) void {
        self.motes[self.head] = m;
        self.motes[self.head].max = m.life;
        self.head = (self.head + 1) % MOTES;
    }

    /// Draw before lighting/fog; stains precede airborne motes.
    pub fn draw(self: *const Fx, ox: f32, oy: f32, cell: f32) void {
        const k = pxScale(cell);
        for (&self.motes) |*m| {
            if (m.life <= 0 or !m.landed) continue;
            const a = m.life / (m.max * STAIN_FADE);
            const s = screen(m.p, ox, oy, cell);
            pixel.rect(s, m.r * STAIN_W * 2, m.r * STAIN_H * 2, k, look.fade(m.col, a));
        }
        for (&self.motes) |*m| {
            if (m.life <= 0 or m.landed or m.add) continue;
            const a = if (m.stains) 1 else m.life / (m.max * FLY_FADE);
            pixel.fleck(screen(m.p, ox, oy, cell), m.r, k, look.fade(m.col, a));
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
            for (a.points[1..], a.points[0 .. ARC_POINTS - 1], 0..) |p, from, i| {
                if (!lv.isLit(mathx.cellOf(p)) or !lv.isLit(mathx.cellOf(from))) continue;
                const alpha = @min(1, a.life / (ARC_S * 0.5)) * grid.cellOr(f32, sight, mathx.cellOf(p), 0);
                const v = projected(from, ox, oy, cell);
                const w = projected(p, ox, oy, cell);
                pixel.line(v, w, 3, k, look.fade(look.LIGHTNING, alpha * 0.28));
                pixel.line(v, w, 1, k, look.fade(look.LIGHTNING_CORE, alpha));
                if (i % 6 == 3) {
                    const tip = rl.Vector2{ .x = w.x + (w.y - v.y) * 1.8, .y = w.y - (w.x - v.x) * 1.8 };
                    const at = mathx.cellOf(unprojected(tip, ox, oy, cell));
                    if (lv.isLit(at) and grid.clearLine(lv, mathx.cellOf(p), at)) pixel.line(w, tip, 1, k, look.fade(look.LIGHTNING, alpha * 0.65));
                }
            }
        }
    }
};

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
/// burst flashes, and whether its motes add light; a fireball's light reaches further.
const Flare = struct { radius: f32, gain: f32, trail_s: f32, rise: f32, burst: Glow, add: bool };
const FIREBALL_REACH: f32 = 2.8;

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
        .radius = if (act == .fireball) FIREBALL_REACH else m.radius,
        .gain = m.gain,
    };
}

pub fn drawMissile(at: [2]f32, dir: [2]f32, act: skillbar.Act, t: f32, ox: f32, oy: f32, cell: f32) void {
    if (act.element() == .lightning) return;
    const p = projected(at, ox, oy, cell);
    const k = pxScale(cell);
    const col = look.arrowInk(act);
    if (act == .fireball) {
        for (0..6) |i| {
            const f: f32 = @floatFromInt(i);
            const w = rl.Vector2{ .x = p.x - dir[0] * f * 4 * k, .y = p.y - dir[1] * f * 4 * k + @sin(t * 65 + f * 2) * 2 * k };
            pixel.fleck(w, 5.5 - f * 0.7, k, look.fade(look.FIRE, 1 - f * 0.13));
        }
        pixel.fleck(p, 3, k, look.FIRE_CORE);
        pixel.rect(p, 2, 2, k, rl.Color.white);
        return;
    }
    drawArrow(p, dir, col, k);
}

pub fn drawArrow(p: rl.Vector2, dir: [2]f32, col: rl.Color, k: f32) void {
    const tail = rl.Vector2{ .x = p.x - dir[0] * 16 * k, .y = p.y - dir[1] * 16 * k };
    pixel.line(tail, p, 1, k, look.SPLINTER);
    const back = rl.Vector2{ .x = p.x - dir[0] * 4 * k, .y = p.y - dir[1] * 4 * k };
    for ([_]f32{ -2, -1, 0, 1, 2 }) |side| {
        pixel.line(p, .{ .x = back.x - dir[1] * side * k, .y = back.y + dir[0] * side * k }, 1, k, col);
    }
    const nock = rl.Vector2{ .x = tail.x + dir[0] * 4 * k, .y = tail.y + dir[1] * 4 * k };
    for ([_]f32{ -1, 1 }) |side| {
        const feather = rl.Vector2{ .x = tail.x - dir[1] * side * 3 * k, .y = tail.y + dir[0] * side * 3 * k };
        pixel.line(feather, nock, 1, k, col);
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

const TEST_BLOW = Blow{ .slot = 3, .at = .{ 20.5, 20.5 }, .dir = .{ 1, 0 }, .matter = .blood, .lethal = false };

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

test "water footsteps make a few small droplets that vanish without stains or flashes" {
    for ([_]grid.Tile{ .shallows, .water }) |water| {
        var lv = grid.openFloor();
        lv.set(.{ .x = 20, .y = 20 }, water);
        var effects = Fx{};
        effects.splash(.{ 20.5, 20.5 });
        const n = live(&effects).flying;
        try std.testing.expectEqual(WATER_MOTES, n);
        var peak: f32 = 0;
        for (0..120) |_| {
            for (effects.motes) |m| {
                if (m.life <= 0) continue;
                try std.testing.expect(!m.stains and !m.add);
                try std.testing.expect(m.r <= 1.5 and m.col.a <= look.WATER_DROP.a);
                peak = @max(peak, m.p[2]);
            }
            effects.step(&lv, mathx.TEST_DT);
        }
        try std.testing.expect(peak < 0.12);
        try std.testing.expectEqual(@as(usize, 0), live(&effects).flying + live(&effects).stains);
        for (effects.flash) |f| try std.testing.expectEqual(@as(f32, 0), f);
        std.debug.print("water footsteps on {s}: {d} small drops, peak {d:.3} cells, no stains or flashes\n", .{ @tagName(water), n, peak });
    }
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
    for (fx.flash) |f| try std.testing.expectEqual(@as(f32, 0), f);
    std.debug.print("Juke effects: {d} trail motes, {d} landing dust motes, all gone after 1.1 s\n", .{ trail, dust });
}

test "a blow flashes its body for a beat and sprays blood a fraction of a cell, which lies a moment and is gone" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    fx.strike(0, TEST_BLOW);
    try std.testing.expectApproxEqAbs(FLASH_GAIN, fx.flashOf(3), 1e-6);
    try std.testing.expectEqual(@as(f32, 0), fx.flashOf(2));
    const dt = mathx.TEST_DT;
    var reach: f32 = 0;
    var ahead: usize = 0;
    var t: f32 = 0;
    var flash_gone: ?f32 = null;
    while (t < 3) : (t += dt) {
        fx.step(&lv, dt);
        if (flash_gone == null and fx.flashOf(3) == 0) flash_gone = t;
        for (fx.motes) |m| {
            if (m.life <= 0 or m.add) continue;
            reach = @max(reach, mathx.len(m.p[0] - TEST_BLOW.at[0], m.p[1] - TEST_BLOW.at[1]));
        }
        if (@abs(t - 0.7) < dt * 0.5) {
            for (fx.motes) |m| {
                if (m.landed and m.life > 0 and m.p[0] > TEST_BLOW.at[0]) ahead += 1;
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
    b.lethal = true;
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
    b.lethal = true;
    fx.strike(0, b);
    for (0..240) |_| fx.step(&lv, mathx.TEST_DT);
    var sum = [2]f32{ 0, 0 };
    var reach: f32 = 0;
    var n: f32 = 0;
    for (fx.motes) |m| {
        if (!m.landed or m.life <= 0) continue;
        const dx = m.p[0] - b.at[0];
        const dy = m.p[1] - b.at[1];
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
    try std.testing.expectEqual(@as(f32, 0), fx.flashOf(3));
    fx.step(&lv, 0.06);
    try std.testing.expect(fx.flashOf(3) > 0);
}

test "overdue flashes keep the latest impact time regardless of queue order" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.sting(0.12, .{ .slot = 3 });
    fx.strike(0.02, TEST_BLOW);
    fx.sting(0.08, .{ .slot = 3 });
    fx.step(&lv, 0.15);
    try std.testing.expectApproxEqAbs(FLASH_S - 0.03, fx.flash[3], 1e-6);
    fx.step(&lv, FLASH_S);
    try std.testing.expect(!fx.holds(3));
    fx.strike(-FLASH_S, TEST_BLOW);
    try std.testing.expect(!fx.holds(3));
    std.debug.print("flash timing: 3 unordered impacts and an overdue immediate blow checked\n", .{});
}

test "a sting flashes its body when the picture gets there and sprays nothing" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    fx.sting(0.1, .{ .slot = 3 });
    fx.step(&lv, 0.05);
    try std.testing.expectEqual(@as(f32, 0), fx.flashOf(3));
    fx.step(&lv, 0.06);
    try std.testing.expectApproxEqAbs(FLASH_GAIN, fx.flashOf(3), 0.1);
    try std.testing.expectEqual(@as(usize, 0), live(&fx).flying + live(&fx).stains);
    for (fx.motes) |m| try std.testing.expect(m.life <= 0);
}
