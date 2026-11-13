const std = @import("std");
const attrs = @import("attrs.zig");
const mathx = @import("../core/mathx.zig");
const consumable = @import("consumable.zig");
const affixes = @import("affixes.zig");
const item_bases = @import("item_bases.zig");
const items = @import("items.zig");
const Gear = @import("gear.zig").Gear;
const inventory = @import("inventory.zig");
const ground_items = @import("ground_items.zig");

pub const BASES = blk: {
    var ks: []const item_bases.Kind = &.{};
    for (std.enums.values(item_bases.Kind)) |k| {
        if (k.flaskOf() == null and k.equippable()) ks = ks ++ &[_]item_bases.Kind{k};
    }
    break :blk ks[0..ks.len].*;
};

pub const DROP_PERCENT = 10;
pub const FOE_GOLD_PERCENT = 50;
pub const MAGIC_PERCENT = 20;
pub const RARE_PERCENT = 5;
pub const FOE_SUPPLY_PERCENT = 8;
pub const CHEST_SUPPLY_PERCENT = 50;

/// A gold drop's range, both ends inclusive.
pub const Gold = struct {
    lo: i32,
    hi: i32,

    pub fn roll(g: Gold, rng: *mathx.Rng) i32 {
        return rng.range(g.lo, g.hi);
    }
};
pub const BARREL_GOLD = Gold{ .lo = 3, .hi = 12 };
pub const BARREL_ITEM_PERCENT = 15;
pub const CHEST_GOLD = Gold{ .lo = 18, .hi = 36 };
pub const FOE_GOLD = Gold{ .lo = 1, .hi = 6 };

pub fn qualityChance(base: u32, item_rarity: i32) u32 {
    return @intCast(std.math.clamp(@divTrunc(@as(i64, base) * (mathx.PERCENT + @as(i64, item_rarity)), mathx.PERCENT), 0, mathx.PERCENT));
}

pub const Loot = struct { gold: i32 = 0, item: ?items.Item = null, supply: ?consumable.Kind = null };

pub fn foeLoot(rng: *mathx.Rng, item_rarity: i32) Loot {
    return .{
        .gold = if (rng.percent(FOE_GOLD_PERCENT)) FOE_GOLD.roll(rng) else 0,
        .item = if (rng.percent(DROP_PERCENT)) items.roll(rng, item_rarity) else null,
        .supply = consumable.roll(rng, FOE_SUPPLY_PERCENT),
    };
}

/// What a chest holds, rolled item, gold, then supply.
pub fn chestLoot(rng: *mathx.Rng, item_rarity: i32) Loot {
    const item = items.roll(rng, item_rarity);
    const gold = CHEST_GOLD.roll(rng);
    return .{ .item = item, .gold = gold, .supply = consumable.roll(rng, CHEST_SUPPLY_PERCENT) };
}

/// A chest's loot, its item rolled and then given up for a rare.
pub fn mimicLoot(rng: *mathx.Rng, item_rarity: i32) Loot {
    var loot = chestLoot(rng, item_rarity);
    loot.item = items.rollRare(rng);
    return loot;
}

/// Its gold, then now and then a white item, rolled only where `room` lets it lie.
pub fn barrelLoot(rng: *mathx.Rng, room: bool) Loot {
    const gold = BARREL_GOLD.roll(rng);
    return .{ .gold = gold, .item = if (rng.percent(BARREL_ITEM_PERCENT) and room) items.unrolled(rng) else null };
}

test "foes now and then drop each kind of consumable, which stacks only as far as its cap" {
    var rng = mathx.Rng.init(0x5A99);
    var seen = std.EnumSet(consumable.Kind).initEmpty();
    var dropped: usize = 0;
    for (0..10000) |_| if (foeLoot(&rng, 0).supply) |k| {
        dropped += 1;
        seen.insert(k);
    };
    try std.testing.expect(dropped >= 650 and dropped <= 950);
    try std.testing.expectEqual(consumable.KINDS.len, seen.count());
    var inv = inventory.Inventory{};
    var ground = ground_items.Ground{};
    for (0..consumable.STACK_MAX) |_| try std.testing.expect(inv.stock(.bandage));
    try std.testing.expect(!inv.stock(.bandage));
    try std.testing.expect(ground.addSupply(.{ .kind = .bandage, .at = .{ .x = 3, .y = 3 } }));
    try std.testing.expect(!ground.takeSupply(0, &inv));
    try std.testing.expectEqual(@as(usize, 1), ground.supply_n);
    try std.testing.expectEqual(@as(usize, 0), inv.n);
}

test "foe loot is mostly gold then plain items with magic and rare affixes" {
    var rng = mathx.Rng.init(0xC157E2);
    const rolls = 10000;
    var gold: usize = 0;
    var plain: usize = 0;
    var magic: usize = 0;
    var rare: usize = 0;
    for (0..rolls) |_| {
        const reward = foeLoot(&rng, 0);
        if (reward.gold > 0) {
            gold += 1;
            try std.testing.expect(reward.gold >= FOE_GOLD.lo and reward.gold <= FOE_GOLD.hi);
        }
        if (reward.item) |it| {
            if (it.magical()) {
                if (it.rarity() == .rare) rare += 1 else magic += 1;
                if (it.mods[1]) |second| try std.testing.expect(second.kind != it.mods[0].?.kind);
            } else {
                plain += 1;
                try std.testing.expectEqual(@as([affixes.AFFIXES_MAX]?affixes.Affix, @splat(null)), it.mods);
            }
        }
    }
    try std.testing.expect(gold >= 4500 and gold <= 5500);
    try std.testing.expect(plain >= 650 and plain <= 950);
    try std.testing.expect(magic >= 125 and magic <= 275);
    try std.testing.expect(rare >= 20 and rare <= 80);
}

test "spoils rarity improves magic and rare quality without increasing item quantity" {
    const samples = 20000;
    for ([_]i32{ 0, 25, 100, 400, 1000, -200 }) |rarity| {
        var rng = mathx.Rng.init(0x5F0115);
        var magic: usize = 0;
        var rare: usize = 0;
        var drops: usize = 0;
        for (0..samples) |_| {
            const reward = foeLoot(&rng, rarity);
            if (reward.item) |it| {
                drops += 1;
                if (it.magical()) magic += 1;
                if (it.rarity() == .rare) rare += 1;
            }
        }
        try std.testing.expect(drops > 1800 and drops < 2200);
        const expected = @as(f64, @floatFromInt(qualityChance(MAGIC_PERCENT + RARE_PERCENT, rarity))) / 100;
        const expected_rare = @as(f64, @floatFromInt(qualityChance(RARE_PERCENT, rarity))) / 100;
        try std.testing.expect(@abs(@as(f64, @floatFromInt(magic)) / @as(f64, @floatFromInt(drops)) - expected) < 0.035);
        try std.testing.expect(@abs(@as(f64, @floatFromInt(rare)) / @as(f64, @floatFromInt(drops)) - expected_rare) < 0.035);
        if (expected == 0) try std.testing.expectEqual(@as(usize, 0), magic);
        if (expected == 1) try std.testing.expectEqual(drops, magic);
    }
    var gear = Gear{};
    gear.slots.set(.chest, .{ .kind = .leather, .mods = .{ .{ .kind = .thorns, .value = 2 }, null, null, null } });
    gear.slots.set(.left_hand, .{ .kind = .shield, .mods = .{ .{ .kind = .thorns, .value = 1 }, null, null, null } });
    gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .spoils, .value = 25 }, null, null, null } });
    gear.slots.set(.amulet, .{ .kind = .amulet, .mods = .{ .{ .kind = .spoils, .value = 15 }, null, null, null } });
    const a = gear.stats(attrs.Attrs.of(.{ .strength = 20, .dexterity = 20, .intelligence = 20 }));
    try std.testing.expectEqual(@as(i32, 3), a.thorns);
    try std.testing.expectEqual(@as(i32, 40), a.gold_find);
    try std.testing.expectEqual(@as(i32, 40), a.item_rarity);
}
