const std = @import("std");
const mathx = @import("../core/mathx.zig");
const grid = @import("grid.zig");
const gen = @import("gen.zig");

// EVERY GAS, Brogue CE's `updateVolumetricMedia` for one gas. The loss is per cell, so a cloud spread thin over open
// ground clears fast and one shut in a room lingers.

const P = mathx.P;

/// Brogue's `DF_BLOAT_DEATH`.
pub const BURST: u16 = 2000;
/// Brogue updates gas twice a hundred ticks, which is one turn.
pub const PASSES: usize = 2;
/// Brogue's `TM_GAS_DISSIPATES`.
pub const DISSIPATE: f32 = 0.2;
/// Brogue's `T_CAUSES_DAMAGE`: a fifteenth of the body's full hp a turn.
const HARM_PART: i32 = 15;

pub fn harm(max_hp: i32) i32 {
    return @max(1, @divTrunc(max_hp, HARM_PART));
}

pub fn any(lv: *const grid.Level) bool {
    return std.mem.indexOfNone(u16, &lv.gas, &.{0}) != null;
}

/// A floor without gas rolls nothing.
pub fn turn(lv: *grid.Level, rng: *mathx.Rng) void {
    for (0..PASSES) |_| spread(lv, rng);
}

/// Row by row as Brogue goes, over only the cells a pass can reach: past them every sum is 0 and nothing is rolled.
fn spread(lv: *grid.Level, rng: *mathx.Rng) void {
    const box = reach(lv) orelse return;
    var next = [_]u16{0} ** grid.CELLS;
    var y = box[0].y;
    while (y <= box[1].y) : (y += 1) {
        var x = box[0].x;
        while (x <= box[1].x) : (x += 1) {
            const p = P{ .x = x, .y = y };
            const i = grid.Level.idx(p);
            if (lv.tile[i].solid()) continue;
            const own = lv.gas[i];
            var sum: u32 = own;
            var n: u32 = 1;
            for (mathx.ALL_DIRS) |d| {
                const q = p.add(d.delta());
                if (!lv.walkable(q)) continue;
                sum += lv.gasAt(q);
                n += 1;
            }
            if (sum == 0) continue;
            var v = sum / n;
            if (rng.below(n) < sum % n) v += 1;
            if (v > 0 and own > 0 and rng.chance(DISSIPATE)) v -= 1;
            next[i] = @intCast(v);
        }
    }
    lv.gas = next;
}

/// The corners of the box round every cell holding gas, a cell wider all round.
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
    return .{
        .{ .x = @max(0, lo.x - 1), .y = @max(0, lo.y - 1) },
        .{ .x = @min(grid.W - 1, hi.x + 1), .y = @min(grid.H - 1, hi.y + 1) },
    };
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

const OPEN_AT = P{ .x = @divTrunc(grid.W, 2), .y = @divTrunc(grid.H, 2) };

fn onOpenFloor(rng: *mathx.Rng) !Life {
    var lv = grid.openFloor();
    lv.addGas(OPEN_AT, BURST);
    return lasts(&lv, rng);
}

test "a burst shut in a room lingers, and on open floor thins out and clears far sooner" {
    var rng = mathx.Rng.init(0x6A5);
    var shut = grid.Level.blank();
    const room = gen.Room{ .x = 10, .y = 10, .w = 9, .h = 6 };
    gen.carveRoom(&shut, room);
    shut.addGas(room.centre(), BURST);
    const a = try lasts(&shut, &rng);
    const b = try onOpenFloor(&rng);
    std.debug.print("a bloat's burst: shut in a 9x6 room it lasts {d} turns over at most {d} cells, on open floor {d} turns over at most {d}\n", .{ a.turns, a.most, b.turns, b.most });
    try std.testing.expectEqual(@as(usize, @intCast(room.w * room.h)), a.most);
    try std.testing.expect(a.turns > b.turns * 2);
    try std.testing.expect(b.most > a.most * 4);
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
