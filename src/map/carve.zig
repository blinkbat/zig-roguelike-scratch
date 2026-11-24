const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");

const P = mathx.P;

const CROWD: usize = 5;
const POCKET: usize = 16;
const NONE = std.math.maxInt(u16);
const NO_CELL = std.math.maxInt(u32);
/// Radians; a bend changes by up to half this a step.
const MEANDER: f32 = 0.55;
/// Radians, at full wander.
const BEND_MAX: f32 = 1.1;
const MEANDER_STEPS: usize = 4 * (grid.COLS + grid.ROWS);

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
    tee = 0x7EE0,
    tee_woods = 0x7EE1,
    section = 0x5EC7,

    pub fn of(salt: Salt, seed: u64) u64 {
        return seed ^ @intFromEnum(salt);
    }

    pub fn rng(salt: Salt, seed: u64) mathx.Rng {
        return mathx.Rng.init(salt.of(seed));
    }
};

pub const Noise = struct {
    seed: u64,

    pub fn init(seed: u64, salt: Salt) Noise {
        return .{ .seed = salt.of(seed) };
    }

    fn lattice(self: Noise, x: i32, y: i32) f32 {
        var h = self.seed ^ (@as(u64, @bitCast(@as(i64, x))) *% mathx.GOLDEN_GAMMA) ^ (@as(u64, @bitCast(@as(i64, y))) *% 0xC2B2AE3D27D4EB4F);
        h ^= h >> 31;
        h *%= 0xBF58476D1CE4E5B9;
        h ^= h >> 29;
        return mathx.unitOf(h);
    }

    fn value(self: Noise, x: f32, y: f32) f32 {
        return mathx.valueNoise(self, lattice, x, y);
    }

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

pub fn stretch(v: f32, gain: f32) f32 {
    return std.math.clamp((v - 0.5) * gain + 0.5, 0, 1);
}

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

/// `sown` is percent; `strays` per thousand.
pub fn cellular(lv: *grid.Level, rng: *mathx.Rng, sown: u32, passes: u32, strays: u32, pal: Palette) void {
    sow(lv, rng, sown, pal.solid, pal.open);
    smooth(lv, passes, pal.solid, pal.open);
    scatter(lv, rng, strays, .{ .tile = pal.open }, pal.solid, true);
}

/// Off the map counts as solid.
pub fn smooth(lv: *grid.Level, passes: u32, solid: grid.Tile, open: grid.Tile) void {
    var next: [grid.CELLS]grid.Tile = undefined;
    var walled: Walled = undefined;
    for (0..passes) |_| {
        @memset(&walled, 1);
        for (0..grid.CELLS) |i| walled[padded(i)] = @intFromBool(lv.tile[i] == solid);
        for (0..grid.CELLS) |i| {
            const t = lv.tile[i];
            next[i] = if (t != solid and t != open) t else if (rimAt(i) or crowded(&walled, padded(i))) solid else open;
        }
        lv.tile = next;
    }
}

const PADDED_W: usize = grid.COLS + 2;
const Walled = [PADDED_W * (grid.ROWS + 2)]u8;

fn padded(i: usize) usize {
    return (i / grid.COLS + 1) * PADDED_W + i % grid.COLS + 1;
}

fn crowded(walled: *const Walled, c: usize) bool {
    var n: usize = 0;
    for ([_]usize{ c - PADDED_W, c, c + PADDED_W }) |row| n += @as(usize, walled[row - 1]) + walled[row] + walled[row + 1];
    return n >= CROWD;
}

pub fn clearAround(lv: *const grid.Level, p: P) bool {
    return grid.allNeighbours(p, lv, grid.Level.walkable);
}

pub const Over = struct {
    tile: grid.Tile,
    decked: bool = false,
    water_range: u8 = 0,
    water_clear: u8 = 0,
    land_range: u8 = 0,

    pub const RANGES: []const []const u8 = &.{ "water_range", "water_clear", "land_range" };

    fn has(o: Over, t: grid.Tile) bool {
        return t == o.tile or (o.decked and !t.solid() and t.ground() == o.tile and (grid.LITTER_TILES.contains(t) or t.tinder()));
    }

    fn at(o: Over, lv: *const grid.Level, p: P) bool {
        if (!o.has(lv.at(p))) return false;
        if (o.water_range != 0 and !nearWater(lv, p, o.water_range)) return false;
        if (o.water_clear != 0 and nearWater(lv, p, o.water_clear)) return false;
        return o.land_range == 0 or near(lv, p, o.land_range, Land{ .tile = o.tile });
    }

    fn mask(o: Over, lv: *const grid.Level, within: grid.Box) grid.CellSet {
        var wet: Summed = undefined;
        var land: Summed = undefined;
        if (o.water_range != 0 or o.water_clear != 0) wet.fill(lv, Is(grid.Tile.wet){});
        if (o.land_range != 0) land.fill(lv, Land{ .tile = o.tile });
        var out = grid.CellSet.initEmpty();
        var cells = within.cells();
        while (cells.next()) |p| {
            if (!o.has(lv.at(p))) continue;
            if (o.water_range != 0 and !wet.any(p, o.water_range)) continue;
            if (o.water_clear != 0 and wet.any(p, o.water_clear)) continue;
            if (o.land_range != 0 and !land.any(p, o.land_range)) continue;
            out.set(grid.Level.idx(p));
        }
        return out;
    }

    const Land = struct {
        tile: grid.Tile,

        fn holds(l: Land, t: grid.Tile) bool {
            if (t.solid() and t.ground() == null) return false;
            const ground = t.ground() orelse t;
            return !ground.wet() and ground != l.tile;
        }
    };
};

comptime {
    var ranges = 0;
    for (std.meta.fields(Over)) |f| ranges += @intFromBool(f.type == u8);
    std.debug.assert(ranges == Over.RANGES.len);
    for (Over.RANGES) |name| std.debug.assert(@FieldType(Over, name) == u8);
}

pub fn nearWater(lv: *const grid.Level, p: P, range: u8) bool {
    return near(lv, p, range, Is(grid.Tile.wet){});
}

fn Is(comptime has: fn (grid.Tile) bool) type {
    return struct {
        fn holds(_: @This(), t: grid.Tile) bool {
            return has(t);
        }
    };
}

fn near(lv: *const grid.Level, p: P, r: i32, which: anytype) bool {
    var cells = grid.Cells.around(p, r);
    while (cells.next()) |q| {
        if (grid.Level.inside(q) and which.holds(lv.at(q))) return true;
    }
    return false;
}

const Summed = struct {
    const W = grid.COLS + 1;
    sum: [W * (grid.ROWS + 1)]u16,

    fn fill(self: *Summed, lv: *const grid.Level, which: anytype) void {
        @memset(self.sum[0..W], 0);
        for (0..grid.ROWS) |y| {
            self.sum[(y + 1) * W] = 0;
            var row: u16 = 0;
            for (0..grid.COLS) |x| {
                const i = grid.Level.idx(.{ .x = @intCast(x), .y = @intCast(y) });
                row += @intFromBool(which.holds(lv.tile[i]));
                self.sum[(y + 1) * W + x + 1] = self.sum[y * W + x + 1] + row;
            }
        }
    }

    fn any(self: *const Summed, p: P, r: i32) bool {
        const b = grid.Box.around(p, r);
        const x0: usize = @intCast(std.math.clamp(b.lo.x, 0, grid.W));
        const y0: usize = @intCast(std.math.clamp(b.lo.y, 0, grid.H));
        const x1: usize = @intCast(std.math.clamp(b.hi.x, 0, grid.W));
        const y1: usize = @intCast(std.math.clamp(b.hi.y, 0, grid.H));
        const s = &self.sum;
        return @as(i32, s[y1 * W + x1]) - s[y0 * W + x1] - s[y1 * W + x0] + s[y0 * W + x0] > 0;
    }
};

test "a summed range answers as the square scan does" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(11);
    for (&lv.tile) |*t| t.* = if (rng.perMille(15)) .water else if (rng.perMille(40)) .wall else .grass;
    const on = Over{ .tile = .grass, .water_range = 6, .land_range = 3 };
    const clear = Over{ .tile = .grass, .water_clear = 2 };
    for ([_]Over{ on, clear }) |o| {
        const mask = o.mask(&lv, grid.MAP);
        for (0..grid.CELLS) |i| try std.testing.expectEqual(o.at(&lv, grid.Level.of(i)), mask.isSet(i));
    }
}

pub fn scatter(lv: *grid.Level, rng: *mathx.Rng, per_mille: u32, on: Over, put: grid.Tile, lone: bool) void {
    scatterIn(lv, rng, per_mille, on, put, lone, grid.MAP);
}

pub fn scatterIn(lv: *grid.Level, rng: *mathx.Rng, per_mille: u32, on: Over, put: grid.Tile, lone: bool, within: grid.Box) void {
    const over = on.mask(lv, within);
    var cells = within.cells();
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        if (!over.isSet(i)) continue;
        if (grid.Level.onRim(p) or (lone and !clearAround(lv, p))) continue;
        if (rng.perMille(per_mille)) lv.tile[i] = put;
    }
}

pub fn disc(lv: *grid.Level, c: P, r: f32, t: grid.Tile, comptime over: ?fn (grid.Tile) bool) void {
    discOf(lv, c, r, t, false, null, over);
}

pub const LANE_MIN: u8 = 2;
pub const SPAN: grid.Tile = .bridge;

pub const Lane = union(enum) {
    cut,
    road: grid.Tile,

    pub const bridged: Lane = .{ .road = SPAN };
};

pub fn lane(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, width: u8, wander: f32, t: grid.Tile, comptime how: Lane) void {
    std.debug.assert(width >= LANE_MIN);
    const r = laneRadius(width);
    const span: ?grid.Tile = switch (how) {
        .cut => null,
        .road => |s| s,
    };
    var m = Meander.init(a, b, wander);
    while (m.next(rng)) |c| discOf(lv, c, r, t, how == .road, span, null);
}

pub fn laneRadius(width: u8) f32 {
    return @as(f32, @floatFromInt(width - 1)) / 2 + 0.5;
}

pub fn inDisc(c: P, q: P, r: f32) bool {
    const dx: f32 = @floatFromInt(q.x - c.x);
    const dy: f32 = @floatFromInt(q.y - c.y);
    return dx * dx + dy * dy <= r * r + DISC_SLACK;
}

const DISC_SLACK: f32 = 0.25;

pub fn discReach(r: f32) i32 {
    return @intFromFloat(@floor(@sqrt(r * r + DISC_SLACK)));
}

fn discOf(lv: *grid.Level, c: P, r: f32, t: grid.Tile, comptime with_rim: bool, comptime pave: ?grid.Tile, comptime over: ?fn (grid.Tile) bool) void {
    const k: i32 = @intFromFloat(@ceil(r));
    var cells = grid.Cells.around(c, k);
    while (cells.next()) |q| {
        if (!with_rim and grid.Level.onRim(q)) continue;
        if (!inDisc(c, q, r)) continue;
        if (over) |ok| {
            if (!ok(lv.at(q))) continue;
        }
        lv.set(q, if (pave) |span| paved(lv.at(q), t, span) else t);
    }
}

pub const CAVE_SCALE: f32 = 3;

pub fn blob(lv: *grid.Level, noise: Noise, c: P, r: f32, scale: f32, lo: f32, span: f32, t: grid.Tile) void {
    blobIn(lv, noise, c, r, scale, lo, span, t, blobBox(c, r, lo, span), null);
}

pub fn blobBox(c: P, r: f32, lo: f32, span: f32) grid.Box {
    return grid.Box.around(c, @intFromFloat(@ceil(r * @max(lo, lo + span))));
}

pub fn blobIn(lv: *grid.Level, noise: Noise, c: P, r: f32, scale: f32, lo: f32, span: f32, t: grid.Tile, within: grid.Box, comptime over: ?fn (grid.Tile) bool) void {
    var cells = within.cells();
    while (cells.next()) |q| {
        if (grid.Level.onRim(q)) continue;
        if (over) |ok| {
            if (!ok(lv.at(q))) continue;
        }
        if (mathx.distEuclid(q, c) / r < lo + span * noise.at(q, scale, 2)) lv.set(q, t);
    }
}

pub fn field(lv: *grid.Level, pal: Palette) void {
    fill(lv, pal.open);
    rim(lv, pal.solid);
}

pub fn rimAt(i: usize) bool {
    return grid.Level.onRim(grid.Level.of(i));
}

pub fn box(lv: *grid.Level, b: grid.Box, t: grid.Tile) void {
    var cells = b.cells();
    while (cells.next()) |q| lv.set(q, t);
}

pub fn outline(lv: *grid.Level, b: grid.Box, t: grid.Tile) void {
    var cells = b.cells();
    while (cells.next()) |q| {
        if (b.onEdge(q)) lv.set(q, t);
    }
}

pub fn corners(b: grid.Box) [4]P {
    return .{ b.lo, .{ .x = b.hi.x - 1, .y = b.lo.y }, .{ .x = b.lo.x, .y = b.hi.y - 1 }, b.hi.sub(.{ .x = 1, .y = 1 }) };
}

pub fn alongOf(side: mathx.Dir, p: P) i32 {
    return switch (side) {
        .n, .s => p.x,
        .w, .e => p.y,
        .ne, .se, .sw, .nw => unreachable,
    };
}

pub fn inFrom(side: mathx.Dir, p: P) i32 {
    return switch (side) {
        .w => p.x,
        .e => grid.W - 1 - p.x,
        .n => p.y,
        .s => grid.H - 1 - p.y,
        .ne, .se, .sw, .nw => unreachable,
    };
}

pub fn sideAt(b: grid.Box, side: mathx.Dir, along: i32) P {
    return switch (side) {
        .n => .{ .x = along, .y = b.lo.y },
        .s => .{ .x = along, .y = b.hi.y - 1 },
        .w => .{ .x = b.lo.x, .y = along },
        .e => .{ .x = b.hi.x - 1, .y = along },
        .ne, .se, .sw, .nw => unreachable,
    };
}

pub fn sideMid(b: grid.Box, side: mathx.Dir) P {
    return sideAt(b, side, alongOf(side, grid.MIDDLE));
}

pub fn openDoors(lv: *grid.Level, doors: []const P, ground: grid.Tile) void {
    for (doors, 0..) |d, k| {
        lv.putDoor(d, k);
        const i = grid.Level.idx(d);
        lv.tile[i] = ground;
        const in = grid.Level.inset(d);
        if (lv.at(in).solid()) lv.set(in, ground);
    }
}

pub fn seal(lv: *grid.Level, t: grid.Tile) void {
    for (0..grid.CELLS) |i| {
        if (leaky(lv, i)) lv.tile[i] = t;
    }
}

fn leaky(lv: *const grid.Level, i: usize) bool {
    return rimAt(i) and !lv.tile[i].solid() and lv.door[i] == grid.NO_DOOR;
}

pub fn leaks(lv: *const grid.Level) usize {
    var n: usize = 0;
    for (0..grid.CELLS) |i| {
        n += @intFromBool(leaky(lv, i));
    }
    return n;
}

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

pub fn clearRound(lv: *grid.Level, b: grid.Box, pal: Palette) void {
    var cells = b.grown(1).cells();
    while (cells.next()) |q| {
        if (closes(lv.at(q), pal) and !b.holds(q) and !grid.Level.onRim(q)) lv.set(q, pal.open);
    }
}

pub fn closes(t: grid.Tile, pal: Palette) bool {
    return t == pal.solid or (t.solid() and t.ground() != null and !t.prized());
}

pub const Laid = struct {
    lots: []const grid.Box = &.{},
    before: ?*const [grid.CELLS]grid.Tile = null,
    /// Painted by hand: a join goes round their solid cells, and through one only to reach what they shut in.
    authored: ?*const grid.CellSet = null,
};

const UNPAINTED = grid.CellSet.initEmpty();

pub fn connect(lv: *grid.Level, rng: *mathx.Rng, pal: Palette, laid: Laid) void {
    var st: Stretches = .{};
    const region = &st.region;
    const size = &st.size;
    for (0..grid.CELLS) |_| {
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
            if (!joinRound(lv, rng, &st, region[orphan], main, from, to, pal.path, laid.authored orelse &UNPAINTED)) break;
        }
    }
}

/// The trail if it crosses no painted solid or prize, else the way through fewest: false when that breaks one, so the pass relabels first.
fn joinRound(lv: *grid.Level, rng: *mathx.Rng, st: *Stretches, from_r: u16, main: u16, a: P, b: P, path: grid.Tile, painted: *const grid.CellSet) bool {
    var way: [Trail.MOST]P = undefined;
    var n: usize = 0;
    var crosses = false;
    var t = Trail{ .p = a, .b = b };
    while (t.next(rng, lv)) |p| {
        way[n] = p;
        n += 1;
        crosses = crosses or breaksLast(lv, painted, grid.Level.idx(p));
    }
    if (!crosses) {
        for (way[0..n]) |p| lay(lv, p, path);
        return true;
    }
    const broke = route(lv, st, from_r, main, path, painted) orelse return true;
    return broke == 0;
}

fn walledBy(lv: *const grid.Level, painted: ?*const grid.CellSet, i: usize) bool {
    const p = painted orelse return false;
    return p.isSet(i) and lv.tile[i].solid();
}

pub fn breaksLast(lv: *const grid.Level, painted: ?*const grid.CellSet, i: usize) bool {
    return walledBy(lv, painted, i) or lv.tile[i].prized();
}

/// Square steps from every cell of `from_r` to the nearest of `main` off the rim, through the fewest cells it `breaksLast`; how many.
fn route(lv: *grid.Level, st: *Stretches, from_r: u16, main: u16, path: grid.Tile, painted: *const grid.CellSet) ?usize {
    const Way = struct {
        lv: *const grid.Level,
        st: *const Stretches,
        main: u16,
        painted: *const grid.CellSet,

        pub const ON_TAKE = false;
        pub const LIT_LAST = true;

        pub fn opens(_: @This(), q: P) bool {
            return !grid.Level.onRim(q);
        }

        pub fn last(w: @This(), k: usize) bool {
            return breaksLast(w.lv, w.painted, k);
        }

        pub fn done(w: @This(), k: usize) bool {
            return w.st.region[k] == w.main;
        }
    };
    var search: Fewest = .{};
    for (st.region, 0..) |r, i| if (r == from_r) search.seed(i);
    const found = search.run(lv, Way{ .lv = lv, .st = st, .main = main, .painted = painted }) orelse return null;
    var way = search.trace(found.end);
    while (way.next()) |p| lay(lv, p, path);
    return found.breaks;
}

pub const Fewest = struct {
    back: [grid.CELLS]u32 = @splat(NO_CELL),
    seen: grid.CellSet = .initEmpty(),
    queue: [grid.CELLS]u32 = undefined,
    walls: [grid.CELLS]u32 = undefined,
    tail: usize = 0,

    pub const Found = struct { end: u32, breaks: usize };

    pub fn seed(self: *Fewest, i: usize) void {
        self.seen.set(i);
        self.queue[self.tail] = @intCast(i);
        self.tail += 1;
    }

    pub fn trace(self: *const Fewest, end: u32) Trace {
        return .{ .back = &self.back, .at = end };
    }

    pub const Trace = struct {
        back: *const [grid.CELLS]u32,
        at: u32,

        pub fn next(t: *Trace) ?P {
            if (t.at == NO_CELL) return null;
            const p = grid.Level.of(t.at);
            t.at = t.back[t.at];
            return p;
        }
    };

    /// `ON_TAKE` tests `done` on a cell as it is taken, else on a step's first reach, ending at the cell it stepped from; `LIT_LAST` holds lit cells behind unlit.
    pub fn run(self: *Fewest, lv: *const grid.Level, way: anytype) ?Found {
        const Way = @TypeOf(way);
        var head: usize = 0;
        var breaks: usize = 0;
        while (head < self.tail) : (breaks += 1) {
            var walled: usize = 0;
            while (head < self.tail) : (head += 1) {
                const i = self.queue[head];
                if (Way.ON_TAKE and way.done(i)) return .{ .end = i, .breaks = breaks };
                const p = grid.Level.of(i);
                for (mathx.CARDINALS) |d| {
                    const q = p.add(d);
                    if (!grid.Level.inside(q) or !way.opens(q)) continue;
                    const k = grid.Level.idx(q);
                    if (self.seen.isSet(k)) continue;
                    self.seen.set(k);
                    if (!Way.ON_TAKE and way.done(k)) return .{ .end = i, .breaks = breaks };
                    self.back[k] = i;
                    if (way.last(k)) {
                        self.walls[walled] = @intCast(k);
                        walled += 1;
                        continue;
                    }
                    self.queue[self.tail] = @intCast(k);
                    self.tail += 1;
                }
            }
            for ([_]bool{ false, true }) |lit| {
                for (self.walls[0..walled]) |k| {
                    if (Way.LIT_LAST and lv.torch.has(grid.Level.of(k)) != lit) continue;
                    if (!Way.LIT_LAST and lit) continue;
                    self.queue[self.tail] = k;
                    self.tail += 1;
                }
            }
        }
        return null;
    }
};

pub const Stretches = struct {
    region: [grid.CELLS]u16 = undefined,
    size: [grid.CELLS]u32 = undefined,
    queue: [grid.CELLS]u32 = undefined,
    n: usize = 0,

    pub fn label(s: *Stretches, lv: *const grid.Level) usize {
        return s.labelBy(lv, false);
    }

    pub fn biggest(s: *const Stretches) u16 {
        return biggestOf(s.size[0..s.n]);
    }

    pub fn biggestOf(sizes: []const u32) u16 {
        var main: u16 = 0;
        for (sizes[1..], 1..) |n, r| {
            if (n > sizes[main]) main = @intCast(r);
        }
        return main;
    }

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
        var seen = grid.CellSet.initEmpty();
        var n: u16 = 0;
        for (0..grid.CELLS) |c| {
            if (seen.isSet(c) or !lv.openAt(c) or (barred and lv.barrel[c])) continue;
            const Way = Walked(barred);
            var spread = grid.Spread(Way, Way.has){ .ctx = .{ .lv = lv }, .steps = &grid.STEPS, .seen = &seen, .queue = &s.queue };
            spread.seed(grid.Level.of(c));
            while (spread.next()) |p| s.region[grid.Level.idx(p)] = n;
            s.size[n] = @intCast(spread.tail);
            n += 1;
        }
        s.n = n;
        return n;
    }
};

fn Walked(comptime barred: bool) type {
    return struct {
        lv: *const grid.Level,

        fn has(w: @This(), p: P) bool {
            if (!w.lv.walkable(p)) return false;
            if (!barred) return true;
            const i = grid.Level.idx(p);
            return !w.lv.barrel[i];
        }
    };
}

const InStretch = struct {
    st: *const Stretches,
    r: u16,

    pub fn has(s: InStretch, i: usize) bool {
        return s.st.region[i] == s.r and !rimAt(i);
    }
};

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
    var left = lv.barrelCount();
    try std.testing.expect(!lv.barrel[grid.Level.idx(doorway)]);
    try std.testing.expectEqual(@as(usize, 2), left);
    lv.barrel[grid.Level.idx(doorway)] = true;
    const porch = P{ .x = 15, .y = 13 };
    lv.barrel[grid.Level.idx(porch)] = true;
    lv.set(.{ .x = 14, .y = 13 }, .wall);
    lv.set(.{ .x = 16, .y = 13 }, .wall);
    unbar(&lv);
    left = lv.barrelCount();
    try std.testing.expect(!lv.barrel[grid.Level.idx(doorway)] and !lv.barrel[grid.Level.idx(porch)]);
    try std.testing.expectEqual(@as(usize, 2), left);
}

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

fn keepsBeside(t: grid.Tile) bool {
    return t.liquid() or t.prized();
}

fn keptIn(lv: *const grid.Level, region: *const [grid.CELLS]u16, pal: Palette, laid: Laid) Regions {
    const base = Over{ .tile = pal.open, .decked = true };
    var out = Regions.initEmpty();
    for (0..grid.CELLS) |i| {
        if (region[i] == NONE or out.isSet(region[i])) continue;
        const t = lv.tile[i];
        const other = !base.has(t) and t != pal.path;
        const opened = if (laid.before) |b| b[i].solid() else false;
        if (other or opened or lv.door[i] != grid.NO_DOOR or near(lv, grid.Level.of(i), 1, Is(keepsBeside){})) out.set(region[i]);
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

pub const Regions = std.StaticBitSet(grid.CELLS);

pub fn trail(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, path: grid.Tile) void {
    var t = Trail{ .p = a, .b = b };
    while (t.next(rng, lv)) |p| lay(lv, p, path);
}

const DETOURS_MAX = 8;

const Trail = struct {
    p: P,
    b: P,
    begun: bool = false,
    detours: u8 = 0,

    /// Cells a trail lays: one per step across and down the map, and two per detour.
    const MOST: usize = grid.COLS + grid.ROWS + 2 * DETOURS_MAX;

    fn next(t: *Trail, rng: *mathx.Rng, lv: *const grid.Level) ?P {
        if (!t.begun) {
            t.begun = true;
            return t.p;
        }
        if (t.p.eq(t.b)) return null;
        const dx = t.b.x - t.p.x;
        const dy = t.b.y - t.p.y;
        const across = dy == 0 or (dx != 0 and rng.below(@abs(dx) + @abs(dy)) < @abs(dx));
        const along = P{ .x = std.math.sign(dx), .y = 0 };
        const down = P{ .x = 0, .y = std.math.sign(dy) };
        t.p = t.p.add(if (across) t.round(lv, along, down) else t.round(lv, down, along));
        return t.p;
    }

    /// `step`, else the other way toward `b`, else aside: a trail passes a chest or glow plant by.
    fn round(t: *Trail, lv: *const grid.Level, step: P, other: P) P {
        if (!lv.at(t.p.add(step)).prized() or t.detours >= DETOURS_MAX) return step;
        if (!other.eq(.{ .x = 0, .y = 0 }) and !lv.at(t.p.add(other)).prized()) return other;
        const side = P{ .x = step.y, .y = step.x };
        for ([_]P{ side, side.scaled(-1) }) |s| {
            const q = t.p.add(s);
            if (grid.Level.inside(q) and !grid.Level.onRim(q) and !lv.at(q).prized()) {
                t.detours += 1;
                return s;
            }
        }
        return step;
    }
};

test "a trail steps round a chest or glow plant in its way and still joins its ends" {
    for (0..20) |seed| {
        var lv = grid.Level.blank();
        const a = P{ .x = 10, .y = 10 };
        const b = P{ .x = 20, .y = 10 };
        lv.set(a, .floor);
        lv.set(.{ .x = 12, .y = 10 }, .glow_plant);
        lv.set(.{ .x = 16, .y = 10 }, .chest);
        lv.set(.{ .x = 19, .y = 9 }, .chest);
        lv.set(.{ .x = 19, .y = 11 }, .chest);
        var rng = mathx.Rng.init(seed + 1);
        trail(&lv, &rng, a, b, .floor);
        try std.testing.expectEqual(grid.Tile.glow_plant, lv.at(.{ .x = 12, .y = 10 }));
        try std.testing.expectEqual(grid.Tile.chest, lv.at(.{ .x = 16, .y = 10 }));
        try std.testing.expectEqual(grid.Tile.floor, lv.at(b));
        var st: Stretches = .{};
        _ = st.label(&lv);
        try std.testing.expectEqual(st.of(a), st.of(b));
    }
}

test "a join with nothing painted goes round prizes its trail would pave" {
    const orphan = P{ .x = 20, .y = 10 };
    const prizes = [_]P{ .{ .x = 29, .y = 10 }, .{ .x = 28, .y = 9 }, .{ .x = 28, .y = 11 } };
    for (0..10) |seed| {
        var lv = grid.Level.blank();
        var cells = (grid.Box{ .lo = .{ .x = 30, .y = 10 }, .hi = .{ .x = 50, .y = 11 } }).cells();
        while (cells.next()) |q| lv.set(q, .floor);
        lv.set(orphan, .floor);
        for (prizes) |q| lv.set(q, .chest);
        var rng = mathx.Rng.init(seed + 1);
        connect(&lv, &rng, Palette.BUILT, .{});
        for (prizes) |q| try std.testing.expectEqual(grid.Tile.chest, lv.at(q));
        var st: Stretches = .{};
        _ = st.label(&lv);
        try std.testing.expectEqual(st.of(orphan), st.of(.{ .x = 40, .y = 10 }));
    }
}

test "a trail along the row inside the rim steps round a chest without opening the rim" {
    for (0..20) |seed| {
        var lv = grid.Level.blank();
        lv.set(.{ .x = 40, .y = 1 }, .chest);
        var rng = mathx.Rng.init(seed + 1);
        trail(&lv, &rng, .{ .x = 45, .y = 1 }, .{ .x = 30, .y = 1 }, .floor);
        for (0..grid.CELLS) |i| {
            const p = grid.Level.of(i);
            if (grid.Level.onRim(p)) try std.testing.expect(lv.at(p).solid());
        }
    }
}

fn lay(lv: *grid.Level, p: P, path: grid.Tile) void {
    layWith(lv, p, path, SPAN);
}

pub fn layWith(lv: *grid.Level, p: P, path: grid.Tile, span: grid.Tile) void {
    const t = lv.at(p);
    if (t.solid()) lv.set(p, paved(t, path, span));
}

fn paved(t: grid.Tile, put: grid.Tile, span: grid.Tile) grid.Tile {
    if (t.spans()) return t;
    return if (t.liquid()) t.spannedBy(span) else put;
}

pub fn crossing(t: grid.Tile) bool {
    return t.liquid() or t.spans();
}

pub fn gateway(lv: *grid.Level, at: P, in: mathx.Dir, outside: i32, inside: i32, half: i32, open: ?grid.Tile) void {
    const side = in.across().scaled(half);
    const step = in.delta();
    bridge(lv, grid.Box.between(at.sub(step.scaled(outside)).sub(side), at.add(step.scaled(inside)).add(side)), open);
}

pub fn bridge(lv: *grid.Level, b: grid.Box, open: ?grid.Tile) void {
    var cells = b.cells();

    while (cells.next()) |q| {
        const was = lv.at(q);
        lv.set(q, paved(was, if (open != null and was == .wall) open.? else was, SPAN));
    }
}

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
        const c = mathx.roundCell(self.x, self.y);
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

    pub fn within(self: Meander, bounds: grid.Box) Within {
        return .{ .m = self, .bounds = bounds };
    }

    pub const Within = struct {
        m: Meander,
        bounds: grid.Box,

        pub fn next(self: *Within, rng: *mathx.Rng) ?P {
            return self.bounds.clamp(self.m.next(rng) orelse return null);
        }
    };
};

pub const Flow = struct {
    cell: [MEANDER_STEPS]P = undefined,
    n: usize = 0,

    pub fn of(rng: *mathx.Rng, a: P, b: P, wander: f32) Flow {
        var f = Flow{};
        var m = Meander.init(a, b, wander);
        while (m.next(rng)) |c| _ = mathx.push(P, &f.cell, &f.n, c);
        return f;
    }

    pub fn course(f: *const Flow) []const P {
        return f.cell[0..f.n];
    }

    pub fn bank(f: *const Flow, lv: *grid.Level, width: f32, t: grid.Tile, comptime over: fn (grid.Tile) bool) void {
        for (f.course()) |c| disc(lv, c, bankReach(width), t, over);
    }

    pub fn fill(f: *const Flow, lv: *grid.Level, width: f32, t: grid.Tile, comptime with_rim: bool) void {
        for (f.course()) |c| discOf(lv, c, width / 2, t, with_rim, null, null);
    }
};

pub fn bankReach(width: f32) f32 {
    return width / 2 + 1;
}

pub fn notLiquid(t: grid.Tile) bool {
    return !t.liquid();
}

fn edge(rng: *mathx.Rng, side: mathx.Dir) P {
    return sideAt(grid.MAP, side, middleHalf(rng, alongOf(side, grid.SIZE)));
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
        hearts(lv, TILES.tall_grass, .reeds);
        strewn(lv, rng, d.shrooms, TILES.shrooms);
    }
};

/// Each `t` with only `t` all round it becomes `heart`, judged on the tiles as they lay before.
fn hearts(lv: *grid.Level, t: grid.Tile, heart: grid.Tile) void {
    const before = lv.tile;
    for (before, 0..) |here, i| {
        if (here != t) continue;
        const p = grid.Level.of(i);
        const whole = for (mathx.ALL_DIRS) |d| {
            const q = p.add(d.delta());
            if (!grid.Level.inside(q)) break false;
            const k = grid.Level.idx(q);
            if (before[k] != t) break false;
        } else true;
        if (whole) lv.tile[i] = heart;
    }
}

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

pub fn clumps(lv: *grid.Level, noise: Noise, scale: f32, per_mille: u32, on: Over, put: grid.Tile) void {
    const BUCKETS = 256;
    var hist = [_]u32{0} ** BUCKETS;
    var of: [grid.CELLS]u16 = @splat(BUCKETS);
    var n: u32 = 0;
    const over = on.mask(lv, grid.MAP);
    for (0..grid.CELLS) |i| {
        if (!over.isSet(i) or rimAt(i)) continue;
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

pub fn partOf(n: i32, share: f32) i32 {
    return @intFromFloat(@as(f32, @floatFromInt(n)) * share);
}

pub fn count(lv: *const grid.Level, t: grid.Tile) usize {
    var n: usize = 0;
    for (lv.tile) |c| {
        if (c == t) n += 1;
    }
    return n;
}

test "the cave rule counts each cell's solid neighbours, off the map solid, as cell by cell" {
    var lv = grid.Level.blank();
    var want = grid.Level.blank();
    var rng = mathx.Rng.init(0x5300);
    for (0..20) |_| {
        sow(&lv, &rng, 45, .rock, .floor);
        for (0..40) |_| lv.tile[rng.below(grid.CELLS)] = .water;
        want.tile = lv.tile;
        for (0..4) |_| {
            var next = want.tile;
            for (0..grid.CELLS) |i| {
                const t = want.tile[i];
                if (t != .rock and t != .floor) continue;
                const p = grid.Level.of(i);
                var n: usize = 0;
                var cells = grid.Cells.around(p, 1);
                while (cells.next()) |q| {
                    if (!grid.Level.inside(q) or want.at(q) == .rock) n += 1;
                }
                next[i] = if (grid.Level.onRim(p) or n >= CROWD) .rock else .floor;
            }
            want.tile = next;
        }
        smooth(&lv, 4, .rock, .floor);
        try std.testing.expectEqualSlices(grid.Tile, &want.tile, &lv.tile);
    }
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
    try std.testing.expect(lo >= 0 and hi <= 1 and hi - lo > 0.5 and jump < 0.2);
}

test "connecting hundreds of painted pockets reaches every preserved floor" {
    var lv = grid.Level.blank();
    @memset(&lv.tile, .wall);
    const painted = grid.CellSet.initFull();
    const SIDE = 17;
    for (0..SIDE) |y| for (0..SIDE) |x| {
        lv.set(.{ .x = @intCast(2 + x * 2), .y = @intCast(2 + y * 2) }, .floor);
    };
    var st = Stretches{};
    try std.testing.expectEqual(@as(usize, SIDE * SIDE), st.label(&lv));
    var rng = mathx.Rng.init(0xC011EC7);
    connect(&lv, &rng, Palette.BUILT, .{ .authored = &painted });
    try std.testing.expectEqual(@as(usize, 1), st.label(&lv));
    for (0..SIDE) |y| for (0..SIDE) |x| {
        try std.testing.expectEqual(grid.Tile.floor, lv.at(.{ .x = @intCast(2 + x * 2), .y = @intCast(2 + y * 2) }));
    };
}

test "a join beside painted ground goes round a row of chests too long to step past" {
    var lv = grid.Level.blank();
    @memset(&lv.tile, .wall);
    for (2..10) |x| for (2..grid.ROWS - 2) |y| lv.set(.{ .x = @intCast(x), .y = @intCast(y) }, .floor);
    for (30..34) |x| for (18..22) |y| lv.set(.{ .x = @intCast(x), .y = @intCast(y) }, .floor);
    for (4..grid.ROWS - 1) |y| lv.set(.{ .x = 20, .y = @intCast(y) }, .chest);
    const painted = grid.CellSet.initEmpty();
    var rng = mathx.Rng.init(7);
    connect(&lv, &rng, Palette.BUILT, .{ .authored = &painted });
    for (4..grid.ROWS - 1) |y| try std.testing.expectEqual(grid.Tile.chest, lv.at(.{ .x = 20, .y = @intCast(y) }));
    var st = Stretches{};
    try std.testing.expectEqual(@as(usize, 1), st.label(&lv));
}

test "a small island is bridged, not filled as a pocket" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x15E);
    const pal = Palette.WILD.pocketed();
    field(&lv, pal);
    disc(&lv, grid.MIDDLE, 4, .water, null);
    disc(&lv, grid.MIDDLE, 1, .grass, null);
    connect(&lv, &rng, pal, .{});
    try std.testing.expect(lv.walkable(grid.MIDDLE));
    try std.testing.expect(count(&lv, .bridge) > 0);
}

test "an island in lava or a chasm is joined by stone, which no fire burns into water" {
    for ([_]grid.Tile{ .lava, .chasm }) |liquid| {
        var lv = grid.Level.blank();
        var rng = mathx.Rng.init(0x15E);
        const pal = Palette.WILD.pocketed();
        field(&lv, pal);
        disc(&lv, grid.MIDDLE, 4, liquid, null);
        disc(&lv, grid.MIDDLE, 1, .grass, null);
        connect(&lv, &rng, pal, .{});
        try std.testing.expect(lv.walkable(grid.MIDDLE));
        try std.testing.expect(count(&lv, .stone_bridge) > 0);
        try std.testing.expectEqual(@as(usize, 0), count(&lv, .bridge));
    }
}

test "a river runs edge to edge and parts the ground, and a join bridges it" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x21E);
    field(&lv, Palette.WILD);
    const f = Flow.of(&rng, .{ .x = 0, .y = 32 }, .{ .x = grid.W - 1, .y = 30 }, 1);
    f.bank(&lv, 3, .shallows, notLiquid);
    f.fill(&lv, 3, .water, true);
    var st: Stretches = .{};
    const parted = st.label(&lv);
    connect(&lv, &rng, Palette.TRAILED, .{});
    const joined = st.label(&lv);
    try std.testing.expect(parted >= 2);
    try std.testing.expectEqual(@as(usize, 1), joined);
    try std.testing.expect(count(&lv, .bridge) > 0);
}
