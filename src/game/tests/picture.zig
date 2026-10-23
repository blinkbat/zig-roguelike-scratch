const std = @import("std");
const mathx = @import("../../core/mathx.zig");
const input = @import("../../core/input.zig");
const grid = @import("../../map/grid.zig");
const hud = @import("../../ui/hud.zig");
const actor = @import("../../play/actor.zig");
const bow = @import("../../play/bow.zig");
const burning = @import("../../play/burning.zig");
const flask = @import("../../play/flask.zig");
const skillbar = @import("../../play/skillbar.zig");
const look = @import("../../gfx/look.zig");
const fx = @import("../../gfx/fx.zig");
const vignette = @import("../../gfx/vignette.zig");
const day = @import("../../map/day.zig");
const scene = @import("../scene.zig");
const combat = @import("../combat.zig");
const harness = @import("../harness.zig");
const game = @import("../../game.zig");
const glide = @import("../glide.zig");
const P = mathx.P;
const HERO = actor.HERO;

/// Seconds of frames till a split-off half in `slot` is drawn, and till what is owed it lands.
fn showsAndLands(g: *game.Game, slot: usize) struct { shows: f32, lands: f32 } {
    var shows: ?f32 = null;
    var lands: ?f32 = null;
    var t: f32 = 0;
    while ((shows == null or lands == null) and t < 1) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (shows == null and harness.drawn(g, slot)) shows = t;
        if (lands == null and !g.pic.fx.pending(slot)) lands = t;
    }
    return .{ .shows = shows.?, .lands = lands.? };
}

fn ledge(g: *game.Game) P {
    harness.wallRow(&g.sim.lv, 21, 18, 26);
    return .{ .x = 22, .y = 22 };
}

fn revealed(g: *game.Game, slot: usize) bool {
    return g.pic.split_from[slot] == null;
}

const Ledged = struct { dark: P, half: usize };

/// The gas splits a half off a slime on an unlit ledge into sight as the archer steps; returns before `catchUp`.
fn gassedOffLedge(g: *game.Game) Ledged {
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const dark = ledge(g);
    const id = harness.spawnAt(g, .slime_half, dark, true);
    const half = actor.Pool.slot(harness.spawnAt(g, .slime_quarter, .{ .x = 22, .y = 19 }, true));
    const s = actor.Pool.slot(id);
    g.pic.split_from[half] = s;
    g.sim.pool.move(&g.sim.lv, g.sim.hero, .{ .x = 19, .y = 20 });
    game.castSight(g, .{ .x = 19, .y = 20 });
    var after = g.pic.afterOf(&g.sim, s);
    after.reveals = half;
    g.pic.owed[s].gassed = .{ .kill = false, .after = after };
    g.sim.order_n = 0;
    g.pic.stepGlide(&g.sim, g.cloud, 0);
    return .{ .dark = dark, .half = half };
}

test "the camera shows past the floor only under the hud, keeps the archer clear of it, and centres a small floor" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    game.begin(g, 4321);
    const map_w: f32 = @floatFromInt(game.MAP_PX.x);
    const map_h: f32 = @floatFromInt(game.MAP_PX.y + hud.COVER);
    for ([_]P{ game.WINDOW, game.SCREEN_1440 }) |screen| {
        g.screen = screen;
        for ([_]P{ .{ .x = 0, .y = 0 }, .{ .x = grid.W - 1, .y = grid.H - 1 }, .{ .x = 48, .y = 32 } }) |p| {
            g.sim.heroActor().?.at = p;
            g.pic.snapGlide(&g.sim.pool);
            const v = game.camWant(g);
            try std.testing.expect(v.x >= 0 and v.y >= 0);
            try std.testing.expect(v.x + @as(f32, @floatFromInt(screen.x)) <= map_w);
            try std.testing.expect(v.y + @as(f32, @floatFromInt(g.screen.y)) <= map_h);
            const foot = @as(f32, @floatFromInt((p.y + 1) * game.CELL)) - v.y;
            if (p.y == grid.H - 1) std.debug.print("{d}x{d}: bottom-row archer's foot at {d:.0}, hud top {d}\n", .{ screen.x, screen.y, foot, hud.Layout.of(screen, game.SKILLS_W).top });
            try std.testing.expect(foot <= @as(f32, @floatFromInt(hud.Layout.of(screen, game.SKILLS_W).top)));
        }
    }
    g.screen = .{ .x = game.MAP_PX.x + 200, .y = game.MAP_PX.y + hud.COVER + 100 };
    const v = game.camWant(g);
    try std.testing.expectEqual((map_w - @as(f32, @floatFromInt(g.screen.x))) * 0.5, v.x);
    try std.testing.expectEqual((map_h - @as(f32, @floatFromInt(g.screen.y))) * 0.5, v.y);
}

test "a held walk glides at one steady speed and the camera follows it without surging" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    for ([_]f32{ 60, 144 }) |hz| {
        harness.arena(g, .{ .x = 20, .y = 32 }, &.{});
        g.st = .{};
        const dt = 1.0 / hz;
        const hero = g.sim.heroSlot().?;
        var last = [2]f32{ g.pic.glide[hero].now().x, g.cam.x };
        var lo = [2]f32{ std.math.floatMax(f32), std.math.floatMax(f32) };
        var hi = [2]f32{ 0, 0 };
        var on_last: i32 = 0;
        var on_dir: i32 = 0;
        var flips: usize = 0;
        var t: f32 = 0;
        while (t < 2.0) : (t += dt) {
            harness.walkFrame(g, dt, .e);
            const now = [2]f32{ g.pic.glide[hero].now().x, g.cam.x };
            if (t > 0.8) {
                for (0..2) |k| {
                    lo[k] = @min(lo[k], now[k] - last[k]);
                    hi[k] = @max(hi[k], now[k] - last[k]);
                }
            }
            const on = scene.Cam.of(g).px(g.pic.glide[hero].now()).x;
            if (on != on_last) {
                const dir: i32 = if (on > on_last) 1 else -1;
                if (t > input.Stepper.SETTLE + input.Stepper.DAS + game.GLIDE_S and on_dir != 0 and dir != on_dir) flips += 1;
                on_dir = dir;
            }
            on_last = on;
            last = now;
        }
        std.debug.print("held walk at {d} Hz: body {d:.3}-{d:.3} px/frame, camera {d:.3}-{d:.3} px/frame, archer's screen x reverses {d} times\n", .{ hz, lo[0], hi[0], lo[1], hi[1], flips });
        try std.testing.expect(lo[0] > 0 and hi[0] - lo[0] < 0.05);
        try std.testing.expect(lo[1] > 0 and hi[1] - lo[1] < 0.5);
        try std.testing.expectEqual(@as(usize, 0), flips);
    }
}

test "water footsteps follow the shown ground unit step once, excluding flying units" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var grounded: usize = 0;
    var flying: usize = 0;
    for (std.enums.values(actor.Kind)) |kind| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
        const id = if (kind == HERO) g.sim.hero else harness.spawnAt(g, kind, .{ .x = 24, .y = 20 }, false);
        const slot = actor.Pool.slot(id);
        const from = g.sim.pool.get(id).?.at;
        const to = from.add(mathx.Dir.e.delta());
        g.sim.lv.set(from, .shallows);
        g.sim.lv.set(to, .shallows);
        game.settle(g);
        g.st = .{};
        const initial = g.pic.fx.head;
        const clock = g.sim.clock;
        const rng = g.sim.rng;
        game.update(g, 0.1);
        try std.testing.expectEqual(initial, g.pic.fx.head);
        harness.stepTo(g, id, to);
        const span = g.pic.glide[slot].span();
        g.pic.glide[slot].t = -0.2;
        game.update(g, 0.19);
        try std.testing.expectEqual(initial, g.pic.fx.head);
        game.update(g, 0.01 + span * (game.presentation.SPLASH_AT - 0.1));
        try std.testing.expectEqual(initial, g.pic.fx.head);
        game.update(g, span * 0.2);
        const emitted = g.pic.fx.head;
        if (actor.row(kind).movement == .ground) {
            grounded += 1;
            try std.testing.expect(emitted != initial);
            const at = game.middle(g.pic.glide[slot].now());
            for (g.pic.fx.motes) |m| {
                if (m.life <= 0) continue;
                try std.testing.expect(@abs(m.p[0] - at[0]) < fx.SPLASH_R + 0.03);
                try std.testing.expect(@abs(m.p[1] - at[1] - fx.SPLASH_FOOT) < fx.SPLASH_RY + 0.02);
            }
        } else {
            flying += 1;
            try std.testing.expectEqual(initial, emitted);
        }
        game.update(g, 1);
        try std.testing.expectEqual(emitted, g.pic.fx.head);
        try std.testing.expectEqual(clock, g.sim.clock);
        try std.testing.expectEqual(rng, g.sim.rng);
    }
    try std.testing.expect(grounded > 0 and flying > 0);
    std.debug.print("water footsteps: {d} ground kinds splash once at the shown footfall, {d} flying kind stays dry; no idle effects or simulation changes\n", .{ grounded, flying });
}

test "a long frame that ends a step in shallows and starts the next walk still splashes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const from = P{ .x = 20, .y = 20 };
    const to = P{ .x = 21, .y = 20 };
    harness.arena(g, from, &.{});
    for (0..4) |dx| g.sim.lv.set(from.add(.{ .x = @intCast(dx), .y = 0 }), .shallows);
    game.settle(g);
    g.st = .{};
    const slot = g.sim.heroSlot().?;
    const initial = g.pic.fx.head;
    harness.stepTo(g, g.sim.hero, to);
    const span = g.pic.glide[slot].span();
    g.pic.glide[slot].t = span * (game.presentation.SPLASH_AT - 0.05);
    g.pic.busy = span * (1 - game.presentation.SPLASH_AT + 0.05);
    g.pending = .{ .walk = .e };
    game.update(g, span * (1 - game.presentation.SPLASH_AT + 0.1));
    try std.testing.expect(g.sim.heroActor().?.at.eq(to.add(mathx.Dir.e.delta())));
    try std.testing.expect(g.pic.fx.head != initial);
}

test "water footsteps do not appear on dry ground, hidden steps or melee bumps" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const cases = [_]struct { tile: grid.Tile, hidden: bool = false, bump: bool = false }{
        .{ .tile = .floor },
        .{ .tile = .bridge },
        .{ .tile = .ice },
        .{ .tile = .lava },
        .{ .tile = .shallows, .hidden = true },
        .{ .tile = .shallows, .bump = true },
    };
    for (cases) |case| {
        const from = P{ .x = 20, .y = 20 };
        const to = P{ .x = 21, .y = 20 };
        harness.arena(g, from, &.{});
        g.sim.lv.set(from, .shallows);
        g.sim.lv.set(to, case.tile);
        game.settle(g);
        g.st = .{};
        const initial = g.pic.fx.head;
        const slot = g.sim.heroSlot().?;
        if (case.bump) {
            g.pic.glide[slot] = g.pic.glide[slot].bumping(to, 0);
        } else {
            harness.stepTo(g, g.sim.hero, to);
        }
        if (case.hidden) @memset(&g.sim.lv.lit, false);
        game.update(g, g.pic.glide[slot].span());
        try std.testing.expectEqual(initial, g.pic.fx.head);
    }
    std.debug.print("water footsteps: {d} dry, hidden or attacking cases emit no drops\n", .{cases.len});
}

test "every step is one hop that peaks mid-glide and lands as the glide ends, and the ground under it does not bob" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 32 }, &.{.{ .x = 50, .y = 32 }});
    harness.wakeFoes(g);
    g.st = .{};
    const hero = g.sim.heroSlot().?;
    const dt = harness.TEST_DT;
    var peaks = [_]i32{0} ** actor.MAX;
    var steps: usize = 0;
    var hops: usize = 0;
    var high = false;
    const ground = [2]f32{ g.pic.glide[hero].now().y, g.cam.y };
    var bobbed = false;
    var t: f32 = 0;
    var was = g.sim.heroActor().?.at;
    while (t < 1.5) : (t += dt) {
        harness.walkFrame(g, dt, .e);
        if (!g.sim.heroActor().?.at.eq(was)) steps += 1;
        was = g.sim.heroActor().?.at;
        const up = g.pic.glide[hero].lift() * 2 > @as(i32, game.HOP_PX);
        if (up and !high) hops += 1;
        high = up;
        for (g.pic.glide[0..g.sim.pool.n], 0..) |gl, i| peaks[i] = @max(peaks[i], gl.lift());
        if (g.pic.glide[hero].now().y != ground[0] or g.cam.y != ground[1]) bobbed = true;
    }
    for (0..60) |_| {
        harness.walkFrame(g, dt, null);
    }
    std.debug.print("hop: {d} steps, {d} hops, the archer peaks {d} px and the rat {d} px\n", .{ steps, hops, peaks[hero], peaks[actor.Pool.slot(2)] });
    try std.testing.expect(steps > 5);
    try std.testing.expectEqual(steps, hops);
    try std.testing.expectEqual(@as(i32, game.HOP_PX), peaks[hero]);
    try std.testing.expectEqual(@as(i32, game.HOP_PX), peaks[actor.Pool.slot(2)]);
    for (g.pic.glide[0..g.sim.pool.n]) |gl| try std.testing.expectEqual(@as(i32, 0), gl.lift());
    try std.testing.expect(!bobbed);
}

test "a foe stepping into the cell of a body still dying there sets off once that body is no longer drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 25, .y = 20 } });
    const cell = P{ .x = 24, .y = 20 };
    const dying = actor.Pool.slot(2);
    const mover = actor.Pool.slot(3);
    _ = g.sim.pool.damage(&g.sim.lv, 2, g.sim.pool.get(2).?.hp);
    const lands: f32 = 0.3;
    g.pic.strike(&g.sim, g.cloud, dying, .{ .from = .{ .x = 20, .y = 20 }, .wait = lands }, cell, true, g.pic.afterOf(&g.sim, dying));
    g.sim.pool.move(&g.sim.lv, 3, cell);
    harness.staggerOnly(g, 3);
    var overlap: f32 = 0;
    var t: f32 = 0;
    while (t < 1) : (t += harness.TEST_DT) {
        if (g.pic.standing(&g.sim, dying) and g.pic.glide[mover].done() > 0) overlap += harness.TEST_DT;
        game.update(g, harness.TEST_DT);
    }
    std.debug.print("a rat dying {d:.2} s out holds the next into its cell: {d:.3} s drawn together\n", .{ lands, overlap });
    try std.testing.expect(overlap <= harness.TEST_TOL);
    try std.testing.expect(g.pic.glide[mover].done() >= 1);
}

test "a step taken mid-hop hops on from the height the body was at" {
    var gl = glide.Glide.still(.{ .x = 5, .y = 5 }, .hop);
    gl = gl.toward(.{ .x = 6, .y = 5 }, 0);
    var worst: f32 = 0;
    var t: f32 = 0;
    const dt = harness.TEST_DT;
    while (t < game.GLIDE_S * 3) : (t += dt) {
        const before = gl.height();
        gl.t += dt;
        if (@abs(t - game.GLIDE_S * 0.4) < dt * 0.5) gl = gl.toward(.{ .x = 7, .y = 5 }, 0);
        worst = @max(worst, @abs(gl.height() - before));
    }
    std.debug.print("hop cut short by a step: the biggest jump in height between {d} Hz frames {d:.2} px\n", .{ 1 / dt, worst });
    try std.testing.expect(worst < game.HOP_PX * 0.2);
    try std.testing.expectEqual(@as(i32, 0), gl.lift());
}

test "a slime slides without hopping, a little past its cell, and settles exactly on it" {
    var gl = glide.Glide.still(.{ .x = 5, .y = 5 }, look.gait(.slime));
    gl = gl.toward(.{ .x = 6, .y = 5 }, 0);
    const to = glide.cellPx(.{ .x = 6, .y = 5 }).x;
    var past: f32 = 0;
    var peak_at: f32 = 0;
    var t: f32 = 0;
    while (t < gl.span() * 1.5) : (t += harness.TEST_DT) {
        gl.t = t;
        try std.testing.expectEqual(@as(i32, 0), gl.lift());
        if (gl.now().x - to > past) {
            past = gl.now().x - to;
            peak_at = gl.done();
        }
    }
    std.debug.print("slime slide: {d:.1} px past its cell at {d:.0}% of the glide\n", .{ past, peak_at * 100 });
    try std.testing.expectApproxEqAbs(game.CELL_F * 0.05, past, 0.3);
    try std.testing.expectEqual(to, gl.now().x);
}

test "a turn's glides start the archer first, then each foe in sight a stagger behind, and the next walk waits for the last" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 27, .y = 20 }, .{ .x = 24, .y = 23 } });
    _ = harness.spawnAt(g, .slime, .{ .x = 26, .y = 17 }, true);
    harness.wakeFoes(g);
    game.settle(g);
    harness.nudge(g, .e);
    const t = [_]f32{ g.pic.glide[g.sim.heroSlot().?].t, g.pic.glide[actor.Pool.slot(3)].t, g.pic.glide[actor.Pool.slot(4)].t, g.pic.glide[actor.Pool.slot(2)].t };
    std.debug.print("glide starts: archer {d:.3} s, then {d:.3}, {d:.3}, {d:.3}; the turn is busy {d:.3} s\n", .{ -t[0], -t[1], -t[2], -t[3], g.pic.busy });
    try std.testing.expectEqualSlices(u16, &.{ 3, 4, 2 }, g.sim.order[0..g.sim.order_n]);
    for (t, 0..) |v, i| try std.testing.expectApproxEqAbs(-game.STAGGER_S * @as(f32, @floatFromInt(i)), v, 1e-6);
    try std.testing.expectApproxEqAbs(game.STAGGER_S * 2 + game.SLIDE_S, g.pic.busy, 1e-6);
    const at = g.sim.heroActor().?.at;
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    g.st = .{};
    var waited: f32 = 0;
    while (g.sim.heroActor().?.at.eq(at) and waited < 1) : (waited += harness.TEST_DT) game.update(g, harness.TEST_DT);
    std.debug.print("a walk pressed mid-turn steps {d:.3} s later\n", .{waited});
    try std.testing.expect(!g.sim.heroActor().?.at.eq(at));
    try std.testing.expectApproxEqAbs(game.STAGGER_S * 2 + game.SLIDE_S, waited, harness.TEST_TOL);
}

test "an arrow's rat flashes when the arrow gets there, not when the hit resolves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    harness.confirmUse(g, .shoot);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.sim.pool.get(2).?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.flashOf(rat));
    const t = harness.framesUntil(g, rat, harness.flashing);
    std.debug.print("arrow 5 cells out: the rat flashes {d:.3} s after the shot, the arrow reaches it at {d:.3} s\n", .{ t, game.presentation.flown(4) });
    try std.testing.expectApproxEqAbs(game.presentation.flown(4), t, harness.TEST_TOL);
}

test "after an arrow the foes act a stagger after it lands, so the rat it strikes is still under it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    harness.wakeFoes(g);
    harness.confirmUse(g, .shoot);
    const lands = game.presentation.flown(6);
    const starts = -g.pic.glide[actor.Pool.slot(2)].t;
    std.debug.print("an arrow 7 cells out lands {d:.3} s in, and the rat it struck steps at {d:.3} s\n", .{ lands, starts });
    try std.testing.expect(g.sim.pool.get(2).?.hurt());
    try std.testing.expectEqual(@as(i32, 26), g.sim.pool.get(2).?.at.x);
    try std.testing.expectApproxEqAbs(lands + game.STAGGER_S, starts, 1e-6);
}

test "a body the arrow kills stands until the arrow reaches it and its flash is gone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 20 + bow.RANGE, .y = 20 }});
    g.sim.pool.get(2).?.hp = 1;
    harness.confirmUse(g, .shoot);
    const rat = actor.Pool.slot(2);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(2));
    try std.testing.expect(g.pic.drawnAt(&g.sim, rat) != null);
    const t = harness.framesUntil(g, rat, harness.gone);
    const lands = game.presentation.flown(bow.RANGE - 1);
    std.debug.print("a rat an arrow kills {d} cells out is drawn {d:.3} s on; the arrow lands at {d:.3} s\n", .{ bow.RANGE, t, lands });
    try std.testing.expectApproxEqAbs(lands + fx.FLASH_S, t, harness.TEST_TOL);
}

test "a long frame finishes a killing flash before the next turn is ready" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.sim.pool.get(2).?.hp = 1;
    harness.confirmUse(g, .shoot);
    g.st = .{};
    game.update(g, g.pic.busy + 0.01);
    try std.testing.expect(g.pic.quiet());
    try std.testing.expect(g.pic.drawnAt(&g.sim, actor.Pool.slot(2)) == null);
    std.debug.print("long frame: killing flash finished when play becomes ready\n", .{});
}

test "the bite that kills the archer leaves it standing and followed until it lands, and the veil waits for the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.bittenToDeath(g);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    const hero = g.sim.heroSlot().?;
    try std.testing.expect(g.pic.drawnAt(&g.sim, hero) != null and g.pic.carrierAt(&g.sim) != null);
    const t = harness.framesUntil(g, hero, harness.gone);
    std.debug.print("a killing bite a stagger in: the archer stands {d:.3} s, the turn is over at {d:.3} s\n", .{ t, t + g.pic.busy });
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS + fx.FLASH_S, t, harness.TEST_TOL);
    try std.testing.expect(g.pic.carrierAt(&g.sim) == null and g.pic.busy <= 0);
}

test "a foe whose bite kills the archer is not then killed by the gas it stands in" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    g.sim.pool.get(2).?.hp = 1;
    g.sim.heroActor().?.hp = 1;
    g.sim.lv.addGas(.{ .x = 21, .y = 20 }, harness.TEST_GAS);
    harness.use(g, .wait);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    try std.testing.expect(g.sim.pool.get(2) != null);
    try std.testing.expectEqual(@as(usize, 0), g.sim.kills);
    try std.testing.expectEqualStrings("Archer dies.", g.sim.log.line(0).?);
}

test "a bite lands on the archer at the height of the biter's bump, from its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    harness.wakeFoes(g);
    harness.nudge(g, .e);
    const hero = g.sim.heroSlot().?;
    try std.testing.expect(g.sim.heroActor().?.hurt());
    const t = harness.framesUntil(g, hero, harness.flashing);
    std.debug.print("the biting rat is first in the turn: it sets off {d:.3} s in, the archer flashes {d:.3} s in\n", .{ game.STAGGER_S, t });
    try std.testing.expectEqualSlices(u16, &.{ 3, 2 }, g.sim.order[0..g.sim.order_n]);
    const bump = g.pic.glide[actor.Pool.slot(3)].bump orelse return error.NoBump;
    try std.testing.expect(bump.x < 0 and bump.y == 0);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t, harness.TEST_TOL);
}

test "a kick bumps the rat and lands at the bump's height, and the rat bites back a stagger after" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    const cam = g.cam;
    g.sim.rng = harness.meleeThenBites(g, 1);
    harness.nudge(g, .e);
    const hero = g.sim.heroSlot().?;
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.sim.pool.get(2).?.hurt() and g.sim.heroActor().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.flashOf(rat));
    g.st = .{};
    var bumped: f32 = 0;
    var bumped_at: f32 = 0;
    var rat_hit: ?f32 = null;
    var t: f32 = 0;
    while (t < game.BUMP_S) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        const off = g.pic.glide[hero].now().x - glide.cellPx(at).x;
        if (off > bumped) {
            bumped = off;
            bumped_at = t + harness.TEST_DT;
        }
        if (rat_hit == null and harness.flashing(g, rat)) rat_hit = t + harness.TEST_DT;
        try std.testing.expectEqual(glide.cellPx(at), g.pic.glide[hero].ground());
    }
    try std.testing.expect(harness.samePx(g.pic.glide[hero].now(), glide.cellPx(at)));
    const bitten = t + harness.framesUntil(g, hero, harness.flashing);
    std.debug.print("a kick: the archer bumps {d:.1} px toward the rat at {d:.3} s, the rat flashes at {d:.3} s and bites back at {d:.3} s, the camera {d:.1} px off\n", .{ bumped, bumped_at, rat_hit.?, bitten, @abs(g.cam.x - cam.x) });
    try std.testing.expectApproxEqAbs(game.BUMP_PX, bumped, 0.5);
    try std.testing.expectApproxEqAbs(game.BUMP_LANDS, bumped_at, harness.TEST_TOL);
    try std.testing.expectApproxEqAbs(game.BUMP_LANDS, rat_hit.?, harness.TEST_TOL);
    try std.testing.expectApproxEqAbs(game.BUMP_LANDS + game.STAGGER_S + game.BUMP_LANDS, bitten, harness.TEST_TOL);
    try std.testing.expectEqual(cam, g.cam);
}

test "the lean shows a kick on the rat a kick killed until it falls" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{.{ .x = 21, .y = 20 }});
    g.sim.pool.get(2).?.hp = 1;
    harness.nudge(g, .e);
    try std.testing.expect(g.sim.pool.get(2) == null);
    try std.testing.expectEqual(game.Move.kick, scene.leanShown(g, &scene.stoodNow(g), at, .e));
    harness.drawnOut(g);
    try std.testing.expectEqual(game.Move.step, scene.leanShown(g, &scene.stoodNow(g), at, .e));
}

test "a kick dealt in a frame of play is no further into its bump than its blow is to landing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.calm(g);
    g.st = .{ .walk = .e };
    game.update(g, mathx.FRAME_DT);
    const t = g.pic.glide[g.sim.heroSlot().?].t;
    std.debug.print("a kick dealt in a 60 fps frame: {d:.4} s into its bump as the frame ends\n", .{t});
    try std.testing.expectEqual(@as(f32, 0), t);
}

test "only the bite that kills the archer lands as a killing blow" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var deaths: usize = 0;
    var hurts: usize = 0;
    for (0..40) |i| {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 }, .{ .x = 20, .y = 21 } });
        g.sim.rng = mathx.Rng.init(i);
        harness.wakeFoes(g);
        g.sim.heroActor().?.hp = actor.row(.rat).blow.strike.hit.hi + 1;
        combat.endTurn(g);
        var kills: usize = 0;
        for (g.pic.owed) |o| {
            if ((o.bit orelse continue) == .kill) kills += 1;
        }
        try std.testing.expectEqual(@as(usize, if (g.mode == .dead) 1 else 0), kills);
        if (g.mode != .dead) continue;
        deaths += 1;
        for (g.pic.owed) |o| {
            if ((o.bit orelse continue) == .hurt) hurts += 1;
        }
    }
    std.debug.print("three rats on a {d} hp archer: {d} of 40 turns kill, with {d} bites before the killing ones that only hurt\n", .{ actor.row(.rat).blow.strike.hit.hi + 1, deaths, hurts });
    try std.testing.expect(deaths > 0 and hurts >= deaths);
}

test "a body at rest lands on its tile's pixel whatever fraction the camera is at" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const p = P{ .x = 17, .y = 9 };
    var f: f32 = -3;
    while (f < 3) : (f += 0.125) {
        g.cam = .{ .x = 500 + f, .y = 300 - f };
        const c = scene.Cam.of(g);
        try std.testing.expectEqual(c.corner(p), c.px(glide.cellPx(p)));
    }
}

test "hidden and offscreen objects keep casting without being drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const p = P{ .x = 27, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{p});
    const i = actor.Pool.slot(2);
    const view = grid.Box{ .lo = .{ .x = 15, .y = 15 }, .hi = .{ .x = 27, .y = 25 } };
    const cast = view.grown(game.CAST_MARGIN);
    g.sim.lv.lit[grid.Level.idx(p)] = false;
    g.sim.lv.seen[grid.Level.idx(p)] = false;
    try std.testing.expect(g.pic.drawnAt(&g.sim, i) == null);
    try std.testing.expect(g.pic.casterAt(&g.sim, i, view) == null);
    try std.testing.expectEqual(g.pic.glide[i].now(), g.pic.casterAt(&g.sim, i, cast).?);
    g.pic.split_from[i] = g.sim.heroSlot().?;
    try std.testing.expect(g.pic.casterAt(&g.sim, i, cast) == null);
    g.pic.split_from[i] = null;
    g.sim.pool.items[i].alive = false;
    try std.testing.expect(g.pic.casterAt(&g.sim, i, cast) == null);
    g.sim.lv.putBarrel(p);
    try std.testing.expect(!scene.barrelShownAt(g, p));
    try std.testing.expect(scene.barrelPresent(g, p));
    std.debug.print("hidden actor and barrel still cast within {d} cells of the view; dead actors and unborn splits do not\n", .{game.CAST_MARGIN});
}

test "the minimap and the day beneath it fit in the top right, clear of the hud" {
    for ([_]P{ game.SCREEN_720, game.WINDOW, game.SCREEN_1080, game.SCREEN_1440 }) |screen| {
        const o = scene.miniOrigin(screen.x);
        try std.testing.expect(o.x > @divTrunc(screen.x, 2));
        try std.testing.expect(scene.dayLine(screen.x).y + @as(i32, @intFromFloat(@ceil(scene.DAY_GLYPH_R))) + scene.DAY_DROP < hud.Layout.of(screen, game.SKILLS_W).top);
    }
}

test "a foe the gas kills out of sight leaves nothing drawn and nothing said" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 40, .y = 20 }});
    g.sim.lv.addGas(.{ .x = 40, .y = 20 }, harness.TEST_GAS);
    g.sim.pool.get(2).?.hp = 1;
    const said = g.sim.log.n;
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(2));
    try std.testing.expectEqual(@as(usize, 1), g.sim.kills);
    try std.testing.expectEqual(@as(usize, 0), g.pic.fx.due_n);
    for (g.pic.fx.motes) |m| try std.testing.expect(m.life <= 0);
    try std.testing.expectEqualStrings("The last rat is dead.", g.sim.log.line(0).?);
    try std.testing.expect(std.mem.endsWith(u8, g.sim.log.line(1).?, "experience."));
    try std.testing.expectEqual(said + 2, g.sim.log.n);
}

test "a foe the gas kills after it steps keeps its place in the turn, and its death lands as it arrives" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    const was = g.sim.pool.get(2).?.at;
    harness.wakeFoes(g);
    g.sim.pool.get(2).?.hp = 1;
    g.sim.lv.addGas(was, harness.TEST_GAS);
    harness.nudge(g, .w);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(2));
    try std.testing.expect(!g.sim.pool.items[actor.Pool.slot(2)].at.eq(was));
    const t = harness.framesUntil(g, actor.Pool.slot(2), harness.flashing);
    std.debug.print("a rat that steps and dies in the gas: its death lands {d:.3} s into the turn, its hop ends at {d:.3} s\n", .{ t, game.STAGGER_S + game.GLIDE_S });
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.GLIDE_S, t, harness.TEST_TOL);
}

test "an arrow that bursts a bloat eats at a sleeping foe with its gas as it lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const bloat = harness.spawnAt(g, .bloat, .{ .x = 27, .y = 20 }, false);
    const rat = harness.spawnAt(g, .rat, .{ .x = 28, .y = 21 }, false);
    g.sim.pool.get(bloat).?.hp = 1;
    harness.confirmUse(g, .shoot);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(bloat));
    try std.testing.expect(g.sim.pool.get(rat).?.hurt());
    const lands = game.presentation.flown(6);
    const t = harness.framesUntil(g, actor.Pool.slot(rat), harness.flashing);
    std.debug.print("a bloat shot 7 cells out: the arrow lands {d:.3} s in, and its gas stings the rat beside it {d:.3} s in\n", .{ lands, t });
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
}

test "a bloat's cloud is drawn from when its burst lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const Burst = struct {
        const at = P{ .x = 27, .y = 20 };
        fn clouded(gm: *game.Game, _: usize) bool {
            return gm.cloud.tint[grid.Level.idx(at)] > 0;
        }
    };
    const bloat = harness.spawnAt(g, .bloat, Burst.at, false);
    g.sim.pool.get(bloat).?.hp = 1;
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.sim.lv.gasAt(Burst.at) > 0 and !Burst.clouded(g, 0));
    const t = harness.framesUntil(g, 0, Burst.clouded);
    std.debug.print("a bloat shot 7 cells out: the arrow lands {d:.3} s in, its cloud first drawn {d:.3} s in\n", .{ game.presentation.flown(6), t });
    try std.testing.expectApproxEqAbs(game.presentation.flown(6), t, harness.TEST_TOL);
}

test "a foe stepping out of sight takes its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = actor.Pool.slot(2);
    const dark = ledge(g);
    game.castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.sim.lv.isLit(dark));
    g.sim.pool.move(&g.sim.lv, 2, dark);
    harness.staggerOnly(g, 2);
    std.debug.print("a rat stepping out of sight a stagger after a kick sets off {d:.3} s in\n", .{-g.pic.glide[rat].t});
    try std.testing.expectApproxEqAbs(game.STAGGER_S, -g.pic.glide[rat].t, 1e-6);
}

test "a barrel the arrow breaks stands until the arrow reaches it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const Gone = struct {
        const at = P{ .x = 20 + bow.RANGE, .y = 20 };
        fn f(gm: *game.Game, _: usize) bool {
            return !scene.barrelShownAt(gm, at);
        }
    };
    g.sim.lv.putBarrel(Gone.at);
    harness.confirmUse(g, .shoot);
    try std.testing.expect(!g.sim.lv.hasBarrel(Gone.at) and !Gone.f(g, 0));
    try std.testing.expect(game.mapAssets(g).barrel);
    const t = harness.framesUntil(g, 0, Gone.f);
    try std.testing.expect(!game.mapAssets(g).barrel);
    const lands = game.presentation.flown(bow.RANGE - 1);
    std.debug.print("a barrel shot {d} cells out breaks {d:.3} s on; the arrow lands at {d:.3} s\n", .{ bow.RANGE, t, lands });
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
}

test "a foe's hp as drawn, the archer's and the low glow drop as the blow lands, not as it resolves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 27, .y = 20 }});
    const rat = actor.Pool.slot(2);
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.sim.pool.get(2).?.hurt());
    try std.testing.expectEqual(actor.row(.rat).hp, g.pic.pictured[rat].hp);
    const Drop = struct {
        fn f(gm: *game.Game, i: usize) bool {
            return gm.pic.pictured[i].hp < actor.row(.rat).hp;
        }
    };
    const t = harness.framesUntil(g, rat, Drop.f);
    std.debug.print("an arrow 7 cells out: the rat's bar drops {d:.3} s in, as it lands at {d:.3} s\n", .{ t, game.presentation.flown(6) });
    try std.testing.expectApproxEqAbs(game.presentation.flown(6), t, harness.TEST_TOL);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    harness.wakeFoes(g);
    const low: i32 = @intFromFloat(vignette.LOW * @as(f32, @floatFromInt(actor.row(HERO).hp)));
    g.sim.heroActor().?.hp = low;
    g.pic.catchUp(&g.sim);
    g.sim.rng = harness.bitesRng(g, .rat, &.{true});
    harness.nudge(g, .e);
    const hero = g.sim.heroSlot().?;
    try std.testing.expect(g.sim.heroActor().?.hp < low);
    try std.testing.expectEqual(low, g.pic.pictured[hero].hp);
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const r = harness.framesUntil(g, hero, harness.reddened);
    std.debug.print("a bite on an archer at a third of its hp: the view reddens {d:.3} s in, as it lands at {d:.3} s\n", .{ r, game.STAGGER_S + game.BUMP_LANDS });
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, r, harness.TEST_TOL);
}

test "an arrow that splits a slime shows it as the arrow lands, the new half sliding out of it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 27, .y = 20 };
    const id = harness.splittable(g, at, false);
    g.pic.catchUp(&g.sim);
    harness.confirmUse(g, .shoot);
    const slime = actor.Pool.slot(id);
    const other = slime + 1;
    try std.testing.expectEqual(actor.Kind.slime_half, g.sim.pool.get(id).?.kind);
    try std.testing.expectEqual(actor.Kind.slime_half, g.sim.pool.items[other].kind);
    try std.testing.expectEqual(actor.Kind.slime, g.pic.pictured[slime].kind);
    try std.testing.expect(game.mapAssets(g).bodies.contains(.slime));
    try std.testing.expect(g.pic.drawnAt(&g.sim, other) == null);
    try std.testing.expectEqual(fx.Body.of(g.sim.pool.items[other], g.pic.pictured[other].seq), g.pic.pictured[other]);
    try std.testing.expectEqualStrings("The slime splits in two!", g.sim.log.line(0).?);
    const t = harness.framesUntil(g, other, harness.drawn);
    const lands = game.presentation.flown(6);
    try std.testing.expectEqual(actor.Kind.slime_half, g.pic.pictured[slime].kind);
    try std.testing.expect(!game.mapAssets(g).bodies.contains(.slime));
    try std.testing.expect(game.mapAssets(g).bodies.contains(.slime_quarter));
    try std.testing.expect(harness.samePx(g.pic.glide[other].now(), glide.cellPx(at)));
    try std.testing.expect(g.pic.busy >= game.SLIDE_S);
    const slid = harness.framesUntil(g, other, struct {
        fn f(gm: *game.Game, i: usize) bool {
            return gm.pic.glide[i].done() >= 1;
        }
    }.f);
    std.debug.print("an arrow 7 cells out splits a slime: the new half shows {d:.3} s in, as it lands at {d:.3} s, and slides out over {d:.3} s\n", .{ t, lands, slid });
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
    try std.testing.expectApproxEqAbs(game.SLIDE_S, slid, harness.TEST_TOL);
    try std.testing.expect(harness.samePx(g.pic.glide[other].now(), glide.cellPx(g.sim.pool.items[other].at)));
    try std.testing.expectEqual(actor.Tally{ .left = 2, .total = 2 }, g.sim.pool.tally(.slime));
}

test "each bite on the archer drops its hp as drawn as that bite lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 } });
    harness.wakeFoes(g);
    harness.use(g, .wait);
    const hero = g.sim.heroSlot().?;
    const full = actor.row(HERO).hp;
    const hp = g.sim.heroActor().?.hp;
    try std.testing.expectEqual(full, g.pic.pictured[hero].hp);
    const One = struct {
        fn f(gm: *game.Game, i: usize) bool {
            return gm.pic.pictured[i].hp < actor.row(HERO).hp;
        }
    };
    const t1 = harness.framesUntil(g, hero, One.f);
    const first = g.pic.pictured[hero].hp;
    try std.testing.expect(first > hp);
    const t2 = t1 + harness.framesUntil(g, hero, harness.caughtUp);
    std.debug.print("two rats bite an archer of {d} hp: drawn on {d} as the first lands {d:.3} s in, on {d} as the second lands {d:.3} s in\n", .{ full, first, t1, hp, t2 });
    try std.testing.expectApproxEqAbs(game.BUMP_LANDS, t1, harness.TEST_TOL);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t2, harness.TEST_TOL);
}

test "a slime an arrow splits shows split as the arrow lands, though the gas eats at it later in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = harness.splittable(g, at, true);
    for ([_]P{ at, .{ .x = 24, .y = 20 } }) |p| g.sim.lv.addGas(p, harness.TEST_GAS);
    g.pic.catchUp(&g.sim);
    harness.confirmUse(g, .shoot);
    const slime = actor.Pool.slot(id);
    const other = slime + 1;
    try std.testing.expect(!g.sim.pool.items[slime].at.eq(at));
    const t = harness.framesUntil(g, other, harness.drawn);
    const lands = game.presentation.flown(4);
    std.debug.print("an arrow 5 cells out splits a slime in gas: the new half shows {d:.3} s in, as the arrow lands at {d:.3} s, the gas still to land on the slime\n", .{ t, lands });
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
    try std.testing.expect(g.pic.fx.pending(slime));
    try std.testing.expectEqual(actor.Kind.slime_half, g.pic.pictured[slime].kind);
}

test "a half the gas splits off a burning slime on the foes' turn burns no sooner than it shows" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = harness.splittable(g, at, true);
    const a = g.sim.pool.get(id).?;
    a.burn = .{ .turns = 2 };
    for ([_]P{ at, .{ .x = 24, .y = 20 } }) |p| g.sim.lv.addGas(p, harness.TEST_GAS);
    g.pic.catchUp(&g.sim);
    harness.use(g, .wait);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(g.pic.split_from[half] != null and g.pic.fx.pending(half));
    const when = showsAndLands(g, half);
    std.debug.print("a half the gas splits off a burning slime on the foes' turn: shows {d:.3} s in, its burn lands {d:.3} s in\n", .{ when.shows, when.lands });
    try std.testing.expect(when.lands >= when.shows);
}

test "a half an arrow splits off into gas takes the gas on its waiting turn, no sooner than it shows" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = harness.splittable(g, at, true);
    var cells = grid.Cells.around(at, 2);
    while (cells.next()) |p| g.sim.lv.addGas(p, harness.TEST_GAS);
    g.pic.catchUp(&g.sim);
    harness.confirmUse(g, .shoot);
    const half = actor.Pool.slot(id) + 1;
    try std.testing.expect(g.pic.split_from[half] != null);
    const when = showsAndLands(g, half);
    const b = g.sim.pool.items[half];
    std.debug.print("a half split off into gas: shows {d:.3} s in, stung {d:.3} s in, {s} on {d} of {d} hp\n", .{ when.shows, when.lands, actor.row(b.kind).name, b.hp, b.max });
    try std.testing.expect(b.kind != .slime_half or b.hp < b.max);
    try std.testing.expect(when.lands >= when.shows);
}

test "a barrel broken in sight but in the dark stays remembered until light shows it gone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const p = P{ .x = 28, .y = 20 };
    g.sim.lv.putBarrel(p);
    game.settle(g);
    try std.testing.expect(scene.barrelShownAt(g, p));
    g.sim.clock = day.Clock.at(day.DEAD_OF_NIGHT);
    try std.testing.expect(g.sim.lv.breakBarrel(p));
    game.castSight(g, g.sim.heroActor().?.at);
    try std.testing.expect(g.sim.lv.inLos(p) and !g.sim.lv.isLit(p));
    try std.testing.expect(scene.barrelShownAt(g, p));
    g.sim.clock = day.Clock.at(day.NOON);
    game.castSight(g, g.sim.heroActor().?.at);
    try std.testing.expect(!scene.barrelShownAt(g, p));
}

test "a barrel broken out of sight stays remembered, with no blow drawn, until it is seen gone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const p = P{ .x = 23, .y = 20 };
    g.sim.lv.putBarrel(p);
    game.settle(g);
    try std.testing.expect(scene.barrelShownAt(g, p));
    try std.testing.expect(g.sim.lv.breakBarrel(p));
    g.sim.lv.lit[grid.Level.idx(p)] = false;
    g.pic.strike(&g.sim, g.cloud, null, .{ .from = .{ .x = 24, .y = 20 }, .wait = 0.2 }, p, true, null);
    try std.testing.expect(!g.pic.fx.breaking(p));
    try std.testing.expect(scene.barrelShownAt(g, p));
    game.castSight(g, g.sim.heroActor().?.at);
    try std.testing.expect(!scene.barrelShownAt(g, p));
}

test "a half a beefy pib's sweep splits off into gas takes the gas no sooner than it shows" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.sim.unkillable = true;
    const at = P{ .x = 20, .y = 21 };
    const id = harness.splittable(g, at, false);
    _ = harness.spawnAt(g, .beefy_pib, .{ .x = 21, .y = 20 }, true);
    for ([_]P{ .{ .x = 19, .y = 20 }, .{ .x = 19, .y = 21 }, .{ .x = 19, .y = 22 }, .{ .x = 21, .y = 21 }, .{ .x = 21, .y = 22 } }) |p| g.sim.lv.set(p, .wall);
    g.sim.lv.addGas(.{ .x = 20, .y = 23 }, harness.TEST_GAS);
    game.settle(g);
    harness.use(g, .wait);
    const half = g.sim.pool.n - 1;
    try std.testing.expectEqual(@as(?usize, actor.Pool.slot(id)), g.pic.split_from[half]);
    try std.testing.expect(g.sim.lv.gassy(g.sim.pool.items[half].at) and !g.sim.lv.gassy(at));
    const when = showsAndLands(g, half);
    std.debug.print("a half a sweep splits off into gas: shows {d:.3} s in, stung {d:.3} s in\n", .{ when.shows, when.lands });
    try std.testing.expect(when.lands >= when.shows);
}

test "a half the gas splits off an unlit slime into sight shows as the archer's step lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const l = gassedOffLedge(g);
    const half = l.half;
    try std.testing.expect(!g.sim.lv.isLit(l.dark) and g.sim.lv.isLit(g.sim.pool.items[half].at));
    const step = g.pic.glide[g.sim.heroSlot().?].left();
    g.pic.catchUp(&g.sim);
    const t = harness.framesUntil(g, half, revealed);
    std.debug.print("a half split off an unlit slime by the gas: revealed {d:.3} s in, the archer's step lands at {d:.3} s\n", .{ t, step });
    try std.testing.expect(step > 0);
    try std.testing.expectApproxEqAbs(step, t, harness.TEST_TOL);
}

test "a half revealed as the turn's picture ends shows before a held walk starts the next turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const half = gassedOffLedge(g).half;
    g.pic.catchUp(&g.sim);
    const from = g.sim.heroActor().?.at;
    var shown: ?usize = null;
    var n: usize = 0;
    while (n < 400) : (n += 1) {
        g.st = .{ .walk = .w };
        game.update(g, harness.TEST_DT);
        if (shown == null and revealed(g, half)) shown = n;
        if (!g.sim.heroActor().?.at.eq(from)) break;
    }
    std.debug.print("held walk past a reveal: half shown at frame {?d}, next step at frame {d}\n", .{ shown, n });
    try std.testing.expect(shown != null and n > shown.?);
}

test "a half revealed as the turn's picture ends holds the turn's log lines until it has slid out" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const half = gassedOffLedge(g).half;
    g.pic.catchUp(&g.sim);
    g.sim.log.say("held", .{});
    var shown: ?usize = null;
    var released: ?usize = null;
    var n: usize = 0;
    while (n < 400 and released == null) : (n += 1) {
        game.update(g, harness.TEST_DT);
        if (shown == null and revealed(g, half)) shown = n;
        if (g.sim.log.held == 0) released = n;
    }
    std.debug.print("log past a reveal: half shown at frame {?d}, lines released at frame {?d}\n", .{ shown, released });
    try std.testing.expect(shown != null and released != null and released.? > shown.?);
}

test "a quarter the gas splits off a burning half on its waiting turn burns that turn as its sibling does" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 25, .y = 20 };
    const id = harness.spawnAt(g, .slime_half, at, true);
    const a = g.sim.pool.get(id).?;
    a.hp = actor.row(.slime_quarter).hp;
    a.burn = .{ .turns = burning.TURNS };
    a.resists.set(.fire, 50);
    a.waits = true;
    g.sim.lv.addGas(at, harness.TEST_GAS);
    g.pic.catchUp(&g.sim);
    harness.use(g, .wait);
    const s = actor.Pool.slot(id);
    const q = s + 1;
    try std.testing.expectEqual(actor.Kind.slime_quarter, g.sim.pool.items[q].kind);
    std.debug.print("a burning half split by the gas on its waiting turn: burn turns left {d} and {d}\n", .{ g.sim.pool.items[s].burn.turns, g.sim.pool.items[q].burn.turns });
    try std.testing.expectEqual(g.sim.pool.items[s].burn.turns, g.sim.pool.items[q].burn.turns);
}

test "a split nobody sees holds no one's walk" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const at = P{ .x = 40, .y = 20 };
    const id = harness.splittable(g, at, false);
    g.sim.lv.addGas(at, harness.TEST_GAS);
    g.pic.catchUp(&g.sim);
    harness.use(g, .wait);
    try std.testing.expectEqual(actor.Kind.slime_half, g.sim.pool.get(id).?.kind);
    try std.testing.expectEqual(@as(?usize, null), g.pic.split_from[actor.Pool.slot(id) + 1]);
    try std.testing.expect(g.pic.busy <= 0);
}

test "a foe the gas kills as it steps out of sight is drawn stepping out, not gone from where it stood" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = actor.Pool.slot(2);
    const dark = ledge(g);
    game.castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.sim.lv.isLit(dark));
    g.sim.pool.move(&g.sim.lv, 2, dark);
    _ = g.sim.pool.damage(&g.sim.lv, 2, actor.row(.rat).hp);
    g.pic.owed[rat].gassed = .{ .kill = true, .after = .{ .body = fx.Body.of(g.sim.pool.items[rat], 0) } };
    harness.staggerOnly(g, 2);
    g.pic.catchUp(&g.sim);
    try std.testing.expect(g.pic.drawnAt(&g.sim, rat) != null);
    const alive_shown = g.pic.pictured[rat].hp;
    const t = harness.framesUntil(g, rat, harness.gone);
    std.debug.print("a rat the gas kills stepping out of sight a stagger in: drawn until {d:.3} s on {d} hp, its hop {d:.3} to {d:.3} s\n", .{ t, alive_shown, game.STAGGER_S, game.STAGGER_S + game.GLIDE_S });
    try std.testing.expect(alive_shown > 0);
    try std.testing.expect(t > game.STAGGER_S and t < game.STAGGER_S + game.GLIDE_S);
}

test "a foe the gas kills stepping from dark to dark has its death landed by the time the turn is quiet" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const dark = ledge(g);
    const was = P{ .x = dark.x + 1, .y = dark.y };
    const id = harness.spawnAt(g, .slime, was, true);
    const s = actor.Pool.slot(id);
    game.castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.sim.lv.isLit(dark) and !g.sim.lv.isLit(was));
    g.sim.pool.move(&g.sim.lv, id, dark);
    _ = g.sim.pool.damage(&g.sim.lv, id, g.sim.pool.items[s].hp);
    g.pic.owed[s].gassed = .{ .kill = true, .after = .{ .body = fx.Body.of(g.sim.pool.items[s], 0) } };
    harness.staggerOnly(g, id);
    g.pic.catchUp(&g.sim);
    var t: f32 = 0;
    while (!g.pic.quiet() and t < 1) : (t += harness.TEST_DT) game.update(g, harness.TEST_DT);
    game.update(g, harness.TEST_DT);
    std.debug.print("a slime the gas kills sliding dark to dark: quiet {d:.3} s in, its death still due: {}\n", .{ t, g.pic.fx.pending(s) });
    try std.testing.expect(!g.pic.fx.pending(s));
}

test "a foe with no place in the turn is stung as the archer's step lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 28, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
    g.sim.lv.addGas(at, harness.TEST_GAS);
    harness.nudge(g, .w);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.sim.pool.get(2).?.hurt() and g.sim.pool.get(2).?.at.eq(at));
    const t = harness.framesUntil(g, rat, harness.flashing);
    std.debug.print("a still rat in gas as the archer steps: stung {d:.3} s in, the step lands at {d:.3} s\n", .{ t, game.GLIDE_S });
    try std.testing.expectApproxEqAbs(game.GLIDE_S, t, harness.TEST_TOL);
}

test "a foe is drawn turning at its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    harness.wakeFoes(g);
    harness.use(g, .wait);
    const far = actor.Pool.slot(3);
    try std.testing.expectEqual(actor.Facing.right, g.pic.facing[far]);
    const t = harness.framesUntil(g, far, harness.facesLeft);
    std.debug.print("the second rat in the turn is drawn turning {d:.3} s in\n", .{t});
    try std.testing.expectApproxEqAbs(game.STAGGER_S, t, harness.TEST_TOL);
}

test "a kick due late in a frame puts the foes a stagger after it lands, late once" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 20, .y = 21 } });
    harness.wakeFoes(g);
    const late: f32 = 0.05;
    harness.calm(g);
    g.pic.busy = -1;
    g.st = .{ .walk = .e };
    g.st.step.late = late;
    g.sim.rng = harness.meleeThenBites(g, 2);
    game.update(g, 0);
    const t = harness.framesUntil(g, g.sim.heroSlot().?, harness.reddened);
    std.debug.print("a kick due {d:.3} s late: the first bite lands {d:.3} s on\n", .{ late, t });
    try std.testing.expectApproxEqAbs(2 * game.BUMP_LANDS + game.STAGGER_S - late, t, harness.TEST_TOL);
}

test "a flask pressed mid-walk is drunk once the step is drawn, ahead of the held walk" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    g.sim.heroActor().?.hp -= 5;
    const by = harness.boundTo(g, .life_flask);
    g.pic.busy = game.GLIDE_S;
    g.st = .{ .walk = .e, .pressed = .initOne(by.by), .down = .initOne(by.by) };
    if (by.set == .secondary) g.st.down.insert(g.bar.modifier.?);
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    const clock = g.sim.clock;
    g.st = .{ .walk = .e };
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expect(g.pending == null);
    try std.testing.expectEqual(flask.CHARGES / flask.USE - 1, g.sim.flasks.get(.life).uses());
    try std.testing.expectEqual(clock, g.sim.clock);
    try std.testing.expect(g.sim.heroActor().?.at.eq(at));
    std.debug.print("flask queued behind a held walk: drunk on the first quiet frame, hero still at {d},{d}\n", .{ at.x, at.y });
}

test "a fresh walk tap pressed after a queued skill replaces it, the latest press winning" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    g.sim.heroActor().?.hp -= 5;
    const by = harness.boundTo(g, .life_flask);
    g.pic.busy = game.GLIDE_S;
    g.st = .{ .pressed = .initOne(by.by), .down = .initOne(by.by) };
    if (by.set == .secondary) g.st.down.insert(g.bar.modifier.?);
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    g.st = .{ .walk = .e, .step = .{ .latched = .e, .fresh = true } };
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Queued, .{ .walk = .e }), g.pending);
    g.st = .{};
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expect(g.pending == null);
    try std.testing.expectEqual(flask.CHARGES / flask.USE, g.sim.flasks.get(.life).uses());
    try std.testing.expect(g.sim.heroActor().?.at.eq(at.add(mathx.Dir.e.delta())));
    std.debug.print("flask queued, then a fresh tap east: the step taken, the flask not drunk\n", .{});
}

test "losing focus discards a queued walk while the current turn finishes drawing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    g.pic.busy = game.GLIDE_S;
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(@as(?game.Queued, .{ .walk = .e }), g.pending);
    const minute = g.sim.clock.minute;
    g.st = .{ .focused = false };
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expect(g.pic.quiet() and g.pending == null);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    try std.testing.expectEqual(minute, g.sim.clock.minute);
    g.st = .{};
    game.update(g, mathx.FRAME_DT);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    std.debug.print("focus loss: queued walk discarded, presentation finishes, no extra turn on return\n", .{});
}

test "a walk due just before the last turn is drawn out starts as it ends" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const busy: f32 = 0.005;
    const dt: f32 = 0.016;
    const due: f32 = 0.015;
    harness.calm(g);
    g.pic.busy = busy;
    g.st = .{ .walk = .e };
    g.st.step.late = due;
    game.update(g, dt);
    const t = g.pic.glide[g.sim.heroSlot().?].t;
    std.debug.print("a walk due {d:.3} s ago, the turn drawn out {d:.3} s ago: the step is {d:.3} s in\n", .{ due, dt - busy, t });
    try std.testing.expectApproxEqAbs(dt - busy, t, 1e-5);
}

test "a run left mid-turn keeps the way its foes were turning" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    harness.wakeFoes(g);
    harness.use(g, .wait);
    const far = actor.Pool.slot(3);
    try std.testing.expectEqual(actor.Facing.right, g.pic.facing[far]);
    game.leave(g);
    std.debug.print("a rat turning as the run is left faces {s}\n", .{@tagName(g.pic.facing[far])});
    try std.testing.expectEqual(actor.Facing.left, g.pic.facing[far]);
}

test "a foe that notices the archer turns to it once the archer's step is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 24, .y = 20 }});
    harness.nudge(g, .w);
    const rat = actor.Pool.slot(2);
    try std.testing.expect(g.sim.pool.get(2).?.awake);
    const t = harness.framesUntil(g, rat, harness.facesLeft);
    std.debug.print("a rat noticing the archer turns {d:.3} s in, the step lands at {d:.3} s\n", .{ t, game.GLIDE_S });
    try std.testing.expectApproxEqAbs(game.GLIDE_S, t, harness.TEST_TOL);
}

test "a slime split off one not yet drawn waits for it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const p = actor.Pool.slot(harness.spawnAt(g, .slime_half, .{ .x = 25, .y = 20 }, false));
    const c = actor.Pool.slot(harness.spawnAt(g, .slime_half, .{ .x = 26, .y = 20 }, false));
    const d = actor.Pool.slot(harness.spawnAt(g, .slime_quarter, .{ .x = 27, .y = 20 }, false));
    g.pic.split_from[c] = p;
    g.pic.split_from[d] = c;
    const wait: f32 = 0.1;
    g.pic.fx.strike(wait, .{ .slot = p, .at = mathx.centre(g.sim.pool.items[p].at), .dir = null, .matter = .ooze, .lethal = false, .after = .{ .body = fx.Body.of(g.sim.pool.items[p], 1), .reveals = c } });
    g.pic.catchUp(&g.sim);
    try std.testing.expect(g.pic.split_from[c] != null and g.pic.split_from[d] != null);
    const t = harness.framesUntil(g, d, harness.drawn);
    try std.testing.expectApproxEqAbs(wait, t, harness.TEST_TOL);
    try std.testing.expect(g.pic.drawnAt(&g.sim, c) != null);
}

test "the view's edge reddens as a bite lands on the archer, not before, and as the gas eats at it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    harness.wakeFoes(g);
    harness.nudge(g, .e);
    try std.testing.expect(g.sim.heroActor().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const t = harness.framesUntil(g, g.sim.heroSlot().?, harness.reddened);
    std.debug.print("a bite bumped a stagger into the turn reddens the view {d:.3} s in\n", .{t});
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t, harness.TEST_TOL);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.sim.lv.addGas(.{ .x = 20, .y = 20 }, harness.TEST_GAS);
    harness.use(g, .wait);
    try std.testing.expect(g.sim.heroActor().?.hurt());
    try std.testing.expect(harness.framesUntil(g, g.sim.heroSlot().?, harness.reddened) < harness.TEST_TOL);
}

test "gas left to eat at the archer kills it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    g.sim.lv.addGas(.{ .x = 20, .y = 20 }, harness.TEST_GAS);
    g.sim.heroActor().?.hp = 1;
    harness.use(g, .wait);
    try std.testing.expectEqual(game.Mode.dead, g.mode);
    try std.testing.expectEqualStrings("Archer dies.", g.sim.log.line(0).?);
    try std.testing.expect(harness.framesUntil(g, g.sim.heroSlot().?, harness.reddened) < harness.TEST_TOL);
}

test "an unkillable archer keeps 1 hp through gas and bites that would kill it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 21, .y = 20 }, .{ .x = 19, .y = 20 } });
    harness.wakeFoes(g);
    g.sim.unkillable = true;
    g.sim.lv.addGas(.{ .x = 20, .y = 20 }, harness.TEST_GAS);
    g.sim.heroActor().?.hp = 2;
    for (0..20) |_| harness.use(g, .wait);
    std.debug.print("an unkillable archer after 20 turns in gas between two rats: {d} hp\n", .{g.sim.heroActor().?.hp});
    try std.testing.expectEqual(game.Mode.play, g.mode);
    try std.testing.expectEqual(@as(i32, 1), g.sim.heroActor().?.hp);
}

test "a bloat that bursts on the archer takes its place in the turn as a bite does, and its spray lands there" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    var seed: u64 = 0;
    while (seed < 50) : (seed += 1) {
        harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 19, .y = 20 }});
        harness.wakeFoes(g);
        const id = harness.spawnAt(g, .bloat, .{ .x = 21, .y = 20 }, true);
        g.sim.rng = mathx.Rng.init(seed);
        harness.use(g, .wait);
        if (g.sim.pool.get(id) == null) break;
    } else return error.NeverBurst;
    try std.testing.expectEqualSlices(u16, &.{ 2, 3 }, g.sim.order[0..g.sim.order_n]);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS + fx.FLASH_S, g.pic.busy, 1e-6);
    try std.testing.expectEqual(@as(usize, 2), g.pic.fx.due_n);
    const busy = g.pic.busy;
    const t = harness.framesUntil(g, actor.Pool.slot(3), harness.flashing);
    std.debug.print("a rat bites, then a bloat bursts on the archer: the burst lands {d:.3} s in, the turn is busy {d:.3} s\n", .{ t, busy });
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t, harness.TEST_TOL);
}
