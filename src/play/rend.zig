const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const bleeding = @import("bleeding.zig");
const damage = @import("damage.zig");
const bash = @import("bash.zig");

const P = mathx.P;

pub const COST: i32 = 4;
pub const AILMENT = @import("resilience.zig").Kind.bleed;
pub const BLEED: i32 = 2;
pub const VERB = "rends";
pub const TAKES = bleeding.TAKES;
pub const DESCRIPTION = std.fmt.comptimePrint("Strike an adjacent foe. Inflicts a bleed of {d} per turn.", .{BLEED});

pub const BASE = damage.Base{ .lo = 2, .hi = 4 };

pub const CHANCE: u32 = mathx.PERCENT;
pub const procs = damage.chance(CHANCE);
pub const chance = damage.flat(CHANCE);

pub fn afflict(a: anytype, _: *mathx.Rng) void {
    a.bleed.startWith(BLEED);
}

pub const aimable = bash.aimable;

test "rend reaches a body beside the knight and opens a bleed stronger than an arrow's" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    lv.stand(.{ .x = 21, .y = 20 }, 2);
    try std.testing.expect(aimable(&lv, from, .{ .x = 21, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 19, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 22, .y = 20 }));
    var rng = mathx.Rng.init(0x4E4D);
    var a: struct { bleed: bleeding.Bleed = .{} } = .{};
    try std.testing.expect(procs(&rng, 0));
    afflict(&a, &rng);
    try std.testing.expectEqual(bleeding.TURNS, a.bleed.turns);
    try std.testing.expectEqual(BLEED, a.bleed.amount);
    std.debug.print("rend: reach 1, bleed {d} per turn ({d} moving) for {d} turns\n", .{ BLEED, BLEED * bleeding.MOVE_FACTOR, bleeding.TURNS });
}
