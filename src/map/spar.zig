const std = @import("std");
const atlas = @import("atlas.zig");
const grid = @import("grid.zig");
const actor = @import("../play/actor.zig");

pub const ROOM = grid.Box.centred(19, 9);
pub const HERO = grid.MIDDLE.sub(.{ .x = 3, .y = 0 });
pub const FOE = grid.MIDDLE.add(.{ .x = 3, .y = 0 });

pub fn author(map: *atlas.Atlas, kind: actor.Kind) void {
    std.debug.assert(kind.foe());
    map.* = .{};
    const node = map.add(.{ .bespoke = .{} }).?;
    _ = map.node[node].rename("Arena");
    const room = &map.node[node].plan.bespoke;
    var cells = ROOM.cells();
    while (cells.next()) |p| room.tile[grid.Level.idx(p)] = .floor;
    for ([_]i32{ -6, 0, 6 }) |dx| std.debug.assert(room.torch.add(.{ .x = grid.MIDDLE.x + dx, .y = ROOM.lo.y - 1 }));
    std.debug.assert(room.addFoe(.{ .kind = kind, .at = FOE }));
    map.start = .{ .node = node, .at = HERO };
}

test "the arena contains one selected foe, a sealed room and an open start" {
    const map = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(map);
    var checked: usize = 0;
    for (std.enums.values(actor.Kind)) |kind| {
        if (!kind.foe()) continue;
        author(map, kind);
        try std.testing.expectEqual(@as(usize, 1), map.node_n);
        const room = &map.node[0].plan.bespoke;
        try std.testing.expectEqual(@as(usize, 1), room.foe_n);
        try std.testing.expectEqual(kind, room.foe[0].kind);
        try std.testing.expect(room.floorAt(HERO) and room.floorAt(FOE));
        try std.testing.expect(room.bodies() <= actor.MAX);
        for (room.tile, 0..) |tile, i| try std.testing.expectEqual(ROOM.holds(grid.Level.of(i)), tile == .floor);
        for (room.torches()) |torch| try std.testing.expect(map.node[0].torchFits(room, torch));
        checked += 1;
    }
    std.debug.print("{d} arena opponents: one foe, reserved split capacity, sealed floor and valid torches\n", .{checked});
}
