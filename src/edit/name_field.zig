const std = @import("std");
const atlas = @import("../map/atlas.zig");
const Desk = @import("../core/input.zig").Desk;

pub fn Text(comptime N: usize) type {
    return struct {
        const Self = @This();
        buf: [N]u8 = undefined,
        n: usize = 0,
        cap: usize = N,
        selected: bool = false,

        pub fn text(field: *const Self) []const u8 {
            return field.buf[0..field.n];
        }

        pub fn set(field: *Self, s: []const u8, cap: usize) void {
            field.cap = @min(cap, N);
            field.n = @min(s.len, field.cap);
            @memcpy(field.buf[0..field.n], s[0..field.n]);
            field.selected = false;
        }

        pub fn put(field: *Self, s: []const u8) void {
            field.set(s, N);
        }

        pub fn feed(field: *Self, desk: *const Desk) void {
            if (desk.text_all) field.selected = true;
            if (desk.paste_text) |pasted| {
                for (pasted) |c| if (!std.ascii.isPrint(c)) return;
                const from: usize = if (field.selected) 0 else field.n;
                if (pasted.len > field.cap - from) return;
                @memcpy(field.buf[from..][0..pasted.len], pasted);
                field.n = from + pasted.len;
                field.selected = false;
            }
            if (desk.text().len > 0 and field.selected) {
                field.n = 0;
                field.selected = false;
            }
            for (desk.text()) |c| {
                if (field.n == field.cap) break;
                field.buf[field.n] = c;
                field.n += 1;
            }
            if (desk.rub) {
                if (field.selected) field.n = 0 else if (field.n > 0) field.n -= 1;
                field.selected = false;
            }
        }
    };
}

test "editor naming fields paste atomically and replace selected names" {
    var f = Text(32){};
    f.set("Old name", atlas.NAME_MAX);
    f.feed(&.{ .text_all = true, .paste_text = "New name" });
    try std.testing.expectEqualStrings("New name", f.text());
    f.feed(&.{ .paste_text = "\ninvalid" });
    try std.testing.expectEqualStrings("New name", f.text());
    f.feed(&.{ .paste_text = "\xc3\xa9" });
    try std.testing.expectEqualStrings("New name", f.text());
    f.feed(&.{ .paste_text = "a" ** atlas.NAME_MAX });
    try std.testing.expectEqualStrings("New name", f.text());
    f.feed(&.{ .text_all = true });
    f.feed(&.{ .paste_text = "a" ** (atlas.NAME_MAX + 1) });
    try std.testing.expectEqualStrings("New name", f.text());
    try std.testing.expect(f.selected);
    f.feed(&.{ .rub = true });
    try std.testing.expectEqualStrings("", f.text());
    f.feed(&.{ .paste_text = "a" ** atlas.NAME_MAX });
    try std.testing.expectEqual(atlas.NAME_MAX, f.n);
    var typed = Desk{ .text_all = true };
    typed.typed.n = 1;
    typed.typed.buf[0] = 'B';
    f.feed(&typed);
    try std.testing.expectEqualStrings("B", f.text());
    std.debug.print("editor names: valid paste, 4 atomic rejections, select-all deletion and typed replacement checked\n", .{});
}
