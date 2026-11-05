const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../map/grid.zig");
const actor = @import("../play/actor.zig");
const skillbar = @import("../play/skillbar.zig");
const ground = @import("ground.zig");
const line_icons = @import("line_icons.zig");
const shaders = @import("shaders.zig");
const raster = @import("raster.zig");
const look = @import("look.zig");
const sprite_assets = @import("sprite_assets.zig");
const sprite_materials = @import("sprite_materials.zig");

pub const Piece = struct { tex: rl.Texture2D, src: rl.Rectangle };

pub const Mirrors = struct { live: rl.Texture2D, memory: rl.Texture2D };

pub const WaterView = struct {
    screen: [2]f32,
    visibility: rl.Texture2D,
    glints: rl.Texture2D,
    mirror: ?Mirrors = null,
    shimmer: bool = false,
    seconds: f32 = 0,
};

/// Needs a live GL context.
pub const Sprites = struct {
    bodies: sprite_assets.Bodies = .initFill(null),
    grass2: ?rl.Texture2D = null,
    dirt2: ?rl.Texture2D = null,
    shallows2: ?rl.Texture2D = null,
    shallows3: ?rl.Texture2D = null,
    shallows_cliff: ?rl.Texture2D = null,
    shallows_cliff_cap: ?rl.Texture2D = null,
    water_cliff: ?rl.Texture2D = null,
    water_cliff_cap: ?rl.Texture2D = null,
    dirt_shallows_edges: ?rl.Texture2D = null,
    dirt_water_edges: ?rl.Texture2D = null,
    shallows_water_edges: ?rl.Texture2D = null,
    shallows_water_cap: ?rl.Texture2D = null,
    shrub2: ?rl.Texture2D = null,
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
    wall: [sprite_assets.WALL_MASKS.len]?rl.Texture2D = @splat(null),
    forest: [sprite_assets.WALL_MASKS.len]?rl.Texture2D = @splat(null),
    /// Each ground's whole sheet, drawn a piece at a time so a ground's pieces batch.
    grounds: std.EnumArray(ground.Ground, ?rl.Texture2D) = .initFill(null),
    /// Every skill's icon side by side, in `skillbar.Act`'s order, inked once rather than every frame.
    skills: ?rl.Texture2D = null,
    /// Every item kind's icon at each `line_icons.ItemSize`, a strip per size.
    item_icons: ?rl.Texture2D = null,
    hud_border: ?rl.Texture2D = null,
    log_fade: ?sprite_materials.FadeShader = null,
    water: ?sprite_materials.WaterShader = null,
    bank_cap: ?sprite_materials.BankCapShader = null,
    water_face: ?sprite_materials.WaterFaceShader = null,
    shine: ?sprite_materials.ShineShader = null,
    scenery: ?sprite_materials.SceneryShader = null,
    mirror: ?rl.RenderTexture2D = null,
    mirror_memory: ?rl.RenderTexture2D = null,

    pub fn loadCommon(self: *Sprites) void {
        self.skills = line_icons.skillIcons();
        self.item_icons = line_icons.itemIcons();
        self.loadBorder();
        self.log_fade = shaders.program(sprite_materials.FadeShader, sprite_materials.FADE_FS);
        self.water = shaders.program(sprite_materials.WaterShader, sprite_materials.WATER_FS);
        self.bank_cap = shaders.program(sprite_materials.BankCapShader, sprite_materials.BANK_CAP_FS);
        self.water_face = shaders.program(sprite_materials.WaterFaceShader, sprite_materials.WATER_FACE_FS);
        self.shine = shaders.program(sprite_materials.ShineShader, sprite_materials.SHINE_FS);
        self.scenery = shaders.program(sprite_materials.SceneryShader, sprite_materials.SCENERY_FS);
    }

    pub fn loadBorder(self: *Sprites) void {
        if (self.hud_border == null) self.hud_border = texture(HUD_BORDER_PNG);
    }

    pub fn drawScenery(self: *const Sprites, tex: rl.Texture2D, dest: rl.Rectangle, view: shaders.MapView, lightmap: rl.Texture2D, fogmap: rl.Texture2D, occlusion: look.Occlusion, focus: look.Focused) bool {
        if (!self.beginScenery(view, lightmap, fogmap, occlusion, focus)) return false;
        defer rl.endShaderMode();
        raster.stretch(tex, dest, look.LIT);
        return true;
    }

    pub fn beginScenery(self: *const Sprites, view: shaders.MapView, lightmap: rl.Texture2D, fogmap: rl.Texture2D, occlusion: look.Occlusion, focus: look.Focused) bool {
        const s = self.scenery orelse return false;
        rl.beginShaderMode(s.shader);
        shaders.setMapView(s, view);
        occlusion.set(s);
        focus.set(s);
        rl.setShaderValueTexture(s.shader, s.lightmap, lightmap);
        rl.setShaderValueTexture(s.shader, s.fogmap, fogmap);
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

    pub fn sync(self: *Sprites, need: sprite_assets.Assets) void {
        inline for (comptime std.meta.fieldNames(@TypeOf(sprite_assets.SOURCES))) |name| {
            const held = &@field(self, name);
            const wants = @field(need, name);
            const src = @field(sprite_assets.SOURCES, name);
            switch (@typeInfo(@TypeOf(held.*))) {
                .optional => syncTexture(held, wants, src),
                .array => syncShapes(held, wants, src),
                else => for (std.enums.values(@TypeOf(wants).Key)) |k| syncTexture(held.getPtr(k), wants.contains(k), src.get(k)),
            }
        }
    }

    fn groundPiece(self: *const Sprites, g: ground.Ground, mask: u4, p: mathx.P) ?Piece {
        if (mask == ground.FULL) {
            if (self.alternateAt(g, p)) |tex| return .{ .tex = tex, .src = raster.whole(tex) };
        }
        const tex = self.grounds.getPtrConst(g).* orelse return null;
        const at = ground.CELL_OF[mask];
        return .{ .tex = tex, .src = sprite_assets.sheetCell(at.x, at.y) };
    }

    fn alternateAt(self: *const Sprites, g: ground.Ground, p: mathx.P) ?rl.Texture2D {
        switch (g) {
            inline else => |k| if (comptime sprite_assets.GROUND_ALTERNATES.get(k)) |alts| {
                const roll = mathx.cellHash(alts.seed, p) % alts.in;
                inline for (alts.fields, 0..) |name, i| {
                    if (roll == i) return @field(self, name);
                }
            },
        }
        return null;
    }

    /// The grounds with a sheet loaded.
    pub fn sheets(self: *const Sprites) ground.Grounds {
        var s = ground.Grounds.initEmpty();
        for (std.enums.values(ground.Ground)) |g| s.setPresent(g, self.grounds.getPtrConst(g).* != null);
        return s;
    }

    /// Draw lowest layers first; `origin` is cell (0, 0)'s top-left and `px` is pixels per cell.
    /// `tiles.at(p)` is the tile drawn at `p`: a level, or play's presented picture of one.
    pub fn drawGround(self: *const Sprites, tiles: anytype, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView) void {
        const sheeted = self.sheets();
        for (ground.LAYERS) |gr| {
            if (!beds.shown.contains(gr)) continue;
            const sheet = sheeted.contains(gr);
            const depth = if (sheet) look.waterDepth(gr) else null;
            const reflective = if (depth) |d| self.beginWater(water, origin, px, d) else false;
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
                    raster.blit(piece.tex, piece.src, pointRect(at, px), look.LIT);
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
                    const decor = sprite_assets.grassDecor(tiles.at(p), p) orelse continue;
                    const tex = (switch (decor) {
                        inline else => |k| @field(self, @tagName(k)),
                    }) orelse continue;
                    const at = cellAt(origin, p, px);
                    raster.stretch(tex, .{ .x = at[0], .y = at[1], .width = px, .height = px }, look.LIT);
                }
            }
            if (reflective) rl.endShaderMode();
        }
        self.drawWaterCliffs(beds, origin, px, water);
        self.drawWaterEdges(beds, origin, px, water);
    }

    pub fn drawWaterEdges(self: *const Sprites, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView) void {
        inline for (sprite_assets.WATER_EDGES) |pair| if (@field(self, pair.name)) |tex| {
            for (std.enums.values(WaterBand)) |band| {
                const depth = band.depth();
                const surface = band.surface() and self.beginWater(water, origin, px, depth);
                const face = if (band.face()) self.waterFace(water) else null;
                if (face) |f| f.begin(depth);
                var points = beds.points();
                while (points.next()) |p| {
                    const corners = beds.pointAt(p).corners;
                    const mask = corners.edgeMask(pair.upper, pair.lower) orelse continue;
                    const cell = ground.CELL_OF[mask];
                    const src = sprite_assets.sheetCell(cell.x + @as(i32, @intCast(@intFromEnum(band) * ground.COLS)), cell.y);
                    const at = cellAt(origin, p, px);
                    if (corners.pairMask(pair.upper, pair.lower) != null) {
                        raster.blit(tex, src, pointRect(at, px), look.LIT);
                    } else for (0..4) |q| {
                        if (!corners.edgeQuarter(pair.upper, pair.lower, q)) continue;
                        const dx = @as(f32, @floatFromInt(q % 2)) / 2;
                        const dy = @as(f32, @floatFromInt(q / 2)) / 2;
                        const quarter_src = rl.Rectangle{ .x = src.x + dx * look.SPRITE_PX, .y = src.y + dy * look.SPRITE_PX, .width = look.SPRITE_PX / 2, .height = look.SPRITE_PX / 2 };
                        raster.blit(tex, quarter_src, .{ .x = at[0] + (dx - 0.5) * px, .y = at[1] + (dy - 0.5) * px, .width = px / 2, .height = px / 2 }, look.LIT);
                    }
                }
                if (surface or face != null) rl.endShaderMode();
            }
        };
    }

    fn drawWaterCliffs(self: *const Sprites, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView) void {
        if (self.shallows_cliff == null and self.water_cliff == null) return;
        for (std.enums.values(ground.Bank)) |bank| {
            self.drawWaterBankFaces(beds, origin, px, water, bank);
            self.drawWaterBankCaps(beds, origin, px, water, bank);
        }
    }

    pub fn drawWaterCliffFaces(self: *const Sprites, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView) void {
        for (std.enums.values(ground.Bank)) |bank| self.drawWaterBankFaces(beds, origin, px, water, bank);
    }

    fn drawWaterBankFaces(self: *const Sprites, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView, bank: ground.Bank) void {
        const face = self.waterFace(water);
        var bound: ?f32 = null;
        var points = beds.points();
        while (points.next()) |p| {
            const piece = beds.pointAt(p).corners.waterCliffFor(bank) orelse continue;
            const at = cellAt(origin, p, px);
            for (0..2) |side| {
                const depth = beds.ground(p.add(.{ .x = piece.wetSide(side), .y = 0 })) orelse continue;
                const tex = (if (depth == .water) self.water_cliff else self.shallows_cliff) orelse continue;
                if (face) |f| {
                    const d = look.waterDepth(depth).?;
                    if (bound != d) {
                        if (bound != null) rl.gl.rlDrawRenderBatchActive();
                        f.begin(d);
                        bound = d;
                    }
                }
                const half = bankHalf(piece, side, at, px);
                raster.blit(tex, half.src, half.dst, look.LIT);
            }
        }
        if (bound != null) rl.endShaderMode();
    }

    /// `side`'s half of `piece`'s face or cap cell, and where it stands over the point at `at`.
    fn bankHalf(piece: ground.BankPiece, side: usize, at: [2]f32, px: f32) struct { src: rl.Rectangle, dst: rl.Rectangle } {
        const shift = sideShift(side);
        var src = sprite_assets.sheetCell(piece.col(), 0);
        src.x += shift * look.SPRITE_PX;
        src.width /= 2;
        return .{ .src = src, .dst = .{ .x = at[0] + (shift - 0.5) * px, .y = at[1] - px * ground.BANK_LIFT, .width = px / 2, .height = px } };
    }

    fn sideShift(side: usize) f32 {
        return @as(f32, @floatFromInt(side)) / 2;
    }

    pub fn drawWaterCliffCaps(self: *const Sprites, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView) void {
        for (std.enums.values(ground.Bank)) |bank| self.drawWaterBankCaps(beds, origin, px, water, bank);
    }

    fn drawWaterBankCaps(self: *const Sprites, beds: *const ground.Beds, origin: [2]f32, px: f32, water: ?WaterView, bank: ground.Bank) void {
        var points = beds.points();
        while (points.next()) |p| {
            const piece = beds.pointAt(p).corners.waterCliffFor(bank) orelse continue;
            const at = cellAt(origin, p, px);
            for (0..2) |side| {
                const north = p.add(.{ .x = @as(i32, @intCast(side)) - 1, .y = -1 });
                const gr = beds.ground(north) orelse continue;
                const depth = beds.ground(p.add(.{ .x = piece.wetSide(side), .y = 0 })) orelse continue;
                if (!ground.bankAbove(gr.tile(), depth.tile())) continue;
                const fill = self.bankFill(gr) orelse continue;
                const reflective = if (look.waterDepth(gr)) |d| self.beginWater(water, origin, px, d) else false;
                raster.blit(fill.piece.tex, fill.lowerQuarter(side), .{ .x = at[0] + (sideShift(side) - 0.5) * px, .y = at[1] - px / 2, .width = px / 2, .height = px / 2 }, look.LIT);
                if (reflective) rl.endShaderMode();
            }
            for (0..2) |side| {
                const land = p.add(.{ .x = @as(i32, @intCast(side)) - 1, .y = if (piece.outside(side)) 0 else -1 });
                const depth = beds.ground(p.add(.{ .x = piece.wetSide(side), .y = 0 })) orelse continue;
                const cap = (if (depth == .water) self.water_cliff_cap else self.shallows_cliff_cap) orelse continue;
                const gr = beds.ground(land) orelse continue;
                if (!ground.bankAbove(gr.tile(), depth.tile())) continue;
                const fill = self.bankFill(gr);
                const mask = Piece{ .tex = cap, .src = sprite_assets.sheetCell(piece.col(), 0) };
                const wet_cap = if (gr == .shallows) self.shallows_water_cap else null;
                const reflective = wet_cap != null and self.beginWater(water, origin, px, look.WATER_SHALLOW);
                if (!reflective and !self.beginGroundFill(mask, fill, look.tileBg(gr.tile()) orelse rl.Color.blank)) continue;
                const half = bankHalf(piece, side, at, px);
                raster.blit(if (reflective) wet_cap.? else cap, half.src, half.dst, look.LIT);
                rl.endShaderMode();
            }
        }
    }

    /// Land drawn into a bank's cap: a sheet's full cell, set on the dual grid, or a whole tile picture, set on its own cell.
    const BankFill = struct {
        piece: Piece,
        sheet: bool,

        /// Where its picture continues in the lower quarter of the cell north-west (side 0) or north-east (side 1) of a point.
        fn lowerQuarter(self: BankFill, side: usize) rl.Rectangle {
            const shift = sideShift(side);
            var src = self.piece.src;
            if (self.sheet) {
                src.x += shift * src.width;
            } else {
                src.x += (0.5 - shift) * src.width;
                src.y += src.height / 2;
            }
            src.width /= 2;
            src.height /= 2;
            return src;
        }

        /// The cap shader's shift from the cap cell, `BANK_LIFT` above the point's row, into this picture's frame.
        fn offset(self: BankFill) [2]f32 {
            return if (self.sheet) .{ 0, 0.5 - ground.BANK_LIFT } else .{ 0.5, 1 - ground.BANK_LIFT };
        }
    };

    fn bankFill(self: *const Sprites, gr: ground.Ground) ?BankFill {
        if (self.grounds.getPtrConst(gr).*) |tex| {
            const cell = ground.CELL_OF[ground.FULL];
            return .{ .piece = .{ .tex = tex, .src = sprite_assets.sheetCell(cell.x, cell.y) }, .sheet = true };
        }
        const tex = self.tiles.getPtrConst(gr.tile()).* orelse return null;
        return .{ .piece = .{ .tex = tex, .src = raster.whole(tex) }, .sheet = false };
    }

    fn beginGroundFill(self: *const Sprites, mask: Piece, maybe: ?BankFill, color: rl.Color) bool {
        const s = self.bank_cap orelse return false;
        rl.beginShaderMode(s.shader);
        rl.gl.rlDrawRenderBatchActive();
        shaders.setUniform(s.shader, s.mask_region, raster.uvOf(mask.tex, mask.src));
        shaders.setUniform(s.shader, s.textured, maybe != null);
        if (maybe) |fill| {
            const piece = fill.piece;
            shaders.setUniform(s.shader, s.offset, fill.offset());
            shaders.setUniform(s.shader, s.region, raster.uvOf(piece.tex, piece.src));
            rl.setShaderValueTexture(s.shader, s.land, piece.tex);
        } else shaders.setUniform(s.shader, s.solid, look.rgbaOf(color));
        return true;
    }

    const WaterFace = struct {
        s: sprite_materials.WaterFaceShader,
        screen: [2]f32,

        fn begin(f: WaterFace, depth: f32) void {
            rl.beginShaderMode(f.s.shader);
            shaders.setUniform(f.s.shader, f.s.screen, f.screen);
            shaders.setUniform(f.s.shader, f.s.depth, depth);
        }
    };

    fn waterFace(self: *const Sprites, view: ?WaterView) ?WaterFace {
        const v = view orelse return null;
        return .{ .s = self.water_face orelse return null, .screen = v.screen };
    }

    fn beginWater(self: *const Sprites, view: ?WaterView, origin: [2]f32, px: f32, depth: f32) bool {
        const v = view orelse return false;
        const s = self.water orelse return false;
        rl.beginShaderMode(s.shader);
        shaders.setMapView(s, .{ .origin = origin, .cell = px, .screen = v.screen });
        shaders.setUniform(s.shader, s.depth, depth);
        shaders.setUniform(s.shader, s.mirrored, v.mirror != null);
        shaders.setUniform(s.shader, s.shimmer, v.shimmer);
        shaders.setUniform(s.shader, s.seconds, v.seconds);
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

    /// A cell's square centred on the dual-grid point at `at`.
    fn pointRect(at: [2]f32, px: f32) rl.Rectangle {
        return .{ .x = at[0] - px / 2, .y = at[1] - px / 2, .width = px, .height = px };
    }

    /// The part of a ground's square from `uv` across `span`, fractions of the cell: its picture, else its colour.
    fn squarePart(self: *const Sprites, t: grid.Tile, cell: [2]f32, px: f32, uv: [2]f32, span: f32) void {
        const dest = rl.Rectangle{ .x = cell[0] + uv[0] * px, .y = cell[1] + uv[1] * px, .width = span * px, .height = span * px };
        if (self.tiles.getPtrConst(t).*) |tex| {
            const w, const h = raster.sizeOf(tex);
            raster.blit(tex, .{ .x = uv[0] * w, .y = uv[1] * h, .width = span * w, .height = span * h }, dest, look.LIT);
        } else if (look.tileBg(t)) |bg| rl.drawRectangleRec(dest, bg);
    }

    pub fn unload(self: *Sprites) void {
        raster.unloadAll(self);
    }

    pub fn body(self: *const Sprites, k: actor.Kind) ?rl.Texture2D {
        return self.bodies.getPtrConst(k).*;
    }

    pub fn figures(self: *const Sprites) [sprite_assets.FIGURES]?rl.Texture2D {
        var casters: [sprite_assets.PICTURE_CASTERS.len]?rl.Texture2D = undefined;
        for (sprite_assets.PICTURE_CASTERS, &casters) |t, *s| s.* = self.tiles.getPtrConst(t).*;
        const props: [sprite_assets.PROP_FIGURES]?rl.Texture2D = .{ self.item_bag, self.chest_item_bag, self.mimic_closed, self.shrub2 };
        return self.litFigures() ++ casters ++ self.forest ++ props;
    }

    fn litFigures(self: *const Sprites) [sprite_assets.LIT_FIGURES]?rl.Texture2D {
        return self.bodies.values ++ [_]?rl.Texture2D{self.barrel};
    }

    pub fn tileAt(self: *const Sprites, lv: *const grid.Level, p: mathx.P) ?rl.Texture2D {
        return self.cut(sprite_assets.cutAt(lv, p) orelse return null);
    }

    pub fn tileOf(self: *const Sprites, t: grid.Tile, shape: ?grid.WallShape) ?rl.Texture2D {
        return self.cut(sprite_assets.cutOf(t, shape) orelse return null);
    }

    fn cut(self: *const Sprites, c: sprite_assets.Cut) ?rl.Texture2D {
        return switch (c) {
            .tile => |t| self.tiles.getPtrConst(t).*,
            .wall => |i| self.wall[i],
            .forest => |i| self.forest[i],
            .shrub2 => self.shrub2,
        };
    }

    pub fn count(self: *const Sprites) usize {
        return self.resident().count();
    }

    pub fn resident(self: *const Sprites) sprite_assets.Assets {
        var held = sprite_assets.Assets{};
        inline for (std.meta.fields(sprite_assets.Assets)) |f| {
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

    fn syncTexture(t: *?rl.Texture2D, needed: bool, png: ?[]const u8) void {
        if (!needed) raster.release(t);
        if (needed and t.* == null) t.* = texture(png orelse return);
    }

    fn syncShapes(held: *[sprite_assets.WALL_MASKS.len]?rl.Texture2D, need: std.StaticBitSet(sprite_assets.WALL_MASKS.len), png: []const u8) void {
        var missing = false;
        for (held, 0..) |*t, i| {
            if (!need.isSet(i)) raster.release(t);
            missing = missing or (need.isSet(i) and t.* == null);
        }
        if (!missing) return;
        const sheet = rl.loadImageFromMemory(".png", png) catch return;
        defer rl.unloadImage(sheet);
        for (held, 0..) |*t, i| {
            if (need.isSet(i) and t.* == null) t.* = raster.adopt(sprite_assets.wallCell(sheet, i) orelse continue);
        }
    }

    fn texture(png: []const u8) ?rl.Texture2D {
        return raster.adopt(rl.loadImageFromMemory(".png", png) catch return null);
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

/// A ui panel's backing and border.
pub fn backing(sprites: *const Sprites, x: i32, y: i32, width: i32, height: i32) void {
    hudPanel(sprites, x, y, width, height, look.BACKING, look.LIT);
}

pub fn backingIn(sprites: *const Sprites, r: rl.Rectangle) void {
    hudPanelIn(sprites, r, look.BACKING, look.LIT);
}

fn hudBorder(sprites: *const Sprites, x: i32, y: i32, width: i32, height: i32, tint: rl.Color) void {
    const tex = sprites.hud_border orelse {
        rl.drawRectangleLines(x, y, width, height, tint);
        return;
    };
    const cut = HUD_BORDER_CUT;
    if (width < cut * 2 or height < cut * 2) return;
    const size = comptime sprite_assets.pngSize(HUD_BORDER_PNG);
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

/// A ground with neither a sheet nor a picture, which shows its glyph.
pub fn glyphGround(t: grid.Tile, sprites: *const Sprites) bool {
    const g = ground.of(t) orelse return false;
    return sprites.grounds.getPtrConst(g).* == null and sprites.tiles.getPtrConst(t).* == null;
}

const WaterBand = enum {
    dry,
    shallow,
    deep,
    shallow_face,
    deep_face,

    fn depth(self: WaterBand) f32 {
        return switch (self) {
            .shallow, .shallow_face => look.WATER_SHALLOW,
            .dry, .deep, .deep_face => look.WATER_DEEP,
        };
    }

    fn surface(self: WaterBand) bool {
        return switch (self) {
            .shallow, .deep => true,
            .dry, .shallow_face, .deep_face => false,
        };
    }

    fn face(self: WaterBand) bool {
        return switch (self) {
            .shallow_face, .deep_face => true,
            .dry, .shallow, .deep => false,
        };
    }
};

comptime {
    const size = mathx.P{ .x = std.enums.values(WaterBand).len * ground.COLS * look.SPRITE_PX, .y = ground.ROWS * look.SPRITE_PX };
    for (sprite_assets.WATER_EDGES) |e| std.debug.assert(std.meta.eql(sprite_assets.pngSize(@field(sprite_assets.SOURCES, e.name)), size));
    std.debug.assert(std.meta.eql(sprite_assets.pngSize(sprite_assets.SOURCES.shallows_water_cap), mathx.P{ .x = ground.BankPiece.COUNT * look.SPRITE_PX, .y = look.SPRITE_PX }));
}
test "the hud border's size and corner cut are the ones its export script checks" {
    const path = "tools/hud_art/export_border.lua";
    const size = comptime sprite_assets.pngSize(HUD_BORDER_PNG);
    try ground.expectLuaList(i32, &.{size.x}, path, "local W=");
    try ground.expectLuaList(i32, &.{size.y}, path, "local H=");
    try ground.expectLuaList(i32, &.{HUD_BORDER_CUT}, path, "local CUT=");
}

test "water material bands and cap sampling match the tile-art exporter" {
    try ground.expectLuaList(WaterBand, std.enums.values(WaterBand), "tools/tile_art/water_cliff_materials.lua", "local bands={");
    try ground.expectLuaList(i32, &.{@intFromFloat(ground.BANK_LIFT_PX)}, "tools/tile_art/export_water_edges.lua", "local BANK_LIFT=");
    const cap = try rl.loadImageFromMemory(".png", sprite_assets.SOURCES.shallows_water_cap);
    defer rl.unloadImage(cap);
    const mask = try rl.loadImageFromMemory(".png", sprite_assets.SOURCES.water_cliff_cap);
    defer rl.unloadImage(mask);
    const water = try rl.loadImageFromMemory(".png", sprite_assets.GROUND_PNGS.get(.shallows).?);
    defer rl.unloadImage(water);
    const cell = ground.CELL_OF[ground.FULL];
    const lift: i32 = @intFromFloat(ground.BANK_LIFT_PX);
    var covered: usize = 0;
    var y: i32 = 0;
    while (y < cap.height) : (y += 1) {
        var x: i32 = 0;
        while (x < cap.width) : (x += 1) {
            const actual = rl.getImageColor(cap, x, y);
            if (rl.getImageColor(mask, x, y).a == 0) {
                try std.testing.expectEqual(@as(u8, 0), actual.a);
                continue;
            }
            const expected = rl.getImageColor(water, cell.x * look.SPRITE_PX + @mod(x, look.SPRITE_PX), cell.y * look.SPRITE_PX + @mod(y + look.SPRITE_PX / 2 - lift, look.SPRITE_PX));
            try std.testing.expectEqual(expected, actual);
            covered += 1;
        }
    }
    try std.testing.expect(covered > 0);
    std.debug.print("water export: {d} named material bands, {d} cap pixels aligned at bank lift {d}\n", .{ std.enums.values(WaterBand).len, covered, lift });
}

test "the deep water sheet is the shallows' at WATER_DEEP_PERCENT, as deepen_water.lua rounds it" {
    try ground.expectLuaList(i32, &.{look.WATER_DEEP_PERCENT}, "tools/tile_art/deepen_water.lua", "local percent=tonumber(app.params.percent) or ");
    const shallow = try rl.loadImageFromMemory(".png", sprite_assets.GROUND_PNGS.get(.shallows).?);
    defer rl.unloadImage(shallow);
    const deep = try rl.loadImageFromMemory(".png", sprite_assets.GROUND_PNGS.get(.water).?);
    defer rl.unloadImage(deep);
    try std.testing.expectEqual(shallow.width, deep.width);
    try std.testing.expectEqual(shallow.height, deep.height);
    const Lua = struct {
        fn channel(v: u8) u8 {
            return @intCast((@as(u32, v) * look.WATER_DEEP_PERCENT + mathx.PERCENT / 2) / mathx.PERCENT);
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
