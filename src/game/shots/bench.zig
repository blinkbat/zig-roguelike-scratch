const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const atlas = @import("../../map/atlas.zig");
const look = @import("../../gfx/look.zig");
const fx = @import("../../gfx/fx.zig");
const day = @import("../../map/day.zig");
const game = @import("../../game.zig");
const SHOT_BIOME = @import("capture.zig").SHOT_BIOME;
const SHOT_OUTDOOR = @import("capture.zig").SHOT_OUTDOOR;
const SHOT_SEED = @import("capture.zig").SHOT_SEED;
const drawInto = @import("capture.zig").drawInto;
const dropAtlas = @import("capture.zig").dropAtlas;
const heapAtlas = @import("capture.zig").heapAtlas;
const renderTarget = @import("capture.zig").renderTarget;
const loadStrand = @import("poses.zig").loadStrand;
const poseGas = @import("poses.zig").poseGas;
const poseWaterMirrors = @import("poses.zig").poseWaterMirrors;
const studyLit = @import("poses.zig").studyLit;

/// Milliseconds a frame takes to draw, over `n` frames after `warm` unmeasured.
pub fn meanDraw(g: *game.Game, target: rl.RenderTexture2D, warm: usize, n: usize) !f64 {
    for (0..warm) |_| drawInto(g, target);
    var timer = try std.time.Timer.start();
    for (0..n) |_| drawInto(g, target);
    return ms(timer.read() / n);
}

const BENCH_FRAMES: usize = 3600;
const BENCH_DRAWS: usize = BENCH_FRAMES / 6;

pub fn ms(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}

pub fn benchWalk(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    var t = try std.time.Timer.start();
    game.begin(g, SHOT_SEED);
    game.prepare(g);
    std.debug.print("first map: {d:.3} ms, {d} map textures\n", .{ ms(t.read()), g.sprites.count() });
    var rng = mathx.Rng.init(SHOT_SEED);
    var d: mathx.Dir = .e;
    const dt = mathx.FRAME_DT;
    var sim = [_]u64{0} ** BENCH_FRAMES;
    var draw = [_]u64{0} ** BENCH_FRAMES;
    for (0..BENCH_FRAMES) |i| {
        if (g.mode == .dead) game.begin(g, SHOT_SEED +% i);
        const was = g.sim.heroActor().?.at;
        t.reset();
        game.harness.walkFrame(g, dt, d);
        sim[i] = t.lap();
        drawInto(g, target);
        draw[i] = t.read();
        const tried = g.st.walk != null and g.pending == null;
        if (tried and g.sim.heroActor() != null and g.sim.heroActor().?.at.eq(was)) d = rng.pick(mathx.Dir, mathx.ALL_DIRS);
    }
    for ([_][]u64{ &sim, &draw }, [_][]const u8{ "update", "draw" }) |xs, name| {
        std.mem.sort(u64, xs, {}, std.sort.asc(u64));
        var sum: u64 = 0;
        for (xs) |x| sum += x;
        std.debug.print("{s}: mean {d:.3} ms, p99 {d:.3} ms, max {d:.3} ms\n", .{ name, ms(sum / xs.len), ms(xs[xs.len * 99 / 100]), ms(xs[xs.len - 1]) });
    }
    try benchAssets(g);
    try benchEffects(g, target);
    poseWaterMirrors(g, day.NOON, true);
    std.debug.print("smooth water with mirrors and glints: {d:.3} ms mean draw over {d} frames\n", .{ try meanDraw(g, target, 1, BENCH_DRAWS), BENCH_DRAWS });
    try benchGrass(g, target);
    try benchStrand(g, target);
}

fn benchStrand(g: *game.Game, target: rl.RenderTexture2D) !void {
    const w = try heapAtlas();
    defer dropAtlas(g, w);
    try loadStrand(g, w);
    g.sim.clock = day.Clock.at(day.NOON);
    game.settle(g);
    game.prepare(g);
    std.debug.print("strand at noon: {d:.3} ms mean draw over {d} frames\n", .{ try meanDraw(g, target, 1, BENCH_DRAWS), BENCH_DRAWS });
}

fn benchGrass(g: *game.Game, target: rl.RenderTexture2D) !void {
    game.harness.grassArena(g, .{ .x = 24, .y = 20 }, &.{});
    studyLit(g, true, day.NOON);
    game.prepare(g);
    const alt = g.sprites.grass2 orelse return error.GrassAlternateMissing;
    defer g.sprites.grass2 = alt;
    const varied = try meanDraw(g, target, 1, BENCH_DRAWS);
    g.sprites.grass2 = null;
    const plain = try meanDraw(g, target, 1, BENCH_DRAWS);
    g.sprites.grass2 = alt;
    const repeated = try meanDraw(g, target, 1, BENCH_DRAWS);
    std.debug.print("flat grass: alternate {d:.3}/{d:.3} ms, plain {d:.3} ms mean draw over {d} frames\n", .{ varied, repeated, plain, BENCH_DRAWS });
    for (0..8) |i| g.sim.lv.set(.{ .x = 20 + @as(i32, @intCast(i)), .y = 21 }, .large_tree);
    studyLit(g, true, day.NOON);
    game.prepare(g);
    std.debug.print("flat grass with 8 tall trees: {d:.3} ms mean draw over {d} frames\n", .{ try meanDraw(g, target, 1, BENCH_DRAWS), BENCH_DRAWS });
}

fn benchEffects(g: *game.Game, target: rl.RenderTexture2D) !void {
    poseGas(g);
    for ([_]usize{ 0, 8, 32 }) |count| {
        g.pic.fx.clear();
        for (0..count) |i| {
            const at = mathx.centre(.{ .x = 15 + @as(i32, @intCast(i % 8)), .y = 14 + @as(i32, @intCast(i / 8)) });
            g.pic.fx.glow(at, look.FIRE, .{ .radius = fx.EMBER_GLOW.radius, .gain = fx.EMBER_GLOW.gain, .life = 1 });
        }
        std.debug.print("effects {d}: {d:.3} ms mean draw over {d} frames\n", .{ count, try meanDraw(g, target, 1, BENCH_DRAWS), BENCH_DRAWS });
    }
}

fn benchAssets(g: *game.Game) !void {
    const alloc = std.heap.c_allocator;
    const w = try heapAtlas();
    defer dropAtlas(g, w);
    inline for ([_][]const u8{ SHOT_OUTDOOR, SHOT_BIOME, SHOT_OUTDOOR }) |name| {
        try w.load(alloc, atlas.mapPath(name));
        game.beginMapAt(g, w, w.start, SHOT_SEED);
        var t = try std.time.Timer.start();
        game.prepare(g);
        const loaded = t.read();
        if (!std.meta.eql(game.mapAssets(g), g.sprites.resident())) return error.MissingMapAsset;
        const held = g.sprites;
        g.art = .stale;
        t.reset();
        game.prepare(g);
        const reused = t.read();
        if (!std.meta.eql(held, g.sprites)) return error.ReloadedMapAsset;
        std.debug.print("assets {s}: {d} textures, {d:.3} ms; unchanged map {d:.3} ms, all textures reused\n", .{ name, g.sprites.count(), ms(loaded), ms(reused) });
    }
}
