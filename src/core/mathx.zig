const std = @import("std");

pub const TAU: f32 = std.math.tau;

pub fn lerpF(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// Within this of its target an ease lands on it exactly.
pub const SETTLE: f32 = 1e-3;

pub fn ease(v: f32, want: f32, up: f32, down: f32) f32 {
    const n = v + (want - v) * (if (want > v) up else down);
    return if (@abs(want - n) < SETTLE) want else n;
}

pub fn easing(dt: f32, rate: f32) f32 {
    return 1 - @exp(-dt * rate);
}

pub fn smooth(t: f32) f32 {
    const c = std.math.clamp(t, 0, 1);
    return c * c * (3 - 2 * c);
}

pub fn roundTiesUp(v: f32) i32 {
    return @intFromFloat(@floor(v + 0.5));
}

pub fn roundTiesDown(v: f32) i32 {
    return @intFromFloat(@ceil(v - 0.5));
}

/// A cell. The grid is y-DOWN: north is (0, -1) everywhere.
pub const P = struct {
    x: i32,
    y: i32,

    pub fn eq(a: P, b: P) bool {
        return a.x == b.x and a.y == b.y;
    }

    pub fn add(a: P, b: P) P {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: P, b: P) P {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn min(a: P, b: P) P {
        return .{ .x = @min(a.x, b.x), .y = @min(a.y, b.y) };
    }

    pub fn max(a: P, b: P) P {
        return .{ .x = @max(a.x, b.x), .y = @max(a.y, b.y) };
    }
};

/// The middle of `p`, in cells: `cellOf` of it is `p`.
pub fn centre(p: P) [2]f32 {
    return .{ @as(f32, @floatFromInt(p.x)) + 0.5, @as(f32, @floatFromInt(p.y)) + 0.5 };
}

/// The cell a point measured in cells lies in.
pub fn cellOf(q: [2]f32) P {
    return .{ .x = @intFromFloat(@floor(q[0])), .y = @intFromFloat(@floor(q[1])) };
}

pub const PERCENT = 100;
pub const MILLE = 1000;

pub fn fraction(pc: anytype) f32 {
    return @as(f32, @floatFromInt(pc)) / PERCENT;
}

pub fn smoothstep(lo: f32, hi: f32, x: f32) f32 {
    return smooth(std.math.clamp((x - lo) / (hi - lo), 0, 1));
}

/// Across a square's corners, top-left, top-right, bottom-left, bottom-right.
pub fn bilerp(c: [4]f32, a: f32, b: f32) f32 {
    return lerpF(lerpF(c[0], c[1], a), lerpF(c[2], c[3], a), b);
}

pub fn valueNoise(ctx: anytype, comptime lattice: fn (@TypeOf(ctx), i32, i32) f32, u: f32, v: f32) f32 {
    const fu = @floor(u);
    const fv = @floor(v);
    const x: i32 = @intFromFloat(fu);
    const y: i32 = @intFromFloat(fv);
    return bilerp(.{ lattice(ctx, x, y), lattice(ctx, x + 1, y), lattice(ctx, x, y + 1), lattice(ctx, x + 1, y + 1) }, smooth(u - fu), smooth(v - fv));
}

pub fn span(comptime T: type, r: [2]T, lo: T, hi: T) [2]T {
    const top = std.math.clamp(r[1], lo, hi);
    return .{ std.math.clamp(r[0], lo, top), top };
}

pub fn wrap(i: usize, by: i32, n: usize) usize {
    return @intCast(@mod(@as(i32, @intCast(i)) + by, @as(i32, @intCast(n))));
}

/// Chebyshev, to match 8-way movement: every step, range and gap on the grid.
pub fn dist(a: P, b: P) i32 {
    return @intCast(@max(@abs(a.x - b.x), @abs(a.y - b.y)));
}

/// The cells exactly `r` from `c`, row by row.
pub const Ring = struct {
    c: P,
    r: i32,
    at: P,

    pub fn init(c: P, r: i32) Ring {
        return .{ .c = c, .r = r, .at = .{ .x = c.x - r, .y = c.y - r } };
    }

    pub fn cells(r: i32) usize {
        return if (r == 0) 1 else @intCast(8 * r);
    }

    pub fn next(self: *Ring) ?P {
        if (self.at.y > self.c.y + self.r) return null;
        const p = self.at;
        const right = self.c.x + self.r;
        const edge = p.y == self.c.y - self.r or p.y == self.c.y + self.r;
        if (p.x >= right) {
            self.at = .{ .x = self.c.x - self.r, .y = p.y + 1 };
        } else self.at.x = if (edge) p.x + 1 else right;
        return p;
    }
};

test "a ring is the cells of its box exactly its radius out, in the box's order" {
    const c = P{ .x = 3, .y = -2 };
    for (0..6) |ri| {
        const r: i32 = @intCast(ri);
        var ring = Ring.init(c, r);
        var n: usize = 0;
        var y = c.y - r;
        while (y <= c.y + r) : (y += 1) {
            var x = c.x - r;
            while (x <= c.x + r) : (x += 1) {
                const p = P{ .x = x, .y = y };
                if (dist(p, c) != r) continue;
                try std.testing.expectEqual(p, ring.next().?);
                n += 1;
            }
        }
        try std.testing.expectEqual(@as(?P, null), ring.next());
        try std.testing.expectEqual(Ring.cells(r), n);
    }
}

pub fn distEuclid(a: P, b: P) f32 {
    return len(@floatFromInt(a.x - b.x), @floatFromInt(a.y - b.y));
}

/// Real seconds summed frame by frame, in f64: an f32 sum stops moving after a day or so.
pub const Seconds = struct {
    sum: f64 = 0,

    pub fn step(s: *Seconds, dt: f32) void {
        s.sum += dt;
    }

    pub fn at(s: Seconds) f32 {
        return @floatCast(s.sum);
    }
};

/// `std.math.hypot` without its guard against overflow, which costs in a per-texel loop.
pub fn len(x: f32, y: f32) f32 {
    return @sqrt(x * x + y * y);
}

/// Clockwise from north: `dirOf` and `heading` rely on the ordinals.
pub const Dir = enum(u3) {
    n = 0,
    ne = 1,
    e = 2,
    se = 3,
    s = 4,
    sw = 5,
    w = 6,
    nw = 7,

    pub fn delta(d: Dir) P {
        return DELTAS.get(d);
    }

    pub fn diagonal(d: Dir) bool {
        return @intFromEnum(d) % 2 == 1;
    }

    pub fn heading(d: Dir) f32 {
        return @as(f32, @floatFromInt(@intFromEnum(d))) * SECTOR;
    }

    pub fn opposite(d: Dir) Dir {
        return @enumFromInt(@intFromEnum(d) +% 4);
    }
};

const SECTOR: f32 = TAU / @as(f32, @floatFromInt(ALL_DIRS.len));

const DELTAS = std.EnumArray(Dir, P).init(.{
    .n = .{ .x = 0, .y = -1 },
    .ne = .{ .x = 1, .y = -1 },
    .e = .{ .x = 1, .y = 0 },
    .se = .{ .x = 1, .y = 1 },
    .s = .{ .x = 0, .y = 1 },
    .sw = .{ .x = -1, .y = 1 },
    .w = .{ .x = -1, .y = 0 },
    .nw = .{ .x = -1, .y = -1 },
});

pub const ALL_DIRS = std.enums.values(Dir);

/// The four straight steps, east, west, south, north: generators draw in this order.
pub const CARDINALS = [_]P{ Dir.e.delta(), Dir.w.delta(), Dir.s.delta(), Dir.n.delta() };

pub fn dirTo(a: P, b: P) ?Dir {
    const d = b.sub(a);
    for (ALL_DIRS) |dir| {
        if (dir.delta().eq(d)) return dir;
    }
    return null;
}

/// 0 is north, growing clockwise.
pub fn headingOf(dx: f32, dy: f32) f32 {
    const a = std.math.atan2(dx, -dy);
    return if (a < 0) a + TAU else a;
}

pub const HYST: f32 = 0.14;

/// `bias` is the sector currently held, kept for an extra `HYST` radians so a thumb on a boundary does not flicker.
pub fn dirOf(heading: f32, bias: ?Dir) Dir {
    const raw: Dir = @enumFromInt(@as(u3, @intCast(@mod(@as(i32, @intFromFloat(@floor(heading / SECTOR + 0.5))), @as(i32, ALL_DIRS.len)))));
    const b = bias orelse return raw;
    if (raw == b) return b;
    const off = @abs(angleDelta(heading, b.heading()));
    return if (off <= SECTOR * 0.5 + HYST) b else raw;
}

pub fn angleDelta(a: f32, b: f32) f32 {
    var d = @mod(a - b, TAU);
    if (d > TAU / 2.0) d -= TAU;
    return d;
}

/// Radial, never per-axis: a square gate's corner is 0.62 per axis but 0.88 true.
pub fn deflection(x: f32, y: f32) f32 {
    return @min(1.0, len(x, y));
}

pub const Rng = struct {
    impl: std.Random.DefaultPrng,

    pub fn init(seed: u64) Rng {
        return .{ .impl = std.Random.DefaultPrng.init(seed) };
    }

    fn r(self: *Rng) std.Random {
        return self.impl.random();
    }

    pub fn below(self: *Rng, max: u32) u32 {
        std.debug.assert(max > 0);
        return self.r().uintLessThan(u32, max);
    }

    /// Inclusive both ends.
    pub fn range(self: *Rng, lo: i32, hi: i32) i32 {
        if (hi <= lo) return lo;
        return lo + @as(i32, @intCast(self.below(@intCast(hi - lo + 1))));
    }

    pub fn chance(self: *Rng, p: f32) bool {
        return self.unit() < p;
    }

    pub fn percent(self: *Rng, pc: u32) bool {
        return self.below(PERCENT) < pc;
    }

    pub fn perMille(self: *Rng, pm: u32) bool {
        return self.below(MILLE) < pm;
    }

    /// [0, 1).
    pub fn unit(self: *Rng) f32 {
        return self.r().float(f32);
    }

    pub fn pickWhere(self: *Rng, comptime T: type, items: []const T, ctx: anytype, comptime ok: fn (@TypeOf(ctx), T) bool) ?T {
        var n: u32 = 0;
        for (items) |it| {
            if (ok(ctx, it)) n += 1;
        }
        if (n == 0) return null;
        var k = self.below(n);
        for (items) |it| {
            if (!ok(ctx, it)) continue;
            if (k == 0) return it;
            k -= 1;
        }
        unreachable;
    }
};

test "dir deltas run clockwise from north" {
    try std.testing.expectEqual(P{ .x = 0, .y = -1 }, Dir.n.delta());
    try std.testing.expectEqual(P{ .x = 1, .y = 0 }, Dir.e.delta());
    try std.testing.expectEqual(P{ .x = 0, .y = 1 }, Dir.s.delta());
    try std.testing.expectEqual(P{ .x = -1, .y = 0 }, Dir.w.delta());
    for (ALL_DIRS) |d| {
        const p = d.delta();
        try std.testing.expectEqual(d, dirOf(headingOf(@floatFromInt(p.x), @floatFromInt(p.y)), null));
    }
}

test "the held sector survives a thumb resting on its boundary" {
    const past = Dir.n.heading() + SECTOR * 0.5 + 0.05;
    try std.testing.expectEqual(Dir.ne, dirOf(past, null));
    try std.testing.expectEqual(Dir.n, dirOf(past, .n));
    const far = Dir.n.heading() + SECTOR * 0.5 + HYST + 0.05;
    try std.testing.expectEqual(Dir.ne, dirOf(far, .n));
}

test "chebyshev makes a diagonal step cost one" {
    const a = P{ .x = 4, .y = 4 };
    try std.testing.expectEqual(@as(i32, 1), dist(a, .{ .x = 5, .y = 5 }));
    try std.testing.expectEqual(@as(i32, 3), dist(a, .{ .x = 7, .y = 2 }));
}

test "a seed reproduces a roll" {
    var a = Rng.init(99);
    var b = Rng.init(99);
    for (0..64) |_| try std.testing.expectEqual(a.range(1, 6), b.range(1, 6));
}
