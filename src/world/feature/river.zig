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
    var bed = carve.Bed{};
    for (0..p.count) |_| {
        const ends = p.course.ends(rng);
        carve.river(lv, rng, ends[0], ends[1], w, p.fill, p.bank.tile(), &bed);
    }
    if (bed.n == 0) return;
    const across = fordOf(p.fill, pal);
    const bank = p.bank.tile();
    const ford_r = @divTrunc(@as(i32, p.width), 2) + 1;
    const bank_r: i32 = @intFromFloat(@ceil(carve.bankReach(w)));
    for (0..p.fords) |_| {
        const c = bed.cell[rng.below(@intCast(bed.n))];
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

fn fordOf(fill: grid.Tile, pal: carve.Palette) grid.Tile {
    if (fill == .water) return .shallows;
    if (fill.liquid()) return .bridge;
    return pal.path;
}

/// Of `rivers` laid one to a fresh map with a ford, how many leave a tenth of the ground cut off.
fn cutOff(rivers: usize, bank: carve.Bank) usize {
    var st: carve.Stretches = .{};
    const pal = carve.Palette{ .open = .grass, .solid = .shrub, .path = .dirt };
    var cut: usize = 0;
    for (0..rivers) |i| {
        var lv = grid.Level.blank();
        var rng = mathx.Rng.init(i);
        carve.field(&lv, carve.Palette.WILD);
        apply(&lv, &rng, 0, pal, (Params{ .bank = bank, .course = .across, .fords = 1 }).fit());
        const sizes = st.size[0..st.label(&lv)];
        const most = st.biggest();
        var ground: u32 = 0;
        for (sizes) |s| ground += s;
        for (sizes, 0..) |s, r| {
            if (r != most and s * 10 > ground) {
                cut += 1;
                break;
            }
        }
    }
    return cut;
}

test "a ford crosses a river's rock bank as it does a walkable one" {
    const RIVERS = 50;
    const rock = cutOff(RIVERS, .rock);
    const shallows = cutOff(RIVERS, .shallows);
    std.debug.print("{d} rivers, a ford each, still cut off a tenth of the map: {d} banked with rock, {d} with shallows\n", .{ RIVERS, rock, shallows });
    try std.testing.expectEqual(shallows, rock);
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
