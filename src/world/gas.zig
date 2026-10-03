const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const gen = @import("gen.zig");

const P = mathx.P;

/// Brogue's `DF_BLOAT_DEATH`.
pub const BURST: u16 = 2000;
/// Brogue updates gas twice a hundred ticks, which is one turn.
pub const PASSES: usize = 2;
/// A cell holding less keeps its gas: it takes from a gassed-up neighbour and gives none on.
pub const GASSED_UP: u16 = 20;
/// The share of passes a cell that held gas loses a unit; Brogue's `TM_GAS_DISSIPATES` is 0.2.
pub const DISSIPATE: f32 = 0.5;
/// Brogue's `T_CAUSES_DAMAGE`: a fifteenth of the body's full hp a turn.
const HARM_PART: i32 = 15;

pub fn harm(max_hp: i32) i32 {
    return @max(1, @divTrunc(max_hp, HARM_PART));
}

fn any(lv: *const grid.Level) bool {
    return std.mem.indexOfNone(u16, &lv.gas, &.{0}) != null;
}

/// A floor without gas rolls nothing.
pub fn turn(lv: *grid.Level, rng: *mathx.Rng) void {
    for (0..PASSES) |_| spread(lv, rng);
}

/// What a gassed-up cell cannot share evenly goes a unit at a time to any of its cells at random, so spreading loses none.
fn spread(lv: *grid.Level, rng: *mathx.Rng) void {
    const box = reach(lv) orelse return;
    var next = [_]u32{0} ** grid.CELLS;
    var cells = grid.Cells.of(box[0], box[1]);
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        const v = lv.gas[i];
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
            if (!lv.walkable(q)) continue;
            to[n] = grid.Level.idx(q);
            n += 1;
        }
        const share: u32 = v / @as(u32, @intCast(n));
        for (to[0..n]) |t| next[t] += share;
        for (0..v % n) |_| next[to[rng.below(@intCast(n))]] += 1;
    }
    cells = grid.Cells.of(box[0], box[1]);
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        if (next[i] > 0 and lv.gas[i] > 0 and rng.chance(DISSIPATE)) next[i] -= 1;
        lv.gas[i] = @intCast(@min(next[i], std.math.maxInt(u16)));
    }
}

/// The box round every cell holding gas, a cell wider all round, up to but not including its high corner.
fn reach(lv: *const grid.Level) ?[2]P {
    var lo = P{ .x = grid.W, .y = grid.H };
    var hi = P{ .x = -1, .y = -1 };
    for (&lv.gas, 0..) |v, i| {
        if (v == 0) continue;
        const p = grid.Level.of(i);
        lo = .{ .x = @min(lo.x, p.x), .y = @min(lo.y, p.y) };
        hi = .{ .x = @max(hi.x, p.x), .y = @max(hi.y, p.y) };
    }
    if (hi.x < 0) return null;
    return grid.grown(lo, hi.add(.{ .x = 1, .y = 1 }), 1);
}

const Life = struct { turns: usize = 0, most: usize = 0 };

const NEVER: usize = 2000;

fn lasts(lv: *grid.Level, rng: *mathx.Rng) !Life {
    var life = Life{};
    while (any(lv)) : (life.turns += 1) {
        if (life.turns == NEVER) return error.NeverClears;
        turn(lv, rng);
        var cells: usize = 0;
        for (lv.gas, lv.tile) |v, t| {
            if (v == 0) continue;
            if (t.solid()) return error.GasInWall;
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
    return lasts(&lv, rng);
}

test "a gassed-up cell shares its gas evenly with its open neighbours, and a thinner one keeps its own" {
    var rng = mathx.Rng.init(0x6A5);
    const at = P{ .x = 20, .y = 20 };
    var lv = grid.openFloor();
    lv.addGas(at, 9 * 100);
    spread(&lv, &rng);
    for (mathx.ALL_DIRS) |d| try std.testing.expectEqual(@as(u16, 100), lv.gasAt(at.add(d.delta())));
    try std.testing.expect(lv.gasAt(at) >= 99);
    var thin = grid.openFloor();
    thin.addGas(at, GASSED_UP - 1);
    spread(&thin, &rng);
    for (mathx.ALL_DIRS) |d| try std.testing.expectEqual(@as(u16, 0), thin.gasAt(at.add(d.delta())));
    try std.testing.expect(thin.gasAt(at) >= GASSED_UP - 2);
}

test "a burst shut in a room lingers, and on open floor clears sooner and spreads only as far as it stays gassed up" {
    var rng = mathx.Rng.init(0x6A5);
    var shut = grid.Level.blank();
    const room = gen.Room.sized(.{ .x = 10, .y = 10 }, 9, 6);
    gen.carveRoom(&shut, room);
    shut.addGas(room.centre(), BURST);
    const a = try lasts(&shut, &rng);
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
        const f = gen.build(&lv, 0x6A5 +% i *% 7919);
        const r = f.rooms[1];
        lv.addGas(r.centre(), BURST);
        real += (try lasts(&lv, &rng)).turns;
        shut = grid.Level.blank();
        gen.carveRoom(&shut, r);
        shut.addGas(r.centre(), BURST);
        sealed += (try lasts(&shut, &rng)).turns;
    }
    const open = (try onOpenFloor(&rng)).turns;
    std.debug.print("{d} floors, a burst in a room's middle: gone in {d} turns on average, {d} with the same rooms shut, {d} on open floor\n", .{ FLOORS, real / FLOORS, sealed / FLOORS, open });
    try std.testing.expect(real < sealed);
    try std.testing.expect(real > open * FLOORS);
}

test "gas eats a fifteenth of full hp a turn and never less than one" {
    try std.testing.expectEqual(@as(i32, 1), harm(4));
    try std.testing.expectEqual(@as(i32, 1), harm(24));
    try std.testing.expectEqual(@as(i32, 2), harm(40));
}
