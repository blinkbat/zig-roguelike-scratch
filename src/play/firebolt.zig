const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");

const P = mathx.P;

pub const NAME = "firebolt";
pub const ELEMENT: damage.Element = .fire;
/// Of a cell, how far toward its first cell a bolt not yet flown is drawn.
const HAND: f32 = 0.35;

/// Thrown every `every` turns once the last has come down; it flies `speed` cells a turn, `range` at most.
pub const Hurl = struct { range: i32, speed: u8, every: u8, hit: damage.Base, burns: u32 };

/// In flight along the line from `from` through `toward`, `flown` cells out.
pub const Bolt = struct {
    from: P,
    toward: P,
    flown: u8 = 0,

    /// At `at`, its line carried on past it.
    pub fn aimed(from: P, mark: P, range: i32) Bolt {
        const d = mathx.dist(from, mark);
        std.debug.assert(d > 0);
        return .{ .from = from, .toward = from.add(mark.sub(from).scaled(@divFloor(range + d - 1, d))) };
    }

    /// The cell `k` along its line; `from` itself at 0.
    pub fn cell(b: Bolt, k: usize) P {
        var ray = grid.Ray.init(b.from, b.toward);
        var c = b.from;
        for (0..k) |_| c = ray.next() orelse break;
        return c;
    }

    /// Thrown from a cell on the map, along a line, no farther out than that line runs.
    pub fn valid(b: Bolt) bool {
        return grid.Level.inside(b.from) and !b.from.eq(b.toward) and b.flown <= mathx.dist(b.from, b.toward);
    }

    pub fn at(b: Bolt) P {
        return b.cell(b.flown);
    }

    /// Where it is drawn, in cells: one not yet flown sits in the hand that threw it.
    pub fn point(b: Bolt) [2]f32 {
        if (b.flown > 0) return mathx.centre(b.at());
        return mathx.lerp2(mathx.centre(b.from), mathx.centre(b.cell(1)), HAND);
    }

    pub fn heading(b: Bolt) [2]f32 {
        const a = mathx.centre(b.from);
        const z = mathx.centre(b.toward);
        const len = @max(0.001, mathx.len(z[0] - a[0], z[1] - a[1]));
        return .{ (z[0] - a[0]) / len, (z[1] - a[1]) / len };
    }
};

/// What it came down on: a body or barrel in the cell it entered, a wall short of it, or the end of its range.
pub const Stop = union(enum) { body: u16, barrel: P, wall, spent };

pub const Flew = struct { cells: u8 = 0, stop: ?Stop = null };

/// `speed` cells on, or fewer where it comes down; it enters a body's or barrel's cell, but not a wall's.
pub fn fly(b: *Bolt, lv: *const grid.Level, h: Hurl) Flew {
    var out = Flew{};
    while (out.cells < h.speed) {
        if (b.flown >= h.range) {
            out.stop = .spent;
            return out;
        }
        const c = b.cell(b.flown + 1);
        if (!grid.Level.inside(c) or lv.hasBarrier(c)) {
            out.stop = .wall;
            return out;
        }
        const w = lv.who(c);
        const t = lv.at(c);
        if (w == grid.NO_ONE and !lv.hasBarrel(c) and t.solid() and t.blind()) {
            out.stop = .wall;
            return out;
        }
        b.flown += 1;
        out.cells += 1;
        if (w != grid.NO_ONE) {
            out.stop = .{ .body = w };
            return out;
        }
        if (lv.hasBarrel(c)) {
            out.stop = .{ .barrel = c };
            return out;
        }
        if (t.halts()) {
            out.stop = .wall;
            return out;
        }
    }
    if (b.flown >= h.range) out.stop = .spent;
    return out;
}

const TEST_HURL = Hurl{ .range = 6, .speed = 2, .every = 2, .hit = .{ .lo = 1, .hi = 1 }, .burns = 0 };

test "a bolt flies its speed a turn along its line and is spent at its range" {
    const lv = grid.openFloor();
    var b = Bolt.aimed(.{ .x = 10, .y = 10 }, .{ .x = 12, .y = 11 }, TEST_HURL.range);
    try std.testing.expectEqual(P{ .x = 10, .y = 10 }, b.at());
    var flown: [3]Flew = undefined;
    for (&flown) |*f| f.* = fly(&b, &lv, TEST_HURL);
    for (flown[0..2]) |f| try std.testing.expectEqual(Flew{ .cells = 2 }, f);
    try std.testing.expectEqual(Flew{ .cells = 2, .stop = .spent }, flown[2]);
    try std.testing.expectEqual(P{ .x = 16, .y = 13 }, b.at());
    try std.testing.expectEqual(P{ .x = 12, .y = 11 }, b.cell(2));
}

test "a bolt enters a body's or barrel's cell, stops short of a wall, and never leaves its line" {
    var lv = grid.openFloor();
    var b = Bolt.aimed(.{ .x = 10, .y = 10 }, .{ .x = 11, .y = 10 }, TEST_HURL.range);
    lv.stand(.{ .x = 12, .y = 10 }, 3);
    try std.testing.expectEqual(Flew{ .cells = 2, .stop = .{ .body = 3 } }, fly(&b, &lv, TEST_HURL));
    lv.clear(.{ .x = 12, .y = 10 });
    lv.putBarrel(.{ .x = 13, .y = 10 });
    try std.testing.expectEqual(Flew{ .cells = 1, .stop = .{ .barrel = .{ .x = 13, .y = 10 } } }, fly(&b, &lv, TEST_HURL));
    var w = Bolt.aimed(.{ .x = 10, .y = 10 }, .{ .x = 10, .y = 14 }, TEST_HURL.range);
    lv.set(.{ .x = 10, .y = 12 }, .wall);
    try std.testing.expectEqual(Flew{ .cells = 1, .stop = .wall }, fly(&w, &lv, TEST_HURL));
    try std.testing.expectEqual(P{ .x = 10, .y = 11 }, w.at());
}
