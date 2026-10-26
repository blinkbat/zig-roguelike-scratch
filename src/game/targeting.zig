const std = @import("std");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const skillbar = @import("../play/skillbar.zig");

pub const Aim = struct {
    by: input.Button,
    set: skillbar.Set = .primary,
    mark: mathx.P,
    action: union(enum) { single: skillbar.Act, wall_start, wall_end: mathx.P },

    pub fn of(by: input.Button, act_: skillbar.Act, mark: mathx.P) Aim {
        std.debug.assert(act_.reticle() != null);
        return .{ .by = by, .mark = mark, .action = if (act_ == .arcane_barrier) .wall_start else .{ .single = act_ } };
    }

    pub fn act(self: Aim) skillbar.Act {
        return switch (self.action) {
            .single => |a| a,
            .wall_start, .wall_end => .arcane_barrier,
        };
    }

    pub fn anchor(self: Aim) ?mathx.P {
        return switch (self.action) {
            .wall_end => |at| at,
            .single, .wall_start => null,
        };
    }

    pub fn chooseStart(self: *Aim) bool {
        if (self.action != .wall_start) return false;
        self.action = .{ .wall_end = self.mark };
        return true;
    }
};
