const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Diablo II's DrlgMaze: each room drawn by the mask of sides it opens on, as the game picks its presets.

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
        return std.meta.eql(palette(.{ .style = s }), carve.Palette.BUILT);
    }
};

const CAVE_WANDER: f32 = 0.6;
/// A cave room's blob: its edge's least and spread.
const CAVE_LO: f32 = 0.55;
const CAVE_SPAN: f32 = 0.6;
/// The least inner size a tomb room takes its pillars in.
const TOMB_INNER: i32 = 8;
const GRAVE_CHANCE: f32 = 0.4;
const TOMB_BARREL_CHANCE: f32 = 0.5;
const TOMB_BARREL_AT = P{ .x = 2, .y = 3 };
/// The rows of a sewer room's canal off its middle, and how far along its bridge reaches.
const CANAL_FROM: i32 = 2;
const CANAL_TO: i32 = 3;
const BRIDGE_REACH: i32 = 1;
const LAVA_CHANCE: f32 = 0.6;
const LAVA_JITTER: i32 = 2;
/// A snowfield's radius is the room's size over this.
const SNOW_PER: f32 = 5;

pub const Params = struct {
    style: Style = .caves,
    rooms: u8 = 14,
    /// Cells a side.
    size: u8 = 12,
    /// A thousand: how often a room set beside another already there is joined to it too.
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

/// Rooms of side `size` across and down inside the rim.
fn slotsFor(size: i32) struct { x: usize, y: usize } {
    return .{ .x = @intCast(@divTrunc(grid.W - 2, size)), .y = @intCast(@divTrunc(grid.H - 2, size)) };
}

const Plan = struct {
    cols: usize,
    rows: usize,
    size: i32,
    origin: P,
    /// Each slot's open sides; null where no room stands.
    mask: [COLS_MAX * ROWS_MAX]?u4 = @splat(null),

    fn at(self: *const Plan, c: usize, r: usize) ?u4 {
        return self.mask[r * COLS_MAX + c];
    }

    fn slot(self: *const Plan, cr: P) ?usize {
        if (cr.x < 0 or cr.y < 0 or cr.x >= self.cols or cr.y >= self.rows) return null;
        return @as(usize, @intCast(cr.y)) * COLS_MAX + @as(usize, @intCast(cr.x));
    }

    fn place(k: usize) P {
        return .{ .x = @intCast(k % COLS_MAX), .y = @intCast(k / COLS_MAX) };
    }

    fn corner(self: *const Plan, c: usize, r: usize) P {
        return self.origin.add(.{ .x = @as(i32, @intCast(c)) * self.size, .y = @as(i32, @intCast(r)) * self.size });
    }
};

const SIDES = [_]mathx.Dir{ .w, .e, .s, .n };

fn bitOf(d: mathx.Dir) u4 {
    return @as(u4, 1) << @intCast(std.mem.indexOfScalar(mathx.Dir, &SIDES, d).?);
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
    placed[0] = (pl.rows / 2) * COLS_MAX + pl.cols / 2;
    pl.mask[placed[0]] = 0;
    var tries: usize = 0;
    while (n < p.rooms and tries < TRIES) : (tries += 1) {
        const pick = rng.below(@intCast(n));
        const from = placed[pick];
        const side = SIDES[rng.below(SIDES.len)];
        const cr = Plan.place(from).add(side.delta());
        const k = pl.slot(cr) orelse continue;
        if (pl.mask[k] != null) continue;
        pl.mask[k] = bitOf(side.opposite());
        pl.mask[from].? |= bitOf(side);
        for (SIDES) |s| {
            const o = pl.slot(cr.add(s.delta())) orelse continue;
            if (o == from or pl.mask[o] == null or !rng.perMille(p.merge)) continue;
            pl.mask[k].? |= bitOf(s);
            pl.mask[o].? |= bitOf(s.opposite());
        }
        placed[n] = k;
        n += 1;
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
fn room(lv: *grid.Level, rng: *mathx.Rng, noise: carve.Noise, style: Style, pal: carve.Palette, lo: P, size: i32, mask: u4) void {
    const whole = grid.Box.sized(lo, size, size);
    const mid = whole.centre();
    const inside = whole.inner();
    if (style.built()) {
        carve.box(lv, inside, pal.open);
    } else {
        carve.blobIn(lv, noise, mid, @as(f32, @floatFromInt(size)) / 2 - 1, carve.CAVE_SCALE, CAVE_LO, CAVE_SPAN, pal.open, inside);
    }
    for (SIDES) |s| {
        if (mask & bitOf(s) == 0) continue;
        const step = s.delta();
        const edge = mid.add(step.scaled(@divTrunc(size, 2)));
        carve.lane(lv, rng, mid, edge.add(step), DOOR_W, if (style.built()) 0 else CAVE_WANDER, pal.open, .cut);
    }
    const inner = size - 2;
    switch (style) {
        .tombs => if (inner >= TOMB_INNER) {
            for (carve.corners(whole.shrunk(2))) |c| lv.set(c, .wall);
            if (rng.chance(GRAVE_CHANCE)) lv.set(mid, .grave) else if (rng.chance(TOMB_BARREL_CHANCE)) lv.putBarrel(lo.add(TOMB_BARREL_AT));
            if (mask & bitOf(.n) == 0) lv.addTorch(.{ .x = mid.x, .y = lo.y });
        },
        .sewers => {
            const across = mask & (bitOf(.w) | bitOf(.e)) != 0;
            var cells = inside.cells();
            while (cells.next()) |q| {
                const off = if (across) q.y - mid.y else q.x - mid.x;
                const along = if (across) q.x - mid.x else q.y - mid.y;
                if (off < CANAL_FROM or off > CANAL_TO) continue;
                lv.set(q, if (@abs(along) <= BRIDGE_REACH) .bridge else .water);
            }
        },
        .lava => if (rng.chance(LAVA_CHANCE)) pool(lv, grid.Box.around(mid, LAVA_JITTER).roll(rng)),

        .caves => {},
        .ice => carve.disc(lv, mid, @as(f32, @floatFromInt(size)) / SNOW_PER, .snow, null),
    }
}

const POOL_R: f32 = 1.6;

fn pool(lv: *grid.Level, c: P) void {
    var st: carve.Stretches = .{};
    _ = st.label(lv);
    const region = st.region;
    const was = lv.tile;
    carve.disc(lv, c, POOL_R, .lava, null);
    _ = st.label(lv);
    if (st.parts(&region)) lv.tile = was;
}

test "a lava maze's pools never part ground its ways join" {
    var lv = grid.Level.blank();
    var st: carve.Stretches = .{};
    var mazes: usize = 0;
    var parted: usize = 0;
    for ([_]u8{ SIZE_MIN, (Params{}).size, SIZE_MAX }) |size| {
        for (0..100) |i| {
            var rng = mathx.Rng.init(i);
            shape(&lv, &rng, i, (Params{ .style = .lava, .size = size }).fit());
            const with = st.label(&lv);
            for (&lv.tile) |*t| {
                if (t.* == .lava) t.* = .floor;
            }
            mazes += 1;
            if (with > st.label(&lv)) parted += 1;
        }
    }
    std.debug.print("{d} lava mazes: {d} with ground a pool parts\n", .{ mazes, parted });
    try std.testing.expectEqual(@as(usize, 0), parted);
}

test "a maze sets the rooms asked, joined, and merging adds loops" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xD2);
    shape(&lv, &rng, 1, .{ .style = .tombs, .merge = 0 });
    const tree = carve.count(&lv, .floor);
    rng = mathx.Rng.init(0xD2);
    shape(&lv, &rng, 1, .{ .style = .tombs, .merge = 1000 });
    std.debug.print("a 14-room tomb maze: {d} floor as a tree, {d} merged\n", .{ tree, carve.count(&lv, .floor) });
    try std.testing.expect(tree > 14 * 50);
}
