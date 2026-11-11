const sprite_assets = @import("sprite_assets.zig");
const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const look = @import("look.zig");

const P = mathx.P;

/// Lowest first among the grounds with a sheet, and among those without.
pub const Ground = enum {
    chasm,
    lava,
    water,
    shallows,
    ice,
    snow,
    sand,
    dirt,
    crop,
    grass,
    rubble,
    bridge,
    cobble,

    /// Exported to `assets/ground/<name>-ground.png` by `export_ground.lua`, which names its Desktop source.
    pub fn png(comptime g: Ground) []const u8 {
        return @tagName(g) ++ "-ground.png";
    }

    pub fn tile(g: Ground) grid.Tile {
        return switch (g) {
            .cobble => .floor,
            inline else => |n| @field(grid.Tile, @tagName(n)),
        };
    }

    fn bears(g: Ground, t: grid.Tile) bool {
        if (t == .reeds) return switch (g) {
            .grass, .dirt, .shallows => true,
            .ice, .snow, .sand, .rubble, .cobble, .chasm, .lava, .water, .crop, .bridge => false,
        };
        return switch (g) {
            .ice, .snow, .sand, .dirt, .grass, .rubble, .cobble => true,
            .chasm, .lava, .water, .shallows, .crop, .bridge => false,
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

const NONE: u8 = 0;
const RANKS = NONE + 1 + std.enums.values(Ground).len;
const Ranks = std.meta.Int(.unsigned, RANKS);

const RANK = blk: {
    var r = std.EnumArray(Ground, u8).initFill(0);
    var n: u8 = NONE + 1;
    for ([2]bool{ false, true }) |sheet| {
        for (std.enums.values(Ground)) |g| {
            if (sprite_assets.GROUND_SHEETS.contains(g) != sheet) continue;
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

pub const LAYERS: []const Ground = BY_RANK[NONE + 1 ..];

pub fn of(t: grid.Tile) ?Ground {
    return switch (t) {
        .floor => .cobble,
        .stone_bridge => .bridge,
        inline else => |n| if (@hasField(Ground, @tagName(n))) @field(Ground, @tagName(n)) else null,
    };
}

comptime {
    for (std.enums.values(grid.Tile)) |t| {
        const over = t.upright() and look.tileBg(t) != null;
        std.debug.assert(@intFromBool(of(t) != null) + @intFromBool(look.under(t) != null) + @intFromBool(over) == 1);
    }
}

/// Under standing tiles, the neighbours' majority ground (only seen ones vote with `seen_only`), lowest rank on ties; otherwise `look.under`.
pub fn bedAt(lv: *const grid.Level, p: P, seen_only: bool) ?Ground {
    const t = lv.at(p);
    if (of(t)) |g| return g;
    const fallback = look.under(t) orelse return null;
    var votes = [_]u8{0} ** RANKS;
    var best = of(fallback).?;
    var most: u8 = 0;
    for (mathx.ALL_DIRS) |d| {
        const q = p.add(d.delta());
        if (seen_only and !lv.isSeen(q)) continue;
        const g = of(lv.at(q)) orelse continue;
        if (!g.bears(t)) continue;
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

const OVER: u8 = std.math.maxInt(u8);

fn isGround(r: u8) bool {
    return r != NONE and r != OVER;
}

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

    /// Slots back from a point's south-east cell to each of `AROUND`, in its order.
    const AROUND_SLOT = blk: {
        var back: [AROUND.len]usize = undefined;
        for (AROUND, &back) |a, *o| o.* = @intCast(-(a.d.y * @as(i32, SPAN) + a.d.x));
        break :blk back;
    };

    pub const Point = struct {
        corners: Corners,
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
            const g = bedAt(lv, p, seen_only) orelse {
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
            var k: Corners = undefined;
            for (AROUND_SLOT, &k.rank) |back, *r| r.* = b.rank[se - back];
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

    pub fn points(self: *const Beds) grid.Cells {
        return grid.Cells.of(self.lo, self.hi.add(.{ .x = 1, .y = 1 }));
    }

    pub fn pointAt(self: *const Beds, c: P) Point {
        const i = @as(usize, @intCast(c.y - self.lo.y)) * self.across + @as(usize, @intCast(c.x - self.lo.x));
        return self.point[i];
    }
};

comptime {
    for (std.enums.values(Ground)) |g| std.debug.assert(of(g.tile()).? == g);
}

const NW: u4 = 1;
const NE: u4 = 2;
const SW: u4 = 4;
const SE: u4 = 8;
pub const FULL: u4 = NW | NE | SW | SE;

/// A ground sheet's 16 cells, read across its 4x4 block, by mask: `tools/tile_art/ground_corners.lua`.
pub const ORDER = [MASKS]u4{ 9, 12, 4, 8, 10, 15, 13, 14, 6, 11, 7, 3, 5, 2, 1, 0 };
const MASKS: usize = @as(usize, FULL) + 1;
pub const COLS: usize = 4;
pub const ROWS: usize = MASKS / COLS;

pub const CELL_OF = blk: {
    var at: [MASKS]P = undefined;
    var seen = [_]bool{false} ** MASKS;
    for (ORDER, 0..) |m, i| {
        std.debug.assert(!seen[m]);
        seen[m] = true;
        at[m] = mathx.unslot(i, COLS);
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

const Corners = struct {
    rank: [4]u8,

    pub fn pairMask(self: Corners, upper: Ground, lower: Ground) ?u4 {
        var mask_: u4 = 0;
        for (self.rank, AROUND) |r, a| {
            if (r == upper.rank()) mask_ |= a.bit else if (r != lower.rank()) return null;
        }
        return if (mask_ == 0 or mask_ == FULL) null else mask_;
    }

    pub fn edgeMask(self: Corners, upper: Ground, lower: Ground) ?u4 {
        if (!self.holds(upper) or !self.holds(lower)) return null;
        for (self.rank) |r| {
            if (!isGround(r) or !sprite_assets.EDGE_GROUNDS.contains(Ground.ofRank(r))) return null;
        }
        return self.mask(upper);
    }

    comptime {
        std.debug.assert(sprite_assets.EDGE_GROUNDS.contains(.dirt) and sprite_assets.EDGE_GROUNDS.contains(.shallows));
    }

    pub fn edgeQuarter(self: Corners, upper: Ground, lower: Ground, quarter: usize) bool {
        if (self.pairMask(upper, lower) != null) return true;
        if (upper == .shallows) return self.rank[quarter] != Ground.dirt.rank();
        for ([_]usize{ quarter, quarter ^ 2, quarter ^ 1, quarter ^ 3 }) |q| {
            if (self.rank[q] == Ground.dirt.rank()) continue;
            return self.rank[q] == lower.rank();
        }
        return false;
    }

    pub fn waterCliffFor(self: Corners, bank: Bank) ?BankPiece {
        return .of(bank.matches(self.rank[0], self.rank[2]), bank.matches(self.rank[1], self.rank[3]));
    }

    fn holds(self: Corners, g: Ground) bool {
        return std.mem.indexOfScalar(u8, &self.rank, g.rank()) != null;
    }

    pub fn mask(self: Corners, g: Ground) u4 {
        if (!self.holds(g)) return 0;
        var m: u4 = 0;
        for (AROUND, self.rank) |a, r| {
            if (r != NONE and r >= g.rank()) m |= a.bit;
        }
        return m;
    }

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

pub const Bank = enum {
    shallow_deep,
    land_deep,
    land_shallow,

    fn matches(self: Bank, north: u8, south: u8) bool {
        if (!isGround(north) or !isGround(south)) return false;
        return Bank.of(Ground.ofRank(north).tile(), Ground.ofRank(south).tile()) == self;
    }

    pub fn of(north: grid.Tile, south: grid.Tile) ?Bank {
        if (north == .shallows and south == .water) return .shallow_deep;
        if (!bankLand(north)) return null;
        return landBank(south);
    }
};

fn landBank(south: grid.Tile) ?Bank {
    return switch (of(south) orelse return null) {
        .shallows => .land_shallow,
        .water => .land_deep,
        .chasm, .lava, .ice, .snow, .sand, .dirt, .crop, .grass, .rubble, .bridge, .cobble => null,
    };
}

/// A bank's face and cap across a dual-grid point, its columns in the art: the west end, a joined middle, the east end.
pub const BankPiece = enum(u8) {
    left,
    repeat,
    right,

    pub const COUNT = std.enums.values(BankPiece).len;

    pub fn of(west: bool, east: bool) ?BankPiece {
        return if (west) (if (east) .repeat else .right) else if (east) .left else null;
    }

    pub fn col(self: BankPiece) i32 {
        return @intFromEnum(self);
    }

    fn wetSide(self: BankPiece, side: usize) i32 {
        return switch (self) {
            .left => 0,
            .right => -1,
            .repeat => @as(i32, @intCast(side)) - 1,
        };
    }

    pub fn wetAt(self: BankPiece, p: P, side: usize) P {
        return p.add(.{ .x = self.wetSide(side), .y = 0 });
    }

    pub fn outside(self: BankPiece, side: usize) bool {
        return (self == .left and side == 0) or (self == .right and side == 1);
    }
};

fn bankLand(t: grid.Tile) bool {
    return switch (of(t) orelse return false) {
        .water, .shallows, .lava, .chasm, .bridge => false,
        .ice, .snow, .sand, .dirt, .crop, .grass, .rubble, .cobble => true,
    };
}

const BankDepth = struct { px: f32, feet: Profile, lip: Profile };

const BANK_DEPTHS = std.EnumArray(Ground, ?BankDepth).initDefault(@as(?BankDepth, null), .{
    .shallows = .{ .px = 6, .feet = cliffFeet(@embedFile("shallows-cliff-foot.txt")), .lip = cliffFeet(@embedFile("shallows-cliff-lip.txt")) },
    .water = .{ .px = 24, .feet = cliffFeet(@embedFile("water-cliff-foot.txt")), .lip = cliffFeet(@embedFile("water-cliff-lip.txt")) },
});

fn depthOf(g: Ground) ?*const BankDepth {
    return if (BANK_DEPTHS.getPtrConst(g).*) |*d| d else null;
}

pub fn bankHeight(t: grid.Tile) f32 {
    const d = depthOf(of(t) orelse return 0) orelse return 0;
    return d.px / @as(f32, look.SPRITE_PX);
}

pub fn bankAbove(north: grid.Tile, south: grid.Tile) bool {
    return Bank.of(north, south) != null;
}

pub const BANK_LIFT_PX: f32 = 8;
pub const BANK_LIFT: f32 = BANK_LIFT_PX / look.SPRITE_PX;

const Profile = [BankPiece.COUNT * look.SPRITE_PX]u8;
const Heights = fn (*const BankDepth) *const Profile;

fn feetOf(d: *const BankDepth) *const Profile {
    return &d.feet;
}

fn lipOf(d: *const BankDepth) *const Profile {
    return &d.lip;
}

fn cliffFeet(comptime text: []const u8) Profile {
    @setEvalBranchQuota(100000);
    var feet: Profile = undefined;
    var words = std.mem.tokenizeAny(u8, text, ",\r\n");
    for (&feet) |*foot| {
        foot.* = std.fmt.parseInt(u8, words.next().?, 10) catch unreachable;
        std.debug.assert(foot.* <= look.SPRITE_PX);
    }
    std.debug.assert(words.next() == null);
    return feet;
}

fn bankCell(lv: *const grid.Level, p: P) bool {
    if (bankHeight(lv.at(p)) == 0) return false;
    const above = p.add(.{ .x = 0, .y = -1 });
    if (!grid.Level.inside(above)) return false;
    const north = bedAt(lv, above, false) orelse return false;
    return bankAbove(north.tile(), lv.at(p));
}

pub fn bankFoot(lv: *const grid.Level, q: [2]f32) ?f32 {
    return bankProfile(lv, q, feetOf);
}

pub fn bankLip(lv: *const grid.Level, q: [2]f32) ?f32 {
    return bankProfile(lv, q, lipOf);
}

fn bankProfile(lv: *const grid.Level, q: [2]f32, comptime heights: Heights) ?f32 {
    const c = mathx.cellOf(q);
    return (BankShape.of(lv, c) orelse return null).profile(c, q, heights);
}

const BankShape = struct {
    water: Ground,
    pieces: [2]BankPiece,

    fn of(lv: *const grid.Level, c: P) ?BankShape {
        if (!bankCell(lv, c)) return null;
        const north = bedAt(lv, c.add(.{ .x = 0, .y = -1 }), false).?;
        const bank = Bank.of(north.tile(), lv.at(c)).?;
        var s = BankShape{ .water = bedAt(lv, c, false).?, .pieces = undefined };
        for (&s.pieces, 0..) |*piece, h| piece.* = pieceAt(lv, bank, c.add(.{ .x = @intCast(h), .y = 0 }));
        return s;
    }

    fn profile(s: BankShape, c: P, q: [2]f32, comptime heights: Heights) ?f32 {
        const p = mathx.cellOf(.{ q[0] + 0.5, q[1] });
        const h: usize = @intCast(p.x - c.x);
        const piece = s.pieces[h];
        const col: usize = @intFromFloat((q[0] - @as(f32, @floatFromInt(p.x)) + 0.5) * look.SPRITE_PX);
        const depth = depthOf(s.water).?;
        const offset = @as(usize, @intFromEnum(piece)) * look.SPRITE_PX + @min(col, look.SPRITE_PX - 1);
        if (depth.feet[offset] == 0) return null;
        const foot = heights(depth)[offset];
        return @as(f32, @floatFromInt(p.y)) + (@as(f32, @floatFromInt(foot)) - BANK_LIFT_PX) / look.SPRITE_PX;
    }
};

fn pieceAt(lv: *const grid.Level, bank: Bank, p: P) BankPiece {
    const west_p = p.add(.{ .x = -1, .y = 0 });
    const west_n = bedAt(lv, west_p.add(.{ .x = 0, .y = -1 }), false);
    const east_n = bedAt(lv, p.add(.{ .x = 0, .y = -1 }), false);
    const west = if (west_n) |g| Bank.of(g.tile(), lv.at(west_p)) == bank else false;
    const east = if (east_n) |g| Bank.of(g.tile(), lv.at(p)) == bank else false;
    return BankPiece.of(west, east) orelse .left;
}

pub const LiveBanks = struct {
    lv: *const grid.Level,

    pub fn bed(b: LiveBanks, p: P) ?Ground {
        return bedAt(b.lv, p, false);
    }

    pub fn foot(b: LiveBanks, q: [2]f32) ?f32 {
        return bankFoot(b.lv, q);
    }

    pub fn lip(b: LiveBanks, q: [2]f32) ?f32 {
        return bankLip(b.lv, q);
    }
};

pub const Banks = struct {
    beds: [grid.CELLS]?Ground = undefined,
    shapes: [grid.CELLS]?BankShape = undefined,
    tiles: [grid.CELLS]grid.Tile = undefined,
    built: bool = false,

    pub fn sync(b: *Banks, lv: *const grid.Level) void {
        if (b.built and std.mem.eql(grid.Tile, &b.tiles, &lv.tile)) return;
        b.tiles = lv.tile;
        b.built = true;
        for (0..grid.CELLS) |i| {
            const c = grid.Level.of(i);
            b.beds[i] = bedAt(lv, c, false);
            b.shapes[i] = BankShape.of(lv, c);
        }
    }

    pub fn bed(b: *const Banks, p: P) ?Ground {
        const i = grid.Level.idx(p);
        return b.beds[i];
    }

    pub fn foot(b: *const Banks, q: [2]f32) ?f32 {
        return b.profile(q, feetOf);
    }

    pub fn lip(b: *const Banks, q: [2]f32) ?f32 {
        return b.profile(q, lipOf);
    }

    fn profile(b: *const Banks, q: [2]f32, comptime heights: Heights) ?f32 {
        const c = mathx.cellOf(q);
        if (!grid.Level.inside(c)) return null;
        const i = grid.Level.idx(c);
        return (b.shapes[i] orelse return null).profile(c, q, heights);
    }
};

test "every ground without a sheet lies under every ground with one, and each keeps its order among its own" {
    for (std.enums.values(Ground)) |a| {
        for (std.enums.values(Ground)) |b| {
            const sa = sprite_assets.GROUND_SHEETS.contains(a);
            const sb = sprite_assets.GROUND_SHEETS.contains(b);
            const want = if (sa == sb) @intFromEnum(a) < @intFromEnum(b) else sb;
            try std.testing.expectEqual(want, a.rank() < b.rank());
        }
        try std.testing.expectEqual(a, Ground.ofRank(a.rank()));
    }
    try std.testing.expectEqual(std.enums.values(Ground).len, LAYERS.len);
    for (LAYERS[1..], LAYERS[0 .. LAYERS.len - 1]) |a, b| try std.testing.expect(b.rank() < a.rank());
}

fn paintedAsTested() !void {
    const s = sprite_assets.GROUND_SHEETS;
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
}

test "what stands takes the ground its neighbours bear" {
    try paintedAsTested();
    var lv = grid.Level.blank();
    @memset(&lv.tile, .rock);
    lv.set(.{ .x = 3, .y = 3 }, .shrub);
    lv.set(.{ .x = 4, .y = 3 }, .wall);
    lv.set(.{ .x = 6, .y = 3 }, .sand);
    try std.testing.expectEqual(@as(?Ground, .grass), bedAt(&lv, .{ .x = 3, .y = 3 }, false));
    try std.testing.expectEqual(@as(?Ground, .cobble), bedAt(&lv, .{ .x = 4, .y = 3 }, false));
    try std.testing.expectEqual(@as(?Ground, .sand), bedAt(&lv, .{ .x = 6, .y = 3 }, false));
    try std.testing.expectEqual(@as(?Ground, null), bedAt(&lv, .{ .x = 8, .y = 3 }, false));
    const boulder = P{ .x = 20, .y = 20 };
    lv.set(boulder, .boulder);
    for ([_]P{ .{ .x = 19, .y = 19 }, .{ .x = 20, .y = 19 }, .{ .x = 21, .y = 19 } }) |q| lv.set(q, .dirt);
    for ([_]P{ .{ .x = 19, .y = 21 }, .{ .x = 20, .y = 21 } }) |q| lv.set(q, .sand);
    for ([_]P{ .{ .x = 19, .y = 20 }, .{ .x = 21, .y = 20 }, .{ .x = 21, .y = 21 } }) |q| lv.set(q, .water);
    try std.testing.expectEqual(@as(?Ground, .dirt), bedAt(&lv, boulder, false));
    lv.set(.{ .x = 21, .y = 21 }, .sand);
    try std.testing.expectEqual(@as(?Ground, .sand), bedAt(&lv, boulder, false));
    lv.set(.{ .x = 21, .y = 21 }, .grass);
    try std.testing.expectEqual(@as(?Ground, .dirt), bedAt(&lv, boulder, false));
    lv.set(.{ .x = 20, .y = 19 }, .grass);
    try std.testing.expectEqual(@as(?Ground, .sand), bedAt(&lv, boulder, false));
    try std.testing.expectEqual(of(look.under(.boulder).?), bedAt(&lv, boulder, true));
    lv.seen[grid.Level.idx(.{ .x = 19, .y = 19 })] = true;
    try std.testing.expectEqual(@as(?Ground, .dirt), bedAt(&lv, boulder, true));
}

test "ground sheet cells and corner bits match the art templates independently of installed sheets" {
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

test "water edge edits select all mixed pair masks and exclude unseen or different grounds" {
    for ([_][2]Ground{ .{ .dirt, .shallows }, .{ .dirt, .water }, .{ .shallows, .water } }) |pair| {
        for (0..MASKS) |n| {
            const mask_: u4 = @intCast(n);
            var c: Corners = undefined;
            for (&c.rank, AROUND) |*r, a| r.* = (if (mask_ & a.bit != 0) pair[0] else pair[1]).rank();
            try std.testing.expectEqual(if (n == 0 or n == FULL) @as(?u4, null) else mask_, c.pairMask(pair[0], pair[1]));
            for ([_]u8{ NONE, OVER, Ground.grass.rank() }) |other| {
                var mixed = c;
                mixed.rank[0] = other;
                try std.testing.expectEqual(@as(?u4, null), mixed.pairMask(pair[0], pair[1]));
            }
        }
    }
}

test "stepped water banks end each depth independently and route all three material corners" {
    const c = Corners{ .rank = .{ Ground.shallows.rank(), Ground.dirt.rank(), Ground.water.rank(), Ground.shallows.rank() } };
    try std.testing.expectEqual(@as(?BankPiece, .right), c.waterCliffFor(.shallow_deep));
    try std.testing.expectEqual(@as(?BankPiece, .left), c.waterCliffFor(.land_shallow));
    try std.testing.expectEqual(@as(?BankPiece, null), c.waterCliffFor(.land_deep));
    try std.testing.expectEqual(@as(?u4, NE), c.edgeMask(.dirt, .shallows));
    try std.testing.expectEqual(@as(?u4, NW | NE | SE), c.edgeMask(.shallows, .water));
    const grounds = [_]Ground{ .dirt, .shallows, .water };
    var mixed_n: usize = 0;
    for (0..81) |n| {
        var k: Corners = undefined;
        var left = n;
        for (&k.rank) |*r| {
            r.* = grounds[left % 3].rank();
            left /= 3;
        }
        if (!k.holds(.dirt) or !k.holds(.shallows) or !k.holds(.water)) continue;
        mixed_n += 1;
        for (0..4) |q| {
            try std.testing.expect(k.edgeQuarter(.dirt, .shallows, q) != k.edgeQuarter(.dirt, .water, q));
            try std.testing.expectEqual(k.rank[q] != Ground.dirt.rank(), k.edgeQuarter(.shallows, .water, q));
        }
    }
    try std.testing.expectEqual(@as(usize, 36), mixed_n);
}

test "water cliff faces dry north banks with joined middles and separate ends" {
    var lv = grid.Level.blank();
    @memset(&lv.tile, .grass);
    @memset(&lv.seen, true);
    for (10..13) |x| lv.set(.{ .x = @intCast(x), .y = 10 }, .shallows);
    var b = bedsOf(&lv, .{ .x = 8, .y = 8 }, .{ .x = 15, .y = 13 }, true);
    for ([_]?BankPiece{ .left, .repeat, .repeat, .right }, 10..) |want, x| {
        try std.testing.expectEqual(want, b.pointAt(.{ .x = @intCast(x), .y = 10 }).corners.waterCliffFor(.land_shallow));
        for (std.enums.values(Bank)) |bank| {
            try std.testing.expectEqual(@as(?BankPiece, null), b.pointAt(.{ .x = @intCast(x), .y = 11 }).corners.waterCliffFor(bank));
        }
    }
    for ([_]grid.Tile{ .water, .shallows, .bridge, .chasm, .lava }) |t| {
        lv.set(.{ .x = 10, .y = 9 }, t);
        lv.set(.{ .x = 11, .y = 9 }, t);
        b.fill(&lv, b.lo, b.hi, true);
        for (std.enums.values(Bank)) |bank| {
            try std.testing.expectEqual(@as(?BankPiece, null), b.pointAt(.{ .x = 11, .y = 10 }).corners.waterCliffFor(bank));
        }
    }
    lv.set(.{ .x = 10, .y = 9 }, .dirt);
    lv.set(.{ .x = 11, .y = 9 }, .dirt);
    lv.seen[grid.Level.idx(.{ .x = 10, .y = 9 })] = false;
    lv.seen[grid.Level.idx(.{ .x = 11, .y = 9 })] = false;
    b.fill(&lv, b.lo, b.hi, true);
    try std.testing.expectEqual(@as(?BankPiece, null), b.pointAt(.{ .x = 11, .y = 10 }).corners.waterCliffFor(.land_shallow));
    b.fill(&lv, b.lo, b.hi, false);
    try std.testing.expectEqual(@as(?BankPiece, .repeat), b.pointAt(.{ .x = 11, .y = 10 }).corners.waterCliffFor(.land_shallow));
    lv.set(.{ .x = 10, .y = 10 }, .water);
    lv.set(.{ .x = 11, .y = 10 }, .water);
    b.fill(&lv, b.lo, b.hi, false);
    try std.testing.expectEqual(@as(?BankPiece, .repeat), b.pointAt(.{ .x = 11, .y = 10 }).corners.waterCliffFor(.land_deep));
    lv.set(.{ .x = 10, .y = 9 }, .shallows);
    lv.set(.{ .x = 11, .y = 9 }, .shallows);
    b.fill(&lv, b.lo, b.hi, false);
    try std.testing.expectEqual(@as(?BankPiece, .repeat), b.pointAt(.{ .x = 11, .y = 10 }).corners.waterCliffFor(.shallow_deep));
    try std.testing.expect(bankLip(&lv, .{ 10.75, 10 }) != null);
    try std.testing.expect(bankFoot(&lv, .{ 10.75, 10 }) != null);
    const top_lips = struct {
        const TOP: Profile = @splat(0);
        fn at(_: *const BankDepth) *const Profile {
            return &TOP;
        }
    }.at;
    try std.testing.expectEqual(@as(?f32, 10 - BANK_LIFT), bankProfile(&lv, .{ 10.75, 10 }, top_lips));
    for ([_]Ground{ .ice, .snow, .sand, .dirt, .crop, .grass, .rubble, .cobble }) |land| {
        for ([_]Ground{ .shallows, .water }) |water| {
            lv.set(.{ .x = 10, .y = 9 }, land.tile());
            lv.set(.{ .x = 11, .y = 9 }, land.tile());
            lv.set(.{ .x = 10, .y = 10 }, water.tile());
            lv.set(.{ .x = 11, .y = 10 }, water.tile());
            b.fill(&lv, b.lo, b.hi, false);
            for (std.enums.values(Bank)) |bank| {
                const want: ?BankPiece = if (bank == (if (water == .shallows) Bank.land_shallow else Bank.land_deep)) .repeat else null;
                try std.testing.expectEqual(want, b.pointAt(.{ .x = 11, .y = 10 }).corners.waterCliffFor(bank));
            }
        }
    }
    lv.set(.{ .x = 10, .y = 9 }, .grass);
    lv.set(.{ .x = 11, .y = 9 }, .dirt);
    lv.set(.{ .x = 10, .y = 10 }, .shallows);
    b.fill(&lv, b.lo, b.hi, false);
    const mixed = b.pointAt(.{ .x = 11, .y = 10 }).corners;
    try std.testing.expectEqual(@as(?BankPiece, .right), mixed.waterCliffFor(.land_shallow));
    try std.testing.expectEqual(@as(?BankPiece, .left), mixed.waterCliffFor(.land_deep));
    try std.testing.expectEqual(@as(?BankPiece, null), mixed.waterCliffFor(.shallow_deep));
    lv.set(.{ .x = 10, .y = 0 }, .water);
    lv.set(.{ .x = 11, .y = 0 }, .water);
    try std.testing.expectEqual(@as(?f32, null), bankFoot(&lv, .{ 10.75, 0 }));
    try std.testing.expectEqual(@as(?f32, null), bankLip(&lv, .{ 10.75, 0 }));
}

/// The values in a tile-art script after `after`, to its `}` when it opens a table or else to the line's end, are `want`.
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
        const value = switch (@typeInfo(T)) {
            .@"enum" => std.meta.stringToEnum(T, std.mem.trim(u8, m, "'\"")) orelse return error.InvalidEnum,
            else => try std.fmt.parseInt(T, m, 10),
        };
        try std.testing.expectEqual(want[n], value);
    }
    try std.testing.expectEqual(want.len, n);
}
