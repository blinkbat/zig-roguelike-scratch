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
/// The value beside a label in a pair.
const VALUE_X = 300;
/// The confirmation panel, and its two buttons along its foot.
const PROMPT_AT: P = .{ .x = 240, .y = 210 };
const PROMPT_W = 620;
const PROMPT_H = 210;
const PROMPT_PAD = 24;
const CONFIRM_GAP = 28;
const CONFIRM_Y = 154;
const BUTTON_H = 36;
/// Sideways distance between cells costs this much more than distance ahead.
const CELL_ACROSS: f32 = 2;
/// Columns of a was/now/change table, from its label.
const WAS_X = 240;
const NOW_X = 340;
const DELTA_X = 420;
/// The most cells any page lays out by box.
const CELLS_MAX = @max(progress.NODES.len, items.SLOTS.len);
/// "Requires   STR {[strength]d} ..." over `attrs.Needs`.
const REQUIRES = blk: {
    var s: []const u8 = "Requires";
    for (attr.ATTRS, 0..) |at, i| s = s ++ (if (i == 0) "   " else "    ") ++ menu.caps(@tagName(at)[0..3]) ++ " {[" ++ @tagName(at) ++ "]d}";
    break :blk s;
};
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

    fn command(n: Nearby) Command {
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
    };
}
pub const Book = struct {
    page: Page = .equipment,
    tabs: bool = true,
    cursor: usize = 0,
    zoom: f32 = 1,
    actions: ?usize = null,
    prompt: ?Command = null,
    yes: bool = false,
    direct: bool = false,
    message: menu.Note(80) = .{},

    pub fn open(self: *Book) void {
        if (self.page == .nearby) self.choose(.equipment);
        self.tabs = true;
        self.actions = null;
        self.prompt = null;
        self.direct = false;
        self.message.clear();
    }
    pub fn choose(self: *Book, page: Page) void {
        self.page = page;
        self.cursor = 0;
        self.zoom = 1;
        self.tabs = page != .nearby;
        self.actions = null;
        self.prompt = null;
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
    fn ask(self: *Book, command: Command) void {
        self.prompt = command;
        self.yes = false;
        self.actions = null;
        self.message.clear();
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
        return .{ .cursor = self.cursor, .zoom = self.zoom };
    }
    fn zoomBy(self: *Book, amount: f32) void {
        self.zoom = std.math.clamp(self.zoom + amount, trees.ZOOM_MIN, trees.ZOOM_MAX);
    }
    fn inWindow(self: *const Book, i: usize) bool {
        return !self.listed() or (i >= self.first() and i < self.first() + VISIBLE);
    }
    /// From the tabs into the page's cells; the passive tree starts on the class's own node.
    fn enter(self: *Book, v: View) void {
        if (self.count(v) == 0) return;
        self.tabs = false;
        if (self.page == .passives) self.cursor = progress.start(v.class);
    }
    fn selected(self: *const Book, v: View) ?items.Item {
        return switch (self.page) {
            .equipment => v.inventory.gear.slots.get(items.SLOTS[self.cursor]),
            .inventory => if (self.cursor < v.inventory.n) v.inventory.bag[self.cursor] else null,
            .nearby => if (self.cursor < v.nearby.len) v.nearby[self.cursor].item else null,
            else => null,
        };
    }
    /// An inventory item's actions: equip to each slot it fits, then drop.
    fn actionCount(self: *const Book, v: View) usize {
        if (self.page != .inventory) return 1;
        const it = self.selected(v) orelse return 1;
        return it.kind.slots().len + 1;
    }
    fn select(self: *Book, v: View) void {
        if (self.cursor >= self.count(v)) return;
        switch (self.page) {
            .equipment => if (self.selected(v) != null) {
                self.ask(.{ .unequip = items.SLOTS[self.cursor] });
            } else {
                self.choose(.inventory);
            },
            .inventory => self.actions = 0,
            .stats => {},
            .passives => if (v.growth.passive_points > 0 and v.growth.available(self.cursor)) {
                self.ask(.{ .passive = self.cursor });
            },
            .skills => {
                const act = progress.skills(v.class)[self.cursor].act;
                if (v.growth.canLearn(v.class, act)) self.ask(.{ .skill = act });
            },
            .nearby => self.ask(v.nearby[self.cursor].command()),
        }
    }
    fn action(self: *Book, v: View, i: usize) void {
        const it = self.selected(v) orelse return;
        const slots = it.kind.slots();
        if (i == slots.len) {
            self.ask(.{ .drop = self.cursor });
        } else self.ask(.{ .equip = .{ .index = self.cursor, .slot = slots[i] } });
    }
    pub fn step(self: *Book, st: *const input.State, screen: P, v: View) ?Command {
        const o = originOf(screen);
        self.cursor = @min(self.cursor, self.count(v) -| 1);
        if (self.prompt) |cmd| {
            if (menu.backed(st)) {
                self.prompt = null;
                return null;
            }
            if (st.walk) |d| {
                if (d.delta().x != 0) self.yes = d.delta().x > 0;
            }
            if (st.click) if (st.pointer) |p| {
                for (0..2) |i| if (look.holds(confirmBox(o, i), p)) {
                    self.prompt = null;
                    return if (i == 1) cmd else null;
                };
            };
            if (st.hit(menu.CONFIRM)) {
                self.prompt = null;
                return if (self.yes) cmd else null;
            }
            return null;
        }
        if (self.actions) |a| {
            if (menu.backed(st)) {
                self.actions = null;
                return null;
            }
            if (st.walk) |d| {
                const delta = d.delta();
                self.actions = mathx.wrap(a, if (delta.x != 0) delta.x else delta.y, self.actionCount(v));
            }
            if (st.click) if (st.pointer) |p| {
                for (0..self.actionCount(v)) |i| if (look.holds(actionBox(o, i), p)) {
                    self.action(v, i);
                    return null;
                };
            };
            if (st.hit(menu.CONFIRM)) self.action(v, self.actions.?);
            return null;
        }
        if (menu.backed(st)) {
            if (!self.tabs and !self.direct) {
                self.tabs = true;
                return null;
            }
            return .close;
        }
        if (self.page == .passives and !self.tabs) {
            if (st.hit(menu.CHANGE)) self.zoomBy(0.4);
            if (st.hit(menu.REMOVE)) self.zoomBy(-0.4);
            if (st.pointer) |p| if (trees.onCanvas(o, p)) {
                if (st.scroll != 0) self.zoomBy(@as(f32, @floatFromInt(st.scroll)) * 0.2);
            };
        }
        if (self.listed() and st.scroll != 0 and self.count(v) > 0) {
            self.cursor = mathx.nudge(self.cursor, -st.scroll, self.count(v));
            self.tabs = false;
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
                    self.tabs = false;
                    self.zoomBy(if (increase) 0.4 else -0.4);
                    return null;
                };
            }
            const primary = if (self.treePanel() != null) trees.actionBox(o) else actionBox(o, 0);
            if (!self.tabs and look.holds(primary, p)) {
                self.select(v);
                return null;
            }
            for (0..self.count(v)) |i| {
                if (!self.inWindow(i)) continue;
                if (self.page == .passives and !trees.onCanvas(o, p)) continue;
                if (look.holds(self.cellBox(o, i, v), p)) {
                    self.cursor = i;
                    self.tabs = false;
                    return null;
                }
            }
        };
        if (st.walk) |dir| {
            const d = dir.delta();
            if (self.tabs) {
                if (d.x != 0) self.choose(mathx.stepIn(Page, &PAGES, self.page, d.x, 0)) else if (d.y > 0) self.enter(v);
                if (self.tabs and self.page == .passives) self.cursor = progress.start(v.class);
            } else if (self.listed()) {
                if (d.y < 0 and self.cursor == 0 and !self.direct) self.tabs = true else if (d.y != 0 and self.count(v) > 0) self.cursor = mathx.wrap(self.cursor, d.y, self.count(v));
            } else if (self.page == .passives) {
                const next = progress.passives.step(self.cursor, @floatFromInt(d.x), @floatFromInt(d.y));
                if (next != self.cursor) self.cursor = next else if (d.y < 0) self.tabs = true;
            } else if (self.count(v) > 0) {
                var boxes: [CELLS_MAX]rl.Rectangle = undefined;
                for (0..self.count(v)) |i| boxes[i] = self.cellBox(o, i, v);
                if (menu.nearest(boxes[self.cursor], boxes[0..self.count(v)], dir, CELL_ACROSS)) |i| self.cursor = i else if (d.y < 0 and !self.direct) self.tabs = true;
            }
        }
        if (st.hit(menu.CONFIRM)) {
            if (self.tabs) self.enter(v) else self.select(v);
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
    pub fn draw(self: *const Book, face: *const font.Face, sprites: *const look.Sprites, screen: P, v: View) void {
        const o = originOf(screen);
        look.hudPanel(sprites, o.x, o.y, W, H, look.CARD_BG, look.LIT);
        var who: menu.Note(100) = .{};
        who.say("{s}   {s}", .{ v.name, v.class.title() });
        face.draw(who.text(), o.x + LIST_X, o.y + 22, font.HEAD, look.TEXT);
        var xp: menu.Note(100) = .{};
        xp.say("Level  {d}     XP  {d} / {d}", .{ v.growth.level, v.growth.xp, v.growth.needed() });
        face.draw(xp.text(), o.x + RIGHT, o.y + 26, font.BODY, look.TEXT);
        button(face, closeBox(o), verbOf(.close), false);
        if (self.direct) face.draw("NEARBY", o.x + LIST_X, o.y + 82, font.HEAD, look.TEXT) else for (PAGES, 0..) |page, i| button(face, tabBox(o, i), menu.named(page), self.page == page);
        if (self.treePanel() == null) rl.drawLine(o.x + DIVIDER_X, o.y + TOP, o.x + DIVIDER_X, o.y + H - 30, look.EDGE);
        if (self.treePanel()) |panel| {
            trees.draw(panel, face, sprites, o, v.class, v.growth, self.treeView(), !self.tabs);
        } else if (self.page == .stats) {
            const a = v.stats();
            var left = Rows{ .x = o.x + 40, .y = o.y + TOP };
            for (attr.ATTRS) |at| left.put(face, menu.named(at), a.get(at));
            left.gap();
            left.put(face, "Maximum life", a.life());
            left.put(face, "Maximum mana", a.mana());
            left.put(face, "Physical reduction %", a.reduction());
            left.put(face, "Dodge %", a.dodge());
            left.gap();
            left.put(face, "Gold", v.gold);
            var right = Rows{ .x = o.x + RIGHT, .y = o.y + TOP };
            for (attr.STYLES) |s| right.put(face, menu.named(s), a.increase(s));
            right.gap();
            right.put(face, "Critical chance %", a.crit());
            right.put(face, "Critical damage %", attr.CRIT_MULTI);
            right.gap();
            right.put(face, "Passive points", v.growth.passive_points);
            right.put(face, "Active points", v.growth.active_points);
        } else {
            self.drawCells(face, o, v);
            self.drawDetail(face, o, v);
        }
        if (self.message.n > 0) face.draw(self.message.text(), o.x + (if (self.treePanel() != null) @as(i32, 764) else RIGHT), o.y + H - 32, font.SMALL, look.TEXT);
        if (self.prompt) |cmd| {
            const p = o.add(PROMPT_AT);
            look.hudPanel(sprites, p.x, p.y, PROMPT_W, PROMPT_H, look.CARD_BG, look.LIT);
            face.draw(cmd.verb(), p.x + PROMPT_PAD, p.y + 22, font.HEAD, look.TEXT);
            const target: [:0]const u8 = switch (cmd) {
                .equip, .drop, .pickup => if (self.selected(v)) |it| it.name() else "Item",
                .unequip => |s| s.name(),
                .skill => |a| a.name(),
                .passive => |i| progress.NODES[i].name,
                .open_chest => CHEST,
                .travel => DOOR,
                .close => "",
            };
            pair(face, p.x + PROMPT_PAD, p.y + 66, "Target", target);
            pair(face, p.x + PROMPT_PAD, p.y + 100, "Cost", switch (cmd) {
                .passive => @as([:0]const u8, "1 passive point"),
                .skill => @as([:0]const u8, "1 active point"),
                .close => "",
                .equip, .unequip, .drop, .pickup, .open_chest, .travel => @as([:0]const u8, "1 turn"),
            });
            button(face, confirmBox(o, 0), "Cancel", !self.yes);
            button(face, confirmBox(o, 1), "Confirm", self.yes);
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
            const chosen = !self.tabs and i == self.cursor;
            rl.drawRectangleRec(r, look.BG);
            rl.drawRectangleLinesEx(r, if (chosen) 2 else 1, if (chosen) look.RETICLE else look.EDGE);
            switch (self.page) {
                .equipment => {
                    const slot = items.SLOTS[i];
                    face.draw(slotLabel(slot), x + 4, y + 4, font.TINY, look.DIM);
                    const it = v.inventory.gear.slots.get(slot);
                    const mid = look.middleAt(r);
                    face.centred(if (it) |a| menu.named(a.kind) else "-", mid.x, mid.y + 8, if (r.width < 60) font.TINY else font.SMALL, look.TEXT);
                },
                .inventory => {
                    const it = v.inventory.bag[i];
                    const slots = it.kind.slots();
                    face.draw(it.name(), x + TEXT_X, y + 4, font.BODY, if (it.magical()) look.WARD else look.TEXT);
                    face.draw(if (slots.len > 1) menu.named(it.kind) else slots[0].name(), x + SECOND_X, y + 5, font.SMALL, look.DIM);
                },
                .nearby => {
                    const n = v.nearby[i];
                    face.draw(n.label(), x + TEXT_X, y + 4, font.BODY, look.TEXT);
                    face.draw(n.command().verb(), x + SECOND_X, y + 5, font.SMALL, look.DIM);
                },
                .passives, .skills, .stats => unreachable,
            }
        }
    }
    /// Judged as the equip or unequip would: without the item displaced, or the worn item itself.
    fn requirementMet(self: *const Book, v: View, it: items.Item, slot: items.Slot) bool {
        return switch (self.page) {
            .inventory => if (v.inventory.swapped(self.cursor, slot)) |after| after.wornMeets(slot, v.base) else |_| it.meets(v.stats()),
            .equipment => v.inventory.gear.wornMeets(slot, v.base),
            else => it.meets(v.stats()),
        };
    }
    fn drawDetail(self: *const Book, face: *const font.Face, o: P, v: View) void {
        const x = o.x + RIGHT;
        const y = o.y + TOP;
        if (self.count(v) == 0) return;
        var rows = Rows{ .x = x, .y = y, .n = TITLE_ROWS };
        const it = self.selected(v) orelse {
            face.draw(if (self.page == .nearby) v.nearby[self.cursor].label() else "Empty slot", x, y, font.HEAD, look.TEXT);
            button(face, actionBox(o, 0), if (self.page == .nearby) "Interact" else "Inventory", !self.tabs);
            return;
        };
        const spec = items.spec(it.kind);
        const asked: ?items.Slot = if (self.prompt) |cmd| switch (cmd) {
            .equip => |e| e.slot,
            else => null,
        } else null;
        const slots = it.kind.slots();
        const slot = asked orelse if (self.page == .equipment) items.SLOTS[self.cursor] else if (self.actions) |a| slots[if (a < slots.len) a else 0] else slots[0];
        const worn = v.inventory.gear.slots.get(slot);
        face.draw(it.name(), x, y, font.HEAD, look.TEXT);
        face.draw(if (spec.two_handed) "Two hands" else slot.name(), x, y + 32, font.SMALL, look.DIM);
        header(face, x, rows.next(), "WORN", "ITEM");
        const was = if (worn) |w| items.spec(w.kind) else null;
        const hit = spec.damage orelse NO_DAMAGE;
        const had = if (was) |w| w.damage orelse NO_DAMAGE else NO_DAMAGE;
        comparison(face, x, rows.next(), "Min damage", had.lo, hit.lo);
        comparison(face, x, rows.next(), "Max damage", had.hi, hit.hi);
        comparison(face, x, rows.next(), "Reduction %", if (was) |w| w.armour else 0, spec.armour);
        for (items.MODS) |m| comparison(face, x, rows.next(), menu.named(m), if (worn) |w| w.value(m) else 0, it.value(m));
        var req: menu.Note(100) = .{};
        req.say(REQUIRES, spec.needs);
        face.draw(req.text(), x, rows.next(), font.SMALL, if (self.requirementMet(v, it, slot)) look.DIM else look.RETICLE);
        if (self.page == .inventory) {
            const at = rows.next();
            if (v.inventory.preview(self.cursor, slot, v.base)) |after| {
                const a = after.stats(v.base);
                var total: menu.Note(100) = .{};
                total.say("After   Life {d}   Mana {d}   Reduction {d}%", .{ a.life(), a.mana(), a.reduction() });
                face.draw(total.text(), x, at, font.SMALL, look.TEXT);
                const moved_at = rows.next();
                for (items.SLOTS) |s| {
                    if (s == slot or !v.inventory.displaced(after, slot, s)) continue;
                    var moved: menu.Note(70) = .{};
                    moved.say("To inventory   {s}", .{s.name()});
                    face.draw(moved.text(), x, moved_at, font.SMALL, look.RETICLE);
                }
            } else |err| face.draw(items.caption(err), x, at, font.SMALL, look.RETICLE);
        }
        if (self.actions) |a| {
            for (0..self.actionCount(v)) |i| button(face, actionBox(o, i), if (i == slots.len) verbOf(.drop) else if (slots.len > 1) equipLabel(slots[i]) else verbOf(.equip), a == i);
        } else button(face, actionBox(o, 0), switch (self.page) {
            .equipment => verbOf(.unequip),
            .inventory => "Actions",
            .nearby => verbOf(.pickup),
            .stats, .passives, .skills => unreachable,
        }, !self.tabs);
    }
};
fn originOf(screen: P) P {
    return .{ .x = @divTrunc(screen.x - W, 2), .y = @divTrunc(screen.y - H, 2) };
}
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
    return look.rect(o.x + W - 104, o.y + 18, 80, 32);
}
fn confirmBox(o: P, i: usize) rl.Rectangle {
    const p = o.add(PROMPT_AT);
    const w = @divExact(PROMPT_W - 2 * PROMPT_PAD - CONFIRM_GAP, 2);
    return look.rect(p.x + PROMPT_PAD + @as(i32, @intCast(i)) * (w + CONFIRM_GAP), p.y + CONFIRM_Y, w, BUTTON_H);
}
/// Short enough for a ring's small box.
fn slotLabel(s: items.Slot) [:0]const u8 {
    return switch (s) {
        .left_ring => "L ring",
        .right_ring => "R ring",
        .left_hand, .right_hand, .helm, .chest, .belt, .gloves, .boots, .amulet => s.name(),
    };
}
fn equipLabel(s: items.Slot) [:0]const u8 {
    return switch (s) {
        .left_ring => "Equip left",
        .right_ring => "Equip right",
        .left_hand, .right_hand, .helm, .chest, .belt, .gloves, .boots, .amulet => verbOf(.equip),
    };
}
const NO_DAMAGE = damage.Base{ .lo = 0, .hi = 0 };
/// The item detail's name and slot lines.
const TITLE_ROWS = 2;
/// Lines down a column, one `ROW` each.
const Rows = struct {
    x: i32,
    y: i32,
    n: usize = 0,
    fn next(r: *Rows) i32 {
        defer r.n += 1;
        return r.y + row(r.n);
    }
    fn gap(r: *Rows) void {
        r.n += 1;
    }
    fn put(r: *Rows, face: *const font.Face, text: [:0]const u8, n: anytype) void {
        pair(face, r.x, r.next(), text, n);
    }
};
fn button(face: *const font.Face, r: rl.Rectangle, text: [:0]const u8, on: bool) void {
    rl.drawRectangleLinesEx(r, if (on) 2 else 1, if (on) look.RETICLE else look.EDGE);
    const m = look.middleAt(r);
    face.centred(text, m.x, m.y, font.BODY, if (on) look.TEXT else look.DIM);
}
fn value(face: *const font.Face, x: i32, y: i32, n: anytype) void {
    var buf: [80]u8 = undefined;
    const s = if (@typeInfo(@TypeOf(n)) == .pointer) std.fmt.bufPrintZ(&buf, "{s}", .{n}) catch "" else std.fmt.bufPrintZ(&buf, "{d}", .{n}) catch "";
    face.draw(s, x, y, font.BODY, look.TEXT);
}
fn pair(face: *const font.Face, x: i32, y: i32, text: [:0]const u8, n: anytype) void {
    face.draw(text, x, y, font.BODY, look.DIM);
    value(face, x + VALUE_X, y, n);
}
fn header(face: *const font.Face, x: i32, y: i32, was: [:0]const u8, now: [:0]const u8) void {
    face.draw(was, x + WAS_X, y, font.SMALL, look.DIM);
    face.draw(now, x + NOW_X, y, font.SMALL, look.DIM);
    face.draw("DELTA", x + DELTA_X, y, font.SMALL, look.DIM);
}
fn comparison(face: *const font.Face, x: i32, y: i32, text: [:0]const u8, was: anytype, now: anytype) void {
    face.draw(text, x, y, font.BODY, look.DIM);
    value(face, x + WAS_X, y, was);
    value(face, x + NOW_X, y, now);
    var buf: [24]u8 = undefined;
    const delta = @as(i32, @intCast(now)) - @as(i32, @intCast(was));
    face.draw(std.fmt.bufPrintZ(&buf, "{s}{d}", .{ if (delta > 0) "+" else "", delta }) catch "", x + DELTA_X, y, 20, if (delta != 0) look.RETICLE else look.DIM);
}

test "item actions require deliberate confirmation and default to cancel" {
    var inv = items.Inventory{};
    try std.testing.expect(inv.add(.{ .kind = .cap }));
    var growth = progress.State.of(.archer);
    const v = View{ .class = .archer, .name = "Test", .inventory = &inv, .growth = &growth, .base = growth.attributes(.archer) };
    var book = Book{ .page = .inventory, .tabs = false };
    const screen = P{ .x = 1280, .y = 720 };
    var confirm = input.State{};
    confirm.pressed.insert(menu.CONFIRM);
    try std.testing.expect(book.step(&confirm, screen, v) == null);
    try std.testing.expect(book.actions != null);
    try std.testing.expect(book.step(&confirm, screen, v) == null);
    try std.testing.expect(book.prompt != null and !book.yes);
    try std.testing.expect(book.step(&confirm, screen, v) == null);
    try std.testing.expect(book.prompt == null);
    _ = book.step(&confirm, screen, v);
    _ = book.step(&confirm, screen, v);
    _ = book.step(&.{ .walk = .e }, screen, v);
    try std.testing.expect(book.step(&confirm, screen, v).? == .equip);
    try std.testing.expectEqual(@as(usize, 1), inv.n);
}

test "tree browsing zooms without spending and point prompts default to cancel" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    growth.passive_points = 2;
    growth.active_points = 2;
    const v = View{ .class = .archer, .name = "Test", .inventory = &inv, .growth = &growth, .base = growth.attributes(.archer) };
    const screen = P{ .x = 1280, .y = 720 };
    var book = Book{ .page = .passives, .tabs = false, .cursor = progress.passives.branchFirst(.rogue_evade) };
    var zoom = input.State{};
    zoom.pressed.insert(menu.CHANGE);
    _ = book.step(&zoom, screen, v);
    try std.testing.expect(book.zoom > 1);
    var confirm = input.State{};
    confirm.pressed.insert(menu.CONFIRM);
    _ = book.step(&confirm, screen, v);
    try std.testing.expect(book.prompt != null and !book.yes);
    _ = book.step(&confirm, screen, v);
    try std.testing.expect(book.prompt == null);
    try std.testing.expectEqual(@as(u16, 2), growth.passive_points);
    _ = book.step(&confirm, screen, v);
    _ = book.step(&.{ .walk = .e }, screen, v);
    try std.testing.expectEqual(book.cursor, book.step(&confirm, screen, v).?.passive);
    book.choose(.skills);
    book.tabs = false;
    book.cursor = 0;
    _ = book.step(&confirm, screen, v);
    try std.testing.expect(book.prompt != null and !book.yes);
    _ = book.step(&confirm, screen, v);
    try std.testing.expect(book.prompt == null);
    try std.testing.expectEqual(@as(u16, 2), growth.active_points);
    std.debug.print("tree book: spatial browsing and zoom spend no points; passive and skill prompts default to cancel\n", .{});
}
