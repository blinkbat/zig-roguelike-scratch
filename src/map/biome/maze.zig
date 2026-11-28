const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");
const lume = @import("../lume.zig");

const P = mathx.P;

pub const SIZE_MIN: u8 = 8;
pub const SIZE_MAX: u8 = 20;
pub const ROOMS_MAX: u8 = 48;
const TRIES: usize = 2000;
const DOOR_W: u8 = 3;

pub const Style = enum {
    caves,
    tombs,
    sewers,
    lava,
    ice,

    fn built(s: Style) bool {
        return switch (s) {
            .tombs, .sewers => true,
            .caves, .lava, .ice => false,
        };
    }
};

const CAVE_WANDER: f32 = 0.6;
const CAVE_LO: f32 = 0.55;
const CAVE_SPAN: f32 = 0.6;
const TOMB_INNER: i32 = 8;
const GRAVE_CHANCE: f32 = 0.4;
const TOMB_BARREL_CHANCE: f32 = 0.5;
const TOMB_BARREL_AT = P{ .x = 2, .y = 3 };
const CANAL_FROM: i32 = 2;
const CANAL_TO: i32 = 3;
const BRIDGE_REACH: i32 = 1;
const LAVA_CHANCE: f32 = 0.6;
const LAVA_JITTER: i32 = 2;
const SNOW_PER: f32 = 5;

pub const Params = struct {
    style: Style = .caves,
    rooms: u8 = 14,
    size: u8 = 12,
    /// Chance per thousand of joining an adjacent room.
    merge: u16 = 500,

    pub fn fit(p: Params) Params {
        var q = p;
        q.rooms = std.math.clamp(p.rooms, 1, ROOMS_MAX);
        q.size = std.math.clamp(p.size, SIZE_MIN, SIZE_MAX);
        q.merge = @min(p.merge, mathx.MILLE);
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    return switch (p.style) {
        .tombs, .sewers => carve.Palette.BUILT,
        .caves, .lava => carve.Palette.CAVE,
        .ice => .{ .open = .ice, .solid = .rock, .path = .snow },
    };
}

const COLS_MAX: usize = slotsFor(SIZE_MIN).x;
const ROWS_MAX: usize = slotsFor(SIZE_MIN).y;

fn slotsFor(size: i32) struct { x: usize, y: usize } {
    return .{ .x = @intCast(@divTrunc(grid.W - 2, size)), .y = @intCast(@divTrunc(grid.H - 2, size)) };
}

const Plan = struct {
    cols: usize,
    rows: usize,
    size: i32,
    origin: P,
    /// Each slot's open sides; null where no room stands.
    mask: [COLS_MAX * ROWS_MAX]?Opened = @splat(null),

    fn at(self: *const Plan, c: usize, r: usize) ?Opened {
        const k = self.slot(.{ .x = @intCast(c), .y = @intCast(r) }).?;
        return self.mask[k];
    }

    fn slot(self: *const Plan, cr: P) ?usize {
        if (cr.x >= self.cols or cr.y >= self.rows) return null;
        return mathx.slot(cr.x, cr.y, COLS_MAX, ROWS_MAX);
    }

    fn place(k: usize) P {
        return mathx.unslot(k, COLS_MAX);
    }

    fn corner(self: *const Plan, c: usize, r: usize) P {
        return self.origin.add(.{ .x = @as(i32, @intCast(c)) * self.size, .y = @as(i32, @intCast(r)) * self.size });
    }
};

const OPENINGS = [_]mathx.Dir{ .w, .e, .s, .n };
const Opened = std.meta.Int(.unsigned, OPENINGS.len);

fn bitOf(d: mathx.Dir) Opened {
    return @as(Opened, 1) << @intCast(std.mem.indexOfScalar(mathx.Dir, &OPENINGS, d).?);
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    const pal = palette(p);
    carve.fill(lv, pal.solid);
    const size: i32 = p.size;
    var pl = Plan{
        .cols = slotsFor(size).x,
        .rows = slotsFor(size).y,
        .size = size,
        .origin = undefined,
    };
    pl.origin = grid.Box.centred(@as(i32, @intCast(pl.cols)) * size, @as(i32, @intCast(pl.rows)) * size).lo;
    var placed: [COLS_MAX * ROWS_MAX]usize = undefined;
    var n: usize = 1;
    placed[0] = pl.slot(.{ .x = @intCast(pl.cols / 2), .y = @intCast(pl.rows / 2) }).?;
    pl.mask[placed[0]] = 0;
    var tries: usize = 0;
    while (n < p.rooms and tries < TRIES) : (tries += 1) {
        const from = rng.pick(usize, placed[0..n]);
        const side = rng.pick(mathx.Dir, &OPENINGS);
        const cr = Plan.place(from).add(side.delta());
        const k = pl.slot(cr) orelse continue;
        if (pl.mask[k] != null) continue;
        pl.mask[k] = bitOf(side.opposite());
        pl.mask[from].? |= bitOf(side);
        for (OPENINGS) |s| {
            const o = pl.slot(cr.add(s.delta())) orelse continue;
            if (o == from or pl.mask[o] == null or !rng.perMille(p.merge)) continue;
            pl.mask[k].? |= bitOf(s);
            pl.mask[o].? |= bitOf(s.opposite());
        }
        _ = mathx.push(usize, &placed, &n, k);
    }
    const noise = carve.Noise.init(seed, .maze);
    for (0..pl.rows) |r| {
        for (0..pl.cols) |c| {
            const mask = pl.at(c, r) orelse continue;
            room(lv, rng, noise, p.style, pal, pl.corner(c, r), size, mask);
        }
    }
}

/// The cell beyond each opening is the next room's.
fn room(lv: *grid.Level, rng: *mathx.Rng, noise: carve.Noise, style: Style, pal: carve.Palette, lo: P, size: i32, mask: Opened) void {
    const whole = grid.Box.sized(lo, size, size);
    const mid = whole.centre();
    const inside = whole.inner();
    if (style.built()) {
        carve.box(lv, inside, pal.open);
    } else {
        carve.blobIn(lv, noise, mid, @as(f32, @floatFromInt(size)) / 2 - 1, carve.CAVE_SCALE, CAVE_LO, CAVE_SPAN, pal.open, inside, null);
    }
    for (OPENINGS) |s| {
        if (mask & bitOf(s) == 0) continue;
        const step = s.delta();
        const edge = mid.add(step.scaled(@divTrunc(size, 2)));
        carve.lane(lv, rng, mid, edge.add(step), DOOR_W, if (style.built()) 0 else CAVE_WANDER, pal.open, .cut);
    }
    switch (style) {
        .tombs => if (inside.width() >= TOMB_INNER) {
            for (carve.corners(whole.shrunk(2))) |c| lv.set(c, .wall);
            if (rng.chance(GRAVE_CHANCE)) lv.set(mid, .grave) else if (rng.chance(TOMB_BARREL_CHANCE)) lv.putBarrel(lo.add(TOMB_BARREL_AT));
            if (mask & bitOf(.n) == 0) lv.addTorch(lume.torchOver(inside, mid.x));
        },
        .sewers => {
            const across = mask & (bitOf(.w) | bitOf(.e)) != 0;
            var cells = inside.cells();
            while (cells.next()) |q| {
                const off = if (across) q.y - mid.y else q.x - mid.x;
                const along = if (across) q.x - mid.x else q.y - mid.y;
                if (off < CANAL_FROM or off > CANAL_TO) continue;
                lv.set(q, if (@abs(along) <= BRIDGE_REACH) carve.SPAN else .water);
            }
        },
        .lava => if (rng.chance(LAVA_CHANCE)) pool(lv, grid.Box.around(mid, LAVA_JITTER).roll(rng)),

        .caves => {},
        .ice => carve.disc(lv, mid, @as(f32, @floatFromInt(size)) / SNOW_PER, .snow, null),
    }
}

const POOL_R: f32 = 1.6;

fn pool(lv: *grid.Level, c: P) void {
    if (keepsNearbyWays(lv, c)) return carve.disc(lv, c, POOL_R, .lava, null);
    var st: carve.Stretches = .{};
    _ = st.label(lv);
    const region = st.region;
    const was = lv.tile;
    carve.disc(lv, c, POOL_R, .lava, null);
    _ = st.label(lv);
    if (st.parts(&region)) lv.tile = was;
}

fn keepsNearbyWays(lv: *const grid.Level, centre: P) bool {
    const Crossing = struct {
        lv: *const grid.Level,
        centre: P,
        window: grid.Box,

        fn submerged(self: @This(), p: P) bool {
            return !grid.Level.onRim(p) and carve.inDisc(self.centre, p, POOL_R);
        }

        fn removed(self: @This(), p: P) bool {
            return self.submerged(p) and self.lv.walkable(p);
        }

        fn survives(self: @This(), p: P) bool {
            return self.window.holds(p) and !self.submerged(p) and self.lv.walkable(p);
        }
    };
    const reach = carve.discReach(POOL_R);
    const crossing = Crossing{ .lv = lv, .centre = centre, .window = grid.Box.around(centre, reach + 2).grown(0) };
    var cells = grid.Box.around(centre, reach + 1).grown(0).cells();
    var exits = grid.CellSet.initEmpty();
    var start: ?P = null;
    var remaining: usize = 0;
    while (cells.next()) |p| {
        if (!crossing.survives(p) or !grid.anyNeighbour(p, crossing, Crossing.removed)) continue;
        exits.set(grid.Level.idx(p));
        start = p;
        remaining += 1;
    }
    if (remaining <= 1) return true;
    var seen = grid.CellSet.initEmpty();
    var queue: [grid.CELLS]u32 = undefined;
    var walk = grid.Spread(Crossing, Crossing.survives){ .ctx = crossing, .steps = &grid.STEPS, .seen = &seen, .queue = &queue };
    walk.seed(start.?);
    while (walk.next()) |p| {
        if (exits.isSet(grid.Level.idx(p))) {
            remaining -= 1;
            if (remaining == 0) return true;
        }
    }
    return false;
}

test "a lava maze's pools never part ground its ways join" {
    var lv = grid.Level.blank();
    var st: carve.Stretches = .{};
    var parted: usize = 0;
    for ([_]u8{ SIZE_MIN, (Params{}).size, SIZE_MAX }) |size| {
        for (0..100) |i| {
            var rng = mathx.Rng.init(i);
            shape(&lv, &rng, i, (Params{ .style = .lava, .size = size }).fit());
            const with = st.label(&lv);
            for (&lv.tile) |*t| {
                if (t.* == .lava) t.* = .floor;
            }
            if (with > st.label(&lv)) parted += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 0), parted);

    lv = grid.Level.blank();
    const centre = P{ .x = 12, .y = 12 };
    carve.box(&lv, grid.Box.sized(.{ .x = 7, .y = 12 }, 11, 1), .floor);
    try std.testing.expect(!keepsNearbyWays(&lv, centre));
    pool(&lv, centre);
    try std.testing.expectEqual(grid.Tile.floor, lv.at(centre));
}

test "a maze sets the rooms asked, joined, and merging adds loops" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xD2);
    shape(&lv, &rng, 1, .{ .style = .tombs, .merge = 0 });
    const tree = carve.count(&lv, .floor);
    rng = mathx.Rng.init(0xD2);
    shape(&lv, &rng, 1, .{ .style = .tombs, .merge = 1000 });
    try std.testing.expect(tree > 14 * 50);
    try std.testing.expect(carve.count(&lv, .floor) > tree);
}
