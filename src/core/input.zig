const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

const ENTER_KEYS = [_]rl.KeyboardKey{ .enter, .kp_enter };
const INTERACT_KEYS = ENTER_KEYS ++ [_]rl.KeyboardKey{.space};
const LEAN: rl.GamepadButton = .left_trigger_2;
const SHIFT_KEYS = [_]rl.KeyboardKey{ .left_shift, .right_shift };
const CTRL_KEYS = [_]rl.KeyboardKey{ .left_control, .right_control };
const ALT_KEYS = [_]rl.KeyboardKey{ .left_alt, .right_alt };
const LEAN_KEYS = SHIFT_KEYS;

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

extern fn glfwGetJoystickGUID(jid: c_int) ?[*:0]const u8;
extern fn glfwJoystickIsGamepad(jid: c_int) c_int;

/// raylib's MAX_GAMEPADS, the slots it polls.
const PADS: usize = 4;

fn mapped(at: i32) bool {
    return rl.isGamepadAvailable(at) and glfwJoystickIsGamepad(at) != 0;
}

fn choosePad(was: ?i32, focused: bool, before: *const [PADS]Triggers, now: *const [PADS]Triggers) ?i32 {
    for (0..PADS) |i| {
        const at: i32 = @intCast(i);
        if (focused and mapped(at) and struck(at, before, now)) return at;
    }
    if (was) |w| {
        if (mapped(w)) return w;
    }
    for (0..PADS) |i| {
        const at: i32 = @intCast(i);
        if (mapped(at)) return at;
    }
    return null;
}

fn kindAt(at: i32) Device {
    return padOf(std.mem.span(glfwGetJoystickGUID(at) orelse return .xbox));
}

const SONY = "4c05";
const PS5_PRODUCTS = [_]*const [USB_ID]u8{ "e60c", "f20d" };
const USB_ID = SONY.len;
const VENDOR_AT = 8;
const PRODUCT_AT = 16;

/// GLFW GUID vendor/product bytes are little-endian at offsets 8/16; XInput defaults to Xbox.
fn padOf(guid: []const u8) Device {
    if (guid.len < PRODUCT_AT + USB_ID or !std.mem.eql(u8, guid[VENDOR_AT..][0..USB_ID], SONY)) return .xbox;
    for (PS5_PRODUCTS) |p| {
        if (std.mem.eql(u8, guid[PRODUCT_AT..][0..USB_ID], p)) return .ps5;
    }
    return .ps4;
}

/// SDL_GameControllerDB (see assets/gamecontrollerdb-LICENSE); environment and adjacent file override it.
const MAPPINGS_FILE = "gamecontrollerdb.txt";
const MAPPINGS = @embedFile(MAPPINGS_FILE);
const MAPPINGS_ENV = "SDL_GAMECONTROLLERCONFIG";
const MAPPINGS_MAX: usize = 4 << 20;

/// Needs the window open.
pub fn mapPads() void {
    _ = rl.setGamepadMappings(MAPPINGS);
    const a = std.heap.page_allocator;
    if (std.process.getEnvVarOwned(a, MAPPINGS_ENV)) |env| {
        defer a.free(env);
        if (a.dupeZ(u8, env)) |z| {
            defer a.free(z);
            _ = rl.setGamepadMappings(z);
        } else |_| {}
    } else |_| {}
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const here = std.fs.selfExeDirPath(&buf) catch return;
    var dir = std.fs.openDirAbsolute(here, .{}) catch return;
    defer dir.close();
    const file = dir.readFileAllocOptions(a, MAPPINGS_FILE, MAPPINGS_MAX, null, 1, 0) catch return;
    defer a.free(file);
    _ = rl.setGamepadMappings(file);
}

const Trigger = enum {
    left,
    right,

    fn axis(t: Trigger) rl.GamepadAxis {
        return switch (t) {
            .left => .left_trigger,
            .right => .right_trigger,
        };
    }

    fn of(b: rl.GamepadButton) ?Trigger {
        return switch (b) {
            .left_trigger_2 => .left,
            .right_trigger_2 => .right,
            else => null,
        };
    }
};

/// Trigger hysteresis avoids raylib's 55% threshold chatter.
const TRIGGER_ON: f32 = 0.6;
const TRIGGER_OFF: f32 = 0.4;

const Triggers = std.EnumArray(Trigger, bool);

fn pulled(at: i32, was: Triggers) Triggers {
    var now = Triggers.initFill(false);
    if (!mapped(at)) return now;
    for (std.enums.values(Trigger)) |t| now.set(t, latch((rl.getGamepadAxisMovement(at, t.axis()) + 1) / 2, was.get(t)));
    return now;
}

fn edge(was: Triggers, now: Triggers, t: Trigger) bool {
    return now.get(t) and !was.get(t);
}

fn rose(was: Triggers, now: Triggers) bool {
    for (std.enums.values(Trigger)) |t| {
        if (edge(was, now, t)) return true;
    }
    return false;
}

fn struck(at: i32, before: *const [PADS]Triggers, now: *const [PADS]Triggers) bool {
    const i: usize = @intCast(at);
    return padPressed(at) or rose(before[i], now[i]);
}

fn latch(travel: f32, was: bool) bool {
    return travel >= if (was) TRIGGER_OFF else TRIGGER_ON;
}

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

/// raylib names a pad's buttons by place, as GLFW maps every pad onto Xbox's.
fn padName(comptime b: rl.GamepadButton, comptime d: Device) [:0]const u8 {
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
    fn keys(b: Button) []const rl.KeyboardKey {
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

    fn isSlot(b: Button) bool {
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
const SLOT_KEYS = blk: {
    var out: [SLOT_ORDER.len]rl.KeyboardKey = undefined;
    for (&out, 0..) |*k, i| k.* = @enumFromInt(@intFromEnum(rl.KeyboardKey.one) + i);
    break :blk out;
};
const SLOT_CAPTIONS = captions(&SLOT_KEYS);

fn captions(comptime keys: []const rl.KeyboardKey) [keys.len][:0]const u8 {
    var out: [keys.len][:0]const u8 = undefined;
    for (keys, &out) |k, *c| c.* = keyName(k);
    return out;
}

pub fn glyphCaption(comptime text: []const u8) [:0]const u8 {
    return "\x1e" ++ text ++ "\x1f";
}

fn keyGlyph(comptime key: rl.KeyboardKey) [:0]const u8 {
    return glyphCaption(keyName(key));
}

fn glyphCaptions(comptime keys: []const rl.KeyboardKey) [keys.len][:0]const u8 {
    var out: [keys.len][:0]const u8 = undefined;
    for (keys, &out) |key, *text| text.* = keyGlyph(key);
    return out;
}
const SECOND_KEYS = CTRL_KEYS;
pub const SECOND_CAPTION = keyName(SECOND_KEYS[0]);

const BUTTONS = std.enums.values(Button);

/// raylib closes the window on Esc unless its exit key is cleared. Needs the window open.
pub fn claimKeys() void {
    rl.setExitKey(.null);
}

/// Schmitt trigger plus DAS/ARR; `settle` merges staggered key presses into diagonals.
pub const Stepper = struct {
    pub const FIRE: f32 = 0.50;
    const REARM: f32 = 0.32;
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
            if (self.latched) |last| {
                if (self.due == HELD and partOf(now, last)) {
                    self.latched = now;
                    return null;
                }
            }
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

    /// Rearm only on release or direction change; staggered diagonal release stays held.
    pub fn hold(self: *Stepper) void {
        self.* = .{ .latched = self.latched, .held = self.held, .due = HELD, .fired = 1 };
    }

    const HELD = std.math.inf(f32);

    /// A diagonal that has not stepped survives one of its keys coming up first.
    fn owe(self: Stepper, now: mathx.Dir) ?mathx.Dir {
        const last = self.latched orelse return now;
        if (self.fired > 0) return if (partOf(now, last)) null else now;
        const o = self.owed orelse return now;
        return if (partOf(now, o)) o else now;
    }
};

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

pub const TreeInput = struct {
    move: ?rl.Vector2 = null,
    pan: rl.Vector2 = .{ .x = 0, .y = 0 },
    zoom: f32 = 0,
    reset: bool = false,
    dt: f32 = 0,
};

const RadialStepper = struct {
    direction: ?rl.Vector2 = null,
    wait: f32 = 0,

    fn tick(self: *RadialStepper, dt: f32, x: f32, y: f32) ?rl.Vector2 {
        const magnitude = std.math.hypot(x, y);
        if (!stickWalks(magnitude, self.direction != null)) {
            self.* = .{};
            return null;
        }
        const next = rl.Vector2{ .x = x / magnitude, .y = y / magnitude };
        const turned = if (self.direction) |old| old.x * next.x + old.y * next.y < 0.766 else true;
        if (turned) {
            self.direction = next;
            self.wait = Stepper.DAS;
            return next;
        }
        self.wait -= dt;
        if (self.wait > 0) return null;
        self.wait = Stepper.ARR;
        self.direction = next;
        return next;
    }
};

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

/// The passive tree's keyboard zoom and overview; browsing walks and panning shifts the walk.
pub const TreeKeys = struct {
    const ZOOM_IN = [2]rl.KeyboardKey{ .equal, .kp_add };
    const ZOOM_OUT = [2]rl.KeyboardKey{ .minus, .kp_subtract };
    const PAGE_IN: rl.KeyboardKey = .page_up;
    const PAGE_OUT: rl.KeyboardKey = .page_down;
    const OVERVIEW: rl.KeyboardKey = .home;
    pub const BROWSE_CAPTION = letters(&WALKS);
    pub const ZOOM_IN_CAPTION = keyName(ZOOM_IN[0]);
    pub const ZOOM_OUT_CAPTION = keyName(ZOOM_OUT[0]);
    pub const OVERVIEW_CAPTION = keyName(OVERVIEW);
};

pub const State = struct {
    pub const Context = enum { menu, play, target, tree };

    pressed: std.EnumSet(Button) = .initEmpty(),
    down: std.EnumSet(Button) = .initEmpty(),
    device: Device = .xbox,
    focused: bool = true,
    fullscreen: bool = false,
    character_page: ?CharacterPage = null,
    walk: ?mathx.Dir = null,
    lean: bool = false,
    step: Stepper = .{},
    radial: RadialStepper = .{},
    tree: TreeInput = .{},
    /// A latched stick takes priority over digital movement.
    stick: bool = false,
    /// Set before each `update`, which clears it: typing keys then type, and press no button.
    typing: bool = false,
    typed: Typed = .{},
    rub: bool = false,
    /// Play uses numbered slots; menus and targeting use standard confirm/back keys.
    context: Context = .menu,
    /// Set before each `update`: Ctrl holds the modifier though the number keys press no slot.
    sets: bool = false,
    /// Set before each `update`: the slot Ctrl holds, which the number keys skip.
    modifier: ?Button = null,
    /// Set before each `update`: in targeting, the slot whose own number key confirms too.
    aimed: ?Button = null,
    /// Retained for captions while unfocused.
    pad_at: ?i32 = null,
    /// Poll even unfocused so a held pull does not fire again on focus.
    triggers: [PADS]Triggers = @splat(.initFill(false)),
    /// Where the mouse rests on the window, when focused and over it.
    pointer: ?mathx.P = null,
    click: bool = false,
    interact: bool = false,
    scroll: i32 = 0,
    /// Touchpads and smooth wheels report fractions of a notch; they add up to whole scrolls.
    wheel: f32 = 0,

    pub fn hit(self: State, b: Button) bool {
        return self.pressed.contains(b);
    }

    pub fn held(self: State, b: Button) bool {
        return self.down.contains(b);
    }

    pub fn caption(self: State, b: Button) [:0]const u8 {
        return b.caption(self.device);
    }

    pub fn slotCaption(self: State, b: Button) [:0]const u8 {
        if (self.device.pad() or !b.isSlot()) return b.caption(self.device);
        if (b == self.modifier) return SECOND_CAPTION;
        return SLOT_CAPTIONS[numberOf(self.modifier, b).?];
    }

    /// A way held over from a screen that used it walks nobody.
    pub fn holdWalk(self: *State) void {
        self.step.hold();
        self.radial.wait = std.math.inf(f32);
        self.tree.move = null;
        self.walk = null;
    }

    fn treeWalk(self: *State, dt: f32, x: f32, y: f32) void {
        const move = self.radial.tick(dt, x, y);
        if (self.context == .tree) {
            self.tree.move = move;
            if (self.stick) self.walk = null;
        }
    }

    /// Seconds since this frame's walk step was due; 0 when none fired.
    pub fn late(self: State) f32 {
        return if (self.walk != null) self.step.late else 0;
    }

    /// The aimed slot's number key, which confirms its reticle; pads have no such repeat.
    fn againKey(self: State) ?rl.KeyboardKey {
        if (self.context != .target) return null;
        const b = self.aimed orelse return null;
        return SLOT_KEYS[numberOf(self.modifier, b) orelse return null];
    }

    fn keysFor(self: State, b: Button) []const rl.KeyboardKey {
        if (self.context != .play or !b.isSlot()) return b.keys();
        if (self.typing) return &.{};
        if (b == self.modifier) return &SECOND_KEYS;
        return SLOT_KEYS[numberOf(self.modifier, b).?..][0..1];
    }

    pub fn update(self: *State, dt: f32) void {
        const before = self.triggers;
        for (&self.triggers, 0..) |*pad, i| pad.* = pulled(@intCast(i), pad.*);
        const focused = rl.isWindowFocused();
        const was_focused = self.focused;
        self.pad_at = choosePad(self.pad_at, focused, &before, &self.triggers);
        self.focus(focused);
        if (!focused) return;
        const kind: ?Device = if (self.pad_at) |at| kindAt(at) else null;
        const live = self.pad_at;
        self.pointer = if (rl.isCursorOnScreen()) mouseAt() else null;
        self.click = self.pointer != null and rl.isMouseButtonPressed(.left);
        self.wheel += rl.getMouseWheelMove();
        self.scroll = @intFromFloat(self.wheel);
        self.wheel -= @floatFromInt(self.scroll);
        const alt_down = altDown();
        const free_keys = !self.typing and !alt_down;
        self.character_page = null;
        if (free_keys) {
            for (std.enums.values(CharacterPage)) |page| {
                if (rl.isKeyPressed(page.key())) self.character_page = page;
            }
        }
        self.interact = self.context == .play and free_keys and
            (anyHit(&INTERACT_KEYS) or
                (if (live) |at| self.padHit(at, CONFIRM.pad(), &before) else false));
        for (BUTTONS) |b| {
            var on = false;
            var hold = false;
            if (live) |at| {
                on = self.padHit(at, b.pad(), &before);
                hold = self.padHeld(at, b.pad());
            }
            if (!alt_down) {
                for (self.keysFor(b)) |k| {
                    if (self.typing and types(k)) continue;
                    on = on or rl.isKeyPressed(k);
                    hold = hold or rl.isKeyDown(k);
                }
            }
            self.pressed.setPresent(b, on);
            self.down.setPresent(b, hold);
        }
        if (free_keys) {
            if (self.againKey()) |k| {
                if (rl.isKeyPressed(k)) self.pressed.insert(CONFIRM);
            }
        }
        if (self.context != .play and self.sets and free_keys) {
            if (self.modifier) |m| {
                if (either(SECOND_KEYS)) self.down.insert(m);
            }
        }
        var keyed = false;
        while (rl.getKeyPressed() != .null) keyed = true;
        self.fullscreen = fullscreenHit();
        self.lean = (self.context == .play or self.context == .target) and ((if (live) |at| self.padHeld(at, LEAN) else false) or either(LEAN_KEYS));
        self.typed.n = 0;
        self.rub = false;
        if (self.typing) {
            self.typed.read();
            self.rub = rubbed();
        }

        self.tree = .{};
        const on_tree = self.context == .tree;
        const pan_keys = on_tree and free_keys and either(SHIFT_KEYS);
        if (on_tree and free_keys) {
            self.tree.dt = dt;
            if (live) |at| {
                const px = rl.getGamepadAxisMovement(at, .right_x);
                const py = rl.getGamepadAxisMovement(at, .right_y);
                if (std.math.hypot(px, py) >= 0.18) self.tree.pan = .{ .x = px, .y = py };
                self.tree.zoom = @as(f32, if (rl.isGamepadButtonDown(at, .left_face_up)) 1 else 0) - @as(f32, if (rl.isGamepadButtonDown(at, .left_face_down)) 1 else 0);
                self.tree.reset = self.padHit(at, .right_thumb, &before);
            }
            if (pan_keys) {
                const p = heldWalk(&WALKS, false);
                const length = @max(1, std.math.hypot(@as(f32, @floatFromInt(p.x)), @as(f32, @floatFromInt(p.y))));
                self.tree.pan = .{ .x = @as(f32, @floatFromInt(p.x)) / length, .y = @as(f32, @floatFromInt(p.y)) / length };
            }
            if (either(TreeKeys.ZOOM_IN) or rl.isKeyDown(TreeKeys.PAGE_IN)) self.tree.zoom += 1;
            if (either(TreeKeys.ZOOM_OUT) or rl.isKeyDown(TreeKeys.PAGE_OUT)) self.tree.zoom -= 1;
            self.tree.reset = self.tree.reset or rl.isKeyPressed(TreeKeys.OVERVIEW);
        }
        var x: f32 = 0;
        var y: f32 = 0;
        if (live) |at| {
            x = rl.getGamepadAxisMovement(at, .left_x);
            y = rl.getGamepadAxisMovement(at, .left_y);
        }
        var defl = mathx.deflection(x, y);
        var heading = mathx.headingOf(x, y);
        var settle: f32 = 0;
        const was_stick = self.stick;
        self.stick = stickWalks(defl, self.stick);
        if (!self.stick) {
            defl = 0;
            const digital = if (!on_tree) (if (live) |at| dpadWalk(at) else null) else null;
            if (digital orelse (if (pan_keys or alt_down) null else keyWalk(self.typing))) |p| {
                const d = if (self.lean) leanOf(mathx.stepDir(p).?).delta() else p;
                defl = 1;
                heading = mathx.headingOf(@floatFromInt(d.x), @floatFromInt(d.y));
                settle = Stepper.SETTLE;
            }
        }
        self.walk = self.step.tick(dt, defl, heading, settle);
        self.treeWalk(dt, x, y);
        if (!was_focused) self.holdWalk();
        self.typing = false;
        const pad_hit = if (live) |at| struck(at, &before, &self.triggers) else false;
        self.device = deviceOf(self.device, kind, (self.stick and !was_stick) or pad_hit or (on_tree and !pan_keys and (self.tree.pan.x != 0 or self.tree.pan.y != 0)), keyed or self.click or self.scroll != 0);
    }

    fn padHeld(self: *const State, at: i32, b: rl.GamepadButton) bool {
        if (Trigger.of(b)) |t| return self.triggers[@intCast(at)].get(t);
        return rl.isGamepadButtonDown(at, b);
    }

    fn focus(self: *State, focused: bool) void {
        if (focused) {
            self.focused = true;
            return;
        }
        const kept = self.*;
        self.* = .{
            .device = kept.device,
            .focused = false,
            .context = kept.context,
            .sets = kept.sets,
            .modifier = kept.modifier,
            .aimed = kept.aimed,
            .pad_at = kept.pad_at,
            .triggers = kept.triggers,
        };
    }

    fn padHit(self: *const State, at: i32, b: rl.GamepadButton, before: *const [PADS]Triggers) bool {
        if (Trigger.of(b)) |t| return edge(before[@intCast(at)], self.triggers[@intCast(at)], t);
        return rl.isGamepadButtonPressed(at, b);
    }
};

fn numberOf(modifier: ?Button, b: Button) ?usize {
    var n: usize = 0;
    for (SLOT_ORDER) |s| {
        if (s == modifier) continue;
        if (s == b) return n;
        n += 1;
    }
    return null;
}

fn deviceOf(was: Device, pad: ?Device, pad_hit: bool, keyed: bool) Device {
    const kind = pad orelse return .keys;
    if (pad_hit) return kind;
    if (keyed) return .keys;
    return if (was.pad()) kind else was;
}

/// The triggers are `pulled`'s: raylib's own press for them is its unlatched 55% line.
fn padPressed(at: i32) bool {
    for (std.enums.values(rl.GamepadButton)) |b| {
        if (b != .unknown and Trigger.of(b) == null and rl.isGamepadButtonPressed(at, b)) return true;
    }
    return false;
}

fn mouseAt() mathx.P {
    const m = rl.getMousePosition();
    return .{ .x = @intFromFloat(m.x), .y = @intFromFloat(m.y) };
}

/// The editor's mouse and keys: it is a desk tool, so it names them.
pub const Desk = struct {
    pub const TOOL_KEYS = [_]rl.KeyboardKey{ .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero };
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
    pub const ZOOM_OUT_KEY: rl.KeyboardKey = .minus;
    pub const ZOOM_IN_KEY: rl.KeyboardKey = .equal;
    pub const FIT_KEY: rl.KeyboardKey = .home;
    pub const HELP_KEY: rl.KeyboardKey = .f1;
    pub const OBJECTS_KEY: rl.KeyboardKey = .f3;
    pub const REROLL_KEY: rl.KeyboardKey = .e;
    pub const DELETE_KEY: rl.KeyboardKey = .delete;
    pub const COPY_KEY: rl.KeyboardKey = .c;
    pub const CUT_KEY: rl.KeyboardKey = .x;
    pub const PASTE_KEY: rl.KeyboardKey = .v;
    const NAV_KEYS = [2]rl.KeyboardKey{ .up, .down };
    const CTRL = keyGlyph(CTRL_KEYS[0]) ++ "+";
    const ALT = keyGlyph(ALT_KEYS[0]) ++ "+";
    pub const SHIFT_NAME = keyName(SHIFT_KEYS[0]);
    pub const SHIFT_CAPTION = keyGlyph(SHIFT_KEYS[0]);
    const CTRL_SHIFT = CTRL ++ SHIFT_CAPTION ++ "+";
    pub const PLAY_CAPTION = keyGlyph(PLAY_KEY);
    pub const PLAY_HERE_CAPTION = keyGlyph(PLAY_HERE_KEY);
    pub const SAVE_CAPTION = CTRL ++ keyGlyph(SAVE_KEY);
    pub const SAVE_AS_CAPTION = CTRL_SHIFT ++ keyGlyph(SAVE_KEY);
    pub const OPEN_CAPTION = CTRL ++ keyGlyph(OPEN_KEY);
    pub const NEW_CAPTION = CTRL ++ keyGlyph(NEW_KEY);
    pub const UNDO_CAPTION = CTRL ++ keyGlyph(UNDO_KEY);
    pub const REDO_CAPTION = CTRL ++ keyGlyph(REDO_KEY) ++ " / " ++ CTRL_SHIFT ++ keyGlyph(UNDO_KEY);
    pub const TOOLS_CAPTION = TOOL_CAPTIONS[0] ++ " to " ++ TOOL_CAPTIONS[TOOL_KEYS.len - 1];
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
        break :blk glyphCaption(mouseName(GRAB_BUTTON)) ++ " drag / " ++ glyphCaption(letters(&PAN_KEYS)) ++ " / " ++ glyphCaption("arrows");
    };
    pub const WHEEL_CAPTION = glyphCaption("wheel");
    pub const GRAPH_CAPTION = keyGlyph(GRAPH_KEY);
    pub const GO_CAPTION = keyGlyph(GO_KEY);
    pub const RENAME_CAPTION = keyGlyph(RENAME_KEY);
    pub const BACK_CAPTION = keyGlyph(BACK_KEY);
    pub const ENTER_CAPTION = keyGlyph(ENTER_KEYS[0]);
    pub const FULLSCREEN_CAPTION = ALT ++ ENTER_CAPTION;

    const BARE = [_][]const u8{ "play", "play_here", "graph", "go", "rename", "back", "smaller", "bigger", "zoom_in", "zoom_out", "fit", "help", "objects", "reroll", "delete" };
    const WITH_CTRL = [_][]const u8{ "open", "new", "copy", "cut", "paste" };
    const SHIFTED = [_][]const u8{ "save", "undo", "redo" };

    fn keyOf(comptime field: []const u8) rl.KeyboardKey {
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
    alt: bool = false,
    zoom_in: bool = false,
    zoom_out: bool = false,
    fit: bool = false,
    help: bool = false,
    objects: bool = false,
    reroll: bool = false,
    delete: bool = false,
    copy: bool = false,
    cut: bool = false,
    paste: bool = false,
    /// Up -1 or down 1, as pressed or repeated.
    nav: i32 = 0,
    tool: ?usize = null,
    shape: ?usize = null,
    typed: Typed = .{},

    pub fn text(self: *const Desk) []const u8 {
        return self.typed.text();
    }

    pub fn clicked(self: *const Desk) bool {
        return self.paint_hit or self.erase_hit;
    }

    pub fn update(self: *Desk) void {
        const d = rl.getMouseDelta();
        self.mouse = mouseAt();
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
        inline for (BARE) |f| @field(self, f) = bare and hit(comptime keyOf(f));
        inline for (WITH_CTRL) |f| @field(self, f) = ctrl and hit(comptime keyOf(f));
        self.save = ctrl and !self.shift and hit(SAVE_KEY);
        self.save_as = ctrl and self.shift and hit(SAVE_KEY);
        self.undo = ctrl and !self.shift and hit(UNDO_KEY);
        self.redo = ctrl and (hit(REDO_KEY) or (self.shift and hit(UNDO_KEY)));
        self.fullscreen = fullscreenHit();
        self.enter = !altDown() and anyHit(&ENTER_KEYS);
        self.rub = rubbed();
        self.alt = altDown();
        self.nav = 0;
        for (NAV_KEYS, [2]i32{ -1, 1 }) |k, by| {
            if (repeated(k)) self.nav = by;
        }
        self.tool = null;
        self.shape = null;
        if (bare) {
            for (TOOL_KEYS, 0..) |k, i| {
                if (hit(k)) self.tool = i;
            }
            for (SHAPE_KEYS, 0..) |k, i| {
                if (hit(k)) self.shape = i;
            }
        }
        self.typed.read();
    }
};

fn either(pair: [2]rl.KeyboardKey) bool {
    return rl.isKeyDown(pair[0]) or rl.isKeyDown(pair[1]);
}

fn altDown() bool {
    return either(ALT_KEYS);
}

fn fullscreenHit() bool {
    return altDown() and anyHit(&ENTER_KEYS);
}

const RUB_KEY: rl.KeyboardKey = .backspace;
pub const RUB_CAPTION = keyGlyph(RUB_KEY);

fn rubbed() bool {
    return repeated(RUB_KEY);
}

fn repeated(k: rl.KeyboardKey) bool {
    return rl.isKeyPressed(k) or rl.isKeyPressedRepeat(k);
}

fn keyName(comptime k: rl.KeyboardKey) [:0]const u8 {
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

fn anyHit(keys: []const rl.KeyboardKey) bool {
    for (keys) |k| {
        if (rl.isKeyPressed(k)) return true;
    }
    return false;
}

fn stepOf(p: mathx.P) ?mathx.P {
    return if (p.x == 0 and p.y == 0) null else p.sign();
}

fn dpadWalk(at: i32) ?mathx.P {
    var p = mathx.P{ .x = 0, .y = 0 };
    for (WALKS) |w| {
        const b = w.pad orelse continue;
        if (rl.isGamepadButtonDown(at, b)) p = p.add(w.d.delta());
    }
    return stepOf(p);
}

fn keyWalk(typing: bool) ?mathx.P {
    return stepOf(heldWalk(&WALKS, typing));
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

test "tree stick follows the bearing with hysteresis, turn edges and repeat" {
    var radial = RadialStepper{};
    try std.testing.expect(radial.tick(0.01, 0.1, 0.1) == null);
    const first = radial.tick(0.01, 0.6, 0.8).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), first.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), first.y, 0.001);
    try std.testing.expect(radial.tick(0.01, 0.62, 0.78) == null);
    try std.testing.expect(radial.tick(Stepper.DAS, 0.62, 0.78) != null);
    try std.testing.expect(radial.tick(0.01, -0.6, 0.8) != null);
    try std.testing.expect(radial.tick(0.01, 0, 0) == null);
    try std.testing.expect(radial.tick(0.01, -0.6, 0.8) != null);
    var state = State{ .context = .tree, .radial = radial, .tree = .{ .move = first, .pan = first, .zoom = 1 } };
    state.holdWalk();
    try std.testing.expect(state.tree.move == null);
    try std.testing.expect(state.radial.tick(1, -0.6, 0.8) == null);
    state.focus(false);
    try std.testing.expect(state.tree.move == null and state.tree.zoom == 0 and state.tree.pan.x == 0);
    std.debug.print("tree input: raw bearing, deadzone, repeat, turning, release, held navigation and focus loss checked\n", .{});
}

test "a stick resting off centre leaves the d-pad and keys to walk, and a pushed one holds its walk down to rearming" {
    const resting = (Stepper.REARM + Stepper.FIRE) / 2;
    try std.testing.expect(!stickWalks(resting, false));
    try std.testing.expect(stickWalks(Stepper.FIRE, false));
    try std.testing.expect(stickWalks(resting, true));
    try std.testing.expect(!stickWalks(Stepper.REARM / 2, true));
}

test "a held stick cannot move the tree when opening it from another screen" {
    for ([_]State.Context{ .play, .menu, .target }) |context| {
        var state = State{ .context = context, .stick = true };
        state.treeWalk(0.01, 0.6, 0.8);
        state.holdWalk();
        state.context = .tree;
        state.treeWalk(1, 0.6, 0.8);
        try std.testing.expect(state.tree.move == null);
        state.treeWalk(0.01, -0.6, 0.8);
        try std.testing.expect(state.tree.move != null);
        state.holdWalk();
        state.treeWalk(0.01, 0, 0);
        state.treeWalk(0.01, -0.6, 0.8);
        try std.testing.expect(state.tree.move != null);
    }
    std.debug.print("3 tree entry contexts suppress held movement and rearm on turn or release\n", .{});
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

test "losing focus cancels unsettled movement and held actions without forgetting the controller" {
    var st = State{ .device = .ps5, .pad_at = 1, .context = .play };
    st.character_page = .skills;
    st.triggers[1].set(.left, true);
    st.pressed.insert(.a);
    st.down.insert(.a);
    st.walk = st.step.tick(mathx.FRAME_DT, 1, mathx.Dir.n.heading(), Stepper.SETTLE);
    try std.testing.expect(st.step.owed != null);
    st.focus(false);
    try std.testing.expect(!st.focused and st.walk == null);
    try std.testing.expect(st.character_page == null);
    try std.testing.expect(!st.hit(.a) and !st.held(.a));
    try std.testing.expectEqual(@as(?mathx.Dir, null), st.step.tick(mathx.FRAME_DT, 0, 0, Stepper.SETTLE));
    try std.testing.expectEqual(Device.ps5, st.device);
    try std.testing.expectEqual(@as(?i32, 1), st.pad_at);
    try std.testing.expect(st.triggers[1].get(.left));
    st.focus(true);
    try std.testing.expect(st.focused and st.walk == null);
    std.debug.print("focus loss: pending tap and held action cancelled; controller and trigger latch retained\n", .{});
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

test "a held diagonal let go one key at a time steps nowhere, and a new way walks" {
    var s = Stepper{};
    const dt = mathx.FRAME_DT;
    const settle = Stepper.SETTLE;
    for (0..30) |_| _ = s.tick(dt, 1, mathx.Dir.ne.heading(), settle);
    s.hold();
    var steps: usize = 0;
    for ([_]mathx.Dir{ .ne, .e }) |d| {
        for (0..30) |_| {
            if (s.tick(dt, 1, d.heading(), settle) != null) steps += 1;
        }
    }
    if (s.tick(dt, 0, 0, settle) != null) steps += 1;
    try std.testing.expectEqual(@as(usize, 0), steps);
    for (0..30) |_| {
        if (s.tick(dt, 1, mathx.Dir.s.heading(), settle) != null) steps += 1;
    }
    try std.testing.expect(steps > 0);
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

test "walk keys held together sum to one step a lean can turn" {
    for ([_]mathx.P{ .{ .x = 1, .y = -2 }, .{ .x = 2, .y = -1 }, .{ .x = 0, .y = -2 }, .{ .x = 2, .y = 0 } }) |held| {
        const p = stepOf(held).?;
        try std.testing.expect(mathx.stepDir(p) != null);
    }
    try std.testing.expectEqual(@as(?mathx.P, null), stepOf(.{ .x = 0, .y = 0 }));
}

test "the last device pressed is the one named, and the keyboard when no pad is plugged in" {
    try std.testing.expectEqual(Device.keys, deviceOf(.xbox, .xbox, false, true));
    try std.testing.expectEqual(Device.xbox, deviceOf(.keys, .xbox, true, true));
    try std.testing.expectEqual(Device.keys, deviceOf(.keys, .xbox, false, false));
    try std.testing.expectEqual(Device.xbox, deviceOf(.xbox, .xbox, false, false));
    try std.testing.expectEqual(Device.keys, deviceOf(.xbox, null, false, false));
    try std.testing.expectEqual(Device.ps5, deviceOf(.xbox, .ps5, false, false));
    try std.testing.expectEqual(Device.keys, deviceOf(.keys, .ps5, false, false));
}

test "a Sony pad is told by its GUID, a DualSense from the rest" {
    try std.testing.expectEqual(Device.ps5, padOf("030000004c050000e60c000000000000"));
    try std.testing.expectEqual(Device.ps5, padOf("030000004c050000f20d000000000000"));
    try std.testing.expectEqual(Device.ps4, padOf("030000004c050000cc09000000000000"));
    try std.testing.expectEqual(Device.xbox, padOf("78696e707574010000000000000000000"));
    try std.testing.expectEqual(Device.xbox, padOf("030000005e0400008e02000000000000"));
    try std.testing.expectEqual(Device.xbox, padOf(""));
    for (PS5_PRODUCTS) |p| try std.testing.expect(std.mem.indexOf(u8, MAPPINGS, "\n03000000" ++ SONY ++ "0000" ++ p ++ "000000000000,") != null);
}

test "a trigger presses past most of its travel and lets go under less, so a resting finger does not chatter" {
    var presses: usize = 0;
    var was = false;
    for ([_]f32{ 0, 0.53, 0.57, 0.54, 0.56, 0.5, 0.7, 0.45, 0.65, 0.42, 0.3, 0.5 }) |travel| {
        const now = latch(travel, was);
        if (now and !was) presses += 1;
        was = now;
    }
    std.debug.print("a trigger hovering at raylib's 55% then pulled once, wavering, and let go: {d} press\n", .{presses});
    try std.testing.expectEqual(@as(usize, 1), presses);
    try std.testing.expect(!latch(0.5, false));
    const off = Triggers.initFill(false);
    var rt = off;
    rt.set(.right, true);
    try std.testing.expect(rose(off, rt) and !rose(rt, rt) and !rose(rt, off));
    try std.testing.expectEqual(@as(?Trigger, .right), Trigger.of(Button.rt.pad()));
    try std.testing.expectEqual(@as(?Trigger, .left), Trigger.of(LEAN));
    try std.testing.expectEqual(@as(?Trigger, null), Trigger.of(Button.lb.pad()));
}

test "every pad button has a name on each maker's pad, a PlayStation's by its own" {
    try std.testing.expectEqualStrings("Cross", Button.a.caption(.ps5));
    try std.testing.expectEqualStrings("Circle", Button.b.caption(.ps4));
    try std.testing.expectEqualStrings("Square", Button.x.caption(.ps5));
    try std.testing.expectEqualStrings("Triangle", Button.y.caption(.ps5));
    try std.testing.expectEqualStrings("L1", Button.lb.caption(.ps5));
    try std.testing.expectEqualStrings("R2", Button.rt.caption(.ps4));
    try std.testing.expectEqualStrings("Options", Button.character.caption(.ps5));
    try std.testing.expectEqualStrings("Options", Button.character.caption(.ps4));
    try std.testing.expectEqualStrings("Create", Button.pause.caption(.ps5));
    try std.testing.expectEqualStrings("Menu", Button.character.caption(.xbox));
    for (std.enums.values(Device)) |d| {
        if (!d.pad()) continue;
        for (BUTTONS) |b| try std.testing.expect(b.caption(d).len > 0);
    }
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
    try std.testing.expectEqualStrings("Tab", s.slotCaption(.character));
    s.device = .xbox;
    try std.testing.expectEqualStrings("RT", s.slotCaption(.rt));
}

test "on the keyboard Enter, Space and Z confirm in menus, and X and Esc back out" {
    try std.testing.expectEqualSlices(rl.KeyboardKey, &.{ .enter, .kp_enter, .space, .z }, Button.a.keys());
    try std.testing.expectEqualSlices(rl.KeyboardKey, &.{ .escape, .x }, Button.b.keys());
    try std.testing.expectEqualSlices(rl.KeyboardKey, &.{.escape}, Button.pause.keys());
    for (BUTTONS) |b| {
        for (BUTTONS) |o| {
            if (b == o or (b == .b and o == .pause) or (b == .pause and o == .b)) continue;
            for (b.keys()) |k| try std.testing.expect(std.mem.indexOfScalar(rl.KeyboardKey, o.keys(), k) == null);
        }
    }
}

test "targeting uses confirm and back keys instead of numbered skills for every modifier binding" {
    for (SLOT_ORDER) |modifier| {
        var s = State{ .context = .target, .modifier = modifier };
        try std.testing.expectEqualSlices(rl.KeyboardKey, &.{ .enter, .kp_enter, .space, .z }, s.keysFor(.a));
        try std.testing.expectEqualSlices(rl.KeyboardKey, &.{ .escape, .x }, s.keysFor(.b));
        try std.testing.expectEqualSlices(rl.KeyboardKey, &.{.escape}, s.keysFor(.pause));
        for (BUTTONS) |b| {
            for (s.keysFor(b)) |k| try std.testing.expect(std.mem.indexOfScalar(rl.KeyboardKey, &SLOT_KEYS, k) == null);
        }
        try std.testing.expectEqual(@as(?rl.KeyboardKey, null), s.againKey());
        for (SLOT_ORDER) |b| {
            if (b == modifier) continue;
            s.aimed = b;
            try std.testing.expectEqual(@as(?rl.KeyboardKey, SLOT_KEYS[numberOf(modifier, b).?]), s.againKey());
        }
        s.context = .play;
        try std.testing.expectEqual(@as(?rl.KeyboardKey, null), s.againKey());
        s.aimed = null;
        try std.testing.expectEqualSlices(rl.KeyboardKey, &SECOND_KEYS, s.keysFor(modifier));
        for (SLOT_ORDER) |b| {
            if (b == modifier) continue;
            try std.testing.expectEqualSlices(rl.KeyboardKey, SLOT_KEYS[numberOf(modifier, b).?..][0..1], s.keysFor(b));
        }
        s.typing = true;
        for (SLOT_ORDER) |b| try std.testing.expectEqual(@as(usize, 0), s.keysFor(b).len);
    }
    std.debug.print("{d} modifier bindings: targeting confirms/backs out with menu keys or the aimed slot's own number, play uses numbered slots, typing fires none\n", .{SLOT_ORDER.len});
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
