const std = @import("std");
const actor = @import("actor.zig");
const wording = @import("../core/wording.zig");
const cleave = @import("cleave.zig");
const attr = @import("attrs.zig");

const NUMBERS = [_][]const u8{ "none", "one", "two", "three", "four", "five", "six", "seven", "eight" };

pub const MANA_REGEN: i32 = 1;
pub const MANA_REGEN_TURNS: i32 = 5;

pub fn manaRegen(perks: @import("passives.zig").Perks) i32 {
    return MANA_REGEN + perks.mana_regen;
}
/// Hp then most hp, as a save slot reads it.
pub const HP_FMT = "HP {d}/{d}";
pub const GOLD_FMT = "Gold {d}";

pub const Class = enum {
    archer,
    wizard,
    knight,

    pub fn title(c: Class) [:0]const u8 {
        return wording.named(c);
    }

    pub fn unnamed(c: Class) Name {
        return Name.of(c.title());
    }

    pub fn blurb(c: Class) [:0]const u8 {
        return SPECS.getPtrConst(c).blurb;
    }

    pub fn attrs(c: Class) attr.Attrs {
        return SPECS.getPtrConst(c).attrs;
    }

    /// Its bump at a foe beside it.
    pub fn strike(c: Class) actor.Strike {
        return SPECS.getPtrConst(c).strike;
    }

    pub fn kind(c: Class) actor.Kind {
        return switch (c) {
            inline else => |t| @field(actor.Kind, @tagName(t)),
        };
    }
};

const Spec = struct { attrs: attr.Attrs, strike: actor.Strike, blurb: [:0]const u8 };
const SPECS = std.EnumArray(Class, Spec).init(.{
    .archer = .{
        .attrs = .of(.{ .strength = 14, .dexterity = 20, .intelligence = 10 }),
        .strike = .{ .hit = .{ .lo = 1, .hi = 2 }, .verb = "kicks" },
        .blurb = "A bow that reaches what it sees, and a kick for what comes close",
    },
    .wizard = .{
        .attrs = .of(.{ .strength = 8, .dexterity = 10, .intelligence = 20 }),
        .strike = .{ .hit = .{ .lo = 1, .hi = 2 }, .verb = "bonks" },
        .blurb = "Sparks that stun what they strike, and a blink to be elsewhere",
    },
    .knight = .{
        .attrs = blk: {
            var a = attr.Attrs.of(.{ .strength = 24, .dexterity = 10, .intelligence = 10 });
            a.armour = 10;
            break :blk a;
        },
        .strike = .{ .hit = .{ .lo = 3, .hi = 5 }, .verb = "slashes" },
        .blurb = std.fmt.comptimePrint("A shield that knocks foes back stunned, and a blade that sweeps {s} at once", .{NUMBERS[cleave.WIDTH]}),
    },
});

pub const CLASSES = std.enums.values(Class);
pub const DEFAULT: Class = @field(Class, @tagName(actor.HERO));

pub const Name = struct {
    pub const MAX: usize = 16;
    buf: [MAX]u8 = undefined,
    n: usize = 0,

    pub fn of(s: []const u8) Name {
        var nm = Name{};
        for (s) |c| _ = nm.push(c);
        return nm;
    }

    pub fn text(self: *const Name) []const u8 {
        return self.buf[0..self.n];
    }

    pub fn push(self: *Name, c: u8) bool {
        const word = std.ascii.isAlphanumeric(c) or c == '-' or c == '\'';
        const gap = c == ' ' and self.n > 0 and self.buf[self.n - 1] != ' ';
        if (self.n == MAX or !(word or gap)) return false;
        self.buf[self.n] = c;
        self.n += 1;
        return true;
    }

    /// Whether `push` would have spelt it, as a name read from a file must be.
    pub fn valid(self: *const Name) bool {
        return self.n <= MAX and Name.of(self.text()).n == self.n;
    }

    pub fn pop(self: *Name) void {
        self.n -|= 1;
    }

    pub fn done(self: *const Name) Name {
        var nm = self.*;
        while (nm.n > 0 and nm.buf[nm.n - 1] == ' ') nm.n -= 1;
        return nm;
    }
};

test "a name takes letters and single spaces, up to its length, and ends on no space" {
    var nm = Name{};
    for ("  Ar wen!!  the Bold and Brave") |c| _ = nm.push(c);
    try std.testing.expectEqualStrings("Ar wen the Bold ", nm.text());
    try std.testing.expectEqualStrings("Ar wen the Bold", nm.done().text());
    try std.testing.expectEqualStrings("O'Neil-Ray", Name.of("O'Neil-Ray").text());
    try std.testing.expect(nm.valid());
    nm.buf[1] = '!';
    try std.testing.expect(!nm.valid());
}
