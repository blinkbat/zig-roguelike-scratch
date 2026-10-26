const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("actor.zig");
const fov = @import("../map/fov.zig");
const damage = @import("damage.zig");

const P = mathx.P;

pub const RANGE: i32 = 9;
pub const VERB = "shoots";

pub const BASE = damage.Base{ .lo = 3, .hi = 5 };

pub const Hit = union(enum) { body: u16, barrel: P };

pub const Flight = struct {
    path: [RANGE]P = undefined,
    len: usize = 0,
    struck: ?Hit = null,

    pub fn impact(f: *const Flight) ?P {
        if (f.struck == null) return null;
        return f.path[f.len - 1];
    }
};

pub fn aimable(lv: *const grid.Level, from: P, to: P) bool {
    const d = mathx.dist(from, to);
    return d >= 1 and d <= RANGE and grid.Level.inside(to) and grid.clearLine(lv, from, to);
}

pub fn pick(lv: *const grid.Level, pool: *actor.Pool, from: P) ?P {
    var near = Nearest{ .from = from };
    for (pool.slice()) |a| {
        if (a.alive and a.foe() and lv.isLit(a.at) and aimable(lv, from, a.at)) {
            const flight = preview(lv, from, a.at);
            if (flight.impact()) |at| if (at.eq(a.at)) {
                near.offer(a.at);
            };
        }
    }
    if (near.best != null) return near.best;
    var cells = grid.Cells.around(from, RANGE);
    while (cells.next()) |p| {
        if (lv.hasBarrel(p) and lv.isLit(p) and aimable(lv, from, p)) near.offer(p);
    }
    return near.best;
}

/// The nearest cell offered within `reach`, by steps and then by the straighter line.
pub const Nearest = struct {
    from: P,
    reach: i32 = std.math.maxInt(i32),
    best: ?P = null,
    best_d: i32 = std.math.maxInt(i32),
    best_line: f32 = std.math.floatMax(f32),

    pub fn offer(n: *Nearest, p: P) void {
        const d = mathx.dist(n.from, p);
        const line = mathx.distEuclid(n.from, p);
        if (d > n.reach or d > n.best_d or (d == n.best_d and line >= n.best_line)) return;
        n.best_d = d;
        n.best_line = line;
        n.best = p;
    }
};

pub fn fly(lv: *const grid.Level, from: P, to: P) Flight {
    return trace(lv, from, to, false);
}

pub fn preview(lv: *const grid.Level, from: P, to: P) Flight {
    return trace(lv, from, to, true);
}

fn trace(lv: *const grid.Level, from: P, to: P, comptime visible_only: bool) Flight {
    var f = Flight{};
    var ray = grid.Ray.init(from, to);
    while (ray.next()) |c| {
        if (!grid.Level.inside(c) or f.len == f.path.len or lv.hasBarrier(c) or (!c.eq(to) and lv.at(c).blind())) break;
        f.path[f.len] = c;
        f.len += 1;
        if (lv.at(c).halts()) break;
        if (visible_only and !lv.isLit(c)) continue;
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

test "a foe standing in reeds is aimable and the arrow reaches it" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 10, .y = 10 };
    const at = P{ .x = 14, .y = 10 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    lv.set(at, .reeds);
    const rat = pool.spawn(&lv, actor.Actor.of(.rat, at));
    fov.cast(&lv, hero, actor.row(actor.HERO).sight);
    try std.testing.expect(aimable(&lv, hero, at));
    try std.testing.expectEqual(@as(?Hit, .{ .body = rat }), fly(&lv, hero, at).struck);
}

test "an arrow flies over water to the rat across it" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 10, .y = 10 };
    const at = P{ .x = 15, .y = 10 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    for (0..3) |k| lv.set(.{ .x = 12 + @as(i32, @intCast(k)), .y = 10 }, .water);
    const rat = pool.spawn(&lv, actor.Actor.of(.rat, at));
    fov.cast(&lv, hero, actor.row(actor.HERO).sight);
    try std.testing.expect(aimable(&lv, hero, at));
    try std.testing.expectEqual(@as(?Hit, .{ .body = rat }), fly(&lv, hero, at).struck);
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

test "a closed chest stops an arrow without opening, while an opened chest lets it pass" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const from = P{ .x = 10, .y = 10 };
    const to = P{ .x = 16, .y = 10 };
    const at = P{ .x = 12, .y = 10 };
    const rat = pool.spawn(&lv, actor.Actor.of(.rat, to));
    lv.set(at, .chest);
    const stopped = fly(&lv, from, to);
    try std.testing.expectEqual(@as(?Hit, null), stopped.struck);
    try std.testing.expectEqual(@as(usize, 2), stopped.len);
    try std.testing.expectEqual(grid.Tile.chest, lv.at(at));
    lv.set(at, .chest_open);
    try std.testing.expectEqual(@as(?Hit, .{ .body = rat }), fly(&lv, from, to).struck);
    std.debug.print("closed chest intercepts an arrow at 2 cells; opened chest passes it to the foe at 6\n", .{});
}

test "pick suggests an intercepting barrel instead of a foe behind it" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    lv.putBarrel(.{ .x = 32, .y = 30 });
    lv.putBarrel(.{ .x = 30, .y = 30 - RANGE - 1 });
    fov.cast(&lv, hero, actor.row(actor.HERO).sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 32, .y = 30 }), pick(&lv, &pool, hero));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 36, .y = 30 }));
    try std.testing.expectEqual(@as(?P, .{ .x = 32, .y = 30 }), pick(&lv, &pool, hero));
}

test "projectile suggestions do not expose hidden interceptors" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const from = P{ .x = 20, .y = 20 };
    const hidden = P{ .x = 23, .y = 20 };
    const to = P{ .x = 26, .y = 20 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, from));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, to));
    fov.cast(&lv, from, actor.row(actor.HERO).sight);
    lv.lit[grid.Level.idx(hidden)] = false;
    const clear = pick(&lv, &pool, from);
    const clear_preview = preview(&lv, from, to);
    const rat = pool.spawn(&lv, actor.Actor.of(.rat, hidden));
    try std.testing.expectEqual(clear, pick(&lv, &pool, from));
    const body_preview = preview(&lv, from, to);
    try std.testing.expectEqual(clear_preview.struck, body_preview.struck);
    try std.testing.expectEqualSlices(P, clear_preview.path[0..clear_preview.len], body_preview.path[0..body_preview.len]);
    try std.testing.expectEqual(@as(?Hit, .{ .body = rat }), fly(&lv, from, to).struck);
    _ = pool.damage(&lv, rat, actor.row(.rat).hp);
    lv.putBarrel(hidden);
    try std.testing.expectEqual(clear, pick(&lv, &pool, from));
    const barrel_preview = preview(&lv, from, to);
    try std.testing.expectEqual(clear_preview.struck, barrel_preview.struck);
    try std.testing.expectEqualSlices(P, clear_preview.path[0..clear_preview.len], barrel_preview.path[0..barrel_preview.len]);
    try std.testing.expectEqual(@as(?Hit, .{ .barrel = hidden }), fly(&lv, from, to).struck);
    lv.lit[grid.Level.idx(hidden)] = true;
    try std.testing.expectEqual(@as(?Hit, .{ .barrel = hidden }), preview(&lv, from, to).struck);
    std.debug.print("projectile previews and suggestions: 2 hidden interceptors preserve paths and visible selection; real arrows and visible barrels still collide\n", .{});
}

test "pick takes the nearest visible rat in range and ignores the dark" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 36, .y = 30 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 27, .y = 32 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 30, .y = 30 + RANGE + 1 }));
    const sight = actor.row(actor.HERO).sight;
    fov.cast(&lv, hero, sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 27, .y = 32 }), pick(&lv, &pool, hero));
    var y: i32 = 25;
    while (y < 36) : (y += 1) lv.set(.{ .x = 28, .y = y }, .wall);
    fov.cast(&lv, hero, sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 36, .y = 30 }), pick(&lv, &pool, hero));
}

test "pick takes the rat fewest steps away, not the one nearest as the crow flies" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 35, .y = 30 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 34, .y = 34 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 34, .y = 27 }));
    fov.cast(&lv, hero, actor.row(actor.HERO).sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 34, .y = 27 }), pick(&lv, &pool, hero));
}

test "free projectile aim accepts dark empty and wall marks but cannot aim beyond walls" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    const mark = P{ .x = 26, .y = 20 };
    try std.testing.expect(!lv.isLit(mark));
    try std.testing.expect(aimable(&lv, from, mark));
    try std.testing.expectEqual(@as(usize, 6), fly(&lv, from, mark).len);
    lv.set(.{ .x = 23, .y = 20 }, .wall);
    try std.testing.expect(!aimable(&lv, from, mark));
    try std.testing.expect(aimable(&lv, from, .{ .x = 23, .y = 20 }));
    try std.testing.expectEqual(@as(usize, 2), fly(&lv, from, mark).len);
    try std.testing.expect(!aimable(&lv, from, from));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 30, .y = 20 }));
    try std.testing.expect(!aimable(&lv, .{ .x = 1, .y = 1 }, .{ .x = -1, .y = 1 }));
    std.debug.print("free projectile aim: dark and empty cells, wall endpoints, blocked sight, collision, range and map bounds checked\n", .{});
}

test "a rat takes exactly two arrows" {
    const hp = actor.row(.rat).hp;
    try std.testing.expect(BASE.hi < hp);
    try std.testing.expect(BASE.lo * 2 >= hp);
}

test "a slime outlasts two arrows and hits harder than a rat" {
    const s = actor.row(.slime);
    const slam = s.blow.strike;
    const bite = actor.row(.rat).blow.strike;
    std.debug.print("slime: {d} hp, {d}-{d} arrows to kill\n", .{ s.hp, std.math.divCeil(i32, s.hp, BASE.hi) catch 0, std.math.divCeil(i32, s.hp, BASE.lo) catch 0 });
    try std.testing.expect(BASE.hi * 2 < s.hp);
    try std.testing.expect(slam.hit.lo > bite.hit.lo and slam.hit.hi > bite.hit.hi);
}

test "one arrow bursts a bloat two times in three, and one that lives is left on 1 hp" {
    const hp = actor.row(.bloat).hp;
    try std.testing.expectEqual(2 * (BASE.hi - BASE.lo + 1), 3 * (BASE.hi - hp + 1));
    try std.testing.expectEqual(@as(i32, 1), hp - BASE.lo);
}
