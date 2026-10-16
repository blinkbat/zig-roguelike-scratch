const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const damage = @import("damage.zig");
const actor = @import("actor.zig");
const spark = @import("spark.zig");
const bow = @import("bow.zig");

pub const COST: i32 = 20;
pub const LIGHTNING_LO: i32 = 2;
pub const LIGHTNING_HI: i32 = 5;
/// Foes it leaps on to after the first, each the nearest unstruck foe to the last within `JUMP_RANGE`.
pub const JUMPS: usize = 2;
pub const JUMP_RANGE: i32 = 3;
pub const VERB = "shocks";
pub const BOLT = "chain lightning";
pub const TAKES = spark.TAKES;
pub const ELEMENT: damage.Element = .lightning;
pub const DESCRIPTION = std.fmt.comptimePrint("A bolt of {d}-{d} lightning that leaps on to {d} more foes, each within {d} tiles of the last. {d}% chance to stun each. {d} mana.", .{ LIGHTNING_LO, LIGHTNING_HI, JUMPS, JUMP_RANGE, spark.CHANCE, COST });

pub const roll = mathx.Rng.rolls(LIGHTNING_LO, LIGHTNING_HI);

pub const procs = spark.procs;
pub const afflict = spark.afflict;

/// The bodies it strikes, the first first: each after it the nearest lit foe to the one before, in a clear line.
pub const Chain = struct {
    id: [JUMPS + 1]u16 = undefined,
    n: usize = 0,

    pub fn slice(self: *const Chain) []const u16 {
        return self.id[0..self.n];
    }
};

pub fn chain(lv: *const grid.Level, pool: *actor.Pool, first: u16) Chain {
    var c = Chain{};
    c.id[0] = first;
    c.n = 1;
    while (c.n <= JUMPS) {
        const last = actor.Pool.slot(c.id[c.n - 1]);
        const from = pool.items[last].at;
        var near = bow.Nearest{ .from = from, .reach = JUMP_RANGE };
        for (pool.slice(), 0..) |a, i| {
            if (!a.alive or !a.foe() or std.mem.indexOfScalar(u16, c.slice(), actor.Pool.idOf(i)) != null) continue;
            if (lv.isLit(a.at) and grid.clearLine(lv, from, a.at)) near.offer(a.at);
        }
        c.id[c.n] = lv.who(near.best orelse break);
        c.n += 1;
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
    lv.set(.{ .x = 17, .y = 10 }, .wall);
    lv.set(.{ .x = 17, .y = 11 }, .wall);
    c = chain(&lv, &pool, first);
    try std.testing.expectEqualSlices(u16, &.{ first, near }, c.slice());
    std.debug.print("chain lightning: up to {d} bodies, leaps of {d} tiles at most; a wall ends the chain\n", .{ JUMPS + 1, JUMP_RANGE });
}
