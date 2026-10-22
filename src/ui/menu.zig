const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");

pub const CONFIRM = input.CONFIRM;
pub const BACK = input.Button.b;
pub const PAUSE = input.Button.pause;
pub const CHARACTER = input.Button.character;
pub const CHANGE = input.Button.x;
pub const REMOVE = input.Button.y;
pub const RUB = input.Button.x;

pub const TITLE: i32 = 54;
pub const ROW: i32 = 28;
pub const ROW_STEP: i32 = 38;
pub const NOTE: i32 = 18;
const TITLE_DY: i32 = -44;
const ROWS_DY: i32 = 16;
const NOTE_GAP: i32 = 24;
const MARK_GAP: i32 = 14;
const MARK_L = ">";
const MARK_R = "<";
/// `draw`'s, from the title's top to the first row, and from under the last row to the note's foot.
const ABOVE: i32 = TITLE - TITLE_DY + ROWS_DY;
const BELOW: i32 = NOTE_GAP + NOTE;
/// The rows sit at the middle, so either side takes the more of the two.
const CHROME_H: i32 = 2 * @as(i32, @max(ABOVE, BELOW));
pub const NOTE_MAX: usize = 160;
pub const SEP = "   ";
pub const CARET = "_";

/// A surface keeps this far inside the screen; past its own size it grows at `GROWTH` of the room, up to `SCALE_MAX`.
const SURFACE_MARGIN: i32 = 16;
const GROWTH: f32 = 0.5;
const SCALE_MAX: f32 = 1.25;

pub const Surface = struct {
    scale: f32,
    offset: rl.Vector2,

    pub fn of(screen: mathx.P, size: mathx.P) Surface {
        const fit = @min(@as(f32, @floatFromInt(@max(1, screen.x - 2 * SURFACE_MARGIN))) / @as(f32, @floatFromInt(size.x)), @as(f32, @floatFromInt(@max(1, screen.y - 2 * SURFACE_MARGIN))) / @as(f32, @floatFromInt(size.y)));
        return centred(screen, size, if (fit <= 1) fit else @min(SCALE_MAX, 1 + (fit - 1) * GROWTH));
    }

    /// `size` centred at the scale `reference` gets, so a smaller panel's text matches it; shrunk further only to fit.
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

    /// The screen pixel over surface point `p`; `point` undoes it.
    pub fn screenOf(self: Surface, p: rl.Vector2) mathx.P {
        return .{ .x = @intFromFloat(self.offset.x + p.x * self.scale), .y = @intFromFloat(self.offset.y + p.y * self.scale) };
    }

    pub fn begin(self: Surface) void {
        rl.beginMode2D(.{ .target = .{ .x = 0, .y = 0 }, .offset = self.offset, .rotation = 0, .zoom = self.scale });
    }

    /// `begin`, then a panel's card backing across `size`.
    pub fn beginPanel(self: Surface, sprites: *const look.Sprites, size: mathx.P) void {
        self.begin();
        look.hudPanel(sprites, 0, 0, size.x, size.y, look.CARD_BG, look.LIT);
    }

    /// `f` as this surface draws it: scaled, from the mipmapped atlas rather than the native-size ones.
    pub fn faceFor(self: Surface, f: font.Face) font.Face {
        var out = f;
        if (self.scale != 1) out.native = @splat(null);
        return out;
    }

    pub fn clip(self: Surface, r: rl.Rectangle) void {
        rl.beginScissorMode(@intFromFloat(@floor(self.offset.x + r.x * self.scale)), @intFromFloat(@floor(self.offset.y + r.y * self.scale)), @intFromFloat(@ceil(r.width * self.scale)), @intFromFloat(@ceil(r.height * self.scale)));
    }
};

test "panel surfaces stay invertible when the window shrinks below its margins" {
    const size = mathx.P{ .x = 640, .y = 480 };
    const edges = [_]i32{ 0, 1, 2 * SURFACE_MARGIN - 1, 2 * SURFACE_MARGIN, 2 * SURFACE_MARGIN + 1 };
    for (edges) |edge| {
        for ([_]mathx.P{ .{ .x = edge, .y = 720 }, .{ .x = 1280, .y = edge } }) |screen| {
            const surface = Surface.of(screen, size);
            try std.testing.expect(std.math.isFinite(surface.scale) and surface.scale > 0);
            _ = surface.point(.{ .x = 0, .y = 0 });
        }
    }
    std.debug.print("panel surfaces: {d} narrow or short window sizes remain invertible\n", .{edges.len * 2});
}

/// A box's edge, doubled in `on_ink` when it is the one chosen.
pub fn outline(r: rl.Rectangle, on: bool, on_ink: rl.Color, off_ink: rl.Color) void {
    rl.drawRectangleLinesEx(r, if (on) 2 else 1, if (on) on_ink else off_ink);
}

/// Inside an action box, its edge to the prompt and to the label's far side, and the prompt to the label.
const ACTION_PAD: i32 = 10;
pub const PROMPT_GAP: i32 = 8;

pub fn action(face: *const font.Face, r: rl.Rectangle, prompt: look.Prompt, label: [:0]const u8) void {
    rl.drawRectangleRec(r, look.PICK_BG);
    rl.drawRectangleLinesEx(r, 1, look.EDGE);
    const text_x = actionPrompt(face, r, prompt, 1);
    const text_w = @as(i32, @intFromFloat(r.x + r.width)) - ACTION_PAD - text_x;
    face.centred(label, text_x + @divTrunc(text_w, 2), look.middleAt(r).y, font.BODY, look.TEXT);
}

/// An action box's prompt; returns where its label starts.
pub fn actionPrompt(face: *const font.Face, r: rl.Rectangle, prompt: look.Prompt, alpha: f32) i32 {
    return prompt.drawFrom(face, @as(i32, @intFromFloat(r.x)) + ACTION_PAD, look.middleAt(r).y, font.BODY, alpha) + PROMPT_GAP;
}

pub fn Note(comptime N: usize) type {
    return struct {
        const Self = @This();
        buf: [N + 1]u8 = @splat(0),
        n: usize = 0,

        pub fn say(self: *Self, comptime fmt: []const u8, args: anytype) void {
            self.n = (std.fmt.bufPrintZ(&self.buf, fmt, args) catch blk: {
                self.buf[N] = 0;
                break :blk self.buf[0..N];
            }).len;
        }

        pub fn clear(self: *Self) void {
            self.n = 0;
            self.buf[0] = 0;
        }

        pub const Writer = std.io.GenericWriter(*Self, error{NoSpaceLeft}, append);

        /// Appends to the text, as much as fits.
        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        fn append(self: *Self, bytes: []const u8) error{NoSpaceLeft}!usize {
            const n = @min(bytes.len, N - self.n);
            if (n == 0 and bytes.len > 0) return error.NoSpaceLeft;
            @memcpy(self.buf[self.n..][0..n], bytes[0..n]);
            self.n += n;
            self.buf[self.n] = 0;
            return n;
        }

        pub fn text(self: *const Self) [:0]const u8 {
            return self.buf[0..self.n :0];
        }
    };
}

pub const Conjunction = enum { @"and", @"or" };

pub fn joined(comptime names: anytype, comptime last: Conjunction) [:0]const u8 {
    comptime var s: [:0]const u8 = "";
    inline for (names, 0..) |nm, i| s = s ++ listSep(i, names.len, last) ++ nm;
    const out = s;
    return out;
}

pub fn listSep(i: usize, n: usize, last: Conjunction) []const u8 {
    if (i == 0) return "";
    if (i + 1 < n) return ", ";
    return switch (last) {
        .@"and" => " and ",
        .@"or" => " or ",
    };
}

pub const Menu = struct {
    at: usize = 0,

    pub fn step(self: *Menu, st: *const input.State, n: usize) ?usize {
        self.at = @min(self.at, n - 1);
        if (st.walk) |d| self.at = mathx.wrap(self.at, d.delta().y, n);
        return if (st.hit(CONFIRM)) self.at else null;
    }
};

pub fn backed(st: *const input.State) bool {
    return st.hit(BACK) or st.hit(PAUSE);
}

/// Backed out, or Character pressed to shut what it opened over.
pub fn closed(st: *const input.State) bool {
    return backed(st) or st.hit(CHARACTER);
}

/// Sideways distance between boxes costs this much more than distance ahead.
const ACROSS: f32 = 2;

/// The box in `boxes` a move `dir` from `from` lands on: nearest ahead, sideways distance costing `ACROSS` times as much.
pub fn nearest(from: rl.Rectangle, boxes: []const rl.Rectangle, dir: mathx.Dir) ?usize {
    var best: ?usize = null;
    var best_score = std.math.floatMax(f32);
    for (boxes, 0..) |to, i| {
        const score = directionScore(from, to, dir, ACROSS) orelse continue;
        if (score < best_score) {
            best_score = score;
            best = i;
        }
    }
    return best;
}

fn directionScore(from: rl.Rectangle, to: rl.Rectangle, dir: mathx.Dir, across_weight: f32) ?f32 {
    const a = look.middle(from);
    const b = look.middle(to);
    const vx = b.x - a.x;
    const vy = b.y - a.y;
    const d = dir.delta();
    const wx: f32 = @floatFromInt(d.x);
    const wy: f32 = @floatFromInt(d.y);
    const along = vx * wx + vy * wy;
    if (along <= 0) return null;
    return along + across_weight * @abs(vx * wy - vy * wx);
}

pub const Window = struct {
    from: usize,
    len: usize,

    pub fn of(n: usize, at: usize, room: usize) Window {
        const len = @min(n, room);
        return .{ .from = @min(at -| len / 2, n - len), .len = len };
    }
};

fn window(screen_h: i32, n: usize, at: usize) Window {
    const room: usize = @intCast(@max(1, @divTrunc(screen_h - CHROME_H, ROW_STEP)));
    return Window.of(n, at, room);
}

pub fn draw(face: font.Face, screen: mathx.P, title: [:0]const u8, all: []const []const u8, at: usize, note: ?[:0]const u8) void {
    const win = window(screen.y, all.len, at);
    const rows = all[win.from..][0..win.len];
    const top = @divTrunc(screen.y, 2) - @divTrunc(@as(i32, @intCast(rows.len)) * ROW_STEP, 2);
    heading(face, screen, title, top + TITLE_DY - TITLE, TITLE, look.TEXT, look.UI_GOLD);
    const mark_w = face.width(MARK_L, ROW);
    const widest = screen.x - 2 * (MARK_GAP * 2 + mark_w);
    var fit_buf: [NOTE_MAX + 1]u8 = undefined;
    for (rows, win.from..) |whole, i| {
        const r = face.fit(&fit_buf, whole, ROW, widest, false);
        const y = top + ROWS_DY + @as(i32, @intCast(i - win.from)) * ROW_STEP;
        const on = i == at;
        const w = face.width(r, ROW);
        const x = @divTrunc(screen.x - w, 2);
        face.text(r, x, y, ROW, if (on) look.UI_FOCUS else look.DIM);
        if (on) {
            face.text(MARK_L, x - MARK_GAP - mark_w, y, ROW, look.UI_FOCUS);
            face.text(MARK_R, x + w + MARK_GAP, y, ROW, look.UI_FOCUS);
        }
    }
    if (note) |n| mid(face, screen, n, top + ROWS_DY + @as(i32, @intCast(rows.len)) * ROW_STEP + NOTE_GAP, NOTE, look.DIM);
}

/// Printed into `buf` upper-cased, as a title is; empty if it does not fit.
pub fn shout(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    const s = std.fmt.bufPrintZ(buf, fmt, args) catch return "";
    _ = std.ascii.upperString(buf[0..s.len], s);
    return s;
}

/// `shout` for a string known at compile time; call it `comptime`.
pub const caps = input.upper;

/// "Rat" from "rat"; call it `comptime`.
pub fn capital(comptime s: [:0]const u8) [:0]const u8 {
    comptime var c: [s.len:0]u8 = s[0..s.len].*;
    c[0] = std.ascii.toUpper(c[0]);
    const out = c;
    return &out;
}

/// "Burning Arrow" from "burning_arrow"; call it `comptime`.
pub fn titled(comptime s: [:0]const u8) [:0]const u8 {
    comptime var c: [s.len:0]u8 = s[0..s.len].*;
    for (&c, 0..) |*ch, i| {
        if (ch.* == '_') {
            ch.* = ' ';
        } else if (i == 0 or s[i - 1] == '_') ch.* = std.ascii.toUpper(ch.*);
    }
    const out = c;
    return &out;
}

pub fn named(e: anytype) [:0]const u8 {
    return switch (e) {
        inline else => |t| comptime capital(@tagName(t)),
    };
}

pub fn toggle(comptime label: []const u8, on: bool) [:0]const u8 {
    return if (on) label ++ ": On" else label ++ ": Off";
}

pub fn mid(face: font.Face, screen: mathx.P, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    var buf: [NOTE_MAX + 1]u8 = undefined;
    const t = face.fit(&buf, s, size, screen.x - 2 * MARK_GAP, false);
    face.textMid(t, @divTrunc(screen.x, 2), y, size, col);
}

const RULE_REACH: i32 = 56;
const RULE_GAP: i32 = 9;
const RULE_PIP: f32 = 3;
const RULE_A: f32 = 0.7;
/// Of a heading's size, from its top down to its rule.
const RULE_DROP: f32 = 1.02;

/// Engraved and centred, over a rule in `accent`.
pub fn heading(face: font.Face, screen: mathx.P, s: [:0]const u8, y: i32, size: i32, col: rl.Color, accent: rl.Color) void {
    var buf: [NOTE_MAX + 1]u8 = undefined;
    const t = face.fit(&buf, s, size, screen.x - 2 * MARK_GAP, false);
    const cx = @divTrunc(screen.x, 2);
    face.engravedMid(t, cx, y, size, col);
    const half = @min(@divTrunc(face.width(t, size), 2) + RULE_REACH, @divTrunc(screen.x, 2) - MARK_GAP);
    rule(cx, y + @as(i32, @intFromFloat(@as(f32, @floatFromInt(size)) * RULE_DROP)), half, look.fade(accent, RULE_A * look.alphaOf(col)));
}

/// Hairlines fading out either side of a small diamond.
pub fn rule(cx: i32, y: i32, half: i32, col: rl.Color) void {
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

test "a long menu shows the rows that fit, the one it is on among them" {
    const w = window(900, 40, 39);
    std.debug.print("40 rows on a 900 px screen: {d} shown, from {d}\n", .{ w.len, w.from });
    try std.testing.expect(w.len < 40 and w.from + w.len == 40);
    try std.testing.expectEqual(@as(usize, 0), window(900, 40, 0).from);
    try std.testing.expectEqual(@as(usize, 3), window(900, 3, 2).len);
}

test "a note's writer appends what fits and stays terminated" {
    var note: Note(8) = .{};
    note.writer().print("{d} of {d}", .{ 12, 34 }) catch {};
    note.writer().writeAll("overflow") catch {};
    try std.testing.expectEqualStrings("12 of 34", note.text());
    note.clear();
    note.writer().writeAll("ab") catch {};
    try std.testing.expectEqualStrings("ab", note.text());
    std.debug.print("note writer: {d}-byte note truncates and re-terminates after clear\n", .{8});
}

test "a tag is titled word by word" {
    try std.testing.expectEqualStrings("Chain Lightning", comptime titled("chain_lightning"));
    try std.testing.expectEqualStrings("Fireball", comptime titled("fireball"));
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
