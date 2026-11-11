const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const mathx = @import("../core/mathx.zig");
const passives = @import("passives.zig");
const flask = @import("flask.zig");
const affixes = @import("affixes.zig");
const item_bases = @import("item_bases.zig");
const items = @import("items.zig");
const loot = @import("loot.zig");
const inventory = @import("inventory.zig");

pub const Gear = struct {
    slots: std.EnumArray(item_bases.Slot, ?items.Item) = .initFill(null),

    pub const flasks: Gear = blk: {
        var out = Gear{};
        out.wearFlasks();
        break :blk out;
    };

    pub fn wearFlasks(self: *Gear) void {
        for (std.enums.values(flask.Kind)) |k| self.slots.set(.ofFlask(k), .{ .kind = .ofFlask(k) });
    }

    pub fn holds(self: Gear, k: flask.Kind) bool {
        return self.slots.get(.ofFlask(k)) != null;
    }

    pub fn stats(self: Gear, base: attrs.Attrs) attrs.Attrs {
        var out = base;
        for (self.slots.values) |maybe| if (maybe) |it| it.apply(&out);
        return out;
    }

    pub fn perks(self: Gear, base: passives.Perks) passives.Perks {
        var out = base;
        for (self.slots.values) |maybe| if (maybe) |it| it.perk(&out);
        return out;
    }

    pub fn forAttack(self: Gear, base: attrs.Attrs, attack: attrs.Attack) attrs.Attrs {
        var out = base;
        if (self.weapon(attack) == null) out.physical_bonus -= self.sum(.physical_damage);
        out.crit_bonus += if (attack == .spell) base.spell_crit_bonus else if (self.weapon(attack) != null) base.weapon_crit_bonus else 0;
        return out;
    }

    /// Life its worn items heal for a kill, innate grants and rolled modifiers alike; passives' heal blows only.
    pub fn killRecovery(self: Gear) i32 {
        return self.perks(.{}).life_on_kill;
    }

    pub fn manaOnKill(self: Gear) i32 {
        return @max(0, self.sum(.mana_on_kill));
    }

    pub fn sum(self: Gear, kind: affixes.Mod) i32 {
        var n: i32 = 0;
        for (self.slots.values) |maybe| if (maybe) |it| {
            n += it.value(kind);
        };
        return n;
    }

    /// Turns Alacrity takes off every cooldown.
    pub fn quicker(self: Gear) u8 {
        return std.math.lossyCast(u8, @max(0, self.sum(.alacrity)));
    }

    /// Cells Bounding adds to every movement skill's reach.
    pub fn bounding(self: Gear) i32 {
        return @max(0, self.sum(.bounding));
    }

    pub fn lifeRegen(self: Gear) i32 {
        return @max(0, self.sum(.life_regen));
    }

    pub fn leech(self: Gear) i32 {
        return @max(0, self.sum(.leech));
    }

    /// Cells added to every area skill's radius.
    pub fn wider(self: Gear) i32 {
        return @max(0, self.sum(.area));
    }

    /// Foes a single-target projectile passes through before the one that stops it.
    pub fn pierce(self: Gear) usize {
        return @intCast(@max(0, self.sum(.pierce)));
    }

    /// Percent chance an action spends no turn.
    pub fn haste(self: Gear) u32 {
        return @intCast(std.math.clamp(self.sum(.haste), 0, mathx.PERCENT));
    }

    /// Each flask's recovery bonus: life from `held`, which already counts worn grants; mana from worn mods alone.
    pub fn draughts(self: Gear, held: passives.Perks) flask.Bonus {
        return .{ .life = held.life_flask, .mana = self.sum(.mana_flask) };
    }

    pub fn draughtsOver(self: Gear, passive: passives.Perks) flask.Bonus {
        return self.draughts(self.perks(passive));
    }

    pub fn onHit(self: Gear, attack: attrs.Attack) item_bases.WeaponEffect {
        const held = self.wielded(attack) orelse return .{};
        var out = item_bases.WeaponEffect{ .penetration = self.sum(.penetration) };
        for (self.slots.values) |maybe| if (maybe) |it| {
            for (it.mods) |m| if (m) |a| if (a.kind == .imbue) out.imbue(a.element, @intCast(a.value));
        };
        const innate = held.innate orelse return out;
        const fixed: item_bases.WeaponEffect = switch (innate) {
            .bleed => |b| .{ .bleed = b.chance, .bleed_damage = b.damage },
            .stun => |n| .{ .stun = n },
            .penetration => |n| .{ .penetration = n },
            .grant, .weapon_crit, .spell_crit, .physical_damage, .element, .flask => .{},
        };
        out.bleed = fixed.bleed;
        out.bleed_damage = fixed.bleed_damage;
        out.stun = fixed.stun;
        out.penetration += fixed.penetration;
        return out;
    }

    pub fn twoHander(self: Gear) ?items.Item {
        const it = self.slots.get(.right_hand) orelse return null;
        return if (item_bases.spec(it.kind).two_handed) it else null;
    }

    pub fn valid(self: Gear, base: attrs.Attrs) bool {
        return self.validFrom(.{}, base);
    }

    /// A loaded save can wear unmet gear after a retune; only a change that unmeets an item is refused.
    pub fn validFrom(self: Gear, before: Gear, base: attrs.Attrs) bool {
        if (self.twoHander() != null and self.slots.get(.left_hand) != null) return false;
        for (item_bases.SLOTS) |slot| if (self.slots.get(slot)) |it| {
            if (!it.fits(slot) or !self.keepsMet(before, slot, base)) return false;
        };
        return true;
    }

    pub fn keepsMet(self: Gear, before: Gear, slot: item_bases.Slot, base: attrs.Attrs) bool {
        if (self.wornMeets(slot, base)) return true;
        const was = before.slots.get(slot) orelse return false;
        return std.meta.eql(@as(?items.Item, was), self.slots.get(slot)) and !before.wornMeets(slot, base);
    }

    /// `it` worn in `slot`, with the hands it displaces emptied.
    pub fn wearing(self: Gear, it: items.Item, slot: item_bases.Slot) Gear {
        var after = self;
        after.slots.set(slot, it);
        if (item_bases.spec(it.kind).two_handed) after.slots.set(.left_hand, null);
        if (slot == .left_hand and self.twoHander() != null) after.slots.set(.right_hand, null);
        return after;
    }

    pub fn statsWithout(self: Gear, slot: item_bases.Slot, base: attrs.Attrs) attrs.Attrs {
        var without = self;
        without.slots.set(slot, null);
        return without.stats(base);
    }

    /// An item cannot fund its own requirement.
    pub fn wornMeets(self: Gear, slot: item_bases.Slot, base: attrs.Attrs) bool {
        const it = self.slots.get(slot) orelse return true;
        return it.meets(self.statsWithout(slot, base));
    }

    fn wielded(self: Gear, attack: attrs.Attack) ?item_bases.Spec {
        const it = self.slots.get(.right_hand) orelse return null;
        const s = item_bases.spec(it.kind);
        return if (s.attack == attack and s.damage != null) s else null;
    }

    pub fn weapon(self: Gear, attack: attrs.Attack) ?damage.Base {
        return (self.wielded(attack) orelse return null).damage;
    }

    pub fn scaling(self: Gear, attack: attrs.Attack) attrs.Style {
        return if (self.wielded(attack)) |s| s.style else attack.defaultStyle();
    }
};

test "weapon weights cross melee and range while caster implements have no innate attack" {
    const heavy = [_]item_bases.Kind{ .longsword, .mace, .greatsword, .crossbow, .greatclub, .axe };
    const light = [_]item_bases.Kind{ .bow, .sling, .dagger, .sword, .handaxe };
    var gear = Gear{};
    const strong = attrs.Attrs.of(.{ .strength = 60, .dexterity = 10, .intelligence = 20 });
    for (heavy ++ light) |kind| {
        gear.slots.set(.right_hand, .{ .kind = kind });
        const s = item_bases.spec(kind);
        const is_heavy = std.mem.indexOfScalar(item_bases.Kind, &heavy, kind) != null;
        try std.testing.expectEqual(if (is_heavy) attrs.Style.heavy else .light, gear.scaling(s.attack));
        try std.testing.expectEqual(@as(i32, if (is_heavy) 60 else 10), strong.increase(gear.scaling(s.attack)));
        try std.testing.expect(s.damage != null);
        try std.testing.expectEqual(s.damage, gear.weapon(s.attack));
        try std.testing.expect(gear.weapon(if (s.attack == .ranged) .melee else .ranged) == null);
    }
    const implements = [_]item_bases.Kind{ .wand, .staff };
    for (implements) |kind| {
        gear.slots.set(.right_hand, .{ .kind = kind });
        try std.testing.expect(item_bases.spec(kind).damage == null);
        for (std.enums.values(attrs.Attack)) |attack| {
            try std.testing.expect(gear.weapon(attack) == null);
            try std.testing.expectEqual(attack.defaultStyle(), gear.scaling(attack));
        }
    }
    const base = attrs.Attrs.of(.{ .strength = 30, .dexterity = 30, .intelligence = 30 });
    const offhands = [_]item_bases.Kind{ .tome, .orb, .buckler, .shield, .totem };
    for (offhands) |kind| {
        var inv = inventory.Inventory{};
        try std.testing.expect(inv.add(.{ .kind = .wand }));
        try inv.equip(0, .right_hand, base);
        try std.testing.expect(inv.add(.{ .kind = kind }));
        try inv.equip(0, .left_hand, base);
        try std.testing.expect(inv.gear.valid(base));
        try std.testing.expectEqual(item_bases.Kind.wand, inv.gear.slots.get(.right_hand).?.kind);
        try std.testing.expect(item_bases.spec(kind).damage == null);
        try std.testing.expect(inv.add(.{ .kind = .staff }));
        try inv.equip(0, .right_hand, base);
        try std.testing.expect(inv.gear.slots.get(.left_hand) == null);
        try std.testing.expectEqual(@as(usize, 2), inv.n);
    }
    var seen = std.EnumSet(item_bases.Kind).initEmpty();
    var rng = mathx.Rng.init(0x17E);
    for (0..2000) |_| seen.insert(items.roll(&rng, 0).kind);
    try std.testing.expectEqual(loot.BASES.len, seen.count());
}

test "rolled combat defenses and recovery modifiers reach equipment consumers" {
    const base = attrs.Attrs.of(.{ .strength = 20, .dexterity = 20, .intelligence = 20 });
    var gear = Gear{};
    gear.slots.set(.right_hand, .{ .kind = .crossbow, .mods = .{ .{ .kind = .physical_damage, .value = 20 }, .{ .kind = .penetration, .value = 10 }, null, null } });
    gear.slots.set(.gloves, .{ .kind = .gloves, .mods = .{ .{ .kind = .armour, .value = 4 }, .{ .kind = .crit, .value = 5 }, null, null } });
    gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .resistance, .value = 20, .element = .cold }, .{ .kind = .mana_regen, .value = 1 }, null, null } });
    gear.slots.set(.belt, .{ .kind = .belt, .mods = .{ .{ .kind = .life_flask, .value = 20 }, null, null, null } });
    const stats = gear.stats(base);
    try std.testing.expectEqual(@as(i32, 20), stats.physical_bonus);
    try std.testing.expectEqual(@as(i16, 20), stats.resists.get(.cold));
    try std.testing.expectEqual(base.crit() + 5, stats.crit());
    try std.testing.expectEqual(@as(i32, 30), gear.onHit(.ranged).penetration);
    try std.testing.expectEqual(@as(i32, 0), gear.onHit(.melee).penetration);
    try std.testing.expectEqual(@as(i32, 0), gear.forAttack(stats, .spell).physical_bonus);
    try std.testing.expectEqualDeep(passives.Perks{ .mana_regen = 1, .life_flask = 20 }, gear.perks(.{}));
}

test "imbued weapons add their element's ailment to that weapon's hits and worn mods sum across slots" {
    var gear = Gear{};
    gear.slots.set(.right_hand, .{ .kind = .handaxe, .mods = .{ .{ .kind = .imbue, .value = 15, .element = .fire }, .{ .kind = .mana_on_kill, .value = 2 }, null, null } });
    gear.slots.set(.helm, .{ .kind = .helmet, .mods = .{ .{ .kind = .masked, .value = 30 }, .{ .kind = .resolve, .value = 12 }, null, null } });
    gear.slots.set(.amulet, .{ .kind = .amulet, .mods = .{ .{ .kind = .lantern, .value = 1 }, .{ .kind = .resolve, .value = 8 }, null, null } });
    gear.slots.set(.belt, .{ .kind = .belt, .mods = .{ .{ .kind = .mana_flask, .value = 20 }, null, null, null } });
    gear.slots.set(.boots, .{ .kind = .boots, .mods = .{ .{ .kind = .stillness, .value = 2 }, null, null, null } });
    const hit = gear.onHit(.melee);
    try std.testing.expectEqual(@as(u32, 15), hit.chance(.burn));
    try std.testing.expectEqual(@as(u32, 25), hit.chance(.bleed));
    try std.testing.expectEqual(@as(u32, 0), hit.chance(.chill) + hit.chance(.shock));
    try std.testing.expectEqual(@as(u32, 0), gear.onHit(.ranged).chance(.burn));
    try std.testing.expectEqual(@as(i32, 20), gear.sum(.resolve));
    try std.testing.expectEqual(@as(i32, 1), gear.sum(.lantern));
    try std.testing.expectEqual(@as(i32, 30), gear.sum(.masked));
    try std.testing.expectEqual(@as(i32, 2), gear.sum(.stillness));
    try std.testing.expectEqualDeep(passives.Perks{}, gear.perks(.{}));
    try std.testing.expectEqual(@as(i32, 2), gear.sum(.mana_on_kill));
    try std.testing.expectEqual(@as(i32, 12), flask.recovers(.mana, 0, gear.draughts(gear.perks(.{}))));
    var line: [64]u8 = undefined;
    var s = std.io.fixedBufferStream(&line);
    (affixes.Affix{ .kind = .imbue, .value = 15, .element = .lightning }).write(s.writer());
    try std.testing.expectEqualStrings("15% chance to shock on hit", s.getWritten());
}
