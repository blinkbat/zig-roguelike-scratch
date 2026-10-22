const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const hero = @import("../play/hero.zig");
const attr = @import("../play/attrs.zig");
const items = @import("../play/items.zig");
const damage = @import("../play/damage.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const trees = @import("trees.zig");
const P = mathx.P;
pub const Page = enum {
    equipment,
    inventory,
    stats,
    passives,
    skills,
    nearby,
    loot,

    pub fn of(key_page: input.CharacterPage) Page {
        return switch (key_page) {
            inline else => |page| @field(Page, @tagName(page)),
        };
    }

    fn shortcut(self: Page) ?input.CharacterPage {
        return switch (self) {
            .nearby, .loot => null,
            inline else => |page| @field(input.CharacterPage, @tagName(page)),
        };
    }

    /// Container selection and loot open without the character tabs.
    fn direct(self: Page) bool {
        return self.shortcut() == null;
    }
};
pub const PAGES = blk: {
    const keyed = std.enums.values(input.CharacterPage);
    var out: [keyed.len]Page = undefined;
    for (keyed, &out) |k, *p| p.* = Page.of(k);
    break :blk out;
};
const W = 1100;
const H = 640;
pub const SIZE = P{ .x = W, .y = H };
const TOP = 132;
const RIGHT = 568;
const DIVIDER_X = RIGHT - 18;
const ROW = 28;
const VISIBLE = 14;
/// A list's rows, then its text and second column within a row, and their tops down from the row's.
const LIST_X = 24;
const LIST_Y = 30;
const LIST_W = 510;
const TEXT_X = 8;
const SECOND_X = 336;
const ROW_TEXT_DY = 4;
const ROW_SECOND_DY = 5;
/// Down from a list's header to "Empty" when it has no rows.
const EMPTY_DY = 46;
/// The area under the tabs a page lays out in.
pub const AREA = look.rect(LIST_X, TOP, W - 2 * LIST_X, AREA_H);
const AREA_H = 458;
const CARD_W = 246;
const CARD_GAP = 16;
const CARD_H = 252;
/// Two cards side by side; one card alone or a note under them spans it.
const DETAIL_W = CARD_W * 2 + CARD_GAP;
const CLOSE_W = 108;
const CLOSE_H = 32;
const CLOSE_Y = 18;
/// The header row's middle: name, level and the close button.
const HEADER_MID = CLOSE_Y + CLOSE_H / 2;
/// Footer text's top, and where the divider stops.
const FOOT_Y = H - 32;
const DIVIDER_FOOT = H - 30;
/// An equipment cell's lines about its middle: the two of a held two-hander, or the worn item's name.
const PAIR_DY = 12;
const NAME_DY = 8;
const BOTH_HANDS = "Both hands";
const BOTH_IN_USE = BOTH_HANDS ++ " in use";
const TWO_HANDED = "Two-handed";
const ONE_HANDED = "One-handed";
const EMPTY_SLOT = "Empty slot";
const TAB_Y = 76;
const TAB_W = 184;
const TAB_H = 34;
const TAB_GAP = 9;
const TAB_MID = TAB_Y + TAB_H / 2;
const OFF_TAB_A: f32 = 0.7;
const TABS_X: i32 = @divExact(W - @as(i32, PAGES.len) * TAB_W - (@as(i32, PAGES.len) - 1) * TAB_GAP, 2);
/// Room each side of the tabs for the shoulder buttons' icons.
const SHOULDER_W = 40;
comptime {
    std.debug.assert(LIST_X + SHOULDER_W < TABS_X);
}
const ACTION_W = 164;
pub const ACTION_GAP = 8;
const ACTION_H = 36;
pub const ACTION_BOX = P{ .x = ACTION_W, .y = ACTION_H };
const ACTION_Y = H - 82;
/// Nearby and loot: header, list, the chosen item's card, a note line and the actions, each only as tall as it needs.
const DIRECT_W = 2 * LIST_X + LIST_W;
const DIRECT_GAP = 14;
/// Under the header, loot's inventory and gold line.
const HOLDING_Y = CLOSE_Y + CLOSE_H + 4;
const CHANGES_GAP = 10;
const RETURNS_GAP = 4;
/// Under "Both hands in use", its explanation's top.
const HELD_NOTE_DY = 42;
const LOSS = look.rgb(0xe18c83);
const GAIN = look.rgb(0xa8c596);
/// The most cells any page lays out by box.
const CELLS_MAX = @max(skillbar.ACTS.len, items.SLOTS.len);
const SLOT_BOX = std.EnumArray(items.Slot, struct { at: P, w: i32, h: i32 }).init(.{
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
});
const SLOT_LABEL = font.SMALL;
const SLOT_INSET = 4;
pub const Nearby = struct {
    kind: enum { loot, bag, chest, door },
    index: usize = 0,
    at: P,
    item: ?items.Item = null,

    pub fn command(n: Nearby) Command {
        return switch (n.kind) {
            .loot => .{ .pickup = n.index },
            .bag, .chest => .{ .open_loot = n.at },
            .door => .{ .travel = n.at },
        };
    }

    fn label(n: Nearby) [:0]const u8 {
        return if (n.item) |it| it.name() else switch (n.kind) {
            .chest => "Treasure chest",
            .bag => "Item bag",
            .door => "Door",
            .loot => unreachable,
        };
    }
};
pub const View = struct {
    class: hero.Class,
    name: []const u8,
    inventory: *const items.Inventory,
    growth: *const progress.State,
    /// Class and passives, before gear.
    base: attr.Attrs,
    gold: i32 = 0,
    nearby: []const Nearby = &.{},
    device: input.Device = .keys,
    chest: bool = false,
    fn stats(v: View) attr.Attrs {
        return v.inventory.gear.stats(v.base);
    }
};
pub const Command = union(enum) {
    close,
    equip: struct { index: usize, slot: items.Slot },
    unequip: items.Slot,
    drop: usize,
    passive: usize,
    skill: skillbar.Act,
    pickup: usize,
    take_all,
    open_loot: P,
    travel: P,
    bindings: skillbar.Act,

    fn verb(c: Command) [:0]const u8 {
        return verbOf(std.meta.activeTag(c));
    }
};
fn verbOf(c: std.meta.Tag(Command)) [:0]const u8 {
    return switch (c) {
        .close => "Close",
        .equip => "Equip",
        .unequip => "Unequip",
        .drop => "Drop",
        .passive, .skill => unreachable,
        .pickup => "Take item",
        .take_all => "Take all",
        .open_loot => "Loot",
        .travel => "Travel",
        .bindings => "Bind skill",
    };
}
pub const Book = struct {
    page: Page = .equipment,
    cursor: usize = 0,
    /// The first list row shown.
    top: usize = 0,
    last_page: Page = .equipment,
    last_cursor: usize = 0,
    loot_at: P = .{ .x = 0, .y = 0 },
    zoom: f32 = trees.ZOOM_START,
    pan: rl.Vector2 = .{ .x = 0, .y = 0 },
    destination_index: usize = 0,
    message: menu.Note(80) = .{},

    pub fn open(self: *Book) void {
        if (self.direct()) {
            const cursor = self.last_cursor;
            self.choose(self.last_page);
            self.cursor = cursor;
        }
        self.resetView();
    }
    pub fn direct(self: *const Book) bool {
        return self.page.direct();
    }
    pub fn choose(self: *Book, page: Page) void {
        if (page.direct() and !self.direct()) {
            self.last_page = self.page;
            self.last_cursor = self.cursor;
        }
        self.page = page;
        self.cursor = 0;
        self.top = 0;
        self.resetView();
    }
    fn resetView(self: *Book) void {
        self.zoom = trees.ZOOM_START;
        self.recentre();
        self.destination_index = 0;
        self.message.clear();
    }
    fn recentre(self: *Book) void {
        self.pan = .{ .x = 0, .y = 0 };
    }
    /// Selects cell `i`; the passive tree recentres on it.
    fn browse(self: *Book, i: usize) void {
        self.cursor = i;
        if (self.page == .passives) self.recentre();
    }
    /// Browses toward a bearing; with no node there, the cursor and the pan stay.
    fn walkTree(self: *Book, dx: f32, dy: f32) void {
        const next = progress.passives.step(self.cursor, dx, dy);
        if (next != self.cursor) self.browse(next);
    }
    fn selectedSkill(self: *const Book, v: View) skillbar.Act {
        return progress.skills(v.class)[self.cursor].act;
    }
    fn count(self: *const Book, v: View) usize {
        return switch (self.page) {
            .equipment => items.SLOTS.len,
            .inventory => v.inventory.n,
            .stats => 0,
            .passives => progress.NODES.len,
            .skills => progress.skills(v.class).len,
            .nearby, .loot => v.nearby.len,
        };
    }
    fn settledTop(self: *const Book, v: View) usize {
        return @min(mathx.reveal(self.top, self.cursor, VISIBLE), self.count(v) -| VISIBLE);
    }
    /// A scrolling list rather than laid-out cells.
    fn listed(self: *const Book) bool {
        return self.page == .inventory or self.direct();
    }
    fn treePanel(self: *const Book) ?trees.Panel {
        return switch (self.page) {
            .passives => .passives,
            .skills => .skills,
            else => null,
        };
    }
    fn treeView(self: *const Book) trees.View {
        return .{ .cursor = self.cursor, .zoom = self.zoom, .pan = self.pan };
    }
    fn zoomBy(self: *Book, amount: f32) void {
        self.zoom = std.math.clamp(self.zoom + amount, trees.ZOOM_MIN, trees.ZOOM_MAX);
        if (self.zoom == trees.ZOOM_MIN) self.recentre();
        self.clampPan();
    }
    fn clampPan(self: *Book) void {
        self.pan = trees.clampPan(self.treeView());
    }
    pub fn treeActive(self: *const Book) bool {
        return self.page == .passives;
    }
    fn inWindow(self: *const Book, i: usize) bool {
        return !self.listed() or (i >= self.top and i < self.top + VISIBLE);
    }
    pub fn enter(self: *Book, v: View) void {
        if (self.count(v) == 0) return;
        if (self.page == .passives) self.browse(progress.start(v.class));
    }
    fn selected(self: *const Book, v: View) ?items.Item {
        return switch (self.page) {
            .equipment => v.inventory.gear.slots.get(items.SLOTS[self.cursor]),
            .inventory => if (self.cursor < v.inventory.n) v.inventory.bag[self.cursor] else null,
            .nearby, .loot => if (self.cursor < v.nearby.len) v.nearby[self.cursor].item else null,
            else => null,
        };
    }
    fn destination(self: *const Book, v: View) items.Slot {
        const it = self.selected(v).?;
        const slots = it.kind.slots();
        return slots[@min(self.destination_index, slots.len - 1)];
    }
    fn select(self: *Book, v: View) ?Command {
        if (self.cursor >= self.count(v)) return null;
        return switch (self.page) {
            .equipment => if (self.selected(v) != null) .{ .unequip = items.SLOTS[self.cursor] } else blk: {
                self.choose(.inventory);
                break :blk null;
            },
            .inventory => .{ .equip = .{ .index = self.cursor, .slot = self.destination(v) } },
            .stats => null,
            .passives => if (v.growth.canAllocate(self.cursor)) .{ .passive = self.cursor } else null,
            .skills => blk: {
                const act = self.selectedSkill(v);
                break :blk if (v.growth.canLearn(v.class, act)) .{ .skill = act } else null;
            },
            .nearby, .loot => v.nearby[self.cursor].command(),
        };
    }
    fn size(self: *const Book, v: View) P {
        return if (self.direct()) .{ .x = DIRECT_W, .y = self.directActionY(v) + ACTION_H + LIST_X } else SIZE;
    }
    pub fn surface(self: *const Book, screen: P, v: View) menu.Surface {
        return if (self.direct()) menu.Surface.like(screen, self.size(v), SIZE) else menu.Surface.of(screen, SIZE);
    }
    fn directTop(self: *const Book) i32 {
        return if (self.page == .loot) HOLDING_Y + font.SMALL + DIRECT_GAP else CLOSE_Y + CLOSE_H + DIRECT_GAP;
    }
    fn cardTop(self: *const Book, v: View) i32 {
        return self.directTop() + @as(i32, @intCast(@min(self.count(v), VISIBLE))) * ROW + DIRECT_GAP;
    }
    /// The tallest card any listed item needs, so the panel keeps its size while the cursor moves.
    fn cardRoom(v: View) i32 {
        var most: i32 = 0;
        for (v.nearby) |n| if (n.item) |it| {
            for (it.kind.slots()) |slot| most = @max(most, cardFoot(it, slot, neededAttrs(v, it, slot)));
        };
        return most;
    }
    fn noteY(self: *const Book, v: View) i32 {
        const room = cardRoom(v);
        return self.cardTop(v) + if (room > 0) room + DIRECT_GAP else 0;
    }
    fn directActionY(self: *const Book, v: View) i32 {
        return self.noteY(v) + font.SMALL + DIRECT_GAP;
    }
    pub fn step(self: *Book, state: *const input.State, screen: P, v: View) ?Command {
        var local = state.*;
        if (local.pointer) |p| local.pointer = self.surface(screen, v).point(p);
        const st = &local;
        self.cursor = @min(self.cursor, self.count(v) -| 1);
        const previous_cursor = self.cursor;
        const previous_page = self.page;
        defer {
            if (self.cursor != previous_cursor or self.page != previous_page) {
                self.message.clear();
                self.destination_index = 0;
            }
            self.top = self.settledTop(v);
        }
        self.top = self.settledTop(v);
        if (local.click) if (local.pointer) |p| if (self.buttonAt(p, v)) |b| {
            local.pressed.insert(b);
            local.click = false;
        };
        if (menu.closed(st)) return .close;
        if (self.page == .loot and self.count(v) > 0 and st.hit(menu.CHANGE)) return .take_all;
        if (!self.direct() and (st.hit(.lb) or st.hit(.rb))) {
            self.choose(mathx.stepIn(Page, &PAGES, self.page, if (st.hit(.lb)) -1 else 1, 0));
            self.enter(v);
            return null;
        }
        if (self.page == .inventory and self.selected(v) != null) {
            if (st.hit(menu.REMOVE)) return .{ .drop = self.cursor };
            if (st.hit(menu.CHANGE)) self.destination_index = mathx.wrap(self.destination_index, 1, self.selected(v).?.kind.slots().len);
        }
        if (self.page == .skills and st.hit(menu.CHANGE)) return .{ .bindings = self.selectedSkill(v) };
        if (self.page == .passives) {
            if (st.hit(menu.CHANGE)) self.zoomBy(trees.ZOOM_STEP);
            if (st.hit(menu.REMOVE)) self.zoomBy(-trees.ZOOM_STEP);
            if (st.tree.zoom != 0) self.zoomBy(st.tree.zoom * trees.ZOOM_RATE * st.tree.dt);
            self.pan.x += st.tree.pan.x * trees.PAN_RATE * st.tree.dt / self.zoom;
            self.pan.y += st.tree.pan.y * trees.PAN_RATE * st.tree.dt / self.zoom;
            self.clampPan();
            if (st.tree.reset) {
                self.zoom = trees.ZOOM_MIN;
                self.recentre();
            }
            if (st.tree.move) |d| self.walkTree(d.x, d.y);
            if (st.pointer) |p| if (trees.onCanvas(p) and st.scroll != 0) {
                self.zoomBy(@as(f32, @floatFromInt(st.scroll)) * trees.ZOOM_WHEEL);
            };
        }
        if (self.listed() and st.scroll != 0 and self.count(v) > 0) {
            self.cursor = mathx.nudge(self.cursor, -st.scroll, self.count(v));
        }
        if (st.click) if (st.pointer) |p| {
            if (!self.direct()) for (PAGES, 0..) |page, i| if (look.holds(tabBox(i), p)) {
                self.choose(page);
                self.enter(v);
                return null;
            };
            for (0..self.count(v)) |i| {
                if (!self.inWindow(i)) continue;
                if (self.page == .passives and !trees.onCanvas(p)) continue;
                if (look.holds(self.cellBox(i, v), p)) {
                    self.browse(i);
                    return null;
                }
            }
        };
        if (st.walk) |dir| {
            const d = dir.delta();
            if (self.listed()) {
                if (d.y != 0 and self.count(v) > 0) self.cursor = mathx.wrap(self.cursor, d.y, self.count(v));
            } else if (self.page == .passives) {
                self.walkTree(@floatFromInt(d.x), @floatFromInt(d.y));
            } else if (self.count(v) > 0) {
                var boxes: [CELLS_MAX]rl.Rectangle = undefined;
                for (0..self.count(v)) |i| boxes[i] = self.cellBox(i, v);
                if (menu.nearest(boxes[self.cursor], boxes[0..self.count(v)], dir)) |i| self.cursor = i;
            }
        }
        if (st.hit(menu.CONFIRM)) {
            return self.select(v);
        }
        return null;
    }
    /// The button whose box is under `p`, so a click there is that button's press.
    fn buttonAt(self: *const Book, p: P, v: View) ?input.Button {
        const shown = self.controls(v);
        for (shown.all[0..shown.n]) |c| if (look.holds(c.box, p)) return c.button;
        return null;
    }
    /// Every button the page shows, the close button first.
    fn controls(self: *const Book, v: View) Controls {
        var c: Controls = .{};
        c.add(self.closeBox(v), menu.BACK, .{ .label = verbOf(.close) });
        switch (self.page) {
            .passives => {
                for ([_]bool{ false, true }) |increase| c.add(trees.zoomBox(increase), if (increase) menu.CHANGE else menu.REMOVE, .drawn);
                c.add(trees.actionBox(), menu.CONFIRM, .{ .prompt = if (v.growth.canAllocate(self.cursor)) 1 else look.FADED_A });
            },
            .skills => {
                const act = self.selectedSkill(v);
                c.add(trees.bindBox(), menu.CHANGE, .{ .label = if (v.growth.unlocked(act)) verbOf(.bindings) else "Bindings" });
                c.add(trees.actionBox(), menu.CONFIRM, .{ .prompt = if (v.growth.canLearn(v.class, act)) 1 else look.FADED_A });
            },
            .stats => {},
            .equipment, .inventory, .nearby, .loot => if (self.count(v) > 0) {
                const it = self.selected(v) orelse {
                    c.add(self.actionBox(menu.CONFIRM, v), menu.CONFIRM, .{ .label = if (self.direct()) v.nearby[self.cursor].command().verb() else "Inventory" });
                    return c;
                };
                c.add(self.actionBox(menu.CONFIRM, v), menu.CONFIRM, .{ .label = switch (self.page) {
                    .equipment => verbOf(.unequip),
                    .inventory => verbOf(.equip),
                    .nearby, .loot => verbOf(.pickup),
                    .stats, .passives, .skills => unreachable,
                } });
                if (self.page == .loot) c.add(self.actionBox(menu.CHANGE, v), menu.CHANGE, .{ .label = verbOf(.take_all) });
                if (self.page == .inventory) {
                    if (it.kind.slots().len > 1) c.add(self.actionBox(menu.CHANGE, v), menu.CHANGE, .{ .label = slotLabel(self.destination(v)) });
                    c.add(self.actionBox(menu.REMOVE, v), menu.REMOVE, .{ .label = verbOf(.drop) });
                }
            },
        }
        return c;
    }
    pub fn actionBox(self: *const Book, b: input.Button, v: View) rl.Rectangle {
        const i: i32 = @intCast(std.mem.indexOfScalar(input.Button, &ACTIONS, b).?);
        const x: i32 = if (self.direct()) LIST_X else RIGHT;
        return look.rect(x + i * (ACTION_W + ACTION_GAP), if (self.direct()) self.directActionY(v) else ACTION_Y, ACTION_W, ACTION_H);
    }
    fn closeBox(self: *const Book, v: View) rl.Rectangle {
        return look.rect(self.size(v).x - LIST_X - CLOSE_W, CLOSE_Y, CLOSE_W, CLOSE_H);
    }
    fn cellBox(self: *const Book, i: usize, v: View) rl.Rectangle {
        const y = TOP;
        return switch (self.page) {
            .equipment => blk: {
                const s = SLOT_BOX.get(items.SLOTS[i]);
                break :blk look.rect(s.at.x, y + s.at.y, s.w, s.h);
            },
            .inventory, .nearby, .loot => look.rect(LIST_X, (if (self.direct()) self.directTop() else y + LIST_Y) + (@as(i32, @intCast(i)) - @as(i32, @intCast(self.top))) * ROW, LIST_W, ROW),
            .passives, .skills => trees.cellBox(self.treePanel().?, v.class, i, self.treeView()),
            .stats => unreachable,
        };
    }
    /// A command can shrink the list under the cursor before the next `step` clamps it.
    pub fn draw(self: *const Book, source_face: *const font.Face, sprites: *const look.Sprites, screen: P, v: View) void {
        var shown = self.*;
        shown.cursor = @min(self.cursor, self.count(v) -| 1);
        shown.top = shown.settledTop(v);
        shown.drawClamped(source_face, sprites, screen, v);
    }
    fn drawClamped(self: *const Book, source_face: *const font.Face, sprites: *const look.Sprites, screen: P, v: View) void {
        const on = self.surface(screen, v);
        on.beginPanel(sprites, self.size(v));
        defer rl.endMode2D();
        const scaled_face = on.faceFor(source_face.*);
        const face = &scaled_face;
        if (self.direct()) {
            self.drawDirect(face, v);
        } else {
            var who: menu.Note(100) = .{};
            who.say("{s}   {s}", .{ v.name, v.class.title() });
            face.engraved(who.text(), LIST_X, HEADER_MID - font.HEAD / 2, font.HEAD, look.TEXT);
            var xp: menu.Note(100) = .{};
            xp.say("Level  {d}     XP  {d} / {d}", .{ v.growth.level, v.growth.xp, v.growth.needed() });
            face.drawMiddle(xp.text(), RIGHT, HEADER_MID, font.BODY, look.TEXT);
            for (PAGES, 0..) |page, i| tab(face, tabBox(i), page, self.page == page, v.device);
            if (self.treePanel() == null) rl.drawLine(DIVIDER_X, TOP, DIVIDER_X, DIVIDER_FOOT, look.EDGE);
            if (self.treePanel()) |panel| {
                trees.draw(panel, face, sprites, v.class, v.growth, self.treeView(), v.device, .{ .stats = v.stats(), .gear = v.inventory.gear }, on);
            } else if (self.page == .stats) {
                drawStats(face, v);
            } else {
                self.drawCells(face, v);
                self.drawDetail(face, v);
            }
            if (self.message.n > 0) {
                if (self.treePanel() != null) trees.note(face, self.message.text()) else face.draw(self.message.text(), RIGHT, FOOT_Y, font.SMALL, look.TEXT);
            }
        }
        const shown = self.controls(v);
        for (shown.all[0..shown.n]) |c| {
            const prompt = look.Prompt.menuOn(v.device, c.button);
            switch (c.shown) {
                .label => |label| menu.action(face, c.box, prompt, label),
                .prompt => |alpha| _ = menu.actionPrompt(face, c.box, prompt, alpha),
                .drawn => {},
            }
        }
        if (!self.direct()) {
            look.Prompt.menuOn(v.device, .lb).draw(face, LIST_X + SHOULDER_W / 2, TAB_MID, font.BODY, 1);
            look.Prompt.menuOn(v.device, .rb).draw(face, W - LIST_X - SHOULDER_W / 2, TAB_MID, font.BODY, 1);
        }
    }

    fn drawDirect(self: *const Book, face: *const font.Face, v: View) void {
        face.engraved(if (self.page == .nearby) "NEARBY" else if (v.chest) "CHEST LOOT" else "ITEM BAG", LIST_X, HEADER_MID - font.HEAD / 2, font.HEAD, look.TEXT);
        if (self.page == .loot) {
            var holding: menu.Note(100) = .{};
            holding.say("Inventory  {d} / {d}     Gold  {d}", .{ v.inventory.n, items.BAG_MAX, v.gold });
            face.draw(holding.text(), LIST_X, HOLDING_Y, font.SMALL, look.DIM);
        }
        self.drawCells(face, v);
        if (self.count(v) == 0) {
            face.draw("Empty", LIST_X + TEXT_X, self.directTop(), font.BODY, look.DIM);
            return;
        }
        if (self.selected(v)) |it| {
            const slot = self.destination(v);
            itemCard(face, LIST_X, self.cardTop(v), LIST_W, it, slot, self.requirementAttrs(v, slot), if (v.chest) "IN THE CHEST" else if (self.page == .loot) "IN THE BAG" else "ON THE GROUND");
        }
        const note_y = self.noteY(v);
        if (self.message.n > 0) face.draw(self.message.text(), LIST_X, note_y, font.SMALL, look.TEXT);
        var position: menu.Note(50) = .{};
        position.say("{d} / {d}", .{ self.cursor + 1, self.count(v) });
        face.draw(position.text(), DIRECT_W - LIST_X - face.width(position.text(), font.SMALL), note_y, font.SMALL, look.DIM);
    }

    fn drawCells(self: *const Book, face: *const font.Face, v: View) void {
        if (self.page == .inventory) {
            const text_x = LIST_X + TEXT_X;
            face.draw("ITEM", text_x, TOP, font.SMALL, look.DIM);
            face.draw("SLOT", LIST_X + SECOND_X, TOP, font.SMALL, look.DIM);
            if (self.count(v) == 0) face.draw("Empty", text_x, TOP + EMPTY_DY, font.BODY, look.DIM);
            var position: menu.Note(50) = .{};
            position.say("{d} / {d}", .{ if (self.count(v) > 0) self.cursor + 1 else 0, self.count(v) });
            face.draw(position.text(), text_x, FOOT_Y, font.SMALL, look.DIM);
        }
        for (0..self.count(v)) |i| {
            if (!self.inWindow(i)) continue;
            const r = self.cellBox(i, v);
            const x: i32 = @intFromFloat(r.x);
            const y: i32 = @intFromFloat(r.y);
            const chosen = i == self.cursor;
            rl.drawRectangleRec(r, look.BG);
            menu.outline(r, chosen, look.UI_FOCUS, look.EDGE);
            switch (self.page) {
                .equipment => {
                    const slot = items.SLOTS[i];
                    const inner = @as(i32, @intFromFloat(r.width)) - 2 * SLOT_INSET;
                    var fitted: [64]u8 = undefined;
                    face.draw(face.fit(&fitted, slotLabel(slot), SLOT_LABEL, inner, false), x + SLOT_INSET, y + SLOT_INSET, SLOT_LABEL, look.DIM);
                    const it = v.inventory.gear.slots.get(slot);
                    const mid = look.middleAt(r);
                    if (offhandWeapon(v.inventory.gear, slot)) |weapon| {
                        face.centred(BOTH_HANDS, mid.x, mid.y - PAIR_DY, font.SMALL, look.DIM);
                        face.centred(face.fit(&fitted, weapon.name(), font.SMALL, inner, false), mid.x, mid.y + PAIR_DY, font.SMALL, look.DIM);
                    } else {
                        const name = if (it) |a| (if (slot == .right_hand or slot == .left_hand) a.name() else menu.named(a.kind)) else "-";
                        face.centred(face.fit(&fitted, name, font.SMALL, inner, false), mid.x, mid.y + NAME_DY, font.SMALL, inkOf(it));
                    }
                },
                .inventory => {
                    const it = v.inventory.bag[i];
                    const slots = it.kind.slots();
                    listRow(face, x, y, it.name(), look.itemInk(it.magical()), if (items.spec(it.kind).two_handed) BOTH_HANDS else if (slots.len > 1) menu.named(it.kind) else slots[0].name());
                },
                .nearby, .loot => {
                    const n = v.nearby[i];
                    listRow(face, x, y, n.label(), inkOf(n.item), n.command().verb());
                },
                .passives, .skills, .stats => unreachable,
            }
        }
    }
    fn requirementAttrs(self: *const Book, v: View, slot: items.Slot) attr.Attrs {
        return switch (self.page) {
            .inventory => (v.inventory.swapped(self.cursor, slot) catch v.inventory.gear).statsWithout(slot, v.base),
            .nearby, .loot => neededAttrs(v, self.selected(v).?, slot),
            else => v.inventory.gear.statsWithout(slot, v.base),
        };
    }
    fn drawDetail(self: *const Book, face: *const font.Face, v: View) void {
        const x = RIGHT;
        const y = TOP;
        if (self.count(v) == 0) return;
        const it = self.selected(v) orelse {
            if (self.page == .equipment) if (offhandWeapon(v.inventory.gear, items.SLOTS[self.cursor])) |weapon| {
                face.draw(BOTH_IN_USE, x, y, font.HEAD, look.TEXT);
                var held: menu.Note(128) = .{};
                held.say("{s} uses both hands. Equipping an offhand returns it to inventory.", .{weapon.name()});
                _ = face.paragraph(held.text(), x, y + HELD_NOTE_DY, DETAIL_W, font.SMALL, look.DIM);
                return;
            };
            face.draw(if (self.direct()) v.nearby[self.cursor].label() else EMPTY_SLOT, x, y, font.HEAD, look.TEXT);
            return;
        };
        const slot = if (self.page == .equipment) items.SLOTS[self.cursor] else self.destination(v);
        const comparing = self.page == .inventory;
        itemCard(face, x, y, if (comparing) CARD_W else DETAIL_W, it, slot, self.requirementAttrs(v, slot), if (comparing) "SELECTED" else if (self.page == .equipment) "EQUIPPED" else if (v.chest) "IN THE CHEST" else "IN THE BAG");
        if (comparing) itemCard(face, x + CARD_W + CARD_GAP, y, CARD_W, v.inventory.gear.slots.get(slot), slot, v.inventory.gear.statsWithout(slot, v.base), "EQUIPPED");
        if (self.page == .inventory) {
            const at = y + CARD_H + CHANGES_GAP;
            if (v.inventory.preview(self.cursor, slot, v.base)) |after| {
                var below = drawChanges(face, x, at, v.stats(), after.stats(v.base)) + RETURNS_GAP;
                for (items.SLOTS) |s| {
                    if (s == slot or !v.inventory.displaced(after, slot, s)) continue;
                    var moved: menu.Note(100) = .{};
                    moved.say("Returns {s} to inventory.", .{v.inventory.gear.slots.get(s).?.name()});
                    face.draw(moved.text(), x, below, font.SMALL, look.DIM);
                    below += CHANGE_ROW;
                }
            } else |err| {
                var reason: menu.Note(140) = .{};
                if (err != error.Requirements) {
                    reason.say("{s}", .{items.caption(err)});
                } else if (dependent(v, self.cursor, slot)) |other| {
                    reason.say("Would leave {s} without its required attributes.", .{other.name()});
                } else reason.say("Cannot equip: requirements not met.", .{});
                _ = face.paragraph(reason.text(), x, at, DETAIL_W, font.SMALL, LOSS);
            }
        }
    }
};

const CONTROLS_MAX = 4;
/// A labelled button; a prompt over a button the tree panel draws, at this alpha; or drawn there whole.
const Shown = union(enum) { label: [:0]const u8, prompt: f32, drawn };
const Control = struct { box: rl.Rectangle, button: input.Button, shown: Shown };
const Controls = struct {
    all: [CONTROLS_MAX]Control = undefined,
    n: usize = 0,

    fn add(self: *Controls, box: rl.Rectangle, button: input.Button, shown: Shown) void {
        self.all[self.n] = .{ .box = box, .button = button, .shown = shown };
        self.n += 1;
    }
};

fn listRow(face: *const font.Face, x: i32, y: i32, text: [:0]const u8, ink: rl.Color, second: [:0]const u8) void {
    face.draw(text, x + TEXT_X, y + ROW_TEXT_DY, font.BODY, ink);
    face.draw(second, x + SECOND_X, y + ROW_SECOND_DY, font.SMALL, look.DIM);
}
fn tabBox(i: usize) rl.Rectangle {
    return look.rect(TABS_X + @as(i32, @intCast(i)) * (TAB_W + TAB_GAP), TAB_Y, TAB_W, TAB_H);
}
/// The detail panel's buttons, left to right.
const ACTIONS = [_]input.Button{ menu.CONFIRM, menu.CHANGE, menu.REMOVE };
/// What wearing ground item `it` in `slot` leaves to meet its requirements.
fn neededAttrs(v: View, it: items.Item, slot: items.Slot) attr.Attrs {
    return v.inventory.gear.wearing(it, slot).statsWithout(slot, v.base);
}
/// Short enough for a ring's small box.
fn slotLabel(s: items.Slot) [:0]const u8 {
    return switch (s) {
        .left_ring => "L ring",
        .right_ring => "R ring",
        .left_hand, .right_hand, .helm, .chest, .belt, .gloves, .boots, .amulet => s.name(),
    };
}
fn tab(face: *const font.Face, r: rl.Rectangle, page: Page, on: bool, device: input.Device) void {
    menu.outline(r, on, look.UI_FOCUS, look.EDGE);
    const m = look.middleAt(r);
    const text = menu.named(page);
    const ink = if (on) look.TEXT else look.DIM;
    if (!device.pad()) {
        const prompt = look.Prompt{ .key = page.shortcut().?.caption() };
        const left = m.x - @divTrunc(prompt.width(face, font.BODY) + menu.PROMPT_GAP + face.width(text, font.BODY), 2);
        const after = prompt.drawFrom(face, left, m.y, font.BODY, if (on) 1 else OFF_TAB_A);
        face.drawMiddle(text, after + menu.PROMPT_GAP, m.y, font.BODY, ink);
    } else face.centred(text, m.x, m.y, font.BODY, ink);
}
fn offhandWeapon(gear: items.Gear, slot: items.Slot) ?items.Item {
    return if (slot == .left_hand) gear.twoHander() else null;
}

/// Something else worn that equipping bag item `at` in `slot` would leave unmet.
fn dependent(v: View, at: usize, slot: items.Slot) ?items.Item {
    const after = v.inventory.swapped(at, slot) catch return null;
    for (items.SLOTS) |s| {
        if (s == slot) continue;
        if (after.slots.get(s)) |other| if (!after.wornMeets(s, v.base)) return other;
    }
    return null;
}

const CARD_LINE = 22;
/// Down from a card's top: its rule, name (or "Empty slot"), slot, flavor and first stat line.
const CARD_RULE = 20;
const CARD_NAME = 32;
const CARD_EMPTY = 35;
const CARD_SLOT = 62;
const CARD_FLAVOR = 82;
const CARD_STATS = 104;
/// Above and below the modifiers' rule, and its inset from the card's sides.
const MODS_ABOVE = 8;
const MODS_BELOW = 12;
const MODS_INSET = 30;

const CardLine = union(enum) {
    damage: damage.Base,
    scaling: attr.Attr,
    unarmed,
    armour: i16,
    requires: struct { at: attr.Attr, n: i32, met: bool },
    available: i32,

    fn text(l: CardLine, out: *menu.Note(120)) [:0]const u8 {
        switch (l) {
            .damage => |hit| out.say("Physical damage: {d}-{d}", .{ hit.lo, hit.hi }),
            .scaling => |at| out.say("Scales with {s}", .{menu.named(at)}),
            .unarmed => return "No weapon damage",
            .armour => |n| out.say("Physical damage reduced by {d}%", .{n}),
            .requires => |r| out.say("Requires {d} {s}", .{ r.n, menu.named(r.at) }),
            .available => |n| out.say("({d} available)", .{n}),
        }
        return out.text();
    }

    fn ink(l: CardLine) rl.Color {
        return switch (l) {
            .damage, .armour => look.TEXT,
            .scaling, .unarmed => look.DIM,
            .requires => |r| if (r.met) look.DIM else LOSS,
            .available => LOSS,
        };
    }
};

const CardLines = struct {
    all: [3 + 2 * attr.ATTRS.len]CardLine = undefined,
    n: usize = 0,

    fn add(self: *CardLines, l: CardLine) void {
        self.all[self.n] = l;
        self.n += 1;
    }

    /// `spec`'s lines for `slot`; with no `available`, every requirement is unmet, the most lines it can have.
    fn of(spec: items.Spec, slot: items.Slot, available: ?attr.Attrs) CardLines {
        var out: CardLines = .{};
        if (spec.damage) |hit| {
            out.add(.{ .damage = hit });
            out.add(.{ .scaling = spec.style.attr() });
        } else if (slot == .right_hand) out.add(.unarmed);
        if (spec.armour > 0) out.add(.{ .armour = spec.armour });
        inline for (attr.ATTRS) |at| {
            const required = @field(spec.needs, @tagName(at));
            if (required > 0) {
                const met = if (available) |a| a.get(at) >= required else false;
                out.add(.{ .requires = .{ .at = at, .n = required, .met = met } });
                if (!met) out.add(.{ .available = if (available) |a| a.get(at) else 0 });
            }
        }
        return out;
    }

    fn lines(self: *const CardLines) []const CardLine {
        return self.all[0..self.n];
    }
};

/// Down from a card's top to the foot of its last line, as `itemCard` lays out `lines` stat lines and `mods` modifiers.
fn footOf(lines: usize, mods: usize) i32 {
    const n: i32 = @intCast(lines);
    const m: i32 = @intCast(mods);
    const last = CARD_STATS + n * CARD_LINE + (if (m > 0) MODS_ABOVE + MODS_BELOW + m * CARD_LINE else 0) - CARD_LINE;
    return @max(CARD_FLAVOR, last) + font.SMALL;
}

fn cardFoot(it: items.Item, slot: items.Slot, available: attr.Attrs) i32 {
    var mods: usize = 0;
    if (it.magical()) for (items.MODS) |m| {
        if (it.value(m) != 0) mods += 1;
    };
    return footOf(CardLines.of(items.spec(it.kind), slot, available).n, mods);
}

comptime {
    const mods = (items.Item{ .kind = .cap }).mods.len;
    for (std.enums.values(items.Kind)) |k| {
        const s = items.spec(k);
        for (s.slots) |slot| {
            if (footOf(CardLines.of(s, slot, null).n, mods) > CARD_H) @compileError(s.name ++ "'s card can run past CARD_H");
        }
    }
}

fn itemCard(face: *const font.Face, x: i32, y: i32, width: i32, maybe: ?items.Item, slot: items.Slot, available: attr.Attrs, caption: [:0]const u8) void {
    const mid = x + @divTrunc(width, 2);
    face.drawMid(caption, mid, y, font.SMALL, look.DIM);
    rl.drawLine(x, y + CARD_RULE, x + width, y + CARD_RULE, look.EDGE);
    const it = maybe orelse {
        face.drawMid(EMPTY_SLOT, mid, y + CARD_EMPTY, font.BODY, look.DIM);
        face.drawMid(slot.name(), mid, y + CARD_SLOT, font.SMALL, look.DIM);
        return;
    };
    const spec = items.spec(it.kind);
    const ink = look.itemInk(it.magical());
    var fitted: [64]u8 = undefined;
    face.engravedMid(face.fit(&fitted, it.name(), font.HEAD, width, false), mid, y + CARD_NAME, font.HEAD, ink);
    face.drawMid(if (slot == .right_hand) (if (spec.two_handed) TWO_HANDED else ONE_HANDED) else slot.name(), mid, y + CARD_SLOT, font.SMALL, look.DIM);
    face.drawMid(face.fit(&fitted, it.flavor(), font.SMALL, width, false), mid, y + CARD_FLAVOR, font.SMALL, look.DIM);
    var top = y + CARD_STATS;
    var line: menu.Note(120) = .{};
    const stats = CardLines.of(spec, slot, available);
    for (stats.lines()) |l| {
        face.drawMid(l.text(&line), mid, top, font.SMALL, l.ink());
        top += CARD_LINE;
    }
    if (it.magical()) {
        top += MODS_ABOVE;
        rl.drawLine(x + MODS_INSET, top, x + width - MODS_INSET, top, look.EDGE);
        top += MODS_BELOW;
        for (items.MODS) |m| {
            const n = it.value(m);
            if (n == 0) continue;
            line.say(attr.Bonus.RAISE_FMT, .{ n, m.label() });
            face.drawMid(line.text(), mid, top, font.SMALL, look.MAGIC);
            top += CARD_LINE;
        }
    }
}

fn change(face: *const font.Face, x: i32, y: i32, n: *usize, label: [:0]const u8, was: i32, now: i32, percent: bool) void {
    const delta = now - was;
    if (delta == 0) return;
    var text: menu.Note(100) = .{};
    text.say("{s}{d}{s} {s}", .{ if (delta > 0) @as([]const u8, "+") else "", delta, if (percent) @as([]const u8, "%") else "", label });
    const at = mathx.unslot(n.*, CHANGE_COLS);
    face.draw(text.text(), x + at.x * (CARD_W + CARD_GAP), y + at.y * CHANGE_ROW, font.SMALL, if (delta > 0) GAIN else LOSS);
    n.* += 1;
}

const CHANGE_ROW = 20;
const CHANGE_COLS = 2;

fn changeRows(n: usize) i32 {
    return @intCast((n + CHANGE_COLS - 1) / CHANGE_COLS);
}
/// A character stat the Stats page and the change list both show.
const Measure = union(enum) {
    life,
    mana,
    attribute: attr.Attr,
    reduction,
    crit,
    dodge,
    style: attr.Style,

    fn of(m: Measure, a: attr.Attrs) i32 {
        return switch (m) {
            .life => a.life(),
            .mana => a.mana(),
            .attribute => |at| a.get(at),
            .reduction => a.reduction(),
            .crit => @intCast(a.crit()),
            .dodge => @intCast(a.dodge()),
            .style => |s| a.increase(s),
        };
    }

    fn percent(m: Measure) bool {
        return switch (m) {
            .life, .mana, .attribute => false,
            .reduction, .crit, .dodge, .style => true,
        };
    }

    /// Its Stats page row.
    fn title(m: Measure) [:0]const u8 {
        return switch (m) {
            .life => comptime menu.capital(attr.Bonus.life.label()),
            .mana => comptime menu.capital(attr.Bonus.mana.label()),
            .attribute => |at| menu.named(at),
            .reduction => comptime menu.capital(attr.REDUCTION_LABEL),
            .crit => comptime menu.capital(attr.CRIT_LABEL),
            .dodge => "Chance to dodge",
            .style => |s| s.label(),
        };
    }

    /// Its change line, short enough for half the detail panel.
    fn label(m: Measure) [:0]const u8 {
        return switch (m) {
            .life => attr.Bonus.life.label(),
            .mana => attr.Bonus.mana.label(),
            .attribute => |at| menu.named(at),
            .reduction => "physical reduction",
            .crit => "critical chance",
            .dodge => "dodge chance",
            .style => |s| damageLabel(s),
        };
    }
};
/// Every line `drawChanges` can list, in order.
const CHANGE_ROWS = blk: {
    var rows: []const Measure = &.{ .life, .mana };
    for (attr.ATTRS) |at| rows = rows ++ &[_]Measure{.{ .attribute = at }};
    rows = rows ++ &[_]Measure{ .reduction, .crit, .dodge };
    for (attr.STYLES) |s| rows = rows ++ &[_]Measure{.{ .style = s }};
    break :blk rows[0..rows.len].*;
};

comptime {
    std.debug.assert(TOP + CARD_H + CHANGES_GAP + CARD_LINE + changeRows(CHANGE_ROWS.len) * CHANGE_ROW + RETURNS_GAP + font.SMALL <= ACTION_Y);
}

/// The foot of the change list.
fn drawChanges(face: *const font.Face, x: i32, y: i32, was: attr.Attrs, now: attr.Attrs) i32 {
    face.draw("IF EQUIPPED", x, y, font.SMALL, look.DIM);
    var n: usize = 0;
    const top = y + CARD_LINE;
    for (CHANGE_ROWS) |m| change(face, x, top, &n, m.label(), m.of(was), m.of(now), m.percent());
    if (n == 0) {
        face.draw("No attribute or defense changes.", x, top, font.SMALL, look.DIM);
        return top + CHANGE_ROW;
    }
    return top + changeRows(n) * CHANGE_ROW;
}

fn inkOf(it: ?items.Item) rl.Color {
    return look.itemInk(if (it) |i| i.magical() else false);
}

fn damageLabel(s: attr.Style) [:0]const u8 {
    return switch (s) {
        inline else => |t| @tagName(t) ++ " damage bonus",
    };
}

const STAT_W = 440;
const STATS_X = 40;
/// A section's title to its rule and to its first row, and row to row.
const SECTION_RULE = 25;
const SECTION_ROWS = 38;
const STAT_ROW = 30;
const ATTR_ROW = 58;
/// Under an attribute's row, its description.
const ATTR_NOTE_DY = 25;
/// Below a section's rows: its note, and the gap to what follows.
const SURVIVAL_NOTE_DY = 7;
const BONUS_NOTE_DY = 11;
const SURVIVAL_GAP = 14;
const CRIT_GAP = 52;
const PROGRESSION_GAP = 32;
const GOLD_GAP = 20;

fn row(top: i32, i: usize, step: i32) i32 {
    return top + SECTION_ROWS + @as(i32, @intCast(i)) * step;
}

fn stat(face: *const font.Face, x: i32, y: i32, label: [:0]const u8, number: i32, prefix: []const u8, suffix: []const u8) void {
    face.draw(label, x, y, font.BODY, look.TEXT);
    var text: menu.Note(48) = .{};
    text.say("{s}{d}{s}", .{ prefix, number, suffix });
    face.draw(text.text(), x + STAT_W - face.width(text.text(), font.BODY), y, font.BODY, look.TEXT);
}

fn measure(face: *const font.Face, x: i32, y: i32, m: Measure, a: attr.Attrs) void {
    stat(face, x, y, m.title(), m.of(a), if (m == .style) "+" else "", if (m.percent()) "%" else "");
}

const SURVIVAL = [_]Measure{ .life, .mana, .reduction, .dodge };

fn section(face: *const font.Face, x: i32, y: i32, title: [:0]const u8) void {
    face.draw(title, x, y, font.SMALL, look.UI_FOCUS);
    rl.drawLine(x, y + SECTION_RULE, x + STAT_W, y + SECTION_RULE, look.EDGE);
}

fn drawStats(face: *const font.Face, v: View) void {
    const a = v.stats();
    const x = STATS_X;
    const right = RIGHT;
    const y = TOP;
    section(face, x, y, "ATTRIBUTES");
    for (attr.ATTRS, 0..) |at, i| {
        const top = row(y, i, ATTR_ROW);
        measure(face, x, top, .{ .attribute = at }, a);
        face.draw(switch (at) {
            .strength => "Life and heavy weapon damage",
            .dexterity => "Light weapons, critical chance and dodge",
            .intelligence => "Mana and spell damage",
        }, x, top + ATTR_NOTE_DY, font.SMALL, look.DIM);
    }
    const survival = row(y, attr.ATTRS.len, ATTR_ROW) + SURVIVAL_GAP;
    section(face, x, survival, "SURVIVAL");
    for (SURVIVAL, 0..) |m, i| measure(face, x, row(survival, i, STAT_ROW), m, a);
    var note: menu.Note(100) = .{};
    note.say("Physical reduction is capped at {d}%.", .{attr.ARMOUR_MAX});
    face.draw(note.text(), x, row(survival, SURVIVAL.len, STAT_ROW) + SURVIVAL_NOTE_DY, font.SMALL, look.DIM);
    section(face, right, y, "DAMAGE BONUSES");
    for (attr.STYLES, 0..) |s, i| measure(face, right, row(y, i, STAT_ROW), .{ .style = s }, a);
    const bonuses = row(y, attr.STYLES.len, STAT_ROW);
    face.draw("Bonuses to base damage; skill ranks add their own.", right, bonuses + BONUS_NOTE_DY, font.SMALL, look.DIM);
    const crit = bonuses + CRIT_GAP;
    measure(face, right, crit, .crit, a);
    stat(face, right, crit + STAT_ROW, "Critical damage multiplier", attr.CRIT_MULTI, "", "%");
    const progression = crit + 2 * STAT_ROW + PROGRESSION_GAP;
    section(face, right, progression, "PROGRESSION");
    stat(face, right, row(progression, 0, STAT_ROW), "Passive points available", v.growth.passive_points, "", "");
    stat(face, right, row(progression, 1, STAT_ROW), "Active skill points available", v.growth.active_points, "", "");
    stat(face, right, row(progression, 2, STAT_ROW) + GOLD_GAP, "Gold", v.gold, "", "");
}

test "character actions need one press and tabs are directly reachable" {
    var inv = items.Inventory{};
    try std.testing.expect(inv.add(.{ .kind = .cap }));
    var growth = progress.State.of(.archer);
    const v = View{ .class = .archer, .name = "Test", .inventory = &inv, .growth = &growth, .base = growth.attributes(.archer) };
    var book = Book{ .page = .inventory };
    const screen = P{ .x = 1600, .y = 900 };
    const confirm = input.State{ .pressed = .initOne(menu.CONFIRM) };
    try std.testing.expect(book.step(&confirm, screen, v).? == .equip);
    try std.testing.expectEqual(@as(usize, 1), inv.n);
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.REMOVE) }, screen, v).? == .drop);
    _ = book.step(&.{ .pressed = .initOne(.rb) }, screen, v);
    try std.testing.expectEqual(Page.stats, book.page);
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.BACK) }, screen, v).? == .close);
    book.choose(.inventory);
    const surface = book.surface(screen, v);
    const box = book.actionBox(menu.CONFIRM, v);
    const p = surface.screenOf(.{ .x = box.x + 20, .y = box.y + 20 });
    try std.testing.expect(book.step(&.{ .click = true, .pointer = p }, screen, v).? == .equip);
    book.choose(.skills);
    book.cursor = 2;
    book.choose(.nearby);
    book.open();
    try std.testing.expectEqual(Page.skills, book.page);
    try std.testing.expectEqual(@as(usize, 2), book.cursor);
    book.choose(.passives);
    book.zoom = trees.ZOOM_MIN;
    book.open();
    try std.testing.expectEqual(trees.ZOOM_START, book.zoom);
    std.debug.print("character actions: direct equip/drop, shoulder tabs, one-step close, scaled mouse hit; commands leave inventory untouched\n", .{});
}

test "loot exposes single pickup and take all through controller and mouse controls" {
    const inv = items.Inventory{};
    const growth = progress.State.of(.archer);
    const v = View{ .class = .archer, .name = "Test", .inventory = &inv, .growth = &growth, .base = growth.attributes(.archer), .nearby = &.{.{ .kind = .loot, .index = 7, .at = .{ .x = 20, .y = 20 }, .item = .{ .kind = .cap } }} };
    var book = Book{ .page = .loot };
    const screen = P{ .x = 1280, .y = 720 };
    const one = book.step(&.{ .pressed = .initOne(menu.CONFIRM) }, screen, v).?;
    try std.testing.expectEqual(@as(usize, 7), one.pickup);
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.CHANGE) }, screen, v).? == .take_all);
    const surface = book.surface(screen, v);
    const box = book.actionBox(menu.CHANGE, v);
    const p = surface.screenOf(.{ .x = box.x + 20, .y = box.y + 20 });
    try std.testing.expect(book.step(&.{ .click = true, .pointer = p }, screen, v).? == .take_all);
    const panel = book.size(v);
    try std.testing.expect(panel.x < SIZE.x and panel.y < SIZE.y);
    try std.testing.expectEqual(@as(f32, @floatFromInt(panel.y - ACTION_H - LIST_X)), book.actionBox(menu.CONFIRM, v).y);
    std.debug.print("loot panel: {d}x{d} for one item, Book {d}x{d}\n", .{ panel.x, panel.y, SIZE.x, SIZE.y });
    _ = book.step(&.{ .pressed = .initOne(.rb) }, screen, v);
    try std.testing.expectEqual(Page.loot, book.page);
    std.debug.print("loot controls: selected index, take-all press and scaled mouse hit, no character tabs\n", .{});
}

test "the inventory list scrolls back when the bag shrinks" {
    var inv = items.Inventory{};
    for (0..VISIBLE + 6) |_| try std.testing.expect(inv.add(.{ .kind = .cap }));
    var growth = progress.State.of(.archer);
    const v = View{ .class = .archer, .name = "Test", .inventory = &inv, .growth = &growth, .base = growth.attributes(.archer) };
    const screen = P{ .x = 1600, .y = 900 };
    var book = Book{ .page = .inventory, .cursor = VISIBLE + 5 };
    _ = book.step(&.{}, screen, v);
    try std.testing.expectEqual(@as(usize, 6), book.top);
    for (0..6) |_| _ = inv.remove(inv.n - 1);
    _ = book.step(&.{}, screen, v);
    try std.testing.expectEqual(@as(usize, 0), book.top);
    try std.testing.expectEqual(@as(usize, VISIBLE - 1), book.cursor);
    book.top = 6;
    var drawn = book;
    drawn.top = drawn.settledTop(v);
    const box = drawn.cellBox(0, v);
    const surface = menu.Surface.of(screen, SIZE);
    const p = surface.screenOf(.{ .x = box.x + 20, .y = box.y + 10 });
    _ = book.step(&.{ .click = true, .pointer = p }, screen, v);
    try std.testing.expectEqual(@as(usize, 0), book.cursor);
    std.debug.print("inventory scroll: top 6 of {d}, back to {d} once {d} remain\n", .{ VISIBLE + 6, book.top, inv.n });
}

test "item card requirements exclude the item itself and every displaced hand" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    const base = attr.Attrs.of(.{ .strength = 10, .dexterity = 12, .intelligence = 10 });
    const v = View{ .class = .archer, .name = "Test", .inventory = &inv, .growth = &growth, .base = base };
    inv.gear.slots.set(.left_hand, .{ .kind = .shield, .mods = .{ .{ .kind = .strength, .value = 10 }, null } });
    try std.testing.expect(inv.add(.{ .kind = .axe, .mods = .{ .{ .kind = .strength, .value = 10 }, null } }));
    var book = Book{ .page = .inventory };
    try std.testing.expectEqual(@as(i32, 10), book.requirementAttrs(v, .right_hand).get(.strength));
    try std.testing.expectError(error.Requirements, inv.preview(0, .right_hand, base));
    try std.testing.expect(inv.gear.slots.get(.left_hand) != null and inv.n == 1);
    inv.gear.slots.set(.left_hand, null);
    inv.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 3 }, null } });
    inv.gear.slots.set(.right_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 7 }, null } });
    inv.bag[0] = .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 2 }, null } };
    try std.testing.expectEqual(@as(i32, 17), book.requirementAttrs(v, .left_ring).get(.strength));
    try std.testing.expectEqual(@as(i32, 13), book.requirementAttrs(v, .right_ring).get(.strength));
    book.page = .equipment;
    try std.testing.expectEqual(@as(i32, 17), book.requirementAttrs(v, .left_ring).get(.strength));
    inv.gear.slots.set(.left_hand, .{ .kind = .shield, .mods = .{ .{ .kind = .strength, .value = 10 }, null } });
    var ground = v;
    ground.nearby = &.{.{ .kind = .loot, .at = .{ .x = 0, .y = 0 }, .item = .{ .kind = .axe, .mods = .{ null, null } } }};
    book.choose(.nearby);
    try std.testing.expectEqual(@as(i32, 20), book.requirementAttrs(ground, .right_hand).get(.strength));
    std.debug.print("item cards: 2-hand displacement, self-funding, both ring destinations and ground items; inventory unchanged\n", .{});
}

test "tree browsing is free and point actions issue one command" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    growth.passive_points = 2;
    growth.active_points = 2;
    const v = View{ .class = .archer, .name = "Test", .inventory = &inv, .growth = &growth, .base = growth.attributes(.archer) };
    const screen = P{ .x = 1280, .y = 720 };
    var book = Book{ .page = .passives, .cursor = progress.passives.branchFirst(.rogue_evade) };
    try std.testing.expectEqual(trees.ZOOM_START, book.zoom);
    try std.testing.expect(book.treeActive());
    const original_cursor = book.cursor;
    _ = book.step(&.{ .tree = .{ .zoom = -1, .pan = .{ .x = 1, .y = -1 }, .dt = 0.25 } }, screen, v);
    try std.testing.expect(book.zoom < trees.ZOOM_START and book.pan.x > 0 and book.pan.y < 0);
    try std.testing.expectEqual(original_cursor, book.cursor);
    _ = book.step(&.{ .tree = .{ .move = .{ .x = 1, .y = 0 } } }, screen, v);
    try std.testing.expectEqual(progress.passives.step(original_cursor, 1, 0), book.cursor);
    try std.testing.expectEqual(@as(f32, 0), book.pan.x);
    _ = book.step(&.{ .tree = .{ .zoom = 1, .dt = 100 } }, screen, v);
    try std.testing.expectEqual(trees.ZOOM_MAX, book.zoom);
    _ = book.step(&.{ .tree = .{ .reset = true } }, screen, v);
    try std.testing.expectEqual(trees.ZOOM_MIN, book.zoom);
    try std.testing.expectEqual(@as(f32, 0), book.pan.y);
    book.cursor = original_cursor;
    var zoom = input.State{};
    zoom.pressed.insert(menu.CHANGE);
    _ = book.step(&zoom, screen, v);
    try std.testing.expect(book.zoom > trees.ZOOM_MIN);
    var confirm = input.State{};
    confirm.pressed.insert(menu.CONFIRM);
    try std.testing.expectEqual(book.cursor, book.step(&confirm, screen, v).?.passive);
    try std.testing.expectEqual(@as(u16, 2), growth.passive_points);
    book.choose(.skills);
    book.cursor = 0;
    try std.testing.expectEqual(progress.skills(.archer)[0].act, book.step(&confirm, screen, v).?.skill);
    try std.testing.expectEqual(@as(u16, 2), growth.active_points);
    book.choose(.passives);
    try std.testing.expectEqual(trees.ZOOM_START, book.zoom);
    const canvas = trees.zoomBox(true);
    const surface = menu.Surface.of(screen, SIZE);
    _ = book.step(&.{ .pointer = surface.screenOf(.{ .x = canvas.x, .y = canvas.y }), .scroll = -1 }, screen, v);
    try std.testing.expect(book.treeActive() and book.zoom < trees.ZOOM_START);
    std.debug.print("tree book: spatial browsing and zoom spend no points; passive and skill selection return one command\n", .{});
}

test "a stick pushed where no passive lies keeps the pan, as the keys do" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    const v = View{ .class = .archer, .name = "Test", .inventory = &inv, .growth = &growth, .base = growth.attributes(.archer) };
    const screen = P{ .x = 1280, .y = 720 };
    const dead_end = found: for (0..progress.NODES.len) |i| {
        for (mathx.CARDINALS) |delta| {
            if (progress.passives.step(i, @floatFromInt(delta.x), @floatFromInt(delta.y)) == i) break :found .{ i, delta };
        }
    } else unreachable;
    var book = Book{ .page = .passives, .cursor = dead_end[0] };
    _ = book.step(&.{ .tree = .{ .pan = .{ .x = 1, .y = 1 }, .dt = 0.25 } }, screen, v);
    const pan = book.pan;
    try std.testing.expect(pan.x != 0 or pan.y != 0);
    const move: rl.Vector2 = .{ .x = @floatFromInt(dead_end[1].x), .y = @floatFromInt(dead_end[1].y) };
    _ = book.step(&.{ .tree = .{ .move = move } }, screen, v);
    try std.testing.expectEqual(dead_end[0], book.cursor);
    try std.testing.expectEqual(pan, book.pan);
    std.debug.print("dead-end stick on node {d}: pan kept at {d:.1},{d:.1}\n", .{ dead_end[0], pan.x, pan.y });
}
