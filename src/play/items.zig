const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const passives = @import("passives.zig");
const bleeding = @import("bleeding.zig");

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
        };
    }
};
pub const SLOTS = std.enums.values(Slot);
const Mod = attrs.Bonus;
/// The modifiers loot rolls, in roll order, with their value ranges.
const AFFIXES = [_]struct { kind: Mod, lo: i32, hi: i32 }{
    .{ .kind = .life, .lo = 2, .hi = 6 },
    .{ .kind = .mana, .lo = 1, .hi = 3 },
    .{ .kind = .strength, .lo = 1, .hi = 3 },
    .{ .kind = .dexterity, .lo = 1, .hi = 3 },
    .{ .kind = .intelligence, .lo = 1, .hi = 3 },
};
pub const MODS = blk: {
    var out: [AFFIXES.len]Mod = undefined;
    for (AFFIXES, &out) |a, *m| m.* = a.kind;
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

    pub fn slots(k: Kind) []const Slot {
        return spec(k).slots;
    }
};
const KINDS = std.enums.values(Kind);
/// Percent of slain foes that drop an item.
pub const DROP_PERCENT = 10;
pub const FOE_GOLD_PERCENT = 50;
pub const MAGIC_PERCENT = 20;
/// A gold drop's range, both ends inclusive.
pub const Gold = struct {
    lo: i32,
    hi: i32,

    pub fn roll(g: Gold, rng: *mathx.Rng) i32 {
        return rng.range(g.lo, g.hi);
    }
};
pub const BARREL_GOLD = Gold{ .lo = 3, .hi = 12 };
pub const CHEST_GOLD = Gold{ .lo = 18, .hi = 36 };
pub const FOE_GOLD = Gold{ .lo = 1, .hi = 6 };
pub const Affix = struct { kind: Mod, value: i16 };
pub const AFFIXES_MAX = 2;
pub const WeaponEffect = struct {
    bleed: u32 = 0,
    bleed_damage: i32 = bleeding.STILL,
    stun: u32 = 0,
    penetration: i32 = 0,
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
            .bleed, .stun, .penetration => {},
        }
    }

    pub fn write(self: Innate, w: anytype) void {
        switch (self) {
            .grant => |g| g.write(w),
            .weapon_crit => |n| w.print("+{d}% " ++ attrs.WEAPON_CRIT_LABEL, .{n}) catch {},
            .spell_crit => |n| w.print("+{d}% " ++ attrs.SPELL_CRIT_LABEL, .{n}) catch {},
            .physical_damage => |n| w.print("+{d}% " ++ attrs.PHYSICAL_LABEL, .{n}) catch {},
            .element => |e| w.print("+{d}% {s} damage", .{ e.percent, @tagName(e.kind) }) catch {},
            .bleed => |b| w.print("{d}% chance to bleed on hit", .{b.chance}) catch {},
            .stun => |n| w.print("{d}% chance to stun on hit", .{n}) catch {},
            .penetration => |n| w.print("Ignore {d}% physical reduction", .{n}) catch {},
        }
    }
};

pub const Spec = struct {
    name: [:0]const u8,
    flavor: [:0]const u8,
    /// Where it may be worn.
    slots: []const Slot,
    needs: attrs.Needs = .{},
    damage: ?damage.Base = null,
    style: attrs.Style = .heavy,
    attack: attrs.Attack = .melee,
    two_handed: bool = false,
    armour: i16 = 0,
    innate: ?Innate = null,
};
const SPECS = std.EnumArray(Kind, Spec).init(.{
    .sword = .{ .name = "Short sword", .flavor = "Quick answers in tight tunnels.", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 3, .hi = 4 }, .style = .light },
    .axe = .{ .name = "Great axe", .flavor = "Built to fell trees. Not picky.", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 3, .hi = 6 }, .two_handed = true, .innate = .{ .bleed = .{ .chance = 30, .damage = 2 } } },
    .bow = .{ .name = "Short bow", .flavor = "Yew, gut string, a steady nerve.", .slots = &.{.right_hand}, .needs = .{ .dexterity = 12 }, .damage = .{ .lo = 2, .hi = 5 }, .style = .light, .attack = .ranged, .two_handed = true },
    .staff = .{ .name = "Oak staff", .flavor = "Old wood remembers its spells.", .slots = &.{.right_hand}, .needs = .{ .intelligence = 16 }, .two_handed = true, .innate = Innate.stat(.spell_damage, 30) },
    .longsword = .{ .name = "Longsword", .flavor = "A knight's blade, well notched.", .slots = &.{.right_hand}, .needs = .{ .strength = 10 }, .damage = .{ .lo = 3, .hi = 5 } },
    .mace = .{ .name = "Mace", .flavor = "Armour only makes it louder.", .slots = &.{.right_hand}, .needs = .{ .strength = 10 }, .damage = .{ .lo = 2, .hi = 4 }, .innate = .{ .stun = 15 } },
    .greatsword = .{ .name = "Greatsword", .flavor = "Rarely needs drawing twice.", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 5, .hi = 8 }, .two_handed = true },
    .crossbow = .{ .name = "Crossbow", .flavor = "Slow to wind, quick to end it.", .slots = &.{.right_hand}, .needs = .{ .strength = 12 }, .damage = .{ .lo = 2, .hi = 5 }, .attack = .ranged, .two_handed = true, .innate = .{ .penetration = 20 } },
    .greatclub = .{ .name = "Greatclub", .flavor = "The oldest weapon. Still works.", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 3, .hi = 6 }, .two_handed = true, .innate = .{ .stun = 25 } },
    .sling = .{ .name = "Sling", .flavor = "A stone, a strap, a grudge.", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 1, .hi = 4 }, .style = .light, .attack = .ranged },
    .dagger = .{ .name = "Dagger", .flavor = "For close work, closer secrets.", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 1, .hi = 4 }, .style = .light, .innate = .{ .weapon_crit = 15 } },
    .handaxe = .{ .name = "Handaxe", .flavor = "Splits kindling and skulls.", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 2, .hi = 3 }, .style = .light, .innate = .{ .bleed = .{ .chance = 25 } } },
    .wand = .{ .name = "Wand", .flavor = "Its tip stays warm, remembering.", .slots = &.{.right_hand}, .needs = .{ .intelligence = 12 }, .innate = .{ .spell_crit = 8 } },
    .tome = .{ .name = "Tome", .flavor = "Its scorched pages whisper.", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .innate = Innate.stat(.mana, 3) },
    .orb = .{ .name = "Orb", .flavor = "Something stirs in the glass.", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .innate = .{ .spell_crit = 6 } },
    .buckler = .{ .name = "Buckler", .flavor = "Small, until it saves your life.", .slots = &.{.left_hand}, .needs = .{ .dexterity = 10 }, .armour = 2, .innate = Innate.stat(.dodge, 4) },
    .totem = .{ .name = "Totem", .flavor = "Carved faces watch the dark.", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 }, .innate = Innate.stat(.life_on_kill, 1) },
    .shield = .{ .name = "Wooden shield", .flavor = "Splintered at the rim. Standing.", .slots = &.{.left_hand}, .needs = .{ .strength = 10 }, .armour = 6 },
    .cap = .{ .name = "Leather cap", .flavor = "Better than nothing. Barely.", .slots = &.{.helm}, .armour = 2 },
    .helmet = .{ .name = "Iron helm", .flavor = "Cold iron and a narrow view.", .slots = &.{.helm}, .needs = .{ .strength = 16 }, .armour = 4, .innate = Innate.stat(.life, 3) },
    .leather = .{ .name = "Leather armour", .flavor = "Stiff, scarred, smells of rain.", .slots = &.{.chest}, .needs = .{ .strength = 10 }, .armour = 5, .innate = Innate.stat(.dodge, 5) },
    .mail = .{ .name = "Mail armour", .flavor = "Each ring a vow to stay alive.", .slots = &.{.chest}, .needs = .{ .strength = 20 }, .armour = 10 },
    .belt = .{ .name = "Leather belt", .flavor = "Holds up trousers, and hope.", .slots = &.{.belt}, .armour = 1 },
    .gloves = .{ .name = "Leather gloves", .flavor = "Worn thin at the knuckles.", .slots = &.{.gloves}, .armour = 1, .innate = Innate.stat(.light_damage, 10) },
    .boots = .{ .name = "Soft boots", .flavor = "They have walked out of worse.", .slots = &.{.boots}, .armour = 1, .innate = Innate.stat(.dodge, 3) },
    .ring = .{ .name = "Copper ring", .flavor = "Green at the edges, warm inside.", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.life, 1) },
    .amulet = .{ .name = "Bronze amulet", .flavor = "Wards off the dark. Mostly.", .slots = &.{.amulet}, .innate = Innate.stat(.life, 2) },
    .hunting_bow = .{ .name = "Hunting bow", .flavor = "A notch for every clean shot.", .slots = &.{.right_hand}, .needs = .{ .dexterity = 16 }, .damage = .{ .lo = 2, .hi = 4 }, .style = .light, .attack = .ranged, .two_handed = true, .innate = .{ .weapon_crit = 12 } },
    .war_bow = .{ .name = "War bow", .flavor = "The string pulls back.", .slots = &.{.right_hand}, .needs = .{ .dexterity = 22 }, .damage = .{ .lo = 3, .hi = 6 }, .style = .light, .attack = .ranged, .two_handed = true },
    .ash_wand = .{ .name = "Ash wand", .flavor = "Warm even in the rain.", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14 }, .innate = .{ .element = .{ .kind = .fire, .percent = 25 } } },
    .rime_wand = .{ .name = "Rime wand", .flavor = "Frost gathers round the grip.", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14 }, .innate = .{ .element = .{ .kind = .cold, .percent = 25 } } },
    .storm_wand = .{ .name = "Storm wand", .flavor = "The hairs rise before the rain.", .slots = &.{.right_hand}, .needs = .{ .intelligence = 14 }, .innate = .{ .element = .{ .kind = .lightning, .percent = 25 } } },
    .plate = .{ .name = "Plate armour", .flavor = "A door that walks.", .slots = &.{.chest}, .needs = .{ .strength = 24 }, .armour = 15 },
    .robes = .{ .name = "Robes", .flavor = "Thin cloth, deep pockets.", .slots = &.{.chest}, .needs = .{ .intelligence = 12 }, .armour = 1, .innate = Innate.stat(.mana, 4) },
    .hood = .{ .name = "Hunter's hood", .flavor = "A narrow shadow over the eyes.", .slots = &.{.helm}, .needs = .{ .dexterity = 14 }, .armour = 1, .innate = Innate.stat(.crit, 5) },
    .circlet = .{ .name = "Circlet", .flavor = "Cool silver, clear thoughts.", .slots = &.{.helm}, .needs = .{ .intelligence = 14 }, .innate = Innate.stat(.mana_regen, 1) },
    .gauntlets = .{ .name = "Gauntlets", .flavor = "Iron closes round the hilt.", .slots = &.{.gloves}, .needs = .{ .strength = 14 }, .armour = 2, .innate = Innate.stat(.heavy_damage, 10) },
    .spellwraps = .{ .name = "Spellwraps", .flavor = "Old runes round steady fingers.", .slots = &.{.gloves}, .needs = .{ .intelligence = 12 }, .innate = Innate.stat(.spell_damage, 10) },
    .iron_boots = .{ .name = "Iron boots", .flavor = "Every step rings hollow.", .slots = &.{.boots}, .needs = .{ .strength = 14 }, .armour = 5 },
    .broad_belt = .{ .name = "Broad belt", .flavor = "Another hole, another winter.", .slots = &.{.belt}, .innate = Innate.stat(.life, 3) },
    .flask_belt = .{ .name = "Flask belt", .flavor = "Glass kept close to the heart.", .slots = &.{.belt}, .innate = Innate.stat(.life_flask, 20) },
    .sash = .{ .name = "Woven sash", .flavor = "Knots to hold a thought.", .slots = &.{.belt}, .innate = Innate.stat(.mana, 2) },
    .iron_ring = .{ .name = "Iron ring", .flavor = "A small weight behind the blow.", .slots = &.{ .left_ring, .right_ring }, .innate = .{ .physical_damage = 10 } },
    .jade_ring = .{ .name = "Jade ring", .flavor = "Smooth from nervous fingers.", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.dodge, 3) },
    .ruby_ring = .{ .name = "Ruby ring", .flavor = "A red spark under the grime.", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.life, 3) },
    .sapphire_ring = .{ .name = "Sapphire ring", .flavor = "A drop of blue held still.", .slots = &.{ .left_ring, .right_ring }, .innate = Innate.stat(.mana, 2) },
});

/// Characters of flavor a compared item card holds on one line.
pub const FLAVOR_MAX = 32;
comptime {
    for (SPECS.values) |s| if (s.flavor.len > FLAVOR_MAX) @compileError(s.name ++ ": flavor longer than a card line");
}

pub fn spec(k: Kind) Spec {
    return SPECS.getPtrConst(k).*;
}

pub const Item = struct {
    kind: Kind,
    mods: [AFFIXES_MAX]?Affix = @splat(null),

    pub fn name(self: Item) [:0]const u8 {
        return spec(self.kind).name;
    }

    pub fn flavor(self: Item) [:0]const u8 {
        return spec(self.kind).flavor;
    }

    pub fn fits(self: Item, slot: Slot) bool {
        return std.mem.indexOfScalar(Slot, self.kind.slots(), slot) != null;
    }

    pub fn magical(self: Item) bool {
        return self.mods[0] != null;
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
        for (self.mods) |maybe| if (maybe) |m| a.add(m.kind, m.value);
    }

    pub fn meets(self: Item, a: attrs.Attrs) bool {
        return a.meets(spec(self.kind).needs);
    }
};

pub fn roll(rng: *mathx.Rng) Item {
    var out = Item{ .kind = rng.pick(Kind, KINDS) };
    if (!rng.percent(MAGIC_PERCENT)) return out;
    const count = rng.range(1, out.mods.len);
    for (0..@intCast(count)) |i| {
        var at: usize = rng.below(AFFIXES.len);
        while (for (out.mods[0..i]) |m| {
            if (m.?.kind == AFFIXES[at].kind) break true;
        } else false) at = mathx.wrap(at, 1, AFFIXES.len);
        const a = AFFIXES[at];
        out.mods[i] = .{ .kind = a.kind, .value = @intCast(rng.range(a.lo, a.hi)) };
    }
    return out;
}

pub const Loot = struct { gold: i32 = 0, item: ?Item = null };

pub fn foeLoot(rng: *mathx.Rng) Loot {
    return .{
        .gold = if (rng.percent(FOE_GOLD_PERCENT)) FOE_GOLD.roll(rng) else 0,
        .item = if (rng.percent(DROP_PERCENT)) roll(rng) else null,
    };
}

pub const Gear = struct {
    slots: std.EnumArray(Slot, ?Item) = .initFill(null),

    pub fn stats(self: Gear, base: attrs.Attrs) attrs.Attrs {
        var out = base;
        for (self.slots.values) |maybe| if (maybe) |it| it.apply(&out);
        return out;
    }

    pub fn perks(self: Gear, base: passives.Perks) passives.Perks {
        var out = base;
        for (self.slots.values) |maybe| if (maybe) |it| {
            if (spec(it.kind).innate) |innate| if (innate == .grant) innate.grant.perk(&out);
        };
        return out;
    }

    pub fn forAttack(self: Gear, base: attrs.Attrs, attack: attrs.Attack) attrs.Attrs {
        var out = base;
        out.crit_bonus += if (attack == .spell) base.spell_crit_bonus else if (self.weapon(attack) != null) base.weapon_crit_bonus else 0;
        return out;
    }

    pub fn onHit(self: Gear, attack: attrs.Attack) WeaponEffect {
        if (self.weapon(attack) == null) return .{};
        const innate = spec(self.slots.get(.right_hand).?.kind).innate orelse return .{};
        return switch (innate) {
            .bleed => |b| .{ .bleed = b.chance, .bleed_damage = b.damage },
            .stun => |n| .{ .stun = n },
            .penetration => |n| .{ .penetration = n },
            else => .{},
        };
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

    pub fn add(self: *Inventory, it: Item) bool {
        if (self.n == BAG_MAX) return false;
        self.bag[self.n] = it;
        self.n += 1;
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
pub const Coins = struct {
    at: mathx.P,
    amount: i32,

    /// More than any one barrel holds: only piles dropped on one another are large.
    pub const LARGE = BARREL_GOLD.hi + 1;

    pub fn large(c: Coins) bool {
        return c.amount >= LARGE;
    }
};
pub const Ground = struct {
    drops: [GROUND_MAX]Drop = undefined,
    n: usize = 0,
    coins: [grid.CELLS]Coins = undefined,
    coin_n: usize = 0,

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
    for (0..2000) |_| seen.insert(roll(&rng).kind);
    try std.testing.expectEqual(KINDS.len, seen.count());
    std.debug.print("items: {d} heavy, {d} light, {d} non-attacking implements, {d} offhand swaps; all {d} kinds roll as loot\n", .{ heavy.len, light.len, implements.len, offhands.len, KINDS.len });
}

test "equipment swaps preserve both hands, reject self-funded requirements and keep dependent gear valid" {
    const base = attrs.Attrs.of(.{ .strength = 18, .dexterity = 20, .intelligence = 10 });
    var inv = Inventory{};
    try std.testing.expect(inv.add(.{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 2 }, null } }));
    try inv.equip(0, .left_ring, base);
    try std.testing.expect(inv.add(.{ .kind = .mail }));
    try inv.equip(0, .chest, base);
    try std.testing.expectError(error.Requirements, inv.unequip(.left_ring, base));
    try inv.unequip(.chest, base);
    try inv.unequip(.left_ring, base);
    var other = Inventory{};
    try std.testing.expect(other.add(.{ .kind = .mail, .mods = .{ .{ .kind = .strength, .value = 3 }, null } }));
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
        const it = roll(&rng);
        if (it.mods[1]) |b| try std.testing.expect(it.mods[0].?.kind != b.kind);
    }
    std.debug.print("equipment: bow plus all 3 great weapons occupy both hands; reverse swaps, dependency checks, atomic failures and 2000 bounded modifier rolls\n", .{});
}

test "foe loot is mostly gold then plain items with rare magic affixes" {
    var rng = mathx.Rng.init(0xC157E2);
    const rolls = 10000;
    var gold: usize = 0;
    var plain: usize = 0;
    var magic: usize = 0;
    for (0..rolls) |_| {
        const reward = foeLoot(&rng);
        if (reward.gold > 0) {
            gold += 1;
            try std.testing.expect(reward.gold >= FOE_GOLD.lo and reward.gold <= FOE_GOLD.hi);
        }
        if (reward.item) |it| {
            if (it.magical()) {
                magic += 1;
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
    std.debug.print("foe loot over {d} kills: {d} gold, {d} plain items without affixes, {d} magic items\n", .{ rolls, gold, plain, magic });
}

test "every equipment base rolls white and blue and keeps its innate separate from affixes" {
    var rng = mathx.Rng.init(0xBA5E);
    var white = std.EnumSet(Kind).initEmpty();
    var blue = std.EnumSet(Kind).initEmpty();
    for (0..20000) |_| {
        const it = roll(&rng);
        if (it.magical()) blue.insert(it.kind) else white.insert(it.kind);
    }
    try std.testing.expectEqual(KINDS.len, white.count());
    try std.testing.expectEqual(KINDS.len, blue.count());
    const base = attrs.Attrs.of(.{ .strength = 30, .dexterity = 30, .intelligence = 30 });
    for (KINDS) |kind| {
        var plain = base;
        var magic = base;
        const it = Item{ .kind = kind };
        it.apply(&plain);
        (Item{ .kind = kind, .mods = .{ .{ .kind = .mana, .value = 2 }, null } }).apply(&magic);
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
    std.debug.print("bases: all {d} roll in both rarities over 20000 drops; innate/affix separation, scoped crit and recovery perks checked\n", .{KINDS.len});
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
