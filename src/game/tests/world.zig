const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const fov = @import("../../map/fov.zig");
const gas = @import("../../map/gas.zig");
const atlas = @import("../../map/atlas.zig");
const actor = @import("../../play/actor.zig");
const bow = @import("../../play/bow.zig");
const glacial = @import("../../play/glacial.zig");
const juke = @import("../../play/juke.zig");
const light = @import("../../gfx/light.zig");
const sky = @import("../../gfx/sky.zig");
const climate = @import("../../map/climate.zig");
const day = @import("../../map/day.zig");
const shots = @import("../shots.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const P = mathx.P;
const HERO = actor.HERO;

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
    harness.use(g, .shoot);
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
    harness.corridor(b);
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
    harness.idle(g);
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
    harness.idle(g);
    try std.testing.expectEqual(room, g.node);
    try std.testing.expectEqual(@as(i32, 17), g.gold);
    try std.testing.expect(std.mem.endsWith(u8, g.log.line(0).?, "picks up 17 gold."));
    try std.testing.expect(std.mem.startsWith(u8, g.log.line(1).?, "Entered "));
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
    const b = harness.twoRooms(w);
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
