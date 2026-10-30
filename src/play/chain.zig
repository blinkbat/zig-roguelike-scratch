const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const actor = @import("actor.zig");
const spark = @import("spark.zig");
const clock = @import("clock.zig");

pub const COST: i32 = 4;
/// Foes it leaps on to after the first, each the nearest unstruck foe to the last within `JUMP_RANGE`.
pub const JUMPS: usize = 2;
pub const JUMP_RANGE: i32 = 3;
pub const VERB = "shocks";
pub const BOLT = "chain lightning";
pub const TAKES = spark.TAKES;
pub const ELEMENT: damage.Element = .lightning;
pub const DESCRIPTION = std.fmt.comptimePrint("Lightning leaps to {d} more foes, each within {d} tiles of the last. {s} each.", .{ JUMPS, JUMP_RANGE, clock.stunNote(spark.CHANCE) });

pub const BASE = damage.Base{ .lo = 2, .hi = 5 };

pub const CHANCE = spark.CHANCE;
pub const procs = spark.procs;
pub const chance = spark.chance;
pub const afflict = spark.afflict;
pub const AILMENT = spark.AILMENT;

/// The bodies it strikes, the first first: each after it the nearest lit foe to the one before, in a clear line.
pub const Chain = actor.Ids(JUMPS + 1);

pub fn chain(lv: *const grid.Level, pool: *actor.Pool, first: u16) Chain {
    var c = Chain{};
    c.push(first);
    while (c.n <= JUMPS) {
        const last = actor.Pool.slot(c.id[c.n - 1]);
        const from = pool.items[last].at;
        var near = grid.Nearest{ .from = from, .reach = JUMP_RANGE };
        for (pool.slice(), 0..) |a, i| {
            if (!a.seenFoe(lv) or c.has(actor.Pool.idOf(i))) continue;
            if (grid.projectileLine(lv, from, a.at)) near.offer(a.at);
        }
        c.push(lv.who(near.best orelse break));
    }
    return c;
}

test "chain lightning leaps to the nearest lit foe in a clear line, never twice to one, never past its reach" {
    var lv = grid.openFloor();
    lv.lit = @splat(true);
    var pool = actor.Pool{};
    _ = pool.spawn(&lv, actor.Actor.of(.wizard, .{ .x = 10, .y = 10 }));
    const first = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 15, .y = 10 }));
    const far = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 18, .y = 10 }));
    const near = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 16, .y = 11 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 25, .y = 10 }));
    var c = chain(&lv, &pool, first);
    try std.testing.expectEqualSlices(u16, &.{ first, near, far }, c.slice());
    lv.barrier[grid.Level.idx(.{ .x = 17, .y = 10 })] = 3;
    lv.barrier[grid.Level.idx(.{ .x = 17, .y = 11 })] = 3;
    try std.testing.expectEqualSlices(u16, &.{ first, near }, chain(&lv, &pool, first).slice());
    lv.barrier = @splat(0);
    lv.set(.{ .x = 17, .y = 10 }, .wall);
    lv.set(.{ .x = 17, .y = 11 }, .wall);
    c = chain(&lv, &pool, first);
    try std.testing.expectEqualSlices(u16, &.{ first, near }, c.slice());
    std.debug.print("chain lightning: up to {d} bodies, leaps of {d} tiles at most; a wall ends the chain\n", .{ JUMPS + 1, JUMP_RANGE });
}
