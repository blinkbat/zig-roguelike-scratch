const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const actor = @import("actor.zig");

const P = mathx.P;

pub const RANGE: i32 = 9;
pub const DMG_LO: i32 = 3;
pub const DMG_HI: i32 = 5;

pub const Flight = struct {
    path: [RANGE]P = undefined,
    len: usize = 0,
    struck: u16 = grid.NO_ONE,
};

/// The reticle's legal cells and the shot's legality are this one call.
pub fn aimable(lv: *const grid.Level, from: P, to: P) bool {
    const d = mathx.dist(from, to);
    return d >= 1 and d <= RANGE and lv.walkable(to) and lv.isLit(to) and grid.clearLine(lv, from, to);
}

/// The nearest foe the archer can see, in range, with a clear Bresenham line to it.
pub fn pick(lv: *const grid.Level, pool: *actor.Pool, from: P) ?u16 {
    var best: ?u16 = null;
    var best_d: f32 = std.math.floatMax(f32);
    for (pool.slice(), 0..) |a, i| {
        if (!a.alive or !a.foe()) continue;
        if (!aimable(lv, from, a.at)) continue;
        const d = mathx.distEuclid(from, a.at);
        if (d < best_d) {
            best_d = d;
            best = actor.Pool.idOf(i);
        }
    }
    return best;
}

/// Walks the line to `to` and stops on the first body, or short of the first wall.
pub fn fly(lv: *const grid.Level, from: P, to: P) Flight {
    var f = Flight{};
    var ray = grid.Ray.init(from, to);
    while (ray.next()) |c| {
        if (f.len == f.path.len or lv.at(c).blind()) break;
        f.path[f.len] = c;
        f.len += 1;
        const w = lv.who(c);
        if (w != grid.NO_ONE) {
            f.struck = w;
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
    try std.testing.expectEqual(near, f.struck);
    try std.testing.expectEqual(@as(usize, 3), f.len);
}

test "a wall stops an arrow short of it" {
    var lv = grid.openFloor();
    lv.set(.{ .x = 13, .y = 10 }, .wall);
    const f = fly(&lv, .{ .x = 10, .y = 10 }, .{ .x = 16, .y = 10 });
    try std.testing.expectEqual(grid.NO_ONE, f.struck);
    try std.testing.expectEqual(@as(usize, 2), f.len);
}

test "pick takes the nearest visible rat in range and ignores the dark" {
    const fov = @import("../world/fov.zig");
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 36, .y = 30 }));
    const close = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 27, .y = 32 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 30, .y = 30 + RANGE + 1 }));
    const sight = actor.row(.archer).sight;
    fov.cast(&lv, hero, sight);
    try std.testing.expectEqual(@as(?u16, close), pick(&lv, &pool, hero));
    var y: i32 = 25;
    while (y < 36) : (y += 1) lv.set(.{ .x = 28, .y = y }, .wall);
    fov.cast(&lv, hero, sight);
    try std.testing.expectEqual(@as(?u16, 2), pick(&lv, &pool, hero));
}

test "a rat takes exactly two arrows" {
    const hp = actor.row(.rat).hp;
    try std.testing.expect(DMG_HI < hp);
    try std.testing.expect(DMG_LO * 2 >= hp);
}
