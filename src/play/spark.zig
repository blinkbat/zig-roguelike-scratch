const std = @import("std");
const damage = @import("damage.zig");
const clock = @import("clock.zig");

pub const COST: i32 = 2;
pub const AILMENT = @import("resilience.zig").Kind.stun;
pub const CHANCE = damage.AfflictionChance{ .percent = 50 };
pub const VERB = "sparks";
pub const BOLT = "spark";
pub const BOLT_RANGE: i32 = 7;
pub const TAKES = clock.STUNNED;
pub const ELEMENT: damage.Element = .lightning;
pub const DESCRIPTION = std.fmt.comptimePrint("Strike a target in sight with lightning. {s}.", .{clock.stunNote(CHANCE.percent)});

pub const BASE = damage.Base{ .lo = 3, .hi = 4 };

pub const afflict = clock.stuns;
