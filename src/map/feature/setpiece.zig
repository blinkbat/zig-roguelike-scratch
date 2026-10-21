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

/// In `grid.groundOf`'s legend; ' ' leaves the ground as it is.
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
            "+,0,,,,",
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
        var q = p;
        q.count = std.math.clamp(p.count, 1, COUNT_MAX);
        q.apart = @min(p.apart, APART_MAX);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, pal: carve.Palette, lots: *buildings.Lots, p: Params) void {
    const art = rows(p.piece);
    const w = size(art).x;
    const h = size(art).y;
    for (0..p.count) |_| {
        const room = spaced(lots, lv, rng, w, h, p.apart, pal) orelse continue;
        place(lv, room.lo, art, pal);
    }
}

fn spaced(lots: *buildings.Lots, lv: *const grid.Level, rng: *mathx.Rng, w: i32, h: i32, apart: i32, pal: carve.Palette) ?grid.Box {
    const least = buildings.Lots.GAP;
    var gap = @max(least, 2 * apart);
    while (true) : (gap = @divTrunc(gap, 2)) {
        if (lots.takeApart(lv, rng, w, h, gap, pal)) |r| return r;
        if (gap <= least) return null;
    }
}

/// Stamped, its gaps and the ring round it opened, so no thicket or rock seals its ground in.
pub fn place(lv: *grid.Level, at: P, art: []const []const u8, pal: carve.Palette) void {
    stampOver(lv, at, art, pal);
    carve.clearRound(lv, grid.Box.sized(at, size(art).x, size(art).y), pal);
}

pub fn size(art: []const []const u8) P {
    return .{ .x = @intCast(art[0].len), .y = @intCast(art.len) };
}

pub fn cornerFor(mid: P, art: []const []const u8) P {
    const s = size(art);
    return mid.sub(.{ .x = @divTrunc(s.x, 2), .y = @divTrunc(s.y, 2) });
}

pub fn stampAround(lv: *grid.Level, mid: P, art: []const []const u8) void {
    stamp(lv, cornerFor(mid, art), art);
}

pub fn stamp(lv: *grid.Level, at: P, art: []const []const u8) void {
    stampOver(lv, at, art, null);
}

/// With `open`, a ' ' gap is opened where what stands there would close it.
fn stampOver(lv: *grid.Level, at: P, art: []const []const u8, open: ?carve.Palette) void {
    var it = Spots{ .at = at, .art = art };
    while (it.next()) |s| {
        if (grid.Level.onRim(s.q)) continue;
        if (grid.groundOf(s.c)) |t| {
            lv.set(s.q, t);
            if (s.c == grid.BARREL_LETTER) lv.putBarrel(s.q);
        } else if (open) |pal| {
            if (carve.closes(lv.at(s.q), pal)) lv.set(s.q, pal.open);
        }
    }
}

/// Each cell of `art` laid with its top left at `at`, and its letter.
pub const Spots = struct {
    at: P,
    art: []const []const u8,
    x: usize = 0,
    y: usize = 0,

    pub fn next(s: *Spots) ?struct { q: P, c: u8 } {
        if (s.y == s.art.len) return null;
        const q = s.at.add(.{ .x = @intCast(s.x), .y = @intCast(s.y) });
        const c = s.art[s.y][s.x];
        s.x += 1;
        if (s.x == s.art[s.y].len) {
            s.x = 0;
            s.y += 1;
        }
        return .{ .q = q, .c = c };
    }
};

test "every piece is a rectangle of known keys" {
    for (std.enums.values(Piece)) |pc| {
        const art = rows(pc);
        for (art) |line| {
            try std.testing.expectEqual(art[0].len, line.len);
            for (line) |c| try std.testing.expect(c == ' ' or grid.groundOf(c) != null);
        }
    }
}

test "pieces land apart on open ground" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x5E7);
    carve.field(&lv, carve.Palette.WILD);
    var lots: buildings.Lots = .{};
    apply(&lv, &rng, 0, carve.Palette.WILD, &lots, .{ .piece = .graveyard, .count = 3 });
    std.debug.print("3 graveyards: {d} graves\n", .{carve.count(&lv, .grave)});
    try std.testing.expectEqual(@as(usize, 3 * 12), carve.count(&lv, .grave));
}

test "shrines set wide apart land no closer than at the default margin" {
    var default: i32 = 0;
    std.debug.print("the nearest two of 3 shrines in 50 maps by apart:", .{});
    for ([_]u8{ 0, 6, 20, APART_MAX }) |apart| {
        var nearest: i32 = std.math.maxInt(i32);
        for (0..50) |seed| {
            var lv = grid.Level.blank();
            var rng = mathx.Rng.init(0x5E7 +% seed *% grid.TEST_SEED_STRIDE);
            carve.field(&lv, carve.Palette.WILD);
            var lots: buildings.Lots = .{};
            apply(&lv, &rng, 0, carve.Palette.WILD, &lots, (Params{ .piece = .shrine, .count = 3, .apart = apart }).fit());
            var at: [3]P = undefined;
            var n: usize = 0;
            for (lv.barrel, 0..) |b, i| {
                if (!b) continue;
                at[n] = grid.Level.of(i);
                n += 1;
            }
            for (at[0..n], 0..) |a, i| {
                for (at[i + 1 .. n]) |b| nearest = @min(nearest, mathx.dist(a, b));
            }
        }
        std.debug.print(" {d}:{d}", .{ apart, nearest });
        if (apart == (Params{}).apart) default = nearest;
        if (apart > (Params{}).apart) try std.testing.expect(nearest >= default);
    }
    std.debug.print("\n", .{});
}
