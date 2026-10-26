const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");
const P = mathx.P;
const smooth = mathx.smooth;

/// Per second.
const REVEAL: f32 = 14.0;
const FORGET: f32 = 5.0;
/// Cells: memory is black on the edge of anything unseen and full this far from it.
const VOID_FADE: f32 = 1.5;
/// Keep the sight fade inside unseen cell rims so visible ground stays bright.
const SIGHT_FADE: f32 = 0.4;
pub const VOID_REACH: i32 = @intFromFloat(@ceil(VOID_FADE));
const VOID_SPAN: usize = @intCast(grid.Cells.span(VOID_REACH));
pub const View = struct { sight: f32, memory: f32, lit: f32 };

/// 0 outside the grid; texel centres sit on whole numbers.
fn bilinear(f: []const f32, w: i32, h: i32, u: f32, v: f32) f32 {
    const fx = @floor(u);
    const fy = @floor(v);
    const x0: i32 = @intFromFloat(fx);
    const y0: i32 = @intFromFloat(fy);
    return mathx.bilerp(.{ texel(f, w, h, x0, y0), texel(f, w, h, x0 + 1, y0), texel(f, w, h, x0, y0 + 1), texel(f, w, h, x0 + 1, y0 + 1) }, u - fx, v - fy);
}

/// Bilinear self-weight is at least 1/4, keeping remembered open ground whole.
const OPEN_WHOLE: f32 = 4;

/// A map-sized field at a point on the screen, cells.
pub fn sample(f: *const [grid.CELLS]f32, x: f32, y: f32) f32 {
    const uv = fieldUv(.{ .x = 0, .y = 0 }, x, y);
    return bilinear(f, grid.W, grid.H, uv[0], uv[1]);
}

pub fn fieldUv(o: P, x: f32, y: f32) [2]f32 {
    return .{ x - @as(f32, @floatFromInt(o.x)) - 0.5, y - @as(f32, @floatFromInt(o.y)) - 0.5 };
}

const SightField = enum { soft, weight, open };

fn sightOf(sees: anytype, ground: bool, x: f32, y: f32) f32 {
    const soft = sees.at(.soft, x, y);
    if (!ground) return soft;
    const weight = sees.at(.weight, x, y);
    if (weight <= 0) return soft;
    return mathx.lerpF(soft, sees.at(.open, x, y) / weight, @min(1, weight * OPEN_WHOLE));
}

const Whole = struct {
    fields: *const Visibility,

    fn at(w: Whole, k: SightField, x: f32, y: f32) f32 {
        return sample(w.fields.sightField(k), x, y);
    }
};

pub const Patch = struct {
    const SIDE = 3;

    lo: P,
    v: std.EnumArray(SightField, [SIDE * SIDE]f32),

    pub fn of(l: *const Visibility, c: P) Patch {
        var p = Patch{ .lo = c.sub(.{ .x = SIDE / 2, .y = SIDE / 2 }), .v = undefined };
        for (std.enums.values(SightField)) |k| {
            const f = l.sightField(k);
            const out = p.v.getPtr(k);
            for (out, 0..) |*o, i| {
                const q = p.lo.add(mathx.unslot(i, SIDE));
                o.* = texel(f, grid.W, grid.H, q.x, q.y);
            }
        }
        return p;
    }

    pub fn sightAt(self: *const Patch, ground: bool, x: f32, y: f32) f32 {
        return sightOf(self, ground, x, y);
    }

    fn at(p: *const Patch, k: SightField, x: f32, y: f32) f32 {
        const u = x - 0.5;
        const v = y - 0.5;
        const fx = @floor(u);
        const fy = @floor(v);
        const ix: usize = @intCast(@as(i32, @intFromFloat(fx)) - p.lo.x);
        const iy: usize = @intCast(@as(i32, @intFromFloat(fy)) - p.lo.y);
        const f = p.v.getPtrConst(k);
        const i = iy * SIDE + ix;
        return mathx.bilerp(.{ f[i], f[i + 1], f[i + SIDE], f[i + SIDE + 1] }, u - fx, v - fy);
    }
};

pub fn sampleOccluded(reach: *const [grid.CELLS]f32, open: *const [grid.CELLS]f32, x: f32, y: f32) f32 {
    const uv = fieldUv(.{ .x = 0, .y = 0 }, x, y);
    return occluded(reach, open, grid.W, grid.H, uv[0], uv[1]);
}

pub fn texel(f: []const f32, w: i32, h: i32, x: i32, y: i32) f32 {
    return f[mathx.slot(x, y, @intCast(w), @intCast(h)) orelse return 0];
}

/// Blend unreachable cells over `open` so walls cannot pass light onward.
pub fn occluded(reach: []const f32, open: []const f32, w: i32, h: i32, u: f32, v: f32) f32 {
    const own = texel(reach, w, h, mathx.roundTiesUp(u), mathx.roundTiesUp(v)) > 0;
    return bilinear(if (own) reach else open, w, h, u, v);
}

pub fn mask(on: bool) f32 {
    return @floatFromInt(@intFromBool(on));
}

fn hidesGround(t: grid.Tile) bool {
    return t.blind() and t.upright() and !look.stands(t);
}

pub const Fade = struct {
    flat: ?f32 = null,
    n: usize = 0,
    short: [grid.Cells.square(VOID_REACH)]Short = undefined,

    const Short = struct { x: f32, y: f32, m: f32 };

    pub fn view(self: *const Fade, sight: f32, point: [2]f32) View {
        const memory = self.at(point[0], point[1], sight);
        return .{ .sight = sight, .memory = memory, .lit = sight * memory };
    }

    fn at(f: *const Fade, x: f32, y: f32, sight: f32) f32 {
        if (f.flat) |v| return v;
        const reach = mathx.lerpF(VOID_FADE, SIGHT_FADE, sight);
        var v: f32 = 1;
        for (f.short[0..f.n]) |c| {
            const dx = @max(0, @max(c.x - x, x - c.x - 1));
            const dy = @max(0, @max(c.y - y, y - c.y - 1));
            if (dx >= reach or dy >= reach) continue;
            v = @min(v, mathx.lerpF(c.m, 1, smooth(mathx.len(dx, dy) / reach)));
        }
        return v;
    }
};

pub const Visibility = struct {
    sight: [grid.CELLS]f32,
    memory: [grid.CELLS]f32,
    soft_sight: [grid.CELLS]f32,
    /// Weighted sight over open ground only, preventing light leaks through walls.
    open_sight: [grid.CELLS]f32,
    /// 1 on a cell that blocks no sight; set from the terrain.
    see_through: [grid.CELLS]f32,
    /// Open-ground memory weights; `sightAt` divides weighted sight by these.
    open_weight: [grid.CELLS]f32,
    /// Ground visibility includes shrub edges, keeping them continuous with adjacent ground.
    ground: [grid.CELLS]f32,
    blur: [grid.CELLS]f32,
    share: [grid.CELLS]f32,
    /// `sight` but for what blocks it, as `Torch.open` is, so the carried light passes through no wall.
    carry_open: [grid.CELLS]f32,
    clear: [grid.CELLS]bool,
    clear_row: [grid.CELLS]bool,

    pub fn reset(self: *Visibility) void {
        @memset(&self.sight, 0);
        @memset(&self.memory, 0);
    }

    pub fn terrain(self: *Visibility, level: *const grid.Level) void {
        for (&self.see_through, &self.ground, &level.tile) |*k, *g, t| {
            k.* = mask(!t.blind());
            g.* = mask(!hidesGround(t));
        }
    }

    pub fn snap(self: *Visibility, level: *const grid.Level, reveal_map: bool) void {
        for (0..grid.CELLS) |i| {
            self.sight[i] = mask(level.lit[i]);
            self.memory[i] = mask(reveal_map or level.seen[i]);
        }
        self.soften();
    }

    pub fn step(self: *Visibility, level: *const grid.Level, dt: f32, reveal_map: bool) void {
        const reveal_rate = mathx.easing(dt, REVEAL);
        const forget_rate = mathx.easing(dt, FORGET);
        var changed = false;
        for (0..grid.CELLS) |i| {
            const target_sight = mask(level.lit[i]);
            const target_memory = mask(reveal_map or level.seen[i]);
            if (self.sight[i] == target_sight and self.memory[i] == target_memory) continue;
            const sight = mathx.ease(self.sight[i], target_sight, reveal_rate, forget_rate);
            const memory = mathx.ease(self.memory[i], target_memory, reveal_rate, forget_rate);
            changed = changed or sight != self.sight[i] or memory != self.memory[i];
            self.sight[i] = sight;
            self.memory[i] = memory;
        }
        if (changed) self.soften();
    }

    pub fn reveal(self: *Visibility, level: *const grid.Level, enabled: bool) void {
        for (0..grid.CELLS) |i| self.memory[i] = mask(enabled or level.seen[i]);
        self.soften();
    }

    /// Blur only seen cells, and ground sight only over open ground, to prevent dim rims and wall leaks.
    pub fn soften(self: *Visibility) void {
        for (&self.soft_sight, &self.open_sight, &self.open_weight, &self.carry_open, &self.sight, &self.memory, &self.see_through) |*seen, *open, *w, *carry, s, m, k| {
            seen.* = s * m;
            open.* = s * m * k;
            w.* = m * k;
            carry.* = s * k;
        }
        self.blurShare(&self.soft_sight, &self.memory);
        self.blurShare(&self.open_sight, &self.open_weight);
        for (&self.open_sight, &self.open_weight) |*o, w| o.* *= w;
        self.markClear();
    }

    fn markClear(self: *Visibility) void {
        const r: usize = VOID_REACH;
        const span = VOID_SPAN;
        const w = grid.COLS;
        const h = grid.ROWS;
        @memset(&self.clear_row, false);
        @memset(&self.clear, false);
        for (0..h) |y| {
            var run: usize = 0;
            for (self.memory[y * w ..][0..w], 0..) |m, x| {
                run = if (m >= 1) run + 1 else 0;
                if (run >= span) self.clear_row[y * w + x - r] = true;
            }
        }
        var runs: [grid.COLS]u16 = @splat(0);
        for (0..h) |y| {
            for (self.clear_row[y * w ..][0..w], &runs, 0..) |ok, *run, x| {
                run.* = if (ok) run.* + 1 else 0;
                if (run.* >= span) self.clear[(y - r) * w + x] = true;
            }
        }
    }

    fn blurShare(self: *Visibility, num: *[grid.CELLS]f32, den: *const [grid.CELLS]f32) void {
        blur121(num, &self.blur, num);
        blur121(den, &self.blur, &self.share);
        for (num, &self.share) |*o, d| o.* = if (d > 0) @min(1, o.* / d) else 0;
    }

    /// A point on the screen, cells.
    pub fn sightAt(self: *const Visibility, x: f32, y: f32) f32 {
        return sightOf(Whole{ .fields = self }, self.groundAt(mathx.cellOf(.{ x, y })), x, y);
    }

    pub fn groundAt(self: *const Visibility, c: P) bool {
        return grid.cellOr(f32, &self.ground, c, 0) > 0;
    }

    fn sightField(self: *const Visibility, k: SightField) *const [grid.CELLS]f32 {
        return switch (k) {
            .soft => &self.soft_sight,
            .weight => &self.open_weight,
            .open => &self.open_sight,
        };
    }

    /// Distance fade reaches black at unseen rims; a blur leaks around corners.
    pub fn fadeOf(self: *const Visibility, c: P) Fade {
        const own = self.memoryAt(c);
        if (own <= 0) return .{ .flat = 0 };
        if (own >= 1 and self.whole(c)) return .{ .flat = 1 };
        var f = Fade{};
        var box = grid.Cells.around(c, VOID_REACH);
        while (box.next()) |p| {
            const m = self.memoryAt(p);
            if (m >= 1) continue;
            f.short[f.n] = .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y), .m = m };
            f.n += 1;
        }
        return f;
    }

    pub fn memoryAt(self: *const Visibility, p: P) f32 {
        return grid.cellOr(f32, &self.memory, p, 0);
    }

    fn whole(self: *const Visibility, p: P) bool {
        return grid.cellOr(bool, &self.clear, p, false);
    }

    pub fn viewAt(self: *const Visibility, q: [2]f32) View {
        return self.viewIn(q, &self.fadeOf(mathx.cellOf(q)));
    }

    pub fn viewIn(self: *const Visibility, q: [2]f32, fade: *const Fade) View {
        return fade.view(self.sightAt(q[0], q[1]), q);
    }
};

/// The edges repeat their own cell. `out` may be `src`.
fn blur121(src: *const [grid.CELLS]f32, tmp: *[grid.CELLS]f32, out: *[grid.CELLS]f32) void {
    const w = grid.COLS;
    const h = grid.ROWS;
    for (0..h) |y| {
        const s = src[y * w ..][0..w];
        const t = tmp[y * w ..][0..w];
        t[0] = (s[0] + s[0] * 2 + s[1]) * 0.25;
        for (t[1 .. w - 1], s[0 .. w - 2], s[1 .. w - 1], s[2..w]) |*v, l, m, r| v.* = (l + m * 2 + r) * 0.25;
        t[w - 1] = (s[w - 2] + s[w - 1] * 2 + s[w - 1]) * 0.25;
    }
    for (0..h) |y| {
        const u = tmp[(if (y == 0) 0 else y - 1) * w ..][0..w];
        const m = tmp[y * w ..][0..w];
        const d = tmp[@min(h - 1, y + 1) * w ..][0..w];
        for (out[y * w ..][0..w], u, m, d) |*v, a, b, c| v.* = (a + b * 2 + c) * 0.25;
    }
}
