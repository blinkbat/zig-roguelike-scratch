const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const gen = @import("../world/gen.zig");
const actor = @import("actor.zig");

const P = mathx.P;

pub const PER_FLOOR: usize = 6;
/// The first kind leads; the rest stand at most `REACH` from it.
pub const KINDS = [_][]const actor.Kind{
    &.{ .rat, .slime },
    &.{ .rat, .rat, .slime },
    &.{.rat},
    &.{ .rat, .rat },
};
pub const REACH: i32 = 2;
pub const BIGGEST: usize = blk: {
    var most: usize = 0;
    for (KINDS) |k| most = @max(most, k.len);
    break :blk most;
};

comptime {
    std.debug.assert(1 + PER_FLOOR * BIGGEST <= actor.MAX);
    std.debug.assert(REACH <= RING_HI);
}

/// Every member at least `gap` from `start`.
pub fn place(lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng, start: P, gap: i32) void {
    for (0..PER_FLOOR) |_| {
        const kinds = KINDS[rng.below(KINDS.len)];
        const lead = gen.openSpot(lv, rng, start, gap) orelse return;
        _ = pool.spawn(lv, actor.Actor.of(kinds[0], lead));
        for (kinds[1..]) |k| {
            const at = spotNear(lv, rng, lead, start, gap) orelse break;
            _ = pool.spawn(lv, actor.Actor.of(k, at));
        }
    }
}

const RING_HI: usize = 4;

/// Nearest ring first, and only a cell the lead has a clear line to.
fn spotNear(lv: *const grid.Level, rng: *mathx.Rng, lead: P, start: P, gap: i32) ?P {
    var ring: i32 = 1;
    while (ring <= REACH) : (ring += 1) {
        var spots: [8 * RING_HI]P = undefined;
        var n: usize = 0;
        var y = lead.y - ring;
        while (y <= lead.y + ring) : (y += 1) {
            var x = lead.x - ring;
            while (x <= lead.x + ring) : (x += 1) {
                const p = P{ .x = x, .y = y };
                if (mathx.dist(p, lead) != ring or !lv.walkable(p) or lv.taken(p)) continue;
                if (mathx.dist(p, start) < gap or !grid.clearLine(lv, lead, p)) continue;
                spots[n] = p;
                n += 1;
            }
        }
        if (n > 0) return spots[rng.below(@intCast(n))];
    }
    return null;
}

test "packs come only in their listed makeups, and every slime stands by a rat" {
    var lv: grid.Level = undefined;
    var counts = std.EnumArray(actor.Kind, usize).initFill(0);
    var lone_slimes: usize = 0;
    for (0..200) |i| {
        const seed: u64 = 0x9AC5 +% i *% 7919;
        const f = gen.build(&lv, seed);
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(seed);
        place(&lv, &pool, &rng, f.start, 12);
        try std.testing.expect(pool.n >= PER_FLOOR and pool.n <= PER_FLOOR * BIGGEST);
        for (pool.slice()) |a| {
            counts.getPtr(a.kind).* += 1;
            try std.testing.expect(!lv.hasBarrel(a.at) and lv.walkable(a.at));
            try std.testing.expect(mathx.dist(a.at, f.start) >= 12);
            if (a.kind != .slime) continue;
            const by_rat = for (pool.slice()) |b| {
                if (b.kind == .rat and mathx.dist(a.at, b.at) <= REACH) break true;
            } else false;
            if (!by_rat) lone_slimes += 1;
        }
    }
    std.debug.print("200 floors, {d} packs each: {d} rats, {d} slimes, {d} slimes with no rat beside them\n", .{ PER_FLOOR, counts.get(.rat), counts.get(.slime), lone_slimes });
    try std.testing.expectEqual(@as(usize, 0), counts.get(.archer));
    try std.testing.expectEqual(@as(usize, 0), lone_slimes);
    try std.testing.expect(counts.get(.slime) < counts.get(.rat));
}
