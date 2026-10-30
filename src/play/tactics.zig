const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const glacial = @import("glacial.zig");
const bow = @import("bow.zig");
const P = mathx.P;

pub const Caltrops = struct {
    pub const COST: i32 = 4;
    pub const COOLDOWN: u8 = 5;
    pub const RANGE: i32 = 5;
    pub const DESCRIPTION = "Scatter caltrops that pin entering foes.";
    pub fn duration(rank: u8) u8 {
        return 4 + rank;
    }
    /// What a patch's cells are laid with.
    pub fn laid(rank: u8) u8 {
        return duration(rank) + 1;
    }
    pub fn pins(rank: u8) u8 {
        return 1 + @as(u8, @intFromBool(rank == TOP_RANK));
    }
    pub fn bleed(rank: u8) i32 {
        return rank -| 1;
    }
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, 1);
    }
    pub fn writeRank(rank: u8, w: anytype) void {
        w.print("Patch: {d} turns; pin: {d} turn(s); ", .{ duration(rank), pins(rank) }) catch {};
        if (bleed(rank) == 0) w.writeAll("no bleed.") catch {} else w.print("bleed: {d} per turn.", .{bleed(rank)}) catch {};
    }
};
pub const Overwatch = struct {
    pub const RANGE = bow.RANGE;
    pub const COST: i32 = 4;
    pub const COOLDOWN: u8 = 3;
    pub const VERB = "shoots on overwatch";
    pub const DESCRIPTION = "Cover a direction until your next action. Shoot the first foe moving into its cone.";
    pub const BASE = bow.BASE;
};
pub const SteadyAim = struct {
    pub const COST: i32 = 2;
    pub const DESCRIPTION = "Prepare your next arrow for increased damage and critical chance. Movement cancels preparation.";
    pub fn bonus(rank: u8) i32 {
        return 15 + 15 * @as(i32, @max(1, rank));
    }
    pub fn critical(rank: u8) i32 {
        return 5 + 5 * @as(i32, @max(1, rank));
    }
    pub fn writeRank(rank: u8, w: anytype) void {
        w.print("Next arrow: +{d}% damage, +{d}% critical chance.", .{ bonus(rank), critical(rank) }) catch {};
    }
};
pub const GravityWell = struct {
    pub const COST: i32 = 6;
    pub const COOLDOWN: u8 = 5;
    pub const RANGE: i32 = 6;
    pub const RADIUS: i32 = 2;
    pub const DESCRIPTION = std.fmt.comptimePrint("Pull foes within {d} cells toward a visible center.", .{RADIUS});
    pub fn pulls(rank: u8) usize {
        return if (rank == TOP_RANK) 2 else 1;
    }
    pub fn pins(rank: u8) u8 {
        return rank -| 1;
    }
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, RADIUS);
    }
    pub fn writeRank(rank: u8, w: anytype) void {
        w.print("Pull: {d} cell(s); pin: {d} turn(s).", .{ pulls(rank), pins(rank) }) catch {};
    }
};
pub const Combustion = struct {
    pub const COST: i32 = 5;
    pub const COOLDOWN: u8 = 3;
    pub const RANGE: i32 = 7;
    pub const VERB = "detonates";
    pub const ELEMENT = damage.Element.fire;
    pub const BASE = damage.Base{ .lo = 5, .hi = 8 };
    pub const DESCRIPTION = std.fmt.comptimePrint("Consume a visible foe's burn. Explode it and its neighbors for fire damage, adding {d} damage per remaining burn turn.", .{FUEL_DAMAGE});
    pub const FUEL_DAMAGE: i32 = 2;
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, 1);
    }
};
pub const ArcaneBarrier = struct {
    pub const COST: i32 = 6;
    pub const COOLDOWN: u8 = 6;
    pub const RANGE: i32 = 6;
    pub const DESCRIPTION = "Choose two endpoints to raise a straight arcane wall. Blocks movement and projectiles, allows sight. Cannot cover bodies, props or doors.";
    pub fn length(rank: u8) usize {
        return 2 + @as(usize, @max(1, rank));
    }
    pub fn duration(rank: u8) u8 {
        return 3 + @max(1, rank);
    }
    /// What a wall's cells are laid with.
    pub fn laid(rank: u8) u8 {
        return duration(rank) + 1;
    }
    pub fn writeRank(rank: u8, w: anytype) void {
        w.print("Wall: up to {d} cells, {d} turns.", .{ length(rank), duration(rank) }) catch {};
    }
};
pub const Shatter = struct {
    pub const COST: i32 = 5;
    pub const COOLDOWN: u8 = 3;
    pub const RANGE: i32 = 7;
    pub const VERB = "shatters";
    pub const ELEMENT = damage.Element.cold;
    pub const BASE = damage.Base{ .lo = 5, .hi = 8 };
    pub const DESCRIPTION = std.fmt.comptimePrint("Consume a visible foe's chill. Shatter it and its neighbors for cold damage, adding {d} damage per remaining chill turn.", .{FUEL_DAMAGE});
    pub const FUEL_DAMAGE: i32 = 2;
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, 1);
    }
};
pub const FireWall = struct {
    pub const COST: i32 = 6;
    pub const COOLDOWN: u8 = 5;
    pub const RANGE = ArcaneBarrier.RANGE;
    pub const DESCRIPTION = "Choose two endpoints to set a straight line of ground ablaze. Foes shun the flames; any that enter them, or stand there as they rise, catch fire. Cannot cover water, props or doors.";
    pub const length = ArcaneBarrier.length;
    pub const duration = ArcaneBarrier.duration;
    /// What its flames are laid with.
    pub const laid = ArcaneBarrier.laid;
    pub fn writeRank(rank: u8, w: anytype) void {
        w.print("Flames: up to {d} cells, {d} turns.", .{ length(rank), duration(rank) }) catch {};
    }
};
pub const WarCry = struct {
    pub const COST: i32 = 4;
    pub const COOLDOWN: u8 = 5;
    pub const RADIUS: i32 = 3;
    pub const DESCRIPTION = std.fmt.comptimePrint("Each visible foe within {d} tiles may be frightened and run from you.", .{RADIUS});
    pub fn chance(rank: u8) u32 {
        return 40 + 15 * @as(u32, @max(1, rank));
    }
    pub fn turns(rank: u8) u8 {
        return 2 + @max(1, rank);
    }
    pub fn writeRank(rank: u8, w: anytype) void {
        w.print("{d}% fright chance; frightened {d} turns.", .{ chance(rank), turns(rank) }) catch {};
    }
};
pub const Guard = struct {
    pub const COST: i32 = 2;
    pub const DESCRIPTION = "Reduce incoming physical attack damage until your next action.";
    pub fn reduction(rank: u8) i32 {
        return 40 + 10 * @as(i32, @max(1, rank));
    }
    /// `dmg` as guarding at `rank` lets it through, rounded up.
    pub fn reduce(rank: u8, dmg: i32) i32 {
        return @intCast(@divTrunc(@as(i64, dmg) * (mathx.PERCENT - reduction(rank)) + mathx.PERCENT - 1, mathx.PERCENT));
    }
    pub fn writeRank(rank: u8, w: anytype) void {
        w.print("{d}% less physical attack damage.", .{reduction(rank)}) catch {};
    }
};
pub const Whirlwind = struct {
    pub const COST: i32 = 5;
    pub const COOLDOWN: u8 = 3;
    pub const VERB = "whirls into";
    pub const BASE = damage.Base{ .lo = 2, .hi = 4 };
    pub const DESCRIPTION = "Strike every adjacent foe and barrel with your melee weapon.";
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, 1);
    }
};
pub const Unyielding = struct {
    pub const COST: i32 = 2;
    pub const VERB = "counters";
    pub const DESCRIPTION = "Counter adjacent melee attackers. Toggle the stance; ends when mana runs out.";
    pub const DRAIN: i32 = 2;
    pub fn chance(rank: u8) u32 {
        return 15 + 10 * @as(u32, @max(1, rank));
    }
    pub fn writeRank(rank: u8, w: anytype) void {
        w.print("{d}% counter chance; {d} mana per turn.", .{ chance(rank), DRAIN }) catch {};
    }
};

pub const State = struct {
    steady: u8 = 0,
    guard: u8 = 0,
    unyielding: bool = false,
    overwatch: ?mathx.Dir = null,
};

pub const patch = glacial.patch;
pub fn covered(from: P, dir: mathx.Dir, at: P) bool {
    return mathx.ahead(from, dir.delta(), at);
}
const TOP_RANK = @import("progress.zig").RANKS;
pub const Wall = grid.Area(@max(ArcaneBarrier.length(TOP_RANK), FireWall.length(TOP_RANK)));
pub fn wall(lv: *const grid.Level, hero: P, start: P, end: P, rank: u8) ?Wall {
    return line(lv, hero, start, end, ArcaneBarrier.length(rank), ArcaneBarrier.RANGE, raisable);
}
/// Fire Wall's cells: open dry ground, bodies or not.
pub fn blaze(lv: *const grid.Level, hero: P, start: P, end: P, rank: u8) ?Wall {
    return line(lv, hero, start, end, FireWall.length(rank), FireWall.RANGE, flammable);
}
fn raisable(lv: *const grid.Level, p: P) bool {
    return lv.vacant(p);
}
fn flammable(lv: *const grid.Level, p: P) bool {
    return lv.walkable(p) and !lv.hasBarrel(p) and !lv.at(p).liquid();
}
fn line(lv: *const grid.Level, hero: P, start: P, end: P, most: usize, range: i32, comptime fits: fn (*const grid.Level, P) bool) ?Wall {
    var out = Wall{};
    var p = start;
    var ray = grid.Ray.init(start, end);
    while (true) {
        if (out.n == most or !fits(lv, p) or lv.at(p).isChest() or lv.doorAt(p) != null or !lv.isLit(p) or mathx.dist(hero, p) > range) return null;
        out.push(p);
        if (p.eq(end)) return out;
        p = ray.next() orelse return null;
    }
}

test "tactical wall follows arbitrary bearings and validates every cell before placement" {
    var lv = grid.openFloor();
    lv.lit = @splat(true);
    const hero = P{ .x = 20, .y = 20 };
    const a = P{ .x = 22, .y = 20 };
    const b = P{ .x = 24, .y = 21 };
    try std.testing.expectEqual(@as(usize, 3), wall(&lv, hero, a, b, 1).?.n);
    lv.putBarrel(.{ .x = 23, .y = 20 });
    lv.putBarrel(.{ .x = 23, .y = 21 });
    try std.testing.expect(wall(&lv, hero, a, b, 1) == null);
    try std.testing.expect(wall(&lv, hero, a, .{ .x = 26, .y = 20 }, 1) == null);
    std.debug.print("tactical geometry: angled wall, occupied interior and rank length caps checked\n", .{});
}

test "a fire line may cover bodies but not barrels or water, and stretches with rank" {
    var lv = grid.openFloor();
    lv.lit = @splat(true);
    const hero = P{ .x = 20, .y = 20 };
    const a = P{ .x = 22, .y = 18 };
    const b = P{ .x = 22, .y = 22 };
    try std.testing.expect(blaze(&lv, hero, a, b, 1) == null);
    try std.testing.expectEqual(@as(usize, 5), blaze(&lv, hero, a, b, 3).?.n);
    lv.stand(.{ .x = 22, .y = 20 }, 2);
    try std.testing.expect(blaze(&lv, hero, a, b, 3) != null);
    try std.testing.expect(wall(&lv, hero, a, b, 3) == null);
    lv.set(.{ .x = 22, .y = 21 }, .water);
    try std.testing.expect(blaze(&lv, hero, a, b, 3) == null);
    lv.set(.{ .x = 22, .y = 21 }, .floor);
    lv.putBarrel(.{ .x = 22, .y = 19 });
    try std.testing.expect(blaze(&lv, hero, a, b, 3) == null);
    std.debug.print("fire line: {d}-{d} cells by rank over bodies; water and barrels refused\n", .{ FireWall.length(1), FireWall.length(TOP_RANK) });
}
