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
pub const Page = enum { equipment, inventory, stats, passives, skills, nearby };
pub const PAGES = [_]Page{ .equipment, .inventory, .stats, .passives, .skills };
const W = 1100;
const H = 620;
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
const CELL_ACROSS: f32 = 2;
const CARD_W = 246;
const CARD_GAP = 16;
const CARD_H = 230;
const LOSS = look.rgb(0xe18c83);
const GAIN = look.rgb(0xa8c596);
/// The most cells any page lays out by box.
const CELLS_MAX = @max(progress.NODES.len, items.SLOTS.len);
const SLOT_BOX = std.EnumArray(items.Slot, struct { at: P, w: i32, h: i32 }).init(.{
    .right_hand = .{ .at = .{ .x = 48, .y = 106 }, .w = 96, .h = 180 },
    .left_hand = .{ .at = .{ .x = 396, .y = 106 }, .w = 96, .h = 180 },
    .helm = .{ .at = .{ .x = 222, .y = 40 }, .w = 96, .h = 96 },
    .chest = .{ .at = .{ .x = 222, .y = 148 }, .w = 96, .h = 138 },
    .amulet = .{ .at = .{ .x = 333, .y = 84 }, .w = 48, .h = 48 },
    .gloves = .{ .at = .{ .x = 48, .y = 301 }, .w = 96, .h = 96 },
    .right_ring = .{ .at = .{ .x = 162, .y = 301 }, .w = 48, .h = 48 },
    .belt = .{ .at = .{ .x = 222, .y = 301 }, .w = 96, .h = 48 },
    .left_ring = .{ .at = .{ .x = 333, .y = 301 }, .w = 48, .h = 48 },
    .boots = .{ .at = .{ .x = 396, .y = 301 }, .w = 96, .h = 96 },
});
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
        return self.cursor -| (VISIBLE - 1);
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
        const limit = 1.6 + 6 * (1 - 1 / self.zoom);
        self.pan.x = std.math.clamp(self.pan.x, -limit, limit);
        self.pan.y = std.math.clamp(self.pan.y, -limit, limit);
    }
    pub fn treeActive(self: *const Book) bool {
        return self.page == .passives;
    }
    fn inWindow(self: *const Book, i: usize) bool {
        return !self.listed() or (i >= self.first() and i < self.first() + VISIBLE);
    }
    fn enter(self: *Book, v: View) void {
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
            .passives => if (v.growth.passive_points > 0 and v.growth.available(self.cursor)) .{ .passive = self.cursor } else null,
            .skills => blk: {
                const act = progress.skills(v.class)[self.cursor].act;
                break :blk if (v.growth.canLearn(v.class, act)) .{ .skill = act } else null;
            },
            .nearby => v.nearby[self.cursor].command(),
        };
    }
    pub fn step(self: *Book, state: *const input.State, screen: P, v: View) ?Command {
        var local = state.*;
        if (local.pointer) |p| local.pointer = menu.Surface.of(screen, .{ .x = W, .y = H }).point(p);
        const st = &local;
        const previous_cursor = self.cursor;
        const previous_page = self.page;
        defer if (self.cursor != previous_cursor or self.page != previous_page) self.message.clear();
        const o = P{ .x = 0, .y = 0 };
        self.cursor = @min(self.cursor, self.count(v) -| 1);
        if (menu.backed(st) or st.hit(menu.CHARACTER)) return .close;
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
            if (st.hit(menu.CHANGE)) self.zoomBy(0.4);
            if (st.hit(menu.REMOVE)) self.zoomBy(-0.4);
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
                    self.zoomBy(@as(f32, @floatFromInt(st.scroll)) * 0.2);
                }
            };
        }
        if (self.listed() and st.scroll != 0 and self.count(v) > 0) {
            self.cursor = mathx.nudge(self.cursor, -st.scroll, self.count(v));
        }
        if (st.click) if (st.pointer) |p| {
            if (look.holds(closeBox(o), p)) return .close;
            if (!self.direct) for (PAGES, 0..) |page, i| if (look.holds(tabBox(o, i), p)) {
                self.choose(page);
                if (page == .passives) self.cursor = progress.start(v.class);
                return null;
            };
            if (self.page == .passives) {
                for ([_]bool{ false, true }) |increase| if (look.holds(trees.zoomBox(o, increase), p)) {
                    self.zoomBy(if (increase) 0.4 else -0.4);
                    return null;
                };
            }
            if (self.page == .skills and look.holds(look.rect(764, 580, 292, 30), p)) return .{ .bindings = progress.skills(v.class)[self.cursor].act };
            if (self.page == .inventory and self.selected(v) != null) {
                if (look.holds(actionBox(o, 2), p)) return .{ .drop = self.cursor };
                if (look.holds(actionBox(o, 1), p)) {
                    self.destination_index = mathx.wrap(self.destination_index, 1, self.selected(v).?.kind.slots().len);
                    return null;
                }
            }
            const primary = if (self.treePanel() != null) trees.actionBox(o) else actionBox(o, 0);
            if (look.holds(primary, p)) {
                return self.select(v);
            }
            for (0..self.count(v)) |i| {
                if (!self.inWindow(i)) continue;
                if (self.page == .passives and !trees.onCanvas(o, p)) continue;
                if (look.holds(self.cellBox(o, i, v), p)) {
                    self.cursor = i;
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
    pub fn draw(self: *const Book, source_face: *const font.Face, sprites: *const look.Sprites, screen: P, v: View) void {
        const surface = menu.Surface.of(screen, .{ .x = W, .y = H });
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
        face.draw(xp.text(), o.x + RIGHT, o.y + 26, font.BODY, look.TEXT);
        const st = input.State{ .device = v.device };
        menu.action(face, closeBox(o), look.Prompt.menuOf(&st, menu.BACK), "Close");
        if (self.direct) face.draw("NEARBY", o.x + LIST_X, o.y + 82, font.HEAD, look.TEXT) else for (PAGES, 0..) |page, i| button(face, tabBox(o, i), menu.named(page), self.page == page);
        if (self.treePanel() == null) rl.drawLine(o.x + DIVIDER_X, o.y + TOP, o.x + DIVIDER_X, o.y + H - 30, look.EDGE);
        if (self.treePanel()) |panel| {
            trees.draw(panel, face, sprites, o, v.class, v.growth, self.treeView(), true, v.device, .{ .stats = v.stats(), .gear = v.inventory.gear }, surface);
        } else if (self.page == .stats) {
            drawStats(face, o, v);
        } else {
            self.drawCells(face, o, v);
            self.drawDetail(face, o, v);
        }
        if (self.message.n > 0) face.draw(self.message.text(), o.x + (if (self.treePanel() != null) @as(i32, 764) else RIGHT), o.y + H - 32, font.SMALL, look.TEXT);
        if (self.treePanel() != null) {
            const r = trees.actionBox(o);
            const prompt = look.Prompt.menuOf(&st, menu.CONFIRM);
            const enabled = if (self.page == .passives) v.growth.passive_points > 0 and v.growth.available(self.cursor) else v.growth.canLearn(v.class, progress.skills(v.class)[self.cursor].act);
            prompt.draw(face, @as(i32, @intFromFloat(r.x)) + 10 + @divTrunc(prompt.width(face, font.BODY), 2), @as(i32, @intFromFloat(r.y + r.height / 2)), font.BODY, if (enabled) 1 else 0.35);
        }
        if (self.page == .skills) menu.action(face, look.rect(o.x + 764, o.y + 580, 292, 30), look.Prompt.menuOf(&st, menu.CHANGE), if (v.growth.unlocked(progress.skills(v.class)[self.cursor].act)) "Bind skill" else "Bindings");
        if (!self.direct) {
            look.Prompt.menuOf(&st, .lb).draw(face, o.x + 14, o.y + 93, font.BODY, 1);
            look.Prompt.menuOf(&st, .rb).draw(face, o.x + W - 14, o.y + 93, font.BODY, 1);
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
                    face.draw(slotLabel(slot), x + 4, y + 4, 16, look.DIM);
                    const it = v.inventory.gear.slots.get(slot);
                    const mid = look.middleAt(r);
                    if (offhandWeapon(v.inventory.gear, slot)) |weapon| {
                        face.centred("Both hands", mid.x, mid.y - 12, font.SMALL, look.DIM);
                        face.centred(weapon.name(), mid.x, mid.y + 12, font.SMALL, look.DIM);
                    } else {
                        face.centred(if (it) |a| (if (slot == .right_hand or slot == .left_hand) a.name() else menu.named(a.kind)) else "-", mid.x, mid.y + 8, font.SMALL, if (it != null and it.?.magical()) look.WARD else look.TEXT);
                    }
                },
                .inventory => {
                    const it = v.inventory.bag[i];
                    const slots = it.kind.slots();
                    face.draw(it.name(), x + TEXT_X, y + 4, font.BODY, if (it.magical()) look.WARD else look.TEXT);
                    face.draw(if (items.spec(it.kind).two_handed) "Both hands" else if (slots.len > 1) menu.named(it.kind) else slots[0].name(), x + SECOND_X, y + 5, font.SMALL, look.DIM);
                },
                .nearby => {
                    const n = v.nearby[i];
                    face.draw(n.label(), x + TEXT_X, y + 4, font.BODY, if (n.item != null and n.item.?.magical()) look.WARD else look.TEXT);
                    face.draw(n.command().verb(), x + SECOND_X, y + 5, font.SMALL, look.DIM);
                },
                .passives, .skills, .stats => unreachable,
            }
        }
    }
    fn requirementAttrs(self: *const Book, v: View, slot: items.Slot) attr.Attrs {
        const gear = if (self.page == .inventory) v.inventory.swapped(self.cursor, slot) catch v.inventory.gear else v.inventory.gear;
        return if (self.page == .inventory or self.page == .equipment) withoutItem(gear, slot, v.base) else v.stats();
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
                _ = textBlock(face, held.text(), x, y + 42, CARD_W * 2 + CARD_GAP, font.SMALL, look.DIM);
                menu.action(face, actionBox(o, 0), look.Prompt.menuOf(&.{ .device = v.device }, menu.CONFIRM), "Inventory");
                return;
            };
            face.draw(if (self.page == .nearby) v.nearby[self.cursor].label() else "Empty slot", x, y, font.HEAD, look.TEXT);
            menu.action(face, actionBox(o, 0), look.Prompt.menuOf(&.{ .device = v.device }, menu.CONFIRM), if (self.page == .nearby) "Interact" else "Inventory");
            return;
        };
        const slots = it.kind.slots();
        const slot = if (self.page == .equipment) items.SLOTS[self.cursor] else self.destination(v);
        const comparing = self.page == .inventory;
        itemCard(face, x, y, if (comparing) CARD_W else CARD_W * 2 + CARD_GAP, it, slot, self.requirementAttrs(v, slot), if (comparing) "SELECTED" else if (self.page == .equipment) "EQUIPPED" else "ON THE GROUND");
        if (comparing) itemCard(face, x + CARD_W + CARD_GAP, y, CARD_W, v.inventory.gear.slots.get(slot), slot, withoutItem(v.inventory.gear, slot, v.base), "EQUIPPED");
        if (self.page == .inventory) {
            const at = y + CARD_H + 18;
            if (v.inventory.preview(self.cursor, slot, v.base)) |after| {
                drawChanges(face, x, at, v.stats(), after.stats(v.base));
                for (items.SLOTS) |s| {
                    if (s == slot or !v.inventory.displaced(after, slot, s)) continue;
                    var moved: menu.Note(100) = .{};
                    moved.say("Returns {s} to inventory.", .{v.inventory.gear.slots.get(s).?.name()});
                    face.draw(moved.text(), x, o.y + H - 100, font.SMALL, look.DIM);
                }
            } else |err| {
                var reason: menu.Note(140) = .{};
                reason.say("{s}", .{items.caption(err)});
                if (err == error.Requirements) {
                    reason.say("Cannot equip: requirements not met.", .{});
                    if (v.inventory.swapped(self.cursor, slot)) |after| {
                        for (items.SLOTS) |s| {
                            if (s == slot) continue;
                            if (after.slots.get(s)) |other| if (!after.wornMeets(s, v.base)) {
                                reason.say("Would leave {s} without its required attributes.", .{other.name()});
                                break;
                            };
                        }
                    } else |_| {}
                }
                _ = textBlock(face, reason.text(), x, at, CARD_W * 2 + CARD_GAP, font.SMALL, LOSS);
            }
        }
        const st = input.State{ .device = v.device };
        menu.action(face, actionBox(o, 0), look.Prompt.menuOf(&st, menu.CONFIRM), switch (self.page) {
            .equipment => verbOf(.unequip),
            .inventory => verbOf(.equip),
            .nearby => verbOf(.pickup),
            .stats, .passives, .skills => unreachable,
        });
        if (self.page == .inventory) {
            if (slots.len > 1) menu.action(face, actionBox(o, 1), look.Prompt.menuOf(&st, menu.CHANGE), slotLabel(slot));
            menu.action(face, actionBox(o, 2), look.Prompt.menuOf(&st, menu.REMOVE), "Drop");
        }
    }
};
fn row(i: usize) i32 {
    return @as(i32, @intCast(i)) * ROW;
}
fn tabBox(o: P, i: usize) rl.Rectangle {
    return look.rect(o.x + LIST_X + @as(i32, @intCast(i)) * 210, o.y + 76, 202, 34);
}
fn actionBox(o: P, i: usize) rl.Rectangle {
    return look.rect(o.x + RIGHT + @as(i32, @intCast(i)) * 166, o.y + H - 82, 156, 36);
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
fn button(face: *const font.Face, r: rl.Rectangle, text: [:0]const u8, on: bool) void {
    rl.drawRectangleLinesEx(r, if (on) 2 else 1, if (on) look.UI_FOCUS else look.EDGE);
    const m = look.middleAt(r);
    face.centred(text, m.x, m.y, font.BODY, if (on) look.TEXT else look.DIM);
}
fn withoutItem(gear: items.Gear, slot: items.Slot, base: attr.Attrs) attr.Attrs {
    var without = gear;
    without.slots.set(slot, null);
    return without.stats(base);
}

fn offhandWeapon(gear: items.Gear, slot: items.Slot) ?items.Item {
    if (slot != .left_hand) return null;
    const weapon = gear.slots.get(.right_hand) orelse return null;
    return if (items.spec(weapon.kind).two_handed) weapon else null;
}

fn textBlock(face: *const font.Face, text: []const u8, x: i32, y: i32, width: i32, size: i32, ink: rl.Color) i32 {
    var buf: [hud.TIP_LINES_MAX][hud.TIP_COLS_MAX + 1]u8 = undefined;
    var lines: [hud.TIP_LINES_MAX][:0]const u8 = undefined;
    const n = hud.wrap(face, text, size, width, &buf, &lines);
    for (lines[0..n], 0..) |line, i| face.draw(line, x, y + @as(i32, @intCast(i)) * (size + 4), size, ink);
    return y + @as(i32, @intCast(n)) * (size + 4);
}

fn itemCard(face: *const font.Face, x: i32, y: i32, width: i32, maybe: ?items.Item, slot: items.Slot, available: attr.Attrs, caption: [:0]const u8) void {
    const mid = x + @divTrunc(width, 2);
    face.drawMid(caption, mid, y, 16, look.DIM);
    rl.drawLine(x, y + 20, x + width, y + 20, look.EDGE);
    const it = maybe orelse {
        face.drawMid("Empty slot", mid, y + 35, font.BODY, look.DIM);
        face.drawMid(slot.name(), mid, y + 62, font.SMALL, look.DIM);
        return;
    };
    const spec = items.spec(it.kind);
    const ink = if (it.magical()) look.WARD else look.TEXT;
    face.drawMid(it.name(), mid, y + 32, font.HEAD, ink);
    face.drawMid(if (slot == .right_hand) (if (spec.two_handed) "Two-handed" else "One-handed") else slot.name(), mid, y + 62, font.SMALL, look.DIM);
    var top = y + 92;
    var line: menu.Note(120) = .{};
    if (spec.damage) |hit| {
        line.say("Physical damage: {d}-{d}", .{ hit.lo, hit.hi });
        face.drawMid(line.text(), mid, top, font.SMALL, look.TEXT);
        top += 22;
        line.say("Scales with {s}", .{menu.named(spec.style.attr())});
        face.drawMid(line.text(), mid, top, font.SMALL, look.DIM);
        top += 22;
    } else if (slot == .right_hand) {
        face.drawMid("No weapon damage", mid, top, font.SMALL, look.DIM);
        top += 22;
    }
    if (spec.armour > 0) {
        line.say("Physical damage reduced by {d}%", .{spec.armour});
        face.drawMid(line.text(), mid, top, font.SMALL, look.TEXT);
        top += 22;
    }
    inline for (attr.ATTRS) |at| {
        const required = @field(spec.needs, @tagName(at));
        if (required > 0) {
            line.say("Requires {d} {s}", .{ required, menu.named(at) });
            const met = available.get(at) >= required;
            face.drawMid(line.text(), mid, top, font.SMALL, if (met) look.DIM else LOSS);
            top += 22;
            if (!met) {
                line.say("({d} available)", .{available.get(at)});
                face.drawMid(line.text(), mid, top, font.SMALL, LOSS);
                top += 22;
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
            line.say("+{d} to {s}", .{ n, switch (m) {
                .life => @as([:0]const u8, "maximum life"),
                .mana => "maximum mana",
                else => menu.named(m),
            } });
            face.drawMid(line.text(), mid, top, font.SMALL, look.WARD);
            top += 22;
        }
    }
}

fn change(face: *const font.Face, x: i32, y: i32, n: *usize, label: [:0]const u8, was: i32, now: i32, percent: bool) void {
    const delta = now - was;
    if (delta == 0) return;
    var text: menu.Note(100) = .{};
    text.say("{s}{d}{s} {s}", .{ if (delta > 0) @as([]const u8, "+") else "", delta, if (percent) @as([]const u8, "%") else "", label });
    face.draw(text.text(), x + @as(i32, @intCast(n.* % 2)) * (CARD_W + CARD_GAP), y + @as(i32, @intCast(n.* / 2)) * 20, font.SMALL, if (delta > 0) GAIN else LOSS);
    n.* += 1;
}

fn drawChanges(face: *const font.Face, x: i32, y: i32, was: attr.Attrs, now: attr.Attrs) void {
    face.draw("IF EQUIPPED", x, y, 16, look.DIM);
    var n: usize = 0;
    const top = y + 22;
    change(face, x, top, &n, "maximum life", was.life(), now.life(), false);
    change(face, x, top, &n, "maximum mana", was.mana(), now.mana(), false);
    for (attr.ATTRS) |at| change(face, x, top, &n, menu.named(at), was.get(at), now.get(at), false);
    change(face, x, top, &n, "physical reduction", was.reduction(), now.reduction(), true);
    change(face, x, top, &n, "critical chance", @intCast(was.crit()), @intCast(now.crit()), true);
    change(face, x, top, &n, "dodge chance", @intCast(was.dodge()), @intCast(now.dodge()), true);
    for (attr.STYLES) |s| change(face, x, top, &n, damageLabel(s), was.increase(s), now.increase(s), true);
    if (n == 0) face.draw("No attribute or defense changes.", x, top, font.SMALL, look.DIM);
}

fn damageLabel(s: attr.Style) [:0]const u8 {
    return switch (s) {
        .heavy => "heavy damage bonus",
        .light => "light damage bonus",
        .spell => "spell damage bonus",
    };
}

fn stat(face: *const font.Face, x: i32, y: i32, label: [:0]const u8, number: i32, prefix: []const u8, suffix: []const u8) void {
    face.draw(label, x, y, font.BODY, look.TEXT);
    var text: menu.Note(48) = .{};
    text.say("{s}{d}{s}", .{ prefix, number, suffix });
    face.draw(text.text(), x + 440 - face.width(text.text(), font.BODY), y, font.BODY, look.TEXT);
}

fn section(face: *const font.Face, x: i32, y: i32, title: [:0]const u8) void {
    face.draw(title, x, y, font.SMALL, look.UI_FOCUS);
    rl.drawLine(x, y + 25, x + 440, y + 25, look.EDGE);
}

fn drawStats(face: *const font.Face, o: P, v: View) void {
    const a = v.stats();
    const x = o.x + 40;
    const right = o.x + RIGHT;
    const y = o.y + TOP;
    section(face, x, y, "ATTRIBUTES");
    for (attr.ATTRS, 0..) |at, i| {
        const top = y + 38 + @as(i32, @intCast(i)) * 58;
        stat(face, x, top, menu.named(at), a.get(at), "", "");
        face.draw(switch (at) {
            .strength => "Life and heavy weapon damage",
            .dexterity => "Light weapons, critical chance and dodge",
            .intelligence => "Mana and spell damage",
        }, x, top + 25, font.SMALL, look.DIM);
    }
    section(face, x, y + 226, "SURVIVAL");
    stat(face, x, y + 264, "Maximum life", a.life(), "", "");
    stat(face, x, y + 294, "Maximum mana", a.mana(), "", "");
    stat(face, x, y + 324, "Physical damage reduction", a.reduction(), "", "%");
    stat(face, x, y + 354, "Chance to dodge", @intCast(a.dodge()), "", "%");
    var note: menu.Note(100) = .{};
    note.say("Physical reduction is capped at {d}%.", .{attr.ARMOUR_MAX});
    face.draw(note.text(), x, y + 391, font.SMALL, look.DIM);
    section(face, right, y, "DAMAGE BONUSES");
    const names = [_][:0]const u8{ "Heavy weapon damage", "Light weapon damage", "Spell damage" };
    for (attr.STYLES, names, 0..) |s, name, i| stat(face, right, y + 38 + @as(i32, @intCast(i)) * 30, name, a.increase(s), "+", "%");
    face.draw("Bonuses to base damage; skill ranks add their own.", right, y + 139, font.SMALL, look.DIM);
    stat(face, right, y + 180, "Critical strike chance", @intCast(a.crit()), "", "%");
    stat(face, right, y + 210, "Critical damage multiplier", attr.CRIT_MULTI, "", "%");
    section(face, right, y + 272, "PROGRESSION");
    stat(face, right, y + 310, "Passive points available", v.growth.passive_points, "", "");
    stat(face, right, y + 340, "Active skill points available", v.growth.active_points, "", "");
    stat(face, right, y + 390, "Gold", v.gold, "", "");
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
    const surface = menu.Surface.of(screen, .{ .x = W, .y = H });
    const box = actionBox(.{ .x = 0, .y = 0 }, 0);
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
    std.debug.print("item cards: 2-hand displacement, self-funding and both ring destinations; inventory unchanged\n", .{});
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
    const surface = menu.Surface.of(screen, .{ .x = W, .y = H });
    _ = book.step(&.{ .pointer = .{ .x = @intFromFloat(surface.offset.x + canvas.x * surface.scale), .y = @intFromFloat(surface.offset.y + canvas.y * surface.scale) }, .scroll = -1 }, screen, v);
    try std.testing.expect(book.treeActive() and book.zoom < trees.ZOOM_START);
    std.debug.print("tree book: spatial browsing and zoom spend no points; passive and skill selection return one command\n", .{});
}
