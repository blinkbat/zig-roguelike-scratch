const std = @import("std");
const mathx = @import("../core/mathx.zig");

pub const Element = enum { cold, fire, chaos, lightning };

/// A skill's `procs` landing `pc` percent of the time, whatever the resistance; certain, it draws nothing.
pub fn chance(comptime pc: u32) fn (*mathx.Rng, i16) bool {
    if (pc >= mathx.PERCENT) return always;
    return struct {
        fn procs(rng: *mathx.Rng, _: i16) bool {
            return rng.percent(pc);
        }
    }.procs;
}

/// A skill's `chance` to afflict: `pc` percent whatever the resistance, as `chance(pc)` rolls it.
pub fn flat(comptime pc: u32) fn (i16) u32 {
    return struct {
        fn of(_: i16) u32 {
            return pc;
        }
    }.of;
}

/// `pc` percent cut by `resist` as its element's damage is, held to 0..100.
pub fn resistedChance(pc: u32, resist: i16) u32 {
    return @intCast(@min(mathx.PERCENT, resisted(std.math.lossyCast(i32, pc), resist)));
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
            _ = begin(self, TURNS);
        }

        pub fn tick(self: *@This(), arg: Arg) ?i32 {
            return if (due(self)) amount(arg) else null;
        }

        /// The turn it started in is over, whether or not its tick ran.
        pub fn settle(self: *@This()) void {
            self.fresh = false;
        }
    };
}

/// Starts or refreshes a lasting harm's `turns` and `fresh`; true when it was not already running.
pub fn begin(self: anytype, turns: u8) bool {
    const new = self.turns == 0;
    if (new) self.fresh = true;
    self.turns = turns;
    return new;
}

/// Spends one of a lasting harm's turns, unless it started this turn: whether it harms now.
pub fn due(self: anytype) bool {
    if (self.turns == 0) return false;
    if (self.fresh) {
        self.fresh = false;
        return false;
    }
    self.turns -= 1;
    return true;
}

/// Resistances, elemental and to statuses alike, run from -100% to 100%.
pub const RESIST_MAX: i16 = mathx.PERCENT;

pub fn clampResist(v: i32) i16 {
    return @intCast(std.math.clamp(v, -RESIST_MAX, RESIST_MAX));
}

pub fn resisted(amount: i32, resist: i16) i32 {
    const scale: i64 = mathx.PERCENT - @as(i64, clampResist(resist));
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
    std.debug.print("{d} elemental resistances checked: 50% of 20 = 10, physical damage unchanged\n", .{std.enums.values(Element).len});
}

test "damage floors each element separately clamps resistance and saturates large totals" {
    const Case = struct { amount: i32, resist: i16, want: i32 };
    const cases = [_]Case{
        .{ .amount = 3, .resist = 50, .want = 1 },
        .{ .amount = 1, .resist = 1, .want = 0 },
        .{ .amount = 3, .resist = -50, .want = 4 },
        .{ .amount = 3, .resist = -101, .want = 6 },
        .{ .amount = 3, .resist = 101, .want = 0 },
        .{ .amount = 0, .resist = -100, .want = 0 },
        .{ .amount = -3, .resist = -100, .want = 0 },
        .{ .amount = std.math.maxInt(i32), .resist = -100, .want = std.math.maxInt(i32) },
    };
    for (cases) |c| try std.testing.expectEqual(c.want, resisted(c.amount, c.resist));
    const tiny = Damage{ .physical = -5, .elements = .initFill(1) };
    try std.testing.expectEqual(@as(i32, 0), tiny.total(.initFill(50)));
    const large = Damage{ .physical = std.math.maxInt(i32), .elements = .initFill(std.math.maxInt(i32)) };
    try std.testing.expectEqual(std.math.maxInt(i32), large.total(.initFill(-100)));
    std.debug.print("damage boundaries: {d} explicit cases, per-element rounding and saturated mixed totals checked\n", .{cases.len});
}

test "elemental statuses require penetrating damage and a surviving target" {
    var checks: usize = 0;
    for (std.enums.values(Element)) |element| {
        const hit = Damage{ .physical = 3 };
        var elemental = hit;
        elemental.elements.set(element, 2);
        const clear = Resists.initFill(0);
        try std.testing.expect(elemental.afflicts(clear, element, 6));
        try std.testing.expect(!elemental.afflicts(clear, element, 5));
        try std.testing.expect(!elemental.afflicts(clear, element, 4));
        var immune = clear;
        immune.set(element, 100);
        try std.testing.expect(!elemental.afflicts(immune, element, 20));
        try std.testing.expect(!hit.afflicts(clear, element, 20));
        elemental.elements.set(element, 1);
        immune.set(element, 50);
        try std.testing.expect(!elemental.afflicts(immune, element, 20));
        checks += 6;
    }
    std.debug.print("elemental status eligibility: {d} survival, lethal, immune, absent and rounded-away cases checked\n", .{checks});
}
