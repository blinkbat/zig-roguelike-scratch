const std = @import("std");
const mathx = @import("../core/mathx.zig");

const P = mathx.P;

pub const W: i32 = 96;
pub const H: i32 = 64;
pub const CELLS: usize = @intCast(W * H);

pub const NO_ONE: u16 = 0;
pub const MAX_TORCHES: usize = 32;

pub const Tile = enum(u8) {
    wall,
    floor,

    pub fn solid(t: Tile) bool {
        return switch (t) {
            .wall => true,
            .floor => false,
        };
    }

    pub fn blind(t: Tile) bool {
        return switch (t) {
            .wall => true,
            .floor => false,
        };
    }
};

/// Stamped once by `gen.build` and never recomputed.
pub const WallShape = enum {
    top,
    bottom,
    left,
    right,
    /// Named for where it sits on the block: `block_tr` has its floor north and east.
    block_tl,
    block_tr,
    block_bl,
    block_br,
    post,
    /// Named for where it sits on the room: `corner_tl` has its floor south-east.
    corner_tl,
    corner_tr,
    corner_bl,
    corner_br,
    solid,

    /// Floor lies below it, so its brick face shows.
    pub fn faced(s: WallShape) bool {
        return switch (s) {
            .top, .block_bl, .block_br, .post => true,
            .bottom, .left, .right, .block_tl, .block_tr, .corner_tl, .corner_tr, .corner_bl, .corner_br, .solid => false,
        };
    }
};

pub const Level = struct {
    tile: [CELLS]Tile,
    /// Null on anything that is not a wall.
    shape: [CELLS]?WallShape,
    seen: [CELLS]bool,
    lit: [CELLS]bool,
    /// 1-based into the actor pool; `NO_ONE` is empty.
    occupant: [CELLS]u16,
    /// Walls with a torch on their face.
    torch: [MAX_TORCHES]P,
    torch_n: usize,

    pub fn blank() Level {
        return .{
            .tile = [_]Tile{.wall} ** CELLS,
            .shape = [_]?WallShape{null} ** CELLS,
            .seen = [_]bool{false} ** CELLS,
            .lit = [_]bool{false} ** CELLS,
            .occupant = [_]u16{NO_ONE} ** CELLS,
            .torch = undefined,
            .torch_n = 0,
        };
    }

    pub fn torches(self: *const Level) []const P {
        return self.torch[0..self.torch_n];
    }

    pub fn addTorch(self: *Level, p: P) void {
        if (self.torch_n == MAX_TORCHES) return;
        self.torch[self.torch_n] = p;
        self.torch_n += 1;
    }

    pub fn wallShape(self: *const Level, p: P) ?WallShape {
        return cellOr(?WallShape, &self.shape, p, null);
    }

    pub fn inside(p: P) bool {
        return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H;
    }

    /// Bind it before reading: `self.tile[idx(p)]` makes Zig 0.14 copy the whole array to honour the call's order.
    pub fn idx(p: P) usize {
        std.debug.assert(inside(p));
        return @intCast(p.y * W + p.x);
    }

    pub fn of(i: usize) P {
        const n: i32 = @intCast(i);
        return .{ .x = @mod(n, W), .y = @divFloor(n, W) };
    }

    /// Outside the map reads as wall, so no caller needs a bounds check.
    pub fn at(self: *const Level, p: P) Tile {
        return cellOr(Tile, &self.tile, p, .wall);
    }

    pub fn set(self: *Level, p: P, t: Tile) void {
        if (!inside(p)) return;
        self.tile[idx(p)] = t;
    }

    pub fn who(self: *const Level, p: P) u16 {
        return cellOr(u16, &self.occupant, p, NO_ONE);
    }

    pub fn stand(self: *Level, p: P, id: u16) void {
        self.occupant[idx(p)] = id;
    }

    pub fn clear(self: *Level, p: P) void {
        self.occupant[idx(p)] = NO_ONE;
    }

    pub fn lightless(self: *Level) void {
        self.lit = [_]bool{false} ** CELLS;
    }

    pub fn light(self: *Level, p: P) void {
        if (!inside(p)) return;
        self.lit[idx(p)] = true;
        self.seen[idx(p)] = true;
    }

    pub fn isLit(self: *const Level, p: P) bool {
        return cellOr(bool, &self.lit, p, false);
    }

    pub fn isSeen(self: *const Level, p: P) bool {
        return cellOr(bool, &self.seen, p, false);
    }

    pub fn walkable(self: *const Level, p: P) bool {
        return inside(p) and !self.at(p).solid();
    }

    /// Terrain only. A diagonal may not cut the corner of a wall on either side of it.
    pub fn passOk(self: *const Level, from: P, d: mathx.Dir) bool {
        const to = from.add(d.delta());
        if (!self.walkable(to)) return false;
        if (!d.diagonal()) return true;
        return self.walkable(.{ .x = to.x, .y = from.y }) and self.walkable(.{ .x = from.x, .y = to.y });
    }

    /// `ignore` is the mover's own id.
    pub fn stepOk(self: *const Level, from: P, d: mathx.Dir, ignore: u16) bool {
        if (!self.passOk(from, d)) return false;
        const w = self.who(from.add(d.delta()));
        return w == NO_ONE or w == ignore;
    }
};

pub fn cellOr(comptime T: type, cells: *const [CELLS]T, p: P, outside: T) T {
    if (!Level.inside(p)) return outside;
    const i = Level.idx(p);
    return cells[i];
}

/// Terrain only; -1 where nothing reaches.
pub fn distances(lv: *const Level, from: P, out: *[CELLS]i32, queue: *[CELLS]u32) usize {
    @memset(out, -1);
    var head: usize = 0;
    var tail: usize = 0;
    const s = Level.idx(from);
    out[s] = 0;
    queue[tail] = @intCast(s);
    tail += 1;
    while (head < tail) {
        const i = queue[head];
        head += 1;
        const here = Level.of(i);
        for (mathx.ALL_DIRS) |d| {
            if (!lv.passOk(here, d)) continue;
            const qi = Level.idx(here.add(d.delta()));
            if (out[qi] >= 0) continue;
            out[qi] = out[i] + 1;
            queue[tail] = @intCast(qi);
            tail += 1;
        }
    }
    return tail;
}

/// Bresenham from the cell after `from` up to and including `to`.
pub const Ray = struct {
    x: i32,
    y: i32,
    tx: i32,
    ty: i32,
    dx: i32,
    dy: i32,
    sx: i32,
    sy: i32,
    err: i32,
    done: bool,

    pub fn init(from: P, to: P) Ray {
        const dx: i32 = @intCast(@abs(to.x - from.x));
        const dy: i32 = @intCast(@abs(to.y - from.y));
        return .{
            .x = from.x,
            .y = from.y,
            .tx = to.x,
            .ty = to.y,
            .dx = dx,
            .dy = dy,
            .sx = if (to.x > from.x) 1 else -1,
            .sy = if (to.y > from.y) 1 else -1,
            .err = dx - dy,
            .done = from.eq(to),
        };
    }

    pub fn next(self: *Ray) ?P {
        if (self.done) return null;
        const e2 = self.err * 2;
        if (e2 > -self.dy) {
            self.err -= self.dy;
            self.x += self.sx;
        }
        if (e2 < self.dx) {
            self.err += self.dx;
            self.y += self.sy;
        }
        if (self.x == self.tx and self.y == self.ty) self.done = true;
        return .{ .x = self.x, .y = self.y };
    }
};

/// No wall strictly between the two. The target's own cell may be opaque.
pub fn clearLine(lv: *const Level, from: P, to: P) bool {
    var ray = Ray.init(from, to);
    while (ray.next()) |c| {
        if (c.eq(to)) return true;
        if (lv.at(c).blind()) return false;
    }
    return true;
}

pub fn openFloor() Level {
    var lv = Level.blank();
    for (0..CELLS) |i| {
        const p = Level.of(i);
        if (p.x > 0 and p.y > 0 and p.x < W - 1 and p.y < H - 1) lv.tile[i] = .floor;
    }
    return lv;
}

test "an index round-trips" {
    for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = W - 1, .y = H - 1 }, .{ .x = 37, .y = 41 } }) |p| {
        try std.testing.expectEqual(p, Level.of(Level.idx(p)));
    }
    try std.testing.expect(!Level.inside(.{ .x = -1, .y = 0 }));
    try std.testing.expect(!Level.inside(.{ .x = W, .y = 0 }));
}

test "outside the map reads as wall" {
    var lv = Level.blank();
    lv.set(.{ .x = -3, .y = 2 }, .floor);
    try std.testing.expectEqual(Tile.wall, lv.at(.{ .x = -3, .y = 2 }));
}

test "a diagonal cannot cut the corner of a single wall" {
    var lv = openFloor();
    const from = P{ .x = 10, .y = 10 };
    try std.testing.expect(lv.stepOk(from, .se, NO_ONE));
    lv.set(.{ .x = 11, .y = 10 }, .wall);
    try std.testing.expect(!lv.stepOk(from, .se, NO_ONE));
    try std.testing.expect(lv.stepOk(from, .s, NO_ONE));
}

test "a body blocks a step but never itself" {
    var lv = openFloor();
    lv.stand(.{ .x = 6, .y = 5 }, 7);
    try std.testing.expect(!lv.stepOk(.{ .x = 5, .y = 5 }, .e, 3));
    try std.testing.expect(lv.stepOk(.{ .x = 5, .y = 5 }, .e, 7));
}

test "a ray reaches its mark in chebyshev steps and a wall blocks the line" {
    var lv = openFloor();
    const a = P{ .x = 4, .y = 9 };
    const b = P{ .x = 17, .y = 14 };
    var ray = Ray.init(a, b);
    var last = a;
    var n: i32 = 0;
    while (ray.next()) |c| {
        last = c;
        n += 1;
    }
    try std.testing.expectEqual(b, last);
    try std.testing.expectEqual(mathx.dist(a, b), n);
    try std.testing.expect(clearLine(&lv, a, b));
    var y: i32 = 5;
    while (y < 20) : (y += 1) lv.set(.{ .x = 10, .y = y }, .wall);
    try std.testing.expect(!clearLine(&lv, a, b));
}

test "distances walk round a wall rather than through it" {
    var lv = openFloor();
    var y: i32 = 1;
    while (y < 20) : (y += 1) lv.set(.{ .x = 10, .y = y }, .wall);
    var out: [CELLS]i32 = undefined;
    var queue: [CELLS]u32 = undefined;
    _ = distances(&lv, .{ .x = 9, .y = 5 }, &out, &queue);
    const across = out[Level.idx(.{ .x = 11, .y = 5 })];
    std.debug.print("two cells apart through a wall: {d} steps walked\n", .{across});
    try std.testing.expect(across > 20);
}
