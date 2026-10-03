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
            var s: []const u8 = "{";
            for (st.fields) |f| s = s ++ f.name ++ ":" ++ describe(f.type) ++ ";";
            break :blk s ++ "}";
        },
        .@"union" => |u| blk: {
            if (u.tag_type == null) @compileError(@typeName(T) ++ " has no tag to store");
            var s: []const u8 = "union{";
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
    {
        var f = try std.fs.cwd().createFile(tmp, .{});
        defer f.close();
        try f.writeAll(bytes);
        try f.sync();
    }
    try std.fs.cwd().rename(tmp, path);
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
