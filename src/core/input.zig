const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

// THE ONLY FILE THAT TOUCHES A DEVICE. The pad is primary and the only one the UI names; the keyboard mirrors it.

pub const PAD: i32 = 0;
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
        };
    }

    fn keys(b: Button) []const rl.KeyboardKey {
        return switch (b) {
            .a => &.{ .enter, .kp_enter },
            .b => &.{ .period, .kp_5 },
            .x => &.{ .f, .space },
            .y => &.{.e},
            .lb => &.{.q},
            .rb => &.{.r},
            .rt => &.{.t},
            .view => &.{.tab},
        };
    }

    pub fn caption(b: Button) [:0]const u8 {
        return padName(b.pad());
    }
};

const BUTTONS = std.enums.values(Button);
const FULLSCREEN_KEYS = [_]rl.KeyboardKey{ .enter, .kp_enter };

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

pub const State = struct {
    pressed: std.EnumSet(Button) = .initEmpty(),
    down: std.EnumSet(Button) = .initEmpty(),
    fullscreen: bool = false,
    walk: ?mathx.Dir = null,
    lean: bool = false,
    step: Stepper = .{},

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
                    on = on or rl.isKeyPressed(k);
                    hold = hold or rl.isKeyDown(k);
                }
            }
            self.pressed.setPresent(b, on);
            self.down.setPresent(b, hold);
        }
        self.fullscreen = false;
        if (alt_down) {
            for (FULLSCREEN_KEYS) |k| self.fullscreen = self.fullscreen or rl.isKeyPressed(k);
        }
        self.lean = pad and rl.isGamepadButtonDown(PAD, LEAN);

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
            if (digital orelse keyWalk()) |d| {
                defl = 1;
                heading = mathx.headingOf(@floatFromInt(d.x), @floatFromInt(d.y));
                settle = Stepper.SETTLE;
            }
        }
        self.walk = self.step.tick(dt, defl, heading, settle);
    }
};

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

fn keyWalk() ?mathx.P {
    var p = mathx.P{ .x = 0, .y = 0 };
    for (WALKS) |w| {
        for (w.keys) |k| {
            if (!rl.isKeyDown(k)) continue;
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
