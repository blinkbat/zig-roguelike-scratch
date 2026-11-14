const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const damage = @import("damage.zig");
const glacial = @import("glacial.zig");
const areas = @import("area.zig");
const resilience = @import("resilience.zig");

const P = mathx.P;

pub const Kind = enum { bandage, smelling_salts, frost_vial };
pub const KINDS = std.enums.values(Kind);
pub const STACK_MAX: u8 = 20;
pub const Stacks = std.EnumArray(Kind, u8);

pub fn stocked(s: *const Stacks) usize {
    var n: usize = 0;
    for (KINDS) |k| n += @intFromBool(s.get(k) > 0);
    return n;
}

pub fn mend(s: *Stacks) void {
    for (&s.values) |*n| n.* = @min(n.*, STACK_MAX);
}

pub fn stock(s: *Stacks, k: Kind) bool {
    const n = s.getPtr(k);
    if (n.* >= STACK_MAX) return false;
    n.* += 1;
    return true;
}

pub fn stockedAt(s: *const Stacks, row: usize) ?Kind {
    var left = row;
    for (KINDS) |k| if (s.get(k) > 0) {
        if (left == 0) return k;
        left -= 1;
    };
    return null;
}

pub fn roll(rng: *mathx.Rng, percent: u32) ?Kind {
    return if (rng.percent(percent)) rng.pick(Kind, KINDS) else null;
}

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
    pub const BOLT_RANGE: i32 = 4;
    pub const TAKES = glacial.TAKES;
    pub const ELEMENT = glacial.ELEMENT;
    pub const BASE = damage.Base{ .lo = 1, .hi = 3 };
    pub const CHANCE = glacial.CHANCE;
    pub const procs = glacial.procs;
    pub const chance = glacial.chance;
    pub const afflict = glacial.afflict;
    pub const AILMENT = glacial.AILMENT;
    pub const DESCRIPTION = std.fmt.comptimePrint("A thrown vial shatters into cold, hitting every foe within {d} tile{s}. {s}.", .{ BLAST, mathx.plural(BLAST), glacial.CHILL_NOTE });

    pub const burst = areas.Patch(BLAST).burst;
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
}

test "a frost vial's splash takes the cell it strikes and the eight round it, but not past a wall" {
    var lv = grid.openFloor();
    const at = P{ .x = 20, .y = 20 };
    const open: usize = @intCast(grid.Cells.square(FrostVial.BLAST));
    try std.testing.expectEqual(open, FrostVial.burst(&lv, .{ .x = 14, .y = 20 }, at, 0).n);
    lv.set(.{ .x = 21, .y = 20 }, .wall);
    try std.testing.expect(!FrostVial.burst(&lv, .{ .x = 14, .y = 20 }, at, 0).has(.{ .x = 21, .y = 20 }));
}
