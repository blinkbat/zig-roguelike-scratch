const std = @import("std");
const rl = @import("raylib");
const atlas = @import("../../map/atlas.zig");
const light = @import("../../gfx/light.zig");
const game = @import("../../game.zig");
const SHOTS_DIR = @import("capture.zig").SHOTS_DIR;
const capture = @import("capture.zig").capture;
const differentPixels = @import("capture.zig").differentPixels;
const drawInto = @import("capture.zig").drawInto;
const readTarget = @import("capture.zig").readTarget;
const redrawnDiff = @import("capture.zig").redrawnDiff;
const target720 = @import("capture.zig").target720;
const MORNING = @import("poses.zig").MORNING;
const POSE_ZAP = @import("poses.zig").POSE_ZAP;
const loadStrand = @import("poses.zig").loadStrand;
const poseWaterMirrors = @import("poses.zig").poseWaterMirrors;
const captureLoot = @import("ui.zig").captureLoot;

pub fn captureDebug(g: *game.Game) !void {
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/debug");
    const screen = g.screen;
    defer g.screen = screen;
    const target = try target720(g);
    defer rl.unloadRenderTexture(target);
    poseWaterMirrors(g, MORNING, true);
    g.pic.fx.zap(0, POSE_ZAP);
    try capture(g, target, SHOTS_DIR ++ "/debug/all-on.png");
    inline for (std.meta.fields(light.Options)) |f| {
        try checkDebugOption(g, target, &@field(g.light.options, f.name), f.name);
    }
    try checkDebugOption(g, target, &g.debug.visuals.water_reflections, "water_reflections");
    const w = try std.heap.c_allocator.create(atlas.Atlas);
    defer std.heap.c_allocator.destroy(w);
    defer g.sim.map = null;
    try loadStrand(g, w);
    try checkDebugOption(g, target, &g.debug.visuals.weather, "weather");
    game.character.openPause(g);
    inline for (comptime std.enums.values(game.debugging.Page)) |page| {
        game.debugging.open(g, page);
        try capture(g, target, SHOTS_DIR ++ "/debug/menu-" ++ @tagName(page) ++ ".png");
    }
    try captureLoot(g);
}

fn checkDebugOption(g: *game.Game, target: rl.RenderTexture2D, option: *bool, comptime name: []const u8) !void {
    drawInto(g, target);
    const before = try readTarget(target);
    defer rl.unloadImage(before);
    const enabled = option.*;
    defer option.* = enabled;
    option.* = false;
    try capture(g, target, SHOTS_DIR ++ "/debug/off-" ++ name ++ ".png");
    const disabled = try readTarget(target);
    defer rl.unloadImage(disabled);
    const changed = differentPixels(before, disabled);
    if (changed == 0) return error.DebugOptionDidNotChangeFrame;
    option.* = true;
    if (try redrawnDiff(g, target, before) != 0) return error.DebugOptionDidNotRestoreFrame;
    std.debug.print("Debug {s}: {d} pixels changed, exact restoration\n", .{ name, changed });
}
