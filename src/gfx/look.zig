const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const damage = @import("../play/damage.zig");
const items = @import("../play/items.zig");
const skillbar = @import("../play/skillbar.zig");
const resilience = @import("../play/resilience.zig");
const font = @import("font.zig");
const ground = @import("ground.zig");
const sky = @import("sky.zig");
const line_icons = @import("line_icons.zig");
const shaders = @import("shaders.zig");
const raster = @import("raster.zig");
const embedded = @import("assets").names;

pub const SPRITE_PX: i32 = 64;

pub fn pxScale(cell: f32) f32 {
    return cell / SPRITE_PX;
}
/// A faced wall's bottom rows of brick, as `tools/tile_art/export_walls.lua` paints them.
pub const WALL_FACE_PX: i32 = 23;
/// A body or tile with no sprite draws its glyph this big, at `SPRITE_PX`.
pub const GLYPH_PX: i32 = 60;

pub const Look = struct {
    ch: u8,
    fg: rl.Color,
};

pub const Bodies = std.EnumArray(actor.Kind, ?rl.Texture2D);

const Shadow = enum { silhouette, canopy };

const STANDS = std.EnumArray(grid.Tile, ?Shadow).initDefault(@as(?Shadow, null), .{
    .shrub = .canopy,
    .swamp_tree = .canopy,
    .large_tree = .canopy,
    .tiny_shrub = .canopy,
    .boulder = .silhouette,
    .fungus = .silhouette,
    .tall_grass = .silhouette,
    .shrooms = .silhouette,
    .chest = .silhouette,
    .chest_open = .silhouette,
});

const STANDING = blk: {
    var n: usize = 0;
    for (STANDS.values) |s| {
        if (s != null) n += 1;
    }
    var out: [n]grid.Tile = undefined;
    var i: usize = 0;
    for (std.enums.values(grid.Tile)) |t| {
        if (STANDS.get(t) == null) continue;
        out[i] = t;
        i += 1;
    }
    break :blk out;
};

pub fn stands(t: grid.Tile) bool {
    return STANDS.get(t) != null;
}

pub fn canopied(t: grid.Tile) bool {
    return STANDS.get(t) == .canopy;
}

pub fn tall(t: grid.Tile) bool {
    return t == .large_tree;
}

pub fn occludes(t: grid.Tile) bool {
    return tall(t) or t == .reeds;
}

pub const OCCLUDED_A: f32 = 0.4;

pub const Occlusion = struct {
    body: [2]f32 = .{ 0, 0 },
    hidden: f32 = 0,

    pub fn set(self: Occlusion, shader: rl.Shader, at: i32, hidden: i32) void {
        shaders.setUniform(shader, at, self.body);
        shaders.setUniform(shader, hidden, self.hidden);
    }
};

pub const OCCLUSION_FS = shaders.glslConsts(.{ .OCCLUDED_A = OCCLUDED_A, .OCCLUSION_RADIUS = [2]f32{ 0.6, 0.85 }, .OCCLUSION_INNER = @as(f32, 0.35) }) ++
    \\uniform vec2 body;
    \\uniform float hidden;
    \\float occlusionAt(vec2 p) {
    \\    float distance = length((p - body) / OCCLUSION_RADIUS);
    \\    float aperture = 1.0 - smoothstep(OCCLUSION_INNER, 1.0, distance);
    \\    return mix(1.0, OCCLUDED_A, hidden * aperture);
    \\}
;

pub fn occlusionAlpha(hidden: f32) f32 {
    return mathx.lerpF(1, OCCLUDED_A, hidden);
}

pub fn tileRect(t: grid.Tile, tex: rl.Texture2D, cell: rl.Rectangle) rl.Rectangle {
    const height = cell.width * @as(f32, @floatFromInt(tex.height)) / @as(f32, @floatFromInt(tex.width));
    return .{ .x = cell.x, .y = cell.y + if (tall(t)) cell.height - height else (cell.height - height) / 2, .width = cell.width, .height = height };
}

/// Every sprite that throws a shadow from its feet: bodies, barrel, standing tiles, forest shapes, item bags and a mimic's chest.
pub const FIGURES: usize = LIT_FIGURES + STANDING.len + WALL_MASKS.len + PROP_FIGURES;
const PROP_FIGURES = 3;
/// The first of `figures`, the bodies and the barrel, which the body shader lights from their normals.
pub const LIT_FIGURES: usize = Bodies.len + 1;

pub const Assets = struct {
    bodies: std.EnumSet(actor.Kind) = .initEmpty(),
    tiles: std.EnumSet(grid.Tile) = .initEmpty(),
    wall: std.StaticBitSet(WALL_MASKS.len) = .initEmpty(),
    forest: std.StaticBitSet(WALL_MASKS.len) = .initEmpty(),
    grounds: ground.Grounds = .initEmpty(),
    grass2: bool = false,
    brush: bool = false,
    flowers: bool = false,
    barrel: bool = false,
    item_bag: bool = false,
    chest_item_bag: bool = false,
    mimic_closed: bool = false,
    small_coins: bool = false,
    large_coins: bool = false,

    pub fn of(lv: *const grid.Level) Assets {
        var need = Assets{ .item_bag = true, .small_coins = true, .large_coins = true };
        for (lv.tile, lv.barrel, 0..) |t, barrel, i| {
            const p = grid.Level.of(i);
            need.decor(t, p);
            need.barrel = need.barrel or barrel or (lv.seen[i] and lv.barrel_seen[i]);
            need.chest_item_bag = need.chest_item_bag or t.isChest();
            if (t.opened()) |open| need.add(.{ .tile = open });
            if (standsOver(t)) {
                if (cutAt(lv, p)) |c| need.add(c);
            }
            const g = ground.bedAt(lv, p, false) orelse continue;
            need.bed(g);
            if (under(t)) |u| need.bed(ground.of(u).?);
        }
        return need;
    }

    /// The ground `t` a mimic's chest stands on at `p`, ready for when the chest is flung open.
    pub fn beneath(need: *Assets, t: grid.Tile, p: mathx.P) void {
        need.decor(t, p);
        if (standsOver(t)) if (cutOf(t, null)) |c| need.add(c);
        if (ground.of(t)) |g| need.bed(g);
        if (under(t)) |u| need.bed(ground.of(u).?);
    }

    fn decor(need: *Assets, t: grid.Tile, p: mathx.P) void {
        if (grassDecor(t, p)) |d| switch (d) {
            .brush => need.brush = true,
            .flowers => need.flowers = true,
        };
    }

    fn bed(need: *Assets, g: ground.Ground) void {
        need.grass2 = need.grass2 or g == .grass;
        if (GROUND_SHEETS.contains(g)) need.grounds.insert(g) else need.add(.{ .tile = g.tile() });
    }

    fn add(need: *Assets, c: Cut) void {
        switch (c) {
            .tile => |t| if (TILE_PNGS.get(t) != null) need.tiles.insert(t),
            .wall => |i| need.wall.set(i),
            .forest => |i| need.forest.set(i),
        }
    }

    pub fn body(need: *Assets, k: actor.Kind) void {
        need.bodies.setUnion(actor.descent(k).intersectWith(PICTURED));
    }

    /// Preload every editor asset so painting does not decode sheets mid-stroke.
    pub fn everything() Assets {
        var all = Assets{ .grounds = GROUND_SHEETS, .bodies = PICTURED, .wall = .initFull(), .forest = .initFull() };
        inline for (std.meta.fields(Assets)) |f| {
            if (f.type == bool) @field(all, f.name) = true;
        }
        for (std.enums.values(grid.Tile)) |t| all.add(.{ .tile = t });
        return all;
    }

    pub fn merge(a: Assets, b: Assets) Assets {
        var out: Assets = undefined;
        inline for (std.meta.fields(Assets)) |f| {
            const x = @field(a, f.name);
            const y = @field(b, f.name);
            @field(out, f.name) = if (f.type == bool) x or y else x.unionWith(y);
        }
        return out;
    }

    pub fn count(need: Assets) usize {
        var n: usize = 0;
        inline for (std.meta.fields(Assets)) |f| {
            const x = @field(need, f.name);
            n += if (f.type == bool) @intFromBool(x) else x.count();
        }
        return n;
    }
};

fn listed(comptime name: []const u8) bool {
    @setEvalBranchQuota(10_000);
    for (embedded) |n| {
        if (std.mem.eql(u8, n, name)) return true;
    }
    return false;
}

fn optionalPng(comptime name: []const u8) ?[]const u8 {
    return if (comptime listed(name)) @embedFile(name) else null;
}

const GROUND_PNGS = blk: {
    var pngs = std.EnumArray(ground.Ground, ?[]const u8).initFill(null);
    for (std.enums.values(ground.Ground)) |g| pngs.set(g, optionalPng(g.png()));
    break :blk pngs;
};

pub const GROUND_SHEETS = blk: {
    var s = ground.Grounds.initEmpty();
    for (std.enums.values(ground.Ground)) |g| {
        const png = GROUND_PNGS.get(g) orelse continue;
        std.debug.assert(std.meta.eql(pngSize(png), mathx.P{ .x = ground.COLS * SPRITE_PX, .y = ground.ROWS * SPRITE_PX }));
        s.insert(g);
    }
    break :blk s;
};

pub const Piece = struct { tex: rl.Texture2D, src: rl.Rectangle };

pub const Mirrors = struct { live: rl.Texture2D, memory: rl.Texture2D };

pub const WaterView = struct {
    screen: [2]f32,
    visibility: rl.Texture2D,
    glints: rl.Texture2D,
    mirror: ?Mirrors = null,
};

const WaterShader = struct { shader: rl.Shader, origin: i32, cell: i32, screen: i32, depth: i32, visibility: i32, glints: i32, mirror: i32, memory: i32, mirrored: i32 };

const SceneryShader = struct { shader: rl.Shader, origin: i32, cell: i32, screen: i32, lightmap: i32, fogmap: i32, body: i32, hidden: i32, texel: i32, strength: i32 };

/// Needs a live GL context.
pub const Sprites = struct {
    bodies: Bodies = .initFill(null),
    grass2: ?rl.Texture2D = null,
    brush: ?rl.Texture2D = null,
    flowers: ?rl.Texture2D = null,
    barrel: ?rl.Texture2D = null,
    item_bag: ?rl.Texture2D = null,
    chest_item_bag: ?rl.Texture2D = null,
    mimic_closed: ?rl.Texture2D = null,
    small_coins: ?rl.Texture2D = null,
    large_coins: ?rl.Texture2D = null,
    tiles: std.EnumArray(grid.Tile, ?rl.Texture2D) = .initFill(null),
    /// In the sheet's order, `WALL_MASKS`.
    wall: [WALL_MASKS.len]?rl.Texture2D = @splat(null),
    forest: [WALL_MASKS.len]?rl.Texture2D = @splat(null),
    /// Each ground's whole sheet, drawn a piece at a time so a ground's pieces batch.
    grounds: std.EnumArray(ground.Ground, ?rl.Texture2D) = .initFill(null),
    /// Every skill's icon side by side, in `skillbar.Act`'s order, inked once rather than every frame.
    skills: ?rl.Texture2D = null,
    /// Every item kind's icon at each `line_icons.ItemSize`, a strip per size.
    item_icons: ?rl.Texture2D = null,
    hud_border: ?rl.Texture2D = null,
    log_fade: ?FadeShader = null,
    water: ?WaterShader = null,
    shine: ?ShineShader = null,
    scenery: ?SceneryShader = null,
    mirror: ?rl.RenderTexture2D = null,
    mirror_memory: ?rl.RenderTexture2D = null,

    pub fn loadCommon(self: *Sprites) void {
        self.skills = line_icons.skillIcons();
        self.item_icons = line_icons.itemIcons();
        self.hud_border = texture(HUD_BORDER_PNG);
        self.log_fade = shaders.program(FadeShader, FADE_FS);
        self.water = shaders.program(WaterShader, WATER_FS);
        self.shine = shaders.program(ShineShader, SHINE_FS);
        self.scenery = shaders.program(SceneryShader, SCENERY_FS);
    }

    pub fn drawScenery(self: *const Sprites, tex: rl.Texture2D, dest: rl.Rectangle, view: shaders.MapView, lightmap: rl.Texture2D, fogmap: rl.Texture2D, occlusion: Occlusion, focus: Focused) bool {
        const s = self.scenery orelse return false;
        rl.beginShaderMode(s.shader);
        defer rl.endShaderMode();
        shaders.setMapView(s, view);
        occlusion.set(s.shader, s.body, s.hidden);
        focus.set(s.shader, s.texel, s.strength);
        rl.setShaderValueTexture(s.shader, s.lightmap, lightmap);
        rl.setShaderValueTexture(s.shader, s.fogmap, fogmap);
        raster.stretch(tex, dest, LIT);
        return true;
    }

    /// `t` again over itself at `dest`, as the band at `sweep` crosses it.
    pub fn drawShine(self: *const Sprites, t: rl.Texture2D, dest: rl.Rectangle, sweep: f32, col: rl.Color) void {
        const s = self.shine orelse return;
        rl.beginShaderMode(s.shader);
        defer rl.endShaderMode();
        shaders.setUniform(s.shader, s.sweep, sweep);
        raster.stretch(t, dest, col);
    }

    pub fn sync(self: *Sprites, need: Assets) void {
        inline for (comptime std.meta.fieldNames(@TypeOf(SOURCES))) |name| {
            const held = &@field(self, name);
            const wants = @field(need, name);
            const src = @field(SOURCES, name);
            switch (@typeInfo(@TypeOf(held.*))) {
                .optional => syncTexture(held, wants, src),
                .array => syncShapes(held, wants, src),
                else => for (std.enums.values(@TypeOf(wants).Key)) |k| syncTexture(held.getPtr(k), wants.contains(k), src.get(k)),
            }
        }
    }

    fn groundPiece(self: *const Sprites, g: ground.Ground, mask: u4, p: mathx.P) ?Piece {
        if (g == .grass and mask == ground.FULL and cellHash(GRASS2_SEED, p) % GRASS2_IN == 0) {
            if (self.grass2) |tex| return .{ .tex = tex, .src = raster.whole(tex) };
        }
        const tex = self.grounds.getPtrConst(g).* orelse return null;
        const at = ground.CELL_OF[mask];
        return .{ .tex = tex, .src = sheetCell(at.x, at.y) };
    }

    /// The grounds with a sheet loaded.
    pub fn sheets(self: *const Sprites) ground.Grounds {
        var s = ground.Grounds.initEmpty();
        for (std.enums.values(ground.Ground)) |g| s.setPresent(g, self.grounds.getPtrConst(g).* != null);
        return s;
    }

    /// Draw lowest layers first; `origin` is cell (0, 0)'s top-left and `px` is pixels per cell.
    pub fn drawGround(self: *const Sprites, lv: *const grid.Level, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView) void {
        const sheeted = self.sheets();
        for (ground.LAYERS) |gr| {
            if (!beds.shown.contains(gr)) continue;
            const sheet = sheeted.contains(gr);
            const depth = if (sheet) waterDepth(gr) else null;
            const reflective = if (depth) |d| self.beginWater(water, origin, px, d) else false;
            defer if (reflective) rl.endShaderMode();
            if (!sheet) {
                var cells = grid.Cells.of(beds.lo, beds.hi);
                while (cells.next()) |p| {
                    if (beds.ground(p) == gr) self.squarePart(gr.tile(), cellAt(origin, p, px), px, .{ 0, 0 }, 1);
                }
            }
            var points = beds.points();
            while (points.next()) |p| {
                const here = beds.pointAt(p);
                if (!here.has(gr)) continue;
                if (sheet) {
                    const piece = self.groundPiece(gr, here.corners.mask(gr), p) orelse continue;
                    const at = cellAt(origin, p, px);
                    raster.blit(piece.tex, piece.src, .{ .x = at[0] - px / 2, .y = at[1] - px / 2, .width = px, .height = px }, LIT);
                    continue;
                }
                const under_ = here.corners.under(gr, sheeted);
                if (under_ == 0) continue;
                for (ground.AROUND) |a| {
                    if (under_ & a.bit == 0) continue;
                    const toward: [2]f32 = .{ @floatFromInt(-a.d.x), @floatFromInt(-a.d.y) };
                    self.squarePart(gr.tile(), cellAt(origin, p.add(a.d), px), px, .{ toward[0] / 2, toward[1] / 2 }, 0.5);
                }
            }
            if (gr == .grass) {
                var cells = grid.Cells.of(beds.lo, beds.hi);
                while (cells.next()) |p| {
                    if (beds.ground(p) != .grass) continue;
                    const decor = grassDecor(lv.at(p), p) orelse continue;
                    const tex = (switch (decor) {
                        .brush => self.brush,
                        .flowers => self.flowers,
                    }) orelse continue;
                    const at = cellAt(origin, p, px);
                    raster.stretch(tex, .{ .x = at[0], .y = at[1], .width = px, .height = px }, LIT);
                }
            }
        }
    }

    fn beginWater(self: *const Sprites, view: ?WaterView, origin: [2]f32, px: f32, depth: f32) bool {
        const v = view orelse return false;
        const s = self.water orelse return false;
        rl.beginShaderMode(s.shader);
        shaders.setMapView(s, .{ .origin = origin, .cell = px, .screen = v.screen });
        shaders.setUniform(s.shader, s.depth, depth);
        shaders.setUniform(s.shader, s.mirrored, @as(i32, @intFromBool(v.mirror != null)));
        rl.setShaderValueTexture(s.shader, s.visibility, v.visibility);
        rl.setShaderValueTexture(s.shader, s.glints, v.glints);
        if (v.mirror) |m| {
            rl.setShaderValueTexture(s.shader, s.mirror, m.live);
            rl.setShaderValueTexture(s.shader, s.memory, m.memory);
        }
        return true;
    }

    pub fn beginMirror(self: *Sprites, screen: mathx.P, outer: u32, memory: bool) bool {
        if (self.water == null) return false;
        if (!raster.beginTarget(if (memory) &self.mirror_memory else &self.mirror, screen, outer, rl.Color.blank)) return false;
        rl.gl.rlDisableBackfaceCulling();
        return true;
    }

    pub fn endMirror(self: *const Sprites, outer: u32) Mirrors {
        rl.gl.rlDrawRenderBatchActive();
        rl.gl.rlEnableBackfaceCulling();
        raster.endTarget(outer);
        return .{ .live = self.mirror.?.texture, .memory = self.mirror_memory.?.texture };
    }

    fn cellAt(origin: [2]f32, p: mathx.P, px: f32) [2]f32 {
        return .{ origin[0] + @as(f32, @floatFromInt(p.x)) * px, origin[1] + @as(f32, @floatFromInt(p.y)) * px };
    }

    /// The part of a ground's square from `uv` across `span`, fractions of the cell: its picture, else its colour.
    fn squarePart(self: *const Sprites, t: grid.Tile, cell: [2]f32, px: f32, uv: [2]f32, span: f32) void {
        const dest = rl.Rectangle{ .x = cell[0] + uv[0] * px, .y = cell[1] + uv[1] * px, .width = span * px, .height = span * px };
        if (self.tiles.getPtrConst(t).*) |tex| {
            const w, const h = raster.sizeOf(tex);
            raster.blit(tex, .{ .x = uv[0] * w, .y = uv[1] * h, .width = span * w, .height = span * h }, dest, LIT);
        } else if (tileBg(t)) |bg| rl.drawRectangleRec(dest, bg);
    }

    pub fn unload(self: *Sprites) void {
        unloadAll(self);
    }

    pub fn body(self: *const Sprites, k: actor.Kind) ?rl.Texture2D {
        return self.bodies.getPtrConst(k).*;
    }

    pub fn figures(self: *const Sprites) [FIGURES]?rl.Texture2D {
        var standing: [STANDING.len]?rl.Texture2D = undefined;
        for (STANDING, &standing) |t, *s| s.* = self.tiles.getPtrConst(t).*;
        const props: [PROP_FIGURES]?rl.Texture2D = .{ self.item_bag, self.chest_item_bag, self.mimic_closed };
        return self.litFigures() ++ standing ++ self.forest ++ props;
    }

    fn litFigures(self: *const Sprites) [LIT_FIGURES]?rl.Texture2D {
        return self.bodies.values ++ [_]?rl.Texture2D{self.barrel};
    }

    pub fn tileAt(self: *const Sprites, lv: *const grid.Level, p: mathx.P) ?rl.Texture2D {
        return self.cut(cutAt(lv, p) orelse return null);
    }

    pub fn tileOf(self: *const Sprites, t: grid.Tile, shape: ?grid.WallShape) ?rl.Texture2D {
        return self.cut(cutOf(t, shape) orelse return null);
    }

    fn cut(self: *const Sprites, c: Cut) ?rl.Texture2D {
        return switch (c) {
            .tile => |t| self.tiles.getPtrConst(t).*,
            .wall => |i| self.wall[i],
            .forest => |i| self.forest[i],
        };
    }

    pub fn count(self: *const Sprites) usize {
        return self.resident().count();
    }

    pub fn resident(self: *const Sprites) Assets {
        var held = Assets{};
        inline for (std.meta.fields(Assets)) |f| {
            const have = &@field(self, f.name);
            const out = &@field(held, f.name);
            switch (@typeInfo(@TypeOf(have.*))) {
                .optional => out.* = have.* != null,
                .array => for (have.*, 0..) |t, i| out.setValue(i, t != null),
                else => for (std.enums.values(@TypeOf(out.*).Key)) |k| out.setPresent(k, have.getPtrConst(k).* != null),
            }
        }
        return held;
    }

    fn keep(t: *?rl.Texture2D, needed: bool) void {
        if (needed) return;
        if (t.*) |held| rl.unloadTexture(held);
        t.* = null;
    }

    fn syncTexture(t: *?rl.Texture2D, needed: bool, png: ?[]const u8) void {
        keep(t, needed);
        if (needed and t.* == null) t.* = texture(png orelse return);
    }

    fn syncShapes(held: *[WALL_MASKS.len]?rl.Texture2D, need: std.StaticBitSet(WALL_MASKS.len), png: []const u8) void {
        var missing = false;
        for (held, 0..) |*t, i| {
            keep(t, need.isSet(i));
            missing = missing or (need.isSet(i) and t.* == null);
        }
        if (!missing) return;
        const sheet = rl.loadImageFromMemory(".png", png) catch return;
        defer rl.unloadImage(sheet);
        for (held, 0..) |*t, i| {
            if (need.isSet(i) and t.* == null) t.* = toTexture(wallCell(sheet, i) orelse continue);
        }
    }

    fn texture(png: []const u8) ?rl.Texture2D {
        return toTexture(rl.loadImageFromMemory(".png", png) catch return null);
    }

    pub fn toTexture(img: rl.Image) ?rl.Texture2D {
        defer rl.unloadImage(img);
        return rl.loadTextureFromImage(img) catch null;
    }
};

const HUD_BORDER_PNG = @embedFile("hud-border.png");
pub const HUD_BORDER_CUT: i32 = 9;

pub fn hudPanel(sprites: *const Sprites, x: i32, y: i32, width: i32, height: i32, fill: rl.Color, tint: rl.Color) void {
    rl.drawRectangle(x, y, width, height, fill);
    hudBorder(sprites, x, y, width, height, tint);
}

pub fn hudPanelIn(sprites: *const Sprites, r: rl.Rectangle, fill: rl.Color, tint: rl.Color) void {
    hudPanel(sprites, @intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height), fill, tint);
}

fn hudBorder(sprites: *const Sprites, x: i32, y: i32, width: i32, height: i32, tint: rl.Color) void {
    const tex = sprites.hud_border orelse {
        rl.drawRectangleLines(x, y, width, height, tint);
        return;
    };
    const cut = HUD_BORDER_CUT;
    if (width < cut * 2 or height < cut * 2) return;
    const size = comptime pngSize(HUD_BORDER_PNG);
    const sx = [_]i32{ 0, cut, size.x - cut };
    const sy = [_]i32{ 0, cut, size.y - cut };
    const sw = [_]i32{ cut, size.x - cut * 2, cut };
    const sh = [_]i32{ cut, size.y - cut * 2, cut };
    const dx = [_]i32{ x, x + cut, x + width - cut };
    const dy = [_]i32{ y, y + cut, y + height - cut };
    const dw = [_]i32{ cut, width - cut * 2, cut };
    const dh = [_]i32{ cut, height - cut * 2, cut };
    for (0..3) |row| {
        for (0..3) |col| {
            if (row == 1 and col == 1) continue;
            var yy: i32 = 0;
            while (yy < dh[row]) : (yy += sh[row]) {
                var xx: i32 = 0;
                while (xx < dw[col]) : (xx += sw[col]) {
                    const w = @min(sw[col], dw[col] - xx);
                    const h = @min(sh[row], dh[row] - yy);
                    rl.drawTextureRec(tex, raster.rect(sx[col], sy[row], w, h), raster.vec(.{ .x = dx[col] + xx, .y = dy[row] + yy }), tint);
                }
            }
        }
    }
}

const BODY_PNGS = std.EnumArray(actor.Kind, ?[]const u8).init(.{
    .archer = @embedFile("archer.png"),
    .wizard = @embedFile("wizard.png"),
    .knight = @embedFile("knight.png"),
    .rat = @embedFile("rat.png"),
    .slime = @embedFile("slime.png"),
    .slime_half = @embedFile("slime-half.png"),
    .slime_quarter = @embedFile("slime-quarter.png"),
    .bloat = @embedFile("bloat.png"),
    .pib = @embedFile("pib.png"),
    .beefy_pib = @embedFile("beefy-pib.png"),
    .bandit_crossbowman = @embedFile("bandit-crossbowman.png"),
    .bandit_netter = null,
    .bandit_shieldbearer = null,
    .frost_wisp = null,
    .pyre_bloat = null,
    .pib_shaman = null,
    .bog_leech = null,
    .mimic = @embedFile("mimic-open.png"),
});

const PICTURED = blk: {
    var s = std.EnumSet(actor.Kind).initEmpty();
    for (std.enums.values(actor.Kind)) |k| s.setPresent(k, BODY_PNGS.get(k) != null);
    break :blk s;
};

/// A wall's are cut from `WALLS_PNG` by its shape instead, and a forest's shrubs from `FOREST_PNG`.
const TILE_PNGS = std.EnumArray(grid.Tile, ?[]const u8).initDefault(@as(?[]const u8, null), .{
    .floor = @embedFile("floor.png"),
    .grass = @embedFile("grass.png"),
    .reeds = @embedFile("reeds.png"),
    .shrub = @embedFile("shrub.png"),
    .swamp_tree = @embedFile("swamp-tree.png"),
    .large_tree = @embedFile("large-tree.png"),
    .tiny_shrub = @embedFile("tiny-shrub.png"),
    .boulder = @embedFile("boulder.png"),
    .fungus = @embedFile("tall-shroom.png"),
    .tall_grass = @embedFile("tall-grass.png"),
    .shrooms = @embedFile("small-shrooms.png"),
    .chest = @embedFile("chest.png"),
    .chest_open = @embedFile("chest-open.png"),
});

comptime {
    std.debug.assert(TILE_PNGS.get(.wall) == null);
    std.debug.assert(std.meta.eql(pngSize(TILE_PNGS.get(.large_tree).?), mathx.P{ .x = SPRITE_PX, .y = 2 * SPRITE_PX }));
    for (std.enums.values(grid.Tile)) |t| {
        if (!standsOver(t)) continue;
        const size = pngSize(TILE_PNGS.get(t) orelse continue);
        if (size.x != SPRITE_PX or (size.y > SPRITE_PX) != tall(t)) @compileError(@tagName(t) ++ ": a standing picture is a sprite wide, and taller only when `tall`");
    }
    for (STANDING) |t| {
        if (TILE_PNGS.get(t) == null) @compileError("a standing tile casts from its picture: " ++ @tagName(t));
    }
}

const WALLS_PNG = @embedFile("walls.png");
const FOREST_PNG = @embedFile("forest-tree-walls.png");

const SOURCES = .{
    .bodies = BODY_PNGS,
    .tiles = TILE_PNGS,
    .grounds = GROUND_PNGS,
    .grass2 = @as([]const u8, @embedFile("grass2.png")),
    .brush = @as([]const u8, @embedFile("brush.png")),
    .flowers = @as([]const u8, @embedFile("flowers.png")),
    .barrel = @as([]const u8, @embedFile("barrel.png")),
    .item_bag = @as([]const u8, @embedFile("item-bag.png")),
    .chest_item_bag = @as([]const u8, @embedFile("chest-item-bag.png")),
    .mimic_closed = @as([]const u8, @embedFile("mimic-closed.png")),
    .small_coins = @as([]const u8, @embedFile("small-coins.png")),
    .large_coins = @as([]const u8, @embedFile("large-coins.png")),
    .wall = @as([]const u8, WALLS_PNG),
    .forest = @as([]const u8, FOREST_PNG),
};

comptime {
    const want = std.meta.fieldNames(Assets);
    std.debug.assert(want.len == std.meta.fieldNames(@TypeOf(SOURCES)).len);
    for (want) |n| std.debug.assert(@hasField(@TypeOf(SOURCES), n));
}

comptime {
    std.debug.assert(std.meta.eql(pngSize(WALLS_PNG), pngSize(FOREST_PNG)));
}

/// One lone shrub in this many is a forest clump, the rest `shrub.png`; which ones by a hash of the cell.
const LONE_CLUMP_IN: u64 = 3;
const LONE_CLUMP_SEED: u64 = 0xF02E57;
/// One whole grass piece in this many draws `grass2.png`; one grass cell in `DECOR_IN` takes brush, one more flowers.
const GRASS2_IN: u64 = 3;
const GRASS2_SEED: u64 = 0x62A552;
const DECOR_IN: u64 = 20;
const DECOR_SEED: u64 = 0xB2754;

const GrassDecor = enum { brush, flowers };

fn grassDecor(t: grid.Tile, p: mathx.P) ?GrassDecor {
    if (t != .grass) return null;
    return switch (cellHash(DECOR_SEED, p) % DECOR_IN) {
        0 => .brush,
        1 => .flowers,
        else => null,
    };
}

fn loneClump(p: mathx.P) bool {
    return cellHash(LONE_CLUMP_SEED, p) % LONE_CLUMP_IN == 0;
}

fn cellHash(seed: u64, p: mathx.P) u64 {
    const coordinates = [2]i32{ p.x, p.y };
    return std.hash.Wyhash.hash(seed, std.mem.asBytes(&coordinates));
}

pub fn forestAt(lv: *const grid.Level, p: mathx.P) bool {
    return lv.at(p) == .shrub and (lv.tileMask(p) != 0 or loneClump(p));
}

const Cut = union(enum) { tile: grid.Tile, wall: usize, forest: usize };

fn cutAt(lv: *const grid.Level, p: mathx.P) ?Cut {
    if (forestAt(lv, p)) return .{ .forest = WALL_CELL[lv.tileMask(p)] };
    return cutOf(lv.at(p), lv.tileShape(p));
}

fn cutOf(t: grid.Tile, shape: ?grid.WallShape) ?Cut {
    if (t == .wall) return .{ .wall = WALL_CELL[(shape orelse return null).mask()] };
    return .{ .tile = t };
}

/// Row-major masks shared with `tools/tile_art/wall_masks.lua` for both wall and forest sheets.
const WALL_MASKS = [_]u8{ 0, 1, 2, 4, 8, 3, 19, 5, 6, 38, 9, 137, 10, 12, 76, 7, 23, 39, 55, 11, 27, 139, 155, 13, 77, 141, 205, 14, 46, 78, 110, 15, 31, 47, 63, 79, 95, 111, 127, 143, 159, 175, 191, 207, 223, 239, 255 };
const WALL_COLS: usize = @divExact(pngSize(WALLS_PNG).x, SPRITE_PX);

fn pngSize(png: []const u8) mathx.P {
    return .{ .x = std.mem.readInt(i32, png[16..20], .big), .y = std.mem.readInt(i32, png[20..24], .big) };
}

const WALL_CELL = blk: {
    @setEvalBranchQuota(10_000);
    var at = [_]u8{0xFF} ** 256;
    for (WALL_MASKS, 0..) |m, i| {
        std.debug.assert(at[m] == 0xFF and @as(grid.WallShape, @bitCast(m)).joined().mask() == m);
        at[m] = i;
    }
    var all: [256]u8 = undefined;
    for (&all, 0..) |*cell, m| {
        cell.* = at[@as(grid.WallShape, @bitCast(@as(u8, m))).joined().mask()];
        std.debug.assert(cell.* != 0xFF);
    }
    break :blk all;
};

/// raylib's `imageFromImage` copies without clamping, so a cell off the sheet would read past it.
fn wallCell(sheet: rl.Image, i: usize) ?rl.Image {
    const at = mathx.unslot(i, WALL_COLS);
    if ((at.x + 1) * SPRITE_PX > sheet.width or (at.y + 1) * SPRITE_PX > sheet.height) return null;
    return rl.imageFromImage(sheet, sheetCell(at.x, at.y));
}

fn sheetCell(col: i32, row: i32) rl.Rectangle {
    return raster.rect(col * SPRITE_PX, row * SPRITE_PX, SPRITE_PX, SPRITE_PX);
}

fn unloadEach(held: []?rl.Texture2D) void {
    for (held) |*h| {
        if (h.*) |t| rl.unloadTexture(t);
        h.* = null;
    }
}

pub fn unloadAll(v: anytype) void {
    inline for (std.meta.fields(@TypeOf(v.*))) |f| {
        if (comptime @typeInfo(f.type) == .@"struct" and @hasField(f.type, "values") and @hasDecl(f.type, "Key") and std.meta.Elem(@FieldType(f.type, "values")) == ?rl.Texture2D) {
            unloadEach(&@field(v.*, f.name).values);
            continue;
        }
        if (comptime @typeInfo(f.type) == .array and std.meta.Elem(f.type) == ?rl.Texture2D) {
            unloadEach(&@field(v.*, f.name));
            continue;
        }
        const Child = switch (@typeInfo(f.type)) {
            .optional => |o| o.child,
            else => void,
        };
        const program_ = @typeInfo(Child) == .@"struct" and @hasField(Child, "shader");
        const resource = Child == rl.Texture2D or Child == rl.RenderTexture2D or Child == rl.Shader or program_;
        if (!resource and comptime std.mem.startsWith(u8, @typeName(Child), "raylib.")) @compileError("unloadAll frees no " ++ @typeName(Child));
        if (resource) {
            const held = &@field(v.*, f.name);
            if (held.*) |r| {
                if (Child == rl.Texture2D) rl.unloadTexture(r) else if (Child == rl.RenderTexture2D) rl.unloadRenderTexture(r) else if (Child == rl.Shader) rl.unloadShader(r) else rl.unloadShader(r.shader);
            }
            held.* = null;
        }
    }
}

pub fn rgb(hex: u24) rl.Color {
    return .{ .r = @intCast(hex >> 16), .g = @intCast((hex >> 8) & 0xff), .b = @intCast(hex & 0xff), .a = 255 };
}

pub fn fade(c: rl.Color, a: f32) rl.Color {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = @intFromFloat(@as(f32, @floatFromInt(c.a)) * std.math.clamp(a, 0, 1)) };
}

pub fn mixed(a: rl.Color, b: rl.Color, t: f32) rl.Color {
    const k = std.math.clamp(t, 0, 1);
    const ch = struct {
        fn of(p: u8, q: u8, w: f32) u8 {
            return @intFromFloat(@round(mathx.lerpF(@floatFromInt(p), @floatFromInt(q), w)));
        }
    };
    return .{ .r = ch.of(a.r, b.r, k), .g = ch.of(a.g, b.g, k), .b = ch.of(a.b, b.b, k), .a = a.a };
}

const GOLD = rgb(0xc9a24a);
const FOE = rgb(0xe0503a);
const SHADE = rgb(0x3e3c46);

pub const BG = rgb(0x07070a);
pub const FOG = rgb(0x0a0a0a);
pub const LIT = rl.Color.white;
const FLOOR_BG = rgb(0x121116);
const GRASS_BG = rgb(0x111a0e);
/// The editor's wall where it has no texture.
pub const BARE_WALL = rgb(0x1e1c24);
pub const TEXT = rgb(0xd8cdb4);
pub const DIM = rgb(0x8c8672);
pub const LIFE = rgb(0x9c2f2a);
pub const FIRE = rgb(0xff8a32);
pub const FIRE_CORE = rgb(0xffe6a0);
pub const LEVEL_GOLD = rgb(0xe6c57c);
pub const LEVEL_CORE = rgb(0xffedbd);
/// The light a level gain adds to its body, per channel.
pub const LEVEL_BODY_TINT = [3]f32{ 1, 0.72, 0.28 };
pub const BLEED = rgb(0xd8483a);
pub const EDGE = rgb(0x4a4438);
pub const UI_GOLD = rgb(0xbca06b);
pub const UI_FOCUS = rgb(0xd0b581);
const ARROW = rgb(0xe6dcb4);
pub const VEIL = fade(BG, 0.72);

/// Its symbol, centred on `cx, cy`; its ASCII `ch` where the font has no atlas.
pub fn inkTile(face: *const font.Face, t: grid.Tile, cx: i32, cy: i32, size: i32) void {
    const l = TILES.getPtrConst(t);
    face.symbol(l.sym, l.ch, cx, cy, size, l.fg);
}

pub fn tile(t: grid.Tile) Look {
    const l = TILES.getPtrConst(t);
    return .{ .ch = l.ch, .fg = l.fg };
}

/// Under a tile's glyph where it has no sprite; null leaves the background.
pub fn tileBg(t: grid.Tile) ?rl.Color {
    return TILES.getPtrConst(t).bg;
}

/// Fallback underlay when `ground.bedAt` finds no suitable neighbour.
pub fn under(t: grid.Tile) ?grid.Tile {
    return t.ground() orelse if (t.upright() and tileBg(t) == null) .floor else null;
}

/// Tree crowns: ground the light shades beneath them, and the atmosphere's shafts fall between.
const CROWNS = std.EnumSet(grid.Tile).init(.{ .shrub = true, .swamp_tree = true, .large_tree = true });
/// Scenery depth of field softens: the crowns and the small plants.
pub const SOFTENED = CROWNS.unionWith(grid.LITTER_TILES);

comptime {
    for (std.enums.values(grid.Tile)) |t| {
        if (SOFTENED.contains(t) and !stands(t)) @compileError(@tagName(t) ++ " is softened but stands in no STANDS row");
        if (CROWNS.contains(t) and !canopied(t)) @compileError(@tagName(t) ++ " is a crown but no .canopy STANDS row");
    }
}

pub fn crowned(t: grid.Tile) bool {
    return CROWNS.contains(t);
}

/// Gas veils what stands in it; brick and rock walls stay clear.
pub fn veiled(t: grid.Tile) bool {
    return t != .wall and t != .rock;
}

/// Drawn in the solid pass, over the ground and the shadows cast on it: everything that is not itself a ground.
pub fn standsOver(t: grid.Tile) bool {
    return ground.of(t) == null;
}

/// A ground with neither a sheet nor a picture, which shows its glyph.
pub fn glyphGround(t: grid.Tile, sprites: *const Sprites) bool {
    const g = ground.of(t) orelse return false;
    return sprites.grounds.getPtrConst(g).* == null and sprites.tiles.getPtrConst(t).* == null;
}

const TileLook = struct { sym: [:0]const u8, ch: u8, fg: rl.Color, bg: ?rl.Color, mini: rl.Color, mini_dim: rl.Color };

const TILES = std.EnumArray(grid.Tile, TileLook).init(.{
    .wall = .{ .sym = "#", .ch = '#', .fg = rgb(0x9a8e78), .bg = null, .mini = rgb(0x8a7f6a), .mini_dim = rgb(0x46434c) },
    .floor = .{ .sym = "·", .ch = '.', .fg = rgb(0x5e5a50), .bg = FLOOR_BG, .mini = rgb(0x3a3830), .mini_dim = rgb(0x1c1c22) },
    .grass = .{ .sym = "\"", .ch = '"', .fg = rgb(0x4f7a3a), .bg = GRASS_BG, .mini = rgb(0x2e4426), .mini_dim = rgb(0x182016) },
    .shrub = .{ .sym = "¥", .ch = '&', .fg = rgb(0x6f9a4a), .bg = null, .mini = rgb(0x5e8a3e), .mini_dim = rgb(0x2e3c2a) },
    .rock = .{ .sym = "#", .ch = '#', .fg = rgb(0x8a7e6c), .bg = rgb(0x262220), .mini = rgb(0x6e6558), .mini_dim = rgb(0x38332e) },
    .dirt = .{ .sym = "·", .ch = '.', .fg = rgb(0x8a6a44), .bg = rgb(0x1a140e), .mini = rgb(0x4a3a28), .mini_dim = rgb(0x231c14) },
    .sand = .{ .sym = "·", .ch = '.', .fg = rgb(0xd8c084), .bg = rgb(0x2e2716), .mini = rgb(0x8a7a50), .mini_dim = rgb(0x403a28) },
    .snow = .{ .sym = "°", .ch = '*', .fg = rgb(0xe6eef2), .bg = rgb(0x2c3036), .mini = rgb(0x9aa2a8), .mini_dim = rgb(0x464a50) },
    .water = .{ .sym = "≈", .ch = '~', .fg = rgb(0x4a80d0), .bg = rgb(0x0e1a36), .mini = rgb(0x24508a), .mini_dim = rgb(0x142640) },
    .shallows = .{ .sym = "~", .ch = '~', .fg = rgb(0x78b0d4), .bg = rgb(0x14283c), .mini = rgb(0x3e6e8e), .mini_dim = rgb(0x1e3444) },
    .bridge = .{ .sym = "=", .ch = '=', .fg = rgb(0xa87c48), .bg = rgb(0x1e160e), .mini = rgb(0x7a5a36), .mini_dim = rgb(0x3a2c1c) },
    .reeds = .{ .sym = "¦", .ch = '|', .fg = rgb(0xa8b24a), .bg = null, .mini = rgb(0x6a7030), .mini_dim = rgb(0x32361a) },
    .rubble = .{ .sym = "•", .ch = ',', .fg = rgb(0x8a7f6a), .bg = rgb(0x18161a), .mini = rgb(0x4e4840), .mini_dim = rgb(0x26241f) },
    .fence = .{ .sym = "∏", .ch = '#', .fg = rgb(0x9a6638), .bg = null, .mini = rgb(0x7a5030), .mini_dim = rgb(0x3a2818) },
    .lava = .{ .sym = "≈", .ch = '~', .fg = rgb(0xff8a30), .bg = rgb(0x501406), .mini = rgb(0xc8501a), .mini_dim = rgb(0x5a240c) },
    .fungus = .{ .sym = "¶", .ch = 'T', .fg = rgb(0xb882e0), .bg = null, .mini = rgb(0x7a4e9a), .mini_dim = rgb(0x3a2a48) },
    .chasm = .{ .sym = "·", .ch = ':', .fg = rgb(0x24222a), .bg = rgb(0x030305), .mini = rgb(0x0c0c10), .mini_dim = rgb(0x060608) },
    .ice = .{ .sym = "·", .ch = '_', .fg = rgb(0xb8e4f4), .bg = rgb(0x1c3440), .mini = rgb(0x7ab0c8), .mini_dim = rgb(0x3a5462) },
    .grave = .{ .sym = "†", .ch = '+', .fg = rgb(0xc8c4b8), .bg = null, .mini = rgb(0x8a8680), .mini_dim = rgb(0x44423e) },
    .crop = .{ .sym = "¥", .ch = '"', .fg = rgb(0xd8b84a), .bg = rgb(0x1e1a0a), .mini = rgb(0x8a7a30), .mini_dim = rgb(0x403a18) },
    .tiny_shrub = .{ .sym = "'", .ch = '\'', .fg = rgb(0x6f9a4a), .bg = null, .mini = rgb(0x4e7436), .mini_dim = rgb(0x26341f) },
    .boulder = .{ .sym = "o", .ch = 'o', .fg = rgb(0x9a8e90), .bg = null, .mini = rgb(0x7a7072), .mini_dim = rgb(0x3c3638) },
    .tall_grass = .{ .sym = "\"", .ch = '"', .fg = rgb(0x7aa84e), .bg = null, .mini = rgb(0x3a5630), .mini_dim = rgb(0x1c2818) },
    .shrooms = .{ .sym = "•", .ch = ',', .fg = rgb(0xd8ccb4), .bg = null, .mini = rgb(0x3c4a30), .mini_dim = rgb(0x1e241a) },
    .chest = .{ .sym = "C", .ch = 'C', .fg = GOLD, .bg = null, .mini = GOLD, .mini_dim = rgb(0x66502b) },
    .chest_open = .{ .sym = "O", .ch = 'O', .fg = rgb(0x96724d), .bg = null, .mini = rgb(0x96724d), .mini_dim = rgb(0x443422) },
    .swamp_tree = .{ .sym = "S", .ch = 'S', .fg = rgb(0x788650), .bg = null, .mini = rgb(0x667247), .mini_dim = rgb(0x343b29) },
    .large_tree = .{ .sym = "L", .ch = 'L', .fg = rgb(0x788650), .bg = null, .mini = rgb(0x667247), .mini_dim = rgb(0x343b29) },
    .glow_plant = .{ .sym = "&", .ch = '&', .fg = rgb(0x9fd2ff), .bg = null, .mini = rgb(0x7fb2e0), .mini_dim = rgb(0x2e4256) },
});

comptime {
    for (TILES.values) |l| std.debug.assert(l.sym.len != 1 or l.sym[0] == l.ch);
}

pub const TILE_CODEPOINTS = blk: {
    var out: []const i32 = &.{};
    for (TILES.values) |l| {
        const cp: i32 = std.unicode.utf8Decode(l.sym) catch unreachable;
        if (cp < 0x80) continue;
        const have = for (out) |o| {
            if (o == cp) break true;
        } else false;
        if (!have) out = out ++ &[_]i32{cp};
    }
    break :blk out;
};

pub const TORCH = Look{ .ch = 'i', .fg = rgb(0xffc46a) };
pub const TORCH_DIM = rgb(0x4a4238);
pub const BARREL = Look{ .ch = '0', .fg = rgb(0x8a5a32) };
pub const FOLK = Look{ .ch = '@', .fg = rgb(0xd8a860) };
pub const DOOR = Look{ .ch = '+', .fg = rgb(0xb89a5a) };
/// What a picture of the whole map marks a cell with over its tile, a door before a barrel.
pub const Mark = enum {
    door,
    barrel,

    pub fn of(lv: *const grid.Level, i: usize) ?Mark {
        if (lv.door[i] != grid.NO_DOOR) return .door;
        if (lv.barrel[i]) return .barrel;
        return null;
    }

    pub fn look(m: Mark) Look {
        return switch (m) {
            .door => DOOR,
            .barrel => BARREL,
        };
    }
};

pub fn body(k: actor.Kind) Look {
    return switch (k) {
        .archer => .{ .ch = '@', .fg = rgb(0x7cc86e) },
        .wizard => .{ .ch = '@', .fg = rgb(0x8f9cf2) },
        .knight => .{ .ch = '@', .fg = rgb(0xd6d9e0) },
        .rat => .{ .ch = 'r', .fg = rgb(0xb07a4e) },
        .slime, .slime_half, .slime_quarter => .{ .ch = 's', .fg = rgb(0x6fae5a) },
        .bloat => .{ .ch = 'b', .fg = BLOAT },
        .pib => .{ .ch = 'p', .fg = rgb(0xe89aa6) },
        .beefy_pib => .{ .ch = 'P', .fg = rgb(0xe89aa6) },
        .bandit_crossbowman => .{ .ch = 'c', .fg = rgb(0xb07a4e) },
        .bandit_netter => .{ .ch = 'N', .fg = rgb(0xffeb3b) },
        .bandit_shieldbearer => .{ .ch = 'S', .fg = rgb(0x4d7cff) },
        .frost_wisp => .{ .ch = 'W', .fg = rgb(0x4ff0ff) },
        .pyre_bloat => .{ .ch = 'B', .fg = rgb(0xff3b3b) },
        .pib_shaman => .{ .ch = 'Y', .fg = rgb(0xc77dff) },
        .bog_leech => .{ .ch = 'L', .fg = rgb(0x8cff3f) },
        .mimic => .{ .ch = 'M', .fg = rgb(0xff9f1c) },
    };
}

/// Drawn a figure's glyph is, offset down-right in this ink, so letters standing in for art read at a glance.
pub const GLYPH_SHADOW = rl.Color{ .r = 0, .g = 0, .b = 0, .a = DROP_SHADOW_A };
pub const GLYPH_SHADOW_PX: i32 = 4;
/// A glyph's or a line of text's drop shadow, at full ink.
pub const DROP_SHADOW_A: u8 = 200;

/// Brogue's `poisonGasColor`, the bloat's.
pub const BLOAT = rgb(0xbf40d9);
/// Its caustic gas, a greyer purple.
pub const GAS = rgb(0x9a76aa);
pub const HEALING_GAS = rgb(0xa6cff0);
pub const STEAM = rgb(0xe6e8ea);

pub fn gasInk(g: grid.Gas) rl.Color {
    return switch (g) {
        .caustic => GAS,
        .healing => HEALING_GAS,
        .steam => STEAM,
    };
}

pub const BLOOD = rl.Color{ .r = 112, .g = 22, .b = 16, .a = GORE_A };
pub const OOZE = rl.Color{ .r = 70, .g = 120, .b = 72, .a = GORE_A };
pub const SPLINTER = rl.Color{ .r = 120, .g = 82, .b = 46, .a = 230 };
/// Brogue's purple blood: the bloat's, darker.
pub const ICHOR = rl.Color{ .r = BLOAT.r / 2, .g = BLOAT.g / 2, .b = BLOAT.b / 2, .a = GORE_A };
const GORE_A: u8 = 220;
pub const CONTACT = rl.Color{ .r = 255, .g = 244, .b = 214, .a = 180 };
pub const JUKE_TRAIL = rl.Color{ .r = 196, .g = 212, .b = 218, .a = 140 };
pub const JUKE_DUST = rl.Color{ .r = 184, .g = 161, .b = 125, .a = 170 };
pub const WATER_DROP = rl.Color{ .r = 166, .g = 197, .b = 242, .a = 150 };
pub const NET = rgb(0xd6c496);
pub const RAIN = rgb(0xc4d0e2);
/// The atmosphere's water mist, and its light shafts and dust.
pub const MIST_TINT = [3]f32{ 0.48, 0.58, 0.68 };
pub const SHAFT_TINT = [3]f32{ 1.0, 0.87, 0.64 };

pub const Gait = enum { hop, slide };

pub fn gait(k: actor.Kind) Gait {
    return switch (k) {
        .archer, .wizard, .knight, .rat, .pib, .beefy_pib, .bandit_crossbowman, .bandit_netter, .bandit_shieldbearer, .pib_shaman, .mimic => .hop,
        .slime, .slime_half, .slime_quarter, .bloat, .frost_wisp, .pyre_bloat, .bog_leech => .slide,
    };
}

pub fn mini(t: grid.Tile, lit: bool) rl.Color {
    const l = TILES.getPtrConst(t);
    return if (lit) l.mini else l.mini_dim;
}

pub const AIM_REACH = fade(GOLD, 0.10);
pub const AIM_PATH = fade(GOLD, 0.28);
pub const COLD = rgb(0x8cddf5);
pub const PIN = rgb(0xc8c2b4);
pub const SHOCK = rgb(0xb48cff);
pub const SUNDER = rgb(0xb5652e);
pub const BLIND = rgb(0x8a96a3);
pub const CONFUSION = rgb(0x9ad46b);
pub const FEAR = rgb(0xe39bc4);
pub const WARD = rgb(0x6fa8f0);
pub const MAGIC = WARD;
pub const RARE = rgb(0xe8d15a);

pub fn itemInk(rarity: items.Rarity) rl.Color {
    return switch (rarity) {
        .normal => rl.Color.white,
        .magic => MAGIC,
        .rare => RARE,
    };
}
const AIM_AREA_A: f32 = 0.24;
pub const RETICLE = rgb(0xe8c25a);

/// A burst's cells, shaded while it is aimed.
pub fn aimArea(a: skillbar.Act) rl.Color {
    return fade(arrowInk(a), AIM_AREA_A);
}
pub const RETICLE_BLOCKED = SHADE;
pub const LEAN_OPEN = GOLD;
pub const LEAN_FOE = FOE;
pub const LEAN_BLOCKED = SHADE;

pub fn arrowInk(a: skillbar.Act) rl.Color {
    return elementInk(a.element() orelse return PHYSICAL);
}

pub fn elementInk(e: damage.Element) rl.Color {
    return switch (e) {
        .fire => FIRE,
        .cold => COLD,
        .lightning => LIGHTNING,
        .chaos => ARROW,
    };
}

pub const LIGHTNING = rgb(0xf4e872);
pub const LIGHTNING_CORE = FIRE_CORE;
pub const PHYSICAL = ARROW;
/// Life and mana as text, brighter than their orbs so they read on a panel.
pub const LIFE_TEXT = rgb(0xe0645a);
pub const MANA_TEXT = rgb(0x6e9ce8);

pub fn ailmentInk(k: resilience.Kind) rl.Color {
    return switch (k) {
        .stun => LIGHTNING,
        .burn => elementInk(.fire),
        .bleed => BLEED,
        .chill => elementInk(.cold),
        .pin => PIN,
        .shock => SHOCK,
        .sunder => SUNDER,
        .blind => BLIND,
        .confusion => CONFUSION,
        .fright => FEAR,
    };
}

const PANEL = rgb(0x0e0d12);
const RAISED = rgb(0x1a1820);

pub const SLOT_BG = RAISED;
pub const SLOT_EMPTY = PANEL;
pub const SLOT_HELD = UI_GOLD;
pub const SLOT_CURSOR = UI_FOCUS;
pub const SLOT_CLEAR = FOE;
pub const PICK_BG = PANEL;
pub const CARD_BG = PANEL;
pub const CLEAR = Look{ .ch = 'x', .fg = SLOT_CLEAR };

/// The alpha below which nothing is drawn.
pub const CLEAR_A: f32 = 0.004;
/// The alpha of a skill or action that cannot be used now.
pub const FADED_A: f32 = 0.35;

/// How far a sprite is softened; a shader drawing over it again (the gas veil) softens its own alpha alike.
pub const Focused = struct {
    texel: [2]f32 = .{ 0, 0 },
    strength: f32 = 0,

    pub const sharp: Focused = .{};

    pub fn set(self: Focused, s: rl.Shader, texel: i32, strength: i32) void {
        shaders.setUniform(s, texel, self.texel);
        shaders.setUniform(s, strength, self.strength);
    }
};

/// `texture0` here and at its four sides, premultiplied; the sides share what the centre leaves.
pub const FOCUS_CENTRE_W = 0.4;
pub const FOCUS_SIDE_W = (1 - FOCUS_CENTRE_W) / 4.0;
pub const FOCUS_WEIGHTS = shaders.glslConsts(.{ .FOCUS_CENTRE_W = FOCUS_CENTRE_W, .FOCUS_SIDE_W = FOCUS_SIDE_W });
/// `focused()`: `texture0` softened by `Focused`'s uniforms, premultiplied; `unpremultiplied(c)` its colour back.
pub const FOCUS_TAPS = FOCUS_WEIGHTS ++
    \\uniform vec2 texel;
    \\uniform float strength;
    \\vec4 tap(vec2 offset) {
    \\    vec4 c = texture(texture0, clamp(fragTexCoord + offset * texel, texel * 0.5, vec2(1.0) - texel * 0.5));
    \\    return vec4(c.rgb * c.a, c.a);
    \\}
    \\vec4 focused() {
    \\    vec4 base = tap(vec2(0.0));
    \\    vec4 blur = base * FOCUS_CENTRE_W;
    \\    blur += (tap(vec2(1.0, 0.0)) + tap(vec2(-1.0, 0.0)) + tap(vec2(0.0, 1.0)) + tap(vec2(0.0, -1.0))) * FOCUS_SIDE_W;
    \\    return mix(base, blur, strength);
    \\}
    \\vec3 unpremultiplied(vec4 c) {
    \\    return c.rgb / max(c.a, 0.0001);
    \\}
    \\
;

/// `noise(p)`: value noise over the `float hash(vec2)` declared before it.
pub const VALUE_NOISE_FS =
    \\float noise(vec2 p) {
    \\    vec2 i = floor(p);
    \\    vec2 f = fract(p);
    \\    vec2 u = f * f * (3.0 - 2.0 * f);
    \\    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
    \\}
    \\
;

const FadeShader = struct { shader: rl.Shader, bounds: i32, minimum: i32 };
const SCENERY_FS = shaders.FS_HEAD ++ FOCUS_TAPS ++ shaders.MAP_VIEW_FS ++ OCCLUSION_FS ++ shaders.glslConsts(.{ .FOG_RGB = rgbOf(FOG), .OVERBRIGHT = @import("light.zig").OVERBRIGHT }) ++
    \\uniform sampler2D lightmap;
    \\uniform sampler2D fogmap;
    \\void main() {
    \\    vec2 p = cellAtFrag();
    \\    if (!insideMap(p)) discard;
    \\    vec2 uv = p / CELLS;
    \\    vec4 art = focused();
    \\    vec3 lit = texture(lightmap, uv).rgb * OVERBRIGHT;
    \\    vec3 fog = FOG_RGB * texture(fogmap, uv).a;
    \\    finalColor = vec4(unpremultiplied(art) * lit + fog, art.a * occlusionAt(p));
    \\}
;

const FADE_FS = shaders.FS_HEAD ++
    \\uniform vec2 bounds;
    \\uniform float minimum;
    \\void main() {
    \\    vec4 ink = texture(texture0, fragTexCoord) * fragColor;
    \\    ink.a *= mix(1.0, minimum, smoothstep(bounds.x, bounds.y, gl_FragCoord.y));
    \\    finalColor = ink;
    \\}
;

const ShineShader = struct { shader: rl.Shader, sweep: i32 };
/// Each shining cell's band crosses once a period, at its own place in it.
const SHINE_PERIOD_S: f32 = 7;
const SHINE_WIPE_S: f32 = 0.9;
/// Of the sprite's diagonal, the band's half-width.
const SHINE_WIDTH: f32 = 0.12;
/// How far the band leans: down the sprite per unit across.
const SHINE_SLANT: f32 = 0.6;
const SHINE_GAIN: f32 = 0.18;
const SHINE_SEED: u64 = 0x5417E;
const SHINE_PHASES = 1000;
const SHINE_FS = shaders.FS_HEAD ++ shaders.glslConsts(.{ .SHINE_WIDTH = SHINE_WIDTH, .SHINE_SLANT = SHINE_SLANT, .SHINE_GAIN = SHINE_GAIN }) ++
    \\uniform float sweep;
    \\void main() {
    \\    vec4 tex = texture(texture0, fragTexCoord);
    \\    float along = (fragTexCoord.x + fragTexCoord.y * SHINE_SLANT) / (1.0 + SHINE_SLANT);
    \\    float band = 1.0 - smoothstep(0.0, SHINE_WIDTH, abs(along - sweep));
    \\    finalColor = vec4(fragColor.rgb, tex.a * fragColor.a * band * SHINE_GAIN);
    \\}
;

/// Where the shine's band crosses the sprite on `p` at `seconds`, corner to corner; null between its shines.
pub fn shineSweep(seconds: f32, p: mathx.P) ?f32 {
    const phase = cellHash(SHINE_SEED, p) % SHINE_PHASES;
    const t = @mod(seconds + @as(f32, @floatFromInt(phase)) / SHINE_PHASES * SHINE_PERIOD_S, SHINE_PERIOD_S);
    if (t >= SHINE_WIPE_S) return null;
    return mathx.lerpF(-SHINE_WIDTH, 1 + SHINE_WIDTH, t / SHINE_WIPE_S);
}

/// Of the shallows' colours, what deep water's art keeps: `tools/tile_art/deepen_water.lua`.
const WATER_DEEP_PERCENT = 60;
const WATER_DEEP: f32 = mathx.fraction(WATER_DEEP_PERCENT);
const WATER_SHALLOW: f32 = 1;
const WATER_SATURATION: f32 = 0.8;
const MIRROR_DEEP: f32 = 0.42;
const MIRROR_SHALLOW: f32 = 0.28;
const MIRROR_TINT = [3]f32{ 0.8, 0.9, 1.0 };
const WATER_FS = shaders.FS_HEAD ++ shaders.glslConsts(.{
    .SATURATION = WATER_SATURATION,
    .OVERBRIGHT = @import("light.zig").OVERBRIGHT,
    .DEEP = WATER_DEEP,
    .SHALLOW = WATER_SHALLOW,
    .MIRROR_DEEP = MIRROR_DEEP,
    .MIRROR_SHALLOW = MIRROR_SHALLOW,
    .MIRROR_TINT = MIRROR_TINT,
}) ++ shaders.MAP_VIEW_FS ++
    \\uniform float depth;
    \\uniform sampler2D visibility;
    \\uniform sampler2D glints;
    \\uniform sampler2D mirror;
    \\uniform sampler2D memory;
    \\uniform int mirrored;
    \\void main() {
    \\    vec4 art = texture(texture0, fragTexCoord) * fragColor;
    \\    vec2 at = cellAtFrag();
    \\    vec4 light = texture(visibility, at / CELLS);
    \\    vec4 reflected = vec4(0.0);
    \\    if (mirrored != 0) {
    \\        vec2 uv = gl_FragCoord.xy / screen;
    \\        vec4 remembered = texture(memory, uv);
    \\        remembered.rgb *= light.rgb * OVERBRIGHT;
    \\        reflected = mix(remembered, texture(mirror, uv), light.a);
    \\    }
    \\    float strength = mix(MIRROR_DEEP, MIRROR_SHALLOW, smoothstep(DEEP, SHALLOW, depth));
    \\    vec3 shine = reflected.rgb * MIRROR_TINT * strength;
    \\    shine = mix(vec3(dot(shine, LUMA)), shine, SATURATION);
    \\    shine += texture(glints, at / CELLS).rgb * light.a;
    \\    vec3 base = art.rgb * (1.0 - reflected.a * strength);
    \\    finalColor = vec4(clamp(base + shine / max(light.rgb * OVERBRIGHT, vec3(0.06)), 0.0, 1.0), art.a);
    \\}
;

fn waterDepth(gr: ground.Ground) ?f32 {
    return switch (gr) {
        .water => WATER_DEEP,
        .shallows => WATER_SHALLOW,
        .chasm, .lava, .ice, .snow, .sand, .dirt, .crop, .grass, .rubble, .bridge, .cobble => null,
    };
}

/// The grounds that mirror the scene and glint.
pub const REFLECTIVE = blk: {
    var set = std.EnumSet(ground.Ground).initEmpty();
    for (std.enums.values(ground.Ground)) |gr| {
        if (waterDepth(gr) != null) set.insert(gr);
    }
    break :blk set;
};

pub fn reflects(t: grid.Tile) bool {
    return REFLECTIVE.contains(ground.of(t) orelse return false);
}

pub fn alphaOf(c: rl.Color) f32 {
    return @as(f32, @floatFromInt(c.a)) / 255;
}

pub fn rgbOf(c: rl.Color) sky.Rgb {
    return sky.Rgb{ @floatFromInt(c.r), @floatFromInt(c.g), @floatFromInt(c.b) } / sky.splat(255);
}

pub fn colourOf(c: sky.Rgb, a: f32) rl.Color {
    const k = @max(sky.splat(0), @min(sky.splat(1), c)) * sky.splat(255) + sky.splat(0.5);
    return .{ .r = @intFromFloat(k[0]), .g = @intFromFloat(k[1]), .b = @intFromFloat(k[2]), .a = @intFromFloat(std.math.clamp(a, 0, 1) * 255 + 0.5) };
}

/// The opacity of the hud plate's and the minimap's backing.
pub const BACKING_A: f32 = 0.7;
pub const MINI_BG = fade(FOG, BACKING_A);
pub const MINI_HERO = rgb(0x9cf08a);
pub const MINI_FOE = FOE;
pub const MINI_VIEW = fade(GOLD, 0.7);
pub const DAY_SUN = LEVEL_GOLD;
pub const DAY_MOON = rgb(0xc9cfdc);
pub const DAY_PATH = fade(UI_GOLD, 0.45);
pub const DAY_SHADOW = fade(BG, 0.75);

pub const EDIT_PANEL = PANEL;
pub const EDIT_ROW_ON = RAISED;
pub const EDIT_ON = UI_GOLD;
pub const EDIT_PICKED = UI_FOCUS;
pub const EDIT_WARN = FOE;
pub const EDIT_HOVER = fade(TEXT, 0.6);
pub const EDIT_UNLINKED = DIM;

pub const PROMPT_BODY = rgb(0x1b1713);
pub const PROMPT_FACE = rgb(0x28221c);
pub const PROMPT_EDGE = rgb(0x6a604e);
pub const PROMPT_LIP = rgb(0x0c0a08);
pub const PROMPT_INK = rgb(0xe2d2b4);
pub const XBOX_A = rgb(0x5eb242);
pub const XBOX_B = rgb(0xd63e34);
pub const XBOX_X = rgb(0x2e78cd);
pub const XBOX_Y = UI_FOCUS;
pub const SONY_CROSS = rgb(0x7cb2e8);
pub const SONY_CIRCLE = rgb(0xea6060);
pub const SONY_SQUARE = rgb(0xd686c4);
pub const SONY_TRIANGLE = rgb(0x40c4a0);

test "a cell's shine crosses once a period, corner to corner, and neighbours shine at other times" {
    const dt = mathx.TEST_DT;
    const p = mathx.P{ .x = 10, .y = 10 };
    var shining: usize = 0;
    var last: ?f32 = null;
    var t: f32 = 0;
    const frames: usize = @intFromFloat(SHINE_PERIOD_S / dt);
    for (0..frames) |_| {
        t += dt;
        const s = shineSweep(t, p) orelse {
            last = null;
            continue;
        };
        shining += 1;
        try std.testing.expect(s >= -SHINE_WIDTH and s <= 1 + SHINE_WIDTH);
        if (last) |l| try std.testing.expect(s > l);
        last = s;
    }
    const share = @as(f32, @floatFromInt(shining)) / @as(f32, @floatFromInt(frames));
    std.debug.print("shine: lit {d:.3} of a {d} s period (wipe {d} s)\n", .{ share, SHINE_PERIOD_S, SHINE_WIPE_S });
    try std.testing.expectApproxEqAbs(SHINE_WIPE_S / SHINE_PERIOD_S, share, 0.01);
    var together: usize = 0;
    for (0..20) |x| {
        if ((shineSweep(1, .{ .x = @intCast(x), .y = 0 }) != null) == (shineSweep(1, .{ .x = @intCast(x + 1), .y = 0 }) != null)) together += 1;
    }
    try std.testing.expect(together < 20);
}

test "map assets include unseen shapes, ground under props and future slime forms" {
    const gen = @import("../map/gen.zig");
    var lv = grid.Level.blank();
    @memset(&lv.tile, .rock);
    lv.set(.{ .x = 20, .y = 20 }, .wall);
    lv.set(.{ .x = 23, .y = 20 }, .shrub);
    lv.set(.{ .x = 24, .y = 20 }, .shrub);
    lv.set(.{ .x = 30, .y = 20 }, .boulder);
    gen.shapeWalls(&lv);
    var need = Assets.of(&lv);
    need.body(.archer);
    need.body(.slime_half);
    try std.testing.expect(need.tiles.contains(.floor) and need.grounds.contains(.grass) and !need.tiles.contains(.grass));
    try std.testing.expect(need.tiles.contains(.boulder) and !need.tiles.contains(.shrub));
    try std.testing.expectEqual(@as(usize, 1), need.wall.count());
    try std.testing.expect(need.wall.isSet(WALL_CELL[0]));
    try std.testing.expectEqual(@as(usize, 2), need.forest.count());
    try std.testing.expect(need.forest.isSet(WALL_CELL[2]) and need.forest.isSet(WALL_CELL[8]));
    try std.testing.expect(need.bodies.contains(.slime_half) and need.bodies.contains(.slime_quarter));
    try std.testing.expect(!need.bodies.contains(.slime) and !need.bodies.contains(.rat));
    try std.testing.expect(!need.barrel);
    need.body(.slime);
    try std.testing.expectEqual(@as(usize, 4), need.bodies.count());
    lv = grid.openFloor();
    lv.putBarrel(grid.MIDDLE);
    lv.set(.{ .x = 20, .y = 20 }, .chest);
    const next = Assets.of(&lv);
    try std.testing.expect(next.item_bag and next.chest_item_bag and next.tiles.contains(.chest_open));
    try std.testing.expect(next.barrel and next.forest.count() == 0 and next.bodies.count() == 0);
    try std.testing.expect(next.tiles.contains(.floor) and !next.tiles.contains(.grass));
    const cell = grid.Level.idx(grid.MIDDLE);
    lv.seen[cell] = true;
    lv.barrel_seen[cell] = true;
    try std.testing.expect(lv.breakBarrel(grid.MIDDLE));
    try std.testing.expect(Assets.of(&lv).barrel);
    lv.barrel_seen[cell] = false;
    try std.testing.expect(!Assets.of(&lv).barrel);
    std.debug.print("map assets: hidden walls and forest, 2 underlays, slime descendants, remembered barrels and map replacement checked\n", .{});
}

test "map assets hold the fallback ground a prop stands on when only unbearing neighbours are seen" {
    var lv = grid.Level.blank();
    @memset(&lv.tile, .water);
    @memset(&lv.seen, true);
    const p = grid.MIDDLE;
    lv.set(p, .boulder);
    const fallback = ground.of(under(.boulder).?).?;
    const other: ground.Ground = if (fallback == .dirt) .sand else .dirt;
    for (mathx.CARDINALS) |d| {
        lv.set(p.add(d), other.tile());
        lv.seen[grid.Level.idx(p.add(d))] = false;
    }
    const shown = ground.bedAt(&lv, p, true).?;
    try std.testing.expect(shown != ground.bedAt(&lv, p, false).?);
    const need = Assets.of(&lv);
    try std.testing.expect(if (GROUND_SHEETS.contains(shown)) need.grounds.contains(shown) else need.tiles.contains(shown.tile()));
    std.debug.print("prop seen over water only: drawn on {s}, loaded\n", .{@tagName(shown)});
}

test "every glyph is printable ascii" {
    const inked = struct {
        fn f(c: u8) bool {
            return std.ascii.isPrint(c) and c != ' ';
        }
    }.f;
    for (std.enums.values(grid.Tile)) |t| try std.testing.expect(inked(TILES.get(t).ch));
    for (std.enums.values(actor.Kind)) |k| try std.testing.expect(inked(body(k).ch));
    try std.testing.expect(inked(TORCH.ch));
    try std.testing.expect(inked(BARREL.ch));
    try std.testing.expect(inked(DOOR.ch));
    try std.testing.expect(inked(CLEAR.ch));
}

test "every wall and forest cell lies inside its PNG, and one past its end is refused" {
    for ([_][]const u8{ WALLS_PNG, FOREST_PNG }, [_][]const u8{ "walls", "forest" }) |png, name| {
        const w = pngSize(png).x;
        const h = pngSize(png).y;
        const sheet = rl.genImageColor(w, h, rl.Color.white);
        defer rl.unloadImage(sheet);
        try std.testing.expectEqual(@as(i32, SPRITE_PX * WALL_COLS), w);
        try std.testing.expectEqual(@as(i32, SPRITE_PX * ((WALL_MASKS.len + WALL_COLS - 1) / WALL_COLS)), h);
        for (0..WALL_MASKS.len) |i| rl.unloadImage(wallCell(sheet, i) orelse return error.CellOffSheet);
        std.debug.print("{s}.png {d}x{d}: {d} shapes cut from it\n", .{ name, w, h, WALL_MASKS.len });
        try std.testing.expect(wallCell(sheet, @intCast(@divTrunc(w, SPRITE_PX) * @divTrunc(h, SPRITE_PX))) == null);
    }
}

test "forest sprites follow connections and isolated trees mix with clumps without changing visibility" {
    const gen = @import("../map/gen.zig");
    var lv = grid.Level.blank();
    @memset(&lv.tile, .grass);
    var sprites = Sprites{};
    const tree = rl.Texture2D{ .id = 1, .width = SPRITE_PX, .height = SPRITE_PX, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
    sprites.tiles.set(.shrub, tree);
    for (&sprites.forest, 0..) |*t, i| {
        var texture_ = tree;
        texture_.id = @intCast(i + 2);
        t.* = texture_;
    }
    const a = mathx.P{ .x = 20, .y = 20 };
    const b = a.add(.{ .x = 1, .y = 0 });
    lv.set(a, .shrub);
    lv.set(b, .shrub);
    gen.shapeWalls(&lv);
    try std.testing.expectEqual(sprites.forest[WALL_CELL[2]].?.id, sprites.tileAt(&lv, a).?.id);
    try std.testing.expectEqual(sprites.forest[WALL_CELL[8]].?.id, sprites.tileAt(&lv, b).?.id);
    lv.seen = @splat(true);
    try std.testing.expectEqual(sprites.forest[WALL_CELL[2]].?.id, sprites.tileAt(&lv, a).?.id);
    @memset(&lv.tile, .grass);
    var trees: usize = 0;
    var clumps: usize = 0;
    for (0..100) |i| {
        const p = mathx.P{ .x = 2 + @as(i32, @intCast(i % 10)) * 3, .y = 2 + @as(i32, @intCast(i / 10)) * 3 };
        lv.set(p, .shrub);
    }
    gen.shapeWalls(&lv);
    const need = Assets.of(&lv);
    try std.testing.expect(need.tiles.contains(.shrub) and need.forest.isSet(WALL_CELL[0]));
    for (lv.tile, 0..) |t, i| {
        if (t != .shrub) continue;
        const p = grid.Level.of(i);
        const id = sprites.tileAt(&lv, p).?.id;
        try std.testing.expectEqual(id, sprites.tileAt(&lv, p).?.id);
        try std.testing.expect(t.solid() and t.blind());
        if (id == tree.id) trees += 1 else if (id == sprites.forest[WALL_CELL[0]].?.id) clumps += 1 else return error.NotAnIsolatedSprite;
    }
    std.debug.print("100 isolated blockers: {d} lone trees, {d} forest clumps; 2 connected tiles keep their shapes\n", .{ trees, clumps });
    try std.testing.expect(trees > 40 and clumps > 15 and clumps < trees);
}

test "floor shows through a wall's gaps; a tile with its own ground or background keeps it" {
    try std.testing.expectEqual(@as(?grid.Tile, .floor), under(.wall));
    try std.testing.expectEqual(@as(?grid.Tile, .grass), under(.shrub));
    try std.testing.expectEqual(@as(?grid.Tile, .dirt), under(.swamp_tree));
    try std.testing.expectEqual(@as(?grid.Tile, null), under(.rock));
    try std.testing.expectEqual(@as(?grid.Tile, null), under(.floor));
    try std.testing.expectEqual(@as(?grid.Tile, null), under(.water));
}

test "the wall sheet's masks, shape bits and face height are the ones its scripts paint" {
    try ground.expectLuaList(u8, &WALL_MASKS, "tools/tile_art/wall_masks.lua", "local masks={");
    const sides = .{ "n", "e", "s", "w", "ne", "se", "sw", "nw" };
    var bits: [sides.len]u8 = undefined;
    inline for (sides, 0..) |side, i| {
        var shape = grid.WallShape{};
        @field(shape, side) = true;
        bits[i] = shape.mask();
    }
    try ground.expectLuaList(u8, &bits, "tools/tile_art/wall_masks.lua", "local N,E,S,W,NE,SE,SW,NW=");
    try ground.expectLuaList(i32, &.{WALL_FACE_PX}, "tools/tile_art/export_walls.lua", "local FACE=");
    try ground.expectLuaList(i32, &.{WALL_FACE_PX}, "tools/tile_art/guide_walls.lua", "local FACE=tonumber(app.params.rows) or ");
    try ground.expectLuaList(i32, &.{WALL_FACE_PX}, "tools/tile_art/idea_walls.lua", "local FACE=");
}

test "the hud border's size and corner cut are the ones its export script checks" {
    const path = "tools/hud_art/export_border.lua";
    const size = comptime pngSize(HUD_BORDER_PNG);
    try ground.expectLuaList(i32, &.{size.x}, path, "local W=");
    try ground.expectLuaList(i32, &.{size.y}, path, "local H=");
    try ground.expectLuaList(i32, &.{HUD_BORDER_CUT}, path, "local CUT=");
}

test "the deep water sheet is the shallows' at WATER_DEEP_PERCENT, as deepen_water.lua rounds it" {
    try ground.expectLuaList(i32, &.{WATER_DEEP_PERCENT}, "tools/tile_art/deepen_water.lua", "local percent=tonumber(app.params.percent) or ");
    const shallow = try rl.loadImageFromMemory(".png", GROUND_PNGS.get(.shallows).?);
    defer rl.unloadImage(shallow);
    const deep = try rl.loadImageFromMemory(".png", GROUND_PNGS.get(.water).?);
    defer rl.unloadImage(deep);
    try std.testing.expectEqual(shallow.width, deep.width);
    try std.testing.expectEqual(shallow.height, deep.height);
    const Lua = struct {
        fn channel(v: u8) u8 {
            return @intCast((@as(u32, v) * WATER_DEEP_PERCENT + mathx.PERCENT / 2) / mathx.PERCENT);
        }
    };
    var y: i32 = 0;
    while (y < shallow.height) : (y += 1) {
        var x: i32 = 0;
        while (x < shallow.width) : (x += 1) {
            const s = rl.getImageColor(shallow, x, y);
            const d = rl.getImageColor(deep, x, y);
            try std.testing.expectEqual(s.a, d.a);
            if (s.a == 0) continue;
            try std.testing.expectEqual([3]u8{ Lua.channel(s.r), Lua.channel(s.g), Lua.channel(s.b) }, [3]u8{ d.r, d.g, d.b });
        }
    }
}
