const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");
const setpiece = @import("../feature/setpiece.zig");

// An upside-down T of open ground cut from forest: woods to the west, a caravan camp where a path climbs the stem, a river bridged to the east.
// Winding trails may lead off it into the forest, a crescent pond hold chests waded out to, and small goblin camps keep away from the carts.

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
pub const SPURS_MAX: u8 = 8;
pub const POND_MIN: u8 = 4;
pub const POND_MAX: u8 = 8;
pub const POND_CHESTS_MAX: u8 = 4;
pub const CAMPS_MAX: u8 = 3;

/// Forest kept below the bar.
const FOOT: i32 = 2;
/// The first row of the foot, just below the bar.
const BAR_FLOOR: i32 = grid.H - 1 - FOOT;
const SHIFT: i32 = 3;
const FRAY_SCALE: f32 = 5;
const THICKET_SCALE: f32 = 4;
const CAMP_SCALE: f32 = 3;
const CAMP_LO: f32 = 0.8;
const CAMP_SPAN: f32 = 0.4;
const PATH_WANDER: f32 = 0.4;
const RIVER_WANDER: f32 = 0.2;
const TRIES: usize = 60;
const OVERHANG: i32 = 2;
const ROAD_JITTER: i32 = 1;
const LANDING: i32 = 2;
const KEEP_CLEAR: f32 = 1;
const BARREL_REACH: i32 = 2;
const PROP_NEAR: f32 = 0.35;
const PROP_EDGE: f32 = 1;
const SPUR_WIDTH: u8 = carve.LANE_MIN;
const SPUR_SHORTEST: i32 = 8;
const SPUR_LONGEST: i32 = 16;
/// Forest a trail needs ahead of it to start.
const SPUR_INTO: i32 = 4;
const SPUR_WANDER: f32 = 1;
const SPUR_BOX = grid.Box.inMap(2);
const GLADE_R: f32 = 2;
const GLADE_PERCENT: u8 = 35;
/// Of the pond's radius, the hollow cut from its disc to leave a crescent, and how far that hollow sits off its middle.
const HOLLOW: f32 = 0.7;
const HOLLOW_OFF: f32 = 0.6;
/// Cells in from the crescent's edge where the water is deep.
const DEEP: f32 = 0.6;
/// Cells past the disc's edge kept dry, so no other water joins the pond.
const WATER_APART: f32 = 2;
const POND_TRIES: usize = 400;
const SITE_TRIES: usize = 400;
const CHEST_APART: i32 = 3;
/// Cells from the caravan camp's edge to a pond's or a goblin camp's, at least.
const CLEAR_OF_CARTS: i32 = 12;
const CAMP_ART = setpiece.rows(.camp);

comptime {
    std.debug.assert(CLEAR_OF_CARTS > @import("../../play/pack.zig").CAMP_GAP);
}

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
    /// Winding trails off the T into the forest, each ending narrow or in a small glade.
    spurs: u8 = 0,
    /// The crescent pond's radius; 0 for none.
    pond: u8 = 0,
    /// Chests standing out in the pond, each with shallows to wade out by.
    pond_chests: u8 = 0,
    /// Small goblin camps, off the roads and away from the carts.
    camps: u8 = 0,
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
        q.spurs = @min(p.spurs, SPURS_MAX);
        q.pond = if (p.pond == 0) 0 else std.math.clamp(p.pond, POND_MIN, POND_MAX);
        q.pond_chests = @min(p.pond_chests, POND_CHESTS_MAX);
        q.camps = @min(p.camps, CAMPS_MAX);
        return q;
    }
};

pub fn palette(_: Params) carve.Palette {
    return PAL;
}

const PAL = carve.Palette.TRAILED.pocketed();
const TRAIL = PAL.path;
const SOLID = PAL.solid;
const OPEN = PAL.open;
/// Where a pond or goblin camp may lie, or a trail lead: off the rim and above the foot.
const ABOVE_FOOT = grid.Box{ .lo = .{ .x = 1, .y = 1 }, .hi = .{ .x = grid.W - 1, .y = BAR_FLOOR - 1 } };
/// The camp's river crossing, which no fire takes down.
const CROSSING: grid.Tile = .stone_bridge;

const Plan = struct {
    bar: grid.Box,
    stem: grid.Box,
    camp: P,
    /// Where the river and its far bank begin, in from the east rim; `grid.W` with none.
    river_w: i32,

    fn of(rng: *mathx.Rng, p: Params) Plan {
        const fray: i32 = p.fray;
        const out = fray + OVERHANG;
        const top = BAR_FLOOR - @as(i32, p.bar);
        const river_w = if (p.river == 0) grid.W else grid.W - 1 - @as(i32, p.bank) - @as(i32, p.river);
        const stem_x = @divTrunc(river_w, 2) + rng.range(-SHIFT, SHIFT);
        const road_y = @min(top + @divTrunc(@as(i32, p.bar), 2) + rng.range(-ROAD_JITTER, ROAD_JITTER), lowestFor(@max(p.path, p.bridge)));
        const half = @divTrunc(@as(i32, p.stem), 2);
        return .{
            .bar = .{ .lo = .{ .x = -out, .y = top }, .hi = .{ .x = grid.W + out, .y = BAR_FLOOR } },
            .stem = .{ .lo = .{ .x = stem_x - half, .y = -out }, .hi = .{ .x = stem_x - half + p.stem, .y = top + 1 } },
            .camp = .{ .x = stem_x, .y = road_y },
            .river_w = river_w,
        };
    }

    /// Cells in from the T's edge; under 0 outside it.
    fn depth(t: Plan, q: P) f32 {
        return @floatFromInt(@max(t.bar.edgeDist(q), t.stem.edgeDist(q)));
    }
};

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    carve.fill(lv, SOLID);
    const plan = Plan.of(rng, p);
    const edge = carve.Noise.init(seed, .tee);
    const fray: f32 = @floatFromInt(p.fray);
    for (0..grid.CELLS) |i| {
        const q = grid.Level.of(i);
        if (grid.Level.onRim(q) or q.y >= plan.bar.hi.y) continue;
        if (plan.depth(q) + fray * swing(edge.at(q, FRAY_SCALE, 2)) >= 0) lv.tile[i] = OPEN;
    }
    if (p.river > 0) river(lv, rng, plan, p);
    camp(lv, edge, plan.camp, p.camp);
    woods(lv, rng, seed, plan, p);
    var kept = grid.CellSet.initEmpty();
    roads(lv, rng, plan, p, &kept);
    props(lv, rng, plan.camp, p, &kept);
    if (p.pond > 0) pond(lv, rng, plan.camp, p, &kept);
    goblinCamps(lv, rng, plan.camp, p, &kept);
    for (0..p.spurs) |_| spur(lv, rng);
}

/// Summed value noise keeps near its middle; this spreads it to about -1..1.
fn swing(v: f32) f32 {
    return std.math.clamp((v - 0.5) * NOISE_GAIN, -1, 1);
}

const NOISE_GAIN: f32 = 5;

fn river(lv: *grid.Level, rng: *mathx.Rng, plan: Plan, p: Params) void {
    const x = plan.river_w + @divTrunc(@as(i32, p.river), 2) - SHIFT;
    var f = carve.Flow.of(rng, .{ .x = x + rng.range(-SHIFT, 0), .y = 0 }, .{ .x = x + rng.range(-SHIFT, 0), .y = grid.H - 1 }, RIVER_WANDER);
    for (f.cell[0..f.n]) |*c| c.x = @min(c.x, x);
    const width: f32 = @floatFromInt(p.river);
    f.bank(lv, width, .shallows, dry);
    f.fill(lv, width, .water, false);
}

fn dry(t: grid.Tile) bool {
    return !t.solid();
}

fn camp(lv: *grid.Level, edge: carve.Noise, c: P, radius: u8) void {
    const r: f32 = @floatFromInt(radius);
    carve.blobIn(lv, edge, c, r, CAMP_SCALE, CAMP_LO, CAMP_SPAN, TRAIL, carve.blobBox(c, r, CAMP_LO, CAMP_SPAN), campable);
}

fn campable(t: grid.Tile) bool {
    return !t.solid() and !t.wet();
}

fn woods(lv: *grid.Level, rng: *mathx.Rng, seed: u64, plan: Plan, p: Params) void {
    if (p.forest == 0) return;
    const clumps = carve.Noise.init(seed, .tee_woods);
    const reach: f32 = @floatFromInt(p.forest);
    const wood = grid.Box.sized(.{ .x = 1, .y = plan.bar.lo.y - p.fray }, p.forest, plan.bar.height() + p.fray);
    var cells = wood.cells();
    while (cells.next()) |q| {
        if (lv.at(q) != OPEN) continue;
        const thin = 1 - @as(f32, @floatFromInt(q.x)) / reach;
        if (rise(clumps.at(q, THICKET_SCALE, 2)) < mathx.fraction(p.thicket) * thin) lv.set(q, SOLID);
    }
    carve.scatterIn(lv, rng, p.trees, .{ .tile = OPEN }, .large_tree, true, wood);
}

fn rise(v: f32) f32 {
    return swing(v) * 0.5 + 0.5;
}

fn roads(lv: *grid.Level, rng: *mathx.Rng, plan: Plan, p: Params, kept: *grid.CellSet) void {
    const c = plan.camp;
    const lowest = lowestFor(p.path);
    const west = P{ .x = 0, .y = c.y + rng.range(-SHIFT, SHIFT) };
    road(lv, rng, west, c, p.path, PATH_WANDER, lowest, kept);
    const up = P{ .x = c.x + rng.range(-SHIFT, SHIFT), .y = 0 };
    road(lv, rng, c, up, p.path, PATH_WANDER, lowest, kept);
    if (p.river == 0) {
        road(lv, rng, c, .{ .x = grid.W - 1, .y = c.y }, p.path, PATH_WANDER, lowest, kept);
        return;
    }
    const span = wetSpan(lv, c) orelse return;
    const near = P{ .x = span[0] - LANDING, .y = c.y };
    const far = P{ .x = span[1] + LANDING, .y = c.y };
    road(lv, rng, c, near, p.path, PATH_WANDER, lowest, kept);
    carve.lane(lv, rng, near, far, p.bridge, 0, TRAIL, .{ .road = CROSSING });
    road(lv, rng, far, .{ .x = grid.W - 1, .y = c.y }, p.path, 0, lowest, kept);
}

/// The first and last wet cells east of `from` on its row.
fn wetSpan(lv: *const grid.Level, from: P) ?[2]i32 {
    var x = from.x;
    while (x < grid.W - 1 and !lv.at(.{ .x = x, .y = from.y }).wet()) x += 1;
    var last = grid.W - 2;
    while (last > x and !lv.at(.{ .x = last, .y = from.y }).wet()) last -= 1;
    return if (x < last) .{ x, last } else null;
}

/// The lowest row a lane of `width` can run along without paving the foot.
fn lowestFor(width: u8) i32 {
    return BAR_FLOOR - 1 - carve.discReach(carve.laneRadius(width));
}

fn road(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, width: u8, wander: f32, lowest: i32, kept: *grid.CellSet) void {
    const r = carve.laneRadius(width);
    const clear: i32 = @intFromFloat(@ceil(r) + KEEP_CLEAR);
    const above = grid.Box{ .lo = .{ .x = std.math.minInt(i32), .y = std.math.minInt(i32) }, .hi = .{ .x = std.math.maxInt(i32), .y = lowest + 1 } };
    var m = carve.Meander.init(a, b, wander).within(above);
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
        if (grid.Level.onRim(q)) return false;
        const i = grid.Level.idx(q);
        return s.lv.tile[i] == TRAIL and !s.kept.isSet(i) and !s.lv.barrel[i];
    }

    fn roomy(s: Spot, q: P, t: grid.Tile) bool {
        const foot = t.footprint(q);
        var cells = foot.grown(1).cells();
        while (cells.next()) |n| {
            if (!s.lv.walkable(n)) return false;
        }
        var feet = foot.cells();
        while (feet.next()) |n| {
            if (!s.free(n)) return false;
        }
        return true;
    }
};

fn props(lv: *grid.Level, rng: *mathx.Rng, c: P, p: Params, kept: *const grid.CellSet) void {
    const spot = Spot{ .lv = lv, .kept = kept };
    const r: f32 = @floatFromInt(p.camp);
    var carts = grid.Bounded(P, CARTS_MAX){};
    for (0..p.carts) |_| {
        const at = around(rng, c, r, .caravan, spot) orelse continue;
        lv.putProp(at, .caravan);
        carts.push(at);
    }
    for (0..p.chests) |_| {
        const at = around(rng, c, r, .chest, spot) orelse continue;
        lv.set(at, .chest);
    }
    for (0..p.barrels) |_| {
        const near = if (carts.n > 0) rng.pick(P, carts.slice()) else c;
        const at = grid.Box.around(near, BARREL_REACH).rollWhere(rng, TRIES, spot, Spot.free) orelse continue;
        lv.putBarrel(at);
    }
}

fn around(rng: *mathx.Rng, c: P, r: f32, t: grid.Tile, spot: Spot) ?P {
    for (0..TRIES) |_| {
        const a = rng.angle();
        const d = rng.between(r * PROP_NEAR, r - PROP_EDGE);
        const q = c.add(mathx.roundCell(@cos(a) * d, @sin(a) * d));
        if (spot.roomy(q, t)) return q;
    }
    return null;
}

fn forest(t: grid.Tile) bool {
    return t == SOLID;
}

/// A disc of radius `r` about `c` with a hollow cut from one side, leaving a crescent.
const Crescent = struct {
    c: P,
    r: f32,
    hollow_x: f32,
    hollow_y: f32,

    fn of(c: P, r: f32, angle: f32) Crescent {
        const cx: f32 = @floatFromInt(c.x);
        const cy: f32 = @floatFromInt(c.y);
        return .{ .c = c, .r = r, .hollow_x = cx + @cos(angle) * r * HOLLOW_OFF, .hollow_y = cy + @sin(angle) * r * HOLLOW_OFF };
    }

    /// Cells in from its nearer edge; under 0 outside it.
    fn depth(s: Crescent, q: P) f32 {
        return @min(s.inDisc(q), s.inHollow(q) - s.r * HOLLOW);
    }

    /// Cells in from the disc's edge.
    fn inDisc(s: Crescent, q: P) f32 {
        return s.r - mathx.distEuclid(q, s.c);
    }

    /// Cells from the hollow's middle.
    fn inHollow(s: Crescent, q: P) f32 {
        return mathx.len(@as(f32, @floatFromInt(q.x)) - s.hollow_x, @as(f32, @floatFromInt(q.y)) - s.hollow_y);
    }

    /// The water, the hollow it curls round, and a cell of shore beyond.
    fn reaches(s: Crescent, q: P) bool {
        return s.inDisc(q) >= -1;
    }

    fn box(s: Crescent) grid.Box {
        return grid.Box.around(s.c, @as(i32, @intFromFloat(@ceil(s.r))) + 1);
    }

    fn hollow(s: Crescent) P {
        return mathx.roundCell(s.hollow_x, s.hollow_y);
    }
};

/// Grass, forest or a lone tree: ground a pond or a goblin camp may be laid over.
fn layable(t: grid.Tile) bool {
    return t == OPEN or t == SOLID or t == .large_tree;
}

/// Ground a pond or a goblin camp may be laid over, at least `clear` from the caravan camp's middle.
const Site = struct {
    lv: *const grid.Level,
    kept: *const grid.CellSet,
    caravan: P,
    clear: i32,

    fn nearCarts(s: Site, c: P) bool {
        return mathx.dist(c, s.caravan) < s.clear;
    }

    /// Above the foot, off the roads, the bridge and anything standing, over grass, forest or a lone tree.
    fn layableAt(s: Site, q: P) bool {
        if (!ABOVE_FOOT.holds(q)) return false;
        const i = grid.Level.idx(q);
        return !s.kept.isSet(i) and !s.lv.barrel[i] and layable(s.lv.tile[i]);
    }

    /// A goblin camp's art with its corner at `lo`, and a cell round it.
    fn campFits(s: Site, lo: P) bool {
        const b = grid.Box.sizedP(lo, setpiece.size(CAMP_ART));
        if (s.nearCarts(b.centre())) return false;
        var cells = b.grown(1).cells();
        while (cells.next()) |q| {
            if (!s.layableAt(q)) return false;
        }
        return true;
    }
};

/// Where the pond may lie: on `Site` ground, apart from other water so it stays a pond of its own,
/// and with some of its shore on the T's grass so nothing need be cut to it.
const PondSite = struct {
    site: Site,
    r: f32,
    angle: f32,

    fn fits(s: PondSite, c: P) bool {
        if (s.site.nearCarts(c)) return false;
        const pond_at = Crescent.of(c, s.r, s.angle);
        var shore = false;
        var cells = pond_at.box().grown(1).cells();
        while (cells.next()) |q| {
            const into = pond_at.inDisc(q);
            if (into < -WATER_APART) continue;
            if (s.site.lv.at(q).wet()) return false;
            if (!pond_at.reaches(q)) continue;
            if (!s.site.layableAt(q)) return false;
            shore = shore or (into < 0 and s.site.lv.at(q) == OPEN);
        }
        return shore;
    }
};

/// A crescent of water in a clearing of its own, deep in from its edge, with chests out in it.
fn pond(lv: *grid.Level, rng: *mathx.Rng, caravan: P, p: Params, kept: *grid.CellSet) void {
    const r: f32 = @floatFromInt(p.pond);
    const angle = rng.angle();
    const site = PondSite{ .site = .{ .lv = lv, .kept = kept, .caravan = caravan, .clear = @as(i32, p.camp) + p.pond + CLEAR_OF_CARTS }, .r = r, .angle = angle };
    const c = grid.Box.inMap(p.pond + 1).rollWhere(rng, POND_TRIES, site, PondSite.fits) orelse return;
    const s = Crescent.of(c, r, angle);
    var cells = s.box().cells();
    while (cells.next()) |q| {
        if (!s.reaches(q)) continue;
        kept.set(grid.Level.idx(q));
        const d = s.depth(q);
        lv.set(q, if (d >= DEEP) .water else if (d >= 0) .shallows else OPEN);
    }
    var chests = grid.Bounded(P, POND_CHESTS_MAX){};
    for (0..p.pond_chests) |_| {
        const at = s.box().rollWhere(rng, TRIES, ChestSite{ .lv = lv, .chests = chests.slice() }, ChestSite.fits) orelse continue;
        chests.push(at);
        wade(lv, at, s.hollow());
        lv.set(at, .chest);
    }
}

const ChestSite = struct {
    lv: *const grid.Level,
    chests: []const P,

    /// Deep water with water all round it, apart from the other chests.
    fn fits(s: ChestSite, q: P) bool {
        if (!grid.Level.inside(q) or s.lv.at(q) != .water) return false;
        for (s.chests) |c| if (mathx.dist(c, q) < CHEST_APART) return false;
        var round = grid.Cells.around(q, 1);
        while (round.next()) |n| if (!s.lv.at(n).wet()) return false;
        return true;
    }
};

/// Shallows round `at` and on to dry ground toward `shore`, so it is waded out to.
fn wade(lv: *grid.Level, at: P, shore: P) void {
    var cells = grid.Cells.around(at, 1);
    while (cells.next()) |q| {
        if (grid.Level.inside(q) and lv.at(q) == .water) lv.set(q, .shallows);
    }
    const dx: f32 = @floatFromInt(shore.x - at.x);
    const dy: f32 = @floatFromInt(shore.y - at.y);
    const steps: usize = @intFromFloat(@ceil(@max(@abs(dx), @abs(dy))));
    for (1..steps + 1) |k| {
        const f = @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(steps));
        const q = P{ .x = at.x + @as(i32, @intFromFloat(@round(dx * f))), .y = at.y + @as(i32, @intFromFloat(@round(dy * f))) };
        const t = lv.at(q);
        if (!t.wet()) return;
        if (t == .water) lv.set(q, .shallows);
    }
}

fn goblinCamps(lv: *grid.Level, rng: *mathx.Rng, caravan: P, p: Params, kept: *grid.CellSet) void {
    const size = setpiece.size(CAMP_ART);
    const half = @divTrunc(@max(size.x, size.y), 2);
    const site = Site{ .lv = lv, .kept = kept, .caravan = caravan, .clear = @as(i32, p.camp) + CLEAR_OF_CARTS + half };
    for (0..p.camps) |_| {
        const at = grid.Box.inMap(2).rollForWhere(rng, size.x, size.y, SITE_TRIES, site, Site.campFits) orelse continue;
        setpiece.place(lv, at, CAMP_ART, PAL);
        var cells = grid.Box.sizedP(at, size).grown(1).cells();
        while (cells.next()) |q| kept.set(grid.Level.idx(q));
    }
}

/// Forest along `d` from `q`, far enough for a trail to wind into.
fn leadsInto(lv: *const grid.Level, q: P, d: mathx.Dir) bool {
    const ahead = q.add(d.delta().scaled(SPUR_INTO));
    return ABOVE_FOOT.holds(ahead) and forest(lv.at(q.add(d.delta()))) and forest(lv.at(ahead));
}

fn spurStart(lv: *const grid.Level, q: P) bool {
    if (!lv.walkable(q) or lv.at(q).wet()) return false;
    for (carve.SIDES) |d| if (leadsInto(lv, q, d)) return true;
    return false;
}

/// A winding trail from the T's edge into the forest, ending narrow or in a small glade.
fn spur(lv: *grid.Level, rng: *mathx.Rng) void {
    const start = SPUR_BOX.rollWhere(rng, SITE_TRIES, @as(*const grid.Level, lv), spurStart) orelse return;
    var ways = grid.Bounded(mathx.Dir, carve.SIDES.len){};
    for (carve.SIDES) |d| if (leadsInto(lv, start, d)) ways.push(d);
    const d = rng.pick(mathx.Dir, ways.slice()).delta();
    const length = rng.range(SPUR_SHORTEST, SPUR_LONGEST);
    const aside = rng.range(-@divTrunc(length, 2), @divTrunc(length, 2));
    const r = carve.laneRadius(SPUR_WIDTH);
    var bounds = SPUR_BOX;
    bounds.hi.y = lowestFor(SPUR_WIDTH);
    const to = bounds.clamp(.{ .x = start.x + d.x * length - d.y * aside, .y = start.y + d.y * length + d.x * aside });
    var m = carve.Meander.init(start, to, SPUR_WANDER).within(bounds);
    var end = start;
    while (m.next(rng)) |step| {
        end = step;
        carve.disc(lv, end, r, TRAIL, forest);
    }
    if (rng.percent(GLADE_PERCENT)) carve.disc(lv, end, GLADE_R, OPEN, forest);
}

fn rolled(lv: *grid.Level, seed: u64, doors: []const P, p: Params) void {
    @import("../procgen.zig").roll(lv, seed, doors, .{ .tee = p }, &.{});
}

const RUNS: usize = 100;

fn bridgeAt(lv: *const grid.Level) !P {
    return grid.Level.of(std.mem.indexOfScalar(grid.Tile, &lv.tile, CROSSING) orelse return error.NoBridge);
}

/// Dry cells east of the bridge on its middle row, up to the rim.
fn farBank(lv: *const grid.Level) i32 {
    var lo: ?P = null;
    var hi: ?P = null;
    for (lv.tile, 0..) |t, k| {
        if (t != CROSSING) continue;
        const q = grid.Level.of(k);
        if (lo == null) lo = q;
        hi = q;
    }
    const y = @divTrunc(lo.?.y + hi.?.y, 2);
    var x = grid.W - 2;
    var n: i32 = 0;
    while (x > 0 and !lv.at(.{ .x = x, .y = y }).wet() and !lv.at(.{ .x = x, .y = y }).spans()) : (x -= 1) n += 1;
    return n;
}

test "a tee stays shut outside its T, and lays its camp, woods and bridge" {
    var lv: grid.Level = undefined;
    const p = (Params{}).fit();
    const door = [_]P{.{ .x = 0, .y = 46 }};
    var corner_open: usize = 0;
    var carts: usize = 0;
    var bridged: usize = 0;
    var flammable: usize = 0;
    var trees: usize = 0;
    var barrels: usize = 0;
    var bank: i32 = grid.W;
    var narrow: i32 = grid.W;
    var narrowed = p;
    narrowed.bank = BANK_MIN;
    narrowed.river = RIVER_MAX;
    var low = p;
    low.bar = BAR_MIN;
    low.path = PATH_MAX;
    low.bridge = BRIDGE_MAX;
    const low_door = [_]P{.{ .x = 0, .y = BAR_FLOOR - BAR_MIN / 2 }};
    const foot = grid.Box.sized(.{ .x = 1, .y = BAR_FLOOR }, grid.W - 2, FOOT);
    var low_foot_open: usize = 0;
    for (0..RUNS) |i| {
        rolled(&lv, 0x7E0 +% i *% grid.TEST_SEED_STRIDE, &low_door, low);
        var under = foot.cells();
        while (under.next()) |q| low_foot_open += @intFromBool(lv.walkable(q));
        rolled(&lv, 0x17f78a +% i *% grid.TEST_SEED_STRIDE, &door, narrowed);
        narrow = @min(narrow, farBank(&lv));
        rolled(&lv, 0x7EE +% i *% grid.TEST_SEED_STRIDE, &door, p);
        bank = @min(bank, farBank(&lv));
        for ([_]grid.Box{ grid.Box.sized(.{ .x = 1, .y = 1 }, 8, 20), grid.Box.sized(.{ .x = grid.W - 9, .y = 1 }, 8, 20), foot }) |b| {
            var cells = b.cells();
            while (cells.next()) |q| corner_open += @intFromBool(lv.walkable(q));
        }
        carts += carve.count(&lv, .caravan);
        bridged += @intFromBool(carve.count(&lv, CROSSING) > 0);
        flammable += carve.count(&lv, .bridge);
        trees += carve.count(&lv, .large_tree);
        barrels += lv.barrelCount();
    }
    std.debug.print("{d} tees: {d} open cells in the upper corners and under the bar, {d} of {d} carts, {d} bridged in stone, {d} wooden bridge cells, {d} large trees and {d} barrels a map, a far bank {d} cells at the least of {d}, {d} of {d} at the narrowest\n", .{ RUNS, corner_open, carts, RUNS * p.carts, bridged, flammable, trees / RUNS, barrels / RUNS, bank, p.bank, narrow, BANK_MIN });
    std.debug.print("{d} low tees with the widest paths: {d} open cells under the bar\n", .{ RUNS, low_foot_open });
    try std.testing.expectEqual(@as(usize, 0), corner_open);
    try std.testing.expectEqual(@as(usize, 0), low_foot_open);
    try std.testing.expect(bank * 2 >= p.bank and narrow >= BANK_MIN);
    try std.testing.expectEqual(RUNS, bridged);
    try std.testing.expectEqual(@as(usize, 0), flammable);
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
        _ = grid.distances(&lv, try bridgeAt(&lv), &dist, &queue);
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

test "a tee's crescent pond, its chests and its goblin camps' fires are all walked to from the bridge" {
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const p = (Params{ .spurs = 6, .pond = 6, .pond_chests = 2, .camps = 2 }).fit();
    const door = [_]P{.{ .x = 0, .y = 46 }};
    var ponds: usize = 0;
    var chests = [2]usize{ 0, 0 };
    var fires = [2]usize{ 0, 0 };
    for (0..RUNS) |i| {
        rolled(&lv, 0x7F0 +% i *% grid.TEST_SEED_STRIDE, &door, p);
        _ = grid.distances(&lv, try bridgeAt(&lv), &dist, &queue);
        ponds += @intFromBool(carve.count(&lv, .water) > 0 and carve.count(&lv, .shallows) > 0);
        for (lv.tile, 0..) |t, k| {
            const which: *[2]usize = switch (t) {
                .chest => &chests,
                .lava => &fires,
                else => continue,
            };
            const q = grid.Level.of(k);
            var round = grid.Cells.around(q, 1);
            const wet = t == .lava or while (round.next()) |n| {
                if (!n.eq(q) and !lv.at(n).wet()) break false;
            } else true;
            if (!wet) continue;
            which[0] += 1;
            round = grid.Cells.around(q, 1);
            while (round.next()) |n| if (grid.Level.inside(n) and dist[grid.Level.idx(n)] >= 0) {
                which[1] += 1;
                break;
            };
        }
    }
    std.debug.print("{d} tees with spurs, a pond and camps: {d} ponds, {d} chests out in water ({d} reached), {d} camp fires ({d} reached)\n", .{ RUNS, ponds, chests[0], chests[1], fires[0], fires[1] });
    try std.testing.expectEqual(RUNS, ponds);
    try std.testing.expect(chests[0] * 100 >= RUNS * p.pond_chests * 95);
    try std.testing.expectEqual(chests[0], chests[1]);
    try std.testing.expect(fires[0] * 10 >= RUNS * p.camps * 9);
    try std.testing.expectEqual(fires[0], fires[1]);
}

test "the biggest camp frays as far as its blob reaches, past a box of its radius" {
    const c = P{ .x = grid.W / 2, .y = grid.H / 2 };
    var past: usize = 0;
    for (0..RUNS) |i| {
        var lv = grid.openFloor();
        camp(&lv, carve.Noise.init(0xCA4 +% i *% grid.TEST_SEED_STRIDE, .tee), c, CAMP_MAX);
        for (lv.tile, 0..) |t, k| past += @intFromBool(t == TRAIL and mathx.dist(grid.Level.of(k), c) > CAMP_MAX + 1);
    }
    std.debug.print("{d} camps of radius {d}: {d} trail cells beyond {d} of the middle\n", .{ RUNS, CAMP_MAX, past, CAMP_MAX + 1 });
    try std.testing.expect(past > 0);
}
