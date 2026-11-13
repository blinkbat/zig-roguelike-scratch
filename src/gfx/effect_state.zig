const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const actor = @import("../play/actor.zig");
const damage = @import("../play/damage.zig");
const areas = @import("../play/area.zig");
const resilience = @import("../play/resilience.zig");
const sunder = @import("../play/sunder.zig");
const ward = @import("../play/ward.zig");
const clock = @import("../play/clock.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("look.zig");
const light = @import("light.zig");
const lume = @import("../map/lume.zig");
const menu = @import("../ui/menu.zig");

pub const Matter = enum { blood, ooze, wood, ichor };

pub const ActorImpact = struct {
    slot: actor.ActorSlot,
    at: mathx.P,
    lethal: bool,
    after: ?After = null,
};

pub const Impact = union(enum) {
    actor: ActorImpact,
    barrel: mathx.P,

    pub fn at(self: Impact) mathx.P {
        return switch (self) {
            .actor => |a| a.at,
            .barrel => |p| p,
        };
    }

    pub fn lethal(self: Impact) bool {
        return switch (self) {
            .actor => |a| a.lethal,
            .barrel => true,
        };
    }
};

pub const Blow = struct {
    impact: Impact,
    /// Unit travel direction; null scatters a directionless hit such as gas.
    dir: ?[2]f32,
    matter: Matter,
    element: ?damage.Element = null,
};

const BURN_GLOW = light.Reach{ .radius = 2, .gain = 0.55 };
const WARD_GLOW = light.Reach{ .radius = 1.5, .gain = 0.25 };
const STUN_GLOW = light.Reach{ .radius = 1.3, .gain = 0.45 };
pub const FLAMES_GLOW = light.Reach{ .radius = @as(f32, @floatFromInt(lume.FIRE_REACH)) + 0.5, .gain = 0.3 };
/// What a body suffers for turns, in the order the hud names them.
pub const Status = enum {
    stunned,
    bleeding,
    burning,
    chilled,
    pinned,
    shocked,
    sundered,
    blinded,
    confused,
    enfeebled,
    maimed,
    frightened,
    exposed,
    warded,
    resistant,
    guarding,
    unyielding,
    steady,
    overwatch,
    imbued,
    biding,

    pub fn ink(s: Status) rl.Color {
        return switch (s) {
            .warded => look.WARD,
            .exposed => look.ailmentInk(.sunder),
            .imbued => look.ailmentInk(.burn),
            .resistant => look.UI_GOLD,
            inline else => |t| if (comptime t.stance() != null) look.UI_GOLD else look.ailmentInk(comptime t.ailment().?),
        };
    }

    pub fn ailment(s: Status) ?resilience.Kind {
        return switch (s) {
            .stunned => .stun,
            .bleeding => .bleed,
            .burning => .burn,
            .chilled => .chill,
            .pinned => .pin,
            .shocked => .shock,
            .sundered => .sunder,
            .blinded => .blind,
            .confused => .confusion,
            .enfeebled => .enfeeble,
            .maimed => .maim,
            .frightened => .fright,
            .exposed, .warded, .resistant, .guarding, .unyielding, .steady, .overwatch, .imbued, .biding => null,
        };
    }

    fn stance(s: Status) ?skillbar.Act {
        return switch (s) {
            .guarding => .guard,
            .unyielding => .unyielding,
            .steady => .steady_aim,
            .overwatch => .overwatch,
            .imbued => .imbue,
            .biding => .bide,
            .stunned, .bleeding, .burning, .chilled, .pinned, .shocked, .sundered, .blinded, .confused, .enfeebled, .maimed, .frightened, .exposed, .warded, .resistant => null,
        };
    }

    /// The first status a body has, in this order, that glows lights it.
    pub fn glow(s: Status) ?light.Reach {
        return switch (s) {
            .stunned => STUN_GLOW,
            .burning => BURN_GLOW,
            .warded => WARD_GLOW,
            .bleeding, .chilled, .pinned, .shocked, .sundered, .blinded, .confused, .enfeebled, .maimed, .frightened, .exposed, .resistant, .guarding, .unyielding, .steady, .overwatch, .imbued, .biding => null,
        };
    }

    pub fn emission(s: Status, at: [2]f32, flicker: f32) ?light.Emission {
        const g = s.glow() orelse return null;
        return g.lit(at, s.ink(), flicker);
    }

    pub fn title(s: Status) [:0]const u8 {
        return switch (s) {
            .warded => skillbar.Act.mana_shield.name(),
            .resistant => "Status resistance",
            inline else => |t| if (comptime t.stance()) |a| a.name() else comptime menu.capital(@tagName(t)),
        };
    }

    pub fn about(s: Status) []const u8 {
        return switch (s) {
            .stunned => clock.STATUS,
            .resistant => resilience.ABOUT,
            .frightened => actor.FRIGHT_STATUS,
            .exposed => actor.EXPOSED_STATUS,
            inline else => |t| comptime if (t.stance()) |a| skillbar.Act.skill(a).DESCRIPTION else module(t).STATUS,
        };
    }

    fn module(comptime s: Status) type {
        if (comptime s.stance() != null) @compileError("about names " ++ @tagName(s) ++ "'s skill's text");
        return switch (s) {
            .warded => ward,
            .stunned, .frightened, .exposed, .resistant => @compileError("about names " ++ @tagName(s) ++ "'s text itself"),
            else => resilience.module(comptime s.ailment().?).?,
        };
    }

    fn field(comptime s: Status) []const u8 {
        return switch (s) {
            .stunned => "clock",
            .warded => "ward",
            .resistant => "resilience",
            .exposed => "stuck",
            inline else => |t| if (comptime t.stance() != null) "tactics" else @tagName(comptime t.ailment().?),
        };
    }

    fn turnsOf(s: Status, a: actor.Actor) u8 {
        return switch (s) {
            .stunned => @intFromBool(a.clock.stunned),
            .resistant => a.resilience.peak().turns,
            .guarding => @intFromBool(a.tactics.guard > 0),
            .unyielding => @intFromBool(a.tactics.unyielding),
            .steady => @intFromBool(a.tactics.steady > 0),
            .overwatch => @intFromBool(a.tactics.overwatch != null),
            .imbued => a.tactics.imbue,
            .biding => a.tactics.bide,
            .frightened => a.fright,
            .exposed => @intFromBool(a.stuck),
            inline else => |t| @field(a, field(t)).turns,
        };
    }

    comptime {
        for (std.meta.fields(actor.Actor)) |f| {
            if (@typeInfo(f.type) != .@"struct" or !@hasField(f.type, "turns")) continue;
            var claimed = false;
            for (std.enums.values(Status)) |s| claimed = claimed or std.mem.eql(u8, field(s), f.name);
            if (!claimed) @compileError("effect_state.Status: no status shows Actor." ++ f.name);
        }
    }
};

/// Presented body state; `seq` preserves simulation hit order.
pub const Body = struct {
    kind: actor.Kind,
    hp: i32,
    max: i32,
    seq: u64,
    status: std.EnumArray(Status, u8) = .initFill(0),
    resilience: resilience.State = .{},
    sunder: sunder.Sunder = .{},
    braced: ?mathx.Dir = null,

    pub fn of(a: actor.Actor, seq: u64) Body {
        var b = Body{ .kind = a.kind, .hp = a.hp, .max = a.max, .seq = seq };
        if (a.alive) {
            b.resilience = a.resilience;
            b.sunder = a.sunder;
            b.braced = a.braced;
            for (std.enums.values(Status)) |s| b.status.set(s, s.turnsOf(a));
        }
        return b;
    }

    pub fn hurt(self: Body) bool {
        return self.hp < self.max;
    }

    pub fn down(self: Body) bool {
        return self.hp <= 0;
    }
};

/// State at impact; `reveals` is the newly visible split-half pool slot.
pub const After = struct { body: Body, reveals: ?actor.ActorSlot = null, mana: i32 = 0 };

pub const Drip = struct { at: [2]f32, matter: Matter };

pub const Puff = struct {
    at: [2]f32,
    ink: rl.Color,
    motes: usize = TICK_WISPS,

    pub fn over(mark: ?[2]f32, ink: rl.Color) ?Puff {
        return .{ .at = mark orelse return null, .ink = ink };
    }
};

pub const TICK_WISPS: usize = 6;
pub const BURST_WISPS: usize = 22;

pub const Sting = struct { slot: actor.ActorSlot, after: ?After = null, fire_at: ?[2]f32 = null, drip: ?Drip = null, puff: ?Puff = null };

pub const Settle = struct { slot: actor.ActorSlot, after: After, puff: ?Puff = null };

pub const Burst = struct { at: mathx.P, area: areas.Burst, element: damage.Element };

pub const Zap = struct { from: [2]f32, to: [2]f32 };

pub const Shimmer = struct { at: [2]f32, col: rl.Color };

test "the hero and foes picture a stun alike, with a mark over the body" {
    for ([_]actor.Kind{ actor.HERO, .rat }) |k| {
        var a = actor.Actor.of(k, .{ .x = 4, .y = 4 });
        try std.testing.expectEqual(@as(u8, 0), Body.of(a, 0).status.get(.stunned));
        a.clock.stun();
        try std.testing.expectEqual(@as(u8, 1), Body.of(a, 0).status.get(.stunned));
    }
    try std.testing.expect(@import("status_marks.zig").Renderer.marks(.stunned));
}
