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

pub const PANEL_W: i32 = 420;
pub const PAD: i32 = 12;
pub const ROW_H: i32 = 34;
pub const GAP: i32 = 6;
pub const SECTION_GAP: i32 = GAP * 3;
pub const BLOCK_GAP: i32 = GAP * 2;
pub const ROW_STEP: i32 = ROW_H + GAP;
pub const TEXT: i32 = 24;
pub const DETAIL: i32 = 20;
pub const HEAD: i32 = 32;
pub const LINE_STEP: i32 = TEXT + GAP;
pub const INNER_W: i32 = PANEL_W - PAD * 2;
pub const LINE: usize = 200;
pub const MODAL_W: i32 = 720;
pub const MODAL_HEAD: i32 = PAD + HEAD + PAD;
pub const MODAL_ROWS: usize = 12;
pub const MODAL_BTN_W: i32 = 180;
pub const PAGE_W: i32 = 1800;
pub const PAGE_H: i32 = 1080;
pub const STEP_W: i32 = 30;
pub const SCROLL_W: i32 = 3;
pub const GLYPH_OF_CELL: f32 = @as(f32, @floatFromInt(look.GLYPH_PX)) / @as(f32, @floatFromInt(look.SPRITE_PX));
pub const PANEL_BG = look.EDIT_PANEL;
pub const ROW_ON = look.EDIT_ROW_ON;
pub const ON = look.EDIT_ON;

const SMALL = DETAIL;

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

pub fn buttonOn(controls: Controls, face: *const font.Face, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, modal: bool, tip: ?[:0]const u8) bool {
    const h = hot(controls, r, live, modal, tip);
    rl.drawRectangleRec(r, look.fade(ROW_ON, if (live) 0.5 else 0.2));
    rl.drawRectangleLinesEx(r, 1, look.fade(look.EDGE, if (live) 0.85 else 0.35));
    plate(r, on, h.hot);
    const y: i32 = @intFromFloat(r.y);
    drawFit(face, label, TEXT, insetW(r), false, textX(r), y + @divTrunc(@as(i32, @intFromFloat(r.height)) - TEXT, 2), if (live) look.TEXT else look.DIM);
    return h.hit;
}

pub const Step = struct { tip: ?[:0]const u8, live: bool = true };

/// How a stepper looks: its two arrows, its value's size, and whether it sits on a modal page over a filled well.
pub const Arrows = struct { glyphs: [2][:0]const u8, size: i32, modal: bool, well: bool };
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
    if (arrows.well) rl.drawRectangle(x + STEP_W, y, w - 2 * STEP_W, ROW_H, look.fade(ROW_ON, 0.5));
    var fit_buf: [LINE]u8 = undefined;
    const shown = textFace(face).fit(&fit_buf, value, arrows.size, @intFromFloat(stepValue(r).width), false);
    textFace(face).drawMid(shown, x + @divTrunc(w, 2), y + @divTrunc(ROW_H - arrows.size, 2), arrows.size, look.TEXT);
    return if (shift) by * SHIFT_STEP else by;
}

pub fn stepValue(r: rl.Rectangle) rl.Rectangle {
    const inset: f32 = @floatFromInt(STEP_W + GAP);
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

pub fn plate(r: rl.Rectangle, on: bool, hot_: bool) void {
    if (on or hot_) rl.drawRectangleRec(r, ROW_ON);
    if (on) rl.drawRectangleLinesEx(r, 1, ON);
}

pub fn row(x: i32, y: i32, w: i32) rl.Rectangle {
    return raster.rect(x, y, w, ROW_H);
}

pub fn slotOf(x0: i32, span: i32, y: i32, k: usize, n: usize) rl.Rectangle {
    const ni: i32 = @intCast(n);
    const w = @divTrunc(span - GAP * (ni - 1), ni);
    return row(x0 + @as(i32, @intCast(k)) * (w + GAP), y, w);
}

pub fn cellOfRow(y: i32, k: usize, n: usize) rl.Rectangle {
    return slotOf(PAD, INNER_W, y, k, n);
}

pub fn scissor(r: rl.Rectangle) void {
    rl.beginScissorMode(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height));
}

pub fn scrollThumb(track: rl.Rectangle, offset: usize, shown: usize, total: usize) ?rl.Rectangle {
    if (shown == 0 or total <= shown or track.width <= 0 or track.height <= 0) return null;
    const visible: f32 = @floatFromInt(shown);
    const count: f32 = @floatFromInt(total);
    const height = @min(track.height, @max(24, track.height * visible / count));
    const travel = (track.height - height) * @as(f32, @floatFromInt(@min(offset, total - shown))) / @as(f32, @floatFromInt(total - shown));
    return .{ .x = track.x, .y = track.y + travel, .width = track.width, .height = height };
}

pub fn scrollbar(track: rl.Rectangle, offset: usize, shown: usize, total: usize) void {
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
        return @intFromFloat(s.box.height);
    }

    /// The content ran to `bottom`, wanting `margin` below it.
    pub fn fit(s: Scroll, bottom: i32, margin: i32) void {
        s.most.* = @max(0, bottom + margin + s.top.* - @as(i32, @intFromFloat(s.box.y)) - s.shown());
    }

    pub fn bar(s: Scroll) void {
        if (s.most.* > 0) scrollbarIn(s.box, @intCast(s.top.*), @intCast(s.shown()), @intCast(s.shown() + s.most.*));
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
            try std.testing.expect(thumb.height >= @min(24, height));
        }
        try std.testing.expect(scrollThumb(track, 0, 4, 4) == null);
        try std.testing.expect(scrollThumb(track, 0, 0, 4) == null);
    }
    std.debug.print("editor scrollbars: 6 large-catalog/short-view bounds and 4 non-scrollable cases checked\n", .{});
}

pub const Across = struct {
    y: i32,
    n: usize,
    k: usize = 0,

    pub fn next(a: *Across) rl.Rectangle {
        std.debug.assert(a.k < a.n);
        defer a.k += 1;
        return cellOfRow(a.y, a.k, a.n);
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
    return .{ .x = textFace(face).width(s, SMALL) + 2 * pad.x, .y = SMALL + 2 * pad.y };
}

pub fn drawTag(face: *const font.Face, s: [:0]const u8, at: P, pad: P, bg: rl.Color, edge: ?rl.Color) void {
    const size = tagSize(face, s, pad);
    rl.drawRectangle(at.x, at.y, size.x, size.y, bg);
    if (edge) |e| rl.drawRectangleLines(at.x, at.y, size.x, size.y, e);
    textFace(face).draw(s, at.x + pad.x, at.y + pad.y, SMALL, look.TEXT);
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

    pub fn buttonX(f: Frame) i32 {
        return f.x + f.w - PAD - MODAL_BTN_W;
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
