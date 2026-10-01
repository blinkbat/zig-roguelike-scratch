const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");

pub const CONFIRM = input.Button.a;
pub const BACK = input.Button.b;

pub const TITLE: i32 = 60;
const ROW: i32 = 30;
const ROW_STEP: i32 = 46;
pub const NOTE: i32 = 20;
const TITLE_DY: i32 = -60;
const ROWS_DY: i32 = 20;
const NOTE_GAP: i32 = 30;
const LEGEND_DY: i32 = 60;
const MARK_GAP: i32 = 18;
pub const NOTE_MAX: usize = 160;
/// Between the items of a legend or crib.
pub const SEP = "   ";

/// A column of rows, walked with the d-pad and picked with A.
pub const Menu = struct {
    at: usize = 0,

    /// The row picked this frame.
    pub fn step(self: *Menu, st: *const input.State, n: usize) ?usize {
        self.at = @min(self.at, n - 1);
        if (st.walk) |d| {
            const dy = d.delta().y;
            if (dy < 0) self.at = (self.at + n - 1) % n;
            if (dy > 0) self.at = (self.at + 1) % n;
        }
        return if (st.hit(CONFIRM)) self.at else null;
    }
};

const LEGEND = CONFIRM.caption() ++ " select" ++ SEP ++ input.MOVE_CAPTION ++ " move";

/// Centred on the screen, the row at `at` marked.
pub fn draw(face: font.Face, screen: mathx.P, title: [:0]const u8, rows: []const [:0]const u8, at: usize, note: ?[]const u8, back: ?[:0]const u8) void {
    const top = @divTrunc(screen.y, 2) - @divTrunc(@as(i32, @intCast(rows.len)) * ROW_STEP, 2);
    mid(face, screen, title, top + TITLE_DY - TITLE, TITLE, look.TEXT);
    for (rows, 0..) |r, i| {
        const y = top + ROWS_DY + @as(i32, @intCast(i)) * ROW_STEP;
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
        var buf: [NOTE_MAX + 1]u8 = undefined;
        mid(face, screen, std.fmt.bufPrintZ(&buf, "{s}", .{n}) catch "", y, NOTE, look.DIM);
        y += NOTE_GAP;
    }
    var buf: [96]u8 = undefined;
    const legend = if (back) |b| std.fmt.bufPrintZ(&buf, LEGEND ++ SEP ++ "{s} {s}", .{ BACK.caption(), b }) catch LEGEND else LEGEND;
    mid(face, screen, legend, y + LEGEND_DY - NOTE_GAP, NOTE, look.DIM);
}

/// Centred across the screen.
pub fn mid(face: font.Face, screen: mathx.P, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    face.text(s, @divTrunc(screen.x - face.width(s, size), 2), y, size, col);
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
