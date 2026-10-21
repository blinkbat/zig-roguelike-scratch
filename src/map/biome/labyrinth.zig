const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's Minotaur Maze and the Water Dragon's Lair, braided.

const P = mathx.P;

pub const CHAMBER_MAX: u8 = 20;
const CELLS_X: usize = @intCast(@divTrunc(grid.W - 1, 2));
const CELLS_Y: usize = @intCast(@divTrunc(grid.H - 1, 2));
const MID = P{ .x = CELLS_X / 2, .y = CELLS_Y / 2 };

pub const Style = enum { walls, rock, hedge };

pub const Params = struct {
    style: Style = .walls,
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

fn cellAt(c: P) P {
    return c.scaled(2).add(.{ .x = 1, .y = 1 });
}

const Unseen = struct {
    seen: *const [CELLS_X * CELLS_Y]bool,
    at: P,

    fn has(u: Unseen, s: P) bool {
        const near = mathx.slot(u.at.x + s.x, u.at.y + s.y, CELLS_X, CELLS_Y) orelse return false;
        return !u.seen[near];
    }
};

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    const pal = palette(p);
    carve.fill(lv, pal.solid);
    var seen = [_]bool{false} ** (CELLS_X * CELLS_Y);
    var stack: [CELLS_X * CELLS_Y]u16 = undefined;
    var top: usize = 1;
    const start = mathx.slot(MID.x, MID.y, CELLS_X, CELLS_Y).?;
    stack[0] = @intCast(start);
    seen[start] = true;
    lv.set(cellAt(mathx.unslot(start, CELLS_X)), pal.open);
    const steps = mathx.CARDINALS;
    while (top > 0) {
        const at = mathx.unslot(stack[top - 1], CELLS_X);
        const s = rng.pickWhere(P, &steps, Unseen{ .seen = &seen, .at = at }, Unseen.has) orelse {
            top -= 1;
            continue;
        };
        const next = at.add(s);
        const k = mathx.slot(next.x, next.y, CELLS_X, CELLS_Y).?;
        seen[k] = true;
        lv.set(cellAt(at).add(s), pal.open);
        lv.set(cellAt(next), pal.open);
        stack[top] = @intCast(k);
        top += 1;
    }
    for (0..CELLS_Y) |cy| {
        for (0..CELLS_X) |cx| {
            const c = cellAt(.{ .x = @intCast(cx), .y = @intCast(cy) });
            var walls: [steps.len]P = undefined;
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
            if (opens == 1 and n > 0 and rng.percent(p.braid)) {
                lv.set(rng.pick(P, walls[0..n]), pal.open);
            }
        }
    }
    if (p.chamber > 0) {
        const h: i32 = p.chamber;
        const w = @divTrunc(h * 3, 2);
        carve.box(lv, grid.Box.between(grid.MIDDLE.sub(.{ .x = w, .y = h }), grid.MIDDLE.add(.{ .x = w, .y = h })), pal.open);
    }
}

test "a perfect maze reaches every cell from the middle" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x3A2E);
    shape(&lv, &rng, 0, .{ .braid = 0 });
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const reached = grid.distances(&lv, cellAt(MID), &dist, &queue);
    std.debug.print("a {d}x{d} maze: {d} open cells, all reached: {}\n", .{ CELLS_X, CELLS_Y, carve.count(&lv, .floor), reached == carve.count(&lv, .floor) });
    try std.testing.expectEqual(carve.count(&lv, .floor), reached);
    try std.testing.expectEqual(CELLS_X * CELLS_Y * 2 - 1, reached);
}
