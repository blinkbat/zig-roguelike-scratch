const std = @import("std");
const rl = @import("raylib");
const mathx = @import("mathx.zig");

/// Schmitt trigger plus DAS/ARR; `settle` merges staggered key presses into diagonals.
pub const Stepper = struct {
    pub const FIRE: f32 = 0.50;
    pub const REARM: f32 = 0.32;
    pub const DAS: f32 = 0.28;
    pub const ARR: f32 = 0.2175;
    pub const SETTLE: f32 = 0.05;

    latched: ?mathx.Dir = null,
    held: f32 = 0,
    due: f32 = 0,
    fired: u32 = 0,
    /// How long before this frame's end the last step was due.
    late: f32 = 0,
    owed: ?mathx.Dir = null,
    /// A way pressed down that has not stepped yet.
    press: bool = false,
    /// This frame's step is that press's, not a held way repeating or turning.
    fresh: bool = false,

    pub fn tick(self: *Stepper, dt: f32, deflection: f32, heading: f32, settle: f32) ?mathx.Dir {
        self.fresh = false;
        if (!stickWalks(deflection, self.latched != null)) {
            const tap = self.owed;
            const press = self.press;
            self.* = .{ .fresh = press and tap != null };
            return tap;
        }
        const now = mathx.dirOf(heading, self.latched);
        if (self.latched != now) {
            if (self.carried() and (if (self.latched) |last| partOf(now, last) else true)) {
                self.latched = now;
                return null;
            }
            const owed = self.owe(now);
            self.* = .{ .latched = now, .due = settle, .owed = owed, .press = self.press };
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
        self.fresh = self.press;
        self.press = false;
        return now;
    }

    /// Rearm only on release or direction change; staggered diagonal release stays held.
    pub fn hold(self: *Stepper) void {
        self.* = .{ .latched = self.latched, .held = self.held, .due = HELD, .fired = 1 };
    }

    pub const HELD = std.math.inf(f32);

    /// A way first pressed after the screen changed was not held over, unless one was already latched.
    pub fn pressed(self: *Stepper) void {
        if (self.carried() and self.latched == null) self.* = .{};
    }

    /// A way held over from another screen, still down.
    pub fn carried(self: Stepper) bool {
        return self.due == HELD;
    }

    /// A diagonal that has not stepped survives one of its keys coming up first.
    fn owe(self: Stepper, now: mathx.Dir) ?mathx.Dir {
        const last = self.latched orelse return now;
        if (self.fired > 0) return if (partOf(now, last)) null else now;
        const o = self.owed orelse return now;
        return if (partOf(now, o)) o else now;
    }
};

pub fn stickWalks(deflection: f32, was: bool) bool {
    return deflection >= Stepper.FIRE or (was and deflection >= Stepper.REARM);
}

fn partOf(d: mathx.Dir, diag: mathx.Dir) bool {
    if (!diag.diagonal() or d.diagonal()) return false;
    const a = diag.delta();
    const b = d.delta();
    return b.x == a.x or b.y == a.y;
}

pub const RadialStepper = struct {
    direction: ?rl.Vector2 = null,
    wait: f32 = 0,

    /// Cosine of 40 degrees: a bearing turned further than this is a fresh press, not a hold.
    const TURN_COS: f32 = 0.766;
    const ARR: f32 = 0.1625;

    pub fn tick(self: *RadialStepper, dt: f32, x: f32, y: f32) ?rl.Vector2 {
        const magnitude = mathx.len(x, y);
        if (!stickWalks(magnitude, self.direction != null)) {
            self.* = .{};
            return null;
        }
        const next = rl.Vector2{ .x = x / magnitude, .y = y / magnitude };
        const turned = if (self.direction) |old| old.x * next.x + old.y * next.y < TURN_COS else true;
        if (turned) {
            self.direction = next;
            self.wait = Stepper.DAS;
            return next;
        }
        self.wait -= dt;
        if (self.wait > 0) return null;
        self.wait = ARR;
        self.direction = next;
        return next;
    }
};

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

test "only a pressed way steps fresh, not a held one repeating or letting a diagonal's key go" {
    var s = Stepper{ .press = true };
    const dt = mathx.FRAME_DT;
    var steps: usize = 0;
    var fresh: usize = 0;
    for ([_]mathx.Dir{ .ne, .e }) |d| {
        for (0..60) |_| {
            if (s.tick(dt, 1, d.heading(), Stepper.SETTLE) == null) continue;
            steps += 1;
            if (s.fresh) fresh += 1;
        }
    }
    std.debug.print("held north-east then east: {d} steps, {d} fresh\n", .{ steps, fresh });
    try std.testing.expect(steps > 3 and fresh == 1);
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
