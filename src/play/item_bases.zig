const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const passives = @import("passives.zig");
const bleeding = @import("bleeding.zig");
const flask = @import("flask.zig");
const wording = @import("../core/wording.zig");
const resilience = @import("resilience.zig");
const affixes = @import("affixes.zig");
const hero = @import("hero.zig");

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
            inline else => |t| @field(Slot, @tagName(t) ++ "_flask"),
        };
    }

    pub fn armour(s: Slot) bool {
        return switch (s) {
            .helm, .chest, .belt, .gloves, .boots => true,
            .left_hand, .right_hand, .left_ring, .right_ring, .amulet, .life_flask, .mana_flask => false,
        };
    }
};

pub const SLOTS = std.enums.values(Slot);

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
    quiver,
    ember_quiver,
    frost_quiver,
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
    small_key,

    pub fn slots(k: Kind) []const Slot {
        return spec(k).slots;
    }

    pub fn equippable(k: Kind) bool {
        return k.slots().len > 0;
    }

    pub fn fits(k: Kind, slot: Slot) bool {
        return std.mem.indexOfScalar(Slot, k.slots(), slot) != null;
    }

    pub fn ofFlask(k: flask.Kind) Kind {
        return switch (k) {
            inline else => |t| @field(Kind, @tagName(t) ++ "_flask"),
        };
    }

    pub fn blocks(k: Kind) bool {
        return spec(k).block > 0;
    }

    pub fn flaskOf(k: Kind) ?flask.Kind {
        const innate = spec(k).innate orelse return null;
        return if (innate == .flask) innate.flask else null;
    }

    pub fn usableBy(k: Kind, c: hero.Class) bool {
        return spec(k).classes.contains(c);
    }
};

pub const Classes = std.EnumSet(hero.Class);
const ARCHER: Classes = .initOne(.archer);
const WIZARD: Classes = .initOne(.wizard);
const KNIGHT: Classes = .initOne(.knight);
const NOBODY: Classes = .initEmpty();
const LIGHT = attrs.only(.light);
const HEAVY = attrs.only(.heavy);

fn both(a: attrs.Style, b: attrs.Style) attrs.Scaling {
    return .initMany(&.{ a, b });
}

pub const ON_HIT_FMT = "{d}% chance to {s} on hit";
pub const BLOCK_CHANCE_FMT = "{d}% chance to block";
pub const BLOCK_FMT = "+" ++ BLOCK_CHANCE_FMT;

pub const WeaponEffect = struct {
    bleed: u32 = 0,
    bleed_damage: i32 = bleeding.STILL,
    stun: u32 = 0,
    burn: u32 = 0,
    chill: u32 = 0,
    shock: u32 = 0,
    penetration: i32 = 0,

    pub fn chance(self: WeaponEffect, k: resilience.Kind) u32 {
        return switch (k) {
            inline else => |t| if (@hasField(WeaponEffect, @tagName(t))) @field(self, @tagName(t)) else 0,
        };
    }

    pub fn imbue(self: *WeaponEffect, e: damage.Element, n: u32) void {
        switch (e) {
            inline else => |el| @field(self, @tagName(affixes.imbued(el))) += n,
        }
    }
};
comptime {
    for (std.meta.fieldNames(WeaponEffect)) |f| {
        if (!std.mem.eql(u8, f, "bleed_damage") and !std.mem.eql(u8, f, "penetration")) _ = @field(resilience.Kind, f);
    }
}

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

    pub fn apply(self: Innate, a: *attrs.Attrs) void {
        switch (self) {
            .grant => |g| g.apply(a),
            .weapon_crit => |n| a.weapon_crit_bonus += n,
            .spell_crit => |n| a.spell_crit_bonus += n,
            .physical_damage => |n| a.physical_bonus += n,
            .element => |e| a.element_bonus.getPtr(e.kind).* += e.percent,
            .bleed, .stun, .penetration, .flask => {},
        }
    }

    pub fn effect(self: Innate) WeaponEffect {
        return switch (self) {
            .bleed => |b| .{ .bleed = b.chance, .bleed_damage = b.damage },
            .stun => |n| .{ .stun = n },
            .penetration => |n| .{ .penetration = n },
            .grant, .weapon_crit, .spell_crit, .physical_damage, .element, .flask => .{},
        };
    }

    pub fn write(self: Innate, w: anytype) void {
        switch (self) {
            .grant => |g| g.write(w),
            .weapon_crit => |n| w.print("+{d}% " ++ attrs.WEAPON_CRIT_LABEL, .{n}) catch {},
            .spell_crit => |n| w.print("+{d}% " ++ attrs.SPELL_CRIT_LABEL, .{n}) catch {},
            .physical_damage => |n| w.print("+{d}% " ++ attrs.PHYSICAL_LABEL, .{n}) catch {},
            .element => |e| w.print("+{d}% {s} damage", .{ e.percent, wording.word(e.kind) }) catch {},
            .bleed => |b| w.print(ON_HIT_FMT, .{ b.chance, wording.word(resilience.Kind.bleed) }) catch {},
            .stun => |n| w.print(ON_HIT_FMT, .{ n, wording.word(resilience.Kind.stun) }) catch {},
            .penetration => |n| w.print("Ignore {d}% physical reduction", .{n}) catch {},
            .flask => |k| w.writeAll(flask.effect(k)) catch {},
        }
    }
};

pub const Spec = struct {
    name: [:0]const u8,
    slots: []const Slot,
    needs: attrs.Needs = .{},
    damage: ?damage.Base = null,
    /// What its attack scales with, or for a caster its spells; null takes the attack's own.
    scales: ?attrs.Scaling = null,
    attack: attrs.Attack = .melee,
    two_handed: bool = false,
    /// A spellcaster's implement, which rolls spell modifiers.
    caster: bool = false,
    /// An offhand worn beside a two-handed ranged weapon.
    quiver: bool = false,
    armour: i16 = 0,
    block: i16 = 0,
    innate: ?Innate = null,
    classes: Classes = .initFull(),

    pub fn scaling(s: Spec) attrs.Scaling {
        return s.scales orelse if (s.caster) attrs.only(.spell) else s.attack.defaultScaling();
    }

    pub fn scalingFor(s: Spec, attack: attrs.Attack) ?attrs.Scaling {
        return if ((s.damage != null and s.attack == attack) or (attack == .spell and s.caster)) s.scaling() else null;
    }
};

const SPECS = std.EnumArray(Kind, Spec).init(.{
    .sword = .{ .name = "Short sword", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 3, .hi = 4 }, .scales = LIGHT, .classes = NOBODY },
    .axe = .{ .name = "Great axe", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 5, .hi = 9 }, .two_handed = true, .innate = .{ .bleed = .{ .chance = 30, .damage = 2 } }, .classes = KNIGHT },
    .bow = .{ .name = "Short bow", .slots = &.{.right_hand}, .needs = .{ .dexterity = 12 }, .damage = .{ .lo = 2, .hi = 5 }, .attack = .ranged, .two_handed = true, .classes = ARCHER },
    .staff = .{ .name = "Oak staff", .slots = &.{.right_hand}, .needs = .{ .intelligence = 16, .strength = 12 }, .two_handed = true, .caster = true, .innate = Innate.stat(.spell_damage, 30), .scales = both(.spell, .heavy), .classes = WIZARD },
    .longsword = .{ .name = "Longsword", .slots = &.{.right_hand}, .needs = .{ .strength = 12, .dexterity = 12 }, .damage = .{ .lo = 4, .hi = 7 }, .scales = both(.heavy, .light), .classes = KNIGHT },
    .mace = .{ .name = "Mace", .slots = &.{.right_hand}, .needs = .{ .strength = 12, .intelligence = 12 }, .damage = .{ .lo = 3, .hi = 6 }, .innate = .{ .stun = 15 }, .scales = both(.heavy, .spell), .classes = KNIGHT },
    .greatsword = .{ .name = "Greatsword", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 7, .hi = 12 }, .two_handed = true, .classes = KNIGHT },
    .crossbow = .{ .name = "Crossbow", .slots = &.{.right_hand}, .needs = .{ .strength = 12 }, .damage = .{ .lo = 3, .hi = 7 }, .attack = .ranged, .two_handed = true, .innate = .{ .penetration = 20 }, .scales = HEAVY, .classes = ARCHER },
    .greatclub = .{ .name = "Greatclub", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 5, .hi = 9 }, .two_handed = true, .innate = .{ .stun = 25 }, .classes = KNIGHT },
    .sling = .{ .name = "Sling", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 1, .hi = 4 }, .attack = .ranged, .classes = NOBODY },
    .dagger = .{ .name = "Dagger", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 1, .hi = 4 }, .scales = LIGHT, .innate = .{ .weapon_crit = 15 }, .classes = NOBODY },
    .handaxe = .{ .name = "Handaxe", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 2, .hi = 3 }, .scales = LIGHT, .innate = .{ .bleed = .{ .chance = 25 } }, .classes = NOBODY },
    .wand = .{ .name = "Wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 12 }, .caster = true, .innate = .{ .spell_crit = 8 }, .classes = WIZARD },
    .tome = .{ .name = "Tome", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .caster = true, .innate = Innate.stat(.mana, 3), .classes = WIZARD },
    .orb = .{ .name = "Orb", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .caster = true, .innate = .{ .spell_crit = 6 }, .classes = WIZARD },
    .buckler = .{ .name = "Buckler", .slots = &.{.left_hand}, .needs = .{ .dexterity = 10 }, .armour = 2, .block = 10, .innate = Innate.stat(.dodge, 4), .classes = NOBODY },
    .totem = .{ .name = "Totem", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .innate = Innate.stat(.life_on_kill, 1), .classes = NOBODY },
    .shield = .{ .name = "Wooden shield", .slots = &.{.left_hand}, .needs = .{ .strength = 10 }, .armour = 6, .block = 20, .classes = KNIGHT },
    .cap = .{ .name = "Leather cap", .slots = &.{.helm}, .armour = 2 },
    .helmet = .{ .name = "Iron helm", .slots = &.{.helm}, .needs = .{ .strength = 16 }, .armour = 4, .innate = Innate.stat(.life, 3) },
    .leather = .{ .name = "Leather armour", .slots = &.{.chest}, .needs = .{ .strength = 10 }, .armour = 5, .innate = Innate.stat(.dodge, 5) },
    .mail = .{ .name = "Mail armour", .slots = &.{.chest}, .needs = .{ .strength = 20 }, .armour = 10 },
    .belt = .{ .name = "Leather belt", .slots = &.{.belt}, .armour = 1 },
    .gloves = .{ .name = "Leather gloves", .slots = &.{.gloves}, .armour = 1, .innate = Innate.stat(.light_damage, 10) },
    .boots = .{ .name = "Soft boots", .slots = &.{.boots}, .armour = 1, .innate = Innate.stat(.dodge, 3) },
    .ring = .{ .name = "Copper ring", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.life, 1) },
    .amulet = .{ .name = "Bronze amulet", .slots = &.{.amulet}, .innate = Innate.stat(.life, 2) },
    .hunting_bow = .{ .name = "Hunting bow", .slots = &.{.right_hand}, .needs = .{ .dexterity = 16 }, .damage = .{ .lo = 2, .hi = 4 }, .attack = .ranged, .two_handed = true, .innate = .{ .weapon_crit = 12 }, .classes = ARCHER },
    .war_bow = .{ .name = "War bow", .slots = &.{.right_hand}, .needs = .{ .dexterity = 20, .strength = 16 }, .damage = .{ .lo = 3, .hi = 6 }, .scales = both(.light, .heavy), .attack = .ranged, .two_handed = true, .classes = ARCHER },
    .quiver = .{ .name = "Quiver", .slots = &.{.left_hand}, .needs = .{ .dexterity = 10 }, .quiver = true, .innate = .{ .physical_damage = 10 }, .classes = ARCHER },
    .ember_quiver = .{ .name = "Ember quiver", .slots = &.{.left_hand}, .needs = .{ .dexterity = 14 }, .quiver = true, .innate = .{ .element = .{ .kind = .fire, .percent = 20 } }, .classes = ARCHER },
    .frost_quiver = .{ .name = "Frost quiver", .slots = &.{.left_hand}, .needs = .{ .dexterity = 14 }, .quiver = true, .innate = .{ .element = .{ .kind = .cold, .percent = 20 } }, .classes = ARCHER },
    .ash_wand = .{ .name = "Ash wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14 }, .caster = true, .innate = .{ .element = .{ .kind = .fire, .percent = 25 } }, .classes = WIZARD },
    .rime_wand = .{ .name = "Rime wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14 }, .caster = true, .innate = .{ .element = .{ .kind = .cold, .percent = 25 } }, .classes = WIZARD },
    .storm_wand = .{ .name = "Storm wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14, .dexterity = 12 }, .caster = true, .innate = .{ .element = .{ .kind = .lightning, .percent = 25 } }, .scales = both(.spell, .light), .classes = WIZARD },
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
    .small_key = .{ .name = "Small Key", .slots = &.{} },
});

pub fn spec(k: Kind) Spec {
    return SPECS.getPtrConst(k).*;
}

pub fn baseOf(k: Kind) [:0]const u8 {
    return wording.namedOr(k, spec(k).name);
}
