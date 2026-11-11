const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const font = @import("../gfx/font.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const script = @import("../map/script.zig");
const menu = @import("menu.zig");

const ENTRY_GAP: i32 = 14;
const LINE_MAX: usize = @max(script.TITLE_MAX, script.NOTE_MAX) + 1;
pub const NONE = "No quests yet.";

pub const Entry = struct { title: []const u8, asks: []const u8, done: bool };

pub const Journal = struct {
    entries: []const Entry = &.{},
    last_top: usize = 0,

    pub fn of(face: anytype, entries: []const Entry, box: rl.Rectangle) Journal {
        const w: i32 = @intFromFloat(box.width);
        var room: i32 = @intFromFloat(box.height);
        var top = entries.len;
        while (top > 0) {
            room -= entryHeight(face, entries[top - 1], w);
            if (room < 0 and top < entries.len) break;
            top -= 1;
        }
        return .{ .entries = entries, .last_top = top };
    }

    pub fn scroll(self: Journal, top: usize, st: *const input.State) usize {
        const by = -st.scroll + (if (st.walk) |d| d.delta().y else 0);
        return @min(mathx.nudge(top, by, self.entries.len), self.last_top);
    }
};

fn underWay(e: Entry) bool {
    return !e.done and e.asks.len > 0;
}

fn entryHeight(face: anytype, e: Entry, w: i32) i32 {
    const n: i32 = if (underWay(e)) @intCast(font.lineCount(face, e.asks, font.BODY, w)) else 0;
    return font.BODY_LINE * (1 + n) + ENTRY_GAP;
}

pub fn draw(face: *const font.Face, entries: []const Entry, top: usize, box: rl.Rectangle) void {
    const x: i32 = @intFromFloat(box.x);
    const w: i32 = @intFromFloat(box.width);
    const bottom = raster.bottom(box);
    const first: i32 = @intFromFloat(box.y);
    var y = first;
    if (entries.len == 0) return face.text(NONE, x, y, font.BODY, look.DIM);
    var fit: [LINE_MAX]u8 = undefined;
    for (entries[@min(top, entries.len - 1)..]) |e| {
        if (y > first and y + entryHeight(face, e, w) - ENTRY_GAP > bottom) break;
        face.text(face.fit(&fit, e.title, font.BODY, w, false), x, y, font.BODY, if (e.done) look.DIM else look.UI_GOLD);
        y += font.BODY_LINE;
        if (underWay(e)) y = face.paragraphWith(font.Face.text, e.asks, x, y, w, font.BODY, look.TEXT);
        y += ENTRY_GAP;
    }
}

test "every quest is reached by walking and the wheel, and scrolling stops at the last screenful" {
    const face = menu.TestFace{};
    const box = rl.Rectangle{ .x = 0, .y = 0, .width = 600, .height = 400 };
    const long = Entry{ .title = "Quest", .asks = "a word " ** (script.NOTE_MAX / 7), .done = false };
    const entries = [_]Entry{long} ** script.MAX_QUESTS;
    const j = Journal.of(&face, &entries, box);
    try std.testing.expect(j.last_top > 0 and j.last_top < entries.len);
    var tail: i32 = 0;
    for (entries[j.last_top..]) |e| tail += entryHeight(&face, e, 600);
    try std.testing.expect(tail <= 400 and tail + entryHeight(&face, entries[j.last_top - 1], 600) > 400);
    for ([_]input.State{ .{ .walk = .s }, .{ .scroll = -1 } }) |st| {
        var top: usize = 0;
        for (0..entries.len) |_| top = j.scroll(top, &st);
        try std.testing.expectEqual(j.last_top, top);
        try std.testing.expectEqual(@as(usize, 0), j.scroll(top, &.{ .scroll = 100 }));
    }
    const short = [_]Entry{.{ .title = "Done", .asks = "", .done = true }} ** 3;
    const fits = Journal.of(&face, &short, box);
    try std.testing.expectEqual(@as(usize, 0), fits.last_top);
    try std.testing.expectEqual(@as(usize, 0), fits.scroll(0, &.{ .walk = .s }));
    try std.testing.expectEqual(@as(usize, 0), Journal.of(&face, &.{}, box).last_top);
}
