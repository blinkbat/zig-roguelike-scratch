const std = @import("std");
const mathx = @import("../core/mathx.zig");

pub const Kind = enum { life, mana };
/// Percent more each flask's drink recovers.
pub const Bonus = std.enums.EnumFieldStruct(Kind, i32, 0);

pub const CHARGES: u8 = 60;
pub const USE: u8 = 20;
pub const PER_KILL: u8 = 5;
/// Recovery ticks: one on the drinking turn, then one per spent turn.
pub const TURNS: u8 = 3;
const LIFE_PCT: i32 = 50;
const TENTHS: i32 = 10;
pub const MANA_GAIN: i32 = 10;

pub const Life = struct {
    pub const KIND: Kind = .life;
    const TEXT = "Recover {d}{s}% of life.";
    pub const EFFECT = std.fmt.comptimePrint(TEXT[0 .. TEXT.len - 1], .{ LIFE_PCT, "" });
    pub const DESCRIPTION = EFFECT ++ ".";

    pub fn describe(w: anytype, bonus: Bonus) void {
        const tenths = lifeTenths(bonus.life);
        var part: [3]u8 = undefined;
        const fraction = if (@mod(tenths, TENTHS) == 0) "" else std.fmt.bufPrint(&part, ".{d}", .{@mod(tenths, TENTHS)}) catch unreachable;
        w.print(TEXT, .{ @divTrunc(tenths, TENTHS), fraction }) catch {};
    }
};

pub const Mana = struct {
    pub const KIND: Kind = .mana;
    const TEXT = "Recover {d} mana.";
    pub const EFFECT = std.fmt.comptimePrint(TEXT[0 .. TEXT.len - 1], .{MANA_GAIN});
    pub const DESCRIPTION = EFFECT ++ ".";

    pub fn describe(w: anytype, bonus: Bonus) void {
        w.print(TEXT, .{manaOf(bonus.mana)}) catch {};
    }
};

fn manaOf(bonus: i32) i32 {
    return mathx.percentOf(MANA_GAIN, mathx.PERCENT + bonus);
}

pub fn effect(k: Kind) [:0]const u8 {
    return switch (k) {
        .life => Life.EFFECT,
        .mana => Mana.EFFECT,
    };
}

pub const Flask = struct {
    charges: u8 = CHARGES,
    left: i32 = 0,
    turns: u8 = 0,

    pub fn full(self: Flask) bool {
        return self.charges >= USE;
    }

    /// Drunk again while recovering, it starts over on the new amount.
    pub fn drink(self: *Flask, amount: i32) void {
        std.debug.assert(self.full());
        self.charges -= USE;
        self.left = amount;
        self.turns = TURNS;
    }

    pub fn tick(self: *Flask) i32 {
        if (self.turns == 0) return 0;
        const n = std.math.divCeil(i32, self.left, self.turns) catch unreachable;
        self.left -= n;
        self.turns -= 1;
        return n;
    }

    pub fn mend(self: *Flask) void {
        self.charges = @min(self.charges, CHARGES);
        self.turns = @min(self.turns, TURNS);
        if (self.turns == 0) self.left = 0;
    }

    pub fn fill(self: *Flask, n: u8) void {
        self.charges = @min(CHARGES, self.charges +| n);
    }

    pub fn uses(self: Flask) u8 {
        return self.charges / USE;
    }
};

/// The share of life a drink recovers, in hundredths of a percent.
fn lifeShare(bonus: i32) i32 {
    return LIFE_PCT * (mathx.PERCENT + bonus);
}

fn lifeTenths(bonus: i32) i32 {
    return @divTrunc(lifeShare(bonus), TENTHS);
}

pub fn lifeOf(max: i32, bonus: i32) i32 {
    return std.math.lossyCast(i32, @divTrunc(@as(i64, max) * lifeShare(bonus), mathx.BASIS_POINTS));
}

pub fn recovers(k: Kind, max_life: i32, bonus: Bonus) i32 {
    return switch (k) {
        .life => lifeOf(max_life, bonus.life),
        .mana => manaOf(bonus.mana),
    };
}

test "a bonused drink scales the base recovery once, without truncating its share" {
    try std.testing.expectEqual(@as(i32, 625_000), lifeOf(1_000_000, 25));
    try std.testing.expectEqual(@as(i32, 25), lifeOf(40, 25));
    try std.testing.expectEqual(@as(i32, 125), lifeOf(200, 25));
    var buf: [128]u8 = undefined;
    var s = std.io.fixedBufferStream(&buf);
    Life.describe(s.writer(), .{ .life = 25 });
    try std.testing.expect(std.mem.startsWith(u8, s.getWritten(), "Recover 62.5% of life"));
}

test "a flask holds three drinks, each recovering its amount whole over three ticks, and kills refill it" {
    var f = Flask{};
    try std.testing.expectEqual(CHARGES / USE, f.uses());
    f.drink(lifeOf(24, 0));
    var total: i32 = 0;
    for (0..TURNS + 2) |_| total += f.tick();
    try std.testing.expectEqual(lifeOf(24, 0), total);
    f.drink(10);
    f.drink(10);
    try std.testing.expect(!f.full());
    for (0..USE / PER_KILL) |_| f.fill(PER_KILL);
    try std.testing.expect(f.full());
    for (0..100) |_| f.fill(PER_KILL);
    try std.testing.expectEqual(CHARGES, f.charges);
}
