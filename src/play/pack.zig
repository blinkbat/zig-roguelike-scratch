const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const gen = @import("../world/gen.zig");
const actor = @import("actor.zig");

const P = mathx.P;

pub const PER_FLOOR: usize = 10;
/// Every foe kind has at least this many on a floor.
pub const FEW: usize = 3;
/// The first kind leads; the rest stand at most `REACH` from it.
pub const KINDS = [_][]const actor.Kind{
    &.{ .rat, .slime },
    &.{ .rat, .rat, .slime },
    &.{.rat},
    &.{ .rat, .rat },
    &.{.bloat},
};
pub const REACH: i32 = 2;
/// Cells from the archer's start to every member of every pack: past the archer's sight, so none starts in view.
pub const GAP: i32 = 12;
pub const BIGGEST: usize = blk: {
    var most: usize = 0;
    for (KINDS) |k| most = @max(most, k.len);
    break :blk most;
};

/// The foes in the fewest makeups first, so the packs that fill their quota fill the others' on the way.
const QUOTA_ORDER = blk: {
    var ks = actor.FOES;
    for (1..ks.len) |i| {
        var j = i;
        while (j > 0 and makeupsWith(ks[j]) < makeupsWith(ks[j - 1])) : (j -= 1) std.mem.swap(actor.Kind, &ks[j], &ks[j - 1]);
    }
    break :blk ks;
};

/// The archer and every pack, each slime split down to quarters.
const MOST_BODIES = blk: {
    var most: usize = 0;
    for (KINDS) |m| {
        var n: usize = 0;
        for (m) |k| n += actor.most(k);
        most = @max(most, n);
    }
    break :blk 1 + PER_FLOOR * most;
};

comptime {
    std.debug.assert(MOST_BODIES <= actor.MAX);
    std.debug.assert(GAP > actor.row(.archer).sight);
    std.debug.assert(FEW * actor.FOES.len <= PER_FLOOR);
    for (actor.FOES) |k| std.debug.assert(makeupsWith(k) > 0);
}

fn holds(makeup: []const actor.Kind, k: actor.Kind) bool {
    return std.mem.indexOfScalar(actor.Kind, makeup, k) != null;
}

fn makeupsWith(k: actor.Kind) usize {
    var n: usize = 0;
    for (KINDS) |m| {
        if (holds(m, k)) n += 1;
    }
    return n;
}

pub fn place(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P) void {
    var packs: usize = 0;
    for (QUOTA_ORDER) |k| {
        while (packs < PER_FLOOR and pool.tally(k).total < FEW) : (packs += 1) {
            if (!placeOne(lv, pool, rng, start, holding(rng, k))) return;
        }
    }
    while (packs < PER_FLOOR) : (packs += 1) {
        if (!placeOne(lv, pool, rng, start, KINDS[rng.below(KINDS.len)])) return;
    }
}

fn placeOne(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, kinds: []const actor.Kind) bool {
    const lead = gen.openSpot(lv, rng, start, GAP) orelse return false;
    _ = pool.spawn(lv, actor.Actor.of(kinds[0], lead));
    for (kinds[1..]) |k| {
        const at = spotNear(lv, rng, lead, start) orelse break;
        _ = pool.spawn(lv, actor.Actor.of(k, at));
    }
    return true;
}

fn holding(rng: *mathx.Rng, k: actor.Kind) []const actor.Kind {
    var ids: [KINDS.len]usize = undefined;
    var n: usize = 0;
    for (KINDS, 0..) |m, i| {
        if (!holds(m, k)) continue;
        ids[n] = i;
        n += 1;
    }
    return KINDS[ids[rng.below(@intCast(n))]];
}

fn spotNear(lv: *const grid.Level, rng: *mathx.Rng, lead: P, start: P) ?P {
    var ring: i32 = 1;
    while (ring <= REACH) : (ring += 1) {
        var spots: [8 * REACH]P = undefined;
        var n: usize = 0;
        var y = lead.y - ring;
        while (y <= lead.y + ring) : (y += 1) {
            var x = lead.x - ring;
            while (x <= lead.x + ring) : (x += 1) {
                const p = P{ .x = x, .y = y };
                if (mathx.dist(p, lead) != ring or !lv.walkable(p) or lv.taken(p)) continue;
                if (mathx.dist(p, start) < GAP or !grid.clearLine(lv, lead, p)) continue;
                spots[n] = p;
                n += 1;
            }
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
        place(&lv, &pool, &rng, f.start);
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
