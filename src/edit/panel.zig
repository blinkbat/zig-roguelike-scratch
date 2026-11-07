const interaction = @import("interaction.zig");
const placement = @import("placement.zig");
const widgets = @import("widgets.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const playground = @import("../map/playground.zig");
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
const effects = @import("effects.zig");
const P = mathx.P;
const Desk = input.Desk;
const Column = widgets.Column;
const DETAIL = widgets.DETAIL;
const PANEL_BG = widgets.PANEL_BG;
const ON = widgets.ON;
const WARN = look.EDIT_WARN;
const SEP = menu.SEP;

/// Buttons along the top bar: as wide as their words, set apart in groups.
const BAR_GROUP: i32 = 18;
const TAB_PIC: f32 = 26;

/// A row of the top bar, laid rightward from its left or leftward from its right.
const Bar = struct {
    ed: *editor.Editor,
    g: *game.Game,
    lay: union(enum) { right: widgets.Lay, left: widgets.LayEnd },

    fn from(ed: *editor.Editor, g: *game.Game, x: i32, y: i32) Bar {
        return .{ .ed = ed, .g = g, .lay = .{ .right = .{ .x = x, .y = y } } };
    }

    fn back(ed: *editor.Editor, g: *game.Game, right: i32, y: i32) Bar {
        return .{ .ed = ed, .g = g, .lay = .{ .left = .{ .right = right, .y = y } } };
    }

    fn take(b: *Bar, w: i32) rl.Rectangle {
        return switch (b.lay) {
            .right => |*l| l.take(w),
            .left => |*l| l.take(w),
        };
    }

    fn button(b: *Bar, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
        return smallButton(b.ed, b.g, b.take(widgets.labelW(&b.g.face, label, DETAIL)), label, on, live, tip);
    }

    fn group(b: *Bar) void {
        switch (b.lay) {
            .right => |*l| l.x += BAR_GROUP,
            .left => |*l| l.right -= BAR_GROUP,
        }
    }
};

pub const FileItem = enum {
    new,
    open,
    save,
    save_as,
    title,

    fn label(f: FileItem) [:0]const u8 {
        return switch (f) {
            .new => "New",
            .open => "Open",
            .save => "Save",
            .save_as => "Save as",
            .title => "Back to the title",
        };
    }

    fn key(f: FileItem) [:0]const u8 {
        return switch (f) {
            .new => Desk.NEW_CAPTION,
            .open => Desk.OPEN_CAPTION,
            .save => Desk.SAVE_CAPTION,
            .save_as => Desk.SAVE_AS_CAPTION,
            .title => Desk.BACK_CAPTION,
        };
    }

    fn pressed(f: FileItem, d: *const Desk) bool {
        return switch (f) {
            .new => d.new,
            .open => d.open,
            .save => d.save,
            .save_as => d.save_as,
            .title => false,
        };
    }

    pub fn onKey(f: FileItem, ed: *editor.Editor) void {
        if (f.pressed(&ed.desk)) f.act(ed);
    }

    fn act(f: FileItem, ed: *editor.Editor) void {
        switch (f) {
            .new => ed.askName(.new),
            .open => ed.askOpen(),
            .save => _ = ed.save(),
            .save_as => ed.askName(.save_as),
            .title => ed.request(.leave),
        }
    }
};

pub const FILE_ITEMS = std.enums.values(FileItem);

pub fn drawTop(ed: *editor.Editor, g: *game.Game) void {
    rl.drawRectangle(0, 0, g.screen.x, widgets.TOP_H, PANEL_BG);
    rl.drawRectangle(0, widgets.TOP_H - 1, g.screen.x, 1, look.EDGE);
    const file = fileSlot(g);
    var verbs = Bar.from(ed, g, widgets.rightX(file) + widgets.GAP, widgets.GAP);
    if (smallButton(ed, g, file, FILE_LABEL, isPopup(ed, .file), true, "New, open and save maps; back to the title")) {
        editor.openPopup(ed, file, .file, 0, g.screen.y);
    }
    verbs.group();
    if (verbs.button("Undo", false, ed.history.at > 0, widgets.keyed("Undo", Desk.UNDO_CAPTION))) ed.undo();
    if (verbs.button("Redo", false, ed.history.at < ed.history.len, widgets.keyed("Redo", Desk.REDO_CAPTION))) ed.redo();
    verbs.group();
    if (verbs.button("Objects", ed.modal == .objects, true, widgets.keyed("Every tile and body, and what each is", Desk.OBJECTS_CAPTION))) ed.ask(.objects);
    if (verbs.button("Effects", ed.modal == .effects, true, "Every particle effect and drawn missile, playing")) effects.open(ed);
    if (verbs.button("Text", ed.modal == .text, true, "Rewrite player-facing text and tag its author")) text_panel.open(ed);
    for (std.enums.values(editor.plot.Page)) |page| {
        if (verbs.button(page.label(), isPlot(ed, page), true, page.tip())) editor.plot.open(ed, page);
    }
    if (verbs.button("Keys", ed.modal == .help, true, widgets.keyed("Every key", Desk.HELP_CAPTION))) ed.ask(.help);
    var plays = Bar.back(ed, g, g.screen.x - widgets.PAD, widgets.GAP);
    const here = editor.CELL_ACTIONS.get(.play);
    if (plays.button(here.label, ed.cell_action == .play, true, here.tip)) interaction.armCellAction(ed, .play);
    if (plays.button("Play", false, true, "Play from the map start (" ++ Desk.PLAY_CAPTION ++ "); " ++ Desk.PLAY_HERE_CAPTION ++ " comes back")) ed.playStart();
    if (plays.button("Playground", false, true, PLAYGROUND_TIP)) ed.action = .playground;

    const tabs_y = widgets.GAP + widgets.ROW_STEP;
    var tabs = Bar.from(ed, g, widgets.PAD, tabs_y);
    for (editor.FAMILIES) |f| {
        const label = menu.named(f);
        const r = tabs.take(@as(i32, @intFromFloat(TAB_PIC)) + widgets.GAP + widgets.labelW(&g.face, label, DETAIL));
        const h = widgets.hot(ed.controls(), r, true, false, f.tip());
        widgets.buttonBack(r, true);
        widgets.plate(r, ed.family == f, h.hot);
        const pic = widgets.pictureAt(r, @floatFromInt(widgets.GAP), TAB_PIC);
        familyFigure(ed, g, f, pic);
        widgets.textFace(&g.face).draw(label, widgets.rightX(pic) + widgets.GAP, tabs_y + widgets.DETAIL_DY, DETAIL, look.TEXT);
        if (h.hit) ed.openFamily(f);
    }
    var views = Bar.back(ed, g, g.screen.x - widgets.PAD, tabs_y);
    if (views.button("Fit", false, ed.view == .map, widgets.keyed("Fit the map in view", Desk.FIT_CAPTION))) interaction.fitView(ed, editor.Editor.canvas(g));
    views.group();
    const order = std.enums.values(editor.View);
    for (0..order.len) |k| {
        const v = order[order.len - 1 - k];
        if (views.button(menu.named(v), ed.view == v, true, widgets.keyed("The map of one node, or every node and how they link", Desk.GRAPH_CAPTION))) ed.setView(v);
    }
}

const FILE_LABEL = "File";
const PLAYGROUND_TIP = "Every terrain, and a " ++ menu.word(playground.CLASS) ++ " casting freely; " ++ menu.named(game.PauseRow.debug) ++ " > " ++ menu.titleOf(game.debugging.Row.restart_map) ++ " resets it";

/// The File button's place, the bar's first.
pub fn fileSlot(g: *const game.Game) rl.Rectangle {
    return widgets.row(widgets.PAD, widgets.GAP, widgets.labelW(&g.face, FILE_LABEL, DETAIL));
}

fn isPopup(ed: *const editor.Editor, w: std.meta.Tag(editor.Which)) bool {
    const p = ed.popup orelse return false;
    return p.which == w;
}

fn isPlot(ed: *const editor.Editor, page: editor.plot.Page) bool {
    return switch (ed.modal) {
        .plot => |p| p == page,
        else => false,
    };
}

fn familyFigure(ed: *editor.Editor, g: *game.Game, f: editor.Family, r: rl.Rectangle) void {
    switch (f) {
        .terrain => swatch(g, ed.ink.get(.first), r),
        .props, .foes, .folk, .doors => toolFigure(g, ed.family_tool.get(f), r),
    }
}

/// The File dropdown's rows in `box`; a row picked closes it and does what it names.
pub fn fileRows(ed: *editor.Editor, g: *game.Game, box: rl.Rectangle) void {
    for (FILE_ITEMS, 0..) |f, k| {
        const r = editor.popupRow(box, .file, k);
        const hit = widgets.buttonSized(ed.controls(), &g.face, r, f.label(), DETAIL, false, true, true, null);
        const key_w = widgets.textFace(&g.face).width(f.key(), DETAIL);
        widgets.textFace(&g.face).draw(f.key(), widgets.rightX(r) - widgets.GAP - key_w, @as(i32, @intFromFloat(r.y)) + widgets.DETAIL_DY, DETAIL, look.DIM);
        if (hit) {
            ed.popup = null;
            f.act(ed);
        }
    }
}

fn heading(g: *game.Game, col: Column, y: *i32, s: [:0]const u8) void {
    widgets.heading(&g.face, s, col.left(), y.*);
    y.* += widgets.HEADING_H;
}

fn backPanel(col: Column, band: editor.Band, edge_x: i32) void {
    rl.drawRectangle(col.x, band.top, col.w, band.bottom - band.top, PANEL_BG);
    rl.drawRectangle(edge_x, band.top, 1, band.bottom - band.top, look.EDGE);
}

pub fn drawSide(ed: *editor.Editor, g: *game.Game) void {
    const col = editor.SIDE;
    const band = editor.Editor.bandOf(g.screen);
    backPanel(col, band, col.x + col.w - 1);
    var y = beginPane(ed, .side, col.box(band.top, band.bottom)) + widgets.PAD;
    y = drawSelect(ed, g, col, y);
    switch (ed.family) {
        .terrain => y = drawTerrain(ed, g, col, y),
        .foes => {
            y = drawFoeTypes(ed, g, col, y);
            y = drawTools(ed, g, col, y, .foes);
        },
        .props, .folk => y = drawTools(ed, g, col, y, ed.family),
        .doors => {
            y = drawTools(ed, g, col, y, .doors);
            y += widgets.GAP;
            const go = comptime editor.CELL_ACTIONS.get(.go);
            if (editor.button(ed, g, col.row(y), go.label, ed.cell_action == .go, true, widgets.keyed(go.tip, Desk.GO_CAPTION))) interaction.armCellAction(ed, .go);
            y += widgets.ROW_STEP;
        },
    }
    closePane(ed, .side, y);
}

/// Select, and once it is chosen the clipboard over its selection.
fn drawSelect(ed: *editor.Editor, g: *game.Game, col: Column, top: i32) i32 {
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    const selecting = ed.shape == .select;
    if (labelButton(ed, g, col.row(y), shapeLabel(&buf, .select), selecting, true, editor.Shape.select.tip())) ed.toggleSelect();
    y += widgets.ROW_STEP;
    if (!selecting) return y + widgets.GAP;
    var clipboard = widgets.Across{ .col = col, .y = y, .n = 4 };
    const on_map = ed.view == .map and ed.paintable();
    const selected = ed.selection != null and on_map;
    if (smallButton(ed, g, clipboard.next(), "Copy", false, selected, widgets.keyed("Copy selection", Desk.COPY_CAPTION))) placement.copySelection(ed, false);
    if (smallButton(ed, g, clipboard.next(), "Cut", false, selected, widgets.keyed("Cut selection", Desk.CUT_CAPTION))) placement.copySelection(ed, true);
    if (smallButton(ed, g, clipboard.next(), "Paste", ed.pasting, ed.board.size.x > 0 and on_map, widgets.keyed("Paste selection", Desk.PASTE_CAPTION))) placement.startPaste(ed);
    if (smallButton(ed, g, clipboard.next(), "Clear", false, selected, widgets.keyed("Clear selection", Desk.DELETE_CAPTION))) placement.clearSelection(ed);
    clipboard.done();
    return y + widgets.ROW_STEP + widgets.GAP;
}

fn smallButton(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return widgets.buttonSized(ed.controls(), &g.face, r, label, DETAIL, on, live, false, tip);
}

fn labelButton(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return widgets.flatButton(ed.controls(), &g.face, r, label, if (live) look.TEXT else look.DIM, on, live, false, tip);
}

fn drawTools(ed: *editor.Editor, g: *game.Game, col: Column, top: i32, f: editor.Family) i32 {
    var y = top;
    for (editor.TOOLS, Desk.TOOL_CAPTIONS) |t, key| {
        if (t.family() == f and (t != .foe or ed.foeShown(t.foe))) toolRow(ed, g, col, &y, t, key);
    }
    return y;
}

const TOOL_ROW_H: i32 = 44;
const TOOL_PIC: f32 = 36;
const KEY_W: i32 = 30;

/// A tool to pick: its key, its picture and its name.
fn toolRow(ed: *editor.Editor, g: *game.Game, col: Column, y: *i32, t: editor.Tool, key: [:0]const u8) void {
    defer y.* += TOOL_ROW_H;
    if (clippedH(ed, y.*, TOOL_ROW_H)) return;
    const r = raster.rect(col.left(), y.*, col.inner(), TOOL_ROW_H - widgets.GAP / 2);
    const live = t.fits(ed.here());
    const h = widgets.hot(ed.controls(), r, live, false, if (live) t.tip() else editor.GENERATED);
    widgets.plate(r, t.eql(ed.tool) and ed.shape != .select, h.hot);
    widgets.textFace(&g.face).draw(key, widgets.textX(r), widgets.midY(r, DETAIL), DETAIL, look.DIM);
    const pic = widgets.pictureAt(r, @floatFromInt(widgets.GAP + KEY_W), TOOL_PIC);
    if (t == .paint) swatch(g, ed.ink.get(.first), pic) else toolFigure(g, t, pic);
    const name_x = widgets.rightX(pic) + widgets.GAP * 2;
    widgets.drawFit(&g.face, t.name(), widgets.TEXT, widgets.rightX(r) - name_x - widgets.GAP, false, name_x, widgets.midY(r, widgets.TEXT), if (live) look.TEXT else look.DIM);
    if (!live) rl.drawRectangleRec(r, UNLIVE);
    if (h.hit) ed.takeTool(t);
}

const CHIP_GAP: i32 = 4;

/// Chips that narrow the foes listed to one type, wrapping as they fill the row.
fn drawFoeTypes(ed: *editor.Editor, g: *game.Game, col: Column, top: i32) i32 {
    var y = top;
    var x = col.left();
    const types = std.enums.values(actor.FoeType);
    for (0..types.len + 1) |k| {
        const t: ?actor.FoeType = if (k == 0) null else types[k - 1];
        const label = if (t) |ft| menu.named(ft) else "All";
        const w = widgets.labelW(&g.face, label, DETAIL);
        if (x > col.left() and x + w > col.left() + col.inner()) {
            x = col.left();
            y += widgets.ROW_H + CHIP_GAP;
        }
        if (smallButton(ed, g, widgets.row(x, y, w), label, ed.foe_type == t, true, "List the foes of this type")) ed.foe_type = t;
        x += w + CHIP_GAP;
    }
    return y + widgets.ROW_STEP + widgets.GAP;
}

const BRUSH_W: i32 = 64;
const BRUSH_SPAN: i32 = 2 * widgets.STEP_W + BRUSH_W;
const SWATCH: i32 = 40;
const SWATCH_GAP: i32 = 4;
const SHAPE_COLS: usize = 3;
const PALETTE = grid.SINGLES;
pub const PAINT_SHAPES = blk: {
    var out: []const editor.Shape = &.{};
    for (editor.SHAPES) |s| {
        if (s != .select) out = out ++ &[_]editor.Shape{s};
    }
    break :blk out[0..out.len].*;
};

fn drawTerrain(ed: *editor.Editor, g: *game.Game, col: Column, top: i32) i32 {
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    for (PAINT_SHAPES, 0..) |s, i| {
        const r = shapeSlot(col, y, i);
        const live = ed.paintable();
        if (labelButton(ed, g, r, shapeLabel(&buf, s), ed.shape == s and ed.tool.broad(), live, if (live) s.tip() else editor.GENERATED)) ed.setShape(s);
    }
    y += widgets.rowsOf(PAINT_SHAPES.len, SHAPE_COLS) * widgets.ROW_STEP + widgets.GAP;
    rowLabel(g, col, y, "Brush", DETAIL);
    const n = ed.brushSize();
    const by = knobs.stepper(ed, g, widgets.row(col.left() + editor.LABEL_W, y, BRUSH_SPAN), std.fmt.bufPrintZ(&buf, "{d}x{d}", .{ n, n }) catch "", .{
        .{ .tip = widgets.keyed("Smaller", Desk.BRUSH_CAPTION), .live = ed.brush > 0 },
        .{ .tip = widgets.keyed("Bigger", Desk.BRUSH_CAPTION), .live = ed.brush < editor.BRUSHES.len - 1 },
    });
    if (by != 0) ed.stepBrush(by);
    y += widgets.ROW_STEP;
    rowLabel(g, col, y, "Inks", DETAIL);
    for (editor.INKS, 0..) |k, i| {
        const r = raster.rect(col.left() + editor.LABEL_W + @as(i32, @intCast(i)) * (SWATCH + widgets.GAP), widgets.midIn(y, widgets.ROW_H, SWATCH), SWATCH, SWATCH);
        swatch(g, ed.ink.get(k), r);
        rl.drawRectangleLinesEx(r, canvas.INK_EDGE, INK_EDGES.get(k));
        _ = widgets.hot(ed.controls(), r, true, false, INK_TIPS.get(k));
    }
    y += widgets.ROW_STEP + widgets.GAP;
    heading(g, col, &y, "Palette");
    const swatches = Tiles{ .x = col.left(), .y = y, .cols = paletteCols(col), .pitch = SWATCH + SWATCH_GAP, .size = SWATCH };
    for (PALETTE, 0..) |t, i| {
        const r = swatches.at(i);
        const h = widgets.hot(ed.controls(), r, true, false, PALETTE_TIPS.get(t));
        swatch(g, t, r);
        if (inkOf(ed, t)) |k| rl.drawRectangleLinesEx(r, canvas.INK_EDGE, INK_EDGES.get(k)) else widgets.hoverEdge(r, h.hot);
        const second = h.hot and ed.desk.erase_hit;
        if (h.hit or second) {
            ed.ink.set(.of(second), t);
            ed.setShape(if (ed.shape == .select) .brush else ed.shape);
        }
    }
    return y + swatches.height(PALETTE.len) + widgets.SECTION_GAP;
}

fn paletteCols(col: Column) usize {
    return @intCast(@divTrunc(col.inner() + SWATCH_GAP, SWATCH + SWATCH_GAP));
}

pub fn rowLabel(g: *game.Game, col: Column, y: i32, s: [:0]const u8, size: i32) void {
    widgets.drawFit(&g.face, s, size, editor.LABEL_W - widgets.GAP, false, col.left(), widgets.midIn(y, widgets.ROW_H, size), look.TEXT);
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
        return widgets.rowsOf(n, t.cols) * t.pitch;
    }
};

pub fn shapeSlot(col: Column, top: i32, i: usize) rl.Rectangle {
    return col.grid(top, i, SHAPE_COLS, widgets.ROW_STEP);
}

const UNLIVE = look.fade(look.BG, 0.6);

fn shapeLabel(buf: []u8, s: editor.Shape) [:0]const u8 {
    return std.fmt.bufPrintZ(buf, "{s} {s}", .{ s.caption(), menu.named(s) }) catch "";
}
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

const INSPECT_TIPS = std.EnumArray(editor.Inspect, [:0]const u8).init(.{
    .things = "What is on this node and what is wrong with it; a row shows it on the map",
    .generator = "What this procgen node's floor, sky and foes are rolled from",
});

/// The node dropdown's place; fixed, so a pose can open it without drawing first.
pub fn nodeSlot(g: *const game.Game) rl.Rectangle {
    return editor.Editor.inspector(g).row(editor.Editor.bandOf(g.screen).top + widgets.PAD + widgets.HEADING_H);
}

pub fn drawInspector(ed: *editor.Editor, g: *game.Game) void {
    const col = editor.Editor.inspector(g);
    const band = editor.Editor.bandOf(g.screen);
    backPanel(col, band, col.x);
    const slot = nodeSlot(g);
    widgets.heading(&g.face, "Node", col.left(), band.top + widgets.PAD);
    var y: i32 = @intFromFloat(slot.y);
    if (ed.renaming or ed.renamed) {
        modals.fieldRow(ed, g, slot);
    } else if (nodeDropdown(ed, g, slot)) editor.openPopup(ed, slot, .node, ed.node, g.screen.y);
    y += widgets.ROW_STEP;
    var detail_buf: [widgets.LINE]u8 = undefined;
    const nd = ed.here();
    widgets.textFace(&g.face).draw(nodeDetail(nd, &detail_buf), col.left(), y, DETAIL, nodeInk(nd));
    y += DETAIL + widgets.BLOCK_GAP;
    var node = widgets.Across{ .col = col, .y = y, .n = 2 };
    if (smallButton(ed, g, node.next(), "Rename", ed.renaming, true, widgets.keyed("Name this node", Desk.RENAME_CAPTION)) and !ed.renamed) ed.startRename();
    const armed = ed.delete_armed == ed.node;
    if (smallButton(ed, g, node.next(), if (armed) "Delete it?" else "Delete", armed, ed.map.node_n > 1, if (armed) "Again deletes it; its doors' links go with it" else "Delete this node; it asks first")) {
        if (armed) editor.deleteNode(ed) else ed.delete_armed = ed.node;
    } else if (armed and ed.desk.clicked()) ed.delete_armed = null;
    node.done();
    y += widgets.ROW_STEP;
    var adds = widgets.Across{ .col = col, .y = y, .n = 2 };
    if (smallButton(ed, g, adds.next(), "+ Bespoke", false, true, "A node you paint yourself")) editor.addNode(ed, .{ .bespoke = .{} });
    if (smallButton(ed, g, adds.next(), "+ Procgen", false, true, knobs.ADD_PROCGEN_TIP)) editor.addNode(ed, .{ .procgen = .{} });
    adds.done();
    y += widgets.ROW_STEP + widgets.BLOCK_GAP;
    var tabs = widgets.Across{ .col = col, .y = y, .n = std.enums.values(editor.Inspect).len };
    for (std.enums.values(editor.Inspect)) |i| {
        const live = i != .generator or ed.rolled() != null;
        if (smallButton(ed, g, tabs.next(), menu.named(i), ed.inspect == i, live, if (live) INSPECT_TIPS.get(i) else "Only a procgen node is rolled from a generator")) ed.setInspect(i);
    }
    tabs.done();
    y += widgets.ROW_H;
    rl.drawRectangle(col.left(), y, col.inner(), 1, look.EDGE);
    y += widgets.GAP;
    const box = col.box(y, band.bottom);
    switch (ed.inspect) {
        .things => drawThings(ed, g, col, box),
        .generator => if (ed.rolled()) |pg| knobs.drawGenerator(ed, g, box, pg),
    }
}

/// The open node, picked from every node in the dropdown below it.
fn nodeDropdown(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle) bool {
    var buf: [widgets.LINE]u8 = undefined;
    const h = widgets.hot(ed.controls(), r, true, false, "Open another node");
    rl.drawRectangleRec(r, widgets.LIVE_FILL);
    rl.drawRectangleLinesEx(r, 1, if (isPopup(ed, .node)) ON else widgets.LIVE_EDGE);
    widgets.plate(r, false, h.hot);
    const caret_w = widgets.textFace(&g.face).width(DROP_CARET, widgets.TEXT);
    const y = @as(i32, @intFromFloat(r.y)) + widgets.TEXT_DY;
    widgets.drawFit(&g.face, ed.nodeTitle(ed.node, &buf), widgets.TEXT, widgets.insetW(r) - caret_w - widgets.GAP, false, widgets.textX(r), y, look.TEXT);
    widgets.textFace(&g.face).draw(DROP_CARET, widgets.rightX(r) - widgets.GAP - caret_w, y, widgets.TEXT, look.DIM);
    return h.hit;
}

const DROP_CARET = "v";

/// A node in the dropdown: its title and what it is; true when picked.
pub fn nodeRow(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, n: usize, modal: bool) bool {
    var detail_buf: [widgets.LINE]u8 = undefined;
    const h = widgets.hot(ed.controls(), r, true, modal, "Open this node");
    widgets.plate(r, n == ed.node, h.hot);
    const y: i32 = @intFromFloat(r.y);
    drawNodeTitle(ed, g, n, r, y + editor.TITLE_DY);
    const nd = &ed.map.node[n];
    widgets.textFace(&g.face).draw(nodeDetail(nd, &detail_buf), widgets.textX(r), y + editor.TITLE_DY + editor.NODE_DETAIL_DY, DETAIL, nodeInk(nd));
    return h.hit;
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

fn nodeInk(nd: *const atlas.Node) rl.Color {
    return if (nd.unlinked() > 0) WARN else look.DIM;
}

fn drawThings(ed: *editor.Editor, g: *game.Game, col: Column, box: rl.Rectangle) void {
    var name: [atlas.TITLE_MAX]u8 = undefined;
    var y = beginPane(ed, .inspector, box);
    const is = ed.scene.issues;
    heading(g, col, &y, "Problems");
    var wrong = false;
    if (is.start_walled) {
        wrong = true;
        thingRow(ed, g, col, &y, "The start is on solid ground", .{}, WARN, ed.map.start.at);
    }
    if (is.unlinked > 0) {
        wrong = true;
        thingRow(ed, g, col, &y, "{d} door(s) lead nowhere", .{is.unlinked}, WARN, null);
    }
    if (is.cut_off > 0) {
        wrong = true;
        thingRow(ed, g, col, &y, "{d} open cells no walk reaches (shaded)", .{is.cut_off}, WARN, is.reach_from);
    }
    if (is.foes_cut_off > 0) {
        wrong = true;
        thingRow(ed, g, col, &y, "{d} foe(s) no walk reaches", .{is.foes_cut_off}, WARN, null);
    }
    const endless = ed.map.script.endless();
    if (endless > 0) {
        wrong = true;
        thingRow(ed, g, col, &y, "{d} dialog(s) never end, so never open", .{endless}, WARN, null);
    }
    if (!wrong) thingRow(ed, g, col, &y, "Nothing wrong", .{}, look.DIM, null);
    y += widgets.BLOCK_GAP;
    heading(g, col, &y, if (ed.here().unrolled()) "On this roll" else "On this node");
    if (ed.scene.start_at) |s| thingRow(ed, g, col, &y, "Start  {d},{d}", .{ s.x, s.y }, look.TEXT, s);
    for (ed.here().doors(), 0..) |d, k| {
        if (d.to) |to|
            thingRow(ed, g, col, &y, "Door {d}  {d},{d}  to {s}, door {d}", .{ k, d.at.x, d.at.y, ed.nodeName(to.node, &name), to.door }, look.TEXT, d.at)
        else
            thingRow(ed, g, col, &y, "Door {d}  {d},{d}  leads nowhere", .{ k, d.at.x, d.at.y }, WARN, d.at);
    }
    for (ed.scene.shownFoes()) |f| thingRow(ed, g, col, &y, "{s}  {d},{d}", .{ editor.kindName(f.kind), f.at.x, f.at.y }, look.TEXT, f.at);
    const s = &ed.map.script;
    for (s.folks()) |f| {
        if (f.node != ed.node) continue;
        thingRow(ed, g, col, &y, "{s}  {d},{d}  talks: {s}", .{ f.called(), f.at.x, f.at.y, editor.plot.talksTo(s, &f) }, look.TEXT, f.at);
    }
    switch (ed.plan().*) {
        .bespoke => |*b| {
            for (b.torches()) |t| thingRow(ed, g, col, &y, "Torch  {d},{d}", .{ t.x, t.y }, look.TEXT, t);
            for (&b.barrel, 0..) |*on, i| {
                if (!on.*) continue;
                const p = grid.Level.of(i);
                thingRow(ed, g, col, &y, "Barrel  {d},{d}", .{ p.x, p.y }, look.TEXT, p);
            }
        },
        .procgen => {},
    }
    closePane(ed, .inspector, y);
}

pub fn clipped(ed: *const editor.Editor, y: i32) bool {
    return clippedH(ed, y, widgets.ROW_H);
}

fn clippedH(ed: *const editor.Editor, y: i32, h: i32) bool {
    const c = ed.clip orelse return false;
    const top: f32 = @floatFromInt(y);
    return top + @as(f32, @floatFromInt(h)) <= c.y or top >= c.y + c.height;
}

/// Formatted only when it shows.
fn thingRow(ed: *editor.Editor, g: *game.Game, col: Column, y: *i32, comptime fmt: []const u8, args: anytype, ink: rl.Color, at: ?P) void {
    if (clipped(ed, y.*)) {
        y.* += widgets.ROW_H;
        return;
    }
    var buf: [widgets.LINE]u8 = undefined;
    const line = std.fmt.bufPrintZ(&buf, fmt, args) catch "";
    if (widgets.flatButton(ed.controls(), &g.face, col.row(y.*), line, ink, false, at != null, false, if (at != null) "Show it on the map" else null)) ed.showCell(editor.Editor.canvas(g), at.?);
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

/// Clips to `box`, a pane's scrolled area, so nothing outside it is hot; the content's first row.
pub fn beginPane(ed: *editor.Editor, p: editor.Pane, box: rl.Rectangle) i32 {
    return ed.paneScroll(p, box).begin(&ed.clip);
}

/// The pane's content ran to `end`: stops clipping, then how far it scrolls, and its bar.
pub fn closePane(ed: *editor.Editor, p: editor.Pane, end: i32) void {
    ed.paneScroll(p, ed.pane.get(p).box).close(&ed.clip, end, widgets.PAD);
}

pub fn drawStatus(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle) void {
    var buf: [widgets.LINE + 1]u8 = undefined;
    var state_buf: [widgets.LINE + 1]u8 = undefined;
    var path_buf: [widgets.LINE]u8 = undefined;
    const top = editor.Editor.bandOf(g.screen).bottom;
    rl.drawRectangle(0, top, g.screen.x, editor.STATUS_H, PANEL_BG);
    rl.drawRectangle(0, top, g.screen.x, 1, look.EDGE);
    const x = widgets.PAD;
    const w = g.screen.x - 2 * widgets.PAD;
    const face = widgets.textFace(&g.face);
    var y = top + widgets.GAP;
    const state = toolState(ed, &state_buf);
    const state_w = face.width(state, widgets.TEXT);
    widgets.drawFit(&g.face, hover(ed, c, &buf), widgets.TEXT, w - state_w - widgets.BLOCK_GAP, false, x, y, look.TEXT);
    face.draw(state, x + w - state_w, y, widgets.TEXT, look.DIM);
    y += widgets.LINE_STEP;
    const file = std.fmt.bufPrintZ(&path_buf, "{s}{s}", .{ ed.path(), if (ed.history.dirty) " *" else "" }) catch "";
    const file_w = @min(face.width(file, widgets.TEXT), @divTrunc(w, 3));
    widgets.drawFit(&g.face, file, widgets.TEXT, file_w, true, x + w - file_w, y, if (ed.history.dirty) look.UI_GOLD else look.DIM);
    const said = ed.said_t > 0;
    const line: []const u8 = if (said) ed.said.text() else if (ed.view == .map) editor.CRIB_MAP else editor.CRIB_GRAPH;
    widgets.drawFit(&g.face, line, widgets.TEXT, w - file_w - widgets.BLOCK_GAP, false, x, y, if (said) look.UI_FOCUS else look.DIM);
}

fn toolState(ed: *const editor.Editor, buf: []u8) [:0]const u8 {
    const px: i32 = @intFromFloat(ed.px());
    if (ed.pasting) return std.fmt.bufPrintZ(buf, "Pasting {d}x{d}" ++ SEP ++ "{d} px", .{ ed.board.size.x, ed.board.size.y, px }) catch "";
    if (ed.shape == .select) return std.fmt.bufPrintZ(buf, "Select" ++ SEP ++ "{d} px", .{px}) catch "";
    const n = ed.brushSize();
    if (ed.tool.broad()) return std.fmt.bufPrintZ(buf, "{s} / {s}" ++ SEP ++ "{s} {d}x{d}" ++ SEP ++ "{d} px", .{ @tagName(ed.ink.get(.first)), @tagName(ed.ink.get(.second)), menu.named(ed.shape), n, n, px }) catch "";
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
