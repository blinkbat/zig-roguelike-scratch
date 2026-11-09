const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const resilience = @import("resilience.zig");
const areas = @import("area.zig");

pub const TURNS: u8 = 3;
/// Cells from where lightning lands that the water it lands in carries it.
pub const CONDUCT: i32 = 2;
pub const CONDUCTS = "The water carries the shock!";

comptime {
    std.debug.assert(CONDUCT <= areas.BURST_MAX);
}
/// Percent more damage the hit it is spent on deals, rounded up.
pub const MORE: i32 = 50;
pub const AILMENT = resilience.Kind.shock;
pub const TAKES = "is shocked";
pub const STATUS = std.fmt.comptimePrint("The next hit taken deals {d}% more damage.", .{MORE});

/// Its turns left waiting for a hit; the first that deals damage spends it.
pub const Shock = resilience.Turns(TURNS);

/// `dmg` as the hit `s` is spent on deals it; a hit dealing nothing leaves it waiting.
pub fn spend(s: *Shock, dmg: i32) i32 {
    if (s.turns == 0 or dmg <= 0) return dmg;
    s.turns = 0;
    return mathx.percentCeil(dmg, mathx.PERCENT + MORE);
}

pub const afflict = resilience.Starts(AILMENT).afflict;

/// The deep water and shallows joined to `at` within `CONDUCT` cells of it; none where `at` is dry.
pub fn conducted(lv: *const grid.Level, at: mathx.P) areas.Burst {
    var out = areas.Burst{};
    if (!lv.at(at).wet()) return out;
    out.push(at);
    var i: usize = 0;
    while (i < out.n) : (i += 1) {
        const from = out.items[i];
        for (mathx.ALL_DIRS) |d| {
            const p = from.add(d.delta());
            if (mathx.dist(at, p) > CONDUCT or !lv.at(p).wet() or out.has(p)) continue;
            out.push(p);
        }
    }
    return out;
}

test "lightning runs through the water joined to where it lands, out to its reach, and not over dry ground" {
    var lv = grid.openFloor();
    const at = mathx.P{ .x = 20, .y = 20 };
    var x: i32 = 16;
    while (x <= 24) : (x += 1) lv.set(.{ .x = x, .y = 20 }, if (@mod(x, 2) == 0) .water else .shallows);
    lv.set(.{ .x = 20, .y = 22 }, .water);
    const wet = conducted(&lv, at);
    try std.testing.expectEqual(@as(usize, 2 * CONDUCT + 1), wet.n);
    for (wet.slice()) |p| try std.testing.expect(p.y == 20 and mathx.dist(at, p) <= CONDUCT);
    lv.set(.{ .x = 21, .y = 20 }, .floor);
    try std.testing.expectEqual(@as(usize, CONDUCT + 1), conducted(&lv, at).n);
    try std.testing.expectEqual(@as(usize, 0), conducted(&lv, .{ .x = 30, .y = 30 }).n);
    std.debug.print("conduction: {d} cells along a channel within {d}; a dry gap cuts it to {d}; dry ground none\n", .{ wet.n, CONDUCT, conducted(&lv, at).n });
}

test "a shock adds half again to the next damaging hit, rounded up, then is gone" {
    const cases = [_][2]i32{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 5 }, .{ 4, 6 }, .{ 10, 15 } };
    for (cases) |c| {
        var s = Shock{};
        s.start();
        try std.testing.expectEqual(c[1], spend(&s, c[0]));
        try std.testing.expectEqual(@as(u8, 0), s.turns);
        try std.testing.expectEqual(c[0], spend(&s, c[0]));
    }
    var s = Shock{};
    s.start();
    try std.testing.expectEqual(@as(i32, 0), spend(&s, 0));
    try std.testing.expectEqual(TURNS, s.turns);
    for (0..TURNS) |_| _ = s.wear();
    try std.testing.expectEqual(@as(i32, 4), spend(&s, 4));
    s.start();
    try std.testing.expectEqual(std.math.maxInt(i32), spend(&s, std.math.maxInt(i32)));
    std.debug.print("shock: {d} hits each amplified once ({d}% rounded up); a 0-damage hit keeps it; {d} unhit turns end it\n", .{ cases.len, MORE, TURNS });
}
