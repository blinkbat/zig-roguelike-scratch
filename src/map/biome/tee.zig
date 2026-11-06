const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// An upside-down T of open ground cut from forest: woods to the west, a caravan camp where a path climbs the stem, a river bridged to the east.

const P = mathx.P;

pub const BAR_MIN: u8 = 10;
pub const BAR_MAX: u8 = 40;
pub const STEM_MIN: u8 = 6;
pub const STEM_MAX: u8 = 40;
pub const FRAY_MAX: u8 = 6;
pub const FOREST_MAX: u8 = 40;
pub const TREES_MAX: u16 = 200;
pub const CAMP_MIN: u8 = 4;
pub const CAMP_MAX: u8 = 14;
pub const CARTS_MAX: u8 = 8;
pub const BARRELS_MAX: u8 = 16;
pub const CHESTS_MAX: u8 = 4;
pub const RIVER_MAX: u8 = 30;
pub const BANK_MIN: u8 = 2;
pub const BANK_MAX: u8 = 12;
pub const BRIDGE_MAX: u8 = 9;
pub const PATH_MAX: u8 = 5;

/// Forest kept below the bar.
const FOOT: i32 = 2;
const SHIFT: i32 = 3;
const FRAY_SCALE: f32 = 5;
const THICKET_SCALE: f32 = 4;
const CAMP_SCALE: f32 = 3;
const PATH_WANDER: f32 = 0.4;
const RIVER_WANDER: f32 = 0.2;
const TRIES: usize = 60;

pub const Params = struct {
    /// Rows the crossbar is tall.
    bar: u8 = 24,
    /// Cells the stem is wide.
    stem: u8 = 26,
    /// Cells the edge wanders in or out.
    fray: u8 = 3,
    /// Cells of the crossbar, from the west, that are woods.
    forest: u8 = 24,
    /// Percent of the woods' grass at the west edge that is shrub, thinning toward the camp.
    thicket: u8 = 45,
    /// Per thousand cells of the woods' grass, a lone large tree.
    trees: u16 = 80,
    camp: u8 = 8,
    carts: u8 = 3,
    barrels: u8 = 6,
    chests: u8 = 1,
    /// Cells the river is wide; 0 for none.
    river: u8 = 22,
    /// Cells of land east of the river.
    bank: u8 = 6,
    bridge: u8 = 5,
    path: u8 = 3,
    litter: carve.Litter = .{},
    decor: carve.Decor = .{},

    pub fn fit(p: Params) Params {
        var q = p;
        q.bar = std.math.clamp(p.bar, BAR_MIN, BAR_MAX);
        q.stem = std.math.clamp(p.stem, STEM_MIN, STEM_MAX);
        q.fray = @min(p.fray, FRAY_MAX);
        q.forest = @min(p.forest, FOREST_MAX);
        q.thicket = @min(p.thicket, mathx.PERCENT);
        q.trees = @min(p.trees, TREES_MAX);
        q.camp = std.math.clamp(p.camp, CAMP_MIN, CAMP_MAX);
        q.carts = @min(p.carts, CARTS_MAX);
        q.barrels = @min(p.barrels, BARRELS_MAX);
        q.chests = @min(p.chests, CHESTS_MAX);
        q.river = @min(p.river, RIVER_MAX);
        q.bank = std.math.clamp(p.bank, BANK_MIN, BANK_MAX);
        q.bridge = std.math.clamp(p.bridge, carve.LANE_MIN, BRIDGE_MAX);
        q.path = std.math.clamp(p.path, carve.LANE_MIN, PATH_MAX);
        return q;
    }
};

pub fn palette(_: Params) carve.Palette {
    return carve.Palette.TRAILED.pocketed();
}

const TRAIL = palette(.{}).path;

const Plan = struct {
    bar: grid.Box,
    stem: grid.Box,
    camp: P,
    /// The river's westmost column, `grid.W` with none.
    river_w: i32,

    fn of(rng: *mathx.Rng, p: Params) Plan {
        const fray: i32 = p.fray;
        const out = fray + 2;
        const top = grid.H - 1 - FOOT - @as(i32, p.bar);
        const river_w = if (p.river == 0) grid.W else grid.W - 1 - @as(i32, p.bank) - @as(i32, p.river);
        const stem_x = @divTrunc(river_w, 2) + rng.range(-SHIFT, SHIFT);
        const road_y = top + @divTrunc(@as(i32, p.bar), 2) + rng.range(-1, 1);
        const half = @divTrunc(@as(i32, p.stem), 2);
        return .{
            .bar = .{ .lo = .{ .x = -out, .y = top }, .hi = .{ .x = grid.W + out, .y = grid.H - 1 - FOOT } },
            .stem = .{ .lo = .{ .x = stem_x - half, .y = -out }, .hi = .{ .x = stem_x - half + p.stem, .y = top + 1 } },
            .camp = .{ .x = stem_x, .y = road_y },
            .river_w = river_w,
        };
    }

    /// Cells in from the T's edge; under 0 outside it.
    fn depth(t: Plan, q: P) f32 {
        return @max(inFrom(t.bar, q), inFrom(t.stem, q));
    }
};

fn inFrom(b: grid.Box, q: P) f32 {
    return @floatFromInt(@min(@min(q.x - b.lo.x, b.hi.x - 1 - q.x), @min(q.y - b.lo.y, b.hi.y - 1 - q.y)));
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    const pal = palette(p);
    carve.fill(lv, pal.solid);
    const plan = Plan.of(rng, p);
    const edge = carve.Noise.init(seed, .tee);
    const fray: f32 = @floatFromInt(p.fray);
    for (0..grid.CELLS) |i| {
        const q = grid.Level.of(i);
        if (grid.Level.onRim(q)) continue;
        if (plan.depth(q) + fray * swing(edge.at(q, FRAY_SCALE, 2)) >= 0) lv.tile[i] = pal.open;
    }
    if (p.river > 0) river(lv, rng, plan, p);
    camp(lv, edge, plan.camp, p.camp);
    woods(lv, rng, seed, plan, p);
    var kept = grid.CellSet.initEmpty();
    roads(lv, rng, plan, p, &kept);
    props(lv, rng, plan.camp, p, &kept);
}

/// Summed value noise keeps near its middle; this spreads it to about -1..1.
fn swing(v: f32) f32 {
    return std.math.clamp((v - 0.5) * NOISE_GAIN, -1, 1);
}

const NOISE_GAIN: f32 = 5;

fn river(lv: *grid.Level, rng: *mathx.Rng, plan: Plan, p: Params) void {
    const r = @as(f32, @floatFromInt(p.river)) / 2;
    const x = plan.river_w + @divTrunc(@as(i32, p.river), 2) - SHIFT;
    var m = carve.Meander.init(.{ .x = x + rng.range(-SHIFT, 0), .y = 0 }, .{ .x = x + rng.range(-SHIFT, 0), .y = grid.H - 1 }, RIVER_WANDER);
    var course: [grid.CELLS]P = undefined;
    var n: usize = 0;
    while (m.next(rng)) |c| {
        course[n] = c;
        n += 1;
    }
    for (course[0..n]) |c| carve.disc(lv, c, carve.bankReach(2 * r), .shallows, dry);
    for (course[0..n]) |c| carve.disc(lv, c, r, .water, null);
}

fn dry(t: grid.Tile) bool {
    return !t.solid();
}

fn camp(lv: *grid.Level, edge: carve.Noise, c: P, radius: u8) void {
    const r: f32 = @floatFromInt(radius);
    var cells = grid.Cells.around(c, radius + 1);
    while (cells.next()) |q| {
        if (!grid.Level.inside(q) or lv.at(q).solid() or lv.at(q).wet()) continue;
        if (mathx.distEuclid(q, c) / r < 0.8 + 0.4 * edge.at(q, CAMP_SCALE, 2)) lv.set(q, TRAIL);
    }
}

fn woods(lv: *grid.Level, rng: *mathx.Rng, seed: u64, plan: Plan, p: Params) void {
    if (p.forest == 0) return;
    const clumps = carve.Noise.init(seed, .tee_woods);
    const reach: f32 = @floatFromInt(p.forest);
    var cells = grid.Box.sized(.{ .x = 1, .y = plan.bar.lo.y - p.fray }, p.forest, plan.bar.height() + p.fray).cells();
    while (cells.next()) |q| {
        if (lv.at(q) != .grass) continue;
        const thin = 1 - @as(f32, @floatFromInt(q.x)) / reach;
        if (swing(clumps.at(q, THICKET_SCALE, 2)) * 0.5 + 0.5 < mathx.fraction(p.thicket) * thin) lv.set(q, .shrub);
    }
    cells = grid.Box.sized(.{ .x = 1, .y = 1 }, p.forest, grid.H - 2).cells();
    while (cells.next()) |q| {
        if (lv.at(q) == .grass and carve.clearAround(lv, q) and rng.perMille(p.trees)) lv.set(q, .large_tree);
    }
}

fn roads(lv: *grid.Level, rng: *mathx.Rng, plan: Plan, p: Params, kept: *grid.CellSet) void {
    const c = plan.camp;
    const west = P{ .x = 0, .y = c.y + rng.range(-SHIFT, SHIFT) };
    road(lv, rng, west, c, p.path, PATH_WANDER, kept);
    const up = P{ .x = c.x + rng.range(-SHIFT, SHIFT), .y = 0 };
    road(lv, rng, c, up, p.path, PATH_WANDER, kept);
    if (p.river == 0) {
        road(lv, rng, c, .{ .x = grid.W - 1, .y = c.y }, p.path, PATH_WANDER, kept);
        return;
    }
    const span = wetSpan(lv, c) orelse return;
    const near = P{ .x = span[0] - 2, .y = c.y };
    const far = P{ .x = span[1] + 2, .y = c.y };
    road(lv, rng, c, near, p.path, PATH_WANDER, kept);
    carve.lane(lv, rng, near, far, p.bridge, 0, TRAIL, .road);
    road(lv, rng, far, .{ .x = grid.W - 1, .y = c.y }, p.path, 0, kept);
}

/// The first and last wet cells east of `from` on its row.
fn wetSpan(lv: *const grid.Level, from: P) ?[2]i32 {
    var x = from.x;
    while (x < grid.W - 1 and !lv.at(.{ .x = x, .y = from.y }).wet()) x += 1;
    var last = grid.W - 2;
    while (last > x and !lv.at(.{ .x = last, .y = from.y }).wet()) last -= 1;
    return if (x < last) .{ x, last } else null;
}

fn road(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, width: u8, wander: f32, kept: *grid.CellSet) void {
    const r = @as(f32, @floatFromInt(width - 1)) / 2 + 0.5;
    const clear: i32 = @intFromFloat(@ceil(r) + 1);
    var m = carve.Meander.init(a, b, wander);
    while (m.next(rng)) |c| {
        carve.disc(lv, c, r, TRAIL, null);
        var cells = grid.Cells.around(c, clear);
        while (cells.next()) |q| {
            if (grid.Level.inside(q)) kept.set(grid.Level.idx(q));
        }
    }
}

const Spot = struct {
    lv: *const grid.Level,
    kept: *const grid.CellSet,

    /// Camp ground off the roads, open all round.
    fn free(s: Spot, q: P) bool {
        if (!grid.Level.inside(q) or grid.Level.onRim(q)) return false;
        const i = grid.Level.idx(q);
        return s.lv.tile[i] == TRAIL and !s.kept.isSet(i) and !s.lv.barrel[i];
    }

    fn roomy(s: Spot, q: P, w: i32) bool {
        var cells = grid.Box.sized(q.sub(.{ .x = 1, .y = 1 }), w + 2, 3).cells();
        while (cells.next()) |n| {
            if (!grid.Level.inside(n) or !s.lv.walkable(n)) return false;
        }
        var feet = grid.Box.sized(q, w, 1).cells();
        while (feet.next()) |n| {
            if (!s.free(n)) return false;
        }
        return true;
    }
};

fn props(lv: *grid.Level, rng: *mathx.Rng, c: P, p: Params, kept: *const grid.CellSet) void {
    const spot = Spot{ .lv = lv, .kept = kept };
    const r: f32 = @floatFromInt(p.camp);
    var carts: [CARTS_MAX]P = undefined;
    var n: usize = 0;
    const wide = grid.Tile.caravan.wide();
    for (0..p.carts) |_| {
        const at = around(rng, c, r, wide, spot) orelse continue;
        lv.set(at, .caravan);
        var k: i32 = 1;
        while (k < wide) : (k += 1) lv.set(at.add(.{ .x = k, .y = 0 }), .caravan_part);
        carts[n] = at;
        n += 1;
    }
    for (0..p.chests) |_| {
        const at = around(rng, c, r, 1, spot) orelse continue;
        lv.set(at, .chest);
    }
    for (0..p.barrels) |_| {
        const near = if (n > 0) carts[rng.below(@intCast(n))] else c;
        const at = grid.Box.around(near, 2).rollWhere(rng, TRIES, spot, Spot.free) orelse continue;
        lv.putBarrel(at);
    }
}

fn around(rng: *mathx.Rng, c: P, r: f32, w: i32, spot: Spot) ?P {
    for (0..TRIES) |_| {
        const a = rng.unit() * std.math.tau;
        const d = rng.between(r * 0.35, r - 1);
        const q = P{ .x = c.x + @as(i32, @intFromFloat(@round(@cos(a) * d))), .y = c.y + @as(i32, @intFromFloat(@round(@sin(a) * d))) };
        if (spot.roomy(q, w)) return q;
    }
    return null;
}

fn rolled(lv: *grid.Level, seed: u64, doors: []const P, p: Params) void {
    @import("../procgen.zig").roll(lv, seed, doors, .{ .tee = p }, &.{});
}

const RUNS: usize = 100;

/// Dry cells east of the bridge on its middle row, up to the rim.
fn farBank(lv: *const grid.Level) i32 {
    var lo: ?P = null;
    var hi: ?P = null;
    for (lv.tile, 0..) |t, k| {
        if (t != .bridge) continue;
        const q = grid.Level.of(k);
        if (lo == null) lo = q;
        hi = q;
    }
    const y = @divTrunc(lo.?.y + hi.?.y, 2);
    var x = grid.W - 2;
    var n: i32 = 0;
    while (x > 0 and !lv.at(.{ .x = x, .y = y }).wet() and lv.at(.{ .x = x, .y = y }) != .bridge) : (x -= 1) n += 1;
    return n;
}

test "a tee stays shut outside its T, and lays its camp, woods and bridge" {
    var lv: grid.Level = undefined;
    const p = (Params{}).fit();
    const door = [_]P{.{ .x = 0, .y = 46 }};
    var corner_open: usize = 0;
    var carts: usize = 0;
    var bridged: usize = 0;
    var trees: usize = 0;
    var barrels: usize = 0;
    var bank: i32 = grid.W;
    for (0..RUNS) |i| {
        rolled(&lv, 0x7EE +% i *% grid.TEST_SEED_STRIDE, &door, p);
        bank = @min(bank, farBank(&lv));
        for ([_]grid.Box{ grid.Box.sized(.{ .x = 1, .y = 1 }, 8, 20), grid.Box.sized(.{ .x = grid.W - 9, .y = 1 }, 8, 20) }) |b| {
            var cells = b.cells();
            while (cells.next()) |q| corner_open += @intFromBool(lv.walkable(q));
        }
        carts += carve.count(&lv, .caravan);
        bridged += @intFromBool(carve.count(&lv, .bridge) > 0);
        trees += carve.count(&lv, .large_tree);
        for (lv.barrel) |b| barrels += @intFromBool(b);
    }
    std.debug.print("{d} tees: {d} open cells in the upper corners, {d} of {d} carts, {d} bridged, {d} large trees and {d} barrels a map, a far bank {d} cells at the least of {d}\n", .{ RUNS, corner_open, carts, RUNS * p.carts, bridged, trees / RUNS, barrels / RUNS, bank, p.bank });
    try std.testing.expectEqual(@as(usize, 0), corner_open);
    try std.testing.expect(bank * 2 >= p.bank);
    try std.testing.expectEqual(RUNS, bridged);
    try std.testing.expect(carts * 10 >= RUNS * p.carts * 9);
    try std.testing.expect(trees > RUNS and barrels > RUNS);
}

test "a tee's carts stand whole and its roads reach the west, north and east edges" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const p = (Params{}).fit();
    var reached: [3]usize = @splat(0);
    for (0..RUNS) |i| {
        var rng = mathx.Rng.init(0x7EF +% i);
        @import("../procgen.zig").lay(@This(), &lv, &rng, 0x7EF +% i, p);
        try std.testing.expect(grid.propsWhole(&lv.tile));
        const ends = [_]grid.Box{
            grid.Box.sized(.{ .x = 1, .y = 1 }, 1, grid.H - 2),
            grid.Box.sized(.{ .x = 1, .y = 1 }, grid.W - 2, 1),
            grid.Box.sized(.{ .x = grid.W - 2, .y = 1 }, 1, grid.H - 2),
        };
        const from = for (0..grid.CELLS) |k| {
            if (lv.tile[k] == .bridge) break grid.Level.of(k);
        } else return error.NoBridge;
        _ = grid.distances(&lv, from, &dist, &queue);
        for (ends, &reached) |b, *got| {
            var cells = b.cells();
            while (cells.next()) |q| {
                if (dist[grid.Level.idx(q)] >= 0) {
                    got.* += 1;
                    break;
                }
            }
        }
    }
    std.debug.print("{d} tees: the bridge walks to the west edge {d}, the north {d}, the east {d} times\n", .{ RUNS, reached[0], reached[1], reached[2] });
    for (reached) |got| try std.testing.expectEqual(RUNS, got);
}
