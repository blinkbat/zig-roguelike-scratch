const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");
const buildings = @import("buildings.zig");

// Dwarf Fortress's hamlet fields, Path of Exile's Ogham Farmlands, Diablo II's corrals, Qud's watervine farms (crop: reeds, furrows: shallows).

pub const COUNT_MAX: u8 = 16;
pub const SIZE_MIN: u8 = 6;
pub const SIZE_MAX: u8 = 24;

pub const Params = struct {
    count: u8 = 5,
    /// Smallest and largest side, fence and all.
    size: [2]u8 = .{ 8, 16 },
    crop: grid.Tile = .crop,
    furrow: grid.Tile = .dirt,
    fence: grid.Tile = .fence,

    pub fn fit(p: Params) Params {
        var q = p;
        q.count = std.math.clamp(p.count, 1, COUNT_MAX);
        q.size = mathx.span(u8, p.size, SIZE_MIN, SIZE_MAX);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, pal: carve.Palette, p: Params) void {
    var lots: buildings.Lots(COUNT_MAX) = .{};
    for (0..p.count) |_| {
        const b = lots.take(lv, rng, rng.range(p.size[0], p.size[1]), rng.range(p.size[0], p.size[1])) orelse continue;
        const across = rng.chance(0.5);
        var cells = b.cells();
        while (cells.next()) |q| {
            const row = if (across) q.y - b.lo.y else q.x - b.lo.x;
            lv.set(q, if (b.onEdge(q)) p.fence else if (@mod(row, 2) == 0) p.furrow else p.crop);
        }
        buildings.openWay(lv, buildings.doorway(rng, b), p.furrow, pal.open);
    }
}

test "fields are fenced, in furrows of crop" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xFA2);
    carve.field(&lv, carve.Palette.WILD);
    apply(&lv, &rng, 0, .{ .open = .grass, .solid = .shrub, .path = .dirt }, .{});
    std.debug.print("5 fields: {d} fence, {d} crop, {d} furrow\n", .{ carve.count(&lv, .fence), carve.count(&lv, .crop), carve.count(&lv, .dirt) });
    try std.testing.expect(carve.count(&lv, .crop) > 50 and carve.count(&lv, .fence) > 50);
}
