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
    &.{ .goblin, .goblin },
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
/// Cells from a caravan cart to every foe placed, at least.
pub const CAMP_GAP: i32 = 10;
pub const FEW_MAX: usize = PACKS_MAX;
pub const MAKEUP_MIN: usize = 1;
pub const MAKEUP_MAX: usize = 5;
pub const MAKEUPS_MIN: usize = 1;
pub const MAKEUPS_MAX: usize = 16;
pub const WEIGHT_MIN: u8 = 1;
pub const WEIGHT_MAX: u8 = 9;
pub const COUNT_MIN: u8 = 1;
pub const COUNT_MAX: u8 = 9;
/// Cells from a door to an exit pack's lead, at most.
pub const EXIT_REACH: i32 = 6;
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

pub const Draw = union(enum) {
    weight: u8,
    /// Exactly this many packs, placed before any is drawn by weight.
    count: u8,

    pub fn flipped(d: Draw) Draw {
        return switch (d) {
            .weight => .{ .count = COUNT_MIN },
            .count => .{ .weight = WEIGHT_MIN },
        };
    }
};

/// Where a makeup's lead stands, when not by a door.
pub const Lair = enum {
    anywhere,
    /// At the end of a narrow dead-end path.
    nook,
    /// In or within `POND_REACH` of a small body of water.
    pond,
    /// Within `HEARTH_REACH` of a lone fire, as a camp's.
    hearth,
};

/// Wet cells joined together, at most, that are a pond rather than a river or a sea.
pub const POND_MOST: usize = 200;
pub const POND_REACH: i32 = 2;
pub const HEARTH_REACH: i32 = 3;
/// A nook's walk this many steps back reaches no more than `NOOK_CELLS`.
const NOOK_STEPS: i32 = 6;
const NOOK_CELLS: usize = 32;
/// Open cells round a nook, at most.
const NOOK_SIDES: usize = 3;
/// Cells in from the map's edge a nook keeps, so a road's end at the rim is none.
const NOOK_RIM: i32 = 3;

pub const Makeup = struct {
    kind: [MAKEUP_MAX]actor.Kind = @splat(FIRST),
    n: usize = MAKEUP_MIN,
    draw: Draw = .{ .weight = WEIGHT_MIN },
    /// The lead stands within `EXIT_REACH` of a door.
    exit: bool = false,
    /// Where the lead stands otherwise.
    lair: Lair = .anywhere,

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
        return self.canGrow() and mathx.push(actor.Kind, &self.kind, &self.n, FIRST);
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
        return self.canAdd() and mathx.push(Makeup, &self.makeup, &self.makeup_n, .{});
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
            if (m.exit) m.lair = .anywhere;
            switch (m.draw) {
                .weight => |*w| w.* = std.math.clamp(w.*, WEIGHT_MIN, WEIGHT_MAX),
                .count => |*c| c.* = std.math.clamp(c.*, COUNT_MIN, COUNT_MAX),
            }
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

    fn pick(self: *const Spec, rng: *mathx.Rng, k: ?actor.Kind, bodies: usize, homeless: Homeless) ?*const Makeup {
        const Holding = struct {
            spec: *const Spec,
            k: ?actor.Kind,
            bodies: usize,
            homeless: Homeless,

            fn weight(h: @This(), i: usize) u32 {
                const m = &h.spec.makeups()[i];
                const w = switch (m.draw) {
                    .weight => |w| w,
                    .count => return 0,
                };
                return if (!h.homeless.refuses(m) and m.fits(h.bodies, h.k)) w else 0;
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

/// The leads no ground could be found for anywhere, those found none by any door, and none in each lair.
const Homeless = struct {
    anywhere: Kinds = .initEmpty(),
    by_door: Kinds = .initEmpty(),
    lairs: std.EnumArray(Lair, Kinds) = .initFill(.initEmpty()),

    fn refuses(h: Homeless, m: *const Makeup) bool {
        return h.anywhere.contains(m.lead()) or h.of(m).contains(m.lead());
    }

    fn add(h: *Homeless, m: *const Makeup) void {
        h.ofMut(m).insert(m.lead());
    }

    fn of(h: *const Homeless, m: *const Makeup) *const Kinds {
        return @constCast(h).ofMut(m);
    }

    fn ofMut(h: *Homeless, m: *const Makeup) *Kinds {
        if (m.exit) return &h.by_door;
        return if (m.lair == .anywhere) &h.anywhere else h.lairs.getPtr(m.lair);
    }
};

/// The cells each lair a spec's makeups name holds; only those named are found.
const Lairs = struct {
    cells: std.EnumArray(Lair, grid.CellSet) = .initFill(.initEmpty()),

    fn of(lv: *const grid.Level, spec: *const Spec) Lairs {
        var named = std.EnumSet(Lair).initEmpty();
        for (spec.makeups()) |*m| if (!m.exit) named.insert(m.lair);
        var out = Lairs{};
        if (named.contains(.nook)) out.cells.set(.nook, nooks(lv));
        if (named.contains(.pond)) out.cells.set(.pond, widened(ponds(lv), POND_REACH));
        if (named.contains(.hearth)) out.cells.set(.hearth, widened(fires(lv), HEARTH_REACH));
        return out;
    }
};

/// Open cells at the end of a narrow dead-end path: few open round them, and a short walk back reaching little.
fn nooks(lv: *const grid.Level) grid.CellSet {
    var out = grid.CellSet.initEmpty();
    for (0..grid.CELLS) |i| {
        const q = grid.Level.of(i);
        if (grid.Level.edgeDist(q) < NOOK_RIM or !lv.walkable(q) or lv.tile[i].wet()) continue;
        var sides: usize = 0;
        var round = grid.Cells.around(q, 1);
        while (round.next()) |n| sides += @intFromBool(!n.eq(q) and lv.walkable(n));
        if (sides <= NOOK_SIDES and walkReaches(lv, q, NOOK_STEPS, NOOK_CELLS)) out.set(i);
    }
    return out;
}

/// No more than `most` cells lie within `steps` steps' walk of `from`.
fn walkReaches(lv: *const grid.Level, from: P, comptime steps: i32, most: usize) bool {
    const w = 2 * steps + 1;
    var seen = [_]bool{false} ** (w * w);
    var queue: [w * w]P = undefined;
    var depth: [w * w]i32 = undefined;
    const Window = struct {
        fn slot(o: P, q: P) ?usize {
            return mathx.slot(q.x - o.x + steps, q.y - o.y + steps, w, w);
        }
    };
    seen[Window.slot(from, from).?] = true;
    queue[0] = from;
    depth[0] = 0;
    var n: usize = 1;
    var at: usize = 0;
    while (at < n) : (at += 1) {
        if (depth[at] == steps) continue;
        var round = grid.Cells.around(queue[at], 1);
        while (round.next()) |q| {
            const k = Window.slot(from, q) orelse continue;
            if (seen[k] or !lv.walkable(q)) continue;
            seen[k] = true;
            if (n == most) return false;
            queue[n] = q;
            depth[n] = depth[at] + 1;
            n += 1;
        }
    }
    return true;
}

/// Wet cells in bodies of no more than `POND_MOST` joined cells.
fn ponds(lv: *const grid.Level) grid.CellSet {
    var out = grid.CellSet.initEmpty();
    var seen = grid.CellSet.initEmpty();
    var queue: [grid.CELLS]u16 = undefined;
    for (0..grid.CELLS) |i| {
        if (seen.isSet(i) or !lv.tile[i].wet()) continue;
        seen.set(i);
        queue[0] = @intCast(i);
        var n: usize = 1;
        var at: usize = 0;
        while (at < n) : (at += 1) {
            var round = grid.Cells.around(grid.Level.of(queue[at]), 1);
            while (round.next()) |q| {
                if (!grid.Level.inside(q)) continue;
                const k = grid.Level.idx(q);
                if (seen.isSet(k) or !lv.tile[k].wet()) continue;
                seen.set(k);
                queue[n] = @intCast(k);
                n += 1;
            }
        }
        if (n <= POND_MOST) for (queue[0..n]) |k| out.set(k);
    }
    return out;
}

/// Lava cells with no lava beside them: camp fires, not lava fields.
fn fires(lv: *const grid.Level) grid.CellSet {
    var out = grid.CellSet.initEmpty();
    for (0..grid.CELLS) |i| {
        if (lv.tile[i] != .lava) continue;
        var round = grid.Cells.around(grid.Level.of(i), 1);
        const lone = while (round.next()) |q| {
            if (!q.eq(grid.Level.of(i)) and grid.Level.inside(q) and lv.at(q) == .lava) break false;
        } else true;
        if (lone) out.set(i);
    }
    return out;
}

/// Every cell within `r` of one of `cells`.
fn widened(cells: grid.CellSet, r: i32) grid.CellSet {
    var out = grid.CellSet.initEmpty();
    var it = cells.iterator(.{});
    while (it.next()) |i| {
        var round = grid.Cells.around(grid.Level.of(i), r);
        while (round.next()) |q| if (grid.Level.inside(q)) out.set(grid.Level.idx(q));
    }
    return out;
}

/// No more than the pool holds once every slime placed has split down to quarters.
/// A makeup whose lead finds no ground of its own, as a leech on a dry floor, gives way to the rest.
pub fn place(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, exits: []const P, given: *const Spec) void {
    const fitted = given.fit();
    const spec = &fitted;
    const camp = campOf(lv);
    const lairs = Lairs.of(lv, spec);
    var bodies = pool.n;
    var homeless = Homeless{};
    var packs: usize = 0;
    for (spec.makeups()) |*m| {
        const count = switch (m.draw) {
            .count => |c| c,
            .weight => continue,
        };
        for (0..count) |_| {
            if (packs == spec.packs or !m.fits(bodies, null) or !placeOne(lv, pool, rng, start, exits, spec, &camp, &lairs, m, &bodies)) break;
            packs += 1;
        }
    }
    for (spec.quotaOrder()) |k| {
        while (packs < spec.packs and pool.tally(k).total < spec.few) {
            const m = spec.pick(rng, k, bodies, homeless) orelse break;
            const before = pool.tally(k).total;
            if (!placeOne(lv, pool, rng, start, exits, spec, &camp, &lairs, m, &bodies)) {
                homeless.add(m);
                continue;
            }
            packs += 1;
            if (pool.tally(k).total == before) break;
        }
    }
    while (packs < spec.packs) {
        const m = spec.pick(rng, null, bodies, homeless) orelse return;
        if (placeOne(lv, pool, rng, start, exits, spec, &camp, &lairs, m, &bodies)) packs += 1 else homeless.add(m);
    }
}

/// An exit makeup's lead tries a door at random, then each other door in turn; a lair's, any cell of it.
fn placeOne(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, exits: []const P, spec: *const Spec, camp: *const grid.CellSet, lairs: *const Lairs, m: *const Makeup, bodies: *usize) bool {
    const ground = Ground{ .lv = lv, .pool = pool, .start = start, .spec = spec, .camp = camp, .others = pool.n };
    const lead = if (!m.exit) (if (m.lair == .anywhere) ground.leadSpot(rng, null, m.lead()) else ground.leadIn(rng, lairs.cells.getPtrConst(m.lair), m.lead())) orelse return false else lead: {
        if (exits.len == 0) return false;
        const first = rng.below(@intCast(exits.len));
        for (0..exits.len) |k| {
            const by = exits[(first + k) % exits.len];
            if (ground.leadSpot(rng, by, m.lead())) |p| break :lead p;
        }
        return false;
    };
    spawnCounted(lv, pool, m.lead(), lead, bodies);
    for (m.followers()) |k| {
        if (!actor.roomFor(bodies.*, k)) continue;
        const at = ground.spotNear(rng, lead, k) orelse continue;
        spawnCounted(lv, pool, k, at, bodies);
    }
    return true;
}

fn spawnCounted(lv: *grid.Level, pool: *actor.Pool, k: actor.Kind, at: P, bodies: *usize) void {
    _ = pool.spawn(lv, actor.Actor.of(k, at));
    bodies.* += actor.most(k);
}

/// The cells closer than `CAMP_GAP` to a caravan cart.
fn campOf(lv: *const grid.Level) grid.CellSet {
    var near = grid.CellSet.initEmpty();
    for (0..grid.CELLS) |i| {
        if (lv.tile[i] != .caravan and lv.tile[i] != .caravan_part) continue;
        var cells = grid.Cells.around(grid.Level.of(i), CAMP_GAP - 1);
        while (cells.next()) |q| {
            if (grid.Level.inside(q)) near.set(grid.Level.idx(q));
        }
    }
    return near;
}

/// Where one pack's bodies may stand; `others` bounds the previously placed packs.
const Ground = struct {
    lv: *const grid.Level,
    pool: *const actor.Pool,
    start: P,
    spec: *const Spec,
    camp: *const grid.CellSet,
    others: usize,

    fn clear(g: Ground, p: P, k: actor.Kind) bool {
        if (!actor.dwells(k, g.lv, p) or mathx.dist(p, g.start) < g.spec.gap or g.camp.isSet(grid.Level.idx(p))) return false;
        if (g.spec.apart == 0) return true;
        for (g.pool.items[0..g.others]) |*a| {
            if (a.foe() and mathx.dist(a.at, p) < g.spec.apart) return false;
        }
        return true;
    }

    /// `by`: the door the lead must stand within `EXIT_REACH` of.
    fn leadSpot(g: Ground, rng: *mathx.Rng, by: ?P, k: actor.Kind) ?P {
        const Lead = struct {
            ground: Ground,
            k: actor.Kind,

            fn at(l: @This(), p: P) bool {
                return grid.Box.inMap(1).holds(p) and l.ground.clear(p, l.k);
            }
        };
        const box = if (by) |d| grid.Box.around(d, EXIT_REACH) else grid.Box.inMap(1);
        return box.rollWhere(rng, SPOT_TRIES, Lead{ .ground = g, .k = k }, Lead.at);
    }

    /// Any clear cell of `lair`, each as likely.
    fn leadIn(g: Ground, rng: *mathx.Rng, lair: *const grid.CellSet, k: actor.Kind) ?P {
        var chosen: ?P = null;
        var seen: u32 = 0;
        var it = lair.iterator(.{});
        while (it.next()) |i| {
            const p = grid.Level.of(i);
            if (!grid.Box.inMap(1).holds(p) or !g.clear(p, k)) continue;
            seen += 1;
            if (rng.below(seen) == 0) chosen = p;
        }
        return chosen;
    }

    fn spotNear(g: Ground, rng: *mathx.Rng, lead: P, k: actor.Kind) ?P {
        var ring: i32 = 1;
        while (ring <= g.spec.reach) : (ring += 1) {
            var spots: [mathx.Ring.cells(REACH_MAX)]P = undefined;
            var n: usize = 0;
            var cells = mathx.Ring.init(lead, ring);
            while (cells.next()) |p| {
                if (!g.clear(p, k) or !grid.clearLine(g.lv, lead, p)) continue;
                spots[n] = p;
                n += 1;
            }
            if (n > 0) return rng.pick(P, spots[0..n]);
        }
        return null;
    }
};

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
        place(&lv, &pool, &rng, f.start, &.{}, &.{});
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
    spec.makeup[0].draw = .{ .weight = WEIGHT_MAX };
    spec.makeup[1] = Makeup.of(&.{.rat});
    var pool = actor.Pool{};
    var rng = mathx.Rng.init(0x1EEC);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &.{}, &spec);
    try std.testing.expectEqual(@as(usize, 4), pool.tally(.rat).total);
    try std.testing.expectEqual(@as(usize, 0), pool.tally(.bog_leech).total);
    pool = .{};
    lv = grid.openFloor();
    var cells = grid.Cells.of(.{ .x = 30, .y = 30 }, .{ .x = 34, .y = 33 });
    while (cells.next()) |p| lv.set(p, .water);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &.{}, &spec);
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
        place(&lv, &pool, &rng, f.start, &.{}, &spec);
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
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &.{}, &crowd);
    const rats = pool.n;
    crowd.makeup[0] = Makeup.of(&.{ .slime, .slime, .slime, .slime, .slime });
    _ = gen.build(&lv, 0xC20D);
    pool = .{};
    _ = pool.spawn(&lv, actor.Actor.of(.archer, .{ .x = 0, .y = 0 }));
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &.{}, &crowd);
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
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &.{}, &spec);
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
    spec.makeup[0].draw = .{ .weight = WEIGHT_MAX };
    spec.makeup[1] = Makeup.of(&.{.pib});
    _ = gen.build(&lv, 0x5EED);
    var pool = actor.Pool{};
    _ = pool.spawn(&lv, actor.Actor.of(.archer, grid.Level.of(0)));
    for (1..actor.MAX - 2) |i| _ = pool.spawn(&lv, actor.Actor.of(.rat, grid.Level.of(i)));
    var rng = mathx.Rng.init(0x5EED);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &.{}, &spec);
    std.debug.print("two places left, a slime-led makeup weighted {d} to 1: {d} pibs\n", .{ WEIGHT_MAX, pool.tally(.pib).total });
    try std.testing.expectEqual(@as(usize, 2), pool.tally(.pib).total);
    try std.testing.expectEqual(@as(usize, 0), pool.tally(.slime).total);
}

test "a quota whose makeup places its lead but not the kind gives way to the next kind's" {
    var lv = grid.openFloor();
    var spec = Spec{ .packs = 14, .few = 1, .gap = 0, .makeup_n = 3 };
    spec.makeup[0] = Makeup.of(&.{ .rat, .bog_leech });
    spec.makeup[1] = Makeup.of(&.{.pib});
    spec.makeup[2] = Makeup.of(&.{ .pib, .rat });
    var pool = actor.Pool{};
    var rng = mathx.Rng.init(0x5EED);
    place(&lv, &pool, &rng, .{ .x = 0, .y = 0 }, &.{}, &spec);
    const pibs = pool.tally(.pib).total;
    std.debug.print("a leech-holding makeup on a dry floor: no leeches, {d} pibs still placed\n", .{pibs});
    try std.testing.expectEqual(@as(usize, 0), pool.tally(.bog_leech).total);
    try std.testing.expect(pibs >= spec.few);
}

test "a counted makeup places exactly its packs, an exit one's lead by a door, and is never drawn by weight" {
    var lv: grid.Level = undefined;
    const door = P{ .x = grid.W - 2, .y = 20 };
    var spec = Spec{ .packs = 8, .few = 0, .gap = 0, .makeup_n = 3 };
    spec.makeup[0] = Makeup.of(&.{ .beefy_pib, .pib, .pib });
    spec.makeup[0].draw = .{ .count = 1 };
    spec.makeup[0].exit = true;
    spec.makeup[1] = Makeup.of(&.{.bloat});
    spec.makeup[1].draw = .{ .count = 2 };
    spec.makeup[2] = Makeup.of(&.{ .rat, .rat });
    var farthest: i32 = 0;
    for (0..50) |i| {
        lv = grid.openFloor();
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(0xE417 +% i);
        place(&lv, &pool, &rng, .{ .x = 1, .y = 1 }, &.{door}, &spec);
        try std.testing.expectEqual(@as(usize, 1), pool.tally(.beefy_pib).total);
        try std.testing.expectEqual(@as(usize, 2), pool.tally(.bloat).total);
        try std.testing.expectEqual(@as(usize, 10), pool.tally(.rat).total);
        for (pool.slice()) |a| if (a.kind == .beefy_pib) {
            farthest = @max(farthest, mathx.dist(a.at, door));
        };
    }
    std.debug.print("50 rolls of 8 packs, one beefy pib by the door and two bloats counted: beefy pib at most {d} cells from the door\n", .{farthest});
    try std.testing.expect(farthest <= EXIT_REACH);
}

test "an exit pack that no door can hold leaves its lead's other makeups be, and tries every door before giving up" {
    var spec = Spec{ .packs = 4, .few = 0, .gap = 12, .makeup_n = 2 };
    spec.makeup[0] = Makeup.of(&.{.rat});
    spec.makeup[0].exit = true;
    spec.makeup[0].draw = .{ .weight = WEIGHT_MAX };
    spec.makeup[1] = Makeup.of(&.{ .rat, .rat });
    const start = P{ .x = 2, .y = 2 };
    const far = P{ .x = grid.W - 3, .y = grid.H - 3 };
    var doorless: usize = 0;
    var by_far: usize = 0;
    for (0..50) |i| {
        var lv = grid.openFloor();
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(0xD00E +% i);
        place(&lv, &pool, &rng, start, &.{}, &spec);
        doorless += pool.tally(.rat).total;
        try std.testing.expectEqual(@as(usize, 2 * spec.packs), pool.tally(.rat).total);
        var counted = spec;
        counted.makeup[0] = Makeup.of(&.{.bloat});
        counted.makeup[0].exit = true;
        counted.makeup[0].draw = .{ .count = 1 };
        lv = grid.openFloor();
        pool = .{};
        place(&lv, &pool, &rng, start, &.{ start, far }, &counted);
        for (pool.slice()) |a| if (a.kind == .bloat) {
            try std.testing.expect(mathx.dist(a.at, far) <= EXIT_REACH);
            by_far += 1;
        };
    }
    try std.testing.expectEqual(@as(usize, 50), by_far);
    std.debug.print("exit packs: 50 doorless nodes still laid {d} rats in pairs; a counted exit pack, the arrival door too near, stood by the far door {d} of 50\n", .{ doorless, by_far });
}

test "lairs: a mimic at a winding trail's end, leeches in the pond and slimes by it, goblins by their camps' fires" {
    const procgen = @import("../map/procgen.zig");
    const lairs = [_]struct { lair: Lair, kinds: []const actor.Kind, count: u8 }{
        .{ .lair = .nook, .kinds = &.{.mimic}, .count = 1 },
        .{ .lair = .pond, .kinds = &.{ .bog_leech, .bog_leech }, .count = 1 },
        .{ .lair = .pond, .kinds = &.{ .slime, .slime }, .count = 1 },
        .{ .lair = .hearth, .kinds = &.{ .goblin, .goblin }, .count = 2 },
    };
    var spec = Spec{ .packs = 5, .few = 0, .makeup_n = lairs.len };
    for (lairs, 0..) |l, i| {
        spec.makeup[i] = Makeup.of(l.kinds);
        spec.makeup[i].lair = l.lair;
        spec.makeup[i].draw = .{ .count = l.count };
    }
    const door = P{ .x = 0, .y = 46 };
    const RUNS = 50;
    var placed = std.EnumArray(actor.Kind, usize).initFill(0);
    var astray: usize = 0;
    var nooks_seen: usize = 0;
    for (0..RUNS) |i| {
        var lv: grid.Level = undefined;
        procgen.roll(&lv, 0x1A12 +% i *% grid.TEST_SEED_STRIDE, &.{door}, .{ .tee = .{ .spurs = 6, .pond = 6, .pond_chests = 2, .camps = 2 } }, &.{});
        const found = Lairs.of(&lv, &spec);
        nooks_seen += found.cells.getPtrConst(.nook).count();
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(0x1A12 +% i);
        place(&lv, &pool, &rng, door, &.{}, &spec);
        for (pool.slice()) |a| {
            placed.getPtr(a.kind).* += 1;
            const lair: Lair, const slack: i32 = switch (a.kind) {
                .mimic => .{ .nook, 0 },
                .bog_leech => .{ .pond, spec.reach },
                .slime => .{ .pond, spec.reach },
                .goblin => .{ .hearth, spec.reach },
                else => unreachable,
            };
            var round = grid.Cells.around(a.at, slack);
            const home = while (round.next()) |q| {
                if (grid.Level.inside(q) and found.cells.getPtrConst(lair).isSet(grid.Level.idx(q))) break true;
            } else false;
            astray += @intFromBool(!home);
        }
    }
    std.debug.print("{d} caravan tees: {d} nooks a map; {d} mimics, {d} leeches, {d} slimes, {d} goblins placed, {d} astray of their lairs\n", .{ RUNS, nooks_seen / RUNS, placed.get(.mimic), placed.get(.bog_leech), placed.get(.slime), placed.get(.goblin), astray });
    try std.testing.expectEqual(@as(usize, 0), astray);
    try std.testing.expect(placed.get(.mimic) * 10 >= RUNS * 9);
    try std.testing.expect(placed.get(.bog_leech) >= RUNS and placed.get(.slime) >= RUNS and placed.get(.goblin) >= 2 * RUNS);
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
