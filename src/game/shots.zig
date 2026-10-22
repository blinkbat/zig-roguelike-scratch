const std = @import("std");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const journal = @import("../ui/journal.zig");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const gen = @import("../map/gen.zig");
const carve = @import("../map/carve.zig");
const gas = @import("../map/gas.zig");
const atlas = @import("../map/atlas.zig");
const spar = @import("../map/spar.zig");
const editor = @import("../edit/editor.zig");
const menu = @import("../ui/menu.zig");
const hud = @import("../ui/hud.zig");
const book = @import("../ui/book.zig");
const heroes = @import("../play/hero.zig");
const naming = @import("../ui/naming.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const burning = @import("../play/burning.zig");
const bleeding = @import("../play/bleeding.zig");
const glacial = @import("../play/glacial.zig");
const juke = @import("../play/juke.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const dual = @import("../gfx/ground.zig");
const light = @import("../gfx/light.zig");
const fx = @import("../gfx/fx.zig");
const cinema = @import("../gfx/cinema.zig");
const sky = @import("../gfx/sky.zig");
const day = @import("../map/day.zig");
const game = @import("../game.zig");
const P = mathx.P;
const CONFIRM = menu.CONFIRM;
const SHOOT = bow.VERB;
const HERO = actor.HERO;
const SHOT_SEED: u64 = 0x5EED_1234;
const SHOTS_DIR = "shots";
const SHOTS_MAPS = SHOTS_DIR ++ "/maps";

fn renderTarget(g: *game.Game) !rl.RenderTexture2D {
    return rl.loadRenderTexture(g.screen.x, g.screen.y);
}

pub fn shoot(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_DIR);

    game.begin(g, SHOT_SEED);
    poseRat(g);
    g.st.lean = true;
    try capture(g, target, SHOTS_DIR ++ "/lean.png");

    g.st.lean = false;
    game.openAim(g, game.harness.boundTo(g, .shoot).by, .shoot);
    try capture(g, target, SHOTS_DIR ++ "/aim.png");

    g.mode = .play;
    poseTorch(g);
    try capture(g, target, SHOTS_DIR ++ "/torch.png");

    posePicker(g, game.harness.boundTo(g, .shoot));
    try capture(g, target, SHOTS_DIR ++ "/bind.png");

    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    game.harness.grassOver(&g.lv);
    const chest_at = P{ .x = 21, .y = 20 };
    g.lv.set(chest_at, .chest);
    g.lv.putBarrel(.{ .x = 23, .y = 20 });
    game.settle(g);
    try capture(g, target, SHOTS_DIR ++ "/chest-closed.png");
    game.heroStep(g, .e, 0);
    game.harness.drawnOut(g);
    if (g.lv.at(chest_at) != .chest_open or g.ground.coin_n != 0 or g.gold < items.CHEST_GOLD.lo or g.character.page != .loot) return error.ChestUnopened;
    try capture(g, target, SHOTS_DIR ++ "/chest-loot.png");
    game.character.characterCommand(g, .close);
    try capture(g, target, SHOTS_DIR ++ "/chest-open.png");

    game.harness.arena(g, .{ .x = 20, .y = 15 }, &.{.{ .x = 25, .y = 14 }});
    g.lv.set(.{ .x = 21, .y = 15 }, .water);
    _ = g.pool.damage(&g.lv, g.hero, 6);
    game.settle(g);
    game.openLeap(g, game.harness.boundTo(g, .juke).by, .juke);
    g.mark = .{ .x = 20 + juke.RANGE, .y = 15 };
    try capture(g, target, SHOTS_DIR ++ "/juke-aim.png");
    game.confirmAim(g);
    g.st = .{};
    game.update(g, 0.06);
    try capture(g, target, SHOTS_DIR ++ "/juke.png");

    game.harness.arena(g, .{ .x = 20, .y = 15 }, &.{});
    _ = game.harness.spawnAt(g, .slime, .{ .x = 28, .y = 15 }, false);
    game.settle(g);
    g.rng = game.harness.procRng(g, .burning_arrow, 1, true);
    game.useSkill(g, game.harness.boundTo(g, .burning_arrow));
    try capture(g, target, SHOTS_DIR ++ "/burning-aim.png");
    game.confirmAim(g);
    g.st = .{};
    game.update(g, 0.08);
    try capture(g, target, SHOTS_DIR ++ "/burning-arrow.png");
    game.update(g, 0.10);
    try capture(g, target, SHOTS_DIR ++ "/burning.png");

    game.harness.arena(g, .{ .x = 20, .y = 15 }, &.{});
    _ = game.harness.spawnAt(g, .slime, .{ .x = 26, .y = 15 }, false);
    _ = game.harness.spawnAt(g, .slime, .{ .x = 27, .y = 14 }, false);
    _ = game.harness.spawnAt(g, .slime, .{ .x = 28, .y = 16 }, false);
    game.settle(g);
    g.rng = game.harness.procRng(g, .glacial_shot, 3, true);
    game.useSkill(g, game.harness.boundTo(g, .glacial_shot));
    try capture(g, target, SHOTS_DIR ++ "/glacial-aim.png");
    game.confirmAim(g);
    g.st = .{};
    game.update(g, 0.05);
    try capture(g, target, SHOTS_DIR ++ "/glacial-arrow.png");
    game.update(g, 0.14);
    try capture(g, target, SHOTS_DIR ++ "/glacial.png");
    game.harness.drawnOut(g);
    posePicker(g, game.harness.boundTo(g, .glacial_shot));
    try capture(g, target, SHOTS_DIR ++ "/glacial-bind.png");

    try shootEffects(g, target);

    poseFright(g);
    if (speechLeft(g) <= fx.SPEECH_FADE_S) return error.FrightUnspoken;
    try capture(g, target, SHOTS_DIR ++ "/pib-fright.png");
    game.update(g, speechLeft(g) - fx.SPEECH_FADE_S / 2);
    try capture(g, target, SHOTS_DIR ++ "/pib-fright-fade.png");

    poseGas(g);
    try capture(g, target, SHOTS_DIR ++ "/gas.png");
    g.cloud.clear();
    try capture(g, target, SHOTS_DIR ++ "/gas-clear.png");
    g.cloud.settle(&g.lv);

    game.character.openPause(g);
    try capture(g, target, SHOTS_DIR ++ "/pause.png");
    g.pause_menu.at = game.rowAt(game.PauseRow.debug);
    game.harness.press(g, CONFIRM);
    try capture(g, target, SHOTS_DIR ++ "/debug.png");
    g.mode = .play;

    poseWaterSteps(g);
    try capture(g, target, SHOTS_DIR ++ "/water-steps.png");

    for ([_]struct { hour: f32, outdoors: bool, path: [:0]const u8 }{
        .{ .hour = day.NOON, .outdoors = true, .path = SHOTS_DIR ++ "/water-mirrors-day.png" },
        .{ .hour = NIGHT, .outdoors = true, .path = SHOTS_DIR ++ "/water-mirrors-night.png" },
        .{ .hour = day.NOON, .outdoors = false, .path = SHOTS_DIR ++ "/water-mirrors-torch.png" },
    }) |study| {
        poseWaterMirrors(g, study.hour, study.outdoors);
        try capture(g, target, study.path);
    }
    try checkWaterMirrors(g, target);
    try checkMapEdge(g, target);
    try cinemaWater(g, target);

    poseForest(g);
    try capture(g, target, SHOTS_DIR ++ "/forest.png");
    studyAt(g, true, MORNING);
    try captureCinema(g, target, "forest");
    for ([_]struct { hour: f32, name: [:0]const u8 }{
        .{ .hour = MORNING, .name = SHOTS_DIR ++ "/shadows-morning.png" },
        .{ .hour = day.NOON, .name = SHOTS_DIR ++ "/shadows-noon.png" },
        .{ .hour = EVENING, .name = SHOTS_DIR ++ "/shadows-evening.png" },
        .{ .hour = day.DEAD_OF_NIGHT, .name = SHOTS_DIR ++ "/shadows-moon.png" },
    }) |study| {
        poseShadowStudy(g, study.hour, true);
        try capture(g, target, study.name);
    }
    poseShadowStudy(g, day.NOON, false);
    try capture(g, target, SHOTS_DIR ++ "/shadows-torch.png");
    for ([_]struct { hour: ?f32, path: [:0]const u8 }{
        .{ .hour = MORNING, .path = SHOTS_DIR ++ "/shadows-hidden-sun.png" },
        .{ .hour = NIGHT, .path = SHOTS_DIR ++ "/shadows-hidden-moon.png" },
        .{ .hour = null, .path = SHOTS_DIR ++ "/shadows-hidden-torch.png" },
    }) |study| {
        poseHiddenShadows(g, study.hour);
        try checkHiddenShadowMask(g, target, true);
        try capture(g, target, study.path);
        @memset(&g.lv.lit, false);
        @memset(&g.lv.seen, true);
        g.light.settle(&g.lv);
        try checkHiddenShadowMask(g, target, false);
    }
    poseHiddenShadows(g, MORNING);
    g.cam.x = @floatFromInt(HIDDEN_SHADOW_X * game.CELL - g.screen.x);
    try checkHiddenShadowMask(g, target, true);
    try capture(g, target, SHOTS_DIR ++ "/shadows-offscreen.png");

    try shootHud(g);

    try shootLevelUp(g);

    {
        const w = try std.heap.c_allocator.create(atlas.Atlas);
        defer std.heap.c_allocator.destroy(w);
        try overviews(g, w);
        {
            try w.load(std.heap.c_allocator, atlas.mapPath(SHOT_BIOME));
            game.beginMapAt(g, w, w.start, SHOT_SEED);
            try capture(g, target, SHOTS_DIR ++ "/biome.png");
        }
        {
            try loadStrand(g, w);
            try capture(g, target, SHOTS_DIR ++ "/strand.png");
            try captureCinema(g, target, "strand");
            const seen = g.lv.seen;
            const lit = g.lv.lit;
            game.character.toggleReveal(g);
            try capture(g, target, SHOTS_DIR ++ "/map-revealed.png");
            game.character.toggleReveal(g);
            if (!std.mem.eql(bool, &seen, &g.lv.seen) or !std.mem.eql(bool, &lit, &g.lv.lit)) return error.RevealChangedSight;
            try checkWaterSurface(g);
            try shootWater(g, target);
        }
        {
            try w.load(std.heap.c_allocator, atlas.mapPath(SHOT_OUTDOOR));
            for (SHOT_HOURS) |s| {
                game.beginMapAt(g, w, w.start, SHOT_SEED);
                g.lv.seen = @splat(false);
                g.clock = day.Clock.at(s.hour);
                game.settle(g);
                try capture(g, target, s.path);
            }
            inline for ([_]f32{ BLEAK_MORNING, day.NOON, DUSK, day.DEAD_OF_NIGHT }) |hour| {
                game.beginMapAt(g, w, w.start, SHOT_SEED);
                g.clock = day.Clock.at(hour);
                game.settle(g);
                g.light.sky = sky.under(hour, .bleak);
                try capture(g, target, SHOTS_DIR ++ "/bleak-" ++ std.fmt.comptimePrint("{d:.1}", .{hour}) ++ ".png");
            }
            g.clock = day.Clock.at(day.NOON);
            game.settle(g);
            g.clock = day.Clock.at(day.DEAD_OF_NIGHT);
            game.settle(g);
            try capture(g, target, SHOTS_DIR ++ "/night-memory.png");
        }
        game.begin(g, SHOT_SEED);
    }

    try editor.shoot(g, target, SHOTS_DIR ++ "/edit.png", SHOTS_DIR ++ "/edit-graph.png", SHOTS_DIR ++ "/edit-gen.png", SHOTS_DIR ++ "/edit-objects.png");
    try shootCharacter(g);
    try shootLoot(g);

    const entry = naming.Entry{ .name = heroes.Name.of("Arwen"), .row = 2, .col = 4 };
    rl.beginTextureMode(target);
    rl.clearBackground(look.BG);
    var title: [naming.TITLE_MAX]u8 = undefined;
    naming.draw(&entry, g.face, g.screen, naming.titleOf(heroes.DEFAULT, &title), .xbox);
    rl.endTextureMode();
    try exportTarget(target, SHOTS_DIR ++ "/name.png");
}

pub fn shootUi(g: *game.Game) !void {
    try std.fs.cwd().makePath(SHOTS_DIR);
    try shootCharacter(g);
    try shootLoot(g);
    try shootHud(g);
    try shootLevelUp(g);
}

pub fn shootDebug(g: *game.Game) !void {
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/debug");
    const screen = g.screen;
    defer g.screen = screen;
    g.screen = game.SCREEN_720;
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    poseWaterMirrors(g, MORNING, true);
    g.fx.zap(0, POSE_ZAP);
    try capture(g, target, SHOTS_DIR ++ "/debug/all-on.png");
    inline for (std.meta.fields(light.Options)) |f| {
        try checkDebugOption(g, target, &@field(g.light.options, f.name), f.name);
    }
    try checkDebugOption(g, target, &g.debug.visuals.water_reflections, "water_reflections");
    const w = try std.heap.c_allocator.create(atlas.Atlas);
    defer std.heap.c_allocator.destroy(w);
    defer g.map = null;
    try loadStrand(g, w);
    try checkDebugOption(g, target, &g.debug.visuals.weather, "weather");
    game.character.openPause(g);
    inline for (comptime std.enums.values(game.debugging.Page)) |page| {
        game.debugging.open(g, page);
        try capture(g, target, SHOTS_DIR ++ "/debug/menu-" ++ @tagName(page) ++ ".png");
    }
    try shootLoot(g);
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
    drawInto(g, target);
    const restored = try readTarget(target);
    defer rl.unloadImage(restored);
    if (differentPixels(before, restored) != 0) return error.DebugOptionDidNotRestoreFrame;
    std.debug.print("Debug {s}: {d} pixels changed, exact restoration\n", .{ name, changed });
}

fn differentPixels(a: rl.Image, b: rl.Image) usize {
    var changed: usize = 0;
    var px = pixels(a.width, a.height);
    while (px.next()) |p| changed += @intFromBool(!sameRgb(rl.getImageColor(a, p.x, p.y), rl.getImageColor(b, p.x, p.y)));
    return changed;
}

fn pixels(width: i32, height: i32) grid.Cells {
    return grid.Cells.of(.{ .x = 0, .y = 0 }, .{ .x = width, .y = height });
}

fn shootLoot(g: *game.Game) !void {
    const screen = g.screen;
    defer g.screen = screen;
    const device = g.st.device;
    defer g.st.device = device;
    g.screen = game.SCREEN_720;
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    game.harness.grassOver(&g.lv);
    const bag = P{ .x = 19, .y = 20 };
    const chest = P{ .x = 21, .y = 20 };
    for ([_]items.Kind{ .ring, .boots, .axe }) |kind| _ = g.ground.add(.{ .item = .{ .kind = kind, .mods = .{ if (kind == .axe) .{ .kind = .strength, .value = 3 } else null, null } }, .at = bag });
    g.lv.set(chest, .chest);
    game.settle(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-ground.png");
    _ = game.character.openNearby(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-containers.png");
    game.character.openLoot(g, bag);
    g.st.device = .xbox;
    try capture(g, target, SHOTS_DIR ++ "/loot-bag-pad.png");
    g.st.device = .keys;
    try capture(g, target, SHOTS_DIR ++ "/loot-bag-keys.png");
    game.character.characterCommand(g, .close);
    game.character.openLoot(g, chest);
    game.harness.drawnOut(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-chest.png");
    game.character.characterCommand(g, .close);
    try capture(g, target, SHOTS_DIR ++ "/loot-chest-left.png");
    game.character.openLoot(g, chest);
    game.character.characterCommand(g, .take_all);
    game.harness.drawnOut(g);
    if (g.ground.n != 3 or g.inventory.n != 1 or g.lv.at(chest) != .chest_open) return error.LootContainerMismatch;
    try capture(g, target, SHOTS_DIR ++ "/loot-chest-empty.png");
    for (0..items.BAG_MAX - g.inventory.n) |_| _ = g.inventory.add(.{ .kind = .cap });
    game.character.openLoot(g, bag);
    game.character.characterCommand(g, .take_all);
    try capture(g, target, SHOTS_DIR ++ "/loot-full.png");

    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{chest});
    game.harness.grassOver(&g.lv);
    g.loot_rng = game.harness.lootRng(true);
    game.settle(g);
    game.harness.slay(g, 2, g.heroActor().?.at);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-before.png");
    game.harness.drawnOut(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-dropped.png");
    game.character.openLoot(g, chest);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-blue.png");
}

fn shootLevelUp(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/level-up");
    inline for (.{ .{ "day", day.NOON }, .{ "night", NIGHT } }) |scene| {
        poseForest(g);
        studyAt(g, true, scene[1]);
        g.st = .{ .device = .keys };
        game.settleXp(g);
        try capture(g, target, SHOTS_DIR ++ "/level-up/" ++ scene[0] ++ "-before.png");
        _ = g.growth.gain(@intCast(g.growth.needed()));
        game.update(g, 0);
        var elapsed: f32 = 0;
        inline for (.{ 0.12, 0.4, 0.9, 1.5, 2.1 }, 0..) |time, i| {
            game.update(g, time - elapsed);
            elapsed = time;
            try capture(g, target, std.fmt.comptimePrint(SHOTS_DIR ++ "/level-up/{s}-{d}.png", .{ scene[0], i }));
        }
    }
}

pub fn shootCinema(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    const w = try std.heap.c_allocator.create(atlas.Atlas);
    defer std.heap.c_allocator.destroy(w);
    try loadStrand(g, w);
    try captureCinema(g, target, "strand");
    poseForest(g);
    studyAt(g, true, MORNING);
    try captureCinema(g, target, "forest");
    try cinemaWater(g, target);
    game.character.openPause(g);
    game.debugging.select(g, .composed_lighting);
    try capture(g, target, SHOTS_DIR ++ "/cinema/debug.png");
}

/// The start map with its weather under way.
fn loadStrand(g: *game.Game, w: *atlas.Atlas) !void {
    try w.load(std.heap.c_allocator, atlas.START);
    game.beginMapAt(g, w, w.start, SHOT_SEED);
    for (0..RAIN_FRAMES) |_| game.update(g, mathx.FRAME_DT);
}

/// Water by day and by night through each effect, then the effects' checks.
fn cinemaWater(g: *game.Game, target: rl.RenderTexture2D) !void {
    poseWaterMirrors(g, day.NOON, true);
    try captureCinema(g, target, "water-day");
    poseWaterMirrors(g, NIGHT, true);
    try captureCinema(g, target, "water-night");
    try checkCinema(g, target);
}

fn captureCinema(g: *game.Game, target: rl.RenderTexture2D, comptime name: []const u8) !void {
    const options = g.cinema.options;
    defer g.cinema.options = options;
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/cinema");
    g.cinema.options = cinema.Options.off;
    try capture(g, target, SHOTS_DIR ++ "/cinema/" ++ name ++ "-off.png");
    const base = try readTarget(target);
    defer rl.unloadImage(base);
    if (g.cinema.bloom == null or g.cinema.air == null or g.cinema.focus == null) return error.CinemaShaderMissing;
    inline for (std.meta.fields(cinema.Options)) |f| {
        g.cinema.options = cinema.Options.off;
        @field(g.cinema.options, f.name) = true;
        try capture(g, target, SHOTS_DIR ++ "/cinema/" ++ name ++ "-" ++ f.name ++ ".png");
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
                const p = mathx.cellOf(.{ @as(f32, @floatFromInt(x + c.x)) / game.CELL_F, @as(f32, @floatFromInt(y + c.y)) / game.CELL_F });
                const live_only = comptime cinema.LIVE_ONLY.contains(@field(cinema.Effect, f.name));
                const dx = @mod(x + c.x, game.CELL);
                const dy = @mod(y + c.y, game.CELL);
                const interior = dx >= game.CELL / light.SUB and dx < game.CELL - game.CELL / light.SUB and dy >= game.CELL / light.SUB and dy < game.CELL - game.CELL / light.SUB;
                if ((!g.lv.isSeen(p) and interior) or (live_only and !g.lv.isLit(p))) {
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
    try capture(g, target, SHOTS_DIR ++ "/cinema/" ++ name ++ "-all.png");
    g.cinema.options = cinema.Options.off;
    drawInto(g, target);
    const restored = try readTarget(target);
    defer rl.unloadImage(restored);
    var px = pixels(base.width, base.height);
    while (px.next()) |p| {
        if (!std.meta.eql(rl.getImageColor(base, p.x, p.y), rl.getImageColor(restored, p.x, p.y))) return error.CinemaOffChangedFrame;
    }
}

const CINEMA_FRAMES = 120;

fn checkCinema(g: *game.Game, target: rl.RenderTexture2D) !void {
    g.fx.zap(0, POSE_ZAP);
    try captureCinema(g, target, "spell");
    const options = g.cinema.options;
    defer g.cinema.options = options;
    for ([_]bool{ false, true }) |enabled| {
        g.cinema.options = if (enabled) .{} else cinema.Options.off;
        std.debug.print("cinema {s}: {d:.3} ms mean headless draw over {d} frames\n", .{ if (enabled) "on" else "off", try meanDraw(g, target, 12, CINEMA_FRAMES), CINEMA_FRAMES });
    }
    const screen = g.screen;
    defer g.screen = screen;
    for ([_]P{ game.SCREEN_720, game.SCREEN_1080, screen }) |size| {
        g.screen = size;
        const resized = try renderTarget(g);
        defer rl.unloadRenderTexture(resized);
        drawInto(g, resized);
        if (g.cinema.scene.?.texture.width != size.x or g.cinema.scene.?.texture.height != size.y or g.cinema.spread.?.texture.width != size.x or g.cinema.spread.?.texture.height != size.y) return error.CinemaResizeFailed;
    }
    std.debug.print("cinema targets: 720p, 1080p and restored dimensions checked\n", .{});
}

fn shootCharacter(g: *game.Game) !void {
    const w = try std.heap.c_allocator.create(atlas.Atlas);
    defer std.heap.c_allocator.destroy(w);
    defer g.map = null;
    const screen = g.screen;
    defer g.screen = screen;
    g.screen = game.SCREEN_720;
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    spar.author(w, .slime);
    g.class = heroes.DEFAULT;
    game.beginMapAt(g, w, w.start, SHOT_SEED);
    _ = g.growth.gain(100);
    _ = g.inventory.add(.{ .kind = .cap, .mods = .{ .{ .kind = .life, .value = 3 }, null } });
    try g.inventory.equip(0, .helm, g.growth.attributes(g.class));
    _ = g.inventory.add(.{ .kind = .bow, .mods = .{ .{ .kind = .dexterity, .value = 2 }, null } });
    try g.inventory.equip(0, .right_hand, g.growth.attributes(g.class));
    _ = g.inventory.add(.{ .kind = .helmet, .mods = .{ .{ .kind = .life, .value = 6 }, .{ .kind = .mana, .value = 10 } } });
    _ = g.inventory.add(.{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 3 }, null } });
    _ = g.inventory.add(.{ .kind = .leather });
    _ = g.ground.add(.{ .item = .{ .kind = .amulet }, .at = g.heroActor().?.at });
    g.log.push(.event, "Archer enters the old ruins.", .{});
    g.log.push(.damage, "Archer shoots the rat for 3.", .{});
    g.log.push(.danger, "The rat bites Archer for 2.", .{});
    g.log.push(.recovery, "Archer recovers 4 life.", .{});
    g.log.push(.loot, "Archer picks up 8 gold.", .{});
    g.log.push(.event, "Archer opens the chest.", .{});
    g.log.push(.loot, "Picked up Iron helm.", .{});
    g.log.push(.progress, "Level 3: +2 passive, +2 active points.", .{});
    g.log.push(.damage, "Archer shoots the slime for 4.", .{});
    g.log.push(.danger, "The slime hits Archer for 2.", .{});
    game.combat.noticeItems(g, g.heroActor().?.at);
    game.syncStats(g);
    game.harness.drawnOut(g);
    g.back = .editor;
    try capture(g, target, SHOTS_DIR ++ "/arena.png");
    game.character.openCharacter(g);
    inline for (book.PAGES) |page| {
        g.character.choose(page);

        if (page == .passives) g.character.cursor = progress.start(g.class);
        if (page == .equipment) g.character.cursor = @intFromEnum(items.Slot.helm);
        try capture(g, target, SHOTS_DIR ++ "/character-" ++ @tagName(page) ++ ".png");
    }
    {
        const device = g.st.device;
        defer g.st.device = device;
        g.st.device = .keys;
        g.character.choose(.equipment);
        try capture(g, target, SHOTS_DIR ++ "/character-keyboard.png");
    }
    {
        const gear = g.inventory.gear;
        defer g.inventory.gear = gear;
        const bag_n = g.inventory.n;
        defer g.inventory.n = bag_n;
        g.character.choose(.inventory);

        g.character.cursor = 2;
        try capture(g, target, SHOTS_DIR ++ "/item-normal-armour.png");
        g.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .mana, .value = 15 }, null } });
        g.inventory.gear.slots.set(.right_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .dexterity, .value = 3 }, null } });
        g.character.cursor = 1;
        g.character.destination_index = 0;
        try capture(g, target, SHOTS_DIR ++ "/item-ring-left.png");
        g.character.destination_index = 1;
        try capture(g, target, SHOTS_DIR ++ "/item-ring-right.png");
        g.inventory.gear.slots.set(.right_hand, .{ .kind = .sling });
        g.inventory.gear.slots.set(.left_hand, .{ .kind = .buckler, .mods = .{ .{ .kind = .life, .value = 6 }, null } });
        _ = g.inventory.add(.{ .kind = .crossbow, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .mana, .value = 10 } } });
        g.character.cursor = bag_n;
        g.character.destination_index = 0;
        try capture(g, target, SHOTS_DIR ++ "/item-two-handed.png");
        const class = g.class;
        defer g.class = class;
        g.class = .knight;
        g.inventory.gear.slots.set(.left_hand, null);
        g.character.choose(.equipment);

        inline for ([_]items.Kind{ .axe, .greatclub, .greatsword }) |kind| {
            g.inventory.gear.slots.set(.right_hand, .{ .kind = kind });
            g.character.cursor = @intFromEnum(items.Slot.right_hand);
            try capture(g, target, SHOTS_DIR ++ "/item-" ++ @tagName(kind) ++ "-equipped.png");
        }
        g.character.cursor = @intFromEnum(items.Slot.left_hand);
        try capture(g, target, SHOTS_DIR ++ "/item-offhand-occupied.png");
    }
    {
        const device = g.st.device;
        defer g.st.device = device;
        inline for ([_]input.Device{ .keys, .xbox, .ps5 }) |d| {
            g.st.device = d;
            g.character.choose(.passives);

            g.character.cursor = progress.start(g.class);
            try capture(g, target, SHOTS_DIR ++ "/tree-controls-" ++ @tagName(d) ++ ".png");
        }
        g.character.pan = .{ .x = 1.5, .y = -0.8 };
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-pan.png");
        g.character.pan = .{ .x = 0, .y = 0 };
        g.character.zoom = 1;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-overview.png");
    }
    {
        const was_class = g.class;
        const was_growth = g.growth;
        defer g.class = was_class;
        defer g.growth = was_growth;
        inline for (heroes.CLASSES) |class| {
            g.class = class;
            g.growth = progress.State.of(class);
            g.growth.active_points = 2;
            g.character.choose(.skills);

            g.character.cursor = progress.skills(class).len - 1;
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-future.png");
            g.character.cursor = if (class == .wizard) 4 else 0;
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-description.png");
            g.growth.ranks.set(progress.skills(class)[g.character.cursor].act, 2);
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-upgrade.png");
            if (class == .archer) {
                g.character.cursor = 2;
                g.growth.ranks.set(progress.skills(class)[2].act, 2);
                try capture(g, target, SHOTS_DIR ++ "/tree-skills-mixed-upgrade.png");
            }
            g.character.cursor = progress.skills(class).len - 1;
            g.growth.active_points = 30;
            for (progress.skills(class)) |s| while (g.growth.learn(class, s.act)) {};
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-maximum.png");
        }
        g.class = .knight;
        g.growth = progress.State.of(g.class);
        g.growth.passive_points = 30;
        const branch = progress.passives.branchFirst(.warrior_life);
        for (branch..branch + progress.passives.PER_BRANCH - 1) |i| _ = g.growth.allocate(i);
        const bridge = progress.passives.bridgeFirst(.warrior_rogue);
        _ = g.growth.allocate(bridge);
        g.character.choose(.passives);

        g.character.cursor = branch + progress.passives.PER_BRANCH - 1;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-capstone.png");
        g.character.zoom = 2.2;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-zoom.png");
        g.character.zoom = 1;
        g.character.cursor = branch + 1;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-interest.png");
        g.character.cursor = progress.passives.bridgeFirst(.warrior_rogue);
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-bridge.png");
        g.growth.passive_points = 0;
        g.character.cursor = branch + progress.passives.PER_BRANCH - 1;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-no-points.png");
    }
    {
        const book_screen = g.screen;
        const device = g.st.device;
        defer g.screen = book_screen;
        defer g.st.device = device;
        inline for (.{ game.WINDOW, game.SCREEN_1080 }) |size| {
            g.screen = size;
            g.st.device = .keys;
            const large = try renderTarget(g);
            defer rl.unloadRenderTexture(large);
            inline for (book.PAGES) |page| {
                g.character.choose(page);
                try capture(g, large, SHOTS_DIR ++ "/character-" ++ @tagName(page) ++ "-" ++ std.fmt.comptimePrint("{d}", .{size.x}) ++ ".png");
            }
        }
    }
    g.character.choose(.inventory);
    try capture(g, target, SHOTS_DIR ++ "/character-actions.png");
    g.mode = .play;
    _ = game.character.openNearby(g);
    try capture(g, target, SHOTS_DIR ++ "/character-nearby.png");
    g.mode = .play;
    g.log.release();
    try capture(g, target, SHOTS_DIR ++ "/event-log.png");
    g.inventory = .{};
    for (std.enums.values(items.Kind)) |kind| _ = g.inventory.add(.{ .kind = kind });
    g.mode = .pause;
    g.pause_page = .character;
    g.character.open();
    g.character.choose(.inventory);

    inline for ([_]items.Kind{ .crossbow, .dagger, .staff, .wand, .tome, .orb, .buckler, .shield, .totem }) |kind| {
        g.character.cursor = @intFromEnum(kind);
        try capture(g, target, SHOTS_DIR ++ "/item-" ++ @tagName(kind) ++ ".png");
    }
}

fn shootEffects(g: *game.Game, target: rl.RenderTexture2D) !void {
    inline for (.{
        .{ heroes.Class.wizard, skillbar.Act.spark },
        .{ heroes.Class.wizard, skillbar.Act.fireball },
        .{ heroes.Class.wizard, skillbar.Act.chain_lightning },
        .{ heroes.Class.wizard, skillbar.Act.frost_nova },
        .{ heroes.Class.wizard, skillbar.Act.blink },
        .{ heroes.Class.wizard, skillbar.Act.mana_shield },
        .{ heroes.Class.archer, skillbar.Act.burning_arrow },
        .{ heroes.Class.archer, skillbar.Act.glacial_shot },
    }) |study| {
        const act = study[1];
        const from = P{ .x = 20, .y = 20 };
        game.harness.heroArena(g, study[0], from, &.{});
        carve.box(&g.lv, .{ .lo = .{ .x = 13, .y = 13 }, .hi = .{ .x = 33, .y = 28 } }, .grass);
        game.harness.wallRow(&g.lv, 17, 18, 29);
        @import("../map/procgen.zig").reshape(&g.lv);
        for ([_]P{ .{ .x = 23, .y = 20 }, .{ .x = 24, .y = 19 }, .{ .x = 24, .y = 21 }, .{ .x = 22, .y = 21 } }) |at| _ = game.harness.spawnAt(g, .slime, at, false);
        game.harness.toughenFoes(g);
        g.clock = day.Clock.at(day.DEAD_OF_NIGHT);
        game.settle(g);
        const directory = SHOTS_DIR ++ "/fx-" ++ @tagName(act);
        try std.fs.cwd().makePath(directory);
        try capture(g, target, directory ++ "/before.png");
        game.useSkill(g, game.harness.boundTo(g, act));
        if (act.reticle()) |reticle| {
            g.mark = if (reticle == .leap) .{ .x = 22, .y = 20 } else .{ .x = 23, .y = 20 };
            game.confirmAim(g);
        }
        g.st = .{};
        var previous: f32 = 0;
        inline for ([_]f32{ 0.012, 0.028, 0.05, 0.09, 0.16, 0.26 }, 0..) |t, i| {
            game.update(g, t - previous);
            previous = t;
            try capture(g, target, directory ++ "/" ++ std.fmt.comptimePrint("{d}", .{i}) ++ ".png");
        }
    }
    g.class = heroes.DEFAULT;
    g.bar = skillbar.Bar.of(g.class);
}

fn shootHud(g: *game.Game) !void {
    const screen = g.screen;
    defer g.screen = screen;
    var saved_bar: skillbar.Bar = .{};
    saved_bar = g.bar;
    defer g.bar = saved_bar;
    var saved_state: input.State = .{};
    saved_state = g.st;
    defer g.st = saved_state;
    const studies = [_]struct { screen: P, hp: i32, mana: i32, xp: f32 = 0, device: input.Device, path: [:0]const u8, ailing: bool = false, bind: ?[:0]const u8 = null }{
        .{ .screen = game.SCREEN_720, .hp = 100, .mana = 100, .xp = 0.95, .device = .keys, .path = SHOTS_DIR ++ "/hud-full-1280.png", .bind = SHOTS_DIR ++ "/hud-bind-720.png" },
        .{ .screen = game.SCREEN_720, .hp = 75, .mana = 60, .xp = 0.62, .device = .ps5, .path = SHOTS_DIR ++ "/hud-ps5-1280.png", .bind = SHOTS_DIR ++ "/hud-bind-ps5.png" },
        .{ .screen = game.WINDOW, .hp = 50, .mana = 35, .xp = 0.37, .device = .xbox, .path = SHOTS_DIR ++ "/hud-partial-1600.png", .ailing = true },
        .{ .screen = game.SCREEN_1080, .hp = 10, .mana = 0, .xp = 0.08, .device = .keys, .path = SHOTS_DIR ++ "/hud-critical-1920.png" },
        .{ .screen = game.WINDOW, .hp = 0, .mana = 0, .device = .keys, .path = SHOTS_DIR ++ "/hud-empty-1600.png" },
    };
    for (studies) |study| {
        g.screen = study.screen;
        poseForest(g);
        g.bar = skillbar.Bar.of(g.class);
        g.st = .{ .device = study.device, .modifier = g.bar.modifier };
        const body = &g.pictured[game.heroSlot(g).?];
        body.hp = mathx.percentOf(body.max, study.hp);
        g.mana = mathx.percentOf(game.manaMax(g), study.mana);
        game.overlay.settleResources(g);
        g.xp_shown = study.xp;
        if (study.ailing) {
            body.status = .initDefault(0, .{ .bleeding = bleeding.TURNS, .burning = burning.TURNS, .chilled = glacial.TURNS - 1 });
            g.cooldown.set(.juke, juke.COOLDOWN);
        }
        const target = try renderTarget(g);
        defer rl.unloadRenderTexture(target);
        try capture(g, target, study.path);
        if (study.bind) |path| {
            posePicker(g, game.harness.boundTo(g, .shoot));
            try capture(g, target, path);
        }
        if (study.ailing) {
            g.bar.bind(.{ .set = .secondary, .button = .x }, .glacial_shot);
            g.bar.bind(.{ .set = .secondary, .button = .b }, .burning_arrow);
            g.st.down.insert(g.bar.modifier.?);
            try capture(g, target, SHOTS_DIR ++ "/hud-secondary-pad.png");
            g.st.down = .initEmpty();
            posePicker(g, game.harness.boundTo(g, .shoot));
            try capture(g, target, SHOTS_DIR ++ "/hud-bind-pad.png");
            g.mode = .inspect;
            g.inspecting = .{ .slot = game.Binds.colOf(.x) };
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-skill.png");
            g.inspecting = .{ .status = .burning };
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-status.png");
            g.inspecting = .mana;
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-mana.png");
            g.mode = .play;
        }
    }
    std.debug.print("HUD: {d} resource states captured, with every prompt device, the secondary set and the bind picker\n", .{studies.len});
    promptRoom(g);
}

const PROMPT_GAP_MIN: i32 = 4;

fn promptRoom(g: *const game.Game) void {
    var least: i32 = std.math.maxInt(i32);
    for (std.enums.values(input.Device)) |d| {
        const st = input.State{ .device = d, .modifier = g.bar.modifier };
        for (skillbar.SLOTS[0 .. skillbar.SLOTS.len - 1], skillbar.SLOTS[1..], game.SLOT_XS[0 .. game.SLOT_XS.len - 1], game.SLOT_XS[1..]) |a, b, xa, xb| {
            const wa = look.Prompt.of(&st, a).width(&g.face, game.PROMPT_PX);
            const wb = look.Prompt.of(&st, b).width(&g.face, game.PROMPT_PX);
            least = @min(least, xb - xa - @divTrunc(wa + wb, 2));
        }
    }
    std.debug.print("slot prompts: {d} px apart at the closest\n", .{least});
    std.debug.assert(least >= PROMPT_GAP_MIN);
}

const POSE_BURST = P{ .x = 25, .y = 15 };
const POSE_ZAP = fx.Zap{ .from = .{ 27.5, 20.5 }, .to = .{ 29.5, 20.5 } };
pub const MIDNIGHT: f32 = 0;
const LATE_NIGHT: f32 = day.SUNRISE - 2;
const DAWN: f32 = day.SUNRISE + 1;
const BLEAK_MORNING: f32 = day.SUNRISE + 2.5;
const MORNING: f32 = day.SUNRISE + 3;
const AFTERNOON: f32 = day.SUNSET - 3.5;
const EVENING: f32 = day.SUNSET - 3;
const DUSK: f32 = day.SUNSET - 0.7;
pub const LATE_DUSK: f32 = day.SUNSET - 0.5;
const EARLY_NIGHT: f32 = day.SUNSET + 2;
const NIGHT: f32 = day.SUNSET + 2.5;
const POSE_GAS_TURNS: usize = 3;

fn posePicker(g: *game.Game, u: game.Use) void {
    game.openBinds(g);
    g.binds.row = game.rowAt(u.set);
    g.binds.col = game.Binds.colOf(u.by);
    var kit_buf: skillbar.KitBuf = undefined;
    g.binds.openPick(g.growth.kit(g.class, &kit_buf), &g.bar);
}

fn poseFright(g: *game.Game) void {
    const hero = P{ .x = 20, .y = 20 };
    game.harness.arena(g, hero, &.{.{ .x = 23, .y = 20 }});
    const pibs = [fx.FRIGHT_WORDS.len]P{ .{ .x = 23, .y = 17 }, .{ .x = 26, .y = 19 }, .{ .x = 26, .y = 22 }, .{ .x = 21, .y = 23 } };
    var slots: [pibs.len]usize = undefined;
    for (pibs, &slots) |p, *s| s.* = actor.Pool.slot(game.harness.spawnAt(g, .pib, p, false));
    game.settle(g);
    const wait: f32 = 0.2;
    game.combat.wound(g, 2, .{ .dmg = actor.row(.rat).hp }, SHOOT, .{ .from = hero, .wait = wait });
    g.lead = wait;
    game.combat.endTurn(g);
    g.st = .{};
    game.update(g, 0);
    for (0..18) |_| game.update(g, mathx.FRAME_DT);
    for (slots, 0..) |s, i| g.fx.speech[s].word = i;
}

fn speechLeft(g: *const game.Game) f32 {
    var most: f32 = 0;
    for (g.fx.speech[0..g.pool.n]) |s| most = @max(most, s.life);
    return most;
}

fn poseGas(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 23, .y = 16 }, &.{.{ .x = 24, .y = 15 }});
    game.harness.wallRow(&g.lv, 10, 13, 31);
    game.harness.wallRow(&g.lv, 21, 13, 31);
    game.harness.wallIn(&g.lv, .{ .x = 13, .y = 10 }, .{ .x = 13, .y = 21 });
    game.harness.wallIn(&g.lv, .{ .x = 31, .y = 10 }, .{ .x = 31, .y = POSE_BURST.y - 1 });
    game.harness.wallIn(&g.lv, .{ .x = 31, .y = POSE_BURST.y + 1 }, .{ .x = 31, .y = 21 });
    g.lv.addTorch(.{ .x = 22, .y = 10 });
    _ = g.pool.spawn(&g.lv, actor.Actor.of(.bloat, .{ .x = 16, .y = 12 }));
    _ = g.pool.spawn(&g.lv, actor.Actor.of(.bloat, .{ .x = 26, .y = 14 }));
    g.lv.putBarrel(.{ .x = 26, .y = 16 });
    g.lv.set(.{ .x = 24, .y = 14 }, .chest);
    g.lv.set(.{ .x = 25, .y = 17 }, .boulder);
    game.harness.wallIn(&g.lv, .{ .x = 28, .y = 13 }, .{ .x = 28, .y = 17 });
    g.lv.addGas(POSE_BURST, gas.BURST);
    for (0..POSE_GAS_TURNS) |_| gas.turn(&g.lv, &g.rng);
    posed(g, false);
}

const POSE_TORCH = P{ .x = 20, .y = 10 };

const Wader = struct { kind: actor.Kind, at: P };

const WADERS = [_]Wader{
    .{ .kind = .rat, .at = .{ .x = 23, .y = 20 } },
    .{ .kind = .bloat, .at = .{ .x = 26, .y = 20 } },
    .{ .kind = .pib, .at = .{ .x = 20, .y = 23 } },
    .{ .kind = .beefy_pib, .at = .{ .x = 28, .y = 23 } },
    .{ .kind = .slime, .at = .{ .x = 23, .y = 23 } },
    .{ .kind = .slime_half, .at = .{ .x = 26, .y = 23 } },
    .{ .kind = .slime_quarter, .at = .{ .x = 23, .y = 17 } },
    .{ .kind = .wizard, .at = .{ .x = 20, .y = 17 } },
    .{ .kind = .knight, .at = .{ .x = 26, .y = 17 } },
};

comptime {
    var seen = std.EnumSet(actor.Kind).initOne(HERO);
    for (WADERS) |w| {
        std.debug.assert(!seen.contains(w.kind));
        seen.insert(w.kind);
    }
    std.debug.assert(seen.count() == std.enums.values(actor.Kind).len);
}

fn poseWaterSteps(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    game.harness.grassOver(&g.lv);
    var cells = grid.Cells.of(.{ .x = 17, .y = 15 }, .{ .x = 30, .y = 26 });
    while (cells.next()) |p| g.lv.set(p, if (p.x < 19) .water else .shallows);
    for (WADERS) |w| _ = game.harness.spawnAt(g, w.kind, w.at, false);
    game.settle(g);
    g.st = .{};
    for (g.pool.slice(), 0..) |a, i| {
        const to = a.at.add(mathx.Dir.e.delta());
        g.pool.move(&g.lv, actor.Pool.idOf(i), to);
        g.glide[i] = g.glide[i].toward(to, g.glide[i].span() * (game.SPLASH_AT + 0.01));
    }
    game.update(g, 0);
    game.update(g, 0.055);
}

fn poseWaterMirrors(g: *game.Game, hour: f32, outdoors: bool) void {
    game.harness.arena(g, .{ .x = 24, .y = 20 }, &.{.{ .x = 27, .y = 21 }});
    game.harness.grassOver(&g.lv);
    var cells = grid.Cells.of(.{ .x = 17, .y = 18 }, .{ .x = 33, .y = 26 });
    while (cells.next()) |p| g.lv.set(p, if (p.y >= 23) .water else .shallows);
    for ([_]i32{ 19, 20, 21, 28, 29 }) |x| g.lv.set(.{ .x = x, .y = 17 }, .shrub);
    g.lv.set(.{ .x = 31, .y = 20 }, .boulder);
    g.lv.putBarrel(.{ .x = 21, .y = 21 });
    _ = game.harness.spawnAt(g, .wizard, .{ .x = 25, .y = 23 }, false);
    _ = game.harness.spawnAt(g, .slime, .{ .x = 29, .y = 22 }, false);
    game.harness.wallRow(&g.lv, 17, 23, 26);
    g.lv.addTorch(.{ .x = 24, .y = 17 });
    studyLit(g, outdoors, hour);
}

fn poseForest(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 24, .y = 18 }, &.{});
    game.harness.grassOver(&g.lv);
    const rows = [_][]const u8{
        "...................",
        ".#####...####......",
        ".#...#...####..#...",
        ".#...#...####......",
        ".#.......#.....#...",
        ".#####...###.......",
        ".............#.....",
        ".#..#..#..#..#..#..",
        "...................",
    };
    for (rows, 0..) |row, y| {
        for (row, 0..) |ch, x| {
            if (ch == '#') g.lv.set(.{ .x = 16 + @as(i32, @intCast(x)), .y = 12 + @as(i32, @intCast(y)) }, .shrub);
        }
    }
    posed(g, g.outdoors);
}

fn poseShadowStudy(g: *game.Game, hour: f32, outdoors: bool) void {
    game.harness.arena(g, .{ .x = 24, .y = 21 }, &.{.{ .x = 29, .y = 22 }});
    game.harness.grassOver(&g.lv);
    game.harness.wallRow(&g.lv, 16, 22, 26);
    if (!outdoors) g.lv.addTorch(.{ .x = 24, .y = 16 });
    const props = [_]struct { t: grid.Tile, p: P }{
        .{ .t = .wall, .p = .{ .x = 16, .y = 19 } },
        .{ .t = .wall, .p = .{ .x = 17, .y = 19 } },
        .{ .t = .rock, .p = .{ .x = 20, .y = 19 } },
        .{ .t = .shrub, .p = .{ .x = 23, .y = 19 } },
        .{ .t = .shrub, .p = .{ .x = 24, .y = 19 } },
        .{ .t = .shrub, .p = .{ .x = 25, .y = 19 } },
        .{ .t = .boulder, .p = .{ .x = 28, .y = 19 } },
        .{ .t = .fungus, .p = .{ .x = 31, .y = 19 } },
        .{ .t = .shrub, .p = .{ .x = 16, .y = 23 } },
        .{ .t = .shrub, .p = .{ .x = 19, .y = 23 } },
        .{ .t = .tiny_shrub, .p = .{ .x = 22, .y = 23 } },
        .{ .t = .tall_grass, .p = .{ .x = 24, .y = 24 } },
        .{ .t = .shrooms, .p = .{ .x = 26, .y = 23 } },
        .{ .t = .fence, .p = .{ .x = 17, .y = 16 } },
        .{ .t = .grave, .p = .{ .x = 20, .y = 16 } },
        .{ .t = .reeds, .p = .{ .x = 28, .y = 16 } },
        .{ .t = .crop, .p = .{ .x = 31, .y = 16 } },
    };
    for (props) |prop| g.lv.set(prop.p, prop.t);
    g.lv.putBarrel(.{ .x = 32, .y = 23 });
    _ = game.harness.spawnAt(g, .slime, .{ .x = 31, .y = 22 }, false);
    studyLit(g, outdoors, hour);
}

fn studyLit(g: *game.Game, outdoors: bool, hour: f32) void {
    studyAt(g, outdoors, hour);
    @memset(&g.lv.seen, true);
    @memset(&g.lv.lit, true);
    g.light.settle(&g.lv);
}

fn studyAt(g: *game.Game, outdoors: bool, hour: f32) void {
    g.clock = day.Clock.at(hour);
    posed(g, outdoors);
}

fn posed(g: *game.Game, outdoors: bool) void {
    g.outdoors = outdoors;
    gen.shapeWalls(&g.lv);
    game.settle(g);
}

fn poseTorch(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 20, .y = 15 }, &.{ .{ .x = 17, .y = 12 }, .{ .x = 23, .y = 13 } });
    game.harness.wallRow(&g.lv, POSE_TORCH.y, 12, 28);
    g.lv.set(.{ .x = 22, .y = 12 }, .wall);
    g.lv.addTorch(POSE_TORCH);
    posed(g, false);
}

const HIDDEN_SHADOW_X: i32 = 27;
const Hidden = enum { forest, tree, barrel, actor };
const HIDDEN_SHADOW_ROWS = std.EnumArray(Hidden, i32).init(.{ .forest = 14, .tree = 17, .barrel = 20, .actor = 23 });

fn poseHiddenShadows(g: *game.Game, hour: ?f32) void {
    const x = HIDDEN_SHADOW_X;
    const row = HIDDEN_SHADOW_ROWS;
    game.harness.arena(g, .{ .x = 22, .y = 19 }, &.{.{ .x = x, .y = row.get(.actor) }});
    game.harness.grassOver(&g.lv);
    g.lv.set(.{ .x = x, .y = row.get(.forest) }, .shrub);
    g.lv.set(.{ .x = x, .y = row.get(.forest) + 1 }, .shrub);
    g.lv.set(.{ .x = x, .y = row.get(.tree) }, .shrub);
    g.lv.putBarrel(.{ .x = x, .y = row.get(.barrel) });
    if (hour == null) {
        game.harness.wallRow(&g.lv, 12, 29, 31);
        g.lv.addTorch(.{ .x = 30, .y = 12 });
        game.harness.wallRow(&g.lv, 18, 29, 31);
        g.lv.addTorch(.{ .x = 30, .y = 18 });
    }
    studyAt(g, hour != null, hour orelse day.NOON);
    for (0..grid.CELLS) |i| {
        const visible = grid.Level.of(i).x < x;
        g.lv.seen[i] = visible;
        g.lv.lit[i] = visible;
    }
    g.light.settle(&g.lv);
}

fn waterSample(g: *game.Game, target: rl.RenderTexture2D, beds: *const dual.Beds, view: ?look.WaterView, origin: [2]f32) !rl.Image {
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    g.sprites.drawGround(beds, origin, game.CELL_F, view);
    rl.endTextureMode();
    return readTarget(target);
}

fn shootWater(g: *game.Game, target: rl.RenderTexture2D) !void {
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/water-reflections");
    g.st = .{};
    const FRAMES = 40;
    const EVERY = 6;
    const before = g.light.t.at();
    const minute = g.clock;
    for (0..FRAMES) |i| {
        for (0..EVERY) |_| game.update(g, mathx.FRAME_DT);
        var path: [80]u8 = undefined;
        try capture(g, target, try std.fmt.bufPrintZ(&path, SHOTS_DIR ++ "/water-reflections/{d:0>2}.png", .{i}));
    }
    const elapsed = g.light.t.at() - before;
    if (elapsed < FRAMES * EVERY * mathx.FRAME_DT - 0.01 or !std.meta.eql(minute, g.clock)) return error.WaterIdleClock;
    std.debug.print("water reflections idle play: {d:.2} seconds in {d} rendered frames, no turn spent\n", .{ elapsed, FRAMES });
}

const CAMERA_SHIFT = P{ .x = 16, .y = 8 };

fn checkWaterSurface(g: *game.Game) !void {
    const BANDS = [_]grid.Tile{ .water, .shallows, .grass };
    const DRY = comptime std.mem.indexOfScalar(grid.Tile, &BANDS, .grass).?;
    const BAND = 4;
    const ROWS = 2;
    const Band = struct {
        fn of(x: i32) ?usize {
            const in_band = @mod(x, BAND * game.CELL);
            if (in_band < game.HALF_CELL or in_band >= BAND * game.CELL - game.HALF_CELL) return null;
            return @intCast(@divTrunc(x, BAND * game.CELL));
        }
    };
    const width = BANDS.len * BAND * game.CELL;
    const height = ROWS * game.CELL;
    const target = try rl.loadRenderTexture(width, height);
    defer rl.unloadRenderTexture(target);
    const mirror = try rl.loadRenderTexture(width, height);
    defer rl.unloadRenderTexture(mirror);
    rl.beginTextureMode(mirror);
    rl.clearBackground(look.rgb(0x1010ff));
    rl.drawRectangle(0, game.CELL, width, game.CELL, look.rgb(0xff1010));
    rl.endTextureMode();
    var lv = grid.Level.blank();
    for (&lv.tile, 0..) |*t, i| {
        const x: usize = @intCast(grid.Level.of(i).x);
        t.* = BANDS[@min(x / BAND, BANDS.len - 1)];
    }
    var beds: dual.Beds = undefined;
    beds.fill(&lv, .{ .x = 0, .y = 0 }, .{ .x = BANDS.len * BAND, .y = ROWS }, false);
    var sight: [grid.CELLS]rl.Color = @splat(.{ .r = 128, .g = 128, .b = 128, .a = 0 });
    for (sight[0..grid.COLS]) |*pixel| pixel.a = 255;
    const visibility = look.clamped(look.rgba(&sight, grid.W, grid.H), .point) orelse return error.WaterVisibilityMissing;
    defer rl.unloadTexture(visibility);
    const gleam = look.canvas(grid.W, grid.H, look.rgb(0x302010), .point) orelse return error.WaterGlintsMissing;
    defer rl.unloadTexture(gleam);
    const dark = look.canvas(1, 1, rl.Color.black, .point) orelse return error.WaterGlintsMissing;
    defer rl.unloadTexture(dark);
    const blank = look.canvas(1, 1, rl.Color.blank, .point) orelse return error.WaterMirrorMissing;
    defer rl.unloadTexture(blank);
    const plain = try waterSample(g, target, &beds, null, .{ 0, 0 });
    defer rl.unloadImage(plain);
    var view = look.WaterView{ .screen = .{ width, height }, .visibility = visibility, .glints = dark };
    const still = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(still);
    view.glints = gleam;
    const first = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(first);
    if (!rl.exportImage(first, SHOTS_DIR ++ "/water-glints.png")) return error.ExportFailed;
    view.glints = dark;
    view.mirror = .{ .live = mirror.texture, .memory = blank };
    const second = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(second);
    if (!rl.exportImage(second, SHOTS_DIR ++ "/water-mirror-mask.png")) return error.ExportFailed;
    var glinted = [_]usize{0} ** BANDS.len;
    var reflected = [_]usize{0} ** BANDS.len;
    var fixed: usize = 0;
    {
        var px = pixels(width, height);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const base = rl.getImageColor(plain, x, y);
            if (!std.meta.eql(base, rl.getImageColor(still, x, y))) return error.WaterSurfaceChanged;
            const a = rl.getImageColor(first, x, y);
            const b = rl.getImageColor(second, x, y);
            if (a.a != base.a or b.a != base.a) return error.WaterAlphaChanged;
            const band = Band.of(x) orelse continue;
            if (y >= game.CELL or band == DRY) {
                if (!std.meta.eql(base, a) or !std.meta.eql(base, b)) return error.WaterOutsideSurface;
                fixed += 1;
            } else {
                if (!std.meta.eql(base, a)) glinted[band] += 1;
                if (!std.meta.eql(base, b)) {
                    if (b.b <= b.r) return error.WaterMirrorUpsideDown;
                    reflected[band] += 1;
                }
            }
        }
    }
    for (0..DRY) |i| {
        if (glinted[i] < MIN_PIXELS or reflected[i] < MIN_PIXELS) return error.WaterReflectionMissing;
    }
    view.mirror = .{ .live = blank, .memory = mirror.texture };
    const memory = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(memory);
    var remembered = [_]usize{0} ** BANDS.len;
    {
        var px = pixels(width, height);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const base = rl.getImageColor(plain, x, y);
            const m = rl.getImageColor(memory, x, y);
            if (m.a != base.a) return error.WaterAlphaChanged;
            const band = Band.of(x) orelse continue;
            if (y < game.CELL or band == DRY) {
                if (!std.meta.eql(base, m)) return error.WaterOutsideSurface;
            } else if (!std.meta.eql(base, m)) {
                if (@as(i32, m.r) - base.r <= @as(i32, m.b) - base.b) return error.WaterMirrorUpsideDown;
                remembered[band] += 1;
            }
        }
    }
    for (remembered[0..DRY]) |count| {
        if (count < MIN_PIXELS) return error.WaterMemoryMissing;
    }
    view.glints = gleam;
    view.mirror = null;
    const shift = CAMERA_SHIFT;
    const shifted = try waterSample(g, target, &beds, view, .{ -shift.x, -shift.y });
    defer rl.unloadImage(shifted);
    var compared: usize = 0;
    {
        var px = pixels(width - shift.x, height - shift.y);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const a = rl.getImageColor(first, x + shift.x, y + shift.y);
            const b = rl.getImageColor(shifted, x, y);
            if (@abs(@as(i32, a.r) - b.r) > 1 or @abs(@as(i32, a.g) - b.g) > 1 or @abs(@as(i32, a.b) - b.b) > 1 or a.a != b.a) return error.WaterMovesWithCamera;
            compared += 1;
        }
    }
    std.debug.print("smooth water GPU: glints {d}/{d}, live mirrors {d}/{d}, remembered mirrors {d}/{d}; {d} grass/memory pixels exclude live effects, {d} camera samples agree; static art and alpha preserved\n", .{ glinted[0], glinted[1], reflected[0], reflected[1], remembered[0], remembered[1], fixed, compared });
}

fn checkMapEdge(g: *game.Game, target: rl.RenderTexture2D) !void {
    game.harness.arena(g, .{ .x = 24, .y = grid.H - 4 }, &.{});
    game.harness.grassOver(&g.lv);
    for (0..grid.W) |x| g.lv.set(.{ .x = @intCast(x), .y = grid.H - 1 }, .grass);
    studyLit(g, true, day.NOON);
    const edge = @divTrunc(g.screen.y, 2);
    g.cam.y = @floatFromInt(game.MAP_PX.y - edge);
    game.prepare(g);
    var compared: usize = 0;
    for ([_]bool{ true, false }) |visible| {
        @memset(&g.lv.lit, visible);
        g.light.settle(&g.lv);
        intoTarget(g, target);
        rl.clearBackground(look.FOG);
        game.scene.drawMap(g);
        outOfTarget(g);
        try exportTarget(target, if (visible) SHOTS_DIR ++ "/map-bottom-edge.png" else SHOTS_DIR ++ "/map-bottom-memory.png");
        const img = try readTarget(target);
        defer rl.unloadImage(img);
        {
            var px = grid.Cells.of(.{ .x = 0, .y = edge }, .{ .x = g.screen.x, .y = edge + game.CELL });
            while (px.next()) |q| {
                const x = q.x;
                const y = q.y;
                const pixel = rl.getImageColor(img, x, y);
                if (!sameRgb(pixel, look.FOG)) return error.MapEdgeOverhang;
                compared += 1;
            }
        }
    }
    std.debug.print("map bottom GPU: {d} pixels beyond lit and remembered terrain stay clear\n", .{compared});
}

fn checkWaterMirrors(g: *game.Game, target: rl.RenderTexture2D) !void {
    const original = try readTarget(g.sprites.mirror orelse return error.WaterMirrorMissing);
    defer rl.unloadImage(original);
    const camera = g.cam;
    const shift = CAMERA_SHIFT;
    g.cam.x += @floatFromInt(shift.x);
    g.cam.y += @floatFromInt(shift.y);
    drawInto(g, target);
    const moved = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(moved);
    var compared: usize = 0;
    var reflected: usize = 0;
    {
        var px = pixels(original.width - shift.x, original.height - shift.y);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const a = rl.getImageColor(original, x + shift.x, y + shift.y);
            const b = rl.getImageColor(moved, x, y);
            if (a.a > 0) reflected += 1;
            if (!std.meta.eql(a, b)) return error.WaterMirrorCameraDrift;
            compared += 1;
        }
    }
    if (reflected < MIN_PIXELS) return error.WaterMirrorEmpty;
    g.cam = camera;
    @memset(&g.lv.lit, false);
    g.light.settle(&g.lv);
    try capture(g, target, SHOTS_DIR ++ "/water-mirrors-memory.png");
    const memory = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(memory);
    const dim = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(dim);
    const actors = g.pool.n;
    g.pool.n = 0;
    defer g.pool.n = actors;
    drawInto(g, target);
    const empty = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(empty);
    var remembered: usize = 0;
    {
        var px = pixels(memory.width, memory.height);
        while (px.next()) |p| {
            if (rl.getImageColor(memory, p.x, p.y).a > 0) remembered += 1;
            if (!std.meta.eql(rl.getImageColor(dim, p.x, p.y), rl.getImageColor(empty, p.x, p.y))) return error.WaterMirrorRevealsHidden;
        }
    }
    if (remembered < MIN_PIXELS) return error.WaterMemoryMissing;
    try checkRememberedBarrels(g, target, memory);
    @memset(&g.lv.seen, false);
    g.light.settle(&g.lv);
    intoTarget(g, target);
    const c = game.scene.Cam.of(g);
    var flame_buf: [grid.MAX_TORCHES]light.Flame = undefined;
    _ = game.scene.drawMirrors(g, c, game.scene.viewBox(g, c), &.{}, g.light.flames(&g.lv, &flame_buf));
    outOfTarget(g);
    for ([_]rl.RenderTexture2D{ g.sprites.mirror.?, g.sprites.mirror_memory.? }) |t| {
        const hidden = try readTarget(t);
        defer rl.unloadImage(hidden);
        {
            var px = pixels(hidden.width, hidden.height);
            while (px.next()) |p| {
                if (rl.getImageColor(hidden, p.x, p.y).a != 0) return error.WaterMirrorRevealsHidden;
            }
        }
    }
    std.debug.print("water mirror GPU: {d} live and {d} remembered pixels; {d} camera samples agree; hidden bodies and unexplored scenery absent\n", .{ reflected, remembered, compared });
}

fn checkRememberedBarrels(g: *game.Game, target: rl.RenderTexture2D, before: rl.Image) !void {
    const barrels = g.lv.barrel;
    const remembered = g.lv.barrel_seen;
    defer {
        g.lv.barrel = barrels;
        g.lv.barrel_seen = remembered;
        g.art_ready = false;
    }
    @memset(&g.lv.barrel, false);
    g.art_ready = false;
    try capture(g, target, SHOTS_DIR ++ "/water-mirrors-broken-remembered.png");
    const broken = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(broken);
    @memset(&g.lv.barrel_seen, false);
    g.art_ready = false;
    drawInto(g, target);
    const forgotten = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(forgotten);
    var kept: usize = 0;
    var px = pixels(before.width, before.height);
    while (px.next()) |p| {
        const a = rl.getImageColor(before, p.x, p.y);
        const b = rl.getImageColor(broken, p.x, p.y);
        if (!std.meta.eql(a, b)) return error.WaterMirrorForgetsUnseenBarrel;
        if (!std.meta.eql(b, rl.getImageColor(forgotten, p.x, p.y))) kept += 1;
    }
    if (kept < MIN_PIXELS) return error.WaterBarrelMemoryMissing;
    std.debug.print("remembered barrel GPU: {d} reflection pixels survive unseen destruction and clear with memory\n", .{kept});
}

fn checkHiddenShadowMask(g: *game.Game, target: rl.RenderTexture2D, visible: bool) !void {
    game.prepare(g);
    const c = game.scene.Cam.of(g);
    const view = game.scene.viewBox(g, c);
    g.light.bake(&g.lv, view.lo, view.hi);
    {
        rl.beginTextureMode(target);
        defer rl.endTextureMode();
        rl.clearBackground(rl.Color.white);
        if (!game.scene.shadowPass(g, c, view, target.id)) return error.ShadowShaderMissing;
    }
    const img = try readTarget(target);
    defer rl.unloadImage(img);
    var hits = std.EnumArray(Hidden, usize).initFill(0);
    var leaked: usize = 0;
    {
        var px = pixels(g.screen.x, g.screen.y);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const rgb = rl.getImageColor(img, x, y);
            if (rgb.r >= 252 and rgb.g >= 252 and rgb.b >= 252) continue;
            const map_x = x + c.x;
            const map_y = y + c.y;
            if (!visible or map_x >= (HIDDEN_SHADOW_X + 1) * game.CELL) leaked += 1;
            if (map_x < (HIDDEN_SHADOW_X - 2) * game.CELL or map_x >= HIDDEN_SHADOW_X * game.CELL) continue;
            for (std.enums.values(Hidden)) |k| {
                const row = HIDDEN_SHADOW_ROWS.get(k);
                if (map_y >= (row - 1) * game.CELL and map_y < (row + 2) * game.CELL) hits.getPtr(k).* += 1;
            }
        }
    }
    std.debug.print("hidden shadow GPU check ({s}):", .{if (visible) "sight" else "memory"});
    for (std.enums.values(Hidden)) |k| std.debug.print(" {s} {d}", .{ @tagName(k), hits.get(k) });
    std.debug.print(" pixels; {d} outside visible ground\n", .{leaked});
    if (leaked != 0) return error.ShadowOutsideSight;
    if (visible) for (hits.values) |hit| {
        if (hit == 0) return error.HiddenShadowMissing;
    };
}

fn drawInto(g: *game.Game, target: rl.RenderTexture2D) void {
    game.prepare(g);
    intoTarget(g, target);
    defer outOfTarget(g);
    game.drawFrame(g);
}

fn intoTarget(g: *game.Game, target: rl.RenderTexture2D) void {
    rl.beginTextureMode(target);
    g.framebuffer = target.id;
}

fn outOfTarget(g: *game.Game) void {
    rl.endTextureMode();
    g.framebuffer = 0;
}

const OVERVIEW_CELL: i32 = 10;
const OVERVIEW_MID: i32 = @divTrunc(OVERVIEW_CELL, 2);
/// A glyph a little bigger than its cell, so the font's side bearings leave no gaps.
const OVERVIEW_INK: i32 = OVERVIEW_CELL + 2;
const SHOT_BIOME = "qud/qud_salt_marsh";
/// Warm up rain so the Strand capture includes both drops and splashes.
const RAIN_FRAMES: usize = 90;
const SHOT_OUTDOOR = "wilds";
const SHOT_HOURS = [_]struct { hour: f32, path: [:0]const u8 }{
    .{ .hour = DAWN, .path = SHOTS_DIR ++ "/dawn.png" },
    .{ .hour = day.NOON, .path = SHOTS_DIR ++ "/noon.png" },
    .{ .hour = AFTERNOON, .path = SHOTS_DIR ++ "/day.png" },
    .{ .hour = DUSK, .path = SHOTS_DIR ++ "/dusk.png" },
    .{ .hour = EARLY_NIGHT, .path = SHOTS_DIR ++ "/early-night.png" },
    .{ .hour = day.DEAD_OF_NIGHT, .path = SHOTS_DIR ++ "/night.png" },
    .{ .hour = LATE_NIGHT, .path = SHOTS_DIR ++ "/late-night.png" },
};

fn overviews(g: *game.Game, w: *atlas.Atlas) !void {
    const target = try rl.loadRenderTexture(grid.W * OVERVIEW_CELL, grid.H * OVERVIEW_CELL);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_MAPS);
    var list = atlas.Listing{};
    list.scanAll();
    for (0..list.n) |i| {
        try w.load(std.heap.c_allocator, list.at(i));
        w.node[w.start.node].stamp(&g.lv, SHOT_SEED +% i);
        rl.beginTextureMode(target);
        rl.clearBackground(look.BG);
        for (0..grid.CELLS) |k| {
            const p = grid.Level.of(k);
            const t = g.lv.tile[k];
            const x = p.x * OVERVIEW_CELL;
            const y = p.y * OVERVIEW_CELL;
            const under = t.ground() orelse t;
            if (look.tileBg(under)) |bg| rl.drawRectangle(x, y, OVERVIEW_CELL, OVERVIEW_CELL, bg);
            const cx = x + OVERVIEW_MID;
            const cy = y + OVERVIEW_MID;
            if (look.Mark.of(&g.lv, k)) |m| {
                g.face.glyph(m.look().ch, cx, cy, OVERVIEW_INK, m.look().fg);
            } else look.inkTile(&g.face, t, cx, cy, OVERVIEW_INK);
        }
        for (g.lv.torches()) |t| g.face.glyph(look.TORCH.ch, t.x * OVERVIEW_CELL + OVERVIEW_MID, t.y * OVERVIEW_CELL + OVERVIEW_MID, OVERVIEW_INK, look.TORCH.fg);
        rl.endTextureMode();
        var buf: [atlas.PATH_MAX + 32]u8 = undefined;
        const name = try std.fmt.bufPrintZ(&buf, SHOTS_MAPS ++ "/{s}.png", .{list.stem(i)});
        try exportTarget(target, name);
    }
}

/// Milliseconds a frame takes to draw, over `n` frames after `warm` unmeasured.
fn meanDraw(g: *game.Game, target: rl.RenderTexture2D, warm: usize, n: usize) !f64 {
    for (0..warm) |_| drawInto(g, target);
    var timer = try std.time.Timer.start();
    for (0..n) |_| drawInto(g, target);
    return ms(timer.read() / n);
}

/// The fewest pixels a shot check counts as an effect drawn at all.
const MIN_PIXELS = 100;

fn sameRgb(a: rl.Color, b: rl.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b;
}

/// Draws into `target`, whose batch raylib flushes at `endTextureMode`, and saves it.
fn capture(g: *game.Game, target: rl.RenderTexture2D, path: [:0]const u8) !void {
    drawInto(g, target);
    try exportTarget(target, path);
}

/// The target's pixels, top row first; the caller unloads it.
fn readTarget(target: rl.RenderTexture2D) !rl.Image {
    var img = try rl.loadImageFromTexture(target.texture);
    rl.imageFlipVertical(&img);
    return img;
}

pub fn exportTarget(target: rl.RenderTexture2D, path: [:0]const u8) !void {
    errdefer std.debug.print("{s} FAILED\n", .{path});
    var img = try readTarget(target);
    defer rl.unloadImage(img);
    // Blending leaves alpha in the target that a window never shows.
    rl.imageFormat(&img, .uncompressed_r8g8b8);
    if (!rl.exportImage(img, path)) return error.ExportFailed;
    std.debug.print("{s} written\n", .{path});
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
        const was = g.heroActor().?.at;
        t.reset();
        game.harness.walkFrame(g, dt, d);
        sim[i] = t.lap();
        drawInto(g, target);
        draw[i] = t.read();
        const tried = g.st.walk != null and g.pending == null;
        if (tried and g.heroActor() != null and g.heroActor().?.at.eq(was)) d = rng.pick(mathx.Dir, mathx.ALL_DIRS);
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
}

fn benchEffects(g: *game.Game, target: rl.RenderTexture2D) !void {
    poseGas(g);
    for ([_]usize{ 0, 8, 32 }) |count| {
        g.fx.clear();
        for (0..count) |i| {
            const at = mathx.centre(.{ .x = 15 + @as(i32, @intCast(i % 8)), .y = 14 + @as(i32, @intCast(i / 8)) });
            g.fx.glow(at, look.FIRE, .{ .radius = fx.EMBER_GLOW.radius, .gain = fx.EMBER_GLOW.gain, .life = 1 });
        }
        std.debug.print("effects {d}: {d:.3} ms mean draw over {d} frames\n", .{ count, try meanDraw(g, target, 1, BENCH_DRAWS), BENCH_DRAWS });
    }
}

fn benchAssets(g: *game.Game) !void {
    const alloc = std.heap.c_allocator;
    const w = try alloc.create(atlas.Atlas);
    defer alloc.destroy(w);
    defer g.map = null;
    inline for ([_][]const u8{ SHOT_OUTDOOR, SHOT_BIOME, SHOT_OUTDOOR }) |name| {
        try w.load(alloc, atlas.mapPath(name));
        game.beginMapAt(g, w, w.start, SHOT_SEED);
        var t = try std.time.Timer.start();
        game.prepare(g);
        const loaded = t.read();
        if (!std.meta.eql(game.mapAssets(g), g.sprites.resident())) return error.MissingMapAsset;
        const held = g.sprites;
        g.art_ready = false;
        t.reset();
        game.prepare(g);
        const reused = t.read();
        if (!std.meta.eql(held, g.sprites)) return error.ReloadedMapAsset;
        std.debug.print("assets {s}: {d} textures, {d:.3} ms; unchanged map {d:.3} ms, all textures reused\n", .{ name, g.sprites.count(), ms(loaded), ms(reused) });
    }
}

const POSE_NEAR: i32 = 3;
const POSE_FAR: i32 = 5;

fn poseRat(g: *game.Game) void {
    const h = g.heroActor() orelse return;
    const rat = for (g.pool.slice(), 0..) |a, i| {
        if (a.kind == .rat) break actor.Pool.idOf(i);
    } else return;
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        const d = mathx.dist(p, h.at);
        if (d < POSE_NEAR or d > POSE_FAR or !bow.aimable(&g.lv, h.at, p) or g.lv.taken(p)) continue;
        g.pool.move(&g.lv, rat, p);
        break;
    }
    game.combat.wound(g, rat, .{ .dmg = bow.BASE.lo }, SHOOT, .{ .from = h.at, .wait = 0 });
    game.settle(g);
}
