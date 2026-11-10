const std = @import("std");
const rl = @import("raylib");
const mathx = @import("../core/mathx.zig");
const script = @import("../map/script.zig");
const grid = @import("../map/grid.zig");
const atlas = @import("../map/atlas.zig");
const actor = @import("../play/actor.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");
const editor = @import("editor.zig");
const widgets = @import("widgets.zig");
const text_panel = @import("text_panel.zig");
const modals = @import("modals.zig");
const interaction = @import("interaction.zig");
const Script = script.Script;

const PAD = widgets.PAD;
const GAP = widgets.GAP;
const ROW = widgets.ROW_H;
const STEP = widgets.ROW_STEP;
const TEXT = widgets.TEXT;
const DETAIL = widgets.DETAIL;
const LABEL_W: i32 = 130;
const SUB_W: i32 = 100;
const SUB_X: i32 = LABEL_W - SUB_W;
const DROP_W: i32 = widgets.ROW_H;
const BTN_W: i32 = 200;
const TALK_W: i32 = 320;
const TARGET_W: i32 = 300;
const WHICH_W: i32 = 260;
const NEW_W: i32 = 90;
const NAME_BTN_W: i32 = 210;
const NAME_BTN_GAP: i32 = 10;
const TOGGLE_W: i32 = 160;
const PRIORITY_LABEL_W: i32 = 90;
const PRIORITY_W: i32 = 140;
const CHOICE_ADD_W: i32 = 120;
const COND_ADD_W: i32 = 160;
const NAME_ADD_W: i32 = 50;
const OP_W: i32 = 150;
const COUNTOP_W: i32 = 130;
const ELAPSED_W: i32 = 180;
const REGION_W: i32 = 400;
const FOE_W: i32 = 220;
const NUMBER_W: i32 = 150;
const UNIT_W: i32 = 170;
const SPLIT_VALUE_W: i32 = 24;
const SPLIT_MIN_W: i32 = widgets.stepperW(SPLIT_VALUE_W);
const LIST_PARTS: i32 = 5;
const LIST_MIN_W: i32 = 240;
const LIST_MAX_W: i32 = 330;
const LINES_PARTS: i32 = 4;
const LINES_MIN_W: i32 = 200;
const LINES_MAX_W: i32 = 300;
const KIND_PARTS: i32 = 3;
const KIND_MIN_W: i32 = 150;
const KIND_MAX_W: i32 = 200;
const SILENT = "(says nothing)";
const SAY_ROWS: i32 = 4;
const WHEEL_NOTCH: i32 = 2;

pub const Page = enum {
    dialogs,
    script,
    quests,

    pub fn label(p: Page) [:0]const u8 {
        return switch (p) {
            .dialogs => "Dialog",
            .script => "Script",
            .quests => "Quests",
        };
    }

    pub fn tip(p: Page) [:0]const u8 {
        return switch (p) {
            .dialogs => "NPCs and the conversations they open: lines, choices and what each does",
            .script => "Triggers: when every condition holds after a turn, their actions run in order",
            .quests => "Quests the journal lists: titles, and what each stage asks; actions give and finish them",
        };
    }
};

const LineAt = struct { d: u8, l: u8 };
const StageAt = struct { q: u8, k: u8 };
const ChoiceAt = struct { d: u8, l: u8, c: u8 };
const TableAt = struct { t: script.Table, i: u8 };
/// An action in place: a trigger's, a line's or a choice's.
const ActAt = union(enum) {
    trigger: struct { t: u8, a: u8 },
    line: struct { d: u8, l: u8, a: u8 },
    choice: struct { d: u8, l: u8, c: u8, a: u8 },
};
/// The one piece of words being typed into, written to the map as it is typed.
const Focus = union(enum) {
    npc: u8,
    dialog: u8,
    line: LineAt,
    who: LineAt,
    say: LineAt,
    ask: ChoiceAt,
    trigger: u8,
    table: TableAt,
    note: ActAt,
    quest: u8,
    title: u8,
    stage: StageAt,
};
pub const Pick = union(enum) { none, npc: u8, dialog: u8 };

pub const State = struct {
    pick: Pick = .none,
    line: u8 = 0,
    trigger: ?u8 = null,
    quest: ?u8 = null,
    focus: ?Focus = null,
    field: Field = .{},
    /// A field took this frame's click.
    claimed: bool = false,
    list: widgets.Scrolled = .{},
    detail: widgets.Scrolled = .{},
    /// The script's lists as the page last drew them; a picked index means nothing once they changed elsewhere.
    seen: Seen = .{},

    fn pickDialog(s: *State, d: u8) void {
        s.pick = .{ .dialog = d };
        s.line = 0;
    }

    /// Each pick dropped once the list it indexes has shrunk past it.
    fn fit(s: *State, m: *const Script) void {
        switch (s.pick) {
            .npc => |i| if (i >= m.npc_n) {
                s.pick = .none;
            },
            .dialog => |i| if (i >= m.dialog_n) {
                s.pick = .none;
            },
            .none => {},
        }
        if (s.trigger) |t| if (t >= m.trigger_n) {
            s.trigger = null;
        };
        if (s.quest) |q| if (q >= m.quest_n) {
            s.quest = null;
        };
    }
};

pub const Seen = struct {
    npcs: usize = 0,
    dialogs: usize = 0,
    triggers: usize = 0,
    quests: usize = 0,

    pub fn of(m: *const script.Script) Seen {
        return .{ .npcs = m.npc_n, .dialogs = m.dialog_n, .triggers = m.trigger_n, .quests = m.quest_n };
    }
};

pub fn openNpc(ed: *editor.Editor, i: u8) void {
    open(ed, .dialogs);
    ed.plot.pick = .{ .npc = i };
}

pub fn open(ed: *editor.Editor, p: Page) void {
    ed.plot.focus = null;
    ed.plot.detail.top = 0;
    if (!std.meta.eql(ed.plot.seen, Seen.of(&ed.map.script))) {
        ed.plot.pick = .none;
        ed.plot.trigger = null;
        ed.plot.quest = null;
    }
    if (p == .dialogs and ed.plot.pick == .none and ed.map.script.dialog_n > 0) ed.plot.pick = .{ .dialog = 0 };
    if (p == .script and ed.plot.trigger == null and ed.map.script.trigger_n > 0) ed.plot.trigger = 0;
    if (p == .quests and ed.plot.quest == null and ed.map.script.quest_n > 0) ed.plot.quest = 0;
    ed.ask(.{ .plot = p });
}

pub fn keys(ed: *editor.Editor) void {
    const d = &ed.desk;
    const s = &ed.plot;
    if (d.save) _ = ed.save();
    if (d.undo or d.redo) {
        s.focus = null;
        if (d.undo) ed.undo() else ed.redo();
    }
    if (d.clicked()) ed.gesture();
    if (d.undo or d.redo) return;
    if (d.wheel != 0) {
        const by = d.notch() * WHEEL_NOTCH;
        s.list.wheel(d.mouse, by);
        s.detail.wheel(d.mouse, by);
    }
    if (s.focus) |f| {
        const t = (if (d.back or d.enter) null else target(&ed.map.script, f)) orelse {
            s.focus = null;
            return;
        };
        return typed(ed, t);
    }
    if (interaction.backed(d)) close(ed);
}

fn close(ed: *editor.Editor) void {
    ed.plot.focus = null;
    ed.modal = .none;
}

fn typed(ed: *editor.Editor, t: Target) void {
    const s = &ed.plot;
    if (!s.field.feed(&ed.desk, false)) return ed.say("Plain letters on one line, {d} at most", .{s.field.cap});
    const now = std.mem.trim(u8, s.field.text(), " ");
    const was = t.words.text();
    if (std.mem.eql(u8, now, was)) return;
    if (put(&ed.map.script, t, now)) return ed.bank();
    if (t.unique == null) s.field.set(was);
    ed.say("{s}", .{if (t.unique != null) "A name is letters, digits, _ or -, not taken, " ++ std.fmt.comptimePrint("{d}", .{script.NAME_MAX}) ++ " at most" else "That is as long as it can be"});
}

/// The words a focus types into; a name the map reads back is unique in its list.
const Target = struct { words: Words, unique: ?Unique = null };

const Words = union(enum) {
    name: *script.Name,
    who: *script.Who,
    say: *script.Say,
    ask: *script.Ask,
    note: *script.Note,
    title: *script.Title,

    fn text(w: Words) []const u8 {
        return switch (w) {
            inline else => |p| p.text(),
        };
    }

    fn most(w: Words) usize {
        return switch (w) {
            inline else => |p| @TypeOf(p.*).MAX,
        };
    }

    fn set(w: Words, s: []const u8) bool {
        return switch (w) {
            inline else => |p| p.set(s),
        };
    }
};

const Field = text_panel.FieldOf(WORDS_MAX, plainChar);
const WORDS_MAX = blk: {
    var most: usize = 0;
    for (std.meta.fields(Words)) |f| most = @max(most, std.meta.Child(f.type).MAX);
    break :blk most;
};

fn plainChar(c: u8) bool {
    return script.plain(&[_]u8{c});
}

const Unique = union(enum) { dialog: u8, line: LineAt, trigger: u8, table: TableAt, quest: u8 };

fn target(m: *Script, f: Focus) ?Target {
    return switch (f) {
        .npc => |i| if (i < m.npc_n) .{ .words = .{ .who = &m.npc[i].name } } else null,
        .dialog => |i| if (i < m.dialog_n) .{ .words = .{ .name = &m.dialog[i].name }, .unique = .{ .dialog = i } } else null,
        .line => |at| if (lineOf(m, at)) |ln| .{ .words = .{ .name = &ln.name }, .unique = .{ .line = at } } else null,
        .who => |at| if (lineOf(m, at)) |ln| .{ .words = .{ .who = &ln.who } } else null,
        .say => |at| if (lineOf(m, at)) |ln| .{ .words = .{ .say = &ln.say } } else null,
        .ask => |at| if (choiceOf(m, at)) |c| .{ .words = .{ .ask = &c.ask } } else null,
        .trigger => |i| if (i < m.trigger_n) .{ .words = .{ .name = &m.trigger[i].name }, .unique = .{ .trigger = i } } else null,
        .table => |at| if (at.i < m.names(at.t).len) .{ .words = .{ .name = tableName(m, at) }, .unique = .{ .table = at } } else null,
        .note => |at| if (actOf(m, at)) |a| .{ .words = .{ .note = &a.note } } else null,
        .quest => |i| if (i < m.quest_n) .{ .words = .{ .name = &m.quest[i].name }, .unique = .{ .quest = i } } else null,
        .title => |i| if (i < m.quest_n) .{ .words = .{ .title = &m.quest[i].title } } else null,
        .stage => |at| if (at.q < m.quest_n and at.k < m.quest[at.q].stage_n) .{ .words = .{ .note = &m.quest[at.q].stage[at.k] } } else null,
    };
}

fn put(m: *Script, t: Target, s: []const u8) bool {
    const u = t.unique orelse return t.words.set(s);
    return switch (u) {
        .dialog => |i| script.renameIn(m.dialog[0..m.dialog_n], i, s),
        .line => |at| script.renameIn(m.dialog[at.d].line[0..m.dialog[at.d].line_n], at.l, s),
        .trigger => |i| script.renameIn(m.trigger[0..m.trigger_n], i, s),
        .table => |at| m.rename(at.t, at.i, s),
        .quest => |i| script.renameIn(m.quest[0..m.quest_n], i, s),
    };
}

fn tableName(m: *Script, at: TableAt) *script.Name {
    return switch (at.t) {
        inline else => |t| &@field(m.*, @tagName(t))[at.i],
    };
}

fn lineOf(m: *Script, at: LineAt) ?*script.Line {
    if (at.d >= m.dialog_n or at.l >= m.dialog[at.d].line_n) return null;
    return &m.dialog[at.d].line[at.l];
}

fn choiceOf(m: *Script, at: ChoiceAt) ?*script.Choice {
    const ln = lineOf(m, .{ .d = at.d, .l = at.l }) orelse return null;
    return if (at.c < ln.choice_n) &ln.choice[at.c] else null;
}

const ActList = struct { items: []script.Act, n: *u8 };

fn listOf(m: *Script, at: ActAt) ?ActList {
    return switch (at) {
        .trigger => |t| if (t.t < m.trigger_n) .{ .items = &m.trigger[t.t].act, .n = &m.trigger[t.t].act_n } else null,
        .line => |l| if (lineOf(m, .{ .d = l.d, .l = l.l })) |ln| .{ .items = &ln.act, .n = &ln.act_n } else null,
        .choice => |c| if (choiceOf(m, .{ .d = c.d, .l = c.l, .c = c.c })) |ch| .{ .items = &ch.act, .n = &ch.act_n } else null,
    };
}

fn actOf(m: *Script, at: ActAt) ?*script.Act {
    const list = listOf(m, at) orelse return null;
    const a = switch (at) {
        inline else => |p| p.a,
    };
    return if (a < list.n.*) &list.items[a] else null;
}

/// One frame of a page; a click no field took leaves the words.
pub fn draw(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.plot;
    s.claimed = false;
    const clicked = ed.desk.paint_hit;
    if (s.focus) |f| if (target(&ed.map.script, f) == null) {
        s.focus = null;
    };
    s.fit(&ed.map.script);
    switch (ed.modal.plot) {
        .script => drawScript(ed, g),
        .dialogs => drawDialogs(ed, g),
        .quests => drawQuests(ed, g),
    }
    if (clicked and !s.claimed and !ed.fresh) s.focus = null;
    s.seen = Seen.of(&ed.map.script);
}

const Frame = struct {
    x: i32,
    y: i32,
    w: i32,
    bottom: i32,

    fn listW(f: Frame) i32 {
        return widgets.share(f.w, LIST_PARTS, LIST_MIN_W, LIST_MAX_W);
    }
};

/// Widths across `w` in proportion to `shares`, each held to its cap, a gap between each.
fn split(w: i32, comptime shares: []const i32, comptime caps: []const i32) [shares.len]i32 {
    var total: i32 = 0;
    inline for (shares) |s| total += s;
    const room = w - GAP * @as(i32, @intCast(shares.len - 1));
    var out: [shares.len]i32 = undefined;
    inline for (shares, caps, 0..) |s, cap, i| out[i] = @max(SPLIT_MIN_W, @min(cap, @divTrunc(room * s, total)));
    return out;
}

const Split = struct { shares: []const i32, caps: []const i32 };
const NAME_CMP_NUMBER = Split{ .shares = &.{ 4, 3, 3 }, .caps = &.{ WHICH_W, OP_W, NUMBER_W } };
const NAME_OP_NUMBER = Split{ .shares = &.{ 4, 3, 3 }, .caps = &.{ WHICH_W, COUNTOP_W, NUMBER_W } };
const NAME_TOGGLE = Split{ .shares = &.{ 3, 2 }, .caps = &.{ WHICH_W, TOGGLE_W } };
const NAME_UNITS = Split{ .shares = &.{ 3, 2 }, .caps = &.{ WHICH_W, UNIT_W } };

fn splitBy(w: i32, comptime s: Split) [s.shares.len]i32 {
    return split(w, s.shares, s.caps);
}

fn listArea(ed: *editor.Editor, f: Frame) widgets.Scroll {
    return ed.plot.list.at(raster.rect(f.x, f.y, f.listW(), f.bottom - f.y));
}

/// Ends the list at `y`; the column right of it, past its divider.
fn rightOf(ed: *editor.Editor, f: Frame, list: widgets.Scroll, y: i32) widgets.Column {
    list.close(&ed.clip, y, 0);
    const x = widgets.besides(f.x, f.listW(), f.y, f.bottom);
    return .{ .x = x, .w = f.x + f.w - x };
}

fn frameOf(ed: *editor.Editor, g: *game.Game, p: Page) Frame {
    const page = widgets.pageFrame(&g.face, g.screen, p.label());
    const f = page.frame;
    if (modals.backPressed(ed, g, f, page.bottom - ROW, "Close", "Every change is in the map already; it saves with it")) close(ed);
    const col = page.column();
    return .{ .x = col.left(), .y = f.y, .w = col.inner(), .bottom = page.bottom - ROW - GAP };
}

/// A list's heading with its count, and a "+ New" at its end; whether that was pressed.
fn listHead(ed: *editor.Editor, g: *game.Game, f: Frame, y: i32, comptime title: []const u8, n: usize, most: usize, tip: [:0]const u8) bool {
    countHeading(g, f.x, y, f.listW(), title, n, most);
    return rightButton(ed, g, f.x + f.listW() - GAP, y, NEW_W, "+ New", n < most, tip);
}

/// A row of the list; picking it scrolls the detail back to its top.
fn listRow(ed: *editor.Editor, g: *game.Game, f: Frame, y: i32, label: []const u8, on: bool, tip: [:0]const u8) bool {
    const hit = button(ed, g, widgets.row(f.x, y, f.listW() - GAP), label, on, true, tip);
    if (hit) ed.plot.detail.top = 0;
    return hit;
}

/// The picked item's detail, scrolled within the column right of the list.
fn detailPane(ed: *editor.Editor, g: *game.Game, x: i32, top: i32, w: i32, bottom: i32, comptime body: fn (*editor.Editor, *game.Game, u8, i32, i32, i32) i32, i: u8) void {
    const area = ed.plot.detail.at(raster.rect(x, top, w, bottom - top));
    const end = body(ed, g, i, x, area.begin(&ed.clip), w - PAD);
    area.close(&ed.clip, end, 0);
}

/// A delete button's words: what still names it, or that it can go.
fn dropLabel(buf: []u8, users: usize, comptime noun: []const u8) [:0]const u8 {
    if (users > 0) return std.fmt.bufPrintZ(buf, "Used {d} times", .{users}) catch "";
    return "Delete " ++ noun;
}

fn beforeDrop(w: i32) i32 {
    return w - LABEL_W - DROP_W - GAP;
}

/// A condition that may be absent: its row and a drop, or a button that adds one.
fn optCond(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, c: *?script.Cond, drop_tip: [:0]const u8, add_tip: [:0]const u8) void {
    if (c.*) |*cond| {
        condRow(ed, g, x + LABEL_W, y, beforeDrop(w), cond);
        if (dropButton(ed, g, x + w, y, true, drop_tip)) {
            c.* = null;
            ed.bank();
        }
    } else if (button(ed, g, widgets.row(x + LABEL_W, y, BTN_W), "+ Condition", false, true, add_tip)) {
        c.* = .{ .kind = .always };
        ed.bank();
    }
}

const button = editor.modalButton;

fn rightButton(ed: *editor.Editor, g: *game.Game, right: i32, y: i32, w: i32, label: []const u8, live: bool, tip: ?[:0]const u8) bool {
    return button(ed, g, widgets.row(right - w, y, w), label, false, live, tip);
}

fn dropButton(ed: *editor.Editor, g: *game.Game, right: i32, y: i32, live: bool, tip: [:0]const u8) bool {
    return rightButton(ed, g, right, y, DROP_W, widgets.DROP, live, tip);
}

fn dropRow(ed: *editor.Editor, g: *game.Game, right: i32, y: i32, tip: [:0]const u8, comptime T: type, items: []T, n: *u8, i: usize) bool {
    if (!dropButton(ed, g, right, y, true, tip)) return false;
    script.cut(T, items, n, i);
    ed.bank();
    return true;
}

/// A name's row: its label, its words, and a button at its end; whether that was pressed.
fn nameRow(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, label: []const u8, f: Focus, act: [:0]const u8, live: bool, tip: [:0]const u8) bool {
    caption(g, x, y, LABEL_W, label, look.TEXT);
    words(ed, g, widgets.row(x + LABEL_W, y, w - LABEL_W - NAME_BTN_W - NAME_BTN_GAP), f, "");
    return rightButton(ed, g, x + w, y, NAME_BTN_W, act, live, tip);
}

fn wordsRow(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, label: []const u8, f: Focus, blank: []const u8) void {
    caption(g, x, y, LABEL_W, label, look.TEXT);
    words(ed, g, widgets.row(x + LABEL_W, y, w - LABEL_W), f, blank);
}

fn caption(g: *game.Game, x: i32, y: i32, w: i32, s: []const u8, col: rl.Color) void {
    widgets.rowText(&g.face, s, DETAIL, x, y, w, col);
}

fn heading(g: *game.Game, x: i32, y: i32, w: i32, s: []const u8) void {
    widgets.rowText(&g.face, s, TEXT, x, y, w, look.UI_GOLD);
}

fn countHeading(g: *game.Game, x: i32, y: i32, w: i32, comptime title: []const u8, n: usize, most: usize) void {
    var buf: [widgets.LINE]u8 = undefined;
    heading(g, x, y, w, std.fmt.bufPrint(&buf, title ++ " {d}/{d}", .{ n, most }) catch "");
}

fn countHead(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, comptime title: []const u8, n: usize, most: usize, add_w: i32, label: []const u8, tip: [:0]const u8) bool {
    countHeading(g, x, y, w, title, n, most);
    return rightButton(ed, g, x + w, y, add_w, label, n < most, tip);
}

/// `<` and `>` round `value`; -1 or 1 as one is pressed, `SHIFT_STEP` times that when `shift`; 0 otherwise.
fn stepper(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, value: []const u8, live: bool, tip: ?[:0]const u8, shift: bool) i32 {
    const step = widgets.Step{ .tip = tip, .live = live };
    return widgets.stepper(ed.controls(), &g.face, r, value, widgets.PAGE_ARROWS, .{ step, step }, shift);
}

const cycle = mathx.cycle;

fn numberStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, v: *i32, span: script.Span, unit: []const u8, tip: [:0]const u8) void {
    var buf: [32]u8 = undefined;
    const by = stepper(ed, g, r, std.fmt.bufPrint(&buf, "{d}{s}", .{ v.*, unit }) catch "", true, tip, ed.desk.shift);
    if (by == 0) return;
    const next = span.clamp(v.* + by);
    if (next == v.*) return;
    v.* = next;
    ed.bank();
}

fn wordStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, comptime T: type, v: *T, names: *const std.EnumArray(T, []const u8), tip: ?[:0]const u8) void {
    const by = stepper(ed, g, r, names.get(v.*), true, tip, false);
    if (by == 0) return;
    v.* = cycle(T, v.*, by);
    ed.bank();
}

fn indexStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, label: []const u8, slot: *u8, n: usize, tip: [:0]const u8) void {
    const by = stepper(ed, g, r, label, n > 1, tip, false);
    if (by == 0) return;
    slot.* = @intCast(mathx.wrap(slot.*, by, n));
    ed.bank();
}

/// `v` stepped `by` round none, first, then each of the `n` it may name.
fn optionalStep(v: *?u8, by: i32, n: usize) void {
    const at: usize = if (v.*) |i| @as(usize, i) + 1 else 0;
    const to = mathx.wrap(at, by, n + 1);
    v.* = if (to == 0) null else @intCast(to - 1);
}

/// A box of words that becomes the field when clicked.
fn words(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, f: Focus, blank: []const u8) void {
    const s = &ed.plot;
    const on = if (s.focus) |now| std.meta.eql(now, f) else false;
    if (on) {
        const shown = if (ed.clip) |c| ed.mouseIn(c) else true;
        if (text_panel.drawField(ed, g, &s.field, r, true, true) or (shown and ed.mouseIn(r))) s.claimed = true;
        return;
    }
    const origin = widgets.well(r, false);
    const h = widgets.hoverHit(ed.controls(), r, true, "Click to type; it is written into the map as you type");
    const words_ = target(&ed.map.script, f).?.words;
    const now = words_.text();
    const x = origin.x;
    const y = origin.y;
    const w = widgets.insetW(r);
    if (now.len == 0) {
        widgets.drawFit(&g.face, blank, TEXT, w, false, x, y, look.DIM);
    } else if (r.height > @as(f32, @floatFromInt(text_panel.fieldHeight(1)))) {
        widgets.scissorIn(ed.clip, r);
        _ = g.face.paragraph(now, x, y, w, TEXT, look.TEXT);
        widgets.reclip(ed.clip);
    } else widgets.drawFit(&g.face, now, TEXT, w, false, x, y, look.TEXT);
    if (h.hit) {
        s.focus = f;
        s.field.limit(words_.most());
        s.field.set(now);
        s.claimed = true;
    }
}

fn drawDialogs(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.plot;
    const m = &ed.map.script;
    const f = frameOf(ed, g, .dialogs);
    const lw = f.listW();
    var buf: [widgets.LINE]u8 = undefined;
    const list = listArea(ed, f);
    var y = list.begin(&ed.clip);
    countHeading(g, f.x, y, lw, "NPCs", m.npc_n, script.MAX_NPCS);
    y += STEP;
    if (m.npc_n == 0) {
        caption(g, f.x, y, lw, "Place NPCs with their tool", look.DIM);
        y += STEP;
    }
    for (m.npcs(), 0..) |*npc, i| {
        const line = std.fmt.bufPrint(&buf, "{s}  (node {d})", .{ npc.called(), npc.node }) catch "";
        if (listRow(ed, g, f, y, line, s.pick == .npc and s.pick.npc == i, "What this NPC is called and which dialog it opens")) s.pick = .{ .npc = @intCast(i) };
        y += STEP;
    }
    y += GAP;
    if (listHead(ed, g, f, y, "Dialogs", m.dialog_n, script.MAX_DIALOGS, "A new dialog of one empty line")) {
        if (m.addDialog("")) |d| {
            ed.bank();
            s.pickDialog(d);
            s.detail.top = 0;
        }
    }
    y += STEP;
    for (m.dialogs(), 0..) |*dl, i| {
        if (listRow(ed, g, f, y, dl.name.text(), s.pick == .dialog and s.pick.dialog == i, "Its lines, what they say and where each choice goes")) s.pickDialog(@intCast(i));
        y += STEP;
    }
    const right = rightOf(ed, f, list, y);
    switch (s.pick) {
        .none => caption(g, right.x, f.y, right.w, "Pick an NPC or a dialog", look.DIM),
        .npc => |i| drawNpc(ed, g, i, right.x, f.y, right.w),
        .dialog => |i| drawDialog(ed, g, i, right.x, f.y, right.w, f.bottom),
    }
}

fn drawNpc(ed: *editor.Editor, g: *game.Game, i: u8, x: i32, top: i32, w: i32) void {
    const m = &ed.map.script;
    const npc = &m.npc[i];
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    var title: [atlas.TITLE_MAX]u8 = undefined;
    heading(g, x, y, w, std.fmt.bufPrint(&buf, "NPC on {s}", .{ed.nodeName(npc.node, &title)}) catch "");
    y += STEP;
    wordsRow(ed, g, x, y, w, "Called", .{ .npc = i }, script.STRANGER);
    y += STEP;
    caption(g, x, y, LABEL_W, "Talks with", look.TEXT);
    var talks = widgets.Lay{ .x = x + LABEL_W, .y = y };
    const by = stepper(ed, g, talks.take(TALK_W), talksTo(m, npc), m.dialog_n > 0, "Which dialog speaking to it opens", false);
    if (by != 0) {
        optionalStep(&npc.dialog, by, m.dialog_n);
        ed.bank();
    }
    if (button(ed, g, talks.take(BTN_W), "New dialog for it", false, m.dialog_n < script.MAX_DIALOGS, "A dialog of one line, named for it, that it opens")) {
        var nb: [script.NAME_MAX]u8 = undefined;
        if (m.addDialog(stemOf(&nb, npc.called()))) |d| {
            npc.dialog = d;
            ed.bank();
        }
    }
    y += STEP;
    if (npc.dialog) |d| {
        if (button(ed, g, widgets.row(x + LABEL_W, y, TALK_W), "Edit its dialog", false, true, null)) ed.plot.pickDialog(d);
        y += STEP;
    }
    caption(g, x, y, LABEL_W, "Stands", look.TEXT);
    var stands = widgets.Lay{ .x = x + LABEL_W, .y = y };
    const moved = stepper(ed, g, stands.take(TALK_W), spotWords(npc.spot, &buf), true, "On its painted cell, beside a prop, or far from the doors; the last two are found afresh on each roll of its node", false);
    if (moved != 0) stepSpot(ed, i, moved);
    switch (npc.spot) {
        .by => |*t| {
            const prop_by = stepper(ed, g, stands.take(WHICH_W), @tagName(t.*), PROPS.len > 1, "Which prop it stands beside: the first in reading order with room round it", false);
            if (prop_by != 0) {
                t.* = mathx.stepIn(grid.Tile, &PROPS, t.*, prop_by, 0);
                ed.changed();
            }
        },
        .at, .far => {},
    }
    y += STEP;
    caption(g, x, y, LABEL_W, "Stands while", look.TEXT);
    optCond(ed, g, x, y, w, &npc.shows, "Always stands", "Gone, and talked to by no one, while it does not hold");
    y += STEP;
    caption(g, x, y, LABEL_W, "Looks like", look.TEXT);
    const kinds = std.enums.values(actor.Kind);
    const looks_by = stepper(ed, g, widgets.row(x + LABEL_W, y, TALK_W), if (npc.looks) |k| actor.row(k).name else "a person", true, "The body it is drawn as", false);
    if (looks_by != 0) {
        var at: ?u8 = if (npc.looks) |k| @intCast(std.mem.indexOfScalar(actor.Kind, kinds, k).?) else null;
        optionalStep(&at, looks_by, kinds.len);
        npc.looks = if (at) |k| kinds[k] else null;
        ed.bank();
    }
    y += STEP + GAP;
    var foot = widgets.Lay{ .x = x, .y = y };
    if (button(ed, g, foot.take(BTN_W), "Show on the map", false, true, "Close and look at it")) {
        const c = editor.Editor.canvas(g);
        ed.visit(c, npc.node, npc.cell() orelse grid.MIDDLE);
        ed.preview();
        const at = ed.scene.npcSpot(ed.map, i) orelse npc.cell() orelse grid.MIDDLE;
        ed.showCell(c, at);
        close(ed);
        return;
    }
    if (button(ed, g, foot.take(BTN_W), "Remove it", false, true, "Take this NPC off the map; any trigger that waited on its nearness never fires")) {
        m.dropNpc(i);
        ed.changed();
        ed.plot.pick = .none;
    }
}

/// What an NPC may stand beside.
const PROPS = blk: {
    var out: []const grid.Tile = &.{};
    for (std.enums.values(grid.Tile)) |t| {
        if (script.besideable(t)) out = out ++ &[_]grid.Tile{t};
    }
    break :blk out[0..out.len].*;
};
const FIRST_PROP: grid.Tile = .caravan;

comptime {
    std.debug.assert(std.mem.indexOfScalar(grid.Tile, &PROPS, FIRST_PROP) != null);
}

fn spotWords(s: script.Spot, buf: []u8) []const u8 {
    return switch (s) {
        .at => |p| std.fmt.bufPrint(buf, "on its cell {d},{d}", .{ p.x, p.y }) catch "",
        .by => "beside a prop",
        .far => "far from the doors",
    };
}

/// NPC `i`'s spot stepped `by` round its kinds: a painted cell only on a painted node, and only where it now stands free.
fn stepSpot(ed: *editor.Editor, i: u8, by: i32) void {
    const npc = &ed.map.script.npc[i];
    const SpotKind = std.meta.Tag(script.Spot);
    var k = std.meta.activeTag(npc.spot);
    const cell = paintedCell(ed, i);
    for (0..std.enums.values(SpotKind).len) |_| {
        k = cycle(SpotKind, k, by);
        if (k != .at or cell != null) break;
    }
    if (k == std.meta.activeTag(npc.spot)) return;
    npc.spot = switch (k) {
        .at => .{ .at = cell.? },
        .by => .{ .by = FIRST_PROP },
        .far => .far,
    };
    ed.changed();
}

/// Where NPC `i` stands now, when that is a painted node's open cell no other NPC is painted on.
fn paintedCell(ed: *editor.Editor, i: u8) ?mathx.P {
    const npc = &ed.map.script.npc[i];
    if (npc.node != ed.node or ed.map.node[npc.node].unrolled()) return null;
    ed.preview();
    const at = ed.scene.npcSpot(ed.map, i) orelse return null;
    if (!ed.map.npcFits(npc.node, at) or ed.map.script.npcAt(npc.node, at) != null) return null;
    return at;
}

pub fn talksTo(m: *const Script, f: *const script.Npc) []const u8 {
    return if (f.dialog) |d| m.dialog[d].name.text() else "nothing to say";
}

/// A dialog name from an NPC's: its words lowered and joined by `_`, where it reads back.
fn stemOf(buf: *[script.NAME_MAX]u8, name: []const u8) []const u8 {
    var n: usize = 0;
    for (name) |c| {
        if (n == buf.len) break;
        if (std.ascii.isAlphanumeric(c)) {
            buf[n] = std.ascii.toLower(c);
            n += 1;
        } else if (n > 0 and buf[n - 1] != '_') {
            buf[n] = '_';
            n += 1;
        }
    }
    while (n > 0 and buf[n - 1] == '_') n -= 1;
    return buf[0..n];
}

fn drawDialog(ed: *editor.Editor, g: *game.Game, di: u8, x: i32, top: i32, w: i32, bottom: i32) void {
    const s = &ed.plot;
    const m = &ed.map.script;
    const d = &m.dialog[di];
    var buf: [widgets.LINE]u8 = undefined;
    s.line = @min(s.line, d.line_n - 1);
    const lines_w = widgets.share(w, LINES_PARTS, LINES_MIN_W, LINES_MAX_W);
    var y = top;
    const users = m.dialogUsers(di);
    if (nameRow(ed, g, x, y, w, "Dialog", .{ .dialog = di }, dropLabel(&buf, users, "dialog"), users == 0, "Delete it; a dialog an NPC or trigger still names cannot go")) {
        if (m.dropDialog(di)) {
            ed.bank();
            s.pick = .none;
            return;
        }
    }
    y += STEP + GAP;
    const lx = x;
    countHeading(g, lx, y, lines_w, "Lines", d.line_n, script.MAX_LINES);
    y += STEP;
    var line_buf: [script.NAME_MAX + script.SAY_MAX + 5]u8 = undefined;
    for (d.lines(), 0..) |*ln, i| {
        const first = if (ln.say.n > 0) ln.say.text() else SILENT;
        const label = std.fmt.bufPrintZ(&line_buf, "{s}{s}: {s}", .{ if (i == 0) "> " else "", ln.name.text(), first }) catch "";
        if (button(ed, g, widgets.row(lx, y, lines_w - GAP), label, s.line == i, true, if (i == 0) "Where it opens" else null)) {
            s.line = @intCast(i);
            s.detail.top = 0;
        }
        y += STEP;
    }
    const tools_w = lines_w - GAP;
    if (button(ed, g, widgets.slotOf(lx, tools_w, y, 0, 3), "+ Line", false, d.line_n < script.MAX_LINES, "Another line, reached by a choice or a then")) {
        if (d.addLine()) |l| {
            ed.bank();
            s.line = l;
        }
    }
    if (button(ed, g, widgets.slotOf(lx, tools_w, y, 1, 3), "Up", false, s.line > 0, "Earlier in the list; the first is where it opens")) {
        d.swapLines(s.line, s.line - 1);
        s.line -= 1;
        ed.bank();
    }
    if (button(ed, g, widgets.slotOf(lx, tools_w, y, 2, 3), "Delete", false, d.line_n > 1, "Delete this line; every way into it ends the dialog instead")) {
        d.dropLine(s.line);
        s.line = @min(s.line, d.line_n - 1);
        ed.bank();
    }
    const dx = widgets.besides(x, lines_w, top + STEP + GAP, bottom);
    detailPane(ed, g, dx, top + STEP + GAP, x + w - dx, bottom, drawLine, di);
}

/// The picked line of dialog `di`.
fn drawLine(ed: *editor.Editor, g: *game.Game, di: u8, x: i32, top: i32, w: i32) i32 {
    const m = &ed.map.script;
    const d = &m.dialog[di];
    const li = ed.plot.line;
    const ln = &d.line[li];
    const at = LineAt{ .d = di, .l = li };
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    wordsRow(ed, g, x, y, w, "Line", .{ .line = at }, "");
    y += STEP;
    wordsRow(ed, g, x, y, w, "Speaker", .{ .who = at }, "(blank: whoever is spoken to)");
    y += STEP;
    caption(g, x, y, LABEL_W, std.fmt.bufPrint(&buf, "Says {d}/{d}", .{ ln.say.n, script.SAY_MAX }) catch "", look.TEXT);
    const say_h = text_panel.fieldHeight(SAY_ROWS);
    words(ed, g, raster.rect(x + LABEL_W, y, w - LABEL_W, say_h), .{ .say = at }, SILENT);
    y += say_h + GAP;
    y = actRows(ed, g, x, x, y, w, "When shown", .{ .line = .{ .d = di, .l = li, .a = 0 } });
    y += GAP;
    if (countHead(ed, g, x, y, w, "Choices", ln.choice_n, script.MAX_CHOICES, CHOICE_ADD_W, "+ Choice", "Something the hero may answer")) {
        if (mathx.push(script.Choice, &ln.choice, &ln.choice_n, .{})) ed.bank();
    }
    y += STEP;
    var c: u8 = 0;
    while (c < ln.choice_n) : (c += 1) {
        const ch = &ln.choice[c];
        const cat = ChoiceAt{ .d = di, .l = li, .c = c };
        caption(g, x, y, LABEL_W, std.fmt.bufPrint(&buf, "{d}. Answer", .{c + 1}) catch "", look.TEXT);
        words(ed, g, widgets.row(x + LABEL_W, y, beforeDrop(w)), .{ .ask = cat }, "(what the hero says)");
        if (dropRow(ed, g, x + w, y, "Take this choice away", script.Choice, &ln.choice, &ln.choice_n, c)) break;
        y += STEP;
        caption(g, x + SUB_X, y, SUB_W, "goes to", look.DIM);
        targetStep(ed, g, widgets.row(x + LABEL_W, y, TARGET_W), d, &ch.next);
        y += STEP;
        caption(g, x + SUB_X, y, SUB_W, "shown if", look.DIM);
        optCond(ed, g, x, y, w, &ch.gate, "Always shown", "Hidden, not greyed, while it does not hold");
        y += STEP;
        y = actRows(ed, g, x, x + SUB_X, y, w, "does", .{ .choice = .{ .d = di, .l = li, .c = c, .a = 0 } });
        y += GAP;
    }
    const used = ln.thenUsed();
    caption(g, x, y, LABEL_W, if (used) "Then" else "Then (unused)", if (used) look.TEXT else look.DIM);
    var then = widgets.Lay{ .x = x + LABEL_W, .y = y };
    targetStep(ed, g, then.take(TARGET_W), d, &ln.then);
    caption(g, then.x, y, w - LABEL_W - TARGET_W, "where a line with no choices goes on", look.DIM);
    y += STEP;
    return y;
}

fn targetStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, d: *const script.Dialog, next: *?u8) void {
    const label = if (next.*) |n| d.line[n].name.text() else "end";
    const by = stepper(ed, g, r, label, true, "Another line of this dialog, or the end of it", false);
    if (by == 0) return;
    optionalStep(next, by, d.line_n);
    ed.bank();
}

/// The actions at `first` and those after it in the same list, with a header that adds one.
fn actRows(ed: *editor.Editor, g: *game.Game, x: i32, title_x: i32, top: i32, w: i32, title: []const u8, first: ActAt) i32 {
    const m = &ed.map.script;
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    caption(g, title_x, y, x + LABEL_W - GAP - title_x, title, look.DIM);
    const spoken = first != .trigger;
    const list = listOf(m, first).?;
    const count = list.n.*;
    const most = list.items.len;
    if (count < most and button(ed, g, widgets.row(x + LABEL_W, y, BTN_W), "+ Action", false, true, if (spoken) "Done as the line shows or the choice is taken" else "Done in order once every condition holds")) {
        var a = script.Act{ .kind = if (spoken) .flag else .text };
        fitAct(m, &a, spoken);
        if (mathx.push(script.Act, list.items, list.n, a)) ed.bank();
    } else if (count == most) caption(g, x + LABEL_W, y, w - LABEL_W, std.fmt.bufPrint(&buf, "{d} is the most", .{most}) catch "", look.DIM);
    y += STEP;
    var i: u8 = 0;
    while (i < count) : (i += 1) {
        const at = withAct(first, i);
        const a = actOf(m, at) orelse break;
        actRow(ed, g, x + LABEL_W, y, beforeDrop(w), a, at, spoken);
        if (dropRow(ed, g, x + w, y, "Take this action away", script.Act, list.items, list.n, i)) break;
        y += STEP;
    }
    return y;
}

fn withAct(at: ActAt, i: u8) ActAt {
    return switch (at) {
        .trigger => |t| .{ .trigger = .{ .t = t.t, .a = i } },
        .line => |l| .{ .line = .{ .d = l.d, .l = l.l, .a = i } },
        .choice => |c| .{ .choice = .{ .d = c.d, .l = c.l, .c = c.c, .a = i } },
    };
}

/// A kind the act can be given here: a conversation's lines only say and set; one naming what the map lacks is passed over.
fn actKindOk(m: *const Script, k: script.ActKind, spoken: bool) bool {
    if (spoken and !k.spoken()) return false;
    return refOk(m, script.actRef(k));
}

/// Its slot in range, naming the table its kind reads: coined when the table is empty.
fn fitAct(m: *Script, a: *script.Act, spoken: bool) void {
    while (!actKindOk(m, a.kind, spoken)) a.kind = cycle(script.ActKind, a.kind, 1);
    if (script.actRef(a.kind)) |r| fitRef(m, r, &a.slot) else a.slot = 0;
    a.n = a.kind.span().clamp(a.n);
    if (a.kind == .quest and a.questop == .stage) a.n = stagesOf(m, a.slot, 1).clamp(a.n);
}

/// The map has something for `r` to name; a table always does, as one is coined.
fn refOk(m: *const Script, r: ?script.Ref) bool {
    const ref = r orelse return true;
    return ref == .table or m.refLen(ref) > 0;
}

fn fitRef(m: *Script, r: script.Ref, slot: *u8) void {
    switch (r) {
        .table => |t| fitSlot(m, t, slot),
        .npc, .dialog, .quest => slot.* = @intCast(@min(slot.*, m.refLen(r) - 1)),
    }
}

/// `slot` held to table `t`, its first name coined when the table is empty.
fn fitSlot(m: *Script, t: script.Table, slot: *u8) void {
    if (m.names(t).len == 0) slot.* = m.coin(t) orelse 0 else slot.* = @min(slot.*, @as(u8, @intCast(m.names(t).len - 1)));
}

fn kindW(w: i32) i32 {
    return widgets.share(w, KIND_PARTS, KIND_MIN_W, KIND_MAX_W);
}

/// The kind heading an action's or a condition's row: a new kind starts afresh, fitted to the map by `rule`.
fn kindStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, v: anytype, names: anytype, tip: [:0]const u8, rule: anytype) void {
    const K = @TypeOf(v.kind);
    const by = stepper(ed, g, r, names.get(v.kind), true, tip, false);
    if (by == 0) return;
    var k = cycle(K, v.kind, by);
    while (!rule.ok(k)) k = cycle(K, k, by);
    if (k == v.kind) return;
    v.* = .{ .kind = k };
    rule.fit(v);
    ed.bank();
}

const ActRule = struct {
    m: *Script,
    spoken: bool,

    fn ok(r: ActRule, k: script.ActKind) bool {
        return actKindOk(r.m, k, r.spoken);
    }

    fn fit(r: ActRule, a: *script.Act) void {
        fitAct(r.m, a, r.spoken);
    }
};

const CondRule = struct {
    ed: *editor.Editor,

    fn ok(r: CondRule, k: script.CondKind) bool {
        return condKindOk(&r.ed.map.script, k);
    }

    fn fit(r: CondRule, c: *script.Cond) void {
        fitCond(r.ed, c);
    }
};

const ACT_WORDS = std.EnumArray(script.ActKind, []const u8).init(.{
    .dialog = "open dialog",
    .text = "say in the log",
    .flag = "flag",
    .counter = "counter",
    .timer = "start timer",
    .wait = "wait",
    .preserve = "keep it ready",
    .quest = "quest",
});
const SETOP_WORDS = std.EnumArray(script.Setop, []const u8).init(.{ .off = "clear it", .on = "set it", .flip = "flip it" });
const COUNTOP_WORDS = std.EnumArray(script.Countop, []const u8).init(.{ .set = "set to", .add = "add", .sub = "take" });
const QUESTOP_WORDS = std.EnumArray(script.Questop, []const u8).init(.{ .stage = "to stage", .done = "finish it" });
const STATE_WORDS = std.EnumArray(script.QuestState, []const u8).init(.{ .unstarted = "not begun", .active = "under way", .done = "finished" });

fn actRow(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, a: *script.Act, at: ActAt, spoken: bool) void {
    const kw = kindW(w);
    kindStep(ed, g, widgets.row(x, y, kw), a, &ACT_WORDS, "What it does", ActRule{ .m = &ed.map.script, .spoken = spoken });
    const fx = x + kw + GAP;
    const fw = w - kw - GAP;
    var lay = widgets.Lay{ .x = fx, .y = y };
    switch (a.kind) {
        .preserve => caption(g, fx, y, fw, "not spent: it fires again when it next holds", look.DIM),
        .dialog => dialogStep(ed, g, widgets.row(fx, y, @min(fw, WHICH_W)), &a.slot),
        .text => words(ed, g, widgets.row(fx, y, fw), .{ .note = at }, "(the line the log shows)"),
        .flag => {
            const ws = split(fw, &.{ 3, 2 }, &.{ WHICH_W, OP_W });
            tableStep(ed, g, lay.take(ws[0]), script.actRef(a.kind).?.table, &a.slot);
            wordStep(ed, g, lay.take(ws[1]), script.Setop, &a.setop, &SETOP_WORDS, null);
        },
        .counter => {
            const ws = splitBy(fw, NAME_OP_NUMBER);
            tableStep(ed, g, lay.take(ws[0]), script.actRef(a.kind).?.table, &a.slot);
            wordStep(ed, g, lay.take(ws[1]), script.Countop, &a.countop, &COUNTOP_WORDS, null);
            numberStep(ed, g, lay.take(ws[2]), &a.n, a.kind.span(), "", "By how much");
        },
        .timer => {
            const ws = splitBy(fw, NAME_UNITS);
            tableStep(ed, g, lay.take(ws[0]), script.actRef(a.kind).?.table, &a.slot);
            numberStep(ed, g, lay.take(ws[1]), &a.n, a.kind.span(), " turns", "Turns it runs before it is done");
        },
        .wait => numberStep(ed, g, widgets.row(fx, y, UNIT_W), &a.n, a.kind.span(), " turns", "Spent turns held before the next action"),
        .quest => {
            const ws = splitBy(fw, NAME_OP_NUMBER);
            const before = a.*;
            questStep(ed, g, lay.take(ws[0]), &a.slot);
            wordStep(ed, g, lay.take(ws[1]), script.Questop, &a.questop, &QUESTOP_WORDS, "Begin it or move it to a stage, or finish it; a finished quest stays finished");
            if (a.slot != before.slot or a.questop != before.questop) fitAct(&ed.map.script, a, spoken);
            if (a.questop == .stage) numberStep(ed, g, lay.take(ws[2]), &a.n, stagesOf(&ed.map.script, a.slot, 1), "", "Which stage, from the first");
        },
    }
}

fn questStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, slot: *u8) void {
    const m = &ed.map.script;
    indexStep(ed, g, r, m.quest[slot.*].titled(), slot, m.quest_n, "Which quest; they are kept in the Quests page");
}

/// The stages quest `q` has, from `lo`.
fn stagesOf(m: *const Script, q: u8, lo: i32) script.Span {
    return m.quest[q].reach(lo);
}

fn dialogStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, slot: *u8) void {
    const m = &ed.map.script;
    indexStep(ed, g, r, m.dialog[slot.*].name.text(), slot, m.dialog_n, "Which dialog");
}

/// A name from table `t`, with `+` coining a new one.
fn tableStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, t: script.Table, slot: *u8) void {
    const m = &ed.map.script;
    const all = m.names(t);
    const w: i32 = @intFromFloat(r.width);
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    indexStep(ed, g, widgets.row(x, y, w - widgets.STEP_W - GAP), all[slot.*].text(), slot, all.len, "Which one; names are kept in the Script page");
    if (rightButton(ed, g, x + w, y, widgets.STEP_W, "+", all.len < Script.tableMax(t), "A new one, named for its kind; rename it in the Script page")) {
        if (m.coin(t)) |i| {
            slot.* = i;
            ed.bank();
        }
    }
}

const COND_WORDS = std.EnumArray(script.CondKind, []const u8).init(.{
    .always = "always",
    .never = "never",
    .flag = "flag",
    .counter = "counter",
    .timer = "timer",
    .elapsed = "turns passed",
    .region = "hero in region",
    .near = "hero near NPC",
    .talked = "has heard",
    .deaths = "deaths of",
    .alive = "alive here",
    .quest = "quest is",
    .stage = "quest stage",
});
const CMP_WORDS = std.EnumArray(script.Cmp, []const u8).init(.{ .lt = "under", .le = "at most", .eq = "exactly", .ge = "at least", .gt = "over" });

fn condKindOk(m: *const Script, k: script.CondKind) bool {
    return refOk(m, script.condRef(k));
}

fn fitCond(ed: *editor.Editor, c: *script.Cond) void {
    const m = &ed.map.script;
    while (!condKindOk(m, c.kind)) c.kind = cycle(script.CondKind, c.kind, 1);
    if (script.condRef(c.kind)) |r| fitRef(m, r, &c.slot);
    switch (c.kind) {
        .near => {
            c.n = c.kind.span().clamp(c.n);
            if (c.n == 0) c.n = script.NEAR_DEFAULT;
        },
        .region => {
            c.node = @intCast(ed.node);
            if (ed.selection) |b| {
                c.from = b.lo;
                c.to = b.hi.sub(.{ .x = 1, .y = 1 });
            }
        },
        .always, .never, .flag, .counter, .timer, .elapsed, .talked, .deaths, .alive, .quest, .stage => {},
    }
}

fn condRow(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, c: *script.Cond) void {
    const m = &ed.map.script;
    var buf: [widgets.LINE]u8 = undefined;
    const kw = kindW(w);
    kindStep(ed, g, widgets.row(x, y, kw), c, &COND_WORDS, "What has to hold", CondRule{ .ed = ed });
    const fx = x + kw + GAP;
    const fw = w - kw - GAP;
    var lay = widgets.Lay{ .x = fx, .y = y };
    switch (c.kind) {
        .always, .never => {},
        .flag, .timer => {
            const ws = splitBy(fw, NAME_TOGGLE);
            tableStep(ed, g, lay.take(ws[0]), script.condTable(c.kind).?, &c.slot);
            const words_ = if (c.kind == .flag) [2][:0]const u8{ "is off", "is on" } else [2][:0]const u8{ "is running", "has run out" };
            if (button(ed, g, lay.take(ws[1]), words_[@intFromBool(c.on)], false, true, "Which way it has to be")) {
                c.on = !c.on;
                ed.bank();
            }
        },
        .counter => {
            const ws = splitBy(fw, NAME_CMP_NUMBER);
            tableStep(ed, g, lay.take(ws[0]), script.condTable(c.kind).?, &c.slot);
            cmpStep(ed, g, lay.take(ws[1]), &c.cmp);
            numberStep(ed, g, lay.take(ws[2]), &c.n, c.kind.span(), "", "The number it is held to");
        },
        .elapsed => {
            const ws = split(fw, &.{ 1, 1 }, &.{ OP_W, ELAPSED_W });
            cmpStep(ed, g, lay.take(ws[0]), &c.cmp);
            numberStep(ed, g, lay.take(ws[1]), &c.n, c.kind.span(), " turns", "Spent turns since the run began");
        },
        .region => {
            const ws = split(fw, &.{ 3, 2 }, &.{ REGION_W, BTN_W });
            caption(g, fx, y, ws[0], std.fmt.bufPrint(&buf, "node {d}: {d},{d} to {d},{d}", .{ c.node, c.from.x, c.from.y, c.to.x, c.to.y }) catch "", look.TEXT);
            _ = lay.take(ws[0]);
            if (button(ed, g, lay.take(ws[1]), "From selection", false, ed.selection != null, widgets.keyed("This node and the cells selected on it", comptime editor.Shape.select.caption()))) {
                const before = c.*;
                fitCond(ed, c);
                if (!std.meta.eql(before, c.*)) ed.bank();
            }
        },
        .near => {
            const ws = splitBy(fw, NAME_UNITS);
            indexStep(ed, g, lay.take(ws[0]), m.npc[c.slot].called(), &c.slot, m.npc_n, "Which NPC");
            numberStep(ed, g, lay.take(ws[1]), &c.n, c.kind.span(), " cells", "How near, in steps either way");
        },
        .talked => dialogStep(ed, g, widgets.row(fx, y, @min(fw, WHICH_W)), &c.slot),
        .deaths, .alive => {
            const ws = split(fw, &.{ 4, 3, 3 }, &.{ FOE_W, OP_W, NUMBER_W });
            const by = stepper(ed, g, lay.take(ws[0]), actor.row(c.foe).name, true, "Which foe; a slime counts its halves", false);
            if (by != 0) {
                c.foe = mathx.stepIn(actor.Kind, &actor.FOES, c.foe, by, 0);
                ed.bank();
            }
            cmpStep(ed, g, lay.take(ws[1]), &c.cmp);
            numberStep(ed, g, lay.take(ws[2]), &c.n, c.kind.span(), "", "How many");
        },
        .quest => {
            const ws = splitBy(fw, NAME_TOGGLE);
            questStep(ed, g, lay.take(ws[0]), &c.slot);
            wordStep(ed, g, lay.take(ws[1]), script.QuestState, &c.state, &STATE_WORDS, "Where it has to stand");
        },
        .stage => {
            const ws = splitBy(fw, NAME_CMP_NUMBER);
            const was = c.slot;
            questStep(ed, g, lay.take(ws[0]), &c.slot);
            if (c.slot != was) c.n = stagesOf(m, c.slot, 0).clamp(c.n);
            cmpStep(ed, g, lay.take(ws[1]), &c.cmp);
            numberStep(ed, g, lay.take(ws[2]), &c.n, stagesOf(m, c.slot, 0), "", "Its stage, from the first; 0 before it begins, and the last it reached once finished");
        },
    }
}

fn cmpStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, cmp: *script.Cmp) void {
    wordStep(ed, g, r, script.Cmp, cmp, &CMP_WORDS, "How the two are compared");
}

fn drawScript(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.plot;
    const m = &ed.map.script;
    const f = frameOf(ed, g, .script);
    const lw = f.listW();
    var buf: [widgets.LINE]u8 = undefined;
    const list = listArea(ed, f);
    var y = list.begin(&ed.clip);
    if (listHead(ed, g, f, y, "Triggers", m.trigger_n, script.MAX_TRIGGERS, "A trigger that always holds and does nothing yet")) {
        if (m.addTrigger()) |t| {
            ed.bank();
            s.trigger = t;
            s.detail.top = 0;
        }
    }
    y += STEP;
    for (m.triggers(), 0..) |*t, i| {
        const label = std.fmt.bufPrint(&buf, "{s}{s}", .{ t.name.text(), if (t.parked) "  (parked)" else "" }) catch "";
        if (listRow(ed, g, f, y, label, if (s.trigger) |at| at == i else false, "When it fires and what it does")) s.trigger = @intCast(i);
        y += STEP;
    }
    inline for (comptime std.enums.values(script.Table)) |t| {
        y += GAP;
        const all = m.names(t);
        countHeading(g, f.x, y, lw, comptime menu.capital(@tagName(t)) ++ "s", all.len, Script.tableMax(t));
        if (rightButton(ed, g, f.x + lw - GAP, y, NAME_ADD_W, "+", all.len < Script.tableMax(t), "A new " ++ @tagName(t) ++ ", named for its kind")) {
            if (m.coin(t)) |_| ed.bank();
        }
        y += STEP;
        var i: u8 = 0;
        while (i < m.names(t).len) : (i += 1) {
            words(ed, g, widgets.row(f.x, y, lw - 2 * GAP - DROP_W), .{ .table = .{ .t = t, .i = i } }, "");
            const users = m.tableUsers(t, i);
            if (dropButton(ed, g, f.x + lw - GAP, y, users == 0, if (users == 0) "Remove it" else "Still named by a condition or action")) {
                if (m.undeclare(t, i)) ed.bank();
                break;
            }
            y += STEP;
        }
    }
    const right = rightOf(ed, f, list, y);
    const ti = s.trigger orelse return caption(g, right.x, f.y, right.w, "Pick a trigger: when every condition holds after a turn, its actions run in order", look.DIM);
    detailPane(ed, g, right.x, f.y, right.w, f.bottom, drawTrigger, ti);
}

fn drawTrigger(ed: *editor.Editor, g: *game.Game, ti: u8, x: i32, top: i32, w: i32) i32 {
    const m = &ed.map.script;
    const t = &m.trigger[ti];
    var y = top;
    if (nameRow(ed, g, x, y, w, "Trigger", .{ .trigger = ti }, "Delete trigger", true, "Throw it away")) {
        m.dropTrigger(ti);
        ed.bank();
        ed.plot.trigger = null;
        return y + STEP;
    }
    y += STEP;
    var toggles = widgets.Lay{ .x = x + LABEL_W, .y = y };
    if (button(ed, g, toggles.take(TOGGLE_W), if (t.once) "Fires once" else "Repeats", false, true, "Once, or every turn its conditions hold")) {
        t.once = !t.once;
        ed.bank();
    }
    if (button(ed, g, toggles.take(TOGGLE_W), if (t.parked) "Parked" else "Live", t.parked, true, "A parked trigger stays in the map and never runs")) {
        t.parked = !t.parked;
        ed.bank();
    }
    const priority_x = toggles.x + GAP;
    caption(g, priority_x, y, PRIORITY_LABEL_W, "priority", look.DIM);
    var pri: i32 = t.priority;
    numberStep(ed, g, widgets.row(priority_x + PRIORITY_LABEL_W, y, PRIORITY_W), &pri, script.PRIORITY, "", "Higher runs first when two are ready on the same turn");
    t.priority = @intCast(pri);
    y += STEP + GAP;
    if (countHead(ed, g, x, y, w, "When every one holds", t.cond_n, script.MAX_CONDS, COND_ADD_W, "+ Condition", "Another that has to hold; with none it never fires")) {
        if (mathx.push(script.Cond, &t.cond, &t.cond_n, .{ .kind = .always })) ed.bank();
    }
    y += STEP;
    if (t.cond_n == 0) {
        caption(g, x + LABEL_W, y, w - LABEL_W, "No conditions: it never fires", look.EDIT_WARN);
        y += STEP;
    }
    var c: u8 = 0;
    while (c < t.cond_n) : (c += 1) {
        condRow(ed, g, x + LABEL_W, y, beforeDrop(w), &t.cond[c]);
        if (dropRow(ed, g, x + w, y, "Take this condition away", script.Cond, &t.cond, &t.cond_n, c)) break;
        y += STEP;
    }
    y += GAP;
    heading(g, x, y, w, "Then, in order");
    y += STEP;
    y = actRows(ed, g, x, x, y, w, "do", .{ .trigger = .{ .t = ti, .a = 0 } });
    return y;
}

fn drawQuests(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.plot;
    const m = &ed.map.script;
    const f = frameOf(ed, g, .quests);
    const list = listArea(ed, f);
    var y = list.begin(&ed.clip);
    if (listHead(ed, g, f, y, "Quests", m.quest_n, script.MAX_QUESTS, "A quest of one blank stage")) {
        if (m.addQuest()) |q| {
            ed.bank();
            s.quest = q;
            s.detail.top = 0;
        }
    }
    y += STEP;
    for (m.quests(), 0..) |*q, i| {
        if (listRow(ed, g, f, y, q.titled(), if (s.quest) |at| at == i else false, "Its title and what each stage asks")) s.quest = @intCast(i);
        y += STEP;
    }
    const right = rightOf(ed, f, list, y);
    const qi = s.quest orelse return caption(g, right.x, f.y, right.w, "Pick a quest: the journal lists it once an action brings it to a stage", look.DIM);
    detailPane(ed, g, right.x, f.y, right.w, f.bottom, drawQuest, qi);
}

fn drawQuest(ed: *editor.Editor, g: *game.Game, qi: u8, x: i32, top: i32, w: i32) i32 {
    const m = &ed.map.script;
    const q = &m.quest[qi];
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    const users = m.questUsers(qi);
    if (nameRow(ed, g, x, y, w, "Quest", .{ .quest = qi }, dropLabel(&buf, users, "quest"), users == 0, "Delete it; a quest conditions or actions still name cannot go")) {
        if (m.dropQuest(qi)) {
            ed.bank();
            ed.plot.quest = null;
            return y + STEP;
        }
    }
    y += STEP;
    wordsRow(ed, g, x, y, w, "Title", .{ .title = qi }, "(blank: its name)");
    y += STEP + GAP;
    if (countHead(ed, g, x, y, w, "Stages", q.stage_n, script.MAX_STAGES, CHOICE_ADD_W, "+ Stage", "What the journal asks next")) {
        if (mathx.push(script.Note, &q.stage, &q.stage_n, .{})) ed.bank();
    }
    y += STEP;
    var k: u8 = 0;
    while (k < q.stage_n) : (k += 1) {
        caption(g, x, y, LABEL_W, std.fmt.bufPrint(&buf, "{d}. Asks", .{k + 1}) catch "", look.TEXT);
        words(ed, g, widgets.row(x + LABEL_W, y, beforeDrop(w)), .{ .stage = .{ .q = qi, .k = k } }, "(what the journal asks)");
        if (dropButton(ed, g, x + w, y, q.stage_n > 1, "Take this stage away; whatever named a later stage names the one it became")) {
            m.dropStage(qi, k);
            ed.bank();
            break;
        }
        y += STEP;
    }
    return y;
}

test "an NPC's name gives its dialog a name the map reads back" {
    var buf: [script.NAME_MAX]u8 = undefined;
    try std.testing.expectEqualStrings("old_wenna", stemOf(&buf, "Old Wenna!"));
    try std.testing.expectEqualStrings("", stemOf(&buf, "  "));
    try std.testing.expect(script.token(stemOf(&buf, "The Hunter of the Long Road")));
    var s = Script{};
    _ = s.addDialog("old_wenna").?;
    try std.testing.expectEqualStrings("dialog1", s.dialog[s.addDialog("old_wenna").?].name.text());
}

test "typed words refuse what the map's words refuse" {
    var f = Field{};
    f.limit(script.Name.MAX);
    f.set("");
    try std.testing.expect(!f.insert("\x1eEnter\x1f"));
    try std.testing.expect(!f.insert("a\tb"));
    try std.testing.expect(!f.insert("a" ** (script.NAME_MAX + 1)));
    try std.testing.expect(f.insert("a" ** script.NAME_MAX));
    try std.testing.expect(script.Name.of(f.text()).eql(f.text()));
    std.debug.print("typed words: 3 refusals (control markers, tab, one past the name limit) and a full name accepted\n", .{});
}

test "changing a quest action fits its stage to the new quest's objectives" {
    const trigger = @import("../play/trigger.zig");
    const log = @import("../play/log.zig");
    var m = Script{};
    const first = m.addQuest().?;
    m.quest[first].stage_n = 3;
    const second = m.addQuest().?;
    _ = m.quest[second].stage[0].set("Return to the merchant");
    var a = script.Act{ .kind = .quest, .slot = first, .n = 3 };
    a.slot = second;
    fitAct(&m, &a, false);
    var runtime = trigger.Runtime{};
    var history = log.Log{};
    runtime.apply(&m, &a, &history);
    try std.testing.expectEqual(@as(u8, 1), runtime.quests[second].stage);
    try std.testing.expectEqualStrings("Return to the merchant", m.quest[second].asks(runtime.quests[second].stage));
    a = .{ .kind = .quest, .slot = second, .questop = .done, .n = 3 };
    a.questop = .stage;
    fitAct(&m, &a, true);
    try std.testing.expectEqual(@as(i32, 1), a.n);
    std.debug.print("quest actions: changing quest and resuming stage mode both retain a real objective\n", .{});
}
