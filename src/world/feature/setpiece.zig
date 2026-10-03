const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");
const buildings = @import("buildings.zig");

// Diablo II's outdoor presets and Burial Grounds, Path of Exile's Cemetery.

const P = mathx.P;

pub const COUNT_MAX: u8 = 8;
pub const APART_MAX: u8 = 30;

pub const Piece = enum { circle, cairns, camp, graveyard, well, tower, shrine, corral, oasis };

/// In `grid.Tile.letter`'s legend; ' ' leaves the ground as it is.
fn key(c: u8) ?grid.Tile {
    return if (c == grid.BARREL_LETTER) .floor else grid.Tile.ofLetter(c);
}

pub fn rows(p: Piece) []const []const u8 {
    return switch (p) {
        .circle => &.{
            "  % %  ",
            " %,,,% ",
            "%,,,,,%",
            " ,,%,, ",
            "%,,,,,%",
            " %,,,% ",
            "  % %  ",
        },
        .cairns => &.{
            " %   % ",
            "   ,   ",
            "% ,,, %",
            "  , ,  ",
            "   %   ",
        },
        .camp => &.{
            " +++++ ",
            "+,,,,,+",
            "+,,!,,+",
            "+,0,,, ",
            " +++++ ",
        },
        .graveyard => &.{
            "+++++++++++",
            "+,,,,,,,,,+",
            "+,t,t,t,t,+",
            "+,,,,,,,,,+",
            "+,t,t,t,t,+",
            "+,,,,,,,,,+",
            "+,t,t,t,t,+",
            "+,,,,,,,,,+",
            "+++++,+++++",
        },
        .well => &.{
            " ,,, ",
            ",#-#,",
            ",-~-,",
            ",#-#,",
            " ,,, ",
        },
        .tower => &.{
            "  ###  ",
            " #...# ",
            "#.....#",
            "#..0..#",
            "#.....#",
            " #...# ",
            "  #.#  ",
        },
        .shrine => &.{
            "#####",
            "#...#",
            "#.0.#",
            "#...#",
            "##.##",
        },
        .corral => &.{
            "+++++++",
            "+\"\"\"\"\"+",
            "+\"\"\"\"\"+",
            "+\"\"\"\"\"+",
            "+++\"+++",
        },
        .oasis => &.{
            "  & &  ",
            " &---& ",
            "&-~~~-&",
            " -~~~- ",
            "&-~~~-&",
            " &---& ",
            "  & &  ",
        },
    };
}

pub const Params = struct {
    piece: Piece = .circle,
    count: u8 = 2,
    /// Cells of margin round each, clear of the others.
    apart: u8 = 6,

    pub fn fit(p: Params) Params {
        return .{ .piece = p.piece, .count = std.math.clamp(p.count, 1, COUNT_MAX), .apart = @min(p.apart, APART_MAX) };
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, _: carve.Palette, p: Params) void {
    const art = rows(p.piece);
    const w = size(art).x;
    const h = size(art).y;
    const pad: i32 = p.apart;
    var taken: [COUNT_MAX]buildings.Box = undefined;
    var n: usize = 0;
    for (0..p.count) |_| {
        const room = buildings.site(lv, rng, w + 2 * pad, h + 2 * pad, taken[0..n]) orelse
            buildings.site(lv, rng, w, h, taken[0..n]) orelse continue;
        taken[n] = room;
        n += 1;
        const at = P{ .x = @divTrunc(room.lo.x + room.hi.x - w, 2), .y = @divTrunc(room.lo.y + room.hi.y - h, 2) };
        stamp(lv, at, art);
    }
}

/// Cells across and down.
pub fn size(art: []const []const u8) P {
    return .{ .x = @intCast(art[0].len), .y = @intCast(art.len) };
}

/// `stamp`ed with its middle on `mid`.
pub fn stampAround(lv: *grid.Level, mid: P, art: []const []const u8) void {
    const s = size(art);
    stamp(lv, mid.sub(.{ .x = @divTrunc(s.x, 2), .y = @divTrunc(s.y, 2) }), art);
}

pub fn stamp(lv: *grid.Level, at: P, art: []const []const u8) void {
    for (art, 0..) |line, y| {
        for (line, 0..) |c, x| {
            const q = at.add(.{ .x = @intCast(x), .y = @intCast(y) });
            if (grid.Level.onRim(q)) continue;
            lv.set(q, key(c) orelse continue);
            if (c == grid.BARREL_LETTER) lv.putBarrel(q);
        }
    }
}

test "every piece is a rectangle of known keys" {
    for (std.enums.values(Piece)) |pc| {
        const art = rows(pc);
        for (art) |line| {
            try std.testing.expectEqual(art[0].len, line.len);
            for (line) |c| try std.testing.expect(c == ' ' or key(c) != null);
        }
    }
}

test "pieces land apart on open ground" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x5E7);
    carve.fill(&lv, .grass);
    carve.rim(&lv, .shrub);
    apply(&lv, &rng, 0, carve.Palette.WILD, .{ .piece = .graveyard, .count = 3 });
    std.debug.print("3 graveyards: {d} graves\n", .{carve.count(&lv, .grave)});
    try std.testing.expectEqual(@as(usize, 3 * 12), carve.count(&lv, .grave));
}
