const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const font = @import("../gfx/font.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const shaders = @import("../gfx/shaders.zig");
const hud = @import("hud.zig");

pub const Kind = @import("../play/log.zig").Kind;
pub const Log = @import("../play/log.zig").Log;

fn ink(k: Kind) rl.Color {
    return switch (k) {
        .event => look.TEXT,
        .damage => look.rgb(0xf0ba87),
        .danger => look.rgb(0xf08080),
        .recovery => look.rgb(0x8bcf9d),
        .loot => look.UI_FOCUS,
        .progress => look.rgb(0xc6a0ed),
        .status => look.WARD,
    };
}

const MARGIN: i32 = hud.EDGE;
const BOX_H: i32 = 270;
const MIN_W: i32 = 160;
const MAX_W: i32 = 440;
/// Kept clear between the box and the hud's assembly.
const HUD_GAP: i32 = 24;
const ROWS_Y: i32 = 10;
/// Rows clip this far above the box's foot; the last row's leading falls inside it.
const CLIP_BOTTOM: i32 = 12;
const ROWS_BOTTOM: i32 = BOX_H - CLIP_BOTTOM - font.LEADING;
const CLIP_X: i32 = 10;
const TEXT_X: i32 = 14;
const LINE_H = font.SMALL_LINE;
const ENTRY_GAP: i32 = 4;
const TOP_OPACITY: f32 = 0.1;
const BG_A: u8 = 210;
const BG = blk: {
    var c = hud.PLATE;
    c.a = BG_A;
    break :blk c;
};

pub fn box(screen: mathx.P) rl.Rectangle {
    const beside = hud.leftOf(screen) - HUD_GAP;
    const width = @max(MIN_W, @min(MAX_W, beside));
    return raster.rect(MARGIN, screen.y - MARGIN - BOX_H, width, BOX_H);
}
pub fn draw(face: *const font.Face, sprites: *const look.Sprites, screen: mathx.P, log: *const Log) void {
    const r = box(screen);
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    if (sprites.log_fade) |fade| {
        rl.beginShaderMode(fade.shader);
        shaders.setUniform(fade.shader, fade.bounds, [2]f32{ @floatFromInt(screen.y - y - BOX_H), @floatFromInt(screen.y - y) });
        shaders.setUniform(fade.shader, fade.minimum, TOP_OPACITY);
        look.hudPanelIn(sprites, r, BG, look.LIT);
    } else {
        rl.drawRectangleGradientV(x, y, w, BOX_H, look.fade(BG, TOP_OPACITY), BG);
    }
    defer if (sprites.log_fade != null) rl.endShaderMode();
    var bottom = y + ROWS_BOTTOM;
    var back = log.held + log.scroll;
    rl.beginScissorMode(x + CLIP_X, y + ROWS_Y, w - 2 * CLIP_X, BOX_H - ROWS_Y - CLIP_BOTTOM);
    defer rl.endScissorMode();
    var buf: font.Wrapped = undefined;
    var rows: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
    while (back < log.n and bottom > y + ROWS_Y) : (back += 1) {
        const count = font.wrap(face, log.line(back).?, font.SMALL, w - 2 * TEXT_X, &buf, &rows);
        bottom -= @as(i32, @intCast(count)) * LINE_H;
        const at = log.index(back);
        const color = ink(log.kinds[at]);
        for (rows[0..count], 0..) |text, i| {
            const row = bottom + @as(i32, @intCast(i)) * LINE_H;
            const alpha = mathx.lerpF(TOP_OPACITY, 1, std.math.clamp(@as(f32, @floatFromInt(row - y)) / BOX_H, 0, 1));
            face.draw(text, x + TEXT_X, row, font.SMALL, if (sprites.log_fade != null) color else look.fade(color, alpha));
        }
        bottom -= ENTRY_GAP;
    }
}
