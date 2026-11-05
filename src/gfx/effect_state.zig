const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const actor = @import("../play/actor.zig");
const damage = @import("../play/damage.zig");
const glacial = @import("../play/glacial.zig");
const resilience = @import("../play/resilience.zig");
const sunder = @import("../play/sunder.zig");
const ward = @import("../play/ward.zig");
const tactics = @import("../play/tactics.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("look.zig");
const light = @import("light.zig");
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
    fire: bool = false,
};

const StatusGlow = struct { radius: f32, gain: f32 };
const BURN_GLOW = StatusGlow{ .radius = 2, .gain = 0.55 };
const WARD_GLOW = StatusGlow{ .radius = 1.5, .gain = 0.25 };
/// What a body suffers for turns, in the order the hud names them.
pub const Status = enum {
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
    warded,
    resistant,
    guarding,
    unyielding,
    steady,
    overwatch,

    pub fn ink(s: Status) rl.Color {
        return switch (s) {
            .warded => look.WARD,
            .resistant, .guarding, .unyielding, .steady, .overwatch => look.UI_GOLD,
            inline else => |t| look.ailmentInk(comptime t.ailment().?),
        };
    }

    fn ailment(s: Status) ?resilience.Kind {
        return switch (s) {
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
            .warded, .resistant, .guarding, .unyielding, .steady, .overwatch => null,
        };
    }

    /// The first status a body has, in this order, that glows lights it.
    pub fn glow(s: Status) ?StatusGlow {
        return switch (s) {
            .burning => BURN_GLOW,
            .warded => WARD_GLOW,
            .bleeding, .chilled, .pinned, .shocked, .sundered, .blinded, .confused, .enfeebled, .maimed, .frightened, .resistant, .guarding, .unyielding, .steady, .overwatch => null,
        };
    }

    pub fn emission(s: Status, at: [2]f32, flicker: f32) ?light.Emission {
        const g = s.glow() orelse return null;
        return .{ .at = .{ at[0], at[1], light.BODY_Z }, .col = s.ink(), .radius = g.radius, .gain = g.gain * flicker };
    }

    pub fn title(s: Status) [:0]const u8 {
        return switch (s) {
            .warded => skillbar.Act.mana_shield.name(),
            .resistant => "Status resistance",
            .guarding => skillbar.Act.guard.name(),
            .unyielding => skillbar.Act.unyielding.name(),
            .steady => skillbar.Act.steady_aim.name(),
            .overwatch => skillbar.Act.overwatch.name(),
            inline else => |t| comptime menu.capital(@tagName(t)),
        };
    }

    /// What it does to the body, as its tooltip says.
    pub fn about(s: Status) []const u8 {
        return switch (s) {
            .resistant => resilience.ABOUT,
            .guarding => tactics.Guard.DESCRIPTION,
            .unyielding => tactics.Unyielding.DESCRIPTION,
            .steady => tactics.SteadyAim.DESCRIPTION,
            .overwatch => tactics.Overwatch.DESCRIPTION,
            .frightened => actor.FRIGHT_STATUS,
            inline else => |t| module(t).STATUS,
        };
    }

    fn module(comptime s: Status) type {
        return switch (s) {
            .warded => ward,
            .frightened, .resistant, .guarding, .unyielding, .steady, .overwatch => @compileError("about names " ++ @tagName(s) ++ "'s text itself"),
            else => resilience.module(comptime s.ailment().?),
        };
    }

    fn field(comptime s: Status) []const u8 {
        return switch (s) {
            .warded => "ward",
            .resistant => "resilience",
            .guarding, .unyielding, .steady, .overwatch => "tactics",
            inline else => |t| @tagName(comptime t.ailment().?),
        };
    }

    fn turnsOf(s: Status, a: actor.Actor) u8 {
        return switch (s) {
            .resistant => a.resilience.peak().turns,
            .guarding => @intFromBool(a.tactics.guard > 0),
            .unyielding => @intFromBool(a.tactics.unyielding),
            .steady => @intFromBool(a.tactics.steady > 0),
            .overwatch => @intFromBool(a.tactics.overwatch != null),
            .frightened => a.fright,
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
    /// Turns left of each.
    status: std.EnumArray(Status, u8) = .initFill(0),
    resilience: resilience.State = .{},
    sunder: sunder.Sunder = .{},

    pub fn of(a: actor.Actor, seq: u64) Body {
        var b = Body{ .kind = a.kind, .hp = a.hp, .max = a.max, .seq = seq };
        if (a.alive) {
            b.resilience = a.resilience;
            b.sunder = a.sunder;
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

/// Gas curling off a body it eats at or mends, or out of a glowbulb bursting.
pub const Puff = struct {
    at: [2]f32,
    ink: rl.Color,
    motes: usize = TICK_WISPS,

    /// Over a body seen at `mark`; none for an unseen one.
    pub fn over(mark: ?[2]f32, ink: rl.Color) ?Puff {
        return .{ .at = mark orelse return null, .ink = ink };
    }
};

pub const TICK_WISPS: usize = 6;
pub const BURST_WISPS: usize = 22;

pub const Sting = struct { slot: actor.ActorSlot, after: ?After = null, fire_at: ?[2]f32 = null, drip: ?Drip = null, puff: ?Puff = null };

/// A body changed by no seen blow, as a chill wearing off or a heal: it catches up unflashed.
pub const Settle = struct { slot: actor.ActorSlot, after: After, puff: ?Puff = null };

pub const Burst = struct { at: mathx.P, area: glacial.Burst, element: damage.Element };

pub const Zap = struct { from: [2]f32, to: [2]f32 };

pub const Shimmer = struct { at: [2]f32, col: rl.Color };
