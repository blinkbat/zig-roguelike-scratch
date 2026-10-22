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

pub const State = struct {
    meters: std.EnumArray(Kind, Meter) = .initFill(.{}),

    pub fn peak(self: State) Meter {
        var out = Meter{};
        for (self.meters.values) |m| {
            out.percent = @max(out.percent, m.percent);
            out.turns = @max(out.turns, m.turns);
        }
        return out;
    }

    pub fn resistance(self: State, kind: Kind, innate: u8) u32 {
        return @min(100, @as(u32, innate) + self.meters.get(kind).percent);
    }

    pub fn take(self: *State, kind: Kind, innate: u8, rng: *mathx.Rng) bool {
        const resist = self.resistance(kind, innate);
        if (resist >= 100 or (resist > 0 and rng.percent(resist))) return false;
        const meter = self.meters.getPtr(kind);
        meter.* = .{ .percent = @min(100, meter.percent + GAIN), .turns = EXPIRY, .fresh = true };
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
        try std.testing.expectEqual(@as(usize, 4), landed);
        try std.testing.expectEqual(@as(u32, 100), s.resistance(kind, 0));
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
    std.debug.print("resilience: 5 independent meters, 4 successes before immunity; innate 75% needs 1, expiry {d} turns\n", .{EXPIRY});
}
