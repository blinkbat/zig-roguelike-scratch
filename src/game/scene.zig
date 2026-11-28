const sprite_assets = @import("../gfx/sprite_assets.zig");
const sprite = @import("../gfx/sprites.zig");
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const bow = @import("../play/bow.zig");
const windup = @import("../play/windup.zig");
const skillbar = @import("../play/skillbar.zig");
const glacial = @import("../play/glacial.zig");
const tactics = @import("../play/tactics.zig");
const tactics_exec = @import("tactics_exec.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const font = @import("../gfx/font.zig");
const line_icons = @import("../gfx/line_icons.zig");
const dual = @import("../gfx/ground.zig");
const light = @import("../gfx/light.zig");
const light_visibility = @import("../gfx/light_visibility.zig");
const shadows = @import("../gfx/shadow.zig");
const fx = @import("../gfx/fx.zig");
const ground_items = @import("../play/ground_items.zig");
const cloud = @import("../gfx/cloud.zig");
const sky = @import("../gfx/sky.zig");
const day = @import("../map/day.zig");
const climate = @import("../map/climate.zig");
const shaders = @import("../gfx/shaders.zig");
const hud = @import("../ui/hud.zig");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const firebolt = @import("../play/firebolt.zig");
const P = mathx.P;

const LEAN_GLYPH: i32 = game.authored(40);
const LEAN_MARK: i32 = game.authored(30);
const LEAN_PAD: i32 = game.authored(4);
const OUTLINE_INSET: i32 = game.authored(1);
const BODY_BAR_INSET: i32 = game.authored(6);
const BODY_BAR_W: i32 = game.CELL - BODY_BAR_INSET * 2;
const BODY_BAR_H: i32 = game.authored(4);
const BODY_BAR_LIFT: i32 = game.authored(2);
const RESIST_BAR_H: i32 = game.authored(2);
const RESIST_BAR_GAP: i32 = game.authored(2);
const CHILL_BAR_H: i32 = game.authored(3);
const CHILL_BAR_GAP: i32 = game.authored(2);
const CHILL_PIP_GAP: i32 = game.authored(2);
const FLAME_FILL_A: f32 = 0.24;
const BARRIER_FILL_A: f32 = 0.28;
const BARRIER_INSET: i32 = game.authored(5);
const BARRIER_BARS = .{ game.authored(16), game.authored(48) };
/// Caltrop centers in authored cell pixels.
const CALTROPS = [_]P{ .{ .x = 12, .y = 20 }, .{ .x = 29, .y = 32 }, .{ .x = 42, .y = 17 } };
const CALTROP_HALF: i32 = game.authored(4);
const CALTROP_UP: i32 = game.authored(5);
const CALTROP_DOWN: i32 = game.authored(3);
const MINI: i32 = 3;
const MINI_W: i32 = grid.W * MINI;
const MINI_H: i32 = grid.H * MINI;
const MINI_PAD: i32 = hud.EDGE;
const MINI_FRAME: i32 = sprite.HUD_BORDER_CUT;
const MINI_HERO_GROW: i32 = 1;
const DAY_GAP: i32 = 12;
const DAY_INSET: i32 = 16;
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

    pub fn origin(c: Cam) [2]f32 {
        return .{ @floatFromInt(-c.x), @floatFromInt(-c.y) };
    }

    /// Round after subtracting the camera offset to avoid jitter during matched motion.
    pub fn px(c: Cam, v: rl.Vector2) P {
        return .{ .x = mathx.roundTiesUp(v.x - c.at.x), .y = mathx.roundTiesUp(v.y - c.at.y) };
    }
};

fn spriteRect(t: rl.Texture2D, s: P) rl.Rectangle {
    const k = @max(1, @divTrunc(game.CELL, t.width));
    return raster.rect(s.x + @divTrunc(game.CELL - t.width * k, 2), s.y + @divTrunc(game.CELL - t.height * k, 2), t.width * k, t.height * k);
}

fn tileRect(kind: grid.Tile, tex: rl.Texture2D, c: Cam, p: P) rl.Rectangle {
    return look.tileRect(kind, tex, c.box(p));
}

fn cellInk(g: *const game.Game, p: P) rl.Color {
    return look.fade(look.LIT, g.pic.cellAlpha(p));
}

fn drawShining(g: *const game.Game, t: rl.Texture2D, c: Cam, p: P, loot_glow: bool) void {
    const rect = spriteRect(t, c.corner(p));
    const ink = cellInk(g, p);
    raster.stretch(t, rect, ink);
    shineOver(g, t, rect, p, ink, loot_glow);
}

fn shineOver(g: *const game.Game, t: rl.Texture2D, rect: rl.Rectangle, p: P, col: rl.Color, loot_glow: bool) void {
    if (g.pic.cellAlpha(p) <= 0) return;
    const sweep = look.shineSweep(g.pic.fx.seconds.at(), p) orelse if (loot_glow) -1 else return;
    g.sprites.drawShine(t, rect, sweep, col, if (loot_glow) look.LOOT_GLOW else 0);
}

fn drawGlyph(g: *game.Game, ch: u8, s: P, col: rl.Color) void {
    g.face.glyph(ch, s.x + game.HALF_CELL, s.y + game.HALF_CELL, game.GLYPH, col);
}

fn drawFigureGlyph(g: *game.Game, ch: u8, sx: i32, sy: i32, col: rl.Color) void {
    for ([_]i32{ 0, game.authored(1) }) |dx| g.face.glyph(ch, sx + dx + game.HALF_CELL, sy + game.HALF_CELL, game.CELL, col);
}

fn drawFigureLetter(g: *game.Game, l: look.Look, s: P, flash: f32, opacity: f32) void {
    const off = game.authored(look.GLYPH_SHADOW_PX);
    drawFigureGlyph(g, l.ch, s.x + off, s.y + off, look.fade(look.GLYPH_SHADOW, opacity));
    drawFigureGlyph(g, l.ch, s.x, s.y, look.fade(look.mixed(l.fg, look.LIT, flash), opacity));
}

fn drawCoins(g: *const game.Game, c: Cam, pile: ground_items.Coins) void {
    const tex = if (pile.large()) g.sprites.large_coins else g.sprites.small_coins;
    if (tex) |t| {
        drawShining(g, t, c, pile.at, false);
    } else {
        const m = c.mid(pile.at);
        g.face.centred("$", m.x, m.y, game.GLYPH, look.fade(look.UI_GOLD, g.pic.cellAlpha(pile.at)));
    }
}

fn looseBag(here: grid.Tile, bags: *const Bags, p: P) bool {
    return here != .chest_open and bags.isSet(grid.Level.idx(p));
}

fn chestShines(here: grid.Tile, p: P, bags: *const Bags) bool {
    return here == .chest or (here == .chest_open and bags.isSet(grid.Level.idx(p)));
}

fn outline(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleLinesEx(raster.grown(c.box(p), @floatFromInt(-OUTLINE_INSET)), @floatFromInt(game.LINE_W), col);
}

fn fillCell(c: Cam, p: P, col: rl.Color) void {
    rl.drawRectangleRec(c.box(p), col);
}

fn fillLit(g: *const game.Game, c: Cam, cells: []const P, col: rl.Color) void {
    for (cells) |p| if (g.sim.lv.isLit(p)) fillCell(c, p, col);
}

pub fn barrelShownAt(g: *game.Game, p: P) bool {
    if (!terrainSeen(g, p)) return false;
    if (g.pic.litShown(&g.sim, p) or !g.sim.lv.isSeen(p)) return g.pic.barrelPresent(&g.sim, p);
    return g.pic.barrelSeenShown(&g.sim, p);
}

pub fn toggleReveal(g: *game.Game) void {
    g.light.reveal(&g.sim.lv, !g.light.reveal_map);
    g.mini.stale = true;
}

pub fn terrainSeen(g: *const game.Game, p: P) bool {
    return g.light.reveal_map or g.pic.seenShown(&g.sim, p);
}

pub fn shownAt(g: *game.Game, stood: *const grid.CellSet, p: P) bool {
    return insideSet(stood, p) or barrelShownAt(g, p);
}

fn insideSet(set: *const grid.CellSet, p: P) bool {
    return grid.Level.inside(p) and grid.inSet(set, p);
}

pub fn stoodNow(g: *game.Game) grid.CellSet {
    var stood = grid.CellSet.initEmpty();
    for (0..g.sim.pool.n) |i| stand(&stood, g.pic.drawnCell(&g.sim, i) orelse continue);
    return stood;
}

fn stand(stood: *grid.CellSet, under: P) void {
    if (grid.Level.inside(under)) stood.set(grid.Level.idx(under));
}

const Shown = struct {
    pic: fx.Body,
    slot: usize,
    sighted: f32,
    s: P,
    lifted: P,
    mid: [2]f32,
    left: bool,
    shine: light.Shine,
    opacity: f32,
    dark: f32,
    flash: f32,
};

pub const Scratch = struct {
    beds: dual.Beds,
    burnt: dual.Beds,
    bodies: [actor.MAX]Shown,
    aim_ground: grid.Level,
};

const Prop = struct {
    s: P,
    mid: [2]f32,
    shine: light.Shine,

    fn at(g: *game.Game, c: Cam, p: P, casting: bool) Prop {
        const mid = mathx.centre(p);
        return .{ .s = c.corner(p), .mid = mid, .shine = if (casting) g.light.onCaster(mid, false) else g.light.onBody(mid, false) };
    }

    fn remembered(c: Cam, p: P) Prop {
        return .{ .s = c.corner(p), .mid = mathx.centre(p), .shine = .{ .ambient = @splat(1) } };
    }

    fn over(g: *game.Game, c: Cam, p: P, kind: grid.Tile) Prop {
        var mid = mathx.centre(p);
        mid[0] += @as(f32, @floatFromInt(kind.wide() - 1)) / 2;
        return .{ .s = c.corner(p), .mid = mid, .shine = g.light.onCaster(mid, false) };
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

fn drawLit(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32, opacity: f32, fade: [2]f32) void {
    if (tex) |t| {
        g.light.drawBody(t, spriteRect(t, s), left, mid, shine, flash, opacity, fade);
    } else drawFigureLetter(g, l, s, flash, opacity);
}

fn drawFigure(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32, opacity: f32) void {
    drawLit(g, tex, l, s, left, mid, shine, flash, opacity, .{ 0, 0 });
    const tall = if (tex) |t| spriteRect(t, s).height else game.CELL_F;
    if (!beginFigureVeil(g, mathx.cellOf(mid), tall, shine.tint(look.LIT), .sharp)) return;
    defer cloud.Cloud.endVeil();
    const ink = look.fade(look.LIT, opacity);
    if (tex) |t| {
        raster.blit(t, raster.facing(t, left), spriteRect(t, s), ink);
    } else drawFigureGlyph(g, l.ch, s.x, s.y, ink);
}

fn drawGroundPass(g: *game.Game, c: Cam, ground: *const grid.Level, beds: *const dual.Beds, stood: *const grid.CellSet, mirror: ?sprite.Mirrors, burnt: ?*const grid.Level) void {
    const x = std.math.clamp(-c.x, 0, g.screen.x);
    const y = std.math.clamp(-c.y, 0, g.screen.y);
    const right = std.math.clamp(game.MAP_PX.x - c.x, 0, g.screen.x);
    const bottom = std.math.clamp(game.MAP_PX.y - c.y, 0, g.screen.y);
    rl.beginScissorMode(x, y, right - x, bottom - y);
    defer rl.endScissorMode();
    const water: ?sprite.WaterView = if (g.light.glintTexture()) |glints| if (g.light.mapTexture()) |tex| .{
        .screen = .{ @floatFromInt(g.screen.x), @floatFromInt(g.screen.y) },
        .visibility = tex,
        .glints = glints,
        .mirror = mirror,
        .shimmer = g.light.options.water_glints,
        .seconds = g.light.t.at(),
    } else null else null;
    g.sprites.drawGround(ground, beds, c.origin(), game.CELL_F, water);
    if (burnt) |old| drawBurntGround(g, c, old, water);
    var cells = grid.Cells.of(beds.lo, beds.hi);
    while (cells.next()) |p| {
        if (!terrainSeen(g, p)) continue;
        const here = ground.at(p);
        if (sprite.glyphGround(here, &g.sprites)) inkCell(g, c, p, here, stood);
        if (g.sim.lv.doorAt(p) != null) drawGlyph(g, look.DOOR.ch, c.corner(p), look.DOOR.fg);
    }
}

fn drawBurntGround(g: *game.Game, c: Cam, old: *const grid.Level, water: ?sprite.WaterView) void {
    const beds = &g.drawn.burnt;
    beds.fill(old, g.pic.burnt_box.lo, g.pic.burnt_box.hi, !g.light.reveal_map);
    const target = &g.sprites.burnt_ground;
    if (!raster.beginTarget(target, g.screen, g.framebuffer, rl.Color.blank)) return;
    g.sprites.drawGround(old, beds, c.origin(), game.CELL_F, water);
    raster.endTarget(g.framebuffer);
    const t = target.*.?.texture;
    var cells = g.pic.burnt_box.cells();
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        if (g.pic.fadingBurnt(i) == null or !terrainSeen(g, p)) continue;
        raster.drawTargetPart(t, c.box(p), look.fade(look.LIT, g.pic.ember(i)));
    }
}

fn drawBurntStanding(g: *game.Game, c: Cam, old: *const grid.Level, occluding: bool) void {
    var cells = g.pic.burnt_box.cells();
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        const was = g.pic.fadingBurnt(i) orelse continue;
        if (!look.standsOver(was) or look.occludes(was) != occluding) continue;
        if (!terrainSeen(g, p)) continue;
        const tex = g.sprites.tileAt(old, p) orelse continue;
        const a = g.pic.ember(i);
        if (occluding) {
            raster.stretch(tex, tileRect(was, tex, c, p), look.fade(sceneryTint(g, p), a));
            if (flamesSeen(g, p)) drawCellFlames(g, c, p);
        } else raster.stretch(tex, spriteRect(tex, c.corner(p)), look.fade(look.LIT, a));
    }
}

pub fn bagCells(g: *const game.Game) grid.CellSet {
    var bags = grid.CellSet.initEmpty();
    inline for (g.sim.ground.laid()) |laid| for (laid) |l| {
        const remembered = g.sim.lv.at(l.at) == .chest_open and g.pic.laidDown(l);
        if (remembered or g.pic.laidShown(&g.sim, l)) bags.set(grid.Level.idx(l.at));
    };
    for (g.sim.ground.coins[0..g.sim.ground.coin_n]) |pile| {
        if (g.sim.lv.at(pile.at) == .chest_open and g.pic.pileLanded(&g.sim, pile) != null) bags.set(grid.Level.idx(pile.at));
    }
    return bags;
}

pub const Bags = struct {
    contents: grid.CellSet,
    view: ?struct { g: *const game.Game, ground: *const grid.Level } = null,

    pub fn isSet(bags: *const Bags, i: usize) bool {
        if (bags.view) |view| {
            const cell = &view.g.pic.seen_cells[i];
            if (view.ground.tile[i] != .chest_open) return cell.bag and cell.alpha > 0;
            if (!view.g.pic.litShown(&view.g.sim, grid.Level.of(i))) return cell.bag or cell.coins > 0;
        }
        return bags.contents.isSet(i);
    }
};

pub fn shownBags(g: *const game.Game, ground: *const grid.Level) Bags {
    return .{ .contents = bagCells(g), .view = .{ .g = g, .ground = ground } };
}

fn tileTexture(g: *const game.Game, ground: *const grid.Level, here: grid.Tile, p: P, bags: *const Bags) ?rl.Texture2D {
    if (here == .chest_open and bags.isSet(grid.Level.idx(p))) return g.sprites.chest_item_bag;
    if (here == .chest and g.pic.mimicAt(&g.sim, p)) return g.sprites.mimic_closed;
    return g.sprites.tileAt(ground, p);
}

fn drawSolidPass(g: *game.Game, c: Cam, ground: *const grid.Level, lo: P, hi: P, stood: *const grid.CellSet, bags: *const Bags) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        if (!terrainSeen(g, p)) continue;
        const here = ground.at(p);
        defer if (looseBag(here, bags, p)) {
            if (g.sprites.item_bag) |t| {
                drawShining(g, t, c, p, true);
                veilSprite(g, t, c, p, .sharp, cellInk(g, p));
            }
        };
        if (look.occludes(here) or here.isPart()) continue;
        if (!look.standsOver(here)) continue;
        if (tileTexture(g, ground, here, p, bags)) |t| {
            const focus = g.cinema.beginFocus(here, t, mathx.centre(p), g.light.carrier);
            const rect = spriteRect(t, c.corner(p));
            raster.stretch(t, rect, look.LIT);
            if (focus != null) rl.endShaderMode();
            if (chestShines(here, p, bags)) shineOver(g, t, rect, p, cellInk(g, p), here == .chest_open);
            if (look.veiled(here)) veilSprite(g, t, c, p, focus orelse .sharp, look.LIT);
            continue;
        }
        if (look.tileBg(here)) |bg| fillCell(c, p, bg);
        inkCell(g, c, p, here, stood);
        if (look.veiled(here) and beginFigureVeil(g, p, game.CELL_F, look.LIT, .sharp)) {
            inkCell(g, c, p, here, stood);
            cloud.Cloud.endVeil();
        }
    }
}

fn veilSprite(g: *game.Game, t: rl.Texture2D, c: Cam, p: P, focus: look.Focused, ink: rl.Color) void {
    const rect = spriteRect(t, c.corner(p));
    if (!beginFigureVeil(g, p, rect.height, ink, focus)) return;
    raster.stretch(t, rect, ink);
    cloud.Cloud.endVeil();
}

fn beginFigureVeil(g: *game.Game, feet: P, tall: f32, ink: rl.Color, focus: look.Focused) bool {
    return g.cloud.veils(veilBox(feet, tall)) and g.cloud.beginVeil(ink, focus);
}

/// Pad the figure's footprint by one cell for glide motion.
fn veilBox(feet: P, tall: f32) grid.Box {
    const rows = cellsTall(tall);
    return .{ .lo = .{ .x = feet.x - 1, .y = feet.y - rows }, .hi = .{ .x = feet.x + 2, .y = feet.y + 2 } };
}

fn cellsTall(px: f32) i32 {
    return @divTrunc(@as(i32, @intFromFloat(px)) + game.CELL - 1, game.CELL);
}

fn inkCell(g: *game.Game, c: Cam, p: P, here: grid.Tile, stood: *const grid.CellSet) void {
    if (shownAt(g, stood, p) or (g.pic.npcShown(p) != null and g.pic.litShown(&g.sim, p))) return;
    const m = c.mid(p);
    look.inkTile(&g.face, here, m.x, m.y, game.GLYPH);
}

/// False with no shader for it.
pub fn shadowPass(g: *game.Game, c: Cam, ground: *const grid.Level, view: grid.Box, bags: *const Bags, framebuffer: u32) bool {
    if (!g.light.beginShadows(g.screen, framebuffer)) return false;
    drawShadows(g, c, ground, view.grown(shadows.sceneryMargin(&g.sprites)), bags);
    g.light.endShadows(-c.x, -c.y, game.CELL);
    return true;
}

fn drawShadows(g: *game.Game, c: Cam, ground: *const grid.Level, cast: grid.Box, bags: *const Bags) void {
    var props = cast.cells();
    while (props.next()) |p| {
        const kind = ground.at(p);
        if (terrainSeen(g, p) and looseBag(kind, bags, p)) propShadow(g, c, p, g.sprites.item_bag, g.pic.cellAlpha(p));
        if (barrelShownAt(g, p)) propShadow(g, c, p, g.sprites.barrel, 1);
        if (!look.castsPicture(kind) or !footprintSeen(g, p, kind)) continue;
        const forest = sprite_assets.forestAt(ground, p);
        const t = tileTexture(g, ground, kind, p, bags) orelse continue;
        const pr = Prop.over(g, c, p, kind);
        const rect = tileRect(kind, t, c, p);
        if (forest) {
            g.light.drawForestShadows(t, rect, pr.mid, &pr.shine, g.sim.lv.tileShape(p) orelse .{});
        } else if (look.canopied(kind)) {
            g.light.drawCanopy(t, rect, pr.mid, &pr.shine);
        } else g.light.drawShadows(t, rect, false, pr.mid, &pr.shine, 1);
    }
    for (0..g.sim.pool.n) |i| {
        const at = g.pic.casterAt(&g.sim, i, cast) orelse continue;
        const body = g.pic.bodyShown(&g.sim, i);
        const opacity = figureOpacity(g.pic.sighted[i], body.opacity, body.pic.kind);
        if (opacity <= 0) continue;
        const t = g.sprites.body(body.pic.kind) orelse continue;
        const s = c.px(at);
        const mid = game.middle(at);
        const shine = g.light.onCaster(mid, g.sim.isHero(i));
        g.light.drawShadows(t, spriteRect(t, s), body.facing == .left, mid, &shine, opacity);
    }
}

fn propShadow(g: *game.Game, c: Cam, p: P, tex: ?rl.Texture2D, opacity: f32) void {
    const t = tex orelse return;
    const b = Prop.at(g, c, p, true);
    g.light.drawShadows(t, spriteRect(t, b.s), false, b.mid, &b.shine, opacity);
}

pub fn viewBox(g: *const game.Game, c: Cam) grid.Box {
    return grid.Box.between(c.cellAt(.{ .x = 0, .y = 0 }), c.cellAt(g.screen)).grown(0);
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

const GLYPH_FOOT: f32 = 0.8;

fn footOf(g: *const game.Game, tex: ?rl.Texture2D, s: P) f32 {
    const t = tex orelse return @as(f32, @floatFromInt(s.y)) + game.CELL_F * GLYPH_FOOT;
    return g.light.footY(t, spriteRect(t, s));
}

fn drawMirrored(g: *game.Game, tex: ?rl.Texture2D, l: look.Look, stands: P, s: P, left: bool, mid: [2]f32, shine: *const light.Shine, flash: f32, opacity: f32) void {
    const foot = footOf(g, tex, stands);
    const top = if (tex) |t| g.light.topY(t, spriteRect(t, s)) else @as(f32, @floatFromInt(font.Face.topFor(s.y + game.HALF_CELL, game.GLYPH)));
    const bounds = mirrorFade(g, foot, top, footOf(g, tex, s));
    const r = Reflection.begin(g, foot, if (tex == null) bounds else null);
    defer r.end();
    drawLit(g, tex, l, s, left, mid, shine, flash, opacity, bounds);
}

fn mirrorFade(g: *const game.Game, foot: f32, top: f32, bottom: f32) [2]f32 {
    const screen: f32 = @floatFromInt(g.screen.y);
    return .{ screen - 2 * foot + top, screen - 2 * foot + mathx.lerpF(top, bottom, MIRROR_FADE) };
}

fn drawBody(g: *game.Game, b: *const Shown, mirrored: bool) void {
    const tex = g.sprites.body(b.pic.kind);
    const l = look.body(b.pic.kind);
    const opacity = figureOpacity(b.sighted, b.opacity, b.pic.kind);
    var shine = b.shine;
    if (look.bodyGlow(b.pic.kind)) |col| shine.emission = look.rgbOf(col) * sky.splat(look.BODY_GLOW_EMISSION);
    if (g.sim.isHero(b.slot)) shine.emission = g.pic.fx.level_up.bodyGlow();
    if (b.dark > 0) darken(&shine, b.dark);
    if (mirrored) drawMirrored(g, tex, l, b.s, b.lifted, b.left, b.mid, &shine, b.flash, opacity) else drawFigure(g, tex, l, b.lifted, b.left, b.mid, &shine, b.flash, opacity);
}

fn figureOpacity(sighted: f32, opacity: f32, kind: actor.Kind) f32 {
    return sighted * opacity * look.bodyOpacity(kind);
}

fn darken(shine: *light.Shine, dark: f32) void {
    const k = sky.mix(sky.splat(1), fx.DEATH_RGB, dark);
    shine.ambient *= k;
    shine.floor *= k;
    shine.emission *= k;
    for (shine.lamp[0..shine.n]) |*l| l.colour *= k;
}

fn drawBarrel(g: *game.Game, b: *const Prop, mirrored: bool) void {
    if (mirrored) drawMirrored(g, g.sprites.barrel, look.BARREL, b.s, b.s, false, b.mid, &b.shine, 0, 1) else drawFigure(g, g.sprites.barrel, look.BARREL, b.s, false, b.mid, &b.shine, 0, 1);
}

fn sceneryTint(g: *const game.Game, p: P) rl.Color {
    return g.light.onBody(mathx.centre(p), false).tint(look.LIT);
}

fn mirrorsOnWater(ground: *const grid.Level, c: Cam, rect: rl.Rectangle, foot: f32) bool {
    const lo = c.cellAt(.{ .x = @intFromFloat(@floor(rect.x)), .y = @intFromFloat(@floor(foot)) }).sub(.{ .x = 1, .y = 1 });
    const hi = c.cellAt(.{ .x = @intFromFloat(@ceil(rect.x + rect.width)), .y = @intFromFloat(@ceil(2 * foot - rect.y)) }).add(.{ .x = 2, .y = 2 });
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |q| {
        if (grid.Level.inside(q) and look.reflects(ground.at(q))) return true;
    }
    return false;
}

fn mirrorSprite(g: *const game.Game, c: Cam, ground: *const grid.Level, p: P, kind: grid.Tile, t: rl.Texture2D, shaded: bool, opacity: f32) void {
    const rect = tileRect(kind, t, c, p);
    const foot = g.light.footY(t, rect);
    if (!mirrorsOnWater(ground, c, rect, foot)) return;
    const tint = look.fade(if (shaded) sceneryTint(g, p) else look.LIT, opacity);
    const r = Reflection.begin(g, foot, mirrorFade(g, foot, g.light.topY(t, rect), foot));
    defer r.end();
    raster.stretch(t, rect, tint);
}

fn drawMirrorScenery(g: *game.Game, c: Cam, ground: *const grid.Level, view: grid.Box, bags: *const Bags, memory: bool) void {
    var cells = view.grown(game.CAST_MARGIN).cells();
    while (cells.next()) |p| {
        const kind = ground.at(p);
        if (!footprintSeen(g, p, kind)) continue;
        if (look.standsOver(kind)) {
            if (tileTexture(g, ground, kind, p, bags)) |t| mirrorSprite(g, c, ground, p, kind, t, !memory, 1);
        }
        if (!memory and looseBag(kind, bags, p)) {
            if (g.sprites.item_bag) |t| mirrorSprite(g, c, ground, p, kind, t, true, g.pic.cellAlpha(p));
        }
        if (barrelShownAt(g, p)) {
            var b = if (memory) Prop.remembered(c, p) else Prop.at(g, c, p, false);
            drawBarrel(g, &b, true);
        }
    }
}

fn drawMirrorTorches(g: *game.Game, c: Cam, ground: *const grid.Level, flames: []const light.Flame, memory: bool) void {
    for (flames) |f| {
        if (f.kind != .wall) continue;
        const foot = f.foot * game.CELL_F - @as(f32, @floatFromInt(c.y));
        const top = f.at[1] * game.CELL_F - @as(f32, @floatFromInt(c.y + game.authored(fx.TORCH_TOP_PX)));
        const x = f.at[0] * game.CELL_F - @as(f32, @floatFromInt(c.x));
        if (!mirrorsOnWater(ground, c, .{ .x = x - game.CELL_F, .y = top, .width = 2 * game.CELL_F, .height = foot - top }, foot)) continue;
        const r = Reflection.begin(g, foot, mirrorFade(g, foot, top, foot));
        defer r.end();
        drawFlame(g, c, f, if (memory) 0 else flameLit(f) * g.pic.cellAlpha(mathx.cellOf(f.at)));
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

pub fn drawMirrors(g: *game.Game, c: Cam, ground: *const grid.Level, view: grid.Box, bags: *const Bags, bodies: []const Shown, flames: []const light.Flame) ?sprite.Mirrors {
    if (!g.sprites.beginMirror(g.screen, g.framebuffer, true)) return null;
    rl.gl.rlDisableBackfaceCulling();
    defer rl.gl.rlEnableBackfaceCulling();
    drawMirrorScenery(g, c, ground, view, bags, true);
    drawMirrorTorches(g, c, ground, flames, true);
    if (!g.sprites.beginMirror(g.screen, g.framebuffer, false)) return null;
    drawMirrorScenery(g, c, ground, view, bags, false);
    for (bodies) |*b| drawBody(g, b, true);
    drawMirrorTorches(g, c, ground, flames, false);
    return g.sprites.endMirror(g.framebuffer);
}

pub fn drawMap(g: *game.Game, ground: *const grid.Level) void {
    const lens_outer = g.framebuffer;
    const lens_active = g.cinema.lens.begin(g.screen, lens_outer);
    if (lens_active) g.framebuffer = g.cinema.lens.scene.?.id;
    defer if (lens_active) {
        g.cinema.lens.end(lens_outer);
        g.framebuffer = lens_outer;
    };
    g.light.composed = g.cinema.options.composed_lighting;
    effectLights(g, ground);
    const c = Cam.of(g);
    const view = viewBox(g, c);
    const lo = view.lo;
    const hi = view.hi;
    g.light.bake(ground, lo, hi);
    const aim_from: ?P = if (g.mode != .aim) null else if (g.sim.heroActor()) |a| a.at else null;
    const aim_reach = if (aim_from != null) g.sim.reachOf(g.mode.aim.act()) else 0;
    const aim_ground = if (aim_from) |from| skills.targetGround(g, from, g.mode.aim.act()) else &g.sim.lv;
    const aim_legal = if (aim_from) |from| tactics_exec.validWithReach(g, aim_ground, g.mode.aim.act(), from, g.mode.aim.mark, aim_reach) else false;

    const shown = &g.drawn.bodies;
    const stood = stoodNow(g);
    var n: usize = 0;
    var pictured = g.pic.shownBodies(&g.sim);
    while (pictured.next()) |b| {
        const at = b.at;
        const body = b.body;
        const mid = game.middle(at);
        const s = c.px(at);
        shown[n] = .{
            .pic = body.pic,
            .slot = b.slot,
            .sighted = g.pic.sighted[b.slot],
            .s = s,
            .lifted = s.sub(.{ .x = 0, .y = body.lift }),
            .mid = mid,
            .left = body.facing == .left,
            .shine = g.light.onBody(mid, g.sim.isHero(b.slot)),
            .opacity = body.opacity,
            .dark = body.dark,
            .flash = body.flash,
        };
        n += 1;
    }
    const bodies = shown[0..n];

    var flame_buf: [light.LIGHTS]light.Flame = undefined;
    const flames = g.light.flames(ground, &flame_buf);
    g.weather_blend.follow(&g.sim.locations);
    g.cinema.prepare(ground, g.light, view, flames, &g.weather_blend, if (g.debug.visuals.weather) g.pic.local_weather_shown else climate.CALM);
    const outer = g.framebuffer;
    const blooming = g.cinema.beginScene(g.screen, outer);
    if (blooming) g.framebuffer = g.cinema.scene.?.id;
    const beds = &g.drawn.beds;
    beds.fill(ground, lo, hi, !g.light.reveal_map);
    const bags = shownBags(g, ground);
    const mirror = if (g.debug.visuals.water_reflections and beds.shown.intersectWith(look.REFLECTIVE).count() > 0) drawMirrors(g, c, ground, view, &bags, bodies, flames) else null;
    const burnt = g.pic.burntShown(ground);
    drawGroundPass(g, c, ground, beds, &stood, mirror, burnt);
    var coin_cells = view.cells();
    while (coin_cells.next()) |p| {
        const cell = &g.pic.seen_cells[grid.Level.idx(p)];
        if (cell.alpha <= 0 or cell.coins <= 0 or ground.at(p).isChest() or bags.isSet(grid.Level.idx(p))) continue;
        drawCoins(g, c, .{ .at = p, .amount = cell.coins });
    }
    if (g.sim.heroSlot()) |hero| {
        if (g.pic.glide[hero].left() > 0) for (g.pic.gold_taken.slice()) |pile| {
            if (g.pic.cellAlpha(pile.at) > 0) drawCoins(g, c, pile);
        };
    }
    _ = shadowPass(g, c, ground, view, &bags, g.framebuffer);
    g.cloud.draw(ground, view, -c.x, -c.y, game.CELL, g.screen);
    drawSolidPass(g, c, ground, lo, hi, &stood, &bags);
    if (burnt) |old| drawBurntStanding(g, c, old, false);
    const o = c.origin();
    g.pic.fx.draw(o[0], o[1], game.CELL_F);
    g.light.drawMap(-c.x, -c.y, game.CELL);
    drawTacticalGround(g, c, ground, lo, hi);
    drawBraced(g, c, ground);
    drawOrbLanes(g, c, ground);
    const level_up_at = game.heroDrawnMiddle(g);
    if (level_up_at) |at| g.pic.fx.level_up.drawBeam(at, o[0], o[1], game.CELL_F);

    if (aim_from) |from| {
        const reach = grid.Box.around(from, aim_reach);
        var cells = grid.Cells.of(lo.max(reach.lo), hi.min(reach.hi));
        while (cells.next()) |p| {
            if (aim_ground.isLit(p) and tactics_exec.validWithReach(g, aim_ground, g.mode.aim.act(), from, p, aim_reach)) fillCell(c, p, look.AIM_REACH);
        }
        if (g.mode.aim.act().reticle() == .bow and aim_legal) {
            const f = skills.shownFlight(g, from, g.mode.aim.act(), g.mode.aim.mark);
            fillLit(g, c, f.path[0..f.len], look.AIM_PATH);
            switch (g.mode.aim.act()) {
                inline else => |a| if (comptime a.bursts()) if (f.impact()) |at| {
                    if (g.sim.lv.isLit(at)) {
                        const area = skillbar.Act.elemental(a).burst(&g.sim.lv, from, at, g.sim.wider());
                        fillLit(g, c, area.slice(), look.aimArea(a));
                    }
                },
            }
        }
        const act = g.mode.aim.act();
        if (act.spans()) {
            if (aim_legal) if (tactics_exec.span(g, aim_ground, act, from, g.mode.aim.anchor() orelse g.mode.aim.mark, g.mode.aim.mark)) |area| {
                for (area.slice()) |p| fillCell(c, p, if (act == .fire_wall) look.aimElement(.fire) else look.AIM_PATH);
            };
        } else switch (act) {
            .overwatch => if (mathx.toward(from, g.mode.aim.mark)) |d| {
                var covered = grid.Cells.around(from, tactics.Overwatch.RANGE);
                while (covered.next()) |p| {
                    if (tactics_exec.watches(&g.sim.lv, from, d, p)) fillCell(c, p, look.AIM_PATH);
                }
            },
            inline else => |a| if (comptime a.sweeps()) {
                const arc = skillbar.Act.skill(a).arc(aim_ground, from, g.mode.aim.mark);
                for (arc.slice()) |p| if (aim_ground.isLit(p) and (!aim_ground.at(p).solid() or !g.sim.untargetableAt(p))) fillCell(c, p, look.AIM_PATH);
            } else if (comptime a.reticle() == .ground and @hasDecl(skillbar.Act.skill(a), "area")) {
                const area = skillbar.Act.skill(a).area(&g.sim.lv, g.mode.aim.mark, g.sim.wider());
                if (aim_legal) fillLit(g, c, area.slice(), look.AIM_PATH);
            },
        }
    }

    drawPlants(g, c, flames);
    var barrels = Barrels.of(g, c, lo, hi);
    while (barrels.next()) |b| {
        drawBarrel(g, &b, false);
        if (g.sprites.barrel) |t| shineOver(g, t, spriteRect(t, b.s), mathx.cellOf(b.mid), b.shine.tint(look.LIT), false);
    }
    var npc_cells = grid.Cells.of(lo, hi);
    while (npc_cells.next()) |p| {
        const cell = &g.pic.seen_cells[grid.Level.idx(p)];
        const i = cell.npc orelse continue;
        if (cell.alpha <= 0) continue;
        const f = Prop.at(g, c, p, false);
        const body = if (g.sim.script()) |s| if (i < s.npc_n) s.npc[i].looks else null else null;
        const tex = if (body) |k| g.sprites.body(k) else null;
        const l = if (body) |k| look.body(k) else look.NPC;
        drawFigure(g, tex, l, f.s, false, f.mid, &f.shine, 0, cell.alpha);
    }
    var order_buf: [actor.MAX]u8 = undefined;
    const order = order_buf[0..n];
    for (order, 0..) |*o_i, i| o_i.* = @intCast(i);
    std.sort.insertion(u8, order, bodies, struct {
        fn less(all: []const Shown, a: u8, b: u8) bool {
            return all[a].mid[1] < all[b].mid[1];
        }
    }.less);
    if (burnt) |old| drawBurntStanding(g, c, old, true);
    var next_body: usize = 0;
    var run: OccluderRun = .{};
    const crossed = behindWalls(bodies);
    var occluders = view.grown(1).cells();
    while (occluders.next()) |p| {
        const kind = ground.at(p);
        const fronts = look.occludes(kind) or (insideSet(&crossed, p) and walled(ground, p));
        if (!fronts or !footprintSeen(g, p, kind)) continue;
        const depth = mathx.centre(p)[1];
        while (next_body < order.len and bodies[order[next_body]].mid[1] <= depth) : (next_body += 1) {
            run.end();
            drawStandingBody(g, &bodies[order[next_body]]);
        }
        drawOccluder(g, c, ground, p, kind, &run);
        if (flamesSeen(g, p)) {
            run.end();
            drawCellFlames(g, c, p);
        }
    }
    run.end();
    for (order[next_body..]) |i| drawStandingBody(g, &bodies[i]);

    drawTorches(g, c, flames);
    g.pic.fx.drawGlow(ground, &g.light.visibility.sight, o[0], o[1], game.CELL_F);
    if (level_up_at) |at| g.pic.fx.level_up.drawSparks(at, o[0], o[1], game.CELL_F);
    if (g.debug.visuals.weather) if (g.light.sky) |k| g.rain.draw(game.weatherNow(g), g.pic.local_weather_shown, &g.weather_blend, &g.light.visibility.sight, o[0], o[1], game.CELL_F, sky.brightness(k));

    if (g.pic.shot) |s| if (s.started()) drawShot(g, s, c);
    for (&g.pic.foe_shots) |*pending| {
        const s = pending.* orelse continue;
        if (s.started()) drawShot(g, s, c);
    }
    for (&g.pic.bolts) |*pending| {
        const b = pending.* orelse continue;
        const at = b.view.at orelse continue;
        fx.drawHurl(at, b.heading(), b.element, g.pic.fx.seconds.at(), o[0], o[1], game.CELL_F, b.view.alpha);
    }
    g.cinema.drawAir(g.light, o, game.CELL_F, g.screen, g.pic.hour_shown, g.debug.visuals.water_reflections);
    if (blooming) {
        g.cinema.endScene(outer, o, game.CELL_F, g.light);
        g.framebuffer = outer;
    }

    for (order) |i| {
        const b = &bodies[i];
        if (b.pic.kind.hero() or b.pic.down()) continue;
        const x_bar = b.s.x + BODY_BAR_INSET;
        const y_bar = b.s.y + game.CELL - BODY_BAR_H - BODY_BAR_LIFT;
        const back = look.fade(look.BG, b.sighted);
        const chill = b.pic.status.get(.chilled);
        if (chill > 0) pips(x_bar, y_bar - CHILL_BAR_GAP - CHILL_BAR_H, BODY_BAR_W, chill, glacial.TURNS, look.fade(look.ailmentInk(.chill), b.sighted), back);
        if (!b.pic.hurt()) continue;
        raster.meter(x_bar, y_bar, BODY_BAR_W, BODY_BAR_H, b.pic.hp, b.pic.max, back, look.fade(look.LIFE, b.sighted));
        const resistance = b.pic.resilience.peak().percent;
        if (resistance > 0) raster.meter(x_bar, y_bar + BODY_BAR_H + RESIST_BAR_GAP, BODY_BAR_W, RESIST_BAR_H, resistance, mathx.PERCENT, back, look.fade(look.UI_GOLD, b.sighted));
    }

    if (aim_from != null) outline(c, g.mode.aim.mark, if (aim_legal) look.RETICLE else look.RETICLE_BLOCKED);
    if (game.playShown(g) and g.st.lean) drawLean(g, c, ground, &stood);

    for (order) |i| {
        const b = &bodies[i];
        g.pic.fx.drawSpeech(&g.face, b.slot, b.lifted.x, b.lifted.y, game.CELL_F, b.shine.sight * b.sighted);
    }
    if (level_up_at) |at| g.pic.fx.level_up.drawText(at, &g.face, o[0], o[1], game.CELL_F);
}

/// Cells a body overlaps from behind, its feet north of their middle: a gliding body is in front of none of them.
fn behindWalls(bodies: []const Shown) grid.CellSet {
    var out = grid.CellSet.initEmpty();
    for (bodies) |*b| {
        var near = grid.Cells.around(mathx.cellOf(b.mid), 1);
        while (near.next()) |q| {
            if (grid.Level.inside(q) and overlapsFromBehind(b.mid, q)) out.set(grid.Level.idx(q));
        }
    }
    return out;
}

fn overlapsFromBehind(mid: [2]f32, q: P) bool {
    const m = mathx.centre(q);
    return @abs(m[0] - mid[0]) < 1 and m[1] > mid[1] and m[1] - mid[1] < 1;
}

test "a body crossing a wall's top corner is behind it; one beside, above or below it is not" {
    const wall = P{ .x = 5, .y = 5 };
    for ([_][2]f32{ .{ 5.0, 5.0 }, .{ 6.0, 5.0 }, .{ 4.8, 4.8 } }) |crossing| try std.testing.expect(overlapsFromBehind(crossing, wall));
    for ([_][2]f32{ .{ 4.5, 5.5 }, .{ 6.5, 5.5 }, .{ 5.5, 4.5 }, .{ 5.5, 6.5 }, .{ 5.0, 6.0 } }) |clear| try std.testing.expect(!overlapsFromBehind(clear, wall));
}

fn walled(ground: *const grid.Level, p: P) bool {
    const cut = sprite_assets.cutAt(ground, p) orelse return false;
    return cut == .wall or cut == .forest;
}

fn footprintSeen(g: *const game.Game, p: P, kind: grid.Tile) bool {
    var cells = kind.footprint(p).cells();
    while (cells.next()) |q| {
        if (terrainSeen(g, q)) return true;
    }
    return false;
}

const OccluderRun = struct {
    focus: ?look.Focused = null,

    fn end(self: *OccluderRun) void {
        if (self.focus == null) return;
        rl.endShaderMode();
        self.focus = null;
    }
};

fn drawOccluder(g: *game.Game, c: Cam, ground: *const grid.Level, p: P, kind: grid.Tile, run: *OccluderRun) void {
    const i = grid.Level.idx(p);
    const hidden = g.pic.occlusion[i];
    const occlusion: look.Occlusion = .{ .body = g.pic.occluder[i], .hidden = hidden };
    const tex = g.sprites.tileAt(ground, p) orelse {
        run.end();
        const l = look.tile(kind);
        drawGlyph(g, l.ch, c.corner(p), look.fade(g.light.onBody(mathx.centre(p), false).tint(l.fg), look.occlusionAlpha(hidden)));
        return;
    };
    const rect = tileRect(kind, tex, c, p);
    const focus = g.cinema.focusOf(kind, tex, mathx.centre(p), g.light.carrier) orelse look.Focused.sharp;
    const view = shaders.MapView.of(-c.x, -c.y, game.CELL, g.screen.x, g.screen.y);
    const lightmap = g.light.mapTexture();
    const fogmap = g.light.gpu.layers.get(.fog);
    const rows = cellsTall(rect.height);
    const under = grid.Box{ .lo = .{ .x = p.x, .y = p.y + 1 - rows }, .hi = kind.footprint(p).hi };
    if (hidden == 0 and lightmap != null and fogmap != null and !g.cloud.veils(under)) {
        if (run.focus == null or !std.meta.eql(run.focus.?, focus)) {
            run.end();
            if (g.sprites.beginScenery(view, lightmap.?, fogmap.?, occlusion, focus)) run.focus = focus;
        }
        if (run.focus != null) {
            raster.stretch(tex, rect, look.LIT);
            return;
        }
    }
    run.end();
    const shaded = if (lightmap != null and fogmap != null) g.sprites.drawScenery(tex, rect, view, lightmap.?, fogmap.?, occlusion, focus) else false;
    if (!shaded) raster.stretch(tex, rect, look.fade(sceneryTint(g, p), look.occlusionAlpha(hidden)));
    if (g.cloud.veils(under) and g.cloud.beginOccludedVeil(sceneryTint(g, p), focus, if (shaded) occlusion else .{})) {
        raster.stretch(tex, rect, if (shaded) look.LIT else look.fade(look.LIT, look.occlusionAlpha(hidden)));
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
        g.pic.fx.drawStatus(s, .{ .x = x, .y = y, .cell = game.CELL_F, .seed = b.slot, .ink = look.fade(b.shine.tint(s.ink()), b.sighted), .alpha = b.shine.sight * b.sighted, .stacks = b.pic.sunder.stacks });
    }
}

fn drawShot(g: *const game.Game, s: game.presentation.Shot, c: Cam) void {
    const at = s.view.at orelse return;
    const o = c.origin();
    if (!s.hook) return drawFlightAt(&s, at, o, game.CELL_F, s.view.alpha);
    const bounds = grid.Box.between(s.from, mathx.cellOf(at)).grown(1);
    var cells = bounds.cells();
    const full = while (cells.next()) |p| {
        if (!g.pic.litShown(&g.sim, p)) break false;
    } else true;
    if (full) return drawFlightAt(&s, at, o, game.CELL_F, s.view.alpha);
    cells = bounds.cells();
    while (cells.next()) |p| {
        if (!g.pic.litShown(&g.sim, p)) continue;
        const clip = fx.hookCellClip(p, o, game.CELL_F);
        rl.beginScissorMode(clip.lo.x, clip.lo.y, clip.width(), clip.height());
        fx.drawHookChain(mathx.centre(s.from), at, s.direction(), o[0], o[1], game.CELL_F, s.view.alpha);
        rl.endScissorMode();
    }
    fx.drawHookHead(at, s.direction(), o[0], o[1], game.CELL_F, s.view.alpha);
}

pub fn drawFlight(s: *const game.presentation.Shot, o: [2]f32, cell: f32) void {
    drawFlightAt(s, s.position(s.t), o, cell, 1);
}

fn drawFlightAt(s: *const game.presentation.Shot, at: [2]f32, o: [2]f32, cell: f32, alpha: f32) void {
    if (s.net) {
        fx.drawNetFaded(at, s.t, o[0], o[1], cell, alpha);
    } else if (s.hook) {
        fx.drawHookFaded(mathx.centre(s.from), at, s.direction(), o[0], o[1], cell, alpha);
    } else fx.drawMissileFaded(at, s.direction(), s.act, s.t, o[0], o[1], cell, alpha);
}

pub const Kin = std.EnumSet(mathx.Dir);

pub fn drawFlames(effects: *const fx.Fx, x: f32, y: f32, cell: f32, seed: usize, kin: Kin, alpha: f32) void {
    const h = cell / 2;
    const core = look.fade(look.FLAME_FILL, FLAME_FILL_A * alpha);
    const Quarter = struct { dx: f32, dy: f32, side_x: mathx.Dir, side_y: mathx.Dir, corner: mathx.Dir };
    for ([_]Quarter{
        .{ .dx = 0, .dy = 0, .side_x = .w, .side_y = .n, .corner = .nw },
        .{ .dx = 1, .dy = 0, .side_x = .e, .side_y = .n, .corner = .ne },
        .{ .dx = 0, .dy = 1, .side_x = .w, .side_y = .s, .corner = .sw },
        .{ .dx = 1, .dy = 1, .side_x = .e, .side_y = .s, .corner = .se },
    }) |q| {
        const across = inkIf(core, kin.contains(q.side_x));
        const along = inkIf(core, kin.contains(q.side_y));
        const far = inkIf(core, kin.contains(q.side_x) and kin.contains(q.side_y) and kin.contains(q.corner));
        const left = q.dx == 0;
        const top = q.dy == 0;
        rl.drawRectangleGradientEx(
            .{ .x = x + q.dx * h, .y = y + q.dy * h, .width = h, .height = h },
            if (left and top) far else if (left) across else if (top) along else core,
            if (left and !top) far else if (left) across else if (!top) along else core,
            if (!left and !top) far else if (!left) across else if (!top) along else core,
            if (!left and top) far else if (!left) across else if (top) along else core,
        );
    }
    effects.drawBurning(x, y, cell, seed, alpha);
}

fn flameAlpha(g: *const game.Game, i: usize) f32 {
    const cell = g.pic.seen_cells[i];
    return cell.flame * cell.alpha;
}

fn flamesSeen(g: *const game.Game, p: P) bool {
    return flameAlpha(g, grid.Level.idx(p)) > 0;
}

fn inkIf(c: rl.Color, on: bool) rl.Color {
    return if (on) c else look.fade(c, 0);
}

fn kinOf(g: *const game.Game, p: P) Kin {
    var kin = Kin.initEmpty();
    for (mathx.ALL_DIRS) |d| {
        const q = p.add(d.delta());
        if (grid.Level.inside(q) and flamesSeen(g, q)) kin.insert(d);
    }
    return kin;
}

fn drawBraced(g: *game.Game, c: Cam, ground: *const grid.Level) void {
    var pictured = g.pic.shownBodies(&g.sim);
    while (pictured.next()) |shown| {
        const b = shown.body.pic;
        const d = b.braced orelse continue;
        if (b.down()) continue;
        const at = game.cellUnder(shown.at);
        const lane = windup.lane(ground, at, d, actor.braceReach(b.kind) orelse continue);
        for (lane.slice()) |p| laneCell(g, c, p, look.BRACED, g.pic.sighted[shown.slot]);
    }
}

fn laneCell(g: *const game.Game, c: Cam, p: P, ink: rl.Color, alpha: f32) void {
    fillCell(c, p, look.fade(ink, g.pic.cellAlpha(p) * alpha));
}

fn drawOrbLanes(g: *game.Game, c: Cam, ground: *const grid.Level) void {
    for (0..g.sim.pool.n) |i| {
        const b = g.pic.bolts[i] orelse continue;
        if (fx.hurlLook(b.element) != .orb) continue;
        const at = b.view.at orelse continue;
        const hu = actor.row(g.sim.pool.items[i].kind).hurls orelse continue;
        const here = mathx.cellOf(at);
        var start: usize = 0;
        var near = mathx.dist(here, b.line.from);
        var seek = grid.Ray.init(b.line.from, b.line.toward);
        for (1..@as(usize, b.line.flown) + 1) |k| {
            const p = seek.next() orelse break;
            if (mathx.dist(p, here) < near) {
                near = mathx.dist(p, here);
                start = k;
            }
        }
        var ray = grid.Ray.init(b.line.from, b.line.toward);
        for (1..@as(usize, @intCast(hu.range)) + 1) |k| {
            const p = ray.next() orelse break;
            if (k <= start) continue;
            const e = firebolt.entryOf(ground, p, grid.Level.inside(p) and barrelShownAt(g, p));
            if (!firebolt.enters(e)) break;
            laneCell(g, c, p, look.CHAOS_LANE, b.view.alpha);
            if (e != .open) break;
        }
    }
}

fn drawTacticalGround(g: *game.Game, c: Cam, ground: *const grid.Level, lo: P, hi: P) void {
    var cells = grid.Cells.of(lo, hi);
    while (cells.next()) |p| {
        const i = grid.Level.idx(p);
        const cell = g.pic.seen_cells[i];
        if (cell.alpha <= 0) continue;
        const x = c.sx(p);
        const y = c.sy(p);
        if (cell.caltrops) {
            const gold = look.fade(look.UI_GOLD, cell.alpha);
            inline for (CALTROPS) |q| {
                const tip = P{ .x = x + game.authored(q.x), .y = y + game.authored(q.y) - CALTROP_UP };
                const left = P{ .x = x + game.authored(q.x) - CALTROP_HALF, .y = y + game.authored(q.y) + CALTROP_DOWN };
                const right = P{ .x = x + game.authored(q.x) + CALTROP_HALF, .y = left.y };
                rl.drawLine(left.x, left.y, tip.x, tip.y, gold);
                rl.drawLine(tip.x, tip.y, right.x, right.y, gold);
            }
        }
        if (cell.barrier) {
            const ward = look.fade(look.WARD, cell.alpha);
            fillCell(c, p, look.fade(look.WARD, BARRIER_FILL_A * cell.alpha));
            outline(c, p, ward);
            inline for (BARRIER_BARS) |bar_x| rl.drawLine(x + bar_x, y + BARRIER_INSET, x + bar_x, y + game.CELL - BARRIER_INSET, ward);
        }
        const burnt_over = if (g.pic.fadingBurnt(i)) |was| look.occludes(was) else false;
        if (!look.occludes(ground.at(p)) and !burnt_over) drawCellFlames(g, c, p);
    }
}

fn drawCellFlames(g: *game.Game, c: Cam, p: P) void {
    const i = grid.Level.idx(p);
    const a = flameAlpha(g, i);
    if (a > 0) drawFlames(&g.pic.fx, @floatFromInt(c.sx(p)), @floatFromInt(c.sy(p)), game.CELL_F, i, kinOf(g, p), a);
}

fn pips(x: i32, y: i32, w: i32, n: u8, of: u8, fill: rl.Color, back: rl.Color) void {
    const count: i32 = of;
    const each = @divTrunc(w - (count - 1) * CHILL_PIP_GAP, count);
    for (0..of) |k| {
        const px = x + @as(i32, @intCast(k)) * (each + CHILL_PIP_GAP);
        rl.drawRectangle(px, y, each, CHILL_BAR_H, if (k < n) fill else back);
    }
}

pub const EFFECT_SOURCES = fx.PULSES + 2;

/// Emits effect lights first, then level-up and projectile lights.
pub fn effectSources(effects: *const fx.Fx, carrier: ?[2]f32, shot: ?*const game.presentation.Shot, buf: *[EFFECT_SOURCES]light.Emission) []const light.Emission {
    var n = effects.pulseLights(buf[0..fx.PULSES]).len;
    if (carrier) |at| if (effects.level_up.emission(at)) |e| {
        _ = mathx.push(light.Emission, buf, &n, e);
    };
    if (shot) |s| if (fx.missileLight(s.position(s.t), s.act)) |e| {
        _ = mathx.push(light.Emission, buf, &n, e);
    };
    return buf[0..n];
}

pub fn effectLights(g: *game.Game, ground: *const grid.Level) void {
    g.light.clearEffects();
    if (!g.light.options.effect_lights) return;
    var buf: [EFFECT_SOURCES]light.Emission = undefined;
    for (effectSources(&g.pic.fx, g.pic.carrierAt(&g.sim), null, &buf)) |source| g.light.emit(ground, source);
    if (g.pic.shot) |s| if (s.view.at) |at| if (fx.missileLight(at, s.act)) |source| emitFaded(g, ground, source, s.view.alpha);
    var pictured = g.pic.shownBodies(&g.sim);
    while (pictured.next()) |b| {
        const i = b.slot;
        const mid = game.middle(b.at);
        const pic = b.body.pic;
        if (pic.down()) continue;
        if (look.bodyGlow(pic.kind)) |col| {
            const source = fx.BODY_GLOW.lit(mid, col, 1);
            emitFaded(g, ground, source, g.pic.sighted[i]);
        }
        const flicker = g.pic.fx.statusFlicker(@floatFromInt(i));
        const source = for (std.enums.values(fx.Status)) |s| {
            if (pic.status.get(s) > 0) if (s.emission(mid, flicker)) |e| break e;
        } else continue;
        emitFaded(g, ground, source, g.pic.sighted[i]);
    }
    for (&g.pic.bolts) |*pending| {
        const b = pending.* orelse continue;
        const at = b.view.at orelse continue;
        if (fx.hurlLight(at, b.element)) |source| emitFaded(g, ground, source, b.view.alpha);
    }
    for (0..grid.CELLS) |i| {
        const a = flameAlpha(g, i);
        if (a <= 0) continue;
        const mid = mathx.centre(grid.Level.of(i));
        emitFaded(g, ground, fx.FLAMES_GLOW.lit(mid, look.FIRE, g.pic.fx.statusFlicker(@floatFromInt(i))), a);
    }
}

fn emitFaded(g: *game.Game, ground: *const grid.Level, source: light.Emission, alpha: f32) void {
    var e = source;
    e.gain *= alpha;
    g.light.emit(ground, e);
}

/// Composite emissive plants above the light map and behind bodies.
fn drawPlants(g: *game.Game, c: Cam, flames: []const light.Flame) void {
    for (flames) |f| if (f.kind == .plant and f.live()) {
        const p = mathx.cellOf(f.at);
        const t = g.pic.tileShown(&g.sim, p);
        if (g.sprites.tileOf(t, null) != null) continue;
        const l = look.tile(t);
        drawGlyph(g, l.ch, c.corner(p), look.fade(l.fg, flameLit(f)));
    };
}

fn drawTorches(g: *game.Game, c: Cam, flames: []const light.Flame) void {
    for (flames) |f| if (f.kind == .wall) drawFlame(g, c, f, flameLit(f));
    const o = c.origin();
    g.light.drawGlows(flames, o[0], o[1], game.CELL_F, g.screen, g.framebuffer);
}

pub fn leanShown(g: *game.Game, ground: *const grid.Level, stood: *const grid.CellSet, from: P, d: mathx.Dir) game.Move {
    return leanWith(g, ground, stood, from, d, foesShown(g));
}

fn leanWith(g: *game.Game, ground: *const grid.Level, stood: *const grid.CellSet, from: P, d: mathx.Dir, foes: bool) game.Move {
    return game.moveOf(g, ground, from, d, shownAt(g, stood, from.add(d.delta())), foes);
}

fn foesShown(g: *game.Game) bool {
    for (g.sim.pool.constSlice(), 0..) |a, i| {
        if (a.foe() and !g.pic.pictured[i].down() and g.pic.drawnAt(&g.sim, i) != null) return true;
    }
    return false;
}

fn drawLean(g: *game.Game, c: Cam, ground: *const grid.Level, stood: *const grid.CellSet) void {
    const at = game.cellUnder(g.pic.heroNow(&g.sim) orelse return);
    const foes = foesShown(g);
    for (input.DPAD) |button| {
        const d = input.leanOf(button);
        const p = at.add(d.delta());
        const col = switch (leanWith(g, ground, stood, at, d, foes)) {
            .kick => look.LEAN_FOE,
            .step, .open, .gate, .burst, .loot, .talk, .swap => look.LEAN_OPEN,
            .blocked => look.LEAN_BLOCKED,
        };
        outline(c, p, col);
        if (ground.walkable(p) and !shownAt(g, stood, p)) {
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

/// Requires a live GL context.
pub const Minimap = struct {
    tex: ?rl.Texture2D = null,
    px: [grid.CELLS]rl.Color = undefined,
    /// Sight changes invalidate the minimap. Pictured tile impacts and fades can also require rebaking.
    stale: bool = true,
    fading: bool = false,
    pictured: game.presentation.Pictured = .{},

    pub fn load(m: *Minimap) void {
        m.tex = raster.canvas(grid.W, grid.H, rl.Color.blank, .point);
        m.stale = true;
    }

    pub fn unload(m: *Minimap) void {
        raster.unloadAll(m);
    }
};

pub fn miniOrigin(screen_w: i32) P {
    return .{ .x = screen_w - MINI_W - MINI_PAD - MINI_FRAME, .y = MINI_PAD + MINI_FRAME };
}

fn miniDot(o: P, p: P, grow: i32, col: rl.Color) void {
    rl.drawRectangleRec(raster.grown(raster.rect(o.x + p.x * MINI, o.y + p.y * MINI, MINI, MINI), @floatFromInt(grow)), col);
}

pub fn drawMinimap(g: *game.Game, ground: *const grid.Level) void {
    const o = miniOrigin(g.screen.x);
    const map = miniBox(g.screen.x);
    sprite.hudPanelIn(&g.sprites, miniFrame(g.screen.x), look.MINI_BG, look.LIT);
    if (g.mini.tex) |t| {
        const pictured = g.pic.pictureKey();
        if (g.mini.stale or g.mini.fading or !std.meta.eql(pictured, g.mini.pictured)) {
            g.mini.fading = false;
            for (&g.mini.px, &ground.tile, &ground.seen, &ground.lit, &g.light.visibility.memory, &g.light.visibility.sight) |*c, tile, seen, lit, memory, sight| {
                c.* = look.fade(look.mixed(look.mini(tile, false), look.mini(tile, true), sight), memory);
                g.mini.fading = g.mini.fading or memory != light_visibility.mask(seen or g.light.reveal_map) or sight != light_visibility.mask(lit);
            }
            rl.updateTexture(t, &g.mini.px);
            g.mini.stale = false;
            g.mini.pictured = pictured;
        }
        raster.stretch(t, map, look.LIT);
    }
    var bodies = g.pic.shownBodies(&g.sim);
    while (bodies.next()) |b| {
        if (!g.sim.pool.items[b.slot].foe()) continue;
        miniDot(o, game.cellUnder(b.at), 0, look.fade(look.MINI_FOE, g.pic.sighted[b.slot] * b.body.opacity));
    }
    if (g.pic.heroNow(&g.sim)) |at| miniDot(o, game.cellUnder(at), MINI_HERO_GROW, look.MINI_HERO);
    const v = miniView(Cam.of(g), g.screen);
    rl.drawRectangleLines(o.x + v.lo.x, o.y + v.lo.y, v.width(), v.height(), look.MINI_VIEW);
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
    return .{ .x0 = m.x + DAY_INSET, .x1 = m.x + MINI_W - DAY_INSET, .y = raster.bottom(f) + DAY_GAP };
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
        const a = mathx.spoke(@floatFromInt(i), SUN_RAYS);
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
