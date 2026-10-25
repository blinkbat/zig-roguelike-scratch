const std = @import("std");
const mathx = @import("../core/mathx.zig");
const wording = @import("../core/wording.zig");
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
            .strength => wording.named(Attr.strength),
            .dexterity => wording.named(Attr.dexterity),
            .intelligence => wording.named(Attr.intelligence),
            .life => "maximum life",
            .mana => "maximum mana",
            .armour => "Armour",
        };
    }
};
comptime {
    for (ATTRS) |at| _ = @field(Bonus, @tagName(at));
}
/// What `Attrs.reduction` and `Attrs.crit` are called.
pub const REDUCTION_LABEL = "physical damage reduction";
pub const CRIT_LABEL = "critical strike chance";
pub const WEAPON_CRIT_LABEL = "weapon critical chance";
pub const SPELL_CRIT_LABEL = "spell critical chance";
pub const PHYSICAL_LABEL = "physical damage";
pub const SCALES_FMT = "Scales with {s}";
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
const MANA_BASE: i32 = 16;
const MANA_PER_INT: i32 = 2;
const MANA_INT_DIVISOR: i32 = 5;
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

/// A physical blow of `amount` after `armour` takes its share.
pub fn armoured(armour: i32, amount: i32, rng: *mathx.Rng) i32 {
    return Dealt.of(@as(i64, @max(0, amount)) * (mathx.PERCENT - std.math.clamp(armour, 0, ARMOUR_MAX)) * mathx.PERCENT).roll(rng);
}

pub const Attrs = struct {
    points: std.EnumArray(Attr, i32),
    life_bonus: i32 = 0,
    mana_bonus: i32 = 0,
    armour: i32 = 0,
    damage_bonus: std.EnumArray(Style, i32) = .initFill(0),
    crit_bonus: i32 = 0,
    dodge_bonus: i32 = 0,
    weapon_crit_bonus: i32 = 0,
    spell_crit_bonus: i32 = 0,
    physical_bonus: i32 = 0,
    thorns: i32 = 0,
    gold_find: i32 = 0,
    item_rarity: i32 = 0,
    element_bonus: std.EnumArray(damage.Element, i32) = .initFill(0),
    resists: damage.Resists = .initFill(0),

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
        return MANA_BASE + @divTrunc(MANA_PER_INT * a.get(.intelligence), MANA_INT_DIVISOR) + a.mana_bonus;
    }

    /// Percent more damage its blows of `s` deal.
    pub fn increase(a: Attrs, s: Style) i32 {
        return DAMAGE_PER_POINT * a.get(s.attr()) + a.damage_bonus.get(s);
    }

    pub fn reduction(a: Attrs) i32 {
        return std.math.clamp(a.armour, 0, ARMOUR_MAX);
    }

    pub fn physical(a: Attrs, amount: i32, rng: *mathx.Rng) i32 {
        return armoured(a.armour, amount, rng);
    }

    pub fn collectedGold(a: Attrs, amount: i32, rng: *mathx.Rng) i32 {
        if (amount <= 0) return 0;
        const scaled = @as(i64, amount) * @max(0, 100 + @as(i64, a.gold_find));
        const whole = @divTrunc(scaled, 100);
        const fraction: u32 = @intCast(@mod(scaled, 100));
        const extra: i64 = @intFromBool(fraction > 0 and rng.percent(fraction));
        return @intCast(@min(std.math.maxInt(i32), whole + extra));
    }

    pub fn crit(a: Attrs) u32 {
        return a.critWith(0);
    }

    pub fn critWith(a: Attrs, extra: i32) u32 {
        return @intCast(std.math.clamp(CRIT_BASE + @divTrunc(a.get(.dexterity), DEX_PER_CRIT) + a.crit_bonus + extra, 0, mathx.PERCENT));
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
        return a.dealtWith(s, amount, critical, 0);
    }

    fn dealtWith(a: Attrs, s: Style, amount: i32, critical: bool, extra: i32) Dealt {
        return Dealt.of(@as(i64, @max(0, amount)) * @max(0, mathx.PERCENT + a.increase(s) + extra) * @as(i64, if (critical) CRIT_MULTI else mathx.PERCENT));
    }

    /// What a `b` roll of `s` deals without a critical strike.
    pub fn span(a: Attrs, s: Style, b: damage.Base) damage.Span {
        return a.spanWith(s, b, a.physical_bonus);
    }

    pub fn elementSpan(a: Attrs, s: Style, b: damage.Base, e: damage.Element) damage.Span {
        return a.spanWith(s, b, a.element_bonus.get(e));
    }

    fn spanWith(a: Attrs, s: Style, b: damage.Base, extra: i32) damage.Span {
        return .{ .lo = a.dealtWith(s, b.lo, false, extra).least(), .hi = a.dealtWith(s, b.hi, false, extra).most() };
    }

    pub fn blow(a: Attrs, s: Style, d: damage.Damage, critical: bool, rng: *mathx.Rng) damage.Damage {
        var out = d;
        out.physical = a.dealtWith(s, d.physical, critical, a.physical_bonus).roll(rng);
        for (std.enums.values(damage.Element)) |e| out.elements.set(e, a.dealtWith(s, d.elements.get(e), critical, a.element_bonus.get(e)).roll(rng));
        return out;
    }
};

const SHARE: u32 = mathx.BASIS_POINTS;

test "spoils gold rounds fractional coins fairly and preserves baseline rng" {
    var a = Attrs.of(.{ .strength = 0, .dexterity = 0, .intelligence = 0 });
    var rng = mathx.Rng.init(0x601D);
    const before = rng;
    try std.testing.expectEqual(@as(i32, 37), a.collectedGold(37, &rng));
    try std.testing.expectEqualDeep(before, rng);
    a.gold_find = 25;
    try std.testing.expectEqual(@as(i32, 25), a.collectedGold(20, &rng));
    var total: i32 = 0;
    for (0..10000) |_| total += a.collectedGold(1, &rng);
    try std.testing.expect(total > 12300 and total < 12700);
    try std.testing.expectEqual(@as(i32, 0), a.collectedGold(0, &rng));
    try std.testing.expectEqual(std.math.maxInt(i32), a.collectedGold(std.math.maxInt(i32), &rng));
    std.debug.print("Spoils gold: {d} from 10000 single coins at +25%; exact larger piles, zero and saturation checked\n", .{total});
}

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
    try std.testing.expectEqual(@as(i32, 20), a.mana());
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

test "physical and elemental base bonuses affect only their damage part and share preview bounds" {
    var a = Attrs.of(.{ .strength = 0, .dexterity = 0, .intelligence = 0 });
    a.physical_bonus = 10;
    a.element_bonus.set(.fire, 25);
    const raw = damage.Damage{ .physical = 20, .elements = .initFill(20) };
    var rng = mathx.Rng.init(443);
    const hit = a.blow(.spell, raw, false, &rng);
    try std.testing.expectEqual(@as(i32, 22), hit.physical);
    try std.testing.expectEqual(@as(i32, 25), hit.elements.get(.fire));
    try std.testing.expectEqual(@as(i32, 20), hit.elements.get(.cold));
    try std.testing.expectEqual(damage.Span{ .lo = 25, .hi = 25 }, a.elementSpan(.spell, .{ .lo = 20, .hi = 20 }, .fire));
    try std.testing.expectEqual(damage.Span{ .lo = 22, .hi = 22 }, a.span(.spell, .{ .lo = 20, .hi = 20 }));
    std.debug.print("damage parts: 20 becomes 22 physical, 25 fire, 20 cold/lightning/chaos; previews match\n", .{});
}
