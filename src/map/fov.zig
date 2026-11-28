const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");

const P = mathx.P;

const QUADS = [_]mathx.Dir{ .n, .s, .e, .w };

const Quad = struct {
    origin: P,
    card: mathx.Dir,

    fn at(q: Quad, depth: i32, col: i32) P {
        return q.origin.add(q.card.delta().scaled(depth)).add(q.card.across().scaled(col));
    }
};

const Row = struct {
    depth: i32,
    start: f32,
    end: f32,

    const FIRST = Row{ .depth = 1, .start = -1, .end = 1 };
};

fn slope(depth: i32, col: i32) f32 {
    const d: f32 = @floatFromInt(depth);
    const c: f32 = @floatFromInt(col);
    return (2 * c - 1) / (2 * d);
}

fn symmetric(row: Row, col: i32) bool {
    const d: f32 = @floatFromInt(row.depth);
    const c: f32 = @floatFromInt(col);
    return c >= d * row.start and c <= d * row.end;
}

pub fn cast(lv: *grid.Level, origin: P, radius: i32) void {
    lv.lightless();
    castWith(lv, origin, radius, Sight{ .lv = lv });
}

pub fn castInto(lv: *const grid.Level, origin: P, radius: i32, out: *[grid.CELLS]bool) void {
    castWith(lv, origin, radius, Into{ .out = out });
}

const Sight = struct {
    lv: *grid.Level,

    fn mark(s: Sight, p: P) void {
        s.lv.light(p);
    }
};

const Into = struct {
    out: *[grid.CELLS]bool,

    fn mark(s: Into, p: P) void {
        if (!grid.Level.inside(p)) return;
        const i = grid.Level.idx(p);
        s.out[i] = true;
    }
};

fn castWith(lv: *const grid.Level, origin: P, radius: i32, sink: anytype) void {
    sink.mark(origin);
    for (QUADS) |c| {
        scan(lv, sink, .{ .origin = origin, .card = c }, Row.FIRST, radius);
    }
}

fn scan(lv: *const grid.Level, sink: anytype, q: Quad, row_in: Row, radius: i32) void {
    if (row_in.depth > radius) return;
    var row = row_in;
    var prev_wall: ?bool = null;
    const d: f32 = @floatFromInt(row.depth);
    // Round near ties up and far ties down to block sight through wall corners.
    var col = mathx.roundTiesUp(d * row.start);
    const max_col = mathx.roundTiesDown(d * row.end);
    while (col <= max_col) : (col += 1) {
        const p = q.at(row.depth, col);
        const wall = lv.blocksSight(p);
        if (mathx.reaches(q.origin, p, @floatFromInt(radius))) {
            if (wall or symmetric(row, col)) sink.mark(p);
        }
        if (prev_wall) |pw| {
            if (pw and !wall) row.start = slope(row.depth, col);
            if (!pw and wall) {
                scan(lv, sink, q, .{ .depth = row.depth + 1, .start = row.start, .end = slope(row.depth, col) }, radius);
            }
        }
        prev_wall = wall;
    }
    if (prev_wall) |pw| {
        if (!pw) scan(lv, sink, q, .{ .depth = row.depth + 1, .start = row.start, .end = row.end }, radius);
    }
}

pub fn sees(lv: *const grid.Level, watcher: P, hero: P, reach: i32) bool {
    if (!grid.Level.inside(watcher) or !grid.Level.inside(hero) or mathx.dist(watcher, hero) > reach) return false;
    if (watcher.eq(hero)) return true;
    var found = false;
    const Probe = struct {
        target: P,
        found: *bool,

        fn mark(self: @This(), p: P) void {
            if (p.eq(self.target)) self.found.* = true;
        }
    };
    const probe = Probe{ .target = watcher, .found = &found };
    const radius: i32 = @intFromFloat(@ceil(mathx.distEuclid(watcher, hero)));
    const delta = watcher.sub(hero);
    if (@abs(delta.y) >= @abs(delta.x)) scan(lv, probe, .{ .origin = hero, .card = if (delta.y < 0) .n else .s }, Row.FIRST, radius);
    if (!found and @abs(delta.x) >= @abs(delta.y)) scan(lv, probe, .{ .origin = hero, .card = if (delta.x < 0) .w else .e }, Row.FIRST, radius);
    return found;
}

test "foe sight reads current occluders independently of hero sight and memory" {
    var lv = grid.openFloor();
    const hero = P{ .x = 20, .y = 20 };
    const watcher = hero.add(.{ .x = 3, .y = 0 });
    const diagonal = hero.add(.{ .x = 3, .y = 3 });
    cast(&lv, hero, 1);
    const before = lv;
    try std.testing.expect(sees(&lv, watcher, hero, 3));
    try std.testing.expect(sees(&lv, diagonal, hero, 3));
    try std.testing.expect(!sees(&lv, watcher, hero, 2));
    try std.testing.expectEqualDeep(before, lv);
    const between = hero.add(.{ .x = 1, .y = 0 });
    lv.smoke[grid.Level.idx(between)] = std.math.maxInt(u16);
    try std.testing.expect(sees(&lv, watcher, hero, 3));
    lv.set(between, .wall);
    try std.testing.expect(!sees(&lv, watcher, hero, 3));
}

test "targeted sight matches full casts around boundaries and burning cover" {
    var lv = grid.openFloor();
    var rng = mathx.Rng.init(7);
    for (0..grid.CELLS) |i| switch (rng.below(6)) {
        0 => lv.tile[i] = .wall,
        1, 2 => {
            lv.tile[i] = .reeds;
            lv.flames[i] = @intCast(rng.below(2));
        },
        else => {},
    };
    for ([_]P{ .{ .x = 0, .y = 0 }, grid.MIDDLE, grid.SIZE.sub(.{ .x = 1, .y = 1 }) }) |origin| {
        var targets = grid.Box.around(origin, 8).grown(0).cells();
        while (targets.next()) |watcher| {
            var whole: [grid.CELLS]bool = @splat(false);
            const radius: i32 = @intFromFloat(@ceil(mathx.distEuclid(watcher, origin)));
            castInto(&lv, origin, radius, &whole);
            try std.testing.expectEqual(whole[grid.Level.idx(watcher)], sees(&lv, watcher, origin, 8));
        }
    }
}

test "burning foliage and smoke pass sight light and targeting while solid cover stays opaque" {
    const fire = @import("fire.zig");
    const bow = @import("../play/bow.zig");
    const hero = P{ .x = 20, .y = 20 };
    const between = hero.add(.{ .x = 1, .y = 0 });
    const target = hero.add(.{ .x = 3, .y = 0 });
    for ([_]grid.Tile{ .floor, .grass, .reeds, .crop, .wall, .shrub }) |tile| {
        var lv = grid.openFloor();
        lv.set(between, tile);
        cast(&lv, hero, 5);
        try std.testing.expectEqual(!tile.blind(), lv.isLit(target));
        fire.lay(&lv, between, fire.BURNS, 0);
        const visible = !tile.blind() or tile.burns();
        cast(&lv, hero, 5);
        try std.testing.expectEqual(visible, lv.isLit(target));
        try std.testing.expectEqual(visible, sees(&lv, target, hero, 5));
        try std.testing.expectEqual(visible, grid.clearLine(&lv, hero, target));
        try std.testing.expectEqual(visible, bow.aimable(&lv, hero, target, 5));
        if (visible) try std.testing.expect(bow.fly(&lv, hero, target).end().?.eq(target));
        var lit: [grid.CELLS]bool = @splat(false);
        castInto(&lv, hero, 5, &lit);
        try std.testing.expectEqual(visible, lit[grid.Level.idx(target)]);
        lv.smoke[grid.Level.idx(between)] = std.math.maxInt(u16);
        cast(&lv, hero, 5);
        try std.testing.expectEqual(visible, lv.isLit(target));
        try std.testing.expectEqual(visible, sees(&lv, target, hero, 5));
        lv.smoke[grid.Level.idx(between)] = 0;
        var rng = mathx.Rng.init(1);
        _ = fire.douse(&lv, &.{between}, 100, &rng);
        cast(&lv, hero, 5);
        try std.testing.expectEqual(!tile.blind(), lv.isLit(target));
    }
}

test "an open floor lights a round pool, not a square one" {
    var lv = grid.openFloor();
    const o = P{ .x = 40, .y = 30 };
    cast(&lv, o, 8);
    var lit: usize = 0;
    for (lv.lit) |l| {
        if (l) lit += 1;
    }
    const disc = std.math.pi * 8.5 * 8.5;
    try std.testing.expect(@as(f32, @floatFromInt(lit)) > disc * 0.9);
    try std.testing.expect(@as(f32, @floatFromInt(lit)) < disc * 1.1);
}

test "sight is symmetric through a field of pillars" {
    var lv = grid.openFloor();
    var rng = mathx.Rng.init(0xA11CE);
    for (0..220) |_| lv.set(.{ .x = rng.range(24, 56), .y = rng.range(16, 44) }, .wall);
    const o = P{ .x = 40, .y = 30 };
    lv.set(o, .floor);
    const r: i32 = 10;
    cast(&lv, o, r);
    var fwd: [grid.CELLS]bool = undefined;
    @memcpy(&fwd, &lv.lit);
    var checked: usize = 0;
    var broken: usize = 0;
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        if (lv.at(p).blind()) continue;
        if (mathx.distEuclid(o, p) > @as(f32, @floatFromInt(r))) continue;
        checked += 1;
        cast(&lv, p, r);
        if (fwd[i] != lv.isLit(o)) broken += 1;
    }
    try std.testing.expect(checked > 150);
    try std.testing.expectEqual(@as(usize, 0), broken);
}
