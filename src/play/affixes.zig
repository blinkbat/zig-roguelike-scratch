const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const mathx = @import("../core/mathx.zig");
const passives = @import("passives.zig");
const wording = @import("../core/wording.zig");
const resilience = @import("resilience.zig");
const item_bases = @import("item_bases.zig");
const items = @import("items.zig");
const hero = @import("hero.zig");

pub const Mod = enum {
    life,
    mana,
    strength,
    dexterity,
    intelligence,
    physical_damage,
    spell_damage,
    crit,
    armour,
    dodge,
    resistance,
    mana_regen,
    life_on_kill,
    life_flask,
    penetration,
    thorns,
    spoils,
    imbue,
    resolve,
    lantern,
    mana_on_kill,
    mana_flask,
    masked,
    stillness,
    opportunist,
    bounding,
    alacrity,
    crit_damage,
    block,
    life_regen,
    leech,
    area,
    pierce,
    haste,

    pub fn grant(comptime m: Mod, amount: i32) passives.Grant {
        return .{ .kind = @field(passives.Kind, @tagName(m)), .amount = amount };
    }

    pub fn granted(comptime m: Mod) bool {
        return @hasField(passives.Kind, @tagName(m));
    }

    pub fn prefix(m: Mod) bool {
        return switch (m) {
            .strength, .dexterity, .intelligence, .physical_damage, .spell_damage, .armour, .resistance, .thorns, .imbue, .masked, .opportunist, .crit_damage, .block, .leech, .area, .pierce => true,
            .life, .mana, .crit, .dodge, .mana_regen, .life_on_kill, .life_flask, .penetration, .spoils, .resolve, .lantern, .mana_on_kill, .mana_flask, .stillness, .bounding, .alacrity, .life_regen, .haste => false,
        };
    }

    pub fn elements(m: Mod) []const damage.Element {
        return switch (m) {
            .resistance => std.enums.values(damage.Element),
            .imbue => &IMBUES,
            .life, .mana, .strength, .dexterity, .intelligence, .physical_damage, .spell_damage, .crit, .armour, .dodge, .mana_regen, .life_on_kill, .life_flask, .penetration, .thorns, .spoils, .resolve, .lantern, .mana_on_kill, .mana_flask, .masked, .stillness, .opportunist, .bounding, .alacrity, .crit_damage, .block, .life_regen, .leech, .area, .pierce, .haste => &.{},
        };
    }
    pub fn title(m: Mod, element: damage.Element) [:0]const u8 {
        return switch (m) {
            .life => "of Life",
            .mana => "of Insight",
            .strength => "Bear's",
            .dexterity => "Serpent's",
            .intelligence => "Sage's",
            .physical_damage => "Cruel",
            .spell_damage => "Sorcerous",
            .crit => "of Precision",
            .armour => "Reinforced",
            .dodge => "of Evasion",
            .resistance => switch (element) {
                .fire => "Fire-Warded",
                .cold => "Cold-Warded",
                .lightning => "Storm-Warded",
                .chaos => "Chaos-Warded",
            },
            .mana_regen => "of Renewal",
            .life_on_kill => "of Harvest",
            .life_flask => "of Plenty",
            .penetration => "of Puncturing",
            .thorns => "Thorned",
            .spoils => "of Spoils",
            .imbue => switch (element) {
                .fire => "Searing",
                .cold => "Rimed",
                .lightning, .chaos => "Charged",
            },
            .resolve => "of Resolve",
            .lantern => "of the Lantern",
            .mana_on_kill => "of Siphoning",
            .mana_flask => "of Draughts",
            .masked => "Masked",
            .stillness => "of Stillness",
            .opportunist => "Opportunist's",
            .bounding => "of Bounding",
            .alacrity => "of Alacrity",
            .crit_damage => "Savage",
            .block => "Stalwart",
            .life_regen => "of Mending",
            .leech => "Vampiric",
            .area => "Sweeping",
            .pierce => "Skewering",
            .haste => "of Haste",
        };
    }
    pub fn allows(m: Mod, k: item_bases.Kind) bool {
        const s = item_bases.spec(k);
        if (!k.equippable()) return false;
        const slot = s.slots[0];
        const weapon = s.damage != null;
        const ring = k.fits(.left_ring);
        const armour = slot.armour();
        return switch (m) {
            .physical_damage => weapon,
            .spell_damage => s.caster or slot == .amulet,
            .crit => weapon or slot == .gloves or ring,
            .armour => armour or k == .shield or k == .buckler,
            .dodge => slot == .boots or slot == .gloves or ring,
            .resistance => armour or slot == .left_hand or ring or slot == .amulet,
            .mana_regen => s.caster or k == .circlet or ring or slot == .amulet,
            .life_on_kill => weapon or k == .totem or ring,
            .life_flask => slot == .belt or slot == .amulet,
            .penetration => weapon or slot == .gloves,
            .thorns => slot == .chest or k == .shield,
            .spoils => ring or slot == .amulet,
            .imbue => weapon,
            .resolve => slot == .helm or slot == .chest or slot == .amulet,
            .lantern => slot == .helm or slot == .amulet,
            .mana_on_kill => s.caster or ring,
            .mana_flask => slot == .belt,
            .masked => slot == .helm,
            .stillness => slot == .boots or slot == .chest,
            .opportunist => weapon or slot == .gloves,
            .bounding => slot == .boots,
            .alacrity => k == .circlet or slot == .amulet,
            .crit_damage => weapon or s.caster or slot == .gloves or slot == .amulet,
            .block => k.blocks(),
            .life_regen => slot == .chest or slot == .belt or slot == .amulet,
            .leech => weapon or ring,
            .area => s.caster or slot == .amulet,
            .pierce => (weapon and s.attack == .ranged) or (s.caster and slot == .right_hand and !s.two_handed),
            .haste => slot == .boots or slot == .amulet,
            .life, .mana, .strength, .dexterity, .intelligence => true,
        };
    }
};

pub const IMBUES = [_]damage.Element{ .fire, .cold, .lightning };

pub fn imbued(e: damage.Element) resilience.Kind {
    return switch (e) {
        .fire => .burn,
        .cold => .chill,
        .lightning, .chaos => .shock,
    };
}

/// The modifiers loot rolls, in items.roll order, with their value ranges.
pub const AffixRoll = struct { kind: Mod, lo: i32, hi: i32 };

const Range = struct { lo: i32, hi: i32 };

const RANGES = std.EnumArray(Mod, Range).init(.{
    .life = .{ .lo = 2, .hi = 6 },
    .mana = .{ .lo = 1, .hi = 3 },
    .strength = .{ .lo = 1, .hi = 3 },
    .dexterity = .{ .lo = 1, .hi = 3 },
    .intelligence = .{ .lo = 1, .hi = 3 },
    .physical_damage = .{ .lo = 10, .hi = 20 },
    .spell_damage = .{ .lo = 10, .hi = 20 },
    .crit = .{ .lo = 2, .hi = 5 },
    .armour = .{ .lo = 2, .hi = 4 },
    .dodge = .{ .lo = 2, .hi = 4 },
    .resistance = .{ .lo = 10, .hi = 20 },
    .mana_regen = .{ .lo = 1, .hi = 1 },
    .life_on_kill = .{ .lo = 1, .hi = 2 },
    .life_flask = .{ .lo = 10, .hi = 20 },
    .penetration = .{ .lo = 5, .hi = 10 },
    .thorns = .{ .lo = 1, .hi = 2 },
    .spoils = .{ .lo = 15, .hi = 25 },
    .imbue = .{ .lo = 10, .hi = 20 },
    .resolve = .{ .lo = 10, .hi = 20 },
    .lantern = .{ .lo = 1, .hi = 1 },
    .mana_on_kill = .{ .lo = 1, .hi = 2 },
    .mana_flask = .{ .lo = 10, .hi = 20 },
    .masked = .{ .lo = 25, .hi = 40 },
    .stillness = .{ .lo = 1, .hi = 2 },
    .opportunist = .{ .lo = 15, .hi = 30 },
    .bounding = .{ .lo = 1, .hi = 1 },
    .alacrity = .{ .lo = 1, .hi = 1 },
    .crit_damage = .{ .lo = 10, .hi = 25 },
    .block = .{ .lo = 5, .hi = 10 },
    .life_regen = .{ .lo = 1, .hi = 2 },
    .leech = .{ .lo = 5, .hi = 10 },
    .area = .{ .lo = 1, .hi = 1 },
    .pierce = .{ .lo = 1, .hi = 2 },
    .haste = .{ .lo = 5, .hi = 10 },
});

pub const MODS = std.enums.values(Mod)[0..std.enums.values(Mod).len].*;

pub const AFFIXES = blk: {
    var out: [MODS.len]AffixRoll = undefined;
    for (MODS, &out) |m, *a| a.* = affixOf(m);
    break :blk out;
};

pub fn affixOf(k: Mod) AffixRoll {
    const r = RANGES.get(k);
    return .{ .kind = k, .lo = r.lo, .hi = r.hi };
}

pub const RareName = struct {
    first: First,
    last: Last,

    pub const First = enum { Spine, Void, Magus, Doom, Dread, Storm, Blood, Bone, Ash, Rune, Gloom, Soul, Death, Wraith, Grim, Viper, Raven, Dragon, Demon, Havoc, Eagle, Bramble, Carrion, Mind, Iron, Blight, Thorn, Frost, Ember, Shadow, Night, Plague, Grave, Rot, Hollow, Pale, Bitter, Cinder, Hate, Oath, Wolf, Serpent, Corpse, Skull, Pyre, Stone, Thunder, Venom, Mire, Gale, Moon, Dusk, Rift, Scourge, Wrath, Sorrow, Fate, Vortex, Hex, Brood, Kraken, Golem, Behemoth, Beast, Tempest, Ghoul, Lich, Warp, Chaos, Rage, Pain, Gore, Winter, Cairn };
    pub const Last = enum { Crusher, Maw, Fold, Bite, Grasp, Shroud, Song, Ward, Eye, Heart, Fang, Coil, Veil, Mark, Clasp, Crown, Touch, Hold, Bane, Whisper, Shell, Knot, Edge, Call, Thirst, Spike, Lash, Scar, Brand, Howl, Wing, Claw, Talon, Horn, Spur, Gnash, Rend, Ruin, Torment, Weaver, Reaver, Spiral, Breaker, Gyre, Scream, Roar, Stinger, Needle, Spark, Gaze, Bloom, Loop, Band, Sigil, Mantle, Cowl, Guard, Aegis, Bastion, Keep, Wall, Tread, Stride, Grip, Fist, Hand, Hew, Cleaver, Splitter, Impaler, Harp, Chant, Dirge, Hymn };

    pub fn roll(rng: *mathx.Rng) RareName {
        return .{ .first = rng.pick(First, std.enums.values(First)), .last = rng.pick(Last, std.enums.values(Last)) };
    }

    pub fn name(self: RareName, buf: []u8) [:0]const u8 {
        return std.fmt.bufPrintZ(buf, "{s} {s}", .{ @tagName(self.first), @tagName(self.last) }) catch @tagName(self.first);
    }
};

pub const Affix = struct {
    kind: Mod,
    value: i16,
    element: damage.Element = .fire,

    pub fn write(m: Affix, w: anytype) void {
        const n = m.value;
        switch (m.kind) {
            inline .life, .mana, .strength, .dexterity, .intelligence, .crit, .armour, .mana_regen, .life_flask => |k| k.grant(n).write(w),
            .life_regen => w.print("+{d} life recovered per {d} turns", .{ n, hero.LIFE_REGEN_TURNS }) catch {},
            .physical_damage => w.print("+{d}% physical weapon damage", .{n}) catch {},
            .spell_damage => w.print("+{d}% spell damage", .{n}) catch {},
            .dodge => w.print("+{d}% dodge chance", .{n}) catch {},
            .resistance => w.print("+{d}% {s} resistance", .{ n, wording.word(m.element) }) catch {},
            .life_on_kill => w.print("+{d} life on kill", .{n}) catch {},
            .penetration => w.print("Ignore {d}% " ++ attrs.REDUCTION_LABEL, .{n}) catch {},
            .thorns => w.print("Return {d} damage to melee attackers", .{n}) catch {},
            .spoils => w.print("+{d}% gold and item rarity", .{n}) catch {},
            .imbue => w.print(item_bases.ON_HIT_FMT, .{ n, wording.word(imbued(m.element)) }) catch {},
            .resolve => w.print("+{d}% stun resistance", .{n}) catch {},
            .lantern => w.print("+{d} light radius", .{n}) catch {},
            .mana_on_kill => w.print("+{d} mana on kill", .{n}) catch {},
            .mana_flask => w.print("+{d}% mana flask recovery", .{n}) catch {},
            .masked => w.print("{d}% less gas and steam damage", .{n}) catch {},
            .stillness => w.print("Sleeping foes notice {d} cells nearer", .{n}) catch {},
            .opportunist => w.print("+{d}% damage against pinned, chilled or maimed foes", .{n}) catch {},
            .bounding => w.print("+{d} movement skill range", .{n}) catch {},
            .alacrity => w.print("Skill cooldowns {d} turn{s} shorter", .{ n, mathx.plural(n) }) catch {},
            .crit_damage => w.print("+{d}% critical strike damage", .{n}) catch {},
            .block => w.print(item_bases.BLOCK_FMT, .{n}) catch {},
            .leech => w.print("Heal {d}% of the damage blows deal", .{n}) catch {},
            .area => w.print("+{d} area skill radius", .{n}) catch {},
            .pierce => w.print("Projectiles pass through {d} more foe{s}", .{ n, mathx.plural(n) }) catch {},
            .haste => w.print("{d}% chance an action takes no turn", .{n}) catch {},
        }
    }
};

pub const MAGIC_SIDE: usize = 1;
pub const RARE_SIDE: usize = 2;
const SIDES = 2;
pub const MAGIC_MOST = SIDES * MAGIC_SIDE;
pub const AFFIXES_MAX = SIDES * RARE_SIDE;
pub const RARE_LEAST = MAGIC_MOST + 1;

test "magic affixes respect equipment eligibility prefix suffix and rolled bounds" {
    var rng = mathx.Rng.init(0xAFF1);
    var seen = std.EnumSet(Mod).initEmpty();
    var elements = std.EnumSet(damage.Element).initEmpty();
    var imbues = std.EnumSet(damage.Element).initEmpty();
    for (0..50000) |_| {
        const it = items.roll(&rng, 0);
        for (it.mods) |maybe| if (maybe) |m| {
            seen.insert(m.kind);
            try std.testing.expect(m.kind.allows(it.kind));
            try std.testing.expect(m.value >= affixOf(m.kind).lo and m.value <= affixOf(m.kind).hi);
            if (m.kind == .resistance) elements.insert(m.element);
            if (m.kind == .imbue) {
                try std.testing.expect(m.element != .chaos);
                imbues.insert(m.element);
            }
        };
        if (it.rarity() == .magic) if (it.mods[1]) |second| {
            try std.testing.expect(it.mods[0].?.kind.prefix() != second.kind.prefix());
        };
    }
    try std.testing.expectEqual(AFFIXES.len, seen.count());
    try std.testing.expectEqual(std.enums.values(damage.Element).len, elements.count());
    try std.testing.expectEqual(IMBUES.len, imbues.count());
    var name: [items.NAME_MAX]u8 = undefined;
    try std.testing.expectEqualStrings("Rimed Mace of Siphoning", (items.Item{ .kind = .mace, .mods = .{ .{ .kind = .imbue, .value = 10, .element = .cold }, .{ .kind = .mana_on_kill, .value = 1 }, null, null } }).name(&name));
    try std.testing.expectEqualStrings("Masked Iron Helm of the Lantern", (items.Item{ .kind = .helmet, .mods = .{ .{ .kind = .masked, .value = 30 }, .{ .kind = .lantern, .value = 1 }, null, null } }).name(&name));
    const gloves = items.Item{ .kind = .gloves, .mods = .{ .{ .kind = .strength, .value = 2 }, .{ .kind = .crit, .value = 3 }, null, null } };
    try std.testing.expectEqualStrings("Bear's Leather Gloves of Precision", gloves.name(&name));
    try std.testing.expectEqualStrings("bear's leather gloves of precision", gloves.spoken(&name));
    try std.testing.expectEqualStrings("Leather Gloves of Precision", (items.Item{ .kind = .gloves, .mods = .{ .{ .kind = .crit, .value = 3 }, null, null, null } }).name(&name));
    try std.testing.expectEqualStrings("Fire-Warded Hunter's Hood", (items.Item{ .kind = .hood, .mods = .{ .{ .kind = .resistance, .value = 10, .element = .fire }, null, null, null } }).name(&name));
    try std.testing.expectEqualStrings("Short Sword", items.baseName(.sword, &name));
    try std.testing.expectEqualStrings("Magus Fold", (items.Item{ .kind = .robes, .rare_name = .{ .first = .Magus, .last = .Fold } }).spoken(&name));
}
