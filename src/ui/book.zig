const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const hero = @import("../play/hero.zig");
const attr = @import("../play/attrs.zig");
const items = @import("../play/items.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const trees = @import("trees.zig");
const hud = @import("hud.zig");
const P = mathx.P;
pub const Page = enum {
    equipment,
    inventory,
    stats,
    passives,
    skills,
    nearby,

    pub fn of(key_page: input.CharacterPage) Page {
        return switch (key_page) {
            inline else => |page| @field(Page, @tagName(page)),
        };
    }

    fn shortcut(self: Page) ?input.CharacterPage {
        return switch (self) {
            .nearby => null,
            inline else => |page| @field(input.CharacterPage, @tagName(page)),
        };
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
/// A list's rows, then its text and second column within a row.
const LIST_X = 24;
const LIST_Y = 30;
const LIST_W = 510;
const TEXT_X = 8;
const SECOND_X = 336;
/// Sideways distance between cells costs this much more than distance ahead.
pub const CELL_ACROSS: f32 = 2;
const CARD_W = 246;
const CARD_GAP = 16;
const CARD_H = 252;
const TAB_Y = 76;
const TAB_W = 184;
const TAB_H = 34;
const TAB_GAP = 9;
const TABS_X: i32 = @divExact(W - @as(i32, PAGES.len) * TAB_W - (@as(i32, PAGES.len) - 1) * TAB_GAP, 2);
/// Room each side of the tabs for the shoulder buttons' icons.
const SHOULDER_W = 40;
comptime {
    std.debug.assert(LIST_X + SHOULDER_W < TABS_X);
}
const ACTION_W = 164;
const ACTION_GAP = 8;
const ACTION_H = 36;
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
    kind: enum { loot, chest, door },
    index: usize = 0,
    at: P,
    item: ?items.Item = null,

    pub fn command(n: Nearby) Command {
        return switch (n.kind) {
            .loot => .{ .pickup = n.index },
            .chest => .{ .open_chest = n.at },
            .door => .{ .travel = n.at },
        };
    }

    fn label(n: Nearby) [:0]const u8 {
        return if (n.item) |it| it.name() else switch (n.kind) {
            .chest => CHEST,
            .door => DOOR,
            .loot => unreachable,
        };
    }
};
const CHEST = "Treasure chest";
const DOOR = "Door";
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
    open_chest: P,
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
        .passive => "Allocate",
        .skill => "Learn",
        .pickup => "Pick up",
        .open_chest => "Open",
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
    zoom: f32 = trees.ZOOM_START,
    pan: rl.Vector2 = .{ .x = 0, .y = 0 },
    destination_index: usize = 0,
    direct: bool = false,
    message: menu.Note(80) = .{},

    pub fn open(self: *Book) void {
        if (self.page == .nearby) {
            const cursor = self.last_cursor;
            self.choose(self.last_page);
            self.cursor = cursor;
        }
        self.destination_index = 0;
        self.direct = false;
        self.message.clear();
    }
    pub fn choose(self: *Book, page: Page) void {
        if (page == .nearby and self.page != .nearby) {
            self.last_page = self.page;
            self.last_cursor = self.cursor;
        }
        self.page = page;
        self.cursor = 0;
        self.top = 0;
        self.zoom = trees.ZOOM_START;
        self.pan = .{ .x = 0, .y = 0 };
        self.destination_index = 0;
        self.message.clear();
    }
    fn count(self: *const Book, v: View) usize {
        return switch (self.page) {
            .equipment => items.SLOTS.len,
            .inventory => v.inventory.n,
            .stats => 0,
            .passives => progress.NODES.len,
            .skills => progress.skills(v.class).len,
            .nearby => v.nearby.len,
        };
    }
    fn first(self: *const Book) usize {
        return mathx.reveal(self.top, self.cursor, VISIBLE);
    }
    fn settledTop(self: *const Book, v: View) usize {
        return @min(self.first(), self.count(v) -| VISIBLE);
    }
    /// A scrolling list rather than laid-out cells.
    fn listed(self: *const Book) bool {
        return self.page == .inventory or self.page == .nearby;
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
        if (self.zoom == trees.ZOOM_MIN) self.pan = .{ .x = 0, .y = 0 };
        self.clampPan();
    }
    fn clampPan(self: *Book) void {
        self.pan = trees.clampPan(self.treeView());
    }
    pub fn treeActive(self: *const Book) bool {
        return self.page == .passives;
    }
    fn inWindow(self: *const Book, i: usize) bool {
        return !self.listed() or (i >= self.first() and i < self.first() + VISIBLE);
    }
    pub fn enter(self: *Book, v: View) void {
        if (self.count(v) == 0) return;
        if (self.page == .passives) {
            self.cursor = progress.start(v.class);
            self.pan = .{ .x = 0, .y = 0 };
        }
    }
    fn selected(self: *const Book, v: View) ?items.Item {
        return switch (self.page) {
            .equipment => v.inventory.gear.slots.get(items.SLOTS[self.cursor]),
            .inventory => if (self.cursor < v.inventory.n) v.inventory.bag[self.cursor] else null,
            .nearby => if (self.cursor < v.nearby.len) v.nearby[self.cursor].item else null,
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
                const act = progress.skills(v.class)[self.cursor].act;
                break :blk if (v.growth.canLearn(v.class, act)) .{ .skill = act } else null;
            },
            .nearby => v.nearby[self.cursor].command(),
        };
    }
    pub fn step(self: *Book, state: *const input.State, screen: P, v: View) ?Command {
        var local = state.*;
        if (local.pointer) |p| local.pointer = menu.Surface.of(screen, SIZE).point(p);
        const st = &local;
        const previous_cursor = self.cursor;
        const previous_page = self.page;
        defer {
            if (self.cursor != previous_cursor or self.page != previous_page) {
                self.message.clear();
                self.destination_index = 0;
            }
            self.top = self.settledTop(v);
        }
        const o = P{ .x = 0, .y = 0 };
        self.cursor = @min(self.cursor, self.count(v) -| 1);
        if (local.click) if (local.pointer) |p| if (self.buttonAt(o, p, v)) |b| {
            local.pressed.insert(b);
            local.click = false;
        };
        if (menu.closed(st)) return .close;
        if (!self.direct and (st.hit(.lb) or st.hit(.rb))) {
            self.choose(mathx.stepIn(Page, &PAGES, self.page, if (st.hit(.lb)) -1 else 1, 0));
            self.enter(v);
            return null;
        }
        if (self.page == .inventory and self.selected(v) != null) {
            if (st.hit(menu.REMOVE)) return .{ .drop = self.cursor };
            if (st.hit(menu.CHANGE)) self.destination_index = mathx.wrap(self.destination_index, 1, self.selected(v).?.kind.slots().len);
        }
        if (self.page == .skills and st.hit(menu.CHANGE)) return .{ .bindings = progress.skills(v.class)[self.cursor].act };
        if (self.page == .passives) {
            if (st.hit(menu.CHANGE)) self.zoomBy(trees.ZOOM_STEP);
            if (st.hit(menu.REMOVE)) self.zoomBy(-trees.ZOOM_STEP);
            if (st.tree.zoom != 0) self.zoomBy(st.tree.zoom * trees.ZOOM_RATE * st.tree.dt);
            self.pan.x += st.tree.pan.x * trees.PAN_RATE * st.tree.dt / self.zoom;
            self.pan.y += st.tree.pan.y * trees.PAN_RATE * st.tree.dt / self.zoom;
            self.clampPan();
            if (st.tree.reset) {
                self.zoom = trees.ZOOM_MIN;
                self.pan = .{ .x = 0, .y = 0 };
            }
            if (st.tree.move) |d| {
                self.cursor = progress.passives.step(self.cursor, d.x, d.y);
                self.pan = .{ .x = 0, .y = 0 };
            }
        }
        if (self.page == .passives) {
            if (st.pointer) |p| if (trees.onCanvas(o, p)) {
                if (st.scroll != 0) {
                    self.zoomBy(@as(f32, @floatFromInt(st.scroll)) * trees.ZOOM_WHEEL);
                }
            };
        }
        if (self.listed() and st.scroll != 0 and self.count(v) > 0) {
            self.cursor = mathx.nudge(self.cursor, -st.scroll, self.count(v));
        }
        if (st.click) if (st.pointer) |p| {
            if (!self.direct) for (PAGES, 0..) |page, i| if (look.holds(tabBox(o, i), p)) {
                self.choose(page);
                self.enter(v);
                return null;
            };
            for (0..self.count(v)) |i| {
                if (!self.inWindow(i)) continue;
                if (self.page == .passives and !trees.onCanvas(o, p)) continue;
                if (look.holds(self.cellBox(o, i, v), p)) {
                    self.cursor = i;
                    if (self.page == .passives) self.pan = .{ .x = 0, .y = 0 };
                    return null;
                }
            }
        };
        if (st.walk) |dir| {
            const d = dir.delta();
            if (self.listed()) {
                if (d.y != 0 and self.count(v) > 0) self.cursor = mathx.wrap(self.cursor, d.y, self.count(v));
            } else if (self.page == .passives) {
                const next = progress.passives.step(self.cursor, @floatFromInt(d.x), @floatFromInt(d.y));
                if (next != self.cursor) {
                    self.cursor = next;
                    self.pan = .{ .x = 0, .y = 0 };
                }
            } else if (self.count(v) > 0) {
                var boxes: [CELLS_MAX]rl.Rectangle = undefined;
                for (0..self.count(v)) |i| boxes[i] = self.cellBox(o, i, v);
                if (menu.nearest(boxes[self.cursor], boxes[0..self.count(v)], dir, CELL_ACROSS)) |i| self.cursor = i;
            }
        }
        if (st.hit(menu.CONFIRM)) {
            return self.select(v);
        }
        return null;
    }
    /// The button whose box is under `p`, so a click there is that button's press.
    fn buttonAt(self: *const Book, o: P, p: P, v: View) ?input.Button {
        if (look.holds(closeBox(o), p)) return menu.BACK;
        switch (self.page) {
            .passives => for ([_]bool{ false, true }) |increase| {
                if (look.holds(trees.zoomBox(o, increase), p)) return if (increase) menu.CHANGE else menu.REMOVE;
            },
            .skills => if (look.holds(trees.bindBox(o), p)) return menu.CHANGE,
            .inventory => if (self.selected(v) != null) for (ACTIONS[1..]) |b| {
                if (look.holds(actionBox(o, b), p)) return b;
            },
            else => {},
        }
        const primary = if (self.treePanel() != null) trees.actionBox(o) else actionBox(o, menu.CONFIRM);
        return if (look.holds(primary, p)) menu.CONFIRM else null;
    }
    fn cellBox(self: *const Book, o: P, i: usize, v: View) rl.Rectangle {
        const y = o.y + TOP;
        return switch (self.page) {
            .equipment => blk: {
                const s = SLOT_BOX.get(items.SLOTS[i]);
                break :blk look.rect(o.x + s.at.x, y + s.at.y, s.w, s.h);
            },
            .inventory, .nearby => look.rect(o.x + LIST_X, y + LIST_Y + (@as(i32, @intCast(i)) - @as(i32, @intCast(self.first()))) * ROW, LIST_W, ROW),
            .passives, .skills => trees.cellBox(self.treePanel().?, o, v.class, i, self.treeView()),
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
        const surface = menu.Surface.of(screen, SIZE);
        surface.begin();
        defer rl.endMode2D();
        var scaled_face = source_face.*;
        if (surface.scale != 1) scaled_face.native = @splat(null);
        const face = &scaled_face;
        const o = P{ .x = 0, .y = 0 };
        look.hudPanel(sprites, o.x, o.y, W, H, look.CARD_BG, look.LIT);
        var who: menu.Note(100) = .{};
        who.say("{s}   {s}", .{ v.name, v.class.title() });
        face.draw(who.text(), o.x + LIST_X, o.y + 22, font.HEAD, look.TEXT);
        var xp: menu.Note(100) = .{};
        xp.say("Level  {d}     XP  {d} / {d}", .{ v.growth.level, v.growth.xp, v.growth.needed() });
        face.draw(xp.text(), o.x + RIGHT, o.y + 24, font.BODY, look.TEXT);
        menu.action(face, closeBox(o), look.Prompt.menuOn(v.device, menu.BACK), verbOf(.close));
        if (self.direct) face.draw("NEARBY", o.x + LIST_X, o.y + TAB_Y + (TAB_H - font.HEAD) / 2, font.HEAD, look.TEXT) else for (PAGES, 0..) |page, i| tab(face, tabBox(o, i), page, self.page == page, v.device);
        if (self.treePanel() == null) rl.drawLine(o.x + DIVIDER_X, o.y + TOP, o.x + DIVIDER_X, o.y + H - 30, look.EDGE);
        if (self.treePanel()) |panel| {
            trees.draw(panel, face, sprites, o, v.class, v.growth, self.treeView(), v.device, .{ .stats = v.stats(), .gear = v.inventory.gear }, surface);
        } else if (self.page == .stats) {
            drawStats(face, o, v);
        } else {
            self.drawCells(face, o, v);
            self.drawDetail(face, o, v);
        }
        if (self.message.n > 0) {
            if (self.treePanel() != null) trees.note(face, o, self.message.text()) else face.draw(self.message.text(), o.x + RIGHT, o.y + H - 32, font.SMALL, look.TEXT);
        }
        if (self.treePanel() != null) {
            const enabled = if (self.page == .passives) v.growth.canAllocate(self.cursor) else v.growth.canLearn(v.class, progress.skills(v.class)[self.cursor].act);
            _ = menu.actionPrompt(face, trees.actionBox(o), look.Prompt.menuOn(v.device, menu.CONFIRM), if (enabled) 1 else look.FADED_A);
        }
        if (self.page == .skills) menu.action(face, trees.bindBox(o), look.Prompt.menuOn(v.device, menu.CHANGE), if (v.growth.unlocked(progress.skills(v.class)[self.cursor].act)) verbOf(.bindings) else "Bindings");
        if (!self.direct) {
            const y = o.y + TAB_Y + TAB_H / 2;
            look.Prompt.menuOn(v.device, .lb).draw(face, o.x + LIST_X + SHOULDER_W / 2, y, font.BODY, 1);
            look.Prompt.menuOn(v.device, .rb).draw(face, o.x + W - LIST_X - SHOULDER_W / 2, y, font.BODY, 1);
        }
    }

    fn drawCells(self: *const Book, face: *const font.Face, o: P, v: View) void {
        if (self.listed()) {
            const text_x = o.x + LIST_X + TEXT_X;
            face.draw("ITEM", text_x, o.y + TOP, font.SMALL, look.DIM);
            face.draw(if (self.page == .inventory) "SLOT" else "ACTION", o.x + LIST_X + SECOND_X, o.y + TOP, font.SMALL, look.DIM);
            if (self.count(v) == 0) face.draw("Empty", text_x, o.y + TOP + 46, font.BODY, look.DIM);
            var position: menu.Note(50) = .{};
            position.say("{d} / {d}", .{ if (self.count(v) > 0) self.cursor + 1 else 0, self.count(v) });
            face.draw(position.text(), text_x, o.y + H - 32, font.SMALL, look.DIM);
        }
        for (0..self.count(v)) |i| {
            if (!self.inWindow(i)) continue;
            const r = self.cellBox(o, i, v);
            const x: i32 = @intFromFloat(r.x);
            const y: i32 = @intFromFloat(r.y);
            const chosen = i == self.cursor;
            rl.drawRectangleRec(r, look.BG);
            rl.drawRectangleLinesEx(r, if (chosen) 2 else 1, if (chosen) look.UI_FOCUS else look.EDGE);
            switch (self.page) {
                .equipment => {
                    const slot = items.SLOTS[i];
                    const inner = @as(i32, @intFromFloat(r.width)) - 2 * SLOT_INSET;
                    var fitted: [64]u8 = undefined;
                    face.draw(face.fit(&fitted, slotLabel(slot), SLOT_LABEL, inner, false), x + SLOT_INSET, y + SLOT_INSET, SLOT_LABEL, look.DIM);
                    const it = v.inventory.gear.slots.get(slot);
                    const mid = look.middleAt(r);
                    if (offhandWeapon(v.inventory.gear, slot)) |weapon| {
                        face.centred("Both hands", mid.x, mid.y - 12, font.SMALL, look.DIM);
                        face.centred(face.fit(&fitted, weapon.name(), font.SMALL, inner, false), mid.x, mid.y + 12, font.SMALL, look.DIM);
                    } else {
                        const name = if (it) |a| (if (slot == .right_hand or slot == .left_hand) a.name() else menu.named(a.kind)) else "-";
                        face.centred(face.fit(&fitted, name, font.SMALL, inner, false), mid.x, mid.y + 8, font.SMALL, look.itemInk(it != null and it.?.magical()));
                    }
                },
                .inventory => {
                    const it = v.inventory.bag[i];
                    const slots = it.kind.slots();
                    face.draw(it.name(), x + TEXT_X, y + 4, font.BODY, look.itemInk(it.magical()));
                    face.draw(if (items.spec(it.kind).two_handed) "Both hands" else if (slots.len > 1) menu.named(it.kind) else slots[0].name(), x + SECOND_X, y + 5, font.SMALL, look.DIM);
                },
                .nearby => {
                    const n = v.nearby[i];
                    face.draw(n.label(), x + TEXT_X, y + 4, font.BODY, look.itemInk(n.item != null and n.item.?.magical()));
                    face.draw(n.command().verb(), x + SECOND_X, y + 5, font.SMALL, look.DIM);
                },
                .passives, .skills, .stats => unreachable,
            }
        }
    }
    fn requirementAttrs(self: *const Book, v: View, slot: items.Slot) attr.Attrs {
        const gear = switch (self.page) {
            .inventory => v.inventory.swapped(self.cursor, slot) catch v.inventory.gear,
            .nearby => v.inventory.gear.wearing(self.selected(v).?, slot),
            else => v.inventory.gear,
        };
        return gear.statsWithout(slot, v.base);
    }
    fn drawDetail(self: *const Book, face: *const font.Face, o: P, v: View) void {
        const x = o.x + RIGHT;
        const y = o.y + TOP;
        if (self.count(v) == 0) return;
        const it = self.selected(v) orelse {
            if (self.page == .equipment) if (offhandWeapon(v.inventory.gear, items.SLOTS[self.cursor])) |weapon| {
                face.draw("Both hands in use", x, y, font.HEAD, look.TEXT);
                var held: menu.Note(128) = .{};
                held.say("{s} uses both hands. Equipping an offhand returns it to inventory.", .{weapon.name()});
                _ = trees.paragraph(face, held.text(), x, y + 42, CARD_W * 2 + CARD_GAP, look.DIM);
                menu.action(face, actionBox(o, menu.CONFIRM), look.Prompt.menuOn(v.device, menu.CONFIRM), "Inventory");
                return;
            };
            face.draw(if (self.page == .nearby) v.nearby[self.cursor].label() else "Empty slot", x, y, font.HEAD, look.TEXT);
            menu.action(face, actionBox(o, menu.CONFIRM), look.Prompt.menuOn(v.device, menu.CONFIRM), if (self.page == .nearby) v.nearby[self.cursor].command().verb() else "Inventory");
            return;
        };
        const slots = it.kind.slots();
        const slot = if (self.page == .equipment) items.SLOTS[self.cursor] else self.destination(v);
        const comparing = self.page == .inventory;
        itemCard(face, x, y, if (comparing) CARD_W else CARD_W * 2 + CARD_GAP, it, slot, self.requirementAttrs(v, slot), if (comparing) "SELECTED" else if (self.page == .equipment) "EQUIPPED" else "ON THE GROUND");
        if (comparing) itemCard(face, x + CARD_W + CARD_GAP, y, CARD_W, v.inventory.gear.slots.get(slot), slot, v.inventory.gear.statsWithout(slot, v.base), "EQUIPPED");
        if (self.page == .inventory) {
            const at = y + CARD_H + 18;
            if (v.inventory.preview(self.cursor, slot, v.base)) |after| {
                var below = drawChanges(face, x, at, v.stats(), after.stats(v.base)) + 8;
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
                _ = trees.paragraph(face, reason.text(), x, at, CARD_W * 2 + CARD_GAP, LOSS);
            }
        }
        menu.action(face, actionBox(o, menu.CONFIRM), look.Prompt.menuOn(v.device, menu.CONFIRM), switch (self.page) {
            .equipment => verbOf(.unequip),
            .inventory => verbOf(.equip),
            .nearby => verbOf(.pickup),
            .stats, .passives, .skills => unreachable,
        });
        if (self.page == .inventory) {
            if (slots.len > 1) menu.action(face, actionBox(o, menu.CHANGE), look.Prompt.menuOn(v.device, menu.CHANGE), slotLabel(slot));
            menu.action(face, actionBox(o, menu.REMOVE), look.Prompt.menuOn(v.device, menu.REMOVE), verbOf(.drop));
        }
    }
};
fn tabBox(o: P, i: usize) rl.Rectangle {
    return look.rect(o.x + TABS_X + @as(i32, @intCast(i)) * (TAB_W + TAB_GAP), o.y + TAB_Y, TAB_W, TAB_H);
}
/// The detail panel's buttons, left to right.
const ACTIONS = [_]input.Button{ menu.CONFIRM, menu.CHANGE, menu.REMOVE };
fn actionBox(o: P, b: input.Button) rl.Rectangle {
    const i: i32 = @intCast(std.mem.indexOfScalar(input.Button, &ACTIONS, b).?);
    return look.rect(o.x + RIGHT + i * (ACTION_W + ACTION_GAP), o.y + H - 82, ACTION_W, ACTION_H);
}
fn closeBox(o: P) rl.Rectangle {
    return look.rect(o.x + W - 132, o.y + 18, 108, 32);
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
    rl.drawRectangleLinesEx(r, if (on) 2 else 1, if (on) look.UI_FOCUS else look.EDGE);
    const m = look.middleAt(r);
    const text = menu.named(page);
    const ink = if (on) look.TEXT else look.DIM;
    if (!device.pad()) {
        const prompt = look.Prompt{ .key = page.shortcut().?.caption() };
        const w = prompt.width(face, font.BODY);
        const left = m.x - @divTrunc(w + menu.PROMPT_GAP + face.width(text, font.BODY), 2);
        prompt.draw(face, left + @divTrunc(w, 2), m.y, font.BODY, if (on) 1 else 0.7);
        face.draw(text, left + w + menu.PROMPT_GAP, m.y - font.BODY / 2, font.BODY, ink);
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

fn itemCard(face: *const font.Face, x: i32, y: i32, width: i32, maybe: ?items.Item, slot: items.Slot, available: attr.Attrs, caption: [:0]const u8) void {
    const mid = x + @divTrunc(width, 2);
    face.drawMid(caption, mid, y, font.SMALL, look.DIM);
    rl.drawLine(x, y + 20, x + width, y + 20, look.EDGE);
    const it = maybe orelse {
        face.drawMid("Empty slot", mid, y + 35, font.BODY, look.DIM);
        face.drawMid(slot.name(), mid, y + 62, font.SMALL, look.DIM);
        return;
    };
    const spec = items.spec(it.kind);
    const ink = look.itemInk(it.magical());
    face.drawMid(it.name(), mid, y + 32, font.HEAD, ink);
    face.drawMid(if (slot == .right_hand) (if (spec.two_handed) "Two-handed" else "One-handed") else slot.name(), mid, y + 62, font.SMALL, look.DIM);
    face.drawMid(it.flavor(), mid, y + 82, font.SMALL, look.DIM);
    var top = y + 104;
    var line: menu.Note(120) = .{};
    if (spec.damage) |hit| {
        line.say("Physical damage: {d}-{d}", .{ hit.lo, hit.hi });
        face.drawMid(line.text(), mid, top, font.SMALL, look.TEXT);
        top += CARD_LINE;
        line.say("Scales with {s}", .{menu.named(spec.style.attr())});
        face.drawMid(line.text(), mid, top, font.SMALL, look.DIM);
        top += CARD_LINE;
    } else if (slot == .right_hand) {
        face.drawMid("No weapon damage", mid, top, font.SMALL, look.DIM);
        top += CARD_LINE;
    }
    if (spec.armour > 0) {
        line.say("Physical damage reduced by {d}%", .{spec.armour});
        face.drawMid(line.text(), mid, top, font.SMALL, look.TEXT);
        top += CARD_LINE;
    }
    inline for (attr.ATTRS) |at| {
        const required = @field(spec.needs, @tagName(at));
        if (required > 0) {
            line.say("Requires {d} {s}", .{ required, menu.named(at) });
            const met = available.get(at) >= required;
            face.drawMid(line.text(), mid, top, font.SMALL, if (met) look.DIM else LOSS);
            top += CARD_LINE;
            if (!met) {
                line.say("({d} available)", .{available.get(at)});
                face.drawMid(line.text(), mid, top, font.SMALL, LOSS);
                top += CARD_LINE;
            }
        }
    }
    if (it.magical()) {
        top += 8;
        rl.drawLine(x + 30, top, x + width - 30, top, look.EDGE);
        top += 12;
        for (items.MODS) |m| {
            const n = it.value(m);
            if (n == 0) continue;
            line.say("+{d} to {s}", .{ n, m.label() });
            face.drawMid(line.text(), mid, top, font.SMALL, look.WARD);
            top += CARD_LINE;
        }
    }
}

fn change(face: *const font.Face, x: i32, y: i32, n: *usize, label: [:0]const u8, was: i32, now: i32, percent: bool) void {
    const delta = now - was;
    if (delta == 0) return;
    var text: menu.Note(100) = .{};
    text.say("{s}{d}{s} {s}", .{ if (delta > 0) @as([]const u8, "+") else "", delta, if (percent) @as([]const u8, "%") else "", label });
    face.draw(text.text(), x + @as(i32, @intCast(n.* % 2)) * (CARD_W + CARD_GAP), y + @as(i32, @intCast(n.* / 2)) * CHANGE_ROW, font.SMALL, if (delta > 0) GAIN else LOSS);
    n.* += 1;
}

const CHANGE_ROW = 20;

/// The foot of the change list.
fn drawChanges(face: *const font.Face, x: i32, y: i32, was: attr.Attrs, now: attr.Attrs) i32 {
    face.draw("IF EQUIPPED", x, y, font.SMALL, look.DIM);
    var n: usize = 0;
    const top = y + CARD_LINE;
    change(face, x, top, &n, attr.Bonus.life.label(), was.life(), now.life(), false);
    change(face, x, top, &n, attr.Bonus.mana.label(), was.mana(), now.mana(), false);
    for (attr.ATTRS) |at| change(face, x, top, &n, menu.named(at), was.get(at), now.get(at), false);
    change(face, x, top, &n, "physical reduction", was.reduction(), now.reduction(), true);
    change(face, x, top, &n, "critical chance", @intCast(was.crit()), @intCast(now.crit()), true);
    change(face, x, top, &n, "dodge chance", @intCast(was.dodge()), @intCast(now.dodge()), true);
    for (attr.STYLES) |s| change(face, x, top, &n, damageLabel(s), was.increase(s), now.increase(s), true);
    if (n == 0) {
        face.draw("No attribute or defense changes.", x, top, font.SMALL, look.DIM);
        return top + CHANGE_ROW;
    }
    return top + @as(i32, @intCast((n + 1) / 2)) * CHANGE_ROW;
}

fn damageLabel(s: attr.Style) [:0]const u8 {
    return switch (s) {
        inline else => |t| @tagName(t) ++ " damage bonus",
    };
}

const STAT_W = 440;
/// A section's title to its first row, and row to row.
const SECTION_ROWS = 38;
const STAT_ROW = 30;
const ATTR_ROW = 58;

fn row(top: i32, i: usize, step: i32) i32 {
    return top + SECTION_ROWS + @as(i32, @intCast(i)) * step;
}

fn stat(face: *const font.Face, x: i32, y: i32, label: [:0]const u8, number: i32, prefix: []const u8, suffix: []const u8) void {
    face.draw(label, x, y, font.BODY, look.TEXT);
    var text: menu.Note(48) = .{};
    text.say("{s}{d}{s}", .{ prefix, number, suffix });
    face.draw(text.text(), x + STAT_W - face.width(text.text(), font.BODY), y, font.BODY, look.TEXT);
}

fn section(face: *const font.Face, x: i32, y: i32, title: [:0]const u8) void {
    face.draw(title, x, y, font.SMALL, look.UI_FOCUS);
    rl.drawLine(x, y + 25, x + STAT_W, y + 25, look.EDGE);
}

fn drawStats(face: *const font.Face, o: P, v: View) void {
    const a = v.stats();
    const x = o.x + 40;
    const right = o.x + RIGHT;
    const y = o.y + TOP;
    section(face, x, y, "ATTRIBUTES");
    for (attr.ATTRS, 0..) |at, i| {
        const top = row(y, i, ATTR_ROW);
        stat(face, x, top, menu.named(at), a.get(at), "", "");
        face.draw(switch (at) {
            .strength => "Life and heavy weapon damage",
            .dexterity => "Light weapons, critical chance and dodge",
            .intelligence => "Mana and spell damage",
        }, x, top + 25, font.SMALL, look.DIM);
    }
    const survival = y + 226;
    section(face, x, survival, "SURVIVAL");
    stat(face, x, row(survival, 0, STAT_ROW), "Maximum life", a.life(), "", "");
    stat(face, x, row(survival, 1, STAT_ROW), "Maximum mana", a.mana(), "", "");
    stat(face, x, row(survival, 2, STAT_ROW), "Physical damage reduction", a.reduction(), "", "%");
    stat(face, x, row(survival, 3, STAT_ROW), "Chance to dodge", @intCast(a.dodge()), "", "%");
    var note: menu.Note(100) = .{};
    note.say("Physical reduction is capped at {d}%.", .{attr.ARMOUR_MAX});
    face.draw(note.text(), x, row(survival, 4, STAT_ROW) + 7, font.SMALL, look.DIM);
    section(face, right, y, "DAMAGE BONUSES");
    for (attr.STYLES, 0..) |s, i| stat(face, right, row(y, i, STAT_ROW), s.label(), a.increase(s), "+", "%");
    face.draw("Bonuses to base damage; skill ranks add their own.", right, row(y, attr.STYLES.len, STAT_ROW) + 11, font.SMALL, look.DIM);
    stat(face, right, y + 180, "Critical strike chance", @intCast(a.crit()), "", "%");
    stat(face, right, y + 180 + STAT_ROW, "Critical damage multiplier", attr.CRIT_MULTI, "", "%");
    const progression = y + 272;
    section(face, right, progression, "PROGRESSION");
    stat(face, right, row(progression, 0, STAT_ROW), "Passive points available", v.growth.passive_points, "", "");
    stat(face, right, row(progression, 1, STAT_ROW), "Active skill points available", v.growth.active_points, "", "");
    stat(face, right, row(progression, 3, STAT_ROW) - 10, "Gold", v.gold, "", "");
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
    const surface = menu.Surface.of(screen, SIZE);
    const box = actionBox(.{ .x = 0, .y = 0 }, menu.CONFIRM);
    const p = P{ .x = @intFromFloat(surface.offset.x + (box.x + 20) * surface.scale), .y = @intFromFloat(surface.offset.y + (box.y + 20) * surface.scale) };
    try std.testing.expect(book.step(&.{ .click = true, .pointer = p }, screen, v).? == .equip);
    book.choose(.skills);
    book.cursor = 2;
    book.choose(.nearby);
    book.open();
    try std.testing.expectEqual(Page.skills, book.page);
    try std.testing.expectEqual(@as(usize, 2), book.cursor);
    std.debug.print("character actions: direct equip/drop, shoulder tabs, one-step close, scaled mouse hit; commands leave inventory untouched\n", .{});
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
    try std.testing.expect(book.zoom > 1);
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
    const canvas = trees.zoomBox(.{ .x = 0, .y = 0 }, true);
    const surface = menu.Surface.of(screen, SIZE);
    _ = book.step(&.{ .pointer = .{ .x = @intFromFloat(surface.offset.x + canvas.x * surface.scale), .y = @intFromFloat(surface.offset.y + canvas.y * surface.scale) }, .scroll = -1 }, screen, v);
    try std.testing.expect(book.treeActive() and book.zoom < trees.ZOOM_START);
    std.debug.print("tree book: spatial browsing and zoom spend no points; passive and skill selection return one command\n", .{});
}
