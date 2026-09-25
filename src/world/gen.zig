const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");

const P = mathx.P;

const MARGIN: i32 = 2;
/// Wall cells between two rooms, so no outline cell belongs to both.
const ROOM_GAP: i32 = 2;
pub const MAX_ROOMS: usize = 24;
const ROOM_TRIES: usize = 300;
const ROOM_W_LO: i32 = 5;
const ROOM_W_HI: i32 = 13;
const ROOM_H_LO: i32 = 4;
const ROOM_H_HI: i32 = 9;
const ROOMS_PER_LOOP: usize = 4;
const CONNECT_PASSES: usize = 64;
const SPOT_TRIES: usize = 2000;
const TORCH_CHANCE: f32 = 0.7;

comptime {
    std.debug.assert(grid.MAX_TORCHES >= MAX_ROOMS);
}

/// A room's outer corner has its floor on the diagonal away from it: `corner_tl` has its floor to the south-east.
const CORNERS = [_]struct { floor: mathx.Dir, s: grid.WallShape }{
    .{ .floor = .se, .s = .corner_tl },
    .{ .floor = .sw, .s = .corner_tr },
    .{ .floor = .ne, .s = .corner_bl },
    .{ .floor = .nw, .s = .corner_br },
};

pub const Room = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn centre(r: Room) P {
        return .{ .x = r.x + @divTrunc(r.w, 2), .y = r.y + @divTrunc(r.h, 2) };
    }

    fn overlaps(a: Room, b: Room, pad: i32) bool {
        return a.x - pad < b.x + b.w and a.x + a.w + pad > b.x and
            a.y - pad < b.y + b.h and a.y + a.h + pad > b.y;
    }

    /// The outline cell at the corner whose floor lies toward `floor`.
    fn corner(r: Room, floor: mathx.Dir) P {
        const d = floor.delta();
        return .{ .x = if (d.x > 0) r.x - 1 else r.x + r.w, .y = if (d.y > 0) r.y - 1 else r.y + r.h };
    }
};

pub const Floor = struct {
    rooms: [MAX_ROOMS]Room = undefined,
    room_n: usize = 0,
    start: P = .{ .x = 0, .y = 0 },
};

/// Rooms and L-corridors, then tunnelled until one flood fill reaches every open cell. Reproducible from the seed.
pub fn build(lv: *grid.Level, seed: u64) Floor {
    lv.* = grid.Level.blank();
    var rng = mathx.Rng.init(seed);
    var f = Floor{};
    var tries: usize = 0;
    while (tries < ROOM_TRIES and f.room_n < MAX_ROOMS) : (tries += 1) {
        const w = rng.range(ROOM_W_LO, ROOM_W_HI);
        const h = rng.range(ROOM_H_LO, ROOM_H_HI);
        const r = Room{
            .x = rng.range(MARGIN, grid.W - MARGIN - w),
            .y = rng.range(MARGIN, grid.H - MARGIN - h),
            .w = w,
            .h = h,
        };
        if (!addRoom(&f, r)) continue;
        carveRoom(lv, r);
    }
    var i: usize = 1;
    while (i < f.room_n) : (i += 1) tunnel(lv, f.rooms[i - 1].centre(), f.rooms[i].centre(), &rng);
    // A pure tree puts every fight in a corridor with no way round.
    for (0..f.room_n / ROOMS_PER_LOOP) |_| {
        const a = rng.below(@intCast(f.room_n));
        const b = rng.below(@intCast(f.room_n));
        if (a != b) tunnel(lv, f.rooms[a].centre(), f.rooms[b].centre(), &rng);
    }
    connect(lv, &rng);
    shapeWalls(lv);
    for (f.rooms[0..f.room_n]) |r| outlineRoom(lv, r);
    for (f.rooms[0..f.room_n]) |r| {
        if (rng.chance(TORCH_CHANCE)) hangTorch(lv, r, &rng);
    }
    f.start = f.rooms[0].centre();
    return f;
}

/// On the brick face of a wall along the room's top edge.
fn hangTorch(lv: *grid.Level, r: Room, rng: *mathx.Rng) void {
    var spots: [ROOM_W_HI]i32 = undefined;
    var n: usize = 0;
    var x = r.x;
    while (x < r.x + r.w) : (x += 1) {
        if (lv.wallShape(.{ .x = x, .y = r.y - 1 }) != .top) continue;
        spots[n] = x;
        n += 1;
    }
    if (n == 0) return;
    lv.addTorch(.{ .x = spots[rng.below(@intCast(n))], .y = r.y - 1 });
}

fn addRoom(f: *Floor, r: Room) bool {
    for (f.rooms[0..f.room_n]) |have| {
        if (r.overlaps(have, ROOM_GAP)) return false;
    }
    f.rooms[f.room_n] = r;
    f.room_n += 1;
    return true;
}

fn carveRoom(lv: *grid.Level, r: Room) void {
    var y = r.y;
    while (y < r.y + r.h) : (y += 1) {
        var x = r.x;
        while (x < r.x + r.w) : (x += 1) lv.set(.{ .x = x, .y = y }, .floor);
    }
}

fn tunnel(lv: *grid.Level, a: P, b: P, rng: *mathx.Rng) void {
    if (rng.chance(0.5)) {
        runX(lv, a.x, b.x, a.y);
        runY(lv, a.y, b.y, b.x);
    } else {
        runY(lv, a.y, b.y, a.x);
        runX(lv, a.x, b.x, b.y);
    }
}

fn runX(lv: *grid.Level, x0: i32, x1: i32, y: i32) void {
    var x = @min(x0, x1);
    while (x <= @max(x0, x1)) : (x += 1) lv.set(.{ .x = x, .y = y }, .floor);
}

fn runY(lv: *grid.Level, y0: i32, y1: i32, x: i32) void {
    var y = @min(y0, y1);
    while (y <= @max(y0, y1)) : (y += 1) lv.set(.{ .x = x, .y = y }, .floor);
}

fn firstOpen(lv: *const grid.Level) ?P {
    for (0..grid.CELLS) |i| {
        if (!lv.tile[i].solid()) return grid.Level.of(i);
    }
    return null;
}

/// Tunnels from the first unreached cell to the nearest reached one until nothing is orphaned.
fn connect(lv: *grid.Level, rng: *mathx.Rng) void {
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    for (0..CONNECT_PASSES) |_| {
        const start = firstOpen(lv) orelse return;
        _ = grid.distances(lv, start, &dist, &queue);
        var orphan: ?P = null;
        for (0..grid.CELLS) |i| {
            if (!lv.tile[i].solid() and dist[i] < 0) {
                orphan = grid.Level.of(i);
                break;
            }
        }
        const o = orphan orelse return;
        var best: ?P = null;
        var best_d: i32 = std.math.maxInt(i32);
        for (0..grid.CELLS) |i| {
            if (dist[i] < 0) continue;
            const d = mathx.dist(grid.Level.of(i), o);
            if (d < best_d) {
                best_d = d;
                best = grid.Level.of(i);
            }
        }
        tunnel(lv, o, best orelse return, rng);
    }
}

/// A room knows its own corners, so they are corners even where a corridor runs just outside them. Stamped over
/// `shapeWalls`, except where a tunnel carved the corner open, opened a doorway beside it, or runs below it.
fn outlineRoom(lv: *grid.Level, r: Room) void {
    for (CORNERS) |c| {
        const p = r.corner(c.floor);
        if (lv.at(p) != .wall or !grid.Level.inside(p) or keepsFloorShape(lv, p, c.floor)) continue;
        lv.shape[grid.Level.idx(p)] = c.s;
    }
}

/// A room corner whose floor lies toward `floor`, with a doorway in the outline beside it or floor below it.
fn keepsFloorShape(lv: *const grid.Level, p: P, floor: mathx.Dir) bool {
    const d = floor.delta();
    return lv.walkable(p.add(.{ .x = d.x, .y = 0 })) or lv.walkable(p.add(.{ .x = 0, .y = d.y })) or
        lv.walkable(p.add(mathx.Dir.s.delta()));
}

/// Every wall's `grid.WallShape` from the terrain round it: what corridors and anything no room claims are drawn
/// as. Runs once at the end of generation and nothing recomputes it.
pub fn shapeWalls(lv: *grid.Level) void {
    for (0..grid.CELLS) |i| {
        lv.shape[i] = if (lv.tile[i] == .wall) wallShape(lv, grid.Level.of(i)) else null;
    }
}

fn wallShape(lv: *const grid.Level, p: P) grid.WallShape {
    const n = lv.walkable(p.add(mathx.Dir.n.delta()));
    const s = lv.walkable(p.add(mathx.Dir.s.delta()));
    const e = lv.walkable(p.add(mathx.Dir.e.delta()));
    const w = lv.walkable(p.add(mathx.Dir.w.delta()));
    if (s and (e or w)) return if (e and w) .post else if (e) .block_br else .block_bl;
    if (n and e != w) return if (e) .block_tr else .block_tl;
    if (s) return .top;
    if (e) return .left;
    if (w) return .right;
    if (n) return .bottom;
    var found: ?grid.WallShape = null;
    for (CORNERS) |c| {
        if (!lv.walkable(p.add(c.floor.delta()))) continue;
        if (found != null) return .bottom;
        found = c.s;
    }
    return found orelse .solid;
}

/// A floor cell nobody stands on, at least `min_gap` from `away_from`.
pub fn openSpot(lv: *const grid.Level, rng: *mathx.Rng, away_from: P, min_gap: i32) ?P {
    for (0..SPOT_TRIES) |_| {
        const p = P{ .x = rng.range(1, grid.W - 2), .y = rng.range(1, grid.H - 2) };
        if (!lv.walkable(p) or lv.who(p) != grid.NO_ONE) continue;
        if (mathx.dist(p, away_from) < min_gap) continue;
        return p;
    }
    return null;
}

test "every floor connects" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var worst: usize = grid.CELLS;
    for (0..200) |i| {
        const seed: u64 = 0xBEEF +% i *% 7919;
        const f = build(&lv, seed);
        var open: usize = 0;
        for (lv.tile) |t| {
            if (!t.solid()) open += 1;
        }
        const reached = grid.distances(&lv, f.start, &dist, &queue);
        if (reached != open) {
            std.debug.print("seed {d}: {d} open cells, flood reached {d}\n", .{ seed, open, reached });
            return error.FloorNotConnected;
        }
        worst = @min(worst, open);
    }
    std.debug.print("200 floors connected; smallest has {d} open cells\n", .{worst});
    try std.testing.expect(worst > 400);
}

test "the rim stays solid and the start is floor" {
    var lv: grid.Level = undefined;
    for (0..40) |i| {
        const f = build(&lv, 0xC0FFEE +% i *% 31);
        try std.testing.expect(lv.walkable(f.start));
        var x: i32 = 0;
        while (x < grid.W) : (x += 1) {
            try std.testing.expect(!lv.walkable(.{ .x = x, .y = 0 }));
            try std.testing.expect(!lv.walkable(.{ .x = x, .y = grid.H - 1 }));
        }
        var y: i32 = 0;
        while (y < grid.H) : (y += 1) {
            try std.testing.expect(!lv.walkable(.{ .x = 0, .y = y }));
            try std.testing.expect(!lv.walkable(.{ .x = grid.W - 1, .y = y }));
        }
    }
}

fn room(lv: *grid.Level, x0: i32, y0: i32, x1: i32, y1: i32) void {
    carveRoom(lv, .{ .x = x0, .y = y0, .w = x1 - x0 + 1, .h = y1 - y0 + 1 });
}

test "a room's four sides, its corners and the rock behind it" {
    var lv = grid.Level.blank();
    room(&lv, 5, 5, 10, 8);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(.{ .x = 7, .y = 4 }).?);
    try std.testing.expectEqual(grid.WallShape.bottom, lv.wallShape(.{ .x = 7, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.left, lv.wallShape(.{ .x = 4, .y = 6 }).?);
    try std.testing.expectEqual(grid.WallShape.right, lv.wallShape(.{ .x = 11, .y = 6 }).?);
    try std.testing.expectEqual(grid.WallShape.corner_tl, lv.wallShape(.{ .x = 4, .y = 4 }).?);
    try std.testing.expectEqual(grid.WallShape.corner_tr, lv.wallShape(.{ .x = 11, .y = 4 }).?);
    try std.testing.expectEqual(grid.WallShape.corner_bl, lv.wallShape(.{ .x = 4, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.corner_br, lv.wallShape(.{ .x = 11, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.solid, lv.wallShape(.{ .x = 2, .y = 2 }).?);
    try std.testing.expectEqual(@as(?grid.WallShape, null), lv.wallShape(.{ .x = 7, .y = 6 }));
}

test "a wall with floor on two diagonals and none beside it is a bottom wall, not a corner" {
    var lv = grid.Level.blank();
    lv.set(.{ .x = 6, .y = 6 }, .floor);
    lv.set(.{ .x = 4, .y = 4 }, .floor);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape.bottom, lv.wallShape(.{ .x = 5, .y = 5 }).?);
}

test "a wall with no floor below it is never drawn as a post" {
    var lv = grid.Level.blank();
    room(&lv, 4, 2, 8, 2);
    room(&lv, 5, 3, 5, 10);
    room(&lv, 7, 3, 7, 10);
    room(&lv, 4, 11, 8, 11);
    room(&lv, 2, 14, 10, 14);
    room(&lv, 2, 16, 10, 16);
    room(&lv, 11, 14, 11, 16);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape.left, lv.wallShape(.{ .x = 6, .y = 3 }).?);
    try std.testing.expectEqual(grid.WallShape.left, lv.wallShape(.{ .x = 6, .y = 6 }).?);
    try std.testing.expectEqual(grid.WallShape.post, lv.wallShape(.{ .x = 6, .y = 10 }).?);
    try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(.{ .x = 6, .y = 15 }).?);
    try std.testing.expectEqual(grid.WallShape.block_br, lv.wallShape(.{ .x = 10, .y = 15 }).?);
}

test "a corridor's walls run with it, and turn a block corner where another meets it" {
    var lv = grid.Level.blank();
    room(&lv, 5, 10, 20, 10);
    room(&lv, 30, 5, 30, 20);
    room(&lv, 40, 10, 44, 10);
    room(&lv, 40, 11, 40, 14);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(.{ .x = 12, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.bottom, lv.wallShape(.{ .x = 12, .y = 11 }).?);
    try std.testing.expectEqual(grid.WallShape.left, lv.wallShape(.{ .x = 29, .y = 12 }).?);
    try std.testing.expectEqual(grid.WallShape.block_tl, lv.wallShape(.{ .x = 41, .y = 11 }).?);
}

test "a room ringed by corridors keeps its top corners, and a wall with a corridor below it faces that corridor" {
    var lv = grid.Level.blank();
    const r = Room{ .x = 8, .y = 3, .w = 9, .h = 6 };
    carveRoom(&lv, r);
    room(&lv, 1, 1, 24, 1);
    room(&lv, 1, 10, 24, 10);
    room(&lv, 5, 1, 5, 10);
    room(&lv, 19, 1, 19, 10);
    room(&lv, 5, 6, 19, 6);
    shapeWalls(&lv);
    try std.testing.expect(lv.wallShape(.{ .x = 7, .y = 2 }).? != .corner_tl);
    outlineRoom(&lv, r);
    try std.testing.expectEqual(grid.WallShape.corner_tl, lv.wallShape(.{ .x = 7, .y = 2 }).?);
    try std.testing.expectEqual(grid.WallShape.corner_tr, lv.wallShape(.{ .x = 17, .y = 2 }).?);
    try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(.{ .x = 7, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(.{ .x = 17, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(.{ .x = 12, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.left, lv.wallShape(.{ .x = 7, .y = 4 }).?);
    try std.testing.expectEqual(grid.WallShape.right, lv.wallShape(.{ .x = 17, .y = 4 }).?);
    try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(.{ .x = 12, .y = 2 }).?);
    try std.testing.expectEqual(@as(?grid.WallShape, null), lv.wallShape(.{ .x = 7, .y = 6 }));
    try std.testing.expectEqual(grid.WallShape.block_br, lv.wallShape(.{ .x = 7, .y = 5 }).?);
    try std.testing.expectEqual(grid.WallShape.block_tr, lv.wallShape(.{ .x = 7, .y = 7 }).?);
    try std.testing.expectEqual(grid.WallShape.block_bl, lv.wallShape(.{ .x = 17, .y = 5 }).?);
    try std.testing.expectEqual(grid.WallShape.block_tl, lv.wallShape(.{ .x = 17, .y = 7 }).?);
}

test "a room corner beside a doorway takes the shape of the floor round it" {
    var lv = grid.Level.blank();
    const r = Room{ .x = 8, .y = 3, .w = 9, .h = 6 };
    carveRoom(&lv, r);
    room(&lv, 8, 1, 8, 2);
    room(&lv, 2, 8, 7, 8);
    shapeWalls(&lv);
    outlineRoom(&lv, r);
    try std.testing.expectEqual(grid.WallShape.left, lv.wallShape(.{ .x = 7, .y = 2 }).?);
    try std.testing.expectEqual(grid.WallShape.block_bl, lv.wallShape(.{ .x = 9, .y = 2 }).?);
    try std.testing.expectEqual(grid.WallShape.bottom, lv.wallShape(.{ .x = 7, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.block_br, lv.wallShape(.{ .x = 7, .y = 7 }).?);
    try std.testing.expectEqual(grid.WallShape.corner_tr, lv.wallShape(.{ .x = 17, .y = 2 }).?);
    try std.testing.expectEqual(grid.WallShape.corner_br, lv.wallShape(.{ .x = 17, .y = 9 }).?);
    try std.testing.expectEqual(grid.WallShape.bottom, lv.wallShape(.{ .x = 12, .y = 9 }).?);
}

test "every room corner still standing after generation is drawn as that corner, unless floor beside or below shapes it" {
    var lv: grid.Level = undefined;
    var standing: usize = 0;
    var by_floor: usize = 0;
    for (0..40) |i| {
        const f = build(&lv, 0xC0 +% i *% 104729);
        for (f.rooms[0..f.room_n]) |r| {
            for (CORNERS) |c| {
                const p = r.corner(c.floor);
                if (lv.at(p) != .wall) continue;
                if (keepsFloorShape(&lv, p, c.floor)) {
                    by_floor += 1;
                    try std.testing.expect(lv.wallShape(p).? != c.s);
                    continue;
                }
                standing += 1;
                try std.testing.expectEqual(c.s, lv.wallShape(p).?);
            }
        }
    }
    std.debug.print("40 floors: {d} room corners drawn as corners, {d} drawn by the floor beside or below them\n", .{ standing, by_floor });
    try std.testing.expect(standing > 40 * 4);
}

test "floor lies below a wall exactly when it is a top wall, a bottom block corner or a post" {
    var lv: grid.Level = undefined;
    for (0..40) |i| {
        _ = build(&lv, 0xFACE +% i *% 7919);
        for (lv.shape, 0..) |shape, k| {
            const s = shape orelse continue;
            const below = lv.walkable(grid.Level.of(k).add(mathx.Dir.s.delta()));
            const faced = switch (s) {
                .top, .block_bl, .block_br, .post => true,
                else => false,
            };
            try std.testing.expectEqual(below, faced);
        }
    }
}

test "build stamps a shape on every wall and on nothing else, and they divide up like this" {
    var lv: grid.Level = undefined;
    const shapes = comptime std.enums.values(grid.WallShape);
    var counts = [_]usize{0} ** shapes.len;
    for (0..40) |i| {
        _ = build(&lv, 0xA11 +% i *% 7919);
        for (lv.tile, lv.shape) |t, s| {
            try std.testing.expectEqual(t == .wall, s != null);
            if (s) |w| counts[@intFromEnum(w)] += 1;
        }
    }
    var faces: usize = 0;
    for (shapes, counts) |s, n| {
        if (s != .solid) faces += n;
    }
    std.debug.print("40 floors, {d} wall faces:", .{faces});
    for (shapes, counts) |s, n| {
        if (s != .solid) std.debug.print(" {s} {d}%", .{ @tagName(s), n * 100 / faces });
    }
    std.debug.print("\n", .{});
    const at = struct {
        fn n(cs: []const usize, s: grid.WallShape) usize {
            return cs[@intFromEnum(s)];
        }
    }.n;
    try std.testing.expect(at(&counts, .top) + at(&counts, .bottom) > faces / 4);
    try std.testing.expect(at(&counts, .left) + at(&counts, .right) > faces / 4);
}

test "every torch hangs on a room's top wall with floor below it" {
    var lv: grid.Level = undefined;
    var total: usize = 0;
    var rooms: usize = 0;
    for (0..40) |i| {
        const f = build(&lv, 0x7040 +% i *% 7919);
        rooms += f.room_n;
        total += lv.torch_n;
        for (lv.torches()) |t| {
            try std.testing.expectEqual(grid.WallShape.top, lv.wallShape(t).?);
            try std.testing.expect(lv.walkable(t.add(mathx.Dir.s.delta())));
        }
    }
    std.debug.print("40 floors: {d} torches over {d} rooms\n", .{ total, rooms });
    try std.testing.expect(total * 2 > rooms);
}

test "a seed reproduces a floor" {
    var a: grid.Level = undefined;
    var b: grid.Level = undefined;
    _ = build(&a, 777);
    _ = build(&b, 777);
    try std.testing.expectEqualSlices(grid.Tile, &a.tile, &b.tile);
    try std.testing.expectEqualSlices(P, a.torches(), b.torches());
}
