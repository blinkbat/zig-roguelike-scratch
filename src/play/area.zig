const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");

const P = mathx.P;

pub const BURST_MAX: i32 = 3;
pub const Burst = grid.Bounded(P, grid.Cells.square(BURST_MAX));

fn castR(range: i32) i32 {
    return mathx.roundTiesDown(@as(f32, @floatFromInt(range)) * std.math.sqrt2);
}

comptime {
    for (1..BURST_MAX + 1) |r| std.debug.assert(mathx.reaches(.{ .x = 0, .y = 0 }, .{ .x = r, .y = r }, castR(r)));
}

pub fn spread(lv: *const grid.Level, at: P, range: i32, ctx: anytype, comptime keep: fn (@TypeOf(ctx), P) bool) Burst {
    return reached(lv, at, range, grid.Level.walkable, ctx, keep);
}

pub fn wetIn(lv: *const grid.Level, at: P, range: i32) Burst {
    return reached(lv, at, range, grid.Level.wetAt, {}, every);
}

fn reached(lv: *const grid.Level, at: P, wanted: i32, comptime ground: fn (*const grid.Level, P) bool, ctx: anytype, comptime keep: fn (@TypeOf(ctx), P) bool) Burst {
    const range = @min(wanted, BURST_MAX);
    var out = Burst{};
    var visible: [grid.CELLS]bool = @splat(false);
    fov.castInto(lv, at, castR(range), &visible);
    var cells = grid.Cells.around(at, range);
    while (cells.next()) |p| {
        if (!ground(lv, p)) continue;
        const k = grid.Level.idx(p);
        if (visible[k] and keep(ctx, p)) out.push(p);
    }
    return out;
}

pub fn patch(lv: *const grid.Level, at: P, range: i32) Burst {
    return spread(lv, at, range, {}, every);
}

pub fn Patch(comptime range: i32) type {
    comptime std.debug.assert(range <= BURST_MAX);
    return struct {
        pub fn area(lv: *const grid.Level, at: P, wider: i32) Burst {
            return patch(lv, at, range + wider);
        }

        pub fn burst(lv: *const grid.Level, _: P, impact: P, wider: i32) Burst {
            return patch(lv, impact, range + wider);
        }
    };
}

pub fn every(_: void, _: P) bool {
    return true;
}

test "a burst's wet cells take the deep water round it as well as the shallows a patch takes, and none past a wall" {
    var lv = grid.openFloor();
    const at = P{ .x = 20, .y = 20 };
    const deep = P{ .x = 19, .y = 20 };
    const shallow = P{ .x = 20, .y = 21 };
    const walled = P{ .x = 22, .y = 20 };
    lv.set(deep, .water);
    lv.set(shallow, .shallows);
    lv.set(walled, .water);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    const near = wetIn(&lv, at, 1);
    try std.testing.expectEqual(@as(usize, 2), near.n);
    try std.testing.expect(near.has(deep) and near.has(shallow));
    const area = patch(&lv, at, 1);
    try std.testing.expect(!area.has(deep) and area.has(shallow));
    try std.testing.expect(!wetIn(&lv, at, 2).has(walled));
}

test "a wider patch grows by its bonus and stops at the largest burst" {
    var lv = grid.openFloor();
    const at = P{ .x = 20, .y = 20 };
    const One = Patch(1);
    try std.testing.expectEqual(@as(usize, @intCast(grid.Cells.square(1))), One.area(&lv, at, 0).n);
    try std.testing.expectEqual(@as(usize, @intCast(grid.Cells.square(2))), One.area(&lv, at, 1).n);
    try std.testing.expectEqual(@as(usize, @intCast(grid.Cells.square(BURST_MAX))), One.burst(&lv, at, at, 9).n);
}
