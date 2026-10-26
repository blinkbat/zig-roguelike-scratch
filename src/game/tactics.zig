const std = @import("std");
const game = @import("../game.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const rules = @import("../play/tactics.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const combat = @import("combat.zig");
const skills = @import("skills.zig");
const P = mathx.P;

pub fn instant(g: *game.Game, comptime act: skillbar.Act) void {
    const h = g.sim.heroActor() orelse return;
    const rank = g.sim.growth.ranks.get(act);
    switch (act) {
        .steady_aim => h.tactics.steady = rank,
        .guard => h.tactics.guard = rank,
        .unyielding => h.tactics.unyielding = !h.tactics.unyielding,
        .whirlwind => {
            const area = rules.Whirlwind.area(&g.sim.lv, h.at);
            const ids = skills.foesIn(g, area);
            const raw = combat.rollRaw(&g.sim.rng, .whirlwind, combat.basesFor(g, .whirlwind), true);
            const s = game.presentation.Stroke{ .from = h.at, .wait = game.CAST_S };
            for (ids.slice()) |id| combat.wound(g, id, combat.heroScaled(g, .whirlwind, raw).physical(), "whirls into", s);
            for (area.slice()) |at| combat.smash(g, at, "whirls into", s);
            g.pic.lead = s.wait;
        },
        else => @compileError(@tagName(act) ++ " has no instant tactical use"),
    }
    g.sim.log.say("{s}: {s}{s}.", .{ g.sim.name.text(), act.name(), if (act == .unyielding and !h.tactics.unyielding) " ended" else "" });
    g.pic.fx.shimmer(mathx.centre(h.at), look.UI_GOLD);
}

pub fn valid(g: *const game.Game, from: P, at: P) bool {
    return validAct(g, g.aim_act, from, at);
}

pub fn validAct(g: *const game.Game, act: skillbar.Act, from: P, at: P) bool {
    if (!act.aimable(&g.sim.lv, from, at)) return false;
    return switch (act) {
        .combustion => blk: {
            const id = g.sim.lv.who(at);
            if (id == grid.NO_ONE) break :blk false;
            const a = g.sim.pool.items[actor.Pool.slot(id)];
            break :blk a.alive and a.foe() and a.burn.turns > 0;
        },
        .arcane_barrier => rules.wall(&g.sim.lv, from, g.barrier_start orelse at, at, g.sim.growth.ranks.get(.arcane_barrier)) != null,
        .overwatch => !from.eq(at),
        else => true,
    };
}

pub fn cast(g: *game.Game, act: skillbar.Act, from: P) void {
    switch (act) {
        inline else => |a| if (comptime a.reticle() != .ground) unreachable else castGround(g, a, from),
    }
}

fn castGround(g: *game.Game, comptime act: skillbar.Act, from: P) void {
    const rank = g.sim.growth.ranks.get(act);
    const at = g.mark;
    switch (act) {
        .overwatch => g.sim.heroActor().?.tactics.overwatch = mathx.toward(from, at).?,
        .caltrops => {
            const area = rules.Caltrops.area(&g.sim.lv, at);
            for (area.slice()) |p| {
                if (!g.sim.lv.isLit(p)) continue;
                g.sim.lv.caltrops[grid.Level.idx(p)] = .{ .turns = rules.Caltrops.duration(rank) + 1, .rank = rank };
            }
        },
        .gravity_well => {
            const area = rules.GravityWell.area(&g.sim.lv, at);
            const ids = skills.foesIn(g, area);
            for (ids.slice()) |id| {
                const a = g.sim.pool.get(id) orelse continue;
                if (!g.sim.lv.isLit(a.at)) continue;
                for (0..rules.GravityWell.pulls(rank)) |_| {
                    if (a.pin.turns > 0) break;
                    const d = mathx.toward(a.at, at) orelse break;
                    const to = a.at.add(d.delta());
                    if (!g.sim.lv.vacant(to) or !area.has(to)) break;
                    g.sim.pool.move(&g.sim.lv, id, to);
                    g.sim.displaced.set(actor.Pool.slot(id));
                    entered(g, id);
                }
                if (rules.GravityWell.pins(rank) > 0 and g.sim.takeStatus(a, .pin)) a.pin.turns = @max(a.pin.turns, rules.GravityWell.pins(rank));
                g.pic.fx.settle(game.CAST_S, .{ .slot = actor.Pool.slot(id), .after = g.pic.afterOf(&g.sim, actor.Pool.slot(id)) });
            }
            g.sim.flowed = false;
            g.pic.fx.shimmer(mathx.centre(at), look.WARD);
        },
        .combustion => {
            const target = g.sim.pool.get(g.sim.lv.who(at)).?;
            const fuel: i32 = target.burn.turns;
            target.burn = .{};
            const slot = actor.Pool.slot(g.sim.lv.who(at));
            g.pic.fx.settle(game.CAST_S, .{ .slot = slot, .after = g.pic.afterOf(&g.sim, slot) });
            const area = rules.Combustion.area(&g.sim.lv, at);
            const ids = skills.foesIn(g, area);
            var raw = combat.rollRaw(&g.sim.rng, .combustion, combat.basesFor(g, .combustion), false);
            raw.elements.getPtr(.fire).* += rules.Combustion.FUEL_DAMAGE * fuel;
            const s = game.presentation.Stroke{ .from = from, .wait = game.CAST_S, .fire = true };
            g.pic.fx.burst(s.wait, .{ .at = at, .area = area, .element = .fire });
            for (ids.slice()) |id| {
                const a = g.sim.pool.get(id) orelse continue;
                const hit = combat.heroScaled(g, .combustion, raw);
                combat.wound(g, id, .{ .dmg = hit.blow.total(g.sim.combatStats(a).elements), .crit = hit.crit }, "detonates", s);
            }
        },
        .arcane_barrier => {
            const area = rules.wall(&g.sim.lv, from, g.barrier_start.?, at, rank).?;
            for (area.slice()) |p| g.sim.lv.barrier[grid.Level.idx(p)] = rules.ArcaneBarrier.duration(rank) + 1;
            g.barrier_start = null;
        },
        else => @compileError(@tagName(act) ++ " has no ground tactical use"),
    }
    g.sim.log.say("{s} casts {s}.", .{ g.sim.name.text(), act.name() });
    g.pic.lead = game.CAST_S;
    g.pic.holdUntil(game.CAST_S);
    combat.endTurn(g);
}

pub fn beforeAction(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    h.tactics.guard = 0;
    h.tactics.overwatch = null;
}

pub fn startTurn(g: *game.Game) void {
    const h = g.sim.heroActor() orelse return;
    if (h.tactics.unyielding) {
        if (g.sim.mana >= rules.Unyielding.DRAIN) {
            g.sim.mana -= rules.Unyielding.DRAIN;
        } else {
            h.tactics.unyielding = false;
            g.sim.log.say("{s}'s Unyielding ends: not enough mana.", .{g.sim.name.text()});
        }
    }
    for (&g.sim.lv.barrier) |*t| t.* -|= 1;
    for (&g.sim.lv.caltrops) |*c| {
        c.turns -|= 1;
        if (c.turns == 0) c.rank = 0;
    }
}

pub fn entered(g: *game.Game, id: u16) void {
    const a = g.sim.pool.get(id) orelse return;
    const trap = g.sim.lv.caltrops[grid.Level.idx(a.at)];
    if (trap.turns > 0 and actor.row(a.kind).movement != .flying) {
        if (g.sim.takeStatus(a, .pin)) a.pin.turns = @max(a.pin.turns, rules.Caltrops.pins(trap.rank));
        if (rules.Caltrops.bleed(trap.rank) > 0 and g.sim.takeStatus(a, .bleed)) a.bleed.startWith(rules.Caltrops.bleed(trap.rank));
        g.pic.owed[actor.Pool.slot(id)].worn = g.pic.afterOf(&g.sim, actor.Pool.slot(id));
        g.sim.sayAt(a.at, "The {s} steps into caltrops.", .{actor.row(a.kind).name});
    }
    const h = g.sim.heroActor() orelse return;
    const direction = h.tactics.overwatch orelse return;
    if (!rules.covered(h.at, direction, a.at) or !bow.aimable(&g.sim.lv, h.at, a.at)) return;
    const flight = bow.fly(&g.sim.lv, h.at, a.at);
    if (flight.struck == null or flight.struck.? != .body or flight.struck.?.body != id) return;
    h.tactics.overwatch = null;
    combat.reaction(g, id, combat.heroSkill(g, .overwatch), "shoots on overwatch", .{ .from = h.at, .wait = 0 }, id, flight);
    h.tactics.steady = 0;
}

pub fn counter(g: *game.Game, id: u16) void {
    const h = g.sim.heroActor() orelse return;
    const a = g.sim.pool.get(id) orelse return;
    if (!h.tactics.unyielding or mathx.dist(h.at, a.at) != 1 or !g.sim.rng.percent(rules.Unyielding.chance(g.sim.growth.ranks.get(.unyielding)))) return;
    const raw = combat.kickRaw(&g.sim.rng, &g.sim.inventory.gear, g.sim.heroRow().blow.strike);
    combat.reaction(g, id, combat.heroRoll(g, .melee, raw), "counters", .{ .from = h.at, .wait = 0 }, id, null);
}

fn targeted(g: *game.Game, act: skillbar.Act, at: P) void {
    skills.useSkill(g, .{ .act = act, .by = .x });
    if (g.mode != .aim) return;
    g.mark = at;
    skills.confirmAim(g);
}

test "tactical caltrops ranks pin entering ground foes and unlock stronger bleeding" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    for (1..4) |rank| {
        h.heroArena(g, .archer, .{ .x = 20, .y = 20 }, &.{});
        g.sim.growth.ranks.set(.caltrops, @intCast(rank));
        const id = h.spawnAt(g, .rat, .{ .x = 24, .y = 20 }, true);
        h.toughen(g.sim.pool.get(id).?);
        targeted(g, .caltrops, .{ .x = 22, .y = 20 });
        const foe = g.sim.pool.get(id).?;
        try std.testing.expectEqual(@as(i32, 23), foe.at.x);
        try std.testing.expectEqual(rules.Caltrops.pins(@intCast(rank)), foe.pin.turns);
        try std.testing.expectEqual(rank >= 2, foe.bleed.turns > 0);
        if (rank >= 2) try std.testing.expectEqual(@as(i32, @intCast(rank - 1)), foe.bleed.amount);
        const turns = g.sim.lv.caltrops[grid.Level.idx(foe.at)].turns;
        h.drawnOut(g);
        game.update(g, 1);
        try std.testing.expectEqual(turns, g.sim.lv.caltrops[grid.Level.idx(foe.at)].turns);
    }
    std.debug.print("tactical caltrops: 3 ranks, real enemy entries, pinning, bleed unlock/strength and idle lifetime checked\n", .{});
}

test "tactical overwatch fires once after movement and steady aim is consumed or canceled by movement" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .archer, from, &.{});
    skills.useSkill(g, .{ .act = .steady_aim, .by = .x });
    try std.testing.expectEqual(@as(u8, 1), g.sim.heroActor().?.tactics.steady);
    const boosted = combat.blowFor(g, .shoot).by;
    g.sim.heroActor().?.tactics.steady = 0;
    const plain = combat.blowFor(g, .shoot).by;
    try std.testing.expectEqual(plain.increase(.light) + rules.SteadyAim.bonus(1), boosted.increase(.light));
    h.drawnOut(g);
    g.sim.heroActor().?.tactics.steady = 2;
    const id = h.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, true);
    h.toughen(g.sim.pool.get(id).?);
    game.settle(g);
    const before = g.sim.pool.get(id).?.hp;
    targeted(g, .overwatch, .{ .x = 25, .y = 20 });
    try std.testing.expect(g.sim.pool.get(id).?.hp < before);
    try std.testing.expect(g.sim.heroActor().?.tactics.overwatch == null);
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.steady);
    try std.testing.expect(g.pic.owed[actor.Pool.slot(id)].reaction != null);
    try std.testing.expectEqual(before, g.pic.pictured[actor.Pool.slot(id)].hp);
    h.drawnOut(g);
    g.sim.heroActor().?.tactics.steady = 1;
    game.heroStep(g, .w, 0);
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.steady);
    std.debug.print("tactical archer: scaled preparation, single overwatch reaction, delayed pictured damage and movement cancellation checked\n", .{});
}

test "tactical gravity ranks pull and unlock pin while combustion consumes burn and hits each victim once" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    for (1..4) |rank| {
        h.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
        g.sim.growth.ranks.set(.gravity_well, @intCast(rank));
        const id = h.spawnAt(g, .rat, .{ .x = 24, .y = 20 }, false);
        targeted(g, .gravity_well, .{ .x = 22, .y = 20 });
        const foe = g.sim.pool.get(id).?;
        try std.testing.expectEqual(@as(i32, if (rank == 3) 22 else 23), foe.at.x);
        try std.testing.expectEqual(rank >= 2, foe.resilience.meters.get(.pin).percent > 0);
    }
    h.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    const id = h.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, false);
    const neighbor = h.spawnAt(g, .rat, .{ .x = 23, .y = 21 }, false);
    h.toughen(g.sim.pool.get(id).?);
    h.toughen(g.sim.pool.get(neighbor).?);
    const before = g.sim.pool.get(id).?.hp;
    const mana = g.sim.mana;
    targeted(g, .combustion, .{ .x = 23, .y = 20 });
    try std.testing.expectEqual(mana, g.sim.mana);
    try std.testing.expectEqual(game.Mode.play, g.mode);
    g.sim.pool.get(id).?.burn.start();
    targeted(g, .combustion, .{ .x = 23, .y = 20 });
    try std.testing.expectEqual(@as(u8, 0), g.sim.pool.get(id).?.burn.turns);
    try std.testing.expect(g.sim.pool.get(id).?.hp < before);
    try std.testing.expect(g.sim.pool.get(neighbor).?.hp < before);
    std.debug.print("tactical wizard: 3 pull/pin ranks, no-spend invalid combustion, consumed burn and neighboring explosion checked\n", .{});
}

test "tactical combustion consumes pictured burn at explosion time even when damage misses" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    var misses: usize = 0;
    for ([_]u64{ 0, 10 }) |seed| {
        h.heroArena(g, .wizard, from, &.{at});
        g.sim.lv.set(from, .reeds);
        const id = g.sim.lv.who(at);
        const foe = g.sim.pool.get(id).?;
        h.toughen(foe);
        foe.burn.start();
        game.settle(g);
        const slot = actor.Pool.slot(id);
        const hp = foe.hp;
        const burning = g.pic.pictured[slot].status.get(.burning);
        g.sim.rng = mathx.Rng.init(seed);
        targeted(g, .combustion, at);
        misses += @intFromBool(foe.hp == hp);
        try std.testing.expectEqual(@as(u8, 0), foe.burn.turns);
        g.pic.stepGlide(&g.sim, g.cloud, 0);
        g.pic.advance(&g.sim, game.CAST_S / 2);
        try std.testing.expectEqual(burning, g.pic.pictured[slot].status.get(.burning));
        try std.testing.expectEqual(hp, g.pic.pictured[slot].hp);
        g.pic.advance(&g.sim, game.CAST_S / 2 + 0.001);
        try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[slot].status.get(.burning));
        try std.testing.expectEqual(foe.hp, g.pic.pictured[slot].hp);
        h.drawnOut(g);
    }
    try std.testing.expectEqual(@as(usize, 1), misses);
    std.debug.print("tactical combustion: hit and miss retain burning until explosion, then consume it with damage\n", .{});
}

test "tactical barrier selects endpoints without spending then blocks paths until spent-turn expiry" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    const start = P{ .x = 22, .y = 19 };
    const end = P{ .x = 22, .y = 21 };
    h.heroArena(g, .wizard, from, &.{});
    const mana = g.sim.mana;
    targeted(g, .arcane_barrier, start);
    try std.testing.expectEqual(mana, g.sim.mana);
    try std.testing.expectEqual(start, g.barrier_start.?);
    g.mark = end;
    skills.confirmAim(g);
    const middle = P{ .x = 22, .y = 20 };
    try std.testing.expect(g.sim.lv.hasBarrier(middle));
    try std.testing.expect(!g.sim.lv.walkable(middle));
    try std.testing.expect(bow.aimable(&g.sim.lv, from, .{ .x = 24, .y = 20 }));
    try std.testing.expect(grid.clearLine(&g.sim.lv, from, .{ .x = 24, .y = 20 }));
    try std.testing.expectEqual(@as(usize, 1), bow.fly(&g.sim.lv, from, .{ .x = 24, .y = 20 }).len);
    try std.testing.expect(g.sim.lv.isLit(.{ .x = 24, .y = 20 }));
    h.drawnOut(g);
    for (0..rules.ArcaneBarrier.duration(1)) |_| {
        skills.useSkill(g, .{ .act = .wait, .by = .y });
        h.drawnOut(g);
    }
    try std.testing.expect(!g.sim.lv.hasBarrier(middle));
    try std.testing.expectEqual(grid.Tile.floor, g.sim.lv.at(middle));
    std.debug.print("tactical barrier: two-stage confirmation, transparent wall, movement/projectile blocking and exact expiry preserve terrain\n", .{});
}

test "tactical knight guard expires on action whirlwind hits neighbors and unyielding drains and toggles off empty" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .knight, from, &.{});
    skills.useSkill(g, .{ .act = .guard, .by = .x });
    try std.testing.expect(g.sim.heroActor().?.tactics.guard > 0);
    h.drawnOut(g);
    skills.useSkill(g, .{ .act = .wait, .by = .y });
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.guard);
    h.drawnOut(g);
    const a = h.spawnAt(g, .rat, from.add(.{ .x = 1, .y = 0 }), false);
    const b = h.spawnAt(g, .rat, from.add(.{ .x = -1, .y = 0 }), false);
    h.toughen(g.sim.pool.get(a).?);
    h.toughen(g.sim.pool.get(b).?);
    const before = g.sim.pool.get(a).?.hp;
    game.settle(g);
    skills.useSkill(g, .{ .act = .whirlwind, .by = .x });
    try std.testing.expect(g.sim.pool.get(a).?.hp < before and g.sim.pool.get(b).?.hp < before);
    h.drawnOut(g);
    h.heroArena(g, .knight, from, &.{});
    g.sim.mana = 4;
    skills.useSkill(g, .{ .act = .unyielding, .by = .x });
    try std.testing.expect(g.sim.heroActor().?.tactics.unyielding);
    try std.testing.expectEqual(@as(i32, 0), g.sim.mana);
    h.drawnOut(g);
    skills.useSkill(g, .{ .act = .unyielding, .by = .x });
    try std.testing.expect(!g.sim.heroActor().?.tactics.unyielding);
    h.drawnOut(g);
    g.sim.heroActor().?.tactics.unyielding = true;
    skills.useSkill(g, .{ .act = .wait, .by = .y });
    try std.testing.expect(!g.sim.heroActor().?.tactics.unyielding);
    std.debug.print("tactical knight: guard expiry, two-sided whirlwind, activation/upkeep and zero-mana stance exit checked\n", .{});
}

test "tactical regressions cover forced trap entries chest action cleanup and prepared previews" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .wizard, from, &.{});
    g.sim.growth.ranks.set(.gravity_well, 3);
    const id = h.spawnAt(g, .rat, .{ .x = 24, .y = 20 }, false);
    g.sim.lv.caltrops[grid.Level.idx(.{ .x = 23, .y = 20 })] = .{ .turns = 5, .rank = 2 };
    targeted(g, .gravity_well, .{ .x = 22, .y = 20 });
    try std.testing.expectEqual(@as(i32, 23), g.sim.pool.get(id).?.at.x);
    try std.testing.expect(g.sim.pool.get(id).?.bleed.turns > 0);
    h.heroArena(g, .knight, from, &.{});
    const bashed = h.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, false);
    h.toughen(g.sim.pool.get(bashed).?);
    g.sim.lv.caltrops[grid.Level.idx(.{ .x = 22, .y = 20 })] = .{ .turns = 5, .rank = 2 };
    combat.knock(g, .shield_bash, .e, .{ .from = from, .wait = 0 });
    try std.testing.expect(g.sim.pool.get(bashed).?.pin.turns > 0);
    try std.testing.expect(g.sim.pool.get(bashed).?.bleed.turns > 0);
    h.heroArena(g, .knight, from, &.{});
    const chest = P{ .x = 21, .y = 20 };
    g.sim.lv.set(chest, .chest);
    g.sim.heroActor().?.tactics = .{ .guard = 1, .overwatch = .e };
    game.character.openLoot(g, chest);
    try std.testing.expectEqual(@as(u8, 0), g.sim.heroActor().?.tactics.guard);
    try std.testing.expect(g.sim.heroActor().?.tactics.overwatch == null);
    h.heroArena(g, .archer, from, &.{});
    g.sim.heroActor().?.tactics.steady = 3;
    const preview = g.sim.growth.preparedHit(g.sim.heroAttrs(), g.sim.inventory.gear, .shoot, 3).?;
    try std.testing.expectEqualDeep(combat.blowFor(g, .shoot).hit(.shoot), preview);
    std.debug.print("tactical regressions: intermediate pull trap, bash trap, chest cleanup and shared prepared damage checked\n", .{});
}

test "tactical reaction recovery waits for impact and Harvest restores life from bleeding kills" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .knight, from, &.{});
    g.sim.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .life_on_kill, .value = 2 }, null, null, null } });
    game.syncStats(g);
    g.sim.heroActor().?.hp -= 10;
    const id = h.spawnAt(g, .rat, .{ .x = 21, .y = 20 }, true);
    game.settle(g);
    const before = g.sim.heroActor().?.hp;
    combat.reaction(g, id, .{ .dmg = 100 }, "counters", .{ .from = from, .wait = 0 }, id, null);
    try std.testing.expectEqual(before + 2, g.sim.heroActor().?.hp);
    g.pic.stepGlide(&g.sim, g.cloud, 0);
    g.pic.catchUp(&g.sim);
    try std.testing.expectEqual(before, g.pic.heroShown(&g.sim).?.hp);
    h.drawnOut(g);
    try std.testing.expectEqual(before + 2, g.pic.heroShown(&g.sim).?.hp);
    const bled = h.spawnAt(g, .rat, .{ .x = 23, .y = 20 }, false);
    g.sim.pool.get(bled).?.hp = 1;
    g.sim.pool.get(bled).?.bleed.startWith(2);
    g.sim.pool.get(bled).?.bleed.fresh = false;
    game.settle(g);
    skills.useSkill(g, .{ .act = .wait, .by = .y });
    try std.testing.expect(g.sim.pool.get(bled) == null);
    try std.testing.expectEqual(before + 4, g.sim.heroActor().?.hp);
    h.drawnOut(g);
    try std.testing.expectEqual(before + 4, g.pic.heroShown(&g.sim).?.hp);
    std.debug.print("tactical recovery: counter heal stays hidden until impact; Harvest also recovers on a bleed death\n", .{});
}

test "tactical overwatch reaction finishes before the next foe can expose its recovery" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const h = game.harness;
    const from = P{ .x = 20, .y = 20 };
    h.heroArena(g, .archer, from, &.{});
    g.sim.inventory.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .life_on_kill, .value = 2 }, null, null, null } });
    game.syncStats(g);
    g.sim.heroActor().?.hp -= 10;
    const rat = h.spawnAt(g, .rat, .{ .x = 24, .y = 20 }, true);
    g.sim.pool.get(rat).?.hp = 1;
    const bandit = h.spawnAt(g, .bandit_crossbowman, .{ .x = 24, .y = 21 }, true);
    const hidden = h.spawnAt(g, .rat, .{ .x = 40, .y = 20 }, false);
    g.sim.pool.get(hidden).?.hp = 1;
    g.sim.pool.get(hidden).?.bleed.startWith(2);
    g.sim.pool.get(hidden).?.bleed.fresh = false;
    game.settle(g);
    targeted(g, .overwatch, .{ .x = 25, .y = 20 });
    try std.testing.expect(g.pic.owed[actor.Pool.slot(rat)].reaction.?.recovery != null);
    g.pic.stepGlide(&g.sim, g.cloud, 0);
    const reaction_shot = g.pic.shot.?;
    const pictured_before = g.pic.heroShown(&g.sim).?.hp;
    const next_shot = g.pic.foe_shots[actor.Pool.slot(bandit)].?;
    try std.testing.expect(-next_shot.t >= -reaction_shot.t + reaction_shot.lands());
    g.pic.advance(&g.sim, 0.01);
    try std.testing.expectEqual(pictured_before, g.pic.heroShown(&g.sim).?.hp);
    h.drawnOut(g);
    std.debug.print("tactical reaction ordering: rat and crossbowman at equal range preserve arrow/heal then later attack order\n", .{});
}
