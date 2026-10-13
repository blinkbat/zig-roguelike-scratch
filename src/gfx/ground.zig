const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const look = @import("look.zig");

// The ground drawn on a dual grid: a piece sits on each point where four cells meet, its mask the corners round it
// that hold its ground (NW 1, NE 2, SW 4, SE 8). Grounds stack in `Ground`'s order, each over the ones before it,
// so a ground's 16 pieces meet every ground below it and no pair needs its own set. Nothing in the simulation reads it.

const P = mathx.P;

/// Lowest first: each lies over those before it, so its own edges are the ones drawn where two meet.
pub const Ground = enum {
    water,
    dirt,
    grass,
    cobble,

    /// The Desktop template, `<name>.aseprite`, exported to `assets/<name>-ground.png`.
    pub fn png(comptime g: Ground) []const u8 {
        return @tagName(g) ++ "-ground.png";
    }
};

pub const Grounds = std.EnumSet(Ground);

/// The ground a cell shows, from the tile drawn at its foot (`look.under`, else its own).
pub fn of(t: grid.Tile) ?Ground {
    return switch (t) {
        .water => .water,
        .dirt => .dirt,
        .grass => .grass,
        .floor => .cobble,
        else => null,
    };
}

pub const NW: u4 = 1;
pub const NE: u4 = 2;
pub const SW: u4 = 4;
pub const SE: u4 = 8;
pub const FULL: u4 = NW | NE | SW | SE;

/// A ground sheet's 16 cells, read across its 4x4 block, by mask: `tools/tile_art/ground_corners.lua`.
pub const ORDER = [16]u4{ 9, 12, 4, 8, 10, 15, 13, 14, 6, 11, 7, 3, 5, 2, 1, 0 };
pub const COLS: usize = 4;

/// Where each mask's piece lies in its sheet, cells across and down.
pub const CELL_OF = blk: {
    var at: [16]P = undefined;
    var seen = [_]bool{false} ** 16;
    for (ORDER, 0..) |m, i| {
        std.debug.assert(!seen[m]);
        seen[m] = true;
        at[m] = .{ .x = @intCast(i % COLS), .y = @intCast(i / COLS) };
    }
    break :blk at;
};

comptime {
    for (ORDER, 0..) |m, i| {
        if (i % COLS < COLS - 1) {
            const e = ORDER[i + 1];
            std.debug.assert((m & NE != 0) == (e & NW != 0) and (m & SE != 0) == (e & SW != 0));
        }
        if (i / COLS < COLS - 1) {
            const s = ORDER[i + COLS];
            std.debug.assert((m & SW != 0) == (s & NW != 0) and (m & SE != 0) == (s & NE != 0));
        }
    }
}

/// The four cells round point `c`, which lies at the top-left corner of cell `c`, with their bits.
const AROUND = [4]struct { d: P, bit: u4 }{
    .{ .d = .{ .x = -1, .y = -1 }, .bit = NW },
    .{ .d = .{ .x = 0, .y = -1 }, .bit = NE },
    .{ .d = .{ .x = -1, .y = 0 }, .bit = SW },
    .{ .d = .{ .x = 0, .y = 0 }, .bit = SE },
};

/// What a corner point's cells hold: each one's ground, or none for a ground with no sheet, off the map, or unseen.
pub const Corners = struct {
    ground: [4]?Ground,

    /// `seen_only` leaves out cells never seen, as play draws; the editor draws them all.
    pub fn at(lv: *const grid.Level, c: P, sheets: Grounds, seen_only: bool) Corners {
        var out = Corners{ .ground = @splat(null) };
        for (AROUND, &out.ground) |a, *gr| {
            const q = c.add(a.d);
            if (!grid.Level.inside(q) or (seen_only and !lv.isSeen(q))) continue;
            const g = groundAt(lv, q) orelse continue;
            if (sheets.contains(g)) gr.* = g;
        }
        return out;
    }

    /// `g`'s piece here: the corners holding it or a ground over it, so it runs under them; 0 where `g` is not here.
    pub fn mask(self: Corners, g: Ground) u4 {
        var here = false;
        var m: u4 = 0;
        for (AROUND, self.ground) |a, gr| {
            const other = gr orelse continue;
            if (other == g) here = true;
            if (@intFromEnum(other) >= @intFromEnum(g)) m |= a.bit;
        }
        return if (here) m else 0;
    }
};

/// The cell's ground as drawn: the tile at its foot, or its own.
pub fn groundAt(lv: *const grid.Level, q: P) ?Ground {
    const t = lv.at(q);
    return of(look.under(t) orelse t);
}

test "a corner's pieces stack: each ground covers its own corners and those of every ground over it" {
    var lv = grid.Level.blank();
    @memset(&lv.tile, .grass);
    @memset(&lv.seen, true);
    const all = Grounds.initFull();
    lv.set(.{ .x = 10, .y = 10 }, .water);
    lv.set(.{ .x = 11, .y = 10 }, .dirt);
    lv.set(.{ .x = 10, .y = 11 }, .floor);
    const c = Corners.at(&lv, .{ .x = 11, .y = 11 }, all, true);
    try std.testing.expectEqual(FULL, c.mask(.water));
    try std.testing.expectEqual(NE | SW | SE, c.mask(.dirt));
    try std.testing.expectEqual(SW | SE, c.mask(.grass));
    try std.testing.expectEqual(SW, c.mask(.cobble));
    const plain = Corners.at(&lv, .{ .x = 30, .y = 30 }, all, true);
    try std.testing.expectEqual(FULL, plain.mask(.grass));
    try std.testing.expectEqual(@as(u4, 0), plain.mask(.dirt));
    const no_dirt = Corners.at(&lv, .{ .x = 11, .y = 11 }, Grounds.initMany(&.{ .water, .grass, .cobble }), true);
    try std.testing.expectEqual(NW | SW | SE, no_dirt.mask(.water));
    try std.testing.expectEqual(@as(u4, 0), no_dirt.mask(.dirt));
    lv.seen[grid.Level.idx(.{ .x = 11, .y = 11 })] = false;
    const fogged = Corners.at(&lv, .{ .x = 11, .y = 11 }, all, true);
    try std.testing.expectEqual(NW | NE | SW, fogged.mask(.water));
    try std.testing.expectEqual(@as(u4, 0), fogged.mask(.grass));
    const edge = Corners.at(&lv, .{ .x = 0, .y = 0 }, all, true);
    try std.testing.expectEqual(SE, edge.mask(.grass));
    std.debug.print("water, dirt, grass and cobble round one point: masks {d} {d} {d} {d}\n", .{ c.mask(.water), c.mask(.dirt), c.mask(.grass), c.mask(.cobble) });
}

test "under a tree is grass and under a wall cobble, and the sheet's cells match the template's order" {
    var lv = grid.Level.blank();
    lv.set(.{ .x = 3, .y = 3 }, .shrub);
    lv.set(.{ .x = 4, .y = 3 }, .wall);
    lv.set(.{ .x = 5, .y = 3 }, .sand);
    lv.set(.{ .x = 6, .y = 3 }, .rock);
    try std.testing.expectEqual(@as(?Ground, .grass), groundAt(&lv, .{ .x = 3, .y = 3 }));
    try std.testing.expectEqual(@as(?Ground, .cobble), groundAt(&lv, .{ .x = 4, .y = 3 }));
    try std.testing.expectEqual(@as(?Ground, null), groundAt(&lv, .{ .x = 5, .y = 3 }));
    try std.testing.expectEqual(@as(?Ground, null), groundAt(&lv, .{ .x = 6, .y = 3 }));
    const alloc = std.testing.allocator;
    const lua = try std.fs.cwd().readFileAlloc(alloc, "tools/tile_art/ground_corners.lua", 4096);
    defer alloc.free(lua);
    const list = lua[(std.mem.indexOf(u8, lua, "return {") orelse return error.NoList) + "return {".len ..];
    var nums = std.mem.tokenizeAny(u8, list[0 .. std.mem.indexOfScalar(u8, list, '}') orelse return error.NoList], ", \r\n");
    var n: usize = 0;
    while (nums.next()) |m| : (n += 1) try std.testing.expectEqual(ORDER[n], try std.fmt.parseInt(u4, m, 10));
    try std.testing.expectEqual(ORDER.len, n);
    try std.testing.expectEqual(P{ .x = 1, .y = 1 }, CELL_OF[FULL]);
}
