const std = @import("std");
const bow = @import("bow.zig");

pub const COST: i32 = 5;
pub const PIERCES = true;
pub const VERB = "pierces";
pub const DESCRIPTION = std.fmt.comptimePrint("Arrow damage to every foe in a line, out to {d} tiles. Barrels and walls stop it.", .{bow.RANGE});

test "a piercing arrow names its full reach" {
    try std.testing.expect(std.mem.indexOf(u8, DESCRIPTION, std.fmt.comptimePrint("{d} tiles", .{bow.RANGE})) != null);
    std.debug.print("piercing shot: {d}-tile reach, {d} mana\n", .{ bow.RANGE, COST });
}
