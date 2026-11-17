const std = @import("std");
const journal = @import("../../ui/journal.zig");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const hud = @import("../../ui/hud.zig");
const light = @import("../../gfx/light.zig");
const raster = @import("../../gfx/raster.zig");
const cinema = @import("../../gfx/cinema.zig");
const climate = @import("../../map/climate.zig");
const day = @import("../../map/day.zig");
const fire = @import("../../map/fire.zig");
const gas = @import("../../map/gas.zig");
const options_menu = @import("../../ui/options.zig");
const look = @import("../../gfx/look.zig");
const game = @import("../../game.zig");
const shots = @import("capture.zig");
const SHARP_BAND = @import("../../gfx/lens.zig").SHARP_BAND;

const P = mathx.P;
const CINEMA_DIR = shots.CINEMA_DIR;
const capture = shots.capture;
const capturef = shots.capturef;
const SIZES = game.SIZES;
const differentPixels = shots.differentPixels;
const neutralLens = shots.neutralLens;
const drawInto = shots.drawInto;
const dropAtlas = shots.dropAtlas;
const heapAtlas = shots.heapAtlas;
const readTarget = shots.readTarget;
const redrawnDiff = shots.redrawnDiff;
const renderTarget = shots.renderTarget;
const sameRgb = shots.sameRgb;
const targetAt = shots.targetAt;
const AIR_BACKDROP = rl.Color{ .r = 0, .g = 0, .b = 0, .a = 80 };
const MORNING = @import("poses.zig").MORNING;
const NIGHT = @import("poses.zig").NIGHT;
const POSE_ZAP = @import("poses.zig").POSE_ZAP;
const loadStrand = @import("poses.zig").loadStrand;
const poseForest = @import("poses.zig").poseForest;
const poseWaterMirrors = @import("poses.zig").poseWaterMirrors;
const studyAt = @import("poses.zig").studyAt;
const meanDraw = @import("bench.zig").meanDraw;

pub fn captureCinema(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    const w = try heapAtlas();
    defer dropAtlas(g, w);
    try loadStrand(g, w);
    try captureCinemaScene(g, target, "strand", .{ .bench = true });
    try captureStrandForest(g, target);
    poseForest(g);
    studyBeams(g, MORNING);
    try captureCinemaScene(g, target, "forest", .{ .bench = true, .bloomless = true });
    _ = game.harness.spawnAt(g, .beefy_pib, .{ .x = 20, .y = 18 }, false);
    _ = game.harness.spawnAt(g, .wizard, .{ .x = 29, .y = 18 }, false);
    studyBeams(g, MORNING);
    try captureCinemaScene(g, target, "forest-units", .{});
    for ([_]f32{ 7, 9, 10, 16, 17, 18 }) |hour| {
        studyBeams(g, hour);
        try capturef(g, target, CINEMA_DIR ++ "/forest-units-hour-{d:.0}.png", .{hour});
    }
    try captureBeamWater(g, target);
    try cinemaWater(g, target);
    try captureLens(g);
    try captureVisibility(g, target);
    game.character.openPause(g);
    game.debugging.select(g, .composed_lighting);
    try capture(g, target, CINEMA_DIR ++ "/debug.png");
}

fn studyBeams(g: *game.Game, hour: f32) void {
    studyAt(g, true, hour);
    g.pic.local_weather_shown = .initFill((climate.Climate{ .weather = .beams }).now(0, 0));
}

fn captureBeamWater(g: *game.Game, target: rl.RenderTexture2D) !void {
    poseForest(g);
    var cells = grid.Box.sized(.{ .x = 17, .y = 19 }, 18, 5).cells();
    while (cells.next()) |p| g.sim.lv.set(p, .water);
    for ([_]i32{ 18, 22, 26, 30, 34 }) |x| g.sim.lv.set(.{ .x = x, .y = 17 }, .large_tree);
    studyBeams(g, MORNING);
    try captureCinemaScene(g, target, "beam-water", .{ .bench = true });
    const before = g.debug.visuals.water_reflections;
    defer g.debug.visuals.water_reflections = before;
    g.debug.visuals.water_reflections = true;
    try capture(g, target, CINEMA_DIR ++ "/beam-water-defaults.png");
    g.light.t.step(1.5);
    try capture(g, target, CINEMA_DIR ++ "/beam-water-ripple-later.png");
    try checkBeamReflection(g, target);
}

fn checkBeamReflection(g: *game.Game, target: rl.RenderTexture2D) !void {
    const c = game.scene.Cam.of(g);
    var images: [2]rl.Image = undefined;
    var count: usize = 0;
    defer for (images[0..count]) |img| rl.unloadImage(img);
    for (&images, 0..) |*img, i| {
        img.* = try shots.airImage(g, target, AIR_BACKDROP, i == 1);
        count += 1;
    }
    var changed: usize = 0;
    var px = shots.pixels(g.screen.x, g.screen.y);
    while (px.next()) |q| {
        const a = rl.getImageColor(images[0], q.x, q.y);
        const b = rl.getImageColor(images[1], q.x, q.y);
        if (a.a != b.a) return error.BeamReflectionChangedAlpha;
        if (sameRgb(a, b)) continue;
        const p = c.cellAt(q);
        if (!grid.Level.inside(p) or !look.reflects(g.sim.lv.at(p))) return error.BeamReflectionOutsideWater;
        changed += 1;
    }
    if (changed < shots.MIN_PIXELS) return error.BeamReflectionMissing;
    std.debug.print("shaft reflection GPU: {d} water pixels; dry ground and alpha unchanged\n", .{changed});
}

fn captureStrandForest(g: *game.Game, target: rl.RenderTexture2D) !void {
    const from = g.sim.heroAt().?;
    var best: ?P = null;
    var distance: i32 = std.math.maxInt(i32);
    for (g.sim.locations, 0..) |place, i| {
        if (place != .forest) continue;
        const p = grid.Level.of(i);
        if (!g.sim.lv.walkable(p) or g.sim.lv.held(p)) continue;
        if (p.x < from.x + 22 or g.sim.lv.at(p) != .grass) continue;
        const d = mathx.dist(from, p);
        if (d >= distance) continue;
        best = p;
        distance = d;
    }
    const at = best orelse return error.StrandForestMissing;
    g.sim.pool.move(&g.sim.lv, g.sim.hero, at);
    g.sim.clock = day.Clock.at(MORNING);
    game.settle(g);
    try captureCinemaScene(g, target, "strand-forest", .{});
    try capture(g, target, CINEMA_DIR ++ "/strand-forest-defaults.png");
    g.light.t.step(2);
    try capture(g, target, CINEMA_DIR ++ "/strand-forest-motes-later.png");
}

fn captureVisibility(g: *game.Game, target: rl.RenderTexture2D) !void {
    try captureFireSight(g, target);
    const from = P{ .x = 20, .y = 20 };
    const foe = P{ .x = 24, .y = 20 };
    const reeds = P{ .x = 22, .y = 20 };
    game.harness.grassArena(g, from, &.{foe});
    g.sim.lv.set(reeds, .reeds);
    fire.lay(&g.sim.lv, reeds, fire.BURNS, 0);
    const bag = P{ .x = 23, .y = 22 };
    if (!g.sim.ground.add(.{ .item = .{ .kind = .cap }, .at = bag })) return error.CaptureLootFull;
    studyAt(g, true, day.NOON);
    if (!g.sim.lv.isLit(foe)) return error.BurningReedsBlockSight;
    try capture(g, target, CINEMA_DIR ++ "/visibility-flame-los.png");
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        const dx = p.x - from.x;
        const dy = p.y - from.y;
        g.sim.lv.seen[i] = dx * dx + dy * dy < 64;
        g.sim.lv.lit[i] = g.sim.lv.seen[i];
    }
    g.light.settle(&g.sim.lv);
    g.pic.snapSight(&g.sim);
    try capture(g, target, CINEMA_DIR ++ "/visibility-edge.png");
    for (&g.sim.lv.lit, 0..) |*lit, i| if (grid.Level.of(i).x > 21) {
        lit.* = false;
    };
    try captureEased(g, target, &.{ 0.05, 0.12, 0.25, 0.60 }, "out");
    for (&g.sim.lv.lit, g.sim.lv.seen) |*lit, seen| lit.* = seen;
    try captureEased(g, target, &.{ 0.05, 0.12, 0.25 }, "in");
    try captureGasBagFade(g, target);
}

fn captureGasBagFade(g: *game.Game, target: rl.RenderTexture2D) !void {
    const bag = P{ .x = 23, .y = 20 };
    game.harness.grassArena(g, .{ .x = 20, .y = 20 }, &.{});
    if (!g.sim.ground.add(.{ .item = .{ .kind = .cap }, .at = bag })) return error.CaptureLootFull;
    var cloud = grid.Cells.around(bag, 1);
    while (cloud.next()) |p| g.sim.lv.gas[grid.Level.idx(p)] = shots.VEIL_GAS;
    studyAt(g, true, day.NOON);
    game.prepare(g);
    if (g.sprites.item_bag == null or g.cloud.veil == null) return error.BagVeilMissing;
    const cell = &g.pic.seen_cells[grid.Level.idx(bag)];
    if (!cell.bag or cell.alpha != 1) return error.BagNotVisible;
    try capture(g, target, CINEMA_DIR ++ "/visibility-gas-bag.png");
    cell.alpha = 0.5;
    try capture(g, target, CINEMA_DIR ++ "/visibility-gas-bag-half.png");
    cell.alpha = 0;
    try capture(g, target, CINEMA_DIR ++ "/visibility-gas-bag-hidden.png");
    const hidden = try readTarget(target);
    defer rl.unloadImage(hidden);
    cell.alpha = 1.0 / 4096.0;
    if (try redrawnDiff(g, target, hidden) != 0) return error.GasVeilOutlivedBag;
    cell.alpha = 1;
    std.debug.print("gas-covered loot: subpixel fade matches hidden bag exactly\n", .{});
}

fn captureFireSight(g: *game.Game, target: rl.RenderTexture2D) !void {
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 21 };
    const past = P{ .x = 26, .y = 22 };
    game.harness.grassArena(g, from, &.{past});
    const bloat = game.harness.spawnAt(g, .pyre_bloat, at, false);
    studyAt(g, true, day.NOON);
    game.combat.wound(g, bloat, .{ .dmg = 100, .hit_checked = true }, game.combat.SHOOT, .{ .from = from, .wait = 0.3 });
    fire.lay(&g.sim.lv, at, fire.BURNS, 0);
    game.castSight(g, from);
    game.harness.drawnOut(g);
    if (!g.sim.lv.isLit(past) or !grid.clearLine(&g.sim.lv, from, past)) return error.FireBlocksSight;
    try capture(g, target, CINEMA_DIR ++ "/visibility-pyre-fire.png");
    var cloud = grid.Cells.around(at, 1);
    while (cloud.next()) |p| g.sim.lv.release(.smoke, p, gas.SMOKE_BURST);
    game.castSight(g, from);
    game.harness.drawnOut(g);
    if (!g.sim.lv.isLit(past)) return error.SmokeBlocksSight;
    try capture(g, target, CINEMA_DIR ++ "/visibility-smoke.png");
}

fn captureEased(g: *game.Game, target: rl.RenderTexture2D, times: []const f32, comptime way: []const u8) !void {
    var elapsed: f32 = 0;
    for (times) |t| {
        game.harness.ease(g, t - elapsed);
        g.light.step(&g.sim.lv, t - elapsed);
        elapsed = t;
        try capturef(g, target, CINEMA_DIR ++ "/visibility-" ++ way ++ "-{d:.0}ms.png", .{t * 1000});
    }
}

fn captureLens(g: *game.Game) !void {
    const lens = &g.cinema.lens;
    const before = lens.options;
    defer lens.options = before;
    if (lens.program == null) return error.LensShaderMissing;
    for (SIZES) |size| {
        const shot = try targetAt(g, size);
        defer shot.close(g);
        poseWaterMirrors(g, day.NOON, true);
        lens.options = .neutral;
        drawInto(g, shot.target);
        const base = try readTarget(shot.target);
        defer rl.unloadImage(base);
        try capturef(g, shot.target, CINEMA_DIR ++ "/lens-{d}-off.png", .{size.y});
        inline for (std.meta.fields(@TypeOf(lens.options))) |field| {
            lens.options = .neutral;
            @field(lens.options, field.name) = if (comptime std.mem.eql(u8, field.name, "saturation")) 0 else 1;
            try capturef(g, shot.target, CINEMA_DIR ++ "/lens-{d}-{s}.png", .{ size.y, field.name });
            const image = try readTarget(shot.target);
            defer rl.unloadImage(image);
            if (differentPixels(base, image) == 0) return error.LensDidNotChangeFrame;
            if (comptime std.mem.eql(u8, field.name, "lens_blur")) {
                var points = grid.Cells.of(.{ .x = 0, .y = @intFromFloat(@ceil(SHARP_BAND[0] * @as(f32, @floatFromInt(size.y)))) }, .{ .x = size.x, .y = @intFromFloat(@floor(SHARP_BAND[1] * @as(f32, @floatFromInt(size.y)))) });
                while (points.next()) |p| {
                    if (!sameRgb(rl.getImageColor(base, p.x, p.y), rl.getImageColor(image, p.x, p.y))) return error.LensBlurChangedSharpBand;
                }
            }
        }
        lens.options = .{ .lens_blur = 1, .perspective = 1, .vignette = 1, .saturation = 1.2, .warmth = 0.3 };
        try capturef(g, shot.target, CINEMA_DIR ++ "/lens-{d}-all.png", .{size.y});
        const on_ms = try meanDraw(g, shot.target, CINEMA_WARM, CINEMA_FRAMES);
        if (!sizedTo(lens.scene.?, lens.spread.?, size)) return error.LensResizeFailed;
        lens.options = .neutral;
        if (try redrawnDiff(g, shot.target, base) != 0) return error.LensOffChangedFrame;
        std.debug.print("lens {d}p: off {d:.3} ms, all {d:.3} ms mean headless draw\n", .{ size.y, try meanDraw(g, shot.target, CINEMA_WARM, CINEMA_FRAMES), on_ms });
        std.debug.print("lens {d}p: independent effects, sharp middle, resize and exact restoration checked\n", .{size.y});
        lens.options = .{};
        try capturef(g, shot.target, CINEMA_DIR ++ "/lens-{d}-defaults.png", .{size.y});
        game.character.openPause(g);
        g.pause_page = .visuals;
        g.pause_menu.at = 0;
        try capturef(g, shot.target, CINEMA_DIR ++ "/lens-{d}-options.png", .{size.y});
        g.pause_menu.at = options_menu.index(.visuals, .set_all_to_0);
        try capturef(g, shot.target, CINEMA_DIR ++ "/lens-{d}-filters-menu.png", .{size.y});
        g.pause_page = .display;
        g.pause_menu = .{};
        try capturef(g, shot.target, CINEMA_DIR ++ "/lens-{d}-display-menu.png", .{size.y});
        g.mode = .play;
    }
}

pub fn cinemaWater(g: *game.Game, target: rl.RenderTexture2D) !void {
    poseWaterMirrors(g, day.NOON, true);
    try captureCinemaScene(g, target, "water-day", .{});
    poseWaterMirrors(g, NIGHT, true);
    try captureCinemaScene(g, target, "water-night", .{});
    try checkCinema(g, target);
}

pub const Scene = struct { bench: bool = false, bloomless: bool = false };

pub fn captureCinemaScene(g: *game.Game, target: rl.RenderTexture2D, comptime name: []const u8, comptime scene: Scene) !void {
    const lens_options = neutralLens(g);
    defer g.cinema.lens.options = lens_options;
    const options = g.cinema.options;
    defer g.cinema.options = options;
    try std.fs.cwd().makePath(CINEMA_DIR);
    g.cinema.options = cinema.Options.off;
    try capture(g, target, CINEMA_DIR ++ "/" ++ name ++ "-off.png");
    const base = try readTarget(target);
    defer rl.unloadImage(base);
    if (g.cinema.bloom == null or g.cinema.air == null or g.cinema.focus == null) return error.CinemaShaderMissing;
    inline for (std.meta.fields(cinema.Options)) |f| {
        g.cinema.options = cinema.Options.off;
        @field(g.cinema.options, f.name) = true;
        try capture(g, target, CINEMA_DIR ++ "/" ++ name ++ "-" ++ f.name ++ ".png");
        const img = try readTarget(target);
        defer rl.unloadImage(img);
        const c = game.scene.Cam.of(g);
        var changed: usize = 0;
        var hidden: usize = 0;
        {
            const log = journal.box(g.screen);
            const lo_x: i32 = @intFromFloat(@ceil(log.x + log.width));
            const hi_x: i32 = @intFromFloat(game.scene.miniFrame(g.screen.x).x);
            var px = grid.Cells.of(.{ .x = lo_x, .y = 0 }, .{ .x = hi_x, .y = g.screen.y - hud.COVER });
            while (px.next()) |q| {
                const x = q.x;
                const y = q.y;
                const a = rl.getImageColor(base, x, y);
                const b = rl.getImageColor(img, x, y);
                const same = sameRgb(a, b);
                changed += @intFromBool(!same);
                const p = c.cellAt(q);
                const live_only = comptime cinema.LIVE_ONLY.contains(@field(cinema.Effect, f.name));
                const dx = @mod(x + c.x, game.CELL);
                const dy = @mod(y + c.y, game.CELL);
                const interior = dx >= game.CELL / light.SUB and dx < game.CELL - game.CELL / light.SUB and dy >= game.CELL / light.SUB and dy < game.CELL - game.CELL / light.SUB;
                const sight = g.light.sightAt((@as(f32, @floatFromInt(x + c.x)) + 0.5) / game.CELL_F, (@as(f32, @floatFromInt(y + c.y)) + 0.5) / game.CELL_F);
                if (interior and (!g.sim.lv.isSeen(p) or (live_only and sight == 0))) {
                    hidden += 1;
                    if (!same) {
                        std.debug.print("cinema {s}/{s} changed hidden pixel {d},{d}, cell {d},{d}: {any} to {any}\n", .{ name, f.name, x, y, p.x, p.y, a, b });
                        return error.CinemaRevealedTerrain;
                    }
                }
            }
        }
        if (comptime scene.bloomless and @field(cinema.Effect, f.name) == .bloom) {
            if (changed != 0) return error.CinemaBloomWithoutSource;
        }
        std.debug.print("cinema {s}/{s}: {d} changed pixels, {d} hidden pixels unchanged\n", .{ name, f.name, changed, hidden });
    }
    const air_strength = g.cinema.strengths.atmosphere;
    g.cinema.options = cinema.Options.off;
    g.cinema.options.atmosphere = true;
    g.cinema.strengths.atmosphere = 0;
    const zero_diff = redrawnDiff(g, target, base);
    g.cinema.strengths.atmosphere = air_strength;
    if (try zero_diff != 0) return error.ZeroAtmosphereChangedFrame;
    g.cinema.options = .{};
    try capture(g, target, CINEMA_DIR ++ "/" ++ name ++ "-all.png");
    if (scene.bench) {
        for ([_]bool{ false, true }) |enabled| {
            g.cinema.options.atmosphere = enabled;
            std.debug.print("atmosphere {s}/{s}: {d:.3} ms mean draw\n", .{ name, if (enabled) "on" else "off", try meanDraw(g, target, CINEMA_WARM, CINEMA_FRAMES) });
        }
    }
    g.cinema.options = cinema.Options.off;
    if (try redrawnDiff(g, target, base) != 0) return error.CinemaOffChangedFrame;
}

const CINEMA_FRAMES = 120;
const CINEMA_WARM = 12;

fn checkCinema(g: *game.Game, target: rl.RenderTexture2D) !void {
    g.pic.fx.zap(0, POSE_ZAP);
    try captureCinemaScene(g, target, "spell", .{});
    const options = g.cinema.options;
    defer g.cinema.options = options;
    for ([_]bool{ false, true }) |enabled| {
        g.cinema.options = if (enabled) .{} else cinema.Options.off;
        std.debug.print("cinema {s}: {d:.3} ms mean headless draw over {d} frames\n", .{ if (enabled) "on" else "off", try meanDraw(g, target, CINEMA_WARM, CINEMA_FRAMES), CINEMA_FRAMES });
    }
    for (SIZES ++ [_]P{g.screen}) |size| {
        const resized = try targetAt(g, size);
        defer resized.close(g);
        drawInto(g, resized.target);
        if (!sizedTo(g.cinema.scene.?, g.cinema.spread.?, size)) return error.CinemaResizeFailed;
    }
    std.debug.print("cinema targets: 720p, 1080p and restored dimensions checked\n", .{});
}

fn sizedTo(scene: rl.RenderTexture2D, spread: rl.RenderTexture2D, size: P) bool {
    return raster.extentOf(scene.texture).eq(size) and raster.extentOf(spread.texture).eq(size);
}
