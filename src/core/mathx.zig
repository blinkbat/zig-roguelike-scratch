const std = @import("std");

pub const TAU: f32 = std.math.tau;

pub fn lerpF(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// An eased value this near where it is going lands there exactly, so one that has arrived reads as arrived.
pub const SETTLE: f32 = 1e-3;

/// `up` and `down` are the share of the way it goes, rising and falling.
pub fn ease(v: f32, want: f32, up: f32, down: f32) f32 {
    const n = v + (want - v) * (if (want > v) up else down);
    return if (@abs(want - n) < SETTLE) want else n;
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
};

/// The cell a point measured in cells lies in.
pub fn cellOf(q: [2]f32) P {
    return .{ .x = @intFromFloat(@floor(q[0])), .y = @intFromFloat(@floor(q[1])) };
}

/// Chebyshev, to match 8-way movement: every step, range and gap on the grid.
pub fn dist(a: P, b: P) i32 {
    return @intCast(@max(@abs(a.x - b.x), @abs(a.y - b.y)));
}

pub fn distEuclid(a: P, b: P) f32 {
    const dx: f32 = @floatFromInt(a.x - b.x);
    const dy: f32 = @floatFromInt(a.y - b.y);
    return @sqrt(dx * dx + dy * dy);
}

/// Clockwise from north; `dirOf` divides a heading straight into the ordinal.
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
    return @min(1.0, @sqrt(x * x + y * y));
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

    /// [0, 1).
    pub fn unit(self: *Rng) f32 {
        return self.r().float(f32);
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
