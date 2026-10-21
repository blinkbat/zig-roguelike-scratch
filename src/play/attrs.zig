const std = @import("std");
const mathx = @import("../core/mathx.zig");
const damage = @import("damage.zig");

pub const Attr = enum { strength, dexterity, intelligence };
pub const ATTRS = std.enums.values(Attr);
pub const Needs = std.enums.EnumFieldStruct(Attr, i32, 0);

/// What an item modifier adds to; a passive's `Kind` adds to these, a `Style`'s damage, crit, dodge or `Perks`.
pub const Bonus = enum {
    strength,
    dexterity,
    intelligence,
    life,
    mana,
    armour,

    /// How a grant of it reads, with its amount and `label`.
    pub const RAISE_FMT = "+{d} to {s}";

    /// What "+N to" raises.
    pub fn label(b: Bonus) [:0]const u8 {
        return switch (b) {
            .strength => "Strength",
            .dexterity => "Dexterity",
            .intelligence => "Intelligence",
            .life => "maximum life",
            .mana => "maximum mana",
            .armour => "Armour",
        };
    }
};
comptime {
    for (ATTRS) |at| _ = @field(Bonus, @tagName(at));
}
/// What a blow is, and so which attribute raises it.
pub const Style = enum {
    heavy,
    light,
    spell,

    pub fn attr(s: Style) Attr {
        return switch (s) {
            .heavy => .strength,
            .light => .dexterity,
            .spell => .intelligence,
        };
    }

    pub fn label(s: Style) [:0]const u8 {
        return switch (s) {
            .heavy => "Heavy weapon damage",
            .light => "Light weapon damage",
            .spell => "Spell damage",
        };
    }
};
pub const STYLES = std.enums.values(Style);

pub const Attack = enum {
    melee,
    ranged,
    spell,

    pub fn defaultStyle(a: Attack) Style {
        return switch (a) {
            .melee => .heavy,
            .ranged => .light,
            .spell => .spell,
        };
    }
};

const LIFE_BASE: i32 = 10;
const LIFE_PER_STR: i32 = 1;
const MANA_BASE: i32 = 80;
const MANA_PER_INT: i32 = 2;
/// Percent more damage of a style per point of its attribute.
const DAMAGE_PER_POINT: i32 = 1;
const CRIT_BASE: i32 = 5;
const DEX_PER_CRIT: i32 = 4;
/// Percent of the blow a critical strike deals.
pub const CRIT_MULTI: i32 = 150;
const DEX_PER_DODGE: i32 = 2;
pub const DODGE_MAX: i32 = 75;
/// Percent of a physical blow armour may take at most.
pub const ARMOUR_MAX: i32 = 75;

pub const Attrs = struct {
    points: std.EnumArray(Attr, i32),
    life_bonus: i32 = 0,
    mana_bonus: i32 = 0,
    armour: i32 = 0,
    damage_bonus: std.EnumArray(Style, i32) = .initFill(0),
    crit_bonus: i32 = 0,
    dodge_bonus: i32 = 0,

    pub fn of(points: std.enums.EnumFieldStruct(Attr, i32, null)) Attrs {
        return .{ .points = .init(points) };
    }

    pub fn get(a: Attrs, at: Attr) i32 {
        return a.points.get(at);
    }

    pub fn add(a: *Attrs, b: Bonus, n: i32) void {
        switch (b) {
            .life => a.life_bonus += n,
            .mana => a.mana_bonus += n,
            .armour => a.armour += n,
            inline else => |t| a.points.getPtr(@field(Attr, @tagName(t))).* += n,
        }
    }

    pub fn meets(a: Attrs, needs: Needs) bool {
        inline for (ATTRS) |at| if (a.get(at) < @field(needs, @tagName(at))) return false;
        return true;
    }

    pub fn life(a: Attrs) i32 {
        return LIFE_BASE + LIFE_PER_STR * a.get(.strength) + a.life_bonus;
    }

    pub fn mana(a: Attrs) i32 {
        return MANA_BASE + MANA_PER_INT * a.get(.intelligence) + a.mana_bonus;
    }

    /// Percent more damage its blows of `s` deal.
    pub fn increase(a: Attrs, s: Style) i32 {
        return DAMAGE_PER_POINT * a.get(s.attr()) + a.damage_bonus.get(s);
    }

    pub fn reduction(a: Attrs) i32 {
        return std.math.clamp(a.armour, 0, ARMOUR_MAX);
    }

    pub fn physical(a: Attrs, amount: i32, rng: *mathx.Rng) i32 {
        return Dealt.of(@as(i64, @max(0, amount)) * (mathx.PERCENT - a.reduction()) * mathx.PERCENT).roll(rng);
    }

    pub fn crit(a: Attrs) u32 {
        return @intCast(std.math.clamp(CRIT_BASE + @divTrunc(a.get(.dexterity), DEX_PER_CRIT) + a.crit_bonus, 0, mathx.PERCENT));
    }

    pub fn dodge(a: Attrs) u32 {
        return @intCast(std.math.clamp(@divTrunc(a.get(.dexterity), DEX_PER_DODGE) + a.dodge_bonus, 0, DODGE_MAX));
    }

    pub fn crits(a: Attrs, rng: *mathx.Rng) bool {
        return rng.percent(a.crit());
    }

    pub fn dodges(a: Attrs, rng: *mathx.Rng) bool {
        return rng.percent(a.dodge());
    }

    pub fn dealt(a: Attrs, s: Style, amount: i32, critical: bool) Dealt {
        return Dealt.of(@as(i64, @max(0, amount)) * @max(0, mathx.PERCENT + a.increase(s)) * @as(i64, if (critical) CRIT_MULTI else mathx.PERCENT));
    }

    /// What a `b` roll of `s` deals without a critical strike.
    pub fn span(a: Attrs, s: Style, b: damage.Base) damage.Span {
        return .{ .lo = a.dealt(s, b.lo, false).least(), .hi = a.dealt(s, b.hi, false).most() };
    }

    pub fn blow(a: Attrs, s: Style, d: damage.Damage, critical: bool, rng: *mathx.Rng) damage.Damage {
        var out = d;
        out.physical = a.dealt(s, d.physical, critical).roll(rng);
        for (&out.elements.values) |*v| v.* = a.dealt(s, v.*, critical).roll(rng);
        return out;
    }
};

const SHARE: u32 = mathx.PERCENT * mathx.PERCENT;

/// A scaled amount: `whole`, and one more `part` times in `SHARE`.
pub const Dealt = struct {
    whole: i32,
    part: u32,

    /// From an amount counted in `SHARE`ths.
    fn of(v: i64) Dealt {
        return .{ .whole = std.math.lossyCast(i32, @divTrunc(v, SHARE)), .part = @intCast(@mod(v, SHARE)) };
    }

    pub fn least(d: Dealt) i32 {
        return d.whole;
    }

    pub fn most(d: Dealt) i32 {
        return d.whole + @intFromBool(d.part > 0);
    }

    /// Rounded up as often as its fraction, so a small roll keeps its bonus on average.
    pub fn roll(d: Dealt, rng: *mathx.Rng) i32 {
        return d.whole + @intFromBool(d.part > 0 and rng.below(SHARE) < d.part);
    }
};

test "attributes raise life, mana, their own style's damage, crits and dodge" {
    const a = Attrs.of(.{ .strength = 20, .dexterity = 20, .intelligence = 10 });
    try std.testing.expectEqual(@as(i32, 30), a.life());
    try std.testing.expectEqual(@as(i32, 100), a.mana());
    try std.testing.expectEqual(Dealt{ .whole = 12, .part = 0 }, a.dealt(.heavy, 10, false));
    try std.testing.expectEqual(Dealt{ .whole = 11, .part = 0 }, a.dealt(.spell, 10, false));
    try std.testing.expectEqual(Dealt{ .whole = 18, .part = 0 }, a.dealt(.light, 10, true));
    try std.testing.expectEqual(damage.Span{ .lo = 2, .hi = 5 }, a.span(.heavy, .{ .lo = 2, .hi = 4 }));
    try std.testing.expectEqual(@as(u32, 10), a.crit());
    try std.testing.expectEqual(@as(u32, 10), a.dodge());
    try std.testing.expectEqual(@as(u32, DODGE_MAX), Attrs.of(.{ .strength = 0, .dexterity = 1000, .intelligence = 0 }).dodge());
    var rng = mathx.Rng.init(0xA77);
    const ROLLS = 10_000;
    var sum: i64 = 0;
    for (0..ROLLS) |_| {
        const v = a.dealt(.heavy, 2, false).roll(&rng);
        try std.testing.expect(v == 2 or v == 3);
        sum += v;
    }
    const mean = @as(f32, @floatFromInt(sum)) / ROLLS;
    try std.testing.expect(@abs(mean - 2.4) < 0.03);
    var hit = damage.Damage{ .physical = 10 };
    hit.elements.set(.fire, 20);
    const b = a.blow(.light, hit, false, &rng);
    try std.testing.expectEqual(@as(i32, 12), b.physical);
    try std.testing.expectEqual(@as(i32, 24), b.elements.get(.fire));
    std.debug.print("attributes 20/20/10: life {d}, mana {d}, crit {d}%, dodge {d}%; 2 heavy at +20% averages {d:.3} over {d} rolls\n", .{ a.life(), a.mana(), a.crit(), a.dodge(), mean, ROLLS });
}
