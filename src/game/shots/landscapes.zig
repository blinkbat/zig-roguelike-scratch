const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const atlas = @import("../../map/atlas.zig");
const grid = @import("../../map/grid.zig");
const day = @import("../../map/day.zig");
const game = @import("../../game.zig");
const capture = @import("capture.zig");
const studyLit = @import("poses.zig").studyLit;

const TILE = mathx.P{ .x = 1536, .y = 1024 };
const ACROSS: usize = @intCast(@divExact(game.MAP_PX.x, TILE.x));
const DOWN: usize = @intCast(@divExact(game.MAP_PX.y, TILE.y));
const PLACES = [_]struct { node: usize, name: []const u8 }{
    .{ .node = atlas.CARAVAN_NODE, .name = "caravan" },
    .{ .node = atlas.GOBLIN_CAMP_NODE, .name = "goblin-camp" },
};

pub fn captureLandscapes(g: *game.Game) !void {
    try std.fs.cwd().makePath(capture.SHOTS_DIR ++ "/landscapes");
    const w = try capture.heapAtlas();
    defer capture.dropAtlas(g, w);
    try w.load(std.heap.c_allocator, atlas.START);
    const shot = try capture.targetAt(g, TILE);
    defer shot.close(g);
    for (PLACES) |place| {
        const node = place.node;
        const name = place.name;
        game.beginMapAt(g, w, .{ .node = node, .at = w.node[node].door[0].at }, capture.SHOT_SEED);
        studyLit(g, true, day.NOON);
        game.prepare(g);
        for (0..DOWN) |y| {
            for (0..ACROSS) |x| {
                g.cam = .{ .x = @floatFromInt(x * TILE.x), .y = @floatFromInt(y * TILE.y) };
                capture.drawMapInto(g, shot.target, rl.Color.black);
                var path: [capture.PATH_MAX]u8 = undefined;
                try capture.exportTarget(shot.target, try std.fmt.bufPrintZ(&path, capture.SHOTS_DIR ++ "/landscapes/{s}-{d}-{d}.png", .{ name, x, y }));
            }
        }
        for ([_]grid.Tile{ .caravan, .chest, .glow_plant }) |tile| {
            const i = std.mem.indexOfScalar(grid.Tile, &g.sim.lv.tile, tile) orelse continue;
            const at = grid.Level.of(i);
            g.cam = .{
                .x = @floatFromInt(std.math.clamp(at.x * game.CELL - @divTrunc(TILE.x, 2), 0, game.MAP_PX.x - TILE.x)),
                .y = @floatFromInt(std.math.clamp(at.y * game.CELL - @divTrunc(TILE.y, 2), 0, game.MAP_PX.y - TILE.y)),
            };
            try capture.capturef(g, shot.target, capture.SHOTS_DIR ++ "/landscapes/{s}-{s}.png", .{ name, @tagName(tile) });
        }
    }
}
