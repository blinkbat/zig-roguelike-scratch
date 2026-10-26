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
        for (&self.textures) |*t| {
            if (t.*) |texture| rl.unloadTexture(texture);
            t.* = null;
        }
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
            const lv = if (n == scene.node and !scene.stale) &scene.lv else blk: {
                map.node[n].stamp(&self.scratch, scene.roll);
                break :blk &self.scratch;
            };
            var px: [grid.CELLS]rl.Color = undefined;
            for (&px, 0..) |*c, i| {
                c.* = if (look.Mark.of(lv, i)) |m|
                    m.look().fg
                else if (if (lv.wallShape(grid.Level.of(i))) |s| s.solid() else false)
                    look.BG
                else
                    look.mini(lv.tile[i], true);
            }
            if (self.textures[n] == null) {
                self.textures[n] = raster.canvas(grid.W, grid.H, look.BG, .point);
            }
            if (self.textures[n]) |t| rl.updateTexture(t, &px);
            self.valid.set(n);
        }
        return self.textures[n];
    }
};

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
    map.remove(0);
    thumbnails.changedMap(map, before);
    try std.testing.expectEqual(@as(usize, 0), thumbnails.valid.count());
    thumbnails.valid = .initFull();
    thumbnails.invalidate(2);
    try std.testing.expect(thumbnails.valid.isSet(0) and !thumbnails.valid.isSet(2));
    thumbnails.invalidateAll();
    try std.testing.expectEqual(@as(usize, 0), thumbnails.valid.count());
    std.debug.print("thumbnail owner: local edit preserves other nodes; removal and reroll invalidate every cached identity\n", .{});
}
