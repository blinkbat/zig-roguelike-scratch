const std = @import("std");
const affixes = @import("../../play/affixes.zig");
const ground_items = @import("../../play/ground_items.zig");
const inventory = @import("../../play/inventory.zig");
const item_bases = @import("../../play/item_bases.zig");
const items = @import("../../play/items.zig");
const loot = @import("../../play/loot.zig");
const consumable = @import("../../play/consumable.zig");
const progress = @import("../../play/progress.zig");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const menu = @import("../../ui/menu.zig");
const book = @import("../../ui/book.zig");
const heroes = @import("../../play/hero.zig");
const actor = @import("../../play/actor.zig");
const skillbar = @import("../../play/skillbar.zig");
const day = @import("../../map/day.zig");
const scene = @import("../scene.zig");
const character = @import("../character.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const attacks = @import("../attacks.zig");
const combat = @import("../combat.zig");
const overlay = @import("../overlay.zig");
const gas = @import("../../map/gas.zig");
const flask = @import("../../play/flask.zig");
const light = @import("../../gfx/light.zig");
const juke = @import("../../play/juke.zig");
const blink = @import("../../play/blink.zig");
const P = mathx.P;
const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;

const TWO_ROOMS_SEED: u64 = 123;

test "rare chest and foe drops keep their names and mods through pickup and dropping" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(.{ .x = 1, .y = 0 });
    for ([_]bool{ false, true }) |foe| {
        harness.arena(g, from, &.{});
        var expected: ?items.Item = null;
        for (0..10000) |seed| {
            var rng = mathx.Rng.init(seed);
            const candidate = if (foe) loot.foeLoot(&rng, 0).item else items.roll(&rng, 0);
            if (candidate) |it| if (it.rarity() == .rare) {
                expected = it;
                g.sim.loot_rng = mathx.Rng.init(seed);
                break;
            };
        }
        try std.testing.expect(expected != null);
        if (foe) {
            const rat = harness.spawnAt(g, .rat, at, false);
            game.settle(g);
            harness.slay(g, rat, from);
            try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
        } else {
            g.sim.lv.set(at, .chest);
            try std.testing.expect(game.combat.openChest(g, at));
        }
        try std.testing.expectEqualDeep(expected.?, g.sim.ground.drops[0].item);
        harness.drawnOut(g);
        game.character.openLoot(g, at);
        harness.press(g, CONFIRM);
        harness.drawnOut(g);
        try std.testing.expectEqual(@as(usize, 1), g.sim.inventory.n);
        try std.testing.expectEqualDeep(expected.?, g.sim.inventory.bag[0]);
        game.character.openCharacter(g);
        game.character.characterCommand(g, .{ .drop = 0 });
        harness.drawnOut(g);
        try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
        try std.testing.expectEqualDeep(expected.?, g.sim.ground.drops[0].item);
    }
}

test "spoils applies to chest and foe quality and every gold pickup route" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(.{ .x = 1, .y = 0 });
    harness.arena(g, from, &.{});
    g.sim.inventory.gear.slots.set(.left_ring, harness.affixed(.ring, .{ .kind = .spoils, .value = 25 }));
    var magic: usize = 0;
    for (0..100) |seed| {
        g.sim.ground = .{};
        g.sim.lv.set(at, .chest);
        g.sim.loot_rng = mathx.Rng.init(seed);
        var expected_rng = g.sim.loot_rng;
        const expected = items.roll(&expected_rng, 25);
        try std.testing.expect(game.combat.openChest(g, at));
        try std.testing.expectEqualDeep(expected, g.sim.ground.drops[0].item);
        if (expected.magical()) magic += 1;
    }
    try std.testing.expect(magic > 0 and magic < 100);
    g.sim.ground = .{};
    g.sim.loot_rng = harness.lootRng(true);
    var expected_rng = g.sim.loot_rng;
    const expected = loot.foeLoot(&expected_rng, 25);
    const rat = harness.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, false);
    harness.slay(g, rat, from);
    try std.testing.expectEqualDeep(expected.item.?, g.sim.ground.drops[0].item);
    try std.testing.expectEqual(expected.gold, g.sim.ground.coins[0].amount);
    harness.drawnOut(g);
    for (0..3) |route| {
        g.sim.ground = .{};
        g.sim.gold = 0;
        if (!g.sim.heroActor().?.at.eq(from)) g.sim.pool.move(&g.sim.lv, g.sim.hero, from);
        g.sim.lv.set(at, if (route == 2) .chest_open else .floor);
        try std.testing.expect(g.sim.ground.gold(at, 20));
        if (route == 0) {
            harness.nudge(g, .e);
            try std.testing.expectEqual(@as(i32, 20), g.pic.gold_taken.?.amount);
        } else {
            try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .cap }, .at = at }));
            harness.pressInteract(g);
            try std.testing.expectEqual(book.Page.loot, g.character.page);
            if (route == 1) g.character.cursor = 1;
            harness.press(g, if (route == 1) CONFIRM else menu.CHANGE);
        }
        try std.testing.expectEqual(@as(i32, 25), g.sim.gold);
        try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
        harness.drawnOut(g);
        if (g.mode == .pause) harness.press(g, BACK);
        harness.drawnOut(g);
    }
}

fn runTwoRooms(g: *game.Game, w: *atlas.Atlas) usize {
    const b = harness.twoRooms(w);
    game.beginMapAt(g, w, w.start, TWO_ROOMS_SEED);
    return b;
}

test "a kicked barrel breaks for gold where it stood, and the archer stays put" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 21, .y = 20 };
    g.sim.lv.putBarrel(at);
    g.sim.loot_rng = harness.barrelRng(false);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.n);
    try std.testing.expect(!g.sim.lv.hasBarrel(at));
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try harness.expectWithin(g.sim.ground.coins[0].amount, loot.BARREL_GOLD.lo, loot.BARREL_GOLD.hi);
    try std.testing.expectEqual(P{ .x = 20, .y = 20 }, g.sim.heroActor().?.at);
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.drawnOut(g);
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    try std.testing.expect(g.pic.pileShown(&g.sim, g.sim.ground.coins[0]) != null);
    harness.nudge(g, .e);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try harness.expectWithin(g.sim.gold, loot.BARREL_GOLD.lo, loot.BARREL_GOLD.hi);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
}

test "a broken barrel sometimes leaves a white item in a bag with its gold, unseen until the break is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 21, .y = 20 };
    g.sim.lv.putBarrel(at);
    g.sim.loot_rng = harness.barrelRng(true);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
    try std.testing.expectEqual(items.Rarity.normal, g.sim.ground.drops[0].item.rarity());
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.drawnOut(g);
    try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
}

test "a chest first bump reveals loot and stops held walking; the next enters and opens loot" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    harness.arena(g, from, &.{});
    g.sim.lv.set(at, .chest);
    const minute = g.sim.clock.minute;
    try std.testing.expectEqual(game.Move.open, game.heroMove(g, .e));
    try std.testing.expect(!g.sim.lv.walkable(at));
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(grid.Tile.chest_open, g.sim.lv.at(at));
    try std.testing.expectEqual(from, g.sim.heroActor().?.at);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try harness.expectWithin(g.sim.ground.coins[0].amount, loot.CHEST_GOLD.lo, loot.CHEST_GOLD.hi);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
    try std.testing.expect(loot.CHEST_GOLD.lo > loot.BARREL_GOLD.hi);
    try std.testing.expect(g.pic.glide[g.sim.heroSlot().?].bump == null);
    const gold = g.sim.ground.coins[0].amount;
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    harness.walkFrame(g, 0, null);
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(at, g.character.loot_at);
    try std.testing.expectEqual(minute + 2 * day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
    harness.press(g, menu.CHANGE);
    harness.drawnOut(g);
    try std.testing.expectEqual(gold, g.sim.gold);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(usize, 1), g.sim.inventory.n);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.n);
    harness.nudge(g, .w);
    harness.nudge(g, .e);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(gold, g.sim.gold);
    try std.testing.expectEqual(grid.Tile.chest_open, g.sim.lv.at(at));
}

test "ground pressure preserves closed chest rewards and reserves every possible foe drop" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    const chest = at.add(.{ .x = 1, .y = 0 });
    g.sim.lv.set(chest, .chest);
    for (0..ground_items.GROUND_MAX - actor.MAX) |_| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    const before = g.sim.clock;
    const rng = g.sim.loot_rng;
    g.sim.heroActor().?.tactics.guard = 1;
    g.sim.heroActor().?.tactics.overwatch = .e;
    const tactics = g.sim.heroActor().?.tactics;
    game.heroStep(g, .e, 0);
    try std.testing.expectEqualDeep(before, g.sim.clock);
    try std.testing.expectEqualDeep(rng, g.sim.loot_rng);
    try std.testing.expectEqualDeep(tactics, g.sim.heroActor().?.tactics);
    try std.testing.expect(g.sim.lv.at(chest).opened() != null);
    for (0..actor.MAX) |_| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expectEqual(ground_items.GROUND_MAX, g.sim.ground.n);
}

test "new runs gate class skills; underfoot and adjacent loot commit exactly one turn; gold waits for the loot to close" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for (heroes.CLASSES) |c| {
        g.sim.class = c;
        game.begin(g, 123);
        for (progress.skills(c)) |s| try std.testing.expectEqual(s.initial, g.sim.growth.unlocked(s.act));
        for (skillbar.EVERY_SLOT) |slot| {
            if (g.bar.at(slot)) |act| try std.testing.expect(g.sim.growth.unlocked(act));
        }
    }
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const at = g.sim.heroActor().?.at;
    try std.testing.expect(g.sim.ground.add(.{ .item = harness.affixed(.cap, .{ .kind = .life, .value = 6 }), .at = at }));
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at.add(.{ .x = 1, .y = 0 }) }));
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .boots }, .at = at.add(.{ .x = 2, .y = 0 }) }));
    const clock = g.sim.clock;
    harness.pressInteract(g);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(clock, g.sim.clock);
    var nearby: game.NearbyBuf = undefined;
    try std.testing.expectEqual(@as(usize, 2), character.nearbyOf(g, &nearby).len);
    character.characterCommand(g, .{ .pickup = 0 });
    try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(usize, 1), g.sim.inventory.n);
    harness.drawnOut(g);
    const hp = g.sim.heroActor().?.hp;
    const minute = g.sim.clock.minute;
    character.characterCommand(g, .{ .equip = .{ .index = 0, .slot = .helm } });
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
    try std.testing.expectEqual(hp + 6, g.sim.heroActor().?.max);
    harness.drawnOut(g);
    try std.testing.expect(g.sim.ground.gold(at.add(.{ .x = 1, .y = 0 }), 17));
    const before = g.sim.clock.minute;
    harness.press(g, BACK);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n - 1);
    harness.drawnOut(g);
    var listed: game.NearbyBuf = undefined;
    try std.testing.expectEqual(@as(i32, 17), character.bookView(g, &listed).loot_gold);
    try std.testing.expectEqual(@as(usize, 1), character.bookView(g, &listed).nearby.len);
    harness.press(g, BACK);
    try std.testing.expectEqual(@as(i32, 17), g.sim.gold);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.n);
}

test "walking onto a bag opens only its loot and can leave every item behind" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.sim.name = heroes.Name.of("Arwen");
    g.sim.log = .{};
    const at = P{ .x = 21, .y = 20 };
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .cap }, .at = at }));
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .boots }, .at = .{ .x = 22, .y = 20 } }));
    const before = g.sim.clock.minute;
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 2), g.sim.log.n);
    try std.testing.expectEqualStrings("Arwen steps over leather cap.", g.sim.log.line(1).?);
    try std.testing.expectEqualStrings("Arwen steps over copper ring.", g.sim.log.line(0).?);
    try std.testing.expectEqual(@as(usize, 2), g.sim.log.held);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(@as(usize, 3), g.sim.ground.n);
    try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(at, g.character.loot_at);
    try std.testing.expectEqual(@as(usize, 2), character.bookView(g, &g.nearby).nearby.len);
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(usize, 0), g.sim.log.held);
    for (0..30) |_| game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(usize, 2), g.sim.log.n);
    for (0..inventory.BAG_MAX) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .cap }));
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(@as(usize, 3), g.sim.ground.n);
    harness.press(g, BACK);
    g.sim.lv.set(.{ .x = 22, .y = 20 }, .wall);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 2), g.sim.log.n);
    harness.nudge(g, .w);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 4), g.sim.log.n);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(usize, 3), g.sim.ground.n);
}

test "consumables lie in a bag, list in its loot, stack when taken and stay put once their stack is full" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 21, .y = 20 };
    for ([_]consumable.Kind{ .bandage, .bandage, .frost_vial }) |k| try std.testing.expect(g.sim.ground.addSupply(.{ .kind = k, .at = at }));
    try std.testing.expect(g.sim.ground.bagged(at) and !g.sim.ground.hasItems(at));
    try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.nudge(g, .e);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    const view = character.bookView(g, &g.nearby);
    try std.testing.expectEqual(@as(usize, 3), view.nearby.len);
    try std.testing.expectEqual(@as(?consumable.Kind, .bandage), view.nearby[0].supplyOf());
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(u8, 1), g.sim.inventory.stacks.get(.bandage));
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.supply_n);
    g.sim.inventory.stacks.set(.bandage, consumable.STACK_MAX);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(u8, 1), g.sim.inventory.stacks.get(.frost_vial));
    try std.testing.expectEqual(consumable.STACK_MAX, g.sim.inventory.stacks.get(.bandage));
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.supply_n);
    try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
}

test "interact pressed mid-turn waits for quiet instead of queuing its button's skill; the turn's log lines wait too" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = g.sim.heroActor().?.at }));
    g.pic.busy = game.GLIDE_S;
    g.sim.log.say("Said as the turn resolved.", .{});
    harness.pressInteract(g);
    try std.testing.expectEqual(@as(?game.Queued, .interact), g.pending);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(usize, 1), g.sim.log.held);
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Queued, .interact), g.pending);
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(@as(usize, 0), g.sim.log.held);
    harness.drawnOut(g);
    game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(usize, 0), g.sim.log.held);
}

test "foes with items drop one bag at their presented death and gold stays with the items" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    for ([_]bool{ false, true }) |magic| {
        const rolls = harness.lootRng(magic);
        for (std.enums.values(actor.Kind)) |kind| {
            if (!kind.foe() or actor.row(kind).disguised) continue;
            harness.arena(g, from, &.{});
            const id = harness.spawnAt(g, kind, at, false);
            game.settle(g);
            g.sim.loot_rng = rolls;
            harness.slay(g, id, from);
            try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
            try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
            try std.testing.expectEqual(magic, g.sim.ground.drops[0].item.magical());
            try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
            try std.testing.expect(g.pic.pileShown(&g.sim, g.sim.ground.coins[0]) == null);
            harness.drawnOut(g);
            try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
            try std.testing.expect(g.pic.pileShown(&g.sim, g.sim.ground.coins[0]) != null);
            const gold = g.sim.ground.coins[0].amount;
            harness.pressInteract(g);
            try std.testing.expectEqual(book.Page.loot, g.character.page);
            try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
            try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
            try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
            harness.press(g, CONFIRM);
            try std.testing.expectEqual(@as(usize, 1), g.sim.inventory.n);
            try std.testing.expectEqual(magic, g.sim.inventory.bag[0].magical());
            try std.testing.expectEqual(gold, g.sim.gold);
            try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
            try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
            try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
        }
    }
}

test "a death on a drawn gold pile adds its gold when it lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    harness.arena(g, from, &.{});
    const rolls = harness.lootRng(null);
    var was: i32 = 0;
    for (0..2) |_| {
        const id = harness.spawnAt(g, .rat, at, false);
        game.settle(g);
        g.sim.loot_rng = rolls;
        was = if (g.sim.ground.coin_n > 0) g.sim.ground.coins[0].amount else 0;
        harness.slay(g, id, from);
        const drawn = g.pic.pileShown(&g.sim, g.sim.ground.coins[0]);
        try std.testing.expectEqual(was, if (drawn) |pile| pile.amount else 0);
        harness.drawnOut(g);
        try std.testing.expectEqual(g.sim.ground.coins[0].amount, g.pic.pileShown(&g.sim, g.sim.ground.coins[0]).?.amount);
        try std.testing.expectEqual(@as(usize, 0), scene.bagCells(g).count());
    }
}

test "loot groups each cell into one bag and takes only the selected container" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    const beside = at.add(mathx.Dir.e.delta());
    harness.arena(g, at, &.{});
    for ([_]item_bases.Kind{ .cap, .ring, .boots }) |kind| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .amulet }, .at = beside }));
    const hidden = at.add(.{ .x = 2, .y = 0 });
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .bow }, .at = hidden }));
    g.sim.lv.lit[grid.Level.idx(hidden)] = false;
    try std.testing.expectEqual(@as(usize, 2), scene.bagCells(g).count());
    const minute = g.sim.clock.minute;
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.nearby, g.character.page);
    try std.testing.expectEqual(@as(usize, 2), character.bookView(g, &g.nearby).nearby.len);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(at, g.character.loot_at);
    try std.testing.expectEqual(@as(usize, 3), character.bookView(g, &g.nearby).nearby.len);
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
    character.characterCommand(g, .{ .pickup = 3 });
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(usize, 1), g.sim.inventory.n);
    try std.testing.expectEqual(item_bases.Kind.cap, g.sim.inventory.bag[0].kind);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(usize, 3), g.sim.inventory.n);
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.n);
    try std.testing.expectEqual(item_bases.Kind.amulet, g.sim.ground.drops[0].item.kind);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
}

test "chest interactions reveal before browsing, closing collects gold and take all preserves excess items" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.sim.lv.set(at, .chest);
    for (0..inventory.BAG_MAX - 1) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .cap }));
    const minute = g.sim.clock.minute;
    harness.pressInteract(g);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(grid.Tile.chest_open, g.sim.lv.at(at));
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    const gold = g.sim.ground.coins[0].amount;
    try harness.expectWithin(gold, loot.CHEST_GOLD.lo, loot.CHEST_GOLD.hi);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    for ([_]item_bases.Kind{ .boots, .ring }) |kind| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
    harness.drawnOut(g);
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(inventory.BAG_MAX, g.sim.inventory.n);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.n);
    try std.testing.expect(g.character.message.n > 0);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    harness.press(g, BACK);
    try std.testing.expectEqual(gold, g.sim.gold);
    try std.testing.expectEqual(minute + 2 * day.TURN_MINUTES, g.sim.clock.minute);
    harness.drawnOut(g);
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(gold, g.sim.gold);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.n);
    _ = g.sim.inventory.remove(0);
    _ = g.sim.inventory.remove(0);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.n);
    try std.testing.expectEqual(grid.Tile.chest_open, g.sim.lv.at(at));
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(gold, g.sim.gold);
    harness.drawnOut(g);
    harness.nudge(g, .e);
    try std.testing.expectEqual(gold, g.sim.gold);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
}

test "gold-only drops auto-loot on movement with a full inventory and no modal" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    const other = from.add(mathx.Dir.w.delta());
    harness.arena(g, from, &.{});
    for (0..inventory.BAG_MAX) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .cap }));
    try std.testing.expect(g.sim.ground.gold(at, 37));
    try std.testing.expect(g.sim.ground.gold(other, 19));
    try std.testing.expect(g.sim.ground.gold(.{ .x = 60, .y = 20 }, 11));
    try std.testing.expectEqual(@as(usize, 0), scene.bagCells(g).count());
    const minute = g.sim.clock.minute;
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.nearby, g.character.page);
    try std.testing.expectEqual(@as(usize, 2), character.bookView(g, &g.nearby).nearby.len);
    try std.testing.expect(!character.lootReached(g, from, at));
    character.openLoot(g, at);
    try std.testing.expectEqual(book.Page.nearby, g.character.page);
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    g.sim.lv.lit[grid.Level.idx(at)] = false;
    character.characterCommand(g, .{ .take_gold = at });
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    g.sim.lv.lit[grid.Level.idx(at)] = true;
    harness.press(g, BACK);
    try std.testing.expectEqual(game.Move.step, game.heroMove(g, .e));
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(i32, 37), g.sim.gold);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(inventory.BAG_MAX, g.sim.inventory.n);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.coin_n);
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.drawnOut(g);
    harness.nudge(g, .w);
    harness.nudge(g, .w);
    try std.testing.expectEqual(@as(i32, 56), g.sim.gold);
    try std.testing.expectEqual(minute + 3 * day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
}

test "closing a mixed bag takes its gold for free even when no item fits" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    for (0..inventory.BAG_MAX) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .cap }));
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expect(g.sim.ground.gold(at, 37));
    character.openLoot(g, at);
    const minute = g.sim.clock.minute;
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
    try std.testing.expectEqual(inventory.BAG_MAX, g.sim.inventory.n);
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expect(g.character.message.n > 0);
    harness.press(g, BACK);
    try std.testing.expectEqual(@as(i32, 37), g.sim.gold);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    _ = g.sim.inventory.remove(0);
    character.openLoot(g, at);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
}

test "loot gold left while the step onto its bag is drawn is taken from the bag before the next walk starts" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expect(g.sim.ground.gold(at, 37));
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    g.st = .{ .pressed = .initOne(BACK) };
    game.update(g, mathx.TEST_DT);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(!g.pic.quiet() and g.loot_gold != null);
    g.st = .{ .walk = .e };
    game.update(g, mathx.TEST_DT);
    g.st = .{};
    var t: f32 = 0;
    while (t < 2 and g.sim.heroActor().?.at.eq(at)) : (t += mathx.TEST_DT) game.update(g, mathx.TEST_DT);
    try std.testing.expect(!g.sim.heroActor().?.at.eq(at));
    try std.testing.expectEqual(@as(i32, 37), g.sim.gold);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
}

test "loot gold left while the step onto its bag is drawn is taken there though the walk is held two cells on" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expect(g.sim.ground.gold(at, 37));
    g.st = .{ .walk = .e };
    game.update(g, 0);
    g.st = .{ .pressed = .initOne(BACK) };
    game.update(g, mathx.TEST_DT);
    const minute = g.sim.clock.minute;
    var t: f32 = 0;
    while (t < 3 and g.sim.clock.minute < minute + 2 * day.TURN_MINUTES) : (t += mathx.TEST_DT) {
        g.st = .{ .walk = .e };
        game.update(g, mathx.TEST_DT);
    }
    g.st = .{};
    try std.testing.expectEqual(@as(i32, 23), g.sim.heroActor().?.at.x);
    try std.testing.expectEqual(@as(i32, 37), g.sim.gold);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(?P, null), g.loot_gold);
}

test "a hero killed while a bag's loot is open takes none of its gold" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{at.add(.{ .x = 1, .y = 0 })});
    harness.wakeFoes(g);
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expect(g.sim.ground.gold(at, 37));
    character.openLoot(g, at);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    harness.setLife(g.sim.heroActor().?, 1, harness.TEST_HP);
    g.sim.rng = harness.foeAttacksRng(g, &.{.{ .id = harness.foeId(0), .lands = true }});
    game.combat.endTurn(g);
    try std.testing.expect(g.sim.heroActor() == null);
    harness.drawnOut(g);
    for (0..4) |_| game.update(g, mathx.TEST_DT);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
}

test "every pickup in one loot visit is one turn, spent however the loot closes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const exits = [_][]const u8{ "back", "tab key", "pad view" };
    for (exits, 0..) |_, exit| {
        g.sim.inventory = .{};
        for ([_]item_bases.Kind{ .cap, .ring, .boots }) |kind| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
        try std.testing.expect(g.sim.ground.gold(at, 5));
        character.openLoot(g, at);
        const minute = g.sim.clock.minute;
        harness.press(g, CONFIRM);
        harness.press(g, CONFIRM);
        try std.testing.expectEqual(@as(usize, 2), g.sim.inventory.n);
        try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
        try std.testing.expectEqual(book.Page.loot, g.character.page);
        try std.testing.expectEqual(minute, g.sim.clock.minute);
        switch (exit) {
            0 => harness.press(g, BACK),
            1 => {
                g.st = .{ .character_page = .inventory };
                game.update(g, 0);
            },
            else => {
                g.st = .{ .device = .xbox };
                g.st.pressed.insert(menu.PAUSE);
                game.update(g, 0);
            },
        }
        try std.testing.expect(!(g.mode == .pause and g.pause_page == .character and g.character.page == .loot));
        try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
        try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
        harness.drawnOut(g);
        try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
        g.mode = .play;
        g.sim.ground = .{};
    }
}

test "a chest left holding items or gold keeps its bag out of sight, and loose bags out of sight are not drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const chest = P{ .x = 60, .y = 20 };
    const loose = P{ .x = 60, .y = 22 };
    g.sim.lv.set(chest, .chest_open);
    for ([_]P{ chest, loose }) |p| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = p }));
    try std.testing.expect(!g.sim.lv.isLit(chest) and !g.sim.lv.isLit(loose));
    const bags = scene.bagCells(g);
    try std.testing.expect(bags.isSet(grid.Level.idx(chest)));
    try std.testing.expect(!bags.isSet(grid.Level.idx(loose)));
    g.sim.ground.n = 0;
    for ([_]P{ chest, loose }) |p| try std.testing.expect(g.sim.ground.gold(p, 17));
    const gold_bags = scene.bagCells(g);
    try std.testing.expect(gold_bags.isSet(grid.Level.idx(chest)));
    try std.testing.expect(!gold_bags.isSet(grid.Level.idx(loose)));
}

test "nearby loot checks stay inside the map at every edge and corner" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const edges = [_]P{
        .{ .x = 0, .y = 0 },          .{ .x = grid.W - 1, .y = 0 },
        .{ .x = 0, .y = grid.H - 1 }, .{ .x = grid.W - 1, .y = grid.H - 1 },
        .{ .x = 0, .y = grid.H / 2 }, .{ .x = grid.W - 1, .y = grid.H / 2 },
        .{ .x = grid.W / 2, .y = 0 }, .{ .x = grid.W / 2, .y = grid.H - 1 },
    };
    for (edges) |at| {
        harness.arena(g, at, &.{});
        g.sim.lv.set(at, .floor);
        game.settle(g);
        try std.testing.expect(!character.anyNearby(g));
        try std.testing.expect(g.sim.ground.gold(at, 5));
        var buf: game.NearbyBuf = undefined;
        const nearby = character.nearbyOf(g, &buf);
        try std.testing.expectEqual(@as(usize, 1), nearby.len);
        try std.testing.expectEqual(at, nearby[0].gold.at);
        try std.testing.expect(character.openNearby(g));
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
        try std.testing.expectEqual(@as(i32, 5), g.sim.gold);
    }
}

test "loot on a nearby door preserves both loot and travel choices" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    const door = P{ .x = 2, .y = 5 };
    for (1..4) |contents| {
        _ = runTwoRooms(g, w);
        if (contents & 1 != 0) try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = door }));
        if (contents & 2 != 0) try std.testing.expect(g.sim.ground.gold(door, 5));
        var buf: game.NearbyBuf = undefined;
        const nearby = character.nearbyOf(g, &buf);
        try std.testing.expectEqual(@as(usize, 2), nearby.len);
        var bags: usize = 0;
        var doors: usize = 0;
        for (nearby) |entry| switch (entry) {
            .bag => |at| {
                try std.testing.expectEqual(door, at);
                bags += 1;
            },
            .gold => |pile| {
                try std.testing.expectEqual(door, pile.at);
                try std.testing.expectEqual(@as(usize, 2), contents);
                bags += 1;
            },
            .door => |at| {
                try std.testing.expectEqual(door, at);
                doors += 1;
            },
            else => return error.UnexpectedNearbyEntry,
        };
        try std.testing.expectEqual(@as(usize, 1), bags);
        try std.testing.expectEqual(@as(usize, 1), doors);
        try std.testing.expect(character.openNearby(g));
        try std.testing.expectEqual(book.Page.nearby, g.character.page);
        try std.testing.expectEqual(g.sim.map.?.start.node, g.sim.node);
    }
}

test "a door is listed nearby only once no body is drawn on it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    _ = runTwoRooms(g, w);
    const door = P{ .x = 2, .y = 5 };
    const from = g.sim.heroActor().?.at;
    const rat = harness.spawnAt(g, .rat, door, false);
    try std.testing.expectEqual(@as(?atlas.Link, null), character.doorReached(g, from, door));
    g.sim.pool.move(&g.sim.lv, rat, .{ .x = 6, .y = 5 });
    g.pic.busy = game.GLIDE_S;
    try std.testing.expectEqual(@as(?atlas.Link, null), character.doorReached(g, from, door));
    harness.calm(g);
    g.pic.snapGlide(&g.sim.pool);
    try std.testing.expect(character.doorReached(g, from, door) != null);
}

test "the nearby list closes once a body takes the last door it listed" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    _ = runTwoRooms(g, w);
    try std.testing.expect(character.openNearby(g));
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    _ = harness.spawnAt(g, .rat, .{ .x = 2, .y = 5 }, false);
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
}

test "interact during door travel stays an interaction on arrival" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    const b = runTwoRooms(g, w);
    harness.nudge(g, .w);
    const minute = g.sim.clock.minute;
    try std.testing.expect(g.sim.travel != null);
    harness.pressInteract(g);
    try std.testing.expectEqual(@as(?game.Queued, .interact), g.pending);
    g.st = .{ .walk = .w };
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Queued, .interact), g.pending);
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.sim.node);
    game.update(g, mathx.FRAME_DT);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(book.Page.nearby, g.character.page);
    try std.testing.expectEqual(minute, g.sim.clock.minute);
}

test "travel and chest opening from the nearby list turn the hero toward them" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    _ = runTwoRooms(g, w);
    const at = g.sim.heroActor().?.at;
    const slot = g.sim.heroSlot().?;
    g.pic.facing[slot] = .right;
    character.characterCommand(g, .{ .travel = at.add(mathx.Dir.w.delta()) });
    try std.testing.expectEqual(actor.Facing.left, g.pic.facing[slot]);

    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const chest = P{ .x = 19, .y = 20 };
    g.sim.lv.set(chest, .chest);
    g.pic.facing[g.sim.heroSlot().?] = .right;
    character.characterCommand(g, .{ .open_loot = chest });
    try std.testing.expectEqual(grid.Tile.chest_open, g.sim.lv.at(chest));
    try std.testing.expectEqual(actor.Facing.left, g.pic.facing[g.sim.heroSlot().?]);
}

test "a door trip finishes behind Character opened during it, so item commands can act" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    const b = runTwoRooms(g, w);
    harness.nudge(g, .w);
    try std.testing.expect(g.sim.travel != null);
    g.st = .{ .character_page = .inventory };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.sim.node);
    try std.testing.expect(g.sim.travel == null);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(book.Page.inventory, g.character.page);
}

test "a pinned hero on the door it came through struggles there instead of going back" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    const b = runTwoRooms(g, w);
    harness.nudge(g, .w);
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.sim.node);
    const at = g.sim.heroAt().?;
    try std.testing.expect(character.doorReached(g, at, at) != null);
    g.sim.heroActor().?.pin.turns = 2;
    character.characterCommand(g, .{ .travel = at });
    try std.testing.expect(g.sim.travel == null);
    try std.testing.expect(std.mem.indexOf(u8, g.sim.log.line(0).?, "struggles") != null);
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.sim.node);
}

test "clicking the hero on the door it came through waits instead of going back" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    const b = runTwoRooms(g, w);
    harness.nudge(g, .w);
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.sim.node);
    const at = g.sim.heroAt().?;
    try std.testing.expect(character.doorReached(g, at, at) != null);
    var next = g.sim.clock;
    _ = next.turn();
    g.mouse.target = at;
    g.mouse.fresh = true;
    try std.testing.expect(game.mouseControls.step(g));
    try std.testing.expect(g.sim.travel == null);
    try std.testing.expectEqual(next, g.sim.clock);
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.sim.node);
}

test "inspect opened during a door trip opens, and the trip still finishes behind it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    const b = runTwoRooms(g, w);
    harness.nudge(g, .w);
    try std.testing.expect(g.sim.travel != null);
    harness.press(g, skillbar.INSPECT);
    try std.testing.expectEqual(game.Mode.inspect, std.meta.activeTag(g.mode));
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.sim.node);
    try std.testing.expect(g.sim.travel == null);
    try std.testing.expectEqual(game.Mode.inspect, std.meta.activeTag(g.mode));
}

test "an imbued weapon's hit brings its element's ailment and a resolute helm adds stun resistance" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    const rat = g.sim.pool.get(harness.foeId(0)).?;
    harness.toughen(rat);
    const h = g.sim.heroActor().?;
    for (affixes.IMBUES) |e| {
        g.sim.inventory.gear.slots.set(.right_hand, harness.affixed(.sword, .{ .kind = .imbue, .value = 100, .element = e }));
        var roll = attacks.heroMelee(&g.sim);
        roll.hit_checked = true;
        combat.wound(g, harness.foeId(0), roll, combat.SHOOT, .{ .from = h.at, .wait = 0.2 });
    }
    try std.testing.expect(rat.burn.turns > 0 and rat.chill.turns > 0 and rat.shock.turns > 0);
    try std.testing.expect(harness.logged(g, "catches fire") and harness.logged(g, "is chilled") and harness.logged(g, "is shocked"));
    const stun = g.sim.combatStats(h).statuses.get(.stun);
    g.sim.inventory.gear.slots.set(.helm, harness.affixed(.helmet, .{ .kind = .resolve, .value = 20 }));
    try std.testing.expectEqual(stun + 20, g.sim.combatStats(h).statuses.get(.stun));
}

test "a lantern widens what the hero's light shows at night" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    g.sim.outdoors = false;
    const edge = at.add(.{ .x = g.sim.heroRow().light + 1, .y = 0 });
    g.sim.see(at);
    try std.testing.expect(!g.sim.lv.isLit(edge));
    g.sim.inventory.gear.slots.set(.amulet, harness.affixed(.amulet, .{ .kind = .lantern, .value = 1 }));
    g.sim.see(at);
    try std.testing.expect(g.sim.lv.isLit(edge));
    try std.testing.expectEqual(light.carryR(g.sim.heroRow().light) + 1, light.carryR(g.sim.heroLight()));
}

test "a mask cuts the hero's gas harm and spares foes nothing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const harm = gas.harm(harness.TEST_HP);
    for ([_]i16{ 50, 100 }, [_]i32{ @divExact(harm, 2), 0 }) |mask, lost| {
        const at = P{ .x = 20, .y = 20 };
        harness.arena(g, at, &.{});
        const h = g.sim.heroActor().?;
        harness.toughen(h);
        g.sim.inventory.gear.slots.set(.helm, harness.affixed(.cap, .{ .kind = .masked, .value = mask }));
        g.sim.lv.addGas(at, harness.TEST_GAS * 10);
        game.settle(g);
        harness.use(g, .wait);
        try std.testing.expectEqual(harness.TEST_HP - lost, h.hp);
    }
}

test "stillness keeps a sleeping foe from noticing the hero until nearer" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const sight = actor.row(.rat).sight;
    for ([_]i16{ 0, 2 }, [_]bool{ true, false }) |still, wakes| {
        const at = P{ .x = 20, .y = 20 };
        harness.arena(g, at, &.{});
        if (still > 0) g.sim.inventory.gear.slots.set(.boots, harness.affixed(.boots, .{ .kind = .stillness, .value = still }));
        const id = harness.spawnAt(g, .rat, at.add(.{ .x = sight - 1, .y = 0 }), false);
        harness.use(g, .wait);
        try std.testing.expectEqual(wakes, g.sim.pool.get(id).?.awake);
    }
}

test "opportunist's blows land harder only on a pinned, chilled or maimed foe" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    const rat = g.sim.pool.get(harness.foeId(0)).?;
    const blow = attacks.Roll{ .dmg = 10, .hit_checked = true };
    g.sim.inventory.gear.slots.set(.gloves, harness.affixed(.gloves, .{ .kind = .opportunist, .value = 25 }));
    var dealt: [4]i32 = undefined;
    for (&dealt, 0..) |*d, i| {
        harness.setLife(rat, 50, 50);
        rat.pin.turns = @intFromBool(i == 1);
        rat.chill.turns = @intFromBool(i == 2);
        rat.maim.turns = @intFromBool(i == 3);
        d.* = attacks.resolve(&g.sim, .fromInt(harness.foeId(0)), blow, .chosen).?.hit.damage.dmg;
    }
    try std.testing.expectEqualSlices(i32, &.{ 10, 13, 13, 13 }, &dealt);
}

test "opportunist reads the foe as it stood before the blow pinned it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = g.sim.pool.get(harness.foeId(0)).?;
    g.sim.inventory.gear.slots.set(.gloves, harness.affixed(.gloves, .{ .kind = .opportunist, .value = 25 }));
    const h = g.sim.heroActor().?;
    var tries: usize = 0;
    while (rat.pin.turns == 0) : (tries += 1) {
        try std.testing.expect(tries < 50);
        harness.setLife(rat, 50, 50);
        rat.resilience = .{};
        combat.skillHit(g, harness.foeId(0), .{ .blow = .{ .physical = 10 } }, .pinning_shot, .{ .from = h.at, .wait = 0.2 });
    }
    try std.testing.expectEqual(@as(i32, 40), rat.hp);
}

test "an imbued ailment is resisted by its element's resistance" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .frost_wisp, .{ .x = 21, .y = 20 }, true);
    const wisp = g.sim.pool.get(id).?;
    harness.toughen(wisp);
    const h = g.sim.heroActor().?;
    g.sim.inventory.gear.slots.set(.right_hand, harness.affixed(.sword, .{ .kind = .imbue, .value = 100, .element = .cold }));
    var landed: usize = 0;
    for (0..20) |_| {
        var roll = attacks.heroMelee(&g.sim);
        roll.hit_checked = true;
        landed += @intFromBool(roll.dmg > 0);
        combat.wound(g, id, roll, combat.SHOOT, .{ .from = h.at, .wait = 0.2 });
    }
    try std.testing.expect(landed > 0);
    try std.testing.expectEqual(@as(u8, 0), wisp.chill.turns);
}

test "bounding boots stretch every movement skill's reach and nothing else" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const far = from.add(.{ .x = juke.RANGE + 1, .y = 0 });
    harness.arena(g, from, &.{});
    harness.aimAt(g, .juke, far);
    try std.testing.expectEqual(from, g.sim.heroActor().?.at);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    g.sim.inventory.gear.slots.set(.boots, harness.affixed(.boots, .{ .kind = .bounding, .value = 1 }));
    for (skillbar.ACTS) |a| try std.testing.expectEqual(a.reach() + @intFromBool(a.moves()), g.sim.reachOf(a));
    try std.testing.expect(skillbar.Act.juke.moves() and skillbar.Act.blink.moves() and skillbar.Act.charge.moves());
    var desc: [256]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, overlay.describe(g, .juke, &desc), "within 3 tiles") != null);
    try std.testing.expect(std.mem.indexOf(u8, overlay.describe(g, .charge, &desc), "foe 1-5 tiles away") != null);
    harness.aimAt(g, .juke, far);
    try std.testing.expectEqual(far, g.sim.heroActor().?.at);
}

test "alacrity shortens every cooldown it is spent on, never below a turn-taking skill's floor" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    g.sim.inventory.gear.slots.set(.amulet, harness.affixed(.amulet, .{ .kind = .alacrity, .value = 1 }));
    harness.aimAt(g, .juke, from.add(.{ .x = juke.RANGE, .y = 0 }));
    try std.testing.expectEqual(juke.COOLDOWN - 1, g.sim.cooldown.get(.juke));
    const growth = progress.State{};
    try std.testing.expectEqual(blink.COOLDOWN - 1, growth.cooldown(.blink, 1));
    try std.testing.expectEqual(@as(u8, 2), growth.cooldown(.blink, 9));
    try std.testing.expectEqual(@as(u8, 1), growth.cooldown(.juke, 9));
}

test "siphoning mana lands with the kill and draughts enlarge a mana drink" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    g.sim.inventory.gear.slots.set(.left_ring, harness.affixed(.ring, .{ .kind = .mana_on_kill, .value = 2 }));
    g.sim.inventory.gear.slots.set(.belt, harness.affixed(.belt, .{ .kind = .mana_flask, .value = 20 }));
    g.sim.mana = 0;
    g.pic.catchUp(&g.sim);
    harness.slay(g, harness.foeId(0), g.sim.heroActor().?.at);
    try std.testing.expectEqual(@as(i32, 2), g.sim.mana);
    try std.testing.expectEqual(@as(i32, 0), g.pic.manaShown(&g.sim));
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(i32, 2), g.pic.manaShown(&g.sim));
    const drink = flask.recovers(.mana, 0, g.sim.heroDraughts());
    var desc: [256]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, overlay.describe(g, .mana_flask, &desc), "Recover 12 mana") != null);
    harness.use(g, .mana_flask);
    try std.testing.expectEqual(drink - try std.math.divCeil(i32, drink, flask.TURNS), g.sim.flasks.get(.mana).left);
}

test "each kill's siphoned mana shows as its own death is drawn, not the turn's last" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 22, .y = 20 }, .{ .x = 20, .y = 22 } });
    g.sim.inventory.gear.slots.set(.left_ring, harness.affixed(.ring, .{ .kind = .mana_on_kill, .value = 2 }));
    g.sim.mana = 0;
    g.pic.catchUp(&g.sim);
    for ([_]u16{ harness.foeId(0), harness.foeId(1) }) |id| harness.slay(g, id, g.sim.heroActor().?.at);
    try std.testing.expectEqual(@as(i32, 4), g.sim.mana);
    try std.testing.expectEqual(@as(i32, 0), g.pic.manaShown(&g.sim));
    g.pic.pictured[harness.foeSlot(0)].hp = 0;
    try std.testing.expectEqual(@as(i32, 2), g.pic.manaShown(&g.sim));
}
