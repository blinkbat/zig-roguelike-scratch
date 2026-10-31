const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const passives = @import("passives.zig");
const bleeding = @import("bleeding.zig");
const flask = @import("flask.zig");
const consumable = @import("consumable.zig");
const wording = @import("../core/wording.zig");

pub const Slot = enum {
    left_hand,
    right_hand,
    helm,
    chest,
    belt,
    gloves,
    boots,
    left_ring,
    right_ring,
    amulet,
    life_flask,
    mana_flask,
    pub fn name(s: Slot) [:0]const u8 {
        return switch (s) {
            .left_hand => "Offhand",
            .right_hand => "Main hand",
            .helm => "Helm",
            .chest => "Chest",
            .belt => "Belt",
            .gloves => "Gloves",
            .boots => "Boots",
            .left_ring => "Left ring",
            .right_ring => "Right ring",
            .amulet => "Amulet",
            .life_flask => "Life flask",
            .mana_flask => "Mana flask",
        };
    }

    pub fn ofFlask(k: flask.Kind) Slot {
        return switch (k) {
            .life => .life_flask,
            .mana => .mana_flask,
        };
    }

    /// Worn as armour.
    pub fn armour(s: Slot) bool {
        return switch (s) {
            .helm, .chest, .belt, .gloves, .boots => true,
            .left_hand, .right_hand, .left_ring, .right_ring, .amulet, .life_flask, .mana_flask => false,
        };
    }
};
pub const SLOTS = std.enums.values(Slot);
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

    /// The passive of the same name, for a modifier that reads and applies as one.
    fn grant(comptime m: Mod, amount: i32) passives.Grant {
        return .{ .kind = @field(passives.Kind, @tagName(m)), .amount = amount };
    }

    pub fn prefix(m: Mod) bool {
        return switch (m) {
            .strength, .dexterity, .intelligence, .physical_damage, .spell_damage, .armour, .resistance, .thorns => true,
            .life, .mana, .crit, .dodge, .mana_regen, .life_on_kill, .life_flask, .penetration, .spoils => false,
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
        };
    }
    pub fn allows(m: Mod, k: Kind) bool {
        const s = spec(k);
        const slot = s.slots[0];
        const weapon = s.damage != null;
        const ring = slot == .left_ring;
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
            .life, .mana, .strength, .dexterity, .intelligence => true,
        };
    }
};
/// The modifiers loot rolls, in roll order, with their value ranges.
const AffixRoll = struct { kind: Mod, lo: i32, hi: i32 };
const AFFIXES = [_]AffixRoll{
    .{ .kind = .life, .lo = 2, .hi = 6 },
    .{ .kind = .mana, .lo = 1, .hi = 3 },
    .{ .kind = .strength, .lo = 1, .hi = 3 },
    .{ .kind = .dexterity, .lo = 1, .hi = 3 },
    .{ .kind = .intelligence, .lo = 1, .hi = 3 },
    .{ .kind = .physical_damage, .lo = 10, .hi = 20 },
    .{ .kind = .spell_damage, .lo = 10, .hi = 20 },
    .{ .kind = .crit, .lo = 2, .hi = 5 },
    .{ .kind = .armour, .lo = 2, .hi = 4 },
    .{ .kind = .dodge, .lo = 2, .hi = 4 },
    .{ .kind = .resistance, .lo = 10, .hi = 20 },
    .{ .kind = .mana_regen, .lo = 1, .hi = 1 },
    .{ .kind = .life_on_kill, .lo = 1, .hi = 2 },
    .{ .kind = .life_flask, .lo = 10, .hi = 20 },
    .{ .kind = .penetration, .lo = 5, .hi = 10 },
    .{ .kind = .thorns, .lo = 1, .hi = 2 },
    .{ .kind = .spoils, .lo = 15, .hi = 25 },
};
pub const MODS = blk: {
    var out: [AFFIXES.len]Mod = undefined;
    for (AFFIXES, &out) |a, *m| m.* = a.kind;
    std.debug.assert(std.mem.eql(Mod, &out, std.enums.values(Mod)));
    break :blk out;
};
pub const Kind = enum {
    sword,
    axe,
    bow,
    staff,
    longsword,
    mace,
    greatsword,
    crossbow,
    greatclub,
    sling,
    dagger,
    handaxe,
    wand,
    tome,
    orb,
    buckler,
    totem,
    shield,
    cap,
    helmet,
    leather,
    mail,
    belt,
    gloves,
    boots,
    ring,
    amulet,
    hunting_bow,
    war_bow,
    ash_wand,
    rime_wand,
    storm_wand,
    plate,
    robes,
    hood,
    circlet,
    gauntlets,
    spellwraps,
    iron_boots,
    broad_belt,
    flask_belt,
    sash,
    iron_ring,
    jade_ring,
    ruby_ring,
    sapphire_ring,
    life_flask,
    mana_flask,

    pub fn slots(k: Kind) []const Slot {
        return spec(k).slots;
    }

    pub fn ofFlask(k: flask.Kind) Kind {
        return switch (k) {
            .life => .life_flask,
            .mana => .mana_flask,
        };
    }

    pub fn flaskOf(k: Kind) ?flask.Kind {
        const innate = spec(k).innate orelse return null;
        return if (innate == .flask) innate.flask else null;
    }
};
/// What loot rolls: every base but the flasks.
const LOOT = blk: {
    var out: [std.enums.values(Kind).len - std.enums.values(flask.Kind).len]Kind = undefined;
    var n: usize = 0;
    for (std.enums.values(Kind)) |k| if (k.flaskOf() == null) {
        out[n] = k;
        n += 1;
    };
    break :blk out;
};
/// Percent of slain foes that drop an item.
pub const DROP_PERCENT = 10;
pub const FOE_GOLD_PERCENT = 50;
pub const MAGIC_PERCENT = 20;
pub const RARE_PERCENT = 5;
pub const Rarity = enum { normal, magic, rare };

pub const RareName = struct {
    first: First,
    last: Last,

    pub const First = enum { Spine, Void, Magus, Doom, Dread, Storm, Blood, Bone, Ash, Rune, Gloom, Soul, Death, Wraith, Grim, Viper, Raven, Dragon, Demon, Havoc, Eagle, Bramble, Carrion, Mind };
    pub const Last = enum { Crusher, Maw, Fold, Bite, Grasp, Shroud, Song, Ward, Eye, Heart, Fang, Coil, Veil, Mark, Clasp, Crown, Touch, Hold, Bane, Whisper, Shell, Knot, Edge, Call };

    fn roll(rng: *mathx.Rng) RareName {
        return .{ .first = rng.pick(First, std.enums.values(First)), .last = rng.pick(Last, std.enums.values(Last)) };
    }

    pub fn name(self: RareName, buf: []u8) [:0]const u8 {
        return std.fmt.bufPrintZ(buf, "{s} {s}", .{ @tagName(self.first), @tagName(self.last) }) catch @tagName(self.first);
    }
};
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
pub const Affix = struct {
    kind: Mod,
    value: i16,
    element: damage.Element = .fire,

    pub fn write(m: Affix, w: anytype) void {
        const n = m.value;
        switch (m.kind) {
            inline .life, .mana, .strength, .dexterity, .intelligence, .crit, .armour, .mana_regen, .life_flask => |k| k.grant(n).write(w),
            .physical_damage => w.print("+{d}% physical weapon damage", .{n}) catch {},
            .spell_damage => w.print("+{d}% spell damage", .{n}) catch {},
            .dodge => w.print("+{d}% dodge chance", .{n}) catch {},
            .resistance => w.print("+{d}% {s} resistance", .{ n, wording.word(m.element) }) catch {},
            .life_on_kill => w.print("+{d} life on kill", .{n}) catch {},
            .penetration => w.print("Ignore {d}% " ++ attrs.REDUCTION_LABEL, .{n}) catch {},
            .thorns => w.print("Return {d} damage to melee attackers", .{n}) catch {},
            .spoils => w.print("+{d}% gold and item rarity", .{n}) catch {},
        }
    }
};
pub const AFFIXES_MAX = 4;
pub const NAME_MAX = 128;
pub const WeaponEffect = struct {
    bleed: u32 = 0,
    bleed_damage: i32 = bleeding.STILL,
    stun: u32 = 0,
    penetration: i32 = 0,

    pub fn chance(self: WeaponEffect, k: @import("resilience.zig").Kind) u32 {
        return switch (k) {
            .bleed => self.bleed,
            .stun => self.stun,
            .burn, .chill, .pin, .shock, .sunder, .blind, .confusion, .fright => 0,
        };
    }
};

pub const Innate = union(enum) {
    grant: passives.Grant,
    weapon_crit: i32,
    spell_crit: i32,
    physical_damage: i32,
    element: struct { kind: damage.Element, percent: i32 },
    bleed: struct { chance: u32, damage: i32 = bleeding.STILL },
    stun: u32,
    penetration: i32,
    flask: flask.Kind,

    pub fn stat(kind: passives.Kind, amount: i32) Innate {
        return .{ .grant = .{ .kind = kind, .amount = amount } };
    }

    fn apply(self: Innate, a: *attrs.Attrs) void {
        switch (self) {
            .grant => |g| g.apply(a),
            .weapon_crit => |n| a.weapon_crit_bonus += n,
            .spell_crit => |n| a.spell_crit_bonus += n,
            .physical_damage => |n| a.physical_bonus += n,
            .element => |e| a.element_bonus.getPtr(e.kind).* += e.percent,
            .bleed, .stun, .penetration, .flask => {},
        }
    }

    pub fn write(self: Innate, w: anytype) void {
        switch (self) {
            .grant => |g| g.write(w),
            .weapon_crit => |n| w.print("+{d}% " ++ attrs.WEAPON_CRIT_LABEL, .{n}) catch {},
            .spell_crit => |n| w.print("+{d}% " ++ attrs.SPELL_CRIT_LABEL, .{n}) catch {},
            .physical_damage => |n| w.print("+{d}% " ++ attrs.PHYSICAL_LABEL, .{n}) catch {},
            .element => |e| w.print("+{d}% {s} damage", .{ e.percent, wording.word(e.kind) }) catch {},
            .bleed => |b| w.print("{d}% chance to bleed on hit", .{b.chance}) catch {},
            .stun => |n| w.print("{d}% chance to stun on hit", .{n}) catch {},
            .penetration => |n| w.print("Ignore {d}% physical reduction", .{n}) catch {},
            .flask => |k| w.writeAll(flask.effect(k)) catch {},
        }
    }
};

pub const Spec = struct {
    name: [:0]const u8,
    /// Where it may be worn.
    slots: []const Slot,
    needs: attrs.Needs = .{},
    damage: ?damage.Base = null,
    style: attrs.Style = .heavy,
    attack: attrs.Attack = .melee,
    two_handed: bool = false,
    /// A spellcaster's implement, which rolls spell modifiers.
    caster: bool = false,
    armour: i16 = 0,
    innate: ?Innate = null,
};
const SPECS = std.EnumArray(Kind, Spec).init(.{
    .sword = .{ .name = "Short sword", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 3, .hi = 4 }, .style = .light },
    .axe = .{ .name = "Great axe", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 5, .hi = 9 }, .two_handed = true, .innate = .{ .bleed = .{ .chance = 30, .damage = 2 } } },
    .bow = .{ .name = "Short bow", .slots = &.{.right_hand}, .needs = .{ .dexterity = 12 }, .damage = .{ .lo = 2, .hi = 5 }, .style = .light, .attack = .ranged, .two_handed = true },
    .staff = .{ .name = "Oak staff", .slots = &.{.right_hand}, .needs = .{ .intelligence = 16 }, .two_handed = true, .caster = true, .innate = Innate.stat(.spell_damage, 30) },
    .longsword = .{ .name = "Longsword", .slots = &.{.right_hand}, .needs = .{ .strength = 10 }, .damage = .{ .lo = 4, .hi = 7 } },
    .mace = .{ .name = "Mace", .slots = &.{.right_hand}, .needs = .{ .strength = 10 }, .damage = .{ .lo = 3, .hi = 6 }, .innate = .{ .stun = 15 } },
    .greatsword = .{ .name = "Greatsword", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 7, .hi = 12 }, .two_handed = true },
    .crossbow = .{ .name = "Crossbow", .slots = &.{.right_hand}, .needs = .{ .strength = 12 }, .damage = .{ .lo = 3, .hi = 7 }, .attack = .ranged, .two_handed = true, .innate = .{ .penetration = 20 } },
    .greatclub = .{ .name = "Greatclub", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 5, .hi = 9 }, .two_handed = true, .innate = .{ .stun = 25 } },
    .sling = .{ .name = "Sling", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 1, .hi = 4 }, .style = .light, .attack = .ranged },
    .dagger = .{ .name = "Dagger", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 1, .hi = 4 }, .style = .light, .innate = .{ .weapon_crit = 15 } },
    .handaxe = .{ .name = "Handaxe", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 2, .hi = 3 }, .style = .light, .innate = .{ .bleed = .{ .chance = 25 } } },
    .wand = .{ .name = "Wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 12 }, .caster = true, .innate = .{ .spell_crit = 8 } },
    .tome = .{ .name = "Tome", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .caster = true, .innate = Innate.stat(.mana, 3) },
    .orb = .{ .name = "Orb", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .caster = true, .innate = .{ .spell_crit = 6 } },
    .buckler = .{ .name = "Buckler", .slots = &.{.left_hand}, .needs = .{ .dexterity = 10 }, .armour = 2, .innate = Innate.stat(.dodge, 4) },
    .totem = .{ .name = "Totem", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .innate = Innate.stat(.life_on_kill, 1) },
    .shield = .{ .name = "Wooden shield", .slots = &.{.left_hand}, .needs = .{ .strength = 10 }, .armour = 6 },
    .cap = .{ .name = "Leather cap", .slots = &.{.helm}, .armour = 2 },
    .helmet = .{ .name = "Iron helm", .slots = &.{.helm}, .needs = .{ .strength = 16 }, .armour = 4, .innate = Innate.stat(.life, 3) },
    .leather = .{ .name = "Leather armour", .slots = &.{.chest}, .needs = .{ .strength = 10 }, .armour = 5, .innate = Innate.stat(.dodge, 5) },
    .mail = .{ .name = "Mail armour", .slots = &.{.chest}, .needs = .{ .strength = 20 }, .armour = 10 },
    .belt = .{ .name = "Leather belt", .slots = &.{.belt}, .armour = 1 },
    .gloves = .{ .name = "Leather gloves", .slots = &.{.gloves}, .armour = 1, .innate = Innate.stat(.light_damage, 10) },
    .boots = .{ .name = "Soft boots", .slots = &.{.boots}, .armour = 1, .innate = Innate.stat(.dodge, 3) },
    .ring = .{ .name = "Copper ring", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.life, 1) },
    .amulet = .{ .name = "Bronze amulet", .slots = &.{.amulet}, .innate = Innate.stat(.life, 2) },
    .hunting_bow = .{ .name = "Hunting bow", .slots = &.{.right_hand}, .needs = .{ .dexterity = 16 }, .damage = .{ .lo = 2, .hi = 4 }, .style = .light, .attack = .ranged, .two_handed = true, .innate = .{ .weapon_crit = 12 } },
    .war_bow = .{ .name = "War bow", .slots = &.{.right_hand}, .needs = .{ .dexterity = 22 }, .damage = .{ .lo = 3, .hi = 6 }, .style = .light, .attack = .ranged, .two_handed = true },
    .ash_wand = .{ .name = "Ash wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14 }, .caster = true, .innate = .{ .element = .{ .kind = .fire, .percent = 25 } } },
    .rime_wand = .{ .name = "Rime wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14 }, .caster = true, .innate = .{ .element = .{ .kind = .cold, .percent = 25 } } },
    .storm_wand = .{ .name = "Storm wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14 }, .caster = true, .innate = .{ .element = .{ .kind = .lightning, .percent = 25 } } },
    .plate = .{ .name = "Plate armour", .slots = &.{.chest}, .needs = .{ .strength = 24 }, .armour = 15 },
    .robes = .{ .name = "Robes", .slots = &.{.chest}, .needs = .{ .intelligence = 12 }, .armour = 1, .innate = Innate.stat(.mana, 4) },
    .hood = .{ .name = "Hunter's hood", .slots = &.{.helm}, .needs = .{ .dexterity = 14 }, .armour = 1, .innate = Innate.stat(.crit, 5) },
    .circlet = .{ .name = "Circlet", .slots = &.{.helm}, .needs = .{ .intelligence = 14 }, .innate = Innate.stat(.mana_regen, 1) },
    .gauntlets = .{ .name = "Gauntlets", .slots = &.{.gloves}, .needs = .{ .strength = 14 }, .armour = 2, .innate = Innate.stat(.heavy_damage, 10) },
    .spellwraps = .{ .name = "Spellwraps", .slots = &.{.gloves}, .needs = .{ .intelligence = 12 }, .innate = Innate.stat(.spell_damage, 10) },
    .iron_boots = .{ .name = "Iron boots", .slots = &.{.boots}, .needs = .{ .strength = 14 }, .armour = 5 },
    .broad_belt = .{ .name = "Broad belt", .slots = &.{.belt}, .innate = Innate.stat(.life, 3) },
    .flask_belt = .{ .name = "Flask belt", .slots = &.{.belt}, .innate = Innate.stat(.life_flask, 20) },
    .sash = .{ .name = "Woven sash", .slots = &.{.belt}, .innate = Innate.stat(.mana, 2) },
    .iron_ring = .{ .name = "Iron ring", .slots = &.{ .left_ring, .right_ring }, .innate = .{ .physical_damage = 10 } },
    .jade_ring = .{ .name = "Jade ring", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.dodge, 3) },
    .ruby_ring = .{ .name = "Ruby ring", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.life, 3) },
    .sapphire_ring = .{ .name = "Sapphire ring", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.mana, 2) },
    .life_flask = .{ .name = "Life flask", .slots = &.{.life_flask}, .innate = .{ .flask = .life } },
    .mana_flask = .{ .name = "Mana flask", .slots = &.{.mana_flask}, .innate = .{ .flask = .mana } },
});

pub fn spec(k: Kind) Spec {
    return SPECS.getPtrConst(k).*;
}

pub const Item = struct {
    kind: Kind,
    mods: [AFFIXES_MAX]?Affix = @splat(null),
    rare_name: ?RareName = null,

    pub fn name(self: Item, buf: []u8) [:0]const u8 {
        if (self.rare_name) |rare| return rare.name(buf);
        const base = wording.namedOr(self.kind, spec(self.kind).name);
        var pre: []const u8 = "";
        var post: []const u8 = "";
        for (self.mods) |maybe| if (maybe) |m| {
            if (m.kind.prefix()) pre = m.kind.title(m.element) else post = m.kind.title(m.element);
        };
        return std.fmt.bufPrintZ(buf, "{s}{s}{s}{s}{s}", .{ pre, if (pre.len > 0) " " else "", base, if (post.len > 0) " " else "", post }) catch base;
    }

    pub fn fits(self: Item, slot: Slot) bool {
        return std.mem.indexOfScalar(Slot, self.kind.slots(), slot) != null;
    }

    pub fn magical(self: Item) bool {
        return self.mods[0] != null;
    }

    pub fn rarity(self: Item) Rarity {
        return if (self.rare_name != null) .rare else if (self.magical()) .magic else .normal;
    }

    fn allows(self: Item, kind: Mod) bool {
        if (!kind.allows(self.kind)) return false;
        var same_side: usize = 0;
        for (self.mods) |maybe| if (maybe) |m| {
            if (m.kind == kind) return false;
            if (m.kind.prefix() == kind.prefix()) same_side += 1;
        };
        return same_side < @as(usize, if (self.rarity() == .rare) 2 else 1);
    }

    fn allowsRoll(self: Item, a: AffixRoll) bool {
        return self.allows(a.kind);
    }

    pub fn value(self: Item, kind: Mod) i32 {
        var n: i32 = 0;
        for (self.mods) |maybe| if (maybe) |m| {
            if (m.kind == kind) n += m.value;
        };
        return n;
    }

    pub fn apply(self: Item, a: *attrs.Attrs) void {
        const base = spec(self.kind);
        a.armour += base.armour;
        if (base.innate) |innate| innate.apply(a);
        for (self.mods) |maybe| if (maybe) |m| switch (m.kind) {
            inline .life, .mana, .strength, .dexterity, .intelligence, .spell_damage, .crit, .armour, .dodge => |k| k.grant(m.value).apply(a),
            .physical_damage => a.physical_bonus += m.value,
            .resistance => a.resists.getPtr(m.element).* += m.value,
            .thorns => a.thorns += m.value,
            .spoils => {
                a.gold_find += m.value;
                a.item_rarity += m.value;
            },
            .mana_regen, .life_on_kill, .life_flask, .penetration => {},
        };
    }

    pub fn meets(self: Item, a: attrs.Attrs) bool {
        return a.meets(spec(self.kind).needs);
    }
};

/// A white item, no modifiers rolled.
pub fn unrolled(rng: *mathx.Rng) Item {
    return .{ .kind = rng.pick(Kind, &LOOT) };
}

pub fn roll(rng: *mathx.Rng, item_rarity: i32) Item {
    var out = unrolled(rng);
    const quality = rng.below(mathx.PERCENT);
    if (quality >= qualityChance(MAGIC_PERCENT + RARE_PERCENT, item_rarity)) return out;
    affix(&out, rng, quality < qualityChance(RARE_PERCENT, item_rarity));
    return out;
}

pub fn rollRare(rng: *mathx.Rng) Item {
    var out = unrolled(rng);
    affix(&out, rng, true);
    return out;
}

fn affix(out: *Item, rng: *mathx.Rng, rare: bool) void {
    if (rare) out.rare_name = RareName.roll(rng);
    const count = if (rare) rng.range(3, AFFIXES_MAX) else rng.range(1, 2);
    for (0..@intCast(count)) |i| {
        const a = rng.pickWhere(AffixRoll, &AFFIXES, out.*, Item.allowsRoll).?;
        out.mods[i] = .{ .kind = a.kind, .value = @intCast(rng.range(a.lo, a.hi)), .element = if (a.kind == .resistance) rng.pick(damage.Element, std.enums.values(damage.Element)) else .fire };
    }
}

fn qualityChance(base: u32, item_rarity: i32) u32 {
    return @intCast(std.math.clamp(@divTrunc(@as(i64, base) * (mathx.PERCENT + @as(i64, item_rarity)), mathx.PERCENT), 0, mathx.PERCENT));
}

pub const Loot = struct { gold: i32 = 0, item: ?Item = null, supply: ?consumable.Kind = null };

pub fn foeLoot(rng: *mathx.Rng, item_rarity: i32) Loot {
    return .{
        .gold = if (rng.percent(FOE_GOLD_PERCENT)) FOE_GOLD.roll(rng) else 0,
        .item = if (rng.percent(DROP_PERCENT)) roll(rng, item_rarity) else null,
        .supply = consumable.roll(rng, consumable.FOE_PERCENT),
    };
}

pub const Gear = struct {
    slots: std.EnumArray(Slot, ?Item) = .initFill(null),

    /// A new run's: both flasks worn, nothing else.
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
        for (self.slots.values) |maybe| if (maybe) |it| {
            if (spec(it.kind).innate) |innate| if (innate == .grant) innate.grant.perk(&out);
            out.mana_regen += it.value(.mana_regen);
            out.life_on_kill += it.value(.life_on_kill);
            out.life_flask += it.value(.life_flask);
        };
        return out;
    }

    pub fn forAttack(self: Gear, base: attrs.Attrs, attack: attrs.Attack) attrs.Attrs {
        var out = base;
        if (self.weapon(attack) == null) {
            for (self.slots.values) |maybe| if (maybe) |it| {
                out.physical_bonus -= it.value(.physical_damage);
            };
        }
        out.crit_bonus += if (attack == .spell) base.spell_crit_bonus else if (self.weapon(attack) != null) base.weapon_crit_bonus else 0;
        return out;
    }

    /// Life its worn items heal for a kill, innate grants and rolled modifiers alike; passives' heal blows only.
    pub fn killRecovery(self: Gear) i32 {
        return self.perks(.{}).life_on_kill;
    }

    pub fn onHit(self: Gear, attack: attrs.Attack) WeaponEffect {
        if (self.weapon(attack) == null) return .{};
        var out = WeaponEffect{};
        for (self.slots.values) |maybe| if (maybe) |it| {
            out.penetration += it.value(.penetration);
        };
        const innate = spec(self.slots.get(.right_hand).?.kind).innate orelse return out;
        const fixed: WeaponEffect = switch (innate) {
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

    /// The main hand's weapon, when it takes both hands.
    pub fn twoHander(self: Gear) ?Item {
        const it = self.slots.get(.right_hand) orelse return null;
        return if (spec(it.kind).two_handed) it else null;
    }

    pub fn valid(self: Gear, base: attrs.Attrs) bool {
        if (self.twoHander() != null and self.slots.get(.left_hand) != null) return false;
        for (SLOTS) |slot| if (self.slots.get(slot)) |it| {
            if (!it.fits(slot) or !self.wornMeets(slot, base)) return false;
        };
        return true;
    }

    /// `it` worn in `slot`, with the hands it displaces emptied.
    pub fn wearing(self: Gear, it: Item, slot: Slot) Gear {
        var after = self;
        after.slots.set(slot, it);
        if (spec(it.kind).two_handed) after.slots.set(.left_hand, null);
        if (slot == .left_hand and self.twoHander() != null) after.slots.set(.right_hand, null);
        return after;
    }

    /// What everything else worn gives, with `slot` emptied.
    pub fn statsWithout(self: Gear, slot: Slot, base: attrs.Attrs) attrs.Attrs {
        var without = self;
        without.slots.set(slot, null);
        return without.stats(base);
    }

    /// An item cannot fund its own requirement.
    pub fn wornMeets(self: Gear, slot: Slot, base: attrs.Attrs) bool {
        const it = self.slots.get(slot) orelse return true;
        return it.meets(self.statsWithout(slot, base));
    }

    pub fn weapon(self: Gear, attack: attrs.Attack) ?damage.Base {
        const it = self.slots.get(.right_hand) orelse return null;
        const s = spec(it.kind);
        return if (s.attack == attack) s.damage else null;
    }

    pub fn scaling(self: Gear, attack: attrs.Attack) attrs.Style {
        if (self.weapon(attack) != null) return spec(self.slots.get(.right_hand).?.kind).style;
        return attack.defaultStyle();
    }
};

pub const BAG_MAX = 256;
pub const Failure = error{ Missing, WrongSlot, Requirements, Full };

pub fn caption(err: Failure) [:0]const u8 {
    return switch (err) {
        error.Full => "Inventory full",
        error.Requirements => "Requirements unmet in final loadout",
        error.WrongSlot => "Wrong slot",
        error.Missing => "Item unavailable",
    };
}
pub const Inventory = struct {
    bag: [BAG_MAX]Item = undefined,
    n: usize = 0,
    gear: Gear = .{},
    stacks: std.EnumArray(consumable.Kind, u8) = .initFill(0),

    pub const COUNTED = .{.{ "bag", "n" }};

    pub fn add(self: *Inventory, it: Item) bool {
        if (self.n == BAG_MAX) return false;
        self.bag[self.n] = it;
        self.n += 1;
        return true;
    }

    /// One more `k` on its stack, unless the stack is full.
    pub fn stock(self: *Inventory, k: consumable.Kind) bool {
        const n = self.stacks.getPtr(k);
        if (n.* >= consumable.STACK_MAX) return false;
        n.* += 1;
        return true;
    }

    pub fn remove(self: *Inventory, at: usize) Item {
        std.debug.assert(at < self.n);
        const it = self.bag[at];
        mathx.removeAt(Item, &self.bag, &self.n, at, null);
        return it;
    }

    /// The loadout with bag item `at` worn in `slot`, before requirements are checked.
    pub fn swapped(self: *const Inventory, at: usize, slot: Slot) Failure!Gear {
        if (at >= self.n) return error.Missing;
        const it = self.bag[at];
        if (!it.fits(slot)) return error.WrongSlot;
        return self.gear.wearing(it, slot);
    }

    pub fn preview(self: *const Inventory, at: usize, slot: Slot, base: attrs.Attrs) Failure!Gear {
        const after = try self.swapped(at, slot);
        if (!after.valid(base)) return error.Requirements;
        var n = self.n - 1;
        for (SLOTS) |s| n += @intFromBool(self.displaced(after, slot, s));
        if (n > BAG_MAX) return error.Full;
        return after;
    }

    /// Whether equipping into `slot`, giving `after`, sends what `s` wears to the bag.
    pub fn displaced(self: *const Inventory, after: Gear, slot: Slot, s: Slot) bool {
        const worn = self.gear.slots.get(s) orelse return false;
        return s == slot or !std.meta.eql(@as(?Item, worn), after.slots.get(s));
    }

    pub fn equip(self: *Inventory, at: usize, slot: Slot, base: attrs.Attrs) Failure!void {
        const after = try self.preview(at, slot, base);
        _ = self.remove(at);
        for (SLOTS) |s| if (self.displaced(after, slot, s)) std.debug.assert(self.add(self.gear.slots.get(s).?));
        self.gear = after;
    }

    pub fn unequip(self: *Inventory, slot: Slot, base: attrs.Attrs) Failure!void {
        const it = self.gear.slots.get(slot) orelse return error.Missing;
        if (self.n == BAG_MAX) return error.Full;
        var after = self.gear;
        after.slots.set(slot, null);
        if (!after.valid(base)) return error.Requirements;
        std.debug.assert(self.add(it));
        self.gear = after;
    }
};

pub const GROUND_MAX = 512;
pub const Drop = struct { item: Item, at: mathx.P, source: u16 = grid.NO_ONE };
pub const Supply = struct { kind: consumable.Kind, at: mathx.P, source: u16 = grid.NO_ONE };
pub const Coins = struct {
    at: mathx.P,
    amount: i32,

    pub fn large(c: Coins) bool {
        return c.amount > BARREL_GOLD.hi;
    }
};
pub const Ground = struct {
    drops: [GROUND_MAX]Drop = undefined,
    n: usize = 0,
    coins: [grid.CELLS]Coins = undefined,
    coin_n: usize = 0,
    supplies: [GROUND_MAX]Supply = undefined,
    supply_n: usize = 0,

    pub const COUNTED = .{ .{ "drops", "n" }, .{ "coins", "coin_n" }, .{ "supplies", "supply_n" } };

    pub fn laid(self: *const Ground) struct { []const Drop, []const Supply } {
        return .{ self.drops[0..self.n], self.supplies[0..self.supply_n] };
    }

    pub fn hasItems(self: *const Ground, at: mathx.P) bool {
        for (self.drops[0..self.n]) |drop| if (drop.at.eq(at)) return true;
        return false;
    }

    /// Items or consumables lie here, which a bag holds.
    pub fn bagged(self: *const Ground, at: mathx.P) bool {
        if (self.hasItems(at)) return true;
        for (self.supplies[0..self.supply_n]) |s| if (s.at.eq(at)) return true;
        return false;
    }

    pub fn addSupply(self: *Ground, s: Supply) bool {
        if (self.supply_n == self.supplies.len) return false;
        self.supplies[self.supply_n] = s;
        self.supply_n += 1;
        return true;
    }

    pub fn takeSupply(self: *Ground, i: usize, into: *Inventory) bool {
        if (i >= self.supply_n or !into.stock(self.supplies[i].kind)) return false;
        mathx.removeAt(Supply, &self.supplies, &self.supply_n, i, null);
        return true;
    }

    pub fn gold(self: *Ground, at: mathx.P, amount: i32) bool {
        std.debug.assert(grid.Level.inside(at) and amount > 0);
        for (self.coins[0..self.coin_n]) |*pile| if (pile.at.eq(at)) {
            pile.amount +|= amount;
            return true;
        };
        if (self.coin_n == self.coins.len) return false;
        self.coins[self.coin_n] = .{ .at = at, .amount = amount };
        self.coin_n += 1;
        return true;
    }

    pub fn collect(self: *Ground, at: mathx.P) i32 {
        for (self.coins[0..self.coin_n], 0..) |pile, i| if (pile.at.eq(at)) {
            return mathx.swapRemove(Coins, &self.coins, &self.coin_n, i).amount;
        };
        return 0;
    }

    pub fn add(self: *Ground, drop: Drop) bool {
        if (self.n == GROUND_MAX) return false;
        self.drops[self.n] = drop;
        self.n += 1;
        return true;
    }

    pub fn room(self: *const Ground, reserved: usize) bool {
        return self.n + reserved < self.drops.len;
    }

    pub fn take(self: *Ground, i: usize, into: *Inventory) bool {
        if (i >= self.n or !into.add(self.drops[i].item)) return false;
        mathx.removeAt(Drop, &self.drops, &self.n, i, null);
        return true;
    }
};

test "weapon weights cross melee and range while caster implements have no innate attack" {
    const heavy = [_]Kind{ .longsword, .mace, .greatsword, .crossbow, .greatclub, .axe };
    const light = [_]Kind{ .bow, .sling, .dagger, .sword, .handaxe };
    var gear = Gear{};
    const strong = attrs.Attrs.of(.{ .strength = 60, .dexterity = 10, .intelligence = 20 });
    for (heavy ++ light) |kind| {
        gear.slots.set(.right_hand, .{ .kind = kind });
        const s = spec(kind);
        const is_heavy = std.mem.indexOfScalar(Kind, &heavy, kind) != null;
        try std.testing.expectEqual(if (is_heavy) attrs.Style.heavy else .light, gear.scaling(s.attack));
        try std.testing.expectEqual(@as(i32, if (is_heavy) 60 else 10), strong.increase(gear.scaling(s.attack)));
        try std.testing.expect(s.damage != null);
        try std.testing.expectEqual(s.damage, gear.weapon(s.attack));
        try std.testing.expect(gear.weapon(if (s.attack == .ranged) .melee else .ranged) == null);
    }
    const implements = [_]Kind{ .wand, .staff };
    for (implements) |kind| {
        gear.slots.set(.right_hand, .{ .kind = kind });
        try std.testing.expect(spec(kind).damage == null);
        for (std.enums.values(attrs.Attack)) |attack| {
            try std.testing.expect(gear.weapon(attack) == null);
            try std.testing.expectEqual(attack.defaultStyle(), gear.scaling(attack));
        }
    }
    const base = attrs.Attrs.of(.{ .strength = 30, .dexterity = 30, .intelligence = 30 });
    const offhands = [_]Kind{ .tome, .orb, .buckler, .shield, .totem };
    for (offhands) |kind| {
        var inv = Inventory{};
        try std.testing.expect(inv.add(.{ .kind = .wand }));
        try inv.equip(0, .right_hand, base);
        try std.testing.expect(inv.add(.{ .kind = kind }));
        try inv.equip(0, .left_hand, base);
        try std.testing.expect(inv.gear.valid(base));
        try std.testing.expectEqual(Kind.wand, inv.gear.slots.get(.right_hand).?.kind);
        try std.testing.expect(spec(kind).damage == null);
        try std.testing.expect(inv.add(.{ .kind = .staff }));
        try inv.equip(0, .right_hand, base);
        try std.testing.expect(inv.gear.slots.get(.left_hand) == null);
        try std.testing.expectEqual(@as(usize, 2), inv.n);
    }
    var seen = std.EnumSet(Kind).initEmpty();
    var rng = mathx.Rng.init(0x17E);
    for (0..2000) |_| seen.insert(roll(&rng, 0).kind);
    try std.testing.expectEqual(LOOT.len, seen.count());
    std.debug.print("items: {d} heavy, {d} light, {d} non-attacking implements, {d} offhand swaps; all {d} kinds roll as loot\n", .{ heavy.len, light.len, implements.len, offhands.len, LOOT.len });
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
    var inv = Inventory{};
    var ground = Ground{};
    for (0..consumable.STACK_MAX) |_| try std.testing.expect(inv.stock(.bandage));
    try std.testing.expect(!inv.stock(.bandage));
    try std.testing.expect(ground.addSupply(.{ .kind = .bandage, .at = .{ .x = 3, .y = 3 } }));
    try std.testing.expect(!ground.takeSupply(0, &inv));
    try std.testing.expectEqual(@as(usize, 1), ground.supply_n);
    try std.testing.expectEqual(@as(usize, 0), inv.n);
    std.debug.print("consumables: {d} of 10000 foes drop one, all {d} kinds seen; a stack holds {d}\n", .{ dropped, seen.count(), consumable.STACK_MAX });
}

test "flasks start worn in their own slots, never roll as loot, and come off and back like gear" {
    var rng = mathx.Rng.init(0xF1A5);
    for (0..5000) |_| try std.testing.expect(roll(&rng, 0).kind.flaskOf() == null);
    const base = attrs.Attrs.of(.{ .strength = 10, .dexterity = 10, .intelligence = 10 });
    var inv = Inventory{ .gear = .flasks };
    try std.testing.expectEqualDeep(base, inv.gear.stats(base));
    try std.testing.expectEqualDeep(passives.Perks{}, inv.gear.perks(.{}));
    for (std.enums.values(flask.Kind), [_]flask.Kind{ .mana, .life }) |k, other| {
        try std.testing.expect(inv.gear.holds(k));
        try inv.unequip(.ofFlask(k), base);
        try std.testing.expect(!inv.gear.holds(k));
        try std.testing.expectEqual(Kind.ofFlask(k), inv.bag[inv.n - 1].kind);
        try std.testing.expectError(error.WrongSlot, inv.swapped(inv.n - 1, .ofFlask(other)));
        try std.testing.expectError(error.WrongSlot, inv.swapped(inv.n - 1, .belt));
        try inv.equip(inv.n - 1, .ofFlask(k), base);
        try std.testing.expect(inv.gear.holds(k));
    }
    try std.testing.expectEqual(@as(usize, 0), inv.n);
    std.debug.print("flasks: none in 5000 loot rolls; both worn from the start, each fits only its own slot and adds no stats\n", .{});
}

test "equipment swaps preserve both hands, reject self-funded requirements and keep dependent gear valid" {
    const base = attrs.Attrs.of(.{ .strength = 18, .dexterity = 20, .intelligence = 10 });
    var inv = Inventory{};
    try std.testing.expect(inv.add(.{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 2 }, null, null, null } }));
    try inv.equip(0, .left_ring, base);
    try std.testing.expect(inv.add(.{ .kind = .mail }));
    try inv.equip(0, .chest, base);
    try std.testing.expectError(error.Requirements, inv.unequip(.left_ring, base));
    try inv.unequip(.chest, base);
    try inv.unequip(.left_ring, base);
    var other = Inventory{};
    try std.testing.expect(other.add(.{ .kind = .mail, .mods = .{ .{ .kind = .strength, .value = 3 }, null, null, null } }));
    try std.testing.expectError(error.Requirements, other.equip(0, .chest, base));
    try std.testing.expectEqual(@as(usize, 1), other.n);
    try std.testing.expect(inv.add(.{ .kind = .sword }));
    try inv.equip(inv.n - 1, .right_hand, base);
    try std.testing.expect(inv.add(.{ .kind = .shield }));
    try inv.equip(inv.n - 1, .left_hand, base);
    const n = inv.n;
    try std.testing.expect(inv.add(.{ .kind = .bow }));
    try inv.equip(inv.n - 1, .right_hand, base);
    try std.testing.expectEqual(n + 2, inv.n);
    try std.testing.expect(inv.gear.slots.get(.left_hand) == null);
    try std.testing.expectEqual(Kind.bow, inv.gear.slots.get(.right_hand).?.kind);
    const strong = attrs.Attrs.of(.{ .strength = 20, .dexterity = 20, .intelligence = 10 });
    for ([_]Kind{ .axe, .greatclub, .greatsword }) |kind| {
        var hands = Inventory{};
        hands.gear.slots.set(.right_hand, .{ .kind = .sword });
        hands.gear.slots.set(.left_hand, .{ .kind = .shield });
        try std.testing.expect(hands.add(.{ .kind = kind }));
        const after = try hands.preview(0, .right_hand, strong);
        try std.testing.expect(after.slots.get(.left_hand) == null);
        try std.testing.expectEqual(@as(usize, 1), hands.n);
        try std.testing.expect(hands.gear.slots.get(.left_hand) != null);
        try hands.equip(0, .right_hand, strong);
        try std.testing.expectEqual(@as(usize, 2), hands.n);
        try std.testing.expectEqual(Kind.sword, hands.bag[1].kind);
        try std.testing.expectEqual(Kind.shield, hands.bag[0].kind);
        try std.testing.expectEqual(kind, hands.gear.slots.get(.right_hand).?.kind);
        try std.testing.expect(hands.gear.slots.get(.left_hand) == null);
        try hands.equip(0, .left_hand, strong);
        try std.testing.expect(hands.gear.slots.get(.right_hand) == null);
        try std.testing.expectEqual(kind, hands.bag[hands.n - 1].kind);
    }
    var rng = mathx.Rng.init(123);
    for (0..2000) |_| {
        const it = roll(&rng, 0);
        if (it.mods[1]) |b| try std.testing.expect(it.mods[0].?.kind != b.kind);
    }
    std.debug.print("equipment: bow plus all 3 great weapons occupy both hands; reverse swaps, dependency checks, atomic failures and 2000 bounded modifier rolls\n", .{});
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
                try std.testing.expectEqual(@as([AFFIXES_MAX]?Affix, @splat(null)), it.mods);
            }
        }
    }
    try std.testing.expect(gold >= 4500 and gold <= 5500);
    try std.testing.expect(plain >= 650 and plain <= 950);
    try std.testing.expect(magic >= 125 and magic <= 275);
    try std.testing.expect(rare >= 20 and rare <= 80);
    std.debug.print("foe loot over {d} kills: {d} gold, {d} plain, {d} magic, {d} rare items\n", .{ rolls, gold, plain, magic, rare });
}

test "magic affixes respect equipment eligibility prefix suffix and rolled bounds" {
    var rng = mathx.Rng.init(0xAFF1);
    var seen = std.EnumSet(Mod).initEmpty();
    var elements = std.EnumSet(damage.Element).initEmpty();
    var two: usize = 0;
    for (0..50000) |_| {
        const it = roll(&rng, 0);
        for (it.mods) |maybe| if (maybe) |m| {
            seen.insert(m.kind);
            try std.testing.expect(m.kind.allows(it.kind));
            for (AFFIXES) |a| if (a.kind == m.kind) try std.testing.expect(m.value >= a.lo and m.value <= a.hi);
            if (m.kind == .resistance) elements.insert(m.element);
        };
        if (it.rarity() == .magic) if (it.mods[1]) |second| {
            two += 1;
            try std.testing.expect(it.mods[0].?.kind.prefix() != second.kind.prefix());
        };
    }
    try std.testing.expectEqual(AFFIXES.len, seen.count());
    try std.testing.expectEqual(std.enums.values(damage.Element).len, elements.count());
    var name: [NAME_MAX]u8 = undefined;
    const gloves = Item{ .kind = .gloves, .mods = .{ .{ .kind = .strength, .value = 2 }, .{ .kind = .crit, .value = 3 }, null, null } };
    try std.testing.expectEqualStrings("Bear's Leather gloves of Precision", gloves.name(&name));
    try std.testing.expectEqualStrings("Leather gloves of Precision", (Item{ .kind = .gloves, .mods = .{ .{ .kind = .crit, .value = 3 }, null, null, null } }).name(&name));
    std.debug.print("magic affixes: 50000 rolls, all {d} modifiers and {d} elements; {d} legal prefix/suffix pairs and exact composed names checked\n", .{ seen.count(), elements.count(), two });
}

test "rare items roll distinct legal affixes and persistent combinatorial names" {
    var rng = mathx.Rng.init(0x2A2E);
    var counts = std.EnumArray(Rarity, usize).initFill(0);
    var bases = std.EnumSet(Kind).initEmpty();
    var firsts = std.EnumSet(RareName.First).initEmpty();
    var lasts = std.EnumSet(RareName.Last).initEmpty();
    var sizes = [_]usize{ 0, 0 };
    for (0..100000) |_| {
        const it = roll(&rng, 0);
        counts.getPtr(it.rarity()).* += 1;
        if (it.rarity() != .rare) continue;
        bases.insert(it.kind);
        firsts.insert(it.rare_name.?.first);
        lasts.insert(it.rare_name.?.last);
        var seen = std.EnumSet(Mod).initEmpty();
        var sides = [_]usize{ 0, 0 };
        for (it.mods) |maybe| if (maybe) |m| {
            try std.testing.expect(m.kind.allows(it.kind));
            try std.testing.expect(!seen.contains(m.kind));
            seen.insert(m.kind);
            sides[@intFromBool(m.kind.prefix())] += 1;
            for (AFFIXES) |a| if (a.kind == m.kind) try std.testing.expect(m.value >= a.lo and m.value <= a.hi);
        };
        try std.testing.expect(seen.count() >= 3 and seen.count() <= 4);
        try std.testing.expect(sides[0] <= 2 and sides[1] <= 2);
        sizes[seen.count() - 3] += 1;
    }
    try std.testing.expect(counts.get(.normal) > 74000 and counts.get(.normal) < 76000);
    try std.testing.expect(counts.get(.magic) > 19000 and counts.get(.magic) < 21000);
    try std.testing.expect(counts.get(.rare) > 4500 and counts.get(.rare) < 5500);
    try std.testing.expectEqual(LOOT.len, bases.count());
    try std.testing.expectEqual(std.enums.values(RareName.First).len, firsts.count());
    try std.testing.expectEqual(std.enums.values(RareName.Last).len, lasts.count());
    try std.testing.expect(sizes[0] > 0 and sizes[1] > 0);
    var name: [NAME_MAX]u8 = undefined;
    for ([_]RareName{ .{ .first = .Spine, .last = .Crusher }, .{ .first = .Void, .last = .Maw }, .{ .first = .Magus, .last = .Fold } }, [_][]const u8{ "Spine Crusher", "Void Maw", "Magus Fold" }) |rare, expected| {
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
    var inv = Inventory{};
    try std.testing.expect(inv.add(rare));
    try inv.equip(0, .right_hand, base);
    try std.testing.expectEqualDeep(rare, inv.gear.slots.get(.right_hand).?);
    try inv.unequip(.right_hand, base);
    try std.testing.expectEqualDeep(rare, inv.bag[0]);
    std.debug.print("rare loot: 100000 drops, {d} normal / {d} magic / {d} rare; all {d} bases, {d} names, both mod counts and four-mod equipment effects checked\n", .{ counts.get(.normal), counts.get(.magic), counts.get(.rare), bases.count(), firsts.count() * lasts.count() });
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
    std.debug.print("rolled item effects: weapon-scoped damage and penetration, additive crit, elemental defense and two recovery consumers checked\n", .{});
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
        std.debug.print("Spoils rarity +{d}%: {d}/{d} improved items, {d} rare over {d} kills\n", .{ rarity, magic, drops, rare, samples });
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

test "every equipment base rolls all three rarities and keeps its innate separate from affixes" {
    var rng = mathx.Rng.init(0xBA5E);
    var white = std.EnumSet(Kind).initEmpty();
    var blue = std.EnumSet(Kind).initEmpty();
    var yellow = std.EnumSet(Kind).initEmpty();
    for (0..20000) |_| {
        const it = roll(&rng, 0);
        switch (it.rarity()) {
            .normal => white.insert(it.kind),
            .magic => blue.insert(it.kind),
            .rare => yellow.insert(it.kind),
        }
    }
    try std.testing.expectEqual(LOOT.len, white.count());
    try std.testing.expectEqual(LOOT.len, blue.count());
    try std.testing.expectEqual(LOOT.len, yellow.count());
    const base = attrs.Attrs.of(.{ .strength = 30, .dexterity = 30, .intelligence = 30 });
    for (LOOT) |kind| {
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
    std.debug.print("bases: all {d} roll in all three rarities over 20000 drops; innate/affix separation, scoped crit and recovery perks checked\n", .{LOOT.len});
}

test "ground gold accommodates every cell and full pickup leaves its item intact" {
    var ground = Ground{};
    var inv = Inventory{};
    for (0..grid.CELLS) |i| try std.testing.expect(ground.gold(grid.Level.of(i), 1));
    try std.testing.expectEqual(grid.CELLS, ground.coin_n);
    try std.testing.expect(ground.gold(.{ .x = 1, .y = 1 }, 7));
    try std.testing.expectEqual(@as(i32, 8), ground.collect(.{ .x = 1, .y = 1 }));
    try std.testing.expect(ground.add(.{ .item = .{ .kind = .cap }, .at = .{ .x = 1, .y = 1 } }));
    for (0..BAG_MAX) |_| try std.testing.expect(inv.add(.{ .kind = .ring }));
    try std.testing.expect(!ground.take(0, &inv));
    try std.testing.expectEqual(@as(usize, 1), ground.n);
    std.debug.print("ground: {d} gold cells, merged piles and full pickup preservation checked\n", .{grid.CELLS});
}

fn expectInventoryUnchanged(before: *const Inventory, after: *const Inventory) !void {
    try std.testing.expectEqual(before.n, after.n);
    try std.testing.expectEqualDeep(before.gear, after.gear);
    try std.testing.expectEqualSlices(Item, before.bag[0..before.n], after.bag[0..after.n]);
}

test "equipment failures preserve every carried item and the complete loadout" {
    const base = attrs.Attrs.of(.{ .strength = 18, .dexterity = 20, .intelligence = 10 });
    var inv = Inventory{};
    inv.gear.slots.set(.right_hand, .{ .kind = .sword });
    try std.testing.expect(inv.add(.{ .kind = .mail, .mods = .{ .{ .kind = .strength, .value = 3 }, null, null, null } }));
    const before = inv;
    for ([_]usize{ inv.n, BAG_MAX, std.math.maxInt(usize) }) |missing| {
        try std.testing.expectError(error.Missing, inv.preview(missing, .chest, base));
        try std.testing.expectError(error.Missing, inv.equip(missing, .chest, base));
        try expectInventoryUnchanged(&before, &inv);
    }
    try std.testing.expectError(error.WrongSlot, inv.equip(0, .helm, base));
    try expectInventoryUnchanged(&before, &inv);
    try std.testing.expectError(error.Requirements, inv.preview(0, .chest, base));
    try std.testing.expectError(error.Requirements, inv.equip(0, .chest, base));
    try expectInventoryUnchanged(&before, &inv);
    try std.testing.expectError(error.Missing, inv.unequip(.left_ring, base));
    try expectInventoryUnchanged(&before, &inv);

    inv.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 2 }, null, null, null } });
    inv.gear.slots.set(.chest, .{ .kind = .mail });
    try std.testing.expect(inv.gear.valid(base));
    const dependent = inv;
    try std.testing.expectError(error.Requirements, inv.unequip(.left_ring, base));
    try expectInventoryUnchanged(&dependent, &inv);
    try std.testing.expect(inv.add(.{ .kind = .ring }));
    const replacement = inv;
    try std.testing.expectError(error.Requirements, inv.equip(1, .left_ring, base));
    try expectInventoryUnchanged(&replacement, &inv);
    std.debug.print("equipment atomicity: missing indices, wrong slot, self-funded requirements and 2 dependent-gear failures preserve all items\n", .{});
}

test "equipment swaps account for exact bag capacity and both displaced hands" {
    const base = attrs.Attrs.of(.{ .strength = 30, .dexterity = 30, .intelligence = 30 });
    var inv = Inventory{};
    inv.gear.slots.set(.right_hand, .{ .kind = .sword });
    inv.gear.slots.set(.left_hand, .{ .kind = .shield });
    try std.testing.expect(inv.add(.{ .kind = .greatsword }));
    for (1..BAG_MAX) |_| try std.testing.expect(inv.add(.{ .kind = .ring }));
    const full = inv;
    try std.testing.expectError(error.Full, inv.preview(0, .right_hand, base));
    try std.testing.expectError(error.Full, inv.equip(0, .right_hand, base));
    try expectInventoryUnchanged(&full, &inv);
    try std.testing.expectError(error.Full, inv.unequip(.left_hand, base));
    try expectInventoryUnchanged(&full, &inv);
    try std.testing.expect(!inv.add(.{ .kind = .cap }));
    try expectInventoryUnchanged(&full, &inv);

    _ = inv.remove(inv.n - 1);
    const before_preview = inv;
    const preview = try inv.preview(0, .right_hand, base);
    try expectInventoryUnchanged(&before_preview, &inv);
    try inv.equip(0, .right_hand, base);
    try std.testing.expectEqualDeep(preview, inv.gear);
    try std.testing.expectEqual(@as(usize, BAG_MAX), inv.n);
    try std.testing.expectEqual(Kind.shield, inv.bag[BAG_MAX - 2].kind);
    try std.testing.expectEqual(Kind.sword, inv.bag[BAG_MAX - 1].kind);
    for (inv.bag[0 .. BAG_MAX - 2]) |it| try std.testing.expectEqual(Kind.ring, it.kind);

    try inv.equip(BAG_MAX - 2, .left_hand, base);
    try std.testing.expectEqual(@as(usize, BAG_MAX), inv.n);
    try std.testing.expect(inv.gear.slots.get(.right_hand) == null);
    try std.testing.expectEqual(Kind.shield, inv.gear.slots.get(.left_hand).?.kind);
    try std.testing.expectEqual(Kind.greatsword, inv.bag[BAG_MAX - 1].kind);
    _ = inv.remove(0);
    try inv.unequip(.left_hand, base);
    try std.testing.expectEqual(@as(usize, BAG_MAX), inv.n);
    try std.testing.expectEqual(Kind.shield, inv.bag[BAG_MAX - 1].kind);
    try std.testing.expect(inv.gear.slots.get(.left_hand) == null);
    std.debug.print("equipment capacity: {d}-item rejection, exact-fit two-hand swap, reverse swap and exact-fit unequip checked\n", .{BAG_MAX});
}

test "ground pickups preserve order and source identity and never collect another cell's gold" {
    const here = mathx.P{ .x = 5, .y = 5 };
    const there = mathx.P{ .x = 6, .y = 5 };
    var ground = Ground{};
    var inv = Inventory{};
    const drops = [_]Drop{
        .{ .item = .{ .kind = .cap }, .at = here, .source = 2 },
        .{ .item = .{ .kind = .ring }, .at = there, .source = 3 },
        .{ .item = .{ .kind = .boots }, .at = here, .source = 4 },
    };
    for (drops) |drop| try std.testing.expect(ground.add(drop));
    try std.testing.expect(ground.gold(here, 7));
    try std.testing.expect(ground.gold(there, 11));
    for ([_]usize{ ground.n, GROUND_MAX, std.math.maxInt(usize) }) |missing| try std.testing.expect(!ground.take(missing, &inv));
    try std.testing.expectEqual(@as(usize, 0), inv.n);
    try std.testing.expectEqualSlices(Drop, &drops, ground.drops[0..ground.n]);
    try std.testing.expect(ground.take(1, &inv));
    try std.testing.expectEqual(Kind.ring, inv.bag[0].kind);
    try std.testing.expectEqualSlices(Drop, &.{ drops[0], drops[2] }, ground.drops[0..ground.n]);
    try std.testing.expect(!ground.hasItems(there));
    try std.testing.expect(ground.hasItems(here));
    try std.testing.expectEqual(@as(usize, 2), ground.coin_n);
    try std.testing.expectEqual(@as(i32, 7), ground.collect(here));
    try std.testing.expectEqual(@as(i32, 0), ground.collect(here));
    try std.testing.expectEqual(@as(usize, 1), ground.coin_n);
    try std.testing.expectEqualDeep(Coins{ .at = there, .amount = 11 }, ground.coins[0]);
    try std.testing.expect(ground.gold(there, std.math.maxInt(i32)));
    try std.testing.expectEqual(std.math.maxInt(i32), ground.collect(there));
    try std.testing.expectEqual(@as(usize, 0), ground.coin_n);
    try std.testing.expectEqualSlices(Drop, &.{ drops[0], drops[2] }, ground.drops[0..ground.n]);
    std.debug.print("ground transactions: 3 invalid indices, ordered pickup with source identity, isolated gold and saturated merge checked\n", .{});
}
