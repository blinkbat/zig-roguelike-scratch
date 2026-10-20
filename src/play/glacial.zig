const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const damage = @import("damage.zig");

const P = mathx.P;

pub const COST: i32 = 20;
pub const CHANCE: i32 = 50;
pub const TURNS: u8 = 3;
pub const RANGE: i32 = 2;
pub const CYCLE: u8 = 3;
pub const VERB = "frosts";
pub const TAKES = "is chilled";
pub const ELEMENT: damage.Element = .cold;
/// Its chance to chill, as every cold skill's description says it.
pub const CHILL_NOTE = std.fmt.comptimePrint("{d}% chill (cold resistance lowers chance)", .{CHANCE});
pub const DESCRIPTION = std.fmt.comptimePrint("An arrow bursts into a {d}-tile cone of cold. {s}: skip 1 in {d} turns for {d} turns.", .{ RANGE, CHILL_NOTE, CYCLE, TURNS });
pub const FLAVOR = "Winter, fletched and loosed.";

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
    return @intCast(@min(mathx.PERCENT, damage.resisted(CHANCE, resist)));
}

pub fn procs(rng: *mathx.Rng, resist: i16) bool {
    return rng.percent(chance(resist));
}

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.chill.apply();
}

/// The widest any burst reaches, this cone's, a fireball's or a nova's; `Burst` holds the cells of one.
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
    std.debug.assert(range <= BURST_MAX);
    var out = Burst{};
    var visible: [grid.CELLS]bool = @splat(false);
    fov.castInto(lv, at, castR(range), &visible);
    var cells = grid.Cells.around(at, range);
    while (cells.next()) |p| {
        if (lv.walkable(p) and visible[grid.Level.idx(p)] and keep(ctx, p)) out.push(p);
    }
    return out;
}

const Ahead = struct {
    impact: P,
    dx: i32,
    dy: i32,

    fn holds(a: Ahead, p: P) bool {
        if (p.eq(a.impact)) return true;
        const x = p.x - a.impact.x;
        const y = p.y - a.impact.y;
        const along = a.dx * x + a.dy * y;
        const across = a.dx * y - a.dy * x;
        return along > 0 and @abs(across) <= along;
    }
};

pub fn cone(lv: *const grid.Level, from: P, impact: P) Burst {
    if (from.eq(impact)) return .{};
    return spread(lv, impact, RANGE, Ahead{ .impact = impact, .dx = impact.x - from.x, .dy = impact.y - from.y }, Ahead.holds);
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
    std.debug.print("glacial cone: 8 directions plus oblique aim, 2-tile reach, wall occlusion, no sight changes\n", .{});
}
