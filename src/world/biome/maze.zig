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
/// A doorway's width between two joined rooms.
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

    /// Walled and floored, its ways straight.
    fn built(s: Style) bool {
        return switch (s) {
            .tombs, .sewers => true,
            .caves, .lava, .ice => false,
        };
    }
};

/// How much a natural maze's ways wander.
const CAVE_WANDER: f32 = 0.6;

pub const Params = struct {
    style: Style = .caves,
    rooms: u8 = 14,
    /// Cells a side.
    size: u8 = 12,
    /// A thousand: how often a room set beside another already there is joined to it too.
    merge: u16 = 500,

    pub fn fit(p: Params) Params {
        return .{ .style = p.style, .rooms = std.math.clamp(p.rooms, 1, ROOMS_MAX), .size = std.math.clamp(p.size, SIZE_MIN, SIZE_MAX), .merge = @min(p.merge, mathx.MILLE) };
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

    fn corner(self: *const Plan, c: usize, r: usize) P {
        return self.origin.add(.{ .x = @as(i32, @intCast(c)) * self.size, .y = @as(i32, @intCast(r)) * self.size });
    }
};

const SIDES = [4]struct { dc: i32, dr: i32, bit: u4, back: u4 }{
    .{ .dc = -1, .dr = 0, .bit = W_BIT, .back = E_BIT },
    .{ .dc = 1, .dr = 0, .bit = E_BIT, .back = W_BIT },
    .{ .dc = 0, .dr = 1, .bit = S_BIT, .back = N_BIT },
    .{ .dc = 0, .dr = -1, .bit = N_BIT, .back = S_BIT },
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
    pl.origin = .{ .x = @divTrunc(grid.W - @as(i32, @intCast(pl.cols)) * size, 2), .y = @divTrunc(grid.H - @as(i32, @intCast(pl.rows)) * size, 2) };
    var placed: [COLS_MAX * ROWS_MAX]usize = undefined;
    var n: usize = 1;
    placed[0] = (pl.rows / 2) * COLS_MAX + pl.cols / 2;
    pl.mask[placed[0]] = 0;
    var tries: usize = 0;
    while (n < p.rooms and tries < TRIES) : (tries += 1) {
        const from = placed[rng.below(@intCast(n))];
        const side = SIDES[rng.below(4)];
        const c = @as(i32, @intCast(from % COLS_MAX)) + side.dc;
        const r = @as(i32, @intCast(from / COLS_MAX)) + side.dr;
        if (c < 0 or r < 0 or c >= pl.cols or r >= pl.rows) continue;
        const k = @as(usize, @intCast(r)) * COLS_MAX + @as(usize, @intCast(c));
        if (pl.mask[k] != null) continue;
        pl.mask[k] = side.back;
        pl.mask[from].? |= side.bit;
        for (SIDES) |s| {
            const oc = c + s.dc;
            const orr = r + s.dr;
            if (oc < 0 or orr < 0 or oc >= pl.cols or orr >= pl.rows) continue;
            const o = @as(usize, @intCast(orr)) * COLS_MAX + @as(usize, @intCast(oc));
            if (o == from or pl.mask[o] == null or !carve.chance(rng, p.merge)) continue;
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

/// One room in its box, opening on the sides its mask names: the cell beyond each opening is the next room's.
fn room(lv: *grid.Level, rng: *mathx.Rng, noise: carve.Noise, style: Style, pal: carve.Palette, lo: P, size: i32, mask: u4) void {
    const mid = lo.add(.{ .x = @divTrunc(size, 2), .y = @divTrunc(size, 2) });
    const in_lo = lo.add(.{ .x = 1, .y = 1 });
    const in_hi = lo.add(.{ .x = size - 1, .y = size - 1 });
    switch (style) {
        .tombs, .sewers => carve.box(lv, in_lo, in_hi, pal.open),
        .caves, .lava, .ice => {
            const half: f32 = @as(f32, @floatFromInt(size)) / 2 - 1;
            var cells = grid.Cells.of(in_lo, in_hi);
            while (cells.next()) |q| {
                if (mathx.distEuclid(q, mid) / half < 0.55 + 0.6 * noise.at(q, 3, 2)) lv.set(q, pal.open);
            }
        },
    }
    for (SIDES) |s| {
        if (mask & s.bit == 0) continue;
        const edge = mid.add(.{ .x = s.dc * @divTrunc(size, 2), .y = s.dr * @divTrunc(size, 2) });
        var m = carve.Meander.init(mid, edge.add(.{ .x = s.dc, .y = s.dr }), if (style.built()) 0 else CAVE_WANDER);
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
            lv.addTorch(.{ .x = mid.x, .y = lo.y });
        },
        .sewers => {
            const across = mask & (W_BIT | E_BIT) != 0;
            var cells = grid.Cells.of(in_lo, in_hi);
            while (cells.next()) |q| {
                const off = if (across) q.y - mid.y else q.x - mid.x;
                const along = if (across) q.x - mid.x else q.y - mid.y;
                if (off != 2 and off != 3) continue;
                lv.set(q, if (@abs(along) <= 1) .bridge else .water);
            }
        },
        .lava => if (rng.chance(0.6)) carve.disc(lv, mid.add(.{ .x = rng.range(-2, 2), .y = rng.range(-2, 2) }), 1.6, .lava, null),
        .ice => carve.disc(lv, mid, @as(f32, @floatFromInt(size)) / 5, .snow, null),
        .caves => {},
    }
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
