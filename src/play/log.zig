const std = @import("std");
const mathx = @import("../core/mathx.zig");
const text = @import("../core/text.zig");

pub const Kind = enum {
    event,
    damage,
    danger,
    recovery,
    loot,
    progress,
    status,
};
pub const Log = struct {
    pub const LINES: usize = 128;
    pub const COLS: usize = 160;
    lines: [LINES]text.Note(COLS - 1) = @splat(.{}),
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
    pub fn index(self: *const Log, back: usize) usize {
        return (self.head + LINES - 1 - back) % LINES;
    }
    pub fn line(self: *const Log, back: usize) ?[:0]const u8 {
        return if (back < self.n) self.lines[self.index(back)].text() else null;
    }
    pub fn move(self: *Log, delta: i32) void {
        self.scroll = mathx.nudge(self.scroll, delta, self.shown());
    }
};

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
