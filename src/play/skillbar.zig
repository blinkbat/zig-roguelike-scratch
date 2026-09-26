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

pub const SETS: usize = 2;
pub const SET_NAMES = [SETS][:0]const u8{ "Primary Skill Set", "Secondary Skill Set" };

/// PoE2's bind screen groups, less LT and the d-pad, which lean and move here.
pub const GROUPS = [_][]const Button{ &.{.lb}, &.{ .a, .x, .y, .b }, &.{ .rb, .rt } };

pub const SLOTS = blk: {
    var s: []const Button = &.{};
    for (GROUPS) |g| s = s ++ g;
    break :blk s[0..s.len].*;
};

pub const Slot = struct { set: usize, button: Button };

const Row = std.EnumArray(Button, ?Act);

pub const Bar = struct {
    set: [SETS]Row = .{ PRIMARY, .initFill(null) },
    modifier: ?Button = .lb,

    pub fn at(self: Bar, s: Slot) ?Act {
        if (self.modifier == s.button) return .secondary;
        return self.set[s.set].get(s.button);
    }

    pub fn active(self: Bar, down: std.EnumSet(Button)) usize {
        const m = self.modifier orelse return 0;
        return if (down.contains(m)) 1 else 0;
    }

    /// The secondary set's modifier moves by swapping whole columns, so no binding is lost to it.
    pub fn bind(self: *Bar, s: Slot, a: Act) void {
        if (a == .secondary) {
            if (self.modifier) |m| {
                self.swapColumns(m, s.button);
            } else {
                for (&self.set) |*row| row.set(s.button, null);
            }
            self.modifier = s.button;
            return;
        }
        if (self.modifier == s.button) self.modifier = null;
        self.set[s.set].set(s.button, a);
    }

    pub fn clear(self: *Bar, s: Slot) void {
        if (self.modifier == s.button) {
            self.modifier = null;
            return;
        }
        self.set[s.set].set(s.button, null);
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
        const a = self.set[from.set].get(from.button);
        self.set[from.set].set(from.button, self.set[to.set].get(to.button));
        self.set[to.set].set(to.button, a);
    }

    fn swapColumns(self: *Bar, p: Button, q: Button) void {
        for (&self.set) |*row| {
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

comptime {
    for (SLOTS, 0..) |a, i| {
        for (SLOTS[i + 1 ..]) |b| std.debug.assert(a != b);
        std.debug.assert(a != .view);
    }
}

test "the bar starts with Shoot on X, Wait on B and the secondary set held on LB" {
    const bar = Bar{};
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = 0, .button = .x }));
    try std.testing.expectEqual(@as(?Act, .wait), bar.at(.{ .set = 0, .button = .b }));
    try std.testing.expectEqual(@as(?Act, .secondary), bar.at(.{ .set = 1, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, null), bar.at(.{ .set = 1, .button = .x }));
    var down = std.EnumSet(Button).initEmpty();
    try std.testing.expectEqual(@as(usize, 0), bar.active(down));
    down.insert(.lb);
    try std.testing.expectEqual(@as(usize, 1), bar.active(down));
}

test "moving the secondary set's modifier carries off whatever sat on its new button, in both sets" {
    var bar = Bar{};
    bar.bind(.{ .set = 1, .button = .rb }, .shoot);
    bar.bind(.{ .set = 0, .button = .rb }, .wait);
    bar.bind(.{ .set = 0, .button = .rb }, .secondary);
    try std.testing.expectEqual(@as(?Button, .rb), bar.modifier);
    try std.testing.expectEqual(@as(?Act, .wait), bar.at(.{ .set = 0, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = 1, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .secondary), bar.at(.{ .set = 1, .button = .rb }));
}

test "a skill bound over the modifier unbinds it, and removing a slot empties it" {
    var bar = Bar{};
    bar.bind(.{ .set = 0, .button = .lb }, .shoot);
    try std.testing.expectEqual(@as(?Button, null), bar.modifier);
    try std.testing.expectEqual(@as(usize, 0), bar.active(std.EnumSet(Button).initFull()));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = 0, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = 0, .button = .x }));
    bar.clear(.{ .set = 0, .button = .x });
    try std.testing.expectEqual(@as(?Act, null), bar.at(.{ .set = 0, .button = .x }));
}

test "picking a slot up and putting it down on another swaps the two, across sets too" {
    var bar = Bar{};
    bar.swap(.{ .set = 0, .button = .x }, .{ .set = 1, .button = .b });
    try std.testing.expectEqual(@as(?Act, null), bar.at(.{ .set = 0, .button = .x }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = 1, .button = .b }));
    bar.swap(.{ .set = 0, .button = .lb }, .{ .set = 1, .button = .b });
    try std.testing.expectEqual(@as(?Button, .b), bar.modifier);
    try std.testing.expectEqual(@as(?Act, .wait), bar.at(.{ .set = 0, .button = .lb }));
    try std.testing.expectEqual(@as(?Act, .shoot), bar.at(.{ .set = 1, .button = .lb }));
}
