const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// ADOM's rivers, Diablo II's river and Dry Hills cliff, the River of Flame, a rift.

pub const WIDTH_MAX: u8 = 9;
pub const COUNT_MAX: u8 = 3;
pub const FORDS_MAX: u8 = 6;

pub const Params = struct {
    fill: grid.Tile = .water,
    width: u8 = 3,
    bank: carve.Bank = .shallows,
    course: carve.Course = .any,
    count: u8 = 1,
    /// Crossings laid over it, each a cell wider than it.
    fords: u8 = 0,

    pub fn fit(p: Params) Params {
        var q = p;
        q.width = std.math.clamp(p.width, 1, WIDTH_MAX);
        q.count = std.math.clamp(p.count, 1, COUNT_MAX);
        q.fords = @min(p.fords, FORDS_MAX);
        return q;
    }
};

pub fn apply(lv: *grid.Level, rng: *mathx.Rng, _: u64, pal: carve.Palette, p: Params) void {
    const w: f32 = @floatFromInt(p.width);
    var beds = [_]carve.Bed{.{}} ** COUNT_MAX;
    for (beds[0..p.count]) |*bed| {
        const ends = p.course.ends(rng);
        carve.river(lv, rng, ends[0], ends[1], w, p.fill, p.bank.tile(), bed);
    }
    const across = fordOf(p.fill, pal);
    const bank = p.bank.tile();
    const ford_r: i32 = @intFromFloat(@floor(carve.bankReach(w)));
    const bank_r: i32 = @intFromFloat(@ceil(carve.bankReach(w)));
    for (0..p.fords) |k| {
        const c = fordAt(&beds[k % p.count], rng, bank_r + ford_r) orelse continue;
        var cells = grid.Cells.around(c, bank_r);
        while (cells.next()) |q| {
            if (grid.Level.onRim(q)) continue;
            const t = lv.at(q);
            if (t == p.fill and mathx.dist(q, c) <= ford_r) {
                lv.set(q, across);
            } else if (t == bank and t.solid()) lv.set(q, pal.path);
        }
    }
}

/// A cell of the bed, `clear` cells off the map's edge if the bed has one, so the ford crosses to the map.
fn fordAt(bed: *const carve.Bed, rng: *mathx.Rng, clear: i32) ?mathx.P {
    const cells = bed.cell[0..bed.n];
    if (cells.len == 0) return null;
    return rng.pickWhere(mathx.P, cells, clear, offEdge) orelse cells[rng.below(@intCast(cells.len))];
}

fn offEdge(clear: i32, c: mathx.P) bool {
    return grid.Level.edgeDist(c) > clear;
}

fn fordOf(fill: grid.Tile, pal: carve.Palette) grid.Tile {
    if (fill == .water) return .shallows;
    if (fill.liquid()) return .bridge;
    return pal.path;
}

fn cutOff(maps: usize, p: Params, least: u32) usize {
    var st: carve.Stretches = .{};
    const pal = carve.Palette{ .open = .grass, .solid = .shrub, .path = .dirt };
    var cut: usize = 0;
    for (0..maps) |i| {
        var lv = grid.Level.blank();
        var rng = mathx.Rng.init(i);
        carve.field(&lv, carve.Palette.WILD);
        apply(&lv, &rng, 0, pal, p.fit());
        const sizes = st.size[0..st.label(&lv)];
        const most = st.biggest();
        for (sizes, 0..) |s, r| {
            if (r != most and s >= least) {
                cut += 1;
                break;
            }
        }
    }
    return cut;
}

test "a ford crosses a river's rock bank as it does a walkable one" {
    const RIVERS = 50;
    const tenth = grid.CELLS / 10;
    const rock = cutOff(RIVERS, .{ .bank = .rock, .course = .across, .fords = 1 }, tenth);
    const shallows = cutOff(RIVERS, .{ .bank = .shallows, .course = .across, .fords = 1 }, tenth);
    std.debug.print("{d} rivers, a ford each, still cut off a tenth of the map: {d} banked with rock, {d} with shallows\n", .{ RIVERS, rock, shallows });
    try std.testing.expectEqual(shallows, rock);
}

test "a ford lands off the map's edge whenever its river runs there" {
    var bed = carve.Bed{};
    bed.n = 0;
    var y: i32 = 1;
    while (y < grid.H - 1) : (y += 1) {
        bed.cell[bed.n] = .{ .x = 1, .y = y };
        bed.n += 1;
    }
    bed.cell[bed.n] = grid.MIDDLE;
    bed.n += 1;
    var rng = mathx.Rng.init(0xF0D);
    var hugging: usize = 0;
    for (0..200) |_| {
        if (grid.Level.edgeDist(fordAt(&bed, &rng, 4).?) <= 4) hugging += 1;
    }
    std.debug.print("a bed along the west rim but one cell: 200 fords, {d} against the rim\n", .{hugging});
    try std.testing.expectEqual(@as(usize, 0), hugging);
}

test "a cliff band with a gap leaves the map whole, and a river's ford is shallow" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0xC11F);
    carve.field(&lv, carve.Palette.WILD);
    const pal = carve.Palette{ .open = .grass, .solid = .shrub, .path = .dirt };
    apply(&lv, &rng, 0, pal, .{ .fill = .rock, .bank = .none, .course = .across, .fords = 1 });
    try std.testing.expect(carve.count(&lv, .rock) > grid.W);
    try std.testing.expect(carve.count(&lv, .dirt) > 0);
    apply(&lv, &rng, 0, pal, .{ .course = .down, .fords = 2 });
    std.debug.print("a cliff across and a river down: {d} rock, {d} water, {d} ford shallows and banks\n", .{ carve.count(&lv, .rock), carve.count(&lv, .water), carve.count(&lv, .shallows) });
    try std.testing.expect(carve.count(&lv, .water) > grid.H);
}
