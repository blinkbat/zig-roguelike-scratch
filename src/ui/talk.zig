const sprite = @import("../gfx/sprites.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const font = @import("../gfx/font.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const script = @import("../map/script.zig");
const menu = @import("menu.zig");
const P = mathx.P;

const WIDTH: i32 = 1040;
const MARGIN: i32 = 24;
const PAD: i32 = 22;
const RULE_GAP: i32 = 10;
const ROW_H: i32 = font.BODY_LINE + 10;
const ROW_INSET: i32 = 8;
const TALK_VEIL = look.fade(look.BG, 0.45);
const CHOICES_RULE_A: f32 = 0.8;
const LINE_MAX: usize = @max(script.SAY_MAX, script.ASK_MAX) + 8;
const FIGURE_BOX: i32 = 140;
const FIGURE_GAP: i32 = 20;
const FIGURE_INSET: i32 = 6;
const FIGURE_GLYPH: i32 = 96;
const FIGURE_WELL_A: f32 = 0.7;
/// The prose keeps this much width, or the figure is left out.
const TEXT_MIN_W: i32 = 420;

/// Whom the hero is speaking with, drawn beside the words.
pub const Figure = struct { tex: ?rl.Texture2D = null, glyph: look.Look = look.NPC };

pub const View = struct {
    who: []const u8,
    say: []const u8,
    choices: []const []const u8,
    cursor: usize,
    prompt: prompt_icon.Prompt,
    figure: ?Figure = null,
};

pub const Layout = struct {
    panel: rl.Rectangle,
    text_x: i32,
    text_w: i32,
    figure: ?rl.Rectangle = null,
    rows: [script.MAX_CHOICES]rl.Rectangle = undefined,
    row_n: usize = 0,
    action: rl.Rectangle,
    wrapped: font.Wrapped = undefined,
    lines: [font.WRAP_LINES_MAX][:0]const u8 = undefined,
    line_n: usize = 0,
    who_y: i32 = 0,
    who_rule_y: i32 = 0,
    text_y: i32 = 0,
    choices_rule_y: i32 = 0,

    pub fn of(self: *Layout, face: anytype, screen: P, v: View) void {
        const w = @max(1, @min(WIDTH, screen.x - 2 * MARGIN));
        const pictured = v.figure != null and w - 2 * PAD - FIGURE_BOX - FIGURE_GAP >= TEXT_MIN_W;
        const column: i32 = if (pictured) FIGURE_BOX + FIGURE_GAP else 0;
        self.text_w = w - 2 * PAD - column;
        self.line_n = font.wrap(face, v.say, font.BODY, self.text_w, &self.wrapped, &self.lines);
        self.row_n = @min(v.choices.len, script.MAX_CHOICES);
        var down: i32 = PAD;
        const who_rule = down + font.HEAD_LINE + RULE_GAP;
        if (v.who.len > 0) down += font.HEAD_LINE + 2 * RULE_GAP;
        const text = down;
        down += @as(i32, @intCast(self.line_n)) * font.BODY_LINE;
        const choices_rule = down + RULE_GAP;
        if (self.row_n > 0) down += 2 * RULE_GAP;
        const rows = down;
        down += @as(i32, @intCast(self.row_n)) * ROW_H;
        const h = @max(down + RULE_GAP + menu.ACTION_BOX.y + PAD, if (pictured) 2 * PAD + FIGURE_BOX else 0);
        const x = @divTrunc(screen.x - w, 2);
        const y = @max(0, screen.y - MARGIN - h);
        self.panel = raster.rect(x, y, w, h);
        self.figure = if (pictured) raster.rect(x + PAD, y + PAD, FIGURE_BOX, FIGURE_BOX) else null;
        self.text_x = x + PAD + column;
        self.who_y = y + PAD;
        self.who_rule_y = y + who_rule;
        self.text_y = y + text;
        self.choices_rule_y = y + choices_rule;
        for (0..self.row_n) |i| {
            self.rows[i] = raster.rect(self.text_x - ROW_INSET, y + rows + @as(i32, @intCast(i)) * ROW_H, self.text_w + 2 * ROW_INSET, ROW_H);
        }
        self.action = raster.rect(x + w - PAD - menu.ACTION_BOX.x, y + h - PAD - menu.ACTION_BOX.y, menu.ACTION_BOX.x, menu.ACTION_BOX.y);
    }

    pub fn rowAt(self: *const Layout, p: P) ?usize {
        for (self.rows[0..self.row_n], 0..) |r, i| {
            if (raster.holds(r, p)) return i;
        }
        return null;
    }
};

pub fn draw(face: *const font.Face, sprites: *const sprite.Sprites, screen: P, v: View, l: *const Layout) void {
    var buf: [LINE_MAX]u8 = undefined;
    rl.drawRectangle(0, 0, screen.x, screen.y, TALK_VEIL);
    sprite.backingIn(sprites, l.panel);
    if (l.figure) |r| drawFigure(face, r, v.figure.?);
    if (v.who.len > 0) {
        face.engraved(std.fmt.bufPrintZ(&buf, "{s}", .{v.who}) catch "", l.text_x, l.who_y, font.HEAD, look.UI_GOLD);
        rl.drawRectangle(l.text_x, l.who_rule_y, l.text_w, 1, look.fade(look.UI_GOLD, look.FADED_A));
    }
    for (l.lines[0..l.line_n], 0..) |line, i| face.text(line, l.text_x, l.text_y + @as(i32, @intCast(i)) * font.BODY_LINE, font.BODY, look.TEXT);
    if (l.row_n > 0) rl.drawRectangle(l.text_x, l.choices_rule_y, l.text_w, 1, look.fade(look.EDGE, CHOICES_RULE_A));
    for (l.rows[0..l.row_n], v.choices[0..l.row_n], 0..) |r, label, i| {
        const on = i == v.cursor;
        menu.band(r, on);
        const row = std.fmt.bufPrintZ(&buf, "{d}. {s}", .{ i + 1, label }) catch "";
        var fit_buf: [LINE_MAX]u8 = undefined;
        face.text(face.fit(&fit_buf, row, font.BODY, l.text_w, false), l.text_x, raster.top(r) + @divTrunc(ROW_H - font.BODY, 2), font.BODY, menu.rowInk(on));
    }
    menu.action(face, l.action, v.prompt, if (l.row_n > 0) "Choose" else "Continue");
}

/// Pixel art at a whole multiple of its size, as large as the well takes.
fn drawFigure(face: *const font.Face, r: rl.Rectangle, f: Figure) void {
    menu.boxed(r, look.fade(look.BG, FIGURE_WELL_A), look.EDGE);
    const inner = FIGURE_BOX - 2 * FIGURE_INSET;
    const t = f.tex orelse {
        const m = raster.middleAt(r);
        face.glyph(f.glyph.ch, m.x, m.y, FIGURE_GLYPH, f.glyph.fg);
        return;
    };
    const scale = @max(1, @divTrunc(inner, @max(t.width, t.height)));
    const w = t.width * scale;
    const h = t.height * scale;
    const x = raster.left(r) + @divTrunc(FIGURE_BOX - w, 2);
    const y = raster.top(r) + FIGURE_BOX - FIGURE_INSET - h;
    raster.blit(t, raster.facing(t, false), raster.rect(x, y, w, h), look.LIT);
}

test "the conversation panel keeps every choice and its action inside the window at the smallest size" {
    const face = menu.TestFace{};
    var l: Layout = .{ .panel = undefined, .text_x = 0, .text_w = 0, .action = undefined };
    const longest = "a word " ** (script.SAY_MAX / 7);
    const asks = [_][]const u8{"y" ** script.ASK_MAX} ** script.MAX_CHOICES;
    const display = @import("../core/window.zig");
    for ([_]P{ display.SCREEN_720, display.SCREEN_1080, .{ .x = 800, .y = 600 } }) |screen| {
        for ([_]?Figure{ null, .{} }) |figure| {
            l.of(&face, screen, .{ .who = "w" ** script.WHO_MAX, .say = longest, .choices = &asks, .cursor = 0, .prompt = .{ .key = "Enter" }, .figure = figure });
            try std.testing.expect(l.panel.y >= 0 and l.panel.y + l.panel.height <= @as(f32, @floatFromInt(screen.y)));
            try std.testing.expect(l.action.y + l.action.height <= l.panel.y + l.panel.height);
            try std.testing.expect(l.rows[l.row_n - 1].y + l.rows[l.row_n - 1].height <= l.action.y);
            try std.testing.expect(l.line_n < font.WRAP_LINES_MAX);
            if (l.figure) |r| try std.testing.expect(r.y + r.height <= l.panel.y + l.panel.height and r.x + r.width < @as(f32, @floatFromInt(l.text_x)));
        }
    }
}

test "a narrow face fills the panel's width before it wraps" {
    const narrow: i32 = 10;
    const w: i32 = 700;
    var wrapped: font.Wrapped = undefined;
    var lines: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
    const n = font.wrap(menu.TestFace{}, "ab " ** 200, narrow, w, &wrapped, &lines);
    try std.testing.expect(n > 1);
    try std.testing.expect(menu.TestFace.width(.{}, lines[0], narrow) > w - 3 * @divTrunc(narrow, 2));
}
