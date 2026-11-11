const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const gen = @import("../../map/gen.zig");
const carve = @import("../../map/carve.zig");
const gas = @import("../../map/gas.zig");
const fire = @import("../../map/fire.zig");
const atlas = @import("../../map/atlas.zig");
const listing = @import("../../map/listing.zig");
const playground = @import("../../map/playground.zig");
const procgen = @import("../../map/procgen.zig");
const editor = @import("../../edit/editor.zig");
const menu = @import("../../ui/menu.zig");
const heroes = @import("../../play/hero.zig");
const naming = @import("../../ui/naming.zig");
const actor = @import("../../play/actor.zig");
const bow = @import("../../play/bow.zig");
const juke = @import("../../play/juke.zig");
const skillbar = @import("../../play/skillbar.zig");
const look = @import("../../gfx/look.zig");
const fx = @import("../../gfx/fx.zig");
const sky = @import("../../gfx/sky.zig");
const day = @import("../../map/day.zig");
const climate = @import("../../map/climate.zig");
const game = @import("../../game.zig");
const skills = @import("../skills.zig");
const binds = @import("../binds.zig");

const P = mathx.P;
const CONFIRM = menu.CONFIRM;
const HERO = actor.HERO;
const SHOTS_DIR = @import("capture.zig").SHOTS_DIR;
const SHOTS_MAPS = @import("capture.zig").SHOTS_MAPS;
const SHOT_BIOME = @import("capture.zig").SHOT_BIOME;
const SHOT_OUTDOOR = @import("capture.zig").SHOT_OUTDOOR;
const SHOT_SEED = @import("capture.zig").SHOT_SEED;
const capture = @import("capture.zig").capture;
const dropAtlas = @import("capture.zig").dropAtlas;
const exportTarget = @import("capture.zig").exportTarget;
const heapAtlas = @import("capture.zig").heapAtlas;
const pixels = @import("capture.zig").pixels;
const readTarget = @import("capture.zig").readTarget;
const renderTarget = @import("capture.zig").renderTarget;
const captureWater = @import("water_cliffs.zig").captureWater;
const checkMapEdge = @import("water_cliffs.zig").checkMapEdge;
const checkWaterMirrors = @import("water_cliffs.zig").checkWaterMirrors;
const checkWaterSurface = @import("water_cliffs.zig").checkWaterSurface;
const captureCharacter = @import("ui.zig").captureCharacter;
const captureHud = @import("ui.zig").captureHud;
const captureLevelUp = @import("ui.zig").captureLevelUp;
const captureLoot = @import("ui.zig").captureLoot;
const captureRares = @import("ui.zig").captureRares;
const captureCinemaScene = @import("cinema.zig").captureCinemaScene;
const cinemaWater = @import("cinema.zig").cinemaWater;

fn captureCrossbowman(g: *game.Game, target: rl.RenderTexture2D) !void {
    const h = game.harness;
    h.arena(g, .{ .x = 21, .y = 20 }, &.{ .{ .x = 25, .y = 19 }, .{ .x = 26, .y = 21 } });
    h.grassOver(&g.sim.lv);
    const id = h.spawnAt(g, .bandit_crossbowman, .{ .x = 26, .y = 20 }, true);
    const slot = actor.Pool.slot(id);
    game.settle(g);
    g.pic.turnToward(.fromInt(id), -1);
    try capture(g, target, SHOTS_DIR ++ "/bandit-crossbowman-pack.png");
    g.sim.rng = h.foeAttacksRng(g, &.{.{ .id = id, .lands = true }});
    h.use(g, .wait);
    const hp_after_shot = g.sim.heroActor().?.hp;
    const shot = g.pic.foe_shots[slot] orelse return error.CrossbowmanDidNotShoot;
    g.st = .{};
    game.update(g, -shot.t + shot.lands() / 2);
    try capture(g, target, SHOTS_DIR ++ "/bandit-crossbowman-arrow.png");
    h.drawnOut(g);
    if (g.sim.heroActor().?.hp != hp_after_shot) return error.CrossbowmanIdleDamage;
    const retreat = actor.row(.bandit_crossbowman).ranged.?.retreat;
    g.sim.pool.move(&g.sim.lv, g.sim.hero, .{ .x = 26 - retreat, .y = 20 });
    game.settle(g);
    h.use(g, .wait);
    if (mathx.dist(g.sim.pool.get(id).?.at, g.sim.heroActor().?.at) != retreat + 1) return error.CrossbowmanDidNotRetreat;
    h.drawnOut(g);
    try capture(g, target, SHOTS_DIR ++ "/bandit-crossbowman-retreat.png");
}

pub fn captureGeneral(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_DIR);

    game.begin(g, SHOT_SEED);
    poseRat(g);
    g.st.lean = true;
    try capture(g, target, SHOTS_DIR ++ "/lean.png");

    g.st.lean = false;
    skills.openAim(g, game.harness.boundTo(g, .shoot).by, .shoot);
    try capture(g, target, SHOTS_DIR ++ "/aim.png");

    g.mode = .play;
    poseTorch(g);
    try capture(g, target, SHOTS_DIR ++ "/torch.png");

    posePicker(g, game.harness.boundTo(g, .shoot));
    try capture(g, target, SHOTS_DIR ++ "/bind.png");

    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    game.harness.grassOver(&g.sim.lv);
    const chest_at = P{ .x = 21, .y = 20 };
    g.sim.lv.set(chest_at, .chest);
    g.sim.lv.putBarrel(.{ .x = 23, .y = 20 });
    game.settle(g);
    try capture(g, target, SHOTS_DIR ++ "/chest-closed.png");
    game.heroStep(g, .e, 0);
    game.harness.drawnOut(g);
    if (g.sim.lv.at(chest_at) != .chest_open or g.sim.ground.coin_n != 1 or g.sim.gold != 0 or g.mode != .play) return error.ChestUnopened;
    try capture(g, target, SHOTS_DIR ++ "/chest-open.png");
    game.heroStep(g, .e, 0);
    game.harness.drawnOut(g);
    if (g.sim.ground.coin_n != 1 or g.sim.gold != 0 or g.character.page != .loot) return error.ChestLootUnopened;
    try capture(g, target, SHOTS_DIR ++ "/chest-loot.png");
    game.character.characterCommand(g, .close);

    game.harness.arena(g, .{ .x = 20, .y = 15 }, &.{.{ .x = 25, .y = 14 }});
    g.sim.lv.set(.{ .x = 21, .y = 15 }, .water);
    _ = g.sim.pool.damage(&g.sim.lv, g.sim.hero, 6);
    game.settle(g);
    skills.openLeap(g, game.harness.boundTo(g, .juke).by, .juke);
    g.mode.aim.mark = .{ .x = 20 + juke.RANGE, .y = 15 };
    try capture(g, target, SHOTS_DIR ++ "/juke-aim.png");
    skills.confirmAim(g);
    g.st = .{};
    game.update(g, 0.06);
    try capture(g, target, SHOTS_DIR ++ "/juke.png");

    game.harness.arena(g, .{ .x = 20, .y = 15 }, &.{});
    _ = game.harness.spawnAt(g, .slime, .{ .x = 28, .y = 15 }, false);
    game.settle(g);
    g.sim.rng = game.harness.procRng(g, .burning_arrow, 1, true);
    skills.useSkill(g, game.harness.boundTo(g, .burning_arrow));
    try capture(g, target, SHOTS_DIR ++ "/burning-aim.png");
    skills.confirmAim(g);
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
    g.sim.rng = game.harness.procRng(g, .glacial_shot, 3, true);
    skills.useSkill(g, game.harness.boundTo(g, .glacial_shot));
    try capture(g, target, SHOTS_DIR ++ "/glacial-aim.png");
    skills.confirmAim(g);
    g.st = .{};
    game.update(g, 0.05);
    try capture(g, target, SHOTS_DIR ++ "/glacial-arrow.png");
    game.update(g, 0.14);
    try capture(g, target, SHOTS_DIR ++ "/glacial.png");
    game.harness.drawnOut(g);
    posePicker(g, game.harness.boundTo(g, .glacial_shot));
    try capture(g, target, SHOTS_DIR ++ "/glacial-bind.png");

    try captureEffects(g, target);
    try captureCrossbowman(g, target);
    try capturePlayground(g, target);

    poseFright(g);
    if (speechLeft(g) <= fx.SPEECH_FADE_S) return error.FrightUnspoken;
    try capture(g, target, SHOTS_DIR ++ "/pib-fright.png");
    game.update(g, speechLeft(g) - fx.SPEECH_FADE_S / 2);
    try capture(g, target, SHOTS_DIR ++ "/pib-fright-fade.png");

    poseGas(g);
    try capture(g, target, SHOTS_DIR ++ "/gas.png");
    g.cloud.clear();
    try capture(g, target, SHOTS_DIR ++ "/gas-clear.png");
    g.cloud.settle(&g.sim.lv);

    game.character.openPause(g);
    try capture(g, target, SHOTS_DIR ++ "/pause.png");
    g.pause_menu.at = game.rowAt(game.PauseRow.debug);
    game.harness.press(g, CONFIRM);
    try capture(g, target, SHOTS_DIR ++ "/debug.png");
    g.mode = .play;

    poseSteps(g, .shallows);
    try capture(g, target, SHOTS_DIR ++ "/water-steps.png");
    poseSteps(g, .dirt);
    try capture(g, target, SHOTS_DIR ++ "/dirt-steps.png");

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

    poseBridges(g);
    try capture(g, target, SHOTS_DIR ++ "/bridges.png");

    poseForest(g);
    try capture(g, target, SHOTS_DIR ++ "/forest.png");
    studyAt(g, true, MORNING);
    try captureCinemaScene(g, target, "forest");
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
    for ([_]struct { hour: f32, name: [:0]const u8 }{
        .{ .hour = MORNING, .name = SHOTS_DIR ++ "/glowbulb-morning.png" },
        .{ .hour = day.NOON, .name = SHOTS_DIR ++ "/glowbulb-noon.png" },
        .{ .hour = DUSK, .name = SHOTS_DIR ++ "/glowbulb-dusk.png" },
        .{ .hour = day.DEAD_OF_NIGHT, .name = SHOTS_DIR ++ "/glowbulb-night.png" },
    }) |study| {
        poseGlowbulbs(g);
        studyAt(g, true, study.hour);
        try capture(g, target, study.name);
    }
    for ([_]struct { hour: ?f32, path: [:0]const u8 }{
        .{ .hour = MORNING, .path = SHOTS_DIR ++ "/shadows-hidden-sun.png" },
        .{ .hour = NIGHT, .path = SHOTS_DIR ++ "/shadows-hidden-moon.png" },
        .{ .hour = null, .path = SHOTS_DIR ++ "/shadows-hidden-torch.png" },
    }) |study| {
        poseHiddenShadows(g, study.hour);
        try checkHiddenShadowMask(g, target, true);
        try capture(g, target, study.path);
        @memset(&g.sim.lv.lit, false);
        @memset(&g.sim.lv.seen, true);
        g.light.settle(&g.sim.lv);
        try checkHiddenShadowMask(g, target, false);
    }
    poseHiddenShadows(g, MORNING);
    g.cam.x = @floatFromInt(HIDDEN_SHADOW_X * game.CELL - g.screen.x);
    try checkHiddenShadowMask(g, target, true);
    try capture(g, target, SHOTS_DIR ++ "/shadows-offscreen.png");

    try captureHud(g);

    try captureLevelUp(g);

    {
        const w = try heapAtlas();
        defer dropAtlas(g, w);
        try overviews(g, w);
        {
            try w.load(std.heap.c_allocator, atlas.mapPath(SHOT_BIOME));
            game.beginMapAt(g, w, w.start, SHOT_SEED);
            try capture(g, target, SHOTS_DIR ++ "/biome.png");
        }
        {
            try loadStrand(g, w);
            try capture(g, target, SHOTS_DIR ++ "/strand.png");
            try captureCinemaScene(g, target, "strand");
            const seen = g.sim.lv.seen;
            const lit = g.sim.lv.lit;
            game.scene.toggleReveal(g);
            try capture(g, target, SHOTS_DIR ++ "/map-revealed.png");
            game.scene.toggleReveal(g);
            if (!std.mem.eql(bool, &seen, &g.sim.lv.seen) or !std.mem.eql(bool, &lit, &g.sim.lv.lit)) return error.RevealChangedSight;
            try checkWaterSurface(g);
            try captureWater(g, target);
        }
        {
            try w.load(std.heap.c_allocator, atlas.mapPath(SHOT_OUTDOOR));
            for (SHOT_HOURS) |s| {
                game.beginMapAt(g, w, w.start, SHOT_SEED);
                g.sim.lv.seen = @splat(false);
                g.sim.clock = day.Clock.at(s.hour);
                game.settle(g);
                try capture(g, target, s.path);
            }
            inline for ([_]f32{ BLEAK_MORNING, day.NOON, DUSK, day.DEAD_OF_NIGHT }) |hour| {
                game.beginMapAt(g, w, w.start, SHOT_SEED);
                g.sim.clock = day.Clock.at(hour);
                game.settle(g);
                g.light.sky = sky.under(hour, climate.Light.bleak.overcast());
                try capture(g, target, SHOTS_DIR ++ "/bleak-" ++ std.fmt.comptimePrint("{d:.1}", .{hour}) ++ ".png");
            }
            g.sim.clock = day.Clock.at(day.NOON);
            game.settle(g);
            g.sim.clock = day.Clock.at(day.DEAD_OF_NIGHT);
            game.settle(g);
            try capture(g, target, SHOTS_DIR ++ "/night-memory.png");
        }
        game.begin(g, SHOT_SEED);
    }

    try editor.capture(g, target, SHOTS_DIR ++ "/edit.png", SHOTS_DIR ++ "/edit-graph.png", SHOTS_DIR ++ "/edit-gen.png", SHOTS_DIR ++ "/edit-objects.png");
    try captureCharacter(g);
    try captureRares(g);
    try captureLoot(g);

    const entry = naming.Entry{ .name = heroes.Name.of("Arwen"), .row = 2, .col = 4 };
    rl.beginTextureMode(target);
    rl.clearBackground(look.BG);
    var title: [naming.TITLE_MAX]u8 = undefined;
    naming.draw(&entry, g.face, g.screen, naming.titleOf(heroes.DEFAULT, &title), .xbox);
    rl.endTextureMode();
    try exportTarget(target, SHOTS_DIR ++ "/name.png");
}

pub fn loadStrand(g: *game.Game, w: *atlas.Atlas) !void {
    try w.load(std.heap.c_allocator, atlas.START);
    game.beginMapAt(g, w, w.start, SHOT_SEED);
    for (0..RAIN_FRAMES) |_| game.update(g, mathx.FRAME_DT);
}

fn capturePlayground(g: *game.Game, target: rl.RenderTexture2D) !void {
    const w = try heapAtlas();
    defer dropAtlas(g, w);
    defer g.sim.playground = false;
    game.enterPlayground(g, w);
    const Pose = struct { patch: grid.Tile, name: [:0]const u8, fading: ?[:0]const u8 = null };
    for ([_]Pose{
        .{ .patch = .glow_plant, .name = SHOTS_DIR ++ "/playground-glowbulbs.png" },
        .{ .patch = .floor, .name = SHOTS_DIR ++ "/playground-torches.png" },
        .{ .patch = .reeds, .name = SHOTS_DIR ++ "/playground-reeds-burning.png", .fading = SHOTS_DIR ++ "/playground-reeds-fading.png" },
        .{ .patch = .grass, .name = SHOTS_DIR ++ "/playground-grass-burning.png", .fading = SHOTS_DIR ++ "/playground-grass-fading.png" },
    }) |pose| {
        const box = if (pose.patch == .floor) null else playground.boxOf(playground.indexOf(.{ .tile = pose.patch }));
        const at = if (box) |b| b.lo.add(.{ .x = -1, .y = 1 }) else playground.HERO;
        game.beginMapAt(g, w, .{ .node = 0, .at = at }, SHOT_SEED);
        if (pose.fading != null) {
            var cells = box.?.cells();
            while (cells.next()) |p| fire.lay(&g.sim.lv, p, 1, 0);
            game.settle(g);
        }
        try capture(g, target, pose.name);
        const fading = pose.fading orelse continue;
        const mid = grid.Level.idx(box.?.lo.add(.{ .x = 0, .y = 1 }));
        game.harness.useAct(g, .wait);
        var waited: f32 = 0;
        while (g.pic.fadingBurnt(mid) == null) : (waited += 0.01) {
            if (waited > 3) return error.BurntUnfaded;
            g.pic.advance(&g.sim, 0.01);
        }
        g.pic.advance(&g.sim, game.presentation.EMBER_S * 0.4);
        try capture(g, target, fading);
    }
}

fn captureEffects(g: *game.Game, target: rl.RenderTexture2D) !void {
    try captureArrows();
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
        carve.box(&g.sim.lv, .{ .lo = .{ .x = 13, .y = 13 }, .hi = .{ .x = 33, .y = 28 } }, .grass);
        game.harness.wallRow(&g.sim.lv, 17, 18, 29);
        procgen.reshape(&g.sim.lv);
        for ([_]P{ .{ .x = 23, .y = 20 }, .{ .x = 24, .y = 19 }, .{ .x = 24, .y = 21 }, .{ .x = 22, .y = 21 } }) |at| _ = game.harness.spawnAt(g, .slime, at, false);
        game.harness.toughenFoes(g);
        g.sim.clock = day.Clock.at(day.DEAD_OF_NIGHT);
        game.settle(g);
        const directory = SHOTS_DIR ++ "/fx-" ++ @tagName(act);
        try std.fs.cwd().makePath(directory);
        try capture(g, target, directory ++ "/before.png");
        skills.useSkill(g, game.harness.boundTo(g, act));
        if (act.reticle()) |reticle| {
            g.mode.aim.mark = if (reticle == .leap) .{ .x = 22, .y = 20 } else .{ .x = 23, .y = 20 };
            skills.confirmAim(g);
        }
        g.st = .{};
        var previous: f32 = 0;
        inline for ([_]f32{ 0.012, 0.028, 0.05, 0.09, 0.16, 0.26 }, 0..) |t, i| {
            game.update(g, t - previous);
            previous = t;
            try capture(g, target, directory ++ "/" ++ std.fmt.comptimePrint("{d}", .{i}) ++ ".png");
        }
    }
    g.sim.class = heroes.DEFAULT;
    g.bar = skillbar.Bar.of(g.sim.class);
}

fn captureArrows() !void {
    const target = try rl.loadRenderTexture(640, 320);
    defer rl.unloadRenderTexture(target);
    rl.beginTextureMode(target);
    rl.clearBackground(look.FOG);
    for ([_]f32{ 1, 2 }, 0..) |scale, row| {
        for (0..16) |i| {
            const angle = @as(f32, @floatFromInt(i)) * std.math.tau / 16;
            const dir = [2]f32{ @cos(angle), @sin(angle) };
            const x = 40 + @as(f32, @floatFromInt(i % 8)) * 80;
            const y = 40 + @as(f32, @floatFromInt(row * 2 + i / 8)) * 80;
            fx.drawArrow(.{ .x = x + dir[0] * 8 * scale, .y = y + dir[1] * 8 * scale }, dir, look.arrowInk(.shoot), .{ 0, 0 }, scale);
        }
    }
    rl.endTextureMode();
    try exportTarget(target, SHOTS_DIR ++ "/arrow-directions.png");
}

const POSE_BURST = P{ .x = 25, .y = 15 };

pub const POSE_ZAP = fx.Zap{ .from = .{ 27.5, 20.5 }, .to = .{ 29.5, 20.5 } };

const LATE_NIGHT: f32 = day.SUNRISE - 2;
const DAWN: f32 = day.SUNRISE + 1;
const BLEAK_MORNING: f32 = day.SUNRISE + 2.5;
pub const MORNING: f32 = day.SUNRISE + 3;
const AFTERNOON: f32 = day.SUNSET - 3.5;
pub const EVENING: f32 = day.SUNSET - 3;
const DUSK: f32 = day.SUNSET - 0.7;
const EARLY_NIGHT: f32 = day.SUNSET + 2;
pub const NIGHT: f32 = day.SUNSET + 2.5;
const POSE_GAS_TURNS: usize = 3;

pub fn posePicker(g: *game.Game, u: skills.Use) void {
    binds.openBinds(g);
    g.binds.row = game.rowAt(u.set);
    g.binds.col = binds.Binds.colOf(u.by.?);
    var kit_buf: skillbar.KitBuf = undefined;
    g.binds.openPick(g.sim.growth.kit(g.sim.class, &kit_buf), &g.bar);
}

fn poseFright(g: *game.Game) void {
    const hero = P{ .x = 20, .y = 20 };
    game.harness.arena(g, hero, &.{.{ .x = 23, .y = 20 }});
    const pibs = [fx.FRIGHT_WORDS.len]P{ .{ .x = 23, .y = 17 }, .{ .x = 26, .y = 19 }, .{ .x = 26, .y = 22 }, .{ .x = 21, .y = 23 } };
    var slots: [pibs.len]usize = undefined;
    for (pibs, &slots) |p, *s| s.* = actor.Pool.slot(game.harness.spawnAt(g, .pib, p, false));
    game.settle(g);
    const wait: f32 = 0.2;
    game.combat.wound(g, game.harness.foeId(0), .{ .dmg = actor.row(.rat).hp }, game.combat.SHOOT, .{ .from = hero, .wait = wait });
    g.pic.lead = wait;
    game.combat.endTurn(g);
    g.st = .{};
    game.update(g, 0);
    for (0..18) |_| game.update(g, mathx.FRAME_DT);
    for (slots, 0..) |s, i| g.pic.fx.speech[s].word = i;
}

fn speechLeft(g: *const game.Game) f32 {
    var most: f32 = 0;
    for (g.pic.fx.speech[0..g.sim.pool.n]) |s| most = @max(most, s.life);
    return most;
}

pub fn poseGas(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 23, .y = 16 }, &.{.{ .x = 24, .y = 15 }});
    game.harness.wallRow(&g.sim.lv, 10, 13, 31);
    game.harness.wallRow(&g.sim.lv, 21, 13, 31);
    game.harness.wallIn(&g.sim.lv, .{ .x = 13, .y = 10 }, .{ .x = 13, .y = 21 });
    game.harness.wallIn(&g.sim.lv, .{ .x = 31, .y = 10 }, .{ .x = 31, .y = POSE_BURST.y - 1 });
    game.harness.wallIn(&g.sim.lv, .{ .x = 31, .y = POSE_BURST.y + 1 }, .{ .x = 31, .y = 21 });
    g.sim.lv.addTorch(.{ .x = 22, .y = 10 });
    _ = game.harness.spawnAt(g, .bloat, .{ .x = 16, .y = 12 }, false);
    _ = game.harness.spawnAt(g, .bloat, .{ .x = 26, .y = 14 }, false);
    g.sim.lv.putBarrel(.{ .x = 26, .y = 16 });
    g.sim.lv.set(.{ .x = 24, .y = 14 }, .chest);
    g.sim.lv.set(.{ .x = 25, .y = 17 }, .boulder);
    game.harness.wallIn(&g.sim.lv, .{ .x = 28, .y = 13 }, .{ .x = 28, .y = 17 });
    g.sim.lv.addGas(POSE_BURST, gas.BURST);
    for (0..POSE_GAS_TURNS) |_| gas.turn(&g.sim.lv, &g.sim.rng);
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
    .{ .kind = .bandit_crossbowman, .at = .{ .x = 28, .y = 17 } },
    .{ .kind = .bandit_netter, .at = .{ .x = 20, .y = 15 } },
    .{ .kind = .bandit_shieldbearer, .at = .{ .x = 23, .y = 15 } },
    .{ .kind = .frost_wisp, .at = .{ .x = 26, .y = 15 } },
    .{ .kind = .pyre_bloat, .at = .{ .x = 28, .y = 15 } },
    .{ .kind = .pib_shaman, .at = .{ .x = 23, .y = 25 } },
    .{ .kind = .mimic, .at = .{ .x = 26, .y = 25 } },
    .{ .kind = .bog_leech, .at = .{ .x = 19, .y = 21 } },
    .{ .kind = .skeleton, .at = .{ .x = 28, .y = 20 } },
    .{ .kind = .goblin, .at = .{ .x = 20, .y = 25 } },
    .{ .kind = .caravan_guard, .at = .{ .x = 28, .y = 25 } },
};

comptime {
    var seen = std.EnumSet(actor.Kind).initOne(HERO);
    for (WADERS) |w| {
        std.debug.assert(!seen.contains(w.kind));
        seen.insert(w.kind);
    }
    std.debug.assert(seen.count() == std.enums.values(actor.Kind).len);
}

fn poseSteps(g: *game.Game, tile: grid.Tile) void {
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    game.harness.grassOver(&g.sim.lv);
    var cells = grid.Cells.of(.{ .x = 17, .y = 15 }, .{ .x = 30, .y = 26 });
    while (cells.next()) |p| g.sim.lv.set(p, if (p.x < 19) .water else tile);
    for (WADERS) |w| g.sim.pool.get(game.harness.spawnAt(g, w.kind, w.at, false)).?.unmask(&g.sim.lv);
    game.settle(g);
    g.st = .{};
    for (g.sim.pool.slice(), 0..) |a, i| {
        const to = a.at.add(mathx.Dir.e.delta());
        g.sim.pool.move(&g.sim.lv, actor.Pool.idOf(i), to);
        g.pic.glide[i] = g.pic.glide[i].toward(to, g.pic.glide[i].span() * (game.presentation.STEP_AT + 0.01));
    }
    game.update(g, 0);
    game.update(g, 0.055);
}

pub fn poseWaterMirrors(g: *game.Game, hour: f32, outdoors: bool) void {
    game.harness.arena(g, .{ .x = 24, .y = 20 }, &.{.{ .x = 27, .y = 21 }});
    game.harness.grassOver(&g.sim.lv);
    var cells = grid.Cells.of(.{ .x = 17, .y = 18 }, .{ .x = 33, .y = 26 });
    while (cells.next()) |p| g.sim.lv.set(p, if (p.y >= 23) .water else .shallows);
    for ([_]i32{ 19, 20, 21, 28, 29 }) |x| g.sim.lv.set(.{ .x = x, .y = 17 }, .shrub);
    g.sim.lv.set(.{ .x = 31, .y = 20 }, .boulder);
    g.sim.lv.putBarrel(.{ .x = 21, .y = 21 });
    _ = game.harness.spawnAt(g, .wizard, .{ .x = 25, .y = 23 }, false);
    _ = game.harness.spawnAt(g, .slime, .{ .x = 29, .y = 22 }, false);
    game.harness.wallRow(&g.sim.lv, 17, 23, 26);
    g.sim.lv.addTorch(.{ .x = 24, .y = 17 });
    studyLit(g, outdoors, hour);
}

pub fn poseForest(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 24, .y = 18 }, &.{});
    game.harness.grassOver(&g.sim.lv);
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
    stampRows(&g.sim.lv, .{ .x = 16, .y = 12 }, &rows, struct {
        fn of(ch: u8) ?grid.Tile {
            return if (ch == '#') .shrub else null;
        }
    }.of);
    posed(g, g.sim.outdoors);
}

pub fn stampRows(lv: *grid.Level, origin: P, rows: []const []const u8, comptime tileOf: fn (u8) ?grid.Tile) void {
    for (rows, 0..) |row, y| for (row, 0..) |ch, x| {
        if (tileOf(ch)) |t| lv.set(origin.add(.{ .x = @intCast(x), .y = @intCast(y) }), t);
    };
}

fn poseBridges(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 28, .y = 18 }, &.{});
    game.harness.grassOver(&g.sim.lv);
    const rows = [_][]const u8{
        "..=....==...===.....",
        "ss=ssss==sss===sssss",
        "~~=~~~~==~~~===~~~~~",
        "~~=~~~~==~~~===~~~~~",
        "~~=~~~~==~~~========",
        "~~=~~~~==~~~===~~~~~",
        "~~=~~~~==~~~===~~~~~",
        "ss=ssss==sss===sssss",
        "..=....==...===.....",
    };
    stampRows(&g.sim.lv, .{ .x = 15, .y = 14 }, &rows, struct {
        fn of(ch: u8) ?grid.Tile {
            return switch (ch) {
                '=' => .bridge,
                '~' => .water,
                's' => .shallows,
                else => null,
            };
        }
    }.of);
    studyAt(g, true, day.NOON);
}

fn poseShadowStudy(g: *game.Game, hour: f32, outdoors: bool) void {
    game.harness.arena(g, .{ .x = 24, .y = 21 }, &.{.{ .x = 29, .y = 22 }});
    game.harness.grassOver(&g.sim.lv);
    game.harness.wallRow(&g.sim.lv, 16, 22, 26);
    if (!outdoors) g.sim.lv.addTorch(.{ .x = 24, .y = 16 });
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
    for (props) |prop| g.sim.lv.set(prop.p, prop.t);
    g.sim.lv.putBarrel(.{ .x = 32, .y = 23 });
    _ = game.harness.spawnAt(g, .slime, .{ .x = 31, .y = 22 }, false);
    studyLit(g, outdoors, hour);
}

pub fn studyLit(g: *game.Game, outdoors: bool, hour: f32) void {
    studyAt(g, outdoors, hour);
    @memset(&g.sim.lv.seen, true);
    @memset(&g.sim.lv.lit, true);
    g.light.settle(&g.sim.lv);
}

fn poseGlowbulbs(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 24, .y = 21 }, &.{});
    game.harness.grassOver(&g.sim.lv);
    for ([_]P{ .{ .x = 22, .y = 19 }, .{ .x = 27, .y = 20 }, .{ .x = 25, .y = 23 } }) |p| g.sim.lv.set(p, .glow_plant);
}

pub fn studyAt(g: *game.Game, outdoors: bool, hour: f32) void {
    g.sim.clock = day.Clock.at(hour);
    posed(g, outdoors);
}

fn posed(g: *game.Game, outdoors: bool) void {
    g.sim.outdoors = outdoors;
    gen.shapeWalls(&g.sim.lv);
    game.settle(g);
}

fn poseTorch(g: *game.Game) void {
    game.harness.arena(g, .{ .x = 20, .y = 15 }, &.{ .{ .x = 17, .y = 12 }, .{ .x = 23, .y = 13 } });
    game.harness.wallRow(&g.sim.lv, POSE_TORCH.y, 12, 28);
    g.sim.lv.set(.{ .x = 22, .y = 12 }, .wall);
    g.sim.lv.addTorch(POSE_TORCH);
    posed(g, false);
}

const HIDDEN_SHADOW_X: i32 = 27;

const Hidden = enum { forest, tree, barrel, actor };

const HIDDEN_SHADOW_ROWS = std.EnumArray(Hidden, i32).init(.{ .forest = 14, .tree = 17, .barrel = 20, .actor = 23 });

fn poseHiddenShadows(g: *game.Game, hour: ?f32) void {
    const x = HIDDEN_SHADOW_X;
    const row = HIDDEN_SHADOW_ROWS;
    game.harness.arena(g, .{ .x = 22, .y = 19 }, &.{.{ .x = x, .y = row.get(.actor) }});
    game.harness.grassOver(&g.sim.lv);
    g.sim.lv.set(.{ .x = x, .y = row.get(.forest) }, .shrub);
    g.sim.lv.set(.{ .x = x, .y = row.get(.forest) + 1 }, .shrub);
    g.sim.lv.set(.{ .x = x, .y = row.get(.tree) }, .shrub);
    g.sim.lv.putBarrel(.{ .x = x, .y = row.get(.barrel) });
    if (hour == null) {
        game.harness.wallRow(&g.sim.lv, 12, 29, 31);
        g.sim.lv.addTorch(.{ .x = 30, .y = 12 });
        game.harness.wallRow(&g.sim.lv, 18, 29, 31);
        g.sim.lv.addTorch(.{ .x = 30, .y = 18 });
    }
    studyAt(g, hour != null, hour orelse day.NOON);
    for (0..grid.CELLS) |i| {
        const visible = grid.Level.of(i).x < x;
        g.sim.lv.seen[i] = visible;
        g.sim.lv.lit[i] = visible;
    }
    g.light.settle(&g.sim.lv);
}

pub fn shadowMask(g: *game.Game, target: rl.RenderTexture2D, c: game.scene.Cam, cast: grid.Box) !rl.Image {
    {
        rl.beginTextureMode(target);
        defer rl.endTextureMode();
        rl.clearBackground(rl.Color.white);
        if (!game.scene.shadowPass(g, c, g.pic.groundShown(&g.sim), cast, &game.scene.bagCells(g), target.id)) return error.ShadowShaderMissing;
    }
    return readTarget(target);
}

fn checkHiddenShadowMask(g: *game.Game, target: rl.RenderTexture2D, visible: bool) !void {
    game.prepare(g);
    const c = game.scene.Cam.of(g);
    const view = game.scene.viewBox(g, c);
    g.light.bake(&g.sim.lv, view.lo, view.hi);
    const img = try shadowMask(g, target, c, view);
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

const OVERVIEW_CELL: i32 = 10;
const OVERVIEW_MID: i32 = @divTrunc(OVERVIEW_CELL, 2);

/// A glyph a little bigger than its cell, so the font's side bearings leave no gaps.
const OVERVIEW_INK: i32 = OVERVIEW_CELL + 2;

/// Warm up rain so the Strand capture includes both drops and splashes.
const RAIN_FRAMES: usize = 90;

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
    var list = listing.Listing{};
    list.scanAll();
    for (0..list.n) |i| {
        try w.load(std.heap.c_allocator, list.at(i));
        w.node[w.start.node].stamp(&g.sim.lv, SHOT_SEED +% i);
        rl.beginTextureMode(target);
        rl.clearBackground(look.BG);
        for (0..grid.CELLS) |k| {
            const p = grid.Level.of(k);
            const t = g.sim.lv.tile[k];
            const x = p.x * OVERVIEW_CELL;
            const y = p.y * OVERVIEW_CELL;
            const under = t.ground() orelse t;
            if (look.tileBg(under)) |bg| rl.drawRectangle(x, y, OVERVIEW_CELL, OVERVIEW_CELL, bg);
            const cx = x + OVERVIEW_MID;
            const cy = y + OVERVIEW_MID;
            if (look.Mark.of(&g.sim.lv, k)) |m| {
                g.face.glyph(m.look().ch, cx, cy, OVERVIEW_INK, m.look().fg);
            } else look.inkTile(&g.face, t, cx, cy, OVERVIEW_INK);
        }
        for (g.sim.lv.torches()) |t| g.face.glyph(look.TORCH.ch, t.x * OVERVIEW_CELL + OVERVIEW_MID, t.y * OVERVIEW_CELL + OVERVIEW_MID, OVERVIEW_INK, look.TORCH.fg);
        rl.endTextureMode();
        var buf: [listing.PATH_MAX + 32]u8 = undefined;
        const name = try overviewPath(&buf, list.at(i));
        try std.fs.cwd().makePath(std.fs.path.dirname(name).?);
        try exportTarget(target, name);
    }
}

fn overviewPath(buf: []u8, map: []const u8) ![:0]const u8 {
    return std.fmt.bufPrintZ(buf, SHOTS_MAPS ++ "/{s}/overview.png", .{map[atlas.PREFIX.len..]});
}

test "map overview paths preserve folders with repeated map names" {
    const paths = [_][]const u8{ "main", "foo", "a/foo", "b/foo", "a/deeper/foo", "foo.png/bar" };
    inline for (paths) |path| {
        var buf: [listing.PATH_MAX + 32]u8 = undefined;
        try std.testing.expectEqualStrings(SHOTS_MAPS ++ "/" ++ path ++ atlas.EXT ++ "/overview.png", try overviewPath(&buf, atlas.PREFIX ++ path ++ atlas.EXT));
    }
}

const POSE_NEAR: i32 = 3;
const POSE_FAR: i32 = 5;

fn poseRat(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    const rat = for (g.sim.pool.slice(), 0..) |a, i| {
        if (a.kind == .rat) break actor.Pool.idOf(i);
    } else return;
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        const d = mathx.dist(p, h.at);
        if (d < POSE_NEAR or d > POSE_FAR or !bow.aimable(&g.sim.lv, h.at, p, bow.RANGE) or g.sim.lv.taken(p)) continue;
        g.sim.pool.move(&g.sim.lv, rat, p);
        break;
    }
    game.combat.wound(g, rat, .{ .dmg = bow.BASE.lo }, game.combat.SHOOT, .{ .from = h.at, .wait = 0 });
    game.settle(g);
}
