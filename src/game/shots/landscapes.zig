const std = @import("std");
const rl = @import("raylib");
const atlas = @import("../../map/atlas.zig");
const grid = @import("../../map/grid.zig");
const day = @import("../../map/day.zig");
const game = @import("../../game.zig");
const capture = @import("capture.zig");

pub fn captureLandscapes(g: *game.Game) !void {
    try std.fs.cwd().makePath(capture.SHOTS_DIR ++ "/landscapes");
    const w = try capture.heapAtlas();
    defer capture.dropAtlas(g, w);
    try w.load(std.heap.c_allocator, atlas.START);
    const shot = try capture.targetAt(g, .{ .x = 1536, .y = 1024 });
    defer shot.close(g);
    for ([_]usize{ atlas.CARAVAN_NODE, 2 }) |node| {
        game.beginMapAt(g, w, .{ .node = node, .at = w.node[node].door[0].at }, capture.SHOT_SEED);
        @import("poses.zig").studyLit(g, true, day.NOON);
        game.prepare(g);
        const name = if (node == atlas.CARAVAN_NODE) "caravan" else "goblin-camp";
        for (0..4) |y| {
            for (0..4) |x| {
                g.cam = .{ .x = @floatFromInt(x * 1536), .y = @floatFromInt(y * 1024) };
                capture.intoTarget(g, shot.target);
                rl.clearBackground(rl.Color.black);
                game.scene.drawMap(g);
                capture.outOfTarget(g);
                var path: [160]u8 = undefined;
                try capture.exportTarget(shot.target, try std.fmt.bufPrintZ(&path, capture.SHOTS_DIR ++ "/landscapes/{s}-{d}-{d}.png", .{ name, x, y }));
            }
        }
        for ([_]grid.Tile{ .caravan, .chest, .glow_plant }) |tile| {
            const i = std.mem.indexOfScalar(grid.Tile, &g.sim.lv.tile, tile) orelse continue;
            const at = grid.Level.of(i);
            g.cam = .{
                .x = @floatFromInt(std.math.clamp(at.x * game.CELL - 768, 0, grid.W * game.CELL - 1536)),
                .y = @floatFromInt(std.math.clamp(at.y * game.CELL - 512, 0, grid.H * game.CELL - 1024)),
            };
            try capture.capturef(g, shot.target, capture.SHOTS_DIR ++ "/landscapes/{s}-{s}.png", .{ name, @tagName(tile) });
        }
    }
}
