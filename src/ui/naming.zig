const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const hero = @import("../play/hero.zig");
const stage = @import("stage.zig");

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
const FIELD_Y: i32 = 68;
const GRID_Y: i32 = 136;
const GRID_W: i32 = @max(@as(i32, COLS) * KEY_W, @as(i32, LAST.len) * WIDE_W);
const CONTENT_H: i32 = GRID_Y + @as(i32, ROWS) * KEY_H;
const CARET = menu.CARET;
const AT_DONE = Entry{ .row = ROWS - 1, .col = DONE_AT };

fn keyBox(screen: mathx.P, row: usize, col: usize) rl.Rectangle {
    const width: i32 = if (row < LETTERS.len) KEY_W else WIDE_W;
    const count: i32 = @intCast(Entry.width(row));
    const content = contentBox(screen);
    return raster.rect(@as(i32, @intFromFloat(content.x)) + @divTrunc(GRID_W - count * width, 2) + @as(i32, @intCast(col)) * width, @as(i32, @intFromFloat(content.y)) + GRID_Y + @as(i32, @intCast(row)) * KEY_H, width, KEY_H);
}

fn contentBox(screen: mathx.P) rl.Rectangle {
    const column = raster.rect(0, 0, GRID_W, CONTENT_H);
    const body = stage.besideBounds(raster.rect(0, GRID_Y, GRID_W, @as(i32, ROWS) * KEY_H), screen);
    const left = @min(column.x, body.x);
    const top = @min(column.y, body.y);
    const right = @max(column.x + column.width, body.x + body.width);
    const bottom = @max(column.y + column.height, body.y + body.height);
    return .{ .x = @round((@as(f32, @floatFromInt(screen.x)) - (right - left)) / 2 - left), .y = @round((@as(f32, @floatFromInt(screen.y)) - (bottom - top)) / 2 - top), .width = column.width, .height = column.height };
}

/// The letter grid's bounds: its widest rows across, every row down.
pub fn gridBox(screen: mathx.P) rl.Rectangle {
    const content = contentBox(screen);
    return .{ .x = content.x, .y = content.y + GRID_Y, .width = GRID_W, .height = @as(i32, ROWS) * KEY_H };
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
        self.row = AT_DONE.row;
        self.col = AT_DONE.col;
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
    const at = if (device == .keys and !e.pointer_selected) AT_DONE else e.*;
    const content = contentBox(screen);
    rl.beginMode2D(.{ .target = .{ .x = 0, .y = 0 }, .offset = .{ .x = content.x, .y = content.y }, .rotation = 0, .zoom = 1 });
    const column = mathx.P{ .x = GRID_W, .y = CONTENT_H };
    menu.pageHeading(face, column, title, 0);
    var buf: [hero.Name.MAX + CARET.len + 1]u8 = undefined;
    menu.mid(face, column, std.fmt.bufPrintZ(&buf, "{s}" ++ CARET, .{e.name.text()}) catch "", FIELD_Y, FIELD, look.UI_FOCUS);
    rl.endMode2D();
    for (0..ROWS) |r| {
        for (0..Entry.width(r)) |c| {
            const box = keyBox(screen, r, c);
            const centre = raster.middleAt(box);
            const on = r == at.row and c == at.col;
            if (on) rl.drawRectangleRec(box, look.PICK_BG);
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
    const screens = @import("../core/window.zig").SCREENS;
    for (screens) |screen| {
        var e = Entry{};
        const keys = [_][2]usize{ .{ 0, 0 }, .{ 2, 1 }, .{ 4, 0 }, .{ 0, 2 }, .{ 4, 1 } };
        for (keys) |k| {
            const st = input.State{ .device = .keys, .click = true, .pointer = raster.middleAt(keyBox(screen, k[0], k[1])) };
            try std.testing.expectEqual(@as(?Outcome, null), e.stepAt(&st, screen));
        }
        try std.testing.expectEqualStrings("Ab ", e.name.text());
        try std.testing.expectEqual(@as(?Outcome, .done), e.stepAt(&.{ .device = .keys, .click = true, .pointer = raster.middleAt(keyBox(screen, AT_DONE.row, AT_DONE.col)) }, screen));
        try std.testing.expectEqual(@as(?Outcome, .back), e.stepAt(&.{ .right_click = true }, screen));
        try std.testing.expectEqual(@as(?Outcome, .back), e.stepAt(&.{ .click = true, .pointer = raster.middleAt(menu.footerBox(screen, false)) }, screen));
    }
    std.debug.print("mouse naming: five text edits, Done with keyboard prompts and both back controls at {d} resolutions\n", .{screens.len});
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
    var blank = AT_DONE;
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
