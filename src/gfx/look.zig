const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const actor = @import("../play/actor.zig");
const skillbar = @import("../play/skillbar.zig");

// EVERY PICTURE IN THE GAME. A thing with a sprite in `Sprites` draws it; anything without one falls back to its glyph.

pub const SPRITE_PX: i32 = 64;
/// A body or tile with no sprite draws its glyph this big, at `SPRITE_PX`.
pub const GLYPH_PX: i32 = 60;

pub const Look = struct {
    ch: u8,
    fg: rl.Color,
};

pub const Bodies = std.EnumArray(actor.Kind, ?rl.Texture2D);

/// Every sprite lit by the body shader: the bodies, then the barrel.
pub const FIGURES: usize = Bodies.len + 1;

/// Needs a live GL context.
pub const Sprites = struct {
    bodies: Bodies = .initFill(null),
    barrel: ?rl.Texture2D = null,
    floor: ?rl.Texture2D = null,
    wall: std.EnumArray(grid.WallShape, ?rl.Texture2D) = .initFill(null),

    pub fn load() Sprites {
        var s = Sprites{ .floor = texture(@embedFile("floor.png")), .barrel = texture(@embedFile("barrel.png")) };
        for (std.enums.values(actor.Kind)) |k| s.bodies.set(k, texture(BODY_PNGS.get(k) orelse continue));
        const sheet = rl.loadImageFromMemory(".png", WALLS_PNG) catch return s;
        defer rl.unloadImage(sheet);
        for (std.enums.values(grid.WallShape)) |shape| {
            const cell = WALL_CELLS.get(shape) orelse continue;
            s.wall.set(shape, toTexture(wallCell(sheet, cell) orelse continue));
        }
        return s;
    }

    pub fn unload(self: Sprites) void {
        for ([_]?rl.Texture2D{self.floor} ++ self.figures() ++ self.wall.values) |s| {
            if (s) |t| rl.unloadTexture(t);
        }
    }

    pub fn body(self: Sprites, k: actor.Kind) ?rl.Texture2D {
        return self.bodies.get(k);
    }

    pub fn figures(self: Sprites) [FIGURES]?rl.Texture2D {
        return self.bodies.values ++ [_]?rl.Texture2D{self.barrel};
    }

    pub fn tileAt(self: Sprites, lv: *const grid.Level, p: mathx.P) ?rl.Texture2D {
        return switch (lv.at(p)) {
            .wall => self.wall.get(lv.wallShape(p) orelse return null),
            .floor => self.floor,
        };
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
});

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
    .solid = null,
});

/// raylib's `imageFromImage` copies without clamping, so a cell off the sheet would read past it.
fn wallCell(sheet: rl.Image, c: WallCell) ?rl.Image {
    if ((c.col + 1) * SPRITE_PX > sheet.width or (c.row + 1) * SPRITE_PX > sheet.height) return null;
    const px: f32 = @floatFromInt(SPRITE_PX);
    return rl.imageFromImage(sheet, .{
        .x = @as(f32, @floatFromInt(c.col)) * px,
        .y = @as(f32, @floatFromInt(c.row)) * px,
        .width = px,
        .height = px,
    });
}

fn whole(t: rl.Texture2D) rl.Rectangle {
    return .{ .x = 0, .y = 0, .width = @floatFromInt(t.width), .height = @floatFromInt(t.height) };
}

/// All of `t` over `dest`.
pub fn stretch(t: rl.Texture2D, dest: rl.Rectangle, tint: rl.Color) void {
    rl.drawTexturePro(t, whole(t), dest, .{ .x = 0, .y = 0 }, 0, tint);
}

/// Stretched over the whole floor, its top-left corner at `ox, oy`.
pub fn overFloor(t: rl.Texture2D, ox: i32, oy: i32, cell: i32) void {
    const dest = rl.Rectangle{
        .x = @floatFromInt(ox),
        .y = @floatFromInt(oy),
        .width = @floatFromInt(grid.W * cell),
        .height = @floatFromInt(grid.H * cell),
    };
    stretch(t, dest, rl.Color.white);
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
pub fn canvas(w: i32, h: i32, c: rl.Color) ?rl.Texture2D {
    const img = rl.genImageColor(w, h, c);
    defer rl.unloadImage(img);
    return clamped(img, .bilinear);
}

/// White, its alpha `alphaAt(dx, dy)` from the middle, 1 at the middle of each edge. Needs a live GL context.
pub fn radial(comptime px: i32, comptime alphaAt: fn (f32, f32) f32) ?rl.Texture2D {
    const n: usize = @intCast(px);
    var img: [n * n]rl.Color = undefined;
    const half: f32 = @as(f32, @floatFromInt(px)) * 0.5;
    for (0..n) |y| {
        for (0..n) |x| {
            const dx = (@as(f32, @floatFromInt(x)) + 0.5 - half) / half;
            const dy = (@as(f32, @floatFromInt(y)) + 0.5 - half) / half;
            img[y * n + x] = .{ .r = 255, .g = 255, .b = 255, .a = @intFromFloat(alphaAt(dx, dy) * 255) };
        }
    }
    return clamped(rgba(&img, px, px), .bilinear);
}

/// Null when it does not compile: raylib then hands back its default shader rather than an error.
pub fn shader(fs: [:0]const u8) ?rl.Shader {
    const s = rl.loadShaderFromMemory(null, fs) catch return null;
    return if (s.id == rl.gl.rlGetShaderIdDefault()) null else s;
}

/// Every field but `shader` is the location of the GLSL uniform it is named for.
pub fn uniforms(comptime T: type, s: rl.Shader) T {
    var u: T = undefined;
    u.shader = s;
    inline for (std.meta.fields(T)) |f| {
        if (comptime std.mem.eql(u8, f.name, "shader")) continue;
        @field(u, f.name) = rl.getShaderLocation(s, f.name);
    }
    return u;
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
pub const FLOOR_BG = rgb(0x121116);
/// Unlit rock, where a wall has no texture.
pub const ROCK = rgb(0x1e1c24);
/// The editor's ground of a procgen node, whose floor is only rolled in play.
pub const UNROLLED = rgb(0x1b2330);
pub const TEXT = rgb(0xd8cdb4);
pub const DIM = rgb(0x8c8672);
pub const LIFE = rgb(0x9c2f2a);
pub const LIFE_BG = fade(LIFE, 0.25);
pub const EDGE = rgb(0x4a4438);
pub const ARROW = rgb(0xe6dcb4);
pub const VEIL = fade(BG, 0.72);

/// At full light: the light map dims it.
pub fn tile(t: grid.Tile) Look {
    return switch (t) {
        .wall => .{ .ch = '#', .fg = rgb(0x9a8e78) },
        .floor => .{ .ch = '.', .fg = rgb(0x5e5a50) },
    };
}

pub const TORCH = Look{ .ch = 'i', .fg = rgb(0xffc46a) };
pub const TORCH_DIM = rgb(0x4a4238);
pub const BARREL = Look{ .ch = '0', .fg = rgb(0x8a5a32) };
pub const DOOR = Look{ .ch = '+', .fg = rgb(0xb89a5a) };
pub const COIN = GOLD;

pub fn body(k: actor.Kind) Look {
    return switch (k) {
        .archer => .{ .ch = '@', .fg = rgb(0x7cc86e) },
        .rat => .{ .ch = 'r', .fg = rgb(0xb07a4e) },
        .slime, .slime_half, .slime_quarter => .{ .ch = 's', .fg = rgb(0x6fae5a) },
        .bloat => .{ .ch = 'b', .fg = GAS },
    };
}

/// Brogue's `poisonGasColor`, the bloat's and its gas's.
pub const GAS = rgb(0xbf40d9);

/// What a blow sprays: `fx.matterOf`'s.
pub const BLOOD = rl.Color{ .r = 112, .g = 22, .b = 16, .a = 220 };
pub const OOZE = rl.Color{ .r = 70, .g = 120, .b = 72, .a = 220 };
pub const SPLINTER = rl.Color{ .r = 120, .g = 82, .b = 46, .a = 230 };
/// Brogue's purple blood: the gas's, darker.
pub const ICHOR = rl.Color{ .r = GAS.r / 2, .g = GAS.g / 2, .b = GAS.b / 2, .a = BLOOD.a };
/// The pinprick where a blow lands.
pub const CONTACT = rl.Color{ .r = 255, .g = 244, .b = 214, .a = 180 };

pub const Gait = enum { hop, slide };

pub fn gait(k: actor.Kind) Gait {
    return switch (k) {
        .archer, .rat => .hop,
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
    return switch (t) {
        .wall => if (lit) rgb(0x8a7f6a) else rgb(0x46434c),
        .floor => if (lit) rgb(0x3a3830) else rgb(0x1c1c22),
    };
}

pub const AIM_REACH = fade(GOLD, 0.10);
pub const AIM_PATH = fade(GOLD, 0.28);
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

pub fn skill(a: skillbar.Act) Look {
    return switch (a) {
        .shoot => .{ .ch = '}', .fg = ARROW },
        .wait => .{ .ch = 'z', .fg = DIM },
        .secondary => .{ .ch = '2', .fg = GOLD },
    };
}

const PANEL = rgb(0x0e0d12);
const RAISED = rgb(0x1a1820);

pub const SLOT_BG = RAISED;
pub const SLOT_EMPTY = PANEL;
pub const SLOT_HELD = GOLD;
pub const SLOT_CURSOR = RETICLE;
pub const SLOT_CLEAR = FOE;
pub const CLEAR = Look{ .ch = 'x', .fg = SLOT_CLEAR };

pub const MINI_BG = fade(BG, 0.9);
pub const MINI_HERO = rgb(0x9cf08a);
pub const MINI_FOE = FOE;
pub const MINI_VIEW = fade(GOLD, 0.7);

pub const EDIT_PANEL = PANEL;
pub const EDIT_ROW_ON = RAISED;
pub const EDIT_ON = GOLD;
pub const EDIT_PICKED = RETICLE;
pub const EDIT_WARN = FOE;

test "every glyph is printable ascii" {
    const inked = struct {
        fn f(c: u8) bool {
            return std.ascii.isPrint(c) and c != ' ';
        }
    }.f;
    for (std.enums.values(grid.Tile)) |t| try std.testing.expect(inked(tile(t).ch));
    for (std.enums.values(actor.Kind)) |k| try std.testing.expect(inked(body(k).ch));
    try std.testing.expect(inked(TORCH.ch));
    try std.testing.expect(inked(BARREL.ch));
    try std.testing.expect(inked(DOOR.ch));
    try std.testing.expect(inked(CLEAR.ch));
    for (skillbar.ACTS) |a| try std.testing.expect(inked(skill(a).ch));
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
