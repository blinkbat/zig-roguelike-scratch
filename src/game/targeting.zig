const std = @import("std");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const skillbar = @import("../play/skillbar.zig");

pub const Aim = struct {
    by: input.Button,
    set: skillbar.Set = .primary,
    mark: mathx.P,
    action: union(enum) { single: skillbar.Act, wall_start: skillbar.Act, wall_end: struct { act: skillbar.Act, at: mathx.P } },
    /// The mark last confirmed with no visible target on its line, awaiting a second confirmation.
    asked: ?mathx.P = null,

    pub fn of(by: input.Button, act_: skillbar.Act, mark: mathx.P) Aim {
        std.debug.assert(act_.reticle() != null);
        return .{ .by = by, .mark = mark, .action = if (act_.spans()) .{ .wall_start = act_ } else .{ .single = act_ } };
    }

    pub fn act(self: Aim) skillbar.Act {
        return switch (self.action) {
            .single, .wall_start => |a| a,
            .wall_end => |w| w.act,
        };
    }

    pub fn anchor(self: Aim) ?mathx.P {
        return switch (self.action) {
            .wall_end => |w| w.at,
            .single, .wall_start => null,
        };
    }

    pub fn askedHere(self: Aim) bool {
        const at = self.asked orelse return false;
        return at.eq(self.mark);
    }

    pub fn chooseStart(self: *Aim) bool {
        const a = switch (self.action) {
            .wall_start => |a| a,
            .single, .wall_end => return false,
        };
        self.action = .{ .wall_end = .{ .act = a, .at = self.mark } };
        return true;
    }
};
