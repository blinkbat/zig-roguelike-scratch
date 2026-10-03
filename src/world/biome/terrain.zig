const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Dwarf Fortress's fields, classed by its getBiomeType checks; narrow the ranges for one biome, widen them for many.

const P = mathx.P;

pub const SCALE_MIN: u8 = 6;
pub const SCALE_MAX: u8 = 64;
pub const RIVERS_MAX: u8 = 6;
const RIVER_STEPS: usize = 600;
/// Cold lowers with height above this elevation, a point of heat for every point of height, as DF biases it.
const LAPSE_FROM: f32 = 60;
/// A river may start where the height is at least this share of the highest.
const SOURCE_OVER: f32 = 0.75;

pub const Biome = enum { ocean, coast, beach, mountain, foothills, glacier, tundra, desert, wasteland, badlands, grassland, savanna, shrubland, marsh, swamp, forest, taiga };

pub const Params = struct {
    /// Lowest and highest, 0 to 100, each field rolled between them.
    height: [2]u8 = .{ 25, 85 },
    rain: [2]u8 = .{ 0, 100 },
    drain: [2]u8 = .{ 0, 100 },
    heat: [2]u8 = .{ 20, 80 },
    /// Cells across a field's features.
    scale: u8 = 28,
    rivers: u8 = 1,
    litter: carve.Litter = .{},
    decor: carve.Decor = .{},

    pub fn fit(p: Params) Params {
        var q = p;
        q.height = range(p.height);
        q.rain = range(p.rain);
        q.drain = range(p.drain);
        q.heat = range(p.heat);
        q.scale = std.math.clamp(p.scale, SCALE_MIN, SCALE_MAX);
        q.rivers = @min(p.rivers, RIVERS_MAX);
        q.litter = p.litter.fit();
        q.decor = p.decor.fit();
        return q;
    }

    fn range(r: [2]u8) [2]u8 {
        return mathx.span(u8, r, 0, mathx.PERCENT);
    }
};

pub fn palette(_: Params) carve.Palette {
    return .{ .open = .grass, .solid = .rock, .path = .dirt };
}

fn lerp(r: [2]u8, t: f32) f32 {
    return mathx.lerpF(@floatFromInt(r[0]), @floatFromInt(r[1]), t);
}

/// Below this height is sea or shore, where a river ends.
const SHORE: f32 = 26;
const SOURCE_TRIES: usize = 400;
/// Below this height is ocean.
pub const SEA = 20;
/// From this height up is mountain.
pub const MOUNTAIN = 90;
/// At this heat and under is tundra or glacier.
pub const FROST = 10;

/// DF v50's order: lake and mountain and ocean by height, then cold, then rain against drainage.
pub fn classify(height: f32, rain: f32, drain: f32, heat: f32) Biome {
    if (height < SEA) return .ocean;
    if (height < 23) return .coast;
    if (height < SHORE) return .beach;
    if (height >= MOUNTAIN) return .mountain;
    if (height >= 84) return .foothills;
    if (heat <= FROST) return if (drain < 75) .tundra else .glacier;
    if (rain < 10) return if (drain < 33) .desert else if (drain <= 65) .wasteland else .badlands;
    if (rain < 20) return .grassland;
    if (rain < 33) return .savanna;
    if (rain <= 65) return if (drain > 32) .shrubland else .marsh;
    if (drain < 33) return .swamp;
    return if (heat > 25) .forest else .taiga;
}

/// `v` is its fine noise there, `roll` a die from 0 to 1.
fn groundOf(b: Biome, v: f32, roll: f32) grid.Tile {
    return switch (b) {
        .ocean => .water,
        .coast => .shallows,
        .beach => if (roll < 0.03) .rubble else .sand,
        .mountain => if (v > 0.62) .rubble else .rock,
        .foothills => if (v > 0.7) .rock else if (v > 0.45) .rubble else .grass,
        .glacier => if (v > 0.5) .snow else .ice,
        .tundra => if (v < 0.15) .ice else if (v > 0.65) .grass else .snow,
        .desert => if (v > 0.8) .rock else .sand,
        .wasteland => if (v > 0.74) .rock else if (roll < 0.1) .rubble else .dirt,
        .badlands => if (@abs(v - 0.5) < 0.04) .rock else .dirt,
        .grassland => if (roll < 0.01) .shrub else .grass,
        .savanna => if (roll < 0.04) .shrub else .grass,
        .shrubland => if (v > 0.6) .shrub else if (roll < 0.03) .shrub else .grass,
        .marsh => if (v > 0.74) .water else if (v > 0.58) .shallows else if (v > 0.44) .reeds else .grass,
        .swamp => if (v > 0.7) .water else if (v > 0.52) .shallows else if (roll < 0.4) .shrub else .grass,
        .forest => if (v > 0.42) .shrub else .grass,
        .taiga => if (v > 0.5) .shrub else .snow,
    };
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, seed: u64, p: Params) void {
    const s: f32 = @floatFromInt(p.scale);
    const fields = [_]carve.Noise{ .init(seed ^ 0x4E16), .init(seed ^ 0x2A1F), .init(seed ^ 0xD2A1), .init(seed ^ 0x4EA7), .init(seed ^ 0xF1E1) };
    var height: [grid.CELLS]f32 = undefined;
    for (0..grid.CELLS) |i| {
        const q = grid.Level.of(i);
        const h = lerp(p.height, stretch(fields[0].at(q, s, 4)));
        height[i] = h;
        const heat = lerp(p.heat, stretch(fields[3].at(q, s * 2, 2))) - @max(0, h - LAPSE_FROM);
        const b = classify(h, lerp(p.rain, stretch(fields[1].at(q, s, 3))), lerp(p.drain, stretch(fields[2].at(q, s, 3))), heat);
        lv.tile[i] = groundOf(b, fields[4].at(q, 5, 2), rng.unit());
    }
    for (0..p.rivers) |_| river(lv, rng, &height);
    carve.rim(lv, palette(p).solid);
}

/// Value noise bunches round the middle; this spreads it back toward 0 and 1.
fn stretch(v: f32) f32 {
    return std.math.clamp((v - 0.5) * 1.8 + 0.5, 0, 1);
}

/// From a high cell, each step to the lowest neighbour, digging where none is lower, until water or the edge.
fn river(lv: *grid.Level, rng: *mathx.Rng, height: *[grid.CELLS]f32) void {
    var top: f32 = 0;
    for (height) |h| top = @max(top, h);
    var at: P = for (0..SOURCE_TRIES) |_| {
        const q = grid.Box.inMap(2).roll(rng);
        if (height[grid.Level.idx(q)] >= top * SOURCE_OVER) break q;
    } else return;
    const dirs = mathx.CARDINALS;
    for (0..RIVER_STEPS) |_| {
        const i = grid.Level.idx(at);
        if (lv.tile[i] == .water and height[i] < SHORE) return;
        lv.tile[i] = .water;
        var best: ?P = null;
        var best_h: f32 = std.math.floatMax(f32);
        for (dirs) |d| {
            const q = at.add(d);
            if (!grid.Level.inside(q)) return;
            const k = grid.Level.idx(q);
            if (lv.tile[k] == .water and height[k] >= SHORE) continue;
            const h = height[k] + rng.unit() * 0.5;
            if (h < best_h) {
                best_h = h;
                best = q;
            }
        }
        const next = best orelse return;
        const k = grid.Level.idx(next);
        if (height[k] >= height[i]) height[k] = height[i] - 0.01;
        for (dirs) |d| {
            const b = at.add(d);
            if (grid.Level.inside(b) and !lv.at(b).liquid() and rng.chance(0.3)) lv.set(b, .shallows);
        }
        at = next;
    }
}

test "the classes follow Dwarf Fortress's checks" {
    try std.testing.expectEqual(Biome.ocean, classify(10, 50, 50, 50));
    try std.testing.expectEqual(Biome.mountain, classify(95, 50, 50, 50));
    try std.testing.expectEqual(Biome.glacier, classify(50, 50, 80, 5));
    try std.testing.expectEqual(Biome.tundra, classify(50, 50, 20, 5));
    try std.testing.expectEqual(Biome.desert, classify(50, 5, 10, 60));
    try std.testing.expectEqual(Biome.badlands, classify(50, 5, 80, 60));
    try std.testing.expectEqual(Biome.savanna, classify(50, 25, 50, 60));
    try std.testing.expectEqual(Biome.marsh, classify(50, 50, 20, 60));
    try std.testing.expectEqual(Biome.swamp, classify(50, 80, 20, 60));
    try std.testing.expectEqual(Biome.forest, classify(50, 80, 50, 60));
    try std.testing.expectEqual(Biome.taiga, classify(50, 80, 50, 20));
}

test "a narrowed field gives one biome's ground, and a wide one many" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xDF);
    shape(&lv, &rng, 7, .{ .height = .{ 50, 60 }, .rain = .{ 70, 100 }, .drain = .{ 50, 100 }, .heat = .{ 12, 24 }, .rivers = 0 });
    const taiga = carve.count(&lv, .snow) + carve.count(&lv, .shrub);
    shape(&lv, &rng, 7, .{});
    var kinds: usize = 0;
    for (std.enums.values(grid.Tile)) |t| {
        if (carve.count(&lv, t) > 0) kinds += 1;
    }
    std.debug.print("a taiga: {d} of {d} cells snow or conifer; a wide region: {d} kinds of ground, {d} water\n", .{ taiga, grid.CELLS, kinds, carve.count(&lv, .water) });
    try std.testing.expect(taiga * 10 > grid.CELLS * 8);
    try std.testing.expect(kinds >= 6);
}
