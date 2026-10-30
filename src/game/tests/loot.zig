const std = @import("std");
const items = @import("../../play/items.zig");
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
            const candidate = if (foe) items.foeLoot(&rng, 0).item else items.roll(&rng, 0);
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
    std.debug.print("rare loot: chest and foe generation, delayed foe bag, pickup and dropping preserve full item identity\n", .{});
}

test "spoils applies to chest and foe quality and every gold pickup route" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(.{ .x = 1, .y = 0 });
    harness.arena(g, from, &.{});
    g.sim.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .spoils, .value = 25 }, null, null, null } });
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
    const expected = items.foeLoot(&expected_rng, 25);
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
    std.debug.print("Spoils: 100 chest rolls, foe reward, walking coins, bag gold and chest Take all checked\n", .{});
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
    harness.nudge(g, .e);
    std.debug.print("kicked barrel: {d} gold auto-looted on the next step\n", .{g.sim.ground.coins[0].amount});
    try std.testing.expect(!g.sim.lv.hasBarrel(at));
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try harness.expectWithin(g.sim.ground.coins[0].amount, items.BARREL_GOLD.lo, items.BARREL_GOLD.hi);
    try std.testing.expectEqual(P{ .x = 20, .y = 20 }, g.sim.heroActor().?.at);
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.drawnOut(g);
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    try std.testing.expect(scene.pileShown(g, g.sim.ground.coins[0]) != null);
    harness.nudge(g, .e);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try harness.expectWithin(g.sim.gold, items.BARREL_GOLD.lo, items.BARREL_GOLD.hi);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
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
    try harness.expectWithin(g.sim.ground.coins[0].amount, items.CHEST_GOLD.lo, items.CHEST_GOLD.hi);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
    try std.testing.expect(items.CHEST_GOLD.lo > items.BARREL_GOLD.hi);
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
    std.debug.print("chest: first bump reveals, second enters loot without collecting; take all collects {d} gold and its item\n", .{gold});
}

test "ground pressure preserves closed chest rewards and reserves every possible foe drop" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    const chest = at.add(.{ .x = 1, .y = 0 });
    g.sim.lv.set(chest, .chest);
    for (0..items.GROUND_MAX - actor.MAX) |_| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
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
    try std.testing.expectEqual(items.GROUND_MAX, g.sim.ground.n);
    std.debug.print("full ground: chest, turn, Guard and Overwatch untouched, {d} foe rewards reserved\n", .{actor.MAX});
}

test "new runs gate class skills; underfoot and adjacent loot commit exactly one turn; gold waits for the loot to close" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for (heroes.CLASSES) |c| {
        g.sim.class = c;
        game.begin(g, 123);
        for (progress.skills(c)) |s| try std.testing.expectEqual(s.initial, g.sim.growth.unlocked(s.act));
        for (skillbar.SETS) |set| for (skillbar.SLOTS) |button| {
            if (g.bar.at(.{ .set = set, .button = button })) |act| try std.testing.expect(g.sim.growth.unlocked(act));
        };
    }
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const at = g.sim.heroActor().?.at;
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .cap, .mods = .{ .{ .kind = .life, .value = 6 }, null, null, null } }, .at = at }));
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
    g.character.cursor = 1;
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(i32, 17), g.sim.gold);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.n);
    harness.press(g, BACK);
    try std.testing.expectEqual(before + 2 * day.TURN_MINUTES, g.sim.clock.minute);
    std.debug.print("progression: 3 starter kits, one-turn item actions, no equip healing; gold row leaves items, its turn spent on close\n", .{});
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
    try std.testing.expectEqualStrings("Arwen steps over Leather cap.", g.sim.log.line(1).?);
    try std.testing.expectEqualStrings("Arwen steps over Copper ring.", g.sim.log.line(0).?);
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
    for (0..items.BAG_MAX) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .cap }));
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
    std.debug.print("bag bump: 2 selected items, one movement turn, full inventory can cancel and leave all 3 ground items behind\n", .{});
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
    std.debug.print("consumable bag: 3 listed, 1 taken singly, take all stacks the vial and leaves the bandage a full stack refuses\n", .{});
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
    std.debug.print("interact mid-turn: queued, opens loot without taking the item; held log line released on the quiet frame\n", .{});
}

test "foes with items drop one bag at their presented death and gold stays with the items" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    var cases: usize = 0;
    for ([_]bool{ false, true }) |magic| {
        const loot = harness.lootRng(magic);
        for (std.enums.values(actor.Kind)) |kind| {
            if (!kind.foe() or actor.row(kind).disguised) continue;
            harness.arena(g, from, &.{});
            const id = harness.spawnAt(g, kind, at, false);
            game.settle(g);
            g.sim.loot_rng = loot;
            harness.slay(g, id, from);
            try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
            try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
            try std.testing.expectEqual(magic, g.sim.ground.drops[0].item.magical());
            try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
            try std.testing.expect(scene.pileShown(g, g.sim.ground.coins[0]) == null);
            harness.drawnOut(g);
            try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
            try std.testing.expect(scene.pileShown(g, g.sim.ground.coins[0]) != null);
            const gold = g.sim.ground.coins[0].amount;
            harness.pressInteract(g);
            try std.testing.expectEqual(book.Page.loot, g.character.page);
            try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
            try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
            try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
            harness.press(g, CONFIRM);
            try std.testing.expectEqual(@as(usize, 1), g.sim.inventory.n);
            try std.testing.expectEqual(magic, g.sim.inventory.bag[0].magical());
            try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
            try std.testing.expectEqual(gold, g.sim.ground.coins[0].amount);
            harness.drawnOut(g);
            try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
            harness.press(g, CONFIRM);
            try std.testing.expectEqual(gold, g.sim.gold);
            try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
            try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
            try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
            cases += 1;
        }
    }
    std.debug.print("foe loot: {d} kind/rarity deaths, one bag delayed to impact, separate item and gold pickups close empty loot\n", .{cases});
}

test "a death on a drawn gold pile adds its gold when it lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    harness.arena(g, from, &.{});
    const loot = harness.lootRng(null);
    var was: i32 = 0;
    for (0..2) |_| {
        const id = harness.spawnAt(g, .rat, at, false);
        game.settle(g);
        g.sim.loot_rng = loot;
        was = if (g.sim.ground.coin_n > 0) g.sim.ground.coins[0].amount else 0;
        harness.slay(g, id, from);
        const drawn = scene.pileShown(g, g.sim.ground.coins[0]);
        try std.testing.expectEqual(was, if (drawn) |pile| pile.amount else 0);
        harness.drawnOut(g);
        try std.testing.expectEqual(g.sim.ground.coins[0].amount, scene.pileShown(g, g.sim.ground.coins[0]).?.amount);
        try std.testing.expectEqual(@as(usize, 0), scene.bagCells(g).count());
    }
    std.debug.print("a second death on a drawn pile: {d} gold stayed drawn until the blow landed\n", .{was});
}

test "loot groups each cell into one bag and takes only the selected container" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    const beside = at.add(mathx.Dir.e.delta());
    harness.arena(g, at, &.{});
    for ([_]items.Kind{ .cap, .ring, .boots }) |kind| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
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
    try std.testing.expectEqual(items.Kind.cap, g.sim.inventory.bag[0].kind);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(usize, 3), g.sim.inventory.n);
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.n);
    try std.testing.expectEqual(items.Kind.amulet, g.sim.ground.drops[0].item.kind);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    std.debug.print("loot: 3 items share one bag; browse is free, single take then take-all spend one turn as the emptied loot closes; adjacent and hidden loot preserved\n", .{});
}

test "chest interactions reveal before browsing, take all collects gold and preserves excess items" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.sim.lv.set(at, .chest);
    for (0..items.BAG_MAX - 1) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .cap }));
    const minute = g.sim.clock.minute;
    harness.pressInteract(g);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(grid.Tile.chest_open, g.sim.lv.at(at));
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    const gold = g.sim.ground.coins[0].amount;
    try harness.expectWithin(gold, items.CHEST_GOLD.lo, items.CHEST_GOLD.hi);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    for ([_]items.Kind{ .boots, .ring }) |kind| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
    harness.drawnOut(g);
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(items.BAG_MAX, g.sim.inventory.n);
    try std.testing.expectEqual(gold, g.sim.gold);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.n);
    try std.testing.expect(g.character.message.n > 0);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    harness.press(g, BACK);
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
    std.debug.print("chest loot: reveal then browse, take all collects gold and fitting items; full-bag retry is free, 2 excess items survive\n", .{});
}

test "gold-only drops auto-loot on movement with a full inventory and no modal" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    const other = from.add(mathx.Dir.w.delta());
    harness.arena(g, from, &.{});
    for (0..items.BAG_MAX) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .cap }));
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
    try std.testing.expectEqual(items.BAG_MAX, g.sim.inventory.n);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(usize, 2), g.sim.ground.coin_n);
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.drawnOut(g);
    harness.nudge(g, .w);
    harness.nudge(g, .w);
    try std.testing.expectEqual(@as(i32, 56), g.sim.gold);
    try std.testing.expectEqual(minute + 3 * day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.coin_n);
    std.debug.print("gold-only drops: 2 auto-looted by movement, no modal or extra turn, full inventory unchanged, distant gold preserved\n", .{});
}

test "take all collects gold from a mixed bag even when no item fits" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    for (0..items.BAG_MAX) |_| try std.testing.expect(g.sim.inventory.add(.{ .kind = .cap }));
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expect(g.sim.ground.gold(at, 37));
    character.openLoot(g, at);
    const minute = g.sim.clock.minute;
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(i32, 37), g.sim.gold);
    try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
    try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
    try std.testing.expectEqual(items.BAG_MAX, g.sim.inventory.n);
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expect(g.character.message.n > 0);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    _ = g.sim.inventory.remove(0);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    std.debug.print("mixed bag with full inventory: gold taken, item preserved, empty retry free; one freed slot takes the remaining item, one turn in all\n", .{});
}

test "every pickup in one loot visit is one turn, spent however the loot closes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const exits = [_][]const u8{ "back", "tab key", "pad view" };
    for (exits, 0..) |_, exit| {
        g.sim.inventory = .{};
        for ([_]items.Kind{ .cap, .ring, .boots }) |kind| try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
        try std.testing.expect(g.sim.ground.gold(at, 5));
        character.openLoot(g, at);
        const minute = g.sim.clock.minute;
        harness.press(g, CONFIRM);
        harness.press(g, CONFIRM);
        g.character.cursor = 1;
        harness.press(g, CONFIRM);
        try std.testing.expectEqual(@as(usize, 2), g.sim.inventory.n);
        try std.testing.expectEqual(@as(usize, 0), g.sim.ground.coin_n);
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
        try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
        harness.drawnOut(g);
        try std.testing.expectEqual(minute + day.TURN_MINUTES, g.sim.clock.minute);
        g.mode = .play;
        g.sim.ground = .{};
    }
    std.debug.print("one loot visit: 2 items and gold for one turn, closed by {s}, {s} and {s}\n", .{ exits[0], exits[1], exits[2] });
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
    std.debug.print("nearby loot: empty checks and underfoot gold at all 4 edges and 4 corners\n", .{});
}

test "loot on a nearby door preserves both loot and travel choices" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
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
    std.debug.print("nearby doors: items, gold and mixed bags retain their own entry and one travel action\n", .{});
}

test "a door is listed nearby only once no body is drawn on it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
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
    const w = try std.testing.allocator.create(atlas.Atlas);
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
    const w = try std.testing.allocator.create(atlas.Atlas);
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
    std.debug.print("door interact: survives travel and walking repeats, opens nearby without an extra turn\n", .{});
}

test "travel and chest opening from the nearby list turn the hero toward them" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
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
    std.debug.print("nearby travel and chest: hero turned {s} toward each\n", .{@tagName(g.pic.facing[g.sim.heroSlot().?])});
}

test "a door trip finishes behind Character opened during it, so item commands can act" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
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
    std.debug.print("door behind Character: arrived at node {d} with the inventory still open\n", .{g.sim.node});
}

test "a pinned hero on the door it came through struggles there instead of going back" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
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
    try std.testing.expect(std.mem.endsWith(u8, g.sim.log.line(0).?, "is pinned and struggles."));
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.sim.node);
}

test "inspect opened during a door trip opens, and the trip still finishes behind it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
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
    std.debug.print("inspect during a door trip: arrived at node {d} with inspect open\n", .{g.sim.node});
}
