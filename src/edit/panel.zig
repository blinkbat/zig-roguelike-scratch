const interaction = @import("interaction.zig");
const placement = @import("placement.zig");
const widgets = @import("widgets.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const actor = @import("../play/actor.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");
const knobs = @import("knobs.zig");
const canvas = @import("canvas.zig");
const modals = @import("modals.zig");
const editor = @import("editor.zig");
const text_panel = @import("text_panel.zig");
const P = mathx.P;
const Desk = input.Desk;
const SMALL = widgets.DETAIL;
const HEAD = widgets.HEAD;
const PANEL_BG = look.EDIT_PANEL;
const ON = look.EDIT_ON;
const HOVER = look.EDIT_HOVER;
const WARN = look.EDIT_WARN;
const SEP = menu.SEP;

const WORKSPACE_COLS = 2;
const WORKSPACE_ROWS = std.math.divCeil(usize, std.enums.values(editor.Lower).len, WORKSPACE_COLS) catch unreachable;
pub const WORKSPACE_TOP: i32 = widgets.PAD + HEAD + widgets.GAP + (5 + WORKSPACE_ROWS) * widgets.ROW_STEP + widgets.GAP;

pub fn drawPanel(ed: *editor.Editor, g: *game.Game) void {
    var buf: [widgets.LINE]u8 = undefined;
    rl.drawRectangle(0, 0, widgets.PANEL_W, g.screen.y, PANEL_BG);
    rl.drawRectangle(widgets.PANEL_W - 1, 0, 1, g.screen.y, look.EDGE);
    var y = widgets.PAD;
    var fit_buf: [widgets.LINE]u8 = undefined;
    widgets.textFace(&g.face).draw(widgets.fitBefore(&g.face, &buf, &fit_buf, ed.path(), if (ed.history.dirty) " *" else "", widgets.INNER_W), widgets.PAD, y, widgets.TEXT, look.TEXT);
    y += HEAD + widgets.GAP;
    var file = widgets.Across{ .y = y, .n = 4 };
    if (widgets.button(ed.controls(), &g.face, file.next(), "New", false, true, widgets.keyed("New map", Desk.NEW_CAPTION))) ed.askName(.new);
    if (widgets.button(ed.controls(), &g.face, file.next(), "Open", false, true, widgets.keyed("Open a map", Desk.OPEN_CAPTION))) ed.askOpen();
    if (widgets.button(ed.controls(), &g.face, file.next(), "Save", false, true, widgets.keyed("Save", Desk.SAVE_CAPTION))) _ = ed.save();
    if (widgets.button(ed.controls(), &g.face, file.next(), "Save as", false, true, widgets.keyed("Save under a new name", Desk.SAVE_AS_CAPTION))) ed.askName(.save_as);
    file.done();
    y += widgets.ROW_STEP;
    var views = widgets.Across{ .y = y, .n = std.enums.values(editor.View).len + 1 };
    for (std.enums.values(editor.View)) |v| {
        if (widgets.button(ed.controls(), &g.face, views.next(), menu.named(v), ed.view == v, true, widgets.keyed("The map of one node, or every node and how they link", Desk.GRAPH_CAPTION))) ed.setView(v);
    }
    if (widgets.button(ed.controls(), &g.face, views.next(), "Fit", false, ed.view == .map, "Fit the map in view")) interaction.fitView(ed, editor.Editor.canvas(g));
    views.done();
    y += widgets.ROW_STEP;
    var library = widgets.Across{ .y = y, .n = 3 };
    if (widgets.button(ed.controls(), &g.face, library.next(), "Objects", false, true, widgets.keyed("Every tile and body, and what each is", Desk.OBJECTS_CAPTION))) ed.ask(.objects);
    if (widgets.button(ed.controls(), &g.face, library.next(), "Text", false, true, "Rewrite player-facing text and tag its author")) text_panel.open(ed);
    if (widgets.button(ed.controls(), &g.face, library.next(), "Keys", false, true, widgets.keyed("Every key", Desk.HELP_CAPTION))) ed.ask(.help);
    library.done();
    y += widgets.ROW_STEP;
    var story = widgets.Across{ .y = y, .n = 2 };
    if (widgets.button(ed.controls(), &g.face, story.next(), "Dialog", false, true, "Folk and the conversations they open: lines, choices and what each does")) editor.plot.open(ed, .dialogs);
    if (widgets.button(ed.controls(), &g.face, story.next(), "Script", false, true, "Triggers: when every condition holds after a turn, their actions run in order")) editor.plot.open(ed, .script);
    story.done();
    y += widgets.ROW_STEP;
    var acts = widgets.Across{ .y = y, .n = 4 };
    if (widgets.button(ed.controls(), &g.face, acts.next(), "Undo", false, ed.history.at > 0, widgets.keyed("Undo", Desk.UNDO_CAPTION))) ed.undo();
    if (widgets.button(ed.controls(), &g.face, acts.next(), "Redo", false, ed.history.at < ed.history.len, widgets.keyed("Redo", Desk.REDO_CAPTION))) ed.redo();
    if (widgets.button(ed.controls(), &g.face, acts.next(), "Play", false, true, "Play from the map start (" ++ Desk.PLAY_CAPTION ++ "); " ++ Desk.PLAY_HERE_CAPTION ++ " comes back")) {
        ed.playStart();
    }
    if (widgets.button(ed.controls(), &g.face, acts.next(), "Title", false, true, widgets.keyed("Back to the title", Desk.BACK_CAPTION))) ed.request(.leave);
    acts.done();
    y += widgets.ROW_STEP;
    if (ed.lower == .generator and ed.rolled() == null) ed.lower = .nodes;
    for (std.enums.values(editor.Lower), 0..) |l, i| {
        const s = mathx.unslot(i, WORKSPACE_COLS);
        const r = widgets.slotOf(widgets.PAD, widgets.INNER_W, y + s.y * widgets.ROW_STEP, @intCast(s.x), WORKSPACE_COLS);
        const live = l != .generator or ed.rolled() != null;
        if (widgets.button(ed.controls(), &g.face, r, menu.named(l), ed.lower == l, live, LOWER_TIPS.get(l))) {
            ed.lower = l;
            ed.lower_scroll = 0;
        }
    }
    y += WORKSPACE_ROWS * widgets.ROW_STEP + widgets.GAP;
    std.debug.assert(y == WORKSPACE_TOP);
    ed.lower_top = y;
    switch (ed.lower) {
        .tools => drawToolsWorkspace(ed, g, y),
        .nodes => drawNodesWorkspace(ed, g, y),
        .generator => if (ed.generator()) |pg| knobs.drawGenerator(ed, g, y, pg),
        .things => drawThings(ed, g, y),
    }
}

fn drawToolsWorkspace(ed: *editor.Editor, g: *game.Game, top: i32) void {
    var y = beginScroll(ed, g, top);
    defer endScroll(ed);
    var clipboard = widgets.Across{ .y = y, .n = 3 };
    const on_map = ed.view == .map and ed.paintable();
    const selected = ed.selection != null and on_map;
    if (widgets.button(ed.controls(), &g.face, clipboard.next(), "Copy", false, selected, widgets.keyed("Copy selection", Desk.COPY_CAPTION))) placement.copySelection(ed, false);
    if (widgets.button(ed.controls(), &g.face, clipboard.next(), "Cut", false, selected, widgets.keyed("Cut selection", Desk.CUT_CAPTION))) placement.copySelection(ed, true);
    if (widgets.button(ed.controls(), &g.face, clipboard.next(), "Paste", ed.pasting, ed.board.size.x > 0 and on_map, widgets.keyed("Paste selection", Desk.PASTE_CAPTION))) placement.startPaste(ed);
    clipboard.done();
    y += widgets.ROW_STEP;
    if (widgets.button(ed.controls(), &g.face, widgets.cellOfRow(y, 0, 1), "Clear selection", false, selected, widgets.keyed("Clear selection", Desk.DELETE_CAPTION))) placement.clearSelection(ed);
    y += widgets.ROW_STEP + widgets.BLOCK_GAP;
    y = drawTools(ed, g, y);
    scrolledTo(ed, g, top, y);
}

fn drawNodesWorkspace(ed: *editor.Editor, g: *game.Game, top: i32) void {
    var y = top;
    var adds = widgets.Across{ .y = y, .n = 2 };
    if (widgets.button(ed.controls(), &g.face, adds.next(), "+ Bespoke", false, true, "A node you paint yourself")) editor.addNode(ed, .{ .bespoke = .{} });
    if (widgets.button(ed.controls(), &g.face, adds.next(), "+ Procgen", false, true, knobs.ADD_PROCGEN_TIP)) editor.addNode(ed, .{ .procgen = .{} });
    adds.done();
    y += widgets.ROW_STEP;
    if (ed.renaming or ed.renamed) {
        modals.fieldRow(ed, g, widgets.cellOfRow(y, 0, 1));
    } else {
        var node = widgets.Across{ .y = y, .n = 2 };
        if (widgets.button(ed.controls(), &g.face, node.next(), "Rename", false, true, widgets.keyed("Name this node", Desk.RENAME_CAPTION))) ed.startRename();
        const armed = ed.delete_armed == ed.node;
        if (widgets.button(ed.controls(), &g.face, node.next(), if (armed) "Delete it?" else "Delete", armed, ed.map.node_n > 1, if (armed) "Again deletes it; its doors' links go with it" else "Delete this node; it asks first")) {
            if (armed) editor.deleteNode(ed) else ed.delete_armed = ed.node;
        }
        node.done();
    }
    y += widgets.ROW_H + widgets.SECTION_GAP;
    ed.lower_top = y;
    drawNodes(ed, g, y);
}

const LOWER_TIPS = std.EnumArray(editor.Lower, [:0]const u8).init(.{
    .tools = "Painting, shapes, terrain palette and clipboard",
    .nodes = "Every node of the map",
    .things = "What is on this node and what is wrong with it; a row shows it on the map",
    .generator = "What this procgen node's floor, sky and foes are rolled from",
});

fn drawNodes(ed: *editor.Editor, g: *game.Game, top: i32) void {
    var detail_buf: [widgets.LINE]u8 = undefined;
    const shown: i32 = @intFromFloat(lowerArea(g, top).height);
    ed.node_rows = @max(1, @as(usize, @intCast(@divTrunc(shown, editor.NODE_H))));
    if (ed.revealed != ed.node) {
        ed.scroll = mathx.reveal(ed.scroll, ed.node, ed.node_rows);
        ed.revealed = ed.node;
    }
    ed.scroll = widgets.clampTop(ed.scroll, ed.map.node_n, ed.node_rows);
    widgets.scissor(lowerArea(g, top));
    defer rl.endScissorMode();
    var y = top;
    for (ed.map.nodes()[ed.scroll..], ed.scroll..) |*nd, n| {
        if (y >= g.screen.y) break;
        const r = raster.rect(widgets.PAD, y, widgets.INNER_W, editor.NODE_H - editor.NODE_GAP);
        const h = widgets.hot(ed.controls(), r, true, false, "Open this node");
        widgets.plate(r, n == ed.node, h.hot);
        drawNodeTitle(ed, g, n, r, y + editor.TITLE_DY);
        widgets.textFace(&g.face).draw(nodeDetail(nd, &detail_buf), widgets.textX(r), y + editor.TITLE_DY + editor.DETAIL_DY, SMALL, if (nd.unlinked() > 0) WARN else look.DIM);
        if (h.hit) ed.goTo(n);
        y += editor.NODE_H;
    }
    drawScroll(g, top, @as(i32, @intCast(ed.scroll)) * editor.NODE_H, @as(i32, @intCast(ed.map.node_n -| ed.node_rows)) * editor.NODE_H);
}

fn nodeDetail(nd: *const atlas.Node, buf: []u8) [:0]const u8 {
    const kind = switch (nd.plan) {
        .bespoke => @tagName(nd.plan),
        .procgen => |*pg| @tagName(pg.floor),
    };
    const open = nd.unlinked();
    if (open == 0) return std.fmt.bufPrintZ(buf, "{s}, {d} doors", .{ kind, nd.door_n }) catch "";
    return std.fmt.bufPrintZ(buf, "{s}, {d} doors, {d} unlinked", .{ kind, nd.door_n, open }) catch "";
}

const ICON_H: i32 = 52;
const TOOL_ROW: usize = 5;
const SWATCH: i32 = 40;
const SWATCH_GAP: i32 = 4;
pub const SHAPE_COLS: usize = 3;
const PALETTE_COLS: usize = @intCast(@divTrunc(widgets.INNER_W + SWATCH_GAP, SWATCH + SWATCH_GAP));
const PALETTE = blk: {
    var tiles: []const grid.Tile = &.{};
    for (std.enums.values(grid.Tile)) |t| {
        if (!t.isOpened()) tiles = tiles ++ &[_]grid.Tile{t};
    }
    break :blk tiles;
};

fn drawTools(ed: *editor.Editor, g: *game.Game, top: i32) i32 {
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    const rows = comptime std.math.divCeil(usize, editor.TOOLS.len, TOOL_ROW) catch unreachable;
    for (editor.TOOLS, Desk.TOOL_CAPTIONS, 0..) |t, key, i| {
        const s = mathx.unslot(i, TOOL_ROW);
        const r = widgets.slotOf(widgets.PAD, widgets.INNER_W, y + s.y * (ICON_H + widgets.GAP), @intCast(s.x), TOOL_ROW);
        const icon = rl.Rectangle{ .x = r.x, .y = r.y, .width = r.width, .height = ICON_H };
        const live = t.fits(ed.here());
        const h = widgets.hot(ed.controls(), icon, live, false, if (live) t.tip() else editor.GENERATED);
        widgets.plate(icon, t.eql(ed.tool), h.hot);
        const pic = widgets.pictureIn(icon, ICON_PIC, ICON_PIC_TOP);
        if (t == .paint) swatch(g, ed.ink.get(.first), pic) else toolFigure(g, t, pic);
        if (!live) rl.drawRectangleRec(icon, UNLIVE);
        widgets.textFace(&g.face).draw(key, @as(i32, @intFromFloat(icon.x)) + ICON_KEY.x, @as(i32, @intFromFloat(icon.y)) + ICON_KEY.y, SMALL, look.DIM);
        if (h.hit) ed.setTool(t);
    }
    y += @as(i32, @intCast(rows)) * (ICON_H + widgets.GAP) + widgets.GAP;
    for (editor.SHAPES, Desk.SHAPE_CAPTIONS, 0..) |s, key, i| {
        const r = shapeSlot(y, i);
        const label = std.fmt.bufPrintZ(&buf, "{s} {s}", .{ key, SHAPE_LABELS.get(s) }) catch "";
        const live = s == .select or ed.paintable();
        const h = widgets.hot(ed.controls(), r, live, false, if (live) s.tip() else editor.GENERATED);
        widgets.plate(r, ed.shape == s and (s == .select or ed.tool.broad()), h.hot);
        widgets.drawFit(&g.face, label, SMALL, widgets.insetW(r), false, widgets.textX(r), @as(i32, @intFromFloat(r.y)) + editor.SMALL_DY, if (live) look.TEXT else look.DIM);
        if (h.hit) ed.setShape(s);
    }
    y += @as(i32, @intCast(std.math.divCeil(usize, editor.SHAPES.len, SHAPE_COLS) catch unreachable)) * widgets.ROW_STEP;
    knobs.rowLabel(g, y, "Brush");
    const n = ed.brushSize();
    const by = knobs.stepper(ed, g, widgets.row(widgets.PAD + editor.LABEL_W, y, editor.BRUSH_SPAN), std.fmt.bufPrintZ(&buf, "{d}x{d}", .{ n, n }) catch "", .{
        .{ .tip = widgets.keyed("Smaller", Desk.BRUSH_CAPTION), .live = ed.brush > 0 },
        .{ .tip = widgets.keyed("Bigger", Desk.BRUSH_CAPTION), .live = ed.brush < editor.BRUSHES.len - 1 },
    });
    if (by != 0) ed.stepBrush(by);
    const inks_x = widgets.PAD + widgets.INNER_W - @as(i32, editor.INKS.len) * (SWATCH + widgets.GAP) + widgets.GAP;
    for (editor.INKS, 0..) |k, i| {
        const r = raster.rect(inks_x + @as(i32, @intCast(i)) * (SWATCH + widgets.GAP), y - @divTrunc(SWATCH - widgets.ROW_H, 2), SWATCH, SWATCH);
        swatch(g, ed.ink.get(k), r);
        rl.drawRectangleLinesEx(r, canvas.INK_EDGE, INK_EDGES.get(k));
        _ = widgets.hot(ed.controls(), r, true, false, INK_TIPS.get(k));
    }
    widgets.textFace(&g.face).draw("Inks", inks_x - widgets.textFace(&g.face).width("Inks", SMALL) - widgets.GAP, y + editor.SMALL_DY, SMALL, look.DIM);
    y += widgets.ROW_STEP + widgets.GAP;
    const swatches = Tiles{ .x = widgets.PAD, .y = y, .cols = PALETTE_COLS, .pitch = SWATCH + SWATCH_GAP, .size = SWATCH };
    for (PALETTE, 0..) |t, i| {
        const r = swatches.at(i);
        const h = widgets.hot(ed.controls(), r, true, false, PALETTE_TIPS.get(t));
        swatch(g, t, r);
        if (inkOf(ed, t)) |k| rl.drawRectangleLinesEx(r, canvas.INK_EDGE, INK_EDGES.get(k)) else if (h.hot) rl.drawRectangleLinesEx(r, 1, HOVER);
        const second = h.hot and ed.desk.erase_hit;
        if (h.hit or second) {
            ed.ink.set(.of(second), t);
            if (ed.shape == .select) ed.setShape(.brush) else ed.setShape(ed.shape);
        }
    }
    y += swatches.height(PALETTE.len) + widgets.SECTION_GAP;
    return y;
}

pub const Tiles = struct {
    x: i32,
    y: i32,
    cols: usize,
    pitch: i32,
    size: i32,

    pub fn at(t: Tiles, i: usize) rl.Rectangle {
        const s = mathx.unslot(i, t.cols);
        return raster.rect(t.x + s.x * t.pitch, t.y + s.y * t.pitch, t.size, t.size);
    }

    pub fn height(t: Tiles, n: usize) i32 {
        return @as(i32, @intCast(std.math.divCeil(usize, n, t.cols) catch unreachable)) * t.pitch;
    }
};

pub fn shapeSlot(top: i32, i: usize) rl.Rectangle {
    const s = mathx.unslot(i, SHAPE_COLS);
    return widgets.slotOf(widgets.PAD, widgets.INNER_W, top + s.y * widgets.ROW_STEP, @intCast(s.x), SHAPE_COLS);
}

const ICON_PIC: f32 = 36;
const ICON_PIC_TOP: f32 = 3;
const ICON_KEY = P{ .x = 3, .y = 1 };
const UNLIVE = look.fade(look.BG, 0.6);
const SHAPE_LABELS = std.EnumArray(editor.Shape, [:0]const u8).init(.{ .brush = "Brush", .line = "Line", .rect = "Rect", .box = "Box", .fill = "Fill", .select = "Sel" });
const INK_EDGES = std.EnumArray(editor.Ink, rl.Color).init(.{ .first = ON, .second = WARN });
const INK_TIPS = std.EnumArray(editor.Ink, [:0]const u8).init(.{
    .first = "The first ink: " ++ Desk.PAINT_CAPTION ++ " paints it; " ++ Desk.PAINT_CAPTION ++ " on the palette picks it",
    .second = "The second ink: " ++ Desk.ERASE_CAPTION ++ " paints it; " ++ Desk.ERASE_CAPTION ++ " on the palette picks it",
});

fn inkOf(ed: *const editor.Editor, t: grid.Tile) ?editor.Ink {
    for (editor.INKS) |k| {
        if (ed.ink.get(k) == t) return k;
    }
    return null;
}
const PALETTE_TIPS = blk: {
    var tips = std.EnumArray(grid.Tile, [:0]const u8).initUndefined();
    for (std.enums.values(grid.Tile)) |t| {
        tips.set(t, menu.named(t) ++ ": " ++ editor.PALETTE_RULE ++
            (if (t.solid()) "; blocks a step" else "") ++ (if (t.blind()) "; blocks sight" else ""));
    }
    break :blk tips;
};

fn drawThings(ed: *editor.Editor, g: *game.Game, top: i32) void {
    var buf: [widgets.LINE]u8 = undefined;
    var name: [atlas.TITLE_MAX]u8 = undefined;
    var y = beginScroll(ed, g, top);
    defer endScroll(ed);
    const is = ed.scene.issues;
    knobs.section(g, &y, "Problems");
    var wrong = false;
    if (is.start_walled) {
        wrong = true;
        thingRow(ed, g, &y, "The start is on solid ground", WARN, ed.map.start.at);
    }
    if (is.unlinked > 0) {
        wrong = true;
        thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{d} door(s) lead nowhere", .{is.unlinked}) catch "", WARN, null);
    }
    if (is.cut_off > 0) {
        wrong = true;
        thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{d} open cells no walk reaches (shaded)", .{is.cut_off}) catch "", WARN, is.reach_from);
    }
    if (is.foes_cut_off > 0) {
        wrong = true;
        thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{d} foe(s) no walk reaches", .{is.foes_cut_off}) catch "", WARN, null);
    }
    const endless = ed.map.script.endless();
    if (endless > 0) {
        wrong = true;
        thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{d} dialog(s) never end, so never open", .{endless}) catch "", WARN, null);
    }
    if (!wrong) thingRow(ed, g, &y, "Nothing wrong", look.DIM, null);
    y += widgets.BLOCK_GAP;
    knobs.section(g, &y, if (ed.here().unrolled()) "On this roll" else "On this node");
    if (ed.scene.start_at) |s| thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "Start  {d},{d}", .{ s.x, s.y }) catch "", look.TEXT, s);
    for (ed.here().doors(), 0..) |d, k| {
        const line = if (d.to) |to|
            std.fmt.bufPrintZ(&buf, "Door {d}  {d},{d}  to {s}, door {d}", .{ k, d.at.x, d.at.y, ed.nodeName(to.node, &name), to.door }) catch ""
        else
            std.fmt.bufPrintZ(&buf, "Door {d}  {d},{d}  leads nowhere", .{ k, d.at.x, d.at.y }) catch "";
        thingRow(ed, g, &y, line, if (d.to == null) WARN else look.TEXT, d.at);
    }
    for (ed.scene.shownFoes()) |f| thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{s}  {d},{d}", .{ editor.kindName(f.kind), f.at.x, f.at.y }) catch "", look.TEXT, f.at);
    const s = &ed.map.script;
    for (s.folks()) |f| {
        if (f.node != ed.node) continue;
        thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "{s}  {d},{d}  talks: {s}", .{ f.called(), f.at.x, f.at.y, editor.plot.talksTo(s, &f) }) catch "", look.TEXT, f.at);
    }
    switch (ed.plan().*) {
        .bespoke => |*b| {
            for (b.torches()) |t| thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "Torch  {d},{d}", .{ t.x, t.y }) catch "", look.TEXT, t);
            for (&b.barrel, 0..) |*on, i| {
                if (!on.*) continue;
                const p = grid.Level.of(i);
                thingRow(ed, g, &y, std.fmt.bufPrintZ(&buf, "Barrel  {d},{d}", .{ p.x, p.y }) catch "", look.TEXT, p);
            }
        },
        .procgen => {},
    }
    scrolledTo(ed, g, top, y);
}

pub fn clipped(ed: *const editor.Editor, y: i32) bool {
    const c = ed.clip orelse return false;
    const top: f32 = @floatFromInt(y);
    return top + widgets.ROW_H <= c.y or top >= c.y + c.height;
}

fn thingRow(ed: *editor.Editor, g: *game.Game, y: *i32, line: [:0]const u8, col: rl.Color, at: ?P) void {
    if (clipped(ed, y.*)) {
        y.* += widgets.ROW_H;
        return;
    }
    const r = widgets.row(widgets.PAD, y.*, widgets.INNER_W);
    const h = widgets.hot(ed.controls(), r, at != null, false, if (at != null) "Show it on the map" else null);
    widgets.plate(r, false, h.hot);
    widgets.drawFit(&g.face, line, SMALL, widgets.insetW(r), false, widgets.textX(r), y.* + editor.SMALL_DY, col);
    if (h.hit) ed.showCell(editor.Editor.canvas(g), at.?);
    y.* += widgets.ROW_H;
}

pub fn toolPicture(g: *const game.Game, t: editor.Tool) ?rl.Texture2D {
    return switch (t) {
        .barrel => g.sprites.barrel,
        .foe => |k| g.sprites.body(k),
        .start => g.sprites.body(actor.HERO),
        .paint, .torch, .folk, .door, .link => null,
    };
}

pub fn toolFigure(g: *game.Game, t: editor.Tool, r: rl.Rectangle) void {
    widgets.figure(&g.face, toolPicture(g, t), t.look_(), r);
}

pub fn bareBg(t: grid.Tile) rl.Color {
    return look.tileBg(t) orelse look.BARE_WALL;
}

pub fn swatch(g: *game.Game, t: grid.Tile, r: rl.Rectangle) void {
    const u = look.under(t);
    if (u) |b| {
        if (g.sprites.tileOf(b, null)) |tex| widgets.sprite(tex, r) else if (look.tileBg(b)) |bg| rl.drawRectangleRec(r, bg);
    }
    if (g.sprites.tileOf(t, .{})) |tex| return widgets.sprite(tex, r);
    if (u == null) rl.drawRectangleRec(r, bareBg(t));
    widgets.tileGlyph(&g.face, t, r);
}

pub fn drawNodeTitle(ed: *editor.Editor, g: *const game.Game, n: usize, r: rl.Rectangle, y: i32) void {
    var buf: [widgets.LINE]u8 = undefined;
    const typing = ed.renamingNode(n);
    widgets.drawFit(&g.face, ed.nodeTitle(n, &buf), widgets.TEXT, widgets.insetW(r), typing, widgets.textX(r), y, if (typing) look.UI_FOCUS else look.TEXT);
}

fn lowerArea(g: *const game.Game, top: i32) rl.Rectangle {
    return raster.rect(0, top, widgets.PANEL_W, @max(0, g.screen.y - top));
}

fn lowerScroll(ed: *editor.Editor, g: *const game.Game, top: i32) widgets.Scroll {
    return .{ .box = lowerArea(g, top), .top = &ed.lower_scroll, .most = &ed.lower_most };
}

pub fn beginScroll(ed: *editor.Editor, g: *const game.Game, top: i32) i32 {
    return lowerScroll(ed, g, top).begin(&ed.clip);
}

pub fn endScroll(ed: *editor.Editor) void {
    widgets.unclip(&ed.clip);
}

pub fn scrolledTo(ed: *editor.Editor, g: *const game.Game, top: i32, end: i32) void {
    lowerScroll(ed, g, top).fit(end, widgets.PAD);
    drawScroll(g, top, ed.lower_scroll, ed.lower_most);
}

fn drawScroll(g: *const game.Game, top: i32, offset: i32, most: i32) void {
    if (most <= 0) return;
    const height = g.screen.y - top - 2 * widgets.GAP;
    if (height <= 0) return;
    const shown: usize = @intCast(g.screen.y - top);
    widgets.scrollbar(raster.rect(widgets.PANEL_W - 2 * widgets.SCROLL_W, top + widgets.GAP, widgets.SCROLL_W, height), @intCast(std.math.clamp(offset, 0, most)), shown, shown + @as(usize, @intCast(most)));
}

const ACTION_W: i32 = 122;
const ACTIONS: i32 = std.enums.values(editor.CellAction).len;

pub fn drawStatus(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle) void {
    var buf: [widgets.LINE + 1]u8 = undefined;
    var state_buf: [widgets.LINE + 1]u8 = undefined;
    const top: i32 = @intFromFloat(c.y + c.height);
    const x = widgets.PANEL_W + widgets.PAD;
    const w = @as(i32, @intFromFloat(c.width)) - 2 * widgets.PAD;
    rl.drawRectangle(widgets.PANEL_W, top, g.screen.x - widgets.PANEL_W, editor.STATUS_H, PANEL_BG);
    rl.drawRectangle(widgets.PANEL_W, top, g.screen.x - widgets.PANEL_W, 1, look.EDGE);
    const state = toolState(ed, &state_buf);
    const state_w = widgets.textFace(&g.face).width(state, widgets.TEXT);
    var y = top + widgets.GAP;
    const action_w = ACTION_W;
    const actions_w = ACTIONS * action_w + (ACTIONS - 1) * widgets.GAP;
    const first_w = w - actions_w - widgets.BLOCK_GAP;
    widgets.drawFit(&g.face, hover(ed, c, &buf), widgets.TEXT, first_w - state_w - widgets.BLOCK_GAP, false, x, y, look.TEXT);
    widgets.textFace(&g.face).draw(state, x + first_w - state_w, y, widgets.TEXT, look.DIM);
    if (widgets.button(ed.controls(), &g.face, widgets.row(x + w - actions_w, y, action_w), "Play here", ed.cell_action == .play, true, "Choose a cell to play from")) interaction.armCellAction(ed, .play);
    if (widgets.button(ed.controls(), &g.face, widgets.row(x + w - action_w, y, action_w), "Go through", ed.cell_action == .go, true, "Choose a linked door to follow")) interaction.armCellAction(ed, .go);
    y += widgets.LINE_STEP;
    const said = ed.said_t > 0;
    const line: []const u8 = if (said) ed.said.text() else if (ed.view == .map) editor.CRIB_MAP else editor.CRIB_GRAPH;
    widgets.drawFit(&g.face, line, widgets.TEXT, w, false, x, y, if (said) look.UI_FOCUS else look.DIM);
}

fn toolState(ed: *const editor.Editor, buf: []u8) [:0]const u8 {
    const px: i32 = @intFromFloat(ed.px());
    if (ed.pasting) return std.fmt.bufPrintZ(buf, "Pasting {d}x{d}" ++ SEP ++ "{d} px", .{ ed.board.size.x, ed.board.size.y, px }) catch "";
    if (ed.shape == .select) return std.fmt.bufPrintZ(buf, "Select" ++ SEP ++ "{d} px", .{px}) catch "";
    const n = ed.brushSize();
    if (ed.tool.broad()) return std.fmt.bufPrintZ(buf, "{s} / {s}" ++ SEP ++ "{s} {d}x{d}" ++ SEP ++ "{d} px", .{ @tagName(ed.ink.get(.first)), @tagName(ed.ink.get(.second)), SHAPE_LABELS.get(ed.shape), n, n, px }) catch "";
    return std.fmt.bufPrintZ(buf, "{s}" ++ SEP ++ "{d} px", .{ ed.tool.name(), px }) catch "";
}

fn hover(ed: *editor.Editor, c: rl.Rectangle, buf: []u8) [:0]const u8 {
    if (!ed.mouseIn(c)) return "";
    var a: [atlas.TITLE_MAX]u8 = undefined;
    if (ed.view == .graph) {
        if (ed.dotUnder(c, ed.desk.mouse)) |l| {
            const to = ed.map.door(l).to orelse return std.fmt.bufPrintZ(buf, "Node {d} door {d}: leads nowhere; drag to another door's dot to link it", .{ l.node, l.door }) catch "";
            return std.fmt.bufPrintZ(buf, "Node {d} door {d} leads to {s}, door {d}; {s} unlinks", .{ l.node, l.door, ed.nodeName(to.node, &a), to.door, Desk.ERASE_CAPTION }) catch "";
        }
        const n = ed.boxUnder(c, ed.desk.mouse) orelse return "";
        var d: [widgets.LINE]u8 = undefined;
        return std.fmt.bufPrintZ(buf, "{s} (node {d}): {s}", .{ ed.nodeName(n, &a), n, nodeDetail(&ed.map.node[n], &d) }) catch "";
    }
    const p = ed.mouseCell(c);
    if (!grid.Level.inside(p)) return "";
    const nd = ed.here();
    var out = std.io.fixedBufferStream(buf[0 .. buf.len - 1]);
    const wr = out.writer();
    wr.print("{d},{d}  {s}", .{ p.x, p.y, @tagName(ed.scene.lv.at(p)) }) catch {};
    if (nd.unrolled()) wr.writeAll(" (this roll)") catch {};
    switch (nd.plan) {
        .bespoke => |*b| {
            const i = grid.Level.idx(p);
            if (b.barrel[i]) wr.writeAll(", a barrel") catch {};
            if (b.torch.has(p)) wr.writeAll(", a torch") catch {};
        },
        .procgen => {},
    }
    for (ed.scene.shownFoes()) |f| {
        if (f.at.eq(p)) wr.print(", a {s}", .{actor.row(f.kind).name}) catch {};
    }
    if (ed.map.script.folkAt(ed.node, p)) |f| wr.print(", {s} (folk)", .{ed.map.script.folk[f].called()}) catch {};
    if (ed.scene.start_at) |s| {
        if (s.eq(p)) wr.writeAll(", the start") catch {};
    }
    if (nd.doorAt(p)) |k| {
        if (nd.door[k].to) |to| {
            wr.print(", door {d} to {s}, door {d} ({s} goes through)", .{ k, ed.nodeName(to.node, &a), to.door, Desk.GO_CAPTION }) catch {};
        } else wr.print(", door {d}, leading nowhere", .{k}) catch {};
    }
    const n = out.getWritten().len;
    buf[n] = 0;
    return buf[0..n :0];
}
