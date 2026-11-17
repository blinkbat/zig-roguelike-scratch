const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");
const buildings = @import("buildings.zig");

const P = mathx.P;

pub const COUNT_MAX: u8 = 8;
pub const APART_MAX: u8 = 30;

pub const Piece = enum { circle, cairns, camp, graveyard, well, tower, shrine, corral, oasis, chest_niche, light_niche };

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
        .chest_niche => &.{
            "  ####   ",
            " ##..### ",
            " #..C..# ",
            " #.....# ",
            "  #...,# ",
            "  ##.,,# ",
            "    .,,  ",
        },
        .light_niche => &.{
            "   ####  ",
            " ###..## ",
            " #..p..# ",
            " #.....# ",
            " #,...## ",
            "  #,,.#  ",
            "   ,,.   ",
        },
    };
}

pub const Params = struct {
    piece: Piece = .circle,
    count: u8 = 2,
    apart: u8 = 6,

    pub fn fit(p: Params) Params {
        var q = p;
        q.count = std.math.clamp(p.count, 1, COUNT_MAX);
        q.apart = @min(p.apart, APART_MAX);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, pal: carve.Palette, lots: *buildings.Lots, p: Params) void {
    if (p.piece == .chest_niche or p.piece == .light_niche) {
        for (0..p.count) |_| niche(lv, rng, pal, lots, p);
        return;
    }
    const art = rows(p.piece);
    const w = size(art).x;
    const h = size(art).y;
    for (0..p.count) |_| {
        const room = if (p.piece == .camp)
            campSpace(lots, lv, rng, w, h, p.apart, pal) orelse continue
        else
            spaced(lots, lv, rng, w, h, p.apart, pal) orelse continue;
        place(lv, room.lo, art, pal);
    }
}

fn campSpace(lots: *buildings.Lots, lv: *const grid.Level, rng: *mathx.Rng, w: i32, h: i32, apart: u8, pal: carve.Palette) ?grid.Box {
    for (0..400) |_| {
        const at = P{ .x = rng.range(2, grid.W - w - 2), .y = rng.range(2, grid.H - h - 2) };
        const b = grid.Box.sized(at, w, h);
        if (!lots.canTake(lv, b, @max(buildings.Lots.GAP, 2 * @as(i32, apart)), pal)) continue;
        var open: i32 = 0;
        var cells = b.grown(1).cells();
        const clean = while (cells.next()) |q| {
            const t = lv.at(q);
            if ((t != pal.open and t != pal.path and t != pal.solid) or lv.barrel[grid.Level.idx(q)]) break false;
            if (b.holds(q) and lv.walkable(q)) open += 1;
        } else true;
        if (clean and open * 4 >= w * h * 3 and lots.takeAt(lv, b, @max(buildings.Lots.GAP, 2 * @as(i32, apart)), pal)) return b;
    }
    return null;
}

fn turn(q: P, size_: P, rotation: u2) P {
    return switch (rotation) {
        0 => q,
        1 => .{ .x = size_.y - 1 - q.y, .y = q.x },
        2 => .{ .x = size_.x - 1 - q.x, .y = size_.y - 1 - q.y },
        3 => .{ .x = q.y, .y = size_.x - 1 - q.x },
    };
}

fn niche(lv: *grid.Level, rng: *mathx.Rng, pal: carve.Palette, lots: *buildings.Lots, p: Params) void {
    const art = rows(p.piece);
    const size_ = size(art);
    var best: ?struct { box: grid.Box, rotation: u2 } = null;
    var score: usize = 0;
    const gap = @max(buildings.Lots.GAP, @as(i32, p.apart));
    for (0..400) |_| {
        const rotation: u2 = @intCast(rng.range(0, 3));
        const extent = if (rotation % 2 == 0) size_ else P{ .x = size_.y, .y = size_.x };
        const at = P{ .x = rng.range(2, grid.W - extent.x - 2), .y = rng.range(2, grid.H - extent.y - 2) };
        const b = grid.Box.sizedP(at, extent);
        if (!lots.canTake(lv, b, gap, pal)) continue;
        const mouth = at.add(turn(.{ .x = if (p.piece == .chest_niche) 5 else 4, .y = size_.y }, size_, rotation));
        if (!lv.walkable(mouth) or lv.at(mouth).wet() or lv.barrel[grid.Level.idx(mouth)]) continue;
        var solid: usize = 0;
        var cells = b.grown(1).cells();
        const clean = while (cells.next()) |q| {
            const t = lv.at(q);
            if ((t != pal.open and t != pal.path and t != pal.solid) or lv.barrel[grid.Level.idx(q)]) break false;
            solid += @intFromBool(t == pal.solid);
        } else true;
        if (!clean) continue;
        const merit = 1 + @min(solid, 40);
        if (merit <= score) continue;
        best = .{ .box = b, .rotation = rotation };
        score = merit;
    }
    const site = best orelse return;
    if (!lots.takeAt(lv, site.box, gap, pal)) return;
    var spots = Spots{ .at = .{ .x = 0, .y = 0 }, .art = art };
    while (spots.next()) |s| {
        const tile: grid.Tile = switch (s.c) {
            '#' => pal.solid,
            '.' => pal.open,
            ',' => pal.path,
            'C' => .chest,
            'p' => .glow_plant,
            else => continue,
        };
        lv.set(site.box.lo.add(turn(s.q, size_, site.rotation)), tile);
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
    carve.clearRound(lv, grid.Box.sizedP(at, size(art)), pal);
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

test "niches adapt to each biome palette, protect occupied lots and leave their rewards reachable" {
    const procgen = @import("../procgen.zig");
    const door = P{ .x = 0, .y = grid.H / 2 };
    var lv: grid.Level = undefined;
    var dist: [grid.CELLS]i32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    var placed: usize = 0;
    for (std.enums.values(procgen.Algo)) |algo| {
        const base = procgen.Floor.of(algo);
        const pal = base.palette();
        for ([_]Piece{ .chest_niche, .light_niche }) |piece| {
            var rng = mathx.Rng.init(0xA1C0 + @as(u64, @intFromEnum(algo)));
            lv = grid.Level.blank();
            carve.field(&lv, pal);
            lv.barrel = @splat(false);
            var lots: buildings.Lots = .{};
            const reserved = grid.Box.sized(.{ .x = 20, .y = 20 }, 12, 12);
            lots.reserve(reserved);
            lots.begin();
            apply(&lv, &rng, 0, pal, &lots, .{ .piece = piece, .count = 2, .apart = 4 });
            const reward: grid.Tile = if (piece == .chest_niche) .chest else .glow_plant;
            try std.testing.expectEqual(@as(usize, 2), carve.count(&lv, reward));
            var cells = reserved.cells();
            while (cells.next()) |q| try std.testing.expectEqual(pal.open, lv.at(q));
            for (lv.tile) |t| try std.testing.expect(t == pal.open or t == pal.path or t == pal.solid or t == reward);
        }
        procgen.roll(&lv, 0xA1C0, &.{door}, base, &.{
            .{ .setpiece = .{ .piece = .chest_niche, .count = 1 } },
            .{ .setpiece = .{ .piece = .light_niche, .count = 1 } },
        });
        try grid.expectAllReached(&lv, door, &dist, &queue);
        for (lv.tile, 0..) |t, i| {
            if (t != .chest and t != .glow_plant) continue;
            var around_ = grid.Cells.around(grid.Level.of(i), 1);
            const reached = while (around_.next()) |q| {
                if (grid.Level.inside(q) and dist[grid.Level.idx(q)] >= 0) break true;
            } else false;
            try std.testing.expect(reached);
            placed += 1;
        }
    }
    try std.testing.expect(placed >= std.meta.fields(procgen.Algo).len);
}

test "pieces land apart on open ground" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x5E7);
    carve.field(&lv, carve.Palette.WILD);
    var lots: buildings.Lots = .{};
    apply(&lv, &rng, 0, carve.Palette.WILD, &lots, .{ .piece = .graveyard, .count = 3 });
    try std.testing.expectEqual(@as(usize, 3 * 12), carve.count(&lv, .grave));
}

test "shrines set wide apart land no closer than at the default margin" {
    var default: i32 = 0;
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
        if (apart == (Params{}).apart) default = nearest;
        if (apart > (Params{}).apart) try std.testing.expect(nearest >= default);
    }
}
