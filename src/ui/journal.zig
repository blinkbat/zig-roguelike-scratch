const sprite = @import("../gfx/sprites.zig");
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
const BOX_H: i32 = 360;
const MIN_W: i32 = 120;
const MAX_W: i32 = 330;
const HUD_GAP: i32 = 24;
const PAD: i32 = 14;
const ROWS_BOTTOM: i32 = BOX_H - PAD + font.LEADING;
const LINE_H = font.SMALL_LINE;
const ENTRY_GAP: i32 = 4;
const TOP_OPACITY: f32 = 0.1;

pub fn box(screen: mathx.P) rl.Rectangle {
    const beside = hud.leftOf(screen) - HUD_GAP;
    const width = @max(MIN_W, @min(MAX_W, beside));
    return raster.rect(MARGIN, screen.y - MARGIN - BOX_H, width, BOX_H);
}
pub fn draw(face: *const font.Face, sprites: *const sprite.Sprites, screen: mathx.P, log: *const Log) void {
    const r = box(screen);
    const x = raster.left(r);
    const y = raster.top(r);
    const w = raster.width(r);
    if (sprites.log_fade) |fade| {
        rl.beginShaderMode(fade.shader);
        shaders.setUniform(fade.shader, fade.bounds, [2]f32{ @floatFromInt(screen.y - y - BOX_H), @floatFromInt(screen.y - y) });
        shaders.setUniform(fade.shader, fade.minimum, TOP_OPACITY);
        sprite.backingIn(sprites, r);
    } else {
        rl.drawRectangleGradientV(x, y, w, BOX_H, look.fade(look.BACKING, TOP_OPACITY), look.BACKING);
    }
    defer if (sprites.log_fade != null) rl.endShaderMode();
    var bottom = y + ROWS_BOTTOM;
    var back = log.held + log.scroll;
    rl.beginScissorMode(x + PAD, y + PAD, w - 2 * PAD, BOX_H - 2 * PAD);
    defer rl.endScissorMode();
    var buf: font.Wrapped = undefined;
    var rows: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
    while (back < log.n and bottom > y + PAD) : (back += 1) {
        const count = font.wrap(face, log.line(back).?, font.SMALL, w - 2 * PAD, &buf, &rows);
        bottom -= @as(i32, @intCast(count)) * LINE_H;
        const at = log.index(back);
        const color = ink(log.kinds[at]);
        for (rows[0..count], 0..) |text, i| {
            const row = bottom + @as(i32, @intCast(i)) * LINE_H;
            if (row < y + PAD) continue;
            const alpha = mathx.lerpF(TOP_OPACITY, 1, std.math.clamp(@as(f32, @floatFromInt(row - y)) / BOX_H, 0, 1));
            face.draw(text, x + PAD, row, font.SMALL, if (sprites.log_fade != null) color else look.fade(color, alpha));
        }
        bottom -= ENTRY_GAP;
    }
}
