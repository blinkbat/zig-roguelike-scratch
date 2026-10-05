const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const actor = @import("../play/actor.zig");
const skillbar = @import("../play/skillbar.zig");
const font = @import("font.zig");

pub const SPRITE_PX: i32 = 64;
pub const WALL_FACE_PX: i32 = 11;
/// A body or tile with no sprite draws its glyph this big, at `SPRITE_PX`.
pub const GLYPH_PX: i32 = 60;

pub const Look = struct {
    ch: u8,
    fg: rl.Color,
};

pub const Bodies = std.EnumArray(actor.Kind, ?rl.Texture2D);

/// How a standing tile casts: its silhouette, as a body does, or a tree's canopy pool.
pub const Shadow = enum { silhouette, canopy };

const STANDS = std.EnumArray(grid.Tile, ?Shadow).initDefault(@as(?Shadow, null), .{
    .shrub = .canopy,
    .tiny_shrub = .canopy,
    .boulder = .silhouette,
    .fungus = .silhouette,
    .tall_grass = .silhouette,
    .shrooms = .silhouette,
});

pub const STANDING = blk: {
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

/// Every sprite whose silhouette casts: the bodies, the barrel, then the standing tiles.
pub const FIGURES: usize = Bodies.len + 1 + STANDING.len;

/// Needs a live GL context.
pub const Sprites = struct {
    bodies: Bodies = .initFill(null),
    barrel: ?rl.Texture2D = null,
    tiles: std.EnumArray(grid.Tile, ?rl.Texture2D) = .initFill(null),
    wall: std.EnumArray(grid.WallShape, ?rl.Texture2D) = .initFill(null),
    /// Every skill's icon side by side, in `skillbar.Act`'s order, inked once rather than every frame.
    skills: ?rl.Texture2D = null,

    pub fn load() Sprites {
        var s = Sprites{ .barrel = texture(@embedFile("barrel.png")), .skills = skillIcons() };
        for (std.enums.values(actor.Kind)) |k| s.bodies.set(k, texture(BODY_PNGS.get(k) orelse continue));
        for (std.enums.values(grid.Tile)) |t| s.tiles.set(t, texture(TILE_PNGS.get(t) orelse continue));
        const sheet = rl.loadImageFromMemory(".png", WALLS_PNG) catch return s;
        defer rl.unloadImage(sheet);
        for (std.enums.values(grid.WallShape)) |shape| {
            const cell = WALL_CELLS.get(shape) orelse continue;
            s.wall.set(shape, toTexture(wallCell(sheet, cell) orelse continue));
        }
        return s;
    }

    pub fn unload(self: *Sprites) void {
        unloadAll(self);
    }

    pub fn body(self: *const Sprites, k: actor.Kind) ?rl.Texture2D {
        return self.bodies.getPtrConst(k).*;
    }

    pub fn figures(self: Sprites) [FIGURES]?rl.Texture2D {
        var standing: [STANDING.len]?rl.Texture2D = undefined;
        for (STANDING, &standing) |t, *s| s.* = self.tiles.get(t);
        return self.bodies.values ++ [_]?rl.Texture2D{self.barrel} ++ standing;
    }

    pub fn tileAt(self: *const Sprites, lv: *const grid.Level, p: mathx.P) ?rl.Texture2D {
        return self.tileOf(lv.at(p), lv.wallShape(p));
    }

    pub fn tileOf(self: *const Sprites, t: grid.Tile, shape: ?grid.WallShape) ?rl.Texture2D {
        if (t == .wall) return self.wall.getPtrConst(shape orelse return null).*;
        return self.tiles.getPtrConst(t).*;
    }

    fn texture(png: []const u8) ?rl.Texture2D {
        return toTexture(rl.loadImageFromMemory(".png", png) catch return null);
    }

    fn toTexture(img: rl.Image) ?rl.Texture2D {
        defer rl.unloadImage(img);
        return rl.loadTextureFromImage(img) catch null;
    }
};

const BODY_PNGS = std.EnumArray(actor.Kind, ?[]const u8).init(.{
    .archer = @embedFile("archer.png"),
    .rat = @embedFile("rat.png"),
    .slime = @embedFile("slime.png"),
    .slime_half = @embedFile("slime-half.png"),
    .slime_quarter = @embedFile("slime-quarter.png"),
    .bloat = @embedFile("bloat.png"),
    .pib = @embedFile("pib.png"),
});

/// A wall's are cut from `WALLS_PNG` by its shape instead.
const TILE_PNGS = std.EnumArray(grid.Tile, ?[]const u8).initDefault(@as(?[]const u8, null), .{
    .floor = @embedFile("floor.png"),
    .grass = @embedFile("grass.png"),
    .shrub = @embedFile("shrub.png"),
    .tiny_shrub = @embedFile("tiny-shrub.png"),
    .boulder = @embedFile("boulder.png"),
    .fungus = @embedFile("tall-shroom.png"),
    .tall_grass = @embedFile("tall-grass.png"),
    .shrooms = @embedFile("small-shrooms.png"),
});

comptime {
    std.debug.assert(TILE_PNGS.get(.wall) == null);
}

const WALLS_PNG = @embedFile("walls.png");

const WallCell = struct { col: i32, row: i32 };

const WALL_CELLS = std.EnumArray(grid.WallShape, ?WallCell).init(.{
    .corner_tl = .{ .col = 0, .row = 0 },
    .top = .{ .col = 1, .row = 0 },
    .corner_tr = .{ .col = 2, .row = 0 },
    .left = .{ .col = 0, .row = 1 },
    .right = .{ .col = 2, .row = 1 },
    .corner_bl = .{ .col = 0, .row = 2 },
    .bottom = .{ .col = 1, .row = 2 },
    .corner_br = .{ .col = 2, .row = 2 },
    .block_tl = .{ .col = 5, .row = 1 },
    .block_tr = .{ .col = 6, .row = 1 },
    .block_bl = .{ .col = 5, .row = 2 },
    .block_br = .{ .col = 6, .row = 2 },
    .post = .{ .col = 8, .row = 1 },
    .solid = .{ .col = 9, .row = 1 },
});

/// raylib's `imageFromImage` copies without clamping, so a cell off the sheet would read past it.
fn wallCell(sheet: rl.Image, c: WallCell) ?rl.Image {
    if ((c.col + 1) * SPRITE_PX > sheet.width or (c.row + 1) * SPRITE_PX > sheet.height) return null;
    return rl.imageFromImage(sheet, rect(c.col * SPRITE_PX, c.row * SPRITE_PX, SPRITE_PX, SPRITE_PX));
}

pub fn whole(t: rl.Texture2D) rl.Rectangle {
    return rect(0, 0, t.width, t.height);
}

pub fn rect(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(h) };
}

pub fn stretch(t: rl.Texture2D, dest: rl.Rectangle, tint: rl.Color) void {
    rl.drawTexturePro(t, whole(t), dest, .{ .x = 0, .y = 0 }, 0, tint);
}

/// Stretched over the whole floor, its top-left corner at `ox, oy`.
pub fn overFloor(t: rl.Texture2D, ox: i32, oy: i32, cell: i32) void {
    stretch(t, rect(ox, oy, grid.W * cell, grid.H * cell), LIT);
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

/// Null when it does not compile: raylib then hands back its default shader rather than an error.
pub fn shader(fs: [:0]const u8) ?rl.Shader {
    const s = rl.loadShaderFromMemory(null, fs) catch return null;
    return if (s.id == rl.gl.rlGetShaderIdDefault()) null else s;
}

/// Every field but `shader` is the location of the GLSL uniform it is named for.
fn uniforms(comptime T: type, s: rl.Shader) T {
    var u: T = undefined;
    u.shader = s;
    inline for (std.meta.fields(T)) |f| {
        if (comptime std.mem.eql(u8, f.name, "shader")) continue;
        @field(u, f.name) = rl.getShaderLocation(s, f.name);
    }
    return u;
}

/// `fs` loaded with `uniforms` found in it; a field it declares no uniform for is a compile error.
pub fn program(comptime T: type, comptime fs: [:0]const u8) ?T {
    comptime {
        @setEvalBranchQuota(100_000);
        for (std.meta.fields(T)) |f| {
            if (!std.mem.eql(u8, f.name, "shader") and !declares(fs, f.name)) @compileError("no uniform " ++ f.name ++ " in the shader for " ++ @typeName(T));
        }
    }
    return uniforms(T, shader(fs) orelse return null);
}

fn declares(comptime fs: []const u8, comptime name: []const u8) bool {
    var lines = std.mem.splitScalar(u8, fs, '\n');
    while (lines.next()) |l| {
        const line = std.mem.trim(u8, l, " \t\r");
        if (!std.mem.startsWith(u8, line, "uniform ")) continue;
        const end = std.mem.indexOfAny(u8, line, "[;") orelse continue;
        const head = std.mem.trimRight(u8, line[0..end], " ");
        const at = std.mem.lastIndexOfScalar(u8, head, ' ') orelse continue;
        if (std.mem.eql(u8, head[at + 1 ..], name)) return true;
    }
    return false;
}

/// Each texture, render texture and shader `v` holds, a `program`'s too, unloaded and nulled.
pub fn unloadAll(v: anytype) void {
    inline for (std.meta.fields(@TypeOf(v.*))) |f| {
        if (comptime @typeInfo(f.type) == .@"struct" and @hasField(f.type, "values") and @hasDecl(f.type, "Key")) {
            for (&@field(v.*, f.name).values) |*held| {
                if (held.*) |t| rl.unloadTexture(t);
                held.* = null;
            }
            continue;
        }
        const Child = switch (@typeInfo(f.type)) {
            .optional => |o| o.child,
            else => void,
        };
        const program_ = @typeInfo(Child) == .@"struct" and @hasField(Child, "shader");
        const resource = Child == rl.Texture2D or Child == rl.RenderTexture2D or Child == rl.Shader or program_;
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
pub const LIT = rl.Color.white;
const FLOOR_BG = rgb(0x121116);
const GRASS_BG = rgb(0x111a0e);
/// The editor's wall where it has no texture.
pub const BARE_WALL = rgb(0x1e1c24);
/// The editor's ground of a procgen node, whose floor is only rolled in play.
pub const UNROLLED = rgb(0x1b2330);
pub const TEXT = rgb(0xd8cdb4);
pub const DIM = rgb(0x8c8672);
pub const LIFE = rgb(0x9c2f2a);
pub const LIFE_BG = fade(LIFE, 0.25);
pub const MANA = rgb(0x326cb5);
pub const MANA_BG = fade(MANA, 0.25);
pub const FIRE = rgb(0xff8a32);
pub const FIRE_CORE = rgb(0xffe6a0);
pub const BLEED = rgb(0xd8483a);
pub const EDGE = rgb(0x4a4438);
pub const ARROW = rgb(0xe6dcb4);
pub const VEIL = fade(BG, 0.72);

/// Its symbol, centred on `cx, cy`; its ASCII `ch` where the font has no atlas.
pub fn inkTile(face: *const font.Face, t: grid.Tile, cx: i32, cy: i32, size: i32) void {
    const l = TILES.get(t);
    face.symbol(l.sym, l.ch, cx, cy, size, l.fg);
}

/// Under a tile's glyph where it has no sprite; null leaves the background.
pub fn tileBg(t: grid.Tile) ?rl.Color {
    return TILES.get(t).bg;
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
    .reeds = .{ .sym = "¦", .ch = '|', .fg = rgb(0xa8b24a), .bg = rgb(0x161a0c), .mini = rgb(0x6a7030), .mini_dim = rgb(0x32361a) },
    .rubble = .{ .sym = "•", .ch = ',', .fg = rgb(0x8a7f6a), .bg = rgb(0x18161a), .mini = rgb(0x4e4840), .mini_dim = rgb(0x26241f) },
    .fence = .{ .sym = "∏", .ch = '#', .fg = rgb(0x9a6638), .bg = GRASS_BG, .mini = rgb(0x7a5030), .mini_dim = rgb(0x3a2818) },
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
});

comptime {
    for (TILES.values) |l| std.debug.assert(l.sym.len != 1 or l.sym[0] == l.ch);
}

/// Every symbol a tile draws, for the font to bake.
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
pub const COIN = GOLD;

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
        .rat => .{ .ch = 'r', .fg = rgb(0xb07a4e) },
        .slime, .slime_half, .slime_quarter => .{ .ch = 's', .fg = rgb(0x6fae5a) },
        .bloat => .{ .ch = 'b', .fg = GAS },
        .pib => .{ .ch = 'p', .fg = rgb(0xe89aa6) },
    };
}

/// Brogue's `poisonGasColor`, the bloat's and its gas's.
pub const GAS = rgb(0xbf40d9);

pub const BLOOD = rl.Color{ .r = 112, .g = 22, .b = 16, .a = GORE_A };
pub const OOZE = rl.Color{ .r = 70, .g = 120, .b = 72, .a = GORE_A };
pub const SPLINTER = rl.Color{ .r = 120, .g = 82, .b = 46, .a = 230 };
/// Brogue's purple blood: the gas's, darker.
pub const ICHOR = rl.Color{ .r = GAS.r / 2, .g = GAS.g / 2, .b = GAS.b / 2, .a = GORE_A };
/// What a body sprays, as against a barrel's splinters.
const GORE_A: u8 = 220;
/// The pinprick where a blow lands.
pub const CONTACT = rl.Color{ .r = 255, .g = 244, .b = 214, .a = 180 };
pub const JUKE_TRAIL = rl.Color{ .r = 196, .g = 212, .b = 218, .a = 140 };
pub const JUKE_DUST = rl.Color{ .r = 184, .g = 161, .b = 125, .a = 170 };

pub const Gait = enum { hop, slide };

pub fn gait(k: actor.Kind) Gait {
    return switch (k) {
        .archer, .rat, .pib => .hop,
        .slime, .slime_half, .slime_quarter, .bloat => .slide,
    };
}

/// y-down, so a delta whose signs agree runs top-left to bottom-right.
pub fn arrow(dx: i32, dy: i32) u8 {
    if (dy == 0) return '-';
    if (dx == 0) return '|';
    const steep = @abs(dy) > @abs(dx) * 2;
    const flat = @abs(dx) > @abs(dy) * 2;
    if (steep) return '|';
    if (flat) return '-';
    return if ((dx > 0) == (dy > 0)) '\\' else '/';
}

pub fn mini(t: grid.Tile, lit: bool) rl.Color {
    const l = TILES.get(t);
    return if (lit) l.mini else l.mini_dim;
}

pub const AIM_REACH = fade(GOLD, 0.10);
pub const AIM_PATH = fade(GOLD, 0.28);
pub const COLD = rgb(0x8cddf5);
pub const AIM_COLD = fade(COLD, 0.24);
pub const RETICLE = rgb(0xe8c25a);
pub const LEAN_OPEN = GOLD;
pub const LEAN_FOE = FOE;
pub const LEAN_BLOCKED = SHADE;

pub fn caret(d: mathx.Dir) u8 {
    return switch (d) {
        .n => '^',
        .e => '>',
        .s => 'v',
        .w => '<',
        .ne, .se, .sw, .nw => '+',
    };
}

fn skillLines(a: skillbar.Act) []const [4]f32 {
    return switch (a) {
        .shoot => &.{
            .{ 6, 26, 26, 6 },
            .{ 16, 6, 26, 6 },
            .{ 26, 6, 26, 16 },
            .{ 5, 19, 12, 19 },
            .{ 12, 19, 12, 26 },
        },
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
    return switch (a) {
        .burning_arrow => FIRE,
        .glacial_shot => COLD,
        .shoot, .wait, .secondary, .juke => ARROW,
    };
}

pub const SKILL_PX: i32 = 40;

pub fn drawSkill(sprites: *const Sprites, a: skillbar.Act, x: i32, y: i32, alpha: f32) void {
    const ink = fade(rl.Color.white, alpha);
    const t = sprites.skills orelse return inkSkill(a, x, y, ink);
    const i: i32 = @intFromEnum(a);
    rl.drawTexturePro(t, rect(i * SKILL_PX, 0, SKILL_PX, SKILL_PX), rect(x, y, SKILL_PX, SKILL_PX), .{ .x = 0, .y = 0 }, 0, ink);
}

/// Needs a live GL context.
fn skillIcons() ?rl.Texture2D {
    const target = rl.loadRenderTexture(SKILL_PX * @as(i32, @intCast(skillbar.ACTS.len)), SKILL_PX) catch return null;
    defer rl.unloadRenderTexture(target);
    rl.beginTextureMode(target);
    rl.clearBackground(rl.Color.blank);
    for (skillbar.ACTS) |a| inkSkill(a, @as(i32, @intFromEnum(a)) * SKILL_PX, 0, rl.Color.white);
    rl.endTextureMode();
    var img = rl.loadImageFromTexture(target.texture) catch return null;
    rl.imageFlipVertical(&img);
    return Sprites.toTexture(img);
}

fn inkSkill(a: skillbar.Act, x: i32, y: i32, ink: rl.Color) void {
    const scale = @as(f32, @floatFromInt(SKILL_PX)) / 32;
    const ox: f32 = @floatFromInt(x);
    const oy: f32 = @floatFromInt(y);
    for (skillLines(a)) |line| {
        const from = rl.Vector2{ .x = ox + line[0] * scale, .y = oy + line[1] * scale };
        const to = rl.Vector2{ .x = ox + line[2] * scale, .y = oy + line[3] * scale };
        rl.drawLineEx(from, to, 2 * scale, ink);
        rl.drawCircleV(from, scale, ink);
        rl.drawCircleV(to, scale, ink);
    }
}

const PANEL = rgb(0x0e0d12);
const RAISED = rgb(0x1a1820);

pub const SLOT_BG = RAISED;
pub const SLOT_EMPTY = PANEL;
pub const SLOT_HELD = GOLD;
pub const SLOT_CURSOR = RETICLE;
pub const SLOT_CLEAR = FOE;
pub const CLEAR = Look{ .ch = 'x', .fg = SLOT_CLEAR };

/// What every fragment shader opens with: raylib's inputs and output, and the alpha below which nothing is drawn.
pub const FS_HEAD =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\uniform sampler2D texture0;
    \\out vec4 finalColor;
    \\const float CLEAR_A = 0.004;
    \\
;

pub const MINI_BG = fade(BG, 0.9);
pub const MINI_HERO = rgb(0x9cf08a);
pub const MINI_FOE = FOE;
pub const MINI_VIEW = fade(GOLD, 0.7);

pub const EDIT_PANEL = PANEL;
pub const EDIT_ROW_ON = RAISED;
pub const EDIT_ON = GOLD;
pub const EDIT_PICKED = RETICLE;
pub const EDIT_WARN = FOE;
pub const EDIT_HOVER = fade(TEXT, 0.6);
pub const EDIT_UNLINKED = DIM;

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

test "every wall shape's cell lies inside walls.png, and one past its edge is refused" {
    const w = std.mem.readInt(i32, WALLS_PNG[16..20], .big);
    const h = std.mem.readInt(i32, WALLS_PNG[20..24], .big);
    const sheet = rl.genImageColor(w, h, rl.Color.white);
    defer rl.unloadImage(sheet);
    var cut: usize = 0;
    for (WALL_CELLS.values) |c| {
        const img = wallCell(sheet, c orelse continue) orelse return error.CellOffSheet;
        rl.unloadImage(img);
        cut += 1;
    }
    std.debug.print("walls.png {d}x{d}: {d} shapes cut from it\n", .{ w, h, cut });
    try std.testing.expectEqual(std.enums.values(grid.WallShape).len, cut);
    try std.testing.expect(wallCell(sheet, .{ .col = @divTrunc(w, SPRITE_PX), .row = 0 }) == null);
    try std.testing.expect(wallCell(sheet, .{ .col = 0, .row = @divTrunc(h, SPRITE_PX) }) == null);
}

test "an arrow's glyph follows its slope" {
    try std.testing.expectEqual(@as(u8, '-'), arrow(5, 0));
    try std.testing.expectEqual(@as(u8, '|'), arrow(0, -3));
    try std.testing.expectEqual(@as(u8, '\\'), arrow(3, 3));
    try std.testing.expectEqual(@as(u8, '/'), arrow(3, -3));
    try std.testing.expectEqual(@as(u8, '-'), arrow(7, 1));
}
