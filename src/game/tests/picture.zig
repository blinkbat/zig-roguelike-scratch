const sprite_assets = @import("../../gfx/sprite_assets.zig");
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

fn expectFadeAndRestore(g: *game.Game, i: usize, away: P) !void {
    g.pic.ease(&g.sim, 0);
    try std.testing.expectEqual(@as(f32, 0), g.pic.occlusion[i]);
    g.pic.ease(&g.sim, harness.FADING_S);
    try std.testing.expect(g.pic.occlusion[i] > 0 and g.pic.occlusion[i] < 1);
    for (0..harness.FADE_FRAMES) |_| g.pic.ease(&g.sim, mathx.TEST_DT);
    try std.testing.expect(g.pic.occlusion[i] > harness.FADED);
    const hero = g.sim.heroSlot().?;
    g.sim.pool.move(&g.sim.lv, g.sim.hero, away);
    g.pic.ease(&g.sim, harness.FADING_S);
    try std.testing.expect(g.pic.occlusion[i] > harness.FADED);
    g.pic.glide[hero] = glide.Glide.rest(g.sim.heroActor().?);
    g.pic.ease(&g.sim, harness.FADING_S);
    try std.testing.expect(g.pic.occlusion[i] > 0 and g.pic.occlusion[i] < harness.FADED);
    for (0..harness.FADE_FRAMES) |_| g.pic.ease(&g.sim, mathx.TEST_DT);
    try std.testing.expect(g.pic.occlusion[i] < harness.UNFADED);
    g.pic.occlusion[i] = 1;
    game.settle(g);
    try std.testing.expectEqual(@as(f32, 0), g.pic.occlusion[i]);
}

test "large tree boughs fade with the pictured hero and only their base blocks" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const behind = P{ .x = 20, .y = 20 };
    const base = P{ .x = 20, .y = 21 };
    harness.arena(g, behind, &.{});
    harness.grassOver(&g.sim.lv);
    g.sim.lv.set(base, .large_tree);
    game.settle(g);
    const i = grid.Level.idx(base);
    try std.testing.expect(g.sim.lv.walkable(behind));
    try std.testing.expect(!g.sim.lv.walkable(base) and g.sim.lv.at(base).blind());
    try std.testing.expect(sprite_assets.Assets.of(&g.sim.lv).tiles.contains(.large_tree));
    try expectFadeAndRestore(g, i, .{ .x = 22, .y = 20 });
}

test "large trees fade around a drawn foe behind them but not an unseen one" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const seen = P{ .x = 24, .y = 20 };
    const unseen = P{ .x = 30, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ seen, unseen });
    harness.grassOver(&g.sim.lv);
    harness.wallIn(&g.sim.lv, .{ .x = 28, .y = 10 }, .{ .x = 28, .y = 30 });
    g.sim.lv.set(seen.add(.{ .x = 0, .y = 1 }), .large_tree);
    g.sim.lv.set(unseen.add(.{ .x = 0, .y = 1 }), .large_tree);
    game.settle(g);
    const near = grid.Level.idx(seen.add(.{ .x = 0, .y = 1 }));
    const far = grid.Level.idx(unseen.add(.{ .x = 0, .y = 1 }));
    try std.testing.expect(g.pic.drawnCell(&g.sim, actor.Pool.slot(g.sim.lv.who(seen))) != null);
    try std.testing.expect(g.pic.drawnCell(&g.sim, actor.Pool.slot(g.sim.lv.who(unseen))) == null);
    for (0..harness.FADE_FRAMES) |_| g.pic.ease(&g.sim, mathx.TEST_DT);
    try std.testing.expect(g.pic.occlusion[near] > harness.FADED);
    try std.testing.expectEqual(@as(f32, 0), g.pic.occlusion[far]);
    try std.testing.expectEqual([2]f32{ 24.5, 20.5 }, g.pic.occluder[near]);
}

test "sight blocking reeds use pictured hero occlusion within their own walkable cell" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    harness.grassOver(&g.sim.lv);
    g.sim.lv.set(at, .reeds);
    game.settle(g);
    const i = grid.Level.idx(at);
    try std.testing.expect(look.occludes(.reeds) and !look.tall(.reeds));
    try std.testing.expect(!look.occludes(.grass) and !look.occludes(.tall_grass));
    try std.testing.expect(g.sim.lv.walkable(at) and g.sim.lv.at(at).blind());
    try expectFadeAndRestore(g, i, .{ .x = 20, .y = 21 });
}

test "collected coins stay drawn only until the collection step finishes" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 21, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expect(g.sim.ground.gold(at, 37));
    harness.nudge(g, .e);
    try std.testing.expectEqual(@as(i32, 37), g.sim.gold);
    try std.testing.expect(g.pic.gold_taken.?.at.eq(at));
    harness.drawnOut(g);
    try std.testing.expect(g.pic.gold_taken == null);
    harness.nudge(g, .e);
    try std.testing.expect(g.pic.glide[g.sim.heroSlot().?].left() > 0);
    try std.testing.expect(g.pic.gold_taken == null);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    try std.testing.expect(g.sim.ground.gold(at, 37));
    harness.nudge(g, .e);
    g.st = .{ .walk = .e };
    game.update(g, game.GLIDE_S - 0.00005);
    try std.testing.expectEqual(@as(i32, 22), g.sim.heroActor().?.at.x);
    try std.testing.expect(g.pic.glide[g.sim.heroSlot().?].left() > 0);
    try std.testing.expect(g.pic.gold_taken == null);
}

fn showsAndLands(g: *game.Game, slot: usize) struct { shows: f32, lands: f32 } {
    var shows: ?f32 = null;
    var lands: ?f32 = null;
    var t: f32 = 0;
    while ((shows == null or lands == null) and t < 1) : (t += harness.TEST_DT) {
        game.update(g, harness.TEST_DT);
        if (shows == null and harness.drawn(g, slot)) shows = t;
        if (lands == null and !g.pic.fx.impacts.pending(.fromIndex(slot))) lands = t;
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

/// Returns before `catchUp`.
fn gassedOffLedge(g: *game.Game) Ledged {
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{});
    const dark = ledge(g);
    const id = harness.spawnAt(g, .slime_half, dark, true);
    const half = actor.Pool.slot(harness.spawnAt(g, .slime_quarter, .{ .x = 22, .y = 19 }, true));
    const s = actor.Pool.slot(id);
    g.pic.split_from[half] = s;
    g.sim.pool.move(&g.sim.lv, g.sim.hero, .{ .x = 19, .y = 20 });
    game.castSight(g, .{ .x = 19, .y = 20 });
    var after = g.pic.afterOf(&g.sim, .fromIndex(s));
    after.reveals = .fromIndex(half);
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
        g.sim.pool.get(id).?.unmask(&g.sim.lv);
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
        game.update(g, 0.01 + span * (game.presentation.STEP_AT - 0.1));
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
    g.pic.glide[slot].t = span * (game.presentation.STEP_AT - 0.05);
    g.pic.busy = span * (1 - game.presentation.STEP_AT + 0.05);
    g.pending = .{ .walk = .e };
    game.update(g, span * (1 - game.presentation.STEP_AT + 0.1));
    try std.testing.expect(g.sim.heroActor().?.at.eq(to.add(mathx.Dir.e.delta())));
    try std.testing.expect(g.pic.fx.head != initial);
}

test "a step onto dirt or sand kicks up its own dust at the footfall, once" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const cases = [_]struct { tile: grid.Tile, ink: @TypeOf(look.DIRT_DUST) }{
        .{ .tile = .dirt, .ink = look.DIRT_DUST },
        .{ .tile = .sand, .ink = look.SAND_DUST },
    };
    for (cases) |case| {
        const from = P{ .x = 20, .y = 20 };
        const to = P{ .x = 21, .y = 20 };
        harness.arena(g, from, &.{});
        g.sim.lv.set(to, case.tile);
        game.settle(g);
        g.st = .{};
        const slot = g.sim.heroSlot().?;
        harness.stepTo(g, g.sim.hero, to);
        game.update(g, g.pic.glide[slot].span());
        var n: usize = 0;
        for (g.pic.fx.motes) |m| n += @intFromBool(m.life > 0 and harness.sameRgb(m.col, case.ink));
        try std.testing.expect(n > 0);
        const emitted = g.pic.fx.head;
        game.update(g, 1);
        try std.testing.expectEqual(emitted, g.pic.fx.head);
    }
}

test "footfalls do not appear on bare ground, hidden steps or melee bumps" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const cases = [_]struct { tile: grid.Tile, hidden: bool = false, bump: bool = false }{
        .{ .tile = .floor },
        .{ .tile = .bridge },
        .{ .tile = .ice },
        .{ .tile = .lava },
        .{ .tile = .shallows, .hidden = true },
        .{ .tile = .shallows, .bump = true },
        .{ .tile = .dirt, .hidden = true },
        .{ .tile = .dirt, .bump = true },
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
    try std.testing.expect(steps > 5);
    try std.testing.expectEqual(steps, hops);
    try std.testing.expectEqual(@as(i32, game.HOP_PX), peaks[hero]);
    try std.testing.expectEqual(@as(i32, game.HOP_PX), peaks[harness.foeSlot(0)]);
    for (g.pic.glide[0..g.sim.pool.n]) |gl| try std.testing.expectEqual(@as(i32, 0), gl.lift());
    try std.testing.expect(!bobbed);
}

test "a foe stepping into the cell of a body still dying there sets off once that body is no longer drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 24, .y = 20 }, .{ .x = 25, .y = 20 } });
    const cell = P{ .x = 24, .y = 20 };
    const dying = harness.foeSlot(0);
    const mover = harness.foeSlot(1);
    _ = g.sim.pool.damage(&g.sim.lv, harness.foeId(0), g.sim.pool.get(harness.foeId(0)).?.hp);
    const lands: f32 = 0.3;
    g.pic.strike(&g.sim, g.cloud, .{ .actor = .{ .slot = .fromIndex(dying), .at = cell, .lethal = true, .after = g.pic.afterOf(&g.sim, .fromIndex(dying)) } }, .{ .from = .{ .x = 20, .y = 20 }, .wait = lands });
    g.sim.pool.move(&g.sim.lv, 3, cell);
    harness.staggerOnly(g, harness.foeId(1));
    var overlap: f32 = 0;
    var t: f32 = 0;
    while (t < 1) : (t += harness.TEST_DT) {
        if (g.pic.standing(&g.sim, dying) and g.pic.glide[mover].done() > 0) overlap += harness.TEST_DT;
        game.update(g, harness.TEST_DT);
    }
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
    try std.testing.expect(worst < game.HOP_PX * 0.2);
    try std.testing.expectEqual(@as(i32, 0), gl.lift());
}

test "a slime slides without hopping, a little past its cell, and settles exactly on it" {
    var gl = glide.Glide.still(.{ .x = 5, .y = 5 }, look.gait(.slime));
    gl = gl.toward(.{ .x = 6, .y = 5 }, 0);
    const to = glide.cellPx(.{ .x = 6, .y = 5 }).x;
    var past: f32 = 0;
    var t: f32 = 0;
    while (t < gl.span() * 1.5) : (t += harness.TEST_DT) {
        gl.t = t;
        try std.testing.expectEqual(@as(i32, 0), gl.lift());
        if (gl.now().x - to > past) {
            past = gl.now().x - to;
        }
    }
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
    const t = [_]f32{ g.pic.glide[g.sim.heroSlot().?].t, g.pic.glide[harness.foeSlot(1)].t, g.pic.glide[harness.foeSlot(2)].t, g.pic.glide[harness.foeSlot(0)].t };
    try std.testing.expectEqualSlices(u16, &.{ harness.foeId(1), harness.foeId(2), harness.foeId(0) }, g.sim.order[0..g.sim.order_n]);
    for (t, 0..) |v, i| try std.testing.expectApproxEqAbs(-game.STAGGER_S * @as(f32, @floatFromInt(i)), v, 1e-6);
    const last = @max(game.STAGGER_S * 2 + game.SLIDE_S, game.STAGGER_S * 3 + game.GLIDE_S);
    try std.testing.expectApproxEqAbs(last, g.pic.busy, 1e-6);
    const at = g.sim.heroActor().?.at;
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(at, g.sim.heroActor().?.at);
    g.st = .{};
    var waited: f32 = 0;
    while (g.sim.heroActor().?.at.eq(at) and waited < 1) : (waited += harness.TEST_DT) game.update(g, harness.TEST_DT);
    try std.testing.expect(!g.sim.heroActor().?.at.eq(at));
    try std.testing.expectApproxEqAbs(last, waited, harness.TEST_TOL);
}

test "an arrow's rat flashes when the arrow gets there, not when the hit resolves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    harness.confirmUse(g, .shoot);
    const rat = harness.foeSlot(0);
    try std.testing.expect(g.sim.pool.get(harness.foeId(0)).?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.impacts.flashOf(.fromIndex(rat)));
    const t = harness.framesUntil(g, rat, harness.flashing);
    try std.testing.expectApproxEqAbs(harness.SHOT_LANDS, t, harness.TEST_TOL);
}

test "after an arrow the foes act a stagger after it lands, so the rat it strikes is still under it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, harness.SHOT_FROM, &.{harness.SHOT_AT});
    harness.wakeFoes(g);
    harness.confirmUse(g, .shoot);
    const lands = harness.SHOT_LANDS;
    const starts = -g.pic.glide[harness.foeSlot(0)].t;
    try std.testing.expect(g.sim.pool.get(harness.foeId(0)).?.hurt());
    try std.testing.expectEqual(harness.SHOT_AT.x - 1, g.sim.pool.get(harness.foeId(0)).?.at.x);
    try std.testing.expectApproxEqAbs(lands + game.STAGGER_S, starts, 1e-6);
}

test "a body the arrow kills stands until the arrow reaches it and its flash is gone" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 20 + bow.RANGE, .y = 20 }});
    g.sim.pool.get(harness.foeId(0)).?.hp = 1;
    harness.confirmUse(g, .shoot);
    const rat = harness.foeSlot(0);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(harness.foeId(0)));
    try std.testing.expect(g.pic.drawnAt(&g.sim, rat) != null);
    const t = harness.framesUntil(g, rat, harness.undrawn);
    const lands = harness.SHOT_LANDS;
    try std.testing.expectApproxEqAbs(lands + fx.FLASH_S, t, harness.TEST_TOL);
}

test "a long frame finishes a killing flash before the next turn is ready" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    g.sim.pool.get(harness.foeId(0)).?.hp = 1;
    harness.confirmUse(g, .shoot);
    g.st = .{};
    game.update(g, g.pic.busy + 0.01);
    try std.testing.expect(g.pic.quiet());
    try std.testing.expect(g.pic.drawnAt(&g.sim, harness.foeSlot(0)) == null);
}

test "the bite that kills the archer leaves it standing and followed until it lands, and the veil waits for the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.bittenToDeath(g);
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
    const hero = g.sim.heroSlot().?;
    try std.testing.expect(g.pic.drawnAt(&g.sim, hero) != null and g.pic.carrierAt(&g.sim) != null);
    const t = harness.framesUntil(g, hero, harness.undrawn);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS + fx.FLASH_S, t, harness.TEST_TOL);
    try std.testing.expect(g.pic.carrierAt(&g.sim) == null and g.pic.busy <= 0);
}

test "a foe whose bite kills the archer is not then killed by the gas it stands in" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.wakeFoes(g);
    g.sim.pool.get(harness.foeId(0)).?.hp = 1;
    g.sim.heroActor().?.hp = 1;
    g.sim.lv.addGas(.{ .x = 21, .y = 20 }, harness.TEST_GAS);
    harness.use(g, .wait);
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
    try std.testing.expect(g.sim.pool.get(harness.foeId(0)) != null);
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
    try std.testing.expectEqualSlices(u16, &.{ harness.foeId(1), harness.foeId(0) }, g.sim.order[0..g.sim.order_n]);
    const bump = g.pic.glide[harness.foeSlot(1)].bump orelse return error.NoBump;
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
    g.sim.rng = harness.meleeThenFoeAttacks(g, harness.foeId(0), &.{harness.foeId(0)});
    harness.nudge(g, .e);
    const hero = g.sim.heroSlot().?;
    const rat = harness.foeSlot(0);
    try std.testing.expect(g.sim.pool.get(harness.foeId(0)).?.hurt() and g.sim.heroActor().?.hurt());
    try std.testing.expectEqual(@as(f32, 0), g.pic.fx.impacts.flashOf(.fromIndex(rat)));
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
    g.sim.pool.get(harness.foeId(0)).?.hp = 1;
    harness.nudge(g, .e);
    try std.testing.expect(g.sim.pool.get(harness.foeId(0)) == null);
    try std.testing.expectEqual(game.Move.kick, scene.leanShown(g, g.pic.groundShown(&g.sim), &scene.stoodNow(g), at, .e));
    harness.drawnOut(g);
    try std.testing.expectEqual(game.Move.step, scene.leanShown(g, g.pic.groundShown(&g.sim), &scene.stoodNow(g), at, .e));
}

test "the lean shows a glowbulb a kick burst until the burst lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    g.sim.lv.set(.{ .x = 21, .y = 20 }, .glow_plant);
    game.settle(g);
    harness.nudge(g, .e);
    try std.testing.expect(!g.sim.lv.at(.{ .x = 21, .y = 20 }).bursts());
    try std.testing.expectEqual(game.Move.burst, scene.leanShown(g, g.pic.groundShown(&g.sim), &scene.stoodNow(g), at, .e));
    harness.drawnOut(g);
    try std.testing.expectEqual(game.Move.step, scene.leanShown(g, g.pic.groundShown(&g.sim), &scene.stoodNow(g), at, .e));
}

test "a kick dealt in a frame of play is no further into its bump than its blow is to landing" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 21, .y = 20 }});
    harness.calm(g);
    g.st = .{ .walk = .e };
    game.update(g, mathx.FRAME_DT);
    const t = g.pic.glide[g.sim.heroSlot().?].t;
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
            if ((o.foe_hit orelse continue) == .kill) kills += 1;
        }
        try std.testing.expectEqual(@as(usize, if (g.mode == .dead) 1 else 0), kills);
        if (g.mode != .dead) continue;
        deaths += 1;
        for (g.pic.owed) |o| {
            if ((o.foe_hit orelse continue) == .hurt) hurts += 1;
        }
    }
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
    const i = harness.foeSlot(0);
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
    try std.testing.expect(g.pic.barrelPresent(&g.sim, p));
}

test "a body coming into sight fades in with its ground and shadow; one born in sight appears at once" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const p = P{ .x = 24, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{p});
    const i = harness.foeSlot(0);
    const k = grid.Level.idx(p);
    const dt = mathx.FRAME_DT;
    g.sim.lv.lit[k] = false;
    g.light.visibility.snap(&g.sim.lv, false);
    g.pic.ease(&g.sim, dt);
    try std.testing.expectEqual(@as(f32, 0), g.pic.sighted[i]);
    g.sim.lv.lit[k] = true;
    var first: f32 = 0;
    var frames: usize = 0;
    var apart: f32 = 0;
    while (g.pic.sighted[i] < 0.95) : (frames += 1) {
        g.pic.ease(&g.sim, dt);
        g.light.visibility.step(&g.sim.lv, dt, false);
        if (frames == 0) first = g.pic.sighted[i];
        apart = @max(apart, @abs(g.pic.sighted[i] - g.light.visibility.sight[k]));
    }
    try std.testing.expect(first > 0 and first < 0.5);
    try std.testing.expect(apart < 1e-5);
    try std.testing.expect(frames <= 15);
    g.sim.lv.lit[k] = false;
    g.pic.split_from[i] = g.sim.heroSlot().?;
    g.pic.ease(&g.sim, dt);
    g.pic.split_from[i] = null;
    g.sim.lv.lit[k] = true;
    g.pic.ease(&g.sim, dt);
    try std.testing.expectEqual(@as(f32, 1), g.pic.sighted[i]);
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
    g.sim.pool.get(harness.foeId(0)).?.hp = 1;
    const said = g.sim.log.n;
    harness.use(g, .wait);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(harness.foeId(0)));
    try std.testing.expectEqual(@as(usize, 1), g.sim.kills);
    try std.testing.expectEqual(@as(usize, 0), g.pic.fx.impacts.count());
    for (g.pic.fx.motes) |m| try std.testing.expect(m.life <= 0);
    try std.testing.expectEqualStrings("The last rat is dead.", g.sim.log.line(0).?);
    try std.testing.expect(std.mem.endsWith(u8, g.sim.log.line(1).?, "experience."));
    try std.testing.expectEqual(said + 2, g.sim.log.n);
}

test "a foe the gas kills after it steps keeps its place in the turn, and its death lands as it arrives" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 25, .y = 20 }});
    const was = g.sim.pool.get(harness.foeId(0)).?.at;
    harness.wakeFoes(g);
    g.sim.pool.get(harness.foeId(0)).?.hp = 1;
    g.sim.lv.addGas(was, harness.TEST_GAS);
    harness.nudge(g, .w);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(harness.foeId(0)));
    try std.testing.expect(!g.sim.pool.items[harness.foeSlot(0)].at.eq(was));
    const t = harness.framesUntil(g, harness.foeSlot(0), harness.flashing);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.GLIDE_S, t, harness.TEST_TOL);
}

test "an arrow that bursts a caustic bloat eats at a sleeping foe with its gas as it lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, harness.SHOT_FROM, &.{});
    const bloat = harness.spawnAt(g, .bloat, harness.SHOT_AT, false);
    const rat = harness.spawnAt(g, .rat, harness.SHOT_AT.add(.{ .x = 1, .y = 1 }), false);
    g.sim.pool.get(bloat).?.hp = 1;
    harness.confirmUse(g, .shoot);
    try std.testing.expectEqual(@as(?*actor.Actor, null), g.sim.pool.get(bloat));
    try std.testing.expect(g.sim.pool.get(rat).?.hurt());
    const lands = harness.SHOT_LANDS;
    const t = harness.framesUntil(g, actor.Pool.slot(rat), harness.flashing);
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
}

test "a caustic bloat's cloud is drawn from when its burst lands" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, harness.SHOT_FROM, &.{});
    const Burst = struct {
        const at = harness.SHOT_AT;
        fn clouded(gm: *game.Game, _: usize) bool {
            return gm.cloud.tint.getPtrConst(.caustic)[grid.Level.idx(at)] > 0;
        }
    };
    const bloat = harness.spawnAt(g, .bloat, Burst.at, false);
    g.sim.pool.get(bloat).?.hp = 1;
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.sim.lv.gasAt(Burst.at) > 0 and !Burst.clouded(g, 0));
    const t = harness.framesUntil(g, 0, Burst.clouded);
    try std.testing.expectApproxEqAbs(harness.SHOT_LANDS, t, harness.TEST_TOL);
}

test "a foe stepping out of sight takes its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 22, .y = 20 }});
    const rat = harness.foeSlot(0);
    const dark = ledge(g);
    game.castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.sim.lv.isLit(dark));
    g.sim.pool.move(&g.sim.lv, 2, dark);
    harness.staggerOnly(g, harness.foeId(0));
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
    const lands = harness.SHOT_LANDS;
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
}

test "a foe's hp as drawn, the archer's and the low glow drop as the blow lands, not as it resolves" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, harness.SHOT_FROM, &.{harness.SHOT_AT});
    const rat = harness.foeSlot(0);
    harness.confirmUse(g, .shoot);
    try std.testing.expect(g.sim.pool.get(harness.foeId(0)).?.hurt());
    try std.testing.expectEqual(actor.row(.rat).hp, g.pic.pictured[rat].hp);
    const Drop = struct {
        fn f(gm: *game.Game, i: usize) bool {
            return gm.pic.pictured[i].hp < actor.row(.rat).hp;
        }
    };
    const t = harness.framesUntil(g, rat, Drop.f);
    try std.testing.expectApproxEqAbs(harness.SHOT_LANDS, t, harness.TEST_TOL);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 25, .y = 21 }, .{ .x = 22, .y = 20 } });
    harness.wakeFoes(g);
    const low: i32 = @intFromFloat(vignette.LOW * @as(f32, @floatFromInt(actor.row(HERO).hp)));
    g.sim.heroActor().?.hp = low;
    g.pic.catchUp(&g.sim);
    g.sim.rng = harness.foeAttacksRngAt(g, .{ .x = 21, .y = 20 }, &.{.{ .id = harness.foeId(1), .lands = true }});
    harness.nudge(g, .e);
    const hero = g.sim.heroSlot().?;
    try std.testing.expect(g.sim.heroActor().?.hp < low);
    try std.testing.expectEqual(low, g.pic.pictured[hero].hp);
    try std.testing.expectEqual(@as(f32, 0), g.vignette.alpha());
    const r = harness.framesUntil(g, hero, harness.reddened);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, r, harness.TEST_TOL);
}

test "an arrow that splits a slime shows it as the arrow lands, the new half sliding out of it" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, harness.SHOT_FROM, &.{});
    const at = harness.SHOT_AT;
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
    const lands = harness.SHOT_LANDS;
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
    const lands = harness.SHOT_LANDS;
    try std.testing.expectApproxEqAbs(lands, t, harness.TEST_TOL);
    try std.testing.expect(g.pic.fx.impacts.pending(.fromIndex(slime)));
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
    try std.testing.expect(g.pic.split_from[half] != null and g.pic.fx.impacts.pending(.fromIndex(half)));
    const when = showsAndLands(g, half);
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
    g.pic.strike(&g.sim, g.cloud, .{ .barrel = p }, .{ .from = .{ .x = 24, .y = 20 }, .wait = 0.2 });
    try std.testing.expect(!g.pic.fx.impacts.breaking(p));
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
    const rat = harness.foeSlot(0);
    const dark = ledge(g);
    game.castSight(g, .{ .x = 20, .y = 20 });
    try std.testing.expect(!g.sim.lv.isLit(dark));
    g.sim.pool.move(&g.sim.lv, 2, dark);
    _ = g.sim.pool.damage(&g.sim.lv, harness.foeId(0), actor.row(.rat).hp);
    g.pic.owed[rat].gassed = .{ .kill = true, .after = .{ .body = fx.Body.of(g.sim.pool.items[rat], 0) } };
    harness.staggerOnly(g, harness.foeId(0));
    g.pic.catchUp(&g.sim);
    try std.testing.expect(g.pic.drawnAt(&g.sim, rat) != null);
    const alive_shown = g.pic.pictured[rat].hp;
    const t = harness.framesUntil(g, rat, harness.undrawn);
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
    try std.testing.expect(!g.pic.fx.impacts.pending(.fromIndex(s)));
}

test "a foe with no place in the turn is stung as the archer's step lands, not before" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 28, .y = 20 };
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{at});
    g.sim.lv.addGas(at, harness.TEST_GAS);
    harness.nudge(g, .w);
    const rat = harness.foeSlot(0);
    try std.testing.expect(g.sim.pool.get(harness.foeId(0)).?.hurt() and g.sim.pool.get(harness.foeId(0)).?.at.eq(at));
    const t = harness.framesUntil(g, rat, harness.flashing);
    try std.testing.expectApproxEqAbs(game.GLIDE_S, t, harness.TEST_TOL);
}

test "a foe is drawn turning at its place in the turn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    harness.wakeFoes(g);
    harness.use(g, .wait);
    const far = harness.foeSlot(1);
    try std.testing.expectEqual(actor.Facing.right, g.pic.facing[far]);
    const t = harness.framesUntil(g, far, harness.facesLeft);
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
    g.sim.rng = harness.meleeThenFoeAttacks(g, harness.foeId(0), &.{ harness.foeId(0), harness.foeId(1) });
    game.update(g, 0);
    const t = harness.framesUntil(g, g.sim.heroSlot().?, harness.reddened);
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
    g.st = .{ .walk = .e, .pressed = .initOne(by.by.?), .down = .initOne(by.by.?) };
    if (by.set == .secondary) g.st.down.insert(g.bar.modifier.?);
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    g.st = .{ .walk = .e };
    game.update(g, 0);
    try std.testing.expectEqual(skillbar.Act.life_flask, g.pending.?.skill.act);
    var next = g.sim.clock;
    _ = next.turn();
    g.st = .{ .walk = .e };
    game.update(g, game.GLIDE_S + mathx.FRAME_DT);
    try std.testing.expect(g.pending == null);
    try std.testing.expectEqual(flask.CHARGES / flask.USE - 1, g.sim.flasks.get(.life).uses());
    try std.testing.expectEqual(next, g.sim.clock);
    try std.testing.expect(g.sim.heroActor().?.at.eq(at));
}

test "a fresh walk tap pressed after a queued skill replaces it, the latest press winning" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    const at = P{ .x = 20, .y = 20 };
    harness.arena(g, at, &.{});
    g.sim.heroActor().?.hp -= 5;
    const by = harness.boundTo(g, .life_flask);
    g.pic.busy = game.GLIDE_S;
    g.st = .{ .pressed = .initOne(by.by.?), .down = .initOne(by.by.?) };
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
    try std.testing.expectApproxEqAbs(dt - busy, t, 1e-5);
}

test "a run left mid-turn keeps the way its foes were turning" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{ .{ .x = 23, .y = 20 }, .{ .x = 26, .y = 20 } });
    harness.wakeFoes(g);
    harness.use(g, .wait);
    const far = harness.foeSlot(1);
    try std.testing.expectEqual(actor.Facing.right, g.pic.facing[far]);
    game.leave(g);
    try std.testing.expectEqual(actor.Facing.left, g.pic.facing[far]);
}

test "a foe that notices the archer turns to it once the archer's step is drawn" {
    const g = try game.boot(std.testing.allocator);
    defer game.shut(std.testing.allocator, g);
    harness.arena(g, .{ .x = 20, .y = 20 }, &.{.{ .x = 24, .y = 20 }});
    harness.nudge(g, .w);
    const rat = harness.foeSlot(0);
    try std.testing.expect(g.sim.pool.get(harness.foeId(0)).?.awake);
    const t = harness.framesUntil(g, rat, harness.facesLeft);
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
    g.pic.fx.strike(wait, .{ .impact = .{ .actor = .{ .slot = .fromIndex(p), .at = g.sim.pool.items[p].at, .lethal = false, .after = .{ .body = fx.Body.of(g.sim.pool.items[p], 1), .reveals = .fromIndex(c) } } }, .dir = null, .matter = .ooze });
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
    try std.testing.expectEqual(game.Mode.dead, std.meta.activeTag(g.mode));
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
    try std.testing.expectEqual(game.Mode.play, std.meta.activeTag(g.mode));
    try std.testing.expectEqual(@as(i32, 1), g.sim.heroActor().?.hp);
}

test "a caustic bloat that bursts on the archer takes its place in the turn as a bite does, and its spray lands there" {
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
    try std.testing.expectEqualSlices(u16, &.{ harness.foeId(0), harness.foeId(1) }, g.sim.order[0..g.sim.order_n]);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS + fx.FLASH_S, g.pic.busy, 1e-6);
    try std.testing.expectEqual(@as(usize, 2), g.pic.fx.impacts.count());
    const t = harness.framesUntil(g, harness.foeSlot(1), harness.flashing);
    try std.testing.expectApproxEqAbs(game.STAGGER_S + game.BUMP_LANDS, t, harness.TEST_TOL);
}
