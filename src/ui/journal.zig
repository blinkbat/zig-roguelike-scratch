const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const font = @import("../gfx/font.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const shaders = @import("../gfx/shaders.zig");
const menu = @import("menu.zig");
const hud = @import("hud.zig");

pub const Kind = enum {
    event,
    damage,
    danger,
    recovery,
    loot,
    progress,
    status,
    fn ink(k: Kind) rl.Color {
        return switch (k) {
            .event => look.TEXT,
            .damage => look.rgb(0xf0ba87),
            .danger => look.rgb(0xf08080),
            .recovery => look.rgb(0x8bcf9d),
            .loot => look.UI_FOCUS,
            .progress => look.rgb(0xc6a0ed),
            .status => look.WARD,
        };
    }
};
pub const Log = struct {
    pub const LINES: usize = 128;
    pub const COLS: usize = 160;
    lines: [LINES]menu.Note(COLS - 1) = @splat(.{}),
    kinds: [LINES]Kind = @splat(.event),
    head: usize = 0,
    n: usize = 0,
    scroll: usize = 0,
    /// The newest lines, said as the turn resolved, kept back until its picture has caught up.
    held: usize = 0,

    pub fn say(self: *Log, comptime fmt: []const u8, args: anytype) void {
        self.push(.event, fmt, args);
    }
    pub fn push(self: *Log, kind: Kind, comptime fmt: []const u8, args: anytype) void {
        self.lines[self.head].say(fmt, args);
        self.kinds[self.head] = kind;
        self.head = (self.head + 1) % LINES;
        self.n = @min(LINES, self.n + 1);
        self.held = @min(self.n, self.held + 1);
        self.scroll = 0;
    }
    pub fn release(self: *Log) void {
        self.held = 0;
    }
    fn shown(self: *const Log) usize {
        return self.n - self.held;
    }
    fn index(self: *const Log, back: usize) usize {
        return (self.head + LINES - 1 - back) % LINES;
    }
    pub fn line(self: *const Log, back: usize) ?[:0]const u8 {
        return if (back < self.n) self.lines[self.index(back)].text() else null;
    }
    pub fn move(self: *Log, delta: i32) void {
        self.scroll = mathx.nudge(self.scroll, delta, self.shown());
    }
};
const MARGIN: i32 = hud.EDGE;
const BOX_H: i32 = 270;
const MIN_W: i32 = 160;
const MAX_W: i32 = 440;
/// Kept clear between the box and the hud's assembly.
const HUD_GAP: i32 = 24;
const ROWS_Y: i32 = 10;
/// Rows clip this far above the box's foot; the last row's leading falls inside it.
const CLIP_BOTTOM: i32 = 12;
const ROWS_BOTTOM: i32 = BOX_H - CLIP_BOTTOM - font.LEADING;
const CLIP_X: i32 = 10;
const TEXT_X: i32 = 14;
const LINE_H = font.SMALL_LINE;
const ENTRY_GAP: i32 = 4;
const TOP_OPACITY: f32 = 0.1;
const BG_A: u8 = 210;
const BG = blk: {
    var c = hud.PLATE;
    c.a = BG_A;
    break :blk c;
};

pub fn box(screen: mathx.P) rl.Rectangle {
    const beside = hud.leftOf(screen) - HUD_GAP;
    const width = @max(MIN_W, @min(MAX_W, beside));
    return raster.rect(MARGIN, screen.y - MARGIN - BOX_H, width, BOX_H);
}
pub fn draw(face: *const font.Face, sprites: *const look.Sprites, screen: mathx.P, log: *const Log) void {
    const r = box(screen);
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    if (sprites.log_fade) |fade| {
        rl.beginShaderMode(fade.shader);
        shaders.setUniform(fade.shader, fade.bounds, [2]f32{ @floatFromInt(screen.y - y - BOX_H), @floatFromInt(screen.y - y) });
        shaders.setUniform(fade.shader, fade.minimum, TOP_OPACITY);
        look.hudPanelIn(sprites, r, BG, look.LIT);
    } else {
        rl.drawRectangleGradientV(x, y, w, BOX_H, look.fade(BG, TOP_OPACITY), BG);
    }
    defer if (sprites.log_fade != null) rl.endShaderMode();
    var bottom = y + ROWS_BOTTOM;
    var back = log.held + log.scroll;
    rl.beginScissorMode(x + CLIP_X, y + ROWS_Y, w - 2 * CLIP_X, BOX_H - ROWS_Y - CLIP_BOTTOM);
    defer rl.endScissorMode();
    var buf: font.Wrapped = undefined;
    var rows: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
    while (back < log.n and bottom > y + ROWS_Y) : (back += 1) {
        const count = font.wrap(face, log.line(back).?, font.SMALL, w - 2 * TEXT_X, &buf, &rows);
        bottom -= @as(i32, @intCast(count)) * LINE_H;
        const at = log.index(back);
        const ink = log.kinds[at].ink();
        for (rows[0..count], 0..) |text, i| {
            const row = bottom + @as(i32, @intCast(i)) * LINE_H;
            const alpha = mathx.lerpF(TOP_OPACITY, 1, std.math.clamp(@as(f32, @floatFromInt(row - y)) / BOX_H, 0, 1));
            face.draw(text, x + TEXT_X, row, font.SMALL, if (sprites.log_fade != null) ink else look.fade(ink, alpha));
        }
        bottom -= ENTRY_GAP;
    }
}

test "event history keeps chronological rows and colors through wrap; new events return to the bottom" {
    var log = Log{};
    const extra = 8;
    for (0..Log.LINES + extra) |i| log.push(.loot, "Item {d}", .{i});
    try std.testing.expectEqual(Log.LINES, log.n);
    var want: [16]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&want, "Item {d}", .{extra}), log.line(Log.LINES - 1).?);
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&want, "Item {d}", .{Log.LINES + extra - 1}), log.line(0).?);
    log.move(4);
    try std.testing.expectEqual(@as(usize, 0), log.scroll);
    log.release();
    log.move(4);
    try std.testing.expectEqual(@as(usize, 4), log.scroll);
    log.push(.recovery, "Recovered", .{});
    try std.testing.expectEqual(@as(usize, 0), log.scroll);
    try std.testing.expectEqual(Kind.recovery, log.kinds[log.index(0)]);
    try std.testing.expectEqual(Log.LINES - 1, log.shown());
    std.debug.print("event log: {d}-entry ring, colors, scrolling, bottom-follow and held lines checked\n", .{Log.LINES});
}

test "held log entries never enter the scroll range and overflow retains exact text and kinds" {
    var log = Log{};
    try std.testing.expect(log.line(0) == null);
    log.move(1000);
    try std.testing.expectEqual(@as(usize, 0), log.scroll);
    for (0..4) |i| log.say("Visible {d}", .{i});
    log.release();
    log.move(1000);
    try std.testing.expectEqual(@as(usize, 3), log.scroll);
    log.push(.danger, "Held 0", .{});
    log.push(.status, "Held 1", .{});
    try std.testing.expectEqual(@as(usize, 0), log.scroll);
    try std.testing.expectEqual(@as(usize, 2), log.held);
    try std.testing.expectEqual(@as(usize, 4), log.shown());
    log.move(1000);
    try std.testing.expectEqual(@as(usize, 3), log.scroll);
    log.move(-1000);
    try std.testing.expectEqual(@as(usize, 0), log.scroll);
    for (0..Log.LINES + 9) |i| log.push(if (i % 2 == 0) .loot else .damage, "Pending {d}", .{i});
    try std.testing.expectEqual(Log.LINES, log.held);
    try std.testing.expectEqual(@as(usize, 0), log.shown());
    log.move(1000);
    try std.testing.expectEqual(@as(usize, 0), log.scroll);
    log.release();
    log.release();
    try std.testing.expectEqual(Log.LINES, log.shown());
    var buf: [32]u8 = undefined;
    for (0..Log.LINES) |back| {
        const number = Log.LINES + 8 - back;
        try std.testing.expectEqualStrings(try std.fmt.bufPrint(&buf, "Pending {d}", .{number}), log.line(back).?);
        try std.testing.expectEqual(if (number % 2 == 0) Kind.loot else Kind.damage, log.kinds[log.index(back)]);
    }
    try std.testing.expect(log.line(Log.LINES) == null);
    log.move(1000);
    try std.testing.expectEqual(Log.LINES - 1, log.scroll);
    std.debug.print("log visibility: mixed visible/held scrolling, full hidden rollover, idempotent release and all {d} retained text/color pairs checked\n", .{Log.LINES});
}
