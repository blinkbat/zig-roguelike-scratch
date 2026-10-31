const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const skillbar = @import("../play/skillbar.zig");
const glacial = @import("../play/glacial.zig");
const rules = @import("../play/tactics.zig");
const tactics = @import("tactics.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const line_icons = @import("../gfx/line_icons.zig");
const dual = @import("../gfx/ground.zig");
const light = @import("../gfx/light.zig");
const fx = @import("../gfx/fx.zig");
const items = @import("../play/items.zig");
const cloud = @import("../gfx/cloud.zig");
const sky = @import("../gfx/sky.zig");
const day = @import("../map/day.zig");
const shaders = @import("../gfx/shaders.zig");
const hud = @import("../ui/hud.zig");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const P = mathx.P;

const LEAN_GLYPH: i32 = game.authored(40);
const LEAN_MARK: i32 = game.authored(30);
const LEAN_PAD: i32 = game.authored(4);
const OUTLINE_INSET: i32 = game.authored(1);
const BODY_BAR_INSET: i32 = game.authored(6);
const BODY_BAR_H: i32 = game.authored(4);
const BODY_BAR_LIFT: i32 = game.authored(2);
const RESIST_BAR_H: i32 = game.authored(2);
const RESIST_BAR_GAP: i32 = game.authored(2);
const CHILL_BAR_H: i32 = game.authored(3);
const CHILL_BAR_GAP: i32 = game.authored(2);
const CHILL_PIP_GAP: i32 = game.authored(2);
const FLAME_FILL_A: f32 = 0.18;
const BARRIER_FILL_A: f32 = 0.28;
const BARRIER_INSET: i32 = game.authored(5);
/// Each caltrop's middle, in authored cell pixels: a point above it, a foot either side below.
const CALTROPS = [_]P{ .{ .x = 12, .y = 20 }, .{ .x = 29, .y = 32 }, .{ .x = 42, .y = 17 } };
const CALTROP_HALF: i32 = game.authored(4);
const CALTROP_UP: i32 = game.authored(5);
const CALTROP_DOWN: i32 = game.authored(3);
const FLAME_LIGHT_R: f32 = 1.6;
const FLAME_LIGHT_GAIN: f32 = 0.45;
const MINI: i32 = 3;
const MINI_W: i32 = grid.W * MINI;
const MINI_H: i32 = grid.H * MINI;
const MINI_PAD: i32 = hud.EDGE;
const MINI_FRAME: i32 = look.HUD_BORDER_CUT;
const MINI_HERO_GROW: i32 = 1;
const DAY_GAP: i32 = 12;
const DAY_INSET: i32 = 16;
/// Either side of the glyph's middle, the line stays clear of it.
const DAY_CLEAR: f32 = DAY_GLYPH_R + 3;
pub const DAY_DROP: i32 = 1;
const SUN_R: f32 = 3;
const SUN_RAY_IN: f32 = 5;
const SUN_RAY_OUT: f32 = 7;
const SUN_RAYS: usize = 8;
const MOON_R: f32 = 5;
const MOON_CUT: f32 = 2.5;
const MOON_CUT_INSET: f32 = 0.6;
pub const DAY_GLYPH_R: f32 = @max(SUN_RAY_OUT, MOON_R);
/// Of a reflection's height from its top, where its fade to nothing ends.
const MIRROR_FADE: f32 = 0.7;
const FLAME_PHASE = [2]f32{ 0.73, 0.37 };

pub const Cam = struct {
    x: i32,
    y: i32,
    at: rl.Vector2,

    pub fn of(g: *const game.Game) Cam {
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

    pub fn cellAt(c: Cam, s: P) P {
        return .{ .x = @divFloor(s.x + c.x, game.CELL), .y = @divFloor(s.y + c.y, game.CELL) };
    }

    pub fn box(c: Cam, p: P) rl.Rectangle {
        return raster.rect(c.sx(p), c.sy(p), game.CELL, game.CELL);
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
    return raster.rect(sx + @divTrunc(game.CELL - t.width * k, 2), sy + @divTrunc(game.CELL - t.height * k, 2), t.width * k, t.height * k);
}

fn drawSprite(t: rl.Texture2D, sx: i32, sy: i32) void {
    raster.stretch(t, spriteRect(t, sx, sy), look.LIT);
}

fn tileRect(kind: grid.Tile, tex: rl.Texture2D, c: Cam, p: P) rl.Rectangle {
    return look.tileRect(kind, tex, c.box(p));
}

/// `t` on `p`, catching its shine as the band crosses it.
fn drawShining(g: *const game.Game, t: rl.Texture2D, c: Cam, p: P, dx: i32) void {
    const rect = spriteRect(t, c.sx(p) + dx, c.sy(p));
    raster.stretch(t, rect, look.LIT);
    shineOver(g, t, rect, p, look.LIT);
}

/// Only what the hero sees shines; remembered loot stays still.
fn shineOver(g: *const game.Game, t: rl.Texture2D, rect: rl.Rectangle, p: P, col: rl.Color) void {
    if (!g.pic.litShown(&g.sim, p)) return;
    const sweep = look.shineSweep(g.pic.fx.seconds.at(), p) orelse return;
    g.sprites.drawShine(t, rect, sweep, col);
}

fn drawGlyph(g: *game.Game, ch: u8, sx: i32, sy: i32, col: rl.Color) void {
    g.face.glyph(ch, sx + game.HALF_CELL, sy + game.HALF_CELL, game.GLYPH, col);
}

/// A figure with no art: its letter cell-high, doubled a pixel over for weight.
fn drawFigureGlyph(g: *game.Game, ch: u8, sx: i32, sy: i32, col: rl.Color) void {
    for ([_]i32{ 0, game.authored(1) }) |dx| g.face.glyph(ch, sx + dx + game.HALF_CELL, sy + game.HALF_CELL, game.CELL, col);
}

/// Bright whatever the light, over a drop shadow, so a stand-in letter reads at a glance.
fn drawFigureLetter(g: *game.Game, l: look.Look, s: P, flash: f32) void {
    const off = game.authored(look.GLYPH_SHADOW_PX);
    drawFigureGlyph(g, l.ch, s.x + off, s.y + off, look.GLYPH_SHADOW);
    drawFigureGlyph(g, l.ch, s.x, s.y, look.mixed(l.fg, rl.Color.white, flash));
}

fn drawCoins(g: *const game.Game, c: Cam, pile: items.Coins) void {
    const tex = if (pile.large()) g.sprites.large_coins else g.sprites.small_coins;
    if (tex) |t| {
        drawShining(g, t, c, pile.at, 0);
    } else {
        const m = c.mid(pile.at);
        g.face.centred("$", m.x, m.y, game.GLYPH, look.UI_GOLD);
    }
}

fn bagged(bags: *const grid.CellSet, p: P) bool {
    return bags.isSet(grid.Level.idx(p));
}

/// A bag on open ground, drawn as its own sprite; one in an open chest is drawn as the chest's.
fn looseBag(here: grid.Tile, bags: *const grid.CellSet, p: P) bool {
    return here != .chest_open and bagged(bags, p);
}

fn chestShines(here: grid.Tile, p: P, bags: *const grid.CellSet) bool {
    return here == .chest or (here == .chest_open and bagged(bags, p));
}

fn outline(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleLinesEx(raster.grown(c.box(p), @floatFromInt(-OUTLINE_INSET)), @floatFromInt(game.LINE_W), col);
}

fn fillCell(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleRec(c.box(p), col);
}

/// Barrels stay remembered until the hero's visible breaking blow lands, or until it sees them gone.
pub fn barrelShownAt(g: *game.Game, p: P) bool {
    if (!game.character.terrainSeen(g, p)) return false;
    if (g.pic.litShown(&g.sim, p) or !g.sim.lv.isSeen(p)) return barrelPresent(g, p);
    return g.sim.lv.barrelSeen(p);
}

pub fn barrelPresent(g: *const game.Game, p: P) bool {
    return g.sim.lv.hasBarrel(p) or g.pic.fx.breaking(p);
}

pub fn shownAt(g: *game.Game, stood: *const grid.CellSet, p: P) bool {
    return (grid.Level.inside(p) and stood.isSet(grid.Level.idx(p))) or barrelShownAt(g, p);
}

pub fn stoodNow(g: *game.Game) grid.CellSet {
    var stood = grid.CellSet.initEmpty();
    for (0..g.sim.pool.n) |i| stand(&stood, g.pic.drawnCell(&g.sim, i) orelse continue);
    return stood;
}

fn stand(stood: *grid.CellSet, under: P) void {
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
    } else drawFigureLetter(g, l, s, flash);
}

fn drawFigure(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32) void {
    drawLit(g, tex, l, s, left, mid, shine, flash, .{ 0, 0 });
    if (!g.cloud.beginVeil(shine.tint(rl.Color.white), .sharp)) return;
    defer cloud.Cloud.endVeil();
    if (tex) |t| {
        raster.blit(t, raster.rect(0, 0, if (left) -t.width else t.width, t.height), spriteRect(t, s.x, s.y), rl.Color.white);
    } else drawFigureGlyph(g, l.ch, s.x, s.y, rl.Color.white);
}

fn drawGroundPass(g: *game.Game, c: Cam, beds: *const dual.Beds, stood: *const grid.CellSet, mirror: ?look.Mirrors) void {
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
        .shimmer = g.light.options.water_glints,
        .seconds = g.light.t.at(),
    } else null else null;
    g.sprites.drawGround(&g.sim.lv, beds, c.origin(), game.CELL_F, water);
    var cells = grid.Cells.of(beds.lo, beds.hi);
    while (cells.next()) |p| {
        if (!game.character.terrainSeen(g, p)) continue;
        const here = g.sim.lv.at(p);
        if (look.glyphGround(here, &g.sprites)) inkCell(g, c, p, here, stood);
        if (g.sim.lv.doorAt(p) != null) drawGlyph(g, look.DOOR.ch, c.sx(p), c.sy(p), look.DOOR.fg);
    }
}

pub fn bagCells(g: *const game.Game) grid.CellSet {
    var bags = grid.CellSet.initEmpty();
    inline for (g.sim.ground.laid()) |laid| for (laid) |l| {
        const remembered = g.sim.lv.at(l.at) == .chest_open and game.character.laidDown(g, l);
        if (remembered or game.character.laidShown(g, l)) bags.set(grid.Level.idx(l.at));
    };
    for (g.sim.ground.coins[0..g.sim.ground.coin_n]) |pile| {
        if (g.sim.lv.at(pile.at) == .chest_open and pileLanded(g, pile) != null) bags.set(grid.Level.idx(pile.at));
    }
    return bags;
}

pub fn pileShown(g: *const game.Game, pile: items.Coins) ?items.Coins {
    if (!g.pic.litShown(&g.sim, pile.at) or barrelPresent(g, pile.at)) return null;
    return pileLanded(g, pile);
}

fn pileLanded(g: *const game.Game, pile: items.Coins) ?items.Coins {
    var shown = pile;
    for (g.sim.pool.constSlice(), 0..) |a, i| {
        if (!a.alive and a.at.eq(pile.at) and !g.pic.pictured[i].down()) shown.amount -= g.pic.dropped_gold[i];
    }
    return if (shown.amount > 0) shown else null;
}

/// `here` is `tileShown` at `p`.
fn tileTexture(g: *const game.Game, here: grid.Tile, p: P, bags: *const grid.CellSet) ?rl.Texture2D {
    if (here == .chest_open and bagged(bags, p)) return g.sprites.chest_item_bag;
    if (here == .chest and g.pic.mimicAt(&g.sim, p)) return g.sprites.mimic_closed;
    if (here != g.sim.lv.at(p)) return g.sprites.tileOf(here, null);
    return g.sprites.tileAt(&g.sim.lv, p);
}

/// At full light, what stands on the seen cells from `lo` up to `hi`, over the shadows cast on the ground.
fn drawSolidPass(g: *game.Game, c: Cam, lo: P, hi: P, stood: *const grid.CellSet) void {
    const bags = bagCells(g);
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (!game.character.terrainSeen(g, p)) continue;
        const here = g.pic.tileShown(&g.sim, p);
        defer if (looseBag(here, &bags, p)) {
            if (g.sprites.item_bag) |t| {
                drawShining(g, t, c, p, 0);
                veilSprite(g, t, c, p, .sharp);
            }
        };
        if (look.occludes(here)) continue;
        if (!look.standsOver(here)) continue;
        if (tileTexture(g, here, p, &bags)) |t| {
            const focus = g.cinema.beginFocus(here, t, mathx.centre(p), g.light.carrier);
            drawSprite(t, c.sx(p), c.sy(p));
            if (focus != null) rl.endShaderMode();
            if (chestShines(here, p, &bags)) shineOver(g, t, spriteRect(t, c.sx(p), c.sy(p)), p, look.LIT);
            if (look.veiled(here)) veilSprite(g, t, c, p, focus orelse .sharp);
            continue;
        }
        if (look.tileBg(here)) |bg| fillCell(c, p, bg);
        inkCell(g, c, p, here, stood);
        if (look.veiled(here) and g.cloud.beginVeil(rl.Color.white, .sharp)) {
            inkCell(g, c, p, here, stood);
            cloud.Cloud.endVeil();
        }
    }
}

fn veilSprite(g: *game.Game, t: rl.Texture2D, c: Cam, p: P, focus: look.Focused) void {
    if (!g.cloud.beginVeil(rl.Color.white, focus)) return;
    drawSprite(t, c.sx(p), c.sy(p));
    cloud.Cloud.endVeil();
}

fn inkCell(g: *game.Game, c: Cam, p: P, here: grid.Tile, stood: *const grid.CellSet) void {
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
    const bags = bagCells(g);
    var props = cast.cells();
    while (props.next()) |p| {
        const kind = g.pic.tileShown(&g.sim, p);
        if (looseBag(kind, &bags, p)) propShadow(g, c, p, g.sprites.item_bag);
        if (barrelPresent(g, p)) propShadow(g, c, p, g.sprites.barrel);
        if (!look.castsPicture(kind)) continue;
        const forest = look.forestAt(&g.sim.lv, p);
        const t = tileTexture(g, kind, p, &bags) orelse continue;
        const pr = Prop.at(g, c, p, true);
        const rect = tileRect(kind, t, c, p);
        if (forest) {
            g.light.drawForestShadows(t, rect, pr.mid, &pr.shine, g.sim.lv.tileShape(p) orelse .{});
        } else if (look.canopied(kind)) {
            g.light.drawCanopy(t, rect, pr.mid, &pr.shine);
        } else g.light.drawShadows(t, rect, false, pr.mid, &pr.shine);
    }
    for (0..g.sim.pool.n) |i| {
        const at = g.pic.casterAt(&g.sim, i, cast) orelse continue;
        const t = g.sprites.body(g.pic.pictured[i].kind) orelse continue;
        const s = c.px(at);
        const mid = game.middle(at);
        const shine = g.light.onCaster(mid, g.sim.isHero(i));
        g.light.drawShadows(t, spriteRect(t, s.x, s.y), g.pic.facing[i] == .left, mid, &shine);
    }
}

fn propShadow(g: *game.Game, c: Cam, p: P, tex: ?rl.Texture2D) void {
    const t = tex orelse return;
    const b = Prop.at(g, c, p, true);
    g.light.drawShadows(t, spriteRect(t, b.s.x, b.s.y), false, b.mid, &b.shine);
}

pub fn viewBox(g: *const game.Game, c: Cam) grid.Box {
    const lo = c.cellAt(.{ .x = 0, .y = 0 });
    const hi = c.cellAt(g.screen);
    return .{
        .lo = .{ .x = @max(0, lo.x), .y = @max(0, lo.y) },
        .hi = .{ .x = @min(grid.W, hi.x + 1), .y = @min(grid.H, hi.y + 1) },
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
    return .{ screen - 2 * foot + top, screen - 2 * foot + mathx.lerpF(top, bottom, MIRROR_FADE) };
}

fn drawBody(g: *game.Game, b: *const Shown, mirrored: bool) void {
    const tex = g.sprites.body(b.pic.kind);
    const l = look.body(b.pic.kind);
    const flash = g.pic.fx.flashOf(b.slot);
    var shine = b.shine;
    if (g.sim.isHero(b.slot)) shine.emission = g.pic.fx.level_up.bodyGlow();
    if (mirrored) drawMirrored(g, tex, l, b.s, b.lifted, b.left, b.mid, &shine, flash) else drawFigure(g, tex, l, b.lifted, b.left, b.mid, &shine, flash);
}

fn drawBarrel(g: *game.Game, b: *const Prop, mirrored: bool) void {
    if (mirrored) drawMirrored(g, g.sprites.barrel, look.BARREL, b.s, b.s, false, b.mid, &b.shine, 0) else drawFigure(g, g.sprites.barrel, look.BARREL, b.s, false, b.mid, &b.shine, 0);
}

fn sceneryTint(g: *const game.Game, p: P) rl.Color {
    return g.light.onBody(mathx.centre(p), false).tint(rl.Color.white);
}

fn mirrorSprite(g: *const game.Game, c: Cam, p: P, kind: grid.Tile, t: rl.Texture2D, tint: rl.Color) void {
    const rect = tileRect(kind, t, c, p);
    const foot = g.light.footY(t, rect);
    const r = Reflection.begin(g, foot, mirrorFade(g, foot, g.light.topY(t, rect), foot));
    defer r.end();
    raster.stretch(t, rect, tint);
}

fn drawMirrorScenery(g: *game.Game, c: Cam, view: grid.Box, memory: bool) void {
    const bags = bagCells(g);
    var cells = view.grown(game.CAST_MARGIN).cells();
    while (cells.next()) |p| {
        if (!game.character.terrainSeen(g, p)) continue;
        const kind = g.pic.tileShown(&g.sim, p);
        if (look.standsOver(kind)) {
            if (tileTexture(g, kind, p, &bags)) |t| mirrorSprite(g, c, p, kind, t, if (memory) rl.Color.white else sceneryTint(g, p));
        }
        if (!memory and looseBag(kind, &bags, p)) {
            if (g.sprites.item_bag) |t| mirrorSprite(g, c, p, kind, t, sceneryTint(g, p));
        }
        if (barrelShownAt(g, p)) {
            var b = Prop.at(g, c, p, false);
            if (memory) b.shine = .{ .ambient = @splat(1) };
            drawBarrel(g, &b, true);
        }
    }
}

fn drawMirrorTorches(g: *game.Game, c: Cam, flames: []const light.Flame, memory: bool) void {
    for (flames) |f| {
        if (f.kind != .wall) continue;
        const foot = f.foot * game.CELL_F - @as(f32, @floatFromInt(c.y));
        const top = f.at[1] * game.CELL_F - @as(f32, @floatFromInt(c.y + game.authored(fx.TORCH_TOP_PX)));
        const r = Reflection.begin(g, foot, mirrorFade(g, foot, top, foot));
        defer r.end();
        drawFlame(g, c, f, if (memory or !g.pic.litShown(&g.sim, mathx.cellOf(f.at))) 0 else flameLit(f));
    }
}

fn flameLit(f: light.Flame) f32 {
    return f.lit * @min(1, f.glow);
}

fn drawFlame(g: *game.Game, c: Cam, f: light.Flame, lit: f32) void {
    const x = mathx.roundTiesUp(f.at[0] * game.CELL_F) - c.x;
    const y = mathx.roundTiesUp(f.at[1] * game.CELL_F) - c.y;
    g.pic.fx.drawTorch(@floatFromInt(x), @floatFromInt(y), game.CELL_F, f.at[0] * FLAME_PHASE[0] + f.at[1] * FLAME_PHASE[1], lit, f.memory);
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
    const aim_from: ?P = if (g.mode != .aim) null else if (g.sim.heroActor()) |a| a.at else null;

    var shown: [actor.MAX]Shown = undefined;
    const stood = stoodNow(g);
    var n: usize = 0;
    for (0..g.sim.pool.n) |i| {
        const at = g.pic.drawnAt(&g.sim, i) orelse continue;
        const mid = game.middle(at);
        shown[n] = .{
            .pic = g.pic.pictured[i],
            .slot = i,
            .s = c.px(at),
            .lifted = c.px(at).sub(.{ .x = 0, .y = g.pic.glide[i].lift() }),
            .mid = mid,
            .left = g.pic.facing[i] == .left,
            .shine = g.light.onBody(mid, g.sim.isHero(i)),
        };
        n += 1;
    }
    const bodies = shown[0..n];

    g.light.bake(&g.sim.lv, lo, hi);
    var flame_buf: [light.LIGHTS]light.Flame = undefined;
    const flames = g.light.flames(&g.sim.lv, &flame_buf);
    g.cinema.prepare(&g.sim.lv, g.light, view, flames);
    const outer = g.framebuffer;
    const blooming = g.cinema.beginScene(g.screen, outer);
    if (blooming) g.framebuffer = g.cinema.scene.?.id;
    var beds: dual.Beds = undefined;
    beds.fill(&g.sim.lv, lo, hi, !g.light.reveal_map);
    const mirror = if (g.debug.visuals.water_reflections and beds.shown.intersectWith(look.REFLECTIVE).count() > 0) drawMirrors(g, c, view, bodies, flames) else null;
    drawGroundPass(g, c, &beds, &stood, mirror);
    const bags = bagCells(g);
    for (g.sim.ground.coins[0..g.sim.ground.coin_n]) |pile| {
        if (g.sim.lv.at(pile.at).isChest() or bagged(&bags, pile.at)) continue;
        if (pileShown(g, pile)) |shown_pile| drawCoins(g, c, shown_pile);
    }
    if (g.pic.gold_taken) |pile| {
        if (g.sim.heroSlot()) |hero| {
            if (g.pic.glide[hero].left() > 0 and g.pic.litShown(&g.sim, pile.at)) drawCoins(g, c, pile);
        }
    }
    _ = shadowPass(g, c, view, g.framebuffer);
    g.cloud.draw(&g.sim.lv, view, -c.x, -c.y, game.CELL, g.screen);
    drawSolidPass(g, c, lo, hi, &stood);
    const o = c.origin();
    g.pic.fx.draw(o[0], o[1], game.CELL_F);
    g.light.drawMap(-c.x, -c.y, game.CELL);
    g.cinema.drawAir(g.light, o, game.CELL_F, g.screen);
    drawTacticalGround(g, c, lo, hi);
    const level_up_at: ?[2]f32 = if (g.sim.heroSlot()) |i| (if (g.pic.drawnAt(&g.sim, i)) |v| game.middle(v) else null) else null;
    if (level_up_at) |at| g.pic.fx.level_up.drawBeam(at, o[0], o[1], game.CELL_F);

    if (aim_from) |from| {
        var cells = grid.Cells.of(lo, hi);
        while (cells.next()) |p| {
            if (g.sim.lv.isLit(p) and skills.aimable(g, from, p)) fillCell(c, p, look.AIM_REACH);
        }
        if (g.mode.aim.act().reticle() == .bow and skills.aimable(g, from, g.mode.aim.mark)) {
            const f = skills.shownFlight(g, from, g.mode.aim.act(), g.mode.aim.mark);
            for (f.path[0..f.len]) |p| if (g.sim.lv.isLit(p)) {
                fillCell(c, p, look.AIM_PATH);
            };
            switch (g.mode.aim.act()) {
                inline else => |a| if (comptime a.bursts()) if (f.impact()) |at| {
                    if (g.sim.lv.isLit(at)) {
                        const area = skillbar.Act.elemental(a).burst(&g.sim.lv, from, at);
                        for (area.slice()) |p| {
                            if (g.sim.lv.isLit(p)) fillCell(c, p, look.aimArea(a));
                        }
                    }
                },
            }
        }
        switch (g.mode.aim.act()) {
            .arcane_barrier, .fire_wall => |a| if (tactics.span(g, a, from, g.mode.aim.anchor() orelse g.mode.aim.mark, g.mode.aim.mark)) |area| {
                for (area.slice()) |p| fillCell(c, p, if (a == .fire_wall) look.aimElement(.fire) else look.AIM_PATH);
            },
            .overwatch => if (mathx.toward(from, g.mode.aim.mark)) |d| {
                var covered = grid.Cells.around(from, bow.RANGE);
                while (covered.next()) |p| {
                    if (g.sim.lv.isLit(p) and rules.covered(from, d, p) and bow.aimable(&g.sim.lv, from, p)) fillCell(c, p, look.AIM_PATH);
                }
            },
            inline else => |a| if (comptime a.sweeps()) {
                const arc = skillbar.Act.skill(a).arc(&g.sim.lv, from, g.mode.aim.mark);
                for (arc.slice()) |p| fillCell(c, p, look.AIM_PATH);
            } else if (comptime a.reticle() == .ground and @hasDecl(skillbar.Act.skill(a), "area")) {
                const area = skillbar.Act.skill(a).area(&g.sim.lv, g.mode.aim.mark);
                if (skills.aimable(g, from, g.mode.aim.mark)) for (area.slice()) |p| {
                    if (g.sim.lv.isLit(p)) fillCell(c, p, look.AIM_PATH);
                };
            },
        }
    }

    drawPlants(g, c, flames);
    var barrels = Barrels.of(g, c, lo, hi);
    while (barrels.next()) |b| {
        drawBarrel(g, &b, false);
        if (g.sprites.barrel) |t| shineOver(g, t, spriteRect(t, b.s.x, b.s.y), mathx.cellOf(b.mid), b.shine.tint(rl.Color.white));
    }
    var folk_cells = grid.Cells.of(lo, hi);
    while (folk_cells.next()) |p| {
        if (g.sim.lv.folkAt(p) == null or !g.pic.litShown(&g.sim, p)) continue;
        const f = Prop.at(g, c, p, false);
        drawFigure(g, null, look.FOLK, f.s, false, f.mid, &f.shine, 0);
    }
    std.sort.insertion(Shown, bodies, {}, struct {
        fn less(_: void, a: Shown, b: Shown) bool {
            return a.mid[1] < b.mid[1];
        }
    }.less);
    var next_body: usize = 0;
    var occluders = view.grown(1).cells();
    while (occluders.next()) |p| {
        const kind = g.sim.lv.at(p);
        if (!look.occludes(kind) or !game.character.terrainSeen(g, p)) continue;
        const depth = @as(f32, @floatFromInt(p.y)) + 0.5;
        while (next_body < bodies.len and bodies[next_body].mid[1] <= depth) : (next_body += 1) drawStandingBody(g, &bodies[next_body]);
        drawOccluder(g, c, p, kind);
    }
    for (bodies[next_body..]) |*b| drawStandingBody(g, b);

    drawTorches(g, c, flames);
    g.pic.fx.drawGlow(&g.sim.lv, &g.light.visibility.sight, o[0], o[1], game.CELL_F);
    if (level_up_at) |at| g.pic.fx.level_up.drawSparks(at, o[0], o[1], game.CELL_F);
    if (g.debug.visuals.weather) if (g.light.sky) |k| g.rain.draw(game.weatherNow(g), &g.light.visibility.sight, o[0], o[1], game.CELL_F, sky.brightness(k));

    if (g.pic.shot) |s| if (s.t >= 0) {
        drawShot(g, s, o);
    };
    for (&g.pic.foe_shots) |*pending| {
        const s = pending.* orelse continue;
        if (s.t >= 0) drawShot(g, s, o);
    }
    if (blooming) {
        g.cinema.endScene(outer, o, game.CELL_F, g.light);
        g.framebuffer = outer;
    }

    for (bodies) |*b| {
        if (!b.pic.kind.foe()) continue;
        const y_bar = b.s.y + game.CELL - BODY_BAR_H - BODY_BAR_LIFT;
        const chill = b.pic.status.get(.chilled);
        if (chill > 0) pips(b.s.x + BODY_BAR_INSET, y_bar - CHILL_BAR_GAP - CHILL_BAR_H, game.CELL - BODY_BAR_INSET * 2, chill, glacial.TURNS, look.ailmentInk(.chill));
        if (!b.pic.hurt()) continue;
        bar(b.s.x + BODY_BAR_INSET, y_bar, game.CELL - BODY_BAR_INSET * 2, BODY_BAR_H, b.pic.hp, b.pic.max, look.BG, look.LIFE);
        const resistance = b.pic.resilience.peak().percent;
        if (resistance > 0) bar(b.s.x + BODY_BAR_INSET, y_bar + BODY_BAR_H + RESIST_BAR_GAP, game.CELL - BODY_BAR_INSET * 2, RESIST_BAR_H, resistance, mathx.PERCENT, look.BG, look.UI_GOLD);
    }

    if (aim_from) |from| outline(c, g.mode.aim.mark, if (skills.aimable(g, from, g.mode.aim.mark)) look.RETICLE else look.RETICLE_BLOCKED);
    if (game.playShown(g) and g.st.lean) drawLean(g, c, &stood);

    for (bodies) |*b| {
        g.pic.fx.drawSpeech(&g.face, b.slot, b.lifted.x, b.lifted.y, game.CELL_F, b.shine.sight);
    }
    if (level_up_at) |at| g.pic.fx.level_up.drawText(at, &g.face, o[0], o[1], game.CELL_F);
}

fn drawOccluder(g: *game.Game, c: Cam, p: P, kind: grid.Tile) void {
    const i = grid.Level.idx(p);
    const hidden = g.pic.occlusion[i];
    const occlusion: look.Occlusion = .{ .body = g.pic.occluder[i], .hidden = hidden };
    const tex = g.sprites.tileAt(&g.sim.lv, p) orelse {
        const l = look.tile(kind);
        drawGlyph(g, l.ch, c.sx(p), c.sy(p), look.fade(g.light.onBody(mathx.centre(p), false).tint(l.fg), look.occlusionAlpha(hidden)));
        return;
    };
    const rect = tileRect(kind, tex, c, p);
    const focus = g.cinema.focusOf(kind, tex, mathx.centre(p), g.light.carrier) orelse look.Focused.sharp;
    const view = shaders.MapView.of(-c.x, -c.y, game.CELL, g.screen.x, g.screen.y);
    const lightmap = g.light.mapTexture();
    const fogmap = g.light.gpu.layers.get(.fog);
    const shaded = if (lightmap != null and fogmap != null) g.sprites.drawScenery(tex, rect, view, lightmap.?, fogmap.?, occlusion, focus) else false;
    if (!shaded) raster.stretch(tex, rect, look.fade(sceneryTint(g, p), look.occlusionAlpha(hidden)));
    const rows = @divTrunc(@as(i32, @intFromFloat(rect.height)) + game.CELL - 1, game.CELL);
    const under = grid.Box{ .lo = .{ .x = p.x, .y = p.y + 1 - rows }, .hi = .{ .x = p.x + 1, .y = p.y + 1 } };
    if (g.cloud.veils(under) and g.cloud.beginOccludedVeil(sceneryTint(g, p), focus, if (shaded) occlusion else .{})) {
        raster.stretch(tex, rect, if (shaded) rl.Color.white else look.fade(rl.Color.white, look.occlusionAlpha(hidden)));
        cloud.Cloud.endVeil();
    }
}

fn drawStandingBody(g: *game.Game, b: *const Shown) void {
    const at = b.lifted;
    drawBody(g, b, false);
    const x: f32 = @floatFromInt(at.x);
    const y: f32 = @floatFromInt(at.y);
    for (std.enums.values(fx.Status)) |s| {
        if (b.pic.status.get(s) == 0) continue;
        switch (s) {
            .bleeding => g.pic.fx.drawBleeding(x, y, game.CELL_F, b.slot, b.shine.tint(s.ink())),
            .burning => g.pic.fx.drawBurning(x, y, game.CELL_F, b.slot, b.shine.sight),
            .chilled => g.pic.fx.drawChilled(x, y, game.CELL_F, b.slot, b.shine.tint(s.ink())),
            .pinned => g.pic.fx.drawPinned(x, y, game.CELL_F, b.shine.tint(s.ink())),
            .shocked => g.pic.fx.drawShocked(x, y, game.CELL_F, b.slot, b.shine.tint(s.ink())),
            .sundered => g.pic.fx.drawSundered(x, y, game.CELL_F, b.pic.sunder.stacks, b.shine.tint(s.ink())),
            .blinded => g.pic.fx.drawBlinded(x, y, game.CELL_F, b.shine.tint(s.ink())),
            .confused => g.pic.fx.drawConfused(x, y, game.CELL_F, b.slot, b.shine.tint(s.ink())),
            .frightened => g.pic.fx.drawFrightened(x, y, game.CELL_F, b.slot, b.shine.tint(s.ink())),
            .warded => g.pic.fx.drawWarded(x, y, game.CELL_F, b.shine.tint(s.ink())),
            .guarding, .unyielding, .steady, .overwatch => {},
            .resistant => {},
        }
    }
}

fn drawShot(g: *const game.Game, s: game.presentation.Shot, o: [2]f32) void {
    const at = s.position(s.t);
    if (!g.pic.litShown(&g.sim, mathx.cellOf(at))) return;
    if (s.net) fx.drawNet(at, s.t, o[0], o[1], game.CELL_F) else fx.drawMissile(at, s.direction(), s.act, s.t, o[0], o[1], game.CELL_F);
}

fn drawTacticalGround(g: *game.Game, c: Cam, lo: P, hi: P) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (!g.pic.litShown(&g.sim, p)) continue;
        const i = grid.Level.idx(p);
        const x = c.sx(p);
        const y = c.sy(p);
        if (g.sim.lv.caltrops[i].turns > 0) {
            inline for (CALTROPS) |q| {
                const tip = P{ .x = x + game.authored(q.x), .y = y + game.authored(q.y) - CALTROP_UP };
                const left = P{ .x = x + game.authored(q.x) - CALTROP_HALF, .y = y + game.authored(q.y) + CALTROP_DOWN };
                const right = P{ .x = x + game.authored(q.x) + CALTROP_HALF, .y = left.y };
                rl.drawLine(left.x, left.y, tip.x, tip.y, look.UI_GOLD);
                rl.drawLine(tip.x, tip.y, right.x, right.y, look.UI_GOLD);
            }
        }
        if (g.sim.lv.barrier[i] > 0) {
            fillCell(c, p, look.fade(look.WARD, BARRIER_FILL_A));
            outline(c, p, look.WARD);
            inline for (.{ game.CELL / 4, game.CELL * 3 / 4 }) |bar_x| rl.drawLine(x + bar_x, y + BARRIER_INSET, x + bar_x, y + game.CELL - BARRIER_INSET, look.WARD);
        }
        if (g.sim.lv.flames[i] > 0) {
            fillCell(c, p, look.fade(look.FIRE, FLAME_FILL_A));
            g.pic.fx.drawBurning(@floatFromInt(x), @floatFromInt(y), game.CELL_F, i, 1);
        }
    }
}

/// `n` of `of` equal segments lit, as a foe's chill meter.
fn pips(x: i32, y: i32, w: i32, n: u8, of: u8, fill: rl.Color) void {
    const count: i32 = of;
    const each = @divTrunc(w - (count - 1) * CHILL_PIP_GAP, count);
    for (0..of) |k| {
        const px = x + @as(i32, @intCast(k)) * (each + CHILL_PIP_GAP);
        rl.drawRectangle(px, y, each, CHILL_BAR_H, if (k < n) fill else look.BG);
    }
}

pub fn effectLights(g: *game.Game) void {
    g.pic.fx.illuminate(&g.sim.lv, g.light);
    if (g.pic.carrierAt(&g.sim)) |at| {
        if (g.pic.fx.level_up.emission(at)) |source| g.light.emit(&g.sim.lv, source);
    }
    if (g.pic.shot) |s| {
        if (fx.missileLight(s.position(s.t), s.act)) |source| g.light.emit(&g.sim.lv, source);
    }
    for (0..g.sim.pool.n) |i| {
        const at = g.pic.drawnAt(&g.sim, i) orelse continue;
        const pic = g.pic.pictured[i];
        if (pic.down()) continue;
        const flicker = g.pic.fx.statusFlicker(@floatFromInt(i));
        const source = for (std.enums.values(fx.Status)) |s| {
            if (pic.status.get(s) > 0) if (s.emission(game.middle(at), flicker)) |e| break e;
        } else continue;
        g.light.emit(&g.sim.lv, source);
    }
    for (&g.sim.lv.flames, 0..) |turns, i| {
        const p = grid.Level.of(i);
        if (turns == 0 or !g.sim.lv.isLit(p)) continue;
        const mid = mathx.centre(p);
        g.light.emit(&g.sim.lv, .{ .at = .{ mid[0], mid[1], light.BODY_Z }, .col = look.FIRE, .radius = FLAME_LIGHT_R, .gain = FLAME_LIGHT_GAIN * g.pic.fx.statusFlicker(@floatFromInt(i)) });
    }
}

/// Over the light map, so each glows as its own light, but under the bodies that pass it.
fn drawPlants(g: *game.Game, c: Cam, flames: []const light.Flame) void {
    for (flames) |f| if (f.kind == .plant and f.live()) {
        const p = mathx.cellOf(f.at);
        const l = look.tile(g.pic.tileShown(&g.sim, p));
        drawGlyph(g, l.ch, c.sx(p), c.sy(p), look.fade(l.fg, flameLit(f)));
    };
}

/// Over the light map, so each flame is its own light; a remembered one stays drawn, dim and unlit.
fn drawTorches(g: *game.Game, c: Cam, flames: []const light.Flame) void {
    for (flames) |f| if (f.kind == .wall) drawFlame(g, c, f, flameLit(f));
    const o = c.origin();
    g.light.drawGlows(flames, o[0], o[1], game.CELL_F);
}

/// Movement hints follow presented occupants, including deaths still being drawn.
pub fn leanShown(g: *game.Game, stood: *const grid.CellSet, from: P, d: mathx.Dir) game.Move {
    return game.moveOf(g, from, d, shownAt(g, stood, from.add(d.delta())));
}

fn drawLean(g: *game.Game, c: Cam, stood: *const grid.CellSet) void {
    const at = game.cellUnder(g.pic.heroNow(&g.sim) orelse return);
    for (input.DPAD) |button| {
        const d = input.leanOf(button);
        const p = at.add(d.delta());
        const col = switch (leanShown(g, stood, at, d)) {
            .kick => look.LEAN_FOE,
            .step, .open, .burst, .loot, .talk => look.LEAN_OPEN,
            .blocked => look.LEAN_BLOCKED,
        };
        outline(c, p, col);
        if (g.sim.lv.walkable(p) and !shownAt(g, stood, p)) {
            const m = c.mid(p);
            line_icons.drawDirection(button, m.x, m.y, LEAN_GLYPH, col);
            continue;
        }
        const inset = LEAN_PAD + @divTrunc(LEAN_MARK, 2);
        const dx: i32 = if (d.delta().x > 0) game.CELL - inset else inset;
        const dy: i32 = if (d.delta().y > 0) game.CELL - inset else inset;
        line_icons.drawDirection(button, c.sx(p) + dx, c.sy(p) + dy, LEAN_MARK, col);
    }
}

/// One texel per cell, enlarged by `MINI`; requires a live GL context.
pub const Minimap = struct {
    tex: ?rl.Texture2D = null,
    px: [grid.CELLS]rl.Color = undefined,
    /// Set by `castSight` and `toggleReveal`; `drawMinimap` also rebakes when a pictured tile lands.
    stale: bool = true,
    pictured: game.presentation.Pictured = .{},

    pub fn load(m: *Minimap) void {
        m.tex = raster.canvas(grid.W, grid.H, rl.Color.blank, .point);
        m.stale = true;
    }

    pub fn unload(m: *Minimap) void {
        look.unloadAll(m);
    }
};

pub fn miniOrigin(screen_w: i32) P {
    return .{ .x = screen_w - MINI_W - MINI_PAD - MINI_FRAME, .y = MINI_PAD + MINI_FRAME };
}

fn miniDot(o: P, p: P, grow: i32, col: rl.Color) void {
    rl.drawRectangleRec(raster.grown(raster.rect(o.x + p.x * MINI, o.y + p.y * MINI, MINI, MINI), @floatFromInt(grow)), col);
}

pub fn drawMinimap(g: *game.Game) void {
    const o = miniOrigin(g.screen.x);
    const map = miniBox(g.screen.x);
    look.hudPanelIn(&g.sprites, miniFrame(g.screen.x), look.MINI_BG, look.LIT);
    if (g.mini.tex) |t| {
        const pictured = g.pic.pictureKey();
        if (g.mini.stale or !std.meta.eql(pictured, g.mini.pictured)) {
            for (&g.mini.px, &g.sim.lv.seen, 0..) |*c, seen, i| {
                const p = grid.Level.of(i);
                c.* = if (seen or g.light.reveal_map) look.mini(g.pic.tileShown(&g.sim, p), g.pic.litShown(&g.sim, p)) else rl.Color.blank;
            }
            rl.updateTexture(t, &g.mini.px);
            g.mini.stale = false;
            g.mini.pictured = pictured;
        }
        raster.stretch(t, map, look.LIT);
    }
    for (g.sim.pool.slice(), 0..) |a, i| {
        if (!a.foe()) continue;
        miniDot(o, g.pic.drawnCell(&g.sim, i) orelse continue, 0, look.MINI_FOE);
    }
    if (g.pic.heroNow(&g.sim)) |at| miniDot(o, game.cellUnder(at), MINI_HERO_GROW, look.MINI_HERO);
    const v = miniView(Cam.of(g), g.screen);
    rl.drawRectangleLines(o.x + v.lo.x, o.y + v.lo.y, v.hi.x - v.lo.x, v.hi.y - v.lo.y, look.MINI_VIEW);
}

fn miniBox(screen_w: i32) rl.Rectangle {
    const o = miniOrigin(screen_w);
    return raster.rect(o.x, o.y, MINI_W, MINI_H);
}

pub fn miniFrame(screen_w: i32) rl.Rectangle {
    return raster.grown(miniBox(screen_w), @floatFromInt(MINI_FRAME));
}

pub fn dayLine(screen_w: i32) struct { x0: i32, x1: i32, y: i32 } {
    const m = miniOrigin(screen_w);
    const f = miniFrame(screen_w);
    return .{ .x0 = m.x + DAY_INSET, .x1 = m.x + MINI_W - DAY_INSET, .y = @as(i32, @intFromFloat(f.y + f.height)) + DAY_GAP };
}

pub fn drawDayNight(g: *game.Game) void {
    const l = dayLine(g.screen.x);
    const now = day.arc(g.pic.hour_shown);
    const at = rl.Vector2{
        .x = @round(mathx.lerpF(@floatFromInt(l.x0), @floatFromInt(l.x1), now.u)),
        .y = @floatFromInt(l.y),
    };
    const left: i32 = @intFromFloat(at.x - DAY_CLEAR);
    const right: i32 = @intFromFloat(at.x + DAY_CLEAR);
    for ([_]bool{ true, false }) |shadow| {
        const by: i32 = if (shadow) DAY_DROP else 0;
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
    rl.drawCircleV(at, SUN_R, col);
    for (0..SUN_RAYS) |i| {
        const a = mathx.TAU * @as(f32, @floatFromInt(i)) / SUN_RAYS;
        const d = rl.Vector2{ .x = @cos(a), .y = @sin(a) };
        rl.drawLineEx(at.add(d.scale(SUN_RAY_IN)), at.add(d.scale(SUN_RAY_OUT)), 1, col);
    }
}

fn moonGlyph(at: rl.Vector2, col: rl.Color) void {
    const cut_r = MOON_R - MOON_CUT_INSET;
    var y: f32 = -MOON_R + 0.5;
    while (y < MOON_R) : (y += 1) {
        const half = @sqrt(MOON_R * MOON_R - y * y);
        const right = if (@abs(y) < cut_r) @min(half, MOON_CUT - @sqrt(cut_r * cut_r - y * y)) else half;
        if (right <= -half) continue;
        rl.drawRectangleRec(.{ .x = @round(at.x - half), .y = at.y + y - 0.5, .width = @round(right + half), .height = 1 }, col);
    }
}

fn miniView(c: Cam, screen: P) grid.Box {
    return .{
        .lo = .{ .x = @max(0, toMini(c.x)), .y = @max(0, toMini(c.y)) },
        .hi = .{ .x = @min(MINI_W, toMini(c.x + screen.x)), .y = @min(MINI_H, toMini(c.y + screen.y)) },
    };
}

fn toMini(px: i32) i32 {
    return @divTrunc(px * MINI, game.CELL);
}
