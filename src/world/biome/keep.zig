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
pub const SIZE_MIN = [2]u8{ 24, 18 };
pub const SIZE_MAX = [2]u8{ @intCast(grid.W - 2 * (MOAT_MAX + BERM + towerReach(TOWER_MAX))), @intCast(grid.H - 2 * (MOAT_MAX + BERM + towerReach(TOWER_MAX))) };
pub const BARRELS_MAX: u8 = 24;
/// Cells between the spots along the keep's top wall a torch may hang.
const TORCH_EVERY: i32 = 3;
const TORCHES_MOST = grid.MAX_TORCHES / 2;
const CURTAIN: i32 = 2;
const GATE_W: i32 = 3;
/// The keep's share of the courtyard, and the narrowest room it is cut into.
const KEEP_OF: f32 = 0.5;
const ROOM_LEAST: i32 = 4;
const BERM: i32 = 2;
const TOWER_WALL: i32 = 1;
/// Cells between the well and the courtyard's walls or the keep.
const WELL_GAP: i32 = 2;

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
        q.size = .{ std.math.clamp(p.size[0], SIZE_MIN[0], SIZE_MAX[0]), std.math.clamp(p.size[1], SIZE_MIN[1], SIZE_MAX[1]) };
        q.towers = @min(p.towers, TOWER_MAX);
        q.moat = @min(p.moat, MOAT_MAX);
        q.torches = @min(p.torches, mathx.PERCENT);
        q.barrels = @min(p.barrels, BARRELS_MAX);
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    const g = p.outside.tile();
    return .{ .open = g, .solid = .shrub, .path = .dirt };
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    const pal = palette(p);
    const out = pal.open;
    carve.fill(lv, out);
    carve.rim(lv, pal.solid);
    const curtain = curtainOf(p);
    const lo = curtain.lo;
    const hi = curtain.hi;
    const m: i32 = p.moat;
    const berm = bermOf(p);
    if (m > 0) {
        carve.box(lv, lo.sub(.{ .x = berm + m, .y = berm + m }), hi.add(.{ .x = berm + m, .y = berm + m }), .water);
        carve.box(lv, lo.sub(.{ .x = berm, .y = berm }), hi.add(.{ .x = berm, .y = berm }), out);
    }
    carve.box(lv, lo, hi, .wall);
    const yard_lo = lo.add(.{ .x = CURTAIN, .y = CURTAIN });
    const yard_hi = hi.sub(.{ .x = CURTAIN, .y = CURTAIN });
    carve.box(lv, yard_lo, yard_hi, p.yard.tile());
    const t: f32 = @floatFromInt(p.towers);
    if (p.towers > 0) {
        for (towersOf(curtain)) |c| {
            carve.disc(lv, c, @floatFromInt(towerReach(p.towers)), .wall, null);
            carve.disc(lv, c, t - 0.5, .floor, null);
            const toward = P{ .x = std.math.sign(grid.MIDDLE.x - c.x), .y = std.math.sign(grid.MIDDLE.y - c.y) };
            var q = c;
            for (0..@intCast(towerReach(p.towers) + CURTAIN)) |_| {
                for ([_]P{ .{ .x = toward.x, .y = 0 }, .{ .x = 0, .y = toward.y } }) |d| {
                    q = q.add(d);
                    if (lv.at(q) == .wall) lv.set(q, .floor);
                }
            }
        }
    }
    const across = rng.chance(0.5);
    const mid = grid.MIDDLE;
    for ([_]i32{ -1, 1 }) |side| {
        const gate_at = if (across) P{ .x = if (side < 0) lo.x else hi.x - 1, .y = mid.y } else P{ .x = mid.x, .y = if (side < 0) lo.y else hi.y - 1 };
        const out_dir = if (across) P{ .x = side, .y = 0 } else P{ .x = 0, .y = side };
        const span = P{ .x = if (across) 0 else 1, .y = if (across) 1 else 0 };
        var k: i32 = -CURTAIN - berm - m;
        while (k <= CURTAIN) : (k += 1) {
            var s: i32 = -@divTrunc(GATE_W, 2);
            while (s <= @divTrunc(GATE_W, 2)) : (s += 1) {
                const q = gate_at.add(.{ .x = out_dir.x * -k + span.x * s, .y = out_dir.y * -k + span.y * s });
                const was = lv.at(q);
                lv.set(q, carve.paved(was, if (was == .wall) .floor else was));
            }
        }
    }
    const keep = keepOf(p);
    carve.box(lv, keep.lo, keep.hi, .wall);
    const in = keep.inner();
    carve.box(lv, in.lo, in.hi, .floor);
    lv.set(buildings.doorway(rng, keep)[0], .floor);
    buildings.partition(lv, rng, in, ROOM_LEAST, .wall);
    var torches: usize = 0;
    var x = in.lo.x + 1;
    while (x < in.hi.x - 1) : (x += TORCH_EVERY) {
        if (rng.percent(p.torches) and torches < TORCHES_MOST) {
            lv.addTorch(.{ .x = x, .y = keep.lo.y });
            torches += 1;
        }
    }
    for (0..p.barrels) |_| {
        const q = in.roll(rng);
        if (lv.at(q) == .floor and carve.clearAround(lv, q)) lv.putBarrel(q);
    }
    const art = setpiece.rows(.well);
    const room = setpiece.size(art).add(.{ .x = WELL_GAP, .y = WELL_GAP });
    const well = P{ .x = rng.range(yard_lo.x + WELL_GAP, @max(yard_lo.x + WELL_GAP, keep.lo.x - room.x)), .y = rng.range(yard_lo.y + WELL_GAP, yard_hi.y - room.y) };
    if (keep.lo.x - well.x >= room.x) setpiece.stamp(lv, well, art);
}

/// The curtain wall's outside, in the middle of the map.
fn curtainOf(p: Params) grid.Box {
    return grid.Box.centred(p.size[0], p.size[1]);
}

/// Cells from the curtain out to the moat: the berm runs round the towers' outside.
fn bermOf(p: Params) i32 {
    return BERM + towerReach(p.towers);
}

fn towerReach(towers: u8) i32 {
    return if (towers > 0) @as(i32, towers) + TOWER_WALL else 0;
}

fn towersOf(b: grid.Box) [4]P {
    return .{ b.lo, .{ .x = b.hi.x - 1, .y = b.lo.y }, .{ .x = b.lo.x, .y = b.hi.y - 1 }, b.hi.sub(.{ .x = 1, .y = 1 }) };
}

fn keepOf(p: Params) grid.Box {
    const mid = grid.MIDDLE;
    const kw: i32 = @intFromFloat(@as(f32, @floatFromInt(@as(i32, p.size[0]) - 2 * CURTAIN)) * KEEP_OF);
    const kh: i32 = @intFromFloat(@as(f32, @floatFromInt(@as(i32, p.size[1]) - 2 * CURTAIN)) * KEEP_OF);
    return .{ .lo = .{ .x = mid.x - @divTrunc(kw, 2), .y = mid.y - @divTrunc(kh, 2) }, .hi = .{ .x = mid.x + @divTrunc(kw + 1, 2), .y = mid.y + @divTrunc(kh + 1, 2) } };
}

test "every room of the keep opens onto the yard" {
    const KEEPS = 200;
    var lv = grid.Level.blank();
    var st: carve.Stretches = .{};
    const p = (Params{}).fit();
    const in = keepOf(p).inner();
    var sealed: usize = 0;
    for (0..KEEPS) |i| {
        var rng = mathx.Rng.init(i);
        shape(&lv, &rng, 0, p);
        _ = st.label(&lv);
        const most = st.biggest();
        var cells = in.cells();
        const whole = while (cells.next()) |q| {
            if (!lv.at(q).solid() and st.of(q) != most) break false;
        } else true;
        if (!whole) sealed += 1;
    }
    std.debug.print("{d} keeps: {d} with a room sealed off\n", .{ KEEPS, sealed });
    try std.testing.expectEqual(@as(usize, 0), sealed);
}

test "every corner tower opens onto the yard, however wide" {
    var lv = grid.Level.blank();
    var st: carve.Stretches = .{};
    var sealed: usize = 0;
    var towers: usize = 0;
    for (1..TOWER_MAX + 1) |t| {
        const p = (Params{ .towers = @intCast(t) }).fit();
        var rng = mathx.Rng.init(t);
        shape(&lv, &rng, 0, p);
        _ = st.label(&lv);
        const curtain = curtainOf(p);
        const yard = st.of(.{ .x = grid.MIDDLE.x, .y = curtain.lo.y + CURTAIN });
        for (towersOf(curtain)) |c| {
            towers += 1;
            if (st.of(c) != yard) sealed += 1;
        }
    }
    std.debug.print("{d} corner towers: {d} shut off from the yard\n", .{ towers, sealed });
    try std.testing.expectEqual(@as(usize, 0), sealed);
}

test "a keep's ground is one stretch before joining, its berm running round the towers, at any towers and moat" {
    var lv = grid.Level.blank();
    var st: carve.Stretches = .{};
    var keeps: usize = 0;
    var cut: usize = 0;
    for (0..TOWER_MAX + 1) |t| {
        for (0..MOAT_MAX + 1) |m| {
            for ([_][2]u8{ SIZE_MIN, (Params{}).size, SIZE_MAX }) |size| {
                const p = (Params{ .towers = @intCast(t), .moat = @intCast(m), .size = size }).fit();
                var rng = mathx.Rng.init(t * 31 + m);
                shape(&lv, &rng, 0, p);
                keeps += 1;
                if (st.label(&lv) != 1) cut += 1;
            }
        }
    }
    std.debug.print("{d} keeps: {d} cut into more than one stretch\n", .{ keeps, cut });
    try std.testing.expectEqual(@as(usize, 0), cut);
}

test "a keep stands walled, its gates open through the curtain and over the moat" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xCA57);
    shape(&lv, &rng, 0, (Params{}).fit());
    var st: carve.Stretches = .{};
    const parts = st.label(&lv);
    std.debug.print("a keep: {d} wall, {d} moat, {d} bridge, {d} stretches of ground before joining\n", .{ carve.count(&lv, .wall), carve.count(&lv, .water), carve.count(&lv, .bridge), parts });
    try std.testing.expect(carve.count(&lv, .bridge) >= 2 * 3);
    try std.testing.expect(carve.count(&lv, .wall) > 300);
}
