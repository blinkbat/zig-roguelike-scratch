const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const dual = @import("../gfx/ground.zig");
const light = @import("../gfx/light.zig");
const fx = @import("../gfx/fx.zig");
const cloud = @import("../gfx/cloud.zig");
const sky = @import("../gfx/sky.zig");
const day = @import("../map/day.zig");
const game = @import("../game.zig");
const P = mathx.P;

pub const Cam = struct {
    x: i32,
    y: i32,
    at: rl.Vector2,

    pub fn of(g: *game.Game) Cam {
        return .{ .x = mathx.roundTiesDown(g.cam.x), .y = mathx.roundTiesDown(g.cam.y), .at = g.cam };
    }

    fn sx(c: Cam, p: P) i32 {
        return p.x * game.CELL - c.x;
    }

    fn sy(c: Cam, p: P) i32 {
        return p.y * game.CELL - c.y;
    }

    pub fn corner(c: Cam, p: P) P {
        return .{ .x = c.sx(p), .y = c.sy(p) };
    }

    pub fn mid(c: Cam, p: P) P {
        return c.corner(p).add(.{ .x = game.HALF_CELL, .y = game.HALF_CELL });
    }

    fn box(c: Cam, p: P) rl.Rectangle {
        return look.rect(c.sx(p), c.sy(p), game.CELL, game.CELL);
    }

    /// The map's top-left on screen.
    fn origin(c: Cam) [2]f32 {
        return .{ @floatFromInt(-c.x), @floatFromInt(-c.y) };
    }

    /// Rounds the offset from the camera once, so a body keeping pace with it holds still on screen.
    pub fn px(c: Cam, v: rl.Vector2) P {
        return .{ .x = mathx.roundTiesUp(v.x - c.at.x), .y = mathx.roundTiesUp(v.y - c.at.y) };
    }
};

fn spriteRect(t: rl.Texture2D, sx: i32, sy: i32) rl.Rectangle {
    const k = @max(1, @divTrunc(game.CELL, t.width));
    return look.rect(sx + @divTrunc(game.CELL - t.width * k, 2), sy + @divTrunc(game.CELL - t.height * k, 2), t.width * k, t.height * k);
}

fn drawSprite(t: rl.Texture2D, sx: i32, sy: i32) void {
    look.stretch(t, spriteRect(t, sx, sy), look.LIT);
}

fn outline(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleLinesEx(look.grown(c.box(p), @floatFromInt(-game.OUTLINE_INSET)), @floatFromInt(game.LINE_W), col);
}

fn fillCell(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleRec(c.box(p), col);
}

/// Barrels stay remembered until the hero's visible breaking blow lands.
pub fn barrelShownAt(g: *game.Game, p: P) bool {
    return game.character.terrainSeen(g, p) and barrelPresent(g, p);
}

pub fn barrelPresent(g: *game.Game, p: P) bool {
    return g.lv.hasBarrel(p) or g.fx.breaking(p);
}

fn shownAt(g: *game.Game, stood: *const Stood, p: P) bool {
    return (grid.Level.inside(p) and stood.isSet(grid.Level.idx(p))) or barrelShownAt(g, p);
}

pub fn stoodNow(g: *game.Game) Stood {
    var stood = Stood.initEmpty();
    for (0..g.pool.n) |i| stand(&stood, game.drawnCell(g, i) orelse continue);
    return stood;
}

fn stand(stood: *Stood, under: P) void {
    if (grid.Level.inside(under)) stood.set(grid.Level.idx(under));
}

fn bar(x: i32, y: i32, w: i32, h: i32, v: i32, max: i32, back: rl.Color, fill: rl.Color) void {
    rl.drawRectangle(x, y, w, h, back);
    rl.drawRectangle(x, y, mathx.filled(v, max, w), h, fill);
}

const Shown = struct {
    pic: fx.Body,
    slot: usize,
    s: P,
    lifted: P,
    mid: [2]f32,
    left: bool,
    shine: light.Shine,
};

const Prop = struct {
    s: P,
    mid: [2]f32,
    shine: light.Shine,

    fn at(g: *game.Game, c: Cam, p: P, casting: bool) Prop {
        const mid = mathx.centre(p);
        return .{ .s = c.corner(p), .mid = mid, .shine = if (casting) g.light.onCaster(mid, false) else g.light.onBody(mid, false) };
    }
};

const Barrels = struct {
    g: *game.Game,
    c: Cam,
    cells: grid.Cells,

    fn of(g: *game.Game, c: Cam, lo: P, hi: P) Barrels {
        return .{ .g = g, .c = c, .cells = grid.Cells.of(lo, hi) };
    }

    fn next(self: *Barrels) ?Prop {
        while (self.cells.next()) |p| {
            if (barrelShownAt(self.g, p)) return Prop.at(self.g, self.c, p, false);
        }
        return null;
    }
};

fn drawLit(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32, fade: [2]f32) void {
    if (tex) |t| {
        g.light.drawBody(t, spriteRect(t, s.x, s.y), left, mid, shine, flash, fade);
    } else game.drawGlyph(g, l.ch, s.x, s.y, shine.drawn(l.fg, flash));
}

fn drawFigure(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32) void {
    drawLit(g, tex, l, s, left, mid, shine, flash, .{ 0, 0 });
    if (!g.cloud.beginVeil(shine.tint(look.GAS), .sharp)) return;
    defer cloud.Cloud.endVeil();
    if (tex) |t| {
        look.blit(t, look.rect(0, 0, if (left) -t.width else t.width, t.height), spriteRect(t, s.x, s.y), rl.Color.white);
    } else game.drawGlyph(g, l.ch, s.x, s.y, rl.Color.white);
}

const Stood = std.StaticBitSet(grid.CELLS);

fn drawGroundPass(g: *game.Game, c: Cam, beds: *const dual.Beds, stood: *const Stood, mirror: ?look.Mirrors) void {
    const x = std.math.clamp(-c.x, 0, g.screen.x);
    const y = std.math.clamp(-c.y, 0, g.screen.y);
    const right = std.math.clamp(game.MAP_PX.x - c.x, 0, g.screen.x);
    const bottom = std.math.clamp(game.MAP_PX.y - c.y, 0, g.screen.y);
    rl.beginScissorMode(x, y, right - x, bottom - y);
    defer rl.endScissorMode();
    const water: ?look.WaterView = if (g.light.glintTexture()) |glints| if (g.light.mapTexture()) |tex| .{
        .screen = .{ @floatFromInt(g.screen.x), @floatFromInt(g.screen.y) },
        .visibility = tex,
        .glints = glints,
        .mirror = mirror,
    } else null else null;
    g.sprites.drawGround(beds, c.origin(), game.CELL_F, water);
    var cells = grid.Cells.of(beds.lo, beds.hi);
    while (cells.next()) |p| {
        if (!game.character.terrainSeen(g, p)) continue;
        const here = g.lv.at(p);
        if (look.glyphGround(here, &g.sprites)) inkCell(g, c, p, here, stood);
        if (g.lv.doorAt(p) != null) game.drawGlyph(g, look.DOOR.ch, c.sx(p), c.sy(p), look.DOOR.fg);
    }
}

/// At full light, what stands on the seen cells from `lo` up to `hi`, over the shadows cast on the ground.
fn drawSolidPass(g: *game.Game, c: Cam, lo: P, hi: P, stood: *const Stood) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (!game.character.terrainSeen(g, p)) continue;
        const here = g.lv.at(p);
        if (!look.standsOver(here)) continue;
        if (g.sprites.tileAt(&g.lv, p)) |t| {
            const focus = g.cinema.beginFocus(here, t, mathx.centre(p), g.light.carrier);
            drawSprite(t, c.sx(p), c.sy(p));
            if (focus != null) rl.endShaderMode();
            if (look.veiled(here) and g.cloud.beginVeil(look.GAS, focus orelse .sharp)) {
                drawSprite(t, c.sx(p), c.sy(p));
                cloud.Cloud.endVeil();
            }
            continue;
        }
        if (look.tileBg(here)) |bg| fillCell(c, p, bg);
        inkCell(g, c, p, here, stood);
        if (look.veiled(here) and g.cloud.beginVeil(look.GAS, .sharp)) {
            inkCell(g, c, p, here, stood);
            cloud.Cloud.endVeil();
        }
    }
}

fn inkCell(g: *game.Game, c: Cam, p: P, here: grid.Tile, stood: *const Stood) void {
    if (shownAt(g, stood, p)) return;
    const m = c.mid(p);
    look.inkTile(&g.face, here, m.x, m.y, game.GLYPH);
}

/// Every shadow cast into `view`, multiplied over what `framebuffer` holds; false with no shader for it.
pub fn shadowPass(g: *game.Game, c: Cam, view: grid.Box, framebuffer: u32) bool {
    if (!g.light.beginShadows(g.screen, framebuffer)) return false;
    drawShadows(g, c, view.grown(game.CAST_MARGIN));
    g.light.endShadows(-c.x, -c.y, game.CELL);
    return true;
}

fn drawShadows(g: *game.Game, c: Cam, cast: grid.Box) void {
    var props = cast.cells();
    while (props.next()) |p| {
        if (barrelPresent(g, p)) {
            if (g.sprites.barrel) |t| {
                const b = Prop.at(g, c, p, true);
                g.light.drawShadows(t, spriteRect(t, b.s.x, b.s.y), false, b.mid, &b.shine);
            }
        }
        const kind = g.lv.at(p);
        if (!look.stands(kind)) continue;
        const forest = look.forestAt(&g.lv, p);
        const t = g.sprites.tileAt(&g.lv, p) orelse continue;
        const pr = Prop.at(g, c, p, true);
        const rect = spriteRect(t, pr.s.x, pr.s.y);
        if (forest) {
            g.light.drawForestShadows(t, rect, pr.mid, &pr.shine, g.lv.tileShape(p) orelse .{});
        } else if (look.canopied(kind)) {
            g.light.drawCanopy(t, rect, pr.mid, &pr.shine);
        } else g.light.drawShadows(t, rect, false, pr.mid, &pr.shine);
    }
    for (0..g.pool.n) |i| {
        const at = game.casterAt(g, i, cast) orelse continue;
        const t = g.sprites.body(g.pictured[i].kind) orelse continue;
        const s = c.px(at);
        const mid = game.middle(at);
        const shine = g.light.onCaster(mid, game.isHero(g, i));
        g.light.drawShadows(t, spriteRect(t, s.x, s.y), g.facing[i] == .left, mid, &shine);
    }
}

pub fn viewBox(g: *const game.Game, c: Cam) grid.Box {
    return .{
        .lo = .{ .x = @max(0, @divFloor(c.x, game.CELL)), .y = @max(0, @divFloor(c.y, game.CELL)) },
        .hi = .{
            .x = @min(grid.W, @divFloor(c.x + g.screen.x, game.CELL) + 1),
            .y = @min(grid.H, @divFloor(c.y + g.screen.y, game.CELL) + 1),
        },
    };
}

fn mirrorAt(foot: f32) void {
    rl.gl.rlPushMatrix();
    rl.gl.rlTranslatef(0, 2 * foot, 0);
    rl.gl.rlScalef(1, -1, 1);
}

const Reflection = struct {
    fading: bool,

    fn begin(g: *const game.Game, foot: f32, fade: ?[2]f32) Reflection {
        mirrorAt(foot);
        return .{ .fading = if (fade) |b| g.light.beginMirrorFade(b) else false };
    }

    fn end(r: Reflection) void {
        if (r.fading) rl.endShaderMode();
        rl.gl.rlPopMatrix();
    }
};

/// Where a glyph figure, with no art to measure, stands within its cell.
const GLYPH_FOOT: f32 = 0.8;

fn footOf(g: *const game.Game, tex: ?rl.Texture2D, s: P) f32 {
    const t = tex orelse return @as(f32, @floatFromInt(s.y)) + game.CELL_F * GLYPH_FOOT;
    return g.light.footY(t, spriteRect(t, s.x, s.y));
}

fn drawMirrored(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, stands: P, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32) void {
    const foot = footOf(g, tex, stands);
    const top = if (tex) |t| g.light.topY(t, spriteRect(t, s.x, s.y)) else @as(f32, @floatFromInt(s.y + game.HALF_CELL - @divTrunc(game.GLYPH, 2)));
    const bounds = mirrorFade(g, foot, top, footOf(g, tex, s));
    const r = Reflection.begin(g, foot, if (tex == null) bounds else null);
    defer r.end();
    drawLit(g, tex, l, s, left, mid, shine, flash, bounds);
}

fn mirrorFade(g: *const game.Game, foot: f32, top: f32, bottom: f32) [2]f32 {
    const screen: f32 = @floatFromInt(g.screen.y);
    return .{ screen - 2 * foot + top, screen - 2 * foot + mathx.lerpF(top, bottom, 0.7) };
}

fn drawBody(g: *game.Game, b: *const Shown, mirrored: bool) void {
    const tex = g.sprites.body(b.pic.kind);
    const l = look.body(b.pic.kind);
    const flash = g.fx.flashOf(b.slot);
    var shine = b.shine;
    if (game.isHero(g, b.slot)) shine.emission = g.fx.level_up.bodyGlow();
    if (mirrored) drawMirrored(g, tex, l, b.s, b.lifted, b.left, b.mid, &shine, flash) else drawFigure(g, tex, l, b.lifted, b.left, b.mid, &shine, flash);
}

fn drawBarrel(g: *game.Game, b: *const Prop, mirrored: bool) void {
    if (mirrored) drawMirrored(g, g.sprites.barrel, look.BARREL, b.s, b.s, false, b.mid, &b.shine, 0) else drawFigure(g, g.sprites.barrel, look.BARREL, b.s, false, b.mid, &b.shine, 0);
}

fn drawMirrorScenery(g: *game.Game, c: Cam, view: grid.Box, memory: bool) void {
    var cells = view.grown(game.CAST_MARGIN).cells();
    while (cells.next()) |p| {
        if (!game.character.terrainSeen(g, p)) continue;
        const kind = g.lv.at(p);
        if (look.standsOver(kind)) {
            if (g.sprites.tileAt(&g.lv, p)) |t| {
                const rect = spriteRect(t, c.sx(p), c.sy(p));
                const foot = footOf(g, t, c.corner(p));
                const r = Reflection.begin(g, foot, mirrorFade(g, foot, g.light.topY(t, rect), foot));
                defer r.end();
                const tint = if (memory) rl.Color.white else g.light.onBody(mathx.centre(p), false).tint(rl.Color.white);
                look.stretch(t, rect, tint);
            }
        }
        if (barrelPresent(g, p)) {
            var b = Prop.at(g, c, p, false);
            if (memory) b.shine = .{ .ambient = @splat(1) };
            drawBarrel(g, &b, true);
        }
    }
}

fn drawMirrorTorches(g: *game.Game, c: Cam, flames: []const light.Flame, memory: bool) void {
    for (flames) |f| {
        const foot = f.foot * game.CELL_F - @as(f32, @floatFromInt(c.y));
        const top = f.at[1] * game.CELL_F - @as(f32, @floatFromInt(c.y + game.authored(fx.TORCH_TOP_PX)));
        const r = Reflection.begin(g, foot, mirrorFade(g, foot, top, foot));
        defer r.end();
        drawFlame(g, c, f, if (memory or !g.lv.isLit(mathx.cellOf(f.at))) 0 else flameLit(f));
    }
}

fn flameLit(f: light.Flame) f32 {
    return f.lit * @min(1, f.glow);
}

fn drawFlame(g: *game.Game, c: Cam, f: light.Flame, lit: f32) void {
    const x = mathx.roundTiesUp(f.at[0] * game.CELL_F) - c.x;
    const y = mathx.roundTiesUp(f.at[1] * game.CELL_F) - c.y;
    g.fx.drawTorch(@floatFromInt(x), @floatFromInt(y), game.CELL_F, f.at[0] * 0.73 + f.at[1] * 0.37, lit, f.memory);
}

pub fn drawMirrors(g: *game.Game, c: Cam, view: grid.Box, bodies: []const Shown, flames: []const light.Flame) ?look.Mirrors {
    if (!g.sprites.beginMirror(g.screen, g.framebuffer, true)) return null;
    drawMirrorScenery(g, c, view, true);
    drawMirrorTorches(g, c, flames, true);
    if (!g.sprites.beginMirror(g.screen, g.framebuffer, false)) {
        rl.gl.rlEnableBackfaceCulling();
        return null;
    }
    drawMirrorScenery(g, c, view, false);
    for (bodies) |*b| drawBody(g, b, true);
    drawMirrorTorches(g, c, flames, false);
    return g.sprites.endMirror(g.framebuffer);
}

pub fn drawMap(g: *game.Game) void {
    g.light.composed = g.cinema.options.composed_lighting;
    effectLights(g);
    const c = Cam.of(g);
    const view = viewBox(g, c);
    const lo = view.lo;
    const hi = view.hi;
    const aim_from: ?P = if (g.mode != .aim) null else if (g.heroActor()) |a| a.at else null;

    var shown: [actor.MAX]Shown = undefined;
    const stood = stoodNow(g);
    var n: usize = 0;
    for (0..g.pool.n) |i| {
        const at = game.drawnAt(g, i) orelse continue;
        const mid = game.middle(at);
        shown[n] = .{
            .pic = g.pictured[i],
            .slot = i,
            .s = c.px(at),
            .lifted = c.px(at).sub(.{ .x = 0, .y = g.glide[i].lift() }),
            .mid = mid,
            .left = g.facing[i] == .left,
            .shine = g.light.onBody(mid, game.isHero(g, i)),
        };
        n += 1;
    }
    const bodies = shown[0..n];

    g.light.bake(&g.lv, lo, hi);
    var flame_buf: [grid.MAX_TORCHES]light.Flame = undefined;
    const flames = g.light.flames(&g.lv, &flame_buf);
    g.cinema.prepare(&g.lv, g.light, view, flames);
    const outer = g.framebuffer;
    const blooming = g.cinema.beginScene(g.screen, outer);
    if (blooming) g.framebuffer = g.cinema.scene.?.id;
    var beds: dual.Beds = undefined;
    beds.fill(&g.lv, lo, hi, !g.light.reveal_map);
    const mirror = if (beds.shown.intersectWith(look.REFLECTIVE).count() > 0) drawMirrors(g, c, view, bodies, flames) else null;
    drawGroundPass(g, c, &beds, &stood, mirror);
    for (g.ground.coins[0..g.ground.coin_n]) |pile| {
        if (!g.lv.isLit(pile.at) or barrelPresent(g, pile.at)) continue;
        game.drawGold(g, c, pile.at);
    }
    if (g.gold_taken) |p| {
        const hero = game.heroSlot(g).?;
        if (g.glide[hero].left() > 0 and g.lv.isLit(p)) game.drawGold(g, c, p);
    }
    for (g.ground.drops[0..g.ground.n]) |drop| {
        if (!game.character.dropShown(g, drop)) continue;
        game.drawLoot(g, c, drop.at, look.DROP_MARK, game.DROP_DX, look.itemInk(drop.item.magical()));
    }
    _ = shadowPass(g, c, view, g.framebuffer);
    g.cloud.draw(&g.lv, view, -c.x, -c.y, game.CELL, g.screen);
    drawSolidPass(g, c, lo, hi, &stood);
    const o = c.origin();
    g.fx.draw(o[0], o[1], game.CELL_F);
    g.light.drawMap(-c.x, -c.y, game.CELL);
    g.cinema.drawAir(g.light, o, game.CELL_F, g.screen);
    const level_up_at: ?[2]f32 = if (game.heroSlot(g)) |i| (if (game.drawnAt(g, i)) |v| game.middle(v) else null) else null;
    if (level_up_at) |at| g.fx.level_up.drawBeam(at, o[0], o[1], game.CELL_F);

    if (aim_from) |from| {
        var cells = grid.Cells.of(lo, hi);
        while (cells.next()) |p| {
            if (game.aimable(g, from, p)) fillCell(c, p, look.AIM_REACH);
        }
        if (g.aim_act.reticle() == .bow) {
            const f = bow.fly(&g.lv, from, g.mark);
            for (f.path[0..f.len]) |p| fillCell(c, p, look.AIM_PATH);
            switch (g.aim_act) {
                inline else => |a| if (comptime a.bursts()) if (f.impact()) |at| {
                    const area = skillbar.Act.elemental(a).burst(&g.lv, from, at);
                    for (area.slice()) |p| {
                        if (game.character.terrainSeen(g, p)) fillCell(c, p, look.aimArea(a));
                    }
                },
            }
        }
        switch (g.aim_act) {
            inline else => |a| if (comptime a.sweeps()) {
                const arc = skillbar.Act.skill(a).arc(&g.lv, from, g.mark);
                for (arc.slice()) |p| fillCell(c, p, look.AIM_PATH);
            },
        }
    }

    var barrels = Barrels.of(g, c, lo, hi);
    while (barrels.next()) |b| drawBarrel(g, &b, false);
    for (bodies) |*b| {
        const at = b.lifted;
        drawBody(g, b, false);
        const x: f32 = @floatFromInt(at.x);
        const y: f32 = @floatFromInt(at.y);
        for (std.enums.values(fx.Status)) |s| {
            if (b.pic.status.get(s) == 0) continue;
            switch (s) {
                .bleeding => g.fx.drawBleeding(x, y, game.CELL_F, b.slot, b.shine.tint(s.ink())),
                .burning => g.fx.drawBurning(x, y, game.CELL_F, b.slot, b.shine.sight),
                .chilled => g.fx.drawChilled(x, y, game.CELL_F, b.slot, b.shine.tint(s.ink())),
                .pinned => g.fx.drawPinned(x, y, game.CELL_F, b.shine.tint(s.ink())),
                .warded => g.fx.drawWarded(x, y, game.CELL_F, b.shine.tint(s.ink())),
            }
        }
    }

    drawTorches(g, c, flames);
    g.fx.drawGlow(&g.lv, &g.light.sight, o[0], o[1], game.CELL_F);
    if (level_up_at) |at| g.fx.level_up.drawSparks(at, o[0], o[1], game.CELL_F);
    if (g.light.sky) |k| g.rain.draw(game.weatherNow(g), &g.light.sight, o[0], o[1], game.CELL_F, game.PX_SCALE, sky.brightness(k));

    if (g.shot) |s| {
        const at = s.position(s.t);
        if (g.lv.isLit(mathx.cellOf(at))) fx.drawMissile(at, s.direction(), s.act, s.t, o[0], o[1], game.CELL_F);
    }
    if (blooming) {
        g.cinema.endScene(outer, o, game.CELL_F, g.light);
        g.framebuffer = outer;
    }

    for (bodies) |*b| {
        if (!b.pic.kind.foe() or !b.pic.hurt()) continue;
        const y_bar = b.s.y + game.CELL - game.BODY_BAR_H - game.BODY_BAR_LIFT;
        bar(b.s.x + game.BODY_BAR_INSET, y_bar, game.CELL - game.BODY_BAR_INSET * 2, game.BODY_BAR_H, b.pic.hp, b.pic.max, look.BG, look.LIFE);
    }

    if (aim_from) |from| outline(c, g.mark, if (game.aimable(g, from, g.mark)) look.RETICLE else look.RETICLE_BLOCKED);
    if (game.playShown(g) and g.st.lean) drawLean(g, c, &stood);

    for (bodies) |*b| {
        g.fx.drawSpeech(&g.face, b.slot, b.lifted.x, b.lifted.y, game.CELL_F, b.shine.sight);
    }
    if (level_up_at) |at| g.fx.level_up.drawText(at, &g.face, o[0], o[1], game.CELL_F);
}

pub fn effectLights(g: *game.Game) void {
    g.fx.illuminate(&g.lv, g.light);
    if (game.carrierAt(g)) |at| {
        if (g.fx.level_up.emission(at)) |source| g.light.emit(&g.lv, source);
    }
    if (g.shot) |s| {
        if (fx.missileLight(s.position(s.t), s.act)) |source| g.light.emit(&g.lv, source);
    }
    for (0..g.pool.n) |i| {
        const at = game.drawnAt(g, i) orelse continue;
        const pic = g.pictured[i];
        if (pic.down()) continue;
        const flicker = g.fx.statusFlicker(@floatFromInt(i));
        const source = for (std.enums.values(fx.Status)) |s| {
            if (pic.status.get(s) > 0) if (s.emission(game.middle(at), flicker)) |e| break e;
        } else continue;
        g.light.emit(&g.lv, source);
    }
}

/// Over the light map, so each flame is its own light; a remembered one stays drawn, dim and unlit.
fn drawTorches(g: *game.Game, c: Cam, flames: []const light.Flame) void {
    for (flames) |f| drawFlame(g, c, f, flameLit(f));
    const o = c.origin();
    g.light.drawGlows(flames, o[0], o[1], game.CELL_F);
}

/// Movement hints follow presented occupants, including deaths still being drawn.
pub fn leanShown(g: *game.Game, stood: *const Stood, from: P, d: mathx.Dir) game.Move {
    return game.moveOf(g, from, d, shownAt(g, stood, from.add(d.delta())));
}

fn drawLean(g: *game.Game, c: Cam, stood: *const Stood) void {
    const at = game.cellUnder(game.heroNow(g) orelse return);
    for (input.DPAD) |button| {
        const d = input.leanOf(button);
        const p = at.add(d.delta());
        const col = switch (leanShown(g, stood, at, d)) {
            .kick => look.LEAN_FOE,
            .step, .open => look.LEAN_OPEN,
            .blocked => look.LEAN_BLOCKED,
        };
        outline(c, p, col);
        if (g.lv.walkable(p) and !shownAt(g, stood, p)) {
            const m = c.mid(p);
            look.drawDirection(button, m.x, m.y, game.LEAN_GLYPH, col);
            continue;
        }
        const inset = game.LEAN_PAD + @divTrunc(game.LEAN_MARK, 2);
        const dx: i32 = if (d.delta().x > 0) game.CELL - inset else inset;
        const dy: i32 = if (d.delta().y > 0) game.CELL - inset else inset;
        look.drawDirection(button, c.sx(p) + dx, c.sy(p) + dy, game.LEAN_MARK, col);
    }
}

/// One texel per cell, enlarged by `MINI`; requires a live GL context.
pub const Minimap = struct {
    tex: ?rl.Texture2D = null,
    px: [grid.CELLS]rl.Color = undefined,
    /// Set by `castSight` and `toggleReveal`, the only changes to what it shows.
    stale: bool = true,

    pub fn load(m: *Minimap) void {
        m.tex = look.canvas(grid.W, grid.H, rl.Color.blank, .point);
        m.stale = true;
    }

    pub fn unload(m: *Minimap) void {
        look.unloadAll(m);
    }
};

pub fn miniOrigin(screen_w: i32) P {
    return .{ .x = screen_w - game.MINI_W - game.MINI_PAD - game.MINI_FRAME, .y = game.MINI_PAD + game.MINI_FRAME };
}

fn miniDot(o: P, p: P, grow: i32, col: rl.Color) void {
    rl.drawRectangleRec(look.grown(look.rect(o.x + p.x * game.MINI, o.y + p.y * game.MINI, game.MINI, game.MINI), @floatFromInt(grow)), col);
}

pub fn drawMinimap(g: *game.Game) void {
    const o = miniOrigin(g.screen.x);
    const map = miniBox(g.screen.x);
    look.hudPanelIn(&g.sprites, miniFrame(g.screen.x), look.MINI_BG, look.LIT);
    if (g.mini.tex) |t| {
        if (g.mini.stale) {
            for (&g.mini.px, &g.lv.tile, &g.lv.seen, &g.lv.lit) |*c, tile, seen, lit| c.* = if (seen or g.light.reveal_map) look.mini(tile, lit) else rl.Color.blank;
            rl.updateTexture(t, &g.mini.px);
            g.mini.stale = false;
        }
        look.stretch(t, map, look.LIT);
    }
    for (g.pool.slice(), 0..) |a, i| {
        if (!a.foe()) continue;
        miniDot(o, game.drawnCell(g, i) orelse continue, 0, look.MINI_FOE);
    }
    if (game.heroNow(g)) |at| miniDot(o, game.cellUnder(at), game.MINI_HERO_GROW, look.MINI_HERO);
    const v = miniView(Cam.of(g), g.screen);
    rl.drawRectangleLines(o.x + v.lo.x, o.y + v.lo.y, v.hi.x - v.lo.x, v.hi.y - v.lo.y, look.MINI_VIEW);
}

fn miniBox(screen_w: i32) rl.Rectangle {
    const o = miniOrigin(screen_w);
    return look.rect(o.x, o.y, game.MINI_W, game.MINI_H);
}

pub fn miniFrame(screen_w: i32) rl.Rectangle {
    return look.grown(miniBox(screen_w), @floatFromInt(game.MINI_FRAME));
}

pub fn dayLine(screen_w: i32) struct { x0: i32, x1: i32, y: i32 } {
    const m = miniOrigin(screen_w);
    const f = miniFrame(screen_w);
    return .{ .x0 = m.x + game.DAY_INSET, .x1 = m.x + game.MINI_W - game.DAY_INSET, .y = @as(i32, @intFromFloat(f.y + f.height)) + game.DAY_GAP };
}

pub fn drawDayNight(g: *game.Game) void {
    const l = dayLine(g.screen.x);
    const now = day.arc(g.hour_shown);
    const at = rl.Vector2{
        .x = @round(mathx.lerpF(@floatFromInt(l.x0), @floatFromInt(l.x1), now.u)),
        .y = @floatFromInt(l.y),
    };
    const left: i32 = @intFromFloat(at.x - game.DAY_CLEAR);
    const right: i32 = @intFromFloat(at.x + game.DAY_CLEAR);
    for ([_]bool{ true, false }) |shadow| {
        const by: i32 = if (shadow) game.DAY_DROP else 0;
        const line = if (shadow) look.DAY_SHADOW else look.DAY_PATH;
        const clear = look.fade(line, 0);
        if (left > l.x0) rl.drawRectangleGradientH(l.x0 + by, l.y + by, left - l.x0, 1, clear, line);
        if (right < l.x1) rl.drawRectangleGradientH(right + by, l.y + by, l.x1 - right, 1, line, clear);
        const p = at.add(.{ .x = @floatFromInt(by), .y = @floatFromInt(by) });
        const ink = if (shadow) look.DAY_SHADOW else if (now.day) look.DAY_SUN else look.DAY_MOON;
        if (now.day) sunGlyph(p, ink) else moonGlyph(p, ink);
    }
}

fn sunGlyph(at: rl.Vector2, col: rl.Color) void {
    rl.drawCircleV(at, game.SUN_R, col);
    for (0..game.SUN_RAYS) |i| {
        const a = mathx.TAU * @as(f32, @floatFromInt(i)) / game.SUN_RAYS;
        const d = rl.Vector2{ .x = @cos(a), .y = @sin(a) };
        rl.drawLineEx(at.add(d.scale(game.SUN_RAY_IN)), at.add(d.scale(game.SUN_RAY_OUT)), 1, col);
    }
}

fn moonGlyph(at: rl.Vector2, col: rl.Color) void {
    const cut_r = game.MOON_R - game.MOON_CUT_INSET;
    var y: f32 = -game.MOON_R + 0.5;
    while (y < game.MOON_R) : (y += 1) {
        const half = @sqrt(game.MOON_R * game.MOON_R - y * y);
        const right = if (@abs(y) < cut_r) @min(half, game.MOON_CUT - @sqrt(cut_r * cut_r - y * y)) else half;
        if (right <= -half) continue;
        rl.drawRectangleRec(.{ .x = @round(at.x - half), .y = at.y + y - 0.5, .width = @round(right + half), .height = 1 }, col);
    }
}

fn miniView(c: Cam, screen: P) grid.Box {
    return .{
        .lo = .{ .x = @max(0, toMini(c.x)), .y = @max(0, toMini(c.y)) },
        .hi = .{ .x = @min(game.MINI_W, toMini(c.x + screen.x)), .y = @min(game.MINI_H, toMini(c.y + screen.y)) },
    };
}

fn toMini(px: i32) i32 {
    return @divTrunc(px * game.MINI, game.CELL);
}
