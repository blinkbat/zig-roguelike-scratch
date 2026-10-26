const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const gas = @import("../map/gas.zig");
const actor = @import("../play/actor.zig");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const flask = @import("../play/flask.zig");
const Simulation = @import("sim.zig").Simulation;
const P = mathx.P;

const FOE_DROPS = actor.MAX;

comptime {
    std.debug.assert(items.GROUND_MAX > FOE_DROPS);
}

pub const Frightened = std.StaticBitSet(actor.MAX);
pub const Death = struct { gold: i32, frightened: Frightened };
pub const Chest = enum { opened, not_closed, ground_full };

pub fn groundRoom(sim: *Simulation) bool {
    if (sim.ground.room(FOE_DROPS)) return true;
    sim.log.say("Ground full: collect an item first.", .{});
    return false;
}

pub fn dropItem(sim: *Simulation, drop: items.Drop) void {
    const added = sim.ground.add(drop);
    std.debug.assert(added);
}

fn dropGold(sim: *Simulation, at: P, amount: i32) void {
    const added = sim.ground.gold(at, amount);
    std.debug.assert(added);
}

fn rollGold(sim: *Simulation, at: P, range: items.Gold) i32 {
    const gold = range.roll(&sim.loot_rng);
    dropGold(sim, at, gold);
    return gold;
}

pub fn barrelGold(sim: *Simulation, at: P) ?i32 {
    if (!sim.lv.breakBarrel(at)) return null;
    return rollGold(sim, at, items.BARREL_GOLD);
}

pub fn openChest(sim: *Simulation, at: P) Chest {
    const opened = sim.lv.at(at).opened() orelse return .not_closed;
    if (!groundRoom(sim)) return .ground_full;
    sim.lv.set(at, opened);
    dropItem(sim, .{ .item = items.roll(&sim.loot_rng, sim.heroAttrs().item_rarity), .at = at });
    sim.log.push(.loot, "{s} opens the chest: {d} gold and an item.", .{ sim.name.text(), rollGold(sim, at, items.CHEST_GOLD) });
    sim.chronicle.mark(.chest);
    return .opened;
}

pub fn collectGold(sim: *Simulation, at: P) ?items.Coins {
    const coins = sim.ground.collect(at);
    if (coins == 0) return null;
    const amount = sim.heroAttrs().collectedGold(coins, &sim.loot_rng);
    sim.gold +|= amount;
    sim.log.push(.loot, "{s} picks up {d} gold.", .{ sim.name.text(), amount });
    sim.unsaved = true;
    return .{ .at = at, .amount = coins };
}

pub fn noticeItems(sim: *Simulation, at: P) void {
    var name: [items.NAME_MAX]u8 = undefined;
    for (sim.ground.drops[0..sim.ground.n]) |drop| {
        if (drop.at.eq(at)) sim.log.push(.loot, "{s} steps over {s}.", .{ sim.name.text(), drop.item.name(&name) });
    }
}

pub fn defeat(sim: *Simulation, target: actor.ActorId) Death {
    const fallen = sim.pool.items[target.slot().index];
    sim.kills += 1;
    gainExperience(sim, fallen.kind);
    const reward = items.foeLoot(&sim.loot_rng, sim.heroAttrs().item_rarity);
    if (reward.gold > 0) dropGold(sim, fallen.at, reward.gold);
    if (reward.item) |item| dropItem(sim, .{ .item = item, .at = fallen.at, .source = target.value });
    for (&sim.flasks.values) |*flask_| flask_.fill(flask.PER_KILL);
    if (fallen.kind.bursts()) {
        sim.lv.addGas(fallen.at, gas.BURST);
        sim.sayAt(fallen.at, "The {s} bursts, leaving a cloud of " ++ gas.NAME ++ "!", .{actor.row(fallen.kind).name});
    }
    const family = fallen.kind.family();
    if (sim.pool.tally(family).left == 0) {
        sim.log.say("The last {s} is dead.", .{actor.row(family).name});
        sim.chronicle.mark(.{ .cleared = family });
    }
    return .{ .gold = reward.gold, .frightened = scare(sim, fallen.at) };
}

fn gainExperience(sim: *Simulation, kind: actor.Kind) void {
    const xp = progress.xpOf(kind);
    const before = sim.growth;
    const levels = sim.growth.gain(xp);
    sim.log.push(.progress, "{s} gains {d} experience.", .{ sim.name.text(), xp });
    if (levels == 0) return;
    sim.chronicle.mark(.level);
    sim.log.push(.progress, "Level {d}: +{d} passive, +{d} active points.", .{
        sim.growth.level,
        sim.growth.passive_points - before.passive_points,
        sim.growth.active_points - before.active_points,
    });
}

pub fn scare(sim: *Simulation, at: P) Frightened {
    var frightened = Frightened.initEmpty();
    for (sim.pool.slice(), 0..) |*foe, slot| {
        const row = actor.row(foe.kind);
        if (!foe.alive or !row.flees) continue;
        if (mathx.dist(foe.at, at) > actor.FRIGHT_REACH or !grid.clearLine(&sim.lv, foe.at, at)) continue;
        const was_frightened = foe.fright > 0;
        foe.fright = actor.FLEE_TURNS;
        foe.awake = true;
        if (was_frightened) continue;
        sim.sayAt(foe.at, "The {s} flees in terror!", .{row.name});
        frightened.set(slot);
    }
    return frightened;
}

test "death rewards resolve without presentation and return only newly frightened witnesses" {
    const game = @import("../game.zig");
    const harness = @import("harness.zig");
    const run = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, run);
    harness.arena(run, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 23, .y = 20 };
    const fallen = actor.ActorId.fromInt(harness.spawnAt(run, .bloat, at, true));
    const witness = actor.ActorId.fromInt(harness.spawnAt(run, .pib, .{ .x = 24, .y = 20 }, false));
    game.settle(run);
    const pictured = run.pic.pictured[fallen.slot().index];
    const rng = run.sim.rng;
    var loot_rng = run.sim.loot_rng;
    const expected = items.foeLoot(&loot_rng, run.sim.heroAttrs().item_rarity);
    const hp = run.sim.pool.get(fallen.value).?.hp;
    try std.testing.expect(run.sim.resolveDamage(fallen, hp).lethal);
    const result = defeat(&run.sim, fallen);
    try std.testing.expectEqual(@as(usize, 1), run.sim.kills);
    try std.testing.expectEqual(expected.gold, result.gold);
    try std.testing.expectEqualDeep(loot_rng, run.sim.loot_rng);
    try std.testing.expectEqualDeep(rng, run.sim.rng);
    try std.testing.expect(run.sim.lv.gassy(at));
    try std.testing.expectEqual(@as(usize, 1), result.frightened.count());
    try std.testing.expect(result.frightened.isSet(witness.slot().index));
    try std.testing.expectEqualDeep(pictured, run.pic.pictured[fallen.slot().index]);
    try std.testing.expectEqual(@as(i32, 0), run.pic.dropped_gold[fallen.slot().index]);
    try std.testing.expect(!run.pic.owed[witness.slot().index].any());
    const pib = run.sim.pool.get(witness.value).?;
    pib.fright = 1;
    try std.testing.expectEqual(@as(usize, 0), scare(&run.sim, at).count());
    try std.testing.expectEqual(actor.FLEE_TURNS, pib.fright);
    run.pic.recordDeath(fallen, result);
    try std.testing.expectEqual(expected.gold, run.pic.dropped_gold[fallen.slot().index]);
    std.debug.print("death rewards: seeded loot, gas, refreshed fright and unchanged combat RNG/picture; presentation consumes the result separately\n", .{});
}
