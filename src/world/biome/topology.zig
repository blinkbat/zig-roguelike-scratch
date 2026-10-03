const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Path of Exile's topology graphs; the layouts are Grim Tangle, Red Vale, Keth, Manor Ramparts, the Crossroads,
// Mawdun Quarry, Jungle Ruins and Dried Lake.

const P = mathx.P;

pub const CLEARING_MIN: u8 = 2;
pub const CLEARING_MAX: u8 = 12;
pub const PATH_MAX: u8 = 6;
pub const SIDES_MAX: u8 = 10;
/// A spot lands within this share of the box from where its layout puts it.
const JITTER: f32 = 0.06;
const SIDE_REACH: i32 = 14;
/// Cells between a clearing's rim and the map's edge.
const RIM_GAP: i32 = 2;
/// Of the box's shorter side, a bowl's and the lakebed's half-width.
const BOWL_OF: f32 = 0.22;
const ARENA_OF: f32 = 0.42;
/// Of a clearing's radius, how far noise moves its edge in or out; less for a bowl or the lakebed.
const FRAY: f32 = 0.6;
const BIG_FRAY: f32 = 0.25;

pub const Layout = enum { line, ring, diamond, u, plus, bowls, grid, arena };

pub const Params = struct {
    layout: Layout = .line,
    filler: carve.Solid = .shrub,
    ground: carve.Ground = .grass,
    /// A spot's clearing, half-width.
    clearing: u8 = 5,
    path: u8 = 3,
    /// Side paths off to dead-end clearings.
    sides: u8 = 3,
    litter: carve.Litter = .{},

    pub fn fit(p: Params) Params {
        var q = p;
        q.clearing = std.math.clamp(p.clearing, CLEARING_MIN, CLEARING_MAX);
        q.path = std.math.clamp(p.path, 1, PATH_MAX);
        q.sides = @min(p.sides, SIDES_MAX);
        q.litter = p.litter.fit();
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    const g = p.ground.tile();
    return .{ .open = g, .solid = p.filler.tile(), .path = g, .pocket = p.filler.tile() };
}

const Spot = struct { x: f32, y: f32, big: bool = false };
const Edge = [2]u8;
const Graph = struct { spots: []const Spot, edges: []const Edge };

fn graphOf(l: Layout) Graph {
    return switch (l) {
        .line => .{ .spots = &.{ .{ .x = 0.04, .y = 0.5 }, .{ .x = 0.27, .y = 0.35 }, .{ .x = 0.5, .y = 0.62 }, .{ .x = 0.73, .y = 0.4 }, .{ .x = 0.96, .y = 0.55 } }, .edges = &.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 4 } } },
        .ring => .{ .spots = &.{ .{ .x = 0.5, .y = 0.12 }, .{ .x = 0.85, .y = 0.3 }, .{ .x = 0.85, .y = 0.7 }, .{ .x = 0.5, .y = 0.88 }, .{ .x = 0.15, .y = 0.7 }, .{ .x = 0.15, .y = 0.3 } }, .edges = &.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 4 }, .{ 4, 5 }, .{ 5, 0 } } },
        .diamond => .{ .spots = &.{ .{ .x = 0.5, .y = 0.08 }, .{ .x = 0.92, .y = 0.5 }, .{ .x = 0.5, .y = 0.92 }, .{ .x = 0.08, .y = 0.5 }, .{ .x = 0.5, .y = 0.5, .big = true } }, .edges = &.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 }, .{ 0, 4 }, .{ 4, 2 } } },
        .u => .{ .spots = &.{ .{ .x = 0.15, .y = 0.1 }, .{ .x = 0.13, .y = 0.55 }, .{ .x = 0.3, .y = 0.88 }, .{ .x = 0.7, .y = 0.88 }, .{ .x = 0.87, .y = 0.55 }, .{ .x = 0.85, .y = 0.1 } }, .edges = &.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 4 }, .{ 4, 5 } } },
        .plus => .{ .spots = &.{ .{ .x = 0.5, .y = 0.5, .big = true }, .{ .x = 0.05, .y = 0.5 }, .{ .x = 0.95, .y = 0.5 }, .{ .x = 0.5, .y = 0.06 }, .{ .x = 0.5, .y = 0.94 } }, .edges = &.{ .{ 0, 1 }, .{ 0, 2 }, .{ 0, 3 }, .{ 0, 4 } } },
        .bowls => .{ .spots = &.{ .{ .x = 0.03, .y = 0.5 }, .{ .x = 0.28, .y = 0.5, .big = true }, .{ .x = 0.72, .y = 0.5, .big = true }, .{ .x = 0.97, .y = 0.5 }, .{ .x = 0.5, .y = 0.15 }, .{ .x = 0.5, .y = 0.85 } }, .edges = &.{ .{ 0, 1 }, .{ 1, 4 }, .{ 4, 2 }, .{ 1, 5 }, .{ 5, 2 }, .{ 2, 3 } } },
        .grid => .{
            .spots = &.{ .{ .x = 0.15, .y = 0.17 }, .{ .x = 0.5, .y = 0.17 }, .{ .x = 0.85, .y = 0.17 }, .{ .x = 0.15, .y = 0.5 }, .{ .x = 0.5, .y = 0.5 }, .{ .x = 0.85, .y = 0.5 }, .{ .x = 0.15, .y = 0.83 }, .{ .x = 0.5, .y = 0.83 }, .{ .x = 0.85, .y = 0.83 } },
            .edges = &.{ .{ 0, 1 }, .{ 1, 2 }, .{ 3, 4 }, .{ 4, 5 }, .{ 6, 7 }, .{ 7, 8 }, .{ 0, 3 }, .{ 3, 6 }, .{ 1, 4 }, .{ 4, 7 }, .{ 2, 5 }, .{ 5, 8 } },
        },
        .arena => .{ .spots = &.{ .{ .x = 0.5, .y = 0.5, .big = true }, .{ .x = 0.04, .y = 0.5 }, .{ .x = 0.96, .y = 0.5 } }, .edges = &.{ .{ 1, 0 }, .{ 0, 2 } } },
    };
}

/// The most spots any layout has; every edge joins two of its own.
const NODES_MAX: usize = blk: {
    var most: usize = 0;
    for (std.enums.values(Layout)) |l| {
        const g = graphOf(l);
        for (g.edges) |e| std.debug.assert(e[0] < g.spots.len and e[1] < g.spots.len);
        most = @max(most, g.spots.len);
    }
    break :blk most;
};

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    const pal = palette(p);
    carve.fill(lv, pal.solid);
    const g = graphOf(p.layout);
    const noise = carve.Noise.init(seed ^ 0x70B0);
    const inset = p.clearing + RIM_GAP;
    const span = P{ .x = grid.W - 2 * inset, .y = grid.H - 2 * inset };
    var at: [NODES_MAX]P = undefined;
    for (g.spots, 0..) |s, i| {
        const fx = std.math.clamp(s.x + (rng.unit() - 0.5) * 2 * JITTER, 0, 1);
        const fy = std.math.clamp(s.y + (rng.unit() - 0.5) * 2 * JITTER, 0, 1);
        at[i] = .{ .x = inset + @as(i32, @intFromFloat(fx * @as(f32, @floatFromInt(span.x)))), .y = inset + @as(i32, @intFromFloat(fy * @as(f32, @floatFromInt(span.y)))) };
    }
    const short: f32 = @floatFromInt(@min(grid.W, grid.H));
    for (g.spots, 0..) |s, i| {
        const r: f32 = if (!s.big) @floatFromInt(p.clearing) else if (p.layout == .arena) short * ARENA_OF else short * BOWL_OF;
        clearing(lv, noise, at[i], r, if (s.big) BIG_FRAY else FRAY, pal.open);
    }
    const w = @as(f32, @floatFromInt(p.path - 1)) / 2;
    for (g.edges) |e| {
        if (p.layout == .grid and rng.chance(0.3)) continue;
        path(lv, rng, at[e[0]], at[e[1]], w, pal.open);
    }
    for (0..p.sides) |_| {
        const from = at[rng.below(@intCast(g.spots.len))];
        const to = P{
            .x = std.math.clamp(from.x + rng.range(-SIDE_REACH, SIDE_REACH), inset, grid.W - 1 - inset),
            .y = std.math.clamp(from.y + rng.range(-SIDE_REACH, SIDE_REACH), inset, grid.H - 1 - inset),
        };
        path(lv, rng, from, to, w, pal.open);
        clearing(lv, noise, to, @as(f32, @floatFromInt(p.clearing)) * 0.6, FRAY, pal.open);
    }
    p.litter.strew(lv, rng);
}

fn clearing(lv: *grid.Level, noise: carve.Noise, c: P, r: f32, fray: f32, open: grid.Tile) void {
    carve.blob(lv, noise, c, r, 4, 1 - fray / 2, fray, open);
}

fn path(lv: *grid.Level, rng: *mathx.Rng, a: P, b: P, w: f32, open: grid.Tile) void {
    var m = carve.Meander.init(a, b, 0.7);
    while (m.next(rng)) |c| carve.disc(lv, c, @max(w, 0.5) + 0.5, open, null);
}

test "every layout joins its spots" {
    var lv = grid.Level.blank();
    var st: carve.Stretches = .{};
    for (std.enums.values(Layout)) |l| {
        var rng = mathx.Rng.init(0x70B0);
        shape(&lv, &rng, 1, .{ .layout = l, .sides = 0 });
        const parts = st.label(&lv);
        std.debug.print("{s}: {d} open cells in {d} stretches\n", .{ @tagName(l), carve.count(&lv, .grass), parts });
        if (l != .grid) try std.testing.expectEqual(@as(usize, 1), parts);
    }
}
