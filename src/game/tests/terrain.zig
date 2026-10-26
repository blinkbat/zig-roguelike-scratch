const std = @import("std");
const game = @import("../../game.zig");
const grid = @import("../../map/grid.zig");
const mathx = @import("../../core/mathx.zig");
const actor = @import("../../play/actor.zig");
const damage = @import("../../play/damage.zig");
const resilience = @import("../../play/resilience.zig");
const terrain = @import("../../play/terrain.zig");
const skillbar = @import("../../play/skillbar.zig");
const progress = @import("../../play/progress.zig");
const combat = @import("../combat.zig");
const overlay = @import("../overlay.zig");
const character = @import("../character.zig");
const skills = @import("../skills.zig");
const harness = @import("../harness.zig");
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
            try std.testing.expectEqualDeep(normal.on(tile), g.sim.combatStats(&a));
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
        const a = g.sim.pool.get(2).?;
        harness.toughen(a);
        g.sim.lv.set(at, tile);
        const before = a.hp;
        combat.arrowHit(g, 2, .{ .blow = .{ .elements = .initDefault(0, .{ .fire = 20 }) } }, .fireball, .{ .from = g.sim.heroAt().?, .wait = 0 });
        try std.testing.expectEqual(want, before - a.hp);
        a.burn = .{ .turns = 2 };
        g.sim.ran[actor.Pool.slot(2)] = .initEmpty();
        const burnt = a.hp;
        combat.burnHarm(g, 2);
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

test "terrain reeds affect real hero hits without applying harm or statuses on misses" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    harness.arena(g, from, &.{at});
    g.sim.lv.set(from, .reeds);
    g.sim.lv.set(at, .reeds);
    const a = g.sim.pool.get(2).?;
    harness.toughen(a);
    var misses: usize = 0;
    g.sim.rng = mathx.Rng.init(0x123AF);
    for (0..512) |_| {
        a.hp = harness.TEST_HP;
        a.resilience = .{};
        a.bleed = .{};
        const hp = a.hp;
        combat.wound(g, 2, .{ .dmg = 1, .effect = .{ .bleed = 100, .bleed_damage = 2 } }, "strikes", .{ .from = from, .wait = 0 });
        if (a.hp == hp) {
            misses += 1;
            try std.testing.expectEqual(@as(u8, 0), a.bleed.turns);
            try std.testing.expectEqual(@as(u8, 0), a.resilience.peak().percent);
        }
    }
    try std.testing.expect(misses > 20 and misses < 85);
    const view = character.bookView(g, &g.nearby);
    try std.testing.expectEqual(terrain.of(.reeds), view.environment);
    std.debug.print("terrain reeds: {d}/512 real attacks miss; missed blows leave HP, bleed and resistance unchanged\n", .{misses});
}

test "terrain inspection uses pictured characters and tiles while excluding hidden and unborn actors" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const at = P{ .x = 23, .y = 20 };
    harness.arena(g, from, &.{at});
    const a = g.sim.pool.get(2).?;
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
    const far = P{ .x = 26, .y = 20 };
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
        try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
        try std.testing.expect(!std.meta.eql(clock, g.sim.clock));
        try std.testing.expect(g.pic.shot.?.flight.struck == null);

        harness.heroArena(g, if (act == .spark) .wizard else .archer, from, &.{ near, far });
        harness.toughenFoes(g);
        g.sim.pool.get(2).?.clock.stun();
        g.sim.pool.get(3).?.clock.stun();
        harness.use(g, act);
        g.mode.aim.mark = far;
        const untouched = g.sim.pool.get(3).?.hp;
        skills.confirmAim(g);
        try std.testing.expectEqual(@as(u16, 2), g.pic.shot.?.flight.struck.?.body);
        try std.testing.expectEqual(untouched, g.sim.pool.get(3).?.hp);

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
        g.sim.pool.get(2).?.clock.stun();
        g.sim.pool.get(3).?.clock.stun();
        game.castSight(g, from);
        g.sim.rng = rng;
        harness.use(g, .shoot);
        g.mode.aim.mark = far;
        skills.confirmAim(g);
        rng = g.sim.rng;
        missed += @intFromBool(g.sim.pool.get(2).?.hp == harness.TEST_HP);
        try std.testing.expectEqual(@as(u16, 2), g.pic.shot.?.flight.struck.?.body);
        try std.testing.expectEqual(harness.TEST_HP, g.sim.pool.get(3).?.hp);
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
