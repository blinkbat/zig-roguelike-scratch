const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");

const P = mathx.P;

pub const Kind = enum {
    archer,
    rat,
    slime,
    bloat,

    pub fn foe(k: Kind) bool {
        return k != .archer;
    }
};

pub const FOES = blk: {
    var ks: []const Kind = &.{};
    for (std.enums.values(Kind)) |k| {
        if (k.foe()) ks = ks ++ &[_]Kind{k};
    }
    break :blk ks[0..ks.len].*;
};

pub const Strike = struct { lo: i32, hi: i32, verb: [:0]const u8 };

pub const Blow = union(enum) {
    strike: Strike,
    /// It dies instead (Brogue's kamikaze), and bursts into caustic gas however it dies.
    burst,
};

pub const Row = struct {
    name: [:0]const u8,
    hp: i32,
    sight: i32,
    blow: Blow,
    /// Brogue's `MONST_FLITS`: a third of its moves go a random way.
    flits: bool = false,
};

pub const FLIT: f32 = 0.33;

pub fn row(k: Kind) Row {
    return switch (k) {
        .archer => .{ .name = "you", .hp = 24, .sight = 10, .blow = .{ .strike = .{ .lo = 1, .hi = 2, .verb = "kicks" } } },
        .rat => .{ .name = "rat", .hp = 6, .sight = 7, .blow = .{ .strike = .{ .lo = 1, .hi = 3, .verb = "bites" } } },
        .slime => .{ .name = "slime", .hp = 14, .sight = 6, .blow = .{ .strike = .{ .lo = 2, .hi = 5, .verb = "slams" } } },
        .bloat => .{ .name = "bloat", .hp = 4, .sight = 7, .blow = .burst, .flits = true },
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
        return self.kind.foe();
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

/// Brogue's `monsterAvoids`: gas is shunned by a body not already in some.
fn shuns(lv: *const grid.Level, from: P, d: mathx.Dir) bool {
    return lv.gassy(from.add(d.delta())) and !lv.gassy(from);
}

/// Downhill on a walked-distance map from the hero; null when no open neighbour is closer.
pub fn chase(lv: *const grid.Level, from: P, id: u16, flow: *const [grid.CELLS]i32) ?mathx.Dir {
    var best: ?mathx.Dir = null;
    var best_d = flow[grid.Level.idx(from)];
    if (best_d < 0) return null;
    for (mathx.ALL_DIRS) |d| {
        if (!lv.stepOk(from, d, id) or shuns(lv, from, d)) continue;
        const v = flow[grid.Level.idx(from.add(d.delta()))];
        if (v >= 0 and v < best_d) {
            best_d = v;
            best = d;
        }
    }
    return best;
}

/// Brogue's `randValidDirectionFrom`: any step it may take and does not shun, or one onto `prey`.
pub fn flit(lv: *const grid.Level, from: P, id: u16, prey: u16, rng: *mathx.Rng) ?mathx.Dir {
    var ways: [mathx.ALL_DIRS.len]mathx.Dir = undefined;
    var n: usize = 0;
    for (mathx.ALL_DIRS) |d| {
        const onto = lv.passOk(from, d) and lv.who(from.add(d.delta())) == prey;
        if (!onto and (!lv.stepOk(from, d, id) or shuns(lv, from, d))) continue;
        ways[n] = d;
        n += 1;
    }
    if (n == 0) return null;
    return ways[rng.below(@intCast(n))];
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

test "chase will not step from clean air into gas, but walks on through it from inside" {
    var lv = grid.openFloor();
    var flow: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&lv, .{ .x = 20, .y = 5 }, &flow, &queue);
    var y: i32 = 1;
    while (y < grid.H - 1) : (y += 1) lv.addGas(.{ .x = 15, .y = y }, 50);
    const at = P{ .x = 14, .y = 5 };
    try std.testing.expectEqual(@as(?mathx.Dir, null), chase(&lv, at, 1, &flow));
    lv.addGas(at, 50);
    const d = chase(&lv, at, 1, &flow) orelse return error.Stuck;
    try std.testing.expectEqual(@as(i32, 15), at.add(d.delta()).x);
}

test "a flit goes every open way about evenly, onto its prey too, and never into gas from clean air" {
    var lv = grid.openFloor();
    var rng = mathx.Rng.init(0xF117);
    const from = P{ .x = 10, .y = 10 };
    lv.stand(from, 2);
    lv.stand(.{ .x = 11, .y = 10 }, 1);
    lv.putBarrel(.{ .x = 9, .y = 10 });
    lv.addGas(.{ .x = 10, .y = 9 }, 30);
    const TRIES: usize = 6000;
    var counts = std.EnumArray(mathx.Dir, usize).initFill(0);
    for (0..TRIES) |_| counts.getPtr(flit(&lv, from, 2, 1, &rng) orelse return error.Stuck).* += 1;
    std.debug.print("{d} flits beside a barrel west and gas north:", .{TRIES});
    for (mathx.ALL_DIRS) |d| std.debug.print(" {s} {d}", .{ @tagName(d), counts.get(d) });
    std.debug.print("\n", .{});
    try std.testing.expectEqual(@as(usize, 0), counts.get(.w));
    try std.testing.expectEqual(@as(usize, 0), counts.get(.n));
    for ([_]mathx.Dir{ .ne, .e, .se, .s, .sw, .nw }) |d| {
        try std.testing.expect(counts.get(d) * 6 > TRIES * 85 / 100 and counts.get(d) * 6 < TRIES * 115 / 100);
    }
}
