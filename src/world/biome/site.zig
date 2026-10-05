const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../grid.zig");
const carve = @import("../carve.zig");

// Qud's historic sites: sectioned first (Bucklew's fix for WFC's sameness), each section grown by overlapping WFC, N=3.

const P = mathx.P;

const N: usize = 3;
const PATTERNS_MAX: usize = 128;
const Bits = std.StaticBitSet(PATTERNS_MAX);
const SECTION_W: i32 = 30;
const SECTION_H: i32 = 20;
const SECTION_MIN: i32 = 10;
const STREET: i32 = 2;
const MARGIN: i32 = 2;
const ATTEMPTS: usize = 12;
/// In `grid.Tile.letter`'s legend; grass stands for the site's ground.
const SYMBOLS = "\"#.";

comptime {
    for (SYMBOLS) |c| std.debug.assert(grid.Tile.ofLetter(c) != null);
}

pub const Template = enum { huts, compound, pillars, mixed };

const HUTS = [_][]const u8{
    "\"\"\"\"\"\"\"\"\"\"\"\"\"\"",
    "\"#####\"\"\"\"\"\"\"\"",
    "\"#...#\"\"####\"\"",
    "\"#...#\"\"#..#\"\"",
    "\"##.##\"\"#..#\"\"",
    "\"\"\"\"\"\"\"\"##.#\"\"",
    "\"\"\"\"\"\"\"\"\"\"\"\"\"\"",
    "\"\"####\"\"\"\"\"\"\"\"",
    "\"\"#..#\"\"#####\"",
    "\"\"#...\"\"#...#\"",
    "\"\"####\"\"#...#\"",
    "\"\"\"\"\"\"\"\"##.##\"",
    "\"\"\"\"\"\"\"\"\"\"\"\"\"\"",
};

const COMPOUND = [_][]const u8{
    "\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"",
    "\"##############\"",
    "\"#.....#......#\"",
    "\"#.....#......#\"",
    "\"#............#\"",
    "\"#.....#......#\"",
    "\"###.######.###\"",
    "\"#.....#......#\"",
    "\"#............#\"",
    "\"#.....#......#\"",
    "\"######.#######\"",
    "\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"",
};

const PILLARS = [_][]const u8{
    "\"\"\"\"\"\"\"\"\"\"\"\"",
    "\"##########\"",
    "\"#........#\"",
    "\"#.#.#.#..#\"",
    "\"#........#\"",
    "\"#.#.#.#..#\"",
    "\"#.........\"",
    "\"##########\"",
    "\"\"\"\"\"\"\"\"\"\"\"\"",
};

pub const Params = struct {
    template: Template = .mixed,
    /// Percent of wall fallen to rubble.
    decay: u8 = 20,
    ground: carve.Ground = .grass,

    pub fn fit(p: Params) Params {
        var q = p;
        q.decay = @min(p.decay, mathx.PERCENT);
        return q;
    }
};

pub fn palette(p: Params) carve.Palette {
    const g = p.ground.tile();
    return .{ .open = g, .solid = .shrub, .path = g };
}

const Pattern = [N * N]u8;

/// Every N x N window, wrapping round its edges as Qud reads its own, in all eight rotations and reflections, counted.
const Model = struct {
    pat: [PATTERNS_MAX]Pattern = undefined,
    weight: [PATTERNS_MAX]u32 = undefined,
    n: usize = 0,
    /// `fits[p][d]`: the patterns that may sit one step in direction `d` from `p`.
    fits: [PATTERNS_MAX][4]Bits = undefined,
    /// `fits` of every pattern together, each way: what a cell any pattern may yet be allows its neighbours.
    any: [4]Bits = @splat(Bits.initEmpty()),

    fn of(art: []const []const u8) Model {
        var m = Model{};
        const h = art.len;
        const w = art[0].len;
        for (0..h) |y| {
            for (0..w) |x| {
                var base: Pattern = undefined;
                for (0..N) |dy| {
                    for (0..N) |dx| base[dy * N + dx] = symbol(art[(y + dy) % h][(x + dx) % w]);
                }
                var p = base;
                for (0..8) |k| {
                    m.add(p);
                    p = if (k == 3) reflect(base) else rotate(p);
                }
            }
        }
        for (0..m.n) |a| {
            for (DIRS, 0..) |d, k| {
                m.fits[a][k] = Bits.initEmpty();
                for (0..m.n) |b| {
                    if (agrees(m.pat[a], m.pat[b], d.x, d.y)) m.fits[a][k].set(b);
                }
                m.any[k].setUnion(m.fits[a][k]);
            }
        }
        return m;
    }

    fn add(m: *Model, p: Pattern) void {
        for (m.pat[0..m.n], 0..) |q, i| {
            if (std.mem.eql(u8, &q, &p)) {
                m.weight[i] += 1;
                return;
            }
        }
        if (m.n == PATTERNS_MAX) return;
        m.pat[m.n] = p;
        m.weight[m.n] = 1;
        m.n += 1;
    }
};

const DIRS = mathx.CARDINALS;

fn symbol(c: u8) u8 {
    return @intCast(std.mem.indexOfScalar(u8, SYMBOLS, c) orelse 0);
}

fn rotate(p: Pattern) Pattern {
    var q: Pattern = undefined;
    for (0..N) |y| {
        for (0..N) |x| q[y * N + x] = p[(N - 1 - x) * N + y];
    }
    return q;
}

fn reflect(p: Pattern) Pattern {
    var q: Pattern = undefined;
    for (0..N) |y| {
        for (0..N) |x| q[y * N + x] = p[y * N + (N - 1 - x)];
    }
    return q;
}

/// `b` set `dx, dy` from `a` agrees with it wherever the two overlap.
fn agrees(a: Pattern, b: Pattern, dx: i32, dy: i32) bool {
    const n: i32 = N;
    var y: i32 = @max(0, dy);
    while (y < @min(n, n + dy)) : (y += 1) {
        var x: i32 = @max(0, dx);
        while (x < @min(n, n + dx)) : (x += 1) {
            const ai: usize = @intCast(y * n + x);
            const bi: usize = @intCast((y - dy) * n + (x - dx));
            if (a[ai] != b[bi]) return false;
        }
    }
    return true;
}

const CELLS_MAX: usize = @intCast(SECTION_W * SECTION_H);

/// Each cell's pattern's top-left symbol into `out`; false on a contradiction.
fn solve(m: *const Model, rng: *mathx.Rng, w: usize, h: usize, out: *[CELLS_MAX]u8) bool {
    var wave: [CELLS_MAX]Bits = undefined;
    var all = Bits.initEmpty();
    for (0..m.n) |i| all.set(i);
    for (wave[0 .. w * h]) |*c| c.* = all;
    var stack: [CELLS_MAX]u16 = undefined;
    var queued = std.StaticBitSet(CELLS_MAX).initEmpty();
    while (true) {
        var best: ?usize = null;
        var best_e: f32 = std.math.floatMax(f32);
        for (0..w * h) |i| {
            const k = wave[i].count();
            if (k == 0) return false;
            if (k == 1) continue;
            const e = @as(f32, @floatFromInt(k)) + rng.unit() * 0.5;
            if (e < best_e) {
                best_e = e;
                best = i;
            }
        }
        const cell = best orelse break;
        const Open = struct {
            m: *const Model,
            wave: *const Bits,

            fn weight(o: @This(), p: usize) u32 {
                return if (o.wave.isSet(p)) o.m.weight[p] else 0;
            }
        };
        const chosen = rng.weighted(m.n, Open{ .m = m, .wave = &wave[cell] }, Open.weight).?;
        wave[cell] = Bits.initEmpty();
        wave[cell].set(chosen);
        var top: usize = 1;
        stack[0] = @intCast(cell);
        queued.set(cell);
        while (top > 0) {
            top -= 1;
            const c = stack[top];
            queued.unset(c);
            const cx: i32 = @intCast(c % w);
            const cy: i32 = @intCast(c / w);
            var allowed = m.any;
            if (!wave[c].eql(all)) {
                allowed = @splat(Bits.initEmpty());
                var pi = wave[c].iterator(.{});
                while (pi.next()) |p| {
                    for (&allowed, m.fits[p]) |*a, f| a.setUnion(f);
                }
            }
            for (DIRS, 0..) |d, k| {
                const ni = mathx.slot(cx + d.x, cy + d.y, w, h) orelse continue;
                const now = wave[ni].intersectWith(allowed[k]);
                if (now.eql(wave[ni])) continue;
                if (now.count() == 0) return false;
                wave[ni] = now;
                if (queued.isSet(ni)) continue;
                queued.set(ni);
                stack[top] = @intCast(ni);
                top += 1;
            }
        }
    }
    for (0..w * h) |i| out[i] = m.pat[wave[i].findFirstSet().?][0];
    return true;
}

/// Each template's art, at its place in `Template`; `mixed`, last, picks one.
const TEMPLATES = blk: {
    var a: [@intFromEnum(Template.mixed)][]const []const u8 = undefined;
    for (&a, 0..) |*s, i| s.* = switch (@as(Template, @enumFromInt(i))) {
        .huts => &HUTS,
        .compound => &COMPOUND,
        .pillars => &PILLARS,
        .mixed => unreachable,
    };
    break :blk a;
};

comptime {
    std.debug.assert(TEMPLATES.len + 1 == std.enums.values(Template).len);
}

fn templateOf(t: Template, rng: *mathx.Rng) usize {
    return if (t == .mixed) rng.below(TEMPLATES.len) else @intFromEnum(t);
}

pub fn shape(lv: *grid.Level, rng: *mathx.Rng, _: u64, p: Params) void {
    const pal = palette(p);
    carve.field(lv, pal);
    var out: [CELLS_MAX]u8 = undefined;
    var models: [TEMPLATES.len]?Model = @splat(null);
    var y: i32 = MARGIN;
    while (y + SECTION_MIN <= grid.H - MARGIN) {
        const sh = @min(SECTION_H, grid.H - MARGIN - y);
        var x: i32 = MARGIN;
        while (x + SECTION_MIN <= grid.W - MARGIN) {
            const sw = @min(SECTION_W, grid.W - MARGIN - x);
            const k = templateOf(p.template, rng);
            if (models[k] == null) models[k] = Model.of(TEMPLATES[k]);
            const m = &models[k].?;
            const w: usize = @intCast(sw);
            const h: usize = @intCast(sh);
            const solved = for (0..ATTEMPTS) |_| {
                if (solve(m, rng, w, h, &out)) break true;
            } else false;
            if (solved) {
                for (0..h) |yy| {
                    for (0..w) |xx| {
                        const q = P{ .x = x + @as(i32, @intCast(xx)), .y = y + @as(i32, @intCast(yy)) };
                        const t: grid.Tile = switch (grid.Tile.ofLetter(SYMBOLS[out[yy * w + xx]]).?) {
                            .wall => if (rng.percent(p.decay)) .rubble else .wall,
                            .grass => pal.open,
                            else => |kept| kept,
                        };
                        lv.set(q, t);
                    }
                }
            }
            x += sw + STREET;
        }
        y += sh + STREET;
    }
}

test "every template's model holds all its patterns and every one has a neighbour each way" {
    for (TEMPLATES) |art| {
        const m = Model.of(art);
        std.debug.print("a template: {d} patterns of 3x3 with rotations and reflections, room for {d}\n", .{ m.n, PATTERNS_MAX });
        try std.testing.expect(m.n > 10 and m.n < PATTERNS_MAX);
        for (0..m.n) |a| {
            for (0..4) |k| try std.testing.expect(m.fits[a][k].count() > 0);
        }
    }
}

test "a site grows walls and floors from its templates" {
    var lv = grid.Level.blank();
    var rng = mathx.Rng.init(0x517E);
    shape(&lv, &rng, 0, .{ .decay = 0 });
    std.debug.print("a site: {d} wall, {d} floor of {d}\n", .{ carve.count(&lv, .wall), carve.count(&lv, .floor), grid.CELLS });
    try std.testing.expect(carve.count(&lv, .wall) > 200 and carve.count(&lv, .floor) > 200);
}
