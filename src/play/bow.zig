const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("actor.zig");
const fov = @import("../map/fov.zig");
const damage = @import("damage.zig");

const P = mathx.P;

/// An arrow's reach; a bolt names its own.
pub const RANGE: i32 = 5;
pub const LONGEST: i32 = 8;
pub const VERB = "shoots";

pub const BASE = damage.Base{ .lo = 3, .hi = 5 };

pub const Hit = union(enum) { body: u16, barrel: P, plant: P };

comptime {
    std.debug.assert(RANGE <= LONGEST);
}

pub const Flight = struct {
    path: [LONGEST]P = undefined,
    len: usize = 0,
    most: usize = LONGEST,
    struck: ?Hit = null,

    pub fn impact(f: *const Flight) ?P {
        if (f.struck == null) return null;
        return f.end();
    }

    /// Where it came down, struck or not; none when it never left the bow.
    pub fn end(f: *const Flight) ?P {
        if (f.len == 0) return null;
        return f.path[f.len - 1];
    }

    pub fn grounded(f: *const Flight, lv: *const grid.Level) ?P {
        const at = f.end() orelse return null;
        if (f.struck != null or !walled(lv.at(at))) return at;
        return if (f.len > 1) f.path[f.len - 2] else null;
    }

    pub fn hits(f: *const Flight, id: u16) bool {
        const s = f.struck orelse return false;
        return switch (s) {
            .body => |b| b == id,
            .barrel, .plant => false,
        };
    }

    fn prop(f: *Flight, lv: *const grid.Level, c: P) bool {
        if (lv.hasBarrel(c)) {
            f.struck = .{ .barrel = c };
        } else if (lv.at(c).bursts()) {
            f.struck = .{ .plant = c };
        } else return false;
        return true;
    }

    fn enter(f: *Flight, lv: *const grid.Level, c: P, to: P, comptime visible_only: bool) Cell {
        if (!grid.Level.inside(c) or f.len == f.most or lv.hasBarrier(c) or (!c.eq(to) and lv.at(c).blind())) return .stop;
        f.path[f.len] = c;
        f.len += 1;
        if (lv.at(c).halts() or walled(lv.at(c))) return .last;
        if (visible_only and !lv.isLit(c)) return .unseen;
        return .open;
    }
};

fn walled(t: grid.Tile) bool {
    return t.solid() and t.blind();
}

/// `last`: a closed chest, which takes the missile whole; a mimic in it is struck.
const Cell = enum { stop, unseen, open, last };

pub fn aimable(lv: *const grid.Level, from: P, to: P, reach: i32) bool {
    const d = mathx.dist(from, to);
    return d >= 1 and d <= reach and grid.Level.inside(to) and grid.clearLine(lv, from, to);
}

pub fn pick(lv: *const grid.Level, pool: *actor.Pool, from: P, reach: i32) ?P {
    var near = grid.Nearest{ .from = from };
    for (pool.slice()) |a| {
        if (a.seenFoe(lv) and aimable(lv, from, a.at, reach)) {
            const flight = previewAmong(lv, pool, from, a.at);
            if (flight.impact()) |at| if (at.eq(a.at)) {
                near.offer(a.at);
            };
        }
    }
    if (near.best != null) return near.best;
    var cells = grid.Cells.around(from, reach);
    while (cells.next()) |p| {
        if (lv.hasBarrel(p) and lv.isLit(p) and aimable(lv, from, p, reach)) near.offer(p);
    }
    return near.best;
}

pub fn fly(lv: *const grid.Level, from: P, to: P) Flight {
    return trace(lv, null, from, to, false);
}

pub fn clearShot(lv: *const grid.Level, from: P, to: P, reach: i32, id: u16) ?Flight {
    if (!aimable(lv, from, to, reach)) return null;
    const flight = fly(lv, from, to);
    return if (flight.hits(id)) flight else null;
}

pub fn preview(lv: *const grid.Level, from: P, to: P) Flight {
    return trace(lv, null, from, to, true);
}

/// `preview`, passing over the bodies in `pool` the hero cannot see where lit.
pub fn previewAmong(lv: *const grid.Level, pool: *const actor.Pool, from: P, to: P) Flight {
    return trace(lv, pool, from, to, true);
}

fn trace(lv: *const grid.Level, seen: ?*const actor.Pool, from: P, to: P, comptime visible_only: bool) Flight {
    var f = Flight{};
    var ray = grid.Ray.init(from, to);
    while (ray.next()) |c| {
        const cell = f.enter(lv, c, to, visible_only);
        switch (cell) {
            .stop => break,
            .unseen => continue,
            .open, .last => {},
        }
        const w = lv.who(c);
        if (w != grid.NO_ONE and !veiled(seen, w)) {
            f.struck = .{ .body = w };
            break;
        }
        if (cell == .last or f.prop(lv, c)) break;
    }
    return f;
}

fn veiled(seen: ?*const actor.Pool, w: u16) bool {
    const pool = seen orelse return false;
    const i = actor.Pool.slot(w);
    return pool.items[i].veiled();
}

/// The bodies an arrow passes through, nearest first, each with its index along the flight.
pub const Pierced = struct {
    flight: Flight = .{ .most = RANGE },
    body: [RANGE]u16 = undefined,
    step: [RANGE]usize = undefined,
    n: usize = 0,
};

/// On through every body past `to`, out to full range; a barrel, wall or barrier still stops it.
pub fn pierce(lv: *const grid.Level, from: P, to: P) Pierced {
    return through(lv, null, from, to, false);
}

pub fn piercePreviewAmong(lv: *const grid.Level, pool: *const actor.Pool, from: P, to: P) Flight {
    return through(lv, pool, from, to, true).flight;
}

fn through(lv: *const grid.Level, seen: ?*const actor.Pool, from: P, to: P, comptime visible_only: bool) Pierced {
    var out = Pierced{};
    const d = mathx.dist(from, to);
    if (d == 0) return out;
    const f = &out.flight;
    var ray = grid.Ray.init(from, from.add(to.sub(from).scaled(@divFloor(RANGE + d - 1, d))));
    while (ray.next()) |c| {
        const cell = f.enter(lv, c, to, visible_only);
        switch (cell) {
            .stop => break,
            .unseen => continue,
            .open, .last => {},
        }
        const w = lv.who(c);
        if (w != grid.NO_ONE and !veiled(seen, w)) {
            out.body[out.n] = w;
            out.step[out.n] = f.len - 1;
            out.n += 1;
            if (cell == .last) break;
        } else if (cell == .last or (w == grid.NO_ONE and f.prop(lv, c))) break;
    }
    if (f.struck == null and out.n > 0) f.struck = .{ .body = out.body[out.n - 1] };
    return out;
}

test "a piercing preview passes over a submerged leech in lit water without striking it" {
    var lv = grid.openFloor();
    lv.lit = @splat(true);
    var pool = actor.Pool{};
    const from = P{ .x = 10, .y = 10 };
    const mark = P{ .x = 12, .y = 10 };
    lv.set(.{ .x = 14, .y = 10 }, .water);
    const leech = pool.spawn(&lv, actor.Actor.of(.bog_leech, .{ .x = 14, .y = 10 }));
    try std.testing.expect(pool.get(leech).?.veiled());
    const shown = piercePreviewAmong(&lv, &pool, from, mark);
    try std.testing.expectEqual(@as(?Hit, null), shown.struck);
    try std.testing.expect(pierce(&lv, from, mark).flight.hits(leech));
}

test "a piercing arrow passes every body in its line to full range and stops at a barrel" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const from = P{ .x = 10, .y = 10 };
    const near = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 12, .y = 11 }));
    const far = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 14, .y = 12 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 16, .y = 13 }));
    const p = pierce(&lv, from, .{ .x = 12, .y = 11 });
    try std.testing.expectEqual(@as(usize, RANGE), p.flight.len);
    try std.testing.expectEqualSlices(u16, &.{ near, far }, p.body[0..p.n]);
    try std.testing.expectEqual(@as(usize, 1), p.step[0]);
    try std.testing.expectEqual(@as(?Hit, .{ .body = far }), p.flight.struck);
    try std.testing.expectEqualSlices(P, fly(&lv, from, .{ .x = 12, .y = 11 }).path[0..2], p.flight.path[0..2]);
    lv.putBarrel(.{ .x = 13, .y = 11 });
    const stopped = pierce(&lv, from, .{ .x = 12, .y = 11 });
    try std.testing.expectEqualSlices(u16, &.{near}, stopped.body[0..stopped.n]);
    try std.testing.expectEqual(@as(?Hit, .{ .barrel = .{ .x = 13, .y = 11 } }), stopped.flight.struck);
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

test "a piercing arrow aimed at a wall ends in it and spares the body behind" {
    var lv = grid.openFloor();
    const from = P{ .x = 10, .y = 10 };
    const wall = P{ .x = 12, .y = 10 };
    lv.set(wall, .wall);
    var pool = actor.Pool{};
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 14, .y = 10 }));
    try std.testing.expect(aimable(&lv, from, wall, RANGE));
    const p = pierce(&lv, from, wall);
    try std.testing.expectEqual(@as(usize, 0), p.n);
    try std.testing.expectEqual(@as(usize, 2), p.flight.len);
    try std.testing.expect(p.flight.end().?.eq(wall));
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
    try std.testing.expect(aimable(&lv, hero, at, RANGE));
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
    try std.testing.expect(aimable(&lv, hero, at, RANGE));
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

test "a glowbulb in the line takes the arrow, piercing or not" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const from = P{ .x = 10, .y = 10 };
    const to = P{ .x = 16, .y = 10 };
    const plant = P{ .x = 13, .y = 10 };
    _ = pool.spawn(&lv, actor.Actor.of(.rat, to));
    lv.set(plant, .glow_plant);
    try std.testing.expectEqual(@as(?Hit, .{ .plant = plant }), fly(&lv, from, to).struck);
    try std.testing.expectEqual(@as(?Hit, .{ .plant = plant }), pierce(&lv, from, to).flight.struck);
    try std.testing.expectEqual(@as(usize, 3), fly(&lv, from, to).len);
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
}

test "a mimic in its chest takes the arrow its chest stops, though the preview shows only the chest" {
    var lv = grid.openFloor();
    lv.lit = @splat(true);
    var pool = actor.Pool{};
    const from = P{ .x = 10, .y = 10 };
    const at = P{ .x = 13, .y = 10 };
    const to = P{ .x = 15, .y = 10 };
    _ = pool.spawn(&lv, actor.Actor.of(.rat, to));
    const mimic = pool.spawn(&lv, actor.Actor.of(.mimic, at));
    try std.testing.expect(pool.get(mimic).?.disguised and lv.at(at) == .chest);
    const shown = previewAmong(&lv, &pool, from, to);
    try std.testing.expectEqual(@as(?Hit, null), shown.struck);
    try std.testing.expectEqual(@as(usize, 3), shown.len);
    const real = fly(&lv, from, to);
    try std.testing.expectEqual(@as(?Hit, .{ .body = mimic }), real.struck);
    try std.testing.expectEqualSlices(P, shown.path[0..shown.len], real.path[0..real.len]);
    try std.testing.expect(pierce(&lv, from, to).flight.hits(mimic));
}

test "pick suggests an intercepting barrel instead of a foe behind it" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    lv.putBarrel(.{ .x = 32, .y = 30 });
    lv.putBarrel(.{ .x = 30, .y = 30 - RANGE - 1 });
    fov.cast(&lv, hero, actor.row(actor.HERO).sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 32, .y = 30 }), pick(&lv, &pool, hero, RANGE));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 34, .y = 30 }));
    try std.testing.expectEqual(@as(?P, .{ .x = 32, .y = 30 }), pick(&lv, &pool, hero, RANGE));
}

test "projectile suggestions do not expose hidden interceptors" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const from = P{ .x = 20, .y = 20 };
    const hidden = P{ .x = 23, .y = 20 };
    const to = P{ .x = 25, .y = 20 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, from));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, to));
    fov.cast(&lv, from, actor.row(actor.HERO).sight);
    lv.lit[grid.Level.idx(hidden)] = false;
    const clear = pick(&lv, &pool, from, RANGE);
    try std.testing.expectEqual(@as(?P, to), clear);
    const clear_preview = preview(&lv, from, to);
    const rat = pool.spawn(&lv, actor.Actor.of(.rat, hidden));
    try std.testing.expectEqual(clear, pick(&lv, &pool, from, RANGE));
    const body_preview = preview(&lv, from, to);
    try std.testing.expectEqual(clear_preview.struck, body_preview.struck);
    try std.testing.expectEqualSlices(P, clear_preview.path[0..clear_preview.len], body_preview.path[0..body_preview.len]);
    try std.testing.expectEqual(@as(?Hit, .{ .body = rat }), fly(&lv, from, to).struck);
    _ = pool.damage(&lv, rat, actor.row(.rat).hp);
    lv.putBarrel(hidden);
    try std.testing.expectEqual(clear, pick(&lv, &pool, from, RANGE));
    const barrel_preview = preview(&lv, from, to);
    try std.testing.expectEqual(clear_preview.struck, barrel_preview.struck);
    try std.testing.expectEqualSlices(P, clear_preview.path[0..clear_preview.len], barrel_preview.path[0..barrel_preview.len]);
    try std.testing.expectEqual(@as(?Hit, .{ .barrel = hidden }), fly(&lv, from, to).struck);
    lv.lit[grid.Level.idx(hidden)] = true;
    try std.testing.expectEqual(@as(?Hit, .{ .barrel = hidden }), preview(&lv, from, to).struck);
}

test "pick takes the nearest visible rat in range and ignores the dark" {
    var lv = grid.openFloor();
    var pool = actor.Pool{};
    const hero = P{ .x = 30, .y = 30 };
    _ = pool.spawn(&lv, actor.Actor.of(.archer, hero));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 34, .y = 30 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 27, .y = 32 }));
    _ = pool.spawn(&lv, actor.Actor.of(.rat, .{ .x = 30, .y = 30 + RANGE + 1 }));
    const sight = actor.row(actor.HERO).sight;
    fov.cast(&lv, hero, sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 27, .y = 32 }), pick(&lv, &pool, hero, RANGE));
    var y: i32 = 25;
    while (y < 36) : (y += 1) lv.set(.{ .x = 28, .y = y }, .wall);
    fov.cast(&lv, hero, sight);
    try std.testing.expectEqual(@as(?P, .{ .x = 34, .y = 30 }), pick(&lv, &pool, hero, RANGE));
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
    try std.testing.expectEqual(@as(?P, .{ .x = 34, .y = 27 }), pick(&lv, &pool, hero, RANGE));
}

test "free projectile aim accepts dark empty and wall marks but cannot aim beyond walls" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    const mark = P{ .x = 20 + RANGE, .y = 20 };
    try std.testing.expect(!lv.isLit(mark));
    try std.testing.expect(aimable(&lv, from, mark, RANGE));
    try std.testing.expect(!aimable(&lv, from, mark.add(.{ .x = 1, .y = 0 }), RANGE));
    try std.testing.expect(aimable(&lv, from, mark.add(.{ .x = 1, .y = 0 }), RANGE + 1));
    try std.testing.expectEqual(@as(usize, RANGE), fly(&lv, from, mark).len);
    lv.set(.{ .x = 23, .y = 20 }, .wall);
    try std.testing.expect(!aimable(&lv, from, mark, RANGE));
    try std.testing.expect(aimable(&lv, from, .{ .x = 23, .y = 20 }, RANGE));
    try std.testing.expectEqual(@as(usize, 2), fly(&lv, from, mark).len);
    try std.testing.expect(!aimable(&lv, from, from, RANGE));
    try std.testing.expect(!aimable(&lv, .{ .x = 1, .y = 1 }, .{ .x = -1, .y = 1 }, RANGE));
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
    try std.testing.expect(BASE.hi * 2 < s.hp);
    try std.testing.expect(slam.hit.lo > bite.hit.lo and slam.hit.hi > bite.hit.hi);
}

test "one arrow bursts a caustic bloat two times in three, and one that lives is left on 1 hp" {
    const hp = actor.row(.bloat).hp;
    try std.testing.expectEqual(2 * (BASE.hi - BASE.lo + 1), 3 * (BASE.hi - hp + 1));
    try std.testing.expectEqual(@as(i32, 1), hp - BASE.lo);
}
