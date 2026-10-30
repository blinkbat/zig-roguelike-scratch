const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const carve = @import("carve.zig");
const gen = @import("gen.zig");
const damage = @import("../play/damage.zig");

const P = mathx.P;

pub const NAME = "caustic gas";
pub const HEALING_NAME = "healing gas";
pub const STEAM_NAME = "steam";
/// Brogue's `DF_BLOAT_DEATH`.
pub const BURST: u16 = 2000;
/// Brogue's bloodwort pod bursting.
pub const HEALING_BURST: u16 = 350;
/// Brogue updates gas twice a hundred ticks, which is one turn.
pub const PASSES: usize = 2;
/// A cell holding less keeps its gas: it takes from a gassed-up neighbour and gives none on.
pub const GASSED_UP: u16 = 20;
/// The share of passes a cell that held gas loses a unit; Brogue's healing gas dissipates as quickly.
pub const DISSIPATE: f32 = 0.5;
/// Brogue's `T_CAUSES_DAMAGE` and `T_CAUSES_HEALING` alike: a fifteenth of the body's full hp a turn.
const HARM_PART: i32 = 15;
/// What a wet cell gives off where fire lands on it.
pub const BOIL: u16 = 60;
/// Steam also loses this part of each cell's volume a pass, rounded up, so it clears in a few turns.
pub const CONDENSE: u32 = 3;
pub const SCALD: i32 = 2;
const SCALD_ELEMENT: damage.Element = .fire;

pub fn harm(max_hp: i32) i32 {
    return @max(1, @divTrunc(max_hp, HARM_PART));
}

pub fn heal(max_hp: i32) i32 {
    return harm(max_hp);
}

pub fn scald(resists: damage.Resists) i32 {
    return damage.resisted(SCALD, resists.get(SCALD_ELEMENT));
}

/// Steam over each deep water or shallows cell of `cells`; how many boiled.
pub fn boil(lv: *grid.Level, cells: []const P) usize {
    var n: usize = 0;
    for (cells) |p| {
        if (!lv.at(p).wet()) continue;
        lv.release(.steam, p, BOIL);
        n += 1;
    }
    return n;
}

fn any(vol: *const [grid.CELLS]u16) bool {
    return std.mem.indexOfNone(u16, vol, &.{0}) != null;
}

/// A floor without gas rolls nothing.
pub fn turn(lv: *grid.Level, rng: *mathx.Rng) void {
    for (0..PASSES) |_| {
        for (std.enums.values(grid.Gas)) |kind| spread(lv, kind, rng);
    }
}

/// The ground it grew on, under a cloud of healing gas.
pub fn burst(lv: *grid.Level, p: P) bool {
    const t = lv.at(p);
    if (!t.bursts()) return false;
    lv.set(p, t.ground().?);
    lv.release(.healing, p, HEALING_BURST);
    return true;
}

/// Randomly distribute remainders so spreading conserves gas.
fn spread(lv: *grid.Level, kind: grid.Gas, rng: *mathx.Rng) void {
    const vol = lv.volumes(kind);
    const box = reach(vol) orelse return;
    var next = [_]u32{0} ** grid.CELLS;
    var cells = box.cells();
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        const v = vol[i];
        if (v == 0) continue;
        if (v < GASSED_UP) {
            next[i] += v;
            continue;
        }
        var to: [mathx.ALL_DIRS.len + 1]usize = undefined;
        to[0] = i;
        var n: usize = 1;
        for (mathx.ALL_DIRS) |d| {
            const q = p.add(d.delta());
            if (!lv.flat(q)) continue;
            to[n] = grid.Level.idx(q);
            n += 1;
        }
        const share: u32 = v / @as(u32, @intCast(n));
        for (to[0..n]) |t| next[t] += share;
        for (0..v % n) |_| next[rng.pick(usize, to[0..n])] += 1;
    }
    cells = box.cells();
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        if (next[i] > 0 and vol[i] > 0 and rng.chance(DISSIPATE)) next[i] -= 1;
        if (kind == .steam) next[i] -= std.math.divCeil(u32, next[i], CONDENSE) catch unreachable;
        vol[i] = @intCast(@min(next[i], std.math.maxInt(u16)));
    }
}

/// A cell wider than the gas all round; the high corner exclusive.
fn reach(vol: *const [grid.CELLS]u16) ?grid.Box {
    var lo = grid.SIZE;
    var hi = P{ .x = -1, .y = -1 };
    for (vol, 0..) |v, i| {
        if (v == 0) continue;
        const p = grid.Level.of(i);
        lo = lo.min(p);
        hi = hi.max(p);
    }
    if (hi.x < 0) return null;
    return grid.Box.between(lo, hi).grown(1);
}

const Life = struct { turns: usize = 0, most: usize = 0 };

const NEVER: usize = 2000;

fn lasts(lv: *grid.Level, kind: grid.Gas, rng: *mathx.Rng) !Life {
    var life = Life{};
    const vol = lv.volumes(kind);
    while (any(vol)) : (life.turns += 1) {
        if (life.turns == NEVER) return error.NeverClears;
        turn(lv, rng);
        var cells: usize = 0;
        for (vol, lv.tile) |v, t| {
            if (v == 0) continue;
            if (t.upright()) return error.GasInWall;
            cells += 1;
        }
        life.most = @max(life.most, cells);
    }
    return life;
}

const OPEN_AT = grid.MIDDLE;

fn onOpenFloor(rng: *mathx.Rng) !Life {
    var lv = grid.openFloor();
    lv.addGas(OPEN_AT, BURST);
    return lasts(&lv, .caustic, rng);
}

test "a gassed-up cell shares its gas evenly with its open neighbours, and a thinner one keeps its own" {
    var rng = mathx.Rng.init(0x6A5);
    const at = P{ .x = 20, .y = 20 };
    var lv = grid.openFloor();
    lv.addGas(at, 9 * 100);
    spread(&lv, .caustic, &rng);
    for (mathx.ALL_DIRS) |d| try std.testing.expectEqual(@as(u16, 100), lv.gasAt(at.add(d.delta())));
    try std.testing.expect(lv.gasAt(at) >= 99);
    var thin = grid.openFloor();
    thin.addGas(at, GASSED_UP - 1);
    spread(&thin, .caustic, &rng);
    for (mathx.ALL_DIRS) |d| try std.testing.expectEqual(@as(u16, 0), thin.gasAt(at.add(d.delta())));
    try std.testing.expect(thin.gasAt(at) >= GASSED_UP - 2);
}

test "a burst shut in a room lingers, and on open floor clears sooner and spreads only as far as it stays gassed up" {
    var rng = mathx.Rng.init(0x6A5);
    var shut = grid.Level.blank();
    const room = gen.Room.sized(.{ .x = 10, .y = 10 }, 9, 6);
    carve.box(&shut, room, .floor);
    shut.addGas(room.centre(), BURST);
    const a = try lasts(&shut, .caustic, &rng);
    const b = try onOpenFloor(&rng);
    std.debug.print("a bloat's burst: shut in a 9x6 room it lasts {d} turns over at most {d} cells, on open floor {d} turns over at most {d}\n", .{ a.turns, a.most, b.turns, b.most });
    try std.testing.expectEqual(@as(usize, @intCast(room.width() * room.height())), a.most);
    try std.testing.expect(a.turns > b.turns);
    try std.testing.expect(b.most < BURST / GASSED_UP * 2);
}

test "a burst in a room of a real floor leaks out of its doorways: sooner gone than shut in, later than in the open" {
    var rng = mathx.Rng.init(0xB10A7);
    var lv: grid.Level = undefined;
    var shut: grid.Level = undefined;
    const FLOORS: usize = 20;
    var real: usize = 0;
    var sealed: usize = 0;
    for (0..FLOORS) |i| {
        const f = gen.build(&lv, 0x6A5 +% i *% grid.TEST_SEED_STRIDE);
        const r = f.rooms[1];
        lv.addGas(r.centre(), BURST);
        real += (try lasts(&lv, .caustic, &rng)).turns;
        shut = grid.Level.blank();
        carve.box(&shut, r, .floor);
        shut.addGas(r.centre(), BURST);
        sealed += (try lasts(&shut, .caustic, &rng)).turns;
    }
    const open = (try onOpenFloor(&rng)).turns;
    std.debug.print("{d} floors, a burst in a room's middle: gone in {d} turns on average, {d} with the same rooms shut, {d} on open floor\n", .{ FLOORS, real / FLOORS, sealed / FLOORS, open });
    try std.testing.expect(real < sealed);
    try std.testing.expect(real > open * FLOORS);
}

test "gas drifts over a river to the bank across it" {
    var rng = mathx.Rng.init(0x6A5);
    var lv = grid.openFloor();
    const at = P{ .x = 20, .y = 20 };
    var y: i32 = 0;
    while (y < grid.H) : (y += 1) {
        for (0..3) |k| lv.set(.{ .x = 22 + @as(i32, @intCast(k)), .y = y }, .water);
    }
    lv.addGas(at, BURST);
    const across = P{ .x = 25, .y = 20 };
    var turns: usize = 0;
    while (!lv.gassy(across) and any(&lv.gas)) : (turns += 1) turn(&lv, &rng);
    std.debug.print("a burst two cells from a 3-wide river reaches the far bank in {d} turns\n", .{turns});
    try std.testing.expect(lv.gassy(across));
}

test "gas eats a fifteenth of full hp a turn and never less than one" {
    try std.testing.expectEqual(@as(i32, 1), harm(4));
    try std.testing.expectEqual(@as(i32, 1), harm(24));
    try std.testing.expectEqual(@as(i32, 2), harm(40));
    try std.testing.expectEqual(@as(i32, 2), heal(40));
}

test "a glow plant bursts into healing gas over its grass, which spreads and clears apart from caustic gas" {
    var rng = mathx.Rng.init(0x6A5);
    var lv = grid.openFloor();
    const at = OPEN_AT;
    lv.set(at, .glow_plant);
    try std.testing.expect(!burst(&lv, at.add(.{ .x = 1, .y = 0 })));
    try std.testing.expect(burst(&lv, at));
    try std.testing.expectEqual(grid.Tile.grass, lv.at(at));
    try std.testing.expectEqual(HEALING_BURST, lv.volumeAt(.healing, at));
    try std.testing.expect(!lv.gassy(at));
    var turns: usize = 0;
    var most: usize = 0;
    while (any(&lv.healing)) : (turns += 1) {
        try std.testing.expect(turns < NEVER);
        turn(&lv, &rng);
        try std.testing.expect(!any(&lv.gas));
        most = @max(most, grid.CELLS - std.mem.count(u16, &lv.healing, &.{0}));
    }
    std.debug.print("a glow plant's healing gas on open floor: gone in {d} turns, over at most {d} cells\n", .{ turns, most });
    try std.testing.expect(turns > 5 and most > 9);
}

test "fire boils deep water and shallows into steam, and dry ground into nothing" {
    var lv = grid.openFloor();
    const cells = [_]P{ OPEN_AT, OPEN_AT.add(.{ .x = 1, .y = 0 }), OPEN_AT.add(.{ .x = 2, .y = 0 }) };
    lv.set(cells[0], .water);
    lv.set(cells[1], .shallows);
    try std.testing.expectEqual(@as(usize, 2), boil(&lv, &cells));
    try std.testing.expectEqual(BOIL, lv.volumeAt(.steam, cells[0]));
    try std.testing.expectEqual(BOIL, lv.volumeAt(.steam, cells[1]));
    try std.testing.expect(!lv.scalding(cells[2]) and !lv.gassy(cells[0]));
}

test "steam boiled off a lake clears in a few turns, far sooner than as much healing gas" {
    var rng = mathx.Rng.init(0x6A5);
    var lake = grid.openFloor();
    var water = grid.Cells.around(OPEN_AT, 3);
    while (water.next()) |p| lake.set(p, .water);
    var blast: [@intCast(grid.Cells.square(1))]P = undefined;
    var n: usize = 0;
    var cells = grid.Cells.around(OPEN_AT, 1);
    while (cells.next()) |p| : (n += 1) blast[n] = p;
    try std.testing.expectEqual(blast.len, boil(&lake, &blast));
    const steam = try lasts(&lake, .steam, &rng);
    var pool = grid.openFloor();
    pool.set(OPEN_AT, .shallows);
    _ = boil(&pool, &.{OPEN_AT});
    const lone = try lasts(&pool, .steam, &rng);
    var same = grid.openFloor();
    for (blast) |p| same.release(.healing, p, BOIL);
    const healing = try lasts(&same, .healing, &rng);
    std.debug.print("steam: a 3x3 blast on a lake gone in {d} turns over at most {d} cells, one boiled cell in {d}; as much healing gas lasts {d}\n", .{ steam.turns, steam.most, lone.turns, healing.turns });
    try std.testing.expect(steam.turns * 3 < healing.turns);
    try std.testing.expect(lone.turns < steam.turns);
}

test "steam scalds for a little fire damage, less in water, none to the fireproof" {
    try std.testing.expectEqual(SCALD, scald(.initFill(0)));
    try std.testing.expectEqual(@as(i32, 1), scald(.initDefault(0, .{ .fire = 25 })));
    try std.testing.expectEqual(@as(i32, 0), scald(.initDefault(0, .{ .fire = 100 })));
    try std.testing.expectEqual(@as(i32, 3), scald(.initDefault(0, .{ .fire = -50 })));
}
