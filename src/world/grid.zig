const std = @import("std");
const mathx = @import("../core/mathx.zig");

const P = mathx.P;

pub const W: i32 = 96;
pub const H: i32 = 64;
pub const CELLS: usize = @intCast(W * H);
pub const COLS: usize = @intCast(W);
pub const ROWS: usize = @intCast(H);
pub const MIDDLE = P{ .x = @divTrunc(W, 2), .y = @divTrunc(H, 2) };
/// The corners of the map inside its edge, both inclusive.
pub const INNER_LO = P{ .x = 1, .y = 1 };
pub const INNER_HI = P{ .x = W - 2, .y = H - 2 };

pub const NO_ONE: u16 = 0;
pub const MAX_TORCHES: usize = 32;
pub const MAX_DOORS: usize = 16;
pub const NO_DOOR: u8 = 0;

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

/// Stamped once by `gen.shapeWalls`, a room's corners then by `gen.outlineRoom`, and never recomputed.
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
    barrel: [CELLS]bool,
    /// 1-based into the map's doors; `NO_DOOR` is none.
    door: [CELLS]u8,
    /// Caustic gas, Brogue's volume: `world/gas.zig` spreads it.
    gas: [CELLS]u16,
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
            .barrel = [_]bool{false} ** CELLS,
            .door = [_]u8{NO_DOOR} ** CELLS,
            .gas = [_]u16{0} ** CELLS,
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

    /// The nearest cell off the map's edge.
    pub fn inset(p: P) P {
        return .{ .x = std.math.clamp(p.x, INNER_LO.x, INNER_HI.x), .y = std.math.clamp(p.y, INNER_LO.y, INNER_HI.y) };
    }

    pub fn onRim(p: P) bool {
        return !inset(p).eq(p);
    }

    /// No step reaches a map corner: a diagonal into it cuts the rim's corner.
    pub fn cornered(p: P) bool {
        return (p.x == 0 or p.x == W - 1) and (p.y == 0 or p.y == H - 1);
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

    pub fn hasBarrel(self: *const Level, p: P) bool {
        return cellOr(bool, &self.barrel, p, false);
    }

    pub fn putBarrel(self: *Level, p: P) void {
        self.barrel[idx(p)] = true;
    }

    pub fn breakBarrel(self: *Level, p: P) bool {
        if (!self.hasBarrel(p)) return false;
        self.barrel[idx(p)] = false;
        return true;
    }

    /// The door's index into its map's doors.
    pub fn doorAt(self: *const Level, p: P) ?usize {
        const d = cellOr(u8, &self.door, p, NO_DOOR);
        return if (d == NO_DOOR) null else d - 1;
    }

    /// Opens the cell it hangs in.
    pub fn putDoor(self: *Level, p: P, i: usize) void {
        if (!inside(p)) return;
        const k = idx(p);
        self.tile[k] = .floor;
        self.door[k] = @intCast(i + 1);
    }

    pub fn gasAt(self: *const Level, p: P) u16 {
        return cellOr(u16, &self.gas, p, 0);
    }

    pub fn gassy(self: *const Level, p: P) bool {
        return self.gasAt(p) > 0;
    }

    pub fn addGas(self: *Level, p: P, volume: u16) void {
        if (!self.walkable(p)) return;
        const i = idx(p);
        self.gas[i] +|= volume;
    }

    pub fn taken(self: *const Level, p: P) bool {
        return self.who(p) != NO_ONE or self.hasBarrel(p);
    }

    /// Open, and no one and no barrel in it.
    pub fn vacant(self: *const Level, p: P) bool {
        return self.walkable(p) and !self.taken(p);
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
        const to = from.add(d.delta());
        if (self.hasBarrel(to)) return false;
        const w = self.who(to);
        return w == NO_ONE or w == ignore;
    }
};

/// From `lo` up to `hi`, `by` cells bigger each way, on the map.
pub fn grown(lo: P, hi: P, by: i32) [2]P {
    return .{
        .{ .x = @max(0, lo.x - by), .y = @max(0, lo.y - by) },
        .{ .x = @min(W, hi.x + by), .y = @min(H, hi.y + by) },
    };
}

/// Every cell from `lo` up to `hi`, row by row.
pub const Cells = struct {
    lo: P,
    hi: P,
    at: P,

    pub fn of(lo: P, hi: P) Cells {
        return .{ .lo = lo, .hi = hi, .at = if (lo.x < hi.x) lo else .{ .x = lo.x, .y = hi.y } };
    }

    /// Cells across `around(_, r)`.
    pub fn span(r: i32) i32 {
        return r * 2 + 1;
    }

    /// Every cell within `r` of `c`, on the map or off it.
    pub fn around(c: P, r: i32) Cells {
        return of(c.sub(.{ .x = r, .y = r }), c.add(.{ .x = r + 1, .y = r + 1 }));
    }

    pub fn next(self: *Cells) ?P {
        if (self.at.y >= self.hi.y) return null;
        const p = self.at;
        self.at.x += 1;
        if (self.at.x == self.hi.x) self.at = .{ .x = self.lo.x, .y = p.y + 1 };
        return p;
    }
};

pub fn cellOr(comptime T: type, cells: *const [CELLS]T, p: P, outside: T) T {
    if (!Level.inside(p)) return outside;
    const i = Level.idx(p);
    return cells[i];
}

/// Terrain only; -1 where nothing reaches. How many cells it reached.
pub fn distances(lv: *const Level, from: P, out: *[CELLS]i32, queue: *[CELLS]u32) usize {
    var flood = Flood.init(lv, from, out, queue);
    while (flood.next()) |_| {}
    return flood.tail;
}

/// Breadth first from a cell over the terrain, one cell at a time, nearest first; `dist` fills as it goes.
pub const Flood = struct {
    lv: *const Level,
    dist: *[CELLS]i32,
    queue: *[CELLS]u32,
    head: usize = 0,
    tail: usize = 1,

    pub fn init(lv: *const Level, from: P, dist: *[CELLS]i32, queue: *[CELLS]u32) Flood {
        @memset(dist, -1);
        const s = Level.idx(from);
        dist[s] = 0;
        queue[0] = @intCast(s);
        return .{ .lv = lv, .dist = dist, .queue = queue };
    }

    pub fn next(self: *Flood) ?P {
        if (self.head == self.tail) return null;
        const i = self.queue[self.head];
        self.head += 1;
        const here = Level.of(i);
        for (mathx.ALL_DIRS) |d| {
            if (!self.lv.passOk(here, d)) continue;
            const qi = Level.idx(here.add(d.delta()));
            if (self.dist[qi] >= 0) continue;
            self.dist[qi] = self.dist[i] + 1;
            self.queue[self.tail] = @intCast(qi);
            self.tail += 1;
        }
        return here;
    }
};

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
    return lineOk(lv, from, to, false);
}

/// `clearLine`, and every cell on it lit, the target's too.
pub fn litLine(lv: *const Level, from: P, to: P) bool {
    return lineOk(lv, from, to, true);
}

fn lineOk(lv: *const Level, from: P, to: P, comptime lit: bool) bool {
    var ray = Ray.init(from, to);
    while (ray.next()) |c| {
        if (lit and !lv.isLit(c)) return false;
        if (c.eq(to)) return true;
        if (lv.at(c).blind()) return false;
    }
    return true;
}

pub fn openFloor() Level {
    var lv = Level.blank();
    for (0..CELLS) |i| {
        const p = Level.of(i);
        if (!Level.onRim(p)) lv.tile[i] = .floor;
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

test "a barrel blocks a step until it breaks" {
    var lv = openFloor();
    const p = P{ .x = 6, .y = 5 };
    lv.putBarrel(p);
    try std.testing.expect(!lv.stepOk(.{ .x = 5, .y = 5 }, .e, NO_ONE));
    try std.testing.expect(lv.breakBarrel(p));
    try std.testing.expect(!lv.breakBarrel(p));
    try std.testing.expect(lv.stepOk(.{ .x = 5, .y = 5 }, .e, NO_ONE));
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
