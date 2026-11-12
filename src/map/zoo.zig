const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const gen = @import("gen.zig");
const actor = @import("../play/actor.zig");
const P = mathx.P;

pub const MAX_KINDS = 16;
pub const Entry = struct { kind: actor.Kind = .rat, weight: u8 = 1 };
pub const Side = enum { n, e, s, w };
pub const Spec = struct {
    pub const COUNTED = .{.{ "pool", "pool_n" }};
    at: P = .{ .x = 40, .y = 18 },
    width: u8 = 8,
    height: u8 = 6,
    side: Side = .w,
    key: ?P = null,
    pool: [MAX_KINDS]Entry = @splat(.{}),
    pool_n: usize = 1,

    pub fn room(s: *const Spec) grid.Box {
        return grid.Box.sized(s.at, s.width, s.height);
    }

    pub fn inside(s: *const Spec) grid.Box {
        return s.room().grown(-1);
    }

    pub fn reserves(s: *const Spec, p: P) bool {
        return s.room().grown(1).holds(p) or (if (s.key) |k| k.eq(p) else false);
    }

    pub fn door(s: *const Spec) P {
        const r = s.room();
        const c = r.centre();
        return switch (s.side) {
            .n => .{ .x = c.x, .y = r.lo.y },
            .s => .{ .x = c.x, .y = r.hi.y - 1 },
            .w => .{ .x = r.lo.x, .y = c.y },
            .e => .{ .x = r.hi.x - 1, .y = c.y },
        };
    }

    pub fn outward(s: *const Spec) P {
        return std.meta.stringToEnum(mathx.Dir, @tagName(s.side)).?.delta();
    }

    pub fn threshold(s: *const Spec) P {
        return s.door().sub(s.outward());
    }

    pub fn valid(s: *const Spec) bool {
        if (s.width < 5 or s.width > 10 or s.height < 5 or s.height > 10) return false;
        if (s.at.x < 2 or s.at.y < 2 or s.at.x > grid.W - s.width - 2 or s.at.y > grid.H - s.height - 2) return false;
        if (s.pool_n == 0 or s.pool_n > MAX_KINDS) return false;
        for (s.pool[0..s.pool_n]) |e| if (!e.kind.stocked() or e.weight == 0) return false;
        if (s.key) |k| if (!grid.Box.inMap(2).holds(k) or s.room().grown(1).holds(k)) return false;
        return true;
    }

    pub fn cells(s: *const Spec) grid.CellSet {
        var out = grid.CellSet.initEmpty();
        var it = s.room().cells();
        while (it.next()) |p| out.set(grid.Level.idx(p));
        if (s.key) |k| out.set(grid.Level.idx(k));
        return out;
    }

    pub fn stamp(s: *const Spec, lv: *grid.Level, _: u64) void {
        var outside = grid.CellSet.initEmpty();
        for (0..grid.CELLS) |i| {
            const p = grid.Level.of(i);
            if (!s.room().holds(p) and lv.walkable(p)) outside.set(i);
        }
        var it = s.room().grown(1).cells();
        const inner = s.inside();
        while (it.next()) |p| {
            lv.set(p, if (s.room().holds(p) and !inner.holds(p)) .wall else .floor);
            lv.barrel[grid.Level.idx(p)] = false;
        }
        const approach = s.door().add(s.outward());
        s.connectTo(lv, approach, &outside);
        if (s.key) |k| {
            lv.set(k, .floor);
            lv.barrel[grid.Level.idx(k)] = false;
            var dist: [grid.CELLS]i32 = undefined;
            var queue: [grid.CELLS]u32 = undefined;
            _ = grid.distances(lv, approach, &dist, &queue);
            var reached = grid.CellSet.initEmpty();
            for (dist, 0..) |d, i| if (d >= 0) {
                reached.set(i);
            };
            s.connectTo(lv, k, &reached);
        }
        const back = s.door().sub(.{ .x = s.outward().x * (s.width - 2), .y = s.outward().y * (s.height - 2) });
        const across = if (s.side == .w or s.side == .e) P{ .x = 0, .y = -1 } else P{ .x = -1, .y = 0 };
        lv.set(back, .chest);
        lv.set(back.add(across), .chest);
        lv.set(s.door(), if (s.key != null) .locked_gate else .gate);
        if (s.key) |k| lv.set(k, .zoo_key);
        grid.mendProps(&lv.tile);
        gen.shapeWalls(lv);
        gen.keepTorches(lv);
        _ = lv.torch.add(.{ .x = inner.lo.x, .y = s.at.y });
    }

    fn connectTo(s: *const Spec, lv: *grid.Level, from: P, targets: *const grid.CellSet) void {
        if (targets.count() == 0) return;
        var seen = grid.CellSet.initEmpty();
        var back: [grid.CELLS]usize = undefined;
        var queue: [grid.CELLS]P = undefined;
        var head: usize = 0;
        var tail: usize = 1;
        queue[0] = from;
        seen.set(grid.Level.idx(from));
        while (head < tail) : (head += 1) {
            const p = queue[head];
            if (targets.isSet(grid.Level.idx(p))) {
                var at = head;
                while (true) {
                    const q = queue[at];
                    const t = lv.at(q);
                    if (!lv.walkable(q)) lv.set(q, if (t.liquid()) .stone_bridge else .floor);
                    lv.barrel[grid.Level.idx(q)] = false;
                    if (at == 0) return;
                    at = back[at];
                }
            }
            for (mathx.CARDINALS) |d| {
                const q = p.add(d);
                if (!grid.Box.inMap(1).holds(q) or s.room().holds(q)) continue;
                const i = grid.Level.idx(q);
                if (seen.isSet(i)) continue;
                seen.set(i);
                back[tail] = head;
                queue[tail] = q;
                tail += 1;
            }
        }
    }

    pub fn populate(s: *const Spec, lv: *grid.Level, pool: *actor.Pool, rng: *mathx.Rng) void {
        var it = s.inside().cells();
        while (it.next()) |p| {
            if (p.eq(s.threshold()) or !lv.vacant(p)) continue;
            var total: u32 = 0;
            for (s.pool[0..s.pool_n]) |e| if (pool.hasRoomFor(e.kind)) {
                total += e.weight;
            };
            if (total == 0) continue;
            var draw: u32 = @intCast(rng.range(1, @intCast(total)));
            for (s.pool[0..s.pool_n]) |e| {
                if (!pool.hasRoomFor(e.kind)) continue;
                if (draw <= e.weight) {
                    if (actor.row(e.kind).movement == .swimming) lv.set(p, .shallows);
                    _ = pool.spawn(lv, actor.Actor.of(e.kind, p));
                    break;
                }
                draw -= e.weight;
            }
        }
    }

    pub fn collect(s: *const Spec, lv: *grid.Level, at: P) bool {
        const k = s.key orelse return false;
        if (!k.eq(at) or lv.at(k) != .zoo_key) return false;
        lv.set(k, .key_taken);
        return true;
    }

    pub fn open(s: *const Spec, lv: *grid.Level, pool: *actor.Pool) bool {
        const t = lv.at(s.door());
        if (t != .gate and t != .locked_gate) return false;
        if (t == .locked_gate) {
            const k = s.key orelse return false;
            if (lv.at(k) != .key_taken) return false;
        }
        lv.set(s.door(), .open_gate);
        for (pool.slice()) |*a| {
            if (a.livingFoe() and s.inside().holds(a.at)) {
                a.awake = true;
                a.unmask(lv);
                a.submerged = false;
            }
        }
        return true;
    }
};

test "a zoo stays sealed until its own key is taken and opens into a packed room" {
    const s = Spec{ .key = .{ .x = 32, .y = 28 } };
    try std.testing.expect(s.valid());
    var lv = grid.openFloor();
    s.stamp(&lv, 1);
    var pool = actor.Pool{};
    var rng = mathx.Rng.init(3);
    s.populate(&lv, &pool, &rng);
    try std.testing.expectEqual(@as(usize, 21), pool.n);
    try std.testing.expect(!lv.walkable(s.door()) and lv.blocksSight(s.door()));
    try std.testing.expect(!s.open(&lv, &pool));
    for (pool.constSlice()) |a| try std.testing.expect(!a.awake);
    try std.testing.expect(!s.collect(&lv, s.threshold()));
    try std.testing.expect(s.collect(&lv, s.key.?));
    try std.testing.expect(!s.collect(&lv, s.key.?));
    try std.testing.expect(s.open(&lv, &pool));
    try std.testing.expect(lv.walkable(s.door()) and !lv.blocksSight(s.door()));
    for (pool.constSlice()) |a| try std.testing.expect(a.awake);
    try std.testing.expect(!s.open(&lv, &pool));
}

test "zoo populations support every stocked enemy without exceeding split capacity" {
    for (actor.FOES) |kind| {
        var s = Spec{};
        s.pool[0].kind = kind;
        var lv = grid.openFloor();
        s.stamp(&lv, 5);
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(8);
        s.populate(&lv, &pool, &rng);
        try std.testing.expect(pool.n > 0 and pool.eventual() <= actor.MAX);
        try std.testing.expect(s.open(&lv, &pool));
        for (pool.constSlice()) |a| {
            try std.testing.expectEqual(kind, a.kind);
            try std.testing.expect(a.awake and !a.disguised and !a.submerged);
            try std.testing.expect(actor.groundFits(kind, lv.at(a.at)));
        }
    }
}

test "every zoo entrance keeps its walls and room hidden before opening" {
    const fov = @import("fov.zig");
    for (std.enums.values(Side)) |side| {
        const s = Spec{ .side = side };
        var lv = grid.openFloor();
        s.stamp(&lv, 3);
        var seen: [grid.CELLS]bool = @splat(false);
        fov.castInto(&lv, s.door().add(s.outward()), 12, &seen);
        var it = s.inside().cells();
        while (it.next()) |p| try std.testing.expect(!seen[grid.Level.idx(p)]);
        it = s.room().cells();
        while (it.next()) |p| {
            if (!s.inside().holds(p) and !p.eq(s.door())) try std.testing.expectEqual(grid.Tile.wall, lv.at(p));
        }
        var pool = actor.Pool{};
        try std.testing.expect(s.open(&lv, &pool));
        @memset(&seen, false);
        fov.castInto(&lv, s.threshold(), 12, &seen);
        it = s.inside().cells();
        while (it.next()) |p| try std.testing.expect(seen[grid.Level.idx(p)]);
    }
}

test "placing a zoo leaves an unrelated sealed room sealed" {
    const s = Spec{};
    var lv = grid.openFloor();
    const sealed = grid.Box.sized(.{ .x = 10, .y = 10 }, 7, 7);
    var it = sealed.cells();
    while (it.next()) |p| if (!sealed.grown(-1).holds(p)) {
        lv.set(p, .wall);
    };
    s.stamp(&lv, 1);
    it = sealed.cells();
    while (it.next()) |p| if (!sealed.grown(-1).holds(p)) {
        try std.testing.expectEqual(grid.Tile.wall, lv.at(p));
    };
}
