const std = @import("std");
const mathx = @import("../core/mathx.zig");

pub const Element = enum { cold, fire, chaos, lightning };

/// A skill's `procs` landing `pc` percent of the time, whatever the resistance.
pub fn chance(comptime pc: u32) fn (*mathx.Rng, i16) bool {
    return struct {
        fn procs(rng: *mathx.Rng, _: i16) bool {
            return rng.percent(pc);
        }
    }.procs;
}
/// A foe's blow landing its status `pc` percent of the time; never, drawing nothing.
pub fn procs(rng: *mathx.Rng, pc: u32) bool {
    return pc > 0 and rng.percent(pc);
}

/// A skill's `procs` landing every time, drawing nothing.
pub fn always(_: *mathx.Rng, _: i16) bool {
    return true;
}

pub const Resists = std.EnumArray(Element, i16);

/// A skill's damage roll before its attribute, `lo` to `hi`, both included.
pub const Base = struct {
    lo: i32,
    hi: i32,

    pub fn roll(b: Base, rng: *mathx.Rng) i32 {
        return rng.range(b.lo, b.hi);
    }
};

/// The least and most a scaled roll deals.
pub const Span = struct { lo: i32, hi: i32 };
pub const PHYSICAL_FMT = "Physical damage: {d}-{d}";
pub const ELEMENT_FMT = "{s} damage: {d}-{d}";
pub const MIXED_FMT = "Damage: {d}-{d} physical, {d}-{d} {s}";

pub const Damage = struct {
    physical: i32 = 0,
    elements: std.EnumArray(Element, i32) = .initFill(0),

    pub fn total(self: Damage, resists: Resists) i32 {
        var sum: i64 = @max(0, self.physical);
        for (std.enums.values(Element)) |e| sum += resisted(self.elements.get(e), resists.get(e));
        return std.math.lossyCast(i32, sum);
    }

    pub fn reaches(self: Damage, resists: Resists, e: Element) bool {
        return resisted(self.elements.get(e), resists.get(e)) > 0;
    }

    /// Leaves a body on `hp` alive with some of its `e` got through, so `e`'s status may take.
    pub fn afflicts(self: Damage, resists: Resists, e: Element, hp: i32) bool {
        return self.total(resists) < hp and self.reaches(resists, e);
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
    return std.math.lossyCast(i32, @divTrunc(@as(i64, @max(0, amount)) * scale, mathx.PERCENT));
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
