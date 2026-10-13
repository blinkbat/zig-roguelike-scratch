const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const PAD: i32 = 0;
const ENTER_KEYS = [_]rl.KeyboardKey{ .enter, .kp_enter };
const LEAN: rl.GamepadButton = .left_trigger_2;
const SHIFT_KEYS = [_]rl.KeyboardKey{ .left_shift, .right_shift };
const CTRL_KEYS = [_]rl.KeyboardKey{ .left_control, .right_control };
const LEAN_KEYS = SHIFT_KEYS;

/// What the player last pressed, which every caption names.
pub const Device = enum { pad, keys };

/// A caption built at compile time for each device, picked for `d`.
pub fn per(d: Device, comptime f: fn (comptime Device) [:0]const u8) [:0]const u8 {
    return switch (d) {
        inline else => |c| comptime f(c),
    };
}

pub fn moveName(comptime d: Device) [:0]const u8 {
    return switch (d) {
        .pad => "D-pad",
        .keys => comptime letters(&WALKS),
    };
}

/// The letter keys that walk up, left, down and right, as "WASD" reads.
fn letters(comptime walks: []const Walk) [:0]const u8 {
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

fn padName(comptime b: rl.GamepadButton) [:0]const u8 {
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
        else => @compileError("no caption for " ++ @tagName(b)),
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

    /// Its keys in menus, the first naming it; a slot's own key is its number (`SLOT_KEYS`).
    fn keys(b: Button) []const rl.KeyboardKey {
        return switch (b) {
            .a => &ENTER_KEYS,
            .x => &.{.space},
            .y => &.{.delete},
            .b, .lb, .rb, .rt => &.{},
            .view => &.{.tab},
            .pause => &.{.escape},
        };
    }

    fn isSlot(b: Button) bool {
        return std.mem.indexOfScalar(Button, &SLOT_ORDER, b) != null;
    }

    pub fn name(comptime b: Button, comptime d: Device) [:0]const u8 {
        return switch (d) {
            .pad => padName(b.pad()),
            .keys => if (b.keys().len == 0) @compileError(@tagName(b) ++ " has no key in menus") else keyName(b.keys()[0]),
        };
    }

    pub fn caption(b: Button, d: Device) [:0]const u8 {
        return switch (b) {
            inline else => |t| switch (d) {
                inline else => |c| comptime if (c == .keys and t.keys().len == 0) "" else t.name(c),
            },
        };
    }
};

/// The slots left to right, as the keyboard numbers them.
pub const SLOT_ORDER = [_]Button{ .lb, .a, .x, .y, .b, .rb, .rt };
const SLOT_KEYS = blk: {
    var out: [SLOT_ORDER.len]rl.KeyboardKey = undefined;
    for (&out, 0..) |*k, i| k.* = @enumFromInt(@intFromEnum(rl.KeyboardKey.one) + i);
    break :blk out;
};
const SLOT_CAPTIONS = blk: {
    var out: [SLOT_KEYS.len][:0]const u8 = undefined;
    for (SLOT_KEYS, &out) |k, *c| c.* = keyName(k);
    break :blk out;
};
const SECOND_KEYS = CTRL_KEYS;
pub const SECOND_CAPTION = keyName(SECOND_KEYS[0]);

const BUTTONS = std.enums.values(Button);

/// How long a button is held before `State.long` reports it.
pub const HOLD_S: f32 = 0.4;
const SPENT: f32 = -std.math.inf(f32);

/// raylib closes the window on Esc unless its exit key is cleared. Needs the window open.
pub fn claimKeys() void {
    rl.setExitKey(.null);
}

/// Schmitt trigger, then DAS and ARR; `settle` holds a new direction back so two keys a frame apart read as one diagonal.
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
        if (!stickWalks(defl, self.latched != null)) {
            const tap = self.owed;
            self.* = .{};
            return tap;
        }
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

    /// A diagonal that has not stepped survives one of its keys coming up first.
    fn owe(self: Stepper, now: mathx.Dir) ?mathx.Dir {
        const last = self.latched orelse return now;
        if (self.fired > 0) return if (partOf(now, last)) null else now;
        const o = self.owed orelse return now;
        return if (partOf(now, o)) o else now;
    }
};

/// The stick walks once pushed past `FIRE` and holds the walk down to `REARM`; short of that the d-pad and keys walk, the stick resting off centre or not.
fn stickWalks(defl: f32, was: bool) bool {
    return defl >= Stepper.FIRE or (was and defl >= Stepper.REARM);
}

fn partOf(d: mathx.Dir, diag: mathx.Dir) bool {
    if (!diag.diagonal() or d.diagonal()) return false;
    const a = diag.delta();
    const b = d.delta();
    return b.x == a.x or b.y == a.y;
}

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
    down_s: std.EnumArray(Button, f32) = .initFill(0),
    device: Device = .pad,
    fullscreen: bool = false,
    walk: ?mathx.Dir = null,
    lean: bool = false,
    step: Stepper = .{},
    /// The stick holds the walk, from passing `FIRE` until under `REARM`: the d-pad and keys walk only when it does not.
    stick: bool = false,
    /// Set before each `update`, which clears it: typing keys then type, and press no button.
    typing: bool = false,
    typed: Typed = .{},
    rub: bool = false,
    /// Set before each `update`: the number keys press the slots and the menu keys press none.
    playing: bool = false,
    /// Set before each `update`: the slot Ctrl holds, which the number keys skip.
    modifier: ?Button = null,

    pub fn hit(self: State, b: Button) bool {
        return self.pressed.contains(b);
    }

    pub fn held(self: State, b: Button) bool {
        return self.down.contains(b);
    }

    /// Down `HOLD_S` and not yet `spend`t: whatever takes it spends it.
    pub fn long(self: State, b: Button) bool {
        return self.down_s.get(b) >= HOLD_S;
    }

    /// A press used: holding it on reports no `long` until it is let go.
    pub fn spend(self: *State, b: Button) void {
        self.down_s.set(b, SPENT);
    }

    pub fn caption(self: State, b: Button) [:0]const u8 {
        return b.caption(self.device);
    }

    pub fn slotCaption(self: State, b: Button) [:0]const u8 {
        if (self.device == .pad or !b.isSlot()) return b.caption(self.device);
        if (b == self.modifier) return SECOND_CAPTION;
        return SLOT_CAPTIONS[numberOf(self.modifier, b).?];
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
            if (!alt_down and !(self.playing and b.isSlot())) {
                for (b.keys()) |k| {
                    if (self.typing and types(k)) continue;
                    on = on or rl.isKeyPressed(k);
                    hold = hold or rl.isKeyDown(k);
                }
            }
            self.pressed.setPresent(b, on);
            self.down.setPresent(b, hold);
        }
        if (self.playing and !alt_down) self.slotKeys();
        self.time(dt);
        var keyed = false;
        while (rl.getKeyPressed() != .null) keyed = true;
        self.fullscreen = fullscreenHit();
        self.lean = (pad and rl.isGamepadButtonDown(PAD, LEAN)) or (self.playing and either(LEAN_KEYS));
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
        const was_stick = self.stick;
        self.stick = stickWalks(defl, self.stick);
        if (!self.stick) {
            defl = 0;
            const digital = if (pad) dpadWalk() else null;
            if (digital orelse keyWalk(self.typing)) |p| {
                const d = if (self.lean) leanOf(mathx.dirTo(.{ .x = 0, .y = 0 }, p).?).delta() else p;
                defl = 1;
                heading = mathx.headingOf(@floatFromInt(d.x), @floatFromInt(d.y));
                settle = Stepper.SETTLE;
            }
        }
        self.walk = self.step.tick(dt, defl, heading, settle);
        self.typing = false;
        self.device = deviceOf(self.device, pad, (self.stick and !was_stick) or padPressed(pad), keyed);
    }

    fn slotKeys(self: *State) void {
        for (SLOT_ORDER) |b| {
            const keys: []const rl.KeyboardKey = if (b == self.modifier) &SECOND_KEYS else SLOT_KEYS[numberOf(self.modifier, b).?..][0..1];
            for (keys) |k| {
                if (rl.isKeyPressed(k)) self.pressed.insert(b);
                if (rl.isKeyDown(k)) self.down.insert(b);
            }
        }
    }

    fn time(self: *State, dt: f32) void {
        for (BUTTONS) |b| {
            const t = self.down_s.getPtr(b);
            t.* = if (self.down.contains(b)) t.* + dt else 0;
        }
    }
};

/// Its place among the slots the number keys reach, which skip the modifier's.
fn numberOf(modifier: ?Button, b: Button) ?usize {
    var n: usize = 0;
    for (SLOT_ORDER) |s| {
        if (s == modifier) continue;
        if (s == b) return n;
        n += 1;
    }
    return null;
}

fn deviceOf(was: Device, pad: bool, pad_hit: bool, keyed: bool) Device {
    if (!pad) return .keys;
    if (pad_hit) return .pad;
    return if (keyed) .keys else was;
}

fn padPressed(pad: bool) bool {
    if (!pad) return false;
    for (std.enums.values(rl.GamepadButton)) |b| {
        if (b != .unknown and rl.isGamepadButtonPressed(PAD, b)) return true;
    }
    return false;
}

/// The editor's, and the only mouse: it is a desk tool, so it names keys.
pub const Desk = struct {
    pub const TOOL_KEYS = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero, .minus };
    pub const TOOL_CAPTIONS = blk: {
        var out: [TOOL_KEYS.len][:0]const u8 = undefined;
        for (TOOL_KEYS, &out) |k, *c| c.* = keyName(k);
        break :blk out;
    };
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
    const CTRL = keyName(CTRL_KEYS[0]) ++ "+";
    const ALT = "Alt+";
    pub const SHIFT_CAPTION = keyName(SHIFT_KEYS[0]);
    const CTRL_SHIFT = CTRL ++ SHIFT_CAPTION ++ "+";
    pub const PLAY_CAPTION = keyName(PLAY_KEY);
    pub const PLAY_HERE_CAPTION = keyName(PLAY_HERE_KEY);
    pub const SAVE_CAPTION = CTRL ++ keyName(SAVE_KEY);
    pub const SAVE_AS_CAPTION = CTRL_SHIFT ++ keyName(SAVE_KEY);
    pub const OPEN_CAPTION = CTRL ++ keyName(OPEN_KEY);
    pub const NEW_CAPTION = CTRL ++ keyName(NEW_KEY);
    pub const UNDO_CAPTION = CTRL ++ keyName(UNDO_KEY);
    pub const REDO_CAPTION = CTRL ++ keyName(REDO_KEY) ++ " / " ++ CTRL_SHIFT ++ keyName(UNDO_KEY);
    pub const TOOLS_CAPTION = TOOL_CAPTIONS[0] ++ " to " ++ TOOL_CAPTIONS[TOOL_KEYS.len - 1];
    pub const PAINT_CAPTION = mouseName(PAINT_BUTTON);
    pub const ERASE_CAPTION = mouseName(ERASE_BUTTON);
    pub const RECT_CAPTION = SHIFT_CAPTION ++ "+drag";
    pub const BRUSH_CAPTION = keyName(SMALLER_KEY) ++ " " ++ keyName(BIGGER_KEY);
    pub const PAN_CAPTION = blk: {
        for (PAN_KEYS) |w| {
            for (w.keys) |k| {
                if (k == .up or k == .down or k == .left or k == .right) break;
            } else @compileError("no arrow pans " ++ @tagName(w.d));
        }
        break :blk mouseName(GRAB_BUTTON) ++ " drag / " ++ letters(&PAN_KEYS) ++ " / arrows";
    };
    pub const WHEEL_CAPTION = "wheel";
    pub const GRAPH_CAPTION = keyName(GRAPH_KEY);
    pub const GO_CAPTION = keyName(GO_KEY);
    pub const RENAME_CAPTION = keyName(RENAME_KEY);
    pub const BACK_CAPTION = keyName(BACK_KEY);
    pub const ENTER_CAPTION = keyName(ENTER_KEYS[0]);
    pub const FULLSCREEN_CAPTION = ALT ++ ENTER_CAPTION;

    comptime {
        var bare: []const rl.KeyboardKey = &TOOL_KEYS;
        for (PAN_KEYS) |w| bare = bare ++ w.keys;
        var ctrl: []const rl.KeyboardKey = &.{};
        for (@typeInfo(Desk).@"struct".decls) |d| {
            if (!std.mem.endsWith(u8, d.name, "_KEY")) continue;
            const k = [_]rl.KeyboardKey{@field(Desk, d.name)};
            const caption = d.name[0 .. d.name.len - "_KEY".len] ++ "_CAPTION";
            if (@hasDecl(Desk, caption) and std.mem.startsWith(u8, @field(Desk, caption), CTRL)) ctrl = ctrl ++ &k else bare = bare ++ &k;
        }
        distinct(bare);
        distinct(ctrl);
    }

    fn distinct(comptime keys: []const rl.KeyboardKey) void {
        for (keys, 0..) |a, i| {
            for (keys[0..i]) |b| {
                if (a == b) @compileError("two desk keys on " ++ @tagName(a));
            }
        }
    }

    mouse: mathx.P = .{ .x = 0, .y = 0 },
    moved: mathx.P = .{ .x = 0, .y = 0 },
    wheel: f32 = 0,
    paint: bool = false,
    paint_hit: bool = false,
    erase: bool = false,
    erase_hit: bool = false,
    grab: bool = false,
    shift: bool = false,
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

    pub fn clicked(self: *const Desk) bool {
        return self.paint_hit or self.erase_hit;
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
        const ctrl = either(CTRL_KEYS);
        self.shift = either(SHIFT_KEYS);
        self.pan = if (ctrl) .{ .x = 0, .y = 0 } else heldWalk(&PAN_KEYS, false);
        const hit = struct {
            fn f(k: rl.KeyboardKey) bool {
                return rl.isKeyPressed(k);
            }
        }.f;
        const bare = !ctrl;
        self.play = bare and hit(PLAY_KEY);
        self.play_here = bare and hit(PLAY_HERE_KEY);
        self.save = ctrl and !self.shift and hit(SAVE_KEY);
        self.save_as = ctrl and self.shift and hit(SAVE_KEY);
        self.open = ctrl and hit(OPEN_KEY);
        self.new = ctrl and hit(NEW_KEY);
        self.undo = ctrl and !self.shift and hit(UNDO_KEY);
        self.redo = ctrl and (hit(REDO_KEY) or (self.shift and hit(UNDO_KEY)));
        self.graph = bare and hit(GRAPH_KEY);
        self.go = bare and hit(GO_KEY);
        self.rename = bare and hit(RENAME_KEY);
        self.back = bare and hit(BACK_KEY);
        self.fullscreen = fullscreenHit();
        self.enter = !altDown() and anyHit(&ENTER_KEYS);
        self.rub = rubbed();
        self.smaller = bare and hit(SMALLER_KEY);
        self.bigger = bare and hit(BIGGER_KEY);
        self.tool = null;
        if (bare) {
            for (TOOL_KEYS, 0..) |k, i| {
                if (hit(k)) self.tool = i;
            }
        }
        self.typed.read();
    }
};

fn either(pair: [2]rl.KeyboardKey) bool {
    return rl.isKeyDown(pair[0]) or rl.isKeyDown(pair[1]);
}

fn altDown() bool {
    return either(.{ .left_alt, .right_alt });
}

fn fullscreenHit() bool {
    return altDown() and anyHit(&ENTER_KEYS);
}

const RUB_KEY: rl.KeyboardKey = .backspace;
pub const RUB_CAPTION = keyName(RUB_KEY);

fn rubbed() bool {
    return rl.isKeyPressed(RUB_KEY) or rl.isKeyPressedRepeat(RUB_KEY);
}

fn keyName(comptime k: rl.KeyboardKey) [:0]const u8 {
    return switch (k) {
        .f2 => "F2",
        .f5 => "F5",
        .f6 => "F6",
        .tab => "Tab",
        .escape => "Esc",
        .enter => "Enter",
        .space => "Space",
        .backspace => "Backspace",
        .delete => "Del",
        .left_control => "Ctrl",
        .left_shift => "Shift",
        .left_bracket => "[",
        .right_bracket => "]",
        .minus => "-",
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
    try std.testing.expectEqual(@as(?mathx.Dir, null), s.tick(mathx.FRAME_DT, 0.40, north, 0));
    try std.testing.expectEqual(@as(?mathx.Dir, .n), s.tick(mathx.FRAME_DT, 0.90, north, 0));
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
    const dt = mathx.FRAME_DT;
    for (0..31) |_| _ = s.tick(dt, 1, north, 0);
    var steps: usize = 0;
    if (s.tick(1.0, 1, north, 0) != null) steps += 1;
    for (0..4) |_| {
        if (s.tick(dt, 1, north, 0) != null) steps += 1;
    }
    std.debug.print("a 1 s stall, then 4 frames: {d} step(s)\n", .{steps});
    try std.testing.expectEqual(@as(usize, 1), steps);
}

test "a stick resting off centre leaves the d-pad and keys to walk, and a pushed one holds its walk down to rearming" {
    const resting = (Stepper.REARM + Stepper.FIRE) / 2;
    try std.testing.expect(!stickWalks(resting, false));
    try std.testing.expect(stickWalks(Stepper.FIRE, false));
    try std.testing.expect(stickWalks(resting, true));
    try std.testing.expect(!stickWalks(Stepper.REARM / 2, true));
}

test "a stick is steered, not re-pressed" {
    var s = Stepper{};
    try std.testing.expectEqual(@as(?mathx.Dir, .n), s.tick(mathx.FRAME_DT, 0.9, mathx.Dir.n.heading(), 0));
    try std.testing.expectEqual(@as(?mathx.Dir, null), s.tick(mathx.FRAME_DT, 0.9, mathx.Dir.n.heading(), 0));
    try std.testing.expectEqual(@as(?mathx.Dir, .e), s.tick(mathx.FRAME_DT, 0.9, mathx.Dir.e.heading(), 0));
    try std.testing.expectEqual(@as(?mathx.Dir, null), s.tick(mathx.FRAME_DT, 0.1, mathx.Dir.e.heading(), 0));
    try std.testing.expectEqual(@as(?mathx.Dir, .e), s.tick(mathx.FRAME_DT, 0.9, mathx.Dir.e.heading(), 0));
}

test "a d-pad diagonal pressed and released a frame apart is one diagonal step" {
    var s = Stepper{};
    const dt = mathx.FRAME_DT;
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
    const dt = mathx.FRAME_DT;
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
    const dt = mathx.FRAME_DT;
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
    const dt = mathx.FRAME_DT;
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

test "a held button reports long from HOLD_S until it is spent, and not again until it is let go" {
    const dt = mathx.FRAME_DT;
    var s = State{};
    s.down.insert(.view);
    var t: f32 = 0;
    while (!s.long(.view)) {
        t += dt;
        s.time(dt);
    }
    std.debug.print("held: long from {d:.3} s\n", .{t});
    try std.testing.expect(t >= HOLD_S and t - HOLD_S <= dt * 1.5);
    for (0..30) |_| s.time(dt);
    try std.testing.expect(s.long(.view));
    s.spend(.view);
    for (0..120) |_| {
        s.time(dt);
        try std.testing.expect(!s.long(.view));
    }
    s.down = .initEmpty();
    s.time(dt);
    s.down.insert(.view);
    for (0..60) |_| s.time(dt);
    try std.testing.expect(s.long(.view));
}

test "the last device pressed is the one named, and the keyboard when no pad is plugged in" {
    try std.testing.expectEqual(Device.keys, deviceOf(.pad, true, false, true));
    try std.testing.expectEqual(Device.pad, deviceOf(.keys, true, true, true));
    try std.testing.expectEqual(Device.keys, deviceOf(.keys, true, false, false));
    try std.testing.expectEqual(Device.pad, deviceOf(.pad, true, false, false));
    try std.testing.expectEqual(Device.keys, deviceOf(.pad, false, false, false));
}

test "the keyboard numbers the slots past the modifier, which Ctrl holds" {
    var s = State{ .device = .keys, .modifier = .lb };
    std.debug.print("slots, LB the modifier:", .{});
    for (SLOT_ORDER) |b| std.debug.print(" {s}={s}", .{ @tagName(b), s.slotCaption(b) });
    std.debug.print("\n", .{});
    try std.testing.expectEqualStrings(SECOND_CAPTION, s.slotCaption(.lb));
    try std.testing.expectEqualStrings("1", s.slotCaption(.a));
    try std.testing.expectEqualStrings("6", s.slotCaption(.rt));
    s.modifier = .x;
    try std.testing.expectEqualStrings("1", s.slotCaption(.lb));
    try std.testing.expectEqualStrings("3", s.slotCaption(.y));
    s.modifier = null;
    try std.testing.expectEqualStrings("7", s.slotCaption(.rt));
    try std.testing.expectEqualStrings("Tab", s.slotCaption(.view));
    s.device = .pad;
    try std.testing.expectEqualStrings("RT", s.slotCaption(.rt));
}

test "menus name dedicated keys, and the walk names WASD" {
    try std.testing.expectEqualStrings("WASD", moveName(.keys));
    try std.testing.expectEqualStrings("Enter", Button.a.caption(.keys));
    try std.testing.expectEqualStrings("Space", Button.x.caption(.keys));
    try std.testing.expectEqualStrings("Del", Button.y.caption(.keys));
    try std.testing.expectEqualStrings("Esc", Button.pause.caption(.keys));
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
