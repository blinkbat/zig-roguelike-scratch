const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const hero = @import("../play/hero.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");

const P = mathx.P;
pub const Page = enum { equipment, inventory, stats, passives };
const PAGES = std.enums.values(Page);
const Slot = enum { head, body, weapon, offhand, feet, ring };
const SLOTS = std.enums.values(Slot);
const BAG_COLS: usize = 5;
const BAG_CELLS: usize = 20;
const CELL: i32 = 72;
const GAP: i32 = 12;
const PAD: i32 = 24;
const BODY_Y: i32 = 116;
const BODY_H: i32 = 420;
const CARD_W: i32 = 960;
const CARD_H: i32 = 600;
const DETAIL_X: i32 = 536;
const TAB_STEP: i32 = @divTrunc(CARD_W - 2 * PAD, PAGES.len);
const SLOT_AT = std.EnumArray(Slot, P).init(.{
    .head = .{ .x = 100, .y = 38 },
    .body = .{ .x = 340, .y = 38 },
    .weapon = .{ .x = 100, .y = 166 },
    .offhand = .{ .x = 340, .y = 166 },
    .feet = .{ .x = 100, .y = 294 },
    .ring = .{ .x = 340, .y = 294 },
});

pub const View = struct { class: hero.Class, name: []const u8, life: i32, mana: i32 };

pub const Book = struct {
    page: Page = .equipment,
    tabs: bool = true,
    cursor: usize = 0,

    pub fn open(self: *Book) void {
        self.tabs = true;
    }

    fn choose(self: *Book, page: Page) void {
        self.page = page;
        self.cursor = 0;
        self.tabs = true;
    }

    fn count(self: *const Book) usize {
        return switch (self.page) {
            .equipment => SLOTS.len,
            .inventory => BAG_CELLS,
            .stats, .passives => 0,
        };
    }

    fn activate(self: *Book) void {
        if (self.page == .equipment) {
            self.page = .inventory;
            self.cursor = 0;
        }
    }

    pub fn step(self: *Book, st: *const input.State, screen: P) bool {
        if (menu.backed(st)) return true;
        const origin = originOf(screen);
        if (st.click) {
            const pointer = st.pointer orelse return false;
            if (contains(closeBox(origin), pointer)) return true;
            for (PAGES, 0..) |page, i| {
                if (contains(tabBox(origin, i), pointer)) {
                    self.choose(page);
                    return false;
                }
            }
            if (self.page == .equipment and !self.tabs and contains(actionBox(origin), pointer)) {
                self.activate();
                return false;
            }
            for (0..self.count()) |i| {
                if (contains(self.cellBox(origin, i), pointer)) {
                    self.cursor = i;
                    self.tabs = false;
                    return false;
                }
            }
        }
        if (st.walk) |dir| {
            const d = dir.delta();
            if (self.tabs) {
                if (d.x != 0) self.choose(PAGES[mathx.wrap(@intFromEnum(self.page), d.x, PAGES.len)]);
                if (d.y > 0 and self.count() > 0) self.tabs = false;
            } else {
                const from = self.cellBox(origin, self.cursor);
                var best: ?usize = null;
                var score = std.math.floatMax(f32);
                for (0..self.count()) |i| {
                    const cost = menu.directionScore(from, self.cellBox(origin, i), dir, 3) orelse continue;
                    if (cost < score) {
                        best = i;
                        score = cost;
                    }
                }
                if (best) |i| self.cursor = i else if (d.y < 0) {
                    self.tabs = true;
                }
            }
        }
        if (st.hit(menu.CONFIRM)) {
            if (self.tabs) {
                if (self.count() > 0) self.tabs = false;
            } else self.activate();
        }
        return false;
    }

    fn cellBox(self: *const Book, origin: P, i: usize) rl.Rectangle {
        const p = origin.add(.{ .x = PAD, .y = BODY_Y });
        return switch (self.page) {
            .equipment => blk: {
                const at = p.add(SLOT_AT.get(SLOTS[i]));
                break :blk look.rect(at.x - CELL / 2, at.y, CELL, CELL);
            },
            .inventory => look.rect(p.x + 28 + @as(i32, @intCast(i % BAG_COLS)) * (CELL + GAP), p.y + 30 + @as(i32, @intCast(i / BAG_COLS)) * (CELL + GAP), CELL, CELL),
            .stats, .passives => unreachable,
        };
    }

    pub fn draw(self: *const Book, face: *const font.Face, sprites: *const look.Sprites, screen: P, v: View) void {
        const o = originOf(screen);
        look.hudPanel(sprites, o.x, o.y, CARD_W, CARD_H, look.EDIT_PANEL, look.LIT);
        face.draw("CHARACTER", o.x + PAD, o.y + PAD, 24, look.TEXT);
        label(face, closeBox(o), "Close", false);
        for (PAGES, 0..) |page, i| {
            const r = tabBox(o, i);
            if (page == self.page) rl.drawRectangleRec(r, look.EDIT_ROW_ON);
            label(face, r, pageName(page), page == self.page and self.tabs);
        }
        const x = o.x + PAD;
        const y = o.y + BODY_Y;
        if (self.page == .stats) {
            drawStats(face, o, v);
            return;
        }
        if (self.page == .passives) {
            const area = look.rect(x, y, CARD_W - PAD * 2, BODY_H);
            rl.drawRectangleRec(area, look.BG);
            rl.drawRectangleLinesEx(area, 1, look.EDGE);
            face.drawMid("No passives", o.x + CARD_W / 2, y + BODY_H / 2 - 12, 24, look.DIM);
            return;
        }
        if (self.page == .equipment) {
            const cx = x + 220;
            const ink = look.EDIT_ROW_ON;
            rl.drawCircle(cx, y + 90, 24, ink);
            rl.drawRectangle(cx - 28, y + 125, 56, 120, ink);
            rl.drawLineEx(.{ .x = @floatFromInt(cx - 22), .y = @floatFromInt(y + 142) }, .{ .x = @floatFromInt(cx - 60), .y = @floatFromInt(y + 240) }, 14, ink);
            rl.drawLineEx(.{ .x = @floatFromInt(cx + 22), .y = @floatFromInt(y + 142) }, .{ .x = @floatFromInt(cx + 60), .y = @floatFromInt(y + 240) }, 14, ink);
            rl.drawRectangle(cx - 28, y + 245, 22, 105, ink);
            rl.drawRectangle(cx + 6, y + 245, 22, 105, ink);
        }
        for (0..self.count()) |i| {
            const r = self.cellBox(o, i);
            const chosen = !self.tabs and self.cursor == i;
            look.hudPanel(sprites, @intFromFloat(r.x), @intFromFloat(r.y), CELL, CELL, look.BG, look.LIT);
            if (chosen) rl.drawRectangleLinesEx(look.grown(r, -4), 2, look.RETICLE);
            if (self.page == .equipment) face.drawMid(slotName(SLOTS[i]), @intFromFloat(r.x + r.width / 2), @as(i32, @intFromFloat(r.y)) - 23, font.SMALL, look.DIM);
        }
        const dx = o.x + DETAIL_X;
        face.draw(v.class.title(), dx, y + 8, 24, look.TEXT);
        var name: [hero.Name.MAX + 1]u8 = undefined;
        face.draw(std.fmt.bufPrintZ(&name, "{s}", .{v.name}) catch "", dx, y + 42, font.BODY, look.DIM);
        face.draw(if (self.page == .equipment) "No equipment" else "Inventory empty", dx, y + 104, 24, look.DIM);
        if (self.page == .equipment and !self.tabs) {
            face.draw(slotName(SLOTS[self.cursor]), dx, y + 146, font.BODY, look.DIM);
            label(face, actionBox(o), "Browse inventory", true);
        }
    }

    fn drawStats(face: *const font.Face, o: P, v: View) void {
        const x = o.x + PAD + 32;
        const y = o.y + BODY_Y + 20;
        face.draw("Stats", x, y, 24, look.TEXT);
        const names = [_][:0]const u8{ "Maximum life", "Maximum mana" };
        const values = [_]i32{ v.life, v.mana };
        for (names, values, 0..) |name, value, i| {
            var buf: [32]u8 = undefined;
            const at = y + 64 + @as(i32, @intCast(i)) * 56;
            face.draw(name, x, at, font.BODY, look.DIM);
            face.draw(std.fmt.bufPrintZ(&buf, "{d}", .{value}) catch "", x + 300, at, 24, look.TEXT);
        }
        const dx = o.x + DETAIL_X;
        face.draw(v.class.title(), dx, y, 24, look.TEXT);
        var name: [hero.Name.MAX + 1]u8 = undefined;
        face.draw(std.fmt.bufPrintZ(&name, "{s}", .{v.name}) catch "", dx, y + 34, font.BODY, look.DIM);
    }
};

fn originOf(screen: P) P {
    return .{ .x = @divTrunc(screen.x - CARD_W, 2), .y = @divTrunc(screen.y - CARD_H, 2) };
}
fn tabBox(o: P, i: usize) rl.Rectangle {
    return look.rect(o.x + PAD + @as(i32, @intCast(i)) * TAB_STEP, o.y + 68, TAB_STEP - GAP, 34);
}
fn closeBox(o: P) rl.Rectangle {
    return look.rect(o.x + CARD_W - 116, o.y + 18, 92, 34);
}
fn actionBox(o: P) rl.Rectangle {
    return look.rect(o.x + DETAIL_X, o.y + BODY_Y + BODY_H - 56, CARD_W - DETAIL_X - PAD, 40);
}
fn centre(r: rl.Rectangle) P {
    return .{ .x = @intFromFloat(r.x + r.width / 2), .y = @intFromFloat(r.y + r.height / 2) };
}
fn vec(p: P) rl.Vector2 {
    return .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
}
fn contains(r: rl.Rectangle, p: P) bool {
    return rl.checkCollisionPointRec(vec(p), r);
}
fn label(face: *const font.Face, r: rl.Rectangle, text: [:0]const u8, selected: bool) void {
    rl.drawRectangleLinesEx(r, 1, if (selected) look.RETICLE else look.EDGE);
    face.drawMid(text, @intFromFloat(r.x + r.width / 2), @as(i32, @intFromFloat(r.y)) + 7, font.BODY, if (selected) look.TEXT else look.DIM);
}
fn pageName(page: Page) [:0]const u8 {
    return switch (page) {
        inline else => |p| comptime menu.named(p),
    };
}
fn slotName(slot: Slot) [:0]const u8 {
    return switch (slot) {
        inline else => |s| comptime menu.named(s),
    };
}

test "character screens support tabs and empty slots through mouse and menu navigation" {
    var book = Book{};
    book.open();
    const screen = P{ .x = 1280, .y = 720 };
    const o = originOf(screen);
    _ = book.step(&.{ .walk = .e }, screen);
    try std.testing.expectEqual(Page.inventory, book.page);
    _ = book.step(&.{ .walk = .s }, screen);
    try std.testing.expect(!book.tabs);
    _ = book.step(&.{ .walk = .e }, screen);
    try std.testing.expectEqual(@as(usize, 1), book.cursor);
    _ = book.step(&.{ .click = true, .pointer = centre(tabBox(o, 3)) }, screen);
    try std.testing.expectEqual(Page.passives, book.page);
    _ = book.step(&.{ .walk = .s }, screen);
    try std.testing.expect(book.tabs);
    _ = book.step(&.{ .click = true, .pointer = centre(tabBox(o, 0)) }, screen);
    _ = book.step(&.{ .click = true, .pointer = centre(book.cellBox(o, 1)) }, screen);
    _ = book.step(&.{ .click = true, .pointer = centre(actionBox(o)) }, screen);
    try std.testing.expectEqual(Page.inventory, book.page);
    _ = book.step(&.{ .walk = .n }, screen);
    try std.testing.expect(book.tabs);
    try std.testing.expect(book.step(&.{ .click = true, .pointer = centre(closeBox(o)) }, screen));
    std.debug.print("character navigation: tabs, empty slots, blank passives, inventory shortcut and close checked\n", .{});
}
