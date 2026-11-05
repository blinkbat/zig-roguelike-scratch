const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const clock = @import("clock.zig");
const damage = @import("damage.zig");

const P = mathx.P;

pub const COST: i32 = 3;
pub const AILMENT = @import("resilience.zig").Kind.stun;
pub const COOLDOWN: u8 = 3;
pub const CHANCE: u32 = 50;
pub const VERB = "shield-bashes";
pub const TAKES = clock.STUNNED;
pub const DESCRIPTION = std.fmt.comptimePrint("Strike an adjacent foe and knock it back a tile. {s}.", .{clock.stunNote(CHANCE)});

pub const BASE = damage.Base{ .lo = 2, .hi = 4 };

pub const procs = damage.chance(CHANCE);
pub const chance = damage.flat(CHANCE);
pub const afflict = clock.stuns;

/// A body or barrel beside `from`.
pub fn aimable(lv: *const grid.Level, from: P, to: P) bool {
    _ = mathx.dirTo(from, to) orelse return false;
    return lv.strikeable(to) and lv.taken(to);
}

/// The free landing behind a blow; the caller checks whether the body's feet or fins can stand there.
pub fn knocked(lv: *const grid.Level, at: P, d: mathx.Dir, id: u16) ?P {
    const to = at.add(d.delta());
    if (!grid.Level.inside(to) or lv.hasBarrier(to) or (lv.at(to).solid() and !lv.at(to).wet())) return null;
    if (lv.hasBarrel(to) or lv.folkAt(to) != null) return null;
    const who = lv.who(to);
    return if (who == grid.NO_ONE or who == id) to else null;
}

test "a bash reaches a body or barrel beside the knight, and knocks a body back onto open ground only" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    const foe = P{ .x = 21, .y = 21 };
    lv.stand(foe, 2);
    try std.testing.expect(aimable(&lv, from, foe));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 21, .y = 20 }));
    try std.testing.expect(!aimable(&lv, from, .{ .x = 22, .y = 22 }));
    lv.putBarrel(.{ .x = 19, .y = 20 });
    try std.testing.expect(aimable(&lv, from, .{ .x = 19, .y = 20 }));
    try std.testing.expectEqual(@as(?P, .{ .x = 22, .y = 22 }), knocked(&lv, foe, .se, 2));
    lv.set(.{ .x = 22, .y = 22 }, .wall);
    try std.testing.expectEqual(@as(?P, null), knocked(&lv, foe, .se, 2));
    lv.set(.{ .x = 22, .y = 22 }, .floor);
    lv.stand(.{ .x = 22, .y = 22 }, 3);
    try std.testing.expectEqual(@as(?P, null), knocked(&lv, foe, .se, 2));
    std.debug.print("shield bash: reach 1, knockback 1 onto open ground; {d}% stun\n", .{CHANCE});
}

test "wet melee reach allows occupied water through diagonal gaps but never barriers or walls" {
    var lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    var checked: usize = 0;
    for ([_]mathx.Dir{ .ne, .se, .sw, .nw }) |d| {
        lv = grid.openFloor();
        const delta = d.delta();
        const to = from.add(delta);
        lv.set(from.add(.{ .x = delta.x, .y = 0 }), .wall);
        lv.set(from.add(.{ .x = 0, .y = delta.y }), .wall);
        lv.set(to, .water);
        try std.testing.expect(!aimable(&lv, from, to));
        lv.stand(to, 2);
        try std.testing.expect(aimable(&lv, from, to));
        try std.testing.expect(!lv.stepOk(from, d, 0));
        lv.barrier[grid.Level.idx(to)] = 1;
        try std.testing.expect(!aimable(&lv, from, to));
        lv.barrier[grid.Level.idx(to)] = 0;
        lv.set(to, .wall);
        try std.testing.expect(!aimable(&lv, from, to));
        checked += 1;
    }
    std.debug.print("wet melee geometry: {d} tight diagonal gaps accept swimming bodies; empty water, walls and barriers stay excluded\n", .{checked});
}
