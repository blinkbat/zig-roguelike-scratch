const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const passives = @import("passives.zig");
const bleeding = @import("bleeding.zig");
const flask = @import("flask.zig");
const wording = @import("../core/wording.zig");
const resilience = @import("resilience.zig");
const affixes = @import("affixes.zig");

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
            inline else => |t| @field(Kind, @tagName(t) ++ "_flask"),
        };
    }

    pub fn flaskOf(k: Kind) ?flask.Kind {
        const innate = spec(k).innate orelse return null;
        return if (innate == .flask) innate.flask else null;
    }
};

pub const ON_HIT_FMT = "{d}% chance to {s} on hit";

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
        switch (affixes.imbued(e)) {
            inline .burn, .chill, .shock => |t| @field(self, @tagName(t)) += n,
            else => unreachable,
        }
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

pub fn baseName(k: Kind, buf: []u8) [:0]const u8 {
    const base = baseOf(k);
    return wording.recased(buf, std.fmt.bufPrintZ(buf, "{s}", .{base}) catch base, .title);
}

pub fn baseOf(k: Kind) [:0]const u8 {
    return wording.namedOr(k, spec(k).name);
}
