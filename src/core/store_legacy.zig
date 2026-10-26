const std = @import("std");
const builtin = @import("builtin");

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

pub fn valid(comptime Policy: type, value: anytype) bool {
    const T = std.meta.Child(@TypeOf(value));
    return switch (@typeInfo(T)) {
        .int, .void => true,
        .float => std.math.isFinite(value.*),
        .bool => std.mem.asBytes(value)[0] <= 1,
        .@"enum" => blk: {
            _ = std.meta.intToEnum(T, @intFromEnum(value.*)) catch break :blk false;
            break :blk true;
        },
        .optional => |info| blk: {
            // This reader is gated by the original compiler and ABI fingerprint.
            comptime std.debug.assert(@sizeOf(T) > @sizeOf(info.child));
            const present = std.mem.asBytes(value)[@sizeOf(info.child)];
            if (present > 1) break :blk false;
            break :blk present == 0 or valid(Policy, &value.*.?);
        },
        .array => blk: {
            for (value) |*element| if (!valid(Policy, element)) break :blk false;
            break :blk true;
        },
        .@"struct" => |info| blk: {
            inline for (std.meta.fields(T)) |field| {
                if (comptime info.layout == .@"packed") {
                    const unpacked = @field(value, field.name);
                    if (!valid(Policy, &unpacked)) break :blk false;
                } else if (comptime Policy.countField(T, field.name)) |count_field| {
                    const count = @field(value, count_field);
                    const elements = &@field(value, field.name);
                    if (count > elements.len) break :blk false;
                    for (elements[0..count]) |*element| if (!valid(Policy, element)) break :blk false;
                } else if (!valid(Policy, &@field(value, field.name))) break :blk false;
            }
            break :blk true;
        },
        .@"union" => blk: {
            const tag = std.meta.activeTag(value.*);
            if (!valid(Policy, &tag)) break :blk false;
            break :blk switch (value.*) {
                inline else => |*payload| valid(Policy, payload),
            };
        },
        else => @compileError("legacy storage cannot contain pointers"),
    };
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
