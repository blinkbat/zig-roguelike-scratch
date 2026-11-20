const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const carve = @import("../../map/carve.zig");
const day = @import("../../map/day.zig");
const game = @import("../../game.zig");
const glide = @import("../glide.zig");

const P = mathx.P;
const SHOTS_DIR = @import("capture.zig").SHOTS_DIR;
const capture = @import("capture.zig").capture;
const captured = @import("capture.zig").captured;
const renderTarget = @import("capture.zig").renderTarget;
const toggled = @import("capture.zig").toggled;
const NIGHT = @import("poses.zig").NIGHT;
const poseWaterMirrors = @import("poses.zig").poseWaterMirrors;
const studyLit = @import("poses.zig").studyLit;

pub fn captureTrees(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(TREES_DIR);
    game.harness.grassArena(g, .{ .x = 24, .y = 18 }, &.{});
    const tree = P{ .x = 24, .y = 19 };
    g.sim.lv.set(tree, .large_tree);
    g.sim.lv.set(.{ .x = 27, .y = 19 }, .large_tree);
    g.sim.lv.set(.{ .x = 22, .y = 24 }, .large_tree);
    game.harness.wallRow(&g.sim.lv, 18, 26, 30);
    studyLit(g, true, day.NOON);
    g.st = .{};
    try capture(g, target, TREES_DIR ++ "/behind-opaque.png");
    game.update(g, FADING_S);
    const partial = g.pic.occlusion[grid.Level.idx(tree)];
    if (partial <= 0 or partial >= 1) return error.TreeFadeNotSmooth;
    try capture(g, target, TREES_DIR ++ "/behind-fading.png");
    fadeOut(g);
    if (g.pic.occlusion[grid.Level.idx(tree)] < FADED) return error.TreeDidNotFade;
    try capture(g, target, TREES_DIR ++ "/behind-clear.png");
    const hero = g.sim.heroSlot().?;
    const still = g.pic.glide[hero];
    g.pic.glide[hero] = still.toward(.{ .x = 25, .y = 18 }, game.GLIDE_S / 2);
    try capture(g, target, TREES_DIR ++ "/behind-midstep.png");
    g.pic.glide[hero] = still;
    veil(&g.sim.lv, grid.Cells.of(.{ .x = 23, .y = 17 }, .{ .x = 26, .y = 21 }));
    g.cloud.settle(&g.sim.lv);
    try capture(g, target, TREES_DIR ++ "/behind-gas.png");
    @memset(&g.sim.lv.gas, 0);
    g.cloud.settle(&g.sim.lv);
    standInFront(g);
    game.update(g, FADING_S);
    const restoring = g.pic.occlusion[grid.Level.idx(tree)];
    if (restoring <= 0 or restoring >= FADED) return error.TreeRestoreNotSmooth;
    try capture(g, target, TREES_DIR ++ "/front-restoring.png");
    fadeOut(g);
    if (g.pic.occlusion[grid.Level.idx(tree)] > UNFADED) return error.TreeDidNotRestore;
    try capture(g, target, TREES_DIR ++ "/front-opaque.png");
    veil(&g.sim.lv, grid.Cells.of(.{ .x = 21, .y = 17 }, .{ .x = 29, .y = 25 }));
    studyLit(g, false, NIGHT);
    try capture(g, target, TREES_DIR ++ "/night-gas.png");
    g.cam.y = @as(f32, @floatFromInt(24 * game.CELL - g.screen.y + game.HALF_CELL));
    try capture(g, target, TREES_DIR ++ "/bough-at-screen-bottom.png");
    @memset(&g.sim.lv.gas, 0);
    studyLit(g, true, day.NOON);
    game.prepare(g);
    {
        const tex = g.sprites.tiles.get(.large_tree) orelse return error.TreeTextureMissing;
        g.sprites.tiles.set(.large_tree, null);
        defer g.sprites.tiles.set(.large_tree, tex);
        try capture(g, target, TREES_DIR ++ "/glyph-fallback.png");
    }
    poseWaterMirrors(g, day.NOON, true);
    g.sim.lv.set(.{ .x = 27, .y = 17 }, .large_tree);
    studyLit(g, true, day.NOON);
    try capture(g, target, TREES_DIR ++ "/water-reflection.png");
    game.harness.grassArena(g, .{ .x = 24, .y = 18 }, &.{});
    const grass = P{ .x = 24, .y = 18 };
    carve.box(&g.sim.lv, .{ .lo = .{ .x = 23, .y = 17 }, .hi = .{ .x = 26, .y = 20 } }, .reeds);
    studyLit(g, true, day.NOON);
    g.st = .{};
    try capture(g, target, TREES_DIR ++ "/grass-opaque.png");
    game.update(g, FADING_S);
    const grass_partial = g.pic.occlusion[grid.Level.idx(grass)];
    if (grass_partial <= 0 or grass_partial >= 1) return error.GrassFadeNotSmooth;
    try capture(g, target, TREES_DIR ++ "/grass-fading.png");
    fadeOut(g);
    if (g.pic.occlusion[grid.Level.idx(grass)] < FADED) return error.GrassDidNotFade;
    const faded_grass = try captured(g, target, TREES_DIR ++ "/grass-clear.png");
    defer rl.unloadImage(faded_grass);
    const shown = try toggled(g, target, faded_grass, &g.pic.occlusion[grid.Level.idx(grass)], 0, null);
    if (shown.changed == 0) return error.GrassOcclusionDidNotChangeFrame;
    if (!shown.restored) return error.GrassOcclusionDidNotRestoreFrame;
    std.debug.print("reed occlusion GPU check: {d} pixels changed, exact restoration\n", .{shown.changed});
    g.sim.lv.gas[grid.Level.idx(grass)] = VEIL_GAS;
    g.cloud.settle(&g.sim.lv);
    try capture(g, target, TREES_DIR ++ "/grass-gas.png");
    standInFront(g);
    fadeOut(g);
    if (g.pic.occlusion[grid.Level.idx(grass)] > UNFADED) return error.GrassDidNotRestore;
    try capture(g, target, TREES_DIR ++ "/grass-front.png");
    std.debug.print("tall tree captures: native height, wall adjacency, smooth hiding/restoration and front/behind depth checked\n", .{});
    std.debug.print("reed patch captures: body depth, smooth hiding/restoration and shared gas fade checked\n", .{});
}

const FADING_S = game.harness.FADING_S;
const FADED = game.harness.FADED;
const UNFADED = game.harness.UNFADED;
const TREES_DIR = SHOTS_DIR ++ "/trees";
const VEIL_GAS = @import("capture.zig").VEIL_GAS;
const veil = @import("capture.zig").veil;

fn fadeOut(g: *game.Game) void {
    game.harness.fadeFrames(g, game.update);
}

const FRONT = P{ .x = 24, .y = 20 };

fn standInFront(g: *game.Game) void {
    g.sim.pool.move(&g.sim.lv, g.sim.hero, FRONT);
    g.pic.glide[g.sim.heroSlot().?] = glide.Glide.rest(g.sim.heroActor().?);
}
