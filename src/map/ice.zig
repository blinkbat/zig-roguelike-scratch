const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");

const P = mathx.P;

/// Turns frozen shallows stay ice.
pub const THAWS: u8 = 10;
pub const FREEZES = "The water freezes over.";
pub const WATER: grid.Tile = .shallows;

pub fn turned(was: grid.Tile, now: grid.Tile) bool {
    return (was == WATER and now == .ice) or (was == .ice and now == WATER);
}

pub fn freeze(lv: *grid.Level, cells: []const P) usize {
    var n: usize = 0;
    for (cells) |p| {
        if (!grid.Level.inside(p)) continue;
        const i = grid.Level.idx(p);
        if (lv.tile[i] == WATER) {
            lv.tile[i] = .ice;
            n += 1;
        } else if (!lv.frozen(p)) continue;
        lv.thaw[i] = THAWS;
    }
    return n;
}

pub fn melt(lv: *grid.Level, cells: []const P) usize {
    var n: usize = 0;
    for (cells) |p| {
        if (!lv.frozen(p)) continue;
        const i = grid.Level.idx(p);
        lv.tile[i] = WATER;
        lv.thaw[i] = 0;
        n += 1;
    }
    return n;
}

/// True when any frozen cell thawed back to shallows.
pub fn turn(lv: *grid.Level) bool {
    var thawed = false;
    for (&lv.thaw, &lv.tile) |*left, *t| {
        if (left.* == 0) continue;
        if (t.* != .ice) {
            left.* = 0;
            continue;
        }
        left.* -= 1;
        if (left.* > 0) continue;
        t.* = WATER;
        thawed = true;
    }
    return thawed;
}

const AT = grid.MIDDLE;

test "cold freezes only shallows, for its turns, and refreezing starts them afresh" {
    var lv = grid.openFloor();
    const deep = AT.add(.{ .x = 1, .y = 0 });
    const dry = AT.add(.{ .x = 2, .y = 0 });
    lv.set(AT, .shallows);
    lv.set(deep, .water);
    try std.testing.expectEqual(@as(usize, 1), freeze(&lv, &.{ AT, deep, dry }));
    try std.testing.expect(lv.frozen(AT) and !lv.at(AT).wet());
    try std.testing.expectEqual(grid.Tile.water, lv.at(deep));
    try std.testing.expectEqual(grid.Tile.floor, lv.at(dry));
    for (0..THAWS - 1) |_| try std.testing.expect(!turn(&lv));
    try std.testing.expectEqual(@as(usize, 0), freeze(&lv, &.{AT}));
    for (0..THAWS - 1) |_| try std.testing.expect(!turn(&lv));
    try std.testing.expect(turn(&lv));
    try std.testing.expectEqual(grid.Tile.shallows, lv.at(AT));
    try std.testing.expectEqual(@as(u8, 0), lv.thaw[grid.Level.idx(AT)]);
}

test "melting and thawing take back only frozen shallows, never lasting ice or a tile laid over the frozen cell" {
    var lv = grid.openFloor();
    const lasting = AT.add(.{ .x = 1, .y = 0 });
    const paved = AT.add(.{ .x = 2, .y = 0 });
    lv.set(AT, .shallows);
    lv.set(lasting, .ice);
    lv.set(paved, .shallows);
    _ = freeze(&lv, &.{ AT, lasting, paved });
    try std.testing.expect(!lv.frozen(lasting));
    lv.set(paved, .dirt);
    try std.testing.expectEqual(@as(usize, 1), melt(&lv, &.{ AT, lasting, paved }));
    try std.testing.expectEqual(grid.Tile.shallows, lv.at(AT));
    try std.testing.expectEqual(grid.Tile.ice, lv.at(lasting));
    for (0..THAWS) |_| _ = turn(&lv);
    try std.testing.expectEqual(grid.Tile.dirt, lv.at(paved));
    try std.testing.expect(std.mem.allEqual(u8, &lv.thaw, 0));
}
