const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");

const P = mathx.P;

/// Of its 3x3, at least this many solid turns a cell solid on a smoothing pass, the cave rule's.
const CROWD: usize = 5;
/// A pocket of open ground this small, unless `keptIn` keeps it, is filled; a bigger one gets a trail.
const POCKET: usize = 16;
const JOIN_PASSES: usize = 160;
const NONE = std.math.maxInt(u16);
const NO_CELL = std.math.maxInt(u32);
/// A meander's bend changes by up to half this a step, in radians, at full wander.
const MEANDER: f32 = 0.55;
/// The most a meander's bend runs off its heading, in radians, at full wander.
const BEND_MAX: f32 = 1.1;
const MEANDER_STEPS: usize = 4 * (grid.W + grid.H);

/// Each noise field's and RNG stream's own, so no two of one seed move together.
pub const Salt = enum(u64) {
    /// Also the stride between features' seeds.
    features = 0xFEA7_0BE5,
    branches = 0xB2A6_C4E5,
    tall_grass = 0x7A11,
    border = 0xB02D,
    cavern = 0xCA4E,
    coast = 0xC0A5,
    lake = 0x1A4E,
    scatter = 0x5CA7,
    dune_crest = 0xD0E5,
    dune_break = 0xB20C,
    topology = 0x70B0,
    maze = 0x3A2E,
    elevation = 0x4E16,
    rainfall = 0x2A1F,
    drainage = 0xD2A1,
    warmth = 0x4EA7,
    grain = 0xF1E1,

    pub fn of(salt: Salt, seed: u64) u64 {
        return seed ^ @intFromEnum(salt);
    }

    pub fn rng(salt: Salt, seed: u64) mathx.Rng {
        return mathx.Rng.init(salt.of(seed));
    }
};

/// Smooth value noise in 0..1, summed over octaves; a seed is a field.
pub const Noise = struct {
    seed: u64,

    pub fn init(seed: u64, salt: Salt) Noise {
        return .{ .seed = salt.of(seed) };
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
        if (rimAt(i)) lv.tile[i] = t;
    }
}

fn sow(lv: *grid.Level, rng: *mathx.Rng, pc: u32, solid: grid.Tile, open: grid.Tile) void {
    for (0..grid.CELLS) |i| {
        lv.tile[i] = if (rimAt(i) or rng.percent(pc)) solid else open;
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
    water_range: u8 = 0,

    fn has(o: Over, t: grid.Tile) bool {
        return t == o.tile or (o.decked and !t.solid() and t.ground() == o.tile);
    }

    fn at(o: Over, lv: *const grid.Level, p: P) bool {
        return o.has(lv.at(p)) and (o.water_range == 0 or nearWater(lv, p, o.water_range));
    }
};

pub fn nearWater(lv: *const grid.Level, p: P, range: u8) bool {
    return near(lv, p, range, grid.Tile.wet);
}

/// Any cell within `r` of `p`, `p` included, whose tile `has`.
fn near(lv: *const grid.Level, p: P, r: i32, comptime has: fn (grid.Tile) bool) bool {
    var cells = grid.Cells.around(p, r);
    while (cells.next()) |q| {
        if (grid.Level.inside(q) and has(lv.at(q))) return true;
    }
    return false;
}

/// `lone` puts it only where it closes no way.
pub fn scatter(lv: *grid.Level, rng: *mathx.Rng, per_mille: u32, on: Over, put: grid.Tile, lone: bool) void {
    var over = std.StaticBitSet(grid.CELLS).initEmpty();
    for (0..grid.CELLS) |i| over.setValue(i, on.at(lv, grid.Level.of(i)));
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        if (!over.isSet(i)) continue;
        if (grid.Level.onRim(p) or (lone and !clearAround(lv, p))) continue;
        if (rng.perMille(per_mille)) lv.tile[i] = put;
    }
}

pub fn disc(lv: *grid.Level, c: P, r: f32, t: grid.Tile, comptime over: ?fn (grid.Tile) bool) void {
    discOf(lv, c, r, t, false, false, over);
}

fn discAll(lv: *grid.Level, c: P, r: f32, t: grid.Tile) void {
    discOf(lv, c, r, t, true, false, null);
}

pub const LANE_MIN: u8 = 2;

pub const Lane = enum {
    /// Off the rim, over whatever is there.
    cut,
    /// To the rim, bridging a liquid.
    road,
};

pub fn lane(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, width: u8, wander: f32, t: grid.Tile, comptime how: Lane) void {
    std.debug.assert(width >= LANE_MIN);
    const r = @as(f32, @floatFromInt(width - 1)) / 2 + 0.5;
    var m = Meander.init(a, b, wander);
    while (m.next(rng)) |c| discOf(lv, c, r, t, how == .road, how == .road, null);
}

/// Within `r` of `c`, as `disc` lays it.
pub fn inDisc(c: P, q: P, r: f32) bool {
    const dx: f32 = @floatFromInt(q.x - c.x);
    const dy: f32 = @floatFromInt(q.y - c.y);
    return dx * dx + dy * dy <= r * r + 0.25;
}

fn discOf(lv: *grid.Level, c: P, r: f32, t: grid.Tile, comptime with_rim: bool, comptime pave: bool, comptime over: ?fn (grid.Tile) bool) void {
    const k: i32 = @intFromFloat(@ceil(r));
    var cells = grid.Cells.around(c, k);
    while (cells.next()) |q| {
        if (!with_rim and grid.Level.onRim(q)) continue;
        if (!inDisc(c, q, r)) continue;
        if (over) |ok| {
            if (!ok(lv.at(q))) continue;
        }
        lv.set(q, if (pave) paved(lv.at(q), t) else t);
    }
}

pub const CAVE_SCALE: f32 = 3;

/// `t` round `c` off the rim, its edge frayed: in where a cell's distance over `r` is under `lo + span` times the noise.
pub fn blob(lv: *grid.Level, noise: Noise, c: P, r: f32, scale: f32, lo: f32, span: f32, t: grid.Tile) void {
    blobIn(lv, noise, c, r, scale, lo, span, t, grid.Box.around(c, @intFromFloat(@ceil(r * @max(lo, lo + span)))));
}

pub fn blobIn(lv: *grid.Level, noise: Noise, c: P, r: f32, scale: f32, lo: f32, span: f32, t: grid.Tile, within: grid.Box) void {
    var cells = within.cells();
    while (cells.next()) |q| {
        if (grid.Level.onRim(q)) continue;
        if (mathx.distEuclid(q, c) / r < lo + span * noise.at(q, scale, 2)) lv.set(q, t);
    }
}

pub fn field(lv: *grid.Level, pal: Palette) void {
    fill(lv, pal.open);
    rim(lv, pal.solid);
}

fn rimAt(i: usize) bool {
    return grid.Level.onRim(grid.Level.of(i));
}

pub fn box(lv: *grid.Level, b: grid.Box, t: grid.Tile) void {
    var cells = b.cells();
    while (cells.next()) |q| lv.set(q, t);
}

/// `box`'s edge alone.
pub fn outline(lv: *grid.Level, b: grid.Box, t: grid.Tile) void {
    var cells = b.cells();
    while (cells.next()) |q| {
        if (b.onEdge(q)) lv.set(q, t);
    }
}

/// Top left, top right, bottom left, bottom right.
pub fn corners(b: grid.Box) [4]P {
    return .{ b.lo, .{ .x = b.hi.x - 1, .y = b.lo.y }, .{ .x = b.lo.x, .y = b.hi.y - 1 }, b.hi.sub(.{ .x = 1, .y = 1 }) };
}

/// `p`'s part along `side`: its x on the north and south, its y on the west and east.
pub fn alongOf(side: mathx.Dir, p: P) i32 {
    return switch (side) {
        .n, .s => p.x,
        .w, .e => p.y,
        .ne, .se, .sw, .nw => unreachable,
    };
}

/// Cells `p` lies in from the map's edge on `side`.
pub fn inFrom(side: mathx.Dir, p: P) i32 {
    return switch (side) {
        .w => p.x,
        .e => grid.W - 1 - p.x,
        .n => p.y,
        .s => grid.H - 1 - p.y,
        .ne, .se, .sw, .nw => unreachable,
    };
}

/// The cell of `b`'s outermost row on `side` at `along`: an x on the north or south, a y on the west or east.
pub fn sideAt(b: grid.Box, side: mathx.Dir, along: i32) P {
    return switch (side) {
        .n => .{ .x = along, .y = b.lo.y },
        .s => .{ .x = along, .y = b.hi.y - 1 },
        .w => .{ .x = b.lo.x, .y = along },
        .e => .{ .x = b.hi.x - 1, .y = along },
        .ne, .se, .sw, .nw => unreachable,
    };
}

/// `sideAt` level with the map's middle.
pub fn sideMid(b: grid.Box, side: mathx.Dir) P {
    return sideAt(b, side, alongOf(side, grid.MIDDLE));
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
        if (leaky(lv, i)) lv.tile[i] = t;
    }
}

fn leaky(lv: *const grid.Level, i: usize) bool {
    return rimAt(i) and !lv.tile[i].solid() and lv.door[i] == grid.NO_DOOR;
}

/// Walkable cells on the rim that are not doors; none once sealed.
pub fn leaks(lv: *const grid.Level) usize {
    var n: usize = 0;
    for (0..grid.CELLS) |i| {
        n += @intFromBool(leaky(lv, i));
    }
    return n;
}

/// A base's own ground, which its features and the finishing passes draw from.
pub const Palette = struct {
    open: grid.Tile,
    solid: grid.Tile,
    path: grid.Tile,
    /// What fills a small doorless pocket; null gives every pocket a trail.
    pocket: ?grid.Tile = null,

    pub const BUILT = Palette{ .open = .floor, .solid = .wall, .path = .floor };
    pub const CAVE = Palette{ .open = .dirt, .solid = .rock, .path = .dirt };
    pub const WILD = Palette{ .open = .grass, .solid = .shrub, .path = .grass };
    pub const TRAILED = Palette{ .open = .grass, .solid = .shrub, .path = .dirt };

    pub fn on(open: grid.Tile, solid: grid.Tile) Palette {
        return .{ .open = open, .solid = solid, .path = open };
    }

    pub fn pocketed(p: Palette) Palette {
        var q = p;
        q.pocket = p.solid;
        return q;
    }
};

/// Clear a ring to prevent surrounding terrain from sealing or pocket-filling the lot.
pub fn clearRound(lv: *grid.Level, b: grid.Box, pal: Palette) void {
    var cells = b.grown(1).cells();
    while (cells.next()) |q| {
        if (closes(lv.at(q), pal) and !b.holds(q) and !grid.Level.onRim(q)) lv.set(q, pal.open);
    }
}

/// The base's own solid, or what stands on ground: what `clearRound` opens.
pub fn closes(t: grid.Tile, pal: Palette) bool {
    return t == pal.solid or (t.solid() and t.ground() != null);
}

/// Preserve feature-opened ground and lots during pocket filling.
pub const Laid = struct {
    /// What they raised: houses, fields, set pieces.
    lots: []const grid.Box = &.{},
    /// The base before them, so ground they opened from its solid is theirs.
    before: ?*const [grid.CELLS]grid.Tile = null,
};

/// Every stretch of open ground joined to the biggest by a bending trail that bridges water, lava and chasms.
pub fn connect(lv: *grid.Level, rng: *mathx.Rng, pal: Palette, laid: Laid) void {
    var st: Stretches = .{};
    const region = &st.region;
    const size = &st.size;
    for (0..JOIN_PASSES) |_| {
        const n = st.label(lv);
        if (n <= 1) return;
        const main = st.biggest();
        const kept = if (pal.pocket != null) keptIn(lv, region, pal, laid) else Regions.initEmpty();
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

    /// Some stretch of `was`, an earlier `region`, now lies in two.
    pub fn parts(s: *const Stretches, was: *const [grid.CELLS]u16) bool {
        var to: [grid.CELLS]u16 = @splat(NONE);
        for (was, &s.region) |a, b| {
            if (a == NONE or b == NONE) continue;
            if (to[a] == NONE) to[a] = b else if (to[a] != b) return true;
        }
        return false;
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
        return s.st.region[i] == s.r and !rimAt(i);
    }
};

/// Remove barrels until every open region reconnects, choosing the shortest separating run.
pub fn unbar(lv: *grid.Level) void {
    if (std.mem.indexOfScalar(bool, &lv.barrel, true) == null) return;
    var st: Stretches = .{};
    while (true) {
        const n = st.labelBy(lv, true);
        if (n <= 1) return;
        const cut = barBetween(lv, &st, st.biggest()) orelse return;
        lv.barrel[cut] = false;
    }
}

test "unbar takes the barrels plugging the doorway, not the ones in the room behind it" {
    var lv = grid.openFloor();
    outline(&lv, .{ .lo = .{ .x = 10, .y = 5 }, .hi = .{ .x = 21, .y = 13 } }, .wall);
    const doorway = P{ .x = 15, .y = 12 };
    lv.set(doorway, .floor);
    lv.barrel[grid.Level.idx(doorway)] = true;
    lv.barrel[grid.Level.idx(.{ .x = 12, .y = 7 })] = true;
    lv.barrel[grid.Level.idx(.{ .x = 13, .y = 7 })] = true;
    unbar(&lv);
    var left: usize = 0;
    for (lv.barrel) |b| left += @intFromBool(b);
    std.debug.print("a room barred at its doorway with 2 barrels inside: {d} of 3 kept\n", .{left});
    try std.testing.expect(!lv.barrel[grid.Level.idx(doorway)]);
    try std.testing.expectEqual(@as(usize, 2), left);
    lv.barrel[grid.Level.idx(doorway)] = true;
    const porch = P{ .x = 15, .y = 13 };
    lv.barrel[grid.Level.idx(porch)] = true;
    lv.set(.{ .x = 14, .y = 13 }, .wall);
    lv.set(.{ .x = 16, .y = 13 }, .wall);
    unbar(&lv);
    left = 0;
    for (lv.barrel) |b| left += @intFromBool(b);
    std.debug.print("a room barred two deep with 2 barrels inside: {d} of 4 kept\n", .{left});
    try std.testing.expect(!lv.barrel[grid.Level.idx(doorway)] and !lv.barrel[grid.Level.idx(porch)]);
    try std.testing.expectEqual(@as(usize, 2), left);
}

/// The barrel beside `main` that begins the shortest run of barrels from it to another stretch.
fn barBetween(lv: *const grid.Level, st: *Stretches, main: u16) ?usize {
    const region = &st.region;
    const queue = &st.queue;
    var first: [grid.CELLS]u16 = @splat(NONE);
    var tail: usize = 0;
    for (0..grid.CELLS) |i| {
        if (!lv.barrel[i]) continue;
        const p = grid.Level.of(i);
        for (mathx.ALL_DIRS) |d| {
            if (!lv.passOk(p, d) or region[grid.Level.idx(p.add(d.delta()))] != main) continue;
            first[i] = @intCast(i);
            queue[tail] = @intCast(i);
            tail += 1;
            break;
        }
    }
    var head: usize = 0;
    while (head < tail) : (head += 1) {
        const i = queue[head];
        const p = grid.Level.of(i);
        for (mathx.ALL_DIRS) |d| {
            if (!lv.passOk(p, d)) continue;
            const k = grid.Level.idx(p.add(d.delta()));
            const r = region[k];
            if (r != NONE and r != main) return first[i];
            if (!lv.barrel[k] or first[k] != NONE) continue;
            first[k] = first[i];
            queue[tail] = @intCast(k);
            tail += 1;
        }
    }
    return null;
}

fn keptIn(lv: *const grid.Level, region: *const [grid.CELLS]u16, pal: Palette, laid: Laid) Regions {
    const base = Over{ .tile = pal.open, .decked = true };
    var out = Regions.initEmpty();
    for (0..grid.CELLS) |i| {
        if (region[i] == NONE) continue;
        const t = lv.tile[i];
        const other = !base.has(t) and t != pal.path;
        const opened = if (laid.before) |b| b[i].solid() else false;
        if (other or opened or lv.door[i] != grid.NO_DOOR or near(lv, grid.Level.of(i), 1, grid.Tile.liquid)) out.set(region[i]);
    }
    for (laid.lots) |lot| {
        var cells = lot.cells();
        while (cells.next()) |q| {
            const r = region[grid.Level.idx(q)];
            if (r != NONE) out.set(r);
        }
    }
    return out;
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

fn paved(t: grid.Tile, put: grid.Tile) grid.Tile {
    return if (crossing(t)) .bridge else put;
}

pub fn crossing(t: grid.Tile) bool {
    return t.liquid() or t == .bridge;
}

/// A way through a wall at `at`, `half` cells either side of its middle, from `outside` cells out to `inside` cells in along `in`.
pub fn gateway(lv: *grid.Level, at: P, in: mathx.Dir, outside: i32, inside: i32, half: i32, open: ?grid.Tile) void {
    const side = in.across().scaled(half);
    const step = in.delta();
    bridge(lv, grid.Box.between(at.sub(step.scaled(outside)).sub(side), at.add(step.scaled(inside)).add(side)), open);
}

/// A liquid in `b` bridged; with `open`, a wall there opened to it.
pub fn bridge(lv: *grid.Level, b: grid.Box, open: ?grid.Tile) void {
    var cells = b.cells();

    while (cells.next()) |q| {
        const was = lv.at(q);
        lv.set(q, paved(was, if (open != null and was == .wall) open.? else was));
    }
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
        if (dx * dx + dy * dy < 1 or self.steps >= MEANDER_STEPS) {
            self.done = true;
            return c;
        }
        self.bend = std.math.clamp(self.bend + rng.spread(MEANDER) * self.wander, -BEND_MAX * self.wander, BEND_MAX * self.wander);
        const h = std.math.atan2(dy, dx) + self.bend;
        self.x += @cos(h);
        self.y += @sin(h);
        return c;
    }
};

/// A river's middle from edge to edge, the rim too.
pub const Flow = struct {
    cell: [MEANDER_STEPS]P = undefined,
    n: usize = 0,

    pub fn of(rng: *mathx.Rng, a: P, b: P) Flow {
        var f = Flow{};
        var m = Meander.init(a, b, 1);
        while (m.next(rng)) |c| {
            f.cell[f.n] = c;
            f.n += 1;
        }
        return f;
    }

    /// A cell either side of its fill, over whatever is not liquid.
    pub fn bank(f: *const Flow, lv: *grid.Level, width: f32, t: grid.Tile) void {
        for (f.cell[0..f.n]) |c| disc(lv, c, bankReach(width), t, notLiquid);
    }

    pub fn fill(f: *const Flow, lv: *grid.Level, width: f32, t: grid.Tile) void {
        for (f.cell[0..f.n]) |c| discAll(lv, c, width / 2, t);
    }
};

pub fn bankReach(width: f32) f32 {
    return width / 2 + 1;
}

fn notLiquid(t: grid.Tile) bool {
    return !t.liquid();
}

fn edge(rng: *mathx.Rng, side: mathx.Dir) P {
    return sideAt(grid.Box.inMap(0), side, middleHalf(rng, alongOf(side, grid.SIZE)));
}

fn middleHalf(rng: *mathx.Rng, span: i32) i32 {
    return rng.range(@divTrunc(span, 4), @divTrunc(span * 3, 4));
}

pub const ACROSS = [_]mathx.Dir{ .w, .e };
pub const DOWN = [_]mathx.Dir{ .n, .s };
const EDGES = ACROSS ++ DOWN;
pub const SIDES = DOWN ++ ACROSS;

pub const Course = enum {
    across,
    down,
    any,

    pub fn ends(c: Course, rng: *mathx.Rng) [2]P {
        const side = switch (c) {
            .across => rng.pick(mathx.Dir, &ACROSS),
            .down => rng.pick(mathx.Dir, &DOWN),
            .any => rng.pick(mathx.Dir, &EDGES),
        };
        return .{ edge(rng, side), edge(rng, side.opposite()) };
    }
};

pub const LITTER_MAX: u16 = 100;

pub const Litter = struct {
    /// Per thousand cells of open grass.
    boulders: u16 = 4,

    pub fn fit(l: Litter) Litter {
        return capped(l, LITTER_MAX);
    }

    pub fn strew(l: Litter, lv: *grid.Level, rng: *mathx.Rng, _: u64) void {
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

    const TILES = .{ .tiny_shrubs = grid.Tile.tiny_shrub, .tall_grass = grid.Tile.tall_grass, .shrooms = grid.Tile.shrooms };

    comptime {
        var strewn_tiles = std.EnumSet(grid.Tile).initEmpty();
        for (std.meta.fieldNames(Decor), std.meta.fieldNames(@TypeOf(TILES))) |a, b| {
            std.debug.assert(std.mem.eql(u8, a, b));
            strewn_tiles.insert(@field(TILES, a));
        }
        std.debug.assert(strewn_tiles.eql(grid.LITTER_TILES));
    }

    pub fn fit(d: Decor) Decor {
        return capped(d, DECOR_MAX);
    }

    pub fn strew(d: Decor, lv: *grid.Level, rng: *mathx.Rng, seed: u64) void {
        strewn(lv, rng, d.tiny_shrubs, TILES.tiny_shrubs);
        clumps(lv, Noise.init(seed, .tall_grass), TALL_GRASS_SCALE, d.tall_grass, .{ .tile = TILES.tall_grass.ground().? }, TILES.tall_grass);
        strewn(lv, rng, d.shrooms, TILES.shrooms);
    }
};

fn capped(v: anytype, max: u16) @TypeOf(v) {
    var q = v;
    inline for (std.meta.fields(@TypeOf(v))) |f| @field(q, f.name) = @min(@field(v, f.name), max);
    return q;
}

/// In the rng's order: reordering changes every seed's floor.
const DRESSES = [_]type{ Litter, Decor };

fn dressOf(comptime T: type, comptime D: type) ?[:0]const u8 {
    var found: ?[:0]const u8 = null;
    for (std.meta.fields(T)) |f| {
        if (f.type != D) continue;
        if (found != null) @compileError(@typeName(T) ++ " holds two " ++ @typeName(D));
        found = f.name;
    }
    return found;
}

pub fn fitDress(p: anytype) @TypeOf(p) {
    var q = p;
    inline for (DRESSES) |D| {
        if (comptime dressOf(@TypeOf(p), D)) |n| @field(q, n) = @field(p, n).fit();
    }
    return q;
}

/// Its own `fit`, if it has one, then its dressing's.
pub fn fitted(p: anytype) @TypeOf(p) {
    return fitDress(if (comptime @hasDecl(@TypeOf(p), "fit")) p.fit() else p);
}

pub fn dress(p: anytype, lv: *grid.Level, rng: *mathx.Rng, seed: u64) void {
    inline for (DRESSES) |D| {
        if (comptime dressOf(@TypeOf(p), D)) |n| @field(p, n).strew(lv, rng, seed);
    }
}

fn strewn(lv: *grid.Level, rng: *mathx.Rng, per_mille: u32, put: grid.Tile) void {
    scatter(lv, rng, per_mille, .{ .tile = put.ground().? }, put, put.solid());
}

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
    var of: [grid.CELLS]u16 = @splat(BUCKETS);
    var n: u32 = 0;
    for (0..grid.CELLS) |i| {
        if (!on.at(lv, grid.Level.of(i)) or rimAt(i)) continue;
        const b = bucket(noise.at(grid.Level.of(i), scale, 3), BUCKETS);
        of[i] = @intCast(b);
        hist[b] += 1;
        n += 1;
    }
    const want = n * @min(per_mille, mathx.MILLE) / mathx.MILLE;
    var cut: usize = BUCKETS;
    var taken: u32 = 0;
    while (cut > 0 and taken + hist[cut - 1] <= want) : (cut -= 1) taken += hist[cut - 1];
    for (&of, 0..) |b, i| {
        if (b < BUCKETS and b >= cut) lv.tile[i] = put;
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
    const a = Noise.init(7, .grain);
    const b = Noise.init(7, .grain);
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
    const pal = Palette.WILD.pocketed();
    field(&lv, pal);
    disc(&lv, grid.MIDDLE, 4, .water, null);
    disc(&lv, grid.MIDDLE, 1, .grass, null);
    connect(&lv, &rng, pal, .{});
    std.debug.print("a five-cell island in a pocket-filling base: {d} bridge cells after joining\n", .{count(&lv, .bridge)});
    try std.testing.expect(lv.walkable(grid.MIDDLE));
    try std.testing.expect(count(&lv, .bridge) > 0);
}

test "a river runs edge to edge and parts the ground, and a join bridges it" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x21E);
    field(&lv, Palette.WILD);
    const f = Flow.of(&rng, .{ .x = 0, .y = 32 }, .{ .x = grid.W - 1, .y = 30 });
    f.bank(&lv, 3, .shallows);
    f.fill(&lv, 3, .water);
    var st: Stretches = .{};
    const parted = st.label(&lv);
    connect(&lv, &rng, Palette.TRAILED, .{});
    const joined = st.label(&lv);
    std.debug.print("a river: {d} water cells, the ground in {d} parts, {d} after joining by {d} bridge cells\n", .{ count(&lv, .water), parted, joined, count(&lv, .bridge) });
    try std.testing.expect(parted >= 2);
    try std.testing.expectEqual(@as(usize, 1), joined);
    try std.testing.expect(count(&lv, .bridge) > 0);
}
