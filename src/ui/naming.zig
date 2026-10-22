const std = @import("std");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const hero = @import("../play/hero.zig");

const LETTERS = [_][]const u8{ "ABCDEFGHIJKLM", "NOPQRSTUVWXYZ", "abcdefghijklm", "nopqrstuvwxyz" };
const Key = union(enum) { ch: u8, space, rub, done };
const LAST = [_]Key{ .space, .rub, .done };
const DONE_AT = for (LAST, 0..) |k, i| {
    if (k == .done) break i;
} else unreachable;
const ROWS = LETTERS.len + 1;
const COLS = LETTERS[0].len;

comptime {
    for (LETTERS) |row| std.debug.assert(row.len == COLS);
}

const FIELD: i32 = 30;
const KEY = menu.ROW;
const KEY_W: i32 = 38;
const KEY_H = menu.ROW_STEP;
const WIDE_W: i32 = KEY_W * 4;
const TITLE_DY: i32 = -198;
const FIELD_DY: i32 = -130;
const GRID_DY: i32 = -62;
const CARET = menu.CARET;

fn keyBox(screen: mathx.P, row: usize, col: usize) @import("raylib").Rectangle {
    const width: i32 = if (row < LETTERS.len) KEY_W else WIDE_W;
    const count: i32 = @intCast(Entry.width(row));
    return raster.rect(@divTrunc(screen.x - count * width, 2) + @as(i32, @intCast(col)) * width, @divTrunc(screen.y, 2) + GRID_DY + @as(i32, @intCast(row)) * KEY_H, width, KEY_H);
}

pub const Outcome = enum { done, back };

pub const Entry = struct {
    name: hero.Name = .{},
    row: usize = 0,
    col: usize = 0,
    pointer_selected: bool = false,

    fn width(r: usize) usize {
        return if (r < LETTERS.len) COLS else LAST.len;
    }

    fn key(self: *const Entry) Key {
        if (self.row < LETTERS.len) return .{ .ch = LETTERS[self.row][self.col] };
        return LAST[self.col];
    }

    /// On `done` the name is `name.done()`.
    pub fn step(self: *Entry, st: *const input.State) ?Outcome {
        for (st.typed.text()) |c| {
            if (self.name.push(c)) self.onDone();
        }
        if (st.rub or st.hit(menu.RUB)) self.name.pop();
        if (st.walk) |d| {
            self.pointer_selected = false;
            self.move(d);
        }
        if (menu.backed(st)) return .back;
        if (!st.hit(menu.CONFIRM)) return null;
        return self.press(if (st.device == .keys) .done else self.key());
    }

    fn press(self: *Entry, k: Key) ?Outcome {
        switch (k) {
            .ch => |c| _ = self.name.push(c),
            .space => _ = self.name.push(' '),
            .rub => self.name.pop(),
            .done => if (self.name.done().n > 0) return .done,
        }
        return null;
    }

    pub fn stepAt(self: *Entry, st: *const input.State, screen: mathx.P) ?Outcome {
        if (menu.backedAt(st, screen)) return .back;
        if (st.pointing()) {
            for (0..ROWS) |r| for (0..width(r)) |c| {
                if (raster.holds(keyBox(screen, r, c), st.pointer.?)) {
                    self.row = r;
                    self.col = c;
                    self.pointer_selected = true;
                    if (st.click) return self.press(self.key());
                }
            };
        }
        return self.step(st);
    }

    /// Typed on the keyboard, Enter then means done.
    fn onDone(self: *Entry) void {
        self.pointer_selected = false;
        self.row = ROWS - 1;
        self.col = DONE_AT;
    }

    fn move(self: *Entry, d: mathx.Dir) void {
        const v = d.delta();
        if (v.y != 0) {
            self.row = mathx.wrap(self.row, v.y, ROWS);
            self.col = @min(self.col, width(self.row) - 1);
        }
        if (v.x != 0) self.col = mathx.wrap(self.col, v.x, width(self.row));
    }
};

const ASK = "NAME YOUR ";
pub const TITLE_MAX = blk: {
    var most: usize = 0;
    for (hero.CLASSES) |c| most = @max(most, c.title().len);
    break :blk ASK.len + most + 1;
};

pub fn titleOf(c: hero.Class, buf: *[TITLE_MAX]u8) [:0]const u8 {
    return menu.shout(buf, ASK ++ "{s}", .{c.title()});
}

/// On the keyboard Enter is done, so Done is what is focused.
pub fn draw(e: *const Entry, face: font.Face, screen: mathx.P, title: [:0]const u8, device: input.Device) void {
    const at = if (device == .keys and !e.pointer_selected) Entry{ .row = ROWS - 1, .col = DONE_AT } else e.*;
    const mid = @divTrunc(screen.y, 2);
    menu.heading(face, screen, title, mid + TITLE_DY, menu.TITLE, look.TEXT, look.UI_GOLD);
    var buf: [hero.Name.MAX + CARET.len + 1]u8 = undefined;
    menu.mid(face, screen, std.fmt.bufPrintZ(&buf, "{s}" ++ CARET, .{e.name.text()}) catch "", mid + FIELD_DY, FIELD, look.UI_FOCUS);
    for (0..ROWS) |r| {
        for (0..Entry.width(r)) |c| {
            const box = keyBox(screen, r, c);
            const centre = raster.middleAt(box);
            const on = r == at.row and c == at.col;
            if (on) @import("raylib").drawRectangleRec(box, look.PICK_BG);
            const col = if (on) look.UI_FOCUS else look.DIM;
            if (r < LETTERS.len) {
                face.glyph(LETTERS[r][c], centre.x, centre.y, KEY, col);
                continue;
            }
            const label: [:0]const u8 = switch (LAST[c]) {
                .space => "Space",
                .rub => "Delete",
                .done => "Done",
                .ch => unreachable,
            };
            face.textCentred(label, centre.x, centre.y, KEY, col);
        }
    }
}

test "mouse naming types letters spaces deletes and finishes with keyboard hints active" {
    const screen = mathx.P{ .x = 1280, .y = 720 };
    var e = Entry{};
    const keys = [_][2]usize{ .{ 0, 0 }, .{ 2, 1 }, .{ 4, 0 }, .{ 0, 2 }, .{ 4, 1 } };
    for (keys) |k| {
        const st = input.State{ .device = .keys, .click = true, .pointer = raster.middleAt(keyBox(screen, k[0], k[1])) };
        try std.testing.expectEqual(@as(?Outcome, null), e.stepAt(&st, screen));
    }
    try std.testing.expectEqualStrings("Ab ", e.name.text());
    try std.testing.expectEqual(@as(?Outcome, .done), e.stepAt(&.{ .device = .keys, .click = true, .pointer = raster.middleAt(keyBox(screen, ROWS - 1, DONE_AT)) }, screen));
    try std.testing.expectEqual(@as(?Outcome, .back), e.stepAt(&.{ .right_click = true }, screen));
    try std.testing.expectEqual(@as(?Outcome, .back), e.stepAt(&.{ .click = true, .pointer = raster.middleAt(menu.footerBox(screen, false)) }, screen));
    std.debug.print("mouse naming: five text edits, Done with keyboard prompts, both back controls\n", .{});
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
    st.typed = .{};
    @memcpy(st.typed.buf[0..3], "ron");
    st.typed.n = 3;
    _ = e.step(&st);
    try std.testing.expectEqualStrings("Aaron", e.name.text());
    st = .{};
    st.pressed.insert(menu.CONFIRM);
    try std.testing.expectEqual(@as(?Outcome, .done), e.step(&st));
    var blank = Entry{ .row = ROWS - 1, .col = DONE_AT };
    try std.testing.expectEqual(@as(?Outcome, null), blank.step(&st));
}

test "on the keyboard Enter is done wherever the grid's cursor sits" {
    var e = Entry{ .name = hero.Name.of("Ann") };
    var st = input.State{ .device = .keys };
    st.pressed.insert(menu.CONFIRM);
    try std.testing.expectEqual(@as(?Outcome, .done), e.step(&st));
    try std.testing.expectEqualStrings("Ann", e.name.text());
    var blank = Entry{};
    try std.testing.expectEqual(@as(?Outcome, null), blank.step(&st));
    try std.testing.expectEqualStrings("", blank.name.text());
}
