const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Path of Exile's main path, ADOM's roads, Dwarf Fortress's hamlet roads.

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
        q.width = std.math.clamp(p.width, 1, WIDTH_MAX);
        q.count = std.math.clamp(p.count, 1, COUNT_MAX);
        q.wander = @min(p.wander, mathx.PERCENT);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, _: carve.Palette, p: Params) void {
    const r = @max(@as(f32, @floatFromInt(p.width - 1)) / 2, 0.5);
    const surface = p.paving.tile();
    for (0..p.count) |_| {
        const ends = p.course.ends(rng);
        var m = carve.Meander.init(ends[0], ends[1], mathx.fraction(p.wander));
        while (m.next(rng)) |c| {
            const k: i32 = @intFromFloat(@ceil(r));
            var cells = grid.Cells.around(c, k);
            while (cells.next()) |q| {
                if (!grid.Level.inside(q) or mathx.distEuclid(q, c) > r + 0.5) continue;
                lv.set(q, carve.paved(lv.at(q), surface));
            }
        }
    }
}

test "a road crosses the map whole and bridges a river" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x20AD);
    carve.fill(&lv, .shrub);
    carve.river(&lv, &rng, .{ .x = 40, .y = 0 }, .{ .x = 44, .y = grid.H - 1 }, 3, .water, null, null);
    apply(&lv, &rng, 0, carve.Palette.WILD, .{ .course = .across, .wander = 0 });
    var st: carve.Stretches = .{};
    const parts = st.label(&lv);
    std.debug.print("a straight road through a forest and over a river: {d} road, {d} bridge, {d} stretch of ground\n", .{ carve.count(&lv, .dirt), carve.count(&lv, .bridge), parts });
    try std.testing.expectEqual(@as(usize, 1), parts);
    try std.testing.expect(carve.count(&lv, .bridge) > 0);
}
