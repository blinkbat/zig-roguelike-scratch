const std = @import("std");
const mathx = @import("../core/mathx.zig");

pub const Element = enum { cold, fire, chaos, lightning };
pub const Resists = std.EnumArray(Element, i16);

pub const Damage = struct {
    physical: i32 = 0,
    elements: std.EnumArray(Element, i32) = .initFill(0),

    pub fn total(self: Damage, resists: Resists) i32 {
        var sum: i64 = @max(0, self.physical);
        for (std.enums.values(Element)) |e| sum += resisted(self.elements.get(e), resists.get(e));
        return @intCast(@min(sum, std.math.maxInt(i32)));
    }

    /// Some of its `e` gets past `resists`.
    pub fn reaches(self: Damage, resists: Resists, e: Element) bool {
        return resisted(self.elements.get(e), resists.get(e)) > 0;
    }
};

/// Harm a turn for `TURNS` turns from the turn after it starts; started again, it refreshes without stacking or delaying a due tick.
pub fn Lasting(comptime TURNS: u8, comptime Arg: type, comptime amount: fn (Arg) i32) type {
    return struct {
        turns: u8 = 0,
        fresh: bool = false,

        pub fn start(self: *@This()) void {
            if (self.turns == 0) self.fresh = true;
            self.turns = TURNS;
        }

        pub fn tick(self: *@This(), arg: Arg) ?i32 {
            if (self.turns == 0) return null;
            if (self.fresh) {
                self.fresh = false;
                return null;
            }
            self.turns -= 1;
            return amount(arg);
        }

        /// The turn it started in is over, whether or not its tick ran.
        pub fn settle(self: *@This()) void {
            self.fresh = false;
        }
    };
}

pub fn resisted(amount: i32, resist: i16) i32 {
    const scale: i64 = mathx.PERCENT - @as(i64, std.math.clamp(resist, -mathx.PERCENT, mathx.PERCENT));
    return @intCast(@min(@divTrunc(@as(i64, @max(0, amount)) * scale, mathx.PERCENT), std.math.maxInt(i32)));
}

test "each elemental resistance reduces only its own damage and leaves physical damage whole" {
    var hit = Damage{ .physical = 5, .elements = .initFill(20) };
    for (std.enums.values(Element)) |e| {
        var resists = Resists.initFill(0);
        resists.set(e, 50);
        try std.testing.expectEqual(@as(i32, 75), hit.total(resists));
        resists.set(e, 100);
        try std.testing.expectEqual(@as(i32, 65), hit.total(resists));
    }
    hit.elements = .initFill(0);
    try std.testing.expectEqual(@as(i32, 5), hit.total(.initFill(100)));
    try std.testing.expectEqual(@as(i32, 30), resisted(20, -50));
    try std.testing.expectEqual(@as(i32, 0), resisted(20, 150));
    try std.testing.expectEqual(@as(i32, 0), resisted(-1, 0));
    std.debug.print("4 elemental resistances checked: 50% of 20 = 10, physical damage unchanged\n", .{});
}
