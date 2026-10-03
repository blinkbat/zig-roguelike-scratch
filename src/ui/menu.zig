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
const CHROME_H: i32 = TITLE - TITLE_DY + ROWS_DY + NOTE_GAP * 2 + LEGEND_DY + NOTE * 2;
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

pub const MOVE_ITEM = input.MOVE_CAPTION ++ " move";
pub const BACK_LABEL = "back";
pub const BACK_ITEM = BACK.caption() ++ " " ++ BACK_LABEL;
const LEGEND = CONFIRM.caption() ++ " select" ++ SEP ++ MOVE_ITEM;

fn window(screen_h: i32, n: usize, at: usize) struct { from: usize, len: usize } {
    const room: usize = @intCast(@max(1, @divTrunc(screen_h - CHROME_H, ROW_STEP)));
    const len = @min(n, room);
    const from = @min(at -| len / 2, n - len);
    return .{ .from = from, .len = len };
}

pub fn draw(face: font.Face, screen: mathx.P, title: [:0]const u8, all: []const [:0]const u8, at: usize, note: ?[:0]const u8, back: ?[:0]const u8) void {
    const win = window(screen.y, all.len, at);
    const rows = all[win.from..][0..win.len];
    const top = @divTrunc(screen.y, 2) - @divTrunc(@as(i32, @intCast(rows.len)) * ROW_STEP, 2);
    mid(face, screen, title, top + TITLE_DY - TITLE, TITLE, look.TEXT);
    for (rows, win.from..) |r, i| {
        const y = top + ROWS_DY + @as(i32, @intCast(i - win.from)) * ROW_STEP;
        const on = i == at;
        const w = face.width(r, ROW);
        const x = @divTrunc(screen.x - w, 2);
        face.text(r, x, y, ROW, if (on) look.RETICLE else look.DIM);
        if (on) {
            face.text(">", x - MARK_GAP - face.width(">", ROW), y, ROW, look.RETICLE);
            face.text("<", x + w + MARK_GAP, y, ROW, look.RETICLE);
        }
    }
    var y = top + ROWS_DY + @as(i32, @intCast(rows.len)) * ROW_STEP + NOTE_GAP;
    if (note) |n| {
        mid(face, screen, n, y, NOTE, look.DIM);
        y += NOTE_GAP;
    }
    var buf: [NOTE_MAX + 1]u8 = undefined;
    const legend = if (back) |b| std.fmt.bufPrintZ(&buf, LEGEND ++ SEP ++ "{s} {s}", .{ BACK.caption(), b }) catch LEGEND else LEGEND;
    mid(face, screen, legend, y + LEGEND_DY - NOTE_GAP, NOTE, look.DIM);
}

pub fn toggle(comptime label: []const u8, on: bool) [:0]const u8 {
    return if (on) label ++ ": On" else label ++ ": Off";
}

pub fn mid(face: font.Face, screen: mathx.P, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    face.text(s, face.leftFor(s, @divTrunc(screen.x, 2), size), y, size, col);
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
