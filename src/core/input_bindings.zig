const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const names = @import("input_names.zig");
const Device = names.Device;
const keyName = names.keyName;
const padName = names.padName;
const glyphCaption = names.glyphCaption;
const keyGlyph = names.keyGlyph;
const glyphCaptions = names.glyphCaptions;
const upper = names.upper;
const mouseName = names.mouseName;
const ARROWS = names.ARROWS;
const WHEEL = names.WHEEL;

pub const ENTER_KEYS = [_]rl.KeyboardKey{ .enter, .kp_enter };
pub const INTERACT_KEYS = ENTER_KEYS ++ [_]rl.KeyboardKey{.space};
pub const LEAN: rl.GamepadButton = .left_trigger_2;
pub const SHIFT_KEYS = [_]rl.KeyboardKey{ .left_shift, .right_shift };
pub const CTRL_KEYS = [_]rl.KeyboardKey{ .left_control, .right_control };
pub const ALT_KEYS = [_]rl.KeyboardKey{ .left_alt, .right_alt };
pub const LEAN_KEYS = SHIFT_KEYS;
pub const ZOOM_IN_KEYS = [_]rl.KeyboardKey{ .equal, .kp_add };
pub const ZOOM_OUT_KEYS = [_]rl.KeyboardKey{ .minus, .kp_subtract };
pub const OVERVIEW_KEY: rl.KeyboardKey = .home;

pub fn letters(comptime walks: []const Walk) [:0]const u8 {
    var out: []const u8 = "";
    for ([_]mathx.Dir{ .n, .w, .s, .e }) |dir| {
        const w = for (walks) |x| {
            if (x.d == dir) break x;
        } else unreachable;
        for (w.keys) |k| {
            if (@tagName(k).len == 1) out = out ++ keyName(k);
        }
    }
    return std.fmt.comptimePrint("{s}", .{out});
}

pub const Walk = struct {
    d: mathx.Dir,
    pad: ?rl.GamepadButton = null,
    keys: []const rl.KeyboardKey,
};

pub const WALKS = [_]Walk{
    .{ .d = .n, .pad = .left_face_up, .keys = &.{ .up, .w, .kp_8 } },
    .{ .d = .e, .pad = .left_face_right, .keys = &.{ .right, .d, .kp_6 } },
    .{ .d = .s, .pad = .left_face_down, .keys = &.{ .down, .s, .kp_2 } },
    .{ .d = .w, .pad = .left_face_left, .keys = &.{ .left, .a, .kp_4 } },
    .{ .d = .ne, .keys = &.{.kp_9} },
    .{ .d = .se, .keys = &.{.kp_3} },
    .{ .d = .sw, .keys = &.{.kp_1} },
    .{ .d = .nw, .keys = &.{.kp_7} },
};

pub fn walkPad(comptime d: mathx.Dir) rl.GamepadButton {
    return for (WALKS) |w| {
        if (w.d == d) break w.pad.?;
    } else unreachable;
}

pub const DPAD = blk: {
    var ds: []const mathx.Dir = &.{};
    for (WALKS) |w| {
        if (w.pad != null) ds = ds ++ &[_]mathx.Dir{w.d};
    }
    break :blk ds[0..ds.len].*;
};

/// One eighth clockwise: up is up-right, left is up-left.
pub fn leanOf(d: mathx.Dir) mathx.Dir {
    if (d.diagonal()) return d;
    return d.turned(1);
}

pub const Button = enum {
    a,
    b,
    x,
    y,
    lb,
    rb,
    rt,
    character,
    pause,
    /// The right stick pressed in.
    inspect,

    pub fn pad(b: Button) rl.GamepadButton {
        return switch (b) {
            .a => .right_face_down,
            .b => .right_face_right,
            .x => .right_face_left,
            .y => .right_face_up,
            .lb => .left_trigger_1,
            .rb => .right_trigger_1,
            .rt => .right_trigger_2,
            .character => .middle_right,
            .pause => .middle_left,
            .inspect => .right_thumb,
        };
    }

    /// Its keys in menus, the first naming it; a slot's own key is its number (`SLOT_KEYS`).
    pub fn keys(b: Button) []const rl.KeyboardKey {
        return switch (b) {
            .a => &(INTERACT_KEYS ++ [_]rl.KeyboardKey{.z}),
            .b => &.{ .escape, .x },
            .x => &.{.c},
            .y => &.{.delete},
            .lb => &.{.q},
            .rb => &.{.e},
            .rt => &.{},
            .character => &.{.tab},
            .pause => &.{.escape},
            .inspect => &.{.i},
        };
    }

    pub fn isSlot(b: Button) bool {
        return std.mem.indexOfScalar(Button, &SLOT_ORDER, b) != null;
    }

    pub fn name(comptime b: Button, comptime d: Device) [:0]const u8 {
        if (d.pad()) return padName(b.pad(), d);
        if (b.keys().len == 0) @compileError(@tagName(b) ++ " has no key in menus");
        return keyName(b.keys()[0]);
    }

    pub fn caption(b: Button, d: Device) [:0]const u8 {
        return switch (b) {
            inline else => |t| switch (d) {
                inline else => |c| comptime if (c == .keys and t.keys().len == 0) "" else t.name(c),
            },
        };
    }
};

pub const CONFIRM = Button.a;

/// The slots left to right, as the keyboard numbers them.
pub const SLOT_ORDER = [_]Button{ .lb, .a, .x, .y, .b, .rb, .rt };
pub const SLOT_KEYS = blk: {
    var out: [SLOT_ORDER.len]rl.KeyboardKey = undefined;
    for (&out, 0..) |*k, i| k.* = @enumFromInt(@intFromEnum(rl.KeyboardKey.one) + i);
    break :blk out;
};
pub const SLOT_CAPTIONS = captions(&SLOT_KEYS);

pub fn captions(comptime keys: []const rl.KeyboardKey) [keys.len][:0]const u8 {
    var out: [keys.len][:0]const u8 = undefined;
    for (keys, &out) |k, *c| c.* = keyName(k);
    return out;
}

pub const SECOND_KEYS = CTRL_KEYS;
pub const SECOND_CAPTION = keyName(SECOND_KEYS[0]);

pub const BUTTONS = std.enums.values(Button);

pub const CharacterPage = enum {
    equipment,
    inventory,
    stats,
    passives,
    skills,

    pub fn key(self: CharacterPage) rl.KeyboardKey {
        return switch (self) {
            .equipment => .f1,
            .inventory => .f2,
            .stats => .f3,
            .passives => .f4,
            .skills => .f5,
        };
    }

    comptime {
        for (std.enums.values(CharacterPage)) |p| {
            if (p.key() == Desk.PLAY_HERE_KEY) @compileError("a play-test's way back to the editor opens " ++ @tagName(p));
        }
    }

    pub fn caption(self: CharacterPage) [:0]const u8 {
        return switch (self) {
            inline else => |page| keyName(page.key()),
        };
    }
};

/// The passive tree's zoom and overview; browsing walks and panning shifts the walk.
pub const TreeKeys = struct {
    /// The right stick pans past this deflection; the d-pad zooms; Inspect's button shows the whole tree.
    pub const PAN_DEADZONE: f32 = 0.18;
    pub const PAD_ZOOM_IN = walkPad(.n);
    pub const PAD_ZOOM_OUT = walkPad(.s);
    pub const PAD_OVERVIEW: Button = .inspect;
    pub const PAN_KEYS = SHIFT_KEYS;
    pub const PAN_CAPTION = keyName(PAN_KEYS[0]);
    pub const PAGE_IN: rl.KeyboardKey = .page_up;
    pub const PAGE_OUT: rl.KeyboardKey = .page_down;
    pub const BROWSE_CAPTION = letters(&WALKS);
    pub const ZOOM_IN_CAPTION = keyName(ZOOM_IN_KEYS[0]);
    pub const ZOOM_OUT_CAPTION = keyName(ZOOM_OUT_KEYS[0]);
    pub const OVERVIEW_CAPTION = keyName(OVERVIEW_KEY);
};

pub const Desk = struct {
    pub const DIGIT_KEYS = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero };
    pub const TOOL_KEYS = DIGIT_KEYS ++ [_]rl.KeyboardKey{ .grave, .semicolon, .apostrophe, .comma, .period, .slash, .backslash, .h, .j, .k };
    pub const TOOL_CAPTIONS = glyphCaptions(&TOOL_KEYS);
    /// The editor's shapes, named and ordered as its `Shape` is.
    pub const SHAPE_KEYS_BY = .{ .brush = rl.KeyboardKey.b, .line = rl.KeyboardKey.l, .rect = rl.KeyboardKey.r, .box = rl.KeyboardKey.o, .fill = rl.KeyboardKey.f, .select = rl.KeyboardKey.m };
    pub const SHAPE_KEYS = blk: {
        const fs = std.meta.fields(@TypeOf(SHAPE_KEYS_BY));
        var out: [fs.len]rl.KeyboardKey = undefined;
        for (fs, 0..) |f, i| out[i] = @field(SHAPE_KEYS_BY, f.name);
        break :blk out;
    };
    pub const SHAPE_CAPTIONS = glyphCaptions(&SHAPE_KEYS);

    pub const PAN_KEYS = blk: {
        var out: [DPAD.len]Walk = undefined;
        var n: usize = 0;
        for (WALKS) |w| {
            if (w.pad == null) continue;
            var keys: []const rl.KeyboardKey = &.{};
            for (w.keys) |k| {
                if (!std.mem.startsWith(u8, @tagName(k), "kp_")) keys = keys ++ &[_]rl.KeyboardKey{k};
            }
            out[n] = .{ .d = w.d, .keys = keys };
            n += 1;
        }
        break :blk out;
    };
    pub const PAINT_BUTTON: rl.MouseButton = .left;
    pub const ERASE_BUTTON: rl.MouseButton = .right;
    pub const GRAB_BUTTON: rl.MouseButton = .middle;
    pub const PLAY_KEY: rl.KeyboardKey = .f5;
    pub const PLAY_HERE_KEY: rl.KeyboardKey = .f6;
    pub const SAVE_KEY: rl.KeyboardKey = .s;
    pub const OPEN_KEY: rl.KeyboardKey = .o;
    pub const NEW_KEY: rl.KeyboardKey = .n;
    pub const UNDO_KEY: rl.KeyboardKey = .z;
    pub const REDO_KEY: rl.KeyboardKey = .y;
    pub const GRAPH_KEY: rl.KeyboardKey = .tab;
    pub const GO_KEY: rl.KeyboardKey = .g;
    pub const RENAME_KEY: rl.KeyboardKey = .f2;
    pub const BACK_KEY: rl.KeyboardKey = .escape;
    pub const SMALLER_KEY: rl.KeyboardKey = .left_bracket;
    pub const BIGGER_KEY: rl.KeyboardKey = .right_bracket;
    pub const ZOOM_OUT_KEY = ZOOM_OUT_KEYS[0];
    pub const ZOOM_IN_KEY = ZOOM_IN_KEYS[0];
    pub const FIT_KEY = OVERVIEW_KEY;
    pub const HELP_KEY: rl.KeyboardKey = .f1;
    pub const OBJECTS_KEY: rl.KeyboardKey = .f3;
    pub const REROLL_KEY: rl.KeyboardKey = .e;
    pub const DELETE_KEY: rl.KeyboardKey = .delete;
    pub const COPY_KEY: rl.KeyboardKey = .c;
    pub const CUT_KEY: rl.KeyboardKey = .x;
    pub const PASTE_KEY: rl.KeyboardKey = .v;
    pub const NAV_KEYS = [2]rl.KeyboardKey{ .up, .down };
    pub const CTRL = keyGlyph(CTRL_KEYS[0]) ++ "+";
    pub const ALT = keyGlyph(ALT_KEYS[0]) ++ "+";
    pub const SHIFT_CAPTION = keyGlyph(SHIFT_KEYS[0]);
    pub const CTRL_SHIFT = CTRL ++ SHIFT_CAPTION ++ "+";
    pub const PLAY_CAPTION = keyGlyph(PLAY_KEY);
    pub const PLAY_HERE_CAPTION = keyGlyph(PLAY_HERE_KEY);
    pub const SAVE_CAPTION = CTRL ++ keyGlyph(SAVE_KEY);
    pub const SAVE_AS_CAPTION = CTRL_SHIFT ++ keyGlyph(SAVE_KEY);
    pub const OPEN_CAPTION = CTRL ++ keyGlyph(OPEN_KEY);
    pub const NEW_CAPTION = CTRL ++ keyGlyph(NEW_KEY);
    pub const UNDO_CAPTION = CTRL ++ keyGlyph(UNDO_KEY);
    pub const REDO_CAPTION = CTRL ++ keyGlyph(REDO_KEY) ++ " / " ++ CTRL_SHIFT ++ keyGlyph(UNDO_KEY);
    pub const TOOLS_CAPTION = blk: {
        var s: [:0]const u8 = TOOL_CAPTIONS[0] ++ " to " ++ TOOL_CAPTIONS[DIGIT_KEYS.len - 1];
        for (TOOL_CAPTIONS[DIGIT_KEYS.len..]) |c| s = s ++ " " ++ c;
        break :blk s;
    };
    pub const PAINT_CAPTION = glyphCaption(mouseName(PAINT_BUTTON));
    pub const ERASE_CAPTION = glyphCaption(mouseName(ERASE_BUTTON));
    pub const RECT_CAPTION = SHIFT_CAPTION ++ "+drag";
    pub const BRUSH_CAPTION = keyGlyph(SMALLER_KEY) ++ " " ++ keyGlyph(BIGGER_KEY);
    pub const SHAPES_CAPTION = blk: {
        var s: [:0]const u8 = SHAPE_CAPTIONS[0];
        for (SHAPE_CAPTIONS[1..]) |c| s = s ++ " " ++ c;
        break :blk s;
    };
    pub const PICK_CAPTION = ALT ++ PAINT_CAPTION;
    pub const ZOOM_CAPTION = keyGlyph(ZOOM_OUT_KEY) ++ " " ++ keyGlyph(ZOOM_IN_KEY);
    pub const FIT_CAPTION = keyGlyph(FIT_KEY);
    pub const HELP_CAPTION = keyGlyph(HELP_KEY);
    pub const OBJECTS_CAPTION = keyGlyph(OBJECTS_KEY);
    pub const REROLL_CAPTION = keyGlyph(REROLL_KEY);
    pub const DELETE_CAPTION = keyGlyph(DELETE_KEY);
    pub const COPY_CAPTION = CTRL ++ keyGlyph(COPY_KEY);
    pub const CUT_CAPTION = CTRL ++ keyGlyph(CUT_KEY);
    pub const PASTE_CAPTION = CTRL ++ keyGlyph(PASTE_KEY);
    pub const NAV_CAPTION = keyGlyph(NAV_KEYS[0]) ++ " " ++ keyGlyph(NAV_KEYS[1]);
    pub const PAN_CAPTION = blk: {
        for (PAN_KEYS) |w| {
            for (w.keys) |k| {
                if (k == .up or k == .down or k == .left or k == .right) break;
            } else @compileError("no arrow pans " ++ @tagName(w.d));
        }
        break :blk glyphCaption(mouseName(GRAB_BUTTON)) ++ " drag / " ++ glyphCaption(letters(&PAN_KEYS)) ++ " / " ++ glyphCaption(ARROWS);
    };
    pub const WHEEL_CAPTION = glyphCaption(WHEEL);
    pub const GRAPH_CAPTION = keyGlyph(GRAPH_KEY);
    pub const GO_CAPTION = keyGlyph(GO_KEY);
    pub const RENAME_CAPTION = keyGlyph(RENAME_KEY);
    pub const BACK_CAPTION = keyGlyph(BACK_KEY);
    pub const ENTER_CAPTION = keyGlyph(ENTER_KEYS[0]);
    pub const FULLSCREEN_CAPTION = ALT ++ ENTER_CAPTION;

    pub const BARE = [_][]const u8{ "play", "play_here", "graph", "go", "rename", "back", "smaller", "bigger", "zoom_in", "zoom_out", "fit", "help", "objects", "reroll", "delete" };
    pub const WITH_CTRL = [_][]const u8{ "open", "new", "copy", "cut", "paste" };
    pub const SHIFTED = [_][]const u8{ "save", "undo", "redo" };
    /// Shift turns the first of each pair, a `SHIFTED` command, into the second.
    pub const SHIFT_TWINS = [_][2][]const u8{ .{ "save", "save_as" }, .{ "undo", "redo" } };

    pub fn keyOf(comptime field: []const u8) rl.KeyboardKey {
        return @field(Desk, upper(field) ++ "_KEY");
    }

    comptime {
        @setEvalBranchQuota(20_000);
        var bare: []const rl.KeyboardKey = &TOOL_KEYS ++ &SHAPE_KEYS;
        for (PAN_KEYS) |w| bare = bare ++ w.keys;
        var ctrl: []const rl.KeyboardKey = &.{};
        var named: []const rl.KeyboardKey = &.{};
        for (BARE ++ WITH_CTRL ++ SHIFTED) |f| {
            const k = [_]rl.KeyboardKey{keyOf(f)};
            named = named ++ &k;
            const caption = upper(f) ++ "_CAPTION";
            const with_ctrl = @hasDecl(Desk, caption) and std.mem.startsWith(u8, @field(Desk, caption), CTRL);
            const listed_ctrl = for (BARE) |b| {
                if (std.mem.eql(u8, b, f)) break false;
            } else true;
            if (with_ctrl != listed_ctrl) @compileError(f ++ "'s caption and list disagree on Ctrl");
            if (listed_ctrl) ctrl = ctrl ++ &k else bare = bare ++ &k;
        }
        for (@typeInfo(Desk).@"struct".decls) |d| {
            if (!std.mem.endsWith(u8, d.name, "_KEY")) continue;
            if (std.mem.indexOfScalar(rl.KeyboardKey, named, @field(Desk, d.name)) == null) @compileError(d.name ++ " is in no list update reads");
        }
        for (SHIFT_TWINS) |t| {
            for (SHIFTED) |s| {
                if (std.mem.eql(u8, s, t[0])) break;
            } else @compileError(t[0] ++ " turns into " ++ t[1] ++ " with Shift but is not SHIFTED");
        }
        distinct(bare);
        distinct(ctrl);
    }

    pub fn distinct(comptime keys: []const rl.KeyboardKey) void {
        for (keys, 0..) |a, i| {
            for (keys[0..i]) |b| {
                if (a == b) @compileError("two desk keys on " ++ @tagName(a));
            }
        }
    }
};
