const std = @import("std");
const rl = @import("raylib");
const atlas = @import("../../map/atlas.zig");
const day = @import("../../map/day.zig");
const game = @import("../../game.zig");
const capture = @import("capture.zig");

pub fn captureZoo(g: *game.Game) !void {
    try std.fs.cwd().makePath(capture.SHOTS_DIR);
    const w = try capture.heapAtlas();
    defer capture.dropAtlas(g, w);
    try w.load(std.heap.c_allocator, atlas.START);
    const z = w.node[atlas.CARAVAN_NODE].zoo orelse return error.NoZoo;
    game.beginMapAt(g, w, .{ .node = atlas.CARAVAN_NODE, .at = z.key.?.add(.{ .x = 0, .y = 1 }) }, capture.SHOT_SEED);
    g.sim.clock = day.Clock.at(day.NOON);
    game.harness.toughen(g.sim.heroActor().?);
    game.settle(g);
    const target = try capture.renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try capture.capture(g, target, capture.SHOTS_DIR ++ "/zoo-key-chest.png");
    if (!game.combat.openChest(g, z.key.?)) return error.KeyChestDidNotOpen;
    game.harness.drawnOut(g);
    game.character.openLoot(g, z.key.?);
    try capture.capture(g, target, capture.SHOTS_DIR ++ "/zoo-small-key-loot.png");
    game.harness.press(g, @import("../../ui/menu.zig").CONFIRM);
    game.harness.drawnOut(g);
    if (g.sim.inventory.n != 1 or g.sim.inventory.bag[0].kind != .small_key) return error.KeyNotCollected;
    game.character.openCharacter(g);
    g.character.choose(.inventory);
    try capture.capture(g, target, capture.SHOTS_DIR ++ "/zoo-small-key-inventory.png");
    game.toPlay(g);
    game.heroTo(g, z.approach());
    game.settle(g);
    try capture.capture(g, target, capture.SHOTS_DIR ++ "/zoo-closed.png");
    if (!game.jail.interact(g, z.door())) return error.DoorDidNotOpen;
    game.harness.drawnOut(g);
    try capture.capture(g, target, capture.SHOTS_DIR ++ "/zoo-rush.png");

    game.beginMapAt(g, w, .{ .node = atlas.CARAVAN_NODE, .at = z.approach() }, capture.SHOT_SEED);
    g.sim.clock = day.Clock.at(day.NOON);
    if (!g.sim.inventory.add(.{ .kind = .small_key }) or !z.open(&g.sim.lv, &g.sim.pool, &g.sim.inventory)) return error.DoorDidNotOpen;
    game.heroTo(g, z.threshold());
    game.settle(g);
    try capture.capture(g, target, capture.SHOTS_DIR ++ "/zoo-reveal.png");
    std.debug.print("Packed zoo: {d:.3} ms mean draw, {d} actors on map\n", .{
        try @import("bench.zig").meanDraw(g, target, 3, 60), g.sim.pool.n,
    });
}
