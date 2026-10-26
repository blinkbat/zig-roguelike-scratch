const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const P = mathx.P;
const INITIAL_ROLL: u64 = 0x5EE;

pub const Issues = struct {
    unlinked: usize = 0,
    /// Open cells no walk from the start or a door reaches.
    cut_off: usize = 0,
    foes_cut_off: usize = 0,
    start_walled: bool = false,
    reach_from: ?P = null,
};

pub const Scene = struct {
    lv: grid.Level = undefined,
    node: ?usize = null,
    stale: bool = true,
    roll: u64 = INITIAL_ROLL,
    rolled_foes: actor.Pool = .{},
    shown: [actor.MAX]atlas.Foe = undefined,
    shown_n: usize = 0,
    issues: Issues = .{},
    start_at: ?P = null,
    reach_dist: [grid.CELLS]i32 = undefined,
    reach_queue: [grid.CELLS]u32 = undefined,

    pub fn invalidate(self: *Scene) void {
        self.stale = true;
    }

    pub fn reset(self: *Scene) void {
        self.roll = INITIAL_ROLL;
        self.node = null;
        self.invalidate();
    }

    pub fn reroll(self: *Scene) void {
        self.roll = std.hash.Wyhash.hash(self.roll, "again");
        self.invalidate();
    }

    pub fn relinked(self: *Scene, nd: *const atlas.Node) void {
        self.issues.unlinked = nd.unlinked();
    }

    pub fn ensure(self: *Scene, map: *const atlas.Atlas, node: usize) void {
        if (!self.stale and self.node == node) return;
        self.node = node;
        const nd = &map.node[node];
        self.rolled_foes = .{};
        switch (nd.plan) {
            .bespoke => nd.sketch(&self.lv),
            .procgen => |*pg| {
                nd.stamp(&self.lv, self.roll);
                var rng = mathx.Rng.init(self.roll);
                const at = atlas.landing(&self.lv, arrival(map, node), nd.placed()) orelse arrival(map, node);
                _ = self.rolled_foes.spawn(&self.lv, actor.Actor.of(actor.HERO, at));
                pack.place(&self.lv, &self.rolled_foes, &rng, at, &pg.foes);
                self.lv.clear(at);
            },
        }
        self.shown_n = 0;
        for (nd.placed()) |f| self.show(f);
        for (self.rolled_foes.slice()) |a| {
            if (a.foe()) self.show(.{ .kind = a.kind, .at = a.at });
        }
        self.start_at = self.startOn(map, node);
        self.issues = self.issuesOf(map, node);
        self.stale = false;
    }

    fn show(self: *Scene, f: atlas.Foe) void {
        self.shown[self.shown_n] = f;
        self.shown_n += 1;
    }

    pub fn shownFoes(self: *const Scene) []const atlas.Foe {
        return self.shown[0..self.shown_n];
    }

    fn startOn(self: *Scene, map: *const atlas.Atlas, node: usize) ?P {
        const s = map.start;
        if (s.node != node) return null;
        return atlas.landing(&self.lv, s.at, map.node[node].placed());
    }

    fn issuesOf(self: *Scene, map: *const atlas.Atlas, node: usize) Issues {
        const nd = &map.node[node];
        var is = Issues{ .unlinked = nd.unlinked() };
        const s = map.start;
        if (s.node == node) is.start_walled = !self.lv.walkable(s.at);
        var flood: ?grid.Flood = null;
        if (self.start_at) |at| flood = grid.Flood.init(&self.lv, at, &self.reach_dist, &self.reach_queue);
        for (nd.doors()) |d| {
            if (!self.lv.walkable(d.at)) continue;
            if (flood) |*f| {
                f.seed(d.at);
            } else flood = grid.Flood.init(&self.lv, d.at, &self.reach_dist, &self.reach_queue);
        }
        if (flood) |*f| {
            while (f.next()) |_| {}
        } else @memset(&self.reach_dist, -1);
        for (0..grid.CELLS) |i| {
            if (!self.cutOff(i)) continue;
            is.cut_off += 1;
            if (is.reach_from == null) is.reach_from = grid.Level.of(i);
        }
        for (nd.placed()) |foe| {
            const i = grid.Level.idx(foe.at);
            if (self.reach_dist[i] < 0) is.foes_cut_off += 1;
        }

        return is;
    }

    pub fn cutOff(self: *const Scene, i: usize) bool {
        return !self.lv.tile[i].solid() and self.reach_dist[i] < 0;
    }
};

pub fn arrival(map: *const atlas.Atlas, node: usize) P {
    if (map.start.node == node) return map.start.at;
    const ds = map.node[node].doors();
    return if (ds.len > 0) ds[0].at else grid.MIDDLE;
}

test "preview selection invalidation and rerolls never mutate the authored map" {
    const alloc = std.testing.allocator;
    const map = try alloc.create(atlas.Atlas);
    defer alloc.destroy(map);
    map.* = .{};
    const room = grid.Box.centred(9, 9);
    _ = map.oneRoom(room, room.centre());
    const other = map.add(.{ .procgen = .{} }).?;
    const before = try alloc.create(atlas.Atlas);
    defer alloc.destroy(before);
    before.* = map.*;
    const scene = try alloc.create(Scene);
    defer alloc.destroy(scene);
    scene.* = .{};

    scene.ensure(map, 0);
    try std.testing.expectEqual(@as(?P, room.centre()), scene.start_at);
    const painted = scene.lv.tile;
    scene.ensure(map, other);
    try std.testing.expect(scene.start_at == null);
    const first = scene.lv.tile;
    const foes = scene.shown_n;
    scene.ensure(map, other);
    try std.testing.expectEqualSlices(grid.Tile, &first, &scene.lv.tile);
    try std.testing.expectEqual(foes, scene.shown_n);
    scene.reroll();
    scene.ensure(map, other);
    try std.testing.expect(!std.mem.eql(grid.Tile, &first, &scene.lv.tile));
    scene.reset();
    scene.ensure(map, other);
    try std.testing.expectEqualSlices(grid.Tile, &first, &scene.lv.tile);
    scene.ensure(map, 0);
    try std.testing.expectEqualSlices(grid.Tile, &painted, &scene.lv.tile);
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(before), std.mem.asBytes(map));

    map.node[0].plan.bespoke.tile[grid.Level.idx(room.centre())] = .water;
    scene.invalidate();
    scene.ensure(map, 0);
    try std.testing.expectEqual(grid.Tile.water, scene.lv.at(room.centre()));
    std.debug.print("preview owner: selection, cache reuse, reroll, reset and authored edits; map remains unchanged by all previews\n", .{});
}
