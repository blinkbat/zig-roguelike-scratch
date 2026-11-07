const std = @import("std");
const atlas = @import("atlas.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const mathx = @import("../core/mathx.zig");
const hero = @import("../play/hero.zig");

const P = mathx.P;
const Tile = grid.Tile;

pub const CLASS: hero.Class = .wizard;

/// One terrain to try things on, apart from its neighbours.
pub const Patch = union(enum) {
    tile: Tile,
    barrels,
    /// Shallows round deep water, for the bank between them.
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
/// Floor between columns of patches; one row of it runs above and below each.
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
    for (PATCHES, 0..) |p, i| {
        if (std.meta.eql(p, patch)) return i;
    }
    unreachable;
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
        for (0..COLS) |c| {
            const x = boxOf(c).lo.x;
            for (0..SIZE.x) |dx| room.tile[grid.Level.idx(.{ .x = x + @as(i32, @intCast(dx)), .y = y })] = .wall;
        }
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
            fill(room, box, grid.BARREL_GROUND);
            var cells = box.cells();
            while (cells.next()) |p| room.barrel[grid.Level.idx(p)] = checker(box, p);
        },
        .pond => {
            fill(room, box, .shallows);
            fill(room, .{ .lo = box.lo.add(.{ .x = 1, .y = 1 }), .hi = box.hi.sub(.{ .x = 1, .y = 1 }) }, .water);
        },
        .tile => |t| if (t.spans()) {
            fill(room, box, .water);
            fill(room, grid.Box.sized(.{ .x = box.lo.x, .y = box.lo.y + 1 }, box.width(), 1), t);
        } else if (!t.upright() or t.shaped()) {
            fill(room, box, t);
        } else if (t.wide() > 1) {
            fill(room, box, t.bare());
            var x = box.lo.x;
            while (x + t.wide() <= box.hi.x) : (x += t.wide() + 1) prop(room, .{ .x = x, .y = box.lo.y + 1 }, t);
        } else {
            fill(room, box, t.bare());
            var cells = box.cells();
            while (cells.next()) |p| if (checker(box, p)) prop(room, p, t);
        },
    }
}

fn checker(box: grid.Box, p: P) bool {
    return @mod(p.x - box.lo.x + p.y - box.lo.y, 2) == 0;
}

fn fill(room: *atlas.Bespoke, box: grid.Box, t: Tile) void {
    var cells = box.cells();
    while (cells.next()) |p| room.tile[grid.Level.idx(p)] = t;
}

fn prop(room: *atlas.Bespoke, p: P, t: Tile) void {
    const i = grid.Level.idx(p);
    room.tile[i] = t;
    for (1..@intCast(t.wide())) |k| room.tile[i + k] = t.partOf().?;
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
    var flood = grid.Flood.init(lv, HERO, dist, queue);
    while (flood.next()) |_| {}
    var unreached: usize = 0;
    for (0..PATCHES.len) |i| {
        const b = boxOf(i);
        var cells = (grid.Box{ .lo = b.lo.sub(.{ .x = 1, .y = 1 }), .hi = b.hi.add(.{ .x = 1, .y = 1 }) }).cells();
        var touched = false;
        while (cells.next()) |p| touched = touched or dist[grid.Level.idx(p)] >= 0;
        if (!touched) unreached += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), unreached);
    std.debug.print("playground: {d} patches in {d}x{d}, {d} kinds of tile, {d} barrels, {d} torches, every patch beside a reached lane\n", .{ PATCHES.len, ROOM.width(), ROOM.height(), present.count(), barrels, room.torch.n });
}
