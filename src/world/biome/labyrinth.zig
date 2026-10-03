const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's Minotaur Maze and the Water Dragon's Lair, braided.

const P = mathx.P;

pub const CHAMBER_MAX: u8 = 20;
const CELLS_X: usize = @intCast(@divTrunc(grid.W - 1, 2));
const CELLS_Y: usize = @intCast(@divTrunc(grid.H - 1, 2));

pub const Style = enum { walls, rock, hedge };

pub const Params = struct {
    style: Style = .walls,
    /// Half-height of an open chamber at the heart, half again as wide; 0 has none.
    chamber: u8 = 0,
    /// Percent of dead ends knocked through.
    braid: u8 = 10,

    pub fn fit(p: Params) Params {
        var q = p;
        q.chamber = @min(p.chamber, CHAMBER_MAX);
        q.braid = @min(p.braid, mathx.PERCENT);
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    return switch (p.style) {
        .walls => carve.Palette.BUILT,
        .rock => carve.Palette.CAVE,
        .hedge => carve.Palette.WILD,
    };
}

fn cellAt(cx: usize, cy: usize) P {
    return .{ .x = @intCast(cx * 2 + 1), .y = @intCast(cy * 2 + 1) };
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    const pal = palette(p);
    carve.fill(lv, pal.solid);
    var seen = [_]bool{false} ** (CELLS_X * CELLS_Y);
    var stack: [CELLS_X * CELLS_Y]u16 = undefined;
    var top: usize = 1;
    const start = (CELLS_Y / 2) * CELLS_X + CELLS_X / 2;
    stack[0] = @intCast(start);
    seen[start] = true;
    lv.set(cellAt(start % CELLS_X, start / CELLS_X), pal.open);
    const steps = mathx.CARDINALS;
    while (top > 0) {
        const at = stack[top - 1];
        const cx: i32 = @intCast(at % CELLS_X);
        const cy: i32 = @intCast(at / CELLS_X);
        var open: [4]usize = undefined;
        var n: usize = 0;
        for (steps, 0..) |s, k| {
            const nx = cx + s.x;
            const ny = cy + s.y;
            if (nx < 0 or ny < 0 or nx >= CELLS_X or ny >= CELLS_Y) continue;
            if (seen[@as(usize, @intCast(ny)) * CELLS_X + @as(usize, @intCast(nx))]) continue;
            open[n] = k;
            n += 1;
        }
        if (n == 0) {
            top -= 1;
            continue;
        }
        const s = steps[open[rng.below(@intCast(n))]];
        const nx: usize = @intCast(cx + s.x);
        const ny: usize = @intCast(cy + s.y);
        const k = ny * CELLS_X + nx;
        seen[k] = true;
        const here = cellAt(@intCast(cx), @intCast(cy));
        lv.set(here.add(s), pal.open);
        lv.set(cellAt(nx, ny), pal.open);
        stack[top] = @intCast(k);
        top += 1;
    }
    for (0..CELLS_Y) |cy| {
        for (0..CELLS_X) |cx| {
            const c = cellAt(cx, cy);
            var walls: [4]P = undefined;
            var n: usize = 0;
            var opens: usize = 0;
            for (steps) |s| {
                const w = c.add(s);
                if (lv.at(w) == pal.open) {
                    opens += 1;
                } else if (!grid.Level.onRim(w) and !grid.Level.onRim(w.add(s))) {
                    walls[n] = w;
                    n += 1;
                }
            }
            if (opens == 1 and n > 0 and rng.percent(p.braid)) lv.set(walls[rng.below(@intCast(n))], pal.open);
        }
    }
    if (p.chamber > 0) {
        const h: i32 = p.chamber;
        carve.box(lv, grid.MIDDLE.sub(.{ .x = @divTrunc(h * 3, 2), .y = h }), grid.MIDDLE.add(.{ .x = @divTrunc(h * 3, 2) + 1, .y = h + 1 }), pal.open);
    }
}

test "a perfect maze reaches every cell from the middle" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x3A2E);
    shape(&lv, &rng, 0, .{ .braid = 0 });
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const reached = grid.distances(&lv, cellAt(CELLS_X / 2, CELLS_Y / 2), &dist, &queue);
    std.debug.print("a {d}x{d} maze: {d} open cells, all reached: {}\n", .{ CELLS_X, CELLS_Y, carve.count(&lv, .floor), reached == carve.count(&lv, .floor) });
    try std.testing.expectEqual(carve.count(&lv, .floor), reached);
    try std.testing.expectEqual(CELLS_X * CELLS_Y * 2 - 1, reached);
}
