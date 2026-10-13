const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Path of Exile's Twilight Strand, Dwarf Fortress's ocean edge: the sea along one side, its surf, then a beach.

const P = mathx.P;

pub const SEA_MAX: u8 = 24;
pub const SHORE_MAX: u8 = 8;
pub const BEACH_MAX: u8 = 16;
pub const ROUGH_MAX: u8 = 12;
/// Cells along the coast over which a line wanders once.
const WANDER: f32 = 9;
/// Noise rows far enough apart that the waterline and the beach's inland edge wander apart.
const BEACH_ROW: i32 = 1 << 10;

pub const Side = enum { west, east, north, south };

pub const Params = struct {
    side: Side = .west,
    /// Cells of deep water in from the edge.
    sea: u8 = 6,
    /// Cells of shallows past it.
    shore: u8 = 2,
    /// Cells of sand past them.
    beach: u8 = 5,
    /// Cells each line wanders either way, at most.
    rough: u8 = 3,

    pub fn fit(p: Params) Params {
        var q = p;
        q.sea = std.math.clamp(p.sea, 1, SEA_MAX);
        q.shore = @min(p.shore, SHORE_MAX);
        q.beach = @min(p.beach, BEACH_MAX);
        q.rough = @min(p.rough, ROUGH_MAX);
        return q;
    }
};

/// Cells in from `side`'s edge, and along it.
fn inFrom(q: P, side: Side) struct { in: i32, along: i32 } {
    return switch (side) {
        .west => .{ .in = q.x, .along = q.y },
        .east => .{ .in = grid.W - 1 - q.x, .along = q.y },
        .north => .{ .in = q.y, .along = q.x },
        .south => .{ .in = grid.H - 1 - q.y, .along = q.x },
    };
}

pub fn apply(lv: *grid.Level, _: *mathx.Rng, seed: u64, _: carve.Palette, p: Params) void {
    const noise = carve.Noise.init(seed ^ 0xC0A5);
    const rough: f32 = @floatFromInt(p.rough);
    for (0..grid.CELLS) |i| {
        const c = inFrom(grid.Level.of(i), p.side);
        const surf = (noise.at(.{ .x = c.along, .y = 0 }, WANDER, 2) * 2 - 1) * rough;
        const dune = (noise.at(.{ .x = c.along, .y = BEACH_ROW }, WANDER, 2) * 2 - 1) * rough;
        const water = @max(1, @as(f32, @floatFromInt(p.sea)) + surf);
        const shallows = water + @as(f32, @floatFromInt(p.shore));
        const sand = shallows + @max(0, @as(f32, @floatFromInt(p.beach)) + dune);
        const in: f32 = @floatFromInt(c.in);
        if (in < water) {
            lv.tile[i] = .water;
        } else if (in < shallows) {
            lv.tile[i] = .shallows;
        } else if (in < sand) lv.tile[i] = .sand;
    }
}

test "a coast lies deep water, then shallows, then sand, in from its own side alone" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xC0A5);
    for (std.enums.values(Side)) |side| {
        carve.field(&lv, carve.Palette.WILD);
        const p = (Params{ .side = side, .sea = 6, .shore = 2, .beach = 5, .rough = 3 }).fit();
        apply(&lv, &rng, 7, carve.Palette.WILD, p);
        var far: i32 = 0;
        for (0..grid.CELLS) |k| {
            const c = inFrom(grid.Level.of(k), side);
            const t = lv.tile[k];
            if (c.in < p.sea - p.rough) try std.testing.expectEqual(grid.Tile.water, t);
            if (t == .water or t == .shallows or t == .sand) far = @max(far, c.in);
            if (t == .shallows) try std.testing.expect(c.in >= 1);
        }
        std.debug.print("a coast on the {s}: {d} water, {d} shallows, {d} sand, reaching {d} cells in\n", .{ @tagName(side), carve.count(&lv, .water), carve.count(&lv, .shallows), carve.count(&lv, .sand), far });
        try std.testing.expect(far <= p.sea + p.shore + p.beach + 2 * p.rough);
    }
}
