const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");

const P = mathx.P;

const Cardinal = enum { north, south, east, west };

const Quad = struct {
    origin: P,
    card: Cardinal,

    fn at(q: Quad, depth: i32, col: i32) P {
        return switch (q.card) {
            .north => .{ .x = q.origin.x + col, .y = q.origin.y - depth },
            .south => .{ .x = q.origin.x + col, .y = q.origin.y + depth },
            .east => .{ .x = q.origin.x + depth, .y = q.origin.y + col },
            .west => .{ .x = q.origin.x - depth, .y = q.origin.y + col },
        };
    }
};

const Row = struct {
    depth: i32,
    start: f32,
    end: f32,
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

/// Symmetric shadowcasting: what `origin` sees is lit, and seen from then on.
pub fn cast(lv: *grid.Level, origin: P, radius: i32) void {
    lv.lightless();
    castWith(lv, origin, radius, Sight{ .lv = lv });
}

/// Leaves the cells of `out` it does not reach as they were.
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
    for (std.enums.values(Cardinal)) |c| {
        scan(lv, sink, .{ .origin = origin, .card = c }, .{ .depth = 1, .start = -1, .end = 1 }, radius);
    }
}

fn scan(lv: *const grid.Level, sink: anytype, q: Quad, row_in: Row, radius: i32) void {
    if (row_in.depth > radius) return;
    var row = row_in;
    var prev_wall: ?bool = null;
    const d: f32 = @floatFromInt(row.depth);
    // Ties round UP on the near edge and DOWN on the far edge; backwards, a wall corner becomes a peephole.
    var col = mathx.roundTiesUp(d * row.start);
    const max_col = mathx.roundTiesDown(d * row.end);
    while (col <= max_col) : (col += 1) {
        const p = q.at(row.depth, col);
        const wall = lv.at(p).blind();
        if (mathx.distEuclid(q.origin, p) <= @as(f32, @floatFromInt(radius)) + 0.5) {
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

/// The hero carries a light, so is never too dark to see.
pub fn sees(lv: *const grid.Level, watcher: P, hero: P, reach: i32) bool {
    return lv.inLos(watcher) and mathx.dist(watcher, hero) <= reach;
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
    std.debug.print("radius 8: {d} cells lit, a disc is {d:.0}, a square would be {d}\n", .{ lit, disc, 17 * 17 });
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
    std.debug.print("{d} open cells inside the pool, {d} asymmetric\n", .{ checked, broken });
    try std.testing.expect(checked > 150);
    try std.testing.expectEqual(@as(usize, 0), broken);
}
