const std = @import("std");
const mathx = @import("../core/mathx.zig");
const items = @import("../play/items.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const PAGES = @import("character_view.zig").PAGES;
const P = mathx.P;

pub const WIDTH = 1100;
pub const HEIGHT = 640;
pub const SIZE = P{ .x = WIDTH, .y = HEIGHT };
pub const CONTENT_TOP = 132;
pub const DETAIL_X = 568;
pub const DIVIDER_X = DETAIL_X - 18;
pub const ROW_HEIGHT = 28;
pub const VISIBLE_ROWS = 14;
pub const DIRECT_VISIBLE_ROWS = 8;
/// A list's rows, then its glyph's middle, text and second column within a row.
pub const LIST_X = menu.PANEL_PAD;
pub const LIST_Y = 30;
pub const LIST_W = 510;
pub const GLYPH_X = 20;
pub const TEXT_X = 40;
pub const SECOND_X = 336;
/// Between a row's text, cut short, and its second column.
pub const COLUMN_GAP = 12;
/// Down from a list's header to "Empty" when it has no rows.
pub const EMPTY_DY = 46;
/// The area under the tabs a page lays out in.
pub const AREA = raster.rect(LIST_X, CONTENT_TOP, WIDTH - 2 * LIST_X, AREA_H);
pub const AREA_H = 458;
pub const CARD_W = 246;
pub const CARD_GAP = 16;
pub const CARD_H = 334;
/// Two cards side by side; one card alone or a note under them spans it.
pub const DETAIL_W = CARD_W * 2 + CARD_GAP;
pub const CLOSE_W = 108;
pub const CLOSE_H = 32;
pub const CLOSE_Y = 18;
/// The header row's middle: name, level and the close button.
pub const HEADER_MID = CLOSE_Y + CLOSE_H / 2;
/// Footer text's top, and where the divider stops.
pub const FOOT_Y = HEIGHT - 32;
pub const DIVIDER_FOOT = HEIGHT - 30;
/// Equipment cells this tall show the full-size glyph with the item's name under it; shorter ones the glyph alone.
pub const NAMED_CELL_H = 96;
/// Up from a held two-hander's name to "Both hands".
pub const PAIR_DY = 22;
pub const TAB_Y = 76;
pub const TAB_W = 184;
pub const TAB_H = 34;
pub const TAB_GAP = 9;
pub const TAB_MID = TAB_Y + TAB_H / 2;
pub const OFF_TAB_A: f32 = 0.7;
pub const TABS_X: i32 = @divExact(WIDTH - @as(i32, PAGES.len) * TAB_W - (@as(i32, PAGES.len) - 1) * TAB_GAP, 2);
/// Room each side of the tabs for the shoulder buttons' icons.
pub const SHOULDER_W = 40;
comptime {
    std.debug.assert(LIST_X + SHOULDER_W < TABS_X);
}
pub const ACTION_W = menu.ACTION_BOX.x;
pub const ACTION_H = menu.ACTION_BOX.y;
pub const ACTION_Y = HEIGHT - 82;
/// Nearby: header, list, a note line and the actions, only as tall as its list.
pub const DIRECT_W = 2 * LIST_X + LIST_W;
pub const DIRECT_GAP = 14;
/// Under the header, loot's inventory and gold line.
pub const HOLDING_Y = CLOSE_Y + CLOSE_H + 4;
/// Loot: list left, the chosen item's card right, fixed at the tallest card whatever is listed.
pub const LOOT_TOP = HOLDING_Y + font.SMALL + DIRECT_GAP;
pub const LOOT_ROWS = CARD_H / ROW_HEIGHT;
pub const LOOT_FOOT_Y = LOOT_TOP + CARD_H + DIRECT_GAP;
pub const LOOT_SIZE = P{ .x = WIDTH, .y = LOOT_FOOT_Y + ACTION_H + menu.PANEL_PAD };
pub const REQUIREMENT_GAP = 10;
/// Under "Both hands in use", its explanation's top.
pub const HELD_NOTE_DY = 42;
pub const LOSS = look.rgb(0xe18c83);
/// The most cells any page lays out by box.
pub const CELLS_MAX = @max(skillbar.ACTS.len, items.SLOTS.len);
pub const SLOT_BOX = std.EnumArray(items.Slot, struct { at: P, w: i32, h: i32 }).init(.{
    .right_hand = .{ .at = .{ .x = 65, .y = 128 }, .w = 96, .h = 180 },
    .left_hand = .{ .at = .{ .x = 413, .y = 128 }, .w = 96, .h = 180 },
    .helm = .{ .at = .{ .x = 239, .y = 62 }, .w = 96, .h = 96 },
    .chest = .{ .at = .{ .x = 239, .y = 170 }, .w = 96, .h = 138 },
    .amulet = .{ .at = .{ .x = 347, .y = 104 }, .w = 54, .h = 54 },
    .gloves = .{ .at = .{ .x = 65, .y = 320 }, .w = 96, .h = 96 },
    .right_ring = .{ .at = .{ .x = 173, .y = 320 }, .w = 54, .h = 54 },
    .belt = .{ .at = .{ .x = 239, .y = 320 }, .w = 96, .h = 54 },
    .left_ring = .{ .at = .{ .x = 347, .y = 320 }, .w = 54, .h = 54 },
    .boots = .{ .at = .{ .x = 413, .y = 320 }, .w = 96, .h = 96 },
    .life_flask = .{ .at = .{ .x = 173, .y = 386 }, .w = 108, .h = 54 },
    .mana_flask = .{ .at = .{ .x = 293, .y = 386 }, .w = 108, .h = 54 },
});
pub const SLOT_LABEL = font.SMALL;
pub const SLOT_INSET = 4;
