const std = @import("std");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const resilience = @import("resilience.zig");
const attrs = @import("attrs.zig");
const mathx = @import("../core/mathx.zig");
const wording = @import("../core/wording.zig");

pub const Modifiers = struct {
    hit: i16 = 0,
    dodge: i16 = 0,
    elements: damage.Resists = .initFill(0),
    statuses: std.EnumArray(resilience.Kind, i16) = .initFill(0),

    pub fn with(a: Modifiers, b: Modifiers) Modifiers {
        var out = a;
        out.hit +|= b.hit;
        out.dodge +|= b.dodge;
        for (&out.elements.values, b.elements.values) |*x, y| x.* +|= y;
        for (&out.statuses.values, b.statuses.values) |*x, y| x.* +|= y;
        return out;
    }

    pub fn write(self: Modifiers, w: anytype) void {
        var shown = false;
        if (self.hit != 0) {
            w.print("\n{s}{d}% Hit Chance", .{ sign(self.hit), self.hit }) catch {};
            shown = true;
        }
        if (self.dodge != 0) {
            w.print("\n{s}{d}% Dodge Chance", .{ sign(self.dodge), self.dodge }) catch {};
            shown = true;
        }
        for (std.enums.values(damage.Element)) |e| {
            const n = self.elements.get(e);
            if (n != 0) {
                w.print("\n{s}{d}% {s} Resistance", .{ sign(n), n, wording.titleOf(e) }) catch {};
                shown = true;
            }
        }
        for (std.enums.values(resilience.Kind)) |k| {
            const n = -self.statuses.get(k);
            if (n != 0) {
                const label = switch (k) {
                    .stun => "Chance To Be Stunned",
                    .burn => "Chance To Burn",
                    .bleed => "Chance To Bleed",
                    .chill => "Chance To Be Chilled",
                    .pin => "Chance To Be Pinned",
                    .shock => "Chance To Be Shocked",
                    .sunder => "Chance To Be Sundered",
                    .blind => "Chance To Be Blinded",
                    .confusion => "Chance To Be Confused",
                    .enfeeble => "Chance To Be Enfeebled",
                    .maim => "Chance To Be Maimed",
                    .fright => "Chance To Be Frightened",
                };
                w.print("\n{s}{d}% {s}", .{ sign(n), n, label }) catch {};
                shown = true;
            }
        }
        if (!shown) w.writeAll("\nNo Effects") catch {};
    }
};

fn sign(n: i16) []const u8 {
    return if (n > 0) "+" else "";
}

const WET = Modifiers{
    .elements = .initDefault(0, .{ .lightning = -25, .fire = 25 }),
    .statuses = .initDefault(0, .{ .burn = 25 }),
};
const GRASS = Modifiers{
    .elements = .initDefault(0, .{ .fire = -15 }),
    .statuses = .initDefault(0, .{ .burn = -15 }),
};

pub const EFFECTS = std.EnumArray(grid.Tile, Modifiers).initDefault(.{}, .{
    .reeds = .{ .hit = -5, .dodge = 5 },
    .water = WET,
    .shallows = WET,
    .grass = GRASS,
    .tall_grass = GRASS,
});

comptime {
    for (std.enums.values(grid.Tile)) |t| std.debug.assert(t.wet() == std.meta.eql(EFFECTS.get(t), WET));
}

pub fn of(tile: grid.Tile) Modifiers {
    return EFFECTS.get(tile);
}

/// At the heaviest rain, the fire and burn resistance it lends whatever stands out in it.
const RAIN_FIRE: f32 = 30;
const RAIN_BURN: f32 = 40;
/// Rain's resistances move in steps of this, so a card reads whole fives.
const RAIN_STEP: f32 = 5;
/// Rain below these reads as a drizzle, then as rain; heavier is a downpour.
const DRIZZLE_BELOW: f32 = 0.34;
const RAIN_BELOW: f32 = 0.67;

/// Out in rain of `rain`, 0 none to 1 a downpour.
pub fn rained(rain: f32) Modifiers {
    const r = std.math.clamp(rain, 0, 1);
    return .{
        .elements = .initDefault(0, .{ .fire = stepped(RAIN_FIRE * r) }),
        .statuses = .initDefault(0, .{ .burn = stepped(RAIN_BURN * r) }),
    };
}

fn stepped(v: f32) i16 {
    return @intFromFloat(@round(v / RAIN_STEP) * RAIN_STEP);
}

/// Null when `rain` lends nothing.
pub fn rainTitle(rain: f32) ?[]const u8 {
    if (std.meta.eql(rained(rain), Modifiers{})) return null;
    return if (rain < DRIZZLE_BELOW) "Drizzle" else if (rain < RAIN_BELOW) "Rain" else "Downpour";
}

pub const Stats = struct {
    hit: u32 = mathx.PERCENT,
    dodge: u32 = 0,
    /// Before the cap `attrs.armoured` applies.
    armour: i32 = 0,
    elements: damage.Resists = .initFill(0),
    statuses: std.EnumArray(resilience.Kind, i16) = .initFill(0),

    /// On `tile` out in rain of `rain`, the two summed before the caps.
    pub fn onRained(base: Stats, tile: grid.Tile, rain: f32) Stats {
        return base.plus(of(tile).with(rained(rain)));
    }

    pub fn plus(base: Stats, m: Modifiers) Stats {
        var out = base;
        out.hit = @intCast(std.math.clamp(@as(i32, @intCast(base.hit)) + m.hit, 0, mathx.PERCENT));
        out.dodge = @intCast(std.math.clamp(@as(i32, @intCast(base.dodge)) + m.dodge, 0, attrs.DODGE_MAX));
        for (std.enums.values(damage.Element)) |e| out.elements.set(e, damage.clampResist(@as(i32, base.elements.get(e)) + m.elements.get(e)));
        for (std.enums.values(resilience.Kind)) |k| out.statuses.set(k, damage.clampResist(@as(i32, base.statuses.get(k)) + m.statuses.get(k)));
        return out;
    }

    pub fn misses(attacker: Stats, defender: Stats, rng: *mathx.Rng) bool {
        if (attacker.hit < mathx.PERCENT and (attacker.hit == 0 or !rng.percent(attacker.hit))) return true;
        return defender.dodge > 0 and rng.percent(defender.dodge);
    }
};

test "terrain resolves signed modifiers after base stats without mutating them" {
    var base = Stats{ .dodge = 74, .elements = .initFill(90), .statuses = .initFill(25) };
    const original = base;
    const reeds = base.onRained(.reeds, 0);
    try std.testing.expectEqual(@as(u32, 95), reeds.hit);
    try std.testing.expectEqual(@as(u32, 75), reeds.dodge);
    const water = base.onRained(.shallows, 0);
    try std.testing.expectEqual(@as(i16, 100), water.elements.get(.fire));
    try std.testing.expectEqual(@as(i16, 65), water.elements.get(.lightning));
    try std.testing.expectEqual(@as(i16, 50), water.statuses.get(.burn));
    const grass = base.onRained(.grass, 0);
    try std.testing.expectEqual(@as(i16, 75), grass.elements.get(.fire));
    try std.testing.expectEqual(@as(i16, 10), grass.statuses.get(.burn));
    try std.testing.expectEqual(@as(i16, -15), (Stats{}).onRained(.grass, 0).statuses.get(.burn));
    try std.testing.expectEqualDeep(original, base);
    try std.testing.expectEqualDeep(base, base.onRained(.floor, 0));
    base.elements.set(.fire, -100);
    try std.testing.expectEqual(@as(i16, -100), base.onRained(.grass, 0).elements.get(.fire));
    std.debug.print("terrain: hit/dodge, {d} elements, {d} statuses, caps and neutral ground checked\n", .{ std.enums.values(damage.Element).len, std.enums.values(resilience.Kind).len });
}

test "rain lends fire and burn resistance in fives, more the harder it falls, and nothing dry" {
    try std.testing.expectEqualDeep(Modifiers{}, rained(0));
    try std.testing.expectEqual(@as(?[]const u8, null), rainTitle(0));
    var fire_was: i16 = 0;
    var burn_was: i16 = 0;
    var r: f32 = 0;
    while (r <= 1) : (r += 0.01) {
        const m = rained(r);
        try std.testing.expect(m.elements.get(.fire) >= fire_was and m.statuses.get(.burn) >= burn_was);
        try std.testing.expectEqual(@as(i16, 0), @rem(m.elements.get(.fire), 5));
        fire_was = m.elements.get(.fire);
        burn_was = m.statuses.get(.burn);
    }
    const drizzle = rained(@import("../map/climate.zig").DRIZZLE);
    std.debug.print("rain: a drizzle lends +{d}% fire / +{d}% burn resistance, a downpour +{d}% / +{d}%\n", .{ drizzle.elements.get(.fire), drizzle.statuses.get(.burn), fire_was, burn_was });
    try std.testing.expectEqualStrings("Downpour", rainTitle(1).?);
    const soaked = (Stats{}).onRained(.shallows, 1);
    try std.testing.expectEqual(@as(i16, 55), soaked.elements.get(.fire));
    const capped = (Stats{ .elements = .initFill(90) }).onRained(.grass, 1);
    try std.testing.expectEqual(@as(i16, 100), capped.elements.get(.fire));
}
