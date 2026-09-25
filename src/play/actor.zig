const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");

const P = mathx.P;

pub const Kind = enum { archer, rat };

pub const Row = struct {
    name: [:0]const u8,
    hp: i32,
    hit_lo: i32,
    hit_hi: i32,
    sight: i32,
};

pub fn row(k: Kind) Row {
    return switch (k) {
        .archer => .{ .name = "you", .hp = 24, .hit_lo = 1, .hit_hi = 2, .sight = 10 },
        .rat => .{ .name = "rat", .hp = 6, .hit_lo = 1, .hit_hi = 3, .sight = 7 },
    };
}

pub const Actor = struct {
    kind: Kind,
    at: P,
    hp: i32,
    awake: bool = false,
    alive: bool = true,

    pub fn of(k: Kind, at: P) Actor {
        return .{ .kind = k, .at = at, .hp = row(k).hp };
    }

    pub fn hurt(self: Actor) bool {
        return self.hp < row(self.kind).hp;
    }

    pub fn foe(self: Actor) bool {
        return self.kind != .archer;
    }
};

pub const MAX: usize = 32;

/// Ids are 1-based so `grid.NO_ONE` (0) is never a body.
pub const Pool = struct {
    items: [MAX]Actor = undefined,
    n: usize = 0,

    pub fn idOf(i: usize) u16 {
        return @intCast(i + 1);
    }

    pub fn slot(id: u16) usize {
        return id - 1;
    }

    pub fn spawn(self: *Pool, lv: *grid.Level, a: Actor) u16 {
        std.debug.assert(self.n < MAX);
        const id = idOf(self.n);
        self.items[self.n] = a;
        self.n += 1;
        lv.stand(a.at, id);
        return id;
    }

    pub fn get(self: *Pool, id: u16) ?*Actor {
        if (id == grid.NO_ONE or id > self.n) return null;
        const a = &self.items[slot(id)];
        return if (a.alive) a else null;
    }

    pub fn slice(self: *Pool) []Actor {
        return self.items[0..self.n];
    }

    pub fn move(self: *Pool, lv: *grid.Level, id: u16, to: P) void {
        const a = self.get(id) orelse return;
        lv.clear(a.at);
        a.at = to;
        lv.stand(to, id);
    }

    /// The only place hp goes down. Returns true on the killing blow.
    pub fn damage(self: *Pool, lv: *grid.Level, id: u16, amount: i32) bool {
        const a = self.get(id) orelse return false;
        a.hp -= amount;
        a.awake = true;
        if (a.hp > 0) return false;
        a.alive = false;
        lv.clear(a.at);
        return true;
    }
};

/// Downhill on a walked-distance map from the hero; null when no open neighbour is closer.
pub fn chase(lv: *const grid.Level, from: P, id: u16, flow: *const [grid.CELLS]i32) ?mathx.Dir {
    var best: ?mathx.Dir = null;
    var best_d = flow[grid.Level.idx(from)];
    if (best_d < 0) return null;
    for (mathx.ALL_DIRS) |d| {
        if (!lv.stepOk(from, d, id)) continue;
        const v = flow[grid.Level.idx(from.add(d.delta()))];
        if (v >= 0 and v < best_d) {
            best_d = v;
            best = d;
        }
    }
    return best;
}

test "a spawned body stands on the grid and leaves it when it dies" {
    var lv = grid.openFloor();
    var pool = Pool{};
    const id = pool.spawn(&lv, Actor.of(.rat, .{ .x = 5, .y = 5 }));
    try std.testing.expectEqual(id, lv.who(.{ .x = 5, .y = 5 }));
    try std.testing.expect(!pool.damage(&lv, id, 2));
    try std.testing.expect(pool.get(id).?.awake);
    try std.testing.expect(pool.damage(&lv, id, 99));
    try std.testing.expectEqual(grid.NO_ONE, lv.who(.{ .x = 5, .y = 5 }));
    try std.testing.expectEqual(@as(?*Actor, null), pool.get(id));
}

test "chase walks round a wall toward the hero" {
    var lv = grid.openFloor();
    var y: i32 = 1;
    while (y < 12) : (y += 1) lv.set(.{ .x = 10, .y = y }, .wall);
    var flow: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const hero = P{ .x = 12, .y = 5 };
    _ = grid.distances(&lv, hero, &flow, &queue);
    var at = P{ .x = 8, .y = 5 };
    var steps: usize = 0;
    while (mathx.dist(at, hero) > 1 and steps < 40) : (steps += 1) {
        const d = chase(&lv, at, 1, &flow) orelse return error.Stuck;
        at = at.add(d.delta());
    }
    std.debug.print("round a wall: {d} steps to reach a hero 4 cells away\n", .{steps});
    try std.testing.expect(mathx.dist(at, hero) <= 1);
}
