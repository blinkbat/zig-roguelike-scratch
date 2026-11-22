const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const tactics = @import("../play/tactics.zig");
const windup = @import("../play/windup.zig");
const firebolt = @import("../play/firebolt.zig");
const Simulation = @import("sim.zig").Simulation;
const P = mathx.P;

pub const Side = enum { foe, ally };

pub fn orderFoes(sim: *Simulation, from: P) void {
    sim.order_n = 0;
    for (sim.pool.slice(), 0..) |body, slot| {
        const id = actor.Pool.idOf(slot);
        if (id == sim.hero or !body.alive or body.waits) continue;
        _ = mathx.push(u16, &sim.order, &sim.order_n, id);
    }
    const Near = struct {
        pool: *const actor.Pool,
        from: P,
        fn nearer(context: @This(), first: u16, second: u16) bool {
            const first_slot = actor.Pool.slot(first);
            const second_slot = actor.Pool.slot(second);
            const first_distance = mathx.dist(context.pool.items[first_slot].at, context.from);
            const second_distance = mathx.dist(context.pool.items[second_slot].at, context.from);
            return first_distance < second_distance or (first_distance == second_distance and first < second);
        }
    };
    std.mem.sort(u16, sim.order[0..sim.order_n], Near{ .pool = &sim.pool, .from = from }, Near.nearer);
}

pub fn besideOf(sim: *const Simulation, at: P, side: Side) ?u16 {
    var best: ?u16 = null;
    for (mathx.ALL_DIRS) |direction| {
        if (!sim.lv.passOk(at, direction)) continue;
        const id = sim.lv.who(at.add(direction.delta()));
        const candidate = sim.pool.getConst(id) orelse continue;
        const fits = switch (side) {
            .foe => candidate.foe(),
            .ally => candidate.kind.ally(),
        };
        if (!fits or candidate.veiled()) continue;
        if (best) |previous| if (sim.pool.items[actor.Pool.slot(previous)].hp <= candidate.hp) continue;
        best = id;
    }
    return best;
}

pub fn quarry(sim: *const Simulation, from: P, hero: P, sight: i32) ?P {
    var nearest = grid.Nearest{ .from = from };
    for (sim.pool.constSlice()) |candidate| {
        if (!candidate.seenFoe(&sim.lv) or mathx.dist(candidate.at, hero) > tactics.RaiseSkeleton.LEASH) continue;
        if (!fov.sees(&sim.lv, from, candidate.at, sight)) continue;
        nearest.offer(candidate.at);
    }
    return nearest.best;
}

pub fn flowTo(sim: *Simulation, hero: P) *const [grid.CELLS]i32 {
    if (!sim.flowed) {
        _ = grid.distances(&sim.lv, hero, &sim.flow, &sim.queue);
        sim.flowed = true;
    }
    return &sim.flow;
}

pub fn besideWay(sim: *const Simulation, at: P, hero: P) ?mathx.Dir {
    const d = mathx.dirTo(at, hero) orelse return null;
    return if (sim.lv.passOk(at, d)) d else null;
}

pub fn braceTarget(sim: *const Simulation, id: u16, range: i32, sight: i32) ?P {
    const foe = sim.pool.getConst(id).?;
    const hero = sim.heroAt().?;
    const gap = mathx.dist(foe.at, hero);
    if (foe.ready_in > 0 or gap < windup.NEAREST or gap > range or !fov.sees(&sim.lv, foe.at, hero, sight)) return null;
    return hero;
}

fn kinInReach(lv: *const grid.Level, healing: actor.Mend, candidate: *const actor.Actor, from: P, within: i32) bool {
    if (!candidate.alive or std.mem.indexOfScalar(actor.Kind, healing.kin, candidate.kind) == null) return false;
    return mathx.dist(candidate.at, from) <= within and grid.clearLine(lv, from, candidate.at);
}

pub const Mended = struct { slot: ?actor.ActorSlot };

pub fn mend(sim: *Simulation, id: u16, healing: actor.Mend, sight: i32) ?Mended {
    const healer = sim.pool.get(id).?;
    if (healer.ready_in > 0) return null;
    const within = @min(healing.reach, sight);
    var most_hurt: ?usize = null;
    var has_sleepers = false;
    for (sim.pool.slice(), 0..) |*candidate, slot| {
        if (!kinInReach(&sim.lv, healing, candidate, healer.at, within)) continue;
        has_sleepers = has_sleepers or !candidate.awake;
        if (!candidate.hurt()) continue;
        if (most_hurt) |previous| {
            const worst = &sim.pool.items[previous];
            if (@as(i64, candidate.hp) * worst.max >= @as(i64, worst.hp) * candidate.max) continue;
        }
        most_hurt = slot;
    }
    const name = actor.row(healer.kind).name;
    if (most_hurt) |slot| {
        const candidate = &sim.pool.items[slot];
        _ = candidate.heal(healing.amount);
        sim.sayAt(healer.at, "The {s} mends the {s}.", .{ name, actor.row(candidate.kind).name });
    } else if (has_sleepers) {
        for (sim.pool.slice()) |*candidate| {
            if (kinInReach(&sim.lv, healing, candidate, healer.at, within)) candidate.awake = true;
        }
        sim.sayAt(healer.at, "The {s} rouses its kin.", .{name});
    } else return null;
    healer.ready_in = healing.every;
    return .{ .slot = if (most_hurt) |slot| .fromIndex(slot) else null };
}

pub const NetThrow = struct { flight: bow.Flight, facing_delta: i32, landed: bool };

/// Another living foe on or beside the cells `bolt` crosses before it reaches the hero.
pub fn crowded(sim: *const Simulation, id: u16, bolt: firebolt.Bolt, hero: P, range: i32) bool {
    var ray = grid.Ray.init(bolt.from, bolt.toward);
    for (0..@intCast(range)) |_| {
        const c = ray.next() orelse return false;
        if (c.eq(hero)) return false;
        var near = (grid.Box.around(c, 1).clipped() orelse continue).cells();
        while (near.next()) |q| {
            const w = sim.lv.who(q);
            if (w == id) continue;
            if (sim.pool.getConst(w)) |a| if (a.foe()) return true;
        }
    }
    return false;
}

/// Kept off the hero, yet within `reach` of it.
fn inBand(at: P, hero: P, keeps: i32, reach: i32) bool {
    const gap = mathx.dist(at, hero);
    return gap > keeps and gap <= reach;
}

/// Where a netter too close to the hero darts, its quickstep spent and said; none while held, confused or recovering.
pub fn quickstep(sim: *Simulation, id: u16, af: actor.Afflicted) ?P {
    const body = sim.pool.get(id) orelse return null;
    const row = actor.row(body.kind);
    const q = row.quickstep orelse return null;
    const hero = sim.heroAt() orelse return null;
    if (af.contains(.confusion) or body.quickstep_in > 0 or body.pin.holding() or mathx.dist(body.at, hero) > row.keeps) return null;
    var choices: [mathx.ALL_DIRS.len]P = undefined;
    var count: usize = 0;
    for (mathx.ALL_DIRS) |direction| {
        var to = body.at;
        for (0..@intCast(q.cells)) |_| {
            if (!sim.lv.stepOk(to, direction, id) or actor.shuns(&sim.lv, to, direction)) break;
            to = to.add(direction.delta());
        } else {
            if (inBand(to, hero, row.keeps, row.net.?.range)) _ = mathx.push(P, &choices, &count, to);
        }
    }
    if (count == 0) return null;
    body.quickstep_in = q.every;
    sim.sayAt(body.at, "The {s} quicksteps away.", .{row.name});
    return choices[@intCast(sim.rng.range(0, @intCast(count - 1)))];
}

pub fn throwNet(sim: *Simulation, id: u16, net: actor.Net) ?NetThrow {
    const thrower = sim.pool.get(id).?;
    const hero = sim.heroActor().?;
    if (thrower.ready_in > 0 or hero.pin.holding()) return null;
    const flight = bow.clearShot(&sim.lv, thrower.at, hero.at, net.range, sim.hero) orelse return null;
    thrower.ready_in = net.every;
    const name = actor.row(thrower.kind).name;
    const facing_delta = hero.at.x - thrower.at.x;
    if (sim.combatStats(thrower).misses(sim.combatStats(hero), &sim.rng)) {
        sim.log.say("{s} dodges the {s}'s net.", .{ sim.name.text(), name });
        return .{ .flight = flight, .facing_delta = facing_delta, .landed = false };
    }
    if (sim.pinFor(hero, net.pins)) {
        sim.log.push(.danger, "The {s} nets {s}!", .{ name, sim.name.text() });
    } else sim.log.say("{s} shrugs off the {s}'s net.", .{ sim.name.text(), name });
    return .{ .flight = flight, .facing_delta = facing_delta, .landed = true };
}

pub fn repositionStep(sim: *Simulation, id: u16, hurl: actor.Hurl) ?mathx.Dir {
    const body = sim.pool.get(id).?;
    const Spot = struct {
        level: *const grid.Level,
        from: P,
        id: u16,
        hero: P,
        hero_id: u16,
        keeps: i32,
        range: i32,

        fn ok(spot: @This(), direction: mathx.Dir) bool {
            if (!spot.level.stepOk(spot.from, direction, spot.id) or actor.shuns(spot.level, spot.from, direction)) return false;
            const to = spot.from.add(direction.delta());
            return inBand(to, spot.hero, spot.keeps, spot.range) and bow.clearShot(spot.level, to, spot.hero, spot.range, spot.hero_id) != null;
        }
    };
    const spot = Spot{
        .level = &sim.lv,
        .from = body.at,
        .id = id,
        .hero = sim.heroAt().?,
        .hero_id = sim.hero,
        .keeps = actor.row(body.kind).keeps,
        .range = hurl.range,
    };
    sim.lv.clear(spot.from);
    defer sim.lv.stand(spot.from, id);
    return sim.rng.pickWhere(mathx.Dir, mathx.ALL_DIRS, spot, Spot.ok);
}

test "quickstep cannot cross blocked terrain or move a held netter" {
    const game = @import("../game.zig");
    const harness = @import("harness.zig");
    const run = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, run);
    const from = P{ .x = 22, .y = 20 };
    harness.arena(run, .{ .x = 20, .y = 20 }, &.{});
    const id = harness.spawnAt(run, .bandit_netter, from, true);
    const none = actor.Afflicted.initEmpty();
    const to = quickstep(&run.sim, id, none).?;
    try std.testing.expectEqual(actor.row(.bandit_netter).quickstep.?.cells, mathx.dist(from, to));
    try std.testing.expect(mathx.dist(to, run.sim.heroAt().?) > actor.row(.bandit_netter).keeps);
    const body = run.sim.pool.get(id).?;
    body.quickstep_in = 0;
    body.pin.extend(2);
    try std.testing.expect(quickstep(&run.sim, id, none) == null);
    body.pin.turns = 0;
    try std.testing.expect(quickstep(&run.sim, id, .initOne(.confusion)) == null);
    body.quickstep_in = 1;
    try std.testing.expect(quickstep(&run.sim, id, none) == null);
    body.quickstep_in = 0;
    harness.hemIn(&run.sim.lv, from, null);
    const rng = run.sim.rng;
    try std.testing.expect(quickstep(&run.sim, id, none) == null);
    try std.testing.expectEqualDeep(rng, run.sim.rng);
    try std.testing.expectEqual(@as(u8, 0), body.quickstep_in);
}

test "net rules resolve dodges and hits without scheduling the picture" {
    const game = @import("../game.zig");
    const harness = @import("harness.zig");
    const run = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, run);
    for ([_]bool{ false, true }) |lands| {
        harness.arena(run, .{ .x = 20, .y = 20 }, &.{});
        const id = harness.spawnAt(run, .bandit_netter, .{ .x = 24, .y = 20 }, true);
        game.settle(run);
        const net = actor.row(.bandit_netter).net.?;
        const before = run.pic.pictured[run.sim.heroSlot().?];
        run.sim.rng = harness.foeAttacksRng(run, &.{.{ .id = id, .lands = lands }});
        const result = throwNet(&run.sim, id, net).?;
        try std.testing.expectEqual(lands, result.landed);
        try std.testing.expectEqual(net.every, run.sim.pool.get(id).?.ready_in);
        try std.testing.expectEqualDeep(before, run.pic.pictured[run.sim.heroSlot().?]);
        try std.testing.expect(!run.pic.owed[actor.Pool.slot(id)].any());
        const rng = run.sim.rng;
        try std.testing.expect(throwNet(&run.sim, id, net) == null);
        try std.testing.expectEqualDeep(rng, run.sim.rng);
    }
}

test "mending returns the most injured kin while leaving its picture unchanged" {
    const game = @import("../game.zig");
    const harness = @import("harness.zig");
    const run = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, run);
    harness.arena(run, .{ .x = 20, .y = 20 }, &.{});
    const healer = harness.spawnAt(run, .pib_shaman, .{ .x = 24, .y = 20 }, true);
    const injured = harness.spawnAt(run, .pib, .{ .x = 24, .y = 21 }, true);
    run.sim.pool.get(injured).?.hp = 1;
    game.settle(run);
    const slot = actor.ActorId.fromInt(injured).slot();
    const before = run.pic.pictured[slot.index];
    const healing = actor.row(.pib_shaman).mends.?;
    const result = mend(&run.sim, healer, healing, 10).?;
    try std.testing.expectEqual(slot, result.slot.?);
    try std.testing.expect(run.sim.pool.get(injured).?.hp > 1);
    try std.testing.expectEqualDeep(before, run.pic.pictured[slot.index]);
    try std.testing.expect(!run.pic.owed[actor.Pool.slot(healer)].any());
    try std.testing.expectEqual(healing.every, run.sim.pool.get(healer).?.ready_in);
    try std.testing.expect(mend(&run.sim, healer, healing, 10) == null);
}
