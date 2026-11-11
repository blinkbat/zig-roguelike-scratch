const std = @import("std");

pub const TAU: f32 = std.math.tau;

pub fn lerpF(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

pub fn spoke(at: f32, n: anytype) f32 {
    return at * TAU / @as(f32, @floatFromInt(n));
}

pub fn lerp2(a: [2]f32, b: [2]f32, t: f32) [2]f32 {
    return .{ lerpF(a[0], b[0], t), lerpF(a[1], b[1], t) };
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

/// `std.math.pow`'s squarings for a whole power, without its generic path; equal wherever no step goes subnormal.
pub fn powi(x: f32, comptime n: u32) f32 {
    var a: f32 = 1;
    var s = x;
    comptime var i = n;
    inline while (i != 0) : (i >>= 1) {
        if (i & 1 == 1) a *= s;
        if (i > 1) s *= s;
    }
    return a;
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

    pub fn scaled(a: P, k: i32) P {
        return .{ .x = a.x * k, .y = a.y * k };
    }

    pub fn sign(a: P) P {
        return .{ .x = std.math.sign(a.x), .y = std.math.sign(a.y) };
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

pub fn cellOf(q: [2]f32) P {
    return .{ .x = @intFromFloat(@floor(q[0])), .y = @intFromFloat(@floor(q[1])) };
}

/// The cell at `x, y`, each rounded half away from zero.
pub fn roundCell(x: f32, y: f32) P {
    return .{ .x = @intFromFloat(@round(x)), .y = @intFromFloat(@round(y)) };
}

pub const PERCENT = 100;
pub const MILLE = 1000;
pub const BASIS_POINTS = PERCENT * PERCENT;

pub fn fraction(pc: anytype) f32 {
    return @as(f32, @floatFromInt(pc)) / PERCENT;
}

/// `pc` percent of `v`, rounded toward zero.
pub fn percentOf(v: i32, pc: i32) i32 {
    return @divTrunc(v * pc, PERCENT);
}

/// `pc` percent of a non-negative `v`, rounded up.
pub fn percentCeil(v: i32, pc: i32) i32 {
    return std.math.lossyCast(i32, @divTrunc(@as(i64, v) * pc + PERCENT - 1, PERCENT));
}

/// A non-negative `v` cut by `pc` percent, rounded up.
pub fn lessCeil(v: i32, pc: i32) i32 {
    return percentCeil(v, PERCENT - pc);
}

/// A non-negative amount counted in hundredths, rounded up as often as its fraction.
pub fn percentRound(hundredths: i64, rng: *Rng) i64 {
    const part: u32 = @intCast(@mod(hundredths, PERCENT));
    return @divTrunc(hundredths, PERCENT) + @intFromBool(part > 0 and rng.percent(part));
}

pub fn plural(n: anytype) []const u8 {
    return if (n == 1) "" else "s";
}

pub fn fillOf(value: i32, max: i32) f32 {
    return std.math.clamp(@as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(@max(1, max))), 0, 1);
}

pub fn filled(value: i32, max: i32, full: i32) i32 {
    if (max <= 0) return 0;
    const clamped: i64 = std.math.clamp(value, 0, max);
    return @intCast(@divTrunc(clamped * full, max));
}

pub fn smoothstep(lo: f32, hi: f32, x: f32) f32 {
    return smooth((x - lo) / (hi - lo));
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

/// As `wrap`, but held at the first and the last instead.
pub fn nudge(i: usize, by: i32, n: usize) usize {
    if (n == 0) return 0;
    return @intCast(std.math.clamp(@as(i32, @intCast(i)) + by, 0, @as(i32, @intCast(n - 1))));
}

pub fn reveal(top: usize, at: usize, rows: usize) usize {
    if (at < top) return at;
    if (at >= top + rows) return at + 1 - rows;
    return top;
}

/// The value `by` places on from `v` in `list`, wrapping round; counted from `missing` when `v` is not in it.
pub fn stepIn(comptime T: type, list: []const T, v: T, by: i32, missing: ?usize) T {
    const at = std.mem.indexOfScalar(T, list, v) orelse missing.?;
    return list[wrap(at, by, list.len)];
}

/// Chebyshev, to match 8-way movement: every step, range and gap on the grid.
pub fn dist(a: P, b: P) i32 {
    return @intCast(@max(@abs(a.x - b.x), @abs(a.y - b.y)));
}

pub fn adjacent(a: P, b: P) bool {
    return dist(a, b) == 1;
}

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

pub fn slot(x: i32, y: i32, w: usize, h: usize) ?usize {
    if (x < 0 or y < 0 or x >= w or y >= h) return null;
    return @as(usize, @intCast(y)) * w + @as(usize, @intCast(x));
}

pub fn unslot(i: usize, w: usize) P {
    return .{ .x = @intCast(i % w), .y = @intCast(i / w) };
}

/// Sight's round reach: a cell half a cell past `r` is still in it.
pub fn reaches(a: P, b: P, r: f32) bool {
    return distEuclid(a, b) <= r + 0.5;
}

/// Within the right angle `origin` faces along `heading`, `origin` itself left out.
pub fn ahead(origin: P, heading: P, p: P) bool {
    const v = p.sub(origin);
    const along = heading.x * v.x + heading.y * v.y;
    const across = heading.x * v.y - heading.y * v.x;
    return along > 0 and @abs(across) <= along;
}

/// Every field of `p.*` that declares a default set to it, as `alloc.create` does not.
pub fn defaults(p: anytype) void {
    inline for (std.meta.fields(@TypeOf(p.*))) |f| {
        if (comptime f.defaultValue()) |d| @field(p.*, f.name) = d;
    }
}

pub fn removeAt(comptime T: type, items: []T, n: anytype, i: usize, blank: ?T) void {
    std.mem.copyForwards(T, items[i .. n.* - 1], items[i + 1 .. n.*]);
    n.* -= 1;
    if (blank) |b| items[n.*] = b;
}

pub fn swapRemove(comptime T: type, items: []T, n: *usize, i: usize) T {
    const out = items[i];
    n.* -= 1;
    items[i] = items[n.*];
    return out;
}

pub fn push(comptime T: type, items: []T, n: anytype, x: T) bool {
    if (n.* == items.len) return false;
    items[n.*] = x;
    n.* += 1;
    return true;
}

pub const TEST_DT: f32 = 1.0 / 240.0;
pub const FRAME_DT: f32 = 1.0 / 60.0;

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

/// Unlike `std.math.hypot`, this does not guard against overflow.
pub fn len(x: f32, y: f32) f32 {
    return @sqrt(x * x + y * y);
}

/// Clockwise from north: `dirOf`, `heading` and `turned` rely on the ordinals.
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
        return DELTAS.getPtrConst(d).*;
    }

    pub fn diagonal(d: Dir) bool {
        return @intFromEnum(d) % 2 == 1;
    }

    pub fn heading(d: Dir) f32 {
        return @as(f32, @floatFromInt(@intFromEnum(d))) * SECTOR;
    }

    pub fn opposite(d: Dir) Dir {
        return d.turned(4);
    }

    pub fn turned(d: Dir, eighths: u3) Dir {
        return @enumFromInt(@intFromEnum(d) +% eighths);
    }

    pub fn across(d: Dir) P {
        const v = d.delta();
        return .{ .x = @intCast(@abs(v.y)), .y = @intCast(@abs(v.x)) };
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

pub fn stepDir(d: P) ?Dir {
    for (ALL_DIRS) |dir| {
        if (dir.delta().eq(d)) return dir;
    }
    return null;
}

pub fn dirTo(a: P, b: P) ?Dir {
    return stepDir(b.sub(a));
}

/// The step from `a` heading for `b`, however far; null on `b` itself.
pub fn toward(a: P, b: P) ?Dir {
    return stepDir(b.sub(a).sign());
}

/// 0 is north, growing clockwise.
pub fn headingOf(dx: f32, dy: f32) f32 {
    const a = std.math.atan2(dx, -dy);
    return if (a < 0) a + TAU else a;
}

const HYST: f32 = 0.14;

/// `bias` is the sector currently held, kept for an extra `HYST` radians so a thumb on a boundary does not flicker.
pub fn dirOf(heading: f32, bias: ?Dir) Dir {
    const raw: Dir = @enumFromInt(@as(u3, @intCast(@mod(@as(i32, @intFromFloat(@floor(heading / SECTOR + 0.5))), @as(i32, ALL_DIRS.len)))));
    const b = bias orelse return raw;
    if (raw == b) return b;
    const off = @abs(angleDelta(heading, b.heading()));
    return if (off <= SECTOR * 0.5 + HYST) b else raw;
}

fn angleDelta(a: f32, b: f32) f32 {
    var d = @mod(a - b, TAU);
    if (d > TAU / 2.0) d -= TAU;
    return d;
}

/// Radial, never per-axis: a square gate's corner is 0.62 per axis but 0.88 true.
pub fn deflection(x: f32, y: f32) f32 {
    return @min(1.0, len(x, y));
}

pub const Rng = struct {
    impl: std.Random.Xoshiro256,

    pub fn init(seed: u64) Rng {
        return .{ .impl = std.Random.Xoshiro256.init(seed) };
    }

    pub fn valid(self: Rng) bool {
        return !std.mem.allEqual(u64, &self.impl.s, 0);
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

    pub fn coin(self: *Rng) bool {
        return self.chance(0.5);
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

    /// Within `k` wide, centred on 0.
    pub fn spread(self: *Rng, k: f32) f32 {
        return (self.unit() - 0.5) * k;
    }

    pub fn between(self: *Rng, lo: f32, hi: f32) f32 {
        return lerpF(lo, hi, self.unit());
    }

    /// A heading in radians, [0, `TAU`).
    pub fn angle(self: *Rng) f32 {
        return self.unit() * TAU;
    }

    /// An index under `n`, each as likely as its `weight`; null when all weigh nothing.
    pub fn weighted(self: *Rng, n: usize, ctx: anytype, comptime weight: fn (@TypeOf(ctx), usize) u32) ?usize {
        var total: u32 = 0;
        for (0..n) |i| total += weight(ctx, i);
        if (total == 0) return null;
        var left = self.below(total);
        for (0..n) |i| {
            const w = weight(ctx, i);
            if (left < w) return i;
            left -= w;
        }
        unreachable;
    }

    pub fn pick(self: *Rng, comptime T: type, items: []const T) T {
        return items[self.below(@intCast(items.len))];
    }

    /// One of the first `n.*` items at random, taken out by moving the last into its place.
    pub fn takeFrom(self: *Rng, comptime T: type, items: []T, n: *usize) T {
        return swapRemove(T, items, n, self.below(@intCast(n.*)));
    }

    /// Fisher-Yates, from the back.
    pub fn shuffle(self: *Rng, comptime T: type, xs: []T) void {
        var i = xs.len;
        while (i > 1) {
            i -= 1;
            const j = self.below(@intCast(i + 1));
            std.mem.swap(T, &xs[i], &xs[j]);
        }
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

test "powi is std.math.pow bit for bit until a squaring goes subnormal" {
    var bits: u32 = @bitCast(@as(f32, 0.35));
    const one: u32 = @bitCast(@as(f32, 1));
    while (bits <= one) : (bits += 97) {
        const x: f32 = @bitCast(bits);
        try std.testing.expectEqual(@as(u32, @bitCast(std.math.pow(f32, x, 80))), @as(u32, @bitCast(powi(x, 80))));
        try std.testing.expectEqual(@as(u32, @bitCast(std.math.pow(f32, x, 24))), @as(u32, @bitCast(powi(x, 24))));
    }
    try std.testing.expectEqual(@as(f32, 0), powi(0, 80));
}

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

pub fn toDefaults(s: anytype, comptime fields: []const []const u8) void {
    const T = @TypeOf(s.*);
    @setEvalBranchQuota(20_000);
    inline for (fields) |f| @field(s, f) = comptime std.meta.fieldInfo(T, @field(std.meta.FieldEnum(T), f)).defaultValue().?;
}

pub fn unitOf(h: u64) f32 {
    return @as(f32, @floatFromInt(h >> 40)) / (1 << 24);
}

pub fn cellHash(seed: u64, p: P) u64 {
    const coordinates = [2]i32{ p.x, p.y };
    return std.hash.Wyhash.hash(seed, std.mem.asBytes(&coordinates));
}

pub fn cycle(comptime T: type, v: T, by: i32) T {
    return stepIn(T, std.enums.values(T), v, by, 0);
}

pub fn indexOfEql(comptime T: type, list: []const T, want: T) ?usize {
    for (list, 0..) |x, i| {
        if (std.meta.eql(x, want)) return i;
    }
    return null;
}
