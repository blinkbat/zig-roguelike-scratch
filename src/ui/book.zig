const character_view = @import("character_view.zig");
const layout = @import("character_layout.zig");
const item_card = @import("item_card.zig");
const character_stats = @import("character_stats.zig");
pub const Page = character_view.Page;
pub const PAGES = character_view.PAGES;
pub const Nearby = character_view.Nearby;
pub const View = character_view.View;
pub const Command = character_view.Command;
pub const SIZE = layout.SIZE;
pub const verifyCards = item_card.verify;
pub const verifyStats = character_stats.verify;
const BOTH_HANDS = "Both hands";
const BOTH_IN_USE = BOTH_HANDS ++ " in use";
const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const hero = @import("../play/hero.zig");
const attr = @import("../play/attrs.zig");
const items = @import("../play/items.zig");
const consumable = @import("../play/consumable.zig");
const progress = @import("../play/progress.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const line_icons = @import("../gfx/line_icons.zig");
const font = @import("../gfx/font.zig");
const menu = @import("menu.zig");
const trees = @import("trees.zig");
const display = @import("../core/window.zig");
const P = mathx.P;
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
    fn selectedSkill(self: *const Book, view: View) skillbar.Act {
        return progress.skills(view.class)[self.cursor].act;
    }
    fn count(self: *const Book, view: View) usize {
        return switch (self.page) {
            .equipment => items.SLOTS.len,
            .inventory => stocked(view) + view.inventory.n,
            .stats => 0,
            .passives => progress.NODES.len,
            .skills => progress.skills(view.class).len,
            .nearby, .loot => view.nearby.len,
        };
    }
    fn settledTop(self: *const Book, view: View) usize {
        const visible = self.visibleRows();
        return @min(mathx.reveal(self.top, self.cursor, visible), self.count(view) -| visible);
    }
    /// A scrolling list rather than laid-out cells.
    fn listed(self: *const Book) bool {
        return self.page == .inventory or self.direct();
    }
    fn treePanel(self: *const Book) ?trees.Panel {
        return switch (self.page) {
            .passives => .passives,
            .skills => .skills,
            .equipment, .inventory, .stats, .nearby, .loot => null,
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
    pub fn enter(self: *Book, view: View) void {
        if (self.count(view) == 0) return;
        if (self.page == .passives) self.browse(progress.start(view.class));
    }
    /// The bag item under the cursor; carried consumables list above the bag.
    fn bagIndex(self: *const Book, view: View) ?usize {
        const above = stocked(view);
        return if (self.cursor >= above and self.cursor - above < view.inventory.n) self.cursor - above else null;
    }
    fn carriedRow(self: *const Book, view: View) ?consumable.Kind {
        return if (self.page == .inventory) stockAt(view, self.cursor) else null;
    }
    fn selected(self: *const Book, view: View) ?items.Item {
        return switch (self.page) {
            .equipment => view.inventory.gear.slots.get(items.SLOTS[self.cursor]),
            .inventory => if (self.bagIndex(view)) |b| view.inventory.bag[b] else null,
            .nearby, .loot => if (self.cursor < view.nearby.len) view.nearby[self.cursor].item() else null,
            .stats, .passives, .skills => null,
        };
    }
    fn destination(self: *const Book, view: View) items.Slot {
        const it = self.selected(view).?;
        const slots = it.kind.slots();
        return slots[@min(self.destination_index, slots.len - 1)];
    }
    fn select(self: *Book, view: View) ?Command {
        if (self.cursor >= self.count(view)) return null;
        return switch (self.page) {
            .equipment => if (self.selected(view) != null) .{ .unequip = items.SLOTS[self.cursor] } else blk: {
                self.choose(.inventory);
                break :blk null;
            },
            .inventory => if (stockAt(view, self.cursor)) |k| .{ .use = k } else .{ .equip = .{ .index = self.bagIndex(view).?, .slot = self.destination(view) } },
            .stats => null,
            .passives => if (view.growth.canAllocate(self.cursor)) .{ .passive = self.cursor } else null,
            .skills => blk: {
                const act = self.selectedSkill(view);
                break :blk if (view.growth.canLearn(view.class, act)) .{ .skill = act } else null;
            },
            .nearby, .loot => view.nearby[self.cursor].command(),
        };
    }
    fn size(self: *const Book, view: View) P {
        return switch (self.page) {
            .loot => layout.LOOT_SIZE,
            .nearby => .{ .x = layout.DIRECT_W, .y = self.nearbyActionY(view) + layout.ACTION_H + menu.PANEL_PAD },
            .equipment, .inventory, .stats, .passives, .skills => layout.SIZE,
        };
    }
    pub fn surface(self: *const Book, screen: P, view: View) menu.Surface {
        return if (self.direct()) menu.Surface.like(screen, self.size(view), layout.SIZE) else menu.Surface.of(screen, layout.SIZE);
    }
    fn directTop(self: *const Book) i32 {
        return if (self.page == .loot) layout.LOOT_TOP else layout.CLOSE_Y + layout.CLOSE_H + layout.DIRECT_GAP;
    }
    fn visibleRows(self: *const Book) usize {
        return switch (self.page) {
            .loot => layout.LOOT_ROWS,
            .nearby => layout.DIRECT_VISIBLE_ROWS,
            .equipment, .inventory, .stats, .passives, .skills => layout.VISIBLE_ROWS,
        };
    }
    fn noteY(self: *const Book, view: View) i32 {
        if (self.page == .loot) return font.Face.topFor(layout.LOOT_FOOT_Y + layout.ACTION_H / 2, font.SMALL);
        return self.directTop() + @as(i32, @intCast(@min(self.count(view), self.visibleRows()))) * layout.ROW_HEIGHT + layout.DIRECT_GAP;
    }
    fn nearbyActionY(self: *const Book, view: View) i32 {
        return self.noteY(view) + font.SMALL + layout.DIRECT_GAP;
    }
    pub fn step(self: *Book, state: *const input.State, screen: P, view: View) ?Command {
        var local = state.*;
        if (local.pointer) |p| local.pointer = self.surface(screen, view).point(p);
        const st = &local;
        self.cursor = @min(self.cursor, self.count(view) -| 1);
        const previous_cursor = self.cursor;
        const previous_page = self.page;
        defer {
            if (self.cursor != previous_cursor or self.page != previous_page) {
                self.message.clear();
                self.destination_index = 0;
            }
            self.top = self.settledTop(view);
        }
        self.top = self.settledTop(view);
        if (local.click) if (local.pointer) |p| if (self.buttonAt(p, view)) |b| {
            if (self.page == .passives and b == input.TreeKeys.PAD_OVERVIEW) local.tree.reset = true else local.pressed.insert(b);
            local.click = false;
        };
        if (menu.closed(st)) return .close;
        if (self.page == .loot and self.count(view) > 0 and st.hit(menu.CHANGE)) return .take_all;
        if (!self.direct() and (st.hit(menu.PAGE_PREV) or st.hit(menu.PAGE_NEXT))) {
            self.choose(mathx.stepIn(Page, &PAGES, self.page, if (st.hit(menu.PAGE_PREV)) -1 else 1, 0));
            self.enter(view);
            return null;
        }
        if (self.page == .inventory and self.selected(view) != null) {
            if (st.hit(menu.REMOVE)) return .{ .drop = self.bagIndex(view).? };
            if (st.hit(menu.CHANGE)) self.destination_index = mathx.wrap(self.destination_index, 1, self.selected(view).?.kind.slots().len);
        }
        if (self.page == .skills and st.hit(menu.CHANGE)) return .{ .bindings = self.selectedSkill(view) };
        if (self.page == .stats and st.hit(menu.CHANGE)) self.advanced = !self.advanced;
        if (self.page == .passives) {
            if (!st.dragging) self.mouse_panning = false;
            if (st.middle_click) if (st.pointer) |p| {
                self.mouse_panning = trees.onCanvas(p);
            };
            if (self.mouse_panning) {
                const scale = self.surface(screen, view).scale;
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
        if (self.listed() and self.count(view) > 0) self.cursor = st.scrolled(self.cursor, self.count(view));
        if (st.click and !self.mouse_panning) if (st.pointer) |p| {
            if (!self.direct()) for (PAGES, 0..) |page, i| if (raster.holds(layout.tabBox(i), p)) {
                self.choose(page);
                self.enter(view);
                return null;
            };
            for (0..self.count(view)) |i| {
                if (!self.inWindow(i)) continue;
                if (self.page == .passives and !trees.onCanvas(p)) continue;
                if (raster.holds(self.cellBox(i, view), p)) {
                    self.browse(i);
                    return null;
                }
            }
        };
        if (st.walk) |dir| {
            const d = dir.delta();
            if (self.listed()) {
                if (d.y != 0 and self.count(view) > 0) self.cursor = mathx.wrap(self.cursor, d.y, self.count(view));
            } else if (self.page == .passives) {
                self.walkTree(@floatFromInt(d.x), @floatFromInt(d.y));
            } else if (self.count(view) > 0) {
                var boxes: [layout.CELLS_MAX]rl.Rectangle = undefined;
                for (0..self.count(view)) |i| boxes[i] = self.cellBox(i, view);
                if (menu.nearest(boxes[self.cursor], boxes[0..self.count(view)], dir)) |i| self.cursor = i;
            }
        }
        if (st.hit(menu.CONFIRM)) {
            return self.select(view);
        }
        return null;
    }
    /// The button whose box is under `p`, so a click there is that button's press.
    fn buttonAt(self: *const Book, p: P, view: View) ?input.Button {
        if (!self.direct()) {
            if (raster.holds(layout.shoulderBox(false), p)) return menu.PAGE_PREV;
            if (raster.holds(layout.shoulderBox(true), p)) return menu.PAGE_NEXT;
        }
        const shown = self.controls(view);
        for (shown.all[0..shown.n]) |c| if (raster.holds(c.box, p)) return c.button;
        return null;
    }
    /// Every button the page shows, the close button first.
    fn controls(self: *const Book, view: View) Controls {
        var c: Controls = .{};
        c.add(self.closeBox(view), menu.BACK, .{ .label = character_view.verbOf(.close) });
        switch (self.page) {
            .passives => {
                for ([_]bool{ false, true }) |increase| c.add(trees.zoomBox(increase), if (increase) menu.CHANGE else menu.REMOVE, .drawn);
                c.add(trees.overviewBox(), input.TreeKeys.PAD_OVERVIEW, .drawn);
                if (!view.growth.nodes.isSet(self.cursor)) c.add(trees.actionBox(), menu.CONFIRM, .{ .prompt = if (view.growth.canAllocate(self.cursor)) 1 else look.FADED_A });
            },
            .skills => {
                const act = self.selectedSkill(view);
                c.add(trees.bindBox(), menu.CHANGE, .{ .label = if (view.growth.unlocked(act)) character_view.verbOf(.bindings) else "Bindings" });
                c.add(trees.actionBox(), menu.CONFIRM, .{ .prompt = if (view.growth.canLearn(view.class, act)) 1 else look.FADED_A });
            },
            .stats => c.add(self.actionBox(menu.CHANGE, view), menu.CHANGE, .{ .label = if (self.advanced) "Main stats" else "Advanced" }),
            .equipment, .inventory, .nearby, .loot => if (self.count(view) > 0) {
                const it = self.selected(view) orelse {
                    c.add(self.actionBox(menu.CONFIRM, view), menu.CONFIRM, .{ .label = if (self.direct()) view.nearby[self.cursor].command().verb() else if (self.carriedRow(view) != null) character_view.verbOf(.use) else "Inventory" });
                    if (self.page == .loot) c.add(self.actionBox(menu.CHANGE, view), menu.CHANGE, .{ .label = character_view.verbOf(.take_all) });
                    return c;
                };
                c.add(self.actionBox(menu.CONFIRM, view), menu.CONFIRM, .{ .label = switch (self.page) {
                    .equipment => character_view.verbOf(.unequip),
                    .inventory => character_view.verbOf(.equip),
                    .nearby, .loot => character_view.verbOf(.pickup),
                    .stats, .passives, .skills => unreachable,
                } });
                if (self.page == .loot) c.add(self.actionBox(menu.CHANGE, view), menu.CHANGE, .{ .label = character_view.verbOf(.take_all) });
                if (self.page == .inventory) {
                    if (it.kind.slots().len > 1) c.add(self.actionBox(menu.CHANGE, view), menu.CHANGE, .{ .label = slotLabel(self.destination(view)) });
                    c.add(self.actionBox(menu.REMOVE, view), menu.REMOVE, .{ .label = character_view.verbOf(.drop) });
                }
            },
        }
        return c;
    }
    pub fn actionBox(self: *const Book, b: input.Button, view: View) rl.Rectangle {
        const i: i32 = @intCast(std.mem.indexOfScalar(input.Button, &ACTIONS, b).?);
        const at: P = switch (self.page) {
            .loot => .{ .x = layout.DETAIL_X, .y = layout.LOOT_FOOT_Y },
            .nearby => .{ .x = layout.LIST_X, .y = self.nearbyActionY(view) },
            .equipment, .inventory, .stats, .passives, .skills => .{ .x = layout.DETAIL_X, .y = layout.ACTION_Y },
        };
        return raster.rect(at.x + i * (layout.ACTION_W + menu.ACTION_GAP), at.y, layout.ACTION_W, layout.ACTION_H);
    }
    fn closeBox(self: *const Book, view: View) rl.Rectangle {
        return raster.rect(self.size(view).x - layout.LIST_X - layout.CLOSE_W, layout.CLOSE_Y, layout.CLOSE_W, layout.CLOSE_H);
    }
    fn cellBox(self: *const Book, i: usize, view: View) rl.Rectangle {
        const y = layout.CONTENT_TOP;
        return switch (self.page) {
            .equipment => blk: {
                const s = layout.SLOT_BOX.get(items.SLOTS[i]);
                break :blk raster.rect(s.at.x, y + s.at.y, s.w, s.h);
            },
            .inventory, .nearby, .loot => raster.rect(layout.LIST_X, (if (self.direct()) self.directTop() else y + layout.LIST_Y) + (@as(i32, @intCast(i)) - @as(i32, @intCast(self.top))) * layout.ROW_HEIGHT, layout.LIST_W, layout.ROW_HEIGHT),
            .passives, .skills => trees.cellBox(self.treePanel().?, view.class, i, self.treeView()),
            .stats => unreachable,
        };
    }
    /// A command can shrink the list under the cursor before the next `step` clamps it.
    pub fn draw(self: *const Book, source_face: *const font.Face, sprites: *const look.Sprites, screen: P, view: View) void {
        var shown = self.*;
        shown.cursor = @min(self.cursor, self.count(view) -| 1);
        shown.top = shown.settledTop(view);
        shown.drawClamped(source_face, sprites, screen, view);
    }
    fn drawClamped(self: *const Book, source_face: *const font.Face, sprites: *const look.Sprites, screen: P, view: View) void {
        const on = self.surface(screen, view);
        on.beginPanel(sprites, self.size(view));
        defer rl.endMode2D();
        const scaled_face = on.faceFor(source_face.*);
        const face = &scaled_face;
        if (self.direct()) {
            self.drawDirect(face, sprites, view);
        } else {
            var who: menu.Note(100) = .{};
            who.say("{s}   {s}", .{ view.name, view.class.title() });
            header(face, who.text());
            var xp: menu.Note(100) = .{};
            xp.say("Level  {d}     XP  {d} / {d}", .{ view.growth.level, view.growth.xp, view.growth.needed() });
            face.drawMiddle(xp.text(), layout.DETAIL_X, layout.HEADER_MID, font.SMALL, look.DIM);
            for (PAGES, 0..) |page, i| tab(face, layout.tabBox(i), page, self.page == page, view.device);
            if (self.treePanel() == null) rl.drawLine(layout.DIVIDER_X, layout.CONTENT_TOP, layout.DIVIDER_X, layout.DIVIDER_FOOT, look.EDGE);
            if (self.treePanel()) |panel| {
                trees.draw(panel, face, sprites, view.class, view.growth, self.treeView(), view.device, .{ .stats = view.stats(), .gear = view.inventory.gear, .steady = view.steady }, on);
            } else if (self.page == .stats) {
                if (self.advanced) character_stats.drawAdvanced(face, view) else character_stats.draw(face, view);
            } else {
                self.drawCells(face, sprites, view);
                self.drawDetail(face, view);
            }
            if (self.message.n > 0) {
                if (self.treePanel() != null) trees.note(face, self.message.text()) else face.draw(self.message.text(), layout.DETAIL_X, layout.FOOT_Y, font.SMALL, look.TEXT);
            }
        }
        const shown = self.controls(view);
        for (shown.all[0..shown.n]) |c| {
            const prompt = prompt_icon.Prompt.menuOn(view.device, c.button);
            switch (c.shown) {
                .label => |label| menu.action(face, c.box, prompt, label),
                .prompt => |alpha| _ = menu.actionPrompt(face, c.box, prompt, alpha),
                .drawn => {},
            }
        }
        if (!self.direct()) for ([_]bool{ false, true }) |next| {
            const m = raster.middleAt(layout.shoulderBox(next));
            prompt_icon.Prompt.menuOn(view.device, if (next) menu.PAGE_NEXT else menu.PAGE_PREV).draw(face, m.x, m.y, font.BODY, 1);
        };
    }

    fn drawDirect(self: *const Book, face: *const font.Face, sprites: *const look.Sprites, view: View) void {
        header(face, if (self.page == .nearby) "NEARBY" else if (view.chest) "CHEST LOOT" else "ITEM BAG");
        if (self.page == .loot) {
            var holding: menu.Note(100) = .{};
            holding.say("Inventory  {d} / {d}     Gold  {d}", .{ view.inventory.n, items.BAG_MAX, view.gold });
            face.draw(holding.text(), layout.LIST_X, layout.HOLDING_Y, font.SMALL, look.DIM);
            rl.drawLine(layout.DIVIDER_X, layout.LOOT_TOP, layout.DIVIDER_X, layout.LOOT_TOP + layout.CARD_H, look.EDGE);
        }
        self.drawCells(face, sprites, view);
        if (self.count(view) == 0) {
            face.draw("Empty", layout.LIST_X + layout.TEXT_X, self.directTop(), font.BODY, look.DIM);
            return;
        }
        if (self.selected(view)) |it| {
            const slot = self.destination(view);
            item_card.draw(face, layout.DETAIL_X, layout.LOOT_TOP, layout.DETAIL_W, it, slot, self.requirementAttrs(view, slot), null);
        } else if (view.nearby[self.cursor].supplyOf()) |k| {
            item_card.drawSupply(face, layout.DETAIL_X, layout.LOOT_TOP, layout.DETAIL_W, k, view.inventory.stacks.get(k), null);
        }
        const note_y = self.noteY(view);
        if (self.message.n > 0) face.draw(self.message.text(), layout.LIST_X, note_y, font.SMALL, look.TEXT);
        const position = self.positionOf(view);
        face.draw(position.text(), layout.DIRECT_W - layout.LIST_X - face.width(position.text(), font.SMALL), note_y, font.SMALL, look.DIM);
    }

    fn positionOf(self: *const Book, view: View) menu.Note(50) {
        var out: menu.Note(50) = .{};
        out.say("{d} / {d}", .{ if (self.count(view) > 0) self.cursor + 1 else 0, self.count(view) });
        return out;
    }

    fn drawCells(self: *const Book, face: *const font.Face, sprites: *const look.Sprites, view: View) void {
        if (self.page == .inventory) {
            const text_x = layout.LIST_X + layout.TEXT_X;
            face.draw("ITEM", text_x, layout.CONTENT_TOP, font.SMALL, look.DIM);
            face.draw("SLOT", layout.LIST_X + layout.SECOND_X, layout.CONTENT_TOP, font.SMALL, look.DIM);
            if (self.count(view) == 0) face.draw("Empty", text_x, layout.CONTENT_TOP + layout.EMPTY_DY, font.BODY, look.DIM);
            const position = self.positionOf(view);
            face.draw(position.text(), text_x, layout.FOOT_Y, font.SMALL, look.DIM);
        }
        for (0..self.count(view)) |i| {
            var name_buf: [items.NAME_MAX]u8 = undefined;
            if (!self.inWindow(i)) continue;
            const r = self.cellBox(i, view);
            const x: i32 = @intFromFloat(r.x);
            const y: i32 = @intFromFloat(r.y);
            const row_mid = y + layout.ROW_HEIGHT / 2;
            const chosen = i == self.cursor;
            rl.drawRectangleRec(r, look.BG);
            menu.outline(r, chosen, look.UI_FOCUS, look.EDGE);
            switch (self.page) {
                .equipment => {
                    const slot = items.SLOTS[i];
                    const inner = @as(i32, @intFromFloat(r.width)) - 2 * layout.SLOT_INSET;
                    var fitted: [items.NAME_MAX]u8 = undefined;
                    face.draw(face.fit(&fitted, slotLabel(slot), layout.SLOT_LABEL, inner, false), x + layout.SLOT_INSET, y + layout.SLOT_INSET, layout.SLOT_LABEL, look.DIM);
                    const it = view.inventory.gear.slots.get(slot);
                    const named = r.height >= layout.NAMED_CELL_H;
                    const foot = y + @as(i32, @intFromFloat(r.height)) - (if (named) layout.SLOT_INSET + font.SMALL else 0);
                    const glyph = P{ .x = raster.middleAt(r).x, .y = @divTrunc(y + layout.SLOT_INSET + layout.SLOT_LABEL + foot, 2) };
                    const side: line_icons.ItemSize = if (named) .cell else .row;
                    const name_mid = foot + font.SMALL / 2;
                    if (offhandWeapon(view.inventory.gear, slot)) |weapon| {
                        line_icons.drawItem(sprites, weapon.kind, side, glyph.x, glyph.y, look.fade(look.itemInk(weapon.rarity()), look.FADED_A));
                        face.centred(BOTH_HANDS, glyph.x, name_mid - layout.PAIR_DY, font.SMALL, look.DIM);
                        face.centred(face.fit(&fitted, weapon.name(&name_buf), font.SMALL, inner, false), glyph.x, name_mid, font.SMALL, look.itemInk(weapon.rarity()));
                    } else if (it) |worn| {
                        line_icons.drawItem(sprites, worn.kind, side, glyph.x, glyph.y, look.itemInk(worn.rarity()));
                        if (named) face.centred(face.fit(&fitted, worn.name(&name_buf), font.SMALL, inner, false), glyph.x, name_mid, font.SMALL, look.itemInk(worn.rarity()));
                    } else line_icons.drawItem(sprites, slotGlyph(slot), side, glyph.x, glyph.y, look.fade(look.DIM, look.FADED_A));
                },
                .inventory => if (stockAt(view, i)) |k| {
                    var carried: menu.Note(24) = .{};
                    carried.say("{d} carried", .{view.inventory.stacks.get(k)});
                    line_icons.drawSupply(sprites, k, .row, x + layout.GLYPH_X, row_mid, look.itemInk(.normal));
                    listRow(face, x, y, menu.named(k), look.itemInk(.normal), carried.text());
                } else {
                    const at = i - stocked(view);
                    const it = view.inventory.bag[at];
                    const slots = it.kind.slots();
                    line_icons.drawItem(sprites, it.kind, .row, x + layout.GLYPH_X, row_mid, look.itemInk(it.rarity()));
                    listRow(face, x, y, it.name(&name_buf), look.itemInk(it.rarity()), if (items.spec(it.kind).two_handed) BOTH_HANDS else if (slots.len > 1) menu.named(it.kind) else slots[0].name());
                },
                .nearby, .loot => {
                    const n = view.nearby[i];
                    if (n.item()) |it| {
                        line_icons.drawItem(sprites, it.kind, .row, x + layout.GLYPH_X, row_mid, inkOf(it));
                    } else if (n.supplyOf()) |k| line_icons.drawSupply(sprites, k, .row, x + layout.GLYPH_X, row_mid, look.itemInk(.normal));
                    listRow(face, x, y, n.label(&name_buf), inkOf(n.item()), n.command().verb());
                },
                .passives, .skills, .stats => unreachable,
            }
        }
    }
    fn requirementAttrs(self: *const Book, view: View, slot: items.Slot) attr.Attrs {
        return switch (self.page) {
            .inventory => (view.inventory.swapped(self.bagIndex(view).?, slot) catch view.inventory.gear).statsWithout(slot, view.base),
            .nearby, .loot => neededAttrs(view, self.selected(view).?, slot),
            .equipment, .stats, .passives, .skills => view.inventory.gear.statsWithout(slot, view.base),
        };
    }
    fn drawDetail(self: *const Book, face: *const font.Face, view: View) void {
        var name_buf: [items.NAME_MAX]u8 = undefined;
        const x = layout.DETAIL_X;
        const y = layout.CONTENT_TOP;
        if (self.count(view) == 0) return;
        const it = self.selected(view) orelse {
            if (self.carriedRow(view)) |k| return item_card.drawSupply(face, x, y, layout.DETAIL_W, k, view.inventory.stacks.get(k), null);
            if (self.page == .equipment) if (offhandWeapon(view.inventory.gear, items.SLOTS[self.cursor])) |weapon| {
                face.draw(BOTH_IN_USE, x, y, font.HEAD, look.TEXT);
                var held: menu.Note(128) = .{};
                held.say("{s}", .{weapon.name(&name_buf)});
                _ = face.paragraph(held.text(), x, y + layout.HELD_NOTE_DY, layout.DETAIL_W, font.SMALL, look.DIM);
                return;
            };
            face.draw(item_card.EMPTY_SLOT, x, y, font.HEAD, look.TEXT);
            return;
        };
        const slot = if (self.page == .equipment) items.SLOTS[self.cursor] else self.destination(view);
        const comparing = self.page == .inventory;
        item_card.draw(face, x, y, if (comparing) layout.CARD_W else layout.DETAIL_W, it, slot, self.requirementAttrs(view, slot), if (comparing) "SELECTED" else null);
        if (comparing) item_card.draw(face, x + layout.CARD_W + layout.CARD_GAP, y, layout.CARD_W, view.inventory.gear.slots.get(slot), slot, view.inventory.gear.statsWithout(slot, view.base), "EQUIPPED");
        if (comparing) {
            const at = y + @max(item_card.height(it, slot), item_card.height(view.inventory.gear.slots.get(slot), slot)) + layout.REQUIREMENT_GAP;
            const bagged = self.bagIndex(view).?;
            _ = view.inventory.preview(bagged, slot, view.base) catch |err| {
                var reason: menu.Note(140) = .{};
                if (err != error.Requirements) {
                    reason.say("{s}", .{items.caption(err)});
                } else if (dependent(view, bagged, slot)) |other| {
                    reason.say("Would leave {s} without its required attributes.", .{other.name(&name_buf)});
                } else return;
                _ = face.paragraph(reason.text(), x, at, layout.DETAIL_W, font.SMALL, layout.LOSS);
                return;
            };
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
        std.debug.assert(self.n < CONTROLS_MAX);
        self.all[self.n] = .{ .box = box, .button = button, .shown = shown };
        self.n += 1;
    }
};

fn header(face: *const font.Face, text: [:0]const u8) void {
    face.engraved(text, layout.LIST_X, font.Face.topFor(layout.HEADER_MID, font.HEAD), font.HEAD, look.TEXT);
}
fn listRow(face: *const font.Face, x: i32, y: i32, text: [:0]const u8, ink: rl.Color, second: [:0]const u8) void {
    const mid = y + layout.ROW_HEIGHT / 2;
    var fitted: [items.NAME_MAX]u8 = undefined;
    face.drawMiddle(face.fit(&fitted, text, font.BODY, layout.SECOND_X - layout.TEXT_X - layout.COLUMN_GAP, false), x + layout.TEXT_X, mid, font.BODY, ink);
    face.drawMiddle(second, x + layout.SECOND_X, mid, font.SMALL, look.DIM);
}
/// The detail panel's buttons, left to right.
const ACTIONS = [_]input.Button{ menu.CONFIRM, menu.CHANGE, menu.REMOVE };
/// What wearing ground item `it` in `slot` leaves to meet its requirements.
fn neededAttrs(view: View, it: items.Item, slot: items.Slot) attr.Attrs {
    return view.inventory.gear.wearing(it, slot).statsWithout(slot, view.base);
}
/// Short enough for a ring's small box.
fn slotLabel(s: items.Slot) [:0]const u8 {
    return switch (s) {
        .left_ring => "L ring",
        .right_ring => "R ring",
        .left_hand, .right_hand, .helm, .chest, .belt, .gloves, .boots, .amulet, .life_flask, .mana_flask => s.name(),
    };
}
/// The kind an empty slot shows faintly.
fn slotGlyph(s: items.Slot) items.Kind {
    return switch (s) {
        .right_hand => .sword,
        .left_hand => .shield,
        .helm => .helmet,
        .chest => .leather,
        .belt => .belt,
        .gloves => .gloves,
        .boots => .boots,
        .left_ring, .right_ring => .ring,
        .amulet => .amulet,
        .life_flask => .life_flask,
        .mana_flask => .mana_flask,
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
        const after = prompt.drawFrom(face, left, m.y, font.BODY, if (on) 1 else layout.OFF_TAB_A);
        face.drawMiddle(text, after + menu.PROMPT_GAP, m.y, font.BODY, ink);
    } else face.centred(text, m.x, m.y, font.BODY, ink);
}
fn offhandWeapon(gear: items.Gear, slot: items.Slot) ?items.Item {
    return if (slot == .left_hand) gear.twoHander() else null;
}

/// Something else worn that equipping bag item `at` in `slot` would leave unmet.
fn dependent(view: View, at: usize, slot: items.Slot) ?items.Item {
    const after = view.inventory.swapped(at, slot) catch return null;
    for (items.SLOTS) |s| {
        if (s == slot) continue;
        if (after.slots.get(s)) |other| if (!after.wornMeets(s, view.base)) return other;
    }
    return null;
}

/// Kinds carried, which head the Inventory list.
fn stocked(view: View) usize {
    var n: usize = 0;
    for (view.inventory.stacks.values) |carried| n += @intFromBool(carried > 0);
    return n;
}

fn stockAt(view: View, row: usize) ?consumable.Kind {
    var left = row;
    for (consumable.KINDS) |k| if (view.inventory.stacks.get(k) > 0) {
        if (left == 0) return k;
        left -= 1;
    };
    return null;
}

fn inkOf(it: ?items.Item) rl.Color {
    return look.itemInk(if (it) |i| i.rarity() else .normal);
}

fn testView(inv: *const items.Inventory, growth: *const progress.State) View {
    return .{ .class = .archer, .name = "Test", .inventory = inv, .growth = growth, .base = growth.attributes(.archer) };
}

test "character actions need one press and tabs are directly reachable" {
    var inv = items.Inventory{};
    try std.testing.expect(inv.add(.{ .kind = .cap }));
    var growth = progress.State.of(.archer);
    const view = testView(&inv, &growth);
    var book = Book{ .page = .inventory };
    const screen = display.WINDOW;
    const confirm = input.State{ .pressed = .initOne(menu.CONFIRM) };
    try std.testing.expect(book.step(&confirm, screen, view).? == .equip);
    try std.testing.expectEqual(@as(usize, 1), inv.n);
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.REMOVE) }, screen, view).? == .drop);
    _ = book.step(&.{ .pressed = .initOne(menu.PAGE_NEXT) }, screen, view);
    try std.testing.expectEqual(Page.stats, book.page);
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.BACK) }, screen, view).? == .close);
    book.choose(.inventory);
    const surface = book.surface(screen, view);
    const box = book.actionBox(menu.CONFIRM, view);
    const p = surface.screenOf(.{ .x = box.x + 20, .y = box.y + 20 });
    try std.testing.expect(book.step(&.{ .click = true, .pointer = p }, screen, view).? == .equip);
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
    const view = testView(&inv, &growth);
    var book = Book{ .page = .stats };
    const screen = display.WINDOW;
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.CHANGE) }, screen, view) == null);
    try std.testing.expect(book.advanced);
    const box = book.actionBox(menu.CHANGE, view);
    const p = book.surface(screen, view).screenOf(.{ .x = box.x + 20, .y = box.y + 20 });
    _ = book.step(&.{ .click = true, .pointer = p }, screen, view);
    try std.testing.expect(!book.advanced);
    book.advanced = true;
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.BACK) }, screen, view).? == .close);
    std.debug.print("stats: change and a click on its button toggle the advanced sheet; back closes from it\n", .{});
}

test "loot exposes single pickup and take all through controller and mouse controls" {
    const inv = items.Inventory{};
    const growth = progress.State.of(.archer);
    var view = testView(&inv, &growth);
    view.nearby = &.{.{ .loot = .{ .index = 7, .item = .{ .kind = .cap } } }};
    var book = Book{ .page = .loot };
    const screen = display.SCREEN_720;
    const one = book.step(&.{ .pressed = .initOne(menu.CONFIRM) }, screen, view).?;
    try std.testing.expectEqual(@as(usize, 7), one.pickup);
    try std.testing.expect(book.step(&.{ .pressed = .initOne(menu.CHANGE) }, screen, view).? == .take_all);
    const surface = book.surface(screen, view);
    const box = book.actionBox(menu.CHANGE, view);
    const p = surface.screenOf(.{ .x = box.x + 20, .y = box.y + 20 });
    try std.testing.expect(book.step(&.{ .click = true, .pointer = p }, screen, view).? == .take_all);
    const panel = book.size(view);
    try std.testing.expect(panel.y < layout.SIZE.y);
    try std.testing.expectEqual(@as(f32, @floatFromInt(panel.y - layout.ACTION_H - menu.PANEL_PAD)), book.actionBox(menu.CONFIRM, view).y);
    const card = item_card.height(.{ .kind = .cap }, .helm);
    try std.testing.expect(book.cellBox(0, view).x + layout.LIST_W < layout.DETAIL_X and layout.LOOT_TOP + card <= layout.LOOT_FOOT_Y);
    var many: [layout.LOOT_ROWS + 4]Nearby = undefined;
    for (&many, 0..) |*n, i| n.* = .{ .loot = .{ .index = i, .item = .{ .kind = .axe } } };
    var crowded = view;
    crowded.nearby = &many;
    try std.testing.expectEqual(panel, book.size(crowded));
    std.debug.print("loot panel: fixed {d}x{d}, list {d} rows left, card {d}px right, Book {d}x{d}\n", .{ panel.x, panel.y, layout.LOOT_ROWS, card, layout.SIZE.x, layout.SIZE.y });
    _ = book.step(&.{ .pressed = .initOne(menu.PAGE_NEXT) }, screen, view);
    try std.testing.expectEqual(Page.loot, book.page);
    const at = P{ .x = 20, .y = 20 };
    view.nearby = &.{.{ .gold = .{ .at = at, .amount = 37 } }};
    try std.testing.expectEqual(panel, book.size(view));
    try std.testing.expectEqual(at, book.step(&.{ .pressed = .initOne(menu.CONFIRM) }, screen, view).?.take_gold);
    var label: [80]u8 = undefined;
    try std.testing.expectEqualStrings("37 gold", view.nearby[0].label(&label));
    const gold_box = book.actionBox(menu.CHANGE, view);
    const gold_p = book.surface(screen, view).screenOf(.{ .x = gold_box.x + 20, .y = gold_box.y + 20 });
    try std.testing.expect(book.step(&.{ .click = true, .pointer = gold_p }, screen, view).? == .take_all);
    std.debug.print("loot controls: item and gold pickup, take-all press and scaled mouse hit on both row types, no character tabs\n", .{});
}

test "the inventory list scrolls back when the bag shrinks" {
    var inv = items.Inventory{};
    for (0..layout.VISIBLE_ROWS + 6) |_| try std.testing.expect(inv.add(.{ .kind = .cap }));
    var growth = progress.State.of(.archer);
    const view = testView(&inv, &growth);
    const screen = display.WINDOW;
    var book = Book{ .page = .inventory, .cursor = layout.VISIBLE_ROWS + 5 };
    _ = book.step(&.{}, screen, view);
    try std.testing.expectEqual(@as(usize, 6), book.top);
    for (0..6) |_| _ = inv.remove(inv.n - 1);
    _ = book.step(&.{}, screen, view);
    try std.testing.expectEqual(@as(usize, 0), book.top);
    try std.testing.expectEqual(@as(usize, layout.VISIBLE_ROWS - 1), book.cursor);
    book.top = 6;
    var drawn = book;
    drawn.top = drawn.settledTop(view);
    const box = drawn.cellBox(0, view);
    const surface = menu.Surface.of(screen, layout.SIZE);
    const p = surface.screenOf(.{ .x = box.x + 20, .y = box.y + 10 });
    _ = book.step(&.{ .click = true, .pointer = p }, screen, view);
    try std.testing.expectEqual(@as(usize, 0), book.cursor);
    std.debug.print("inventory scroll: top 6 of {d}, back to {d} once {d} remain\n", .{ layout.VISIBLE_ROWS + 6, book.top, inv.n });
}

test "item card requirements exclude the item itself and every displaced hand" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    const base = attr.Attrs.of(.{ .strength = 10, .dexterity = 12, .intelligence = 10 });
    var view = testView(&inv, &growth);
    view.base = base;
    inv.gear.slots.set(.left_hand, .{ .kind = .shield, .mods = .{ .{ .kind = .strength, .value = 10 }, null, null, null } });
    try std.testing.expect(inv.add(.{ .kind = .axe, .mods = .{ .{ .kind = .strength, .value = 10 }, null, null, null } }));
    var book = Book{ .page = .inventory };
    try std.testing.expectEqual(@as(i32, 10), book.requirementAttrs(view, .right_hand).get(.strength));
    try std.testing.expectError(error.Requirements, inv.preview(0, .right_hand, base));
    try std.testing.expect(inv.gear.slots.get(.left_hand) != null and inv.n == 1);
    inv.gear.slots.set(.left_hand, null);
    inv.gear.slots.set(.left_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 3 }, null, null, null } });
    inv.gear.slots.set(.right_ring, .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 7 }, null, null, null } });
    inv.bag[0] = .{ .kind = .ring, .mods = .{ .{ .kind = .strength, .value = 2 }, null, null, null } };
    try std.testing.expectEqual(@as(i32, 17), book.requirementAttrs(view, .left_ring).get(.strength));
    try std.testing.expectEqual(@as(i32, 13), book.requirementAttrs(view, .right_ring).get(.strength));
    book.page = .equipment;
    try std.testing.expectEqual(@as(i32, 17), book.requirementAttrs(view, .left_ring).get(.strength));
    inv.gear.slots.set(.left_hand, .{ .kind = .shield, .mods = .{ .{ .kind = .strength, .value = 10 }, null, null, null } });
    var ground = view;
    ground.nearby = &.{.{ .loot = .{ .index = 0, .item = .{ .kind = .axe, .mods = .{ null, null, null, null } } } }};
    book.choose(.loot);
    try std.testing.expectEqual(@as(i32, 20), book.requirementAttrs(ground, .right_hand).get(.strength));
    std.debug.print("item cards: 2-hand displacement, self-funding, both ring destinations and ground items; inventory unchanged\n", .{});
}

test "tree browsing is free and point actions issue one command" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    growth.passive_points = 2;
    growth.active_points = 2;
    const view = testView(&inv, &growth);
    const screen = display.SCREEN_720;
    var book = Book{ .page = .passives, .cursor = progress.passives.branchFirst(.rogue_evade) };
    try std.testing.expectEqual(trees.ZOOM_START, book.zoom);
    try std.testing.expect(book.treeActive());
    const original_cursor = book.cursor;
    _ = book.step(&.{ .tree = .{ .zoom = -1, .pan = .{ .x = 1, .y = -1 }, .dt = 0.25 } }, screen, view);
    try std.testing.expect(book.zoom < trees.ZOOM_START and book.pan.x > 0 and book.pan.y < 0);
    try std.testing.expectEqual(original_cursor, book.cursor);
    _ = book.step(&.{ .tree = .{ .move = .{ .x = 1, .y = 0 } } }, screen, view);
    try std.testing.expectEqual(progress.passives.step(original_cursor, 1, 0), book.cursor);
    try std.testing.expectEqual(@as(f32, 0), book.pan.x);
    _ = book.step(&.{ .tree = .{ .zoom = 1, .dt = 100 } }, screen, view);
    try std.testing.expectEqual(trees.ZOOM_MAX, book.zoom);
    _ = book.step(&.{ .tree = .{ .reset = true } }, screen, view);
    try std.testing.expectEqual(trees.ZOOM_MIN, book.zoom);
    try std.testing.expectEqual(@as(f32, 0), book.pan.y);
    book.cursor = original_cursor;
    var zoom = input.State{};
    zoom.pressed.insert(menu.CHANGE);
    _ = book.step(&zoom, screen, view);
    try std.testing.expect(book.zoom > trees.ZOOM_MIN);
    var confirm = input.State{};
    confirm.pressed.insert(menu.CONFIRM);
    try std.testing.expectEqual(book.cursor, book.step(&confirm, screen, view).?.passive);
    try std.testing.expectEqual(@as(u16, 2), growth.passive_points);
    book.choose(.skills);
    book.cursor = 0;
    try std.testing.expect(book.step(&confirm, screen, view) == null);
    book.cursor = 1;
    try std.testing.expectEqual(progress.skills(.archer)[1].act, book.step(&confirm, screen, view).?.skill);
    try std.testing.expectEqual(@as(u16, 2), growth.active_points);
    book.choose(.passives);
    try std.testing.expectEqual(trees.ZOOM_START, book.zoom);
    const canvas = trees.zoomBox(true);
    const surface = menu.Surface.of(screen, layout.SIZE);
    _ = book.step(&.{ .pointer = surface.screenOf(.{ .x = canvas.x, .y = canvas.y }), .scroll = -1 }, screen, view);
    try std.testing.expect(book.treeActive() and book.zoom < trees.ZOOM_START);
    std.debug.print("tree book: spatial browsing and zoom spend no points; passive and skill selection return one command\n", .{});
}

test "mouse character browsing and passive dragging preserve points and scaled hit targets" {
    var inv = items.Inventory{};
    var growth = progress.State.of(.archer);
    growth.active_points = 2;
    growth.passive_points = 2;
    const view = testView(&inv, &growth);
    var checked: usize = 0;
    for ([_]P{ display.SCREEN_720, display.SCREEN_1440 }) |screen| {
        var book = Book{ .page = .skills };
        const surface = book.surface(screen, view);
        const p = surface.screenOf(raster.middle(book.cellBox(1, view)));
        try std.testing.expect(book.step(&.{ .pointer = p, .click = true }, screen, view) == null);
        try std.testing.expectEqual(@as(usize, 1), book.cursor);
        _ = book.step(&.{ .pointer = p, .walk = .w }, screen, view);
        try std.testing.expectEqual(@as(usize, 0), book.cursor);
        book.choose(.passives);
        book.enter(view);
        const cursor = book.cursor;
        const inside = surface.screenOf(.{ .x = layout.AREA.x + 150, .y = layout.AREA.y + 160 });
        _ = book.step(&.{ .pointer = inside, .middle_click = true, .dragging = true, .mouse_delta = .{ .x = 30, .y = 15 } }, screen, view);
        try std.testing.expect(book.pan.x < 0 and book.pan.y < 0);
        try std.testing.expectEqual(cursor, book.cursor);
        const pan = book.pan;
        _ = book.step(&.{ .pointer = inside, .mouse_delta = .{ .x = 30, .y = 15 } }, screen, view);
        try std.testing.expectEqual(pan, book.pan);
        const zoom = book.zoom;
        _ = book.step(&.{ .pointer = inside, .scroll = 1 }, screen, view);
        try std.testing.expect(book.zoom > zoom);
        _ = book.step(&.{ .pointer = surface.screenOf(raster.middle(trees.overviewBox())), .click = true }, screen, view);
        try std.testing.expectEqual(trees.ZOOM_MIN, book.zoom);
        try std.testing.expectEqual(rl.Vector2{ .x = 0, .y = 0 }, book.pan);
        try std.testing.expectEqual(@as(u16, 2), growth.active_points);
        try std.testing.expectEqual(@as(u16, 2), growth.passive_points);
        try std.testing.expect(book.step(&.{ .right_click = true }, screen, view).? == .close);
        checked += 1;
    }
    std.debug.print("mouse character: {d} scales, skill selection/controller return, captured drag/release, zoom, overview, no point spend\n", .{checked});
}

test "mouse item and skill selections survive movement across other targets toward actions" {
    var inv = items.Inventory{};
    for (0..8) |_| try std.testing.expect(inv.add(.{ .kind = .cap }));
    const growth = progress.State.of(.archer);
    var view = testView(&inv, &growth);
    const nearby = [_]Nearby{
        .{ .loot = .{ .index = 7, .item = .{ .kind = .cap } } },
        .{ .loot = .{ .index = 8, .item = .{ .kind = .cap } } },
        .{ .loot = .{ .index = 9, .item = .{ .kind = .cap } } },
    };
    var journeys: usize = 0;
    for ([_]P{ display.SCREEN_720, display.SCREEN_1440 }) |screen| {
        for ([_]Page{ .inventory, .loot, .skills }) |page| {
            view.nearby = if (page == .loot) &nearby else &.{};
            var book = Book{ .page = page };
            const surface = book.surface(screen, view);
            const origin = raster.middle(book.cellBox(0, view));
            _ = book.step(&.{ .pointer = surface.screenOf(origin), .click = true }, screen, view);
            const action = if (page == .skills) trees.bindBox() else book.actionBox(menu.CONFIRM, view);
            for (1..book.count(view)) |i| {
                _ = book.step(&.{ .pointer = surface.screenOf(raster.middle(book.cellBox(i, view))), .mouse_moved = true }, screen, view);
                try std.testing.expectEqual(@as(usize, 0), book.cursor);
            }
            const end = raster.middle(action);
            for (1..21) |i| {
                const fraction = @as(f32, @floatFromInt(i)) / 20;
                const p = rl.Vector2{ .x = origin.x + (end.x - origin.x) * fraction, .y = origin.y + (end.y - origin.y) * fraction };
                _ = book.step(&.{ .pointer = surface.screenOf(p), .mouse_moved = true }, screen, view);
            }
            const command = book.step(&.{ .pointer = surface.screenOf(end), .click = true }, screen, view).?;
            switch (page) {
                .inventory => try std.testing.expectEqual(@as(usize, 0), command.equip.index),
                .loot => try std.testing.expectEqual(@as(usize, 7), command.pickup),
                .skills => try std.testing.expectEqual(progress.skills(view.class)[0].act, command.bindings),
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
    const view = testView(&inv, &growth);
    const screen = display.SCREEN_720;
    const dead_end = found: for (0..progress.NODES.len) |i| {
        for (mathx.CARDINALS) |delta| {
            if (progress.passives.step(i, @floatFromInt(delta.x), @floatFromInt(delta.y)) == i) break :found .{ i, delta };
        }
    } else unreachable;
    var book = Book{ .page = .passives, .cursor = dead_end[0] };
    _ = book.step(&.{ .tree = .{ .pan = .{ .x = 1, .y = 1 }, .dt = 0.25 } }, screen, view);
    const pan = book.pan;
    try std.testing.expect(pan.x != 0 or pan.y != 0);
    const move: rl.Vector2 = .{ .x = @floatFromInt(dead_end[1].x), .y = @floatFromInt(dead_end[1].y) };
    _ = book.step(&.{ .tree = .{ .move = move } }, screen, view);
    try std.testing.expectEqual(dead_end[0], book.cursor);
    try std.testing.expectEqual(pan, book.pan);
    std.debug.print("dead-end stick on node {d}: pan kept at {d:.1},{d:.1}\n", .{ dead_end[0], pan.x, pan.y });
}
