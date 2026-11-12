const std = @import("std");
const mathx = @import("../core/mathx.zig");
const zoo = @import("../map/zoo.zig");
const grid = @import("../map/grid.zig");
const game = @import("../game.zig");
const tactics = @import("tactics_exec.zig");
const P = mathx.P;

fn spec(g: *const game.Game) ?zoo.Spec {
    const map = g.sim.map orelse return null;
    return map.node[g.sim.node].zoo;
}

pub fn reached(g: *const game.Game, at: P) bool {
    const from = g.sim.heroAt() orelse return false;
    const z = spec(g) orelse return false;
    const t = g.sim.lv.at(at);
    return at.eq(z.door()) and (t == .gate or t == .locked_gate) and mathx.dist(from, at) <= 1 and g.sim.lv.isLit(at);
}

pub fn beside(g: *const game.Game) ?P {
    const z = spec(g) orelse return null;
    return if (reached(g, z.door())) z.door() else null;
}

pub fn interact(g: *game.Game, at: P) bool {
    if (!reached(g, at)) return false;
    const z = spec(g).?;
    if (!z.open(&g.sim.lv, &g.sim.pool)) {
        g.sim.log.say("The jail door is locked. Find its key.", .{});
        game.holdWalk(g);
        return true;
    }
    tactics.beforeAction(&g.sim);
    g.sim.log.push(.danger, "The jail opens. Monsters surge toward the doorway!", .{});
    g.sim.unsaved = true;
    g.mouse.stop();
    game.holdWalk(g);
    game.castSight(g, g.sim.heroAt().?);
    game.combat.endTurn(g);
    return true;
}

pub fn arrive(g: *game.Game, at: P) void {
    const z = spec(g) orelse return;
    if (!z.collect(&g.sim.lv, at)) return;
    g.sim.log.say("{s} takes the jail key.", .{g.sim.name.text()});
    g.sim.unsaved = true;
}

test "the caravan zoo opens by bump or interact and only spends a turn after unlocking" {
    const atlas = @import("../map/atlas.zig");
    const h = game.harness;
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try std.testing.allocator.create(atlas.Atlas);
    defer std.testing.allocator.destroy(map);
    try map.load(std.testing.allocator, atlas.START);
    const z = map.node[1].zoo.?;
    game.beginMapAt(g, map, .{ .node = 1, .at = z.door().add(z.outward()) }, 77);
    h.toughen(g.sim.heroActor().?);
    const before = g.sim.clock;
    const toward = mathx.dirTo(g.sim.heroAt().?, z.door()).?;
    game.heroStep(g, toward, 0);
    try std.testing.expectEqualDeep(before, g.sim.clock);
    try std.testing.expectEqual(grid.Tile.locked_gate, g.sim.lv.at(z.door()));
    try std.testing.expect(h.logged(g, "locked"));
    try std.testing.expect(z.collect(&g.sim.lv, z.key.?));
    try std.testing.expect(interact(g, z.door()));
    try std.testing.expectEqual(grid.Tile.open_gate, g.sim.lv.at(z.door()));
    try std.testing.expect(!std.meta.eql(before, g.sim.clock));
    try std.testing.expect(h.logged(g, "Monsters surge"));
    try std.testing.expect(g.sim.heroAt().?.eq(z.door().add(z.outward())));
}

test "zoo keys collect on arrival and keyboard controller and mouse can release the room" {
    const atlas = @import("../map/atlas.zig");
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try atlas.testAtlas();
    defer std.testing.allocator.destroy(map);
    try map.load(std.testing.allocator, atlas.START);
    const z = map.node[1].zoo.?;
    const Mode = enum { bump, interact, mouse };
    for (std.enums.values(Mode)) |mode| {
        game.beginMapAt(g, map, .{ .node = 1, .at = z.key.? }, 77);
        try std.testing.expectEqual(grid.Tile.key_taken, g.sim.lv.at(z.key.?));
        try std.testing.expect(game.harness.logged(g, "takes the jail key"));
        game.heroTo(g, z.door().add(z.outward()));
        game.settle(g);
        const before = g.sim.clock;
        switch (mode) {
            .bump => game.heroStep(g, mathx.dirTo(g.sim.heroAt().?, z.door()).?, 0),
            .interact => {
                g.st.interact = true;
                game.update(g, 0);
            },
            .mouse => game.harness.clickAt(g, game.scene.Cam.of(g).mid(z.door())),
        }
        try std.testing.expectEqual(grid.Tile.open_gate, g.sim.lv.at(z.door()));
        var expected = before;
        _ = expected.turn();
        try std.testing.expectEqualDeep(expected, g.sim.clock);
    }
}
