const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("actor.zig");

const P = mathx.P;

pub const GUARD: actor.Kind = .caravan_guard;
pub const GUARDS_MAX: u8 = 8;
pub const POST: grid.Tile = .caravan;

pub const Post = struct {
    guards: u8 = 0,

    pub fn fit(p: Post) Post {
        return .{ .guards = @min(p.guards, GUARDS_MAX) };
    }
};

comptime {
    std.debug.assert(actor.row(GUARD).posted);
}

/// Fill cart posts in reading order until the guard quota or available space runs out.
pub fn place(lv: *grid.Level, pool: *actor.Pool, post: Post, off: *const grid.CellSet) void {
    var left = post.fit().guards;
    while (left > 0) {
        const was = left;
        for (0..grid.CELLS) |i| {
            if (lv.tile[i] != POST) continue;
            if (left == 0 or !pool.hasRoomFor(GUARD)) return;
            const at = grid.besideFoot(POST.footprint(grid.Level.of(i)), Stand{ .lv = lv, .off = off }, Stand.at) orelse continue;
            _ = pool.spawn(lv, actor.Actor.of(GUARD, at));
            left -= 1;
        }
        if (left == was) return;
    }
}

const Stand = struct {
    lv: *const grid.Level,
    off: *const grid.CellSet,

    fn at(self: Stand, q: P) bool {
        return !grid.Level.onRim(q) and !self.off.isSet(grid.Level.idx(q)) and actor.standsOffDoor(GUARD, self.lv, q) and !self.lv.at(q).wet();
    }
};

test "guards stand beside the carts, a cart at a time, and none without a cart" {
    var lv = grid.openFloor();
    const carts = [_]P{ .{ .x = 10, .y = 10 }, .{ .x = 30, .y = 20 } };
    for (carts) |c| lv.putProp(c, POST);
    var pool = actor.Pool{};
    place(&lv, &pool, .{ .guards = 3 }, &.initEmpty());
    var by = [_]usize{ 0, 0 };
    for (pool.constSlice()) |a| {
        try std.testing.expectEqual(GUARD, a.kind);
        for (carts, &by) |c, *n| {
            if (POST.footprint(c).grown(1).holds(a.at)) n.* += 1;
        }
    }
    var bare = grid.openFloor();
    var none = actor.Pool{};
    place(&bare, &none, .{ .guards = GUARDS_MAX }, &.initEmpty());
    try std.testing.expectEqual(@as(usize, 3), pool.n);
    try std.testing.expectEqual([_]usize{ 2, 1 }, by);
    try std.testing.expectEqual(@as(usize, 0), none.n);
}

test "caravan guards cannot occupy protected cells" {
    var lv = grid.openFloor();
    const cart = P{ .x = 10, .y = 10 };
    lv.putProp(cart, POST);
    var off = grid.CellSet.initEmpty();
    var beside = POST.footprint(cart).grown(1).cells();
    while (beside.next()) |p| off.set(grid.Level.idx(p));
    var pool = actor.Pool{};
    place(&lv, &pool, .{ .guards = 1 }, &off);
    try std.testing.expectEqual(@as(usize, 0), pool.n);
}
