const std = @import("std");
const builtin = @import("builtin");

// A file names its types by `fingerprint`, so a build whose types changed refuses it rather than misreads it.

pub fn fingerprint(comptime types: anytype) u64 {
    const h = comptime blk: {
        @setEvalBranchQuota(200_000);
        var s: []const u8 = builtin.zig_version_string;
        for (types) |T| s = s ++ "|" ++ describe(T);
        break :blk std.hash.Wyhash.hash(0, s);
    };
    return h;
}

fn describe(comptime T: type) []const u8 {
    const size = std.fmt.comptimePrint("#{d}", .{@sizeOf(T)});
    return switch (@typeInfo(T)) {
        .int, .float, .bool, .void => @typeName(T),
        .@"enum" => |e| blk: {
            var s: []const u8 = "enum(" ++ @typeName(e.tag_type) ++ "){";
            for (e.fields) |f| s = s ++ f.name ++ std.fmt.comptimePrint("={d},", .{f.value});
            break :blk s ++ "}";
        },
        .array => |a| std.fmt.comptimePrint("[{d}]", .{a.len}) ++ describe(a.child),
        .optional => |o| "?" ++ describe(o.child),
        .@"struct" => |st| blk: {
            var s: []const u8 = if (@hasDecl(T, "Key") and @TypeOf(T.Key) == type) describe(T.Key) ++ "{" else "{";
            for (st.fields) |f| s = s ++ f.name ++ ":" ++ describe(f.type) ++ ";";
            break :blk s ++ "}";
        },
        .@"union" => |u| blk: {
            if (u.tag_type == null) @compileError(@typeName(T) ++ " has no tag to store");
            var s: []const u8 = "union(" ++ describe(u.tag_type.?) ++ "){";
            for (u.fields) |f| s = s ++ f.name ++ ":" ++ describe(f.type) ++ ";";
            break :blk s ++ "}";
        },
        else => @compileError(@typeName(T) ++ " is not plain data"),
    } ++ size;
}

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

/// Bytes before a file's body: its magic, then its fingerprint.
pub fn head(magic: []const u8) usize {
    return magic.len + @sizeOf(u64);
}

pub fn begin(w: anytype, magic: []const u8, print: u64) !void {
    try w.writeAll(magic);
    try put(w, &print);
}

/// Ends a file with the sum of its `body`, everything after its head.
pub fn seal(w: anytype, body: []const u8) !void {
    try put(w, &sum(body));
}

pub const OpenError = error{ Foreign, OtherBuild, Short, Damaged };

pub fn open(bytes: []const u8, magic: []const u8, print: u64) OpenError![]const u8 {
    if (bytes.len < head(magic) or !std.mem.eql(u8, bytes[0..magic.len], magic)) return error.Foreign;
    var b = bytes[magic.len..];
    var got: u64 = undefined;
    _ = take(&b, &got);
    if (got != print) return error.OtherBuild;
    if (b.len < SUM) return error.Short;
    var tail = b[b.len - SUM ..];
    var want: u64 = undefined;
    _ = take(&tail, &want);
    b = b[0 .. b.len - SUM];
    if (want != sum(b)) return error.Damaged;
    return b;
}

pub fn put(w: anytype, v: anytype) !void {
    try w.writeAll(std.mem.asBytes(v));
}

pub fn take(bytes: *[]const u8, v: anytype) bool {
    const out = std.mem.asBytes(v);
    if (bytes.len < out.len) return false;
    @memcpy(out, bytes.*[0..out.len]);
    bytes.* = bytes.*[out.len..];
    return true;
}

test "a value round-trips, and a changed type changes the fingerprint" {
    const A = struct { x: i32, k: enum { a, b }, on: [3]bool };
    const B = struct { x: i32, k: enum { a, b, c }, on: [3]bool };
    try std.testing.expect(fingerprint(.{A}) != fingerprint(.{B}));
    try std.testing.expectEqual(fingerprint(.{ A, u8 }), fingerprint(.{ A, u8 }));
    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    const a = A{ .x = -7, .k = .b, .on = .{ true, false, true } };
    try put(buf.writer(), &a);
    var bytes: []const u8 = buf.items;
    var back: A = undefined;
    try std.testing.expect(take(&bytes, &back));
    try std.testing.expectEqual(a, back);
    try std.testing.expect(!take(&bytes, &back));
}

test "an enum-indexed array whose keys are reordered changes the fingerprint" {
    const A = std.EnumArray(enum { cold, fire }, i16);
    const B = std.EnumArray(enum { fire, cold }, i16);
    try std.testing.expect(fingerprint(.{A}) != fingerprint(.{B}));
}

test "a union whose tag values change changes the fingerprint" {
    const Ab = enum(u8) { a = 0, b = 1 };
    const Ba = enum(u8) { a = 1, b = 0 };
    const A = union(Ab) { a: u8, b: u8 };
    const B = union(Ba) { a: u8, b: u8 };
    try std.testing.expect(fingerprint(.{A}) != fingerprint(.{B}));
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
        try std.testing.expect(!take(&bytes, &value));
        try std.testing.expectEqual(@as(u32, 0xaabbccdd), value);
        try std.testing.expectEqual(source[0..n].ptr, bytes.ptr);
        try std.testing.expectEqual(n, bytes.len);
    }
    var bytes: []const u8 = &source;
    var first: u16 = 0;
    var second: u16 = 0;
    try std.testing.expect(take(&bytes, &first));
    try std.testing.expect(take(&bytes, &second));
    try std.testing.expectEqualSlices(u8, source[0..2], std.mem.asBytes(&first));
    try std.testing.expectEqualSlices(u8, source[2..4], std.mem.asBytes(&second));
    try std.testing.expectEqual(@as(usize, 0), bytes.len);
    std.debug.print("storage reads: empty envelope, 4 short reads without mutation and 2 successive exact reads checked\n", .{});
}

test "storage fingerprints distinguish field identity order lengths and optional payloads" {
    const Base = struct { x: u16, y: u16 };
    const Renamed = struct { x: u16, z: u16 };
    const Reordered = struct { y: u16, x: u16 };
    const Same = struct { x: u16, y: u16 };
    try std.testing.expectEqual(fingerprint(.{Base}), fingerprint(.{Same}));
    try std.testing.expect(fingerprint(.{Base}) != fingerprint(.{Renamed}));
    try std.testing.expect(fingerprint(.{Base}) != fingerprint(.{Reordered}));
    try std.testing.expect(fingerprint(.{[2]u8}) != fingerprint(.{[3]u8}));
    try std.testing.expect(fingerprint(.{u16}) != fingerprint(.{?u16}));
    try std.testing.expect(fingerprint(.{ u16, u32 }) != fingerprint(.{ u32, u16 }));
    std.debug.print("storage fingerprints: equivalent schemas agree; 5 schema changes disagree\n", .{});
}
