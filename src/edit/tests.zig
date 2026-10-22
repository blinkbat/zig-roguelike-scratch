const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const carve = @import("../map/carve.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");
const pack = @import("../play/pack.zig");
const look = @import("../gfx/look.zig");
const menu = @import("../ui/menu.zig");
const knobs = @import("knobs.zig");
const modals = @import("modals.zig");
const editor = @import("editor.zig");
const P = mathx.P;

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
        editor.modalKeys(ed);
        if (modals.seenFoe(seen)) |kind| {
            try std.testing.expectEqual(kind, ed.action.fight);
            fights += 1;
        } else try std.testing.expect(ed.action == .none);
    }
    try std.testing.expect(!ed.dirty);
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
    ed.drag = .{ .node = 0, .grab = .{ .x = 0, .y = 0 }, .from = .{ .x = 100, .y = 100 }, .was = was };
    ed.desk = .{ .paint = true, .mouse = .{ .x = 200, .y = 100 } };
    editor.graphMouse(ed, TEST_CANVAS, true);
    return was;
}

fn mouseOn(ed: *const editor.Editor, c: rl.Rectangle, p: P) P {
    const r = ed.cellRect(c, p);
    return .{ .x = @as(i32, @intFromFloat(r.x)) + 1, .y = @as(i32, @intFromFloat(r.y)) + 1 };
}

fn click(ed: *editor.Editor, t: editor.Tool, p: P) void {
    ed.gesture();
    ed.tool = t;
    editor.place(ed, p);
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
    editor.laySpan(ed, .{ .from = .{ .x = 4, .y = 5 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 5 });
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
        const before = ed.hist_at;
        const want = editor.removable(ed, p);
        editor.remove(ed, p);
        try std.testing.expectEqual(want, ed.hist_at != before);
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
    editor.laySpan(ed, .{ .from = .{ .x = 4, .y = 5 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 5 });
    click(ed, .door, .{ .x = 10, .y = 5 });
    paintClick(ed, .wall, .{ .x = 10, .y = 5 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 5 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 9 });
    click(ed, .torch, .{ .x = 6, .y = 4 });
    click(ed, .torch, .{ .x = 6, .y = 3 });
    ed.gesture();
    ed.tool = .paint;
    editor.remove(ed, .{ .x = 4, .y = 5 });
    ed.preview();
    try std.testing.expectEqual(grid.Tile.wall, ed.lv.at(.{ .x = 4, .y = 5 }));
    try std.testing.expect(ed.lv.walkable(.{ .x = 10, .y = 5 }));
    try std.testing.expectEqual(@as(?usize, 0), ed.lv.doorAt(.{ .x = 10, .y = 5 }));
    try std.testing.expectEqual(@as(usize, 1), w.node[0].plan.bespoke.foe_n);
    try std.testing.expectEqual(@as(usize, 1), ed.lv.torch.n);
    try std.testing.expect(ed.dirty);
    const map = look.Assets.of(&ed.lv);
    try std.testing.expect(std.meta.eql(map.merge(ed.assets), ed.assets));
    try std.testing.expect(ed.assets.bodies.contains(.rat) and ed.assets.bodies.contains(.slime_quarter) and ed.assets.barrel);
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
    try std.testing.expectEqual(@as(?usize, 0), ed.lv.doorAt(.{ .x = 40, .y = 30 }));
}

test "a gesture is one undo however much it paints, and redo puts it back" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.gesture();
    ed.tool = .paint;
    editor.laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 11, .y = 6 });
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 2, .y = 8 }, .erase = false, .shape = .rect }, .{ .x = 3, .y = 8 });
    ed.gesture();
    try std.testing.expectEqual(@as(usize, 52), count(ed, .floor));
    try std.testing.expectEqual(@as(usize, 2), ed.hist_at);
    ed.undo();
    try std.testing.expectEqual(@as(usize, 50), count(ed, .floor));
    ed.undo();
    try std.testing.expectEqual(@as(usize, 0), count(ed, .floor));
    ed.redo();
    ed.redo();
    try std.testing.expectEqual(@as(usize, 52), count(ed, .floor));
    ed.undo();
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 20, .y = 20 }, .erase = false, .shape = .rect }, .{ .x = 20, .y = 20 });
    try std.testing.expectEqual(ed.hist_at, ed.hist_len);
    try std.testing.expectEqual(@as(usize, 51), count(ed, .floor));
    std.debug.print("two strokes over 52 cells, then one after an undo: {d} undo steps\n", .{ed.hist_at});
}

test "undo keeps no more than its cap, dropping the oldest" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    for (0..editor.UNDO_CAP + 5) |i| {
        ed.gesture();
        editor.place(ed, .{ .x = @intCast(1 + i), .y = 1 });
    }
    try std.testing.expectEqual(editor.UNDO_CAP, ed.hist_len);
    for (0..editor.UNDO_CAP) |_| ed.undo();
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 5, .y = 1 }));
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 1 }));
}

test "undoing back to what was saved leaves nothing unsaved, and a press held through New lets go" {
    const ed = try testBespoke();
    defer ed.destroy();
    click(ed, .paint, .{ .x = 3, .y = 3 });
    ed.saved_at = ed.hist_at;
    ed.dirty = false;
    click(ed, .paint, .{ .x = 4, .y = 3 });
    ed.undo();
    try std.testing.expect(!ed.dirty);
    ed.undo();
    try std.testing.expect(ed.dirty);
    ed.redo();
    try std.testing.expect(!ed.dirty);
    ed.drag = .{ .node = 0, .grab = .{ .x = 0, .y = 0 }, .from = .{ .x = 0, .y = 0 }, .was = .{ .x = 0, .y = 0 } };
    ed.span = .{ .from = .{ .x = 1, .y = 1 }, .erase = false, .shape = .rect };
    ed.dirty = false;
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
    editor.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 12, .y = 2 }) };
    editor.mapMouse(ed, c, true);
    const row_n = rowCount(ed, 2, .floor);
    editor.mapMouse(ed, c, false);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    editor.mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 4, .y = 4 }));
    ed.desk = .{};
    editor.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .paint_hit = true, .shift = true, .mouse = mouseOn(ed, c, .{ .x = 2, .y = 6 }) };
    ed.gesture();
    editor.mapMouse(ed, c, true);
    try std.testing.expect(ed.span != null);
    editor.escape(ed);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 8, .y = 6 }) };
    editor.mapMouse(ed, c, true);
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
    editor.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = -3, .y = 10 }) };
    editor.mapMouse(ed, c, true);
    const row_n = rowCount(ed, 10, .floor);
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 20, .y = 20 }) };
    editor.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 10 }) };
    editor.mapMouse(ed, c, true);
    std.debug.print("a stroke from x 5 to x -3 in one frame: {d} cells painted to the edge\n", .{row_n});
    try std.testing.expectEqual(@as(usize, 6), row_n);
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 4, .y = 10 }));
    click(ed, .torch, .{ .x = 3, .y = 9 });
    try std.testing.expectEqual(@as(usize, 1), b.torch.n);
    paintClick(ed, .wall, .{ .x = 3, .y = 10 });
    try std.testing.expectEqual(@as(usize, 0), b.torch.n);
    ed.tool = .paint;
    ed.desk = .{ .shift = true, .paint = true, .erase = true, .paint_hit = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 8, .y = 8 }) };
    editor.mapMouse(ed, c, true);
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
    editor.mapMouse(ed, c, true);
    ed.desk = .{ .paint = true, .erase = true, .erase_hit = true, .mouse = .{ .x = -5, .y = -5 } };
    ed.gesture();
    editor.mapMouse(ed, c, false);
    ed.desk = .{ .paint = true, .erase = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 2 }) };
    editor.mapMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 1), ed.hist_at);
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
    editor.mapMouse(ed, c, true);
    ed.desk = .{ .shift = true, .paint = true, .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    editor.mapMouse(ed, c, true);
    ed.desk = .{ .mouse = mouseOn(ed, c, .{ .x = 4, .y = 4 }) };
    editor.mapMouse(ed, c, true);
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
    editor.mapMouse(ed, c, true);
    ed.desk = .{ .erase = true, .erase_hit = true, .mouse = mouseOn(ed, c, .{ .x = 6, .y = 4 }) };
    ed.gesture();
    editor.mapMouse(ed, c, true);
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
    editor.remove(ed, door);
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
    editor.graphMouse(ed, c, true);
    ed.desk = .{ .mouse = .{ .x = 400, .y = 100 } };
    editor.graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 0), ed.hist_at);
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expect(!ed.dirty);
}

test "leaving with unsaved changes asks first, and leaving a saved map does not" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.request(.leave);
    try std.testing.expect(ed.action == .leave);
    ed.action = .none;
    click(ed, .paint, .{ .x = 3, .y = 3 });
    ed.request(.leave);
    try std.testing.expectEqual(editor.Modal.confirm, ed.modal);
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
        try std.testing.expectEqual(editor.Modal.confirm, ed.modal);
        try std.testing.expect(ed.action == .none);
        try std.testing.expect(ed.drag == null);
        try std.testing.expectEqual(moved, ed.map.node[0].pos);
        try std.testing.expect(ed.dirty);
        ed.modal = .none;
        ed.undo();
        try std.testing.expectEqual(was, ed.map.node[0].pos);
        try std.testing.expect(!ed.dirty);
    }
    std.debug.print("2 departure paths preserve an active graph move, prompt, and undo to the saved state\n", .{});
}

test "Save As or a play-test mid graph drag keeps the move as its own undo" {
    for ([_]bool{ false, true }) |play| {
        const ed = try testBespoke();
        defer ed.destroy();
        ed.map.node[ed.map.start.node].plan.bespoke.tile[grid.Level.idx(ed.map.start.at)] = .floor;
        const was = dragFirstBox(ed);
        const moved = ed.map.node[0].pos;
        if (play) {
            ed.action = .{ .play = ed.map.start };
            editor.launch(ed);
            try std.testing.expect(ed.action == .play);
        } else ed.askName(.save_as);
        try std.testing.expect(ed.drag == null);
        try std.testing.expectEqual(moved, ed.map.node[0].pos);
        try std.testing.expectEqual(@as(usize, 1), ed.hist_at);
        ed.modal = .none;
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
    editor.escape(ed);
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
    var buf: [editor.LINE]u8 = undefined;
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
    editor.laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .line }, .{ .x = 12, .y = 7 });
    const line = count(ed, .floor);
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 20, .y = 20 }, .erase = false, .shape = .box }, .{ .x = 29, .y = 25 });
    const boxed = count(ed, .floor) - line;
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 24, .y = 22 }));
    ed.gesture();
    ed.ink = .init(.{ .first = .water, .second = .wall });
    editor.fill(ed, .{ .x = 24, .y = 22 }, false);
    const filled = count(ed, .water);
    ed.gesture();
    editor.fill(ed, .{ .x = 21, .y = 20 }, true);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 21, .y = 20 }));
    std.debug.print("a line 2,2 to 12,7: {d} cells; a 10x6 box: {d}; filled inside it: {d} cells of water\n", .{ line, boxed, filled });
    try std.testing.expectEqual(@as(usize, 11), line);
    try std.testing.expectEqual(@as(usize, 28), boxed);
    try std.testing.expectEqual(@as(usize, 32), filled);
    try std.testing.expectEqual(@as(usize, 4), ed.hist_at);
    click(ed, .{ .foe = .pib }, .{ .x = 2, .y = 2 });
    ed.tool = .paint;
    editor.pickUp(ed, .{ .x = 22, .y = 22 }, true);
    try std.testing.expectEqual(grid.Tile.water, ed.ink.get(.second));
    editor.pickUp(ed, .{ .x = 2, .y = 2 }, false);
    try std.testing.expect(ed.tool.eql(.{ .foe = .pib }));
    for (0..3) |_| ed.undo();
    editor.pickUp(ed, .{ .x = 22, .y = 22 }, false);
    try std.testing.expect(tileAt(ed, .{ .x = 22, .y = 22 }) != .water);
    try std.testing.expectEqual(tileAt(ed, .{ .x = 22, .y = 22 }), ed.ink.get(.first));
}

test "the paste's ghost lays aside what the click lays, so a door refuses the barrel in both" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .rect }, .{ .x = 5, .y = 4 });
    click(ed, .barrel, .{ .x = 4, .y = 4 });
    click(ed, .{ .foe = .rat }, .{ .x = 5, .y = 4 });
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .select }, .{ .x = 5, .y = 4 });
    editor.copySelection(ed, false);
    const at = P{ .x = 30, .y = 20 };
    const beside = at.add(.{ .x = 1, .y = 0 });
    click(ed, .door, at);
    editor.startPaste(ed);
    const ghost = editor.layAside(ed, at);
    ed.gesture();
    editor.layBoard(ed, at);
    const b = &ed.map.node[0].plan.bespoke;
    try std.testing.expectEqual(@as(usize, 1), ghost.left);
    try std.testing.expect(!ed.trial.barrel[grid.Level.idx(at)] and !b.barrel[grid.Level.idx(at)]);
    try std.testing.expect(ed.trial.foeAt(beside) != null and b.foeAt(beside) != null);
    try std.testing.expectEqualStrings("Pasted; 1 torch(es), barrel(s) or foe(s) did not fit there", ed.said.text());
}

test "a selection copied pastes with what stood on it, and cut leaves the second ink" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .rect }, .{ .x = 9, .y = 8 });
    click(ed, .{ .foe = .rat }, .{ .x = 6, .y = 6 });
    click(ed, .barrel, .{ .x = 4, .y = 4 });
    click(ed, .torch, .{ .x = 5, .y = 3 });
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 4, .y = 3 }, .erase = false, .shape = .select }, .{ .x = 9, .y = 8 });
    editor.copySelection(ed, false);
    try std.testing.expectEqual(P{ .x = 6, .y = 6 }, ed.board.size);
    editor.startPaste(ed);
    try std.testing.expect(ed.pasting);
    ed.gesture();
    editor.layBoard(ed, .{ .x = 30, .y = 20 });
    const b = &ed.map.node[0].plan.bespoke;
    try std.testing.expectEqual(grid.Tile.floor, tileAt(ed, .{ .x = 32, .y = 23 }));
    try std.testing.expect(b.foeAt(.{ .x = 32, .y = 23 }) != null);
    try std.testing.expect(b.barrel[grid.Level.idx(.{ .x = 30, .y = 21 })]);
    try std.testing.expect(b.torch.has(.{ .x = 31, .y = 20 }));
    ed.gesture();
    editor.layBoard(ed, .{ .x = 30, .y = 20 });
    try std.testing.expectEqualStrings("Pasted", ed.said.text());
    const pasted = ed.hist_at;
    editor.copySelection(ed, true);
    try std.testing.expectEqual(pasted + 1, ed.hist_at);
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
    editor.graphMouse(ed, c, true);
    ed.desk = .{ .paint = true, .mouse = .{ .x = @intFromFloat(b.x), .y = @intFromFloat(b.y) } };
    editor.graphMouse(ed, c, true);
    ed.desk = .{ .mouse = .{ .x = @intFromFloat(b.x), .y = @intFromFloat(b.y) } };
    editor.graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(?atlas.Link, .{ .node = 1, .door = 0 }), ed.map.node[0].door[0].to);
    try std.testing.expectEqual(@as(usize, 1), ed.hist_at);
    ed.gesture();
    ed.desk = .{ .erase = true, .erase_hit = true, .mouse = .{ .x = @intFromFloat(a.x), .y = @intFromFloat(a.y) } };
    editor.graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(?atlas.Link, null), ed.map.node[1].door[0].to);
    try std.testing.expectEqual(@as(usize, 2), ed.hist_at);
}

test "Open lists the edited map's folder and Esc goes up a folder before it closes; a new name goes beside the map" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.setPath(".\\" ++ comptime atlas.mapPath("qud\\qud_strata"));
    try std.testing.expectEqualStrings(atlas.DIR ++ "/qud/qud_strata" ++ atlas.EXT, ed.path());
    ed.askOpen();
    try std.testing.expectEqualStrings("qud/", ed.listing.here());
    try std.testing.expectEqualStrings(ed.path(), ed.listing.at(ed.listed_at));
    ed.desk = .{ .back = true };
    editor.modalKeys(ed);
    try std.testing.expectEqual(editor.Modal.open, ed.modal);
    try std.testing.expectEqual(@as(usize, 0), ed.listing.here().len);
    editor.modalKeys(ed);
    try std.testing.expectEqual(editor.Modal.none, ed.modal);
    ed.field.put("Bog");
    var buf: [atlas.PATH_MAX]u8 = undefined;
    try std.testing.expectEqualStrings(atlas.DIR ++ "/qud/bog" ++ atlas.EXT, ed.namedPath(&buf).?);
}

test "a full procgen preview keeps the hero's place in the pool, as play does" {
    const ed = try testEditor();
    defer ed.destroy();
    var foes = pack.Spec{ .packs = pack.PACKS_MAX, .few = 0, .gap = 0, .makeup_n = 1 };
    foes.makeup[0] = pack.Makeup.of(&(.{.rat} ** pack.MAKEUP_MAX));
    const n = ed.map.add(.{ .procgen = .{ .floor = .{ .wilds = .{} }, .foes = foes } }).?;
    ed.select(n);
    ed.preview();
    try std.testing.expectEqual(actor.MAX - actor.most(actor.HERO), ed.shown_n);
    try std.testing.expect(ed.lv.vacant(ed.arrival()) or ed.lv.at(ed.arrival()).solid());
}

test "a procgen node shows a roll of it with its packs, and a bespoke one counts the ground no walk reaches" {
    const ed = try testEditor();
    defer ed.destroy();
    const n = ed.map.add(.{ .procgen = .{ .floor = .{ .wilds = .{} } } }).?;
    ed.select(n);
    ed.preview();
    const open = ed.lv.openCount();
    const foes = ed.shown_n;
    const first = ed.lv.tile;
    editor.reroll(ed);
    ed.preview();
    try std.testing.expect(!std.mem.eql(grid.Tile, &first, &ed.lv.tile));
    const b = ed.map.add(.{ .bespoke = .{} }).?;
    ed.select(b);
    ed.tool = .paint;
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 2, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 6, .y = 6 });
    editor.laySpan(ed, .{ .from = .{ .x = 20, .y = 2 }, .erase = false, .shape = .rect }, .{ .x = 22, .y = 4 });
    ed.map.start = .{ .node = b, .at = .{ .x = 3, .y = 3 } };
    click(ed, .{ .foe = .rat }, .{ .x = 21, .y = 3 });
    ed.preview();
    std.debug.print("a wilds roll: {d} open cells, {d} foes placed; two rooms apart: {d} cells and {d} foe cut off\n", .{ open, foes, ed.issues.cut_off, ed.issues.foes_cut_off });
    try std.testing.expect(open > 0 and foes > 0);
    try std.testing.expectEqual(@as(usize, 9), ed.issues.cut_off);
    try std.testing.expectEqual(@as(usize, 1), ed.issues.foes_cut_off);
    try std.testing.expect(!ed.issues.start_walled);
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
        if (ed.lv.at(q) != inks.get(.first) and ed.here().doorAt(q) == null) break q;
    } else unreachable;
    editor.pickUp(ed, p, false);
    try std.testing.expectEqualStrings(editor.GENERATED, ed.said.text());
    try std.testing.expectEqual(inks.get(.first), ed.ink.get(.first));
    try std.testing.expectEqual(inks.get(.second), ed.ink.get(.second));
}

test "a pasted barrel hanging off the map counts as not fitting, as a torch does" {
    const ed = try testBespoke();
    defer ed.destroy();
    ed.tool = .paint;
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .rect }, .{ .x = 5, .y = 4 });
    click(ed, .barrel, .{ .x = 4, .y = 4 });
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 4, .y = 4 }, .erase = false, .shape = .select }, .{ .x = 5, .y = 4 });
    editor.copySelection(ed, false);
    editor.startPaste(ed);
    const at = P{ .x = -1, .y = 10 };
    try std.testing.expectEqual(@as(usize, 1), editor.layAside(ed, at).left);
    ed.gesture();
    editor.layBoard(ed, at);
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
    try std.testing.expect(ed.dirty);
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
    const hist = .{ ed.hist_base, ed.hist_len, ed.hist_at };
    const was = dragFirstBox(ed);
    try std.testing.expect(!ed.map.node[0].pos.eq(was));
    ed.drop();
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    try std.testing.expectEqual(hist, .{ ed.hist_base, ed.hist_len, ed.hist_at });
    ed.redo();
    ed.redo();
    try std.testing.expectEqual(ed.hist_len, ed.hist_at);
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
    try std.testing.expectEqual(ed.hist_len, ed.hist_at);
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
    editor.mapMouse(ed, c, true);
    editor.escape(ed);
    try std.testing.expect(ed.selection != null);
    ed.desk = .{ .paint = true, .mouse = mouseOn(ed, c, .{ .x = 6, .y = 2 }) };
    editor.mapMouse(ed, c, true);
    try std.testing.expectEqual(grid.Tile.wall, tileAt(ed, .{ .x = 6, .y = 2 }));
    ed.desk = .{};
    editor.mapMouse(ed, c, true);
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 10, .y = 10 }, .erase = false, .shape = .rect }, .{ .x = 12, .y = 12 });
    ed.gesture();
    editor.laySpan(ed, .{ .from = .{ .x = 10, .y = 10 }, .erase = false, .shape = .select }, .{ .x = 12, .y = 12 });
    editor.copySelection(ed, false);
    editor.startPaste(ed);
    ed.desk = .{ .paint = true, .paint_hit = true, .mouse = mouseOn(ed, c, .{ .x = -1, .y = -1 }) };
    ed.gesture();
    editor.mapMouse(ed, c, true);
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
    editor.graphMouse(ed, c, true);
    try std.testing.expect(ed.map.node[0].pos.eq(was));
    ed.desk = .{ .mouse = back };
    editor.graphMouse(ed, c, true);
    try std.testing.expectEqual(@as(usize, 0), ed.hist_at);
    try std.testing.expect(!ed.dirty);
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
    editor.laySpan(ed, .{ .from = room.lo, .erase = false, .shape = .rect }, room.hi.sub(.{ .x = 1, .y = 1 }));
    var cells = room.cells();
    while (cells.next()) |p| {
        if (!actor.roomFor(ed.map.node[ed.node].plan.bespoke.bodies(), .rat)) break;
        click(ed, .{ .foe = .rat }, p);
    }
    ed.tool = .{ .foe = .slime };
    try std.testing.expect(!editor.legal(ed, .{ .x = 2, .y = 2 }));
    ed.tool = .{ .foe = .pib };
    try std.testing.expect(editor.legal(ed, .{ .x = 2, .y = 2 }));
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
