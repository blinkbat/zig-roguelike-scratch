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
const listing = @import("../map/listing.zig");
const spar = @import("../map/spar.zig");
const procgen = @import("../map/procgen.zig");
const app = @import("../app.zig");
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
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const dual = @import("../gfx/ground.zig");
const light = @import("../gfx/light.zig");
const fx = @import("../gfx/fx.zig");
const cinema = @import("../gfx/cinema.zig");
const sky = @import("../gfx/sky.zig");
const day = @import("../map/day.zig");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const binds = @import("binds.zig");
const P = mathx.P;
const CONFIRM = menu.CONFIRM;
const SHOOT = bow.VERB;
const HERO = actor.HERO;
const SHOT_SEED: u64 = 0x5EED_1234;
const SHOTS_DIR = "shots";
const SHOTS_MAPS = SHOTS_DIR ++ "/maps";

fn shootCrossbowman(g: *game.Game, target: rl.RenderTexture2D) !void {
    const h = game.harness;
    h.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 19 }, .{ .x = 26, .y = 21 } });
    h.grassOver(&g.sim.lv);
    const id = h.spawnAt(g, .bandit_crossbowman, .{ .x = 26, .y = 20 }, true);
    const slot = actor.Pool.slot(id);
    game.settle(g);
    g.pic.turnToward(id, -1);
    try capture(g, target, SHOTS_DIR ++ "/bandit-crossbowman-pack.png");
    g.sim.rng = h.bitesRng(g, .bandit_crossbowman, &.{true});
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

fn renderTarget(g: *game.Game) !rl.RenderTexture2D {
    return rl.loadRenderTexture(g.screen.x, g.screen.y);
}

fn target720(g: *game.Game) !rl.RenderTexture2D {
    g.screen = game.SCREEN_720;
    return renderTarget(g);
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
    g.mark = .{ .x = 20 + juke.RANGE, .y = 15 };
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

    try shootEffects(g, target);
    try shootCrossbowman(g, target);

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
        @memset(&g.sim.lv.lit, false);
        @memset(&g.sim.lv.seen, true);
        g.light.settle(&g.sim.lv);
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
            const seen = g.sim.lv.seen;
            const lit = g.sim.lv.lit;
            game.character.toggleReveal(g);
            try capture(g, target, SHOTS_DIR ++ "/map-revealed.png");
            game.character.toggleReveal(g);
            if (!std.mem.eql(bool, &seen, &g.sim.lv.seen) or !std.mem.eql(bool, &lit, &g.sim.lv.lit)) return error.RevealChangedSight;
            try checkWaterSurface(g);
            try shootWater(g, target);
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
                g.light.sky = sky.under(hour, .bleak);
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

    try editor.shoot(g, target, SHOTS_DIR ++ "/edit.png", SHOTS_DIR ++ "/edit-graph.png", SHOTS_DIR ++ "/edit-gen.png", SHOTS_DIR ++ "/edit-objects.png");
    try shootCharacter(g);
    try shootRares(g);
    try shootLoot(g);

    const entry = naming.Entry{ .name = heroes.Name.of("Arwen"), .row = 2, .col = 4 };
    rl.beginTextureMode(target);
    rl.clearBackground(look.BG);
    var title: [naming.TITLE_MAX]u8 = undefined;
    naming.draw(&entry, g.face, g.screen, naming.titleOf(heroes.DEFAULT, &title), .xbox);
    rl.endTextureMode();
    try exportTarget(target, SHOTS_DIR ++ "/name.png");
}

pub fn shootEditor(g: *game.Game) !void {
    const screen = g.screen;
    defer g.screen = screen;
    for (@import("../core/window.zig").SCREENS) |size| {
        g.screen = size;
        const target = try renderTarget(g);
        defer rl.unloadRenderTexture(target);
        var dir_buf: [128]u8 = undefined;
        const dir = try std.fmt.bufPrint(&dir_buf, SHOTS_DIR ++ "/editor-{d}x{d}", .{ size.x, size.y });
        try std.fs.cwd().makePath(dir);
        var paths: [4][256]u8 = undefined;
        try editor.shoot(g, target,
            try std.fmt.bufPrintZ(&paths[0], "{s}/edit.png", .{dir}),
            try std.fmt.bufPrintZ(&paths[1], "{s}/edit-graph.png", .{dir}),
            try std.fmt.bufPrintZ(&paths[2], "{s}/edit-gen.png", .{dir}),
            try std.fmt.bufPrintZ(&paths[3], "{s}/edit-objects.png", .{dir}));
    }
}

pub fn shootUi(g: *game.Game) !void {
    try shootTactics(g);
    try std.fs.cwd().makePath(SHOTS_DIR);
    try book.verifyCards(&g.face);
    try book.verifyStats(&g.face);
    try shootCharacter(g);
    try shootRares(g);
    try shootLoot(g);
    try shootHud(g);
    try shootLevelUp(g);
    try shootMouse(g);
    try app.shootHeroes(g);
}

fn shootRares(g: *game.Game) !void {
    const screen = g.screen;
    defer g.screen = screen;
    game.harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{});
    const crusher = items.Item{ .kind = .axe, .rare_name = .{ .first = .Spine, .last = .Crusher }, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .physical_damage, .value = 20 }, .{ .kind = .crit, .value = 5 }, .{ .kind = .life_on_kill, .value = 2 } } };
    const maw = items.Item{ .kind = .ring, .rare_name = .{ .first = .Void, .last = .Maw }, .mods = .{ .{ .kind = .dexterity, .value = 3 }, .{ .kind = .resistance, .value = 20, .element = .chaos }, .{ .kind = .mana, .value = 3 }, .{ .kind = .spoils, .value = 25 } } };
    const fold = items.Item{ .kind = .robes, .rare_name = .{ .first = .Magus, .last = .Fold }, .mods = .{ .{ .kind = .intelligence, .value = 3 }, .{ .kind = .armour, .value = 4 }, .{ .kind = .life, .value = 6 }, .{ .kind = .mana, .value = 3 } } };
    g.sim.inventory = .{};
    if (!g.sim.inventory.add(crusher) or !g.sim.inventory.add(fold)) return error.InventoryFull;
    g.sim.inventory.gear.slots.set(.left_ring, maw);
    if (!g.sim.ground.add(.{ .item = maw, .at = g.sim.heroActor().?.at })) return error.GroundFull;
    game.syncStats(g);
    game.harness.drawnOut(g);
    inline for (.{ game.SCREEN_720, game.SCREEN_1080, game.SCREEN_1440 }, .{ "720", "1080", "1440" }) |size, tag| {
        g.screen = size;
        const target = try renderTarget(g);
        defer rl.unloadRenderTexture(target);
        game.character.openCharacter(g);
        g.character.choose(.inventory);
        g.character.cursor = 0;
        try capture(g, target, SHOTS_DIR ++ "/item-rare-weapon-" ++ tag ++ ".png");
        g.character.cursor = 1;
        try capture(g, target, SHOTS_DIR ++ "/item-rare-armour-" ++ tag ++ ".png");
        g.character.choose(.equipment);
        g.character.cursor = @intFromEnum(items.Slot.left_ring);
        try capture(g, target, SHOTS_DIR ++ "/item-rare-equipped-" ++ tag ++ ".png");
        game.character.openLoot(g, g.sim.heroActor().?.at);
        try capture(g, target, SHOTS_DIR ++ "/item-rare-loot-" ++ tag ++ ".png");
    }
}

fn shootTactics(g: *game.Game) !void {
    const previous = g.screen;
    defer g.screen = previous;
    const target = try target720(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/tactics");
    inline for (heroes.CLASSES) |class| {
        game.harness.heroArena(g, class, .{ .x = 20, .y = 20 }, &.{});
        g.sim.growth.active_points = 10;
        game.character.openCharacter(g);
        g.character.choose(.skills);
        inline for (comptime progress.skills(class), 0..) |s, i| {
            const act = s.act;
            g.character.cursor = i;
            g.sim.growth.ranks.set(act, 1);
            try capture(g, target, SHOTS_DIR ++ "/tactics/tree-" ++ @tagName(act) ++ ".png");
            g.sim.growth.ranks.set(act, 2);
            try capture(g, target, SHOTS_DIR ++ "/tactics/tree-" ++ @tagName(act) ++ "-upgrade.png");
            g.sim.growth.ranks.set(act, progress.RANKS);
            try capture(g, target, SHOTS_DIR ++ "/tactics/tree-" ++ @tagName(act) ++ "-maximum.png");
        }
    }
    game.harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    skills.useSkill(g, .{ .act = .arcane_barrier, .by = .x });
    g.mark = .{ .x = 23, .y = 19 };
    skills.confirmAim(g);
    g.mark = .{ .x = 23, .y = 21 };
    try capture(g, target, SHOTS_DIR ++ "/tactics/barrier-preview.png");
    skills.confirmAim(g);
    game.harness.drawnOut(g);
    try capture(g, target, SHOTS_DIR ++ "/tactics/barrier-raised.png");
    game.harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    skills.useSkill(g, .{ .act = .caltrops, .by = .x });
    g.mark = .{ .x = 23, .y = 20 };
    try capture(g, target, SHOTS_DIR ++ "/tactics/caltrops-preview.png");
    skills.confirmAim(g);
    game.harness.drawnOut(g);
    try capture(g, target, SHOTS_DIR ++ "/tactics/caltrops-laid.png");
    _ = g.sim.inventory.add(.{ .kind = .gloves, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .crit, .value = 5 }, null, null } });
    game.character.openCharacter(g);
    g.character.choose(.inventory);
    g.character.cursor = 0;
    try capture(g, target, SHOTS_DIR ++ "/tactics/item-prefix-suffix.png");
}

fn shootMouse(g: *game.Game) !void {
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/mouse");
    const screen = g.screen;
    defer g.screen = screen;
    const target = try target720(g);
    defer rl.unloadRenderTexture(target);
    try app.shootMenus(g, target);
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 24, .y = 20 }});
    g.st = .{ .device = .keys, .modifier = g.bar.modifier };
    try capture(g, target, SHOTS_DIR ++ "/mouse/hud.png");
    skills.openAim(g, game.harness.boundTo(g, .shoot).by, .shoot);
    g.st.pointer = game.scene.Cam.of(g).mid(.{ .x = 24, .y = 20 });
    g.st.mouse_moved = true;
    game.update(g, 0);
    try capture(g, target, SHOTS_DIR ++ "/mouse/aim.png");
    try checkMouseHiddenAim(g, target);
    game.character.openPause(g);
    try capture(g, target, SHOTS_DIR ++ "/mouse/pause.png");
    game.debugging.open(g, .diagnostics);
    try capture(g, target, SHOTS_DIR ++ "/mouse/diagnostics.png");
    try editor.shoot(g, target, SHOTS_DIR ++ "/mouse/editor.png", SHOTS_DIR ++ "/mouse/editor-graph.png", SHOTS_DIR ++ "/mouse/editor-generator.png", SHOTS_DIR ++ "/mouse/editor-objects.png");
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const before = g.sim.heroActor().?.hp;
    _ = g.sim.pool.damage(&g.sim.lv, g.sim.hero, before);
    g.sim.chronicle.note(.{ .hurt = .{ .by = .{ .foe = .rat }, .dmg = before, .before = before } });
    g.pic.catchUp(&g.sim);
    g.mode = .dead;
    game.epitaph.inscribe(g);
    try capture(g, target, SHOTS_DIR ++ "/mouse/death.png");
}

fn checkMouseHiddenAim(g: *game.Game, target: rl.RenderTexture2D) !void {
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    for (0..grid.CELLS) |i| if (grid.Level.of(i).x >= 22) {
        g.sim.lv.lit[i] = false;
        g.sim.lv.seen[i] = false;
    };
    g.light.settle(&g.sim.lv);
    skills.aiming(g, game.harness.boundTo(g, .shoot).by, .shoot);
    g.st = .{ .device = .keys, .modifier = g.bar.modifier, .mouse_moved = true, .pointer = game.scene.Cam.of(g).mid(.{ .x = 24, .y = 20 }) };
    _ = game.mouseControls.aim(g);
    if (g.mode != .aim or skills.aimable(g, g.sim.heroActor().?.at, g.mark)) return error.MouseHiddenAimSetup;
    try capture(g, target, SHOTS_DIR ++ "/mouse/aim-hidden.png");
    const aimed = try readTarget(target);
    defer rl.unloadImage(aimed);
    g.mode = .play;
    drawInto(g, target);
    const plain = try readTarget(target);
    defer rl.unloadImage(plain);
    const corner = game.scene.Cam.of(g).corner(.{ .x = 23, .y = 20 });
    var checked: usize = 0;
    for (0..game.CELL) |dy| for (0..game.CELL) |dx| {
        const x = corner.x + @as(i32, @intCast(dx));
        const y = corner.y + @as(i32, @intCast(dy));
        if (!sameRgb(rl.getImageColor(aimed, x, y), rl.getImageColor(plain, x, y))) return error.MouseAimRevealedHiddenPath;
        checked += 1;
    };
    std.debug.print("mouse targeting GPU: {d} hidden path pixels unchanged\n", .{checked});
}

pub fn shootDebug(g: *game.Game) !void {
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
    const target = try target720(g);
    defer rl.unloadRenderTexture(target);
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    game.harness.grassOver(&g.sim.lv);
    const bag = P{ .x = 19, .y = 20 };
    const chest = P{ .x = 21, .y = 20 };
    for ([_]items.Kind{ .ring, .boots, .axe }) |kind| _ = g.sim.ground.add(.{ .item = .{ .kind = kind, .mods = .{ if (kind == .axe) .{ .kind = .strength, .value = 3 } else null, null, null, null } }, .at = bag });
    _ = g.sim.ground.gold(bag, 37);
    g.sim.lv.set(chest, .chest);
    game.settle(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-ground.png");
    _ = game.character.openNearby(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-containers.png");
    game.character.openLoot(g, bag);
    g.st.device = .xbox;
    try capture(g, target, SHOTS_DIR ++ "/loot-bag-pad.png");
    g.st.device = .keys;
    try capture(g, target, SHOTS_DIR ++ "/loot-bag-keys.png");
    g.character.cursor = 3;
    try capture(g, target, SHOTS_DIR ++ "/loot-gold.png");
    game.character.characterCommand(g, .close);
    game.heroStep(g, .e, 0);
    game.harness.drawnOut(g);
    if (g.mode != .play or g.sim.gold != 0 or g.sim.ground.coin_n != 2) return error.ChestRevealMismatch;
    try capture(g, target, SHOTS_DIR ++ "/loot-chest-revealed.png");
    game.heroStep(g, .e, 0);
    game.harness.drawnOut(g);
    if (g.mode != .pause or g.character.page != .loot or g.sim.gold != 0 or g.sim.ground.coin_n != 2) return error.ChestLootUnopened;
    try capture(g, target, SHOTS_DIR ++ "/loot-chest.png");
    game.character.characterCommand(g, .close);
    try capture(g, target, SHOTS_DIR ++ "/loot-chest-left.png");
    game.character.openLoot(g, chest);
    game.character.characterCommand(g, .take_all);
    game.harness.drawnOut(g);
    if (g.sim.ground.n != 3 or g.sim.inventory.n != 1 or g.sim.gold < items.CHEST_GOLD.lo or g.sim.ground.coin_n != 1 or g.sim.lv.at(chest) != .chest_open) return error.LootContainerMismatch;
    try capture(g, target, SHOTS_DIR ++ "/loot-chest-empty.png");
    for (0..items.BAG_MAX - g.sim.inventory.n) |_| _ = g.sim.inventory.add(.{ .kind = .cap });
    game.heroStep(g, .w, 0);
    game.harness.drawnOut(g);
    game.character.openLoot(g, bag);
    game.character.characterCommand(g, .take_all);
    try capture(g, target, SHOTS_DIR ++ "/loot-full.png");
    game.harness.drawnOut(g);
    for (0..16) |_| _ = g.sim.ground.add(.{ .item = .{ .kind = .axe, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .mana, .value = 2 }, null, null } }, .at = bag });
    game.character.openLoot(g, bag);
    try capture(g, target, SHOTS_DIR ++ "/loot-dense.png");
    for (0..18) |_| game.harness.nudge(g, .s);
    try capture(g, target, SHOTS_DIR ++ "/loot-dense-scrolled.png");

    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{chest});
    game.harness.grassOver(&g.sim.lv);
    g.sim.loot_rng = game.harness.lootRng(true);
    game.settle(g);
    game.harness.slay(g, 2, g.sim.heroActor().?.at);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-before.png");
    game.harness.drawnOut(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-dropped.png");
    game.character.openLoot(g, chest);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-blue.png");

    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    game.harness.grassOver(&g.sim.lv);
    _ = g.sim.ground.gold(bag, 37);
    game.settle(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-gold-only-ground.png");
    game.heroStep(g, .w, 0);
    game.harness.drawnOut(g);
    if (g.mode != .play or g.sim.gold != 37 or g.sim.ground.coin_n != 0) return error.GoldAutoLootMismatch;
    try capture(g, target, SHOTS_DIR ++ "/loot-gold-only.png");
}

fn shootLevelUp(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/level-up");
    inline for (.{ .{ "day", day.NOON }, .{ "night", NIGHT } }) |scene| {
        poseForest(g);
        studyAt(g, true, scene[1]);
        g.st = .{ .device = .keys };
        g.pic.settleXp(&g.sim);
        try capture(g, target, SHOTS_DIR ++ "/level-up/" ++ scene[0] ++ "-before.png");
        _ = g.sim.growth.gain(@intCast(g.sim.growth.needed()));
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

pub fn shootTrees(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/trees");
    game.harness.arena(g, .{ .x = 24, .y = 18 }, &.{});
    game.harness.grassOver(&g.sim.lv);
    const tree = P{ .x = 24, .y = 19 };
    g.sim.lv.set(tree, .large_tree);
    g.sim.lv.set(.{ .x = 27, .y = 19 }, .large_tree);
    g.sim.lv.set(.{ .x = 22, .y = 24 }, .large_tree);
    game.harness.wallRow(&g.sim.lv, 18, 26, 30);
    studyLit(g, true, day.NOON);
    g.st = .{};
    try capture(g, target, SHOTS_DIR ++ "/trees/behind-opaque.png");
    game.update(g, 0.04);
    const partial = g.pic.occlusion[grid.Level.idx(tree)];
    if (partial <= 0 or partial >= 1) return error.TreeFadeNotSmooth;
    try capture(g, target, SHOTS_DIR ++ "/trees/behind-fading.png");
    for (0..120) |_| game.update(g, mathx.TEST_DT);
    if (g.pic.occlusion[grid.Level.idx(tree)] < 0.99) return error.TreeDidNotFade;
    try capture(g, target, SHOTS_DIR ++ "/trees/behind-clear.png");
    const hero = g.sim.heroSlot().?;
    const still = g.pic.glide[hero];
    g.pic.glide[hero] = still.toward(.{ .x = 25, .y = 18 }, game.GLIDE_S / 2);
    try capture(g, target, SHOTS_DIR ++ "/trees/behind-midstep.png");
    g.pic.glide[hero] = still;
    var behind_gas = grid.Cells.of(.{ .x = 23, .y = 17 }, .{ .x = 26, .y = 21 });
    while (behind_gas.next()) |p| g.sim.lv.gas[grid.Level.idx(p)] = 60;
    g.cloud.settle(&g.sim.lv);
    try capture(g, target, SHOTS_DIR ++ "/trees/behind-gas.png");
    @memset(&g.sim.lv.gas, 0);
    g.cloud.settle(&g.sim.lv);
    g.sim.pool.move(&g.sim.lv, g.sim.hero, .{ .x = 24, .y = 20 });
    g.pic.glide[hero] = @import("glide.zig").Glide.rest(g.sim.heroActor().?);
    game.update(g, 0.04);
    const restoring = g.pic.occlusion[grid.Level.idx(tree)];
    if (restoring <= 0 or restoring >= 0.99) return error.TreeRestoreNotSmooth;
    try capture(g, target, SHOTS_DIR ++ "/trees/front-restoring.png");
    for (0..120) |_| game.update(g, mathx.TEST_DT);
    if (g.pic.occlusion[grid.Level.idx(tree)] > 0.01) return error.TreeDidNotRestore;
    try capture(g, target, SHOTS_DIR ++ "/trees/front-opaque.png");
    var gassed = grid.Cells.of(.{ .x = 21, .y = 17 }, .{ .x = 29, .y = 25 });
    while (gassed.next()) |p| g.sim.lv.gas[grid.Level.idx(p)] = 60;
    studyLit(g, false, NIGHT);
    try capture(g, target, SHOTS_DIR ++ "/trees/night-gas.png");
    g.cam.y = @as(f32, @floatFromInt(24 * game.CELL - g.screen.y + game.HALF_CELL));
    try capture(g, target, SHOTS_DIR ++ "/trees/bough-at-screen-bottom.png");
    @memset(&g.sim.lv.gas, 0);
    studyLit(g, true, day.NOON);
    game.prepare(g);
    {
        const tex = g.sprites.tiles.get(.large_tree) orelse return error.TreeTextureMissing;
        g.sprites.tiles.set(.large_tree, null);
        defer g.sprites.tiles.set(.large_tree, tex);
        try capture(g, target, SHOTS_DIR ++ "/trees/glyph-fallback.png");
    }
    poseWaterMirrors(g, day.NOON, true);
    g.sim.lv.set(.{ .x = 27, .y = 17 }, .large_tree);
    studyLit(g, true, day.NOON);
    try capture(g, target, SHOTS_DIR ++ "/trees/water-reflection.png");
    std.debug.print("tall tree captures: native height, wall adjacency, smooth hiding/restoration and front/behind depth checked\n", .{});
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
                if ((!g.sim.lv.isSeen(p) and interior) or (live_only and !g.sim.lv.isLit(p))) {
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
    g.pic.fx.zap(0, POSE_ZAP);
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
    defer g.sim.map = null;
    const screen = g.screen;
    defer g.screen = screen;
    const target = try target720(g);
    defer rl.unloadRenderTexture(target);
    spar.author(w, .slime);
    g.sim.class = heroes.DEFAULT;
    game.beginMapAt(g, w, w.start, SHOT_SEED);
    _ = g.sim.growth.gain(100);
    _ = g.sim.inventory.add(.{ .kind = .cap, .mods = .{ .{ .kind = .life, .value = 3 }, null, null, null } });
    try g.sim.inventory.equip(0, .helm, g.sim.growth.attributes(g.sim.class));
    _ = g.sim.inventory.add(.{ .kind = .bow, .mods = .{ .{ .kind = .dexterity, .value = 2 }, null, null, null } });
    try g.sim.inventory.equip(0, .right_hand, g.sim.growth.attributes(g.sim.class));
    _ = g.sim.inventory.add(.{ .kind = .helmet, .mods = .{ .{ .kind = .life, .value = 6 }, .{ .kind = .mana, .value = 2 }, null, null } });
    _ = g.sim.inventory.add(.{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 3 }, null, null, null } });
    _ = g.sim.inventory.add(.{ .kind = .leather });
    _ = g.sim.ground.add(.{ .item = .{ .kind = .amulet }, .at = g.sim.heroActor().?.at });
    g.sim.log.push(.event, "Archer enters the old ruins.", .{});
    g.sim.log.push(.damage, "Archer shoots the rat for 3.", .{});
    g.sim.log.push(.danger, "The rat bites Archer for 2.", .{});
    g.sim.log.push(.recovery, "Archer recovers 4 life.", .{});
    g.sim.log.push(.loot, "Archer picks up 8 gold.", .{});
    g.sim.log.push(.event, "Archer opens the chest.", .{});
    g.sim.log.push(.loot, "Picked up Iron helm.", .{});
    g.sim.log.push(.progress, "Level 3: +2 passive, +2 active points.", .{});
    g.sim.log.push(.damage, "Archer shoots the slime for 4.", .{});
    g.sim.log.push(.danger, "The slime hits Archer for 2.", .{});
    game.combat.noticeItems(g, g.sim.heroActor().?.at);
    game.syncStats(g);
    game.harness.drawnOut(g);
    g.back = .editor;
    try capture(g, target, SHOTS_DIR ++ "/arena.png");
    game.character.openCharacter(g);
    inline for (book.PAGES) |page| {
        g.character.choose(page);

        if (page == .passives) g.character.cursor = progress.start(g.sim.class);
        if (page == .equipment) g.character.cursor = @intFromEnum(items.Slot.helm);
        try capture(g, target, SHOTS_DIR ++ "/character-" ++ @tagName(page) ++ ".png");
    }
    {
        g.character.choose(.stats);
        g.character.advanced = true;
        defer g.character.advanced = false;
        try capture(g, target, SHOTS_DIR ++ "/character-stats-advanced.png");
    }
    {
        const device = g.st.device;
        defer g.st.device = device;
        g.st.device = .keys;
        g.character.choose(.equipment);
        try capture(g, target, SHOTS_DIR ++ "/character-keyboard.png");
    }
    {
        const gear = g.sim.inventory.gear;
        defer g.sim.inventory.gear = gear;
        const bag_n = g.sim.inventory.n;
        defer g.sim.inventory.n = bag_n;
        g.character.choose(.inventory);

        g.character.cursor = 2;
        try capture(g, target, SHOTS_DIR ++ "/item-normal-armour.png");
        g.sim.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .mana, .value = 3 }, null, null, null } });
        g.sim.inventory.gear.slots.set(.right_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .dexterity, .value = 3 }, null, null, null } });
        g.character.cursor = 1;
        g.character.destination_index = 0;
        try capture(g, target, SHOTS_DIR ++ "/item-ring-left.png");
        g.character.destination_index = 1;
        try capture(g, target, SHOTS_DIR ++ "/item-ring-right.png");
        g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = .sling });
        g.sim.inventory.gear.slots.set(.left_hand, .{ .kind = .buckler, .mods = .{ .{ .kind = .life, .value = 6 }, null, null, null } });
        _ = g.sim.inventory.add(.{ .kind = .crossbow, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .mana, .value = 2 }, null, null } });
        g.character.cursor = bag_n;
        g.character.destination_index = 0;
        try capture(g, target, SHOTS_DIR ++ "/item-two-handed.png");
        const class = g.sim.class;
        defer g.sim.class = class;
        g.sim.class = .knight;
        g.sim.inventory.gear.slots.set(.left_hand, null);
        g.character.choose(.equipment);

        inline for ([_]items.Kind{ .axe, .greatclub, .greatsword }) |kind| {
            g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = kind });
            g.character.cursor = @intFromEnum(items.Slot.right_hand);
            try capture(g, target, SHOTS_DIR ++ "/item-" ++ @tagName(kind) ++ "-equipped.png");
        }
        g.character.cursor = @intFromEnum(items.Slot.left_hand);
        try capture(g, target, SHOTS_DIR ++ "/item-offhand-occupied.png");
    }
    {
        const inventory = g.sim.inventory;
        defer g.sim.inventory = inventory;
        const thorned = items.Item{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, .{ .kind = .life, .value = 3 }, null, null } };
        const spoils = items.Item{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .spoils, .value = 25 }, null, null } };
        g.character.choose(.inventory);
        g.character.cursor = g.sim.inventory.n;
        if (!g.sim.inventory.add(thorned)) return error.InventoryFull;
        try capture(g, target, SHOTS_DIR ++ "/item-thorns.png");
        g.character.cursor = g.sim.inventory.n;
        if (!g.sim.inventory.add(spoils)) return error.InventoryFull;
        try capture(g, target, SHOTS_DIR ++ "/item-spoils.png");
        g.sim.inventory.gear.slots.set(.chest, thorned);
        g.sim.inventory.gear.slots.set(.left_ring, spoils);
        g.character.choose(.stats);
        g.character.advanced = true;
        defer g.character.advanced = false;
        try capture(g, target, SHOTS_DIR ++ "/character-thorns-spoils.png");
    }
    {
        const device = g.st.device;
        defer g.st.device = device;
        inline for ([_]input.Device{ .keys, .xbox, .ps5 }) |d| {
            g.st.device = d;
            g.character.choose(.passives);

            g.character.cursor = progress.start(g.sim.class);
            try capture(g, target, SHOTS_DIR ++ "/tree-controls-" ++ @tagName(d) ++ ".png");
        }
        g.character.pan = .{ .x = 1.5, .y = -0.8 };
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-pan.png");
        g.character.pan = .{ .x = 0, .y = 0 };
        g.character.zoom = 1;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-overview.png");
    }
    {
        const was_class = g.sim.class;
        const was_growth = g.sim.growth;
        defer g.sim.class = was_class;
        defer g.sim.growth = was_growth;
        inline for (heroes.CLASSES) |class| {
            g.sim.class = class;
            g.sim.growth = progress.State.of(class);
            g.sim.growth.active_points = 2;
            g.character.choose(.skills);

            g.character.cursor = progress.skills(class).len - 1;
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-future.png");
            g.character.cursor = if (class == .wizard) 4 else 0;
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-description.png");
            g.sim.growth.ranks.set(progress.skills(class)[g.character.cursor].act, 2);
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-upgrade.png");
            if (class == .archer) {
                g.character.cursor = 2;
                g.sim.growth.ranks.set(progress.skills(class)[2].act, 2);
                try capture(g, target, SHOTS_DIR ++ "/tree-skills-mixed-upgrade.png");
            }
            g.character.cursor = progress.skills(class).len - 1;
            g.sim.growth.active_points = 30;
            for (progress.skills(class)) |s| while (g.sim.growth.learn(class, s.act)) {};
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-maximum.png");
        }
        g.sim.class = .knight;
        g.sim.growth = progress.State.of(g.sim.class);
        g.sim.growth.passive_points = 30;
        const branch = progress.passives.branchFirst(.warrior_life);
        for (branch..branch + progress.passives.PER_BRANCH - 1) |i| _ = g.sim.growth.allocate(i);
        const bridge = progress.passives.bridgeFirst(.warrior_rogue);
        _ = g.sim.growth.allocate(bridge);
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
        g.sim.growth.passive_points = 0;
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
    g.sim.log.release();
    try capture(g, target, SHOTS_DIR ++ "/event-log.png");
    g.sim.inventory = .{};
    for (std.enums.values(items.Kind)) |kind| _ = g.sim.inventory.add(.{ .kind = kind });
    g.mode = .pause;
    g.pause_page = .character;
    g.character.open();
    g.character.choose(.inventory);

    inline for ([_]items.Kind{ .crossbow, .dagger, .staff, .wand, .tome, .orb, .buckler, .shield, .totem, .ash_wand, .rime_wand, .storm_wand, .hunting_bow, .war_bow, .circlet, .flask_belt, .robes }) |kind| {
        g.character.cursor = @intFromEnum(kind);
        try capture(g, target, SHOTS_DIR ++ "/item-" ++ @tagName(kind) ++ ".png");
    }
    g.sim.inventory.bag[@intFromEnum(items.Kind.axe)].mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .mana, .value = 2 }, null, null };
    g.character.cursor = @intFromEnum(items.Kind.axe);
    try capture(g, target, SHOTS_DIR ++ "/item-axe-magic.png");
}

fn shootEffects(g: *game.Game, target: rl.RenderTexture2D) !void {
    try shootArrows();
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
            g.mark = if (reticle == .leap) .{ .x = 22, .y = 20 } else .{ .x = 23, .y = 20 };
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

fn shootArrows() !void {
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
            fx.drawArrow(.{ .x = x + dir[0] * 8 * scale, .y = y + dir[1] * 8 * scale }, dir, look.arrowInk(.shoot), scale);
        }
    }
    rl.endTextureMode();
    try exportTarget(target, SHOTS_DIR ++ "/arrow-directions.png");
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
        g.bar = skillbar.Bar.of(g.sim.class);
        g.st = .{ .device = study.device, .modifier = g.bar.modifier };
        const body = &g.pic.pictured[g.sim.heroSlot().?];
        body.hp = mathx.percentOf(body.max, study.hp);
        g.sim.mana = mathx.percentOf(g.sim.manaMax(), study.mana);
        g.pic.settleResources(&g.sim);
        g.pic.xp_shown = study.xp;
        if (study.ailing) {
            body.status = .initDefault(0, .{ .bleeding = bleeding.TURNS, .burning = burning.TURNS, .chilled = glacial.TURNS - 1 });
            body.resilience.meters.set(.stun, .{ .percent = 75, .turns = 4 });
            body.resilience.meters.set(.bleed, .{ .percent = 25, .turns = 5 });
            body.status.set(.resistant, 5);
            g.sim.cooldown.set(.juke, juke.COOLDOWN);
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
            g.inspecting = .{ .slot = binds.Binds.colOf(.x) };
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-skill.png");
            g.inspecting = .{ .status = .burning };
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-status.png");
            g.inspecting = .{ .status = .resistant };
            try capture(g, target, SHOTS_DIR ++ "/hud-inspect-resistance.png");
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
            const wa = prompt_icon.Prompt.of(&st, a).width(&g.face, game.PROMPT_PX);
            const wb = prompt_icon.Prompt.of(&st, b).width(&g.face, game.PROMPT_PX);
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

fn posePicker(g: *game.Game, u: skills.Use) void {
    binds.openBinds(g);
    g.binds.row = game.rowAt(u.set);
    g.binds.col = binds.Binds.colOf(u.by);
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
    game.combat.wound(g, 2, .{ .dmg = actor.row(.rat).hp }, SHOOT, .{ .from = hero, .wait = wait });
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

fn poseGas(g: *game.Game) void {
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
    game.harness.grassOver(&g.sim.lv);
    var cells = grid.Cells.of(.{ .x = 17, .y = 15 }, .{ .x = 30, .y = 26 });
    while (cells.next()) |p| g.sim.lv.set(p, if (p.x < 19) .water else .shallows);
    for (WADERS) |w| _ = game.harness.spawnAt(g, w.kind, w.at, false);
    game.settle(g);
    g.st = .{};
    for (g.sim.pool.slice(), 0..) |a, i| {
        const to = a.at.add(mathx.Dir.e.delta());
        g.sim.pool.move(&g.sim.lv, actor.Pool.idOf(i), to);
        g.pic.glide[i] = g.pic.glide[i].toward(to, g.pic.glide[i].span() * (game.presentation.SPLASH_AT + 0.01));
    }
    game.update(g, 0);
    game.update(g, 0.055);
}

fn poseWaterMirrors(g: *game.Game, hour: f32, outdoors: bool) void {
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

fn poseForest(g: *game.Game) void {
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
    for (rows, 0..) |row, y| {
        for (row, 0..) |ch, x| {
            if (ch == '#') g.sim.lv.set(.{ .x = 16 + @as(i32, @intCast(x)), .y = 12 + @as(i32, @intCast(y)) }, .shrub);
        }
    }
    posed(g, g.sim.outdoors);
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

fn studyLit(g: *game.Game, outdoors: bool, hour: f32) void {
    studyAt(g, outdoors, hour);
    @memset(&g.sim.lv.seen, true);
    @memset(&g.sim.lv.lit, true);
    g.light.settle(&g.sim.lv);
}

fn studyAt(g: *game.Game, outdoors: bool, hour: f32) void {
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

fn waterSample(g: *game.Game, target: rl.RenderTexture2D, beds: *const dual.Beds, view: ?look.WaterView, origin: [2]f32) !rl.Image {
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    g.sprites.drawGround(&g.sim.lv, beds, origin, game.CELL_F, view);
    rl.endTextureMode();
    return readTarget(target);
}

fn shootWater(g: *game.Game, target: rl.RenderTexture2D) !void {
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/water-reflections");
    g.st = .{};
    const FRAMES = 40;
    const EVERY = 6;
    const before = g.light.t.at();
    const minute = g.sim.clock;
    for (0..FRAMES) |i| {
        for (0..EVERY) |_| game.update(g, mathx.FRAME_DT);
        var path: [80]u8 = undefined;
        try capture(g, target, try std.fmt.bufPrintZ(&path, SHOTS_DIR ++ "/water-reflections/{d:0>2}.png", .{i}));
    }
    const elapsed = g.light.t.at() - before;
    if (elapsed < FRAMES * EVERY * mathx.FRAME_DT - 0.01 or !std.meta.eql(minute, g.sim.clock)) return error.WaterIdleClock;
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
    const visibility = raster.clamped(raster.rgba(&sight, grid.W, grid.H), .point) orelse return error.WaterVisibilityMissing;
    defer rl.unloadTexture(visibility);
    const gleam = raster.canvas(grid.W, grid.H, look.rgb(0x302010), .point) orelse return error.WaterGlintsMissing;
    defer rl.unloadTexture(gleam);
    const dark = raster.canvas(1, 1, rl.Color.black, .point) orelse return error.WaterGlintsMissing;
    defer rl.unloadTexture(dark);
    const blank = raster.canvas(1, 1, rl.Color.blank, .point) orelse return error.WaterMirrorMissing;
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
    game.harness.grassOver(&g.sim.lv);
    for (0..grid.W) |x| g.sim.lv.set(.{ .x = @intCast(x), .y = grid.H - 1 }, .grass);
    studyLit(g, true, day.NOON);
    const edge = @divTrunc(g.screen.y, 2);
    g.cam.y = @floatFromInt(game.MAP_PX.y - edge);
    game.prepare(g);
    var compared: usize = 0;
    for ([_]bool{ true, false }) |visible| {
        @memset(&g.sim.lv.lit, visible);
        g.light.settle(&g.sim.lv);
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
    @memset(&g.sim.lv.lit, false);
    g.light.settle(&g.sim.lv);
    try capture(g, target, SHOTS_DIR ++ "/water-mirrors-memory.png");
    const memory = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(memory);
    const dim = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(dim);
    const actors = g.sim.pool.n;
    g.sim.pool.n = 0;
    defer g.sim.pool.n = actors;
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
    @memset(&g.sim.lv.seen, false);
    g.light.settle(&g.sim.lv);
    intoTarget(g, target);
    const c = game.scene.Cam.of(g);
    var flame_buf: [grid.MAX_TORCHES]light.Flame = undefined;
    _ = game.scene.drawMirrors(g, c, game.scene.viewBox(g, c), &.{}, g.light.flames(&g.sim.lv, &flame_buf));
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
    const barrels = g.sim.lv.barrel;
    const remembered = g.sim.lv.barrel_seen;
    defer {
        g.sim.lv.barrel = barrels;
        g.sim.lv.barrel_seen = remembered;
        g.art_ready = false;
    }
    @memset(&g.sim.lv.barrel, false);
    g.art_ready = false;
    try capture(g, target, SHOTS_DIR ++ "/water-mirrors-broken-remembered.png");
    const broken = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(broken);
    @memset(&g.sim.lv.barrel_seen, false);
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
    g.light.bake(&g.sim.lv, view.lo, view.hi);
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
}

fn benchGrass(g: *game.Game, target: rl.RenderTexture2D) !void {
    game.harness.arena(g, .{ .x = 24, .y = 20 }, &.{});
    game.harness.grassOver(&g.sim.lv);
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
    const w = try alloc.create(atlas.Atlas);
    defer alloc.destroy(w);
    defer g.sim.map = null;
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
    const h = g.sim.heroActor() orelse return;
    const rat = for (g.sim.pool.slice(), 0..) |a, i| {
        if (a.kind == .rat) break actor.Pool.idOf(i);
    } else return;
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        const d = mathx.dist(p, h.at);
        if (d < POSE_NEAR or d > POSE_FAR or !bow.aimable(&g.sim.lv, h.at, p) or g.sim.lv.taken(p)) continue;
        g.sim.pool.move(&g.sim.lv, rat, p);
        break;
    }
    game.combat.wound(g, rat, .{ .dmg = bow.BASE.lo }, SHOOT, .{ .from = h.at, .wait = 0 });
    game.settle(g);
}
