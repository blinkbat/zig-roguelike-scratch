const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");

const P = mathx.P;

/// Of its 3x3, at least this many solid turns a cell solid on a smoothing pass, the cave rule's.
const CROWD: usize = 5;
/// A pocket of open ground this small, holding no door and by no liquid, is filled; a bigger one gets a trail.
const POCKET: usize = 16;
const JOIN_PASSES: usize = 160;
const NONE = std.math.maxInt(u16);
const NO_CELL = std.math.maxInt(u32);
/// A river's turn a step, at most, in radians.
const MEANDER: f32 = 0.55;
const RIVER_STEPS: usize = 4 * (grid.W + grid.H);

/// Smooth value noise in 0..1, summed over octaves; a seed is a field.
pub const Noise = struct {
    seed: u64,

    pub fn init(seed: u64) Noise {
        return .{ .seed = seed };
    }

    fn lattice(self: Noise, x: i32, y: i32) f32 {
        var h = self.seed ^ (@as(u64, @bitCast(@as(i64, x))) *% 0x9E3779B97F4A7C15) ^ (@as(u64, @bitCast(@as(i64, y))) *% 0xC2B2AE3D27D4EB4F);
        h ^= h >> 31;
        h *%= 0xBF58476D1CE4E5B9;
        h ^= h >> 29;
        return @as(f32, @floatFromInt(h >> 40)) / @as(f32, @floatFromInt(@as(u64, 1) << 24));
    }

    fn value(self: Noise, x: f32, y: f32) f32 {
        return mathx.valueNoise(self, lattice, x, y);
    }

    /// `scale` is its features' size in cells.
    pub fn at(self: Noise, p: P, scale: f32, octaves: u32) f32 {
        var sum: f32 = 0;
        var weight: f32 = 0;
        var amp: f32 = 1;
        var freq: f32 = 1 / scale;
        for (0..octaves) |o| {
            const shift: f32 = @floatFromInt(o * 17);
            sum += amp * self.value(@as(f32, @floatFromInt(p.x)) * freq + shift, @as(f32, @floatFromInt(p.y)) * freq - shift);
            weight += amp;
            amp *= 0.5;
            freq *= 2;
        }
        return sum / weight;
    }
};

pub fn fill(lv: *grid.Level, t: grid.Tile) void {
    lv.tile = [_]grid.Tile{t} ** grid.CELLS;
}

pub fn rim(lv: *grid.Level, t: grid.Tile) void {
    for (0..grid.CELLS) |i| {
        if (grid.Level.onRim(grid.Level.of(i))) lv.tile[i] = t;
    }
}

pub fn sow(lv: *grid.Level, rng: *mathx.Rng, pc: u32, solid: grid.Tile, open: grid.Tile) void {
    for (0..grid.CELLS) |i| {
        lv.tile[i] = if (grid.Level.onRim(grid.Level.of(i)) or rng.percent(pc)) solid else open;
    }
}

pub const SMOOTH_MAX: u8 = 8;

/// `sown` percent solid, smoothed `passes` times, then `strays` a thousand lone solids over the open.
pub fn cellular(lv: *grid.Level, rng: *mathx.Rng, sown: u32, passes: u32, strays: u32, pal: Palette) void {
    sow(lv, rng, sown, pal.solid, pal.open);
    smooth(lv, passes, pal.solid, pal.open);
    scatter(lv, rng, strays, .{ .tile = pal.open }, pal.solid, true);
}

/// The cave rule, `passes` times: off the map counts as solid; any other tile is left, and counts as open.
pub fn smooth(lv: *grid.Level, passes: u32, solid: grid.Tile, open: grid.Tile) void {
    var next: [grid.CELLS]grid.Tile = undefined;
    for (0..passes) |_| {
        for (0..grid.CELLS) |i| {
            const t = lv.tile[i];
            const p = grid.Level.of(i);
            next[i] = if (t != solid and t != open) t else if (grid.Level.onRim(p) or crowded(lv, p, solid)) solid else open;
        }
        lv.tile = next;
    }
}

fn crowded(lv: *const grid.Level, p: P, solid: grid.Tile) bool {
    var n: usize = 0;
    var cells = grid.Cells.around(p, 1);
    while (cells.next()) |q| {
        if (!grid.Level.inside(q) or lv.at(q) == solid) n += 1;
    }
    return n >= CROWD;
}

/// Open all round, so something solid here closes no way.
pub fn clearAround(lv: *const grid.Level, p: P) bool {
    for (mathx.ALL_DIRS) |d| {
        if (!lv.walkable(p.add(d.delta()))) return false;
    }
    return true;
}

/// What a scatter lays over: `tile`, and if `decked` the decor standing on it too.
pub const Over = struct {
    tile: grid.Tile,
    decked: bool = false,

    fn has(o: Over, t: grid.Tile) bool {
        return t == o.tile or (o.decked and !t.solid() and t.ground() == o.tile);
    }
};

/// `lone` puts it only where it closes no way.
pub fn scatter(lv: *grid.Level, rng: *mathx.Rng, per_mille: u32, on: Over, put: grid.Tile, lone: bool) void {
    for (0..grid.CELLS) |i| {
        if (!on.has(lv.tile[i])) continue;
        const p = grid.Level.of(i);
        if (grid.Level.onRim(p) or (lone and !clearAround(lv, p))) continue;
        if (rng.perMille(per_mille)) lv.tile[i] = put;
    }
}

/// Only over the tiles `over` allows.
pub fn disc(lv: *grid.Level, c: P, r: f32, t: grid.Tile, comptime over: ?fn (grid.Tile) bool) void {
    discOf(lv, c, r, t, false, over);
}

/// `disc`, the rim too, so a river runs off the map.
fn discAll(lv: *grid.Level, c: P, r: f32, t: grid.Tile) void {
    discOf(lv, c, r, t, true, null);
}

fn discOf(lv: *grid.Level, c: P, r: f32, t: grid.Tile, comptime with_rim: bool, comptime over: ?fn (grid.Tile) bool) void {
    const k: i32 = @intFromFloat(@ceil(r));
    var cells = grid.Cells.around(c, k);
    while (cells.next()) |q| {
        if (!with_rim and grid.Level.onRim(q)) continue;
        const dx: f32 = @floatFromInt(q.x - c.x);
        const dy: f32 = @floatFromInt(q.y - c.y);
        if (dx * dx + dy * dy > r * r + 0.25) continue;
        if (over) |ok| {
            if (!ok(lv.at(q))) continue;
        }
        lv.set(q, t);
    }
}

/// `t` round `c` off the rim, its edge frayed: in where a cell's distance over `r` is under `lo + span` times the noise.
pub fn blob(lv: *grid.Level, noise: Noise, c: P, r: f32, scale: f32, lo: f32, span: f32, t: grid.Tile) void {
    var cells = grid.Cells.around(c, @intFromFloat(@ceil(r * @max(lo, lo + span))));
    while (cells.next()) |q| {
        if (grid.Level.onRim(q)) continue;
        if (mathx.distEuclid(q, c) / r < lo + span * noise.at(q, scale, 2)) lv.set(q, t);
    }
}

pub fn field(lv: *grid.Level, pal: Palette) void {
    fill(lv, pal.open);
    rim(lv, pal.solid);
}

pub fn box(lv: *grid.Level, lo: P, hi: P, t: grid.Tile) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |q| lv.set(q, t);
}

/// The cell inside an edge door is opened too.
pub fn openDoors(lv: *grid.Level, doors: []const P, ground: grid.Tile) void {
    for (doors, 0..) |d, k| {
        lv.putDoor(d, k);
        const i = grid.Level.idx(d);
        lv.tile[i] = ground;
        const in = grid.Level.inset(d);
        if (lv.at(in).solid()) lv.set(in, ground);
    }
}

/// No open ground on the map's edge but its doors: a step there would walk off.
pub fn seal(lv: *grid.Level, t: grid.Tile) void {
    for (0..grid.CELLS) |i| {
        if (grid.Level.onRim(grid.Level.of(i)) and !lv.tile[i].solid() and lv.door[i] == grid.NO_DOOR) lv.tile[i] = t;
    }
}

/// A base's own ground, which its features and the finishing passes draw from.
pub const Palette = struct {
    open: grid.Tile,
    solid: grid.Tile,
    /// What a trail lays.
    path: grid.Tile,
    /// What fills a small doorless pocket; null gives every pocket a trail.
    pocket: ?grid.Tile = null,

    pub const BUILT = Palette{ .open = .floor, .solid = .wall, .path = .floor };
    pub const CAVE = Palette{ .open = .dirt, .solid = .rock, .path = .dirt };
    pub const WILD = Palette{ .open = .grass, .solid = .shrub, .path = .grass };
};

/// Every stretch of open ground joined to the biggest by a bending trail that bridges water, lava and chasms.
pub fn connect(lv: *grid.Level, rng: *mathx.Rng, pal: Palette) void {
    var st: Stretches = .{};
    const region = &st.region;
    const size = &st.size;
    for (0..JOIN_PASSES) |_| {
        const n = st.label(lv);
        if (n <= 1) return;
        const main = st.biggest();
        const kept = if (pal.pocket != null) keptIn(lv, region) else Regions.initEmpty();
        var first: [grid.CELLS]u32 = undefined;
        @memset(first[0..n], NO_CELL);
        for (0..grid.CELLS) |i| {
            const r = region[i];
            if (r == NONE or r == main) continue;
            if (pal.pocket) |fill_with| {
                if (size[r] < POCKET and !kept.isSet(r)) {
                    lv.tile[i] = fill_with;
                    continue;
                }
            }
            if (first[r] == NO_CELL) first[r] = @intCast(i);
        }
        for (first[0..n]) |orphan| {
            if (orphan == NO_CELL) continue;
            const from = grid.Level.inset(grid.Level.of(orphan));
            const to = grid.nearest(from, InStretch{ .st = &st, .r = main }) orelse return;
            trail(lv, rng, from, to, pal.path);
        }
    }
}

/// Each open cell's stretch of ground, as a step walks it.
pub const Stretches = struct {
    region: [grid.CELLS]u16 = undefined,
    size: [grid.CELLS]u32 = undefined,
    queue: [grid.CELLS]u32 = undefined,
    n: usize = 0,

    pub fn label(s: *Stretches, lv: *const grid.Level) usize {
        return s.labelBy(lv, false);
    }

    /// The first of any tie.
    pub fn biggest(s: *const Stretches) u16 {
        var main: u16 = 0;
        for (s.size[1..s.n], 1..) |n, r| {
            if (n > s.size[main]) main = @intCast(r);
        }
        return main;
    }

    pub fn of(s: *const Stretches, p: P) u16 {
        const i = grid.Level.idx(p);
        return s.region[i];
    }

    fn labelBy(s: *Stretches, lv: *const grid.Level, comptime barred: bool) usize {
        @memset(&s.region, NONE);
        var n: u16 = 0;
        for (0..grid.CELLS) |c| {
            if (s.region[c] != NONE or lv.tile[c].solid() or (barred and lv.barrel[c])) continue;
            s.region[c] = n;
            s.queue[0] = @intCast(c);
            var head: usize = 0;
            var tail: usize = 1;
            while (head < tail) : (head += 1) {
                const here = grid.Level.of(s.queue[head]);
                for (mathx.ALL_DIRS) |d| {
                    if (!lv.passOk(here, d)) continue;
                    const k = grid.Level.idx(here.add(d.delta()));
                    if (s.region[k] != NONE or (barred and lv.barrel[k])) continue;
                    s.region[k] = n;
                    s.queue[tail] = @intCast(k);
                    tail += 1;
                }
            }
            s.size[n] = @intCast(tail);
            n += 1;
        }
        s.n = n;
        return n;
    }
};

const InStretch = struct {
    st: *const Stretches,
    r: u16,

    pub fn has(s: InStretch, i: usize) bool {
        return s.st.region[i] == s.r;
    }
};

/// Barrels taken away, one a pass, each beside ground they cut off from the biggest stretch, till none does.
pub fn unbar(lv: *grid.Level) void {
    var st: Stretches = .{};
    const region = &st.region;
    while (true) {
        const n = st.labelBy(lv, true);
        if (n <= 1) return;
        const main = st.biggest();
        const cut = for (0..grid.CELLS) |i| {
            if (!lv.barrel[i]) continue;
            const p = grid.Level.of(i);
            for (mathx.ALL_DIRS) |d| {
                if (!lv.passOk(p, d)) continue;
                const k = grid.Level.idx(p.add(d.delta()));
                if (region[k] != NONE and region[k] != main) break;
            } else continue;
            break i;
        } else return;
        lv.barrel[cut] = false;
    }
}

/// The stretches no pocket fill takes: one holding a door, or one by a liquid, as an island is.
fn keptIn(lv: *const grid.Level, region: *const [grid.CELLS]u16) Regions {
    var out = Regions.initEmpty();
    for (0..grid.CELLS) |i| {
        if (region[i] == NONE) continue;
        if (lv.door[i] != grid.NO_DOOR or byLiquid(lv, grid.Level.of(i))) out.set(region[i]);
    }
    return out;
}

fn byLiquid(lv: *const grid.Level, p: P) bool {
    for (mathx.ALL_DIRS) |d| {
        const q = p.add(d.delta());
        if (grid.Level.inside(q) and lv.at(q).liquid()) return true;
    }
    return false;
}

const Regions = std.StaticBitSet(grid.CELLS);

/// Side steps from `a` to `b` picked at random, never leaving their box; solid becomes `path`, a liquid a bridge.
pub fn trail(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, path: grid.Tile) void {
    var p = a;
    lay(lv, p, path);
    while (!p.eq(b)) {
        const dx = b.x - p.x;
        const dy = b.y - p.y;
        const across = dy == 0 or (dx != 0 and rng.below(@abs(dx) + @abs(dy)) < @abs(dx));
        if (across) p.x += std.math.sign(dx) else p.y += std.math.sign(dy);
        lay(lv, p, path);
    }
}

fn lay(lv: *grid.Level, p: P, path: grid.Tile) void {
    const t = lv.at(p);
    if (t.solid()) lv.set(p, paved(t, path));
}

/// What a way laid over `t` leaves: a bridge over a liquid or a bridge, else `put`.
pub fn paved(t: grid.Tile, put: grid.Tile) grid.Tile {
    return if (t.liquid() or t == .bridge) .bridge else put;
}

/// A course from `a` that bends at random but always comes round to `b`; `wander` 0 runs straight.
pub const Meander = struct {
    x: f32,
    y: f32,
    tx: f32,
    ty: f32,
    bend: f32 = 0,
    wander: f32,
    steps: usize = 0,
    done: bool = false,

    pub fn init(a: P, b: P, wander: f32) Meander {
        return .{ .x = @floatFromInt(a.x), .y = @floatFromInt(a.y), .tx = @floatFromInt(b.x), .ty = @floatFromInt(b.y), .wander = wander };
    }

    pub fn next(self: *Meander, rng: *mathx.Rng) ?P {
        if (self.done) return null;
        const c = P{ .x = @intFromFloat(@round(self.x)), .y = @intFromFloat(@round(self.y)) };
        const dx = self.tx - self.x;
        const dy = self.ty - self.y;
        self.steps += 1;
        if (dx * dx + dy * dy < 1 or self.steps >= RIVER_STEPS) {
            self.done = true;
            return c;
        }
        self.bend = std.math.clamp(self.bend + (rng.unit() - 0.5) * MEANDER * self.wander, -1.1 * self.wander, 1.1 * self.wander);
        const h = std.math.atan2(dy, dx) + self.bend;
        self.x += @cos(h);
        self.y += @sin(h);
        return c;
    }
};

/// The cells a river's middle steps through, off the rim, to cross it at.
pub const Bed = struct {
    cell: [RIVER_STEPS]P = undefined,
    n: usize = 0,

    fn add(self: *Bed, c: P) void {
        if (self.n == RIVER_STEPS or grid.Level.onRim(c)) return;
        self.cell[self.n] = c;
        self.n += 1;
    }
};

/// From edge to edge: `fill_with` `width` across, `bank` a cell either side over whatever is not liquid.
pub fn river(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, width: f32, fill_with: grid.Tile, bank: ?grid.Tile, bed: ?*Bed) void {
    var m = Meander.init(a, b, 1);
    while (m.next(rng)) |c| {
        if (bed) |k| k.add(c);
        if (bank) |bk| disc(lv, c, bankReach(width), bk, notLiquid);
        discAll(lv, c, width / 2, fill_with);
    }
}

pub fn bankReach(width: f32) f32 {
    return width / 2 + 1;
}

fn notLiquid(t: grid.Tile) bool {
    return !t.liquid();
}

fn edge(rng: *mathx.Rng, side: mathx.Dir) P {
    return switch (side) {
        .w => .{ .x = 0, .y = middleHalf(rng, grid.H) },
        .e => .{ .x = grid.W - 1, .y = middleHalf(rng, grid.H) },
        .n => .{ .x = middleHalf(rng, grid.W), .y = 0 },
        .s => .{ .x = middleHalf(rng, grid.W), .y = grid.H - 1 },
        .ne, .se, .sw, .nw => unreachable,
    };
}

fn middleHalf(rng: *mathx.Rng, span: i32) i32 {
    return rng.range(@divTrunc(span, 4), @divTrunc(span * 3, 4));
}

/// West and east, then north and south.
const EDGES = [_]mathx.Dir{ .w, .e, .n, .s };

pub const Course = enum {
    across,
    down,
    any,

    pub fn ends(c: Course, rng: *mathx.Rng) [2]P {
        const side = switch (c) {
            .across => EDGES[rng.below(2)],
            .down => EDGES[2 + rng.below(2)],
            .any => EDGES[rng.below(EDGES.len)],
        };
        return .{ edge(rng, side), edge(rng, side.opposite()) };
    }
};

pub const LITTER_MAX: u16 = 100;

pub const Litter = struct {
    /// Per thousand cells of open grass.
    boulders: u16 = 4,

    pub fn fit(l: Litter) Litter {
        var q = l;
        q.boulders = @min(l.boulders, LITTER_MAX);
        return q;
    }

    pub fn strew(l: Litter, lv: *grid.Level, rng: *mathx.Rng) void {
        strewn(lv, rng, l.boulders, .boulder);
    }
};

const DECOR_MAX: u16 = 300;
const TALL_GRASS_SCALE: f32 = 5;

pub const Decor = struct {
    /// Per thousand cells of open grass.
    tiny_shrubs: u16 = 12,
    tall_grass: u16 = 60,
    shrooms: u16 = 6,

    pub fn fit(d: Decor) Decor {
        var q = d;
        q.tiny_shrubs = @min(d.tiny_shrubs, DECOR_MAX);
        q.tall_grass = @min(d.tall_grass, DECOR_MAX);
        q.shrooms = @min(d.shrooms, DECOR_MAX);
        return q;
    }

    pub fn strew(d: Decor, lv: *grid.Level, rng: *mathx.Rng, seed: u64) void {
        strewn(lv, rng, d.tiny_shrubs, .tiny_shrub);
        clumps(lv, Noise.init(seed ^ 0x7A11), TALL_GRASS_SCALE, d.tall_grass, .{ .tile = grid.Tile.tall_grass.ground().? }, .tall_grass);
        strewn(lv, rng, d.shrooms, .shrooms);
    }
};

/// Litter, then decor, for a base whose `Params` has them.
pub fn dress(p: anytype, lv: *grid.Level, rng: *mathx.Rng, seed: u64) void {
    if (@hasField(@TypeOf(p), "litter")) p.litter.strew(lv, rng);
    if (@hasField(@TypeOf(p), "decor")) p.decor.strew(lv, rng, seed);
}

fn strewn(lv: *grid.Level, rng: *mathx.Rng, per_mille: u32, put: grid.Tile) void {
    scatter(lv, rng, per_mille, .{ .tile = put.ground().? }, put, put.solid());
}

/// The tile an enum of tiles names.
pub fn tileOf(e: anytype) grid.Tile {
    return switch (e) {
        inline else => |t| @field(grid.Tile, @tagName(t)),
    };
}

pub const Ground = enum {
    grass,
    dirt,
    sand,
    snow,
    ice,
    floor,
    rubble,
    shallows,

    pub fn tile(g: Ground) grid.Tile {
        return tileOf(g);
    }
};

pub const Solid = enum {
    shrub,
    rock,
    wall,
    water,
    chasm,
    lava,
    fence,

    pub fn tile(s: Solid) grid.Tile {
        return tileOf(s);
    }
};

pub const Bank = enum {
    none,
    shallows,
    sand,
    dirt,
    grass,
    reeds,
    rock,

    pub fn tile(b: Bank) ?grid.Tile {
        return switch (b) {
            .none => null,
            inline else => |t| @field(grid.Tile, @tagName(t)),
        };
    }
};

/// `put` on the `per_mille` of `on` cells whose noise is highest, so it lies in clumps `scale` cells across.
pub fn clumps(lv: *grid.Level, noise: Noise, scale: f32, per_mille: u32, on: Over, put: grid.Tile) void {
    const BUCKETS = 256;
    var hist = [_]u32{0} ** BUCKETS;
    var n: u32 = 0;
    for (0..grid.CELLS) |i| {
        if (!on.has(lv.tile[i]) or grid.Level.onRim(grid.Level.of(i))) continue;
        hist[bucket(noise.at(grid.Level.of(i), scale, 3), BUCKETS)] += 1;
        n += 1;
    }
    const want = n * @min(per_mille, mathx.MILLE) / mathx.MILLE;
    var cut: usize = BUCKETS;
    var taken: u32 = 0;
    while (cut > 0 and taken + hist[cut - 1] <= want) : (cut -= 1) taken += hist[cut - 1];
    for (0..grid.CELLS) |i| {
        if (!on.has(lv.tile[i]) or grid.Level.onRim(grid.Level.of(i))) continue;
        if (bucket(noise.at(grid.Level.of(i), scale, 3), BUCKETS) >= cut) lv.tile[i] = put;
    }
}

fn bucket(v: f32, n: usize) usize {
    return @min(n - 1, @as(usize, @intFromFloat(@max(0, v) * @as(f32, @floatFromInt(n)))));
}

pub fn count(lv: *const grid.Level, t: grid.Tile) usize {
    var n: usize = 0;
    for (lv.tile) |c| {
        if (c == t) n += 1;
    }
    return n;
}

test "noise is smooth, in range, and a seed is a field" {
    const a = Noise.init(7);
    const b = Noise.init(7);
    var lo: f32 = 1;
    var hi: f32 = 0;
    var jump: f32 = 0;
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        const v = a.at(p, 12, 3);
        try std.testing.expectEqual(v, b.at(p, 12, 3));
        lo = @min(lo, v);
        hi = @max(hi, v);
        jump = @max(jump, @abs(v - a.at(p.add(.{ .x = 1, .y = 0 }), 12, 3)));
    }
    std.debug.print("noise at 12 cells, 3 octaves: {d:.2} to {d:.2}, the most one cell steps it {d:.3}\n", .{ lo, hi, jump });
    try std.testing.expect(lo >= 0 and hi <= 1 and hi - lo > 0.5 and jump < 0.2);
}

test "a small island is bridged, not filled as a pocket" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x15E);
    var pal = Palette.WILD;
    pal.pocket = pal.solid;
    field(&lv, pal);
    disc(&lv, grid.MIDDLE, 4, .water, null);
    disc(&lv, grid.MIDDLE, 1, .grass, null);
    connect(&lv, &rng, pal);
    std.debug.print("a five-cell island in a pocket-filling base: {d} bridge cells after joining\n", .{count(&lv, .bridge)});
    try std.testing.expect(lv.walkable(grid.MIDDLE));
    try std.testing.expect(count(&lv, .bridge) > 0);
}

test "a river runs edge to edge and parts the ground, and a join bridges it" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x21E);
    field(&lv, Palette.WILD);
    river(&lv, &rng, .{ .x = 0, .y = 32 }, .{ .x = grid.W - 1, .y = 30 }, 3, .water, .shallows, null);
    var st: Stretches = .{};
    const parted = st.label(&lv);
    connect(&lv, &rng, .{ .open = .grass, .solid = .shrub, .path = .dirt });
    const joined = st.label(&lv);
    std.debug.print("a river: {d} water cells, the ground in {d} parts, {d} after joining by {d} bridge cells\n", .{ count(&lv, .water), parted, joined, count(&lv, .bridge) });
    try std.testing.expect(parted >= 2);
    try std.testing.expectEqual(@as(usize, 1), joined);
    try std.testing.expect(count(&lv, .bridge) > 0);
}
