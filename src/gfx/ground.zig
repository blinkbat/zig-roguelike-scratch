const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const look = @import("look.zig");

// Dual-grid masks use NW 1, NE 2, SW 4, SE 8 and include higher layers.
// Unsheeted grounds draw below sheeted grounds; each group retains Ground order. Presentation only.

const P = mathx.P;

/// Lowest first among the grounds with a sheet, and among those without.
pub const Ground = enum {
    chasm,
    lava,
    water,
    shallows,
    reeds,
    ice,
    snow,
    sand,
    dirt,
    crop,
    grass,
    rubble,
    bridge,
    cobble,

    /// Exported to `assets/<name>-ground.png` by `export_ground.lua`, which names its Desktop source.
    pub fn png(comptime g: Ground) []const u8 {
        return @tagName(g) ++ "-ground.png";
    }

    pub fn tile(g: Ground) grid.Tile {
        return switch (g) {
            .cobble => .floor,
            inline else => |n| @field(grid.Tile, @tagName(n)),
        };
    }

    fn bears(g: Ground) bool {
        return switch (g) {
            .ice, .snow, .sand, .dirt, .grass, .rubble, .cobble => true,
            .chasm, .lava, .water, .shallows, .reeds, .crop, .bridge => false,
        };
    }

    fn rank(g: Ground) u8 {
        return RANK.get(g);
    }

    fn ofRank(r: u8) Ground {
        return BY_RANK[r];
    }
};

pub const Grounds = std.EnumSet(Ground);

const RANKS = std.enums.values(Ground).len + 1;
const Ranks = std.meta.Int(.unsigned, RANKS);

const RANK = blk: {
    var r = std.EnumArray(Ground, u8).initFill(0);
    var n: u8 = 1;
    for ([2]bool{ false, true }) |sheet| {
        for (std.enums.values(Ground)) |g| {
            if (look.GROUND_SHEETS.contains(g) != sheet) continue;
            r.set(g, n);
            n += 1;
        }
    }
    break :blk r;
};

const BY_RANK = blk: {
    var by: [RANKS]Ground = undefined;
    for (std.enums.values(Ground)) |g| by[RANK.get(g)] = g;
    break :blk by;
};

/// Every ground, lowest first, as they draw.
pub const LAYERS: []const Ground = BY_RANK[1..];

pub fn of(t: grid.Tile) ?Ground {
    return switch (t) {
        .floor => .cobble,
        inline else => |n| if (@hasField(Ground, @tagName(n))) @field(Ground, @tagName(n)) else null,
    };
}

comptime {
    for (std.enums.values(grid.Tile)) |t| {
        const over = t.upright() and look.tileBg(t) != null;
        std.debug.assert(@intFromBool(of(t) != null) + @intFromBool(look.under(t) != null) + @intFromBool(over) == 1);
    }
}

/// Under standing tiles, choose the neighbours' majority ground, lowest rank on ties; otherwise `look.under`.
pub fn bedAt(lv: *const grid.Level, p: P) ?Ground {
    const t = lv.at(p);
    if (of(t)) |g| return g;
    const fallback = look.under(t) orelse return null;
    var votes = [_]u8{0} ** RANKS;
    var best = of(fallback).?;
    var most: u8 = 0;
    for (mathx.ALL_DIRS) |d| {
        const g = of(lv.at(p.add(d.delta()))) orelse continue;
        if (!g.bears()) continue;
        const r = g.rank();
        votes[r] += 1;
        const n = votes[r];
        if (n > most or (n == most and r < best.rank())) {
            best = g;
            most = n;
        }
    }
    return best;
}

const NONE: u8 = 0;
const OVER: u8 = std.math.maxInt(u8);

fn isGround(r: u8) bool {
    return r != NONE and r != OVER;
}

/// Cache visible ground ranks and corner points for all layers in a frame.
pub const Beds = struct {
    lo: P,
    hi: P,
    held: Box,
    /// By `slot`: the map and a cell off each edge, so a point's corners are read unchecked.
    rank: [SPAN * (grid.ROWS + 2)]u8,
    shown: Grounds,
    /// The corner points from `lo` to `hi`, both included, row by row.
    point: [grid.CORNERS_W * grid.CORNERS_H]Point,
    across: usize,

    const Box = grid.Box;
    const SPAN: usize = grid.COLS + 2;

    fn slot(p: P) usize {
        return @as(usize, @intCast(p.y + 1)) * SPAN + @as(usize, @intCast(p.x + 1));
    }

    pub const Point = struct {
        corners: Corners,
        /// A bit for each rank among them.
        holds: Ranks,

        pub fn has(self: Point, g: Ground) bool {
            return self.holds & (@as(Ranks, 1) << @intCast(g.rank())) != 0;
        }
    };

    /// `seen_only` leaves out cells never seen, as play draws; the editor draws them all.
    pub fn fill(b: *Beds, lv: *const grid.Level, lo: P, hi: P, seen_only: bool) void {
        b.lo = lo;
        b.hi = hi;
        std.debug.assert(lo.x >= 0 and lo.y >= 0 and hi.x <= grid.W and hi.y <= grid.H);
        b.held = .{ .lo = lo.sub(.{ .x = 1, .y = 1 }), .hi = hi.add(.{ .x = 1, .y = 1 }) };
        b.shown = .initEmpty();
        b.across = @intCast(hi.x - lo.x + 1);
        var cells = b.held.cells();
        while (cells.next()) |p| {
            const s = slot(p);
            b.rank[s] = NONE;
            if (!grid.Level.inside(p)) continue;
            const i = grid.Level.idx(p);
            if (seen_only and !lv.seen[i]) continue;
            const g = bedAt(lv, p) orelse {
                b.rank[s] = OVER;
                continue;
            };
            b.rank[s] = g.rank();
            b.shown.insert(g);
        }
        var corners = b.points();
        var n: usize = 0;
        while (corners.next()) |c| : (n += 1) {
            const se = slot(c);
            const k = Corners{ .rank = .{ b.rank[se - SPAN - 1], b.rank[se - SPAN], b.rank[se - 1], b.rank[se] } };
            var holds: Ranks = 0;
            for (k.rank) |r| {
                if (isGround(r)) holds |= @as(Ranks, 1) << @intCast(r);
            }
            b.point[n] = .{ .corners = k, .holds = holds };
        }
    }

    fn at(self: *const Beds, q: P) u8 {
        std.debug.assert(self.held.holds(q));
        const s = slot(q);
        return self.rank[s];
    }

    pub fn ground(self: *const Beds, p: P) ?Ground {
        const r = self.at(p);
        return if (isGround(r)) Ground.ofRank(r) else null;
    }

    /// Every point from `lo` to `hi`, both included, row by row as `point` holds them.
    pub fn points(self: *const Beds) grid.Cells {
        return grid.Cells.of(self.lo, self.hi.add(.{ .x = 1, .y = 1 }));
    }

    /// Point `c`, from `lo` to `hi`.
    pub fn pointAt(self: *const Beds, c: P) Point {
        const i = @as(usize, @intCast(c.y - self.lo.y)) * self.across + @as(usize, @intCast(c.x - self.lo.x));
        return self.point[i];
    }
};

comptime {
    for (std.enums.values(Ground)) |g| std.debug.assert(of(g.tile()).? == g);
}

pub const NW: u4 = 1;
pub const NE: u4 = 2;
pub const SW: u4 = 4;
pub const SE: u4 = 8;
pub const FULL: u4 = NW | NE | SW | SE;

/// A ground sheet's 16 cells, read across its 4x4 block, by mask: `tools/tile_art/ground_corners.lua`.
pub const ORDER = [MASKS]u4{ 9, 12, 4, 8, 10, 15, 13, 14, 6, 11, 7, 3, 5, 2, 1, 0 };
pub const MASKS: usize = @as(usize, FULL) + 1;
pub const COLS: usize = 4;
pub const ROWS: usize = MASKS / COLS;

/// Where each mask's piece lies in its sheet, cells across and down.
pub const CELL_OF = blk: {
    var at: [MASKS]P = undefined;
    var seen = [_]bool{false} ** MASKS;
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
        if (i / COLS < ROWS - 1) {
            const s = ORDER[i + COLS];
            std.debug.assert((m & SW != 0) == (s & NW != 0) and (m & SE != 0) == (s & NE != 0));
        }
    }
}

/// The four cells round point `c`, which lies at the top-left corner of cell `c`, with their bits.
pub const AROUND = [4]struct { d: P, bit: u4 }{
    .{ .d = .{ .x = -1, .y = -1 }, .bit = NW },
    .{ .d = .{ .x = 0, .y = -1 }, .bit = NE },
    .{ .d = .{ .x = -1, .y = 0 }, .bit = SW },
    .{ .d = .{ .x = 0, .y = 0 }, .bit = SE },
};

/// What the cells round a point hold, as `Beds` ranks them.
pub const Corners = struct {
    rank: [4]u8,

    fn holds(self: Corners, g: Ground) bool {
        return std.mem.indexOfScalar(u8, &self.rank, g.rank()) != null;
    }

    /// `g`'s piece here: the corners holding it or anything over it, so it runs under them; 0 where `g` is not here.
    pub fn mask(self: Corners, g: Ground) u4 {
        if (!self.holds(g)) return 0;
        var m: u4 = 0;
        for (AROUND, self.rank) |a, r| {
            if (r != NONE and r >= g.rank()) m |= a.bit;
        }
        return m;
    }

    /// Unsheeted `g` fills beneath higher sheeted corners; zero if `g` is absent.
    pub fn under(self: Corners, g: Ground, sheets: Grounds) u4 {
        if (!self.holds(g)) return 0;
        var m: u4 = 0;
        for (AROUND, self.rank) |a, r| {
            if (!isGround(r) or r <= g.rank()) continue;
            if (sheets.contains(Ground.ofRank(r))) m |= a.bit;
        }
        return m;
    }
};

test "every ground without a sheet lies under every ground with one, and each keeps its order among its own" {
    for (std.enums.values(Ground)) |a| {
        for (std.enums.values(Ground)) |b| {
            const sa = look.GROUND_SHEETS.contains(a);
            const sb = look.GROUND_SHEETS.contains(b);
            const want = if (sa == sb) @intFromEnum(a) < @intFromEnum(b) else sb;
            try std.testing.expectEqual(want, a.rank() < b.rank());
        }
        try std.testing.expectEqual(a, Ground.ofRank(a.rank()));
    }
    try std.testing.expectEqual(std.enums.values(Ground).len, LAYERS.len);
    for (LAYERS[1..], LAYERS[0 .. LAYERS.len - 1]) |a, b| try std.testing.expect(b.rank() < a.rank());
}

fn paintedAsTested() !void {
    const s = look.GROUND_SHEETS;
    if (!(s.contains(.water) and s.contains(.dirt) and s.contains(.grass)) or s.contains(.cobble) or s.contains(.sand)) return error.SkipZigTest;
}

test "a corner's pieces stack: each ground covers its own corners and those of every ground or tile over it" {
    try paintedAsTested();
    var lv = grid.Level.blank();
    @memset(&lv.tile, .grass);
    @memset(&lv.seen, true);
    lv.set(.{ .x = 10, .y = 10 }, .water);
    lv.set(.{ .x = 11, .y = 10 }, .dirt);
    lv.set(.{ .x = 10, .y = 11 }, .floor);
    const all = bedsOf(&lv, .{ .x = 0, .y = 0 }, grid.SIZE, true);
    const c = all.pointAt(.{ .x = 11, .y = 11 }).corners;
    try std.testing.expectEqual(FULL, c.mask(.cobble));
    try std.testing.expectEqual(NW | NE | SE, c.mask(.water));
    try std.testing.expectEqual(NE | SE, c.mask(.dirt));
    try std.testing.expectEqual(SE, c.mask(.grass));
    try std.testing.expect(all.pointAt(.{ .x = 11, .y = 11 }).has(.dirt) and !all.pointAt(.{ .x = 11, .y = 11 }).has(.sand));
    const plain = all.pointAt(.{ .x = 30, .y = 30 }).corners;
    try std.testing.expectEqual(FULL, plain.mask(.grass));
    try std.testing.expectEqual(@as(u4, 0), plain.mask(.dirt));
    lv.set(.{ .x = 31, .y = 30 }, .rock);
    const rocky = bedsOf(&lv, .{ .x = 20, .y = 20 }, .{ .x = 40, .y = 40 }, true).pointAt(.{ .x = 31, .y = 31 }).corners;
    try std.testing.expectEqual(FULL, rocky.mask(.grass));
    lv.seen[grid.Level.idx(.{ .x = 11, .y = 11 })] = false;
    const fogged = bedsOf(&lv, .{ .x = 5, .y = 5 }, .{ .x = 15, .y = 15 }, true).pointAt(.{ .x = 11, .y = 11 }).corners;
    try std.testing.expectEqual(NW | NE, fogged.mask(.water));
    try std.testing.expectEqual(NW | NE | SW, fogged.mask(.cobble));
    try std.testing.expectEqual(@as(u4, 0), fogged.mask(.grass));
    const edge = bedsOf(&lv, .{ .x = 0, .y = 0 }, .{ .x = 4, .y = 4 }, true).pointAt(.{ .x = 0, .y = 0 }).corners;
    try std.testing.expectEqual(SE, edge.mask(.grass));
    std.debug.print("cobble, water, dirt and grass round one point: masks {d} {d} {d} {d}\n", .{ c.mask(.cobble), c.mask(.water), c.mask(.dirt), c.mask(.grass) });
}

test "what stands takes the ground its neighbours bear, and the sheet's cells match the template's order" {
    try paintedAsTested();
    var lv = grid.Level.blank();
    @memset(&lv.tile, .rock);
    lv.set(.{ .x = 3, .y = 3 }, .shrub);
    lv.set(.{ .x = 4, .y = 3 }, .wall);
    lv.set(.{ .x = 6, .y = 3 }, .sand);
    try std.testing.expectEqual(@as(?Ground, .grass), bedAt(&lv, .{ .x = 3, .y = 3 }));
    try std.testing.expectEqual(@as(?Ground, .cobble), bedAt(&lv, .{ .x = 4, .y = 3 }));
    try std.testing.expectEqual(@as(?Ground, .sand), bedAt(&lv, .{ .x = 6, .y = 3 }));
    try std.testing.expectEqual(@as(?Ground, null), bedAt(&lv, .{ .x = 8, .y = 3 }));
    const boulder = P{ .x = 20, .y = 20 };
    lv.set(boulder, .boulder);
    for ([_]P{ .{ .x = 19, .y = 19 }, .{ .x = 20, .y = 19 }, .{ .x = 21, .y = 19 } }) |q| lv.set(q, .dirt);
    for ([_]P{ .{ .x = 19, .y = 21 }, .{ .x = 20, .y = 21 } }) |q| lv.set(q, .sand);
    for ([_]P{ .{ .x = 19, .y = 20 }, .{ .x = 21, .y = 20 }, .{ .x = 21, .y = 21 } }) |q| lv.set(q, .water);
    try std.testing.expectEqual(@as(?Ground, .dirt), bedAt(&lv, boulder));
    lv.set(.{ .x = 21, .y = 21 }, .sand);
    try std.testing.expectEqual(@as(?Ground, .sand), bedAt(&lv, boulder));
    lv.set(.{ .x = 21, .y = 21 }, .grass);
    try std.testing.expectEqual(@as(?Ground, .dirt), bedAt(&lv, boulder));
    lv.set(.{ .x = 20, .y = 19 }, .grass);
    try std.testing.expectEqual(@as(?Ground, .sand), bedAt(&lv, boulder));
    try expectLuaList(u4, &ORDER, "tools/tile_art/ground_corners.lua", "return {");
    try expectLuaList(u4, &.{ NW, NE, SW, SE }, "tools/tile_art/ground_sheet.lua", "local NW,NE,SW,SE=");

    try std.testing.expectEqual(P{ .x = 1, .y = 1 }, CELL_OF[FULL]);
}

test "a ground with no sheet lies under the edges round it of a higher one that has a sheet" {
    try paintedAsTested();
    var lv = grid.Level.blank();
    @memset(&lv.tile, .grass);
    lv.set(.{ .x = 10, .y = 10 }, .sand);
    lv.set(.{ .x = 12, .y = 10 }, .floor);
    lv.set(.{ .x = 11, .y = 12 }, .shrub);
    lv.set(.{ .x = 9, .y = 11 }, .rock);
    const sheets = Grounds.initMany(&.{ .dirt, .grass });
    const b = bedsOf(&lv, .{ .x = 0, .y = 0 }, grid.SIZE, false);
    try std.testing.expectEqual(NW | NE | SE, b.pointAt(.{ .x = 11, .y = 10 }).corners.under(.sand, sheets));
    try std.testing.expectEqual(NW | SE, b.pointAt(.{ .x = 10, .y = 11 }).corners.under(.sand, sheets));
    try std.testing.expectEqual(NW | NE | SW, b.pointAt(.{ .x = 12, .y = 10 }).corners.under(.cobble, sheets));
    try std.testing.expectEqual(@as(u4, 0), b.pointAt(.{ .x = 12, .y = 10 }).corners.under(.sand, sheets));
    try std.testing.expectEqual(@as(u4, 0), b.pointAt(.{ .x = 11, .y = 10 }).corners.under(.sand, Grounds.initOne(.dirt)));
    try std.testing.expectEqual(P{ .x = -1, .y = 0 }, AROUND[2].d);
    try std.testing.expectEqual(SW, AROUND[2].bit);

    try std.testing.expectEqual(@as(?Ground, .grass), b.ground(.{ .x = 11, .y = 12 }));
    try std.testing.expect(b.shown.contains(.sand) and b.shown.contains(.cobble) and !b.shown.contains(.dirt));
}

fn bedsOf(lv: *const grid.Level, lo: P, hi: P, seen_only: bool) Beds {
    var b: Beds = undefined;
    b.fill(lv, lo, hi, seen_only);
    return b;
}

/// The numbers a tile-art script's `return { ... }` lists are `want`, in order.
pub fn expectLuaList(comptime T: type, want: []const T, path: []const u8, after: []const u8) !void {
    const alloc = std.testing.allocator;
    const lua = try std.fs.cwd().readFileAlloc(alloc, path, 1 << 16);
    defer alloc.free(lua);
    const list = lua[(std.mem.indexOf(u8, lua, after) orelse return error.NoList) + after.len ..];
    const end = if (std.mem.endsWith(u8, after, "{")) std.mem.indexOfScalar(u8, list, '}') else std.mem.indexOfAny(u8, list, "\r\n");
    var nums = std.mem.tokenizeAny(u8, list[0 .. end orelse return error.NoList], ", \r\n");
    var n: usize = 0;
    while (nums.next()) |m| : (n += 1) {
        try std.testing.expect(n < want.len);
        try std.testing.expectEqual(want[n], try std.fmt.parseInt(T, m, 10));
    }
    try std.testing.expectEqual(want.len, n);
}
