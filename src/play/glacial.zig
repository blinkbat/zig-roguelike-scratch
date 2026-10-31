const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const damage = @import("damage.zig");

const P = mathx.P;

pub const COST: i32 = 4;
pub const AILMENT = @import("resilience.zig").Kind.chill;
pub const CHANCE: u32 = 50;
pub const TURNS: u8 = 3;
pub const RANGE: i32 = 2;
pub const CYCLE: u8 = 3;
pub const VERB = "frosts";
pub const TAKES = "is chilled";
pub const ELEMENT: damage.Element = .cold;
pub const STATUS = std.fmt.comptimePrint("Lose 1 action in every {d}.", .{CYCLE});
/// Its chance to chill, as every cold skill's description says it.
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
        if (self.turns == 0) return false;
        self.turns -= 1;
        self.phase = (self.phase + 1) % CYCLE;
        return self.phase == 0;
    }
};

pub const BASE = damage.Base{ .lo = 2, .hi = 4 };

pub fn chance(resist: i16) u32 {
    return damage.resistedChance(CHANCE, resist);
}

pub fn procs(rng: *mathx.Rng, resist: i16) bool {
    return rng.percent(chance(resist));
}

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.chill.apply();
}

/// The widest any burst, patch or spread reaches; `Burst` holds the cells of one.
pub const BURST_MAX: i32 = 2;
pub const Burst = grid.Area(grid.Cells.square(BURST_MAX));

fn castR(range: i32) i32 {
    return mathx.roundTiesDown(@as(f32, @floatFromInt(range)) * std.math.sqrt2);
}

comptime {
    std.debug.assert(RANGE <= BURST_MAX);
    for (1..BURST_MAX + 1) |r| std.debug.assert(mathx.reaches(.{ .x = 0, .y = 0 }, .{ .x = r, .y = r }, castR(r)));
}

/// The walkable cells within `range` of `at` that a burst there reaches past the terrain, those `keep` takes.
pub fn spread(lv: *const grid.Level, at: P, range: i32, ctx: anytype, comptime keep: fn (@TypeOf(ctx), P) bool) Burst {
    return reached(lv, at, range, grid.Level.walkable, ctx, keep);
}

/// The deep water and shallows within `range` of `at` that a burst there reaches, though no body could stand in the deep.
pub fn wetIn(lv: *const grid.Level, at: P, range: i32) Burst {
    return reached(lv, at, range, wet, {}, every);
}

fn wet(lv: *const grid.Level, p: P) bool {
    return lv.at(p).wet();
}

fn reached(lv: *const grid.Level, at: P, range: i32, comptime ground: fn (*const grid.Level, P) bool, ctx: anytype, comptime keep: fn (@TypeOf(ctx), P) bool) Burst {
    std.debug.assert(range <= BURST_MAX);
    var out = Burst{};
    var visible: [grid.CELLS]bool = @splat(false);
    fov.castInto(lv, at, castR(range), &visible);
    var cells = grid.Cells.around(at, range);
    while (cells.next()) |p| {
        if (!ground(lv, p)) continue;
        const k = grid.Level.idx(p);
        if (visible[k] and keep(ctx, p)) out.push(p);
    }
    return out;
}

/// Every cell `spread` reaches within `range` of `at`.
pub fn patch(lv: *const grid.Level, at: P, range: i32) Burst {
    return spread(lv, at, range, {}, every);
}

pub fn Patch(comptime range: i32) type {
    comptime std.debug.assert(range <= BURST_MAX);
    return struct {
        pub fn area(lv: *const grid.Level, at: P) Burst {
            return patch(lv, at, range);
        }

        pub fn burst(lv: *const grid.Level, _: P, impact: P) Burst {
            return patch(lv, impact, range);
        }
    };
}

pub fn every(_: void, _: P) bool {
    return true;
}

const Ahead = struct {
    impact: P,
    heading: P,

    fn holds(a: Ahead, p: P) bool {
        return p.eq(a.impact) or mathx.ahead(a.impact, a.heading, p);
    }
};

pub fn cone(lv: *const grid.Level, from: P, impact: P) Burst {
    if (from.eq(impact)) return .{};
    return spread(lv, impact, RANGE, Ahead{ .impact = impact, .heading = impact.sub(from) }, Ahead.holds);
}

/// What its arrow bursts into where it strikes.
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
    std.debug.print("chill: {d}/30 actions skipped under repeated refreshes; expires after {d} turns\n", .{ skipped, TURNS });
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
    std.debug.print("chill procs per 1000 at 0/50/100% cold resistance: {d}/{d}/{d}\n", .{ counts[0], counts[1], counts[2] });
}

test "glacial cone follows cardinal diagonal and oblique shots and stops at walls without revealing cells" {
    var lv = grid.openFloor();
    const impact = P{ .x = 20, .y = 20 };
    for (mathx.ALL_DIRS) |dir| {
        const d = dir.delta();
        const from = impact.sub(d.scaled(5));
        const area = cone(&lv, from, impact);
        try std.testing.expect(area.has(impact));
        try std.testing.expect(area.has(impact.add(d.scaled(2))));
        try std.testing.expect(!area.has(impact.sub(d)));
        for (area.slice()) |p| try std.testing.expect(mathx.dist(impact, p) <= RANGE);
    }
    const from = P{ .x = 15, .y = 18 };
    var area = cone(&lv, from, impact);
    try std.testing.expect(area.has(.{ .x = 22, .y = 22 }));
    try std.testing.expect(!area.has(.{ .x = 22, .y = 18 }));
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    area = cone(&lv, .{ .x = 15, .y = 20 }, impact);
    try std.testing.expect(!area.has(.{ .x = 21, .y = 20 }));
    try std.testing.expect(!area.has(.{ .x = 22, .y = 20 }));
    try std.testing.expect(area.has(.{ .x = 21, .y = 21 }));
    for (lv.lit) |lit| try std.testing.expect(!lit);
    std.debug.print("glacial cone: {d} directions plus oblique aim, {d}-tile reach, wall occlusion, no sight changes\n", .{ mathx.ALL_DIRS.len, RANGE });
}

test "a burst's wet cells take the deep water round it as well as the shallows a patch takes, and none past a wall" {
    var lv = grid.openFloor();
    const at = P{ .x = 20, .y = 20 };
    const deep = P{ .x = 19, .y = 20 };
    const shallow = P{ .x = 20, .y = 21 };
    const walled = P{ .x = 22, .y = 20 };
    lv.set(deep, .water);
    lv.set(shallow, .shallows);
    lv.set(walled, .water);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    const near = wetIn(&lv, at, 1);
    try std.testing.expectEqual(@as(usize, 2), near.n);
    try std.testing.expect(near.has(deep) and near.has(shallow));
    const area = patch(&lv, at, 1);
    try std.testing.expect(!area.has(deep) and area.has(shallow));
    try std.testing.expect(!wetIn(&lv, at, 2).has(walled));
}
