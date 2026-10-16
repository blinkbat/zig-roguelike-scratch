const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Dwarftown's houses, Dwarf Fortress's hamlet, Diablo II's cottages; decayed, Qud's ruins and the Lost City.

const P = mathx.P;

pub const COUNT_MAX: u8 = 24;
pub const SIZE_MIN: u8 = 4;
pub const SIZE_MAX: u8 = 20;
pub const BARRELS_MAX: u8 = 4;
const TRIES: usize = 120;
const SPLIT_TRIES: usize = 8;
const BARREL_TRIES: usize = 40;
/// Cells between a building and the map's edge.
const SITE_MARGIN: i32 = 2;

pub const Params = struct {
    count: u8 = 6,
    /// Smallest and largest side, outline and all.
    size: [2]u8 = .{ 5, 11 },
    /// Percent of wall fallen to rubble, and half that of floor.
    decay: u8 = 0,
    walls: grid.Tile = .wall,
    floor: grid.Tile = .floor,
    /// The most barrels one stacks.
    barrels: u8 = 1,
    /// Percent of them that hang a torch.
    torches: u8 = 30,

    pub fn fit(p: Params) Params {
        var q = p;
        q.count = std.math.clamp(p.count, 1, COUNT_MAX);
        q.size = mathx.span(u8, p.size, SIZE_MIN, SIZE_MAX);
        q.decay = @min(p.decay, mathx.PERCENT);
        q.barrels = @min(p.barrels, BARRELS_MAX);
        q.torches = @min(p.torches, mathx.PERCENT);
        return q;
    }
};

const Box = grid.Box;

/// Room for every lot a floor's features take, as `procgen` asserts.
pub const LOTS_MAX: usize = @import("../procgen.zig").MAX_FEATURES * COUNT_MAX;

/// Every lot a floor's features take, so no feature raises one over another's.
pub const Lots = struct {
    box: [LOTS_MAX]Box = undefined,
    n: usize = 0,
    /// The first lot of the feature taking them now.
    mine: usize = 0,

    /// Cells between two lots at the least, so neither's ring opens the other.
    pub const GAP: i32 = 1;

    /// A feature starts taking lots, as `procgen` has each: its own keep its gap apart, the earlier features' `GAP`.
    pub fn begin(self: *Lots) void {
        self.mine = self.n;
    }

    pub fn slice(self: *const Lots) []const Box {
        return self.box[0..self.n];
    }

    pub fn take(self: *Lots, lv: *const grid.Level, rng: *mathx.Rng, w: i32, h: i32, pal: carve.Palette) ?Box {
        return self.takeApart(lv, rng, w, h, GAP, pal);
    }

    pub fn takeApart(self: *Lots, lv: *const grid.Level, rng: *mathx.Rng, w: i32, h: i32, gap: i32, pal: carve.Palette) ?Box {
        if (self.n == LOTS_MAX) return null;
        const b = self.site(lv, rng, w, h, gap, pal) orelse return null;
        self.box[self.n] = b;
        self.n += 1;
        return b;
    }

    /// A `w` by `h` box clear of liquid, doors, bridges and any solid `carve.clearRound` leaves standing, a cell of margin round it, and clear of every lot taken.
    fn site(self: *const Lots, lv: *const grid.Level, rng: *mathx.Rng, w: i32, h: i32, gap: i32, pal: carve.Palette) ?Box {
        if (w + SITE_MARGIN * 2 > grid.W or h + SITE_MARGIN * 2 > grid.H) return null;
        for (0..TRIES) |_| {
            const b = Box.sized(Box.inMap(SITE_MARGIN).rollFor(rng, w, h), w, h);
            if (self.clear(b, gap) and fits(lv, b, pal)) return b;
        }
        return null;
    }

    fn clear(self: *const Lots, b: Box, gap: i32) bool {
        for (self.slice(), 0..) |t, i| {
            if (b.overlaps(t, if (i < self.mine) GAP else gap)) return false;
        }
        return true;
    }
};

pub fn openWay(lv: *grid.Level, way: [2]P, inside: grid.Tile, outside: grid.Tile) void {
    lv.set(way[0], inside);
    if (lv.at(way[1]).solid()) lv.set(way[1], outside);
}

fn fits(lv: *const grid.Level, b: Box, pal: carve.Palette) bool {
    var cells = b.grown(1).cells();
    while (cells.next()) |q| {
        const t = lv.at(q);
        if (t.liquid() or t == .bridge or lv.doorAt(q) != null) return false;
        if (t.solid() and !carve.closes(t, pal)) return false;
    }
    return true;
}

/// A cell on the box's outline, not a corner, and the cell outside it.
pub fn doorway(rng: *mathx.Rng, b: Box) [2]P {
    const side = carve.SIDES[rng.below(carve.SIDES.len)];
    return doorwayOn(b, side, rng.range(0, spanOf(b, side) - 1));
}

fn doorwayOn(b: Box, side: mathx.Dir, k: i32) [2]P {
    const w = carve.sideAt(b, side, carve.alongOf(side, b.lo) + 1 + k);
    return .{ w, w.add(side.delta()) };
}

fn spanOf(b: Box, side: mathx.Dir) i32 {
    return carve.alongOf(side, .{ .x = b.width(), .y = b.height() }) - 2;
}

fn dryDoorway(lv: *const grid.Level, rng: *mathx.Rng, b: Box) ?[2]P {
    var all: [2 * (grid.W + grid.H)][2]P = undefined;
    var n: usize = 0;
    for (carve.SIDES) |side| {
        var k: i32 = 0;
        while (k < spanOf(b, side) and n < all.len) : (k += 1) {
            all[n] = doorwayOn(b, side, k);
            n += 1;
        }
    }
    return rng.pickWhere([2]P, all[0..n], lv, dry);
}

fn dry(lv: *const grid.Level, way: [2]P) bool {
    return !lv.at(way[1]).liquid();
}

pub fn cuttable(len: i32, least: i32) bool {
    return len >= 2 * least + 1;
}

pub fn cutAt(rng: *mathx.Rng, lo: i32, hi: i32, least: i32) i32 {
    return rng.range(lo + least, hi - least - 1);
}

/// Where a wall cutting `b` may stand, `least` in from its sides: both its ends meet `walls`, not a doorway.
fn splitAt(lv: *const grid.Level, rng: *mathx.Rng, b: Box, across: bool, least: i32, walls: grid.Tile) ?i32 {
    const lo = if (across) b.lo.x else b.lo.y;
    const hi = if (across) b.hi.x else b.hi.y;
    for (0..SPLIT_TRIES) |_| {
        const at = cutAt(rng, lo, hi, least);
        const ends = cutEnds(b, across, at);
        if (lv.at(ends[0]) == walls and lv.at(ends[1]) == walls) return at;
    }
    return null;
}

/// The two cells just outside `b` that a cut at `at` runs between: above and below it `across`, else either side.
pub fn cutEnds(b: Box, across: bool, at: i32) [2]P {
    return if (across)
        .{ .{ .x = at, .y = b.lo.y - 1 }, .{ .x = at, .y = b.hi.y } }
    else
        .{ .{ .x = b.lo.x - 1, .y = at }, .{ .x = b.hi.x, .y = at } };
}

/// The line of cells a cut at `at` takes out of `b`: a column `across`, else a row.
fn cutLine(b: Box, across: bool, at: i32) Box {
    return if (across)
        .{ .lo = .{ .x = at, .y = b.lo.y }, .hi = .{ .x = at + 1, .y = b.hi.y } }
    else
        .{ .lo = .{ .x = b.lo.x, .y = at }, .hi = .{ .x = b.hi.x, .y = at + 1 } };
}

/// What is left of `b` either side of a cut at `at`, left then right `across`, else top then bottom.
pub fn cutBoxes(b: Box, across: bool, at: i32) [2]Box {
    return if (across)
        .{ .{ .lo = b.lo, .hi = .{ .x = at, .y = b.hi.y } }, .{ .lo = .{ .x = at + 1, .y = b.lo.y }, .hi = b.hi } }
    else
        .{ .{ .lo = b.lo, .hi = .{ .x = b.hi.x, .y = at } }, .{ .lo = .{ .x = b.lo.x, .y = at + 1 }, .hi = b.hi } };
}

/// Cut by walls, each with a doorway, till no room is wider than twice `least`.
pub fn partition(lv: *grid.Level, rng: *mathx.Rng, inside: Box, least: i32, walls: grid.Tile) void {
    var stack: [64]Box = undefined;
    stack[0] = inside;
    var n: usize = 1;
    while (n > 0) {
        n -= 1;
        const b = stack[n];
        const w = b.width();
        const h = b.height();
        const across = if (cuttable(w, least) and cuttable(h, least)) rng.chance(@as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(w + h))) else cuttable(w, least);
        if (!across and !cuttable(h, least)) continue;
        if (n + 2 > stack.len) continue;
        const at = splitAt(lv, rng, b, across, least, walls) orelse continue;
        const wall = cutLine(b, across, at);
        carve.box(lv, wall, walls);
        lv.set(wall.roll(rng), .floor);
        stack[n..][0..2].* = cutBoxes(b, across, at);
        n += 2;
    }
}

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, pal: carve.Palette, lots: *Lots, p: Params) void {
    for (0..p.count) |_| {
        const w = rng.range(p.size[0], p.size[1]);
        const h = rng.range(p.size[0], @max(p.size[0], @divTrunc(p.size[1] * 3, 4)));
        const b = lots.take(lv, rng, w, h, pal) orelse continue;
        raise(lv, rng, b, p, pal.open);
        carve.clearRound(lv, b, pal);
    }
}

/// `outside` is laid outside the doorway where that cell is solid.
pub fn raise(lv: *grid.Level, rng: *mathx.Rng, b: Box, p: Params, outside: grid.Tile) void {
    var cells = b.cells();
    while (cells.next()) |q| {
        const edge = b.onEdge(q);
        const fallen = rng.percent(if (edge) p.decay else p.decay / 2);
        lv.set(q, if (fallen) .rubble else if (edge) p.walls else p.floor);
    }
    const way = dryDoorway(lv, rng, b) orelse doorway(rng, b);
    openWay(lv, way, p.floor, outside);
    const in = b.inner();
    if (rng.percent(p.torches) and in.width() > 2) lv.addTorch(.{ .x = rng.range(in.lo.x + 1, in.hi.x - 2), .y = b.lo.y });
    var left = rng.below(@as(u32, p.barrels) + 1);
    var tries: usize = 0;
    while (left > 0 and tries < BARREL_TRIES) : (tries += 1) {
        const q = in.roll(rng);
        if (!in.onEdge(q) or mathx.dist(q, way[0]) <= 1 or lv.at(q) != p.floor) continue;
        lv.putBarrel(q);
        left -= 1;
    }
}

test "buildings stand walled with a way in, and decayed ones lie in rubble" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xB111);
    carve.field(&lv, carve.Palette.WILD);
    const pal = carve.Palette.WILD;
    var lots: Lots = .{};
    apply(&lv, &rng, 0, pal, &lots, .{ .count = 8 });
    const walls = carve.count(&lv, .wall);
    apply(&lv, &rng, 0, pal, &lots, .{ .count = 8, .decay = 60 });
    std.debug.print("8 houses: {d} wall cells; 8 more at 60% decay: {d} rubble\n", .{ walls, carve.count(&lv, .rubble) });
    try std.testing.expect(walls > 8 * 12 and carve.count(&lv, .rubble) > 40);
}
