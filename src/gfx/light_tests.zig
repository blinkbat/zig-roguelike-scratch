const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const fov = @import("../map/fov.zig");
const look = @import("look.zig");
const sky = @import("sky.zig");
const lume = @import("../map/lume.zig");
const actor = @import("../play/actor.zig");
const shadow = @import("shadow.zig");
const light = @import("light.zig");
const P = mathx.P;
const splat = sky.splat;
const rgbOf = look.rgbOf;
const lum = sky.luma;

const gen = @import("../map/gen.zig");
const day = @import("../map/day.zig");

const TORCH_AT = P{ .x = 20, .y = 10 };
/// Cells in from an edge, so a sample on it reads the seen cell and not the unseen one past it.
const EDGE_EPS: f32 = 1e-4;

fn wallAcross(lv: *grid.Level) void {
    var x: i32 = 1;
    while (x < grid.W - 1) : (x += 1) lv.set(.{ .x = x, .y = TORCH_AT.y }, .wall);
}

const LIT_BOX = grid.Box.between(.{ .x = 10, .y = 10 }, .{ .x = 20, .y = 20 });

fn lightBox(lv: *grid.Level, b: grid.Box) void {
    var cells = b.cells();
    while (cells.next()) |p| lv.light(p);
}

fn testRoom(lv: *grid.Level, walls: []const P) void {
    lv.* = grid.openFloor();
    wallAcross(lv);
    for (walls) |w| lv.set(w, .wall);
    gen.shapeWalls(lv);
    lv.addTorch(TORCH_AT);
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
}

fn litFloor() grid.Level {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    return lv;
}

fn testLight(lv: *const grid.Level) !*light.Light {
    const l = try light.Light.create(std.testing.allocator);
    l.settle(lv);
    return l;
}

fn added(l: *const light.Light, lv: *const grid.Level, q: [2]f32) f32 {
    var ids: [light.LIGHTS]light.TorchIx = undefined;
    return lum(l.at(lv, l.near(grid.Box.inMap(0), &ids), q)) - lum(l.at(lv, &.{}, q));
}

test "effect lights shade terrain and bodies without revealing memory or crossing walls" {
    var lv = litFloor();
    for (0..grid.H) |y| lv.set(.{ .x = 22, .y = @intCast(y) }, .wall);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const near = [2]f32{ 21.5, 20.5 };
    const far = [2]f32{ 23.5, 20.5 };
    const before = l.at(&lv, &.{}, near);
    const hidden = l.at(&lv, &.{}, far);
    const sight = lv.lit;
    const seen = lv.seen;
    l.emit(&lv, .{ .at = .{ 20.5, 20.5, 0.4 }, .col = look.FIRE, .radius = 4, .gain = 1 });
    try std.testing.expect(lum(l.at(&lv, &.{}, near)) > lum(before) + 0.1);
    try std.testing.expectEqual(hidden, l.at(&lv, &.{}, far));
    try std.testing.expect(l.onBody(near, false).n > 0);
    try std.testing.expectEqual(@as(usize, 0), l.onBody(far, false).n);
    try std.testing.expectEqualSlices(bool, &sight, &lv.lit);
    try std.testing.expectEqualSlices(bool, &seen, &lv.seen);
    lv.lit[grid.Level.idx(.{ .x = 21, .y = 20 })] = false;
    l.settle(&lv);
    const memory = l.at(&lv, &.{}, near);
    l.emit(&lv, .{ .at = .{ 20.5, 20.5, 0.4 }, .col = look.COLD, .radius = 4, .gain = 1 });
    try std.testing.expectEqual(memory, l.at(&lv, &.{}, near));
    l.effect_n = 0;
    lv.lit[grid.Level.idx(.{ .x = 20, .y = 20 })] = false;
    l.emit(&lv, .{ .at = .{ 20.5, 20.5, 0.4 }, .col = look.FIRE, .radius = 4, .gain = 1 });
    try std.testing.expectEqual(@as(usize, 0), l.effect_n);
    std.debug.print("effect lighting: floor and body lit; wall, memory and hidden source blocked; visibility unchanged\n", .{});
}

test "effect reach bounds preserve lighting at fractional positions and map edges" {
    var lv = grid.openFloor();
    @memset(&lv.lit, true);
    for (18..25) |x| lv.set(.{ .x = @intCast(x), .y = 21 }, .wall);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const positions = [_][2]f32{ .{ 0.01, 0.99 }, .{ 20.5, 20.5 }, .{ 21.001, 20.999 }, .{ @as(f32, @floatFromInt(grid.W)) - 0.01, @as(f32, @floatFromInt(grid.H)) - 0.01 } };
    const radii = [_]f32{ 0.1, 0.6, 1, 1.6, 2.2, 2.8, 4, 8 };
    const offsets = [_]f32{ 0.001, 0.5, 0.999 };
    const heights = [_]f32{ 0, 0.4, 1.4 };
    var samples: usize = 0;
    var lit: usize = 0;
    for (positions) |at| {
        for (radii) |radius| {
            l.effect_n = 0;
            l.emit(&lv, .{ .at = .{ at[0], at[1], 0.4 }, .col = look.FIRE, .radius = radius, .gain = 1 });
            try std.testing.expectEqual(@as(usize, 1), l.effect_n);
            const bounded = &l.effects[0];
            var reference = bounded.*;
            for (&reference.reach, 0..) |*reached, i| {
                const p = reference.box().lo.add(mathx.unslot(i, light.EFFECT_SPAN));
                reached.* = grid.Level.inside(p) and grid.clearLine(&lv, reference.origin, p);
                for (offsets) |dx| {
                    for (offsets) |dy| {
                        for (heights) |z| {
                            const x = @as(f32, @floatFromInt(p.x)) + dx;
                            const y = @as(f32, @floatFromInt(p.y)) + dy;
                            const expected = reference.strength(x, y, z);
                            try std.testing.expectEqual(expected, bounded.strength(x, y, z));
                            samples += 1;
                            if (expected > 0) lit += 1;
                        }
                    }
                }
            }
        }
    }
    try std.testing.expect(lit > 0);
    std.debug.print("effect reach bounds: {d} samples unchanged, including {d} lit samples across {d} positions and {d} radii\n", .{ samples, lit, positions.len, radii.len });
}

test "cell effect culling preserves floor wall and water lighting" {
    var lv = litFloor();
    for (18..25) |x| lv.set(.{ .x = @intCast(x), .y = 21 }, .wall);
    @import("../map/procgen.zig").reshape(&lv);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const radii = [_]f32{ 0.6, 1.6, 2.8, 4 };
    const heights = [_]f32{ 0, 0.3, 1.4 };
    var all = light.EffectSet.initEmpty();
    for (0..light.EFFECTS) |i| {
        l.emit(&lv, .{
            .at = .{ 16.2 + @as(f32, @floatFromInt(i % 8)) * 2.4, 14.9 + @as(f32, @floatFromInt(i / 8)) * 2.7, heights[i % heights.len] },
            .col = if (i % 2 == 0) look.FIRE else look.COLD,
            .radius = radii[i % radii.len],
            .gain = 0.8,
        });
        all.set(i);
    }
    var cells = grid.Cells.of(.{ .x = 14, .y = 14 }, .{ .x = 38, .y = 32 });
    var samples: usize = 0;
    var candidates: usize = 0;
    var surfaces = std.EnumSet(light.Surface).initEmpty();
    const sub: usize = light.SUB;
    while (cells.next()) |c| {
        const kept = l.effectsNear(c);
        for (0..sub * sub) |i| {
            const q = light.Light.texelCentre(@as(usize, @intCast(c.x)) * sub + i % sub, @as(usize, @intCast(c.y)) * sub + i / sub);
            const v = l.viewAt(q);
            surfaces.insert(light.Spot.of(&lv, q).surface);
            try std.testing.expectEqual(l.shade(&lv, &.{}, all, q, null, v, null, 1), l.shade(&lv, &.{}, kept, q, null, v, null, 1));
            try std.testing.expectEqual(l.waterGlint(&.{}, all, q, null, null, 1), l.waterGlint(&.{}, kept, q, null, null, 1));
            samples += 1;
            candidates += kept.count();
        }
    }
    try std.testing.expectEqual(@as(usize, 3), surfaces.count());
    try std.testing.expect(candidates < samples * light.EFFECTS / 4);
    std.debug.print("effect culling: {d} floor/wall/glint samples unchanged; {d} of {d} light candidates retained\n", .{ samples, candidates, samples * light.EFFECTS });
}

test "smooth water glints follow light direction and respect walls and memory" {
    try std.testing.expectApproxEqAbs(@as(f32, 1), light.smoothSpecular(.{ 0, -1, 1 }, light.GLINT_POWER), 1e-4);
    try std.testing.expect(light.smoothSpecular(.{ 1, -1, 1 }, light.GLINT_POWER) < 0.03);
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    for (&lv.tile) |*tile| {
        if (tile.* == .floor) tile.* = .shallows;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const flame = l.torch[0].flame();
    const at = [2]f32{ flame[0], flame[1] + flame[2] };
    const lit = lum(l.waterGlint(&.{0}, .initEmpty(), at, null, null, 1));
    try std.testing.expect(lit > 0.01 and lit < 0.2);
    try std.testing.expectEqual(@as(f32, 0), lum(l.waterGlint(&.{0}, .initEmpty(), .{ flame[0], 9.5 }, null, null, 1)));
    const before = lv.lit;
    l.bake(&lv, .{ .x = 18, .y = 10 }, .{ .x = 23, .y = 15 });
    var hits: usize = 0;
    for (l.texels.getPtrConst(.glints)) |pixel| {
        if (pixel.r > 0 or pixel.g > 0 or pixel.b > 0) hits += 1;
    }
    try std.testing.expect(hits > 0);
    try std.testing.expectEqualSlices(bool, &before, &lv.lit);
    @memset(&lv.lit, false);
    l.settle(&lv);
    l.bake(&lv, .{ .x = 18, .y = 10 }, .{ .x = 23, .y = 15 });
    for (l.texels.getPtrConst(.glints)) |pixel| try std.testing.expectEqual(rl.Color.blank, pixel);
    std.debug.print("smooth water: {d} glint texels, peak {d:.3}; wall and memory blocked; visibility unchanged\n", .{ hits, lit });
}

test "a torch pools light on the floor below it, fading to nothing at its reach" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const fl = l.torch[0].flame();
    std.debug.print("torchlight on the floor by cells from the flame:", .{});
    var last = std.math.floatMax(f32);
    for ([_]f32{ 0.25, 1, 2, 3, 4, 5, 6, @floatFromInt(light.REACH) }) |r| {
        const v = added(l, &lv, .{ fl[0], fl[1] + r });
        std.debug.print(" {d}:{d:.3}", .{ r, v });
        try std.testing.expect(v <= last);
        last = v;
    }
    std.debug.print("\n", .{});
    try std.testing.expect(added(l, &lv, .{ fl[0], fl[1] + 0.25 }) > 0.6);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last, 1e-5);
}

test "a glowing plant pools pale blue light round its own cell and draws a glow but no flame" {
    var lv = litFloor();
    const at = P{ .x = 30, .y = 30 };
    lv.set(at, .glow_plant);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    try std.testing.expectEqual(@as(usize, 1), l.torch_n);
    var ids: [light.LIGHTS]light.TorchIx = undefined;
    const near = l.near(grid.Box.inMap(0), &ids);
    const top = l.at(&lv, near, mathx.centre(at)) - l.at(&lv, &.{}, mathx.centre(at));
    std.debug.print("glow plant light by cells along the floor:", .{});
    var last = std.math.floatMax(f32);
    for ([_]f32{ 1, 2, 3, 4, 5, 6, @floatFromInt(light.REACH) }) |r| {
        const q = [2]f32{ mathx.centre(at)[0] + r, mathx.centre(at)[1] };
        const rgb = l.at(&lv, near, q) - l.at(&lv, &.{}, q);
        std.debug.print(" {d}:{d:.3}/{d:.3}/{d:.3}", .{ r, rgb[0], rgb[1], rgb[2] });
        try std.testing.expect(lum(rgb) <= last);
        if (r < 6) try std.testing.expect(rgb[2] > rgb[1] and rgb[1] > rgb[0]);
        last = lum(rgb);
    }
    std.debug.print("; its own top {d:.3}\n", .{lum(top)});
    try std.testing.expect(!std.math.isNan(lum(top)) and lum(top) > 0.3);
    try std.testing.expectApproxEqAbs(@as(f32, 0), last, 1e-5);
    var buf: [light.LIGHTS]light.Flame = undefined;
    const got = l.flames(&lv, &buf);
    try std.testing.expectEqual(@as(usize, 1), got.len);
    try std.testing.expect(got[0].kind == .plant and got[0].live());
}

test "the plant lit in an uprooted plant's place flickers apart from every other light" {
    var lv = litFloor();
    var plants: [light.LIGHTS + 1]P = undefined;
    for (&plants, 0..) |*p, i| {
        p.* = .{ .x = 2 + @as(i32, @intCast(i % 40)), .y = 2 + 2 * @as(i32, @intCast(i / 40)) };
        lv.set(p.*, .glow_plant);
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const lit = l.torch_n;
    try std.testing.expect(lit < plants.len);
    lv.set(plants[0], .grass);
    l.uproot(&lv, plants[0]);
    try std.testing.expectEqual(lit, l.torch_n);
    for (l.torch[0..l.torch_n], 0..) |*a, i| {
        for (l.torch[i + 1 .. l.torch_n]) |*b| try std.testing.expect(a.seed != b.seed);
    }
}

test "a brick face by its torch catches far more than the ceiling above it, and one turned away catches none" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{.{ .x = 22, .y = 14 }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const own = added(l, &lv, .{ 20.5, 10.875 });
    const ceiling = added(l, &lv, .{ 20.5, 10.25 });
    const along = added(l, &lv, .{ 23.5, 10.875 });
    const along_ceiling = added(l, &lv, .{ 23.5, 10.25 });
    const away = added(l, &lv, .{ 22.5, 14.875 });
    const away_ceiling = added(l, &lv, .{ 22.5, 14.25 });
    std.debug.print("torchlight: its own face {d:.3} and the ceiling above {d:.3}, a face 3 along {d:.3} and its ceiling {d:.3}, a face in reach turned away {d:.3} under a ceiling at {d:.3}\n", .{ own, ceiling, along, along_ceiling, away, away_ceiling });
    try std.testing.expect(own > ceiling * 3);
    try std.testing.expect(own > along);
    try std.testing.expect(along > along_ceiling * 1.5);
    try std.testing.expect(away_ceiling > 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), away, 1e-5);
}

test "no torchlight reaches the floor behind its wall" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const behind = added(l, &lv, .{ 20.5, 10 - EDGE_EPS });
    const behind_along = added(l, &lv, .{ 24.5, 9.9 });
    const below = added(l, &lv, .{ 24.5, 11 + EDGE_EPS });
    std.debug.print("torchlight on the floor at the back of its wall {d:.3}, 4 along {d:.3}, at its front 4 along {d:.3}\n", .{ behind, behind_along, below });
    try std.testing.expectApproxEqAbs(@as(f32, 0), behind, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), behind_along, 1e-5);
    try std.testing.expect(below > 0.05);
}

test "forest shadow edges project together under torches and the sky" {
    const a = [2]f32{ 20.5, 20.5 };
    var checked: usize = 0;
    for ([_]?[2]f32{ null, .{ 20.5, 17.3 }, .{ 15.5, 20.5 }, .{ 26.5, 25.5 } }) |source| {
        const cast = shadow.Cast{ .lean = .{ 40, -12 }, .len = 42, .solid = 1, .alpha = 0.7, .shade = light.SHADE_RGB, .source = source };
        for (0..2) |axis| {
            var b = a;
            b[axis] += 1;
            for (0..17) |i| {
                const across = @as(f32, @floatFromInt(i)) / 16;
                var auv = [2]f32{ across, across };
                var buv = auv;
                auv[axis] = 1;
                buv[axis] = 0;
                const left = shadow.forestTip(cast, a, auv, ART_H);
                const right = shadow.forestTip(cast, b, buv, ART_H);
                for (0..2) |k| try std.testing.expectApproxEqAbs(left[k], right[k], 1e-5);
                checked += 1;
            }
        }
    }
    std.debug.print("{d} shared forest shadow edge points agree under 3 torches and the sky\n", .{checked});
}

test "shadow casters keep their light outside sight and memory" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const centre = [2]f32{ 20.5, 13.5 };
    l.carrier = .{ 22.5, 14.5 };
    @memset(&lv.los, true);
    var checked: usize = 0;
    for ([_]?f32{ day.NOON, day.DEAD_OF_NIGHT, null }) |hour| {
        l.sky = if (hour) |h| sky.at(h) else null;
        @memset(&lv.lit, true);
        @memset(&lv.seen, true);
        l.settle(&lv);
        var before: [light.BODY_LIGHTS]shadow.Cast = undefined;
        const expected = shadow.casts(&l.onCaster(centre, false), centre, ART_H, &before);
        try std.testing.expect(expected.len > 0);
        for ([_]bool{ false, true }) |remembered_| {
            @memset(&lv.lit, false);
            @memset(&lv.seen, remembered_);
            l.settle(&lv);
            var after: [light.BODY_LIGHTS]shadow.Cast = undefined;
            const actual = shadow.casts(&l.onCaster(centre, false), centre, ART_H, &after);
            try std.testing.expectEqualSlices(shadow.Cast, expected, actual);
            try std.testing.expectEqual(@as(usize, 0), shadow.casts(&l.onBody(centre, false), centre, ART_H, &after).len);
            checked += actual.len;
        }
    }
    std.debug.print("{d} sun, moon and torch casts unchanged outside sight and memory; hidden bodies cast none through their draw lighting\n", .{checked});
}

test "a contact pool needs a light: memory's floor reaches nothing" {
    var lv = grid.openFloor();
    @memset(&lv.los, true);
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const centre = [2]f32{ 20.5, 13.5 };
    l.sky = null;
    l.carrier = null;
    l.settle(&lv);
    const dark = l.onCaster(centre, false);
    l.carrier = .{ 21.5, 13.5 };
    l.settle(&lv);
    const lantern = l.onCaster(centre, false);
    l.carrier = null;
    l.sky = sky.at(day.NOON);
    l.settle(&lv);
    const noon = l.onCaster(centre, false);
    std.debug.print("light reaching a body: dark {d:.3} (drawn {d:.3}), lantern {d:.3}, noon {d:.3}\n", .{ dark.reached(), dark.lit(), lantern.reached(), noon.reached() });
    try std.testing.expect(dark.reached() <= light.FAINT);
    try std.testing.expect(dark.lit() > light.FAINT);
    try std.testing.expect(lantern.reached() > light.FAINT);
    try std.testing.expect(noon.reached() > light.FAINT);
}

test "shadow receivers fade at sight and disappear in remembered or unseen ground" {
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        lv.seen[i] = p.x < 30;
        lv.lit[i] = p.x < 20;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.sky = sky.at(day.NOON);
    l.bake(&lv, .{ .x = 10, .y = 20 }, .{ .x = 40, .y = 21 });
    var live: usize = 0;
    var faded: usize = 0;
    var remembered_: usize = 0;
    var unseen: usize = 0;
    for (10 * light.SUB..40 * light.SUB) |x| {
        const c = l.texels.getPtrConst(.map)[20 * light.SUB * light.MAP_W + x];
        if (x < 18 * light.SUB) {
            try std.testing.expectEqual(@as(u8, 255), c.a);
            live += 1;
        } else if (x > 22 * light.SUB and x < 28 * light.SUB) {
            try std.testing.expectEqual(@as(u8, 0), c.a);
            try std.testing.expect(c.r > 0);
            remembered_ += 1;
        } else if (x >= 30 * light.SUB) {
            try std.testing.expectEqual(rl.Color.blank, c);
            unseen += 1;
        } else if (c.a > 0 and c.a < 255) faded += 1;
    }
    try std.testing.expect(faded > 0);
    std.debug.print("shadow receivers: {d} fully visible, {d} fading, {d} memory and {d} unseen texels with no live shadow\n", .{ live, faded, remembered_, unseen });
}

test "a pillar throws the torch's shadow across the floor behind it" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{.{ .x = 20, .y = 13 }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const behind = added(l, &lv, .{ 20.5, 15.5 });
    const beside = added(l, &lv, .{ 22.5, 14.5 });
    std.debug.print("torchlight behind a pillar {d:.3}, beside it {d:.3}\n", .{ behind, beside });
    try std.testing.expectApproxEqAbs(@as(f32, 0), behind, 1e-5);
    try std.testing.expect(beside > 0.05);
}

fn stepUntil(l: *light.Light, lv: *const grid.Level, q: [2]f32, comptime done: fn (f32) bool) usize {
    var frames: usize = 0;
    var ids: [light.LIGHTS]light.TorchIx = undefined;
    const none = ids[0..0];
    while (frames < 600 and !done(lum(l.at(lv, none, q)))) : (frames += 1) l.step(lv, mathx.FRAME_DT);
    return frames;
}

test "a cell coming into sight fades up fast, and fades down to memory slower once out of it" {
    var lv = grid.openFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    lightBox(&lv, LIT_BOX);
    const q = [2]f32{ 15.5, 15.5 };
    l.carrier = q;
    const bright = lum(l.base() + light.CARRY);
    const dim = lum(light.MEMORY);
    const Up = struct {
        var want: f32 = 0;
        fn f(v: f32) bool {
            return v >= want;
        }
    };
    Up.want = bright * 0.95;
    const up = stepUntil(l, &lv, q, Up.f);
    lv.lightless();
    const Down = struct {
        var want: f32 = 0;
        fn f(v: f32) bool {
            return v <= want;
        }
    };
    Down.want = dim + (bright - dim) * 0.05;
    const down = stepUntil(l, &lv, q, Down.f);
    const ms = struct {
        fn of(frames: usize) f32 {
            return @as(f32, @floatFromInt(frames)) * mathx.FRAME_DT * 1000;
        }
    }.of;
    std.debug.print("fog: 95% of the way into sight in {d:.0} ms, out of it to memory in {d:.0} ms\n", .{ ms(up), ms(down) });
    try std.testing.expect(up > 0 and ms(up) < 333);
    try std.testing.expect(down > up and ms(down) < 1000);
    for (0..600) |_| l.step(&lv, mathx.FRAME_DT);
    try std.testing.expectApproxEqAbs(dim, lum(l.at(&lv, &.{}, q)), 0.002);
}

test "the edge of sight ramps across texels instead of stepping at a cell" {
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| {
        lv.seen[i] = true;
        lv.lit[i] = grid.Level.of(i).x < 20;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.sky = sky.at(day.NOON);
    l.bake(&lv, .{ .x = 10, .y = 25 }, .{ .x = 30, .y = 35 });
    const row: i32 = 30 * light.SUB;
    var biggest: f32 = 0;
    var ramp: usize = 0;
    const from = lum(rgbOf(l.texels.getPtrConst(.map)[@intCast(row * light.MAP_W + 12 * light.SUB)]));
    const to = lum(rgbOf(l.texels.getPtrConst(.map)[@intCast(row * light.MAP_W + 28 * light.SUB)]));
    var tx: i32 = 12 * light.SUB;
    while (tx < 28 * light.SUB) : (tx += 1) {
        const a = lum(rgbOf(l.texels.getPtrConst(.map)[@intCast(row * light.MAP_W + tx)]));
        const b = lum(rgbOf(l.texels.getPtrConst(.map)[@intCast(row * light.MAP_W + tx + 1)]));
        biggest = @max(biggest, @abs(b - a));
        if (@abs(b - a) > 0.001) ramp += 1;
    }
    const jump = @abs(to - from);
    std.debug.print("fog edge: {d} texels of ramp, the steepest step {d:.0}% of the jump\n", .{ ramp, biggest / jump * 100 });
    try std.testing.expect(ramp >= light.SUB * 2);
    try std.testing.expect(biggest < jump * 0.2);
}

test "a baked texel is exactly the light `at` gives its middle, fading or never seen" {
    var lv: grid.Level = undefined;
    const f = gen.build(&lv, 0xBA4E);
    fov.cast(&lv, f.start, actor.row(.archer).sight);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    fov.cast(&lv, f.rooms[1].centre(), actor.row(.archer).sight);
    l.carrier = mathx.centre(f.start);
    for (0..4) |_| l.step(&lv, mathx.FRAME_DT);
    l.bake(&lv, .{ .x = 0, .y = 0 }, grid.SIZE);
    var ids: [light.LIGHTS]light.TorchIx = undefined;
    const torches = l.near(grid.Box.inMap(-1), &ids);
    var dark: usize = 0;
    var fading: usize = 0;
    var off: usize = 0;
    for (0..light.TEXELS) |i| {
        const q = light.Light.texelCentreOf(i);
        const m = l.memoryAt(mathx.cellOf(q));
        if (m == 0) dark += 1;
        if (m > 0 and m < 1) fading += 1;
        const want = light.texelOf(l.at(&lv, torches, q), l.viewAt(q).lit);
        if (!std.meta.eql(want, l.texels.getPtrConst(.map)[i])) off += 1;
    }
    std.debug.print("whole floor baked: {d} texels never seen, {d} fading in, {d} off what `at` gives\n", .{ dark, fading, off });
    try std.testing.expect(dark > 0 and fading > 0);
    try std.testing.expectEqual(@as(usize, 0), off);
}

test "clipped light baking clears unseen texels without touching adjacent rows or columns" {
    var lv = grid.openFloor();
    lv.light(.{ .x = 3, .y = 3 });
    lv.light(.{ .x = 4, .y = 3 });
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const sentinel = rl.Color{ .r = 17, .g = 31, .b = 47, .a = 63 };
    var touched: usize = 0;
    var dark: usize = 0;
    var visible: usize = 0;
    const cases = [_]grid.Box{
        .{ .lo = .{ .x = 0, .y = 0 }, .hi = .{ .x = 1, .y = 1 } },
        .{ .lo = .{ .x = 2, .y = 2 }, .hi = .{ .x = 4, .y = 4 } },
        .{ .lo = .{ .x = grid.W - 1, .y = grid.H - 1 }, .hi = grid.SIZE },
    };
    for (cases) |box| {
        for (std.enums.values(light.Layer)) |k| @memset(l.texels.getPtr(k), sentinel);
        l.bake(&lv, box.lo, box.hi);
        for (0..light.TEXELS) |i| {
            const t = mathx.unslot(i, light.Light.TEXELS_W);
            const inside = t.x >= box.lo.x * light.SUB - 1 and t.x < box.hi.x * light.SUB + 1 and
                t.y >= box.lo.y * light.SUB - 1 and t.y < box.hi.y * light.SUB + 1;
            if (!inside) {
                for (std.enums.values(light.Layer)) |k| try std.testing.expectEqual(sentinel, l.texels.getPtrConst(k)[i]);
                continue;
            }
            touched += 1;
            const q = light.Light.texelCentreOf(i);
            const v = l.viewAt(q);
            if (l.memoryAt(mathx.cellOf(q)) == 0) dark += 1 else visible += 1;
            try std.testing.expectEqual(light.texelOf(l.at(&lv, &.{}, q), v.lit), l.texels.getPtrConst(.map)[i]);
            try std.testing.expectEqual(look.fade(rl.Color.white, 1 - v.memory), l.texels.getPtrConst(.fog)[i]);
            try std.testing.expectEqual(light.UNSEEN.get(.glints), l.texels.getPtrConst(.glints)[i]);
        }
    }
    try std.testing.expect(dark > 0 and visible > 0);
    std.debug.print("clipped light baking: {d} texels updated ({d} unseen, {d} visible); adjacent texels preserved in all 3 layers\n", .{ touched, dark, visible });
}

test "fog tint follows the soft exploration edge without changing visibility" {
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| {
        lv.seen[i] = grid.Level.of(i).x < 20;
        lv.lit[i] = lv.seen[i];
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const seen = lv.seen;
    const lit = lv.lit;
    l.bake(&lv, .{ .x = 18, .y = 20 }, .{ .x = 22, .y = 21 });
    var clear: usize = 0;
    var soft: usize = 0;
    var covered: usize = 0;
    for (20 * light.SUB..21 * light.SUB) |y| {
        for (18 * light.SUB..22 * light.SUB) |x| {
            const pixel = l.texels.getPtrConst(.fog)[y * light.MAP_W + x];
            try std.testing.expectEqual(rl.Color.white.r, pixel.r);
            try std.testing.expectEqual(rl.Color.white.g, pixel.g);
            try std.testing.expectEqual(rl.Color.white.b, pixel.b);
            if (pixel.a == 0) clear += 1 else if (pixel.a == 255) covered += 1 else soft += 1;
            if (x >= 20 * light.SUB) try std.testing.expectEqual(@as(u8, 255), pixel.a);
            if (x < 19 * light.SUB) try std.testing.expectEqual(@as(u8, 0), pixel.a);
        }
    }
    try std.testing.expect(clear > 0 and soft > 0 and covered > 0);
    try std.testing.expectEqualSlices(bool, &seen, &lv.seen);
    try std.testing.expectEqualSlices(bool, &lit, &lv.lit);
    std.debug.print("fog tint: {d} clear, {d} soft and {d} opaque texels; sight and exploration unchanged\n", .{ clear, soft, covered });
}

test "remembered ground fades to black exactly at the edge of what was ever seen" {
    var lv = grid.openFloor();
    for (0..grid.CELLS) |i| lv.seen[i] = grid.Level.of(i).x < 20;
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const full = lum(l.at(&lv, &.{}, .{ 15.5, 30.5 }));
    const at_edge = lum(l.at(&lv, &.{}, .{ 20.0 - EDGE_EPS, 30.5 }));
    const half_in = lum(l.at(&lv, &.{}, .{ 19.5, 30.5 }));
    const one_in = lum(l.at(&lv, &.{}, .{ 19.0, 30.5 }));
    const two_in = lum(l.at(&lv, &.{}, .{ 18.0, 30.5 }));
    var biggest: f32 = 0;
    var x: f32 = 16;
    while (x < 20) : (x += 1.0 / @as(f32, @floatFromInt(light.SUB))) {
        biggest = @max(biggest, @abs(lum(l.at(&lv, &.{}, .{ x + 0.25, 30.5 })) - lum(l.at(&lv, &.{}, .{ x, 30.5 }))));
    }
    std.debug.print("memory at the edge of the unseen: {d:.3} on the line, {d:.3} half a cell in, {d:.3} one in, {d:.3} two in, {d:.3} deep; steepest texel step {d:.0}% of full\n", .{ at_edge, half_in, one_in, two_in, full, biggest / full * 100 });
    try std.testing.expectApproxEqAbs(@as(f32, 0), at_edge, 1e-4);
    try std.testing.expect(half_in < one_in and one_in < two_in);
    try std.testing.expect(two_in > full * 0.97);
    try std.testing.expect(biggest < full * 0.3);
}

test "remembered ground is black on every line where a seen cell meets an unseen one" {
    var lv: grid.Level = undefined;
    const l = try light.Light.create(std.testing.allocator);
    defer std.testing.allocator.destroy(l);
    const sight = actor.row(.archer).sight;
    const full = lum(light.MEMORY);
    var lines: usize = 0;
    var bright: usize = 0;
    var worst: f32 = 0;
    for (0..10) |n| {
        const f = gen.build(&lv, 0x5EE +% n *% grid.TEST_SEED_STRIDE);
        for (f.rooms[0..@min(3, f.room_n)]) |r| fov.cast(&lv, r.centre(), sight);
        lv.lightless();
        l.settle(&lv);
        for (0..grid.CELLS) |i| {
            if (!lv.seen[i]) continue;
            const a = grid.Level.of(i);
            for ([_]mathx.Dir{ .n, .e, .s, .w }) |d| {
                const b = a.add(d.delta());
                if (!grid.Level.inside(b) or lv.isSeen(b)) continue;
                lines += 1;
                const ax: f32 = @floatFromInt(a.x);
                const ay: f32 = @floatFromInt(a.y);
                var most: f32 = 0;
                for ([_]f32{ 0, 0.25, 0.5, 0.75, 1 - EDGE_EPS }) |t| {
                    const q: [2]f32 = switch (d) {
                        .n => .{ ax + t, ay },
                        .s => .{ ax + t, ay + 1 - EDGE_EPS },
                        .w => .{ ax, ay + t },
                        else => .{ ax + 1 - EDGE_EPS, ay + t },
                    };
                    most = @max(most, lum(l.at(&lv, &.{}, q)) / full);
                }
                if (most > 0.05) bright += 1;
                worst = @max(worst, most);
            }
        }
    }
    std.debug.print("{d} lines between seen and unseen over 10 floors, {d} showing memory above 5%, the brightest {d:.0}% of full\n", .{ lines, bright, worst * 100 });
    try std.testing.expect(lines > 500);
    try std.testing.expect(worst < 0.01);
}

test "a doorway sight skips in a hall's side wall leaves no dark patch in the hall" {
    var lv = grid.Level.blank();
    var x: i32 = 5;
    while (x <= 40) : (x += 1) lv.set(.{ .x = x, .y = 20 }, .floor);
    const door = P{ .x = 25, .y = 21 };
    lv.set(door, .floor);
    var y: i32 = 22;
    while (y <= 26) : (y += 1) {
        x = 22;
        while (x <= 28) : (x += 1) lv.set(.{ .x = x, .y = y }, .floor);
    }
    gen.shapeWalls(&lv);
    fov.cast(&lv, .{ .x = 20, .y = 20 }, actor.row(.archer).sight);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = .{ 20.5, 20.5 };
    try std.testing.expect(!lv.isSeen(door));
    std.debug.print("hall light by cells from the archer, a doorway sight skips at 5:", .{});
    var worst: f32 = 0;
    x = 20;
    while (x < 30) : (x += 1) {
        const d: f32 = @floatFromInt(x - 20);
        const v = lum(l.at(&lv, &.{}, .{ 20.5 + d, 20.5 }));
        std.debug.print(" {d}:{d:.3}", .{ d, v });
        worst = @max(worst, @abs(v - lum(l.base() + light.CARRY * splat(light.carryFade(d)))));
    }
    std.debug.print("; furthest off the carried light alone {d:.4}\n", .{worst});
    try std.testing.expect(worst < 1e-3);
    try std.testing.expectEqual(@as(f32, 0), lum(l.at(&lv, &.{}, .{ 25.5, 21.5 })));
}

test "a flame flickers within a tenth or so either way and never jumps" {
    var lo: f32 = 2;
    var hi: f32 = 0;
    var jump: f32 = 0;
    var last = light.flicker(0, 7);
    var i: usize = 1;
    const minute: usize = @intFromFloat(@round(60 / mathx.FRAME_DT));
    while (i < minute) : (i += 1) {
        const v = light.flicker(@as(f32, @floatFromInt(i)) * mathx.FRAME_DT, 7);
        lo = @min(lo, v);
        hi = @max(hi, v);
        jump = @max(jump, @abs(v - last));
        last = v;
    }
    std.debug.print("flicker over a minute: {d:.3} to {d:.3}, at most {d:.4} a frame at 60 Hz\n", .{ lo, hi, jump });
    try std.testing.expect(lo >= 1 - light.FLICKER and hi <= 1 + light.FLICKER);
    try std.testing.expect(hi - lo > light.FLICKER);
    try std.testing.expect(jump < 0.03);
}

test "a shadow fades through zero as a body passes directly under a torch" {
    var s = light.Shine{ .ambient = light.MEMORY };
    s.add(.{ .drawn = .{ 40.5, 30.5 }, .ground = .{ 40.5, 30.5 }, .colour = splat(1), .casts = true });
    var last: f32 = 0;
    var worst: f32 = 0;
    for (0..201) |i| {
        const dx = (@as(f32, @floatFromInt(i)) - 100) / 100;
        var buf: [light.BODY_LIGHTS]shadow.Cast = undefined;
        const cs = shadow.casts(&s, .{ 40.5 + dx, 30.5 }, ART_H, &buf);
        const alpha = if (cs.len == 0) 0 else cs[0].alpha;
        if (i > 0) worst = @max(worst, @abs(alpha - last));
        if (@abs(dx) <= shadow.SHADOW_OVERHEAD) try std.testing.expectEqual(@as(f32, 0), alpha);
        last = alpha;
    }
    std.debug.print("torch shadow passing under the light: largest alpha step {d:.4}\n", .{worst});
    try std.testing.expect(worst < 0.04);
}

test "torch shadow crosses its light's horizontal line without flipping" {
    var s = light.Shine{ .ambient = light.MEMORY };
    s.add(.{ .drawn = .{ 43.5, 30.5 }, .ground = .{ 43.5, 30.5 }, .colour = splat(1), .casts = true });
    var last: ?[2]f32 = null;
    var worst: f32 = 0;
    for (0..41) |i| {
        const dy = (@as(f32, @floatFromInt(i)) - 20) / 1000;
        var buf: [light.BODY_LIGHTS]shadow.Cast = undefined;
        const cs = shadow.casts(&s, .{ 40.5, 30.5 + dy }, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        try std.testing.expectEqual(@as(f32, 0), cs[0].solid);
        if (last) |was| worst = @max(worst, mathx.len(cs[0].lean[0] - was[0], cs[0].lean[1] - was[1]));
        last = cs[0].lean;
    }
    std.debug.print("torch shadow across the horizontal: largest tip step {d:.4} px\n", .{worst});
    try std.testing.expect(worst < 0.1);
}

test "night lantern on explored ground fades into memory without a dark ring" {
    var lv = grid.openFloor();
    lv.seen = @splat(true);
    const at = P{ .x = 40, .y = 30 };
    lume.see(&lv, at, actor.row(.archer).sight, 0, &.{.{ .at = at, .reach = actor.row(.archer).light }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = mathx.centre(at);
    l.sky = sky.at(day.DEAD_OF_NIGHT);
    var lowest = lum(light.MEMORY);
    var rise: f32 = 0;
    var last = lum(l.at(&lv, &.{}, l.carrier.?));
    for (1..161) |i| {
        const d = @as(f32, @floatFromInt(i)) / 20;
        const value = lum(l.at(&lv, &.{}, .{ 40.5 + d, 30.5 }));
        lowest = @min(lowest, value);
        rise = @max(rise, value - last);
        last = value;
    }
    std.debug.print("night lantern into explored ground: minimum {d:.4}, memory {d:.4}, outward rise {d:.4}\n", .{ lowest, lum(light.MEMORY), rise });
    try std.testing.expect(lowest >= lum(light.MEMORY) - 0.002);
    try std.testing.expect(rise < 0.002);
}

test "moving night light stays above memory at 60 and 144 Hz" {
    const from = P{ .x = 40, .y = 30 };
    for ([_]f32{ 60, 144 }) |hz| {
        var lv = grid.openFloor();
        lv.seen = @splat(true);
        lume.see(&lv, from, actor.row(.archer).sight, 0, &.{.{ .at = from, .reach = actor.row(.archer).light }});
        const l = try testLight(&lv);
        defer std.testing.allocator.destroy(l);
        l.sky = sky.at(day.DEAD_OF_NIGHT);
        const to = from.add(.{ .x = 1, .y = 1 });
        lume.see(&lv, to, actor.row(.archer).sight, 0, &.{.{ .at = to, .reach = actor.row(.archer).light }});
        var lowest = lum(light.MEMORY);
        var worst: f32 = 0;
        var previous: [80]f32 = undefined;
        var frame: usize = 0;
        var t: f32 = 0;
        while (t <= 1) : (t += 1 / hz) {
            const k = @min(1, t / 0.13);
            l.carrier = .{ 40.5 + k, 30.5 + k };
            l.step(&lv, 1 / hz);
            for (0..80) |i| {
                const x = 35.5 + @as(f32, @floatFromInt(i)) / 5;
                const v = lum(l.at(&lv, &.{}, .{ x, 30.5 }));
                lowest = @min(lowest, v);
                if (frame > 0) worst = @max(worst, @abs(v - previous[i]));
                previous[i] = v;
            }
            frame += 1;
        }
        std.debug.print("moving night light at {d} Hz: minimum {d:.4}, largest frame change {d:.4}\n", .{ hz, lowest, worst });
        try std.testing.expect(lowest >= lum(light.MEMORY) - 0.002);
        try std.testing.expect(worst < 0.08);
    }
}

test "cinema lighting stays subtle and leaves night and indoor light unchanged" {
    var lv = grid.openFloor();
    lv.set(.{ .x = 20, .y = 20 }, .shrub);
    lv.set(.{ .x = 21, .y = 20 }, .swamp_tree);
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = null;
    var changed: usize = 0;
    var lowest: f32 = 1;
    var highest: f32 = 1;
    for ([_]?sky.Sky{ null, sky.at(day.NOON), sky.at(day.DEAD_OF_NIGHT) }) |k| {
        l.sky = k;
        for (0..100) |i| {
            const q = [2]f32{ 17 + @as(f32, @floatFromInt(i % 10)) * 0.5, 18 + @as(f32, @floatFromInt(i / 10)) * 0.5 };
            l.composed = false;
            const plain = l.at(&lv, &.{}, q);
            l.composed = true;
            const composed = l.at(&lv, &.{}, q);
            if (k == null or k.?.moon == 1) {
                try std.testing.expectEqual(plain, composed);
            } else {
                const ratio = lum(composed) / lum(plain);
                lowest = @min(lowest, ratio);
                highest = @max(highest, ratio);
                try std.testing.expect(ratio > 0.75 and ratio < 1.1);
                changed += @intFromBool(@abs(ratio - 1) > 0.002);
            }
        }
    }
    try std.testing.expect(changed > 50);
    std.debug.print("cinema lighting: {d} daylight samples changed, {d:.1}-{d:.1}% of baseline; 200 night/indoor samples identical\n", .{ changed, lowest * 100, highest * 100 });
}

test "the carried light fades across what it lets the archer see and leaves that edge above memory" {
    const lv = litFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.carrier = .{ 40.5, 30.5 };
    std.debug.print("carried light on the floor by cells out:", .{});
    var last = std.math.floatMax(f32);
    const edge: f32 = @floatFromInt(actor.row(.archer).light);
    for ([_]f32{ 0, edge * 0.4, edge * 0.8, edge }) |d| {
        const v = lum(l.at(&lv, &.{}, .{ 40.5 + d, 30.5 }));
        std.debug.print(" {d}:{d:.3}", .{ d, v });
        try std.testing.expect(v < last);
        last = v;
    }
    const past = lum(l.at(&lv, &.{}, .{ 40.5 + edge + 1, 30.5 }));
    std.debug.print(", a cell past {d:.3}, memory {d:.3}\n", .{ past, lum(light.MEMORY) });
    try std.testing.expect(last > lum(light.MEMORY));
    try std.testing.expectApproxEqAbs(lum(light.MEMORY), past, 1e-4);
}

test "the carried light reaches no remembered floor behind a wall" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    lv.lightless();
    lv.seen = @splat(true);
    const at = P{ .x = 30, .y = TORCH_AT.y + 1 };
    lume.see(&lv, at, actor.row(.archer).sight, 0, &.{.{ .at = at, .reach = actor.row(.archer).light }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const wy: f32 = @floatFromInt(TORCH_AT.y);
    const spots = [_][2]f32{ .{ 30.5, wy - EDGE_EPS }, .{ 31.5, wy - 0.5 } };
    var dark: [spots.len]f32 = undefined;
    for (spots, &dark) |q, *d| d.* = lum(l.at(&lv, &.{}, q));
    l.carrier = mathx.centre(at);
    std.debug.print("carried light added behind a wall:", .{});
    for (spots, dark) |q, d| {
        const v = lum(l.at(&lv, &.{}, q)) - d;
        std.debug.print(" {d:.4}", .{v});
        try std.testing.expectApproxEqAbs(@as(f32, 0), v, 1e-5);
    }
    const front = lum(l.at(&lv, &.{}, .{ 30.5, wy + 1 + EDGE_EPS }));
    std.debug.print(", at its front {d:.4}\n", .{front - lum(light.MEMORY)});
    try std.testing.expect(front > lum(light.MEMORY) + 0.05);
}

test "daylight reaches no remembered floor behind a wall in sight" {
    var lv = grid.openFloor();
    wallAcross(&lv);
    gen.shapeWalls(&lv);
    for (0..grid.CELLS) |i| {
        lv.seen[i] = true;
        lv.lit[i] = grid.Level.of(i).y >= TORCH_AT.y;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.sky = sky.at(day.NOON);
    const wy: f32 = @floatFromInt(TORCH_AT.y);
    std.debug.print("noon behind a wall in sight, over memory:", .{});
    for ([_][2]f32{ .{ 30.5, wy - 1.5 }, .{ 30.5, wy - 0.5 }, .{ 30.5, wy - EDGE_EPS } }) |q| {
        const v = lum(l.at(&lv, &.{}, q)) - lum(light.MEMORY);
        std.debug.print(" {d:.4}", .{v});
        try std.testing.expectApproxEqAbs(@as(f32, 0), v, 1e-5);
    }
    const front = lum(l.at(&lv, &.{}, .{ 30.5, wy + 1.5 }));
    std.debug.print(", in front {d:.4}\n", .{front - lum(light.MEMORY)});
    try std.testing.expect(front > lum(light.MEMORY) + 0.1);
}

test "a cell is clear exactly when every cell within its fade's reach is wholly remembered" {
    var lv = grid.openFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var rng = mathx.Rng.init(0xC1EA);
    const r = light.VOID_REACH;
    var n: usize = 0;
    for (0..20) |_| {
        for (&l.visibility.memory) |*m| m.* = if (rng.percent(97)) 1 else 0.5;
        l.visibility.soften();
        for (0..grid.CELLS) |i| {
            const c = grid.Level.of(i);
            var want = grid.Box.inMap(r).holds(c);
            var box = grid.Cells.around(c, r);
            while (box.next()) |p| want = want and l.memoryAt(p) >= 1;
            try std.testing.expectEqual(want, l.visibility.clear[i]);
            if (want) n += 1;
        }
    }
    std.debug.print("20 memories: {d} cells clear, each as the box round it says\n", .{n});
    try std.testing.expect(n > 0);
}

test "sight has no step where it ends along a wall, nor as it eases out behind one" {
    var lv = grid.openFloor();
    wallAcross(&lv);
    gen.shapeWalls(&lv);
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        lv.seen[i] = true;
        lv.lit[i] = p.y >= TORCH_AT.y and p.x <= 30;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const fy: f32 = @floatFromInt(TORCH_AT.y + 1);
    const step = l.sightAt(31 + EDGE_EPS, fy + 0.5) - l.sightAt(31 - EDGE_EPS, fy + 0.5);
    const behind = grid.Level.idx(.{ .x = 20, .y = TORCH_AT.y - 1 });
    l.visibility.sight[behind] = 2 * mathx.SETTLE;
    l.visibility.soften();
    const easing = l.sightAt(20.5, fy - 1.5);
    l.visibility.sight[behind] = 0;
    l.visibility.soften();
    const gone = l.sightAt(20.5, fy - 1.5);
    std.debug.print("sight across its edge along a wall: {d:.4}; behind a wall, easing out {d:.4}, then gone {d:.4}\n", .{ step, easing, gone });
    try std.testing.expectApproxEqAbs(@as(f32, 0), step, 1e-3);
    try std.testing.expectApproxEqAbs(gone, easing, 1e-2);
}

test "sight has no step where open ground meets a shrub at its edge" {
    var lv = grid.openFloor();
    const shrub = P{ .x = 30, .y = 20 };
    lv.set(shrub, .shrub);
    for (0..grid.CELLS) |i| {
        const p = grid.Level.of(i);
        lv.seen[i] = true;
        lv.lit[i] = p.x <= shrub.x or p.y != shrub.y;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const y = mathx.centre(shrub)[1];
    const x: f32 = @floatFromInt(shrub.x + 1);
    const past = l.sightAt(x + EDGE_EPS, y);
    const step = past - l.sightAt(x - EDGE_EPS, y);
    const own = l.visibility.open_sight[grid.Level.idx(.{ .x = shrub.x + 1, .y = shrub.y })];
    std.debug.print("sight across a shrub's edge where sight ends: {d:.4}; just past it {d:.4}, its ground's own {d:.4}\n", .{ step, past, own });
    try std.testing.expectApproxEqAbs(@as(f32, 0), step, 1e-3);
    try std.testing.expectApproxEqAbs(own, past, 1e-3);
}

test "sight has no step through a shrub clump, nor as the ground behind a hedge is first seen" {
    var lv = grid.openFloor();
    for ([_]P{ .{ .x = 30, .y = 20 }, .{ .x = 31, .y = 20 }, .{ .x = 30, .y = 21 }, .{ .x = 31, .y = 21 } }) |p| lv.set(p, .shrub);
    for (0..grid.CELLS) |i| {
        lv.seen[i] = true;
        lv.lit[i] = grid.Level.of(i).y <= 20;
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const step = l.sightAt(30.6, 20.5 + EDGE_EPS) - l.sightAt(30.6, 20.5 - EDGE_EPS);
    var hedge = grid.openFloor();
    var y: i32 = 1;
    while (y < grid.H - 1) : (y += 1) hedge.set(.{ .x = 30, .y = y }, .shrub);
    for (0..grid.CELLS) |i| {
        hedge.seen[i] = grid.Level.of(i).x <= 30;
        hedge.lit[i] = hedge.seen[i];
    }
    const h = try testLight(&hedge);
    defer std.testing.allocator.destroy(h);
    const unseen = h.sightAt(30.6, 20.5);
    const behind = grid.Level.idx(.{ .x = 31, .y = 20 });
    h.visibility.sight[behind] = 2 * mathx.SETTLE;
    h.visibility.memory[behind] = 2 * mathx.SETTLE;
    h.visibility.soften();
    const glimpsed = h.sightAt(30.6, 20.5);
    std.debug.print("sight through a shrub clump's middle: {d:.4}; behind a hedge, unseen {d:.4}, first glimpsed {d:.4}\n", .{ step, unseen, glimpsed });
    try std.testing.expectApproxEqAbs(@as(f32, 0), step, 1e-2);
    try std.testing.expectApproxEqAbs(unseen, glimpsed, 1e-2);
}

test "a shrub in sight at the edge of what was ever seen is not dimmed toward the cells never seen" {
    var lv = grid.openFloor();
    const shrub = P{ .x = 30, .y = 20 };
    lv.set(shrub, .shrub);
    for (0..grid.CELLS) |i| {
        lv.seen[i] = grid.Level.of(i).x >= shrub.x;
        lv.lit[i] = lv.seen[i];
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const v = l.sightAt(@as(f32, @floatFromInt(shrub.x)) + EDGE_EPS, mathx.centre(shrub)[1]);
    std.debug.print("sight at a shrub's unexplored edge: {d:.4}\n", .{v});
    try std.testing.expectApproxEqAbs(@as(f32, 1), v, 1e-3);
}

test "a torch on a wall never seen has no flame to draw, though the floor below it is in sight" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    lv.lightless();
    @memset(&lv.seen, false);
    lv.light(lume.torchFloor(TORCH_AT));
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var buf: [light.LIGHTS]light.Flame = undefined;
    const got = l.flames(&lv, &buf);
    std.debug.print("unseen torch over a floor in sight: {d} flame(s), lit {d:.3}\n", .{ got.len, if (got.len > 0) got[0].lit else 0 });
    try std.testing.expectEqual(@as(usize, 0), got.len);
}

test "a torch seen only from behind its wall has no flame, and a remembered one fades up with its wall" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    lv.lightless();
    @memset(&lv.seen, false);
    for (0..grid.CELLS) |i| {
        if (grid.Level.of(i).y <= TORCH_AT.y) lv.light(grid.Level.of(i));
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var buf: [light.LIGHTS]light.Flame = undefined;
    try std.testing.expect(lv.isSeen(TORCH_AT));
    try std.testing.expectEqual(@as(usize, 0), l.flames(&lv, &buf).len);
    @memset(&lv.seen, false);
    lv.lightless();
    l.settle(&lv);
    @memset(&lv.lit, true);
    @memset(&lv.seen, true);
    l.step(&lv, mathx.FRAME_DT);
    const first = l.flames(&lv, &buf)[0].memory;
    for (0..120) |_| l.step(&lv, mathx.FRAME_DT);
    const settled = l.flames(&lv, &buf)[0].memory;
    std.debug.print("a torch coming into sight: its remembered flame at {d:.3} the first frame, {d:.3} two seconds on\n", .{ first, settled });
    try std.testing.expect(first < 0.3);
    try std.testing.expectEqual(@as(f32, 1), settled);
}

test "a remembered torch seen again from behind its wall burns at memory, not live" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    lv.lightless();
    @memset(&lv.seen, true);
    for (0..grid.CELLS) |i| {
        if (grid.Level.of(i).y <= TORCH_AT.y) lv.light(grid.Level.of(i));
    }
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.settle(&lv);
    for (0..240) |_| l.step(&lv, mathx.FRAME_DT);
    var buf: [light.LIGHTS]light.Flame = undefined;
    const got = l.flames(&lv, &buf);
    try std.testing.expectEqual(@as(usize, 1), got.len);
    std.debug.print("remembered torch from behind its wall: flame lit {d:.3}, memory {d:.3}\n", .{ got[0].lit, got[0].memory });
    try std.testing.expect(got[0].lit <= light.FAINT);
}

fn castAlpha(l: *const light.Light, at: [2]f32, carrier: bool) [2]f32 {
    var buf: [light.BODY_LIGHTS]shadow.Cast = undefined;
    const cs = shadow.casts(&l.onBody(at, carrier), at, ART_H, &buf);
    if (cs.len == 0) return .{ 0, 0 };
    return .{ cs[0].alpha, cs[0].len };
}

test "a cast shadow fades out smoothly as its body walks away from the torch" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const fl = l.torch[0].flame();
    const Row = struct { name: []const u8, carrier: ?f32, carrying: bool };
    var steepest: f32 = 0;
    var nearest_end: f32 = std.math.floatMax(f32);
    for ([_]Row{ .{ .name = "alone", .carrier = null, .carrying = false }, .{ .name = "archer", .carrier = 0, .carrying = true }, .{ .name = "rat by archer", .carrier = 2, .carrying = false } }) |r| {
        std.debug.print("shadow alpha/px, {s}, by cells from the flame:", .{r.name});
        var last: ?f32 = null;
        var worst: f32 = 0;
        var gone: f32 = 0;
        var d: f32 = 0.5;
        while (d < @as(f32, @floatFromInt(light.REACH)) + 0.5) : (d += 0.0625) {
            const at = [2]f32{ fl[0] + d, fl[1] + 0.5 };
            l.carrier = if (r.carrier) |c| .{ at[0] + c, at[1] } else null;
            const v = castAlpha(l, at, r.carrying);
            if (@mod(d, 1) == 0.5) std.debug.print(" {d:.1}:{d:.2}/{d:.0}", .{ d, v[0], v[1] });
            if (last) |was| worst = @max(worst, was - v[0]);
            if (v[0] > 0) gone = d;
            last = v[0];
        }
        std.debug.print("; biggest drop per 1/16 cell {d:.3}, last cast at {d:.2}\n", .{ worst, gone });
        steepest = @max(steepest, worst);
        nearest_end = @min(nearest_end, gone);
    }
    try std.testing.expect(steepest < 0.07);
    try std.testing.expect(nearest_end + 0.0625 >= @as(f32, @floatFromInt(light.REACH)) - 1.5);
}

test "a body is lit as the ground under it is, fading into sight and on the edge of the unseen" {
    var lv = grid.openFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    lightBox(&lv, LIT_BOX);
    l.carrier = .{ 15.5, 15.5 };
    var worst: f32 = 0;
    var first: [2]f32 = undefined;
    for (0..30) |frame| {
        l.step(&lv, mathx.FRAME_DT);
        for ([_][2]f32{ .{ 15.5, 15.5 }, .{ 18.5, 12.5 }, .{ 20.5, 15.5 }, .{ 20.9, 20.9 } }, 0..) |c, k| {
            const body = l.onBody(c, false);
            const on = lum(body.ambient + body.total());
            const ground = lum(l.at(&lv, &.{}, c));
            if (frame == 0 and k == 0) first = .{ on, ground };
            worst = @max(worst, @abs(on - ground));
        }
    }
    std.debug.print("a body and its ground fading into sight: {d:.3} and {d:.3} the first frame, at most {d:.5} apart\n", .{ first[0], first[1], worst });
    try std.testing.expect(worst < light.FAINT);
}

test "a body takes its torch's light from where the flame is drawn, and none from behind a pillar" {
    var lv: grid.Level = undefined;
    testRoom(&lv, &.{.{ .x = 20, .y = 13 }});
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const open = l.onBody(.{ 23.5, 13.5 }, false);
    try std.testing.expectEqual(@as(usize, 1), open.n);
    try std.testing.expect(open.lamp[0].drawn[0] < 23.5 and open.lamp[0].drawn[1] < 13.5);
    try std.testing.expectEqual(@as(usize, 0), l.onBody(.{ 20.5, 15.5 }, false).n);
    l.carrier = .{ 30.5, 20.5 };
    const near_carrier = l.onBody(.{ 33.5, 20.5 }, false);
    const carrying = l.onBody(.{ 30.5, 20.5 }, true);
    std.debug.print("a rat 3 east of the archer has {d} light(s), the archer {d} and ambient {d:.3}\n", .{ near_carrier.n, carrying.n, lum(carrying.ambient) });
    try std.testing.expectEqual(@as(usize, 1), near_carrier.n);
    try std.testing.expect(near_carrier.lamp[0].drawn[0] < 33.5);
    try std.testing.expect(!near_carrier.lamp[0].casts);
    try std.testing.expect(open.lamp[0].casts);
    try std.testing.expectEqual(@as(usize, 0), carrying.n);
    try std.testing.expect(lum(carrying.ambient) > lum(light.MEMORY + light.CARRY) * 0.95);
}

const ART_H: f32 = @floatFromInt(look.SPRITE_PX);

/// From the middle of `c`, cells away from the sky's light along the ground until the point is half lit.
fn shadowLength(lv: *const grid.Level, k: sky.Sky, c: P) f32 {
    const u = k.across();
    const m = mathx.centre(c);
    var d: f32 = 0;
    while (d < 12) : (d += 0.01) {
        const x = m[0] - u[0] * d;
        const y = m[1] - u[1] * d;
        if (!mathx.cellOf(.{ x, y }).eq(c) and light.sunlit(lv, light.SunRay.of(k), x, y, 0) > 0.5) return d;
    }
    return d;
}

test "the sun throws a thing's shadow its height times the hour's reach, away from the sun, and none on itself" {
    var lv = grid.openFloor();
    const rock = P{ .x = 30, .y = 30 };
    const bush = P{ .x = 60, .y = 30 };
    lv.set(rock, .rock);
    lv.set(bush, .grave);
    for ([_]f32{ 9, 13, 16.5 }) |hour| {
        const k = sky.at(hour);
        const rock_len = shadowLength(&lv, k, rock);
        const bush_len = shadowLength(&lv, k, bush);
        const b = light.CASTERS.get(.grave).?;
        const tip = b.h * k.reach() + b.r.?;
        std.debug.print("at {d:.1}h, reach {d:.2}: a rock's shadow runs {d:.2} cells from its middle, a grave's {d:.2} (its top's tip {d:.2})\n", .{ hour, k.reach(), rock_len, bush_len, tip });
        try std.testing.expect(rock_len > k.reach() * light.WALL_H * (1 - light.SUN_SOFT) and rock_len < k.reach() * light.WALL_H + 0.75);
        try std.testing.expect(bush_len > tip - light.SUN_SOFT * b.h * k.reach() - light.SUN_EDGE and bush_len <= tip);
        const m = mathx.centre(rock);
        const u = k.across();
        try std.testing.expectEqual(@as(f32, 1), light.sunlit(&lv, light.SunRay.of(k), m[0] + u[0] * 0.6, m[1] + u[1] * 0.6, 0));
    }
}

test "everything that blocks a step and does not stand shades the ground past its edge away from the sun, morning, noon and evening" {
    const at = P{ .x = 30, .y = 30 };
    const m = mathx.centre(at);
    for (std.enums.values(grid.Tile)) |t| {
        if (!t.upright() or look.stands(t)) continue;
        var lv = grid.openFloor();
        lv.set(at, t);
        var worst: f32 = 0;
        for ([_]f32{ 8, 12, 17 }) |hour| {
            const k = sky.at(hour);
            const ux = k.across()[0];
            const uy = k.across()[1];
            const edge = light.CASTERS.get(t).?.r orelse 0.5 / @max(@abs(ux), @abs(uy));
            const past = edge + 0.05;
            const shade = light.sunlit(&lv, light.SunRay.of(k), m[0] - ux * past, m[1] - uy * past, 0);
            worst = @max(worst, shade);
            if (light.CASTERS.get(t).?.r != null) try std.testing.expectEqual(@as(f32, 1), light.sunlit(&lv, light.SunRay.of(k), m[0], m[1], light.topOf(t, at, m)));
        }
        std.debug.print("a {s}: the ground just past its edge takes at most {d:.2} of the sun\n", .{ @tagName(t), worst });
        try std.testing.expect(worst < 0.3);
    }
}

test "a standing shrub takes the sun as a body does, and throws its shadow the same length away from it" {
    var lv = litFloor();
    const shrub = P{ .x = 30, .y = 30 };
    const foe = P{ .x = 40, .y = 30 };
    lv.set(shrub, .shrub);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    l.sky = sky.at(16.5);
    var out: [2][light.BODY_LIGHTS]shadow.Cast = undefined;
    var lean: [2][2]f32 = undefined;
    for ([_]P{ shrub, foe }, 0..) |c, i| {
        const s = l.onBody(mathx.centre(c), false);
        const cs = shadow.casts(&s, mathx.centre(c), ART_H, &out[i]);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        lean[i] = cs[0].lean;
    }
    std.debug.print("at 16.5h a shrub's shadow leans {d:.1},{d:.1} px, a foe's {d:.1},{d:.1}\n", .{ lean[0][0], lean[0][1], lean[1][0], lean[1][1] });
    for (0..2) |k| try std.testing.expectApproxEqAbs(lean[1][k], lean[0][k], 1e-3);
    try std.testing.expect(lean[0][0] > 0);
}

test "a body's sun shadow runs the way the ground's do, its height times the hour's reach" {
    const lv = litFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const at = mathx.centre(.{ .x = 40, .y = 30 });
    for ([_]f32{ 9, 13, 16.5 }) |hour| {
        l.sky = sky.at(hour);
        var buf: [light.BODY_LIGHTS]shadow.Cast = undefined;
        const cs = shadow.casts(&l.onBody(at, false), at, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        const u = l.sky.?.across();
        const want = ART_H * l.sky.?.reach();
        std.debug.print("at {d:.1}h a body's shadow leans {d:.1},{d:.1} px, the ground's {d:.1},{d:.1}\n", .{ hour, cs[0].lean[0], cs[0].lean[1], -u[0] * want, -u[1] * want });
        for (0..2) |k| try std.testing.expectApproxEqAbs(-u[k] * want, cs[0].lean[k], 1e-2);
    }
}

test "skipping the sun's march where nothing that casts is near changes nothing it would have found" {
    const procgen = @import("../map/procgen.zig");
    var lv: grid.Level = undefined;
    procgen.roll(&lv, 0x5A7, &.{}, procgen.Floor.of(.wilds), &.{});
    lv.set(.{ .x = 40, .y = 30 }, .rock);
    lv.set(.{ .x = 41, .y = 30 }, .fence);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    var skipped: usize = 0;
    var checked: usize = 0;
    for ([_]f32{ 7, 12, 16.5, 19.5 }) |h| {
        const k = sky.at(h);
        var i: usize = 0;
        while (i < grid.CELLS) : (i += 3) {
            const c = mathx.centre(grid.Level.of(i));
            for ([_]f32{ 0, 0.4 }) |z| {
                const q = [2]f32{ c[0] + 0.3, c[1] - 0.2 };
                checked += 1;
                try std.testing.expectEqual(light.sunlit(&lv, light.SunRay.of(k), q[0], q[1], z), l.sunAt(&lv, &light.SunRay.of(k), q[0], q[1], z));
                const b = light.Light.sunBox(light.SunRay.of(k), q[0], q[1], z);
                if (l.castersIn(b) == 0) skipped += 1;
            }
        }
    }
    std.debug.print("a wilds floor: {d} of {d} sun rays skip the march, every answer the same\n", .{ skipped, checked });
    try std.testing.expect(skipped > checked / 4);
}

test "a sun shadow turns smoothly through due east and due west, never flipping across the feet" {
    const lv = litFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const at = mathx.centre(.{ .x = 40, .y = 30 });
    var worst: f32 = 0;
    for ([_][2]f32{ .{ 5.2, 5.9 }, .{ 20.1, 20.6 } }) |span| {
        var was: ?[2]f32 = null;
        var h = span[0];
        while (h < span[1]) : (h += 0.005) {
            l.sky = sky.at(h);
            var buf: [light.BODY_LIGHTS]shadow.Cast = undefined;
            const cs = shadow.casts(&l.onBody(at, false), at, ART_H, &buf);
            if (cs.len == 0) {
                was = null;
                continue;
            }
            if (was) |w| worst = @max(worst, @abs(cs[0].lean[1] - w[1]));
            was = cs[0].lean;
        }
    }
    std.debug.print("a sun shadow's lean up or down the screen moves at most {d:.2} px in 18 game seconds\n", .{worst});
    try std.testing.expect(worst < 3);
}

test "under the sky, ground in the sun outshines ground in shade, and night is darker than both" {
    const morning: f32 = 9;
    var lv = litFloor();
    const rock = P{ .x = 30, .y = 30 };
    lv.set(rock, .rock);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const none: []const light.TorchIx = &.{};
    l.sky = sky.at(morning);
    const k = l.sky.?;
    const u = k.across();
    const m = mathx.centre(rock);
    const behind = 0.5 + k.reach() * 0.5;
    const shade = lum(l.at(&lv, none, .{ m[0] - u[0] * behind, m[1] - u[1] * behind }));
    const sun = lum(l.at(&lv, none, .{ m[0] + u[0] * 2, m[1] + u[1] * 2 }));
    l.sky = sky.at(0);
    const night = lum(l.at(&lv, none, .{ m[0] + 5, m[1] }));
    std.debug.print("{d}h ground: {d:.2} in the sun, {d:.2} in a rock's shadow; {d:.3} at midnight\n", .{ morning, sun, shade, night });
    try std.testing.expect(sun > shade * 1.2 and sun < shade * 2 and shade > night * 2.5);
    try std.testing.expect(night >= lum(light.MEMORY));
}

test "the moon throws a cold shadow as deep as the sun's, over the archer's own light too" {
    var lv = litFloor();
    const rock = P{ .x = 30, .y = 30 };
    lv.set(rock, .rock);
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const m = mathx.centre(rock);
    l.carrier = m;
    const foe = mathx.centre(.{ .x = 40, .y = 30 });
    var depth: [2]f32 = undefined;
    var blue: [2]f32 = undefined;
    for ([_]f32{ day.NOON, day.DEAD_OF_NIGHT }, 0..) |h, i| {
        l.sky = sky.at(h);
        var buf: [light.BODY_LIGHTS]shadow.Cast = undefined;
        const cs = shadow.casts(&l.onBody(foe, false), foe, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        depth[i] = cs[0].alpha;
        blue[i] = cs[0].shade[2] / cs[0].shade[0];
    }
    const none: []const light.TorchIx = &.{};
    const k = l.sky.?;
    const u = k.across();
    const off = 0.5 + k.reach() * 0.5;
    const back = [2]f32{ m[0] - u[0] * off, m[1] - u[1] * off };
    const front = [2]f32{ m[0] + u[0] * off, m[1] + u[1] * off };
    const behind = l.at(&lv, none, back);
    const toward = l.at(&lv, none, front);
    const near = 0.65;
    const body_behind = l.onBody(.{ m[0] - u[0] * near, m[1] - u[1] * near }, false).lit();
    const body_toward = l.onBody(.{ m[0] + u[0] * near, m[1] + u[1] * near }, false).lit();
    const ground_near = lum(l.at(&lv, none, .{ m[0] - u[0] * near, m[1] - u[1] * near })) / lum(l.at(&lv, none, .{ m[0] + u[0] * near, m[1] + u[1] * near }));
    std.debug.print("a foe's shadow {d:.2} deep at noon, {d:.2} at 1h, blue over red {d:.2} and {d:.2}; by the archer's own light at 1h, ground behind a rock {d:.3} to {d:.3} in front, blue over red {d:.2} to {d:.2}; just past its edge a body takes {d:.2} of the light in front, the ground {d:.2}\n", .{ depth[0], depth[1], blue[0], blue[1], lum(behind), lum(toward), behind[2] / behind[0], toward[2] / toward[0], body_behind / body_toward, ground_near });
    try std.testing.expect(depth[1] > depth[0] * 0.8 and blue[1] > blue[0]);
    try std.testing.expect(lum(behind) < lum(toward) * 0.9 and behind[2] / behind[0] > toward[2] / toward[0]);
    try std.testing.expect(body_behind / body_toward < 0.9 and body_behind / body_toward > ground_near - 0.05);
}

test "sun and torch shadows thinned to slivers give way to soft streaks" {
    const lv = litFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const at = mathx.centre(.{ .x = 40, .y = 30 });
    var silhouette_at: [3]f32 = undefined;
    for ([_]f32{ day.SUNRISE, 8, day.NOON }, &silhouette_at) |h, *k| {
        l.sky = sky.at(h);
        var buf: [light.BODY_LIGHTS]shadow.Cast = undefined;
        const cs = shadow.casts(&l.onBody(at, false), at, ART_H, &buf);
        try std.testing.expectEqual(@as(usize, 1), cs.len);
        k.* = cs[0].solid;
    }
    var torch_least: f32 = 1;
    var a: f32 = 0;
    while (a < std.math.tau) : (a += 0.01) torch_least = @min(torch_least, shadow.solidity(.{ @cos(a), shadow.lampRise(@sin(a)) }));
    std.debug.print("of a sun shadow, silhouette: {d:.2} at 6h, {d:.2} at 8h, {d:.2} at noon; of a torch's, {d:.2} at least\n", .{ silhouette_at[0], silhouette_at[1], silhouette_at[2], torch_least });
    try std.testing.expect(silhouette_at[0] < 0.1 and silhouette_at[1] > 0.5 and silhouette_at[2] == 1 and torch_least == 0);
}

test "a streak is darkest at the feet and gone at the tip, and a sideways sun shadow runs at most its reach" {
    const lv = litFloor();
    const l = try testLight(&lv);
    defer std.testing.allocator.destroy(l);
    const at = mathx.centre(.{ .x = 40, .y = 30 });
    var longest: f32 = 0;
    var h: f32 = 5.5;
    while (h <= 20.5) : (h += 0.1) {
        l.sky = sky.at(h);
        var buf: [light.BODY_LIGHTS]shadow.Cast = undefined;
        for (shadow.casts(&l.onBody(at, false), at, ART_H, &buf)) |c| longest = @max(longest, c.len / ART_H);
    }
    const mid = 0.5;
    var peak_u: f32 = 0;
    var peak: f32 = 0;
    var u: f32 = 0;
    while (u <= 1) : (u += 0.01) {
        if (shadow.streakAlpha(u, mid) > peak) {
            peak = shadow.streakAlpha(u, mid);
            peak_u = u;
        }
    }
    std.debug.print("a streak peaks {d:.2} along, the feet at {d:.2}, {d:.2} at the tip; the longest sun shadow {d:.2} heights\n", .{ peak_u, shadow.STREAK_FOOT, shadow.streakAlpha(1, mid), longest });
    try std.testing.expectApproxEqAbs(shadow.STREAK_FOOT, peak_u, 0.011);
    try std.testing.expect(shadow.streakAlpha(1, mid) < 1e-3 and longest <= sky.REACH_MAX + 1e-3);
}
