const std = @import("std");
const journal = @import("../ui/journal.zig");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const input = @import("../core/input.zig");
const menu = @import("../ui/menu.zig");
const hud = @import("../ui/hud.zig");
const book = @import("../ui/book.zig");
const skillbar = @import("../play/skillbar.zig");
const damage = @import("../play/damage.zig");
const attrs = @import("../play/attrs.zig");
const heroes = @import("../play/hero.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const prompt_icon = @import("../gfx/prompt_icon.zig");
const line_icons = @import("../gfx/line_icons.zig");
const font = @import("../gfx/font.zig");
const game = @import("../game.zig");
const skills = @import("skills.zig");
const binds = @import("binds.zig");
const P = mathx.P;
const CONFIRM = menu.CONFIRM;
const BACK = menu.BACK;
const CHANGE = menu.CHANGE;
const REMOVE = menu.REMOVE;
const plural = mathx.plural;

const SLOT_MID: i32 = @divTrunc(game.SLOT_PX, 2);
const CLEAR_GLYPH: i32 = @divTrunc(game.SLOT_PX, 2);
const SLOT_EDGE_INSET: i32 = look.HUD_BORDER_CUT - 3;
const SLOT_EDGE_W: f32 = 2;
const BIND_TOP: i32 = menu.PANEL_PAD;
const BIND_X0: i32 = @divTrunc(BIND_W - game.SKILLS_W, 2);
const BIND_TITLE: i32 = 32;
const BIND_ROWS_DY: i32 = BIND_TITLE + font.LABEL + 3 * BIND_POP_DY + game.SLOT_PX;
const BIND_LABEL_GAP: i32 = 6;
const BIND_ROW_GAP: i32 = 24;
const BIND_ROW_H: i32 = font.BODY + BIND_LABEL_GAP + game.SLOT_COLUMN_H + BIND_ROW_GAP;
const BIND_POP_DY: i32 = 10;
const BIND_INFO_DY: i32 = 8;
const BIND_DESC_DY: i32 = font.HEAD + BIND_LABEL_GAP;

fn bindRowY(row: usize) i32 {
    return BIND_TOP + BIND_ROWS_DY + @as(i32, @intCast(row)) * BIND_ROW_H;
}

fn bindSlotY(row: usize) i32 {
    return bindRowY(row) + font.BODY + BIND_LABEL_GAP;
}

pub fn bindSlotBox(row: usize, col: usize) rl.Rectangle {
    return raster.rect(BIND_X0 + game.SLOT_XS[col], bindSlotY(row), game.SLOT_PX, game.SLOT_PX);
}

const BindAction = struct {
    button: input.Button,
    label: [:0]const u8,
    browse_only: bool,

    pub fn shown(a: BindAction, b: *const binds.Binds) bool {
        return b.menu == .browse or !a.browse_only;
    }
};
pub const BIND_ACTIONS = [_]BindAction{
    .{ .button = CONFIRM, .label = "Choose skill", .browse_only = false },
    .{ .button = CHANGE, .label = "All skills", .browse_only = true },
    .{ .button = REMOVE, .label = "Clear slot", .browse_only = true },
    .{ .button = BACK, .label = "Back", .browse_only = false },
};
const BIND_ACTION = menu.ACTION_BOX;
const BIND_ACTION_STEP: i32 = BIND_ACTION.x + menu.ACTION_GAP;
const BIND_ACTIONS_W: i32 = BIND_ACTIONS.len * BIND_ACTION_STEP - menu.ACTION_GAP;
/// As wide as the bar or the actions, whichever is wider; descriptions wrap to it.
const BIND_DESC_W: i32 = @max(game.SKILLS_W, BIND_ACTIONS_W);
const BIND_W: i32 = BIND_DESC_W + 2 * menu.PANEL_PAD;
const BIND_ACTION_GAP: i32 = 16;

fn bindInfoY() i32 {
    return bindRowY(skillbar.SETS.len) + BIND_INFO_DY;
}

/// Descriptions wrap the same however the panel scales.
fn bindFace(g: *const game.Game) font.Face {
    return g.face.mipmapped();
}

fn descLines(g: *const game.Game, face: *const font.Face, act: skillbar.Act) usize {
    var desc: [TIP_BODY_MAX + 1]u8 = undefined;
    var buf: font.Wrapped = undefined;
    var lines: [font.WRAP_LINES_MAX][:0]const u8 = undefined;
    return font.wrap(face, describe(g, act, &desc), font.SMALL, BIND_DESC_W, &buf, &lines);
}

/// Tall enough for the longest description among the skills it can bind, so it keeps its size while browsing.
pub fn bindPanel(g: *const game.Game) P {
    const face = bindFace(g);
    var kit_buf: skillbar.KitBuf = undefined;
    var lines: usize = 1;
    for (g.growth.kit(g.class, &kit_buf)) |act| lines = @max(lines, descLines(g, &face, act));
    const desc_h = @as(i32, @intCast(lines)) * (font.SMALL + 4);
    return .{ .x = BIND_W, .y = bindInfoY() + BIND_DESC_DY + desc_h + BIND_ACTION_GAP + BIND_ACTION.y + menu.PANEL_PAD };
}

pub fn bindSurface(g: *const game.Game, panel: P) menu.Surface {
    return menu.Surface.like(g.screen, panel, book.SIZE);
}

pub fn bindActionBox(panel: P, i: usize) rl.Rectangle {
    const x = @divTrunc(panel.x - BIND_ACTIONS_W, 2) + @as(i32, @intCast(i)) * BIND_ACTION_STEP;
    return raster.rect(x, panel.y - menu.PANEL_PAD - BIND_ACTION.y, BIND_ACTION.x, BIND_ACTION.y);
}

const SlotLook = struct { act: ?skillbar.Act, key: ?input.Button, edge: ?rl.Color = null, faded: bool = false };

fn drawSlot(g: *game.Game, box: rl.Rectangle, s: SlotLook) void {
    const x: i32 = @intFromFloat(box.x);
    const y: i32 = @intFromFloat(box.y);
    const a: f32 = if (s.faded) look.FADED_A else 1;
    look.hudPanel(&g.sprites, x, y, game.SLOT_PX, game.SLOT_PX, look.fade(if (s.act == null) look.SLOT_EMPTY else look.SLOT_BG, a), look.fade(look.LIT, a));
    if (s.edge) |edge| {
        rl.drawRectangleLinesEx(raster.grown(box, @floatFromInt(-SLOT_EDGE_INSET)), SLOT_EDGE_W, look.fade(edge, a));
    }
    if (s.act) |act| {
        const inset = @divTrunc(game.SLOT_PX - line_icons.SKILL_PX, 2);
        line_icons.drawSkill(&g.sprites, act, x + inset, y + inset, a);
    }
    const p = prompt_icon.Prompt.of(&g.st, s.key orelse return);
    p.draw(&g.face, x + SLOT_MID, y + game.SLOT_PX + game.KEY_GAP + @divTrunc(game.PROMPT_PX, 2), game.PROMPT_PX, a);
}

/// While aiming, the set the reticle's skill was taken from, whatever is held now.
fn shownSet(g: *const game.Game) skillbar.Set {
    return if (g.mode == .aim) g.aim_set else skills.activeSet(g);
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
    return raster.rect(layout.skills.x + game.SLOT_XS[i], layout.skills.y, game.SLOT_PX, game.SLOT_PX);
}

fn drawSkills(g: *game.Game, layout: hud.Layout) void {
    const mana = game.manaShown(g);
    for (skillbar.SLOTS, 0..) |b, i| {
        const box = slotBox(layout, i);
        const held = (g.st.held(b) and game.playShown(g)) or (g.mode == .aim and g.aim_by == b) or (b == g.bar.modifier and g.mouse.secondary);
        const s = slotShown(g, i);
        drawSlot(g, box, .{
            .act = if (s) |v| v.act else null,
            .key = b,
            .edge = if (held) look.SLOT_HELD else null,
            .faded = if (s) |v| skills.blocked(g, v.act, &g.flasks_shown, mana) != null else false,
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
        return p.win.from * binds.PICK_COLS;
    }

    pub fn end(p: BindPicker) usize {
        return @min(p.picks, (p.win.from + p.win.len) * binds.PICK_COLS);
    }

    pub fn cell(p: BindPicker, i: usize) rl.Rectangle {
        return raster.rect(p.x + @as(i32, @intCast(i % binds.PICK_COLS)) * game.SLOT_STEP, p.y + @as(i32, @intCast(i / binds.PICK_COLS - p.win.from)) * game.SLOT_STEP, game.SLOT_PX, game.SLOT_PX);
    }
};

pub fn bindPicker(b: binds.Binds, picks: usize) BindPicker {
    const pop_y = BIND_TOP + BIND_TITLE + font.LABEL + 2 * BIND_POP_DY;
    const win = menu.Window.of(binds.pickRows(picks), b.menu.pick / binds.PICK_COLS, 1);
    const w = @as(i32, @intCast(@min(picks, binds.PICK_COLS))) * game.SLOT_STEP - game.SLOT_GAP;
    return .{ .win = win, .picks = picks, .x = BIND_X0, .y = pop_y, .w = w, .h = game.SLOT_PX };
}

/// Centred across the bind panel.
fn bindText(g: *const game.Game, panel: P, s: [:0]const u8, y: i32, size: i32, col: rl.Color) void {
    menu.mid(g.face, panel, s, y, size, col);
}

pub fn drawBinds(g: *game.Game) void {
    game.character.veil(g);
    const panel = bindPanel(g);
    const desc_face = bindFace(g);
    const surface = bindSurface(g, panel);
    surface.beginPanel(&g.sprites, panel);
    defer rl.endMode2D();
    const face = g.face;
    g.face = surface.faceFor(face);
    defer g.face = face;
    const b = g.binds;
    menu.heading(g.face, panel, "BIND SKILLS", BIND_TOP, BIND_TITLE, look.TEXT, look.UI_GOLD);
    for (skillbar.SETS, 0..) |set, row| {
        g.face.text(set.name(), BIND_X0, bindRowY(row), font.BODY, look.DIM);
        for (skillbar.SLOTS, 0..) |key, i| {
            drawSlot(g, bindSlotBox(row, i), .{
                .act = g.bar.at(.{ .set = set, .button = key }),
                .key = key,
                .edge = if (row == b.row and i == b.col) look.SLOT_CURSOR else null,
            });
        }
    }
    const info_y = bindInfoY();
    var shown: ?skillbar.Act = b.assigning orelse g.bar.at(b.slot());
    switch (b.menu) {
        .browse => {},
        .pick => |pick| {
            var kit_buf: skillbar.KitBuf = undefined;
            const kit = g.growth.kit(g.class, &kit_buf);
            shown = binds.pickAct(kit, pick);
            const picker = bindPicker(b, binds.picksOf(kit));
            var label: menu.Note(100) = .{};
            label.say("Choose skill  /  {d}-{d} of {d}", .{ picker.first() + 1, picker.end(), picker.picks });
            g.face.draw(label.text(), picker.x, picker.y - font.LABEL - BIND_POP_DY, font.LABEL, look.DIM);
            rl.drawRectangleRec(raster.grown(raster.rect(picker.x, picker.y, picker.w, picker.h), @floatFromInt(game.SLOT_GAP)), look.PICK_BG);
            for (picker.first()..picker.end()) |i| {
                const r = picker.cell(i);
                const x: i32 = @intFromFloat(r.x);
                const y: i32 = @intFromFloat(r.y);
                const act = binds.pickAct(kit, i);
                const edge: ?rl.Color = if (i == pick) look.SLOT_CURSOR else if (act == null) look.SLOT_CLEAR else null;
                drawSlot(g, r, .{ .act = act, .key = null, .edge = edge });
                if (act == null) g.face.glyph(look.CLEAR.ch, x + SLOT_MID, y + SLOT_MID, CLEAR_GLYPH, look.CLEAR.fg);
            }
        },
    }
    if (shown) |a| {
        g.face.draw(a.name(), menu.PANEL_PAD, info_y, font.HEAD, look.TEXT);
        var desc: [TIP_BODY_MAX + 1]u8 = undefined;
        const text = describe(g, a, &desc);
        _ = desc_face.paragraph(text, menu.PANEL_PAD, info_y + BIND_DESC_DY, BIND_DESC_W, font.SMALL, look.TEXT);
    } else if (b.menu == .pick) {
        bindText(g, panel, "Clear slot", info_y, font.BODY, look.TEXT);
    }
    for (BIND_ACTIONS, 0..) |action, i| {
        if (!action.shown(&b)) continue;
        const label = if (action.button == CONFIRM and b.assigning != null and b.menu == .browse) "Assign skill" else action.label;
        menu.action(&g.face, bindActionBox(panel, i), prompt_icon.Prompt.menuOf(&g.st, action.button), label);
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
    act.describe(w, game.heroPerks(g));
    w.writeAll(" ") catch {};
    g.growth.writeUsage(act, w);
    w.writeAll(".") catch {};
}

const Life = struct { hp: i32, max: i32 };

pub fn settleResources(g: *game.Game) void {
    g.life_fill = lifeFill(g);
    g.mana_fill = manaFill(g);
}

/// Where the orbs' fills are easing to.
pub fn lifeFill(g: *const game.Game) f32 {
    const life = lifeShown(g);
    return hud.fillOf(life.hp, life.max);
}

pub fn manaFill(g: *const game.Game) f32 {
    return hud.fillOf(game.manaShown(g), game.manaMax(g));
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
    if (game.heroShown(g)) |h| hud.statuses(layout, &g.sprites, &g.face, h.status, h.resilience.peak().percent);
    game.mouseControls.draw(g);
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
    if (g.st.pointing()) {
        for (spots) |part| if (under(part, g.st.pointer.?)) {
            g.inspecting = part.spot;
            return;
        };
        if (g.st.click) g.mode = .play;
    }
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

fn round(s: game.Spot) bool {
    return s == .life or s == .mana;
}

fn under(s: Part, p: mathx.P) bool {
    return if (round(s.spot)) rl.checkCollisionPointCircle(raster.vec(p), raster.middle(s.box), s.box.width / 2) else raster.holds(s.box, p);
}

pub fn hovered(g: *const game.Game) ?Part {
    if (!game.playShown(g) and g.mode != .aim) return null;
    const p = g.st.pointer orelse return null;
    var buf: [SPOTS_MAX]Part = undefined;
    for (spotsOf(g, &buf)) |s| {
        if (under(s, p)) return s;
    }
    return null;
}

pub fn drawTips(g: *game.Game) void {
    if (g.mode == .inspect) {
        var buf: [SPOTS_MAX]Part = undefined;
        const spots = spotsOf(g, &buf);
        drawTip(g, inspected(g, spots));
    } else if (!g.st.device.pad()) {
        if (hovered(g)) |here| drawTip(g, here);
    }
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
            .body = std.fmt.bufPrint(body_buf, comptime hud.table(.{ .{ "Current", "{d}" }, .{ "Maximum", "{d}" }, .{ std.fmt.comptimePrint("Recovery / {d} turns", .{heroes.MANA_REGEN_TURNS}), "{d}" } }), .{ game.manaShown(g), game.manaMax(g), game.manaRegen(g) }) catch "",
        },
        .slot => |i| blk: {
            const v = slotShown(g, i) orelse break :blk .{ .title = "Empty skill slot", .body = "No skill is bound here." };
            const act = v.act;
            var body = std.io.fixedBufferStream(body_buf);
            const w = body.writer();
            writeDescription(g, act, w);
            if (act.reticle() != null) w.print("\nRange: {d} cells", .{act.reach()}) catch {};
            if (g.growth.hit(game.heroAttrs(g), g.inventory.gear, act)) |h| {
                if (h.physical.hi > 0) w.print("\n" ++ damage.PHYSICAL_FMT, .{ h.physical.lo, h.physical.hi }) catch {};
                if (h.element) |e| w.print("\n" ++ damage.ELEMENT_FMT, .{ menu.named(act.element().?), e.lo, e.hi }) catch {};
                w.print("\n" ++ attrs.SCALES_FMT, .{menu.named(h.style.attr())}) catch {};
            }
            if (v.drinks) |n|
                w.print("\n{d} drink{s} left", .{ n, plural(n) }) catch {}
            else if (v.cooling > 0)
                w.print("\nReady in {d} turn{s}", .{ v.cooling, plural(v.cooling) }) catch {};
            const rank = g.growth.ranks.get(act);
            break :blk .{ .title = if (rank > 0) std.fmt.bufPrintZ(title_buf, "{s} - Rank {d}", .{ act.name(), rank }) catch act.name() else act.name(), .body = body.getWritten() };
        },
        .status => |st| blk: {
            if (st == .resistant) {
                var body = std.io.fixedBufferStream(body_buf);
                const w = body.writer();
                w.writeAll(st.about()) catch {};
                if (game.heroShown(g)) |h| for (std.enums.values(@import("../play/resilience.zig").Kind)) |kind| {
                    const m = h.resilience.meters.get(kind);
                    if (m.turns > 0) w.print("\n{s}: {d}% resistance, {d} turns", .{ menu.named(kind), m.percent, m.turns }) catch {};
                };
                break :blk .{ .title = st.title(), .body = body.getWritten() };
            }
            const turns = if (game.heroShown(g)) |h| h.status.get(st) else 0;
            break :blk .{
                .title = std.fmt.bufPrintZ(title_buf, "{s}, {d} turn{s}", .{ st.title(), turns, plural(turns) }) catch st.title(),
                .body = st.about(),
            };
        },
    };
}
