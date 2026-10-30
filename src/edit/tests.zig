const interaction = @import("interaction.zig");
const placement = @import("placement.zig");
const widgets = @import("widgets.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const listing = @import("../map/listing.zig");
const carve = @import("../map/carve.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const menu = @import("../ui/menu.zig");
const knobs = @import("knobs.zig");
const modals = @import("modals.zig");
const panel = @import("panel.zig");
const editor = @import("editor.zig");
const P = mathx.P;

test "editor input gives modal and view changes priority over canvas gestures" {
    const ed = try editor.Editor.create(std.testing.allocator);
    defer ed.destroy();
    const bounds = raster.rect(0, 0, 800, 600);
    const before = ed.map.node[0].plan.bespoke.tile;
    const history_at = ed.history.at;
    ed.desk = .{ .help = true, .paint_hit = true, .paint = true, .mouse = .{ .x = 64, .y = 64 } };
    interaction.step(ed, bounds, 720, 0);
    try std.testing.expect(ed.modal == .help);
    try std.testing.expectEqualDeep(before, ed.map.node[0].plan.bespoke.tile);
    try std.testing.expectEqual(history_at, ed.history.at);
    ed.desk = .{ .back = true, .paint_hit = true, .paint = true, .mouse = .{ .x = 64, .y = 64 } };
    interaction.step(ed, bounds, 720, 0);
    try std.testing.expect(ed.modal == .none and ed.fresh);
    try std.testing.expectEqualDeep(before, ed.map.node[0].plan.bespoke.tile);
    ed.desk = .{ .graph = true, .paint_hit = true, .paint = true, .mouse = .{ .x = 64, .y = 64 } };
    interaction.step(ed, bounds, 720, 0);
    try std.testing.expect(ed.view == .graph);
    try std.testing.expect(ed.drag == null and ed.linking == null);
    try std.testing.expectEqual(history_at, ed.history.at);
    std.debug.print("editor input: modal opening, modal dismissal and view switching consume their canvas clicks\n", .{});
}

test "editor workspaces retain a useful viewport and shape hit targets do not overlap" {
    try std.testing.expectEqual(@as(i32, 24), widgets.TEXT);
    try std.testing.expect(widgets.DETAIL >= 20);
    for (@import("../core/window.zig").SCREENS) |screen| {
        try std.testing.expect(screen.y - panel.WORKSPACE_TOP >= 380);
        try std.testing.expect(screen.x - widgets.PANEL_W > grid.W * 8);
    }
    for (editor.SHAPES, 0..) |_, i| {
        const r = panel.shapeSlot(panel.WORKSPACE_TOP, i);
        try std.testing.expect(r.x >= widgets.PAD and r.x + r.width <= widgets.PANEL_W - widgets.PAD);
        try std.testing.expect(r.width >= 120 and r.height >= widgets.TEXT + 8);
        for (0..i) |j| try std.testing.expect(!rl.checkCollisionRecs(r, panel.shapeSlot(panel.WORKSPACE_TOP, j)));
    }
    std.debug.print("editor layout: 3 supported screens retain at least 380px of workspace; 6 readable shape targets stay separate\n", .{});
}

test "disabled editor controls expose their tooltip without accepting a click" {
    const ed = try editor.Editor.create(std.testing.allocator);
    defer ed.destroy();
    const r = widgets.row(10, 10, 100);
    ed.desk = .{ .mouse = .{ .x = 15, .y = 15 }, .paint_hit = true };
    const disabled = widgets.hot(ed.controls(), r, false, false, editor.GENERATED);
    try std.testing.expect(!disabled.hot and !disabled.hit);
    try std.testing.expectEqualStrings(editor.GENERATED, ed.tip.?);
    ed.tip = null;
    ed.clip = raster.rect(200, 200, 20, 20);
    try std.testing.expect(!widgets.hot(ed.controls(), r, false, false, editor.GENERATED).hit);
    try std.testing.expect(ed.tip == null);
    ed.clip = null;
    ed.modal = .help;
    try std.testing.expect(!widgets.hot(ed.controls(), r, true, false, editor.GENERATED).hit);
    try std.testing.expect(ed.tip == null);
    try std.testing.expect(widgets.hot(ed.controls(), r, true, true, null).hit);
    ed.fresh = true;
    try std.testing.expect(!widgets.hot(ed.controls(), r, true, true, null).hit);
    ed.fresh = false;
    ed.action = .quit;
    try std.testing.expect(!widgets.hot(ed.controls(), r, true, true, null).hit);
    ed.action = .none;
    ed.modal = .none;
    ed.popup = .{ .slot = r, .which = .algo };
    try std.testing.expect(!widgets.hot(ed.controls(), r, true, false, null).hit);
    try std.testing.expect(widgets.hot(ed.controls(), r, true, true, null).hit);
    std.debug.print("editor hover: disabled tooltip, clipping, modal/popup layers, opening-frame and pending-action click suppression checked\n", .{});
}

fn testEditor() !*editor.Editor {
    const ed = try editor.Editor.create(std.testing.allocator);
    ed.map.* = .{};
    ed.setPath(atlas.mapPath("test_editor"));
    return ed;
}

test "the object viewer fights only foes without changing the edited map" {
    const ed = try editor.Editor.create(std.testing.allocator);
    defer ed.destroy();
    const before = ed.map.node[0].plan.bespoke.tile;
    var fights: usize = 0;
    for (editor.SEEN, 0..) |seen, i| {
        ed.seen_at = i;
        ed.action = .none;
        ed.modal = .objects;
        ed.desk = .{ .enter = true };
        interaction.modalKeys(ed);
        if (modals.seenFoe(seen)) |kind| {
            try std.testing.expectEqual(kind, ed.action.fight);
            fights += 1;
        } else try std.testing.expect(ed.action == .none);
    }
    try std.testing.expect(!ed.history.dirty);
    try std.testing.expectEqualSlices(grid.Tile, &before, &ed.map.node[0].plan.bespoke.tile);
    std.debug.print("object viewer: {d} foe forms can launch a fight; terrain and hero entries cannot\n", .{fights});
}

fn testBespoke() !*editor.Editor {
    const ed = try testEditor();
    _ = ed.map.add(.{ .bespoke = .{} });
    return ed;
}

fn dragFirstBox(ed: *editor.Editor) P {
    const was = ed.map.node[0].pos;
    ed.view = .graph;
    ed.gesture();
    ed.drag = .{ .node = 0, .grab = .{ .x = 0, .y = 0 }, .from = .{ .x = 100, .y = 100 } };
    ed.desk = .{ .paint = true, .mouse = .{ .x = 200, .y = 100 } };
    interaction.graphMouse(ed, TEST_CANVAS, true);
    return was;
}

fn mouseOn(ed: *const editor.Editor, c: rl.Rectangle, p: P) P {
    const r = ed.cellRect(c, p);
    return .{ .x = @as(i32, @intFromFloat(r.x)) + 1, .y = @as(i32, @intFromFloat(r.y)) + 1 };
}

fn click(ed: *editor.Editor, t: editor.Tool, p: P) void {
    ed.gesture();
    ed.tool = t;
    placement.place(ed, p);
}

fn paintClick(ed: *editor.Editor, t: grid.Tile, p: P) void {
    ed.ink.set(.first, t);
    click(ed, .paint, p);
    ed.ink.set(.first, .floor);
}

test "the erasing cursor marks a cell legal exactly when erasing it there removes something" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 5 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 5 });
    click(ed, .door, .{ .x = 10, .y = 5 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 5 });
    click(ed, .barrel, .{ .x = 7, .y = 5 });
    click(ed, .torch, .{ .x = 6, .y = 4 });
    const tools = [_]editor.Tool{ .barrel, .torch, .{ .foe = .pib }, .link, .start, .door };
    const cells = [_]P{ .{ .x = 5, .y = 5 }, .{ .x = 7, .y = 5 }, .{ .x = 6, .y = 4 }, .{ .x = 10, .y = 5 }, .{ .x = 8, .y = 5 } };
    var removed: usize = 0;
    for (tools) |t| for (cells) |p| {
        ed.tool = t;
        ed.gesture();
        const before = ed.history.at;
        const want = placement.removable(ed, p);
        placement.remove(ed, p);
        try std.testing.expectEqual(want, ed.history.at != before);
        if (want) removed += 1;
    };
    try std.testing.expectEqual(@as(usize, 4), removed);
    std.debug.print("erase cursor: {d} tool/cell pairs agree with erasing, {d} removed\n", .{ tools.len * cells.len, removed });
}

test "painting a bespoke node: a door opens its wall and no wall paints over it" {
    const ed = try testEditor();
    defer ed.destroy();
    const w = ed.map;
    _ = w.add(.{ .bespoke = .{} });
    ed.tool = .paint;
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 5 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 5 });
    click(ed, .door, .{ .x = 10, .y = 5 });
    paintClick(ed, .wall, .{ .x = 10, .y = 5 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 5 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 9 });
    click(ed, .torch, .{ .x = 6, .y = 4 });
    click(ed, .torch, .{ .x = 6, .y = 3 });
    ed.gesture();
    ed.tool = .paint;
    placement.remove(ed, .{ .x = 4, .y = 5 });
    ed.preview();
    try std.testing.expectEqual(grid.Tile.wall, ed.scene.lv.at(.{ .x = 4, .y = 5 }));
    try std.testing.expect(ed.scene.lv.walkable(.{ .x = 10, .y = 5 }));
    try std.testing.expectEqual(@as(?usize, 0), ed.scene.lv.doorAt(.{ .x = 10, .y = 5 }));
    try std.testing.expectEqual(@as(usize, 1), w.node[0].plan.bespoke.foe_n);
    try std.testing.expectEqual(@as(usize, 1), ed.scene.lv.torch.n);
    try std.testing.expect(ed.history.dirty);
    const map = look.Assets.of(&ed.scene.lv);
    try std.testing.expect(std.meta.eql(map.merge(look.Assets.everything()), look.Assets.everything()));
    try std.testing.expect(look.Assets.everything().bodies.contains(.rat) and look.Assets.everything().bodies.contains(.slime_quarter) and look.Assets.everything().barrel);
}

test "the link tool joins doors on two nodes, and a procgen node takes doors but no floor" {
    const ed = try testEditor();
    defer ed.destroy();
    const w = ed.map;
    _ = w.add(.{ .bespoke = .{} });
    _ = w.add(.{ .procgen = .{} });
    click(ed, .door, .{ .x = 3, .y = 3 });
    ed.select(1);
    click(ed, .door, .{ .x = 40, .y = 30 });
    click(ed, .link, .{ .x = 40, .y = 30 });
    ed.select(0);
    click(ed, .link, .{ .x = 3, .y = 3 });
    try std.testing.expectEqual(@as(?atlas.Link, .{ .node = 1, .door = 0 }), w.node[0].door[0].to);
    try std.testing.expectEqual(@as(?atlas.Link, .{ .node = 0, .door = 0 }), w.node[1].door[0].to);
    try std.testing.expect(!@as(editor.Tool, .paint).fits(&w.node[1]));
    try std.testing.expect(@as(editor.Tool, .door).fits(&w.node[1]));
    ed.select(1);
    ed.preview();
    try std.testing.expectEqual(@as(?usize, 0), ed.scene.lv.doorAt(.{ .x = 40, .y = 30 }));
}

test "a gesture is one undo however much it paints, and redo puts it back" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.gesture();
    ed.tool = .paint;
    placement.laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 11, .y = 6 });
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 2, .y = 8 }, .erase = false, .shape = .rect }, .{ .x = 3, .y = 8 });
    ed.gesture();
    try std.testing.expectEqual(@as(usize, 52), count(ed, .floor));
    try std.testing.expectEqual(@as(usize, 2), ed.history.at);
    ed.undo();
    try std.testing.expectEqual(@as(usize, 50), count(ed, .floor));
    ed.undo();
    try std.testing.expectEqual(@as(usize, 0), count(ed, .floor));
    ed.redo();
    ed.redo();
    try std.testing.expectEqual(@as(usize, 52), count(ed, .floor));
    ed.undo();
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 20, .y = 20 }, .erase = false, .shape = .rect }, .{ .x = 20, .y = 20 });
    try std.testing.expectEqual(ed.history.at, ed.history.len);
    try std.testing.expectEqual(@as(usize, 51), count(ed, .floor));
    std.debug.print("two strokes over 52 cells, then one after an undo: {d} undo steps\n", .{ed.history.at});
}

test "undo keeps no more than its cap, dropping the oldest" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    for (0..editor.UNDO_CAP + 5) |i| {
        ed.gesture();
        placement.place(ed, .{ .x = @intCast(1 + i), .y = 1 });
    }
    try std.testing.expectEqual(editor.UNDO_CAP, ed.history.len);
    for (0..editor.UNDO_CAP) |_| ed.undo();
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 5, .y = 1 }));
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 1 }));
}

test "undoing back to what was saved leaves nothing unsaved, and a press held through New lets go" {
    const ed = try testBespoke();
    defer ed.destroy();
    click(ed, .paint, .{ .x = 3, .y = 3 });
    ed.history.markSaved();
    click(ed, .paint, .{ .x = 4, .y = 3 });
    ed.undo();
    try std.testing.expect(!ed.history.dirty);
    ed.undo();
    try std.testing.expect(ed.history.dirty);
    ed.redo();
    try std.testing.expect(!ed.history.dirty);
    ed.drag = .{ .node = 0, .grab = .{ .x = 0, .y = 0 }, .from = .{ .x = 0, .y = 0 } };
    ed.span = .{ .from = .{ .x = 1, .y = 1 }, .erase = false, .shape = .rect };
    ed.history.dirty = false;
    ed.request(.new);
    try std.testing.expect(ed.drag == null and ed.span == null);
}

const TEST_CANVAS = rl.Rectangle{ .x = 0, .y = 0, .width = 2000, .height = 2000 };

test "a fast stroke paints every cell it passes, and Esc mid-rectangle lets the press go" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ 0, 0 };
    ed.tool = .paint;
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    interaction.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 12, .y = 2 }) };
    interaction.mapMouse(ed, c, true);
    const row_n = rowCount(ed, 2, .floor);
    interaction.mapMouse(ed, c, false);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    interaction.mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 4, .y = 4 }));
    ed.desk = .{};
    interaction.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .paint_hit = true, .shift = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 6 }) };
    ed.gesture();
    interaction.mapMouse(ed, c, true);
    try std.testing.expect(ed.span != null);
    interaction.escape(ed);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 8, .y = 6 }) };
    interaction.mapMouse(ed, c, true);
    const stray = tileAt(ed, .{ .x = 8, .y = 6 });
    std.debug.print("a stroke dragged 10 cells in one frame: {d} cells painted\n", .{row_n});
    try std.testing.expectEqual(@as(usize, 11), row_n);
    try std.testing.expectEqual(grid.Tile.wall, stray);
    try std.testing.expect(ed.standable(.{ .node = 0, .at = .{ .x = 30, .y = 30 } }));
    _ = ed.map.add(.{ .bespoke = .{} });
    try std.testing.expect(!ed.standable(.{ .node = 1, .at = .{ .x = 30, .y = 30 } }));
}

test "a stroke leaving the map paints up to its edge, and it ends with the button that began it" {
    const ed = try testBespoke();
    defer ed.destroy();
    const b = &ed.map.node[0].plan.bespoke;
    const c = TEST_CANVAS;
    ed.cam = .{ -4, 0 };
    ed.tool = .paint;
    ed.gesture();
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 5, .y = 10 }) };
    interaction.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = -3, .y = 10 }) };
    interaction.mapMouse(ed, c, true);
    const row_n = rowCount(ed, 10, .floor);
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 20, .y = 20 }) };
    interaction.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 10 }) };
    interaction.mapMouse(ed, c, true);
    std.debug.print("a stroke from x 5 to x -3 in one frame: {d} cells painted to the edge\n", .{row_n});
    try std.testing.expectEqual(@as(usize, 6), row_n);
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 4, .y = 10 }));
    click(ed, .torch, .{ .x = 3, .y = 9 });
    try std.testing.expectEqual(@as(usize, 1), b.torch.n);
    paintClick(ed, .wall, .{ .x = 3, .y = 10 });
    try std.testing.expectEqual(@as(usize, 0), b.torch.n);
    ed.tool = .paint;
    ed.desk = .{ .shift = true, .paint = true, .erase = true, .paint_hit = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 8, .y = 8 }) };
    interaction.mapMouse(ed, c, true);
    try std.testing.expect(!ed.span.?.erase);
}

test "a click off the map ends the stroke held through it" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ 0, 0 };
    ed.tool = .paint;
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    interaction.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = .{ .x = -5, .y = -5 } };
    ed.gesture();
    interaction.mapMouse(ed, c, false);
    ed.desk = .{ .paint = true, .erase = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 2 }) };
    interaction.mapMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 1), ed.history.at);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 4, .y = 2 }));
}

test "a rectangle begun off the map fills from its edge" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ -4, -4 };
    ed.tool = .paint;
    ed.gesture();
    ed.desk = .{ .shift = true, .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = -2, .y = -2 }) };
    interaction.mapMouse(ed, c, true);
    ed.desk = .{ .shift = true, .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    interaction.mapMouse(ed, c, true);
    ed.desk = .{ .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    interaction.mapMouse(ed, c, true);
    const n = count(ed, .floor);
    std.debug.print("a rectangle from -2,-2 to 4,4: {d} cells of floor\n", .{n});
    try std.testing.expectEqual(@as(usize, 25), n);
}

test "a click on the frame a rectangle is let go is an undo of its own" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ 0, 0 };
    ed.tool = .paint;
    ed.desk = .{ .shift = true, .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    interaction.mapMouse(ed, c, true);
    ed.desk = .{ .erase = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 6, .y = 4 }) };
    ed.gesture();
    interaction.mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 4 }));
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 5, .y = 4 }));
    ed.undo();
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 6, .y = 4 }));
}

test "a door on a wall taken away takes the torch it held up" {
    const ed = try testBespoke();
    defer ed.destroy();
    const b = &ed.map.node[0].plan.bespoke;
    const door = P{ .x = 6, .y = 5 };
    const torch = lume.torchWall(door);
    _ = ed.map.addDoor(0, door);
    try std.testing.expect(b.torch.add(torch));
    try std.testing.expect(ed.here().torchFits(b, torch));
    ed.gesture();
    ed.tool = .door;
    placement.remove(ed, door);
    try std.testing.expectEqual(@as(usize, 0), b.torch.n);
}

test "the other button pressed mid graph drag puts the box back, and leaves no undo" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    const was = dragFirstBox(ed);
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = .{ .x = 300, .y = 100 } };
    ed.drop();
    ed.desk = .{ .paint = true, .erase = true, .mouse = .{ .x = 400, .y = 100 } };
    interaction.graphMouse(ed, c, true);
    ed.desk = .{ .mouse = .{ .x = 400, .y = 100 } };
    interaction.graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 0), ed.history.at);
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expect(!ed.history.dirty);
}

test "leaving with unsaved changes asks first, and leaving a saved map does not" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.request(.leave);
    try std.testing.expect(ed.action == .leave);
    ed.action = .none;
    click(ed, .paint, .{ .x = 3, .y = 3 });
    ed.request(.leave);
    try std.testing.expectEqual(editor.Modal{ .prompt = .confirm }, ed.modal);
    try std.testing.expect(ed.action == .none);
    ed.commit();
    try std.testing.expect(ed.action == .leave);
}

test "leaving or closing mid graph drag keeps the move and asks before discarding it" {
    for ([_]editor.Pending{ .leave, .quit }) |pending| {
        const ed = try testBespoke();
        defer ed.destroy();
        const was = dragFirstBox(ed);
        const moved = ed.map.node[0].pos;
        try std.testing.expect(!moved.eq(was));
        ed.request(pending);
        try std.testing.expectEqual(editor.Modal{ .prompt = .confirm }, ed.modal);
        try std.testing.expect(ed.action == .none);
        try std.testing.expect(ed.drag == null);
        try std.testing.expectEqual(moved, ed.map.node[0].pos);
        try std.testing.expect(ed.history.dirty);
        ed.modal = .none;
        ed.undo();
        try std.testing.expectEqual(was, ed.map.node[0].pos);
        try std.testing.expect(!ed.history.dirty);
    }
    std.debug.print("2 departure paths preserve an active graph move, prompt, and undo to the saved state\n", .{});
}

test "Save As, a play-test or a rename mid graph drag keeps the move as its own undo" {
    for ([_]enum { save_as, play, rename }{ .save_as, .play, .rename }) |by| {
        const ed = try testBespoke();
        defer ed.destroy();
        ed.map.node[ed.map.start.node].plan.bespoke.tile[grid.Level.idx(ed.map.start.at)] = .floor;
        const was = dragFirstBox(ed);
        const moved = ed.map.node[0].pos;
        switch (by) {
            .play => {
                ed.action = .{ .play = ed.map.start };
                editor.launch(ed);
                try std.testing.expect(ed.action == .play);
            },
            .save_as => ed.askName(.save_as),
            .rename => ed.startRename(),
        }
        try std.testing.expect(ed.drag == null);
        try std.testing.expectEqual(moved, ed.map.node[0].pos);
        try std.testing.expectEqual(@as(usize, 1), ed.history.at);
        ed.modal = .none;
        ed.renaming = false;
        ed.undo();
        try std.testing.expectEqual(was, ed.map.node[0].pos);
    }
}

test "a rename is one undo, and deleting a node renumbers the list round it" {
    const ed = try testEditor();
    defer ed.destroy();
    for (0..3) |_| _ = ed.map.add(.{ .bespoke = .{} });
    ed.select(1);
    ed.startRename();
    ed.field.set("Crypt", atlas.NAME_MAX);
    ed.commitRename();
    try std.testing.expectEqualStrings("Crypt", ed.map.node[1].name());
    ed.select(0);
    ed.gesture();
    editor.deleteNode(ed);
    try std.testing.expectEqualStrings("Crypt", ed.map.node[0].name());
    ed.undo();
    ed.undo();
    try std.testing.expectEqual(@as(usize, 3), ed.map.node_n);
    try std.testing.expectEqual(@as(usize, 0), ed.map.node[1].label.n);
}

test "undo and redo disarm deletion when a node index changes owners" {
    const ed = try testEditor();
    defer ed.destroy();
    for ([_][]const u8{ "First", "Second", "Third" }) |name| {
        const n = ed.map.add(.{ .bespoke = .{} }).?;
        _ = ed.map.node[n].rename(name);
    }
    ed.gesture();
    editor.deleteNode(ed);
    ed.select(1);
    ed.delete_armed = ed.node;
    try std.testing.expectEqualStrings("Third", ed.here().name());
    ed.undo();
    try std.testing.expectEqualStrings("Second", ed.here().name());
    try std.testing.expect(ed.delete_armed == null);
    ed.delete_armed = ed.node;
    ed.redo();
    try std.testing.expectEqualStrings("Third", ed.here().name());
    try std.testing.expect(ed.delete_armed == null);
    ed.delete_armed = ed.node;
    interaction.escape(ed);
    try std.testing.expect(ed.delete_armed == null);
    try std.testing.expectEqual(editor.Action.none, ed.action);
    try std.testing.expectEqual(editor.Modal.none, ed.modal);
    std.debug.print("2 history swaps changed the selected node and cleared its deletion confirmation\n", .{});
}

test "a node added is named as it is added, one undo for both" {
    const ed = try testBespoke();
    defer ed.destroy();
    const before = ed.map.node_n;
    ed.gesture();
    editor.addNode(ed, .{ .procgen = .{} });
    try std.testing.expect(ed.renaming);
    var buf: [widgets.LINE]u8 = undefined;
    ed.field.set("Pit", atlas.NAME_MAX);
    try std.testing.expect(std.mem.endsWith(u8, ed.nodeTitle(ed.node, &buf), "Pit" ++ menu.CARET));
    ed.commitRename();
    try std.testing.expectEqualStrings("Pit", ed.map.node[before].name());
    ed.undo();
    try std.testing.expectEqual(before, ed.map.node_n);
}

test "an undo the same frame a rename starts drops the rename instead of naming another node" {
    const ed = try testBespoke();
    defer ed.destroy();
    const kept = ed.map.node[0].label;
    ed.gesture();
    editor.addNode(ed, .{ .procgen = .{} });
    ed.field.set("Pit", atlas.NAME_MAX);
    ed.commitRename();
    ed.startRename();
    ed.undo();
    try std.testing.expect(!ed.renaming);
    try std.testing.expectEqualStrings(kept.text(), ed.map.node[0].name());
}

fn tileAt(ed: *editor.Editor, p: P) grid.Tile {
    return ed.map.node[ed.node].plan.bespoke.tileAt(p);
}

fn rowCount(ed: *editor.Editor, y: i32, t: grid.Tile) usize {
    var n: usize = 0;
    var x: i32 = 0;
    while (x < grid.W) : (x += 1) n += @intFromBool(tileAt(ed, .{ .x = x, .y = y }) == t);
    return n;
}

fn count(ed: *editor.Editor, t: grid.Tile) usize {
    var n: usize = 0;
    for (ed.map.node[ed.node].plan.bespoke.tile) |x| n += @intFromBool(x == t);
    return n;
}

test "a line, a box and a fill lay the inks, each one undo, and the eyedropper picks a tile or what stands on it" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .line }, .{ .x = 12, .y = 7 });
    const line = count(ed, .floor);
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 20, .y = 20 }, .erase = false, .shape = .box }, .{ .x = 29, .y = 25 });
    const boxed = count(ed, .floor) - line;
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 24, .y = 22 }));
    ed.gesture();
    ed.ink = .init(.{ .first = .water, .second = .wall });
    placement.fill(ed, .{ .x = 24, .y = 22 }, false);
    const filled = count(ed, .water);
    ed.gesture();
    placement.fill(ed, .{ .x = 21, .y = 20 }, true);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 21, .y = 20 }));
    std.debug.print("a line 2,2 to 12,7: {d} cells; a 10x6 box: {d}; filled inside it: {d} cells of water\n", .{ line, boxed, filled });
    try std.testing.expectEqual(@as(usize, 11), line);
    try std.testing.expectEqual(@as(usize, 28), boxed);
    try std.testing.expectEqual(@as(usize, 32), filled);
    try std.testing.expectEqual(@as(usize, 4), ed.history.at);
    click(ed, .{ .foe = .pib }, .{ .x = 2, .y = 2 });
    ed.tool = .paint;
    placement.pickUp(ed, .{ .x = 22, .y = 22 }, true);
    try std.testing.expectEqual(grid.Tile.water, ed.ink.get(.second));
    placement.pickUp(ed, .{ .x = 2, .y = 2 }, false);
    try std.testing.expect(ed.tool.eql(.{ .foe = .pib }));
    for (0..3) |_| ed.undo();
    placement.pickUp(ed, .{ .x = 22, .y = 22 }, false);
    try std.testing.expect(tileAt(ed, .{ .x = 22, .y = 22 }) != .water);
    try std.testing.expectEqual(tileAt(ed, .{ .x = 22, .y = 22 }), ed.ink.get(.first));
}

test "the paste's ghost lays aside what the click lays, so a door refuses the barrel in both" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .rect }, .{ .x = 5, .y = 4 });
    click(ed, .barrel, .{ .x = 4, .y = 4 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 4 });
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .select }, .{ .x = 5, .y = 4 });
    placement.copySelection(ed, false);
    const at = P{ .x = 30, .y = 20 };
    const beside = at.add(.{ .x = 1, .y = 0 });
    click(ed, .door, at);
    placement.startPaste(ed);
    const ghost = placement.layAside(ed, at);
    ed.gesture();
    placement.layBoard(ed, at);
    const b = &ed.map.node[0].plan.bespoke;
    try std.testing.expectEqual(@as(usize, 1), ghost.left);
    try std.testing.expect(!ed.trial.barrel[grid.Level.idx(at)] and !b.barrel[grid.Level.idx(at)]);
    try std.testing.expect(ed.trial.foeAt(beside) != null and b.foeAt(beside) != null);
    try std.testing.expectEqualStrings("Pasted; 1 torch(es), barrel(s) or foe(s) did not fit there", ed.said.text());
}

test "paste previews reuse unchanged content and follow cells clipboard terrain doors nodes and undo" {
    const ed = try editor.Editor.create(std.testing.allocator);
    defer ed.destroy();
    _ = ed.map.oneRoom(grid.Box.inMap(0), grid.MIDDLE);
    const at = P{ .x = 30, .y = 20 };
    const beside = at.add(.{ .x = 1, .y = 0 });
    const outside = P{ .x = 50, .y = 40 };
    ed.board.size = .{ .x = 2, .y = 1 };
    ed.board.cells.tile = @splat(.floor);
    ed.board.cells.barrel[0] = true;
    try std.testing.expect(ed.board.cells.addFoe(.{ .kind = .rat, .at = .{ .x = 1, .y = 0 } }));
    const first = placement.layAside(ed, at);
    try std.testing.expect(first.changed and first.left == 0);
    for (0..256) |_| {
        try std.testing.expectEqualDeep(first, placement.layAside(ed, at));
        try std.testing.expect(ed.trial.barrel[grid.Level.idx(at)]);
        try std.testing.expectEqual(actor.Kind.rat, ed.trial.foe[ed.trial.foeAt(beside).?].kind);
    }
    try std.testing.expect(!ed.map.node[0].plan.bespoke.barrel[grid.Level.idx(at)]);
    try std.testing.expectEqual(@as(usize, 0), ed.map.node[0].plan.bespoke.foe_n);

    const moved = at.add(.{ .x = 3, .y = 0 });
    _ = placement.layAside(ed, moved);
    try std.testing.expect(!ed.trial.barrel[grid.Level.idx(at)]);
    try std.testing.expect(ed.trial.barrel[grid.Level.idx(moved)]);
    ed.board.cells.tile[0] = .dirt;
    try std.testing.expectEqual(@as(usize, 1), placement.layAside(ed, at).left);
    try std.testing.expect(!ed.trial.barrel[grid.Level.idx(at)]);
    ed.board.cells.tile[0] = .floor;
    ed.board.cells.foe[0].kind = .pib;
    try std.testing.expectEqual(@as(usize, 0), placement.layAside(ed, at).left);
    try std.testing.expectEqual(actor.Kind.pib, ed.trial.foe[ed.trial.foeAt(beside).?].kind);
    click(ed, .folk, at);
    ed.modal = .none;
    try std.testing.expectEqual(@as(usize, 1), placement.layAside(ed, at).left);
    ed.undo();
    try std.testing.expectEqual(@as(usize, 0), placement.layAside(ed, at).left);

    paintClick(ed, .rock, outside);
    _ = placement.layAside(ed, at);
    try std.testing.expectEqual(grid.Tile.rock, ed.trial.tile[grid.Level.idx(outside)]);
    ed.undo();
    _ = placement.layAside(ed, at);
    try std.testing.expectEqual(grid.Tile.floor, ed.trial.tile[grid.Level.idx(outside)]);
    ed.redo();
    _ = placement.layAside(ed, at);
    try std.testing.expectEqual(grid.Tile.rock, ed.trial.tile[grid.Level.idx(outside)]);
    click(ed, .door, at);
    try std.testing.expectEqual(@as(usize, 1), placement.layAside(ed, at).left);
    try std.testing.expect(!ed.trial.barrel[grid.Level.idx(at)]);

    const n = ed.map.add(.{ .bespoke = .{} }).?;
    ed.select(n);
    const predicted = placement.layAside(ed, at);
    try std.testing.expectEqual(@as(usize, 0), predicted.left);
    try std.testing.expectEqual(grid.Tile.wall, ed.trial.tile[grid.Level.idx(outside)]);
    const trial = ed.trial;
    ed.gesture();
    placement.layBoard(ed, at);
    const applied = &ed.map.node[n].plan.bespoke;
    try std.testing.expectEqualSlices(grid.Tile, &trial.tile, &applied.tile);
    try std.testing.expectEqualSlices(bool, &trial.barrel, &applied.barrel);
    try std.testing.expectEqualDeep(trial.torches(), applied.torches());
    try std.testing.expectEqualDeep(trial.foes(), applied.foes());
    std.debug.print("paste previews: 256 unchanged frames, moved cell, terrain and foe clipboard edits, terrain undo/redo, door, node and apply parity checked\n", .{});
}

test "a selection copied pastes with what stood on it, and cut leaves the second ink" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 8 });
    click(ed, .{ .foe = .rat }, .{ .x = 6, .y = 6 });
    click(ed, .barrel, .{ .x = 4, .y = 4 });
    click(ed, .torch, .{ .x = 5, .y = 3 });
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 3 }, .erase = false, .shape = .select }, .{ .x = 9, .y = 8 });
    placement.copySelection(ed, false);
    try std.testing.expectEqual(P{ .x = 6, .y = 6 }, ed.board.size);
    placement.startPaste(ed);
    try std.testing.expect(ed.pasting);
    ed.gesture();
    placement.layBoard(ed, .{ .x = 30, .y = 20 });
    const b = &ed.map.node[0].plan.bespoke;
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 32, .y = 23 }));
    try std.testing.expect(b.foeAt(.{ .x = 32, .y = 23 }) != null);
    try std.testing.expect(b.barrel[grid.Level.idx(.{ .x = 30, .y = 21 })]);
    try std.testing.expect(b.torch.has(.{ .x = 31, .y = 20 }));
    ed.gesture();
    placement.layBoard(ed, .{ .x = 30, .y = 20 });
    try std.testing.expectEqualStrings("Pasted", ed.said.text());
    const pasted = ed.history.at;
    placement.copySelection(ed, true);
    try std.testing.expectEqual(pasted + 1, ed.history.at);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 6 }));
    try std.testing.expectEqual(@as(?usize, null), b.foeAt(.{ .x = 6, .y = 6 }));
    std.debug.print("6x6 copied and pasted at 30,20 with its rat, barrel and torch; cut leaves {d} foe(s)\n", .{b.foe_n});
    try std.testing.expectEqual(@as(usize, 1), b.foe_n);
}

test "a door's dot dragged onto another's on the graph links them, and the other button on one unlinks it" {
    const ed = try testBespoke();
    defer ed.destroy();
    _ = ed.map.add(.{ .bespoke = .{} });
    _ = ed.map.addDoor(0, .{ .x = 10, .y = 10 });
    _ = ed.map.addDoor(1, .{ .x = 20, .y = 20 });
    const c = TEST_CANVAS;
    ed.view = .graph;
    const a = ed.dotAt(c, .{ .node = 0, .door = 0 });
    const b = ed.dotAt(c, .{ .node = 1, .door = 0 });
    ed.gesture();
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = .{ .x = @intFromFloat(a.x), .y = @intFromFloat(a.y) } };
    interaction.graphMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = .{ .x = @intFromFloat(b.x), .y = @intFromFloat(b.y) } };
    interaction.graphMouse(ed, c, true);
    ed.desk = .{ .mouse = .{ .x = @intFromFloat(b.x), .y = @intFromFloat(b.y) } };
    interaction.graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(?atlas.Link, .{ .node = 1, .door = 0 }), ed.map.node[0].door[0].to);
    try std.testing.expectEqual(@as(usize, 1), ed.history.at);
    ed.gesture();
    ed.desk = .{ .erase = true, .erase_hit = true, .mouse = .{ .x = @intFromFloat(a.x), .y = @intFromFloat(a.y) } };
    interaction.graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(?atlas.Link, null), ed.map.node[1].door[0].to);
    try std.testing.expectEqual(@as(usize, 2), ed.history.at);
}

test "Open lists the edited map's folder and Esc goes up a folder before it closes; a new name goes beside the map" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.setPath(".\\" ++ comptime atlas.mapPath("qud\\qud_strata"));
    try std.testing.expectEqualStrings(atlas.mapPath("qud/qud_strata"), ed.path());
    ed.askOpen();
    try std.testing.expectEqualStrings("qud/", ed.listing.here());
    try std.testing.expectEqualStrings(ed.path(), ed.listing.at(ed.listed_at));
    ed.desk = .{ .back = true };
    interaction.modalKeys(ed);
    try std.testing.expectEqual(editor.Modal{ .prompt = .open }, ed.modal);
    try std.testing.expectEqual(@as(usize, 0), ed.listing.here().len);
    interaction.modalKeys(ed);
    try std.testing.expectEqual(editor.Modal.none, ed.modal);
    ed.field.put("Bog");
    var buf: [listing.PATH_MAX]u8 = undefined;
    try std.testing.expectEqualStrings(atlas.mapPath("qud/bog"), ed.namedPath(&buf).?);
}

test "mouse editor cell actions choose play starts and linked doors without painting" {
    const ed = try testBespoke();
    defer ed.destroy();
    _ = ed.map.add(.{ .bespoke = .{} });
    const from = P{ .x = 10, .y = 10 };
    const to = P{ .x = 20, .y = 20 };
    _ = ed.map.addDoor(0, from);
    _ = ed.map.addDoor(1, to);
    ed.map.link(.{ .node = 0, .door = 0 }, .{ .node = 1, .door = 0 });
    const before = ed.map.node[0].plan.bespoke.tile;
    const start = P{ .x = 12, .y = 13 };
    ed.pasting = true;
    interaction.armCellAction(ed, .play);
    try std.testing.expect(!ed.pasting and ed.cell_action == .play);
    ed.desk = .{ .mouse = raster.middleAt(ed.cellRect(TEST_CANVAS, from)) };
    interaction.mapMouse(ed, TEST_CANVAS, true);
    try std.testing.expect(ed.action == .none and ed.cell_action == .play);
    ed.desk = .{ .paint_hit = true, .paint = true, .mouse = raster.middleAt(ed.cellRect(TEST_CANVAS, start)) };
    interaction.mapMouse(ed, TEST_CANVAS, true);
    try std.testing.expectEqual(@as(usize, 0), ed.action.play.node);
    try std.testing.expectEqual(start, ed.action.play.at);
    try std.testing.expect(ed.cell_action == null);
    ed.desk.paint_hit = false;
    interaction.mapMouse(ed, TEST_CANVAS, true);
    try std.testing.expectEqualSlices(grid.Tile, &before, &ed.map.node[0].plan.bespoke.tile);
    ed.action = .none;
    interaction.armCellAction(ed, .go);
    ed.desk = .{ .paint_hit = true, .mouse = raster.middleAt(ed.cellRect(TEST_CANVAS, from)) };
    interaction.mapMouse(ed, TEST_CANVAS, true);
    try std.testing.expectEqual(@as(usize, 1), ed.node);
    try std.testing.expect(ed.cell_action == null);
    try std.testing.expectEqual(@as(usize, 0), ed.history.at);
    interaction.armCellAction(ed, .play);
    ed.desk = .{ .erase_hit = true };
    interaction.mapMouse(ed, TEST_CANVAS, true);
    try std.testing.expect(ed.cell_action == null and ed.action == .none);
    interaction.armCellAction(ed, .play);
    interaction.escape(ed);
    try std.testing.expect(ed.cell_action == null and ed.action == .none);
    interaction.armCellAction(ed, .go);
    ed.desk = .{ .paint_hit = true };
    interaction.mapMouse(ed, TEST_CANVAS, false);
    try std.testing.expect(ed.cell_action == null and ed.action == .none);
    try std.testing.expectEqualSlices(grid.Tile, &before, &ed.map.node[0].plan.bespoke.tile);
    std.debug.print("mouse editor: chosen play cell, linked-door travel, intermediate motion, held click and three cancellations preserve map and undo\n", .{});
}

test "a full procgen preview keeps the hero's place in the pool, as play does" {
    const ed = try testEditor();
    defer ed.destroy();
    var foes = pack.Spec{ .packs = pack.PACKS_MAX, .few = 0, .gap = 0, .makeup_n = 1 };
    foes.makeup[0] = pack.Makeup.of(&(.{.rat} ** pack.MAKEUP_MAX));
    const n = ed.map.add(.{ .procgen = .{ .floor = .{ .wilds = .{} }, .foes = foes } }).?;
    ed.select(n);
    ed.preview();
    try std.testing.expectEqual(actor.MAX - actor.most(actor.HERO), ed.scene.shown_n);
    try std.testing.expect(ed.scene.lv.vacant(ed.arrival()) or ed.scene.lv.at(ed.arrival()).solid());
}

test "a procgen node shows a roll of it with its packs, and a bespoke one counts the ground no walk reaches" {
    const ed = try testEditor();
    defer ed.destroy();
    const n = ed.map.add(.{ .procgen = .{ .floor = .{ .wilds = .{} } } }).?;
    ed.select(n);
    ed.preview();
    const open = ed.scene.lv.openCount();
    const foes = ed.scene.shown_n;
    const first = ed.scene.lv.tile;
    editor.reroll(ed);
    ed.preview();
    try std.testing.expect(!std.mem.eql(grid.Tile, &first, &ed.scene.lv.tile));
    const b = ed.map.add(.{ .bespoke = .{} }).?;
    ed.select(b);
    ed.tool = .paint;
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 6, .y = 6 });
    placement.laySpan(ed, .{ .from = .{ .x = 20, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 22, .y = 4 });
    ed.map.start = .{ .node = b, .at = .{ .x = 3, .y = 3 } };
    click(ed, .{ .foe = .rat }, .{ .x = 21, .y = 3 });
    var pond = grid.Cells.of(.{ .x = 7, .y = 2 }, .{ .x = 10, .y = 7 });
    while (pond.next()) |p| paintClick(ed, .water, p);
    click(ed, .{ .foe = .bog_leech }, .{ .x = 9, .y = 4 });
    try std.testing.expect(ed.here().plan.bespoke.foeAt(.{ .x = 9, .y = 4 }) != null);
    ed.preview();
    std.debug.print("a wilds roll: {d} open cells, {d} foes placed; two rooms apart: {d} cells and {d} foe cut off\n", .{ open, foes, ed.scene.issues.cut_off, ed.scene.issues.foes_cut_off });
    try std.testing.expect(open > 0 and foes > 0);
    try std.testing.expectEqual(@as(usize, 9), ed.scene.issues.cut_off);
    try std.testing.expectEqual(@as(usize, 1), ed.scene.issues.foes_cut_off);
    try std.testing.expect(!ed.scene.issues.start_walled);
}

test "the eyedropper refused on a procgen node leaves both inks as they were" {
    const ed = try testEditor();
    defer ed.destroy();
    const n = ed.map.add(.{ .procgen = .{ .floor = .{ .wilds = .{} } } }).?;
    ed.select(n);
    ed.preview();
    const inks = ed.ink;
    var cells = grid.Cells.of(.{ .x = 0, .y = 0 }, grid.SIZE);
    const p = while (cells.next()) |q| {
        if (ed.scene.lv.at(q) != inks.get(.first) and ed.here().doorAt(q) == null) break q;
    } else unreachable;
    placement.pickUp(ed, p, false);
    try std.testing.expectEqualStrings(editor.GENERATED, ed.said.text());
    try std.testing.expectEqual(inks.get(.first), ed.ink.get(.first));
    try std.testing.expectEqual(inks.get(.second), ed.ink.get(.second));
}

test "a pasted barrel hanging off the map counts as not fitting, as a torch does" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .rect }, .{ .x = 5, .y = 4 });
    click(ed, .barrel, .{ .x = 4, .y = 4 });
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .select }, .{ .x = 5, .y = 4 });
    placement.copySelection(ed, false);
    placement.startPaste(ed);
    const at = P{ .x = -1, .y = 10 };
    try std.testing.expectEqual(@as(usize, 1), placement.layAside(ed, at).left);
    ed.gesture();
    placement.layBoard(ed, at);
    try std.testing.expectEqualStrings("Pasted; 1 torch(es), barrel(s) or foe(s) did not fit there", ed.said.text());
}

test "undo mid graph drag takes the drag back as its own step, and the map after it is unsaved" {
    const ed = try testBespoke();
    defer ed.destroy();
    const was = dragFirstBox(ed);
    ed.undo();
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expect(ed.drag == null);
    ed.redo();
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    try std.testing.expect(ed.history.dirty);
}

test "a graph drag put back keeps what there was to redo" {
    const ed = try testBespoke();
    defer ed.destroy();
    _ = ed.map.add(.{ .bespoke = .{} });
    ed.select(1);
    for (0..editor.UNDO_CAP) |_| {
        ed.gesture();
        ed.map.node[1].pos.x += 1;
        ed.bank();
    }
    ed.undo();
    ed.undo();
    const hist = .{ ed.history.base, ed.history.len, ed.history.at };
    const was = dragFirstBox(ed);
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    ed.drop();
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expectEqual(hist, .{ ed.history.base, ed.history.len, ed.history.at });
    ed.redo();
    ed.redo();
    try std.testing.expectEqual(ed.history.len, ed.history.at);
}

test "redo mid graph drag puts the box back and redoes" {
    const ed = try testBespoke();
    defer ed.destroy();
    _ = ed.map.add(.{ .bespoke = .{} });
    ed.gesture();
    ed.map.node[1].pos.x += 40;
    ed.bank();
    const moved = ed.map.node[1].pos;
    ed.undo();
    const was = dragFirstBox(ed);
    ed.redo();
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expect(ed.map.node[1].pos.eq(moved));
    try std.testing.expectEqual(ed.history.len, ed.history.at);
}

test "Esc mid stroke ends it, and a paste hanging off the map lays what lands on it" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    ed.cam = .{ 0, 0 };
    ed.tool = .paint;
    ed.selection = grid.Box.sized(.{ .x = 0, .y = 0 }, 2, 2);
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 2 }) };
    ed.gesture();
    interaction.mapMouse(ed, c, true);
    interaction.escape(ed);
    try std.testing.expect(ed.selection != null);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 6, .y = 2 }) };
    interaction.mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 2 }));
    ed.desk = .{};
    interaction.mapMouse(ed, c, true);
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 10, .y = 10 }, .erase = false, .shape = .rect }, .{ .x = 12, .y = 12 });
    ed.gesture();
    placement.laySpan(ed, .{ .from = .{ .x = 10, .y = 10 }, .erase = false, .shape = .select }, .{ .x = 12, .y = 12 });
    placement.copySelection(ed, false);
    placement.startPaste(ed);
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = -1, .y = -1 }) };
    ed.gesture();
    interaction.mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 0, .y = 0 }));
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 1, .y = 1 }));
}

test "a graph drag let go of where it began leaves no undo and nothing unsaved" {
    const ed = try testBespoke();
    defer ed.destroy();
    const c = TEST_CANVAS;
    const was = dragFirstBox(ed);
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    const back = P{ .x = was.x + @as(i32, @intFromFloat(c.x - ed.gcam[0])), .y = was.y + @as(i32, @intFromFloat(c.y - ed.gcam[1])) };
    ed.desk = .{ .paint = true, .mouse = back };
    interaction.graphMouse(ed, c, true);
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    ed.desk = .{ .mouse = back };
    interaction.graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 0), ed.history.at);
    try std.testing.expect(!ed.history.dirty);
}

test "deleting a node leaves the next unarmed and nothing selected, and the cursor refuses a foe with no room" {
    const ed = try testEditor();
    defer ed.destroy();
    for (0..3) |_| _ = ed.map.add(.{ .bespoke = .{} });
    ed.select(1);
    ed.delete_armed = 1;
    ed.selection = grid.Box.sized(.{ .x = 1, .y = 1 }, 2, 2);
    ed.gesture();
    editor.deleteNode(ed);
    try std.testing.expectEqual(@as(?usize, null), ed.delete_armed);
    try std.testing.expect(ed.selection == null);
    ed.tool = .paint;
    ed.gesture();
    const room = grid.Box.sized(.{ .x = 2, .y = 2 }, 40, 3);
    placement.laySpan(ed, .{ .from = room.lo, .erase = false, .shape = .rect }, room.hi.sub(.{ .x = 1, .y = 1 }));
    var cells = room.cells();
    while (cells.next()) |p| {
        if (!actor.roomFor(ed.map.node[ed.node].plan.bespoke.bodies(), .rat)) break;
        click(ed, .{ .foe = .rat }, p);
    }
    ed.tool = .{ .foe = .slime };
    try std.testing.expect(!placement.legal(ed, .{ .x = 2, .y = 2 }));
    ed.tool = .{ .foe = .pib };
    try std.testing.expect(placement.legal(ed, .{ .x = 2, .y = 2 }));
}

test "a knob's step is dim where its owner's fit would take it back" {
    var spec = pack.Spec{ .reach = pack.REACH_MAX };
    const reach = comptime knobs.rowNamed(&knobs.FOE_ROWS, "reach").?;
    try std.testing.expect(!knobs.moves(&spec, reach, 0, 1));
    try std.testing.expect(knobs.moves(&spec, reach, 0, -1));
    spec.reach = pack.REACH_MIN;
    try std.testing.expect(!knobs.moves(&spec, reach, 0, -1));
    const open = @import("../map/biome/open.zig");
    var floor = open.Params{};
    floor.decor = carve.fitDress(open.Params{ .decor = .{ .tall_grass = std.math.maxInt(@FieldType(carve.Decor, "tall_grass")) } }).decor;
    const decor = comptime knobs.rowNamed(knobs.rowsOf(.open), "decor").?;
    const grass = comptime std.meta.fieldIndex(carve.Decor, "tall_grass").?;
    try std.testing.expect(!knobs.moves(&floor, decor, grass, 1));
    try std.testing.expect(knobs.moves(&floor, decor, grass, -1));
}

test "editor history preserves exact contents through rollover undo and redo after the saved state expires" {
    const ed = try testBespoke();
    defer ed.destroy();
    const total = editor.UNDO_CAP * 2 + 5;
    for (0..total) |i| {
        click(ed, .paint, .{ .x = @intCast(i + 1), .y = 1 });
        if (i == 0) {
            ed.history.markSaved();
        }
    }
    try std.testing.expectEqual(editor.UNDO_CAP, ed.history.len);
    try std.testing.expect(ed.history.saved_at == null);
    for (0..editor.UNDO_CAP + 1) |i| {
        const painted = total - i;
        try std.testing.expectEqual(painted, count(ed, .floor));
        for (0..total) |cell| try std.testing.expectEqual(if (cell < painted) grid.Tile.floor else grid.Tile.wall, tileAt(ed, .{ .x = @intCast(cell + 1), .y = 1 }));
        try std.testing.expect(ed.history.dirty);
        ed.undo();
    }
    try std.testing.expectEqual(@as(usize, 0), ed.history.at);
    for (0..editor.UNDO_CAP + 1) |i| {
        try std.testing.expectEqual(total - editor.UNDO_CAP + i, count(ed, .floor));
        try std.testing.expect(ed.history.dirty);
        ed.redo();
    }
    try std.testing.expectEqual(editor.UNDO_CAP, ed.history.at);
    try std.testing.expectEqual(total, count(ed, .floor));
    std.debug.print("editor history: {d} gestures, all {d} retained states checked cell-by-cell, full redo and both no-op boundaries; evicted save stays dirty\n", .{ total, editor.UNDO_CAP + 1 });
}

test "branching before a saved redo state cannot become clean by reusing its history index" {
    const ed = try testBespoke();
    defer ed.destroy();
    for (0..3) |i| click(ed, .paint, .{ .x = @intCast(i + 1), .y = 1 });
    ed.history.markSaved();
    ed.undo();
    ed.undo();
    try std.testing.expectEqual(@as(usize, 1), ed.history.at);
    click(ed, .paint, .{ .x = 10, .y = 1 });
    try std.testing.expect(ed.history.saved_at == null);
    click(ed, .paint, .{ .x = 11, .y = 1 });
    try std.testing.expectEqual(@as(usize, 3), ed.history.at);
    try std.testing.expect(ed.history.dirty);
    ed.redo();
    try std.testing.expectEqual(@as(usize, 3), count(ed, .floor));
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 2, .y = 1 }));
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 3, .y = 1 }));
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 10, .y = 1 }));
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 11, .y = 1 }));
    for (0..3) |_| {
        ed.undo();
        try std.testing.expect(ed.history.dirty);
    }
    for (0..3) |_| {
        ed.redo();
        try std.testing.expect(ed.history.dirty);
    }
    std.debug.print("editor branching: saved future discarded, equal history index stays dirty through all 3 undo/redo steps\n", .{});
}

fn typeInto(ed: *editor.Editor, s: []const u8) void {
    var d = @import("../core/input.zig").Desk{};
    for (s) |c| {
        d.typed.buf[d.typed.n] = c;
        d.typed.n += 1;
    }
    ed.desk = d;
    editor.plot.keys(ed);
}

test "folk: placing one opens its words, typing is one undo step, and nothing else may share its cell" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    placement.laySpan(ed, .{ .from = .{ .x = 4, .y = 5 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 8 });
    const at = P{ .x = 6, .y = 6 };
    click(ed, .folk, at);
    try std.testing.expectEqual(editor.Modal{ .plot = .dialogs }, ed.modal);
    try std.testing.expectEqual(editor.plot.Pick{ .folk = 0 }, ed.plot.pick);
    ed.modal = .none;
    click(ed, .{ .foe = .rat }, at);
    click(ed, .barrel, at);
    try std.testing.expect(ed.map.node[0].plan.bespoke.foeAt(at) == null);
    try std.testing.expect(!ed.map.node[0].plan.bespoke.barrel[grid.Level.idx(at)]);
    ed.modal = .{ .plot = .dialogs };
    ed.plot.focus = .{ .folk = 0 };
    ed.plot.field.set("");
    ed.gesture();
    const before = ed.history.at;
    typeInto(ed, "Old ");
    typeInto(ed, "Wenna");
    try std.testing.expectEqualStrings("Old Wenna", ed.map.script.folk[0].name.text());
    try std.testing.expectEqual(before + 1, ed.history.at);
    ed.desk = .{ .paste = true, .paste_text = "x" ** atlas.script.WHO_MAX };
    editor.plot.keys(ed);
    try std.testing.expectEqualStrings("Old Wenna", ed.map.script.folk[0].name.text());
    ed.desk = .{ .undo = true };
    editor.plot.keys(ed);
    try std.testing.expectEqualStrings("", ed.map.script.folk[0].name.text());
    try std.testing.expect(ed.plot.focus == null);
    ed.desk = .{ .redo = true, .paint_hit = true };
    editor.plot.keys(ed);
    try std.testing.expectEqualStrings("Old Wenna", ed.map.script.folk[0].name.text());
    ed.map.script.folk[0].name = atlas.script.Who.of("Wenna");
    ed.bank();
    ed.undo();
    try std.testing.expectEqualStrings("Old Wenna", ed.map.script.folk[0].name.text());
    ed.undo();
    try std.testing.expectEqualStrings("", ed.map.script.folk[0].name.text());
    ed.modal = .none;
    paintClick(ed, .wall, at);
    try std.testing.expectEqual(@as(u8, 0), ed.map.script.folk_n);
    std.debug.print("editor folk: placement opens its words, foe and barrel refused on it, typing undone in one step, a wall takes it away\n", .{});
}
