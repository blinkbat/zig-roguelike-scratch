const std = @import("std");
const atlas = @import("atlas.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const mathx = @import("../core/mathx.zig");
const hero = @import("../play/hero.zig");

const P = mathx.P;
const Tile = grid.Tile;

pub const CLASS: hero.Class = .wizard;

pub const Patch = union(enum) {
    tile: Tile,
    barrels,
    pond,
};

fn patched(t: Tile) bool {
    return t != .floor and t != .wall and !t.isOpened() and !t.isPart();
}

pub const PATCHES = blk: {
    var out: []const Patch = &.{};
    for (std.enums.values(Tile)) |t| {
        if (patched(t)) out = out ++ [_]Patch{.{ .tile = t }};
    }
    break :blk out ++ [_]Patch{ .barrels, .pond };
};

const SIZE = P{ .x = 5, .y = 3 };
const LANE: i32 = 2;
const COLS: usize = 6;
const ROWS: usize = std.math.divCeil(usize, PATCHES.len, COLS) catch unreachable;
/// Lane, patch and lane, then the wall dividing it from the next band, whose torches light it.
const BAND: i32 = 1 + SIZE.y + 1 + 1;
const STEP: i32 = SIZE.x + LANE;
const ROOM = grid.Box.centred(@as(i32, COLS) * STEP + LANE, @as(i32, ROWS) * BAND - 1);
pub const HERO = P{ .x = ROOM.lo.x + @as(i32, COLS / 2) * STEP, .y = ROOM.lo.y + @as(i32, ROWS / 2) * BAND };

comptime {
    std.debug.assert(ROWS * ((COLS + 1) / 2) <= grid.MAX_TORCHES);
    std.debug.assert(ROOM.lo.x > 0 and ROOM.lo.y > 0);
}

pub fn indexOf(patch: Patch) usize {
    return mathx.indexOfEql(Patch, PATCHES, patch).?;
}

pub fn boxOf(i: usize) grid.Box {
    const c: i32 = @intCast(i % COLS);
    const r: i32 = @intCast(i / COLS);
    return grid.Box.sized(.{ .x = ROOM.lo.x + LANE + c * STEP, .y = ROOM.lo.y + r * BAND + 1 }, SIZE.x, SIZE.y);
}

pub fn author(map: *atlas.Atlas) void {
    const node = map.oneRoom(ROOM, HERO);
    _ = map.node[node].rename("Playground");
    const room = &map.node[node].plan.bespoke;
    for (1..ROWS) |r| {
        const y = ROOM.lo.y + @as(i32, @intCast(r)) * BAND - 1;
        for (0..COLS) |c| room.fill(grid.Box.sized(.{ .x = boxOf(c).lo.x, .y = y }, SIZE.x, 1), .wall);
    }
    for (PATCHES, 0..) |patch, i| lay(room, boxOf(i), patch);
    for (0..ROWS) |r| {
        var c: usize = 0;
        while (c < COLS) : (c += 2) {
            const b = boxOf(r * COLS + c);
            std.debug.assert(room.torch.add(lume.torchWall(.{ .x = b.hi.x - 1, .y = b.lo.y - 1 })));
        }
    }
}

fn lay(room: *atlas.Bespoke, box: grid.Box, patch: Patch) void {
    switch (patch) {
        .barrels => {
            room.fill(box, grid.BARREL_GROUND);
            var cells = box.cells();
            while (cells.next()) |p| room.barrel[grid.Level.idx(p)] = checker(box, p);
        },
        .pond => {
            room.fill(box, .shallows);
            room.fill(box.inner(), .water);
        },
        .tile => |t| if (t.spans()) {
            room.fill(box, .water);
            room.fill(grid.Box.sized(.{ .x = box.lo.x, .y = box.lo.y + 1 }, box.width(), 1), t);
        } else if (!t.upright() or t.shaped()) {
            room.fill(box, t);
        } else if (t.wide() > 1) {
            room.fill(box, t.bare());
            var x = box.lo.x;
            while (x + t.wide() <= box.hi.x) : (x += t.wide() + 1) grid.layProp(&room.tile, .{ .x = x, .y = box.lo.y + 1 }, t);
        } else {
            room.fill(box, t.bare());
            var cells = box.cells();
            while (cells.next()) |p| if (checker(box, p)) grid.layProp(&room.tile, p, t);
        },
    }
}

fn checker(box: grid.Box, p: P) bool {
    return @mod(p.x - box.lo.x + p.y - box.lo.y, 2) == 0;
}

test "the playground lays every placeable terrain, barrels and a bank, all reachable and torchlit" {
    const alloc = std.testing.allocator;
    const map = try alloc.create(atlas.Atlas);
    defer alloc.destroy(map);
    author(map);
    const room = &map.node[0].plan.bespoke;
    try std.testing.expectEqual(@as(usize, 1), map.node_n);
    try std.testing.expectEqual(@as(usize, 0), room.foe_n);
    try std.testing.expect(room.floorAt(HERO) and room.barrelAt(HERO) == false);
    var present = std.EnumSet(Tile).initEmpty();
    for (room.tile) |t| present.insert(t);
    for (std.enums.values(Tile)) |t| try std.testing.expect(present.contains(t) or t.isOpened());
    try std.testing.expect(grid.propsWhole(&room.tile));
    var barrels: usize = 0;
    for (room.barrel, 0..) |on, i| if (on) {
        try std.testing.expect(map.node[0].barrelFits(room, grid.Level.of(i)));
        barrels += 1;
    };
    try std.testing.expect(barrels > 0);
    const pond = boxOf(PATCHES.len - 1);
    try std.testing.expectEqual(Tile.water, room.tileAt(pond.centre()));
    try std.testing.expectEqual(Tile.shallows, room.tileAt(pond.centre().add(.{ .x = 0, .y = 1 })));
    for (room.torches()) |torch| try std.testing.expect(map.node[0].torchFits(room, torch));
    const lv = try alloc.create(grid.Level);
    defer alloc.destroy(lv);
    map.node[0].stamp(lv, 0);
    const dist = try alloc.create([grid.CELLS]i32);
    defer alloc.destroy(dist);
    const queue = try alloc.create([grid.CELLS]u32);
    defer alloc.destroy(queue);
    _ = grid.distances(lv, HERO, dist, queue);
    var unreached: usize = 0;
    for (0..PATCHES.len) |i| {
        const b = boxOf(i);
        var cells = b.grown(1).cells();
        var touched = false;
        while (cells.next()) |p| touched = touched or dist[grid.Level.idx(p)] >= 0;
        if (!touched) unreached += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), unreached);
}
