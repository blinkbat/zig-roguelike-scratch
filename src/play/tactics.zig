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
    pub const DESCRIPTION = "Scatter caltrops in a small patch. Entering foes are pinned unless resisted. Rank 2 adds bleeding; rank 3 strengthens it.";
    pub const FLAVOR = "The road behind is no longer safe.";
    pub fn duration(rank: u8) u8 {
        return 4 + rank;
    }
    pub fn pins(rank: u8) u8 {
        return 1 + @as(u8, @intFromBool(rank == 3));
    }
    pub fn bleed(rank: u8) i32 {
        return rank -| 1;
    }
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, 1);
    }
};
pub const Overwatch = struct {
    pub const RANGE = bow.RANGE;
    pub const COST: i32 = 4;
    pub const COOLDOWN: u8 = 3;
    pub const DESCRIPTION = "Cover a direction until your next action. Fire once at the first foe moving into its cone. Uses arrow damage. Higher ranks improve the shot.";
    pub const FLAVOR = "Let them make the first mistake.";
    pub const BASE = bow.BASE;
};
pub const SteadyAim = struct {
    pub const COST: i32 = 2;
    pub const DESCRIPTION = "Prepare your next arrow for increased damage and critical chance. Movement cancels preparation.";
    pub const FLAVOR = "Breathe out. Let the world grow still.";
    pub fn bonus(rank: u8) i32 {
        return 15 + 15 * @as(i32, @max(1, rank));
    }
    pub fn critical(rank: u8) i32 {
        return 5 + 5 * @as(i32, @max(1, rank));
    }
};
pub const GravityWell = struct {
    pub const COST: i32 = 6;
    pub const COOLDOWN: u8 = 5;
    pub const RANGE: i32 = 6;
    pub const DESCRIPTION = "Pull foes within two cells toward a visible center. Rank 2 also pins for one turn unless resisted; rank 3 pulls two cells and pins for two turns.";
    pub const FLAVOR = "Even the dark has weight.";
    pub fn pulls(rank: u8) usize {
        return if (rank == 3) 2 else 1;
    }
    pub fn pins(rank: u8) u8 {
        return rank -| 1;
    }
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, 2);
    }
};
pub const Combustion = struct {
    pub const COST: i32 = 5;
    pub const COOLDOWN: u8 = 3;
    pub const RANGE: i32 = 7;
    pub const ELEMENT = damage.Element.fire;
    pub const BASE = damage.Base{ .lo = 5, .hi = 8 };
    pub const DESCRIPTION = "Consume a visible foe's burn. Explode it and its neighbors for fire damage, adding two damage per remaining burn turn before scaling.";
    pub const FLAVOR = "One spark was only the beginning.";
    pub const FUEL_DAMAGE: i32 = 2;
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, 1);
    }
};
pub const ArcaneBarrier = struct {
    pub const COST: i32 = 6;
    pub const COOLDOWN: u8 = 6;
    pub const RANGE: i32 = 6;
    pub const DESCRIPTION = "Choose two endpoints to raise a straight arcane wall. Blocks movement and projectiles, allows sight. Rank increases length and duration. Cannot cover bodies, props or doors.";
    pub const FLAVOR = "Draw a line the world must obey.";
    pub fn length(rank: u8) usize {
        return 2 + @as(usize, @max(1, rank));
    }
    pub fn duration(rank: u8) u8 {
        return 3 + @max(1, rank);
    }
};
pub const Guard = struct {
    pub const COST: i32 = 2;
    pub const DESCRIPTION = "Brace until your next action. Reduce incoming physical attack damage after armour. Higher ranks improve protection.";
    pub const FLAVOR = "Stand, and make them break upon you.";
    pub fn reduction(rank: u8) i32 {
        return 40 + 10 * @as(i32, @max(1, rank));
    }
};
pub const Whirlwind = struct {
    pub const COST: i32 = 5;
    pub const COOLDOWN: u8 = 3;
    pub const BASE = damage.Base{ .lo = 2, .hi = 4 };
    pub const DESCRIPTION = "Strike every adjacent foe and barrel with your melee weapon. Each foe is struck once.";
    pub const FLAVOR = "Steel has no blind side.";
    pub fn area(lv: *const grid.Level, at: P) glacial.Burst {
        return patch(lv, at, 1);
    }
};
pub const Unyielding = struct {
    pub const COST: i32 = 2;
    pub const DESCRIPTION = "Toggle a stance that drains mana each spent turn; ends when unaffordable. Chance to counter adjacent melee attackers increases by rank. Counters cost no extra turn.";
    pub const FLAVOR = "Every blow invites an answer.";
    pub const DRAIN: i32 = 2;
    pub fn chance(rank: u8) u32 {
        return 15 + 10 * @as(u32, @max(1, rank));
    }
};

pub const State = struct {
    steady: u8 = 0,
    guard: u8 = 0,
    unyielding: bool = false,
    overwatch: ?mathx.Dir = null,
};

pub fn keep(_: void, _: P) bool {
    return true;
}
pub fn patch(lv: *const grid.Level, at: P, radius: i32) glacial.Burst {
    return glacial.spread(lv, at, radius, {}, keep);
}
pub fn covered(from: P, dir: mathx.Dir, at: P) bool {
    const d = dir.delta();
    const v = at.sub(from);
    const along = v.x * d.x + v.y * d.y;
    const across = v.x * d.y - v.y * d.x;
    return along > 0 and @abs(across) <= along;
}
pub const Wall = grid.Area(ArcaneBarrier.length(@import("progress.zig").RANKS));
pub fn wall(lv: *const grid.Level, hero: P, start: P, end: P, rank: u8) ?Wall {
    var out = Wall{};
    var p = start;
    var ray = grid.Ray.init(start, end);
    while (true) {
        if (out.n == ArcaneBarrier.length(rank) or !lv.vacant(p) or lv.at(p).isChest() or lv.doorAt(p) != null or !lv.isLit(p) or mathx.dist(hero, p) > ArcaneBarrier.RANGE) return null;
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
