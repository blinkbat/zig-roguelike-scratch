const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const consumable = @import("consumable.zig");
const item_bases = @import("item_bases.zig");
const items = @import("items.zig");
const inventory = @import("inventory.zig");
const loot = @import("loot.zig");

pub const GROUND_MAX = 512;
pub const Drop = struct { item: items.Item, at: mathx.P, source: u16 = grid.NO_ONE };
pub const Supply = struct { kind: consumable.Kind, at: mathx.P, source: u16 = grid.NO_ONE };
pub const Coins = struct {
    at: mathx.P,
    amount: i32,

    pub fn large(c: Coins) bool {
        return c.amount > loot.BARREL_GOLD.hi;
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

    pub fn bagged(self: *const Ground, at: mathx.P) bool {
        if (self.hasItems(at)) return true;
        for (self.supplies[0..self.supply_n]) |s| if (s.at.eq(at)) return true;
        return false;
    }

    pub fn lying(self: *const Ground) grid.CellSet {
        var out = grid.CellSet.initEmpty();
        inline for (COUNTED) |c| {
            for (@field(self, c[0])[0..@field(self, c[1])]) |x| out.set(grid.Level.idx(x.at));
        }
        return out;
    }

    pub fn addSupply(self: *Ground, s: Supply) bool {
        return mathx.push(Supply, &self.supplies, &self.supply_n, s);
    }

    pub fn takeSupply(self: *Ground, i: usize, into: *inventory.Inventory) bool {
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
        return mathx.push(Coins, &self.coins, &self.coin_n, .{ .at = at, .amount = amount });
    }

    pub fn collect(self: *Ground, at: mathx.P) i32 {
        for (self.coins[0..self.coin_n], 0..) |pile, i| if (pile.at.eq(at)) {
            return mathx.swapRemove(Coins, &self.coins, &self.coin_n, i).amount;
        };
        return 0;
    }

    pub fn add(self: *Ground, drop: Drop) bool {
        return mathx.push(Drop, &self.drops, &self.n, drop);
    }

    pub fn room(self: *const Ground, reserved: usize) bool {
        return self.n + reserved < self.drops.len;
    }

    pub fn take(self: *Ground, i: usize, into: *inventory.Inventory) bool {
        if (i >= self.n or !into.add(self.drops[i].item)) return false;
        mathx.removeAt(Drop, &self.drops, &self.n, i, null);
        return true;
    }
};

test "ground gold accommodates every cell and full pickup leaves its item intact" {
    var ground = Ground{};
    var inv = inventory.Inventory{};
    for (0..grid.CELLS) |i| try std.testing.expect(ground.gold(grid.Level.of(i), 1));
    try std.testing.expectEqual(grid.CELLS, ground.coin_n);
    try std.testing.expect(ground.gold(.{ .x = 1, .y = 1 }, 7));
    try std.testing.expectEqual(@as(i32, 8), ground.collect(.{ .x = 1, .y = 1 }));
    try std.testing.expect(ground.add(.{ .item = .{ .kind = .cap }, .at = .{ .x = 1, .y = 1 } }));
    for (0..inventory.BAG_MAX) |_| try std.testing.expect(inv.add(.{ .kind = .ring }));
    try std.testing.expect(!ground.take(0, &inv));
    try std.testing.expectEqual(@as(usize, 1), ground.n);
}

test "ground pickups preserve order and source identity and never collect another cell's gold" {
    const here = mathx.P{ .x = 5, .y = 5 };
    const there = mathx.P{ .x = 6, .y = 5 };
    var ground = Ground{};
    var inv = inventory.Inventory{};
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
    try std.testing.expectEqual(item_bases.Kind.ring, inv.bag[0].kind);
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
}
