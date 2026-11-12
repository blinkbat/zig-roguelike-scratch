const sprite_assets = @import("../../gfx/sprite_assets.zig");
const sprite = @import("../../gfx/sprites.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../../core/mathx.zig");
const grid = @import("../../map/grid.zig");
const look = @import("../../gfx/look.zig");
const raster = @import("../../gfx/raster.zig");
const ground = @import("../../gfx/ground.zig");
const light = @import("../../gfx/light.zig");
const day = @import("../../map/day.zig");
const game = @import("../../game.zig");

const P = mathx.P;
const MIN_PIXELS = @import("capture.zig").MIN_PIXELS;
const SHOTS_DIR = @import("capture.zig").SHOTS_DIR;
const WATER_CLIFFS_DIR = SHOTS_DIR ++ "/water-cliffs";
const capture = @import("capture.zig").capture;
const drawInto = @import("capture.zig").drawInto;
const exportImage = @import("capture.zig").exportImage;
const exportTarget = @import("capture.zig").exportTarget;
const intoTarget = @import("capture.zig").intoTarget;
const outOfTarget = @import("capture.zig").outOfTarget;
const pixels = @import("capture.zig").pixels;
const readTarget = @import("capture.zig").readTarget;
const renderTarget = @import("capture.zig").renderTarget;
const sameRgb = @import("capture.zig").sameRgb;
const EVENING = @import("poses.zig").EVENING;
const MORNING = @import("poses.zig").MORNING;
const NIGHT = @import("poses.zig").NIGHT;
const poseWaterMirrors = @import("poses.zig").poseWaterMirrors;
const shadowMask = @import("poses.zig").shadowMask;
const stampRows = @import("poses.zig").stampRows;
const studyLit = @import("poses.zig").studyLit;

pub fn captureWaterCliffs(g: *game.Game) !void {
    const target = try renderTarget(g);
    defer rl.unloadRenderTexture(target);
    try std.fs.cwd().makePath(WATER_CLIFFS_DIR);
    try captureFootfalls(g, target);
    try captureWaterVisibility(g, target);
    try checkCaravanShadowCulling(g, target);
    try waterCliffTemplates(g);
    try checkWaterCapTint(g);
    game.harness.grassArena(g, .{ .x = 24, .y = 19 }, &.{});
    const rows = [_][]const u8{
        "...................",
        "..sssssss...sss.....",
        "..sswwwss...sss.....",
        "..sswwwss...sss.....",
        "....sss.....ssssss..",
        "....sss.....ssssss..",
        "...................",
        "..s...ss....wwwww...",
        "..s...ss....wwwww...",
        "...................",
    };
    stampRows(&g.sim.lv, .{ .x = 15, .y = 13 }, &rows);
    studyLit(g, true, day.NOON);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/grass-day.png");
    game.harness.retile(&g.sim.lv, .grass, .dirt);
    studyLit(g, true, day.NOON);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/dirt-day.png");
    studyLit(g, true, NIGHT);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/dirt-night.png");
    const lands = [_]grid.Tile{ .sand, .snow, .ice, .floor, .rubble, .crop };
    for (lands, 0..) |land, n| {
        game.harness.retile(&g.sim.lv, if (n == 0) .dirt else lands[n - 1], land);
        studyLit(g, true, day.NOON);
        var path: [128]u8 = undefined;
        try capture(g, target, try std.fmt.bufPrintZ(&path, WATER_CLIFFS_DIR ++ "/{s}-day.png", .{@tagName(land)}));
    }
    for (&g.sim.lv.tile, 0..) |*t, i| if (t.* == .crop) {
        t.* = if (grid.Level.of(i).x < 21) .grass else .dirt;
    };
    studyLit(g, true, day.NOON);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/mixed-day.png");
    for ([_]struct { hour: f32, name: []const u8 }{ .{ .hour = MORNING, .name = "morning" }, .{ .hour = EVENING, .name = "evening" } }) |sun| {
        studyLit(g, true, sun.hour);
        var path: [128]u8 = undefined;
        try capture(g, target, try std.fmt.bufPrintZ(&path, WATER_CLIFFS_DIR ++ "/sun-{s}.png", .{sun.name}));
        g.light.options.shadows = false;
        g.light.settle(&g.sim.lv);
        try capture(g, target, try std.fmt.bufPrintZ(&path, WATER_CLIFFS_DIR ++ "/sun-{s}-off.png", .{sun.name}));
        g.light.options.shadows = true;
        g.light.settle(&g.sim.lv);
    }
    game.harness.arena(g, .{ .x = 25, .y = 18 }, &.{});
    @memset(&g.sim.lv.tile, .dirt);
    const stepped = [_][]const u8{
        "wwwwwwsdddddddddddd",
        "wwwwwsddddddddddddd",
        "wwwwsdddddddddddddd",
        "wwwsddddddddddddddd",
        "wwwwsdddddddddddddd",
        "wwwwwsddddddddddddd",
        "wwwwwwsdddddddddddd",
        "wwwwwwwsddddddddddd",
        "wwwwwwwwsdddddddddd",
        "wwwwwwwsddddddddddd",
        "wwwwwwsdddddddddddd",
    };
    stampRows(&g.sim.lv, .{ .x = 14, .y = 13 }, &stepped);
    studyLit(g, true, day.NOON);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/stepped-depths.png");
    poseWaterMirrors(g, day.NOON, true);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/mirrors.png");
    try checkWaterMirrors(g, target);
    try checkMapEdge(g, target);
}

fn captureWaterVisibility(g: *game.Game, target: rl.RenderTexture2D) !void {
    const lens = g.cinema.lens.options;
    defer g.cinema.lens.options = lens;
    g.cinema.lens.options = .neutral;
    game.harness.grassArena(g, .{ .x = 24, .y = 19 }, &.{});
    @memset(&g.sim.lv.tile, .water);
    studyLit(g, true, day.NOON);
    for (&g.sim.lv.lit, 0..) |*lit, i| {
        const p = grid.Level.of(i);
        lit.* = p.x + p.y < 44;
    }
    g.light.settle(&g.sim.lv);
    g.pic.snapSight(&g.sim);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/visibility-diagonal.png");
    const c = game.scene.Cam.of(g);
    var air: [2]rl.Image = undefined;
    for (&air, 0..) |*img, i| {
        if (i == 1) @memset(&g.sim.lv.lit, false);
        g.cinema.prepare(&g.sim.lv, g.light, game.scene.viewBox(g, c), &.{});
        intoTarget(g, target);
        rl.clearBackground(rl.Color.black);
        g.cinema.drawAir(g.light, .{ @floatFromInt(-c.x), @floatFromInt(-c.y) }, game.CELL_F, g.screen, 0);
        outOfTarget(g);
        img.* = try readTarget(target);
    }
    defer for (air) |img| rl.unloadImage(img);
    var mist: usize = 0;
    var px = pixels(g.screen.x, g.screen.y);
    while (px.next()) |p| {
        const a = rl.getImageColor(air[0], p.x, p.y);
        const b = rl.getImageColor(air[1], p.x, p.y);
        if (!sameRgb(a, b)) return error.WaterMistCutsAtGameplaySight;
        if (!sameRgb(a, rl.Color.black)) mist += 1;
    }
    if (mist < MIN_PIXELS) return error.WaterMistMissing;
    std.debug.print("water visibility GPU: {d} mist pixels follow presentation sight across a diagonal boundary\n", .{mist});
    g.light.step(&g.sim.lv, 0.05);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/visibility-fading.png");
    g.light.settle(&g.sim.lv);
    try capture(g, target, WATER_CLIFFS_DIR ++ "/visibility-memory.png");
}

fn captureFootfalls(g: *game.Game, target: rl.RenderTexture2D) !void {
    for ([_]grid.Tile{ .grass, .tall_grass, .dirt, .bridge }) |tile| {
        const from = P{ .x = 24, .y = 19 };
        const to = from.add(.{ .x = 1, .y = 0 });
        game.harness.grassArena(g, from, &.{});
        for (23..28) |x| g.sim.lv.set(.{ .x = @intCast(x), .y = from.y }, tile);
        studyLit(g, true, day.NOON);
        g.st = .{};
        game.harness.stepTo(g, g.sim.hero, to);
        const slot = g.sim.heroSlot().?;
        game.update(g, g.pic.glide[slot].span());
        g.pic.fx.step(&g.sim.lv, 0.1);
        var motes: usize = 0;
        for (g.pic.fx.motes) |m| motes += @intFromBool(m.life > 0);
        if (motes == 0) return error.FootfallParticlesMissing;
        var path: [128]u8 = undefined;
        try capture(g, target, try std.fmt.bufPrintZ(&path, WATER_CLIFFS_DIR ++ "/footfall-{s}.png", .{@tagName(tile)}));
    }
}

fn checkCaravanShadowCulling(g: *game.Game, target: rl.RenderTexture2D) !void {
    var missed: usize = 0;
    var cases: usize = 0;
    var shadowed: usize = 0;
    for (10..15) |tx| for (21..26) |ty| {
        game.harness.arena(g, .{ .x = 25, .y = 25 }, &.{});
        g.sim.lv.set(.{ .x = 16, .y = 25 }, .caravan);
        g.sim.lv.set(.{ .x = 17, .y = 25 }, .caravan_part);
        const torch = P{ .x = @intCast(tx), .y = @intCast(ty) };
        g.sim.lv.set(torch, .wall);
        g.sim.lv.addTorch(torch);
        studyLit(g, false, day.NOON);
        g.sim.pool.n = 0;
        g.light.carrier = null;
        g.cam = .{ .x = 20 * game.CELL, .y = 20 * game.CELL };
        game.prepare(g);
        const c = game.scene.Cam.of(g);
        const view = game.scene.viewBox(g, c);
        g.light.bake(&g.sim.lv, view.lo, view.hi);
        var images: [2]rl.Image = undefined;
        for (0..2) |i| {
            images[i] = try shadowMask(g, target, c, if (i == 0) view else grid.Box.inMap(0));
        }
        defer for (images) |im| rl.unloadImage(im);
        var different: usize = 0;
        var px = pixels(g.screen.x, g.screen.y);
        while (px.next()) |p| {
            const expected = rl.getImageColor(images[1], p.x, p.y);
            if (!sameRgb(expected, rl.Color.white)) shadowed += 1;
            if (!sameRgb(rl.getImageColor(images[0], p.x, p.y), expected)) different += 1;
        }
        if (different > 0) {
            if (missed == 0) {
                try exportImage(images[0], WATER_CLIFFS_DIR ++ "/caravan-shadow-culled.png");
                try exportImage(images[1], WATER_CLIFFS_DIR ++ "/caravan-shadow-reference.png");
            }
            std.debug.print("caravan culling torch {d},{d}: {d} differing pixels\n", .{ tx, ty, different });
            missed += different;
        }
        cases += 1;
    };
    std.debug.print("caravan shadow culling GPU: {d} cases, {d} shadow pixels, {d} missing pixels against whole-map scan\n", .{ cases, shadowed, missed });
    if (missed > 0) return error.CaravanShadowCulled;
    if (shadowed < 20) return error.CaravanShadowMissing;
}

const GLINT_INK = look.rgb(0x302010);
const SWATCH_PX = 256;
const SWATCH_ORIGIN: f32 = -608;
const SWATCH_LO = P{ .x = 8, .y = 8 };
const SWATCH_HI = P{ .x = 15, .y = 15 };
const SHIMMER_S: f32 = 1.7;

fn swatch(w: i32, h: i32, c: rl.Color, comptime missing: anyerror) !rl.Texture2D {
    return raster.canvas(w, h, c, .point) orelse return missing;
}

fn checkWaterCapTint(g: *game.Game) !void {
    const target = try rl.loadRenderTexture(SWATCH_PX, SWATCH_PX);
    defer rl.unloadRenderTexture(target);
    const sight = try swatch(1, 1, .{ .r = 128, .g = 128, .b = 128, .a = 255 }, error.WaterVisibilityMissing);
    defer rl.unloadTexture(sight);
    const dark = try swatch(1, 1, rl.Color.black, error.WaterGlintsMissing);
    defer rl.unloadTexture(dark);
    const shine = try swatch(1, 1, GLINT_INK, error.WaterGlintsMissing);
    defer rl.unloadTexture(shine);
    const mirror = try swatch(1, 1, .{ .r = 80, .g = 90, .b = 120, .a = 128 }, error.WaterMirrorMissing);
    defer rl.unloadTexture(mirror);
    const blank = try swatch(1, 1, rl.Color.blank, error.WaterMirrorMissing);
    defer rl.unloadTexture(blank);
    var lv = grid.Level.blank();
    @memset(&lv.tile, .shallows);
    lv.set(.{ .x = 30, .y = 30 }, .water);
    g.sprites.sync(sprite_assets.Assets.of(&lv));
    const alternates = .{ g.sprites.shallows2, g.sprites.shallows3 };
    defer {
        g.sprites.shallows2 = alternates[0];
        g.sprites.shallows3 = alternates[1];
    }
    g.sprites.shallows2 = null;
    g.sprites.shallows3 = null;
    var checked: usize = 0;
    for ([_]bool{ false, true }) |effects| {
        const view = sprite.WaterView{
            .screen = .{ SWATCH_PX, SWATCH_PX },
            .visibility = sight,
            .glints = if (effects) shine else dark,
            .mirror = if (effects) .{ .live = mirror, .memory = blank } else null,
            .shimmer = effects,
            .seconds = SHIMMER_S,
        };
        for ([_]f32{ -640, -544 }) |y_origin| {
            const origin = [2]f32{ SWATCH_ORIGIN, y_origin };
            var beds: ground.Beds = undefined;
            @memset(&lv.tile, .shallows);
            beds.fill(&lv, SWATCH_LO, SWATCH_HI, false);
            const reference = try waterSample(g, target, &beds, view, origin);
            defer rl.unloadImage(reference);
            for (&lv.tile, 0..) |*t, i| if (grid.Level.of(i).y >= 11) {
                t.* = .water;
            };
            beds.fill(&lv, beds.lo, beds.hi, false);
            rl.beginTextureMode(target);
            rl.clearBackground(rl.Color.blank);
            g.sprites.drawWaterCliffCaps(&beds, origin, game.CELL_F, view);
            rl.endTextureMode();
            const cap = try readTarget(target);
            defer rl.unloadImage(cap);
            var px = pixels(SWATCH_PX, SWATCH_PX);
            while (px.next()) |p| {
                const actual = rl.getImageColor(cap, p.x, p.y);
                if (actual.a == 0) continue;
                if (!sameRgb(actual, rl.getImageColor(reference, p.x, p.y))) return error.WaterCapTintMismatch;
                checked += 1;
            }
        }
    }
    if (checked < 20000) return error.WaterCapCoverageMissing;
    std.debug.print("water cap GPU: {d} pixels match ordinary shallow water at two screen heights, with tint-only and reflections/glints/shimmer\n", .{checked});
}

const TemplateLayer = enum { ground, bare, faces, caps, edges };

fn waterCliffTemplates(g: *game.Game) !void {
    game.prepare(g);
    if (g.sprites.bank_cap == null) return error.BankCapShaderMissing;
    const target = try rl.loadRenderTexture(SWATCH_PX, SWATCH_PX);
    defer rl.unloadRenderTexture(target);
    const pairs = [_][2]grid.Tile{ .{ .dirt, .shallows }, .{ .dirt, .water }, .{ .shallows, .water } };
    for (pairs, 0..) |pair, n| {
        var lv = grid.Level.blank();
        @memset(&lv.tile, pair[0]);
        for (ground.ORDER, 0..) |mask, i| {
            const p = P{ .x = 10 + @as(i32, @intCast(i % 4)), .y = 10 + @as(i32, @intCast(i / 4)) };
            for (ground.AROUND) |a| lv.set(p.add(a.d), if (mask & a.bit != 0) pair[0] else pair[1]);
        }
        var beds: ground.Beds = undefined;
        beds.fill(&lv, SWATCH_LO, SWATCH_HI, false);
        g.sprites.sync(sprite_assets.Assets.of(&lv));
        const origin = [2]f32{ SWATCH_ORIGIN, SWATCH_ORIGIN };
        for (std.enums.values(TemplateLayer)) |pass| {
            rl.beginTextureMode(target);
            rl.clearBackground(rl.Color.blank);
            switch (pass) {
                .ground => g.sprites.drawGround(&lv, &beds, origin, game.CELL_F, null),
                .bare => {
                    var base = g.sprites;
                    base.shallows_cliff = null;
                    base.water_cliff = null;
                    base.dirt_shallows_edges = null;
                    base.dirt_water_edges = null;
                    base.shallows_water_edges = null;
                    base.drawGround(&lv, &beds, origin, game.CELL_F, null);
                },
                .faces => g.sprites.drawWaterCliffFaces(&beds, origin, game.CELL_F, null),
                .caps => g.sprites.drawWaterCliffCaps(&beds, origin, game.CELL_F, null),
                .edges => g.sprites.drawWaterEdges(&beds, origin, game.CELL_F, null),
            }
            rl.endTextureMode();
            var path: [128]u8 = undefined;
            const name = if (pass == .ground)
                try std.fmt.bufPrintZ(&path, WATER_CLIFFS_DIR ++ "/template-{d}.png", .{n})
            else
                try std.fmt.bufPrintZ(&path, WATER_CLIFFS_DIR ++ "/template-{d}-layer-{d}.png", .{ n, @intFromEnum(pass) });
            const img = try readTarget(target);
            defer rl.unloadImage(img);
            try exportImage(img, name);
        }
    }
}

fn waterSample(g: *game.Game, target: rl.RenderTexture2D, beds: *const ground.Beds, view: ?sprite.WaterView, origin: [2]f32) !rl.Image {
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    g.sprites.drawGround(&g.sim.lv, beds, origin, game.CELL_F, view);
    rl.endTextureMode();
    return readTarget(target);
}

pub fn captureWater(g: *game.Game, target: rl.RenderTexture2D) !void {
    try std.fs.cwd().makePath(SHOTS_DIR ++ "/water-reflections");
    g.st = .{};
    const FRAMES = 40;
    const EVERY = 6;
    const before = g.light.t.at();
    const minute = g.sim.clock;
    for (0..FRAMES) |i| {
        for (0..EVERY) |_| game.update(g, mathx.FRAME_DT);
        var path: [80]u8 = undefined;
        try capture(g, target, try std.fmt.bufPrintZ(&path, SHOTS_DIR ++ "/water-reflections/{d:0>2}.png", .{i}));
    }
    const elapsed = g.light.t.at() - before;
    if (elapsed < FRAMES * EVERY * mathx.FRAME_DT - 0.01 or !std.meta.eql(minute, g.sim.clock)) return error.WaterIdleClock;
    std.debug.print("water reflections idle play: {d:.2} seconds in {d} rendered frames, no turn spent\n", .{ elapsed, FRAMES });
}

const CAMERA_SHIFT = P{ .x = 16, .y = 8 };

pub fn checkWaterSurface(g: *game.Game) !void {
    const BANDS = [_]grid.Tile{ .water, .shallows, .grass };
    const DRY = comptime std.mem.indexOfScalar(grid.Tile, &BANDS, .grass).?;
    const BAND = 4;
    const ROWS = 2;
    const Band = struct {
        fn of(x: i32) ?usize {
            const in_band = @mod(x, BAND * game.CELL);
            if (in_band < game.HALF_CELL or in_band >= BAND * game.CELL - game.HALF_CELL) return null;
            return @intCast(@divTrunc(x, BAND * game.CELL));
        }
    };
    const width = BANDS.len * BAND * game.CELL;
    const height = ROWS * game.CELL;
    const target = try rl.loadRenderTexture(width, height);
    defer rl.unloadRenderTexture(target);
    const mirror = try rl.loadRenderTexture(width, height);
    defer rl.unloadRenderTexture(mirror);
    rl.beginTextureMode(mirror);
    rl.clearBackground(look.rgb(0x1010ff));
    rl.drawRectangle(0, game.CELL, width, game.CELL, look.rgb(0xff1010));
    rl.endTextureMode();
    var lv = grid.Level.blank();
    for (&lv.tile, 0..) |*t, i| {
        const x: usize = @intCast(grid.Level.of(i).x);
        t.* = BANDS[@min(x / BAND, BANDS.len - 1)];
    }
    var beds: ground.Beds = undefined;
    beds.fill(&lv, .{ .x = 0, .y = 0 }, .{ .x = BANDS.len * BAND, .y = ROWS }, false);
    var sight: [grid.CELLS]rl.Color = @splat(.{ .r = 128, .g = 128, .b = 128, .a = 0 });
    for (sight[0..grid.COLS]) |*pixel| pixel.a = 255;
    const visibility = raster.clamped(raster.rgba(&sight, grid.W, grid.H), .point) orelse return error.WaterVisibilityMissing;
    defer rl.unloadTexture(visibility);
    const gleam = try swatch(grid.W, grid.H, GLINT_INK, error.WaterGlintsMissing);
    defer rl.unloadTexture(gleam);
    const dark = try swatch(1, 1, rl.Color.black, error.WaterGlintsMissing);
    defer rl.unloadTexture(dark);
    const blank = try swatch(1, 1, rl.Color.blank, error.WaterMirrorMissing);
    defer rl.unloadTexture(blank);
    const plain = try waterSample(g, target, &beds, null, .{ 0, 0 });
    defer rl.unloadImage(plain);
    var view = sprite.WaterView{ .screen = .{ width, height }, .visibility = visibility, .glints = dark };
    const still = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(still);
    view.glints = gleam;
    const first = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(first);
    try exportImage(first, SHOTS_DIR ++ "/water-glints.png");
    view.glints = dark;
    view.mirror = .{ .live = mirror.texture, .memory = blank };
    const second = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(second);
    try exportImage(second, SHOTS_DIR ++ "/water-mirror-mask.png");
    var glinted = [_]usize{0} ** BANDS.len;
    var reflected = [_]usize{0} ** BANDS.len;
    var fixed: usize = 0;
    {
        var px = pixels(width, height);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const base = rl.getImageColor(still, x, y);
            const a = rl.getImageColor(first, x, y);
            const b = rl.getImageColor(second, x, y);
            if (base.a != rl.getImageColor(plain, x, y).a or a.a != base.a or b.a != base.a) return error.WaterAlphaChanged;
            const band = Band.of(x) orelse continue;
            if (y >= game.CELL or band == DRY) {
                if (!std.meta.eql(base, a) or !std.meta.eql(base, b)) return error.WaterOutsideSurface;
                fixed += 1;
            } else {
                if (!std.meta.eql(base, a)) glinted[band] += 1;
                if (!std.meta.eql(base, b)) {
                    if (b.b <= b.r) return error.WaterMirrorUpsideDown;
                    reflected[band] += 1;
                }
            }
        }
    }
    for (0..DRY) |i| {
        if (glinted[i] < MIN_PIXELS or reflected[i] < MIN_PIXELS) return error.WaterReflectionMissing;
    }
    view.mirror = .{ .live = blank, .memory = mirror.texture };
    const memory = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(memory);
    var remembered = [_]usize{0} ** BANDS.len;
    {
        var px = pixels(width, height);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const base = rl.getImageColor(still, x, y);
            const m = rl.getImageColor(memory, x, y);
            if (m.a != base.a) return error.WaterAlphaChanged;
            const band = Band.of(x) orelse continue;
            if (y < game.CELL or band == DRY) {
                if (!std.meta.eql(base, m)) return error.WaterOutsideSurface;
            } else if (!std.meta.eql(base, m)) {
                if (@as(i32, m.r) - base.r <= @as(i32, m.b) - base.b) return error.WaterMirrorUpsideDown;
                remembered[band] += 1;
            }
        }
    }
    for (remembered[0..DRY]) |count| {
        if (count < MIN_PIXELS) return error.WaterMemoryMissing;
    }
    view.glints = gleam;
    view.mirror = null;
    // Water fades by screen row, so only a sideways shift keeps each row's fade.
    const shift = P{ .x = CAMERA_SHIFT.x, .y = 0 };
    const shifted = try waterSample(g, target, &beds, view, .{ -shift.x, -shift.y });
    defer rl.unloadImage(shifted);
    var compared: usize = 0;
    {
        var px = pixels(width - shift.x, height - shift.y);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const a = rl.getImageColor(first, x + shift.x, y + shift.y);
            const b = rl.getImageColor(shifted, x, y);
            if (@abs(@as(i32, a.r) - b.r) > 1 or @abs(@as(i32, a.g) - b.g) > 1 or @abs(@as(i32, a.b) - b.b) > 1 or a.a != b.a) return error.WaterMovesWithCamera;
            compared += 1;
        }
    }
    std.debug.print("smooth water GPU: glints {d}/{d}, live mirrors {d}/{d}, remembered mirrors {d}/{d}; {d} grass/memory pixels exclude live effects, {d} sideways camera samples agree; alpha preserved\n", .{ glinted[0], glinted[1], reflected[0], reflected[1], remembered[0], remembered[1], fixed, compared });
    view.glints = dark;
    view.shimmer = true;
    const swelled = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(swelled);
    view.seconds = SHIMMER_S;
    const later = try waterSample(g, target, &beds, view, .{ 0, 0 });
    defer rl.unloadImage(later);
    var swelling = [_]usize{0} ** DRY;
    var moving: usize = 0;
    {
        var px = pixels(width, height);
        while (px.next()) |q| {
            const base = rl.getImageColor(still, q.x, q.y);
            const a = rl.getImageColor(swelled, q.x, q.y);
            const b = rl.getImageColor(later, q.x, q.y);
            if (a.a != base.a or b.a != base.a) return error.WaterAlphaChanged;
            const band = Band.of(q.x) orelse continue;
            if (q.y >= game.CELL or band == DRY) {
                if (!std.meta.eql(base, a) or !std.meta.eql(base, b)) return error.WaterOutsideSurface;
            } else {
                if (!sameRgb(base, a)) swelling[band] += 1;
                if (!sameRgb(a, b)) moving += 1;
            }
        }
    }
    for (swelling) |n| if (n < MIN_PIXELS) return error.WaterShimmerMissing;
    if (moving < MIN_PIXELS) return error.WaterShimmerMissing;
    std.debug.print("water shimmer GPU: {d}/{d} deep/shallow highlight pixels swell, {d} move in {d} s; grass, memory and alpha untouched\n", .{ swelling[0], swelling[1], moving, SHIMMER_S });
}

pub fn checkMapEdge(g: *game.Game, target: rl.RenderTexture2D) !void {
    const lens = g.cinema.lens.options;
    defer g.cinema.lens.options = lens;
    g.cinema.lens.options = .neutral;
    game.harness.grassArena(g, .{ .x = 24, .y = grid.H - 4 }, &.{});
    for (0..grid.W) |x| g.sim.lv.set(.{ .x = @intCast(x), .y = grid.H - 1 }, .grass);
    studyLit(g, true, day.NOON);
    const edge = @divTrunc(g.screen.y, 2);
    g.cam.y = @floatFromInt(game.MAP_PX.y - edge);
    game.prepare(g);
    var compared: usize = 0;
    for ([_]bool{ true, false }) |visible| {
        @memset(&g.sim.lv.lit, visible);
        g.light.settle(&g.sim.lv);
        intoTarget(g, target);
        rl.clearBackground(look.FOG);
        game.scene.drawMap(g);
        outOfTarget(g);
        try exportTarget(target, if (visible) SHOTS_DIR ++ "/map-bottom-edge.png" else SHOTS_DIR ++ "/map-bottom-memory.png");
        const img = try readTarget(target);
        defer rl.unloadImage(img);
        {
            var px = grid.Cells.of(.{ .x = 0, .y = edge }, .{ .x = g.screen.x, .y = edge + game.CELL });
            while (px.next()) |q| {
                const x = q.x;
                const y = q.y;
                const pixel = rl.getImageColor(img, x, y);
                if (!sameRgb(pixel, look.FOG)) return error.MapEdgeOverhang;
                compared += 1;
            }
        }
    }
    std.debug.print("map bottom GPU: {d} pixels beyond lit and remembered terrain stay clear\n", .{compared});
}

pub fn checkWaterMirrors(g: *game.Game, target: rl.RenderTexture2D) !void {
    const original = try readTarget(g.sprites.mirror orelse return error.WaterMirrorMissing);
    defer rl.unloadImage(original);
    const camera = g.cam;
    const shift = CAMERA_SHIFT;
    g.cam.x += @floatFromInt(shift.x);
    g.cam.y += @floatFromInt(shift.y);
    drawInto(g, target);
    const moved = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(moved);
    var compared: usize = 0;
    var reflected: usize = 0;
    {
        var px = pixels(original.width - shift.x, original.height - shift.y);
        while (px.next()) |q| {
            const x = q.x;
            const y = q.y;
            const a = rl.getImageColor(original, x + shift.x, y + shift.y);
            const b = rl.getImageColor(moved, x, y);
            if (a.a > 0) reflected += 1;
            if (!std.meta.eql(a, b)) return error.WaterMirrorCameraDrift;
            compared += 1;
        }
    }
    if (reflected < MIN_PIXELS) return error.WaterMirrorEmpty;
    g.cam = camera;
    @memset(&g.sim.lv.lit, false);
    g.light.settle(&g.sim.lv);
    g.pic.snapSight(&g.sim);
    try capture(g, target, SHOTS_DIR ++ "/water-mirrors-memory.png");
    const memory = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(memory);
    const dim = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(dim);
    const actors = g.sim.pool.n;
    g.sim.pool.n = 0;
    defer g.sim.pool.n = actors;
    drawInto(g, target);
    const empty = try readTarget(g.sprites.mirror.?);
    defer rl.unloadImage(empty);
    var remembered: usize = 0;
    {
        var px = pixels(memory.width, memory.height);
        while (px.next()) |p| {
            if (rl.getImageColor(memory, p.x, p.y).a > 0) remembered += 1;
            if (!std.meta.eql(rl.getImageColor(dim, p.x, p.y), rl.getImageColor(empty, p.x, p.y))) return error.WaterMirrorRevealsHidden;
        }
    }
    if (remembered < MIN_PIXELS) return error.WaterMemoryMissing;
    try checkRememberedBarrels(g, target, memory);
    @memset(&g.sim.lv.seen, false);
    g.light.settle(&g.sim.lv);
    g.pic.snapSight(&g.sim);
    intoTarget(g, target);
    const c = game.scene.Cam.of(g);
    var flame_buf: [light.LIGHTS]light.Flame = undefined;
    _ = game.scene.drawMirrors(g, c, g.pic.groundShown(&g.sim), game.scene.viewBox(g, c), &game.scene.bagCells(g), &.{}, g.light.flames(&g.sim.lv, &flame_buf));
    outOfTarget(g);
    for ([_]rl.RenderTexture2D{ g.sprites.mirror.?, g.sprites.mirror_memory.? }) |t| {
        const hidden = try readTarget(t);
        defer rl.unloadImage(hidden);
        {
            var px = pixels(hidden.width, hidden.height);
            while (px.next()) |p| {
                if (rl.getImageColor(hidden, p.x, p.y).a != 0) return error.WaterMirrorRevealsHidden;
            }
        }
    }
    std.debug.print("water mirror GPU: {d} live and {d} remembered pixels; {d} camera samples agree; hidden bodies and unexplored scenery absent\n", .{ reflected, remembered, compared });
}

fn checkRememberedBarrels(g: *game.Game, target: rl.RenderTexture2D, before: rl.Image) !void {
    const barrels = g.sim.lv.barrel;
    const remembered = g.sim.lv.barrel_seen;
    defer {
        g.sim.lv.barrel = barrels;
        g.sim.lv.barrel_seen = remembered;
        g.art = .stale;
    }
    @memset(&g.sim.lv.barrel, false);
    g.art = .stale;
    try capture(g, target, SHOTS_DIR ++ "/water-mirrors-broken-remembered.png");
    const broken = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(broken);
    @memset(&g.sim.lv.barrel_seen, false);
    g.art = .stale;
    drawInto(g, target);
    const forgotten = try readTarget(g.sprites.mirror_memory.?);
    defer rl.unloadImage(forgotten);
    var kept: usize = 0;
    var px = pixels(before.width, before.height);
    while (px.next()) |p| {
        const a = rl.getImageColor(before, p.x, p.y);
        const b = rl.getImageColor(broken, p.x, p.y);
        if (!std.meta.eql(a, b)) return error.WaterMirrorForgetsUnseenBarrel;
        if (!std.meta.eql(b, rl.getImageColor(forgotten, p.x, p.y))) kept += 1;
    }
    if (kept < MIN_PIXELS) return error.WaterBarrelMemoryMissing;
    std.debug.print("remembered barrel GPU: {d} reflection pixels survive unseen destruction and clear with memory\n", .{kept});
}
