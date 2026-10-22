const std = @import("std");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const gen = @import("../map/gen.zig");
const gas = @import("../map/gas.zig");
const atlas = @import("../map/atlas.zig");
const spar = @import("../map/spar.zig");
const menu = @import("../ui/menu.zig");
const hud = @import("../ui/hud.zig");
const book = @import("../ui/book.zig");
const heroes = @import("../play/hero.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const damage = @import("../play/damage.zig");
const attrs = @import("../play/attrs.zig");
const burning = @import("../play/burning.zig");
const bleeding = @import("../play/bleeding.zig");
const glacial = @import("../play/glacial.zig");
const juke = @import("../play/juke.zig");
const blink = @import("../play/blink.zig");
const spark = @import("../play/spark.zig");
const bash = @import("../play/bash.zig");
const cleave = @import("../play/cleave.zig");
const pinning = @import("../play/pinning.zig");
const nova = @import("../play/nova.zig");
const fireball = @import("../play/fireball.zig");
const chain = @import("../play/chain.zig");
const ward = @import("../play/ward.zig");
const charge = @import("../play/charge.zig");
const flask = @import("../play/flask.zig");
const pack = @import("../play/pack.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const light = @import("../gfx/light.zig");
const fx = @import("../gfx/fx.zig");
const cinema = @import("../gfx/cinema.zig");
const vignette = @import("../gfx/vignette.zig");
const sky = @import("../gfx/sky.zig");
const climate = @import("../map/climate.zig");
const day = @import("../map/day.zig");
const shots = @import("shots.zig");
const scene = @import("scene.zig");
const overlay = @import("overlay.zig");
const character = @import("character.zig");
const combat = @import("combat.zig");
const harness = @import("harness.zig");
const game = @import("../game.zig");
const P = mathx.P;
const BOOK = book.SIZE;
const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;
const CHANGE = menu.CHANGE;
const REMOVE = menu.REMOVE;
const CHARACTER = menu.CHARACTER;
const PAUSE = menu.PAUSE;
const HERO = actor.HERO;

test "skills cannot start a second turn while the first is still being drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const clock = g.clock;
    const hp = g.heroActor().?.hp;
    g.busy = 0.5;
    var bound: usize = 0;
    for (skillbar.SLOTS) |button| {
        const act = g.bar.at(.{ .set = .primary, .button = button }) orelse continue;
        if (act == .secondary) continue;
        bound += 1;
        g.st = .{ .pressed = .initOne(button) };
        game.update(g, 0);
        try std.testing.expectEqual(game.Mode.play, g.mode);
        try std.testing.expectEqual(clock, g.clock);
        try std.testing.expectEqual(hp, g.heroActor().?.hp);
        try std.testing.expectEqual(game.manaMax(g), g.mana);
        try std.testing.expectEqual(act, g.pending.?.skill.act);
    }
    g.pending = null;
    g.busy = 0;
    game.openAim(g, .x, .shoot);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    g.busy = 0.5;
    game.confirmAim(g);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expect(g.shot == null);
    g.busy = 0;
    game.confirmAim(g);
    try std.testing.expect(!std.meta.eql(clock, g.clock));
    try std.testing.expect(g.shot != null);
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
    g.pool.get(6).?.resists.set(.cold, 100);
    g.lv.set(.{ .x = 27, .y = 20 }, .wall);
    game.settle(g);
    const clock = g.clock;
    g.mana = glacial.COST - 1;
    harness.pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(game.Mode.play, g.mode);
    g.mana = game.manaMax(g);
    harness.pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    harness.press(g, .b);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    harness.pressHolding(g, .x, &.{.lb});
    g.mark = g.heroActor().?.at;
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    g.mark = .{ .x = 26, .y = 20 };
    g.rng = harness.procRng(g, .glacial_shot, 1, true);
    harness.press(g, CONFIRM);
    const direct = g.pool.get(2).?;
    const splash = g.pool.get(3).?;
    const dealt = harness.TEST_HP - direct.hp;
    try harness.expectDamage(g, .glacial_shot, dealt, &.{ bow.BASE, glacial.BASE });
    try harness.expectDamage(g, .glacial_shot, harness.TEST_HP - splash.hp, &.{glacial.BASE});
    for ([_]u16{ 4, 5, 6 }) |id| try std.testing.expectEqual(harness.TEST_HP, g.pool.get(id).?.hp);
    try std.testing.expectEqual(@as(u8, 0), g.pool.get(6).?.chill.turns);
    try std.testing.expectEqual(manaAfter(g, .glacial_shot), g.mana);
    try std.testing.expectEqual(glacial.TURNS - 1, direct.chill.turns);
    try std.testing.expectEqual(@as(u8, 0), g.pictured[actor.Pool.slot(2)].status.get(.chilled));
    try std.testing.expectEqual(harness.TEST_HP, g.pictured[actor.Pool.slot(3)].hp);
    try std.testing.expectEqual(skillbar.Act.glacial_shot, g.shot.?.act);
    harness.drawnOut(g);
    try std.testing.expectEqual(direct.chill.turns, g.pictured[actor.Pool.slot(2)].status.get(.chilled));
    try std.testing.expectEqual(splash.hp, g.pictured[actor.Pool.slot(3)].hp);
    std.debug.print("Glacial Shot: {d} direct, {d} cone damage; 3 protected targets untouched; mana {d}; chill shown at impact\n", .{ dealt, harness.TEST_HP - splash.hp, g.mana });
}

test "glacial shot uses an intervening body or barrel and an empty shot has no cone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{ .{ .x = 24, .y = 20 }, .{ .x = 28, .y = 20 } });
    const near = g.pool.get(2).?;
    near.resists.set(.cold, 100);
    harness.pressHolding(g, .x, &.{.lb});
    g.mark = .{ .x = 28, .y = 20 };
    harness.press(g, CONFIRM);
    try harness.expectDamage(g, .glacial_shot, actor.row(.rat).hp - near.hp, &.{bow.BASE});
    try std.testing.expectEqual(@as(u8, 0), near.chill.turns);
    try std.testing.expectEqual(actor.row(.rat).hp, g.pool.get(3).?.hp);
    harness.arena(g, from, &.{.{ .x = 26, .y = 20 }});
    harness.toughenFoes(g);
    const barrel = P{ .x = 24, .y = 20 };
    g.lv.putBarrel(barrel);
    harness.pressHolding(g, .x, &.{.lb});
    harness.press(g, CONFIRM);
    try std.testing.expect(!g.lv.hasBarrel(barrel));
    try std.testing.expect(g.ground.coin_n > 0);
    const splash = harness.TEST_HP - g.pool.get(2).?.hp;
    try harness.expectDamage(g, .glacial_shot, splash, &.{glacial.BASE});
    harness.arena(g, from, &.{.{ .x = 26, .y = 21 }});
    harness.pressHolding(g, .x, &.{.lb});
    g.mark = .{ .x = 25, .y = 20 };
    harness.press(g, CONFIRM);
    try std.testing.expect(g.shot.?.flight.struck == null);
    try std.testing.expectEqual(actor.row(.rat).hp, g.pool.get(2).?.hp);
    std.debug.print("Glacial Shot: first body intercepts, barrel bursts for {d} cold splash, empty shot has no explosion\n", .{splash});
}

test "glacial splash beyond sight does damage without naming the unseen foe in the log" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 29, .y = 20 }});
    const far = harness.spawnAt(g, .bloat, .{ .x = 31, .y = 20 }, false);
    harness.toughenFoes(g);
    game.settle(g);
    try std.testing.expect(!g.lv.isLit(g.pool.get(far).?.at));
    harness.pressHolding(g, .x, &.{.lb});
    harness.press(g, CONFIRM);
    const lost = harness.TEST_HP - g.pool.get(far).?.hp;
    try harness.expectDamage(g, .glacial_shot, lost, &.{glacial.BASE});
    for (0..g.log.n) |i| try std.testing.expect(std.mem.indexOf(u8, g.log.line(i).?, "bloat") == null);
    std.debug.print("unseen glacial splash: {d} damage, 0 log lines naming the hidden bloat\n", .{lost});
}

test "chill slows movement and attacks while idle frames preserve it and skipped turns still take burn and gas" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 28, .y = 20 }});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    rat.chill.apply();
    for (0..glacial.TURNS) |i| {
        harness.use(g, .wait);
        harness.drawnOut(g);
        try std.testing.expectEqual(@as(i32, 28) - @as(i32, @intCast(@min(i + 1, glacial.CYCLE - 1))), rat.at.x);
    }
    try std.testing.expectEqual(@as(u8, 0), rat.chill.turns);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    const adjacent = g.pool.get(2).?;
    adjacent.awake = true;
    harness.toughen(adjacent);
    adjacent.chill = .{ .turns = 2, .phase = glacial.CYCLE - 1 };
    adjacent.burn = .{ .turns = burning.TURNS };
    g.st = .{};
    game.update(g, 1);
    try std.testing.expectEqual(@as(u8, 2), adjacent.chill.turns);
    const hp = g.heroActor().?.hp;
    harness.use(g, .wait);
    try std.testing.expectEqual(hp, g.heroActor().?.hp);
    try std.testing.expectEqual(harness.TEST_HP - burning.PER_TURN, adjacent.hp);
    harness.drawnOut(g);
    adjacent.chill = .{ .turns = 2, .phase = glacial.CYCLE - 1 };
    g.lv.addGas(adjacent.at, harness.TEST_GAS * 10);
    harness.use(g, .wait);
    try std.testing.expectEqual(harness.TEST_HP - 2 * burning.PER_TURN - gas.harm(harness.TEST_HP), adjacent.hp);
    std.debug.print("chill: 2 moves in 3 turns, attack skipped, idle duration unchanged, burning and gas still tick\n", .{});
}

test "glacial chill and its cadence follow slime splits without hitting newborn halves twice" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = splittable(g, .{ .x = 26, .y = 20 }, true);
    const a = g.pool.get(id).?;
    skipsNext(a);
    a.resists.set(.cold, -100);
    combat.burstHit(g, .glacial_shot, .{ .body = id }, a.at, .{ .from = g.heroActor().?.at, .wait = 0.2 });
    try std.testing.expectEqual(@as(usize, 3), g.pool.n);
    const half = g.pool.get(id + 1).?;
    try std.testing.expectEqual(actor.Kind.slime_half, a.kind);
    try std.testing.expectEqual(a.hp, half.hp);
    try std.testing.expectEqual(glacial.TURNS, a.chill.turns);
    try std.testing.expectEqual(@as(u8, 2), a.chill.phase);
    try std.testing.expectEqual(a.chill, half.chill);
    try std.testing.expectEqual(@as(i16, -100), half.resists.get(.cold));
    try std.testing.expect(g.fx.revealing(actor.Pool.slot(id + 1)));
    std.debug.print("Glacial Shot split: 2 equal halves, chill duration {d} and cadence {d} inherited, one damage event each\n", .{ half.chill.turns, half.chill.phase });
}

test "burning arrow spends mana only on confirmation and shows burning when its hit lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 28, .y = 20 }});
    const rat = g.pool.get(2).?;
    harness.toughen(rat);
    game.catchUp(g);
    g.rng = harness.procRng(g, .burning_arrow, 1, true);
    const clock = g.clock;
    harness.press(g, .a);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    harness.press(g, .b);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    harness.press(g, .a);
    harness.press(g, .a);
    const dealt = harness.TEST_HP - rat.hp;
    try harness.expectDamage(g, .burning_arrow, dealt, &.{ bow.BASE, burning.BASE });
    try std.testing.expectEqual(manaAfter(g, .burning_arrow), g.mana);
    try std.testing.expectEqual(burning.TURNS, rat.burn.turns);
    try std.testing.expectEqual(@as(u8, 0), g.pictured[actor.Pool.slot(2)].status.get(.burning));
    try std.testing.expectEqual(skillbar.Act.burning_arrow, g.shot.?.act);
    harness.drawnOut(g);
    try std.testing.expectEqual(burning.TURNS, g.pictured[actor.Pool.slot(2)].status.get(.burning));
    const before = rat.hp;
    for (0..burning.TURNS) |_| {
        harness.use(g, .wait);
        harness.drawnOut(g);
    }
    try std.testing.expectEqual(before - burning.PER_TURN * burning.TURNS, rat.hp);
    try std.testing.expectEqual(@as(u8, 0), g.pictured[actor.Pool.slot(2)].status.get(.burning));
    const after = rat.hp;
    harness.use(g, .wait);
    try std.testing.expectEqual(after, rat.hp);
    std.debug.print("Burning Arrow: {d} on hit, then {d} over {d} later turns; mana {d}, flames delayed until impact\n", .{ dealt, before - after, burning.TURNS, manaAfter(g, .burning_arrow) });
}

test "burning arrow honors fire resistance, refuses insufficient mana and uses the first body in its path" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 27, .y = 20 } });
    const rat = g.pool.get(2).?;
    rat.resists.set(.fire, 100);
    g.mana = burning.COST - 1;
    harness.press(g, .a);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    g.mana = game.manaMax(g);
    harness.press(g, .a);
    g.mark = g.pool.get(3).?.at;
    harness.press(g, .a);
    try harness.expectDamage(g, .burning_arrow, actor.row(.rat).hp - rat.hp, &.{bow.BASE});
    try std.testing.expectEqual(@as(u8, 0), rat.burn.turns);
    try std.testing.expectEqual(actor.row(.rat).hp, g.pool.get(3).?.hp);
    std.debug.print("100% fire resistance: only physical arrow damage, no ignition; far target untouched\n", .{});
}

test "burning and gas both land in order, while a burning kill bursts a bloat" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 28, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
    const rat = g.pool.get(2).?;
    harness.toughen(rat);
    rat.burn = .{ .turns = burning.TURNS };
    rat.resists.set(.fire, 50);
    g.lv.addGas(at, harness.TEST_GAS);
    game.catchUp(g);
    harness.use(g, .wait);
    try std.testing.expectEqual(harness.TEST_HP - gas.harm(harness.TEST_HP) - damage.resisted(burning.PER_TURN, 50), rat.hp);
    harness.drawnOut(g);
    try std.testing.expectEqual(rat.hp, g.pictured[actor.Pool.slot(2)].hp);
    try std.testing.expectEqual(rat.burn.turns, g.pictured[actor.Pool.slot(2)].status.get(.burning));
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .bloat, at, false);
    g.pool.get(id).?.burn = .{ .turns = 1 };
    combat.burnHarm(g, id);
    try std.testing.expect(g.pool.get(id) == null);
    try std.testing.expectEqual(@as(usize, 1), g.kills);
    try std.testing.expectEqual(gas.BURST, g.lv.gasAt(at));
    std.debug.print("burning plus gas: both damage events shown; burning bloat death releases {d} gas\n", .{gas.BURST});
}

test "burning follows both slime halves without an extra application turn or tick" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = splittable(g, .{ .x = 28, .y = 20 }, false);
    const a = g.pool.get(id).?;
    a.burn.start();
    a.resists.set(.fire, 50);
    combat.wound(g, id, .{ .dmg = 4 }, combat.SHOOT, .{ .from = g.heroActor().?.at, .wait = 0 });
    combat.endTurn(g);
    const half = g.pool.get(id + 1).?;
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
    const rat = g.pool.get(2).?;
    rat.awake = true;
    rat.chill.apply();
    game.catchUp(g);
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 24), rat.at.x);
    try std.testing.expectEqual(glacial.TURNS - 1, rat.chill.turns);
    try std.testing.expectEqual(glacial.TURNS, g.pictured[actor.Pool.slot(2)].status.get(.chilled));
    harness.drawnOut(g);
    try std.testing.expectEqual(glacial.TURNS - 1, g.pictured[actor.Pool.slot(2)].status.get(.chilled));
    std.debug.print("chill on a stepping rat: {d} turns shown until its step is drawn, then {d}\n", .{ glacial.TURNS, g.pictured[actor.Pool.slot(2)].status.get(.chilled) });
}

test "a half split off a burning, chilled slime ticks and skips in step with it on its waiting turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = splittable(g, .{ .x = 28, .y = 20 }, false);
    const a = g.pool.get(id).?;
    a.burn = .{ .turns = burning.TURNS };
    a.chill.apply();
    combat.wound(g, id, .{ .dmg = 4 }, combat.SHOOT, .{ .from = g.heroActor().?.at, .wait = 0 });
    combat.endTurn(g);
    const half = g.pool.get(id + 1).?;
    try std.testing.expectEqual(a.hp, half.hp);
    try std.testing.expectEqual(a.burn, half.burn);
    try std.testing.expectEqual(a.chill, half.chill);
    g.st = .{};
    game.update(g, 0);
    for (g.owed) |o| try std.testing.expect(!o.any());
    std.debug.print("split on a burning, chilled slime: both at {d} hp, burn {d} turns, chill {d} turns phase {d}\n", .{ half.hp, half.burn.turns, half.chill.turns, half.chill.phase });
}

test "a half the gas or a burn splits off on the foes' turn keeps the ticks its slime already took" {
    for ([_]bool{ true, false }) |gassed| {
        const g = try game.boot(std.testing.allocator);
        defer game.shut(std.testing.allocator, g);
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const at = P{ .x = 30, .y = 20 };
        const id = harness.spawnAt(g, .slime, at, false);
        const a = g.pool.get(id).?;
        a.hp = harness.SLIME_HALF + @as(i32, if (gassed) 1 else 3);
        a.burn = .{ .turns = 2 };
        a.chill.apply();
        if (gassed) g.lv.addGas(at, gas.BURST);
        combat.endTurn(g);
        const half = g.pool.get(id + 1).?;
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
        const a = g.pool.get(id).?;
        a.hp = harness.SLIME_HALF + 3;
        a.burn = .{ .turns = 2 };
        if (gassed) for (mathx.ALL_DIRS) |d| g.lv.addGas(at.add(d.delta()), gas.GASSED_UP - 1);
        combat.endTurn(g);
        try std.testing.expect(!g.lv.gassy(a.at));
        h.* = g.pool.get(id + 1).?.hp;
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
    g.lv.set(.{ .x = 21, .y = 20 }, .water);
    const clock = g.clock;
    const rng = g.rng;
    harness.press(g, .b);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    for (0..juke.RANGE) |_| harness.nudge(g, .e);
    try std.testing.expectEqual(to, g.mark);
    harness.nudge(g, .e);
    try std.testing.expectEqual(to, g.mark);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(to, g.heroActor().?.at);
    try std.testing.expect(harness.samePx(game.cellPx(to), game.heroNow(g).?));
    try std.testing.expectEqual(grid.NO_ONE, g.lv.who(from));
    try std.testing.expectEqual(g.hero, g.lv.who(to));
    try std.testing.expectEqual(rat, g.pool.get(2).?.at);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(rng, g.rng);
    try std.testing.expectEqual(game.manaMax(g) - juke.COST, g.mana);
    try std.testing.expectEqual(juke.COOLDOWN, g.cooldown.get(.juke));
    try std.testing.expect(g.unsaved);
    var trail: usize = 0;
    for (g.fx.motes) |m| {
        if (m.life > 0 and std.meta.eql(m.col, look.JUKE_TRAIL) and m.p[0] < mathx.centre(from)[0] + 1) trail += 1;
    }
    try std.testing.expect(trail > 0);
    harness.press(g, .b);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    std.debug.print("Juke moved {d} tiles instantly: {d} mana left, {d} turns cooldown, no enemy or clock advance\n", .{ mathx.dist(from, to), g.mana, g.cooldown.get(.juke) });
}

test "juke cancellation and invalid landings cost nothing; recovery requires turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    const clock = g.clock;
    harness.press(g, .b);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    g.lv.putBarrel(.{ .x = 21, .y = 20 });
    harness.nudge(g, .e);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(from, g.heroActor().?.at);
    harness.press(g, CHARACTER);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    try std.testing.expectEqual(@as(u8, 0), g.cooldown.get(.juke));
    try std.testing.expectEqual(clock, g.clock);
    harness.press(g, .b);
    harness.nudge(g, .w);
    harness.press(g, CONFIRM);
    g.st = .{};
    game.update(g, 10);
    try std.testing.expectEqual(juke.COOLDOWN, g.cooldown.get(.juke));
    try std.testing.expectEqual(game.manaMax(g) - juke.COST, g.mana);
    for (0..juke.COOLDOWN) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@as(u8, 0), g.cooldown.get(.juke));
    try std.testing.expectEqual(game.manaMax(g) - juke.COST + heroes.MANA_REGEN * juke.COOLDOWN, g.mana);
    g.mana = juke.COST - 1;
    harness.press(g, .b);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    for (0..@as(usize, @intCast(@divExact(game.manaMax(g), heroes.MANA_REGEN)))) |_| harness.use(g, .wait);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    g.bar.bind(.{ .set = .secondary, .button = .rb }, .juke);
    harness.pressHolding(g, .rb, &.{.lb});
    harness.nudge(g, .w);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(P{ .x = 18, .y = 20 }, g.heroActor().?.at);
    std.debug.print("Juke: free cancel and invalid targets, {d}-turn recovery, mana capped at {d}, secondary binding checked\n", .{ juke.COOLDOWN, game.manaMax(g) });
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
    try std.testing.expectEqual(game.Mode.play, g.mode);
    harness.pressHolding(g, .rb, &.{.lb});
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    try std.testing.expectEqual(input.Button.rb, g.aim_by);
    harness.press(g, .x);
    try std.testing.expect(!g.pool.get(2).?.hurt());
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expect(g.pool.get(2).?.hurt());
}

test "every targeted slot uses standard confirmation in both skill sets" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var checked: usize = 0;
    for (skillbar.SETS) |set| {
        for (skillbar.SLOTS) |by| {
            harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
            harness.toughen(g.pool.get(2).?);
            g.bar = skillbar.Bar.of(.archer);
            const modifier: input.Button = if (by == .lb) .rt else .lb;
            g.bar.bind(.{ .set = .primary, .button = modifier }, .secondary);
            g.bar.bind(.{ .set = set, .button = by }, .shoot);
            const clock = g.clock;
            if (set == .secondary) harness.pressHolding(g, by, &.{modifier}) else harness.press(g, by);
            try std.testing.expectEqual(game.Mode.aim, g.mode);
            try std.testing.expectEqual(clock, g.clock);
            try std.testing.expectEqual(set, g.aim_set);
            if (by != CONFIRM and by != BACK) {
                harness.press(g, by);
                try std.testing.expectEqual(game.Mode.aim, g.mode);
                try std.testing.expectEqual(clock, g.clock);
                try std.testing.expect(!g.pool.get(2).?.hurt());
            }
            harness.press(g, CONFIRM);
            try std.testing.expectEqual(game.Mode.play, g.mode);
            try std.testing.expect(g.pool.get(2).?.hurt());
            try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.clock.minute);
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
            const clock = g.clock;
            const mana = g.mana;
            const cooldown = g.cooldown;
            const at = g.heroActor().?.at;
            harness.press(g, .b);
            try std.testing.expectEqual(game.Mode.aim, g.mode);
            harness.press(g, back);
            try std.testing.expectEqual(game.Mode.play, g.mode);
            try std.testing.expectEqual(clock, g.clock);
            try std.testing.expectEqual(mana, g.mana);
            try std.testing.expectEqual(cooldown, g.cooldown);
            try std.testing.expectEqual(at, g.heroActor().?.at);
            try std.testing.expect(!g.pool.get(2).?.hurt());
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
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    try std.testing.expectEqual(input.Button.y, g.aim_by);
}

test "binding from Skills assigns the selected skill directly and spends no turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const clock = g.clock;
    harness.press(g, menu.CHARACTER);
    g.character.choose(.skills);
    character.characterCommand(g, .{ .bindings = .shoot });
    try std.testing.expectEqual(game.Mode.bind, g.mode);
    g.binds.col = game.Binds.colOf(.y);
    g.binds.row = game.rowAt(skillbar.Set.secondary);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(?skillbar.Act, .shoot), g.bar.at(g.binds.slot()));
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(book.Page.skills, g.character.page);
    character.characterCommand(g, .{ .bindings = .shoot });
    harness.press(g, REMOVE);
    try std.testing.expectEqual(@as(?skillbar.Act, null), g.bar.at(g.binds.slot()));
    harness.press(g, BACK);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    try std.testing.expectEqual(clock, g.clock);
    std.debug.print("bindings: selected skill to either bar in two actions, direct clear, return to Skills, no turns\n", .{});
}

test "binding mouse targets follow both sets at different screen sizes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.clock;
    var checked: usize = 0;
    for ([_]P{ game.SCREEN_720, game.SCREEN_1080 }) |screen| {
        g.screen = screen;
        const panel = overlay.bindPanel(g);
        try std.testing.expect(panel.x < BOOK.x and panel.y < BOOK.y);
        const surface = overlay.bindSurface(g, panel);
        for (skillbar.SETS, 0..) |_, row| for (0..game.SLOT_XS.len) |col| {
            character.openCharacter(g);
            character.characterCommand(g, .{ .bindings = .shoot });
            g.st = .{ .click = true, .pointer = surface.screenOf(look.middle(overlay.bindSlotBox(row, col))) };
            game.update(g, 0);
            try std.testing.expectEqual(row, g.binds.row);
            try std.testing.expectEqual(col, g.binds.col);
            g.st = .{ .click = true, .pointer = surface.screenOf(look.middle(overlay.bindActionBox(panel, 0))) };
            game.update(g, 0);
            try std.testing.expectEqual(@as(?skillbar.Act, .shoot), g.bar.at(g.binds.slot()));
            try std.testing.expectEqual(game.Mode.pause, g.mode);
            checked += 1;
        };
    }
    try std.testing.expectEqual(clock, g.clock);
    std.debug.print("binding mouse: {d} scaled slot selections and assignments, both sets, zero turns\n", .{checked});
}

test "a pool longer than the bar wraps into rows the d-pad walks, and the rows shown scroll to hold the cursor" {
    const n = game.PICK_COLS * 3 + 2;
    const last = n - 1;
    try std.testing.expectEqual(game.PICK_COLS, game.pickStep(0, .{ .x = 0, .y = 1 }, n));
    try std.testing.expectEqual(@as(usize, 1), game.pickStep(game.PICK_COLS + 1, .{ .x = 0, .y = -1 }, n));
    try std.testing.expectEqual(@as(usize, 1), game.pickStep(1, .{ .x = 0, .y = -1 }, n));
    try std.testing.expectEqual(last, game.pickStep(game.PICK_COLS * 2 + game.PICK_COLS - 1, .{ .x = 0, .y = 1 }, n));
    try std.testing.expectEqual(@as(usize, 0), game.pickStep(last, .{ .x = 1, .y = 0 }, n));
    try std.testing.expectEqual(last, game.pickStep(0, .{ .x = -1, .y = 0 }, n));
    try std.testing.expectEqual(game.PICK_COLS + 1, game.pickStep(0, .{ .x = 1, .y = 1 }, n));
    const one_row = game.PICK_MARGIN + game.SLOT_GAP;
    for (0..n) |at| {
        const win = game.pickWindow(0, one_row, n, at);
        try std.testing.expectEqual(@as(usize, 1), win.len);
        try std.testing.expectEqual(at / game.PICK_COLS, win.from);
    }
    const two_rows = one_row + game.SLOT_STEP;
    try std.testing.expectEqual(@as(usize, 2), game.pickWindow(0, two_rows, n, last).len);
    try std.testing.expectEqual(game.pickRows(n) - 2, game.pickWindow(0, two_rows, n, last).from);
    try std.testing.expectEqual(@as(usize, 1), game.pickWindow(two_rows - one_row, two_rows, n, last).len);
    try std.testing.expectEqual(game.pickRows(n), game.pickWindow(0, 10_000, n, 0).len);
}

test "a new floor has every pack placed, no foe in sight or on a barrel" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for (0..40) |i| {
        game.begin(g, 0xF00D +% i *% grid.TEST_SEED_STRIDE);
        var placed: usize = 0;
        for (actor.FOES) |k| {
            const t = g.pool.tally(k);
            try std.testing.expectEqual(t.total, t.left);
            placed += t.total;
        }
        try std.testing.expect(placed >= pack.PER_FLOOR);
        const h = g.heroActor().?;
        for (g.pool.slice()[1..]) |a| {
            try std.testing.expect(!g.lv.isLit(a.at));
            try std.testing.expect(!g.lv.hasBarrel(a.at));
            try std.testing.expect(mathx.dist(a.at, h.at) >= pack.GAP);
        }
    }
}

test "a rat that sees you notices, closes and bites" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    var noticed: ?usize = null;
    var contact: ?usize = null;
    for (0..12) |turn| {
        combat.endTurn(g);
        const r = g.pool.get(2).?;
        if (noticed == null and r.awake) noticed = turn;
        if (contact == null and mathx.dist(r.at, g.heroActor().?.at) == 1) contact = turn;
    }
    const lost = actor.row(HERO).hp - g.heroActor().?.hp;
    std.debug.print("rat 6 away: noticed turn {?d}, adjacent turn {?d}, hero lost {d} hp by turn 12\n", .{ noticed, contact, lost });
    try std.testing.expectEqual(@as(?usize, 0), noticed);
    try std.testing.expectEqual(@as(?usize, 5), contact);
    try std.testing.expect(lost > 0);
}

test "a slime beside you slams you in melee harder than a rat bites" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .slime, .{ .x = 21, .y = 20 }, true);
    combat.endTurn(g);
    const slam = actor.row(.slime).blow.strike;
    const lost = actor.row(HERO).hp - g.heroActor().?.hp;
    std.debug.print("slime slam: {d} hp\n", .{lost});
    try harness.expectWithin(lost, slam.hit.lo, slam.hit.hi);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.pool.get(id).?.at);
}

test "a body faces right until it steps, aims or turns on someone to its left, and straight up or down keeps it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 16, .y = 20 }, .{ .x = 25, .y = 20 } });
    const hero = game.heroSlot(g).?;
    for (g.facing[0..g.pool.n]) |f| try std.testing.expectEqual(game.Facing.right, f);
    harness.nudge(g, .w);
    harness.drawnOut(g);
    try std.testing.expectEqual(game.Facing.left, g.facing[hero]);
    try std.testing.expectEqual(game.Facing.right, g.facing[actor.Pool.slot(2)]);
    try std.testing.expectEqual(game.Facing.left, g.facing[actor.Pool.slot(3)]);
    harness.nudge(g, .n);
    try std.testing.expectEqual(game.Facing.left, g.facing[hero]);
    harness.nudge(g, .e);
    try std.testing.expectEqual(game.Facing.right, g.facing[hero]);
    harness.press(g, .x);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    try std.testing.expect(g.mark.x < g.heroActor().?.at.x);
    try std.testing.expectEqual(game.Facing.left, g.facing[hero]);
}

test "a step moves the hour on a turn's minutes, a bump into a wall does not, and the sky drawn eases after it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.set(.{ .x = 19, .y = 20 }, .wall);
    const was = g.clock.minute;
    harness.nudge(g, .w);
    try std.testing.expectEqual(was, g.clock.minute);
    harness.nudge(g, .e);
    try std.testing.expectEqual(was + day.TURN_MINUTES, g.clock.minute);
    const behind = day.toward(g.hour_shown, g.clock.hour());
    g.st = .{};
    var t: f32 = 0;
    while (day.toward(g.hour_shown, g.clock.hour()) > behind / 100 and t < 2) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    std.debug.print("a step: {d:.3} h ahead of the sky drawn, caught up in {d:.2} s\n", .{ behind, t });
    try std.testing.expect(behind > 0 and t < 2);
}

test "underground a rat past the archer's light is out of sight and out of the bow's reach until a torch lights it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const hero = P{ .x = 20, .y = 20 };
    const rat_at = P{ .x = 27, .y = 20 };
    harness.arena(g, hero, &.{rat_at});
    try std.testing.expect(g.lv.isLit(rat_at) and bow.aimable(&g.lv, hero, rat_at));
    g.outdoors = false;
    game.settle(g);
    try std.testing.expect(!g.lv.isLit(rat_at) and g.lv.inLos(rat_at));
    try std.testing.expect(bow.pick(&g.lv, &g.pool, hero) == null);
    try std.testing.expect(fov.sees(&g.lv, rat_at, hero, actor.row(.rat).sight));
    const wall = rat_at.add(mathx.Dir.n.delta());
    g.lv.set(wall, .wall);
    g.lv.addTorch(wall);
    game.settle(g);
    try std.testing.expect(g.lv.isLit(rat_at) and bow.aimable(&g.lv, hero, rat_at));
}

test "the archer sees further by day than by night out of doors, and as little at midnight as underground" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 40, .y = 30 }, &.{});
    var seen: [4]usize = undefined;
    for ([_]f32{ day.NOON, shots.LATE_DUSK, shots.MIDNIGHT }, 0..) |h, i| {
        g.clock = day.Clock.at(h);
        game.settle(g);
        seen[i] = std.mem.count(bool, &g.lv.lit, &.{true});
    }
    g.outdoors = false;
    game.settle(g);
    seen[3] = std.mem.count(bool, &g.lv.lit, &.{true});
    std.debug.print("cells in the archer's sight: {d} at noon, {d} at dusk, {d} at midnight, {d} underground\n", .{ seen[0], seen[1], seen[2], seen[3] });
    try std.testing.expect(seen[0] > seen[1] and seen[1] > seen[2]);
    try std.testing.expectEqual(seen[3], seen[2]);
}

test "tight diagonals carry movement sight projectiles melee and gas in all four directions" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    for ([_]mathx.Dir{ .ne, .se, .sw, .nw }) |d| {
        const delta = d.delta();
        const near = from.add(delta);
        const ahead = from.add(delta.scaled(2));
        const far = from.add(delta.scaled(3));
        g.lv = grid.Level.blank();
        for (0..4) |i| g.lv.set(from.add(delta.scaled(@intCast(i))), .floor);
        game.reset(g, from);
        g.outdoors = false;
        game.settle(g);
        for ([_]P{ near, ahead, far }) |p| {
            try std.testing.expect(g.lv.isLit(p) and g.lv.isSeen(p));
            try std.testing.expect(bow.aimable(&g.lv, from, p));
        }
        try std.testing.expect(juke.aimable(&g.lv, from, ahead));
        const cone = glacial.cone(&g.lv, from, near);
        try std.testing.expect(cone.has(ahead) and cone.has(far));
        var reverse: [grid.CELLS]bool = @splat(false);
        fov.castInto(&g.lv, far, actor.row(HERO).sight, &reverse);
        try std.testing.expect(reverse[grid.Level.idx(from)]);

        g.lv.set(near, .wall);
        game.castSight(g, from);
        try std.testing.expect(!g.lv.isLit(ahead) and !g.lv.isLit(far));
        try std.testing.expect(!bow.aimable(&g.lv, from, far));
        try std.testing.expectEqual(@as(usize, 0), bow.fly(&g.lv, from, far).len);
        g.lv.set(near, .floor);
        game.castSight(g, from);

        const rat = harness.spawnAt(g, .rat, far, false);
        const flight = bow.fly(&g.lv, from, far);
        try std.testing.expectEqual(@as(?bow.Hit, .{ .body = rat }), flight.struck);
        try std.testing.expectEqual(@as(usize, 3), flight.len);
        harness.nudge(g, d);
        try std.testing.expectEqual(near, g.heroActor().?.at);
        try std.testing.expect(g.pool.get(rat).?.awake);
        harness.use(g, .wait);
        try std.testing.expectEqual(ahead, g.pool.get(rat).?.at);
        const hp = g.heroActor().?.hp;
        const rat_hp = g.pool.get(rat).?.hp;
        g.rng = harness.meleeThenBites(g, 1);
        harness.nudge(g, d);
        try std.testing.expectEqual(near, g.heroActor().?.at);
        try std.testing.expect(g.heroActor().?.hp < hp);
        try std.testing.expect(g.pool.get(rat).?.hp < rat_hp);
        g.lv.addGas(from, gas.BURST);
        gas.turn(&g.lv, &g.rng);
        try std.testing.expect(g.lv.gasAt(near) > 0);
    }
    std.debug.print("4 tight diagonals: walking, pursuit, melee, sight, arrows, Juke, frost and gas agree\n", .{});
}

test "a step into a wall turns no one and spends no turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    harness.wakeFoes(g);
    g.lv.set(.{ .x = 19, .y = 20 }, .wall);
    harness.nudge(g, .w);
    try std.testing.expectEqual(game.Facing.right, g.facing[game.heroSlot(g).?]);
    try std.testing.expectEqual(P{ .x = 25, .y = 20 }, g.pool.get(2).?.at);
}

test "X opens aim on the nearest rat and nothing is spent until standard confirmation" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 27, .y = 20 }, .{ .x = 23, .y = 22 } });
    harness.press(g, .x);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    try std.testing.expectEqual(P{ .x = 23, .y = 22 }, g.mark);
    try std.testing.expect(!g.pool.get(3).?.awake);
    try std.testing.expect(!g.pool.get(3).?.hurt());
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expect(g.pool.get(3).?.hurt());
    try std.testing.expect(!g.pool.get(2).?.hurt());
}

test "B cancels aim and costs no turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    harness.wakeFoes(g);
    harness.press(g, .x);
    harness.press(g, .b);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(P{ .x = 25, .y = 20 }, g.pool.get(2).?.at);
}

test "the reticle walks only onto cells the arrow can reach" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 20 + bow.RANGE, .y = 20 }});
    g.lv.set(.{ .x = 20 + bow.RANGE, .y = 19 }, .wall);
    game.castSight(g, .{ .x = 20, .y = 20 });
    harness.press(g, .x);
    harness.nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 20 + bow.RANGE, .y = 20 }, g.mark);
    harness.nudge(g, .n);
    try std.testing.expectEqual(P{ .x = 20 + bow.RANGE, .y = 20 }, g.mark);
    harness.nudge(g, .w);
    try std.testing.expectEqual(P{ .x = 19 + bow.RANGE, .y = 20 }, g.mark);
}

test "two arrows kill a rat at range, and the first wakes it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    const r = g.pool.get(2).?;
    try std.testing.expect(r.awake and r.hp > 0 and r.hp <= actor.row(.rat).hp - bow.BASE.lo);
    try std.testing.expectEqual(@as(i32, 26), r.at.x);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expectEqual(@as(usize, 1), g.kills);
}

test "X with nothing in sight stays in play and spends no turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 40, .y = 20 }});
    harness.wakeFoes(g);
    harness.press(g, .x);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(@as(i32, 40), g.pool.get(2).?.at.x);
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

test "a chest opens for gold once when approached, without a strike, and stays open" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    harness.arena(g, from, &.{});
    g.lv.set(at, .chest);
    const minute = g.clock.minute;
    try std.testing.expectEqual(game.Move.open, game.heroMove(g, .e));
    try std.testing.expect(!g.lv.walkable(at));
    harness.nudge(g, .e);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    try std.testing.expectEqual(from, g.heroActor().?.at);
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
    try harness.expectWithin(g.gold, items.CHEST_GOLD.lo, items.CHEST_GOLD.hi);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expect(items.CHEST_GOLD.lo > items.BARREL_GOLD.hi);
    try std.testing.expect(g.glide[game.heroSlot(g).?].bump == null);
    const gold = g.gold;
    harness.drawnOut(g);
    harness.press(g, BACK);
    harness.nudge(g, .e);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    harness.nudge(g, .w);
    harness.nudge(g, .e);
    try std.testing.expectEqual(gold, g.gold);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    std.debug.print("chest opened without attacking: {d} gold once, one turn, stays open on return\n", .{gold});
}

test "X aims at a barrel when no rat is in reach, and the arrow breaks it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    g.lv.putBarrel(at);
    harness.press(g, .x);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    try std.testing.expectEqual(at, g.mark);
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    harness.press(g, CONFIRM);
    try std.testing.expect(!g.lv.hasBarrel(at));
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try std.testing.expect(g.ground.coins[0].amount >= items.BARREL_GOLD.lo);
}

test "the camera shows past the floor only under the hud, keeps the archer clear of it, and centres a small floor" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.begin(g, 4321);
    const map_w: f32 = @floatFromInt(game.MAP_PX.x);
    const map_h: f32 = @floatFromInt(game.MAP_PX.y + hud.COVER);
    for ([_]P{ game.WINDOW, game.SCREEN_1440 }) |screen| {
        g.screen = screen;
        for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = grid.W - 1, .y = grid.H - 1 }, .{ .x = 48, .y = 32 } }) |p| {
            g.heroActor().?.at = p;
            game.snapGlide(g);
            const v = game.camWant(g);
            try std.testing.expect(v.x >= 0 and v.y >= 0);
            try std.testing.expect(v.x + @as(f32, @floatFromInt(screen.x)) <= map_w);
            try std.testing.expect(v.y + @as(f32, @floatFromInt(g.screen.y)) <= map_h);
            const foot = @as(f32, @floatFromInt((p.y + 1) * game.CELL)) - v.y;
            if (p.y == grid.H - 1) std.debug.print("{d}x{d}: bottom-row archer's foot at {d:.0}, hud top {d}\n", .{ screen.x, screen.y, foot, hud.Layout.of(screen, game.SKILLS_W).top });
            try std.testing.expect(foot <= @as(f32, @floatFromInt(hud.Layout.of(screen, game.SKILLS_W).top)));
        }
    }
    g.screen = .{ .x = game.MAP_PX.x + 200, .y = game.MAP_PX.y + hud.COVER + 100 };
    const v = game.camWant(g);
    try std.testing.expectEqual((map_w - @as(f32, @floatFromInt(g.screen.x))) * 0.5, v.x);
    try std.testing.expectEqual((map_h - @as(f32, @floatFromInt(g.screen.y))) * 0.5, v.y);
}

test "packs land on the floor as the floor is, not where its own rolls put the rooms" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const inRoom = struct {
        fn f(fl: gen.Floor, p: P) bool {
            for (fl.rooms[0..fl.room_n]) |r| {
                if (r.holds(p)) return true;
            }
            return false;
        }
    }.f;
    var lv: grid.Level = undefined;
    var foes: usize = 0;
    var foes_in: usize = 0;
    var open: usize = 0;
    var open_in: usize = 0;
    for (0..200) |i| {
        const seed: u64 = 0x1234 +% i *% 104729;
        game.begin(g, seed);
        const f = gen.build(&lv, seed);
        for (g.pool.slice()[1..]) |a| {
            foes += 1;
            if (inRoom(f, a.at)) foes_in += 1;
        }
        for (0..grid.CELLS) |c| {
            const p = grid.Level.of(c);
            if (!lv.walkable(p) or lv.hasBarrel(p) or mathx.dist(p, f.start) < pack.GAP) continue;
            open += 1;
            if (inRoom(f, p)) open_in += 1;
        }
    }
    const want = open_in * 100 / open;
    const got = foes_in * 100 / foes;
    std.debug.print("200 floors: {d}% of the open floor a foe may take is in a room, {d}% of foes are\n", .{ want, got });
    try std.testing.expect(got <= want + 5 and got + 5 >= want);
}

test "a held walk glides at one steady speed and the camera follows it without surging" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]f32{ 60, 144 }) |hz| {
        harness.arena(g, .{ .x = 20, .y = 32 }, &.{});
        g.st = .{};
        const dt = 1.0 / hz;
        const hero = game.heroSlot(g).?;
        var last = [2]f32{ g.glide[hero].now().x, g.cam.x };
        var lo = [2]f32{ std.math.floatMax(f32), std.math.floatMax(f32) };
        var hi = [2]f32{ 0, 0 };
        var on_last: i32 = 0;
        var on_dir: i32 = 0;
        var flips: usize = 0;
        var t: f32 = 0;
        while (t < 2.0) : (t += dt) {
            harness.walkFrame(g, dt, .e);
            const now = [2]f32{ g.glide[hero].now().x, g.cam.x };
            if (t > 0.8) {
                for (0..2) |k| {
                    lo[k] = @min(lo[k], now[k] - last[k]);
                    hi[k] = @max(hi[k], now[k] - last[k]);
                }
            }
            const on = scene.Cam.of(g).px(g.glide[hero].now()).x;
            if (on != on_last) {
                const dir: i32 = if (on > on_last) 1 else -1;
                if (t > input.Stepper.SETTLE + input.Stepper.DAS + game.GLIDE_S and on_dir != 0 and dir != on_dir) flips += 1;
                on_dir = dir;
            }
            on_last = on;
            last = now;
        }
        std.debug.print("held walk at {d} Hz: body {d:.3}-{d:.3} px/frame, camera {d:.3}-{d:.3} px/frame, archer's screen x reverses {d} times\n", .{ hz, lo[0], hi[0], lo[1], hi[1], flips });
        try std.testing.expect(lo[0] > 0 and hi[0] - lo[0] < 0.05);
        try std.testing.expect(lo[1] > 0 and hi[1] - lo[1] < 0.5);
        try std.testing.expectEqual(@as(usize, 0), flips);
    }
}

test "water footsteps follow the shown ground unit step once, excluding flying units" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var grounded: usize = 0;
    var flying: usize = 0;
    for (std.enums.values(actor.Kind)) |kind| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = if (kind == HERO) g.hero else harness.spawnAt(g, kind, .{ .x = 24, .y = 20 }, false);
        const slot = actor.Pool.slot(id);
        const from = g.pool.get(id).?.at;
        const to = from.add(mathx.Dir.e.delta());
        g.lv.set(from, .shallows);
        g.lv.set(to, .shallows);
        game.settle(g);
        g.st = .{};
        const initial = g.fx.head;
        const clock = g.clock;
        const rng = g.rng;
        game.update(g, 0.1);
        try std.testing.expectEqual(initial, g.fx.head);
        harness.stepTo(g, id, to);
        const span = g.glide[slot].span();
        g.glide[slot].t = -0.2;
        game.update(g, 0.19);
        try std.testing.expectEqual(initial, g.fx.head);
        game.update(g, 0.01 + span * (game.SPLASH_AT - 0.1));
        try std.testing.expectEqual(initial, g.fx.head);
        game.update(g, span * 0.2);
        const emitted = g.fx.head;
        if (actor.row(kind).movement == .ground) {
            grounded += 1;
            try std.testing.expect(emitted != initial);
            const at = game.middle(g.glide[slot].now());
            for (g.fx.motes) |m| {
                if (m.life <= 0) continue;
                try std.testing.expect(@abs(m.p[0] - at[0]) < fx.SPLASH_R + 0.03);
                try std.testing.expect(@abs(m.p[1] - at[1] - fx.SPLASH_FOOT) < fx.SPLASH_RY + 0.02);
            }
        } else {
            flying += 1;
            try std.testing.expectEqual(initial, emitted);
        }
        game.update(g, 1);
        try std.testing.expectEqual(emitted, g.fx.head);
        try std.testing.expectEqual(clock, g.clock);
        try std.testing.expectEqual(rng, g.rng);
    }
    try std.testing.expect(grounded > 0 and flying > 0);
    std.debug.print("water footsteps: {d} ground kinds splash once at the shown footfall, {d} flying kind stays dry; no idle effects or simulation changes\n", .{ grounded, flying });
}

test "a long frame that ends a step in shallows and starts the next walk still splashes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const to = P{ .x = 21, .y = 20 };
    harness.arena(g, from, &.{});
    for (0..4) |dx| g.lv.set(from.add(.{ .x = @intCast(dx), .y = 0 }), .shallows);
    game.settle(g);
    g.st = .{};
    const slot = game.heroSlot(g).?;
    const initial = g.fx.head;
    harness.stepTo(g, g.hero, to);
    const span = g.glide[slot].span();
    g.glide[slot].t = span * (game.SPLASH_AT - 0.05);
    g.busy = span * (1 - game.SPLASH_AT + 0.05);
    g.pending = .{ .walk = .e };
    game.update(g, span * (1 - game.SPLASH_AT + 0.1));
    try std.testing.expect(g.heroActor().?.at.eq(to.add(mathx.Dir.e.delta())));
    try std.testing.expect(g.fx.head != initial);
}

test "water footsteps do not appear on dry ground, hidden steps or melee bumps" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const cases = [_]struct { tile: grid.Tile, hidden: bool = false, bump: bool = false }{
        .{ .tile = .floor },
        .{ .tile = .bridge },
        .{ .tile = .ice },
        .{ .tile = .lava },
        .{ .tile = .shallows, .hidden = true },
        .{ .tile = .shallows, .bump = true },
    };
    for (cases) |case| {
        const from = P{ .x = 20, .y = 20 };
        const to = P{ .x = 21, .y = 20 };
        harness.arena(g, from, &.{});
        g.lv.set(from, .shallows);
        g.lv.set(to, case.tile);
        game.settle(g);
        g.st = .{};
        const initial = g.fx.head;
        const slot = game.heroSlot(g).?;
        if (case.bump) {
            g.glide[slot] = g.glide[slot].bumping(to, 0);
        } else {
            harness.stepTo(g, g.hero, to);
        }
        if (case.hidden) @memset(&g.lv.lit, false);
        game.update(g, g.glide[slot].span());
        try std.testing.expectEqual(initial, g.fx.head);
    }
    std.debug.print("water footsteps: {d} dry, hidden or attacking cases emit no drops\n", .{cases.len});
}

test "every step is one hop that peaks mid-glide and lands as the glide ends, and the ground under it does not bob" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 32 }, &.{.{ .x = 50, .y = 32 }});
    harness.wakeFoes(g);
    g.st = .{};
    const hero = game.heroSlot(g).?;
    const dt = harness.TEST_DT;
    var peaks = [_]i32{0} ** actor.MAX;
    var steps: usize = 0;
    var hops: usize = 0;
    var high = false;
    const ground = [2]f32{ g.glide[hero].now().y, g.cam.y };
    var bobbed = false;
    var t: f32 = 0;
    var was = g.heroActor().?.at;
    while (t < 1.5) : (t += dt) {
        harness.walkFrame(g, dt, .e);
        if (!g.heroActor().?.at.eq(was)) steps += 1;
        was = g.heroActor().?.at;
        const up = g.glide[hero].lift() * 2 > @as(i32, game.HOP_PX);
        if (up and !high) hops += 1;
        high = up;
        for (g.glide[0..g.pool.n], 0..) |gl, i| peaks[i] = @max(peaks[i], gl.lift());
        if (g.glide[hero].now().y != ground[0] or g.cam.y != ground[1]) bobbed = true;
    }
    for (0..60) |_| {
        harness.walkFrame(g, dt, null);
    }
    std.debug.print("hop: {d} steps, {d} hops, the archer peaks {d} px and the rat {d} px\n", .{ steps, hops, peaks[hero], peaks[actor.Pool.slot(2)] });
    try std.testing.expect(steps > 5);
    try std.testing.expectEqual(steps, hops);
    try std.testing.expectEqual(@as(i32, game.HOP_PX), peaks[hero]);
    try std.testing.expectEqual(@as(i32, game.HOP_PX), peaks[actor.Pool.slot(2)]);
    for (g.glide[0..g.pool.n]) |gl| try std.testing.expectEqual(@as(i32, 0), gl.lift());
    try std.testing.expect(!bobbed);
}

test "a foe stepping into the cell of a body still dying there sets off once that body is no longer drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 25, .y = 20 } });
    const cell = P{ .x = 24, .y = 20 };
    const dying = actor.Pool.slot(2);
    const mover = actor.Pool.slot(3);
    _ = g.pool.damage(&g.lv, 2, g.pool.get(2).?.hp);
    const lands: f32 = 0.3;
    combat.strike(g, dying, .{ .from = .{ .x = 20, .y = 20 }, .wait = lands }, cell, true, .{ .body = combat.snap(g, dying) });
    g.pool.move(&g.lv, 3, cell);
    harness.staggerOnly(g, 3);
    var overlap: f32 = 0;
    var t: f32 = 0;
    while (t < 1) : (t += harness.TEST_DT) {
        if (game.standing(g, dying) and g.glide[mover].done() > 0) overlap += harness.TEST_DT;
        game.update(g, harness.TEST_DT);
    }
    std.debug.print("a rat dying {d:.2} s out holds the next into its cell: {d:.3} s drawn together\n", .{ lands, overlap });
    try std.testing.expect(overlap <= harness.TEST_TOL);
    try std.testing.expect(g.glide[mover].done() >= 1);
}

test "a way held through closing inspect, a reticle or pause walks nobody until let go or turned" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const dt = harness.TEST_DT;
    const Case = struct { mode: game.Mode, close: input.Button };
    const cases = [_]Case{
        .{ .mode = .inspect, .close = skillbar.INSPECT },
        .{ .mode = .aim, .close = menu.BACK },
        .{ .mode = .pause, .close = menu.BACK },
    };
    for (cases) |case| {
        harness.arena(g, .{ .x = 20, .y = 32 }, &.{});
        g.st = .{};
        const start = g.heroActor().?.at;
        g.mark = start;
        if (case.mode == .aim) game.aiming(g, .a, .juke);
        g.mode = case.mode;
        harness.walkFor(g, 0.6, .e);
        g.st.pressed.insert(case.close);
        game.update(g, dt);
        g.st.pressed = .initEmpty();
        try std.testing.expectEqual(game.Mode.play, g.mode);
        harness.walkFor(g, 1, .e);
        try std.testing.expect(g.heroActor().?.at.eq(start));
        harness.walkFrame(g, dt, null);
        for (0..30) |_| {
            harness.walkFrame(g, dt, .e);
        }
        try std.testing.expect(!g.heroActor().?.at.eq(start));
    }
    std.debug.print("held walk: {d} screens closed with the way held, none walked till it was let go\n", .{cases.len});
}

test "a way held from play into pause or inspect moves nothing there until let go or turned" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const dt = harness.TEST_DT;
    const Case = struct { open: input.Button, way: mathx.Dir };
    for ([_]Case{ .{ .open = PAUSE, .way = .s }, .{ .open = skillbar.INSPECT, .way = .e } }) |case| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        g.st = .{};
        for (0..10) |_| harness.walkFrame(g, dt, case.way);
        harness.pressWalking(g, case.open, case.way);
        try std.testing.expect(g.mode != .play);
        const menu_at = g.pause_menu.at;
        const spot = g.inspecting;
        harness.walkFor(g, 1, case.way);
        try std.testing.expectEqual(menu_at, g.pause_menu.at);
        try std.testing.expectEqual(spot, g.inspecting);
        harness.walkFrame(g, dt, null);
        for (0..30) |_| harness.walkFrame(g, dt, case.way);
        try std.testing.expect(g.pause_menu.at != menu_at or !std.meta.eql(spot, g.inspecting));
        g.mode = .play;
    }
}

test "a way held into or out of Character moves nothing until let go" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    for (0..10) |_| harness.walkFrame(g, harness.TEST_DT, .s);
    harness.pressWalking(g, menu.CHARACTER, .s);
    const cursor = g.character.cursor;
    harness.walkFor(g, 1, .s);
    try std.testing.expectEqual(cursor, g.character.cursor);
    harness.pressWalking(g, menu.BACK, .s);
    const at = g.heroActor().?.at;
    harness.walkFor(g, 1, .s);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    std.debug.print("held walk: direct Character entry and exit suppress carried movement\n", .{});
}

test "a way held into or out of the skill picker moves neither cursor until let go" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.st = .{};
    character.openCharacter(g);
    character.characterCommand(g, .{ .bindings = .shoot });
    g.binds.assigning = null;
    for (0..10) |_| harness.walkFrame(g, harness.TEST_DT, .e);
    harness.pressWalking(g, CHANGE, .e);
    const picked = g.binds.menu.pick;
    const slot = g.binds.slot();
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(picked, g.binds.menu.pick);
    harness.pressWalking(g, menu.BACK, .e);
    try std.testing.expect(g.binds.menu == .browse);
    harness.walkFor(g, 1, .e);
    try std.testing.expectEqual(slot, g.binds.slot());
    std.debug.print("held walk: the skill picker and the slot it returns to stayed put with the way held\n", .{});
}

test "a step taken mid-hop hops on from the height the body was at" {
    var gl = game.Glide.still(.{ .x = 5, .y = 5 }, .hop);
    gl = gl.toward(.{ .x = 6, .y = 5 }, 0);
    var worst: f32 = 0;
    var t: f32 = 0;
    const dt = harness.TEST_DT;
    while (t < game.GLIDE_S * 3) : (t += dt) {
        const before = gl.height();
        gl.t += dt;
        if (@abs(t - game.GLIDE_S * 0.4) < dt * 0.5) gl = gl.toward(.{ .x = 7, .y = 5 }, 0);
        worst = @max(worst, @abs(gl.height() - before));
    }
    std.debug.print("hop cut short by a step: the biggest jump in height between {d} Hz frames {d:.2} px\n", .{ 1 / dt, worst });
    try std.testing.expect(worst < game.HOP_PX * 0.2);
    try std.testing.expectEqual(@as(i32, 0), gl.lift());
}

test "a slime slides without hopping, a little past its cell, and settles exactly on it" {
    var gl = game.Glide.still(.{ .x = 5, .y = 5 }, look.gait(.slime));
    gl = gl.toward(.{ .x = 6, .y = 5 }, 0);
    const to = game.cellPx(.{ .x = 6, .y = 5 }).x;
    var past: f32 = 0;
    var peak_at: f32 = 0;
    var t: f32 = 0;
    while (t < gl.span() * 1.5) : (t += harness.TEST_DT) {
        gl.t = t;
        try std.testing.expectEqual(@as(i32, 0), gl.lift());
        if (gl.now().x - to > past) {
            past = gl.now().x - to;
            peak_at = gl.done();
        }
    }
    std.debug.print("slime slide: {d:.1} px past its cell at {d:.0}% of the glide\n", .{ past, peak_at * 100 });
    try std.testing.expectApproxEqAbs(game.CELL_F * 0.05, past, 0.3);
    try std.testing.expectEqual(to, gl.now().x);
}

test "foes act nearest first, so the one behind in a corridor follows the one ahead" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 20 }, .{ .x = 24, .y = 20 } });
    shots.wallRow(&g.lv, 19, 21, 29);
    shots.wallRow(&g.lv, 21, 21, 29);
    harness.wakeFoes(g);
    combat.endTurn(g);
    std.debug.print("corridor: nearer rat to {d}, the one behind to {d}\n", .{ g.pool.get(3).?.at.x, g.pool.get(2).?.at.x });
    try std.testing.expectEqualSlices(u16, &.{ 3, 2 }, g.order[0..g.order_n]);
    try std.testing.expectEqual(@as(i32, 23), g.pool.get(3).?.at.x);
    try std.testing.expectEqual(@as(i32, 24), g.pool.get(2).?.at.x);
}

test "a turn's glides start the archer first, then each foe in sight a stagger behind, and the next walk waits for the last" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 27, .y = 20 }, .{ .x = 24, .y = 23 } });
    _ = g.pool.spawn(&g.lv, actor.Actor.of(.slime, .{ .x = 26, .y = 17 }));
    harness.wakeFoes(g);
    game.settle(g);
    harness.nudge(g, .e);
    const t = [_]f32{ g.glide[game.heroSlot(g).?].t, g.glide[actor.Pool.slot(3)].t, g.glide[actor.Pool.slot(4)].t, g.glide[actor.Pool.slot(2)].t };
    std.debug.print("glide starts: archer {d:.3} s, then {d:.3}, {d:.3}, {d:.3}; the turn is busy {d:.3} s\n", .{ -t[0], -t[1], -t[2], -t[3], g.busy });
    try std.testing.expectEqualSlices(u16, &.{ 3, 4, 2 }, g.order[0..g.order_n]);
    for (t, 0..) |v, i| try std.testing.expectApproxEqAbs(-game.STAGGER_S * @as(f32, @floatFromInt(i)), v, 1e-6);
    try std.testing.expectApproxEqAbs(game.STAGGER_S * 2 + game.SLIDE_S, g.busy, 1e-6);
    const at = g.heroActor().?.at;
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    g.st = .{};
    var waited: f32 = 0;
    while (g.heroActor().?.at.eq(at) and waited < 1) : (waited += harness.TEST_DT) game.update(g, harness.TEST_DT);
    std.debug.print("a walk pressed mid-turn steps {d:.3} s later\n", .{waited});
    try std.testing.expect(!g.heroActor().?.at.eq(at));
    try std.testing.expectApproxEqAbs(game.STAGGER_S * 2 + game.SLIDE_S, waited, harness.TEST_TOL);
}

test "an arrow's rat flashes when the arrow gets there, not when the hit resolves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.fx.flashOf(rat));
    const t = harness.framesUntil(g, rat, harness.flashing);
    std.debug.print("arrow 5 cells out: the rat flashes {d:.3} s after the shot, the arrow reaches it at {d:.3} s\n", .{ t, game.flown(4) });
    try std.testing.expectApproxEqAbs(game.flown(4), t, harness.TEST_TOL);
}

test "after an arrow the foes act a stagger after it lands, so the rat it strikes is still under it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    harness.wakeFoes(g);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    const lands = game.flown(6);
    const starts = -g.glide[actor.Pool.slot(2)].t;
    std.debug.print("an arrow 7 cells out lands {d:.3} s in, and the rat it struck steps at {d:.3} s\n", .{ lands, starts });
    try std.testing.expect(g.pool.get(2).?.hurt());
    try std.testing.expectEqual(@as(i32, 26), g.pool.get(2).?.at.x);
    try std.testing.expectApproxEqAbs(lands + game.STAGGER_S, starts, 1e-6);
}

test "a body the arrow kills stands until the arrow reaches it and its flash is gone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 20 + bow.RANGE, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    const rat = actor.Pool.slot(2);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expect(game.drawnAt(g, rat) != null);
    const t = harness.framesUntil(g, rat, harness.gone);
    const lands = game.flown(bow.RANGE - 1);
    std.debug.print("a rat an arrow kills {d} cells out is drawn {d:.3} s on; the arrow lands at {d:.3} s\n", .{ bow.RANGE, t, lands });
    try std.testing.expectApproxEqAbs(lands + fx.FLASH_S, t, harness.TEST_TOL);
}

test "a long frame finishes a killing flash before the next turn is ready" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    g.st = .{};
    game.update(g, g.busy + 0.01);
    try std.testing.expect(game.quiet(g));
    try std.testing.expect(game.drawnAt(g, actor.Pool.slot(2)) == null);
    std.debug.print("long frame: killing flash finished when play becomes ready\n", .{});
}

test "the bite that kills the archer leaves it standing and followed until it lands, and the veil waits for the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    bittenToDeath(g);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    const hero = game.heroSlot(g).?;
    try std.testing.expect(game.drawnAt(g, hero) != null and game.carrierAt(g) != null);
    const t = harness.framesUntil(g, hero, harness.gone);
    std.debug.print("a killing bite a stagger in: the archer stands {d:.3} s, the turn is over at {d:.3} s\n", .{ t, t + g.busy });
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS + fx.FLASH_S, t, harness.TEST_TOL);
    try std.testing.expect(game.carrierAt(g) == null and g.busy <= 0);
}

test "a foe whose bite kills the archer is not then killed by the gas it stands in" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    g.pool.get(2).?.hp = 1;
    g.heroActor().?.hp = 1;
    g.lv.addGas(.{ .x = 21, .y = 20 }, harness.TEST_GAS);
    harness.use(g, .wait);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    try std.testing.expect(g.pool.get(2) != null);
    try std.testing.expectEqual(@as(usize, 0), g.kills);
    try std.testing.expectEqualStrings("Archer dies.", g.log.line(0).?);
}

test "a bite lands on the archer at the height of the biter's bump, from its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    harness.wakeFoes(g);
    harness.nudge(g, .e);
    const hero = game.heroSlot(g).?;
    try std.testing.expect(g.heroActor().?.hurt());
    const t = harness.framesUntil(g, hero, harness.flashing);
    std.debug.print("the biting rat is first in the turn: it sets off {d:.3} s in, the archer flashes {d:.3} s in\n", .{ game.STAGGER_S, t });
    try std.testing.expectEqualSlices(u16, &.{ 3, 2 }, g.order[0..g.order_n]);
    const bump = g.glide[actor.Pool.slot(3)].bump orelse return error.NoBump;
    try std.testing.expect(bump.x < 0 and bump.y == 0);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t, harness.TEST_TOL);
}

test "a kick bumps the rat and lands at the bump's height, and the rat bites back a stagger after" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    const cam = g.cam;
    g.rng = harness.meleeThenBites(g, 1);
    harness.nudge(g, .e);
    const hero = game.heroSlot(g).?;
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.hurt() and g.heroActor().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.fx.flashOf(rat));
    g.st = .{};
    var bumped: f32 = 0;
    var bumped_at: f32 = 0;
    var rat_hit: ?f32 = null;
    var t: f32 = 0;
    while (t < game.BUMP_S) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        const off = g.glide[hero].now().x - game.cellPx(at).x;
        if (off > bumped) {
            bumped = off;
            bumped_at = t + harness.TEST_DT;
        }
        if (rat_hit == null and harness.flashing(g, rat)) rat_hit = t + harness.TEST_DT;
        try std.testing.expectEqual(game.cellPx(at), g.glide[hero].ground());
    }
    try std.testing.expect(harness.samePx(g.glide[hero].now(), game.cellPx(at)));
    const bitten = t + harness.framesUntil(g, hero, harness.flashing);
    std.debug.print("a kick: the archer bumps {d:.1} px toward the rat at {d:.3} s, the rat flashes at {d:.3} s and bites back at {d:.3} s, the camera {d:.1} px off\n", .{ bumped, bumped_at, rat_hit.?, bitten, @abs(g.cam.x - cam.x) });
    try std.testing.expectApproxEqAbs(game.BUMP_PX, bumped, 0.5);
    try std.testing.expectApproxEqAbs(game.BUMP_LANDS, bumped_at, harness.TEST_TOL);
    try std.testing.expectApproxEqAbs(game.BUMP_LANDS, rat_hit.?, harness.TEST_TOL);
    try std.testing.expectApproxEqAbs(game.BUMP_LANDS + game.STAGGER_S + game.BUMP_LANDS, bitten, harness.TEST_TOL);
    try std.testing.expectEqual(cam, g.cam);
}

test "the lean shows a kick on the rat a kick killed until it falls" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{.{ .x = 21, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    harness.nudge(g, .e);
    try std.testing.expect(g.pool.get(2) == null);
    try std.testing.expectEqual(game.Move.kick, scene.leanShown(g, &scene.stoodNow(g), at, .e));
    harness.drawnOut(g);
    try std.testing.expectEqual(game.Move.step, scene.leanShown(g, &scene.stoodNow(g), at, .e));
}

test "a kick dealt in a frame of play is no further into its bump than its blow is to landing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.calm(g);
    g.st = .{ .walk = .e };
    game.update(g, mathx.FRAME_DT);
    const t = g.glide[game.heroSlot(g).?].t;
    std.debug.print("a kick dealt in a 60 fps frame: {d:.4} s into its bump as the frame ends\n", .{t});
    try std.testing.expectEqual(@as(f32, 0), t);
}

test "only the bite that kills the archer lands as a killing blow" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var deaths: usize = 0;
    var hurts: usize = 0;
    for (0..40) |i| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 }, .{ .x = 20, .y = 21 } });
        g.rng = mathx.Rng.init(i);
        harness.wakeFoes(g);
        g.heroActor().?.hp = actor.row(.rat).blow.strike.hit.hi + 1;
        combat.endTurn(g);
        var kills: usize = 0;
        for (g.owed) |o| {
            if ((o.bit orelse continue) == .kill) kills += 1;
        }
        try std.testing.expectEqual(@as(usize, if (g.mode == .dead) 1 else 0), kills);
        if (g.mode != .dead) continue;
        deaths += 1;
        for (g.owed) |o| {
            if ((o.bit orelse continue) == .hurt) hurts += 1;
        }
    }
    std.debug.print("three rats on a {d} hp archer: {d} of 40 turns kill, with {d} bites before the killing ones that only hurt\n", .{ actor.row(.rat).blow.strike.hit.hi + 1, deaths, hurts });
    try std.testing.expect(deaths > 0 and hurts >= deaths);
}

test "a body at rest lands on its tile's pixel whatever fraction the camera is at" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const p = P{ .x = 17, .y = 9 };
    var f: f32 = -3;
    while (f < 3) : (f += 0.125) {
        g.cam = .{ .x = 500 + f, .y = 300 - f };
        const c = scene.Cam.of(g);
        try std.testing.expectEqual(c.corner(p), c.px(game.cellPx(p)));
    }
}

test "hidden and offscreen objects keep casting without being drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const p = P{ .x = 27, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{p});
    const i = actor.Pool.slot(2);
    const view = grid.Box{ .lo = .{ .x = 15, .y = 15 }, .hi = .{ .x = 27, .y = 25 } };
    const cast = view.grown(game.CAST_MARGIN);
    g.lv.lit[grid.Level.idx(p)] = false;
    g.lv.seen[grid.Level.idx(p)] = false;
    try std.testing.expect(game.drawnAt(g, i) == null);
    try std.testing.expect(game.casterAt(g, i, view) == null);
    try std.testing.expectEqual(g.glide[i].now(), game.casterAt(g, i, cast).?);
    g.split_from[i] = game.heroSlot(g).?;
    try std.testing.expect(game.casterAt(g, i, cast) == null);
    g.split_from[i] = null;
    g.pool.items[i].alive = false;
    try std.testing.expect(game.casterAt(g, i, cast) == null);
    g.lv.putBarrel(p);
    try std.testing.expect(!scene.barrelShownAt(g, p));
    try std.testing.expect(scene.barrelPresent(g, p));
    std.debug.print("hidden actor and barrel still cast within {d} cells of the view; dead actors and unborn splits do not\n", .{game.CAST_MARGIN});
}

test "the minimap and the day beneath it fit in the top right, clear of the hud" {
    for ([_]P{ game.SCREEN_720, game.WINDOW, game.SCREEN_1080, game.SCREEN_1440 }) |screen| {
        const o = scene.miniOrigin(screen.x);
        try std.testing.expect(o.x > @divTrunc(screen.x, 2));
        try std.testing.expect(scene.dayLine(screen.x).y + @as(i32, @intFromFloat(@ceil(scene.DAY_GLYPH_R))) + scene.DAY_DROP < hud.Layout.of(screen, game.SKILLS_W).top);
    }
}

/// Seconds of frames till a split-off half in `slot` is drawn, and till what is owed it lands.
fn showsAndLands(g: *game.Game, slot: usize) struct { shows: f32, lands: f32 } {
    var shows: ?f32 = null;
    var lands: ?f32 = null;
    var t: f32 = 0;
    while ((shows == null or lands == null) and t < 1) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (shows == null and harness.drawn(g, slot)) shows = t;
        if (lands == null and !g.fx.pending(slot)) lands = t;
    }
    return .{ .shows = shows.?, .lands = lands.? };
}

fn corridor(b: *atlas.Bespoke) void {
    var x: i32 = 2;
    while (x <= 12) : (x += 1) b.tile[grid.Level.idx(.{ .x = x, .y = 5 })] = .floor;
}

/// Two corridors joined by a door at each one's end, starting a step from the first's; the second's node.
fn twoRooms(w: *atlas.Atlas) usize {
    w.* = .{};
    const a = w.add(.{ .bespoke = .{} }).?;
    const b = w.add(.{ .bespoke = .{} }).?;
    for ([_]usize{ a, b }) |n| corridor(&w.node[n].plan.bespoke);
    const da = w.addDoor(a, .{ .x = 2, .y = 5 }).?;
    const db = w.addDoor(b, .{ .x = 11, .y = 5 }).?;
    w.link(.{ .node = a, .door = da }, .{ .node = b, .door = db });
    w.start = .{ .node = a, .at = .{ .x = 3, .y = 5 } };
    return b;
}

fn splittable(g: *game.Game, at: P, awake: bool) u16 {
    const id = harness.spawnAt(g, .slime, at, awake);
    g.pool.get(id).?.hp = harness.SLIME_HALF + 1;
    return id;
}

fn bittenToDeath(g: *game.Game) void {
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    harness.wakeFoes(g);
    g.heroActor().?.hp = 1;
    harness.nudge(g, .e);
}

test "a bloat beside the archer bursts on it about two turns in three, and never bites" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    var bursts: usize = 0;
    for (0..harness.TRIES) |i| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = harness.spawnAt(g, .bloat, at, true);
        g.rng = mathx.Rng.init(i);
        combat.endTurn(g);
        try std.testing.expect(!g.heroActor().?.hurt());
        if (g.pool.get(id) != null) continue;
        bursts += 1;
        try std.testing.expectEqual(gas.BURST, g.lv.gasAt(at));
    }
    std.debug.print("an awake bloat beside the archer bursts on {d} of {d} turns\n", .{ bursts, harness.TRIES });
    try std.testing.expect(harness.aboutRate(bursts, 1 - actor.FLIT + actor.FLIT / mathx.ALL_DIRS.len));
}

test "a bloat with no way to the archer still flits a third of its turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const hero = P{ .x = 20, .y = 20 };
    const at = P{ .x = 30, .y = 20 };
    var moved: usize = 0;
    for (0..harness.TRIES) |i| {
        harness.arena(g, hero, &.{});
        for (mathx.ALL_DIRS) |d| g.lv.set(hero.add(d.delta()), .wall);
        const id = harness.spawnAt(g, .bloat, at, true);
        g.rng = mathx.Rng.init(i);
        combat.endTurn(g);
        if (!g.pool.get(id).?.at.eq(at)) moved += 1;
    }
    std.debug.print("a bloat walled off from the archer flits on {d} of {d} turns\n", .{ moved, harness.TRIES });
    try std.testing.expect(harness.aboutRate(moved, actor.FLIT));
}

test "an arrow bursts a bloat where it floats, and its gas reaches the archer and eats at it every turn after" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .bloat, .{ .x = 24, .y = 20 }, false);
    g.pool.get(id).?.hp = 1;
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(id));
    try std.testing.expectEqual(@as(usize, 1), g.kills);
    const per = gas.harm(actor.row(HERO).hp);
    var first: ?usize = null;
    for (1..11) |turn| {
        const before = g.heroActor().?.hp;
        harness.use(g, .wait);
        const lost = before - g.heroActor().?.hp;
        if (first == null and lost > 0) first = turn;
        try std.testing.expectEqual(if (first == null) 0 else per, lost);
        if (lost > 0) try std.testing.expect(g.fx.flashOf(game.heroSlot(g).?) > 0);
    }
    std.debug.print("a bloat shot 4 cells off: its gas first eats at the archer {?d} turns after, {d} hp a turn\n", .{ first, per });
    try std.testing.expectEqual(@as(?usize, 3), first);
}

test "a bloat caught in another's gas bursts too" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const near = harness.spawnAt(g, .bloat, .{ .x = 27, .y = 20 }, false);
    const far = harness.spawnAt(g, .bloat, .{ .x = 28, .y = 21 }, false);
    g.pool.get(near).?.hp = 1;
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(near));
    var waited: usize = 0;
    while (g.pool.get(far) != null and waited < 20) : (waited += 1) harness.use(g, .wait);
    std.debug.print("a bloat beside one shot dead bursts {d} turns later\n", .{waited});
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(far));
    try std.testing.expectEqual(@as(usize, 2), g.kills);
}

test "a foe the gas kills out of sight leaves nothing drawn and nothing said" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 40, .y = 20 }});
    g.lv.addGas(.{ .x = 40, .y = 20 }, harness.TEST_GAS);
    g.pool.get(2).?.hp = 1;
    const said = g.log.n;
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expectEqual(@as(usize, 1), g.kills);
    try std.testing.expectEqual(@as(usize, 0), g.fx.due_n);
    for (g.fx.motes) |m| try std.testing.expect(m.life <= 0);
    try std.testing.expectEqualStrings("The last rat is dead.", g.log.line(0).?);
    try std.testing.expect(std.mem.endsWith(u8, g.log.line(1).?, "experience."));
    try std.testing.expectEqual(said + 2, g.log.n);
}

test "a foe the gas kills after it steps keeps its place in the turn, and its death lands as it arrives" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    const was = g.pool.get(2).?.at;
    harness.wakeFoes(g);
    g.pool.get(2).?.hp = 1;
    g.lv.addGas(was, harness.TEST_GAS);
    harness.nudge(g, .w);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(2));
    try std.testing.expect(!g.pool.items[actor.Pool.slot(2)].at.eq(was));
    const t = harness.framesUntil(g, actor.Pool.slot(2), harness.flashing);
    std.debug.print("a rat that steps and dies in the gas: its death lands {d:.3} s into the turn, its hop ends at {d:.3} s\n", .{ t, game.STAGGER_S + game.GLIDE_S });
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.GLIDE_S, t, harness.TEST_TOL);
}

test "an arrow that bursts a bloat eats at a sleeping foe with its gas as it lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const bloat = harness.spawnAt(g, .bloat, .{ .x = 27, .y = 20 }, false);
    const rat = harness.spawnAt(g, .rat, .{ .x = 28, .y = 21 }, false);
    g.pool.get(bloat).?.hp = 1;
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(bloat));
    try std.testing.expect(g.pool.get(rat).?.hurt());
    const lands = game.flown(6);
    const t = harness.framesUntil(g, actor.Pool.slot(rat), harness.flashing);
    std.debug.print("a bloat shot 7 cells out: the arrow lands {d:.3} s in, and its gas stings the rat beside it {d:.3} s in\n", .{ lands, t });
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
}

test "a bloat's cloud is drawn from when its burst lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const Burst = struct {
        const at = P{ .x = 27, .y = 20 };
        fn clouded(gm: *game.Game, _: usize) bool {
            return gm.cloud.tint[grid.Level.idx(at)] > 0;
        }
    };
    const bloat = harness.spawnAt(g, .bloat, Burst.at, false);
    g.pool.get(bloat).?.hp = 1;
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expect(g.lv.gasAt(Burst.at) > 0 and !Burst.clouded(g, 0));
    const t = harness.framesUntil(g, 0, Burst.clouded);
    std.debug.print("a bloat shot 7 cells out: the arrow lands {d:.3} s in, its cloud first drawn {d:.3} s in\n", .{ game.flown(6), t });
    try std.testing.expectApproxEqAbs(game.flown(6), t, harness.TEST_TOL);
}

test "a foe stepping out of sight takes its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = actor.Pool.slot(2);
    const dark = ledge(g);
    game.castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.lv.isLit(dark));
    g.pool.move(&g.lv, 2, dark);
    harness.staggerOnly(g, 2);
    std.debug.print("a rat stepping out of sight a stagger after a kick sets off {d:.3} s in\n", .{-g.glide[rat].t});
    try std.testing.expectApproxEqAbs(game.STAGGER_S, -g.glide[rat].t, 1e-6);
}

test "a barrel the arrow breaks stands until the arrow reaches it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const Gone = struct {
        const at = P{ .x = 20 + bow.RANGE, .y = 20 };
        fn f(gm: *game.Game, _: usize) bool {
            return !scene.barrelShownAt(gm, at);
        }
    };
    g.lv.putBarrel(Gone.at);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expect(!g.lv.hasBarrel(Gone.at) and !Gone.f(g, 0));
    try std.testing.expect(game.mapAssets(g).barrel);
    const t = harness.framesUntil(g, 0, Gone.f);
    try std.testing.expect(!game.mapAssets(g).barrel);
    const lands = game.flown(bow.RANGE - 1);
    std.debug.print("a barrel shot {d} cells out breaks {d:.3} s on; the arrow lands at {d:.3} s\n", .{ bow.RANGE, t, lands });
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
}

test "a foe's hp as drawn, the archer's and the low glow drop as the blow lands, not as it resolves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    const rat = actor.Pool.slot(2);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expect(g.pool.get(2).?.hurt());
    try std.testing.expectEqual(actor.row(.rat).hp, g.pictured[rat].hp);
    const Drop = struct {
        fn f(gm: *game.Game, i: usize) bool {
            return gm.pictured[i].hp < actor.row(.rat).hp;
        }
    };
    const t = harness.framesUntil(g, rat, Drop.f);
    std.debug.print("an arrow 7 cells out: the rat's bar drops {d:.3} s in, as it lands at {d:.3} s\n", .{ t, game.flown(6) });
    try std.testing.expectApproxEqAbs(game.flown(6), t, harness.TEST_TOL);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    harness.wakeFoes(g);
    const low: i32 = @intFromFloat(vignette.LOW * @as(f32, @floatFromInt(actor.row(HERO).hp)));
    g.heroActor().?.hp = low;
    game.catchUp(g);
    g.rng = harness.bitesRng(g, .rat, &.{true});
    harness.nudge(g, .e);
    const hero = game.heroSlot(g).?;
    try std.testing.expect(g.heroActor().?.hp < low);
    try std.testing.expectEqual(low, g.pictured[hero].hp);
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const r = harness.framesUntil(g, hero, harness.reddened);
    std.debug.print("a bite on an archer at a third of its hp: the view reddens {d:.3} s in, as it lands at {d:.3} s\n", .{ r, game.STAGGER_S + game.BUMP_LANDS });
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, r, harness.TEST_TOL);
}

test "an arrow that splits a slime shows it as the arrow lands, the new half sliding out of it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 27, .y = 20 };
    const id = splittable(g, at, false);
    game.catchUp(g);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    const slime = actor.Pool.slot(id);
    const other = slime + 1;
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.get(id).?.kind);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.items[other].kind);
    try std.testing.expectEqual(actor.Kind.slime, g.pictured[slime].kind);
    try std.testing.expect(game.mapAssets(g).bodies.contains(.slime));
    try std.testing.expect(game.drawnAt(g, other) == null);
    try std.testing.expectEqual(fx.Body.of(g.pool.items[other], g.pictured[other].seq), g.pictured[other]);
    try std.testing.expectEqualStrings("The slime splits in two!", g.log.line(0).?);
    const t = harness.framesUntil(g, other, harness.drawn);
    const lands = game.flown(6);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pictured[slime].kind);
    try std.testing.expect(!game.mapAssets(g).bodies.contains(.slime));
    try std.testing.expect(game.mapAssets(g).bodies.contains(.slime_quarter));
    try std.testing.expect(harness.samePx(g.glide[other].now(), game.cellPx(at)));
    try std.testing.expect(g.busy >= game.SLIDE_S);
    const slid = harness.framesUntil(g, other, struct {
        fn f(gm: *game.Game, i: usize) bool {
            return gm.glide[i].done() >= 1;
        }
    }.f);
    std.debug.print("an arrow 7 cells out splits a slime: the new half shows {d:.3} s in, as it lands at {d:.3} s, and slides out over {d:.3} s\n", .{ t, lands, slid });
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
    try std.testing.expectApproxEqAbs(game.SLIDE_S, slid, harness.TEST_TOL);
    try std.testing.expect(harness.samePx(g.glide[other].now(), game.cellPx(g.pool.items[other].at)));
    try std.testing.expectEqual(actor.Tally{ .left = 2, .total = 2 }, g.pool.tally(.slime));
}

test "a slime split this turn acts from the next, and one a blow kills outright splits nothing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .slime, .{ .x = 21, .y = 20 }, true);
    g.pool.get(id).?.hp = harness.SLIME_HALF;
    harness.nudge(g, .e);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.get(id).?.kind);
    try std.testing.expectEqualSlices(u16, &.{id}, g.order[0..g.order_n]);
    const other = id + 1;
    try std.testing.expect(!g.pool.get(other).?.waits);
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(usize, 2), g.order_n);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const one = harness.spawnAt(g, .slime, .{ .x = 25, .y = 20 }, false);
    g.pool.get(one).?.hp = bow.BASE.lo;
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.pool.get(one));
    try std.testing.expectEqual(actor.Tally{ .left = 0, .total = 1 }, g.pool.tally(.slime));
    try std.testing.expectEqualStrings("The last slime is dead.", g.log.line(0).?);
}

/// Long enough that most of a turn's blows land before the next, so splits show.
const SOAK_DT: f32 = 0.1;

test "slimes split in fights on real floors, and every body keeps a cell of its own" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var splits: usize = 0;
    var most: usize = 0;
    var quarters: usize = 0;
    const FLOORS: usize = 20;
    for (0..FLOORS) |f| {
        game.begin(g, 0x511E +% f *% grid.TEST_SEED_STRIDE);
        harness.wakeFoes(g);
        harness.setLife(g.heroActor().?, 1000, 1000);
        var rng = mathx.Rng.init(f);
        for (0..300) |_| {
            if (g.mode == .dead) break;
            const n = g.pool.n;
            harness.press(g, .x);
            if (g.mode == .aim) harness.press(g, CONFIRM) else harness.nudge(g, rng.pick(mathx.Dir, mathx.ALL_DIRS));
            game.update(g, SOAK_DT);
            for (0..g.pool.n) |i| {
                if (game.drawnAt(g, i) == null) continue;
                const pic = g.pictured[i];
                try std.testing.expect(pic.max > 0 and pic.hp <= pic.max and pic.kind.family() == g.pool.items[i].kind.family());
            }
            splits += g.pool.n - n;
            most = @max(most, g.pool.n);
            var standing_n: usize = 0;
            for (g.pool.slice(), 0..) |a, i| {
                if (!a.alive) continue;
                standing_n += 1;
                try std.testing.expectEqual(actor.Pool.idOf(i), g.lv.who(a.at));
                try std.testing.expect(a.hp > 0 and a.hp <= a.max);
            }
            var taken: usize = 0;
            for (&g.lv.occupant) |*o| {
                if (o.* != grid.NO_ONE) taken += 1;
            }
            try std.testing.expectEqual(standing_n, taken);
        }
        for (g.pool.slice()) |a| {
            if (a.kind == .slime_quarter) quarters += 1;
        }
    }
    std.debug.print("{d} floors of 300 turns with every foe awake: {d} splits, {d} quarter slimes made, at most {d} bodies of {d}\n", .{ FLOORS, splits, quarters, most, actor.MAX });
    try std.testing.expect(splits > FLOORS and quarters > 0);
    try std.testing.expect(most <= actor.MAX);
}

test "each bite on the archer drops its hp as drawn as that bite lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 } });
    harness.wakeFoes(g);
    harness.use(g, .wait);
    const hero = game.heroSlot(g).?;
    const full = actor.row(HERO).hp;
    const hp = g.heroActor().?.hp;
    try std.testing.expectEqual(full, g.pictured[hero].hp);
    const One = struct {
        fn f(gm: *game.Game, i: usize) bool {
            return gm.pictured[i].hp < actor.row(HERO).hp;
        }
    };
    const t1 = harness.framesUntil(g, hero, One.f);
    const first = g.pictured[hero].hp;
    try std.testing.expect(first > hp);
    const t2 = t1 + harness.framesUntil(g, hero, caughtUp);
    std.debug.print("two rats bite an archer of {d} hp: drawn on {d} as the first lands {d:.3} s in, on {d} as the second lands {d:.3} s in\n", .{ full, first, t1, hp, t2 });
    try std.testing.expectApproxEqAbs(game.BUMP_LANDS, t1, harness.TEST_TOL);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t2, harness.TEST_TOL);
}

test "a slime an arrow splits shows split as the arrow lands, though the gas eats at it later in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = splittable(g, at, true);
    for ([_]P{ at, .{ .x = 24, .y = 20 } }) |p| g.lv.addGas(p, harness.TEST_GAS);
    game.catchUp(g);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    const slime = actor.Pool.slot(id);
    const other = slime + 1;
    try std.testing.expect(!g.pool.items[slime].at.eq(at));
    const t = harness.framesUntil(g, other, harness.drawn);
    const lands = game.flown(4);
    std.debug.print("an arrow 5 cells out splits a slime in gas: the new half shows {d:.3} s in, as the arrow lands at {d:.3} s, the gas still to land on the slime\n", .{ t, lands });
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
    try std.testing.expect(g.fx.pending(slime));
    try std.testing.expectEqual(actor.Kind.slime_half, g.pictured[slime].kind);
}

test "a half the gas splits off a burning slime on the foes' turn burns no sooner than it shows" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = splittable(g, at, true);
    const a = g.pool.get(id).?;
    a.burn = .{ .turns = 2 };
    for ([_]P{ at, .{ .x = 24, .y = 20 } }) |p| g.lv.addGas(p, harness.TEST_GAS);
    game.catchUp(g);
    harness.use(g, .wait);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(g.split_from[half] != null and g.fx.pending(half));
    const when = showsAndLands(g, half);
    std.debug.print("a half the gas splits off a burning slime on the foes' turn: shows {d:.3} s in, its burn lands {d:.3} s in\n", .{ when.shows, when.lands });
    try std.testing.expect(when.lands >= when.shows);
}

test "a half an arrow splits off into gas takes the gas on its waiting turn, no sooner than it shows" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = splittable(g, at, true);
    var cells = grid.Cells.around(at, 2);
    while (cells.next()) |p| g.lv.addGas(p, harness.TEST_GAS);
    game.catchUp(g);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(g.split_from[half] != null);
    const when = showsAndLands(g, half);
    const b = g.pool.items[half];
    std.debug.print("a half split off into gas: shows {d:.3} s in, stung {d:.3} s in, {s} on {d} of {d} hp\n", .{ when.shows, when.lands, actor.row(b.kind).name, b.hp, b.max });
    try std.testing.expect(b.kind != .slime_half or b.hp < b.max);
    try std.testing.expect(when.lands >= when.shows);
}

test "a barrel broken in sight but in the dark stays remembered until light shows it gone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const p = P{ .x = 28, .y = 20 };
    g.lv.putBarrel(p);
    game.settle(g);
    try std.testing.expect(scene.barrelShownAt(g, p));
    g.clock = day.Clock.at(day.DEAD_OF_NIGHT);
    try std.testing.expect(g.lv.breakBarrel(p));
    game.castSight(g, g.heroActor().?.at);
    try std.testing.expect(g.lv.inLos(p) and !g.lv.isLit(p));
    try std.testing.expect(scene.barrelShownAt(g, p));
    g.clock = day.Clock.at(day.NOON);
    game.castSight(g, g.heroActor().?.at);
    try std.testing.expect(!scene.barrelShownAt(g, p));
}

test "a barrel broken out of sight stays remembered, with no blow drawn, until it is seen gone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const p = P{ .x = 23, .y = 20 };
    g.lv.putBarrel(p);
    game.settle(g);
    try std.testing.expect(scene.barrelShownAt(g, p));
    try std.testing.expect(g.lv.breakBarrel(p));
    g.lv.lit[grid.Level.idx(p)] = false;
    combat.strike(g, null, .{ .from = .{ .x = 24, .y = 20 }, .wait = 0.2 }, p, true, null);
    try std.testing.expect(!g.fx.breaking(p));
    try std.testing.expect(scene.barrelShownAt(g, p));
    game.castSight(g, g.heroActor().?.at);
    try std.testing.expect(!scene.barrelShownAt(g, p));
}

test "a half a beefy pib's sweep splits off into gas takes the gas no sooner than it shows" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.unkillable = true;
    const at = P{ .x = 20, .y = 21 };
    const id = splittable(g, at, false);
    _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    for ([_]P{ .{ .x = 19, .y = 20 }, .{ .x = 19, .y = 21 }, .{ .x = 19, .y = 22 }, .{ .x = 21, .y = 21 }, .{ .x = 21, .y = 22 } }) |p| g.lv.set(p, .wall);
    g.lv.addGas(.{ .x = 20, .y = 23 }, harness.TEST_GAS);
    game.settle(g);
    harness.use(g, .wait);
    const half = g.pool.n - 1;
    try std.testing.expectEqual(@as(?usize, actor.Pool.slot(id)), g.split_from[half]);
    try std.testing.expect(g.lv.gassy(g.pool.items[half].at) and !g.lv.gassy(at));
    const when = showsAndLands(g, half);
    std.debug.print("a half a sweep splits off into gas: shows {d:.3} s in, stung {d:.3} s in\n", .{ when.shows, when.lands });
    try std.testing.expect(when.lands >= when.shows);
}

fn ledge(g: *game.Game) P {
    shots.wallRow(&g.lv, 21, 18, 26);
    return .{ .x = 22, .y = 22 };
}

fn revealed(g: *game.Game, slot: usize) bool {
    return g.split_from[slot] == null;
}

const Ledged = struct { dark: P, half: usize };

/// The gas splits a half off a slime on an unlit ledge into sight as the archer steps; returns before `catchUp`.
fn gassedOffLedge(g: *game.Game) Ledged {
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const dark = ledge(g);
    const id = harness.spawnAt(g, .slime_half, dark, true);
    const half = actor.Pool.slot(harness.spawnAt(g, .slime_quarter, .{ .x = 22, .y = 19 }, true));
    const s = actor.Pool.slot(id);
    g.split_from[half] = s;
    g.pool.move(&g.lv, g.hero, .{ .x = 19, .y = 20 });
    game.castSight(g, .{ .x = 19, .y = 20 });
    g.owed[s].gassed = .{ .kill = false, .after = .{ .body = combat.snap(g, s), .reveals = half } };
    g.order_n = 0;
    game.stepGlide(g, 0);
    return .{ .dark = dark, .half = half };
}

test "a half the gas splits off an unlit slime into sight shows as the archer's step lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const l = gassedOffLedge(g);
    const half = l.half;
    try std.testing.expect(!g.lv.isLit(l.dark) and g.lv.isLit(g.pool.items[half].at));
    const step = g.glide[game.heroSlot(g).?].left();
    game.catchUp(g);
    const t = harness.framesUntil(g, half, revealed);
    std.debug.print("a half split off an unlit slime by the gas: revealed {d:.3} s in, the archer's step lands at {d:.3} s\n", .{ t, step });
    try std.testing.expect(step > 0);
    try std.testing.expectApproxEqAbs(step, t, harness.TEST_TOL);
}

test "a half revealed as the turn's picture ends shows before a held walk starts the next turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const half = gassedOffLedge(g).half;
    game.catchUp(g);
    const from = g.heroActor().?.at;
    var shown: ?usize = null;
    var n: usize = 0;
    while (n < 400) : (n += 1) {
        g.st = .{ .walk = .w };
        game.update(g, harness.TEST_DT);
        if (shown == null and revealed(g, half)) shown = n;
        if (!g.heroActor().?.at.eq(from)) break;
    }
    std.debug.print("held walk past a reveal: half shown at frame {?d}, next step at frame {d}\n", .{ shown, n });
    try std.testing.expect(shown != null and n > shown.?);
}

test "a half revealed as the turn's picture ends holds the turn's log lines until it has slid out" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const half = gassedOffLedge(g).half;
    game.catchUp(g);
    g.log.say("held", .{});
    var shown: ?usize = null;
    var released: ?usize = null;
    var n: usize = 0;
    while (n < 400 and released == null) : (n += 1) {
        game.update(g, harness.TEST_DT);
        if (shown == null and revealed(g, half)) shown = n;
        if (g.log.held == 0) released = n;
    }
    std.debug.print("log past a reveal: half shown at frame {?d}, lines released at frame {?d}\n", .{ shown, released });
    try std.testing.expect(shown != null and released != null and released.? > shown.?);
}

test "a quarter the gas splits off a burning half on its waiting turn burns that turn as its sibling does" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = harness.spawnAt(g, .slime_half, at, true);
    const a = g.pool.get(id).?;
    a.hp = actor.row(.slime_quarter).hp;
    a.burn = .{ .turns = burning.TURNS };
    a.resists.set(.fire, 50);
    a.waits = true;
    g.lv.addGas(at, harness.TEST_GAS);
    game.catchUp(g);
    harness.use(g, .wait);
    const s = actor.Pool.slot(id);
    const q = s + 1;
    try std.testing.expectEqual(actor.Kind.slime_quarter, g.pool.items[q].kind);
    std.debug.print("a burning half split by the gas on its waiting turn: burn turns left {d} and {d}\n", .{ g.pool.items[s].burn.turns, g.pool.items[q].burn.turns });
    try std.testing.expectEqual(g.pool.items[s].burn.turns, g.pool.items[q].burn.turns);
}

test "a split nobody sees holds no one's walk" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 40, .y = 20 };
    const id = splittable(g, at, false);
    g.lv.addGas(at, harness.TEST_GAS);
    game.catchUp(g);
    harness.use(g, .wait);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pool.get(id).?.kind);
    try std.testing.expectEqual(@as(?usize, null), g.split_from[actor.Pool.slot(id) + 1]);
    try std.testing.expect(g.busy <= 0);
}

test "a foe the gas kills as it steps out of sight is drawn stepping out, not gone from where it stood" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = actor.Pool.slot(2);
    const dark = ledge(g);
    game.castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.lv.isLit(dark));
    g.pool.move(&g.lv, 2, dark);
    _ = g.pool.damage(&g.lv, 2, actor.row(.rat).hp);
    g.owed[rat].gassed = .{ .kill = true, .after = .{ .body = fx.Body.of(g.pool.items[rat], 0) } };
    harness.staggerOnly(g, 2);
    game.catchUp(g);
    try std.testing.expect(game.drawnAt(g, rat) != null);
    const alive_shown = g.pictured[rat].hp;
    const t = harness.framesUntil(g, rat, harness.gone);
    std.debug.print("a rat the gas kills stepping out of sight a stagger in: drawn until {d:.3} s on {d} hp, its hop {d:.3} to {d:.3} s\n", .{ t, alive_shown, game.STAGGER_S, game.STAGGER_S + game.GLIDE_S });
    try std.testing.expect(alive_shown > 0);
    try std.testing.expect(t > game.STAGGER_S and t < game.STAGGER_S + game.GLIDE_S);
}

test "a foe the gas kills stepping from dark to dark has its death landed by the time the turn is quiet" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const dark = ledge(g);
    const was = P{ .x = dark.x + 1, .y = dark.y };
    const id = harness.spawnAt(g, .slime, was, true);
    const s = actor.Pool.slot(id);
    game.castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.lv.isLit(dark) and !g.lv.isLit(was));
    g.pool.move(&g.lv, id, dark);
    _ = g.pool.damage(&g.lv, id, g.pool.items[s].hp);
    g.owed[s].gassed = .{ .kill = true, .after = .{ .body = fx.Body.of(g.pool.items[s], 0) } };
    harness.staggerOnly(g, id);
    game.catchUp(g);
    var t: f32 = 0;
    while (!game.quiet(g) and t < 1) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    game.update(g, harness.TEST_DT);
    std.debug.print("a slime the gas kills sliding dark to dark: quiet {d:.3} s in, its death still due: {}\n", .{ t, g.fx.pending(s) });
    try std.testing.expect(!g.fx.pending(s));
}

test "a foe with no place in the turn is stung as the archer's step lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 28, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
    g.lv.addGas(at, harness.TEST_GAS);
    harness.nudge(g, .w);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.hurt() and g.pool.get(2).?.at.eq(at));
    const t = harness.framesUntil(g, rat, harness.flashing);
    std.debug.print("a still rat in gas as the archer steps: stung {d:.3} s in, the step lands at {d:.3} s\n", .{ t, game.GLIDE_S });
    try std.testing.expectApproxEqAbs(game.GLIDE_S, t, harness.TEST_TOL);
}

test "a foe is drawn turning at its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    harness.wakeFoes(g);
    harness.use(g, .wait);
    const far = actor.Pool.slot(3);
    try std.testing.expectEqual(game.Facing.right, g.facing[far]);
    const t = harness.framesUntil(g, far, harness.facesLeft);
    std.debug.print("the second rat in the turn is drawn turning {d:.3} s in\n", .{t});
    try std.testing.expectApproxEqAbs(game.STAGGER_S, t, harness.TEST_TOL);
}

test "a kick due late in a frame puts the foes a stagger after it lands, late once" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 20, .y = 21 } });
    harness.wakeFoes(g);
    const late: f32 = 0.05;
    harness.calm(g);
    g.busy = -1;
    g.st = .{ .walk = .e };
    g.st.step.late = late;
    g.rng = harness.meleeThenBites(g, 2);
    game.update(g, 0);
    const t = harness.framesUntil(g, game.heroSlot(g).?, harness.reddened);
    std.debug.print("a kick due {d:.3} s late: the first bite lands {d:.3} s on\n", .{ late, t });
    try std.testing.expectApproxEqAbs(2 * game.BUMP_LANDS + game.STAGGER_S - late, t, harness.TEST_TOL);
}

test "a flask pressed mid-walk is drunk once the step is drawn, ahead of the held walk" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    g.heroActor().?.hp -= 5;
    const by = shots.boundTo(g, .life_flask);
    g.busy = game.GLIDE_S;
    g.st = .{ .walk = .e, .pressed = .initOne(by.by), .down = .initOne(by.by) };
    if (by.set == .secondary) g.st.down.insert(g.bar.modifier.?);
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    const clock = g.clock;
    g.st = .{ .walk = .e };
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expect(g.pending == null);
    try std.testing.expectEqual(flask.CHARGES / flask.USE - 1, g.flasks.get(.life).uses());
    try std.testing.expect(!std.meta.eql(clock, g.clock));
    try std.testing.expect(g.heroActor().?.at.eq(at));
    std.debug.print("flask queued behind a held walk: drunk on the first quiet frame, hero still at {d},{d}\n", .{ at.x, at.y });
}

test "losing focus discards a queued walk while the current turn finishes drawing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    g.busy = game.GLIDE_S;
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Queued, .{ .walk = .e }), g.pending);
    const minute = g.clock.minute;
    g.st = .{ .focused = false };
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expect(game.quiet(g) and g.pending == null);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    try std.testing.expectEqual(minute, g.clock.minute);
    g.st = .{};
    game.update(g, mathx.FRAME_DT);
    try std.testing.expectEqual(at, g.heroActor().?.at);
    std.debug.print("focus loss: queued walk discarded, presentation finishes, no extra turn on return\n", .{});
}

test "a walk due just before the last turn is drawn out starts as it ends" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const busy: f32 = 0.005;
    const dt: f32 = 0.016;
    const due: f32 = 0.015;
    harness.calm(g);
    g.busy = busy;
    g.st = .{ .walk = .e };
    g.st.step.late = due;
    game.update(g, dt);
    const t = g.glide[game.heroSlot(g).?].t;
    std.debug.print("a walk due {d:.3} s ago, the turn drawn out {d:.3} s ago: the step is {d:.3} s in\n", .{ due, dt - busy, t });
    try std.testing.expectApproxEqAbs(dt - busy, t, 1e-5);
}

test "a run left mid-turn keeps the way its foes were turning" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    harness.wakeFoes(g);
    harness.use(g, .wait);
    const far = actor.Pool.slot(3);
    try std.testing.expectEqual(game.Facing.right, g.facing[far]);
    game.leave(g);
    std.debug.print("a rat turning as the run is left faces {s}\n", .{@tagName(g.facing[far])});
    try std.testing.expectEqual(game.Facing.left, g.facing[far]);
}

test "a foe that notices the archer turns to it once the archer's step is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 24, .y = 20 }});
    harness.nudge(g, .w);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.pool.get(2).?.awake);
    const t = harness.framesUntil(g, rat, harness.facesLeft);
    std.debug.print("a rat noticing the archer turns {d:.3} s in, the step lands at {d:.3} s\n", .{ t, game.GLIDE_S });
    try std.testing.expectApproxEqAbs(game.GLIDE_S, t, harness.TEST_TOL);
}

test "a slime split off one not yet drawn waits for it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const p = actor.Pool.slot(harness.spawnAt(g, .slime_half, .{ .x = 25, .y = 20 }, false));
    const c = actor.Pool.slot(harness.spawnAt(g, .slime_half, .{ .x = 26, .y = 20 }, false));
    const d = actor.Pool.slot(harness.spawnAt(g, .slime_quarter, .{ .x = 27, .y = 20 }, false));
    g.split_from[c] = p;
    g.split_from[d] = c;
    const wait: f32 = 0.1;
    g.fx.strike(wait, .{ .slot = p, .at = mathx.centre(g.pool.items[p].at), .dir = null, .matter = .ooze, .lethal = false, .after = .{ .body = fx.Body.of(g.pool.items[p], 1), .reveals = c } });
    game.catchUp(g);
    try std.testing.expect(g.split_from[c] != null and g.split_from[d] != null);
    const t = harness.framesUntil(g, d, harness.drawn);
    try std.testing.expectApproxEqAbs(wait, t, harness.TEST_TOL);
    try std.testing.expect(game.drawnAt(g, c) != null);
}

test "the dead archer's floor restarts only once the death is shown" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    bittenToDeath(g);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    g.st = .{};
    g.st.pressed.insert(CONFIRM);
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    _ = harness.framesUntil(g, 0, harness.deathDrawn);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, g.mode);
}

test "the hud's tooltip stays up until the lethal bite is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    bittenToDeath(g);
    try std.testing.expect(g.mode == .dead and !game.deathShown(g));
    var buf: [overlay.SPOTS_MAX]overlay.Part = undefined;
    const spot = overlay.spotsOf(g, &buf)[0];
    g.st.pointer = look.middleAt(spot.box);
    try std.testing.expectEqual(spot.spot, overlay.hovered(g).?.spot);
    const t = harness.framesUntil(g, 0, harness.deathDrawn);
    g.st.pointer = look.middleAt(spot.box);
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    std.debug.print("dying: tooltip held {d:.3} s until the death is drawn\n", .{t});
}

test "Character stays drawn over a lethal item turn until the bite is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    g.heroActor().?.hp = 1;
    character.openCharacter(g);
    var turns: usize = 0;
    while (g.mode != .dead and turns < harness.TRIES) : (turns += 1) {
        try std.testing.expect(g.inventory.add(.{ .kind = .ring }));
        character.characterCommand(g, .{ .drop = g.inventory.n - 1 });
        if (g.mode != .dead) harness.drawnOut(g);
    }
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.pause, game.modeShown(g));
    const t = harness.framesUntil(g, 0, harness.deathDrawn);
    try std.testing.expectEqual(game.Mode.dead, game.modeShown(g));
    std.debug.print("dying in Character: book held {d:.3} s until the death is drawn\n", .{t});
}

test "the Nearby list keeps its entries over a lethal pickup until the bite is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at: P = .{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    g.heroActor().?.hp = 1;
    var turns: usize = 0;
    while (g.mode != .dead and turns < harness.TRIES) : (turns += 1) {
        for (0..2) |_| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = .ring }, .at = at }));
        if (g.mode != .pause) try std.testing.expect(character.openNearby(g));
        character.characterCommand(g, .{ .pickup = 0 });
        if (g.mode != .dead) harness.drawnOut(g);
    }
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.pause, game.modeShown(g));
    var buf: game.NearbyBuf = undefined;
    const shown = character.nearbyOf(g, &buf).len;
    try std.testing.expect(shown > 0);
    std.debug.print("dying in Nearby: {d} entries still listed while the bite is drawn\n", .{shown});
}

test "the ring slid under the cursor after an equip starts on the left ring again" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    for (0..2) |_| try std.testing.expect(g.inventory.add(.{ .kind = .ring }));
    character.openCharacter(g);
    g.character.choose(.inventory);
    g.character.destination_index = 1;
    character.characterCommand(g, .{ .equip = .{ .index = 0, .slot = .right_ring } });
    try std.testing.expect(g.inventory.gear.slots.get(.right_ring) != null);
    try std.testing.expectEqual(@as(usize, 0), g.character.destination_index);
}

test "Menu, B or X leaves the death screen as A does, and none of them pauses it" {
    for (game.DISMISS) |b| {
        const g = try game.boot(std.testing.allocator);
        defer game.shut(std.testing.allocator, g);
        bittenToDeath(g);
        _ = harness.framesUntil(g, 0, harness.deathDrawn);
        harness.press(g, b);
        try std.testing.expectEqual(game.Mode.play, g.mode);
    }
}

test "the reticle crosses the archer to the far side of a corridor" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 15, .y = 20 } });
    shots.wallRow(&g.lv, 19, 10, 30);
    shots.wallRow(&g.lv, 21, 10, 30);
    game.castSight(g, .{ .x = 20, .y = 20 });
    harness.press(g, .x);
    try std.testing.expectEqual(P{ .x = 23, .y = 20 }, g.mark);
    for (0..3) |_| harness.nudge(g, .w);
    try std.testing.expectEqual(P{ .x = 19, .y = 20 }, g.mark);
}

test "the view's edge reddens as a bite lands on the archer, not before, and as the gas eats at it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    harness.wakeFoes(g);
    harness.nudge(g, .e);
    try std.testing.expect(g.heroActor().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const t = harness.framesUntil(g, game.heroSlot(g).?, harness.reddened);
    std.debug.print("a bite bumped a stagger into the turn reddens the view {d:.3} s in\n", .{t});
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t, harness.TEST_TOL);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.addGas(.{ .x = 20, .y = 20 }, harness.TEST_GAS);
    harness.use(g, .wait);
    try std.testing.expect(g.heroActor().?.hurt());
    try std.testing.expect(harness.framesUntil(g, game.heroSlot(g).?, harness.reddened) < harness.TEST_TOL);
}

test "gas left to eat at the archer kills it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.addGas(.{ .x = 20, .y = 20 }, harness.TEST_GAS);
    g.heroActor().?.hp = 1;
    harness.use(g, .wait);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    try std.testing.expectEqualStrings("Archer dies.", g.log.line(0).?);
    try std.testing.expect(harness.framesUntil(g, game.heroSlot(g).?, harness.reddened) < harness.TEST_TOL);
}

test "an unkillable archer keeps 1 hp through gas and bites that would kill it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 } });
    harness.wakeFoes(g);
    g.unkillable = true;
    g.lv.addGas(.{ .x = 20, .y = 20 }, harness.TEST_GAS);
    g.heroActor().?.hp = 2;
    for (0..20) |_| harness.use(g, .wait);
    std.debug.print("an unkillable archer after 20 turns in gas between two rats: {d} hp\n", .{g.heroActor().?.hp});
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(@as(i32, 1), g.heroActor().?.hp);
}

test "a bloat that bursts on the archer takes its place in the turn as a bite does, and its spray lands there" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var seed: u64 = 0;
    while (seed < 50) : (seed += 1) {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 19, .y = 20 }});
        harness.wakeFoes(g);
        const id = harness.spawnAt(g, .bloat, .{ .x = 21, .y = 20 }, true);
        g.rng = mathx.Rng.init(seed);
        harness.use(g, .wait);
        if (g.pool.get(id) == null) break;
    } else return error.NeverBurst;
    try std.testing.expectEqualSlices(u16, &.{ 2, 3 }, g.order[0..g.order_n]);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS + fx.FLASH_S, g.busy, 1e-6);
    try std.testing.expectEqual(@as(usize, 2), g.fx.due_n);
    const busy = g.busy;
    const t = harness.framesUntil(g, actor.Pool.slot(3), harness.flashing);
    std.debug.print("a rat bites, then a bloat bursts on the archer: the burst lands {d:.3} s in, the turn is busy {d:.3} s\n", .{ t, busy });
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t, harness.TEST_TOL);
}

fn idle(g: *game.Game) void {
    harness.calm(g);
    g.st = .{};
    game.update(g, 0);
}

test "a node's sky shows its light and its weather out of doors, and neither under a roof" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    const wet: climate.Climate = .{ .light = .bleak, .weather = .drizzle };
    const strand = w.add(.{ .procgen = .{ .floor = .{ .wilds = .{} }, .sky = wet } }).?;
    const cave = w.add(.{ .procgen = .{ .floor = .{ .caves = .{} }, .sky = wet } }).?;
    g.screen = game.SCREEN_1080;
    for ([_]usize{ strand, cave }) |n| {
        w.start = .{ .node = n, .at = grid.MIDDLE };
        game.beginMap(g, w);
        for (0..10) |_| game.update(g, mathx.FRAME_DT);
        if (n == strand) {
            const bright = sky.brightness(g.light.sky.?);
            const clear = sky.brightness(sky.at(g.hour_shown));
            std.debug.print("a bleak, drizzling wilds at {d:.2}: {d:.2} of a clear noon's light against {d:.2} clear; {d} drops\n", .{ g.hour_shown, bright, clear, g.rain.n });
            try std.testing.expect(bright < clear * 0.9);
            try std.testing.expect(g.rain.n > 0);
        } else {
            try std.testing.expect(g.light.sky == null);
            try std.testing.expectEqual(@as(usize, 0), g.rain.n);
        }
    }
}

test "a door takes the archer to the door it leads to, and a node left is found as it was" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    const room = w.add(.{ .bespoke = .{} }).?;
    const cave = w.add(.{ .procgen = .{} }).?;
    const b = &w.node[room].plan.bespoke;
    corridor(b);
    const slime = P{ .x = 2, .y = 5 };
    _ = b.addFoe(.{ .kind = .slime, .at = slime });
    const d0 = w.addDoor(room, .{ .x = 12, .y = 5 }).?;
    const d1 = w.addDoor(cave, .{ .x = 30, .y = 30 }).?;
    w.link(.{ .node = room, .door = d0 }, .{ .node = cave, .door = d1 });
    w.start = .{ .node = room, .at = .{ .x = 10, .y = 5 } };
    game.beginMap(g, w);
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    _ = g.pool.damage(&g.lv, g.hero, 5);
    harness.nudge(g, .e);
    harness.nudge(g, .e);
    try std.testing.expect(g.travel != null);
    idle(g);
    try std.testing.expectEqual(cave, g.node);
    try std.testing.expectEqual(P{ .x = 30, .y = 30 }, g.heroActor().?.at);
    try std.testing.expectEqual(actor.row(HERO).hp - 5, g.heroActor().?.hp);
    try std.testing.expect(g.pool.n > 1);
    try std.testing.expect(g.visits[room].ground.gold(.{ .x = 12, .y = 5 }, 17));
    const off = found: for ([_]bool{ false, true }) |diagonal| {
        for (mathx.ALL_DIRS) |d| {
            if (d.diagonal() == diagonal and g.lv.stepOk(g.heroActor().?.at, d, g.hero)) break :found d;
        }
    } else return error.DoorWalledIn;
    harness.nudge(g, off);
    harness.nudge(g, off.opposite());
    idle(g);
    try std.testing.expectEqual(room, g.node);
    try std.testing.expectEqual(@as(i32, 17), g.gold);
    try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
    try std.testing.expectEqual(P{ .x = 12, .y = 5 }, g.heroActor().?.at);
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    try std.testing.expectEqual(slime, g.pool.items[actor.Pool.slot(2)].at);
    try std.testing.expect(g.lv.isSeen(.{ .x = 10, .y = 5 }));
    std.debug.print("through a door and back: node {d}, the slime still at {d},{d}\n", .{ g.node, slime.x, slime.y });
}

test "a procgen node rolls another floor round the same doors each run, and two nodes differ in one run" {
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    const n = w.add(.{ .procgen = .{} }).?;
    const door = P{ .x = 30, .y = 30 };
    _ = w.addDoor(n, door);
    var lv: [3]grid.Level = undefined;
    w.node[n].stamp(&lv[0], game.rollOf(1, n));
    w.node[n].stamp(&lv[1], game.rollOf(2, n));
    w.node[n].stamp(&lv[2], game.rollOf(1, n + 1));
    var differ = [2]usize{ 0, 0 };
    for (0..grid.CELLS) |i| {
        if (lv[0].tile[i] != lv[1].tile[i]) differ[0] += 1;
        if (lv[0].tile[i] != lv[2].tile[i]) differ[1] += 1;
    }
    std.debug.print("one procgen node, two runs: {d} cells differ; two nodes of one run: {d}\n", .{ differ[0], differ[1] });
    for (lv) |l| try std.testing.expectEqual(@as(?usize, 0), l.doorAt(door));
    try std.testing.expect(differ[0] > 0 and differ[1] > 0);
}

test "a door keeps the low glow, a level-up, the archer's facing and a walk pressed while the door turn is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    const b = twoRooms(w);
    const a = w.start.node;
    _ = w.node[b].plan.bespoke.addFoe(.{ .kind = .rat, .at = .{ .x = 11, .y = 5 } });
    game.beginMap(g, w);
    _ = g.pool.damage(&g.lv, g.hero, actor.row(HERO).hp - 1);
    g.st = .{};
    for (0..480) |_| game.update(g, harness.TEST_DT);
    const low = g.vignette.low;
    _ = g.growth.gain(@intCast(g.growth.needed()));
    harness.nudge(g, .w);
    g.st = .{ .walk = .w };
    game.update(g, harness.TEST_DT);
    g.st = .{};
    while (g.node == a) game.update(g, harness.TEST_DT);
    try std.testing.expect(g.fx.level_up.life > 0);
    try std.testing.expectEqual(game.Facing.left, g.facing[game.heroSlot(g).?]);
    try std.testing.expect(!g.heroActor().?.at.eq(.{ .x = 11, .y = 5 }));
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    std.debug.print("through a door on 1 hp: the low glow {d:.3} before, {d:.3} after, a walk queued: {}\n", .{ low, g.vignette.low, g.pending != null });
    try std.testing.expect(g.pending != null);
    try std.testing.expectApproxEqAbs(low, g.vignette.low, 0.05);
}

test "the pause menu spends no turn, and its way out leads back to where the game was started from" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    harness.wakeFoes(g);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    for (std.enums.values(game.Back)) |back| {
        g.back = back;
        harness.press(g, PAUSE);
        for (0..game.rowAt(game.PauseRow.back)) |_| harness.nudge(g, .s);
        harness.press(g, .a);
        try std.testing.expectEqual(@as(?game.Exit, .back), g.exit);
        try std.testing.expectEqual(game.Mode.play, g.mode);
        g.exit = null;
    }
    try std.testing.expectEqual(P{ .x = 26, .y = 20 }, g.pool.get(2).?.at);
}

test "Character and Game have separate shortcuts and never spend a turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const clock = g.clock;
    const hp = g.heroActor().?.hp;
    harness.press(g, menu.CHARACTER);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    g.character.choose(.inventory);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(hp, g.heroActor().?.hp);
    harness.press(g, menu.CHARACTER);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    harness.press(g, menu.CHARACTER);
    try std.testing.expectEqual(game.PausePage.character, g.pause_page);
    try std.testing.expectEqual(book.Page.inventory, g.character.page);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(clock, g.clock);
    std.debug.print("Character: direct toggle, retained page, one-step back; Game: separate menu; zero turns\n", .{});
}

test "Character page shortcuts open switch and close without acting or carrying movement" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const at = g.heroActor().?.at;
    const clock = g.clock;
    const mana = g.mana;
    var checked: usize = 0;
    for ([_]game.Mode{ .play, .aim, .inspect, .bind, .pause }) |mode| {
        g.mode = mode;
        g.pause_page = .main;
        for (std.enums.values(input.CharacterPage)) |page| {
            g.st = .{ .device = .keys, .character_page = page, .walk = .s };
            game.update(g, 0);
            try std.testing.expectEqual(game.Mode.pause, g.mode);
            try std.testing.expectEqual(game.PausePage.character, g.pause_page);
            try std.testing.expectEqual(book.Page.of(page), g.character.page);
            try std.testing.expect(g.st.walk == null and g.pending == null);
            if (page == .passives) try std.testing.expectEqual(progress.start(g.class), g.character.cursor);
            try std.testing.expectEqual(at, g.heroActor().?.at);
            checked += 1;
        }
        g.st = .{ .device = .keys, .character_page = .skills };
        game.update(g, 0);
        try std.testing.expectEqual(game.Mode.play, g.mode);
    }
    g.mode = .dead;
    g.st = .{ .character_page = .equipment };
    game.update(g, 0);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqual(mana, g.mana);
    std.debug.print("Character shortcuts: {d} page openings, 5 toggles, death guarded; no turns or mana spent\n", .{checked});
}

test "an arena restart restores its selected opponent and hero" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(map);
    spar.author(map, .bloat);
    game.beginMap(g, map);
    _ = g.pool.damage(&g.lv, 2, 100);
    _ = g.pool.damage(&g.lv, g.hero, 3);
    g.mana = 0;
    game.restart(g);
    try std.testing.expectEqual(@as(usize, 2), g.pool.n);
    try std.testing.expectEqual(actor.Kind.bloat, g.pool.items[1].kind);
    try std.testing.expect(g.pool.items[1].alive);
    try std.testing.expectEqual(actor.row(HERO).hp, g.heroActor().?.hp);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    try std.testing.expectEqual(spar.HERO, g.heroActor().?.at);
    std.debug.print("arena retry: bloat and hero restored at their starting positions with full resources\n", .{});
}

test "Debug graphics toggles are independent and spend no simulation" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
    const before = g.lv;
    const clock = g.clock;
    const rng = g.rng;
    const hp = g.heroActor().?.hp;
    harness.press(g, PAUSE);
    g.pause_menu.at = game.rowAt(game.PauseRow.debug);
    harness.press(g, CONFIRM);
    var toggles: usize = 0;
    inline for (.{ .{ cinema.Options, &g.cinema.options }, .{ light.Options, &g.light.options }, .{ game.debugging.Visuals, &g.debug.visuals } }) |group| {
        inline for (std.meta.fields(group[0])) |f| {
            game.debugging.select(g, @field(game.debugging.Row, f.name));
            for ([_]bool{ false, true }) |on| {
                harness.press(g, CONFIRM);
                inline for (std.meta.fields(group[0])) |other| {
                    const expected = if (comptime std.mem.eql(u8, f.name, other.name)) on else true;
                    try std.testing.expectEqual(expected, @field(group[1], other.name));
                }
                try std.testing.expectEqualSlices(bool, &before.seen, &g.lv.seen);
                try std.testing.expectEqualSlices(bool, &before.lit, &g.lv.lit);
                try std.testing.expectEqualSlices(grid.Tile, &before.tile, &g.lv.tile);
                try std.testing.expectEqual(clock, g.clock);
                try std.testing.expectEqual(rng, g.rng);
                try std.testing.expectEqual(hp, g.heroActor().?.hp);
                try std.testing.expectEqual(game.Mode.pause, g.mode);
                toggles += 1;
            }
        }
    }
    std.debug.print("Debug graphics: {d} independent toggles preserve terrain, visibility, clock, RNG and life\n", .{toggles});
}

test "Debug reveal toggles map terrain without spending turns or changing explored cells" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const far = P{ .x = 60, .y = 40 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{far});
    const seen = g.lv.seen;
    const lit = g.lv.lit;
    const clock = g.clock;
    const rng = g.rng;
    try std.testing.expect(!character.terrainSeen(g, far));
    harness.press(g, PAUSE);
    for (0..game.rowAt(game.PauseRow.debug)) |_| harness.nudge(g, .s);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.debugging.Page.gameplay, g.debug.page);
    harness.nudge(g, .s);
    for ([_]bool{ true, false }) |enabled| {
        harness.press(g, CONFIRM);
        try std.testing.expectEqual(enabled, g.light.reveal_map);
        try std.testing.expectEqual(enabled, character.terrainSeen(g, far));
        try std.testing.expectEqual(@as(f32, if (enabled) 1 else 0), g.light.memory[grid.Level.idx(far)]);
        try std.testing.expectEqualSlices(bool, &seen, &g.lv.seen);
        try std.testing.expectEqualSlices(bool, &lit, &g.lv.lit);
        try std.testing.expectEqual(clock, g.clock);
        try std.testing.expectEqual(rng, g.rng);
        try std.testing.expect(game.drawnAt(g, actor.Pool.slot(2)) == null);
    }
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    try std.testing.expectEqual(game.debugging.Page.main, g.debug.page);
    harness.press(g, BACK);
    try std.testing.expectEqual(game.PausePage.main, g.pause_page);
    try std.testing.expectEqual(game.Mode.pause, g.mode);
    harness.press(g, PAUSE);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    std.debug.print("Debug reveal: on/off restores fog, all {d} exploration cells unchanged; back exits one menu at a time\n", .{grid.CELLS});
}

test "Debug restart begins the map anew and clears visited nodes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(map);
    map.* = .{};
    _ = map.add(.{ .procgen = .{} });
    _ = map.add(.{ .procgen = .{} });
    game.beginMapAt(g, map, .{ .node = 1, .at = grid.MIDDLE }, 12);
    g.visited.set(1);
    g.gold = 99;
    g.heroActor().?.hp = 1;
    harness.press(g, PAUSE);
    for (0..game.rowAt(game.PauseRow.debug)) |_| harness.nudge(g, .s);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.PausePage.debug, g.pause_page);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.debugging.Page.gameplay, g.debug.page);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(map.start.node, g.node);
    try std.testing.expectEqual(@as(usize, 0), g.visited.count());
    try std.testing.expectEqual(@as(i32, 0), g.gold);
    try std.testing.expectEqual(game.heroRow(g).hp, g.heroActor().?.hp);
    try std.testing.expect(g.seed != 12);
    std.debug.print("Debug restart: returns to map start, rerolls seed, restores hero and clears visited nodes and gold\n", .{});
}

test "a pib's landed stab bleeds the archer about three times in ten, drawn once the stab lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var bled: usize = 0;
    var landed: usize = 0;
    for (0..harness.TRIES) |i| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        _ = harness.spawnAt(g, .pib, .{ .x = 21, .y = 20 }, true);
        g.rng = mathx.Rng.init(i);
        harness.use(g, .wait);
        const h = g.heroActor().?;
        if (!h.hurt()) {
            try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
            continue;
        }
        landed += 1;
        if (h.bleed.turns == 0) continue;
        bled += 1;
        try std.testing.expectEqual(bleeding.TURNS, h.bleed.turns);
        try std.testing.expectEqual(@as(u8, 0), g.pictured[game.heroSlot(g).?].status.get(.bleeding));
        harness.drawnOut(g);
        try std.testing.expectEqual(bleeding.TURNS, g.pictured[game.heroSlot(g).?].status.get(.bleeding));
    }
    std.debug.print("a pib beside the archer: {d} stabs, {d} landed, {d} bleeds\n", .{ harness.TRIES, landed, bled });
    try std.testing.expect(landed > 0 and landed < harness.TRIES);
    try std.testing.expect(harness.aboutRateOf(bled, landed, mathx.fraction(actor.row(.pib).blow.strike.bleeds)));
}

fn ratsHp(g: *game.Game) i32 {
    var hp: i32 = 0;
    for (g.pool.slice()) |a| {
        if (a.kind == .rat) hp += a.hp;
    }
    return hp;
}

test "a beefy pib sweeps the archer and every foe and barrel round it every fourth turn, never bleeds and never flees" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 22, .y = 20 }, .{ .x = 22, .y = 21 }, .{ .x = 20, .y = 19 } });
    harness.toughenFoes(g);
    harness.setLife(&g.pool.items[3], 1, 1);
    const beefy = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    const barrel = P{ .x = 22, .y = 19 };
    g.lv.putBarrel(barrel);
    harness.wakeFoes(g);
    g.unkillable = true;
    var swept: [8]bool = undefined;
    for (&swept) |*s| {
        const before = ratsHp(g);
        harness.calm(g);
        harness.use(g, .wait);
        s.* = ratsHp(g) < before;
    }
    std.debug.print("a beefy pib's 8 turns, swept: {any}\n", .{swept});
    try std.testing.expectEqualSlices(bool, &.{ true, false, false, false, true, false, false, false }, &swept);
    try std.testing.expect(!g.lv.hasBarrel(barrel));
    try std.testing.expect(!g.pool.items[3].alive);
    try std.testing.expectEqual(@as(u8, 0), g.pool.get(beefy).?.fright);
    try std.testing.expectEqual(@as(u8, 0), g.heroActor().?.bleed.turns);
}

test "a beefy pib's landed blow stuns the archer about a quarter of the time, and its next turn passes without it once drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var landed: usize = 0;
    var stunned: usize = 0;
    for (0..harness.TRIES) |i| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
        g.pool.get(id).?.sweep_in = actor.row(.beefy_pib).sweep_every + 1;
        g.unkillable = true;
        g.rng = mathx.Rng.init(i);
        harness.use(g, .wait);
        const h = g.heroActor().?;
        if (!h.hurt()) {
            try std.testing.expect(!h.clock.owes());
            continue;
        }
        landed += 1;
        if (!h.clock.owes()) continue;
        stunned += 1;
        const turn = g.clock;
        const at = h.at;
        g.st = .{};
        game.update(g, 0);
        try std.testing.expectEqual(turn, g.clock);
        g.pool.get(id).?.clock.stun();
        g.busy = 0;
        g.st = .{ .walk = .w };
        game.update(g, 0);
        try std.testing.expect(!std.meta.eql(turn, g.clock));
        try std.testing.expectEqual(at, g.heroActor().?.at);
        try std.testing.expect(!g.heroActor().?.clock.owes());
    }
    std.debug.print("a beefy pib beside the archer: {d} blows, {d} landed, {d} stunned\n", .{ harness.TRIES, landed, stunned });
    try std.testing.expect(landed > 0 and landed < harness.TRIES);
    try std.testing.expect(harness.aboutRateOf(stunned, landed, mathx.fraction(actor.row(.beefy_pib).blow.strike.stuns)));
}

test "a foe a beefy pib sweeps is drawn struck as the sweep lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 21 }});
    harness.toughenFoes(g);
    const rat: usize = 1;
    _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    g.unkillable = true;
    harness.use(g, .wait);
    try std.testing.expect(g.pool.items[rat].hp < harness.TEST_HP);
    try std.testing.expectEqual(harness.TEST_HP, g.pictured[rat].hp);
    const t = harness.framesUntil(g, rat, harness.flashing);
    harness.drawnOut(g);
    std.debug.print("a rat swept beside the archer: struck {d:.3} s in, the sweep's bump lands at {d:.3} s\n", .{ t, game.BUMP_LANDS });
    try std.testing.expect(t >= game.BUMP_LANDS - harness.TEST_TOL);
    try std.testing.expectEqual(g.pool.items[rat].hp, g.pictured[rat].hp);
}

test "a sweep stun skips the victim's next action before or after its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const strike = actor.row(.beefy_pib).blow.strike;
    for ([_]bool{ false, true }) |earlier| {
        const at = if (earlier) P{ .x = 21, .y = 21 } else P{ .x = 22, .y = 20 };
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
        harness.toughenFoes(g);
        harness.wakeFoes(g);
        _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
        g.unkillable = true;
        var seed: u64 = 0;
        while (seed < 1000) : (seed += 1) {
            var rng = mathx.Rng.init(seed);
            if (earlier) {
                const by = game.heroAttrs(g);
                if (combat.bite(&rng, by, actor.row(.rat).blow.strike)) |dmg| _ = by.physical(dmg, &rng);
            }
            _ = strike.roll(&rng);
            if (damage.procs(&rng, strike.stuns)) break;
        }
        try std.testing.expect(seed < 1000);
        g.rng = mathx.Rng.init(seed);
        combat.endTurn(g);
        try std.testing.expect(g.pool.items[1].hp < harness.TEST_HP);
        try std.testing.expectEqual(at, g.pool.items[1].at);
        try std.testing.expectEqual(!earlier, g.pool.items[1].clock.stalled);
        try std.testing.expectEqual(earlier, g.pool.items[1].clock.owes());
        if (earlier) try std.testing.expect(g.owed[1].bit != null);
        g.owed[1] = .{};
        combat.endTurn(g);
        try std.testing.expectEqual(earlier, at.eq(g.pool.items[1].at));
        try std.testing.expectEqual(earlier, g.pool.items[1].clock.stalled);
        try std.testing.expect(!g.pool.items[1].clock.owes());
        if (earlier) {
            try std.testing.expect(g.owed[1].bit == null);
            combat.endTurn(g);
            try std.testing.expect(!g.pool.items[1].clock.stalled);
            try std.testing.expect(g.owed[1].bit != null);
        }
    }
    std.debug.print("sweep stun: 2 actor orders skip exactly the victim's next action, then resume moving or striking\n", .{});
}

test "a sweep stun is paid once by both halves when a later slime splits" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 22, .y = 20 };
    const slime = harness.spawnAt(g, .slime, at, true);
    g.pool.get(slime).?.hp = 22;
    _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    g.unkillable = true;
    const strike = actor.row(.beefy_pib).blow.strike;
    var seed: u64 = 0;
    while (seed < 1000) : (seed += 1) {
        var rng = mathx.Rng.init(seed);
        _ = strike.roll(&rng);
        if (damage.procs(&rng, strike.stuns)) break;
    }
    try std.testing.expect(seed < 1000);
    g.rng = mathx.Rng.init(seed);
    combat.endTurn(g);
    try std.testing.expectEqual(@as(usize, 4), g.pool.n);
    try std.testing.expectEqual(at, g.pool.get(slime).?.at);
    for ([_]usize{ actor.Pool.slot(slime), 3 }) |i| {
        try std.testing.expectEqual(actor.Kind.slime_half, g.pool.items[i].kind);
        try std.testing.expect(g.pool.items[i].clock.stalled);
        try std.testing.expect(!g.pool.items[i].clock.owes());
    }
    combat.endTurn(g);
    for ([_]usize{ actor.Pool.slot(slime), 3 }) |i| try std.testing.expect(!g.pool.items[i].clock.stalled);
    std.debug.print("sweep stun and split: 2 halves share the paid stun and can act the following turn\n", .{});
}

test "a swept foe's skipped status turn waits for the sweep's impact" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    harness.toughenFoes(g);
    const rat: usize = 1;
    g.pool.items[rat].chill = .{ .turns = glacial.TURNS, .phase = glacial.CYCLE - 1 };
    _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    g.unkillable = true;
    harness.use(g, .wait);
    try std.testing.expect(g.pool.items[rat].hp < harness.TEST_HP);
    try std.testing.expectEqual(harness.TEST_HP, g.pictured[rat].hp);
    const t = harness.framesUntil(g, rat, harness.flashing);
    try std.testing.expect(t >= game.BUMP_LANDS - harness.TEST_TOL);
    harness.drawnOut(g);
    try std.testing.expectEqual(g.pool.items[rat].hp, g.pictured[rat].hp);
    std.debug.print("swept chilled foe: damage held until impact at {d:.3} s\n", .{t});
}

test "a bleed costs the archer 1 a turn standing and 2 a turn it steps, and stops after five" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const h = g.heroActor().?;
    h.bleed = .{ .turns = bleeding.TURNS };
    const full = h.hp;
    harness.use(g, .wait);
    try std.testing.expectEqual(full - bleeding.STILL, h.hp);
    harness.nudge(g, .e);
    try std.testing.expectEqual(full - bleeding.STILL - bleeding.MOVING, h.hp);
    for (0..bleeding.TURNS - 2) |_| harness.use(g, .wait);
    const spent = full - h.hp;
    try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
    try std.testing.expect(std.mem.indexOf(u8, g.log.line(0).?, "stops bleeding") != null);
    harness.use(g, .wait);
    std.debug.print("a {d}-turn bleed, one turn stepped: {d} hp; none after\n", .{ bleeding.TURNS, spent });
    try std.testing.expectEqual(bleeding.STILL * (bleeding.TURNS - 1) + bleeding.MOVING, spent);
    try std.testing.expectEqual(full - spent, h.hp);
}

test "a pib that sees a foe die wakes and runs for a few turns, then comes back; one behind a wall does not" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const hero = P{ .x = 14, .y = 20 };
    harness.arena(g, hero, &.{.{ .x = 19, .y = 20 }});
    shots.wallRow(&g.lv, 22, 15, 25);
    const near = harness.spawnAt(g, .pib, .{ .x = 20, .y = 21 }, false);
    const walled = harness.spawnAt(g, .pib, .{ .x = 19, .y = 24 }, false);
    game.castSight(g, hero);
    combat.wound(g, 2, .{ .dmg = actor.row(.rat).hp }, combat.SHOOT, .{ .from = hero, .wait = 0.2 });
    const p = g.pool.get(near).?;
    try std.testing.expect(p.awake);
    try std.testing.expectEqual(actor.FLEE_TURNS, p.fright);
    try std.testing.expectEqual(@as(u8, 0), g.pool.get(walled).?.fright);
    try std.testing.expect(std.mem.indexOf(u8, g.log.line(0).?, "flees in terror") != null);
    const speech = &g.fx.speech[actor.Pool.slot(near)];
    const rng = g.rng;
    g.st = .{};
    game.update(g, 0.1);
    try std.testing.expectEqual(@as(f32, 0), speech.life);
    game.update(g, 0.11);
    try std.testing.expectEqual(fx.SPEECH_S, speech.life);
    try std.testing.expectEqual(@as(?usize, null), g.fx.speech[actor.Pool.slot(walled)].after);
    try std.testing.expectEqual(@as(f32, 0), g.fx.speech[actor.Pool.slot(walled)].life);
    combat.scare(g, actor.Pool.slot(2));
    try std.testing.expectEqual(@as(?usize, null), speech.after);
    game.update(g, fx.SPEECH_S);
    try std.testing.expectEqual(@as(f32, 0), speech.life);
    try std.testing.expectEqualDeep(rng, g.rng);
    std.debug.print("pib reaction: {d} phrases, waits for impact, expires after {d:.1}s, no simulation RNG spent\n", .{ fx.FRIGHT_WORDS.len, fx.SPEECH_S });
    var far = mathx.dist(p.at, hero);
    const from = far;
    for (0..actor.FLEE_TURNS) |_| {
        combat.endTurn(g);
        try std.testing.expectEqual(far + 1, mathx.dist(p.at, hero));
        far += 1;
    }
    try std.testing.expectEqual(@as(u8, 0), p.fright);
    combat.endTurn(g);
    std.debug.print("a frightened pib runs from {d} to {d} cells in {d} turns, then turns back to {d}\n", .{ from, far, actor.FLEE_TURNS, mathx.dist(p.at, hero) });
    try std.testing.expect(mathx.dist(p.at, hero) < far);
}

test "a frightened pib in a dead end holds it, and strikes only an archer beside it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const end = P{ .x = 18, .y = 20 };
    const walls = [_]P{ .{ .x = 17, .y = 19 }, .{ .x = 18, .y = 19 }, .{ .x = 19, .y = 19 }, .{ .x = 19, .y = 20 }, .{ .x = 19, .y = 21 }, .{ .x = 18, .y = 21 }, .{ .x = 17, .y = 21 } };
    var moves: usize = 0;
    var strikes: i32 = 0;
    for ([_]P{ .{ .x = 14, .y = 20 }, .{ .x = 17, .y = 20 } }) |hero| {
        harness.arena(g, hero, &.{});
        for (walls) |w| g.lv.set(w, .wall);
        const id = harness.spawnAt(g, .pib, end, true);
        g.pool.get(id).?.fright = actor.FLEE_TURNS;
        const full = g.heroActor().?.hp;
        for (0..actor.FLEE_TURNS) |_| {
            combat.endTurn(g);
            if (!g.pool.get(id).?.at.eq(end)) moves += 1;
        }
        if (hero.x == 17) strikes = full - g.heroActor().?.hp else try std.testing.expectEqual(full, g.heroActor().?.hp);
    }
    std.debug.print("a cornered pib over {d} turns: {d} steps out of its dead end, {d} hp off an archer beside it\n", .{ actor.FLEE_TURNS, moves, strikes });
    try std.testing.expectEqual(@as(usize, 0), moves);
    try std.testing.expect(strikes > 0);
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
    try std.testing.expectEqual(@as(usize, 1), g.ground.n - 1);
    std.debug.print("progression: 3 starter kits, underfoot/adjacent menu, one-turn item actions, no equip healing, automatic gold\n", .{});
}

test "walking over items logs each item once per arrival without picking it up" {
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
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(usize, 0), g.log.held);
    for (0..30) |_| game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(usize, 2), g.log.n);
    g.lv.set(.{ .x = 22, .y = 20 }, .wall);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 2), g.log.n);
    harness.nudge(g, .w);
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(usize, 4), g.log.n);
    std.debug.print("underfoot loot: 2 items named per arrival, no idle/blocked repeats, no pickup or extra turn\n", .{});
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

test "every foe drops loot at its presented death and gold collects when opening its bag" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = from.add(mathx.Dir.e.delta());
    var cases: usize = 0;
    for ([_]bool{ false, true }) |magic| {
        var seed: u64 = 0;
        while (true) : (seed += 1) {
            var probe = mathx.Rng.init(seed);
            const reward = items.foeLoot(&probe);
            if (reward.gold > 0 and reward.item != null and reward.item.?.magical() == magic) break;
        }
        for (std.enums.values(actor.Kind)) |kind| {
            if (!kind.foe()) continue;
            harness.arena(g, from, &.{});
            const id = harness.spawnAt(g, kind, at, false);
            game.settle(g);
            g.loot_rng = mathx.Rng.init(seed);
            combat.wound(g, id, .{ .dmg = 1000 }, combat.SHOOT, .{ .from = from, .wait = 0.2 });
            try std.testing.expectEqual(@as(usize, 1), g.ground.n);
            try std.testing.expectEqual(@as(usize, 1), g.ground.coin_n);
            try std.testing.expectEqual(magic, g.ground.drops[0].item.magical());
            try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
            try std.testing.expect(!scene.goldShown(g, at));
            harness.drawnOut(g);
            try std.testing.expect(scene.bagCells(g).isSet(grid.Level.idx(at)));
            try std.testing.expect(scene.goldShown(g, at));
            const gold = g.ground.coins[0].amount;
            harness.pressInteract(g);
            try std.testing.expectEqual(book.Page.loot, g.character.page);
            try std.testing.expectEqual(gold, g.gold);
            try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
            try std.testing.expectEqual(@as(usize, 0), g.inventory.n);
            harness.press(g, CONFIRM);
            try std.testing.expectEqual(@as(usize, 1), g.inventory.n);
            try std.testing.expectEqual(magic, g.inventory.bag[0].magical());
            cases += 1;
        }
    }
    std.debug.print("foe loot: {d} kind/rarity deaths, bags and gold delayed to impact, gold automatic and items chosen\n", .{cases});
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

test "chest loot collects gold once and leaves excess items when inventory fills" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.lv.set(at, .chest);
    for (0..items.BAG_MAX - 1) |_| try std.testing.expect(g.inventory.add(.{ .kind = .cap }));
    const minute = g.clock.minute;
    harness.pressInteract(g);
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    try std.testing.expectEqual(@as(usize, 1), g.ground.n);
    try std.testing.expectEqual(@as(usize, 0), g.ground.coin_n);
    try harness.expectWithin(g.gold, items.CHEST_GOLD.lo, items.CHEST_GOLD.hi);
    const gold = g.gold;
    try std.testing.expectEqual(minute + day.TURN_MINUTES, g.clock.minute);
    for ([_]items.Kind{ .boots, .ring }) |kind| try std.testing.expect(g.ground.add(.{ .item = .{ .kind = kind }, .at = at }));
    harness.drawnOut(g);
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
    try std.testing.expectEqual(gold, g.gold);
    try std.testing.expectEqual(@as(usize, 2), g.ground.n);
    _ = g.inventory.remove(0);
    _ = g.inventory.remove(0);
    harness.press(g, menu.CHANGE);
    try std.testing.expectEqual(@as(usize, 0), g.ground.n);
    try std.testing.expectEqual(grid.Tile.chest_open, g.lv.at(at));
    try std.testing.expect(!scene.bagCells(g).isSet(grid.Level.idx(at)));
    try std.testing.expectEqual(game.Mode.play, g.mode);
    std.debug.print("chest loot: automatic gold once, full-bag retry costs no turn, 2 excess items survive reopening, empty chest remains\n", .{});
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

test "life and mana fill and drain at XP speed after their presented impact" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const h = g.heroActor().?;
    const max_mana = game.manaMax(g);
    overlay.settleResources(g);
    h.hp = @divTrunc(h.max, 2);
    g.mana = @divTrunc(max_mana, 2);
    g.mana_held = max_mana - g.mana;
    g.fx.settle(1, .{ .slot = game.heroSlot(g).?, .after = .{ .body = combat.snap(g, game.heroSlot(g).?), .mana = g.mana_held } });
    g.busy = 1;
    g.st = .{};
    game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(f32, 1), g.life_fill);
    try std.testing.expectEqual(@as(f32, 1), g.mana_fill);
    g.busy = 0;
    g.fx.step(&g.lv, 1);
    game.catchUp(g);
    const life_target = overlay.resourceFill(h.hp, h.max);
    const mana_target = overlay.resourceFill(g.mana, max_mana);
    game.update(g, harness.TEST_DT);
    try std.testing.expectApproxEqAbs(1 + (life_target - 1) * mathx.easing(harness.TEST_DT, game.XP_EASE), g.life_fill, 0.0001);
    try std.testing.expectApproxEqAbs(1 + (mana_target - 1) * mathx.easing(harness.TEST_DT, game.XP_EASE), g.mana_fill, 0.0001);
    for (0..300) |_| game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(life_target, g.life_fill);
    try std.testing.expectEqual(mana_target, g.mana_fill);
    h.hp = h.max;
    g.mana = max_mana;
    game.catchUp(g);
    game.update(g, harness.TEST_DT);
    try std.testing.expect(g.life_fill > life_target and g.life_fill < 1);
    try std.testing.expect(g.mana_fill > mana_target and g.mana_fill < 1);
    for (0..300) |_| game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(f32, 1), g.life_fill);
    try std.testing.expectEqual(@as(f32, 1), g.mana_fill);
    std.debug.print("resource fills: held until impact, exact XP easing in both directions, settle without overshoot\n", .{});
}

test "the experience bar holds a turn's experience until the turn is drawn, then fills toward it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.busy = game.GLIDE_S;
    _ = g.growth.gain(progress.xpOf(.rat) * 3);
    game.update(g, 0);
    try std.testing.expectEqual(@as(f32, 0), g.xp_shown);
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    const aim = game.xpLevels(g);
    try std.testing.expect(g.xp_shown > 0 and g.xp_shown < aim);
    var t: f32 = 0;
    while (g.xp_shown != aim and t < 1) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    std.debug.print("experience bar: {d:.3} of a level drawn {d:.2} s after the turn\n", .{ g.xp_shown, t });
    try std.testing.expect(t > 0 and t < 1);
    try std.testing.expectEqual(aim, g.xp_shown);
}

test "a level reached exactly empties the bar, and the book shows it only once the turn is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.busy = game.GLIDE_S;
    _ = g.growth.gain(@intCast(g.growth.needed()));
    g.gold += 7;
    game.update(g, 0);
    var nearby: game.NearbyBuf = undefined;
    const held = character.bookView(g, &nearby);
    try std.testing.expectEqual(@as(u16, 1), held.growth.level);
    try std.testing.expectEqual(@as(i32, 0), held.gold);
    var t: f32 = 0;
    while (g.xp_shown != game.xpLevels(g) and t < 10) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(f32, 1), g.xp_shown);
    try std.testing.expectEqual(@as(u16, 2), character.bookView(g, &nearby).growth.level);
    try std.testing.expectEqual(@as(i32, 7), character.bookView(g, &nearby).gold);
    std.debug.print("exact level-up: bar fill {d} after {d:.2} s\n", .{ g.xp_shown - @floor(g.xp_shown), t });
}

test "level-up celebrates presented progression once without holding play or replaying on load" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.clock;
    const rng = g.rng;
    const seen = g.lv.seen;
    g.busy = game.GLIDE_S;
    _ = g.growth.gain(@intCast(g.growth.needed()));
    game.update(g, 0);
    try std.testing.expectEqual(@as(f32, 0), g.fx.level_up.life);
    game.update(g, game.GLIDE_S + 0.01);
    try std.testing.expectEqual(fx.LEVEL_UP_S, g.fx.level_up.life);
    try std.testing.expect(game.quiet(g));
    game.update(g, 0.5);
    try std.testing.expectEqual(fx.LEVEL_UP_S - 0.5, g.fx.level_up.life);
    scene.effectLights(g);
    try std.testing.expectEqual(@as(usize, 1), g.light.effect_n);
    const peak_light = g.light.effects[0].source.gain;
    const glow = g.fx.level_up.bodyGlow();
    try std.testing.expect(glow[0] > glow[1] and glow[1] > glow[2] and glow[2] > 0);
    game.update(g, 1.25);
    scene.effectLights(g);
    try std.testing.expect(g.light.effects[0].source.gain < peak_light);
    try std.testing.expect(g.fx.level_up.bodyGlow()[0] < glow[0]);
    game.update(g, fx.LEVEL_UP_S);
    try std.testing.expectEqual(@as(f32, 0), g.fx.level_up.life);
    scene.effectLights(g);
    try std.testing.expectEqual(@as(usize, 0), g.light.effect_n);
    try std.testing.expectEqual([_]f32{ 0, 0, 0 }, g.fx.level_up.bodyGlow());
    _ = g.growth.gain(@intCast(g.growth.needed()));
    game.settleXp(g);
    game.update(g, 0);
    try std.testing.expectEqual(@as(f32, 0), g.fx.level_up.life);
    g.fx.levelUp();
    g.fx.clear();
    try std.testing.expectEqual(@as(f32, 0), g.fx.level_up.life);
    try std.testing.expectEqual(clock, g.clock);
    try std.testing.expectEqualDeep(rng, g.rng);
    try std.testing.expectEqualDeep(seen, g.lv.seen);
    std.debug.print("level-up: delayed, one-shot, nonblocking; gold body glow and local light fade and expire together; load suppressed and reset; clock/RNG/exploration unchanged\n", .{});
}

test "the log says the blow and the experience it awards, a juke as itself, and never a bare skill use" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    game.settle(g);
    harness.use(g, .shoot);
    harness.press(g, CONFIRM);
    try std.testing.expect(g.pool.get(2) == null);
    var buf: [64]u8 = undefined;
    const gained = try std.fmt.bufPrint(&buf, "Archer gains {d} experience.", .{progress.xpOf(.rat)});
    var said = false;
    for (0..g.log.n) |i| {
        const l = g.log.line(i).?;
        said = said or std.mem.eql(u8, l, gained);
        try std.testing.expect(std.mem.indexOf(u8, l, " uses ") == null);
    }
    try std.testing.expect(said);
    while (!game.quiet(g)) game.update(g, harness.TEST_DT);
    game.openLeap(g, shots.boundTo(g, .juke).by, .juke);
    g.mark = .{ .x = 20 + juke.RANGE, .y = 20 };
    game.confirmAim(g);
    try std.testing.expectEqualStrings("Archer jukes away.", g.log.line(0).?);
    std.debug.print("log: \"{s}\" then \"{s}\"\n", .{ gained, g.log.line(0).? });
}

test "a door is listed nearby only once no body is drawn on it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(w);
    _ = twoRooms(w);
    game.beginMapAt(g, w, w.start, 123);
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
    _ = twoRooms(w);
    game.beginMapAt(g, w, w.start, 123);
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
    const b = twoRooms(w);
    game.beginMapAt(g, w, w.start, 123);
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
    _ = twoRooms(w);
    game.beginMapAt(g, w, w.start, 123);
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
    const b = twoRooms(w);
    game.beginMapAt(g, w, w.start, 123);
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
    const b = twoRooms(w);
    game.beginMapAt(g, w, w.start, 123);
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

test "charge retreats down an empty line and passive and skill allocations spend points without turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.clock;
    g.growth = progress.State.of(.knight);
    _ = g.growth.gain(40);
    for (progress.NODES, 0..) |_, i| if (g.growth.available(i)) {
        character.characterCommand(g, .{ .passive = i });
        break;
    };
    try std.testing.expectEqual(@as(u16, 0), g.growth.passive_points);
    character.characterCommand(g, .{ .skill = .cleave });
    try std.testing.expectEqual(@as(u8, 1), g.growth.ranks.get(.cleave));
    try std.testing.expectEqual(@as(u16, 0), g.growth.active_points);
    try std.testing.expectEqual(clock, g.clock);
    harness.drawnOut(g);
    harness.use(g, .charge);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    g.mark = .{ .x = 17, .y = 20 };
    game.confirmAim(g);
    try std.testing.expectEqual(P{ .x = 17, .y = 20 }, g.heroActor().?.at);
    try std.testing.expectEqual(clock.minute + day.TURN_MINUTES, g.clock.minute);
    try std.testing.expectEqual(manaAfter(g, .charge), g.mana);
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
            const target = g.pool.get(2).?;
            harness.toughen(target);
            target.resists = .initFill(50);
            g.rng = mathx.Rng.init(seed);
            var expected_rng = g.rng;
            const raw = combat.rollRaw(&expected_rng, c[1], combat.basesFor(g, c[1]), true);
            const critical = c[0].attrs().crits(&expected_rng);
            criticals += @intFromBool(critical);
            const expected = c[0].attrs().blow(comptime c[1].defaultStyle().?, raw, critical, &expected_rng).total(target.resists);
            harness.use(g, c[1]);
            try std.testing.expectEqual(game.Mode.aim, g.mode);
            game.confirmAim(g);
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
    g.inventory.gear.slots.set(.right_hand, .{ .kind = .bow });
    g.growth.ranks.set(.shoot, 3);
    g.bar.bind(.{ .set = .primary, .button = skillbar.SLOTS[0] }, .shoot);
    var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
    var body: [overlay.TIP_BODY_MAX]u8 = undefined;
    const tip = overlay.tipOf(g, .{ .slot = 0 }, &title, &body).?;
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "Range: 9 cells") != null);
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "Physical damage: 3-8") != null);
    try std.testing.expectEqualStrings("Shoot - Rank 3", tip.title);
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
        g.inventory.gear.slots.set(.right_hand, .{ .kind = case[0] });
        g.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 70 }, null } });
        g.growth.ranks.set(act, 2);
        var expected_attrs = game.heroAttrs(g);
        expected_attrs.damage_bonus.getPtr(style).* += g.growth.damageBonus(act);
        try std.testing.expectEqualDeep(expected_attrs, combat.blowFor(g, act).by);
        const raw = damage.Damage{ .physical = 100 };
        g.rng = mathx.Rng.init(0xDA6);
        var expected_rng = g.rng;
        const critical = expected_attrs.crits(&expected_rng);
        const expected = expected_attrs.blow(style, raw, critical, &expected_rng);
        try std.testing.expectEqualDeep(expected, combat.heroScaled(g, act, raw).blow);
        g.bar.bind(.{ .set = .primary, .button = skillbar.SLOTS[0] }, act);
        var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
        var body: [overlay.TIP_BODY_MAX]u8 = undefined;
        const tip = overlay.tipOf(g, .{ .slot = 0 }, &title, &body).?;
        const scaling_label = comptime "Scales with " ++ menu.named(case[2].attr());
        try std.testing.expect(std.mem.indexOf(u8, tip.body, scaling_label) != null);
        const span = expected_attrs.span(style, combat.basesFor(g, act).physical());
        var wanted: [64]u8 = undefined;
        try std.testing.expect(std.mem.indexOf(u8, tip.body, try std.fmt.bufPrint(&wanted, "Physical damage: {d}-{d}", .{ span.lo, span.hi })) != null);
        if (act == .cleave) {
            g.rng = mathx.Rng.init(0xDA6);
            expected_rng = g.rng;
            const by = game.heroAttrs(g);
            const crit = by.crits(&expected_rng);
            try std.testing.expectEqual(by.blow(style, raw, crit, &expected_rng).physical, combat.heroRoll(g, .melee, 100).dmg);
        }
    }
    for ([_]items.Kind{ .wand, .staff }) |kind| {
        var gear = items.Gear{};
        gear.slots.set(.right_hand, .{ .kind = kind });
        inline for ([_]skillbar.Act{ .shoot, .cleave, .spark }) |act| {
            try std.testing.expectEqualDeep(combat.basesOf(&.{}, act), combat.basesOf(&gear, act));
        }
    }
    std.debug.print("weapon scaling: 5 ranged/melee skill and tooltip cases, 2 bump attacks, 6 zero-innate-damage checks\n", .{});
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
                const h = g.heroActor().?;
                if (warded) h.ward.raise();
                const hp = h.hp;
                const clock = g.clock;
                g.rng = harness.bitesRng(g, .pib, &.{!dodged});
                harness.use(g, .wait);
                try std.testing.expect(!std.meta.eql(clock, g.clock));
                if (dodged) {
                    try std.testing.expectEqual(hp, h.hp);
                    try std.testing.expectEqual(game.manaMax(g), g.mana);
                    try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
                } else if (warded) {
                    try std.testing.expectEqual(hp, h.hp);
                    try std.testing.expect(g.mana < game.manaMax(g));
                } else try std.testing.expect(h.hp < hp);
                g.st = .{};
                game.update(g, harness.TEST_DT);
                try std.testing.expect(g.busy > 0);
                harness.drawnOut(g);
                try std.testing.expectEqual(h.hp, g.pictured[game.heroSlot(g).?].hp);
                try std.testing.expectEqual(g.mana, game.manaShown(g));
                if (dodged) try std.testing.expectEqual(@as(f32, 0), g.fx.flashOf(game.heroSlot(g).?));
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
    try std.testing.expectEqual(actor.Kind.wizard, g.heroActor().?.kind);
    const rat = g.pool.get(2).?;
    rat.awake = true;
    harness.toughen(rat);
    for (0..2) |_| {
        harness.press(g, .x);
        try std.testing.expectEqual(game.Mode.aim, g.mode);
        g.rng = harness.procRng(g, .spark, 1, true);
        harness.press(g, CONFIRM);
        harness.drawnOut(g);
    }
    const dealt = harness.TEST_HP - rat.hp;
    try harness.expectDamage(g, .spark, dealt, &.{ spark.BASE, spark.BASE });
    try std.testing.expectEqual(@as(i32, 26), rat.at.x);
    try std.testing.expectEqual(game.manaMax(g) - 2 * (spark.COST - heroes.MANA_REGEN), g.mana);
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
        const rat = g.pool.get(2).?;
        rat.awake = true;
        harness.toughen(rat);
        const hp = g.heroActor().?.hp;
        harness.press(g, .a);
        try std.testing.expectEqual(game.Mode.aim, g.mode);
        try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mark);
        g.rng = harness.procRng(g, .shield_bash, 1, stuns);
        harness.press(g, CONFIRM);
        const dealt = harness.TEST_HP - rat.hp;
        try harness.expectDamage(g, .shield_bash, dealt, &.{bash.BASE});
        try std.testing.expectEqual(hp, g.heroActor().?.hp);
        try std.testing.expectEqual(manaAfter(g, .shield_bash), g.mana);
        try std.testing.expectEqual(bash.COOLDOWN - 1, g.cooldown.get(.shield_bash));
        x.* = rat.at.x;
        harness.drawnOut(g);
        try std.testing.expect(harness.samePx(game.cellPx(rat.at), g.glide[actor.Pool.slot(2)].now()));
    }
    try std.testing.expectEqual(@as(i32, 22), landed[0]);
    try std.testing.expectEqual(@as(i32, 21), landed[1]);
    harness.heroArena(g, .knight, from, &.{.{ .x = 21, .y = 20 }});
    g.lv.set(.{ .x = 22, .y = 20 }, .wall);
    harness.press(g, .a);
    g.rng = harness.procRng(g, .shield_bash, 1, true);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.pool.get(2).?.at);
    std.debug.print("shield bash: stunned rat ends the turn at x {d}, unstunned steps back to x {d}; against a wall it stays\n", .{ landed[0], landed[1] });
}

test "a foe knocked back and stepping in again is drawn on its cell until the bash lands, then knocked the whole tile" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{at});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    harness.toughen(rat);
    harness.press(g, .a);
    g.rng = harness.procRng(g, .shield_bash, 1, false);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(@as(i32, 21), rat.at.x);
    const gl = &g.glide[actor.Pool.slot(2)];
    try std.testing.expect(harness.samePx(game.cellPx(at), gl.now()));
    var held: f32 = 0;
    var furthest: f32 = 0;
    var t: f32 = 0;
    while (t < 2 and g.busy > 0) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (harness.samePx(game.cellPx(at), gl.now())) held = t + harness.TEST_DT;
        furthest = @max(furthest, gl.now().x);
    }
    std.debug.print("knocked rat: still on its cell {d:.3} s in (the bash lands at {d:.3}), knocked to x {d:.1} px of {d}\n", .{ held, game.BUMP_LANDS, furthest, game.cellPx(at.add(.{ .x = 1, .y = 0 })).x });
    try std.testing.expect(held + harness.TEST_TOL >= game.BUMP_LANDS);
    try std.testing.expect(furthest > game.cellPx(at.add(.{ .x = 1, .y = 0 })).x - 1);
}

test "a cleave strikes only the bodies in its arc as it is swung, not a half split into it by the same swing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const slime = P{ .x = 21, .y = 19 };
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{});
    for ([_]P{ .{ .x = 20, .y = 18 }, .{ .x = 21, .y = 18 }, .{ .x = 22, .y = 18 }, .{ .x = 20, .y = 19 }, .{ .x = 22, .y = 19 }, .{ .x = 22, .y = 20 } }) |w| g.lv.set(w, .wall);
    const id = harness.spawnAt(g, .slime, slime, false);
    g.pool.get(id).?.hp = @divTrunc(actor.row(.slime).hp, 2);
    harness.press(g, .x);
    harness.nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mark);
    harness.press(g, CONFIRM);
    var slimes: usize = 0;
    for (g.pool.slice()) |a| {
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
    harness.press(g, .x);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    harness.nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.mark);
    harness.press(g, CONFIRM);
    var hit: usize = 0;
    for (g.pool.slice()[1..], 0..) |a, i| {
        const lost = harness.TEST_HP - a.hp;
        if (i < arc.len) {
            try harness.expectDamage(g, .cleave, lost, &.{cleave.BASE});
            hit += 1;
        } else try std.testing.expectEqual(@as(i32, 0), lost);
    }
    try std.testing.expectEqual(manaAfter(g, .cleave), g.mana);
    std.debug.print("cleave: {d} of {d} rats struck, the {d} outside its arc untouched\n", .{ hit, arc.len + outside.len, outside.len });
}

test "a wizard's blink lands further than juke and takes a turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.heroArena(g, .wizard, from, &.{.{ .x = 30, .y = 20 }});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    const hour = g.clock;
    harness.press(g, .b);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    for (0..blink.RANGE + 1) |_| harness.nudge(g, .e);
    try std.testing.expectEqual(P{ .x = 20 + blink.RANGE, .y = 20 }, g.mark);
    harness.press(g, CONFIRM);
    try std.testing.expectEqual(g.mark, g.heroActor().?.at);
    try std.testing.expect(g.glide[actor.Pool.slot(2)].t <= -game.STAGGER_S + harness.TEST_TOL);
    try std.testing.expect(!std.meta.eql(hour, g.clock));
    try std.testing.expectEqual(@as(i32, 29), rat.at.x);
    try std.testing.expectEqual(manaAfter(g, .blink), g.mana);
    try std.testing.expectEqual(blink.COOLDOWN - 1, g.cooldown.get(.blink));
    std.debug.print("blink: {d} tiles in a turn; the rat stepped once\n", .{blink.RANGE});
}

test "a flask drink takes a turn, recovers over the next turns, and kills refill its charges" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const h = g.heroActor().?;
    h.hp = 1;
    g.mana = 0;
    const hour = g.clock;
    harness.press(g, .rb);
    try std.testing.expect(!std.meta.eql(hour, g.clock));
    const per = firstLifeTick(h.max);
    try std.testing.expectEqual(1 + per, h.hp);
    for (1..flask.TURNS) |_| harness.use(g, .wait);
    try std.testing.expectEqual(1 + flask.lifeOf(h.max, 0), h.hp);
    harness.press(g, .rt);
    for (1..flask.TURNS + 2) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@min(game.manaMax(g), flask.MANA_GAIN + heroes.MANA_REGEN * (flask.TURNS + flask.TURNS + 2)), g.mana);
    harness.press(g, .rb);
    harness.press(g, .rb);
    try std.testing.expectEqual(@as(u8, 0), g.flasks.get(.life).uses());
    const hp = h.hp;
    harness.press(g, .rb);
    try std.testing.expectEqual(hp, h.hp);
    try std.testing.expectEqual(@as(u8, 0), g.flasks.get(.life).uses());
    for (0..flask.USE / flask.PER_KILL) |_| combat.fell(g, 2);
    try std.testing.expectEqual(@as(u8, 1), g.flasks.get(.life).uses());
    std.debug.print("life flask: {d} hp over {d} turns on a knight of {d}; empty after {d} drinks; {d} kills refill one\n", .{ flask.lifeOf(h.max, 0), flask.TURNS, h.max, flask.CHARGES / flask.USE, flask.USE / flask.PER_KILL });
}

fn firstLifeTick(max: i32) i32 {
    var f = flask.Flask{};
    f.drink(flask.lifeOf(max, 0));
    return f.tick();
}

test "a flask's heal shows at the turn's end, before a bite that turn lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    const h = g.heroActor().?;
    h.hp = 10;
    game.catchUp(g);
    const hero = game.heroSlot(g).?;
    harness.press(g, .rb);
    const healed = 10 + firstLifeTick(h.max);
    try std.testing.expect(h.hp < healed);
    var first: ?i32 = null;
    g.st = .{};
    var t: f32 = 0;
    while (t < 1) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (first == null and g.pictured[hero].hp != 10) first = g.pictured[hero].hp;
    }
    std.debug.print("flask heal under a bite: drawn {d} -> {?d} -> {d}\n", .{ 10, first, g.pictured[hero].hp });
    try std.testing.expectEqual(@as(?i32, healed), first);
    try std.testing.expectEqual(h.hp, g.pictured[hero].hp);
}

fn takeNode(g: *game.Game, name: []const u8) void {
    for (progress.NODES, 0..) |n, i| if (std.mem.eql(u8, n.name, name)) return g.growth.nodes.set(i);
    unreachable;
}

fn takeCull(g: *game.Game) void {
    takeNode(g, "Culling Blow");
    takeNode(g, "Executioner");
}

fn caughtUp(g: *game.Game, slot: usize) bool {
    return g.pictured[slot].hp == g.pool.items[slot].hp;
}

test "passive leech and kill healing land on the drawn hero with the arrow" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    takeNode(g, "Sanguine Pact");
    takeNode(g, "Red Harvest");
    const h = g.heroActor().?;
    h.hp = 5;
    g.pool.get(2).?.hp = 1;
    game.catchUp(g);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expect(g.pool.get(2) == null);
    try std.testing.expectEqual(@as(i32, 5 + 1 + 2), h.hp);
    const hero = game.heroSlot(g).?;
    try std.testing.expectEqual(@as(i32, 5), g.pictured[hero].hp);
    const t = harness.framesUntil(g, hero, caughtUp);
    std.debug.print("leech 1 + kill heal 2: drawn hero 5 -> 8 at {d:.3} s, as the arrow lands at {d:.3} s\n", .{ t, game.flown(6) });
    try std.testing.expectApproxEqAbs(game.flown(6), t, harness.TEST_TOL);
}

test "passive cull finishes a foe left at its threshold and spares one above it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 22, .y = 20 }, .{ .x = 22, .y = 22 } });
    takeCull(g);
    try std.testing.expectEqual(@as(i32, 10), g.growth.perks().cull);
    for ([_]u16{ 2, 3 }) |id| harness.setLife(g.pool.get(id).?, 20, 20);
    const from = g.heroActor().?.at;
    combat.wound(g, 2, .{ .dmg = 18 }, combat.SHOOT, .{ .from = from, .wait = 0 });
    combat.wound(g, 3, .{ .dmg = 17 }, combat.SHOOT, .{ .from = from, .wait = 0 });
    try std.testing.expect(g.pool.get(2) == null);
    try std.testing.expectEqual(@as(i32, 3), g.pool.get(3).?.hp);
    std.debug.print("cull 10%: a 20-life foe left at 2 is cut down, one left at 3 survives\n", .{});
}

test "a culled foe is not said to take the arrow's status" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    takeCull(g);
    harness.setLife(g.pool.get(2).?, 3, 20);
    combat.arrowHit(g, 2, .{ .blow = .{ .physical = 1 } }, .pinning_shot, .{ .from = g.heroActor().?.at, .wait = 0 });
    try std.testing.expect(g.pool.get(2) == null);
    for (0..g.log.n) |i| try std.testing.expect(std.mem.indexOf(u8, g.log.line(i).?, pinning.TAKES) == null);
}

test "passive leech waits for the arrow while a life flask recovers" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    takeNode(g, "Sanguine Pact");
    const h = g.heroActor().?;
    h.hp = 5;
    harness.setLife(g.pool.get(2).?, 50, 50);
    harness.press(g, .rb);
    game.catchUp(g);
    const hero = game.heroSlot(g).?;
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expect(g.pool.get(2) != null);
    const t = harness.framesUntil(g, hero, caughtUp);
    std.debug.print("leech under a ticking flask: drawn hero reaches {d} at {d:.3} s, as the arrow lands at {d:.3} s\n", .{ h.hp, t, game.flown(6) });
    try std.testing.expectApproxEqAbs(game.flown(6), t, harness.TEST_TOL);
}

test "passive mana recovery, skill cost and flask recovery reach the live numbers" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const cost = g.growth.cost(.charge);
    takeNode(g, "Slow Tide");
    takeNode(g, "Attuned");
    takeNode(g, "Scar Tissue");
    try std.testing.expectEqual(mathx.percentOf(charge.COST, 90), g.growth.cost(.charge));
    g.mana = 0;
    harness.use(g, .wait);
    try std.testing.expectEqual(heroes.MANA_REGEN + 1, g.mana);
    const h = g.heroActor().?;
    h.hp = 1;
    harness.press(g, .rb);
    for (1..flask.TURNS) |_| harness.use(g, .wait);
    const healed = flask.lifeOf(h.max, 20);
    try std.testing.expectEqual(1 + healed, h.hp);
    var desc: [256]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, overlay.describe(g, .life_flask, &desc), "Recover 60% of life") != null);
    std.debug.print("passives: mana {d}/turn, charge {d} -> {d} mana, life flask {d} -> {d} on {d} life\n", .{ game.manaRegen(g), cost, g.growth.cost(.charge), flask.lifeOf(h.max, 0), healed, h.max });
}

test "a kill's flask refill shows as the kill is drawn, not as the arrow leaves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    g.flasks.getPtr(.life).charges = flask.USE - flask.PER_KILL;
    game.catchUp(g);
    harness.press(g, .x);
    harness.press(g, CONFIRM);
    try std.testing.expect(g.pool.get(2) == null);
    try std.testing.expectEqual(@as(u8, 1), g.flasks.get(.life).uses());
    try std.testing.expectEqual(@as(u8, 0), g.flasks_shown.get(.life).uses());
    const Refilled = struct {
        fn f(gm: *game.Game, _: usize) bool {
            return gm.flasks_shown.get(.life).uses() == 1;
        }
    };
    const t = harness.framesUntil(g, 0, Refilled.f);
    std.debug.print("a kill 7 cells out refills the drawn flask {d:.3} s in, as the arrow lands at {d:.3} s\n", .{ t, game.flown(6) });
    try std.testing.expectApproxEqAbs(game.flown(6), t, harness.TEST_TOL);
}

fn manaAfter(g: *const game.Game, act: skillbar.Act) i32 {
    return game.manaMax(g) - g.growth.cost(act) + game.manaRegen(g);
}

fn skipsNext(a: *actor.Actor) void {
    a.chill = .{ .turns = 1, .phase = glacial.CYCLE - 1 };
}

fn bleedingNow(a: *actor.Actor) void {
    a.bleed.start();
    a.bleed.fresh = false;
}

test "a pinning shot holds a chasing rat to its cell for two to four of its turns, and a pinned rat still bites" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const rat = g.pool.get(2).?;
    rat.awake = true;
    harness.toughen(rat);
    harness.pressHolding(g, .a, &.{.lb});
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    harness.pressHolding(g, .a, &.{.lb});
    const dealt = harness.TEST_HP - rat.hp;
    try harness.expectDamage(g, .pinning_shot, dealt, &.{bow.BASE});
    try std.testing.expectEqual(manaAfter(g, .pinning_shot), g.mana);
    var held: usize = 1;
    while (rat.at.x == 26 and held < 10) {
        harness.use(g, .wait);
        if (rat.at.x == 26) held += 1;
    }
    try harness.expectWithin(held, pinning.TURNS_LO, pinning.TURNS_HI);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    const biter = g.pool.get(2).?;
    biter.awake = true;
    biter.pin.turns = pinning.TURNS_HI;
    const hp = g.heroActor().?.hp;
    g.rng = harness.bitesRng(g, .rat, &.{true});
    harness.use(g, .wait);
    try std.testing.expect(g.heroActor().?.hp < hp);
    try std.testing.expectEqual(@as(i32, 21), biter.at.x);
    std.debug.print("pinning shot: {d} damage, the rat held {d} turns, then walked on; pinned beside the hero it bit for {d}\n", .{ dealt, held, hp - g.heroActor().?.hp });
}

test "a barbed arrow always opens a bleed on a body it leaves alive" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    const rat = g.pool.get(2).?;
    harness.toughen(rat);
    harness.pressHolding(g, .b, &.{.lb});
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    harness.press(g, CONFIRM);
    const dealt = harness.TEST_HP - rat.hp;
    try harness.expectDamage(g, .barbed_arrow, dealt, &.{bow.BASE});
    try std.testing.expectEqual(bleeding.TURNS, rat.bleed.turns);
    try std.testing.expectEqual(manaAfter(g, .barbed_arrow), g.mana);
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
        g.rng = mathx.Rng.init(seed);
        harness.pressHolding(g, .a, &.{.lb});
        const near = harness.TEST_HP - g.pool.get(2).?.hp;
        const off = harness.TEST_HP - g.pool.get(3).?.hp;
        try harness.expectDamage(g, .frost_nova, near, &.{nova.BASE});
        try harness.expectDamage(g, .frost_nova, off, &.{nova.BASE});
        apart += @intFromBool(near != off);
        try std.testing.expectEqual(harness.TEST_HP, g.pool.get(4).?.hp);
        try std.testing.expectEqual(manaAfter(g, .frost_nova), g.mana);
        try std.testing.expectEqual(nova.COOLDOWN - 1, g.cooldown.get(.frost_nova));
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
    g.pool.get(2).?.hp = 1;
    const id = splittable(g, at, false);
    var ring = grid.Box.around(at, 1).cells();
    while (ring.next()) |p| {
        if (!p.eq(at) and !p.eq(cell)) g.lv.set(p, .wall);
    }
    game.settle(g);
    harness.pressHolding(g, .a, &.{.lb});
    const dying = actor.Pool.slot(2);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(!g.pool.items[dying].alive);
    try std.testing.expect(g.pool.items[half].at.eq(cell));
    var overlap: f32 = 0;
    var t: f32 = 0;
    g.st = .{};
    while (t < 1) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (game.standing(g, dying) and harness.drawn(g, half) and g.glide[half].done() > 0) overlap += harness.TEST_DT;
    }
    std.debug.print("a half split into a dying rat's cell: {d:.3} s drawn together\n", .{overlap});
    try std.testing.expect(overlap <= harness.TEST_TOL);
    try std.testing.expect(g.glide[half].done() >= 1);
}

test "a fireball bursts on the first foe it strikes, burning the foes round it, and none past its blast" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 26, .y = 20 }, .{ .x = 27, .y = 21 }, .{ .x = 29, .y = 20 } });
    harness.toughenFoes(g);
    harness.press(g, .a);
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    harness.press(g, .a);
    const struck = harness.TEST_HP - g.pool.get(2).?.hp;
    try harness.expectDamage(g, .fireball, struck, &.{fireball.BASE});
    try harness.expectDamage(g, .fireball, harness.TEST_HP - g.pool.get(3).?.hp, &.{fireball.BASE});
    try std.testing.expectEqual(harness.TEST_HP, g.pool.get(4).?.hp);
    try std.testing.expectEqual(manaAfter(g, .fireball), g.mana);
    std.debug.print("fireball: {d} fire to the struck rat, {d} to the one beside it, none to the rat 3 tiles on\n", .{ struck, harness.TEST_HP - g.pool.get(3).?.hp });
}

test "chain lightning leaps from the struck foe to two more, each within three tiles of the last" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 26, .y = 21 }, .{ .x = 29, .y = 21 }, .{ .x = 25, .y = 25 } });
    harness.toughenFoes(g);
    harness.pressHolding(g, .x, &.{.lb});
    try std.testing.expectEqual(game.Mode.aim, g.mode);
    harness.press(g, CONFIRM);
    var hit: usize = 0;
    for ([_]u16{ 2, 3, 4 }) |id| {
        const dealt = harness.TEST_HP - g.pool.get(id).?.hp;
        try harness.expectDamage(g, .chain_lightning, dealt, &.{chain.BASE});
        hit += 1;
    }
    try std.testing.expectEqual(harness.TEST_HP, g.pool.get(5).?.hp);
    try std.testing.expectEqual(manaAfter(g, .chain_lightning), g.mana);
    std.debug.print("chain lightning: {d} rats struck, the fourth 4 tiles from each left whole\n", .{hit});
}

test "resisted chain lightning still holds play until its last jump" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 26, .y = 21 }, .{ .x = 29, .y = 21 } });
    for (g.pool.slice()[1..]) |*a| a.resists.set(.lightning, 100);
    harness.pressHolding(g, .x, &.{.lb});
    harness.press(g, CONFIRM);
    const last = game.flown(g.shot.?.flight.len - 1) + chain.JUMPS * game.ZAP_S;
    try std.testing.expect(g.busy >= last);
    g.st = .{ .pressed = .initOne(.y) };
    const before = g.clock;
    game.update(g, last - game.ZAP_S / 2);
    try std.testing.expectEqual(before, g.clock);
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(usize, 0), g.fx.due_n);
    std.debug.print("resisted chain lightning: {d} jumps hold play for {d:.3} s\n", .{ chain.JUMPS, last });
}

test "a mana shield turns a bite onto mana, the orb dropping as the bite lands, until its turns run out" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    g.pool.get(2).?.awake = true;
    const h = g.heroActor().?;
    const hp = h.hp;
    g.rng = harness.bitesRng(g, .rat, &.{true});
    harness.pressHolding(g, .b, &.{.lb});
    const after_cast = manaAfter(g, .mana_shield);
    const bitten = after_cast - g.mana;
    try std.testing.expectEqual(hp, h.hp);
    try harness.expectWithin(bitten, 1, 3);
    try std.testing.expectEqual(ward.TURNS - 1, h.ward.turns);
    try std.testing.expectEqual(after_cast, g.mana + g.mana_held);
    g.st = .{};
    game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(ward.TURNS, g.pictured[game.heroSlot(g).?].status.get(.warded));
    try std.testing.expect(g.mana_held > 0);
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(i32, 0), g.mana_held);
    for (1..ward.TURNS) |_| harness.use(g, .wait);
    try std.testing.expectEqual(hp, h.hp);
    try std.testing.expectEqual(@as(u8, 0), h.ward.turns);
    g.rng = harness.bitesRng(g, .rat, &.{true});
    harness.use(g, .wait);
    try std.testing.expect(h.hp < hp);
    std.debug.print("mana shield: a bite of {d} taken from mana, the orb holding till it landed; {d} turns, then the bites drew blood\n", .{ bitten, ward.TURNS });
}

test "mana shield deductions follow each staggered hit" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 20, .y = 21 } });
    harness.wakeFoes(g);
    g.rng = harness.bitesRng(g, .rat, &.{ true, true });
    harness.pressHolding(g, .b, &.{.lb});
    const before = manaAfter(g, .mana_shield);
    try std.testing.expectEqual(before, g.mana + g.mana_held);
    g.st = .{};
    game.update(g, game.BUMP_LANDS + game.STAGGER_S * 1.5);
    const between = g.mana + g.mana_held;
    try std.testing.expect(between < before);
    try std.testing.expect(between > g.mana);
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(i32, 0), g.mana_held);
    std.debug.print("mana shield: shown mana {d}, {d}, {d} across two hits\n", .{ before, between, g.mana });
}

test "a mana shield's last turn stays drawn until the foes' moves of that turn are" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    harness.wakeFoes(g);
    const h = g.heroActor().?;
    h.ward.turns = 1;
    g.st = .{};
    game.update(g, harness.TEST_DT);
    const hero = game.heroSlot(g).?;
    try std.testing.expectEqual(@as(u8, 1), g.pictured[hero].status.get(.warded));
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 1), mathx.dist(g.pool.get(2).?.at, h.at));
    try std.testing.expectEqual(@as(u8, 0), h.ward.turns);
    try std.testing.expect(g.busy > 0);
    try std.testing.expectEqual(@as(u8, 1), g.pictured[hero].status.get(.warded));
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(u8, 0), g.pictured[hero].status.get(.warded));
    std.debug.print("mana shield: last turn drawn through the rat's step, gone after\n", .{});
}

test "a charge runs the knight down a line to the foe, striking it and knocking it back, but a pinned foe stands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var stood: [2]i32 = undefined;
    for ([_]bool{ false, true }, &stood) |pinned, *x| {
        harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
        const rat = g.pool.get(2).?;
        harness.toughen(rat);
        skipsNext(rat);
        if (pinned) rat.pin.turns = pinning.TURNS_HI;
        harness.press(g, .b);
        try std.testing.expectEqual(game.Mode.aim, g.mode);
        try std.testing.expectEqual(P{ .x = 23, .y = 20 }, g.mark);
        harness.press(g, .a);
        try std.testing.expectEqual(P{ .x = 22, .y = 20 }, g.heroActor().?.at);
        const dealt = harness.TEST_HP - rat.hp;
        try harness.expectDamage(g, .charge, dealt, &.{charge.BASE});
        try std.testing.expectEqual(manaAfter(g, .charge), g.mana);
        try std.testing.expectEqual(charge.COOLDOWN - 1, g.cooldown.get(.charge));
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
    const rat = g.pool.get(2).?;
    harness.toughen(rat);
    skipsNext(rat);
    bleedingNow(rat);
    harness.press(g, .b);
    harness.press(g, .a);
    const i = actor.Pool.slot(2);
    try std.testing.expectEqual(@as(i32, 24), rat.at.x);
    const bled = rat.hp;
    g.st = .{};
    var t: f32 = 0;
    while (g.pictured[i].hp != bled and t < 2) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(bled, g.pictured[i].hp);
    try std.testing.expect(g.glide[i].left() <= harness.TEST_TOL);
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
            g.rng = mathx.Rng.init(17);
            const rat = g.pool.get(2).?;
            harness.toughen(rat);
            skipsNext(rat);
            if (pinned) rat.pin.turns = pinning.TURNS_HI;
            if (bleeds) bleedingNow(rat);
            harness.press(g, .b);
            harness.press(g, .a);
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

test "inspect walks the orbs, the slots and the statuses, spends no turn, and backs out by any way back or its own button" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    g.heroActor().?.bleed.turns = bleeding.TURNS;
    game.catchUp(g);
    const clock = g.clock;
    harness.press(g, skillbar.INSPECT);
    try std.testing.expectEqual(game.Mode.inspect, g.mode);
    g.inspecting = .life;
    var walked: usize = 0;
    while (g.inspecting != .mana and walked < 20) : (walked += 1) harness.nudge(g, .e);
    try std.testing.expectEqual(skillbar.SLOTS.len + 1, walked);
    harness.nudge(g, .e);
    try std.testing.expectEqual(game.Spot.mana, g.inspecting);
    g.inspecting = .{ .slot = 3 };
    harness.nudge(g, .n);
    try std.testing.expectEqual(game.Spot{ .status = .bleeding }, g.inspecting);
    harness.nudge(g, .s);
    try std.testing.expect(g.inspecting == .slot);
    for ([_]input.Button{ menu.BACK, menu.PAUSE, skillbar.INSPECT }) |out| {
        harness.press(g, out);
        try std.testing.expectEqual(game.Mode.play, g.mode);
        harness.press(g, skillbar.INSPECT);
        try std.testing.expectEqual(game.Mode.inspect, g.mode);
    }
    harness.press(g, skillbar.INSPECT);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expect(std.meta.eql(clock, g.clock));
    std.debug.print("inspect: life to mana in {d} steps across {d} slots, up to a status and down again; 3 ways out, no turn spent\n", .{ walked, skillbar.SLOTS.len });
}

test "the mouse over an orb, a slot or a status shows its tooltip while playing, and nothing off the hud" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    g.heroActor().?.bleed.turns = bleeding.TURNS;
    game.catchUp(g);
    var buf: [overlay.SPOTS_MAX]overlay.Part = undefined;
    const spots = overlay.spotsOf(g, &buf);
    for (spots) |s| {
        g.st.pointer = look.middleAt(s.box);
        try std.testing.expectEqual(s.spot, overlay.hovered(g).?.spot);
    }
    const orb = hud.orbBox(overlay.hudLayout(g).life);
    g.st.pointer = .{ .x = @intFromFloat(orb.x + 1), .y = @intFromFloat(orb.y + 1) };
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    g.st.pointer = .{ .x = 0, .y = 0 };
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    g.st.pointer = null;
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    g.st.pointer = look.middleAt(spots[1].box);
    g.mode = .pause;
    try std.testing.expectEqual(@as(?overlay.Part, null), overlay.hovered(g));
    std.debug.print("hover: {d} hud parts each found at their centre; the orb's corner, the screen's, no mouse and pause show none\n", .{spots.len});
}
