const std = @import("std");
const progress = @import("../../play/progress.zig");
const mathx = @import("../../core/mathx.zig");
const hud = @import("../../ui/hud.zig");
const book = @import("../../ui/book.zig");
const heroes = @import("../../play/hero.zig");
const juke = @import("../../play/juke.zig");
const pinning = @import("../../play/pinning.zig");
const charge = @import("../../play/charge.zig");
const flask = @import("../../play/flask.zig");
const skillbar = @import("../../play/skillbar.zig");
const light = @import("../../gfx/light.zig");
const fx = @import("../../gfx/fx.zig");
const scene = @import("../scene.zig");
const overlay = @import("../overlay.zig");
const character = @import("../character.zig");
const combat = @import("../combat.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const skills = @import("../skills.zig");

fn firstLifeTick(max: i32) i32 {
    var f = flask.Flask{};
    f.drink(flask.lifeOf(max, 0));
    return f.tick();
}

fn takeNode(g: *game.Game, name: []const u8) void {
    for (progress.NODES, 0..) |n, i| if (std.mem.eql(u8, n.name, name)) return g.growth.nodes.set(i);
    unreachable;
}

fn takeCull(g: *game.Game) void {
    takeNode(g, "Culling Blow");
    takeNode(g, "Executioner");
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
    const life_target = hud.fillOf(h.hp, h.max);
    const mana_target = hud.fillOf(g.mana, max_mana);
    game.update(g, harness.TEST_DT);
    try std.testing.expectApproxEqAbs(1 + (life_target - 1) * mathx.easing(harness.TEST_DT, game.RESOURCE_EASE), g.life_fill, 0.0001);
    try std.testing.expectApproxEqAbs(1 + (mana_target - 1) * mathx.easing(harness.TEST_DT, game.RESOURCE_EASE), g.mana_fill, 0.0001);
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
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.pool.get(2) == null);
    var buf: [64]u8 = undefined;
    const gained = try std.fmt.bufPrint(&buf, "Archer gains {d} experience.", .{progress.xpOf(.rat)});
    try std.testing.expect(harness.logged(g, gained));
    try std.testing.expect(!harness.logged(g, " uses "));
    while (!game.quiet(g)) game.update(g, harness.TEST_DT);
    skills.openLeap(g, harness.boundTo(g, .juke).by, .juke);
    g.mark = .{ .x = 20 + juke.RANGE, .y = 20 };
    skills.confirmAim(g);
    try std.testing.expectEqualStrings("Archer jukes away.", g.log.line(0).?);
    std.debug.print("log: \"{s}\" then \"{s}\"\n", .{ gained, g.log.line(0).? });
}

test "a flask drink is free, recovers immediately and over later turns, and kills refill its charges" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const h = g.heroActor().?;
    h.hp = 1;
    g.mana = 0;
    const hour = g.clock;
    harness.use(g, .life_flask);
    try std.testing.expectEqual(hour, g.clock);
    const per = firstLifeTick(h.max);
    try std.testing.expectEqual(1 + per, h.hp);
    for (1..flask.TURNS) |_| harness.use(g, .wait);
    try std.testing.expectEqual(1 + flask.lifeOf(h.max, 0), h.hp);
    harness.use(g, .mana_flask);
    for (1..flask.TURNS + 2) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@min(game.manaMax(g), flask.MANA_GAIN + @divTrunc(heroes.MANA_REGEN * (flask.TURNS * 2), heroes.MANA_REGEN_TURNS)), g.mana);
    harness.use(g, .life_flask);
    harness.use(g, .life_flask);
    try std.testing.expectEqual(@as(u8, 0), g.flasks.get(.life).uses());
    const hp = h.hp;
    harness.use(g, .life_flask);
    try std.testing.expectEqual(hp, h.hp);
    try std.testing.expectEqual(@as(u8, 0), g.flasks.get(.life).uses());
    for (0..flask.USE / flask.PER_KILL) |_| combat.fell(g, 2);
    try std.testing.expectEqual(@as(u8, 1), g.flasks.get(.life).uses());
    std.debug.print("life flask: {d} hp over {d} ticks on a knight of {d}; empty after {d} drinks; {d} kills refill one\n", .{ flask.lifeOf(h.max, 0), flask.TURNS, h.max, flask.CHARGES / flask.USE, flask.USE / flask.PER_KILL });
}

test "both flask sips leave foes ailments cooldowns regeneration and the other flask untouched" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]skillbar.Act{ .life_flask, .mana_flask }) |act| {
        harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
        harness.wakeFoes(g);
        const h = g.heroActor().?;
        h.hp = 1;
        h.burn = .{ .turns = 2 };
        g.mana = 0;
        g.mana_recovery = heroes.MANA_REGEN_TURNS - 1;
        g.cooldown.set(.charge, 2);
        const kind = act.flaskOf().?;
        const other: flask.Kind = if (kind == .life) .mana else .life;
        g.flasks.getPtr(other).drink(9);
        const other_before = g.flasks.get(other);
        const foe = g.pool.get(2).?.*;
        const clock = g.clock;
        const rng = g.rng;
        g.unsaved = false;
        game.catchUp(g);
        harness.use(g, act);
        try std.testing.expect(g.unsaved);
        try std.testing.expectEqual(clock, g.clock);
        try std.testing.expectEqualDeep(foe, g.pool.get(2).?.*);
        try std.testing.expectEqual(rng, g.rng);
        try std.testing.expectEqual(@as(u8, 2), h.burn.turns);
        try std.testing.expectEqual(@as(u8, 2), g.cooldown.get(.charge));
        try std.testing.expectEqual(heroes.MANA_REGEN_TURNS - 1, g.mana_recovery);
        try std.testing.expectEqual(other_before, g.flasks.get(other));
        try std.testing.expectEqual(@as(u8, 0), act.turns());
        try std.testing.expectEqual(flask.TURNS - 1, g.flasks.get(kind).turns);
        try std.testing.expectEqual(flask.CHARGES / flask.USE - 1, g.flasks.get(kind).uses());
        try std.testing.expectEqual(if (kind == .life) 1 + firstLifeTick(h.max) else @as(i32, 1), h.hp);
        try std.testing.expectEqual(if (kind == .mana) try std.math.divCeil(i32, flask.MANA_GAIN, flask.TURNS) else @as(i32, 0), g.mana);
        try std.testing.expectEqual(h.hp, g.pictured[game.heroSlot(g).?].hp);
        var description: [256]u8 = undefined;
        try std.testing.expect(std.mem.indexOf(u8, overlay.describe(g, act, &description), "no turn cost") != null);
        const recovering = g.flasks;
        const hp = h.hp;
        const mana = g.mana;
        g.st = .{};
        game.update(g, 1);
        try std.testing.expectEqualDeep(recovering, g.flasks);
        try std.testing.expectEqual(hp, h.hp);
        try std.testing.expectEqual(mana, g.mana);
        try std.testing.expectEqual(clock, g.clock);
    }
    std.debug.print("2 flask types: same-frame first tick, zero turns, no foe/status/cooldown/regen/other-flask advance, and no idle recovery\n", .{});
}

test "mana recovery carries partial progress over spent turns and resets on a new run" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.mana = 0;
    for (0..4) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 0), g.mana);
    try std.testing.expectEqual(@as(i32, 4), g.mana_recovery);
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 1), g.mana);
    try std.testing.expectEqual(@as(i32, 0), g.mana_recovery);
    takeNode(g, "Slow Tide");
    for (0..3) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 2), g.mana);
    try std.testing.expectEqual(@as(i32, 1), g.mana_recovery);
    for (0..2) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 3), g.mana);
    try std.testing.expectEqual(@as(i32, 0), g.mana_recovery);
    harness.use(g, .wait);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expectEqual(@as(i32, 0), g.mana_recovery);
    try std.testing.expectEqual(game.manaMax(g), g.mana);
    std.debug.print("mana: 1 per 5 spent turns, Slow Tide 2 per 5 with carried remainder, fresh runs reset recovery\n", .{});
}

test "a flask's first heal shows immediately and later recovery precedes the next bite" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    const h = g.heroActor().?;
    h.hp = 10;
    game.catchUp(g);
    const hero = game.heroSlot(g).?;
    harness.use(g, .life_flask);
    const first_tick = 10 + firstLifeTick(h.max);
    try std.testing.expectEqual(first_tick, h.hp);
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(first_tick, g.pictured[hero].hp);
    g.rng = harness.bitesRng(g, .rat, &.{true});
    harness.use(g, .wait);
    const healed = first_tick + firstLifeTick(h.max);
    try std.testing.expect(h.hp < healed);
    var first: ?i32 = null;
    g.st = .{};
    var t: f32 = 0;
    while (t < 1) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (first == null and g.pictured[hero].hp != first_tick) first = g.pictured[hero].hp;
    }
    std.debug.print("flask heal: immediate {d} -> {d}, next turn {?d} before bite -> {d}\n", .{ 10, first_tick, first, g.pictured[hero].hp });
    try std.testing.expectEqual(@as(?i32, healed), first);
    try std.testing.expectEqual(h.hp, g.pictured[hero].hp);
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
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.pool.get(2) == null);
    try std.testing.expectEqual(@as(i32, 5 + 1 + 2), h.hp);
    const hero = game.heroSlot(g).?;
    try std.testing.expectEqual(@as(i32, 5), g.pictured[hero].hp);
    const t = harness.framesUntil(g, hero, harness.caughtUp);
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
    try std.testing.expect(!harness.logged(g, pinning.TAKES));
}

test "passive leech waits for the arrow while a life flask recovers" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    takeNode(g, "Sanguine Pact");
    const h = g.heroActor().?;
    h.hp = 5;
    harness.setLife(g.pool.get(2).?, 50, 50);
    harness.use(g, .life_flask);
    game.catchUp(g);
    const hero = game.heroSlot(g).?;
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.pool.get(2) != null);
    const t = harness.framesUntil(g, hero, harness.caughtUp);
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
    try std.testing.expectEqual(try std.math.divCeil(i32, charge.COST * 90, 100), g.growth.cost(.charge));
    g.mana = 0;
    for (0..heroes.MANA_REGEN_TURNS) |_| harness.use(g, .wait);
    try std.testing.expectEqual(heroes.MANA_REGEN + 1, g.mana);
    const h = g.heroActor().?;
    h.hp = 1;
    harness.use(g, .life_flask);
    for (1..flask.TURNS) |_| harness.use(g, .wait);
    const healed = flask.lifeOf(h.max, 20);
    try std.testing.expectEqual(1 + healed, h.hp);
    var desc: [256]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, overlay.describe(g, .life_flask, &desc), "Recover 60% of life") != null);
    std.debug.print("passives: mana {d}/{d} turns, charge {d} -> {d} mana, life flask {d} -> {d} on {d} life\n", .{ game.manaRegen(g), heroes.MANA_REGEN_TURNS, cost, g.growth.cost(.charge), flask.lifeOf(h.max, 0), healed, h.max });
}

test "a kill's flask refill shows as the kill is drawn, not as the arrow leaves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    g.pool.get(2).?.hp = 1;
    g.flasks.getPtr(.life).charges = flask.USE - flask.PER_KILL;
    game.catchUp(g);
    harness.confirmUse(g, .shoot);
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
