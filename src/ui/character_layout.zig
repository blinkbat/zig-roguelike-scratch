const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const item_bases = @import("../play/item_bases.zig");
const skillbar = @import("../play/skillbar.zig");
const raster = @import("../gfx/raster.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const PAGES = @import("character_view.zig").PAGES;
const P = mathx.P;

pub const WIDTH = 1100;
const HEIGHT = 640;
pub const SIZE = P{ .x = WIDTH, .y = HEIGHT };
pub const CONTENT_TOP = 132;
pub const DETAIL_X = 568;
pub const DIVIDER_X = DETAIL_X - 18;
pub const ROW_HEIGHT = 28;
pub const VISIBLE_ROWS = 14;
pub const DIRECT_VISIBLE_ROWS = 8;
pub const LIST_X = menu.PANEL_PAD;
pub const LIST_Y = 30;
pub const LIST_W = 510;
pub const GLYPH_X = 20;
pub const TEXT_X = 40;
pub const SECOND_X = 336;
pub const COLUMN_GAP = 12;
pub const EMPTY_DY = 46;
pub const AREA = raster.rect(LIST_X, CONTENT_TOP, WIDTH - 2 * LIST_X, AREA_H);
const AREA_H = 458;
pub const CARD_W = 246;
pub const CARD_GAP = 16;
pub const CARD_H = 334;
pub const DETAIL_W = CARD_W * 2 + CARD_GAP;
pub const CLOSE_W = 108;
pub const CLOSE_H = 32;
pub const CLOSE_Y = 18;
pub const HEADER_MID = CLOSE_Y + CLOSE_H / 2;
pub const FOOT_Y = HEIGHT - 32;
pub const DIVIDER_FOOT = HEIGHT - 30;
pub const NAMED_CELL_H = 96;
pub const PAIR_DY = 22;
const TAB_Y = 78;
const TAB_W = 148;
const TAB_H = 30;
const TAB_GAP = 8;
pub const TAB_TEXT = font.SMALL;
pub const OFF_TAB_A: f32 = 0.7;
const TABS_X: i32 = @divExact(WIDTH - @as(i32, PAGES.len) * TAB_W - (@as(i32, PAGES.len) - 1) * TAB_GAP, 2);
const SHOULDER_W = 40;
comptime {
    std.debug.assert(LIST_X + SHOULDER_W < TABS_X);
}

pub const TAB_PAD = 8;

pub fn tabBox(i: usize) rl.Rectangle {
    return raster.rect(TABS_X + @as(i32, @intCast(i)) * (TAB_W + TAB_GAP), TAB_Y, TAB_W, TAB_H);
}

pub fn shoulderBox(next: bool) rl.Rectangle {
    const x: i32 = if (next) WIDTH - LIST_X - SHOULDER_W else LIST_X;
    return raster.rect(x, TAB_Y, SHOULDER_W, TAB_H);
}

pub const ACTION_W = menu.ACTION_BOX.x;
pub const ACTION_H = menu.ACTION_BOX.y;
pub const ACTION_Y = HEIGHT - 82;
pub const DIRECT_W = 2 * LIST_X + LIST_W;
pub const DIRECT_GAP = 14;
pub const HOLDING_Y = CLOSE_Y + CLOSE_H + 4;
pub const LOOT_TOP = HOLDING_Y + font.SMALL + DIRECT_GAP;
pub const LOOT_ROWS = CARD_H / ROW_HEIGHT;
pub const LOOT_FOOT_Y = LOOT_TOP + CARD_H + DIRECT_GAP;
pub const LOOT_SIZE = P{ .x = WIDTH, .y = LOOT_FOOT_Y + ACTION_H + menu.PANEL_PAD };
pub const REQUIREMENT_GAP = 10;
pub const HELD_NOTE_DY = 42;
pub const CELLS_MAX = @max(skillbar.ACTS.len, item_bases.SLOTS.len);
const SLOT_BIG = 96;
const SLOT_SMALL = 54;
const SLOT_GUTTER = 12;
const SLOT_LEFT = 65;
const SLOT_TOP = 62;
const HANDS_Y = 128;
const LOW_Y = 320;
const SLOT_COLS = [_]i32{ SLOT_BIG, SLOT_SMALL, SLOT_BIG, SLOT_SMALL, SLOT_BIG };
const SLOT_X = blk: {
    var xs: [SLOT_COLS.len]i32 = undefined;
    var x: i32 = SLOT_LEFT;
    for (&xs, SLOT_COLS) |*at, w| {
        at.* = x;
        x += w + SLOT_GUTTER;
    }
    break :blk xs;
};
const CHEST_Y = SLOT_TOP + SLOT_BIG + SLOT_GUTTER;
const FLASK_Y = LOW_Y + SLOT_SMALL + SLOT_GUTTER;
const FLASK_W = @divExact(SLOT_X[3] + SLOT_SMALL - SLOT_X[1] - SLOT_GUTTER, 2);
pub const SLOT_BOX = std.EnumArray(item_bases.Slot, struct { at: P, w: i32, h: i32 }).init(.{
    .right_hand = .{ .at = .{ .x = SLOT_X[0], .y = HANDS_Y }, .w = SLOT_BIG, .h = LOW_Y - SLOT_GUTTER - HANDS_Y },
    .left_hand = .{ .at = .{ .x = SLOT_X[4], .y = HANDS_Y }, .w = SLOT_BIG, .h = LOW_Y - SLOT_GUTTER - HANDS_Y },
    .helm = .{ .at = .{ .x = SLOT_X[2], .y = SLOT_TOP }, .w = SLOT_BIG, .h = SLOT_BIG },
    .chest = .{ .at = .{ .x = SLOT_X[2], .y = CHEST_Y }, .w = SLOT_BIG, .h = LOW_Y - SLOT_GUTTER - CHEST_Y },
    .amulet = .{ .at = .{ .x = SLOT_X[3], .y = SLOT_TOP + SLOT_BIG - SLOT_SMALL }, .w = SLOT_SMALL, .h = SLOT_SMALL },
    .gloves = .{ .at = .{ .x = SLOT_X[0], .y = LOW_Y }, .w = SLOT_BIG, .h = SLOT_BIG },
    .right_ring = .{ .at = .{ .x = SLOT_X[1], .y = LOW_Y }, .w = SLOT_SMALL, .h = SLOT_SMALL },
    .belt = .{ .at = .{ .x = SLOT_X[2], .y = LOW_Y }, .w = SLOT_BIG, .h = SLOT_SMALL },
    .left_ring = .{ .at = .{ .x = SLOT_X[3], .y = LOW_Y }, .w = SLOT_SMALL, .h = SLOT_SMALL },
    .boots = .{ .at = .{ .x = SLOT_X[4], .y = LOW_Y }, .w = SLOT_BIG, .h = SLOT_BIG },
    .life_flask = .{ .at = .{ .x = SLOT_X[1], .y = FLASK_Y }, .w = FLASK_W, .h = SLOT_SMALL },
    .mana_flask = .{ .at = .{ .x = SLOT_X[1] + FLASK_W + SLOT_GUTTER, .y = FLASK_Y }, .w = FLASK_W, .h = SLOT_SMALL },
});
pub const SLOT_LABEL = font.SMALL;
pub const SLOT_INSET = 4;
