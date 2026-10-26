const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

/// Last active device; selects maker-specific button captions.
pub const Device = enum {
    xbox,
    ps4,
    ps5,
    keys,

    pub fn pad(d: Device) bool {
        return d != .keys;
    }

    pub fn playstation(d: Device) bool {
        return switch (d) {
            .ps4, .ps5 => true,
            .xbox, .keys => false,
        };
    }
};

/// raylib names a pad's buttons by place, as GLFW maps every pad onto Xbox's.
pub fn padName(comptime b: rl.GamepadButton, comptime d: Device) [:0]const u8 {
    const ps = d.playstation();
    return switch (b) {
        .right_face_down => if (ps) "Cross" else "A",
        .right_face_right => if (ps) "Circle" else "B",
        .right_face_left => if (ps) "Square" else "X",
        .right_face_up => if (ps) "Triangle" else "Y",
        .left_trigger_1 => if (ps) "L1" else "LB",
        .left_trigger_2 => if (ps) "L2" else "LT",
        .right_trigger_1 => if (ps) "R1" else "RB",
        .right_trigger_2 => if (ps) "R2" else "RT",
        .middle_left => switch (d) {
            .ps5 => "Create",
            .ps4 => "Share",
            .xbox, .keys => "View",
        },
        .middle_right => if (ps) "Options" else "Menu",
        .right_thumb => if (ps) "R3" else "RS",
        else => @compileError("no caption for " ++ @tagName(b)),
    };
}

/// Drawn text marks a glyph's caption between these; `prompt_text` draws it as a key, mouse or arrows icon.
pub const GLYPH_OPEN = '\x1e';
pub const GLYPH_CLOSE = '\x1f';
pub const WHEEL = "wheel";
pub const ARROWS = "arrows";
/// Key captions a prompt draws as an arrow.
pub const ARROW_KEYS = [_]struct { caption: [:0]const u8, d: mathx.Dir }{
    .{ .caption = keyName(.up), .d = .n },
    .{ .caption = keyName(.down), .d = .s },
};

pub fn glyphCaption(comptime text: []const u8) [:0]const u8 {
    return std.fmt.comptimePrint("{c}{s}{c}", .{ GLYPH_OPEN, text, GLYPH_CLOSE });
}

pub fn keyGlyph(comptime key: rl.KeyboardKey) [:0]const u8 {
    return glyphCaption(keyName(key));
}

pub fn glyphCaptions(comptime keys: []const rl.KeyboardKey) [keys.len][:0]const u8 {
    var out: [keys.len][:0]const u8 = undefined;
    for (keys, &out) |key, *text| text.* = keyGlyph(key);
    return out;
}

pub fn keyName(comptime k: rl.KeyboardKey) [:0]const u8 {
    return switch (k) {
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12 => comptime upper(@tagName(k)),
        .tab => "Tab",
        .escape => "Esc",
        .enter => "Enter",
        .space => "Space",
        .backspace => "Backspace",
        .delete => "Del",
        .left_control => "Ctrl",
        .left_shift => "Shift",
        .left_alt => "Alt",
        .left_bracket => "[",
        .right_bracket => "]",
        .minus => "-",
        .equal => "=",
        .semicolon => ";",
        .grave => "`",
        .home => "Home",
        .up => "Up",
        .down => "Down",
        .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z => &[_:0]u8{std.ascii.toUpper(@tagName(k)[0])},
        .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine => &[_:0]u8{'0' + @intFromEnum(k) - @intFromEnum(rl.KeyboardKey.zero)},
        else => @compileError("no caption for " ++ @tagName(k)),
    };
}

/// Uppercase text at compile time.
pub fn upper(comptime s: []const u8) [:0]const u8 {
    var b: [s.len:0]u8 = undefined;
    _ = std.ascii.upperString(&b, s);
    const out = b;
    return &out;
}

pub fn mouseName(comptime b: rl.MouseButton) [:0]const u8 {
    return switch (b) {
        .left => "LMB",
        .right => "RMB",
        .middle => "MMB",
        else => @compileError("no caption for " ++ @tagName(b)),
    };
}
