const std = @import("std");
const mathx = @import("../core/mathx.zig");
const day = @import("day.zig");
const grid = @import("grid.zig");

// Outdoor weather from the profile, run seed and minutes, and from a cell's location where a node overrides its weather; only its rain reaches the rules (`terrain.rained`, `fire.damped`).

pub const Light = enum {
    clear,
    bleak,

    pub fn overcast(l: Light) f32 {
        return switch (l) {
            .clear => 0,
            .bleak => 1,
        };
    }
};

pub const Weather = enum {
    clear,
    drizzle,
    coastal,
    stormy,
    misty,
    beams,
};

pub const Location = enum { inland, coast, forest };
pub const Locations = std.EnumArray(Location, ?Weather);
pub const Field = [grid.CELLS]Location;
pub const Local = std.EnumArray(Location, Now);
pub const CALM: Local = .initFill(.initFill(0));
/// Cells round a tree that count as forest.
const FOREST_REACH: i32 = 2;

pub fn locations(lv: *const grid.Level) Field {
    var field: Field = @splat(.inland);
    var seen = grid.CellSet.initEmpty();
    var queue: [grid.CELLS]u32 = undefined;
    var spread = grid.Spread(*const grid.Level, coastal){ .ctx = lv, .steps = &mathx.CARDINALS, .seen = &seen, .queue = &queue };
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        if (grid.Level.onRim(p) and coastal(lv, p)) spread.seed(p);
    }
    while (spread.next()) |p| field[grid.Level.idx(p)] = .coast;
    for (lv.tile, 0..) |t, i| {
        if (!grid.TREE_TILES.contains(t)) continue;
        var cells = grid.Box.around(grid.Level.of(i), FOREST_REACH).grown(0).cells();
        while (cells.next()) |p| {
            const j = grid.Level.idx(p);
            if (field[j] != .coast) field[j] = .forest;
        }
    }
    return field;
}

fn coastal(lv: *const grid.Level, p: mathx.P) bool {
    const t = lv.at(p);
    return t == .sand or t.wet() or t.spans() or lv.frozen(p);
}

pub fn placeAt(field: *const Field, p: mathx.P) Location {
    return grid.cellOr(Location, field, p, .inland);
}

const BLEND_R: usize = 3;
const BLEND_PASSES = 2;
const COLS = grid.COLS;
const ROWS = grid.ROWS;

pub const Blend = struct {
    of: Field = @splat(.inland),
    weight: std.EnumArray(Location, [grid.CELLS]f32) = .init(.{ .inland = @splat(1), .coast = @splat(0), .forest = @splat(0) }),
    scratch: [grid.CELLS]f32 = undefined,

    pub fn follow(self: *Blend, field: *const Field) void {
        if (std.mem.eql(Location, &self.of, field)) return;
        self.of = field.*;
        for (std.enums.values(Location)) |place| {
            const w = self.weight.getPtr(place);
            for (w, field) |*v, f| v.* = if (f == place) 1 else 0;
            for (0..BLEND_PASSES) |_| {
                blurAlong(w, &self.scratch, 1, COLS);
                blurAlong(&self.scratch, w, COLS, ROWS);
            }
        }
    }

    fn blurAlong(from: *const [grid.CELLS]f32, to: *[grid.CELLS]f32, stride: usize, n: usize) void {
        const lines = grid.CELLS / n;
        const across: usize = if (stride == 1) COLS else 1;
        const k: f32 = 1 / @as(f32, @floatFromInt(2 * BLEND_R + 1));
        for (0..lines) |line| {
            const base = line * across;
            for (0..n) |i| {
                var sum: f32 = 0;
                for (0..2 * BLEND_R + 1) |d| {
                    const j = std.math.clamp(@as(isize, @intCast(i + d)) - @as(isize, BLEND_R), 0, @as(isize, @intCast(n - 1)));
                    sum += from[base + @as(usize, @intCast(j)) * stride];
                }
                to[base + i * stride] = sum * k;
            }
        }
    }

    pub fn cell(self: *const Blend, weather: Local, i: usize) Now {
        var result = Now.initFill(0);
        for (std.enums.values(Location)) |place| addShare(&result, weather.getPtrConst(place), self.weight.getPtrConst(place)[i]);
        return result;
    }

    /// `at` in cells, a cell spanning [p, p + 1).
    pub fn at(self: *const Blend, weather: Local, c: [2]f32) Now {
        const fx = std.math.clamp(c[0] - 0.5, 0, @as(f32, COLS - 1));
        const fy = std.math.clamp(c[1] - 0.5, 0, @as(f32, ROWS - 1));
        const x0: usize = @intFromFloat(@floor(fx));
        const y0: usize = @intFromFloat(@floor(fy));
        const x1 = @min(x0 + 1, COLS - 1);
        const y1 = @min(y0 + 1, ROWS - 1);
        const tx = fx - @as(f32, @floatFromInt(x0));
        const ty = fy - @as(f32, @floatFromInt(y0));
        var result = Now.initFill(0);
        for (std.enums.values(Location)) |place| {
            const w = self.weight.getPtrConst(place);
            addShare(&result, weather.getPtrConst(place), mathx.bilerp(.{ w[y0 * COLS + x0], w[y0 * COLS + x1], w[y1 * COLS + x0], w[y1 * COLS + x1] }, tx, ty));
        }
        return result;
    }

    fn addShare(into: *Now, n: *const Now, share: f32) void {
        if (share <= 0) return;
        for (&into.values, n.values) |*r, v| r.* += v * share;
    }
};

test "weather fades across a few cells where locations meet and is whole away from the edge" {
    var field: Field = @splat(.inland);
    for (&field, 0..) |*f, i| if (grid.Level.of(i).x >= 40) {
        f.* = .coast;
    };
    var blend: Blend = .{};
    blend.follow(&field);
    var weather = CALM;
    weather.getPtr(.coast).set(.rain, 1);
    const y: f32 = 20.5;
    try std.testing.expectApproxEqAbs(@as(f32, 0), blend.at(weather, .{ 30.5, y }).get(.rain), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), blend.at(weather, .{ 50.5, y }).get(.rain), 1e-5);
    var last: f32 = 0;
    var x: f32 = 33;
    while (x < 47) : (x += 0.25) {
        const r = blend.at(weather, .{ x, y }).get(.rain);
        try std.testing.expect(r >= last - 1e-6 and r - last < 0.06);
        last = r;
    }
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), blend.at(weather, .{ 40, y }).get(.rain), 1e-5);
}

pub fn local(c: Climate, overrides: Locations, seed: u64, minutes: u64) Local {
    var result = Local.initUndefined();
    for (std.enums.values(Location)) |place| result.set(place, c.in(overrides, place).now(seed, minutes));
    return result;
}

pub fn strongest(values: Local) Now {
    var result = Now.initFill(0);
    for (values.values) |n| {
        for (&result.values, n.values) |*r, v| r.* = @max(r.*, v);
    }
    return result;
}

pub const Rain = struct {
    uniform: f32 = 0,
    field: ?*const Field = null,
    local: std.EnumArray(Location, f32) = .initFill(0),

    pub fn at(self: Rain, p: mathx.P) f32 {
        const field = self.field orelse return self.uniform;
        return self.local.get(placeAt(field, p));
    }
};

pub const Drive = enum { storm, haze };

pub const Cycle = struct {
    /// Game minutes a spell lasts.
    spell: u16 = 240,
    lean: f32 = 1,
};

pub const Span = struct {
    on: Drive = .storm,
    least: f32 = 0,
    most: f32 = 0,
    from: f32 = 0,

    fn at(s: Span, v: f32) f32 {
        const k = if (v <= s.from) 0 else (v - s.from) / (1 - s.from);
        return mathx.lerpF(s.least, s.most, k);
    }
};

pub const Layer = enum { overcast, rain, mist, lightning, beams };

pub const Now = std.EnumArray(Layer, f32);

pub const Profile = struct {
    cycle: std.EnumArray(Drive, Cycle) = .initFill(.{}),
    layer: std.EnumArray(Layer, Span) = .initFill(.{}),
};

pub const DRIZZLE: f32 = 0.19;

pub const PROFILES = std.EnumArray(Weather, Profile).init(.{
    .clear = .{},
    .drizzle = .{ .layer = .init(.{
        .overcast = .{},
        .rain = .{ .least = DRIZZLE, .most = DRIZZLE },
        .mist = .{},
        .lightning = .{},
        .beams = .{},
    }) },
    .coastal = .{
        .cycle = .init(.{ .storm = .{ .spell = 180 }, .haze = .{ .spell = 180, .lean = 1.3 } }),
        .layer = .init(.{
            .overcast = .{ .least = 0.4, .most = 1 },
            .rain = .{ .most = 0.75, .from = 0.4 },
            .mist = .{ .on = .haze, .least = 0.1, .most = 0.8, .from = 0.3 },
            .lightning = .{ .most = 0.2, .from = 0.85 },
            .beams = .{},
        }),
    },
    .stormy = .{
        .cycle = .init(.{ .storm = .{ .spell = 240 }, .haze = .{} }),
        .layer = .init(.{
            .overcast = .{ .least = 0.2, .most = 1 },
            .rain = .{ .most = 1, .from = 0.45 },
            .mist = .{ .on = .haze, .most = 0.3, .from = 0.6 },
            .lightning = .{ .most = 1, .from = 0.65 },
            .beams = .{},
        }),
    },
    .misty = .{
        .cycle = .init(.{ .storm = .{ .spell = 300, .lean = 1.5 }, .haze = .{ .spell = 360, .lean = 0.6 } }),
        .layer = .init(.{
            .overcast = .{ .least = 0.2, .most = 0.6 },
            .rain = .{ .most = 0.25, .from = 0.75 },
            .mist = .{ .on = .haze, .least = 0.4, .most = 1 },
            .lightning = .{},
            .beams = .{},
        }),
    },
    .beams = .{ .layer = .init(.{
        .overcast = .{},
        .rain = .{},
        .mist = .{},
        .lightning = .{},
        .beams = .{ .least = 1, .most = 1 },
    }) },
});

pub const Climate = struct {
    light: Light = .clear,
    weather: Weather = .clear,

    /// As it stands at `place`, whose weather `overrides` may set.
    pub fn in(c: Climate, overrides: Locations, place: Location) Climate {
        return .{ .light = c.light, .weather = overrides.get(place) orelse c.weather };
    }

    pub fn now(c: Climate, seed: u64, minutes: u64) Now {
        const p = PROFILES.get(c.weather);
        var d = std.EnumArray(Drive, f32).initUndefined();
        for (std.enums.values(Drive)) |k| d.set(k, drive(seed, k, p.cycle.get(k), minutes));
        var n = Now.initUndefined();
        for (std.enums.values(Layer)) |l| {
            const span = p.layer.get(l);
            n.set(l, span.at(d.get(span.on)));
        }
        n.set(.overcast, @max(n.get(.overcast), c.light.overcast()));
        return n;
    }

    pub fn rain(c: Climate, seed: u64, minutes: u64) f32 {
        const profile = PROFILES.getPtrConst(c.weather);
        const span = profile.layer.get(.rain);
        if (span.least == span.most) return span.least;
        return span.at(drive(seed, span.on, profile.cycle.get(span.on), minutes));
    }
};

const EASE_SHARE: f32 = 0.6;

fn drive(seed: u64, k: Drive, c: Cycle, minutes: u64) f32 {
    const spell: u64 = @max(c.spell, 1);
    const n = minutes / spell;
    const t = @as(f32, @floatFromInt(minutes % spell)) / @as(f32, @floatFromInt(spell));
    return mathx.lerpF(roll(seed, k, c, n), roll(seed, k, c, n + 1), mathx.smoothstep(1 - EASE_SHARE, 1, t));
}

fn roll(seed: u64, k: Drive, c: Cycle, n: u64) f32 {
    var h = std.hash.Wyhash.init(seed);
    h.update(std.mem.asBytes(&@intFromEnum(k)));
    h.update(std.mem.asBytes(&n));
    const u = mathx.unitOf(h.final());
    return std.math.pow(f32, u, c.lean);
}

pub fn eased(from: Now, to: Now, k: f32) Now {
    var n = from;
    for (&n.values, to.values) |*v, t| v.* = mathx.lerpF(v.*, t, k);
    return n;
}

test "a sky left alone is the clear day it always was" {
    const c = Climate{};
    try std.testing.expectEqual(Light.clear, c.light);
    try std.testing.expectEqual(Weather.clear, c.weather);
    for (0..200) |m| {
        for (c.now(7, m * 37).values) |v| try std.testing.expectEqual(@as(f32, 0), v);
    }
}

test "locations keep inland ponds dry and give the coast priority over nearby trees" {
    var lv = grid.openFloor();
    for (0..12) |x| lv.set(.{ .x = @intCast(x), .y = 20 }, if (x < 6) .water else .sand);
    lv.set(.{ .x = 10, .y = 19 }, .large_tree);
    lv.set(.{ .x = 30, .y = 20 }, .water);
    lv.set(.{ .x = 40, .y = 20 }, .shrub);
    lv.set(.{ .x = 0, .y = 0 }, .large_tree);
    const field = locations(&lv);
    try std.testing.expectEqual(Location.coast, field[grid.Level.idx(.{ .x = 11, .y = 20 })]);
    try std.testing.expectEqual(Location.forest, field[grid.Level.idx(.{ .x = 12, .y = 19 })]);
    try std.testing.expectEqual(Location.inland, field[grid.Level.idx(.{ .x = 30, .y = 20 })]);
    try std.testing.expectEqual(Location.forest, field[grid.Level.idx(.{ .x = 42, .y = 22 })]);
    try std.testing.expectEqual(Location.inland, field[grid.Level.idx(.{ .x = 43, .y = 20 })]);
    try std.testing.expectEqual(Location.forest, field[0]);
    lv.set(.{ .x = 5, .y = 20 }, .shallows);
    _ = @import("ice.zig").freeze(&lv, &.{.{ .x = 5, .y = 20 }});
    try std.testing.expectEqualSlices(Location, &field, &locations(&lv));
    lv.set(.{ .x = 5, .y = 20 }, .bridge);
    lv.thaw[grid.Level.idx(.{ .x = 5, .y = 20 })] = 0;
    try std.testing.expectEqualSlices(Location, &field, &locations(&lv));
    var overrides = Locations.initFill(null);
    overrides.set(.coast, .drizzle);
    overrides.set(.forest, .beams);
    const weather = local(.{}, overrides, 17, 400);
    try std.testing.expectEqual(DRIZZLE, weather.get(.coast).get(.rain));
    try std.testing.expectEqual(@as(f32, 0), weather.get(.forest).get(.rain));
    try std.testing.expectEqual(@as(f32, 1), weather.get(.forest).get(.beams));
    try std.testing.expectEqual(@as(f32, 0), weather.get(.inland).get(.beams));
}

test "a profile's weather holds, changes by spells, keeps each layer in its span, and is the same for the same seed and time" {
    const days = 30;
    const step = day.TURN_MINUTES;
    for (std.enums.values(Weather)) |w| {
        const c = Climate{ .weather = w };
        const p = PROFILES.get(w);
        var most_turn: f32 = 0;
        var before = c.now(42, 0);
        var m: u64 = step;
        while (m < days * day.MINUTES) : (m += step) {
            const n = c.now(42, m);
            try std.testing.expectEqual(n, c.now(42, m));
            try std.testing.expectEqual(n.get(.rain), c.rain(42, m));
            for (std.enums.values(Layer)) |l| {
                const s = p.layer.get(l);
                try std.testing.expect(n.get(l) >= s.least - 1e-5 and n.get(l) <= s.most + 1e-5);
                most_turn = @max(most_turn, @abs(n.get(l) - before.get(l)));
            }
            before = n;
        }
        try std.testing.expect(most_turn < 0.2);
    }
    const coast = Climate{ .weather = .coastal };
    try std.testing.expect(!std.meta.eql(coast.now(1, 600), coast.now(2, 600)));
    const bleak = Climate{ .light = .bleak, .weather = .coastal };
    try std.testing.expectEqual(@as(f32, 1), bleak.now(1, 600).get(.overcast));
}
