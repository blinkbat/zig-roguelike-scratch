const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const actor = @import("../play/actor.zig");
const glacial = @import("../play/glacial.zig");
const look = @import("look.zig");

/// `ichor` is Brogue's purple blood.
pub const Matter = enum { blood, ooze, wood, ichor };

/// A body's, or a barrel's (null).
pub fn matterOf(kind: ?actor.Kind) Matter {
    const k = kind orelse return .wood;
    return switch (k) {
        .archer, .rat, .pib => .blood,
        .slime, .slime_half, .slime_quarter => .ooze,
        .bloat => .ichor,
    };
}

/// The flash's colour is `light.FLASH_RGB`, since the body shader draws it. Longer holds every turn with a blow in it.
pub const FLASH_S: f32 = 0.16;
pub const FLASH_GAIN: f32 = 0.75;

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
/// Seconds: a long frame moves the motes in steps this short, so none flies past a wall in one.
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
    /// Unit, the way the blow travelled; null for one from nowhere, the gas's, which sprays all round.
    dir: ?[2]f32,
    matter: Matter,
    lethal: bool,
    after: ?After = null,
    /// What a barrel breaks for, shown as the blow lands.
    gold: i32 = 0,
    fire: bool = false,
};

/// What a body suffers for turns, in the order the hud names them.
pub const Status = enum {
    bleeding,
    burning,
    chilled,

    pub fn caption(s: Status) [:0]const u8 {
        return switch (s) {
            .bleeding => "Bleeding",
            .burning => "Burning",
            .chilled => "Chilled",
        };
    }

    pub fn ink(s: Status) rl.Color {
        return switch (s) {
            .bleeding => look.BLEED,
            .burning => look.FIRE,
            .chilled => look.COLD,
        };
    }

    fn turnsOf(s: Status, a: actor.Actor) u8 {
        return switch (s) {
            .bleeding => a.bleed.turns,
            .burning => a.burn.turns,
            .chilled => a.chill.turns,
        };
    }
};

/// A body as the picture has it; `seq` is the order the simulation dealt the blows that left it so.
pub const Body = struct {
    kind: actor.Kind,
    hp: i32,
    max: i32,
    seq: u64,
    /// Turns left of each.
    status: std.EnumArray(Status, u8) = .initFill(0),

    pub fn of(a: actor.Actor, seq: u64) Body {
        var b = Body{ .kind = a.kind, .hp = a.hp, .max = a.max, .seq = seq };
        if (a.alive) {
            for (std.enums.values(Status)) |s| b.status.set(s, s.turnsOf(a));
        }
        return b;
    }

    pub fn hurt(self: Body) bool {
        return self.hp < self.max;
    }
};

/// What landing shows: the body as the blow left it, and the slot of one it split off, drawn from then.
pub const After = struct { body: Body, reveals: ?usize = null };

pub const Sting = struct { slot: usize, after: ?After = null, fire_at: ?[2]f32 = null, drip_at: ?[2]f32 = null };

/// A body changed by no blow, as a chill wearing off: it catches up unflashed.
pub const Settle = struct { slot: usize, after: After };

pub const MOTES: usize = 320;
/// A turn's worth: on every body, what its turn owes the picture and the archer's blow; then the frost and a barrel's blow.
pub const DUE: usize = actor.MAX * 6 + 2;

pub const Frost = struct { at: mathx.P, area: glacial.Cone };

pub const JUKE_S: f32 = 0.6;
const ICE_MOTES: usize = 12;
const TRAIL_MOTES: usize = 20;
const DUST_MOTES: usize = 24;

const Due = union(enum) {
    blow: Blow,
    sting: Sting,
    settle: Settle,
    frost: Frost,

    fn on(d: Due) ?usize {
        return switch (d) {
            .blow => |b| b.slot,
            .sting => |s| s.slot,
            .settle => |s| s.slot,
            .frost => null,
        };
    }

    fn after(d: Due) ?After {
        return switch (d) {
            .blow => |b| b.after,
            .sting => |s| s.after,
            .settle => |s| s.after,
            .frost => null,
        };
    }
};

pub const Fx = struct {
    motes: [MOTES]Mote = @splat(.{ .p = @splat(0), .v = @splat(0), .r = 0, .col = rl.Color.blank }),
    head: usize = 0,
    flash: [actor.MAX]f32 = @splat(0),
    due: [DUE]struct { t: f32, what: Due } = undefined,
    due_n: usize = 0,
    /// Of `due`, the blows on a barrel.
    barrels_due: usize = 0,
    /// Indexed by pool slot: the body as the latest-dealt of the blows landed on it left it.
    landed: [actor.MAX]?Body = @splat(null),
    rng: mathx.Rng = mathx.Rng.init(0xF1A5),
    seconds: mathx.Seconds = .{},

    pub fn clear(self: *Fx) void {
        for (&self.motes) |*m| m.life = 0;
        self.flash = @splat(0);
        self.due_n = 0;
        self.barrels_due = 0;
        self.landed = @splat(null);
    }

    /// `wait` seconds from now, when the picture reaches the blow the simulation already dealt.
    pub fn strike(self: *Fx, wait: f32, b: Blow) void {
        self.later(wait, .{ .blow = b });
    }

    pub fn sting(self: *Fx, wait: f32, s: Sting) void {
        self.later(wait, .{ .sting = s });
    }

    pub fn settle(self: *Fx, wait: f32, s: Settle) void {
        self.later(wait, .{ .settle = s });
    }

    pub fn frost(self: *Fx, wait: f32, f: Frost) void {
        self.later(wait, .{ .frost = f });
    }

    fn later(self: *Fx, wait: f32, what: Due) void {
        if (wait <= 0 or self.due_n == DUE) return self.fire(what);
        self.due[self.due_n] = .{ .t = wait, .what = what };
        self.due_n += 1;
        if (onBarrel(what)) self.barrels_due += 1;
    }

    fn onBarrel(what: Due) bool {
        return switch (what) {
            .blow => |b| b.slot == null,
            .sting, .settle, .frost => false,
        };
    }

    fn fire(self: *Fx, what: Due) void {
        switch (what) {
            .blow => |b| self.land(b),
            .frost => |f| self.ice(f),
            .settle => {},
            .sting => |s| {
                self.flash[s.slot] = FLASH_S;
                if (s.fire_at) |at| self.embers(at);
                if (s.drip_at) |at| self.drip(at);
            },
        }
        const slot = what.on() orelse return;
        const a = what.after() orelse return;
        if (self.landed[slot]) |was| {
            if (was.seq >= a.body.seq) return;
        }
        self.landed[slot] = a.body;
    }

    /// A blow or sting is still to land on the slot.
    pub fn pending(self: *const Fx, slot: usize) bool {
        for (self.due[0..self.due_n]) |d| {
            if (d.what.on() == slot) return true;
        }
        return false;
    }

    pub fn landedOn(self: *const Fx, slot: usize) ?Body {
        return self.landed[slot];
    }

    /// The blow that split the body in `slot` off another is still to land.
    pub fn revealing(self: *const Fx, slot: usize) bool {
        for (self.due[0..self.due_n]) |d| {
            const a = d.what.after() orelse continue;
            if (a.reveals == slot) return true;
        }
        return false;
    }

    pub fn holds(self: *const Fx, slot: usize) bool {
        return self.flash[slot] > 0 or self.pending(slot);
    }

    /// A blow is still to land on the barrel at `p`.
    pub fn breaking(self: *const Fx, p: mathx.P) bool {
        if (self.barrels_due == 0) return false;
        for (self.due[0..self.due_n]) |d| {
            switch (d.what) {
                .blow => |b| if (b.slot == null and mathx.cellOf(b.at).eq(p)) return true,
                .sting, .settle, .frost => {},
            }
        }
        return false;
    }

    /// Dealt, and not yet shown: its blow is still to land.
    pub fn goldDue(self: *const Fx) i32 {
        var n: i32 = 0;
        for (self.due[0..self.due_n]) |d| {
            switch (d.what) {
                .blow => |b| n += b.gold,
                .sting, .settle, .frost => {},
            }
        }
        return n;
    }

    /// Eased out, so it holds near full before it fades.
    pub fn flashOf(self: *const Fx, slot: usize) f32 {
        const k = std.math.clamp(self.flash[slot] / FLASH_S, 0, 1);
        return FLASH_GAIN * k * (2 - k);
    }

    pub fn step(self: *Fx, lv: *const grid.Level, dt: f32) void {
        self.seconds.step(dt);
        for (&self.flash) |*f| f.* = @max(0, f.* - dt);
        var i: usize = 0;
        while (i < self.due_n) {
            self.due[i].t -= dt;
            if (self.due[i].t > 0) {
                i += 1;
                continue;
            }
            const what = self.due[i].what;
            self.due_n -= 1;
            self.due[i] = self.due[self.due_n];
            if (onBarrel(what)) self.barrels_due -= 1;
            self.fire(what);
        }
        var left = dt;
        while (left > 0) : (left -= MOTE_STEP) {
            for (&self.motes) |*m| tick(m, lv, @min(left, MOTE_STEP));
        }
    }

    fn land(self: *Fx, b: Blow) void {
        if (b.fire) self.embers(b.at);
        if (b.slot) |s| self.flash[s] = FLASH_S;
        self.emit(.{ .p = .{ b.at[0], b.at[1], STRIKE_Z }, .v = .{ 0, 0, 0 }, .life = CONTACT_S, .r = CONTACT_R * (if (b.lethal) KILL_POP else 1), .col = CONTACT, .add = true });
        const s = sprayOf(b.matter);
        const rng = &self.rng;
        for (0..if (b.lethal) s.kill else s.hit) |_| {
            const dir = b.dir orelse heading(rng.unit() * mathx.TAU);
            const along = mathx.lerpF(s.along_lo, s.along_hi, rng.unit());
            const across = (rng.unit() * 2 - 1) * s.fan;
            self.emit(.{
                .p = .{ b.at[0], b.at[1], STRIKE_Z },
                .v = .{ dir[0] * along - dir[1] * across, dir[1] * along + dir[0] * across, mathx.lerpF(s.up_lo, s.up_hi, rng.unit()) },
                .life = mathx.lerpF(s.life_lo, s.life_hi, rng.unit()),
                .r = mathx.lerpF(s.r_lo, s.r_hi, rng.unit()),
                .col = s.col,
                .grav = s.grav,
                .drag = s.drag,
                .bounce = s.bounce,
                .stains = s.stains,
            });
        }
    }

    fn embers(self: *Fx, at: [2]f32) void {
        for (0..18) |_| {
            const dir = heading(self.rng.unit() * mathx.TAU);
            const speed = 0.4 + self.rng.unit();
            self.emit(.{
                .p = .{ at[0], at[1], STRIKE_Z },
                .v = .{ dir[0] * speed, dir[1] * speed, 0.5 + self.rng.unit() },
                .life = 0.25 + self.rng.unit() * 0.3,
                .r = 1.5 + self.rng.unit() * 2,
                .col = look.FIRE,
                .drag = 2,
            });
        }
    }

    fn drip(self: *Fx, at: [2]f32) void {
        const s = sprayOf(.blood);
        for (0..5) |_| {
            self.emit(.{
                .p = .{ at[0] + (self.rng.unit() - 0.5) * 0.4, at[1] + (self.rng.unit() - 0.5) * 0.2, STRIKE_Z + self.rng.unit() * 0.2 },
                .v = .{ (self.rng.unit() - 0.5) * 0.3, (self.rng.unit() - 0.5) * 0.3, 0 },
                .life = s.life_hi,
                .r = mathx.lerpF(s.r_lo, s.r_hi, self.rng.unit()),
                .col = s.col,
                .grav = s.grav,
                .drag = s.drag,
                .stains = true,
            });
        }
    }

    pub fn drawBleeding(self: *const Fx, x: f32, y: f32, cell: f32, seed: usize, ink: rl.Color) void {
        const t = self.seconds.at();
        for (0..4) |i| {
            const phase = @as(f32, @floatFromInt(i)) / 4;
            const age = @mod(t * 0.9 + phase + @as(f32, @floatFromInt(seed)) * 0.23, 1);
            const at = rl.Vector2{ .x = x + cell * (0.3 + phase * 0.4), .y = y + cell * (0.45 + age * 0.4) };
            const r = cell * (0.022 + age * 0.012);
            rl.drawCircleV(at, r, look.fade(ink, (1 - age * age) * 0.9));
        }
    }

    fn ice(self: *Fx, f: Frost) void {
        const from = mathx.centre(f.at);
        for (f.area.cells[0..f.area.n]) |p| {
            const to = mathx.centre(p);
            for (0..ICE_MOTES) |_| {
                const life = 0.22 + self.rng.unit() * 0.18;
                self.emit(.{
                    .p = .{ to[0] - 0.25 + self.rng.unit() * 0.5, to[1] - 0.25 + self.rng.unit() * 0.5, STRIKE_Z },
                    .v = .{ (to[0] - from[0]) * 0.25, (to[1] - from[1]) * 0.25, self.rng.unit() * 0.3 },
                    .life = life,
                    .r = 2 + self.rng.unit() * 4,
                    .col = look.COLD,
                });
            }
        }
    }

    pub fn drawChilled(self: *const Fx, x: f32, y: f32, cell: f32, seed: usize, ink: rl.Color) void {
        const t = self.seconds.at() + @as(f32, @floatFromInt(seed));
        for (0..5) |i| {
            const phase = @as(f32, @floatFromInt(i)) / 5;
            const cx = x + cell * (0.22 + phase * 0.56);
            const cy = y + cell * (0.75 + @sin(t * 2 + phase * mathx.TAU) * 0.06);
            const r = cell * 0.035;
            const col = look.fade(ink, 0.7 + @sin(t * 3 + phase) * 0.2);
            rl.drawLineEx(.{ .x = cx - r, .y = cy }, .{ .x = cx + r, .y = cy }, cell * 0.012, col);
            rl.drawLineEx(.{ .x = cx, .y = cy - r }, .{ .x = cx, .y = cy + r }, cell * 0.012, col);
        }
    }

    pub fn drawBurning(self: *const Fx, x: f32, y: f32, cell: f32, seed: usize, alpha: f32) void {
        const t = self.seconds.at();
        for (0..7) |i| {
            const phase = @as(f32, @floatFromInt(i)) / 7;
            const age = @mod(t * 1.7 + phase + @as(f32, @floatFromInt(seed)) * 0.17, 1);
            const sway = @sin(t * 6 + phase * mathx.TAU) * 0.04;
            const at = rl.Vector2{ .x = x + cell * (0.22 + phase * 0.56 + sway), .y = y + cell * (0.82 - age * 0.65) };
            const r = cell * (0.065 - age * 0.045);
            rl.drawCircleV(at, r, look.fade(look.FIRE, (1 - age) * 0.85 * alpha));
            rl.drawCircleV(at, r * 0.45, look.fade(look.FIRE_CORE, (1 - age) * 0.9 * alpha));
        }
    }

    pub fn juke(self: *Fx, from: mathx.P, to: mathx.P) void {
        const a = mathx.centre(from);
        const b = mathx.centre(to);
        const count = @as(usize, @intCast(mathx.dist(from, to))) * TRAIL_MOTES;
        for (0..count) |i| {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(count));
            self.emit(.{
                .p = .{ mathx.lerpF(a[0], b[0], t), mathx.lerpF(a[1], b[1], t), 0.15 + self.rng.unit() * 0.35 },
                .v = .{ 0, 0, 0.12 },
                .life = 0.18 + t * 0.16,
                .r = 2 + self.rng.unit() * 3,
                .col = look.JUKE_TRAIL,
                .terrain = false,
            });
        }
        for (0..DUST_MOTES) |i| {
            const dir = heading((@as(f32, @floatFromInt(i)) + self.rng.unit()) * mathx.TAU / @as(f32, DUST_MOTES));
            const speed = 0.8 + self.rng.unit() * 1.8;
            self.emit(.{
                .p = .{ b[0] + dir[0] * 0.28, b[1] + dir[1] * 0.28, 0.04 },
                .v = .{ dir[0] * speed, dir[1] * speed, 0.3 + self.rng.unit() * 0.7 },
                .life = (1 + self.rng.unit()) * JUKE_S / 2,
                .r = 2 + self.rng.unit() * 3,
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

    /// Before the light map, which lights and fogs the motes as it does the floor under them; stains under the rest.
    pub fn draw(self: *const Fx, ox: f32, oy: f32, cell: f32) void {
        const k = cell / @as(f32, @floatFromInt(look.SPRITE_PX));
        for (&self.motes) |*m| {
            if (m.life <= 0 or !m.landed) continue;
            const a = m.life / (m.max * STAIN_FADE);
            const s = screen(m.*, ox, oy, cell);
            rl.drawEllipse(@intFromFloat(s.x), @intFromFloat(s.y), m.r * k * STAIN_W, m.r * k * STAIN_H, look.fade(m.col, a));
        }
        for (&self.motes) |*m| {
            if (m.life <= 0 or m.landed or m.add) continue;
            const a = if (m.stains) 1 else m.life / (m.max * FLY_FADE);
            rl.drawCircleV(screen(m.*, ox, oy, cell), m.r * k, look.fade(m.col, a));
        }
        rl.beginBlendMode(.additive);
        defer rl.endBlendMode();
        for (&self.motes) |*m| {
            if (m.life <= 0 or !m.add) continue;
            const t = m.life / m.max;
            rl.drawCircleV(screen(m.*, ox, oy, cell), m.r * k * t, look.fade(m.col, t));
        }
    }
};

fn heading(a: f32) [2]f32 {
    return .{ @cos(a), @sin(a) };
}

fn screen(m: Mote, ox: f32, oy: f32, cell: f32) rl.Vector2 {
    return .{ .x = ox + m.p[0] * cell, .y = oy + (m.p[1] - m.p[2]) * cell };
}

/// A drop that will stain does not age in the air, so every one that lands leaves its stain.
fn tick(m: *Mote, lv: *const grid.Level, dt: f32) void {
    if (m.life <= 0) return;
    if (!m.stains or m.landed) m.life -= dt;
    if (m.landed or m.add) return;
    const k = 1 / (1 + m.drag * dt);
    for (0..3) |i| m.p[i] += m.v[i] * dt;
    m.v[0] *= k;
    m.v[1] *= k;
    m.v[2] = m.v[2] * k - m.grav * dt;
    if (m.terrain and !lv.walkable(mathx.cellOf(.{ m.p[0], m.p[1] }))) {
        m.life = 0;
        return;
    }
    if (m.p[2] > 0) return;
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

test "glacial frost waits for impact then fills only its cone and clears without stains" {
    const lv = grid.openFloor();
    var fx = Fx{};
    const at = mathx.P{ .x = 20, .y = 20 };
    const area = glacial.cone(&lv, .{ .x = 15, .y = 20 }, at);
    fx.frost(0.2, .{ .at = at, .area = area });
    fx.step(&lv, 0.1);
    try std.testing.expectEqual(@as(usize, 0), live(&fx).flying);
    fx.step(&lv, 0.11);
    const n = live(&fx).flying;
    try std.testing.expectEqual(area.n * ICE_MOTES, n);
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
    const dt: f32 = 1.0 / 240.0;
    var reach: f32 = 0;
    var ahead: usize = 0;
    var t: f32 = 0;
    var flash_gone: ?f32 = null;
    while (t < 3) : (t += dt) {
        fx.step(&lv, dt);
        if (flash_gone == null and fx.flashOf(3) == 0) flash_gone = t;
        for (fx.motes) |m| {
            if (m.life <= 0 or m.add) continue;
            reach = @max(reach, mathx.len(m.p[0] - 20.5, m.p[1] - 20.5));
        }
        if (@abs(t - 0.7) < dt * 0.5) {
            for (fx.motes) |m| {
                if (m.landed and m.life > 0 and m.p[0] > 20.5) ahead += 1;
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
    while (t < 1.5) : (t += 1.0 / 240.0) {
        fx.step(&lv, 1.0 / 240.0);
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
    while (t < 1) : (t += 1.0 / 240.0) fx.step(&lv, 1.0 / 240.0);
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

test "a blow from nowhere sprays all round, not in one heap" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    var b = TEST_BLOW;
    b.dir = null;
    b.lethal = true;
    fx.strike(0, b);
    for (0..240) |_| fx.step(&lv, 1.0 / 240.0);
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
