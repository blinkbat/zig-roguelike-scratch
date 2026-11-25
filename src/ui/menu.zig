const sprite = @import("../gfx/sprites.zig");
const std = @import("std");
const wording = @import("../core/wording.zig");
const text = @import("../core/text.zig");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const font = @import("../gfx/font.zig");
const display = @import("../core/window.zig");

pub const CONFIRM = input.CONFIRM;
pub const BACK = input.Button.b;
pub const PAUSE = input.Button.pause;
pub const CHARACTER = input.Button.character;
pub const CHANGE = input.Button.x;
pub const REMOVE = input.Button.y;
pub const RUB = input.Button.x;
pub const PAGE_PREV = input.Button.lb;
pub const PAGE_NEXT = input.Button.rb;
pub const INSPECT = input.Button.inspect;

pub const TITLE: i32 = 54;
pub const ROW: i32 = 28;
pub const ROW_STEP: i32 = 38;
pub const NOTE: i32 = font.SMALL;
const TITLE_DY: i32 = -44;
const ROWS_DY: i32 = 16;
const ROW_INSET: i32 = 4;
pub const NOTE_GAP: i32 = 24;
const MARK_GAP: i32 = 14;
const SCREEN_MARGIN: i32 = 14;
const MARK_L = ">";
const ABOVE: i32 = TITLE - TITLE_DY + ROWS_DY;
const BELOW: i32 = NOTE_GAP + NOTE;
pub const TITLE_LEAD: i32 = ABOVE - ROW_INSET;
const CHROME_H: i32 = 2 * @as(i32, @max(ABOVE, BELOW));
pub const NOTE_MAX: usize = 160;
pub const SEP = "   ";
pub const CARET = "_";
pub const FRACTION_FMT = "{d} / {d}";

const SURFACE_MARGIN: i32 = 16;
const GROWTH: f32 = 0.5;
const SCALE_MAX: f32 = 1.25;

pub const Surface = struct {
    scale: f32,
    offset: rl.Vector2,

    pub const IDENTITY = Surface{ .scale = 1, .offset = .{ .x = 0, .y = 0 } };

    pub fn of(screen: mathx.P, size: mathx.P) Surface {
        const fit = @min(@as(f32, @floatFromInt(@max(1, screen.x - 2 * SURFACE_MARGIN))) / @as(f32, @floatFromInt(size.x)), @as(f32, @floatFromInt(@max(1, screen.y - 2 * SURFACE_MARGIN))) / @as(f32, @floatFromInt(size.y)));
        return centred(screen, size, if (fit <= 1) fit else @min(SCALE_MAX, 1 + (fit - 1) * GROWTH));
    }

    pub fn like(screen: mathx.P, size: mathx.P, reference: mathx.P) Surface {
        return centred(screen, size, @min(of(screen, size).scale, of(screen, reference).scale));
    }

    fn centred(screen: mathx.P, size: mathx.P, scale: f32) Surface {
        return .{ .scale = scale, .offset = .{
            .x = @round((@as(f32, @floatFromInt(screen.x)) - @as(f32, @floatFromInt(size.x)) * scale) / 2),
            .y = @round((@as(f32, @floatFromInt(screen.y)) - @as(f32, @floatFromInt(size.y)) * scale) / 2),
        } };
    }

    pub fn point(self: Surface, p: mathx.P) mathx.P {
        return .{
            .x = @intFromFloat((@as(f32, @floatFromInt(p.x)) - self.offset.x) / self.scale),
            .y = @intFromFloat((@as(f32, @floatFromInt(p.y)) - self.offset.y) / self.scale),
        };
    }

    pub fn screenOf(self: Surface, p: rl.Vector2) mathx.P {
        return .{ .x = @intFromFloat(self.offset.x + p.x * self.scale), .y = @intFromFloat(self.offset.y + p.y * self.scale) };
    }

    pub fn begin(self: Surface) void {
        rl.beginMode2D(.{ .target = .{ .x = 0, .y = 0 }, .offset = self.offset, .rotation = 0, .zoom = self.scale });
    }

    pub fn beginPanel(self: Surface, sprites: *const sprite.Sprites, size: mathx.P) void {
        self.begin();
        sprite.layeredBacking(sprites, 0, 0, size.x, size.y, .menu);
    }

    /// `f` as this surface draws it: scaled, from the mipmapped atlas rather than the native-size ones.
    pub fn faceFor(self: Surface, f: font.Face) font.Face {
        return if (self.scale != 1) f.mipmapped() else f;
    }

    pub fn rectOf(self: Surface, r: rl.Rectangle) rl.Rectangle {
        return .{ .x = self.offset.x + r.x * self.scale, .y = self.offset.y + r.y * self.scale, .width = r.width * self.scale, .height = r.height * self.scale };
    }

    pub fn clip(self: Surface, r: rl.Rectangle) void {
        const t = self.rectOf(r);
        rl.beginScissorMode(@intFromFloat(@floor(t.x)), @intFromFloat(@floor(t.y)), @intFromFloat(@ceil(t.width)), @intFromFloat(@ceil(t.height)));
    }
};

test "panel surfaces stay invertible when the window shrinks below its margins" {
    const size = mathx.P{ .x = 640, .y = 480 };
    const edges = [_]i32{ 0, 1, 2 * SURFACE_MARGIN - 1, 2 * SURFACE_MARGIN, 2 * SURFACE_MARGIN + 1 };
    for (edges) |edge| {
        for ([_]mathx.P{ .{ .x = edge, .y = display.SCREEN_720.y }, .{ .x = display.SCREEN_720.x, .y = edge } }) |screen| {
            const surface = Surface.of(screen, size);
            try std.testing.expect(std.math.isFinite(surface.scale) and surface.scale > 0);
            _ = surface.point(.{ .x = 0, .y = 0 });
        }
    }
}

pub fn outline(r: rl.Rectangle, on: bool) void {
    hairline(r, if (on) look.UI_FOCUS else look.BORDER);
}

pub fn border(r: rl.Rectangle, col: rl.Color) void {
    if (!std.meta.eql(col, look.BORDER)) return lines(r, look.BORDER_W, col);
    const tex = sprite.small_border orelse return lines(r, look.BORDER_W, col);
    const s = ScreenPx.now();
    if (!raster.frame(tex, sprite.SMALL_BORDER_CUT, s.x(r.x), s.y(r.y), s.x(r.x + r.width), s.y(r.y + r.height), s.scale, look.LIT)) lines(r, look.BORDER_W, col);
}

pub fn shimmer(sprites: *const sprite.Sprites, r: rl.Rectangle, seconds: f32, key: usize) void {
    const t = look.boxShine(seconds, key) orelse return;
    const s = ScreenPx.now();
    const size = [2]f32{ r.width * s.scale, r.height * s.scale };
    const span = size[0] + size[1] * look.SHINE_SLANT;
    sprites.shineBox(r, size, mathx.lerpF(-look.BOX_SHINE_WIDTH_PX, span + look.BOX_SHINE_WIDTH_PX, t));
}

pub fn hairline(r: rl.Rectangle, col: rl.Color) void {
    lines(r, look.HAIRLINE_W, col);
}

pub fn edgeRule(x: i32, y: i32, width: i32) void {
    edgeLine(raster.rect(x, y, width, 0), true);
}

pub fn edgeColumn(x: i32, top: i32, foot: i32) void {
    edgeLine(raster.rect(x, top, 0, foot - top), false);
}

const DIVIDER_A: f32 = 0.5;

fn edgeLine(line: rl.Rectangle, across: bool) void {
    const s = ScreenPx.now();
    var r = s.rect(line);
    if (across) r.height = s.of(look.HAIRLINE_W) else r.width = s.of(look.HAIRLINE_W);
    rl.drawRectangleRec(r, look.fade(look.BORDER, DIVIDER_A));
}

/// A square dot centred on `mid_y` at `x`; returns where text after it starts.
pub fn middot(x: i32, mid_y: i32, col: rl.Color) i32 {
    rl.drawRectangle(x + DOT_GAP, mid_y - @divTrunc(DOT, 2), DOT, DOT, col);
    return x + MIDDOT_W;
}

const DOT: i32 = 3;
const DOT_GAP: i32 = 8;
pub const MIDDOT_W: i32 = DOT_GAP * 2 + DOT;

fn lines(r: rl.Rectangle, w: f32, col: rl.Color) void {
    const s = ScreenPx.now();
    rl.drawRectangleLinesEx(s.rect(r), s.of(w), col);
}

/// Panels draw under a zoomed camera: borders are measured in, and snapped to, whole screen pixels.
const ScreenPx = struct {
    scale: f32,
    dx: f32,
    dy: f32,

    fn now() ScreenPx {
        const m = rl.gl.rlGetMatrixModelview();
        return .{ .scale = if (m.m0 > 0) m.m0 else 1, .dx = m.m12, .dy = m.m13 };
    }

    fn x(s: ScreenPx, v: f32) f32 {
        return (@round(v * s.scale + s.dx) - s.dx) / s.scale;
    }

    fn y(s: ScreenPx, v: f32) f32 {
        return (@round(v * s.scale + s.dy) - s.dy) / s.scale;
    }

    fn of(s: ScreenPx, px: f32) f32 {
        return px / s.scale;
    }

    fn rect(s: ScreenPx, r: rl.Rectangle) rl.Rectangle {
        const left = s.x(r.x);
        const top = s.y(r.y);
        return .{ .x = left, .y = top, .width = s.x(r.x + r.width) - left, .height = s.y(r.y + r.height) - top };
    }
};

pub fn titledCard(face: *const font.Face, sprites: *const sprite.Sprites, x: i32, y: i32, w: i32, h: i32, depth: look.Depth, pad: i32, title: [:0]const u8) void {
    sprite.layeredBacking(sprites, x, y, w, h, depth);
    face.richText(title, x + pad, y + pad, font.BODY, look.UI_FOCUS);
}

pub fn cardBodyY(pad: i32, gap: i32) i32 {
    return pad + font.BODY + gap;
}

pub fn cardHeight(pad: i32, gap: i32, line: i32, rows: usize) i32 {
    return cardBodyY(pad, gap) + pad + @as(i32, @intCast(rows)) * line;
}

const ACTION_PAD: i32 = 10;
pub const PROMPT_GAP: i32 = 8;
pub const ACTION_BOX = mathx.P{ .x = 164, .y = 36 };
pub const ACTION_WIDE = mathx.P{ .x = 220, .y = 40 };
pub const ACTION_GAP: i32 = 8;
pub const PANEL_PAD: i32 = 24;

pub fn boxed(r: rl.Rectangle, fill: rl.Color, edge: rl.Color) void {
    rl.drawRectangleRec(r, fill);
    border(r, edge);
}

pub fn boxedSmall(r: rl.Rectangle, fill: rl.Color, edge: rl.Color) void {
    rl.drawRectangleRec(r, fill);
    hairline(r, edge);
}

pub fn action(face: *const font.Face, r: rl.Rectangle, prompt: prompt_icon.Prompt, label: [:0]const u8) void {
    boxed(r, look.PICK_BG, look.BORDER);
    const text_x = actionPrompt(face, r, prompt, 1);
    const text_w = raster.right(r) - ACTION_PAD - text_x;
    face.centred(label, text_x + @divTrunc(text_w, 2), raster.middleAt(r).y, font.BODY, look.TEXT);
}

pub fn actionPrompt(face: *const font.Face, r: rl.Rectangle, prompt: prompt_icon.Prompt, alpha: f32) i32 {
    return prompt.drawFrom(face, raster.left(r) + ACTION_PAD, raster.middleAt(r).y, font.BODY, alpha) + PROMPT_GAP;
}

pub const Note = text.Note;

pub fn joined(comptime names: anytype, comptime last: text.Conjunction) [:0]const u8 {
    comptime var s: [:0]const u8 = "";
    inline for (names, 0..) |nm, i| s = s ++ listSep(i, names.len, last) ++ nm;
    const out = s;
    return out;
}

pub const listSep = text.listSep;

pub const Activation = union(enum) {
    mouse: usize,
    confirm: usize,

    pub fn row(self: Activation) usize {
        return switch (self) {
            .mouse, .confirm => |i| i,
        };
    }
};

pub const Menu = struct {
    at: usize = 0,
    dragging: ?usize = null,

    fn clampTo(self: *Menu, n: usize) bool {
        if (n == 0) return false;
        self.at = @min(self.at, n - 1);
        return true;
    }

    pub fn step(self: *Menu, st: *const input.State, n: usize) ?usize {
        if (!self.clampTo(n)) return null;
        if (st.walk) |d| self.at = mathx.wrap(self.at, d.delta().y, n);
        return if (st.hit(CONFIRM)) self.at else null;
    }

    pub fn stepAt(self: *Menu, st: *const input.State, n: usize, screen: mathx.P) ?usize {
        const activation = self.activateAt(st, n, screen) orelse return null;
        return activation.row();
    }

    pub fn activateAt(self: *Menu, st: *const input.State, n: usize, screen: mathx.P) ?Activation {
        if (!self.clampTo(n)) return null;
        const win = window(screen.y, n, self.at);
        self.at = st.scrolled(self.at, n);
        if (win.len == n or st.click) if (pointed(st, win.len, Rows{ .screen = screen, .win = win }, Rows.box)) |k| {
            self.at = win.from + k;
            if (st.click) return .{ .mouse = self.at };
        };
        return self.confirm(st, n);
    }

    pub fn activateOver(self: *Menu, st: *const input.State, n: usize, ctx: anytype, comptime boxOf: fn (@TypeOf(ctx), usize) rl.Rectangle) ?Activation {
        if (!self.clampTo(n)) return null;
        if (pointAt(&self.at, st, n, ctx, boxOf)) |k| return .{ .mouse = k };
        return self.confirm(st, n);
    }

    fn confirm(self: *Menu, st: *const input.State, n: usize) ?Activation {
        const i = self.step(st, n) orelse return null;
        return .{ .confirm = i };
    }
};

pub fn pointAt(at: *usize, st: *const input.State, n: usize, ctx: anytype, comptime boxOf: fn (@TypeOf(ctx), usize) rl.Rectangle) ?usize {
    at.* = st.scrolled(at.*, n);
    const k = pointed(st, n, ctx, boxOf) orelse return null;
    at.* = k;
    return if (st.click) k else null;
}

const Rows = struct {
    screen: mathx.P,
    win: Window,

    fn box(r: Rows, k: usize) rl.Rectangle {
        return rowBox(r.screen, r.win, r.win.from + k);
    }
};

fn pointed(st: *const input.State, n: usize, ctx: anytype, comptime boxOf: fn (@TypeOf(ctx), usize) rl.Rectangle) ?usize {
    if (!st.pointing() or st.scroll != 0 or st.walk != null) return null;
    for (0..n) |i| {
        if (raster.holds(boxOf(ctx, i), st.pointer.?)) return i;
    }
    return null;
}

pub fn backed(st: *const input.State) bool {
    return st.right_click or st.hit(BACK) or st.hit(PAUSE);
}

pub fn footerBox(screen: mathx.P) rl.Rectangle {
    return raster.rect(PANEL_PAD, screen.y - PANEL_PAD - ACTION_WIDE.y, ACTION_WIDE.x, ACTION_WIDE.y);
}

pub fn backedAt(st: *const input.State, screen: mathx.P) bool {
    return backed(st) or st.clicked(footerBox(screen));
}

pub fn drawBack(face: *const font.Face, screen: mathx.P, st: *const input.State) void {
    action(face, footerBox(screen), prompt_icon.Prompt.menuOf(st, BACK), "Back");
}

pub fn closed(st: *const input.State) bool {
    return backed(st) or st.hit(CHARACTER);
}

pub fn clampOn(at: i32, size: i32, room: i32, margin: i32) i32 {
    return std.math.clamp(at, margin, @max(margin, room - size - margin));
}

pub fn besideX(anchor: rl.Rectangle, w: i32, screen_w: i32, gap: i32, margin: i32) ?i32 {
    const right = raster.right(anchor) + gap;
    if (right + w <= screen_w - margin) return right;
    const left = raster.left(anchor) - gap - w;
    return if (left >= margin) left else null;
}

const ACROSS: f32 = 2;

fn sliceBox(boxes: []const rl.Rectangle, i: usize) rl.Rectangle {
    return boxes[i];
}

pub fn nearest(from: rl.Rectangle, boxes: []const rl.Rectangle, dir: mathx.Dir) ?usize {
    return nearestFrom(from, boxes.len, dir, boxes, sliceBox);
}

pub fn nearestBy(n: usize, from: usize, dir: mathx.Dir, ctx: anytype, comptime boxOf: fn (@TypeOf(ctx), usize) rl.Rectangle) ?usize {
    return nearestFrom(boxOf(ctx, from), n, dir, ctx, boxOf);
}

fn nearestFrom(start: rl.Rectangle, n: usize, dir: mathx.Dir, ctx: anytype, comptime boxOf: fn (@TypeOf(ctx), usize) rl.Rectangle) ?usize {
    var best: ?usize = null;
    var best_score = std.math.floatMax(f32);
    for (0..n) |i| {
        const score = directionScore(start, boxOf(ctx, i), dir) orelse continue;
        if (score < best_score) {
            best_score = score;
            best = i;
        }
    }
    return best;
}

fn directionScore(from: rl.Rectangle, to: rl.Rectangle, dir: mathx.Dir) ?f32 {
    const a = raster.middle(from);
    const b = raster.middle(to);
    const vx = b.x - a.x;
    const vy = b.y - a.y;
    const d = dir.delta();
    const wx: f32 = @floatFromInt(d.x);
    const wy: f32 = @floatFromInt(d.y);
    const along = vx * wx + vy * wy;
    if (along <= 0) return null;
    return along + ACROSS * @abs(vx * wy - vy * wx);
}

pub const Window = struct {
    from: usize,
    len: usize,

    pub fn of(n: usize, at: usize, room: usize) Window {
        const len = @min(n, room);
        return .{ .from = @min(at -| len / 2, n - len), .len = len };
    }
};

pub fn window(screen_h: i32, n: usize, at: usize) Window {
    const room: usize = @intCast(@max(1, @divTrunc(screen_h - CHROME_H, ROW_STEP)));
    return Window.of(n, at, room);
}

const LIST_W: i32 = 640;

pub fn listWidth(screen: mathx.P) i32 {
    return @min(LIST_W, @max(1, screen.x - 2 * SCREEN_MARGIN));
}

pub fn listLeft(screen: mathx.P) i32 {
    return @divTrunc(screen.x - listWidth(screen), 2);
}

pub fn rowBox(screen: mathx.P, win: Window, i: usize) rl.Rectangle {
    const top = @divTrunc(screen.y, 2) - @divTrunc(@as(i32, @intCast(win.len)) * ROW_STEP, 2);
    return raster.rect(listLeft(screen), top + ROWS_DY + @as(i32, @intCast(i - win.from)) * ROW_STEP - ROW_INSET, listWidth(screen), ROW_STEP);
}

pub fn rowTextY(box: rl.Rectangle) i32 {
    return raster.top(box) + ROW_INSET;
}

pub fn titleY(first: rl.Rectangle) i32 {
    return raster.top(first) - TITLE_LEAD;
}

pub fn noteY(first: rl.Rectangle, count: usize) i32 {
    return rowTextY(first) + @as(i32, @intCast(count)) * ROW_STEP + NOTE_GAP;
}

pub fn listFrame(face: font.Face, sprites: *const sprite.Sprites, screen: mathx.P, title: [:0]const u8, n: usize, at: usize) Window {
    const win = window(screen.y, n, at);
    const first = rowBox(screen, win, win.from);
    pageHeading(face, screen, title, titleY(first));
    if (win.len > 0) listPanel(sprites, .{ .x = first.x, .y = first.y, .width = first.width, .height = @floatFromInt(win.len * ROW_STEP) });
    return win;
}

pub fn draw(face: font.Face, sprites: *const sprite.Sprites, screen: mathx.P, title: [:0]const u8, all: []const []const u8, at: usize, note: ?[:0]const u8) void {
    const win = listFrame(face, sprites, screen, title, all.len, at);
    const rows = all[win.from..][0..win.len];
    const first = rowBox(screen, win, win.from);
    const inset = markInset(face);
    const widest = raster.width(first) - 2 * inset;
    var fit_buf: [NOTE_MAX + 1]u8 = undefined;
    for (rows, win.from..) |whole, i| {
        const r = face.fit(&fit_buf, whole, ROW, widest, false);
        const box = rowBox(screen, win, i);
        const on = i == at;
        face.text(r, pick(face, box, on), rowTextY(box), ROW, rowInk(on));
    }
    if (note) |n| _ = face.paragraph(n, raster.left(first) + inset, noteY(first, rows.len), widest, NOTE, look.DIM);
}

pub fn listPanel(sprites: *const sprite.Sprites, rows: rl.Rectangle) void {
    sprite.layeredBackingIn(sprites, raster.grown(rows, @floatFromInt(sprite.HUD_BORDER_CUT)), .menu);
}

fn markInset(face: font.Face) i32 {
    return MARK_GAP * 2 + face.width(MARK_L, ROW);
}

pub fn pick(face: font.Face, box: rl.Rectangle, on: bool) i32 {
    const x = raster.left(box) + markInset(face);
    band(box, on);
    if (on) face.textRight(MARK_L, x - MARK_GAP, rowTextY(box), ROW, look.UI_FOCUS);
    return x;
}

pub fn band(box: rl.Rectangle, on: bool) void {
    if (on) rl.drawRectangleRec(box, look.ROW_ON);
}

pub fn rowInk(on: bool) rl.Color {
    return if (on) look.UI_FOCUS else look.DIM;
}

/// Printed into `buf` upper-cased, as a title is; empty if it does not fit.
pub fn shout(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    const s = std.fmt.bufPrintZ(buf, fmt, args) catch return "";
    _ = std.ascii.upperString(buf[0..s.len], s);
    return s;
}

/// `shout` for a string known at compile time; call it `comptime`.
pub const caps = text.upper;

pub const capital = wording.spoken;

pub const named = wording.named;
pub const titleOf = wording.titleOf;
pub const word = wording.word;

test "display aliases use actual enum types without renaming identifiers" {
    const Hero = @import("../play/hero.zig").Class;
    const Act = @import("../play/skillbar.zig").Act;
    const Kind = @import("../play/item_bases.zig").Kind;
    try std.testing.expectEqualStrings("play.hero.Class", @typeName(Hero));
    try std.testing.expectEqualStrings("play.skillbar.Act", @typeName(Act));
    try std.testing.expectEqualStrings("play.item_bases.Kind", @typeName(Kind));
    const labels = "play.hero.Class.archer\tWayfarer\nplay.skillbar.Act.shoot\tLoose Arrow\nplay.items.Kind.short_bow\tHunting bow\n";
    try std.testing.expectEqualStrings("Wayfarer", comptime wording.displayAliasIn(labels, @typeName(Hero), "archer").?);
    try std.testing.expectEqualStrings("Loose Arrow", comptime wording.displayAliasIn(labels, @typeName(Act), "shoot").?);
    try std.testing.expectEqualStrings("Hunting bow", comptime wording.displayAliasIn(labels, @typeName(Kind), "short_bow").?);
    try std.testing.expectEqualStrings("archer", @tagName(Hero.archer));
}

test "an enum's label reads as words" {
    try std.testing.expectEqualStrings("Iron boots", named(@import("../play/item_bases.zig").Kind.iron_boots));
}

pub const TestFace = struct {
    pub fn width(_: @This(), s: [:0]const u8, size: i32) i32 {
        return @as(i32, @intCast(s.len)) * @divTrunc(size, 2);
    }
};

pub fn toggle(comptime label: []const u8, on: bool) [:0]const u8 {
    return if (on) label ++ ": On" else label ++ ": Off";
}

fn fitScreen(face: font.Face, buf: *[NOTE_MAX + 1]u8, screen: mathx.P, s: [:0]const u8, size: i32) [:0]const u8 {
    return face.fit(buf, s, size, screen.x - 2 * SCREEN_MARGIN, false);
}

pub fn mid(face: font.Face, screen: mathx.P, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    var buf: [NOTE_MAX + 1]u8 = undefined;
    face.textMid(fitScreen(face, &buf, screen, s, size), @divTrunc(screen.x, 2), y, size, col);
}

const RULE_REACH: i32 = 56;
const RULE_GAP: i32 = 9;
const RULE_PIP: f32 = 3;
const RULE_A: f32 = 0.7;
const RULE_DROP: f32 = 1.02;

pub fn heading(face: font.Face, screen: mathx.P, s: [:0]const u8, y: i32, size: i32, col: rl.Color, accent: rl.Color) void {
    var buf: [NOTE_MAX + 1]u8 = undefined;
    const t = fitScreen(face, &buf, screen, s, size);
    const cx = @divTrunc(screen.x, 2);
    face.engravedMid(t, cx, y, size, col);
    const half = @min(@divTrunc(face.width(t, size), 2) + RULE_REACH, @divTrunc(screen.x, 2) - SCREEN_MARGIN);
    rule(cx, y + @as(i32, @intFromFloat(@as(f32, @floatFromInt(size)) * RULE_DROP)), half, look.fade(accent, RULE_A * look.alphaOf(col)));
}

pub fn pageHeading(face: font.Face, screen: mathx.P, s: [:0]const u8, y: i32) void {
    heading(face, screen, s, y, TITLE, look.TEXT, look.UI_GOLD);
}

fn rule(cx: i32, y: i32, half: i32, col: rl.Color) void {
    for ([_]bool{ true, false }) |shadow| {
        const by: i32 = @intFromBool(shadow);
        const ink = if (shadow) look.fade(look.BG, look.alphaOf(col)) else col;
        const clear = look.fade(ink, 0);
        const reach = half - RULE_GAP;
        rl.drawRectangleGradientH(cx - half + by, y + by, reach, 1, clear, ink);
        rl.drawRectangleGradientH(cx + RULE_GAP + by, y + by, reach, 1, ink, clear);
        rl.drawPoly(.{ .x = @floatFromInt(cx + by), .y = @as(f32, @floatFromInt(y + by)) + 0.5 }, 4, RULE_PIP, 0, ink);
    }
}

test "mouse menus share drawn rows and scrolling keeps long menus reachable" {
    for (display.SIZES) |screen| {
        var m = Menu{};
        for (0..6) |i| {
            const p = raster.middleAt(rowBox(screen, window(screen.y, 6, m.at), i));
            try std.testing.expectEqual(@as(?usize, null), m.stepAt(&.{ .pointer = p, .mouse_moved = true }, 6, screen));
            try std.testing.expectEqual(i, m.at);
            try std.testing.expectEqual(@as(?usize, i), m.stepAt(&.{ .pointer = p, .click = true }, 6, screen));
            _ = m.stepAt(&.{ .pointer = p, .walk = .s }, 6, screen);
            try std.testing.expectEqual((i + 1) % 6, m.at);
        }
        _ = m.stepAt(&.{ .scroll = -100 }, 40, screen);
        try std.testing.expectEqual(@as(usize, 39), m.at);
        const win = window(screen.y, 40, m.at);
        const p = raster.middleAt(rowBox(screen, win, win.from));
        try std.testing.expectEqual(@as(?usize, win.from), m.stepAt(&.{ .pointer = p, .click = true }, 40, screen));
        try std.testing.expectEqual(@as(?usize, null), m.stepAt(&.{ .pointer = .{ .x = 1, .y = 1 }, .click = true }, 40, screen));
        try std.testing.expect(backedAt(&.{ .pointer = raster.middleAt(footerBox(screen)), .click = true }, screen));
        try std.testing.expect(backed(&.{ .right_click = true }));
    }
    var empty = Menu{};
    try std.testing.expectEqual(@as(?usize, null), empty.stepAt(&.{ .click = true }, 0, display.SCREEN_720));
}

test "a long menu shows the rows that fit, the one it is on among them" {
    const w = window(900, 40, 39);
    try std.testing.expect(w.len < 40 and w.from + w.len == 40);
    try std.testing.expectEqual(@as(usize, 0), window(900, 40, 0).from);
    try std.testing.expectEqual(@as(usize, 3), window(900, 3, 2).len);
}

test "the menu walks round its rows and picks the one it is on" {
    var m = Menu{};
    var st = input.State{ .walk = .n };
    try std.testing.expectEqual(@as(?usize, null), m.step(&st, 3));
    try std.testing.expectEqual(@as(usize, 2), m.at);
    st = .{ .walk = .s };
    _ = m.step(&st, 3);
    _ = m.step(&st, 3);
    try std.testing.expectEqual(@as(usize, 1), m.at);
    st = .{};
    st.pressed.insert(CONFIRM);
    try std.testing.expectEqual(@as(?usize, 1), m.step(&st, 3));
}
