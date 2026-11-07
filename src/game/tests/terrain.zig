const std = @import("std");
const game = @import("../../game.zig");
const grid = @import("../../map/grid.zig");
const atlas = @import("../../map/atlas.zig");
const mathx = @import("../../core/mathx.zig");
const actor = @import("../../play/actor.zig");
const damage = @import("../../play/damage.zig");
const resilience = @import("../../play/resilience.zig");
const skillbar = @import("../../play/skillbar.zig");
const progress = @import("../../play/progress.zig");
const combat = @import("../combat.zig");
const overlay = @import("../overlay.zig");
const skills = @import("../skills.zig");
const rewards = @import("../rewards.zig");
const harness = @import("../harness.zig");
const fire = @import("../../map/fire.zig");
const ice = @import("../../map/ice.zig");
const areas = @import("../../play/area.zig");
const shock = @import("../../play/shock.zig");
const fireball = @import("../../play/fireball.zig");
const heroes = @import("../../play/hero.zig");
const P = mathx.P;

test "terrain follows every actor across movement and leaves base and saved buildup unchanged" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 23, .y = 20 };
    var checked: usize = 0;
    for (std.enums.values(actor.Kind)) |kind| {
        var a = actor.Actor.of(kind, at);
        a.resists = .initFill(20);
        a.resilience.meters.set(.burn, .{ .percent = 25, .turns = 3 });
        const base = a;
        g.sim.lv.set(at, .floor);
        const normal = g.sim.combatStats(&a);
        for ([_]grid.Tile{ .reeds, .grass, .tall_grass, .water, .shallows }) |tile| {
            g.sim.lv.set(at, tile);
            try std.testing.expectEqualDeep(normal.onRained(tile, 0), g.sim.combatStats(&a));
            try std.testing.expectEqualDeep(base, a);
            a.at = .{ .x = 24, .y = 20 };
            try std.testing.expectEqualDeep(normal, g.sim.combatStats(&a));
            a.at = at;
            checked += 1;
        }
    }
    std.debug.print("terrain movement: {d} actor/tile cases including flying bodies; base resistances and buildup preserved\n", .{checked});
}

test "terrain fire damage burn ticks and burn application share effective resistance" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 23, .y = 20 };
    const tiles = [_]grid.Tile{ .floor, .shallows, .grass };
    const expected = [_]i32{ 20, 15, 23 };
    var accepted: [tiles.len]usize = @splat(0);
    var fresh: [tiles.len]usize = @splat(0);
    for (tiles, expected, 0..) |tile, want, k| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
        const a = g.sim.pool.get(harness.foeId(0)).?;
        harness.toughen(a);
        g.sim.lv.set(at, tile);
        const before = a.hp;
        combat.arrowHit(g, harness.foeId(0), .{ .blow = .{ .elements = .initDefault(0, .{ .fire = 20 }) } }, .fireball, .{ .from = g.sim.heroAt().?, .wait = 0 });
        try std.testing.expectEqual(want, before - a.hp);
        a.burn = .{ .turns = 2 };
        g.sim.ran[harness.foeSlot(0)] = .initEmpty();
        const burnt = a.hp;
        combat.burnHarm(g, harness.foeId(0));
        try std.testing.expectEqual(damage.resisted(4, g.sim.combatStats(a).elements.get(.fire)), burnt - a.hp);
        g.sim.rng = mathx.Rng.init(1234);
        for (0..2048) |_| {
            a.resilience.meters.set(.burn, .{ .percent = 25, .turns = 2 });
            accepted[k] += @intFromBool(g.sim.takeStatus(a, .burn));
        }
        g.sim.rng = mathx.Rng.init(73456);
        for (0..2048) |_| {
            a.resilience = .{};
            fresh[k] += @intFromBool(g.sim.procStatus(a, .burn, 50));
        }
    }
    try std.testing.expect(accepted[1] < accepted[0] and accepted[0] < accepted[2]);
    try std.testing.expect(fresh[1] < fresh[0] and fresh[0] < fresh[2]);
    std.debug.print("terrain fire: 20 damage becomes 20/15/23 on floor/water/grass; real burn ticks checked; applications {d}/{d}/{d} of 2048\n", .{ accepted[0], accepted[1], accepted[2] });
    std.debug.print("terrain burn vulnerability: fresh 50% procs land {d}/{d}/{d} times on floor/water/grass without buildup\n", .{ fresh[0], fresh[1], fresh[2] });
}

test "rain out of doors dampens fire hits and ignition, and the card names it beneath the tile" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    _ = w.add(.{ .procgen = .{ .floor = .{ .wilds = .{} }, .sky = .{ .weather = .drizzle } } }).?;
    const at = P{ .x = 23, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
    g.sim.map = w;
    g.sim.node = 0;
    const a = g.sim.pool.get(harness.foeId(0)).?;
    harness.toughen(a);
    g.sim.outdoors = true;
    const wet = g.sim.combatStats(a);
    g.sim.outdoors = false;
    const dry = g.sim.combatStats(a);
    var dry_lit: usize = 0;
    g.sim.rng = mathx.Rng.init(0xF1AE);
    for (0..2048) |_| {
        a.resilience = .{};
        dry_lit += @intFromBool(g.sim.ignite(harness.foeSlot(0), a));
    }
    g.sim.outdoors = true;
    var wet_lit: usize = 0;
    g.sim.rng = mathx.Rng.init(0xF1AE);
    for (0..2048) |_| {
        a.resilience = .{};
        wet_lit += @intFromBool(g.sim.ignite(harness.foeSlot(0), a));
    }
    try std.testing.expectEqual(dry.elements.get(.fire) + 5, wet.elements.get(.fire));
    try std.testing.expectEqual(dry.statuses.get(.burn) + 10, wet.statuses.get(.burn));
    try std.testing.expect(wet_lit < dry_lit);
    a.burn = .{};
    a.resilience = .{};
    const before = a.hp;
    combat.arrowHit(g, harness.foeId(0), .{ .blow = .{ .elements = .initDefault(0, .{ .fire = 40 }) } }, .fireball, .{ .from = g.sim.heroAt().?, .wait = 0 });
    try std.testing.expectEqual(damage.resisted(40, wet.elements.get(.fire)), before - a.hp);
    try std.testing.expect(before - a.hp < damage.resisted(40, dry.elements.get(.fire)));
    game.settle(g);
    var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
    var body: [overlay.TIP_BODY_MAX]u8 = undefined;
    const tip = overlay.tipOf(g, .{ .actor = 2 }, &title, &body).?;
    var expected: [256]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "{d}/{d} HP\n---\nFloor\nNo Effects\nDrizzle\n+5% Fire Resistance\n-10% Chance To Burn", .{ g.pic.pictured[1].hp, a.max }), tip.body);
    std.debug.print("rain: a drizzle takes 40 fire to {d} against {d} dry; ignitions {d} of 2048 against {d} dry\n", .{ before - a.hp, damage.resisted(40, dry.elements.get(.fire)), wet_lit, dry_lit });
}

test "terrain reeds affect real hero hits without applying harm or statuses on misses" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    harness.arena(g, from, &.{at});
    g.sim.lv.set(from, .reeds);
    g.sim.lv.set(at, .reeds);
    const a = g.sim.pool.get(harness.foeId(0)).?;
    harness.toughen(a);
    var misses: usize = 0;
    g.sim.rng = mathx.Rng.init(0x123AF);
    for (0..512) |_| {
        a.hp = harness.TEST_HP;
        a.resilience = .{};
        a.bleed = .{};
        const hp = a.hp;
        combat.wound(g, harness.foeId(0), .{ .dmg = 1, .effect = .{ .bleed = 100, .bleed_damage = 2 } }, "strikes", .{ .from = from, .wait = 0 });
        if (a.hp == hp) {
            misses += 1;
            try std.testing.expectEqual(@as(u8, 0), a.bleed.turns);
            try std.testing.expectEqual(@as(u8, 0), a.resilience.peak().percent);
        }
    }
    try std.testing.expect(misses > 20 and misses < 85);
    std.debug.print("terrain reeds: {d}/512 real attacks miss; missed blows leave HP, bleed and resistance unchanged\n", .{misses});
}

test "terrain inspection uses pictured characters and tiles while excluding hidden and unborn actors" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    harness.arena(g, from, &.{at});
    const a = g.sim.pool.get(harness.foeId(0)).?;
    g.sim.lv.set(at, .shallows);
    game.settle(g);
    const shown = g.pic.pictured[1].hp;
    a.hp = 1;
    a.burn.start();
    var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
    var body: [overlay.TIP_BODY_MAX]u8 = undefined;
    const tip = overlay.tipOf(g, .{ .actor = 2 }, &title, &body).?;
    var expected: [256]u8 = undefined;
    try std.testing.expectEqualStrings("Rat", tip.title);
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "{d}/{d} HP\n---\nShallows\n+25% Fire Resistance\n-25% Lightning Resistance\n-25% Chance To Burn", .{ shown, a.max }), tip.body);
    try std.testing.expect(std.mem.indexOf(u8, tip.body, "Burning:") == null);
    var parts: [overlay.SPOTS_MAX]overlay.Part = undefined;
    var found: usize = 0;
    for (overlay.spotsOf(g, &parts)) |part| if (part.spot == .actor) {
        found += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), found);
    g.sim.lv.lit[grid.Level.idx(at)] = false;
    try std.testing.expect(overlay.tipOf(g, .{ .actor = 2 }, &title, &body) == null);
    g.sim.lv.lit[grid.Level.idx(at)] = true;
    g.pic.split_from[1] = 0;
    try std.testing.expect(overlay.tipOf(g, .{ .actor = 2 }, &title, &body) == null);
    std.debug.print("terrain inspection: pictured HP, separate terrain effects, title case, visible actor spots and hidden/unborn exclusions checked\n", .{});
}

test "terrain inspection retains the drawn tile and modifiers until freezing and melting land" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 23, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
    g.sim.lv.set(at, .shallows);
    game.settle(g);
    const area = areas.patch(&g.sim.lv, at, 0);
    var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
    var body: [overlay.TIP_BODY_MAX]u8 = undefined;
    var before: [overlay.TIP_BODY_MAX]u8 = undefined;
    var checked: usize = 0;
    for ([_]bool{ true, false }) |freezing| {
        const tip = overlay.tipOf(g, .{ .actor = harness.foeId(0) }, &title, &body).?;
        const n = tip.body.len;
        @memcpy(before[0..n], tip.body);
        if (freezing) combat.coldLands(g, &area, 0.3) else combat.fireLands(g, at, 0, .{ .chance = 0 }, 0.3);
        const held = overlay.tipOf(g, .{ .actor = harness.foeId(0) }, &title, &body).?;
        try std.testing.expectEqualStrings(before[0..n], held.body);
        g.pic.advance(&g.sim, 0.4);
        const landed = overlay.tipOf(g, .{ .actor = harness.foeId(0) }, &title, &body).?;
        try std.testing.expect(!std.mem.eql(u8, before[0..n], landed.body));
        checked += 1;
    }
    std.debug.print("terrain inspection: {d} transitions retain the drawn tile and modifiers until impact\n", .{checked});
}

test "inspection includes visible actors beside the HUD and excludes actors beyond the screen" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 23, .y = 20 };
    var checked: usize = 0;
    for (game.SCREENS) |screen| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
        g.screen = screen;
        const shown = P{ .x = screen.x - game.CELL - 24, .y = overlay.hudLayout(g).top + 24 };
        g.cam = .{ .x = @floatFromInt(at.x * game.CELL - shown.x), .y = @floatFromInt(at.y * game.CELL - shown.y) };
        g.st.pointer = shown.add(.{ .x = game.HALF_CELL, .y = game.HALF_CELL });
        const hovered = overlay.hovered(g);
        try std.testing.expect(hovered != null);
        try std.testing.expectEqual(game.Spot{ .actor = 2 }, hovered.?.spot);
        var parts: [overlay.SPOTS_MAX]overlay.Part = undefined;
        for ([_]P{
            .{ .x = -game.CELL, .y = shown.y },
            .{ .x = screen.x, .y = shown.y },
            .{ .x = shown.x, .y = -game.CELL },
            .{ .x = shown.x, .y = screen.y },
        }) |outside| {
            g.cam = .{ .x = @floatFromInt(at.x * game.CELL - outside.x), .y = @floatFromInt(at.y * game.CELL - outside.y) };
            for (overlay.spotsOf(g, &parts)) |part| {
                try std.testing.expect(part.spot != .actor or part.spot.actor != 2);
            }
            checked += 1;
        }
    }
    std.debug.print("actor inspection: 3 visible HUD gutters and {d} offscreen boundaries checked\n", .{checked});
}

test "foe inspection keeps basic health separate from terrain effects" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 23, .y = 20 };
    const id = harness.spawnAt(g, .beefy_pib, at, true);
    g.sim.lv.set(at, .grass);
    game.settle(g);
    g.pic.pictured[actor.Pool.slot(id)].hp = 12;
    var title: [overlay.TIP_TITLE_MAX]u8 = undefined;
    var body: [overlay.TIP_BODY_MAX]u8 = undefined;
    const tip = overlay.tipOf(g, .{ .actor = id }, &title, &body).?;
    try std.testing.expectEqualStrings("Beefy Pib", tip.title);
    try std.testing.expectEqualStrings("12/40 HP\n---\nGrass\n-15% Fire Resistance\n+15% Chance To Burn", tip.body);
    g.sim.lv.set(at, .floor);
    const neutral = overlay.tipOf(g, .{ .actor = id }, &title, &body).?;
    try std.testing.expectEqualStrings("12/40 HP\n---\nFloor\nNo Effects", neutral.body);
    std.debug.print("foe cards: title and presented HP, divider, tile and signed effects only; neutral terrain states no effects\n", .{});
}

test "projectiles fire at empty dark cells in line of sight and stop at the first actor even on a miss" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const near = P{ .x = 23, .y = 20 };
    const far = P{ .x = 25, .y = 20 };
    inline for ([_]skillbar.Act{ .shoot, .burning_arrow, .spark }) |act| {
        harness.heroArena(g, if (act == .spark) .wizard else .archer, from, &.{});
        const clock = g.sim.clock;
        harness.use(g, act);
        try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
        try std.testing.expectEqual(clock, g.sim.clock);
        g.mode.aim.mark = far;
        g.sim.lv.lit[grid.Level.idx(far)] = false;
        try std.testing.expect(skills.aimable(g, from, far));
        skills.confirmAim(g);
        try std.testing.expect(g.mode == .aim and g.mode.aim.askedHere());
        try std.testing.expectEqual(clock, g.sim.clock);
        skills.confirmAim(g);
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
        try std.testing.expect(!std.meta.eql(clock, g.sim.clock));
        try std.testing.expect(g.pic.shot.?.flight.struck == null);

        harness.heroArena(g, if (act == .spark) .wizard else .archer, from, &.{ near, far });
        harness.toughenFoes(g);
        g.sim.pool.get(harness.foeId(0)).?.clock.stun();
        g.sim.pool.get(harness.foeId(1)).?.clock.stun();
        harness.use(g, act);
        g.mode.aim.mark = far;
        const untouched = g.sim.pool.get(harness.foeId(1)).?.hp;
        skills.confirmAim(g);
        try std.testing.expectEqual(@as(u16, 2), g.pic.shot.?.flight.struck.?.body);
        try std.testing.expectEqual(untouched, g.sim.pool.get(harness.foeId(1)).?.hp);

        harness.heroArena(g, if (act == .spark) .wizard else .archer, from, &.{});
        g.sim.lv.set(near, .wall);
        game.castSight(g, from);
        harness.use(g, act);
        g.mode.aim.mark = far;
        const before = g.sim.clock;
        const mana = g.sim.mana;
        skills.confirmAim(g);
        try std.testing.expectEqual(game.Mode.aim, std.meta.activeTag(g.mode));
        try std.testing.expectEqual(before, g.sim.clock);
        try std.testing.expectEqual(mana, g.sim.mana);
    }
    var missed: usize = 0;
    var rng = mathx.Rng.init(0x51273);
    for (0..128) |_| {
        harness.arena(g, from, &.{ near, far });
        harness.toughenFoes(g);
        g.sim.lv.set(from, .reeds);
        g.sim.pool.get(harness.foeId(0)).?.clock.stun();
        g.sim.pool.get(harness.foeId(1)).?.clock.stun();
        game.castSight(g, from);
        g.sim.rng = rng;
        harness.use(g, .shoot);
        g.mode.aim.mark = far;
        skills.confirmAim(g);
        rng = g.sim.rng;
        missed += @intFromBool(g.sim.pool.get(harness.foeId(0)).?.hp == harness.TEST_HP);
        try std.testing.expectEqual(@as(u16, 2), g.pic.shot.?.flight.struck.?.body);
        try std.testing.expectEqual(harness.TEST_HP, g.sim.pool.get(harness.foeId(1)).?.hp);
    }
    try std.testing.expect(missed > 0);
    var state = progress.State.of(.archer);
    state.active_points = 10;
    const before = state;
    try std.testing.expect(!state.learn(.archer, .shoot));
    try std.testing.expectEqualDeep(before, state);
    state.ranks.set(.shoot, 3);
    try std.testing.expectEqual(@as(i32, 0), state.damageBonus(.shoot));
    try std.testing.expect(state.refundBasicRanks());
    try std.testing.expectEqual(@as(u16, 12), state.active_points);
    try std.testing.expectEqual(@as(u8, 1), state.ranks.get(.shoot));
    const refunded = state;
    try std.testing.expect(!state.refundBasicRanks());
    try std.testing.expectEqualDeep(refunded, state);
    harness.arena(g, from, &.{});
    g.sim.growth = state;
    g.sim.growth.ranks.set(.shoot, 3);
    game.resumeRun(g);
    try std.testing.expectEqual(@as(u16, 14), g.sim.growth.active_points);
    try std.testing.expectEqual(@as(u8, 1), g.sim.growth.ranks.get(.shoot));
    try std.testing.expect(g.sim.unsaved);
    std.debug.print("open projectile simulation: 3 attacks check empty/dark fire, first collision, no out-of-LOS spending; Shoot cannot upgrade or gain legacy rank damage\n", .{});
    std.debug.print("nonpiercing misses: {d}/128 intercepted attacks missed; all 128 stopped at the first body, refunds apply once\n", .{missed});
}

fn meadow(g: *game.Game, around: P, r: i32) void {
    var cells = grid.Cells.around(around, r);
    while (cells.next()) |p| g.sim.lv.set(p, .grass);
    game.settle(g);
}

fn alight(lv: *const grid.Level) usize {
    return grid.CELLS - std.mem.count(u8, &lv.flames, &.{0});
}

test "a fireball on grass sets some alight as its blast lands, and the fire spreads, smokes and burns down to dirt within its heat" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 26, .y = 20 };
    var caught: usize = 0;
    var burnt: usize = 0;
    var longest: usize = 0;
    var smoked = false;
    const blazes: usize = 40;
    for (0..blazes) |seed| {
        harness.heroArena(g, .wizard, from, &.{at});
        harness.toughenFoes(g);
        g.sim.unkillable = true;
        meadow(g, at, 5);
        g.sim.rng = mathx.Rng.init(seed);
        harness.aimAt(g, .fireball, at);
        const lit = alight(&g.sim.lv);
        if (lit == 0) continue;
        caught += 1;
        try std.testing.expect(harness.logged(g, fire.CATCHES));
        try std.testing.expect(std.mem.allEqual(u8, &g.pic.flames_shown, 0));
        harness.drawnOut(g);
        try std.testing.expectEqualSlices(u8, &g.sim.lv.flames, &g.pic.flames_shown);
        var turns: usize = 0;
        while (alight(&g.sim.lv) > 0) : (turns += 1) {
            try std.testing.expect(turns < 30);
            smoked = smoked or !std.mem.allEqual(u16, &g.sim.lv.smoke, 0);
            harness.useAct(g, .wait);
            harness.drawnOut(g);
        }
        longest = @max(longest, turns);
        for (g.sim.lv.tile, 0..) |t, i| {
            if (t != fire.ASH) continue;
            burnt += 1;
            try std.testing.expect(mathx.dist(at, grid.Level.of(i)) <= fireball.BLAST + @as(i32, fireball.KINDLE.heat));
        }
    }
    g.sim.unkillable = false;
    std.debug.print("a fireball into a meadow: {d}/{d} set it alight, {d:.1} cells burnt to dirt on average, out within {d} turns\n", .{ caught, blazes, @as(f32, @floatFromInt(burnt)) / @as(f32, @floatFromInt(@max(caught, 1))), longest });
    try std.testing.expect(caught > blazes * 9 / 10 and smoked);
}

test "grass burning out while a fireball flies stays drawn as grass under its held flames until the blast lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 26, .y = 20 };
    const old = P{ .x = 20, .y = 27 };
    var held: usize = 0;
    for (0..harness.TRIES) |seed| {
        harness.heroArena(g, .wizard, from, &.{at});
        harness.toughenFoes(g);
        g.sim.lv.set(old, .grass);
        fire.lay(&g.sim.lv, old, 1, 0);
        meadow(g, at, 5);
        g.sim.rng = mathx.Rng.init(seed);
        harness.aimAt(g, .fireball, at);
        try std.testing.expectEqual(fire.ASH, g.sim.lv.at(old));
        if (alight(&g.sim.lv) == 0) continue;
        held += 1;
        try std.testing.expectEqual(grid.Tile.grass, g.pic.tileShown(&g.sim, old));
        harness.drawnOut(g);
        try std.testing.expectEqual(fire.ASH, g.pic.tileShown(&g.sim, old));
    }
    try std.testing.expect(held > 0);
}

test "reeds burnt down and their flames fade out over the ash instead of vanishing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 22, .y = 20 };
    harness.heroArena(g, .wizard, .{ .x = 20, .y = 20 }, &.{});
    g.sim.lv.set(at, .reeds);
    fire.lay(&g.sim.lv, at, 1, 0);
    game.settle(g);
    const i = grid.Level.idx(at);
    try std.testing.expect(g.pic.flamesShown(i));
    harness.useAct(g, .wait);
    try std.testing.expectEqual(fire.ASH, g.sim.lv.at(at));
    var waited: f32 = 0;
    while (g.pic.fadingBurnt(i) == null) : (waited += 0.01) {
        try std.testing.expect(waited < 3);
        g.pic.advance(&g.sim, 0.01);
    }
    try std.testing.expect(!g.pic.flamesShown(i) and g.pic.ember(i) > 0.9);
    try std.testing.expectEqual(grid.Tile.reeds, g.pic.burntShown(&g.sim.lv).?.at(at));
    g.pic.advance(&g.sim, game.presentation.EMBER_S / 2);
    const half = g.pic.ember(i);
    try std.testing.expect(half > 0.3 and half < 0.7);
    g.pic.advance(&g.sim, game.presentation.EMBER_S);
    try std.testing.expect(g.pic.fadingBurnt(i) == null and g.pic.burntShown(&g.sim.lv) == null and g.pic.ember(i) == 0);
    std.debug.print("burnt reeds: out after {d:.2} s, half faded at {d:.2}, gone after {d} s\n", .{ waited, half, game.presentation.EMBER_S });
}

test "a burning arrow sets grass alight far less often than a fireball" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var caught = [_]usize{ 0, 0 };
    for ([_]heroes.Class{ .wizard, .archer }, [_]skillbar.Act{ .fireball, .burning_arrow }, &caught) |c, act, *n| {
        for (0..harness.TRIES) |seed| {
            harness.heroArena(g, c, .{ .x = 20, .y = 20 }, &.{});
            meadow(g, .{ .x = 25, .y = 20 }, 2);
            g.sim.rng = mathx.Rng.init(seed);
            harness.aimAt(g, act, .{ .x = 25, .y = 20 });
            n.* += @intFromBool(alight(&g.sim.lv) > 0);
        }
    }
    std.debug.print("into empty grass: a fireball set it alight {d}/{d} times, a burning arrow {d}/{d}\n", .{ caught[0], harness.TRIES, caught[1], harness.TRIES });
    try std.testing.expect(caught[1] > 0 and caught[1] * 3 < caught[0]);
}

test "flames scorch the body standing in them each turn and may set it burning, the picture taking it as it lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    var ignited: usize = 0;
    var scorch: i32 = 0;
    for (0..harness.TRIES) |seed| {
        harness.arena(g, at, &.{});
        meadow(g, at, 1);
        const h = g.sim.heroActor().?;
        harness.toughen(h);
        fire.lay(&g.sim.lv, at, fire.BURNS, 0);
        game.settle(g);
        g.sim.rng = mathx.Rng.init(seed);
        scorch = fire.scorch(g.sim.combatStats(h).elements);
        harness.useAct(g, .wait);
        try std.testing.expectEqual(harness.TEST_HP - scorch, h.hp);
        try std.testing.expectEqual(harness.TEST_HP, g.pic.heroShown(&g.sim).?.hp);
        ignited += @intFromBool(h.burn.turns > 0);
        g.st = .{};
        var t: f32 = 0;
        while (t < 1 and !harness.caughtUp(g, g.sim.heroSlot().?)) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
        try std.testing.expect(t < 1);
        try std.testing.expectEqual(h.burn.turns, g.pic.heroShown(&g.sim).?.status.get(.burning));
    }
    try std.testing.expect(harness.logged(g, fire.NAME));
    std.debug.print("a turn standing in flames on grass: scorched for {d}, set burning {d}/{d} times\n", .{ scorch, ignited, harness.TRIES });
    try std.testing.expect(ignited > 0 and ignited < harness.TRIES);
}

test "a frost nova puts out most flames round it and some burning foes, the picture taking both as it lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const foe = P{ .x = 21, .y = 20 };
    const seeds: usize = 40;
    var laid: usize = 0;
    var doused: usize = 0;
    var quenched: usize = 0;
    for (0..seeds) |seed| {
        harness.heroArena(g, .wizard, from, &.{foe});
        harness.toughenFoes(g);
        g.sim.unkillable = true;
        meadow(g, from, 2);
        var ring = grid.Cells.around(from, 2);
        while (ring.next()) |p| if (!p.eq(from) and !p.eq(foe)) fire.lay(&g.sim.lv, p, fire.BURNS, 0);
        const rat = g.sim.pool.get(harness.foeId(0)).?;
        rat.burn.start();
        game.settle(g);
        const before = alight(&g.sim.lv);
        g.sim.rng = mathx.Rng.init(seed);
        harness.use(g, .frost_nova);
        laid += before;
        doused += before - alight(&g.sim.lv);
        try std.testing.expectEqual(before, grid.CELLS - std.mem.count(u8, &g.pic.flames_shown, &.{0}));
        const out = rat.burn.turns == 0;
        quenched += @intFromBool(out);
        if (out) try std.testing.expect(g.pic.pictured[harness.foeSlot(0)].status.get(.burning) > 0);
        harness.drawnOut(g);
        try std.testing.expectEqualSlices(u8, &g.sim.lv.flames, &g.pic.flames_shown);
        if (out) try std.testing.expectEqual(@as(u8, 0), g.pic.pictured[harness.foeSlot(0)].status.get(.burning));
    }
    g.sim.unkillable = false;
    std.debug.print("frost nova over burning grass: {d}/{d} flames put out, a burning rat quenched {d}/{d} times\n", .{ doused, laid, quenched, seeds });
    try std.testing.expect(doused * 100 > laid * 70);
    try std.testing.expect(quenched > seeds / 4 and quenched < seeds * 3 / 4);
}

test "a frost nova freezes the shallows round it, drawn as it lands, cutting conduction until they thaw" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const near = P{ .x = 21, .y = 20 };
    const far = P{ .x = 23, .y = 20 };
    harness.heroArena(g, .wizard, from, &.{});
    var pool = grid.Cells.around(from, 3);
    while (pool.next()) |p| g.sim.lv.set(p, .shallows);
    game.settle(g);
    try std.testing.expect(shock.conducted(&g.sim.lv, from).has(.{ .x = 22, .y = 20 }));
    harness.aimAt(g, .frost_nova, from);
    try std.testing.expect(g.sim.lv.frozen(near) and !g.sim.lv.at(near).wet());
    try std.testing.expectEqual(grid.Tile.shallows, g.sim.lv.at(from));
    try std.testing.expectEqual(grid.Tile.shallows, g.sim.lv.at(far));
    try std.testing.expectEqual(grid.Tile.shallows, g.pic.tileShown(&g.sim, near));
    try std.testing.expectEqual(grid.Tile.shallows, g.pic.groundShown(&g.sim).at(near));
    harness.drawnOut(g);
    try std.testing.expectEqual(grid.Tile.ice, g.pic.tileShown(&g.sim, near));
    try std.testing.expectEqual(grid.Tile.ice, g.pic.groundShown(&g.sim).at(near));
    try std.testing.expect(harness.logged(g, ice.FREEZES));
    try std.testing.expectEqual(@as(usize, 1), shock.conducted(&g.sim.lv, from).n);
    var turns: usize = 0;
    while (g.sim.lv.frozen(near)) : (turns += 1) {
        try std.testing.expect(turns <= ice.THAWS);
        harness.useAct(g, .wait);
        harness.drawnOut(g);
    }
    try std.testing.expectEqual(grid.Tile.shallows, g.sim.lv.at(near));
    std.debug.print("frost nova over shallows: frozen round the caster, thawed {d} waits after the casting turn\n", .{turns});
    try std.testing.expectEqual(@as(usize, ice.THAWS - 1), turns);
}

test "fire landing on frozen shallows melts them and boils them into steam" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 22, .y = 22 };
    harness.heroArena(g, .wizard, from, &.{});
    var pool = grid.Cells.around(from, 2);
    while (pool.next()) |p| if (!p.eq(from)) g.sim.lv.set(p, .shallows);
    game.settle(g);
    harness.aimAt(g, .frost_nova, from);
    harness.drawnOut(g);
    try std.testing.expect(g.sim.lv.frozen(at));
    harness.aimAt(g, .fireball, at);
    try std.testing.expectEqual(grid.Tile.shallows, g.sim.lv.at(at));
    try std.testing.expect(g.sim.lv.frozen(.{ .x = 21, .y = 19 }));
    try std.testing.expectEqual(grid.Tile.ice, g.pic.tileShown(&g.sim, at));
    try std.testing.expectEqual(grid.Tile.ice, g.pic.groundShown(&g.sim).at(at));
    harness.drawnOut(g);
    try std.testing.expectEqual(grid.Tile.shallows, g.pic.tileShown(&g.sim, at));
    try std.testing.expectEqual(grid.Tile.shallows, g.pic.groundShown(&g.sim).at(at));
    try std.testing.expect(g.sim.lv.volumeAt(.steam, at) > 0);
}

test "a pyre bloat's melted ice stays drawn until its death burst lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 22, .y = 20 };
    var checked: usize = 0;
    for ([_]bool{ false, true }) |own_turn| {
        harness.arena(g, from, &.{});
        const bloat = harness.spawnAt(g, .pyre_bloat, .{ .x = 21, .y = 20 }, own_turn);
        g.sim.lv.set(at, .shallows);
        const area = areas.patch(&g.sim.lv, at, 0);
        try std.testing.expect(rewards.freezeRound(&g.sim, &area));
        game.settle(g);
        if (own_turn) {
            g.sim.pool.get(bloat).?.pin.extend(2);
            harness.use(g, .wait);
        } else {
            combat.wound(g, bloat, .{ .dmg = 100, .hit_checked = true }, combat.SHOOT, .{ .from = from, .wait = 0.3 });
        }
        try std.testing.expectEqual(grid.Tile.shallows, g.sim.lv.at(at));
        g.st = .{};
        var frames: usize = 0;
        while (!g.pic.pictured[actor.Pool.slot(bloat)].down()) : (frames += 1) {
            try std.testing.expect(frames < 200);
            try std.testing.expectEqual(grid.Tile.ice, g.pic.tileShown(&g.sim, at));
            try harness.expectGroundShown(g);
            game.update(g, harness.TEST_DT);
        }
        try std.testing.expect(frames > 0);
        harness.drawnOut(g);
        try std.testing.expectEqual(grid.Tile.shallows, g.pic.tileShown(&g.sim, at));
        checked += 1;
    }
    std.debug.print("pyre ice: {d} death paths hold the frozen picture until the burst lands\n", .{checked});
}

test "cold leaves the shallows a swimmer lies in open" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 22, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    var pool = grid.Cells.around(at, 1);
    while (pool.next()) |p| g.sim.lv.set(p, .shallows);
    _ = g.sim.pool.spawn(&g.sim.lv, actor.Actor.of(.bog_leech, at));
    const area = areas.patch(&g.sim.lv, at, 1);
    try std.testing.expect(rewards.freezeRound(&g.sim, &area));
    try std.testing.expectEqual(grid.Tile.shallows, g.sim.lv.at(at));
    try std.testing.expect(g.sim.lv.frozen(.{ .x = 23, .y = 20 }));
}

test "rain out of doors sets less grass alight" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const w = try atlas.testAtlas();
    defer std.testing.allocator.destroy(w);
    w.* = .{};
    _ = w.add(.{ .procgen = .{ .floor = .{ .wilds = .{} }, .sky = .{ .weather = .drizzle } } }).?;
    const at = P{ .x = 25, .y = 20 };
    var caught = [_]usize{ 0, 0 };
    for ([_]bool{ false, true }, &caught) |wet, *n| {
        g.sim.rng = mathx.Rng.init(0xA5);
        for (0..harness.TRIES) |_| {
            g.sim.map = null;
            harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
            meadow(g, at, 1);
            g.sim.map = w;
            g.sim.node = 0;
            g.sim.outdoors = wet;
            _ = rewards.kindleRound(&g.sim, at, fireball.BLAST, fireball.KINDLE);
            n.* += alight(&g.sim.lv);
        }
    }
    g.sim.map = null;
    std.debug.print("a fireball's kindling over {d} blasts: {d} cells caught dry, {d} in a drizzle\n", .{ harness.TRIES, caught[0], caught[1] });
    try std.testing.expect(caught[1] < caught[0]);
}
