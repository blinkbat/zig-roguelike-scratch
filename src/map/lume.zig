const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const fov = @import("fov.zig");
const day = @import("day.zig");

const P = mathx.P;

/// Torch radius in cells, centred below its wall. Glow plants use their own cell.
pub const TORCH_REACH: i32 = 7;
pub const FIRE_REACH: i32 = 3;

pub fn torchFloor(wall: P) P {
    return wall.add(mathx.Dir.s.delta());
}

pub fn torchWall(floor: P) P {
    return floor.add(mathx.Dir.n.delta());
}

pub fn torchOver(floor: grid.Box, x: i32) P {
    return torchWall(.{ .x = x, .y = floor.lo.y });
}

pub fn torchPool(lv: *const grid.Level, from: P, out: *[grid.CELLS]bool) void {
    fov.castInto(lv, from, TORCH_REACH, out);
}

pub const Source = struct { at: P, reach: i32 };

/// In cells: the whole `sight` by day, none at night or under a roof.
pub fn skyReach(outdoors: bool, hour: f32, sight: i32) f32 {
    if (!outdoors) return 0;
    return day.daylight(hour) * @as(f32, @floatFromInt(sight));
}

fn pools(lv: *const grid.Level, viewer: P, sight: i32, carried: []const Source, out: *[grid.CELLS]bool) void {
    @memset(out, false);
    for (lv.torches()) |t| poolNear(lv, viewer, sight, .{ .at = torchFloor(t), .reach = TORCH_REACH }, out);
    var glows = lv.glowing();
    while (glows.next()) |p| poolNear(lv, viewer, sight, .{ .at = p, .reach = TORCH_REACH }, out);
    var flames = grid.Box.around(viewer, sight + FIRE_REACH).grown(0).cells();
    while (flames.next()) |at| if (lv.burning(at)) fov.castInto(lv, at, FIRE_REACH, out);
    for (carried) |s| fov.castInto(lv, s.at, s.reach, out);
}

fn poolNear(lv: *const grid.Level, viewer: P, sight: i32, s: Source, out: *[grid.CELLS]bool) void {
    if (mathx.dist(s.at, viewer) <= sight + s.reach) fov.castInto(lv, s.at, s.reach, out);
}

pub fn pooled(lv: *const grid.Level, viewer: P, sight: i32, carried: []const Source, p: P) bool {
    var lit_by: [grid.CELLS]bool = undefined;
    pools(lv, viewer, sight, carried, &lit_by);
    return grid.cellOr(bool, &lit_by, p, false);
}

pub fn see(lv: *grid.Level, viewer: P, sight: i32, sky: f32, carried: []const Source) void {
    lv.lightless();
    @memset(&lv.los, false);
    fov.castInto(lv, viewer, sight, &lv.los);
    var lit_by: [grid.CELLS]bool = undefined;
    const need_pools = sky < @as(f32, @floatFromInt(sight));
    if (need_pools) pools(lv, viewer, sight, carried, &lit_by);
    var cells = grid.Box.around(viewer, @max(0, sight)).grown(0).cells();
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        if (!lv.los[i] or !(mathx.reaches(viewer, p, sky) or (need_pools and lit_by[i]))) continue;
        lv.light(p);
        lv.barrel_seen[i] = lv.barrel[i];
    }
}

fn count(cells: *const [grid.CELLS]bool) usize {
    return std.mem.count(bool, cells, &.{true});
}

test "the dark shows only what a light reaches, the day all the eyes do, and dusk between" {
    var lv = grid.openFloor();
    const at = P{ .x = 40, .y = 30 };
    const sight: i32 = 10;
    const lamp = [_]Source{.{ .at = at, .reach = 5 }};
    see(&lv, at, sight, skyReach(false, day.NOON, sight), &lamp);
    const dark = count(&lv.lit);
    const reached = count(&lv.los);
    see(&lv, at, sight, skyReach(true, day.NOON, sight), &lamp);
    const noon = count(&lv.lit);
    see(&lv, at, sight, skyReach(true, day.SUNSET - 0.5, sight), &lamp);
    const dusk = count(&lv.lit);
    see(&lv, at, sight, skyReach(true, 0, sight), &lamp);
    const midnight = count(&lv.lit);
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

test "flames light their own pool in the dark until they go out, and a burnt reed bed stops hiding what lies past it" {
    var lv = grid.openFloor();
    const at = P{ .x = 40, .y = 30 };
    const lamp = [_]Source{.{ .at = at, .reach = 2 }};
    const blaze = P{ .x = 46, .y = 30 };
    const beside = P{ .x = 46, .y = 33 };
    const reed = P{ .x = 44, .y = 30 };
    see(&lv, at, 10, 0, &lamp);
    try std.testing.expect(!lv.isLit(blaze) and !lv.isLit(beside));
    lv.flames[grid.Level.idx(blaze)] = 1;
    see(&lv, at, 10, 0, &lamp);
    try std.testing.expect(lv.isLit(blaze) and lv.isLit(beside));
    try std.testing.expect(!lv.isLit(.{ .x = 46, .y = 30 + FIRE_REACH + 1 }));
    lv.set(reed, .reeds);
    see(&lv, at, 10, 0, &lamp);
    try std.testing.expect(!lv.inLos(blaze));
    lv.set(reed, .dirt);
    lv.flames[grid.Level.idx(blaze)] = 0;
    see(&lv, at, 10, 0, &lamp);
    try std.testing.expect(lv.inLos(blaze) and !lv.isLit(blaze));
}

test "a glowing plant lights its own pool at night, out to the hero's sight and no farther" {
    var lv = grid.openFloor();
    const at = P{ .x = 40, .y = 30 };
    const lamp = [_]Source{.{ .at = at, .reach = 5 }};
    const plant = P{ .x = 49, .y = 30 };
    const behind = P{ .x = 47, .y = 30 };
    const past = P{ .x = 53, .y = 30 };
    see(&lv, at, 10, 0, &lamp);
    try std.testing.expect(!lv.isLit(behind));
    lv.set(plant, .glow_plant);
    see(&lv, at, 10, 0, &lamp);
    try std.testing.expect(lv.isLit(plant) and lv.isLit(behind));
    try std.testing.expect(!lv.isLit(past) and lv.inLos(.{ .x = 50, .y = 30 }));
}
