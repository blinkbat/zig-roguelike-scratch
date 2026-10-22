const std = @import("std");
const items = @import("../../play/items.zig");
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
    g.lv.putBarrel(at);
    harness.nudge(g, .e);
    std.debug.print("kicked barrel: {d} gold on the ground\n", .{g.ground.coins[0].amount});
    try std.testing.expect(!g.lv.hasBarrel(at));
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try harness.expectWithin(g.ground.coins[0].amount, items.BARREL_GOLD.lo, items.BARREL_GOLD.hi);
    try std.testing.expectEqual(P{ .x = 20, .y = 20 }, g.heroActor().?.at);
    harness.nudge(g, .e);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    try harness.expectWithin(g.gold, items.BARREL_GOLD.lo, items.BARREL_GOLD.hi);
    try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
}

test "a chest first bump reveals loot and stops held walking; the next enters and opens loot" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    harness.arena(g, from, &.{});
    g.lv.set(at, .chest);
    const minute = g.clock.minute;
    try std.testing.expectEqual(game.Move.open, game.heroMove(g, .e));
    try std.testing.expect(!g.lv.walkable(at));
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    try std.testing.expectEqual(from, g.heroActor().?.at);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(@as(usize, 1), g.ground.coin_n);
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try harness.expectWithin(g.ground.coins[0].amount, items.CHEST_GOLD.lo, items.CHEST_GOLD.hi);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
    try std.testing.expect(items.CHEST_GOLD.lo > items.BARREL_GOLD.hi);
    try std.testing.expect(g.glide[game.heroSlot(g).?].bump == null);
    const gold = g.ground.coins[0].amount;
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    harness.walkFrame(g, 0, null);
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(at, g.character.loot_at);
    try std.testing.expectEqual(minute + 2 * day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(gold, g.gold);
    try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
    try std.testing.expectEqual(@as(usize, 0), g.inventory.n);
    harness.press(g, menu.CHANGE);
    harness.drawnOut(g);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(@as(usize, 1), g.inventory.n);
    try std.testing.expectEqual(@as(usize, 0), g.ground.n);
    harness.nudge(g, .w);
    harness.nudge(g, .e);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(gold, g.gold);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    std.debug.print("chest: first bump reveals, held walk stops, second enters loot and collects {d} ground gold; empty return walks through\n", .{gold});
}

test "ground pressure preserves closed chest rewards and reserves every possible foe drop" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    const chest = at.add(.{ .x = 1, .y = 0 });
    g.lv.set(chest, .chest);
    for (0..items.GROUND_MAX - actor.MAX) |_| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    const before = g.clock;
    const rng = g.loot_rng;
    game.heroStep(g, .e, 0);
    try std.testing.expectEqualDeep(before, g.clock);
    try std.testing.expectEqualDeep(rng, g.loot_rng);
    try std.testing.expect(g.lv.at(chest).opened() != null);
    for (0..actor.MAX) |_| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expectEqual(items.GROUND_MAX, g.ground.n);
    std.debug.print("full ground: chest and turn untouched, {d} foe rewards reserved\n", .{actor.MAX});
}

test "new runs gate class skills; underfoot and adjacent loot commit exactly one turn; gold collects on movement" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for (heroes.CLASSES) |c| {
        g.class = c;
        game.begin(g, 123);
        for (progress.skills(c)) |s| try std.testing.expectEqual(s.initial, g.growth.unlocked(s.act));
        for (skillbar.SETS) |set| for (skillbar.SLOTS) |button| {
            if (g.bar.at(.{ .set = set, .button = button })) |act| try std.testing.expect(g.growth.unlocked(act));
        };
    }
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const at = g.heroActor().?.at;
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .cap, .mods = .{ .{ .kind = .life, .value = 6 }, null } }, .at = at }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at.add(.{ .x = 1, .y = 0 }) }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .boots }, .at = at.add(.{ .x = 2, .y = 0 }) }));
    const clock = g.clock;
    harness.pressInteract(g);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(clock, g.clock);
    var nearby: game.NearbyBuf = undefined;
    try std.testing.expectEqual(@as(usize, 2), character.nearbyOf(g, &nearby).len);
    character.characterCommand(g, .{ .pickup = 0 });
    try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(@as(usize, 1), g.inventory.n);
    harness.drawnOut(g);
    const hp = g.heroActor().?.hp;
    const minute = g.clock.minute;
    character.characterCommand(g, .{ .equip = .{ .index = 0, .slot = .helm } });
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(hp, g.heroActor().?.hp);
    try std.testing.expectEqual(hp + 6, g.heroActor().?.max);
    harness.drawnOut(g);
    try std.testing.expect(g.ground.gold(at.add(.{ .x = 1, .y = 0 }), 17));
    const before = g.clock.minute;
    harness.press(g, BACK);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(i32, 17), g.gold);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(@as(usize, 1), g.ground.n - 1);
    std.debug.print("progression: 3 starter kits, underfoot/adjacent menu, one-turn item actions, no equip healing, automatic gold\n", .{});
}

test "walking onto a bag opens only its loot and can leave every item behind" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.name = heroes.Name.of("Arwen");
    g.log = .{};
    const at = P{ .x = 21, .y = 20 };
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .cap }, .at = at }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .boots }, .at = .{ .x = 22, .y = 20 } }));
    const before = g.clock.minute;
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 2), g.log.n);
    try std.testing.expectEqualStrings("Arwen steps over Leather cap.", g.log.line(1).?);
    try std.testing.expectEqualStrings("Arwen steps over Copper ring.", g.log.line(0).?);
    try std.testing.expectEqual(@as(usize, 2), g.log.held);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(@as(usize, 3), g.ground.n);
    try std.testing.expectEqual(@as(usize, 0), g.inventory.n);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(at, g.character.loot_at);
    try std.testing.expectEqual(@as(usize, 2), character.bookView(g, &g.nearby).nearby.len);
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(usize, 0), g.log.held);
    for (0..30) |_| game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(usize, 2), g.log.n);
    for (0..items.BAG_MAX) |_| try std.testing.expect(g.inventory.add(.{ .kind = .cap }));
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(before + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(@as(usize, 3), g.ground.n);
    harness.press(g, BACK);
    g.lv.set(.{ .x = 22, .y = 20 }, .wall);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 2), g.log.n);
    harness.nudge(g, .w);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 4), g.log.n);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(@as(usize, 3), g.ground.n);
    std.debug.print("bag bump: 2 selected items, one movement turn, full inventory can cancel and leave all 3 ground items behind\n", .{});
}

test "interact pressed mid-turn waits for quiet instead of queuing its button's skill; the turn's log lines wait too" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = g.heroActor().?.at }));
    g.busy = game.GLIDE_S;
    g.log.say("Said as the turn resolved.", .{});
    harness.pressInteract(g);
    try std.testing.expectEqual(@as(?game.Queued, .interact), g.pending);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(@as(usize, 1), g.log.held);
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Queued, .interact), g.pending);
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(@as(usize, 0), g.inventory.n);
    try std.testing.expectEqual(@as(usize, 1), g.ground.n);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(@as(usize, 0), g.log.held);
    harness.drawnOut(g);
    game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(usize, 0), g.log.held);
    std.debug.print("interact mid-turn: queued, opens loot without taking the item; held log line released on the quiet frame\n", .{});
}

test "every foe drops loot at its presented death and bag interactions leave ground gold alone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    var cases: usize = 0;
    for ([_]bool{ false, true }) |magic| {
        const loot = harness.lootRng(magic);
        for (std.enums.values(actor.Kind)) |kind| {
            if (!kind.foe()) continue;
            harness.arena(g, from, &.{});
            const id = harness.spawnAt(g, kind, at, false);
            game.settle(g);
            g.loot_rng = loot;
            harness.slay(g, id, from);
            try std.testing.expectEqual(@as(usize, 1), g.ground.n);
            try std.testing.expectEqual(@as(usize, 1), g.ground.coin_n);
            try std.testing.expectEqual(magic, g.ground.drops[0].item.magical());
            try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
            try std.testing.expect(scene.pileShown(g, g.ground.coins[0]) == null);
            harness.drawnOut(g);
            try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
            try std.testing.expect(scene.pileShown(g, g.ground.coins[0]) != null);
            const gold = g.ground.coins[0].amount;
            harness.pressInteract(g);
            try std.testing.expectEqual(book.Page.loot, g.character.page);
            try std.testing.expectEqual(@as(i32, 0), g.gold);
            try std.testing.expectEqual(@as(usize, 1), g.ground.coin_n);
            try std.testing.expectEqual(@as(usize, 0), g.inventory.n);
            harness.press(g, CONFIRM);
            try std.testing.expectEqual(@as(usize, 1), g.inventory.n);
            try std.testing.expectEqual(magic, g.inventory.bag[0].magical());
            try std.testing.expectEqual(@as(i32, 0), g.gold);
            try std.testing.expectEqual(gold, g.ground.coins[0].amount);
            harness.drawnOut(g);
            harness.nudge(g, .e);
            try std.testing.expectEqual(gold, g.gold);
            try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
            cases += 1;
        }
    }
    std.debug.print("foe loot: {d} kind/rarity deaths, bags and gold delayed to impact, coins wait for movement through browsing and pickup\n", .{cases});
}

test "a death on a drawn pile keeps the pile drawn and adds its gold when it lands" {
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
        g.loot_rng = loot;
        was = if (g.ground.coin_n > 0) g.ground.coins[0].amount else 0;
        harness.slay(g, id, from);
        const drawn = scene.pileShown(g, g.ground.coins[0]);
        try std.testing.expectEqual(was, if (drawn) |pile| pile.amount else 0);
        harness.drawnOut(g);
        try std.testing.expectEqual(g.ground.coins[0].amount, scene.pileShown(g, g.ground.coins[0]).?.amount);
    }
    std.debug.print("a second death on a drawn pile: {d} gold stayed drawn until the blow landed\n", .{was});
}

test "loot groups each cell into one bag and takes only the selected container" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    const beside = at.add(mathx.Dir.e.delta());
    harness.arena(g, at, &.{});
    for ([_]items.Kind{ .cap, .ring, .boots }) |kind| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .amulet }, .at = beside }));
    const hidden = at.add(.{ .x = 2, .y = 0 });
    try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .bow }, .at = hidden }));
    g.lv.lit[grid.Level.idx(hidden)] = false;
    try std.testing.expectEqual(@as(usize, 2), scene.bagCells(g).count());
    const minute = g.clock.minute;
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.nearby, g.character.page);
    try std.testing.expectEqual(@as(usize, 2), character.bookView(g, &g.nearby).nearby.len);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(at, g.character.loot_at);
    try std.testing.expectEqual(@as(usize, 3), character.bookView(g, &g.nearby).nearby.len);
    try std.testing.expectEqual(minute, g.clock.minute);
    try std.testing.expectEqual(@as(usize, 0), g.inventory.n);
    character.characterCommand(g, .{ .pickup = 3 });
    try std.testing.expectEqual(minute, g.clock.minute);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(usize, 1), g.inventory.n);
    try std.testing.expectEqual(items.Kind.cap, g.inventory.bag[0].kind);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    harness.drawnOut(g);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(usize, 3), g.inventory.n);
    try std.testing.expectEqual(@as(usize, 2), g.ground.n);
    try std.testing.expectEqual(items.Kind.amulet, g.ground.drops[0].item.kind);
    try std.testing.expectEqual(minute + 2 * day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    std.debug.print("loot: 3 items share one bag; browse is free, single take then take-all spend 2 turns; adjacent and hidden loot preserved\n", .{});
}

test "chest interactions reveal before browsing, leave ground gold and preserve excess items" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.set(at, .chest);
    for (0..items.BAG_MAX - 1) |_| try std.testing.expect(g.inventory.add(.{ .kind = .cap }));
    const minute = g.clock.minute;
    harness.pressInteract(g);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    try std.testing.expectEqual(@as(usize, 1), g.ground.n);
    try std.testing.expectEqual(@as(usize, 1), g.ground.coin_n);
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    const gold = g.ground.coins[0].amount;
    try harness.expectWithin(gold, items.CHEST_GOLD.lo, items.CHEST_GOLD.hi);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    for ([_]items.Kind{ .boots, .ring }) |kind| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
    harness.drawnOut(g);
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(items.BAG_MAX, g.inventory.n);
    try std.testing.expectEqual(@as(usize, 2), g.ground.n);
    try std.testing.expect(g.character.message.n > 0);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
    harness.drawnOut(g);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(minute + 2 * day.TURN_MINUTES, g.clock.minute);
    harness.press(g, BACK);
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try std.testing.expectEqual(gold, g.ground.coins[0].amount);
    try std.testing.expectEqual(@as(usize, 2), g.ground.n);
    _ = g.inventory.remove(0);
    _ = g.inventory.remove(0);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(usize, 0), g.ground.n);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    harness.drawnOut(g);
    harness.nudge(g, .e);
    try std.testing.expectEqual(gold, g.gold);
    try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
    std.debug.print("chest loot: reveal then browse, coins wait for arrival, full-bag retry costs no turn, 2 excess items survive reopening\n", .{});
}

test "a chest left holding items keeps its bag out of sight, and a loose bag out of sight is not drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const chest = P{ .x = 60, .y = 20 };
    const loose = P{ .x = 60, .y = 22 };
    g.lv.set(chest, .chest_open);
    for ([_]P{ chest, loose }) |p| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = p }));
    try std.testing.expect(!g.lv.isLit(chest) and !g.lv.isLit(loose));
    const bags = scene.bagCells(g);
    try std.testing.expect(bags.isSet(grid.Level.idx(chest)));
    try std.testing.expect(!bags.isSet(grid.Level.idx(loose)));
}

test "a door is listed nearby only once no body is drawn on it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    _ = runTwoRooms(g, w);
    const door = P{ .x = 2, .y = 5 };
    const from = g.heroActor().?.at;
    const rat = harness.spawnAt(g, .rat, door, false);
    try std.testing.expectEqual(@as(?atlas.Link, null), character.doorReached(g, from, door));
    g.pool.move(&g.lv, rat, .{ .x = 6, .y = 5 });
    g.busy = game.GLIDE_S;
    try std.testing.expectEqual(@as(?atlas.Link, null), character.doorReached(g, from, door));
    harness.calm(g);
    game.snapGlide(g);
    try std.testing.expect(character.doorReached(g, from, door) != null);
}

test "the nearby list closes once a body takes the last door it listed" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    _ = runTwoRooms(g, w);
    try std.testing.expect(character.openNearby(g));
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    _ = harness.spawnAt(g, .rat, .{ .x = 2, .y = 5 }, false);
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.play, g.mode);
}

test "interact during door travel stays an interaction on arrival" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    const b = runTwoRooms(g, w);
    harness.nudge(g, .w);
    const minute = g.clock.minute;
    try std.testing.expect(g.travel != null);
    harness.pressInteract(g);
    try std.testing.expectEqual(@as(?game.Queued, .interact), g.pending);
    g.st = .{ .walk = .w };
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Queued, .interact), g.pending);
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.node);
    game.update(g, mathx.FRAME_DT);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(book.Page.nearby, g.character.page);
    try std.testing.expectEqual(minute, g.clock.minute);
    std.debug.print("door interact: survives travel and walking repeats, opens nearby without an extra turn\n", .{});
}

test "travel and chest opening from the nearby list turn the hero toward them" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    _ = runTwoRooms(g, w);
    const at = g.heroActor().?.at;
    const slot = game.heroSlot(g).?;
    g.facing[slot] = .right;
    character.characterCommand(g, .{ .travel = at.add(mathx.Dir.w.delta()) });
    try std.testing.expectEqual(game.Facing.left, g.facing[slot]);

    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const chest = P{ .x = 19, .y = 20 };
    g.lv.set(chest, .chest);
    g.facing[game.heroSlot(g).?] = .right;
    character.characterCommand(g, .{ .open_loot = chest });
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(chest));
    try std.testing.expectEqual(game.Facing.left, g.facing[game.heroSlot(g).?]);
    std.debug.print("nearby travel and chest: hero turned {s} toward each\n", .{@tagName(g.facing[game.heroSlot(g).?])});
}

test "a door trip finishes behind Character opened during it, so item commands can act" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    const b = runTwoRooms(g, w);
    harness.nudge(g, .w);
    try std.testing.expect(g.travel != null);
    g.st = .{ .character_page = .inventory };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.node);
    try std.testing.expect(g.travel == null);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(book.Page.inventory, g.character.page);
    std.debug.print("door behind Character: arrived at node {d} with the inventory still open\n", .{g.node});
}

test "inspect opened during a door trip opens, and the trip still finishes behind it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    const b = runTwoRooms(g, w);
    harness.nudge(g, .w);
    try std.testing.expect(g.travel != null);
    harness.press(g, skillbar.INSPECT);
    try std.testing.expectEqual(game.Mode.inspect, g.mode);
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expectEqual(b, g.node);
    try std.testing.expect(g.travel == null);
    try std.testing.expectEqual(game.Mode.inspect, g.mode);
    std.debug.print("inspect during a door trip: arrived at node {d} with inspect open\n", .{g.node});
}
