const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const glacial = @import("glacial.zig");
const resilience = @import("resilience.zig");

const P = mathx.P;

pub const Kind = enum { bandage, smelling_salts, frost_vial };
pub const KINDS = std.enums.values(Kind);
/// The most of one kind the bag carries.
pub const STACK_MAX: u8 = 20;
pub const FOE_PERCENT = 8;
pub const CHEST_PERCENT = 50;

/// One of any kind, `percent` of the time.
pub fn roll(rng: *mathx.Rng, percent: u32) ?Kind {
    return if (rng.percent(percent)) rng.pick(Kind, KINDS) else null;
}

/// As the log names one lying somewhere.
pub fn phrase(k: Kind) []const u8 {
    return switch (k) {
        .bandage => "a bandage",
        .smelling_salts => "smelling salts",
        .frost_vial => "a frost vial",
    };
}

pub const Bandage = struct {
    pub const SUPPLY: Kind = .bandage;
    pub const DONE = "binds a bandage";
    pub const DESCRIPTION = "Stop bleeding.";
};

pub const SmellingSalts = struct {
    pub const SUPPLY: Kind = .smelling_salts;
    pub const TURNS: u8 = 5;
    pub const DONE = "breathes smelling salts";
    pub const DESCRIPTION = std.fmt.comptimePrint("No stun can land for {d} turns.", .{TURNS});

    pub fn steel(r: *resilience.State) void {
        r.immune(.stun, TURNS);
    }
};

pub const FrostVial = struct {
    pub const SUPPLY: Kind = .frost_vial;
    pub const BLAST: i32 = 1;
    pub const VERB = "splashes";
    pub const BOLT = "frost vial";
    pub const TAKES = glacial.TAKES;
    pub const ELEMENT: damage.Element = .cold;
    pub const BASE = damage.Base{ .lo = 1, .hi = 3 };
    pub const CHANCE = glacial.CHANCE;
    pub const procs = glacial.procs;
    pub const chance = glacial.chance;
    pub const afflict = glacial.afflict;
    pub const AILMENT = glacial.AILMENT;
    pub const DESCRIPTION = std.fmt.comptimePrint("A thrown vial shatters into cold, hitting every foe within {d} tile{s}. {s}.", .{ BLAST, mathx.plural(BLAST), glacial.CHILL_NOTE });

    comptime {
        std.debug.assert(BLAST <= glacial.BURST_MAX);
    }

    pub fn burst(lv: *const grid.Level, _: P, impact: P) glacial.Burst {
        return glacial.patch(lv, impact, BLAST);
    }
};

test "smelling salts hold stun resistance full until their turns run out, and leave other meters alone" {
    var r = resilience.State{};
    r.meters.set(.bleed, .{ .percent = resilience.GAIN, .turns = 2 });
    SmellingSalts.steel(&r);
    var rng = mathx.Rng.init(0x5A17);
    r.settle();
    for (0..SmellingSalts.TURNS) |_| {
        try std.testing.expect(!r.take(.stun, 0, &rng));
        r.settle();
    }
    try std.testing.expectEqual(@as(u32, 0), r.resistance(.stun, 0));
    try std.testing.expect(r.take(.stun, 0, &rng));
    try std.testing.expectEqual(@as(u8, 0), r.meters.get(.bleed).turns);
    std.debug.print("smelling salts: {d} turns of full stun resistance after the turn they are used, then stuns land again\n", .{SmellingSalts.TURNS});
}

test "a frost vial's splash takes the cell it strikes and the eight round it, but not past a wall" {
    var lv = grid.openFloor();
    const at = P{ .x = 20, .y = 20 };
    const open: usize = @intCast(grid.Cells.square(FrostVial.BLAST));
    try std.testing.expectEqual(open, FrostVial.burst(&lv, .{ .x = 14, .y = 20 }, at).n);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    try std.testing.expect(!FrostVial.burst(&lv, .{ .x = 14, .y = 20 }, at).has(.{ .x = 21, .y = 20 }));
    std.debug.print("frost vial: a {d}-cell splash on open ground, walls excluded\n", .{open});
}
