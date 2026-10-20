const std = @import("std");
const rl = @import("raylib");
const font = @import("font.zig");
const look = @import("look.zig");
const input = @import("../core/input.zig");
const OPEN = input.GLYPH_OPEN;
const CLOSE = input.GLYPH_CLOSE;
/// The longest run of plain text laid out at once.
const RUN_MAX: usize = 256;
/// Beside an inline glyph's own width, the room it takes.
const GLYPH_PAD: i32 = 4;

const Part = struct {
    text: []const u8,
    control: bool,
    end: usize,
};

fn next(s: []const u8, at: usize) ?Part {
    if (at >= s.len) return null;
    if (s[at] == OPEN) {
        const end = std.mem.indexOfScalarPos(u8, s, at + 1, CLOSE) orelse return null;
        return .{ .text = s[at + 1 .. end], .control = true, .end = end + 1 };
    }
    const end = std.mem.indexOfScalarPos(u8, s, at, OPEN) orelse s.len;
    return .{ .text = s[at..@min(end, at + RUN_MAX)], .control = false, .end = @min(end, at + RUN_MAX) };
}

fn icon(text: [:0]const u8) look.Prompt {
    inline for (.{ .left, .right, .middle }) |b| {
        if (std.mem.eql(u8, text, input.mouseName(b))) return .{ .mouse = b };
    }
    if (std.mem.eql(u8, text, input.WHEEL)) return .{ .mouse = .wheel };
    if (std.mem.eql(u8, text, input.ARROWS)) return .arrows;
    return .{ .key = text };
}

pub const Face = struct {
    face: *const font.Face,

    pub fn width(self: Face, s: [:0]const u8, size: i32) i32 {
        return self.layout(s, 0, null, size, rl.Color.white);
    }

    pub fn draw(self: Face, s: [:0]const u8, x: i32, y: i32, size: i32, col: rl.Color) void {
        _ = self.layout(s, x, y, size, col);
    }

    pub fn drawMid(self: Face, s: [:0]const u8, cx: i32, y: i32, size: i32, col: rl.Color) void {
        self.draw(s, cx - @divTrunc(self.width(s, size), 2), y, size, col);
    }

    fn layout(self: Face, s: []const u8, x: i32, y: ?i32, size: i32, col: rl.Color) i32 {
        var at: usize = 0;
        var offset: i32 = 0;
        while (next(s, at)) |part| {
            var buffer: [RUN_MAX + 1]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buffer, "{s}", .{part.text}) catch return offset;
            if (part.control) {
                const prompt = icon(text);
                const w = prompt.width(self.face, size) + GLYPH_PAD;
                if (y) |top| prompt.draw(self.face, x + offset + @divTrunc(w, 2), top + @divTrunc(size, 2), size, @as(f32, @floatFromInt(col.a)) / 255);
                offset += w;
            } else {
                if (y) |top| self.face.draw(text, x + offset, top, size, col);
                offset += self.face.width(text, size);
            }
            at = part.end;
        }
        return offset;
    }

    pub fn fit(self: Face, buf: []u8, s: []const u8, size: i32, max: i32, keep_end: bool) [:0]const u8 {
        if (std.mem.indexOfScalar(u8, s, OPEN) == null) return self.face.fit(buf, s, size, max, keep_end);
        const whole = std.fmt.bufPrintZ(buf, "{s}", .{s}) catch "";
        if (whole.len == s.len and self.width(whole, size) <= max) return whole;
        var edge: usize = if (keep_end) s.len else 0;
        var at: usize = 0;
        while (at < s.len) {
            const end = if (s[at] == OPEN) (next(s, at) orelse break).end else at + 1;
            const text = font.elided(buf, if (keep_end) s[at..] else s[0..end], keep_end) catch {
                if (keep_end) {
                    at = end;
                    continue;
                }
                break;
            };
            if (self.width(text, size) <= max) {
                edge = if (keep_end) at else end;
                if (keep_end) break;
            } else if (!keep_end) break;
            at = end;
        }
        return font.elided(buf, if (keep_end) s[edge..] else s[0..edge], keep_end) catch "";
    }
};

test "input glyph markup keeps chords and ordinary text separate" {
    const text = "Save \x1eCtrl\x1f+\x1eS\x1f now";
    var at: usize = 0;
    var icons: usize = 0;
    var words: usize = 0;
    while (next(text, at)) |part| {
        if (part.control) icons += 1 else words += 1;
        at = part.end;
    }
    try std.testing.expectEqual(@as(usize, 2), icons);
    try std.testing.expectEqual(@as(usize, 3), words);
    try std.testing.expectEqual(text.len, at);
    try std.testing.expect(next("\x1eCtrl", 0) == null);
    try std.testing.expect(icon(input.mouseName(.left)) == .mouse);
    try std.testing.expect(icon(input.ARROWS) == .arrows);
    try std.testing.expect(icon("Enter") == .key);
    std.debug.print("input glyph text: 2 chord glyphs, 3 text runs, incomplete token and mouse/keyboard dispatch checked\n", .{});
}
