const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const hero = @import("../play/hero.zig");

// A name typed on a grid of keys with the d-pad, as a console asks for one; the keyboard types straight into it.

const LETTERS = [_][]const u8{ "ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "abcdefghijklm", "nopqrstuvwxyz" };
const Key = union(enum) { ch: u8, space, rub, done };
const LAST = [_]Key{ .space, .rub, .done };
const ROWS = LETTERS.len + 1;
const COLS = LETTERS[0].len;

pub const RUB = input.Button.x;

const FIELD: i32 = 36;
const KEY: i32 = 30;
const KEY_W: i32 = 44;
const KEY_H: i32 = 46;
const WIDE_W: i32 = KEY_W * 4;
const TITLE_DY: i32 = -230;
const FIELD_DY: i32 = -150;
const GRID_DY: i32 = -70;
const LEGEND_DY: i32 = 200;
const CARET = "_";

const LEGEND = menu.CONFIRM.caption() ++ " type" ++ menu.SEP ++ RUB.caption() ++ " delete" ++ menu.SEP ++
    input.MOVE_CAPTION ++ " move" ++ menu.SEP ++ menu.BACK.caption() ++ " back";

pub const Outcome = enum { done, back };

pub const Entry = struct {
    name: hero.Name = .{},
    row: usize = 0,
    col: usize = 0,

    fn width(r: usize) usize {
        return if (r < LETTERS.len) COLS else LAST.len;
    }

    fn key(self: *const Entry) Key {
        if (self.row < LETTERS.len) return .{ .ch = LETTERS[self.row][self.col] };
        return LAST[self.col];
    }

    /// The name, done, once it is confirmed; `back` when backed out of.
    pub fn step(self: *Entry, st: *const input.State) ?Outcome {
        for (st.typed.text()) |c| {
            if (self.name.push(c)) self.onDone();
        }
        if (st.rub or st.hit(RUB)) self.name.pop();
        if (st.walk) |d| self.move(d);
        if (st.hit(menu.BACK) or st.hit(input.Button.pause)) return .back;
        if (!st.hit(menu.CONFIRM)) return null;
        switch (self.key()) {
            .ch => |c| _ = self.name.push(c),
            .space => _ = self.name.push(' '),
            .rub => self.name.pop(),
            .done => if (self.name.done().n > 0) return .done,
        }
        return null;
    }

    /// Typed on the keyboard, Enter then means done.
    fn onDone(self: *Entry) void {
        self.row = ROWS - 1;
        self.col = LAST.len - 1;
    }

    fn move(self: *Entry, d: mathx.Dir) void {
        const v = d.delta();
        if (v.y != 0) {
            self.row = @intCast(@mod(@as(i32, @intCast(self.row)) + v.y, @as(i32, ROWS)));
            self.col = @min(self.col, width(self.row) - 1);
        }
        if (v.x != 0) {
            const w: i32 = @intCast(width(self.row));
            self.col = @intCast(@mod(@as(i32, @intCast(self.col)) + v.x, w));
        }
    }
};

pub fn draw(e: *const Entry, face: font.Face, screen: mathx.P, title: [:0]const u8) void {
    const mid = @divTrunc(screen.y, 2);
    menu.mid(face, screen, title, mid + TITLE_DY, menu.TITLE, look.TEXT);
    var buf: [hero.Name.MAX + CARET.len + 1]u8 = undefined;
    menu.mid(face, screen, std.fmt.bufPrintZ(&buf, "{s}" ++ CARET, .{e.name.text()}) catch "", mid + FIELD_DY, FIELD, look.RETICLE);
    const grid_w: i32 = COLS * KEY_W;
    const x0 = @divTrunc(screen.x - grid_w, 2);
    const y0 = mid + GRID_DY;
    for (0..ROWS) |r| {
        const y = y0 + @as(i32, @intCast(r)) * KEY_H;
        for (0..Entry.width(r)) |c| {
            const on = r == e.row and c == e.col;
            const col = if (on) look.RETICLE else look.DIM;
            if (r < LETTERS.len) {
                face.glyph(LETTERS[r][c], x0 + @as(i32, @intCast(c)) * KEY_W + @divTrunc(KEY_W, 2), y + @divTrunc(KEY_H, 2), KEY, col);
                continue;
            }
            const label: [:0]const u8 = switch (LAST[c]) {
                .space => "Space",
                .rub => "Delete",
                .done => "Done",
                .ch => unreachable,
            };
            const cx = @divTrunc(screen.x, 2) + (@as(i32, @intCast(c)) - 1) * WIDE_W;
            face.text(label, cx - @divTrunc(face.width(label, KEY), 2), y + @divTrunc(KEY_H - KEY, 2), KEY, col);
        }
    }
    menu.mid(face, screen, LEGEND, mid + LEGEND_DY, menu.NOTE, look.DIM);
}

test "the grid types a name, the keyboard types into it, and done waits for a name" {
    var e = Entry{};
    var st = input.State{};
    st.pressed.insert(menu.CONFIRM);
    _ = e.step(&st);
    st = .{ .walk = .s };
    _ = e.step(&st);
    _ = e.step(&st);
    st = .{};
    st.pressed.insert(menu.CONFIRM);
    _ = e.step(&st);
    try std.testing.expectEqualStrings("Aa", e.name.text());
    st = .{};
    st.typed = .{ .buf = "ron".* ++ ([_]u8{0} ** 13), .n = 3 };
    _ = e.step(&st);
    try std.testing.expectEqualStrings("Aaron", e.name.text());
    st = .{};
    st.pressed.insert(menu.CONFIRM);
    try std.testing.expectEqual(@as(?Outcome, .done), e.step(&st));
    var blank = Entry{ .row = ROWS - 1, .col = LAST.len - 1 };
    try std.testing.expectEqual(@as(?Outcome, null), blank.step(&st));
}
