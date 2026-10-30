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
    if (!actor.groundFits(kind, .floor)) {
        var pond = grid.Box.around(FOE, POND).cells();
        while (pond.next()) |p| room.tile[grid.Level.idx(p)] = .water;
    }
    std.debug.assert(map.node[node].foeFits(room, FOE, kind));
    std.debug.assert(room.addFoe(.{ .kind = kind, .at = FOE }));
}

/// Cells round an opponent that cannot stand on floor that are water, short of the hero.
const POND: i32 = 1;

comptime {
    std.debug.assert(mathx.dist(HERO, FOE) > POND + 1);
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
        const swims = actor.row(kind).movement == .swimming;
        try std.testing.expect(room.floorAt(HERO) and map.node[0].foeFits(room, FOE, kind));
        try std.testing.expectEqual(HERO.x - ROOM.lo.x, ROOM.hi.x - 1 - FOE.x);
        try std.testing.expect(room.bodies() <= actor.MAX);
        for (room.tile, 0..) |tile, i| {
            const p = grid.Level.of(i);
            const pond = swims and mathx.dist(p, FOE) <= POND;
            try std.testing.expectEqual(ROOM.holds(p) and !pond, tile == .floor);
            try std.testing.expectEqual(pond, tile == .water);
        }
        for (room.torches()) |torch| try std.testing.expect(map.node[0].torchFits(room, torch));
        checked += 1;
    }
    std.debug.print("{d} arena opponents: one foe, reserved split capacity, sealed floor and valid torches\n", .{checked});
}
