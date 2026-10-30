const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const store = @import("../../core/store.zig");
const actor = @import("../../play/actor.zig");
const blind = @import("../../play/blind.zig");
const confusion = @import("../../play/confusion.zig");
const shock = @import("../../play/shock.zig");
const sunder = @import("../../play/sunder.zig");
const fx = @import("../../gfx/fx.zig");
const hud = @import("../../ui/hud.zig");
const format = @import("../../save_format.zig");
const data = @import("../../save_data.zig");
const attacks = @import("../attacks.zig");
const character = @import("../character.zig");
const combat = @import("../combat.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const P = mathx.P;

const FROM = P{ .x = 20, .y = 20 };
const EAST = FROM.add(.{ .x = 1, .y = 0 });
const TRIES: usize = 400;
/// Of the eight ways a stray picks from, one is the way it meant.
const STRAY_PERCENT = confusion.CHANCE * 7 / 8;

fn strayedAbout(strayed: usize) bool {
    const want = TRIES * STRAY_PERCENT / mathx.PERCENT;
    return strayed * 5 > want * 4 and strayed * 5 < want * 6;
}

test "a shock adds half again to the next hit on either side, then is spent" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{.{ .x = 23, .y = 20 }});
    const target = g.sim.pool.get(2).?;
    harness.setLife(target, 50, 50);
    target.shock.start();
    const blow = attacks.Roll{ .dmg = 4, .hit_checked = true };
    try std.testing.expectEqual(@as(i32, 6), attacks.resolve(&g.sim, .fromInt(2), blow, .chosen).?.hit.damage.dmg);
    try std.testing.expectEqual(@as(u8, 0), target.shock.turns);
    try std.testing.expectEqual(@as(i32, 4), attacks.resolve(&g.sim, .fromInt(2), blow, .chosen).?.hit.damage.dmg);

    var lost: [2]i32 = undefined;
    for ([_]bool{ false, true }, &lost) |shocked, *out| {
        harness.arena(g, FROM, &.{});
        const id = harness.spawnAt(g, .rat, EAST, true);
        const hero = g.sim.heroActor().?;
        if (shocked) hero.shock.start();
        const hp = hero.hp;
        g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = true }});
        combat.endTurn(g);
        out.* = hp - g.sim.heroActor().?.hp;
        try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.shock.turns);
    }
    try std.testing.expectEqual(@divTrunc(lost[0] * 3 + 1, 2), lost[1]);
    std.debug.print("shock: a 4-damage blow on a foe deals 6 then 4; a rat bite of {d} on the hero deals {d} shocked\n", .{ lost[0], lost[1] });
}

test "sunder takes armour off in the shared resolver, three stacks at most, letting more of a physical blow through" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{});
    const id = harness.spawnAt(g, .beefy_pib, .{ .x = 23, .y = 20 }, false);
    const pib = g.sim.pool.get(id).?;
    const blow = attacks.Roll{ .dmg = 10, .physical = 10, .hit_checked = true };
    var dealt: [sunder.MOST + 2]i32 = undefined;
    for (&dealt, 0..) |*d, stacks| {
        pib.sunder = .{};
        for (0..stacks) |_| sunder.afflict(pib, &g.sim.rng);
        harness.setLife(pib, 100, 100);
        d.* = attacks.resolve(&g.sim, .fromInt(id), blow, .chosen).?.hit.damage.dmg;
    }
    try std.testing.expectEqualSlices(i32, &.{ 8, 9, 10, 10, 10 }, &dealt);

    harness.heroArena(g, .knight, FROM, &.{});
    const hero = g.sim.heroActor().?;
    const armour = g.sim.combatStats(hero).armour;
    sunder.afflict(hero, &g.sim.rng);
    try std.testing.expectEqual(armour - sunder.PER_STACK, g.sim.combatStats(hero).armour);
    g.pic.catchUp(&g.sim);
    var nearby: game.NearbyBuf = undefined;
    try std.testing.expectEqual(armour - sunder.PER_STACK, character.bookView(g, &nearby).stats().reduction());
    std.debug.print("sunder: a 10-damage blow on a beefy pib deals {any} at 0-{d} stacks; the knight's {d}% reduction shows {d}%\n", .{ dealt, sunder.MOST + 1, armour, armour - sunder.PER_STACK });
}

test "a blinded foe neither notices nor hunts the hero past the next cell until three of its turns pass" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{});
    const asleep = harness.spawnAt(g, .rat, FROM.add(.{ .x = 3, .y = 0 }), false);
    const hunting = harness.spawnAt(g, .rat, FROM.add(.{ .x = 0, .y = 4 }), true);
    for ([_]u16{ asleep, hunting }) |id| blind.afflict(g.sim.pool.get(id).?, &g.sim.rng);
    const was = g.sim.pool.get(hunting).?.at;
    for (0..blind.TURNS) |_| {
        combat.endTurn(g);
        try std.testing.expect(!g.sim.pool.get(asleep).?.awake);
        try std.testing.expect(g.sim.pool.get(hunting).?.at.eq(was));
    }
    combat.endTurn(g);
    try std.testing.expect(g.sim.pool.get(asleep).?.awake);
    try std.testing.expectEqual(@as(i32, 3), mathx.dist(g.sim.pool.get(hunting).?.at, FROM));
    std.debug.print("blind foes: asleep 3 cells off and hunting 4 off, both idle {d} turns, then notice and close in\n", .{blind.TURNS});
}

test "a blinded hero sees only the cells beside it for three of its turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{});
    const far = FROM.add(.{ .x = 4, .y = 0 });
    const near = FROM.add(.{ .x = 1, .y = 1 });
    try std.testing.expect(g.sim.lv.isLit(far));
    blind.afflict(g.sim.heroActor().?, &g.sim.rng);
    game.castSight(g, FROM);
    var blinded: usize = 0;
    while (!g.sim.lv.isLit(far)) : (blinded += 1) {
        try std.testing.expect(g.sim.lv.isLit(near) and blinded <= blind.TURNS);
        combat.endTurn(g);
    }
    try std.testing.expectEqual(@as(usize, blind.TURNS), blinded);
    std.debug.print("blind hero: {d} turns seeing {d} cell, then a cell 4 off is lit again\n", .{ blinded, blind.SIGHT });
}

test "a confused hero's moves stray about as often as its chance, only onto moves that spend a turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var strayed: usize = 0;
    for (0..TRIES) |seed| {
        harness.arena(g, FROM, &.{});
        g.sim.heroActor().?.confusion.start();
        g.sim.rng = mathx.Rng.init(seed);
        game.heroStep(g, .e, 0);
        strayed += @intFromBool(!g.sim.heroActor().?.at.eq(EAST));
    }
    try std.testing.expect(strayedAbout(strayed));
    const WALLED = 64;
    for (0..WALLED) |seed| {
        harness.arena(g, FROM, &.{});
        for (mathx.ALL_DIRS) |d| if (d != .e) g.sim.lv.set(FROM.add(d.delta()), .wall);
        g.sim.heroActor().?.confusion.start();
        g.sim.rng = mathx.Rng.init(seed);
        game.heroStep(g, .e, 0);
        try std.testing.expect(g.sim.heroActor().?.at.eq(EAST));
    }
    std.debug.print("confused hero: {d}/{d} steps strayed (~{d}% expected); walled in but for one way, {d}/{d} took it\n", .{ strayed, TRIES, STRAY_PERCENT, WALLED, WALLED });
}

test "a confused foe's steps stray about as often as its chance" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = FROM.add(.{ .x = 5, .y = 0 });
    harness.arena(g, FROM, &.{});
    const steady = harness.spawnAt(g, .rat, start, true);
    combat.endTurn(g);
    const chased = g.sim.pool.get(steady).?.at;
    try std.testing.expect(!chased.eq(start));
    var strayed: usize = 0;
    for (0..TRIES) |seed| {
        harness.arena(g, FROM, &.{});
        const id = harness.spawnAt(g, .rat, start, true);
        g.sim.pool.get(id).?.confusion.start();
        g.sim.rng = mathx.Rng.init(seed);
        combat.endTurn(g);
        strayed += @intFromBool(!g.sim.pool.get(id).?.at.eq(chased));
    }
    try std.testing.expect(strayedAbout(strayed));
    std.debug.print("confused rat: {d}/{d} steps strayed from its chase (~{d}% expected)\n", .{ strayed, TRIES, STRAY_PERCENT });
}

test "every affliction shows on the pictured hero and the HUD, worn down by the turns it spends" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{});
    const hero = g.sim.heroActor().?;
    shock.afflict(hero, &g.sim.rng);
    sunder.afflict(hero, &g.sim.rng);
    blind.afflict(hero, &g.sim.rng);
    confusion.afflict(hero, &g.sim.rng);
    g.pic.catchUp(&g.sim);
    const statuses = [_]fx.Status{ .shocked, .sundered, .blinded, .confused };
    const turns = [_]u8{ shock.TURNS, sunder.TURNS, blind.TURNS, confusion.TURNS };
    var buf: hud.Shown = undefined;
    try std.testing.expectEqualSlices(fx.Status, &statuses, hud.shownStatuses(g.pic.heroShown(&g.sim).?.status, &buf));
    combat.endTurn(g);
    try std.testing.expectEqual(shock.TURNS, g.pic.heroShown(&g.sim).?.status.get(.shocked));
    harness.stagger(g);
    g.st = .{};
    game.update(g, harness.TEST_DT);
    harness.drawnOut(g);
    const shown = g.pic.heroShown(&g.sim).?;
    for (statuses, turns) |s, t| {
        try std.testing.expectEqual(t - 1, shown.status.get(s));
        try std.testing.expect(s.about().len > 0);
    }
    try std.testing.expectEqual(@as(u8, 1), shown.sunder.stacks);
    std.debug.print("afflictions: {d} statuses shown in HUD order, each a turn down once the turn is drawn\n", .{statuses.len});
}

test "afflictions survive a save and load, and an impossible sunder is refused" {
    const alloc = std.testing.allocator;
    const g = try game.boot(alloc);
    defer game.shut(alloc, g);
    game.begin(g, 1);
    const hero = g.sim.heroActor().?;
    hero.shock.turns = 2;
    hero.sunder = .{ .stacks = 2, .turns = 3 };
    hero.blind.turns = 1;
    hero.confusion.turns = 3;
    const back = try game.boot(alloc);
    defer game.shut(alloc, back);
    game.begin(back, 2);
    const map = try alloc.create(data.Map);
    defer alloc.destroy(map);
    var bytes = std.ArrayList(u8).init(alloc);
    defer bytes.deinit();
    try sealed(g, &bytes);
    try format.read(bytes.items, back, map);
    const loaded = back.sim.heroActor().?;
    try std.testing.expectEqual(hero.shock, loaded.shock);
    try std.testing.expectEqual(hero.sunder, loaded.sunder);
    try std.testing.expectEqual(hero.blind, loaded.blind);
    try std.testing.expectEqual(hero.confusion, loaded.confusion);
    hero.sunder.stacks = sunder.MOST + 1;
    bytes.clearRetainingCapacity();
    try sealed(g, &bytes);
    try std.testing.expectError(error.Damaged, format.read(bytes.items, back, map));
    try std.testing.expectEqual(@as(u8, 2), back.sim.heroActor().?.sunder.stacks);
    std.debug.print("afflictions: shock, sunder, blind and confusion round-trip; {d} sunder stacks refused before load\n", .{sunder.MOST + 1});
}

fn sealed(g: *game.Game, out: *std.ArrayList(u8)) !void {
    try format.write(g, out);
    try store.seal(out.writer(), out.items[store.head(format.MAGIC)..]);
}
