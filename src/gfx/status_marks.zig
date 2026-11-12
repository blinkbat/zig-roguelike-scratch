const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const Status = @import("effect_state.zig").Status;
const look = @import("look.zig");
const pixel = @import("pixel.zig");
const pxScale = look.pxScale;

pub const Mark = struct { x: f32, y: f32, cell: f32, seed: usize, ink: rl.Color, alpha: f32, stacks: u8 };
const BLEED_DROPS = 4;
const CHILL_FLAKES = 5;
const BURN_FLAMES = 7;
const TORCH_FLAMES = 7;
const FLAME_HZ: f32 = 1.7;
const TORCH_RISE_PX: f32 = 16;
const TORCH_FLECK_PX: f32 = 3.5;
pub const TORCH_TOP_PX = 20;
const WARD_DOTS = 48;
const SHOCK_SPARKS = 4;
const EXPOSED_CRACKS = @import("../play/sunder.zig").MOST;
const SHOCK_HZ: f32 = 9;
const CONFUSION_DOTS = 3;
const HALO_Y: f32 = 0.1;
const HALO_R: f32 = 0.2;
const ENFEEBLE_X: f32 = 0.2;
const ENFEEBLE_HZ: f32 = 0.8;
const FRIGHT_X: f32 = 0.8;
const FRIGHT_SHAKE: f32 = 0.015;
const FRIGHT_RAD_S: f32 = 30;
const PIN_STAKES = [_][2]f32{ .{ 0.24, -0.06 }, .{ 0.5, 0 }, .{ 0.76, 0.06 } };
const PIN_H: f32 = 0.16;
const PIN_FOOT: f32 = 0.92;
const WARD_R: f32 = 0.46;
const WARD_RAD_S: f32 = 2.4;
const MARKS_FROM: f32 = 0.22;
const MARKS_SPAN: f32 = 0.56;

comptime {
    std.debug.assert(TORCH_RISE_PX + TORCH_FLECK_PX <= TORCH_TOP_PX);
}

fn flameAge(t: f32, phase: f32, seed: f32) f32 {
    return @mod(t * FLAME_HZ + phase + seed, 1);
}

pub const Renderer = struct {
    seconds: f32,

    pub fn drawStatus(self: *const Renderer, s: Status, m: Mark) void {
        const mark = markOf(s) orelse return;
        mark(self, m);
    }

    pub fn marks(s: Status) bool {
        return markOf(s) != null;
    }

    fn markOf(s: Status) ?*const fn (*const Renderer, Mark) void {
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
            .exposed => &drawExposed,
            .warded => &drawWarded,
            .resistant, .guarding, .unyielding, .steady, .overwatch, .imbued, .biding => null,
        };
    }

    fn markBurning(self: *const Renderer, m: Mark) void {
        self.drawBurning(m.x, m.y, m.cell, m.seed, m.alpha);
    }

    fn drawBleeding(self: *const Renderer, m: Mark) void {
        const t = self.seconds;
        for (0..BLEED_DROPS) |i| {
            const phase = @as(f32, @floatFromInt(i)) / BLEED_DROPS;
            const age = @mod(t * 0.9 + phase + @as(f32, @floatFromInt(m.seed)) * 0.23, 1);
            const at = rl.Vector2{ .x = m.x + m.cell * (0.3 + phase * 0.4), .y = m.y + m.cell * (0.45 + age * 0.4) };
            const r = look.SPRITE_PX * (0.022 + age * 0.012);
            pixel.oval(at, r, r * 1.8, pxScale(m.cell), look.fade(m.ink, (1 - age * age) * 0.9));
        }
    }

    fn drawChilled(self: *const Renderer, m: Mark) void {
        const t = self.seconds + @as(f32, @floatFromInt(m.seed));
        for (0..CHILL_FLAKES) |i| {
            const phase = @as(f32, @floatFromInt(i)) / CHILL_FLAKES;
            const cx = m.x + m.cell * (MARKS_FROM + phase * MARKS_SPAN);
            const cy = m.y + m.cell * (0.75 + @sin(t * 2 + phase * mathx.TAU) * 0.06);
            const across = @as(f32, look.SPRITE_PX) * 0.07;
            const col = look.fade(m.ink, 0.7 + @sin(t * 3 + phase) * 0.2);
            pixel.cross(.{ .x = cx, .y = cy }, across, pxScale(m.cell), col);
        }
    }

    fn drawPinned(_: *const Renderer, m: Mark) void {
        for (PIN_STAKES) |s| {
            const foot = rl.Vector2{ .x = m.x + m.cell * s[0], .y = m.y + m.cell * PIN_FOOT };
            const top = rl.Vector2{ .x = foot.x + m.cell * s[1], .y = foot.y - m.cell * PIN_H };
            pixel.line(top, foot, 2, pxScale(m.cell), m.ink);
        }
    }

    fn drawWarded(self: *const Renderer, m: Mark) void {
        const breath = @sin(self.seconds * WARD_RAD_S);
        const r = m.cell * (WARD_R + breath * 0.02);
        for (0..WARD_DOTS) |i| {
            const a = mathx.spoke(@floatFromInt(i), WARD_DOTS);
            const k = 0.35 + 0.25 * @sin(a * 3 + self.seconds * 2);
            pixel.rect(.{ .x = m.x + m.cell * 0.5 + @cos(a) * r, .y = m.y + m.cell * 0.5 + @sin(a) * r }, 1, 2, pxScale(m.cell), look.fade(m.ink, k));
        }
    }

    fn drawShocked(self: *const Renderer, m: Mark) void {
        const t = self.seconds * SHOCK_HZ + @as(f32, @floatFromInt(m.seed)) * 0.37;
        const k = pxScale(m.cell);
        const arm = m.cell * 0.05;
        for (0..SHOCK_SPARKS) |i| {
            const phase = @as(f32, @floatFromInt(i)) / SHOCK_SPARKS;
            if (@mod(t + phase * 3.7, 1) > 0.45) continue;
            const at = rl.Vector2{ .x = m.x + m.cell * (MARKS_FROM + phase * MARKS_SPAN), .y = m.y + m.cell * (0.35 + @mod(phase * 2.3 + @floor(t) * 0.17, 0.4)) };
            const bend = rl.Vector2{ .x = at.x + arm * 0.3, .y = at.y };
            pixel.bend(.{ .x = at.x - arm, .y = at.y - arm }, bend, .{ .x = at.x - arm * 0.3, .y = at.y + arm * 1.2 }, 1, k, m.ink);
        }
    }

    fn drawSundered(_: *const Renderer, m: Mark) void {
        const k = pxScale(m.cell);
        for (0..m.stacks) |i| {
            const cx = m.x + m.cell * (0.3 + @as(f32, @floatFromInt(i)) * 0.2);
            const top = m.y + m.cell * 0.45;
            const mid = rl.Vector2{ .x = cx + m.cell * 0.04, .y = top + m.cell * 0.08 };
            pixel.bend(.{ .x = cx, .y = top }, mid, .{ .x = cx - m.cell * 0.02, .y = top + m.cell * 0.16 }, 1, k, m.ink);
        }
    }

    fn drawExposed(self: *const Renderer, m: Mark) void {
        var cracked = m;
        cracked.stacks = EXPOSED_CRACKS;
        self.drawSundered(cracked);
    }

    fn drawBlinded(_: *const Renderer, m: Mark) void {
        const k = pxScale(m.cell);
        const lid = m.y + m.cell * HALO_Y;
        pixel.line(.{ .x = m.x + m.cell * 0.38, .y = lid }, .{ .x = m.x + m.cell * 0.62, .y = lid }, 1, k, m.ink);
        for ([_]f32{ 0.42, 0.5, 0.58 }) |across| pixel.line(.{ .x = m.x + m.cell * across, .y = lid }, .{ .x = m.x + m.cell * across, .y = lid + m.cell * 0.04 }, 1, k, m.ink);
    }

    fn drawConfused(self: *const Renderer, m: Mark) void {
        const t = self.seconds * 3 + @as(f32, @floatFromInt(m.seed));
        for (0..CONFUSION_DOTS) |i| {
            const a = t + mathx.spoke(@floatFromInt(i), CONFUSION_DOTS);
            const at = rl.Vector2{ .x = m.x + m.cell * (0.5 + @cos(a) * HALO_R), .y = m.y + m.cell * (HALO_Y + @sin(a) * HALO_R * 0.35) };
            pixel.rect(at, 2, 2, pxScale(m.cell), look.fade(m.ink, 0.65 + 0.3 * @sin(a)));
        }
    }

    fn drawEnfeebled(self: *const Renderer, m: Mark) void {
        const k = pxScale(m.cell);
        const sink = @mod(self.seconds * ENFEEBLE_HZ + @as(f32, @floatFromInt(m.seed)) * 0.31, 1);
        const tip = rl.Vector2{ .x = m.x + m.cell * ENFEEBLE_X, .y = m.y + m.cell * (HALO_Y + 0.08 + sink * 0.08) };
        const arm = m.cell * 0.05;
        const col = look.fade(m.ink, 0.9 - sink * 0.5);
        pixel.bend(.{ .x = tip.x - arm, .y = tip.y - arm }, tip, .{ .x = tip.x + arm, .y = tip.y - arm }, 1, k, col);
    }

    fn drawMaimed(_: *const Renderer, m: Mark) void {
        const k = pxScale(m.cell);
        const foot = m.y + m.cell * PIN_FOOT;
        const knee = rl.Vector2{ .x = m.x + m.cell * 0.3, .y = foot - m.cell * 0.1 };
        pixel.bend(.{ .x = m.x + m.cell * 0.24, .y = foot }, knee, .{ .x = m.x + m.cell * 0.38, .y = foot - m.cell * 0.04 }, 2, k, m.ink);
    }

    fn drawFrightened(self: *const Renderer, m: Mark) void {
        const k = pxScale(m.cell);
        const shake = @sin(self.seconds * FRIGHT_RAD_S + @as(f32, @floatFromInt(m.seed))) * FRIGHT_SHAKE;
        const top = rl.Vector2{ .x = m.x + m.cell * (FRIGHT_X + shake), .y = m.y + m.cell * HALO_Y };
        pixel.rect(top, 2, 6, k, m.ink);
        pixel.rect(.{ .x = top.x, .y = top.y + 6 * k }, 2, 2, k, m.ink);
    }

    pub fn drawBurning(self: *const Renderer, x: f32, y: f32, cell: f32, seed: usize, alpha: f32) void {
        const t = self.seconds;
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

    pub fn drawTorch(self: *const Renderer, x: f32, y: f32, cell: f32, seed: f32, lit: f32, memory: f32) void {
        const k = pxScale(cell);
        pixel.rect(.{ .x = x, .y = y + 7 * k }, 3, 12, k, look.fade(look.TORCH_HANDLE, memory * 0.7));
        pixel.rect(.{ .x = x, .y = y + k }, 7, 3, k, look.fade(look.TORCH_DIM, memory));
        const t = self.seconds;
        for (0..TORCH_FLAMES) |i| {
            const f: f32 = @floatFromInt(i);
            const age = flameAge(t, f / TORCH_FLAMES, seed);
            const p = rl.Vector2{ .x = x + @sin(t * 7 + f * 3 + seed) * (1 + age * 2) * k, .y = y - age * TORCH_RISE_PX * k };
            pixel.fleck(p, TORCH_FLECK_PX - age * 2.8, k, look.fade(look.FIRE, (1 - age) * lit));
            pixel.rect(p, 2 - age, 3 - age * 2, k, look.fade(look.FIRE_CORE, (1 - age) * lit));
        }
    }
};
