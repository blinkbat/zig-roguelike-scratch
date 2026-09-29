const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const actor = @import("../play/actor.zig");
const look = @import("look.zig");

// EVERY BLOW'S AFTERMATH, after zig-soulslike's and far fainter. Nothing in the simulation reads any of it.

/// `ichor` is Brogue's purple blood.
pub const Matter = enum { blood, ooze, wood, ichor };

pub fn matterOf(k: actor.Kind) Matter {
    return switch (k) {
        .archer, .rat => .blood,
        .slime => .ooze,
        .bloat => .ichor,
    };
}

/// The flash's colour is `light.FLASH_RGB`, since the body shader draws it.
pub const FLASH_S: f32 = 0.16;
pub const FLASH_GAIN: f32 = 0.45;

/// Cells, ground to where a blow lands on a body.
const STRIKE_Z: f32 = 0.3;
const STAIN_S: f32 = 1.2;
/// Of a stain's life, the last part over which it fades.
const STAIN_FADE: f32 = 0.6;
/// Of a stain's own radius, flattened onto the floor.
const STAIN_W: f32 = 1.5;
const STAIN_H: f32 = 0.8;
/// Of a flight that leaves no stain, the last part over which the mote fades.
const FLY_FADE: f32 = 0.5;
/// Of its speed along the ground a mote keeps through each bounce.
const SKID: f32 = 0.6;
const CONTACT = rl.Color{ .r = 255, .g = 244, .b = 214, .a = 130 };
const CONTACT_S: f32 = 0.07;
/// Sprite pixels.
const CONTACT_R: f32 = 5;

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
        .blood => .{ .col = .{ .r = 112, .g = 22, .b = 16, .a = 220 }, .hit = 4, .kill = 9, .along_lo = 0.6, .along_hi = 1.8, .fan = 0.8, .up_lo = 0.6, .up_hi = 1.5, .grav = 7, .drag = 3, .life_lo = 0.35, .life_hi = 0.6, .r_lo = 1, .r_hi = 2, .stains = true },
        .ooze => .{ .col = .{ .r = 70, .g = 120, .b = 72, .a = 220 }, .hit = 4, .kill = 10, .along_lo = 0.4, .along_hi = 1.4, .fan = 0.9, .up_lo = 0.5, .up_hi = 1.3, .grav = 5.5, .drag = 3, .life_lo = 0.3, .life_hi = 0.6, .r_lo = 1.2, .r_hi = 2.4, .stains = true },
        .wood => .{ .col = .{ .r = 120, .g = 82, .b = 46, .a = 230 }, .hit = 4, .kill = 7, .along_lo = 0.2, .along_hi = 1.0, .fan = 1.4, .up_lo = 0.8, .up_hi = 1.8, .grav = 9, .drag = 2, .life_lo = 0.4, .life_hi = 0.7, .r_lo = 1, .r_hi = 2, .stains = false, .bounce = 0.35 },
        .ichor => blk: {
            var s = sprayOf(.blood);
            s.col = .{ .r = look.GAS.r / 2, .g = look.GAS.g / 2, .b = look.GAS.b / 2, .a = s.col.a };
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
};

pub const Blow = struct {
    /// The pool slot to flash; null for what has no body left to flash, a barrel.
    slot: ?usize,
    /// Cells, the middle of the struck cell on the ground.
    at: [2]f32,
    /// Unit, the way the blow travelled.
    dir: [2]f32,
    matter: Matter,
    lethal: bool,
};

pub const MOTES: usize = 160;
const DUE: usize = 32;

const Due = union(enum) {
    blow: Blow,
    /// The pool slot of a body that only flashes, since nothing struck it: the gas.
    sting: usize,
};

pub const Fx = struct {
    motes: [MOTES]Mote = @splat(.{ .p = @splat(0), .v = @splat(0), .r = 0, .col = rl.Color.blank }),
    head: usize = 0,
    flash: [actor.MAX]f32 = @splat(0),
    due: [DUE]struct { t: f32, what: Due } = undefined,
    due_n: usize = 0,
    rng: mathx.Rng = mathx.Rng.init(0xF1A5),

    pub fn clear(self: *Fx) void {
        for (&self.motes) |*m| m.life = 0;
        self.flash = @splat(0);
        self.due_n = 0;
    }

    /// `wait` seconds from now, when the picture reaches the blow the simulation already dealt.
    pub fn after(self: *Fx, wait: f32, b: Blow) void {
        self.later(wait, .{ .blow = b });
    }

    pub fn sting(self: *Fx, wait: f32, slot: usize) void {
        self.later(wait, .{ .sting = slot });
    }

    fn later(self: *Fx, wait: f32, what: Due) void {
        if (wait <= 0 or self.due_n == DUE) return self.fire(what);
        self.due[self.due_n] = .{ .t = wait, .what = what };
        self.due_n += 1;
    }

    fn fire(self: *Fx, what: Due) void {
        switch (what) {
            .blow => |b| self.land(b),
            .sting => |s| self.flash[s] = FLASH_S,
        }
    }

    pub fn flashOf(self: *const Fx, slot: usize) f32 {
        return FLASH_GAIN * std.math.clamp(self.flash[slot] / FLASH_S, 0, 1);
    }

    pub fn step(self: *Fx, lv: *const grid.Level, dt: f32) void {
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
            self.fire(what);
        }
        for (&self.motes) |*m| tick(m, lv, dt);
    }

    fn land(self: *Fx, b: Blow) void {
        if (b.slot) |s| self.flash[s] = FLASH_S;
        self.emit(.{ .p = .{ b.at[0], b.at[1], STRIKE_Z }, .v = .{ 0, 0, 0 }, .life = CONTACT_S, .r = CONTACT_R, .col = CONTACT, .add = true });
        const s = sprayOf(b.matter);
        const rng = &self.rng;
        for (0..if (b.lethal) s.kill else s.hit) |_| {
            const along = mathx.lerpF(s.along_lo, s.along_hi, rng.unit());
            const across = (rng.unit() * 2 - 1) * s.fan;
            self.emit(.{
                .p = .{ b.at[0], b.at[1], STRIKE_Z },
                .v = .{ b.dir[0] * along - b.dir[1] * across, b.dir[1] * along + b.dir[0] * across, mathx.lerpF(s.up_lo, s.up_hi, rng.unit()) },
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

    fn emit(self: *Fx, m: Mote) void {
        self.motes[self.head] = m;
        self.motes[self.head].max = m.life;
        self.head = (self.head + 1) % MOTES;
    }

    /// Before the light map, which lights and fogs the motes as it does the floor under them; stains under the rest.
    pub fn draw(self: *const Fx, ox: f32, oy: f32, cell: f32) void {
        const k = cell / @as(f32, @floatFromInt(look.SPRITE_PX));
        for (self.motes) |m| {
            if (m.life <= 0 or !m.landed) continue;
            const a = m.life / (m.max * STAIN_FADE);
            rl.drawEllipse(@intFromFloat(ox + m.p[0] * cell), @intFromFloat(oy + m.p[1] * cell), m.r * k * STAIN_W, m.r * k * STAIN_H, look.fade(m.col, a));
        }
        for (self.motes) |m| {
            if (m.life <= 0 or m.landed or m.add) continue;
            const a = if (m.stains) 1 else m.life / (m.max * FLY_FADE);
            rl.drawCircleV(screen(m, ox, oy, cell), m.r * k, look.fade(m.col, a));
        }
        rl.beginBlendMode(.additive);
        defer rl.endBlendMode();
        for (self.motes) |m| {
            if (m.life <= 0 or !m.add) continue;
            const t = m.life / m.max;
            rl.drawCircleV(screen(m, ox, oy, cell), m.r * k * t, look.fade(m.col, t));
        }
    }
};

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
    if (!lv.walkable(mathx.cellOf(.{ m.p[0], m.p[1] }))) {
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

test "a blow flashes its body for a beat and sprays blood a fraction of a cell, which lies a moment and is gone" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    fx.after(0, TEST_BLOW);
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
            reach = @max(reach, @sqrt((m.p[0] - 20.5) * (m.p[0] - 20.5) + (m.p[1] - 20.5) * (m.p[1] - 20.5)));
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
    fx.after(0, b);
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
    fx.after(0, b);
    t = 0;
    while (t < 1) : (t += 1.0 / 240.0) fx.step(&lv, 1.0 / 240.0);
    for (fx.motes) |m| {
        if (m.life > 0 and !m.add) try std.testing.expect(m.p[0] < 21);
    }
}

test "a blow dealt now lands when the picture gets there" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    fx.after(0.1, TEST_BLOW);
    fx.step(&lv, 0.05);
    try std.testing.expectEqual(@as(f32, 0), fx.flashOf(3));
    fx.step(&lv, 0.06);
    try std.testing.expect(fx.flashOf(3) > 0);
}

test "a sting flashes its body when the picture gets there and sprays nothing" {
    const lv = grid.openFloor();
    var fx = Fx{};
    fx.clear();
    fx.sting(0.1, 3);
    fx.step(&lv, 0.05);
    try std.testing.expectEqual(@as(f32, 0), fx.flashOf(3));
    fx.step(&lv, 0.06);
    try std.testing.expectApproxEqAbs(FLASH_GAIN, fx.flashOf(3), 0.1);
    try std.testing.expectEqual(@as(usize, 0), live(&fx).flying + live(&fx).stains);
    for (fx.motes) |m| try std.testing.expect(m.life <= 0);
}
