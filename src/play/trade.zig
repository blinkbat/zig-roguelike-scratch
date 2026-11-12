const std = @import("std");
const mathx = @import("../core/mathx.zig");
const items = @import("items.zig");
const consumable = @import("consumable.zig");
const inventory = @import("inventory.zig");

pub const WARES_MAX: usize = 8;
const WARES_LEAST: i32 = 5;
const SUPPLY_LEAST: i32 = 1;
const SUPPLY_MOST: i32 = 5;
/// Item rarity on a merchant's shelf, as the spoils affix counts it.
const SHELF_RARITY: i32 = 100;
/// A merchant pays this share of what it asks.
const SELL_DIVISOR: i32 = 4;
const STOCK_SALT: u64 = 0x9E37_79B9_7F4A_7C15;

const RARITY_PRICE = std.EnumArray(items.Rarity, i32).init(.{ .normal = 15, .magic = 45, .rare = 120 });
const AFFIX_PRICE = std.EnumArray(items.Rarity, i32).init(.{ .normal = 0, .magic = 10, .rare = 20 });
const SUPPLY_PRICE = std.EnumArray(consumable.Kind, i32).init(.{ .bandage = 6, .smelling_salts = 10, .frost_vial = 12 });

pub const NOT_ENOUGH_GOLD = "Not enough gold";

pub fn price(it: items.Item) i32 {
    var mods: i32 = 0;
    for (it.mods) |m| mods += @intFromBool(m != null);
    const r = it.rarity();
    return RARITY_PRICE.get(r) + AFFIX_PRICE.get(r) * mods;
}

pub fn supplyPrice(k: consumable.Kind) i32 {
    return SUPPLY_PRICE.get(k);
}

pub fn offered(asked: i32) i32 {
    return @max(1, @divTrunc(asked, SELL_DIVISOR));
}

/// A row of either list: a stacked supply, or an item by its index on the shelf or in the bag.
pub const Ware = union(enum) {
    supply: consumable.Kind,
    item: usize,
};

pub const Wares = struct {
    pub const COUNTED = .{.{ "item", "item_n" }};
    item: [WARES_MAX]items.Item = undefined,
    item_n: u8 = 0,
    supplies: consumable.Stacks = .initFill(0),

    /// The same shelf for the same run and merchant.
    pub fn roll(run_seed: u64, merchant: u8) Wares {
        var rng = mathx.Rng.init(run_seed ^ (@as(u64, merchant) +% 1) *% STOCK_SALT);
        var w = Wares{};
        for (consumable.KINDS) |k| w.supplies.set(k, @intCast(rng.range(SUPPLY_LEAST, SUPPLY_MOST)));
        const n: usize = @intCast(rng.range(WARES_LEAST, WARES_MAX));
        for (0..n) |_| _ = mathx.push(items.Item, &w.item, &w.item_n, items.roll(&rng, SHELF_RARITY));
        return w;
    }

    pub fn shelved(self: *const Wares) []const items.Item {
        return self.item[0..self.item_n];
    }

    pub fn count(self: *const Wares) usize {
        return consumable.stocked(&self.supplies) + self.item_n;
    }

    /// Supplies first, in `consumable.KINDS` order, then the items.
    pub fn at(self: *const Wares, row: usize) ?Ware {
        return rowOf(&self.supplies, self.item_n, row);
    }

    pub fn cost(self: *const Wares, w: Ware) i32 {
        return asking(w, self.shelved());
    }

    pub fn mend(self: *Wares) void {
        for (self.item[0..self.item_n]) |*it| it.mend();
        for (&self.supplies.values) |*n| n.* = @min(n.*, consumable.STACK_MAX);
    }

    pub fn valid(self: *const Wares) bool {
        return self.item_n <= WARES_MAX;
    }
};

/// The hero's goods as a merchant lists them: carried supplies, then the bag; worn gear is not for sale.
pub fn carried(inv: *const inventory.Inventory) usize {
    return inv.carriedCount() + inv.n;
}

pub fn carriedAt(inv: *const inventory.Inventory, row: usize) ?Ware {
    return rowOf(&inv.stacks, inv.n, row);
}

pub fn worth(inv: *const inventory.Inventory, w: Ware) i32 {
    return offered(asking(w, inv.bag[0..inv.n]));
}

fn rowOf(stacks: *const consumable.Stacks, n: usize, row: usize) ?Ware {
    if (consumable.stockedAt(stacks, row)) |k| return .{ .supply = k };
    const at = row - consumable.stocked(stacks);
    return if (at < n) .{ .item = at } else null;
}

fn asking(w: Ware, goods: []const items.Item) i32 {
    return switch (w) {
        .supply => |k| supplyPrice(k),
        .item => |i| price(goods[i]),
    };
}

pub const Failure = error{ Gold, Full, StackFull, Gone };

pub fn caption(err: Failure) [:0]const u8 {
    return switch (err) {
        error.Gold => NOT_ENOUGH_GOLD,
        error.Full => inventory.caption(error.Full),
        error.StackFull => inventory.STACK_FULL,
        error.Gone => inventory.caption(error.Missing),
    };
}

pub const Deal = struct { ware: union(enum) { supply: consumable.Kind, item: items.Item }, gold: i32 };

pub fn buy(shelf: *Wares, row: usize, inv: *inventory.Inventory, gold: *i32) Failure!Deal {
    const w = shelf.at(row) orelse return error.Gone;
    const cost = shelf.cost(w);
    if (gold.* < cost) return error.Gold;
    const deal: Deal = switch (w) {
        .supply => |k| blk: {
            if (!inv.stock(k)) return error.StackFull;
            shelf.supplies.getPtr(k).* -= 1;
            break :blk .{ .ware = .{ .supply = k }, .gold = cost };
        },
        .item => |i| blk: {
            const it = shelf.item[i];
            if (!inv.add(it)) return error.Full;
            mathx.removeAt(items.Item, &shelf.item, &shelf.item_n, i, null);
            break :blk .{ .ware = .{ .item = it }, .gold = cost };
        },
    };
    gold.* -= cost;
    return deal;
}

pub fn sell(row: usize, inv: *inventory.Inventory, gold: *i32) Failure!Deal {
    const w = carriedAt(inv, row) orelse return error.Gone;
    const paid = worth(inv, w);
    const deal: Deal = switch (w) {
        .supply => |k| blk: {
            inv.stacks.getPtr(k).* -= 1;
            break :blk .{ .ware = .{ .supply = k }, .gold = paid };
        },
        .item => |i| .{ .ware = .{ .item = inv.remove(i) }, .gold = paid },
    };
    gold.* +|= paid;
    return deal;
}

test "a merchant's shelf is the same for the same run and differs between merchants" {
    const a = Wares.roll(0xC0FFEE, 0);
    const again = Wares.roll(0xC0FFEE, 0);
    const other = Wares.roll(0xC0FFEE, 1);
    try std.testing.expectEqualSlices(items.Item, a.shelved(), again.shelved());
    try std.testing.expect(a.item_n >= WARES_LEAST and a.item_n <= WARES_MAX);
    try std.testing.expect(!std.meta.eql(a.item, other.item) or !std.meta.eql(a.supplies, other.supplies));
    for (consumable.KINDS) |k| try std.testing.expect(a.supplies.get(k) >= SUPPLY_LEAST);
    try std.testing.expectEqual(a.count(), consumable.KINDS.len + a.item_n);
}

test "buying takes the price and the ware, and an empty purse or a full bag refuses with both untouched" {
    var shelf = Wares.roll(7, 3);
    var inv = inventory.Inventory{};
    var gold: i32 = 0;
    const first_item = consumable.KINDS.len;
    try std.testing.expectError(error.Gold, buy(&shelf, first_item, &inv, &gold));
    try std.testing.expectEqual(@as(usize, 0), inv.n);
    const wanted = shelf.item[0];
    gold = price(wanted) + 3;
    const n = shelf.item_n;
    const deal = try buy(&shelf, first_item, &inv, &gold);
    try std.testing.expectEqual(@as(i32, 3), gold);
    try std.testing.expectEqualDeep(wanted, deal.ware.item);
    try std.testing.expectEqualDeep(wanted, inv.bag[0]);
    try std.testing.expectEqual(n - 1, shelf.item_n);
    while (inv.add(.{ .kind = .cap })) {}
    gold = 10_000;
    const before = shelf;
    try std.testing.expectError(error.Full, buy(&shelf, first_item, &inv, &gold));
    try std.testing.expectEqual(@as(i32, 10_000), gold);
    try std.testing.expectEqualDeep(before.shelved(), shelf.shelved());
}

test "a supply bought comes off the shelf's stack, and a full stack refuses it" {
    var shelf = Wares.roll(11, 0);
    var inv = inventory.Inventory{};
    var gold: i32 = 1000;
    const k = shelf.at(0).?.supply;
    const had = shelf.supplies.get(k);
    _ = try buy(&shelf, 0, &inv, &gold);
    try std.testing.expectEqual(had - 1, shelf.supplies.get(k));
    try std.testing.expectEqual(@as(u8, 1), inv.stacks.get(k));
    inv.stacks.set(k, consumable.STACK_MAX);
    try std.testing.expectError(error.StackFull, buy(&shelf, 0, &inv, &gold));
    shelf.supplies.set(k, 0);
    try std.testing.expect(shelf.at(0).? != .supply or shelf.at(0).?.supply != k);
}

test "selling pays a quarter of the asking price, at least a coin, and lists supplies before the bag" {
    var inv = inventory.Inventory{};
    try std.testing.expect(inv.add(.{ .kind = .ring, .rare_name = .{ .first = .Void, .last = .Maw }, .mods = .{ .{ .kind = .mana, .value = 2 }, .{ .kind = .life, .value = 3 }, null, null } }));
    try std.testing.expect(inv.stock(.bandage));
    var gold: i32 = 0;
    try std.testing.expectEqual(@as(usize, 2), carried(&inv));
    try std.testing.expectEqual(Ware{ .supply = .bandage }, carriedAt(&inv, 0).?);
    const deal = try sell(0, &inv, &gold);
    try std.testing.expectEqual(@as(i32, 1), deal.gold);
    try std.testing.expectEqual(@as(u8, 0), inv.stacks.get(.bandage));
    const rare = try sell(0, &inv, &gold);
    try std.testing.expectEqual(@divTrunc(RARITY_PRICE.get(.rare) + 2 * AFFIX_PRICE.get(.rare), SELL_DIVISOR), rare.gold);
    try std.testing.expectEqual(@as(usize, 0), inv.n);
    try std.testing.expectError(error.Gone, sell(0, &inv, &gold));
}
