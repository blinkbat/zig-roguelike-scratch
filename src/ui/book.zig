const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const hero = @import("../play/hero.zig");
const attr = @import("../play/attrs.zig");
const items = @import("../play/items.zig");
const damage = @import("../play/damage.zig");
const bleeding = @import("../play/bleeding.zig");
const resilience = @import("../play/resilience.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const trees = @import("trees.zig");
const hud = @import("hud.zig");
const display = @import("../core/window.zig");
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
const DIRECT_VISIBLE = 8;
/// A list's rows, then its text and second column within a row.
const LIST_X = menu.PANEL_PAD;
const LIST_Y = 30;
const LIST_W = 510;
const TEXT_X = 8;
const SECOND_X = 336;
/// Down from a list's header to "Empty" when it has no rows.
const EMPTY_DY = 46;
/// The area under the tabs a page lays out in.
pub const AREA = raster.rect(LIST_X, TOP, W - 2 * LIST_X, AREA_H);
const AREA_H = 458;
const CARD_W = 246;
const CARD_GAP = 16;
const CARD_H = 290;
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
const ACTION_W = menu.ACTION_BOX.x;
const ACTION_H = menu.ACTION_BOX.y;
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
pub const Nearby = union(enum) {
    loot: struct { index: usize, item: items.Item },
    gold: items.Coins,
    bag: P,
    chest: P,
    door: P,

    pub fn command(n: Nearby) Command {
        return switch (n) {
            .loot => |l| .{ .pickup = l.index },
            .gold => |pile| .{ .take_gold = pile.at },
            .bag, .chest => |at| .{ .open_loot = at },
            .door => |at| .{ .travel = at },
        };
    }

    fn item(n: Nearby) ?items.Item {
        return switch (n) {
            .loot => |l| l.item,
            .gold, .bag, .chest, .door => null,
        };
    }

    fn label(n: Nearby, buf: []u8) [:0]const u8 {
        return switch (n) {
            .loot => |l| l.item.name(buf),
            .gold => |pile| std.fmt.bufPrintZ(buf, "{d} gold", .{pile.amount}) catch "Gold",
            .chest => "Treasure chest",
            .bag => "Item bag",
            .door => "Door",
        };
    }
};
pub const Vital = struct { now: i32 = 0, max: i32 = 0 };
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
    life: Vital = .{},
    mana: Vital = .{},
    resists: damage.Resists = .initFill(0),
    status_resist: std.EnumArray(resilience.Kind, resilience.Standing) = .initFill(.{}),
    steady: u8 = 0,
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
    take_gold: P,
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
        .take_gold => "Take gold",
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
    mouse_panning: bool = false,
    message: menu.Note(80) = .{},
    /// Stats shows its advanced sheet, as D2's Advanced Stats.
    advanced: bool = false,

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
        self.mouse_panning = false;
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
        const visible = self.visibleRows();
        return @min(mathx.reveal(self.top, self.cursor, visible), self.count(v) -| visible);
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
        return !self.listed() or (i >= self.top and i < self.top + self.visibleRows());
    }
    pub fn enter(self: *Book, v: View) void {
        if (self.count(v) == 0) return;
        if (self.page == .passives) self.browse(progress.start(v.class));
    }
    fn selected(self: *const Book, v: View) ?items.Item {
        return switch (self.page) {
            .equipment => v.inventory.gear.slots.get(items.SLOTS[self.cursor]),
            .inventory => if (self.cursor < v.inventory.n) v.inventory.bag[self.cursor] else null,
            .nearby, .loot => if (self.cursor < v.nearby.len) v.nearby[self.cursor].item() else null,
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
        return if (self.direct()) .{ .x = DIRECT_W, .y = self.directActionY(v) + ACTION_H + menu.PANEL_PAD } else SIZE;
    }
    pub fn surface(self: *const Book, screen: P, v: View) menu.Surface {
        return if (self.direct()) menu.Surface.like(screen, self.size(v), SIZE) else menu.Surface.of(screen, SIZE);
    }
    fn directTop(self: *const Book) i32 {
        return if (self.page == .loot) HOLDING_Y + font.SMALL + DIRECT_GAP else CLOSE_Y + CLOSE_H + DIRECT_GAP;
    }
    fn cardTop(self: *const Book, v: View) i32 {
        return self.directTop() + @as(i32, @intCast(@min(self.count(v), self.visibleRows()))) * ROW + DIRECT_GAP;
    }
    fn visibleRows(self: *const Book) usize {
        return if (self.direct()) DIRECT_VISIBLE else VISIBLE;
    }
    /// The tallest card any listed item needs, so the panel keeps its size while the cursor moves.
    fn cardRoom(v: View) i32 {
        var most: i32 = 0;
        for (v.nearby) |n| if (n.item()) |it| {
            for (it.kind.slots()) |slot| most = @max(most, cardFoot(it, slot));
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
            if (self.page == .passives and b == input.TreeKeys.PAD_OVERVIEW) local.tree.reset = true else local.pressed.insert(b);
            local.click = false;
        };
        if (menu.closed(st)) return .close;
        if (self.page == .loot and self.count(v) > 0 and st.hit(menu.CHANGE)) return .take_all;
        if (!self.direct() and (st.hit(menu.PAGE_PREV) or st.hit(menu.PAGE_NEXT))) {
            self.choose(mathx.stepIn(Page, &PAGES, self.page, if (st.hit(menu.PAGE_PREV)) -1 else 1, 0));
            self.enter(v);
            return null;
        }
        if (self.page == .inventory and self.selected(v) != null) {
            if (st.hit(menu.REMOVE)) return .{ .drop = self.cursor };
            if (st.hit(menu.CHANGE)) self.destination_index = mathx.wrap(self.destination_index, 1, self.selected(v).?.kind.slots().len);
        }
        if (self.page == .skills and st.hit(menu.CHANGE)) return .{ .bindings = self.selectedSkill(v) };
        if (self.page == .stats and st.hit(menu.CHANGE)) self.advanced = !self.advanced;
        if (self.page == .passives) {
            if (!st.dragging) self.mouse_panning = false;
            if (st.middle_click) if (st.pointer) |p| {
                self.mouse_panning = trees.onCanvas(p);
            };
            if (self.mouse_panning) {
                const scale = self.surface(screen, v).scale;
                self.pan = trees.drag(self.treeView(), .{ .x = @as(f32, @floatFromInt(st.mouse_delta.x)) / scale, .y = @as(f32, @floatFromInt(st.mouse_delta.y)) / scale });
            }
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
        if (self.listed() and self.count(v) > 0) self.cursor = st.scrolled(self.cursor, self.count(v));
        if (st.click and !self.mouse_panning) if (st.pointer) |p| {
            if (!self.direct()) for (PAGES, 0..) |page, i| if (raster.holds(tabBox(i), p)) {
                self.choose(page);
                self.enter(v);
                return null;
            };
            for (0..self.count(v)) |i| {
                if (!self.inWindow(i)) continue;
                if (self.page == .passives and !trees.onCanvas(p)) continue;
                if (raster.holds(self.cellBox(i, v), p)) {
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
        if (!self.direct()) {
            if (raster.holds(raster.rect(LIST_X, TAB_Y, SHOULDER_W, TAB_H), p)) return menu.PAGE_PREV;
            if (raster.holds(raster.rect(W - LIST_X - SHOULDER_W, TAB_Y, SHOULDER_W, TAB_H), p)) return menu.PAGE_NEXT;
        }
        const shown = self.controls(v);
        for (shown.all[0..shown.n]) |c| if (raster.holds(c.box, p)) return c.button;
        return null;
    }
    /// Every button the page shows, the close button first.
    fn controls(self: *const Book, v: View) Controls {
        var c: Controls = .{};
        c.add(self.closeBox(v), menu.BACK, .{ .label = verbOf(.close) });
        switch (self.page) {
            .passives => {
                for ([_]bool{ false, true }) |increase| c.add(trees.zoomBox(increase), if (increase) menu.CHANGE else menu.REMOVE, .drawn);
                c.add(trees.overviewBox(), input.TreeKeys.PAD_OVERVIEW, .drawn);
                if (!v.growth.nodes.isSet(self.cursor)) c.add(trees.actionBox(), menu.CONFIRM, .{ .prompt = if (v.growth.canAllocate(self.cursor)) 1 else look.FADED_A });
            },
            .skills => {
                const act = self.selectedSkill(v);
                c.add(trees.bindBox(), menu.CHANGE, .{ .label = if (v.growth.unlocked(act)) verbOf(.bindings) else "Bindings" });
                c.add(trees.actionBox(), menu.CONFIRM, .{ .prompt = if (v.growth.canLearn(v.class, act)) 1 else look.FADED_A });
            },
            .stats => c.add(self.actionBox(menu.CHANGE, v), menu.CHANGE, .{ .label = if (self.advanced) "Main stats" else "Advanced" }),
            .equipment, .inventory, .nearby, .loot => if (self.count(v) > 0) {
                const it = self.selected(v) orelse {
                    c.add(self.actionBox(menu.CONFIRM, v), menu.CONFIRM, .{ .label = if (self.direct()) v.nearby[self.cursor].command().verb() else "Inventory" });
                    if (self.page == .loot) c.add(self.actionBox(menu.CHANGE, v), menu.CHANGE, .{ .label = verbOf(.take_all) });
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
        return raster.rect(x + i * (ACTION_W + menu.ACTION_GAP), if (self.direct()) self.directActionY(v) else ACTION_Y, ACTION_W, ACTION_H);
    }
    fn closeBox(self: *const Book, v: View) rl.Rectangle {
        return raster.rect(self.size(v).x - LIST_X - CLOSE_W, CLOSE_Y, CLOSE_W, CLOSE_H);
    }
    fn cellBox(self: *const Book, i: usize, v: View) rl.Rectangle {
        const y = TOP;
        return switch (self.page) {
            .equipment => blk: {
                const s = SLOT_BOX.get(items.SLOTS[i]);
                break :blk raster.rect(s.at.x, y + s.at.y, s.w, s.h);
            },
            .inventory, .nearby, .loot => raster.rect(LIST_X, (if (self.direct()) self.directTop() else y + LIST_Y) + (@as(i32, @intCast(i)) - @as(i32, @intCast(self.top))) * ROW, LIST_W, ROW),
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
            header(face, who.text());
            var xp: menu.Note(100) = .{};
            xp.say("Level  {d}     XP  {d} / {d}", .{ v.growth.level, v.growth.xp, v.growth.needed() });
            face.drawMiddle(xp.text(), RIGHT, HEADER_MID, font.SMALL, look.DIM);
            for (PAGES, 0..) |page, i| tab(face, tabBox(i), page, self.page == page, v.device);
            if (self.treePanel() == null) rl.drawLine(DIVIDER_X, TOP, DIVIDER_X, DIVIDER_FOOT, look.EDGE);
            if (self.treePanel()) |panel| {
                trees.draw(panel, face, sprites, v.class, v.growth, self.treeView(), v.device, .{ .stats = v.stats(), .gear = v.inventory.gear, .steady = v.steady }, on);
            } else if (self.page == .stats) {
                if (self.advanced) drawAdvanced(face, v) else drawStats(face, v);
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
            const prompt = prompt_icon.Prompt.menuOn(v.device, c.button);
            switch (c.shown) {
                .label => |label| menu.action(face, c.box, prompt, label),
                .prompt => |alpha| _ = menu.actionPrompt(face, c.box, prompt, alpha),
                .drawn => {},
            }
        }
        if (!self.direct()) {
            prompt_icon.Prompt.menuOn(v.device, menu.PAGE_PREV).draw(face, LIST_X + SHOULDER_W / 2, TAB_MID, font.BODY, 1);
            prompt_icon.Prompt.menuOn(v.device, menu.PAGE_NEXT).draw(face, W - LIST_X - SHOULDER_W / 2, TAB_MID, font.BODY, 1);
        }
    }

    fn drawDirect(self: *const Book, face: *const font.Face, v: View) void {
        header(face, if (self.page == .nearby) "NEARBY" else if (v.chest) "CHEST LOOT" else "ITEM BAG");
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
            itemCard(face, LIST_X, self.cardTop(v), LIST_W, it, slot, self.requirementAttrs(v, slot), if (v.chest) "IN THE CHEST" else "IN THE BAG");
        }
        const note_y = self.noteY(v);
        if (self.message.n > 0) face.draw(self.message.text(), LIST_X, note_y, font.SMALL, look.TEXT);
        const position = self.positionOf(v);
        face.draw(position.text(), DIRECT_W - LIST_X - face.width(position.text(), font.SMALL), note_y, font.SMALL, look.DIM);
    }

    fn positionOf(self: *const Book, v: View) menu.Note(50) {
        var out: menu.Note(50) = .{};
        out.say("{d} / {d}", .{ if (self.count(v) > 0) self.cursor + 1 else 0, self.count(v) });
        return out;
    }

    fn drawCells(self: *const Book, face: *const font.Face, v: View) void {
        if (self.page == .inventory) {
            const text_x = LIST_X + TEXT_X;
            face.draw("ITEM", text_x, TOP, font.SMALL, look.DIM);
            face.draw("SLOT", LIST_X + SECOND_X, TOP, font.SMALL, look.DIM);
            if (self.count(v) == 0) face.draw("Empty", text_x, TOP + EMPTY_DY, font.BODY, look.DIM);
            const position = self.positionOf(v);
            face.draw(position.text(), text_x, FOOT_Y, font.SMALL, look.DIM);
        }
        for (0..self.count(v)) |i| {
            var name_buf: [items.NAME_MAX]u8 = undefined;
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
                    const mid = raster.middleAt(r);
                    if (offhandWeapon(v.inventory.gear, slot)) |weapon| {
                        face.centred(BOTH_HANDS, mid.x, mid.y - PAIR_DY, font.SMALL, look.DIM);
                        face.centred(face.fit(&fitted, weapon.name(&name_buf), font.SMALL, inner, false), mid.x, mid.y + PAIR_DY, font.SMALL, look.DIM);
                    } else {
                        const name = if (it) |a| a.name(&name_buf) else "-";
                        face.centred(face.fit(&fitted, name, font.SMALL, inner, false), mid.x, mid.y + NAME_DY, font.SMALL, inkOf(it));
                    }
                },
                .inventory => {
                    const it = v.inventory.bag[i];
                    const slots = it.kind.slots();
                    listRow(face, x, y, it.name(&name_buf), look.itemInk(it.magical()), if (items.spec(it.kind).two_handed) BOTH_HANDS else if (slots.len > 1) menu.named(it.kind) else slots[0].name());
                },
                .nearby, .loot => {
                    const n = v.nearby[i];
                    listRow(face, x, y, n.label(&name_buf), inkOf(n.item()), n.command().verb());
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
        var name_buf: [items.NAME_MAX]u8 = undefined;
        const x = RIGHT;
        const y = TOP;
        if (self.count(v) == 0) return;
        const it = self.selected(v) orelse {
            if (self.page == .equipment) if (offhandWeapon(v.inventory.gear, items.SLOTS[self.cursor])) |weapon| {
                face.draw(BOTH_IN_USE, x, y, font.HEAD, look.TEXT);
                var held: menu.Note(128) = .{};
                held.say("{s} uses both hands. Equipping an offhand returns it to inventory.", .{weapon.name(&name_buf)});
                _ = face.paragraph(held.text(), x, y + HELD_NOTE_DY, DETAIL_W, font.SMALL, look.DIM);
                return;
            };
            face.draw(EMPTY_SLOT, x, y, font.HEAD, look.TEXT);
            return;
        };
        const slot = if (self.page == .equipment) items.SLOTS[self.cursor] else self.destination(v);
        const comparing = self.page == .inventory;
        itemCard(face, x, y, if (comparing) CARD_W else DETAIL_W, it, slot, self.requirementAttrs(v, slot), if (comparing) "SELECTED" else "EQUIPPED");
        if (comparing) itemCard(face, x + CARD_W + CARD_GAP, y, CARD_W, v.inventory.gear.slots.get(slot), slot, v.inventory.gear.statsWithout(slot, v.base), "EQUIPPED");
        if (comparing) {
            const equipped = v.inventory.gear.slots.get(slot);
            const at = y + @max(cardFoot(it, slot), if (equipped) |worn| cardFoot(worn, slot) else CARD_SLOT + font.SMALL) + CHANGES_GAP;
            if (v.inventory.preview(self.cursor, slot, v.base)) |after| {
                var below = drawChanges(face, x, at, v, after) + RETURNS_GAP;
                for (items.SLOTS) |s| {
                    if (s == slot or !v.inventory.displaced(after, slot, s)) continue;
                    var moved: menu.Note(100) = .{};
                    moved.say("Returns {s} to inventory.", .{v.inventory.gear.slots.get(s).?.name(&name_buf)});
                    face.draw(moved.text(), x, below, font.SMALL, look.DIM);
                    below += CHANGE_ROW;
                }
            } else |err| {
                var reason: menu.Note(140) = .{};
                if (err != error.Requirements) {
                    reason.say("{s}", .{items.caption(err)});
                } else if (dependent(v, self.cursor, slot)) |other| {
                    reason.say("Would leave {s} without its required attributes.", .{other.name(&name_buf)});
                } else reason.say("Cannot equip: requirements not met.", .{});
                _ = face.paragraph(reason.text(), x, at, DETAIL_W, font.SMALL, LOSS);
            }
        }
    }
};

const CONTROLS_MAX = 5;
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

fn header(face: *const font.Face, text: [:0]const u8) void {
    face.engraved(text, LIST_X, font.Face.topFor(HEADER_MID, font.HEAD), font.HEAD, look.TEXT);
}
fn listRow(face: *const font.Face, x: i32, y: i32, text: [:0]const u8, ink: rl.Color, second: [:0]const u8) void {
    const mid = y + ROW / 2;
    face.drawMiddle(text, x + TEXT_X, mid, font.BODY, ink);
    face.drawMiddle(second, x + SECOND_X, mid, font.SMALL, look.DIM);
}
fn tabBox(i: usize) rl.Rectangle {
    return raster.rect(TABS_X + @as(i32, @intCast(i)) * (TAB_W + TAB_GAP), TAB_Y, TAB_W, TAB_H);
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
    const m = raster.middleAt(r);
    const text = menu.named(page);
    const ink = if (on) look.TEXT else look.DIM;
    if (!device.pad()) {
        const prompt = prompt_icon.Prompt{ .key = page.shortcut().?.caption() };
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

const CARD_LINE = font.SMALL_LINE;
/// Down from a card's top: its rule, name (or "Empty slot"), slot, flavor and first stat line.
const CARD_RULE = 20;
const CARD_NAME = 32;
const CARD_EMPTY = 35;
const CARD_SLOT = 84;
const SLOT_STATS_GAP = 11;
const CARD_STATS = CARD_SLOT + font.LABEL + SLOT_STATS_GAP;
const FLAVOR_GAP = 12;
/// Above and below the modifiers' rule, and its inset from the card's sides.
const MODS_ABOVE = 6;
const MODS_BELOW = 10;
const MODS_INSET = 0;

const CardLine = union(enum) {
    damage: damage.Base,
    unarmed,
    armour: i16,
    innate: items.Innate,
    bleed_damage: i32,
    requires: struct { at: attr.Attr, n: i32, available: i32, met: bool },

    fn text(l: CardLine, out: *menu.Note(120)) [:0]const u8 {
        switch (l) {
            .damage => |hit| out.say(damage.PHYSICAL_FMT, .{ hit.lo, hit.hi }),
            .unarmed => return "No weapon damage",
            .armour => |n| out.say("{d}% " ++ attr.REDUCTION_LABEL, .{n}),
            .innate => |innate| {
                out.clear();
                innate.write(out.writer());
            },
            .bleed_damage => |n| out.say("Bleed: {d}/turn, {d} when moving", .{ n, n * bleeding.MOVE_FACTOR }),
            .requires => |r| if (r.met) out.say("Requires {d} {s}", .{ r.n, menu.named(r.at) }) else out.say("Requires {d} {s} ({d} available)", .{ r.n, menu.named(r.at), r.available }),
        }
        return out.text();
    }

    fn size(l: CardLine) i32 {
        return switch (l) {
            .requires, .bleed_damage, .unarmed => font.LABEL,
            .damage, .armour, .innate => font.SMALL,
        };
    }

    fn ink(l: CardLine) rl.Color {
        return switch (l) {
            .damage, .armour, .innate, .bleed_damage => look.TEXT,
            .unarmed => look.DIM,
            .requires => |r| if (r.met) look.DIM else LOSS,
        };
    }
};

const CardLines = struct {
    all: [4 + attr.ATTRS.len]CardLine = undefined,
    n: usize = 0,

    fn add(self: *CardLines, l: CardLine) void {
        self.all[self.n] = l;
        self.n += 1;
    }

    /// `spec`'s lines for `slot`; with no `available`, every requirement is unmet by one, the most and widest lines it can have.
    fn of(spec: items.Spec, slot: items.Slot, available: ?attr.Attrs) CardLines {
        var out: CardLines = .{};
        if (spec.damage) |hit| {
            out.add(.{ .damage = hit });
        } else if (slot == .right_hand) out.add(.unarmed);
        if (spec.armour > 0) out.add(.{ .armour = spec.armour });
        if (spec.innate) |innate| {
            out.add(.{ .innate = innate });
            if (innate == .bleed) out.add(.{ .bleed_damage = innate.bleed.damage });
        }
        inline for (attr.ATTRS) |at| {
            const required = @field(spec.needs, @tagName(at));
            if (required > 0) {
                const met = if (available) |a| a.get(at) >= required else false;
                out.add(.{ .requires = .{ .at = at, .n = required, .met = met, .available = if (available) |a| a.get(at) else required - 1 } });
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
    return CARD_STATS + n * CARD_LINE + (if (m > 0) MODS_ABOVE + MODS_BELOW + m * CARD_LINE else 0) + FLAVOR_GAP + font.LABEL;
}

fn cardFoot(it: items.Item, slot: items.Slot) i32 {
    var mods: usize = 0;
    if (it.magical()) for (items.MODS) |m| {
        if (it.value(m) != 0) mods += 1;
    };
    return footOf(CardLines.of(items.spec(it.kind), slot, null).n, mods);
}

comptime {
    const mods = items.AFFIXES_MAX;
    for (std.enums.values(items.Kind)) |k| {
        const s = items.spec(k);
        for (s.slots) |slot| {
            if (footOf(CardLines.of(s, slot, null).n, mods) > CARD_H) @compileError(s.name ++ "'s card can run past CARD_H");
        }
    }
}

fn itemCard(face: *const font.Face, x: i32, y: i32, width: i32, maybe: ?items.Item, slot: items.Slot, available: attr.Attrs, caption: [:0]const u8) void {
    face.draw(caption, x, y, font.LABEL, look.DIM);
    rl.drawLine(x, y + CARD_RULE, x + width, y + CARD_RULE, look.EDGE);
    const it = maybe orelse {
        face.draw(EMPTY_SLOT, x, y + CARD_EMPTY, font.BODY, look.DIM);
        face.draw(slot.name(), x, y + CARD_SLOT, font.LABEL, look.DIM);
        return;
    };
    const spec = items.spec(it.kind);
    const ink = look.itemInk(it.magical());
    var fitted: [64]u8 = undefined;
    var name_buf: [items.NAME_MAX]u8 = undefined;
    _ = face.paragraph(it.name(&name_buf), x, y + CARD_NAME, width, font.BODY, ink);
    var metadata: menu.Note(100) = .{};
    const slot_name = if (slot == .right_hand) (if (spec.two_handed) TWO_HANDED else ONE_HANDED) else slot.name();
    if (spec.damage != null) metadata.say("{s}  /  {s}", .{ slot_name, menu.named(spec.style.attr()) }) else metadata.say("{s}", .{slot_name});
    face.draw(metadata.text(), x, y + CARD_SLOT, font.LABEL, look.DIM);
    var top = y + CARD_STATS;
    var line: menu.Note(120) = .{};
    const stats = CardLines.of(spec, slot, available);
    for (stats.lines()) |l| {
        face.draw(l.text(&line), x, top, l.size(), l.ink());
        top += CARD_LINE;
    }
    if (it.magical()) {
        top += MODS_ABOVE;
        rl.drawLine(x + MODS_INSET, top, x + width - MODS_INSET, top, look.EDGE);
        top += MODS_BELOW;
        for (items.MODS) |m| {
            const n = it.value(m);
            if (n == 0) continue;
            line.clear();
            for (it.mods) |rolled| if (rolled) |a| { if (a.kind == m) a.write(line.writer()); };
            face.draw(line.text(), x, top, font.SMALL, look.MAGIC);
            top += CARD_LINE;
        }
    }
    face.draw(face.fit(&fitted, it.flavor(), font.LABEL, width, false), x, top + FLAVOR_GAP, font.LABEL, look.DIM);
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

const CHANGE_ROW = font.SMALL_TIGHT;
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
    weapon_crit,
    spell_crit,
    physical,
    element: damage.Element,
    dodge,
    style: attr.Style,

    fn of(m: Measure, a: attr.Attrs) i32 {
        return switch (m) {
            .life => a.life(),
            .mana => a.mana(),
            .attribute => |at| a.get(at),
            .reduction => a.reduction(),
            .weapon_crit => @intCast(a.critWith(a.weapon_crit_bonus)),
            .spell_crit => @intCast(a.critWith(a.spell_crit_bonus)),
            .physical => a.physical_bonus,
            .element => |e| a.element_bonus.get(e),
            .dodge => @intCast(a.dodge()),
            .style => |s| a.increase(s),
        };
    }

    fn percent(m: Measure) bool {
        return switch (m) {
            .life, .mana, .attribute => false,
            .reduction, .weapon_crit, .spell_crit, .physical, .element, .dodge, .style => true,
        };
    }

    /// Its Stats page row.
    fn title(m: Measure) [:0]const u8 {
        return switch (m) {
            .life => comptime menu.capital(attr.Bonus.life.label()),
            .mana => comptime menu.capital(attr.Bonus.mana.label()),
            .attribute => |at| menu.named(at),
            .reduction => comptime menu.capital(attr.REDUCTION_LABEL),
            .weapon_crit => comptime menu.capital(attr.WEAPON_CRIT_LABEL),
            .spell_crit => comptime menu.capital(attr.SPELL_CRIT_LABEL),
            .physical => comptime menu.capital(attr.PHYSICAL_LABEL) ++ " bonus",
            .element => |e| switch (e) {
                inline else => |t| comptime menu.named(t) ++ " damage bonus",
            },
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
            .weapon_crit => attr.WEAPON_CRIT_LABEL,
            .spell_crit => attr.SPELL_CRIT_LABEL,
            .physical => attr.PHYSICAL_LABEL,
            .element => |e| switch (e) {
                inline else => |t| comptime menu.word(t) ++ " damage",
            },
            .dodge => "dodge chance",
            .style => |s| damageLabel(s),
        };
    }
};
/// Every line `drawChanges` can list, in order.
const CHANGE_ROWS = blk: {
    var rows: []const Measure = &.{ .life, .mana };
    for (attr.ATTRS) |at| rows = rows ++ &[_]Measure{.{ .attribute = at }};
    rows = rows ++ &[_]Measure{ .reduction, .weapon_crit, .spell_crit, .dodge };
    for (attr.STYLES) |s| rows = rows ++ &[_]Measure{.{ .style = s }};
    rows = rows ++ &[_]Measure{.physical};
    for (std.enums.values(damage.Element)) |e| rows = rows ++ &[_]Measure{.{ .element = e }};
    break :blk rows[0..rows.len].*;
};

/// The foot of the change list.
fn drawChanges(face: *const font.Face, x: i32, y: i32, v: View, after: items.Gear) i32 {
    face.draw("IF EQUIPPED", x, y, font.SMALL, look.DIM);
    var n: usize = 0;
    const top = y + CARD_LINE;
    const was = v.stats();
    const now = after.stats(v.base);
    for (CHANGE_ROWS) |m| change(face, x, top, &n, m.label(), m.of(was), m.of(now), m.percent());
    const recovery = PerkChanges.of(v.inventory.gear, after, v.growth.perks());
    inline for (std.meta.fields(progress.passives.Perks)) |f| {
        const delta = @field(recovery.delta, f.name);
        change(face, x, top, &n, PerkChanges.label(f.name), 0, delta, PerkChanges.percent(f.name));
    }
    for (std.enums.values(damage.Element)) |e| change(face, x, top, &n, resistanceLabel(e), was.resists.get(e), now.resists.get(e), true);
    inline for (.{ attr.Attack.melee, attr.Attack.ranged }) |attack| {
        change(face, x, top, &n, if (attack == .melee) "melee penetration" else "ranged penetration", v.inventory.gear.onHit(attack).penetration, after.onHit(attack).penetration, true);
    }
    if (n == 0) {
        face.draw("No attribute, defense or recovery changes.", x, top, font.SMALL, look.DIM);
        return top + CHANGE_ROW;
    }
    return top + changeRows(n) * CHANGE_ROW;
}

const PerkChanges = struct {
    delta: progress.passives.Perks,

    fn of(before: items.Gear, after: items.Gear, base: progress.passives.Perks) PerkChanges {
        const was = before.perks(base);
        const now = after.perks(base);
        var delta: progress.passives.Perks = undefined;
        inline for (std.meta.fields(progress.passives.Perks)) |f| {
            @field(delta, f.name) = if (comptime std.mem.eql(u8, f.name, "mana_regen")) hero.manaRegen(now) - hero.manaRegen(was) else @field(now, f.name) - @field(was, f.name);
        }
        return .{ .delta = delta };
    }

    fn label(comptime name: []const u8) [:0]const u8 {
        return switch (@field(std.meta.FieldEnum(progress.passives.Perks), name)) {
            .mana_regen => std.fmt.comptimePrint("mana / {d} turns", .{hero.MANA_REGEN_TURNS}),
            .life_on_hit => "life on hit",
            .life_on_kill => "life on kill",
            .life_flask => "life flask recovery",
            .cull => "cull threshold",
            .mana_cost => "mana cost reduction",
        };
    }

    fn percent(comptime name: []const u8) bool {
        return switch (@field(std.meta.FieldEnum(progress.passives.Perks), name)) {
            .mana_regen, .life_on_hit, .life_on_kill => false,
            .life_flask, .cull, .mana_cost => true,
        };
    }
};

fn inkOf(it: ?items.Item) rl.Color {
    return look.itemInk(if (it) |i| i.magical() else false);
}

fn damageLabel(s: attr.Style) [:0]const u8 {
    return switch (s) {
        inline else => |t| comptime menu.word(t) ++ " damage bonus",
    };
}

const STAT_W = 440;
const STATS_X = 40;
/// A section's title to its rule and to its first row, and row to row.
const SECTION_RULE = 22;
const SECTION_ROWS = 32;
const STAT_ROW = font.BODY_LINE;
const HEADLINE = font.HEAD + 4;
const HEADLINE_ROW = HEADLINE + 8;
const CHANCE_ROW = font.LABEL + 3;
const NOTE_DY = 7;
const SECTION_GAP = 14;
const CRIT_GAP = 20;
/// Between a row's label and its value, at the least.
const ROW_GAP = 16;
/// Between one skill's chances to afflict.
const CHANCE_GAP = 18;
/// The lowest a column may reach: the right one stops above the actions.
const LEFT_FOOT = FOOT_Y;
const RIGHT_FOOT = ACTION_Y - SECTION_GAP;

/// The sheet's type, fanciest first: what the player came to read, then what builds it, then the rest.
const Tier = enum {
    headline,
    key,
    plain,

    fn size(t: Tier) i32 {
        return switch (t) {
            .headline => HEADLINE,
            .key => font.BODY,
            .plain => font.SMALL,
        };
    }

    fn step(t: Tier) i32 {
        return if (t == .headline) HEADLINE_ROW else STAT_ROW;
    }

    /// The display face engraved for the first two, the data face for the rest.
    fn put(t: Tier, face: *const font.Face, s: [:0]const u8, x: i32, y: i32, col: rl.Color) void {
        if (t == .plain) face.draw(s, x, y, t.size(), col) else face.engraved(s, x, y, t.size(), col);
    }

    fn label(t: Tier) Tier {
        return if (t == .headline) .key else t;
    }

    /// Its label beside its value shares their baseline.
    fn labelDrop(t: Tier) i32 {
        return @divTrunc((t.size() - t.label().size()) * 3, 4);
    }
};

/// Nothing to read in a zero, so it recedes.
fn quiet(n: i32, col: rl.Color) rl.Color {
    return if (n == 0) look.DIM else if (n < 0) LOSS else col;
}

fn noLine(_: *const font.Face, _: [:0]const u8, _: i32, _: i32, _: i32, _: rl.Color) void {}

/// One column of the sheet, top down; `dry` lays it out without drawing to check it fits.
const Column = struct {
    face: *const font.Face,
    x: i32,
    y: i32 = TOP,
    dry: bool = false,
    cramped: bool = false,

    fn heading(c: *Column, title: [:0]const u8) void {
        if (!c.dry) {
            c.face.draw(title, c.x, c.y, font.SMALL, look.UI_FOCUS);
            rl.drawLine(c.x, c.y + SECTION_RULE, c.x + STAT_W, c.y + SECTION_RULE, look.EDGE);
        }
        c.y += SECTION_ROWS;
    }

    fn fits(c: *Column, w: i32) void {
        if (w > STAT_W) c.cramped = true;
    }

    fn entry(c: *Column, label: [:0]const u8, value: [:0]const u8, tier: Tier, col: rl.Color) void {
        c.fits(c.face.width(label, tier.label().size()) + ROW_GAP + c.face.width(value, tier.size()));
        if (!c.dry) {
            tier.label().put(c.face, label, c.x, c.y + tier.labelDrop(), look.TEXT);
            tier.put(c.face, value, c.x + STAT_W - c.face.width(value, tier.size()), c.y, col);
        }
        c.y += tier.step();
    }

    fn stat(c: *Column, m: Measure, a: attr.Attrs, tier: Tier, col: rl.Color) void {
        var text: menu.Note(48) = .{};
        text.say("{s}{d}{s}", .{ if (m == .style) "+" else "", m.of(a), if (m.percent()) "%" else "" });
        c.entry(m.title(), text.text(), tier, col);
    }

    fn vital(c: *Column, label: [:0]const u8, v: Vital, col: rl.Color) void {
        var text: menu.Note(32) = .{};
        text.say("{d} / {d}", .{ v.now, v.max });
        c.entry(label, text.text(), .headline, col);
    }

    fn note(c: *Column, s: []const u8, size: i32, col: rl.Color) void {
        c.y = if (c.dry) c.face.paragraphWith(noLine, s, c.x, c.y, STAT_W, size, col) else c.face.paragraph(s, c.x, c.y, STAT_W, size, col);
    }

    /// A skill's name, then its hit coloured part by part, then what it may afflict.
    fn skill(c: *Column, act: skillbar.Act, hit: progress.Hit, effect: items.WeaponEffect) void {
        var physical: menu.Note(24) = .{};
        var element: menu.Note(40) = .{};
        if (hit.physical.hi > 0) physical.say("{d}-{d}", .{ hit.physical.lo, hit.physical.hi });
        if (hit.element) |e| element.say("{d}-{d} {s}", .{ e.lo, e.hi, menu.word(act.element().?) });
        const join: [:0]const u8 = if (physical.n > 0 and element.n > 0) " + " else "";
        const parts = [_]struct { [:0]const u8, rl.Color }{
            .{ physical.text(), look.PHYSICAL },
            .{ join, look.DIM },
            .{ element.text(), look.arrowInk(act) },
        };
        const tier = Tier.key;
        var w: i32 = 0;
        for (parts) |p| w += c.face.width(p[0], tier.size());
        c.fits(c.face.width(act.name(), tier.label().size()) + ROW_GAP + w);
        if (!c.dry) {
            tier.label().put(c.face, act.name(), c.x, c.y + tier.labelDrop(), look.TEXT);
            var at = c.x + STAT_W - w;
            for (parts) |p| {
                tier.put(c.face, p[0], at, c.y, p[1]);
                at += c.face.width(p[0], tier.size());
            }
        }
        c.y += tier.step();
        const chances = chancesOf(act, hit, effect);
        var any = false;
        var at = c.x;
        for (std.enums.values(resilience.Kind)) |k| {
            const pc = chances.get(k);
            if (pc == 0) continue;
            any = true;
            var text: menu.Note(32) = .{};
            text.say("{d}% {s}", .{ pc, menu.word(k) });
            if (!c.dry) c.face.draw(text.text(), at, c.y, font.LABEL, look.ailmentInk(k));
            at += c.face.width(text.text(), font.LABEL) + CHANCE_GAP;
        }
        if (!any) return;
        c.fits(at - CHANCE_GAP - c.x);
        c.y += CHANCE_ROW;
    }
};

/// Each ailment a hit may bring, the skill's own roll first and the weapon's only if that missed, as combat rolls them.
fn chancesOf(act: skillbar.Act, hit: progress.Hit, effect: items.WeaponEffect) std.EnumArray(resilience.Kind, u32) {
    var out = std.EnumArray(resilience.Kind, u32).initFill(0);
    if (act.ailment()) |ail| out.set(ail.kind, ail.chance);
    if (hit.physical.hi > 0) {
        for (std.enums.values(resilience.Kind)) |k| {
            const skill = out.get(k);
            out.set(k, skill + ((mathx.PERCENT - skill) * effect.chance(k) + mathx.PERCENT / 2) / mathx.PERCENT);
        }
    }
    return out;
}

fn attributeNote(at: attr.Attr) [:0]const u8 {
    return switch (at) {
        .strength => "Life and heavy weapon damage",
        .dexterity => "Light weapons, critical chance and dodge",
        .intelligence => "Mana and spell damage",
    };
}

const DEFENCES = [_]Measure{ .reduction, .dodge };
const CRITS = [_]Measure{ .weapon_crit, .spell_crit };

/// What the player reads at a glance: life, mana and each skill's hit, then what builds them.
fn sheet(face: *const font.Face, v: View, dry: bool) [2]Column {
    const a = v.stats();
    var left = Column{ .face = face, .x = STATS_X, .dry = dry };
    left.heading("SURVIVAL");
    left.vital(hud.LIFE, v.life, look.LIFE_TEXT);
    left.vital(hud.MANA, v.mana, look.MANA_TEXT);
    for (DEFENCES) |m| left.stat(m, a, .plain, look.TEXT);
    left.y += NOTE_DY;
    var note: menu.Note(100) = .{};
    note.say("Physical reduction is capped at {d}%.", .{attr.ARMOUR_MAX});
    left.note(note.text(), font.SMALL, look.DIM);
    left.y += SECTION_GAP;
    left.heading("ATTRIBUTES");
    for (attr.ATTRS) |at| {
        left.stat(.{ .attribute = at }, a, .key, look.TEXT);
        left.note(attributeNote(at), font.LABEL, look.DIM);
    }
    left.y += SECTION_GAP;
    left.heading("PROGRESSION");
    note.say("{d} passive, {d} skill", .{ v.growth.passive_points, v.growth.active_points });
    left.entry("Unspent points", note.text(), .plain, quiet(@as(i32, v.growth.passive_points) + v.growth.active_points, look.UI_FOCUS));
    var gold: menu.Note(24) = .{};
    gold.say("{d}", .{v.gold});
    left.entry("Gold", gold.text(), .plain, look.LEVEL_GOLD);

    var right = Column{ .face = face, .x = RIGHT, .dry = dry };
    right.heading("DAMAGE");
    for (skillbar.kit(v.class)) |act| if (act.attack() != null and v.growth.unlocked(act)) {
        right.skill(act, v.growth.preparedHit(a, v.inventory.gear, act, v.steady).?, v.inventory.gear.onHit(act.attack().?));
    };
    right.y += NOTE_DY;
    right.note("Per hit, before critical hits, defenses and resistances.", font.SMALL, look.DIM);
    right.y += CRIT_GAP;
    for (CRITS) |m| right.stat(m, a, .plain, look.TEXT);
    return .{ left, right };
}

/// D2's Advanced Stats: every bonus, recovery and resistance, zeros included.
fn advancedSheet(face: *const font.Face, v: View, dry: bool) [2]Column {
    const a = v.stats();
    var left = Column{ .face = face, .x = STATS_X, .dry = dry };
    left.heading("DAMAGE BONUSES");
    for (attr.STYLES) |s| left.stat(.{ .style = s }, a, .plain, quiet(a.increase(s), look.TEXT));
    left.stat(.physical, a, .plain, quiet(a.physical_bonus, look.PHYSICAL));
    for (std.enums.values(damage.Element)) |e| left.stat(.{ .element = e }, a, .plain, quiet(a.element_bonus.get(e), look.elementInk(e)));
    var text: menu.Note(48) = .{};
    text.say("{d}%", .{attr.CRIT_MULTI});
    left.entry("Critical damage multiplier", text.text(), .plain, look.TEXT);
    left.y += SECTION_GAP;
    left.heading("RECOVERY");
    const perks = v.inventory.gear.perks(v.growth.perks());
    text.say("{d} / {d} turns", .{ hero.manaRegen(perks), hero.MANA_REGEN_TURNS });
    left.entry("Mana recovery", text.text(), .plain, look.MANA_TEXT);
    text.say("{d}", .{perks.life_on_hit});
    left.entry("Life on hit", text.text(), .plain, quiet(perks.life_on_hit, look.LIFE_TEXT));
    text.say("{d}", .{perks.life_on_kill});
    left.entry("Life on kill", text.text(), .plain, quiet(perks.life_on_kill, look.LIFE_TEXT));
    text.say("+{d}%", .{perks.life_flask});
    left.entry("Life flask recovery", text.text(), .plain, quiet(perks.life_flask, look.LIFE_TEXT));

    var right = Column{ .face = face, .x = RIGHT, .dry = dry };
    right.heading("RESISTANCES");
    for (std.enums.values(damage.Element)) |e| {
        const n = v.resists.get(e);
        text.say("{d}%", .{n});
        right.entry(resistanceLabel(e), text.text(), .plain, quiet(n, look.elementInk(e)));
    }
    right.y += SECTION_GAP;
    right.heading("STATUS RESISTANCE");
    for (std.enums.values(resilience.Kind)) |k| {
        const m = v.status_resist.get(k);
        if (m.turns > 0) text.say("{d}%, {d} turn{s}", .{ m.percent, m.turns, mathx.plural(m.turns) }) else text.say("{d}%", .{m.percent});
        right.entry(resistanceLabel(k), text.text(), .plain, quiet(m.percent, look.ailmentInk(k)));
    }
    right.y += NOTE_DY;
    right.note(resilience.ABOUT, font.SMALL, look.DIM);
    return .{ left, right };
}

fn resistanceLabel(e: anytype) [:0]const u8 {
    return switch (e) {
        inline else => |t| comptime menu.named(t) ++ " resistance",
    };
}

fn drawStats(face: *const font.Face, v: View) void {
    _ = sheet(face, v, false);
}

fn drawAdvanced(face: *const font.Face, v: View) void {
    _ = advancedSheet(face, v, false);
}

/// Every class with every skill learned keeps both sheets' rows inside their columns and above the actions.
pub fn verifyStats(face: *const font.Face) !void {
    var checked: usize = 0;
    for (hero.CLASSES) |class| {
        var growth = progress.State.of(class);
        for (progress.skills(class)) |s| growth.ranks.set(s.act, progress.RANKS);
        var inv = items.Inventory{};
        inv.gear.slots.set(.right_hand, .{ .kind = .axe });
        var v = testView(&inv, &growth);
        v.class = class;
        v.base = growth.attributes(class);
        v.life = .{ .now = 999, .max = 999 };
        v.mana = .{ .now = 999, .max = 999 };
        for (std.enums.values(resilience.Kind)) |k| v.status_resist.set(k, .{ .percent = 100, .turns = resilience.EXPIRY });
        for ([_][2]Column{ sheet(face, v, true), advancedSheet(face, v, true) }) |cols| {
            for (cols, [_]i32{ LEFT_FOOT, RIGHT_FOOT }) |col, foot| {
                if (col.cramped or col.y > foot) {
                    std.debug.print("stats overflow {s}: column at x {d} reaches {d} of {d}, cramped {}\n", .{ @tagName(class), col.x, col.y, foot, col.cramped });
                    return error.StatsOverflow;
                }
                checked += 1;
            }
        }
    }
    std.debug.print("stats typography: {d} columns fit, main and advanced, every class fully learned\n", .{checked});
}

pub fn verifyCards(face: *const font.Face) !void {
    var count: usize = 0;
    var text: menu.Note(120) = .{};
    for (std.enums.values(items.Kind)) |kind| {
        const spec = items.spec(kind);
        if (face.width(spec.flavor, font.LABEL) > CARD_W) {
            std.debug.print("card overflow {s}: {s}\n", .{ spec.name, spec.flavor });
            return error.ItemCardOverflow;
        }
        count += 1;
        for (spec.slots) |slot| {
            const rows = CardLines.of(spec, slot, null);
            for (rows.lines()) |line| {
                const value = line.text(&text);
                if (face.width(value, line.size()) > CARD_W) {
                    std.debug.print("card overflow {s}: {s}\n", .{ spec.name, value });
                    return error.ItemCardOverflow;
                }
                count += 1;
            }
        }
    }
    std.debug.print("item typography: {d} flavor, property and requirement rows fit {d}px comparison cards\n", .{ count, CARD_W });
}

fn testView(inv: *const items.Inventory, growth: *const progress.State) View {
    return .{ .class = .archer, .name = "Test", .inventory = inv, .growth = growth, .base = growth.attributes(.archer) };
}

test "character actions need one press and tabs are directly reachable" {
    var inv = items.Inventory{};
    try std.testing.expect(inv.add(.{ .kind = .cap }));
    var growth = progress.State.of(.archer);
    const v = testView(&inv, &growth);
    var book = Book{ .page = .inventory };
    const screen = display.WINDOW;
    const confirm = input.State{ .pressed = .initOne(menu.CONFIRM) };
    try std.testing.expect(book.step(&confirm, screen, v).? == .equip);
    try std.testing.expectEqual(@as(usize, 1), inv.n);
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.REMOVE) }, screen, v).? == .drop);
    _ = book.step(&.{ .pressed = .initOne(menu.PAGE_NEXT) }, screen, v);
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

test "stats change between main and advanced by button and by click, and back still closes" {
    const inv = items.Inventory{};
    const growth = progress.State.of(.wizard);
    const v = testView(&inv, &growth);
    var book = Book{ .page = .stats };
    const screen = display.WINDOW;
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.CHANGE) }, screen, v) == null);
    try std.testing.expect(book.advanced);
    const box = book.actionBox(menu.CHANGE, v);
    const p = book.surface(screen, v).screenOf(.{ .x = box.x + 20, .y = box.y + 20 });
    _ = book.step(&.{ .click = true, .pointer = p }, screen, v);
    try std.testing.expect(!book.advanced);
    book.advanced = true;
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.BACK) }, screen, v).? == .close);
    std.debug.print("stats: change and a click on its button toggle the advanced sheet; back closes from it\n", .{});
}

test "a skill's status chances combine its own roll with the weapon's second roll" {
    const bash = chancesOf(.shield_bash, .{ .physical = .{ .lo = 1, .hi = 2 }, .element = null, .style = .heavy }, .{ .stun = 20, .bleed = 10 });
    try std.testing.expectEqual(@as(u32, 60), bash.get(.stun));
    try std.testing.expectEqual(@as(u32, 10), bash.get(.bleed));
    const spark = chancesOf(.spark, .{ .physical = .{ .lo = 0, .hi = 0 }, .element = .{ .lo = 1, .hi = 3 }, .style = .spell }, .{ .stun = 20 });
    try std.testing.expectEqual(@as(u32, 50), spark.get(.stun));
    std.debug.print("status chances: bash 50% + mace 20% = {d}% stun; pure lightning ignores the weapon at {d}%\n", .{ bash.get(.stun), spark.get(.stun) });
}

test "loot exposes single pickup and take all through controller and mouse controls" {
    const inv = items.Inventory{};
    const growth = progress.State.of(.archer);
    var v = testView(&inv, &growth);
    v.nearby = &.{.{ .loot = .{ .index = 7, .item = .{ .kind = .cap } } }};
    var book = Book{ .page = .loot };
    const screen = display.SCREEN_720;
    const one = book.step(&.{ .pressed = .initOne(menu.CONFIRM) }, screen, v).?;
    try std.testing.expectEqual(@as(usize, 7), one.pickup);
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.CHANGE) }, screen, v).? == .take_all);
    const surface = book.surface(screen, v);
    const box = book.actionBox(menu.CHANGE, v);
    const p = surface.screenOf(.{ .x = box.x + 20, .y = box.y + 20 });
    try std.testing.expect(book.step(&.{ .click = true, .pointer = p }, screen, v).? == .take_all);
    const panel = book.size(v);
    try std.testing.expect(panel.x < SIZE.x and panel.y < SIZE.y);
    try std.testing.expectEqual(@as(f32, @floatFromInt(panel.y - ACTION_H - menu.PANEL_PAD)), book.actionBox(menu.CONFIRM, v).y);
    std.debug.print("loot panel: {d}x{d} for one item, Book {d}x{d}\n", .{ panel.x, panel.y, SIZE.x, SIZE.y });
    _ = book.step(&.{ .pressed = .initOne(menu.PAGE_NEXT) }, screen, v);
    try std.testing.expectEqual(Page.loot, book.page);
    const at = P{ .x = 20, .y = 20 };
    v.nearby = &.{.{ .gold = .{ .at = at, .amount = 37 } }};
    try std.testing.expectEqual(at, book.step(&.{ .pressed = .initOne(menu.CONFIRM) }, screen, v).?.take_gold);
    var label: [80]u8 = undefined;
    try std.testing.expectEqualStrings("37 gold", v.nearby[0].label(&label));
    const gold_box = book.actionBox(menu.CHANGE, v);
    const gold_p = book.surface(screen, v).screenOf(.{ .x = gold_box.x + 20, .y = gold_box.y + 20 });
    try std.testing.expect(book.step(&.{ .click = true, .pointer = gold_p }, screen, v).? == .take_all);
    std.debug.print("loot controls: item and gold pickup, take-all press and scaled mouse hit on both row types, no character tabs\n", .{});
}

test "the inventory list scrolls back when the bag shrinks" {
    var inv = items.Inventory{};
    for (0..VISIBLE + 6) |_| try std.testing.expect(inv.add(.{ .kind = .cap }));
    var growth = progress.State.of(.archer);
    const v = testView(&inv, &growth);
    const screen = display.WINDOW;
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
    var v = testView(&inv, &growth);
    v.base = base;
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
    ground.nearby = &.{.{ .loot = .{ .index = 0, .item = .{ .kind = .axe, .mods = .{ null, null } } } }};
    book.choose(.loot);
    try std.testing.expectEqual(@as(i32, 20), book.requirementAttrs(ground, .right_hand).get(.strength));
    std.debug.print("item cards: 2-hand displacement, self-funding, both ring destinations and ground items; inventory unchanged\n", .{});
}

test "equipment comparisons show recovery gains and displaced offhand losses without changing inventory" {
    const base = attr.Attrs.of(.{ .strength = 40, .dexterity = 40, .intelligence = 40 });
    const perks = progress.passives.Perks{ .mana_regen = 3, .life_on_kill = 4, .life_flask = 30, .life_on_hit = 2, .cull = 5, .mana_cost = 8 };
    const cases = [_]struct { kind: items.Kind, slot: items.Slot, expected: progress.passives.Perks }{
        .{ .kind = .circlet, .slot = .helm, .expected = .{ .mana_regen = 1 } },
        .{ .kind = .totem, .slot = .left_hand, .expected = .{ .life_on_kill = 1 } },
        .{ .kind = .flask_belt, .slot = .belt, .expected = .{ .life_flask = 20 } },
    };
    for (cases) |case| {
        var inv = items.Inventory{};
        try std.testing.expect(inv.add(.{ .kind = case.kind }));
        const original = inv;
        const after = try inv.preview(0, case.slot, base);
        try std.testing.expectEqualDeep(case.expected, PerkChanges.of(inv.gear, after, perks).delta);
        try std.testing.expectEqualDeep(progress.passives.Perks{}, PerkChanges.of(after, after, perks).delta);
        try std.testing.expectEqual(original.n, inv.n);
        try std.testing.expectEqualDeep(original.gear, inv.gear);
        try std.testing.expectEqualDeep(original.bag[0..original.n], inv.bag[0..inv.n]);
    }
    var inv = items.Inventory{};
    inv.gear.slots.set(.left_hand, .{ .kind = .totem });
    inv.gear.slots.set(.helm, .{ .kind = .circlet });
    inv.gear.slots.set(.belt, .{ .kind = .flask_belt });
    try std.testing.expect(inv.add(.{ .kind = .bow }));
    const original = inv;
    const after = try inv.preview(0, .right_hand, base);
    try std.testing.expect(after.slots.get(.left_hand) == null);
    try std.testing.expectEqualDeep(progress.passives.Perks{ .life_on_kill = -1 }, PerkChanges.of(inv.gear, after, perks).delta);
    try std.testing.expectEqual(original.n, inv.n);
    try std.testing.expectEqualDeep(original.gear, inv.gear);
    try std.testing.expectEqualDeep(original.bag[0..original.n], inv.bag[0..inv.n]);
    try std.testing.expectEqualStrings("mana / 5 turns", PerkChanges.label("mana_regen"));
    try std.testing.expect(!PerkChanges.percent("mana_regen") and !PerkChanges.percent("life_on_kill") and PerkChanges.percent("life_flask"));
    std.debug.print("equipment recovery comparison: {d} gains, {d} unchanged previews and a two-handed offhand loss; passive perks retained and inventory unchanged\n", .{ cases.len, cases.len });
}

test "tree browsing is free and point actions issue one command" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    growth.passive_points = 2;
    growth.active_points = 2;
    const v = testView(&inv, &growth);
    const screen = display.SCREEN_720;
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

test "mouse character browsing and passive dragging preserve points and scaled hit targets" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    growth.active_points = 2;
    growth.passive_points = 2;
    const v = testView(&inv, &growth);
    var checked: usize = 0;
    for ([_]P{ display.SCREEN_720, display.SCREEN_1440 }) |screen| {
        var book = Book{ .page = .skills };
        const surface = book.surface(screen, v);
        const p = surface.screenOf(raster.middle(book.cellBox(1, v)));
        try std.testing.expect(book.step(&.{ .pointer = p, .click = true }, screen, v) == null);
        try std.testing.expectEqual(@as(usize, 1), book.cursor);
        _ = book.step(&.{ .pointer = p, .walk = .w }, screen, v);
        try std.testing.expectEqual(@as(usize, 0), book.cursor);
        book.choose(.passives);
        book.enter(v);
        const cursor = book.cursor;
        const inside = surface.screenOf(.{ .x = AREA.x + 150, .y = AREA.y + 160 });
        _ = book.step(&.{ .pointer = inside, .middle_click = true, .dragging = true, .mouse_delta = .{ .x = 30, .y = 15 } }, screen, v);
        try std.testing.expect(book.pan.x < 0 and book.pan.y < 0);
        try std.testing.expectEqual(cursor, book.cursor);
        const pan = book.pan;
        _ = book.step(&.{ .pointer = inside, .mouse_delta = .{ .x = 30, .y = 15 } }, screen, v);
        try std.testing.expectEqual(pan, book.pan);
        const zoom = book.zoom;
        _ = book.step(&.{ .pointer = inside, .scroll = 1 }, screen, v);
        try std.testing.expect(book.zoom > zoom);
        _ = book.step(&.{ .pointer = surface.screenOf(raster.middle(trees.overviewBox())), .click = true }, screen, v);
        try std.testing.expectEqual(trees.ZOOM_MIN, book.zoom);
        try std.testing.expectEqual(rl.Vector2{ .x = 0, .y = 0 }, book.pan);
        try std.testing.expectEqual(@as(u16, 2), growth.active_points);
        try std.testing.expectEqual(@as(u16, 2), growth.passive_points);
        try std.testing.expect(book.step(&.{ .right_click = true }, screen, v).? == .close);
        checked += 1;
    }
    std.debug.print("mouse character: {d} scales, skill selection/controller return, captured drag/release, zoom, overview, no point spend\n", .{checked});
}

test "mouse item and skill selections survive movement across other targets toward actions" {
    var inv = items.Inventory{};
    for (0..8) |_| try std.testing.expect(inv.add(.{ .kind = .cap }));
    const growth = progress.State.of(.archer);
    var v = testView(&inv, &growth);
    const nearby = [_]Nearby{
        .{ .loot = .{ .index = 7, .item = .{ .kind = .cap } } },
        .{ .loot = .{ .index = 8, .item = .{ .kind = .cap } } },
        .{ .loot = .{ .index = 9, .item = .{ .kind = .cap } } },
    };
    var journeys: usize = 0;
    for ([_]P{ display.SCREEN_720, display.SCREEN_1440 }) |screen| {
        for ([_]Page{ .inventory, .loot, .skills }) |page| {
            v.nearby = if (page == .loot) &nearby else &.{};
            var book = Book{ .page = page };
            const surface = book.surface(screen, v);
            const origin = raster.middle(book.cellBox(0, v));
            _ = book.step(&.{ .pointer = surface.screenOf(origin), .click = true }, screen, v);
            const action = if (page == .skills) trees.bindBox() else book.actionBox(menu.CONFIRM, v);
            for (1..book.count(v)) |i| {
                _ = book.step(&.{ .pointer = surface.screenOf(raster.middle(book.cellBox(i, v))), .mouse_moved = true }, screen, v);
                try std.testing.expectEqual(@as(usize, 0), book.cursor);
            }
            const end = raster.middle(action);
            for (1..21) |i| {
                const fraction = @as(f32, @floatFromInt(i)) / 20;
                const p = rl.Vector2{ .x = origin.x + (end.x - origin.x) * fraction, .y = origin.y + (end.y - origin.y) * fraction };
                _ = book.step(&.{ .pointer = surface.screenOf(p), .mouse_moved = true }, screen, v);
            }
            const command = book.step(&.{ .pointer = surface.screenOf(end), .click = true }, screen, v).?;
            switch (page) {
                .inventory => try std.testing.expectEqual(@as(usize, 0), command.equip.index),
                .loot => try std.testing.expectEqual(@as(usize, 7), command.pickup),
                .skills => try std.testing.expectEqual(progress.skills(v.class)[0].act, command.bindings),
                else => unreachable,
            }
            journeys += 1;
        }
    }
    std.debug.print("mouse action journeys: {d} scaled inventory, loot and skill targets survive intermediate motion\n", .{journeys});
}

test "a stick pushed where no passive lies keeps the pan, as the keys do" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    const v = testView(&inv, &growth);
    const screen = display.SCREEN_720;
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
