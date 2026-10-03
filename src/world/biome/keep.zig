const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");
const buildings = @import("../feature/buildings.zig");
const setpiece = @import("../feature/setpiece.zig");

// Dwarf Fortress's keeps, Diablo II's Monastery and Barracks, Qud's snapjaw forts.

const P = mathx.P;

pub const TOWER_MAX: u8 = 6;
pub const MOAT_MAX: u8 = 4;
const CURTAIN: i32 = 2;
const GATE_W: i32 = 3;
/// The keep's share of the courtyard, and the narrowest room it is cut into.
const KEEP_OF: f32 = 0.5;
const ROOM_LEAST: i32 = 4;
const BERM: i32 = 2;

pub const Params = struct {
    /// The curtain's width and height.
    size: [2]u8 = .{ 60, 36 },
    /// A corner tower's half-width; 0 has none.
    towers: u8 = 3,
    moat: u8 = 2,
    yard: carve.Ground = .dirt,
    outside: carve.Ground = .grass,
    torches: u8 = 60,
    barrels: u8 = 6,

    pub fn fit(p: Params) Params {
        var q = p;
        const room = 2 * (MOAT_MAX + BERM + TOWER_MAX + 1);
        q.size = .{ std.math.clamp(p.size[0], 24, @as(u8, @intCast(grid.W - room))), std.math.clamp(p.size[1], 18, @as(u8, @intCast(grid.H - room))) };
        q.towers = @min(p.towers, TOWER_MAX);
        q.moat = @min(p.moat, MOAT_MAX);
        q.torches = @min(p.torches, mathx.PERCENT);
        q.barrels = @min(p.barrels, 24);
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    const g = p.outside.tile();
    return .{ .open = g, .solid = .shrub, .path = .dirt };
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    const out = p.outside.tile();
    carve.fill(lv, out);
    carve.rim(lv, .shrub);
    const w: i32 = p.size[0];
    const h: i32 = p.size[1];
    const lo = P{ .x = @divTrunc(grid.W - w, 2), .y = @divTrunc(grid.H - h, 2) };
    const hi = lo.add(.{ .x = w, .y = h });
    const m: i32 = p.moat;
    if (m > 0) {
        carve.box(lv, lo.sub(.{ .x = BERM + m, .y = BERM + m }), hi.add(.{ .x = BERM + m, .y = BERM + m }), .water);
        carve.box(lv, lo.sub(.{ .x = BERM, .y = BERM }), hi.add(.{ .x = BERM, .y = BERM }), out);
    }
    carve.box(lv, lo, hi, .wall);
    const yard_lo = lo.add(.{ .x = CURTAIN, .y = CURTAIN });
    const yard_hi = hi.sub(.{ .x = CURTAIN, .y = CURTAIN });
    carve.box(lv, yard_lo, yard_hi, p.yard.tile());
    const t: f32 = @floatFromInt(p.towers);
    if (p.towers > 0) {
        for ([_]P{ lo, .{ .x = hi.x - 1, .y = lo.y }, .{ .x = lo.x, .y = hi.y - 1 }, hi.sub(.{ .x = 1, .y = 1 }) }) |c| {
            carve.disc(lv, c, t + 1, .wall, null);
            carve.disc(lv, c, t - 0.5, .floor, null);
            const toward = P{ .x = std.math.sign(grid.MIDDLE.x - c.x), .y = std.math.sign(grid.MIDDLE.y - c.y) };
            var q = c;
            for (0..@intCast(p.towers + CURTAIN + 1)) |_| {
                q = q.add(toward);
                if (lv.at(q) == .wall) lv.set(q, .floor);
            }
        }
    }
    const across = rng.chance(0.5);
    const mid = grid.MIDDLE;
    for ([_]i32{ -1, 1 }) |side| {
        const gate_at = if (across) P{ .x = if (side < 0) lo.x else hi.x - 1, .y = mid.y } else P{ .x = mid.x, .y = if (side < 0) lo.y else hi.y - 1 };
        const out_dir = if (across) P{ .x = side, .y = 0 } else P{ .x = 0, .y = side };
        const span = P{ .x = if (across) 0 else 1, .y = if (across) 1 else 0 };
        var k: i32 = -CURTAIN - BERM - m;
        while (k <= CURTAIN) : (k += 1) {
            var s: i32 = -@divTrunc(GATE_W, 2);
            while (s <= @divTrunc(GATE_W, 2)) : (s += 1) {
                const q = gate_at.add(.{ .x = out_dir.x * -k + span.x * s, .y = out_dir.y * -k + span.y * s });
                const was = lv.at(q);
                lv.set(q, if (was == .water) .bridge else if (was == .wall) .floor else was);
            }
        }
    }
    const yw = yard_hi.x - yard_lo.x;
    const yh = yard_hi.y - yard_lo.y;
    const kw: i32 = @intFromFloat(@as(f32, @floatFromInt(yw)) * KEEP_OF);
    const kh: i32 = @intFromFloat(@as(f32, @floatFromInt(yh)) * KEEP_OF);
    const keep = buildings.Box{ .lo = .{ .x = mid.x - @divTrunc(kw, 2), .y = mid.y - @divTrunc(kh, 2) }, .hi = .{ .x = mid.x + @divTrunc(kw + 1, 2), .y = mid.y + @divTrunc(kh + 1, 2) } };
    carve.box(lv, keep.lo, keep.hi, .wall);
    const in = keep.inner();
    carve.box(lv, in.lo, in.hi, .floor);
    buildings.partition(lv, rng, in, ROOM_LEAST, .wall);
    const way = buildings.doorway(rng, keep);
    lv.set(way[0], .floor);
    var torches: usize = 0;
    var x = in.lo.x + 1;
    while (x < in.hi.x - 1) : (x += 3) {
        if (carve.percent(rng, p.torches) and torches < grid.MAX_TORCHES / 2) {
            lv.addTorch(.{ .x = x, .y = keep.lo.y });
            torches += 1;
        }
    }
    for (0..p.barrels) |_| {
        const q = P{ .x = rng.range(in.lo.x, in.hi.x - 1), .y = rng.range(in.lo.y, in.hi.y - 1) };
        if (lv.at(q) == .floor and carve.clearAround(lv, q)) lv.putBarrel(q);
    }
    const well = P{ .x = rng.range(yard_lo.x + 2, @max(yard_lo.x + 2, keep.lo.x - 7)), .y = rng.range(yard_lo.y + 2, yard_hi.y - 7) };
    if (keep.lo.x - well.x > 6) setpiece.stamp(lv, well, setpiece.rows(.well));
}

test "a keep stands walled, its gates open through the curtain and over the moat" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xCA57);
    shape(&lv, &rng, 0, (Params{}).fit());
    var region: [grid.CELLS]u16 = undefined;
    var size: [grid.CELLS]u32 = undefined;
    var queue: [grid.CELLS]u32 = undefined;
    const parts = carve.label(&lv, &region, &size, &queue);
    std.debug.print("a keep: {d} wall, {d} moat, {d} bridge, {d} stretches of ground before joining\n", .{ carve.count(&lv, .wall), carve.count(&lv, .water), carve.count(&lv, .bridge), parts });
    try std.testing.expect(carve.count(&lv, .bridge) >= 2 * 3);
    try std.testing.expect(carve.count(&lv, .wall) > 300);
}
