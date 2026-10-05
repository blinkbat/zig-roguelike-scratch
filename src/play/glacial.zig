const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const fov = @import("../world/fov.zig");
const damage = @import("damage.zig");

const P = mathx.P;

pub const COST: i32 = 15;
pub const COLD_LO: i32 = 2;
pub const COLD_HI: i32 = 4;
pub const CHANCE: i32 = 50;
pub const TURNS: u8 = 3;
pub const RANGE: i32 = 2;
pub const CYCLE: u8 = 3;
pub const VERB = "frosts";
pub const DESCRIPTION = std.fmt.comptimePrint("{d}-{d} cold in a {d}-tile cone. {d}% chill (cold resistance lowers chance): skip 1 in {d} turns for {d} turns. {d} mana.", .{ COLD_LO, COLD_HI, RANGE, CHANCE, CYCLE, TURNS, COST });

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

pub fn roll(rng: *mathx.Rng) i32 {
    return rng.range(COLD_LO, COLD_HI);
}

pub fn chance(resist: i16) u32 {
    return @intCast(@min(mathx.PERCENT, damage.resisted(CHANCE, resist)));
}

pub fn procs(rng: *mathx.Rng, resist: i16) bool {
    return rng.percent(chance(resist));
}

pub const Cone = struct {
    cells: [(RANGE * 2 + 1) * (RANGE * 2 + 1)]P = undefined,
    n: usize = 0,

    pub fn has(self: *const Cone, p: P) bool {
        for (self.cells[0..self.n]) |c| {
            if (c.eq(p)) return true;
        }
        return false;
    }
};

pub fn cone(lv: *const grid.Level, from: P, impact: P) Cone {
    var out = Cone{};
    if (from.eq(impact)) return out;
    var visible: [grid.CELLS]bool = @splat(false);
    fov.castInto(lv, impact, RANGE * 2, &visible);
    const dx = impact.x - from.x;
    const dy = impact.y - from.y;
    var cells = grid.Cells.around(impact, RANGE);
    while (cells.next()) |p| {
        if (!lv.walkable(p) or !visible[grid.Level.idx(p)]) continue;
        const x = p.x - impact.x;
        const y = p.y - impact.y;
        const along = dx * x + dy * y;
        const across = dx * y - dy * x;
        if (!p.eq(impact) and (along <= 0 or @abs(across) > along)) continue;
        out.cells[out.n] = p;
        out.n += 1;
    }
    return out;
}

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
        const from = P{ .x = impact.x - d.x * 5, .y = impact.y - d.y * 5 };
        const area = cone(&lv, from, impact);
        try std.testing.expect(area.has(impact));
        try std.testing.expect(area.has(impact.add(.{ .x = d.x * 2, .y = d.y * 2 })));
        try std.testing.expect(!area.has(impact.add(.{ .x = -d.x, .y = -d.y })));
        for (area.cells[0..area.n]) |p| try std.testing.expect(mathx.dist(impact, p) <= RANGE);
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
