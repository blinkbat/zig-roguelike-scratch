const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");

const P = mathx.P;

/// Of its 3x3, at least this many solid turns a cell solid on a smoothing pass, the cave rule's.
const CROWD: usize = 5;
/// A pocket of open ground this small, holding no door, is filled; a bigger one gets a trail.
pub const POCKET: usize = 16;
const JOIN_PASSES: usize = 160;
const NONE = std.math.maxInt(u16);
const NO_CELL = std.math.maxInt(u32);
/// A river's turn a step, at most, in radians.
const MEANDER: f32 = 0.55;
const RIVER_STEPS: usize = 4 * (grid.W + grid.H);

pub fn chance(rng: *mathx.Rng, per_mille: u32) bool {
    return rng.below(mathx.MILLE) < per_mille;
}

pub fn percent(rng: *mathx.Rng, pc: u32) bool {
    return rng.below(mathx.PERCENT) < pc;
}

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
        const fx = @floor(x);
        const fy = @floor(y);
        const ix: i32 = @intFromFloat(fx);
        const iy: i32 = @intFromFloat(fy);
        const tx = mathx.smooth(x - fx);
        const ty = mathx.smooth(y - fy);
        const top = mathx.lerpF(self.lattice(ix, iy), self.lattice(ix + 1, iy), tx);
        const bottom = mathx.lerpF(self.lattice(ix, iy + 1), self.lattice(ix + 1, iy + 1), tx);
        return mathx.lerpF(top, bottom, ty);
    }

    /// At a cell, its features about `scale` cells across, finer octaves on them.
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

/// Every cell inside the rim `solid` at `pc` percent, else `open`; the rim `solid`.
pub fn sow(lv: *grid.Level, rng: *mathx.Rng, pc: u32, solid: grid.Tile, open: grid.Tile) void {
    for (0..grid.CELLS) |i| {
        lv.tile[i] = if (grid.Level.onRim(grid.Level.of(i)) or percent(rng, pc)) solid else open;
    }
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

/// On `on` cells, `put` at `per_mille`; `lone` only where it closes no way.
pub fn scatter(lv: *grid.Level, rng: *mathx.Rng, per_mille: u32, on: grid.Tile, put: grid.Tile, lone: bool) void {
    for (0..grid.CELLS) |i| {
        if (lv.tile[i] != on) continue;
        const p = grid.Level.of(i);
        if (grid.Level.onRim(p) or (lone and !clearAround(lv, p))) continue;
        if (chance(rng, per_mille)) lv.tile[i] = put;
    }
}

/// Every cell within `r` of `c`, a circle as near as cells make one, over the tiles `over` allows.
pub fn disc(lv: *grid.Level, c: P, r: f32, t: grid.Tile, comptime over: ?fn (grid.Tile) bool) void {
    const k: i32 = @intFromFloat(@ceil(r));
    var cells = grid.Cells.around(c, k);
    while (cells.next()) |q| {
        if (grid.Level.onRim(q)) continue;
        const dx: f32 = @floatFromInt(q.x - c.x);
        const dy: f32 = @floatFromInt(q.y - c.y);
        if (dx * dx + dy * dy > r * r + 0.25) continue;
        if (over) |ok| {
            if (!ok(lv.at(q))) continue;
        }
        lv.set(q, t);
    }
}

pub fn box(lv: *grid.Level, lo: P, hi: P, t: grid.Tile) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |q| lv.set(q, t);
}

/// Each door opened on `ground`, and the cell inside an edge door too.
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

/// What a trail lays, and what fills a small doorless pocket; null gives every pocket a trail.
pub const Join = struct { path: grid.Tile, pocket: ?grid.Tile = null };

/// A base's own ground, which its features and the finishing passes draw from.
pub const Palette = struct {
    open: grid.Tile,
    solid: grid.Tile,
    path: grid.Tile,
    pocket: ?grid.Tile = null,

    /// Floor walled round, as the rooms are.
    pub const BUILT = Palette{ .open = .floor, .solid = .wall, .path = .floor };
    /// Dirt in rock.
    pub const CAVE = Palette{ .open = .dirt, .solid = .rock, .path = .dirt };
};

/// Every stretch of open ground joined to the biggest by a bending trail that bridges water and lava.
pub fn connect(lv: *grid.Level, rng: *mathx.Rng, j: Join) void {
    var region: [grid.CELLS]u16 = undefined;
    var size: [grid.CELLS]u32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    for (0..JOIN_PASSES) |_| {
        const n = label(lv, &region, &size, &queue);
        if (n <= 1) return;
        const main = biggest(size[0..n]);
        const doored = doorsIn(lv, &region);
        var first: [grid.CELLS]u32 = undefined;
        @memset(first[0..n], NO_CELL);
        for (0..grid.CELLS) |i| {
            const r = region[i];
            if (r == NONE or r == main) continue;
            if (j.pocket) |fill_with| {
                if (size[r] < POCKET and !doored.isSet(r)) {
                    lv.tile[i] = fill_with;
                    continue;
                }
            }
            if (first[r] == NO_CELL) first[r] = @intCast(i);
        }
        for (first[0..n]) |orphan| {
            if (orphan == NO_CELL) continue;
            const from = grid.Level.inset(grid.Level.of(orphan));
            var best: ?P = null;
            var best_d: i32 = std.math.maxInt(i32);
            for (0..grid.CELLS) |i| {
                const q = grid.Level.of(i);
                if (region[i] != main or grid.Level.onRim(q)) continue;
                const d = mathx.dist(q, from);
                if (d < best_d) {
                    best_d = d;
                    best = q;
                }
            }
            trail(lv, rng, from, best orelse return, j.path);
        }
    }
}

/// The stretch with the most cells, the first of any tie.
fn biggest(size: []const u32) u16 {
    var main: u16 = 0;
    for (size[1..], 1..) |n, r| {
        if (n > size[main]) main = @intCast(r);
    }
    return main;
}

/// Each open cell's stretch of ground, as a step walks it; how many stretches.
pub fn label(lv: *const grid.Level, region: *[grid.CELLS]u16, size: *[grid.CELLS]u32, queue: *[grid.CELLS]u32) usize {
    return labelBy(lv, region, size, queue, false);
}

fn labelBy(lv: *const grid.Level, region: *[grid.CELLS]u16, size: *[grid.CELLS]u32, queue: *[grid.CELLS]u32, comptime barred: bool) usize {
    @memset(region, NONE);
    var n: u16 = 0;
    for (0..grid.CELLS) |s| {
        if (region[s] != NONE or lv.tile[s].solid() or (barred and lv.barrel[s])) continue;
        region[s] = n;
        queue[0] = @intCast(s);
        var head: usize = 0;
        var tail: usize = 1;
        while (head < tail) : (head += 1) {
            const here = grid.Level.of(queue[head]);
            for (mathx.ALL_DIRS) |d| {
                if (!lv.passOk(here, d)) continue;
                const k = grid.Level.idx(here.add(d.delta()));
                if (region[k] != NONE or (barred and lv.barrel[k])) continue;
                region[k] = n;
                queue[tail] = @intCast(k);
                tail += 1;
            }
        }
        size[n] = @intCast(tail);
        n += 1;
    }
    return n;
}

/// Barrels taken away, one a pass, each beside ground they cut off from the biggest stretch, till none does.
pub fn unbar(lv: *grid.Level) void {
    var region: [grid.CELLS]u16 = undefined;
    var size: [grid.CELLS]u32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    while (true) {
        const n = labelBy(lv, &region, &size, &queue, true);
        if (n <= 1) return;
        const main = biggest(size[0..n]);
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

pub fn anyOpen(lv: *const grid.Level) bool {
    for (lv.tile) |t| {
        if (!t.solid()) return true;
    }
    return false;
}

/// The stretches holding a door.
fn doorsIn(lv: *const grid.Level, region: *const [grid.CELLS]u16) Regions {
    var out = Regions.initEmpty();
    for (0..grid.CELLS) |i| {
        if (lv.door[i] != grid.NO_DOOR and region[i] != NONE) out.set(region[i]);
    }
    return out;
}

const Regions = std.StaticBitSet(grid.CELLS);

/// Side steps from `a` to `b` picked at random, never leaving their box; solid becomes `path`, water and lava a bridge.
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
    if (t.liquid()) lv.set(p, .bridge) else if (t.solid()) lv.set(p, path);
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

/// From edge to edge: `fill` `width` across, `bank` a cell either side over whatever is not liquid.
pub fn river(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, width: f32, fill_with: grid.Tile, bank: ?grid.Tile, bed: ?*Bed) void {
    var m = Meander.init(a, b, 1);
    while (m.next(rng)) |c| {
        if (bed) |k| k.add(c);
        if (bank) |bk| disc(lv, c, width / 2 + 1, bk, notLiquid);
        discAll(lv, c, width / 2, fill_with);
    }
}

fn notLiquid(t: grid.Tile) bool {
    return !t.liquid();
}

/// `disc`, the rim too, so a river runs off the map.
pub fn discAll(lv: *grid.Level, c: P, r: f32, t: grid.Tile) void {
    const k: i32 = @intFromFloat(@ceil(r));
    var cells = grid.Cells.around(c, k);
    while (cells.next()) |q| {
        const dx: f32 = @floatFromInt(q.x - c.x);
        const dy: f32 = @floatFromInt(q.y - c.y);
        if (dx * dx + dy * dy <= r * r + 0.25) lv.set(q, t);
    }
}

/// A cell on the map's edge: `side` 0 west, 1 east, 2 north, 3 south, somewhere along its middle half.
pub fn edge(rng: *mathx.Rng, side: u32) P {
    return switch (side % 4) {
        0 => .{ .x = 0, .y = rng.range(@divTrunc(grid.H, 4), @divTrunc(grid.H * 3, 4)) },
        1 => .{ .x = grid.W - 1, .y = rng.range(@divTrunc(grid.H, 4), @divTrunc(grid.H * 3, 4)) },
        2 => .{ .x = rng.range(@divTrunc(grid.W, 4), @divTrunc(grid.W * 3, 4)), .y = 0 },
        else => .{ .x = rng.range(@divTrunc(grid.W, 4), @divTrunc(grid.W * 3, 4)), .y = grid.H - 1 },
    };
}

pub const Course = enum {
    across,
    down,
    any,

    /// Its two ends, on opposite edges.
    pub fn ends(c: Course, rng: *mathx.Rng) [2]P {
        const side: u32 = switch (c) {
            .across => rng.below(2),
            .down => 2 + rng.below(2),
            .any => rng.below(4),
        };
        return .{ edge(rng, side), edge(rng, side ^ 1) };
    }
};

pub const LITTER_MAX: u16 = 100;

/// Lone tiny shrubs and boulders strewn over open grass, each where it closes no way.
pub const Litter = struct {
    /// Per thousand cells of open grass.
    tiny_shrubs: u16 = 12,
    boulders: u16 = 4,

    pub fn fit(l: Litter) Litter {
        return .{ .tiny_shrubs = @min(l.tiny_shrubs, LITTER_MAX), .boulders = @min(l.boulders, LITTER_MAX) };
    }

    pub fn strew(l: Litter, lv: *grid.Level, rng: *mathx.Rng) void {
        scatter(lv, rng, l.tiny_shrubs, .grass, .tiny_shrub, true);
        scatter(lv, rng, l.boulders, .grass, .boulder, true);
    }
};

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
pub fn clumps(lv: *grid.Level, noise: Noise, scale: f32, per_mille: u32, on: grid.Tile, put: grid.Tile) void {
    const BUCKETS = 256;
    var hist = [_]u32{0} ** BUCKETS;
    var n: u32 = 0;
    for (0..grid.CELLS) |i| {
        if (lv.tile[i] != on or grid.Level.onRim(grid.Level.of(i))) continue;
        hist[bucket(noise.at(grid.Level.of(i), scale, 3), BUCKETS)] += 1;
        n += 1;
    }
    const want = n * @min(per_mille, mathx.MILLE) / mathx.MILLE;
    var cut: usize = BUCKETS;
    var taken: u32 = 0;
    while (cut > 0 and taken + hist[cut - 1] <= want) : (cut -= 1) taken += hist[cut - 1];
    for (0..grid.CELLS) |i| {
        if (lv.tile[i] != on or grid.Level.onRim(grid.Level.of(i))) continue;
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

test "a river runs edge to edge and parts the ground, and a join bridges it" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x21E);
    fill(&lv, .grass);
    rim(&lv, .shrub);
    river(&lv, &rng, .{ .x = 0, .y = 32 }, .{ .x = grid.W - 1, .y = 30 }, 3, .water, .shallows, null);
    var region: [grid.CELLS]u16 = undefined;
    var size: [grid.CELLS]u32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const parted = label(&lv, &region, &size, &queue);
    connect(&lv, &rng, .{ .path = .dirt });
    const joined = label(&lv, &region, &size, &queue);
    std.debug.print("a river: {d} water cells, the ground in {d} parts, {d} after joining by {d} bridge cells\n", .{ count(&lv, .water), parted, joined, count(&lv, .bridge) });
    try std.testing.expect(parted >= 2);
    try std.testing.expectEqual(@as(usize, 1), joined);
    try std.testing.expect(count(&lv, .bridge) > 0);
}
