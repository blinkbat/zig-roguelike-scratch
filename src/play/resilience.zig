const std = @import("std");
const mathx = @import("../core/mathx.zig");

pub const Kind = enum { stun, burn, bleed, chill, pin };
pub const GAIN: u8 = 25;
pub const EXPIRY: u8 = 5;
pub const ABOUT = std.fmt.comptimePrint("Repeated harmful statuses build resistance. Each successful application adds {d}%; it expires after {d} turns without another successful application.", .{ GAIN, EXPIRY });

pub const Meter = struct {
    percent: u8 = 0,
    turns: u8 = 0,
    fresh: bool = false,
};

/// A body's resistance to a status as shown, and the turns before its built-up part expires.
pub const Standing = struct {
    percent: i16 = 0,
    turns: u8 = 0,
};

pub const State = struct {
    meters: std.EnumArray(Kind, Meter) = .initFill(.{}),

    pub fn peak(self: State) Standing {
        var out = Standing{};
        for (self.meters.values) |m| {
            out.percent = @max(out.percent, m.percent);
            out.turns = @max(out.turns, m.turns);
        }
        return out;
    }

    pub fn resistance(self: State, kind: Kind, innate: u8) u32 {
        return @min(mathx.PERCENT, @as(u32, innate) + self.meters.get(kind).percent);
    }

    /// Its whole resistance to `kind`, innate included.
    pub fn standing(self: State, kind: Kind, innate: u8) Standing {
        return .{ .percent = @intCast(self.resistance(kind, innate)), .turns = self.meters.get(kind).turns };
    }

    pub fn take(self: *State, kind: Kind, innate: u8, rng: *mathx.Rng) bool {
        return self.takeResisted(kind, @intCast(self.resistance(kind, innate)), rng);
    }

    pub fn takeResisted(self: *State, kind: Kind, resist: i16, rng: *mathx.Rng) bool {
        if (resist >= mathx.PERCENT or (resist > 0 and rng.percent(@intCast(resist)))) return false;
        const meter = self.meters.getPtr(kind);
        meter.* = .{ .percent = @min(mathx.PERCENT, meter.percent + GAIN), .turns = EXPIRY, .fresh = true };
        return true;
    }

    pub fn settle(self: *State) void {
        for (&self.meters.values) |*m| {
            if (m.fresh) {
                m.fresh = false;
            } else {
                m.turns -|= 1;
                if (m.turns == 0) m.* = .{};
            }
        }
    }
};

test "status buildup is independent, blocks repeated applications and expires on spent turns" {
    var rng = mathx.Rng.init(0xAE51);
    var s = State{};
    for (std.enums.values(Kind)) |kind| {
        var landed: usize = 0;
        for (0..1000) |_| landed += @intFromBool(s.take(kind, 0, &rng));
        try std.testing.expectEqual(@as(usize, mathx.PERCENT / GAIN), landed);
        try std.testing.expectEqual(@as(u32, mathx.PERCENT), s.resistance(kind, 0));
    }
    s.settle();
    for (0..EXPIRY - 1) |_| s.settle();
    try std.testing.expectEqual(@as(u32, 100), s.resistance(.stun, 0));
    s.settle();
    try std.testing.expectEqual(@as(u32, 0), s.resistance(.stun, 0));
    var successes: usize = 0;
    for (0..1000) |_| successes += @intFromBool(s.take(.stun, 75, &rng));
    try std.testing.expectEqual(@as(usize, 1), successes);
    try std.testing.expectEqual(@as(u32, 0), s.resistance(.bleed, 0));
    std.debug.print("resilience: {d} independent meters, {d} successes before immunity; innate 75% needs 1, expiry {d} turns\n", .{ std.enums.values(Kind).len, mathx.PERCENT / GAIN, EXPIRY });
}

test "failed status applications preserve expiry freshness and all other meters" {
    var accepted: usize = 0;
    var refused: usize = 0;
    for (std.enums.values(Kind)) |kind| {
        for (0..128) |seed| {
            var s = State{};
            s.meters.set(kind, .{ .percent = GAIN, .turns = 2 });
            var rng = mathx.Rng.init(seed);
            var want = s;
            if (s.take(kind, 0, &rng)) {
                accepted += 1;
                want.meters.set(kind, .{ .percent = GAIN * 2, .turns = EXPIRY, .fresh = true });
            } else refused += 1;
            try std.testing.expectEqualDeep(want, s);
        }
    }
    try std.testing.expect(accepted > 0 and refused > 0);
    std.debug.print("status retry atomicity: {d} accepted and {d} resisted applications across all {d} meters\n", .{ accepted, refused, std.enums.values(Kind).len });
}

test "certain status outcomes draw no RNG and immunity expires without failed retries extending it" {
    for (std.enums.values(Kind)) |kind| {
        var rng = mathx.Rng.init(51);
        const before = rng;
        var s = State{};
        try std.testing.expect(s.take(kind, 0, &rng));
        try std.testing.expectEqualDeep(before, rng);
        s.meters.set(kind, .{ .percent = mathx.PERCENT, .turns = 2 });
        const immune = s;
        try std.testing.expect(!s.take(kind, 0, &rng));
        try std.testing.expectEqualDeep(immune, s);
        try std.testing.expectEqualDeep(before, rng);
        s.settle();
        try std.testing.expectEqual(@as(u8, 1), s.meters.get(kind).turns);
        try std.testing.expect(!s.take(kind, 0, &rng));
        s.settle();
        try std.testing.expectEqualDeep(State{}, s);
        try std.testing.expect(!s.take(kind, mathx.PERCENT, &rng));
        try std.testing.expectEqualDeep(State{}, s);
        try std.testing.expectEqualDeep(before, rng);
        try std.testing.expect(s.take(kind, 0, &rng));
        s.settle();
        try std.testing.expectEqual(EXPIRY, s.meters.get(kind).turns);
        try std.testing.expect(!s.meters.get(kind).fresh);
        s.settle();
        try std.testing.expectEqual(EXPIRY - 1, s.meters.get(kind).turns);
    }
    std.debug.print("status lifetime: {d} meters check no-draw certainty, innate immunity, failed retries, exact expiry and one fresh-turn exemption\n", .{std.enums.values(Kind).len});
}
