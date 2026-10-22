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
    splashed: bool = false,
    /// Retain mid-hop height when a new step starts.
    from_lift: f32 = 0,
    /// Pixels toward what a melee blow strikes, at the bump's height; null for a step.
    bump: ?rl.Vector2 = null,
    /// The glide still drawn while this one waits its turn.
    prior: ?Prior = null,

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
    };

    comptime {
        for (std.meta.fields(Glide)) |f| {
            const own = std.mem.eql(u8, f.name, "t") or std.mem.eql(u8, f.name, "splashed") or std.mem.eql(u8, f.name, "prior");
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
        var prior: ?Prior = null;
        if (t < 0 and self.left() > 0) {
            var was: Prior = undefined;
            Prior.copy(&was, self);
            was.ahead = self.t - t;
            prior = was;
        }
        return .{ .from = then.now(), .to = p, .t = t, .gait = self.gait, .from_lift = then.height(), .prior = prior };
    }

    fn waiting(self: Glide) ?Glide {
        if (self.t >= 0) return null;
        const p = self.prior orelse return null;
        var gl = Glide{ .from = undefined, .to = undefined, .t = self.t + p.ahead, .gait = undefined };
        Prior.copy(&gl, p);
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
