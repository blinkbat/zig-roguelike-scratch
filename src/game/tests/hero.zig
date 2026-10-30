const attacks = @import("../attacks.zig");
const std = @import("std");
const progress = @import("../../play/progress.zig");
const mathx = @import("../../core/mathx.zig");
const hud = @import("../../ui/hud.zig");
const heroes = @import("../../play/hero.zig");
const bow = @import("../../play/bow.zig");
const juke = @import("../../play/juke.zig");
const pinning = @import("../../play/pinning.zig");
const charge = @import("../../play/charge.zig");
const flask = @import("../../play/flask.zig");
const skillbar = @import("../../play/skillbar.zig");
const fx = @import("../../gfx/fx.zig");
const scene = @import("../scene.zig");
const overlay = @import("../overlay.zig");
const character = @import("../character.zig");
const combat = @import("../combat.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const skills = @import("../skills.zig");
const consumable = @import("../../play/consumable.zig");
const menu = @import("../../ui/menu.zig");

fn carry(g: *game.Game, act: skillbar.Act, n: u8) void {
    g.sim.inventory.stacks.set(act.supplyOf().?, n);
    if (g.bar.slotOf(act) == null) g.bar.bind(g.bar.firstEmpty().?, act);
}

test "a bandage stops bleeding for a turn and one from the stack, and none left spends nothing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    carry(g, .bandage, 1);
    const h = g.sim.heroActor().?;
    h.bleed.startWith(3);
    const hp = h.hp;
    var next = g.sim.clock;
    next.turn();
    harness.use(g, .bandage);
    try std.testing.expectEqual(next, g.sim.clock);
    try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
    try std.testing.expectEqual(hp, h.hp);
    try std.testing.expectEqual(@as(u8, 0), g.sim.inventory.stacks.get(.bandage));
    h.bleed.startWith(3);
    harness.use(g, .bandage);
    try std.testing.expectEqual(next, g.sim.clock);
    try std.testing.expect(h.bleed.turns > 0);
    try std.testing.expect(harness.logged(g, "none carried"));
    std.debug.print("bandage: bleed stopped in one turn with no bleed tick; an empty stack refuses and spends no turn\n", .{});
}

test "smelling salts keep every stun off through the turn they are used and the five after" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    carry(g, .smelling_salts, 1);
    const h = g.sim.heroActor().?;
    harness.use(g, .smelling_salts);
    try std.testing.expectEqual(@as(u8, 0), g.sim.inventory.stacks.get(.smelling_salts));
    for (0..consumable.SmellingSalts.TURNS) |_| {
        const rng = g.sim.rng;
        try std.testing.expect(!g.sim.takeStatus(h, .stun));
        try std.testing.expectEqualDeep(rng, g.sim.rng);
        harness.use(g, .wait);
    }
    try std.testing.expect(g.sim.takeStatus(h, .stun));
    std.debug.print("smelling salts: {d} turns after use with no stun landing and no roll drawn, then a stun lands\n", .{consumable.SmellingSalts.TURNS});
}

test "a frost vial thrown from the bag splashes cold on every foe round its mark and none past it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{ .{ .x = 26, .y = 20 }, .{ .x = 27, .y = 21 }, .{ .x = 29, .y = 20 } });
    harness.toughenFoes(g);
    g.sim.inventory.stacks.set(.frost_vial, 2);
    character.openCharacter(g);
    g.character.choose(.inventory);
    harness.press(g, menu.CONFIRM);
    try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(u8, 2), g.sim.inventory.stacks.get(.frost_vial));
    var next = g.sim.clock;
    next.turn();
    harness.press(g, menu.CONFIRM);
    try std.testing.expectEqual(next, g.sim.clock);
    try std.testing.expectEqual(@as(u8, 1), g.sim.inventory.stacks.get(.frost_vial));
    const struck = harness.TEST_HP - g.sim.pool.get(2).?.hp;
    try harness.expectDamage(g, .frost_vial, struck, &.{consumable.FrostVial.BASE});
    try harness.expectDamage(g, .frost_vial, harness.TEST_HP - g.sim.pool.get(3).?.hp, &.{consumable.FrostVial.BASE});
    try std.testing.expectEqual(harness.TEST_HP, g.sim.pool.get(4).?.hp);
    std.debug.print("frost vial: {d} cold to the struck rat, {d} beside it, none 3 tiles on; one vial used\n", .{ struck, harness.TEST_HP - g.sim.pool.get(3).?.hp });
}

test "attack resolution returns harm and statuses without advancing the picture" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
    const target = g.sim.pool.get(2).?;
    harness.setLife(target, 20, 20);
    g.pic.catchUp(&g.sim);
    const before = g.pic.pictured[1];
    const raw = attacks.Roll{ .dmg = 3, .hit_checked = true, .effect = .{ .bleed = 100, .bleed_damage = 2, .stun = 100 } };
    const outcome = attacks.resolve(&g.sim, .fromInt(2), raw, .chosen).?;
    try std.testing.expect(outcome == .hit);
    const hit = outcome.hit;
    try std.testing.expectEqual(@as(i32, 17), target.hp);
    try std.testing.expectEqual(@as(i32, 3), hit.damage.dmg);
    try std.testing.expect(!hit.damage.lethal and !hit.culled);
    try std.testing.expect(hit.bled != null and hit.stunned);
    try std.testing.expectEqual(@as(i32, 2), target.bleed.amount);
    try std.testing.expect(hit.at.eq(target.at));
    try std.testing.expectEqualDeep(before, g.pic.pictured[1]);
    try std.testing.expect(!g.pic.owed[1].any());
    const rng = g.sim.rng;
    const log = g.sim.log;
    try std.testing.expect(attacks.resolve(&g.sim, .fromInt(3), raw, .chosen) == null);
    try std.testing.expectEqualDeep(rng, g.sim.rng);
    try std.testing.expectEqualDeep(log, g.sim.log);
    std.debug.print("attack boundary: damage, bleed and stun resolved before picture changes; missing target leaves RNG and log untouched\n", .{});
}

test "chosen attacks reactions and status ticks retain recorded seeded outcomes" {
    const cases = .{
        .{ @as(u64, 11), @as(i32, 82), [_]u64{ 862564402851664045, 4794504947867443746, 7755685727112513350, 12536992963963539506 } },
        .{ @as(u64, 42), @as(i32, 78), [_]u64{ 7903954225905035531, 9357853297271469720, 2724644940759801119, 10543582298886573110 } },
        .{ @as(u64, 113), @as(i32, 81), [_]u64{ 4410175173307694628, 1620366555190407232, 5054763941814804829, 38094909334747344 } },
    };
    inline for (cases) |case| {
        const g = try game.boot(std.testing.allocator);
        defer game.shut(std.testing.allocator, g);
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
        const target = g.sim.pool.get(2).?;
        target.max = 100;
        target.hp = 100;
        g.sim.rng = mathx.Rng.init(case[0]);
        const stroke = game.presentation.Stroke{ .from = g.sim.heroAt().?, .wait = 0.2 };
        combat.wound(g, 2, attacks.heroRoll(&g.sim, .ranged, 7), "shoots", stroke);
        combat.reaction(g, 2, attacks.heroRoll(&g.sim, .melee, 5), "counters", stroke, 2, null);
        target.burn.start();
        _ = target.burn.tick(0);
        combat.burnHarm(g, 2);
        try std.testing.expectEqual(case[1], target.hp);
        try std.testing.expectEqualDeep(case[2], g.sim.rng.impl.s);
    }
    std.debug.print("seeded combat: 3 chosen/reaction/burn sequences retain original HP and final RNG state\n", .{});
}

test "hero post-action death prevents gas spread and foe actions while clearing turn tracking" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = mathx.P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    const h = g.sim.heroActor().?;
    h.hp = 1;
    g.sim.lv.addGas(from, @import("../../map/gas.zig").BURST);
    const lv = g.sim.lv;
    const rng = g.sim.rng;
    const foe = g.sim.pool.items[1];
    g.sim.stepped = true;
    g.sim.displaced.set(1);
    combat.endTurn(g);
    try std.testing.expect(g.mode == .dead);
    try std.testing.expectEqualDeep(rng, g.sim.rng);
    try std.testing.expectEqualDeep(lv.gas, g.sim.lv.gas);
    try std.testing.expectEqualDeep(foe.clock, g.sim.pool.items[1].clock);
    try std.testing.expectEqual(foe.at, g.sim.pool.items[1].at);
    try std.testing.expect(!g.pic.owed[1].any());
    try std.testing.expect(!g.sim.stepped);
    try std.testing.expectEqual(@as(usize, 0), g.sim.displaced.count());
    for (g.sim.ran) |ran| try std.testing.expectEqual(@as(usize, 0), ran.count());
    std.debug.print("turn stages: lethal hero gas precedes spread and foe clocks; all consumed ticks and displacement cleared\n", .{});
}

test "damage resolution changes only simulation and preserves random streams" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |protected| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const h = g.sim.heroActor().?;
        h.hp = 9;
        h.ward.turns = 3;
        g.sim.mana = 4;
        g.sim.unkillable = protected;
        game.settle(g);
        const rng = g.sim.rng;
        const loot_rng = g.sim.loot_rng;
        const pictured = g.pic.heroShown(&g.sim).?;
        const result = g.sim.resolveDamage(.fromInt(g.sim.hero), 20);
        try std.testing.expectEqual(@as(i32, 4), result.mana);
        try std.testing.expectEqual(@as(i32, if (protected) 8 else 16), result.dmg);
        try std.testing.expectEqual(!protected, result.lethal);
        try std.testing.expectEqual(@as(i32, 0), g.sim.mana);
        try std.testing.expectEqual(@as(i32, 0), g.pic.mana_held);
        try std.testing.expectEqualDeep(pictured, g.pic.heroShown(&g.sim).?);
        try std.testing.expectEqualDeep(rng, g.sim.rng);
        try std.testing.expectEqualDeep(loot_rng, g.sim.loot_rng);
    }
    std.debug.print("damage resolver: shield absorption, lethal and protected harm, unchanged picture and both RNG streams\n", .{});
}

fn firstLifeTick(max: i32) i32 {
    var f = flask.Flask{};
    f.drink(flask.lifeOf(max, 0));
    return f.tick();
}

fn takeNode(g: *game.Game, name: []const u8) void {
    for (progress.NODES, 0..) |n, i| if (std.mem.eql(u8, n.name, name)) return g.sim.growth.nodes.set(i);
    unreachable;
}

fn takeCull(g: *game.Game) void {
    takeNode(g, "Culling Blow");
    takeNode(g, "Executioner");
}

test "a hero bitten to death gets an epitaph naming the rat, entombed only while the hall has room" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var hall = game.ossuary.Hall{};
    g.hall = &hall;
    harness.bittenToDeath(g);
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
    const said = g.epitaph.?.text();
    std.debug.print("epitaph: {s}\n", .{said});
    try std.testing.expect(std.mem.startsWith(u8, said, "Archer was bitten to death by a rat on a nameless floor."));
    try std.testing.expect(std.mem.endsWith(u8, said, " " ++ game.ossuary.ENTOMBED));
    try std.testing.expectEqual(@as(usize, 1), hall.n);
    for (&hall.entries) |*e| {
        e.* = g.epitaph.?;
        e.renown = std.math.maxInt(u32);
    }
    hall.n = game.ossuary.MAX;
    harness.bittenToDeath(g);
    try std.testing.expect(!std.mem.endsWith(u8, g.epitaph.?.text(), game.ossuary.ENTOMBED));
    try std.testing.expectEqual(game.ossuary.MAX, hall.n);
}

fn missedBlowArena(g: *game.Game) !u16 {
    const from = mathx.P{ .x = 20, .y = 20 };
    harness.heroArena(g, .knight, from, &.{});
    g.sim.name = heroes.Name.of("Knight");
    g.sim.lv.set(from, .reeds);
    const id = harness.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, true);
    game.settle(g);
    const attacker = g.sim.combatStats(g.sim.heroBody().?);
    const defender = g.sim.combatStats(g.sim.pool.get(id).?);
    for (0..1000) |seed| {
        var rng = mathx.Rng.init(seed);
        if (attacker.misses(defender, &rng)) {
            g.sim.rng = mathx.Rng.init(seed);
            return id;
        }
    }
    return error.NoMissSeed;
}

test "missed reactions preserve the chosen last deed while chosen attacks still report misses" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |reacting| {
        const id = try missedBlowArena(g);
        const hero = g.sim.heroBody().?;
        const before = g.sim.pool.get(id).?.hp;
        g.sim.chronicle.begin(.{ .hp = hero.hp, .max = hero.max });
        g.sim.chronicle.note(.{ .used = if (reacting) .wait else .shoot });
        const stroke = game.presentation.Stroke{ .from = hero.at, .wait = 0 };
        if (reacting) combat.reaction(g, id, .{ .dmg = 100 }, "counters", stroke, id, null) else combat.wound(g, id, .{ .dmg = 100 }, "shoots", stroke);
        try std.testing.expectEqual(before, g.sim.pool.get(id).?.hp);
        g.sim.chronicle.note(.{ .hurt = .{ .by = .{ .foe = .rat }, .dmg = hero.hp, .before = hero.hp } });
        const report = game.epitaph.of(g);
        const deed = if (reacting) "Knight waited." else "Knight's last arrow missed.";
        try std.testing.expect(std.mem.indexOf(u8, report.text(), deed) != null);
    }
    std.debug.print("missed blows: chosen attack reported, automatic reaction preserves Wait in the epitaph\n", .{});
}

test "missed reactions preserve projectile timing without phantom barrels or impact effects" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |projectile| {
        const id = try missedBlowArena(g);
        const from = g.sim.heroAt().?;
        const at = g.sim.pool.get(id).?.at;
        const before = g.sim.pool.get(id).?.hp;
        const flight = if (projectile) bow.fly(&g.sim.lv, from, at) else null;
        combat.reaction(g, id, .{ .dmg = 100 }, "counters", .{ .from = from, .wait = 0 }, id, flight);
        try std.testing.expectEqual(before, g.sim.pool.get(id).?.hp);
        g.pic.stepGlide(&g.sim, g.cloud, 0);
        try std.testing.expect(!g.pic.fx.breaking(at));
        try std.testing.expectEqual(projectile, g.pic.shot != null);
        try std.testing.expect(g.pic.busy >= game.BUMP_LANDS);
        if (g.pic.shot) |shot| try std.testing.expect(g.pic.busy >= -shot.t + shot.ends());
        try std.testing.expectEqual(@as(usize, 0), g.pic.fx.due_n);
        harness.drawnOut(g);
        try std.testing.expect(!g.pic.fx.breaking(at));
    }
    std.debug.print("missed reactions: melee and projectile misses schedule no barrel or hit effects; arrow timing retained\n", .{});
}

test "life and mana fill and drain at XP speed after their presented impact" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const h = g.sim.heroActor().?;
    const max_mana = g.sim.manaMax();
    g.pic.settleResources(&g.sim);
    h.hp = @divTrunc(h.max, 2);
    g.sim.mana = @divTrunc(max_mana, 2);
    g.pic.mana_held = max_mana - g.sim.mana;
    var after = g.pic.afterOf(&g.sim, g.sim.heroSlot().?);
    after.mana = g.pic.mana_held;
    g.pic.fx.settle(1, .{ .slot = g.sim.heroSlot().?, .after = after });
    g.pic.busy = 1;
    g.st = .{};
    game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(f32, 1), g.pic.life_fill);
    try std.testing.expectEqual(@as(f32, 1), g.pic.mana_fill);
    g.pic.busy = 0;
    g.pic.fx.step(&g.sim.lv, 1);
    g.pic.catchUp(&g.sim);
    const life_target = hud.fillOf(h.hp, h.max);
    const mana_target = hud.fillOf(g.sim.mana, max_mana);
    game.update(g, harness.TEST_DT);
    try std.testing.expectApproxEqAbs(1 + (life_target - 1) * mathx.easing(harness.TEST_DT, game.presentation.RESOURCE_EASE), g.pic.life_fill, 0.0001);
    try std.testing.expectApproxEqAbs(1 + (mana_target - 1) * mathx.easing(harness.TEST_DT, game.presentation.RESOURCE_EASE), g.pic.mana_fill, 0.0001);
    for (0..300) |_| game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(life_target, g.pic.life_fill);
    try std.testing.expectEqual(mana_target, g.pic.mana_fill);
    h.hp = h.max;
    g.sim.mana = max_mana;
    g.pic.catchUp(&g.sim);
    game.update(g, harness.TEST_DT);
    try std.testing.expect(g.pic.life_fill > life_target and g.pic.life_fill < 1);
    try std.testing.expect(g.pic.mana_fill > mana_target and g.pic.mana_fill < 1);
    for (0..300) |_| game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(f32, 1), g.pic.life_fill);
    try std.testing.expectEqual(@as(f32, 1), g.pic.mana_fill);
    std.debug.print("resource fills: held until impact, exact XP easing in both directions, settle without overshoot\n", .{});
}

test "the experience bar holds a turn's experience until the turn is drawn, then fills toward it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.pic.busy = game.GLIDE_S;
    _ = g.sim.growth.gain(progress.xpOf(.rat) * 3);
    game.update(g, 0);
    try std.testing.expectEqual(@as(f32, 0), g.pic.xp_shown);
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    const aim = g.sim.xpLevels();
    try std.testing.expect(g.pic.xp_shown > 0 and g.pic.xp_shown < aim);
    var t: f32 = 0;
    while (g.pic.xp_shown != aim and t < 1) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    std.debug.print("experience bar: {d:.3} of a level drawn {d:.2} s after the turn\n", .{ g.pic.xp_shown, t });
    try std.testing.expect(t > 0 and t < 1);
    try std.testing.expectEqual(aim, g.pic.xp_shown);
}

test "a level reached exactly empties the bar, and the book shows it only once the turn is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    g.pic.busy = game.GLIDE_S;
    _ = g.sim.growth.gain(@intCast(g.sim.growth.needed()));
    g.sim.gold += 7;
    game.update(g, 0);
    var nearby: game.NearbyBuf = undefined;
    const held = character.bookView(g, &nearby);
    try std.testing.expectEqual(@as(u16, 1), held.growth.level);
    try std.testing.expectEqual(@as(i32, 0), held.gold);
    var t: f32 = 0;
    while (g.pic.xp_shown != g.sim.xpLevels() and t < 10) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    try std.testing.expectEqual(@as(f32, 1), g.pic.xp_shown);
    try std.testing.expectEqual(@as(u16, 2), character.bookView(g, &nearby).growth.level);
    try std.testing.expectEqual(@as(i32, 7), character.bookView(g, &nearby).gold);
    std.debug.print("exact level-up: bar fill {d} after {d:.2} s\n", .{ g.pic.xp_shown - @floor(g.pic.xp_shown), t });
}

test "level-up celebrates presented progression once without holding play or replaying on load" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
    const clock = g.sim.clock;
    const rng = g.sim.rng;
    const seen = g.sim.lv.seen;
    g.pic.busy = game.GLIDE_S;
    _ = g.sim.growth.gain(@intCast(g.sim.growth.needed()));
    game.update(g, 0);
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.level_up.life);
    game.update(g, game.GLIDE_S + 0.01);
    try std.testing.expectEqual(fx.LEVEL_UP_S, g.pic.fx.level_up.life);
    try std.testing.expect(g.pic.quiet());
    game.update(g, 0.5);
    try std.testing.expectEqual(fx.LEVEL_UP_S - 0.5, g.pic.fx.level_up.life);
    scene.effectLights(g);
    try std.testing.expectEqual(@as(usize, 1), g.light.effect_n);
    const peak_light = g.light.effects[0].source.gain;
    const glow = g.pic.fx.level_up.bodyGlow();
    try std.testing.expect(glow[0] > glow[1] and glow[1] > glow[2] and glow[2] > 0);
    game.update(g, 1.25);
    scene.effectLights(g);
    try std.testing.expect(g.light.effects[0].source.gain < peak_light);
    try std.testing.expect(g.pic.fx.level_up.bodyGlow()[0] < glow[0]);
    game.update(g, fx.LEVEL_UP_S);
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.level_up.life);
    scene.effectLights(g);
    try std.testing.expectEqual(@as(usize, 0), g.light.effect_n);
    try std.testing.expectEqual([_]f32{ 0, 0, 0 }, g.pic.fx.level_up.bodyGlow());
    _ = g.sim.growth.gain(@intCast(g.sim.growth.needed()));
    g.pic.settleXp(&g.sim);
    game.update(g, 0);
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.level_up.life);
    g.pic.fx.levelUp();
    g.pic.fx.clear();
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.level_up.life);
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expectEqualDeep(rng, g.sim.rng);
    try std.testing.expectEqualDeep(seen, g.sim.lv.seen);
    std.debug.print("level-up: delayed, one-shot, nonblocking; gold body glow and local light fade and expire together; load suppressed and reset; clock/RNG/exploration unchanged\n", .{});
}

test "the log says the blow and the experience it awards, a juke as itself, and never a bare skill use" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 23, .y = 20 }});
    g.sim.pool.get(2).?.hp = 1;
    game.settle(g);
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.sim.pool.get(2) == null);
    var buf: [64]u8 = undefined;
    const gained = try std.fmt.bufPrint(&buf, "Archer gains {d} experience.", .{progress.xpOf(.rat)});
    try std.testing.expect(harness.logged(g, gained));
    try std.testing.expect(!harness.logged(g, " uses "));
    while (!g.pic.quiet()) game.update(g, harness.TEST_DT);
    skills.openLeap(g, harness.boundTo(g, .juke).by, .juke);
    g.mode.aim.mark = .{ .x = 20 + juke.RANGE, .y = 20 };
    skills.confirmAim(g);
    try std.testing.expectEqualStrings("Archer jukes away.", g.sim.log.line(0).?);
    std.debug.print("log: \"{s}\" then \"{s}\"\n", .{ gained, g.sim.log.line(0).? });
}

test "a flask drink spends a turn, recovers on it and the next two, and kills refill only a worn flask" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const h = g.sim.heroActor().?;
    h.hp = 1;
    g.sim.mana = 0;
    var next = g.sim.clock;
    next.turn();
    harness.use(g, .life_flask);
    try std.testing.expectEqual(next, g.sim.clock);
    const per = firstLifeTick(h.max);
    try std.testing.expectEqual(1 + per, h.hp);
    for (1..flask.TURNS) |_| harness.use(g, .wait);
    try std.testing.expectEqual(1 + flask.lifeOf(h.max, 0), h.hp);
    harness.use(g, .mana_flask);
    for (1..flask.TURNS) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@min(g.sim.manaMax(), flask.MANA_GAIN + @divTrunc(heroes.MANA_REGEN * (flask.TURNS * 2), heroes.MANA_REGEN_TURNS)), g.sim.mana);
    harness.use(g, .life_flask);
    harness.use(g, .life_flask);
    try std.testing.expectEqual(@as(u8, 0), g.sim.flasks.get(.life).uses());
    const empty = g.sim.clock;
    harness.use(g, .life_flask);
    try std.testing.expectEqual(empty, g.sim.clock);
    try std.testing.expectEqual(@as(u8, 0), g.sim.flasks.get(.life).uses());
    for (0..flask.USE / flask.PER_KILL) |_| combat.fell(g, 2);
    try std.testing.expectEqual(@as(u8, 1), g.sim.flasks.get(.life).uses());
    try g.sim.inventory.unequip(.life_flask, g.sim.growth.attributes(g.sim.class));
    const charges = g.sim.flasks.get(.life).charges;
    g.sim.flasks.getPtr(.mana).charges = flask.USE;
    const mana_charges = g.sim.flasks.get(.mana).charges;
    const unworn = g.sim.clock;
    harness.use(g, .life_flask);
    try std.testing.expectEqual(unworn, g.sim.clock);
    try std.testing.expectEqual(charges, g.sim.flasks.get(.life).charges);
    try std.testing.expect(harness.logged(g, "is not equipped."));
    combat.fell(g, 2);
    try std.testing.expectEqual(charges, g.sim.flasks.get(.life).charges);
    try std.testing.expectEqual(mana_charges + flask.PER_KILL, g.sim.flasks.get(.mana).charges);
    std.debug.print("life flask: {d} hp over {d} turns on a knight of {d}; empty after {d} drinks; {d} kills refill one; unworn it neither drinks nor refills\n", .{ flask.lifeOf(h.max, 0), flask.TURNS, h.max, flask.CHARGES / flask.USE, flask.USE / flask.PER_KILL });
}

test "each flask drink is a whole turn: foes, ailments, cooldowns, regeneration and the other flask all advance" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]skillbar.Act{ .life_flask, .mana_flask }) |act| {
        harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
        harness.wakeFoes(g);
        const h = g.sim.heroActor().?;
        h.hp = h.max - firstLifeTick(h.max);
        h.burn = .{ .turns = 2 };
        g.sim.mana = 0;
        g.sim.mana_recovery = heroes.MANA_REGEN_TURNS - 1;
        g.sim.cooldown.set(.charge, 2);
        const kind = act.flaskOf().?;
        const other: flask.Kind = if (kind == .life) .mana else .life;
        g.sim.flasks.getPtr(other).drink(9);
        const other_before = g.sim.flasks.get(other);
        var next = g.sim.clock;
        next.turn();
        const rng = g.sim.rng;
        g.sim.unsaved = false;
        g.pic.catchUp(&g.sim);
        harness.use(g, act);
        try std.testing.expect(g.sim.unsaved);
        try std.testing.expectEqual(next, g.sim.clock);
        try std.testing.expect(!std.meta.eql(rng, g.sim.rng));
        try std.testing.expect(h.burn.turns < 2);
        try std.testing.expectEqual(@as(u8, 1), g.sim.cooldown.get(.charge));
        try std.testing.expectEqual(@as(i32, 0), g.sim.mana_recovery);
        try std.testing.expectEqual(other_before.turns - 1, g.sim.flasks.get(other).turns);
        try std.testing.expectEqual(@as(u8, 1), act.turns());
        try std.testing.expectEqual(flask.TURNS - 1, g.sim.flasks.get(kind).turns);
        try std.testing.expectEqual(flask.CHARGES / flask.USE - 1, g.sim.flasks.get(kind).uses());
        const flask_mana = if (kind == .mana) try std.math.divCeil(i32, flask.MANA_GAIN, flask.TURNS) else try std.math.divCeil(i32, 9, flask.TURNS);
        try std.testing.expectEqual(heroes.MANA_REGEN + flask_mana, g.sim.mana);
        var description: [256]u8 = undefined;
        try std.testing.expect(std.mem.indexOf(u8, overlay.describe(g, act, &description), "1 turn") != null);
        const recovering = g.sim.flasks;
        const hp = h.hp;
        const mana = g.sim.mana;
        harness.calm(g);
        g.st = .{};
        game.update(g, 1);
        try std.testing.expectEqualDeep(recovering, g.sim.flasks);
        try std.testing.expectEqual(hp, h.hp);
        try std.testing.expectEqual(mana, g.sim.mana);
        try std.testing.expectEqual(next, g.sim.clock);
    }
    std.debug.print("2 flask types: one turn each, foes roll, burn, cooldown, regeneration and the other flask advance; no idle recovery\n", .{});
}

test "mana recovery carries partial progress over spent turns and resets on a new run" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.sim.mana = 0;
    for (0..4) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 0), g.sim.mana);
    try std.testing.expectEqual(@as(i32, 4), g.sim.mana_recovery);
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 1), g.sim.mana);
    try std.testing.expectEqual(@as(i32, 0), g.sim.mana_recovery);
    takeNode(g, "Slow Tide");
    for (0..3) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 2), g.sim.mana);
    try std.testing.expectEqual(@as(i32, 1), g.sim.mana_recovery);
    for (0..2) |_| harness.use(g, .wait);
    try std.testing.expectEqual(@as(i32, 3), g.sim.mana);
    try std.testing.expectEqual(@as(i32, 0), g.sim.mana_recovery);
    harness.use(g, .wait);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expectEqual(@as(i32, 0), g.sim.mana_recovery);
    try std.testing.expectEqual(g.sim.manaMax(), g.sim.mana);
    std.debug.print("mana: 1 per 5 spent turns, Slow Tide 2 per 5 with carried remainder, fresh runs reset recovery\n", .{});
}

test "a flask's first heal shows on its own turn and later recovery precedes the next bite" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    const h = g.sim.heroActor().?;
    h.hp = 10;
    g.pic.catchUp(&g.sim);
    const hero = g.sim.heroSlot().?;
    g.sim.rng = harness.bitesRng(g, &.{.{ .id = 2, .lands = false }});
    harness.use(g, .life_flask);
    const first_tick = 10 + firstLifeTick(h.max);
    try std.testing.expectEqual(first_tick, h.hp);
    g.st = .{};
    game.update(g, 0);
    try std.testing.expectEqual(first_tick, g.pic.pictured[hero].hp);
    g.sim.rng = harness.bitesRng(g, &.{.{ .id = 2, .lands = true }});
    harness.use(g, .wait);
    const healed = first_tick + firstLifeTick(h.max);
    try std.testing.expect(h.hp < healed);
    var first: ?i32 = null;
    g.st = .{};
    var t: f32 = 0;
    while (t < 1) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (first == null and g.pic.pictured[hero].hp != first_tick) first = g.pic.pictured[hero].hp;
    }
    std.debug.print("flask heal: immediate {d} -> {d}, next turn {?d} before bite -> {d}\n", .{ 10, first_tick, first, g.pic.pictured[hero].hp });
    try std.testing.expectEqual(@as(?i32, healed), first);
    try std.testing.expectEqual(h.hp, g.pic.pictured[hero].hp);
}

test "passive leech and kill healing land on the drawn hero with the arrow" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    takeNode(g, "Sanguine Pact");
    takeNode(g, "Red Harvest");
    const h = g.sim.heroActor().?;
    h.hp = 5;
    g.sim.pool.get(2).?.hp = 1;
    g.pic.catchUp(&g.sim);
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.sim.pool.get(2) == null);
    try std.testing.expectEqual(@as(i32, 5 + 1 + 2), h.hp);
    const hero = g.sim.heroSlot().?;
    try std.testing.expectEqual(@as(i32, 5), g.pic.pictured[hero].hp);
    const t = harness.framesUntil(g, hero, harness.caughtUp);
    std.debug.print("leech 1 + kill heal 2: drawn hero 5 -> 8 at {d:.3} s, as the arrow lands at {d:.3} s\n", .{ t, game.presentation.flown(6) });
    try std.testing.expectApproxEqAbs(game.presentation.flown(6), t, harness.TEST_TOL);
}

test "passive cull finishes a foe left at its threshold and spares one above it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 22, .y = 20 }, .{ .x = 22, .y = 22 } });
    takeCull(g);
    try std.testing.expectEqual(@as(i32, 10), g.sim.growth.perks().cull);
    for ([_]u16{ 2, 3 }) |id| harness.setLife(g.sim.pool.get(id).?, 20, 20);
    const from = g.sim.heroActor().?.at;
    combat.wound(g, 2, .{ .dmg = 18 }, combat.SHOOT, .{ .from = from, .wait = 0 });
    combat.wound(g, 3, .{ .dmg = 17 }, combat.SHOOT, .{ .from = from, .wait = 0 });
    try std.testing.expect(g.sim.pool.get(2) == null);
    try std.testing.expectEqual(@as(i32, 3), g.sim.pool.get(3).?.hp);
    std.debug.print("cull 10%: a 20-life foe left at 2 is cut down, one left at 3 survives\n", .{});
}

test "a blow that does no damage culls nothing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    takeCull(g);
    harness.setLife(g.sim.pool.get(2).?, 2, 20);
    combat.wound(g, 2, .{ .dmg = 0 }, combat.SHOOT, .{ .from = g.sim.heroActor().?.at, .wait = 0 });
    try std.testing.expectEqual(@as(i32, 2), g.sim.pool.get(2).?.hp);
}

test "a culled foe is not said to take the arrow's status" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    takeCull(g);
    harness.setLife(g.sim.pool.get(2).?, 3, 20);
    combat.arrowHit(g, 2, .{ .blow = .{ .physical = 1 } }, .pinning_shot, .{ .from = g.sim.heroActor().?.at, .wait = 0 });
    try std.testing.expect(g.sim.pool.get(2) == null);
    try std.testing.expect(!harness.logged(g, pinning.TAKES));
}

test "passive leech waits for the arrow while a life flask recovers" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    takeNode(g, "Sanguine Pact");
    const h = g.sim.heroActor().?;
    h.hp = 5;
    harness.setLife(g.sim.pool.get(2).?, 50, 50);
    harness.use(g, .life_flask);
    g.pic.catchUp(&g.sim);
    const hero = g.sim.heroSlot().?;
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.sim.pool.get(2) != null);
    const t = harness.framesUntil(g, hero, harness.caughtUp);
    std.debug.print("leech under a ticking flask: drawn hero reaches {d} at {d:.3} s, as the arrow lands at {d:.3} s\n", .{ h.hp, t, game.presentation.flown(6) });
    try std.testing.expectApproxEqAbs(game.presentation.flown(6), t, harness.TEST_TOL);
}

test "passive mana recovery, skill cost and flask recovery reach the live numbers" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .knight, .{ .x = 20, .y = 20 }, &.{.{ .x = 30, .y = 20 }});
    const cost = g.sim.growth.cost(.charge);
    takeNode(g, "Slow Tide");
    takeNode(g, "Attuned");
    takeNode(g, "Scar Tissue");
    try std.testing.expectEqual(try std.math.divCeil(i32, charge.COST * 90, 100), g.sim.growth.cost(.charge));
    g.sim.mana = 0;
    for (0..heroes.MANA_REGEN_TURNS) |_| harness.use(g, .wait);
    try std.testing.expectEqual(heroes.MANA_REGEN + 1, g.sim.mana);
    const h = g.sim.heroActor().?;
    h.hp = 1;
    harness.use(g, .life_flask);
    for (1..flask.TURNS) |_| harness.use(g, .wait);
    const healed = flask.lifeOf(h.max, 20);
    try std.testing.expectEqual(1 + healed, h.hp);
    var desc: [256]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, overlay.describe(g, .life_flask, &desc), "Recover 60% of life") != null);
    std.debug.print("passives: mana {d}/{d} turns, charge {d} -> {d} mana, life flask {d} -> {d} on {d} life\n", .{ g.sim.manaRegen(), heroes.MANA_REGEN_TURNS, cost, g.sim.growth.cost(.charge), flask.lifeOf(h.max, 0), healed, h.max });
}

test "a kill's flask refill shows as the kill is drawn, not as the arrow leaves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    g.sim.pool.get(2).?.hp = 1;
    g.sim.flasks.getPtr(.life).charges = flask.USE - flask.PER_KILL;
    g.pic.catchUp(&g.sim);
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.sim.pool.get(2) == null);
    try std.testing.expectEqual(@as(u8, 1), g.sim.flasks.get(.life).uses());
    try std.testing.expectEqual(@as(u8, 0), g.pic.flasks_shown.get(.life).uses());
    const Refilled = struct {
        fn f(gm: *game.Game, _: usize) bool {
            return gm.pic.flasks_shown.get(.life).uses() == 1;
        }
    };
    const t = harness.framesUntil(g, 0, Refilled.f);
    std.debug.print("a kill 7 cells out refills the drawn flask {d:.3} s in, as the arrow lands at {d:.3} s\n", .{ t, game.presentation.flown(6) });
    try std.testing.expectApproxEqAbs(game.presentation.flown(6), t, harness.TEST_TOL);
}
