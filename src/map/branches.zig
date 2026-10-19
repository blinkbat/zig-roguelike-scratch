const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const carve = @import("carve.zig");
const wilds = @import("biome/wilds.zig");

const P = mathx.P;
const BLOCK = 2;
const W = @divExact(grid.W, BLOCK);
const H = @divExact(grid.H, BLOCK);
const N = W * H;
const NONE = std.math.maxInt(u16);
const MIN_AREA = 12;
const MAX_AREA = 180;
const MIN_DEPTH = 6;
const LOOP_REACH = 10;
const DIG_MAX = 8;
const PASSES = 64;
const SALT = 0xB2A6_C4E5;
const CHEST_AREA = 500;
const CHEST_MIN = 3;
const CHEST_GAP = 14;
const BARREL_AREA = 150;
const BARREL_MAX = 24;
const BARREL_GAP = 8;

const Branch = struct { root: u16, neck: u16 };

const Graph = struct {
    edges: [N]u8 = @splat(0),
    weight: [N]u8 = @splat(0),
    order: [N]u16 = undefined,
    rank: [N]u16 = @splat(NONE),
    end: [N]u16 = undefined,
    low: [N]u16 = undefined,
    parent: [N]u16 = @splat(NONE),
    area: [N]u16 = undefined,
    branch: [N]Branch = undefined,
    n: usize = 0,

    fn blockOf(p: P) P {
        return .{ .x = @divFloor(p.x, BLOCK), .y = @divFloor(p.y, BLOCK) };
    }

    fn blockAt(node: usize) P {
        return .{ .x = @intCast(node % W), .y = @intCast(@divTrunc(node, W)) };
    }

    fn nodeOf(block: P) usize {
        return mathx.slot(block.x, block.y, W, H).?;
    }

    fn cell(p: P) usize {
        return nodeOf(blockOf(p));
    }

    fn first(lv: *const grid.Level, node: usize) ?P {
        var cells = grid.Box.sized(blockAt(node).scaled(BLOCK), BLOCK, BLOCK).cells();
        while (cells.next()) |p| if (lv.walkable(p)) return p;
        return null;
    }

    fn build(g: *Graph, lv: *const grid.Level, doors: []const P) void {
        g.* = .{};
        for (0..grid.CELLS) |i| {
            const p = grid.Level.of(i);
            if (!lv.walkable(p)) continue;
            const a = cell(p);
            g.weight[a] += 1;
            for (mathx.ALL_DIRS) |d| {
                if (!lv.passOk(p, d)) continue;
                const dir = mathx.dirTo(blockOf(p), blockOf(p.add(d.delta()))) orelse continue;
                g.edges[a] |= @as(u8, 1) << @intFromEnum(dir);
            }
        }
        const origin = if (doors.len > 0) doors[0] else lv.firstOpen() orelse return;
        var stack: [N]u16 = undefined;
        var next: [N]u8 = @splat(0);
        var count: u16 = 0;
        for (0..N) |k| {
            const root = (cell(origin) + k) % N;
            if (g.weight[root] == 0 or g.rank[root] != NONE) continue;
            stack[0] = @intCast(root);
            var top: usize = 1;
            g.enter(@intCast(root), &count);
            while (top > 0) {
                const v = stack[top - 1];
                if (next[v] == mathx.ALL_DIRS.len) {
                    g.end[v] = count;
                    top -= 1;
                    if (g.parent[v] != NONE) {
                        const parent = g.parent[v];
                        g.low[parent] = @min(g.low[parent], g.low[v]);
                        g.area[parent] += g.area[v];
                    }
                    continue;
                }
                const dir = next[v];
                next[v] += 1;
                if (g.edges[v] & (@as(u8, 1) << @intCast(dir)) == 0) continue;
                const to = nodeOf(blockAt(v).add(mathx.ALL_DIRS[dir].delta()));
                if (g.rank[to] == NONE) {
                    g.parent[to] = v;
                    g.enter(@intCast(to), &count);
                    stack[top] = @intCast(to);
                    top += 1;
                } else if (to != g.parent[v]) g.low[v] = @min(g.low[v], g.rank[to]);
            }
        }
        var candidates: [N]bool = @splat(false);
        for (g.order[0..count]) |v| {
            const parent = g.parent[v];
            if (parent == NONE or g.low[v] < g.rank[parent] or g.area[v] < MIN_AREA or g.area[v] > MAX_AREA) continue;
            var protected = false;
            for (doors) |door| {
                if (g.contains(v, cell(door))) protected = true;
            }
            candidates[v] = !protected;
        }
        for (g.order[0..count]) |v| {
            if (!candidates[v]) continue;
            var leaf = true;
            for (g.order[g.rank[v] + 1 .. g.end[v]]) |child| {
                if (candidates[child]) {
                    leaf = false;
                    break;
                }
            }
            if (leaf) {
                g.branch[g.n] = .{ .root = v, .neck = g.parent[v] };
                g.n += 1;
            }
        }
    }

    fn enter(g: *Graph, v: u16, count: *u16) void {
        g.rank[v] = count.*;
        g.low[v] = count.*;
        g.area[v] = g.weight[v];
        g.order[count.*] = v;
        count.* += 1;
    }

    fn contains(g: *const Graph, root: u16, v: usize) bool {
        return g.rank[v] != NONE and g.rank[v] >= g.rank[root] and g.rank[v] < g.end[root];
    }
};

pub const Result = struct { loops: usize = 0, chests: usize = 0, barrels: usize = 0 };

pub fn improves(params: wilds.Params) bool {
    return params.loops > 0 or params.rewards != .none;
}

pub fn improve(lv: *grid.Level, seed: u64, doors: []const P, params: wilds.Params) Result {
    var result = Result{};
    const loops = params.loops;
    if (!improves(params)) return result;
    const pal = wilds.palette(params);
    var rng = mathx.Rng.init(seed ^ SALT);
    var g: Graph = .{};
    var attempted: [N]bool = @splat(false);
    var distances: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    g.build(lv, doors);
    var pass: usize = 0;
    while (loops > 0 and pass < PASSES) : (pass += 1) {
        var choices: [N]Branch = undefined;
        var n: usize = 0;
        for (g.branch[0..g.n]) |b| {
            if (!attempted[b.root]) {
                choices[n] = b;
                n += 1;
            }
        }
        if (n == 0) break;
        const b = choices[rng.below(@intCast(n))];
        attempted[b.root] = true;
        if (!rng.percent(loops)) continue;
        const neck = Graph.first(lv, b.neck) orelse continue;
        _ = grid.distances(lv, neck, &distances, &queue);
        if (rejoin(lv, &g, b, &distances, &queue, pal)) {
            result.loops += 1;
            g.build(lv, doors);
        }
    }
    if (params.rewards == .chests) {
        var reached: [grid.CELLS]i32 = undefined;
        var open = lv.openCount();
        for (g.branch[0..g.n]) |b| {
            const neck = Graph.first(lv, b.neck) orelse continue;
            _ = grid.distances(lv, neck, &distances, &queue);
            while (true) {
                var far: ?P = null;
                var deepest: i32 = MIN_DEPTH - 1;
                for (0..grid.CELLS) |i| {
                    const p = grid.Level.of(i);
                    if (!g.contains(b.root, Graph.cell(p)) or distances[i] <= deepest or !rewardAt(lv, p)) continue;
                    deepest = distances[i];
                    far = p;
                }
                const p = far orelse break;
                const was = lv.at(p);
                lv.set(p, .chest);
                if (grid.distances(lv, neck, &reached, &queue) == open - 1) {
                    result.chests += 1;
                    open -= 1;
                    break;
                }
                lv.set(p, was);
                distances[grid.Level.idx(p)] = -1;
            }
        }
        var blocked = lv.*;
        for (blocked.barrel, 0..) |on, i| {
            if (on) blocked.tile[i] = .wall;
        }
        const origin = blocked.firstOpen() orelse return result;
        const available = blocked.openCount();
        result.chests += stock(lv, &blocked, origin, doors, &rng, .chest, @min(CHEST_MIN, available / CHEST_AREA), CHEST_GAP);
        result.barrels = stock(lv, &blocked, origin, doors, &rng, .barrel, @min(BARREL_MAX, available / BARREL_AREA), BARREL_GAP);
    }
    return result;
}

const Reward = enum {
    chest,
    barrel,

    fn has(kind: Reward, lv: *const grid.Level, p: P) bool {
        return switch (kind) {
            .chest => lv.at(p) == .chest,
            .barrel => lv.hasBarrel(p),
        };
    }
};

fn stock(lv: *grid.Level, blocked: *grid.Level, origin: P, doors: []const P, rng: *mathx.Rng, kind: Reward, target: usize, gap: i32) usize {
    var spots: [grid.CELLS]P = undefined;
    var count: usize = 0;
    var placed: [grid.CELLS]P = undefined;
    var have: usize = 0;
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        if (kind.has(lv, p)) {
            placed[have] = p;
            have += 1;
        }
        if (!rewardAt(lv, p) or p.eq(origin)) continue;
        var near_door = false;
        for (doors) |door| {
            if (mathx.dist(p, door) < MIN_DEPTH) near_door = true;
        }
        if (near_door) continue;
        var edges: usize = 0;
        for (mathx.CARDINALS) |d| {
            const q = p.add(d);
            if (!grid.Level.onRim(q) and lv.at(q).solid() and lv.at(q) != .chest) edges += 1;
        }
        if (edges < @as(usize, if (kind == .chest) 2 else 1)) continue;
        spots[count] = p;
        count += 1;
    }
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var open = blocked.openCount();
    var added: usize = 0;
    while (have < target and count > 0) {
        const pick = rng.below(@intCast(count));
        const p = spots[pick];
        count -= 1;
        spots[pick] = spots[count];
        var near = false;
        for (placed[0..have]) |other| {
            if (mathx.dist(p, other) < gap) near = true;
        }
        if (near) continue;
        const was = blocked.at(p);
        blocked.set(p, .chest);
        if (grid.distances(blocked, origin, &dist, &queue) != open - 1) {
            blocked.set(p, was);
            continue;
        }
        switch (kind) {
            .chest => lv.set(p, .chest),
            .barrel => lv.putBarrel(p),
        }
        placed[have] = p;
        have += 1;
        added += 1;
        open -= 1;
    }
    return added;
}

fn rewardAt(lv: *const grid.Level, p: P) bool {
    if (grid.Level.onRim(p) or !lv.vacant(p) or lv.doorAt(p) != null or lv.torch.has(lume.torchWall(p))) return false;
    for (mathx.ALL_DIRS) |d| {
        const q = p.add(d.delta());
        if (lv.at(q) == .chest or lv.hasBarrel(q)) return false;
    }
    return switch (lv.at(p)) {
        .grass, .dirt, .sand, .floor, .rubble, .tiny_shrub, .tall_grass, .shrooms => true,
        .wall, .shrub, .rock, .snow, .water, .shallows, .bridge, .reeds, .fence, .lava, .fungus, .chasm, .ice, .grave, .crop, .boulder, .chest, .chest_open => false,
    };
}

fn rejoin(lv: *grid.Level, g: *const Graph, b: Branch, distances: *const [grid.CELLS]i32, queue: *[grid.CELLS]u32, pal: carve.Palette) bool {
    var previous: [grid.CELLS]u32 = @splat(std.math.maxInt(u32));
    var depth: [grid.CELLS]u8 = @splat(0);
    var head: usize = 0;
    var tail: usize = 0;
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        if (!lv.walkable(p) or distances[i] < MIN_DEPTH or !g.contains(b.root, Graph.cell(p))) continue;
        for (mathx.ALL_DIRS) |dir| {
            const q = p.add(dir.delta());
            if (grid.Level.onRim(q) or lv.at(q) != pal.solid) continue;
            const k = grid.Level.idx(q);
            if (depth[k] != 0) continue;
            depth[k] = 1;
            previous[k] = @intCast(i);
            queue[tail] = @intCast(k);
            tail += 1;
        }
    }
    while (head < tail) : (head += 1) {
        const i = queue[head];
        const p = grid.Level.of(i);
        for (mathx.ALL_DIRS) |dir| {
            const q = p.add(dir.delta());
            if (grid.Level.onRim(q)) continue;
            const k = grid.Level.idx(q);
            if (lv.walkable(q) and !g.contains(b.root, Graph.cell(q)) and distances[k] >= LOOP_REACH) {
                var back = i;
                while (depth[back] != 0) {
                    lv.tile[back] = carve.Palette.TRAILED.path;
                    back = previous[back];
                }
                return true;
            }
            if (lv.at(q) != pal.solid or depth[k] != 0 or depth[i] == DIG_MAX) continue;
            depth[k] = depth[i] + 1;
            previous[k] = i;
            queue[tail] = @intCast(k);
            tail += 1;
        }
    }
    return false;
}

test "side paths rejoin through forest and true dead ends receive closed chests" {
    var base = grid.Level.blank();
    carve.box(&base, .{ .lo = .{ .x = 8, .y = 8 }, .hi = .{ .x = 42, .y = 38 } }, .shrub);
    carve.box(&base, .{ .lo = .{ .x = 10, .y = 10 }, .hi = .{ .x = 40, .y = 12 } }, .grass);
    carve.box(&base, .{ .lo = .{ .x = 20, .y = 12 }, .hi = .{ .x = 22, .y = 32 } }, .grass);
    carve.box(&base, .{ .lo = .{ .x = 28, .y = 12 }, .hi = .{ .x = 30, .y = 32 } }, .grass);
    const doors = [_]P{ .{ .x = 10, .y = 10 }, .{ .x = 39, .y = 10 } };
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var joined = base;
    const loops = improve(&joined, 44, &doors, .{ .loops = 100 });
    try std.testing.expect(loops.loops > 0);
    try std.testing.expect(joined.openCount() > base.openCount());
    try std.testing.expectEqual(joined.openCount(), grid.distances(&joined, doors[0], &dist, &queue));
    for (base.tile, joined.tile) |before, after| {
        if (before != after) {
            try std.testing.expectEqual(grid.Tile.shrub, before);
            try std.testing.expectEqual(grid.Tile.dirt, after);
        }
    }
    var rewarded = base;
    const rewards = improve(&rewarded, 44, &doors, .{ .rewards = .chests });
    var deep: usize = 0;
    for (rewarded.tile, 0..) |t, i| {
        if (t == .chest) {
            try std.testing.expect(grid.Level.of(i).y >= 28);
            deep += 1;
        }
        try std.testing.expect(t != .chest_open);
    }
    try std.testing.expectEqual(@as(usize, 2), deep);
    try std.testing.expectEqual(deep, rewards.chests);
    try std.testing.expectEqual(rewarded.openCount(), grid.distances(&rewarded, doors[0], &dist, &queue));
    for (doors) |p| try std.testing.expect(rewarded.walkable(p));
    std.debug.print("two side paths: {d} connection(s) through forest, or {d} closed rewards at their ends; both exits preserved\n", .{ loops.loops, rewards.chests });
}

test "a chest never takes the floor a torch hangs over" {
    var lv = grid.openFloor();
    const p = P{ .x = 10, .y = 10 };
    lv.set(lume.torchWall(p), .wall);
    try std.testing.expect(rewardAt(&lv, p));
    try std.testing.expect(lv.torch.add(lume.torchWall(p)));
    try std.testing.expect(!rewardAt(&lv, p));
}

test "scattered rewards leave narrow routes and the approach to existing treasure open" {
    var lv = grid.Level.blank();
    carve.box(&lv, grid.Box.sized(.{ .x = 10, .y = 10 }, 60, 1), .grass);
    const doors = [_]P{ .{ .x = 10, .y = 10 }, .{ .x = 69, .y = 10 } };
    for (doors, 0..) |p, i| lv.putDoor(p, i);
    var blocked = lv;
    var rng = mathx.Rng.init(44);
    try std.testing.expectEqual(@as(usize, 0), stock(&lv, &blocked, doors[0], &doors, &rng, .chest, 3, CHEST_GAP));
    try std.testing.expectEqual(@as(usize, 0), stock(&lv, &blocked, doors[0], &doors, &rng, .barrel, 12, BARREL_GAP));
    const at = P{ .x = 40, .y = 10 };
    lv.set(at.add(.{ .x = 0, .y = 1 }), .chest);
    try std.testing.expect(!rewardAt(&lv, at));
    lv.set(at.add(.{ .x = 0, .y = 1 }), .grass);
    lv.putBarrel(at.add(.{ .x = 0, .y = 1 }));
    try std.testing.expect(!rewardAt(&lv, at));
    std.debug.print("60-cell route: no chest or barrel blocks it; neither can take the sole approach to existing treasure\n", .{});
}

test "a clearing without dead ends puts chests in sheltered corners and barrels along its edges" {
    var lv = grid.Level.blank();
    const room = grid.Box.sized(.{ .x = 8, .y = 8 }, 80, 48);
    carve.box(&lv, room, .grass);
    const origin = P{ .x = 8, .y = 32 };
    lv.putDoor(origin, 0);
    var g: Graph = .{};
    g.build(&lv, &.{origin});
    try std.testing.expectEqual(@as(usize, 0), g.n);
    const result = improve(&lv, 44, &.{origin}, .{ .rewards = .chests });
    try std.testing.expectEqual(@as(usize, 3), result.chests);
    try std.testing.expect(result.barrels >= 12);
    var blocked = lv;
    for (lv.tile, 0..) |t, i| {
        if (t == .chest) {
            const p = grid.Level.of(i);
            try std.testing.expect(p.x == room.lo.x or p.x == room.hi.x - 1);
            try std.testing.expect(p.y == room.lo.y or p.y == room.hi.y - 1);
        }
        if (lv.barrel[i]) blocked.tile[i] = .wall;
    }
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    try std.testing.expectEqual(blocked.openCount(), grid.distances(&blocked, origin, &dist, &queue));
    std.debug.print("clearing with no dead ends: {d} corner chests and {d} edge barrels, every route open\n", .{ result.chests, result.barrels });
}
