const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const actor = @import("actor.zig");

const P = mathx.P;

pub const RANGE: i32 = 9;
pub const DMG_LO: i32 = 3;
pub const DMG_HI: i32 = 5;
pub const VERB = "shoots";

pub const Hit = union(enum) { body: u16, barrel: P };

pub const Flight = struct {
    path: [RANGE]P = undefined,
    len: usize = 0,
    struck: ?Hit = null,
};

/// The reticle's legal cells and the shot's legality are this one call; a line slips past corners sight does not, so every cell on it is lit.
pub fn aimable(lv: *const grid.Level, from: P, to: P) bool {
    const d = mathx.dist(from, to);
    return d >= 1 and d <= RANGE and lv.walkable(to) and grid.litLine(lv, from, to);
}

pub fn pick(lv: *const grid.Level, pool: *actor.Pool, from: P) ?P {
    var near = Nearest{ .from = from };
    for (pool.slice()) |a| {
        if (a.alive and a.foe() and aimable(lv, from, a.at)) near.offer(a.at);
    }
    if (near.best != null) return near.best;
    var cells = grid.Cells.around(from, RANGE);
    while (cells.next()) |p| {
        if (lv.hasBarrel(p) and aimable(lv, from, p)) near.offer(p);
    }
    return near.best;
}

/// Chebyshev first; the straighter line breaks a tie.
const Nearest = struct {
    from: P,
    best: ?P = null,
    best_d: i32 = std.math.maxInt(i32),
    best_line: f32 = std.math.floatMax(f32),

    fn offer(n: *Nearest, p: P) void {
        const d = mathx.dist(n.from, p);
        const line = mathx.distEuclid(n.from, p);
        if (d > n.best_d or (d == n.best_d and line >= n.best_line)) return;
        n.best_d = d;
        n.best_line = line;
        n.best = p;
    }
};

pub fn fly(lv: *const grid.Level, from: P, to: P) Flight {
    var f = Flight{};
    var ray = grid.Ray.init(from, to);
    while (ray.next()) |c| {
        if (f.len == f.path.len or lv.at(c).blind()) break;
        f.path[f.len] = c;
        f.len += 1;
        const w = lv.who(c);
        if (w != grid.NO_ONE) {
            f.struck = .{ .body = w };
            break;
        }
        if (lv.hasBarrel(c)) {
            f.struck = .{ .barrel = c };
            break;
        }
    }
    return f;
}

test "an arrow stops on the first body in the line" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    _ = pool.spawn(&lv, actor.Actor.of(.archer, .{ .x = 10, .y = 10 }));
    const near = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 13, .y = 10 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 16, .y = 10 }));
    const f = fly(&lv, .{ .x = 10, .y = 10 }, .{ .x = 16, .y = 10 });
    try std.testing.expectEqual(@as(?Hit, .{ .body = near }), f.struck);
    try std.testing.expectEqual(@as(usize, 3), f.len);
}

test "a wall stops an arrow short of it" {
    var lv = grid.openFloor();
    lv.set(.{ .x = 13, .y = 10 }, .wall);
    const f = fly(&lv, .{ .x = 10, .y = 10 }, .{ .x = 16, .y = 10 });
    try std.testing.expectEqual(@as(?Hit, null), f.struck);
    try std.testing.expectEqual(@as(usize, 2), f.len);
}

test "a barrel in the line takes the arrow meant for the rat behind it" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 16, .y = 10 }));
    lv.putBarrel(.{ .x = 12, .y = 10 });
    const f = fly(&lv, .{ .x = 10, .y = 10 }, .{ .x = 16, .y = 10 });
    try std.testing.expectEqual(@as(?Hit, .{ .barrel = .{ .x = 12, .y = 10 } }), f.struck);
    try std.testing.expectEqual(@as(usize, 2), f.len);
}

test "pick takes a barrel only when no foe is in reach" {
    const fov = @import("../world/fov.zig");
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    lv.putBarrel(.{ .x = 32, .y = 30 });
    lv.putBarrel(.{ .x = 30, .y = 30 - RANGE - 1 });
    fov.cast(&lv, hero, actor.row(.archer).sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 32, .y = 30 }), pick(&lv, &pool, hero));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 36, .y = 30 }));
    try std.testing.expectEqual(@as(?P, .{ .x = 36, .y = 30 }), pick(&lv, &pool, hero));
}

test "pick takes the nearest visible rat in range and ignores the dark" {
    const fov = @import("../world/fov.zig");
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 36, .y = 30 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 27, .y = 32 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 30, .y = 30 + RANGE + 1 }));
    const sight = actor.row(.archer).sight;
    fov.cast(&lv, hero, sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 27, .y = 32 }), pick(&lv, &pool, hero));
    var y: i32 = 25;
    while (y < 36) : (y += 1) lv.set(.{ .x = 28, .y = y }, .wall);
    fov.cast(&lv, hero, sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 36, .y = 30 }), pick(&lv, &pool, hero));
}

test "pick takes the rat fewest steps away, not the one nearest as the crow flies" {
    const fov = @import("../world/fov.zig");
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 35, .y = 30 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 34, .y = 34 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 34, .y = 27 }));
    fov.cast(&lv, hero, actor.row(.archer).sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 34, .y = 27 }), pick(&lv, &pool, hero));
}

test "no mark is legal whose line crosses a cell out of sight, though the mark is lit and no wall stands on the line" {
    const fov = @import("../world/fov.zig");
    const gen = @import("../world/gen.zig");
    var lv: grid.Level = undefined;
    _ = gen.build(&lv, 41120);
    const from = P{ .x = 37, .y = 28 };
    const mark = P{ .x = 45, .y = 27 };
    const past = P{ .x = 42, .y = 27 };
    fov.cast(&lv, from, actor.row(.archer).sight);
    try std.testing.expect(lv.isLit(mark) and grid.clearLine(&lv, from, mark));
    try std.testing.expect(lv.walkable(past) and !lv.isLit(past));
    try std.testing.expect(!aimable(&lv, from, mark));
    var marks: usize = 0;
    var dark: usize = 0;
    for (0..10) |i| {
        _ = gen.build(&lv, 41120 +% i *% 7919);
        var k: usize = 0;
        while (k < grid.CELLS) : (k += 7) {
            const at = grid.Level.of(k);
            if (!lv.walkable(at)) continue;
            fov.cast(&lv, at, actor.row(.archer).sight);
            var y = at.y - RANGE;
            while (y <= at.y + RANGE) : (y += 1) {
                var x = at.x - RANGE;
                while (x <= at.x + RANGE) : (x += 1) {
                    const p = P{ .x = x, .y = y };
                    if (!aimable(&lv, at, p)) continue;
                    marks += 1;
                    var ray = grid.Ray.init(at, p);
                    while (ray.next()) |c| {
                        if (lv.isLit(c)) continue;
                        dark += 1;
                        break;
                    }
                }
            }
        }
    }
    std.debug.print("{d} legal marks over 10 floors, {d} of them past a cell out of sight\n", .{ marks, dark });
    try std.testing.expect(marks > 10000);
    try std.testing.expectEqual(@as(usize, 0), dark);
}

test "a rat takes exactly two arrows" {
    const hp = actor.row(.rat).hp;
    try std.testing.expect(DMG_HI < hp);
    try std.testing.expect(DMG_LO * 2 >= hp);
}

test "a slime outlasts two arrows and hits harder than a rat" {
    const s = actor.row(.slime);
    const slam = s.blow.strike;
    const bite = actor.row(.rat).blow.strike;
    std.debug.print("slime: {d} hp, {d}-{d} arrows to kill\n", .{ s.hp, std.math.divCeil(i32, s.hp, DMG_HI) catch 0, std.math.divCeil(i32, s.hp, DMG_LO) catch 0 });
    try std.testing.expect(DMG_HI * 2 < s.hp);
    try std.testing.expect(slam.lo > bite.lo and slam.hi > bite.hi);
}

test "one arrow bursts a bloat two times in three, and one that lives is left on 1 hp" {
    const hp = actor.row(.bloat).hp;
    try std.testing.expectEqual(2 * (DMG_HI - DMG_LO + 1), 3 * (DMG_HI - hp + 1));
    try std.testing.expectEqual(@as(i32, 1), hp - DMG_LO);
}
