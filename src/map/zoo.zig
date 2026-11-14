const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const gen = @import("gen.zig");
const carve = @import("carve.zig");
const lume = @import("lume.zig");
const actor = @import("../play/actor.zig");
const Inventory = @import("../play/inventory.zig").Inventory;
const P = mathx.P;

pub const MAX_KINDS = 16;
const SIZE_MIN: u8 = 5;
const SIZE_MAX: u8 = 10;
const MARGIN: i32 = 2;
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
        return s.room().inner();
    }

    pub fn reserved(s: *const Spec) grid.Box {
        return s.room().grown(1);
    }

    pub fn reserves(s: *const Spec, p: P) bool {
        return s.reserved().holds(p) or s.keyAt(p);
    }

    pub fn entries(s: *const Spec) []const Entry {
        return s.pool[0..s.pool_n];
    }

    pub fn occupies(s: *const Spec, p: P) bool {
        return s.room().holds(p) or s.keyAt(p);
    }

    fn dir(s: *const Spec) mathx.Dir {
        return switch (s.side) {
            inline else => |t| @field(mathx.Dir, @tagName(t)),
        };
    }

    fn along(s: *const Spec) i32 {
        return carve.alongOf(s.dir(), s.room().centre());
    }

    pub fn door(s: *const Spec) P {
        return carve.sideAt(s.room(), s.dir(), s.along());
    }

    fn outward(s: *const Spec) P {
        return s.dir().delta();
    }

    pub fn threshold(s: *const Spec) P {
        return s.door().sub(s.outward());
    }

    pub fn approach(s: *const Spec) P {
        return s.door().add(s.outward());
    }

    pub fn keyAt(s: *const Spec, p: P) bool {
        return if (s.key) |k| k.eq(p) else false;
    }

    pub fn valid(s: *const Spec) bool {
        if (s.width < SIZE_MIN or s.width > SIZE_MAX or s.height < SIZE_MIN or s.height > SIZE_MAX) return false;
        if (s.at.x < MARGIN or s.at.y < MARGIN or s.at.x > grid.W - s.width - MARGIN or s.at.y > grid.H - s.height - MARGIN) return false;
        if (s.pool_n == 0 or s.pool_n > MAX_KINDS) return false;
        for (s.entries()) |e| if (!e.kind.stocked() or e.weight == 0) return false;
        if (s.key) |k| if (!grid.Box.inMap(MARGIN).holds(k) or s.reserved().holds(k)) return false;
        return true;
    }

    pub fn cells(s: *const Spec) grid.CellSet {
        var out = grid.CellSet.initEmpty();
        grid.markBox(&out, s.room());
        if (s.key) |k| out.set(grid.Level.idx(k));
        return out;
    }

    pub fn keyReachable(s: *const Spec, distances: *const [grid.CELLS]i32) bool {
        const at = s.key orelse return true;
        for (grid.STEPS) |delta| {
            if (grid.cellOr(i32, distances, at.add(delta), -1) >= 0) return true;
        }
        return false;
    }

    pub fn stamp(s: *const Spec, lv: *grid.Level) void {
        const r = s.room();
        var outside = grid.CellSet.initEmpty();
        for (0..grid.CELLS) |i| {
            const p = grid.Level.of(i);
            if (lv.walkable(p) and !s.occupies(p)) outside.set(i);
        }
        var it = s.reserved().cells();
        const inner = s.inside();
        while (it.next()) |p| {
            lv.set(p, if (r.onEdge(p)) .wall else .floor);
            _ = lv.breakBarrel(p);
        }
        const way_in = s.approach();
        s.connectTo(lv, way_in, &outside);
        if (s.key) |k| {
            lv.set(k, .floor);
            _ = lv.breakBarrel(k);
            const joined = reachedFrom(lv, way_in);
            s.connectTo(lv, k, &joined);
            lv.set(k, .chest);
            const kept = reachedFrom(lv, way_in);
            for (grid.STEPS) |d| {
                const n = k.add(d);
                if (grid.Level.inside(n) and joined.isSet(grid.Level.idx(n)) and !kept.isSet(grid.Level.idx(n))) s.connectTo(lv, n, &kept);
            }
        }
        const back = carve.sideAt(inner, s.dir().opposite(), s.along());
        lv.set(back, .chest);
        lv.set(back.sub(s.dir().across()), .chest);
        lv.set(s.door(), if (s.key != null) .locked_gate else .gate);
        grid.mendProps(&lv.tile);
        gen.reshape(lv);
        lv.addTorch(lume.torchOver(inner, inner.lo.x));
    }

    fn reachedFrom(lv: *const grid.Level, from: P) grid.CellSet {
        var dist: [grid.CELLS]i32 = undefined;
        var queue: [grid.CELLS]u32 = undefined;
        var flood = grid.Flood.init(lv, from, &dist, &queue);
        var out = grid.CellSet.initEmpty();
        while (flood.next()) |p| out.set(grid.Level.idx(p));
        return out;
    }

    fn connectTo(s: *const Spec, lv: *grid.Level, from: P, targets: *const grid.CellSet) void {
        if (targets.count() == 0) return;
        var dist: [grid.CELLS]i32 = undefined;
        var reach: [grid.CELLS]u32 = undefined;
        var flood = grid.Flood.init(lv, from, &dist, &reach);
        while (flood.next()) |p| if (targets.isSet(grid.Level.idx(p))) return;
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
                    carve.layWith(lv, q, .floor, .stone_bridge);
                    _ = lv.breakBarrel(q);
                    if (at == 0) return;
                    at = back[at];
                }
            }
            for (mathx.CARDINALS) |d| {
                const q = p.add(d);
                if (grid.Level.onRim(q) or s.occupies(q)) continue;
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
            for (s.entries()) |e| if (pool.hasRoomFor(e.kind)) {
                total += e.weight;
            };
            if (total == 0) continue;
            var draw: u32 = @intCast(rng.range(1, @intCast(total)));
            for (s.entries()) |e| {
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

    pub fn open(s: *const Spec, lv: *grid.Level, pool: *actor.Pool, inventory: *Inventory) bool {
        const t = lv.at(s.door());
        if (!t.closedGate()) return false;
        if (t == .locked_gate and !inventory.takeSmallKey()) return false;
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

test "a zoo accepts any Small Key and consumes one only when a locked gate opens" {
    const s = Spec{ .key = .{ .x = 32, .y = 28 } };
    try std.testing.expect(s.valid());
    var lv = grid.openFloor();
    s.stamp(&lv);
    var pool = actor.Pool{};
    var inventory = Inventory{};
    var rng = mathx.Rng.init(3);
    s.populate(&lv, &pool, &rng);
    try std.testing.expectEqual(@as(usize, 21), pool.n);
    try std.testing.expect(!lv.walkable(s.door()) and lv.blocksSight(s.door()));
    try std.testing.expect(!s.open(&lv, &pool, &inventory));
    for (pool.constSlice()) |a| try std.testing.expect(!a.awake);
    try std.testing.expectEqual(grid.Tile.chest, lv.at(s.key.?));
    for (0..2) |_| try std.testing.expect(inventory.add(.{ .kind = .small_key }));
    try std.testing.expect(s.open(&lv, &pool, &inventory));
    try std.testing.expectEqual(@as(usize, 1), inventory.n);
    try std.testing.expectEqual(grid.Tile.chest, lv.at(s.key.?));
    try std.testing.expect(lv.walkable(s.door()) and !lv.blocksSight(s.door()));
    for (pool.constSlice()) |a| try std.testing.expect(a.awake);
    try std.testing.expect(!s.open(&lv, &pool, &inventory));
    try std.testing.expectEqual(@as(usize, 1), inventory.n);
    lv.set(s.door(), .gate);
    try std.testing.expect(s.open(&lv, &pool, &inventory));
    try std.testing.expectEqual(@as(usize, 1), inventory.n);
}

test "the key chest never stands in the only way to the gate" {
    const s = Spec{ .key = .{ .x = 38, .y = 21 } };
    try std.testing.expect(s.valid());
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| if (grid.Level.of(i).x >= 20) {
        lv.tile[i] = .rock;
    };
    s.stamp(&lv);
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&lv, .{ .x = 5, .y = 5 }, &dist, &queue);
    try std.testing.expect(dist[grid.Level.idx(s.approach())] >= 0);
    try std.testing.expect(s.keyReachable(&dist));
}

test "a key chest on the only corridor to the gate leaves the gate reachable" {
    const s = Spec{ .key = .{ .x = 30, .y = 21 } };
    try std.testing.expect(s.valid());
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        if (p.x >= 20 and !(p.y == 21 and p.x <= 38)) lv.tile[i] = .rock;
    }
    s.stamp(&lv);
    try std.testing.expectEqual(grid.Tile.chest, lv.at(s.key.?));
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&lv, .{ .x = 5, .y = 5 }, &dist, &queue);
    try std.testing.expect(dist[grid.Level.idx(s.approach())] >= 0);
    try std.testing.expect(s.keyReachable(&dist));
}

test "zoo populations support every stocked enemy without exceeding split capacity" {
    for (actor.FOES) |kind| {
        var s = Spec{};
        s.pool[0].kind = kind;
        var lv = grid.openFloor();
        s.stamp(&lv);
        var pool = actor.Pool{};
        var rng = mathx.Rng.init(8);
        s.populate(&lv, &pool, &rng);
        try std.testing.expect(pool.n > 0 and pool.eventual() <= actor.MAX);
        var inventory = Inventory{};
        try std.testing.expect(s.open(&lv, &pool, &inventory));
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
        s.stamp(&lv);
        var seen: [grid.CELLS]bool = @splat(false);
        fov.castInto(&lv, s.approach(), 12, &seen);
        var it = s.inside().cells();
        while (it.next()) |p| try std.testing.expect(!seen[grid.Level.idx(p)]);
        it = s.room().cells();
        while (it.next()) |p| {
            if (s.room().onEdge(p) and !p.eq(s.door())) try std.testing.expectEqual(grid.Tile.wall, lv.at(p));
        }
        var pool = actor.Pool{};
        var inventory = Inventory{};
        try std.testing.expect(s.open(&lv, &pool, &inventory));
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
    while (it.next()) |p| if (sealed.onEdge(p)) {
        lv.set(p, .wall);
    };
    s.stamp(&lv);
    it = sealed.cells();
    while (it.next()) |p| if (sealed.onEdge(p)) {
        try std.testing.expectEqual(grid.Tile.wall, lv.at(p));
    };
}

test "a zoo whose ring already meets open ground carves nothing into a nearer sealed room" {
    const s = Spec{ .side = .e };
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| if (grid.Level.of(i).x >= s.reserved().lo.x) {
        lv.tile[i] = .rock;
    };
    const vault = grid.Box.sized(s.approach().add(.{ .x = 2, .y = -3 }), 5, 7);
    var it = vault.cells();
    while (it.next()) |p| lv.set(p, if (vault.onEdge(p)) .wall else .floor);
    s.stamp(&lv);
    it = vault.cells();
    while (it.next()) |p| if (vault.onEdge(p)) {
        try std.testing.expectEqual(grid.Tile.wall, lv.at(p));
    };
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&lv, .{ .x = 5, .y = 5 }, &dist, &queue);
    try std.testing.expect(dist[grid.Level.idx(s.approach())] >= 0);
}

test "a key chest touching the zoo's ring only at a corner is reachable" {
    var s = Spec{};
    const ring = s.reserved();
    s.key = .{ .x = ring.hi.x, .y = ring.lo.y - 1 };
    try std.testing.expect(s.valid());
    var lv = grid.openFloor();
    for (&lv.tile) |*t| t.* = .rock;
    var it = grid.Box.sized(.{ .x = 2, .y = grid.H - 8 }, 4, 4).cells();
    while (it.next()) |p| lv.set(p, .floor);
    s.stamp(&lv);
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    _ = grid.distances(&lv, s.approach(), &dist, &queue);
    try std.testing.expect(s.keyReachable(&dist));
}
