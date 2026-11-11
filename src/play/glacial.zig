const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const areas = @import("area.zig");
const damage = @import("damage.zig");
const resilience = @import("resilience.zig");

const P = mathx.P;

pub const COST: i32 = 4;
pub const AILMENT = resilience.Kind.chill;
pub const CHANCE: u32 = 50;
pub const TURNS: u8 = 3;
pub const RANGE: i32 = 2;
pub const CYCLE: u8 = 3;
pub const VERB = "frosts";
pub const TAKES = "is chilled";
pub const ELEMENT: damage.Element = .cold;
pub const STATUS = std.fmt.comptimePrint("Lose 1 action in every {d}.", .{CYCLE});
pub const CHILL_NOTE = std.fmt.comptimePrint("{d}% chill chance", .{CHANCE});
pub const DESCRIPTION = std.fmt.comptimePrint("An arrow bursts into a {d}-tile cone of cold. {s}.", .{ RANGE, CHILL_NOTE });

pub const Chill = struct {
    turns: u8 = 0,
    phase: u8 = 0,

    pub fn apply(self: *Chill) void {
        if (self.turns == 0) self.phase = 0;
        self.turns = TURNS;
    }

    pub fn skip(self: *Chill) bool {
        if (!resilience.wearTurn(&self.turns)) return false;
        self.phase = (self.phase + 1) % CYCLE;
        return self.phase == 0;
    }
};

pub const BASE = damage.Base{ .lo = 2, .hi = 4 };

pub fn chance(resist: i16) u32 {
    return damage.resistedChance(CHANCE, resist);
}

pub fn procs(rng: *mathx.Rng, resist: i16) bool {
    return damage.procs(rng, chance(resist));
}

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.chill.apply();
}

comptime {
    std.debug.assert(RANGE <= areas.BURST_MAX);
}

const Ahead = struct {
    impact: P,
    heading: P,

    fn holds(a: Ahead, p: P) bool {
        return p.eq(a.impact) or mathx.ahead(a.impact, a.heading, p);
    }
};

pub fn cone(lv: *const grid.Level, from: P, impact: P, wider: i32) areas.Burst {
    if (from.eq(impact)) return .{};
    return areas.spread(lv, impact, RANGE + wider, Ahead{ .impact = impact, .heading = impact.sub(from) }, Ahead.holds);
}

pub const burst = cone;

test "chill skips one action in three and refreshing never postpones the skipped action" {
    var chill = Chill{};
    chill.apply();
    try std.testing.expect(!chill.skip());
    chill.apply();
    try std.testing.expect(!chill.skip());
    chill.apply();
    try std.testing.expect(chill.skip());
    try std.testing.expect(!chill.skip());
    try std.testing.expect(!chill.skip());
    try std.testing.expect(!chill.skip());
    chill.apply();
    var skipped: usize = 0;
    for (0..30) |_| {
        chill.apply();
        if (chill.skip()) skipped += 1;
    }
    try std.testing.expectEqual(@as(usize, 10), skipped);
}

test "cold resistance reduces chill probability independently of rounded cold damage" {
    try std.testing.expectEqual(@as(u32, 50), chance(0));
    try std.testing.expectEqual(@as(u32, 25), chance(50));
    try std.testing.expectEqual(@as(u32, 0), chance(100));
    try std.testing.expectEqual(@as(u32, 0), chance(200));
    try std.testing.expectEqual(@as(u32, 75), chance(-50));
    try std.testing.expectEqual(@as(u32, 100), chance(-200));
    var counts = [_]usize{ 0, 0, 0 };
    for ([_]i16{ 0, 50, 100 }, 0..) |resist, i| {
        var rng = mathx.Rng.init(812);
        for (0..1000) |_| {
            if (procs(&rng, resist)) counts[i] += 1;
        }
    }
    try std.testing.expect(counts[0] > 400 and counts[0] < 600);
    try std.testing.expect(counts[1] > 175 and counts[1] < 325);
    try std.testing.expectEqual(@as(usize, 0), counts[2]);
}

test "glacial cone follows cardinal diagonal and oblique shots and stops at walls without revealing cells" {
    var lv = grid.openFloor();
    const impact = P{ .x = 20, .y = 20 };
    for (mathx.ALL_DIRS) |dir| {
        const d = dir.delta();
        const from = impact.sub(d.scaled(5));
        const area = cone(&lv, from, impact, 0);
        try std.testing.expect(area.has(impact));
        try std.testing.expect(area.has(impact.add(d.scaled(2))));
        try std.testing.expect(!area.has(impact.sub(d)));
        for (area.slice()) |p| try std.testing.expect(mathx.dist(impact, p) <= RANGE);
    }
    const from = P{ .x = 15, .y = 18 };
    var area = cone(&lv, from, impact, 0);
    try std.testing.expect(area.has(.{ .x = 22, .y = 22 }));
    try std.testing.expect(!area.has(.{ .x = 22, .y = 18 }));
    try std.testing.expect(!cone(&lv, .{ .x = 15, .y = 20 }, impact, 0).has(.{ .x = 23, .y = 20 }));
    try std.testing.expect(cone(&lv, .{ .x = 15, .y = 20 }, impact, 1).has(.{ .x = 23, .y = 20 }));
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    area = cone(&lv, .{ .x = 15, .y = 20 }, impact, 0);
    try std.testing.expect(!area.has(.{ .x = 21, .y = 20 }));
    try std.testing.expect(!area.has(.{ .x = 22, .y = 20 }));
    try std.testing.expect(area.has(.{ .x = 21, .y = 21 }));
    for (lv.lit) |lit| try std.testing.expect(!lit);
}
