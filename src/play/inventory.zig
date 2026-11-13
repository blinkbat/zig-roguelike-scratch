const std = @import("std");
const attrs = @import("attrs.zig");
const mathx = @import("../core/mathx.zig");
const passives = @import("passives.zig");
const flask = @import("flask.zig");
const consumable = @import("consumable.zig");
const item_bases = @import("item_bases.zig");
const items = @import("items.zig");
const Gear = @import("gear.zig").Gear;

pub const BAG_MAX = 256;
pub const Failure = error{ Missing, WrongSlot, Requirements, Full };

pub const STACK_FULL = "Stack full";

pub fn caption(err: Failure) [:0]const u8 {
    return switch (err) {
        error.Full => "Inventory full",
        error.Requirements => "Requirements unmet in final loadout",
        error.WrongSlot => "Wrong slot",
        error.Missing => "Item unavailable",
    };
}

pub const Inventory = struct {
    bag: [BAG_MAX]items.Item = undefined,
    n: usize = 0,
    gear: Gear = .{},
    stacks: consumable.Stacks = .initFill(0),

    pub const COUNTED = .{.{ "bag", "n" }};

    pub fn add(self: *Inventory, it: items.Item) bool {
        return mathx.push(items.Item, &self.bag, &self.n, it);
    }

    pub fn mend(self: *Inventory) void {
        for (self.bag[0..self.n]) |*it| it.mend();
        for (&self.gear.slots.values) |*worn| if (worn.*) |*it| it.mend();
    }

    pub fn stock(self: *Inventory, k: consumable.Kind) bool {
        const n = self.stacks.getPtr(k);
        if (n.* >= consumable.STACK_MAX) return false;
        n.* += 1;
        return true;
    }

    /// Kinds carried, in `consumable.KINDS` order.
    pub fn carriedCount(self: *const Inventory) usize {
        return consumable.stocked(&self.stacks);
    }

    pub fn carriedAt(self: *const Inventory, row: usize) ?consumable.Kind {
        return consumable.stockedAt(&self.stacks, row);
    }

    pub fn remove(self: *Inventory, at: usize) items.Item {
        std.debug.assert(at < self.n);
        const it = self.bag[at];
        mathx.removeAt(items.Item, &self.bag, &self.n, at, null);
        return it;
    }

    pub fn takeSmallKey(self: *Inventory) bool {
        for (self.bag[0..self.n], 0..) |it, i| {
            if (it.kind != .small_key) continue;
            _ = self.remove(i);
            return true;
        }
        return false;
    }

    /// The loadout with bag item `at` worn in `slot`, before requirements are checked.
    pub fn swapped(self: *const Inventory, at: usize, slot: item_bases.Slot) Failure!Gear {
        if (at >= self.n) return error.Missing;
        const it = self.bag[at];
        if (!it.fits(slot)) return error.WrongSlot;
        return self.gear.wearing(it, slot);
    }

    pub fn preview(self: *const Inventory, at: usize, slot: item_bases.Slot, base: attrs.Attrs) Failure!Gear {
        const after = try self.swapped(at, slot);
        if (!after.validFrom(self.gear, base)) return error.Requirements;
        var n = self.n - 1;
        for (item_bases.SLOTS) |s| n += @intFromBool(self.displaced(after, slot, s));
        if (n > BAG_MAX) return error.Full;
        return after;
    }

    pub fn displaced(self: *const Inventory, after: Gear, slot: item_bases.Slot, s: item_bases.Slot) bool {
        const worn = self.gear.slots.get(s) orelse return false;
        return s == slot or !std.meta.eql(@as(?items.Item, worn), after.slots.get(s));
    }

    pub fn equip(self: *Inventory, at: usize, slot: item_bases.Slot, base: attrs.Attrs) Failure!void {
        const after = try self.preview(at, slot, base);
        _ = self.remove(at);
        for (item_bases.SLOTS) |s| if (self.displaced(after, slot, s)) std.debug.assert(self.add(self.gear.slots.get(s).?));
        self.gear = after;
    }

    pub fn unequip(self: *Inventory, slot: item_bases.Slot, base: attrs.Attrs) Failure!void {
        const it = self.gear.slots.get(slot) orelse return error.Missing;
        if (self.n == BAG_MAX) return error.Full;
        var after = self.gear;
        after.slots.set(slot, null);
        if (!after.validFrom(self.gear, base)) return error.Requirements;
        std.debug.assert(self.add(it));
        self.gear = after;
    }
};

test "flasks start worn in their own slots, never roll as loot, and come off and back like gear" {
    var rng = mathx.Rng.init(0xF1A5);
    for (0..5000) |_| try std.testing.expect(items.roll(&rng, 0).kind.flaskOf() == null);
    const base = attrs.Attrs.of(.{ .strength = 10, .dexterity = 10, .intelligence = 10 });
    var inv = Inventory{ .gear = .flasks };
    try std.testing.expectEqualDeep(base, inv.gear.stats(base));
    try std.testing.expectEqualDeep(passives.Perks{}, inv.gear.perks(.{}));
    for (std.enums.values(flask.Kind), [_]flask.Kind{ .mana, .life }) |k, other| {
        try std.testing.expect(inv.gear.holds(k));
        try inv.unequip(.ofFlask(k), base);
        try std.testing.expect(!inv.gear.holds(k));
        try std.testing.expectEqual(item_bases.Kind.ofFlask(k), inv.bag[inv.n - 1].kind);
        try std.testing.expectError(error.WrongSlot, inv.swapped(inv.n - 1, .ofFlask(other)));
        try std.testing.expectError(error.WrongSlot, inv.swapped(inv.n - 1, .belt));
        try inv.equip(inv.n - 1, .ofFlask(k), base);
        try std.testing.expect(inv.gear.holds(k));
    }
    try std.testing.expectEqual(@as(usize, 0), inv.n);
}

test "Small Keys have no equipment slots or affixes and stay out of equipment rolls" {
    const key = item_bases.Kind.small_key;
    try std.testing.expectEqual(@as(usize, 0), key.slots().len);
    for (@import("affixes.zig").MODS) |mod| try std.testing.expect(!mod.allows(key));
    try std.testing.expect(std.mem.indexOfScalar(item_bases.Kind, &@import("loot.zig").BASES, key) == null);
    var inv = Inventory{};
    try std.testing.expect(inv.add(.{ .kind = key }));
    try std.testing.expectError(error.WrongSlot, inv.swapped(0, .right_hand));
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
    try std.testing.expectEqual(item_bases.Kind.bow, inv.gear.slots.get(.right_hand).?.kind);
    const strong = attrs.Attrs.of(.{ .strength = 20, .dexterity = 20, .intelligence = 10 });
    for ([_]item_bases.Kind{ .axe, .greatclub, .greatsword }) |kind| {
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
        try std.testing.expectEqual(item_bases.Kind.sword, hands.bag[1].kind);
        try std.testing.expectEqual(item_bases.Kind.shield, hands.bag[0].kind);
        try std.testing.expectEqual(kind, hands.gear.slots.get(.right_hand).?.kind);
        try std.testing.expect(hands.gear.slots.get(.left_hand) == null);
        try hands.equip(0, .left_hand, strong);
        try std.testing.expect(hands.gear.slots.get(.right_hand) == null);
        try std.testing.expectEqual(kind, hands.bag[hands.n - 1].kind);
    }
    var rng = mathx.Rng.init(123);
    for (0..2000) |_| {
        const it = items.roll(&rng, 0);
        if (it.mods[1]) |b| try std.testing.expect(it.mods[0].?.kind != b.kind);
    }
}

fn expectInventoryUnchanged(before: *const Inventory, after: *const Inventory) !void {
    try std.testing.expectEqual(before.n, after.n);
    try std.testing.expectEqualDeep(before.gear, after.gear);
    try std.testing.expectEqualSlices(items.Item, before.bag[0..before.n], after.bag[0..after.n]);
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
}

test "gear already unmet on load comes off and does not block other slots" {
    const weak = attrs.Attrs.of(.{ .strength = 12, .dexterity = 20, .intelligence = 10 });
    var inv = Inventory{};
    inv.gear.slots.set(.chest, .{ .kind = .mail });
    inv.gear.slots.set(.helm, .{ .kind = .helmet });
    try std.testing.expect(!inv.gear.valid(weak));
    try std.testing.expect(inv.add(.{ .kind = .ring }));
    try inv.equip(0, .left_ring, weak);
    try inv.unequip(.chest, weak);
    try inv.unequip(.helm, weak);
    try std.testing.expect(inv.add(.{ .kind = .mail }));
    try std.testing.expectError(error.Requirements, inv.equip(inv.n - 1, .chest, weak));
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
    try std.testing.expectEqual(item_bases.Kind.shield, inv.bag[BAG_MAX - 2].kind);
    try std.testing.expectEqual(item_bases.Kind.sword, inv.bag[BAG_MAX - 1].kind);
    for (inv.bag[0 .. BAG_MAX - 2]) |it| try std.testing.expectEqual(item_bases.Kind.ring, it.kind);

    try inv.equip(BAG_MAX - 2, .left_hand, base);
    try std.testing.expectEqual(@as(usize, BAG_MAX), inv.n);
    try std.testing.expect(inv.gear.slots.get(.right_hand) == null);
    try std.testing.expectEqual(item_bases.Kind.shield, inv.gear.slots.get(.left_hand).?.kind);
    try std.testing.expectEqual(item_bases.Kind.greatsword, inv.bag[BAG_MAX - 1].kind);
    _ = inv.remove(0);
    try inv.unequip(.left_hand, base);
    try std.testing.expectEqual(@as(usize, BAG_MAX), inv.n);
    try std.testing.expectEqual(item_bases.Kind.shield, inv.bag[BAG_MAX - 1].kind);
    try std.testing.expect(inv.gear.slots.get(.left_hand) == null);
}
