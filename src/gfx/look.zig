const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const damage = @import("../play/damage.zig");
const skillbar = @import("../play/skillbar.zig");
const font = @import("font.zig");
const ground = @import("ground.zig");
const sky = @import("sky.zig");
const embedded = @import("assets").names;

pub const SPRITE_PX: i32 = 64;
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

/// Every sprite that throws a shadow from its feet: bodies, barrel, standing tiles and forest shapes.
pub const FIGURES: usize = LIT_FIGURES + STANDING.len + WALL_MASKS.len;
/// The first of `figures`, the bodies and the barrel, which the body shader lights from their normals.
pub const LIT_FIGURES: usize = Bodies.len + 1;

pub const Assets = struct {
    bodies: std.EnumSet(actor.Kind) = .initEmpty(),
    tiles: std.EnumSet(grid.Tile) = .initEmpty(),
    wall: std.StaticBitSet(WALL_MASKS.len) = .initEmpty(),
    forest: std.StaticBitSet(WALL_MASKS.len) = .initEmpty(),
    grounds: ground.Grounds = .initEmpty(),
    barrel: bool = false,

    pub fn of(lv: *const grid.Level) Assets {
        var need = Assets{};
        for (lv.tile, lv.barrel, 0..) |t, barrel, i| {
            const p = grid.Level.of(i);
            need.barrel = need.barrel or barrel;
            if (t.opened()) |open| need.add(.{ .tile = open });
            if (standsOver(t)) {
                if (cutAt(lv, p)) |c| need.add(c);
            }
            const g = ground.bedAt(lv, p) orelse continue;
            if (GROUND_SHEETS.contains(g)) need.grounds.insert(g) else need.add(.{ .tile = g.tile() });
        }
        return need;
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
        var all = Assets{ .barrel = true, .grounds = GROUND_SHEETS, .bodies = PICTURED, .wall = .initFull(), .forest = .initFull() };
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

/// Needs a live GL context.
pub const Sprites = struct {
    bodies: Bodies = .initFill(null),
    barrel: ?rl.Texture2D = null,
    tiles: std.EnumArray(grid.Tile, ?rl.Texture2D) = .initFill(null),
    /// In the sheet's order, `WALL_MASKS`.
    wall: [WALL_MASKS.len]?rl.Texture2D = @splat(null),
    forest: [WALL_MASKS.len]?rl.Texture2D = @splat(null),
    /// Each ground's whole sheet, drawn a piece at a time so a ground's pieces batch.
    grounds: std.EnumArray(ground.Ground, ?rl.Texture2D) = .initFill(null),
    /// Every skill's icon side by side, in `skillbar.Act`'s order, inked once rather than every frame.
    skills: ?rl.Texture2D = null,
    hud_border: ?rl.Texture2D = null,
    log_fade: ?FadeShader = null,
    water: ?WaterShader = null,
    mirror: ?rl.RenderTexture2D = null,
    mirror_memory: ?rl.RenderTexture2D = null,

    pub fn loadCommon(self: *Sprites) void {
        self.skills = skillIcons();
        self.hud_border = texture(HUD_BORDER_PNG);
        self.log_fade = program(FadeShader, FADE_FS);
        self.water = program(WaterShader, WATER_FS);
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

    fn groundPiece(self: *const Sprites, g: ground.Ground, mask: u4) ?Piece {
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
    pub fn drawGround(self: *const Sprites, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView) void {
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
                    const piece = self.groundPiece(gr, here.corners.mask(gr)) orelse continue;
                    const at = cellAt(origin, p, px);
                    blit(piece.tex, piece.src, .{ .x = at[0] - px / 2, .y = at[1] - px / 2, .width = px, .height = px }, LIT);
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
        }
    }

    fn beginWater(self: *const Sprites, view: ?WaterView, origin: [2]f32, px: f32, depth: f32) bool {
        const v = view orelse return false;
        const s = self.water orelse return false;
        rl.beginShaderMode(s.shader);
        setMapView(s, .{ .origin = origin, .cell = px, .screen = v.screen });
        setUniform(s.shader, s.depth, depth);
        setUniform(s.shader, s.mirrored, @as(i32, @intFromBool(v.mirror != null)));
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
        if (!beginTarget(if (memory) &self.mirror_memory else &self.mirror, screen, outer, rl.Color.blank)) return false;
        rl.gl.rlDisableBackfaceCulling();
        return true;
    }

    pub fn endMirror(self: *const Sprites, outer: u32) Mirrors {
        rl.gl.rlDrawRenderBatchActive();
        rl.gl.rlEnableBackfaceCulling();
        endTarget(outer);
        return .{ .live = self.mirror.?.texture, .memory = self.mirror_memory.?.texture };
    }

    fn cellAt(origin: [2]f32, p: mathx.P, px: f32) [2]f32 {
        return .{ origin[0] + @as(f32, @floatFromInt(p.x)) * px, origin[1] + @as(f32, @floatFromInt(p.y)) * px };
    }

    /// The part of a ground's square from `uv` across `span`, fractions of the cell: its picture, else its colour.
    fn squarePart(self: *const Sprites, t: grid.Tile, cell: [2]f32, px: f32, uv: [2]f32, span: f32) void {
        const dest = rl.Rectangle{ .x = cell[0] + uv[0] * px, .y = cell[1] + uv[1] * px, .width = span * px, .height = span * px };
        if (self.tiles.getPtrConst(t).*) |tex| {
            const w, const h = sizeOf(tex);
            blit(tex, .{ .x = uv[0] * w, .y = uv[1] * h, .width = span * w, .height = span * h }, dest, LIT);
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
        return self.litFigures() ++ standing ++ self.forest;
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

    fn toTexture(img: rl.Image) ?rl.Texture2D {
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
                    rl.drawTextureRec(tex, rect(sx[col], sy[row], w, h), vec(.{ .x = dx[col] + xx, .y = dy[row] + yy }), tint);
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
    .barrel = @as([]const u8, @embedFile("barrel.png")),
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

fn loneClump(p: mathx.P) bool {
    const coordinates = [2]i32{ p.x, p.y };
    return std.hash.Wyhash.hash(LONE_CLUMP_SEED, std.mem.asBytes(&coordinates)) % LONE_CLUMP_IN == 0;
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
    const col: i32 = @intCast(i % WALL_COLS);
    const row: i32 = @intCast(i / WALL_COLS);
    if ((col + 1) * SPRITE_PX > sheet.width or (row + 1) * SPRITE_PX > sheet.height) return null;
    return rl.imageFromImage(sheet, sheetCell(col, row));
}

fn sheetCell(col: i32, row: i32) rl.Rectangle {
    return rect(col * SPRITE_PX, row * SPRITE_PX, SPRITE_PX, SPRITE_PX);
}

pub fn whole(t: rl.Texture2D) rl.Rectangle {
    return rect(0, 0, t.width, t.height);
}

pub fn sizeOf(t: rl.Texture2D) [2]f32 {
    return .{ @floatFromInt(t.width), @floatFromInt(t.height) };
}

pub fn rect(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(h) };
}

pub fn vec(p: mathx.P) rl.Vector2 {
    return .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
}

pub fn holds(r: rl.Rectangle, p: mathx.P) bool {
    return rl.checkCollisionPointRec(vec(p), r);
}

pub fn middle(r: rl.Rectangle) rl.Vector2 {
    return .{ .x = r.x + r.width / 2, .y = r.y + r.height / 2 };
}

/// The pixel at `r`'s middle.
pub fn middleAt(r: rl.Rectangle) mathx.P {
    const m = middle(r);
    return .{ .x = @intFromFloat(m.x), .y = @intFromFloat(m.y) };
}

pub fn stretch(t: rl.Texture2D, dest: rl.Rectangle, tint: rl.Color) void {
    blit(t, whole(t), dest, tint);
}

/// `r` grown `by` pixels on every side.
pub fn grown(r: rl.Rectangle, by: f32) rl.Rectangle {
    return .{ .x = r.x - by, .y = r.y - by, .width = r.width + 2 * by, .height = r.height + 2 * by };
}

/// `src` of `t` drawn over `dest`, unturned.
pub fn blit(t: rl.Texture2D, src: rl.Rectangle, dest: rl.Rectangle, tint: rl.Color) void {
    rl.drawTexturePro(t, src, dest, .{ .x = 0, .y = 0 }, 0, tint);
}

pub fn overFloor(t: rl.Texture2D, ox: i32, oy: i32, cell: i32) void {
    stretch(t, floorRect(ox, oy, cell), LIT);
}

/// The whole floor on screen, its top-left at `ox, oy`.
pub fn floorRect(ox: i32, oy: i32, cell: i32) rl.Rectangle {
    return rect(ox, oy, grid.W * cell, grid.H * cell);
}

/// Borrows `px`, packed `w` to a row: nothing to unload.
pub fn rgba(px: *anyopaque, w: i32, h: i32) rl.Image {
    return .{ .data = px, .width = w, .height = h, .mipmaps = 1, .format = .uncompressed_r8g8b8a8 };
}

/// Needs a live GL context.
pub fn clamped(img: rl.Image, filter: rl.TextureFilter) ?rl.Texture2D {
    const t = rl.loadTextureFromImage(img) catch return null;
    rl.setTextureFilter(t, filter);
    rl.setTextureWrap(t, .clamp);
    return t;
}

/// Filled with `c`, for pixels uploaded every frame. Needs a live GL context.
pub fn canvas(w: i32, h: i32, c: rl.Color, filter: rl.TextureFilter) ?rl.Texture2D {
    const img = rl.genImageColor(w, h, c);
    defer rl.unloadImage(img);
    return clamped(img, filter);
}

pub fn beginTarget(target: *?rl.RenderTexture2D, screen: mathx.P, outer: u32, clear: rl.Color) bool {
    rl.gl.rlDrawRenderBatchActive();
    if (target.*) |t| {
        if (t.texture.width != screen.x or t.texture.height != screen.y) {
            rl.unloadRenderTexture(t);
            target.* = null;
        }
    }
    if (target.* == null) target.* = rl.loadRenderTexture(screen.x, screen.y) catch {
        endTarget(outer);
        return false;
    };
    rl.gl.rlEnableFramebuffer(target.*.?.id);
    rl.clearBackground(clear);
    return true;
}

/// Back to `outer` after `beginTarget`, with what was drawn flushed into the target.
pub fn endTarget(outer: u32) void {
    rl.gl.rlDrawRenderBatchActive();
    rl.gl.rlEnableFramebuffer(outer);
}

/// Blending by GL factors and equation, until `rl.endBlendMode`.
pub fn beginBlend(src: i32, dst: i32, equation: i32) void {
    rl.gl.rlSetBlendFactors(src, dst, equation);
    rl.beginBlendMode(.custom);
}

/// A render texture over the whole frame, flipped the right way up.
pub fn drawTarget(t: rl.Texture2D) void {
    rl.drawTextureRec(t, rect(0, 0, t.width, -t.height), .{ .x = 0, .y = 0 }, rl.Color.white);
}

/// White, its alpha `alphaAt(r)` at `r` from the middle, 1 at the middle of each edge. Needs a live GL context.
pub fn radial(comptime px: i32, comptime alphaAt: fn (f32) f32) ?rl.Texture2D {
    const round = struct {
        fn at(u: f32, v: f32) f32 {
            return alphaAt(mathx.len(u * 2 - 1, v * 2 - 1));
        }
    };
    return field(px, px, round.at);
}

/// White, its alpha `alphaAt(u, v)` at each texel's middle, `u` and `v` 0 to 1 across and down. Needs a live GL context.
pub fn field(comptime w: i32, comptime h: i32, comptime alphaAt: fn (f32, f32) f32) ?rl.Texture2D {
    const nw: usize = @intCast(w);
    const nh: usize = @intCast(h);
    var img: [nw * nh]rl.Color = undefined;
    for (0..nh) |y| {
        for (0..nw) |x| {
            const u = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(w));
            const v = (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(h));
            img[y * nw + x] = fade(rl.Color.white, alphaAt(u, v));
        }
    }
    return clamped(rgba(&img, w, h), .bilinear);
}

/// Shaders `shader` has failed to compile since the process started.
pub var shader_failures: u32 = 0;

/// Null when it does not compile: raylib then hands back its default shader rather than an error.
pub fn shader(fs: [:0]const u8) ?rl.Shader {
    const s = rl.loadShaderFromMemory(null, fs) catch {
        shader_failures += 1;
        return null;
    };
    if (s.id != rl.gl.rlGetShaderIdDefault()) return s;
    shader_failures += 1;
    return null;
}

/// For headless runs, after everything they draw has loaded.
pub fn expectShaders() error{ShaderFailed}!void {
    if (shader_failures > 0) return error.ShaderFailed;
}

fn uniforms(comptime T: type, s: rl.Shader) T {
    var u: T = undefined;
    u.shader = s;
    inline for (std.meta.fields(T)) |f| {
        if (comptime std.mem.eql(u8, f.name, "shader")) continue;
        @field(u, f.name) = rl.getShaderLocation(s, f.name);
    }
    return u;
}

/// Shader uniforms and `T`'s fields must match in both directions at compile time.
pub fn program(comptime T: type, comptime fs: [:0]const u8) ?T {
    comptime {
        @setEvalBranchQuota(100_000);
        for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "shader") and !declares(fs, f.name)) @compileError("no uniform " ++ f.name ++ " in the shader for " ++ @typeName(T));
        }
        var lines = std.mem.splitScalar(u8, fs, '\n');
        while (lines.next()) |l| {
            const name = uniformOf(l) orelse continue;
            if (!std.mem.eql(u8, name, "texture0") and !@hasField(T, name)) @compileError("uniform " ++ name ++ " has no field in " ++ @typeName(T));
        }
    }
    return uniforms(T, shader(fs) orelse return null);
}

/// `value` to the uniform at `loc`, its GLSL type read off its Zig type.
pub fn setUniform(s: rl.Shader, loc: i32, value: anytype) void {
    rl.setShaderValue(s, loc, &value, comptime uniformType(@TypeOf(value)));
}

/// The first `n` of `values` to the uniform array at `loc`.
pub fn setUniforms(s: rl.Shader, loc: i32, values: anytype, n: i32) void {
    rl.setShaderValueV(s, loc, values, comptime uniformType(std.meta.Elem(@TypeOf(values.*))), n);
}

fn uniformType(comptime T: type) rl.ShaderUniformDataType {
    return switch (T) {
        f32 => .float,
        [2]f32 => .vec2,
        [3]f32 => .vec3,
        [4]f32 => .vec4,
        i32 => .int,
        else => @compileError("no uniform type for " ++ @typeName(T)),
    };
}

fn declares(comptime fs: []const u8, comptime name: []const u8) bool {
    var lines = std.mem.splitScalar(u8, fs, '\n');
    while (lines.next()) |l| {
        if (std.mem.eql(u8, uniformOf(l) orelse continue, name)) return true;
    }
    return false;
}

fn uniformOf(comptime l: []const u8) ?[]const u8 {
    const line = std.mem.trim(u8, l, " \t\r");
    if (!std.mem.startsWith(u8, line, "uniform ")) return null;
    const end = std.mem.indexOfAny(u8, line, "[;") orelse return null;
    const head = std.mem.trimRight(u8, line[0..end], " ");
    const at = std.mem.lastIndexOfScalar(u8, head, ' ') orelse return null;
    return head[at + 1 ..];
}

fn unloadEach(held: []?rl.Texture2D) void {
    for (held) |*h| {
        if (h.*) |t| rl.unloadTexture(t);
        h.* = null;
    }
}

pub fn unloadAll(v: anytype) void {
    inline for (std.meta.fields(@TypeOf(v.*))) |f| {
        if (comptime @typeInfo(f.type) == .@"struct" and @hasField(f.type, "values") and @hasDecl(f.type, "Key")) {
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

/// Under a tile's glyph where it has no sprite; null leaves the background.
pub fn tileBg(t: grid.Tile) ?rl.Color {
    return TILES.getPtrConst(t).bg;
}

/// Fallback underlay when `ground.bedAt` finds no suitable neighbour.
pub fn under(t: grid.Tile) ?grid.Tile {
    return t.ground() orelse if (t.upright() and tileBg(t) == null) .floor else null;
}

/// Tree crowns: ground the light shades beneath them, and the atmosphere's shafts fall between.
const CROWNS = std.EnumSet(grid.Tile).init(.{ .shrub = true, .swamp_tree = true });
/// Scenery depth of field softens: the crowns and the small plants.
pub const SOFTENED = CROWNS.unionWith(grid.LITTER_TILES);

comptime {
    for (std.enums.values(grid.Tile)) |t| {
        if (SOFTENED.contains(t) and !stands(t)) @compileError(@tagName(t) ++ " is softened but stands in no STANDS row");
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
pub const DOOR = Look{ .ch = '+', .fg = rgb(0xb89a5a) };
/// Gold on the ground, in the reticle's gold, and an item, in `itemInk`.
pub const COIN_MARK = "$";
pub const DROP_MARK = "*";

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
        .bloat => .{ .ch = 'b', .fg = GAS },
        .pib => .{ .ch = 'p', .fg = rgb(0xe89aa6) },
        .beefy_pib => .{ .ch = 'P', .fg = rgb(0xe89aa6) },
    };
}

/// Brogue's `poisonGasColor`, the bloat's and its gas's.
pub const GAS = rgb(0xbf40d9);

pub const BLOOD = rl.Color{ .r = 112, .g = 22, .b = 16, .a = GORE_A };
pub const OOZE = rl.Color{ .r = 70, .g = 120, .b = 72, .a = GORE_A };
pub const SPLINTER = rl.Color{ .r = 120, .g = 82, .b = 46, .a = 230 };
/// Brogue's purple blood: the gas's, darker.
pub const ICHOR = rl.Color{ .r = GAS.r / 2, .g = GAS.g / 2, .b = GAS.b / 2, .a = GORE_A };
const GORE_A: u8 = 220;
pub const CONTACT = rl.Color{ .r = 255, .g = 244, .b = 214, .a = 180 };
pub const JUKE_TRAIL = rl.Color{ .r = 196, .g = 212, .b = 218, .a = 140 };
pub const JUKE_DUST = rl.Color{ .r = 184, .g = 161, .b = 125, .a = 170 };
pub const WATER_DROP = rl.Color{ .r = 166, .g = 197, .b = 242, .a = 150 };

pub const Gait = enum { hop, slide };

pub fn gait(k: actor.Kind) Gait {
    return switch (k) {
        .archer, .wizard, .knight, .rat, .pib, .beefy_pib => .hop,
        .slime, .slime_half, .slime_quarter, .bloat => .slide,
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
pub const WARD = rgb(0x6fa8f0);
pub const MAGIC = WARD;

/// An item's name and mark: magic ones in the ward's blue.
pub fn itemInk(magical: bool) rl.Color {
    return if (magical) MAGIC else TEXT;
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

pub fn drawDirection(d: mathx.Dir, cx: i32, cy: i32, size: i32, col: rl.Color) void {
    const delta = d.delta();
    const unit: f32 = if (d.diagonal()) std.math.sqrt1_2 else 1;
    const dx = @as(f32, @floatFromInt(delta.x)) * unit;
    const dy = @as(f32, @floatFromInt(delta.y)) * unit;
    const scale = @as(f32, @floatFromInt(size)) / SKILL_GRID;
    const x: f32 = @floatFromInt(cx);
    const y: f32 = @floatFromInt(cy);
    const lines = [_][4]f32{ .{ -12, 0, 12, 0 }, .{ 4, -8, 12, 0 }, .{ 12, 0, 4, 8 } };
    for (lines) |line| {
        const from = rl.Vector2{
            .x = x + (dx * line[0] - dy * line[1]) * scale,
            .y = y + (dy * line[0] + dx * line[1]) * scale,
        };
        const to = rl.Vector2{
            .x = x + (dx * line[2] - dy * line[3]) * scale,
            .y = y + (dy * line[2] + dx * line[3]) * scale,
        };
        stroke(from, to, scale, col);
    }
}

const FLASK = [_][4]f32{
    .{ 13, 4, 19, 4 },
    .{ 13, 4, 13, 11 },
    .{ 19, 4, 19, 11 },
    .{ 13, 11, 6, 18 },
    .{ 19, 11, 26, 18 },
    .{ 6, 18, 6, 26 },
    .{ 26, 18, 26, 26 },
    .{ 6, 28, 26, 28 },
};

const ARROW_LINES = [_][4]f32{
    .{ 6, 26, 26, 6 },
    .{ 16, 6, 26, 6 },
    .{ 26, 6, 26, 16 },
};

const SHIELD_LINES = [_][4]f32{
    .{ 6, 5, 26, 5 },
    .{ 26, 5, 26, 16 },
    .{ 26, 16, 16, 28 },
    .{ 16, 28, 6, 16 },
    .{ 6, 16, 6, 5 },
};

fn skillLines(a: skillbar.Act) []const [4]f32 {
    return switch (a) {
        .shoot => &(ARROW_LINES ++ [_][4]f32{
            .{ 5, 19, 12, 19 },
            .{ 12, 19, 12, 26 },
        }),
        .burning_arrow => &.{
            .{ 13, 26, 27, 12 },
            .{ 19, 12, 27, 12 },
            .{ 27, 12, 27, 20 },
            .{ 9, 23, 4, 18 },
            .{ 4, 18, 4, 14 },
            .{ 4, 14, 11, 5 },
            .{ 11, 5, 10, 13 },
            .{ 10, 13, 15, 10 },
            .{ 15, 10, 17, 17 },
            .{ 17, 17, 13, 22 },
        },
        .glacial_shot => &.{
            .{ 5, 27, 25, 7 },
            .{ 17, 7, 25, 7 },
            .{ 25, 7, 25, 15 },
            .{ 5, 6, 15, 16 },
            .{ 5, 16, 15, 6 },
            .{ 3, 11, 17, 11 },
            .{ 10, 4, 10, 18 },
        },
        .juke => &.{
            .{ 6, 7, 15, 16 },
            .{ 15, 16, 6, 25 },
            .{ 17, 7, 26, 16 },
            .{ 26, 16, 17, 25 },
        },
        .spark => &.{
            .{ 19, 3, 9, 17 },
            .{ 9, 17, 17, 17 },
            .{ 17, 17, 12, 29 },
            .{ 12, 29, 24, 13 },
            .{ 24, 13, 16, 13 },
            .{ 16, 13, 19, 3 },
        },
        .blink => &.{
            .{ 4, 16, 8, 16 },
            .{ 6, 14, 6, 18 },
            .{ 12, 16, 16, 16 },
            .{ 20, 16, 28, 16 },
            .{ 24, 10, 24, 22 },
            .{ 20, 12, 28, 20 },
            .{ 20, 20, 28, 12 },
        },
        .shield_bash => &(SHIELD_LINES ++ [_][4]f32{
            .{ 16, 9, 16, 22 },
        }),
        .pinning_shot => &.{
            .{ 16, 4, 16, 24 },
            .{ 11, 19, 16, 24 },
            .{ 21, 19, 16, 24 },
            .{ 12, 4, 16, 8 },
            .{ 20, 4, 16, 8 },
            .{ 5, 27, 27, 27 },
        },
        .barbed_arrow => &(ARROW_LINES ++ [_][4]f32{
            .{ 11, 21, 7, 21 },
            .{ 11, 21, 11, 25 },
            .{ 16, 16, 12, 16 },
            .{ 16, 16, 16, 20 },
        }),
        .frost_nova => &.{
            .{ 16, 3, 16, 29 },
            .{ 3, 16, 29, 16 },
            .{ 7, 7, 25, 25 },
            .{ 7, 25, 25, 7 },
            .{ 13, 4, 16, 7 },
            .{ 19, 4, 16, 7 },
            .{ 13, 28, 16, 25 },
            .{ 19, 28, 16, 25 },
        },
        .fireball => &.{
            .{ 14, 10, 20, 12 },
            .{ 20, 12, 22, 18 },
            .{ 22, 18, 20, 24 },
            .{ 20, 24, 14, 26 },
            .{ 14, 26, 8, 24 },
            .{ 8, 24, 6, 18 },
            .{ 6, 18, 8, 12 },
            .{ 8, 12, 14, 10 },
            .{ 20, 12, 27, 5 },
            .{ 22, 18, 29, 13 },
            .{ 14, 10, 18, 3 },
        },
        .chain_lightning => &.{
            .{ 4, 27, 11, 15 },
            .{ 11, 15, 17, 21 },
            .{ 17, 21, 22, 9 },
            .{ 22, 9, 28, 14 },
            .{ 9, 13, 13, 17 },
            .{ 15, 19, 19, 23 },
            .{ 20, 7, 24, 11 },
        },
        .mana_shield => &(SHIELD_LINES ++ [_][4]f32{
            .{ 16, 9, 21, 15 },
            .{ 21, 15, 16, 21 },
            .{ 16, 21, 11, 15 },
            .{ 11, 15, 16, 9 },
        }),
        .charge => &.{
            .{ 14, 16, 28, 16 },
            .{ 22, 10, 28, 16 },
            .{ 28, 16, 22, 22 },
            .{ 4, 10, 12, 10 },
            .{ 2, 16, 10, 16 },
            .{ 4, 22, 12, 22 },
        },
        .life_flask => &(FLASK ++ [_][4]f32{
            .{ 16, 17, 16, 25 },
            .{ 12, 21, 20, 21 },
        }),
        .mana_flask => &(FLASK ++ [_][4]f32{
            .{ 11, 21, 14, 18 },
            .{ 14, 18, 18, 24 },
            .{ 18, 24, 21, 21 },
        }),
        .cleave => &.{
            .{ 4, 26, 24, 6 },
            .{ 20, 4, 27, 11 },
            .{ 8, 20, 12, 24 },
            .{ 6, 10, 4, 16 },
            .{ 22, 28, 16, 28 },
            .{ 4, 16, 6, 22 },
            .{ 16, 28, 10, 26 },
        },
        .wait => &.{
            .{ 7, 5, 25, 5 },
            .{ 7, 27, 25, 27 },
            .{ 9, 5, 9, 10 },
            .{ 9, 10, 23, 22 },
            .{ 23, 22, 23, 27 },
            .{ 23, 5, 23, 10 },
            .{ 23, 10, 9, 22 },
            .{ 9, 22, 9, 27 },
        },
        .secondary => &.{
            .{ 6, 10, 26, 10 },
            .{ 20, 4, 26, 10 },
            .{ 26, 10, 20, 16 },
            .{ 26, 22, 6, 22 },
            .{ 12, 16, 6, 22 },
            .{ 6, 22, 12, 28 },
        },
    };
}

pub fn arrowInk(a: skillbar.Act) rl.Color {
    return elementInk(a.element() orelse return ARROW);
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

pub const SKILL_PX: i32 = 30;

pub fn drawSkill(sprites: *const Sprites, a: skillbar.Act, x: i32, y: i32, alpha: f32) void {
    const ink = fade(rl.Color.white, alpha);
    const t = sprites.skills orelse return inkSkill(a, x, y, ink);
    blit(t, rect(skillX(a), 0, SKILL_PX, SKILL_PX), rect(x, y, SKILL_PX, SKILL_PX), ink);
}

fn skillX(a: skillbar.Act) i32 {
    return @as(i32, @intCast(a.index())) * SKILL_PX;
}

/// Needs a live GL context.
fn skillIcons() ?rl.Texture2D {
    const target = rl.loadRenderTexture(SKILL_PX * @as(i32, @intCast(skillbar.ACTS.len)), SKILL_PX) catch return null;
    defer rl.unloadRenderTexture(target);
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    for (skillbar.ACTS) |a| inkSkill(a, skillX(a), 0, rl.Color.white);
    rl.endTextureMode();
    var img = rl.loadImageFromTexture(target.texture) catch return null;
    rl.imageFlipVertical(&img);
    return Sprites.toTexture(img);
}

const SKILL_GRID: f32 = 32;

fn inkSkill(a: skillbar.Act, x: i32, y: i32, ink: rl.Color) void {
    const scale = @as(f32, @floatFromInt(SKILL_PX)) / SKILL_GRID;
    const ox: f32 = @floatFromInt(x);
    const oy: f32 = @floatFromInt(y);
    for (skillLines(a)) |line| {
        const from = rl.Vector2{ .x = ox + line[0] * scale, .y = oy + line[1] * scale };
        const to = rl.Vector2{ .x = ox + line[2] * scale, .y = oy + line[3] * scale };
        stroke(from, to, scale, ink);
    }
}

/// Two grid units wide, with round caps.
fn stroke(from: rl.Vector2, to: rl.Vector2, scale: f32, col: rl.Color) void {
    rl.drawLineEx(from, to, 2 * scale, col);
    rl.drawCircleV(from, scale, col);
    rl.drawCircleV(to, scale, col);
}

/// Device-specific input icons: PlayStation shapes, Xbox letters, or keyboard caps.
pub const Prompt = union(enum) {
    face: struct { button: FaceButton, sony: bool },
    pill: [:0]const u8,
    view,
    menu,
    key: [:0]const u8,
    stick: enum { left, right },
    dpad,
    arrows,
    mouse: enum { left, right, middle, wheel },

    pub fn menuOf(st: *const input.State, b: input.Button) Prompt {
        return if (st.device.pad()) of(st, b) else .{ .key = st.caption(b) };
    }

    /// A menu button as `device` shows it, outside any live input state.
    pub fn menuOn(device: input.Device, b: input.Button) Prompt {
        return menuOf(&.{ .device = device }, b);
    }

    pub fn of(st: *const input.State, b: input.Button) Prompt {
        if (!st.device.pad()) return .{ .key = st.slotCaption(b) };
        return switch (b.pad()) {
            .right_face_down => .{ .face = .{ .button = .a, .sony = st.device.playstation() } },
            .right_face_right => .{ .face = .{ .button = .b, .sony = st.device.playstation() } },
            .right_face_left => .{ .face = .{ .button = .x, .sony = st.device.playstation() } },
            .right_face_up => .{ .face = .{ .button = .y, .sony = st.device.playstation() } },
            .left_trigger_1, .right_trigger_1, .right_trigger_2, .right_thumb => .{ .pill = st.caption(b) },
            .middle_right => if (st.device.playstation()) .{ .pill = st.caption(b) } else .menu,
            .middle_left => if (st.device.playstation()) .{ .pill = st.caption(b) } else .view,
            else => unreachable,
        };
    }

    /// Across, at `h` tall.
    pub fn width(p: Prompt, face: *const font.Face, h: i32) i32 {
        return switch (p) {
            .face, .stick, .dpad, .arrows, .mouse => h,
            .pill => |s| face.width(s, labelPx(h)) + h,
            .view, .menu => h + @divTrunc(h, 2),
            .key => |s| @max(h, face.width(s, labelPx(h)) + @divTrunc(h, 2)),
        };
    }

    /// `draw`, its left on `x`; returns the x past it.
    pub fn drawFrom(p: Prompt, face: *const font.Face, x: i32, cy: i32, h: i32, alpha: f32) i32 {
        const w = p.width(face, h);
        p.draw(face, x + @divTrunc(w, 2), cy, h, alpha);
        return x + w;
    }

    /// Its middle on `cx`, `cy`, `h` tall, faded to `alpha`.
    pub fn draw(p: Prompt, face: *const font.Face, cx: i32, cy: i32, h: i32, alpha: f32) void {
        const w = p.width(face, h);
        const box = rect(cx - @divTrunc(w, 2), cy - @divTrunc(h, 2), w, h);
        switch (p) {
            .stick => |side| {
                const c = vec(.{ .x = cx, .y = cy });
                const radius: f32 = @as(f32, @floatFromInt(h)) * 0.46;
                rl.drawCircleV(c, radius, fade(PROMPT_BODY, alpha));
                rl.drawRing(c, radius - 1.5, radius, 0, 360, 24, fade(PROMPT_EDGE, alpha));
                face.centred(if (side == .left) "L" else "R", cx, cy, labelPx(h), fade(PROMPT_INK, alpha));
            },
            .dpad, .arrows => {
                const step = @divTrunc(h, 3);
                for ([_]mathx.Dir{ .n, .e, .s, .w }) |d| {
                    const offset = d.delta();
                    const ink = if (p == .dpad and offset.x != 0) PROMPT_EDGE else PROMPT_INK;
                    promptArrow(d, cx + offset.x * step, cy + offset.y * step, arrowPx(h), fade(ink, alpha));
                }
            },
            .mouse => |button| {
                const shell = rect(cx - @divTrunc(h, 3), cy - @divTrunc(h, 2), @divTrunc(h * 2, 3), h);
                rl.drawRectangleRounded(shell, 0.65, 8, fade(PROMPT_BODY, alpha));
                rl.drawRectangleRoundedLinesEx(shell, 0.65, 8, 1, fade(PROMPT_EDGE, alpha));
                const x: f32 = @floatFromInt(cx);
                const y: f32 = @floatFromInt(cy);
                const s: f32 = @floatFromInt(h);
                if (button == .left or button == .right) {
                    rl.drawRectangleRec(.{ .x = x + (if (button == .left) -s * 0.24 else @as(f32, 0.04)), .y = y - s * 0.33, .width = s * 0.2, .height = s * 0.3 }, fade(PROMPT_INK, alpha));
                } else {
                    rl.drawRectangleRounded(.{ .x = x - 1.5, .y = y - s * 0.3, .width = 3, .height = s * 0.3 }, 0.5, 4, fade(PROMPT_INK, alpha));
                    if (button == .wheel) for ([_]mathx.Dir{ .n, .s }) |d| {
                        promptArrow(d, cx, cy + d.delta().y * @divTrunc(h, 3), arrowPx(h), fade(PROMPT_INK, alpha));
                    };
                }
            },
            .face => |f| faceButton(face, f.button, f.sony, cx, cy, h, alpha),
            .pill => |s| {
                pill(box, alpha);
                face.centred(s, cx, cy, labelPx(h), fade(PROMPT_INK, alpha));
            },
            .view => {
                pill(box, alpha);
                viewMark(cx, cy, h, alpha);
            },
            .menu => {
                pill(box, alpha);
                menuMark(cx, cy, h, alpha);
            },
            .key => |s| {
                keycap(box, alpha);
                const direction: ?mathx.Dir = for (input.ARROW_KEYS) |a| {
                    if (std.mem.eql(u8, s, a.caption)) break a.d;
                } else null;
                if (direction) |d| promptArrow(d, cx, cy - @divTrunc(h, 12), @divTrunc(h, 2), fade(PROMPT_INK, alpha)) else face.centred(s, cx, cy - @divTrunc(h, 12), labelPx(h), fade(PROMPT_INK, alpha));
            },
        }
    }
};

/// The small arrows of an input icon `h` tall.
fn arrowPx(h: i32) i32 {
    return @max(6, @divTrunc(h, 3));
}

fn promptArrow(d: mathx.Dir, cx: i32, cy: i32, size: i32, col: rl.Color) void {
    const delta = d.delta();
    const dx: f32 = @floatFromInt(delta.x);
    const dy: f32 = @floatFromInt(delta.y);
    const radius = @as(f32, @floatFromInt(size)) / 2;
    const x: f32 = @floatFromInt(cx);
    const y: f32 = @floatFromInt(cy);
    const tip = rl.Vector2{ .x = x + dx * radius, .y = y + dy * radius };
    rl.drawLineEx(.{ .x = x - dx * radius, .y = y - dy * radius }, tip, 1.2, col);
    for ([_]f32{ -1, 1 }) |side| rl.drawLineEx(.{ .x = x - dy * radius * side, .y = y + dx * radius * side }, tip, 1.2, col);
}

/// An input icon `h` tall: its caption's text size.
pub fn labelPx(h: i32) i32 {
    return @divTrunc(h * 11, 16);
}

const PROMPT_BODY = rgb(0x1b1713);
const PROMPT_FACE = rgb(0x28221c);
const PROMPT_EDGE = rgb(0x6a604e);
const PROMPT_LIP = rgb(0x0c0a08);
const PROMPT_INK = rgb(0xe2d2b4);

const FaceButton = enum { a, b, x, y };

fn faceInk(b: FaceButton, sony: bool) rl.Color {
    return switch (b) {
        .a => if (sony) rgb(0x7cb2e8) else rgb(0x5eb242),
        .b => if (sony) rgb(0xea6060) else rgb(0xd63e34),
        .x => if (sony) rgb(0xd686c4) else rgb(0x2e78cd),
        .y => if (sony) rgb(0x40c4a0) else UI_FOCUS,
    };
}

fn faceButton(face: *const font.Face, b: FaceButton, sony: bool, cx: i32, cy: i32, h: i32, alpha: f32) void {
    const r: f32 = @as(f32, @floatFromInt(h)) / 2;
    const c = vec(.{ .x = cx, .y = cy });
    const ink = faceInk(b, sony);
    rl.drawCircleV(c, r, fade(PROMPT_LIP, alpha));
    rl.drawCircleV(c, r - 1, fade(PROMPT_BODY, alpha));
    rl.drawCircleV(.{ .x = c.x, .y = c.y - r * 0.12 }, r * 0.78, fade(PROMPT_FACE, alpha));
    rl.drawRing(c, r - 2.6, r - 1, 0, 360, 32, fade(ink, alpha));
    if (!sony) {
        const letter = [_:0]u8{std.ascii.toUpper(@tagName(b)[0])};
        return face.centred(&letter, cx, cy, labelPx(h), fade(ink, alpha));
    }
    const s = r * 0.42;
    const line = @max(1.5, r * 0.16);
    const col = fade(ink, alpha);
    switch (b) {
        .a => {
            rl.drawLineEx(.{ .x = c.x - s, .y = c.y - s }, .{ .x = c.x + s, .y = c.y + s }, line, col);
            rl.drawLineEx(.{ .x = c.x - s, .y = c.y + s }, .{ .x = c.x + s, .y = c.y - s }, line, col);
        },
        .b => rl.drawRing(c, s - line / 2, s + line / 2, 0, 360, 24, col),
        .x => rl.drawRectangleLinesEx(.{ .x = c.x - s, .y = c.y - s, .width = s * 2, .height = s * 2 }, line, col),
        .y => {
            const top = rl.Vector2{ .x = c.x, .y = c.y - s * 1.1 };
            const left = rl.Vector2{ .x = c.x - s * 1.1, .y = c.y + s * 0.8 };
            const right = rl.Vector2{ .x = c.x + s * 1.1, .y = c.y + s * 0.8 };
            rl.drawLineEx(top, left, line, col);
            rl.drawLineEx(left, right, line, col);
            rl.drawLineEx(right, top, line, col);
        },
    }
}

fn pill(box: rl.Rectangle, alpha: f32) void {
    rl.drawRectangleRounded(box, 0.6, 8, fade(PROMPT_BODY, alpha));
    rl.drawRectangleRoundedLinesEx(box, 0.6, 8, 1, fade(PROMPT_EDGE, alpha));
}

fn keycap(box: rl.Rectangle, alpha: f32) void {
    const lip = @max(2, box.height / 8);
    rl.drawRectangleRounded(box, 0.3, 6, fade(PROMPT_LIP, alpha));
    const top = rl.Rectangle{ .x = box.x, .y = box.y, .width = box.width, .height = box.height - lip };
    rl.drawRectangleRounded(top, 0.3, 6, fade(PROMPT_FACE, alpha));
    rl.drawRectangleRoundedLinesEx(top, 0.3, 6, 1, fade(PROMPT_EDGE, alpha));
}

fn viewMark(cx: i32, cy: i32, h: i32, alpha: f32) void {
    const s: f32 = @as(f32, @floatFromInt(h)) * 0.22;
    const x: f32 = @floatFromInt(cx);
    const y: f32 = @floatFromInt(cy);
    const col = fade(PROMPT_INK, alpha);
    rl.drawRectangleLinesEx(.{ .x = x - s * 1.3, .y = y - s * 1.1, .width = s * 1.6, .height = s * 1.4 }, 1.2, col);
    rl.drawRectangleLinesEx(.{ .x = x - s * 0.3, .y = y - s * 0.3, .width = s * 1.6, .height = s * 1.4 }, 1.2, col);
}

fn menuMark(cx: i32, cy: i32, h: i32, alpha: f32) void {
    const s: f32 = @as(f32, @floatFromInt(h)) * 0.24;
    const x: f32 = @floatFromInt(cx);
    const y: f32 = @floatFromInt(cy);
    for ([_]f32{ -1, 0, 1 }) |k| rl.drawLineEx(.{ .x = x - s, .y = y + k * s * 0.7 }, .{ .x = x + s, .y = y + k * s * 0.7 }, 1.5, fade(PROMPT_INK, alpha));
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

/// GLSL `const`s named for `values`' fields: floats at full precision, integers, and two- to four-float vectors.
pub fn glslConsts(comptime values: anytype) [:0]const u8 {
    comptime {
        var out: [:0]const u8 = "";
        for (std.meta.fields(@TypeOf(values))) |f| {
            const v = @field(values, f.name);
            out = out ++ switch (@typeInfo(@TypeOf(v))) {
                .int, .comptime_int => std.fmt.comptimePrint("const int {s} = {d};\n", .{ f.name, v }),
                .float, .comptime_float => "const float " ++ f.name ++ " = " ++ glslFloat(v) ++ ";\n",
                .array, .vector => glslVec(f.name, v),
                else => @compileError(f.name ++ " is no GLSL constant"),
            };
        }
        return out;
    }
}

fn glslVec(comptime name: []const u8, comptime v: anytype) [:0]const u8 {
    const n = switch (@typeInfo(@TypeOf(v))) {
        inline .array, .vector => |a| a.len,
        else => unreachable,
    };
    if (n < 2 or n > 4) @compileError(name ++ " has no GLSL vector of its length");
    const kind = std.fmt.comptimePrint("vec{d}", .{n});
    var parts: [:0]const u8 = glslFloat(v[0]);
    for (1..n) |i| parts = parts ++ ", " ++ glslFloat(v[i]);
    return "const " ++ kind ++ " " ++ name ++ " = " ++ kind ++ "(" ++ parts ++ ");\n";
}

fn glslFloat(comptime v: anytype) [:0]const u8 {
    const s = std.fmt.comptimePrint("{d}", .{@as(f32, v)});
    return if (std.mem.indexOfAny(u8, s, ".e") == null) s ++ ".0" else s;
}

/// What every fragment shader opens with: raylib's inputs and output, `CLEAR_A`, the map's size in cells and `sky.LUMA`.
pub const FS_HEAD =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\uniform sampler2D texture0;
    \\out vec4 finalColor;
    \\
++ glslConsts(.{ .CLEAR_A = CLEAR_A, .CELLS = [2]f32{ grid.W, grid.H }, .LUMA = sky.LUMA });

/// The map's place on screen: `cellAtFrag()` is the map position under the fragment, in cells, `cellAtPixel` under a y-down screen pixel,
/// `targetPixel` the y-down screen pixel at a render target's uv, and `insideMap` whether a map position lies on the map.
pub const MAP_VIEW_FS =
    \\uniform vec2 origin;
    \\uniform float cell;
    \\uniform vec2 screen;
    \\vec2 cellAtPixel(vec2 pixel) {
    \\    return (pixel - origin) / cell;
    \\}
    \\vec2 cellAtFrag() {
    \\    return cellAtPixel(vec2(gl_FragCoord.x, screen.y - gl_FragCoord.y));
    \\}
    \\vec2 targetPixel(vec2 uv) {
    \\    return vec2(uv.x, 1.0 - uv.y) * screen;
    \\}
    \\bool insideMap(vec2 c) {
    \\    return all(greaterThanEqual(c, vec2(0.0))) && all(lessThan(c, CELLS));
    \\}
    \\
;

/// `MAP_VIEW_FS`'s uniforms: where the map's top-left corner lands, a cell's pixels, and the target's size.
pub const MapView = struct {
    origin: [2]f32,
    cell: f32,
    screen: [2]f32,

    pub fn of(ox: i32, oy: i32, cell: i32, w: i32, h: i32) MapView {
        return .{ .origin = .{ @floatFromInt(ox), @floatFromInt(oy) }, .cell = @floatFromInt(cell), .screen = .{ @floatFromInt(w), @floatFromInt(h) } };
    }
};

/// Sets `MAP_VIEW_FS`'s uniforms on a program with `origin`, `cell` and `screen` locations.
pub fn setMapView(p: anytype, v: MapView) void {
    setUniform(p.shader, p.origin, v.origin);
    setUniform(p.shader, p.cell, v.cell);
    setUniform(p.shader, p.screen, v.screen);
}

/// How far a sprite is softened; a shader drawing over it again (the gas veil) softens its own alpha alike.
pub const Focused = struct {
    texel: [2]f32 = .{ 0, 0 },
    strength: f32 = 0,

    pub const sharp: Focused = .{};

    pub fn set(self: Focused, s: rl.Shader, texel: i32, strength: i32) void {
        setUniform(s, texel, self.texel);
        setUniform(s, strength, self.strength);
    }
};

/// `texture0` here and at its four sides, premultiplied; the sides share what the centre leaves.
pub const FOCUS_CENTRE_W = 0.4;
pub const FOCUS_SIDE_W = (1 - FOCUS_CENTRE_W) / 4.0;
pub const FOCUS_WEIGHTS = glslConsts(.{ .FOCUS_CENTRE_W = FOCUS_CENTRE_W, .FOCUS_SIDE_W = FOCUS_SIDE_W });
/// `focused()`: `texture0` softened by `Focused`'s uniforms, premultiplied.
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
const FADE_FS = FS_HEAD ++
    \\uniform vec2 bounds;
    \\uniform float minimum;
    \\void main() {
    \\    vec4 ink = texture(texture0, fragTexCoord) * fragColor;
    \\    ink.a *= mix(1.0, minimum, smoothstep(bounds.x, bounds.y, gl_FragCoord.y));
    \\    finalColor = ink;
    \\}
;

/// Of the shallows' colours, what deep water's art keeps: `tools/tile_art/deepen_water.lua`.
const WATER_DEEP_PERCENT = 60;
const WATER_DEEP: f32 = mathx.fraction(WATER_DEEP_PERCENT);
const WATER_SHALLOW: f32 = 1;
const WATER_SATURATION: f32 = 0.8;
const MIRROR_DEEP: f32 = 0.42;
const MIRROR_SHALLOW: f32 = 0.28;
const WATER_FS = FS_HEAD ++ glslConsts(.{
    .SATURATION = WATER_SATURATION,
    .OVERBRIGHT = @import("light.zig").OVERBRIGHT,
    .DEEP = WATER_DEEP,
    .SHALLOW = WATER_SHALLOW,
    .MIRROR_DEEP = MIRROR_DEEP,
    .MIRROR_SHALLOW = MIRROR_SHALLOW,
}) ++ MAP_VIEW_FS ++
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
    \\    vec3 shine = reflected.rgb * vec3(0.80, 0.90, 1.0) * strength;
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
    const next = Assets.of(&lv);
    try std.testing.expect(next.barrel and next.forest.count() == 0 and next.bodies.count() == 0);
    try std.testing.expect(next.tiles.contains(.floor) and !next.tiles.contains(.grass));
    std.debug.print("map assets: hidden walls and forest, 2 underlays, slime descendants and map replacement checked\n", .{});
}

test "a slot's prompt is its maker's face button or shoulder on a pad, and its key's cap on the keyboard" {
    _ = Prompt.draw;
    var st = input.State{ .device = .xbox };
    try std.testing.expectEqual(FaceButton.a, Prompt.of(&st, .a).face.button);
    try std.testing.expect(!Prompt.of(&st, .y).face.sony);
    try std.testing.expectEqualStrings("RB", Prompt.of(&st, .rb).pill);
    try std.testing.expect(Prompt.of(&st, .character) == .menu);
    try std.testing.expect(Prompt.of(&st, .pause) == .view);
    st.device = .ps5;
    try std.testing.expect(Prompt.of(&st, .x).face.sony);
    try std.testing.expectEqualStrings("L1", Prompt.of(&st, .lb).pill);
    try std.testing.expectEqualStrings("Options", Prompt.of(&st, .character).pill);
    try std.testing.expectEqualStrings("Create", Prompt.of(&st, .pause).pill);
    st.device = .ps4;
    try std.testing.expectEqualStrings("Share", Prompt.of(&st, .pause).pill);
    st = .{ .device = .keys, .modifier = .lb };
    try std.testing.expectEqualStrings(input.SECOND_CAPTION, Prompt.of(&st, .lb).key);
    try std.testing.expectEqualStrings("1", Prompt.of(&st, .a).key);
    try std.testing.expectEqualStrings("Enter", Prompt.menuOf(&st, .a).key);
    try std.testing.expectEqualStrings("Esc", Prompt.menuOf(&st, .b).key);
    try std.testing.expectEqualStrings("Q", Prompt.menuOf(&st, .lb).key);
    try std.testing.expectEqualStrings("E", Prompt.menuOf(&st, .rb).key);
    for (input.SLOT_ORDER) |b| {
        for ([_]input.Device{ .xbox, .ps4 }) |d| {
            st.device = d;
            switch (Prompt.of(&st, b)) {
                .face => |f| try std.testing.expect(faceInk(f.button, d.playstation()).a == 255),
                else => {},
            }
        }
    }
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

test "the wall sheet's masks and face height are the ones its export script paints" {
    try ground.expectLuaList(u8, &WALL_MASKS, "tools/tile_art/wall_masks.lua", "return {");
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
