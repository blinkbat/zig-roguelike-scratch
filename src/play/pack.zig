const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const gen = @import("../world/gen.zig");
const actor = @import("actor.zig");

const P = mathx.P;

pub const PER_FLOOR: usize = 10;
pub const FEW: usize = 3;
/// The first kind leads.
pub const KINDS = [_][]const actor.Kind{
    &.{ .rat, .slime },
    &.{ .rat, .rat, .slime },
    &.{.rat},
    &.{ .rat, .rat },
    &.{.bloat},
};
pub const REACH: i32 = 2;
/// Past the archer's sight, so by default none starts in view.
pub const GAP: i32 = 12;
pub const BIGGEST: usize = blk: {
    var most: usize = 0;
    for (KINDS) |k| most = @max(most, k.len);
    break :blk most;
};

pub const PACKS_MAX: usize = 32;
pub const FEW_MAX: usize = PACKS_MAX;
pub const MAKEUP_MAX: usize = 5;
pub const MAKEUPS_MAX: usize = 8;
pub const WEIGHT_MIN: u8 = 1;
pub const WEIGHT_MAX: u8 = 9;
pub const FIRST = actor.FOES[0];
pub const REACH_MIN: i32 = 1;
pub const REACH_MAX: i32 = 4;
pub const GAP_MAX: i32 = 48;
pub const APART_MAX: i32 = 32;
const SPOT_TRIES: usize = 2000;

comptime {
    std.debug.assert(GAP > actor.row(.archer).sight);
    std.debug.assert(FEW * actor.FOES.len <= PER_FLOOR);
    std.debug.assert(KINDS.len <= MAKEUPS_MAX and BIGGEST <= MAKEUP_MAX and REACH <= REACH_MAX);
    for (actor.FOES) |k| std.debug.assert((Spec{}).holders(k) > 0);
    std.debug.assert((Spec{}).valid());
}

pub const Makeup = struct {
    kind: [MAKEUP_MAX]actor.Kind = @splat(FIRST),
    n: usize = 1,
    weight: u8 = WEIGHT_MIN,

    pub fn of(ks: []const actor.Kind) Makeup {
        var m = Makeup{ .n = ks.len };
        @memcpy(m.kind[0..ks.len], ks);
        return m;
    }

    pub fn kinds(self: *const Makeup) []const actor.Kind {
        return self.kind[0..self.n];
    }

    fn holds(self: *const Makeup, k: actor.Kind) bool {
        return std.mem.indexOfScalar(actor.Kind, self.kinds(), k) != null;
    }

    pub fn canGrow(self: *const Makeup) bool {
        return self.n < MAKEUP_MAX;
    }

    pub fn canShrink(self: *const Makeup) bool {
        return self.n > 1;
    }

    pub fn grow(self: *Makeup) bool {
        if (!self.canGrow()) return false;
        self.kind[self.n] = FIRST;
        self.n += 1;
        return true;
    }

    pub fn shrink(self: *Makeup) bool {
        if (!self.canShrink()) return false;
        self.n -= 1;
        self.kind[self.n] = FIRST;
        return true;
    }

    pub fn turn(self: *Makeup, i: usize) void {
        const at = std.mem.indexOfScalar(actor.Kind, &actor.FOES, self.kind[i]) orelse actor.FOES.len - 1;
        self.kind[i] = actor.FOES[mathx.wrap(at, 1, actor.FOES.len)];
    }
};

const DEFAULT_MAKEUPS = blk: {
    var ms: [MAKEUPS_MAX]Makeup = @splat(.{});
    for (KINDS, 0..) |k, i| ms[i] = Makeup.of(k);
    break :blk ms;
};

pub const Spec = struct {
    packs: usize = PER_FLOOR,
    /// Each kind any makeup holds has at least this many, while packs are left to place.
    few: usize = FEW,
    /// Cells from its lead to the rest of a pack, at most.
    reach: i32 = REACH,
    /// Cells from where the archer arrives to every foe, at least.
    gap: i32 = GAP,
    /// Cells from every member of one pack to every member of another, at least.
    apart: i32 = 0,
    makeup: [MAKEUPS_MAX]Makeup = DEFAULT_MAKEUPS,
    makeup_n: usize = KINDS.len,

    pub fn makeups(self: *const Spec) []const Makeup {
        return self.makeup[0..self.makeup_n];
    }

    pub fn canAdd(self: *const Spec) bool {
        return self.makeup_n < MAKEUPS_MAX;
    }

    pub fn canDrop(self: *const Spec) bool {
        return self.makeup_n > 1;
    }

    pub fn addMakeup(self: *Spec) bool {
        if (!self.canAdd()) return false;
        self.makeup[self.makeup_n] = .{};
        self.makeup_n += 1;
        return true;
    }

    pub fn dropMakeup(self: *Spec, i: usize) bool {
        if (!self.canDrop()) return false;
        std.mem.copyForwards(Makeup, self.makeup[i .. self.makeup_n - 1], self.makeup[i + 1 .. self.makeup_n]);
        self.makeup_n -= 1;
        self.makeup[self.makeup_n] = .{};
        return true;
    }

    pub fn fit(s: Spec) Spec {
        var t = s;
        t.packs = @min(s.packs, PACKS_MAX);
        t.few = @min(s.few, FEW_MAX);
        t.reach = std.math.clamp(s.reach, REACH_MIN, REACH_MAX);
        t.gap = std.math.clamp(s.gap, 0, GAP_MAX);
        t.apart = std.math.clamp(s.apart, 0, APART_MAX);
        t.makeup_n = std.math.clamp(s.makeup_n, 1, MAKEUPS_MAX);
        for (t.makeup[0..t.makeup_n]) |*m| {
            m.n = std.math.clamp(m.n, 1, MAKEUP_MAX);
            m.weight = std.math.clamp(m.weight, WEIGHT_MIN, WEIGHT_MAX);
            for (m.kind[0..m.n]) |*k| {
                if (!k.stocked()) k.* = FIRST;
            }
        }
        return t;
    }

    pub fn valid(s: *const Spec) bool {
        return std.meta.eql(s.fit(), s.*);
    }

    fn holders(self: *const Spec, k: actor.Kind) usize {
        var n: usize = 0;
        for (self.makeups()) |*m| {
            if (m.holds(k)) n += 1;
        }
        return n;
    }

    fn pick(self: *const Spec, rng: *mathx.Rng, k: ?actor.Kind) *const Makeup {
        var total: u32 = 0;
        for (self.makeups()) |*m| {
            if (k == null or m.holds(k.?)) total += m.weight;
        }
        var r = rng.below(total);
        for (self.makeups()) |*m| {
            if (k != null and !m.holds(k.?)) continue;
            if (r < m.weight) return m;
            r -= m.weight;
        }
        unreachable;
    }

    /// The foes in the fewest makeups first, so the packs that fill their quota fill the others' on the way.
    fn quotaOrder(self: *const Spec) [actor.FOES.len]actor.Kind {
        var ks = actor.FOES;
        std.sort.insertion(actor.Kind, &ks, self, fewerHolders);
        return ks;
    }

    fn fewerHolders(self: *const Spec, a: actor.Kind, b: actor.Kind) bool {
        return self.holders(a) < self.holders(b);
    }
};

/// No more than the pool holds once every slime placed has split down to quarters.
pub fn place(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, given: *const Spec) void {
    const fitted = given.fit();
    const spec = &fitted;
    var bodies = pool.n;
    var packs: usize = 0;
    for (spec.quotaOrder()) |k| {
        if (spec.holders(k) == 0) continue;
        while (packs < spec.packs and pool.tally(k).total < spec.few) : (packs += 1) {
            if (!placeOne(lv, pool, rng, start, spec, spec.pick(rng, k), &bodies)) return;
        }
    }
    while (packs < spec.packs) : (packs += 1) {
        if (!placeOne(lv, pool, rng, start, spec, spec.pick(rng, null), &bodies)) return;
    }
}

fn placeOne(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, spec: *const Spec, m: *const Makeup, bodies: *usize) bool {
    if (!actor.roomFor(bodies.*, m.kind[0])) return false;
    const others = pool.n;
    const lead = leadSpot(lv, pool, rng, start, spec, others) orelse return false;
    spawnCounted(lv, pool, m.kind[0], lead, bodies);
    for (m.kinds()[1..]) |k| {
        if (!actor.roomFor(bodies.*, k)) break;
        const at = spotNear(lv, pool, rng, lead, start, spec, others) orelse break;
        spawnCounted(lv, pool, k, at, bodies);
    }
    return true;
}

fn spawnCounted(lv: *grid.Level, pool: *actor.Pool, k: actor.Kind, at: P, bodies: *usize) void {
    _ = pool.spawn(lv, actor.Actor.of(k, at));
    bodies.* += actor.most(k);
}

/// Free, `spec.gap` from the start, and `spec.apart` from every foe of the packs placed before, the first `others`.
fn clear(lv: *const grid.Level, pool: *actor.Pool, p: P, start: P, spec: *const Spec, others: usize) bool {
    if (!lv.vacant(p) or mathx.dist(p, start) < spec.gap) return false;
    if (spec.apart == 0) return true;
    for (pool.items[0..others]) |*a| {
        if (a.foe() and mathx.dist(a.at, p) < spec.apart) return false;
    }
    return true;
}

fn leadSpot(lv: *const grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, spec: *const Spec, others: usize) ?P {
    for (0..SPOT_TRIES) |_| {
        const p = grid.Box.inMap(1).roll(rng);
        if (clear(lv, pool, p, start, spec, others)) return p;
    }
    return null;
}

fn spotNear(lv: *const grid.Level, pool: *actor.Pool, rng: *mathx.Rng, lead: P, start: P, spec: *const Spec, others: usize) ?P {
    var ring: i32 = 1;
    while (ring <= spec.reach) : (ring += 1) {
        var spots: [mathx.Ring.cells(REACH_MAX)]P = undefined;
        var n: usize = 0;
        var cells = mathx.Ring.init(lead, ring);
        while (cells.next()) |p| {
            if (!clear(lv, pool, p, start, spec, others) or !grid.clearLine(lv, lead, p)) continue;
            spots[n] = p;
            n += 1;
        }
        if (n > 0) return spots[rng.below(@intCast(n))];
    }
    return null;
}

test "every floor has a few of each foe at least, and every slime stands by a rat" {
    var lv: grid.Level = undefined;
    var counts = std.EnumArray(actor.Kind, usize).initFill(0);
    var fewest = std.EnumArray(actor.Kind, usize).initFill(actor.MAX);
    var lone_slimes: usize = 0;
    for (0..200) |i| {
        const seed: u64 = 0x9AC5 +% i *% 7919;
        const f = gen.build(&lv, seed);
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(seed);
        place(&lv, &pool, &rng, f.start, &.{});
        try std.testing.expect(pool.n >= PER_FLOOR and pool.n <= PER_FLOOR * BIGGEST);
        for (actor.FOES) |k| fewest.set(k, @min(fewest.get(k), pool.tally(k).total));
        for (pool.slice()) |a| {
            counts.getPtr(a.kind).* += 1;
            try std.testing.expect(!lv.hasBarrel(a.at) and lv.walkable(a.at));
            try std.testing.expect(mathx.dist(a.at, f.start) >= GAP);
            if (a.kind != .slime) continue;
            const by_rat = for (pool.slice()) |b| {
                if (b.kind == .rat and mathx.dist(a.at, b.at) <= REACH) break true;
            } else false;
            if (!by_rat) lone_slimes += 1;
        }
    }
    std.debug.print("200 floors, {d} packs each: {d} rats, {d} slimes, {d} bloats; the fewest on one floor {d} rats, {d} slimes, {d} bloats; {d} slimes with no rat beside them\n", .{ PER_FLOOR, counts.get(.rat), counts.get(.slime), counts.get(.bloat), fewest.get(.rat), fewest.get(.slime), fewest.get(.bloat), lone_slimes });
    try std.testing.expectEqual(@as(usize, 0), counts.get(.archer));
    try std.testing.expectEqual(@as(usize, 0), lone_slimes);
    try std.testing.expect(counts.get(.slime) < counts.get(.rat));
    for (actor.FOES) |k| try std.testing.expect(fewest.get(k) >= FEW);
}

test "a spec of its own makeups places only them, its packs kept apart and the pool never overfilled" {
    var lv: grid.Level = undefined;
    var spec = Spec{ .packs = 6, .few = 0, .apart = 10, .makeup_n = 1 };
    spec.makeup[0] = Makeup.of(&.{ .bloat, .bloat });
    var closest: i32 = APART_MAX;
    for (0..40) |i| {
        const seed: u64 = 0xA9A27 +% i *% 7919;
        const f = gen.build(&lv, seed);
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(seed);
        place(&lv, &pool, &rng, f.start, &spec);
        try std.testing.expect(pool.n <= 2 * spec.packs);
        for (pool.slice(), 0..) |a, k| {
            try std.testing.expectEqual(actor.Kind.bloat, a.kind);
            for (pool.slice()[0..k]) |b| {
                const d = mathx.dist(a.at, b.at);
                if (d > spec.reach * 2) closest = @min(closest, d);
            }
        }
    }
    var crowd = Spec{ .packs = PACKS_MAX, .few = 0, .gap = 0, .makeup_n = 1 };
    crowd.makeup[0] = Makeup.of(&.{ .rat, .rat, .rat, .rat, .rat });
    _ = gen.build(&lv, 0xC20D);
    var pool = actor.Pool{};
    var rng = mathx.Rng.init(0xC20D);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &crowd);
    const rats = pool.n;
    crowd.makeup[0] = Makeup.of(&.{ .slime, .slime, .slime, .slime, .slime });
    _ = gen.build(&lv, 0xC20D);
    pool = .{};
    _ = pool.spawn(&lv, actor.Actor.of(.archer, .{ .x = 0, .y = 0 }));
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &crowd);
    const slimes = pool.tally(.slime).total;
    std.debug.print("pairs of bloats 10 apart: the closest two of different packs {d} cells; 32 packs of 5 rats: {d} bodies; of 5 slimes, by an archer: {d} slimes\n", .{ closest, rats, slimes });
    try std.testing.expect(closest >= spec.apart);
    try std.testing.expectEqual(actor.MAX, rats);
    try std.testing.expectEqual(actor.MAX, 1 + slimes * actor.most(.slime) + 3);
    try std.testing.expect(!(Spec{ .makeup_n = 0 }).valid());
    try std.testing.expect((Spec{}).valid());
}

test "a makeup grows, shrinks to its lead and turns round the foe kinds; the last makeup stays" {
    var s = Spec{};
    while (s.addMakeup()) {}
    try std.testing.expectEqual(MAKEUPS_MAX, s.makeup_n);
    const m = &s.makeup[MAKEUPS_MAX - 1];
    while (m.grow()) {}
    try std.testing.expectEqual(MAKEUP_MAX, m.n);
    while (m.shrink()) {}
    try std.testing.expectEqual(@as(usize, 1), m.n);
    for (actor.FOES[1..]) |k| {
        m.turn(0);
        try std.testing.expectEqual(k, m.kind[0]);
    }
    m.turn(0);
    try std.testing.expectEqual(actor.FOES[0], m.kind[0]);
    try std.testing.expect(s.dropMakeup(0));
    try std.testing.expectEqualSlices(actor.Kind, KINDS[1], s.makeup[0].kinds());
    while (s.dropMakeup(0)) {}
    try std.testing.expectEqual(@as(usize, 1), s.makeup_n);
    try std.testing.expect(s.valid());
}
