const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const gas = @import("gas.zig");
const ice = @import("ice.zig");
const damage = @import("../play/damage.zig");

const P = mathx.P;

pub const NAME = "flames";
pub const CATCHES = "Fire takes hold!";
pub const DIES = "The flames die out.";
/// Turns a cell burns once it catches.
pub const BURNS: u8 = 3;
/// Each turn, a burning cell's chance to catch each neighbour that burns, to boil each wet one or to melt each frozen one.
pub const SPREAD: u32 = 20;
/// Smoke a burning tile gives off a turn.
pub const SMOKE: u16 = 14;
/// At the heaviest rain, the share of every chance to catch that it puts out.
pub const RAIN_DAMP: f32 = 0.8;
/// What a tile that burns leaves behind.
pub const ASH: grid.Tile = .dirt;
/// What standing in flames deals a turn, before fire resistance.
pub const SCORCH: i32 = 3;
/// The chance standing in flames sets a body burning, before its fire and burn resistance.
pub const CATCH: u32 = 50;
/// The cells landing fire may leap on from what it catches, unless its source says otherwise.
pub const LANDED_HEAT: u8 = 2;

/// Fire landing: its chance to catch each cell that burns, and the cells it may leap on from there.
pub const Kindle = struct { chance: u32, heat: u8 = LANDED_HEAT };

/// `now` is the ash of `was`, burnt down.
pub fn burntDown(was: grid.Tile, now: grid.Tile) bool {
    return now == ASH and was.burns();
}

/// What standing in flames deals a turn against `resists`.
pub fn scorch(resists: damage.Resists) i32 {
    return damage.resisted(SCORCH, resists.get(.fire));
}

/// `chance` under rain of `rain`, 0 none to 1 a downpour.
pub fn damped(chance: u32, rain: f32) u32 {
    const r = std.math.clamp(rain, 0, 1);
    return @intFromFloat(@round(@as(f32, @floatFromInt(chance)) * (1 - RAIN_DAMP * r)));
}

/// `p` burning for `turns`, its fire leaping `heat` cells on.
pub fn lay(lv: *grid.Level, p: P, turns: u8, heat: u8) void {
    const i = grid.Level.idx(p);
    lv.flames[i] = @max(lv.flames[i], turns);
    lv.heat[i] = @max(lv.heat[i], heat);
}

fn catches(lv: *const grid.Level, p: P) bool {
    return grid.Level.inside(p) and lv.at(p).burns() and !lv.burning(p);
}

/// Each cell of `cells` that burns catches by `k`'s chance under `rain`; how many did.
pub fn kindle(lv: *grid.Level, cells: []const P, k: Kindle, rain: f32, rng: *mathx.Rng) usize {
    const chance = damped(k.chance, rain);
    if (chance == 0) return 0;
    var n: usize = 0;
    for (cells) |p| {
        if (!catches(lv, p) or !rng.percent(chance)) continue;
        lay(lv, p, BURNS, k.heat);
        n += 1;
    }
    return n;
}

/// Every cold blow's chance to put out each burning cell it reaches.
pub const DOUSE: u32 = 85;
/// Every cold blow's chance to put out each burning body it reaches.
pub const QUENCH: u32 = 50;
pub const QUENCHED = "stops burning";

/// Each burning cell of `cells` goes out by `chance`, leaving its tile unburnt; how many did.
pub fn douse(lv: *grid.Level, cells: []const P, chance: u32, rng: *mathx.Rng) usize {
    var n: usize = 0;
    for (cells) |p| {
        if (!grid.Level.inside(p) or !lv.burning(p) or !rng.percent(chance)) continue;
        const i = grid.Level.idx(p);
        lv.flames[i] = 0;
        lv.heat[i] = 0;
        n += 1;
    }
    return n;
}

/// A turn of the floor's fire: each burning tile smokes, each fire leaps to what burns beside it, boils the water and melts the frozen shallows beside it,
/// then every cell burns a turn down, and a tile that burns goes to `ASH` as its fire goes out; true when any did.
pub fn turn(lv: *grid.Level, rng: *mathx.Rng, rain: f32) bool {
    if (std.mem.allEqual(u8, &lv.flames, 0)) return false;
    const was = lv.flames;
    const chance = damped(SPREAD, rain);
    for (was, 0..) |left, i| {
        if (left == 0) continue;
        const p = grid.Level.of(i);
        if (lv.tile[i].burns()) lv.release(.smoke, p, SMOKE);
        if (chance == 0) continue;
        const heat = lv.heat[i];
        for (mathx.ALL_DIRS) |d| {
            const q = p.add(d.delta());
            if (!grid.Level.inside(q)) continue;
            if (lv.at(q).wet()) {
                if (rng.percent(chance)) _ = gas.boil(lv, &.{q});
            } else if (lv.frozen(q)) {
                if (rng.percent(chance)) _ = ice.melt(lv, &.{q});
            } else if (heat > 0 and catches(lv, q) and rng.percent(chance)) lay(lv, q, BURNS, heat - 1);
        }
    }
    var burnt = false;
    for (&lv.flames, &lv.heat, &lv.tile, was) |*f, *h, *t, left| {
        if (left == 0) continue;
        f.* -= 1;
        if (f.* > 0) continue;
        h.* = 0;
        if (!t.burns()) continue;
        t.* = ASH;
        burnt = true;
    }
    return burnt;
}

fn field(t: grid.Tile) grid.Level {
    var lv = grid.openFloor();
    for (&lv.tile) |*c| c.* = t;
    return lv;
}

const AT = grid.MIDDLE;
const NEVER: usize = 100;
const TRIES: usize = 200;

const Burn = struct { cells: usize, turns: usize, reach: i32 };

fn burnOut(lv: *grid.Level, rng: *mathx.Rng, rain: f32) !Burn {
    var turns: usize = 0;
    while (!std.mem.allEqual(u8, &lv.flames, 0)) : (turns += 1) {
        if (turns == NEVER) return error.NeverOut;
        _ = turn(lv, rng, rain);
    }
    var out = Burn{ .cells = 0, .turns = turns, .reach = 0 };
    for (lv.tile, 0..) |t, i| {
        if (t != ASH) continue;
        out.cells += 1;
        out.reach = @max(out.reach, mathx.dist(AT, grid.Level.of(i)));
    }
    return out;
}

fn average(heat: u8, rain: f32, rng: *mathx.Rng) !struct { cells: f32, reach: i32, turns: usize } {
    var cells: usize = 0;
    var reach: i32 = 0;
    var turns: usize = 0;
    for (0..TRIES) |_| {
        var lv = field(.grass);
        lay(&lv, AT, BURNS, heat);
        const b = try burnOut(&lv, rng, rain);
        try std.testing.expect(b.reach <= heat);
        try std.testing.expectEqual(@as(u8, 0), std.mem.max(u8, &lv.heat));
        cells += b.cells;
        reach = @max(reach, b.reach);
        turns = @max(turns, b.turns);
    }
    return .{ .cells = @as(f32, @floatFromInt(cells)) / TRIES, .reach = reach, .turns = turns };
}

test "a fire in a field of grass leaps only as far as its heat, goes out in a few turns and leaves dirt" {
    var rng = mathx.Rng.init(0xF12E);
    var was: f32 = 0;
    for (0..4) |h| {
        const heat: u8 = @intCast(h);
        const a = try average(heat, 0, &rng);
        std.debug.print("a grass fire of heat {d}: {d:.1} cells burnt on average, out to {d} cells, out in at most {d} turns\n", .{ heat, a.cells, a.reach, a.turns });
        try std.testing.expect(a.cells >= was and a.reach <= heat);
        if (heat == 0) try std.testing.expectEqual(@as(f32, 1), a.cells);
        was = a.cells;
    }
}

test "rain damps every chance to catch, a downpour most" {
    try std.testing.expectEqual(SPREAD, damped(SPREAD, 0));
    const DRIZZLE = @import("climate.zig").DRIZZLE;
    try std.testing.expect(damped(SPREAD, DRIZZLE) < SPREAD and damped(SPREAD, 1) < damped(SPREAD, DRIZZLE));
    var rng = mathx.Rng.init(0x2A1);
    const dry = try average(3, 0, &rng);
    const drizzle = try average(3, DRIZZLE, &rng);
    const downpour = try average(3, 1, &rng);
    std.debug.print("a heat-3 grass fire burns {d:.1} cells dry, {d:.1} in a drizzle, {d:.1} in a downpour; spread {d}%/{d}%/{d}%\n", .{ dry.cells, drizzle.cells, downpour.cells, SPREAD, damped(SPREAD, DRIZZLE), damped(SPREAD, 1) });
    try std.testing.expect(downpour.cells < drizzle.cells and drizzle.cells < dry.cells);
}

test "fire takes grass, reeds, crops and bridges, never bare ground, walls or trees, and boils the water beside it" {
    var rng = mathx.Rng.init(0xB1D6);
    for (std.enums.values(grid.Tile)) |t| {
        var lv = field(.floor);
        lv.set(AT, .grass);
        lv.set(AT.add(.{ .x = 1, .y = 0 }), t);
        lay(&lv, AT, BURNS, 1);
        for (0..TRIES) |_| {
            if (lv.burning(AT.add(.{ .x = 1, .y = 0 }))) break;
            lv.flames[grid.Level.idx(AT)] = BURNS;
            _ = turn(&lv, &rng, 0);
        }
        try std.testing.expectEqual(t.burns(), lv.burning(AT.add(.{ .x = 1, .y = 0 })));
        try std.testing.expectEqual(t.wet(), lv.scalding(AT.add(.{ .x = 1, .y = 0 })));
    }
    for ([_]grid.Tile{ .grass, .reeds, .crop, .bridge, .tall_grass }) |t| try std.testing.expect(t.burns());
    for ([_]grid.Tile{ .floor, .dirt, .wall, .shrub, .swamp_tree, .large_tree, .rock, .water, .shallows }) |t| try std.testing.expect(!t.burns());
}

test "a burning tile smokes, laid flames on bare floor do not, and a fire of no heat stays put" {
    var rng = mathx.Rng.init(0x5A0E);
    var lv = field(.grass);
    const bare = AT.add(.{ .x = 10, .y = 0 });
    lv.set(bare, .floor);
    lay(&lv, AT, BURNS, 0);
    lay(&lv, bare, BURNS, 0);
    _ = turn(&lv, &rng, 0);
    try std.testing.expectEqual(SMOKE, lv.volumeAt(.smoke, AT));
    try std.testing.expectEqual(@as(u16, 0), lv.volumeAt(.smoke, bare));
    try std.testing.expectEqual(@as(usize, 2), grid.CELLS - std.mem.count(u8, &lv.flames, &.{0}));
    for (1..BURNS) |_| _ = turn(&lv, &rng, 0);
    try std.testing.expectEqual(ASH, lv.at(AT));
    try std.testing.expectEqual(grid.Tile.floor, lv.at(bare));
    try std.testing.expect(!lv.burning(AT) and !lv.burning(bare));
}

test "dousing puts out only burning cells, by its chance, and leaves their tiles unburnt" {
    var rng = mathx.Rng.init(0xD0);
    var out: usize = 0;
    for (0..TRIES) |_| {
        var lv = field(.grass);
        lay(&lv, AT, BURNS, 2);
        out += douse(&lv, &.{ AT, AT.add(.{ .x = 1, .y = 0 }) }, 50, &rng);
        try std.testing.expectEqual(grid.Tile.grass, lv.at(AT));
        if (!lv.burning(AT)) try std.testing.expectEqual(@as(u8, 0), lv.heat[grid.Level.idx(AT)]);
    }
    std.debug.print("a 50% douse put out {d}/{d} fires and nothing unlit\n", .{ out, TRIES });
    try std.testing.expect(out > TRIES / 3 and out < TRIES * 2 / 3);
    var lv = field(.grass);
    lay(&lv, AT, BURNS, 2);
    try std.testing.expectEqual(@as(usize, 1), douse(&lv, &.{AT}, mathx.PERCENT, &rng));
    try std.testing.expect(!lv.burning(AT));
    try std.testing.expectEqual(@as(usize, 0), douse(&lv, &.{AT}, mathx.PERCENT, &rng));
}

test "kindling catches only what burns and is not alight, by its chance under the rain" {
    var rng = mathx.Rng.init(0x1D);
    var caught: usize = 0;
    var soaked: usize = 0;
    const k = Kindle{ .chance = 50, .heat = 2 };
    for (0..TRIES) |_| {
        var lv = field(.grass);
        caught += kindle(&lv, &.{AT}, k, 0, &rng);
        var wet = field(.grass);
        soaked += kindle(&wet, &.{AT}, k, 1, &rng);
    }
    std.debug.print("a 50% kindling caught {d}/{d} dry, {d}/{d} in a downpour\n", .{ caught, TRIES, soaked, TRIES });
    try std.testing.expect(caught > TRIES / 3 and caught < TRIES * 2 / 3 and soaked < caught / 2);
    var lv = field(.floor);
    try std.testing.expectEqual(@as(usize, 0), kindle(&lv, &.{AT}, .{ .chance = mathx.PERCENT, .heat = 1 }, 0, &rng));
    lv.set(AT, .grass);
    try std.testing.expectEqual(@as(usize, 1), kindle(&lv, &.{AT}, .{ .chance = mathx.PERCENT, .heat = 1 }, 0, &rng));
    try std.testing.expectEqual(@as(usize, 0), kindle(&lv, &.{AT}, .{ .chance = mathx.PERCENT, .heat = 1 }, 0, &rng));
}
