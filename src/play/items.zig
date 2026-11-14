const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const mathx = @import("../core/mathx.zig");
const passives = @import("passives.zig");
const wording = @import("../core/wording.zig");
const affixes = @import("affixes.zig");
const item_bases = @import("item_bases.zig");
const loot = @import("loot.zig");
const Gear = @import("gear.zig").Gear;
const inventory = @import("inventory.zig");

pub const Rarity = enum { normal, magic, rare };

pub const NAME_MAX = 128;

pub const Item = struct {
    kind: item_bases.Kind,
    mods: [affixes.AFFIXES_MAX]?affixes.Affix = @splat(null),
    rare_name: ?affixes.RareName = null,

    pub fn name(self: Item, buf: []u8) [:0]const u8 {
        return wording.recased(buf, self.composed(buf), .title);
    }

    /// Lower case within a sentence, as the log says it; a rare item's own name keeps its capitals.
    pub fn spoken(self: Item, buf: []u8) [:0]const u8 {
        const text = self.composed(buf);
        return if (self.rare_name != null) text else wording.recased(buf, text, .lower);
    }

    fn composed(self: Item, buf: []u8) [:0]const u8 {
        if (self.rare_name) |rare| return rare.name(buf);
        const base = item_bases.baseOf(self.kind);
        var pre: []const u8 = "";
        var post: []const u8 = "";
        for (self.mods) |maybe| if (maybe) |m| {
            if (m.kind.prefix()) pre = m.kind.title(m.element) else post = m.kind.title(m.element);
        };
        return std.fmt.bufPrintZ(buf, "{s}{s}{s}{s}{s}", .{ pre, if (pre.len > 0) " " else "", base, if (post.len > 0) " " else "", post }) catch base;
    }

    pub fn fits(self: Item, slot: item_bases.Slot) bool {
        return self.kind.fits(slot);
    }

    pub fn magical(self: Item) bool {
        return self.mods[0] != null;
    }

    pub fn rarity(self: Item) Rarity {
        return if (self.rare_name != null) .rare else if (self.magical()) .magic else .normal;
    }

    fn allows(self: Item, kind: affixes.Mod) bool {
        if (!kind.allows(self.kind)) return false;
        var same_side: usize = 0;
        for (self.mods) |maybe| if (maybe) |m| {
            if (m.kind == kind) return false;
            if (m.kind.prefix() == kind.prefix()) same_side += 1;
        };
        return same_side < @as(usize, if (self.rarity() == .rare) affixes.RARE_SIDE else affixes.MAGIC_SIDE);
    }

    fn allowsRoll(self: Item, a: affixes.AffixRoll) bool {
        return self.allows(a.kind);
    }

    /// A loaded item's modifiers, kept within what their rolls give.
    pub fn mend(self: *Item) void {
        for (&self.mods) |*maybe| if (maybe.*) |*m| {
            const a = affixes.affixOf(m.kind);
            m.value = std.math.clamp(m.value, @as(i16, @intCast(a.lo)), @as(i16, @intCast(a.hi)));
        };
    }

    pub fn value(self: Item, kind: affixes.Mod) i32 {
        var n: i32 = 0;
        for (self.mods) |maybe| if (maybe) |m| {
            if (m.kind == kind) n += m.value;
        };
        return n;
    }

    pub fn apply(self: Item, a: *attrs.Attrs) void {
        const base = item_bases.spec(self.kind);
        a.armour += base.armour;
        a.block += base.block;
        if (base.innate) |innate| innate.apply(a);
        for (self.mods) |maybe| if (maybe) |m| switch (m.kind) {
            .physical_damage => a.physical_bonus += m.value,
            .crit_damage => a.crit_damage += m.value,
            .block => a.block += m.value,
            .resistance => a.resists.getPtr(m.element).* += m.value,
            .thorns => a.thorns += m.value,
            .spoils => {
                a.gold_find += m.value;
                a.item_rarity += m.value;
            },
            .penetration, .imbue, .resolve, .lantern, .mana_on_kill, .mana_flask, .masked, .stillness, .opportunist, .bounding, .alacrity, .life_regen, .leech, .area, .pierce, .haste => {},
            inline else => |k| {
                if (comptime !k.granted()) @compileError("Item.apply: say where " ++ @tagName(k) ++ " takes effect");
                k.grant(m.value).apply(a);
            },
        };
    }

    pub fn perk(self: Item, p: *passives.Perks) void {
        if (item_bases.spec(self.kind).innate) |innate| if (innate == .grant) innate.grant.perk(p);
        for (self.mods) |maybe| if (maybe) |m| switch (m.kind) {
            inline else => |k| if (comptime k.granted()) k.grant(m.value).perk(p),
        };
    }

    pub fn meets(self: Item, a: attrs.Attrs) bool {
        return a.meets(item_bases.spec(self.kind).needs);
    }
};

pub const SMALL_KEY = Item{ .kind = .small_key };

pub fn baseName(k: item_bases.Kind, buf: []u8) [:0]const u8 {
    return (Item{ .kind = k }).name(buf);
}

pub fn unrolled(rng: *mathx.Rng) Item {
    return .{ .kind = rng.pick(item_bases.Kind, &loot.BASES) };
}

pub fn roll(rng: *mathx.Rng, item_rarity: i32) Item {
    var out = unrolled(rng);
    const quality = rng.below(mathx.PERCENT);
    if (quality >= loot.qualityChance(loot.MAGIC_PERCENT + loot.RARE_PERCENT, item_rarity)) return out;
    affix(&out, rng, quality < loot.qualityChance(loot.RARE_PERCENT, item_rarity));
    return out;
}

pub fn rollRare(rng: *mathx.Rng) Item {
    var out = unrolled(rng);
    affix(&out, rng, true);
    return out;
}

fn affix(out: *Item, rng: *mathx.Rng, rare: bool) void {
    if (rare) out.rare_name = affixes.RareName.roll(rng);
    const count = if (rare) rng.range(affixes.RARE_LEAST, affixes.AFFIXES_MAX) else rng.range(1, affixes.MAGIC_MOST);
    for (0..@intCast(count)) |i| {
        const a = rng.pickWhere(affixes.AffixRoll, &affixes.AFFIXES, out.*, Item.allowsRoll).?;
        const from = a.kind.elements();
        out.mods[i] = .{ .kind = a.kind, .value = @intCast(rng.range(a.lo, a.hi)), .element = if (from.len > 0) rng.pick(damage.Element, from) else .fire };
    }
}

test "rare items roll distinct legal affixes and persistent combinatorial names" {
    var rng = mathx.Rng.init(0x2A2E);
    var counts = std.EnumArray(Rarity, usize).initFill(0);
    var bases = std.EnumSet(item_bases.Kind).initEmpty();
    var firsts = std.EnumSet(affixes.RareName.First).initEmpty();
    var lasts = std.EnumSet(affixes.RareName.Last).initEmpty();
    var sizes: [affixes.AFFIXES_MAX - affixes.RARE_LEAST + 1]usize = @splat(0);
    for (0..100000) |_| {
        const it = roll(&rng, 0);
        counts.getPtr(it.rarity()).* += 1;
        if (it.rarity() != .rare) continue;
        bases.insert(it.kind);
        firsts.insert(it.rare_name.?.first);
        lasts.insert(it.rare_name.?.last);
        var seen = std.EnumSet(affixes.Mod).initEmpty();
        var sides = [_]usize{ 0, 0 };
        for (it.mods) |maybe| if (maybe) |m| {
            try std.testing.expect(m.kind.allows(it.kind));
            try std.testing.expect(!seen.contains(m.kind));
            seen.insert(m.kind);
            sides[@intFromBool(m.kind.prefix())] += 1;
            try std.testing.expect(m.value >= affixes.affixOf(m.kind).lo and m.value <= affixes.affixOf(m.kind).hi);
        };
        try std.testing.expect(seen.count() >= affixes.RARE_LEAST and seen.count() <= affixes.AFFIXES_MAX);
        try std.testing.expect(sides[0] <= affixes.RARE_SIDE and sides[1] <= affixes.RARE_SIDE);
        sizes[seen.count() - affixes.RARE_LEAST] += 1;
    }
    try std.testing.expect(counts.get(.normal) > 74000 and counts.get(.normal) < 76000);
    try std.testing.expect(counts.get(.magic) > 19000 and counts.get(.magic) < 21000);
    try std.testing.expect(counts.get(.rare) > 4500 and counts.get(.rare) < 5500);
    try std.testing.expectEqual(loot.BASES.len, bases.count());
    try std.testing.expectEqual(std.enums.values(affixes.RareName.First).len, firsts.count());
    try std.testing.expectEqual(std.enums.values(affixes.RareName.Last).len, lasts.count());
    try std.testing.expect(sizes[0] > 0 and sizes[1] > 0);
    var name: [NAME_MAX]u8 = undefined;
    for ([_]affixes.RareName{ .{ .first = .Spine, .last = .Crusher }, .{ .first = .Void, .last = .Maw }, .{ .first = .Magus, .last = .Fold } }, [_][]const u8{ "Spine Crusher", "Void Maw", "Magus Fold" }) |rare, expected| {
        try std.testing.expectEqualStrings(expected, (Item{ .kind = .axe, .rare_name = rare }).name(&name));
    }
    const rare = Item{ .kind = .mace, .rare_name = .{ .first = .Spine, .last = .Crusher }, .mods = .{ .{ .kind = .strength, .value = 3 }, .{ .kind = .crit, .value = 5 }, .{ .kind = .physical_damage, .value = 20 }, .{ .kind = .life_on_kill, .value = 2 } } };
    var gear = Gear{};
    gear.slots.set(.right_hand, rare);
    const base = attrs.Attrs.of(.{ .strength = 20, .dexterity = 20, .intelligence = 20 });
    const stats = gear.stats(base);
    try std.testing.expectEqual(base.get(.strength) + 3, stats.get(.strength));
    try std.testing.expectEqual(@as(i32, 20), stats.physical_bonus);
    try std.testing.expectEqual(base.crit() + 5, stats.crit());
    try std.testing.expectEqual(@as(i32, 2), gear.killRecovery());
    var inv = inventory.Inventory{};
    try std.testing.expect(inv.add(rare));
    try inv.equip(0, .right_hand, base);
    try std.testing.expectEqualDeep(rare, inv.gear.slots.get(.right_hand).?);
    try inv.unequip(.right_hand, base);
    try std.testing.expectEqualDeep(rare, inv.bag[0]);
}

test "every equipment base rolls all three rarities and keeps its innate separate from affixes" {
    var rng = mathx.Rng.init(0xBA5E);
    var white = std.EnumSet(item_bases.Kind).initEmpty();
    var blue = std.EnumSet(item_bases.Kind).initEmpty();
    var yellow = std.EnumSet(item_bases.Kind).initEmpty();
    for (0..20000) |_| {
        const it = roll(&rng, 0);
        switch (it.rarity()) {
            .normal => white.insert(it.kind),
            .magic => blue.insert(it.kind),
            .rare => yellow.insert(it.kind),
        }
    }
    try std.testing.expectEqual(loot.BASES.len, white.count());
    try std.testing.expectEqual(loot.BASES.len, blue.count());
    try std.testing.expectEqual(loot.BASES.len, yellow.count());
    const base = attrs.Attrs.of(.{ .strength = 30, .dexterity = 30, .intelligence = 30 });
    for (loot.BASES) |kind| {
        var plain = base;
        var magic = base;
        const it = Item{ .kind = kind };
        it.apply(&plain);
        (Item{ .kind = kind, .mods = .{ .{ .kind = .mana, .value = 2 }, null, null, null } }).apply(&magic);
        try std.testing.expectEqual(@as(i32, 0), it.value(.mana));
        plain.mana_bonus += 2;
        try std.testing.expectEqualDeep(plain, magic);
    }
    var gear = Gear{};
    gear.slots.set(.right_hand, .{ .kind = .dagger });
    const dagger = gear.stats(base);
    try std.testing.expect(gear.forAttack(dagger, .melee).crit() > base.crit());
    try std.testing.expectEqual(base.crit(), gear.forAttack(dagger, .spell).crit());
    gear.slots.set(.right_hand, .{ .kind = .wand });
    gear.slots.set(.left_hand, .{ .kind = .orb });
    const caster = gear.stats(base);
    try std.testing.expectEqual(base.crit() + 14, gear.forAttack(caster, .spell).crit());
    try std.testing.expectEqual(base.crit(), gear.forAttack(caster, .melee).crit());
    gear.slots.set(.helm, .{ .kind = .circlet });
    gear.slots.set(.belt, .{ .kind = .flask_belt });
    gear.slots.set(.left_hand, .{ .kind = .totem });
    try std.testing.expectEqualDeep(passives.Perks{ .mana_regen = 1, .life_flask = 20, .life_on_kill = 1 }, gear.perks(.{}));
}
