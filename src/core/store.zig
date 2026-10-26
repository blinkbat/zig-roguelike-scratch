const std = @import("std");
pub const legacy = @import("store_legacy.zig");

/// Written beside itself and renamed over it, so a write that fails part-way leaves the last one standing.
pub fn replace(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |d| try std.fs.cwd().makePath(d);
    var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp = try std.fmt.bufPrint(&tmp_buf, "{s}.tmp", .{path});
    errdefer std.fs.cwd().deleteFile(tmp) catch {};
    {
        var f = try std.fs.cwd().createFile(tmp, .{});
        defer f.close();
        try f.writeAll(bytes);
        try f.sync();
    }
    try std.fs.cwd().rename(tmp, path);
}

pub const DIR = "saves";
pub const SUM = @sizeOf(u64);

pub fn sum(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

/// Bytes before a file's body: its magic, then its format version.
pub fn head(magic: []const u8) usize {
    return magic.len + @sizeOf(u64);
}

pub fn begin(w: anytype, magic: []const u8, print: u64) !void {
    try w.writeAll(magic);
    try w.writeInt(u64, print, .little);
}

/// Ends a file with the sum of its `body`, everything after its head.
pub fn seal(w: anytype, body: []const u8) !void {
    try w.writeInt(u64, sum(body), .little);
}

pub const OpenError = error{ Foreign, OtherBuild, Short, Damaged };

pub fn open(bytes: []const u8, magic: []const u8, print: u64) OpenError![]const u8 {
    if (bytes.len < head(magic) or !std.mem.eql(u8, bytes[0..magic.len], magic)) return error.Foreign;
    const got = std.mem.readInt(u64, bytes[magic.len..][0..8], .little);
    var b = bytes[head(magic)..];
    if (got != print) return error.OtherBuild;
    if (b.len < SUM) return error.Short;
    const want = std.mem.readInt(u64, b[b.len - SUM ..][0..8], .little);
    b = b[0 .. b.len - SUM];
    if (want != sum(b)) return error.Damaged;
    return b;
}

test "sealed storage rejects every truncated prefix and every changed byte" {
    const magic = "test-store\n";
    const print: u64 = 0x123456789abcdef0;
    const body = "a body with enough bytes to truncate";
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try begin(buf.writer(), magic, print);
    try buf.appendSlice(body);
    try seal(buf.writer(), body);
    try std.testing.expectEqualStrings(body, try open(buf.items, magic, print));
    try std.testing.expectError(error.OtherBuild, open(buf.items, magic, print + 1));
    for (0..buf.items.len) |cut| {
        const expected: OpenError = if (cut < head(magic)) error.Foreign else if (cut < head(magic) + SUM) error.Short else error.Damaged;
        try std.testing.expectError(expected, open(buf.items[0..cut], magic, print));
    }
    for (buf.items, 0..) |*byte, i| {
        byte.* ^= 1;
        const expected: OpenError = if (i < magic.len) error.Foreign else if (i < head(magic)) error.OtherBuild else error.Damaged;
        try std.testing.expectError(expected, open(buf.items, magic, print));
        byte.* ^= 1;
    }
    try std.testing.expectEqualStrings(body, try open(buf.items, magic, print));
    try buf.append(0);
    try std.testing.expectError(error.Damaged, open(buf.items, magic, print));
    std.debug.print("storage envelope: {d} truncated prefixes, {d} single-byte changes, wrong build and trailing data rejected\n", .{ buf.items.len - 1, buf.items.len - 1 });
}

test "storage accepts an empty sealed body and failed takes preserve destination and cursor" {
    const magic = "empty";
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    try begin(buf.writer(), magic, 7);
    try seal(buf.writer(), "");
    try std.testing.expectEqualStrings("", try open(buf.items, magic, 7));
    const source = [_]u8{ 1, 2, 3, 4 };
    for (0..@sizeOf(u32)) |n| {
        var bytes: []const u8 = source[0..n];
        var value: u32 = 0xaabbccdd;
        try std.testing.expect(!legacy.take(&bytes, &value));
        try std.testing.expectEqual(@as(u32, 0xaabbccdd), value);
        try std.testing.expectEqual(source[0..n].ptr, bytes.ptr);
        try std.testing.expectEqual(n, bytes.len);
    }
    var bytes: []const u8 = &source;
    var first: u16 = 0;
    var second: u16 = 0;
    try std.testing.expect(legacy.take(&bytes, &first));
    try std.testing.expect(legacy.take(&bytes, &second));
    try std.testing.expectEqualSlices(u8, source[0..2], std.mem.asBytes(&first));
    try std.testing.expectEqualSlices(u8, source[2..4], std.mem.asBytes(&second));
    try std.testing.expectEqual(@as(usize, 0), bytes.len);
    std.debug.print("storage reads: empty envelope, 4 short reads without mutation and 2 successive exact reads checked\n", .{});
}
