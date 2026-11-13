const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const lume = @import("lume.zig");
const carve = @import("carve.zig");
const actor = @import("../play/actor.zig");

const P = mathx.P;
const ORIGIN = P{ .x = 0, .y = 0 };

pub const MAX_FOES: usize = actor.MAX - actor.most(actor.HERO);
/// Every roll seals the rim, so a section paints inside it.
pub const ROOM = grid.Box.inMap(1);
pub const UNPAINTED: u8 = '_';

comptime {
    std.debug.assert(grid.groundOf(UNPAINTED) == null);
}

pub const Foe = struct { kind: actor.Kind, at: P };
const NO_FOE = Foe{ .kind = std.enums.values(actor.Kind)[0], .at = ORIGIN };

pub fn bodiesOf(foes: []const Foe) usize {
    var n = actor.most(actor.HERO);
    for (foes) |f| n += actor.most(f.kind);
    return n;
}

pub fn foeIn(foes: []const Foe, p: P) ?usize {
    for (foes, 0..) |f, i| {
        if (f.at.eq(p)) return i;
    }
    return null;
}

pub const Anchor = enum {
    fixed,
    /// Its painted box moves whole to a spot each roll draws, its ring clear of the doors.
    roams,
};

pub const Section = struct {
    pub const COUNTED = .{.{ "foe", "foe_n" }};
    anchor: Anchor = .fixed,
    tile: [grid.CELLS]?grid.Tile = @splat(null),
    barrel: [grid.CELLS]bool = @splat(false),
    torch: grid.Torches = .{},
    /// Unused slots retain defaults so plans compare by content.
    foe: [MAX_FOES]Foe = @splat(NO_FOE),
    foe_n: usize = 0,

    pub fn tileAt(self: *const Section, p: P) ?grid.Tile {
        return grid.cellOr(?grid.Tile, &self.tile, p, null);
    }

    fn paintedAs(self: *const Section, p: P, t: grid.Tile) bool {
        return if (self.tileAt(p)) |here| here == t else false;
    }

    fn openAt(self: *const Section, p: P) bool {
        return if (self.tileAt(p)) |here| !here.solid() else false;
    }

    pub fn barrelAt(self: *const Section, p: P) bool {
        return grid.cellOr(bool, &self.barrel, p, false);
    }

    pub fn box(self: *const Section) ?grid.Box {
        var lo = grid.SIZE;
        var hi = ORIGIN;
        for (self.tile, 0..) |t, i| {
            if (t == null) continue;
            const p = grid.Level.of(i);
            lo = lo.min(p);
            hi = hi.max(p.add(.{ .x = 1, .y = 1 }));
        }
        return if (lo.x < hi.x) .{ .lo = lo, .hi = hi } else null;
    }

    pub fn empty(self: *const Section) bool {
        return for (self.tile) |t| {
            if (t != null) break false;
        } else true;
    }

    /// Whether it changed; null erases. What no longer fits on or over the cell goes with it.
    pub fn paint(self: *Section, p: P, t: ?grid.Tile) bool {
        if (!ROOM.holds(p)) return false;
        if (t) |put| if (put.stamped()) return false;
        const i = grid.Level.idx(p);
        if (std.meta.eql(self.tile[i], t)) return false;
        self.tile[i] = t;
        for ([_]P{ p, lume.torchWall(p) }) |w| {
            if (self.torch.has(w) and !self.torchFits(w)) _ = self.torch.remove(w);
        }
        if (self.barrel[i] and !self.barrelFits(p)) self.barrel[i] = false;
        if (self.foeAt(p)) |f| {
            if (!self.foeFits(p, self.foe[f].kind)) self.dropFoe(f);
        }
        return true;
    }

    pub fn barrelFits(self: *const Section, p: P) bool {
        return self.paintedAs(p, grid.BARREL_GROUND);
    }

    pub fn putBarrel(self: *Section, p: P) bool {
        if (!self.barrelFits(p) or self.foeAt(p) != null) return false;
        const i = grid.Level.idx(p);
        self.barrel[i] = true;
        return true;
    }

    pub fn torchFits(self: *const Section, w: P) bool {
        return self.paintedAs(w, .wall) and self.openAt(lume.torchFloor(w));
    }

    pub fn addTorch(self: *Section, w: P) bool {
        return self.torchFits(w) and self.torch.add(w);
    }

    pub fn foes(self: *const Section) []const Foe {
        return self.foe[0..self.foe_n];
    }

    pub fn foeAt(self: *const Section, p: P) ?usize {
        return foeIn(self.foes(), p);
    }

    pub fn foeFits(self: *const Section, p: P, k: actor.Kind) bool {
        const t = self.tileAt(p) orelse return false;
        return k.stocked() and !self.barrelAt(p) and actor.groundFits(k, t);
    }

    pub fn bodies(self: *const Section) usize {
        return bodiesOf(self.foes());
    }

    pub fn addFoe(self: *Section, f: Foe) bool {
        if (self.foeAt(f.at) != null or !self.foeFits(f.at, f.kind) or !actor.roomFor(self.bodies(), f.kind)) return false;
        return mathx.push(Foe, &self.foe, &self.foe_n, f);
    }

    pub fn dropFoe(self: *Section, i: usize) void {
        mathx.removeAt(Foe, &self.foe, &self.foe_n, i, NO_FOE);
    }

    pub fn valid(self: *const Section) bool {
        if (self.foe_n > MAX_FOES or self.torch.n > grid.MAX_TORCHES) return false;
        var whole: [grid.CELLS]grid.Tile = undefined;
        for (self.tile, self.barrel, &whole, 0..) |t, b, *w, i| {
            const p = grid.Level.of(i);
            w.* = t orelse .floor;
            if (t) |put| if (!ROOM.holds(p) or put.stamped()) return false;
            if (b and !self.barrelFits(p)) return false;
        }
        if (!grid.propsWhole(&whole)) return false;
        for (self.torch.slice(), 0..) |w, i| {
            if (!self.torchFits(w) or grid.anyNear(w, self.torch.slice()[0..i], 1)) return false;
        }
        for (self.foes(), 0..) |f, i| {
            if (!self.foeFits(f.at, f.kind) or self.foeAt(f.at).? != i) return false;
        }
        for (self.foe[self.foe_n..]) |f| {
            if (!std.meta.eql(f, NO_FOE)) return false;
        }
        return self.bodies() <= actor.MAX;
    }

    /// Where a roll lays it, or null when it paints nothing.
    pub fn lands(self: *const Section, seed: u64, doors: []const P) ?Placed {
        const b = self.box() orelse return null;
        const to = switch (self.anchor) {
            .fixed => b.lo,
            .roams => roam(b, seed, doors),
        };
        return .{ .section = self, .shift = to.sub(b.lo), .area = grid.Box.sized(to, b.width(), b.height()) };
    }
};

/// Every corner that keeps `b` in `ROOM` and its ring off the doors is as likely; with none, it stays where painted.
fn roam(b: grid.Box, seed: u64, doors: []const P) P {
    const corners = grid.Box{ .lo = ROOM.lo, .hi = ROOM.hi.sub(.{ .x = b.width() - 1, .y = b.height() - 1 }) };
    const w: usize = @intCast(corners.width());
    const Roam = struct {
        b: grid.Box,
        doors: []const P,
        lo: P,
        w: usize,

        fn clear(r: @This(), i: usize) u32 {
            return @intFromBool(clearOf(r.b, r.lo.add(mathx.unslot(i, r.w)), r.doors));
        }
    };
    var rng = carve.Salt.section.rng(seed);
    const i = rng.weighted(w * @as(usize, @intCast(corners.height())), Roam{ .b = b, .doors = doors, .lo = corners.lo, .w = w }, Roam.clear) orelse return b.lo;
    return corners.lo.add(mathx.unslot(i, w));
}

fn clearOf(b: grid.Box, lo: P, doors: []const P) bool {
    const ring = grid.Box.sized(lo, b.width(), b.height()).grown(1);
    for (doors) |d| {
        if (ring.holds(d)) return false;
    }
    return true;
}

pub const Placed = struct {
    section: *const Section,
    shift: P,
    area: grid.Box,

    pub fn at(self: Placed, p: P) P {
        return p.add(self.shift);
    }

    pub fn foe(self: Placed, f: Foe) Foe {
        return .{ .kind = f.kind, .at = self.at(f.at) };
    }

    pub fn cells(self: Placed) grid.CellSet {
        var out = grid.CellSet.initEmpty();
        for (self.section.tile, 0..) |t, i| {
            if (t != null) out.set(grid.Level.idx(self.at(grid.Level.of(i))));
        }
        return out;
    }

    /// Its tiles and barrels over the roll's, and on its cells its own torches alone.
    pub fn stamp(self: Placed, lv: *grid.Level) void {
        const s = self.section;
        for (s.tile, s.barrel, 0..) |t, b, i| {
            const put = t orelse continue;
            const k = grid.Level.idx(self.at(grid.Level.of(i)));
            lv.tile[k] = put;
            lv.barrel[k] = b;
        }
        const painted = self.cells();
        lv.torch.keep(&painted, unpainted);
        lv.torch.n = @min(lv.torch.n, grid.MAX_TORCHES - s.torch.n);
        for (s.torch.slice()) |w| lv.addTorch(self.at(w));
    }
};

fn unpainted(painted: *const grid.CellSet, w: P) bool {
    return !painted.isSet(grid.Level.idx(w));
}

test "a roaming section lands alike for a seed, elsewhere across seeds, never ringing a door, and stays put with no room" {
    var s = Section{ .anchor = .roams };
    const painted = grid.Box.sized(.{ .x = 10, .y = 10 }, 6, 4);
    var it = painted.cells();
    while (it.next()) |p| _ = s.paint(p, .floor);
    const doors = [_]P{ .{ .x = 0, .y = 20 }, .{ .x = 50, .y = 30 }, .{ .x = grid.W - 1, .y = 5 } };
    var seen = grid.CellSet.initEmpty();
    var spots: usize = 0;
    const RUNS = 200;
    for (0..RUNS) |i| {
        const seed = 0x5EC +% i *% grid.TEST_SEED_STRIDE;
        const a = s.lands(seed, &doors).?;
        try std.testing.expectEqual(a.shift, s.lands(seed, &doors).?.shift);
        try std.testing.expectEqual(painted.width(), a.area.width());
        try std.testing.expect(ROOM.holds(a.area.lo) and ROOM.holds(a.area.hi.sub(.{ .x = 1, .y = 1 })));
        try std.testing.expect(clearOf(a.area, a.area.lo, &doors));
        const k = grid.Level.idx(a.area.lo);
        if (!seen.isSet(k)) spots += 1;
        seen.set(k);
    }
    try std.testing.expect(spots * 2 > RUNS);
    s.anchor = .fixed;
    try std.testing.expectEqual(ORIGIN, s.lands(0x5EC, &doors).?.shift);
    var wide = Section{ .anchor = .roams };
    _ = wide.paint(ROOM.lo, .floor);
    _ = wide.paint(ROOM.hi.sub(.{ .x = 1, .y = 1 }), .floor);
    try std.testing.expectEqual(ORIGIN, wide.lands(0x5EC, &doors).?.shift);
    try std.testing.expect((Section{}).lands(0x5EC, &doors) == null);
}

test "painting over a section's cell takes the barrel, torch and foe it no longer bears" {
    var s = Section{};
    const wall = P{ .x = 8, .y = 8 };
    const below = lume.torchFloor(wall);
    try std.testing.expect(!s.paint(.{ .x = 0, .y = 8 }, .floor));
    try std.testing.expect(s.paint(wall, .wall) and s.paint(below, .floor));
    try std.testing.expect(!s.paint(below, .floor));
    try std.testing.expect(s.addTorch(wall));
    try std.testing.expect(s.putBarrel(below));
    try std.testing.expect(!s.addFoe(.{ .kind = .rat, .at = below }));
    try std.testing.expect(!s.addFoe(.{ .kind = .rat, .at = .{ .x = 9, .y = 9 } }));
    try std.testing.expect(s.paint(.{ .x = 9, .y = 9 }, .floor));
    try std.testing.expect(s.addFoe(.{ .kind = .rat, .at = .{ .x = 9, .y = 9 } }));
    try std.testing.expect(s.valid());
    try std.testing.expect(s.paint(below, .water));
    try std.testing.expect(!s.barrelAt(below) and s.torch.n == 0);
    try std.testing.expect(s.paint(.{ .x = 9, .y = 9 }, null));
    try std.testing.expectEqual(@as(usize, 0), s.foe_n);
    try std.testing.expect(s.valid());
    try std.testing.expectEqualDeep(NO_FOE, s.foe[0]);
    s.tile[0] = .floor;
    try std.testing.expect(!s.valid());
}

test "a section takes no more slimes than the pool holds once every one has split to quarters" {
    var s = Section{};
    var it = grid.Box.sized(.{ .x = 1, .y = 1 }, 40, 2).cells();
    while (it.next()) |p| _ = s.paint(p, .floor);
    var slimes: usize = 0;
    while (s.addFoe(.{ .kind = .slime, .at = .{ .x = @intCast(1 + slimes), .y = 1 } })) slimes += 1;
    try std.testing.expectEqual((actor.MAX - 1) / actor.most(.slime), slimes);
    try std.testing.expect(s.bodies() <= actor.MAX and s.valid());
}
