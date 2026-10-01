const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

// THE ONLY FILE THAT TOUCHES A DEVICE. The pad is primary and the only one the UI names; the keyboard mirrors it.

const PAD: i32 = 0;
const ENTER_KEYS = [_]rl.KeyboardKey{ .enter, .kp_enter };
const LEAN: rl.GamepadButton = .left_trigger_2;

pub const MOVE_CAPTION = "D-pad";
pub const LEAN_CAPTION = padName(LEAN);

fn padName(b: rl.GamepadButton) [:0]const u8 {
    return switch (b) {
        .right_face_down => "A",
        .right_face_right => "B",
        .right_face_left => "X",
        .right_face_up => "Y",
        .left_trigger_1 => "LB",
        .left_trigger_2 => "LT",
        .right_trigger_1 => "RB",
        .right_trigger_2 => "RT",
        .middle_left => "View",
        .middle_right => "Menu",
        else => "?",
    };
}

const Walk = struct {
    d: mathx.Dir,
    pad: ?rl.GamepadButton = null,
    keys: []const rl.KeyboardKey,
};

const WALKS = [_]Walk{
    .{ .d = .n, .pad = .left_face_up, .keys = &.{ .up, .w, .kp_8 } },
    .{ .d = .e, .pad = .left_face_right, .keys = &.{ .right, .d, .kp_6 } },
    .{ .d = .s, .pad = .left_face_down, .keys = &.{ .down, .s, .kp_2 } },
    .{ .d = .w, .pad = .left_face_left, .keys = &.{ .left, .a, .kp_4 } },
    .{ .d = .ne, .keys = &.{.kp_9} },
    .{ .d = .se, .keys = &.{.kp_3} },
    .{ .d = .sw, .keys = &.{.kp_1} },
    .{ .d = .nw, .keys = &.{.kp_7} },
};

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
    return @enumFromInt(@intFromEnum(d) + 1);
}

pub const Button = enum {
    a,
    b,
    x,
    y,
    lb,
    rb,
    rt,
    view,
    pause,

    fn pad(b: Button) rl.GamepadButton {
        return switch (b) {
            .a => .right_face_down,
            .b => .right_face_right,
            .x => .right_face_left,
            .y => .right_face_up,
            .lb => .left_trigger_1,
            .rb => .right_trigger_1,
            .rt => .right_trigger_2,
            .view => .middle_left,
            .pause => .middle_right,
        };
    }

    fn keys(b: Button) []const rl.KeyboardKey {
        return switch (b) {
            .a => &ENTER_KEYS,
            .b => &.{ .period, .kp_5 },
            .x => &.{ .f, .space },
            .y => &.{.e},
            .lb => &.{.q},
            .rb => &.{.r},
            .rt => &.{.t},
            .view => &.{.tab},
            .pause => &.{.escape},
        };
    }

    pub fn caption(b: Button) [:0]const u8 {
        return padName(b.pad());
    }
};

const BUTTONS = std.enums.values(Button);

/// raylib closes the window on Esc unless its exit key is cleared. Needs the window open.
pub fn claimKeys() void {
    rl.setExitKey(.null);
}

/// Schmitt trigger, then DAS and ARR; re-latches the moment it is steered. `settle` holds a new direction back so two
/// keys a frame apart read as one diagonal; a tap let go before it settles steps once, on release.
pub const Stepper = struct {
    pub const FIRE: f32 = 0.50;
    pub const REARM: f32 = 0.32;
    pub const DAS: f32 = 0.28;
    pub const ARR: f32 = 0.13;
    pub const SETTLE: f32 = 0.05;

    latched: ?mathx.Dir = null,
    held: f32 = 0,
    due: f32 = 0,
    fired: u32 = 0,
    /// How long before this frame's end the last step was due.
    late: f32 = 0,
    owed: ?mathx.Dir = null,

    pub fn tick(self: *Stepper, dt: f32, defl: f32, heading: f32, settle: f32) ?mathx.Dir {
        if (defl < REARM) {
            const tap = self.owed;
            self.* = .{};
            return tap;
        }
        if (self.latched == null and defl < FIRE) return null;
        const now = mathx.dirOf(heading, self.latched);
        if (self.latched != now) {
            const owed = self.owe(now);
            self.* = .{ .latched = now, .due = settle, .owed = owed };
        } else {
            self.held += dt;
        }
        if (self.held < self.due) return null;
        self.late = self.held - self.due;
        const gap: f32 = if (self.fired == 0) DAS else ARR;
        self.due += gap;
        if (self.due <= self.held) self.due = self.held + gap;
        self.fired += 1;
        self.owed = null;
        return now;
    }

    /// The key left over from a diagonal that stepped owes nothing; a diagonal that has not stepped survives one
    /// of its keys coming up first.
    fn owe(self: Stepper, now: mathx.Dir) ?mathx.Dir {
        const last = self.latched orelse return now;
        if (self.fired > 0) return if (partOf(now, last)) null else now;
        const o = self.owed orelse return now;
        return if (partOf(now, o)) o else now;
    }
};

fn partOf(d: mathx.Dir, diag: mathx.Dir) bool {
    if (!diag.diagonal() or d.diagonal()) return false;
    const a = diag.delta();
    const b = d.delta();
    return b.x == a.x or b.y == a.y;
}

/// Printable ascii typed this frame.
pub const Typed = struct {
    const MAX: usize = 16;
    buf: [MAX]u8 = undefined,
    n: usize = 0,

    pub fn text(self: *const Typed) []const u8 {
        return self.buf[0..self.n];
    }

    fn read(self: *Typed) void {
        self.n = 0;
        while (true) {
            const c = rl.getCharPressed();
            if (c == 0) break;
            if (c < ' ' or c > '~' or self.n == MAX) continue;
            self.buf[self.n] = @intCast(c);
            self.n += 1;
        }
    }
};

/// A key that types a character, which a field being typed in takes from the buttons and the walk.
fn types(k: rl.KeyboardKey) bool {
    const c = @intFromEnum(k);
    return (c >= @intFromEnum(rl.KeyboardKey.a) and c <= @intFromEnum(rl.KeyboardKey.z)) or
        (c >= @intFromEnum(rl.KeyboardKey.zero) and c <= @intFromEnum(rl.KeyboardKey.nine)) or
        (c >= @intFromEnum(rl.KeyboardKey.kp_0) and c <= @intFromEnum(rl.KeyboardKey.kp_9)) or
        k == .space or k == .period or k == .apostrophe or k == .minus;
}

pub const State = struct {
    pressed: std.EnumSet(Button) = .initEmpty(),
    down: std.EnumSet(Button) = .initEmpty(),
    fullscreen: bool = false,
    walk: ?mathx.Dir = null,
    lean: bool = false,
    step: Stepper = .{},
    /// Set by whatever is typed into, before each `update`, which it lasts: typing keys then type, and press no button.
    typing: bool = false,
    typed: Typed = .{},
    rub: bool = false,

    pub fn hit(self: State, b: Button) bool {
        return self.pressed.contains(b);
    }

    pub fn held(self: State, b: Button) bool {
        return self.down.contains(b);
    }

    /// Seconds since this frame's walk step was due; 0 when none fired.
    pub fn late(self: State) f32 {
        return if (self.walk != null) self.step.late else 0;
    }

    pub fn update(self: *State, dt: f32) void {
        const pad = rl.isGamepadAvailable(PAD);
        const alt_down = altDown();
        for (BUTTONS) |b| {
            var on = pad and rl.isGamepadButtonPressed(PAD, b.pad());
            var hold = pad and rl.isGamepadButtonDown(PAD, b.pad());
            if (!alt_down) {
                for (b.keys()) |k| {
                    if (self.typing and types(k)) continue;
                    on = on or rl.isKeyPressed(k);
                    hold = hold or rl.isKeyDown(k);
                }
            }
            self.pressed.setPresent(b, on);
            self.down.setPresent(b, hold);
        }
        self.fullscreen = fullscreenHit();
        self.lean = pad and rl.isGamepadButtonDown(PAD, LEAN);
        self.typed.n = 0;
        self.rub = false;
        if (self.typing) {
            self.typed.read();
            self.rub = rubbed();
        }

        var x: f32 = 0;
        var y: f32 = 0;
        if (pad) {
            x = rl.getGamepadAxisMovement(PAD, .left_x);
            y = rl.getGamepadAxisMovement(PAD, .left_y);
        }
        var defl = mathx.deflection(x, y);
        var heading = mathx.headingOf(x, y);
        var settle: f32 = 0;
        if (defl < Stepper.REARM) {
            var digital = if (pad) dpadWalk() else null;
            if (digital) |p| {
                if (self.lean) digital = leanOf(mathx.dirTo(.{ .x = 0, .y = 0 }, p).?).delta();
            }
            if (digital orelse keyWalk(self.typing)) |d| {
                defl = 1;
                heading = mathx.headingOf(@floatFromInt(d.x), @floatFromInt(d.y));
                settle = Stepper.SETTLE;
            }
        }
        self.walk = self.step.tick(dt, defl, heading, settle);
        self.typing = false;
    }
};

/// The editor's, and the only mouse: it is a desk tool, so it names keys.
pub const Desk = struct {
    pub const TOOL_KEYS = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero };
    pub const TOOL_CAPTIONS = blk: {
        var out: [TOOL_KEYS.len][:0]const u8 = undefined;
        for (TOOL_KEYS, &out) |k, *c| c.* = keyName(k);
        break :blk out;
    };
    /// The walk's d-pad directions, on the keys that are not the keypad's.
    const PAN_KEYS = blk: {
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
    const PAINT_BUTTON: rl.MouseButton = .left;
    const ERASE_BUTTON: rl.MouseButton = .right;
    const GRAB_BUTTON: rl.MouseButton = .middle;
    const PLAY_KEY: rl.KeyboardKey = .f5;
    const PLAY_HERE_KEY: rl.KeyboardKey = .f6;
    const SAVE_KEY: rl.KeyboardKey = .s;
    const OPEN_KEY: rl.KeyboardKey = .o;
    const NEW_KEY: rl.KeyboardKey = .n;
    const UNDO_KEY: rl.KeyboardKey = .z;
    const REDO_KEY: rl.KeyboardKey = .y;
    const GRAPH_KEY: rl.KeyboardKey = .tab;
    const GO_KEY: rl.KeyboardKey = .g;
    const RENAME_KEY: rl.KeyboardKey = .f2;
    const BACK_KEY: rl.KeyboardKey = .escape;
    const SMALLER_KEY: rl.KeyboardKey = .left_bracket;
    const BIGGER_KEY: rl.KeyboardKey = .right_bracket;
    const CTRL = "Ctrl+";
    pub const SHIFT_CAPTION = "Shift";
    pub const PLAY_CAPTION = keyName(PLAY_KEY);
    pub const PLAY_HERE_CAPTION = keyName(PLAY_HERE_KEY);
    pub const SAVE_CAPTION = CTRL ++ keyName(SAVE_KEY);
    pub const SAVE_AS_CAPTION = CTRL ++ SHIFT_CAPTION ++ "+" ++ keyName(SAVE_KEY);
    pub const OPEN_CAPTION = CTRL ++ keyName(OPEN_KEY);
    pub const NEW_CAPTION = CTRL ++ keyName(NEW_KEY);
    pub const UNDO_CAPTION = CTRL ++ keyName(UNDO_KEY);
    pub const REDO_CAPTION = CTRL ++ keyName(REDO_KEY) ++ " / " ++ CTRL ++ SHIFT_CAPTION ++ "+" ++ keyName(UNDO_KEY);
    pub const TOOLS_CAPTION = TOOL_CAPTIONS[0] ++ "-" ++ TOOL_CAPTIONS[TOOL_KEYS.len - 1];
    pub const PAINT_CAPTION = mouseName(PAINT_BUTTON);
    pub const ERASE_CAPTION = mouseName(ERASE_BUTTON);
    pub const RECT_CAPTION = SHIFT_CAPTION ++ "+drag";
    pub const BRUSH_CAPTION = keyName(SMALLER_KEY) ++ " " ++ keyName(BIGGER_KEY);
    pub const PAN_CAPTION = blk: {
        var letters: []const u8 = "";
        for ([_]mathx.Dir{ .n, .w, .s, .e }) |d| {
            const w = for (PAN_KEYS) |p| {
                if (p.d == d) break p;
            } else unreachable;
            var arrow = false;
            for (w.keys) |k| {
                if (k == .up or k == .down or k == .left or k == .right) {
                    arrow = true;
                } else letters = letters ++ keyName(k);
            }
            if (!arrow) @compileError("no arrow pans " ++ @tagName(d));
        }
        break :blk mouseName(GRAB_BUTTON) ++ " drag / " ++ letters ++ " / arrows";
    };
    pub const WHEEL_CAPTION = "wheel";
    pub const GRAPH_CAPTION = keyName(GRAPH_KEY);
    pub const GO_CAPTION = keyName(GO_KEY);
    pub const RENAME_CAPTION = keyName(RENAME_KEY);
    pub const BACK_CAPTION = keyName(BACK_KEY);
    pub const ENTER_CAPTION = keyName(ENTER_KEYS[0]);
    pub const FULLSCREEN_CAPTION = "Alt+" ++ ENTER_CAPTION;

    comptime {
        var bare: []const rl.KeyboardKey = &(TOOL_KEYS ++ [_]rl.KeyboardKey{ PLAY_KEY, PLAY_HERE_KEY, GRAPH_KEY, GO_KEY, RENAME_KEY, BACK_KEY, SMALLER_KEY, BIGGER_KEY });
        for (PAN_KEYS) |w| bare = bare ++ w.keys;
        distinct(bare);
        distinct(&.{ SAVE_KEY, OPEN_KEY, NEW_KEY, UNDO_KEY, REDO_KEY });
    }

    fn distinct(comptime keys: []const rl.KeyboardKey) void {
        for (keys, 0..) |a, i| {
            for (keys[0..i]) |b| {
                if (a == b) @compileError("two desk keys on " ++ @tagName(a));
            }
        }
    }

    mouse: mathx.P = .{ .x = 0, .y = 0 },
    /// Pixels the mouse moved since the last frame.
    moved: mathx.P = .{ .x = 0, .y = 0 },
    wheel: f32 = 0,
    paint: bool = false,
    paint_hit: bool = false,
    erase: bool = false,
    erase_hit: bool = false,
    grab: bool = false,
    shift: bool = false,
    /// Held pan keys, one step on each axis.
    pan: mathx.P = .{ .x = 0, .y = 0 },
    play: bool = false,
    play_here: bool = false,
    save: bool = false,
    save_as: bool = false,
    open: bool = false,
    new: bool = false,
    undo: bool = false,
    redo: bool = false,
    graph: bool = false,
    go: bool = false,
    rename: bool = false,
    back: bool = false,
    enter: bool = false,
    fullscreen: bool = false,
    rub: bool = false,
    smaller: bool = false,
    bigger: bool = false,
    tool: ?usize = null,
    typed: Typed = .{},

    pub fn text(self: *const Desk) []const u8 {
        return self.typed.text();
    }

    pub fn update(self: *Desk) void {
        const m = rl.getMousePosition();
        const d = rl.getMouseDelta();
        self.mouse = .{ .x = @intFromFloat(m.x), .y = @intFromFloat(m.y) };
        self.moved = .{ .x = @intFromFloat(d.x), .y = @intFromFloat(d.y) };
        self.wheel = rl.getMouseWheelMove();
        self.paint = rl.isMouseButtonDown(PAINT_BUTTON);
        self.paint_hit = rl.isMouseButtonPressed(PAINT_BUTTON);
        self.erase = rl.isMouseButtonDown(ERASE_BUTTON);
        self.erase_hit = rl.isMouseButtonPressed(ERASE_BUTTON);
        self.grab = rl.isMouseButtonDown(GRAB_BUTTON);
        const ctrl = either(.left_control, .right_control);
        self.shift = either(.left_shift, .right_shift);
        self.pan = if (ctrl) .{ .x = 0, .y = 0 } else heldWalk(&PAN_KEYS, false);
        const hit = struct {
            fn f(k: rl.KeyboardKey) bool {
                return rl.isKeyPressed(k);
            }
        }.f;
        self.play = hit(PLAY_KEY);
        self.play_here = hit(PLAY_HERE_KEY);
        self.save = ctrl and !self.shift and hit(SAVE_KEY);
        self.save_as = ctrl and self.shift and hit(SAVE_KEY);
        self.open = ctrl and hit(OPEN_KEY);
        self.new = ctrl and hit(NEW_KEY);
        self.undo = ctrl and !self.shift and hit(UNDO_KEY);
        self.redo = ctrl and (hit(REDO_KEY) or (self.shift and hit(UNDO_KEY)));
        self.graph = hit(GRAPH_KEY);
        self.go = !ctrl and hit(GO_KEY);
        self.rename = hit(RENAME_KEY);
        self.back = hit(BACK_KEY);
        self.fullscreen = fullscreenHit();
        self.enter = !altDown() and anyHit(&ENTER_KEYS);
        self.rub = rubbed();
        self.smaller = hit(SMALLER_KEY);
        self.bigger = hit(BIGGER_KEY);
        self.tool = null;
        if (!ctrl) {
            for (TOOL_KEYS, 0..) |k, i| {
                if (hit(k)) self.tool = i;
            }
        }
        self.typed.read();
    }
};

fn either(l: rl.KeyboardKey, r: rl.KeyboardKey) bool {
    return rl.isKeyDown(l) or rl.isKeyDown(r);
}

fn altDown() bool {
    return either(.left_alt, .right_alt);
}

fn fullscreenHit() bool {
    return altDown() and anyHit(&ENTER_KEYS);
}

/// Backspace, pressed or held into repeat.
fn rubbed() bool {
    return rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace);
}

/// What the editor's crib calls a key.
fn keyName(comptime k: rl.KeyboardKey) [:0]const u8 {
    return switch (k) {
        .f2 => "F2",
        .f5 => "F5",
        .f6 => "F6",
        .tab => "Tab",
        .escape => "Esc",
        .enter => "Enter",
        .left_bracket => "[",
        .right_bracket => "]",
        .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z => &[_:0]u8{std.ascii.toUpper(@tagName(k)[0])},
        .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine => &[_:0]u8{'0' + @intFromEnum(k) - @intFromEnum(rl.KeyboardKey.zero)},
        else => @compileError("no caption for " ++ @tagName(k)),
    };
}

fn anyHit(keys: []const rl.KeyboardKey) bool {
    for (keys) |k| {
        if (rl.isKeyPressed(k)) return true;
    }
    return false;
}

fn nonZero(p: mathx.P) ?mathx.P {
    return if (p.x == 0 and p.y == 0) null else p;
}

fn dpadWalk() ?mathx.P {
    var p = mathx.P{ .x = 0, .y = 0 };
    for (WALKS) |w| {
        const b = w.pad orelse continue;
        if (rl.isGamepadButtonDown(PAD, b)) p = p.add(w.d.delta());
    }
    return nonZero(p);
}

fn keyWalk(typing: bool) ?mathx.P {
    return nonZero(heldWalk(&WALKS, typing));
}

/// Each walk with a key of it held, once however many are.
fn heldWalk(walks: []const Walk, typing: bool) mathx.P {
    var p = mathx.P{ .x = 0, .y = 0 };
    for (walks) |w| {
        for (w.keys) |k| {
            if ((typing and types(k)) or !rl.isKeyDown(k)) continue;
            p = p.add(w.d.delta());
            break;
        }
    }
    return p;
}

/// What the editor's crib calls a mouse button.
fn mouseName(comptime b: rl.MouseButton) [:0]const u8 {
    return switch (b) {
        .left => "LMB",
        .right => "RMB",
        .middle => "MMB",
        else => @compileError("no caption for " ++ @tagName(b)),
    };
}

test "the walk fires once, waits DAS, then repeats at ARR" {
    var s = Stepper{};
    const north = mathx.Dir.n.heading();
    try std.testing.expectEqual(@as(?mathx.Dir, null), s.tick(0.016, 0.40, north, 0));
    try std.testing.expectEqual(@as(?mathx.Dir, .n), s.tick(0.016, 0.90, north, 0));
    const dt: f32 = 1.0 / 600.0;
    var gaps: [4]f32 = undefined;
    var n: usize = 0;
    var t: f32 = 0;
    var last: f32 = 0;
    while (n < gaps.len and t < 3.0) {
        t += dt;
        if (s.tick(dt, 0.90, north, 0) != null) {
            gaps[n] = t - last;
            last = t;
            n += 1;
        }
    }
    std.debug.print("first repeat {d:.3} s, then {d:.3} {d:.3} {d:.3} s\n", .{ gaps[0], gaps[1], gaps[2], gaps[3] });
    try std.testing.expect(@abs(gaps[0] - Stepper.DAS) <= dt * 2);
    for (gaps[1..]) |g| try std.testing.expect(@abs(g - Stepper.ARR) <= dt * 2);
}

test "a stalled frame does not bank repeats" {
    var s = Stepper{};
    const north = mathx.Dir.n.heading();
    const dt: f32 = 1.0 / 60.0;
    for (0..31) |_| _ = s.tick(dt, 1, north, 0);
    var steps: usize = 0;
    if (s.tick(1.0, 1, north, 0) != null) steps += 1;
    for (0..4) |_| {
        if (s.tick(dt, 1, north, 0) != null) steps += 1;
    }
    std.debug.print("a 1 s stall, then 4 frames: {d} step(s)\n", .{steps});
    try std.testing.expectEqual(@as(usize, 1), steps);
}

test "a stick is steered, not re-pressed" {
    var s = Stepper{};
    try std.testing.expectEqual(@as(?mathx.Dir, .n), s.tick(0.016, 0.9, mathx.Dir.n.heading(), 0));
    try std.testing.expectEqual(@as(?mathx.Dir, null), s.tick(0.016, 0.9, mathx.Dir.n.heading(), 0));
    try std.testing.expectEqual(@as(?mathx.Dir, .e), s.tick(0.016, 0.9, mathx.Dir.e.heading(), 0));
    try std.testing.expectEqual(@as(?mathx.Dir, null), s.tick(0.016, 0.1, mathx.Dir.e.heading(), 0));
    try std.testing.expectEqual(@as(?mathx.Dir, .e), s.tick(0.016, 0.9, mathx.Dir.e.heading(), 0));
}

test "a d-pad diagonal pressed and released a frame apart is one diagonal step" {
    var s = Stepper{};
    const dt: f32 = 1.0 / 60.0;
    const settle = Stepper.SETTLE;
    var steps: [8]?mathx.Dir = undefined;
    steps[0] = s.tick(dt, 1, mathx.Dir.n.heading(), settle);
    steps[1] = s.tick(dt, 1, mathx.Dir.ne.heading(), settle);
    for (steps[2..6]) |*st| st.* = s.tick(dt, 1, mathx.Dir.ne.heading(), settle);
    steps[6] = s.tick(dt, 1, mathx.Dir.e.heading(), settle);
    steps[7] = s.tick(dt, 0, 0, settle);
    var got: usize = 0;
    for (steps) |st| {
        if (st) |d| {
            try std.testing.expectEqual(mathx.Dir.ne, d);
            got += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), got);
}

test "a tap let go before it settles steps once, on release" {
    var s = Stepper{};
    const dt: f32 = 1.0 / 60.0;
    const settle = Stepper.SETTLE;
    const got = [_]?mathx.Dir{
        s.tick(dt, 1, mathx.Dir.n.heading(), settle),
        s.tick(dt, 1, mathx.Dir.n.heading(), settle),
        s.tick(dt, 0, 0, settle),
        s.tick(dt, 0, 0, settle),
    };
    try std.testing.expectEqualSlices(?mathx.Dir, &.{ null, null, .n, null }, &got);
}

test "a quick diagonal tap let go one key at a time steps the diagonal" {
    var s = Stepper{};
    const dt: f32 = 1.0 / 60.0;
    const settle = Stepper.SETTLE;
    const got = [_]?mathx.Dir{
        s.tick(dt, 1, mathx.Dir.n.heading(), settle),
        s.tick(dt, 1, mathx.Dir.ne.heading(), settle),
        s.tick(dt, 1, mathx.Dir.n.heading(), settle),
        s.tick(dt, 0, 0, settle),
    };
    try std.testing.expectEqualSlices(?mathx.Dir, &.{ null, null, null, .ne }, &got);
}

test "a held walk that has stepped owes nothing when it is let go" {
    var s = Stepper{};
    const dt: f32 = 1.0 / 60.0;
    var steps: usize = 0;
    const held: usize = @intFromFloat(@ceil((Stepper.SETTLE + Stepper.DAS) / dt) + 2);
    for (0..held) |_| {
        if (s.tick(dt, 1, mathx.Dir.e.heading(), Stepper.SETTLE) != null) steps += 1;
    }
    if (s.tick(dt, 0, 0, Stepper.SETTLE) != null) steps += 1;
    try std.testing.expectEqual(@as(usize, 2), steps);
}

test "every direction walks on exactly one entry, and every bound key a name types into is taken from its button" {
    var seen = [_]usize{0} ** mathx.ALL_DIRS.len;
    for (WALKS) |w| seen[@intFromEnum(w.d)] += 1;
    for (seen) |n| try std.testing.expectEqual(@as(usize, 1), n);
    for (BUTTONS) |b| {
        for (b.keys()) |k| {
            const c = @intFromEnum(k);
            if (c > ' ' and c <= '~') try std.testing.expect(types(k));
        }
    }
}

test "every button the ui names has a caption" {
    for (BUTTONS) |b| try std.testing.expect(!std.mem.eql(u8, b.caption(), "?"));
    try std.testing.expect(!std.mem.eql(u8, LEAN_CAPTION, "?"));
}

test "the lean layer puts each d-pad button on its own diagonal" {
    var seen = [_]bool{false} ** mathx.ALL_DIRS.len;
    for (DPAD) |c| {
        const d = leanOf(c);
        try std.testing.expect(d.diagonal());
        try std.testing.expect(!seen[@intFromEnum(d)]);
        seen[@intFromEnum(d)] = true;
    }
    try std.testing.expectEqual(mathx.Dir.ne, leanOf(.n));
    try std.testing.expectEqual(mathx.Dir.nw, leanOf(.w));
    try std.testing.expectEqual(mathx.Dir.se, leanOf(.se));
}
