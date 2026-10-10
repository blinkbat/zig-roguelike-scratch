const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const carve = @import("carve.zig");
const lume = @import("lume.zig");

const P = mathx.P;

const MARGIN: i32 = 2;
/// Wall cells between two rooms, so no outline cell belongs to both.
const ROOM_GAP: i32 = 2;
pub const MAX_ROOMS: usize = 24;
const ROOM_TRIES: usize = 300;
pub const ROOM_MIN: i32 = 3;
pub const ROOM_W_MAX: i32 = 24;
pub const ROOM_H_MAX: i32 = 16;
pub const BARRELS_MAX: u32 = 6;
pub const SIZE_MIN = P{ .x = ROOM_MIN + 2 * MARGIN, .y = ROOM_MIN + 2 * MARGIN };
const ROOMS_PER_LOOP: usize = 4;
const CONNECT_PASSES: usize = 64;

comptime {
    std.debug.assert(grid.MAX_TORCHES >= MAX_ROOMS);
}

pub const Params = struct {
    size: P = .{ .x = grid.W, .y = grid.H },
    rooms: usize = MAX_ROOMS,
    /// Lowest and highest, both inclusive.
    room_w: [2]i32 = .{ 5, 13 },
    room_h: [2]i32 = .{ 4, 9 },
    /// Percent of rooms that hang a torch.
    torches: u8 = 70,
    /// The most barrels one room stacks.
    barrels: u32 = 2,

    pub fn fit(p: Params) Params {
        var q = p;
        q.size = .{ .x = std.math.clamp(p.size.x, SIZE_MIN.x, grid.W), .y = std.math.clamp(p.size.y, SIZE_MIN.y, grid.H) };
        q.rooms = std.math.clamp(p.rooms, 1, MAX_ROOMS);
        q.room_w = span(p.room_w, @min(ROOM_W_MAX, q.size.x - 2 * MARGIN));
        q.room_h = span(p.room_h, @min(ROOM_H_MAX, q.size.y - 2 * MARGIN));
        q.torches = @min(p.torches, mathx.PERCENT);
        q.barrels = @min(p.barrels, BARRELS_MAX);
        return q;
    }

    fn span(r: [2]i32, most: i32) [2]i32 {
        return mathx.span(i32, r, ROOM_MIN, most);
    }

    fn corner(p: Params) P {
        return grid.Box.centred(p.size.x, p.size.y).lo;
    }
};

pub const Room = grid.Box;

pub const Floor = struct {
    rooms: [MAX_ROOMS]Room = undefined,
    room_n: usize = 0,
    start: P = .{ .x = 0, .y = 0 },
};

pub fn build(lv: *grid.Level, seed: u64) Floor {
    return around(lv, seed, &.{}, .{});
}

/// Every open cell connected, each of `doors` too; reproducible from the seed, the doors and `params`.
pub fn around(lv: *grid.Level, seed: u64, doors: []const P, params: Params) Floor {
    std.debug.assert(doors.len <= grid.MAX_DOORS);
    const pm = params.fit();
    const o = pm.corner();
    lv.* = grid.Level.blank();
    var rng = mathx.Rng.init(seed);
    var f = Floor{};
    var tries: usize = 0;
    while (tries < ROOM_TRIES and f.room_n < pm.rooms) : (tries += 1) {
        const w = rng.range(pm.room_w[0], pm.room_w[1]);
        const h = rng.range(pm.room_h[0], pm.room_h[1]);
        const at = (grid.Box{ .lo = o.add(.{ .x = MARGIN, .y = MARGIN }), .hi = o.add(pm.size).sub(.{ .x = MARGIN, .y = MARGIN }) }).rollFor(&rng, w, h);
        const r = Room.sized(at, w, h);
        if (!addRoom(&f, r)) continue;
        carve.box(lv, r, .floor);
    }
    var i: usize = 1;
    while (i < f.room_n) : (i += 1) tunnel(lv, f.rooms[i - 1].centre(), f.rooms[i].centre(), &rng);
    // A pure tree puts every fight in a corridor with no way round.
    for (0..f.room_n / ROOMS_PER_LOOP) |_| {
        const a = rng.below(@intCast(f.room_n));
        const b = rng.below(@intCast(f.room_n));
        if (a != b) tunnel(lv, f.rooms[a].centre(), f.rooms[b].centre(), &rng);
    }
    for (doors, 0..) |d, k| {
        lv.putDoor(d, k);
        // A door on the map's edge is reached from the cell inside it, so no corridor runs along the edge.
        const in = grid.Level.inset(d);
        runX(lv, d.x, in.x, d.y);
        runY(lv, d.y, in.y, in.x);
    }
    connect(lv, &rng);
    shapeWalls(lv);
    for (f.rooms[0..f.room_n]) |r| {
        if (rng.percent(pm.torches)) hangTorch(lv, r, &rng);
    }
    for (f.rooms[0..f.room_n]) |r| stackBarrels(lv, r, &rng, pm.barrels);
    f.start = f.rooms[0].centre();
    return f;
}

fn hangTorch(lv: *grid.Level, r: Room, rng: *mathx.Rng) void {
    var spots: [ROOM_W_MAX]i32 = undefined;
    var n: usize = 0;
    var x = r.lo.x;
    while (x < r.hi.x) : (x += 1) {
        if (!bearsTorch(lv, .{ .x = x, .y = r.lo.y - 1 })) continue;
        spots[n] = x;
        n += 1;
    }
    if (n == 0) return;
    lv.addTorch(.{ .x = spots[rng.below(@intCast(n))], .y = r.lo.y - 1 });
}

/// Against the room's own walls and nowhere beside a way in, so no barrel can seal a path.
fn stackBarrels(lv: *grid.Level, r: Room, rng: *mathx.Rng, most: u32) void {
    var spots: [2 * (ROOM_W_MAX + ROOM_H_MAX)]P = undefined;
    var n: usize = 0;
    var cells = r.cells();
    while (cells.next()) |p| {
        if (!r.onEdge(p) or besideDoor(lv, r, p) or lv.doorAt(p) != null) continue;
        spots[n] = p;
        n += 1;
    }
    var left = rng.below(most + 1);
    while (left > 0 and n > 0) : (left -= 1) {
        const k = rng.below(@intCast(n));
        lv.putBarrel(spots[k]);
        n -= 1;
        spots[k] = spots[n];
    }
}

fn besideDoor(lv: *const grid.Level, r: Room, p: P) bool {
    for (mathx.ALL_DIRS) |d| {
        const q = p.add(d.delta());
        if (!r.holds(q) and lv.walkable(q)) return true;
    }
    return false;
}

fn addRoom(f: *Floor, r: Room) bool {
    for (f.rooms[0..f.room_n]) |have| {
        if (r.overlaps(have, ROOM_GAP)) return false;
    }
    f.rooms[f.room_n] = r;
    f.room_n += 1;
    return true;
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

fn connect(lv: *grid.Level, rng: *mathx.Rng) void {
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    for (0..CONNECT_PASSES) |_| {
        const start = lv.firstOpen() orelse return;
        _ = grid.distances(lv, start, &dist, &queue);
        var orphan: ?P = null;
        for (0..grid.CELLS) |i| {
            if (!lv.tile[i].solid() and dist[i] < 0) {
                orphan = grid.Level.of(i);
                break;
            }
        }
        const o = grid.Level.inset(orphan orelse return);
        tunnel(lv, o, grid.nearest(o, Reached{ .dist = &dist }) orelse return, rng);
    }
}

const Reached = struct {
    dist: *const [grid.CELLS]i32,

    pub fn has(r: Reached, i: usize) bool {
        return r.dist[i] >= 0 and !grid.Level.onRim(grid.Level.of(i));
    }
};

pub fn shapeWalls(lv: *grid.Level) void {
    for (0..grid.CELLS) |i| {
        lv.shape[i] = if (lv.tile[i] == .wall) wallShape(lv, grid.Level.of(i)) else null;
    }
}

fn wallShape(lv: *const grid.Level, p: P) grid.WallShape {
    return grid.WallShape.joined(.{
        .n = joins(lv, p, .n),
        .e = joins(lv, p, .e),
        .s = joins(lv, p, .s),
        .w = joins(lv, p, .w),
        .ne = joins(lv, p, .ne),
        .se = joins(lv, p, .se),
        .sw = joins(lv, p, .sw),
        .nw = joins(lv, p, .nw),
    });
}

/// Off the map counts, so a wall runs on over the edge.
fn joins(lv: *const grid.Level, p: P, d: mathx.Dir) bool {
    return lv.at(p.add(d.delta())) == .wall;
}

/// A wall whose brick face looks onto floor.
pub fn bearsTorch(lv: *const grid.Level, p: P) bool {
    const s = lv.wallShape(p) orelse return false;
    return s.faced() and lv.walkable(lume.torchFloor(p));
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
    carve.box(lv, .{ .lo = .{ .x = x0, .y = y0 }, .hi = .{ .x = x1 + 1, .y = y1 + 1 } }, .floor);
}

fn shapeAt(lv: *const grid.Level, x: i32, y: i32) grid.WallShape {
    return lv.wallShape(.{ .x = x, .y = y }).?;
}

test "a room's sides and corners are shaped by the walls round them, and the rock behind it is solid" {
    var lv = grid.Level.blank();
    room(&lv, 5, 5, 10, 8);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .w = true, .ne = true, .nw = true }, shapeAt(&lv, 7, 4));
    try std.testing.expectEqual(grid.WallShape{ .e = true, .s = true, .w = true, .se = true, .sw = true }, shapeAt(&lv, 7, 9));
    try std.testing.expectEqual(grid.WallShape{ .n = true, .s = true, .w = true, .sw = true, .nw = true }, shapeAt(&lv, 4, 6));
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .s = true, .ne = true, .se = true }, shapeAt(&lv, 11, 6));
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .s = true, .w = true, .ne = true, .sw = true, .nw = true }, shapeAt(&lv, 4, 4));
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .s = true, .w = true, .ne = true, .se = true, .nw = true }, shapeAt(&lv, 11, 4));
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .s = true, .w = true, .se = true, .sw = true, .nw = true }, shapeAt(&lv, 4, 9));
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .s = true, .w = true, .ne = true, .se = true, .sw = true }, shapeAt(&lv, 11, 9));
    try std.testing.expect(shapeAt(&lv, 2, 2).solid());
    try std.testing.expectEqual(@as(?grid.WallShape, null), lv.wallShape(.{ .x = 7, .y = 6 }));
}

test "a wall with floor on two diagonals joins the other two corners" {
    var lv = grid.Level.blank();
    lv.set(.{ .x = 6, .y = 6 }, .floor);
    lv.set(.{ .x = 4, .y = 4 }, .floor);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .s = true, .w = true, .ne = true, .sw = true }, shapeAt(&lv, 5, 5));
}

test "a corner joins only where both sides beside it do" {
    var lv = grid.Level.blank();
    lv.set(.{ .x = 5, .y = 4 }, .floor);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape{ .e = true, .s = true, .w = true, .se = true, .sw = true }, shapeAt(&lv, 5, 5));
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .s = true, .w = true, .se = true, .sw = true, .nw = true }, shapeAt(&lv, 4, 5));
}

test "a wall on the map's edge runs on over it" {
    var lv = grid.Level.blank();
    lv.set(.{ .x = 1, .y = 1 }, .floor);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .s = true, .w = true, .ne = true, .sw = true, .nw = true }, shapeAt(&lv, 0, 0));
}

test "a wall between two corridors joins only along itself, and a pillar joins nothing" {
    var lv = grid.Level.blank();
    room(&lv, 5, 10, 20, 10);
    room(&lv, 5, 12, 20, 12);
    room(&lv, 30, 5, 34, 9);
    lv.set(.{ .x = 32, .y = 7 }, .wall);
    shapeWalls(&lv);
    try std.testing.expectEqual(grid.WallShape{ .e = true, .w = true }, shapeAt(&lv, 12, 11));
    try std.testing.expectEqual(grid.WallShape{ .n = true, .e = true, .w = true, .ne = true, .nw = true }, shapeAt(&lv, 12, 9));
    try std.testing.expectEqual(grid.WallShape{}, shapeAt(&lv, 32, 7));
}

test "a wall's brick face shows exactly when no wall stands below it" {
    var lv: grid.Level = undefined;
    for (0..40) |i| {
        _ = build(&lv, 0xFACE +% i *% 7919);
        for (lv.shape, 0..) |shape, k| {
            const s = shape orelse continue;
            try std.testing.expectEqual(lv.at(grid.Level.of(k).add(mathx.Dir.s.delta())) != .wall, s.faced());
        }
    }
}

test "build stamps a joined shape on every wall and on nothing else" {
    var lv: grid.Level = undefined;
    var used = std.StaticBitSet(256).initEmpty();
    for (0..40) |i| {
        _ = build(&lv, 0xA11 +% i *% 7919);
        for (lv.tile, lv.shape) |t, s| {
            try std.testing.expectEqual(t == .wall, s != null);
            const w = s orelse continue;
            try std.testing.expectEqual(w, w.joined());
            used.set(w.mask());
        }
    }
    std.debug.print("40 floors use {d} of the 47 wall shapes\n", .{used.count()});
    try std.testing.expect(used.count() > 20);
}

test "every torch hangs on a room's wall with its face onto floor" {
    var lv: grid.Level = undefined;
    var total: usize = 0;
    var rooms: usize = 0;
    for (0..40) |i| {
        const f = build(&lv, 0x7040 +% i *% 7919);
        rooms += f.room_n;
        total += lv.torch.n;
        for (lv.torches()) |t| try std.testing.expect(bearsTorch(&lv, t));
    }
    std.debug.print("40 floors: {d} torches over {d} rooms\n", .{ total, rooms });
    try std.testing.expect(total * 2 > rooms);
}

test "barrels stand on room floor and never cut one open cell off from the start" {
    var lv: grid.Level = undefined;
    var reached: [grid.CELLS]bool = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var barrels: usize = 0;
    var rooms: usize = 0;
    for (0..200) |i| {
        const f = build(&lv, 0xBA22E1 +% i *% 7919);
        rooms += f.room_n;
        try std.testing.expect(!lv.hasBarrel(f.start));
        var open: usize = 0;
        for (0..grid.CELLS) |c| {
            if (lv.barrel[c]) {
                barrels += 1;
                try std.testing.expect(lv.walkable(grid.Level.of(c)));
            } else if (!lv.tile[c].solid()) open += 1;
        }
        @memset(&reached, false);
        reached[grid.Level.idx(f.start)] = true;
        queue[0] = @intCast(grid.Level.idx(f.start));
        var head: usize = 0;
        var tail: usize = 1;
        while (head < tail) : (head += 1) {
            const here = grid.Level.of(queue[head]);
            for (mathx.ALL_DIRS) |d| {
                if (!lv.stepOk(here, d, grid.NO_ONE)) continue;
                const k = grid.Level.idx(here.add(d.delta()));
                if (reached[k]) continue;
                reached[k] = true;
                queue[tail] = @intCast(k);
                tail += 1;
            }
        }
        try std.testing.expectEqual(open, tail);
    }
    std.debug.print("200 floors: {d} barrels over {d} rooms, every open cell still reached\n", .{ barrels, rooms });
    try std.testing.expect(barrels > rooms / 2);
}

test "a floor generated around doors reaches every door, and no barrel stands on one" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var rng = mathx.Rng.init(0xD00);
    var longest: i32 = 0;
    for (0..100) |i| {
        var doors: [4]P = undefined;
        const band: i32 = @divTrunc(grid.H, @as(i32, doors.len));
        for (&doors, 0..) |*d, k| {
            const top = @as(i32, @intCast(k)) * band;
            d.* = .{ .x = rng.range(0, grid.W - 1), .y = rng.range(top, top + band - 1) };
        }
        const f = around(&lv, 0xD0025 +% i *% 7919, &doors, .{});
        _ = grid.distances(&lv, f.start, &dist, &queue);
        for (doors, 0..) |d, k| {
            try std.testing.expectEqual(@as(?usize, k), lv.doorAt(d));
            try std.testing.expect(!lv.hasBarrel(d));
            const walked = dist[grid.Level.idx(d)];
            try std.testing.expect(walked >= 0);
            longest = @max(longest, walked);
        }
    }
    std.debug.print("100 floors round 4 doors each: every door reached, the farthest {d} steps from the start\n", .{longest});
}

test "a door on the map's edge is the only floor on the edge" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var rng = mathx.Rng.init(0xED6E);
    var rim: usize = 0;
    for (0..200) |i| {
        const doors = [_]P{
            .{ .x = 0, .y = rng.range(1, grid.H - 2) },
            .{ .x = grid.W - 1, .y = rng.range(1, grid.H - 2) },
            .{ .x = rng.range(1, grid.W - 2), .y = 0 },
            .{ .x = rng.range(1, grid.W - 2), .y = grid.H - 1 },
        };
        const f = around(&lv, 0xED6E5 +% i *% 7919, &doors, .{});
        _ = grid.distances(&lv, f.start, &dist, &queue);
        for (doors) |d| try std.testing.expect(dist[grid.Level.idx(d)] >= 0);
        for (0..grid.CELLS) |k| {
            const p = grid.Level.of(k);
            if (grid.Level.onRim(p) and lv.walkable(p) and lv.doorAt(p) == null) rim += 1;
        }
    }
    std.debug.print("200 floors with a door on each edge: {d} edge cells of floor that are not doors\n", .{rim});
    try std.testing.expectEqual(@as(usize, 0), rim);
}

test "a floor rolled in a small box keeps its rooms in it, to their count and size, and still connects" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const pm = Params{ .size = .{ .x = 40, .y = 30 }, .rooms = 6, .room_w = .{ 4, 8 }, .room_h = .{ 3, 6 }, .torches = 0, .barrels = 0 };
    const o = pm.corner();
    var rooms: usize = 0;
    for (0..50) |i| {
        const f = around(&lv, 0xB0C5 +% i *% 7919, &.{.{ .x = 2, .y = 2 }}, pm);
        rooms += f.room_n;
        try std.testing.expect(f.room_n >= 1 and f.room_n <= pm.rooms);
        try std.testing.expectEqual(@as(usize, 0), lv.torch.n);
        for (f.rooms[0..f.room_n]) |r| {
            try std.testing.expect(r.width() >= 4 and r.width() <= 8 and r.height() >= 3 and r.height() <= 6);
            try std.testing.expect(r.lo.x >= o.x + MARGIN and r.hi.x <= o.x + pm.size.x - MARGIN);
            try std.testing.expect(r.lo.y >= o.y + MARGIN and r.hi.y <= o.y + pm.size.y - MARGIN);
        }
        _ = grid.distances(&lv, f.start, &dist, &queue);
        try std.testing.expect(dist[grid.Level.idx(.{ .x = 2, .y = 2 })] >= 0);
    }
    std.debug.print("50 floors in a 40x30 box, at most 6 rooms: {d} rooms\n", .{rooms});
    const squeezed = (Params{ .size = .{ .x = 1, .y = 500 }, .room_w = .{ 20, 2 } }).fit();
    try std.testing.expectEqual(SIZE_MIN.x, squeezed.size.x);
    try std.testing.expectEqual([2]i32{ ROOM_MIN, ROOM_MIN }, squeezed.room_w);
    try std.testing.expectEqual(grid.H, squeezed.size.y);
}

test "a seed reproduces a floor" {
    var a: grid.Level = undefined;
    var b: grid.Level = undefined;
    _ = build(&a, 777);
    _ = build(&b, 777);
    try std.testing.expectEqualSlices(grid.Tile, &a.tile, &b.tile);
    try std.testing.expectEqualSlices(P, a.torches(), b.torches());
    try std.testing.expectEqualSlices(bool, &a.barrel, &b.barrel);
}
