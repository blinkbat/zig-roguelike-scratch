const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const gen = @import("../../map/gen.zig");
const gas = @import("../../map/gas.zig");
const menu = @import("../../ui/menu.zig");
const actor = @import("../../play/actor.zig");
const bow = @import("../../play/bow.zig");
const bleeding = @import("../../play/bleeding.zig");
const glacial = @import("../../play/glacial.zig");
const pack = @import("../../play/pack.zig");
const fx = @import("../../gfx/fx.zig");
const combat = @import("../combat.zig");
const attacks = @import("../attacks.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const P = mathx.P;
const CONFIRM = menu.CONFIRM;
const HERO = actor.HERO;

test "thorns returns melee damage with the incoming impact and ignores dodges and arrows" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    inline for (.{ actor.Kind.rat, actor.Kind.bandit_crossbowman }) |kind| {
        for ([_]bool{ false, true }) |hit| {
            harness.arena(g, from, &.{});
            g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, null, null, null } });
            const id = harness.spawnAt(g, kind, from.add(.{ .x = if (kind == .rat) 1 else 4, .y = 0 }), true);
            game.settle(g);
            const slot = actor.Pool.slot(id);
            const hp = g.sim.pool.get(id).?.hp;
            const hero_hp = g.sim.heroActor().?.hp;
            g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = hit }});
            combat.endTurn(g);
            const expected: i32 = if (kind == .rat and hit) 2 else 0;
            try std.testing.expectEqual(hp - expected, g.sim.pool.get(id).?.hp);
            try std.testing.expectEqual(expected > 0, g.pic.owed[slot].thorns != null);
            try std.testing.expectEqual(hp, g.pic.pictured[slot].hp);
            harness.stagger(g);
            if (expected > 0) {
                const impact = g.pic.fx.landsIn(slot);
                try std.testing.expectApproxEqAbs(impact, g.pic.fx.landsIn(g.sim.heroSlot().?), 0.0001);
                game.update(g, impact - 0.001);
                try std.testing.expectEqual(hp, g.pic.pictured[slot].hp);
                try std.testing.expectEqual(hero_hp, g.pic.pictured[g.sim.heroSlot().?].hp);
                game.update(g, 0.002);
                try std.testing.expectEqual(hp - expected, g.pic.pictured[slot].hp);
                try std.testing.expect(g.pic.pictured[g.sim.heroSlot().?].hp < hero_hp);
            }
            harness.drawnOut(g);
            try std.testing.expectEqual(hp - expected, g.pic.pictured[slot].hp);
        }
    }
    std.debug.print("Thorns: melee hit/dodge and ranged hit/dodge, both bodies change at the same impact\n", .{});
}

test "thorns still returns a connected melee hit rounded to zero by hero armour" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var absorbed: usize = 0;
    for (0..64) |seed| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, .{ .kind = .armour, .value = 75 }, null, null } });
        const id = harness.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, true);
        game.settle(g);
        const hero_hp = g.sim.heroActor().?.hp;
        const foe_hp = g.sim.pool.get(id).?.hp;
        g.sim.rng = mathx.Rng.init(seed);
        combat.endTurn(g);
        const slot = actor.Pool.slot(id);
        if (g.pic.owed[slot].bit.? == .miss) continue;
        if (g.sim.heroActor().?.hp != hero_hp) continue;
        absorbed += 1;
        try std.testing.expectEqual(foe_hp - 2, g.sim.pool.get(id).?.hp);
        try std.testing.expect(g.pic.owed[slot].thorns != null);
        harness.stagger(g);
        harness.drawnOut(g);
        try std.testing.expectEqual(foe_hp - 2, g.pic.pictured[slot].hp);
        try std.testing.expectEqual(hero_hp, g.pic.heroShown(&g.sim).?.hp);
    }
    try std.testing.expect(absorbed > 0);
    std.debug.print("Thorns: {d} connected hits fully absorbed by armour still retaliate at impact over 64 seeds\n", .{absorbed});
}

test "thorns kills grant rewards and harvest after a shielded hit without blow recovery" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |lethal_hero| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, null, null, null } });
        g.sim.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .life_on_kill, .value = 2 }, null, null, null } });
        const id = harness.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, true);
        g.sim.pool.get(id).?.hp = 1;
        const hero = g.sim.heroActor().?;
        hero.hp = if (lethal_hero) 1 else hero.max - 3;
        if (!lethal_hero) hero.ward.turns = 2;
        const hp = hero.hp;
        game.settle(g);
        const kills = g.sim.kills;
        g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = true }});
        combat.endTurn(g);
        try std.testing.expect(g.sim.pool.get(id) == null);
        try std.testing.expectEqual(kills + 1, g.sim.kills);
        try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].thorns.?.kill);
        if (lethal_hero) {
            try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
            try std.testing.expect(g.sim.heroActor() == null);
        } else {
            try std.testing.expectEqual(hp + 2, g.sim.heroActor().?.hp);
            try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].thorns.?.recovery != null);
        }
        harness.stagger(g);
        harness.drawnOut(g);
        try std.testing.expect(!g.pic.standing(&g.sim, actor.Pool.slot(id)));
    }
    std.debug.print("Thorns: shield absorption and simultaneous death, rewards and delayed Harvest recovery checked\n", .{});
}

test "retaliation kills do not replace the last arrow in the death report" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var deaths: usize = 0;
    for (0..16) |seed| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, null, null, null } });
        const rat = harness.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, true);
        g.sim.pool.get(rat).?.hp = 1;
        const target = harness.spawnAt(g, .bandit_crossbowman, .{ .x = 20, .y = 24 }, false);
        harness.toughen(g.sim.pool.get(target).?);
        g.sim.pool.get(target).?.clock.stun();
        g.sim.heroActor().?.hp = 1;
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        const skills = @import("../skills.zig");
        skills.useSkill(g, .{ .act = .shoot, .by = .x });
        g.mode.aim.mark = g.sim.pool.get(target).?.at;
        skills.confirmAim(g);
        if (g.mode != .dead) continue;
        deaths += 1;
        try std.testing.expect(g.sim.pool.get(rat) == null);
        const report = g.epitaph.?.text();
        try std.testing.expect(std.mem.indexOf(u8, report, "last arrow hit a bandit crossbowman without killing it") != null);
        try std.testing.expect(std.mem.indexOf(u8, report, "last arrow killed a rat") == null);
    }
    try std.testing.expect(deaths > 0);
    std.debug.print("death reports: {d} lethal thorns turns preserve the arrow's actual target across 16 seeds\n", .{deaths});
}

test "thorns respects armour splits slimes and coexists with unyielding counters" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    var counters: usize = 0;
    var reduced: usize = 0;
    for (0..40) |seed| {
        harness.heroArena(g, .knight, from, &.{});
        g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, null, null, null } });
        const id = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        combat.endTurn(g);
        if (g.pic.owed[actor.Pool.slot(id)].thorns) |debt| {
            const loss = actor.row(.beefy_pib).hp - debt.after.body.hp;
            try std.testing.expect(loss == 1 or loss == 2);
            if (loss == 1) reduced += 1;
        }
        harness.heroArena(g, .knight, from, &.{});
        g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, null, null, null } });
        const rat = harness.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, true);
        harness.toughen(g.sim.pool.get(rat).?);
        g.sim.heroActor().?.tactics.unyielding = true;
        g.sim.growth.ranks.set(.unyielding, 3);
        g.sim.mana = 100;
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        combat.endTurn(g);
        const debt = g.pic.owed[actor.Pool.slot(rat)];
        if (debt.thorns != null and debt.reaction != null) {
            counters += 1;
            try std.testing.expect(debt.thorns.?.after.body.hp > debt.reaction.?.outcome.hit.after.?.body.hp);
            harness.stagger(g);
            harness.drawnOut(g);
            try std.testing.expectEqual(g.sim.pool.get(rat).?.hp, g.pic.pictured[actor.Pool.slot(rat)].hp);
        }
    }
    try std.testing.expect(reduced > 0 and counters > 0);
    harness.arena(g, from, &.{});
    g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, null, null, null } });
    const slime = harness.spawnAt(g, .slime, .{ .x = 21, .y = 20 }, true);
    g.sim.pool.get(slime).?.hp = 5;
    game.settle(g);
    g.sim.rng = harness.bitesRng(g, &.{.{ .id = slime, .lands = true }});
    combat.endTurn(g);
    try std.testing.expectEqual(@as(usize, 2), g.sim.pool.tally(.slime).left);
    try std.testing.expect(g.pic.owed[actor.Pool.slot(slime)].thorns.?.after.reveals != null);
    harness.stagger(g);
    harness.drawnOut(g);
    std.debug.print("Thorns: {d} armour reductions, {d} separate counters across 40 seeds, one inherited slime split\n", .{ reduced, counters });
}

/// Long enough that most of a turn's blows land before the next, so splits show.
const SOAK_DT: f32 = 0.1;

fn ratsHp(g: *game.Game) i32 {
    var hp: i32 = 0;
    for (g.sim.pool.slice()) |a| {
        if (a.kind == .rat) hp += a.hp;
    }
    return hp;
}

test "a new floor has every pack placed, no foe in sight or on a barrel" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for (0..40) |i| {
        game.begin(g, 0xF00D +% i *% grid.TEST_SEED_STRIDE);
        var placed: usize = 0;
        for (actor.FOES) |k| {
            const t = g.sim.pool.tally(k);
            try std.testing.expectEqual(t.total, t.left);
            placed += t.total;
        }
        try std.testing.expect(placed >= pack.PER_FLOOR);
        const h = g.sim.heroActor().?;
        for (harness.foes(g)) |a| {
            try std.testing.expect(!g.sim.lv.isLit(a.at));
            try std.testing.expect(!g.sim.lv.hasBarrel(a.at));
            try std.testing.expect(mathx.dist(a.at, h.at) >= pack.GAP);
        }
    }
}

test "a crossbowman notices then shoots at the player's arrow range and closes only when out of range" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const hero = P{ .x = 20, .y = 20 };
    const at = hero.add(.{ .x = bow.RANGE, .y = 0 });
    harness.arena(g, hero, &.{});
    const id = harness.spawnAt(g, .bandit_crossbowman, at, false);
    const slot = actor.Pool.slot(id);
    game.settle(g);
    const hp = g.sim.heroActor().?.hp;
    combat.endTurn(g);
    try std.testing.expect(g.sim.pool.get(id).?.awake);
    try std.testing.expect(g.pic.owed[slot].arrow == null);
    g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = true }});
    combat.endTurn(g);
    try std.testing.expectEqual(at, g.sim.pool.get(id).?.at);
    try std.testing.expectEqual(@as(usize, bow.RANGE), g.pic.owed[slot].arrow.?.len);
    try harness.expectWithin(hp - g.sim.heroActor().?.hp, bow.BASE.lo, bow.BASE.hi);
    harness.arena(g, hero, &.{});
    const far = at.add(.{ .x = 1, .y = 0 });
    const far_id = harness.spawnAt(g, .bandit_crossbowman, far, true);
    game.settle(g);
    combat.endTurn(g);
    try std.testing.expectEqual(bow.RANGE, mathx.dist(g.sim.pool.get(far_id).?.at, hero));
    try std.testing.expect(g.pic.owed[actor.Pool.slot(far_id)].arrow == null);
    try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
    std.debug.print("crossbowman: notices before firing, shoots at {d} tiles for {d}-{d}, closes from {d}\n", .{ bow.RANGE, bow.BASE.lo, bow.BASE.hi, bow.RANGE + 1 });
}

test "crossbowman arrows respect terrain bodies containers darkness and diagonal gaps" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const Case = enum { wall, barrel, chest, rat, darkness, water, open_chest, diagonal };
    var fired: usize = 0;
    for (std.enums.values(Case)) |case| {
        const hero = P{ .x = 20, .y = 20 };
        const at = P{ .x = if (case == .darkness) 28 else 26, .y = if (case == .diagonal) 26 else 20 };
        const middle = P{ .x = 23, .y = 20 };
        harness.arena(g, hero, &.{});
        const id = harness.spawnAt(g, .bandit_crossbowman, at, true);
        g.sim.pool.get(id).?.pin.turns = 2;
        switch (case) {
            .wall => g.sim.lv.set(middle, .wall),
            .barrel => g.sim.lv.putBarrel(middle),
            .chest => g.sim.lv.set(middle, .chest),
            .rat => {
                const rat = harness.spawnAt(g, .rat, middle, false);
                g.sim.pool.get(rat).?.pin.turns = 2;
            },
            .darkness => g.sim.outdoors = false,
            .water => g.sim.lv.set(middle, .water),
            .open_chest => g.sim.lv.set(middle, .chest_open),
            .diagonal => {
                g.sim.lv.set(.{ .x = 23, .y = 24 }, .wall);
                g.sim.lv.set(.{ .x = 24, .y = 23 }, .wall);
            },
        }
        game.settle(g);
        const hp = g.sim.heroActor().?.hp;
        const expected = case == .water or case == .open_chest or case == .diagonal or case == .darkness;
        g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = true }});
        combat.endTurn(g);
        const flight = g.pic.owed[actor.Pool.slot(id)].arrow;
        if (expected != (flight != null)) std.debug.print("unexpected arrow in {s} case\n", .{@tagName(case)});
        try std.testing.expectEqual(expected, flight != null);
        try std.testing.expectEqual(expected, g.sim.heroActor().?.hp < hp);
        try std.testing.expectEqual(at, g.sim.pool.get(id).?.at);
        if (flight) |f| {
            fired += 1;
            try std.testing.expectEqual(g.sim.hero, f.struck.?.body);
            try std.testing.expectEqual(hero, f.impact().?);
        }
    }
    std.debug.print("crossbowman arrows: {d} obstruction/visibility cases, {d} clear shots\n", .{ std.enums.values(Case).len, fired });
}

test "a crossbowman retreats when crowded and fires when pinned or cornered" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const hero = P{ .x = 20, .y = 20 };
    const retreat = actor.row(.bandit_crossbowman).ranged.?.retreat;
    var distance: i32 = 1;
    while (distance <= retreat) : (distance += 1) {
        harness.arena(g, hero, &.{});
        const id = harness.spawnAt(g, .bandit_crossbowman, hero.add(.{ .x = distance, .y = 0 }), true);
        game.settle(g);
        const hp = g.sim.heroActor().?.hp;
        combat.endTurn(g);
        try std.testing.expectEqual(distance + 1, mathx.dist(hero, g.sim.pool.get(id).?.at));
        try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
        try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].arrow == null);
    }
    for ([_]bool{ false, true }) |pinned| {
        harness.arena(g, hero, &.{});
        const at = hero.add(.{ .x = 1, .y = 0 });
        const id = harness.spawnAt(g, .bandit_crossbowman, at, true);
        if (pinned) {
            g.sim.pool.get(id).?.pin.turns = 2;
        } else {
            for (mathx.ALL_DIRS) |d| {
                const cell = at.add(d.delta());
                if (!cell.eq(hero)) g.sim.lv.set(cell, .wall);
            }
        }
        game.settle(g);
        const hp = g.sim.heroActor().?.hp;
        g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = true }});
        combat.endTurn(g);
        try std.testing.expectEqual(at, g.sim.pool.get(id).?.at);
        try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].arrow != null);
        try std.testing.expect(g.sim.heroActor().?.hp < hp);
    }
    std.debug.print("crossbowman: {d} close ranges retreat without firing; pin and dead end hold position and fire\n", .{retreat});
}

test "a crossbowman with its shot blocked holds outside its retreat instead of shuttling in and out" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const hero = P{ .x = 20, .y = 20 };
    harness.arena(g, hero, &.{});
    g.sim.unkillable = true;
    const retreat = actor.row(.bandit_crossbowman).ranged.?.retreat;
    const rat = harness.spawnAt(g, .rat, hero.add(.{ .x = 1, .y = 0 }), true);
    g.sim.pool.get(rat).?.pin.turns = 100;
    const id = harness.spawnAt(g, .bandit_crossbowman, hero.add(.{ .x = retreat + 1, .y = 0 }), true);
    game.settle(g);
    var nearest: i32 = std.math.maxInt(i32);
    for (0..6) |_| {
        combat.endTurn(g);
        nearest = @min(nearest, mathx.dist(hero, g.sim.pool.get(id).?.at));
    }
    std.debug.print("crossbowman behind a rat: nearest {d} over 6 turns, retreat {d}\n", .{ nearest, retreat });
    try std.testing.expect(nearest > retreat);
}

test "a crossbowman's stun and chill skip shots while retreat avoids gas and ticks movement bleed" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |chilled| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = harness.spawnAt(g, .bandit_crossbowman, .{ .x = 26, .y = 20 }, true);
        const a = g.sim.pool.get(id).?;
        if (chilled) a.chill = .{ .turns = 2, .phase = glacial.CYCLE - 1 } else a.clock.stun();
        game.settle(g);
        const hp = g.sim.heroActor().?.hp;
        combat.endTurn(g);
        try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
        try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].arrow == null);
    }
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .bandit_crossbowman, .{ .x = 22, .y = 20 }, true);
    const a = g.sim.pool.get(id).?;
    a.bleed = .{ .turns = 2 };
    g.sim.lv.addGas(.{ .x = 23, .y = 19 }, gas.GASSED_UP - 1);
    game.settle(g);
    const hp = a.hp;
    combat.endTurn(g);
    try std.testing.expect(!g.sim.lv.gassy(a.at));
    try std.testing.expectEqual(actor.row(.bandit_crossbowman).ranged.?.retreat + 1, mathx.dist(a.at, g.sim.heroActor().?.at));
    try std.testing.expectEqual(bleeding.MOVING, hp - a.hp);
    std.debug.print("crossbowman: stun/chill skip 2 shots; retreat avoids gas and takes {d} movement bleed\n", .{bleeding.MOVING});
}

test "crossbowman arrows present separate hits on arrival and stay busy through the last flight" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const near = harness.spawnAt(g, .bandit_crossbowman, .{ .x = 23, .y = 20 }, true);
    const far = harness.spawnAt(g, .bandit_crossbowman, .{ .x = 20, .y = 27 }, true);
    game.settle(g);
    const hero = g.sim.heroSlot().?;
    const hp = g.sim.heroActor().?.hp;
    g.sim.rng = harness.bitesRng(g, &.{ .{ .id = near, .lands = true }, .{ .id = far, .lands = true } });
    harness.use(g, .wait);
    const first = g.pic.foe_shots[actor.Pool.slot(near)].?;
    const last = g.pic.foe_shots[actor.Pool.slot(far)].?;
    const first_hit = -first.t + first.lands();
    const last_hit = -last.t + last.lands();
    try std.testing.expect(first_hit > 0 and last_hit > first_hit);
    try std.testing.expect(g.pic.busy >= -last.t + last.ends());
    try std.testing.expect(g.pic.glide[actor.Pool.slot(near)].bump == null);
    try std.testing.expectEqual(hp, g.pic.pictured[hero].hp);
    g.st = .{};
    game.update(g, first_hit - 0.001);
    try std.testing.expectEqual(hp, g.pic.pictured[hero].hp);
    game.update(g, 0.002);
    const between = g.pic.pictured[hero].hp;
    try std.testing.expect(between < hp and between > g.sim.heroActor().?.hp);
    try std.testing.expect(!g.pic.quiet());
    game.update(g, last_hit - first_hit);
    try std.testing.expectEqual(g.sim.heroActor().?.hp, g.pic.pictured[hero].hp);
    harness.drawnOut(g);
    try std.testing.expect(g.pic.quiet());
    for (g.pic.foe_shots) |s| try std.testing.expect(s == null);
    std.debug.print("2 crossbowman arrows: hits at {d:.3}/{d:.3}s, pictured HP {d}/{d}/{d}\n", .{ first_hit, last_hit, hp, between, g.pic.pictured[hero].hp });
}

test "crossbowman arrows can be dodged and mana shield harm waits for the arrow" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |shielded| {
        harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
        const id = harness.spawnAt(g, .bandit_crossbowman, .{ .x = 26, .y = 20 }, true);
        if (shielded) g.sim.heroActor().?.ward.turns = 2;
        game.settle(g);
        const hp = g.sim.heroActor().?.hp;
        const mana = g.sim.mana;
        g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = shielded }});
        harness.use(g, .wait);
        try std.testing.expect(g.pic.foe_shots[actor.Pool.slot(id)] != null);
        try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
        try std.testing.expectEqual(shielded, g.sim.mana < mana);
        try std.testing.expectEqual(mana, g.sim.mana + g.pic.mana_held);
        harness.drawnOut(g);
        try std.testing.expectEqual(@as(i32, 0), g.pic.mana_held);
    }
    std.debug.print("crossbowman arrows: 1 dodge and 1 mana-shield impact preserve HP and clear their flights\n", .{});
}

test "a rat that sees you notices, closes and bites" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 26, .y = 20 }});
    var noticed: ?usize = null;
    var contact: ?usize = null;
    for (0..12) |turn| {
        combat.endTurn(g);
        const r = g.sim.pool.get(2).?;
        if (noticed == null and r.awake) noticed = turn;
        if (contact == null and mathx.dist(r.at, g.sim.heroActor().?.at) == 1) contact = turn;
    }
    const lost = actor.row(HERO).hp - g.sim.heroActor().?.hp;
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
    const lost = actor.row(HERO).hp - g.sim.heroActor().?.hp;
    std.debug.print("slime slam: {d} hp\n", .{lost});
    try harness.expectWithin(lost, slam.hit.lo, slam.hit.hi);
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.sim.pool.get(id).?.at);
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
        for (harness.foes(g)) |a| {
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

test "foes act nearest first, so the one behind in a corridor follows the one ahead" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 20 }, .{ .x = 24, .y = 20 } });
    harness.wallRow(&g.sim.lv, 19, 21, 29);
    harness.wallRow(&g.sim.lv, 21, 21, 29);
    harness.wakeFoes(g);
    combat.endTurn(g);
    std.debug.print("corridor: nearer rat to {d}, the one behind to {d}\n", .{ g.sim.pool.get(3).?.at.x, g.sim.pool.get(2).?.at.x });
    try std.testing.expectEqualSlices(u16, &.{ 3, 2 }, g.sim.order[0..g.sim.order_n]);
    try std.testing.expectEqual(@as(i32, 23), g.sim.pool.get(3).?.at.x);
    try std.testing.expectEqual(@as(i32, 24), g.sim.pool.get(2).?.at.x);
}

test "a bloat beside the archer bursts on it about two turns in three, and never bites" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    var bursts: usize = 0;
    for (0..harness.TRIES) |i| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = harness.spawnAt(g, .bloat, at, true);
        g.sim.rng = mathx.Rng.init(i);
        combat.endTurn(g);
        try std.testing.expect(!g.sim.heroActor().?.hurt());
        if (g.sim.pool.get(id) != null) continue;
        bursts += 1;
        try std.testing.expectEqual(gas.BURST, g.sim.lv.gasAt(at));
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
        for (mathx.ALL_DIRS) |d| g.sim.lv.set(hero.add(d.delta()), .wall);
        const id = harness.spawnAt(g, .bloat, at, true);
        g.sim.rng = mathx.Rng.init(i);
        combat.endTurn(g);
        if (!g.sim.pool.get(id).?.at.eq(at)) moved += 1;
    }
    std.debug.print("a bloat walled off from the archer flits on {d} of {d} turns\n", .{ moved, harness.TRIES });
    try std.testing.expect(harness.aboutRate(moved, actor.FLIT));
}

test "an arrow bursts a bloat where it floats, and its gas reaches the archer and eats at it every turn after" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .bloat, .{ .x = 24, .y = 20 }, false);
    g.sim.pool.get(id).?.hp = 1;
    harness.confirmUse(g, .shoot);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(id));
    try std.testing.expectEqual(@as(usize, 1), g.sim.kills);
    const per = gas.harm(actor.row(HERO).hp);
    var first: ?usize = null;
    for (1..11) |turn| {
        const before = g.sim.heroActor().?.hp;
        harness.use(g, .wait);
        const lost = before - g.sim.heroActor().?.hp;
        if (first == null and lost > 0) first = turn;
        try std.testing.expectEqual(if (first == null) 0 else per, lost);
        if (lost > 0) try std.testing.expect(g.pic.fx.flashOf(g.sim.heroSlot().?) > 0);
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
    g.sim.pool.get(near).?.hp = 1;
    harness.confirmUse(g, .shoot);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(near));
    var waited: usize = 0;
    while (g.sim.pool.get(far) != null and waited < 20) : (waited += 1) harness.use(g, .wait);
    std.debug.print("a bloat beside one shot dead bursts {d} turns later\n", .{waited});
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(far));
    try std.testing.expectEqual(@as(usize, 2), g.sim.kills);
}

test "a slime split this turn acts from the next, and one a blow kills outright splits nothing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .slime, .{ .x = 21, .y = 20 }, true);
    g.sim.pool.get(id).?.hp = harness.SLIME_HALF;
    harness.nudge(g, .e);
    try std.testing.expectEqual(actor.Kind.slime_half, g.sim.pool.get(id).?.kind);
    try std.testing.expectEqualSlices(u16, &.{id}, g.sim.order[0..g.sim.order_n]);
    const other = id + 1;
    try std.testing.expect(!g.sim.pool.get(other).?.waits);
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(usize, 2), g.sim.order_n);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const one = harness.spawnAt(g, .slime, .{ .x = 25, .y = 20 }, false);
    g.sim.pool.get(one).?.hp = bow.BASE.lo;
    harness.confirmUse(g, .shoot);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(one));
    try std.testing.expectEqual(actor.Tally{ .left = 0, .total = 1 }, g.sim.pool.tally(.slime));
    try std.testing.expectEqualStrings("The last slime is dead.", g.sim.log.line(0).?);
}

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
        harness.setLife(g.sim.heroActor().?, 1000, 1000);
        var rng = mathx.Rng.init(f);
        for (0..300) |_| {
            if (g.mode == .dead) break;
            const n = g.sim.pool.n;
            harness.use(g, .shoot);
            if (g.mode == .aim) harness.press(g, CONFIRM) else harness.nudge(g, rng.pick(mathx.Dir, mathx.ALL_DIRS));
            game.update(g, SOAK_DT);
            for (0..g.sim.pool.n) |i| {
                if (g.pic.drawnAt(&g.sim, i) == null) continue;
                const pic = g.pic.pictured[i];
                try std.testing.expect(pic.max > 0 and pic.hp <= pic.max and pic.kind.family() == g.sim.pool.items[i].kind.family());
            }
            splits += g.sim.pool.n - n;
            most = @max(most, g.sim.pool.n);
            var standing_n: usize = 0;
            for (g.sim.pool.slice(), 0..) |a, i| {
                if (!a.alive) continue;
                standing_n += 1;
                try std.testing.expectEqual(actor.Pool.idOf(i), g.sim.lv.who(a.at));
                try std.testing.expect(a.hp > 0 and a.hp <= a.max);
            }
            var taken: usize = 0;
            for (&g.sim.lv.occupant) |*o| {
                if (o.* != grid.NO_ONE) taken += 1;
            }
            try std.testing.expectEqual(standing_n, taken);
        }
        for (g.sim.pool.slice()) |a| {
            if (a.kind == .slime_quarter) quarters += 1;
        }
    }
    std.debug.print("{d} floors of 300 turns with every foe awake: {d} splits, {d} quarter slimes made, at most {d} bodies of {d}\n", .{ FLOORS, splits, quarters, most, actor.MAX });
    try std.testing.expect(splits > FLOORS and quarters > 0);
    try std.testing.expect(most <= actor.MAX);
}

test "a pib's landed stab bleeds the archer about three times in ten, drawn once the stab lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var bled: usize = 0;
    var landed: usize = 0;
    for (0..harness.TRIES) |i| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        _ = harness.spawnAt(g, .pib, .{ .x = 21, .y = 20 }, true);
        g.sim.rng = mathx.Rng.init(i);
        harness.use(g, .wait);
        const h = g.sim.heroActor().?;
        if (!h.hurt()) {
            try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
            continue;
        }
        landed += 1;
        if (h.bleed.turns == 0) continue;
        bled += 1;
        try std.testing.expectEqual(bleeding.TURNS, h.bleed.turns);
        try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[g.sim.heroSlot().?].status.get(.bleeding));
        harness.drawnOut(g);
        try std.testing.expectEqual(bleeding.TURNS, g.pic.pictured[g.sim.heroSlot().?].status.get(.bleeding));
    }
    std.debug.print("a pib beside the archer: {d} stabs, {d} landed, {d} bleeds\n", .{ harness.TRIES, landed, bled });
    try std.testing.expect(landed > 0 and landed < harness.TRIES);
    try std.testing.expect(harness.aboutRateOf(bled, landed, mathx.fraction(actor.row(.pib).blow.strike.bleeds)));
}

test "a beefy pib sweeps the archer and every foe and barrel round it every fourth turn, never bleeds and never flees" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 22, .y = 20 }, .{ .x = 22, .y = 21 }, .{ .x = 20, .y = 19 } });
    harness.toughenFoes(g);
    harness.setLife(&g.sim.pool.items[3], 1, 1);
    const beefy = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    const barrel = P{ .x = 22, .y = 19 };
    g.sim.lv.putBarrel(barrel);
    harness.wakeFoes(g);
    g.sim.unkillable = true;
    var swept: [8]bool = undefined;
    for (&swept) |*s| {
        const before = ratsHp(g);
        harness.calm(g);
        harness.use(g, .wait);
        s.* = ratsHp(g) < before;
    }
    std.debug.print("a beefy pib's 8 turns, swept: {any}\n", .{swept});
    try std.testing.expectEqualSlices(bool, &.{ true, false, false, false, true, false, false, false }, &swept);
    try std.testing.expect(!g.sim.lv.hasBarrel(barrel));
    try std.testing.expect(!g.sim.pool.items[3].alive);
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(beefy).?.fright);
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.bleed.turns);
}

test "a beefy pib's landed blow stuns the archer about a quarter of the time, and its next turn passes without it once drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var landed: usize = 0;
    var stunned: usize = 0;
    for (0..harness.TRIES) |i| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
        g.sim.pool.get(id).?.sweep_in = actor.row(.beefy_pib).sweep_every + 1;
        g.sim.unkillable = true;
        g.sim.rng = mathx.Rng.init(i);
        harness.use(g, .wait);
        const h = g.sim.heroActor().?;
        if (!h.hurt()) {
            try std.testing.expect(!h.clock.owes());
            continue;
        }
        landed += 1;
        if (!h.clock.owes()) continue;
        stunned += 1;
        const turn = g.sim.clock;
        const at = h.at;
        g.st = .{};
        game.update(g, 0);
        try std.testing.expectEqual(turn, g.sim.clock);
        g.sim.pool.get(id).?.clock.stun();
        harness.nudge(g, .w);
        try std.testing.expect(!std.meta.eql(turn, g.sim.clock));
        try std.testing.expectEqual(at, g.sim.heroActor().?.at);
        try std.testing.expect(!g.sim.heroActor().?.clock.owes());
        try std.testing.expectEqual(@as(?game.Queued, .{ .walk = .w }), g.pending);
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
    g.sim.unkillable = true;
    harness.use(g, .wait);
    try std.testing.expect(g.sim.pool.items[rat].hp < harness.TEST_HP);
    try std.testing.expectEqual(harness.TEST_HP, g.pic.pictured[rat].hp);
    const t = harness.framesUntil(g, rat, harness.flashing);
    harness.drawnOut(g);
    std.debug.print("a rat swept beside the archer: struck {d:.3} s in, the sweep's bump lands at {d:.3} s\n", .{ t, game.BUMP_LANDS });
    try std.testing.expect(t >= game.BUMP_LANDS - harness.TEST_TOL);
    try std.testing.expectEqual(g.sim.pool.items[rat].hp, g.pic.pictured[rat].hp);
}

test "a sweep stun skips the victim's next action before or after its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]bool{ false, true }) |earlier| {
        const at = if (earlier) P{ .x = 21, .y = 21 } else P{ .x = 22, .y = 20 };
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
        harness.toughenFoes(g);
        harness.wakeFoes(g);
        const sweeper = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
        g.sim.unkillable = true;
        g.sim.rng = harness.sweepStunRng(g, sweeper, 2, earlier);
        combat.endTurn(g);
        try std.testing.expect(g.sim.pool.items[1].hp < harness.TEST_HP);
        try std.testing.expectEqual(at, g.sim.pool.items[1].at);
        try std.testing.expectEqual(!earlier, g.sim.pool.items[1].clock.stalled);
        try std.testing.expectEqual(earlier, g.sim.pool.items[1].clock.owes());
        if (earlier) try std.testing.expect(g.pic.owed[1].bit != null);
        g.pic.owed[1] = .{};
        combat.endTurn(g);
        try std.testing.expectEqual(earlier, at.eq(g.sim.pool.items[1].at));
        try std.testing.expectEqual(earlier, g.sim.pool.items[1].clock.stalled);
        try std.testing.expect(!g.sim.pool.items[1].clock.owes());
        if (earlier) {
            try std.testing.expect(g.pic.owed[1].bit == null);
            combat.endTurn(g);
            try std.testing.expect(!g.sim.pool.items[1].clock.stalled);
            try std.testing.expect(g.pic.owed[1].bit != null);
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
    g.sim.pool.get(slime).?.hp = 22;
    const sweeper = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    g.sim.unkillable = true;
    g.sim.rng = harness.sweepStunRng(g, sweeper, slime, false);
    combat.endTurn(g);
    try std.testing.expectEqual(@as(usize, 4), g.sim.pool.n);
    try std.testing.expectEqual(at, g.sim.pool.get(slime).?.at);
    for ([_]usize{ actor.Pool.slot(slime), 3 }) |i| {
        try std.testing.expectEqual(actor.Kind.slime_half, g.sim.pool.items[i].kind);
        try std.testing.expect(g.sim.pool.items[i].clock.stalled);
        try std.testing.expect(!g.sim.pool.items[i].clock.owes());
    }
    combat.endTurn(g);
    for ([_]usize{ actor.Pool.slot(slime), 3 }) |i| try std.testing.expect(!g.sim.pool.items[i].clock.stalled);
    std.debug.print("sweep stun and split: 2 halves share the paid stun and can act the following turn\n", .{});
}

test "a swept foe's skipped status turn waits for the sweep's impact" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    harness.toughenFoes(g);
    const rat: usize = 1;
    g.sim.pool.items[rat].chill = .{ .turns = glacial.TURNS, .phase = glacial.CYCLE - 1 };
    _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    g.sim.unkillable = true;
    harness.use(g, .wait);
    try std.testing.expect(g.sim.pool.items[rat].hp < harness.TEST_HP);
    try std.testing.expectEqual(harness.TEST_HP, g.pic.pictured[rat].hp);
    const t = harness.framesUntil(g, rat, harness.flashing);
    try std.testing.expect(t >= game.BUMP_LANDS - harness.TEST_TOL);
    harness.drawnOut(g);
    try std.testing.expectEqual(g.sim.pool.items[rat].hp, g.pic.pictured[rat].hp);
    std.debug.print("swept chilled foe: damage held until impact at {d:.3} s\n", .{t});
}

test "a bleed costs the archer 1 a turn standing and 2 a turn it steps, and stops after five" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const h = g.sim.heroActor().?;
    h.bleed = .{ .turns = bleeding.TURNS };
    const full = h.hp;
    harness.use(g, .wait);
    try std.testing.expectEqual(full - bleeding.STILL, h.hp);
    harness.nudge(g, .e);
    try std.testing.expectEqual(full - bleeding.STILL - bleeding.MOVING, h.hp);
    for (0..bleeding.TURNS - 2) |_| harness.use(g, .wait);
    const spent = full - h.hp;
    try std.testing.expectEqual(@as(u8, 0), h.bleed.turns);
    try std.testing.expect(std.mem.indexOf(u8, g.sim.log.line(0).?, "stops bleeding") != null);
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
    harness.wallRow(&g.sim.lv, 22, 15, 25);
    const near = harness.spawnAt(g, .pib, .{ .x = 20, .y = 21 }, false);
    const walled = harness.spawnAt(g, .pib, .{ .x = 19, .y = 24 }, false);
    game.settle(g);
    game.castSight(g, hero);
    harness.slay(g, 2, hero);
    const p = g.sim.pool.get(near).?;
    try std.testing.expect(p.awake);
    try std.testing.expectEqual(actor.FLEE_TURNS, p.fright);
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(walled).?.fright);
    try std.testing.expect(std.mem.indexOf(u8, g.sim.log.line(0).?, "flees in terror") != null);
    const speech = &g.pic.fx.speech[actor.Pool.slot(near)];
    const rng = g.sim.rng;
    g.st = .{};
    game.update(g, 0.1);
    try std.testing.expectEqual(@as(f32, 0), speech.life);
    try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[actor.Pool.slot(near)].status.get(.frightened));
    game.update(g, 0.11);
    try std.testing.expectEqual(fx.SPEECH_S, speech.life);
    try std.testing.expectEqual(actor.FLEE_TURNS, g.pic.pictured[actor.Pool.slot(near)].status.get(.frightened));
    try std.testing.expectEqual(@as(?usize, null), g.pic.fx.speech[actor.Pool.slot(walled)].after);
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.speech[actor.Pool.slot(walled)].life);
    combat.scare(g, actor.Pool.slot(2));
    try std.testing.expectEqual(@as(?usize, null), speech.after);
    game.update(g, fx.SPEECH_S);
    try std.testing.expectEqual(@as(f32, 0), speech.life);
    try std.testing.expectEqualDeep(rng, g.sim.rng);
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

test "a pib's fright is drawn until its last flight is" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .pib, .{ .x = 22, .y = 20 }, true);
    g.sim.pool.get(id).?.fright = 1;
    game.settle(g);
    const slot = actor.Pool.slot(id);
    combat.endTurn(g);
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(id).?.fright);
    harness.stagger(g);
    g.pic.catchUp(&g.sim);
    try std.testing.expectEqual(@as(u8, 1), g.pic.pictured[slot].status.get(.frightened));
    harness.drawnOut(g);
    try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[slot].status.get(.frightened));
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
        for (walls) |w| g.sim.lv.set(w, .wall);
        const id = harness.spawnAt(g, .pib, end, true);
        g.sim.pool.get(id).?.fright = actor.FLEE_TURNS;
        const full = g.sim.heroActor().?.hp;
        for (0..actor.FLEE_TURNS) |_| {
            combat.endTurn(g);
            if (!g.sim.pool.get(id).?.at.eq(end)) moves += 1;
        }
        if (hero.x == 17) strikes = full - g.sim.heroActor().?.hp else try std.testing.expectEqual(full, g.sim.heroActor().?.hp);
    }
    std.debug.print("a cornered pib over {d} turns: {d} steps out of its dead end, {d} hp off an archer beside it\n", .{ actor.FLEE_TURNS, moves, strikes });
    try std.testing.expectEqual(@as(usize, 0), moves);
    try std.testing.expect(strikes > 0);
}

test "a bog leech swims unseen to the shore, surfaces beside the hero and is struck where it floats" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    var cells = grid.Cells.of(.{ .x = 21, .y = 18 }, .{ .x = 27, .y = 23 });
    while (cells.next()) |p| g.sim.lv.set(p, .water);
    const id = harness.spawnAt(g, .bog_leech, .{ .x = 25, .y = 20 }, true);
    game.settle(g);
    const slot = actor.Pool.slot(id);
    try std.testing.expect(g.sim.pool.get(id).?.submerged and harness.gone(g, slot));
    try std.testing.expectEqual(@as(?P, null), bow.pick(&g.sim.lv, &g.sim.pool, from));
    var turns: usize = 0;
    while (g.sim.pool.get(id).?.submerged and turns < 8) : (turns += 1) {
        combat.endTurn(g);
        try std.testing.expectEqual(grid.Tile.water, g.sim.lv.at(g.sim.pool.get(id).?.at));
        if (!g.sim.pool.get(id).?.submerged) {
            harness.stagger(g);
            g.pic.catchUp(&g.sim);
            try std.testing.expect(harness.gone(g, slot));
        }
        harness.drawnOut(g);
    }
    std.debug.print("bog leech: {d} turns swimming unseen, then shown beside the hero\n", .{turns});
    try std.testing.expectEqual(P{ .x = 21, .y = 20 }, g.sim.pool.get(id).?.at);
    try std.testing.expect(harness.drawn(g, slot) and g.sim.pool.get(id).?.seenIn(&g.sim.lv));
    try std.testing.expectEqual(game.Move.kick, game.heroMove(g, .e));
}

test "a mimic stands as a closed chest until opened, then bites, and dies leaving a chest's loot" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, from, &.{});
    const id = harness.spawnAt(g, .mimic, at, false);
    game.settle(g);
    const slot = actor.Pool.slot(id);
    try std.testing.expectEqual(grid.Tile.chest, g.sim.lv.at(at));
    try std.testing.expect(harness.gone(g, slot));
    for (0..3) |_| {
        combat.endTurn(g);
        harness.drawnOut(g);
    }
    try std.testing.expect(g.sim.pool.get(id).?.disguised and !g.sim.pool.get(id).?.awake);
    try std.testing.expect(g.pic.mimicAt(&g.sim, at) and !g.pic.mimicAt(&g.sim, from));
    try std.testing.expectEqual(game.Move.open, game.heroMove(g, .e));
    game.heroStep(g, .e, 0);
    const m = g.sim.pool.get(id).?;
    try std.testing.expect(!m.disguised and m.awake);
    try std.testing.expectEqual(grid.Tile.floor, g.sim.lv.at(at));
    try std.testing.expect(!g.pic.mimicAt(&g.sim, at));
    try std.testing.expect(g.pic.owed[slot].bit != null);
    harness.drawnOut(g);
    try std.testing.expect(harness.drawn(g, slot));
    const drops = g.sim.ground.n;
    combat.wound(g, id, .{ .dmg = 1000, .hit_checked = true }, combat.SHOOT, .{ .from = from, .wait = 0 });
    try std.testing.expect(g.sim.pool.get(id) == null);
    try std.testing.expectEqual(drops + 1, g.sim.ground.n);
    try std.testing.expect(g.sim.ground.hasItems(at));
}

test "an arrow into a submerged leech strikes it unseen: no line names it until a blow kills it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    const lake = P{ .x = 24, .y = 20 };
    g.sim.lv.set(lake, .water);
    const id = harness.spawnAt(g, .bog_leech, lake, false);
    harness.toughen(g.sim.pool.get(id).?);
    game.settle(g);
    const name = actor.row(.bog_leech).name;
    var struck: usize = 0;
    for (0..8) |seed| {
        g.sim.rng = mathx.Rng.init(seed);
        harness.aimAt(g, .shoot, lake);
        harness.drawnOut(g);
        if (g.sim.pool.get(id).?.hp < harness.TEST_HP) struck += 1;
        try std.testing.expect(g.sim.pool.get(id).?.submerged and !harness.logged(g, name));
    }
    std.debug.print("submerged leech: struck by {d} of 8 arrows, none said\n", .{struck});
    try std.testing.expect(struck > 0);
    combat.wound(g, id, .{ .dmg = 1000, .hit_checked = true }, combat.SHOOT, .{ .from = from, .wait = 0 });
    try std.testing.expect(harness.logged(g, name));
}

test "a status taking hold of a disguised mimic names nothing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    harness.arena(g, from, &.{});
    const id = harness.spawnAt(g, .mimic, at, false);
    game.settle(g);
    const raw = attacks.rawFor(&g.sim, .burning_arrow, true);
    var burned: usize = 0;
    for (0..16) |seed| {
        harness.toughen(g.sim.pool.get(id).?);
        g.sim.rng = mathx.Rng.init(seed);
        combat.arrowHit(g, id, attacks.heroScaled(&g.sim, .burning_arrow, raw), .burning_arrow, .{ .from = from, .wait = 0 });
        if (g.sim.pool.get(id).?.burn.turns > 0) burned += 1;
        g.sim.pool.get(id).?.burn = .{};
    }
    std.debug.print("disguised mimic: set alight by {d} of 16 burning arrows, none said\n", .{burned});
    try std.testing.expect(burned > 0 and g.sim.pool.get(id).?.disguised);
    try std.testing.expect(!harness.logged(g, actor.row(.mimic).name));
}

test "a disguised mimic's afflictions wear off on its turns" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(g, .mimic, .{ .x = 26, .y = 20 }, false);
    game.settle(g);
    const m = g.sim.pool.get(id).?;
    m.chill.apply();
    m.pin.turns = 2;
    var turns: usize = 0;
    while ((m.chill.turns > 0 or m.pin.turns > 0) and turns < 20) : (turns += 1) {
        combat.endTurn(g);
        harness.drawnOut(g);
    }
    std.debug.print("disguised mimic: chill and pin worn off in {d} turns\n", .{turns});
    try std.testing.expect(m.disguised and m.chill.turns == 0 and m.pin.turns == 0);
}

test "a bandit netter's net pins the hero, who struggles in place and cannot leap until it wears off" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const skills = @import("../skills.zig");
    const from = P{ .x = 20, .y = 20 };
    const net = actor.row(.bandit_netter).net.?;
    var tries: usize = 0;
    const pinned = for (0..64) |seed| {
        tries += 1;
        harness.arena(g, from, &.{});
        const id = harness.spawnAt(g, .bandit_netter, .{ .x = 24, .y = 20 }, true);
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        combat.endTurn(g);
        const slot = actor.Pool.slot(id);
        try std.testing.expect(g.pic.owed[slot].bit.? == .snare);
        try std.testing.expectEqual(net.every, g.sim.pool.get(id).?.ready_in);
        if (g.sim.heroActor().?.pin.turns == 0) continue;
        try std.testing.expectEqual(net.pins, g.sim.heroActor().?.pin.turns);
        harness.stagger(g);
        try std.testing.expect(g.pic.foe_shots[slot].?.net);
        try std.testing.expectEqual(@as(u8, 0), g.pic.heroShown(&g.sim).?.status.get(.pinned));
        harness.drawnOut(g);
        try std.testing.expect(g.pic.heroShown(&g.sim).?.status.get(.pinned) > 0);
        try std.testing.expect((skills.blocked(g, .juke, &g.sim.flasks, g.sim.mana, skills.heroPinned(g)) orelse return error.NotPinned) == .pinned);
        for (0..net.pins) |_| {
            game.heroStep(g, .w, 0);
            try std.testing.expectEqual(from, g.sim.heroAt().?);
            harness.drawnOut(g);
        }
        game.heroStep(g, .w, 0);
        try std.testing.expectEqual(from.add(mathx.Dir.w.delta()), g.sim.heroAt().?);
        break true;
    } else false;
    std.debug.print("bandit netter: pinned on throw {d}; {d} struggling turns in place, then free\n", .{ tries, net.pins });
    try std.testing.expect(pinned);
}

test "a bandit shieldbearer's landed bash knocks the hero a cell back as the blow lands, unless walled" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const glide = @import("../glide.zig");
    const from = P{ .x = 20, .y = 20 };
    const back = from.add(mathx.Dir.w.delta());
    for ([_]bool{ false, true }) |walled| {
        harness.arena(g, from, &.{});
        if (walled) g.sim.lv.set(back, .wall);
        const id = harness.spawnAt(g, .bandit_shieldbearer, .{ .x = 21, .y = 20 }, true);
        game.settle(g);
        g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = true }});
        combat.endTurn(g);
        const want = if (walled) from else back;
        try std.testing.expectEqual(want, g.sim.heroAt().?);
        const hero = g.sim.heroSlot().?;
        harness.stagger(g);
        try std.testing.expect(harness.samePx(g.pic.glide[hero].ground(), glide.cellPx(from)));
        harness.drawnOut(g);
        try std.testing.expect(harness.samePx(g.pic.glide[hero].ground(), glide.cellPx(want)));
    }
}

test "a shieldbearer killed by thorns as its bash lands still knocks the hero back, tearing its bleed" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    g.sim.inventory.gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 50 }, null, null, null } });
    const id = harness.spawnAt(g, .bandit_shieldbearer, .{ .x = 21, .y = 20 }, true);
    g.sim.pool.get(id).?.hp = 1;
    harness.toughen(g.sim.heroActor().?);
    game.settle(g);
    g.sim.rng = harness.bitesRng(g, &.{.{ .id = id, .lands = true }});
    combat.endTurn(g);
    try std.testing.expect(g.sim.pool.get(id) == null);
    try std.testing.expectEqual(from.add(mathx.Dir.w.delta()), g.sim.heroAt().?);
    try std.testing.expect(g.sim.stepped);
}

test "a frost wisp's touch chills the hero unless cold-proof, and a chilled hero's third action costs the next turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    var touched = false;
    for (0..64) |seed| {
        harness.arena(g, from, &.{});
        _ = harness.spawnAt(g, .frost_wisp, .{ .x = 21, .y = 20 }, true);
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        const hp = g.sim.heroActor().?.hp;
        combat.endTurn(g);
        if (g.sim.heroActor().?.hp == hp) continue;
        try std.testing.expectEqual(glacial.TURNS, g.sim.heroActor().?.chill.turns);
        touched = true;
        break;
    }
    try std.testing.expect(touched);
    for (0..16) |seed| {
        harness.arena(g, from, &.{});
        g.sim.heroActor().?.resists.set(.cold, 100);
        _ = harness.spawnAt(g, .frost_wisp, .{ .x = 21, .y = 20 }, true);
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        const hp = g.sim.heroActor().?.hp;
        combat.endTurn(g);
        try std.testing.expectEqual(hp, g.sim.heroActor().?.hp);
        try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.chill.turns);
    }
    harness.arena(g, from, &.{});
    g.sim.heroActor().?.chill.apply();
    for (0..glacial.CYCLE) |i| {
        try std.testing.expect(!g.sim.heroActor().?.clock.owes());
        combat.endTurn(g);
        try std.testing.expectEqual(i + 1 == glacial.CYCLE, g.sim.heroActor().?.clock.owes());
    }
    harness.drawnOut(g);
    harness.idle(g);
    try std.testing.expect(!g.sim.heroActor().?.clock.owes());
    std.debug.print("frost wisp: touch chills for {d} turns, cold-proof heroes untouched; one lost turn after {d} chilled actions\n", .{ glacial.TURNS, glacial.CYCLE });
}

test "a pyre bloat bursts into flame, setting the bodies beside it burning and nothing further" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, from, &.{});
    const bloat = harness.spawnAt(g, .pyre_bloat, at, false);
    const near = harness.spawnAt(g, .rat, .{ .x = 22, .y = 21 }, false);
    const far = harness.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, false);
    game.settle(g);
    combat.wound(g, bloat, .{ .dmg = 100, .hit_checked = true }, combat.SHOOT, .{ .from = from, .wait = 0 });
    try std.testing.expect(g.sim.pool.get(bloat) == null);
    try std.testing.expect(g.sim.heroActor().?.burn.turns > 0);
    try std.testing.expect(g.sim.pool.get(near).?.burn.turns > 0);
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(far).?.burn.turns);
    try std.testing.expect(!g.sim.lv.gassy(at) and !g.sim.lv.scalding(at));
}

test "a pyre bloat bursting over a lake boils the water beside it into steam and none further" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 24, .y = 20 };
    harness.arena(g, from, &.{});
    var lake = grid.Cells.around(at, 2);
    while (lake.next()) |p| g.sim.lv.set(p, .water);
    const bloat = harness.spawnAt(g, .pyre_bloat, at, false);
    game.settle(g);
    combat.wound(g, bloat, .{ .dmg = 100, .hit_checked = true }, combat.SHOOT, .{ .from = from, .wait = 0 });
    try std.testing.expect(g.sim.pool.get(bloat) == null);
    var cells = grid.Cells.around(at, 2);
    while (cells.next()) |p| {
        const steam = g.sim.lv.volumeAt(.steam, p);
        try std.testing.expectEqual(if (mathx.dist(p, at) <= 1) gas.BOIL else 0, steam);
    }
    try std.testing.expect(harness.logged(g, gas.STEAM_NAME));
}

test "a pib shaman mends the most hurt pib in reach, else wakes the sleeping ones, and keeps off the hero" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const mend = actor.row(.pib_shaman).mends.?;
    harness.arena(g, from, &.{});
    const shaman = harness.spawnAt(g, .pib_shaman, .{ .x = 27, .y = 20 }, true);
    const worse = harness.spawnAt(g, .pib, .{ .x = 28, .y = 20 }, true);
    const better = harness.spawnAt(g, .pib, .{ .x = 28, .y = 21 }, true);
    const sleeper = harness.spawnAt(g, .pib, .{ .x = 29, .y = 19 }, false);
    g.sim.pool.get(worse).?.hp = 3;
    g.sim.pool.get(better).?.hp = 8;
    game.settle(g);
    combat.endTurn(g);
    const mended = g.sim.pool.get(worse).?.hp;
    try std.testing.expectEqual(@min(3 + mend.amount, g.sim.pool.get(worse).?.max), mended);
    try std.testing.expectEqual(@as(i32, 8), g.sim.pool.get(better).?.hp);
    try std.testing.expectEqual(mend.every, g.sim.pool.get(shaman).?.ready_in);
    try std.testing.expect(!g.sim.pool.get(sleeper).?.awake);
    harness.drawnOut(g);
    g.sim.pool.get(better).?.hp = g.sim.pool.get(better).?.max;
    var turns: usize = 0;
    while (!g.sim.pool.get(sleeper).?.awake and turns < mend.every) : (turns += 1) {
        combat.endTurn(g);
        harness.drawnOut(g);
    }
    try std.testing.expect(g.sim.pool.get(sleeper).?.awake);
    try std.testing.expect(mathx.dist(g.sim.pool.get(shaman).?.at, from) > actor.row(.pib_shaman).keeps);
    harness.arena(g, from, &.{});
    const cornered = harness.spawnAt(g, .pib_shaman, .{ .x = 21, .y = 20 }, true);
    game.settle(g);
    combat.endTurn(g);
    try std.testing.expectEqual(@as(i32, 2), mathx.dist(g.sim.pool.get(cornered).?.at, from));
    std.debug.print("pib shaman: mended a pib to {d}, woke a sleeper {d} turns later, stepped back from a hero beside it\n", .{ mended, turns });
}

test "a foe biting before a shieldbearer's knock that turn lunges at where the hero stood" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    harness.toughen(g.sim.heroActor().?);
    const rat = harness.spawnAt(g, .rat, .{ .x = 20, .y = 19 }, true);
    const shield = harness.spawnAt(g, .bandit_shieldbearer, .{ .x = 21, .y = 20 }, true);
    game.settle(g);
    g.sim.rng = harness.bitesRng(g, &.{ .{ .id = rat, .lands = true }, .{ .id = shield, .lands = true } });
    combat.endTurn(g);
    try std.testing.expectEqual(from.add(mathx.Dir.w.delta()), g.sim.heroAt().?);
    harness.stagger(g);
    const bump = g.pic.glide[actor.Pool.slot(rat)].bump.?;
    std.debug.print("knock order: the rat ahead of the knock lunges ({d:.1}, {d:.1}) px, straight at the hero's old cell\n", .{ bump.x, bump.y });
    try std.testing.expect(bump.x == 0 and bump.y > 0);
}

test "a mimic killed in its chest stays the chest until the killing blow lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    harness.arena(g, from, &.{});
    const id = harness.spawnAt(g, .mimic, at, false);
    game.settle(g);
    const slot = actor.Pool.slot(id);
    combat.wound(g, id, .{ .dmg = 1000, .hit_checked = true }, combat.SHOOT, .{ .from = from, .wait = 0.3 });
    try std.testing.expect(g.sim.pool.get(id) == null);
    try std.testing.expect(g.sim.lv.at(at) != .chest);
    var frames: usize = 0;
    while (!g.pic.pictured[slot].down()) : (frames += 1) {
        try std.testing.expectEqual(grid.Tile.chest, g.pic.tileShown(&g.sim, at));
        try std.testing.expect(g.pic.mimicAt(&g.sim, at));
        try std.testing.expect(harness.gone(g, slot));
        game.update(g, harness.TEST_DT);
    }
    try std.testing.expectEqual(g.sim.lv.at(at), g.pic.tileShown(&g.sim, at));
    try std.testing.expect(!g.pic.mimicAt(&g.sim, at));
    std.debug.print("mimic: drawn as its chest for {d} frames, until the killing arrow lands\n", .{frames});
    try std.testing.expect(frames > 0);
}

test "a pyre bloat sets its neighbours alight as its death lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    const bloat = harness.spawnAt(g, .pyre_bloat, .{ .x = 22, .y = 20 }, false);
    const near = harness.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, false);
    game.settle(g);
    const slot = actor.Pool.slot(near);
    combat.wound(g, bloat, .{ .dmg = 100, .hit_checked = true }, combat.SHOOT, .{ .from = from, .wait = 0.3 });
    try std.testing.expect(g.sim.pool.get(near).?.burn.turns > 0);
    var frames: usize = 0;
    while (!g.pic.pictured[actor.Pool.slot(bloat)].down()) : (frames += 1) {
        try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[slot].status.get(.burning));
        game.update(g, harness.TEST_DT);
    }
    try std.testing.expect(g.pic.pictured[slot].status.get(.burning) > 0);
    std.debug.print("pyre: the rat beside it drawn unburnt for {d} frames, alight as the burst lands\n", .{frames});
    try std.testing.expect(frames > 0);
}

test "a pyre bloat bursting on its own turn scalds a body on the water it boils only as the burst lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const lake = P{ .x = 22, .y = 20 };
    g.sim.lv.set(lake, .water);
    const bloat = harness.spawnAt(g, .pyre_bloat, .{ .x = 21, .y = 20 }, true);
    g.sim.pool.get(bloat).?.pin.extend(2);
    const leech = harness.spawnAt(g, .bog_leech, lake, true);
    harness.toughen(g.sim.pool.get(leech).?);
    game.settle(g);
    harness.use(g, .wait);
    try std.testing.expect(g.sim.pool.get(bloat) == null and g.sim.pool.get(leech).?.hp < harness.TEST_HP);
    const slot = actor.Pool.slot(leech);
    g.st = .{};
    var frames: usize = 0;
    while (!g.pic.pictured[actor.Pool.slot(bloat)].down()) : (frames += 1) {
        try std.testing.expect(frames < 200);
        try std.testing.expectEqual(harness.TEST_HP, g.pic.pictured[slot].hp);
        game.update(g, harness.TEST_DT);
    }
    const t = harness.framesUntil(g, slot, harness.caughtUp);
    std.debug.print("pyre steam: the leech drawn unscalded for {d} frames, scalded {d:.3} s after the burst lands\n", .{ frames, t });
    try std.testing.expect(frames > 0 and t < 1);
}

test "a leech swimming unseen holds neither the stagger nor the walk" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    harness.arena(g, from, &.{});
    var cells = grid.Cells.of(.{ .x = 21, .y = 18 }, .{ .x = 27, .y = 23 });
    while (cells.next()) |p| g.sim.lv.set(p, .water);
    const id = harness.spawnAt(g, .bog_leech, .{ .x = 25, .y = 20 }, true);
    game.settle(g);
    combat.endTurn(g);
    const leech = g.sim.pool.get(id).?;
    try std.testing.expect(leech.submerged and !leech.at.eq(.{ .x = 25, .y = 20 }));
    harness.stagger(g);
    std.debug.print("submerged leech: swam to {d},{d}; the turn holds {d:.3} s\n", .{ leech.at.x, leech.at.y, @max(0, g.pic.busy) });
    try std.testing.expect(g.pic.quiet());
}

test "a sleeping leech the hero steps beside surfaces as the step lands, and dives as the step away does" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const lake = P{ .x = 22, .y = 20 };
    g.sim.lv.set(lake, .water);
    const id = harness.spawnAt(g, .bog_leech, lake, false);
    game.settle(g);
    const slot = actor.Pool.slot(id);
    const hero = g.sim.heroSlot().?;
    try std.testing.expect(harness.gone(g, slot));
    var shown: [2]f32 = undefined;
    inline for (.{ mathx.Dir.e, mathx.Dir.w }, .{ false, true }, &shown) |d, under, *t| {
        harness.nudge(g, d);
        try std.testing.expectEqual(under, g.sim.pool.get(id).?.submerged);
        const step = g.pic.glide[hero].left();
        t.* = harness.framesUntil(g, slot, if (under) harness.gone else harness.drawn);
        try std.testing.expect(t.* + harness.TEST_DT >= step and t.* < 1);
        harness.drawnOut(g);
    }
    std.debug.print("leech: surfaces {d:.3} s and dives {d:.3} s into the hero's step\n", .{ shown[0], shown[1] });
}

test "a bolt bursting on a leech in deep water strikes it though the burst spreads over no water" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    var struck: usize = 0;
    for (0..16) |seed| {
        harness.arena(g, from, &.{});
        g.sim.lv.set(at, .water);
        const id = harness.spawnAt(g, .bog_leech, at, true);
        const a = g.sim.pool.get(id).?;
        a.submerged = false;
        harness.toughen(a);
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        combat.burstHit(g, .glacial_shot, .{ .body = id }, at, .{ .from = from, .wait = 0.2 });
        if (g.sim.pool.get(id).?.hp < harness.TEST_HP) struck += 1;
    }
    std.debug.print("bolt on a leech in deep water: struck {d} of 16 rolls\n", .{struck});
    try std.testing.expect(struck > 0);
}
