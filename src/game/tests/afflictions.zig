const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const store = @import("../../core/store.zig");
const actor = @import("../../play/actor.zig");
const blind = @import("../../play/blind.zig");
const confusion = @import("../../play/confusion.zig");
const shock = @import("../../play/shock.zig");
const sunder = @import("../../play/sunder.zig");
const enfeeble = @import("../../play/enfeeble.zig");
const maim = @import("../../play/maim.zig");
const fx = @import("../../gfx/fx.zig");
const hud = @import("../../ui/hud.zig");
const format = @import("../../save_format.zig");
const data = @import("../../save_data.zig");
const attacks = @import("../attacks.zig");
const character = @import("../character.zig");
const combat = @import("../combat.zig");
const harness = @import("../harness.zig");
const grid = @import("../../map/grid.zig");
const game = @import("../../game.zig");
const P = mathx.P;

const FROM = P{ .x = 20, .y = 20 };
const EAST = FROM.add(.{ .x = 1, .y = 0 });
const TRIES: usize = 400;
/// Of the eight ways a stray picks from, one is the way it meant.
const STRAY_PERCENT = confusion.CHANCE * 7 / 8;

fn strayedAbout(strayed: usize) bool {
    return harness.aboutRateOf(strayed, TRIES, mathx.fraction(STRAY_PERCENT));
}

test "a shock adds half again to the next hit on either side, then is spent" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{.{ .x = 23, .y = 20 }});
    const target = g.sim.pool.get(harness.foeId(0)).?;
    harness.setLife(target, 50, 50);
    target.shock.start();
    const blow = attacks.Roll{ .dmg = 4, .hit_checked = true };
    try std.testing.expectEqual(@as(i32, 6), attacks.resolve(&g.sim, .fromInt(harness.foeId(0)), blow, .chosen).?.hit.damage.dmg);
    try std.testing.expectEqual(@as(u8, 0), target.shock.turns);
    try std.testing.expectEqual(@as(i32, 4), attacks.resolve(&g.sim, .fromInt(harness.foeId(0)), blow, .chosen).?.hit.damage.dmg);

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

test "hero blindness does not hide it from unblinded foes beyond adjacent cells" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const ahead = FROM.add(.{ .x = 3, .y = 0 });
    const between = FROM.add(.{ .x = 1, .y = 0 });
    for (0..3) |obstacle| {
        harness.arena(g, FROM, &.{});
        const id = harness.spawnAt(g, .rat, ahead, false);
        if (obstacle == 1) {
            for (0..@intCast(grid.H)) |y| g.sim.lv.set(.{ .x = between.x, .y = @intCast(y) }, .wall);
        } else if (obstacle == 2) {
            for (0..@intCast(grid.H)) |y| g.sim.lv.smoke[grid.Level.idx(.{ .x = between.x, .y = @intCast(y) })] = 60000;
        }
        blind.afflict(g.sim.heroActor().?, &g.sim.rng);
        game.castSight(g, FROM);
        try std.testing.expect(!g.sim.lv.inLos(ahead));
        combat.endTurn(g);
        try std.testing.expectEqual(obstacle == 0, g.sim.pool.get(id).?.awake);
        try std.testing.expect(!g.sim.lv.isLit(ahead));
    }
    std.debug.print("blind hero: an unblinded rat notices across open floor; walls and thick smoke still hide the hero\n", .{});
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
    enfeeble.afflict(hero, &g.sim.rng);
    maim.afflict(hero, &g.sim.rng);
    g.pic.catchUp(&g.sim);
    const statuses = [_]fx.Status{ .shocked, .sundered, .blinded, .confused, .enfeebled, .maimed };
    const turns = [_]u8{ shock.TURNS, sunder.TURNS, blind.TURNS, confusion.TURNS, enfeeble.TURNS, maim.TURNS };
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
    hero.enfeeble.turns = 2;
    hero.maim = .{ .turns = 3, .limp = true };
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
    try std.testing.expectEqual(hero.enfeeble, loaded.enfeeble);
    try std.testing.expectEqual(hero.maim, loaded.maim);
    hero.sunder.stacks = sunder.MOST + 1;
    bytes.clearRetainingCapacity();
    try sealed(g, &bytes);
    try std.testing.expectError(error.Damaged, format.read(bytes.items, back, map));
    try std.testing.expectEqual(@as(u8, 2), back.sim.heroActor().?.sunder.stacks);
    hero.sunder.stacks = 2;
    hero.maim = .{ .limp = true };
    bytes.clearRetainingCapacity();
    try sealed(g, &bytes);
    try std.testing.expectError(error.Damaged, format.read(bytes.items, back, map));
    std.debug.print("afflictions: shock, sunder, blind, confusion, enfeeble and maim round-trip; {d} sunder stacks and a limp with no maim refused before load\n", .{sunder.MOST + 1});
}

test "an enfeebled body's blows deal 30% less, rounded up, on either side" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{.{ .x = 23, .y = 20 }});
    harness.setLife(g.sim.pool.get(harness.foeId(0)).?, 50, 50);
    const blow = attacks.Roll{ .dmg = 10, .hit_checked = true };
    enfeeble.afflict(g.sim.heroActor().?, &g.sim.rng);
    try std.testing.expectEqual(@as(i32, 7), attacks.resolve(&g.sim, .fromInt(harness.foeId(0)), blow, .chosen).?.hit.damage.dmg);

    var lost: [2]i32 = undefined;
    for ([_]bool{ false, true }, &lost) |weak, *out| {
        harness.arena(g, FROM, &.{});
        harness.toughen(g.sim.heroActor().?);
        const id = harness.openMimic(g, EAST);
        if (weak) enfeeble.afflict(g.sim.pool.get(id).?, &g.sim.rng);
        g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = true }});
        combat.endTurn(g);
        out.* = harness.TEST_HP - g.sim.heroActor().?.hp;
    }
    try std.testing.expect(lost[0] > 0);
    try std.testing.expectEqual(enfeeble.weaken(true, lost[0]), lost[1]);
    std.debug.print("enfeeble: the archer's 10-damage blow deals 7; a mimic's bite of {d} deals {d} enfeebled\n", .{ lost[0], lost[1] });
}

test "a blow's ailment check sees it as the enfeebled hero and the target's shock will deal it, spending nothing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{.{ .x = 23, .y = 20 }});
    const target = g.sim.pool.get(harness.foeId(0)).?;
    harness.setLife(target, 10, 10);
    enfeeble.afflict(g.sim.heroActor().?, &g.sim.rng);
    const weak = attacks.dealt(&g.sim, target, 10, .bleed);
    target.shock.start();
    const shocked = attacks.dealt(&g.sim, target, 10, .bleed);
    const shocking = attacks.dealt(&g.sim, target, 10, .shock);
    std.debug.print("ailment check on a 10 hp foe: an enfeebled 10 deals {d}; shocked {d}; a shocking blow {d}\n", .{ weak, shocked, shocking });
    try std.testing.expectEqual(enfeeble.weaken(true, 10), weak);
    try std.testing.expectEqual(mathx.percentCeil(weak, mathx.PERCENT + shock.MORE), shocked);
    try std.testing.expectEqual(weak, shocking);
    try std.testing.expect(target.shock.turns > 0);
    try std.testing.expectEqual(weak, attacks.resolve(&g.sim, .fromInt(harness.foeId(0)), .{ .dmg = 10, .hit_checked = true, .applied = .shock }, .chosen).?.hit.damage.dmg);
}

test "a maimed foe loses a turn to every second step, closing on the hero a step slower over its four turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const start = FROM.add(.{ .x = 7, .y = 0 });
    var gap: [2][maim.TURNS]i32 = undefined;
    for ([_]bool{ false, true }, &gap) |maimed, *row| {
        harness.arena(g, FROM, &.{});
        const id = harness.spawnAt(g, .rat, start, true);
        if (maimed) maim.afflict(g.sim.pool.get(id).?, &g.sim.rng);
        for (row) |*d| {
            combat.endTurn(g);
            d.* = mathx.dist(g.sim.pool.get(id).?.at, FROM);
        }
        if (maimed) try std.testing.expectEqualDeep(maim.Maim{}, g.sim.pool.get(id).?.maim);
    }
    try std.testing.expectEqualSlices(i32, &.{ 6, 5, 4, 3 }, &gap[0]);
    try std.testing.expectEqualSlices(i32, &.{ 6, 5, 5, 4 }, &gap[1]);
    std.debug.print("maimed rat: {any} cells off over {d} turns against {any} unmaimed\n", .{ gap[1], maim.TURNS, gap[0] });
}

test "a maimed hero's second step costs its next turn, which passes on its own" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, FROM, &.{});
    const hero = g.sim.heroActor().?;
    maim.afflict(hero, &g.sim.rng);
    game.heroStep(g, .e, 0);
    try std.testing.expect(!hero.clock.owes());
    harness.drawnOut(g);
    game.heroStep(g, .e, 0);
    try std.testing.expect(hero.clock.owes());
    try std.testing.expect(harness.logged(g, maim.LIMPS));
    const minutes = g.sim.clock;
    harness.drawnOut(g);
    harness.idle(g);
    try std.testing.expect(!g.sim.heroActor().?.clock.owes());
    try std.testing.expect(!std.meta.eql(minutes, g.sim.clock));
    try std.testing.expectEqual(FROM.add(.{ .x = 2, .y = 0 }), g.sim.heroAt().?);
    std.debug.print("maimed hero: 2 steps, the second costing the turn after it, which passed unbidden\n", .{});
}

test "lightning striking a body in water shocks every body wading in the water joined to it within reach, the hero too" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const struck = P{ .x = 24, .y = 20 };
    const near = P{ .x = 26, .y = 20 };
    const past = P{ .x = 27, .y = 20 };
    const apart = P{ .x = 24, .y = 23 };
    for ([_]bool{ false, true }) |wading| {
        const hero_at = if (wading) P{ .x = 22, .y = 20 } else FROM;
        harness.heroArena(g, .wizard, hero_at, &.{});
        var x: i32 = 22;
        while (x <= 28) : (x += 1) g.sim.lv.set(.{ .x = x, .y = 20 }, .shallows);
        if (!wading) g.sim.lv.set(.{ .x = 22, .y = 20 }, .floor);
        g.sim.lv.set(apart, .shallows);
        var ids: [4]u16 = undefined;
        for ([_]P{ struck, near, past, apart }, &ids) |p, *id| {
            id.* = harness.spawnAt(g, .rat, p, false);
            harness.toughen(g.sim.pool.get(id.*).?);
        }
        game.castSight(g, hero_at);
        harness.aimAt(g, .spark, struck);
        try std.testing.expect(g.sim.pool.get(ids[0]).?.hp < harness.TEST_HP);
        try std.testing.expect(harness.logged(g, shock.CONDUCTS));
        const shocked = [_]bool{ true, true, false, false };
        for (ids, shocked) |id, want| try std.testing.expectEqual(want, g.sim.pool.get(id).?.shock.turns > 0);
        try std.testing.expectEqual(wading, g.sim.heroActor().?.shock.turns > 0);
    }
    std.debug.print("conducted spark: the struck rat and one 2 cells along the water shocked; one 3 along and one in other water spared; the hero shocked only wading in it\n", .{});
}

test "a slime half split off by a conducting blow carries the shock its parent takes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.heroArena(g, .wizard, FROM, &.{});
    const struck = P{ .x = 24, .y = 20 };
    var cells = grid.Cells.around(struck, 1);
    while (cells.next()) |p| g.sim.lv.set(p, .shallows);
    const id = harness.spawnAt(g, .slime, struck, false);
    harness.setLife(g.sim.pool.get(id).?, 20, 20);
    const born = g.sim.pool.n;
    var blow = attacks.Rolled{ .blow = .{} };
    blow.blow.elements.set(.lightning, 12);
    combat.arrowHit(g, id, blow, .spark, .{ .from = FROM, .wait = 0.2 });
    try std.testing.expectEqual(born + 1, g.sim.pool.n);
    const parent = g.sim.pool.get(id).?;
    const half = &g.sim.pool.items[born];
    try std.testing.expect(parent.shock.turns > 0);
    try std.testing.expectEqual(parent.shock, half.shock);
    std.debug.print("conducted split: a 20 hp slime struck for 12 in shallows splits; parent and half both shocked for {d} turns\n", .{half.shock.turns});
}

fn sealed(g: *game.Game, out: *std.ArrayList(u8)) !void {
    try format.write(g, out);
    try store.seal(out.writer(), out.items[store.head(format.MAGIC)..]);
}
