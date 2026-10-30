const std = @import("std");

pub const Error = error{ Short, Damaged };
const Flag = u8;
const Bits = u64;
const NameLen = u16;
const FieldCount = u16;
const PayloadLen = u32;
const Count = u32;
const FIELD_HEAD = @sizeOf(NameLen) + @sizeOf(PayloadLen);

pub const Defaults = struct {
    pub fn countField(comptime _: type, comptime _: []const u8) ?[]const u8 {
        return null;
    }
};

pub fn maxSize(comptime T: type) usize {
    return maxSizeOf(Defaults, T);
}

fn maxSizeOf(comptime Policy: type, comptime T: type) usize {
    if (@hasDecl(Policy, "Stored")) {
        if (Policy.Stored(T) != T) return maxSizeOf(Policy, Policy.Stored(T));
    }
    return switch (@typeInfo(T)) {
        .int => @sizeOf(Flag) + @sizeOf(Bits),
        .float => @sizeOf(Bits),
        .bool => @sizeOf(Flag),
        .void => 0,
        .optional => |o| @sizeOf(Flag) + maxSizeOf(Policy, o.child),
        .array => |a| @sizeOf(Count) + a.len * (if (a.child == u8) 1 else maxSizeOf(Policy, a.child)),
        .@"enum" => |e| blk: {
            var longest: usize = 0;
            for (e.fields) |field| longest = @max(longest, field.name.len);
            break :blk @sizeOf(NameLen) + longest;
        },
        .@"struct" => blk: {
            var size: usize = @sizeOf(FieldCount);
            if (enumArray(T)) {
                for (std.enums.values(T.Key)) |key| size += FIELD_HEAD + @tagName(key).len + maxSizeOf(Policy, T.Value);
            } else for (std.meta.fields(T)) |field| size += FIELD_HEAD + field.name.len + maxSizeOf(Policy, field.type);
            break :blk size;
        },
        .@"union" => |u| blk: {
            var longest: usize = 0;
            for (u.fields) |field| longest = @max(longest, @sizeOf(NameLen) + field.name.len + maxSizeOf(Policy, field.type));
            break :blk longest;
        },
        else => @compileError("unbounded wire value"),
    };
}

pub fn Codec(comptime Policy: type) type {
    return struct {
        const Self = @This();

        pub fn maxSize(comptime T: type) usize {
            return maxSizeOf(Policy, T);
        }

        pub fn write(out: *std.ArrayList(u8), value: anytype) !void {
            const T = @TypeOf(value);
            if (comptime @hasDecl(Policy, "Stored")) {
                if (comptime Policy.Stored(T) != T) return write(out, try Policy.encode(value));
            }
            switch (@typeInfo(T)) {
                .pointer => |p| {
                    if (p.size != .one) @compileError("wire values require bounded arrays");
                    try write(out, value.*);
                },
                .int => |info| {
                    if (info.bits > 64) @compileError("wire integer exceeds 64 bits");
                    try out.append(@intFromBool(info.signedness == .signed));
                    const bits: Bits = if (info.signedness == .signed) @bitCast(@as(i64, value)) else @intCast(value);
                    try integer(out, Bits, bits);
                },
                .float => try integer(out, Bits, @bitCast(@as(f64, value))),
                .bool => try out.append(@intFromBool(value)),
                .void => {},
                .@"enum" => try string(out, @tagName(value)),
                .optional => {
                    try out.append(@intFromBool(value != null));
                    if (value) |child| try write(out, child);
                },
                .array => try array(out, &value, value.len),
                .@"union" => {
                    try string(out, @tagName(value));
                    switch (value) {
                        inline else => |payload| try write(out, payload),
                    }
                },
                .@"struct" => {
                    if (comptime enumArray(T)) {
                        try integer(out, FieldCount, @intCast(std.enums.values(T.Key).len));
                        for (std.enums.values(T.Key)) |key| try field(out, @tagName(key), value.getPtrConst(key));
                    } else {
                        const fields = std.meta.fields(T);
                        try integer(out, FieldCount, @intCast(fields.len));
                        inline for (fields) |f| {
                            const size_at = try beginField(out, f.name);
                            if (comptime Policy.countField(T, f.name)) |count| {
                                try array(out, &@field(value, f.name), @field(value, count));
                            } else try write(out, &@field(value, f.name));
                            endField(out, size_at);
                        }
                    }
                },
                else => @compileError("unsupported wire value: " ++ @typeName(T)),
            }
        }

        pub fn field(out: *std.ArrayList(u8), name: []const u8, value: anytype) !void {
            const size_at = try beginField(out, name);
            try write(out, value);
            endField(out, size_at);
        }

        fn array(out: *std.ArrayList(u8), values: anytype, count: usize) !void {
            if (count > values.len) return error.Damaged;
            try integer(out, Count, @intCast(count));
            if (comptime std.meta.Elem(@TypeOf(values.*)) == u8) {
                try out.appendSlice(values[0..count]);
            } else for (values[0..count]) |*value| try write(out, value);
        }

        pub fn read(bytes: []const u8, destination: anytype) Error!void {
            var cursor = Cursor{ .bytes = bytes };
            try readValue(&cursor, destination);
            if (cursor.bytes.len != 0) return error.Damaged;
        }

        fn readValue(cursor: *Cursor, destination: anytype) Error!void {
            const T = std.meta.Child(@TypeOf(destination));
            if (comptime @hasDecl(Policy, "Stored")) {
                if (comptime Policy.Stored(T) != T) {
                    var stored: Policy.Stored(T) = undefined;
                    try readValue(cursor, &stored);
                    destination.* = try Policy.decode(T, stored);
                    return;
                }
            }
            switch (@typeInfo(T)) {
                .int => {
                    const signed = try cursor.boolean();
                    const bits = try cursor.int(Bits);
                    destination.* = if (signed)
                        std.math.cast(T, @as(i64, @bitCast(bits))) orelse return error.Damaged
                    else
                        std.math.cast(T, bits) orelse return error.Damaged;
                },
                .float => {
                    const number: f64 = @bitCast(try cursor.int(Bits));
                    if (!std.math.isFinite(number) or @abs(number) > std.math.floatMax(T)) return error.Damaged;
                    destination.* = @floatCast(number);
                },
                .bool => destination.* = try cursor.boolean(),
                .void => destination.* = {},
                .@"enum" => destination.* = std.meta.stringToEnum(T, try cursor.name()) orelse return error.Damaged,
                .optional => |info| {
                    if (try cursor.boolean()) {
                        destination.* = @as(info.child, undefined);
                        try readValue(cursor, &destination.*.?);
                    } else destination.* = null;
                },
                .array => {
                    const count = try readArray(cursor, destination);
                    if (count != destination.len) return error.Damaged;
                },
                .@"union" => |info| {
                    const tag = std.meta.stringToEnum(info.tag_type.?, try cursor.name()) orelse return error.Damaged;
                    switch (tag) {
                        inline else => |active| {
                            destination.* = @unionInit(T, @tagName(active), undefined);
                            try readValue(cursor, &@field(destination, @tagName(active)));
                        },
                    }
                },
                .@"struct" => try readRecord(cursor, destination),
                else => @compileError("unsupported wire destination: " ++ @typeName(T)),
            }
        }

        fn readArray(cursor: *Cursor, destination: anytype) Error!usize {
            const count = try cursor.int(Count);
            if (count > destination.len) return error.Damaged;
            if (comptime std.meta.Elem(std.meta.Child(@TypeOf(destination))) == u8) {
                @memcpy(destination[0..count], try cursor.take(count));
                @memset(destination[count..], 0);
            } else for (destination[0..count]) |*value| try readValue(cursor, value);
            return count;
        }

        fn readRecord(cursor: *Cursor, destination: anytype) Error!void {
            const T = std.meta.Child(@TypeOf(destination));
            if (comptime enumArray(T)) {
                destination.* = T.initFill(defaultValue(T.Value));
                var seen = std.EnumSet(T.Key).initEmpty();
                var record = try Record.init(cursor);
                while (try record.next()) |entry| {
                    const key = std.meta.stringToEnum(T.Key, entry.name) orelse return error.Damaged;
                    if (seen.contains(key)) return error.Damaged;
                    seen.insert(key);
                    try read(entry.bytes, destination.getPtr(key));
                }
                return;
            }
            const fields = std.meta.fields(T);
            var seen = std.StaticBitSet(fields.len).initEmpty();
            var counts: [fields.len]?usize = @splat(null);
            var record = try Record.init(cursor);
            while (try record.next()) |entry| {
                inline for (fields, 0..) |f, index| {
                    if (std.mem.eql(u8, entry.name, f.name)) {
                        if (seen.isSet(index)) return error.Damaged;
                        seen.set(index);
                        if (comptime Policy.countField(T, f.name) != null) {
                            if (f.default_value_ptr) |value| {
                                @field(destination, f.name) = @as(*const f.type, @ptrCast(@alignCast(value))).*;
                            }
                            var body = Cursor{ .bytes = entry.bytes };
                            counts[index] = try readArray(&body, &@field(destination, f.name));
                            if (body.bytes.len != 0) return error.Damaged;
                        } else try read(entry.bytes, &@field(destination, f.name));
                    }
                }
            }
            inline for (fields, 0..) |f, index| {
                if (!seen.isSet(index)) {
                    if (f.default_value_ptr) |value| {
                        @field(destination, f.name) = @as(*const f.type, @ptrCast(@alignCast(value))).*;
                    } else return error.Short;
                }
            }
            if (comptime @hasDecl(Policy, "defaults")) Policy.defaults(destination, seen);
            inline for (fields, 0..) |f, index| {
                if (comptime Policy.countField(T, f.name)) |count_field| {
                    const count = @field(destination, count_field);
                    if (count > @field(destination, f.name).len or (counts[index] orelse 0) != count) return error.Damaged;
                }
            }
        }
    };
}

fn defaultValue(comptime T: type) T {
    if (@typeInfo(T) == .@"struct") {
        if (comptime enumArray(T)) return T.initFill(defaultValue(T.Value));
        const all_default = comptime blk: {
            for (std.meta.fields(T)) |field| if (field.default_value_ptr == null) break :blk false;
            break :blk true;
        };
        if (all_default) return .{};
    }
    return std.mem.zeroes(T);
}

fn enumArray(comptime T: type) bool {
    return @hasDecl(T, "Key") and @hasDecl(T, "Value") and @hasField(T, "values") and @hasDecl(T, "initFill");
}

pub fn integer(out: *std.ArrayList(u8), comptime T: type, value: T) !void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    try out.appendSlice(&bytes);
}

fn string(out: *std.ArrayList(u8), value: []const u8) !void {
    try integer(out, NameLen, std.math.cast(NameLen, value.len) orelse return error.Damaged);
    try out.appendSlice(value);
}

fn beginField(out: *std.ArrayList(u8), name: []const u8) !usize {
    try string(out, name);
    const at = out.items.len;
    try integer(out, PayloadLen, 0);
    return at;
}

fn endField(out: *std.ArrayList(u8), at: usize) void {
    const len = @sizeOf(PayloadLen);
    std.mem.writeInt(PayloadLen, out.items[at..][0..len], @intCast(out.items.len - at - len), .little);
}

pub const Cursor = struct {
    bytes: []const u8,

    pub fn take(self: *Cursor, count: usize) Error![]const u8 {
        if (count > self.bytes.len) return error.Short;
        defer self.bytes = self.bytes[count..];
        return self.bytes[0..count];
    }

    pub fn int(self: *Cursor, comptime T: type) Error!T {
        return std.mem.readInt(T, (try self.take(@sizeOf(T)))[0..@sizeOf(T)], .little);
    }

    fn name(self: *Cursor) Error![]const u8 {
        return self.take(try self.int(NameLen));
    }

    fn boolean(self: *Cursor) Error!bool {
        return switch (try self.int(Flag)) {
            0 => false,
            1 => true,
            else => error.Damaged,
        };
    }
};

pub const Record = struct {
    cursor: *Cursor,
    remaining: FieldCount,
    pub const Entry = struct { name: []const u8, bytes: []const u8 };

    pub fn init(cursor: *Cursor) Error!Record {
        return .{ .cursor = cursor, .remaining = try cursor.int(FieldCount) };
    }

    pub fn next(self: *Record) Error!?Entry {
        if (self.remaining == 0) return null;
        self.remaining -= 1;
        const name = try self.cursor.name();
        const size = try self.cursor.int(PayloadLen);
        return .{ .name = name, .bytes = try self.cursor.take(size) };
    }
};

test "wire encoding survives field order integer widths enum values and added defaults" {
    const Before = struct { score: u16, mode: enum { walking, resting }, active: bool };
    const After = struct { active: bool, mode: enum(u16) { resting = 7, walking = 99 }, score: u64, recovered: u8 = 3 };
    const C = Codec(Defaults);
    var bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer bytes.deinit();
    try C.write(&bytes, Before{ .score = 513, .mode = .walking, .active = true });
    var result: After = undefined;
    try C.read(bytes.items, &result);
    try std.testing.expectEqual(@as(u64, 513), result.score);
    try std.testing.expectEqual(After{ .score = 513, .mode = .walking, .active = true }, result);
    var scalar = std.ArrayList(u8).init(std.testing.allocator);
    defer scalar.deinit();
    try C.write(&scalar, @as(u16, 513));
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2, 0, 0, 0, 0, 0, 0 }, scalar.items);
    std.debug.print("portable wire: fixed little-endian integer fixture; reordered fields/enums, widened integer and added default retained\n", .{});
}

test "wire reads reject truncation duplicates invalid tags overflow and trailing bytes" {
    const C = Codec(Defaults);
    const Value = struct { n: u8, optional: ?bool };
    var bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer bytes.deinit();
    try C.write(&bytes, Value{ .n = 5, .optional = true });
    var value: Value = undefined;
    for (0..bytes.items.len) |cut| try std.testing.expectError(error.Short, C.read(bytes.items[0..cut], &value));
    try bytes.append(0);
    try std.testing.expectError(error.Damaged, C.read(bytes.items, &value));
    bytes.clearRetainingCapacity();
    try integer(&bytes, u16, 2);
    try C.field(&bytes, "n", @as(u8, 1));
    try C.field(&bytes, "n", @as(u8, 2));
    try std.testing.expectError(error.Damaged, C.read(bytes.items, &value));
    var boolean: bool = false;
    try std.testing.expectError(error.Damaged, C.read(&.{2}, &boolean));
    var small: u8 = 0;
    try std.testing.expectError(error.Damaged, C.read(&.{ 0, 0, 1, 0, 0, 0, 0, 0, 0 }, &small));
    var tag: enum { known } = .known;
    try std.testing.expectError(error.Damaged, C.read(&.{ 1, 0, 'x' }, &tag));
    std.debug.print("portable wire: every truncated prefix, duplicate fields, invalid bool/enum, overflow and trailing data rejected\n", .{});
}

test "wire conversion skips retired fields and preserves signedness and named enum array keys" {
    const C = Codec(Defaults);
    const Old = struct { retired: u8, score: u16 };
    const New = struct { score: i64, enabled: bool = true };
    var bytes = std.ArrayList(u8).init(std.testing.allocator);
    defer bytes.deinit();
    try C.write(&bytes, Old{ .retired = 7, .score = 60000 });
    var back: New = undefined;
    try C.read(bytes.items, &back);
    try std.testing.expectEqual(New{ .score = 60000 }, back);
    bytes.clearRetainingCapacity();
    try C.write(&bytes, @as(i8, -1));
    var unsigned: u64 = 0;
    try std.testing.expectError(error.Damaged, C.read(bytes.items, &unsigned));
    bytes.clearRetainingCapacity();
    try C.write(&bytes, @as(u64, std.math.maxInt(u64)));
    var signed: i64 = 0;
    try std.testing.expectError(error.Damaged, C.read(bytes.items, &signed));
    const Before = std.EnumArray(enum { fire, cold }, u8);
    const After = std.EnumArray(enum(u8) { cold = 8, poison = 9, fire = 12 }, u16);
    bytes.clearRetainingCapacity();
    try C.write(&bytes, Before.init(.{ .fire = 7, .cold = 13 }));
    var elements: After = undefined;
    try C.read(bytes.items, &elements);
    try std.testing.expectEqual(@as(u16, 7), elements.get(.fire));
    try std.testing.expectEqual(@as(u16, 13), elements.get(.cold));
    try std.testing.expectEqual(@as(u16, 0), elements.get(.poison));
    std.debug.print("wire conversion: retired field skipped, unsafe signed casts refused, reordered enum keys retained and new key defaulted\n", .{});
}
