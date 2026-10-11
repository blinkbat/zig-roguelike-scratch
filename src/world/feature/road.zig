const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Path of Exile's main path, ADOM's roads, Dwarf Fortress's hamlet roads.

pub const WIDTH_MIN: u8 = carve.LANE_MIN;
pub const WIDTH_MAX: u8 = 5;
pub const COUNT_MAX: u8 = 3;

pub const Paving = enum {
    dirt,
    sand,
    floor,
    rubble,
    snow,
    grass,

    pub fn tile(p: Paving) grid.Tile {
        return carve.tileOf(p);
    }
};

pub const Params = struct {
    paving: Paving = .dirt,
    width: u8 = 2,
    course: carve.Course = .across,
    count: u8 = 1,
    /// Percent of `carve.Meander`'s full wandering.
    wander: u8 = 40,

    pub fn fit(p: Params) Params {
        var q = p;
        q.width = std.math.clamp(p.width, WIDTH_MIN, WIDTH_MAX);
        q.count = std.math.clamp(p.count, 1, COUNT_MAX);
        q.wander = @min(p.wander, mathx.PERCENT);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, _: carve.Palette, p: Params) void {
    for (0..p.count) |_| {
        const ends = p.course.ends(rng);
        carve.lane(lv, rng, ends[0], ends[1], p.width, mathx.fraction(p.wander), p.paving.tile(), .road);
    }
}

test "a road crosses the map whole and bridges a river" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x20AD);
    carve.fill(&lv, .shrub);
    carve.Flow.of(&rng, .{ .x = 40, .y = 0 }, .{ .x = 44, .y = grid.H - 1 }, null).fill(&lv, 3, .water);
    apply(&lv, &rng, 0, carve.Palette.WILD, .{ .course = .across, .wander = 0 });
    var st: carve.Stretches = .{};
    const parts = st.label(&lv);
    std.debug.print("a straight road through a forest and over a river: {d} road, {d} bridge, {d} stretch of ground\n", .{ carve.count(&lv, .dirt), carve.count(&lv, .bridge), parts });
    try std.testing.expectEqual(@as(usize, 1), parts);
    try std.testing.expect(carve.count(&lv, .bridge) > 0);
}

test "every road width draws a different map" {
    var maps: [WIDTH_MAX - WIDTH_MIN + 1][grid.CELLS]grid.Tile = undefined;
    for (&maps, WIDTH_MIN..) |*tiles, w| {
        var lv = grid.Level.blank();
        var rng = mathx.Rng.init(0x20AD);
        carve.fill(&lv, .shrub);
        apply(&lv, &rng, 0, carve.Palette.WILD, (Params{ .width = @intCast(w) }).fit());
        tiles.* = lv.tile;
        for (maps[0 .. w - WIDTH_MIN]) |*was| try std.testing.expect(!std.mem.eql(grid.Tile, was, tiles));
    }
    try std.testing.expectEqual(WIDTH_MIN, (Params{ .width = 1 }).fit().width);
}
