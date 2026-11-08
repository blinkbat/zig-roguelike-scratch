const std = @import("std");

pub fn upper(comptime s: []const u8) [:0]const u8 {
    var b: [s.len:0]u8 = undefined;
    _ = std.ascii.upperString(&b, s);
    const out = b;
    return &out;
}

pub fn contains(list: []const []const u8, name: []const u8) bool {
    return count(list, name) > 0;
}

pub fn count(list: []const []const u8, name: []const u8) usize {
    var n: usize = 0;
    for (list) |item| {
        if (std.mem.eql(u8, item, name)) n += 1;
    }
    return n;
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
