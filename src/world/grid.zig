const std = @import("std");
const mathx = @import("../core/mathx.zig");

const P = mathx.P;

pub const W: i32 = 96;
pub const H: i32 = 64;
pub const CELLS: usize = @intCast(W * H);
pub const COLS: usize = @intCast(W);
pub const ROWS: usize = @intCast(H);
/// The points where cells meet, the map's edges included.
pub const CORNERS_W: usize = COLS + 1;
pub const CORNERS_H: usize = ROWS + 1;
pub const SIZE = P{ .x = W, .y = H };
pub const MIDDLE = P{ .x = @divTrunc(W, 2), .y = @divTrunc(H, 2) };

pub const NO_ONE: u16 = 0;
pub const MAX_TORCHES: usize = 32;
pub const MAX_DOORS: usize = 16;
pub const NO_DOOR: u8 = 0;

pub const Tile = enum(u8) {
    /// Built, and shaped by `gen.shapeWalls`.
    wall,
    floor,
    grass,
    shrub,
    /// Natural stone: a cave's walls, a cliff, a crag.
    rock,
    dirt,
    sand,
    snow,
    water,
    shallows,
    bridge,
    reeds,
    rubble,
    fence,
    lava,
    fungus,
    chasm,
    ice,
    grave,
    crop,
    tiny_shrub,
    boulder,
    tall_grass,
    shrooms,

    pub fn solid(t: Tile) bool {
        return TERRAIN.getPtrConst(t).solid;
    }

    pub fn blind(t: Tile) bool {
        return TERRAIN.getPtrConst(t).blind;
    }

    /// What lies under it: drawn first, beneath its own picture.
    pub fn ground(t: Tile) ?Tile {
        return TERRAIN.getPtrConst(t).ground;
    }

    /// Water, lava or a chasm, which a trail crosses by a bridge.
    pub fn liquid(t: Tile) bool {
        return TERRAIN.getPtrConst(t).liquid;
    }

    pub fn upright(t: Tile) bool {
        return t.solid() and !t.liquid();
    }

    /// Given a `WallShape` by `gen.shapeWalls`, joining its own kind.
    pub fn shaped(t: Tile) bool {
        return t == .wall or t == .shrub;
    }

    pub fn letter(t: Tile) u8 {
        return switch (t) {
            .wall => '#',
            .floor => '.',
            .grass => '"',
            .shrub => '&',
            .rock => '%',
            .dirt => ',',
            .sand => ':',
            .snow => '*',
            .water => '~',
            .shallows => '-',
            .bridge => '=',
            .reeds => '|',
            .rubble => ';',
            .fence => '+',
            .lava => '!',
            .fungus => 'T',
            .chasm => 'v',
            .ice => 'i',
            .grave => 't',
            .crop => 'w',
            .tiny_shrub => '\'',
            .boulder => 'o',
            .tall_grass => 'y',
            .shrooms => 'm',
        };
    }

    pub fn ofLetter(c: u8) ?Tile {
        for (std.enums.values(Tile)) |t| {
            if (t.letter() == c) return t;
        }
        return null;
    }
};

/// `BARREL_GROUND` with a barrel on it.
pub const BARREL_LETTER = '0';
pub const BARREL_GROUND: Tile = .floor;

pub fn groundOf(c: u8) ?Tile {
    return if (c == BARREL_LETTER) BARREL_GROUND else Tile.ofLetter(c);
}

comptime {
    @setEvalBranchQuota(100_000);
    std.debug.assert(Tile.ofLetter(BARREL_LETTER) == null);
    for (std.enums.values(Tile), 0..) |a, i| {
        std.debug.assert(std.ascii.isPrint(a.letter()) and a.letter() != ' ');
        for (std.enums.values(Tile)[0..i]) |b| std.debug.assert(a.letter() != b.letter());
    }
}

const Terrain = struct { solid: bool, blind: bool, ground: ?Tile = null, liquid: bool = false };
const OPEN = Terrain{ .solid = false, .blind = false };
const SHUT = Terrain{ .solid = true, .blind = true };
const MOAT = Terrain{ .solid = true, .blind = false };
const LIQUID = Terrain{ .solid = true, .blind = false, .liquid = true };
const DECOR = Terrain{ .solid = false, .blind = false, .ground = .grass };
const TALL_PROP = Terrain{ .solid = true, .blind = true, .ground = .grass };

const TERRAIN = std.EnumArray(Tile, Terrain).init(.{
    .wall = SHUT,
    .floor = OPEN,
    .grass = OPEN,
    .shrub = TALL_PROP,
    .rock = SHUT,
    .dirt = OPEN,
    .sand = OPEN,
    .snow = OPEN,
    .water = LIQUID,
    .shallows = OPEN,
    .bridge = OPEN,
    .reeds = .{ .solid = false, .blind = true },
    .rubble = OPEN,
    .fence = MOAT,
    .lava = LIQUID,
    .fungus = .{ .solid = true, .blind = true, .ground = .dirt },
    .chasm = LIQUID,
    .ice = OPEN,
    .grave = .{ .solid = true, .blind = false, .ground = .grass },
    .crop = .{ .solid = false, .blind = true },
    .tiny_shrub = DECOR,
    .boulder = TALL_PROP,
    .tall_grass = DECOR,
    .shrooms = DECOR,
});

/// Same-material neighbours, stamped by `gen.shapeWalls`; its bits are the wall sheets' masks.
pub const WallShape = packed struct(u8) {
    n: bool = false,
    e: bool = false,
    s: bool = false,
    w: bool = false,
    ne: bool = false,
    se: bool = false,
    sw: bool = false,
    nw: bool = false,

    /// A corner joins only where both sides beside it do, which leaves 47 shapes of the 256.
    pub fn joined(raw: WallShape) WallShape {
        var j = raw;
        j.ne = raw.ne and raw.n and raw.e;
        j.se = raw.se and raw.s and raw.e;
        j.sw = raw.sw and raw.s and raw.w;
        j.nw = raw.nw and raw.n and raw.w;
        return j;
    }

    pub fn mask(shape: WallShape) u8 {
        return @bitCast(shape);
    }

    /// No wall below it, so its brick face shows.
    pub fn faced(shape: WallShape) bool {
        return !shape.s;
    }

    pub fn solid(shape: WallShape) bool {
        return shape.mask() == 0xFF;
    }
};

pub const Torches = struct {
    at: [MAX_TORCHES]P = undefined,
    n: usize = 0,

    pub fn slice(self: *const Torches) []const P {
        return self.at[0..self.n];
    }

    fn find(self: *const Torches, p: P) ?usize {
        for (self.slice(), 0..) |t, i| {
            if (t.eq(p)) return i;
        }
        return null;
    }

    pub fn has(self: *const Torches, p: P) bool {
        return self.find(p) != null;
    }

    pub fn takes(self: *const Torches, p: P) bool {
        return self.n < MAX_TORCHES and self.find(p) == null;
    }

    pub fn add(self: *Torches, p: P) bool {
        if (!self.takes(p)) return false;
        self.at[self.n] = p;
        self.n += 1;
        return true;
    }

    pub fn remove(self: *Torches, p: P) bool {
        const i = self.find(p) orelse return false;
        self.n -= 1;
        self.at[i] = self.at[self.n];
        return true;
    }

    pub fn keep(self: *Torches, ctx: anytype, comptime fits: fn (@TypeOf(ctx), P) bool) void {
        var kept: usize = 0;
        for (self.slice()) |t| {
            if (!fits(ctx, t)) continue;
            self.at[kept] = t;
            kept += 1;
        }
        self.n = kept;
    }
};

pub const Level = struct {
    tile: [CELLS]Tile,
    /// Null on anything that is neither a wall nor a forest tile.
    shape: [CELLS]?WallShape,
    seen: [CELLS]bool,
    /// In the archer's sight: in its line of sight and light enough to see.
    lit: [CELLS]bool,
    /// In the archer's line of sight, light or dark.
    los: [CELLS]bool,
    /// 1-based into the actor pool; `NO_ONE` is empty.
    occupant: [CELLS]u16,
    barrel: [CELLS]bool,
    /// 1-based into the map's doors; `NO_DOOR` is none.
    door: [CELLS]u8,
    /// Caustic gas, Brogue's volume.
    gas: [CELLS]u16,
    torch: Torches,

    pub fn blank() Level {
        return .{
            .tile = [_]Tile{.wall} ** CELLS,
            .shape = [_]?WallShape{null} ** CELLS,
            .seen = [_]bool{false} ** CELLS,
            .lit = [_]bool{false} ** CELLS,
            .los = [_]bool{false} ** CELLS,
            .occupant = [_]u16{NO_ONE} ** CELLS,
            .barrel = [_]bool{false} ** CELLS,
            .door = [_]u8{NO_DOOR} ** CELLS,
            .gas = [_]u16{0} ** CELLS,
            .torch = .{},
        };
    }

    pub fn torches(self: *const Level) []const P {
        return self.torch.slice();
    }

    pub fn addTorch(self: *Level, p: P) void {
        _ = self.torch.add(p);
    }

    pub fn wallShape(self: *const Level, p: P) ?WallShape {
        if (self.at(p) != .wall) return null;
        return self.tileShape(p);
    }

    pub fn tileShape(self: *const Level, p: P) ?WallShape {
        return cellOr(?WallShape, &self.shape, p, null);
    }

    /// Its shape's mask, 0 for a cell with none.
    pub fn tileMask(self: *const Level, p: P) u8 {
        return (self.tileShape(p) orelse WallShape{}).mask();
    }

    pub fn inside(p: P) bool {
        return p.x >= 0 and p.y >= 0 and p.x < W and p.y < H;
    }

    pub fn clamp(p: P) P {
        return Box.inMap(0).clamp(p);
    }

    /// The nearest cell off the map's edge.
    pub fn inset(p: P) P {
        return Box.inMap(1).clamp(p);
    }

    /// Cells in from the nearest edge: 0 on the rim.
    pub fn edgeDist(p: P) i32 {
        return @min(@min(p.x, W - 1 - p.x), @min(p.y, H - 1 - p.y));
    }

    pub fn firstOpen(self: *const Level) ?P {
        for (&self.tile, 0..) |t, i| {
            if (!t.solid()) return of(i);
        }
        return null;
    }

    pub fn openCount(self: *const Level) usize {
        var n: usize = 0;
        for (self.tile) |t| n += @intFromBool(!t.solid());
        return n;
    }

    pub fn onRim(p: P) bool {
        return !inset(p).eq(p);
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

    pub fn doorAt(self: *const Level, p: P) ?usize {
        const d = cellOr(u8, &self.door, p, NO_DOOR);
        return if (d == NO_DOOR) null else d - 1;
    }

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

    /// Nothing stands up from it: open ground or a liquid, which gas drifts and a drop flies over.
    pub fn flat(self: *const Level, p: P) bool {
        return inside(p) and !self.at(p).upright();
    }

    pub fn addGas(self: *Level, p: P, volume: u16) void {
        if (!self.flat(p)) return;
        const i = idx(p);
        self.gas[i] +|= volume;
    }

    pub fn taken(self: *const Level, p: P) bool {
        return self.who(p) != NO_ONE or self.hasBarrel(p);
    }

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

    pub fn inLos(self: *const Level, p: P) bool {
        return cellOr(bool, &self.los, p, false);
    }

    pub fn isSeen(self: *const Level, p: P) bool {
        return cellOr(bool, &self.seen, p, false);
    }

    pub fn walkable(self: *const Level, p: P) bool {
        return inside(p) and !self.at(p).solid();
    }

    /// Terrain only.
    pub fn passOk(self: *const Level, from: P, d: mathx.Dir) bool {
        return self.walkable(from.add(d.delta()));
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

/// Of the cells `set.has` takes, the nearest `from`, the first of any tie.
pub fn nearest(from: P, set: anytype) ?P {
    const far: i32 = @intCast(@max(@abs(from.x), @abs(W - 1 - from.x), @abs(from.y), @abs(H - 1 - from.y)));
    var r: i32 = 0;
    while (r <= far) : (r += 1) {
        var ring = mathx.Ring.init(from, r);
        while (ring.next()) |q| {
            if (Level.inside(q) and set.has(Level.idx(q))) return q;
        }
    }
    return null;
}

/// Up to `N` cells.
pub fn Area(comptime N: usize) type {
    return struct {
        cells: [N]P = undefined,
        n: usize = 0,

        pub fn has(self: *const @This(), p: P) bool {
            for (self.cells[0..self.n]) |c| {
                if (c.eq(p)) return true;
            }
            return false;
        }
    };
}

pub const Box = struct {
    lo: P,
    hi: P,

    pub fn sized(lo: P, w: i32, h: i32) Box {
        return .{ .lo = lo, .hi = lo.add(.{ .x = w, .y = h }) };
    }

    /// The cells from `a` to `b`, both included, whichever corners they are.
    pub fn between(a: P, b: P) Box {
        return .{ .lo = a.min(b), .hi = a.max(b).add(.{ .x = 1, .y = 1 }) };
    }

    /// Every cell within `r` of `c`, on the map or off it.
    pub fn around(c: P, r: i32) Box {

        return .{ .lo = c.sub(.{ .x = r, .y = r }), .hi = c.add(.{ .x = r + 1, .y = r + 1 }) };
    }

    pub fn inMap(m: i32) Box {
        return .{ .lo = .{ .x = m, .y = m }, .hi = .{ .x = W - m, .y = H - m } };
    }

    pub fn centred(w: i32, h: i32) Box {
        return inMap(0).centredIn(w, h);
    }

    pub fn centredIn(outer: Box, w: i32, h: i32) Box {
        return sized(outer.lo.add(.{ .x = @divTrunc(outer.width() - w, 2), .y = @divTrunc(outer.height() - h, 2) }), w, h);
    }

    /// x is drawn before y.
    pub fn roll(b: Box, rng: *mathx.Rng) P {
        return b.rollFor(rng, 1, 1);
    }

    /// The corner of a `w` by `h` box that lies inside this one; x is drawn before y.
    pub fn rollFor(b: Box, rng: *mathx.Rng, w: i32, h: i32) P {
        const x = rng.range(b.lo.x, b.hi.x - w);
        return .{ .x = x, .y = rng.range(b.lo.y, b.hi.y - h) };
    }

    pub fn width(b: Box) i32 {
        return b.hi.x - b.lo.x;
    }

    pub fn height(b: Box) i32 {
        return b.hi.y - b.lo.y;
    }

    pub fn centre(b: Box) P {
        return b.lo.add(.{ .x = @divTrunc(b.width(), 2), .y = @divTrunc(b.height(), 2) });
    }

    pub fn holds(b: Box, p: P) bool {
        return p.x >= b.lo.x and p.x < b.hi.x and p.y >= b.lo.y and p.y < b.hi.y;
    }

    pub fn cells(b: Box) Cells {
        return Cells.of(b.lo, b.hi);
    }

    pub fn inner(b: Box) Box {
        return b.shrunk(1);
    }

    pub fn shrunk(b: Box, by: i32) Box {
        return .{ .lo = b.lo.add(.{ .x = by, .y = by }), .hi = b.hi.sub(.{ .x = by, .y = by }) };
    }

    pub fn grown(b: Box, by: i32) Box {
        return .{
            .lo = .{ .x = @max(0, b.lo.x - by), .y = @max(0, b.lo.y - by) },
            .hi = .{ .x = @min(W, b.hi.x + by), .y = @min(H, b.hi.y + by) },
        };
    }

    pub fn overlaps(b: Box, o: Box, pad: i32) bool {
        return b.lo.x - pad < o.hi.x and b.hi.x + pad > o.lo.x and b.lo.y - pad < o.hi.y and b.hi.y + pad > o.lo.y;
    }

    pub fn onEdge(b: Box, p: P) bool {
        return b.holds(p) and (p.x == b.lo.x or p.y == b.lo.y or p.x == b.hi.x - 1 or p.y == b.hi.y - 1);
    }

    /// Its cell nearest `p`.
    pub fn clamp(b: Box, p: P) P {
        return .{ .x = std.math.clamp(p.x, b.lo.x, b.hi.x - 1), .y = std.math.clamp(p.y, b.lo.y, b.hi.y - 1) };
    }
};

/// `hi` exclusive, row by row.
pub const Cells = struct {
    lo: P,
    hi: P,
    at: P,

    pub fn of(lo: P, hi: P) Cells {
        return .{ .lo = lo, .hi = hi, .at = if (lo.x < hi.x) lo else .{ .x = lo.x, .y = hi.y } };
    }

    pub fn span(r: i32) i32 {
        return r * 2 + 1;
    }

    pub fn around(c: P, r: i32) Cells {
        return Box.around(c, r).cells();
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

/// `dist` fills as it goes.
pub const Flood = struct {
    lv: *const Level,
    dist: *[CELLS]i32,
    queue: *[CELLS]u32,
    head: usize = 0,
    tail: usize = 0,

    pub fn init(lv: *const Level, from: P, dist: *[CELLS]i32, queue: *[CELLS]u32) Flood {
        @memset(dist, -1);
        var f = Flood{ .lv = lv, .dist = dist, .queue = queue };
        f.seed(from);
        return f;
    }

    /// Another cell the flood starts from, unless it already reached it.
    pub fn seed(self: *Flood, from: P) void {
        const s = Level.idx(from);
        if (self.dist[s] >= 0) return;
        self.dist[s] = 0;
        self.queue[self.tail] = @intCast(s);
        self.tail += 1;
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

/// The target's own cell may be opaque.
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

test "tight diagonals ignore both side cells but still require an open destination" {
    const from = P{ .x = 10, .y = 10 };
    for ([_]mathx.Dir{ .ne, .se, .sw, .nw }) |d| {
        var lv = openFloor();
        const to = from.add(d.delta());
        lv.set(.{ .x = to.x, .y = from.y }, .wall);
        try std.testing.expect(lv.stepOk(from, d, NO_ONE));
        lv.set(.{ .x = from.x, .y = to.y }, .wall);
        try std.testing.expect(lv.stepOk(from, d, NO_ONE));
        try std.testing.expect(lv.stepOk(to, d.opposite(), NO_ONE));
        lv.set(to, .wall);
        try std.testing.expect(!lv.stepOk(from, d, NO_ONE));
        lv.set(to, .floor);
        lv.putBarrel(to);
        try std.testing.expect(!lv.stepOk(from, d, NO_ONE));
        _ = lv.breakBarrel(to);
        lv.stand(to, 7);
        try std.testing.expect(!lv.stepOk(from, d, NO_ONE));
    }
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
