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
const PAD: i32 = 28;
const BODY: i32 = 24;
const LEADING: i32 = 36;
const NUMBER_W: i32 = 32;
const TALK_VEIL = look.fade(look.BG, 0.45);
const FIGURE_BOX: i32 = 140;
const FIGURE_GAP: i32 = 20;
const FIGURE_INSET: i32 = 6;
const FIGURE_GLYPH: i32 = 96;
const FIGURE_WELL_A: f32 = 0.7;
/// The prose keeps this much width, or the figure is left out.
const TEXT_MIN_W: i32 = 420;

/// Whom the hero is speaking with, drawn beside the words.
pub const Figure = struct {
    tex: ?rl.Texture2D = null,
    glyph: look.Look = look.NPC,

    /// The NPC spoken to, unless the line names another speaker.
    pub fn of(art: *const sprite.Sprites, npc: *const script.Npc, ln: *const script.Line) ?Figure {
        if (ln.who.n > 0 and !ln.who.eql(npc.called())) return null;
        const k = npc.looks orelse return .{};
        return .{ .tex = art.body(k), .glyph = look.body(k) };
    }
};

pub const View = struct {
    who: []const u8,
    say: []const u8,
    choices: []const []const u8,
    cursor: usize,
    prompt: prompt_icon.Prompt,
    figure: ?Figure = null,
    ending: bool = false,
};

pub const Layout = struct {
    panel: rl.Rectangle = undefined,
    text_x: i32 = 0,
    text_w: i32 = 0,
    figure: ?rl.Rectangle = null,
    rows: [script.MAX_CHOICES]rl.Rectangle = undefined,
    row_n: usize = 0,
    action: rl.Rectangle = undefined,
    content: rl.Rectangle = undefined,
    starts: [script.MAX_CHOICES]usize = undefined,
    ends: [script.MAX_CHOICES]usize = undefined,
    line_n: usize = 0,
    last: usize = 0,
    who_y: i32 = 0,
    who_rule_y: i32 = 0,
    text_y: i32 = 0,

    pub fn of(self: *Layout, face: anytype, screen: P, v: View) void {
        const w = @max(1, @min(WIDTH, screen.x - 2 * MARGIN));
        const pictured = v.figure != null and w - 2 * PAD - FIGURE_BOX - FIGURE_GAP >= TEXT_MIN_W;
        const column: i32 = if (pictured) FIGURE_BOX + FIGURE_GAP else 0;
        self.text_w = w - 2 * PAD - column;
        self.line_n = countLines(face, v.say, self.text_w);
        self.row_n = @min(v.choices.len, script.MAX_CHOICES);
        const header: i32 = font.HEAD_LINE + 24;
        const footer: i32 = 20 + menu.ACTION_BOX.y;
        const cap_h = @min(@divTrunc(screen.y * 2, 3), screen.y - 2 * MARGIN);
        const capacity: usize = @intCast(@max(1, @divTrunc(cap_h - 2 * PAD - header - footer, LEADING)));
        var total = self.line_n;
        if (self.row_n > 0) total += 1;
        for (v.choices[0..self.row_n], 0..) |label, i| {
            self.starts[i] = total;
            total += @max(1, countLines(face, label, self.text_w - NUMBER_W));
            self.ends[i] = total;
        }
        self.last = @min(total, capacity);
        const visible: i32 = @intCast(@min(@max(total, 3), capacity));
        const h = 2 * PAD + header + visible * LEADING + footer;
        const x = @divTrunc(screen.x - w, 2);
        const y = @max(MARGIN, screen.y - @max(104, @divTrunc(screen.y, 8)) - h);
        self.panel = raster.rect(x, y, w, h);
        self.figure = if (pictured) raster.rect(x + PAD, y + PAD, FIGURE_BOX, FIGURE_BOX) else null;
        self.text_x = x + PAD + column;
        self.who_y = y + PAD;
        self.who_rule_y = self.who_y + font.HEAD_LINE + 10;
        self.text_y = y + PAD + header;
        self.content = raster.rect(self.text_x - 10, self.text_y - 4, self.text_w + 20, visible * LEADING + 8);
        for (0..self.row_n) |i| {
            const start = self.starts[i];
            const end = @min(self.last, self.ends[i]);
            self.rows[i] = if (end > start)
                raster.rect(self.text_x - 10, self.text_y + @as(i32, @intCast(start)) * LEADING - 4, self.text_w + 20, @as(i32, @intCast(end - start)) * LEADING - 2)
            else
                raster.rect(0, 0, 0, 0);
        }
        self.action = raster.rect(x + w - PAD - menu.ACTION_BOX.x, y + h - PAD - menu.ACTION_BOX.y, menu.ACTION_BOX.x, menu.ACTION_BOX.y);
    }

    pub fn rowAt(self: *const Layout, p: P) ?usize {
        for (self.rows[0..self.row_n], 0..) |r, i| {
            if (r.height > 0 and raster.holds(r, p)) return i;
        }
        return null;
    }
};

pub fn draw(face: *const font.Face, sprites: *const sprite.Sprites, screen: P, v: View, l: *const Layout) void {
    var buf: [script.WHO_MAX + 32]u8 = undefined;
    rl.drawRectangle(0, 0, screen.x, screen.y, TALK_VEIL);
    rl.drawRectangleRec(l.panel, look.fade(look.BG, 0.96));
    sprite.backingIn(sprites, l.panel);
    if (l.figure) |r| drawFigure(face, r, v.figure.?);
    const who = if (v.who.len > 0) v.who else "Conversation";
    face.engraved(face.fit(&buf, who, font.HEAD, l.text_w - 110, false), l.text_x, l.who_y, font.HEAD, look.UI_GOLD);
    rl.drawRectangle(l.text_x, l.who_rule_y, l.text_w, 1, look.fade(look.UI_GOLD, look.FADED_A));
    drawPassage(face, v.say, l.text_x, l.text_w, 0, l, look.TEXT);
    for (l.rows[0..l.row_n], v.choices[0..l.row_n], 0..) |r, label, i| {
        if (r.height == 0) continue;
        const on = i == v.cursor;
        menu.boxed(r, look.fade(if (on) look.UI_GOLD else look.BG, if (on) 0.12 else 0.35), look.fade(if (on) look.UI_GOLD else look.EDGE, 0.65));
        if (on) rl.drawRectangle(raster.left(r), raster.top(r), 3, @intFromFloat(r.height), look.UI_GOLD);
        face.text(std.fmt.bufPrintZ(&buf, "{d}.", .{i + 1}) catch "", l.text_x, raster.top(r) + 4, BODY, look.UI_GOLD);
        drawPassage(face, label, l.text_x + NUMBER_W, l.text_w - NUMBER_W, l.starts[i], l, if (on) look.UI_FOCUS else look.TEXT);
    }
    menu.action(face, l.action, v.prompt, if (l.row_n > 0) "Reply" else if (v.ending) "Leave" else "Continue");
}

fn drawPassage(face: *const font.Face, body: []const u8, x: i32, w: i32, start: usize, l: *const Layout, ink: rl.Color) void {
    var offset: usize = 0;
    var line = start;
    var buf: [font.WRAP_COLS_MAX + 1]u8 = undefined;
    while (nextLine(face, body, &offset, w, &buf)) |text| : (line += 1) {
        if (line >= l.last) break;
        face.text(text, x, l.text_y + @as(i32, @intCast(line)) * LEADING, BODY, ink);
    }
}

fn countLines(face: anytype, body: []const u8, w: i32) usize {
    var offset: usize = 0;
    var n: usize = 0;
    var buf: [font.WRAP_COLS_MAX + 1]u8 = undefined;
    while (nextLine(face, body, &offset, w, &buf) != null) n += 1;
    return n;
}

fn nextLine(face: anytype, body: []const u8, offset: *usize, w: i32, buf: *[font.WRAP_COLS_MAX + 1]u8) ?[:0]const u8 {
    if (offset.* >= body.len) return null;
    const rest = body[offset.*..];
    const newline = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    const cap = @min(newline, font.WRAP_COLS_MAX);
    @memcpy(buf[0..cap], rest[0..cap]);
    buf[cap] = 0;
    var lo: usize = 0;
    var hi: usize = cap;
    while (lo < hi) {
        const mid = lo + (hi - lo + 1) / 2;
        const held = buf[mid];
        buf[mid] = 0;
        const fits = face.width(buf[0..mid :0], BODY) <= w;
        buf[mid] = held;
        if (fits) lo = mid else hi = mid - 1;
    }
    var n = if (cap > 0) @max(1, lo) else 0;
    if (n < newline) {
        if (std.mem.lastIndexOfScalar(u8, rest[0..n], ' ')) |space| if (space > 0) {
            n = space;
        };
    }
    offset.* += n;
    if (n == newline and offset.* < body.len) {
        offset.* += 1;
    } else {
        while (offset.* < body.len and body[offset.*] == ' ') offset.* += 1;
    }
    buf[n] = 0;
    return buf[0..n :0];
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

test "an oversized line clips inside the raised panel rather than splitting into pages" {
    const face = menu.TestFace{};
    var l: Layout = .{};
    const longest = "a word " ** (script.SAY_MAX / 7);
    const asks = [_][]const u8{"y" ** script.ASK_MAX} ** script.MAX_CHOICES;
    const display = @import("../core/window.zig");
    for ([_]P{ display.SCREEN_720, display.SCREEN_1080, .{ .x = 800, .y = 600 } }) |screen| {
        for ([_]?Figure{ null, .{} }) |figure| {
            l.of(&face, screen, .{ .who = "w" ** script.WHO_MAX, .say = longest, .choices = &asks, .cursor = 0, .prompt = .{ .key = "Enter" }, .figure = figure });
            try std.testing.expect(l.panel.y >= 0 and l.panel.y + l.panel.height <= @as(f32, @floatFromInt(screen.y)));
            try std.testing.expect(l.action.y + l.action.height <= l.panel.y + l.panel.height);
            try std.testing.expect(l.line_n > l.last);
            try std.testing.expect(l.line_n > font.WRAP_LINES_MAX);
            try std.testing.expect(l.panel.y + l.panel.height <= @as(f32, @floatFromInt(screen.y - 100)));
            for (l.rows[0..l.row_n]) |r| if (r.height > 0) {
                try std.testing.expect(r.y >= l.content.y and r.y + r.height <= l.action.y);
            };
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
