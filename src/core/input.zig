const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");
const repeat = @import("input_repeat.zig");
const names = @import("input_names.zig");
const bindings = @import("input_bindings.zig");

pub const Stepper = repeat.Stepper;
const RadialStepper = repeat.RadialStepper;
const stickWalks = repeat.stickWalks;

const ENTER_KEYS = bindings.ENTER_KEYS;
const INTERACT_KEYS = bindings.INTERACT_KEYS;
const LEAN = bindings.LEAN;
const SHIFT_KEYS = bindings.SHIFT_KEYS;
const CTRL_KEYS = bindings.CTRL_KEYS;
const ALT_KEYS = bindings.ALT_KEYS;
const LEAN_KEYS = bindings.LEAN_KEYS;
const ZOOM_IN_KEYS = bindings.ZOOM_IN_KEYS;
const ZOOM_OUT_KEYS = bindings.ZOOM_OUT_KEYS;
const OVERVIEW_KEY = bindings.OVERVIEW_KEY;

pub const Device = names.Device;

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

const Walk = bindings.Walk;
const WALKS = bindings.WALKS;
pub const DPAD = bindings.DPAD;
pub const leanOf = bindings.leanOf;
pub const Button = bindings.Button;
pub const CONFIRM = bindings.CONFIRM;
pub const SLOT_ORDER = bindings.SLOT_ORDER;
const SLOT_KEYS = bindings.SLOT_KEYS;
const SLOT_CAPTIONS = bindings.SLOT_CAPTIONS;

pub const GLYPH_OPEN = names.GLYPH_OPEN;
pub const GLYPH_CLOSE = names.GLYPH_CLOSE;
pub const WHEEL = names.WHEEL;
pub const ARROWS = names.ARROWS;
pub const ARROW_KEYS = names.ARROW_KEYS;
const keyGlyph = names.keyGlyph;

const SECOND_KEYS = bindings.SECOND_KEYS;
pub const SECOND_CAPTION = bindings.SECOND_CAPTION;
const BUTTONS = bindings.BUTTONS;

/// raylib closes the window on Esc unless its exit key is cleared. Needs the window open.
pub fn claimKeys() void {
    rl.setExitKey(.null);
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

    fn drop(self: *Typed) void {
        self.n = 0;
        while (rl.getCharPressed() != 0) {}
    }
};

const TYPING_RANGES = [_][2]rl.KeyboardKey{ .{ .a, .z }, .{ .zero, .nine }, .{ .kp_0, .kp_9 } };
const TYPING_SINGLES = [_]rl.KeyboardKey{ .space, .period, .apostrophe, .minus };
const TYPING_KEYS = blk: {
    var out: []const rl.KeyboardKey = &TYPING_SINGLES;
    for (TYPING_RANGES) |r| {
        const lo: usize = @intCast(@intFromEnum(r[0]));
        const hi: usize = @intCast(@intFromEnum(r[1]));
        for (lo..hi + 1) |c| out = out ++ &[_]rl.KeyboardKey{@enumFromInt(c)};
    }
    break :blk out[0..out.len].*;
};
const TYPING_SET = blk: {
    var top: usize = 0;
    for (TYPING_KEYS) |k| top = @max(top, @as(usize, @intCast(@intFromEnum(k))));
    var set = std.StaticBitSet(top + 1).initEmpty();
    for (TYPING_KEYS) |k| set.set(@intCast(@intFromEnum(k)));
    break :blk set;
};

fn types(k: rl.KeyboardKey) bool {
    const c = @intFromEnum(k);
    return c >= 0 and c < TYPING_SET.capacity() and TYPING_SET.isSet(@intCast(c));
}

fn typingHeld() bool {
    for (TYPING_KEYS) |k| {
        if (rl.isKeyDown(k)) return true;
    }
    return false;
}

pub const TreeInput = struct {
    move: ?rl.Vector2 = null,
    pan: rl.Vector2 = .{ .x = 0, .y = 0 },
    zoom: f32 = 0,
    reset: bool = false,
    dt: f32 = 0,
};

pub const CharacterPage = bindings.CharacterPage;
pub const TreeKeys = bindings.TreeKeys;

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
    /// Last frame's walk went to the tree's pan or zoom instead.
    muted: bool = false,
    /// The walk is held because a tree pan ended under it, not carried in, so pan and zoom stay live.
    pan_hold: bool = false,
    /// Set before each `update`, which clears it: typing keys then type, and press no button.
    typing: bool = false,
    was_typing: bool = false,
    /// A typing key held into the field types nothing until every typing key is let go.
    held_into_typing: bool = false,
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
    left_released: bool = false,
    right_click: bool = false,
    middle_click: bool = false,
    dragging: bool = false,
    mouse_delta: mathx.P = .{ .x = 0, .y = 0 },
    mouse_moved: bool = false,
    interact: bool = false,
    scroll: i32 = 0,
    /// Touchpads and smooth wheels report fractions of a notch; they add up to whole scrolls.
    wheel: f32 = 0,

    pub fn hit(self: State, b: Button) bool {
        return self.pressed.contains(b);
    }

    pub fn pointing(self: State) bool {
        return self.pointer != null and (self.mouse_moved or self.click);
    }

    fn mouseUsed(self: State, wheel: f32) bool {
        return self.mouse_moved or self.click or self.right_click or self.middle_click or wheel != 0;
    }

    fn movePointer(self: *State, pointer: ?mathx.P, was_focused: bool) void {
        const previous = self.pointer;
        self.pointer = pointer;
        self.mouse_delta = if (pointer != null and previous != null and was_focused) pointer.?.sub(previous.?) else .{ .x = 0, .y = 0 };
        self.mouse_moved = was_focused and pointer != null and (previous == null or self.mouse_delta.x != 0 or self.mouse_delta.y != 0);
    }

    pub fn clicked(self: State, box: rl.Rectangle) bool {
        const p = self.pointer orelse return false;
        return self.click and rl.checkCollisionPointRec(.{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) }, box);
    }

    pub fn scrolled(self: State, at: usize, n: usize) usize {
        return if (self.scroll != 0) mathx.nudge(at, -self.scroll, n) else at;
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
        self.pan_hold = false;
        self.radial.wait = Stepper.HELD;
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

    /// This frame's walk comes from a held way, repeating or turning, not a new press.
    pub fn repeating(self: State) bool {
        return self.walk != null and !self.step.fresh;
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

    /// Outside play the modifier's menu keys still press it, but only Ctrl holds its set.
    fn holdsByKeys(self: State, b: Button) bool {
        return self.context == .play or b != self.modifier;
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
        const wheel = self.readPointer(was_focused);
        const alt_down = altDown();
        const free_keys = !self.typing and !alt_down;
        self.readButtons(alt_down, &before);
        var keyed = false;
        while (rl.getKeyPressed() != .null) keyed = true;
        self.fullscreen = fullscreenHit();
        self.lean = (self.context == .play or self.context == .target) and ((if (live) |at| self.padHeld(at, LEAN) else false) or either(LEAN_KEYS));
        self.readText();
        const pan_keys = self.readTree(dt, free_keys, &before);
        const stick_activated = self.readMovement(dt, alt_down, pan_keys);
        if (!was_focused) self.holdWalk();
        self.typing = false;
        const pad_hit = if (live) |at| struck(at, &before, &self.triggers) else false;
        self.device = deviceOf(self.device, kind, stick_activated or pad_hit or (self.context == .tree and !pan_keys and (self.tree.pan.x != 0 or self.tree.pan.y != 0)), keyed or self.mouseUsed(wheel));
    }

    fn readPointer(self: *State, was_focused: bool) f32 {
        self.movePointer(if (rl.isCursorOnScreen()) mouseAt() else null, was_focused);
        self.click = was_focused and self.pointer != null and rl.isMouseButtonPressed(.left);
        self.left_released = was_focused and self.pointer != null and rl.isMouseButtonReleased(.left);
        self.right_click = was_focused and self.pointer != null and rl.isMouseButtonPressed(.right);
        self.middle_click = was_focused and self.pointer != null and rl.isMouseButtonPressed(.middle);
        self.dragging = was_focused and self.pointer != null and rl.isMouseButtonDown(.middle);
        const wheel = if (self.pointer != null and was_focused) rl.getMouseWheelMove() else 0;
        self.wheel += wheel;
        self.scroll = @intFromFloat(self.wheel);
        self.wheel -= @floatFromInt(self.scroll);
        return wheel;
    }

    fn readButtons(self: *State, alt_down: bool, before: *const [PADS]Triggers) void {
        const live = self.pad_at;
        const free_keys = !self.typing and !alt_down;
        self.character_page = null;
        if (free_keys) {
            for (std.enums.values(CharacterPage)) |page| {
                if (rl.isKeyPressed(page.key())) self.character_page = page;
            }
        }
        self.interact = self.context == .play and free_keys and
            (anyHit(&INTERACT_KEYS) or
                (if (live) |at| self.padHit(at, CONFIRM.pad(), before) else false));
        for (BUTTONS) |b| {
            var on = false;
            var hold = false;
            if (live) |at| {
                on = self.padHit(at, b.pad(), before);
                hold = self.padHeld(at, b.pad());
            }
            if (!alt_down) {
                for (self.keysFor(b)) |k| {
                    if (self.typing and types(k)) continue;
                    on = on or rl.isKeyPressed(k);
                    if (self.holdsByKeys(b)) hold = hold or rl.isKeyDown(k);
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
    }

    fn readText(self: *State) void {
        self.typed.n = 0;
        self.rub = false;
        if (self.typing) {
            if (!self.was_typing or self.held_into_typing) self.held_into_typing = typingHeld();
            if (self.held_into_typing) self.typed.drop() else self.typed.read();
            self.rub = rubbed();
        }
        self.was_typing = self.typing;
    }

    fn readTree(self: *State, dt: f32, free_keys: bool, before: *const [PADS]Triggers) bool {
        const live = self.pad_at;
        self.tree = .{};
        const on_tree = self.context == .tree;
        const pan_keys = on_tree and free_keys and either(TreeKeys.PAN_KEYS);
        if (on_tree and free_keys) {
            self.tree.dt = dt;
            const carried = self.step.carried() and !self.pan_hold;
            if (live) |at| {
                const px = rl.getGamepadAxisMovement(at, .right_x);
                const py = rl.getGamepadAxisMovement(at, .right_y);
                if (mathx.deflection(px, py) >= TreeKeys.PAN_DEADZONE) self.tree.pan = .{ .x = px, .y = py };
                if (!carried) self.tree.zoom = @as(f32, if (self.padHeld(at, TreeKeys.PAD_ZOOM_IN)) 1 else 0) - @as(f32, if (self.padHeld(at, TreeKeys.PAD_ZOOM_OUT)) 1 else 0);
                self.tree.reset = self.padHit(at, TreeKeys.PAD_OVERVIEW.pad(), before);
            }
            if (pan_keys and !carried) {
                const p = heldWalk(&WALKS, false);
                const length = @max(1, mathx.len(@floatFromInt(p.x), @floatFromInt(p.y)));
                self.tree.pan = .{ .x = @as(f32, @floatFromInt(p.x)) / length, .y = @as(f32, @floatFromInt(p.y)) / length };
            }
            if (either(ZOOM_IN_KEYS) or rl.isKeyDown(TreeKeys.PAGE_IN)) self.tree.zoom += 1;
            if (either(ZOOM_OUT_KEYS) or rl.isKeyDown(TreeKeys.PAGE_OUT)) self.tree.zoom -= 1;
            self.tree.reset = self.tree.reset or rl.isKeyPressed(OVERVIEW_KEY);
        }
        return pan_keys;
    }

    fn readMovement(self: *State, dt: f32, alt_down: bool, pan_keys: bool) bool {
        const live = self.pad_at;
        const on_tree = self.context == .tree;
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
        var muted = false;
        if (!self.stick) {
            defl = 0;
            const source = walkSource(on_tree, pan_keys, if (live) |at| dpadWalk(at) else null, if (alt_down) null else keyWalk(self.typing));
            muted = source.muted;
            if (source.p) |p| {
                const d = if (self.lean) leanOf(mathx.stepDir(p).?).delta() else p;
                defl = 1;
                heading = mathx.headingOf(@floatFromInt(d.x), @floatFromInt(d.y));
                settle = Stepper.SETTLE;
            }
        }
        if ((self.stick and !was_stick) or walkPressed(live, self.typing, alt_down)) {
            self.step.pressed();
            self.step.press = true;
        }
        self.stepWalk(dt, defl, heading, settle, muted);
        self.treeWalk(dt, x, y);
        return self.stick and !was_stick;
    }

    fn stepWalk(self: *State, dt: f32, defl: f32, heading: f32, settle: f32, muted: bool) void {
        if (self.muted and !muted and self.step.latched != null) {
            self.step.hold();
            self.pan_hold = true;
        }
        self.muted = muted;
        self.walk = self.step.tick(dt, defl, heading, settle);
        if (!self.step.carried()) self.pan_hold = false;
        if (muted) self.walk = null;
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

/// The editor's mouse and keys, captioned with keyboard and mouse glyphs.
pub const Desk = struct {
    pub const TOOL_KEYS = bindings.Desk.TOOL_KEYS;
    pub const TOOL_CAPTIONS = bindings.Desk.TOOL_CAPTIONS;
    pub const SHAPE_KEYS_BY = bindings.Desk.SHAPE_KEYS_BY;
    pub const SHAPE_KEYS = bindings.Desk.SHAPE_KEYS;
    pub const SHAPE_CAPTIONS = bindings.Desk.SHAPE_CAPTIONS;
    const PAN_KEYS = bindings.Desk.PAN_KEYS;
    const PAINT_BUTTON = bindings.Desk.PAINT_BUTTON;
    const ERASE_BUTTON = bindings.Desk.ERASE_BUTTON;
    const GRAB_BUTTON = bindings.Desk.GRAB_BUTTON;
    const NAV_KEYS = bindings.Desk.NAV_KEYS;
    pub const SHIFT_CAPTION = bindings.Desk.SHIFT_CAPTION;
    pub const PLAY_CAPTION = bindings.Desk.PLAY_CAPTION;
    pub const PLAY_HERE_CAPTION = bindings.Desk.PLAY_HERE_CAPTION;
    pub const SAVE_CAPTION = bindings.Desk.SAVE_CAPTION;
    pub const SAVE_AS_CAPTION = bindings.Desk.SAVE_AS_CAPTION;
    pub const OPEN_CAPTION = bindings.Desk.OPEN_CAPTION;
    pub const NEW_CAPTION = bindings.Desk.NEW_CAPTION;
    pub const UNDO_CAPTION = bindings.Desk.UNDO_CAPTION;
    pub const REDO_CAPTION = bindings.Desk.REDO_CAPTION;
    pub const TOOLS_CAPTION = bindings.Desk.TOOLS_CAPTION;
    pub const PAINT_CAPTION = bindings.Desk.PAINT_CAPTION;
    pub const ERASE_CAPTION = bindings.Desk.ERASE_CAPTION;
    pub const RECT_CAPTION = bindings.Desk.RECT_CAPTION;
    pub const BRUSH_CAPTION = bindings.Desk.BRUSH_CAPTION;
    pub const SHAPES_CAPTION = bindings.Desk.SHAPES_CAPTION;
    pub const PICK_CAPTION = bindings.Desk.PICK_CAPTION;
    pub const ZOOM_CAPTION = bindings.Desk.ZOOM_CAPTION;
    pub const FIT_CAPTION = bindings.Desk.FIT_CAPTION;
    pub const HELP_CAPTION = bindings.Desk.HELP_CAPTION;
    pub const OBJECTS_CAPTION = bindings.Desk.OBJECTS_CAPTION;
    pub const REROLL_CAPTION = bindings.Desk.REROLL_CAPTION;
    pub const DELETE_CAPTION = bindings.Desk.DELETE_CAPTION;
    pub const COPY_CAPTION = bindings.Desk.COPY_CAPTION;
    pub const CUT_CAPTION = bindings.Desk.CUT_CAPTION;
    pub const PASTE_CAPTION = bindings.Desk.PASTE_CAPTION;
    pub const NAV_CAPTION = bindings.Desk.NAV_CAPTION;
    pub const PAN_CAPTION = bindings.Desk.PAN_CAPTION;
    pub const WHEEL_CAPTION = bindings.Desk.WHEEL_CAPTION;
    pub const GRAPH_CAPTION = bindings.Desk.GRAPH_CAPTION;
    pub const GO_CAPTION = bindings.Desk.GO_CAPTION;
    pub const RENAME_CAPTION = bindings.Desk.RENAME_CAPTION;
    pub const BACK_CAPTION = bindings.Desk.BACK_CAPTION;
    pub const ENTER_CAPTION = bindings.Desk.ENTER_CAPTION;
    pub const FULLSCREEN_CAPTION = bindings.Desk.FULLSCREEN_CAPTION;
    const BARE = bindings.Desk.BARE;
    const WITH_CTRL = bindings.Desk.WITH_CTRL;
    const SHIFTED = bindings.Desk.SHIFTED;
    const SHIFT_TWINS = bindings.Desk.SHIFT_TWINS;
    const keyOf = bindings.Desk.keyOf;

    comptime {
        @setEvalBranchQuota(20_000);
        for (@typeInfo(bindings.Desk).@"struct".decls) |b| {
            if (!std.mem.endsWith(u8, b.name, "_CAPTION")) continue;
            for (@typeInfo(Desk).@"struct".decls) |d| {
                if (std.mem.eql(u8, d.name, b.name)) break;
            } else @compileError(b.name ++ " is not on input.Desk, so the editor's help never checks it");
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
    text_left: bool = false,
    text_right: bool = false,
    text_home: bool = false,
    text_end: bool = false,
    text_delete: bool = false,
    text_all: bool = false,
    paste_text: ?[:0]const u8 = null,
    tool: ?usize = null,
    shape: ?usize = null,
    typed: Typed = .{},

    pub fn text(self: *const Desk) []const u8 {
        return self.typed.text();
    }

    pub fn clicked(self: *const Desk) bool {
        return self.paint_hit or self.erase_hit;
    }

    /// One step down a list for the wheel turned toward the user, one up for away, 0 when it is still.
    pub fn notch(self: *const Desk) i32 {
        return if (self.wheel > 0) -1 else if (self.wheel < 0) 1 else 0;
    }

    /// Only the caret, selection, list and copy keys: what reading text that cannot change may still use.
    pub fn navigationOnly(self: *const Desk) Desk {
        return .{ .text_all = self.text_all, .text_left = self.text_left, .text_right = self.text_right, .text_home = self.text_home, .text_end = self.text_end, .shift = self.shift, .nav = self.nav, .copy = self.copy };
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
        inline for (SHIFT_TWINS) |t| @field(self, t[1]) = false;
        inline for (SHIFTED) |f| @field(self, f) = ctrl and hit(comptime keyOf(f));
        inline for (SHIFT_TWINS) |t| {
            if (self.shift and @field(self, t[0])) {
                @field(self, t[0]) = false;
                @field(self, t[1]) = true;
            }
        }
        self.fullscreen = fullscreenHit();
        self.enter = !altDown() and anyHit(&ENTER_KEYS);
        self.rub = rubbed();
        self.alt = altDown();
        self.text_left = repeated(.left);
        self.text_right = repeated(.right);
        self.text_home = hit(.home);
        self.text_end = hit(.end);
        self.text_delete = repeated(.delete);
        self.text_all = ctrl and hit(.a);
        self.paste_text = if (self.paste) rl.getClipboardText() else null;
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

pub fn copyText(text: [:0]const u8) void {
    rl.setClipboardText(text);
}

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

pub const upper = names.upper;

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

/// On the tree the d-pad zooms and Shift pans; they still latch the stepper so leaving the tree does not walk.
fn walkSource(on_tree: bool, pan_keys: bool, pad: ?mathx.P, keys: ?mathx.P) struct { p: ?mathx.P, muted: bool } {
    if (!on_tree) return .{ .p = pad orelse keys, .muted = false };
    if (!pan_keys) if (keys) |k| return .{ .p = k, .muted = false };
    return .{ .p = pad orelse keys, .muted = true };
}

fn keyWalk(typing: bool) ?mathx.P {
    return stepOf(heldWalk(&WALKS, typing));
}

fn walkPressed(pad: ?i32, typing: bool, alt_down: bool) bool {
    for (WALKS) |w| {
        if (pad) |at| if (w.pad) |b| if (rl.isGamepadButtonPressed(at, b)) return true;
        if (alt_down) continue;
        for (w.keys) |k| {
            if (!(typing and types(k)) and rl.isKeyPressed(k)) return true;
        }
    }
    return false;
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

pub const mouseName = names.mouseName;

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

test "mouse motion buttons and fractional wheel select keyboard hints without a stationary pointer taking over" {
    const samples = [_]State{
        .{ .mouse_moved = true },
        .{ .click = true },
        .{ .right_click = true },
        .{ .middle_click = true },
    };
    for (samples) |sample| {
        try std.testing.expectEqual(Device.keys, deviceOf(.ps5, .ps5, false, sample.mouseUsed(0)));
    }
    var st = State{ .pointer = .{ .x = 100, .y = 100 } };
    try std.testing.expectEqual(Device.xbox, deviceOf(.xbox, .xbox, false, st.mouseUsed(0)));
    try std.testing.expectEqual(Device.keys, deviceOf(.xbox, .xbox, false, st.mouseUsed(0.1)));
    try std.testing.expectEqual(Device.ps5, deviceOf(.keys, .ps5, true, false));
    st.movePointer(null, true);
    st.movePointer(.{ .x = 100, .y = 100 }, true);
    try std.testing.expect(st.mouse_moved);
    st.movePointer(st.pointer, true);
    try std.testing.expect(!st.mouse_moved);
    st.movePointer(null, false);
    st.movePointer(.{ .x = 120, .y = 100 }, false);
    try std.testing.expect(!st.mouse_moved);
    st.click = true;
    st.right_click = true;
    st.middle_click = true;
    st.dragging = true;
    st.mouse_moved = true;
    st.focus(false);
    try std.testing.expect(!st.mouseUsed(0) and !st.dragging and st.pointer == null);
    std.debug.print("mouse devices: motion, three buttons, fractional wheel, cursor entry, stationary cursor, controller return and focus loss\n", .{});
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

test "a d-pad zoom or Shift pan held on the tree does not walk after the tree closes" {
    const up = mathx.Dir.n.delta();
    const dt = mathx.FRAME_DT;
    for ([_][2]?mathx.P{ .{ up, null }, .{ null, up } }, [_]bool{ false, true }) |held, pan| {
        var s = Stepper{};
        const on = walkSource(true, pan, held[0], held[1]);
        try std.testing.expect(on.muted and on.p != null);
        for (0..30) |_| _ = s.tick(dt, 1, mathx.Dir.n.heading(), Stepper.SETTLE);
        s.hold();
        const off = walkSource(false, false, held[0], held[1]);
        try std.testing.expect(!off.muted);
        for (0..30) |_| try std.testing.expectEqual(@as(?mathx.Dir, null), s.tick(dt, 1, mathx.Dir.n.heading(), Stepper.SETTLE));
    }
    try std.testing.expect(!walkSource(true, false, up, up).muted);
}

test "a key held through a screen that never latched it walks nothing until it is let go" {
    var s = Stepper{};
    const dt = mathx.FRAME_DT;
    s.hold();
    var steps: usize = 0;
    for (0..30) |_| {
        if (s.tick(dt, 1, mathx.Dir.e.heading(), Stepper.SETTLE) != null) steps += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), steps);
    _ = s.tick(dt, 0, 0, Stepper.SETTLE);
    for (0..30) |_| {
        if (s.tick(dt, 1, mathx.Dir.e.heading(), Stepper.SETTLE) != null) steps += 1;
    }
    try std.testing.expect(steps > 0);
}

test "a way first pressed the frame after the screen changed walks, though one held over does not" {
    const dt = mathx.FRAME_DT;
    var s = Stepper{};
    s.hold();
    s.pressed();
    var steps: usize = 0;
    for (0..30) |_| {
        if (s.tick(dt, 1, mathx.Dir.e.heading(), Stepper.SETTLE) != null) steps += 1;
    }
    try std.testing.expect(steps > 0);
    s.hold();
    s.pressed();
    for (0..30) |_| try std.testing.expectEqual(@as(?mathx.Dir, null), s.tick(dt, 1, mathx.Dir.e.heading(), Stepper.SETTLE));
}

test "a tree pan ended under a held key holds the walk but not pan or zoom, and the first browse after idling steps" {
    var st = State{};
    const dt = mathx.FRAME_DT;
    const east = mathx.Dir.e.heading();
    for (0..10) |_| st.stepWalk(dt, 1, east, Stepper.SETTLE, true);
    st.stepWalk(dt, 1, east, Stepper.SETTLE, false);
    try std.testing.expect(st.pan_hold and st.step.carried());
    st.stepWalk(dt, 0, 0, 0, false);
    try std.testing.expect(!st.pan_hold);
    var idle = State{};
    for (0..10) |_| idle.stepWalk(dt, 0, 0, 0, true);
    var steps: usize = 0;
    for (0..30) |_| {
        idle.stepWalk(dt, 1, east, Stepper.SETTLE, false);
        if (idle.walk != null) steps += 1;
    }
    try std.testing.expect(steps > 0 and !idle.pan_hold);
}

test "letting go of Shift before the key after a tree pan browses nothing until the key is let go" {
    var st = State{};
    const dt = mathx.FRAME_DT;
    const east = mathx.Dir.e.heading();
    for (0..30) |_| st.stepWalk(dt, 1, east, Stepper.SETTLE, true);
    var steps: usize = 0;
    for (0..30) |_| {
        st.stepWalk(dt, 1, east, Stepper.SETTLE, false);
        if (st.walk != null) steps += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), steps);
    st.stepWalk(dt, 0, 0, 0, false);
    for (0..30) |_| {
        st.stepWalk(dt, 1, east, Stepper.SETTLE, false);
        if (st.walk != null) steps += 1;
    }
    try std.testing.expect(steps > 0);
}

test "a way held into the tree stays carried, zooming and panning nothing, until it is let go" {
    var s = Stepper{};
    const dt = mathx.FRAME_DT;
    for (0..30) |_| _ = s.tick(dt, 1, mathx.Dir.n.heading(), Stepper.SETTLE);
    try std.testing.expect(!s.carried());
    s.hold();
    for (0..30) |_| _ = s.tick(dt, 1, mathx.Dir.n.heading(), Stepper.SETTLE);
    try std.testing.expect(s.carried());
    _ = s.tick(dt, 0, 0, Stepper.SETTLE);
    try std.testing.expect(!s.carried());
    _ = s.tick(dt, 1, mathx.Dir.n.heading(), Stepper.SETTLE);
    try std.testing.expect(!s.carried());
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
        for (BUTTONS) |b| try std.testing.expectEqual(b != modifier, s.holdsByKeys(b));
        s.context = .play;
        try std.testing.expectEqual(@as(?rl.KeyboardKey, null), s.againKey());
        try std.testing.expect(s.holdsByKeys(modifier));
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
