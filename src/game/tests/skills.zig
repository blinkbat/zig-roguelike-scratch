const attacks = @import("../attacks.zig");
const std = @import("std");
const items = @import("../../play/items.zig");
const progress = @import("../../play/progress.zig");
const mathx = @import("../../core/mathx.zig");
const input = @import("../../core/input.zig");
const grid = @import("../../map/grid.zig");
const gas = @import("../../map/gas.zig");
const menu = @import("../../ui/menu.zig");
const book = @import("../../ui/book.zig");
const heroes = @import("../../play/hero.zig");
const actor = @import("../../play/actor.zig");
const bow = @import("../../play/bow.zig");
const damage = @import("../../play/damage.zig");
const attrs = @import("../../play/attrs.zig");
const burning = @import("../../play/burning.zig");
const bleeding = @import("../../play/bleeding.zig");
const glacial = @import("../../play/glacial.zig");
const juke = @import("../../play/juke.zig");
const blink = @import("../../play/blink.zig");
const spark = @import("../../play/spark.zig");
const bash = @import("../../play/bash.zig");
const cleave = @import("../../play/cleave.zig");
const pinning = @import("../../play/pinning.zig");
const nova = @import("../../play/nova.zig");
const fireball = @import("../../play/fireball.zig");
const chain = @import("../../play/chain.zig");
const ward = @import("../../play/ward.zig");
const charge = @import("../../play/charge.zig");
const turn_clock = @import("../../play/clock.zig");
const resilience = @import("../../play/resilience.zig");
const skillbar = @import("../../play/skillbar.zig");
const look = @import("../../gfx/look.zig");
const raster = @import("../../gfx/raster.zig");
const day = @import("../../map/day.zig");
const overlay = @import("../overlay.zig");
const character = @import("../character.zig");
const combat = @import("../combat.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const skills = @import("../skills.zig");
const binds = @import("../binds.zig");
const glide = @import("../glide.zig");
const P = mathx.P;
const BOOK = book.SIZE;
const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;
const REMOVE = menu.REMOVE;
const CHARACTER = menu.CHARACTER;
const PAUSE = menu.PAUSE;

fn manaAfter(g: *const game.Game, act: skillbar.Act) i32 {
    return g.sim.manaMax() - g.sim.growth.cost(act) + @divTrunc(g.sim.manaRegen(), heroes.MANA_REGEN_TURNS);
}

fn skipsNext(a: *actor.Actor) void {
    a.chill = .{ .turns = 1, .phase = glacial.CYCLE - 1 };
}

fn bleedingNow(a: *actor.Actor) void {
    a.bleed.start();
    a.bleed.fresh = false;
}

test "equipment base effects reach combat recovery and status resistance" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.heroArena(g, .knight, from, &.{});
    const id = harness.spawnAt(g, .beefy_pib, .{ .x = 23, .y = 20 }, false);
    g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = .crossbow });
    const hit = attacks.heroRoll(&g.sim, .ranged, 10);
    const before = g.sim.pool.get(id).?.hp;
    combat.wound(g, id, hit, "shoots", .{ .from = from, .wait = 0 });
    try std.testing.expectEqual(before - hit.dmg, g.sim.pool.get(id).?.hp);
    game.settle(g);
    g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = .axe });
    const foe = g.sim.pool.get(id).?;
    foe.kind = .rat;
    harness.setLife(foe, 10000, 10000);
    for (0..200) |_| {
        combat.wound(g, id, attacks.heroRoll(&g.sim, .melee, 1), "slashes", .{ .from = from, .wait = 0 });
        game.settle(g);
    }
    try std.testing.expectEqual(@as(i32, 2), foe.bleed.amount);
    try std.testing.expectEqual(@as(u8, mathx.PERCENT), foe.resilience.meters.get(.bleed).percent);
    g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = .mace });
    for (0..200) |_| {
        combat.wound(g, id, attacks.heroRoll(&g.sim, .melee, 1), "strikes", .{ .from = from, .wait = 0 });
        game.settle(g);
    }
    try std.testing.expectEqual(@as(i32, 4 * turn_clock.TURN), foe.clock.ticks);
    try std.testing.expectEqual(@as(u8, mathx.PERCENT), foe.resilience.meters.get(.stun).percent);
    foe.resilience = .{};
    foe.clock = .{};
    foe.kind = .beefy_pib;
    for (0..200) |_| {
        combat.arrowHit(g, id, .{ .blow = .{ .elements = .initDefault(0, .{ .lightning = 1 }) } }, .spark, .{ .from = from, .wait = 0 });
        game.settle(g);
    }
    try std.testing.expectEqual(@as(i32, turn_clock.TURN), foe.clock.ticks);
    try std.testing.expectEqual(resilience.GAIN, foe.resilience.meters.get(.stun).percent);
    g.sim.inventory.gear.slots.set(.helm, .{ .kind = .circlet });
    g.sim.inventory.gear.slots.set(.left_hand, .{ .kind = .totem });
    g.sim.mana = 0;
    for (0..heroes.MANA_REGEN_TURNS) |_| skills.recover(g);
    try std.testing.expectEqual(@as(i32, 2), g.sim.mana);
    const h = g.sim.heroActor().?;
    h.hp = 10;
    combat.wound(g, id, .{ .dmg = foe.hp }, "slays", .{ .from = from, .wait = 0 });
    try std.testing.expectEqual(@as(i32, 11), h.hp);
    std.debug.print("bases in combat: crossbow pierces 20% armour, great axe bleeds for 2, mace and Spark respect buildup; circlet recovery and totem healing apply\n", .{});
}

test "skills cannot start a second turn while the first is still being drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const clock = g.sim.clock;
    const hp = g.sim.heroActor().?.hp;
    g.pic.busy = 0.5;
    var bound: usize = 0;
    for (skillbar.SLOTS) |button| {
        const act = g.bar.at(.{ .set = .primary, .button = button }) orelse continue;
        if (act == .secondary) continue;
        bound += 1;
        g.st = .{ .pressed = .initOne(button) };
        game.update(g, 0);
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
        try std.testing.expectEqual(clock, g.sim.clock);
        try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
        try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
        try std.testing.expectEqual(act, g.pending.?.skill.act);
    }
    harness.calm(g);
    skills.openAim(g, .x, .shoot);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    g.pic.busy = 0.5;
    skills.confirmAim(g);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expect(g.pic.shot == null);
    g.pic.busy = 0;
    skills.confirmAim(g);
    try std.testing.expect(!std.meta.eql(clock, g.sim.clock));
    try std.testing.expect(g.pic.shot != null);
    std.debug.print("{d} bound skills blocked during animation; shooting resumes when quiet\n", .{bound});
}

test "glacial shot spends only on confirmation and bursts at the first body with delayed chill and cone damage" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{
        .{ .x = 26, .y = 20 },
        .{ .x = 27, .y = 19 },
        .{ .x = 28, .y = 20 },
        .{ .x = 25, .y = 21 },
        .{ .x = 27, .y = 21 },
    });
    harness.toughenFoes(g);
    g.sim.pool.get(6).?.resists.set(.cold, 100);
    g.sim.lv.set(.{ .x = 27, .y = 20 }, .wall);
    game.settle(g);
    const clock = g.sim.clock;
    g.sim.mana = glacial.COST - 1;
    harness.use(g, .glacial_shot);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    g.sim.mana = g.sim.manaMax();
    harness.use(g, .glacial_shot);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    harness.press(g, BACK);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    harness.use(g, .glacial_shot);
    g.mode.aim.mark = g.sim.heroActor().?.at;
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    g.mode.aim.mark = .{ .x = 26, .y = 20 };
    g.sim.rng = harness.procRng(g, .glacial_shot, 1, true);
    harness.press(g, CONFIRM);
    const direct = g.sim.pool.get(2).?;
    const splash = g.sim.pool.get(3).?;
    const dealt = harness.TEST_HP - direct.hp;
    try harness.expectDamage(g, .glacial_shot, dealt, &.{ bow.BASE, glacial.BASE });
    try harness.expectDamage(g, .glacial_shot, harness.TEST_HP - splash.hp, &.{glacial.BASE});
    for ([_]u16{ 4, 5, 6 }) |id| try std.testing.expectEqual(harness.TEST_HP, g.sim.pool.get(id).?.hp);
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(6).?.chill.turns);
    try std.testing.expectEqual(manaAfter(g, .glacial_shot), g.sim.mana);
    try std.testing.expectEqual(glacial.TURNS - 1, direct.chill.turns);
    try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[actor.Pool.slot(2)].status.get(.chilled));
    try std.testing.expectEqual(harness.TEST_HP, g.pic.pictured[actor.Pool.slot(3)].hp);
    try std.testing.expectEqual(skillbar.Act.glacial_shot, g.pic.shot.?.act);
    harness.drawnOut(g);
    try std.testing.expectEqual(direct.chill.turns, g.pic.pictured[actor.Pool.slot(2)].status.get(.chilled));
    try std.testing.expectEqual(splash.hp, g.pic.pictured[actor.Pool.slot(3)].hp);
    std.debug.print("Glacial Shot: {d} direct, {d} cone damage; 3 protected targets untouched; mana {d}; chill shown at impact\n", .{ dealt, harness.TEST_HP - splash.hp, g.sim.mana });
}

test "glacial shot uses an intervening body or barrel and an empty shot has no cone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{ .{ .x = 24, .y = 20 }, .{ .x = 28, .y = 20 } });
    const near = g.sim.pool.get(2).?;
    near.resists.set(.cold, 100);
    harness.use(g, .glacial_shot);
    g.mode.aim.mark = .{ .x = 28, .y = 20 };
    harness.press(g, CONFIRM);
    try harness.expectDamage(g, .glacial_shot, actor.row(.rat).hp - near.hp, &.{bow.BASE});
    try std.testing.expectEqual(@as(u8, 0), near.chill.turns);
    try std.testing.expectEqual(actor.row(.rat).hp, g.sim.pool.get(3).?.hp);
    harness.arena(g, from, &.{.{ .x = 26, .y = 20 }});
    harness.toughenFoes(g);
    const barrel = P{ .x = 24, .y = 20 };
    g.sim.lv.putBarrel(barrel);
    harness.confirmUse(g, .glacial_shot);
    try std.testing.expect(!g.sim.lv.hasBarrel(barrel));
    try std.testing.expect(g.sim.ground.coin_n > 0);
    const splash = harness.TEST_HP - g.sim.pool.get(2).?.hp;
    try harness.expectDamage(g, .glacial_shot, splash, &.{glacial.BASE});
    harness.arena(g, from, &.{.{ .x = 26, .y = 21 }});
    harness.use(g, .glacial_shot);
    g.mode.aim.mark = .{ .x = 25, .y = 20 };
    harness.press(g, CONFIRM);
    try std.testing.expect(g.pic.shot.?.flight.struck == null);
    try std.testing.expectEqual(actor.row(.rat).hp, g.sim.pool.get(2).?.hp);
    std.debug.print("Glacial Shot: first body intercepts, barrel bursts for {d} cold splash, empty shot has no explosion\n", .{splash});
}

test "glacial splash beyond sight does damage without naming the unseen foe in the log" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 29, .y = 20 }});
    const far = harness.spawnAt(g, .bloat, .{ .x = 31, .y = 20 }, false);
    harness.toughenFoes(g);
    game.settle(g);
    try std.testing.expect(!g.sim.lv.isLit(g.sim.pool.get(far).?.at));
    harness.confirmUse(g, .glacial_shot);
    const lost = harness.TEST_HP - g.sim.pool.get(far).?.hp;
    try harness.expectDamage(g, .glacial_shot, lost, &.{glacial.BASE});
    try std.testing.expect(!harness.logged(g, "bloat"));
    std.debug.print("unseen glacial splash: {d} damage, 0 log lines naming the hidden bloat\n", .{lost});
}

test "chill slows movement and attacks while idle frames preserve it and skipped turns still take burn and gas" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 28, .y = 20 }});
    const rat = g.sim.pool.get(2).?;
    harness.wakeFoes(g);
    rat.chill.apply();
    for (0..glacial.TURNS) |i| {
        harness.use(g, .wait);
        harness.drawnOut(g);
        try std.testing.expectEqual(@as(i32, 28) - @as(i32, @intCast(@min(i + 1, glacial.CYCLE - 1))), rat.at.x);
    }
    try std.testing.expectEqual(@as(u8, 0), rat.chill.turns);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    const adjacent = g.sim.pool.get(2).?;
    harness.wakeFoes(g);
    harness.toughen(adjacent);
    adjacent.chill = .{ .turns = 2, .phase = glacial.CYCLE - 1 };
    adjacent.burn = .{ .turns = burning.TURNS };
    g.st = .{};
    game.update(g, 1);
    try std.testing.expectEqual(@as(u8, 2), adjacent.chill.turns);
    const hp = g.sim.heroActor().?.hp;
    harness.use(g, .wait);
    try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
    try std.testing.expectEqual(harness.TEST_HP - burning.PER_TURN, adjacent.hp);
    harness.drawnOut(g);
    adjacent.chill = .{ .turns = 2, .phase = glacial.CYCLE - 1 };
    g.sim.lv.addGas(adjacent.at, harness.TEST_GAS * 10);
    harness.use(g, .wait);
    try std.testing.expectEqual(harness.TEST_HP - 2 * burning.PER_TURN - gas.harm(harness.TEST_HP), adjacent.hp);
    std.debug.print("chill: 2 moves in 3 turns, attack skipped, idle duration unchanged, burning and gas still tick\n", .{});
}

test "glacial chill and its cadence follow slime splits without hitting newborn halves twice" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.splittable(g, .{ .x = 26, .y = 20 }, true);
    const a = g.sim.pool.get(id).?;
    skipsNext(a);
    a.resists.set(.cold, -100);
    combat.burstHit(g, .glacial_shot, .{ .body = id }, a.at, .{ .from = g.sim.heroActor().?.at, .wait = 0.2 });
    try std.testing.expectEqual(@as(usize, 3), g.sim.pool.n);
    const half = g.sim.pool.get(id + 1).?;
    try std.testing.expectEqual(actor.Kind.slime_half, a.kind);
    try std.testing.expectEqual(a.hp, half.hp);
    try std.testing.expectEqual(glacial.TURNS, a.chill.turns);
    try std.testing.expectEqual(@as(u8, 2), a.chill.phase);
    try std.testing.expectEqual(a.chill, half.chill);
    try std.testing.expectEqual(@as(i16, -100), half.resists.get(.cold));
    try std.testing.expect(g.pic.fx.revealing(actor.Pool.slot(id + 1)));
    std.debug.print("Glacial Shot split: 2 equal halves, chill duration {d} and cadence {d} inherited, one damage event each\n", .{ half.chill.turns, half.chill.phase });
}

test "burning arrow spends mana only on confirmation and shows burning when its hit lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 28, .y = 20 }});
    const rat = g.sim.pool.get(2).?;
    harness.toughen(rat);
    g.pic.catchUp(&g.sim);
    g.sim.rng = harness.procRng(g, .burning_arrow, 1, true);
    const clock = g.sim.clock;
    harness.use(g, .burning_arrow);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    harness.press(g, BACK);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    harness.confirmUse(g, .burning_arrow);
    const dealt = harness.TEST_HP - rat.hp;
    try harness.expectDamage(g, .burning_arrow, dealt, &.{ bow.BASE, burning.BASE });
    try std.testing.expectEqual(manaAfter(g, .burning_arrow), g.sim.mana);
    try std.testing.expectEqual(burning.TURNS, rat.burn.turns);
    try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[actor.Pool.slot(2)].status.get(.burning));
    try std.testing.expectEqual(skillbar.Act.burning_arrow, g.pic.shot.?.act);
    harness.drawnOut(g);
    try std.testing.expectEqual(burning.TURNS, g.pic.pictured[actor.Pool.slot(2)].status.get(.burning));
    const before = rat.hp;
    for (0..burning.TURNS) |_| {
        harness.use(g, .wait);
        harness.drawnOut(g);
    }
    try std.testing.expectEqual(before - burning.PER_TURN * burning.TURNS, rat.hp);
    try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[actor.Pool.slot(2)].status.get(.burning));
    const after = rat.hp;
    harness.use(g, .wait);
    try std.testing.expectEqual(after, rat.hp);
    std.debug.print("Burning Arrow: {d} on hit, then {d} over {d} later turns; mana {d}, flames delayed until impact\n", .{ dealt, before - after, burning.TURNS, manaAfter(g, .burning_arrow) });
}

test "burning arrow honors fire resistance, refuses insufficient mana and uses the first body in its path" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 27, .y = 20 } });
    const rat = g.sim.pool.get(2).?;
    rat.resists.set(.fire, 100);
    g.sim.mana = burning.COST - 1;
    harness.use(g, .burning_arrow);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    g.sim.mana = g.sim.manaMax();
    harness.use(g, .burning_arrow);
    g.mode.aim.mark = g.sim.pool.get(3).?.at;
    harness.press(g, CONFIRM);
    try harness.expectDamage(g, .burning_arrow, actor.row(.rat).hp - rat.hp, &.{bow.BASE});
    try std.testing.expectEqual(@as(u8, 0), rat.burn.turns);
    try std.testing.expectEqual(actor.row(.rat).hp, g.sim.pool.get(3).?.hp);
    std.debug.print("100% fire resistance: only physical arrow damage, no ignition; far target untouched\n", .{});
}

test "burning and gas both land in order, while a burning kill bursts a bloat" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 28, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
    const rat = g.sim.pool.get(2).?;
    harness.toughen(rat);
    rat.burn = .{ .turns = burning.TURNS };
    rat.resists.set(.fire, 50);
    g.sim.lv.addGas(at, harness.TEST_GAS);
    g.pic.catchUp(&g.sim);
    harness.use(g, .wait);
    try std.testing.expectEqual(harness.TEST_HP - gas.harm(harness.TEST_HP) - damage.resisted(burning.PER_TURN, 50), rat.hp);
    harness.drawnOut(g);
    try std.testing.expectEqual(rat.hp, g.pic.pictured[actor.Pool.slot(2)].hp);
    try std.testing.expectEqual(rat.burn.turns, g.pic.pictured[actor.Pool.slot(2)].status.get(.burning));
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .bloat, at, false);
    g.sim.pool.get(id).?.burn = .{ .turns = 1 };
    combat.burnHarm(g, id);
    try std.testing.expect(g.sim.pool.get(id) == null);
    try std.testing.expectEqual(@as(usize, 1), g.sim.kills);
    try std.testing.expectEqual(gas.BURST, g.sim.lv.gasAt(at));
    std.debug.print("burning plus gas: both damage events shown; burning bloat death releases {d} gas\n", .{gas.BURST});
}

test "burning follows both slime halves without an extra application turn or tick" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.splittable(g, .{ .x = 28, .y = 20 }, false);
    const a = g.sim.pool.get(id).?;
    a.burn.start();
    a.resists.set(.fire, 50);
    combat.wound(g, id, .{ .dmg = 4 }, combat.SHOOT, .{ .from = g.sim.heroActor().?.at, .wait = 0 });
    combat.endTurn(g);
    const half = g.sim.pool.get(id + 1).?;
    try std.testing.expectEqual(@as(i32, 8), a.hp);
    try std.testing.expectEqual(@as(i32, 8), half.hp);
    try std.testing.expectEqual(burning.TURNS, a.burn.turns);
    try std.testing.expectEqual(burning.TURNS, half.burn.turns);
    try std.testing.expect(!a.burn.fresh and !half.burn.fresh);
    try std.testing.expectEqual(@as(i16, 50), half.resists.get(.fire));
    combat.endTurn(g);
    try std.testing.expectEqual(@as(i32, 6), a.hp);
    try std.testing.expectEqual(@as(i32, 6), half.hp);
    try std.testing.expectEqual(burning.TURNS - 1, half.burn.turns);
    std.debug.print("burning slime split: both halves retain 50% fire resistance and take 2 on the next turn\n", .{});
}

test "a chill wearing down on a foe's turn shows as that foe's step is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    const rat = g.sim.pool.get(2).?;
    harness.wakeFoes(g);
    rat.chill.apply();
    g.pic.catchUp(&g.sim);
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 24), rat.at.x);
    try std.testing.expectEqual(glacial.TURNS - 1, rat.chill.turns);
    try std.testing.expectEqual(glacial.TURNS, g.pic.pictured[actor.Pool.slot(2)].status.get(.chilled));
    harness.drawnOut(g);
    try std.testing.expectEqual(glacial.TURNS - 1, g.pic.pictured[actor.Pool.slot(2)].status.get(.chilled));
    std.debug.print("chill on a stepping rat: {d} turns shown until its step is drawn, then {d}\n", .{ glacial.TURNS, g.pic.pictured[actor.Pool.slot(2)].status.get(.chilled) });
}

test "a half split off a burning, chilled slime ticks and skips in step with it on its waiting turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.splittable(g, .{ .x = 28, .y = 20 }, false);
    const a = g.sim.pool.get(id).?;
    a.burn = .{ .turns = burning.TURNS };
    a.chill.apply();
    combat.wound(g, id, .{ .dmg = 4 }, combat.SHOOT, .{ .from = g.sim.heroActor().?.at, .wait = 0 });
    combat.endTurn(g);
    const half = g.sim.pool.get(id + 1).?;
    try std.testing.expectEqual(a.hp, half.hp);
    try std.testing.expectEqual(a.burn, half.burn);
    try std.testing.expectEqual(a.chill, half.chill);
    g.st = .{};
    game.update(g, 0);
    for (g.pic.owed) |o| try std.testing.expect(!o.any());
    std.debug.print("split on a burning, chilled slime: both at {d} hp, burn {d} turns, chill {d} turns phase {d}\n", .{ half.hp, half.burn.turns, half.chill.turns, half.chill.phase });
}

test "a half the gas or a burn splits off on the foes' turn keeps the ticks its slime already took" {
    for ([_]bool{ true, false }) |gassed| {
        const g = try game.boot(std.testing.allocator);
        defer game.shut(std.testing.allocator, g);
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const at = P{ .x = 30, .y = 20 };
        const id = harness.spawnAt(g, .slime, at, false);
        const a = g.sim.pool.get(id).?;
        a.hp = harness.SLIME_HALF + @as(i32, if (gassed) 1 else 3);
        a.burn = .{ .turns = 2 };
        a.chill.apply();
        if (gassed) g.sim.lv.addGas(at, gas.BURST);
        combat.endTurn(g);
        const half = g.sim.pool.get(id + 1).?;
        try std.testing.expect(half.alive);
        try std.testing.expectEqual(a.chill, half.chill);
        try std.testing.expectEqual(a.burn, half.burn);
        std.debug.print("split by {s} on the foes' turn: slime and half chill {d}/{d} phase {d}/{d}, burn {d}/{d}\n", .{ if (gassed) "gas" else "burn", a.chill.turns, half.chill.turns, a.chill.phase, half.chill.phase, a.burn.turns, half.burn.turns });
    }
}

test "a half a burn splits off a slime in clean air into gas takes the gas on its waiting turn" {
    var hp: [2]i32 = undefined;
    for ([_]bool{ false, true }, &hp) |gassed, *h| {
        const g = try game.boot(std.testing.allocator);
        defer game.shut(std.testing.allocator, g);
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const at = P{ .x = 30, .y = 20 };
        const id = harness.spawnAt(g, .slime, at, false);
        const a = g.sim.pool.get(id).?;
        a.hp = harness.SLIME_HALF + 3;
        a.burn = .{ .turns = 2 };
        if (gassed) for (mathx.ALL_DIRS) |d| g.sim.lv.addGas(at.add(d.delta()), gas.GASSED_UP - 1);
        combat.endTurn(g);
        try std.testing.expect(!g.sim.lv.gassy(a.at));
        h.* = g.sim.pool.get(id + 1).?.hp;
    }
    std.debug.print("a half burned off a slime in clean air: {d} hp, into gas {d}\n", .{ hp[0], hp[1] });
    try std.testing.expect(hp[1] < hp[0]);
}

test "juke targets across obstacles, lands instantly and spends mana but no turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const to = P{ .x = 20 + juke.RANGE, .y = 20 };
    const rat = P{ .x = 26, .y = 20 };
    harness.arena(g, from, &.{rat});
    harness.wakeFoes(g);
    g.sim.lv.set(.{ .x = 21, .y = 20 }, .water);
    const clock = g.sim.clock;
    const rng = g.sim.rng;
    harness.use(g, .juke);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    for (0..juke.RANGE) |_| harness.nudge(g, .e);
    try std.testing.expectEqual(to, g.mode.aim.mark);
    harness.nudge(g, .e);
    try std.testing.expectEqual(to, g.mode.aim.mark);
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(to, g.sim.heroActor().?.at);
    try std.testing.expect(harness.samePx(glide.cellPx(to), g.pic.heroNow(&g.sim).?));
    try std.testing.expectEqual(grid.NO_ONE, g.sim.lv.who(from));
    try std.testing.expectEqual(g.sim.hero, g.sim.lv.who(to));
    try std.testing.expectEqual(rat, g.sim.pool.get(2).?.at);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(rng, g.sim.rng);
    try std.testing.expectEqual(g.sim.manaMax() - juke.COST, g.sim.mana);
    try std.testing.expectEqual(juke.COOLDOWN, g.sim.cooldown.get(.juke));
    try std.testing.expect(g.sim.unsaved);
    var trail: usize = 0;
    for (g.pic.fx.motes) |m| {
        if (m.life > 0 and std.meta.eql(m.col, look.JUKE_TRAIL) and m.p[0] < mathx.centre(from)[0] + 1) trail += 1;
    }
    try std.testing.expect(trail > 0);
    harness.use(g, .juke);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    std.debug.print("Juke moved {d} tiles instantly: {d} mana left, {d} turns cooldown, no enemy or clock advance\n", .{ mathx.dist(from, to), g.sim.mana, g.sim.cooldown.get(.juke) });
}

test "juke cancellation and invalid landings cost nothing; recovery requires turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    const clock = g.sim.clock;
    harness.confirmUse(g, .juke);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    g.sim.lv.putBarrel(.{ .x = 21, .y = 20 });
    harness.nudge(g, .e);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(from, g.sim.heroActor().?.at);
    harness.press(g, CHARACTER);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    try std.testing.expectEqual(@as(u8, 0), g.sim.cooldown.get(.juke));
    try std.testing.expectEqual(clock, g.sim.clock);
    harness.use(g, .juke);
    harness.nudge(g, .w);
    harness.press(g, CONFIRM);
    g.st = .{};
    game.update(g, 10);
    try std.testing.expectEqual(juke.COOLDOWN, g.sim.cooldown.get(.juke));
    try std.testing.expectEqual(g.sim.manaMax() - juke.COST, g.sim.mana);
    for (0..juke.COOLDOWN) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@as(u8, 0), g.sim.cooldown.get(.juke));
    try std.testing.expectEqual(g.sim.manaMax() - juke.COST + @divTrunc(heroes.MANA_REGEN * juke.COOLDOWN, heroes.MANA_REGEN_TURNS), g.sim.mana);
    g.sim.mana = juke.COST - 1;
    harness.use(g, .juke);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    for (0..@as(usize, @intCast(@divExact(g.sim.manaMax() * heroes.MANA_REGEN_TURNS, heroes.MANA_REGEN)))) |_| harness.use(g, .wait);
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    g.bar.bind(.{ .set = .secondary, .button = .rb }, .juke);
    harness.pressHolding(g, .rb, &.{.lb});
    harness.nudge(g, .w);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(P{ .x = 18, .y = 20 }, g.sim.heroActor().?.at);
    std.debug.print("Juke: free cancel and invalid targets, {d}-turn recovery, mana capped at {d}, secondary binding checked\n", .{ juke.COOLDOWN, g.sim.manaMax() });
}

test "a skill fires from whatever button holds it, and the secondary set only with its modifier held" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.bar.clear(.{ .set = .primary, .button = .x });
    g.bar.clear(.{ .set = .primary, .button = .rb });
    g.bar.bind(.{ .set = .secondary, .button = .rb }, .shoot);
    harness.press(g, .x);
    harness.press(g, .rb);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    harness.pressHolding(g, .rb, &.{.lb});
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(input.Button.rb, g.mode.aim.by);
    harness.press(g, .x);
    try std.testing.expect(!g.sim.pool.get(2).?.hurt());
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(g.sim.pool.get(2).?.hurt());
}

test "every targeted slot uses standard confirmation in both skill sets" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var checked: usize = 0;
    for (skillbar.SETS) |set| {
        for (skillbar.SLOTS) |by| {
            harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
            harness.toughen(g.sim.pool.get(2).?);
            g.bar = skillbar.Bar.of(.archer);
            const modifier: input.Button = if (by == .lb) .rt else .lb;
            g.bar.bind(.{ .set = .primary, .button = modifier }, .secondary);
            g.bar.bind(.{ .set = set, .button = by }, .shoot);
            const clock = g.sim.clock;
            if (set == .secondary) harness.pressHolding(g, by, &.{modifier}) else harness.press(g, by);
            try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
            try std.testing.expectEqual(clock, g.sim.clock);
            try std.testing.expectEqual(set, g.mode.aim.set);
            if (by != CONFIRM and by != BACK) {
                harness.press(g, by);
                try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
                try std.testing.expectEqual(clock, g.sim.clock);
                try std.testing.expect(!g.sim.pool.get(2).?.hurt());
            }
            harness.press(g, CONFIRM);
            try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
            try std.testing.expect(g.sim.pool.get(2).?.hurt());
            try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.sim.clock.minute);
            checked += 1;
        }
    }
    std.debug.print("{d} targeted bindings: opening spends nothing, standard confirm fires once, secondary selection survives modifier release\n", .{checked});
}

test "standard back controls cancel skills opened with B for every class" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var checked: usize = 0;
    for (std.enums.values(heroes.Class)) |class| {
        for ([_]input.Button{ BACK, PAUSE, CHARACTER }) |back| {
            harness.heroArena(g, class, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
            const clock = g.sim.clock;
            const mana = g.sim.mana;
            const cooldown = g.sim.cooldown;
            const at = g.sim.heroActor().?.at;
            harness.press(g, .b);
            try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
            harness.press(g, back);
            try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
            try std.testing.expectEqual(clock, g.sim.clock);
            try std.testing.expectEqual(mana, g.sim.mana);
            try std.testing.expectEqual(cooldown, g.sim.cooldown);
            try std.testing.expectEqual(at, g.sim.heroActor().?.at);
            try std.testing.expect(!g.sim.pool.get(2).?.hurt());
            checked += 1;
        }
    }
    std.debug.print("{d} B-opened targeting cases cancel without moving, damage, mana, cooldown or turns\n", .{checked});
}

test "pressing the modifier while a button is already held fires that button's secondary skill" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.bar.bind(.{ .set = .secondary, .button = .y }, .shoot);
    harness.pressHolding(g, .lb, &.{.y});
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(input.Button.y, g.mode.aim.by);
}

test "binding from Skills assigns the selected skill directly and spends no turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const clock = g.sim.clock;
    harness.press(g, menu.CHARACTER);
    g.character.choose(.skills);
    character.characterCommand(g, .{ .bindings = .shoot });
    try std.testing.expectEqual(game.Mode.bind, std.meta.activeTag(g.mode));
    g.binds.col = binds.Binds.colOf(.y);
    g.binds.row = game.rowAt(skillbar.Set.secondary);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(?skillbar.Act, .shoot), g.bar.at(g.binds.slot()));
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(book.Page.skills, g.character.page);
    character.characterCommand(g, .{ .bindings = .shoot });
    harness.press(g, REMOVE);
    try std.testing.expectEqual(@as(?skillbar.Act, null), g.bar.at(g.binds.slot()));
    harness.press(g, BACK);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(clock, g.sim.clock);
    std.debug.print("bindings: selected skill to either bar in two actions, direct clear, return to Skills, no turns\n", .{});
}

test "binding mouse targets follow both sets at different screen sizes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.sim.clock;
    var checked: usize = 0;
    for ([_]P{ game.SCREEN_720, game.SCREEN_1080 }) |screen| {
        g.screen = screen;
        const panel = overlay.bindPanel(g);
        try std.testing.expect(panel.x < BOOK.x and panel.y < BOOK.y);
        const surface = overlay.bindSurface(g, panel);
        for (skillbar.SETS, 0..) |_, row| for (0..game.SLOT_XS.len) |col| {
            character.openCharacter(g);
            character.characterCommand(g, .{ .bindings = .shoot });
            g.st = .{ .click = true, .pointer = surface.screenOf(raster.middle(overlay.bindSlotBox(row, col))) };
            game.update(g, 0);
            try std.testing.expectEqual(row, g.binds.row);
            try std.testing.expectEqual(col, g.binds.col);
            g.st = .{ .mouse_moved = true, .pointer = surface.screenOf(raster.middle(overlay.bindSlotBox(1 - row, col))) };
            game.update(g, 0);
            try std.testing.expectEqual(row, g.binds.row);
            try std.testing.expectEqual(col, g.binds.col);
            g.st = .{ .click = true, .pointer = surface.screenOf(raster.middle(overlay.bindActionBox(panel, 0))) };
            game.update(g, 0);
            try std.testing.expectEqual(@as(?skillbar.Act, .shoot), g.bar.at(g.binds.slot()));
            try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
            checked += 1;
        };
    }
    try std.testing.expectEqual(clock, g.sim.clock);
    std.debug.print("binding mouse: {d} scaled slot selections and assignments, both sets, zero turns\n", .{checked});
}

test "a pool longer than the bar wraps into rows the d-pad walks, and the rows shown scroll to hold the cursor" {
    const n = binds.PICK_COLS * 3 + 2;
    const last = n - 1;
    try std.testing.expectEqual(binds.PICK_COLS, binds.pickStep(0, .{ .x = 0, .y = 1 }, n));
    try std.testing.expectEqual(@as(usize, 1), binds.pickStep(binds.PICK_COLS + 1, .{ .x = 0, .y = -1 }, n));
    try std.testing.expectEqual(@as(usize, 1), binds.pickStep(1, .{ .x = 0, .y = -1 }, n));
    try std.testing.expectEqual(last, binds.pickStep(binds.PICK_COLS * 2 + binds.PICK_COLS - 1, .{ .x = 0, .y = 1 }, n));
    try std.testing.expectEqual(@as(usize, 0), binds.pickStep(last, .{ .x = 1, .y = 0 }, n));
    try std.testing.expectEqual(last, binds.pickStep(0, .{ .x = -1, .y = 0 }, n));
    try std.testing.expectEqual(binds.PICK_COLS + 1, binds.pickStep(0, .{ .x = 1, .y = 1 }, n));
    for (0..n) |at| {
        const picker = overlay.bindPicker(.{ .menu = .{ .pick = at } }, n);
        try std.testing.expectEqual(@as(usize, 1), picker.win.len);
        try std.testing.expectEqual(at / binds.PICK_COLS, picker.win.from);
        try std.testing.expect(picker.first() <= at and at < picker.end());
        try std.testing.expectEqual(@min(n, picker.first() + binds.PICK_COLS), picker.end());
        for (picker.first()..picker.end()) |i| {
            const cell = picker.cell(i);
            try std.testing.expectEqual(@as(f32, @floatFromInt(picker.y)), cell.y);
            try std.testing.expect(cell.x >= @as(f32, @floatFromInt(picker.x)));
            try std.testing.expect(cell.x + cell.width <= @as(f32, @floatFromInt(picker.x + picker.w)));
            try std.testing.expect(cell.height <= @as(f32, @floatFromInt(picker.h)));
        }
    }
    std.debug.print("binding picker: {d} selections stay in the actual one-row viewport, including the partial last row\n", .{n});
}

test "X opens aim on the nearest rat and nothing is spent until standard confirmation" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 27, .y = 20 }, .{ .x = 23, .y = 22 } });
    harness.press(g, .x);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(P{ .x = 23, .y = 22 }, g.mode.aim.mark);
    try std.testing.expect(!g.sim.pool.get(3).?.awake);
    try std.testing.expect(!g.sim.pool.get(3).?.hurt());
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expect(g.sim.pool.get(3).?.hurt());
    try std.testing.expect(!g.sim.pool.get(2).?.hurt());
}

test "B cancels aim and costs no turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    harness.wakeFoes(g);
    harness.press(g, .x);
    harness.press(g, .b);
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(P{ .x = 25, .y = 20 }, g.sim.pool.get(2).?.at);
}

test "smart aim retains a moved enemy across skills without spending or firing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 22 } });
    const clock = g.sim.clock;
    const mana = g.sim.mana;
    const rng = g.sim.rng;
    const hp = g.sim.pool.get(3).?.hp;
    skills.useSkill(g, .{ .act = .shoot, .by = .x });
    try std.testing.expectEqual(@as(?u16, 2), g.target);
    g.mode.aim.mark = g.sim.pool.get(3).?.at;
    skills.rememberTarget(g);
    try std.testing.expectEqual(@as(?u16, 3), g.target);
    harness.press(g, BACK);
    const moved = P{ .x = 25, .y = 22 };
    g.sim.pool.move(&g.sim.lv, 3, moved);
    skills.useSkill(g, .{ .act = .burning_arrow, .by = .x });
    try std.testing.expectEqual(moved, g.mode.aim.mark);
    try std.testing.expectEqual(@as(?u16, 3), g.target);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqual(mana, g.sim.mana);
    try std.testing.expectEqualDeep(rng, g.sim.rng);
    try std.testing.expectEqual(hp, g.sim.pool.get(3).?.hp);
    try std.testing.expectEqual(@as(u8, 0), g.sim.cooldown.get(.burning_arrow));
    std.debug.print("smart aim: a moved enemy retains identity across two skills; selection and cancellation spend no mana, cooldown, turn, RNG or damage\n", .{});
}

test "smart aim ignores hidden interception until the shot is confirmed" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const hidden = P{ .x = 23, .y = 20 };
    const to = P{ .x = 26, .y = 20 };
    const Interceptor = enum { body, barrel };
    for (std.enums.values(Interceptor)) |kind| {
        harness.arena(g, from, &.{to});
        const hp = g.sim.pool.get(2).?.hp;
        const id: ?u16 = if (kind == .body) harness.spawnAt(g, .rat, hidden, false) else null;
        if (kind == .barrel) g.sim.lv.putBarrel(hidden);
        g.sim.lv.lit[grid.Level.idx(hidden)] = false;
        const clock = g.sim.clock;
        const mana = g.sim.mana;
        const rng = g.sim.rng;
        skills.openAim(g, .x, .shoot);
        try std.testing.expectEqual(to, g.mode.aim.mark);
        try std.testing.expectEqual(@as(?u16, 2), g.target);
        g.mode = .play;
        skills.openAim(g, .x, .burning_arrow);
        try std.testing.expectEqual(to, g.mode.aim.mark);
        try std.testing.expectEqual(@as(?u16, 2), g.target);
        try std.testing.expectEqual(clock, g.sim.clock);
        try std.testing.expectEqual(mana, g.sim.mana);
        try std.testing.expectEqualDeep(rng, g.sim.rng);
        g.mode.aim.action = .{ .single = .shoot };
        skills.confirmAim(g);
        try std.testing.expectEqual(@as(?P, hidden), g.pic.shot.?.flight.impact());
        try std.testing.expectEqual(hp, g.sim.pool.get(2).?.hp);
        if (id) |rat| try std.testing.expect(g.sim.pool.get(rat).?.hurt()) else try std.testing.expect(!g.sim.lv.hasBarrel(hidden));
    }
    std.debug.print("smart aim: hidden body and barrel preserve initial and retained targets without spending; confirmed shots still hit each interceptor\n", .{});
}

test "smart aim replaces dead hidden blocked distant and invalid targets with a legal foe" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const first = P{ .x = 23, .y = 20 };
    const second = P{ .x = 22, .y = 22 };
    const Invalid = enum { dead, hidden, blocked, distant, missing, hero };
    for (std.enums.values(Invalid)) |why| {
        harness.arena(g, from, &.{ first, second });
        g.target = 2;
        switch (why) {
            .dead => _ = g.sim.pool.damage(&g.sim.lv, 2, 1000),
            .hidden => g.sim.lv.lit[grid.Level.idx(first)] = false,
            .blocked => g.sim.lv.set(.{ .x = 21, .y = 20 }, .wall),
            .distant => g.sim.pool.move(&g.sim.lv, 2, .{ .x = from.x + bow.RANGE + 1, .y = from.y }),
            .missing => g.target = actor.MAX,
            .hero => g.target = g.sim.hero,
        }
        const clock = g.sim.clock;
        const mana = g.sim.mana;
        skills.useSkill(g, .{ .act = .burning_arrow, .by = .x });
        try std.testing.expectEqual(second, g.mode.aim.mark);
        try std.testing.expectEqual(@as(?u16, 3), g.target);
        try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
        try std.testing.expectEqual(clock, g.sim.clock);
        try std.testing.expectEqual(mana, g.sim.mana);
        try std.testing.expect(!g.sim.pool.get(3).?.hurt());
    }
    std.debug.print("smart aim: {d} invalid target cases choose the nearest legal visible foe and wait for confirmation\n", .{std.enums.values(Invalid).len});
}

test "free projectile aim moves one cell in eight directions and retains melee and rush targeting" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const centre = P{ .x = 24, .y = 24 };
    harness.arena(g, from, &.{centre});
    for (mathx.ALL_DIRS) |d| {
        const delta = d.delta();
        _ = harness.spawnAt(g, .rat, centre.add(.{ .x = 2 * delta.x, .y = 2 * delta.y }), false);
    }
    game.castSight(g, from);
    const clock = g.sim.clock;
    for (mathx.ALL_DIRS) |d| {
        g.mode = .play;
        g.target = 2;
        skills.useSkill(g, .{ .act = .shoot, .by = .x });
        g.mode.aim.mark = centre;
        skills.nudgeAim(g, d);
        try std.testing.expectEqual(@as(?u16, null), g.target);
        try std.testing.expectEqual(centre.add(d.delta()), g.mode.aim.mark);
        try std.testing.expectEqual(clock, g.sim.clock);
    }
    harness.heroArena(g, .knight, from, &.{ .{ .x = 20, .y = 19 }, .{ .x = 21, .y = 20 }, .{ .x = 23, .y = 20 } });
    g.target = 3;
    skills.useSkill(g, .{ .act = .shield_bash, .by = .x });
    try std.testing.expectEqual(@as(?u16, 3), g.target);
    g.mode = .play;
    skills.useSkill(g, .{ .act = .charge, .by = .x });
    try std.testing.expectEqual(@as(?u16, null), g.target);
    g.mode = .play;
    g.sim.pool.move(&g.sim.lv, 3, .{ .x = 21, .y = 21 });
    skills.useSkill(g, .{ .act = .charge, .by = .x });
    try std.testing.expectEqual(@as(?u16, 4), g.target);
    try std.testing.expectEqual(P{ .x = 23, .y = 20 }, g.mode.aim.mark);
    skills.openLeap(g, .b, .juke);
    try std.testing.expectEqual(from, g.mode.aim.mark);
    try std.testing.expectEqual(@as(?u16, 4), g.target);
    std.debug.print("free projectile aim: eight directions without snapping; adjacent melee, blocked and clear rushes and free leaps checked\n", .{});
}

test "smart aim forgets actor identities when a pool is reset or a run resumes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{.{ .x = 23, .y = 20 }});
    skills.openAim(g, .x, .shoot);
    try std.testing.expectEqual(@as(?u16, 2), g.target);
    harness.arena(g, from, &.{ .{ .x = 27, .y = 20 }, .{ .x = 22, .y = 22 } });
    try std.testing.expectEqual(@as(?u16, null), g.target);
    skills.openAim(g, .x, .shoot);
    try std.testing.expectEqual(@as(?u16, 3), g.target);
    game.resumeRun(g);
    try std.testing.expectEqual(@as(?u16, null), g.target);
    std.debug.print("smart aim: reset and resume discard actor IDs instead of selecting unrelated replacement actors\n", .{});
}

test "the projectile reticle can aim at walls while staying within range" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 20 + bow.RANGE, .y = 20 }});
    g.sim.lv.set(.{ .x = 20 + bow.RANGE, .y = 19 }, .wall);
    game.castSight(g, .{ .x = 20, .y = 20 });
    harness.use(g, .shoot);
    harness.nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 20 + bow.RANGE, .y = 20 }, g.mode.aim.mark);
    harness.nudge(g, .n);
    try std.testing.expectEqual(P{ .x = 20 + bow.RANGE, .y = 19 }, g.mode.aim.mark);
    harness.nudge(g, .w);
    try std.testing.expectEqual(P{ .x = 19 + bow.RANGE, .y = 19 }, g.mode.aim.mark);
}

test "two arrows kill a rat at range, and the first wakes it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    harness.confirmUse(g, .shoot);
    const r = g.sim.pool.get(2).?;
    try std.testing.expect(r.awake and r.hp > 0 and r.hp <= actor.row(.rat).hp - bow.BASE.lo);
    try std.testing.expectEqual(@as(i32, 26), r.at.x);
    harness.confirmUse(g, .shoot);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(2));
    try std.testing.expectEqual(@as(usize, 1), g.sim.kills);
}

test "projectile aiming opens with nothing in sight and only confirmation spends a turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 40, .y = 20 }});
    harness.wakeFoes(g);
    harness.press(g, .x);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(i32, 40), g.sim.pool.get(2).?.at.x);
}

test "X aims at a barrel when no rat is in reach, and the arrow breaks it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    g.sim.lv.putBarrel(at);
    harness.press(g, .x);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(at, g.mode.aim.mark);
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    harness.press(g, CONFIRM);
    try std.testing.expect(!g.sim.lv.hasBarrel(at));
    try std.testing.expectEqual(@as(i32, 0), g.sim.gold);
    try std.testing.expect(g.sim.ground.coins[0].amount >= items.BARREL_GOLD.lo);
}

test "the reticle crosses the archer to the far side of a corridor" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
    harness.wallRow(&g.sim.lv, 19, 10, 30);
    harness.wallRow(&g.sim.lv, 21, 10, 30);
    game.castSight(g, .{ .x = 20, .y = 20 });
    harness.use(g, .shoot);
    try std.testing.expectEqual(P{ .x = 23, .y = 20 }, g.mode.aim.mark);
    for (0..3) |_| harness.nudge(g, .w);
    try std.testing.expectEqual(P{ .x = 19, .y = 20 }, g.mode.aim.mark);
}

test "charge retreats down an empty line and passive and skill allocations spend points without turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.sim.clock;
    g.sim.growth = progress.State.of(.knight);
    _ = g.sim.growth.gain(40);
    for (progress.NODES, 0..) |_, i| if (g.sim.growth.available(i)) {
        character.characterCommand(g, .{ .passive = i });
        break;
    };
    try std.testing.expectEqual(@as(u16, 0), g.sim.growth.passive_points);
    character.characterCommand(g, .{ .skill = .cleave });
    try std.testing.expectEqual(@as(u8, 2), g.sim.growth.ranks.get(.cleave));
    try std.testing.expectEqual(@as(u16, 0), g.sim.growth.active_points);
    try std.testing.expectEqual(clock, g.sim.clock);
    harness.drawnOut(g);
    harness.use(g, .charge);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    g.mode.aim.mark = .{ .x = 17, .y = 20 };
    skills.confirmAim(g);
    try std.testing.expectEqual(P{ .x = 17, .y = 20 }, g.sim.heroActor().?.at);
    try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.sim.clock.minute);
    try std.testing.expectEqual(manaAfter(g, .charge), g.sim.mana);
    std.debug.print("charge: empty retreat landing; allocations consume points and no turn\n", .{});
}

test "attribute damage and critical rolls reach melee, arrows, mixed arrows and resisted spells" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const cases = .{
        .{ heroes.Class.knight, skillbar.Act.charge },
        .{ heroes.Class.archer, skillbar.Act.shoot },
        .{ heroes.Class.archer, skillbar.Act.burning_arrow },
        .{ heroes.Class.wizard, skillbar.Act.spark },
    };
    const seeds = 64;
    inline for (cases) |c| {
        var criticals: usize = 0;
        for (0..seeds) |seed| {
            harness.heroArena(g, c[0], .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
            const target = g.sim.pool.get(2).?;
            harness.toughen(target);
            target.resists = .initFill(50);
            g.sim.rng = mathx.Rng.init(seed);
            var expected_rng = g.sim.rng;
            const raw = attacks.rollRaw(&expected_rng, c[1], attacks.basesFor(&g.sim, c[1]), true);
            const critical = c[0].attrs().crits(&expected_rng);
            criticals += @intFromBool(critical);
            const expected = c[0].attrs().blow(comptime c[1].defaultStyle().?, raw, critical, &expected_rng).total(target.resists);
            harness.use(g, c[1]);
            try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
            skills.confirmAim(g);
            try std.testing.expectEqual(expected, harness.TEST_HP - target.hp);
        }
        try std.testing.expect(criticals > 0 and criticals < seeds);
        std.debug.print("{s}: {d} exact damage checks, {d} criticals, resistance applied after scaling\n", .{ c[1].name(), seeds, criticals });
    }
}

test "live skill tooltips include equipped damage, ranks and the actual targeting range" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = .bow });
    g.sim.growth.ranks.set(.shoot, 3);
    g.bar.bind(.{ .set = .primary, .button = skillbar.SLOTS[0] }, .shoot);
    var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
    var body: [overlay.TIP_BODY_MAX]u8 = undefined;
    const tip = overlay.tipOf(g, .{ .slot = 0 }, &title, &body).?;
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "Range: 9 cells") != null);
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "Physical damage: 2-6") != null);
    try std.testing.expectEqualStrings("Shoot", tip.title);
    try std.testing.expect(std.mem.startsWith(u8, tip.body, skillbar.Act.shoot.desc()));
    try std.testing.expectEqual(@as(i32, 1), skillbar.Act.cleave.reach());
    g.bar.bind(.{ .set = .primary, .button = skillbar.SLOTS[0] }, .secondary);
    try std.testing.expect(std.mem.indexOf(u8, overlay.tipOf(g, .{ .slot = 0 }, &title, &body).?.body, "no turn cost.") != null);
    std.debug.print("live tooltips: equipment, rank damage, bow/swing ranges and modifier turn cost checked\n", .{});
}

test "weapon weight controls live damage and its preview independently of attack range" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    inline for (.{
        .{ items.Kind.crossbow, skillbar.Act.shoot, attrs.Style.heavy },
        .{ items.Kind.bow, skillbar.Act.shoot, attrs.Style.light },
        .{ items.Kind.sling, skillbar.Act.shoot, attrs.Style.light },
        .{ items.Kind.dagger, skillbar.Act.cleave, attrs.Style.light },
        .{ items.Kind.longsword, skillbar.Act.cleave, attrs.Style.heavy },
    }) |case| {
        const act = case[1];
        const style = case[2];
        harness.heroArena(g, if (act == .shoot) .archer else .knight, .{ .x = 20, .y = 20 }, &.{});
        g.sim.inventory.gear.slots.set(.right_hand, .{ .kind = case[0] });
        g.sim.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 70 }, null, null, null } });
        g.sim.growth.ranks.set(act, 2);
        var expected_attrs = g.sim.inventory.gear.forAttack(g.sim.heroAttrs(), act.attack().?);
        expected_attrs.damage_bonus.getPtr(style).* += g.sim.growth.damageBonus(act);
        try std.testing.expectEqualDeep(expected_attrs, attacks.blowFor(&g.sim, act).by);
        const raw = damage.Damage{ .physical = 100 };
        g.sim.rng = mathx.Rng.init(0xDA6);
        var expected_rng = g.sim.rng;
        const critical = expected_attrs.crits(&expected_rng);
        const expected = expected_attrs.blow(style, raw, critical, &expected_rng);
        try std.testing.expectEqualDeep(expected, attacks.heroScaled(&g.sim, act, raw).blow);
        g.bar.bind(.{ .set = .primary, .button = skillbar.SLOTS[0] }, act);
        var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
        var body: [overlay.TIP_BODY_MAX]u8 = undefined;
        const tip = overlay.tipOf(g, .{ .slot = 0 }, &title, &body).?;
        const scaling_label = comptime std.fmt.comptimePrint(attrs.SCALES_FMT, .{menu.named(case[2].attr())});
        try std.testing.expect(std.mem.indexOf(u8, tip.body, scaling_label) != null);
        const span = expected_attrs.span(style, attacks.basesFor(&g.sim, act).physical());
        var wanted: [64]u8 = undefined;
        try std.testing.expect(std.mem.indexOf(u8, tip.body, try std.fmt.bufPrint(&wanted, damage.PHYSICAL_FMT, .{ span.lo, span.hi })) != null);
        if (act == .cleave) {
            const by = g.sim.inventory.gear.forAttack(g.sim.heroAttrs(), .melee);
            var scoped_only: usize = 0;
            for (0..128) |seed| {
                g.sim.rng = mathx.Rng.init(seed);
                expected_rng = g.sim.rng;
                var unscoped_rng = g.sim.rng;
                const crit = by.crits(&expected_rng);
                scoped_only += @intFromBool(crit and !g.sim.heroAttrs().crits(&unscoped_rng));
                try std.testing.expectEqual(by.blow(style, raw, crit, &expected_rng).physical, attacks.heroRoll(&g.sim, .melee, 100).dmg);
            }
            if (case[0] == .dagger) try std.testing.expect(scoped_only > 0);
        }
    }
    for ([_]items.Kind{ .wand, .staff }) |kind| {
        var gear = items.Gear{};
        gear.slots.set(.right_hand, .{ .kind = kind });
        inline for ([_]skillbar.Act{ .shoot, .cleave, .spark }) |act| {
            try std.testing.expectEqualDeep(act.equippedBases(.{}), act.equippedBases(gear));
        }
    }
    std.debug.print("weapon scaling: 5 ranged/melee skill and tooltip cases, 256 bump attacks including scoped-only crits, 6 zero-innate-damage checks\n", .{});
}

test "dodging spends the foe turn without damage, bleeding or mana shield loss" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var checked: usize = 0;
    for (heroes.CLASSES) |c| {
        for ([_]bool{ false, true }) |warded| {
            for ([_]bool{ false, true }) |dodged| {
                harness.heroArena(g, c, .{ .x = 20, .y = 20 }, &.{});
                _ = harness.spawnAt(g, .pib, .{ .x = 21, .y = 20 }, true);
                const h = g.sim.heroActor().?;
                if (warded) h.ward.raise();
                const hp = h.hp;
                const clock = g.sim.clock;
                g.sim.rng = harness.bitesRng(g, &.{.{ .id = 2, .lands = !dodged }});
                harness.use(g, .wait);
                try std.testing.expect(!std.meta.eql(clock, g.sim.clock));
                if (dodged) {
                    try std.testing.expectEqual(hp, h.hp);
                    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
                    try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
                } else if (warded) {
                    try std.testing.expectEqual(hp, h.hp);
                    try std.testing.expect(g.sim.mana < g.sim.manaMax());
                } else try std.testing.expect(h.hp < hp);
                g.st = .{};
                game.update(g, harness.TEST_DT);
                try std.testing.expect(g.pic.busy > 0);
                harness.drawnOut(g);
                try std.testing.expectEqual(h.hp, g.pic.pictured[g.sim.heroSlot().?].hp);
                try std.testing.expectEqual(g.sim.mana, g.pic.manaShown(&g.sim));
                if (dodged) try std.testing.expectEqual(@as(f32, 0), g.pic.fx.flashOf(g.sim.heroSlot().?));
                checked += 1;
            }
        }
    }
    std.debug.print("dodge: {d} class/hit/shield cases, misses still animate and spend the foe turn\n", .{checked});
}

test "each spark that stuns costs a chasing rat its next turn, and mana is spent on confirmation" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    try std.testing.expectEqual(actor.Kind.wizard, g.sim.heroActor().?.kind);
    const rat = g.sim.pool.get(2).?;
    harness.wakeFoes(g);
    harness.toughen(rat);
    for (0..2) |_| {
        harness.use(g, .spark);
        try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
        g.sim.rng = harness.procRng(g, .spark, 1, true);
        harness.press(g, CONFIRM);
        harness.drawnOut(g);
    }
    const dealt = harness.TEST_HP - rat.hp;
    try harness.expectDamage(g, .spark, dealt, &.{ spark.BASE, spark.BASE });
    try std.testing.expectEqual(@as(i32, 26), rat.at.x);
    try std.testing.expectEqual(g.sim.manaMax() - 2 * spark.COST + @divTrunc(2 * heroes.MANA_REGEN, heroes.MANA_REGEN_TURNS), g.sim.mana);
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 25), rat.at.x);
    std.debug.print("spark: {d} lightning over 2 stunning hits; the rat lost both turns, then walked on\n", .{dealt});
}

test "a knight's shield bash knocks a foe back a tile, and its stun keeps the foe from stepping back in" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    var landed: [2]i32 = undefined;
    for ([_]bool{ true, false }, &landed) |stuns, *x| {
        harness.heroArena(g, .knight, from, &.{.{ .x = 21, .y = 20 }});
        const rat = g.sim.pool.get(2).?;
        harness.wakeFoes(g);
        harness.toughen(rat);
        const hp = g.sim.heroActor().?.hp;
        harness.use(g, .shield_bash);
        try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
        try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mode.aim.mark);
        g.sim.rng = harness.procRng(g, .shield_bash, 1, stuns);
        harness.press(g, CONFIRM);
        const dealt = harness.TEST_HP - rat.hp;
        try harness.expectDamage(g, .shield_bash, dealt, &.{bash.BASE});
        try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
        try std.testing.expectEqual(manaAfter(g, .shield_bash), g.sim.mana);
        try std.testing.expectEqual(bash.COOLDOWN - 1, g.sim.cooldown.get(.shield_bash));
        x.* = rat.at.x;
        harness.drawnOut(g);
        try std.testing.expect(harness.samePx(glide.cellPx(rat.at), g.pic.glide[actor.Pool.slot(2)].now()));
    }
    try std.testing.expectEqual(@as(i32, 22), landed[0]);
    try std.testing.expectEqual(@as(i32, 21), landed[1]);
    harness.heroArena(g, .knight, from, &.{.{ .x = 21, .y = 20 }});
    g.sim.lv.set(.{ .x = 22, .y = 20 }, .wall);
    harness.use(g, .shield_bash);
    g.sim.rng = harness.procRng(g, .shield_bash, 1, true);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.sim.pool.get(2).?.at);
    std.debug.print("shield bash: stunned rat ends the turn at x {d}, unstunned steps back to x {d}; against a wall it stays\n", .{ landed[0], landed[1] });
}

test "a foe knocked back and stepping in again is drawn on its cell until the bash lands, then knocked the whole tile" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{at});
    const rat = g.sim.pool.get(2).?;
    harness.wakeFoes(g);
    harness.toughen(rat);
    harness.use(g, .shield_bash);
    g.sim.rng = harness.procRng(g, .shield_bash, 1, false);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(i32, 21), rat.at.x);
    const gl = &g.pic.glide[actor.Pool.slot(2)];
    try std.testing.expect(harness.samePx(glide.cellPx(at), gl.now()));
    var held: f32 = 0;
    var furthest: f32 = 0;
    var t: f32 = 0;
    while (t < 2 and g.pic.busy > 0) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (harness.samePx(glide.cellPx(at), gl.now())) held = t + harness.TEST_DT;
        furthest = @max(furthest, gl.now().x);
    }
    std.debug.print("knocked rat: still on its cell {d:.3} s in (the bash lands at {d:.3}), knocked to x {d:.1} px of {d}\n", .{ held, game.BUMP_LANDS, furthest, glide.cellPx(at.add(.{ .x = 1, .y = 0 })).x });
    try std.testing.expect(held + harness.TEST_TOL >= game.BUMP_LANDS);
    try std.testing.expect(furthest > glide.cellPx(at.add(.{ .x = 1, .y = 0 })).x - 1);
}

test "a cleave strikes only the bodies in its arc as it is swung, not a half split into it by the same swing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const slime = P{ .x = 21, .y = 19 };
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{});
    for ([_]P{ .{ .x = 20, .y = 18 }, .{ .x = 21, .y = 18 }, .{ .x = 22, .y = 18 }, .{ .x = 20, .y = 19 }, .{ .x = 22, .y = 19 }, .{ .x = 22, .y = 20 } }) |w| g.sim.lv.set(w, .wall);
    const id = harness.spawnAt(g, .slime, slime, false);
    g.sim.pool.get(id).?.hp = @divTrunc(actor.row(.slime).hp, 2);
    harness.use(g, .cleave);
    harness.nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mode.aim.mark);
    harness.press(g, CONFIRM);
    var slimes: usize = 0;
    for (g.sim.pool.slice()) |a| {
        if (!a.alive or a.kind == .knight) continue;
        slimes += 1;
        try std.testing.expectEqual(actor.Kind.slime_half, a.kind);
        try std.testing.expectEqual(a.max, a.hp);
    }
    std.debug.print("cleave on a slime that splits into the arc: {d} halves, both whole\n", .{slimes});
    try std.testing.expectEqual(@as(usize, 2), slimes);
}

test "a knight's cleave strikes the three tiles of its arc and nothing outside it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const arc = [_]P{ .{ .x = 21, .y = 19 }, .{ .x = 21, .y = 20 }, .{ .x = 21, .y = 21 } };
    const outside = [_]P{ .{ .x = 19, .y = 20 }, .{ .x = 20, .y = 21 } };
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &(arc ++ outside));
    harness.toughenFoes(g);
    harness.use(g, .cleave);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    harness.nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mode.aim.mark);
    harness.press(g, CONFIRM);
    var hit: usize = 0;
    for (harness.foes(g), 0..) |a, i| {
        const lost = harness.TEST_HP - a.hp;
        if (i < arc.len) {
            try harness.expectDamage(g, .cleave, lost, &.{cleave.BASE});
            hit += 1;
        } else try std.testing.expectEqual(@as(i32, 0), lost);
    }
    try std.testing.expectEqual(manaAfter(g, .cleave), g.sim.mana);
    std.debug.print("cleave: {d} of {d} rats struck, the {d} outside its arc untouched\n", .{ hit, arc.len + outside.len, outside.len });
}

test "a wizard's blink lands further than juke and takes a turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.heroArena(g, .wizard, from, &.{.{ .x = 30, .y = 20 }});
    const rat = g.sim.pool.get(2).?;
    harness.wakeFoes(g);
    const hour = g.sim.clock;
    harness.use(g, .blink);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    for (0..blink.RANGE + 1) |_| harness.nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 20 + blink.RANGE, .y = 20 }, g.mode.aim.mark);
    const landing = g.mode.aim.mark;
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(landing, g.sim.heroActor().?.at);
    try std.testing.expect(g.pic.glide[actor.Pool.slot(2)].t <= -game.STAGGER_S + harness.TEST_TOL);
    try std.testing.expect(!std.meta.eql(hour, g.sim.clock));
    try std.testing.expectEqual(@as(i32, 29), rat.at.x);
    try std.testing.expectEqual(manaAfter(g, .blink), g.sim.mana);
    try std.testing.expectEqual(blink.COOLDOWN - 1, g.sim.cooldown.get(.blink));
    std.debug.print("blink: {d} tiles in a turn; the rat stepped once\n", .{blink.RANGE});
}

test "a pinning shot holds a chasing rat to its cell for two to four of its turns, and a pinned rat still bites" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const rat = g.sim.pool.get(2).?;
    harness.wakeFoes(g);
    harness.toughen(rat);
    harness.use(g, .pinning_shot);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    harness.press(g, CONFIRM);
    const dealt = harness.TEST_HP - rat.hp;
    try harness.expectDamage(g, .pinning_shot, dealt, &.{bow.BASE});
    try std.testing.expectEqual(manaAfter(g, .pinning_shot), g.sim.mana);
    var held: usize = 1;
    while (rat.at.x == 26 and held < 10) {
        harness.use(g, .wait);
        if (rat.at.x == 26) held += 1;
    }
    try harness.expectWithin(held, pinning.TURNS_LO, pinning.TURNS_HI);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    const biter = g.sim.pool.get(2).?;
    harness.wakeFoes(g);
    biter.pin.turns = pinning.TURNS_HI;
    const hp = g.sim.heroActor().?.hp;
    g.sim.rng = harness.bitesRng(g, &.{.{ .id = 2, .lands = true }});
    harness.use(g, .wait);
    try std.testing.expect(g.sim.heroActor().?.hp < hp);
    try std.testing.expectEqual(@as(i32, 21), biter.at.x);
    std.debug.print("pinning shot: {d} damage, the rat held {d} turns, then walked on; pinned beside the hero it bit for {d}\n", .{ dealt, held, hp - g.sim.heroActor().?.hp });
}

test "a barbed arrow always opens a bleed on a body it leaves alive" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const rat = g.sim.pool.get(2).?;
    harness.toughen(rat);
    harness.use(g, .barbed_arrow);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    harness.press(g, CONFIRM);
    const dealt = harness.TEST_HP - rat.hp;
    try harness.expectDamage(g, .barbed_arrow, dealt, &.{bow.BASE});
    try std.testing.expectEqual(bleeding.TURNS, rat.bleed.turns);
    try std.testing.expectEqual(manaAfter(g, .barbed_arrow), g.sim.mana);
    harness.use(g, .wait);
    try std.testing.expect(harness.TEST_HP - rat.hp > dealt);
    std.debug.print("barbed arrow: {d} damage, a {d}-turn bleed, which bled {d} the next turn\n", .{ dealt, bleeding.TURNS, harness.TEST_HP - rat.hp - dealt });
}

test "a frost nova freezes every foe within two tiles, critical and rounded for each apart, and none further" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const seeds = 32;
    var apart: usize = 0;
    for (0..seeds) |seed| {
        harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 22, .y = 22 }, .{ .x = 23, .y = 20 } });
        harness.toughenFoes(g);
        g.sim.rng = mathx.Rng.init(seed);
        harness.use(g, .frost_nova);
        const near = harness.TEST_HP - g.sim.pool.get(2).?.hp;
        const off = harness.TEST_HP - g.sim.pool.get(3).?.hp;
        try harness.expectDamage(g, .frost_nova, near, &.{nova.BASE});
        try harness.expectDamage(g, .frost_nova, off, &.{nova.BASE});
        apart += @intFromBool(near != off);
        try std.testing.expectEqual(harness.TEST_HP, g.sim.pool.get(4).?.hp);
        try std.testing.expectEqual(manaAfter(g, .frost_nova), g.sim.mana);
        try std.testing.expectEqual(nova.COOLDOWN - 1, g.sim.cooldown.get(.frost_nova));
    }
    try std.testing.expect(apart > 0);
    std.debug.print("frost nova: {d} of {d} casts struck the foes 1 and 2 tiles off differently, none to the one 3 off\n", .{ apart, seeds });
}

test "a half split into the cell of a body the same blow kills slides out once that body is no longer drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const cell = P{ .x = 21, .y = 20 };
    const at = P{ .x = 22, .y = 20 };
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{cell});
    g.sim.pool.get(2).?.hp = 1;
    const id = harness.splittable(g, at, false);
    var ring = grid.Box.around(at, 1).cells();
    while (ring.next()) |p| {
        if (!p.eq(at) and !p.eq(cell)) g.sim.lv.set(p, .wall);
    }
    game.settle(g);
    harness.use(g, .frost_nova);
    const dying = actor.Pool.slot(2);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(!g.sim.pool.items[dying].alive);
    try std.testing.expect(g.sim.pool.items[half].at.eq(cell));
    var overlap: f32 = 0;
    var t: f32 = 0;
    g.st = .{};
    while (t < 1) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (g.pic.standing(&g.sim, dying) and harness.drawn(g, half) and g.pic.glide[half].done() > 0) overlap += harness.TEST_DT;
    }
    std.debug.print("a half split into a dying rat's cell: {d:.3} s drawn together\n", .{overlap});
    try std.testing.expect(overlap <= harness.TEST_TOL);
    try std.testing.expect(g.pic.glide[half].done() >= 1);
}

test "a fireball bursts on the first foe it strikes, burning the foes round it, and none past its blast" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 26, .y = 20 }, .{ .x = 27, .y = 21 }, .{ .x = 29, .y = 20 } });
    harness.toughenFoes(g);
    harness.use(g, .fireball);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    harness.press(g, CONFIRM);
    const struck = harness.TEST_HP - g.sim.pool.get(2).?.hp;
    try harness.expectDamage(g, .fireball, struck, &.{fireball.BASE});
    try harness.expectDamage(g, .fireball, harness.TEST_HP - g.sim.pool.get(3).?.hp, &.{fireball.BASE});
    try std.testing.expectEqual(harness.TEST_HP, g.sim.pool.get(4).?.hp);
    try std.testing.expectEqual(manaAfter(g, .fireball), g.sim.mana);
    std.debug.print("fireball: {d} fire to the struck rat, {d} to the one beside it, none to the rat 3 tiles on\n", .{ struck, harness.TEST_HP - g.sim.pool.get(3).?.hp });
}

test "chain lightning leaps from the struck foe to two more, each within three tiles of the last" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 26, .y = 21 }, .{ .x = 29, .y = 21 }, .{ .x = 25, .y = 25 } });
    harness.toughenFoes(g);
    harness.use(g, .chain_lightning);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    harness.press(g, CONFIRM);
    var hit: usize = 0;
    for ([_]u16{ 2, 3, 4 }) |id| {
        const dealt = harness.TEST_HP - g.sim.pool.get(id).?.hp;
        try harness.expectDamage(g, .chain_lightning, dealt, &.{chain.BASE});
        hit += 1;
    }
    try std.testing.expectEqual(harness.TEST_HP, g.sim.pool.get(5).?.hp);
    try std.testing.expectEqual(manaAfter(g, .chain_lightning), g.sim.mana);
    std.debug.print("chain lightning: {d} rats struck, the fourth 4 tiles from each left whole\n", .{hit});
}

test "resisted chain lightning still holds play until its last jump" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 26, .y = 21 }, .{ .x = 29, .y = 21 } });
    for (harness.foes(g)) |*a| a.resists.set(.lightning, 100);
    harness.confirmUse(g, .chain_lightning);
    const last = g.pic.shot.?.lands() + chain.JUMPS * game.ZAP_S;
    try std.testing.expect(g.pic.busy >= last);
    g.st = .{ .pressed = .initOne(.y) };
    const before = g.sim.clock;
    game.update(g, last - game.ZAP_S / 2);
    try std.testing.expectEqual(before, g.sim.clock);
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(usize, 0), g.pic.fx.due_n);
    std.debug.print("resisted chain lightning: {d} jumps hold play for {d:.3} s\n", .{ chain.JUMPS, last });
}

test "a mana shield turns a bite onto mana, the orb dropping as the bite lands, until its turns run out" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    const h = g.sim.heroActor().?;
    const hp = h.hp;
    g.sim.rng = harness.bitesRng(g, &.{.{ .id = 2, .lands = true }});
    harness.use(g, .mana_shield);
    const after_cast = manaAfter(g, .mana_shield);
    const bitten = after_cast - g.sim.mana;
    try std.testing.expectEqual(hp, h.hp);
    try harness.expectWithin(bitten, 1, 3);
    try std.testing.expectEqual(ward.TURNS - 1, h.ward.turns);
    try std.testing.expectEqual(after_cast, g.sim.mana + g.pic.mana_held);
    g.st = .{};
    game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(ward.TURNS, g.pic.pictured[g.sim.heroSlot().?].status.get(.warded));
    try std.testing.expect(g.pic.mana_held > 0);
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(i32, 0), g.pic.mana_held);
    for (1..ward.TURNS) |_| harness.use(g, .wait);
    try std.testing.expectEqual(hp, h.hp);
    try std.testing.expectEqual(@as(u8, 0), h.ward.turns);
    g.sim.rng = harness.bitesRng(g, &.{.{ .id = 2, .lands = true }});
    harness.use(g, .wait);
    try std.testing.expect(h.hp < hp);
    std.debug.print("mana shield: a bite of {d} taken from mana, the orb holding till it landed; {d} turns, then the bites drew blood\n", .{ bitten, ward.TURNS });
}

test "mana shield deductions follow each staggered hit" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 20, .y = 21 } });
    harness.wakeFoes(g);
    g.sim.rng = harness.bitesRng(g, &.{ .{ .id = 2, .lands = true }, .{ .id = 3, .lands = true } });
    harness.use(g, .mana_shield);
    const before = manaAfter(g, .mana_shield);
    try std.testing.expectEqual(before, g.sim.mana + g.pic.mana_held);
    g.st = .{};
    game.update(g, game.BUMP_LANDS + game.STAGGER_S * 1.5);
    const between = g.sim.mana + g.pic.mana_held;
    try std.testing.expect(between < before);
    try std.testing.expect(between > g.sim.mana);
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(i32, 0), g.pic.mana_held);
    std.debug.print("mana shield: shown mana {d}, {d}, {d} across two hits\n", .{ before, between, g.sim.mana });
}

test "a mana shield's last turn stays drawn until the foes' moves of that turn are" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    harness.wakeFoes(g);
    const h = g.sim.heroActor().?;
    h.ward.turns = 1;
    g.st = .{};
    game.update(g, harness.TEST_DT);
    const hero = g.sim.heroSlot().?;
    try std.testing.expectEqual(@as(u8, 1), g.pic.pictured[hero].status.get(.warded));
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 1), mathx.dist(g.sim.pool.get(2).?.at, h.at));
    try std.testing.expectEqual(@as(u8, 0), h.ward.turns);
    try std.testing.expect(g.pic.busy > 0);
    try std.testing.expectEqual(@as(u8, 1), g.pic.pictured[hero].status.get(.warded));
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[hero].status.get(.warded));
    std.debug.print("mana shield: last turn drawn through the rat's step, gone after\n", .{});
}

test "a charge runs the knight down a line to the foe, striking it and knocking it back, but a pinned foe stands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var stood: [2]i32 = undefined;
    for ([_]bool{ false, true }, &stood) |pinned, *x| {
        harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
        const rat = g.sim.pool.get(2).?;
        harness.toughen(rat);
        skipsNext(rat);
        if (pinned) rat.pin.turns = pinning.TURNS_HI;
        harness.use(g, .charge);
        try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
        try std.testing.expectEqual(P{ .x = 23, .y = 20 }, g.mode.aim.mark);
        harness.press(g, CONFIRM);
        try std.testing.expectEqual(P{ .x = 22, .y = 20 }, g.sim.heroActor().?.at);
        const dealt = harness.TEST_HP - rat.hp;
        try harness.expectDamage(g, .charge, dealt, &.{charge.BASE});
        try std.testing.expectEqual(manaAfter(g, .charge), g.sim.mana);
        try std.testing.expectEqual(charge.COOLDOWN - 1, g.sim.cooldown.get(.charge));
        x.* = rat.at.x;
    }
    try std.testing.expectEqual(@as(i32, 24), stood[0]);
    try std.testing.expectEqual(@as(i32, 23), stood[1]);
    std.debug.print("charge: 2 tiles run, the rat knocked to x {d}; pinned, it stood at x {d}\n", .{ stood[0], stood[1] });
}

test "a knocked rat's bleed lands once its knock slide has ended" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
    const rat = g.sim.pool.get(2).?;
    harness.toughen(rat);
    skipsNext(rat);
    bleedingNow(rat);
    harness.confirmUse(g, .charge);
    const i = actor.Pool.slot(2);
    try std.testing.expectEqual(@as(i32, 24), rat.at.x);
    const bled = rat.hp;
    g.st = .{};
    var t: f32 = 0;
    while (g.pic.pictured[i].hp != bled and t < 2) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(bled, g.pic.pictured[i].hp);
    try std.testing.expect(g.pic.glide[i].left() <= harness.TEST_TOL);
    std.debug.print("knocked and bleeding: the tick landed {d:.3} s in, the slide done\n", .{t});
}

test "bleeding doubles after knockback even if the foe loses its action" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var checked: usize = 0;
    for ([_]bool{ false, true }) |pinned| {
        var hp: [2]i32 = undefined;
        for ([_]bool{ false, true }, &hp) |bleeds, *left| {
            harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
            g.sim.rng = mathx.Rng.init(17);
            const rat = g.sim.pool.get(2).?;
            harness.toughen(rat);
            skipsNext(rat);
            if (pinned) rat.pin.turns = pinning.TURNS_HI;
            if (bleeds) bleedingNow(rat);
            harness.confirmUse(g, .charge);
            left.* = rat.hp;
            try std.testing.expectEqual(@as(i32, if (pinned) 23 else 24), rat.at.x);
            if (bleeds) {
                harness.drawnOut(g);
                skipsNext(rat);
                combat.endTurn(g);
                try std.testing.expectEqual(bleeding.STILL, left.* - rat.hp);
            }
        }
        try std.testing.expectEqual(if (pinned) bleeding.STILL else bleeding.MOVING, hp[0] - hp[1]);
        checked += 1;
    }
    std.debug.print("{d} bleeding cases: a stalled knocked foe moves; a pinned foe stays still\n", .{checked});
}

test "rejected skills preserve simulation across every class and readiness gate" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const Gate = enum { busy, locked, cooling, mana, empty };
    var counts = std.EnumArray(Gate, usize).initFill(0);
    for (heroes.CLASSES) |class| {
        for (skillbar.kit(class)) |act| {
            if (act == .wait or act == .secondary) continue;
            for (std.enums.values(Gate)) |gate| {
                const foe_at = P{ .x = if (act.reticle() == .rush) 23 else 21, .y = 20 };
                harness.heroArena(g, class, .{ .x = 20, .y = 20 }, &.{foe_at});
                if (act == .combustion) g.sim.pool.get(2).?.burn.turns = burning.TURNS;
                switch (gate) {
                    .busy => g.pic.busy = 0.5,
                    .locked => {
                        if (act.flaskOf() != null) continue;
                        g.sim.growth.ranks.set(act, 0);
                    },
                    .cooling => g.sim.cooldown.set(act, 2),
                    .mana => {
                        const cost = g.sim.growth.cost(act);
                        if (cost == 0) continue;
                        g.sim.mana = cost - 1;
                    },
                    .empty => {
                        const kind = act.flaskOf() orelse continue;
                        g.sim.flasks.getPtr(kind).charges = 0;
                    },
                }
                g.sim.unsaved = false;
                const before = .{ g.sim.clock, g.sim.rng, g.sim.loot_rng, g.sim.mana, g.sim.mana_recovery, g.sim.flasks, g.sim.cooldown, g.sim.growth, g.sim.gold, g.sim.kills, g.sim.unsaved };
                const bodies = try std.testing.allocator.dupe(actor.Actor, g.sim.pool.slice());
                defer std.testing.allocator.free(bodies);
                skills.useSkill(g, .{ .act = act, .by = .x });
                try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
                try std.testing.expectEqualDeep(before, .{ g.sim.clock, g.sim.rng, g.sim.loot_rng, g.sim.mana, g.sim.mana_recovery, g.sim.flasks, g.sim.cooldown, g.sim.growth, g.sim.gold, g.sim.kills, g.sim.unsaved });
                try std.testing.expectEqualSlices(actor.Actor, bodies, g.sim.pool.slice());
                try std.testing.expect(g.pic.shot == null and g.pending == null);
                counts.getPtr(gate).* += 1;
            }
        }
    }
    for (counts.values) |count| try std.testing.expect(count > 0);
    std.debug.print("skill rejection: busy {d}, locked {d}, cooling {d}, mana {d}, empty flask {d}; actors, resources, RNG and progression unchanged\n", .{ counts.get(.busy), counts.get(.locked), counts.get(.cooling), counts.get(.mana), counts.get(.empty) });
}

test "every targeted skill rechecks readiness and bounds at confirmation without spending" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const Gate = enum { bounds, busy, locked, cooling, mana };
    var checked: usize = 0;
    for (heroes.CLASSES) |class| {
        for (progress.skills(class)) |skill| {
            const act = skill.act;
            const reticle = act.reticle() orelse continue;
            for (std.enums.values(Gate)) |gate| {
                const from = P{ .x = 20, .y = 20 };
                const foe_at = P{ .x = if (reticle == .rush) 23 else 21, .y = 20 };
                harness.heroArena(g, class, from, &.{foe_at});
                skills.aiming(g, .x, act);
                g.mode.aim.mark = if (reticle == .leap) .{ .x = 22, .y = 20 } else foe_at;
                if (act == .combustion) g.sim.pool.get(2).?.burn.turns = burning.TURNS;
                if (act == .arcane_barrier) {
                    g.mode.aim.action = .{ .wall_end = .{ .x = 21, .y = 21 } };
                    g.mode.aim.mark = .{ .x = 22, .y = 21 };
                }
                try std.testing.expect(skills.aimable(g, from, g.mode.aim.mark));
                switch (gate) {
                    .bounds => g.mode.aim.mark = .{ .x = -1, .y = -1 },
                    .busy => g.pic.busy = 0.5,
                    .locked => g.sim.growth.ranks.set(act, 0),
                    .cooling => g.sim.cooldown.set(act, 2),
                    .mana => {
                        const cost = g.sim.growth.cost(act);
                        if (cost == 0) continue;
                        g.sim.mana = cost - 1;
                    },
                }
                g.sim.unsaved = false;
                const before = .{ g.sim.clock, g.sim.rng, g.sim.mana, g.sim.mana_recovery, g.sim.flasks, g.sim.cooldown, g.sim.growth, g.sim.unsaved };
                const aim_before = .{ g.mode.aim.mark, g.mode.aim.anchor(), g.mode.aim.act(), g.mode.aim.by };
                const bodies = try std.testing.allocator.dupe(actor.Actor, g.sim.pool.slice());
                defer std.testing.allocator.free(bodies);
                skills.confirmAim(g);
                try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
                try std.testing.expectEqualDeep(aim_before, .{ g.mode.aim.mark, g.mode.aim.anchor(), g.mode.aim.act(), g.mode.aim.by });
                try std.testing.expectEqualDeep(before, .{ g.sim.clock, g.sim.rng, g.sim.mana, g.sim.mana_recovery, g.sim.flasks, g.sim.cooldown, g.sim.growth, g.sim.unsaved });
                try std.testing.expectEqualSlices(actor.Actor, bodies, g.sim.pool.slice());
                try std.testing.expect(g.pic.shot == null);
                checked += 1;
            }
        }
    }
    try std.testing.expect(checked > 0);
    std.debug.print("target confirmation: {d} out-of-bounds and changed-readiness cases preserve the reticle and simulation\n", .{checked});
}
