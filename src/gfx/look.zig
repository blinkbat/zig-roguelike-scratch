const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const grid = @import("../world/grid.zig");
const actor = @import("../play/actor.zig");

// EVERY PICTURE IN THE GAME. A thing with a sprite in `Sprites` draws it; anything without one falls back to its glyph.

pub const SPRITE_PX: i32 = 64;

pub const Look = struct {
    ch: u8,
    fg: rl.Color,
};

/// Needs a live GL context, so it is loaded after the window opens and never in a test.
pub const Sprites = struct {
    bodies: std.EnumArray(actor.Kind, ?rl.Texture2D) = .initFill(null),
    floor: ?rl.Texture2D = null,
    wall: std.EnumArray(grid.WallShape, ?rl.Texture2D) = .initFill(null),

    pub fn load() Sprites {
        var s = Sprites{ .floor = texture(@embedFile("floor.png")) };
        for (std.enums.values(actor.Kind)) |k| s.bodies.set(k, texture(BODY_PNGS.get(k) orelse continue));
        const sheet = rl.loadImageFromMemory(".png", @embedFile("walls.png")) catch return s;
        defer rl.unloadImage(sheet);
        for (std.enums.values(grid.WallShape)) |shape| {
            s.wall.set(shape, toTexture(wallCell(sheet, WALL_CELLS.get(shape) orelse continue)));
        }
        return s;
    }

    pub fn unload(self: Sprites) void {
        for ([_]?rl.Texture2D{self.floor} ++ self.bodies.values ++ self.wall.values) |s| {
            if (s) |t| rl.unloadTexture(t);
        }
    }

    pub fn body(self: Sprites, k: actor.Kind) ?rl.Texture2D {
        return self.bodies.get(k);
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
});

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

fn wallCell(sheet: rl.Image, c: WallCell) rl.Image {
    const px: f32 = @floatFromInt(SPRITE_PX);
    return rl.imageFromImage(sheet, .{
        .x = @as(f32, @floatFromInt(c.col)) * px,
        .y = @as(f32, @floatFromInt(c.row)) * px,
        .width = px,
        .height = px,
    });
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
/// The light remembered terrain is drawn under: dark and blue, after Brogue's memory colour.
pub const REMEMBERED = rgb(0x33385c);
pub const FLOOR_BG = rgb(0x121116);
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

/// Drawn over the light map, so the flame is its own light; remembered, it is the dim one.
pub const TORCH = Look{ .ch = 'i', .fg = rgb(0xffc46a) };
pub const TORCH_DIM = rgb(0x4a4238);

pub fn body(k: actor.Kind) Look {
    return switch (k) {
        .archer => .{ .ch = '@', .fg = rgb(0x7cc86e) },
        .rat => .{ .ch = 'r', .fg = rgb(0xb07a4e) },
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

/// The d-pad button a lean-overlay cell answers to.
pub fn caret(d: mathx.Dir) u8 {
    return switch (d) {
        .n => '^',
        .e => '>',
        .s => 'v',
        .w => '<',
        .ne, .se, .sw, .nw => '+',
    };
}

pub const MINI_BG = fade(BG, 0.9);
pub const MINI_HERO = rgb(0x9cf08a);
pub const MINI_FOE = FOE;
pub const MINI_VIEW = fade(GOLD, 0.7);

test "every glyph is printable ascii" {
    for (std.enums.values(grid.Tile)) |t| {
        const c = tile(t).ch;
        try std.testing.expect(c > 32 and c < 127);
    }
    for (std.enums.values(actor.Kind)) |k| {
        const c = body(k).ch;
        try std.testing.expect(c > 32 and c < 127);
    }
    try std.testing.expect(TORCH.ch > 32 and TORCH.ch < 127);
}

test "an arrow's glyph follows its slope" {
    try std.testing.expectEqual(@as(u8, '-'), arrow(5, 0));
    try std.testing.expectEqual(@as(u8, '|'), arrow(0, -3));
    try std.testing.expectEqual(@as(u8, '\\'), arrow(3, 3));
    try std.testing.expectEqual(@as(u8, '/'), arrow(3, -3));
    try std.testing.expectEqual(@as(u8, '-'), arrow(7, 1));
}
