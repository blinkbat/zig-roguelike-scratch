const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");

const P = mathx.P;

pub const Kind = enum {
    archer,
    rat,
    slime,
    slime_half,
    slime_quarter,
    bloat,

    pub fn foe(k: Kind) bool {
        return switch (k) {
            .archer => false,
            .rat, .slime, .slime_half, .slime_quarter, .bloat => true,
        };
    }

    /// A foe a floor is stocked with, not one split off another.
    pub fn stocked(k: Kind) bool {
        return k.foe() and k.family() == k;
    }

    /// The kind a body was placed as: a slime, for the halves and quarters split off one.
    pub fn family(k: Kind) Kind {
        return FAMILY.get(k);
    }

    /// It dies bursting into gas, however it dies.
    pub fn bursts(k: Kind) bool {
        return row(k).blow == .burst;
    }
};

const FAMILY = blk: {
    var t = std.EnumArray(Kind, Kind).initUndefined();
    for (std.enums.values(Kind)) |k| t.set(k, k);
    for (std.enums.values(Kind)) |k| {
        var c = row(k).splits;
        while (c) |x| : (c = row(x).splits) t.set(x, t.get(k));
    }
    break :blk t;
};

/// The foes a floor is stocked with.
pub const FOES = blk: {
    var ks: []const Kind = &.{};
    for (std.enums.values(Kind)) |k| {
        if (k.stocked()) ks = ks ++ &[_]Kind{k};
    }
    break :blk ks[0..ks.len].*;
};

/// The most bodies one of `k` can end as, split and split again.
pub fn most(k: Kind) usize {
    return if (row(k).splits) |n| 2 * most(n) else 1;
}

pub const Strike = struct { lo: i32, hi: i32, verb: [:0]const u8 };

pub const Blow = union(enum) {
    strike: Strike,
    /// It dies instead (Brogue's kamikaze), and bursts into caustic gas however it dies.
    burst,
};

pub const Row = struct {
    name: [:0]const u8,
    /// A fresh body's; one split off a slime has half what that slime had left.
    hp: i32,
    sight: i32,
    blow: Blow,
    /// Brogue's `MONST_FLITS`: a third of its moves go a random way.
    flits: bool = false,
    /// What it splits into, two of them, when a blow leaves it under half its hp.
    splits: ?Kind = null,
};

pub const FLIT: f32 = 0.33;

const SLAM = Blow{ .strike = .{ .lo = 2, .hi = 5, .verb = "slams" } };

pub fn row(k: Kind) Row {
    return switch (k) {
        .archer => .{ .name = "archer", .hp = 24, .sight = 10, .blow = .{ .strike = .{ .lo = 1, .hi = 2, .verb = "kicks" } } },
        .rat => .{ .name = "rat", .hp = 6, .sight = 7, .blow = .{ .strike = .{ .lo = 1, .hi = 3, .verb = "bites" } } },
        .slime => .{ .name = "slime", .hp = 40, .sight = 6, .blow = SLAM, .splits = .slime_half },
        .slime_half => .{ .name = "half slime", .hp = @divTrunc(row(.slime).hp, 2), .sight = row(.slime).sight, .blow = SLAM, .splits = .slime_quarter },
        .slime_quarter => .{ .name = "quarter slime", .hp = @divTrunc(row(.slime_half).hp, 2), .sight = row(.slime).sight, .blow = SLAM },
        .bloat => .{ .name = "bloat", .hp = 4, .sight = 7, .blow = .burst, .flits = true },
    };
}

pub const Actor = struct {
    kind: Kind,
    at: P,
    hp: i32,
    max: i32,
    awake: bool = false,
    alive: bool = true,
    /// Split off this turn: it acts from the next.
    waits: bool = false,

    pub fn of(k: Kind, at: P) Actor {
        return .{ .kind = k, .at = at, .hp = row(k).hp, .max = row(k).hp };
    }

    pub fn hurt(self: Actor) bool {
        return self.hp < self.max;
    }

    pub fn foe(self: Actor) bool {
        return self.kind.foe();
    }
};

pub const MAX: usize = 64;

pub const Tally = struct { left: usize = 0, total: usize = 0 };

/// Ids are 1-based so `grid.NO_ONE` (0) is never a body.
pub const Pool = struct {
    items: [MAX]Actor = undefined,
    n: usize = 0,

    pub fn idOf(i: usize) u16 {
        return @intCast(i + 1);
    }

    pub fn slot(id: u16) usize {
        return id - 1;
    }

    pub fn spawn(self: *Pool, lv: *grid.Level, a: Actor) u16 {
        std.debug.assert(self.n < MAX);
        const id = idOf(self.n);
        self.items[self.n] = a;
        self.n += 1;
        lv.stand(a.at, id);
        return id;
    }

    pub fn get(self: *Pool, id: u16) ?*Actor {
        if (id == grid.NO_ONE or id > self.n) return null;
        const a = &self.items[slot(id)];
        return if (a.alive) a else null;
    }

    pub fn slice(self: *Pool) []Actor {
        return self.items[0..self.n];
    }

    /// A slime's halves and quarters count as slimes.
    pub fn tally(self: *Pool, k: Kind) Tally {
        var t = Tally{};
        for (self.slice()) |a| {
            if (a.kind.family() != k) continue;
            t.total += 1;
            if (a.alive) t.left += 1;
        }
        return t;
    }

    pub fn move(self: *Pool, lv: *grid.Level, id: u16, to: P) void {
        const a = self.get(id) orelse return;
        lv.clear(a.at);
        a.at = to;
        lv.stand(to, id);
    }

    /// The only place hp goes down. Returns true on the killing blow.
    pub fn damage(self: *Pool, lv: *grid.Level, id: u16, amount: i32) bool {
        const a = self.get(id) orelse return false;
        a.hp -= amount;
        a.awake = true;
        if (a.hp > 0) return false;
        a.alive = false;
        lv.clear(a.at);
        return true;
    }

    /// A body `damage` left under half its hp divides into two of what it `splits` into, each on half what it had left,
    /// the new one on a free cell beside it; with none free it waits for a blow that finds one. The new one's id.
    pub fn split(self: *Pool, lv: *grid.Level, id: u16, rng: *mathx.Rng) ?u16 {
        const a = self.get(id) orelse return null;
        const next = row(a.kind).splits orelse return null;
        if (a.hp * 2 >= a.max or self.n == MAX) return null;
        var ways: [mathx.ALL_DIRS.len]P = undefined;
        var n: usize = 0;
        for (mathx.ALL_DIRS) |d| {
            if (!lv.stepOk(a.at, d, grid.NO_ONE)) continue;
            ways[n] = a.at.add(d.delta());
            n += 1;
        }
        if (n == 0) return null;
        const hp = @max(1, @divTrunc(a.hp, 2));
        a.kind = next;
        a.hp = hp;
        a.max = hp;
        return self.spawn(lv, .{ .kind = next, .at = ways[rng.below(@intCast(n))], .hp = hp, .max = hp, .awake = true, .waits = true });
    }
};

/// Brogue's `monsterAvoids`: gas is shunned by a body not already in some.
fn shuns(lv: *const grid.Level, from: P, d: mathx.Dir) bool {
    return lv.gassy(from.add(d.delta())) and !lv.gassy(from);
}

/// Downhill on a walked-distance map from the hero; null when no open neighbour is closer.
pub fn chase(lv: *const grid.Level, from: P, id: u16, flow: *const [grid.CELLS]i32) ?mathx.Dir {
    var best: ?mathx.Dir = null;
    var best_d = flow[grid.Level.idx(from)];
    if (best_d < 0) return null;
    for (mathx.ALL_DIRS) |d| {
        if (!lv.stepOk(from, d, id) or shuns(lv, from, d)) continue;
        const v = flow[grid.Level.idx(from.add(d.delta()))];
        if (v >= 0 and v < best_d) {
            best_d = v;
            best = d;
        }
    }
    return best;
}

/// Brogue's `randValidDirectionFrom`: any step it may take and does not shun, or one onto `prey`.
pub fn flit(lv: *const grid.Level, from: P, id: u16, prey: u16, rng: *mathx.Rng) ?mathx.Dir {
    var ways: [mathx.ALL_DIRS.len]mathx.Dir = undefined;
    var n: usize = 0;
    for (mathx.ALL_DIRS) |d| {
        const onto = lv.passOk(from, d) and lv.who(from.add(d.delta())) == prey;
        if (!onto and (!lv.stepOk(from, d, id) or shuns(lv, from, d))) continue;
        ways[n] = d;
        n += 1;
    }
    if (n == 0) return null;
    return ways[rng.below(@intCast(n))];
}

test "a spawned body stands on the grid and leaves it when it dies" {
    var lv = grid.openFloor();
    var pool = Pool{};
    const id = pool.spawn(&lv, Actor.of(.rat, .{ .x = 5, .y = 5 }));
    try std.testing.expectEqual(id, lv.who(.{ .x = 5, .y = 5 }));
    try std.testing.expect(!pool.damage(&lv, id, 2));
    try std.testing.expect(pool.get(id).?.awake);
    try std.testing.expect(pool.damage(&lv, id, 99));
    try std.testing.expectEqual(grid.NO_ONE, lv.who(.{ .x = 5, .y = 5 }));
    try std.testing.expectEqual(@as(?*Actor, null), pool.get(id));
}

test "a slime a blow leaves under half its hp splits in two of the next kind, each on half what it had left" {
    var lv = grid.openFloor();
    var pool = Pool{};
    var rng = mathx.Rng.init(0x5717);
    const at = P{ .x = 10, .y = 10 };
    const id = pool.spawn(&lv, Actor.of(.slime, at));
    const full = row(.slime).hp;
    try std.testing.expect(!pool.damage(&lv, id, @divTrunc(full, 2)));
    try std.testing.expectEqual(@as(?u16, null), pool.split(&lv, id, &rng));
    try std.testing.expect(!pool.damage(&lv, id, 3));
    const left = pool.get(id).?.hp;
    const other = pool.split(&lv, id, &rng) orelse return error.NoSplit;
    const a = pool.get(id).?.*;
    const b = pool.get(other).?.*;
    std.debug.print("a slime of {d} hp left on {d}: two half slimes of {d}/{d} hp, a cell apart\n", .{ full, left, a.hp, a.max });
    for ([_]Actor{ a, b }) |s| {
        try std.testing.expectEqual(Kind.slime_half, s.kind);
        try std.testing.expectEqual(@divTrunc(left, 2), s.hp);
        try std.testing.expectEqual(s.hp, s.max);
    }
    try std.testing.expectEqual(at, a.at);
    try std.testing.expectEqual(@as(i32, 1), mathx.dist(a.at, b.at));
    try std.testing.expectEqual(other, lv.who(b.at));
    try std.testing.expect(b.awake and b.waits and !a.waits);
    for ([_]u16{ id, other }) |half| {
        try std.testing.expect(!pool.damage(&lv, half, pool.get(half).?.hp - 1));
        const q = pool.split(&lv, half, &rng) orelse return error.NoSplit;
        for ([_]u16{ half, q }) |s| {
            try std.testing.expectEqual(Kind.slime_quarter, pool.get(s).?.kind);
            try std.testing.expectEqual(@as(i32, 1), pool.get(s).?.max);
        }
    }
    try std.testing.expectEqual(Tally{ .left = 4, .total = 4 }, pool.tally(.slime));
    for (pool.slice()) |s| try std.testing.expectEqual(Kind.slime_quarter, s.kind);
    const last = pool.spawn(&lv, Actor.of(.slime_quarter, .{ .x = 30, .y = 30 }));
    try std.testing.expect(!pool.damage(&lv, last, row(.slime_quarter).hp - 1));
    try std.testing.expectEqual(@as(?u16, null), pool.split(&lv, last, &rng));
}

test "a slime with no free cell beside it waits to split until a blow finds one" {
    var lv = grid.openFloor();
    var pool = Pool{};
    var rng = mathx.Rng.init(0x5717);
    const at = P{ .x = 10, .y = 10 };
    const id = pool.spawn(&lv, Actor.of(.slime, at));
    for (mathx.ALL_DIRS) |d| lv.set(at.add(d.delta()), .wall);
    lv.set(at.add(mathx.Dir.e.delta()), .floor);
    lv.putBarrel(at.add(mathx.Dir.e.delta()));
    try std.testing.expect(!pool.damage(&lv, id, row(.slime).hp - 3));
    try std.testing.expectEqual(@as(?u16, null), pool.split(&lv, id, &rng));
    try std.testing.expectEqual(Kind.slime, pool.get(id).?.kind);
    _ = lv.breakBarrel(at.add(mathx.Dir.e.delta()));
    try std.testing.expect(!pool.damage(&lv, id, 1));
    const other = pool.split(&lv, id, &rng) orelse return error.NoSplit;
    try std.testing.expectEqual(at.add(mathx.Dir.e.delta()), pool.get(other).?.at);
    try std.testing.expectEqual(@as(i32, 1), pool.get(other).?.hp);
}

test "every foe a floor is stocked with is its own family, and a slime ends as four quarters at most" {
    try std.testing.expectEqualSlices(Kind, &.{ .rat, .slime, .bloat }, &FOES);
    try std.testing.expectEqual(Kind.slime, Kind.slime_quarter.family());
    try std.testing.expectEqual(Kind.rat, Kind.rat.family());
    try std.testing.expectEqual(@as(usize, 4), most(.slime));
    try std.testing.expectEqual(@as(usize, 1), most(.rat));
}

test "chase walks round a wall toward the hero" {
    var lv = grid.openFloor();
    var y: i32 = 1;
    while (y < 12) : (y += 1) lv.set(.{ .x = 10, .y = y }, .wall);
    var flow: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const hero = P{ .x = 12, .y = 5 };
    _ = grid.distances(&lv, hero, &flow, &queue);
    var at = P{ .x = 8, .y = 5 };
    var steps: usize = 0;
    while (mathx.dist(at, hero) > 1 and steps < 40) : (steps += 1) {
        const d = chase(&lv, at, 1, &flow) orelse return error.Stuck;
        at = at.add(d.delta());
    }
    std.debug.print("round a wall: {d} steps to reach a hero 4 cells away\n", .{steps});
    try std.testing.expect(mathx.dist(at, hero) <= 1);
}

test "chase will not step from clean air into gas, but walks on through it from inside" {
    var lv = grid.openFloor();
    var flow: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&lv, .{ .x = 20, .y = 5 }, &flow, &queue);
    var y: i32 = 1;
    while (y < grid.H - 1) : (y += 1) lv.addGas(.{ .x = 15, .y = y }, 50);
    const at = P{ .x = 14, .y = 5 };
    try std.testing.expectEqual(@as(?mathx.Dir, null), chase(&lv, at, 1, &flow));
    lv.addGas(at, 50);
    const d = chase(&lv, at, 1, &flow) orelse return error.Stuck;
    try std.testing.expectEqual(@as(i32, 15), at.add(d.delta()).x);
}

test "a flit goes every open way about evenly, onto its prey too, and never into gas from clean air" {
    var lv = grid.openFloor();
    var rng = mathx.Rng.init(0xF117);
    const from = P{ .x = 10, .y = 10 };
    lv.stand(from, 2);
    lv.stand(.{ .x = 11, .y = 10 }, 1);
    lv.putBarrel(.{ .x = 9, .y = 10 });
    lv.addGas(.{ .x = 10, .y = 9 }, 30);
    const TRIES: usize = 6000;
    var counts = std.EnumArray(mathx.Dir, usize).initFill(0);
    for (0..TRIES) |_| counts.getPtr(flit(&lv, from, 2, 1, &rng) orelse return error.Stuck).* += 1;
    std.debug.print("{d} flits beside a barrel west and gas north:", .{TRIES});
    for (mathx.ALL_DIRS) |d| std.debug.print(" {s} {d}", .{ @tagName(d), counts.get(d) });
    std.debug.print("\n", .{});
    try std.testing.expectEqual(@as(usize, 0), counts.get(.w));
    try std.testing.expectEqual(@as(usize, 0), counts.get(.n));
    for ([_]mathx.Dir{ .ne, .e, .se, .s, .sw, .nw }) |d| {
        try std.testing.expect(counts.get(d) * 6 > TRIES * 85 / 100 and counts.get(d) * 6 < TRIES * 115 / 100);
    }
}
