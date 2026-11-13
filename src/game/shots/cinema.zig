const std = @import("std");
const journal = @import("../../ui/journal.zig");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const hud = @import("../../ui/hud.zig");
const light = @import("../../gfx/light.zig");
const cinema = @import("../../gfx/cinema.zig");
const day = @import("../../map/day.zig");
const fire = @import("../../map/fire.zig");
const gas = @import("../../map/gas.zig");
const options_menu = @import("../../ui/options.zig");
const game = @import("../../game.zig");

const P = mathx.P;
const CINEMA_DIR = @import("capture.zig").CINEMA_DIR;
const capture = @import("capture.zig").capture;
const differentPixels = @import("capture.zig").differentPixels;
const neutralLens = @import("capture.zig").neutralLens;
const drawInto = @import("capture.zig").drawInto;
const dropAtlas = @import("capture.zig").dropAtlas;
const heapAtlas = @import("capture.zig").heapAtlas;
const readTarget = @import("capture.zig").readTarget;
const redrawnDiff = @import("capture.zig").redrawnDiff;
const renderTarget = @import("capture.zig").renderTarget;
const sameRgb = @import("capture.zig").sameRgb;
const targetAt = @import("capture.zig").targetAt;
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
    try captureCinemaScene(g, target, "strand");
    poseForest(g);
    studyAt(g, true, MORNING);
    try captureCinemaScene(g, target, "forest");
    try cinemaWater(g, target);
    try captureLens(g);
    try captureVisibility(g, target);
    game.character.openPause(g);
    game.debugging.select(g, .composed_lighting);
    try capture(g, target, CINEMA_DIR ++ "/debug.png");
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
    var path: [160]u8 = undefined;
    var elapsed: f32 = 0;
    for (times) |t| {
        game.harness.ease(g, t - elapsed);
        g.light.step(&g.sim.lv, t - elapsed);
        elapsed = t;
        try capture(g, target, try std.fmt.bufPrintZ(&path, CINEMA_DIR ++ "/visibility-" ++ way ++ "-{d:.0}ms.png", .{t * 1000}));
    }
}

fn captureLens(g: *game.Game) !void {
    const lens = &g.cinema.lens;
    const before = lens.options;
    defer lens.options = before;
    if (lens.program == null) return error.LensShaderMissing;
    for ([_]P{ game.SCREEN_720, game.SCREEN_1080 }) |size| {
        const shot = try targetAt(g, size);
        defer shot.close(g);
        poseWaterMirrors(g, day.NOON, true);
        lens.options = .neutral;
        drawInto(g, shot.target);
        const base = try readTarget(shot.target);
        defer rl.unloadImage(base);
        var path: [160]u8 = undefined;
        try capture(g, shot.target, try std.fmt.bufPrintZ(&path, CINEMA_DIR ++ "/lens-{d}-off.png", .{size.y}));
        inline for (std.meta.fields(@TypeOf(lens.options))) |field| {
            lens.options = .neutral;
            @field(lens.options, field.name) = if (comptime std.mem.eql(u8, field.name, "saturation")) 0 else 1;
            try capture(g, shot.target, try std.fmt.bufPrintZ(&path, CINEMA_DIR ++ "/lens-{d}-{s}.png", .{ size.y, field.name }));
            const image = try readTarget(shot.target);
            defer rl.unloadImage(image);
            if (differentPixels(base, image) == 0) return error.LensDidNotChangeFrame;
            if (comptime std.mem.eql(u8, field.name, "lens_blur")) {
                var points = grid.Cells.of(.{ .x = 0, .y = @divTrunc(size.y * 40, 100) }, .{ .x = size.x, .y = @divTrunc(size.y * 60, 100) });
                while (points.next()) |p| {
                    if (!sameRgb(rl.getImageColor(base, p.x, p.y), rl.getImageColor(image, p.x, p.y))) return error.LensBlurChangedSharpBand;
                }
            }
        }
        lens.options = .{ .lens_blur = 1, .perspective = 1, .vignette = 1, .saturation = 1.2, .warmth = 0.3 };
        try capture(g, shot.target, try std.fmt.bufPrintZ(&path, CINEMA_DIR ++ "/lens-{d}-all.png", .{size.y}));
        const on_ms = try meanDraw(g, shot.target, CINEMA_WARM, CINEMA_FRAMES);
        if (lens.scene.?.texture.width != size.x or lens.scene.?.texture.height != size.y or lens.spread.?.texture.width != size.x or lens.spread.?.texture.height != size.y) return error.LensResizeFailed;
        lens.options = .neutral;
        if (try redrawnDiff(g, shot.target, base) != 0) return error.LensOffChangedFrame;
        std.debug.print("lens {d}p: off {d:.3} ms, all {d:.3} ms mean headless draw\n", .{ size.y, try meanDraw(g, shot.target, CINEMA_WARM, CINEMA_FRAMES), on_ms });
        std.debug.print("lens {d}p: independent effects, sharp middle, resize and exact restoration checked\n", .{size.y});
        lens.options = .{};
        try capture(g, shot.target, try std.fmt.bufPrintZ(&path, CINEMA_DIR ++ "/lens-{d}-defaults.png", .{size.y}));
        game.character.openPause(g);
        g.pause_page = .visuals;
        g.pause_menu.at = 0;
        try capture(g, shot.target, try std.fmt.bufPrintZ(&path, CINEMA_DIR ++ "/lens-{d}-options.png", .{size.y}));
        g.pause_menu.at = options_menu.index(.visuals, .set_all_to_0);
        try capture(g, shot.target, try std.fmt.bufPrintZ(&path, CINEMA_DIR ++ "/lens-{d}-filters-menu.png", .{size.y}));
        g.pause_page = .display;
        g.pause_menu = .{};
        try capture(g, shot.target, try std.fmt.bufPrintZ(&path, CINEMA_DIR ++ "/lens-{d}-display-menu.png", .{size.y}));
        g.mode = .play;
    }
}

pub fn cinemaWater(g: *game.Game, target: rl.RenderTexture2D) !void {
    poseWaterMirrors(g, day.NOON, true);
    try captureCinemaScene(g, target, "water-day");
    poseWaterMirrors(g, NIGHT, true);
    try captureCinemaScene(g, target, "water-night");
    try checkCinema(g, target);
}

pub fn captureCinemaScene(g: *game.Game, target: rl.RenderTexture2D, comptime name: []const u8) !void {
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
                const sight = g.light.sightAt(@as(f32, @floatFromInt(x + c.x)) / game.CELL_F, @as(f32, @floatFromInt(y + c.y)) / game.CELL_F);
                if (interior and (!g.sim.lv.isSeen(p) or (live_only and sight == 0))) {
                    hidden += 1;
                    if (!same) {
                        std.debug.print("cinema {s}/{s} changed hidden pixel {d},{d}, cell {d},{d}: {any} to {any}\n", .{ name, f.name, x, y, p.x, p.y, a, b });
                        return error.CinemaRevealedTerrain;
                    }
                }
            }
        }
        if (comptime std.mem.eql(u8, name, "forest") and @field(cinema.Effect, f.name) == .bloom) {
            if (changed != 0) return error.CinemaBloomWithoutSource;
        }
        std.debug.print("cinema {s}/{s}: {d} changed pixels, {d} hidden pixels unchanged\n", .{ name, f.name, changed, hidden });
    }
    g.cinema.options = .{};
    try capture(g, target, CINEMA_DIR ++ "/" ++ name ++ "-all.png");
    g.cinema.options = cinema.Options.off;
    if (try redrawnDiff(g, target, base) != 0) return error.CinemaOffChangedFrame;
}

const CINEMA_FRAMES = 120;
const CINEMA_WARM = 12;

fn checkCinema(g: *game.Game, target: rl.RenderTexture2D) !void {
    g.pic.fx.zap(0, POSE_ZAP);
    try captureCinemaScene(g, target, "spell");
    const options = g.cinema.options;
    defer g.cinema.options = options;
    for ([_]bool{ false, true }) |enabled| {
        g.cinema.options = if (enabled) .{} else cinema.Options.off;
        std.debug.print("cinema {s}: {d:.3} ms mean headless draw over {d} frames\n", .{ if (enabled) "on" else "off", try meanDraw(g, target, CINEMA_WARM, CINEMA_FRAMES), CINEMA_FRAMES });
    }
    for ([_]P{ game.SCREEN_720, game.SCREEN_1080, g.screen }) |size| {
        const resized = try targetAt(g, size);
        defer resized.close(g);
        drawInto(g, resized.target);
        if (g.cinema.scene.?.texture.width != size.x or g.cinema.scene.?.texture.height != size.y or g.cinema.spread.?.texture.width != size.x or g.cinema.spread.?.texture.height != size.y) return error.CinemaResizeFailed;
    }
    std.debug.print("cinema targets: 720p, 1080p and restored dimensions checked\n", .{});
}
