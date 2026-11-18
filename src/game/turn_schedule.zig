const std = @import("std");
const P = @import("../core/mathx.zig").P;

pub const Pace = struct { stagger: f32, bump_lands: f32 };

pub const Motion = struct {
    start_in: f32,
    hero: bool,
    ally: bool = false,
    moved: bool,
    lunges: bool,
    shown: bool,
    visible_origin: bool,
    arrow_seen: bool,
    mending: bool,
    motion_left: f32,
    clear_in: f32,
};

pub const Body = struct {
    moved: bool,
    staggered: bool,
    starts_at: f32,
    begins_in: f32,
    impact_in: f32,
    finishes_in: f32,

    pub fn afterMotion(self: *Body, bumps: bool, strikes: bool, motion_left: f32) bool {
        const held = (self.moved or bumps) and self.staggered;
        if (held) self.finishes_in = motion_left;
        if (self.moved and self.staggered and strikes) self.impact_in = @max(self.impact_in, self.finishes_in);
        return held;
    }

    pub fn reactionRelease(self: Body) f32 {
        return if (self.moved) self.finishes_in else self.impact_in;
    }

    pub fn finishAfter(self: *Body, deadline_in: f32) void {
        self.finishes_in = @max(self.finishes_in, deadline_in);
    }

    pub fn emergesIn(self: Body, submerged: bool) f32 {
        if (submerged or self.moved) return self.finishes_in;
        return if (self.staggered) @max(0, self.begins_in) else self.begins_in;
    }
};

pub const Turn = struct {
    late: f32,
    next_at: f32,
    hero_cell: P,
    pace: Pace,
    /// No foe in sight: allies that only walk keep step with the hero instead of following in turn.
    quiet: bool = false,

    pub fn begin(late: f32, lead_in: ?f32, hero_cell: P, pace: Pace) Turn {
        return .{
            .late = late,
            .next_at = if (lead_in) |t| staggeredAfter(t, late, pace) else 0,
            .hero_cell = hero_cell,
            .pace = pace,
        };
    }

    pub fn afterBolts(self: *Turn, lands_in: f32) void {
        if (lands_in > 0) self.next_at = @max(self.next_at, staggeredAfter(lands_in, self.late, self.pace));
    }

    pub fn motion(self: *Turn, facts: Motion) Body {
        const in_step = self.quiet and facts.ally and facts.moved and !facts.lunges;
        const staggered = staggers(facts) and !in_step;
        var starts_at = if (staggered) self.next_at else 0;
        if (staggered and !facts.hero and (facts.moved or facts.lunges)) starts_at = @max(starts_at, self.late + facts.motion_left);
        if (staggered and facts.moved and !facts.hero) starts_at = @max(starts_at, self.late + facts.clear_in);
        if (staggered) self.next_at = starts_at + self.pace.stagger;
        const begins_in = if (staggered) starts_at - self.late else facts.start_in;
        return .{
            .moved = facts.moved,
            .staggered = staggered,
            .starts_at = starts_at,
            .begins_in = begins_in,
            .impact_in = begins_in + self.pace.bump_lands,
            .finishes_in = if (staggered or facts.moved) begins_in else @max(facts.start_in, facts.motion_left),
        };
    }

    pub fn projectile(self: *Turn, body: *Body, lands_in: f32, ends_in: f32) void {
        body.impact_in = lands_in;
        body.finishes_in = ends_in;
        self.next_at = @max(self.next_at, ends_in + self.late);
    }

    pub fn reaction(self: *Turn, body: *Body, impact_in: f32) void {
        body.finishAfter(impact_in);
        self.next_at = @max(self.next_at, staggeredAfter(impact_in, self.late, self.pace));
    }

    pub fn knock(self: *Turn, body: *Body, to: P, motion_left: f32) void {
        body.finishAfter(motion_left);
        self.hero_cell = to;
        self.next_at = @max(self.next_at, self.late + motion_left);
    }

    pub fn recoveryReadyIn(self: Turn) f32 {
        return @max(0, self.next_at - self.late);
    }
};

pub fn staggers(facts: Motion) bool {
    const visible_action = (facts.shown or facts.arrow_seen) and (facts.lunges or facts.mending);
    return if (facts.moved) facts.shown or facts.visible_origin else visible_action;
}

fn staggeredAfter(in: f32, late: f32, pace: Pace) f32 {
    return in + late + pace.stagger;
}

test "turn schedule uses one time origin for late movement projectile reaction and knockback" {
    const at = P{ .x = 3, .y = 4 };
    var turn = Turn.begin(0.5, 0.2, at, .{ .stagger = 0.1, .bump_lands = 0.05 });
    turn.afterBolts(0.4);
    var body = turn.motion(.{ .start_in = 0.4, .hero = false, .moved = true, .lunges = true, .shown = true, .visible_origin = true, .arrow_seen = false, .mending = false, .motion_left = 0.8, .clear_in = 0.9 });
    try std.testing.expectApproxEqAbs(@as(f32, 1.4), body.starts_at, 0.00001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.9), body.begins_in, 0.00001);
    try std.testing.expect(body.afterMotion(false, true, 1.2));
    try std.testing.expectEqual(@as(f32, 1.2), body.impact_in);
    turn.projectile(&body, 1.4, 1.5);
    try std.testing.expectEqual(@as(f32, 1.5), body.reactionRelease());
    turn.reaction(&body, 1.8);
    const knocked = P{ .x = 4, .y = 4 };
    turn.knock(&body, knocked, 2);
    try std.testing.expectEqual(knocked, turn.hero_cell);
    try std.testing.expectEqual(@as(f32, 2), body.finishes_in);
    try std.testing.expectEqual(@as(f32, 2), turn.recoveryReadyIn());
}

test "turn schedule gives hidden harm its start without delaying later visible actors" {
    var turn = Turn.begin(0.5, null, .{ .x = 0, .y = 0 }, .{ .stagger = 0.1, .bump_lands = 0.05 });
    var hidden = turn.motion(.{ .start_in = 0.3, .hero = false, .moved = false, .lunges = false, .shown = false, .visible_origin = false, .arrow_seen = false, .mending = false, .motion_left = -1, .clear_in = 0 });
    try std.testing.expect(!hidden.staggered);
    try std.testing.expectEqual(@as(f32, 0.3), hidden.finishes_in);
    try std.testing.expectEqual(@as(f32, 0), turn.next_at);
    hidden.finishAfter(0.7);
    try std.testing.expectEqual(@as(f32, 0.3), hidden.emergesIn(false));
    try std.testing.expectEqual(@as(f32, 0.7), hidden.emergesIn(true));
    const visible = turn.motion(.{ .start_in = 0.3, .hero = false, .moved = false, .lunges = true, .shown = true, .visible_origin = true, .arrow_seen = false, .mending = false, .motion_left = 0, .clear_in = 0 });
    try std.testing.expect(visible.staggered);
    try std.testing.expectEqual(@as(f32, 0), visible.begins_in);
}
