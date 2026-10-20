const std = @import("std");
const attrs = @import("attrs.zig");
const damage = @import("damage.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");

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
    .{ .kind = .mana, .lo = 5, .hi = 15 },
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

    pub fn slots(k: Kind) []const Slot {
        return spec(k).slots;
    }
};
const KINDS = std.enums.values(Kind);
/// Percent of slain foes that drop an item.
pub const DROP_PERCENT = 25;
pub const Affix = struct { kind: Mod, value: i16 };
pub const Spec = struct {
    name: [:0]const u8,
    /// Where it may be worn.
    slots: []const Slot,
    needs: attrs.Needs = .{},
    damage: ?damage.Base = null,
    style: attrs.Style = .heavy,
    attack: attrs.Attack = .melee,
    two_handed: bool = false,
    armour: i16 = 0,
};
const SPECS = std.EnumArray(Kind, Spec).init(.{
    .sword = .{ .name = "Short sword", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 2, .hi = 4 }, .style = .light },
    .axe = .{ .name = "Great axe", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 4, .hi = 7 }, .two_handed = true },
    .bow = .{ .name = "Short bow", .slots = &.{.right_hand}, .needs = .{ .dexterity = 12 }, .damage = .{ .lo = 2, .hi = 5 }, .style = .light, .attack = .ranged, .two_handed = true },
    .staff = .{ .name = "Oak staff", .slots = &.{.right_hand}, .needs = .{ .intelligence = 12 }, .two_handed = true },
    .longsword = .{ .name = "Longsword", .slots = &.{.right_hand}, .needs = .{ .strength = 10 }, .damage = .{ .lo = 2, .hi = 4 } },
    .mace = .{ .name = "Mace", .slots = &.{.right_hand}, .needs = .{ .strength = 10 }, .damage = .{ .lo = 2, .hi = 4 } },
    .greatsword = .{ .name = "Greatsword", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 4, .hi = 7 }, .two_handed = true },
    .crossbow = .{ .name = "Crossbow", .slots = &.{.right_hand}, .needs = .{ .strength = 12 }, .damage = .{ .lo = 2, .hi = 5 }, .attack = .ranged, .two_handed = true },
    .greatclub = .{ .name = "Greatclub", .slots = &.{.right_hand}, .needs = .{ .strength = 20 }, .damage = .{ .lo = 4, .hi = 7 }, .two_handed = true },
    .sling = .{ .name = "Sling", .slots = &.{.right_hand}, .needs = .{ .dexterity = 12 }, .damage = .{ .lo = 2, .hi = 5 }, .style = .light, .attack = .ranged },
    .dagger = .{ .name = "Dagger", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 2, .hi = 4 }, .style = .light },
    .handaxe = .{ .name = "Handaxe", .slots = &.{.right_hand}, .needs = .{ .dexterity = 10 }, .damage = .{ .lo = 2, .hi = 4 }, .style = .light },
    .wand = .{ .name = "Wand", .slots = &.{.right_hand}, .needs = .{ .intelligence = 12 } },
    .tome = .{ .name = "Tome", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 } },
    .orb = .{ .name = "Orb", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 } },
    .buckler = .{ .name = "Buckler", .slots = &.{.left_hand}, .needs = .{ .dexterity = 10 }, .armour = 2 },
    .totem = .{ .name = "Totem", .slots = &.{.left_hand}, .needs = .{ .intelligence = 12 } },
    .shield = .{ .name = "Wooden shield", .slots = &.{.left_hand}, .needs = .{ .strength = 10 }, .armour = 6 },
    .cap = .{ .name = "Leather cap", .slots = &.{.helm}, .armour = 2 },
    .helmet = .{ .name = "Iron helm", .slots = &.{.helm}, .needs = .{ .strength = 16 }, .armour = 4 },
    .leather = .{ .name = "Leather armour", .slots = &.{.chest}, .needs = .{ .strength = 10 }, .armour = 5 },
    .mail = .{ .name = "Mail armour", .slots = &.{.chest}, .needs = .{ .strength = 20 }, .armour = 10 },
    .belt = .{ .name = "Leather belt", .slots = &.{.belt}, .armour = 1 },
    .gloves = .{ .name = "Leather gloves", .slots = &.{.gloves}, .armour = 2 },
    .boots = .{ .name = "Leather boots", .slots = &.{.boots}, .armour = 2 },
    .ring = .{ .name = "Copper ring", .slots = &.{ .left_ring, .right_ring } },
    .amulet = .{ .name = "Bronze amulet", .slots = &.{.amulet} },
});

pub fn spec(k: Kind) Spec {
    return SPECS.getPtrConst(k).*;
}

pub const Item = struct {
    kind: Kind,
    mods: [2]?Affix = .{ null, null },

    pub fn name(self: Item) [:0]const u8 {
        return spec(self.kind).name;
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
        a.armour += spec(self.kind).armour;
        for (self.mods) |maybe| if (maybe) |m| a.add(m.kind, m.value);
    }

    pub fn meets(self: Item, a: attrs.Attrs) bool {
        return a.meets(spec(self.kind).needs);
    }
};

pub fn roll(rng: *mathx.Rng) Item {
    var out = Item{ .kind = KINDS[rng.below(KINDS.len)] };
    const count = rng.range(0, out.mods.len);
    for (0..@intCast(count)) |i| {
        var at: usize = rng.below(AFFIXES.len);
        while (for (out.mods[0..i]) |m| {
            if (m.?.kind == AFFIXES[at].kind) break true;
        } else false) at = (at + 1) % AFFIXES.len;
        const a = AFFIXES[at];
        out.mods[i] = .{ .kind = a.kind, .value = @intCast(rng.range(a.lo, a.hi)) };
    }
    return out;
}

pub const Gear = struct {
    slots: std.EnumArray(Slot, ?Item) = .initFill(null),

    pub fn stats(self: Gear, base: attrs.Attrs) attrs.Attrs {
        var out = base;
        for (self.slots.values) |maybe| if (maybe) |it| it.apply(&out);
        return out;
    }

    pub fn valid(self: Gear, base: attrs.Attrs) bool {
        if (self.slots.get(.right_hand)) |it| {
            if (spec(it.kind).two_handed and self.slots.get(.left_hand) != null) return false;
        }
        for (SLOTS) |slot| if (self.slots.get(slot)) |it| {
            if (!it.fits(slot) or !self.wornMeets(slot, base)) return false;
        };
        return true;
    }

    /// An item cannot fund its own requirement.
    pub fn wornMeets(self: Gear, slot: Slot, base: attrs.Attrs) bool {
        const it = self.slots.get(slot) orelse return true;
        var without = self;
        without.slots.set(slot, null);
        return it.meets(without.stats(base));
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
        var after = self.gear;
        after.slots.set(slot, it);
        if (spec(it.kind).two_handed) after.slots.set(.left_hand, null);
        if (slot == .left_hand) if (after.slots.get(.right_hand)) |held| {
            if (spec(held.kind).two_handed) after.slots.set(.right_hand, null);
        };
        return after;
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
pub const Coins = struct { at: mathx.P, amount: i32 };
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
            const amount = pile.amount;
            self.coin_n -= 1;
            self.coins[i] = self.coins[self.coin_n];
            return amount;
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
    for ([_]Kind{ .wand, .staff }) |kind| {
        gear.slots.set(.right_hand, .{ .kind = kind });
        try std.testing.expect(spec(kind).damage == null);
        for (std.enums.values(attrs.Attack)) |attack| {
            try std.testing.expect(gear.weapon(attack) == null);
            try std.testing.expectEqual(attack.defaultStyle(), gear.scaling(attack));
        }
    }
    const base = attrs.Attrs.of(.{ .strength = 30, .dexterity = 30, .intelligence = 30 });
    for ([_]Kind{ .tome, .orb, .buckler, .shield, .totem }) |kind| {
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
    std.debug.print("items: {d} heavy, {d} light, 2 non-attacking implements, 5 offhand swaps; all {d} kinds roll as loot\n", .{ heavy.len, light.len, KINDS.len });
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
