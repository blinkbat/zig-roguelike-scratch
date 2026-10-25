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
            g.sim.rng = harness.bitesRng(g, kind, &.{hit});
            combat.endTurn(g);
            const expected: i32 = if (kind == .rat and hit) 2 else 0;
            try std.testing.expectEqual(hp - expected, g.sim.pool.get(id).?.hp);
            try std.testing.expectEqual(expected > 0, g.pic.owed[slot].thorns != null);
            try std.testing.expectEqual(hp, g.pic.pictured[slot].hp);
            g.pic.lead = 0;
            g.pic.stepGlide(&g.sim, g.cloud, 0);
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
        g.sim.rng = harness.bitesRng(g, .rat, &.{true});
        combat.endTurn(g);
        try std.testing.expect(g.sim.pool.get(id) == null);
        try std.testing.expectEqual(kills + 1, g.sim.kills);
        try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].thorns.?.kill);
        if (lethal_hero) {
            try std.testing.expectEqual(game.Mode.dead, g.mode);
            try std.testing.expect(g.sim.heroActor() == null);
        } else {
            try std.testing.expectEqual(hp + 2, g.sim.heroActor().?.hp);
            try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].thorns.?.recovery != null);
        }
        g.pic.lead = 0;
        g.pic.stepGlide(&g.sim, g.cloud, 0);
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
        g.mark = g.sim.pool.get(target).?.at;
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
            try std.testing.expect(debt.thorns.?.after.body.hp > debt.reaction.?.hit.after.?.body.hp);
            g.pic.lead = 0;
            g.pic.stepGlide(&g.sim, g.cloud, 0);
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
    g.sim.rng = harness.bitesRng(g, .slime, &.{true});
    combat.endTurn(g);
    try std.testing.expectEqual(@as(usize, 2), g.sim.pool.tally(.slime).left);
    try std.testing.expect(g.pic.owed[actor.Pool.slot(slime)].thorns.?.after.reveals != null);
    g.pic.lead = 0;
    g.pic.stepGlide(&g.sim, g.cloud, 0);
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
    g.sim.rng = harness.bitesRng(g, .bandit_crossbowman, &.{true});
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
        const expected = case == .water or case == .open_chest or case == .diagonal;
        g.sim.rng = harness.bitesRng(g, .bandit_crossbowman, &.{true});
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
        g.sim.rng = harness.bitesRng(g, .bandit_crossbowman, &.{true});
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
    g.sim.rng = harness.bitesRng(g, .bandit_crossbowman, &.{ true, true });
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
        g.sim.rng = harness.bitesRng(g, .bandit_crossbowman, &.{shielded});
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
        _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
        g.sim.unkillable = true;
        g.sim.rng = harness.sweepStunRng(g, earlier);
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
    _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    g.sim.unkillable = true;
    g.sim.rng = harness.sweepStunRng(g, false);
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
    game.update(g, 0.11);
    try std.testing.expectEqual(fx.SPEECH_S, speech.life);
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
