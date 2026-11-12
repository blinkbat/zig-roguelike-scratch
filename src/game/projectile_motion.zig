const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const bow = @import("../play/bow.zig");
const firebolt = @import("../play/firebolt.zig");
const skillbar = @import("../play/skillbar.zig");
const fx = @import("../gfx/fx.zig");
const P = mathx.P;

pub const ZAP_S: f32 = 0.08;

pub const MotionView = struct {
    at: ?[2]f32 = null,
    alpha: f32 = 0,

    pub fn step(self: *MotionView, at: ?[2]f32, visible: bool, k: f32) void {
        if (visible) self.at = at;
        self.alpha = mathx.ease(self.alpha, if (visible) 1 else 0, k, k);
        if (self.alpha == 0) self.at = null;
    }
};

test "hidden projectile motion retains its last visible position until fully faded" {
    var view = MotionView{};
    const seen = [2]f32{ 4.5, 6.5 };
    const hidden = [2]f32{ 9.5, 6.5 };
    view.step(seen, true, 1);
    try std.testing.expectEqual(seen, view.at.?);
    try std.testing.expectEqual(@as(f32, 1), view.alpha);
    view.step(hidden, false, 0.25);
    try std.testing.expectEqual(seen, view.at.?);
    try std.testing.expect(view.alpha > 0 and view.alpha < 1);
    view.step(hidden, false, 1);
    try std.testing.expect(view.at == null);
    try std.testing.expectEqual(@as(f32, 0), view.alpha);
}

const FLIGHT_S: f32 = 0.022;
const TRAIL_PER_CELL: usize = 12;

pub fn flown(n: usize) f32 {
    return @as(f32, @floatFromInt(n)) * FLIGHT_S;
}

/// Presentation only: the hit already resolved when this was made.
pub const Shot = struct {
    view: MotionView = .{},
    flight: bow.Flight,
    from: P,
    act: skillbar.Act = .shoot,
    net: bool = false,
    hook: bool = false,
    t: f32 = 0,
    trail_t: f32 = 0,

    pub fn lands(self: *const Shot) f32 {
        return flown(self.flight.len -| 1);
    }

    pub fn ends(self: *const Shot) f32 {
        return flown(self.flight.len);
    }

    pub fn position(self: *const Shot, time: f32) [2]f32 {
        const a = mathx.centre(self.from);
        const b = mathx.centre(self.flight.end() orelse return a);
        const duration = self.lands();
        const k = if (duration > 0) std.math.clamp(time / duration, 0, 1) else 1;
        return mathx.lerp2(a, b, k);
    }

    pub fn direction(self: *const Shot) [2]f32 {
        return mathx.unitToward(mathx.centre(self.from), self.position(self.ends()));
    }

    /// false once it has ended.
    pub fn fly(self: *Shot, effects: *fx.Fx, lv: *const grid.Level, dt: f32) bool {
        self.t += dt;
        const end = @min(self.t, self.lands());
        const gap = self.lands() / @as(f32, @floatFromInt(@max(1, self.flight.len * TRAIL_PER_CELL)));
        const heading = self.direction();
        while (self.trail_t < end) : (self.trail_t += gap) effects.trail(lv, self.position(self.trail_t), heading, self.act, self.t - self.trail_t);
        return self.t < self.ends();
    }

    pub fn zapInto(self: *const Shot, effects: *fx.Fx) void {
        if (self.act.element() != .lightning) return;
        const to = self.flight.end() orelse return;
        effects.zap(@max(0, self.lands() - ZAP_S), .{ .from = mathx.centre(self.from), .to = mathx.centre(to) });
    }
};

test "missiles move continuously to the existing impact time in every direction" {
    const lv = grid.openFloor();
    const from = P{ .x = 20, .y = 20 };
    for (mathx.ALL_DIRS) |d| {
        const delta = d.delta();
        const to = P{ .x = from.x + delta.x * 6, .y = from.y + delta.y * 6 };
        const shot_ = Shot{ .from = from, .flight = bow.fly(&lv, from, to) };
        const lands = shot_.lands();
        try std.testing.expectEqual(mathx.centre(from), shot_.position(0));
        try std.testing.expectEqual(mathx.centre(to), shot_.position(lands));
        const a = shot_.position(lands * 0.4);
        const b = shot_.position(lands * 0.41);
        const moved = mathx.len(b[0] - a[0], b[1] - a[1]);
        try std.testing.expect(moved > 0 and moved < 0.1);
    }
}

/// Seconds a firebolt takes over each cell it flies.
pub const BOLT_CELL_S: f32 = 0.09;

/// A firebolt as drawn: from `from` to `to` over `span` seconds once `t` reaches 0; seen before then if `before`, and after if `after`.
pub const BoltShown = struct {
    view: MotionView = .{},
    from: [2]f32,
    to: [2]f32,
    heading: [2]f32,
    t: f32 = 0,
    span: f32 = 0,
    before: bool = true,
    after: bool = true,

    pub fn resting(b: firebolt.Bolt) BoltShown {
        const p = b.point();
        return .{ .from = p, .to = p, .heading = b.heading() };
    }

    pub fn at(self: *const BoltShown) ?[2]f32 {
        if (self.t < 0) return if (self.before) self.from else null;
        if (self.done()) return if (self.after) self.to else null;
        return mathx.lerp2(self.from, self.to, self.t / self.span);
    }

    pub fn moving(self: *const BoltShown) bool {
        return self.t >= 0 and !self.done();
    }

    pub fn done(self: *const BoltShown) bool {
        return self.t >= self.span;
    }
};
