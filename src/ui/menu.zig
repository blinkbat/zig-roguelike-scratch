const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");

pub const CONFIRM = input.Button.a;
pub const BACK = input.Button.b;
pub const PAUSE = input.Button.pause;

pub const TITLE: i32 = 60;
const ROW: i32 = 30;
const ROW_STEP: i32 = 46;
pub const NOTE: i32 = font.BODY;
const TITLE_DY: i32 = -60;
const ROWS_DY: i32 = 20;
const NOTE_GAP: i32 = 30;
const LEGEND_DY: i32 = 60;
const MARK_GAP: i32 = 18;
const MARK_L = ">";
const MARK_R = "<";
/// `draw`'s, from the title's top to the first row, and from under the last row to the legend's foot.
const ABOVE: i32 = TITLE - TITLE_DY + ROWS_DY;
const BELOW: i32 = NOTE_GAP + LEGEND_DY + NOTE;
/// The rows sit at the middle, so either side takes the more of the two.
const CHROME_H: i32 = 2 * @as(i32, @max(ABOVE, BELOW));
pub const NOTE_MAX: usize = 160;
pub const SEP = "   ";
pub const CARET = "_";

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

        pub fn text(self: *const Self) [:0]const u8 {
            return self.buf[0..self.n :0];
        }
    };
}

pub const Conjunction = enum { @"and", @"or" };

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

pub fn moveItem(comptime d: input.Device) [:0]const u8 {
    return input.moveName(d) ++ " move";
}

pub const BACK_LABEL = "back";

/// `backed` takes either; the keyboard's B is a key nobody reaches for.
pub fn backName(comptime d: input.Device) [:0]const u8 {
    return switch (d) {
        .pad => BACK.name(d),
        .keys => PAUSE.name(d),
    };
}

pub fn backItem(comptime d: input.Device) [:0]const u8 {
    return backName(d) ++ " " ++ BACK_LABEL;
}

fn legendOf(comptime d: input.Device) [:0]const u8 {
    return CONFIRM.name(d) ++ " select" ++ SEP ++ moveItem(d);
}

fn window(screen_h: i32, n: usize, at: usize) struct { from: usize, len: usize } {
    const room: usize = @intCast(@max(1, @divTrunc(screen_h - CHROME_H, ROW_STEP)));
    const len = @min(n, room);
    const from = @min(at -| len / 2, n - len);
    return .{ .from = from, .len = len };
}

pub fn draw(face: font.Face, screen: mathx.P, d: input.Device, title: [:0]const u8, all: []const [:0]const u8, at: usize, note: ?[:0]const u8, back: ?[:0]const u8) void {
    const win = window(screen.y, all.len, at);
    const rows = all[win.from..][0..win.len];
    const top = @divTrunc(screen.y, 2) - @divTrunc(@as(i32, @intCast(rows.len)) * ROW_STEP, 2);
    mid(face, screen, title, top + TITLE_DY - TITLE, TITLE, look.TEXT);
    const mark_w = face.width(MARK_L, ROW);
    const widest = screen.x - 2 * (MARK_GAP * 2 + mark_w);
    var fit_buf: [NOTE_MAX + 1]u8 = undefined;
    for (rows, win.from..) |whole, i| {
        const r = face.fit(&fit_buf, whole, ROW, widest, false);
        const y = top + ROWS_DY + @as(i32, @intCast(i - win.from)) * ROW_STEP;
        const on = i == at;
        const w = face.width(r, ROW);
        const x = @divTrunc(screen.x - w, 2);
        face.text(r, x, y, ROW, if (on) look.RETICLE else look.DIM);
        if (on) {
            face.text(MARK_L, x - MARK_GAP - mark_w, y, ROW, look.RETICLE);
            face.text(MARK_R, x + w + MARK_GAP, y, ROW, look.RETICLE);
        }
    }
    var y = top + ROWS_DY + @as(i32, @intCast(rows.len)) * ROW_STEP + NOTE_GAP;
    if (note) |n| {
        mid(face, screen, n, y, NOTE, look.DIM);
        y += NOTE_GAP;
    }
    var buf: [NOTE_MAX + 1]u8 = undefined;
    const plain = input.per(d, legendOf);
    const legend = if (back) |b| std.fmt.bufPrintZ(&buf, "{s}" ++ SEP ++ "{s} {s}", .{ plain, input.per(d, backName), b }) catch plain else plain;
    mid(face, screen, legend, y + LEGEND_DY - NOTE_GAP, NOTE, look.DIM);
}

/// Printed into `buf` upper-cased, as a title is; empty if it does not fit.
pub fn shout(buf: []u8, comptime fmt: []const u8, args: anytype) [:0]const u8 {
    const s = std.fmt.bufPrintZ(buf, fmt, args) catch return "";
    _ = std.ascii.upperString(buf[0..s.len], s);
    return s;
}

/// `shout` for a string known at compile time; call it `comptime`.
pub fn caps(comptime s: []const u8) [:0]const u8 {
    var b: [s.len:0]u8 = undefined;
    _ = std.ascii.upperString(&b, s);
    const out = b;
    return &out;
}

/// "Rat" from "rat"; call it `comptime`.
pub fn capital(comptime s: [:0]const u8) [:0]const u8 {
    comptime var c: [s.len:0]u8 = s[0..s.len].*;
    c[0] = std.ascii.toUpper(c[0]);
    const out = c;
    return &out;
}

/// An enum value's tag, `capital`ised: a row's label.
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
    face.text(t, face.leftFor(t, @divTrunc(screen.x, 2), size), y, size, col);
}

test "a long menu shows the rows that fit, the one it is on among them" {
    const w = window(900, 40, 39);
    std.debug.print("40 rows on a 900 px screen: {d} shown, from {d}\n", .{ w.len, w.from });
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
