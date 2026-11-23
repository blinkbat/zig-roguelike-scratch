const std = @import("std");
const rl = @import("raylib");
const atlas = @import("../map/atlas.zig");
const grid = @import("../map/grid.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const preview = @import("preview.zig");

pub const Thumbnails = struct {
    textures: [atlas.MAX_NODES]?rl.Texture2D = @splat(null),
    valid: std.StaticBitSet(atlas.MAX_NODES) = .initEmpty(),
    scratch: grid.Level = undefined,

    pub fn deinit(self: *Thumbnails) void {
        for (&self.textures) |*t| raster.release(t);
        self.invalidateAll();
    }

    pub fn invalidate(self: *Thumbnails, node: usize) void {
        self.valid.unset(node);
    }

    pub fn invalidateAll(self: *Thumbnails) void {
        self.valid = .initEmpty();
    }

    pub fn changedMap(self: *Thumbnails, now: *const atlas.Atlas, before: *const atlas.Atlas) void {
        if (now.node_n != before.node_n) return self.invalidateAll();
        if (!std.meta.eql(now.start, before.start)) {
            self.invalidate(now.start.node);
            self.invalidate(before.start.node);
        }
        for (now.node[0..now.node_n], before.node[0..before.node_n], 0..) |*current, *previous, n| {
            if (!std.mem.eql(u8, std.mem.asBytes(current), std.mem.asBytes(previous))) self.invalidate(n);
        }
    }

    pub fn standable(self: *Thumbnails, map: *const atlas.Atlas, from: atlas.Start) bool {
        return map.standable(from, &self.scratch);
    }

    pub fn get(self: *Thumbnails, map: *const atlas.Atlas, scene: *const preview.Scene, n: usize, picture: rl.Rectangle, canvas: rl.Rectangle) ?rl.Texture2D {
        if (!rl.checkCollisionRecs(picture, canvas)) return null;
        if (!self.valid.isSet(n)) {
            const texture = self.textures[n] orelse raster.canvas(grid.W, grid.H, look.BG, .point) orelse return null;
            self.textures[n] = texture;
            const lv = self.terrain(map, scene, n);
            var px: [grid.CELLS]rl.Color = undefined;
            for (&px, 0..) |*c, i| {
                c.* = if (look.Mark.of(lv, i)) |m|
                    m.look().fg
                else if (if (lv.wallShape(grid.Level.of(i))) |s| s.solid() else false)
                    look.BG
                else
                    look.mini(lv.tile[i], true);
            }
            rl.updateTexture(texture, &px);
            self.valid.set(n);
        }
        return self.textures[n];
    }

    fn terrain(self: *Thumbnails, map: *const atlas.Atlas, scene: *const preview.Scene, n: usize) *const grid.Level {
        const node = &map.node[n];
        if (n == scene.node and !scene.stale and node.plan == .bespoke and node.zoo == null) return &scene.lv;
        node.stampAt(&self.scratch, scene.roll, preview.arrival(map, n));
        return &self.scratch;
    }
};

test "thumbnail terrain does not depend on a selected preview's occupants" {
    const alloc = std.testing.allocator;
    const map = try atlas.testAtlas();
    defer alloc.destroy(map);
    const room = grid.Box.centred(35, 35);
    _ = map.oneRoom(room, room.centre());
    map.node[0].zoo = .{ .key = .{ .x = 32, .y = 28 } };
    var scene: preview.Scene = .{};
    var thumbnails: Thumbnails = .{};
    const at = map.start.at;
    const original = thumbnails.terrain(map, &scene, 0).at(at);
    scene.node = 0;
    scene.stale = false;
    scene.lv = thumbnails.scratch;
    scene.lv.set(at, if (original == .shallows) .floor else .shallows);
    try std.testing.expectEqual(original, thumbnails.terrain(map, &scene, 0).at(at));
}

test "thumbnail invalidation follows changed nodes and discards identities after node removal" {
    const alloc = std.testing.allocator;
    const map = try alloc.create(atlas.Atlas);
    defer alloc.destroy(map);
    map.* = .{};
    for (0..3) |_| _ = map.add(.{ .bespoke = .{} });
    const before = try alloc.create(atlas.Atlas);
    defer alloc.destroy(before);
    before.* = map.*;
    var thumbnails = Thumbnails{};
    thumbnails.valid = .initFull();
    _ = map.node[1].rename("Changed");
    thumbnails.changedMap(map, before);
    try std.testing.expect(thumbnails.valid.isSet(0));
    try std.testing.expect(!thumbnails.valid.isSet(1));
    try std.testing.expect(thumbnails.valid.isSet(2));
    thumbnails.valid.set(1);
    map.start = .{ .node = 2, .at = grid.MIDDLE };
    thumbnails.changedMap(map, before);
    try std.testing.expect(!thumbnails.valid.isSet(0));
    try std.testing.expect(!thumbnails.valid.isSet(2));
    map.remove(0);
    thumbnails.changedMap(map, before);
    try std.testing.expectEqual(@as(usize, 0), thumbnails.valid.count());
    thumbnails.valid = .initFull();
    thumbnails.invalidate(2);
    try std.testing.expect(thumbnails.valid.isSet(0) and !thumbnails.valid.isSet(2));
    thumbnails.invalidateAll();
    try std.testing.expectEqual(@as(usize, 0), thumbnails.valid.count());
}
