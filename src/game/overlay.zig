const std = @import("std");
const journal = @import("../ui/journal.zig");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const menu = @import("../ui/menu.zig");
const hud = @import("../ui/hud.zig");
const book = @import("../ui/book.zig");
const skillbar = @import("../play/skillbar.zig");
const look = @import("../gfx/look.zig");
const font = @import("../gfx/font.zig");
const game = @import("../game.zig");
const P = mathx.P;
const BIND_PANEL = book.SIZE;
const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;
const CHANGE = menu.CHANGE;
const REMOVE = menu.REMOVE;
const plural = mathx.plural;

fn bindRowY(row: usize) i32 {
    return game.BIND_TOP + game.BIND_ROWS_DY + @as(i32, @intCast(row)) * game.BIND_ROW_H;
}

fn bindSlotY(row: usize) i32 {
    return bindRowY(row) + game.TEXT + game.BIND_LABEL_GAP;
}

pub fn bindSlotBox(row: usize, col: usize) rl.Rectangle {
    return look.rect(game.BIND_X0 + game.SLOT_XS[col], bindSlotY(row), game.SLOT_PX, game.SLOT_PX);
}

const BindAction = struct {
    button: input.Button,
    label: [:0]const u8,
    browse_only: bool,

    pub fn shown(a: BindAction, b: *const game.Binds) bool {
        return b.menu == .browse or !a.browse_only;
    }
};
pub const BIND_ACTIONS = [_]BindAction{
    .{ .button = CONFIRM, .label = "Choose skill", .browse_only = false },
    .{ .button = CHANGE, .label = "All skills", .browse_only = true },
    .{ .button = REMOVE, .label = "Clear slot", .browse_only = true },
    .{ .button = BACK, .label = "Back", .browse_only = false },
};
/// A labelled action button's size, on the bind and death screens.
pub const ACTION = P{ .x = 220, .y = 40 };
const BIND_ACTION_STEP: i32 = 250;
const BIND_ACTION_X: i32 = @divExact(BIND_PANEL.x - (BIND_ACTIONS.len - 1) * BIND_ACTION_STEP - ACTION.x, 2);
const BIND_ACTION_Y: i32 = BIND_PANEL.y - 68;
const BIND_DESC_W: i32 = 900;

pub fn bindActionBox(i: usize) rl.Rectangle {
    return look.rect(BIND_ACTION_X + @as(i32, @intCast(i)) * BIND_ACTION_STEP, BIND_ACTION_Y, ACTION.x, ACTION.y);
}

const SlotLook = struct { act: ?skillbar.Act, key: ?input.Button, edge: ?rl.Color = null, faded: bool = false };

fn drawSlot(g: *game.Game, box: rl.Rectangle, s: SlotLook) void {
    const x: i32 = @intFromFloat(box.x);
    const y: i32 = @intFromFloat(box.y);
    const a: f32 = if (s.faded) look.FADED_A else 1;
    look.hudPanel(&g.sprites, x, y, game.SLOT_PX, game.SLOT_PX, look.fade(if (s.act == null) look.SLOT_EMPTY else look.SLOT_BG, a), look.fade(look.LIT, a));
    if (s.edge) |edge| {
        rl.drawRectangleLinesEx(look.grown(box, @floatFromInt(-game.SLOT_EDGE_INSET)), @floatFromInt(game.LINE_W), look.fade(edge, a));
    }
    if (s.act) |act| {
        const inset = @divTrunc(game.SLOT_PX - look.SKILL_PX, 2);
        look.drawSkill(&g.sprites, act, x + inset, y + inset, a);
    }
    const p = look.Prompt.of(&g.st, s.key orelse return);
    p.draw(&g.face, x + game.SLOT_MID, y + game.SLOT_PX + game.KEY_GAP + @divTrunc(game.PROMPT_PX, 2), game.PROMPT_PX, a);
}

/// While aiming, the set the reticle's skill was taken from, whatever is held now.
fn shownSet(g: *const game.Game) skillbar.Set {
    return if (g.mode == .aim) g.aim_set else g.bar.active(g.st.down);
}

const SlotShown = struct { act: skillbar.Act, cooling: u8, drinks: ?u8 };

fn slotShown(g: *const game.Game, i: usize) ?SlotShown {
    const act = g.bar.at(.{ .set = shownSet(g), .button = skillbar.SLOTS[i] }) orelse return null;
    return .{ .act = act, .cooling = g.cooldown.get(act), .drinks = if (act.flaskOf()) |k| g.flasks_shown.get(k).uses() else null };
}

pub fn hudLayout(g: *const game.Game) hud.Layout {
    return hud.Layout.of(g.screen, game.SKILLS_W);
}

fn slotBox(layout: hud.Layout, i: usize) rl.Rectangle {
    return look.rect(layout.skills.x + game.SLOT_XS[i], layout.skills.y, game.SLOT_PX, game.SLOT_PX);
}

fn drawSkills(g: *game.Game, layout: hud.Layout) void {
    const mana = game.manaShown(g);
    for (skillbar.SLOTS, 0..) |b, i| {
        const box = slotBox(layout, i);
        const held = (g.st.held(b) and game.playShown(g)) or (g.mode == .aim and g.aim_by == b);
        const s = slotShown(g, i);
        drawSlot(g, box, .{
            .act = if (s) |v| v.act else null,
            .key = b,
            .edge = if (held) look.SLOT_HELD else null,
            .faded = if (s) |v| game.blocked(g, v.act, &g.flasks_shown, mana) != null else false,
        });
        const v = s orelse continue;
        if (v.cooling > 0 or v.drinks != null) hud.counter(&g.face, box, v.drinks orelse v.cooling);
    }
}

const BindPicker = struct {
    win: menu.Window,
    picks: usize,
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn first(p: BindPicker) usize {
        return p.win.from * game.PICK_COLS;
    }

    pub fn end(p: BindPicker) usize {
        return @min(p.picks, (p.win.from + p.win.len) * game.PICK_COLS);
    }

    pub fn cell(p: BindPicker, i: usize) rl.Rectangle {
        return look.rect(p.x + @as(i32, @intCast(i % game.PICK_COLS)) * game.SLOT_STEP, p.y + @as(i32, @intCast(i / game.PICK_COLS - p.win.from)) * game.SLOT_STEP, game.SLOT_PX, game.SLOT_PX);
    }
};

pub fn bindPicker(b: game.Binds, picks: usize) BindPicker {
    const cursor_x = game.BIND_X0 + game.SLOT_XS[b.col];
    const pop_y = bindSlotY(b.row) - game.SLOT_PX - game.BIND_POP_DY;
    const win = game.pickWindow(game.BIND_TOP + game.BIND_TITLE, pop_y, picks, b.menu.pick);
    const w = @as(i32, @intCast(@min(picks, game.PICK_COLS))) * game.SLOT_STEP - game.SLOT_GAP;
    return .{ .win = win, .picks = picks, .x = std.math.clamp(cursor_x + @divTrunc(game.SLOT_PX - w, 2), game.BIND_X0, game.BIND_X0 + game.SKILLS_W - w), .y = pop_y - @as(i32, @intCast(win.len - 1)) * game.SLOT_STEP, .w = w, .h = @as(i32, @intCast(win.len)) * game.SLOT_STEP - game.SLOT_GAP };
}

/// Centred across the bind panel.
fn bindText(g: *const game.Game, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    menu.mid(g.face, BIND_PANEL, s, y, size, col);
}

pub fn drawBinds(g: *game.Game) void {
    game.character.veil(g);
    const surface = menu.Surface.of(g.screen, BIND_PANEL);
    surface.beginPanel(&g.sprites, BIND_PANEL);
    defer rl.endMode2D();
    const face = g.face;
    g.face = surface.faceFor(face);
    defer g.face = face;
    const b = g.binds;
    menu.heading(g.face, BIND_PANEL, "BIND SKILLS", game.BIND_TOP, game.BIND_TITLE, look.TEXT, look.UI_GOLD);
    for (skillbar.SETS, 0..) |set, row| {
        g.face.text(set.name(), game.BIND_X0, bindRowY(row), game.TEXT, look.DIM);
        for (skillbar.SLOTS, 0..) |key, i| {
            drawSlot(g, bindSlotBox(row, i), .{
                .act = g.bar.at(.{ .set = set, .button = key }),
                .key = key,
                .edge = if (row == b.row and i == b.col) look.SLOT_CURSOR else null,
            });
        }
    }
    const info_y = bindRowY(skillbar.SETS.len) + game.BIND_INFO_DY;
    var shown: ?skillbar.Act = b.assigning orelse g.bar.at(b.slot());
    switch (b.menu) {
        .browse => {},
        .pick => |pick| {
            var kit_buf: game.KitBuf = undefined;
            const kit = g.growth.kit(g.class, &kit_buf);
            shown = game.pickAct(kit, pick);
            const picker = bindPicker(b, game.picksOf(kit));
            rl.drawRectangleRec(look.grown(look.rect(picker.x, picker.y, picker.w, picker.h), @floatFromInt(game.SLOT_GAP)), look.PICK_BG);
            for (picker.first()..picker.end()) |i| {
                const r = picker.cell(i);
                const x: i32 = @intFromFloat(r.x);
                const y: i32 = @intFromFloat(r.y);
                const act = game.pickAct(kit, i);
                const edge: ?rl.Color = if (i == pick) look.SLOT_CURSOR else if (act == null) look.SLOT_CLEAR else null;
                drawSlot(g, r, .{ .act = act, .key = null, .edge = edge });
                if (act == null) g.face.glyph(look.CLEAR.ch, x + game.SLOT_MID, y + game.SLOT_MID, game.CLEAR_GLYPH, look.CLEAR.fg);
            }
        },
    }
    if (shown) |a| {
        bindText(g, a.name(), info_y, game.TEXT, look.TEXT);
        var desc: [TIP_BODY_MAX + 1]u8 = undefined;
        const text = describe(g, a, &desc);
        _ = g.face.paragraphWith(font.Face.textMid, text, @divTrunc(BIND_PANEL.x, 2), info_y + game.TEXT_LINE, BIND_DESC_W, font.BODY, look.DIM);
    } else if (b.menu == .pick) {
        bindText(g, "Clear slot", info_y, game.TEXT, look.TEXT);
    }
    for (BIND_ACTIONS, 0..) |action, i| {
        if (!action.shown(&b)) continue;
        const label = if (action.button == CONFIRM and b.assigning != null and b.menu == .browse) "Assign skill" else action.label;
        menu.action(&g.face, bindActionBox(i), look.Prompt.menuOf(&g.st, action.button), label);
    }
}

/// Its description, then its mana, turn and cooldown at the hero's rank.
pub fn describe(g: *const game.Game, act: skillbar.Act, buf: []u8) [:0]const u8 {
    var s = std.io.fixedBufferStream(buf[0 .. buf.len - 1]);
    writeDescription(g, act, s.writer());
    const n = s.getWritten().len;
    buf[n] = 0;
    return buf[0..n :0];
}

fn writeDescription(g: *const game.Game, act: skillbar.Act, w: anytype) void {
    g.growth.writeDescription(act, w);
    w.writeAll(" ") catch {};
    g.growth.writeUsage(act, w);
    w.writeAll(".") catch {};
}

const Life = struct { hp: i32, max: i32 };

pub fn resourceFill(value: i32, max: i32) f32 {
    return std.math.clamp(@as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(@max(1, max))), 0, 1);
}

pub fn settleResources(g: *game.Game) void {
    g.life_fill = lifeFill(g);
    g.mana_fill = manaFill(g);
}

/// Where the orbs' fills are easing to.
pub fn lifeFill(g: *const game.Game) f32 {
    const life = lifeShown(g);
    return resourceFill(life.hp, life.max);
}

pub fn manaFill(g: *const game.Game) f32 {
    return resourceFill(game.manaShown(g), game.manaMax(g));
}

fn lifeShown(g: *const game.Game) Life {
    const h = game.heroShown(g) orelse return .{ .hp = 0, .max = game.lifeMax(g) };
    return .{ .hp = h.hp, .max = h.max };
}

pub fn drawHud(g: *game.Game) void {
    const layout = hudLayout(g);
    hud.frame(layout, &g.sprites);
    const life = lifeShown(g);
    hud.resources(layout, &g.face, life.hp, life.max, game.manaShown(g), game.manaMax(g), g.life_fill, g.mana_fill);
    drawSkills(g, layout);
    hud.experience(layout, g.xp_shown - @floor(g.xp_shown));
    if (game.heroShown(g)) |h| hud.statuses(layout, &g.sprites, &g.face, h.status);
}

pub const Part = struct { spot: game.Spot, box: rl.Rectangle };
const ORBS = 2;
pub const SPOTS_MAX = ORBS + skillbar.SLOTS.len + @typeInfo(hud.Shown).array.len + 1;

pub fn spotsOf(g: *const game.Game, out: *[SPOTS_MAX]Part) []const Part {
    const layout = hudLayout(g);
    var n: usize = 0;
    out[n] = .{ .spot = .life, .box = hud.orbBox(layout.life) };
    n += 1;
    for (0..skillbar.SLOTS.len) |i| {
        out[n] = .{ .spot = .{ .slot = i }, .box = slotBox(layout, i) };
        n += 1;
    }
    out[n] = .{ .spot = .mana, .box = hud.orbBox(layout.mana) };
    n += 1;
    std.debug.assert(n == ORBS + skillbar.SLOTS.len);
    if (game.heroShown(g)) |h| {
        var buf: hud.Shown = undefined;
        const shown = hud.shownStatuses(h.status, &buf);
        for (shown, 0..) |s, k| {
            out[n] = .{ .spot = .{ .status = s }, .box = hud.statusBox(layout, shown.len, k) };
            n += 1;
        }
    }
    out[n] = .{ .spot = .log, .box = journal.box(g.screen) };
    n += 1;
    return out[0..n];
}

fn spotAt(spots: []const Part, s: game.Spot) ?Part {
    for (spots) |x| {
        if (std.meta.eql(x.spot, s)) return x;
    }
    return null;
}

fn toward(spots: []const Part, from: Part, d: mathx.Dir) ?game.Spot {
    var boxes: [SPOTS_MAX]rl.Rectangle = undefined;
    for (spots, boxes[0..spots.len]) |s, *b| b.* = s.box;
    const i = menu.nearest(from.box, boxes[0..spots.len], d) orelse return null;
    return spots[i].spot;
}

pub fn inspectStep(g: *game.Game) void {
    if (menu.backed(&g.st) or g.st.hit(skillbar.INSPECT)) {
        g.mode = .play;
        return;
    }
    var buf: [SPOTS_MAX]Part = undefined;
    const spots = spotsOf(g, &buf);
    const here = inspected(g, spots);
    g.inspecting = here.spot;
    const d = g.st.walk orelse return;
    if (here.spot == .log and d.delta().y != 0 and d.delta().x == 0) {
        g.log.move(-d.delta().y);
        return;
    }
    g.inspecting = toward(spots, here, d) orelse here.spot;
}

fn inspected(g: *const game.Game, spots: []const Part) Part {
    return spotAt(spots, g.inspecting) orelse spotAt(spots, .{ .slot = 0 }).?;
}

pub fn round(s: game.Spot) bool {
    return s == .life or s == .mana;
}

pub fn hovered(g: *const game.Game) ?Part {
    if (!game.playShown(g) and g.mode != .aim) return null;
    const p = g.st.pointer orelse return null;
    var buf: [SPOTS_MAX]Part = undefined;
    for (spotsOf(g, &buf)) |s| {
        const over = if (round(s.spot)) rl.checkCollisionPointCircle(look.vec(p), look.middle(s.box), s.box.width / 2) else look.holds(s.box, p);
        if (over) return s;
    }
    return null;
}

pub fn drawTips(g: *game.Game) void {
    if (g.mode == .inspect) {
        var buf: [SPOTS_MAX]Part = undefined;
        const spots = spotsOf(g, &buf);
        drawTip(g, inspected(g, spots));
    } else if (hovered(g)) |here| drawTip(g, here);
}

fn drawTip(g: *game.Game, here: Part) void {
    hud.focus(here.box, round(here.spot));
    var title_buf: [TIP_TITLE_MAX]u8 = undefined;
    var body_buf: [TIP_BODY_MAX]u8 = undefined;
    const tip = tipOf(g, here.spot, &title_buf, &body_buf) orelse return;
    hud.tooltip(&g.face, hudLayout(g), g.screen, here.box, tip.title, tip.body);
}

const Tip = struct { title: [:0]const u8, body: []const u8 };
pub const TIP_TITLE_MAX: usize = 64;
pub const TIP_BODY_MAX: usize = menu.NOTE_MAX * 2;

/// The log is its own tooltip: scrolled, never titled.
pub fn tipOf(g: *const game.Game, s: game.Spot, title_buf: []u8, body_buf: []u8) ?Tip {
    return switch (s) {
        .log => null,
        .life => blk: {
            const life = lifeShown(g);
            break :blk .{
                .title = hud.LIFE,
                .body = std.fmt.bufPrint(body_buf, comptime hud.table(.{ .{ "Current", "{d}" }, .{ "Maximum", "{d}" }, .{ "Physical reduction", "{d}%" }, .{ "Dodge", "{d}%" } }), .{ life.hp, life.max, game.heroAttrs(g).reduction(), game.heroAttrs(g).dodge() }) catch "",
            };
        },
        .mana => .{
            .title = hud.MANA,
            .body = std.fmt.bufPrint(body_buf, comptime hud.table(.{ .{ "Current", "{d}" }, .{ "Maximum", "{d}" }, .{ "Recovery / turn", "{d}" } }), .{ game.manaShown(g), game.manaMax(g), game.manaRegen(g) }) catch "",
        },
        .slot => |i| blk: {
            const v = slotShown(g, i) orelse break :blk .{ .title = "Empty skill slot", .body = "No skill is bound here." };
            const act = v.act;
            var body = std.io.fixedBufferStream(body_buf);
            const w = body.writer();
            writeDescription(g, act, w);
            if (act.reticle() != null) w.print("\nRange: {d} cells", .{act.reach()}) catch {};
            if (g.growth.hit(game.heroAttrs(g), g.inventory.gear, act)) |h| {
                if (h.physical.hi > 0) w.print("\nPhysical damage: {d}-{d}", .{ h.physical.lo, h.physical.hi }) catch {};
                if (h.element) |e| w.print("\n{s} damage: {d}-{d}", .{ menu.named(act.element().?), e.lo, e.hi }) catch {};
                w.print("\nScales with {s}", .{menu.named(h.style.attr())}) catch {};
            }
            if (v.drinks) |n|
                w.print("\n{d} drink{s} left", .{ n, plural(n) }) catch {}
            else if (v.cooling > 0)
                w.print("\nReady in {d} turn{s}", .{ v.cooling, plural(v.cooling) }) catch {};
            const rank = g.growth.ranks.get(act);
            break :blk .{ .title = if (rank > 0) std.fmt.bufPrintZ(title_buf, "{s} - Rank {d}", .{ act.name(), rank }) catch act.name() else act.name(), .body = body.getWritten() };
        },
        .status => |st| blk: {
            const turns = if (game.heroShown(g)) |h| h.status.get(st) else 0;
            break :blk .{
                .title = std.fmt.bufPrintZ(title_buf, "{s}, {d} turn{s}", .{ st.title(), turns, plural(turns) }) catch st.title(),
                .body = st.about(),
            };
        },
    };
}
