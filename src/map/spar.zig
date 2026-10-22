const std = @import("std");
const atlas = @import("atlas.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const mathx = @import("../core/mathx.zig");
const actor = @import("../play/actor.zig");

const ROOM = grid.Box.centred(19, 9);
const MIDDLE = ROOM.centre();
/// How far either side of the middle the hero and foe begin.
const APART = mathx.P{ .x = 3, .y = 0 };
pub const HERO = MIDDLE.sub(APART);
pub const FOE = MIDDLE.add(APART);
/// Between torches along the top wall.
const TORCH_STEP: i32 = 6;

pub fn author(map: *atlas.Atlas, kind: actor.Kind) void {
    std.debug.assert(kind.foe());
    const node = map.oneRoom(ROOM, HERO);
    _ = map.node[node].rename("Arena");
    const room = &map.node[node].plan.bespoke;
    for ([_]i32{ -TORCH_STEP, 0, TORCH_STEP }) |dx| std.debug.assert(room.torch.add(lume.torchOver(ROOM, MIDDLE.x + dx)));
    std.debug.assert(room.addFoe(.{ .kind = kind, .at = FOE }));
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
        try std.testing.expectEqual(HERO.x - ROOM.lo.x, ROOM.hi.x - 1 - FOE.x);
        try std.testing.expect(room.bodies() <= actor.MAX);
        for (room.tile, 0..) |tile, i| try std.testing.expectEqual(ROOM.holds(grid.Level.of(i)), tile == .floor);
        for (room.torches()) |torch| try std.testing.expect(map.node[0].torchFits(room, torch));
        checked += 1;
    }
    std.debug.print("{d} arena opponents: one foe, reserved split capacity, sealed floor and valid torches\n", .{checked});
}
