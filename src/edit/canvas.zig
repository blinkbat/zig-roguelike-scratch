const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const look = @import("../gfx/look.zig");
const dual = @import("../gfx/ground.zig");
const game = @import("../game.zig");
const modals = @import("modals.zig");
const panel = @import("panel.zig");
const editor = @import("editor.zig");
const P = mathx.P;
const Desk = input.Desk;
const PANEL_BG = look.EDIT_PANEL;
const ON = look.EDIT_ON;
const HOVER = look.EDIT_HOVER;
const PICKED = look.EDIT_PICKED;
const UNLINKED = look.EDIT_UNLINKED;
const WARN = look.EDIT_WARN;
const vec = look.vec;

pub fn visible(ed: *const editor.Editor, c: rl.Rectangle) grid.Box {
    const lo = mathx.P{ .x = @min(grid.W, @max(0, @as(i32, @intFromFloat(@floor(ed.cam[0]))))), .y = @min(grid.H, @max(0, @as(i32, @intFromFloat(@floor(ed.cam[1]))))) };
    return .{ .lo = lo, .hi = .{
        .x = @max(lo.x, @min(grid.W, @as(i32, @intFromFloat(@ceil(ed.cam[0] + c.width / ed.px()))) + 1)),
        .y = @max(lo.y, @min(grid.H, @as(i32, @intFromFloat(@ceil(ed.cam[1] + c.height / ed.px()))) + 1)),
    } };
}

fn drawCells(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle, v: grid.Box) void {
    var beds: dual.Beds = undefined;
    beds.fill(&ed.lv, v.lo, v.hi, false);
    g.sprites.drawGround(&beds, ed.origin(c), ed.px(), null);
    var cells = grid.Cells.of(v.lo, v.hi);
    while (cells.next()) |p| {
        const r = ed.cellRect(c, p);
        const here = ed.lv.at(p);
        if (look.glyphGround(here, &g.sprites)) editor.tileGlyph(g, here, r);
        if (!look.standsOver(here)) continue;
        if (g.sprites.tileAt(&ed.lv, p)) |t| {
            editor.sprite(t, r);
            continue;
        }
        if (look.tileBg(here) orelse if (here == .wall) look.BARE_WALL else null) |bg| rl.drawRectangleRec(r, bg);
        if (here != .wall) editor.tileGlyph(g, here, r);
    }
}

pub fn drawMap(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle) void {
    editor.scissor(c);
    defer rl.endScissorMode();
    const v = visible(ed, c);
    drawCells(ed, g, c, v);
    if (ed.lower == .things and ed.issues.cut_off > 0) {
        var cells = grid.Cells.of(v.lo, v.hi);
        while (cells.next()) |p| {
            if (ed.cutOff(grid.Level.idx(p))) rl.drawRectangleRec(ed.cellRect(c, p), CUT_OFF);
        }
    }
    if (ed.px() >= GRID_PX) drawGrid(ed, c, v);
    rl.drawRectangleLinesEx(look.grown(boxRect(ed, c, grid.Box.inMap(0)), 1), 1, look.EDGE);
    var cells = grid.Cells.of(v.lo, v.hi);
    while (cells.next()) |p| {
        if (ed.lv.hasBarrel(p)) modals.seenPicture(g, .barrel, ed.cellRect(c, p));
    }
    for (ed.lv.torches()) |t| modals.seenPicture(g, .torch, ed.cellRect(c, t));
    for (ed.shownFoes()) |f| modals.seenPicture(g, .{ .body = f.kind }, ed.cellRect(c, f.at));
    drawDoors(ed, g, c);
    if (ed.start_at) |s| panel.toolFigure(g, .start, ed.cellRect(c, s));
    if (ed.selection) |s| {
        outlineCells(ed, c, s, PICKED);
        fillCells(ed, c, s, SELECTED);
    }
    if (ed.flash_t > 0) {
        if (ed.flash) |p| {
            const r = ed.cellRect(c, p);
            rl.drawRectangleLinesEx(look.grown(r, FLASH_PX), PICK_EDGE, look.UI_FOCUS);
        }
    }
    drawCursor(ed, g, c);
    if (ed.here().unrolled()) plaque(g, c, "One roll of this node (" ++ Desk.REROLL_CAPTION ++ " rolls another); play rolls it afresh each run");
}

const GRID_PX: f32 = 32;
const FLASH_PX: f32 = 4;
const GHOST_A: f32 = 0.5;
const GHOST = look.fade(look.LIT, GHOST_A);
const CUT_OFF = look.fade(WARN, 0.35);
const SELECTED = look.fade(PICKED, 0.15);
const GRID_INK = look.fade(look.EDGE, 0.35);
const DOOR_BACK = look.fade(look.BG, 0.55);
const PLAQUE_BG = look.fade(PANEL_BG, 0.85);
pub const INK_EDGE: f32 = 2;
const PICK_EDGE: f32 = 3;

fn drawGrid(ed: *const editor.Editor, c: rl.Rectangle, v: grid.Box) void {
    const lo = ed.cellRect(c, v.lo);
    const hi = ed.cellRect(c, v.hi);
    var x = v.lo.x;
    while (x <= v.hi.x) : (x += 1) {
        const at = ed.cellRect(c, .{ .x = x, .y = v.lo.y }).x;
        rl.drawLineV(.{ .x = at, .y = lo.y }, .{ .x = at, .y = hi.y }, GRID_INK);
    }
    var y = v.lo.y;
    while (y <= v.hi.y) : (y += 1) {
        const at = ed.cellRect(c, .{ .x = v.lo.x, .y = y }).y;
        rl.drawLineV(.{ .x = lo.x, .y = at }, .{ .x = hi.x, .y = at }, GRID_INK);
    }
}

fn drawDoors(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle) void {
    var buf: [8]u8 = undefined;
    for (ed.here().doors(), 0..) |d, k| {
        const r = ed.cellRect(c, d.at);
        rl.drawRectangleRec(r, DOOR_BACK);
        editor.glyph(g, look.DOOR.ch, r, if (d.to == null) UNLINKED else look.DOOR.fg);
        rl.drawRectangleLinesEx(r, 1, if (d.to == null) WARN else look.DOOR.fg);
        if (ed.px() >= editor.LABEL_PX) {
            const label = std.fmt.bufPrintZ(&buf, "{d}", .{k}) catch "";
            editor.drawTag(g, label, .{ .x = @intFromFloat(r.x), .y = @intFromFloat(r.y) }, editor.LABEL_PAD, PANEL_BG, null);
        }
        const pk = ed.pick orelse continue;
        if (pk.eq(.{ .node = ed.node, .door = k })) rl.drawRectangleLinesEx(r, PICK_EDGE, PICKED);
    }
}

fn drawCursor(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle) void {
    const m = ed.mouseCell(c);
    if (ed.pasting) {
        if (!ed.mouseIn(c)) return;
        const bd = &ed.board;
        const view = visible(ed, c);
        const lays = ed.paintable();
        if (lays) _ = editor.layAside(ed, m);
        const trial = &ed.trial;
        var cells = bd.box(.{ .x = 0, .y = 0 }).cells();
        while (cells.next()) |q| {
            const p = m.add(q);
            const k = bd.at(q);
            if (!view.holds(p)) continue;
            ghostInk(ed, g, c, p, bd.tile[k]);
            if (!bd.barrel[k]) continue;
            const i = grid.Level.idx(p);
            ghostPasted(ed, g, c, p, .barrel, lays and trial.barrel[i]);
        }
        for (bd.torch.slice()) |t| {
            const p = m.add(t);
            if (view.holds(p)) ghostPasted(ed, g, c, p, .torch, lays and trial.torch.has(p));
        }
        for (bd.foe[0..bd.foe_n]) |f| {
            const p = m.add(f.at);
            const there = if (lays) trial.foeAt(p) else null;
            if (view.holds(p)) ghostPasted(ed, g, c, p, .{ .foe = f.kind }, if (there) |i| trial.foe[i].kind == f.kind else false);
        }
        outlineCells(ed, c, bd.box(m), if (lays) PICKED else WARN);
        return;
    }
    if (ed.span) |s| {
        const to = grid.Level.clamp(m);
        editor.eachSpanCell(ed, s, to, editor.Ghost.of(ed, g, c, ed.ink.get(.of(s.erase))));
        outlineCells(ed, c, grid.Box.between(s.from, to), PICKED);
        return;
    }
    if (!grid.Level.inside(m) or !ed.mouseIn(c)) return;
    if (ed.shape == .select or (ed.desk.alt and ed.stroke == .none)) return outlineCells(ed, c, editor.brushBox(m, 1), PICKED);
    const erase = if (ed.stroke == .none) ed.desk.erase else ed.stroke == .erase;
    if (ed.tool.broad()) {
        const ghost = editor.Ghost.of(ed, g, c, ed.ink.get(.of(erase)));
        const begins = if (ed.stroke == .none) editor.spanOf(ed, ed.desk.shift) else null;
        if (begins) |sh| {
            editor.eachSpanCell(ed, .{ .from = m, .erase = erase, .shape = sh }, m, ghost);
            return outlineCells(ed, c, editor.brushBox(m, if (sh == .line) ed.brushSize() else 1), HOVER);
        }
        if (ed.shape != .fill) editor.eachBrushCell(ed, m, ghost);
        return outlineCells(ed, c, editor.brushBox(m, if (ed.shape == .fill) 1 else ed.brushSize()), if (ed.tool.fits(ed.here())) HOVER else WARN);
    }
    const r = ed.cellRect(c, m);
    const ok = if (erase) editor.removable(ed, m) else editor.legal(ed, m);
    if (!erase) ghostTool(g, r, ed.tool);
    rl.drawRectangleLinesEx(r, INK_EDGE, if (ok) HOVER else WARN);
    if (!ok) rl.drawRectangleRec(r, CUT_OFF);
}

fn ghostPasted(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle, p: P, tool: editor.Tool, lands: bool) void {
    const r = ed.cellRect(c, p);
    ghostTool(g, r, tool);
    if (!lands) rl.drawRectangleRec(r, CUT_OFF);
}

fn ghostTool(g: *game.Game, r: rl.Rectangle, tool: editor.Tool) void {
    if (panel.toolPicture(g, tool)) |t| return look.stretch(t, r, GHOST);
    const l = tool.look_();
    editor.glyph(g, l.ch, r, look.fade(l.fg, GHOST_A));
}

pub fn ghostInk(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle, p: P, t: grid.Tile) void {
    const r = ed.cellRect(c, p);
    if (ed.paintable() and ed.doorAt(p) == null) ghostTile(g, t, r) else rl.drawRectangleRec(r, CUT_OFF);
}

fn ghostTile(g: *game.Game, t: grid.Tile, r: rl.Rectangle) void {
    if (g.sprites.tileOf(t, .{})) |tex| return look.stretch(tex, r, GHOST);
    rl.drawRectangleRec(r, look.fade(panel.bareBg(t), GHOST_A));
}

fn boxRect(ed: *const editor.Editor, c: rl.Rectangle, b: grid.Box) rl.Rectangle {
    const lo = ed.cellRect(c, b.lo);
    const hi = ed.cellRect(c, b.hi);
    return .{ .x = lo.x, .y = lo.y, .width = hi.x - lo.x, .height = hi.y - lo.y };
}

fn fillCells(ed: *const editor.Editor, c: rl.Rectangle, b: grid.Box, col: rl.Color) void {
    rl.drawRectangleRec(boxRect(ed, c, b), col);
}

fn plaque(g: *game.Game, c: rl.Rectangle, s: [:0]const u8) void {
    editor.drawTag(g, s, .{ .x = @as(i32, @intFromFloat(c.x)) + editor.GAP, .y = @as(i32, @intFromFloat(c.y)) + editor.GAP }, editor.GAPS, PLAQUE_BG, null);
}

fn outlineCells(ed: *const editor.Editor, c: rl.Rectangle, b: grid.Box, col: rl.Color) void {
    rl.drawRectangleLinesEx(boxRect(ed, c, b), 1, col);
}

pub fn drawGraph(ed: *editor.Editor, g: *game.Game, c: rl.Rectangle) void {
    editor.scissor(c);
    defer rl.endScissorMode();
    for (0..ed.map.node_n) |n| {
        const b = ed.boxAt(c, n);
        rl.drawRectangleRec(b, PANEL_BG);
        const picture = thumbRect(b);
        if (thumb(ed, n, picture, c)) |t| editor.sprite(t, picture);
        panel.drawNodeTitle(ed, g, n, b, @as(i32, @intFromFloat(b.y)) + editor.TITLE_DY);
        rl.drawRectangleLinesEx(b, 1, if (n == ed.node) ON else look.EDGE);
    }
    for (ed.map.nodes(), 0..) |*nd, n| {
        for (nd.doors(), 0..) |d, k| {
            const here = atlas.Link{ .node = n, .door = k };
            const at = ed.dotAt(c, here);
            const to = d.to orelse {
                rl.drawCircleV(at, editor.DOT_R, WARN);
                continue;
            };
            if (to.node > n or (to.node == n and to.door > k)) rl.drawLineEx(at, ed.dotAt(c, to), editor.LINK_W, look.DOOR.fg);
            rl.drawCircleV(at, editor.DOT_R, look.DOOR.fg);
        }
    }
    if (ed.dotUnder(c, ed.desk.mouse)) |l| rl.drawCircleLinesV(ed.dotAt(c, l), editor.DOT_R + editor.DOT_SLOP, look.UI_FOCUS);
    if (ed.linking) |from| rl.drawLineEx(ed.dotAt(c, from), vec(ed.desk.mouse), editor.LINK_W, PICKED);
}

fn thumbRect(b: rl.Rectangle) rl.Rectangle {
    return .{ .x = b.x, .y = b.y + @as(f32, @floatFromInt(editor.BOX_TOP)), .width = @floatFromInt(editor.BOX_W), .height = @floatFromInt(editor.BOX_H - editor.BOX_TOP) };
}

fn thumb(ed: *editor.Editor, n: usize, picture: rl.Rectangle, canvas: rl.Rectangle) ?rl.Texture2D {
    if (!rl.checkCollisionRecs(picture, canvas)) return null;
    if (!ed.thumb_ok.isSet(n)) {
        const lv = if (n == ed.node and !ed.stale) &ed.lv else blk: {
            ed.map.node[n].stamp(&ed.thumb_lv, ed.roll);
            break :blk &ed.thumb_lv;
        };
        var px: [grid.CELLS]rl.Color = undefined;
        for (&px, 0..) |*c, i| {
            c.* = if (look.Mark.of(lv, i)) |m|
                m.look().fg
            else if (if (lv.wallShape(grid.Level.of(i))) |s| s.solid() else false)
                look.BG
            else
                look.mini(lv.tile[i], true);
        }
        if (ed.thumbs[n] == null) {
            ed.thumbs[n] = look.canvas(grid.W, grid.H, look.BG, .point);
        }
        if (ed.thumbs[n]) |t| rl.updateTexture(t, &px);
        ed.thumb_ok.set(n);
    }
    return ed.thumbs[n];
}

test "offscreen graph thumbnails defer generation and uploads until their image enters the canvas" {
    const ed = try editor.Editor.create(std.testing.allocator);
    defer ed.destroy();
    while (ed.map.node_n < atlas.MAX_NODES) _ = ed.map.add(.{ .procgen = .{} });
    const c = look.rect(editor.PANEL_W, 0, 640, 480);
    ed.gcam = .{ 10000, 10000 };
    for (0..ed.map.node_n) |n| {
        try std.testing.expect(thumb(ed, n, thumbRect(ed.boxAt(c, n)), c) == null);
        try std.testing.expect(ed.thumbs[n] == null and !ed.thumb_ok.isSet(n));
    }
    ed.gcam = .{ 0, 0 };
    const b = ed.boxAt(c, 0);
    const picture = thumbRect(b);
    var header = b;
    header.height = editor.BOX_TOP;
    try std.testing.expect(thumb(ed, 0, picture, header) == null);
    try std.testing.expect(ed.thumbs[0] == null and !ed.thumb_ok.isSet(0));
    ed.thumbs[0] = .{ .id = 0, .width = grid.W, .height = grid.H, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    defer ed.thumbs[0] = null;
    ed.thumb_ok.set(0);
    var edge = picture;
    edge.x += edge.width;
    try std.testing.expect(thumb(ed, 0, picture, edge) == null);
    edge.x -= 1;
    try std.testing.expect(thumb(ed, 0, picture, edge) != null);
    try std.testing.expect(thumb(ed, 0, picture, c) != null);
    std.debug.print("graph thumbnails: {d} offscreen dirty nodes skip generation and uploads; header-only and exact-edge clips skip, one visible pixel retains the image\n", .{ed.map.node_n});
}
