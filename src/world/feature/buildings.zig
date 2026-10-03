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

pub const Box = struct {
    lo: P,
    hi: P,

    pub fn inner(b: Box) Box {
        return .{ .lo = b.lo.add(.{ .x = 1, .y = 1 }), .hi = b.hi.sub(.{ .x = 1, .y = 1 }) };
    }

    pub fn onEdge(b: Box, p: P) bool {
        return p.x == b.lo.x or p.y == b.lo.y or p.x == b.hi.x - 1 or p.y == b.hi.y - 1;
    }
};

/// A `w` by `h` box clear of liquid, doors, bridges and every box in `taken`, a cell of margin round it.
pub fn site(lv: *const grid.Level, rng: *mathx.Rng, w: i32, h: i32, taken: []const Box) ?Box {
    if (w + 4 > grid.W or h + 4 > grid.H) return null;
    for (0..TRIES) |_| {
        const lo = P{ .x = rng.range(2, grid.W - 2 - w), .y = rng.range(2, grid.H - 2 - h) };
        const b = Box{ .lo = lo, .hi = lo.add(.{ .x = w, .y = h }) };
        if (fits(lv, b, taken)) return b;
    }
    return null;
}

fn fits(lv: *const grid.Level, b: Box, taken: []const Box) bool {
    for (taken) |t| {
        if (b.lo.x - 1 < t.hi.x and b.hi.x + 1 > t.lo.x and b.lo.y - 1 < t.hi.y and b.hi.y + 1 > t.lo.y) return false;
    }
    var cells = grid.Cells.of(b.lo.sub(.{ .x = 1, .y = 1 }), b.hi.add(.{ .x = 1, .y = 1 }));
    while (cells.next()) |q| {
        const t = lv.at(q);
        if (t.liquid() or t == .bridge or lv.doorAt(q) != null) return false;
    }
    return true;
}

/// A cell on the box's outline, not a corner, and the cell outside it.
pub fn doorway(rng: *mathx.Rng, b: Box) [2]P {
    return switch (rng.below(4)) {
        0 => blk: {
            const x = rng.range(b.lo.x + 1, b.hi.x - 2);
            break :blk .{ .{ .x = x, .y = b.lo.y }, .{ .x = x, .y = b.lo.y - 1 } };
        },
        1 => blk: {
            const x = rng.range(b.lo.x + 1, b.hi.x - 2);
            break :blk .{ .{ .x = x, .y = b.hi.y - 1 }, .{ .x = x, .y = b.hi.y } };
        },
        2 => blk: {
            const y = rng.range(b.lo.y + 1, b.hi.y - 2);
            break :blk .{ .{ .x = b.lo.x, .y = y }, .{ .x = b.lo.x - 1, .y = y } };
        },
        else => blk: {
            const y = rng.range(b.lo.y + 1, b.hi.y - 2);
            break :blk .{ .{ .x = b.hi.x - 1, .y = y }, .{ .x = b.hi.x, .y = y } };
        },
    };
}

/// The box's floor cut into rooms by walls, each wall with a doorway, until no room is wider than twice `least`.
pub fn partition(lv: *grid.Level, rng: *mathx.Rng, inside: Box, least: i32, walls: grid.Tile) void {
    var stack: [64]Box = undefined;
    stack[0] = inside;
    var n: usize = 1;
    while (n > 0) {
        n -= 1;
        const b = stack[n];
        const w = b.hi.x - b.lo.x;
        const h = b.hi.y - b.lo.y;
        const across = if (w >= 2 * least + 1 and h >= 2 * least + 1) rng.chance(@as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(w + h))) else w >= 2 * least + 1;
        if (!across and h < 2 * least + 1) continue;
        if (n + 2 > stack.len) continue;
        if (across) {
            const x = rng.range(b.lo.x + least, b.hi.x - least - 1);
            var y = b.lo.y;
            while (y < b.hi.y) : (y += 1) lv.set(.{ .x = x, .y = y }, walls);
            lv.set(.{ .x = x, .y = rng.range(b.lo.y, b.hi.y - 1) }, .floor);
            stack[n] = .{ .lo = b.lo, .hi = .{ .x = x, .y = b.hi.y } };
            stack[n + 1] = .{ .lo = .{ .x = x + 1, .y = b.lo.y }, .hi = b.hi };
        } else {
            const y = rng.range(b.lo.y + least, b.hi.y - least - 1);
            var x = b.lo.x;
            while (x < b.hi.x) : (x += 1) lv.set(.{ .x = x, .y = y }, walls);
            lv.set(.{ .x = rng.range(b.lo.x, b.hi.x - 1), .y = y }, .floor);
            stack[n] = .{ .lo = b.lo, .hi = .{ .x = b.hi.x, .y = y } };
            stack[n + 1] = .{ .lo = .{ .x = b.lo.x, .y = y + 1 }, .hi = b.hi };
        }
        n += 2;
    }
}

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, pal: carve.Palette, p: Params) void {
    var taken: [COUNT_MAX]Box = undefined;
    var n: usize = 0;
    for (0..p.count) |_| {
        const w = rng.range(p.size[0], p.size[1]);
        const h = rng.range(p.size[0], @max(p.size[0], @divTrunc(p.size[1] * 3, 4)));
        const b = site(lv, rng, w, h, taken[0..n]) orelse continue;
        taken[n] = b;
        n += 1;
        raise(lv, rng, b, p, pal.open);
    }
}

/// Walled round on `b`'s outline, a doorway out onto `outside`, a torch and barrels as `p` says.
pub fn raise(lv: *grid.Level, rng: *mathx.Rng, b: Box, p: Params, outside: grid.Tile) void {
    var cells = grid.Cells.of(b.lo, b.hi);
    while (cells.next()) |q| {
        const edge = b.onEdge(q);
        const fallen = carve.percent(rng, if (edge) p.decay else p.decay / 2);
        lv.set(q, if (fallen) .rubble else if (edge) p.walls else p.floor);
    }
    const way = doorway(rng, b);
    lv.set(way[0], p.floor);
    if (lv.at(way[1]).solid()) lv.set(way[1], outside);
    const in = b.inner();
    if (carve.percent(rng, p.torches) and in.hi.x - in.lo.x > 2) lv.addTorch(.{ .x = rng.range(in.lo.x + 1, in.hi.x - 2), .y = b.lo.y });
    var left = rng.below(@as(u32, p.barrels) + 1);
    var tries: usize = 0;
    while (left > 0 and tries < 40) : (tries += 1) {
        const q = P{ .x = rng.range(in.lo.x, in.hi.x - 1), .y = rng.range(in.lo.y, in.hi.y - 1) };
        if (!in.onEdge(q) or mathx.dist(q, way[0]) <= 1 or lv.at(q) != p.floor) continue;
        lv.putBarrel(q);
        left -= 1;
    }
}

test "buildings stand walled with a way in, and decayed ones lie in rubble" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xB111);
    carve.fill(&lv, .grass);
    carve.rim(&lv, .shrub);
    const pal = carve.Palette{ .open = .grass, .solid = .shrub, .path = .grass };
    apply(&lv, &rng, 0, pal, .{ .count = 8 });
    const walls = carve.count(&lv, .wall);
    apply(&lv, &rng, 0, pal, .{ .count = 8, .decay = 60 });
    std.debug.print("8 houses: {d} wall cells; 8 more at 60% decay: {d} rubble\n", .{ walls, carve.count(&lv, .rubble) });
    try std.testing.expect(walls > 8 * 12 and carve.count(&lv, .rubble) > 40);
}
