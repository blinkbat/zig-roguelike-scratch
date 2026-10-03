const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Qud's NoiseMap: sector seeds blurred by the 1-3-1 / 3-6-3 kernel, opened where the blur stands over 2.

const P = mathx.P;

pub const SECTORS_MAX: u8 = 6;
pub const SEEDS_MAX: u8 = 4;
pub const BLUR_MAX: u8 = 10;
/// Qud's: a seed's depth, the ground's top, and what the blur must stand over to open.
const DEPTH: f32 = 80;
const GROUND_TOP: u32 = 4;
const OPEN_OVER: f32 = 2;
const KERNEL = [3][3]f32{ .{ 1, 3, 1 }, .{ 3, 6, 3 }, .{ 1, 3, 1 } };
const KERNEL_SUM: f32 = 22;
/// Cells of rock kept round the map, Qud's border.
const BORDER: i32 = 3;

pub const Params = struct {
    /// Sectors across and down.
    sectors: u8 = 3,
    /// Deep points in each sector, at most.
    seeds: u8 = 2,
    blur: u8 = 5,

    pub fn fit(p: Params) Params {
        return .{ .sectors = std.math.clamp(p.sectors, 1, SECTORS_MAX), .seeds = @min(p.seeds, SEEDS_MAX), .blur = @min(p.blur, BLUR_MAX) };
    }
};

pub fn palette(_: Params) carve.Palette {
    return carve.Palette.CAVE;
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, pm: Params) void {
    var depth: [grid.CELLS]f32 = undefined;
    for (&depth) |*d| d.* = @floatFromInt(rng.below(GROUND_TOP + 1));
    const n: usize = pm.sectors;
    var order: [SECTORS_MAX * SECTORS_MAX]usize = undefined;
    for (order[0 .. n * n], 0..) |*o, i| o.* = i;
    shuffle(rng, order[0 .. n * n]);
    const sw = @divTrunc(grid.W - 2 * BORDER, @as(i32, @intCast(n)));
    const sh = @divTrunc(grid.H - 2 * BORDER, @as(i32, @intCast(n)));
    for (order[0 .. n * n]) |s| {
        const ox = BORDER + @as(i32, @intCast(s % n)) * sw;
        const oy = BORDER + @as(i32, @intCast(s / n)) * sh;
        for (0..rng.below(@as(u32, pm.seeds) + 1)) |_| {
            const p = P{ .x = rng.range(ox, ox + sw - 1), .y = rng.range(oy, oy + sh - 1) };
            depth[grid.Level.idx(p)] = DEPTH;
        }
    }
    var next: [grid.CELLS]f32 = undefined;
    for (0..pm.blur) |_| {
        for (0..grid.CELLS) |i| {
            const p = grid.Level.of(i);
            var sum: f32 = 0;
            for (KERNEL, 0..) |row, ky| {
                for (row, 0..) |k, kx| {
                    const q = p.add(.{ .x = @as(i32, @intCast(kx)) - 1, .y = @as(i32, @intCast(ky)) - 1 });
                    sum += k * grid.cellOr(f32, &depth, q, 0);
                }
            }
            next[i] = sum / KERNEL_SUM;
        }
        depth = next;
    }
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        const inner = grid.Level.edgeDist(p) >= BORDER;
        lv.tile[i] = if (inner and depth[i] > OPEN_OVER) .dirt else .rock;
    }
    if (carve.count(lv, .dirt) == 0) lv.set(grid.MIDDLE, .dirt);
}

fn shuffle(rng: *mathx.Rng, xs: []usize) void {
    var i = xs.len;
    while (i > 1) {
        i -= 1;
        const j = rng.below(@intCast(i + 1));
        std.mem.swap(usize, &xs[i], &xs[j]);
    }
}

test "strata open round their deep points, and more seeds open more" {
    var lv = grid.Level.blank();
    var few: usize = 0;
    var many: usize = 0;
    for (0..10) |i| {
        var rng = mathx.Rng.init(0x5A7A +% i);
        shape(&lv, &rng, 0, .{ .seeds = 1 });
        few += carve.count(&lv, .dirt);
        rng = mathx.Rng.init(0x5A7A +% i);
        shape(&lv, &rng, 0, .{ .seeds = 4 });
        many += carve.count(&lv, .dirt);
    }
    std.debug.print("10 strata: {d} open cells a map at 1 seed a sector, {d} at 4\n", .{ few / 10, many / 10 });
    try std.testing.expect(many > few);
}
