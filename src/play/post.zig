const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("actor.zig");

const P = mathx.P;

pub const GUARD: actor.Kind = .caravan_guard;
pub const GUARDS_MAX: u8 = 8;
const POST: grid.Tile = .caravan;

/// The guards a procgen node posts beside its carts.
pub const Post = struct {
    guards: u8 = 0,

    pub fn fit(p: Post) Post {
        return .{ .guards = @min(p.guards, GUARDS_MAX) };
    }
};

comptime {
    std.debug.assert(actor.row(GUARD).posted);
}

/// Up to `post.guards` guards beside the carts, a cart at a time in reading order; fewer when the carts or the pool run out of room.
pub fn place(lv: *grid.Level, pool: *actor.Pool, post: Post) void {
    var left = post.fit().guards;
    while (left > 0) {
        const was = left;
        for (0..grid.CELLS) |i| {
            if (lv.tile[i] != POST) continue;
            if (left == 0 or !pool.hasRoomFor(GUARD)) return;
            const at = grid.besideFoot(POST.footprint(grid.Level.of(i)), @as(*const grid.Level, lv), stands) orelse continue;
            _ = pool.spawn(lv, actor.Actor.of(GUARD, at));
            left -= 1;
        }
        if (left == was) return;
    }
}

/// Free dry ground a guard may stand on.
fn stands(lv: *const grid.Level, q: P) bool {
    return !grid.Level.onRim(q) and actor.dwells(GUARD, lv, q) and lv.doorAt(q) == null and !lv.at(q).wet();
}

test "guards stand beside the carts, a cart at a time, and none without a cart" {
    var lv = grid.openFloor();
    const carts = [_]P{ .{ .x = 10, .y = 10 }, .{ .x = 30, .y = 20 } };
    for (carts) |c| lv.putProp(c, POST);
    var pool = actor.Pool{};
    place(&lv, &pool, .{ .guards = 3 });
    var by = [_]usize{ 0, 0 };
    for (pool.constSlice()) |a| {
        try std.testing.expectEqual(GUARD, a.kind);
        for (carts, &by) |c, *n| {
            if (POST.footprint(c).grown(1).holds(a.at)) n.* += 1;
        }
    }
    var bare = grid.openFloor();
    var none = actor.Pool{};
    place(&bare, &none, .{ .guards = GUARDS_MAX });
    std.debug.print("3 guards by 2 carts: {d} and {d} beside each; {d} with no cart\n", .{ by[0], by[1], none.n });
    try std.testing.expectEqual(@as(usize, 3), pool.n);
    try std.testing.expectEqual([_]usize{ 2, 1 }, by);
    try std.testing.expectEqual(@as(usize, 0), none.n);
}
