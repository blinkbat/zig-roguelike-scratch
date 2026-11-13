const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const game = @import("../game.zig");
const tactics = @import("tactics_exec.zig");
const rewards = @import("rewards.zig");
const P = mathx.P;

pub fn reached(g: *const game.Game, at: P) bool {
    const from = g.sim.heroAt() orelse return false;
    const z = g.sim.zooNow() orelse return false;
    const t = g.sim.lv.at(at);
    return at.eq(z.door()) and t.closedGate() and game.character.withinReach(from, at) and g.sim.lv.isLit(at);
}

pub fn beside(g: *const game.Game) ?P {
    const z = g.sim.zooNow() orelse return null;
    return if (reached(g, z.door())) z.door() else null;
}

pub fn interact(g: *game.Game, at: P) bool {
    if (!reached(g, at)) return false;
    const z = g.sim.zooNow().?;
    if (!z.open(&g.sim.lv, &g.sim.pool, &g.sim.inventory)) {
        g.sim.log.say("The jail door is locked. Requires a Small Key.", .{});
        game.holdWalk(g);
        return true;
    }
    tactics.beforeAction(&g.sim);
    g.sim.log.push(.danger, "The jail opens. Monsters surge toward the doorway!", .{});
    g.sim.unsaved = true;
    game.holdWalk(g);
    game.castSight(g, g.sim.heroAt().?);
    game.combat.endTurn(g);
    return true;
}

const CARAVAN = @import("../map/atlas.zig").CARAVAN_NODE;
const startAtlas = @import("../map/atlas.zig").testStart;

test "the caravan zoo opens by bump or interact and only spends a turn after unlocking" {
    const h = game.harness;
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try startAtlas();
    defer std.testing.allocator.destroy(map);
    const z = map.node[CARAVAN].zoo.?;
    game.beginMapAt(g, map, .{ .node = CARAVAN, .at = z.approach() }, 77);
    h.toughen(g.sim.heroActor().?);
    const before = g.sim.clock;
    const toward = mathx.dirTo(g.sim.heroAt().?, z.door()).?;
    game.heroStep(g, toward, 0);
    try std.testing.expectEqualDeep(before, g.sim.clock);
    try std.testing.expectEqual(grid.Tile.locked_gate, g.sim.lv.at(z.door()));
    try std.testing.expect(h.logged(g, "locked"));
    try std.testing.expect(g.sim.inventory.add(.{ .kind = .small_key }));
    try std.testing.expect(interact(g, z.door()));
    try std.testing.expectEqual(grid.Tile.open_gate, g.sim.lv.at(z.door()));
    try std.testing.expect(!std.meta.eql(before, g.sim.clock));
    try std.testing.expect(h.logged(g, "Monsters surge"));
    try std.testing.expect(g.sim.heroAt().?.eq(z.approach()));
}

test "interact beside a locked jail gate still reaches a bag lying in reach" {
    const book = @import("../ui/book.zig");
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try startAtlas();
    defer std.testing.allocator.destroy(map);
    const z = map.node[CARAVAN].zoo.?;
    const at = z.approach();
    game.beginMapAt(g, map, .{ .node = CARAVAN, .at = at }, 77);
    try std.testing.expect(beside(g) != null);
    try std.testing.expect(g.sim.ground.add(.{ .item = .{ .kind = .cap }, .at = at }));
    game.harness.pressInteract(g);
    try std.testing.expectEqual(game.Mode.pause, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(book.Page.loot, g.character.page);
    try std.testing.expectEqual(grid.Tile.locked_gate, g.sim.lv.at(z.door()));
    try std.testing.expect(!game.harness.logged(g, "locked"));
}

test "a chest holds a Small Key and keyboard controller and mouse can release the room" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const map = try startAtlas();
    defer std.testing.allocator.destroy(map);
    const z = map.node[CARAVAN].zoo.?;
    const Mode = enum { bump, interact, mouse };
    for (std.enums.values(Mode)) |mode| {
        game.beginMapAt(g, map, .{ .node = CARAVAN, .at = z.key.?.add(.{ .x = 0, .y = 1 }) }, 77);
        try std.testing.expectEqual(grid.Tile.chest, g.sim.lv.at(z.key.?));
        try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
        try std.testing.expectEqual(rewards.Chest.opened, rewards.openChest(&g.sim, z.key.?));
        try std.testing.expectEqual(@as(usize, 1), g.sim.ground.n);
        try std.testing.expectEqual(@import("../play/item_bases.zig").Kind.small_key, g.sim.ground.drops[0].item.kind);
        try std.testing.expectEqual(rewards.Chest.not_closed, rewards.openChest(&g.sim, z.key.?));
        game.character.openLoot(g, z.key.?);
        game.harness.press(g, @import("../ui/menu.zig").CONFIRM);
        game.harness.drawnOut(g);
        try std.testing.expectEqual(@as(usize, 1), g.sim.inventory.n);
        game.heroTo(g, z.approach());
        game.settle(g);
        const before = g.sim.clock;
        switch (mode) {
            .bump => game.heroStep(g, mathx.dirTo(g.sim.heroAt().?, z.door()).?, 0),
            .interact => {
                g.st.interact = true;
                game.update(g, 0);
            },
            .mouse => game.harness.clickCell(g, z.door()),
        }
        try std.testing.expectEqual(grid.Tile.open_gate, g.sim.lv.at(z.door()));
        try std.testing.expectEqual(@as(usize, 0), g.sim.inventory.n);
        try std.testing.expectEqualDeep(game.harness.turned(before, 1), g.sim.clock);
    }
}
