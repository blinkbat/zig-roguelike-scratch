const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const gen = @import("../map/gen.zig");
const actor = @import("actor.zig");

const P = mathx.P;

pub const PER_FLOOR: usize = 14;
pub const FEW: usize = 1;
/// The first kind leads.
pub const KINDS = [_][]const actor.Kind{
    &.{ .rat, .slime },
    &.{ .rat, .rat, .slime },
    &.{.rat},
    &.{ .rat, .rat },
    &.{.bloat},
    &.{ .beefy_pib, .pib, .pib },
    &.{ .pib, .rat, .rat },
    &.{ .rat, .slime, .pib },
    &.{ .bandit_crossbowman, .rat, .rat },
    &.{ .bandit_shieldbearer, .bandit_crossbowman, .bandit_netter },
    &.{ .pib_shaman, .pib, .pib },
    &.{ .frost_wisp, .frost_wisp },
    &.{.pyre_bloat},
    &.{.bog_leech},
    &.{.mimic},
};
pub const REACH: i32 = 2;
/// Past the hero's sight, so by default none starts in view.
pub const GAP: i32 = 12;
pub const BIGGEST: usize = blk: {
    var most: usize = 0;
    for (KINDS) |k| most = @max(most, k.len);
    break :blk most;
};

pub const PACKS_MAX: usize = 32;
pub const FEW_MAX: usize = PACKS_MAX;
pub const MAKEUP_MIN: usize = 1;
pub const MAKEUP_MAX: usize = 5;
pub const MAKEUPS_MIN: usize = 1;
pub const MAKEUPS_MAX: usize = 16;
pub const WEIGHT_MIN: u8 = 1;
pub const WEIGHT_MAX: u8 = 9;
pub const FIRST = actor.FOES[0];
pub const REACH_MIN: i32 = 1;
pub const REACH_MAX: i32 = 4;
pub const GAP_MAX: i32 = 48;
pub const APART_MAX: i32 = 32;
const SPOT_TRIES: usize = 2000;

comptime {
    std.debug.assert(GAP > actor.row(actor.HERO).sight);
    std.debug.assert(FEW * actor.FOES.len <= PER_FLOOR);
    std.debug.assert(KINDS.len <= MAKEUPS_MAX and BIGGEST <= MAKEUP_MAX and REACH <= REACH_MAX);
    for (actor.FOES) |k| std.debug.assert((Spec{}).holders(k) > 0);
    std.debug.assert((Spec{}).valid());
}

pub const Makeup = struct {
    kind: [MAKEUP_MAX]actor.Kind = @splat(FIRST),
    n: usize = MAKEUP_MIN,
    weight: u8 = WEIGHT_MIN,

    pub fn of(ks: []const actor.Kind) Makeup {
        var m = Makeup{ .n = ks.len };
        @memcpy(m.kind[0..ks.len], ks);
        return m;
    }

    pub fn kinds(self: *const Makeup) []const actor.Kind {
        return self.kind[0..self.n];
    }

    fn lead(self: *const Makeup) actor.Kind {
        return self.kind[0];
    }

    fn followers(self: *const Makeup) []const actor.Kind {
        return self.kinds()[1..];
    }

    fn holds(self: *const Makeup, k: actor.Kind) bool {
        return std.mem.indexOfScalar(actor.Kind, self.kinds(), k) != null;
    }

    fn fits(self: *const Makeup, bodies: usize, k: ?actor.Kind) bool {
        if (!actor.roomFor(bodies, self.lead())) return false;
        const want = k orelse return true;
        var n = bodies;
        for (self.kinds()) |m| {
            if (!actor.roomFor(n, m)) continue;
            if (m == want) return true;
            n += actor.most(m);
        }
        return false;
    }

    pub fn canGrow(self: *const Makeup) bool {
        return self.n < MAKEUP_MAX;
    }

    pub fn canShrink(self: *const Makeup) bool {
        return self.n > MAKEUP_MIN;
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
        self.kind[i] = mathx.stepIn(actor.Kind, &actor.FOES, self.kind[i], 1, actor.FOES.len - 1);
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
    /// Cells from where the hero arrives to every foe, at least.
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
        return self.makeup_n > MAKEUPS_MIN;
    }

    pub fn addMakeup(self: *Spec) bool {
        if (!self.canAdd()) return false;
        self.makeup[self.makeup_n] = .{};
        self.makeup_n += 1;
        return true;
    }

    pub fn dropMakeup(self: *Spec, i: usize) bool {
        if (!self.canDrop()) return false;
        mathx.removeAt(Makeup, &self.makeup, &self.makeup_n, i, .{});
        return true;
    }

    pub fn fit(s: Spec) Spec {
        var t = s;
        t.packs = @min(s.packs, PACKS_MAX);
        t.few = @min(s.few, FEW_MAX);
        t.reach = std.math.clamp(s.reach, REACH_MIN, REACH_MAX);
        t.gap = std.math.clamp(s.gap, 0, GAP_MAX);
        t.apart = std.math.clamp(s.apart, 0, APART_MAX);
        t.makeup_n = std.math.clamp(s.makeup_n, MAKEUPS_MIN, MAKEUPS_MAX);
        for (t.makeup[0..t.makeup_n]) |*m| {
            m.n = std.math.clamp(m.n, MAKEUP_MIN, MAKEUP_MAX);
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

    /// `homeless`: the kinds no lead could be found ground for.
    fn pick(self: *const Spec, rng: *mathx.Rng, k: ?actor.Kind, bodies: usize, homeless: Kinds) ?*const Makeup {
        const Holding = struct {
            spec: *const Spec,
            k: ?actor.Kind,
            bodies: usize,
            homeless: Kinds,

            fn weight(h: @This(), i: usize) u32 {
                const m = &h.spec.makeups()[i];
                return if (!h.homeless.contains(m.lead()) and m.fits(h.bodies, h.k)) m.weight else 0;
            }
        };
        return &self.makeups()[rng.weighted(self.makeup_n, Holding{ .spec = self, .k = k, .bodies = bodies, .homeless = homeless }, Holding.weight) orelse return null];
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

const Kinds = std.EnumSet(actor.Kind);

/// No more than the pool holds once every slime placed has split down to quarters.
/// A makeup whose lead finds no ground of its own, as a leech on a dry floor, gives way to the rest.
pub fn place(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, given: *const Spec) void {
    const fitted = given.fit();
    const spec = &fitted;
    var bodies = pool.n;
    var homeless = Kinds.initEmpty();
    var packs: usize = 0;
    for (spec.quotaOrder()) |k| {
        while (packs < spec.packs and pool.tally(k).total < spec.few) {
            const m = spec.pick(rng, k, bodies, homeless) orelse break;
            if (placeOne(lv, pool, rng, start, spec, m, &bodies)) packs += 1 else homeless.insert(m.lead());
        }
    }
    while (packs < spec.packs) {
        const m = spec.pick(rng, null, bodies, homeless) orelse return;
        if (placeOne(lv, pool, rng, start, spec, m, &bodies)) packs += 1 else homeless.insert(m.lead());
    }
}

fn placeOne(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, spec: *const Spec, m: *const Makeup, bodies: *usize) bool {
    const others = pool.n;
    const lead = leadSpot(lv, pool, rng, start, spec, others, m.lead()) orelse return false;
    spawnCounted(lv, pool, m.lead(), lead, bodies);
    for (m.followers()) |k| {
        if (!actor.roomFor(bodies.*, k)) continue;
        const at = spotNear(lv, pool, rng, lead, start, spec, others, k) orelse continue;
        spawnCounted(lv, pool, k, at, bodies);
    }
    return true;
}

fn spawnCounted(lv: *grid.Level, pool: *actor.Pool, k: actor.Kind, at: P, bodies: *usize) void {
    _ = pool.spawn(lv, actor.Actor.of(k, at));
    bodies.* += actor.most(k);
}

/// `others` bounds the previously placed packs.
fn clear(lv: *const grid.Level, pool: *actor.Pool, p: P, start: P, spec: *const Spec, others: usize, k: actor.Kind) bool {
    if (!actor.dwells(k, lv, p) or mathx.dist(p, start) < spec.gap) return false;
    if (spec.apart == 0) return true;
    for (pool.items[0..others]) |*a| {
        if (a.foe() and mathx.dist(a.at, p) < spec.apart) return false;
    }
    return true;
}

fn leadSpot(lv: *const grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, spec: *const Spec, others: usize, k: actor.Kind) ?P {
    const Clear = struct {
        lv: *const grid.Level,
        pool: *actor.Pool,
        start: P,
        spec: *const Spec,
        others: usize,
        k: actor.Kind,

        fn at(c: @This(), p: P) bool {
            return clear(c.lv, c.pool, p, c.start, c.spec, c.others, c.k);
        }
    };
    return grid.Box.inMap(1).rollWhere(rng, SPOT_TRIES, Clear{ .lv = lv, .pool = pool, .start = start, .spec = spec, .others = others, .k = k }, Clear.at);
}

fn spotNear(lv: *const grid.Level, pool: *actor.Pool, rng: *mathx.Rng, lead: P, start: P, spec: *const Spec, others: usize, k: actor.Kind) ?P {
    var ring: i32 = 1;
    while (ring <= spec.reach) : (ring += 1) {
        var spots: [mathx.Ring.cells(REACH_MAX)]P = undefined;
        var n: usize = 0;
        var cells = mathx.Ring.init(lead, ring);
        while (cells.next()) |p| {
            if (!clear(lv, pool, p, start, spec, others, k) or !grid.clearLine(lv, lead, p)) continue;
            spots[n] = p;
            n += 1;
        }
        if (n > 0) return rng.pick(P, spots[0..n]);
    }
    return null;
}

test "every floor has a few of each foe it has ground for, each on its own ground, slimes by rats and crossbowmen by rats or shields" {
    var lv: grid.Level = undefined;
    var counts = std.EnumArray(actor.Kind, usize).initFill(0);
    var fewest = std.EnumArray(actor.Kind, usize).initFill(actor.MAX);
    var lone_slimes: usize = 0;
    var lone_bandits: usize = 0;
    var dry: usize = 0;
    for (0..200) |i| {
        const seed: u64 = 0x9AC5 +% i *% grid.TEST_SEED_STRIDE;
        const f = gen.build(&lv, seed);
        var housed = Kinds.initEmpty();
        for (0..grid.CELLS) |c| for (actor.FOES) |k| {
            const p = grid.Level.of(c);
            if (mathx.dist(p, f.start) >= GAP and actor.dwells(k, &lv, p)) housed.insert(k);
        };
        dry += @intFromBool(!housed.contains(.bog_leech));
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(seed);
        place(&lv, &pool, &rng, f.start, &.{});
        try std.testing.expect(pool.n >= PER_FLOOR and pool.n <= PER_FLOOR * BIGGEST);
        for (actor.FOES) |k| if (housed.contains(k)) fewest.set(k, @min(fewest.get(k), pool.tally(k).total));
        for (pool.slice()) |a| {
            counts.getPtr(a.kind).* += 1;
            try std.testing.expect(!lv.hasBarrel(a.at) and mathx.dist(a.at, f.start) >= GAP);
            switch (actor.row(a.kind).movement) {
                .swimming => try std.testing.expect(lv.at(a.at).wet()),
                else => try std.testing.expect(if (a.disguised) lv.at(a.at) == .chest and a.under.rewards() else lv.walkable(a.at)),
            }
            if (a.kind != .slime and a.kind != .bandit_crossbowman) continue;
            const guarded = for (pool.slice()) |b| {
                const guard = b.kind == .rat or (a.kind == .bandit_crossbowman and b.kind == .bandit_shieldbearer);
                if (guard and mathx.dist(a.at, b.at) <= REACH) break true;
            } else false;
            if (!guarded) {
                if (a.kind == .slime) lone_slimes += 1 else lone_bandits += 1;
            }
        }
    }
    std.debug.print("200 floors, {d} packs each, {d} with no water for leeches:\n", .{ PER_FLOOR, dry });
    for (actor.FOES) |k| std.debug.print("  {s}: {d} total, at least {d} on each floor with ground for it\n", .{ actor.plural(k), counts.get(k), fewest.get(k) });
    std.debug.print("unguarded: {d} slimes, {d} crossbowmen\n", .{ lone_slimes, lone_bandits });
    try std.testing.expectEqual(@as(usize, 0), counts.get(.archer));
    try std.testing.expectEqual(@as(usize, 0), lone_slimes);
    try std.testing.expectEqual(@as(usize, 0), lone_bandits);
    try std.testing.expect(counts.get(.slime) < counts.get(.rat));
    for (actor.FOES) |k| try std.testing.expect(fewest.get(k) >= FEW);
}

test "a pack whose lead has no ground of its own gives way without costing the floor a pack" {
    var lv = grid.openFloor();
    var spec = Spec{ .packs = 4, .few = 0, .gap = 0, .makeup_n = 2 };
    spec.makeup[0] = Makeup.of(&.{.bog_leech});
    spec.makeup[0].weight = WEIGHT_MAX;
    spec.makeup[1] = Makeup.of(&.{.rat});
    var pool = actor.Pool{};
    var rng = mathx.Rng.init(0x1EEC);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &spec);
    try std.testing.expectEqual(@as(usize, 4), pool.tally(.rat).total);
    try std.testing.expectEqual(@as(usize, 0), pool.tally(.bog_leech).total);
    pool = .{};
    lv = grid.openFloor();
    var cells = grid.Cells.of(.{ .x = 30, .y = 30 }, .{ .x = 34, .y = 33 });
    while (cells.next()) |p| lv.set(p, .water);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &spec);
    try std.testing.expect(pool.tally(.bog_leech).total > 0);
    for (pool.slice()) |a| if (a.kind == .bog_leech) try std.testing.expectEqual(grid.Tile.water, lv.at(a.at));
    std.debug.print("a leech-led makeup weighted {d} to 1: a dry floor still takes 4 rat packs; with a pond, {d} leeches swim in it\n", .{ WEIGHT_MAX, pool.tally(.bog_leech).total });
}

test "a spec of its own makeups places only them, its packs kept apart and the pool never overfilled" {
    var lv: grid.Level = undefined;
    var spec = Spec{ .packs = 6, .few = 0, .apart = 10, .makeup_n = 1 };
    spec.makeup[0] = Makeup.of(&.{ .bloat, .bloat });
    var closest: i32 = APART_MAX;
    for (0..40) |i| {
        const seed: u64 = 0xA9A27 +% i *% grid.TEST_SEED_STRIDE;
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
    std.debug.print("pairs of caustic bloats 10 apart: the closest two of different packs {d} cells; 32 packs of 5 rats: {d} bodies; of 5 slimes, by an archer: {d} slimes\n", .{ closest, rats, slimes });
    try std.testing.expect(closest >= spec.apart);
    try std.testing.expectEqual(actor.MAX, rats);
    try std.testing.expectEqual(actor.MAX, 1 + slimes * actor.most(.slime) + 3);
    try std.testing.expect(!(Spec{ .makeup_n = 0 }).valid());
    try std.testing.expect((Spec{}).valid());
}

test "a kind's quota the pool has no more room for gives way to the next kind's" {
    var lv: grid.Level = undefined;
    var spec = Spec{ .packs = PACKS_MAX, .few = FEW_MAX, .gap = 0, .makeup_n = 3 };
    spec.makeup[0] = Makeup.of(&.{.slime});
    spec.makeup[1] = Makeup.of(&.{.rat});
    spec.makeup[2] = Makeup.of(&.{.rat});
    _ = gen.build(&lv, 0x5EED);
    var pool = actor.Pool{};
    _ = pool.spawn(&lv, actor.Actor.of(.archer, .{ .x = 0, .y = 0 }));
    var rng = mathx.Rng.init(0x5EED);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &spec);
    const slimes = pool.tally(.slime).total;
    const rats = pool.tally(.rat).total;
    std.debug.print("slimes first, then rats, by an archer: {d} slimes, {d} rats\n", .{ slimes, rats });
    try std.testing.expectEqual(actor.MAX, 1 + slimes * actor.most(.slime) + rats);
    try std.testing.expect(rats > 0);
}

test "a quota skips a makeup whose lead the pool has no room for, for one holding the kind that fits" {
    var lv: grid.Level = undefined;
    var spec = Spec{ .packs = 2, .gap = 0, .makeup_n = 2 };
    spec.makeup[0] = Makeup.of(&.{ .slime, .pib });
    spec.makeup[0].weight = WEIGHT_MAX;
    spec.makeup[1] = Makeup.of(&.{.pib});
    _ = gen.build(&lv, 0x5EED);
    var pool = actor.Pool{};
    _ = pool.spawn(&lv, actor.Actor.of(.archer, grid.Level.of(0)));
    for (1..actor.MAX - 2) |i| _ = pool.spawn(&lv, actor.Actor.of(.rat, grid.Level.of(i)));
    var rng = mathx.Rng.init(0x5EED);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &spec);
    std.debug.print("two places left, a slime-led makeup weighted {d} to 1: {d} pibs\n", .{ WEIGHT_MAX, pool.tally(.pib).total });
    try std.testing.expectEqual(@as(usize, 2), pool.tally(.pib).total);
    try std.testing.expectEqual(@as(usize, 0), pool.tally(.slime).total);
}

test "a makeup grows, shrinks to its lead and turns round the foe kinds; the last makeup stays" {
    var s = Spec{};
    while (s.addMakeup()) {}
    try std.testing.expectEqual(MAKEUPS_MAX, s.makeup_n);
    const m = &s.makeup[MAKEUPS_MAX - 1];
    m.* = .{};
    while (m.grow()) {}
    try std.testing.expectEqual(MAKEUP_MAX, m.n);
    while (m.shrink()) {}
    try std.testing.expectEqual(@as(usize, 1), m.n);
    for (actor.FOES[1..]) |k| {
        m.turn(0);
        try std.testing.expectEqual(k, m.lead());
    }
    m.turn(0);
    try std.testing.expectEqual(actor.FOES[0], m.lead());
    try std.testing.expect(s.dropMakeup(0));
    try std.testing.expectEqualSlices(actor.Kind, KINDS[1], s.makeup[0].kinds());
    while (s.dropMakeup(0)) {}
    try std.testing.expectEqual(@as(usize, 1), s.makeup_n);
    try std.testing.expect(s.valid());
}
