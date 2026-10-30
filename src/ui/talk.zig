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

const WIDTH: i32 = 960;
const MARGIN: i32 = 24;
const PAD: i32 = 22;
const RULE_GAP: i32 = 10;
const ROW_H: i32 = font.BODY_LINE + 10;
const ROW_INSET: i32 = 8;
const HEAD_LINE: i32 = font.HEAD + font.LEADING;
const VEIL = look.fade(look.BG, 0.45);
const LINE_MAX: usize = @max(script.SAY_MAX, script.ASK_MAX) + 8;

/// What the conversation panel shows; `choices` are only those offered.
pub const View = struct {
    who: []const u8,
    say: []const u8,
    choices: []const []const u8,
    cursor: usize,
    prompt: prompt_icon.Prompt,
};

/// Sized to what it holds, growing up off a fixed bottom edge.
pub const Layout = struct {
    panel: rl.Rectangle,
    text_x: i32,
    text_w: i32,
    rows: [script.MAX_CHOICES]rl.Rectangle = undefined,
    row_n: usize = 0,
    action: rl.Rectangle,
    wrapped: font.Wrapped = undefined,
    lines: [font.WRAP_LINES_MAX][:0]const u8 = undefined,
    line_n: usize = 0,

    pub fn of(self: *Layout, face: anytype, screen: P, v: View) void {
        const w = @max(1, @min(WIDTH, screen.x - 2 * MARGIN));
        self.text_w = w - 2 * PAD;
        self.line_n = font.wrap(face, v.say, font.BODY, self.text_w, &self.wrapped, &self.lines);
        self.row_n = @min(v.choices.len, script.MAX_CHOICES);
        var h: i32 = 2 * PAD + RULE_GAP + menu.ACTION_BOX.y;
        if (v.who.len > 0) h += HEAD_LINE + 2 * RULE_GAP;
        h += @as(i32, @intCast(self.line_n)) * font.BODY_LINE;
        if (self.row_n > 0) h += 2 * RULE_GAP + @as(i32, @intCast(self.row_n)) * ROW_H;
        const x = @divTrunc(screen.x - w, 2);
        const y = @max(0, screen.y - MARGIN - h);
        self.panel = raster.rect(x, y, w, h);
        self.text_x = x + PAD;
        var ry = y + PAD;
        if (v.who.len > 0) ry += HEAD_LINE + 2 * RULE_GAP;
        ry += @as(i32, @intCast(self.line_n)) * font.BODY_LINE;
        if (self.row_n > 0) ry += RULE_GAP * 2;
        for (0..self.row_n) |i| {
            self.rows[i] = raster.rect(self.text_x - ROW_INSET, ry + @as(i32, @intCast(i)) * ROW_H, self.text_w + 2 * ROW_INSET, ROW_H);
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

pub fn draw(face: *const font.Face, screen: P, v: View, l: *const Layout) void {
    var buf: [LINE_MAX]u8 = undefined;
    rl.drawRectangle(0, 0, screen.x, screen.y, VEIL);
    rl.drawRectangleRec(l.panel, look.CARD_BG);
    rl.drawRectangleLinesEx(l.panel, 1, look.EDGE);
    var y: i32 = @as(i32, @intFromFloat(l.panel.y)) + PAD;
    if (v.who.len > 0) {
        face.engraved(std.fmt.bufPrintZ(&buf, "{s}", .{v.who}) catch "", l.text_x, y, font.HEAD, look.UI_GOLD);
        y += HEAD_LINE + RULE_GAP;
        rl.drawRectangle(l.text_x, y, l.text_w, 1, look.fade(look.UI_GOLD, 0.35));
        y += RULE_GAP;
    }
    for (l.lines[0..l.line_n]) |line| {
        face.text(line, l.text_x, y, font.BODY, look.TEXT);
        y += font.BODY_LINE;
    }
    if (l.row_n > 0) rl.drawRectangle(l.text_x, y + RULE_GAP, l.text_w, 1, look.fade(look.EDGE, 0.8));
    for (l.rows[0..l.row_n], v.choices[0..l.row_n], 0..) |r, label, i| {
        const on = i == v.cursor;
        if (on) rl.drawRectangleRec(r, look.EDIT_ROW_ON);
        const row = std.fmt.bufPrintZ(&buf, "{d}. {s}", .{ i + 1, label }) catch "";
        var fit_buf: [LINE_MAX]u8 = undefined;
        face.text(face.fit(&fit_buf, row, font.BODY, l.text_w, false), l.text_x, @as(i32, @intFromFloat(r.y)) + @divTrunc(ROW_H - font.BODY, 2), font.BODY, if (on) look.UI_FOCUS else look.DIM);
    }
    menu.action(face, l.action, v.prompt, if (l.row_n > 0) "Choose" else "Continue");
}

test "the conversation panel keeps every choice and its action inside the window at the smallest size" {
    const Fixed = struct {
        pub fn width(_: @This(), s: [:0]const u8, size: i32) i32 {
            return @as(i32, @intCast(s.len)) * @divTrunc(size, 2);
        }
    };
    const face = Fixed{};
    var l: Layout = .{ .panel = undefined, .text_x = 0, .text_w = 0, .action = undefined };
    const longest = "a word " ** (script.SAY_MAX / 7);
    const asks = [_][]const u8{"y" ** script.ASK_MAX} ** script.MAX_CHOICES;
    var checked: usize = 0;
    for ([_]P{ .{ .x = 1280, .y = 720 }, .{ .x = 1920, .y = 1080 }, .{ .x = 800, .y = 600 } }) |screen| {
        l.of(&face, screen, .{ .who = "w" ** script.WHO_MAX, .say = longest, .choices = &asks, .cursor = 0, .prompt = .{ .key = "Enter" } });
        try std.testing.expect(l.panel.y >= 0 and l.panel.y + l.panel.height <= @as(f32, @floatFromInt(screen.y)));
        try std.testing.expect(l.action.y + l.action.height <= l.panel.y + l.panel.height);
        try std.testing.expect(l.rows[l.row_n - 1].y + l.rows[l.row_n - 1].height <= l.action.y);
        checked += 1;
    }
    std.debug.print("conversation panel: {d} window sizes hold {d} wrapped prose lines, {d} choices and the action\n", .{ checked, l.line_n, script.MAX_CHOICES });
}
