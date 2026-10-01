const std = @import("std");
const input = @import("../core/input.zig");

const Button = input.Button;

pub const Act = enum {
    shoot,
    wait,
    secondary,

    pub fn name(a: Act) [:0]const u8 {
        return switch (a) {
            .shoot => "Shoot",
            .wait => "Wait",
            .secondary => "Activate Secondary Skill Set",
        };
    }

    pub fn desc(a: Act) [:0]const u8 {
        return switch (a) {
            .shoot => "Aim an arrow at a target in range; press again to loose it.",
            .wait => "Let a turn pass.",
            .secondary => "Hold to use Skills in your Secondary Skill Set. Takes up this slot in both Skill Sets.",
        };
    }
};

pub const ACTS = std.enums.values(Act);

pub const Set = enum {
    primary,
    secondary,

    pub fn name(s: Set) [:0]const u8 {
        return switch (s) {
            .primary => "Primary Skill Set",
            .secondary => "Secondary Skill Set",
        };
    }
};

pub const SETS = std.enums.values(Set);

/// PoE2's bind screen groups, less LT and the d-pad, which lean and move here.
pub const GROUPS = [_][]const Button{ &.{.lb}, &.{ .a, .x, .y, .b }, &.{ .rb, .rt } };

pub const SLOTS = blk: {
    var s: []const Button = &.{};
    for (GROUPS) |g| s = s ++ g;
    break :blk s[0..s.len].*;
};

pub const Slot = struct { set: Set, button: Button };

const Row = std.EnumArray(Button, ?Act);

pub const Bar = struct {
    set: std.EnumArray(Set, Row) = .init(.{ .primary = PRIMARY, .secondary = .initFill(null) }),
    modifier: ?Button = .lb,

    pub fn at(self: Bar, s: Slot) ?Act {
        if (self.modifier == s.button) return .secondary;
        return self.set.get(s.set).get(s.button);
    }

    pub fn active(self: Bar, down: std.EnumSet(Button)) Set {
        const m = self.modifier orelse return .primary;
        return if (down.contains(m)) .secondary else .primary;
    }

    /// The secondary set's modifier moves by swapping whole columns, so no binding is lost to it.
    pub fn bind(self: *Bar, s: Slot, a: Act) void {
        if (a == .secondary) {
            if (self.modifier) |m| {
                self.swapColumns(m, s.button);
            } else {
                for (&self.set.values) |*row| row.set(s.button, null);
            }
            self.modifier = s.button;
            return;
        }
        if (self.modifier == s.button) self.modifier = null;
        self.set.getPtr(s.set).set(s.button, a);
    }

    pub fn clear(self: *Bar, s: Slot) void {
        if (self.modifier == s.button) {
            self.modifier = null;
            return;
        }
        self.set.getPtr(s.set).set(s.button, null);
    }

    pub fn swap(self: *Bar, from: Slot, to: Slot) void {
        if (from.set == to.set and from.button == to.button) return;
        if (self.modifier == from.button or self.modifier == to.button) {
            const m = self.modifier.?;
            const other = if (m == from.button) to.button else from.button;
            self.swapColumns(m, other);
            self.modifier = other;
            return;
        }
        const a = self.at(from);
        self.set.getPtr(from.set).set(from.button, self.at(to));
        self.set.getPtr(to.set).set(to.button, a);
    }

    fn swapColumns(self: *Bar, p: Button, q: Button) void {
        for (&self.set.values) |*row| {
            const a = row.get(p);
            row.set(p, row.get(q));
            row.set(q, a);
        }
    }
};

const PRIMARY = blk: {
    var r = Row.initFill(null);
    r.set(.x, .shoot);
    r.set(.b, .wait);
    break :blk r;
};

/// The buttons that open the bind screen and the pause menu, which no skill takes.
const NOT_SLOTS = [_]Button{ .view, .pause };

comptime {
    for (std.enums.values(Button)) |b| {
        var n: usize = 0;
        for (SLOTS ++ NOT_SLOTS) |s| {
            if (s == b) n += 1;
        }
        std.debug.assert(n == 1);
    }
}

test "the bar starts with Shoot on X, Wait on B and the secondary set held on LB" {
    const bar = Bar{};
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .primary, .button = .x }));
    try std.testing.expectEqual(@as(?Act, .wait), bar.at(.{ .set = .primary, .button = .b }));
    try std.testing.expectEqual(@as(?Act, .secondary), bar.at(.{ .set = .secondary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, null), bar.at(.{ .set = .secondary, .button = .x }));
    var down = std.EnumSet(Button).initEmpty();
    try std.testing.expectEqual(Set.primary, bar.active(down));
    down.insert(.lb);
    try std.testing.expectEqual(Set.secondary, bar.active(down));
}

test "moving the secondary set's modifier carries off whatever sat on its new button, in both sets" {
    var bar = Bar{};
    bar.bind(.{ .set = .secondary, .button = .rb }, .shoot);
    bar.bind(.{ .set = .primary, .button = .rb }, .wait);
    bar.bind(.{ .set = .primary, .button = .rb }, .secondary);
    try std.testing.expectEqual(@as(?Button, .rb), bar.modifier);
    try std.testing.expectEqual(@as(?Act, .wait), bar.at(.{ .set = .primary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .secondary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .secondary), bar.at(.{ .set = .secondary, .button = .rb }));
}

test "a skill bound over the modifier unbinds it, and removing a slot empties it" {
    var bar = Bar{};
    bar.bind(.{ .set = .primary, .button = .lb }, .shoot);
    try std.testing.expectEqual(@as(?Button, null), bar.modifier);
    try std.testing.expectEqual(Set.primary, bar.active(std.EnumSet(Button).initFull()));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .primary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .primary, .button = .x }));
    bar.clear(.{ .set = .primary, .button = .x });
    try std.testing.expectEqual(@as(?Act, null), bar.at(.{ .set = .primary, .button = .x }));
}

test "picking a slot up and putting it down on another swaps the two, across sets too" {
    var bar = Bar{};
    bar.swap(.{ .set = .primary, .button = .x }, .{ .set = .secondary, .button = .b });
    try std.testing.expectEqual(@as(?Act, null), bar.at(.{ .set = .primary, .button = .x }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .secondary, .button = .b }));
    bar.swap(.{ .set = .primary, .button = .lb }, .{ .set = .secondary, .button = .b });
    try std.testing.expectEqual(@as(?Button, .b), bar.modifier);
    try std.testing.expectEqual(@as(?Act, .wait), bar.at(.{ .set = .primary, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = .secondary, .button = .lb }));
}
