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
const hero = @import("hero.zig");

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
        const armed = self.weapon(attack) != null;
        if (!armed) out.physical_bonus -= self.sum(.physical_damage);
        out.crit_bonus += if (attack == .spell) base.spell_crit_bonus else if (armed) base.weapon_crit_bonus else 0;
        return out;
    }

    /// Life its worn items heal for a kill, innate grants and rolled modifiers alike; passives' heal blows only.
    pub fn killRecovery(self: Gear) i32 {
        return self.perks(.{}).life_on_kill;
    }

    pub fn manaOnKill(self: Gear) i32 {
        return self.floored(.mana_on_kill);
    }

    pub fn sum(self: Gear, kind: affixes.Mod) i32 {
        var n: i32 = 0;
        for (self.slots.values) |maybe| if (maybe) |it| {
            n += it.value(kind);
        };
        return n;
    }

    fn floored(self: Gear, kind: affixes.Mod) i32 {
        return @max(0, self.sum(kind));
    }

    /// Turns Alacrity takes off every cooldown.
    pub fn quicker(self: Gear) u8 {
        return std.math.lossyCast(u8, self.floored(.alacrity));
    }

    /// Cells Bounding adds to every movement skill's reach.
    pub fn bounding(self: Gear) i32 {
        return self.floored(.bounding);
    }

    pub fn lifeRegen(self: Gear) i32 {
        return self.floored(.life_regen);
    }

    pub fn leech(self: Gear) i32 {
        return self.floored(.leech);
    }

    /// Cells added to every area skill's radius.
    pub fn wider(self: Gear) i32 {
        return self.floored(.area);
    }

    /// Foes a single-target projectile passes through before the one that stops it.
    pub fn pierce(self: Gear) usize {
        return @intCast(self.floored(.pierce));
    }

    /// Percent chance an action spends no turn.
    pub fn haste(self: Gear) u32 {
        return @intCast(self.percent(.haste));
    }

    pub fn masked(self: Gear) i32 {
        return self.percent(.masked);
    }

    pub fn opportunist(self: Gear) i32 {
        return self.floored(.opportunist);
    }

    pub fn kindling(self: Gear) i32 {
        return self.floored(.kindling);
    }

    pub fn nightstalker(self: Gear) i32 {
        return self.floored(.nightstalker);
    }

    pub fn heft(self: Gear) i32 {
        return self.floored(.heft);
    }

    pub fn commander(self: Gear) i32 {
        return self.floored(.commander);
    }

    fn percent(self: Gear, kind: affixes.Mod) i32 {
        return std.math.clamp(self.sum(kind), 0, mathx.PERCENT);
    }

    /// Each flask's recovery bonus: life from `held`, which already counts worn grants; mana from worn mods alone.
    pub fn draughts(self: Gear, held: passives.Perks) flask.Bonus {
        return .{ .life = held.life_flask, .mana = self.sum(.mana_flask) };
    }

    pub fn draughtsOver(self: Gear, passive: passives.Perks) flask.Bonus {
        return self.draughts(self.perks(passive));
    }

    pub fn onHit(self: Gear, attack: attrs.Attack) item_bases.WeaponEffect {
        const own: i32 = if (self.slots.get(.right_hand)) |w| w.value(.penetration) else 0;
        const ammo: i32 = if (self.quiver()) |q| q.value(.penetration) else 0;
        var out = item_bases.WeaponEffect{ .penetration = self.sum(.penetration) - own - ammo };
        const held = self.wielded(attack) orelse return out;
        out.penetration += own;
        if (attack == .ranged) out.penetration += ammo;
        for (self.slots.values) |maybe| if (maybe) |it| {
            for (it.mods) |m| if (m) |a| if (a.kind == .imbue) out.imbue(a.element, @intCast(a.value));
        };
        const fixed = (held.innate orelse return out).effect();
        out.bleed = fixed.bleed;
        out.bleed_damage = fixed.bleed_damage;
        out.stun = fixed.stun;
        out.penetration += fixed.penetration;
        return out;
    }

    fn twoHander(self: Gear) ?items.Item {
        const it = self.slots.get(.right_hand) orelse return null;
        return if (item_bases.spec(it.kind).two_handed) it else null;
    }

    fn quiver(self: Gear) ?items.Item {
        const it = self.slots.get(.left_hand) orelse return null;
        return if (item_bases.spec(it.kind).quiver) it else null;
    }

    pub fn implement(self: Gear) bool {
        const it = self.slots.get(.right_hand) orelse return false;
        return item_bases.spec(it.kind).caster;
    }

    pub fn shield(self: Gear) bool {
        const it = self.slots.get(.left_hand) orelse return false;
        return it.kind.blocks();
    }

    pub fn startFor(c: hero.Class) Gear {
        var out = flasks;
        for (c.arms()) |k| out.slots.set(item_bases.spec(k).slots[0], .{ .kind = k });
        return out;
    }

    fn handsFit(self: Gear) bool {
        const off = self.slots.get(.left_hand) orelse return true;
        const main = item_bases.spec((self.slots.get(.right_hand) orelse return true).kind);
        if (item_bases.spec(off.kind).quiver) return main.attack == .ranged;
        return !main.two_handed;
    }

    pub fn offhandHolder(self: Gear) ?items.Item {
        if (self.slots.get(.left_hand) != null) return null;
        const main = self.twoHander() orelse return null;
        return if (item_bases.spec(main.kind).attack == .ranged) null else main;
    }

    pub fn valid(self: Gear, base: attrs.Attrs) bool {
        return self.validFrom(.{}, base);
    }

    /// A loaded save can wear unmet gear after a retune; only a change that unmeets an item is refused.
    pub fn validFrom(self: Gear, before: Gear, base: attrs.Attrs) bool {
        if (!self.handsFit()) return false;
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
        if (after.handsFit()) return after;
        after.slots.set(if (slot == .left_hand) .right_hand else .left_hand, null);
        return after;
    }

    pub fn statsWithout(self: Gear, slot: item_bases.Slot, base: attrs.Attrs) attrs.Attrs {
        var without = self;
        without.slots.set(slot, null);
        return without.stats(base);
    }

    pub fn requirementStats(self: Gear, it: items.Item, slot: item_bases.Slot, base: attrs.Attrs) attrs.Attrs {
        return self.wearing(it, slot).statsWithout(slot, base);
    }

    /// An item cannot fund its own requirement.
    fn wornMeets(self: Gear, slot: item_bases.Slot, base: attrs.Attrs) bool {
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

    pub fn scaling(self: Gear, attack: attrs.Attack) attrs.Scaling {
        const it = self.slots.get(.right_hand) orelse return attack.defaultScaling();
        return item_bases.spec(it.kind).scalingFor(attack) orelse attack.defaultScaling();
    }
};

test "weapon weights cross melee and range while caster implements have no innate attack" {
    const heavy = [_]item_bases.Kind{ .greatsword, .crossbow, .greatclub, .axe };
    const light = [_]item_bases.Kind{ .bow, .sling, .dagger, .sword, .handaxe };
    var gear = Gear{};
    const strong = attrs.Attrs.of(.{ .strength = 60, .dexterity = 10, .intelligence = 20 });
    for (heavy ++ light) |kind| {
        gear.slots.set(.right_hand, .{ .kind = kind });
        const s = item_bases.spec(kind);
        const is_heavy = std.mem.indexOfScalar(item_bases.Kind, &heavy, kind) != null;
        try std.testing.expectEqual(attrs.only(if (is_heavy) .heavy else .light), gear.scaling(s.attack));
        try std.testing.expectEqual(@as(i32, if (is_heavy) 60 else 10), strong.increaseBy(gear.scaling(s.attack)));
        try std.testing.expect(s.damage != null);
        try std.testing.expectEqual(s.damage, gear.weapon(s.attack));
        try std.testing.expect(gear.weapon(if (s.attack == .ranged) .melee else .ranged) == null);
    }
    const Split = struct { kind: item_bases.Kind, increase: i32 };
    for ([_]Split{ .{ .kind = .longsword, .increase = 35 }, .{ .kind = .mace, .increase = 40 }, .{ .kind = .war_bow, .increase = 35 } }) |split| {
        gear.slots.set(.right_hand, .{ .kind = split.kind });
        const attack = item_bases.spec(split.kind).attack;
        try std.testing.expectEqual(@as(usize, 2), gear.scaling(attack).count());
        try std.testing.expectEqual(split.increase, strong.increaseBy(gear.scaling(attack)));
    }
    const Implement = struct { kind: item_bases.Kind, spells: i32 };
    for ([_]Implement{ .{ .kind = .wand, .spells = 20 }, .{ .kind = .staff, .spells = 40 }, .{ .kind = .storm_wand, .spells = 15 } }) |implement| {
        gear.slots.set(.right_hand, .{ .kind = implement.kind });
        try std.testing.expect(item_bases.spec(implement.kind).damage == null);
        for (std.enums.values(attrs.Attack)) |attack| {
            try std.testing.expect(gear.weapon(attack) == null);
            if (attack != .spell) try std.testing.expectEqual(attack.defaultScaling(), gear.scaling(attack));
        }
        try std.testing.expectEqual(implement.spells, strong.increaseBy(gear.scaling(.spell)));
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
}

test "any class equips any hand base whose requirements it meets, and loot rolls every base" {
    for (hero.CLASSES) |class| {
        for (loot.BASES) |kind| {
            const slot = kind.slots()[0];
            if (slot != .right_hand and slot != .left_hand) continue;
            var met = class.attrs();
            inline for (attrs.ATTRS) |at| met.points.set(at, @max(met.get(at), @field(item_bases.spec(kind).needs, @tagName(at))));
            var inv = inventory.Inventory{};
            try std.testing.expect(inv.add(.{ .kind = kind }));
            try inv.equip(0, slot, met);
            try std.testing.expectEqual(kind, inv.gear.slots.get(slot).?.kind);
        }
    }
    var rng = mathx.Rng.init(0x17E);
    var seen = std.EnumSet(item_bases.Kind).initEmpty();
    for (0..2000) |_| seen.insert(items.roll(&rng, 0, .high).kind);
    try std.testing.expectEqual(loot.BASES.len, seen.count());
}

test "a quiver rides only beside a ranged weapon or an empty main hand" {
    const base = attrs.Attrs.of(.{ .strength = 30, .dexterity = 30, .intelligence = 30 });
    var inv = inventory.Inventory{};
    try std.testing.expect(inv.add(.{ .kind = .war_bow }));
    try inv.equip(0, .right_hand, base);
    try std.testing.expect(inv.add(.{ .kind = .ember_quiver }));
    try inv.equip(0, .left_hand, base);
    try std.testing.expect(inv.gear.valid(base));
    try std.testing.expectEqual(item_bases.Kind.war_bow, inv.gear.slots.get(.right_hand).?.kind);
    try std.testing.expect(inv.add(.{ .kind = .crossbow }));
    try inv.equip(0, .right_hand, base);
    try std.testing.expectEqual(item_bases.Kind.ember_quiver, inv.gear.slots.get(.left_hand).?.kind);
    try std.testing.expectEqual(@as(usize, 1), inv.n);
    try std.testing.expectEqual(@as(i32, 20), inv.gear.stats(base).element_bonus.get(.fire));
    try std.testing.expect(inv.gear.wearing(.{ .kind = .staff }, .right_hand).slots.get(.left_hand) == null);
    var held = Gear{};
    held.slots.set(.right_hand, .{ .kind = .greatsword });
    try std.testing.expectEqual(item_bases.Kind.greatsword, held.offhandHolder().?.kind);
    try std.testing.expect(held.wearing(.{ .kind = .quiver }, .left_hand).slots.get(.right_hand) == null);
    held.slots.set(.left_hand, .{ .kind = .quiver });
    try std.testing.expect(!held.valid(base));
    var sword = Gear{};
    sword.slots.set(.right_hand, .{ .kind = .longsword });
    const quivered = sword.wearing(.{ .kind = .quiver }, .left_hand);
    try std.testing.expect(quivered.slots.get(.right_hand) == null);
    try std.testing.expectEqual(item_bases.Kind.quiver, quivered.slots.get(.left_hand).?.kind);
    try std.testing.expect(quivered.valid(base));
    const armed = quivered.wearing(.{ .kind = .longsword }, .right_hand);
    try std.testing.expect(armed.slots.get(.left_hand) == null);
    try std.testing.expectEqual(item_bases.Kind.longsword, armed.slots.get(.right_hand).?.kind);
    sword.slots.set(.left_hand, .{ .kind = .quiver });
    try std.testing.expect(!sword.valid(base));
    var pierced = Gear{};
    pierced.slots.set(.right_hand, .{ .kind = .war_bow });
    try std.testing.expect(pierced.offhandHolder() == null);
    pierced.slots.set(.left_hand, items.affixed(.quiver, &.{.{ .kind = .penetration, .value = 7 }}));
    try std.testing.expectEqual(@as(i32, 7), pierced.onHit(.ranged).penetration);
    try std.testing.expectEqual(@as(i32, 0), pierced.onHit(.melee).penetration);
    try std.testing.expectEqual(@as(i32, 0), pierced.onHit(.spell).penetration);
}

test "rolled combat defenses and recovery modifiers reach equipment consumers" {
    const base = attrs.Attrs.of(.{ .strength = 20, .dexterity = 20, .intelligence = 20 });
    var gear = Gear{};
    gear.slots.set(.right_hand, items.affixed(.crossbow, &.{ .{ .kind = .physical_damage, .value = 20 }, .{ .kind = .penetration, .value = 10 } }));
    gear.slots.set(.gloves, items.affixed(.gloves, &.{ .{ .kind = .armour, .value = 4 }, .{ .kind = .crit, .value = 5 } }));
    gear.slots.set(.left_ring, items.affixed(.ring, &.{ .{ .kind = .resistance, .value = 20, .element = .cold }, .{ .kind = .mana_regen, .value = 1 } }));
    gear.slots.set(.belt, items.affixed(.belt, &.{.{ .kind = .life_flask, .value = 20 }}));
    const stats = gear.stats(base);
    try std.testing.expectEqual(@as(i32, 20), stats.physical_bonus);
    try std.testing.expectEqual(@as(i16, 20), stats.resists.get(.cold));
    try std.testing.expectEqual(base.crit() + 5, stats.crit());
    try std.testing.expectEqual(@as(i32, 30), gear.onHit(.ranged).penetration);
    try std.testing.expectEqual(@as(i32, 0), gear.onHit(.melee).penetration);
    try std.testing.expectEqual(@as(i32, 0), gear.forAttack(stats, .spell).physical_bonus);
    try std.testing.expectEqualDeep(passives.Perks{ .mana_regen = 1, .life_flask = 20 }, gear.perks(.{}));
    gear.slots.set(.gloves, items.affixed(.gloves, &.{.{ .kind = .penetration, .value = 7 }}));
    try std.testing.expectEqual(@as(i32, 37), gear.onHit(.ranged).penetration);
    try std.testing.expectEqual(@as(i32, 7), gear.onHit(.melee).penetration);
    gear.slots.set(.right_hand, null);
    try std.testing.expectEqual(@as(i32, 7), gear.onHit(.melee).penetration);
}

test "imbued weapons add their element's ailment to that weapon's hits and worn mods sum across slots" {
    var gear = Gear{};
    gear.slots.set(.right_hand, items.affixed(.handaxe, &.{ .{ .kind = .imbue, .value = 15, .element = .fire }, .{ .kind = .mana_on_kill, .value = 2 } }));
    gear.slots.set(.helm, items.affixed(.helmet, &.{ .{ .kind = .masked, .value = 30 }, .{ .kind = .resolve, .value = 12 } }));
    gear.slots.set(.amulet, items.affixed(.amulet, &.{ .{ .kind = .lantern, .value = 1 }, .{ .kind = .resolve, .value = 8 } }));
    gear.slots.set(.belt, items.affixed(.belt, &.{.{ .kind = .mana_flask, .value = 20 }}));
    gear.slots.set(.boots, items.affixed(.boots, &.{.{ .kind = .stillness, .value = 2 }}));
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
