const std = @import("std");
const actor = @import("actor.zig");
const menu = @import("../ui/menu.zig");
const cleave = @import("cleave.zig");

const NUMBERS = [_][]const u8{ "none", "one", "two", "three", "four", "five", "six", "seven", "eight" };

pub const MANA: i32 = 100;
pub const MANA_REGEN: i32 = 1;
/// Hp then most hp, as a save slot reads it.
pub const HP_FMT = "HP {d}/{d}";
pub const GOLD_FMT = "Gold {d}";

pub const Class = enum {
    archer,
    wizard,
    knight,

    pub fn title(c: Class) [:0]const u8 {
        return menu.named(c);
    }

    pub fn unnamed(c: Class) Name {
        return Name.of(c.title());
    }

    pub fn blurb(c: Class) [:0]const u8 {
        return switch (c) {
            .archer => "A bow that reaches what it sees, and a kick for what comes close",
            .wizard => "Sparks that stun what they strike, and a blink to be elsewhere",
            .knight => std.fmt.comptimePrint("A shield that knocks foes back stunned, and a blade that sweeps {s} at once", .{NUMBERS[cleave.WIDTH]}),
        };
    }

    pub fn kind(c: Class) actor.Kind {
        return switch (c) {
            inline else => |t| @field(actor.Kind, @tagName(t)),
        };
    }
};

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
