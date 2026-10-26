const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const raster = @import("../gfx/raster.zig");
const editor = @import("editor.zig");
const placement = @import("placement.zig");
const widgets = @import("widgets.zig");
const modals = @import("modals.zig");
const text_panel = @import("text_panel.zig");
const Editor = editor.Editor;
const Desk = input.Desk;
const P = mathx.P;

const PAN_PX_S: f32 = 900;
const DRAG_PX: i32 = 4;

pub fn step(ed: *Editor, bounds: rl.Rectangle, screen_height: i32, dt: f32) void {
    const desk = &ed.desk;
    ed.said_t -= dt;
    ed.flash_t -= dt;
    if (ed.action != .none) return;
    if (ed.modal != .none) {
        modalKeys(ed);
        if (ed.modal == .none) ed.fresh = true;
        return;
    }
    const over_canvas = ed.mouseIn(bounds);
    if (ed.renaming) {
        ed.field.feed(desk);
        if (desk.back or desk.enter or desk.clicked()) {
            if (desk.back) ed.renaming = false else ed.commitRename();
            ed.renamed = desk.clicked();
        }
        if (ed.renaming or !desk.clicked() or over_canvas) return;
    } else if (desk.back) {
        escape(ed);
        if (desk.clicked()) ed.gesture();
        return;
    }
    if (desk.play) ed.playStart();
    if (desk.play_here) playHere(ed, bounds, over_canvas);
    if (ed.action != .none) return;
    const view = ed.view;
    const node = ed.node;
    shortcuts(ed, bounds, over_canvas);
    if (desk.erase_hit and (ed.drag != null or ed.linking != null)) return ed.drop();
    if (ed.modal != .none or ed.renaming) return;
    if (ed.popup) |pp| {
        if (desk.clicked() and !ed.mouseIn(editor.popupRect(pp, screen_height))) {
            ed.popup = null;
            ed.fresh = true;
        } else if (desk.clicked()) ed.gesture();
        return;
    }
    if (desk.clicked()) ed.gesture();
    if (desk.clicked() and (ed.view != view or ed.node != node)) return;
    moveViewport(ed, bounds, over_canvas, dt);
    scrollPanel(ed);
}

fn shortcuts(ed: *Editor, bounds: rl.Rectangle, over_canvas: bool) void {
    const desk = &ed.desk;
    if (desk.save) _ = ed.save();
    if (desk.save_as) ed.askName(.save_as);
    if (desk.open) ed.askOpen();
    if (desk.new) ed.askName(.new);
    if (desk.help) ed.ask(.help);
    if (desk.objects) ed.ask(.objects);
    if (desk.undo) ed.undo();
    if (desk.redo) ed.redo();
    if (desk.graph) ed.setView(ed.view.other());
    if (desk.rename) ed.startRename();
    if (desk.go) goThrough(ed, bounds, over_canvas);
    if (desk.reroll) editor.reroll(ed);
    if (desk.smaller) ed.stepBrush(-1);
    if (desk.bigger) ed.stepBrush(1);
    if (desk.tool) |i| ed.setTool(editor.TOOLS[i]);
    if (desk.shape) |i| ed.setShape(editor.SHAPES[i]);
    if (ed.view == .map) {
        if (desk.fit) fitView(ed, bounds);
        if (desk.zoom_in or desk.zoom_out) zoom(ed, bounds, if (desk.zoom_in) 1 else -1, raster.middleAt(bounds));
        if (desk.copy) placement.copySelection(ed, false);
        if (desk.cut) placement.copySelection(ed, true);
        if (desk.delete) placement.clearSelection(ed);
        if (desk.paste) placement.startPaste(ed);
    }
}

fn moveViewport(ed: *Editor, bounds: rl.Rectangle, over_canvas: bool, dt: f32) void {
    const desk = &ed.desk;
    switch (ed.view) {
        .map => {
            panBy(&ed.cam, desk, dt, ed.px());
            if (desk.wheel != 0 and over_canvas) zoom(ed, bounds, -notch(desk), desk.mouse);
            mapMouse(ed, bounds, over_canvas);
            if (desk.fullscreen) ed.stroke_at = null;
        },
        .graph => {
            panBy(&ed.gcam, desk, dt, 1);
            graphMouse(ed, bounds, over_canvas);
        },
    }
}

fn scrollPanel(ed: *Editor) void {
    const desk = &ed.desk;
    if (desk.wheel != 0 and desk.mouse.x < widgets.PANEL_W and desk.mouse.y >= ed.lower_top) {
        if (ed.lower == .tools or ed.lower == .things or ed.generator() != null) {
            ed.gen_top = std.math.clamp(ed.gen_top + notch(desk) * widgets.ROW_H, 0, ed.gen_most);
        } else scrollNodes(ed, notch(desk));
    }
}

fn notch(d: *const Desk) i32 {
    return if (d.wheel > 0) -1 else if (d.wheel < 0) 1 else 0;
}

fn scrollTop(top: usize, by: i32, n: usize, rows: usize) usize {
    return mathx.nudge(top, by, (n -| rows) + 1);
}

/// `px` screen pixels a unit of `cam`.
fn panBy(cam: *[2]f32, d: *const Desk, dt: f32, px: f32) void {
    const pan = [2]f32{ @floatFromInt(d.pan.x), @floatFromInt(d.pan.y) };
    const moved = [2]f32{ @floatFromInt(d.moved.x), @floatFromInt(d.moved.y) };
    for (0..2) |k| {
        cam[k] += pan[k] * PAN_PX_S * dt / px;
        if (d.grab) cam[k] -= moved[k] / px;
    }
}

pub fn escape(ed: *Editor) void {
    if (ed.holding()) {
        ed.drop();
    } else if (ed.pasting) {
        ed.putAwayPaste();
    } else if (ed.pick != null) {
        ed.pick = null;
        ed.say(placement.LINK_CANCELLED, .{});
    } else if (ed.delete_armed != null) {
        ed.delete_armed = null;
    } else if (ed.selection != null) {
        ed.selection = null;
    } else if (ed.view == .graph) {
        ed.setView(.map);
    } else ed.request(.leave);
}

pub fn modalKeys(ed: *Editor) void {
    if (ed.modal == .text) return text_panel.keys(ed);
    const d = &ed.desk;
    if (d.erase_hit) {
        ed.modal = .none;
        return;
    }
    if (ed.modal == .open and (d.back or d.rub) and ed.listing.up()) return ed.showListing();
    if (d.back) {
        ed.modal = .none;
        return;
    }
    switch (ed.modal) {
        .confirm => if (d.enter and ed.save()) ed.commit(),
        .name => {
            ed.field.feed(d);
            if (d.enter) ed.named();
        },
        .open => {
            if (d.wheel != 0) ed.listed_top = scrollTop(ed.listed_top, notch(d), ed.listing.n, widgets.MODAL_ROWS);
            if (d.nav != 0 and ed.listing.n > 0) {
                ed.listed_at = mathx.wrap(ed.listed_at, d.nav, ed.listing.n);
                ed.listed_top = mathx.reveal(ed.listed_top, ed.listed_at, widgets.MODAL_ROWS);
            }
            if (d.enter and ed.listed_at < ed.listing.n) ed.openListed(ed.listed_at);
        },
        .objects => {
            if (d.nav != 0) ed.seen_at = mathx.wrap(ed.seen_at, d.nav, editor.SEEN.len);
            if (d.enter) modals.fightSeen(ed);
        },
        .help, .none, .text => {},
    }
}

fn playHere(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const p = ed.mouseCell(c);
    if (ed.view != .map or !grid.Level.inside(p) or !over) {
        return ed.say("{s} plays from the cell under the cursor on a map", .{Desk.PLAY_HERE_CAPTION});
    }
    ed.action = .{ .play = .{ .node = ed.node, .at = p } };
}

pub fn armCellAction(ed: *Editor, action: editor.CellAction) void {
    ed.release();
    ed.setView(.map);
    ed.cell_action = action;
    ed.say("{s} {s}; {s} cancels", .{
        Desk.PAINT_CAPTION,
        if (action == .play) "a cell to play there" else "a linked door to go through",
        Desk.ERASE_CAPTION,
    });
}

fn goThrough(ed: *Editor, c: rl.Rectangle, over: bool) void {
    if (ed.view != .map) return;
    const door = if (over) ed.doorAt(ed.mouseCell(c)) else null;
    const k = door orelse return ed.say("{s} goes through the door under the cursor", .{Desk.GO_CAPTION});
    const to = ed.here().door[k].to orelse return ed.say("Door {d} leads nowhere yet", .{k});
    ed.select(to.node);
    ed.recentre = false;
    ed.lookAt(c, ed.map.door(to).at);
    var buf: [atlas.TITLE_MAX]u8 = undefined;
    ed.say("Through door {d} to {s}, door {d}", .{ k, ed.nodeName(to.node, &buf), to.door });
}

pub fn mapMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const d = &ed.desk;
    const p = ed.mouseCell(c);
    if (ed.cell_action) |action| {
        if (d.erase_hit or (d.paint_hit and !over)) {
            ed.cell_action = null;
        } else if (d.paint_hit and over) {
            ed.cell_action = null;
            switch (action) {
                .play => playHere(ed, c, over),
                .go => goThrough(ed, c, over),
            }
        }
        return;
    }
    if (ed.pasting) {
        if (over and d.paint_hit) {
            if (ed.paintable()) placement.layBoard(ed, p) else ed.say(editor.GENERATED, .{});
        }
        if (over and d.erase_hit) ed.putAwayPaste();
        return;
    }
    const held = switch (ed.stroke) {
        .none => d.paint or d.erase,
        .paint => d.paint,
        .erase => d.erase,
    };
    if (!held) {
        if (ed.span) |s| {
            placement.laySpan(ed, s, grid.Level.clamp(p));
            if (d.clicked()) ed.gesture();
        }
        ed.letGo();
    }
    if (over and d.clicked()) {
        ed.letGo();
        const second = !d.paint_hit;
        if (d.alt) return placement.pickUp(ed, p, second);
        ed.stroke = if (second) .erase else .paint;
        if (placement.spanOf(ed, d.shift)) |s| {
            ed.span = .{ .from = grid.Level.clamp(p), .erase = second, .shape = s };
            return;
        }
        if (ed.shape == .fill and ed.tool.broad()) {
            ed.stroke = .none;
            if (!ed.tool.fits(ed.here())) return ed.say(editor.GENERATED, .{});
            if (grid.Level.inside(p)) placement.fill(ed, p, second);
            return;
        }
    } else if (d.clicked() and ed.span == null) ed.letGo();
    if (!over) ed.stroke_at = null;
    if (ed.span != null or !over or ed.stroke == .none) return;
    const hit = if (ed.stroke == .paint) d.paint_hit else d.erase_hit;
    if (!hit and !ed.tool.strokes()) return;
    if (!ed.tool.fits(ed.here())) {
        if (hit and grid.Level.inside(p)) ed.say(editor.GENERATED, .{});
        return;
    }
    if (hit or ed.stroke_at == null) {
        if (grid.Level.inside(p)) placement.brushAt(ed, p);
    } else {
        var ray = grid.Ray.init(ed.stroke_at.?, p);
        while (ray.next()) |q| {
            if (grid.Level.inside(q)) placement.brushAt(ed, q);
        }
    }
    ed.stroke_at = p;
}

pub fn graphMouse(ed: *Editor, c: rl.Rectangle, over: bool) void {
    const d = &ed.desk;
    if (ed.linking) |from| {
        if (d.paint) return;
        ed.linking = null;
        const to = (if (over) ed.dotUnder(c, d.mouse) else null) orelse return ed.say(placement.LINK_CANCELLED, .{});
        return placement.linkDoors(ed, from, to);
    }
    if (over and d.erase_hit) {
        if (ed.dotUnder(c, d.mouse)) |l| {
            if (ed.map.door(l).to == null) return;
            ed.map.unlink(l);
            ed.relinked();
            return ed.say("Node {d} door {d} unlinked", .{ l.node, l.door });
        }
    }
    if (over and d.paint_hit) {
        if (ed.dotUnder(c, d.mouse)) |l| {
            ed.linking = l;
            return ed.say(placement.LINKING ++ "let go on the door it leads to", .{ l.node, l.door });
        }
        if (ed.boxUnder(c, d.mouse)) |n| {
            const was = ed.map.node[n].pos;
            ed.drag = .{ .node = n, .from = d.mouse, .grab = graphAt(ed, c, d.mouse).sub(was) };
        }
    }
    const dr = if (ed.drag) |*x| x else return;
    if (d.paint) {
        if (!dr.moved and mathx.dist(d.mouse, dr.from) > DRAG_PX) dr.moved = true;
        if (!dr.moved) return;
        ed.history.transaction.previewNode(ed.map, dr.node, atlas.clampPos(graphAt(ed, c, d.mouse).sub(dr.grab)));
        return;
    }
    if (!dr.moved) {
        const n = dr.node;
        ed.drag = null;
        return ed.goTo(n);
    }
    ed.keepDrag();
}

/// The graph's place under the screen point `m`.
fn graphAt(ed: *const Editor, c: rl.Rectangle, m: P) P {
    return m.sub(.{ .x = @intFromFloat(c.x), .y = @intFromFloat(c.y) }).add(.{ .x = @intFromFloat(ed.gcam[0]), .y = @intFromFloat(ed.gcam[1]) });
}

/// `anchor` stays over the same cell.
fn zoom(ed: *Editor, c: rl.Rectangle, by: i32, anchor: P) void {
    const m = [2]f32{ @as(f32, @floatFromInt(anchor.x)) - c.x, @as(f32, @floatFromInt(anchor.y)) - c.y };
    const was = ed.px();
    ed.zoom = mathx.nudge(ed.zoom, by, editor.ZOOMS.len);
    for (0..2) |k| ed.cam[k] += m[k] / was - m[k] / ed.px();
    ed.stroke_at = null;
}

pub fn fitView(ed: *Editor, c: rl.Rectangle) void {
    ed.zoom = 0;
    for (editor.ZOOMS, 0..) |z, i| {
        if (@as(f32, grid.W) * z <= c.width and @as(f32, grid.H) * z <= c.height) ed.zoom = i;
    }
    ed.lookAt(c, grid.MIDDLE);
    ed.stroke_at = null;
}

fn scrollNodes(ed: *Editor, by: i32) void {
    ed.scroll = scrollTop(ed.scroll, by, ed.map.node_n, ed.node_rows);
}
