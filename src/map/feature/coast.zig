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

pub const Side = enum {
    west,
    east,
    north,
    south,

    fn dir(s: Side) mathx.Dir {
        return switch (s) {
            .west => .w,
            .east => .e,
            .north => .n,
            .south => .s,
        };
    }
};

pub const Params = struct {
    side: Side = .west,
    sea: u8 = 6,
    shore: u8 = 2,
    beach: u8 = 5,
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

fn wander(noise: carve.Noise, along: usize, row: i32, rough: f32) f32 {
    return (noise.at(.{ .x = @intCast(along), .y = row }, WANDER, 2) * 2 - 1) * rough;
}

pub fn apply(lv: *grid.Level, _: *mathx.Rng, seed: u64, _: carve.Palette, p: Params) void {
    const noise = carve.Noise.init(seed, .coast);
    const rough: f32 = @floatFromInt(p.rough);
    var edges: [@max(grid.W, grid.H)]struct { water: f32, shallows: f32, sand: f32 } = undefined;
    const side = p.side.dir();
    const len: usize = @intCast(carve.alongOf(side, grid.SIZE));
    for (edges[0..len], 0..) |*edge, along| {
        const surf = wander(noise, along, 0, rough);
        const dune = wander(noise, along, BEACH_ROW, rough);
        const water = @max(1, @as(f32, @floatFromInt(p.sea)) + surf);
        const shallows = water + @as(f32, @floatFromInt(p.shore));
        edge.* = .{
            .water = water,
            .shallows = shallows,
            .sand = if (p.beach == 0) shallows else shallows + @max(0, @as(f32, @floatFromInt(p.beach)) + dune),
        };
    }
    for (0..grid.CELLS) |i| {
        const q = grid.Level.of(i);
        const along: usize = @intCast(carve.alongOf(side, q));
        const edge = edges[along];
        const in: f32 = @floatFromInt(carve.inFrom(side, q));
        if (in < edge.water) {
            lv.tile[i] = .water;
        } else if (in < edge.shallows) {
            lv.tile[i] = .shallows;
        } else if (in < edge.sand) lv.tile[i] = .sand;
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
            const in = carve.inFrom(side.dir(), grid.Level.of(k));
            const t = lv.tile[k];
            if (in < p.sea - p.rough) try std.testing.expectEqual(grid.Tile.water, t);
            if (t == .water or t == .shallows or t == .sand) far = @max(far, in);
            if (t == .shallows) try std.testing.expect(in >= 1);
        }
        std.debug.print("a coast on the {s}: {d} water, {d} shallows, {d} sand, reaching {d} cells in\n", .{ @tagName(side), carve.count(&lv, .water), carve.count(&lv, .shallows), carve.count(&lv, .sand), far });
        try std.testing.expect(far <= p.sea + p.shore + p.beach + 2 * p.rough);
    }
}

test "a coast with no beach lays no sand, however rough" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xC0A5);
    carve.field(&lv, carve.Palette.WILD);
    apply(&lv, &rng, 7, carve.Palette.WILD, (Params{ .beach = 0, .rough = ROUGH_MAX }).fit());
    try std.testing.expectEqual(@as(usize, 0), carve.count(&lv, .sand));
}
