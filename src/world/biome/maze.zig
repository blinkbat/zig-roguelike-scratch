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
const DOOR_W: i32 = 3;
const W_BIT: u4 = 1;
const E_BIT: u4 = 2;
const S_BIT: u4 = 4;
const N_BIT: u4 = 8;

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

const COLS_MAX: usize = @intCast(@divTrunc(grid.W - 2, SIZE_MIN));
const ROWS_MAX: usize = @intCast(@divTrunc(grid.H - 2, SIZE_MIN));

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

    /// The slot at column `cr.x`, row `cr.y`; null off the plan.
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

const SIDES = [4]struct { d: mathx.Dir, bit: u4, back: u4 }{
    .{ .d = .w, .bit = W_BIT, .back = E_BIT },
    .{ .d = .e, .bit = E_BIT, .back = W_BIT },
    .{ .d = .s, .bit = S_BIT, .back = N_BIT },
    .{ .d = .n, .bit = N_BIT, .back = S_BIT },
};

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    const pal = palette(p);
    carve.fill(lv, pal.solid);
    const size: i32 = p.size;
    var pl = Plan{
        .cols = @intCast(@divTrunc(grid.W - 2, size)),
        .rows = @intCast(@divTrunc(grid.H - 2, size)),
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
        const from = placed[rng.below(@intCast(n))];
        const side = SIDES[rng.below(4)];
        const cr = Plan.place(from).add(side.d.delta());
        const k = pl.slot(cr) orelse continue;
        if (pl.mask[k] != null) continue;
        pl.mask[k] = side.back;
        pl.mask[from].? |= side.bit;
        for (SIDES) |s| {
            const o = pl.slot(cr.add(s.d.delta())) orelse continue;
            if (o == from or pl.mask[o] == null or !rng.perMille(p.merge)) continue;
            pl.mask[k].? |= s.bit;
            pl.mask[o].? |= s.back;
        }
        placed[n] = k;
        n += 1;
    }
    const noise = carve.Noise.init(seed ^ 0x3A2E);
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
        carve.blobIn(lv, noise, mid, @as(f32, @floatFromInt(size)) / 2 - 1, 3, 0.55, 0.6, pal.open, inside);
    }
    for (SIDES) |s| {
        if (mask & s.bit == 0) continue;
        const step = s.d.delta();
        const edge = mid.add(.{ .x = step.x * @divTrunc(size, 2), .y = step.y * @divTrunc(size, 2) });
        var m = carve.Meander.init(mid, edge.add(step), if (style.built()) 0 else CAVE_WANDER);
        while (m.next(rng)) |q| {
            var cells = grid.Cells.around(q, @divTrunc(DOOR_W, 2));
            while (cells.next()) |d| {
                if (!grid.Level.onRim(d)) lv.set(d, pal.open);
            }
        }
    }
    const inner = size - 2;
    switch (style) {
        .tombs => if (inner >= 8) {
            for ([_]P{ .{ .x = 2, .y = 2 }, .{ .x = inner - 1, .y = 2 }, .{ .x = 2, .y = inner - 1 }, .{ .x = inner - 1, .y = inner - 1 } }) |o| lv.set(lo.add(o), .wall);
            if (rng.chance(0.4)) lv.set(mid, .grave) else if (rng.chance(0.5)) lv.putBarrel(lo.add(.{ .x = 2, .y = 3 }));
            if (mask & N_BIT == 0) lv.addTorch(.{ .x = mid.x, .y = lo.y });
        },
        .sewers => {
            const across = mask & (W_BIT | E_BIT) != 0;
            var cells = inside.cells();
            while (cells.next()) |q| {
                const off = if (across) q.y - mid.y else q.x - mid.x;
                const along = if (across) q.x - mid.x else q.y - mid.y;
                if (off != 2 and off != 3) continue;
                lv.set(q, if (@abs(along) <= 1) .bridge else .water);
            }
        },
        .lava => if (rng.chance(0.6)) pool(lv, mid.add(.{ .x = rng.range(-2, 2), .y = rng.range(-2, 2) })),
        .caves => {},
        .ice => carve.disc(lv, mid, @as(f32, @floatFromInt(size)) / 5, .snow, null),
    }
}

const POOL_R: f32 = 1.6;

fn pool(lv: *grid.Level, c: P) void {
    var st: carve.Stretches = .{};
    const before = st.label(lv);
    const was = lv.tile;
    carve.disc(lv, c, POOL_R, .lava, null);
    if (st.label(lv) > before) lv.tile = was;
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
    std.debug.print("{d} lava mazes: {d} with ground a pool parts\n", .{ mazes, parted });    try std.testing.expectEqual(@as(usize, 0), parted);
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
