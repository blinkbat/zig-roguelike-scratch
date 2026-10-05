const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const fov = @import("fov.zig");
const day = @import("day.zig");

// Light that decides what is seen; `gfx/light.zig` only draws it.

const P = mathx.P;

/// Cells a torch's flame lights, from the floor below it.
pub const TORCH_REACH: i32 = 7;

pub fn torchFloor(wall: P) P {
    return wall.add(mathx.Dir.s.delta());
}

pub fn torchWall(floor: P) P {
    return floor.add(mathx.Dir.n.delta());
}

/// The cells the torch on `wall` lights, added to `out`.
pub fn torchPool(lv: *const grid.Level, wall: P, out: *[grid.CELLS]bool) void {
    fov.castInto(lv, torchFloor(wall), TORCH_REACH, out);
}

pub const Source = struct { at: P, reach: i32 };

/// In cells: the whole `sight` by day, none at night or under a roof.
pub fn skyReach(outdoors: bool, hour: f32, sight: i32) f32 {
    if (!outdoors) return 0;
    return day.daylight(hour) * @as(f32, @floatFromInt(sight));
}

/// Only as far as `sight` of `viewer` reaches: nothing past it is read.
fn pools(lv: *const grid.Level, viewer: P, sight: i32, carried: []const Source, out: *[grid.CELLS]bool) void {
    @memset(out, false);
    for (lv.torches()) |t| {
        if (mathx.dist(torchFloor(t), viewer) <= sight + TORCH_REACH) torchPool(lv, t, out);
    }
    for (carried) |s| fov.castInto(lv, s.at, s.reach, out);
}

/// Takes `lv.lit` as `fov.cast` left it and keeps it as `los`.
pub fn dim(lv: *grid.Level, viewer: P, sky: f32, lit_by: *const [grid.CELLS]bool, was_seen: *const [grid.CELLS]bool) void {
    lv.los = lv.lit;
    for (0..grid.CELLS) |i| {
        if (!lv.lit[i]) continue;
        const near = mathx.reaches(viewer, grid.Level.of(i), sky);
        lv.lit[i] = near or lit_by[i];
        lv.seen[i] = was_seen[i] or lv.lit[i];
    }
}

pub fn see(lv: *grid.Level, viewer: P, sight: i32, sky: f32, carried: []const Source) void {
    const was = lv.seen;
    fov.cast(lv, viewer, sight);
    var lit_by: [grid.CELLS]bool = undefined;
    pools(lv, viewer, sight, carried, &lit_by);
    dim(lv, viewer, sky, &lit_by, &was);
}

fn count(cells: *const [grid.CELLS]bool) usize {
    return std.mem.count(bool, cells, &.{true});
}

test "the dark shows only what a light reaches, the day all the eyes do, and dusk between" {
    var lv = grid.openFloor();
    const at = P{ .x = 40, .y = 30 };
    const sight: i32 = 10;
    const lamp = [_]Source{.{ .at = at, .reach = 5 }};
    see(&lv, at, sight, skyReach(false, 12, sight), &lamp);
    const dark = count(&lv.lit);
    const reached = count(&lv.los);
    see(&lv, at, sight, skyReach(true, 12, sight), &lamp);
    const noon = count(&lv.lit);
    see(&lv, at, sight, skyReach(true, day.SUNSET - 0.5, sight), &lamp);
    const dusk = count(&lv.lit);
    see(&lv, at, sight, skyReach(true, 0, sight), &lamp);
    const midnight = count(&lv.lit);
    std.debug.print("cells seen of {d} in line of sight: {d} underground, {d} at noon, {d} half an hour before sunset, {d} at midnight\n", .{ reached, dark, noon, dusk, midnight });
    try std.testing.expectEqual(reached, noon);
    try std.testing.expectEqual(dark, midnight);
    try std.testing.expect(dark < dusk and dusk < noon);
    try std.testing.expect(!lv.isLit(.{ .x = at.x + 8, .y = at.y }) and lv.inLos(.{ .x = at.x + 8, .y = at.y }));
}

test "a torch's pool is seen across the dark, and a cell once seen is remembered after the light goes" {
    var lv = grid.openFloor();
    const at = P{ .x = 40, .y = 30 };
    const torch = P{ .x = 48, .y = 25 };
    lv.set(torch, .wall);
    lv.addTorch(torch);
    const lamp = [_]Source{.{ .at = at, .reach = 3 }};
    see(&lv, at, 10, 0, &lamp);
    const under = torchFloor(torch);
    try std.testing.expect(lv.isLit(under));
    try std.testing.expect(!lv.isLit(.{ .x = at.x - 8, .y = at.y }));
    const away = P{ .x = 30, .y = 30 };
    lv.torch.n = 0;
    see(&lv, away, 10, 0, &lamp);
    try std.testing.expect(!lv.isLit(under) and lv.isSeen(under));
    try std.testing.expect(!lv.isSeen(.{ .x = at.x - 8, .y = at.y + 9 }));
}
