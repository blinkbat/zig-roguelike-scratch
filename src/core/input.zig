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
    /// Set by whatever is typed into, before `update`: typing keys then type, and press no button.
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
        const alt_down = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
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
        self.fullscreen = alt_down and anyHit(&ENTER_KEYS);
        self.lean = pad and rl.isGamepadButtonDown(PAD, LEAN);
        self.typed.n = 0;
        self.rub = false;
        if (self.typing) {
            self.typed.read();
            self.rub = rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace);
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
    }
};

/// The editor's, and the only mouse: it is a desk tool, so it names keys.
pub const Desk = struct {
    pub const TOOL_KEYS = [_]struct { key: rl.KeyboardKey, name: [:0]const u8 }{
        .{ .key = .one, .name = "1" },   .{ .key = .two, .name = "2" },   .{ .key = .three, .name = "3" },
        .{ .key = .four, .name = "4" },  .{ .key = .five, .name = "5" },  .{ .key = .six, .name = "6" },
        .{ .key = .seven, .name = "7" }, .{ .key = .eight, .name = "8" }, .{ .key = .nine, .name = "9" },
        .{ .key = .zero, .name = "0" },
    };
    const PAN_KEYS = [_]struct { d: mathx.Dir, keys: [2]rl.KeyboardKey }{
        .{ .d = .n, .keys = .{ .w, .up } },
        .{ .d = .e, .keys = .{ .d, .right } },
        .{ .d = .s, .keys = .{ .s, .down } },
        .{ .d = .w, .keys = .{ .a, .left } },
    };
    pub const PLAY_CAPTION = "F5";
    pub const PLAY_HERE_CAPTION = "F6";
    pub const SAVE_CAPTION = "Ctrl+S";
    pub const SAVE_AS_CAPTION = "Ctrl+Shift+S";
    pub const OPEN_CAPTION = "Ctrl+O";
    pub const NEW_CAPTION = "Ctrl+N";
    pub const UNDO_CAPTION = "Ctrl+Z";
    pub const REDO_CAPTION = "Ctrl+Y / Ctrl+Shift+Z";
    pub const TOOLS_CAPTION = TOOL_KEYS[0].name ++ "-" ++ TOOL_KEYS[TOOL_KEYS.len - 1].name;
    pub const PAINT_CAPTION = "LMB";
    pub const ERASE_CAPTION = "RMB";
    pub const RECT_CAPTION = "Shift+drag";
    pub const BRUSH_CAPTION = "[ ]";
    pub const PAN_CAPTION = "MMB drag / WASD / arrows";
    pub const WHEEL_CAPTION = "wheel";
    pub const FULLSCREEN_CAPTION = "Alt+Enter";
    pub const GRAPH_CAPTION = "Tab";
    pub const GO_CAPTION = "G";
    pub const RENAME_CAPTION = "F2";
    pub const BACK_CAPTION = "Esc";
    pub const ENTER_CAPTION = "Enter";

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
        self.paint = rl.isMouseButtonDown(.left);
        self.paint_hit = rl.isMouseButtonPressed(.left);
        self.erase = rl.isMouseButtonDown(.right);
        self.erase_hit = rl.isMouseButtonPressed(.right);
        self.grab = rl.isMouseButtonDown(.middle);
        const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
        self.shift = rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift);
        self.pan = .{ .x = 0, .y = 0 };
        if (!ctrl) {
            for (PAN_KEYS) |w| {
                for (w.keys) |k| {
                    if (!rl.isKeyDown(k)) continue;
                    self.pan = self.pan.add(w.d.delta());
                    break;
                }
            }
        }
        const hit = struct {
            fn f(k: rl.KeyboardKey) bool {
                return rl.isKeyPressed(k);
            }
        }.f;
        self.play = hit(.f5);
        self.play_here = hit(.f6);
        self.save = ctrl and !self.shift and hit(.s);
        self.save_as = ctrl and self.shift and hit(.s);
        self.open = ctrl and hit(.o);
        self.new = ctrl and hit(.n);
        self.undo = ctrl and !self.shift and hit(.z);
        self.redo = ctrl and (hit(.y) or (self.shift and hit(.z)));
        self.graph = hit(.tab);
        self.go = !ctrl and hit(.g);
        self.rename = hit(.f2);
        self.back = hit(.escape);
        const alt = rl.isKeyDown(.left_alt) or rl.isKeyDown(.right_alt);
        self.fullscreen = alt and anyHit(&ENTER_KEYS);
        self.enter = !alt and anyHit(&ENTER_KEYS);
        self.rub = hit(.backspace) or rl.isKeyPressedRepeat(.backspace);
        self.smaller = hit(.left_bracket);
        self.bigger = hit(.right_bracket);
        self.tool = null;
        if (!ctrl) {
            for (TOOL_KEYS, 0..) |k, i| {
                if (hit(k.key)) self.tool = i;
            }
        }
        self.typed.read();
    }
};

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
    var p = mathx.P{ .x = 0, .y = 0 };
    for (WALKS) |w| {
        for (w.keys) |k| {
            if ((typing and types(k)) or !rl.isKeyDown(k)) continue;
            p = p.add(w.d.delta());
            break;
        }
    }
    return nonZero(p);
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
