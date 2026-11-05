const std = @import("std");
const rl = @import("raylib");
const font = @import("../gfx/font.zig");
const prompt_text = @import("../gfx/prompt_text.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const listing = @import("../map/listing.zig");
const SHIFT_STEP = @import("tool_catalog.zig").SHIFT_STEP;
const P = mathx.P;

/// The brush panel down the left.
pub const SIDE_W: i32 = 360;
/// The node's panel down the right; the generator's rows are laid to it.
pub const INSPECT_W: i32 = 420;
pub const PAD: i32 = 12;
pub const ROW_H: i32 = 34;
pub const GAP: i32 = 6;
/// The two rows of the bar along the top.
pub const TOP_H: i32 = GAP + 2 * (ROW_H + GAP);
pub const SECTION_GAP: i32 = GAP * 3;
pub const BLOCK_GAP: i32 = GAP * 2;
pub const ROW_STEP: i32 = ROW_H + GAP;
pub const TEXT: i32 = font.HEAD;
pub const DETAIL: i32 = font.BODY;
pub const HEAD: i32 = 32;
pub const LINE_STEP: i32 = TEXT + GAP;
pub const HEADING_H: i32 = DETAIL + GAP;
pub const TEXT_DY: i32 = @divTrunc(ROW_H - TEXT, 2);
pub const DETAIL_DY: i32 = @divTrunc(ROW_H - DETAIL, 2);
pub const INSPECT_INNER_W: i32 = INSPECT_W - PAD * 2;
pub const LINE: usize = 200;
pub const MODAL_W: i32 = 720;
pub const MODAL_HEAD: i32 = PAD + HEAD + PAD;
pub const MODAL_ROWS: usize = 12;
const MODAL_BTN_W: i32 = 180;
const PAGE_W: i32 = 1800;
const PAGE_H: i32 = 1080;
pub const STEP_W: i32 = 30;
pub const STEP_PITCH: i32 = STEP_W + GAP;
pub const DROP = "x";
pub const SCROLL_W: i32 = 3;
const THUMB_MIN: f32 = 24;
const GLYPH_OF_CELL: f32 = @as(f32, @floatFromInt(look.GLYPH_PX)) / @as(f32, @floatFromInt(look.SPRITE_PX));
pub const PANEL_BG = look.EDIT_PANEL;
pub const ROW_ON = look.EDIT_ROW_ON;
pub const ON = look.EDIT_ON;
pub const HOVER = look.EDIT_HOVER;
pub const LIVE_FILL = look.fade(ROW_ON, 0.5);
const DEAD_FILL = look.fade(ROW_ON, 0.2);
pub const LIVE_EDGE = look.fade(look.EDGE, 0.85);
const DEAD_EDGE = look.fade(look.EDGE, 0.35);

pub const Controls = struct {
    pointer: P,
    pressed: bool,
    accepting: bool,
    covered: bool,
    clip: ?rl.Rectangle,
    tip: *?[:0]const u8,
};

pub fn textFace(face: *const font.Face) prompt_text.Face {
    return .{ .face = face };
}

/// Modals disable underlying hits; opening one suppresses its own first-frame hits.
pub fn hot(controls: Controls, r: rl.Rectangle, live: bool, modal: bool, tip: ?[:0]const u8) struct { hot: bool, hit: bool } {
    const on_layer = controls.accepting and (modal or !controls.covered);
    const in_clip = if (controls.clip) |c| raster.holds(c, controls.pointer) else true;
    const hovered = on_layer and in_clip and raster.holds(r, controls.pointer);
    if (hovered and tip != null) controls.tip.* = tip;
    return .{ .hot = live and hovered, .hit = live and hovered and controls.pressed };
}

pub fn button(controls: Controls, face: *const font.Face, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return buttonOn(controls, face, r, label, on, live, false, tip);
}

pub fn modalButton(controls: Controls, face: *const font.Face, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return buttonOn(controls, face, r, label, on, live, true, tip);
}

pub fn buttonOn(controls: Controls, face: *const font.Face, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, modal: bool, tip: ?[:0]const u8) bool {
    return buttonSized(controls, face, r, label, TEXT, on, live, modal, tip);
}

/// Its label `size` pixels high.
pub fn buttonSized(controls: Controls, face: *const font.Face, r: rl.Rectangle, label: [:0]const u8, size: i32, on: bool, live: bool, modal: bool, tip: ?[:0]const u8) bool {
    const h = hot(controls, r, live, modal, tip);
    buttonBack(r, live);
    plate(r, on, h.hot);
    drawFit(face, label, size, insetW(r), false, textX(r), midY(r, size), if (live) look.TEXT else look.DIM);
    return h.hit;
}

pub fn buttonBack(r: rl.Rectangle, live: bool) void {
    rl.drawRectangleRec(r, if (live) LIVE_FILL else DEAD_FILL);
    rl.drawRectangleLinesEx(r, 1, if (live) LIVE_EDGE else DEAD_EDGE);
}

/// A row of `r`, with no frame of its own, its label `ink`.
pub fn flatButton(controls: Controls, face: *const font.Face, r: rl.Rectangle, label: []const u8, ink: rl.Color, on: bool, live: bool, modal: bool, tip: ?[:0]const u8) bool {
    const h = hot(controls, r, live, modal, tip);
    plate(r, on, h.hot);
    drawFit(face, label, DETAIL, insetW(r), false, textX(r), @as(i32, @intFromFloat(r.y)) + DETAIL_DY, ink);
    return h.hit;
}

/// Where text `size` high stands centred in `h` from `top`.
pub fn midIn(top: i32, h: i32, size: i32) i32 {
    return top + @divTrunc(h - size, 2);
}

pub fn midY(r: rl.Rectangle, size: i32) i32 {
    return midIn(@intFromFloat(r.y), @intFromFloat(r.height), size);
}

pub fn rightX(r: rl.Rectangle) i32 {
    return @intFromFloat(r.x + r.width);
}

const LABEL_PAD: i32 = 10;

/// A button just wide enough for `label` at `size`.
pub fn labelW(face: *const font.Face, label: [:0]const u8, size: i32) i32 {
    return textFace(face).width(label, size) + 2 * LABEL_PAD;
}

pub const Step = struct { tip: ?[:0]const u8, live: bool = true };

/// How a stepper looks: its two arrows, its value's size, and whether it sits on a modal page over a filled well.
const Arrows = struct { glyphs: [2][:0]const u8, size: i32, modal: bool, well: bool };
pub const KNOB_ARROWS = Arrows{ .glyphs = .{ "-", "+" }, .size = TEXT, .modal = false, .well = false };
pub const PAGE_ARROWS = Arrows{ .glyphs = .{ "<", ">" }, .size = DETAIL, .modal = true, .well = true };

/// Arrows either side of `value`: -1 or 1 as one is pressed, `SHIFT_STEP` times that when `shift`; 0 otherwise.
pub fn stepper(controls: Controls, face: *const font.Face, r: rl.Rectangle, value: []const u8, arrows: Arrows, steps: [2]Step, shift: bool) i32 {
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    var by: i32 = 0;
    if (buttonOn(controls, face, row(x, y, STEP_W), arrows.glyphs[0], false, steps[0].live, arrows.modal, steps[0].tip)) by = -1;
    if (buttonOn(controls, face, row(x + w - STEP_W, y, STEP_W), arrows.glyphs[1], false, steps[1].live, arrows.modal, steps[1].tip)) by = 1;
    if (arrows.well) rl.drawRectangle(x + STEP_W, y, w - 2 * STEP_W, ROW_H, LIVE_FILL);
    var fit_buf: [LINE]u8 = undefined;
    const shown = textFace(face).fit(&fit_buf, value, arrows.size, @intFromFloat(stepValue(r).width), false);
    textFace(face).drawMid(shown, x + @divTrunc(w, 2), midIn(y, ROW_H, arrows.size), arrows.size, look.TEXT);
    return if (shift) by * SHIFT_STEP else by;
}

pub fn stepValue(r: rl.Rectangle) rl.Rectangle {
    const inset: f32 = @floatFromInt(STEP_PITCH);
    return .{ .x = r.x + inset, .y = r.y, .width = r.width - 2 * inset, .height = r.height };
}

pub fn insetW(r: rl.Rectangle) i32 {
    return @as(i32, @intFromFloat(r.width)) - 2 * GAP;
}

pub fn textX(r: rl.Rectangle) i32 {
    return @as(i32, @intFromFloat(r.x)) + GAP;
}

/// `s` fitted ahead of `suffix`, which is kept whole.
pub fn fitBefore(face: *const font.Face, buf: []u8, fit_buf: []u8, s: []const u8, suffix: [:0]const u8, max: i32) [:0]const u8 {
    const head = textFace(face).fit(fit_buf, s, TEXT, max - textFace(face).width(suffix, TEXT), false);
    return std.fmt.bufPrintZ(buf, "{s}{s}", .{ head, suffix }) catch "";
}

pub fn well(r: rl.Rectangle, focused: bool) P {
    rl.drawRectangleRec(r, PANEL_BG);
    rl.drawRectangleLinesEx(r, 1, if (focused) look.UI_FOCUS else look.EDGE);
    return .{ .x = textX(r), .y = @as(i32, @intFromFloat(r.y)) + GAP };
}

pub fn plate(r: rl.Rectangle, on: bool, hot_: bool) void {
    if (on or hot_) rl.drawRectangleRec(r, ROW_ON);
    if (on) rl.drawRectangleLinesEx(r, 1, ON);
}

pub fn hoverEdge(r: rl.Rectangle, hot_: bool) void {
    if (hot_) rl.drawRectangleLinesEx(r, 1, HOVER);
}

pub fn row(x: i32, y: i32, w: i32) rl.Rectangle {
    return raster.rect(x, y, w, ROW_H);
}

pub fn slotOf(x0: i32, span: i32, y: i32, k: usize, n: usize) rl.Rectangle {
    const ni: i32 = @intCast(n);
    const w = @divTrunc(span - GAP * (ni - 1), ni);
    return row(x0 + @as(i32, @intCast(k)) * (w + GAP), y, w);
}

/// A panel down one side of the editor, `w` wide from `x`.
pub const Column = struct {
    x: i32,
    w: i32,

    pub fn left(c: Column) i32 {
        return c.x + PAD;
    }

    pub fn inner(c: Column) i32 {
        return c.w - 2 * PAD;
    }

    pub fn box(c: Column, top: i32, bottom: i32) rl.Rectangle {
        return raster.rect(c.x, top, c.w, @max(0, bottom - top));
    }

    /// The `k`th of `n` equal slots across row `y`.
    pub fn cell(c: Column, y: i32, k: usize, n: usize) rl.Rectangle {
        return slotOf(c.left(), c.inner(), y, k, n);
    }

    pub fn row(c: Column, y: i32) rl.Rectangle {
        return c.cell(y, 0, 1);
    }

    pub fn grid(c: Column, top: i32, i: usize, cols: usize, pitch: i32) rl.Rectangle {
        const s = mathx.unslot(i, cols);
        return c.cell(top + s.y * pitch, @intCast(s.x), cols);
    }
};

pub fn share(w: i32, parts: i32, lo: i32, hi: i32) i32 {
    return std.math.clamp(@divTrunc(w, parts), lo, hi);
}

pub fn rowsOf(n: usize, cols: usize) i32 {
    return @intCast(std.math.divCeil(usize, n, cols) catch unreachable);
}

pub fn scissor(r: rl.Rectangle) void {
    rl.beginScissorMode(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height));
}

fn scrollThumb(track: rl.Rectangle, offset: usize, shown: usize, total: usize) ?rl.Rectangle {
    if (shown == 0 or total <= shown or track.width <= 0 or track.height <= 0) return null;
    const visible: f32 = @floatFromInt(shown);
    const count: f32 = @floatFromInt(total);
    const height = @min(track.height, @max(THUMB_MIN, track.height * visible / count));
    const travel = (track.height - height) * @as(f32, @floatFromInt(@min(offset, total - shown))) / @as(f32, @floatFromInt(total - shown));
    return .{ .x = track.x, .y = track.y + travel, .width = track.width, .height = height };
}

fn scrollbar(track: rl.Rectangle, offset: usize, shown: usize, total: usize) void {
    const thumb = scrollThumb(track, offset, shown, total) orelse return;
    rl.drawRectangleRec(track, look.EDGE);
    rl.drawRectangleRec(thumb, look.UI_GOLD);
}

pub fn scrollbarIn(box: rl.Rectangle, offset: usize, shown: usize, total: usize) void {
    const w: f32 = @floatFromInt(SCROLL_W);
    scrollbar(.{ .x = box.x + box.width - w, .y = box.y, .width = w, .height = box.height }, offset, shown, total);
}

/// The scissor of `r` held within `clip`, the scrolled area it is drawn in.
pub fn scissorIn(clip: ?rl.Rectangle, r: rl.Rectangle) void {
    scissor(if (clip) |c| rl.getCollisionRec(c, r) else r);
}

pub fn reclip(clip: ?rl.Rectangle) void {
    if (clip) |c| scissor(c) else rl.endScissorMode();
}

/// The first of `rows` shown of `n`, moved `by` and held where the last still fills the view.
pub fn scrollTop(top: usize, by: i32, n: usize, rows: usize) usize {
    return mathx.nudge(top, by, (n -| rows) + 1);
}

pub fn clampTop(top: usize, n: usize, rows: usize) usize {
    return @min(top, n -| rows);
}

pub fn scrollBy(top: *i32, most: i32, by: i32) void {
    top.* = std.math.clamp(top.* + by, 0, most);
}

pub const Scroll = struct {
    box: rl.Rectangle,
    top: *i32,
    most: *i32,

    /// Clips to the box, held in `clip` so nothing outside it is hot; the content's first row.
    pub fn begin(s: Scroll, clip: *?rl.Rectangle) i32 {
        clip.* = s.box;
        scissor(s.box);
        s.top.* = std.math.clamp(s.top.*, 0, s.most.*);
        return @as(i32, @intFromFloat(s.box.y)) - s.top.*;
    }

    pub fn shown(s: Scroll) i32 {
        return @max(0, @as(i32, @intFromFloat(s.box.height)));
    }

    /// The content ran to `bottom`, wanting `margin` below it.
    pub fn fit(s: Scroll, bottom: i32, margin: i32) void {
        s.most.* = @max(0, bottom + margin + s.top.* - @as(i32, @intFromFloat(s.box.y)) - s.shown());
    }

    /// Scrolls the least that shows `h` pixels from `at`, the content's own offset.
    pub fn reveal(s: Scroll, at: i32, h: i32) void {
        const shown_at = at - s.top.*;
        if (shown_at < 0) s.top.* += shown_at;
        const below = shown_at + h - s.shown();
        if (below > 0) s.top.* += below;
    }

    pub fn bar(s: Scroll) void {
        if (s.most.* > 0) scrollbarIn(s.box, @intCast(s.top.*), @intCast(s.shown()), @intCast(s.shown() + s.most.*));
    }

    pub fn end(s: Scroll, bottom: i32, margin: i32) void {
        s.fit(bottom, margin);
        s.bar();
    }
};

pub fn unclip(clip: *?rl.Rectangle) void {
    rl.endScissorMode();
    clip.* = null;
}

test "editor scrollbar thumb remains inside its track for large catalogs and short views" {
    for ([_]f32{ 8, 300 }) |height| {
        const track = rl.Rectangle{ .x = 40, .y = 100, .width = 3, .height = height };
        for ([_]usize{ 0, 500, 1_000_000 }) |offset| {
            const thumb = scrollThumb(track, offset, 4, 2000).?;
            try std.testing.expect(thumb.y >= track.y);
            try std.testing.expect(thumb.y + thumb.height <= track.y + track.height);
            try std.testing.expect(thumb.height >= @min(THUMB_MIN, height));
        }
        try std.testing.expect(scrollThumb(track, 0, 4, 4) == null);
        try std.testing.expect(scrollThumb(track, 0, 0, 4) == null);
    }
    std.debug.print("editor scrollbars: 6 large-catalog/short-view bounds and 4 non-scrollable cases checked\n", .{});
}

pub const Across = struct {
    col: Column,
    y: i32,
    n: usize,
    k: usize = 0,

    pub fn next(a: *Across) rl.Rectangle {
        std.debug.assert(a.k < a.n);
        defer a.k += 1;
        return a.col.cell(a.y, a.k, a.n);
    }

    pub fn done(a: *const Across) void {
        std.debug.assert(a.k == a.n);
    }
};

pub const Lay = struct {
    x: i32,
    y: i32,
    gap: i32 = GAP,

    pub fn take(self: *Lay, w: i32) rl.Rectangle {
        defer self.x += w + self.gap;
        return row(self.x, self.y, w);
    }
};

pub const LayEnd = struct {
    right: i32,
    y: i32,
    gap: i32 = GAP,

    pub fn take(self: *LayEnd, w: i32) rl.Rectangle {
        defer self.right -= w + self.gap;
        return row(self.right - w, self.y, w);
    }
};

/// The rule between two columns, in the gutter left of `x`.
pub fn divider(x: i32, top: i32, bottom: i32) void {
    rl.drawRectangle(x - @divTrunc(PAD, 2), top, 1, bottom - top, look.EDGE);
}

pub const GAPS = P{ .x = GAP, .y = GAP };

pub fn tagSize(face: *const font.Face, s: [:0]const u8, pad: P) P {
    return .{ .x = textFace(face).width(s, DETAIL) + 2 * pad.x, .y = DETAIL + 2 * pad.y };
}

pub fn drawTag(face: *const font.Face, s: [:0]const u8, at: P, pad: P, bg: rl.Color, edge: ?rl.Color) void {
    const size = tagSize(face, s, pad);
    rl.drawRectangle(at.x, at.y, size.x, size.y, bg);
    if (edge) |e| rl.drawRectangleLines(at.x, at.y, size.x, size.y, e);
    textFace(face).draw(s, at.x + pad.x, at.y + pad.y, DETAIL, look.TEXT);
}

pub fn heading(face: *const font.Face, s: [:0]const u8, x: i32, y: i32) void {
    textFace(face).draw(s, x, y, DETAIL, look.UI_GOLD);
}

pub fn cellRect(o: [2]f32, p: P, cell: f32) rl.Rectangle {
    return .{ .x = o[0] + @as(f32, @floatFromInt(p.x)) * cell, .y = o[1] + @as(f32, @floatFromInt(p.y)) * cell, .width = cell, .height = cell };
}

pub fn framed(x: i32, y: i32, w: i32, h: i32) void {
    rl.drawRectangle(x, y, w, h, PANEL_BG);
    rl.drawRectangleLines(x, y, w, h, look.EDGE);
}

pub const Frame = struct {
    x: i32,
    w: i32,
    top: i32,
    y: i32,

    fn buttonX(f: Frame) i32 {
        return f.x + f.w - PAD - MODAL_BTN_W;
    }

    pub fn button(f: Frame, y: i32, k: i32) rl.Rectangle {
        return row(f.buttonX() - (MODAL_BTN_W + GAP) * k, y, MODAL_BTN_W);
    }
};

pub fn modalFrame(face: *const font.Face, screen: P, want_w: i32, h: i32, title: [:0]const u8, keep_end: bool) Frame {
    const w = @min(want_w, screen.x - 2 * PAD);
    const x = @divTrunc(screen.x - w, 2);
    const y = @max(0, @divTrunc(screen.y - h, 2));
    framed(x, y, w, h);
    const top = y + PAD;
    drawFit(face, title, HEAD, w - 2 * PAD, keep_end, x + PAD, top, look.TEXT);
    return .{ .x = x, .w = w, .top = top, .y = y + MODAL_HEAD };
}

/// `hint` after the frame's `title`, on its line.
pub fn titleHint(face: *const font.Face, f: Frame, title: [:0]const u8, hint: []const u8) void {
    const x = f.x + 2 * PAD + textFace(face).width(title, HEAD);
    drawFit(face, hint, DETAIL, f.x + f.w - PAD - x, false, x, midIn(f.top, HEAD, DETAIL), look.DIM);
}

pub const Page = struct { frame: Frame, bottom: i32 };

/// A page over the whole editor; `bottom` is the inside of its padding.
pub fn pageFrame(face: *const font.Face, screen: P, title: [:0]const u8) Page {
    const h = @min(PAGE_H, screen.y - 2 * PAD);
    const f = modalFrame(face, screen, PAGE_W, h, title, false);
    return .{ .frame = f, .bottom = f.top - PAD + h - PAD };
}

pub fn keyed(comptime what: []const u8, comptime key: []const u8) [:0]const u8 {
    return what ++ " (" ++ key ++ ")";
}

/// A square picture `size` across, centred in a button `top` below its edge.
pub fn pictureIn(r: rl.Rectangle, size: f32, top: f32) rl.Rectangle {
    return .{ .x = r.x + (r.width - size) / 2, .y = r.y + top, .width = size, .height = size };
}

/// A square picture `size` across, `dx` in from a row's left and centred down it.
pub fn pictureAt(r: rl.Rectangle, dx: f32, size: f32) rl.Rectangle {
    return .{ .x = r.x + dx, .y = r.y + (r.height - size) / 2, .width = size, .height = size };
}

pub fn sprite(t: rl.Texture2D, r: rl.Rectangle) void {
    const scale = @min(r.width / @as(f32, @floatFromInt(t.width)), r.height / @as(f32, @floatFromInt(t.height)));
    const width = @as(f32, @floatFromInt(t.width)) * scale;
    const height = @as(f32, @floatFromInt(t.height)) * scale;
    raster.stretch(t, .{ .x = r.x + (r.width - width) / 2, .y = r.y + (r.height - height) / 2, .width = width, .height = height }, look.LIT);
}

pub fn figure(face: *const font.Face, tex: ?rl.Texture2D, l: look.Look, r: rl.Rectangle) void {
    if (tex) |t| sprite(t, r) else glyph(face, l.ch, r, l.fg);
}

const GlyphBox = struct { x: i32, y: i32, size: i32 };

fn inkIn(r: rl.Rectangle) GlyphBox {
    const at = raster.middleAt(r);
    return .{ .x = at.x, .y = at.y, .size = @intFromFloat(r.width * GLYPH_OF_CELL) };
}

pub fn glyph(face: *const font.Face, ch: u8, r: rl.Rectangle, col: rl.Color) void {
    const m = inkIn(r);
    face.glyph(ch, m.x, m.y, m.size, col);
}

pub fn tileGlyph(face: *const font.Face, t: grid.Tile, r: rl.Rectangle) void {
    const m = inkIn(r);
    look.inkTile(face, t, m.x, m.y, m.size);
}

pub fn drawFit(face: *const font.Face, s: []const u8, size: i32, max: i32, keep_end: bool, x: i32, y: i32, col: rl.Color) void {
    var fit_buf: [listing.PATH_MAX + LINE]u8 = undefined;
    textFace(face).draw(textFace(face).fit(&fit_buf, s, size, max, keep_end), x, y, size, col);
}
