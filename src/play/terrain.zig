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

pub fn of(tile: grid.Tile) Modifiers {
    return EFFECTS.get(tile);
}

pub const Stats = struct {
    hit: u32 = 100,
    dodge: u32 = 0,
    /// Before the cap `attrs.armoured` applies.
    armour: i32 = 0,
    elements: damage.Resists = .initFill(0),
    statuses: std.EnumArray(resilience.Kind, i16) = .initFill(0),

    pub fn on(base: Stats, tile: grid.Tile) Stats {
        const m = of(tile);
        var out = base;
        out.hit = @intCast(std.math.clamp(@as(i32, @intCast(base.hit)) + m.hit, 0, 100));
        out.dodge = @intCast(std.math.clamp(@as(i32, @intCast(base.dodge)) + m.dodge, 0, attrs.DODGE_MAX));
        for (std.enums.values(damage.Element)) |e| out.elements.set(e, @intCast(std.math.clamp(@as(i32, base.elements.get(e)) + m.elements.get(e), -100, 100)));
        for (std.enums.values(resilience.Kind)) |k| out.statuses.set(k, @intCast(std.math.clamp(@as(i32, base.statuses.get(k)) + m.statuses.get(k), -100, 100)));
        return out;
    }

    pub fn misses(attacker: Stats, defender: Stats, rng: *mathx.Rng) bool {
        if (attacker.hit < 100 and (attacker.hit == 0 or !rng.percent(attacker.hit))) return true;
        return defender.dodge > 0 and rng.percent(defender.dodge);
    }
};

test "terrain resolves signed modifiers after base stats without mutating them" {
    var base = Stats{ .dodge = 74, .elements = .initFill(90), .statuses = .initFill(25) };
    const original = base;
    const reeds = base.on(.reeds);
    try std.testing.expectEqual(@as(u32, 95), reeds.hit);
    try std.testing.expectEqual(@as(u32, 75), reeds.dodge);
    const water = base.on(.shallows);
    try std.testing.expectEqual(@as(i16, 100), water.elements.get(.fire));
    try std.testing.expectEqual(@as(i16, 65), water.elements.get(.lightning));
    try std.testing.expectEqual(@as(i16, 50), water.statuses.get(.burn));
    const grass = base.on(.grass);
    try std.testing.expectEqual(@as(i16, 75), grass.elements.get(.fire));
    try std.testing.expectEqual(@as(i16, 10), grass.statuses.get(.burn));
    try std.testing.expectEqual(@as(i16, -15), (Stats{}).on(.grass).statuses.get(.burn));
    try std.testing.expectEqualDeep(original, base);
    try std.testing.expectEqualDeep(base, base.on(.floor));
    base.elements.set(.fire, -100);
    try std.testing.expectEqual(@as(i16, -100), base.on(.grass).elements.get(.fire));
    std.debug.print("terrain: hit/dodge, {d} elements, {d} statuses, caps and neutral ground checked\n", .{ std.enums.values(damage.Element).len, std.enums.values(resilience.Kind).len });
}
