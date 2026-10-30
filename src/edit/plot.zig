const std = @import("std");
const rl = @import("raylib");
const input = @import("../core/input.zig");
const grid = @import("../map/grid.zig");
const script = @import("../map/script.zig");
const actor = @import("../play/actor.zig");
const look = @import("../gfx/look.zig");
const raster = @import("../gfx/raster.zig");
const menu = @import("../ui/menu.zig");
const game = @import("../game.zig");
const editor = @import("editor.zig");
const widgets = @import("widgets.zig");
const text_panel = @import("text_panel.zig");
const Desk = input.Desk;
const Script = script.Script;

const PAD = widgets.PAD;
const GAP = widgets.GAP;
const ROW = widgets.ROW_H;
const STEP = widgets.ROW_STEP;
const TEXT = widgets.TEXT;
const DETAIL = widgets.DETAIL;
const LABEL_W: i32 = 130;
const SUB_W: i32 = 100;
const ARROW_W: i32 = 30;
const DROP_W: i32 = 34;
const SAY_ROWS: i32 = 4;
const FIELD_LINE: i32 = TEXT + 8;
const WHEEL_PX: i32 = ROW * 2;

pub const LineAt = struct { d: u8, l: u8 };
pub const ChoiceAt = struct { d: u8, l: u8, c: u8 };
/// An action in place: a trigger's, a line's or a choice's.
pub const ActAt = union(enum) {
    trigger: struct { t: u8, a: u8 },
    line: struct { d: u8, l: u8, a: u8 },
    choice: struct { d: u8, l: u8, c: u8, a: u8 },
};
/// The one piece of words being typed into, written to the map as it is typed.
pub const Focus = union(enum) {
    folk: u8,
    dialog: u8,
    line: LineAt,
    who: LineAt,
    say: LineAt,
    ask: ChoiceAt,
    trigger: u8,
    table: struct { t: script.Table, i: u8 },
    note: ActAt,
};
pub const Pick = union(enum) { none, folk: u8, dialog: u8 };

pub const State = struct {
    pick: Pick = .none,
    line: u8 = 0,
    trigger: ?u8 = null,
    focus: ?Focus = null,
    field: text_panel.Field = .{},
    /// A field took this frame's click.
    claimed: bool = false,
    list: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    list_top: i32 = 0,
    list_most: i32 = 0,
    detail: rl.Rectangle = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    detail_top: i32 = 0,
    detail_most: i32 = 0,
};

pub fn openFolk(ed: *editor.Editor, i: u8) void {
    ed.plot.pick = .{ .folk = i };
    open(ed, .dialogs);
}

pub fn open(ed: *editor.Editor, m: editor.Modal) void {
    ed.plot.focus = null;
    ed.plot.detail_top = 0;
    if (m == .dialogs and ed.plot.pick == .none and ed.map.script.dialog_n > 0) ed.plot.pick = .{ .dialog = 0 };
    if (m == .script and ed.plot.trigger == null and ed.map.script.trigger_n > 0) ed.plot.trigger = 0;
    ed.ask(m);
}

pub fn keys(ed: *editor.Editor) void {
    const d = &ed.desk;
    const s = &ed.plot;
    if (d.clicked()) ed.gesture();
    if (d.save) _ = ed.save();
    if (d.undo or d.redo) {
        s.focus = null;
        if (d.undo) ed.undo() else ed.redo();
        return;
    }
    if (d.wheel != 0) {
        const by: i32 = if (d.wheel > 0) -WHEEL_PX else WHEEL_PX;
        if (raster.holds(s.list, d.mouse)) s.list_top = std.math.clamp(s.list_top + by, 0, s.list_most);
        if (raster.holds(s.detail, d.mouse)) s.detail_top = std.math.clamp(s.detail_top + by, 0, s.detail_most);
    }
    if (s.focus) |f| {
        if (d.back or d.enter or !holds(&ed.map.script, f)) {
            s.focus = null;
            return;
        }
        typed(ed, f);
        return;
    }
    if (d.back or d.erase_hit) close(ed);
}

fn close(ed: *editor.Editor) void {
    ed.plot.focus = null;
    ed.modal = .none;
}

fn typed(ed: *editor.Editor, f: Focus) void {
    const s = &ed.plot;
    const m = &ed.map.script;
    var nav = ed.desk;
    nav.undo = false;
    nav.redo = false;
    if (!s.field.feed(&nav, false)) return ed.say("Plain letters on one line", .{});
    const now = s.field.text();
    const was = textOf(m, f);
    if (std.mem.eql(u8, now, was)) return;
    if (put(m, f, now)) return ed.bank();
    s.field.set(was);
    ed.say("{s}", .{if (named(f)) "A name is letters, digits, _ or -, not taken, " ++ std.fmt.comptimePrint("{d}", .{script.NAME_MAX}) ++ " at most" else "That is as long as it can be"});
}

fn named(f: Focus) bool {
    return switch (f) {
        .dialog, .line, .trigger, .table => true,
        .folk, .who, .say, .ask, .note => false,
    };
}

fn holds(m: *const Script, f: Focus) bool {
    return switch (f) {
        .folk => |i| i < m.folk_n,
        .dialog => |i| i < m.dialog_n,
        .line, .who, .say => |at| at.d < m.dialog_n and at.l < m.dialog[at.d].line_n,
        .ask => |at| at.d < m.dialog_n and at.l < m.dialog[at.d].line_n and at.c < m.dialog[at.d].line[at.l].choice_n,
        .trigger => |i| i < m.trigger_n,
        .table => |at| at.i < m.names(at.t).len,
        .note => |at| actOf(@constCast(m), at) != null,
    };
}

fn textOf(m: *Script, f: Focus) []const u8 {
    return switch (f) {
        .folk => |i| m.folk[i].name.text(),
        .dialog => |i| m.dialog[i].name.text(),
        .line => |at| m.dialog[at.d].line[at.l].name.text(),
        .who => |at| m.dialog[at.d].line[at.l].who.text(),
        .say => |at| m.dialog[at.d].line[at.l].say.text(),
        .ask => |at| m.dialog[at.d].line[at.l].choice[at.c].ask.text(),
        .trigger => |i| m.trigger[i].name.text(),
        .table => |at| m.names(at.t)[at.i].text(),
        .note => |at| actOf(m, at).?.note.text(),
    };
}

fn put(m: *Script, f: Focus, s: []const u8) bool {
    return switch (f) {
        .folk => |i| m.folk[i].name.set(s),
        .dialog => |i| script.token(s) and (m.findDialog(s) orelse i) == i and m.dialog[i].name.set(s),
        .line => |at| script.token(s) and (m.dialog[at.d].findLine(s) orelse at.l) == at.l and m.dialog[at.d].line[at.l].name.set(s),
        .who => |at| m.dialog[at.d].line[at.l].who.set(s),
        .say => |at| m.dialog[at.d].line[at.l].say.set(s),
        .ask => |at| m.dialog[at.d].line[at.l].choice[at.c].ask.set(s),
        .trigger => |i| script.token(s) and (m.findTrigger(s) orelse i) == i and m.trigger[i].name.set(s),
        .table => |at| m.rename(at.t, at.i, s),
        .note => |at| actOf(m, at).?.note.set(s),
    };
}

fn actOf(m: *Script, at: ActAt) ?*script.Act {
    switch (at) {
        .trigger => |t| {
            if (t.t >= m.trigger_n or t.a >= m.trigger[t.t].act_n) return null;
            return &m.trigger[t.t].act[t.a];
        },
        .line => |l| {
            if (l.d >= m.dialog_n or l.l >= m.dialog[l.d].line_n or l.a >= m.dialog[l.d].line[l.l].act_n) return null;
            return &m.dialog[l.d].line[l.l].act[l.a];
        },
        .choice => |c| {
            if (c.d >= m.dialog_n or c.l >= m.dialog[c.d].line_n) return null;
            const ln = &m.dialog[c.d].line[c.l];
            if (c.c >= ln.choice_n or c.a >= ln.choice[c.c].act_n) return null;
            return &ln.choice[c.c].act[c.a];
        },
    }
}

/// One frame of either page; a click no field took leaves the words.
pub fn draw(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.plot;
    s.claimed = false;
    const clicked = ed.desk.paint_hit;
    if (s.focus) |f| if (!holds(&ed.map.script, f)) {
        s.focus = null;
    };
    switch (ed.modal) {
        .script => drawScript(ed, g),
        else => drawDialogs(ed, g),
    }
    if (clicked and !s.claimed and !ed.fresh) s.focus = null;
}

const Frame = struct {
    x: i32,
    y: i32,
    w: i32,
    bottom: i32,

    fn listW(f: Frame) i32 {
        return std.math.clamp(@divTrunc(f.w, 5), 240, 330);
    }
};

/// Widths across `w` in proportion to `shares`, each held to its cap, a gap between each.
fn split(w: i32, comptime shares: []const i32, comptime caps: []const i32) [shares.len]i32 {
    var total: i32 = 0;
    inline for (shares) |s| total += s;
    const room = w - GAP * @as(i32, @intCast(shares.len - 1));
    var out: [shares.len]i32 = undefined;
    inline for (shares, caps, 0..) |s, cap, i| out[i] = @max(2 * ARROW_W + 24, @min(cap, @divTrunc(room * s, total)));
    return out;
}

/// Boxes laid left to right along one row.
const Lay = struct {
    x: i32,
    y: i32,

    fn take(self: *Lay, w: i32) rl.Rectangle {
        defer self.x += w + GAP;
        return raster.rect(self.x, self.y, w, ROW);
    }
};

/// The scroll area's clip, after something drew under its own.
fn reclip(ed: *const editor.Editor) void {
    if (ed.clip) |c| widgets.scissor(c) else rl.endScissorMode();
}

fn frameOf(ed: *editor.Editor, g: *game.Game, title: [:0]const u8) Frame {
    const height = @min(1080, g.screen.y - 2 * PAD);
    const f = widgets.modalFrame(&g.face, g.screen, 1800, height, title, false);
    const bottom = f.top - PAD + height - PAD;
    if (button(ed, g, raster.rect(f.buttonX(), bottom - ROW, widgets.MODAL_BTN_W, ROW), widgets.keyed("Close", Desk.BACK_CAPTION), false, true, "Every change is in the map already; it saves with it")) close(ed);
    return .{ .x = f.x + PAD, .y = f.y, .w = f.w - 2 * PAD, .bottom = bottom - ROW - GAP };
}

fn button(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, label: [:0]const u8, on: bool, live: bool, tip: ?[:0]const u8) bool {
    return widgets.buttonOn(ed.controls(), &g.face, r, label, on, live, true, tip);
}

fn caption(g: *game.Game, x: i32, y: i32, w: i32, s: []const u8, col: rl.Color) void {
    widgets.drawFit(&g.face, s, DETAIL, w, false, x, y + @divTrunc(ROW - DETAIL, 2), col);
}

fn heading(g: *game.Game, x: i32, y: i32, w: i32, s: []const u8) void {
    widgets.drawFit(&g.face, s, TEXT, w, false, x, y + @divTrunc(ROW - TEXT, 2), look.UI_GOLD);
}

/// `<` and `>` round `value`; -1 or 1 as one is pressed, 0 otherwise.
fn stepper(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, value: []const u8, live: bool, tip: ?[:0]const u8) i32 {
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const w: i32 = @intFromFloat(r.width);
    var by: i32 = 0;
    if (button(ed, g, raster.rect(x, y, ARROW_W, ROW), "<", false, live, tip)) by = -1;
    if (button(ed, g, raster.rect(x + w - ARROW_W, y, ARROW_W, ROW), ">", false, live, tip)) by = 1;
    rl.drawRectangle(x + ARROW_W, y, w - 2 * ARROW_W, ROW, look.fade(look.EDIT_ROW_ON, 0.5));
    var fit_buf: [widgets.LINE]u8 = undefined;
    const shown = widgets.textFace(&g.face).fit(&fit_buf, value, DETAIL, w - 2 * ARROW_W - 2 * GAP, false);
    widgets.textFace(&g.face).drawMid(shown, x + @divTrunc(w, 2), y + @divTrunc(ROW - DETAIL, 2), DETAIL, look.TEXT);
    return by;
}

fn cycle(comptime T: type, v: T, by: i32) T {
    const all = std.enums.values(T);
    const at = std.mem.indexOfScalar(T, all, v) orelse 0;
    return all[@intCast(@mod(@as(i32, @intCast(at)) + by, @as(i32, @intCast(all.len))))];
}

fn numberStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, v: *i32, lo: i32, hi: i32, unit: []const u8, tip: [:0]const u8) void {
    var buf: [32]u8 = undefined;
    const by = stepper(ed, g, r, std.fmt.bufPrint(&buf, "{d}{s}", .{ v.*, unit }) catch "", true, tip);
    if (by == 0) return;
    const next = std.math.clamp(v.* + by * if (ed.desk.shift) editor.SHIFT_STEP else 1, lo, hi);
    if (next == v.*) return;
    v.* = next;
    ed.bank();
}

/// A box of words that becomes the field when clicked; `rows` tall.
fn words(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, f: Focus, blank: []const u8) void {
    const s = &ed.plot;
    const m = &ed.map.script;
    const on = if (s.focus) |now| std.meta.eql(now, f) else false;
    if (on) {
        if (text_panel.drawField(ed, g, &s.field, r, true, true) or ed.mouseIn(r)) s.claimed = true;
        reclip(ed);
        return;
    }
    rl.drawRectangleRec(r, look.EDIT_PANEL);
    rl.drawRectangleLinesEx(r, 1, look.EDGE);
    const h = widgets.hot(ed.controls(), r, true, true, "Click to type; it is written into the map as you type");
    if (h.hot) rl.drawRectangleLinesEx(r, 1, look.EDIT_HOVER);
    const now = textOf(m, f);
    const x: i32 = @as(i32, @intFromFloat(r.x)) + GAP;
    const y: i32 = @as(i32, @intFromFloat(r.y)) + GAP;
    const w: i32 = @as(i32, @intFromFloat(r.width)) - 2 * GAP;
    if (now.len == 0) {
        widgets.drawFit(&g.face, blank, TEXT, w, false, x, y, look.DIM);
    } else if (r.height > @as(f32, @floatFromInt(FIELD_LINE + 2 * GAP))) {
        widgets.scissor(if (ed.clip) |c| rl.getCollisionRec(c, r) else r);
        _ = g.face.paragraph(now, x, y, w, TEXT, look.TEXT);
        reclip(ed);
    } else widgets.drawFit(&g.face, now, TEXT, w, false, x, y, look.TEXT);
    if (h.hit) {
        s.focus = f;
        s.field.set(now);
        s.claimed = true;
    }
}

const Scroll = struct {
    box: rl.Rectangle,
    top: *i32,
    most: *i32,

    fn begin(ed: *editor.Editor, box: rl.Rectangle, top: *i32, most: *i32) Scroll {
        ed.clip = box;
        widgets.scissor(box);
        top.* = std.math.clamp(top.*, 0, most.*);
        return .{ .box = box, .top = top, .most = most };
    }

    fn y0(self: Scroll) i32 {
        return @as(i32, @intFromFloat(self.box.y)) - self.top.*;
    }

    fn end(self: Scroll, ed: *editor.Editor, bottom: i32) void {
        rl.endScissorMode();
        ed.clip = null;
        const shown: i32 = @intFromFloat(self.box.height);
        self.most.* = @max(0, bottom + self.top.* - @as(i32, @intFromFloat(self.box.y)) - shown);
        if (self.most.* > 0) widgets.scrollbar(raster.rect(@as(i32, @intFromFloat(self.box.x + self.box.width)) - 3, @intFromFloat(self.box.y), 3, shown), @intCast(self.top.*), @intCast(shown), @intCast(shown + self.most.*));
    }
};

fn drawDialogs(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.plot;
    const m = &ed.map.script;
    switch (s.pick) {
        .folk => |i| if (i >= m.folk_n) {
            s.pick = .none;
        },
        .dialog => |i| if (i >= m.dialog_n) {
            s.pick = .none;
        },
        .none => {},
    }
    const f = frameOf(ed, g, "Dialog");
    const lw = f.listW();
    var buf: [widgets.LINE]u8 = undefined;
    s.list = raster.rect(f.x, f.y, lw, f.bottom - f.y);
    const list = Scroll.begin(ed, s.list, &s.list_top, &s.list_most);
    var y = list.y0();
    heading(g, f.x, y, lw, std.fmt.bufPrint(&buf, "Folk {d}/{d}", .{ m.folk_n, script.MAX_FOLK }) catch "");
    y += STEP;
    if (m.folk_n == 0) {
        caption(g, f.x, y, lw, "Place folk with their tool on a painted node", look.DIM);
        y += STEP;
    }
    for (m.folks(), 0..) |*fk, i| {
        const line = std.fmt.bufPrintZ(&buf, "{s}  (node {d})", .{ fk.called(), fk.node }) catch "";
        if (button(ed, g, widgets.row(f.x, y, lw - GAP), line, s.pick == .folk and s.pick.folk == i, true, "What this folk is called and which dialog it opens")) {
            s.pick = .{ .folk = @intCast(i) };
            s.detail_top = 0;
        }
        y += STEP;
    }
    y += GAP;
    heading(g, f.x, y, lw, std.fmt.bufPrint(&buf, "Dialogs {d}/{d}", .{ m.dialog_n, script.MAX_DIALOGS }) catch "");
    if (button(ed, g, raster.rect(f.x + lw - GAP - 90, y, 90, ROW), "+ New", false, m.dialog_n < script.MAX_DIALOGS, "A new dialog of one empty line")) {
        if (m.addDialog("")) |d| {
            ed.bank();
            s.pick = .{ .dialog = d };
            s.line = 0;
        }
    }
    y += STEP;
    for (m.dialogs(), 0..) |*dl, i| {
        if (button(ed, g, widgets.row(f.x, y, lw - GAP), std.fmt.bufPrintZ(&buf, "{s}", .{dl.name.text()}) catch "", s.pick == .dialog and s.pick.dialog == i, true, "Its lines, what they say and where each choice goes")) {
            s.pick = .{ .dialog = @intCast(i) };
            s.line = 0;
            s.detail_top = 0;
        }
        y += STEP;
    }
    list.end(ed, y);
    const rx = f.x + lw + PAD;
    const rw = f.x + f.w - rx;
    rl.drawRectangle(rx - @divTrunc(PAD, 2), f.y, 1, f.bottom - f.y, look.EDGE);
    switch (s.pick) {
        .none => caption(g, rx, f.y, rw, "Pick a folk or a dialog", look.DIM),
        .folk => |i| drawFolk(ed, g, i, rx, f.y, rw),
        .dialog => |i| drawDialog(ed, g, i, rx, f.y, rw, f.bottom),
    }
}

fn drawFolk(ed: *editor.Editor, g: *game.Game, i: u8, x: i32, top: i32, w: i32) void {
    const m = &ed.map.script;
    const fk = &m.folk[i];
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    heading(g, x, y, w, std.fmt.bufPrint(&buf, "Folk on node {d} at {d},{d}", .{ fk.node, fk.at.x, fk.at.y }) catch "");
    y += STEP;
    caption(g, x, y, LABEL_W, "Called", look.TEXT);
    words(ed, g, widgets.row(x + LABEL_W, y, w - LABEL_W), .{ .folk = i }, script.STRANGER);
    y += STEP;
    caption(g, x, y, LABEL_W, "Talks with", look.TEXT);
    const talk = if (fk.dialog) |d| m.dialog[d].name.text() else "nothing to say";
    const by = stepper(ed, g, raster.rect(x + LABEL_W, y, 320, ROW), talk, m.dialog_n > 0, "Which dialog speaking to it opens");
    if (by != 0) {
        const n: i32 = @as(i32, m.dialog_n) + 1;
        const at: i32 = if (fk.dialog) |d| @as(i32, d) + 1 else 0;
        const next = @mod(at + by, n);
        fk.dialog = if (next == 0) null else @intCast(next - 1);
        ed.bank();
    }
    if (button(ed, g, raster.rect(x + LABEL_W + 320 + GAP, y, 200, ROW), "New dialog for it", false, m.dialog_n < script.MAX_DIALOGS, "A dialog of one line, named for it, that it opens")) {
        var nb: [script.NAME_MAX]u8 = undefined;
        if (m.addDialog(stemOf(&nb, fk.called()))) |d| {
            fk.dialog = d;
            ed.bank();
        }
    }
    y += STEP;
    if (fk.dialog) |d| {
        if (button(ed, g, raster.rect(x + LABEL_W, y, 320, ROW), "Edit its dialog", false, true, null)) {
            ed.plot.pick = .{ .dialog = d };
            ed.plot.line = 0;
        }
        y += STEP;
    }
    y += GAP;
    if (button(ed, g, raster.rect(x, y, 200, ROW), "Show on the map", false, true, "Close and look at it")) {
        ed.goTo(fk.node);
        ed.recentre = false;
        ed.lookAt(editor.Editor.canvas(g), fk.at);
        ed.flash = fk.at;
        ed.flash_t = 1.2;
        close(ed);
        return;
    }
    if (button(ed, g, raster.rect(x + 200 + GAP, y, 200, ROW), "Remove it", false, true, "Take this folk off the map; any trigger that waited on its nearness never fires")) {
        m.dropFolk(i);
        ed.bank();
        ed.plot.pick = .none;
    }
}

/// A dialog name from a folk's: its first word, lowered, where it reads back.
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
    const lines_w = std.math.clamp(@divTrunc(w, 4), 200, 300);
    var y = top;
    caption(g, x, y, LABEL_W, "Dialog", look.TEXT);
    const users = m.dialogUsers(di);
    words(ed, g, widgets.row(x + LABEL_W, y, w - LABEL_W - 220), .{ .dialog = di }, "");
    if (button(ed, g, raster.rect(x + w - 210, y, 210, ROW), if (users > 0) std.fmt.bufPrintZ(&buf, "Used {d} times", .{users}) catch "" else "Delete dialog", false, users == 0, "Delete it; a dialog folk or triggers still name cannot go")) {
        if (m.dropDialog(di)) {
            ed.bank();
            s.pick = .none;
            return;
        }
    }
    y += STEP + GAP;
    const lx = x;
    heading(g, lx, y, lines_w, std.fmt.bufPrint(&buf, "Lines {d}/{d}", .{ d.line_n, script.MAX_LINES }) catch "");
    y += STEP;
    var line_buf: [script.NAME_MAX + script.SAY_MAX + 5]u8 = undefined;
    for (d.lines(), 0..) |*ln, i| {
        const first = if (ln.say.n > 0) ln.say.text() else "(says nothing)";
        const label = std.fmt.bufPrintZ(&line_buf, "{s}{s}: {s}", .{ if (i == 0) "> " else "", ln.name.text(), first }) catch "";
        if (button(ed, g, widgets.row(lx, y, lines_w - GAP), label, s.line == i, true, if (i == 0) "Where it opens" else null)) {
            s.line = @intCast(i);
            s.detail_top = 0;
        }
        y += STEP;
    }
    const third = @divTrunc(lines_w - 3 * GAP, 3);
    if (button(ed, g, raster.rect(lx, y, third, ROW), "+ Line", false, d.line_n < script.MAX_LINES, "Another line, reached by a choice or a then")) {
        if (d.addLine()) |l| {
            ed.bank();
            s.line = l;
        }
    }
    if (button(ed, g, raster.rect(lx + third + GAP, y, third, ROW), "Up", false, s.line > 0, "Earlier in the list; the first is where it opens")) {
        d.swapLines(s.line, s.line - 1);
        s.line -= 1;
        ed.bank();
    }
    if (button(ed, g, raster.rect(lx + 2 * (third + GAP), y, third, ROW), "Delete", false, d.line_n > 1, "Delete this line; every way into it ends the dialog instead")) {
        d.dropLine(s.line);
        s.line = @min(s.line, d.line_n - 1);
        ed.bank();
    }
    const dx = x + lines_w + PAD;
    const dw = x + w - dx;
    s.detail = raster.rect(dx, top + STEP + GAP, dw, bottom - top - STEP - GAP);
    rl.drawRectangle(dx - @divTrunc(PAD, 2), top + STEP + GAP, 1, bottom - top - STEP - GAP, look.EDGE);
    const area = Scroll.begin(ed, s.detail, &s.detail_top, &s.detail_most);
    const end = drawLine(ed, g, di, s.line, dx, area.y0(), dw - PAD);
    area.end(ed, end);
}

fn drawLine(ed: *editor.Editor, g: *game.Game, di: u8, li: u8, x: i32, top: i32, w: i32) i32 {
    const m = &ed.map.script;
    const d = &m.dialog[di];
    const ln = &d.line[li];
    const at = LineAt{ .d = di, .l = li };
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    caption(g, x, y, LABEL_W, "Line", look.TEXT);
    words(ed, g, widgets.row(x + LABEL_W, y, w - LABEL_W), .{ .line = at }, "");
    y += STEP;
    caption(g, x, y, LABEL_W, "Speaker", look.TEXT);
    words(ed, g, widgets.row(x + LABEL_W, y, w - LABEL_W), .{ .who = at }, "(blank: whoever is spoken to)");
    y += STEP;
    caption(g, x, y, LABEL_W, std.fmt.bufPrint(&buf, "Says {d}/{d}", .{ ln.say.n, script.SAY_MAX }) catch "", look.TEXT);
    const say_h = SAY_ROWS * FIELD_LINE + 2 * GAP;
    words(ed, g, raster.rect(x + LABEL_W, y, w - LABEL_W, say_h), .{ .say = at }, "(says nothing)");
    y += say_h + GAP;
    y = actRows(ed, g, x, x, y, w, "When shown", ln.act_n, script.LINE_ACTS, .{ .line = .{ .d = di, .l = li, .a = 0 } });
    y += GAP;
    heading(g, x, y, w, std.fmt.bufPrint(&buf, "Choices {d}/{d}", .{ ln.choice_n, script.MAX_CHOICES }) catch "");
    if (button(ed, g, raster.rect(x + w - 120, y, 120, ROW), "+ Choice", false, ln.choice_n < script.MAX_CHOICES, "Something the hero may answer")) {
        ln.choice[ln.choice_n] = .{};
        ln.choice_n += 1;
        ed.bank();
    }
    y += STEP;
    var c: u8 = 0;
    while (c < ln.choice_n) : (c += 1) {
        const ch = &ln.choice[c];
        const cat = ChoiceAt{ .d = di, .l = li, .c = c };
        caption(g, x, y, LABEL_W, std.fmt.bufPrint(&buf, "{d}. Answer", .{c + 1}) catch "", look.TEXT);
        words(ed, g, widgets.row(x + LABEL_W, y, w - LABEL_W - DROP_W - GAP), .{ .ask = cat }, "(what the hero says)");
        if (button(ed, g, raster.rect(x + w - DROP_W, y, DROP_W, ROW), "x", false, true, "Take this choice away")) {
            script.cut(script.Choice, &ln.choice, &ln.choice_n, c);
            ed.bank();
            break;
        }
        y += STEP;
        caption(g, x + LABEL_W - SUB_W, y, SUB_W, "goes to", look.DIM);
        targetStep(ed, g, raster.rect(x + LABEL_W, y, 300, ROW), d, &ch.next);
        y += STEP;
        caption(g, x + LABEL_W - SUB_W, y, SUB_W, "shown if", look.DIM);
        if (ch.gate) |*gate| {
            condRow(ed, g, x + LABEL_W, y, w - LABEL_W - DROP_W - GAP, gate);
            if (button(ed, g, raster.rect(x + w - DROP_W, y, DROP_W, ROW), "x", false, true, "Always shown")) {
                ch.gate = null;
                ed.bank();
            }
        } else if (button(ed, g, raster.rect(x + LABEL_W, y, 200, ROW), "+ Condition", false, true, "Hidden, not greyed, while it does not hold")) {
            ch.gate = .{ .kind = .always };
            ed.bank();
        }
        y += STEP;
        y = actRows(ed, g, x, x + LABEL_W - SUB_W, y, w, "does", ch.act_n, script.CHOICE_ACTS, .{ .choice = .{ .d = di, .l = li, .c = c, .a = 0 } });
        y += GAP;
    }
    caption(g, x, y, LABEL_W, if (ln.choice_n == 0) "Then" else "Then (unused)", if (ln.choice_n == 0) look.TEXT else look.DIM);
    targetStep(ed, g, raster.rect(x + LABEL_W, y, 300, ROW), d, &ln.then);
    caption(g, x + LABEL_W + 300 + GAP, y, w - LABEL_W - 300, "where a line with no choices goes on", look.DIM);
    y += STEP;
    return y;
}

fn targetStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, d: *const script.Dialog, next: *?u8) void {
    const label = if (next.*) |n| d.line[n].name.text() else "end";
    const by = stepper(ed, g, r, label, true, "Another line of this dialog, or the end of it");
    if (by == 0) return;
    const n: i32 = @as(i32, d.line_n) + 1;
    const at: i32 = if (next.*) |v| @as(i32, v) + 1 else 0;
    const to = @mod(at + by, n);
    next.* = if (to == 0) null else @intCast(to - 1);
    ed.bank();
}

/// The actions at `first` and those after it in the same list, with a header that adds one.
fn actRows(ed: *editor.Editor, g: *game.Game, x: i32, title_x: i32, top: i32, w: i32, title: []const u8, count: u8, most: usize, first: ActAt) i32 {
    const m = &ed.map.script;
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    caption(g, title_x, y, x + LABEL_W - GAP - title_x, title, look.DIM);
    const spoken = first != .trigger;
    if (count < most and button(ed, g, raster.rect(x + LABEL_W, y, 200, ROW), "+ Action", false, true, if (spoken) "Done as the line shows or the choice is taken" else "Done in order once every condition holds")) {
        if (listOf(m, first)) |list| {
            list.items[list.n.*] = .{ .kind = if (spoken) .flag else .text };
            fitAct(m, &list.items[list.n.*], spoken);
            list.n.* += 1;
            ed.bank();
        }
    } else if (count == most) caption(g, x + LABEL_W, y, w - LABEL_W, std.fmt.bufPrint(&buf, "{d} is the most", .{most}) catch "", look.DIM);
    y += STEP;
    var i: u8 = 0;
    while (i < count) : (i += 1) {
        const at = withAct(first, i);
        const a = actOf(m, at) orelse break;
        actRow(ed, g, x + LABEL_W, y, w - LABEL_W - DROP_W - GAP, a, at, spoken);
        if (button(ed, g, raster.rect(x + w - DROP_W, y, DROP_W, ROW), "x", false, true, "Take this action away")) {
            const list = listOf(m, first).?;
            script.cut(script.Act, list.items, list.n, i);
            ed.bank();
            break;
        }
        y += STEP;
    }
    return y;
}

const ActList = struct { items: []script.Act, n: *u8 };

fn listOf(m: *Script, at: ActAt) ?ActList {
    return switch (at) {
        .trigger => |t| if (t.t < m.trigger_n) .{ .items = &m.trigger[t.t].act, .n = &m.trigger[t.t].act_n } else null,
        .line => |l| if (l.d < m.dialog_n and l.l < m.dialog[l.d].line_n) .{ .items = &m.dialog[l.d].line[l.l].act, .n = &m.dialog[l.d].line[l.l].act_n } else null,
        .choice => |c| blk: {
            if (c.d >= m.dialog_n or c.l >= m.dialog[c.d].line_n or c.c >= m.dialog[c.d].line[c.l].choice_n) break :blk null;
            const ch = &m.dialog[c.d].line[c.l].choice[c.c];
            break :blk .{ .items = &ch.act, .n = &ch.act_n };
        },
    };
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
    return k != .dialog or m.dialog_n > 0;
}

/// Its slot in range, naming the table its kind reads: coined when the table is empty.
fn fitAct(m: *Script, a: *script.Act, spoken: bool) void {
    while (!actKindOk(m, a.kind, spoken)) a.kind = cycle(script.ActKind, a.kind, 1);
    if (script.actTable(a.kind)) |t| {
        if (m.names(t).len == 0) a.slot = m.coin(t) orelse 0 else a.slot = @min(a.slot, @as(u8, @intCast(m.names(t).len - 1)));
    } else if (a.kind == .dialog) a.slot = @min(a.slot, m.dialog_n - 1) else a.slot = 0;
    if ((a.kind == .timer or a.kind == .wait) and a.n < 0) a.n = 0;
}

const ACT_WORDS = std.EnumArray(script.ActKind, []const u8).init(.{
    .dialog = "open dialog",
    .text = "say in the log",
    .flag = "flag",
    .counter = "counter",
    .timer = "start timer",
    .wait = "wait",
    .preserve = "keep it ready",
});
const SETOP_WORDS = std.EnumArray(script.Setop, []const u8).init(.{ .off = "clear it", .on = "set it", .flip = "flip it" });
const COUNTOP_WORDS = std.EnumArray(script.Countop, []const u8).init(.{ .set = "set to", .add = "add", .sub = "take" });

fn actRow(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, a: *script.Act, at: ActAt, spoken: bool) void {
    const m = &ed.map.script;
    const kw = std.math.clamp(@divTrunc(w, 3), 150, 200);
    const kind_by = stepper(ed, g, raster.rect(x, y, kw, ROW), ACT_WORDS.get(a.kind), true, "What it does");
    if (kind_by != 0) {
        var k = cycle(script.ActKind, a.kind, kind_by);
        while (!actKindOk(m, k, spoken)) k = cycle(script.ActKind, k, kind_by);
        if (k != a.kind) {
            a.* = .{ .kind = k };
            fitAct(m, a, spoken);
            ed.bank();
        }
    }
    const fx = x + kw + GAP;
    const fw = w - kw - GAP;
    var lay = Lay{ .x = fx, .y = y };
    switch (a.kind) {
        .preserve => caption(g, fx, y, fw, "not spent: it fires again when it next holds", look.DIM),
        .dialog => dialogStep(ed, g, raster.rect(fx, y, @min(fw, 260), ROW), &a.slot),
        .text => words(ed, g, widgets.row(fx, y, fw), .{ .note = at }, "(the line the log shows)"),
        .flag => {
            const ws = split(fw, &.{ 3, 2 }, &.{ 260, 150 });
            tableStep(ed, g, lay.take(ws[0]), .flag, &a.slot);
            const by = stepper(ed, g, lay.take(ws[1]), SETOP_WORDS.get(a.setop), true, null);
            if (by != 0) {
                a.setop = cycle(script.Setop, a.setop, by);
                ed.bank();
            }
        },
        .counter => {
            const ws = split(fw, &.{ 4, 3, 3 }, &.{ 260, 130, 150 });
            tableStep(ed, g, lay.take(ws[0]), .counter, &a.slot);
            const by = stepper(ed, g, lay.take(ws[1]), COUNTOP_WORDS.get(a.countop), true, null);
            if (by != 0) {
                a.countop = cycle(script.Countop, a.countop, by);
                ed.bank();
            }
            numberStep(ed, g, lay.take(ws[2]), &a.n, -script.NUMBER_MAX, script.NUMBER_MAX, "", "By how much");
        },
        .timer => {
            const ws = split(fw, &.{ 3, 2 }, &.{ 260, 170 });
            tableStep(ed, g, lay.take(ws[0]), .timer, &a.slot);
            numberStep(ed, g, lay.take(ws[1]), &a.n, 0, script.NUMBER_MAX, " turns", "Turns it runs before it is done");
        },
        .wait => numberStep(ed, g, raster.rect(fx, y, 170, ROW), &a.n, 0, script.NUMBER_MAX, " turns", "Spent turns held before the next action"),
    }
}

fn dialogStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, slot: *u8) void {
    const m = &ed.map.script;
    const by = stepper(ed, g, r, m.dialog[slot.*].name.text(), m.dialog_n > 1, "Which dialog");
    if (by == 0) return;
    slot.* = @intCast(@mod(@as(i32, slot.*) + by, @as(i32, m.dialog_n)));
    ed.bank();
}

/// A name from table `t`, with `+` coining a new one.
fn tableStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, t: script.Table, slot: *u8) void {
    const m = &ed.map.script;
    const all = m.names(t);
    const w: i32 = @intFromFloat(r.width);
    const x: i32 = @intFromFloat(r.x);
    const y: i32 = @intFromFloat(r.y);
    const by = stepper(ed, g, raster.rect(x, y, w - ARROW_W - GAP, ROW), all[slot.*].text(), all.len > 1, "Which one; names are kept in the Script page");
    if (by != 0) {
        slot.* = @intCast(@mod(@as(i32, slot.*) + by, @as(i32, @intCast(all.len))));
        ed.bank();
    }
    if (button(ed, g, raster.rect(x + w - ARROW_W, y, ARROW_W, ROW), "+", false, all.len < tableMost(t), "A new one, named for its kind; rename it in the Script page")) {
        if (m.coin(t)) |i| {
            slot.* = i;
            ed.bank();
        }
    }
}

fn tableMost(t: script.Table) usize {
    return switch (t) {
        .flag => script.MAX_FLAGS,
        .counter => script.MAX_COUNTERS,
        .timer => script.MAX_TIMERS,
    };
}

const COND_WORDS = std.EnumArray(script.CondKind, []const u8).init(.{
    .always = "always",
    .never = "never",
    .flag = "flag",
    .counter = "counter",
    .timer = "timer",
    .elapsed = "turns passed",
    .region = "hero in region",
    .near = "hero near folk",
    .talked = "has heard",
    .deaths = "deaths of",
    .alive = "alive here",
});
const CMP_WORDS = std.EnumArray(script.Cmp, []const u8).init(.{ .lt = "under", .le = "at most", .eq = "exactly", .ge = "at least", .gt = "over" });

fn condKindOk(m: *const Script, k: script.CondKind) bool {
    return switch (k) {
        .near => m.folk_n > 0,
        .talked => m.dialog_n > 0,
        else => true,
    };
}

fn fitCond(ed: *editor.Editor, c: *script.Cond) void {
    const m = &ed.map.script;
    while (!condKindOk(m, c.kind)) c.kind = cycle(script.CondKind, c.kind, 1);
    if (script.condTable(c.kind)) |t| {
        if (m.names(t).len == 0) c.slot = m.coin(t) orelse 0 else c.slot = @min(c.slot, @as(u8, @intCast(m.names(t).len - 1)));
    }
    switch (c.kind) {
        .near => {
            c.slot = @min(c.slot, m.folk_n - 1);
            c.n = std.math.clamp(c.n, 0, script.NEAR_MAX);
            if (c.n == 0) c.n = 2;
        },
        .talked => c.slot = @min(c.slot, m.dialog_n - 1),
        .region => {
            c.node = @intCast(ed.node);
            if (ed.selection) |b| {
                c.from = b.lo;
                c.to = b.hi.sub(.{ .x = 1, .y = 1 });
            }
        },
        else => {},
    }
}

fn condRow(ed: *editor.Editor, g: *game.Game, x: i32, y: i32, w: i32, c: *script.Cond) void {
    const m = &ed.map.script;
    var buf: [widgets.LINE]u8 = undefined;
    const kw = std.math.clamp(@divTrunc(w, 3), 150, 200);
    const kind_by = stepper(ed, g, raster.rect(x, y, kw, ROW), COND_WORDS.get(c.kind), true, "What has to hold");
    if (kind_by != 0) {
        var k = cycle(script.CondKind, c.kind, kind_by);
        while (!condKindOk(m, k)) k = cycle(script.CondKind, k, kind_by);
        if (k != c.kind) {
            c.* = .{ .kind = k };
            fitCond(ed, c);
            ed.bank();
        }
    }
    const fx = x + kw + GAP;
    const fw = w - kw - GAP;
    var lay = Lay{ .x = fx, .y = y };
    switch (c.kind) {
        .always, .never => {},
        .flag, .timer => {
            const ws = split(fw, &.{ 3, 2 }, &.{ 260, 160 });
            tableStep(ed, g, lay.take(ws[0]), script.condTable(c.kind).?, &c.slot);
            const words_ = if (c.kind == .flag) [2][]const u8{ "is off", "is on" } else [2][]const u8{ "is running", "has run out" };
            if (button(ed, g, lay.take(ws[1]), std.fmt.bufPrintZ(&buf, "{s}", .{words_[@intFromBool(c.on)]}) catch "", false, true, "Which way it has to be")) {
                c.on = !c.on;
                ed.bank();
            }
        },
        .counter => {
            const ws = split(fw, &.{ 4, 3, 3 }, &.{ 260, 150, 150 });
            tableStep(ed, g, lay.take(ws[0]), .counter, &c.slot);
            cmpStep(ed, g, lay.take(ws[1]), &c.cmp);
            numberStep(ed, g, lay.take(ws[2]), &c.n, -script.NUMBER_MAX, script.NUMBER_MAX, "", "The number it is held to");
        },
        .elapsed => {
            const ws = split(fw, &.{ 1, 1 }, &.{ 150, 180 });
            cmpStep(ed, g, lay.take(ws[0]), &c.cmp);
            numberStep(ed, g, lay.take(ws[1]), &c.n, 0, script.NUMBER_MAX, " turns", "Spent turns since the run began");
        },
        .region => {
            const ws = split(fw, &.{ 3, 2 }, &.{ 400, 200 });
            caption(g, fx, y, ws[0], std.fmt.bufPrint(&buf, "node {d}: {d},{d} to {d},{d}", .{ c.node, c.from.x, c.from.y, c.to.x, c.to.y }) catch "", look.TEXT);
            _ = lay.take(ws[0]);
            if (button(ed, g, lay.take(ws[1]), "From selection", false, ed.selection != null, "This node and the cells selected on it (" ++ Desk.SHAPES_CAPTION ++ ")")) {
                fitCond(ed, c);
                ed.bank();
            }
        },
        .near => {
            const ws = split(fw, &.{ 3, 2 }, &.{ 260, 170 });
            const by = stepper(ed, g, lay.take(ws[0]), m.folk[c.slot].called(), m.folk_n > 1, "Which folk");
            if (by != 0) {
                c.slot = @intCast(@mod(@as(i32, c.slot) + by, @as(i32, m.folk_n)));
                ed.bank();
            }
            numberStep(ed, g, lay.take(ws[1]), &c.n, 0, script.NEAR_MAX, " cells", "How near, in steps either way");
        },
        .talked => dialogStep(ed, g, raster.rect(fx, y, @min(fw, 260), ROW), &c.slot),
        .deaths, .alive => {
            const ws = split(fw, &.{ 4, 3, 3 }, &.{ 220, 150, 150 });
            const by = stepper(ed, g, lay.take(ws[0]), actor.row(c.foe).name, true, "Which foe; a slime counts its halves");
            if (by != 0) {
                const at = std.mem.indexOfScalar(actor.Kind, &actor.FOES, c.foe) orelse 0;
                c.foe = actor.FOES[@intCast(@mod(@as(i32, @intCast(at)) + by, @as(i32, actor.FOES.len)))];
                ed.bank();
            }
            cmpStep(ed, g, lay.take(ws[1]), &c.cmp);
            numberStep(ed, g, lay.take(ws[2]), &c.n, 0, script.NUMBER_MAX, "", "How many");
        },
    }
}

fn cmpStep(ed: *editor.Editor, g: *game.Game, r: rl.Rectangle, cmp: *script.Cmp) void {
    const by = stepper(ed, g, r, CMP_WORDS.get(cmp.*), true, "How the two are compared");
    if (by == 0) return;
    cmp.* = cycle(script.Cmp, cmp.*, by);
    ed.bank();
}

fn drawScript(ed: *editor.Editor, g: *game.Game) void {
    const s = &ed.plot;
    const m = &ed.map.script;
    if (s.trigger) |t| if (t >= m.trigger_n) {
        s.trigger = null;
    };
    const f = frameOf(ed, g, "Script");
    const lw = f.listW();
    var buf: [widgets.LINE]u8 = undefined;
    s.list = raster.rect(f.x, f.y, lw, f.bottom - f.y);
    const list = Scroll.begin(ed, s.list, &s.list_top, &s.list_most);
    var y = list.y0();
    heading(g, f.x, y, lw, std.fmt.bufPrint(&buf, "Triggers {d}/{d}", .{ m.trigger_n, script.MAX_TRIGGERS }) catch "");
    if (button(ed, g, raster.rect(f.x + lw - GAP - 90, y, 90, ROW), "+ New", false, m.trigger_n < script.MAX_TRIGGERS, "A trigger that always holds and does nothing yet")) {
        if (m.addTrigger()) |t| {
            ed.bank();
            s.trigger = t;
            s.detail_top = 0;
        }
    }
    y += STEP;
    for (m.triggers(), 0..) |*t, i| {
        const label = std.fmt.bufPrintZ(&buf, "{s}{s}", .{ t.name.text(), if (t.parked) "  (parked)" else "" }) catch "";
        if (button(ed, g, widgets.row(f.x, y, lw - GAP), label, if (s.trigger) |at| at == i else false, true, "When it fires and what it does")) {
            s.trigger = @intCast(i);
            s.detail_top = 0;
        }
        y += STEP;
    }
    inline for (comptime std.enums.values(script.Table)) |t| {
        y += GAP;
        const all = m.names(t);
        heading(g, f.x, y, lw, std.fmt.bufPrint(&buf, "{s}s {d}/{d}", .{ comptime menu.capital(@tagName(t)), all.len, tableMost(t) }) catch "");
        if (button(ed, g, raster.rect(f.x + lw - GAP - 50, y, 50, ROW), "+", false, all.len < tableMost(t), "A new " ++ @tagName(t) ++ ", named for its kind")) {
            if (m.coin(t)) |_| ed.bank();
        }
        y += STEP;
        var i: u8 = 0;
        while (i < m.names(t).len) : (i += 1) {
            words(ed, g, widgets.row(f.x, y, lw - 2 * GAP - DROP_W), .{ .table = .{ .t = t, .i = i } }, "");
            const users = m.tableUsers(t, i);
            if (button(ed, g, raster.rect(f.x + lw - GAP - DROP_W, y, DROP_W, ROW), "x", false, users == 0, if (users == 0) "Remove it" else "Still named by a condition or action")) {
                if (m.undeclare(t, i)) ed.bank();
                break;
            }
            y += STEP;
        }
    }
    list.end(ed, y);
    const rx = f.x + lw + PAD;
    const rw = f.x + f.w - rx;
    rl.drawRectangle(rx - @divTrunc(PAD, 2), f.y, 1, f.bottom - f.y, look.EDGE);
    const ti = s.trigger orelse return caption(g, rx, f.y, rw, "Pick a trigger: when every condition holds after a turn, its actions run in order", look.DIM);
    s.detail = raster.rect(rx, f.y, rw, f.bottom - f.y);
    const area = Scroll.begin(ed, s.detail, &s.detail_top, &s.detail_most);
    const end = drawTrigger(ed, g, ti, rx, area.y0(), rw - PAD);
    area.end(ed, end);
}

fn drawTrigger(ed: *editor.Editor, g: *game.Game, ti: u8, x: i32, top: i32, w: i32) i32 {
    const m = &ed.map.script;
    const t = &m.trigger[ti];
    var buf: [widgets.LINE]u8 = undefined;
    var y = top;
    caption(g, x, y, LABEL_W, "Trigger", look.TEXT);
    words(ed, g, widgets.row(x + LABEL_W, y, w - LABEL_W - 220), .{ .trigger = ti }, "");
    if (button(ed, g, raster.rect(x + w - 210, y, 210, ROW), "Delete trigger", false, true, "Throw it away")) {
        m.dropTrigger(ti);
        ed.bank();
        ed.plot.trigger = null;
        return y + STEP;
    }
    y += STEP;
    if (button(ed, g, raster.rect(x + LABEL_W, y, 160, ROW), if (t.once) "Fires once" else "Repeats", false, true, "Once, or every turn its conditions hold")) {
        t.once = !t.once;
        ed.bank();
    }
    if (button(ed, g, raster.rect(x + LABEL_W + 160 + GAP, y, 160, ROW), if (t.parked) "Parked" else "Live", t.parked, true, "A parked trigger stays in the map and never runs")) {
        t.parked = !t.parked;
        ed.bank();
    }
    caption(g, x + LABEL_W + 320 + 3 * GAP, y, 90, "priority", look.DIM);
    var pri: i32 = t.priority;
    numberStep(ed, g, raster.rect(x + LABEL_W + 410 + 3 * GAP, y, 140, ROW), &pri, -script.PRIORITY_MAX, script.PRIORITY_MAX, "", "Higher runs first when two are ready on the same turn");
    t.priority = @intCast(pri);
    y += STEP + GAP;
    heading(g, x, y, w, std.fmt.bufPrint(&buf, "When every one holds {d}/{d}", .{ t.cond_n, script.MAX_CONDS }) catch "");
    if (button(ed, g, raster.rect(x + w - 160, y, 160, ROW), "+ Condition", false, t.cond_n < script.MAX_CONDS, "Another that has to hold; with none it never fires")) {
        t.cond[t.cond_n] = .{ .kind = .always };
        t.cond_n += 1;
        ed.bank();
    }
    y += STEP;
    if (t.cond_n == 0) {
        caption(g, x + LABEL_W, y, w - LABEL_W, "No conditions: it never fires", look.EDIT_WARN);
        y += STEP;
    }
    var c: u8 = 0;
    while (c < t.cond_n) : (c += 1) {
        condRow(ed, g, x + LABEL_W, y, w - LABEL_W - DROP_W - GAP, &t.cond[c]);
        if (button(ed, g, raster.rect(x + w - DROP_W, y, DROP_W, ROW), "x", false, true, "Take this condition away")) {
            script.cut(script.Cond, &t.cond, &t.cond_n, c);
            ed.bank();
            break;
        }
        y += STEP;
    }
    y += GAP;
    heading(g, x, y, w, "Then, in order");
    y += STEP;
    y = actRows(ed, g, x, x, y, w, "do", t.act_n, script.MAX_ACTS, .{ .trigger = .{ .t = ti, .a = 0 } });
    return y;
}

test "a folk's name gives its dialog a name the map reads back" {
    var buf: [script.NAME_MAX]u8 = undefined;
    try std.testing.expectEqualStrings("old_wenna", stemOf(&buf, "Old Wenna!"));
    try std.testing.expectEqualStrings("", stemOf(&buf, "  "));
    try std.testing.expect(script.token(stemOf(&buf, "The Hunter of the Long Road")));
    var s = Script{};
    _ = s.addDialog("old_wenna").?;
    try std.testing.expectEqualStrings("dialog1", s.dialog[s.addDialog("old_wenna").?].name.text());
}
