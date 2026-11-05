const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const actor = @import("../play/actor.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const game = @import("../game.zig");
const P = mathx.P;

pub fn cellPx(p: P) rl.Vector2 {
    return raster.vec(p.scaled(game.CELL));
}

/// Presentation only: the body already stands on `to`.
pub const Glide = struct {
    from: rl.Vector2,
    to: P,
    t: f32,
    gait: look.Gait,
    stepped: bool = false,
    /// Retain mid-hop height when a new step starts.
    from_lift: f32 = 0,
    /// Pixels toward what a melee blow strikes, at the bump's height; null for a step.
    bump: ?rl.Vector2 = null,
    /// The glides still drawn while this one waits its turn, newest first.
    priors: [PRIORS]?Prior = @splat(null),

    const PRIORS = 3;

    /// Prior motion, offset by `ahead` seconds.
    const Prior = struct {
        from: rl.Vector2,
        to: P,
        gait: look.Gait,
        from_lift: f32,
        bump: ?rl.Vector2,
        ahead: f32,

        fn copy(dst: anytype, src: anytype) void {
            inline for (std.meta.fields(Prior)) |f| {
                if (comptime !std.mem.eql(u8, f.name, "ahead")) @field(dst, f.name) = @field(src, f.name);
            }
        }

        fn later(self: ?Prior, by: f32) ?Prior {
            var p = self orelse return null;
            p.ahead += by;
            return p;
        }
    };

    comptime {
        for (std.meta.fields(Glide)) |f| {
            const own = std.mem.eql(u8, f.name, "t") or std.mem.eql(u8, f.name, "stepped") or std.mem.eql(u8, f.name, "priors");
            std.debug.assert(own or @hasField(Prior, f.name));
        }
    }

    pub fn still(p: P, gait: look.Gait) Glide {
        var gl = Glide{ .from = cellPx(p), .to = p, .t = 0, .gait = gait };
        gl.t = gl.span();
        return gl;
    }

    pub fn rest(a: *const actor.Actor) Glide {
        return still(a.at, look.gait(a.kind));
    }

    pub fn toward(self: Glide, p: P, t: f32) Glide {
        var then = self;
        if (t < 0) then.t -= t;
        var gl = Glide{ .from = then.now(), .to = p, .t = t, .gait = self.gait, .from_lift = then.height() };
        if (t < 0 and self.left() > 0) {
            const ahead = self.t - t;
            var was: Prior = undefined;
            Prior.copy(&was, self);
            was.ahead = ahead;
            gl.priors[0] = was;
            if (self.t < 0) for (self.priors[0 .. PRIORS - 1], gl.priors[1..]) |older, *kept| {
                kept.* = Prior.later(older, ahead);
            };
        }
        return gl;
    }

    fn waiting(self: Glide) ?Glide {
        if (self.t >= 0) return null;
        const p = self.priors[0] orelse return null;
        var gl = Glide{ .from = undefined, .to = undefined, .t = self.t + p.ahead, .gait = undefined };
        Prior.copy(&gl, p);
        for (self.priors[1..], gl.priors[0 .. PRIORS - 1]) |older, *kept| kept.* = Prior.later(older, -p.ahead);
        return gl;
    }

    pub fn bumping(self: Glide, at: P, t: f32) Glide {
        var gl = self.toward(self.to, t);
        gl.bump = raster.vec(at.sub(self.to)).scale(game.BUMP_PX);
        return gl;
    }

    const Motion = enum { hop, slide, bump };

    fn motion(self: Glide) Motion {
        if (self.bump != null) return .bump;
        return switch (self.gait) {
            inline else => |gt| @field(Motion, @tagName(gt)),
        };
    }

    pub fn span(self: Glide) f32 {
        return switch (self.motion()) {
            .hop => game.GLIDE_S,
            .slide => game.SLIDE_S,
            .bump => game.BUMP_S,
        };
    }

    pub fn left(self: Glide) f32 {
        return self.span() - self.t;
    }

    /// `t` is below 0 while the glide waits its turn.
    pub fn done(self: Glide) f32 {
        return std.math.clamp(self.t / self.span(), 0, 1);
    }

    pub fn now(self: Glide) rl.Vector2 {
        if (self.waiting()) |w| return w.now();
        const at = self.ground();
        const b = self.bump orelse return at;
        const k = bumpOf(self.done());
        return .{ .x = at.x + b.x * k, .y = at.y + b.y * k };
    }

    /// Where the body is, its bump aside: the camera follows this.
    pub fn ground(self: Glide) rl.Vector2 {
        if (self.waiting()) |w| return w.ground();
        const k = switch (self.motion()) {
            .hop, .bump => self.done(),
            .slide => overshoot(self.done()),
        };
        return self.from.lerp(cellPx(self.to), k);
    }

    pub fn height(self: Glide) f32 {
        if (self.waiting()) |w| return w.height();
        const k = self.done();
        const hop: f32 = switch (self.motion()) {
            .hop => game.HOP_PX * 4 * k * (1 - k),
            .slide, .bump => 0,
        };
        return self.from_lift * (1 - k) + hop;
    }

    /// Pixels above the ground the body is drawn; its shadow, bar, light and the camera stay on the ground.
    pub fn lift(self: Glide) i32 {
        return mathx.roundTiesUp(self.height());
    }
};

fn bumpOf(k: f32) f32 {
    if (k < game.BUMP_HIT) {
        const u = k / game.BUMP_HIT;
        return u * u;
    }
    return 1 - mathx.smoothstep(game.BUMP_HIT, 1, k);
}

/// Penner's ease-out-back.
fn overshoot(k: f32) f32 {
    const u = k - 1;
    return 1 + (game.SLIDE_BACK + 1) * u * u * u + game.SLIDE_BACK * u * u;
}

test "two knocks queued behind a walk keep drawing the walk first" {
    const a = P{ .x = 4, .y = 4 };
    const walk = Glide.still(a, .hop).toward(.{ .x = 5, .y = 4 }, 0);
    const first = walk.toward(.{ .x = 6, .y = 4 }, -0.13);
    var second = first.toward(.{ .x = 7, .y = 4 }, -0.41);
    var shown = walk;
    var at: f32 = 0;
    while (at < 0.6) : (at += 0.01) {
        second.t = -0.41 + at;
        const want = if (at < 0.13) blk: {
            shown.t = at;
            break :blk shown.now();
        } else if (at < 0.41) blk: {
            var k = first;
            k.t = -0.13 + at;
            break :blk k.now();
        } else second.now();
        try std.testing.expectApproxEqAbs(want.x, second.now().x, 0.01);
        try std.testing.expectApproxEqAbs(want.y, second.now().y, 0.01);
    }
    second.t = -0.41;
    try std.testing.expectApproxEqAbs(cellPx(a).x, second.now().x, 0.01);
    std.debug.print("glide: a walk then two queued knocks draw in order from the walk's start\n", .{});
}
