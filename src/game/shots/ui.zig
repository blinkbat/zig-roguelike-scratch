const std = @import("std");
const inventory = @import("../../play/inventory.zig");
const item_bases = @import("../../play/item_bases.zig");
const items = @import("../../play/items.zig");
const loot = @import("../../play/loot.zig");
const progress = @import("../../play/progress.zig");
const passives = @import("../../play/passives.zig");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const input = @import("../../core/input.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const spar = @import("../../map/spar.zig");
const app = @import("../../app.zig");
const editor = @import("../../edit/editor.zig");
const book = @import("../../ui/book.zig");
const heroes = @import("../../play/hero.zig");
const actor = @import("../../play/actor.zig");
const burning = @import("../../play/burning.zig");
const bleeding = @import("../../play/bleeding.zig");
const glacial = @import("../../play/glacial.zig");
const juke = @import("../../play/juke.zig");
const skillbar = @import("../../play/skillbar.zig");
const look = @import("../../gfx/look.zig");
const prompt_icon = @import("../../gfx/prompt_icon.zig");
const day = @import("../../map/day.zig");
const game = @import("../../game.zig");
const rewards = @import("../rewards.zig");
const skills = @import("../skills.zig");
const binds = @import("../binds.zig");
const script_text = @import("../../map/script_text.zig");

const P = mathx.P;
const MOUSE_DIR = @import("capture.zig").MOUSE_DIR;
const SHOTS_DIR = @import("capture.zig").SHOTS_DIR;
const SHOT_SEED = @import("capture.zig").SHOT_SEED;
const capture = @import("capture.zig").capture;
const drawInto = @import("capture.zig").drawInto;
const dropAtlas = @import("capture.zig").dropAtlas;
const heapAtlas = @import("capture.zig").heapAtlas;
const exportTarget = @import("capture.zig").exportTarget;
const readTarget = @import("capture.zig").readTarget;
const renderTarget = @import("capture.zig").renderTarget;
const sameRgb = @import("capture.zig").sameRgb;
const target720 = @import("capture.zig").target720;
const targetAt = @import("capture.zig").targetAt;
const TACTICS_DIR = SHOTS_DIR ++ "/tactics";
const LEVEL_UP_DIR = SHOTS_DIR ++ "/level-up";
const NIGHT = @import("poses.zig").NIGHT;
const poseForest = @import("poses.zig").poseForest;
const posePicker = @import("poses.zig").posePicker;
const studyAt = @import("poses.zig").studyAt;

pub fn captureEditor(g: *game.Game) !void {
    for (game.SCREENS) |size| {
        const shot = try targetAt(g, size);
        defer shot.close(g);
        const target = shot.target;
        var dir_buf: [128]u8 = undefined;
        const dir = try std.fmt.bufPrint(&dir_buf, SHOTS_DIR ++ "/editor-{d}x{d}", .{ size.x, size.y });
        try std.fs.cwd().makePath(dir);
        var paths: [4][256]u8 = undefined;
        try editor.capture(g, target, try std.fmt.bufPrintZ(&paths[0], "{s}/edit.png", .{dir}), try std.fmt.bufPrintZ(&paths[1], "{s}/edit-graph.png", .{dir}), try std.fmt.bufPrintZ(&paths[2], "{s}/edit-gen.png", .{dir}), try std.fmt.bufPrintZ(&paths[3], "{s}/edit-objects.png", .{dir}));
    }
}

pub fn captureUi(g: *game.Game) !void {
    try std.fs.cwd().makePath(SHOTS_DIR);
    try captureQuests(g);
    try captureTalk(g);
    try captureTactics(g);
    try book.verifyCards(&g.face);
    try book.verifyStats(&g.face);
    try book.verifyTabs(&g.face);
    try captureCharacter(g);
    try captureRares(g);
    try captureLoot(g);
    try captureHud(g);
    try captureInspect(g);
    try captureLevelUp(g);
    try captureMouse(g);
    try app.captureHeroes(g);
}

fn captureQuests(g: *game.Game) !void {
    const quests = @import("../../ui/quests.zig");
    const script = @import("../../map/script.zig");
    const entries = [_]quests.Entry{.{ .title = "The Stolen Pib", .asks = "Search the goblin camp beyond the north road and return the missing pib to the caravan merchant.", .done = false }} ** (script.MAX_QUESTS - 1) ++ [_]quests.Entry{.{ .title = "The Last Quest", .asks = "", .done = true }};
    const carried = inventory.Inventory{};
    const growth = progress.State.of(heroes.DEFAULT);
    var b = book.Book{};
    b.choose(.quests);
    inline for (.{ game.SCREEN_720, game.SCREEN_1080 }) |size| {
        const view = book.View{ .class = heroes.DEFAULT, .name = "Archer", .inventory = &carried, .growth = &growth, .base = growth.attributes(heroes.DEFAULT), .quests = book.journalOn(size, g.face, &entries) };
        const target = try rl.loadRenderTexture(size.x, size.y);
        defer rl.unloadRenderTexture(target);
        inline for (.{ "first", "last" }) |at| {
            b.top = if (comptime std.mem.eql(u8, at, "first")) 0 else view.quests.last_top;
            rl.beginTextureMode(target);
            rl.clearBackground(look.BG);
            b.draw(&g.face, &g.sprites, size, view);
            rl.endTextureMode();
            try exportTarget(target, SHOTS_DIR ++ std.fmt.comptimePrint("/quests-{d}-{s}.png", .{ size.y, at }));
        }
    }
}

fn captureInspect(g: *game.Game) !void {
    inline for (.{ game.SCREEN_720, game.SCREEN_1080 }) |size| {
        const suffix = std.fmt.comptimePrint("{d}", .{size.y});
        const shot = try targetAt(g, size);
        defer shot.close(g);
        const target = shot.target;
        const h = game.harness;
        const from = P{ .x = 20, .y = 20 };
        const at = P{ .x = 23, .y = 20 };
        h.grassArena(g, from, &.{});
        const id = h.spawnAt(g, .beefy_pib, at, true);
        g.sim.lv.set(at, .shallows);
        g.sim.lv.set(from, .reeds);
        g.sim.pool.get(id).?.burn.start();
        g.sim.pool.get(id).?.resilience.meters.set(.burn, .{ .percent = 25, .turns = 3 });
        game.settle(g);
        g.st = .{ .device = .keys };
        g.mode = .inspect;
        g.inspecting = .{ .actor = id };
        g.inspect_scroll = 0;
        try capture(g, target, SHOTS_DIR ++ "/inspect-enemy-water-" ++ suffix ++ ".png");
        g.inspecting = .{ .actor = g.sim.hero };
        try capture(g, target, SHOTS_DIR ++ "/inspect-hero-reeds-" ++ suffix ++ ".png");
        g.sim.lv.set(at, .grass);
        g.inspecting = .{ .actor = id };
        try capture(g, target, SHOTS_DIR ++ "/inspect-enemy-grass-" ++ suffix ++ ".png");
        g.mode = .play;
    }
}

fn captureTalk(g: *game.Game) !void {
    const w = try heapAtlas();
    defer dropAtlas(g, w);
    w.* = .{};
    const n = w.add(.{ .bespoke = .{} }).?;
    var floor = grid.Box.sized(.{ .x = 6, .y = 4 }, 20, 10).cells();
    while (floor.next()) |p| w.node[n].plan.bespoke.tile[grid.Level.idx(p)] = .floor;
    w.start = .{ .node = n, .at = .{ .x = 12, .y = 8 } };
    try script_text.readAlone(editor.SHOT_SCRIPT, &w.script, w.node_n);
    inline for (.{ game.SCREEN_720, game.SCREEN_1080 }) |size| {
        const suffix = std.fmt.comptimePrint("{d}", .{size.y});
        const shot = try targetAt(g, size);
        defer shot.close(g);
        const target = shot.target;
        game.beginMapAt(g, w, w.start, 5);
        g.st = .{ .device = .keys };
        g.sim.plot = .{};
        game.talking.speak(g, 0);
        try capture(g, target, SHOTS_DIR ++ "/talk-choices-" ++ suffix ++ ".png");
        g.sim.plot.pick(&w.script, 0, g.sim.world(), &g.sim.log);
        try capture(g, target, SHOTS_DIR ++ "/talk-line-" ++ suffix ++ ".png");
        g.sim.plot = .{};
        w.script.npc[0].looks = .caravan_guard;
        game.talking.speak(g, 0);
        try capture(g, target, SHOTS_DIR ++ "/talk-figure-" ++ suffix ++ ".png");
        w.script.npc[0].looks = null;
        g.sim.plot = .{};
        g.mode = .play;
        g.sim.gold = 60;
        g.sim.inventory = .{};
        if (!g.sim.inventory.add(.{ .kind = .axe, .mods = .{ .{ .kind = .strength, .value = 2 }, null, null, null } }) or !g.sim.inventory.stock(.bandage)) return error.InventoryFull;
        game.character.openTrade(g, 0);
        try capture(g, target, SHOTS_DIR ++ "/trade-buy-" ++ suffix ++ ".png");
        g.character.cursor = g.sim.plot.wares[0].?.count() - 1;
        try capture(g, target, SHOTS_DIR ++ "/trade-buy-item-" ++ suffix ++ ".png");
        g.character.selling = true;
        g.character.cursor = 1;
        try capture(g, target, SHOTS_DIR ++ "/trade-sell-" ++ suffix ++ ".png");
        g.sim.plot = .{};
        g.mode = .play;
    }
}

pub fn captureRares(g: *game.Game) !void {
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
    inline for (game.SCREENS) |size| {
        const tag = std.fmt.comptimePrint("{d}", .{size.y});
        const shot = try targetAt(g, size);
        defer shot.close(g);
        const target = shot.target;
        game.character.openCharacter(g);
        g.character.choose(.inventory);
        g.character.cursor = 0;
        try capture(g, target, SHOTS_DIR ++ "/item-rare-weapon-" ++ tag ++ ".png");
        g.character.cursor = 1;
        try capture(g, target, SHOTS_DIR ++ "/item-rare-armour-" ++ tag ++ ".png");
        g.character.choose(.equipment);
        g.character.cursor = @intFromEnum(item_bases.Slot.left_ring);
        try capture(g, target, SHOTS_DIR ++ "/item-rare-equipped-" ++ tag ++ ".png");
        game.character.openLoot(g, g.sim.heroActor().?.at);
        try capture(g, target, SHOTS_DIR ++ "/item-rare-loot-" ++ tag ++ ".png");
    }
}

fn captureTactics(g: *game.Game) !void {
    const shot = try target720(g);
    defer shot.close(g);
    const target = shot.target;
    try std.fs.cwd().makePath(TACTICS_DIR);
    inline for (heroes.CLASSES) |class| {
        game.harness.heroArena(g, class, .{ .x = 20, .y = 20 }, &.{});
        g.sim.growth.active_points = 10;
        game.character.openCharacter(g);
        g.character.choose(.skills);
        inline for (comptime progress.skills(class), 0..) |s, i| {
            const act = s.act;
            g.character.cursor = i;
            g.sim.growth.ranks.set(act, 1);
            try capture(g, target, TACTICS_DIR ++ "/tree-" ++ @tagName(act) ++ ".png");
            g.sim.growth.ranks.set(act, 2);
            try capture(g, target, TACTICS_DIR ++ "/tree-" ++ @tagName(act) ++ "-upgrade.png");
            g.sim.growth.ranks.set(act, progress.RANKS);
            try capture(g, target, TACTICS_DIR ++ "/tree-" ++ @tagName(act) ++ "-maximum.png");
        }
    }
    game.harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    skills.useSkill(g, .{ .act = .arcane_barrier, .by = .x });
    g.mode.aim.mark = .{ .x = 23, .y = 19 };
    skills.confirmAim(g);
    g.mode.aim.mark = .{ .x = 23, .y = 21 };
    try capture(g, target, TACTICS_DIR ++ "/barrier-preview.png");
    skills.confirmAim(g);
    game.harness.drawnOut(g);
    try capture(g, target, TACTICS_DIR ++ "/barrier-raised.png");
    game.harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    skills.useSkill(g, .{ .act = .caltrops, .by = .x });
    g.mode.aim.mark = .{ .x = 23, .y = 20 };
    try capture(g, target, TACTICS_DIR ++ "/caltrops-preview.png");
    skills.confirmAim(g);
    game.harness.drawnOut(g);
    try capture(g, target, TACTICS_DIR ++ "/caltrops-laid.png");
    game.harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    g.sim.growth.ranks.set(.fire_wall, 1);
    _ = game.harness.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, false);
    const chilled = game.harness.spawnAt(g, .rat, .{ .x = 21, .y = 22 }, false);
    const frightened = game.harness.spawnAt(g, .pib, .{ .x = 18, .y = 22 }, false);
    g.sim.pool.get(chilled).?.chill.apply();
    g.sim.pool.get(frightened).?.fright = actor.FLEE_TURNS;
    skills.useSkill(g, .{ .act = .fire_wall, .by = .x });
    g.mode.aim.mark = .{ .x = 23, .y = 19 };
    skills.confirmAim(g);
    g.mode.aim.mark = .{ .x = 23, .y = 21 };
    try capture(g, target, TACTICS_DIR ++ "/fire-wall-preview.png");
    skills.confirmAim(g);
    game.harness.drawnOut(g);
    try capture(g, target, TACTICS_DIR ++ "/fire-wall-chill-fright.png");
    _ = g.sim.inventory.add(.{ .kind = .gloves, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .crit, .value = 5 }, null, null } });
    game.character.openCharacter(g);
    g.character.choose(.inventory);
    g.character.cursor = 0;
    try capture(g, target, TACTICS_DIR ++ "/item-prefix-suffix.png");
    g.sim.inventory.bag[0].mods = .{ .{ .kind = .opportunist, .value = 30 }, .{ .kind = .crit, .value = 5 }, null, null };
    try capture(g, target, TACTICS_DIR ++ "/item-wrapped-affix.png");
}

fn captureMouse(g: *game.Game) !void {
    try std.fs.cwd().makePath(MOUSE_DIR);
    const shot = try target720(g);
    defer shot.close(g);
    const target = shot.target;
    try app.captureMenus(g, target);
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 24, .y = 20 }});
    g.st = .{ .device = .keys, .modifier = g.bar.modifier };
    try capture(g, target, MOUSE_DIR ++ "/hud.png");
    skills.openAim(g, game.harness.boundTo(g, .shoot).by, .shoot);
    g.st.pointer = game.scene.Cam.of(g).mid(.{ .x = 24, .y = 20 });
    g.st.mouse_moved = true;
    game.update(g, 0);
    try capture(g, target, MOUSE_DIR ++ "/aim.png");
    try checkMouseHiddenAim(g, target);
    game.character.openPause(g);
    try capture(g, target, MOUSE_DIR ++ "/pause.png");
    game.debugging.open(g, .diagnostics);
    try capture(g, target, MOUSE_DIR ++ "/diagnostics.png");
    try editor.capture(g, target, MOUSE_DIR ++ "/editor.png", MOUSE_DIR ++ "/editor-graph.png", MOUSE_DIR ++ "/editor-generator.png", MOUSE_DIR ++ "/editor-objects.png");
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const before = g.sim.heroActor().?.hp;
    _ = g.sim.pool.damage(&g.sim.lv, g.sim.hero, before);
    g.sim.chronicle.note(.{ .hurt = .{ .by = .{ .foe = .rat }, .dmg = before, .before = before } });
    g.pic.catchUp(&g.sim);
    g.mode = .dead;
    game.epitaph.inscribe(g);
    try capture(g, target, MOUSE_DIR ++ "/death.png");
}

fn checkMouseHiddenAim(g: *game.Game, target: rl.RenderTexture2D) !void {
    inline for (.{ skillbar.Act.shoot, skillbar.Act.overwatch }) |act| try checkHiddenAim(g, target, act);
}

fn checkHiddenAim(g: *game.Game, target: rl.RenderTexture2D, comptime act: skillbar.Act) !void {
    game.harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    for (0..grid.CELLS) |i| if (grid.Level.of(i).x >= 22) {
        g.sim.lv.lit[i] = false;
        g.sim.lv.seen[i] = false;
    };
    g.light.settle(&g.sim.lv);
    skills.aiming(g, game.harness.boundTo(g, .shoot).by, act);
    g.st = .{ .device = .keys, .modifier = g.bar.modifier, .mouse_moved = true, .pointer = game.scene.Cam.of(g).mid(.{ .x = if (act == .overwatch) 21 else 24, .y = 20 }) };
    _ = game.mouseControls.aim(g);
    if (g.mode != .aim or !skills.aimable(g, g.sim.heroActor().?.at, g.mode.aim.mark)) return error.MouseHiddenAimSetup;
    try capture(g, target, MOUSE_DIR ++ "/aim-hidden-" ++ @tagName(act) ++ ".png");
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
    std.debug.print("{s} targeting GPU: {d} hidden path pixels unchanged\n", .{ @tagName(act), checked });
}

const BAG_GOLD = 37;

pub fn captureLoot(g: *game.Game) !void {
    const device = g.st.device;
    defer g.st.device = device;
    const shot = try target720(g);
    defer shot.close(g);
    const target = shot.target;
    game.harness.grassArena(g, .{ .x = 20, .y = 20 }, &.{});
    const bag = P{ .x = 19, .y = 20 };
    const chest = P{ .x = 21, .y = 20 };
    for ([_]item_bases.Kind{ .ring, .boots, .axe }) |kind| _ = g.sim.ground.add(.{ .item = .{ .kind = kind, .mods = .{ if (kind == .axe) .{ .kind = .strength, .value = 3 } else null, null, null, null } }, .at = bag });
    _ = g.sim.ground.gold(bag, BAG_GOLD);
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
    game.character.characterCommand(g, .close);
    if (g.sim.gold != BAG_GOLD) return error.BagGoldUntaken;
    game.heroStep(g, .e, 0);
    game.harness.drawnOut(g);
    if (g.mode != .play or g.sim.gold != BAG_GOLD or g.sim.ground.coin_n != 1) return error.ChestRevealMismatch;
    try capture(g, target, SHOTS_DIR ++ "/loot-chest-revealed.png");
    game.heroStep(g, .e, 0);
    game.harness.drawnOut(g);
    if (g.mode != .pause or g.character.page != .loot or g.sim.gold != BAG_GOLD or g.sim.ground.coin_n != 1) return error.ChestLootUnopened;
    try capture(g, target, SHOTS_DIR ++ "/loot-chest.png");
    game.character.characterCommand(g, .close);
    try capture(g, target, SHOTS_DIR ++ "/loot-chest-left.png");
    game.character.openLoot(g, chest);
    game.character.characterCommand(g, .take_all);
    game.harness.drawnOut(g);
    if (g.sim.ground.n != 3 or g.sim.inventory.n != 1 or g.sim.gold < BAG_GOLD + loot.CHEST_GOLD.lo or g.sim.ground.coin_n != 0 or g.sim.lv.at(chest) != .chest_open) return error.LootContainerMismatch;
    try capture(g, target, SHOTS_DIR ++ "/loot-chest-empty.png");
    for (0..inventory.BAG_MAX - g.sim.inventory.n) |_| _ = g.sim.inventory.add(.{ .kind = .cap });
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

    game.harness.grassArena(g, .{ .x = 20, .y = 20 }, &.{chest});
    g.sim.loot_rng = game.harness.lootRng(true);
    game.settle(g);
    game.harness.slay(g, game.harness.foeId(0), g.sim.heroActor().?.at);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-before.png");
    game.harness.drawnOut(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-dropped.png");
    game.character.openLoot(g, chest);
    try capture(g, target, SHOTS_DIR ++ "/loot-foe-blue.png");

    game.harness.grassArena(g, .{ .x = 20, .y = 20 }, &.{});
    _ = g.sim.ground.gold(bag, BAG_GOLD);
    game.settle(g);
    try capture(g, target, SHOTS_DIR ++ "/loot-gold-only-ground.png");
    game.heroStep(g, .w, 0);
    game.harness.drawnOut(g);
    if (g.mode != .play or g.sim.gold != BAG_GOLD or g.sim.ground.coin_n != 0) return error.GoldAutoLootMismatch;
    try capture(g, target, SHOTS_DIR ++ "/loot-gold-only.png");
}

pub fn captureLevelUp(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(LEVEL_UP_DIR);
    inline for (.{ .{ .name = "day", .hour = day.NOON }, .{ .name = "night", .hour = NIGHT } }) |scene| {
        poseForest(g);
        studyAt(g, true, scene.hour);
        g.st = .{ .device = .keys };
        g.pic.settleXp(&g.sim);
        try capture(g, target, LEVEL_UP_DIR ++ "/" ++ scene.name ++ "-before.png");
        _ = g.sim.growth.gain(@intCast(g.sim.growth.needed()));
        game.update(g, 0);
        var elapsed: f32 = 0;
        inline for (.{ 0.12, 0.4, 0.9, 1.5, 2.1 }, 0..) |time, i| {
            game.update(g, time - elapsed);
            elapsed = time;
            try capture(g, target, std.fmt.comptimePrint(LEVEL_UP_DIR ++ "/{s}-{d}.png", .{ scene.name, i }));
        }
    }
}

pub fn captureCharacter(g: *game.Game) !void {
    const w = try heapAtlas();
    defer dropAtlas(g, w);
    const shot = try target720(g);
    defer shot.close(g);
    const target = shot.target;
    spar.author(w, .slime);
    g.sim.class = heroes.DEFAULT;
    game.beginMapAt(g, w, w.start, SHOT_SEED);
    _ = g.sim.growth.gain(100);
    _ = g.sim.inventory.add(game.harness.affixed(.cap, .{ .kind = .life, .value = 3 }));
    try g.sim.inventory.equip(0, .helm, g.sim.growth.attributes(g.sim.class));
    _ = g.sim.inventory.add(game.harness.affixed(.bow, .{ .kind = .dexterity, .value = 2 }));
    try g.sim.inventory.equip(0, .right_hand, g.sim.growth.attributes(g.sim.class));
    _ = g.sim.inventory.add(.{ .kind = .helmet, .mods = .{ .{ .kind = .life, .value = 6 }, .{ .kind = .mana, .value = 2 }, null, null } });
    _ = g.sim.inventory.add(game.harness.affixed(.ring, .{ .kind = .strength, .value = 3 }));
    _ = g.sim.inventory.add(.{ .kind = .leather });
    _ = g.sim.ground.add(.{ .item = .{ .kind = .amulet }, .at = g.sim.heroActor().?.at });
    g.sim.log.push(.event, "Archer enters the old ruins.", .{});
    g.sim.log.push(.damage, "Archer shoots the rat for 3.", .{});
    g.sim.log.push(.danger, "The rat bites Archer for 2.", .{});
    g.sim.log.push(.recovery, "Archer recovers 4 life.", .{});
    g.sim.log.push(.loot, "Archer picks up 8 gold.", .{});
    g.sim.log.push(.event, "Archer opens the chest.", .{});
    g.sim.log.push(.loot, "Picked up iron helm.", .{});
    g.sim.log.push(.progress, "Level 3: +2 passive, +2 active points.", .{});
    g.sim.log.push(.damage, "Archer shoots the slime for 4.", .{});
    g.sim.log.push(.danger, "The slime hits Archer for 2.", .{});
    rewards.noticeItems(&g.sim, g.sim.heroActor().?.at);
    game.syncStats(g);
    game.harness.drawnOut(g);
    g.back = .editor;
    try capture(g, target, SHOTS_DIR ++ "/arena.png");
    game.character.openCharacter(g);
    inline for (book.PAGES) |page| {
        g.character.choose(page);

        if (page == .passives) g.character.cursor = passives.start(g.sim.class);
        if (page == .equipment) g.character.cursor = @intFromEnum(item_bases.Slot.helm);
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
        g.sim.inventory.gear.slots.set(.left_ring, game.harness.affixed(.ring, .{ .kind = .mana, .value = 3 }));
        g.sim.inventory.gear.slots.set(.right_ring, game.harness.affixed(.ring, .{ .kind = .dexterity, .value = 3 }));
        g.character.cursor = 1;
        g.character.destination_index = 0;
        try capture(g, target, SHOTS_DIR ++ "/item-ring-left.png");
        g.character.destination_index = 1;
        try capture(g, target, SHOTS_DIR ++ "/item-ring-right.png");
        g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = .sling });
        g.sim.inventory.gear.slots.set(.left_hand, game.harness.affixed(.buckler, .{ .kind = .life, .value = 6 }));
        _ = g.sim.inventory.add(.{ .kind = .crossbow, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .mana, .value = 2 }, null, null } });
        g.character.cursor = bag_n;
        g.character.destination_index = 0;
        try capture(g, target, SHOTS_DIR ++ "/item-two-handed.png");
        const class = g.sim.class;
        defer g.sim.class = class;
        g.sim.class = .knight;
        g.sim.inventory.gear.slots.set(.left_hand, null);
        g.character.choose(.equipment);

        inline for ([_]item_bases.Kind{ .axe, .greatclub, .greatsword }) |kind| {
            g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = kind });
            g.character.cursor = @intFromEnum(item_bases.Slot.right_hand);
            try capture(g, target, SHOTS_DIR ++ "/item-" ++ @tagName(kind) ++ "-equipped.png");
        }
        g.character.cursor = @intFromEnum(item_bases.Slot.left_hand);
        try capture(g, target, SHOTS_DIR ++ "/item-offhand-occupied.png");
    }
    {
        const carried = g.sim.inventory;
        defer g.sim.inventory = carried;
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

            g.character.cursor = passives.start(g.sim.class);
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
            const described = if (class == .wizard) skillbar.Act.frost_nova else progress.skills(class)[0].act;
            g.character.cursor = skillCursor(class, described);
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-description.png");
            g.sim.growth.ranks.set(described, 2);
            try capture(g, target, SHOTS_DIR ++ "/tree-skills-" ++ @tagName(class) ++ "-upgrade.png");
            if (class == .archer) {
                g.character.cursor = skillCursor(class, .burning_arrow);
                g.sim.growth.ranks.set(.burning_arrow, 2);
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
        const branch = passives.branchFirst(.warrior_life);
        for (branch..branch + passives.PER_BRANCH - 1) |i| _ = g.sim.growth.allocate(i);
        const bridge = passives.bridgeFirst(.warrior_rogue);
        _ = g.sim.growth.allocate(bridge);
        g.character.choose(.passives);

        g.character.cursor = branch + passives.PER_BRANCH - 1;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-capstone.png");
        g.character.zoom = 2.2;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-zoom.png");
        g.character.zoom = 1;
        g.character.cursor = branch + 1;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-interest.png");
        g.character.cursor = passives.bridgeFirst(.warrior_rogue);
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-bridge.png");
        g.sim.growth.passive_points = 0;
        g.character.cursor = branch + passives.PER_BRANCH - 1;
        try capture(g, target, SHOTS_DIR ++ "/tree-passives-no-points.png");
    }
    {
        const device = g.st.device;
        defer g.st.device = device;
        inline for (.{ game.WINDOW, game.SCREEN_1080 }) |size| {
            const large = try targetAt(g, size);
            defer large.close(g);
            g.st.device = .keys;
            inline for (book.PAGES) |page| {
                g.character.choose(page);
                try capture(g, large.target, SHOTS_DIR ++ "/character-" ++ @tagName(page) ++ "-" ++ std.fmt.comptimePrint("{d}", .{size.x}) ++ ".png");
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
    for (std.enums.values(item_bases.Kind)) |kind| _ = g.sim.inventory.add(.{ .kind = kind });
    g.mode = .pause;
    g.pause_page = .character;
    g.character.open();
    g.character.choose(.inventory);

    inline for ([_]item_bases.Kind{ .crossbow, .dagger, .staff, .wand, .tome, .orb, .buckler, .shield, .totem, .ash_wand, .rime_wand, .storm_wand, .hunting_bow, .war_bow, .circlet, .flask_belt, .robes }) |kind| {
        g.character.cursor = @intFromEnum(kind);
        try capture(g, target, SHOTS_DIR ++ "/item-" ++ @tagName(kind) ++ ".png");
    }
    g.sim.inventory.bag[@intFromEnum(item_bases.Kind.axe)].mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .mana, .value = 2 }, null, null };
    g.character.cursor = @intFromEnum(item_bases.Kind.axe);
    try capture(g, target, SHOTS_DIR ++ "/item-axe-magic.png");
}

fn skillCursor(class: heroes.Class, act: skillbar.Act) usize {
    for (progress.skills(class), 0..) |s, i| if (s.act == act) return i;
    unreachable;
}

pub fn captureHud(g: *game.Game) !void {
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
            body.status = .initDefault(0, .{ .bleeding = bleeding.TURNS, .burning = burning.TURNS, .chilled = glacial.TURNS - 1, .shocked = 2, .sundered = 3, .blinded = 1, .confused = 2, .enfeebled = 2, .maimed = 3 });
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
